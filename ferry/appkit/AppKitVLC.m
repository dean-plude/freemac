/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * What VLC's Mac interface calls besides the rest of AppKit (freemac 1.NEXT,
 * Ferry 0.NEXT): see AppKitVLC.h. Written from Apple's public
 * documentation; no Apple code was read.
 *
 * Custom cells (VLC's slider, button, pop-up, segmented and stepper cells)
 * override the parts a cell is drawn from and call super for the rest;
 * here those parts draw Ferry's own look on their own, so super has
 * something to do. */
#import "AInternal.h"
#import <objc/runtime.h>
#include <string.h>
#include <sys/mount.h>

static id assoc(id obj, const void *key) { return objc_getAssociatedObject(obj, key); }
static void set_assoc(id obj, const void *key, id value)
{
    objc_setAssociatedObject(obj, key, value, OBJC_ASSOCIATION_RETAIN);
}
static NSInteger assoc_int(id obj, const void *key) { return [(NSNumber *)assoc(obj, key) integerValue]; }
static void set_assoc_int(id obj, const void *key, NSInteger v) { set_assoc(obj, key, @(v)); }

NSNotificationName const NSApplicationDidChangeScreenParametersNotification =
    @"NSApplicationDidChangeScreenParametersNotification";
NSNotificationName const NSWindowWillMiniaturizeNotification = @"NSWindowWillMiniaturizeNotification";
const CGFloat NSBlack = 0, NSDarkGray = 1.0 / 3.0, NSLightGray = 2.0 / 3.0, NSWhite = 1;

/* ---- presentation options ------------------------------------------------------------ */

static char presentation_key;

@implementation NSApplication (FerryPresentationOptions)
- (NSApplicationPresentationOptions)presentationOptions
{
    return (NSApplicationPresentationOptions)assoc_int(self, &presentation_key);
}
- (void)setPresentationOptions:(NSApplicationPresentationOptions)options
{
    /* as on a Mac: hiding the menu bar needs the Dock hidden too, and the
     * Disable options need one of them */
    if ((options & NSApplicationPresentationAutoHideMenuBar) && (options & NSApplicationPresentationHideDock) == 0)
        options |= NSApplicationPresentationAutoHideDock;
    set_assoc_int(self, &presentation_key, (NSInteger)options);
}
- (NSApplicationPresentationOptions)currentSystemPresentationOptions
{
    NSApplicationPresentationOptions o = [self presentationOptions];
    for (NSWindow *w in [self windows])
        if ([w isVisible] && ([w styleMask] & NSWindowStyleMaskFullScreen))
            o |= NSApplicationPresentationFullScreen;
    return o;
}
@end

/* ---- alert sheets -------------------------------------------------------------------- */

static void begin_sheet(NSAlertStyle style, NSString *title, NSString *def, NSString *alt, NSString *other,
                        NSWindow *window, id delegate, SEL didEnd, SEL didDismiss, void *context,
                        NSString *message)
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setAlertStyle:style];
    [alert setMessageText:title ?: @""];
    [alert setInformativeText:message ?: @""];
    /* the default button is OK when none is named, as on a Mac */
    [alert addButtonWithTitle:[def length] ? def : @"OK"];
    if ([alt length])
        [alert addButtonWithTitle:alt];
    if ([other length])
        [alert addButtonWithTitle:other];
    BOOL hasAlt = [alt length] > 0;
    void (^done)(NSModalResponse) = ^(NSModalResponse r) {
        /* the buttons' answers are the old ones, not NSAlertFirstButtonReturn's */
        NSInteger code = r == NSAlertFirstButtonReturn ? NSAlertDefaultReturn
                         : r == NSAlertSecondButtonReturn && hasAlt ? NSAlertAlternateReturn
                                                                    : NSAlertOtherReturn;
        id sheet = [alert window];
        if (delegate && didEnd)
            ((void (*)(id, SEL, id, NSInteger, void *))objc_msgSend)(delegate, didEnd, sheet, code, context);
        if (delegate && didDismiss)
            ((void (*)(id, SEL, id, NSInteger, void *))objc_msgSend)(delegate, didDismiss, sheet, code, context);
    };
    if (window)
        [alert beginSheetModalForWindow:window completionHandler:done];
    else
        done([alert runModal]);
}

#define SHEET(name, style)                                                                                    \
    void name(NSString *title, NSString *def, NSString *alt, NSString *other, NSWindow *window, id delegate, \
              SEL didEnd, SEL didDismiss, void *context, NSString *format, ...)                              \
    {                                                                                                         \
        va_list ap;                                                                                           \
        va_start(ap, format);                                                                                 \
        NSString *message = format ? [[[NSString alloc] initWithFormat:format arguments:ap] autorelease] : nil; \
        va_end(ap);                                                                                           \
        begin_sheet(style, title, def, alt, other, window, delegate, didEnd, didDismiss, context, message);   \
    }
SHEET(NSBeginAlertSheet, NSAlertStyleWarning)
SHEET(NSBeginInformationalAlertSheet, NSAlertStyleInformational)
SHEET(NSBeginCriticalAlertSheet, NSAlertStyleCritical)

/* ---- drawing ------------------------------------------------------------------------- */

void NSFrameRectWithWidthUsingOperation(NSRect rect, CGFloat width, NSCompositingOperation op)
{
    NSGraphicsContext *g = [NSGraphicsContext currentContext];
    [g saveGraphicsState];
    [g setCompositingOperation:op];
    NSFrameRectWithWidth(rect, width);
    [g restoreGraphicsState];
}

/* ---- cells --------------------------------------------------------------------------- */

static char direction_key;

@implementation NSCell (FerryTracking)
- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
    /* a continuous cell sends its action as the mouse moves */
    return [self isContinuous] || [self action] != NULL;
}
- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
    return YES;
}
- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
}
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection
{
    NSNumber *d = assoc(self, &direction_key);
    if (d)
        return (NSUserInterfaceLayoutDirection)[d integerValue];
    NSView *v = [self controlView];
    return v ? [v userInterfaceLayoutDirection] : NSUserInterfaceLayoutDirectionLeftToRight;
}
- (void)setUserInterfaceLayoutDirection:(NSUserInterfaceLayoutDirection)d { set_assoc_int(self, &direction_key, d); }
@end

/* Ferry's slider look, as NSSlider draws it: a thin rounded track, filled
 * with the accent colour up to a round white knob. */
static const CGFloat knob_size = 20, track_width = 4;
static char track_rect_key;

@implementation NSSliderCell (FerryDrawing)
- (CGFloat)knobThickness { return knob_size; }
- (NSRect)trackRect
{
    NSValue *v = assoc(self, &track_rect_key);
    if (v)
        return [v rectValue];
    NSView *c = [self controlView];
    return c ? [c bounds] : NSZeroRect;
}
- (BOOL)_ferryVerticalIn:(NSRect)r
{
    NSInteger v = [self isVertical] ? 1 : 0;
    return v || (r.size.height > r.size.width && [self numberOfTickMarks] == 0 && r.size.width < knob_size + 8);
}
- (double)_ferryFraction
{
    double lo = [self minValue], hi = [self maxValue];
    return hi == lo ? 0 : fmin(fmax(([self doubleValue] - lo) / (hi - lo), 0), 1);
}
- (NSRect)barRectFlipped:(BOOL)flipped
{
    NSRect r = [self trackRect];
    if ([self _ferryVerticalIn:r])
        return NSMakeRect(NSMidX(r) - track_width / 2, NSMinY(r) + knob_size / 2, track_width,
                          MAX(0, r.size.height - knob_size));
    return NSMakeRect(NSMinX(r) + knob_size / 2, NSMidY(r) - track_width / 2, MAX(0, r.size.width - knob_size),
                      track_width);
}
- (NSRect)knobRectFlipped:(BOOL)flipped
{
    NSRect r = [self trackRect];
    double f = [self _ferryFraction];
    NSPoint c;
    if ([self _ferryVerticalIn:r]) {
        CGFloat span = r.size.height - knob_size;
        /* the minimum is at the bottom */
        c = NSMakePoint(NSMidX(r), flipped ? NSMaxY(r) - knob_size / 2 - span * f : NSMinY(r) + knob_size / 2 + span * f);
    } else {
        CGFloat span = r.size.width - knob_size;
        if ([self userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft)
            f = 1 - f;
        c = NSMakePoint(NSMinX(r) + knob_size / 2 + span * f, NSMidY(r));
    }
    return NSMakeRect(c.x - knob_size / 2, c.y - knob_size / 2, knob_size, knob_size);
}
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    CGFloat dim = [self isEnabled] ? 1 : 0.5;
    BOOL vertical = [self _ferryVerticalIn:[self trackRect]];
    NSRect track = vertical ? NSMakeRect(NSMidX(rect) - track_width / 2, NSMinY(rect), track_width, rect.size.height)
                            : NSMakeRect(NSMinX(rect), NSMidY(rect) - track_width / 2, rect.size.width, track_width);
    AFillRoundedRect(track, track_width / 2, [NSColor colorWithWhite:0 alpha:0.12 * dim], nil);
    NSRect knob = [self knobRectFlipped:flipped];
    NSRect filled = track;
    if (vertical) {
        if (flipped) {
            filled.origin.y = NSMidY(knob);
            filled.size.height = NSMaxY(track) - NSMidY(knob);
        } else
            filled.size.height = NSMidY(knob) - NSMinY(track);
    } else
        filled.size.width = NSMidX(knob) - NSMinX(track);
    if (filled.size.width > 0 && filled.size.height > 0)
        AFillRoundedRect(filled, track_width / 2, [[NSColor controlAccentColor] colorWithAlphaComponent:dim], nil);
}
- (void)drawKnob:(NSRect)knobRect
{
    CGFloat dim = [self isEnabled] ? 1 : 0.5;
    NSRect knob = NSInsetRect(knobRect, 0.5, 0.5);
    NSColor *face = [self isHighlighted] ? [NSColor colorWithWhite:0.94 alpha:1] : [NSColor whiteColor];
    AFillRoundedRect(knob, MIN(knob.size.width, knob.size.height) / 2, face,
                     [NSColor colorWithWhite:0 alpha:0.25 * dim]);
}
- (void)drawKnob
{
    NSView *c = [self controlView];
    [self drawKnob:[self knobRectFlipped:c ? [c isFlipped] : NO]];
}
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index
{
    NSInteger n = [self numberOfTickMarks];
    if (index < 0 || index >= n)
        [NSException raise:NSRangeException format:@"-[NSSliderCell rectOfTickMarkAtIndex:]: no tick mark %ld",
                                                    (long)index];
    NSRect bar = [self barRectFlipped:NO];
    double f = n == 1 ? 0.5 : (double)index / (double)(n - 1);
    BOOL above = [self tickMarkPosition] == NSTickMarkPositionAbove;
    if (bar.size.height > bar.size.width) {
        CGFloat y = NSMinY(bar) + bar.size.height * f;
        return NSMakeRect(above ? NSMinX(bar) - knob_size / 2 - 3 : NSMaxX(bar) + knob_size / 2 - 1, y - 0.5, 4, 1);
    }
    CGFloat x = NSMinX(bar) + bar.size.width * f;
    return NSMakeRect(x - 0.5, above ? NSMaxY(bar) + knob_size / 2 - 1 : NSMinY(bar) - knob_size / 2 - 3, 1, 4);
}
- (void)drawTickMarks
{
    [[NSColor colorWithWhite:0 alpha:[self isEnabled] ? 0.35 : 0.18] setFill];
    for (NSInteger i = 0; i < [self numberOfTickMarks]; i++)
        NSRectFill([self rectOfTickMarkAtIndex:i]);
}
- (double)tickMarkValueAtIndex:(NSInteger)index
{
    NSInteger n = [self numberOfTickMarks];
    if (n <= 1)
        return ([self minValue] + [self maxValue]) / 2;
    return [self minValue] + ([self maxValue] - [self minValue]) * (double)index / (double)(n - 1);
}
- (double)closestTickMarkValueToValue:(double)value
{
    NSInteger n = [self numberOfTickMarks];
    if (n == 0)
        return value;
    double best = [self tickMarkValueAtIndex:0];
    for (NSInteger i = 1; i < n; i++) {
        double v = [self tickMarkValueAtIndex:i];
        if (fabs(v - value) < fabs(best - value))
            best = v;
    }
    return best;
}
- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)point
{
    for (NSInteger i = 0; i < [self numberOfTickMarks]; i++)
        if (NSPointInRect(point, NSInsetRect([self rectOfTickMarkAtIndex:i], -2, -2)))
            return i;
    return NSNotFound;
}
/* drawn into a rectangle: the bar, the tick marks and the knob */
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
    [self setControlView:view];
    set_assoc(self, &track_rect_key, [NSValue valueWithRect:frame]);
    BOOL flipped = [view isFlipped];
    [self drawBarInside:[self barRectFlipped:flipped] flipped:flipped];
    [self drawTickMarks];
    [self drawKnob];
}
@end

static char border_inside_key;

@implementation NSButtonCell (FerryDrawing)
- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView
{
    if (![title length])
        return NSZeroRect;
    NSSize s = [title size];
    NSRect r = frame;
    switch ([self alignment]) {
    case NSTextAlignmentLeft: break;
    case NSTextAlignmentRight: r.origin.x = NSMaxX(frame) - s.width; break;
    default: r.origin.x = NSMidX(frame) - s.width / 2; break;
    }
    r.origin.y = NSMidY(frame) - s.height / 2;
    r.size = s;
    [title drawInRect:r];
    return r;
}
- (void)drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(NSView *)controlView
{
    if (!image)
        return;
    NSSize s = [image size];
    if (s.width > frame.size.width || s.height > frame.size.height) {
        CGFloat k = MIN(frame.size.width / MAX(s.width, 1), frame.size.height / MAX(s.height, 1));
        s = NSMakeSize(s.width * k, s.height * k);
    }
    NSRect r = NSMakeRect(NSMidX(frame) - s.width / 2, NSMidY(frame) - s.height / 2, s.width, s.height);
    [image drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
             fraction:[self isEnabled] ? 1 : 0.5 respectFlipped:YES hints:nil];
}
- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView
{
    if ([self isTransparent] || ![self isBordered])
        return;
    CGFloat dim = [self isEnabled] ? 1 : 0.5;
    NSColor *face = [self isHighlighted] ? [NSColor colorWithWhite:0.86 alpha:1] : [NSColor whiteColor];
    AFillRoundedRect(NSInsetRect(frame, 0.5, 1.5), 5, face, [NSColor colorWithWhite:0 alpha:0.2 * dim]);
}
- (BOOL)showsBorderOnlyWhileMouseInside { return assoc_int(self, &border_inside_key) != 0; }
- (void)setShowsBorderOnlyWhileMouseInside:(BOOL)flag { set_assoc_int(self, &border_inside_key, flag); }
@end
@implementation NSButton (FerryBorderWhileInside)
- (BOOL)showsBorderOnlyWhileMouseInside { return assoc_int(self, &border_inside_key) != 0; }
- (void)setShowsBorderOnlyWhileMouseInside:(BOOL)flag { set_assoc_int(self, &border_inside_key, flag); }
@end

@implementation NSSegmentedCell (FerryDrawing)
- (void)drawSegment:(NSInteger)segment inFrame:(NSRect)frame withView:(NSView *)controlView
{
    NSImage *image = [self imageForSegment:segment];
    NSString *label = [self labelForSegment:segment];
    if (image) {
        NSSize s = [image size];
        [image drawInRect:NSMakeRect(NSMidX(frame) - s.width / 2, NSMidY(frame) - s.height / 2, s.width, s.height)
                 fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES
                    hints:nil];
    } else if ([label length]) {
        NSDictionary *a = @{NSFontAttributeName : [self font] ?: [NSFont systemFontOfSize:13]};
        NSSize s = [label sizeWithAttributes:a];
        [label drawAtPoint:NSMakePoint(NSMidX(frame) - s.width / 2, NSMidY(frame) - s.height / 2) withAttributes:a];
    }
}
@end

/* ---- scrollers ----------------------------------------------------------------------- */

static char arrows_key;

@implementation NSScroller (FerryArrows)
/* Ferry's scrollers have no arrows: the knob when there is room for it */
- (NSUsableScrollerParts)usableParts
{
    NSRect b = [self bounds];
    return MAX(b.size.width, b.size.height) > 2 * MIN(b.size.width, b.size.height) ? NSAllScrollerParts
                                                                                   : NSNoScrollerParts;
}
- (NSScrollArrowPosition)arrowsPosition
{
    NSNumber *n = assoc(self, &arrows_key);
    return n ? (NSScrollArrowPosition)[n integerValue] : NSScrollerArrowsNone;
}
- (void)setArrowsPosition:(NSScrollArrowPosition)p { set_assoc_int(self, &arrows_key, (NSInteger)p); }
- (void)drawArrow:(NSScrollerArrow)arrow highlight:(BOOL)flag
{
}
- (void)drawParts
{
}
- (void)highlight:(BOOL)flag
{
    [self setNeedsDisplay:YES];
}
@end

/* ---- views, controls and windows ----------------------------------------------------- */

@implementation NSView (FerryVLC)
- (NSView *)ancestorSharedWithView:(NSView *)view
{
    for (NSView *a = self; a; a = [a superview])
        if (view == a || [view isDescendantOf:a])
            return a;
    return nil;
}
@end

@implementation NSControl (FerryNeedsDisplay)
- (void)setNeedsDisplay { [self setNeedsDisplay:YES]; }
@end

@implementation NSWindow (FerryVLC)
- (void)useOptimizedDrawing:(BOOL)flag
{
}
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen
{
    screen = screen ?: [self screen] ?: [NSScreen mainScreen];
    if (!screen || ([self styleMask] & NSWindowStyleMaskFullScreen))
        return frameRect;
    NSRect v = [screen visibleFrame];
    NSRect r = frameRect;
    /* the title bar on the screen: not above the top, and not wholly below it */
    if (NSMaxY(r) > NSMaxY(v)) {
        CGFloat over = NSMaxY(r) - NSMaxY(v);
        if (([self styleMask] & NSWindowStyleMaskResizable) && r.size.height - over >= [self minSize].height) {
            r.origin.y = NSMaxY(v) - (r.size.height - over);
            r.size.height -= over;
        } else
            r.origin.y -= over;
        if (([self styleMask] & NSWindowStyleMaskResizable) == 0)
            r.origin.y = NSMaxY(v) - r.size.height;
    }
    if (NSMaxY(r) < NSMinY(v) + 22)
        r.origin.y = NSMinY(v) + 22 - r.size.height;
    return r;
}
@end

/* ---- events -------------------------------------------------------------------------- */

@implementation NSEvent (FerryGestures)
- (CGFloat)magnification { return 0; }
- (BOOL)isDirectionInvertedFromDevice { return NO; }
@end

/* ---- images and screens -------------------------------------------------------------- */

static char cap_insets_key, resizing_key;

@implementation NSImage (FerryCapInsets)
- (NSEdgeInsets)capInsets
{
    NSEdgeInsets insets = {0, 0, 0, 0};
    [(NSValue *)assoc(self, &cap_insets_key) getValue:&insets size:sizeof insets];
    return insets;
}
- (void)setCapInsets:(NSEdgeInsets)insets
{
    set_assoc(self, &cap_insets_key, [NSValue valueWithBytes:&insets objCType:@encode(NSEdgeInsets)]);
}
- (NSImageResizingMode)resizingMode { return (NSImageResizingMode)assoc_int(self, &resizing_key); }
- (void)setResizingMode:(NSImageResizingMode)mode { set_assoc_int(self, &resizing_key, mode); }
@end

@implementation NSScreen (FerryVLC)
+ (NSScreen *)deepestScreen { return [self mainScreen]; }
- (NSEdgeInsets)safeAreaInsets { return (NSEdgeInsets){0, 0, 0, 0}; }
- (NSRect)auxiliaryTopLeftArea { return NSZeroRect; }
- (NSRect)auxiliaryTopRightArea { return NSZeroRect; }
@end

/* ---- the visual effect view ---------------------------------------------------------- */

@implementation NSVisualEffectView {
    NSVisualEffectMaterial _material;
    NSVisualEffectBlendingMode _blending;
    NSVisualEffectState _state;
    BOOL _emphasized;
    NSImage *_mask;
}
- (void)dealloc
{
    [_mask release];
    [super dealloc];
}
- (NSVisualEffectMaterial)material { return _material; }
- (void)setMaterial:(NSVisualEffectMaterial)m
{
    _material = m;
    [self setNeedsDisplay:YES];
}
- (NSVisualEffectBlendingMode)blendingMode { return _blending; }
- (void)setBlendingMode:(NSVisualEffectBlendingMode)m { _blending = m; }
- (NSVisualEffectState)state { return _state; }
- (void)setState:(NSVisualEffectState)s { _state = s; }
- (BOOL)isEmphasized { return _emphasized; }
- (void)setEmphasized:(BOOL)f { _emphasized = f; }
- (NSImage *)maskImage { return _mask; }
- (void)setMaskImage:(NSImage *)image
{
    [_mask autorelease];
    _mask = [image retain];
    [self setNeedsDisplay:YES];
}
- (BOOL)_ferryDark
{
    switch (_material) {
    case NSVisualEffectMaterialDark:
    case NSVisualEffectMaterialUltraDark:
    case NSVisualEffectMaterialHUDWindow:
    case NSVisualEffectMaterialFullScreenUI:
        return YES;
    default:
        return NO;
    }
}
- (NSBackgroundStyle)interiorBackgroundStyle
{
    return [self _ferryDark] ? NSBackgroundStyleEmphasized : NSBackgroundStyleNormal;
}
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirty
{
    NSColor *c;
    switch (_material) {
    case NSVisualEffectMaterialDark: c = [NSColor colorWithWhite:0.16 alpha:0.94]; break;
    case NSVisualEffectMaterialUltraDark: c = [NSColor colorWithWhite:0.08 alpha:0.96]; break;
    case NSVisualEffectMaterialHUDWindow:
    case NSVisualEffectMaterialFullScreenUI: c = [NSColor colorWithWhite:0.12 alpha:0.86]; break;
    case NSVisualEffectMaterialSelection: c = [[NSColor controlAccentColor] colorWithAlphaComponent:0.9]; break;
    case NSVisualEffectMaterialMediumLight: c = [NSColor colorWithWhite:0.88 alpha:0.94]; break;
    default: c = [NSColor colorWithWhite:0.96 alpha:0.94]; break;
    }
    NSRect b = [self bounds];
    if (_mask) {
        /* the mask's shape: drawn stretched (by its cap insets) and filled in */
        [_mask drawInRect:b fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
           respectFlipped:YES hints:nil];
        [c setFill];
        NSRectFillUsingOperation(b, NSCompositingOperationSourceIn);
    } else {
        [c setFill];
        NSRectFillUsingOperation(b, NSCompositingOperationSourceOver);
    }
}
@end

/* ---- the workspace ------------------------------------------------------------------- */

@implementation NSWorkspace (FerryFileSystemInfo)
- (BOOL)getFileSystemInfoForPath:(NSString *)fullPath isRemovable:(BOOL *)removableFlag
                      isWritable:(BOOL *)writableFlag isUnmountable:(BOOL *)unmountableFlag
                     description:(NSString **)description type:(NSString **)fileSystemType
{
    const char *path = [fullPath fileSystemRepresentation];
    struct statfs fs;
    if (!path || statfs(path, &fs) != 0)
        return NO;
    const char *dir = fs.f_mntonname;
    BOOL removable = strncmp(dir, "/media/", 7) == 0 || strncmp(dir, "/run/media/", 11) == 0 ||
                     strncmp(dir, "/Volumes/", 9) == 0;
    BOOL readOnly = (fs.f_flags & MNT_RDONLY) != 0;
    if (removableFlag)
        *removableFlag = removable;
    if (unmountableFlag)
        *unmountableFlag = removable;
    if (writableFlag)
        *writableFlag = !readOnly;
    if (fileSystemType)
        *fileSystemType = [NSString stringWithUTF8String:fs.f_fstypename];
    if (description)
        *description = removable ? @"Removable Disk" : @"Local Disk";
    return YES;
}
@end

/* ---- attributed strings -------------------------------------------------------------- */

NSAttributedStringDocumentReadingOptionKey const NSBaseURLDocumentOption = @"BaseURL";

@implementation NSAttributedString (FerryHTMLOptions)
- (instancetype)initWithHTML:(NSData *)data options:(NSDictionary *)options
          documentAttributes:(NSDictionary **)attributes
{
    NSURL *base = options[NSBaseURLDocumentOption];
    return [self initWithHTML:data baseURL:base documentAttributes:attributes];
}
@end

@implementation NSMutableAttributedString (FerryAlignment)
- (void)_ferrySetParagraphs:(NSRange)range change:(void (^)(NSMutableParagraphStyle *))change
{
    NSRange whole = [[self string] paragraphRangeForRange:range];
    [self beginEditing];
    [self enumerateAttribute:NSParagraphStyleAttributeName inRange:whole options:0
                  usingBlock:^(id value, NSRange r, BOOL *stop) {
                      NSMutableParagraphStyle *p =
                          [[(value ?: [NSParagraphStyle defaultParagraphStyle]) mutableCopy] autorelease];
                      change(p);
                      [self addAttribute:NSParagraphStyleAttributeName value:p range:r];
                  }];
    [self endEditing];
}
- (void)setAlignment:(NSTextAlignment)alignment range:(NSRange)range
{
    [self _ferrySetParagraphs:range change:^(NSMutableParagraphStyle *p) { [p setAlignment:alignment]; }];
}
- (void)setBaseWritingDirection:(NSWritingDirection)direction range:(NSRange)range
{
    [self _ferrySetParagraphs:range change:^(NSMutableParagraphStyle *p) { [p setBaseWritingDirection:direction]; }];
}
@end

@implementation NSControl (FerrySelectedCell)
- (NSCell *)selectedCell { return [self cell]; }
@end

/* The host's mount table names every mount point; removable disks are the ones
 * mounted where desktops put them (freemac 1.NEXT, VLC). */
@implementation NSWorkspace (FerryRemovableMedia)
- (NSArray<NSString *> *)mountedRemovableMedia
{
    NSMutableArray *out = [NSMutableArray array];
    NSString *table = [NSString stringWithContentsOfFile:@"/proc/self/mounts" encoding:NSUTF8StringEncoding error:NULL];
    for (NSString *line in [table componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@" "];
        if ([f count] < 2)
            continue;
        NSString *dir = [[[[f objectAtIndex:1] stringByReplacingOccurrencesOfString:@"\\040" withString:@" "]
            stringByReplacingOccurrencesOfString:@"\\011" withString:@"\t"]
            stringByReplacingOccurrencesOfString:@"\\134" withString:@"\\"];
        if ([dir hasPrefix:@"/media/"] || [dir hasPrefix:@"/run/media/"] || [dir hasPrefix:@"/Volumes/"])
            [out addObject:dir];
    }
    return out;
}
@end
