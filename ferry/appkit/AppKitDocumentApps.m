/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * What MacPass and MacDown, and the frameworks they bring, call besides the
 * rest of AppKit (freemac 1.225, Ferry 0.49.0): see AppKitDocumentApps.h.
 * Written from Apple's public documentation; no Apple code was read.
 *
 * Context menus: a right click on a view whose menuForEvent: gives a menu
 * opens it there as a pop-up menu (Ferry's in-window menu, as a pop-up
 * button's), and, as on a Mac, popUpContextMenu: and
 * popUpMenuPositioningItem: return only once the menu is closed, the
 * chosen item's action sent. A view with no menu passes the click on up
 * the responder chain. */
#import "AInternal.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>

static id assoc(id obj, const void *key) { return objc_getAssociatedObject(obj, key); }
static void set_assoc(id obj, const void *key, id value)
{
    objc_setAssociatedObject(obj, key, value, OBJC_ASSOCIATION_RETAIN);
}
static void set_assoc_copy(id obj, const void *key, id value)
{
    objc_setAssociatedObject(obj, key, value, OBJC_ASSOCIATION_COPY);
}

/* ---- context menus ------------------------------------------------------------------- */

static char menu_key;

@implementation NSResponder (NSMenu)
- (NSMenu *)menu { return assoc(self, &menu_key); }
- (void)setMenu:(NSMenu *)menu { set_assoc(self, &menu_key, menu); }
@end

/* Waits for a pop-up menu to close, then sends the chosen item's action. */
@interface AContextMenuOwner : NSObject <AMenuOwner> {
@public
    BOOL done;
    NSMenuItem *chosen;
}
@end
@implementation AContextMenuOwner
- (void)_menuView:(AMenuView *)menu didChooseItem:(NSMenuItem *)item
{
    done = YES;
    chosen = [item retain];
    if ([item action])
        [NSApp sendAction:[item action] to:[item target] from:item];
}
- (void)dealloc
{
    [chosen release];
    [super dealloc];
}
@end

/* The menu open with item number aligned at rect in view (or below it
 * for -1), until it is closed: the program's events are handled meanwhile,
 * as in a modal loop. YES when an item was chosen. */
static BOOL run_menu(NSMenu *menu, NSView *view, NSRect rect, NSInteger aligned, NSFont *font)
{
    if (!menu || ![view window])
        return NO;
    AContextMenuOwner *owner = [[[AContextMenuOwner alloc] init] autorelease];
    AMenuView *open = [AMenuView openMenu:menu forView:view rect:rect alignItem:aligned skipFirst:NO font:font
                                    owner:owner];
    if (!open)
        return NO;
    [open retain];
    while (!owner->done && [open window]) {
        @autoreleasepool {
            /* waking now and then, so a menu closed by a timer ends the wait */
            NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]
                                               inMode:NSEventTrackingRunLoopMode dequeue:YES];
            if (e)
                [NSApp sendEvent:e];
        }
    }
    [open release];
    return owner->chosen != nil;
}

@implementation NSView (FerryContextMenu)
+ (NSMenu *)defaultMenu { return nil; }
- (NSMenu *)menuForEvent:(NSEvent *)event { return [self menu] ?: [[self class] defaultMenu]; }
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {}
- (void)didCloseMenu:(NSMenu *)menu withEvent:(NSEvent *)event {}

- (void)rightMouseDown:(NSEvent *)event
{
    NSMenu *menu = [self menuForEvent:event];
    if (menu)
        [NSMenu popUpContextMenu:menu withEvent:event forView:self];
    else
        [[self nextResponder] rightMouseDown:event];
}

- (void)removeFromSuperviewWithoutNeedingDisplay { [self removeFromSuperview]; }

static char safe_area_key;
- (NSEdgeInsets)additionalSafeAreaInsets
{
    NSEdgeInsets insets = {0, 0, 0, 0};
    [(NSValue *)assoc(self, &safe_area_key) getValue:&insets size:sizeof insets];
    return insets;
}
- (void)setAdditionalSafeAreaInsets:(NSEdgeInsets)insets
{
    set_assoc(self, &safe_area_key, [NSValue valueWithBytes:&insets objCType:@encode(NSEdgeInsets)]);
    [self _safeAreaInsetsChanged];   /* the safe-area guide follows (AppKitNewer.m) */
}
/* no title bar or notch covers a view here: only what the program adds */
- (NSEdgeInsets)safeAreaInsets { return [self additionalSafeAreaInsets]; }
- (NSRect)safeAreaRect
{
    NSEdgeInsets i = [self safeAreaInsets];
    NSRect b = [self bounds];
    CGFloat low = [self isFlipped] ? i.top : i.bottom;   /* the inset at the smaller y */
    return NSMakeRect(NSMinX(b) + i.left, NSMinY(b) + low, MAX(0, b.size.width - i.left - i.right),
                      MAX(0, b.size.height - i.top - i.bottom));
}
@end

static char min_width_key, font_key;

@implementation NSMenu (FerryContextMenu)
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view
{
    [self popUpContextMenu:menu withEvent:event forView:view withFont:nil];
}
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view withFont:(NSFont *)font
{
    if (!menu || !view)
        return;
    NSPoint p = [view convertPoint:[event locationInWindow] fromView:nil];
    [view willOpenMenu:menu withEvent:event];
    run_menu(menu, view, NSMakeRect(p.x, p.y, 0, 0), -1, font ?: [menu font]);
    [view didCloseMenu:menu withEvent:event];
}
- (BOOL)popUpMenuPositioningItem:(NSMenuItem *)item atLocation:(NSPoint)location inView:(NSView *)view
{
    if (!view) {
        /* a place on the screen: the key window's, as a program sees
         * only its own windows */
        NSWindow *w = [NSApp keyWindow] ?: [NSApp mainWindow];
        view = [w contentView];
        if (!view)
            return NO;
        location = [view convertPoint:[w convertPointFromScreen:location] fromView:nil];
    }
    NSInteger aligned = item ? [self indexOfItem:item] : -1;
    return run_menu(self, view, NSMakeRect(location.x, location.y, 0, 0), aligned, [self font]);
}
- (NSInteger)indexOfItemWithRepresentedObject:(id)object
{
    NSArray *items = [self itemArray];
    for (NSUInteger i = 0; i < items.count; i++) {
        id r = [items[i] representedObject];
        if (r == object || [r isEqual:object])
            return (NSInteger)i;
    }
    return -1;
}
- (NSInteger)indexOfItemWithTarget:(id)target andAction:(SEL)action
{
    NSArray *items = [self itemArray];
    for (NSUInteger i = 0; i < items.count; i++)
        if ([items[i] target] == target && (!action || [items[i] action] == action))
            return (NSInteger)i;
    return -1;
}
- (NSInteger)indexOfItemWithTag:(NSInteger)tag
{
    NSArray *items = [self itemArray];
    for (NSUInteger i = 0; i < items.count; i++)
        if ([items[i] tag] == tag)
            return (NSInteger)i;
    return -1;
}
- (NSInteger)indexOfItemWithSubmenu:(NSMenu *)submenu
{
    NSArray *items = [self itemArray];
    for (NSUInteger i = 0; i < items.count; i++)
        if ([items[i] submenu] == submenu)
            return (NSInteger)i;
    return -1;
}
- (NSMenuItem *)highlightedItem
{
    for (NSWindow *w in AAllWindows()) {
        id open = [w _overlayView];
        if ([open isKindOfClass:[AMenuView class]] && [(AMenuView *)open menu] == self) {
            NSInteger i = [(AMenuView *)open highlightedIndex];
            return i >= 0 && i < [self numberOfItems] ? [self itemAtIndex:i] : nil;
        }
    }
    return nil;
}
/* as Ferry's menu lays it out: a row for each item, half a row for a
 * separator */
- (NSSize)size
{
    CGFloat h = 10, w = [self minimumWidth];
    NSFont *font = [self font] ?: [NSFont menuFontOfSize:0];
    for (NSMenuItem *item in [self itemArray]) {
        if ([item isHidden])
            continue;
        h += [item isSeparatorItem] ? 11 : 22;
        NSSize t = [[item title] sizeWithAttributes:@{NSFontAttributeName : font}];
        w = MAX(w, t.width + 22 + 18 + 10);
    }
    return NSMakeSize(w, h);
}
- (CGFloat)minimumWidth { return [assoc(self, &min_width_key) doubleValue]; }
- (void)setMinimumWidth:(CGFloat)width { set_assoc(self, &min_width_key, @(width)); }
- (NSFont *)font { return assoc(self, &font_key); }
- (void)setFont:(NSFont *)font { set_assoc(self, &font_key, font); }
@end

/* ---- windows ------------------------------------------------------------------------- */

static char sharing_key, restorable_key, restoration_class_key, resize_indicator_key, accessories_key,
    animations_key;

@implementation NSWindow (FerryDocumentApps)
+ (NSArray<NSNumber *> *)windowNumbersWithOptions:(NSWindowNumberListOptions)options
{
    /* the key window first, then the main window, then the rest */
    NSMutableArray *out = [NSMutableArray array];
    NSWindow *key = [NSApp keyWindow], *main = [NSApp mainWindow];
    if ([key isVisible])
        [out addObject:@([key windowNumber])];
    if (main != key && [main isVisible])
        [out addObject:@([main windowNumber])];
    for (NSWindow *w in AAllWindows())
        if (w != key && w != main && [w isVisible])
            [out addObject:@([w windowNumber])];
    return out;
}
+ (NSInteger)windowNumberAtPoint:(NSPoint)point belowWindowWithWindowNumber:(NSInteger)windowNumber
{
    BOOL below = windowNumber == 0;
    for (NSNumber *n in [self windowNumbersWithOptions:0]) {
        if (!below) {
            below = [n integerValue] == windowNumber;
            continue;
        }
        NSWindow *w = [NSApp windowWithWindowNumber:[n integerValue]];
        if (NSPointInRect(point, [w frame]))
            return [n integerValue];
    }
    return 0;
}
/* a window's animator, as a view's (NSAnimationContext.m): its frame and
 * its alpha value move over the context's duration */
- (instancetype)animator { return AAnimatorFor(self); }
- (NSDictionary *)animations { return assoc(self, &animations_key) ?: @{}; }
- (void)setAnimations:(NSDictionary *)animations { set_assoc_copy(self, &animations_key, animations); }
- (id)animationForKey:(NSString *)key
{
    id a = [self animations][key];
    if (a)
        return a == [NSNull null] ? nil : a;
    return [[self class] defaultAnimationForKey:key];
}
+ (id)defaultAnimationForKey:(NSString *)key
{
    return [key isEqualToString:@"frame"] || [key isEqualToString:@"alphaValue"] ? [CABasicAnimation animation] : nil;
}
- (void)setIsVisible:(BOOL)flag
{
    if (flag)
        [self orderFront:nil];
    else
        [self orderOut:nil];
}
- (NSWindowSharingType)sharingType
{
    NSNumber *n = assoc(self, &sharing_key);
    return n ? [n unsignedIntegerValue] : NSWindowSharingReadOnly;
}
- (void)setSharingType:(NSWindowSharingType)type { set_assoc(self, &sharing_key, @(type)); }
- (BOOL)isRestorable
{
    NSNumber *n = assoc(self, &restorable_key);
    return n ? [n boolValue] : YES;
}
- (void)setRestorable:(BOOL)flag { set_assoc(self, &restorable_key, @(flag)); }
- (Class)restorationClass { return assoc(self, &restoration_class_key); }
- (void)setRestorationClass:(Class)cls { set_assoc(self, &restoration_class_key, cls); }
- (void)invalidateRestorableState {}
- (BOOL)showsResizeIndicator
{
    NSNumber *n = assoc(self, &resize_indicator_key);
    return n ? [n boolValue] : YES;
}
- (void)setShowsResizeIndicator:(BOOL)flag { set_assoc(self, &resize_indicator_key, @(flag)); }
- (NSButton *)standardWindowButton:(NSWindowButton)button { return nil; }
+ (NSButton *)standardWindowButton:(NSWindowButton)button forStyleMask:(NSWindowStyleMask)styleMask { return nil; }

- (NSMutableArray *)_accessories
{
    NSMutableArray *a = assoc(self, &accessories_key);
    if (!a)
        set_assoc(self, &accessories_key, a = [NSMutableArray array]);
    return a;
}
- (NSArray *)titlebarAccessoryViewControllers { return [[[self _accessories] copy] autorelease]; }
- (void)setTitlebarAccessoryViewControllers:(NSArray *)controllers
{
    [[self _accessories] setArray:controllers ?: @[]];
}
- (void)addTitlebarAccessoryViewController:(NSTitlebarAccessoryViewController *)controller
{
    if (controller)
        [[self _accessories] addObject:controller];
}
- (void)insertTitlebarAccessoryViewController:(NSTitlebarAccessoryViewController *)controller atIndex:(NSInteger)i
{
    NSMutableArray *a = [self _accessories];
    if (controller && i >= 0 && (NSUInteger)i <= a.count)
        [a insertObject:controller atIndex:(NSUInteger)i];
}
- (void)removeTitlebarAccessoryViewControllerAtIndex:(NSInteger)i
{
    NSMutableArray *a = [self _accessories];
    if (i >= 0 && (NSUInteger)i < a.count)
        [a removeObjectAtIndex:(NSUInteger)i];
}
@end

@implementation NSTitlebarAccessoryViewController
- (void)viewWillAppear {}
- (void)viewDidAppear {}
- (void)viewDidDisappear {}
@end

/* ---- editing ------------------------------------------------------------------------- */

@implementation NSViewController (FerryEditor)
- (BOOL)commitEditing { return YES; }
- (void)discardEditing {}
- (void)commitEditingWithDelegate:(id)delegate didCommitSelector:(SEL)sel contextInfo:(void *)contextInfo
{
    if (!delegate || !sel)
        return;
    /* delegate:didCommit:contextInfo: */
    void (*f)(id, SEL, id, BOOL, void *) = (void (*)(id, SEL, id, BOOL, void *))objc_msgSend;
    f(delegate, sel, self, YES, contextInfo);
}
- (BOOL)commitEditingAndReturnError:(NSError **)error { return YES; }
- (void)objectDidBeginEditing:(id<NSEditor>)editor {}
- (void)objectDidEndEditing:(id<NSEditor>)editor {}
@end

/* ---- attributed strings ---------------------------------------------------------------- */

NSAttributedStringKey const NSStrikethroughColorAttributeName = @"NSStrikethroughColor";
NSAttributedStringKey const NSBaselineOffsetAttributeName = @"NSBaselineOffset";
NSAttributedStringKey const NSSuperscriptAttributeName = @"NSSuperScript";
NSAttributedStringKey const NSObliquenessAttributeName = @"NSObliqueness";
NSAttributedStringKey const NSExpansionAttributeName = @"NSExpansion";
NSAttributedStringKey const NSStrokeWidthAttributeName = @"NSStrokeWidth";
NSAttributedStringKey const NSStrokeColorAttributeName = @"NSStrokeColor";

@implementation NSAttributedString (FerryAttributeKinds)
static NSDictionary *attributes_of_kind(NSAttributedString *s, NSRange range, NSArray *keys)
{
    if (![s length] || range.location >= [s length])
        return @{};
    NSDictionary *all = [s attributesAtIndex:range.location effectiveRange:NULL];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in keys)
        if (all[k])
            out[k] = all[k];
    return out;
}
- (NSDictionary *)fontAttributesInRange:(NSRange)range
{
    return attributes_of_kind(self, range, @[
        NSFontAttributeName, NSForegroundColorAttributeName, NSBackgroundColorAttributeName,
        NSUnderlineStyleAttributeName, NSUnderlineColorAttributeName, NSStrikethroughStyleAttributeName,
        NSStrikethroughColorAttributeName, NSShadowAttributeName, NSKernAttributeName, NSLigatureAttributeName,
        NSBaselineOffsetAttributeName, NSSuperscriptAttributeName, NSObliquenessAttributeName,
        NSExpansionAttributeName, NSStrokeWidthAttributeName, NSStrokeColorAttributeName
    ]);
}
- (NSDictionary *)rulerAttributesInRange:(NSRange)range
{
    return attributes_of_kind(self, range, @[ NSParagraphStyleAttributeName ]);
}
@end

@implementation NSMutableAttributedString (FerryFixing)
- (void)fixAttributesInRange:(NSRange)range
{
    [self fixFontAttributeInRange:range];
    [self fixParagraphStyleAttributeInRange:range];
    [self fixAttachmentAttributeInRange:range];
}
- (void)fixFontAttributeInRange:(NSRange)range
{
    NSUInteger len = [self length];
    if (range.location >= len)
        return;
    range.length = MIN(range.length, len - range.location);
    __block NSFont *last = range.location > 0 ? [self attribute:NSFontAttributeName atIndex:range.location - 1
                                                  effectiveRange:NULL]
                                               : nil;
    NSMutableArray *missing = [NSMutableArray array];
    [self enumerateAttribute:NSFontAttributeName inRange:range options:0
                  usingBlock:^(id font, NSRange r, BOOL *stop) {
                      if (font)
                          last = font;
                      else
                          [missing addObject:@[ [NSValue valueWithRange:r], last ?: [NSFont fontWithName:@"Helvetica" size:12] ?: [NSFont systemFontOfSize:12] ]];
                  }];
    for (NSArray *m in missing)
        [self addAttribute:NSFontAttributeName value:m[1] range:[m[0] rangeValue]];
}
/* a paragraph has one style, so each style is kept as it is */
- (void)fixParagraphStyleAttributeInRange:(NSRange)range {}
- (void)fixAttachmentAttributeInRange:(NSRange)range {}
@end

/* ---- text checking ------------------------------------------------------------------- */

static char checking_key;

@implementation NSTextView (FerryTextChecking)
- (NSTextCheckingTypes)enabledTextCheckingTypes
{
    NSTextCheckingTypes t = [assoc(self, &checking_key) unsignedLongLongValue];
    /* the kinds the settings give, besides any others it was set to */
    t &= ~(NSTextCheckingTypes)(NSTextCheckingTypeSpelling | NSTextCheckingTypeGrammar | NSTextCheckingTypeQuote |
                                NSTextCheckingTypeDash | NSTextCheckingTypeLink | NSTextCheckingTypeReplacement |
                                NSTextCheckingTypeCorrection);
    if ([self isContinuousSpellCheckingEnabled])
        t |= NSTextCheckingTypeSpelling;
    if ([self isGrammarCheckingEnabled])
        t |= NSTextCheckingTypeGrammar;
    if ([self isAutomaticQuoteSubstitutionEnabled])
        t |= NSTextCheckingTypeQuote;
    if ([self isAutomaticDashSubstitutionEnabled])
        t |= NSTextCheckingTypeDash;
    if ([self isAutomaticLinkDetectionEnabled])
        t |= NSTextCheckingTypeLink;
    if ([self isAutomaticTextReplacementEnabled])
        t |= NSTextCheckingTypeReplacement;
    if ([self isAutomaticSpellingCorrectionEnabled])
        t |= NSTextCheckingTypeCorrection;
    return t;
}
- (void)setEnabledTextCheckingTypes:(NSTextCheckingTypes)t
{
    set_assoc(self, &checking_key, @(t));
    [self setContinuousSpellCheckingEnabled:(t & NSTextCheckingTypeSpelling) != 0];
    [self setGrammarCheckingEnabled:(t & NSTextCheckingTypeGrammar) != 0];
    [self setAutomaticQuoteSubstitutionEnabled:(t & NSTextCheckingTypeQuote) != 0];
    [self setAutomaticDashSubstitutionEnabled:(t & NSTextCheckingTypeDash) != 0];
    [self setAutomaticLinkDetectionEnabled:(t & NSTextCheckingTypeLink) != 0];
    [self setAutomaticTextReplacementEnabled:(t & NSTextCheckingTypeReplacement) != 0];
    [self setAutomaticSpellingCorrectionEnabled:(t & NSTextCheckingTypeCorrection) != 0];
}
@end

/* ---- documents ------------------------------------------------------------------------ */

@implementation NSDocument (FerryDocumentApps)
- (void)unblockUserInteraction {}
@end

/* ---- cells --------------------------------------------------------------------------- */

static char truncates_key, image_scaling_key;

@implementation NSCell (FerryDocumentApps)
- (BOOL)truncatesLastVisibleLine { return [assoc(self, &truncates_key) boolValue]; }
- (void)setTruncatesLastVisibleLine:(BOOL)flag { set_assoc(self, &truncates_key, @(flag)); }
@end
@implementation NSButtonCell (FerryDocumentApps)
- (NSImageScaling)imageScaling
{
    NSNumber *n = assoc(self, &image_scaling_key);
    if (n)
        return [n integerValue];
    NSView *v = [self controlView];
    return [v isKindOfClass:[NSButton class]] ? [(NSButton *)v imageScaling] : NSImageScaleProportionallyDown;
}
- (void)setImageScaling:(NSImageScaling)scaling
{
    set_assoc(self, &image_scaling_key, @(scaling));
    NSView *v = [self controlView];
    if ([v isKindOfClass:[NSButton class]] && [(NSButton *)v cell] == self)
        [(NSButton *)v setImageScaling:scaling];
}
@end

static char bezel_key;

@implementation NSTextFieldCell (FerryDocumentApps)
- (NSTextFieldBezelStyle)bezelStyle
{
    NSView *v = [self controlView];
    if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v cell] == self)
        return [(NSTextField *)v bezelStyle];
    return [assoc(self, &bezel_key) integerValue];
}
- (void)setBezelStyle:(NSTextFieldBezelStyle)style
{
    set_assoc(self, &bezel_key, @(style));
    NSView *v = [self controlView];
    if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v cell] == self)
        [(NSTextField *)v setBezelStyle:style];
}
@end

/* ---- text views and images ---------------------------------------------------------------- */

@implementation NSTextView (FerryDocumentApps)
- (NSUInteger)characterIndexForPoint:(NSPoint)screenPoint
{
    NSWindow *w = [self window];
    if (!w)
        return NSNotFound;
    NSPoint p = [self convertPoint:[w convertPointFromScreen:screenPoint] fromView:nil];
    if (!NSPointInRect(p, [self bounds]))
        return NSNotFound;
    NSUInteger i = [self characterIndexForInsertionAtPoint:p];
    NSUInteger n = [[self string] length];
    if (n == 0)
        return NSNotFound;
    return i >= n ? n - 1 : i;
}
- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSMenu *menu = [self menu] ?: [[self class] defaultMenu];
    id<NSTextViewDelegate> d = (id)[self delegate];
    if ([d respondsToSelector:@selector(textView:menu:forEvent:atIndex:)]) {
        NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
        menu = [d textView:self menu:menu forEvent:event atIndex:[self characterIndexForInsertionAtPoint:p]];
    }
    return menu;
}
@end

@implementation NSBitmapImageRep (FerryFocusedView)
- (instancetype)initWithFocusedViewRect:(NSRect)rect
{
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    size_t height = cg ? CGBitmapContextGetHeight(cg) : 0;
    CGImageRef all = height ? CGBitmapContextCreateImage(cg) : NULL;
    if (!all) {
        [self release];
        return nil;
    }
    /* the rectangle in the context's pixels, whose rows run top down in the image */
    CGRect d = CGRectIntegral(CGContextConvertRectToDeviceSpace(cg, NSRectToCGRect(rect)));
    d.origin.y = (CGFloat)height - CGRectGetMaxY(d);
    CGImageRef part = CGImageCreateWithImageInRect(all, d);
    CGImageRelease(all);
    if (!part) {
        [self release];
        return nil;
    }
    self = [self initWithCGImage:part];
    CGImageRelease(part);
    [self setSize:rect.size];
    return self;
}
@end

/* ---- the application ------------------------------------------------------------------ */

static BOOL customize_touch_bar_item = YES;

@implementation NSApplication (FerryDocumentApps)
/* the documents of the windows front to back, then the rest */
- (NSArray *)orderedDocuments
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSWindow *w in [self orderedWindows]) {
        id doc = [[w windowController] document];
        if (doc && ![out containsObject:doc])
            [out addObject:doc];
    }
    for (id doc in [[NSDocumentController sharedDocumentController] documents])
        if (![out containsObject:doc])
            [out addObject:doc];
    return out;
}
- (NSArray<NSWindow *> *)orderedWindows
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *n in [NSWindow windowNumbersWithOptions:0]) {
        NSWindow *w = [self windowWithWindowNumber:[n integerValue]];
        if (w)
            [out addObject:w];
    }
    return out;
}
- (BOOL)automaticCustomizeTouchBarMenuItemEnabled { return customize_touch_bar_item; }
- (void)setAutomaticCustomizeTouchBarMenuItemEnabled:(BOOL)flag { customize_touch_bar_item = flag; }
@end

/* ---- the workspace ----------------------------------------------------------------------- */

NSWorkspaceLaunchConfigurationKey const NSWorkspaceLaunchConfigurationAppleEvent =
    @"NSWorkspaceLaunchConfigurationAppleEvent";
NSWorkspaceLaunchConfigurationKey const NSWorkspaceLaunchConfigurationArchitecture =
    @"NSWorkspaceLaunchConfigurationArchitecture";

@implementation NSWorkspace (FerryLaunchOptions)
/* Each URL is opened as openURL: opens it (the desktop picks the
 * program); there is no Mac application to answer, so the answer is nil,
 * with an error when a URL couldn't be opened. */
- (NSRunningApplication *)openURLs:(NSArray<NSURL *> *)urls withApplicationAtURL:(NSURL *)applicationURL
                           options:(NSWorkspaceLaunchOptions)options
                     configuration:(NSDictionary<NSWorkspaceLaunchConfigurationKey, id> *)configuration
                             error:(NSError **)error
{
    for (NSURL *url in urls) {
        if (![self openURL:url]) {
            if (error)
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError
                                         userInfo:url ? @{NSURLErrorKey : url} : nil];
            return nil;
        }
    }
    if (error)
        *error = nil;
    return nil;
}
- (NSImage *)iconForContentType:(UTType *)contentType
{
    NSString *identifier = [contentType identifier];
    return [self iconForFileType:identifier ?: @"public.data"];
}
@end

/* ---- file promises ------------------------------------------------------------------------- */

@implementation NSFilePromiseProvider {
    NSString *_fileType;
    id _userInfo;
    id<NSFilePromiseProviderDelegate> _delegate;   /* not retained */
}
- (id<NSFilePromiseProviderDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSFilePromiseProviderDelegate>)delegate { _delegate = delegate; }
- (instancetype)initWithFileType:(NSString *)fileType delegate:(id<NSFilePromiseProviderDelegate>)delegate
{
    if ((self = [super init])) {
        _fileType = [fileType copy];
        _delegate = delegate;
    }
    return self;
}
- (void)dealloc
{
    [_fileType release];
    [_userInfo release];
    [super dealloc];
}
- (NSString *)fileType { return _fileType; }
- (void)setFileType:(NSString *)type
{
    [_fileType autorelease];
    _fileType = [type copy];
}
- (id)userInfo { return _userInfo; }
- (void)setUserInfo:(id)info
{
    [_userInfo autorelease];
    _userInfo = [info retain];
}
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard { return @[ NSPasteboardTypeFileURL ]; }

/* The promise kept: the file, written by the delegate into a new folder
 * of the temporary folder, is the pasteboard's file URL. */
- (id)pasteboardPropertyListForType:(NSPasteboardType)type
{
    id<NSFilePromiseProviderDelegate> delegate = _delegate;
    if (![type isEqualToString:NSPasteboardTypeFileURL] || !delegate)
        return nil;
    NSString *name = [delegate filePromiseProvider:self fileNameForType:_fileType];
    if (![name length])
        return nil;
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                [NSString stringWithFormat:@"ferry-promise-%@",
                                                                           [[NSUUID UUID] UUIDString]]];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil
                                                         error:NULL])
        return nil;
    NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:[name lastPathComponent]]];
    __block BOOL done = NO, ok = NO;
    [delegate filePromiseProvider:self writePromiseToURL:url completionHandler:^(NSError *error) {
        ok = !error;
        done = YES;
    }];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!done && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return ok ? [url absoluteString] : nil;
}
@end

/* No other program here makes promises: there are none to receive. */
@implementation NSFilePromiseReceiver
+ (NSArray *)readableDraggedTypes { return @[]; }
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard { return @[]; }
- (id)initWithPasteboardPropertyList:(id)propertyList ofType:(NSPasteboardType)type
{
    [self release];
    return nil;
}
- (NSArray *)fileTypes { return @[]; }
- (NSArray *)fileNames { return @[]; }
- (void)receivePromisedFilesAtDestination:(NSURL *)destinationDir options:(NSDictionary *)options
                           operationQueue:(NSOperationQueue *)operationQueue
                                   reader:(void (^)(NSURL *, NSError *))reader
{
}
@end

/* ---- images ------------------------------------------------------------------------------- */

/* imageWithSystemSymbolName:accessibilityDescription: is in AppKitNewer.m
 * (freemac 1.232), with the few symbol images Ferry draws itself. */

/* ---- colour spaces ------------------------------------------------------------------------- */

@implementation NSColorSpace {
    CGColorSpaceRef _space;
    NSString *_name;
}
+ (BOOL)supportsSecureCoding { return YES; }

static NSColorSpace *named_space(NSColorSpace **slot, CGColorSpaceRef cg, NSString *name)
{
    if (!*slot) {
        *slot = [[NSColorSpace alloc] initWithCGColorSpace:cg];
        (*slot)->_name = [name copy];
    }
    CGColorSpaceRelease(cg);
    return *slot;
}
#define SPACE(sel, make, label)                                                                                        \
    +(NSColorSpace *)sel                                                                                               \
    {                                                                                                                  \
        static NSColorSpace *space;                                                                                    \
        return space ?: named_space(&space, make, label);                                                              \
    }
SPACE(sRGBColorSpace, CGColorSpaceCreateWithName(kCGColorSpaceSRGB), @"sRGB IEC61966-2.1")
SPACE(genericRGBColorSpace, CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB), @"Generic RGB")
SPACE(deviceRGBColorSpace, CGColorSpaceCreateDeviceRGB(), @"Device RGB")
SPACE(extendedSRGBColorSpace, CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB), @"Extended sRGB")
SPACE(displayP3ColorSpace, CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3), @"Display P3")
SPACE(adobeRGB1998ColorSpace, CGColorSpaceCreateDeviceRGB(), @"Adobe RGB (1998)")
SPACE(genericGrayColorSpace, CGColorSpaceCreateWithName(kCGColorSpaceGenericGray), @"Generic Gray")
SPACE(genericGamma22GrayColorSpace, CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2),
      @"Generic Gray Gamma 2.2")
SPACE(deviceGrayColorSpace, CGColorSpaceCreateDeviceGray(), @"Device Gray")
SPACE(genericCMYKColorSpace, CGColorSpaceCreateWithName(kCGColorSpaceGenericCMYK), @"Generic CMYK")
SPACE(deviceCMYKColorSpace, CGColorSpaceCreateDeviceCMYK(), @"Device CMYK")
#undef SPACE

- (instancetype)initWithCGColorSpace:(CGColorSpaceRef)cg
{
    if (!cg) {
        [self release];
        return nil;
    }
    if ((self = [super init]))
        _space = CGColorSpaceRetain(cg);
    return self;
}
- (void)dealloc
{
    CGColorSpaceRelease(_space);
    [_name release];
    [super dealloc];
}
- (CGColorSpaceRef)CGColorSpace { return _space; }
- (NSColorSpaceModel)colorSpaceModel
{
    switch (CGColorSpaceGetModel(_space)) {
    case kCGColorSpaceModelMonochrome: return NSColorSpaceModelGray;
    case kCGColorSpaceModelRGB: return NSColorSpaceModelRGB;
    case kCGColorSpaceModelCMYK: return NSColorSpaceModelCMYK;
    case kCGColorSpaceModelLab: return NSColorSpaceModelLAB;
    case kCGColorSpaceModelDeviceN: return NSColorSpaceModelDeviceN;
    case kCGColorSpaceModelIndexed: return NSColorSpaceModelIndexed;
    case kCGColorSpaceModelPattern: return NSColorSpaceModelPatterned;
    default: return NSColorSpaceModelUnknown;
    }
}
- (NSInteger)numberOfColorComponents { return (NSInteger)CGColorSpaceGetNumberOfComponents(_space); }
- (NSString *)localizedName
{
    if (_name)
        return _name;
    NSString *cg = [(NSString *)CGColorSpaceCopyName(_space) autorelease];
    return cg ?: @"";
}
- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[NSColorSpace class]] &&
                             [other colorSpaceModel] == [self colorSpaceModel] &&
                             [[other localizedName] isEqualToString:[self localizedName]]);
}
- (NSUInteger)hash { return (NSUInteger)[self colorSpaceModel] ^ [[self localizedName] hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> %@", [self class], self, [self localizedName]];
}

/* kept by its model: grey, CMYK or RGB */
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeInteger:[self colorSpaceModel] forKey:@"NSModel"]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSInteger model = [coder decodeIntegerForKey:@"NSModel"];
    NSColorSpace *s = model == NSColorSpaceModelGray   ? [NSColorSpace genericGrayColorSpace]
                      : model == NSColorSpaceModelCMYK ? [NSColorSpace genericCMYKColorSpace]
                                                       : [NSColorSpace sRGBColorSpace];
    [self release];
    return [s retain];
}
@end

@implementation NSColor (FerryColorSpaces)
- (NSColorSpace *)colorSpace { return [NSColorSpace sRGBColorSpace]; }
+ (NSColor *)colorWithColorSpace:(NSColorSpace *)space components:(const CGFloat *)c count:(NSInteger)count
{
    if (!c || count < 1)
        return nil;
    switch ([space colorSpaceModel]) {
    case NSColorSpaceModelGray:
        return [NSColor colorWithWhite:c[0] alpha:count > 1 ? c[1] : 1];
    case NSColorSpaceModelCMYK:
        if (count < 4)
            return nil;
        return [NSColor colorWithRed:(1 - c[0]) * (1 - c[3]) green:(1 - c[1]) * (1 - c[3])
                                blue:(1 - c[2]) * (1 - c[3]) alpha:count > 4 ? c[4] : 1];
    default:
        if (count < 3)
            return nil;
        return [NSColor colorWithRed:c[0] green:c[1] blue:c[2] alpha:count > 3 ? c[3] : 1];
    }
}
@end

/* ---- the Touch Bar ---------------------------------------------------------------------- */

/* There is no Touch Bar: the item keeps what it is given. */
@implementation NSPopoverTouchBarItem
@synthesize popoverTouchBar = _popoverTouchBar, customizationLabel = _label,
            collapsedRepresentation = _collapsed, collapsedRepresentationImage = _collapsedImage,
            collapsedRepresentationLabel = _collapsedLabel, pressAndHoldTouchBar = _pressAndHold,
            showsCloseButton = _showsClose;
- (void)dealloc
{
    [_popoverTouchBar release];
    [_label release];
    [_collapsed release];
    [_collapsedImage release];
    [_collapsedLabel release];
    [_pressAndHold release];
    [super dealloc];
}
- (void)showPopover:(id)sender {}
- (void)dismissPopover:(id)sender {}
@end

/* ---- the secure text view ------------------------------------------------------------- */

/* The text view that edits a secure text field on a Mac. It has no public
 * interface (HNHUi declares one, to subclass it), so none is in Ferry's
 * headers; in Ferry a text field edits its own text, and this is a text
 * view whose text can't be copied or cut out of it. */
@interface NSSecureTextView : NSTextView
@end
@implementation NSSecureTextView
- (void)copy:(id)sender { NSBeep(); }
- (void)cut:(id)sender { NSBeep(); }
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(copy:) || [item action] == @selector(cut:))
        return NO;
    return [super validateMenuItem:item];
}
@end
