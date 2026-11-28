/* SPDX-License-Identifier: GPL-3.0-or-later
 * Drawing contexts, drawn by Cairo. A Core Graphics context has its origin
 * at the bottom left with y going up; Cairo's goes down from the top left,
 * so each context keeps a base transform between the two, and
 * CGContextGetCTM reports the transform without it, as a Mac does.
 *
 * Bitmap contexts draw straight into the caller's memory when its layout
 * matches Cairo's (32-bit premultiplied ARGB in host order, which on Intel
 * is kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, or
 * the same with the alpha byte skipped, or 8-bit alpha only). Other
 * layouts, such as RGBA (kCGImageAlphaPremultipliedLast) and 8-bit grey,
 * are drawn in a Cairo copy and converted after each drawing call. */
#import "GInternal.h"
#include <pthread.h>
#include <objc/runtime.h>

static void forget_pending(GContext *c);

@implementation GContext

- (void)dealloc
{
    if (pending)
        forget_pending(self);   /* its memory goes with it: nothing to write out */
    if (cr)
        cairo_destroy(cr);
    if (surface)
        cairo_surface_destroy(surface);
    if (ownsData)
        free(data);
    free(states);
    [space release];
    [cgFont release];
    [super dealloc];
}

- (NSString *)description { return [NSString stringWithFormat:@"<CGContext %p>", self]; }

@end

/* ---- making contexts ----------------------------------------------------------------- */

static void init_state(GContext *c, double height)
{
    c->cap = 8;
    c->states = calloc(c->cap, sizeof *c->states);
    struct gstate *s = GSTATE(c);
    s->fill[3] = s->stroke[3] = 1;
    s->fillSpace = s->strokeSpace = GSpaceRGB();
    s->alpha = 1;
    s->antialias = YES;
    s->fontSize = 0;
    c->allowsAntialias = YES;
    c->textMatrix = CGAffineTransformIdentity;
    cairo_matrix_t base = {1, 0, 0, -1, 0, height};
    c->base = base;
    cairo_set_matrix(c->cr, &base);
    cairo_set_line_width(c->cr, 1);
    cairo_set_miter_limit(c->cr, 10);
}

/* For other parts of Ferry (AppKit will draw windows this way): a context
 * drawing on a Cairo surface of the given height. */
GContext *GContextCreateWithSurface(cairo_surface_t *surface, double height) __attribute__((visibility("default")));
GContext *GContextCreateWithSurface(cairo_surface_t *surface, double height)
{
    GContext *c = [[GContext alloc] init];
    c->surface = cairo_surface_reference(surface); /* the caller keeps its own reference */
    c->cr = cairo_create(surface);
    init_state(c, height);
    return c;
}

static CGContextRef bitmap_failed(const char *why)
{
    fflush(stdout);
    fprintf(stderr, "CGBitmapContextCreate: unsupported parameter combination (%s)\n", why);
    return NULL;
}

CGContextRef CGBitmapContextCreate(void *data, size_t width, size_t height, size_t bpc, size_t bpr,
                                   CGColorSpaceRef cgspace, uint32_t info)
{
    GColorSpace *space = (GColorSpace *)cgspace;
    uint32_t alpha = info & kCGBitmapAlphaInfoMask;
    if (!width || !height)
        return bitmap_failed("empty size");
    if (alpha == kCGImageAlphaFirst || alpha == kCGImageAlphaLast)
        return bitmap_failed("alpha that isn't premultiplied");
    if (!space && alpha != kCGImageAlphaOnly)
        return bitmap_failed("no colour space");
    CGColorSpaceModel model = space ? space->model : kCGColorSpaceModelMonochrome;
    BOOL extra = alpha != kCGImageAlphaNone && alpha != kCGImageAlphaOnly;
    size_t bpp = alpha == kCGImageAlphaOnly ? bpc : bpc * ((space ? space->ncomp : 0) + (extra ? 1 : 0));
    struct gfmt fmt;
    if (model == kCGColorSpaceModelRGB && !extra)
        return bitmap_failed("RGB without an alpha or skipped byte");
    if (!GFormatFor(bpc, bpp, model, info, &fmt))
        return bitmap_failed("Ferry draws 8 bits per component in RGB, grey or alpha only");
    if (!bpr)
        bpr = (width * fmt.bytes + 3) & ~(size_t)3;
    if (bpr < width * fmt.bytes)
        return bitmap_failed("bytes per row too small");

    GContext *c = [[GContext alloc] init];
    c->width = width, c->height = height, c->bpc = bpc, c->bpp = bpp, c->bpr = bpr, c->info = info;
    c->space = [(space ? space : GSpaceGray()) retain];
    c->fmt = fmt;
    if (data) {
        c->data = data;
    } else {
        c->data = calloc(height, bpr);
        c->ownsData = YES;
    }
    int format = fmt.alphaOnly ? CAIRO_FORMAT_A8 : fmt.a >= 0 ? CAIRO_FORMAT_ARGB32 : CAIRO_FORMAT_RGB24;
    BOOL direct = (bpr % 4 == 0) && (fmt.alphaOnly || (!fmt.gray && fmt.bytes == 4 && fmt.r == 2 && fmt.g == 1 &&
                                                       fmt.b == 0 && (fmt.a == 3 || fmt.a < 0)));
    if (direct) {
        c->surface = cairo_image_surface_create_for_data(c->data, format, (int)width, (int)height, (int)bpr);
    } else {
        c->surface = cairo_image_surface_create(format, (int)width, (int)height);
        c->shadow = YES;
    }
    if (cairo_surface_status(c->surface)) {
        [c release];
        return bitmap_failed("Cairo couldn't make the surface");
    }
    c->cr = cairo_create(c->surface);
    init_state(c, height);
    return (CGContextRef)c;
}

/* the contexts whose drawing waits to be written out: main thread only */
static GContext **pending_list;
static size_t pending_count, pending_cap;
static __thread int on_main = -1;
static BOOL main_thread(void)
{
    if (on_main < 0)
        on_main = pthread_main_np() != 0;
    return on_main;
}

static void load_shadow(GContext *c)
{
    uint8_t *dst = cairo_image_surface_get_data(c->surface);
    int stride = cairo_image_surface_get_stride(c->surface);
    for (size_t y = 0; y < c->height; y++) {
        const uint8_t *src = (const uint8_t *)c->data + y * c->bpr;
        if (c->fmt.alphaOnly)
            memcpy(dst + y * stride, src, c->width);
        else
            GToCairo(&c->fmt, src, (uint32_t *)(dst + y * stride), c->width);
    }
}

static void write_shadow(GContext *c)
{
    const uint8_t *src = cairo_image_surface_get_data(c->surface);
    int stride = cairo_image_surface_get_stride(c->surface);
    BOOL opaque = c->fmt.a < 0;
    for (size_t y = 0; y < c->height; y++) {
        uint8_t *dst = (uint8_t *)c->data + y * c->bpr;
        if (c->fmt.alphaOnly)
            memcpy(dst, src + y * stride, c->width);
        else
            GFromCairo(&c->fmt, (const uint32_t *)(src + y * stride), dst, c->width, opaque);
    }
}

void GContextWillDraw(GContext *c)
{
    if (!c->data)
        return;
    if (c->shadow && c->shadowLoaded)
        return;   /* already holds the pixels, with the drawing since */
    cairo_surface_flush(c->surface);
    if (c->shadow)
        load_shadow(c);
    cairo_surface_mark_dirty(c->surface);
    c->shadowLoaded = YES;
}

/* Only after GContextWillDraw: otherwise the caller's pixels are already
 * current, and the shadow surface may not be. */
void GContextDidDraw(GContext *c)
{
    if (!c->data)
        return;
    cairo_surface_flush(c->surface);
    if (!c->shadow || !c->shadowLoaded)
        return;
    c->shadowDirty = YES;
    if (c->ownsData && main_thread()) {
        if (!c->pending) {
            if (pending_count == pending_cap) {
                pending_cap = pending_cap ? pending_cap * 2 : 16;
                pending_list = realloc(pending_list, pending_cap * sizeof *pending_list);
            }
            pending_list[pending_count++] = c;
            c->pending = YES;
        }
        return;
    }
    GContextSync(c);
}

void GContextSync(GContext *c)
{
    if (!c || !c->data || !c->shadow || !c->shadowLoaded)
        return;
    cairo_surface_flush(c->surface);
    if (c->shadowDirty)
        write_shadow(c);
    c->shadowDirty = NO;
    c->shadowLoaded = NO;
}

void GContextSyncAll(void)
{
    if (!pending_count || !main_thread())
        return;
    for (size_t i = 0; i < pending_count; i++) {
        GContextSync(pending_list[i]);
        pending_list[i]->pending = NO;
    }
    pending_count = 0;
}

static void forget_pending(GContext *c)
{
    for (size_t i = 0; i < pending_count; i++)
        if (pending_list[i] == c) {
            pending_list[i] = pending_list[--pending_count];
            break;
        }
    c->pending = NO;
}

/* Writes out the waiting drawing of each context whose memory overlaps
 * bytes: an image made on that memory is about to be read. */
void GContextSyncBytes(const void *bytes, size_t length)
{
    if (!pending_count || !bytes || !main_thread())
        return;
    for (size_t i = 0; i < pending_count;) {
        GContext *c = pending_list[i];
        const uint8_t *a = c->data, *b = bytes;
        if (a < b + length && b < a + c->bpr * c->height) {
            GContextSync(c);
            forget_pending(c);
        } else {
            i++;
        }
    }
}

#define CTX ((GContext *)c)
#define CR (CTX->cr)

void *CGBitmapContextGetData(CGContextRef c)
{
    if (!c)
        return NULL;
    GContextSync(CTX);   /* the caller is about to read or write the pixels */
    return CTX->data;
}
size_t CGBitmapContextGetWidth(CGContextRef c) { return c ? CTX->width : 0; }
size_t CGBitmapContextGetHeight(CGContextRef c) { return c ? CTX->height : 0; }
size_t CGBitmapContextGetBitsPerComponent(CGContextRef c) { return c ? CTX->bpc : 0; }
size_t CGBitmapContextGetBitsPerPixel(CGContextRef c) { return c ? CTX->bpp : 0; }
size_t CGBitmapContextGetBytesPerRow(CGContextRef c) { return c ? CTX->bpr : 0; }
CGColorSpaceRef CGBitmapContextGetColorSpace(CGContextRef c) { return c ? (CGColorSpaceRef)CTX->space : NULL; }
CGImageAlphaInfo CGBitmapContextGetAlphaInfo(CGContextRef c)
{
    return c ? (CGImageAlphaInfo)(CTX->info & kCGBitmapAlphaInfoMask) : kCGImageAlphaNone;
}
CGBitmapInfo CGBitmapContextGetBitmapInfo(CGContextRef c) { return c ? (CGBitmapInfo)CTX->info : 0; }

CGImageRef CGBitmapContextCreateImage(CGContextRef c)
{
    if (!c || !CTX->data)
        return NULL;
    GContextSync(CTX);
    CFDataRef copy = (CFDataRef)[[NSData alloc] initWithBytes:CTX->data length:CTX->bpr * CTX->height];
    CGDataProviderRef p = CGDataProviderCreateWithCFData(copy);
    CFRelease(copy);
    CGImageRef im = CGImageCreate(CTX->width, CTX->height, CTX->bpc, CTX->bpp, CTX->bpr, (CGColorSpaceRef)CTX->space,
                                  CTX->info, p, NULL, true, kCGRenderingIntentDefault);
    CGDataProviderRelease(p);
    return im;
}

CGContextRef CGContextRetain(CGContextRef c) { return (CGContextRef)[OBJ(c) retain]; }
void CGContextRelease(CGContextRef c) { [OBJ(c) release]; }
CFTypeID CGContextGetTypeID(void) { return (CFTypeID)[GContext class]; }
void CGContextFlush(CGContextRef c) { GContextSync(CTX); }
void CGContextSynchronize(CGContextRef c) {}

/* ---- graphics state ------------------------------------------------------------------ */

void CGContextSaveGState(CGContextRef c)
{
    if (CTX->depth + 1 == CTX->cap) {
        CTX->cap *= 2;
        CTX->states = realloc(CTX->states, CTX->cap * sizeof *CTX->states);
    }
    CTX->states[CTX->depth + 1] = CTX->states[CTX->depth];
    CTX->depth++;
    cairo_save(CR);
}

void CGContextRestoreGState(CGContextRef c)
{
    if (!CTX->depth)
        return;
    CTX->depth--;
    cairo_restore(CR);
}

void CGContextConcatCTM(CGContextRef c, CGAffineTransform t)
{
    cairo_matrix_t m = GMatrix(t);
    cairo_transform(CR, &m);
}

void CGContextScaleCTM(CGContextRef c, CGFloat sx, CGFloat sy)
{
    CGContextConcatCTM(c, CGAffineTransformMakeScale(sx, sy));
}

void CGContextTranslateCTM(CGContextRef c, CGFloat tx, CGFloat ty)
{
    CGContextConcatCTM(c, CGAffineTransformMakeTranslation(tx, ty));
}

void CGContextRotateCTM(CGContextRef c, CGFloat angle) { CGContextConcatCTM(c, CGAffineTransformMakeRotation(angle)); }

CGAffineTransform CGContextGetCTM(CGContextRef c)
{
    cairo_matrix_t m, inv = CTX->base, out;
    cairo_get_matrix(CR, &m);
    cairo_matrix_invert(&inv);
    cairo_matrix_multiply(&out, &m, &inv);
    return GTransform(out);
}

CGAffineTransform CGContextGetUserSpaceToDeviceSpaceTransform(CGContextRef c) { return CGContextGetCTM(c); }

CGPoint CGContextConvertPointToDeviceSpace(CGContextRef c, CGPoint p)
{
    return CGPointApplyAffineTransform(p, CGContextGetCTM(c));
}

CGPoint CGContextConvertPointToUserSpace(CGContextRef c, CGPoint p)
{
    return CGPointApplyAffineTransform(p, CGAffineTransformInvert(CGContextGetCTM(c)));
}

CGSize CGContextConvertSizeToDeviceSpace(CGContextRef c, CGSize s)
{
    return CGSizeApplyAffineTransform(s, CGContextGetCTM(c));
}

CGSize CGContextConvertSizeToUserSpace(CGContextRef c, CGSize s)
{
    return CGSizeApplyAffineTransform(s, CGAffineTransformInvert(CGContextGetCTM(c)));
}

CGRect CGContextConvertRectToDeviceSpace(CGContextRef c, CGRect r)
{
    return CGRectApplyAffineTransform(r, CGContextGetCTM(c));
}

CGRect CGContextConvertRectToUserSpace(CGContextRef c, CGRect r)
{
    return CGRectApplyAffineTransform(r, CGAffineTransformInvert(CGContextGetCTM(c)));
}

void CGContextSetLineWidth(CGContextRef c, CGFloat width) { cairo_set_line_width(CR, width); }
void CGContextSetLineCap(CGContextRef c, CGLineCap cap) { cairo_set_line_cap(CR, cap); }
void CGContextSetLineJoin(CGContextRef c, CGLineJoin join) { cairo_set_line_join(CR, join); }
void CGContextSetMiterLimit(CGContextRef c, CGFloat limit) { cairo_set_miter_limit(CR, limit); }
void CGContextSetFlatness(CGContextRef c, CGFloat flatness) {}

void CGContextSetLineDash(CGContextRef c, CGFloat phase, const CGFloat *lengths, size_t count)
{
    cairo_set_dash(CR, lengths, lengths ? (int)count : 0, phase);
}

void CGContextSetAlpha(CGContextRef c, CGFloat alpha) { GSTATE(CTX)->alpha = fmax(0, fmin(1, alpha)); }

void CGContextSetBlendMode(CGContextRef c, CGBlendMode mode)
{
    static const int ops[] = {
        [kCGBlendModeNormal] = CAIRO_OPERATOR_OVER,
        [kCGBlendModeMultiply] = CAIRO_OPERATOR_MULTIPLY,
        [kCGBlendModeScreen] = CAIRO_OPERATOR_SCREEN,
        [kCGBlendModeOverlay] = CAIRO_OPERATOR_OVERLAY,
        [kCGBlendModeDarken] = CAIRO_OPERATOR_DARKEN,
        [kCGBlendModeLighten] = CAIRO_OPERATOR_LIGHTEN,
        [kCGBlendModeColorDodge] = CAIRO_OPERATOR_COLOR_DODGE,
        [kCGBlendModeColorBurn] = CAIRO_OPERATOR_COLOR_BURN,
        [kCGBlendModeSoftLight] = CAIRO_OPERATOR_SOFT_LIGHT,
        [kCGBlendModeHardLight] = CAIRO_OPERATOR_HARD_LIGHT,
        [kCGBlendModeDifference] = CAIRO_OPERATOR_DIFFERENCE,
        [kCGBlendModeExclusion] = CAIRO_OPERATOR_EXCLUSION,
        [kCGBlendModeHue] = CAIRO_OPERATOR_HSL_HUE,
        [kCGBlendModeSaturation] = CAIRO_OPERATOR_HSL_SATURATION,
        [kCGBlendModeColor] = CAIRO_OPERATOR_HSL_COLOR,
        [kCGBlendModeLuminosity] = CAIRO_OPERATOR_HSL_LUMINOSITY,
        [kCGBlendModeClear] = CAIRO_OPERATOR_CLEAR,
        [kCGBlendModeCopy] = CAIRO_OPERATOR_SOURCE,
        [kCGBlendModeSourceIn] = CAIRO_OPERATOR_IN,
        [kCGBlendModeSourceOut] = CAIRO_OPERATOR_OUT,
        [kCGBlendModeSourceAtop] = CAIRO_OPERATOR_ATOP,
        [kCGBlendModeDestinationOver] = CAIRO_OPERATOR_DEST_OVER,
        [kCGBlendModeDestinationIn] = CAIRO_OPERATOR_DEST_IN,
        [kCGBlendModeDestinationOut] = CAIRO_OPERATOR_DEST_OUT,
        [kCGBlendModeDestinationAtop] = CAIRO_OPERATOR_DEST_ATOP,
        [kCGBlendModeXOR] = CAIRO_OPERATOR_XOR,
        [kCGBlendModePlusDarker] = CAIRO_OPERATOR_OVER,
        [kCGBlendModePlusLighter] = CAIRO_OPERATOR_ADD,
    };
    if ((unsigned)mode >= sizeof ops / sizeof ops[0])
        return;
    if (mode == kCGBlendModePlusDarker)
        GWarnOnce("the plus-darker blend mode");
    cairo_set_operator(CR, ops[mode]);
}

static void update_antialias(GContext *c)
{
    cairo_set_antialias(c->cr, GSTATE(c)->antialias && c->allowsAntialias ? CAIRO_ANTIALIAS_DEFAULT
                                                                          : CAIRO_ANTIALIAS_NONE);
}

void CGContextSetShouldAntialias(CGContextRef c, bool should)
{
    GSTATE(CTX)->antialias = should;
    update_antialias(CTX);
}

void CGContextSetAllowsAntialiasing(CGContextRef c, bool allows)
{
    CTX->allowsAntialias = allows;
    update_antialias(CTX);
}

void CGContextSetShouldSmoothFonts(CGContextRef c, bool should) {}

/* Whether the user turned font smoothing off for the whole system: a
 * private call that Chromium declares in its own open source and asks
 * before it draws text (freemac 1.266, Obsidian). freemac smooths fonts. */
bool CGFontRenderingGetFontSmoothingDisabled(void) { return false; }
void CGContextSetAllowsFontSmoothing(CGContextRef c, bool allows) {}
/* A context's font smoothing style, which programs such as MacVim set to a
 * lighter one while they draw text and set back after (freemac 1.NEXT).
 * freemac smooths fonts one way, so the style is kept and changes nothing. */
static char smoothing_key;
int CGContextGetFontSmoothingStyle(CGContextRef c)
{
    return c ? [objc_getAssociatedObject((id)c, &smoothing_key) intValue] : 0;
}
void CGContextSetFontSmoothingStyle(CGContextRef c, int style)
{
    if (c)
        objc_setAssociatedObject((id)c, &smoothing_key, @(style), OBJC_ASSOCIATION_RETAIN);
}
void CGContextSetShouldSubpixelPositionFonts(CGContextRef c, bool should) {}
void CGContextSetAllowsFontSubpixelPositioning(CGContextRef c, bool allows) {}
/* Whether glyphs are drawn at whole fractions of a pixel only; Cairo places
 * them where they are asked to go (freemac 1.266, Obsidian). */
void CGContextSetShouldSubpixelQuantizeFonts(CGContextRef c, bool should) {}
void CGContextSetAllowsFontSubpixelQuantization(CGContextRef c, bool allows) {}

void CGContextSetInterpolationQuality(CGContextRef c, CGInterpolationQuality q) { GSTATE(CTX)->interpolation = q; }
CGInterpolationQuality CGContextGetInterpolationQuality(CGContextRef c) { return GSTATE(CTX)->interpolation; }

/* ---- shadows ---------------------------------------------------------------------------
 * A shadow is set in base space (its offset isn't changed by the current
 * transform, and a positive height moves it up) and is kept with the rest of
 * the graphics state. While one is set, each drawing call draws into a
 * group of its own; the group's coverage, moved by the offset and blurred,
 * is painted in the shadow's colour, then the group itself on top, and the
 * two go onto the context together with the blend mode in force. The blur
 * is close to a Gaussian whose standard deviation is half the blur value
 * (three box blurs). Groups that aren't images (a PDF being printed) are
 * painted without their shadow. */

void CGContextSetShadowWithColor(CGContextRef c, CGSize offset, CGFloat blur, CGColorRef color)
{
    struct gstate *s = GSTATE(CTX);
    s->shadowOffset = offset;
    s->shadowBlur = blur > 0 ? blur : 0;
    if (color)
        memcpy(s->shadowColor, ((GColor *)color)->rgba, sizeof s->shadowColor);
    else
        memset(s->shadowColor, 0, sizeof s->shadowColor);   /* NULL turns shadows off */
}

/* black at a third, as Apple documents */
void CGContextSetShadow(CGContextRef c, CGSize offset, CGFloat blur)
{
    GColor *black = GColorNew(GSpaceRGB(), (CGFloat[]){0, 0, 0, 1.0 / 3});
    CGContextSetShadowWithColor(c, offset, blur, (CGColorRef)black);
    [black release];
}

/* The sizes of three box blurs that together come close to a Gaussian of
 * standard deviation sigma (each an odd width). */
static void box_sizes(double sigma, int sizes[3])
{
    double ideal = sqrt(12 * sigma * sigma / 3 + 1);
    int wl = (int)floor(ideal);
    if (wl % 2 == 0)
        wl--;
    int wu = wl + 2;
    double m = (12 * sigma * sigma - 3 * wl * wl - 12 * wl - 9) / (-4.0 * wl - 4);
    int mm = (int)lround(m);
    for (int i = 0; i < 3; i++)
        sizes[i] = i < mm ? wl : wu;
}

/* One box blur of radius r along n values spaced step apart, from src to dst. */
static void box_pass(const float *src, float *dst, int n, int step, int r)
{
    double sum = 0, w = 2 * r + 1;
    for (int i = 0; i < r && i < n; i++)
        sum += src[i * step];
    for (int i = 0; i < n; i++) {
        if (i + r < n)
            sum += src[(i + r) * step];
        if (i - r - 1 >= 0)
            sum -= src[(i - r - 1) * step];
        dst[i * step] = (float)(sum / w);
    }
}

/* The shadow's coverage for a group's pixels: an alpha-only image of the
 * group's size and place, or NULL when nothing in the group casts one. */
static cairo_surface_t *shadow_mask(GContext *c, cairo_surface_t *group, const struct gstate *s)
{
    cairo_surface_flush(group);
    int w = cairo_image_surface_get_width(group), h = cairo_image_surface_get_height(group);
    int format = cairo_image_surface_get_format(group);
    if (w <= 0 || h <= 0 || (format != CAIRO_FORMAT_ARGB32 && format != CAIRO_FORMAT_A8))
        return NULL;
    const uint8_t *px = cairo_image_surface_get_data(group);
    int stride = cairo_image_surface_get_stride(group);
#define ALPHA(x, y) (format == CAIRO_FORMAT_A8 ? px[(y) * stride + (x)] : ((const uint32_t *)(px + (y) * stride))[x] >> 24)
    int x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
            if (ALPHA(x, y)) {
                if (x < x0) x0 = x;
                if (x > x1) x1 = x;
                if (y < y0) y0 = y;
                if (y > y1) y1 = y;
            }
    if (x1 < 0)
        return NULL;
    double sx = 1, sy = 1;
    cairo_surface_get_device_scale(group, &sx, &sy);
    /* the offset from base space to Cairo's device space, then to pixels */
    double dx = (c->base.xx * s->shadowOffset.width + c->base.xy * s->shadowOffset.height) * sx;
    double dy = (c->base.yx * s->shadowOffset.width + c->base.yy * s->shadowOffset.height) * sy;
    int ox = (int)lround(dx), oy = (int)lround(dy);
    int sizes[3] = {1, 1, 1};
    int reach = 0;
    double sigma = s->shadowBlur / 2 * fmax(sx, sy);
    if (sigma > 0.2) {
        box_sizes(sigma, sizes);
        for (int i = 0; i < 3; i++)
            reach += (sizes[i] - 1) / 2;
    }
    int tx0 = x0 + ox - reach, tx1 = x1 + ox + reach + 1, ty0 = y0 + oy - reach, ty1 = y1 + oy + reach + 1;
    if (tx0 < 0) tx0 = 0;
    if (ty0 < 0) ty0 = 0;
    if (tx1 > w) tx1 = w;
    if (ty1 > h) ty1 = h;
    if (tx1 <= tx0 || ty1 <= ty0)
        return NULL;
    /* the coverage, moved, over the part of the mask it can reach, with
     * room around it for the blur to spread into */
    int bw = tx1 - tx0 + 2 * reach, bh = ty1 - ty0 + 2 * reach;
    int bx0 = tx0 - reach, by0 = ty0 - reach;
    float *a = calloc((size_t)bw * bh, sizeof *a), *t = calloc((size_t)bw * bh, sizeof *t);
    for (int j = 0; j < bh; j++)
        for (int i = 0; i < bw; i++) {
            int gx = bx0 + i - ox, gy = by0 + j - oy;
            if (gx >= 0 && gx < w && gy >= 0 && gy < h)
                a[j * bw + i] = ALPHA(gx, gy) / 255.0f;
        }
#undef ALPHA
    if (reach) {
        for (int p = 0; p < 3; p++) {
            int r = (sizes[p] - 1) / 2;
            for (int j = 0; j < bh; j++)
                box_pass(a + j * bw, t + j * bw, bw, 1, r);
            for (int i = 0; i < bw; i++)
                box_pass(t + i, a + i, bh, bw, r);
        }
    }
    cairo_surface_t *mask = cairo_image_surface_create(CAIRO_FORMAT_A8, w, h);
    uint8_t *m = cairo_image_surface_get_data(mask);
    int mstride = cairo_image_surface_get_stride(mask);
    for (int y = ty0; y < ty1; y++)
        for (int x = tx0; x < tx1; x++) {
            float v = a[(y - by0) * bw + (x - bx0)];
            m[y * mstride + x] = (uint8_t)lrintf(fminf(fmaxf(v, 0), 1) * 255);
        }
    free(a);
    free(t);
    cairo_surface_mark_dirty(mask);
    double gox = 0, goy = 0;
    cairo_surface_get_device_offset(group, &gox, &goy);
    cairo_surface_set_device_scale(mask, sx, sy);
    cairo_surface_set_device_offset(mask, gox, goy);
    return mask;
}

/* Paints a group (a pattern made by cairo_pop_group) with shadow s under it,
 * both at alpha. */
static void paint_with_shadow(GContext *c, cairo_pattern_t *shape, const struct gstate *s, double alpha)
{
    cairo_t *cr = c->cr;
    cairo_surface_t *group = NULL;
    cairo_surface_t *mask = NULL;
    if (cairo_pattern_get_surface(shape, &group) == 0 && group &&
        cairo_surface_get_type(group) == CAIRO_SURFACE_TYPE_IMAGE)
        mask = shadow_mask(c, group, s);
    cairo_push_group(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    if (mask) {
        cairo_pattern_t *mp = cairo_pattern_create_for_surface(mask);
        cairo_matrix_t m;
        cairo_pattern_get_matrix(shape, &m);
        cairo_pattern_set_matrix(mp, &m);
        cairo_set_source_rgba(cr, s->shadowColor[0], s->shadowColor[1], s->shadowColor[2], s->shadowColor[3] * alpha);
        cairo_mask(cr, mp);
        cairo_pattern_destroy(mp);
        cairo_surface_destroy(mask);
    }
    if (s->shadowOnly) {
        /* a focus ring: the shadow outside the shape, none under it */
        cairo_set_operator(cr, CAIRO_OPERATOR_DEST_OUT);
        cairo_set_source(cr, shape);
        cairo_paint(cr);
    } else if (!c->shadowOnly) {
        cairo_set_source(cr, shape);
        cairo_paint_with_alpha(cr, alpha);
    }
    cairo_pop_group_to_source(cr);
    cairo_paint(cr);
}

void GContextSetShadowOnly(CGContextRef c, BOOL only) { GSTATE(CTX)->shadowOnly = only; }
void GContextSetDrawsShadowsOnly(CGContextRef c, BOOL only) { CTX->shadowOnly = only; }

BOOL GContextBeginShadow(GContext *c)
{
    if (GSTATE(c)->shadowColor[3] <= 0 && !c->shadowOnly && !GSTATE(c)->shadowOnly)
        return NO;
    /* the path is carried into the group by hand, in user space */
    cairo_path_t *path = cairo_copy_path(c->cr);
    cairo_push_group(c->cr);
    cairo_set_operator(c->cr, CAIRO_OPERATOR_OVER);
    cairo_new_path(c->cr);
    if (path) {
        cairo_append_path(c->cr, path);
        cairo_path_destroy(path);
    }
    return YES;
}

void GContextEndShadow(GContext *c, BOOL began)
{
    if (!began)
        return;
    cairo_path_t *path = cairo_copy_path(c->cr);
    cairo_pattern_t *shape = cairo_pop_group(c->cr);
    if (GSTATE(c)->shadowColor[3] > 0)
        paint_with_shadow(c, shape, GSTATE(c), 1);
    else if (!c->shadowOnly && !GSTATE(c)->shadowOnly) {
        cairo_set_source(c->cr, shape);
        cairo_paint(c->cr);
    }
    cairo_pattern_destroy(shape);
    cairo_new_path(c->cr);
    if (path) {
        cairo_append_path(c->cr, path);
        cairo_path_destroy(path);
    }
}

/* Transparency layers: what is drawn between the two calls is gathered on
 * its own (a Cairo group, which saves Cairo's state too) and composited as
 * one picture at the alpha in force when the layer began. Inside the layer
 * the alpha starts again at 1. */
void CGContextBeginTransparencyLayerWithRect(CGContextRef c, CGRect rect, CFDictionaryRef auxiliaryInfo)
{
    CGContextSaveGState(c);
    GSTATE(CTX)->alpha = 1;
    memset(GSTATE(CTX)->shadowColor, 0, sizeof GSTATE(CTX)->shadowColor);   /* the layer casts it, as a whole */
    cairo_push_group(CR);
}

void CGContextBeginTransparencyLayer(CGContextRef c, CFDictionaryRef auxiliaryInfo)
{
    CGContextBeginTransparencyLayerWithRect(c, CGRectInfinite, auxiliaryInfo);
}

void CGContextEndTransparencyLayer(CGContextRef c)
{
    if (!CTX->depth)
        return;
    const struct gstate *outer = &CTX->states[CTX->depth - 1];
    double alpha = outer->alpha;
    GContextWillDraw(CTX);
    if (outer->shadowColor[3] > 0) {
        cairo_pattern_t *layer = cairo_pop_group(CR);
        paint_with_shadow(CTX, layer, outer, alpha);
        cairo_pattern_destroy(layer);
    } else {
        cairo_pop_group_to_source(CR);
        cairo_paint_with_alpha(CR, alpha);
    }
    GContextDidDraw(CTX);
    CGContextRestoreGState(c);
}

/* ---- colours ------------------------------------------------------------------------- */

void GContextSetSource(GContext *c, const double rgba[4])
{
    cairo_set_source_rgba(c->cr, rgba[0], rgba[1], rgba[2], rgba[3] * GSTATE(c)->alpha);
}

static void set_color(double out[4], GColor *color)
{
    if (color)
        memcpy(out, color->rgba, 4 * sizeof(double));
}

void CGContextSetFillColorWithColor(CGContextRef c, CGColorRef color)
{
    set_color(GSTATE(CTX)->fill, (GColor *)color);
    if (color)
        GSTATE(CTX)->fillSpace = ((GColor *)color)->space;
}

void CGContextSetStrokeColorWithColor(CGContextRef c, CGColorRef color)
{
    set_color(GSTATE(CTX)->stroke, (GColor *)color);
    if (color)
        GSTATE(CTX)->strokeSpace = ((GColor *)color)->space;
}

static void set_components(double out[4], GColorSpace *space, const CGFloat *k)
{
    GColor *color = GColorNew(space ? space : GSpaceRGB(), k);
    set_color(out, color);
    [color release];
}

void CGContextSetFillColorSpace(CGContextRef c, CGColorSpaceRef space)
{
    GSTATE(CTX)->fillSpace = (GColorSpace *)space;
    CGFloat k[5] = {0, 0, 0, 0, 0};
    k[((GColorSpace *)space)->ncomp] = 1;
    set_components(GSTATE(CTX)->fill, (GColorSpace *)space, k);
}

void CGContextSetStrokeColorSpace(CGContextRef c, CGColorSpaceRef space)
{
    GSTATE(CTX)->strokeSpace = (GColorSpace *)space;
    CGFloat k[5] = {0, 0, 0, 0, 0};
    k[((GColorSpace *)space)->ncomp] = 1;
    set_components(GSTATE(CTX)->stroke, (GColorSpace *)space, k);
}

void CGContextSetFillColor(CGContextRef c, const CGFloat *k) { set_components(GSTATE(CTX)->fill, GSTATE(CTX)->fillSpace, k); }
void CGContextSetStrokeColor(CGContextRef c, const CGFloat *k)
{
    set_components(GSTATE(CTX)->stroke, GSTATE(CTX)->strokeSpace, k);
}

void CGContextSetGrayFillColor(CGContextRef c, CGFloat gray, CGFloat alpha)
{
    CGContextSetRGBFillColor(c, gray, gray, gray, alpha);
}

void CGContextSetGrayStrokeColor(CGContextRef c, CGFloat gray, CGFloat alpha)
{
    CGContextSetRGBStrokeColor(c, gray, gray, gray, alpha);
}

void CGContextSetRGBFillColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
    set_components(GSTATE(CTX)->fill, GSpaceRGB(), (CGFloat[]){r, g, b, a});
}

void CGContextSetRGBStrokeColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
    set_components(GSTATE(CTX)->stroke, GSpaceRGB(), (CGFloat[]){r, g, b, a});
}

void CGContextSetCMYKFillColor(CGContextRef c, CGFloat cy, CGFloat m, CGFloat y, CGFloat k, CGFloat a)
{
    set_components(GSTATE(CTX)->fill, GSpaceCMYK(), (CGFloat[]){cy, m, y, k, a});
}

void CGContextSetCMYKStrokeColor(CGContextRef c, CGFloat cy, CGFloat m, CGFloat y, CGFloat k, CGFloat a)
{
    set_components(GSTATE(CTX)->stroke, GSpaceCMYK(), (CGFloat[]){cy, m, y, k, a});
}

/* ---- the current path ------------------------------------------------------------------ */

static void cr_move(void *i, CGPoint p) { cairo_move_to(i, p.x, p.y); }
static void cr_line(void *i, CGPoint p) { cairo_line_to(i, p.x, p.y); }
static void cr_curve(void *i, CGPoint a, CGPoint b, CGPoint p) { cairo_curve_to(i, a.x, a.y, b.x, b.y, p.x, p.y); }
static void cr_close(void *i) { cairo_close_path(i); }
static BOOL cr_current(void *i, CGPoint *p)
{
    if (!cairo_has_current_point(i))
        return NO;
    cairo_get_current_point(i, &p->x, &p->y);
    return YES;
}

#define CR_SINK(name, c) struct gsink name = {cr_move, cr_line, cr_curve, cr_close, cr_current, (c)->cr}

void CGContextBeginPath(CGContextRef c) { cairo_new_path(CR); }
void CGContextMoveToPoint(CGContextRef c, CGFloat x, CGFloat y) { cairo_move_to(CR, x, y); }
void CGContextAddLineToPoint(CGContextRef c, CGFloat x, CGFloat y) { cairo_line_to(CR, x, y); }
void CGContextAddCurveToPoint(CGContextRef c, CGFloat c1x, CGFloat c1y, CGFloat c2x, CGFloat c2y, CGFloat x, CGFloat y)
{
    cairo_curve_to(CR, c1x, c1y, c2x, c2y, x, y);
}

void CGContextAddQuadCurveToPoint(CGContextRef c, CGFloat cpx, CGFloat cpy, CGFloat x, CGFloat y)
{
    CR_SINK(s, CTX);
    GSinkQuad(&s, CGPointMake(cpx, cpy), CGPointMake(x, y));
}

void CGContextClosePath(CGContextRef c) { cairo_close_path(CR); }

void CGContextAddRect(CGContextRef c, CGRect rect)
{
    CR_SINK(s, CTX);
    GSinkRect(&s, rect);
}

void CGContextAddRects(CGContextRef c, const CGRect *rects, size_t count)
{
    for (size_t i = 0; i < count; i++)
        CGContextAddRect(c, rects[i]);
}

void CGContextAddLines(CGContextRef c, const CGPoint *points, size_t count)
{
    for (size_t i = 0; i < count; i++)
        (i ? cairo_line_to : cairo_move_to)(CR, points[i].x, points[i].y);
}

void CGContextAddEllipseInRect(CGContextRef c, CGRect rect)
{
    CR_SINK(s, CTX);
    GSinkEllipse(&s, rect);
}

void CGContextAddArc(CGContextRef c, CGFloat x, CGFloat y, CGFloat radius, CGFloat startAngle, CGFloat endAngle,
                     int clockwise)
{
    CR_SINK(s, CTX);
    GSinkArc(&s, x, y, radius, startAngle, endAngle, clockwise != 0);
}

void CGContextAddArcToPoint(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat radius)
{
    CR_SINK(s, CTX);
    GSinkArcToPoint(&s, x1, y1, x2, y2, radius);
}

void CGContextAddPath(CGContextRef c, CGPathRef path)
{
    if (path)
        GPathToCairo((GPath *)path, CR);
}

bool CGContextIsPathEmpty(CGContextRef c)
{
    cairo_path_t *p = cairo_copy_path(CR);
    bool empty = !p || p->num_data == 0;
    if (p)
        cairo_path_destroy(p);
    return empty;
}

CGPoint CGContextGetPathCurrentPoint(CGContextRef c)
{
    CGPoint p = CGPointZero;
    if (cairo_has_current_point(CR))
        cairo_get_current_point(CR, &p.x, &p.y);
    return p;
}

CGRect CGContextGetPathBoundingBox(CGContextRef c)
{
    if (CGContextIsPathEmpty(c))
        return CGRectNull;
    double x0, y0, x1, y1;
    cairo_path_extents(CR, &x0, &y0, &x1, &y1);
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

CGPathRef CGContextCopyPath(CGContextRef c) { return (CGPathRef)GPathFromCairo(CR); }

bool CGContextPathContainsPoint(CGContextRef c, CGPoint p, CGPathDrawingMode mode)
{
    if (mode == kCGPathStroke)
        return cairo_in_stroke(CR, p.x, p.y);
    cairo_set_fill_rule(CR, mode == kCGPathEOFill || mode == kCGPathEOFillStroke ? CAIRO_FILL_RULE_EVEN_ODD
                                                                                  : CAIRO_FILL_RULE_WINDING);
    bool in = cairo_in_fill(CR, p.x, p.y);
    if (!in && mode != kCGPathFill && mode != kCGPathEOFill)
        in = cairo_in_stroke(CR, p.x, p.y);
    return in;
}

/* ---- painting ------------------------------------------------------------------------ */

void CGContextDrawPath(CGContextRef c, CGPathDrawingMode mode)
{
    GContextWillDraw(CTX);
    BOOL shadowed = GContextBeginShadow(CTX);
    BOOL fill = mode != kCGPathStroke, stroke = mode == kCGPathStroke || mode == kCGPathFillStroke ||
                                                mode == kCGPathEOFillStroke;
    if (fill) {
        cairo_set_fill_rule(CR, mode == kCGPathEOFill || mode == kCGPathEOFillStroke ? CAIRO_FILL_RULE_EVEN_ODD
                                                                                      : CAIRO_FILL_RULE_WINDING);
        GContextSetSource(CTX, GSTATE(CTX)->fill);
        (stroke ? cairo_fill_preserve : cairo_fill)(CR);
    }
    if (stroke) {
        GContextSetSource(CTX, GSTATE(CTX)->stroke);
        cairo_stroke(CR);
    }
    GContextEndShadow(CTX, shadowed);
    GContextDidDraw(CTX);
}

void CGContextFillPath(CGContextRef c) { CGContextDrawPath(c, kCGPathFill); }
void CGContextEOFillPath(CGContextRef c) { CGContextDrawPath(c, kCGPathEOFill); }
void CGContextStrokePath(CGContextRef c) { CGContextDrawPath(c, kCGPathStroke); }

/* Runs body with an empty path and puts the caller's path back afterwards, for
 * the calls that draw a shape of their own (CGContextFillRect and friends). */
static void with_own_path(GContext *c, void (^body)(void))
{
    cairo_path_t *saved = cairo_copy_path(c->cr);
    cairo_new_path(c->cr);
    body();
    cairo_new_path(c->cr);
    if (saved) {
        cairo_append_path(c->cr, saved);
        cairo_path_destroy(saved);
    }
}

void CGContextFillRects(CGContextRef c, const CGRect *rects, size_t count)
{
    with_own_path(CTX, ^{
        CGContextAddRects(c, rects, count);
        CGContextDrawPath(c, kCGPathFill);
    });
}

void CGContextFillRect(CGContextRef c, CGRect rect) { CGContextFillRects(c, &rect, 1); }

void CGContextStrokeRect(CGContextRef c, CGRect rect)
{
    with_own_path(CTX, ^{
        CGContextAddRect(c, rect);
        CGContextDrawPath(c, kCGPathStroke);
    });
}

void CGContextStrokeRectWithWidth(CGContextRef c, CGRect rect, CGFloat width)
{
    cairo_save(CR);
    cairo_set_line_width(CR, width);
    CGContextStrokeRect(c, rect);
    cairo_restore(CR);
}

void CGContextClearRect(CGContextRef c, CGRect rect)
{
    with_own_path(CTX, ^{
        GContextWillDraw(CTX);
        cairo_save(CR);
        cairo_set_operator(CR, CAIRO_OPERATOR_CLEAR);
        CGContextAddRect(c, rect);
        cairo_fill(CR);
        cairo_restore(CR);
        GContextDidDraw(CTX);
    });
}

void CGContextFillEllipseInRect(CGContextRef c, CGRect rect)
{
    with_own_path(CTX, ^{
        CGContextAddEllipseInRect(c, rect);
        CGContextDrawPath(c, kCGPathFill);
    });
}

void CGContextStrokeEllipseInRect(CGContextRef c, CGRect rect)
{
    with_own_path(CTX, ^{
        CGContextAddEllipseInRect(c, rect);
        CGContextDrawPath(c, kCGPathStroke);
    });
}

void CGContextStrokeLineSegments(CGContextRef c, const CGPoint *points, size_t count)
{
    with_own_path(CTX, ^{
        for (size_t i = 0; i + 1 < count; i += 2) {
            cairo_move_to(CR, points[i].x, points[i].y);
            cairo_line_to(CR, points[i + 1].x, points[i + 1].y);
        }
        CGContextDrawPath(c, kCGPathStroke);
    });
}

/* ---- clipping ------------------------------------------------------------------------- */

void CGContextClip(CGContextRef c)
{
    cairo_set_fill_rule(CR, CAIRO_FILL_RULE_WINDING);
    cairo_clip(CR);
}

void CGContextEOClip(CGContextRef c)
{
    cairo_set_fill_rule(CR, CAIRO_FILL_RULE_EVEN_ODD);
    cairo_clip(CR);
}

void CGContextClipToRects(CGContextRef c, const CGRect *rects, size_t count)
{
    with_own_path(CTX, ^{
        CGContextAddRects(c, rects, count);
        CGContextClip(c);
    });
}

void CGContextClipToRect(CGContextRef c, CGRect rect) { CGContextClipToRects(c, &rect, 1); }

/* Clipping to a mask image: Cairo clips only to paths, so drawing is clipped
 * to the mask's rectangle, and what the mask hides inside it still shows
 * (freemac 1.266). */
void CGContextClipToMask(CGContextRef c, CGRect rect, CGImageRef mask)
{
    if (mask)
        GWarnOnce("clipping to a mask image (only to its rectangle)");
    CGContextClipToRect(c, rect);
}

CGRect CGContextGetClipBoundingBox(CGContextRef c)
{
    double x0, y0, x1, y1;
    cairo_clip_extents(CR, &x0, &y0, &x1, &y1);
    if (x1 <= x0 || y1 <= y0)
        return CGRectNull;
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

/* ---- images and gradients ---------------------------------------------------------------- */

static int filter_for(GContext *c, GImage *im)
{
    CGInterpolationQuality q = GSTATE(c)->interpolation;
    if (q == kCGInterpolationNone || !im->interpolate)
        return CAIRO_FILTER_NEAREST;
    return q == kCGInterpolationHigh ? CAIRO_FILTER_BEST : CAIRO_FILTER_GOOD;
}

void CGContextDrawImage(CGContextRef c, CGRect rect, CGImageRef image)
{
    GImage *im = (GImage *)image;
    cairo_surface_t *s = im ? GImageSurface(im) : NULL;
    if (!s || CGRectIsEmpty(rect))
        return;
    rect = CGRectStandardize(rect);
    with_own_path(CTX, ^{
        GContextWillDraw(CTX);
        BOOL shadowed = GContextBeginShadow(CTX);
        cairo_save(CR);
        /* The image's first row is its top, which goes at the top of rect. */
        CGContextTranslateCTM(c, rect.origin.x, rect.origin.y + rect.size.height);
        CGContextScaleCTM(c, rect.size.width / im->width, -rect.size.height / im->height);
        cairo_pattern_t *p = cairo_pattern_create_for_surface(s);
        cairo_pattern_set_extend(p, CAIRO_EXTEND_PAD);
        cairo_pattern_set_filter(p, filter_for(CTX, im));
        cairo_rectangle(CR, 0, 0, im->width, im->height);
        cairo_clip(CR);
        if (im->mask) {
            /* an image mask paints the fill colour through it (1.263) */
            cairo_push_group(CR);
            GContextSetSource(CTX, GSTATE(CTX)->fill);
            cairo_mask(CR, p);
            cairo_pop_group_to_source(CR);
        } else {
            cairo_set_source(CR, p);
        }
        cairo_paint_with_alpha(CR, GSTATE(CTX)->alpha);
        cairo_pattern_destroy(p);
        cairo_restore(CR);
        GContextEndShadow(CTX, shadowed);
        GContextDidDraw(CTX);
    });
}

void CGContextDrawTiledImage(CGContextRef c, CGRect rect, CGImageRef image)
{
    GImage *im = (GImage *)image;
    cairo_surface_t *s = im ? GImageSurface(im) : NULL;
    if (!s || CGRectIsEmpty(rect))
        return;
    rect = CGRectStandardize(rect);
    GContextWillDraw(CTX);
    BOOL shadowed = GContextBeginShadow(CTX);
    cairo_save(CR);
    CGContextTranslateCTM(c, rect.origin.x, rect.origin.y + rect.size.height);
    CGContextScaleCTM(c, rect.size.width / im->width, -rect.size.height / im->height);
    cairo_pattern_t *p = cairo_pattern_create_for_surface(s);
    cairo_pattern_set_extend(p, CAIRO_EXTEND_REPEAT);
    cairo_pattern_set_filter(p, filter_for(CTX, im));
    cairo_set_source(CR, p);
    cairo_paint_with_alpha(CR, GSTATE(CTX)->alpha);
    cairo_pattern_destroy(p);
    cairo_restore(CR);
    GContextEndShadow(CTX, shadowed);
    GContextDidDraw(CTX);
}

static void add_stops(cairo_pattern_t *p, GGradient *g)
{
    for (size_t i = 0; i < g->count; i++)
        cairo_pattern_add_color_stop_rgba(p, g->locations[i], g->rgba[i][0], g->rgba[i][1], g->rgba[i][2],
                                          g->rgba[i][3]);
}

void CGContextDrawLinearGradient(CGContextRef c, CGGradientRef gradient, CGPoint start, CGPoint end,
                                 CGGradientDrawingOptions options)
{
    GGradient *g = (GGradient *)gradient;
    if (!g)
        return;
    CGFloat dx = end.x - start.x, dy = end.y - start.y, len = hypot(dx, dy);
    if (len == 0)
        return;
    with_own_path(CTX, ^{
        GContextWillDraw(CTX);
        BOOL shadowed = GContextBeginShadow(CTX);
        cairo_save(CR);
        /* Work along the gradient: start at the origin, end at (len, 0). Areas
         * before the start or after the end are painted only if asked for. */
        CGContextTranslateCTM(c, start.x, start.y);
        CGContextRotateCTM(c, atan2(dy, dx));
        double cx0, cy0, cx1, cy1;   /* the area that can be painted, in these coordinates */
        cairo_clip_extents(CR, &cx0, &cy0, &cx1, &cy1);
        double x0 = (options & kCGGradientDrawsBeforeStartLocation) ? fmin(cx0, 0) : 0;
        double x1 = (options & kCGGradientDrawsAfterEndLocation) ? fmax(cx1, len) : len;
        cairo_rectangle(CR, x0, cy0, x1 - x0, cy1 - cy0);
        cairo_clip(CR);
        cairo_pattern_t *p = cairo_pattern_create_linear(0, 0, len, 0);
        add_stops(p, g);
        cairo_pattern_set_extend(p, CAIRO_EXTEND_PAD);
        cairo_set_source(CR, p);
        cairo_paint_with_alpha(CR, GSTATE(CTX)->alpha);
        cairo_pattern_destroy(p);
        cairo_restore(CR);
        GContextEndShadow(CTX, shadowed);
        GContextDidDraw(CTX);
    });
}

void CGContextDrawRadialGradient(CGContextRef c, CGGradientRef gradient, CGPoint startCenter, CGFloat startRadius,
                                 CGPoint endCenter, CGFloat endRadius, CGGradientDrawingOptions options)
{
    GGradient *g = (GGradient *)gradient;
    if (!g)
        return;
    GContextWillDraw(CTX);
    BOOL shadowed = GContextBeginShadow(CTX);
    cairo_pattern_t *p =
        cairo_pattern_create_radial(startCenter.x, startCenter.y, startRadius, endCenter.x, endCenter.y, endRadius);
    add_stops(p, g);
    /* Cairo can extend both ends or neither; one end alone is drawn as both. */
    cairo_pattern_set_extend(p, options ? CAIRO_EXTEND_PAD : CAIRO_EXTEND_NONE);
    cairo_save(CR);
    cairo_set_source(CR, p);
    cairo_paint_with_alpha(CR, GSTATE(CTX)->alpha);
    cairo_restore(CR);
    cairo_pattern_destroy(p);
    GContextEndShadow(CTX, shadowed);
    GContextDidDraw(CTX);
}

/* ---- text state (Core Text draws with it) ----------------------------------------------- */

/* The text position is the translation part of the text matrix. */
void CGContextSetTextMatrix(CGContextRef c, CGAffineTransform t) { CTX->textMatrix = t; }
CGAffineTransform CGContextGetTextMatrix(CGContextRef c) { return CTX->textMatrix; }
void CGContextSetTextPosition(CGContextRef c, CGFloat x, CGFloat y)
{
    CTX->textMatrix.tx = x;
    CTX->textMatrix.ty = y;
}
CGPoint CGContextGetTextPosition(CGContextRef c) { return CGPointMake(CTX->textMatrix.tx, CTX->textMatrix.ty); }
void CGContextSetTextDrawingMode(CGContextRef c, CGTextDrawingMode mode) { GSTATE(CTX)->textMode = mode; }
void CGContextSetCharacterSpacing(CGContextRef c, CGFloat spacing) { GSTATE(CTX)->characterSpacing = spacing; }
void CGContextSetFontSize(CGContextRef c, CGFloat size) { GSTATE(CTX)->fontSize = size; }

/* The font CGContextShowGlyphsAtPositions draws with, at the font size set
 * (Apple's CGContext documentation). It is kept by the context, not saved
 * and restored with the graphics state (freemac 1.266). */
void CGContextSetFont(CGContextRef c, CGFontRef font)
{
    if (!c)
        return;
    id old = CTX->cgFont;
    CTX->cgFont = font ? [(id)font retain] : nil;
    [old release];
}

void CGContextShowGlyphsAtPositions(CGContextRef c, const CGGlyph glyphs[], const CGPoint positions[], size_t count)
{
    if (!c || !CTX->cgFont || !count)
        return;
    CTFontRef f = CTFontCreateWithGraphicsFont((CGFontRef)CTX->cgFont, GSTATE(CTX)->fontSize, NULL, NULL);
    if (!f)
        return;
    CTFontDrawGlyphs(f, glyphs, positions, count, c);
    CFRelease(f);
}

/* Glyphs from the current text position, each one advance after the last
 * (in text space); the text position moves on past them (Apple's CGContext
 * documentation; Hex Fiend draws its bytes this way, freemac 1.270). */
void CGContextShowGlyphsWithAdvances(CGContextRef c, const CGGlyph glyphs[], const CGSize advances[], size_t count)
{
    if (!c || !count)
        return;
    CGPoint *at = malloc(count * sizeof *at);
    if (!at)
        return;
    CGFloat x = 0, y = 0;
    for (size_t i = 0; i < count; i++) {
        at[i] = CGPointMake(x, y);
        x += advances[i].width;
        y += advances[i].height;
    }
    CGContextShowGlyphsAtPositions(c, glyphs, at, count);
    free(at);
    CGAffineTransform *tm = &CTX->textMatrix;
    tm->tx += tm->a * x + tm->c * y;
    tm->ty += tm->b * x + tm->d * y;
}

/* The same with the font's own advances. */
void CGContextShowGlyphs(CGContextRef c, const CGGlyph glyphs[], size_t count)
{
    if (!c || !CTX->cgFont || !count)
        return;
    CTFontRef f = CTFontCreateWithGraphicsFont((CGFontRef)CTX->cgFont, GSTATE(CTX)->fontSize, NULL, NULL);
    if (!f)
        return;
    CGSize *adv = malloc(count * sizeof *adv);
    if (adv) {
        CTFontGetAdvancesForGlyphs(f, kCTFontOrientationHorizontal, glyphs, adv, (CFIndex)count);
        CGContextShowGlyphsWithAdvances(c, glyphs, adv, count);
        free(adv);
    }
    CFRelease(f);
}

/* ---- PDF contexts and pages ---------------------------------------------------------- */

/* Ferry can't draw into a PDF yet, so it makes no PDF context; an app that
 * asks for one prints nothing (Apple's CGPDFContext documentation says it
 * returns NULL when it can't make one). A page begun on any other context
 * is that context (freemac 1.266). */
CGContextRef CGPDFContextCreate(CGDataConsumerRef consumer, const CGRect *mediaBox, CFDictionaryRef auxiliaryInfo)
{
    GWarnOnce("drawing into a PDF");
    return NULL;
}
CGContextRef CGPDFContextCreateWithURL(CFURLRef url, const CGRect *mediaBox, CFDictionaryRef auxiliaryInfo)
{
    return CGPDFContextCreate(NULL, mediaBox, auxiliaryInfo);
}
void CGPDFContextClose(CGContextRef c) {}
void CGPDFContextBeginPage(CGContextRef c, CFDictionaryRef pageInfo) {}
void CGPDFContextEndPage(CGContextRef c) {}
void CGContextBeginPage(CGContextRef c, const CGRect *mediaBox) {}
void CGContextEndPage(CGContextRef c) {}

void GContextDrawText(GContext *c, CGFloat x, CGFloat y, void (^body)(BOOL path))
{
    CGTextDrawingMode mode = GSTATE(c)->textMode;
    if (mode == kCGTextInvisible)
        return;
    GContextWillDraw(c);
    BOOL shadowed = GContextBeginShadow(c);
    cairo_t *cr = c->cr;
    cairo_save(cr);
    CGAffineTransform tm = c->textMatrix;
    CGContextConcatCTM((CGContextRef)c, tm);
    CGContextConcatCTM((CGContextRef)c, CGAffineTransformMake(1, 0, 0, -1, x, y));
    /* That is: text space at (x, y), with y flipped so glyphs stand upright. */
    BOOL fill = mode == kCGTextFill || mode == kCGTextFillStroke || mode == kCGTextFillClip ||
                mode == kCGTextFillStrokeClip;
    BOOL stroke = mode == kCGTextStroke || mode == kCGTextFillStroke || mode == kCGTextStrokeClip ||
                  mode == kCGTextFillStrokeClip;
    BOOL clip = mode >= kCGTextFillClip;
    cairo_path_t *saved = cairo_copy_path(cr);
    cairo_new_path(cr);
    cairo_move_to(cr, 0, 0);
    if (mode == kCGTextFill) {
        GContextSetSource(c, GSTATE(c)->fill);
        body(NO);
    } else {
        body(YES);
        if (fill) {
            GContextSetSource(c, GSTATE(c)->fill);
            cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING);
            cairo_fill_preserve(cr);
        }
        if (stroke) {
            GContextSetSource(c, GSTATE(c)->stroke);
            cairo_stroke_preserve(cr);
        }
    }
    cairo_new_path(cr);
    cairo_restore(cr);
    if (clip)
        GWarnOnce("clipping to text");
    if (saved) {
        cairo_append_path(cr, saved);
        cairo_path_destroy(saved);
    }
    GContextEndShadow(c, shadowed);
    GContextDidDraw(c);
}
