/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CAPropertyAnimation, an animation of one key
 * path. Its kinds give a value for each moment (CABasicAnimation,
 * CAKeyframeAnimation, CASpringAnimation); this applies it: through the
 * value function if there is one, added to the value beneath when the
 * animation is additive, and stepped on by each repeat when cumulative. */
#import "QInternal.h"

@interface CAPropertyAnimation (FerryKinds)
/* The value at progress p (after the timing function), time t into the
 * cycle, given the value beneath and the model's; and the change one whole
 * cycle makes, for cumulative animations. */
- (id)_ferryValueAt:(double)p time:(double)t beneath:(id)beneath model:(id)model;
- (id)_ferryCycleChangeBeneath:(id)beneath model:(id)model;
@end

/* What a value function makes of a number (or of numbers, for the
 * three-axis ones). */
static id through_function(CAValueFunction *f, id v)
{
    if (!f || !v)
        return v;
    NSString *n = [f name];
    double x = [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0;
    double a[3] = {x, x, x};
    if ([v isKindOfClass:[NSArray class]])
        for (NSUInteger i = 0; i < 3 && i < [v count]; i++)
            a[i] = [v[i] doubleValue];
    CATransform3D t = CATransform3DIdentity;
    if ([n isEqualToString:kCAValueFunctionRotateX])
        t = CATransform3DMakeRotation(x, 1, 0, 0);
    else if ([n isEqualToString:kCAValueFunctionRotateY])
        t = CATransform3DMakeRotation(x, 0, 1, 0);
    else if ([n isEqualToString:kCAValueFunctionRotateZ])
        t = CATransform3DMakeRotation(x, 0, 0, 1);
    else if ([n isEqualToString:kCAValueFunctionScale])
        t = CATransform3DMakeScale(a[0], a[1], a[2]);
    else if ([n isEqualToString:kCAValueFunctionScaleX])
        t = CATransform3DMakeScale(x, 1, 1);
    else if ([n isEqualToString:kCAValueFunctionScaleY])
        t = CATransform3DMakeScale(1, x, 1);
    else if ([n isEqualToString:kCAValueFunctionScaleZ])
        t = CATransform3DMakeScale(1, 1, x);
    else if ([n isEqualToString:kCAValueFunctionTranslate])
        t = CATransform3DMakeTranslation(a[0], a[1], a[2]);
    else if ([n isEqualToString:kCAValueFunctionTranslateX])
        t = CATransform3DMakeTranslation(x, 0, 0);
    else if ([n isEqualToString:kCAValueFunctionTranslateY])
        t = CATransform3DMakeTranslation(0, x, 0);
    else if ([n isEqualToString:kCAValueFunctionTranslateZ])
        t = CATransform3DMakeTranslation(0, 0, x);
    return [NSValue valueWithCATransform3D:t];
}

@implementation CAPropertyAnimation {
    NSString *_keyPath;
    BOOL _additive, _cumulative;
    CAValueFunction *_valueFunction;
}

+ (instancetype)animationWithKeyPath:(NSString *)path
{
    CAPropertyAnimation *a = [self animation];
    [a setKeyPath:path];
    return a;
}

- (void)dealloc
{
    [_keyPath release];
    [_valueFunction release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    CAPropertyAnimation *c = [super copyWithZone:zone];
    c->_keyPath = [_keyPath copy];
    c->_additive = _additive, c->_cumulative = _cumulative;
    c->_valueFunction = [_valueFunction retain];
    return c;
}

- (NSString *)keyPath { return _keyPath; }
- (void)setKeyPath:(NSString *)path
{
    id wasKeyPath = _keyPath;
    _keyPath = [path copy];
    [wasKeyPath release];
}
- (BOOL)isAdditive { return _additive; }
- (void)setAdditive:(BOOL)flag { _additive = flag; }
- (BOOL)isCumulative { return _cumulative; }
- (void)setCumulative:(BOOL)flag { _cumulative = flag; }
- (CAValueFunction *)valueFunction { return _valueFunction; }
- (void)setValueFunction:(CAValueFunction *)f
{
    [f retain];
    [_valueFunction release];
    _valueFunction = f;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; keyPath = %@>", [self class], self, _keyPath];
}

- (id)_ferryValueAt:(double)p time:(double)t beneath:(id)beneath model:(id)model { return nil; }
- (id)_ferryCycleChangeBeneath:(id)beneath model:(id)model { return nil; }

- (void)_ferryApplyAtTime:(double)parentTime to:(NSMutableDictionary *)values layer:(CALayer *)layer
{
    if (!_keyPath)
        return;
    struct qtime q;
    QTimingEvaluate(self, parentTime, [self _ferryDefaultDuration], &q);
    if (!q.applies)
        return;
    double dur = [self duration] > 0 ? [self duration] : [self _ferryDefaultDuration];
    double p = QTimingSolve([self timingFunction], q.progress);
    id beneath = QValueAtKeyPath(values, _keyPath, layer);
    id model = QValueAtKeyPath([layer _ferryValues], _keyPath, layer);
    id value = [self _ferryValueAt:p time:q.progress * dur beneath:beneath model:model];
    if (!value)
        return;
    if (_cumulative && q.iteration >= 1) {
        id step = [self _ferryCycleChangeBeneath:beneath model:model];
        for (int i = 0; step && i < (int)fmin(q.iteration, 10000); i++)
            value = QAdd(value, step);
    }
    value = through_function(_valueFunction, value);
    if (_additive)
        value = QAdd(beneath, value);
    QSetValueAtKeyPath(values, _keyPath, value, layer);
}
@end
