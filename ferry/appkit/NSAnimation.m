/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSAnimation and NSViewAnimation, written from Apple's
 * public documentation. An animation runs on a timer in the current run
 * loop at its frame rate: each frame sets its progress (the time gone by
 * over its duration) with setCurrentProgress:, which subclasses override
 * to do their work, and passes any progress marks crossed on to the
 * delegate, the progress-mark notification and the animations started or
 * stopped by them. A blocking animation runs the run loop in a mode of its
 * own until it ends, so nothing else happens meanwhile; a non-blocking one
 * runs in the modes runLoopModesForAnimating gives (the default, modal
 * panel and event tracking modes when it gives none) and startAnimation
 * returns at once. The threaded mode runs like the non-blocking one, on
 * the thread that started it. currentValue is the progress through the
 * curve, or what the delegate makes of it. A view animation moves and
 * resizes views and windows between their start and end frames and fades
 * them in or out; a view faded out, or given an empty end frame, is
 * hidden at the end, and a window faded out is ordered out. Built without
 * ARC. */
#import "AInternal.h"
#include <math.h>

NSNotificationName const NSAnimationProgressMarkNotification = @"NSAnimationProgressMarkNotification";
NSString *const NSAnimationProgressMark = @"NSAnimationProgressMark";
NSViewAnimationKey const NSViewAnimationTargetKey = @"NSViewAnimationTargetKey";
NSViewAnimationKey const NSViewAnimationStartFrameKey = @"NSViewAnimationStartFrameKey";
NSViewAnimationKey const NSViewAnimationEndFrameKey = @"NSViewAnimationEndFrameKey";
NSViewAnimationKey const NSViewAnimationEffectKey = @"NSViewAnimationEffectKey";
NSViewAnimationEffectName const NSViewAnimationFadeInEffect = @"NSViewAnimationFadeInEffect";
NSViewAnimationEffectName const NSViewAnimationFadeOutEffect = @"NSViewAnimationFadeOutEffect";

static NSString *const blocking_mode = @"NSAnimationBlockingRunLoopMode";

/* Another animation started or stopped when this one reaches a progress. */
@interface ALink : NSObject {
@public
    NSAnimation *other;     /* not retained; it clears the link when it goes */
    NSAnimationProgress at;
    BOOL starts;
}
@end
@implementation ALink
@end

@implementation NSAnimation {
    NSTimeInterval _duration, _started;
    NSAnimationCurve _curve;
    NSAnimationBlockingMode _mode;
    float _frameRate;
    NSAnimationProgress _progress;
    id _delegate;
    NSMutableArray *_marks;     /* NSNumbers, in order */
    NSMutableArray *_links;     /* ALinks for the animations this one starts or stops */
    NSAnimation *_startsWith, *_stopsWith;      /* not retained */
    NSTimer *_timer;
    BOOL _animating;
}

- (instancetype)initWithDuration:(NSTimeInterval)duration animationCurve:(NSAnimationCurve)curve
{
    if ((self = [super init])) {
        _duration = duration < 0 ? 0 : duration;
        _curve = curve;
        _mode = NSAnimationBlocking;
        _frameRate = 60;
        _marks = [[NSMutableArray alloc] init];
        _links = [[NSMutableArray alloc] init];
    }
    return self;
}
- (instancetype)init { return [self initWithDuration:1 animationCurve:NSAnimationEaseInOut]; }

- (void)dealloc
{
    [_timer invalidate];
    [_timer release];
    [self clearStartAnimation];
    [self clearStopAnimation];
    for (ALink *l in _links) {
        if (l->other->_startsWith == self)
            l->other->_startsWith = nil;
        if (l->other->_stopsWith == self)
            l->other->_stopsWith = nil;
    }
    [_links release];
    [_marks release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSAnimation *a = [[[self class] allocWithZone:zone] initWithDuration:_duration animationCurve:_curve];
    a->_mode = _mode;
    a->_frameRate = _frameRate;
    a->_delegate = _delegate;
    [a->_marks setArray:_marks];
    return a;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self initWithDuration:[coder decodeDoubleForKey:@"NSAnimationDuration"]
                        animationCurve:(NSAnimationCurve)[coder decodeIntegerForKey:@"NSAnimationCurve"]])) {
        _mode = (NSAnimationBlockingMode)[coder decodeIntegerForKey:@"NSAnimationBlockingMode"];
        if ([coder containsValueForKey:@"NSAnimationFrameRate"])
            _frameRate = [coder decodeFloatForKey:@"NSAnimationFrameRate"];
        NSArray *marks = [coder decodeObjectForKey:@"NSAnimationProgressMarks"];
        if ([marks isKindOfClass:[NSArray class]])
            [self setProgressMarks:marks];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_duration forKey:@"NSAnimationDuration"];
    [coder encodeInteger:(NSInteger)_curve forKey:@"NSAnimationCurve"];
    [coder encodeInteger:(NSInteger)_mode forKey:@"NSAnimationBlockingMode"];
    [coder encodeFloat:_frameRate forKey:@"NSAnimationFrameRate"];
    [coder encodeObject:_marks forKey:@"NSAnimationProgressMarks"];
}

- (NSTimeInterval)duration { return _duration; }
- (void)setDuration:(NSTimeInterval)duration
{
    if (duration < 0)
        [NSException raise:NSInvalidArgumentException format:@"-[NSAnimation setDuration:]: %g is below 0", duration];
    _duration = duration;
}
- (NSAnimationCurve)animationCurve { return _curve; }
- (void)setAnimationCurve:(NSAnimationCurve)curve
{
    if (curve > NSAnimationLinear)
        [NSException raise:NSInvalidArgumentException format:@"-[NSAnimation setAnimationCurve:]: no curve %lu",
                                                              (unsigned long)curve];
    _curve = curve;
}
- (NSAnimationBlockingMode)animationBlockingMode { return _mode; }
- (void)setAnimationBlockingMode:(NSAnimationBlockingMode)mode { _mode = mode; }
- (float)frameRate { return _frameRate; }
- (void)setFrameRate:(float)rate
{
    if (rate < 0)
        [NSException raise:NSInvalidArgumentException format:@"-[NSAnimation setFrameRate:]: %g is below 0", rate];
    _frameRate = rate;
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (BOOL)isAnimating { return _animating; }
- (NSArray *)runLoopModesForAnimating { return nil; }

- (NSAnimationProgress)currentProgress { return _progress; }
- (void)setCurrentProgress:(NSAnimationProgress)progress
{
    _progress = progress < 0 ? 0 : progress > 1 ? 1 : progress;
    /* set while it runs, the clock follows */
    if (_animating)
        _started = [NSDate timeIntervalSinceReferenceDate] - _progress * _duration;
}

- (float)currentValue
{
    float t = _progress;
    if ([_delegate respondsToSelector:@selector(animation:valueForProgress:)])
        return [_delegate animation:self valueForProgress:t];
    switch (_curve) {
    case NSAnimationEaseIn:
        return (float)(1 - cos(t * M_PI / 2));
    case NSAnimationEaseOut:
        return (float)sin(t * M_PI / 2);
    case NSAnimationLinear:
        return t;
    case NSAnimationEaseInOut:
    default:
        return (float)((1 - cos(t * M_PI)) / 2);
    }
}

/* ---- progress marks ------------------------------------------------------------------- */

- (NSArray *)progressMarks { return [[_marks copy] autorelease]; }
- (void)setProgressMarks:(NSArray *)marks
{
    [_marks removeAllObjects];
    for (NSNumber *m in marks)
        [self addProgressMark:[m floatValue]];
}
- (void)addProgressMark:(NSAnimationProgress)mark
{
    mark = mark < 0 ? 0 : mark > 1 ? 1 : mark;
    NSUInteger i = 0;
    for (; i < [_marks count]; i++) {
        float m = [_marks[i] floatValue];
        if (m == mark)
            return;
        if (m > mark)
            break;
    }
    [_marks insertObject:@(mark) atIndex:i];
}
- (void)removeProgressMark:(NSAnimationProgress)mark
{
    for (NSUInteger i = 0; i < [_marks count]; i++)
        if ([_marks[i] floatValue] == mark) {
            [_marks removeObjectAtIndex:i];
            return;
        }
}

static void link_to(NSAnimation *self, NSAnimation *other, NSAnimationProgress at, BOOL starts)
{
    ALink *l = [[ALink alloc] init];
    l->other = self;
    l->at = at;
    l->starts = starts;
    [other->_links addObject:l];
    [l release];
    [other addProgressMark:at];
}
static void unlink_from(NSAnimation *self, NSAnimation *other, BOOL starts)
{
    for (NSInteger i = (NSInteger)[other->_links count] - 1; i >= 0; i--) {
        ALink *l = other->_links[(NSUInteger)i];
        if (l->other == self && l->starts == starts)
            [other->_links removeObjectAtIndex:(NSUInteger)i];
    }
}
- (void)startWhenAnimation:(NSAnimation *)animation reachesProgress:(NSAnimationProgress)progress
{
    [self clearStartAnimation];
    if (!animation || animation == self)
        return;
    _startsWith = animation;
    link_to(self, animation, progress, YES);
}
- (void)stopWhenAnimation:(NSAnimation *)animation reachesProgress:(NSAnimationProgress)progress
{
    [self clearStopAnimation];
    if (!animation || animation == self)
        return;
    _stopsWith = animation;
    link_to(self, animation, progress, NO);
}
- (void)clearStartAnimation
{
    if (_startsWith)
        unlink_from(self, _startsWith, YES);
    _startsWith = nil;
}
- (void)clearStopAnimation
{
    if (_stopsWith)
        unlink_from(self, _stopsWith, NO);
    _stopsWith = nil;
}

/* The marks passed going from one progress to the next. */
- (void)_reachedFrom:(NSAnimationProgress)from to:(NSAnimationProgress)to
{
    for (NSNumber *n in [[_marks copy] autorelease]) {
        float m = [n floatValue];
        if (from == to ? m != from : (m <= from || m > to))
            continue;
        if ([_delegate respondsToSelector:@selector(animation:didReachProgressMark:)])
            [_delegate animation:self didReachProgressMark:m];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSAnimationProgressMarkNotification
                                                            object:self
                                                          userInfo:@{NSAnimationProgressMark : @(m)}];
        for (ALink *l in [[_links copy] autorelease])
            if (l->at == m) {
                if (l->starts)
                    [l->other startAnimation];
                else
                    [l->other stopAnimation];
            }
    }
}

/* ---- running -------------------------------------------------------------------------- */

- (void)_frame:(NSTimer *)timer
{
    if (!_animating)
        return;
    [self retain];
    NSTimeInterval gone = [NSDate timeIntervalSinceReferenceDate] - _started;
    NSAnimationProgress from = _progress;
    NSAnimationProgress to = _duration > 0 ? (NSAnimationProgress)(gone / _duration) : 1;
    if (to > 1)
        to = 1;
    if (to < from)
        to = from;
    [self setCurrentProgress:to];
    if (to > from)
        [self _reachedFrom:from to:to];
    if (_animating && _progress >= 1) {
        _animating = NO;
        [_timer invalidate];
        [_timer release];
        _timer = nil;
        if ([_delegate respondsToSelector:@selector(animationDidEnd:)])
            [_delegate animationDidEnd:self];
    }
    [self release];
}

- (void)startAnimation
{
    if (_animating)
        return;
    if ([_delegate respondsToSelector:@selector(animationShouldStart:)] && ![_delegate animationShouldStart:self])
        return;
    [self retain];
    if (_progress >= 1)
        _progress = 0;
    _animating = YES;
    _started = [NSDate timeIntervalSinceReferenceDate] - _progress * _duration;
    if (_progress == 0)
        [self _reachedFrom:0 to:0];      /* a mark at 0 is reached as it starts */
    NSTimeInterval step = 1.0 / (_frameRate > 0 ? _frameRate : 60);
    _timer = [[NSTimer timerWithTimeInterval:step target:self selector:@selector(_frame:) userInfo:nil
                                     repeats:YES] retain];
    NSRunLoop *loop = [NSRunLoop currentRunLoop];
    if (_mode == NSAnimationBlocking) {
        [loop addTimer:_timer forMode:blocking_mode];
        while (_animating) {
            @autoreleasepool {
                [loop runMode:blocking_mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:step]];
            }
        }
    } else {
        NSArray *modes = [self runLoopModesForAnimating];
        if (![modes count])
            modes = @[ NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode" ];
        for (NSString *m in modes)
            [loop addTimer:_timer forMode:m];
        if (_duration <= 0)
            [self _frame:_timer];
    }
    [self release];
}

- (void)stopAnimation
{
    if (!_animating)
        return;
    _animating = NO;
    [_timer invalidate];
    [_timer release];
    _timer = nil;
    if ([_delegate respondsToSelector:@selector(animationDidStop:)])
        [_delegate animationDidStop:self];
}
@end

/* ---- NSViewAnimation ------------------------------------------------------------------ */

@implementation NSViewAnimation {
    NSArray *_animations;
    NSMutableArray *_starts, *_ends;    /* NSValues of the frames, set as it starts */
    NSMutableArray *_alphas;            /* the alpha each target had when it started */
}

- (instancetype)initWithViewAnimations:(NSArray *)animations
{
    if ((self = [super initWithDuration:0.5 animationCurve:NSAnimationEaseInOut]))
        _animations = [animations copy];
    return self;
}
- (instancetype)initWithDuration:(NSTimeInterval)duration animationCurve:(NSAnimationCurve)curve
{
    return [super initWithDuration:duration animationCurve:curve];
}
- (void)dealloc
{
    [_animations release];
    [_starts release];
    [_ends release];
    [_alphas release];
    [super dealloc];
}
- (NSArray *)viewAnimations { return _animations ?: @[]; }
- (void)setViewAnimations:(NSArray *)animations
{
    if (animations == _animations)
        return;
    id wasAnimations = _animations;
    _animations = [animations copy];
    [wasAnimations release];
}

static NSRect frame_of(id target) { return [target frame]; }
static BOOL is_window(id target) { return [target isKindOfClass:[NSWindow class]]; }

- (void)startAnimation
{
    if ([self isAnimating])
        return;
    if ([self currentProgress] >= 1 || [self currentProgress] == 0 || !_starts) {
        [_starts release];
        [_ends release];
        [_alphas release];
        _starts = [[NSMutableArray alloc] init];
        _ends = [[NSMutableArray alloc] init];
        _alphas = [[NSMutableArray alloc] init];
        for (NSDictionary *d in [self viewAnimations]) {
            id target = d[NSViewAnimationTargetKey];
            NSRect now = target ? frame_of(target) : NSZeroRect;
            NSValue *s = d[NSViewAnimationStartFrameKey], *e = d[NSViewAnimationEndFrameKey];
            [_starts addObject:[NSValue valueWithRect:s ? [s rectValue] : now]];
            [_ends addObject:[NSValue valueWithRect:e ? [e rectValue] : now]];
            CGFloat alpha = target ? [target alphaValue] : 1;
            NSString *effect = d[NSViewAnimationEffectKey];
            if ([effect isEqual:NSViewAnimationFadeInEffect]) {
                /* a hidden target is shown, from clear */
                if (is_window(target) && ![target isVisible]) {
                    [target setAlphaValue:0];
                    [target orderFront:nil];
                } else if (!is_window(target) && [target isHidden]) {
                    [target setAlphaValue:0];
                    [target setHidden:NO];
                } else if (alpha >= 1) {
                    [target setAlphaValue:0];
                }
            }
            [_alphas addObject:@(alpha > 0 ? alpha : 1)];
        }
    }
    [super startAnimation];
}

- (void)setCurrentProgress:(NSAnimationProgress)progress
{
    [super setCurrentProgress:progress];
    if (!_starts)
        return;
    float v = [self currentValue];
    NSArray *list = [self viewAnimations];
    for (NSUInteger i = 0; i < [list count] && i < [_starts count]; i++) {
        NSDictionary *d = list[i];
        id target = d[NSViewAnimationTargetKey];
        if (!target)
            continue;
        NSRect a = [_starts[i] rectValue], b = [_ends[i] rectValue];
        NSRect f = NSMakeRect(a.origin.x + (b.origin.x - a.origin.x) * v, a.origin.y + (b.origin.y - a.origin.y) * v,
                              a.size.width + (b.size.width - a.size.width) * v,
                              a.size.height + (b.size.height - a.size.height) * v);
        if (d[NSViewAnimationStartFrameKey] || d[NSViewAnimationEndFrameKey]) {
            if (is_window(target))
                [target setFrame:f display:YES];
            else
                [(NSView *)target setFrame:f];
        }
        NSString *effect = d[NSViewAnimationEffectKey];
        CGFloat full = [_alphas[i] doubleValue];
        if ([effect isEqual:NSViewAnimationFadeInEffect])
            [target setAlphaValue:full * v];
        else if ([effect isEqual:NSViewAnimationFadeOutEffect])
            [target setAlphaValue:full * (1 - v)];
        if ([self currentProgress] >= 1) {
            BOOL fadedOut = [effect isEqual:NSViewAnimationFadeOutEffect];
            if (is_window(target)) {
                if (fadedOut) {
                    [target orderOut:nil];
                    [target setAlphaValue:full];
                }
            } else if (fadedOut || (d[NSViewAnimationEndFrameKey] && NSIsEmptyRect(b) && b.size.width == 0 &&
                                    b.size.height == 0)) {
                [target setHidden:YES];
                if (fadedOut)
                    [target setAlphaValue:full];
            }
        }
    }
}
@end
