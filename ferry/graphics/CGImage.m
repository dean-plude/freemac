/* SPDX-License-Identifier: GPL-3.0-or-later
 * Data providers, bitmap images and gradients, and the pixel conversions
 * between a Mac program's 8-bit-per-component layouts and Cairo's (32-bit
 * words holding premultiplied alpha, red, green, blue). PNG files are read
 * by Cairo; other image formats aren't supported yet. */
#import "GInternal.h"

/* ---- pixel layouts --------------------------------------------------------------- */

BOOL GFormatFor(size_t bpc, size_t bpp, CGColorSpaceModel model, uint32_t info, struct gfmt *f)
{
    memset(f, 0, sizeof *f);
    f->r = f->g = f->b = f->a = -1;
    uint32_t alpha = info & kCGBitmapAlphaInfoMask, order = info & kCGBitmapByteOrderMask;
    if (bpc != 8 || (info & kCGBitmapFloatComponents))
        return NO;
    f->premultiplied = alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaPremultipliedLast;
    BOOL first = alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaFirst ||
                 alpha == kCGImageAlphaNoneSkipFirst;
    BOOL has_alpha = alpha != kCGImageAlphaNone && alpha != kCGImageAlphaNoneSkipFirst &&
                     alpha != kCGImageAlphaNoneSkipLast;
    if (alpha == kCGImageAlphaOnly) {
        if (bpp != 8)
            return NO;
        f->bytes = 1;
        f->a = 0;
        f->alphaOnly = YES;
        return YES;
    }
    if (model == kCGColorSpaceModelMonochrome) {
        f->gray = YES;
        if (bpp == 8 && alpha == kCGImageAlphaNone) {
            f->bytes = 1;
            f->g = 0;
            return YES;
        }
        if (bpp != 16 || alpha == kCGImageAlphaNone)
            return NO;
        f->bytes = 2;
        f->g = first ? 1 : 0;
        f->a = has_alpha ? (first ? 0 : 1) : -1;
        if (order == kCGBitmapByteOrder16Little) {
            f->g = 1 - f->g;
            if (f->a >= 0)
                f->a = 1 - f->a;
        }
        return YES;
    }
    if (model != kCGColorSpaceModelRGB)
        return NO;
    if (bpp == 24 && alpha == kCGImageAlphaNone) {
        f->bytes = 3;
        f->r = 0, f->g = 1, f->b = 2;
        return YES;
    }
    if (bpp != 32 || alpha == kCGImageAlphaNone)
        return NO;
    f->bytes = 4;
    int base = first ? 1 : 0;
    f->r = base, f->g = base + 1, f->b = base + 2;
    f->a = has_alpha ? (first ? 0 : 3) : -1;
    if (order == kCGBitmapByteOrder32Little) {
        f->r = 3 - f->r, f->g = 3 - f->g, f->b = 3 - f->b;
        if (f->a >= 0)
            f->a = 3 - f->a;
    }
    return YES;
}

static inline uint8_t mul(unsigned v, unsigned a) { return (uint8_t)((v * a + 127) / 255); }

void GToCairo(const struct gfmt *f, const uint8_t *src, uint32_t *dst, size_t width)
{
    for (size_t x = 0; x < width; x++, src += f->bytes) {
        unsigned r, g, b, a = f->a >= 0 ? src[f->a] : 255;
        if (f->alphaOnly)
            r = g = b = 0;
        else if (f->gray)
            r = g = b = src[f->g];
        else
            r = src[f->r], g = src[f->g], b = src[f->b];
        if (!f->premultiplied && a != 255 && !f->alphaOnly)
            r = mul(r, a), g = mul(g, a), b = mul(b, a);
        dst[x] = (uint32_t)a << 24 | r << 16 | g << 8 | b;
    }
}

void GFromCairo(const struct gfmt *f, const uint32_t *src, uint8_t *dst, size_t width, BOOL opaque)
{
    for (size_t x = 0; x < width; x++, dst += f->bytes) {
        uint32_t p = src[x];
        unsigned a = opaque ? 255 : p >> 24, r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
        if (!f->premultiplied && a && a != 255) {
            r = r * 255 / a, g = g * 255 / a, b = b * 255 / a;
        }
        if (f->alphaOnly) {
            dst[f->a] = (uint8_t)a;
            continue;
        }
        if (f->gray) {
            dst[f->g] = (uint8_t)((r * 299 + g * 587 + b * 114 + 500) / 1000);
        } else {
            dst[f->r] = (uint8_t)r, dst[f->g] = (uint8_t)g, dst[f->b] = (uint8_t)b;
        }
        if (f->a >= 0)
            dst[f->a] = (uint8_t)a;
        else if (f->bytes == 4) /* the skipped byte */
            dst[6 - f->r - f->g - f->b] = 255;
    }
}

/* ---- data providers ---------------------------------------------------------------- */

@interface GDataProvider () {
@public
    void *info;
    const void *bytes;
    size_t size;
    CGDataProviderReleaseDataCallback releaseData;
}
@end

@implementation GDataProvider

- (void)dealloc
{
    [data release];
    if (releaseData)
        releaseData(info, bytes, size);
    [super dealloc];
}

@end

CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *bytes, size_t size,
                                               CGDataProviderReleaseDataCallback releaseData)
{
    GDataProvider *p = [[GDataProvider alloc] init];
    p->data = [[NSData alloc] initWithBytesNoCopy:(void *)bytes length:size freeWhenDone:NO];
    p->info = info;
    p->bytes = bytes;
    p->size = size;
    p->releaseData = releaseData;
    return (CGDataProviderRef)p;
}

CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef data)
{
    if (!data)
        return NULL;
    GDataProvider *p = [[GDataProvider alloc] init];
    p->data = [(NSData *)data copy];
    return (CGDataProviderRef)p;
}

CGDataProviderRef CGDataProviderCreateWithFilename(const char *filename)
{
    NSData *d = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:filename]];
    return d ? CGDataProviderCreateWithCFData((CFDataRef)d) : NULL;
}

CGDataProviderRef CGDataProviderCreateWithURL(CFURLRef url)
{
    NSURL *u = (NSURL *)url;
    return u.isFileURL ? CGDataProviderCreateWithFilename(u.path.UTF8String) : NULL;
}

CGDataProviderRef CGDataProviderRetain(CGDataProviderRef p) { return (CGDataProviderRef)[OBJ(p) retain]; }
void CGDataProviderRelease(CGDataProviderRef p) { [OBJ(p) release]; }
CFDataRef CGDataProviderCopyData(CGDataProviderRef p)
{
    return p ? (CFDataRef)[((GDataProvider *)p)->data copy] : NULL;
}

/* ---- images --------------------------------------------------------------------- */

@implementation GImage

- (void)dealloc
{
    if (surface)
        cairo_surface_destroy(surface);
    [space release];
    [provider release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CGImage %p> (%zu x %zu, %zu bpp)", self, width, height, bpp];
}

@end

static GImage *make_image(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, GColorSpace *space,
                          uint32_t info, GDataProvider *provider)
{
    GImage *im = [[GImage alloc] init];
    im->width = w, im->height = h, im->bpc = bpc, im->bpp = bpp, im->bpr = bpr;
    im->space = [space retain];
    im->info = info;
    im->provider = [provider retain];
    im->interpolate = YES;
    return im;
}

CGImageRef CGImageCreate(size_t width, size_t height, size_t bitsPerComponent, size_t bitsPerPixel,
                         size_t bytesPerRow, CGColorSpaceRef space, CGBitmapInfo bitmapInfo,
                         CGDataProviderRef provider, const CGFloat *decode, bool shouldInterpolate,
                         CGColorRenderingIntent intent)
{
    if (!provider || !width || !height || bytesPerRow < width * bitsPerPixel / 8)
        return NULL;
    GDataProvider *p = (GDataProvider *)provider;
    if (p->data.length < bytesPerRow * (height - 1) + width * bitsPerPixel / 8)
        return NULL;
    if (decode)
        GWarnOnce("an image decode array");
    GImage *im = make_image(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow,
                            space ? (GColorSpace *)space : GSpaceRGB(), bitmapInfo, p);
    im->interpolate = shouldInterpolate;
    return (CGImageRef)im;
}

struct png_reader {
    const uint8_t *bytes;
    size_t size, pos;
};

static cairo_status_t read_png(void *closure, unsigned char *out, unsigned int length)
{
    struct png_reader *r = closure;
    if (r->size - r->pos < length)
        return 10; /* CAIRO_STATUS_READ_ERROR */
    memcpy(out, r->bytes + r->pos, length);
    r->pos += length;
    return 0;
}

/* An image holding a copy of an ARGB32 Cairo surface's pixels. */
static GImage *image_from_surface(cairo_surface_t *s)
{
    cairo_surface_flush(s);
    int w = cairo_image_surface_get_width(s), h = cairo_image_surface_get_height(s);
    int stride = cairo_image_surface_get_stride(s);
    BOOL opaque = cairo_image_surface_get_format(s) == CAIRO_FORMAT_RGB24;
    NSMutableData *copy = [NSMutableData dataWithLength:(NSUInteger)w * 4 * h];
    uint8_t *dst = copy.mutableBytes;
    const uint8_t *src = cairo_image_surface_get_data(s);
    for (int y = 0; y < h; y++) {
        memcpy(dst + (size_t)y * w * 4, src + (size_t)y * stride, (size_t)w * 4);
        if (opaque)
            for (int x = 0; x < w; x++)
                dst[(size_t)y * w * 4 + x * 4 + 3] = 255;
    }
    GDataProvider *p = (GDataProvider *)CGDataProviderCreateWithCFData((CFDataRef)copy);
    GImage *im = make_image(w, h, 8, 32, (size_t)w * 4, GSpaceRGB(),
                            (opaque ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaPremultipliedFirst) |
                                kCGBitmapByteOrder32Little,
                            p);
    [p release];
    return im;
}

CGImageRef CGImageCreateWithPNGDataProvider(CGDataProviderRef source, const CGFloat *decode, bool shouldInterpolate,
                                            CGColorRenderingIntent intent)
{
    if (!source)
        return NULL;
    NSData *d = ((GDataProvider *)source)->data;
    struct png_reader r = {d.bytes, d.length, 0};
    cairo_surface_t *s = cairo_image_surface_create_from_png_stream(read_png, &r);
    if (cairo_surface_status(s)) {
        cairo_surface_destroy(s);
        return NULL;
    }
    GImage *im = image_from_surface(s);
    cairo_surface_destroy(s);
    im->interpolate = shouldInterpolate;
    return (CGImageRef)im;
}

CGImageRef CGImageCreateWithImageInRect(CGImageRef image, CGRect rect)
{
    GImage *src = (GImage *)image;
    if (!src)
        return NULL;
    CGRect r = CGRectIntersection(CGRectIntegral(rect), CGRectMake(0, 0, src->width, src->height));
    if (CGRectIsEmpty(r))
        return NULL;
    size_t px = src->bpp / 8, x0 = (size_t)r.origin.x, y0 = (size_t)r.origin.y;
    size_t w = (size_t)r.size.width, h = (size_t)r.size.height, bpr = w * px;
    NSMutableData *copy = [NSMutableData dataWithLength:bpr * h];
    const uint8_t *bytes = src->provider->data.bytes;
    for (size_t y = 0; y < h; y++)
        memcpy((uint8_t *)copy.mutableBytes + y * bpr, bytes + (y0 + y) * src->bpr + x0 * px, bpr);
    GDataProvider *p = (GDataProvider *)CGDataProviderCreateWithCFData((CFDataRef)copy);
    GImage *im = make_image(w, h, src->bpc, src->bpp, bpr, src->space, src->info, p);
    [p release];
    return (CGImageRef)im;
}

CGImageRef CGImageCreateCopy(CGImageRef image) { return (CGImageRef)[OBJ(image) retain]; }
CGImageRef CGImageRetain(CGImageRef image) { return (CGImageRef)[OBJ(image) retain]; }
void CGImageRelease(CGImageRef image) { [OBJ(image) release]; }
size_t CGImageGetWidth(CGImageRef image) { return image ? ((GImage *)image)->width : 0; }
size_t CGImageGetHeight(CGImageRef image) { return image ? ((GImage *)image)->height : 0; }
size_t CGImageGetBitsPerComponent(CGImageRef image) { return image ? ((GImage *)image)->bpc : 0; }
size_t CGImageGetBitsPerPixel(CGImageRef image) { return image ? ((GImage *)image)->bpp : 0; }
size_t CGImageGetBytesPerRow(CGImageRef image) { return image ? ((GImage *)image)->bpr : 0; }
CGColorSpaceRef CGImageGetColorSpace(CGImageRef image) { return image ? (CGColorSpaceRef)((GImage *)image)->space : NULL; }
CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef image)
{
    return image ? (CGImageAlphaInfo)(((GImage *)image)->info & kCGBitmapAlphaInfoMask) : kCGImageAlphaNone;
}
CGBitmapInfo CGImageGetBitmapInfo(CGImageRef image) { return image ? (CGBitmapInfo)((GImage *)image)->info : 0; }
CGDataProviderRef CGImageGetDataProvider(CGImageRef image)
{
    return image ? (CGDataProviderRef)((GImage *)image)->provider : NULL;
}
bool CGImageIsMask(CGImageRef image) { return image && ((GImage *)image)->mask; }
CFTypeID CGImageGetTypeID(void) { return (CFTypeID)[GImage class]; }

cairo_surface_t *GImageSurface(GImage *im)
{
    if (im->surface)
        return im->surface;
    struct gfmt f;
    if (!GFormatFor(im->bpc, im->bpp, im->space->model, im->info, &f)) {
        GWarnOnce("drawing an image in this pixel format");
        return NULL;
    }
    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, (int)im->width, (int)im->height);
    if (cairo_surface_status(s)) {
        cairo_surface_destroy(s);
        return NULL;
    }
    cairo_surface_flush(s);
    uint8_t *dst = cairo_image_surface_get_data(s);
    int stride = cairo_image_surface_get_stride(s);
    const uint8_t *src = im->provider->data.bytes;
    for (size_t y = 0; y < im->height; y++)
        GToCairo(&f, src + y * im->bpr, (uint32_t *)(dst + y * stride), im->width);
    cairo_surface_mark_dirty(s);
    im->surface = s;
    return s;
}

/* ---- gradients ------------------------------------------------------------------- */

@implementation GGradient

- (void)dealloc
{
    free(locations);
    free(rgba);
    [super dealloc];
}

@end

static GGradient *make_gradient(size_t count, const CGFloat *locations)
{
    GGradient *g = [[GGradient alloc] init];
    g->count = count;
    g->locations = malloc(count * sizeof *g->locations);
    g->rgba = malloc(count * sizeof *g->rgba);
    for (size_t i = 0; i < count; i++)
        g->locations[i] = locations ? locations[i] : (count > 1 ? (double)i / (count - 1) : 0);
    return g;
}

CGGradientRef CGGradientCreateWithColorComponents(CGColorSpaceRef space, const CGFloat *components,
                                                  const CGFloat *locations, size_t count)
{
    if (!space || !components || !count)
        return NULL;
    GColorSpace *s = (GColorSpace *)space;
    GGradient *g = make_gradient(count, locations);
    for (size_t i = 0; i < count; i++) {
        GColor *c = GColorNew(s, components + i * (s->ncomp + 1));
        memcpy(g->rgba[i], c->rgba, sizeof g->rgba[i]);
        [c release];
    }
    return (CGGradientRef)g;
}

CGGradientRef CGGradientCreateWithColors(CGColorSpaceRef space, CFArrayRef colors, const CGFloat *locations)
{
    NSArray *a = (NSArray *)colors;
    if (!a.count)
        return NULL;
    GGradient *g = make_gradient(a.count, locations);
    for (size_t i = 0; i < a.count; i++)
        memcpy(g->rgba[i], ((GColor *)a[i])->rgba, sizeof g->rgba[i]);
    return (CGGradientRef)g;
}

CGGradientRef CGGradientRetain(CGGradientRef g) { return (CGGradientRef)[OBJ(g) retain]; }
void CGGradientRelease(CGGradientRef g) { [OBJ(g) release]; }
