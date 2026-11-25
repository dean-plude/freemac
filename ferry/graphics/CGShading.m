/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Graphics functions and shadings (freemac 1.221, Ferry 0.45.0),
 * written from Apple's documentation of CGFunction and CGShading. A
 * shading's colours come from the program's function: Ferry asks it at 256
 * points across its domain and draws a gradient through the answers, axial
 * or radial, extended past either end as the shading says. Sequel Pro's tab
 * bar draws its tabs this way. */
#import "GInternal.h"

#define SAMPLES 256

@interface GFunction : NSObject {
@public
    void *info;
    size_t domainDim, rangeDim;
    CGFloat domain[2];
    CGFloat *range;
    CGFunctionCallbacks callbacks;
}
@end
@implementation GFunction
- (void)dealloc
{
    if (callbacks.releaseInfo)
        callbacks.releaseInfo(info);
    free(range);
    [super dealloc];
}
@end

CGFunctionRef CGFunctionCreate(void *info, size_t domainDimension, const CGFloat *domain, size_t rangeDimension,
                               const CGFloat *range, const CGFunctionCallbacks *callbacks)
{
    if (!callbacks || !callbacks->evaluate || domainDimension < 1 || rangeDimension < 1)
        return NULL;
    GFunction *f = [[GFunction alloc] init];
    f->info = info;
    f->domainDim = domainDimension;
    f->rangeDim = rangeDimension;
    f->domain[0] = domain ? domain[0] : 0;
    f->domain[1] = domain ? domain[1] : 1;
    if (range) {
        f->range = malloc(2 * rangeDimension * sizeof *f->range);
        memcpy(f->range, range, 2 * rangeDimension * sizeof *f->range);
    }
    f->callbacks = *callbacks;
    return (CGFunctionRef)f;
}
CGFunctionRef CGFunctionRetain(CGFunctionRef f) { return (CGFunctionRef)[OBJ(f) retain]; }
void CGFunctionRelease(CGFunctionRef f) { [OBJ(f) release]; }

@interface GShading : NSObject {
@public
    BOOL radial;
    CGPoint start, end;
    CGFloat startRadius, endRadius;
    bool extendStart, extendEnd;
    CGGradientRef gradient;
}
@end
@implementation GShading
- (void)dealloc
{
    CGGradientRelease(gradient);
    [super dealloc];
}
@end

/* The function's colours at SAMPLES points from the start of its domain to
 * the end, each clamped to its range, as a gradient in the shading's space;
 * a function that gives no alpha is opaque. */
static CGGradientRef sample(CGColorSpaceRef space, GFunction *f)
{
    size_t n = CGColorSpaceGetNumberOfComponents(space);
    if (!n)
        return NULL;
    CGFloat *components = calloc(SAMPLES * (n + 1), sizeof *components);
    CGFloat *in = calloc(f->domainDim, sizeof *in);
    CGFloat *out = calloc(f->rangeDim > n + 1 ? f->rangeDim : n + 1, sizeof *out);
    CGFloat locations[SAMPLES];
    for (int i = 0; i < SAMPLES; i++) {
        CGFloat t = (CGFloat)i / (SAMPLES - 1);
        in[0] = f->domain[0] + t * (f->domain[1] - f->domain[0]);
        for (size_t k = 0; k <= n; k++)
            out[k] = k == n ? 1 : 0;
        f->callbacks.evaluate(f->info, in, out);
        for (size_t k = 0; k <= n; k++) {
            CGFloat v = out[k];
            if (f->range && k < f->rangeDim)
                v = fmin(fmax(v, f->range[2 * k]), f->range[2 * k + 1]);
            components[i * (n + 1) + k] = fmin(fmax(v, 0), 1);
        }
        locations[i] = t;
    }
    CGGradientRef g = CGGradientCreateWithColorComponents(space, components, locations, SAMPLES);
    free(components);
    free(in);
    free(out);
    return g;
}

static CGShadingRef make_shading(CGColorSpaceRef space, CGFunctionRef function, BOOL radial, CGPoint start,
                                 CGFloat r0, CGPoint end, CGFloat r1, bool extendStart, bool extendEnd)
{
    if (!space || !function)
        return NULL;
    CGGradientRef g = sample(space, (GFunction *)function);
    if (!g)
        return NULL;
    GShading *s = [[GShading alloc] init];
    s->radial = radial;
    s->start = start;
    s->end = end;
    s->startRadius = r0;
    s->endRadius = r1;
    s->extendStart = extendStart;
    s->extendEnd = extendEnd;
    s->gradient = g;
    return (CGShadingRef)s;
}

CGShadingRef CGShadingCreateAxial(CGColorSpaceRef space, CGPoint start, CGPoint end, CGFunctionRef function,
                                  bool extendStart, bool extendEnd)
{
    return make_shading(space, function, NO, start, 0, end, 0, extendStart, extendEnd);
}
CGShadingRef CGShadingCreateRadial(CGColorSpaceRef space, CGPoint start, CGFloat startRadius, CGPoint end,
                                   CGFloat endRadius, CGFunctionRef function, bool extendStart, bool extendEnd)
{
    return make_shading(space, function, YES, start, startRadius, end, endRadius, extendStart, extendEnd);
}
CGShadingRef CGShadingRetain(CGShadingRef s) { return (CGShadingRef)[OBJ(s) retain]; }
void CGShadingRelease(CGShadingRef s) { [OBJ(s) release]; }

/* fills the clip with the shading */
void CGContextDrawShading(CGContextRef c, CGShadingRef shading)
{
    GShading *s = (GShading *)shading;
    if (!c || !s)
        return;
    CGGradientDrawingOptions options = (s->extendStart ? kCGGradientDrawsBeforeStartLocation : 0) |
                                       (s->extendEnd ? kCGGradientDrawsAfterEndLocation : 0);
    if (s->radial)
        CGContextDrawRadialGradient(c, s->gradient, s->start, s->startRadius, s->end, s->endRadius, options);
    else
        CGContextDrawLinearGradient(c, s->gradient, s->start, s->end, options);
}
