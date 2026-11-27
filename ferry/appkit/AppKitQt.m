/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Qt's Mac platform plugin calls of AppKit and Carbon besides the rest
 * (AppKitQt.h, HIServices/Pasteboard.h, HIServices/Icons.h), for OBS Studio:
 * text input contexts, screen depths and colour spaces, key repeat, the
 * window list, panels' content types, Carbon's Pasteboard Manager over
 * NSPasteboard, and drawing Icon Services icons. */
#import "AInternal.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

/* ---- text input ------------------------------------------------------------------ */

@implementation NSTextInputContext {
    id<NSTextInputClient> _client; /* not retained: the client owns its context */
    NSArray *_locales;
}
@synthesize acceptsGlyphInfo = _acceptsGlyphInfo;

+ (NSTextInputContext *)currentInputContext
{
    id responder = [[NSApp keyWindow] firstResponder];
    return [responder isKindOfClass:[NSView class]] ? [(NSView *)responder inputContext] : nil;
}

- (instancetype)initWithClient:(id<NSTextInputClient>)client
{
    if ((self = [super init]))
        _client = client;
    return self;
}

- (void)dealloc
{
    [_locales release];
    [super dealloc];
}

- (id<NSTextInputClient>)client { return _client; }
- (NSArray *)allowedInputSourceLocales { return _locales; }
- (void)setAllowedInputSourceLocales:(NSArray *)locales
{
    [_locales autorelease];
    _locales = [locales copy];
}
- (void)activate { }
- (void)deactivate { }
- (void)invalidateCharacterCoordinates { }
- (void)discardMarkedText
{
    if ([(id)_client respondsToSelector:@selector(hasMarkedText)] && [_client hasMarkedText])
        [_client unmarkText];
}

- (BOOL)handleEvent:(NSEvent *)event
{
    if ([event type] != NSEventTypeKeyDown || !_client)
        return NO;
    NSString *chars = [event characters];
    NSEventModifierFlags f = [event modifierFlags];
    if (![chars length])
        return NO;
    SEL sel = [chars length] == 1 ? AKeyBindingCommand([chars characterAtIndex:0], f) : NULL;
    if (sel)
        [_client doCommandBySelector:sel];
    else if (!(f & (NSEventModifierFlagCommand | NSEventModifierFlagControl)))
        [_client insertText:chars replacementRange:NSMakeRange(NSNotFound, 0)];
    else
        [_client doCommandBySelector:@selector(noop:)];
    return YES;
}

- (NSArray *)keyboardInputSources
{
    NSString *s = [self selectedKeyboardInputSource];
    return s ? @[ s ] : @[];
}
- (NSString *)selectedKeyboardInputSource
{
    TISInputSourceRef src = TISCopyCurrentKeyboardInputSource();
    NSString *ident = src ? [[(NSString *)TISGetInputSourceProperty(src, kTISPropertyInputSourceID) copy] autorelease]
                          : nil;
    if (src)
        CFRelease(src);
    return ident;
}
- (void)setSelectedKeyboardInputSource:(NSString *)source { (void)source; }
+ (NSString *)localizedNameForInputSource:(NSString *)source
{
    return [[source componentsSeparatedByString:@"."] lastObject];
}
@end

@implementation NSView (FerryTextInput)
static char input_context_key;
- (NSTextInputContext *)inputContext
{
    if (![self conformsToProtocol:@protocol(NSTextInputClient)])
        return nil;
    NSTextInputContext *ctx = objc_getAssociatedObject(self, &input_context_key);
    if (!ctx) {
        ctx = [[[NSTextInputContext alloc] initWithClient:(id<NSTextInputClient>)self] autorelease];
        objc_setAssociatedObject(self, &input_context_key, ctx, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return ctx;
}
@end

/* ---- screens ----------------------------------------------------------------------- */

NSInteger NSBitsPerSampleFromDepth(NSWindowDepth depth) { return depth & 0xff; }
NSInteger NSBitsPerPixelFromDepth(NSWindowDepth depth)
{
    switch (depth) {
    case NSWindowDepthTwentyfourBitRGB: return 24;
    case NSWindowDepthSixtyfourBitRGB: return 64;
    case NSWindowDepthOnehundredtwentyeightBitRGB: return 128;
    default: return (depth & 0xff) * 3;
    }
}
NSInteger NSNumberOfColorComponents(NSString *name)
{
    if ([name isEqualToString:NSCalibratedWhiteColorSpace] || [name isEqualToString:NSDeviceWhiteColorSpace])
        return 1;
    if ([name rangeOfString:@"CMYK"].location != NSNotFound)
        return 4;
    return 3;
}

@implementation NSScreen (FerryDepth)
- (NSWindowDepth)depth { return NSWindowDepthTwentyfourBitRGB; }
- (const NSWindowDepth *)supportedWindowDepths
{
    static const NSWindowDepth depths[] = { NSWindowDepthTwentyfourBitRGB, 0 };
    return depths;
}
- (NSColorSpace *)colorSpace { return [NSColorSpace sRGBColorSpace]; }
+ (BOOL)screensHaveSeparateSpaces { return NO; }
- (CGFloat)maximumExtendedDynamicRangeColorComponentValue { return 1.0; }
- (CGFloat)maximumPotentialExtendedDynamicRangeColorComponentValue { return 1.0; }
- (CGFloat)maximumReferenceExtendedDynamicRangeColorComponentValue { return 0.0; }
@end

@implementation NSColorSpace (FerryICC)
- (instancetype)initWithICCProfileData:(NSData *)iccData
{
    CGColorSpaceRef cg = iccData ? CGColorSpaceCreateWithICCData((CFDataRef)iccData) : NULL;
    if (!cg) {
        [self release];
        return nil;
    }
    self = [self initWithCGColorSpace:cg];
    CGColorSpaceRelease(cg);
    return self;
}
- (NSData *)ICCProfileData
{
    CGColorSpaceRef cg = [self CGColorSpace];
    return cg ? [(NSData *)CGColorSpaceCopyICCData(cg) autorelease] : nil;
}
@end

/* ---- keys -------------------------------------------------------------------------- */

@implementation NSEvent (FerryKeyRepeat)
/* GNOME's defaults: 500 ms before a held key repeats, then 30 a second */
+ (NSTimeInterval)keyRepeatDelay { return 0.5; }
+ (NSTimeInterval)keyRepeatInterval { return 1.0 / 30.0; }
@end

/* ---- windows ----------------------------------------------------------------------- */

NSNotificationName const NSWindowWillStartLiveResizeNotification = @"NSWindowWillStartLiveResizeNotification";
NSNotificationName const NSWindowDidEndLiveResizeNotification = @"NSWindowDidEndLiveResizeNotification";

@implementation NSApplication (FerryWindowList)
- (void)enumerateWindowsWithOptions:(NSWindowListOptions)options
                         usingBlock:(void (^)(NSWindow *window, BOOL *stop))block
{
    if (!block)
        return;
    NSArray *list = [self windows];
    if (options & NSWindowListOrderedFrontToBack) {
        /* the windows on screen front to back, then the rest */
        NSMutableArray *ordered = [[[self orderedWindows] mutableCopy] autorelease];
        for (NSWindow *w in list)
            if (![ordered containsObject:w])
                [ordered addObject:w];
        list = ordered;
    }
    BOOL stop = NO;
    for (NSWindow *w in list) {
        block(w, &stop);
        if (stop)
            break;
    }
}
@end

/* ---- panels ------------------------------------------------------------------------ */

@implementation NSSavePanel (FerryContentTypes)
- (NSArray<UTType *> *)allowedContentTypes
{
    NSMutableArray *types = [NSMutableArray array];
    for (NSString *t in [self allowedFileTypes]) {
        UTType *u = [t rangeOfString:@"."].location != NSNotFound ? [UTType typeWithIdentifier:t]
                                                                   : [UTType typeWithFilenameExtension:t];
        if (u)
            [types addObject:u];
    }
    return types;
}
- (void)setAllowedContentTypes:(NSArray<UTType *> *)types
{
    NSMutableArray *names = [NSMutableArray array];
    for (UTType *u in types)
        if ([u identifier])
            [names addObject:[u identifier]];
    [self setAllowedFileTypes:[names count] ? names : nil];
}
@end

/* ---- the Pasteboard Manager ----------------------------------------------------------
 * A PasteboardRef wraps an NSPasteboard. Items are named by the identifiers
 * the program put them under, or else by their place, 1 for the first. A
 * flavor put with no data is a promise: a data provider that asks the
 * program's promise keeper for it when the flavor is first read. */

@interface APasteboardRef : NSObject {
@public
    NSPasteboard *pb;
    PasteboardPromiseKeeperProcPtr keeper;
    void *context;
    NSInteger seenChangeCount;
    NSMutableDictionary *items; /* identifier -> NSPasteboardItem the program put */
}
@end

@interface APasteboardPromise : NSObject <NSPasteboardItemDataProvider> {
@public
    APasteboardRef *ref; /* not retained */
    PasteboardItemID itemID;
}
@end

@implementation APasteboardRef
- (void)dealloc
{
    [pb release];
    [items release];
    [super dealloc];
}
@end

@implementation APasteboardPromise
- (void)pasteboard:(NSPasteboard *)pasteboard item:(NSPasteboardItem *)item provideDataForType:(NSPasteboardType)type
{
    (void)pasteboard;
    (void)item;
    if (ref && ref->keeper)
        ref->keeper((PasteboardRef)ref, itemID, (CFStringRef)type, ref->context);
}
- (void)pasteboardFinishedWithDataProvider:(NSPasteboard *)pasteboard { (void)pasteboard; }
@end

static APasteboardRef *pb_ref(PasteboardRef p) { return (APasteboardRef *)p; }

static NSPasteboardItem *pb_item(APasteboardRef *r, PasteboardItemID ident)
{
    NSPasteboardItem *item = [r->items objectForKey:[NSNumber numberWithUnsignedLong:(uintptr_t)ident]];
    if (item)
        return item;
    NSArray *all = [r->pb pasteboardItems];
    uintptr_t n = (uintptr_t)ident;
    return n >= 1 && n <= [all count] ? [all objectAtIndex:n - 1] : nil;
}

OSStatus PasteboardCreate(CFStringRef name, PasteboardRef *out)
{
    if (!out)
        return paramErr;
    NSPasteboard *pb;
    if (!name)
        pb = [NSPasteboard pasteboardWithUniqueName];
    else if ([(NSString *)name isEqualToString:@"com.apple.pasteboard.clipboard"])
        pb = [NSPasteboard generalPasteboard];
    else if ([(NSString *)name isEqualToString:@"com.apple.pasteboard.find"])
        pb = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    else
        pb = [NSPasteboard pasteboardWithName:(NSString *)name];
    APasteboardRef *r = [[APasteboardRef alloc] init];
    r->pb = [pb retain];
    r->items = [[NSMutableDictionary alloc] init];
    r->seenChangeCount = [pb changeCount];
    *out = (PasteboardRef)r;
    return noErr;
}

PasteboardSyncFlags PasteboardSynchronize(PasteboardRef p)
{
    APasteboardRef *r = pb_ref(p);
    if (!r)
        return 0;
    NSInteger now = [r->pb changeCount];
    if (now != r->seenChangeCount) {
        r->seenChangeCount = now;
        [r->items removeAllObjects];
        return kPasteboardModified;
    }
    return [r->items count] ? kPasteboardClientIsOwner : 0;
}

OSStatus PasteboardClear(PasteboardRef p)
{
    APasteboardRef *r = pb_ref(p);
    if (!r)
        return paramErr;
    [r->items removeAllObjects];
    r->seenChangeCount = [r->pb clearContents];
    return noErr;
}

OSStatus PasteboardCopyName(PasteboardRef p, CFStringRef *out)
{
    APasteboardRef *r = pb_ref(p);
    if (!r || !out)
        return paramErr;
    *out = (CFStringRef)[[r->pb name] copy];
    return noErr;
}

OSStatus PasteboardGetItemCount(PasteboardRef p, ItemCount *out)
{
    APasteboardRef *r = pb_ref(p);
    if (!r || !out)
        return paramErr;
    *out = [[r->pb pasteboardItems] count];
    return noErr;
}

OSStatus PasteboardGetItemIdentifier(PasteboardRef p, CFIndex index, PasteboardItemID *out)
{
    APasteboardRef *r = pb_ref(p);
    if (!r || !out)
        return paramErr;
    NSArray *all = [r->pb pasteboardItems];
    if (index < 1 || (NSUInteger)index > [all count])
        return badPasteboardIndexErr;
    NSPasteboardItem *item = [all objectAtIndex:index - 1];
    for (NSNumber *k in r->items)
        if ([r->items objectForKey:k] == item) {
            *out = (PasteboardItemID)(uintptr_t)[k unsignedLongValue];
            return noErr;
        }
    *out = (PasteboardItemID)(uintptr_t)index;
    return noErr;
}

OSStatus PasteboardCopyItemFlavors(PasteboardRef p, PasteboardItemID ident, CFArrayRef *out)
{
    APasteboardRef *r = pb_ref(p);
    if (!r || !out)
        return paramErr;
    NSPasteboardItem *item = pb_item(r, ident);
    if (!item)
        return badPasteboardItemErr;
    *out = (CFArrayRef)[[item types] copy];
    return noErr;
}

OSStatus PasteboardGetItemFlavorFlags(PasteboardRef p, PasteboardItemID ident, CFStringRef flavor,
                                      PasteboardFlavorFlags *out)
{
    APasteboardRef *r = pb_ref(p);
    if (!r || !flavor)
        return paramErr;
    NSPasteboardItem *item = pb_item(r, ident);
    if (!item)
        return badPasteboardItemErr;
    if (![[item types] containsObject:(NSString *)flavor])
        return badPasteboardFlavorErr;
    if (out)
        *out = kPasteboardFlavorNoFlags;
    return noErr;
}

OSStatus PasteboardCopyItemFlavorData(PasteboardRef p, PasteboardItemID ident, CFStringRef flavor, CFDataRef *out)
{
    APasteboardRef *r = pb_ref(p);
    if (!r || !flavor || !out)
        return paramErr;
    NSPasteboardItem *item = pb_item(r, ident);
    if (!item)
        return badPasteboardItemErr;
    if (![[item types] containsObject:(NSString *)flavor])
        return badPasteboardFlavorErr;
    NSData *d = [item dataForType:(NSString *)flavor];
    if (!d)
        return cantGetFlavorErr;
    *out = (CFDataRef)[d copy];
    return noErr;
}

OSStatus PasteboardPutItemFlavor(PasteboardRef p, PasteboardItemID ident, CFStringRef flavor, CFDataRef data,
                                 PasteboardFlavorFlags flags)
{
    (void)flags;
    APasteboardRef *r = pb_ref(p);
    if (!r || !flavor)
        return paramErr;
    NSNumber *key = [NSNumber numberWithUnsignedLong:(uintptr_t)ident];
    NSPasteboardItem *item = [r->items objectForKey:key];
    BOOL added = NO;
    if (!item) {
        if ([r->pb changeCount] != r->seenChangeCount)
            return notPasteboardOwnerErr;
        item = [[[NSPasteboardItem alloc] init] autorelease];
        [r->items setObject:item forKey:key];
        added = YES;
    }
    if (data) {
        [item setData:(NSData *)data forType:(NSString *)flavor];
    } else {
        APasteboardPromise *promise = [[[APasteboardPromise alloc] init] autorelease];
        promise->ref = r;
        promise->itemID = ident;
        [item setDataProvider:promise forTypes:@[ (NSString *)flavor ]];
    }
    /* adding the item, or writing nothing more, brings the desktop's
     * clipboard up to date with the first item's text */
    [r->pb writeObjects:added ? @[ item ] : @[]];
    r->seenChangeCount = [r->pb changeCount];
    return noErr;
}

OSStatus PasteboardSetPromiseKeeper(PasteboardRef p, PasteboardPromiseKeeperProcPtr keeper, void *context)
{
    APasteboardRef *r = pb_ref(p);
    if (!r)
        return paramErr;
    r->keeper = keeper;
    r->context = context;
    return noErr;
}

OSStatus PasteboardResolvePromises(PasteboardRef p)
{
    APasteboardRef *r = pb_ref(p);
    if (!r)
        return paramErr;
    if (!r->keeper)
        return noPasteboardPromiseKeeperErr;
    for (NSPasteboardItem *item in [r->items allValues])
        for (NSString *t in [item types])
            [item dataForType:t];
    return noErr;
}

/* ---- drawing Icon Services icons ----------------------------------------------------- */

/* A reference names a file (its path) or a type ('ques'); the desktop's
 * icon for it is drawn to fill the rectangle. */
OSStatus PlotIconRefInContext(CGContextRef ctx, const CGRect *rect, IconAlignmentType align,
                              IconTransformType transform, const RGBColor *labelColor, PlotIconRefFlags flags,
                              IconRef icon)
{
    (void)align;
    (void)labelColor;
    if (!ctx || !rect || !icon)
        return paramErr;
    if (flags & kPlotIconRefNoImage)
        return noErr;
    NSString *name = (NSString *)icon;
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSImage *image = [name hasPrefix:@"/"] ? [ws iconForFile:name] : [ws iconForFileType:name];
    if (!image)
        return noErr;
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];
    CGFloat alpha = (transform & 0xff) == kTransformDisabled ? 0.5 : 1.0;
    [image drawInRect:NSRectFromCGRect(*rect) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
             fraction:alpha];
    [NSGraphicsContext restoreGraphicsState];
    return noErr;
}

Boolean IsIconRefMaskEmpty(IconRef icon) { return icon == NULL; }

/* ---- touches and tablets: none come to Ferry ------------------------------------ */

@implementation NSTouch
- (id)copyWithZone:(NSZone *)zone { (void)zone; return [self retain]; }
- (id<NSObject, NSCopying>)identity { return self; }
- (NSTouchPhase)phase { return NSTouchPhaseCancelled; }
- (NSPoint)normalizedPosition { return NSZeroPoint; }
- (BOOL)isResting { return NO; }
- (id)device { return nil; }
- (NSSize)deviceSize { return NSZeroSize; }
- (NSTouchType)type { return NSTouchTypeIndirect; }
- (NSPoint)locationInView:(NSView *)view { (void)view; return NSZeroPoint; }
- (NSPoint)previousLocationInView:(NSView *)view { (void)view; return NSZeroPoint; }
@end

@implementation NSEvent (FerryTouchesAndTablets)
- (NSSet<NSTouch *> *)touchesMatchingPhase:(NSTouchPhase)phase inView:(NSView *)view
{
    (void)phase, (void)view;
    return [NSSet set];
}
- (NSSet<NSTouch *> *)allTouches { return [NSSet set]; }
- (NSSet<NSTouch *> *)touchesForView:(NSView *)view { (void)view; return [NSSet set]; }
- (NSUInteger)deviceID { return 0; }
- (float)rotation { return 0; }
- (NSInteger)absoluteX { return 0; }
- (NSInteger)absoluteY { return 0; }
- (NSInteger)absoluteZ { return 0; }
- (NSEventButtonMask)buttonMask { return 0; }
- (NSPoint)tilt { return NSZeroPoint; }
- (float)tangentialPressure { return 0; }
- (NSArray *)vendorDefined { return @[]; }
- (NSUInteger)vendorID { return 0; }
- (NSUInteger)tabletID { return 0; }
- (NSUInteger)pointingDeviceID { return 0; }
- (NSUInteger)systemTabletID { return 0; }
- (NSUInteger)vendorPointingDeviceType { return 0; }
- (NSUInteger)pointingDeviceSerialNumber { return 0; }
- (NSUInteger)capabilityMask { return 0; }
- (unsigned long long)uniqueID { return 0; }
- (NSPointingDeviceType)pointingDeviceType { return NSPointingDeviceTypeUnknown; }
- (BOOL)isEnteringProximity { return NO; }
@end

static char touch_types_key, resting_key, placement_key;

static NSUInteger assoc_uint(id o, const void *key, NSUInteger fallback)
{
    NSNumber *n = objc_getAssociatedObject(o, key);
    return n ? n.unsignedIntegerValue : fallback;
}
static void set_assoc_uint(id o, const void *key, NSUInteger v)
{
    objc_setAssociatedObject(o, key, @(v), OBJC_ASSOCIATION_RETAIN);
}

@implementation NSView (FerryTouches)
- (NSTouchTypeMask)allowedTouchTypes { return assoc_uint(self, &touch_types_key, NSTouchTypeMaskDirect); }
- (void)setAllowedTouchTypes:(NSTouchTypeMask)types { set_assoc_uint(self, &touch_types_key, types); }
- (BOOL)wantsRestingTouches { return (BOOL)assoc_uint(self, &resting_key, NO); }
- (void)setWantsRestingTouches:(BOOL)flag { set_assoc_uint(self, &resting_key, flag); }
@end

@implementation NSView (FerryLayerPlacement)
- (NSViewLayerContentsPlacement)layerContentsPlacement
{
    return (NSViewLayerContentsPlacement)assoc_uint(self, &placement_key,
                                                    NSViewLayerContentsPlacementScaleAxesIndependently);
}
- (void)setLayerContentsPlacement:(NSViewLayerContentsPlacement)placement
{
    set_assoc_uint(self, &placement_key, (NSUInteger)placement);
}
@end

/* ---- windows: colour, resize steps, tabs, full screen ---------------------------- */

static char space_key, profile_key, increments_key, content_increments_key, tabbing_key, tabbing_id_key;
static BOOL automatic_tabbing = YES;

@implementation NSWindow (FerryQtWindow)
- (NSColorSpace *)colorSpace
{
    return objc_getAssociatedObject(self, &space_key) ?: (self.screen ?: [NSScreen mainScreen]).colorSpace;
}
- (void)setColorSpace:(NSColorSpace *)space
{
    objc_setAssociatedObject(self, &space_key, space, OBJC_ASSOCIATION_RETAIN);
}
- (BOOL)displaysWhenScreenProfileChanges { return (BOOL)assoc_uint(self, &profile_key, NO); }
- (void)setDisplaysWhenScreenProfileChanges:(BOOL)flag { set_assoc_uint(self, &profile_key, flag); }
- (NSSize)resizeIncrements
{
    NSValue *v = objc_getAssociatedObject(self, &increments_key);
    return v ? v.sizeValue : NSMakeSize(1, 1);
}
- (void)setResizeIncrements:(NSSize)size
{
    objc_setAssociatedObject(self, &increments_key, [NSValue valueWithSize:size], OBJC_ASSOCIATION_RETAIN);
}
- (NSSize)contentResizeIncrements
{
    NSValue *v = objc_getAssociatedObject(self, &content_increments_key);
    return v ? v.sizeValue : NSMakeSize(1, 1);
}
- (void)setContentResizeIncrements:(NSSize)size
{
    objc_setAssociatedObject(self, &content_increments_key, [NSValue valueWithSize:size], OBJC_ASSOCIATION_RETAIN);
}
- (BOOL)worksWhenModal { return NO; }
- (NSWindowTabbingMode)tabbingMode
{
    return (NSWindowTabbingMode)assoc_uint(self, &tabbing_key, NSWindowTabbingModeAutomatic);
}
- (void)setTabbingMode:(NSWindowTabbingMode)mode { set_assoc_uint(self, &tabbing_key, (NSUInteger)mode); }
- (NSWindowTabbingIdentifier)tabbingIdentifier
{
    return objc_getAssociatedObject(self, &tabbing_id_key) ?: NSStringFromClass([self class]);
}
- (void)setTabbingIdentifier:(NSWindowTabbingIdentifier)identifier
{
    objc_setAssociatedObject(self, &tabbing_id_key, identifier, OBJC_ASSOCIATION_COPY);
}
+ (BOOL)allowsAutomaticWindowTabbing { return automatic_tabbing; }
+ (void)setAllowsAutomaticWindowTabbing:(BOOL)flag { automatic_tabbing = flag; }
+ (NSWindowTabbingMode)userTabbingPreference { return NSWindowTabbingModeAutomatic; }
@end

NSNotificationName const NSWindowWillEnterFullScreenNotification = @"NSWindowWillEnterFullScreenNotification";
NSNotificationName const NSWindowDidEnterFullScreenNotification = @"NSWindowDidEnterFullScreenNotification";
NSNotificationName const NSWindowWillExitFullScreenNotification = @"NSWindowWillExitFullScreenNotification";
NSNotificationName const NSWindowDidExitFullScreenNotification = @"NSWindowDidExitFullScreenNotification";
NSNotificationName const NSWindowDidChangeScreenProfileNotification = @"NSWindowDidChangeScreenProfileNotification";
NSNotificationName const NSWindowDidChangeScreenNotification = @"NSWindowDidChangeScreenNotification";

/* ---- scroller knobs and the menu bar's height -------------------------------------- */

NSNotificationName const NSPreferredScrollerStyleDidChangeNotification = @"NSPreferredScrollerStyleDidChangeNotification";

@implementation NSMenu (FerryMenuBarHeight)
- (CGFloat)menuBarHeight {
    if (self != [NSApp mainMenu]) return 0;
    NSScreen *screen = [NSScreen mainScreen];
    if (!screen) return 0;
    CGFloat h = NSMaxY([screen frame]) - NSMaxY([screen visibleFrame]);
    return h > 0 ? h : 0;
}
@end
