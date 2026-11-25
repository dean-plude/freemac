/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Quick Look and the rest of Quartz it offers (freemac 1.222,
 * Ferry 0.46.0), written from Apple's public QLPreviewPanel, QLPreviewView,
 * QuickLook and QCView documentation and from how the panel behaves on a
 * Mac; no Apple code, artwork or headers were used.
 *
 * A preview (QLPreviewView, which the shared panel shows too) is the
 * file's icon and name, with its size or kind, over a body: the picture,
 * for a file NSImage can read; the start of the file, for one that reads
 * as text; otherwise the icon again, larger. The panel's controller is
 * looked for in the responder chain each time it's shown, and told when it
 * stops being one; the left and right arrows move between the items, and
 * Escape and Space put the panel away, after its delegate has had the key.
 *
 * Ferry has no Finder to ask a Quick Look generator for previews, so the
 * generator calls answer requests that never come: they keep what they're
 * given. QLThumbnailImageCreate makes a smaller copy of a picture, or of
 * the file's icon. Quartz Composer's compositions are Apple's own, so
 * QCView can't run one: loading one fails. Built without ARC. */
#import "AInternal.h"
#import <Quartz/Quartz.h>

/* ---- the keys ---- */

const CFStringRef kQLPreviewPropertyDisplayNameKey = (CFStringRef)@"DisplayName";
const CFStringRef kQLPreviewPropertyWidthKey = (CFStringRef)@"Width";
const CFStringRef kQLPreviewPropertyHeightKey = (CFStringRef)@"Height";
const CFStringRef kQLPreviewPropertyBaseBundlePathKey = (CFStringRef)@"BaseBundlePath";
const CFStringRef kQLPreviewPropertyStringEncodingKey = (CFStringRef)@"StringEncoding";
const CFStringRef kQLPreviewPropertyMIMETypeKey = (CFStringRef)@"MimeType";
const CFStringRef kQLPreviewPropertyTextEncodingNameKey = (CFStringRef)@"TextEncoding";
const CFStringRef kQLPreviewPropertyAttachmentDataKey = (CFStringRef)@"AttachmentData";
const CFStringRef kQLPreviewPropertyAttachmentsKey = (CFStringRef)@"Attachments";
const CFStringRef kQLPreviewPropertyPDFStyleKey = (CFStringRef)@"PDFStyle";
const CFStringRef kQLPreviewContentIDScheme = (CFStringRef)@"cid";
const CFStringRef kQLPreviewOptionCursorKey = (CFStringRef)@"Cursor";
const CFStringRef kQLThumbnailOptionIconModeKey = (CFStringRef)@"IconMode";
const CFStringRef kQLThumbnailOptionScaleFactorKey = (CFStringRef)@"QL_Scale";
const CFStringRef kQLThumbnailOptionContentTypeUTI = (CFStringRef)@"ContentTypeUTI";
const CFStringRef kQLThumbnailPropertyExtensionKey = (CFStringRef)@"Extension";
const CFStringRef kQLThumbnailPropertyBadgeImageKey = (CFStringRef)@"BadgeImage";
const CFStringRef kQLThumbnailPropertyIconFlavorKey = (CFStringRef)@"IconFlavor";
NSString *const QCViewDidStartRenderingNotification = @"QCViewDidStartRenderingNotification";
NSString *const QCViewDidStopRenderingNotification = @"QCViewDidStopRenderingNotification";
NSString *const QCCompositionInputXKey = @"_protocolInput_X";
NSString *const QCCompositionInputYKey = @"_protocolInput_Y";

/* ---- what a file shows ---- */

static NSString *path_of(id<QLPreviewItem> item)
{
    NSURL *url = [item respondsToSelector:@selector(previewItemURL)] ? [item previewItemURL] : nil;
    return [url isFileURL] ? [url path] : nil;
}

static NSString *title_of(id<QLPreviewItem> item)
{
    if ([item respondsToSelector:@selector(previewItemTitle)]) {
        NSString *t = [item previewItemTitle];
        if ([t length])
            return t;
    }
    NSURL *url = [item respondsToSelector:@selector(previewItemURL)] ? [item previewItemURL] : nil;
    return [url isFileURL] ? [[NSFileManager defaultManager] displayNameAtPath:[url path]] : [url absoluteString];
}

/* a picture NSImage can read */
static NSImage *picture_at(NSString *path)
{
    BOOL dir = NO;
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir] || dir)
        return nil;
    NSImage *image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
    NSSize s = [image size];
    return [image isValid] && s.width > 0 && s.height > 0 ? image : nil;
}

/* the start of a file that reads as text: no NUL bytes, UTF-8 */
static const NSUInteger kTextBytes = 65536;
static NSString *text_at(NSString *path)
{
    BOOL dir = NO;
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir] || dir)
        return nil;
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *data = [h readDataOfLength:kTextBytes + 1];
    [h closeFile];
    if (!data)
        return nil;
    BOOL cut = [data length] > kTextBytes;
    if (cut)
        data = [data subdataWithRange:NSMakeRange(0, kTextBytes)];
    if (memchr([data bytes], 0, [data length]))
        return nil;
    NSString *s = nil;
    /* a cut may fall inside a character: step back to a whole one */
    for (NSUInteger drop = 0; !s && drop < 4 && drop <= [data length]; drop++)
        s = [[[NSString alloc] initWithBytes:[data bytes] length:[data length] - drop encoding:NSUTF8StringEncoding]
            autorelease];
    if (!s)
        return nil;
    return cut ? [s stringByAppendingString:@"\n…"] : s;
}

static NSString *details_of(NSString *path)
{
    if (!path)
        return @"";
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (!a)
        return @"Not found";
    if ([a[NSFileType] isEqual:NSFileTypeDirectory])
        return @"Folder";
    return [NSByteCountFormatter stringFromByteCount:(long long)[a fileSize] countStyle:NSByteCountFormatterCountStyleFile];
}

/* ---- QLPreviewView ---- */

@interface QLPreviewView ()
- (void)_build;
@end

@implementation QLPreviewView {
    id<QLPreviewItem> _item;
    id _displayState;
    QLPreviewViewStyle _style;
    BOOL _closeWithWindow, _autostarts, _closed;
}
@synthesize displayState = _displayState, shouldCloseWithWindow = _closeWithWindow, autostarts = _autostarts;

- (instancetype)initWithFrame:(NSRect)frame style:(QLPreviewViewStyle)style
{
    if ((self = [super initWithFrame:frame])) {
        _style = style;
        _closeWithWindow = YES;
        [self _build];
    }
    return self;
}
- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame style:QLPreviewViewStyleNormal]; }
- (void)dealloc
{
    [_item release];
    [_displayState release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }
- (id<QLPreviewItem>)previewItem { return _item; }
- (void)setPreviewItem:(id<QLPreviewItem>)item
{
    if (item == _item)
        return;
    [_item release];
    _item = [item retain];
    [self _build];
}
- (void)refreshPreviewItem { [self _build]; }
- (void)close
{
    _closed = YES;
    [self setPreviewItem:nil];
}

/* the header (icon, name, size) over the body, laid out to the view's size */
- (void)_build
{
    for (NSView *v in [[[self subviews] copy] autorelease])
        [v removeFromSuperview];
    if (!_item)
        return;
    NSRect b = [self bounds];
    NSString *path = path_of(_item);
    NSImage *icon = path ? [[NSWorkspace sharedWorkspace] iconForFile:path] : nil;
    BOOL compact = _style == QLPreviewViewStyleCompact;
    CGFloat top = 0;
    if (!compact) {
        NSImageView *iv = [[[NSImageView alloc] initWithFrame:NSMakeRect(12, 8, 48, 48)] autorelease];
        [iv setImage:icon];
        [iv setImageScaling:NSImageScaleProportionallyUpOrDown];
        [self addSubview:iv];
        NSTextField *name = [NSTextField labelWithString:title_of(_item) ?: @""];
        [name setFont:[NSFont boldSystemFontOfSize:13]];
        [name setFrame:NSMakeRect(70, 12, NSWidth(b) - 82, 18)];
        [name setAutoresizingMask:NSViewWidthSizable];
        [self addSubview:name];
        NSTextField *details = [NSTextField labelWithString:details_of(path)];
        [details setFont:[NSFont systemFontOfSize:11]];
        [details setTextColor:[NSColor secondaryLabelColor]];
        [details setFrame:NSMakeRect(70, 32, NSWidth(b) - 82, 16)];
        [details setAutoresizingMask:NSViewWidthSizable];
        [self addSubview:details];
        top = 64;
    }
    NSRect body = NSMakeRect(12, top, MAX(NSWidth(b) - 24, 1), MAX(NSHeight(b) - top - 12, 1));
    NSImage *picture = picture_at(path);
    NSString *text = picture ? nil : text_at(path);
    if (picture || !text) {
        NSImageView *iv = [[[NSImageView alloc] initWithFrame:body] autorelease];
        if (picture) {
            [iv setImage:picture];
            [iv setImageScaling:NSImageScaleProportionallyDown];
        } else {
            /* no preview: the icon, larger */
            [iv setImage:icon];
            [iv setImageScaling:NSImageScaleProportionallyUpOrDown];
            CGFloat side = MIN(128, MIN(NSWidth(body), NSHeight(body)));
            [iv setFrame:NSMakeRect(NSMidX(body) - side / 2, NSMidY(body) - side / 2, side, side)];
        }
        [iv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self addSubview:iv];
        return;
    }
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:body] autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    NSSize inner = [scroll contentSize];
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, inner.width, inner.height)] autorelease];
    [tv setEditable:NO];
    [tv setSelectable:YES];
    [tv setRichText:NO];
    [tv setFont:[NSFont userFixedPitchFontOfSize:11]];
    [tv setAutoresizingMask:NSViewWidthSizable];
    [tv setString:text];
    [scroll setDocumentView:tv];
    [self addSubview:scroll];
}
@end

/* ---- QLPreviewPanel ---- */

static QLPreviewPanel *shared_panel;

@implementation QLPreviewPanel {
    QLPreviewView *_preview;
    id _controller;
    id<QLPreviewPanelDataSource> _dataSource;
    NSInteger _index, _count;
    id _displayState;
    BOOL _fullScreen;
    NSRect _windowedFrame;
}
@dynamic delegate;
@synthesize displayState = _displayState;

+ (QLPreviewPanel *)sharedPreviewPanel
{
    if (!shared_panel) {
        shared_panel = [[QLPreviewPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, 520, 440)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable |
                                NSWindowStyleMaskUtilityWindow
                        backing:NSBackingStoreBuffered
                          defer:YES];
        [shared_panel setReleasedWhenClosed:NO];
        [shared_panel setFloatingPanel:YES];
        [shared_panel setTitle:@"Quick Look"];
        shared_panel->_preview =
            [[QLPreviewView alloc] initWithFrame:[[shared_panel contentView] bounds] style:QLPreviewViewStyleNormal];
        [shared_panel->_preview setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [shared_panel setContentView:shared_panel->_preview];
        [shared_panel center];
    }
    return shared_panel;
}
+ (BOOL)sharedPreviewPanelExists { return shared_panel != nil; }

- (void)dealloc
{
    [_preview release];
    [_controller release];
    [_displayState release];
    [super dealloc];
}

- (id)currentController { return _controller; }
- (id<QLPreviewPanelDataSource>)dataSource { return _dataSource; }
- (void)setDataSource:(id<QLPreviewPanelDataSource>)source
{
    _dataSource = source;
    [self reloadData];
}

/* the first that accepts: the main window's responder chain, the window,
 * its controller and delegate, then the application and its delegate */
- (id)_findController
{
    NSWindow *w = [NSApp mainWindow];
    if (!w || w == self)
        w = [NSApp keyWindow] == self ? nil : [NSApp keyWindow];
    NSMutableArray *chain = [NSMutableArray array];
    for (NSResponder *r = [w firstResponder]; r; r = [r nextResponder])
        if (![chain containsObject:r])
            [chain addObject:r];
    for (id o in @[ w ?: [NSNull null], [w windowController] ?: [NSNull null], (id)[w delegate] ?: [NSNull null],
                    NSApp ?: [NSNull null], (id)[NSApp delegate] ?: [NSNull null] ])
        if (o != [NSNull null] && ![chain containsObject:o])
            [chain addObject:o];
    for (id o in chain)
        if ([o respondsToSelector:@selector(acceptsPreviewPanelControl:)] && [o acceptsPreviewPanelControl:self])
            return o;
    return nil;
}

- (void)_setController:(id)c
{
    if (c == _controller)
        return;
    id old = _controller;
    _controller = nil;
    if ([old respondsToSelector:@selector(endPreviewPanelControl:)])
        [old endPreviewPanelControl:self];
    [old release];
    if (c) {
        _controller = [c retain];
        if ([c respondsToSelector:@selector(beginPreviewPanelControl:)])
            [c beginPreviewPanelControl:self];
    }
    [self reloadData];
}
- (void)updateController { [self _setController:[self isVisible] ? [self _findController] : nil]; }

- (void)_show
{
    id<QLPreviewItem> item = [self currentPreviewItem];
    [_preview setPreviewItem:item];
    [self setTitle:item ? title_of(item) : @"Quick Look"];
}
- (void)reloadData
{
    _count = [_dataSource respondsToSelector:@selector(numberOfPreviewItemsInPreviewPanel:)]
                 ? MAX([_dataSource numberOfPreviewItemsInPreviewPanel:self], 0)
                 : 0;
    if (_index >= _count)
        _index = _count ? _count - 1 : 0;
    [self _show];
}
- (void)refreshCurrentPreviewItem { [_preview refreshPreviewItem]; }
- (NSInteger)currentPreviewItemIndex { return _index; }
- (void)setCurrentPreviewItemIndex:(NSInteger)index
{
    _index = MAX(0, MIN(index, _count - 1));
    [self _show];
}
- (id<QLPreviewItem>)currentPreviewItem
{
    if (_index >= _count || ![_dataSource respondsToSelector:@selector(previewPanel:previewItemAtIndex:)])
        return nil;
    return [_dataSource previewPanel:self previewItemAtIndex:_index];
}

/* shown: find the controller; put away: tell it it's done */
- (void)orderFront:(id)sender
{
    BOOL was = [self isVisible];
    [super orderFront:sender];
    if (!was)
        [self updateController];
}
- (void)orderOut:(id)sender
{
    BOOL was = [self isVisible];
    [super orderOut:sender];
    if (was)
        [self _setController:nil];
}
/* closing keeps the shared panel for next time */
- (void)close
{
    if (_fullScreen)
        [self exitFullScreenModeWithOptions:nil];
    [self orderOut:nil];
}

- (BOOL)_handleKey:(NSEvent *)e
{
    NSString *c = [e charactersIgnoringModifiers];
    unichar ch = [c length] ? [c characterAtIndex:0] : 0;
    switch (ch) {
    case NSLeftArrowFunctionKey:
        if (_index > 0)
            [self setCurrentPreviewItemIndex:_index - 1];
        return YES;
    case NSRightArrowFunctionKey:
        if (_index + 1 < _count)
            [self setCurrentPreviewItemIndex:_index + 1];
        return YES;
    case 0x1b:
    case ' ':
        [self close];
        return YES;
    default: return NO;
    }
}
- (void)sendEvent:(NSEvent *)e
{
    if ([e type] == NSEventTypeKeyDown) {
        id d = [self delegate];
        if ([d respondsToSelector:@selector(previewPanel:handleEvent:)] && [d previewPanel:self handleEvent:e])
            return;
        if ([self _handleKey:e])
            return;
    }
    [super sendEvent:e];
}

- (BOOL)enterFullScreenMode:(NSScreen *)screen withOptions:(NSDictionary *)options
{
    if (_fullScreen)
        return YES;
    _windowedFrame = [self frame];
    _fullScreen = YES;
    [self setFrame:[screen ?: [NSScreen mainScreen] frame] display:YES];
    return YES;
}
- (void)exitFullScreenModeWithOptions:(NSDictionary *)options
{
    if (!_fullScreen)
        return;
    _fullScreen = NO;
    [self setFrame:_windowedFrame display:YES];
}
- (BOOL)isInFullScreenMode { return _fullScreen; }
@end

@implementation NSURL (QLPreviewConvenienceAdditions)
- (NSURL *)previewItemURL { return self; }
@end

/* ---- the generator's requests ---- */

@interface AQLRequest : NSObject {
@public
    NSURL *url;
    NSDictionary *options, *properties;
    NSString *uti, *resultUTI;
    CGSize maxSize;
    BOOL cancelled;
    NSData *data;
    NSURL *resultURL;
    CGImageRef image;
}
@end
@implementation AQLRequest
- (void)dealloc
{
    [url release];
    [options release];
    [properties release];
    [uti release];
    [resultUTI release];
    [data release];
    [resultURL release];
    CGImageRelease(image);
    [super dealloc];
}
@end
#define REQ(r) ((AQLRequest *)(r))

static void keep(AQLRequest *r, NSData *d, NSURL *u, NSString *type, NSDictionary *props)
{
    if (!r)
        return;
    [r->data release];
    r->data = [d copy];
    [r->resultURL release];
    r->resultURL = [u copy];
    [r->resultUTI release];
    r->resultUTI = [type copy];
    [r->properties release];
    r->properties = [props copy];
}

static CGContextRef bitmap_context(CGSize size)
{
    size_t w = (size_t)MAX(ceil(size.width), 1), h = (size_t)MAX(ceil(size.height), 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    return c;
}

static void flush(AQLRequest *r, CGContextRef c)
{
    if (!r || !c)
        return;
    CGImageRelease(r->image);
    r->image = CGBitmapContextCreateImage(c);
}

CFTypeID QLPreviewRequestGetTypeID(void) { return 0x514c0001; }
CFURLRef QLPreviewRequestCopyURL(QLPreviewRequestRef p) { return p ? (CFURLRef)[REQ(p)->url copy] : NULL; }
CFDictionaryRef QLPreviewRequestCopyOptions(QLPreviewRequestRef p)
{
    return p ? (CFDictionaryRef)[REQ(p)->options copy] : NULL;
}
CFStringRef QLPreviewRequestCopyContentUTI(QLPreviewRequestRef p) { return p ? (CFStringRef)[REQ(p)->uti copy] : NULL; }
CFBundleRef QLPreviewRequestGetGeneratorBundle(QLPreviewRequestRef p) { return NULL; }
Boolean QLPreviewRequestIsCancelled(QLPreviewRequestRef p) { return p && REQ(p)->cancelled; }
void QLPreviewRequestSetDataRepresentation(QLPreviewRequestRef p, CFDataRef data, CFStringRef type, CFDictionaryRef props)
{
    keep(REQ(p), (NSData *)data, nil, (NSString *)type, (NSDictionary *)props);
}
void QLPreviewRequestSetURLRepresentation(QLPreviewRequestRef p, CFURLRef url, CFStringRef type, CFDictionaryRef props)
{
    keep(REQ(p), nil, (NSURL *)url, (NSString *)type, (NSDictionary *)props);
}
CGContextRef QLPreviewRequestCreateContext(QLPreviewRequestRef p, CGSize size, Boolean isBitmap, CFDictionaryRef props)
{
    return bitmap_context(size);
}
/* there are no PDF contexts here: a picture of the page's size instead */
CGContextRef QLPreviewRequestCreatePDFContext(QLPreviewRequestRef p, const CGRect *mediaBox, CFDictionaryRef aux,
                                              CFDictionaryRef props)
{
    return bitmap_context(mediaBox ? mediaBox->size : CGSizeMake(612, 792));
}
void QLPreviewRequestFlushContext(QLPreviewRequestRef p, CGContextRef c) { flush(REQ(p), c); }

CFTypeID QLThumbnailRequestGetTypeID(void) { return 0x514c0002; }
CFURLRef QLThumbnailRequestCopyURL(QLThumbnailRequestRef t) { return t ? (CFURLRef)[REQ(t)->url copy] : NULL; }
CFDictionaryRef QLThumbnailRequestCopyOptions(QLThumbnailRequestRef t)
{
    return t ? (CFDictionaryRef)[REQ(t)->options copy] : NULL;
}
CFStringRef QLThumbnailRequestCopyContentUTI(QLThumbnailRequestRef t)
{
    return t ? (CFStringRef)[REQ(t)->uti copy] : NULL;
}
CGSize QLThumbnailRequestGetMaximumSize(QLThumbnailRequestRef t) { return t ? REQ(t)->maxSize : CGSizeZero; }
CFBundleRef QLThumbnailRequestGetGeneratorBundle(QLThumbnailRequestRef t) { return NULL; }
Boolean QLThumbnailRequestIsCancelled(QLThumbnailRequestRef t) { return t && REQ(t)->cancelled; }
void QLThumbnailRequestSetImage(QLThumbnailRequestRef t, CGImageRef image, CFDictionaryRef props)
{
    if (!t)
        return;
    CGImageRetain(image);
    CGImageRelease(REQ(t)->image);
    REQ(t)->image = image;
    keep(REQ(t), nil, nil, nil, (NSDictionary *)props);
}
void QLThumbnailRequestSetImageWithData(QLThumbnailRequestRef t, CFDataRef data, CFDictionaryRef props)
{
    keep(REQ(t), (NSData *)data, nil, nil, (NSDictionary *)props);
}
void QLThumbnailRequestSetImageAtURL(QLThumbnailRequestRef t, CFURLRef url, CFDictionaryRef props)
{
    keep(REQ(t), nil, (NSURL *)url, nil, (NSDictionary *)props);
}
CGContextRef QLThumbnailRequestCreateContext(QLThumbnailRequestRef t, CGSize size, Boolean isBitmap,
                                             CFDictionaryRef props)
{
    return bitmap_context(size);
}
void QLThumbnailRequestFlushContext(QLThumbnailRequestRef t, CGContextRef c) { flush(REQ(t), c); }
void QLThumbnailRequestSetThumbnailWithDataRepresentation(QLThumbnailRequestRef t, CFDataRef data, CFStringRef type,
                                                          CFDictionaryRef previewProps, CFDictionaryRef props)
{
    keep(REQ(t), (NSData *)data, nil, (NSString *)type, (NSDictionary *)previewProps);
}
void QLThumbnailRequestSetThumbnailWithURLRepresentation(QLThumbnailRequestRef t, CFURLRef url, CFStringRef type,
                                                         CFDictionaryRef previewProps, CFDictionaryRef props)
{
    keep(REQ(t), nil, (NSURL *)url, (NSString *)type, (NSDictionary *)previewProps);
}

/* ---- thumbnails ---- */

CGImageRef QLThumbnailImageCreate(CFAllocatorRef allocator, CFURLRef url, CGSize maxSize, CFDictionaryRef options)
{
    NSString *path = [(NSURL *)url isFileURL] ? [(NSURL *)url path] : nil;
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path] || maxSize.width < 1 || maxSize.height < 1)
        return NULL;
    BOOL iconMode = [[(NSDictionary *)options objectForKey:(NSString *)kQLThumbnailOptionIconModeKey] boolValue];
    CGFloat scale = [[(NSDictionary *)options objectForKey:(NSString *)kQLThumbnailOptionScaleFactorKey] doubleValue];
    if (scale <= 0)
        scale = 1;
    NSImage *image = iconMode ? [[NSWorkspace sharedWorkspace] iconForFile:path] : picture_at(path);
    if (!image)
        return NULL;
    NSSize s = [image size];
    if (iconMode)
        s = NSMakeSize(MAX(maxSize.width, maxSize.height), MAX(maxSize.width, maxSize.height));
    /* as large as fits, keeping its shape; a picture is never made larger */
    CGFloat f = MIN(maxSize.width / s.width, maxSize.height / s.height);
    if (!iconMode && f > 1)
        f = 1;
    CGSize out = CGSizeMake(MAX(round(s.width * f * scale), 1), MAX(round(s.height * f * scale), 1));
    NSRect r = NSMakeRect(0, 0, out.width, out.height);
    CGImageRef cg = [image CGImageForProposedRect:&r context:nil hints:nil];
    if (!cg)
        return NULL;
    CGContextRef c = bitmap_context(out);
    CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
    CGContextDrawImage(c, CGRectMake(0, 0, out.width, out.height), cg);
    CGImageRef result = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    return result;
}

/* ---- QCView ---- */

@implementation QCView {
    NSColor *_eraseColor;
    BOOL _autostarts;
    float _maxRate;
}
@synthesize autostartsRendering = _autostarts, maxRenderingFrameRate = _maxRate;

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        _eraseColor = [[NSColor blackColor] retain];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        id color = [coder allowsKeyedCoding] ? [coder decodeObjectForKey:@"NSEraseColor"] : nil;
        _eraseColor = [([color isKindOfClass:[NSColor class]] ? color : [NSColor blackColor]) retain];
        if ([coder allowsKeyedCoding])
            _autostarts = [coder decodeBoolForKey:@"NSAutostartsRendering"];
    }
    return self;
}
- (void)dealloc
{
    [_eraseColor release];
    [super dealloc];
}
- (void)drawRect:(NSRect)dirty
{
    [_eraseColor setFill];
    NSRectFill(dirty);
}
- (BOOL)loadCompositionFromFile:(NSString *)path
{
    AWarnOnce("running a Quartz Composer composition (QCView)");
    return NO;
}
- (BOOL)loadComposition:(QCComposition *)composition { return [self loadCompositionFromFile:nil]; }
- (QCComposition *)loadedComposition { return nil; }
- (void)unloadComposition {}
- (BOOL)startRendering { return NO; }
- (void)stopRendering {}
- (BOOL)isRendering { return NO; }
- (void)pauseRendering {}
- (void)resumeRendering {}
- (BOOL)isPausedRendering { return NO; }
- (IBAction)start:(id)sender { [self startRendering]; }
- (IBAction)stop:(id)sender { [self stopRendering]; }
- (IBAction)play:(id)sender { [self startRendering]; }
- (NSColor *)eraseColor { return _eraseColor; }
- (void)setEraseColor:(NSColor *)color
{
    [_eraseColor autorelease];
    _eraseColor = [color retain];
    [self setNeedsDisplay:YES];
}
- (void)erase { [self setNeedsDisplay:YES]; }
- (NSImage *)snapshotImage
{
    NSImage *image = [[[NSImage alloc] initWithSize:[self bounds].size] autorelease];
    [image lockFocus];
    [_eraseColor setFill];
    NSRectFill([self bounds]);
    [image unlockFocus];
    return image;
}
- (id)createSnapshotImageOfType:(NSString *)type { return [[self snapshotImage] retain]; }
- (BOOL)setValue:(id)value forInputKey:(NSString *)key { return NO; }
- (id)valueForInputKey:(NSString *)key { return nil; }
- (id)valueForOutputKey:(NSString *)key { return nil; }
@end
