/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CAAnimationGroup, animations run together. As
 * Apple's documentation describes, the group's animations are timed in the
 * group's own time (a begin time of 0 is the group's start), are cut off
 * at the group's duration, and their own delegates and removedOnCompletion
 * are not used. They are applied in order, each over the values the ones
 * before it left. */
#import "QInternal.h"

@implementation CAAnimationGroup {
    NSArray *_animations;
}

- (void)dealloc
{
    [_animations release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    CAAnimationGroup *c = [super copyWithZone:zone];
    c->_animations = [_animations copy];
    return c;
}

- (NSArray *)animations { return _animations; }
- (void)setAnimations:(NSArray *)animations
{
    NSArray *c = [animations copy];
    [_animations release];
    _animations = c;
}

- (void)_ferryApplyAtTime:(double)parentTime to:(NSMutableDictionary *)values layer:(CALayer *)layer
{
    struct qtime q;
    QTimingEvaluate(self, parentTime, [self _ferryDefaultDuration], &q);
    if (!q.applies)
        return;
    double dur = [self duration] > 0 ? [self duration] : [self _ferryDefaultDuration];
    double t = QTimingSolve([self timingFunction], q.progress) * dur;
    for (CAAnimation *a in _animations)
        [a _ferryApplyAtTime:t to:values layer:layer];
}
@end
