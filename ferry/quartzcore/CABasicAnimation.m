/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CABasicAnimation, from one value to another.
 * Which two follows Apple's documentation of fromValue, toValue and
 * byValue: both ends given; one end and a step; or one end only, the
 * other being the value beneath (for toValue or byValue alone) or the
 * model's value (for fromValue alone, which is what implicit animations
 * are). */
#import "QInternal.h"

@interface CAPropertyAnimation (FerryKinds)
- (id)_ferryValueAt:(double)p time:(double)t beneath:(id)beneath model:(id)model;
- (id)_ferryCycleChangeBeneath:(id)beneath model:(id)model;
@end

@implementation CABasicAnimation {
    id _fromValue, _toValue, _byValue;
}

- (void)dealloc
{
    [_fromValue release];
    [_toValue release];
    [_byValue release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    CABasicAnimation *c = [super copyWithZone:zone];
    c->_fromValue = [_fromValue retain];
    c->_toValue = [_toValue retain];
    c->_byValue = [_byValue retain];
    return c;
}

- (id)fromValue { return _fromValue; }
- (void)setFromValue:(id)v
{
    [v retain];
    [_fromValue release];
    _fromValue = v;
}
- (id)toValue { return _toValue; }
- (void)setToValue:(id)v
{
    [v retain];
    [_toValue release];
    _toValue = v;
}
- (id)byValue { return _byValue; }
- (void)setByValue:(id)v
{
    [v retain];
    [_byValue release];
    _byValue = v;
}

/* the two ends */
- (void)_ferryFrom:(id *)from to:(id *)to beneath:(id)beneath model:(id)model
{
    id f = _fromValue, t = _toValue, b = _byValue;
    /* for an additive animation the ends are offsets, and none means none */
    id base = [self isAdditive] ? nil : beneath;
    if (f && t) {
    } else if (f && b) {
        t = QAdd(f, b);
    } else if (b && t) {
        f = QSubtract(t, b);
    } else if (f) {
        t = [self isAdditive] ? nil : model;
    } else if (t) {
        f = base;
    } else if (b) {
        f = base, t = QAdd(base, b);
    } else {
        f = base, t = [self isAdditive] ? nil : model;
    }
    *from = f, *to = t;
}

- (id)_ferryValueAt:(double)p time:(double)time beneath:(id)beneath model:(id)model
{
    id f, t;
    [self _ferryFrom:&f to:&t beneath:beneath model:model];
    if (!f && !t)
        return nil;
    return QBlend(f, t, p);
}

- (id)_ferryCycleChangeBeneath:(id)beneath model:(id)model
{
    id f, t;
    [self _ferryFrom:&f to:&t beneath:beneath model:model];
    return f && t ? QSubtract(t, f) : nil;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; keyPath = %@; fromValue = %@; toValue = %@>", [self class], self,
                                      [self keyPath], _fromValue, _toValue];
}
@end
