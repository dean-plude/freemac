/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CASpringAnimation, a basic animation whose
 * progress follows a mass on a damped spring let go at the start value,
 * with the mass, stiffness, damping and initial velocity Apple's
 * documentation describes (defaults 1, 100, 10 and 0). The time is real
 * time into the animation; the timing function isn't used. */
#import "QInternal.h"

@interface CABasicAnimation (FerrySpring)
- (id)_ferryValueAt:(double)p time:(double)t beneath:(id)beneath model:(id)model;
@end

@implementation CASpringAnimation {
    CGFloat _mass, _stiffness, _damping, _initialVelocity;
}

- (instancetype)init
{
    if ((self = [super init]))
        _mass = 1, _stiffness = 100, _damping = 10, _initialVelocity = 0;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    CASpringAnimation *c = [super copyWithZone:zone];
    c->_mass = _mass, c->_stiffness = _stiffness, c->_damping = _damping, c->_initialVelocity = _initialVelocity;
    return c;
}

- (CGFloat)mass { return _mass; }
- (void)setMass:(CGFloat)m { _mass = m > 0 ? m : 1; }
- (CGFloat)stiffness { return _stiffness; }
- (void)setStiffness:(CGFloat)k { _stiffness = k > 0 ? k : 100; }
- (CGFloat)damping { return _damping; }
- (void)setDamping:(CGFloat)c { _damping = c >= 0 ? c : 10; }
- (CGFloat)initialVelocity { return _initialVelocity; }
- (void)setInitialVelocity:(CGFloat)v { _initialVelocity = v; }

/* How far the mass is from the end, as a fraction of the whole distance
 * (-1 at the start), t seconds in. */
static double offset_at(CASpringAnimation *s, double t)
{
    double w0 = sqrt(s->_stiffness / s->_mass);
    double zeta = s->_damping / (2 * sqrt(s->_stiffness * s->_mass));
    double v0 = s->_initialVelocity;
    if (zeta < 1) {
        double wd = w0 * sqrt(1 - zeta * zeta);
        double a = -1, b = (v0 + zeta * w0 * a) / wd;
        return exp(-zeta * w0 * t) * (a * cos(wd * t) + b * sin(wd * t));
    }
    if (zeta == 1) {
        double a = -1, b = v0 + w0 * a;
        return exp(-w0 * t) * (a + b * t);
    }
    double r = sqrt(zeta * zeta - 1);
    double r1 = -w0 * (zeta - r), r2 = -w0 * (zeta + r);
    double c2 = (v0 + r1) / (r2 - r1), c1 = -1 - c2;
    return c1 * exp(r1 * t) + c2 * exp(r2 * t);
}

/* When the mass has come to rest: within a thousandth of the distance from
 * then on, looked at in sixtieths of a second. */
- (CFTimeInterval)settlingDuration
{
    double last = 0;
    for (double t = 0; t < 60; t += 1.0 / 60)
        if (fabs(offset_at(self, t)) > 0.001)
            last = t;
    return ceil((last + 1.0 / 60) * 1000) / 1000;
}

- (double)_ferryDefaultDuration { return [self settlingDuration]; }

- (id)_ferryValueAt:(double)p time:(double)t beneath:(id)beneath model:(id)model
{
    return [super _ferryValueAt:1 + offset_at(self, t) time:t beneath:beneath model:model];
}
@end
