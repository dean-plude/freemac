/* SPDX-License-Identifier: GPL-3.0-or-later
 * CADisplayLink (freemac 1.232, Ferry 0.56.0): a timer at the display's
 * rate, 60 frames a second, that calls its target with itself. Written from
 * Apple's public documentation. */
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

const CAFrameRateRange CAFrameRateRangeDefault = {0, 0, 0};
CAFrameRateRange CAFrameRateRangeMake(float minimum, float maximum, float preferred)
{
    CAFrameRateRange r = {minimum, maximum, preferred};
    return r;
}

/* The timer's target, so that the link isn't retained by its own timer
 * beyond what the run loop holds. */
@interface QDisplayLinkTick : NSObject {
@public
    CADisplayLink *_link;    /* not retained */
}
@end

@interface CADisplayLink ()
- (void)_tick;
@end

@implementation QDisplayLinkTick
- (void)tick:(NSTimer *)t { [_link _tick]; }
@end

@implementation CADisplayLink {
    id _target;    /* retained, as on a Mac, until invalidated */
    SEL _sel;
    NSTimer *_timer;
    QDisplayLinkTick *_tick;
    CFTimeInterval _timestamp;
    BOOL _paused, _invalid;
    NSInteger _fps;
    CAFrameRateRange _range;
}
+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel
{
    CADisplayLink *l = [[self alloc] init];
    l->_target = [target retain];
    l->_sel = sel;
    l->_tick = [[QDisplayLinkTick alloc] init];
    l->_tick->_link = l;
    return [l autorelease];
}
- (void)dealloc
{
    [_timer invalidate];
    [_timer release];
    [_tick release];
    [_target release];
    [super dealloc];
}
- (CFTimeInterval)duration
{
    NSInteger fps = _fps > 0 ? _fps : _range.preferred > 0 ? (NSInteger)_range.preferred : 60;
    return 1.0 / fps;
}
- (CFTimeInterval)timestamp { return _timestamp; }
- (CFTimeInterval)targetTimestamp { return _timestamp + [self duration]; }
- (BOOL)isPaused { return _paused; }
- (void)setPaused:(BOOL)p { _paused = p; }
- (NSInteger)preferredFramesPerSecond { return _fps; }
- (void)setPreferredFramesPerSecond:(NSInteger)fps { _fps = fps; }
- (CAFrameRateRange)preferredFrameRateRange { return _range; }
- (void)setPreferredFrameRateRange:(CAFrameRateRange)r { _range = r; }

- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode
{
    if (_invalid)
        return;
    if (!_timer) {
        _timer = [[NSTimer timerWithTimeInterval:[self duration] target:_tick selector:@selector(tick:) userInfo:nil
                                         repeats:YES] retain];
        [self retain];    /* the run loop keeps the link until it is invalidated */
    }
    [runloop addTimer:_timer forMode:mode];
}
- (void)removeFromRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode { [self invalidate]; }
- (void)invalidate
{
    if (_invalid)
        return;
    _invalid = YES;
    BOOL had = _timer != nil;
    [_timer invalidate];
    [_timer release];
    _timer = nil;
    id target = _target;
    _target = nil;
    [target autorelease];
    if (had)
        [self autorelease];
}
- (void)_tick
{
    if (_paused || _invalid)
        return;
    _timestamp = CACurrentMediaTime();
    [self retain];
    ((void (*)(id, SEL, id))objc_msgSend)(_target, _sel, self);
    [self release];
}
@end
