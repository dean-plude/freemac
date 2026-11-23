/* SPDX-License-Identifier: GPL-3.0-or-later
 * Image I/O's image sources (reading image files into CGImages) and Core
 * Graphics' PDF documents and pages. Our own code, written from Apple's
 * public API documentation. Image files are read by this system's
 * GdkPixbuf (see GImageDecode) and PDF pages are drawn by Poppler, straight
 * into the context's Cairo surface, so they stay sharp at any size. Image
 * I/O is served from this library, as Core Text is. Built without ARC. */
#import "GInternal.h"
#include <ImageIO/ImageIO.h>

const CFStringRef kCGImagePropertyPixelWidth = (CFStringRef)@"PixelWidth";
const CFStringRef kCGImagePropertyPixelHeight = (CFStringRef)@"PixelHeight";
const CFStringRef kCGImagePropertyHasAlpha = (CFStringRef)@"HasAlpha";
const CFStringRef kCGImagePropertyDPIWidth = (CFStringRef)@"DPIWidth";
const CFStringRef kCGImagePropertyDPIHeight = (CFStringRef)@"DPIHeight";
const CFStringRef kCGImageSourceShouldCache = (CFStringRef)@"kCGImageSourceShouldCache";
const CFStringRef kCGImageSourceShouldAllowFloat = (CFStringRef)@"kCGImageSourceShouldAllowFloat";
const CFStringRef kCGImageSourceTypeIdentifierHint = (CFStringRef)@"kCGImageSourceTypeIdentifierHint";
const CFStringRef kCGImageSourceCreateThumbnailFromImageAlways =
    (CFStringRef)@"kCGImageSourceCreateThumbnailFromImageAlways";
const CFStringRef kCGImageSourceCreateThumbnailFromImageIfAbsent =
    (CFStringRef)@"kCGImageSourceCreateThumbnailFromImageIfAbsent";
const CFStringRef kCGImageSourceThumbnailMaxPixelSize = (CFStringRef)@"kCGImageSourceThumbnailMaxPixelSize";
const CFStringRef kCGImageSourceCreateThumbnailWithTransform =
    (CFStringRef)@"kCGImageSourceCreateThumbnailWithTransform";

/* ---- image sources ------------------------------------------------------------------ */

/* The file is read when the source is made; a file GdkPixbuf can't read
 * gives a source with no images. Files with several images (animated GIFs,
 * multi-page TIFFs, icon files) give one: the first, or for an icon file
 * the largest. */
@interface GImageSource : NSObject {
@public
    GImage *image;
    NSString *type;
}
@end
@implementation GImageSource
- (void)dealloc
{
    [image release];
    [type release];
    [super dealloc];
}
@end

static CGImageSourceRef source_for(NSData *data)
{
    if (!data)
        return NULL;
    GImageSource *s = [[GImageSource alloc] init];
    NSString *type = nil;
    s->image = GImageDecode(data, &type);
    s->type = [type copy];
    return (CGImageSourceRef)s;
}

CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options)
{
    return source_for((NSData *)data);
}

CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef provider, CFDictionaryRef options)
{
    return provider ? source_for(((GDataProvider *)provider)->data) : NULL;
}

CGImageSourceRef CGImageSourceCreateWithURL(CFURLRef url, CFDictionaryRef options)
{
    NSURL *u = (NSURL *)url;
    return u.isFileURL ? source_for([NSData dataWithContentsOfFile:u.path]) : NULL;
}

CFTypeID CGImageSourceGetTypeID(void) { return (CFTypeID)[GImageSource class]; }
CFStringRef CGImageSourceGetType(CGImageSourceRef source)
{
    return source ? (CFStringRef)((GImageSource *)source)->type : NULL;
}
size_t CGImageSourceGetCount(CGImageSourceRef source) { return source && ((GImageSource *)source)->image ? 1 : 0; }
CGImageSourceStatus CGImageSourceGetStatus(CGImageSourceRef source)
{
    return source && ((GImageSource *)source)->image ? kCGImageStatusComplete : kCGImageStatusInvalidData;
}
CGImageSourceStatus CGImageSourceGetStatusAtIndex(CGImageSourceRef source, size_t index)
{
    return index < CGImageSourceGetCount(source) ? kCGImageStatusComplete : kCGImageStatusInvalidData;
}

CGImageRef CGImageSourceCreateImageAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options)
{
    if (index >= CGImageSourceGetCount(source))
        return NULL;
    return (CGImageRef)[((GImageSource *)source)->image retain];
}

/* The whole image: Ferry doesn't scale thumbnails down yet. */
CGImageRef CGImageSourceCreateThumbnailAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options)
{
    return CGImageSourceCreateImageAtIndex(source, index, options);
}

CFDictionaryRef CGImageSourceCopyProperties(CGImageSourceRef source, CFDictionaryRef options)
{
    return source ? (CFDictionaryRef)[[NSDictionary alloc] init] : NULL;
}

CFDictionaryRef CGImageSourceCopyPropertiesAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options)
{
    if (index >= CGImageSourceGetCount(source))
        return NULL;
    GImage *im = ((GImageSource *)source)->image;
    uint32_t alpha = im->info & kCGBitmapAlphaInfoMask;
    return (CFDictionaryRef)[[NSDictionary alloc] initWithObjectsAndKeys:
        @(im->width), (id)kCGImagePropertyPixelWidth, @(im->height), (id)kCGImagePropertyPixelHeight,
        @(alpha != kCGImageAlphaNone && alpha != kCGImageAlphaNoneSkipFirst && alpha != kCGImageAlphaNoneSkipLast),
        (id)kCGImagePropertyHasAlpha, @72, (id)kCGImagePropertyDPIWidth, @72, (id)kCGImagePropertyDPIHeight, nil];
}

/* ---- PDF documents ------------------------------------------------------------------- */

@interface GPDFPage : NSObject {
@public
    PopplerPage *page;
    size_t number;
    double width, height;
}
@end

@interface GPDFDocument : NSObject {
@public
    NSData *data;   /* Poppler reads from it for as long as the document lives */
    PopplerDocument *doc;
    NSMutableArray *pages;
}
@end

@implementation GPDFPage
- (void)dealloc
{
    if (page)
        g_object_unref(page);
    [super dealloc];
}
@end

@implementation GPDFDocument
- (void)dealloc
{
    [pages release];
    if (doc)
        g_object_unref(doc);
    [data release];
    [super dealloc];
}
@end

static CGPDFDocumentRef pdf_for(NSData *data)
{
    if (data.length < 5 || memcmp(data.bytes, "%PDF", 4))
        return NULL;
    GError *error = NULL;
    NSData *copy = [data copy];
    PopplerDocument *doc = poppler_document_new_from_data((char *)copy.bytes, (int)copy.length, NULL, &error);
    if (error)
        g_error_free(error);
    if (!doc) {
        [copy release];
        return NULL;
    }
    GPDFDocument *d = [[GPDFDocument alloc] init];
    d->data = copy;
    d->doc = doc;
    int n = poppler_document_get_n_pages(doc);
    d->pages = [[NSMutableArray alloc] initWithCapacity:n > 0 ? n : 0];
    for (int i = 0; i < n; i++) {
        GPDFPage *p = [[GPDFPage alloc] init];
        p->page = poppler_document_get_page(doc, i);
        p->number = (size_t)i + 1;
        if (p->page)
            poppler_page_get_size(p->page, &p->width, &p->height);
        [d->pages addObject:p];
        [p release];
    }
    return (CGPDFDocumentRef)d;
}

CGPDFDocumentRef CGPDFDocumentCreateWithProvider(CGDataProviderRef provider)
{
    return provider ? pdf_for(((GDataProvider *)provider)->data) : NULL;
}
CGPDFDocumentRef CGPDFDocumentCreateWithURL(CFURLRef url)
{
    NSURL *u = (NSURL *)url;
    return u.isFileURL ? pdf_for([NSData dataWithContentsOfFile:u.path]) : NULL;
}
CGPDFDocumentRef CGPDFDocumentRetain(CGPDFDocumentRef d) { return (CGPDFDocumentRef)[OBJ(d) retain]; }
void CGPDFDocumentRelease(CGPDFDocumentRef d) { [OBJ(d) release]; }
CFTypeID CGPDFDocumentGetTypeID(void) { return (CFTypeID)[GPDFDocument class]; }
size_t CGPDFDocumentGetNumberOfPages(CGPDFDocumentRef d) { return d ? ((GPDFDocument *)d)->pages.count : 0; }
bool CGPDFDocumentIsEncrypted(CGPDFDocumentRef d) { return false; }
bool CGPDFDocumentIsUnlocked(CGPDFDocumentRef d) { return true; }
bool CGPDFDocumentAllowsPrinting(CGPDFDocumentRef d) { return true; }
bool CGPDFDocumentAllowsCopying(CGPDFDocumentRef d) { return true; }

/* Pages are numbered from 1, and belong to their document. */
CGPDFPageRef CGPDFDocumentGetPage(CGPDFDocumentRef d, size_t number)
{
    if (!d || number < 1 || number > ((GPDFDocument *)d)->pages.count)
        return NULL;
    return (CGPDFPageRef)((GPDFDocument *)d)->pages[number - 1];
}

CGPDFPageRef CGPDFPageRetain(CGPDFPageRef p) { return (CGPDFPageRef)[OBJ(p) retain]; }
void CGPDFPageRelease(CGPDFPageRef p) { [OBJ(p) release]; }
CFTypeID CGPDFPageGetTypeID(void) { return (CFTypeID)[GPDFPage class]; }
size_t CGPDFPageGetPageNumber(CGPDFPageRef p) { return p ? ((GPDFPage *)p)->number : 0; }
int CGPDFPageGetRotationAngle(CGPDFPageRef p) { return 0; }

/* Every box is the page's size as Poppler gives it, from the origin. */
CGRect CGPDFPageGetBoxRect(CGPDFPageRef p, CGPDFBox box)
{
    return p ? CGRectMake(0, 0, ((GPDFPage *)p)->width, ((GPDFPage *)p)->height) : CGRectZero;
}

CGAffineTransform CGPDFPageGetDrawingTransform(CGPDFPageRef p, CGPDFBox box, CGRect rect, int rotate,
                                               bool preserveAspectRatio)
{
    CGRect r = CGPDFPageGetBoxRect(p, box);
    if (CGRectIsEmpty(r) || CGRectIsEmpty(rect))
        return CGAffineTransformIdentity;
    CGFloat sx = rect.size.width / r.size.width, sy = rect.size.height / r.size.height;
    if (sx > 1)
        sx = 1;
    if (sy > 1)
        sy = 1;
    if (preserveAspectRatio)
        sx = sy = sx < sy ? sx : sy;
    CGFloat tx = rect.origin.x + (rect.size.width - r.size.width * sx) / 2;
    CGFloat ty = rect.origin.y + (rect.size.height - r.size.height * sy) / 2;
    return CGAffineTransformMake(sx, 0, 0, sy, tx, ty);
}

/* Draws the page with its lower left corner at the origin of user space,
 * one PDF unit to one unit there. */
void CGContextDrawPDFPage(CGContextRef c, CGPDFPageRef page)
{
    GPDFPage *p = (GPDFPage *)page;
    GContext *ctx = (GContext *)c;
    if (!ctx || !p || !p->page)
        return;
    GContextWillDraw(ctx);
    cairo_save(ctx->cr);
    /* Poppler draws from the top, with y going down */
    CGContextTranslateCTM(c, 0, p->height);
    CGContextScaleCTM(c, 1, -1);
    if (GSTATE(ctx)->alpha < 1) {
        cairo_push_group(ctx->cr);
        poppler_page_render(p->page, ctx->cr);
        cairo_pop_group_to_source(ctx->cr);
        cairo_paint_with_alpha(ctx->cr, GSTATE(ctx)->alpha);
    } else {
        poppler_page_render(p->page, ctx->cr);
    }
    cairo_restore(ctx->cr);
    GContextDidDraw(ctx);
}
