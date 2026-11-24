/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CATransition. The properties are kept and the
 * animation is timed (its delegate is told when it starts and stops), but
 * the layer is drawn as it will look afterwards from the start: Ferry
 * doesn't draw the fade, push, move-in or reveal yet. */
#import "QInternal.h"

CATransitionType const kCATransitionFade = @"fade";
CATransitionType const kCATransitionMoveIn = @"moveIn";
CATransitionType const kCATransitionPush = @"push";
CATransitionType const kCATransitionReveal = @"reveal";
CATransitionSubtype const kCATransitionFromRight = @"fromRight";
CATransitionSubtype const kCATransitionFromLeft = @"fromLeft";
CATransitionSubtype const kCATransitionFromTop = @"fromTop";
CATransitionSubtype const kCATransitionFromBottom = @"fromBottom";

@implementation CATransition {
    NSString *_type, *_subtype;
    float _startProgress, _endProgress;
    id _filter;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _type = [kCATransitionFade copy];
        _endProgress = 1;
    }
    return self;
}

- (void)dealloc
{
    [_type release];
    [_subtype release];
    [_filter release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    CATransition *c = [super copyWithZone:zone];
    [c->_type release];
    c->_type = [_type copy];
    c->_subtype = [_subtype copy];
    c->_startProgress = _startProgress, c->_endProgress = _endProgress;
    c->_filter = [_filter retain];
    return c;
}

- (NSString *)type { return _type; }
- (void)setType:(NSString *)type
{
    [_type release];
    _type = [type copy];
}
- (NSString *)subtype { return _subtype; }
- (void)setSubtype:(NSString *)subtype
{
    [_subtype release];
    _subtype = [subtype copy];
}
- (float)startProgress { return _startProgress; }
- (void)setStartProgress:(float)p { _startProgress = fmax(0, fmin(1, p)); }
- (float)endProgress { return _endProgress; }
- (void)setEndProgress:(float)p { _endProgress = fmax(0, fmin(1, p)); }
- (id)filter { return _filter; }
- (void)setFilter:(id)filter
{
    [filter retain];
    [_filter release];
    _filter = filter;
}

- (void)_ferryApplyAtTime:(double)parentTime to:(NSMutableDictionary *)values layer:(CALayer *)layer
{
    QWarnOnce("drawing transitions (CATransition)");
}
@end
