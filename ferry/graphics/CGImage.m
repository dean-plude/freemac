/* SPDX-License-Identifier: GPL-3.0-or-later
 * Data providers, bitmap images and gradients, and the pixel conversions
 * between a Mac program's 8-bit-per-component layouts and Cairo's (32-bit
 * words holding premultiplied alpha, red, green, blue). PNG files are read
 * by Cairo, and the other common formats by GdkPixbuf. */
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
    /* already cairo's own layout, premultiplied BGRA or BGRX in memory, as
     * OpenGL's frames and Core Video's 32BGRA are (freemac 1.235): copied
     * a row at a time */
    if (f->bytes == 4 && f->b == 0 && f->g == 1 && f->r == 2 && !f->gray && !f->alphaOnly) {
        if (f->a == 3 && f->premultiplied) {
            memcpy(dst, src, width * 4);
            return;
        }
        if (f->a < 0) {
            for (size_t x = 0; x < width; x++) {
                uint32_t p;
                memcpy(&p, src + x * 4, 4);
                dst[x] = p | 0xff000000u;
            }
            return;
        }
    }
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

CGImageRef CGImageCreateWithJPEGDataProvider(CGDataProviderRef source, const CGFloat *decode, bool shouldInterpolate,
                                             CGColorRenderingIntent intent)
{
    GImage *im = source ? GImageDecode(((GDataProvider *)source)->data, NULL) : nil;
    if (im)
        im->interpolate = shouldInterpolate;
    return (CGImageRef)im;
}

/* The largest PNG picture in an .icns file, in the file format's published
 * layout ("icns", its length, then entries of a four-character type, a
 * length and the data), or nil. */
static NSData *icns_largest_png(NSData *data)
{
    const uint8_t *b = data.bytes;
    size_t n = data.length, at = 8, best = 0;
    NSData *found = nil;
    if (n < 8 || memcmp(b, "icns", 4))
        return nil;
    while (at + 8 <= n) {
        size_t len = ((size_t)b[at + 4] << 24) | ((size_t)b[at + 5] << 16) | ((size_t)b[at + 6] << 8) | b[at + 7];
        if (len < 8 || len > n - at)
            break;
        const uint8_t *d = b + at + 8;
        size_t dl = len - 8;
        if (dl >= 24 && !memcmp(d, "\x89PNG\r\n\x1a\n", 8) && !memcmp(d + 12, "IHDR", 4)) {
            size_t w = ((size_t)d[16] << 24) | ((size_t)d[17] << 16) | ((size_t)d[18] << 8) | d[19];
            if (w > best) {
                best = w;
                found = [NSData dataWithBytes:d length:dl];
            }
        }
        at += len;
    }
    return found;
}

/* What OpenJPEG decoded, as 8-bit RGBA: one, two (grey and alpha), three or
 * four planes of the same size, each scaled from its own precision. */
static GImage *jpeg2000_image(opj_image_t *image)
{
    uint32_t nc = image->numcomps;
    if (nc < 1 || nc > 4)
        return nil;
    opj_image_comp_t *c = image->comps;
    size_t w = c[0].w, h = c[0].h;
    if (!w || !h || w > 16384 || h > 16384)
        return nil;
    for (uint32_t i = 0; i < nc; i++)
        if (c[i].w != w || c[i].h != h || !c[i].data || c[i].prec < 1 || c[i].prec > 16)
            return nil;
    NSMutableData *pixels = [NSMutableData dataWithLength:w * h * 4];
    uint8_t *p = pixels.mutableBytes;
    BOOL grey = nc < 3, alpha = nc == 2 || nc == 4;
    for (size_t i = 0; i < w * h; i++) {
        uint8_t v[4] = {0, 0, 0, 255};
        for (uint32_t k = 0; k < nc; k++) {
            int32_t x = c[k].data[i] + (c[k].sgnd ? 1 << (c[k].prec - 1) : 0);
            int32_t top = (1 << c[k].prec) - 1;
            x = x < 0 ? 0 : x > top ? top : x;
            v[k] = (uint8_t)((x * 255 + top / 2) / top);
        }
        if (grey)
            p[4 * i] = p[4 * i + 1] = p[4 * i + 2] = v[0], p[4 * i + 3] = alpha ? v[1] : 255;
        else
            memcpy(p + 4 * i, v, 4), p[4 * i + 3] = alpha ? v[3] : 255;
    }
    GDataProvider *provider = (GDataProvider *)CGDataProviderCreateWithCFData((CFDataRef)pixels);
    GImage *im = make_image(w, h, 8, 32, w * 4, GSpaceRGB(), kCGImageAlphaLast, provider);
    [provider release];
    return im;
}

/* The largest JPEG 2000 picture in an .icns file (a JP2 file or a bare
 * codestream, as the format's larger entries may hold), or nil. Its size
 * isn't in a header this needs to read, so the longest entry is taken. */
static NSData *icns_largest_jpeg2000(NSData *data, int *format)
{
    const uint8_t *b = data.bytes;
    size_t n = data.length, at = 8, best = 0;
    NSData *found = nil;
    while (at + 8 <= n) {
        size_t len = ((size_t)b[at + 4] << 24) | ((size_t)b[at + 5] << 16) | ((size_t)b[at + 6] << 8) | b[at + 7];
        if (len < 8 || len > n - at)
            break;
        const uint8_t *d = b + at + 8;
        size_t dl = len - 8;
        int f = dl >= 12 && !memcmp(d, "\0\0\0\x0cjP  \r\n\x87\n", 12) ? OPJ_CODEC_JP2
                : dl >= 4 && !memcmp(d, "\xff\x4f\xff\x51", 4)            ? OPJ_CODEC_J2K
                                                                          : -1;
        if (f >= 0 && dl > best) {
            best = dl;
            *format = f;
            found = [NSData dataWithBytes:d length:dl];
        }
        at += len;
    }
    return found;
}

/* OpenJPEG reads the picture from memory through these */
typedef struct {
    const uint8_t *bytes;
    size_t length, at;
} j2k_input;
static size_t j2k_read(void *buffer, size_t n, void *data)
{
    j2k_input *in = data;
    if (in->at >= in->length)
        return (size_t)-1;
    if (n > in->length - in->at)
        n = in->length - in->at;
    memcpy(buffer, in->bytes + in->at, n);
    in->at += n;
    return n;
}
static int64_t j2k_skip(int64_t n, void *data)
{
    j2k_input *in = data;
    if (n < 0 ? (size_t)-n > in->at : (size_t)n > in->length - in->at)
        return -1;
    in->at += n;
    return n;
}
static int j2k_seek(int64_t at, void *data)
{
    j2k_input *in = data;
    if (at < 0 || (size_t)at > in->length)
        return 0;
    in->at = (size_t)at;
    return 1;
}

/* A JPEG 2000 picture as 8-bit RGBA, not premultiplied, by this system's
 * OpenJPEG, or nil when it isn't installed or can't read the picture. A
 * picture larger than 512 pixels across is read at a lower resolution, as
 * the format keeps them, at least 256 across: icons are drawn far smaller
 * than the 1024 an .icns file's largest entry holds, and the whole of one
 * takes OpenJPEG most of a second. Grey and RGB pictures, with or without
 * alpha, are read; any other kind is nil. */
static GImage *jpeg2000_decode(NSData *data, int format)
{
    if (!opj_create_decompress)
        return nil;
    opj_dparameters_t *params = calloc(1, sizeof *params);
    opj_set_default_decoder_parameters(params);
    opj_codec_t *codec = opj_create_decompress(format);
    j2k_input in = {data.bytes, data.length, 0};
    opj_stream_t *stream = opj_stream_create(1 << 16, 1);
    opj_image_t *image = NULL;
    GImage *im = nil;
    if (codec && stream && opj_setup_decoder(codec, params)) {
        opj_stream_set_read_function(stream, j2k_read);
        opj_stream_set_skip_function(stream, j2k_skip);
        opj_stream_set_seek_function(stream, j2k_seek);
        opj_stream_set_user_data(stream, &in, NULL);
        opj_stream_set_user_data_length(stream, data.length);
        if (opj_read_header(stream, codec, &image) && image && image->x1 > image->x0) {
            uint32_t width = image->x1 - image->x0, factor = 0;
            while (width >> factor > 512 && width >> (factor + 1) >= 256)
                factor++;
            if (factor && !opj_set_decoded_resolution_factor(codec, factor))
                factor = 0;
            if (opj_decode(codec, stream, image) && opj_end_decompress(codec, stream))
                im = jpeg2000_image(image);
        }
    }
    if (image)
        opj_image_destroy(image);
    if (stream)
        opj_stream_destroy(stream);
    if (codec)
        opj_destroy_codec(codec);
    free(params);
    return im;
}

static GImage *pixbuf_decode(NSData *data, NSString **type);

/* Any image file this system's GdkPixbuf reads (PNG, JPEG, GIF, TIFF, BMP,
 * ICO, ICNS and more), as 8-bit RGB or RGBA, not premultiplied. *type is
 * set to the file's kind as a uniform type identifier. GdkPixbuf reads an
 * .icns file only at the sizes it looks for, so an icon it can't read, such
 * as one ferry-actool made from an app's icon set with only small sizes, is
 * read from its largest PNG picture (freemac 1.224, Ferry 0.48.0), and one
 * with only JPEG 2000 pictures, which GdkPixbuf has no reader for, such as
 * both of KeyCastr's, by OpenJPEG (freemac 1.228, Ferry 0.52.0). */
GImage *GImageDecode(NSData *data, NSString **type)
{
    GImage *im = pixbuf_decode(data, type);
    if (!im && data.length >= 8 && !memcmp(data.bytes, "icns", 4)) {
        NSData *png = icns_largest_png(data);
        im = png ? pixbuf_decode(png, NULL) : nil;
        int format = 0;
        NSData *j2k = im ? nil : icns_largest_jpeg2000(data, &format);
        if (j2k)
            im = jpeg2000_decode(j2k, format);
        if (im && type)
            *type = @"com.apple.icns";
    }
    return im;
}

static GImage *pixbuf_decode(NSData *data, NSString **type)
{
    if (type)
        *type = nil;
    if (data.length < 4)
        return nil;
    GdkPixbufLoader *loader = gdk_pixbuf_loader_new();
    GError *error = NULL;
    BOOL ok = gdk_pixbuf_loader_write(loader, data.bytes, data.length, &error);
    if (error)
        g_error_free(error), error = NULL;
    gdk_pixbuf_loader_close(loader, &error);
    if (error)
        g_error_free(error);
    GdkPixbuf *pb = ok ? gdk_pixbuf_loader_get_pixbuf(loader) : NULL;
    GImage *im = nil;
    if (pb) {
        int w = gdk_pixbuf_get_width(pb), h = gdk_pixbuf_get_height(pb);
        int n = gdk_pixbuf_get_n_channels(pb), stride = gdk_pixbuf_get_rowstride(pb);
        BOOL alpha = gdk_pixbuf_get_has_alpha(pb);
        if (w > 0 && h > 0 && (n == 3 || n == 4) && (n == 4) == alpha) {
            size_t bpr = (size_t)w * n;
            NSMutableData *copy = [NSMutableData dataWithLength:bpr * h];
            const unsigned char *src = gdk_pixbuf_get_pixels(pb);
            for (int y = 0; y < h; y++)
                memcpy((uint8_t *)copy.mutableBytes + y * bpr, src + (size_t)y * stride, bpr);
            GDataProvider *p = (GDataProvider *)CGDataProviderCreateWithCFData((CFDataRef)copy);
            im = make_image(w, h, 8, 8 * n, bpr, GSpaceRGB(), alpha ? kCGImageAlphaLast : kCGImageAlphaNone, p);
            [p release];
        }
    }
    if (type && im) {
        GdkPixbufFormat *f = gdk_pixbuf_loader_get_format(loader);
        char *name = f ? gdk_pixbuf_format_get_name(f) : NULL;
        static const char *const utis[][2] = {
            {"png", "public.png"},         {"jpeg", "public.jpeg"},      {"gif", "com.compuserve.gif"},
            {"tiff", "public.tiff"},       {"bmp", "com.microsoft.bmp"}, {"ico", "com.microsoft.ico"},
            {"icns", "com.apple.icns"},    {"svg", "public.svg-image"},
        };
        for (size_t i = 0; name && i < sizeof utis / sizeof *utis; i++)
            if (!strcmp(name, utis[i][0]))
                *type = [NSString stringWithUTF8String:utis[i][1]];
        if (name && !*type)
            *type = [NSString stringWithFormat:@"public.%s", name];
        g_free(name);
    }
    g_object_unref(loader);
    return im;
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
/* the same pixels read in another colour space with as many components;
 * NULL for a mask, or a space of another size */
CGImageRef CGImageCreateCopyWithColorSpace(CGImageRef image, CGColorSpaceRef space)
{
    GImage *src = (GImage *)image;
    if (!src || !space || src->mask ||
        CGColorSpaceGetNumberOfComponents(space) != CGColorSpaceGetNumberOfComponents((CGColorSpaceRef)src->space))
        return NULL;
    GImage *im = make_image(src->width, src->height, src->bpc, src->bpp, src->bpr, (GColorSpace *)space, src->info,
                            src->provider);
    im->interpolate = src->interpolate;
    return (CGImageRef)im;
}
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
