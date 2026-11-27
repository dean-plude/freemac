/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * What the IINA video player calls besides the rest of AppKit (freemac
 * 1.262, Ferry 0.85.0): see AppKitIINA.h. Written from Apple's public
 * documentation; no Apple code was read. */
#import "AInternal.h"
#import <objc/runtime.h>
#include <string.h>

static id assoc(id obj, const void *key) { return objc_getAssociatedObject(obj, key); }
static void set_assoc(id obj, const void *key, id value)
{
    objc_setAssociatedObject(obj, key, value, OBJC_ASSOCIATION_RETAIN);
}

/* ---- windows ------------------------------------------------------------------------- */

static char aspect_key, content_aspect_key;

static void apply_aspect(NSWindow *w, NSSize ratio)
{
    GtkWidget *g = [w _gtkWindow];
    if (!g)
        return;
    GdkGeometry geo = {0};
    if (ratio.width > 0 && ratio.height > 0) {
        geo.min_aspect = geo.max_aspect = ratio.width / ratio.height;
        gtk_window_set_geometry_hints(g, NULL, &geo, GDK_HINT_ASPECT);
    } else {
        gtk_window_set_geometry_hints(g, NULL, &geo, 0);
    }
}

@implementation NSWindow (FerryAspectRatio)
- (NSSize)aspectRatio { return [(NSValue *)assoc(self, &aspect_key) sizeValue]; }
- (void)setAspectRatio:(NSSize)ratio
{
    set_assoc(self, &aspect_key, [NSValue valueWithSize:ratio]);
    set_assoc(self, &content_aspect_key, nil);   /* as documented: the two replace each other */
    apply_aspect(self, ratio);
}
- (NSSize)contentAspectRatio { return [(NSValue *)assoc(self, &content_aspect_key) sizeValue]; }
- (void)setContentAspectRatio:(NSSize)ratio
{
    set_assoc(self, &content_aspect_key, [NSValue valueWithSize:ratio]);
    set_assoc(self, &aspect_key, nil);
    apply_aspect(self, ratio);
}
- (void)performWindowDragWithEvent:(NSEvent *)event
{
    GtkWidget *g = [self _gtkWindow];
    GdkEvent *e = gtk_get_current_event();
    if (g && e) {
        double x = 0, y = 0;
        unsigned button = 1;
        gdk_event_get_root_coords(e, &x, &y);
        gdk_event_get_button(e, &button);
        gtk_window_begin_move_drag(g, (int)button, (int)x, (int)y, gdk_event_get_time(e));
    }
    if (e)
        gdk_event_free(e);
}
@end

/* ---- gesture recognizers --------------------------------------------------------------- */

@implementation NSGestureRecognizer {
    id _target;                       /* not retained, as on a Mac */
    SEL _action;
    id _delegate;                     /* not retained */
    NSView *_view;                    /* not retained */
    BOOL _enabled, _delaysPrimary, _delaysSecondary;
}
- (instancetype)initWithTarget:(id)target action:(SEL)action
{
    if ((self = [super init])) {
        _target = target;
        _action = action;
        _enabled = YES;
    }
    return self;
}
- (instancetype)init { return [self initWithTarget:nil action:NULL]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self initWithTarget:nil action:NULL])) {
        if ([coder containsValueForKey:@"NSGestureRecognizer.enabled"])
            _enabled = [coder decodeBoolForKey:@"NSGestureRecognizer.enabled"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeBool:_enabled forKey:@"NSGestureRecognizer.enabled"]; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (NSGestureRecognizerState)state { return NSGestureRecognizerStatePossible; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)e { _enabled = e; }
- (NSView *)view { return _view; }
- (void)_setView:(NSView *)v { _view = v; }
- (BOOL)delaysPrimaryMouseButtonEvents { return _delaysPrimary; }
- (void)setDelaysPrimaryMouseButtonEvents:(BOOL)b { _delaysPrimary = b; }
- (BOOL)delaysSecondaryMouseButtonEvents { return _delaysSecondary; }
- (void)setDelaysSecondaryMouseButtonEvents:(BOOL)b { _delaysSecondary = b; }
- (NSPoint)locationInView:(NSView *)view
{
    NSWindow *w = [view window] ?: [_view window];
    NSPoint p = [w mouseLocationOutsideOfEventStream];
    return view ? [view convertPoint:p fromView:nil] : p;
}
@end

@implementation NSClickGestureRecognizer {
    NSUInteger _mask, _clicks, _touches;
}
- (instancetype)initWithTarget:(id)target action:(SEL)action
{
    if ((self = [super initWithTarget:target action:action])) {
        _mask = 1;
        _clicks = 1;
        _touches = 1;
    }
    return self;
}
- (NSUInteger)buttonMask { return _mask; }
- (void)setButtonMask:(NSUInteger)m { _mask = m; }
- (NSUInteger)numberOfClicksRequired { return _clicks; }
- (void)setNumberOfClicksRequired:(NSUInteger)n { _clicks = n; }
- (NSUInteger)numberOfTouchesRequired { return _touches; }
- (void)setNumberOfTouchesRequired:(NSUInteger)n { _touches = n; }
@end

@implementation NSPressGestureRecognizer {
    NSUInteger _mask, _touches;
    NSTimeInterval _duration;
    CGFloat _movement;
}
- (instancetype)initWithTarget:(id)target action:(SEL)action
{
    if ((self = [super initWithTarget:target action:action])) {
        _mask = 1;
        _touches = 1;
        _duration = 0.5;
        _movement = 10;
    }
    return self;
}
- (NSUInteger)buttonMask { return _mask; }
- (void)setButtonMask:(NSUInteger)m { _mask = m; }
- (NSUInteger)numberOfTouchesRequired { return _touches; }
- (void)setNumberOfTouchesRequired:(NSUInteger)n { _touches = n; }
- (NSTimeInterval)minimumPressDuration { return _duration; }
- (void)setMinimumPressDuration:(NSTimeInterval)d { _duration = d; }
- (CGFloat)allowableMovement { return _movement; }
- (void)setAllowableMovement:(CGFloat)m { _movement = m; }
@end

@implementation NSPanGestureRecognizer {
    NSUInteger _mask, _touches;
    NSPoint _translation;
}
- (instancetype)initWithTarget:(id)target action:(SEL)action
{
    if ((self = [super initWithTarget:target action:action])) {
        _mask = 1;
        _touches = 1;
    }
    return self;
}
- (NSUInteger)buttonMask { return _mask; }
- (void)setButtonMask:(NSUInteger)m { _mask = m; }
- (NSUInteger)numberOfTouchesRequired { return _touches; }
- (void)setNumberOfTouchesRequired:(NSUInteger)n { _touches = n; }
- (NSPoint)translationInView:(NSView *)view { return _translation; }
- (void)setTranslation:(NSPoint)t inView:(NSView *)view { _translation = t; }
- (NSPoint)velocityInView:(NSView *)view { return NSZeroPoint; }
@end

@implementation NSMagnificationGestureRecognizer {
    CGFloat _magnification;
}
- (CGFloat)magnification { return _magnification; }
- (void)setMagnification:(CGFloat)m { _magnification = m; }
@end

@implementation NSRotationGestureRecognizer {
    CGFloat _rotation;
}
- (CGFloat)rotation { return _rotation; }
- (void)setRotation:(CGFloat)r { _rotation = r; }
- (CGFloat)rotationInDegrees { return _rotation * 180 / M_PI; }
- (void)setRotationInDegrees:(CGFloat)d { _rotation = d * M_PI / 180; }
@end

static char gestures_key;

@implementation NSView (FerryGestureRecognizers)
- (NSArray *)gestureRecognizers { return [[(NSArray *)assoc(self, &gestures_key) copy] autorelease] ?: @[]; }
- (void)setGestureRecognizers:(NSArray *)list
{
    for (NSGestureRecognizer *g in [self gestureRecognizers])
        [g _setView:nil];
    set_assoc(self, &gestures_key, [[list mutableCopy] autorelease]);
    for (NSGestureRecognizer *g in list)
        [g _setView:self];
}
- (void)addGestureRecognizer:(NSGestureRecognizer *)g
{
    if (!g)
        return;
    NSMutableArray *list = assoc(self, &gestures_key);
    if (!list) {
        list = [NSMutableArray array];
        set_assoc(self, &gestures_key, list);
    }
    if (![list containsObject:g]) {
        [[g view] removeGestureRecognizer:g];
        [list addObject:g];
        [g _setView:self];
    }
}
- (void)removeGestureRecognizer:(NSGestureRecognizer *)g
{
    NSMutableArray *list = assoc(self, &gestures_key);
    if (g && [list containsObject:g]) {
        [g _setView:nil];
        [list removeObject:g];
    }
}
@end

/* ---- a reversed path ------------------------------------------------------------------ */

@implementation NSBezierPath (FerryReversing)
- (NSBezierPath *)bezierPathByReversingPath
{
    NSBezierPath *out = [[self copy] autorelease];
    [out removeAllPoints];
    NSInteger n = [self elementCount];
    NSInteger i = 0;
    while (i < n) {
        /* one subpath: a move, then lines and curves, maybe a close */
        NSPoint pts[3];
        NSBezierPathElement e = [self elementAtIndex:i associatedPoints:pts];
        if (e != NSBezierPathElementMoveTo) {
            i++;
            continue;
        }
        NSInteger start = i++;
        NSPoint first = pts[0];
        BOOL closed = NO;
        while (i < n) {
            e = [self elementAtIndex:i associatedPoints:pts];
            if (e == NSBezierPathElementMoveTo)
                break;
            i++;
            if (e == NSBezierPathElementClosePath) {
                closed = YES;
                break;
            }
        }
        NSInteger end = closed ? i - 1 : i;   /* elements start..end-1 */
        /* the end point of element k */
        NSPoint (^endOf)(NSInteger) = ^NSPoint(NSInteger k) {
            NSPoint p[3];
            NSBezierPathElement t = [self elementAtIndex:k associatedPoints:p];
            return t == NSBezierPathElementCurveTo ? p[2] : p[0];
        };
        NSPoint last = endOf(end - 1);
        if (closed && (last.x != first.x || last.y != first.y)) {
            /* a close draws a line back to the start: the reverse starts there */
            [out moveToPoint:first];
            [out lineToPoint:last];
        } else {
            [out moveToPoint:last];
        }
        for (NSInteger k = end - 1; k > start; k--) {
            NSPoint p[3];
            NSBezierPathElement t = [self elementAtIndex:k associatedPoints:p];
            NSPoint to = endOf(k - 1);
            if (t == NSBezierPathElementCurveTo)
                [out curveToPoint:to controlPoint1:p[1] controlPoint2:p[0]];
            else
                [out lineToPoint:to];
        }
        if (closed)
            [out closePath];
    }
    return out;
}
@end

/* ---- the rest ------------------------------------------------------------------------- */

@implementation NSColor (FerrySystemEffect)
- (NSColor *)colorWithSystemEffect:(NSColorSystemEffect)effect
{
    switch (effect) {
    case NSColorSystemEffectPressed: return [self shadowWithLevel:0.15] ?: self;
    case NSColorSystemEffectDeepPressed: return [self shadowWithLevel:0.3] ?: self;
    case NSColorSystemEffectDisabled: return [self colorWithAlphaComponent:[self alphaComponent] * 0.5];
    case NSColorSystemEffectRollover: return [self highlightWithLevel:0.1] ?: self;
    default: return self;
    }
}
@end

static BOOL menu_bar_visible = YES;

@implementation NSMenu (FerryMenuBarVisible)
+ (BOOL)menuBarVisible { return menu_bar_visible; }
+ (void)setMenuBarVisible:(BOOL)visible { menu_bar_visible = visible; }
@end

@implementation NSTextView (FerrySelectedRanges)
- (void)setSelectedRanges:(NSArray *)ranges
{
    if ([ranges count])
        [self setSelectedRange:[ranges[0] rangeValue]];
}
@end

@implementation NSApplication (FerryTouchBarCustomization)
- (void)toggleTouchBarCustomizationPalette:(id)sender {}
@end

/* ---- CMTime values in an NSValue (AVFoundation's) ------------------------------------- */

#import <AVFoundation/AVFoundation.h>

@implementation NSValue (FerryCMTime)
+ (NSValue *)valueWithCMTime:(CMTime)t { return [NSValue valueWithBytes:&t objCType:@encode(CMTime)]; }
- (CMTime)CMTimeValue
{
    CMTime t = kCMTimeInvalid;
    if (!strcmp([self objCType], @encode(CMTime)))
        [self getValue:&t];
    return t;
}
+ (NSValue *)valueWithCMTimeRange:(CMTimeRange)r { return [NSValue valueWithBytes:&r objCType:@encode(CMTimeRange)]; }
- (CMTimeRange)CMTimeRangeValue
{
    CMTimeRange r = {kCMTimeInvalid, kCMTimeInvalid};
    if (!strcmp([self objCType], @encode(CMTimeRange)))
        [self getValue:&r];
    return r;
}
+ (NSValue *)valueWithCMTimeMapping:(CMTimeMapping)m { return [NSValue valueWithBytes:&m objCType:@encode(CMTimeMapping)]; }
- (CMTimeMapping)CMTimeMappingValue
{
    CMTimeMapping m = {{kCMTimeInvalid, kCMTimeInvalid}, {kCMTimeInvalid, kCMTimeInvalid}};
    if (!strcmp([self objCType], @encode(CMTimeMapping)))
        [self getValue:&m];
    return m;
}
@end
