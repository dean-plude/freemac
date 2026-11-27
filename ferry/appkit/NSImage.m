/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSImage and its image representations. Our own code,
 * written from Apple's public AppKit documentation. Bitmap files (PNG,
 * JPEG, GIF, TIFF, BMP, ICO, ICNS) are read through Ferry's Image I/O,
 * which uses this system's GdkPixbuf; PDF files are kept as PDF and drawn
 * by Poppler at whatever size they are drawn, as a Mac draws them.
 *
 * The standard images a Mac app can ask for by name (NSImageNameAddTemplate
 * and so on) are Apple artwork, which Ferry doesn't ship: Ferry draws simple
 * ones of its own for the common names instead. Built without ARC. */
#import "AInternal.h"

NSString *const NSImageCompressionFactor = @"NSImageCompressionFactor";
NSString *const NSImageHintCTM = @"ctm";
NSString *const NSImageHintInterpolation = @"interpolation";
NSString *const NSImageHintUserInterfaceLayoutDirection = @"userInterfaceLayoutDirection";

NSImageName const NSImageNameAddTemplate = @"NSAddTemplate";
NSImageName const NSImageNameRemoveTemplate = @"NSRemoveTemplate";
NSImageName const NSImageNameStopProgressTemplate = @"NSStopProgressTemplate";
NSImageName const NSImageNameGoLeftTemplate = @"NSGoLeftTemplate";
NSImageName const NSImageNameGoRightTemplate = @"NSGoRightTemplate";
NSImageName const NSImageNameGoBackTemplate = @"NSGoBackTemplate";
NSImageName const NSImageNameGoForwardTemplate = @"NSGoForwardTemplate";
NSImageName const NSImageNameMenuOnStateTemplate = @"NSMenuOnStateTemplate";
NSImageName const NSImageNameMenuMixedStateTemplate = @"NSMenuMixedStateTemplate";
NSImageName const NSImageNameRefreshTemplate = @"NSRefreshTemplate";
NSImageName const NSImageNameActionTemplate = @"NSActionTemplate";
NSImageName const NSImageNameApplicationIcon = @"NSApplicationIcon";
NSImageName const NSImageNameCaution = @"NSCaution";
NSImageName const NSImageNameInfo = @"NSInfo";
NSImageName const NSImageNameStatusAvailable = @"NSStatusAvailable";
NSImageName const NSImageNameStatusUnavailable = @"NSStatusUnavailable";
NSImageName const NSImageNameStatusPartiallyAvailable = @"NSStatusPartiallyAvailable";
NSImageName const NSImageNameStatusNone = @"NSStatusNone";
NSImageName const NSImageNameFolder = @"NSFolder";
NSImageName const NSImageNameTouchBarAddTemplate = @"NSTouchBarAddTemplate";
NSImageName const NSImageNameLockLockedTemplate = @"NSLockLockedTemplate";
NSImageName const NSImageNameLockUnlockedTemplate = @"NSLockUnlockedTemplate";
NSImageName const NSImageNameTouchBarSearchTemplate = @"NSTouchBarSearchTemplate";
NSImageName const NSImageNameTouchBarGetInfoTemplate = @"NSTouchBarGetInfoTemplate";
NSImageName const NSImageNameTouchBarFolderTemplate = @"NSTouchBarFolderTemplate";
NSImageName const NSImageNameTouchBarQuickLookTemplate = @"NSTouchBarQuickLookTemplate";
NSImageName const NSImageNameTouchBarDeleteTemplate = @"NSTouchBarDeleteTemplate";
NSImageName const NSImageNameTouchBarShareTemplate = @"NSTouchBarShareTemplate";
NSImageName const NSImageNameTouchBarHistoryTemplate = @"NSTouchBarHistoryTemplate";
NSImageName const NSImageNameTouchBarComposeTemplate = @"NSTouchBarComposeTemplate";

static CGContextRef current_cg(void) { return [[NSGraphicsContext currentContext] CGContext]; }

/* ---- representations from files --------------------------------------------------- */

static BOOL is_pdf(NSData *data) { return data.length >= 5 && !memcmp(data.bytes, "%PDF", 4); }

@implementation NSImageRep (FerryFiles)
+ (Class)imageRepClassForData:(NSData *)data
{
    return is_pdf(data) ? [NSPDFImageRep class] : [NSBitmapImageRep class];
}
+ (NSArray *)imageRepsWithData:(NSData *)data
{
    Class cls = self == [NSImageRep class] ? [self imageRepClassForData:data] : self;
    NSImageRep *rep = [cls respondsToSelector:@selector(imageRepWithData:)] ? [cls imageRepWithData:data] : nil;
    return rep ? @[ rep ] : nil;
}
+ (NSArray *)imageRepsWithContentsOfFile:(NSString *)path
{
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    return data ? [self imageRepsWithData:data] : nil;
}
+ (instancetype)imageRepWithContentsOfFile:(NSString *)path
{
    return [[self imageRepsWithContentsOfFile:path] firstObject];
}
@end

@implementation NSPDFImageRep {
    NSData *_pdf;
    CGPDFDocumentRef _doc;
    NSInteger _page;
}
+ (instancetype)imageRepWithData:(NSData *)data { return [[[self alloc] initWithData:data] autorelease]; }
- (instancetype)initWithData:(NSData *)data
{
    if (!(self = [super init]))
        return nil;
    CGDataProviderRef p = is_pdf(data) ? CGDataProviderCreateWithCFData((CFDataRef)data) : NULL;
    _doc = p ? CGPDFDocumentCreateWithProvider(p) : NULL;
    CGDataProviderRelease(p);
    if (!_doc || !CGPDFDocumentGetNumberOfPages(_doc)) {
        [self release];
        return nil;
    }
    _pdf = [data copy];
    [self setSize:[self bounds].size];
    [self setAlpha:YES];
    return self;
}
- (void)dealloc
{
    CGPDFDocumentRelease(_doc);
    [_pdf release];
    [super dealloc];
}
- (NSData *)PDFRepresentation { return _pdf; }
- (NSInteger)pageCount { return (NSInteger)CGPDFDocumentGetNumberOfPages(_doc); }
- (NSInteger)currentPage { return _page; }
- (void)setCurrentPage:(NSInteger)page
{
    if (page >= 0 && page < [self pageCount])
        _page = page;
}
- (NSRect)bounds { return NSRectFromCGRect(CGPDFPageGetBoxRect(CGPDFDocumentGetPage(_doc, _page + 1), kCGPDFCropBox)); }
- (BOOL)drawInRect:(NSRect)rect
{
    CGContextRef cg = current_cg();
    CGPDFPageRef page = CGPDFDocumentGetPage(_doc, _page + 1);
    NSRect b = [self bounds];
    if (!cg || !page || NSIsEmptyRect(b))
        return NO;
    CGContextSaveGState(cg);
    CGContextTranslateCTM(cg, rect.origin.x, rect.origin.y);
    CGContextScaleCTM(cg, rect.size.width / b.size.width, rect.size.height / b.size.height);
    CGContextTranslateCTM(cg, -b.origin.x, -b.origin.y);
    CGContextDrawPDFPage(cg, page);
    CGContextRestoreGState(cg);
    return YES;
}
@end

@implementation NSCustomImageRep {
    BOOL (^_handler)(NSRect);
    BOOL _flipped;
}
- (instancetype)initWithSize:(NSSize)size flipped:(BOOL)flipped drawingHandler:(BOOL (^)(NSRect))handler
{
    if ((self = [super init])) {
        _handler = [handler copy];
        _flipped = flipped;
        [self setSize:size];
        [self setAlpha:YES];
    }
    return self;
}
- (void)dealloc
{
    [_handler release];
    [super dealloc];
}
- (BOOL (^)(NSRect))drawingHandler { return _handler; }
/* The block draws in a space where the image is {0, 0, size}, flipped if
 * the image was made flipped, in a context that says so. */
- (BOOL)drawInRect:(NSRect)rect
{
    NSGraphicsContext *gc = [NSGraphicsContext currentContext];
    CGContextRef cg = [gc CGContext];
    NSSize size = [self size];
    if (!cg || !_handler || size.width <= 0 || size.height <= 0)
        return NO;
    CGContextSaveGState(cg);
    CGContextTranslateCTM(cg, rect.origin.x, rect.origin.y);
    CGContextScaleCTM(cg, rect.size.width / size.width, rect.size.height / size.height);
    if (_flipped) {
        CGContextTranslateCTM(cg, 0, size.height);
        CGContextScaleCTM(cg, 1, -1);
    }
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:cg flipped:_flipped]];
    BOOL ok = _handler((NSRect){NSZeroPoint, size});
    [NSGraphicsContext restoreGraphicsState];
    CGContextRestoreGState(cg);
    return ok;
}
@end

/* ---- the standard images Ferry draws ----------------------------------------------- */

static NSImage *drawn(NSSize size, BOOL isTemplate, void (^draw)(NSRect r))
{
    NSImage *im = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect r) {
        draw(r);
        return YES;
    }];
    [im setTemplate:isTemplate];
    return im;
}

static NSBezierPath *stroked(CGFloat width)
{
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p setLineWidth:width];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    return p;
}

static NSImage *chevron(BOOL left)
{
    return drawn(NSMakeSize(10, 14), YES, ^(NSRect r) {
        [[NSColor blackColor] set];
        NSBezierPath *p = stroked(2);
        CGFloat x0 = left ? 7.5 : 2.5, x1 = left ? 2.5 : 7.5;
        [p moveToPoint:NSMakePoint(x0, 2)];
        [p lineToPoint:NSMakePoint(x1, 7)];
        [p lineToPoint:NSMakePoint(x0, 12)];
        [p stroke];
    });
}

static NSImage *status_dot(CGFloat r, CGFloat g, CGFloat b)
{
    return drawn(NSMakeSize(16, 16), NO, ^(NSRect rect) {
        NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3, 3, 10, 10)];
        [[NSColor colorWithRed:r green:g blue:b alpha:1] setFill];
        [dot fill];
        [[NSColor colorWithWhite:0 alpha:0.25] setStroke];
        [dot setLineWidth:0.5];
        [dot stroke];
    });
}

static NSImage *app_icon(void)
{
    NSBundle *main = [NSBundle mainBundle];
    NSString *file = [main objectForInfoDictionaryKey:@"CFBundleIconFile"];
    if ([file isKindOfClass:[NSString class]] && file.length) {
        NSString *path = [file pathExtension].length ? [main pathForResource:file ofType:nil]
                                                       : [main pathForResource:file ofType:@"icns"];
        NSImage *im = path ? [[[NSImage alloc] initWithContentsOfFile:path] autorelease] : nil;
        if ([im isValid])
            return im;
    }
    /* a plain rounded square, for an app without an icon file */
    return drawn(NSMakeSize(128, 128), NO, ^(NSRect r) {
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(12, 12, 104, 104) xRadius:24 yRadius:24];
        [[NSColor colorWithRed:0.55 green:0.6 blue:0.68 alpha:1] setFill];
        [p fill];
    });
}

static NSImage *standard_image(NSString *name)
{
    /* a padlock, shut or open (freemac 1.225) */
    if ([name isEqualToString:NSImageNameLockLockedTemplate] || [name isEqualToString:NSImageNameLockUnlockedTemplate]) {
        BOOL shut = [name isEqualToString:NSImageNameLockLockedTemplate];
        return drawn(NSMakeSize(14, 14), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 1, 10, 7) xRadius:1.5 yRadius:1.5] fill];
            NSBezierPath *p = stroked(1.6);
            [p appendBezierPathWithArcWithCenter:NSMakePoint(shut ? 7 : 9.5, 9.5) radius:3 startAngle:0 endAngle:180];
            [p moveToPoint:NSMakePoint(shut ? 4 : 6.5, 9.5)];
            [p lineToPoint:NSMakePoint(shut ? 4 : 6.5, shut ? 8 : 9.5)];
            [p moveToPoint:NSMakePoint(shut ? 10 : 12.5, 9.5)];
            [p lineToPoint:NSMakePoint(shut ? 10 : 12.5, 8)];
            [p stroke];
        });
    }
    /* a magnifying glass */
    if ([name isEqualToString:NSImageNameTouchBarSearchTemplate])
        return drawn(NSMakeSize(14, 14), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            NSBezierPath *p = stroked(1.6);
            [p appendBezierPathWithOvalInRect:NSMakeRect(1.5, 4.5, 8, 8)];
            [p moveToPoint:NSMakePoint(8.3, 5.7)];
            [p lineToPoint:NSMakePoint(12.5, 1.5)];
            [p stroke];
        });
    /* the other Touch Bar images are their everyday ones' */
    if ([name isEqualToString:NSImageNameTouchBarGetInfoTemplate])
        return standard_image(NSImageNameInfo);
    if ([name isEqualToString:NSImageNameTouchBarFolderTemplate])
        return standard_image(NSImageNameFolder);
    if ([name isEqualToString:NSImageNameTouchBarDeleteTemplate])
        return standard_image(NSImageNameStopProgressTemplate);
    /* an eye, Quick Look's sign (VLC's Messages window shows details with
     * it, freemac 1.NEXT) */
    if ([name isEqualToString:@"NSQuickLookTemplate"] || [name isEqualToString:NSImageNameTouchBarQuickLookTemplate])
        return drawn(NSMakeSize(19, 12), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            NSBezierPath *eye = stroked(1.4);
            [eye moveToPoint:NSMakePoint(1.5, 6)];
            [eye curveToPoint:NSMakePoint(17.5, 6) controlPoint1:NSMakePoint(5, 12) controlPoint2:NSMakePoint(14, 12)];
            [eye curveToPoint:NSMakePoint(1.5, 6) controlPoint1:NSMakePoint(14, 0) controlPoint2:NSMakePoint(5, 0)];
            [eye closePath];
            [eye stroke];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7, 3.5, 5, 5)] fill];
        });
    if ([name isEqualToString:NSImageNameTouchBarShareTemplate] ||
        [name isEqualToString:NSImageNameTouchBarHistoryTemplate] ||
        [name isEqualToString:NSImageNameTouchBarComposeTemplate])
        return standard_image(NSImageNameActionTemplate);
    if ([name isEqualToString:NSImageNameAddTemplate] || [name isEqualToString:NSImageNameTouchBarAddTemplate] ||
        [name isEqualToString:NSImageNameRemoveTemplate]) {
        BOOL add = ![name isEqualToString:NSImageNameRemoveTemplate];
        return drawn(NSMakeSize(14, 14), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            NSRectFill(NSMakeRect(2, 6, 10, 2));
            if (add)
                NSRectFill(NSMakeRect(6, 2, 2, 10));
        });
    }
    /* the freestanding one is a cross in a filled circle (HandBrake's queue) */
    if ([name isEqualToString:@"NSStopProgressFreestandingTemplate"])
        return drawn(NSMakeSize(14, 14), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 13, 13)] fill];
            [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationClear];
            NSBezierPath *p = stroked(1.6);
            [p moveToPoint:NSMakePoint(4.5, 4.5)];
            [p lineToPoint:NSMakePoint(9.5, 9.5)];
            [p moveToPoint:NSMakePoint(4.5, 9.5)];
            [p lineToPoint:NSMakePoint(9.5, 4.5)];
            [p stroke];
        });
    if ([name isEqualToString:NSImageNameStopProgressTemplate])
        return drawn(NSMakeSize(14, 14), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            NSBezierPath *p = stroked(2);
            [p moveToPoint:NSMakePoint(3, 3)];
            [p lineToPoint:NSMakePoint(11, 11)];
            [p moveToPoint:NSMakePoint(3, 11)];
            [p lineToPoint:NSMakePoint(11, 3)];
            [p stroke];
        });
    if ([name isEqualToString:NSImageNameGoLeftTemplate] || [name isEqualToString:NSImageNameGoBackTemplate])
        return chevron(YES);
    if ([name isEqualToString:NSImageNameGoRightTemplate] || [name isEqualToString:NSImageNameGoForwardTemplate])
        return chevron(NO);
    if ([name isEqualToString:NSImageNameMenuOnStateTemplate])
        return drawn(NSMakeSize(12, 12), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            NSBezierPath *p = stroked(1.8);
            [p moveToPoint:NSMakePoint(2, 6)];
            [p lineToPoint:NSMakePoint(5, 2.8)];
            [p lineToPoint:NSMakePoint(10, 9.5)];
            [p stroke];
        });
    if ([name isEqualToString:NSImageNameMenuMixedStateTemplate])
        return drawn(NSMakeSize(12, 12), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            NSRectFill(NSMakeRect(2, 5, 8, 2));
        });
    if ([name isEqualToString:NSImageNameRefreshTemplate])
        return drawn(NSMakeSize(14, 14), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            NSBezierPath *p = stroked(1.6);
            [p appendBezierPathWithArcWithCenter:NSMakePoint(7, 7) radius:4.5 startAngle:80 endAngle:380];
            [p stroke];
            NSBezierPath *head = [NSBezierPath bezierPath];
            [head moveToPoint:NSMakePoint(7, 13.5)];
            [head lineToPoint:NSMakePoint(10.5, 11.5)];
            [head lineToPoint:NSMakePoint(7, 9)];
            [head closePath];
            [head fill];
        });
    if ([name isEqualToString:NSImageNameActionTemplate])
        return drawn(NSMakeSize(14, 14), YES, ^(NSRect r) {
            [[NSColor blackColor] set];
            for (int i = 0; i < 3; i++)
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1.5 + i * 4, 5.5, 3, 3)] fill];
        });
    if ([name isEqualToString:NSImageNameCaution])
        return drawn(NSMakeSize(32, 32), NO, ^(NSRect r) {
            NSBezierPath *t = [NSBezierPath bezierPath];
            [t moveToPoint:NSMakePoint(16, 29)];
            [t lineToPoint:NSMakePoint(30, 4)];
            [t lineToPoint:NSMakePoint(2, 4)];
            [t closePath];
            [t setLineJoinStyle:NSLineJoinStyleRound];
            [t setLineWidth:2];
            [[NSColor colorWithRed:0.98 green:0.78 blue:0.15 alpha:1] set];
            [t fill];
            [t stroke];
            [[NSColor colorWithWhite:0.15 alpha:1] set];
            NSRectFill(NSMakeRect(14.75, 12, 2.5, 10));
            NSRectFill(NSMakeRect(14.75, 7, 2.5, 2.5));
        });
    if ([name isEqualToString:NSImageNameInfo])
        return drawn(NSMakeSize(32, 32), NO, ^(NSRect r) {
            [[NSColor colorWithRed:0.2 green:0.48 blue:0.95 alpha:1] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(2, 2, 28, 28)] fill];
            [[NSColor whiteColor] set];
            NSRectFill(NSMakeRect(14.5, 7, 3, 12));
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(14, 21.5, 4, 4)] fill];
        });
    if ([name isEqualToString:NSImageNameStatusAvailable])
        return status_dot(0.2, 0.78, 0.3);
    if ([name isEqualToString:NSImageNameStatusUnavailable])
        return status_dot(0.93, 0.25, 0.22);
    if ([name isEqualToString:NSImageNameStatusPartiallyAvailable])
        return status_dot(0.98, 0.75, 0.15);
    if ([name isEqualToString:NSImageNameStatusNone])
        return status_dot(0.75, 0.75, 0.75);
    if ([name isEqualToString:NSImageNameFolder])
        return drawn(NSMakeSize(32, 32), NO, ^(NSRect r) {
            [[NSColor colorWithRed:0.36 green:0.66 blue:0.93 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 21, 12, 6) xRadius:2 yRadius:2] fill];
            [[NSColor colorWithRed:0.47 green:0.74 blue:0.97 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 4, 28, 20) xRadius:2.5 yRadius:2.5] fill];
        });
    if ([name isEqualToString:NSImageNameApplicationIcon])
        return app_icon();
    return nil;
}

/* ---- NSImage --------------------------------------------------------------------------- */

static NSMutableDictionary *named_images;
static NSArray *image_extensions(void)
{
    static NSArray *exts;
    if (!exts)
        exts = [@[ @"png", @"tiff", @"tif", @"jpg", @"jpeg", @"gif", @"pdf", @"icns", @"bmp", @"ico" ] retain];
    return exts;
}

@implementation NSImage {
    NSString *_name;
    NSSize _size;
    BOOL _sizeSet, _template, _flipped, _scales, _matches, _eps, _colorMatch;
    NSMutableArray *_reps;
    NSString *_lazyPath;   /* initByReferencingFile: reads the file when first needed */
    NSColor *_background;
    NSString *_description;
    NSImageCacheMode _cacheMode;
    NSRect _alignment;
    CGImageRef _cgImage;   /* made by CGImageForProposedRect: */
    NSBitmapImageRep *_focusRep;
}

+ (NSArray *)imageTypes
{
    return @[ @"public.png", @"public.jpeg", @"com.compuserve.gif", @"public.tiff", @"com.microsoft.bmp",
              @"com.microsoft.ico", @"com.apple.icns", @"com.adobe.pdf" ];
}
+ (NSArray *)imageUnfilteredTypes { return [self imageTypes]; }
+ (NSArray *)imageFileTypes { return image_extensions(); }

+ (NSImage *)imageNamed:(NSImageName)name
{
    if (![name isKindOfClass:[NSString class]] || !name.length)
        return nil;
    NSImage *im = named_images[name];
    if (im)
        return im;
    im = [[NSBundle mainBundle] imageForResource:name];   /* its asset catalogue first */
    if (!im)
        im = standard_image(name);
    if (!im)
        return nil;
    [im setName:name];
    return im;
}

/* For Swift's NSImage(imageLiteralResourceName:) (freemac 1.260): a new
 * image with the representations of the image of that name, or an empty
 * one if there is none, as a Mac gives. */
- (instancetype)initWithFerryImageLiteralName:(NSString *)name
{
    NSImage *found = [NSImage imageNamed:name];
    if (!found)
        fprintf(stderr, "ferry: the app has no image named %s\n", [name UTF8String]);
    if (!(self = [self initWithSize:found ? [found size] : NSMakeSize(0, 0)]))
        return nil;
    for (NSImageRep *rep in [found representations])
        [self addRepresentation:rep];
    return self;
}

+ (instancetype)imageWithSize:(NSSize)size flipped:(BOOL)flipped drawingHandler:(BOOL (^)(NSRect))handler
{
    NSImage *im = [[[self alloc] initWithSize:size] autorelease];
    NSCustomImageRep *rep = [[NSCustomImageRep alloc] initWithSize:size flipped:flipped drawingHandler:handler];
    [im addRepresentation:rep];
    [rep release];
    return im;
}

- (instancetype)init
{
    if ((self = [super init]))
        _reps = [[NSMutableArray alloc] init];
    return self;
}
- (instancetype)initWithSize:(NSSize)size
{
    if ((self = [self init]) && size.width > 0 && size.height > 0) {
        _size = size;
        _sizeSet = YES;
    }
    return self;
}

/* "name@2x.png" holds pixels for twice the scale: its size is half. */
static CGFloat file_scale(NSString *path)
{
    NSString *base = [[path lastPathComponent] stringByDeletingPathExtension];
    if ([base hasSuffix:@"@2x"])
        return 2;
    if ([base hasSuffix:@"@3x"])
        return 3;
    return 1;
}

- (BOOL)_addRepsFromData:(NSData *)data scale:(CGFloat)scale
{
    NSArray *reps = data ? [NSImageRep imageRepsWithData:data] : nil;
    for (NSImageRep *rep in reps) {
        if (scale > 1 && [rep isKindOfClass:[NSBitmapImageRep class]])
            [rep setSize:NSMakeSize([rep pixelsWide] / scale, [rep pixelsHigh] / scale)];
        [_reps addObject:rep];
    }
    return reps.count > 0;
}

- (instancetype)initWithData:(NSData *)data
{
    if (!(self = [self init]))
        return nil;
    if (![self _addRepsFromData:data scale:1]) {
        [self release];
        return nil;
    }
    return self;
}
- (instancetype)initWithContentsOfFile:(NSString *)path
{
    if (!(self = [self init]))
        return nil;
    if (![self _addRepsFromData:path ? [NSData dataWithContentsOfFile:path] : nil scale:file_scale(path)]) {
        [self release];
        return nil;
    }
    return self;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url
{
    if ([url isFileURL])
        return [self initWithContentsOfFile:[url path]];
    [self release];
    return nil;
}
- (instancetype)initByReferencingFile:(NSString *)path
{
    if ((self = [self init]))
        _lazyPath = [path copy];
    return self;
}
- (instancetype)initByReferencingURL:(NSURL *)url
{
    return [self initByReferencingFile:[url isFileURL] ? [url path] : nil];
}
- (instancetype)initWithCGImage:(CGImageRef)image size:(NSSize)size
{
    if (!(self = [self init]))
        return nil;
    NSBitmapImageRep *rep = image ? [[NSBitmapImageRep alloc] initWithCGImage:image] : nil;
    if (!rep) {
        [self release];
        return nil;
    }
    if (size.width > 0 && size.height > 0)
        [rep setSize:size];
    [_reps addObject:rep];
    [rep release];
    return self;
}

- (void)dealloc
{
    [_name release];
    [_reps release];
    [_lazyPath release];
    [_background release];
    [_description release];
    [_focusRep release];
    CGImageRelease(_cgImage);
    [super dealloc];
}

- (void)_load
{
    if (!_lazyPath)
        return;
    NSString *path = _lazyPath;
    _lazyPath = nil;
    [self _addRepsFromData:[NSData dataWithContentsOfFile:path] scale:file_scale(path)];
    [path release];
}

- (id)copyWithZone:(NSZone *)zone
{
    [self _load];
    NSImage *c = [[[self class] allocWithZone:zone] init];
    [c->_reps addObjectsFromArray:_reps];
    c->_size = _size;
    c->_sizeSet = _sizeSet;
    c->_template = _template;
    c->_flipped = _flipped;
    c->_background = [_background retain];
    c->_description = [_description copy];
    return c;
}

/* Keyed archives: the image's name, or failing that its pixels as PNG. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *name = [coder containsValueForKey:@"NSName"] ? [coder decodeObjectForKey:@"NSName"] : nil;
    NSImage *named = [name isKindOfClass:[NSString class]] ? [NSImage imageNamed:name] : nil;
    if (named) {
        [self release];
        return [named retain];
    }
    if (!(self = [self init]))
        return nil;
    if ([coder containsValueForKey:@"NSFerryImageData"])
        [self _addRepsFromData:[coder decodeObjectForKey:@"NSFerryImageData"] scale:1];
    if ([coder containsValueForKey:@"NSSize"])
        [self setSize:[coder decodeSizeForKey:@"NSSize"]];
    if ([coder containsValueForKey:@"NSTemplate"])
        _template = [coder decodeBoolForKey:@"NSTemplate"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (_name) {
        [coder encodeObject:_name forKey:@"NSName"];
        return;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:[self CGImageForProposedRect:NULL context:nil
                                                                                              hints:nil]];
    [coder encodeObject:[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                 forKey:@"NSFerryImageData"];
    [rep release];
    [coder encodeSize:[self size] forKey:@"NSSize"];
    [coder encodeBool:_template forKey:@"NSTemplate"];
}

- (NSString *)description
{
    NSSize s = [self size];
    return [NSString stringWithFormat:@"<NSImage %p Name=%@ Size={%g, %g} Reps=%lu>", self, _name ?: @"(null)",
                                      s.width, s.height, (unsigned long)[[self representations] count]];
}

- (BOOL)setName:(NSImageName)name
{
    if (name && named_images[name] && named_images[name] != self)
        return NO;
    if (!named_images)
        named_images = [[NSMutableDictionary alloc] init];
    if (_name && named_images[_name] == self)
        [named_images removeObjectForKey:_name];
    id wasName = _name;
    _name = [name copy];
    [wasName release];
    if (_name)
        named_images[_name] = self;
    return YES;
}
- (NSImageName)name { return _name; }
- (NSString *)_imageName { return _name; }

- (NSSize)size
{
    if (_sizeSet)
        return _size;
    [self _load];
    return _reps.count ? [_reps[0] size] : NSZeroSize;
}
- (void)setSize:(NSSize)size
{
    _size = size;
    _sizeSet = YES;
    CGImageRelease(_cgImage);
    _cgImage = NULL;
}
- (BOOL)isTemplate { return _template; }
- (void)setTemplate:(BOOL)t { _template = t; }
- (BOOL)isValid
{
    [self _load];
    return _reps.count > 0;
}
- (NSString *)accessibilityDescription { return _description; }
- (void)setAccessibilityDescription:(NSString *)d
{
    id wasDescription = _description;
    _description = [d copy];
    [wasDescription release];
}
- (NSColor *)backgroundColor { return _background ?: [NSColor clearColor]; }
- (void)setBackgroundColor:(NSColor *)c
{
    id wasBackground = _background;
    _background = [c copy];
    [wasBackground release];
}
- (NSImageCacheMode)cacheMode { return _cacheMode; }
- (void)setCacheMode:(NSImageCacheMode)m { _cacheMode = m; }
- (BOOL)matchesOnMultipleResolution { return _matches; }
- (void)setMatchesOnMultipleResolution:(BOOL)f { _matches = f; }
- (BOOL)usesEPSOnResolutionMismatch { return _eps; }
- (void)setUsesEPSOnResolutionMismatch:(BOOL)f { _eps = f; }
- (BOOL)prefersColorMatch { return _colorMatch; }
- (void)setPrefersColorMatch:(BOOL)f { _colorMatch = f; }
- (NSRect)alignmentRect { return NSIsEmptyRect(_alignment) ? (NSRect){NSZeroPoint, [self size]} : _alignment; }
- (void)setAlignmentRect:(NSRect)r { _alignment = r; }
- (BOOL)isFlipped { return _flipped; }
- (void)setFlipped:(BOOL)f { _flipped = f; }
- (BOOL)scalesWhenResized { return _scales; }
- (void)setScalesWhenResized:(BOOL)f { _scales = f; }

- (NSArray *)representations
{
    [self _load];
    return [[_reps copy] autorelease];
}
- (void)addRepresentation:(NSImageRep *)rep
{
    if (rep)
        [_reps addObject:rep];
    [self recache];
}
- (void)addRepresentations:(NSArray *)reps
{
    [_reps addObjectsFromArray:reps];
    [self recache];
}
- (void)removeRepresentation:(NSImageRep *)rep
{
    [_reps removeObjectIdenticalTo:rep];
    [self recache];
}
- (void)recache
{
    CGImageRelease(_cgImage);
    _cgImage = NULL;
}

/* A vector representation if there is one; otherwise the smallest bitmap
 * with enough pixels for the rectangle at the screen's scale, or the
 * largest. */
- (NSImageRep *)bestRepresentationForRect:(NSRect)rect context:(NSGraphicsContext *)context hints:(NSDictionary *)hints
{
    [self _load];
    NSImageRep *best = nil;
    CGFloat need = (rect.size.width > 0 ? rect.size.width : [self size].width) * AScreenScale();
    for (NSImageRep *rep in _reps) {
        if (![rep isKindOfClass:[NSBitmapImageRep class]])
            return rep;
        if (!best)
            best = rep;
        else if ([best pixelsWide] < need ? [rep pixelsWide] > [best pixelsWide]
                                          : [rep pixelsWide] >= need && [rep pixelsWide] < [best pixelsWide])
            best = rep;
    }
    return best;
}

/* Draws the part of the image in from (the whole image if it's empty) into
 * rect, clipped to rect. */
- (void)_drawInRect:(NSRect)rect from:(NSRect)from operation:(NSCompositingOperation)op fraction:(CGFloat)fraction
               flip:(BOOL)respect tint:(NSColor *)tint
{
    NSGraphicsContext *gc = [NSGraphicsContext currentContext];
    CGContextRef cg = [gc CGContext];
    NSSize size = [self size];
    if (!cg || size.width <= 0 || size.height <= 0 || NSIsEmptyRect(rect))
        return;
    if (from.size.width <= 0 || from.size.height <= 0)
        from = (NSRect){NSZeroPoint, size};
    NSImageRep *rep = [self bestRepresentationForRect:rect context:gc hints:nil];
    if (!rep)
        return;
    NSCompositingOperation savedOp = [gc compositingOperation];
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, NSRectToCGRect(rect));
    if (respect && [gc isFlipped]) {
        CGContextTranslateCTM(cg, 0, NSMinY(rect) + NSMaxY(rect));
        CGContextScaleCTM(cg, 1, -1);
    }
    [gc setCompositingOperation:op];
    CGContextSetAlpha(cg, fraction);
    CGFloat sx = rect.size.width / from.size.width, sy = rect.size.height / from.size.height;
    NSRect whole = NSMakeRect(rect.origin.x - from.origin.x * sx, rect.origin.y - from.origin.y * sy,
                              size.width * sx, size.height * sy);
    if (tint) {
        CGImageRef tinted = [self _tintedImage:tint pixels:NSMakeSize(ceil(whole.size.width * AScreenScale()),
                                                                     ceil(whole.size.height * AScreenScale()))];
        if (tinted)
            CGContextDrawImage(cg, NSRectToCGRect(whole), tinted);
        CGImageRelease(tinted);
    } else if ([rep isKindOfClass:[NSBitmapImageRep class]] && !NSEqualRects(from, (NSRect){NSZeroPoint, size})) {
        /* only the pixels inside from, so none outside it blur in at the edges */
        CGFloat kx = [rep pixelsWide] / size.width, ky = [rep pixelsHigh] / size.height;
        CGRect px = CGRectMake(from.origin.x * kx, (size.height - NSMaxY(from)) * ky, from.size.width * kx,
                               from.size.height * ky);
        CGImageRef sub = CGImageCreateWithImageInRect([(NSBitmapImageRep *)rep CGImage], px);
        if (sub)
            CGContextDrawImage(cg, NSRectToCGRect(rect), sub);
        CGImageRelease(sub);
    } else {
        [rep drawInRect:whole];
    }
    CGContextRestoreGState(cg);
    [gc setCompositingOperation:savedOp];
}

/* The image drawn at a size in pixels, as a new bitmap. */
- (CGContextRef)_bitmapContextWithPixels:(NSSize)pixels
{
    size_t w = (size_t)fmax(pixels.width, 1), h = (size_t)fmax(pixels.height, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!cg)
        return NULL;
    NSSize size = [self size];
    NSImageRep *rep = [self bestRepresentationForRect:NSMakeRect(0, 0, w / AScreenScale(), h / AScreenScale())
                                              context:nil
                                                hints:nil];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:cg flipped:NO]];
    CGContextScaleCTM(cg, w / size.width, h / size.height);
    [rep drawInRect:(NSRect){NSZeroPoint, size}];
    [NSGraphicsContext restoreGraphicsState];
    return cg;
}

/* A template image is a shape, drawn in its alpha only: filled with the
 * colour of the control it is in. */
- (CGImageRef)_tintedImage:(NSColor *)tint pixels:(NSSize)pixels
{
    NSSize size = [self size];
    if (size.width <= 0 || size.height <= 0)
        return NULL;
    CGContextRef cg = [self _bitmapContextWithPixels:pixels];
    if (!cg)
        return NULL;
    CGFloat c[4];
    AColorRGBA(tint, c);
    CGContextSetBlendMode(cg, kCGBlendModeSourceIn);
    CGContextSetRGBFillColor(cg, c[0], c[1], c[2], c[3]);
    CGContextFillRect(cg, CGRectMake(0, 0, size.width, size.height));
    CGImageRef image = CGBitmapContextCreateImage(cg);
    CGContextRelease(cg);
    return image;
}

/* Used by controls: in rect, kept upright in flipped views, tinted with
 * color if the image is a template. */
- (void)_drawInControlRect:(NSRect)rect color:(NSColor *)color fraction:(CGFloat)fraction
{
    [self _drawInRect:rect from:NSZeroRect operation:NSCompositingOperationSourceOver fraction:fraction flip:YES
                 tint:_template ? color : nil];
}

- (void)drawAtPoint:(NSPoint)point fromRect:(NSRect)from operation:(NSCompositingOperation)op fraction:(CGFloat)f
{
    NSSize s = from.size.width > 0 && from.size.height > 0 ? from.size : [self size];
    [self _drawInRect:(NSRect){point, s} from:from operation:op fraction:f flip:NO tint:nil];
}
- (void)drawInRect:(NSRect)rect fromRect:(NSRect)from operation:(NSCompositingOperation)op fraction:(CGFloat)f
{
    [self _drawInRect:rect from:from operation:op fraction:f flip:NO tint:nil];
}
- (void)drawInRect:(NSRect)rect fromRect:(NSRect)from operation:(NSCompositingOperation)op fraction:(CGFloat)f
    respectFlipped:(BOOL)respect hints:(NSDictionary *)hints
{
    [self _drawInRect:rect from:from operation:op fraction:f flip:respect tint:nil];
}
- (void)drawInRect:(NSRect)rect
{
    [self _drawInRect:rect from:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 flip:YES tint:nil];
}
- (void)compositeToPoint:(NSPoint)point operation:(NSCompositingOperation)op
{
    [self drawAtPoint:point fromRect:NSZeroRect operation:op fraction:1];
}
- (void)compositeToPoint:(NSPoint)point operation:(NSCompositingOperation)op fraction:(CGFloat)f
{
    [self drawAtPoint:point fromRect:NSZeroRect operation:op fraction:f];
}
- (void)dissolveToPoint:(NSPoint)point fraction:(CGFloat)f
{
    [self drawAtPoint:point fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:f];
}

/* Drawing into the image: into a new bitmap at the screen's scale, which
 * starts with what the image showed and replaces its representations. */
- (void)lockFocus { [self lockFocusFlipped:NO]; }
- (void)lockFocusFlipped:(BOOL)flipped
{
    NSSize size = [self size];
    if (size.width <= 0 || size.height <= 0) {
        AWarnOnce("lockFocus on an image with no size");
        return;
    }
    CGFloat scale = AScreenScale();
    NSInteger w = (NSInteger)ceil(size.width * scale), h = (NSInteger)ceil(size.height * scale);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:32];
    [rep setSize:size];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate([rep bitmapData], w, h, 8, [rep bytesPerRow], space,
                                            kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextScaleCTM(cg, w / size.width, h / size.height);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:cg flipped:NO]];
    if ([self isValid])
        [self drawInRect:(NSRect){NSZeroPoint, size} fromRect:NSZeroRect operation:NSCompositingOperationCopy
                fraction:1];
    if (flipped) {
        CGContextTranslateCTM(cg, 0, size.height);
        CGContextScaleCTM(cg, 1, -1);
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES]];
    }
    CGContextRelease(cg);
    [_focusRep release];
    _focusRep = rep;
}
- (void)unlockFocus
{
    if (!_focusRep)
        return;
    [NSGraphicsContext restoreGraphicsState];
    [_reps removeAllObjects];
    [_reps addObject:_focusRep];
    [_focusRep release];
    _focusRep = nil;
    if (!_sizeSet) {
        _size = [_reps[0] size];
        _sizeSet = YES;
    }
    [self recache];
}

- (CGImageRef)CGImageForProposedRect:(NSRect *)rect context:(NSGraphicsContext *)context hints:(NSDictionary *)hints
{
    NSRect r = rect && rect->size.width > 0 && rect->size.height > 0 ? *rect : (NSRect){NSZeroPoint, [self size]};
    NSImageRep *rep = [self bestRepresentationForRect:r context:context hints:hints];
    if ([rep isKindOfClass:[NSBitmapImageRep class]])
        return [(NSBitmapImageRep *)rep CGImage];
    if (!rep || r.size.width <= 0 || r.size.height <= 0)
        return NULL;
    if (!_cgImage) {
        CGFloat scale = AScreenScale();
        CGContextRef cg = [self _bitmapContextWithPixels:NSMakeSize(ceil(r.size.width * scale),
                                                                    ceil(r.size.height * scale))];
        _cgImage = cg ? CGBitmapContextCreateImage(cg) : NULL;
        CGContextRelease(cg);
    }
    return _cgImage;
}

- (NSData *)TIFFRepresentation
{
    CGImageRef image = [self CGImageForProposedRect:NULL context:nil hints:nil];
    if (!image)
        return nil;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSData *data = [rep TIFFRepresentation];
    [rep release];
    return data;
}
@end

/* ---- finding images in bundles ------------------------------------------------------- */

@implementation NSBundle (NSBundleImageExtension)
- (NSString *)pathForImageResource:(NSImageName)name
{
    if (!name.length)
        return nil;
    if ([name pathExtension].length) {
        NSString *path = [self pathForResource:name ofType:nil];
        if (path)
            return path;
    }
    for (NSString *ext in image_extensions()) {
        NSString *path = [self pathForResource:name ofType:ext];
        if (path)
            return path;
    }
    for (NSString *ext in image_extensions()) {
        NSString *path = [self pathForResource:[name stringByAppendingString:@"@2x"] ofType:ext];
        if (path)
            return path;
    }
    return nil;
}
- (NSURL *)URLForImageResource:(NSImageName)name
{
    NSString *path = [self pathForImageResource:name];
    return path ? [NSURL fileURLWithPath:path] : nil;
}
/* With "name@2x" beside "name", both are kept, for drawing at either scale. */
- (NSImage *)imageForResource:(NSImageName)name
{
    /* the bundle's asset catalogue first, as on a Mac (NSAssets.m) */
    NSImage *asset = AAssetImage(self, name);
    if (asset)
        return asset;
    NSString *path = [self pathForImageResource:name];
    NSImage *im = path ? [[[NSImage alloc] initWithContentsOfFile:path] autorelease] : nil;
    if (!im)
        return nil;
    /* as on a Mac, an image whose name ends in "Template" is a template */
    if ([[[path lastPathComponent] stringByDeletingPathExtension] hasSuffix:@"Template"])
        [im setTemplate:YES];
    if (file_scale(path) == 1) {
        NSString *dir = [path stringByDeletingLastPathComponent], *ext = [path pathExtension];
        NSString *base = [[path lastPathComponent] stringByDeletingPathExtension];
        NSString *twice = [dir stringByAppendingPathComponent:
                                   [[base stringByAppendingString:@"@2x"] stringByAppendingPathExtension:ext]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:twice]) {
            NSSize size = [im size];
            NSImage *big = [[NSImage alloc] initWithContentsOfFile:twice];
            for (NSImageRep *rep in [big representations]) {
                [rep setSize:size];
                [im addRepresentation:rep];
            }
            [big release];
            [im setSize:size];
        }
    }
    return im;
}
@end
