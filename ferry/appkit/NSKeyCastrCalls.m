/* SPDX-License-Identifier: GPL-3.0-or-later
 * The AppKit calls KeyCastr and its ShortcutRecorder make (freemac 1.224,
 * Ferry 0.48.0), as AppKitMore.h describes them: the layout direction and
 * control tint, which are fixed here; window frames kept in the user
 * defaults by name; a relative curve; drawing a layout manager's text; and
 * launching an app bundle at a URL. Written for freemac from Apple's public
 * API documentation. Built without ARC. */
#import "AInternal.h"
#import <objc/runtime.h>

@interface NSTextLayoutManager (FerryContentManager)
- (void)ferrySetContentManager:(id)manager;
@end

@implementation NSApplication (FerryLayoutDirection)
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection { return NSUserInterfaceLayoutDirectionLeftToRight; }
@end

static char layout_direction_key, control_tint_key, can_hide_key;

@implementation NSView (FerryLayoutDirection)
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection
{
    return [objc_getAssociatedObject(self, &layout_direction_key) integerValue];
}
- (void)setUserInterfaceLayoutDirection:(NSUserInterfaceLayoutDirection)d
{
    objc_setAssociatedObject(self, &layout_direction_key, d ? @(d) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static BOOL ignores_alpha = YES;

@implementation NSColor (FerryControlTint)
+ (NSControlTint)currentControlTint { return NSBlueControlTint; }
+ (NSColor *)colorForControlTint:(NSControlTint)tint
{
    if (tint == NSGraphiteControlTint)
        return [NSColor colorWithSRGBRed:0.56 green:0.6 blue:0.65 alpha:1];
    if (tint == NSClearControlTint)
        return [NSColor clearColor];
    return [NSColor colorWithSRGBRed:0.04 green:0.4 blue:0.88 alpha:1];
}
+ (BOOL)ignoresAlpha { return ignores_alpha; }
+ (void)setIgnoresAlpha:(BOOL)flag { ignores_alpha = flag; }
@end

@implementation NSCell (FerryControlTint)
- (NSControlTint)controlTint { return [objc_getAssociatedObject(self, &control_tint_key) unsignedIntegerValue]; }
- (void)setControlTint:(NSControlTint)tint
{
    objc_setAssociatedObject(self, &control_tint_key, tint ? @(tint) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* ---- window frames by name --------------------------------------------------- */

static NSString *frame_key(NSString *name) { return [@"NSWindow Frame " stringByAppendingString:name]; }

@implementation NSWindow (FerryFrameNames)
/* "x y width height", then the screen's frame, as a Mac writes it */
- (NSString *)stringWithSavedFrame
{
    NSRect f = [self frame], s = [[NSScreen mainScreen] frame];
    return [NSString stringWithFormat:@"%.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f ", f.origin.x, f.origin.y,
                                      f.size.width, f.size.height, s.origin.x, s.origin.y, s.size.width,
                                      s.size.height];
}
- (void)setFrameFromString:(NSString *)string
{
    NSArray *parts = [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
        componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *nums = [NSMutableArray array];
    for (NSString *p in parts)
        if ([p length])
            [nums addObject:p];
    if ([nums count] < 4)
        return;
    NSRect f = NSMakeRect([nums[0] doubleValue], [nums[1] doubleValue], [nums[2] doubleValue], [nums[3] doubleValue]);
    if (f.size.width <= 0 || f.size.height <= 0)
        return;
    if (!([self styleMask] & NSWindowStyleMaskResizable)) {
        /* a window that can't be resized keeps its size; only its place
         * moves */
        f.size = [self frame].size;
    }
    [self setFrame:f display:YES];
}
- (BOOL)setFrameUsingName:(NSString *)name force:(BOOL)force
{
    if (![name length])
        return NO;
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:frame_key(name)];
    if (![s length])
        return NO;
    [self setFrameFromString:s];
    return YES;
}
- (void)saveFrameUsingName:(NSString *)name
{
    if ([name length])
        [[NSUserDefaults standardUserDefaults] setObject:[self stringWithSavedFrame] forKey:frame_key(name)];
}
+ (void)removeFrameUsingName:(NSString *)name
{
    if ([name length])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:frame_key(name)];
}
- (BOOL)canHide
{
    NSNumber *n = objc_getAssociatedObject(self, &can_hide_key);
    return n ? [n boolValue] : YES;
}
- (void)setCanHide:(BOOL)flag
{
    objc_setAssociatedObject(self, &can_hide_key, flag ? nil : @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static char tool_tip_tag_key;
static NSInteger last_tool_tip_tag;

@implementation NSView (FerryToolTipRects)
- (NSToolTipTag)addToolTipRect:(NSRect)rect owner:(id)owner userData:(void *)data
{
    NSToolTipTag tag;
    @synchronized([NSView class]) {
        tag = ++last_tool_tip_tag;
    }
    NSString *tip = nil;
    if ([owner isKindOfClass:[NSString class]])
        tip = owner;
    else if ([owner respondsToSelector:@selector(view:stringForToolTip:point:userData:)])
        tip = [owner view:self stringForToolTip:tag point:NSMakePoint(NSMidX(rect), NSMidY(rect)) userData:data];
    if ([tip isKindOfClass:[NSString class]]) {
        [self setToolTip:tip];
        objc_setAssociatedObject(self, &tool_tip_tag_key, @(tag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return tag;
}
- (void)removeToolTip:(NSToolTipTag)tag
{
    if ([objc_getAssociatedObject(self, &tool_tip_tag_key) integerValue] == tag && tag)
        [self removeAllToolTips];
}
- (void)removeAllToolTips
{
    if (objc_getAssociatedObject(self, &tool_tip_tag_key)) {
        objc_setAssociatedObject(self, &tool_tip_tag_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self setToolTip:nil];
    }
}
@end

@implementation NSBezierPath (FerryRelativeCurve)
- (void)relativeCurveToPoint:(NSPoint)p controlPoint1:(NSPoint)a controlPoint2:(NSPoint)b
{
    NSPoint c = [self currentPoint];
    [self curveToPoint:NSMakePoint(c.x + p.x, c.y + p.y) controlPoint1:NSMakePoint(c.x + a.x, c.y + a.y)
         controlPoint2:NSMakePoint(c.x + b.x, c.y + b.y)];
}
@end

@implementation NSLayoutManager (FerryDrawing)
- (void)drawGlyphsForGlyphRange:(NSRange)range atPoint:(NSPoint)origin
{
    NSTextStorage *storage = [self textStorage];
    NSUInteger len = [storage length];
    if (range.location >= len || !range.length)
        return;
    if (NSMaxRange(range) > len)
        range.length = len - range.location;
    NSTextContainer *tc = [[self textContainers] firstObject];
    NSSize size = tc ? [tc containerSize] : NSMakeSize(1e7, 1e7);
    if (size.width <= 0 || size.width > 1e6)
        size.width = 1e7;
    if (size.height <= 0 || size.height > 1e6)
        size.height = 1e7;
    CGFloat pad = tc ? [tc lineFragmentPadding] : 0;
    NSRect r = NSMakeRect(origin.x + pad, origin.y, size.width - 2 * pad, size.height);
    [[storage attributedSubstringFromRange:range] drawInRect:r];
}
/* The text's background colours are drawn with its glyphs. */
- (void)drawBackgroundForGlyphRange:(NSRange)range atPoint:(NSPoint)origin {}
@end

/* ---- launching an app ---------------------------------------------------------- */

NSWorkspaceLaunchConfigurationKey const NSWorkspaceLaunchConfigurationArguments = @"NSWorkspaceLaunchConfigurationArguments";
NSWorkspaceLaunchConfigurationKey const NSWorkspaceLaunchConfigurationEnvironment = @"NSWorkspaceLaunchConfigurationEnvironment";

static NSError *launch_error(NSURL *url, NSString *why)
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                           userInfo:@{NSLocalizedDescriptionKey : why, NSURLErrorKey : url ?: [NSNull null]}];
}

@implementation NSWorkspace (FerryLaunching)
/* An app bundle's own program, started under Ferry by NSTask. The running
 * app this answers is the new process. Without NSWorkspaceLaunchNewInstance
 * the app itself, already running, is answered as it is. */
- (NSRunningApplication *)launchApplicationAtURL:(NSURL *)url options:(NSWorkspaceLaunchOptions)options
                                   configuration:(NSDictionary *)configuration
                                           error:(NSError **)error
{
    NSBundle *bundle = [url isFileURL] ? [NSBundle bundleWithURL:url] : nil;
    NSString *exe = [bundle executablePath];
    if (!exe || ![[NSFileManager defaultManager] isExecutableFileAtPath:exe]) {
        if (error)
            *error = launch_error(url, @"The application can't be found.");
        return nil;
    }
    if (!(options & NSWorkspaceLaunchNewInstance) &&
        [[[bundle bundleURL] URLByStandardizingPath] isEqual:[[[NSBundle mainBundle] bundleURL] URLByStandardizingPath]])
        return [NSRunningApplication currentApplication];
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setExecutableURL:[NSURL fileURLWithPath:exe]];
    id args = configuration[NSWorkspaceLaunchConfigurationArguments];
    if ([args isKindOfClass:[NSArray class]])
        [task setArguments:args];
    id env = configuration[NSWorkspaceLaunchConfigurationEnvironment];
    if ([env isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *all = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
        [all addEntriesFromDictionary:env];
        [task setEnvironment:all];
    }
    NSError *why = nil;
    if (![task launchAndReturnError:&why]) {
        if (error)
            *error = why ?: launch_error(url, @"The application couldn't be started.");
        return nil;
    }
    return [NSRunningApplication runningApplicationWithProcessIdentifier:[task processIdentifier]];
}
- (void)openApplicationAtURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)configuration
           completionHandler:(void (^)(NSRunningApplication *, NSError *))handler
{
    NSMutableDictionary *conf = [NSMutableDictionary dictionary];
    if ([configuration arguments])
        conf[NSWorkspaceLaunchConfigurationArguments] = [configuration arguments];
    NSError *error = nil;
    NSRunningApplication *app =
        [self launchApplicationAtURL:url
                             options:[configuration createsNewApplicationInstance] ? NSWorkspaceLaunchNewInstance : 0
                       configuration:conf
                               error:&error];
    if (handler)
        handler(app, error);
}
@end

/* ---- what ShortcutRecorder's recorder control asks of AppKit ---- */

@implementation NSObject (FerryBindingOptions)
- (NSArray *)optionDescriptionsForBinding:(NSBindingName)binding { return @[]; }
@end

NSNotificationName const NSControlTintDidChangeNotification = @"NSControlTintDidChangeNotification";
NSNotificationName const NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification =
    @"NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification";

@implementation NSWorkspace (FerryAccessibilityDisplay)
- (BOOL)accessibilityDisplayShouldIncreaseContrast { return NO; }
- (BOOL)accessibilityDisplayShouldDifferentiateWithoutColor { return NO; }
- (BOOL)accessibilityDisplayShouldReduceTransparency { return NO; }
- (BOOL)accessibilityDisplayShouldReduceMotion { return NO; }
- (BOOL)accessibilityDisplayShouldInvertColors { return NO; }
/* VoiceOver and Switch Control are a Mac's own (freemac Godot work) */
- (BOOL)isVoiceOverEnabled { return NO; }
- (BOOL)isSwitchControlEnabled { return NO; }
@end

@implementation NSView (FerryReuse)
- (void)prepareForReuse {}
- (void)viewDidChangeEffectiveAppearance {}
- (void)noteFocusRingMaskChanged {}
- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
    return [self toolTip];
}
@end

@interface NSStringDrawingContext (FerryBounds)
- (void)ferrySetTotalBounds:(NSRect)r;
@end
@implementation NSStringDrawingContext {
    CGFloat _minimumScaleFactor;
    NSRect _totalBounds;
}
- (CGFloat)minimumScaleFactor { return _minimumScaleFactor; }
- (void)setMinimumScaleFactor:(CGFloat)f { _minimumScaleFactor = f; }
- (CGFloat)actualScaleFactor { return 1.0; }
- (NSRect)totalBounds { return _totalBounds; }
- (void)ferrySetTotalBounds:(NSRect)r { _totalBounds = r; }
@end

@implementation NSString (FerryDrawingContext)
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options
          attributes:(NSDictionary *)attributes context:(NSStringDrawingContext *)context
{
    [self drawInRect:rect withAttributes:attributes];
    [context ferrySetTotalBounds:[self boundingRectWithSize:rect.size options:options attributes:attributes]];
}
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options
                    attributes:(NSDictionary *)attributes context:(NSStringDrawingContext *)context
{
    NSRect r = [self boundingRectWithSize:size options:options attributes:attributes];
    [context ferrySetTotalBounds:r];
    return r;
}
@end

@implementation NSAttributedString (FerryDrawingContext)
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options context:(NSStringDrawingContext *)context
{
    [self drawInRect:rect];
    [context ferrySetTotalBounds:[self boundingRectWithSize:rect.size options:options]];
}
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options
                       context:(NSStringDrawingContext *)context
{
    NSRect r = [self boundingRectWithSize:size options:options];
    [context ferrySetTotalBounds:r];
    return r;
}
@end

@implementation NSColor (FerryCatalog)
+ (NSColor *)colorWithCatalogName:(NSString *)list colorName:(NSString *)name
{
    /* only NSColor's own class methods named for a colour, which take nothing */
    if (![list isEqual:@"System"] || ![name hasSuffix:@"Color"] || [name rangeOfString:@":"].location != NSNotFound)
        return nil;
    SEL sel = NSSelectorFromString(name);
    if (![NSColor respondsToSelector:sel])
        return nil;
    id color = ((id (*)(id, SEL))objc_msgSend)([NSColor class], sel);
    return [color isKindOfClass:[NSColor class]] ? color : nil;
}
/* A system colour (one that changes with the appearance, freemac 1.245) is
 * in the System list under its name; other colours are in none. */
- (NSString *)catalogNameComponent { return [self _ferryDynamicName] ? @"System" : nil; }
- (NSString *)colorNameComponent { return [self _ferryDynamicName]; }
- (NSString *)localizedCatalogNameComponent { return [self catalogNameComponent]; }
- (NSString *)localizedColorNameComponent { return [self colorNameComponent]; }
@end

@implementation NSMenuItem (FerryParentItem)
- (NSMenuItem *)parentItem
{
    NSMenu *menu = [self menu];
    for (NSMenuItem *item in [[menu supermenu] itemArray])
        if ([item submenu] == menu)
            return item;
    return nil;
}
@end

/* ---- what Sparkle 2's windows ask of AppKit ---- */

@implementation NSLayoutConstraint (FerryAnimator)
- (instancetype)animator { return AAnimatorFor(self); }
- (NSDictionary *)animations { return @{}; }
- (void)setAnimations:(NSDictionary *)animations {}
- (id)animationForKey:(NSString *)key { return nil; }
+ (id)defaultAnimationForKey:(NSString *)key { return nil; }
@end

static char adaptive_color_key;
@implementation NSTextView (FerryAdaptiveColor)
- (BOOL)usesAdaptiveColorMappingForDarkAppearance
{
    return [objc_getAssociatedObject(self, &adaptive_color_key) boolValue];
}
- (void)setUsesAdaptiveColorMappingForDarkAppearance:(BOOL)b
{
    objc_setAssociatedObject(self, &adaptive_color_key, b ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation NSTextLayoutManager {
    NSTextContainer *_container;
    id _manager;
}
- (void)dealloc
{
    [_container release];
    [super dealloc];
}
- (NSTextContainer *)textContainer { return _container; }
- (void)setTextContainer:(NSTextContainer *)c
{
    [c retain];
    [_container release];
    _container = c;
}
- (id)textContentManager { return _manager; }
- (void)ferrySetContentManager:(id)m { _manager = m; }
@end

@implementation NSTextContentManager {
    NSMutableArray *_layoutManagers;
}
- (void)dealloc
{
    for (NSTextLayoutManager *m in _layoutManagers)
        [m ferrySetContentManager:nil];
    [_layoutManagers release];
    [super dealloc];
}
- (NSArray *)textLayoutManagers { return [[_layoutManagers copy] autorelease] ?: @[]; }
- (void)addTextLayoutManager:(NSTextLayoutManager *)m
{
    if (!m || [_layoutManagers containsObject:m])
        return;
    if (!_layoutManagers)
        _layoutManagers = [[NSMutableArray alloc] init];
    [_layoutManagers addObject:m];
    [m ferrySetContentManager:self];
}
- (void)removeTextLayoutManager:(NSTextLayoutManager *)m
{
    if (![_layoutManagers containsObject:m])
        return;
    [m ferrySetContentManager:nil];
    [_layoutManagers removeObject:m];
}
@end

@implementation NSTextContentStorage {
    NSTextStorage *_storage;
}
- (void)dealloc
{
    [_storage release];
    [super dealloc];
}
- (NSTextStorage *)textStorage { return _storage; }
- (void)setTextStorage:(NSTextStorage *)s
{
    [s retain];
    [_storage release];
    _storage = s;
}
@end

/* ---- three- and nine-part images ---- */

static void draw_part(NSImage *image, NSRect r, NSCompositingOperation op, CGFloat alpha)
{
    if (image && r.size.width > 0 && r.size.height > 0)
        [image drawInRect:r fromRect:NSZeroRect operation:op fraction:alpha respectFlipped:YES hints:nil];
}

void NSDrawThreePartImage(NSRect frame, NSImage *start, NSImage *center, NSImage *end, BOOL vertical,
                          NSCompositingOperation op, CGFloat alpha, BOOL flipped)
{
    NSSize a = [start size], b = [end size];
    if (!vertical) {
        CGFloat h = frame.size.height;
        NSRect left = NSMakeRect(NSMinX(frame), NSMinY(frame), a.width, h);
        NSRect right = NSMakeRect(NSMaxX(frame) - b.width, NSMinY(frame), b.width, h);
        NSRect middle = NSMakeRect(NSMaxX(left), NSMinY(frame), NSMinX(right) - NSMaxX(left), h);
        draw_part(start, left, op, alpha);
        draw_part(center, middle, op, alpha);
        draw_part(end, right, op, alpha);
    } else {
        /* the start cap is at the top: the low end of y when flipped */
        CGFloat w = frame.size.width;
        NSRect top = flipped ? NSMakeRect(NSMinX(frame), NSMinY(frame), w, a.height)
                             : NSMakeRect(NSMinX(frame), NSMaxY(frame) - a.height, w, a.height);
        NSRect bottom = flipped ? NSMakeRect(NSMinX(frame), NSMaxY(frame) - b.height, w, b.height)
                                : NSMakeRect(NSMinX(frame), NSMinY(frame), w, b.height);
        NSRect middle = flipped ? NSMakeRect(NSMinX(frame), NSMaxY(top), w, NSMinY(bottom) - NSMaxY(top))
                                : NSMakeRect(NSMinX(frame), NSMaxY(bottom), w, NSMinY(top) - NSMaxY(bottom));
        draw_part(start, top, op, alpha);
        draw_part(center, middle, op, alpha);
        draw_part(end, bottom, op, alpha);
    }
}

void NSDrawNinePartImage(NSRect frame, NSImage *tl, NSImage *t, NSImage *tr, NSImage *l, NSImage *c, NSImage *r,
                         NSImage *bl, NSImage *b, NSImage *br, NSCompositingOperation op, CGFloat alpha,
                         BOOL flipped)
{
    NSSize tls = [tl size], brs = [br size];
    CGFloat x0 = NSMinX(frame), x1 = x0 + tls.width, x3 = NSMaxX(frame), x2 = x3 - brs.width;
    /* rows from the top: the top row's height is the top-left corner's */
    CGFloat topH = tls.height, bottomH = brs.height, midH = frame.size.height - topH - bottomH;
    CGFloat yTop = flipped ? NSMinY(frame) : NSMaxY(frame) - topH;
    CGFloat yMid = flipped ? NSMinY(frame) + topH : NSMinY(frame) + bottomH;
    CGFloat yBottom = flipped ? NSMaxY(frame) - bottomH : NSMinY(frame);
    draw_part(tl, NSMakeRect(x0, yTop, x1 - x0, topH), op, alpha);
    draw_part(t, NSMakeRect(x1, yTop, x2 - x1, topH), op, alpha);
    draw_part(tr, NSMakeRect(x2, yTop, x3 - x2, topH), op, alpha);
    draw_part(l, NSMakeRect(x0, yMid, x1 - x0, midH), op, alpha);
    draw_part(c, NSMakeRect(x1, yMid, x2 - x1, midH), op, alpha);
    draw_part(r, NSMakeRect(x2, yMid, x3 - x2, midH), op, alpha);
    draw_part(bl, NSMakeRect(x0, yBottom, x1 - x0, bottomH), op, alpha);
    draw_part(b, NSMakeRect(x1, yBottom, x2 - x1, bottomH), op, alpha);
    draw_part(br, NSMakeRect(x2, yBottom, x3 - x2, bottomH), op, alpha);
}

/* ---- MacDown's calls ---- */

NSAttributedStringKey const NSCursorAttributeName = @"NSCursor";

@implementation NSTextView (FerryMarkedText)
- (BOOL)hasMarkedText { return NO; }
- (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); }
- (void)unmarkText {}
@end
