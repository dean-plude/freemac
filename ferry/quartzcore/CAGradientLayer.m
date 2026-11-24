/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CAGradientLayer, a gradient over the layer's
 * bounds. As Apple's documentation describes: colors are CGColors, at
 * locations from 0 to 1 (evenly spaced when none are given); startPoint
 * and endPoint are in the unit square of the bounds, (0.5, 0) and (0.5, 1)
 * by default; an axial gradient runs from one to the other and goes on
 * past both as their colours, and a radial one is centred on the start
 * point and reaches the end point on an ellipse. Conic gradients are drawn
 * as axial ones. */
#import "QInternal.h"

CAGradientLayerType const kCAGradientLayerAxial = @"axial";
CAGradientLayerType const kCAGradientLayerRadial = @"radial";
CAGradientLayerType const kCAGradientLayerConic = @"conic";

@implementation CAGradientLayer
@dynamic colors, locations, startPoint, endPoint, type;

+ (NSSet *)_ferryKnownKeys
{
    static NSSet *keys;
    if (!keys)
        keys = [[[super _ferryKnownKeys]
            setByAddingObjectsFromArray:@[ @"colors", @"locations", @"startPoint", @"endPoint", @"type" ]] retain];
    return keys;
}

+ (NSSet *)_ferryAnimatableKeys
{
    static NSSet *keys;
    if (!keys)
        keys = [[[super _ferryAnimatableKeys]
            setByAddingObjectsFromArray:@[ @"colors", @"locations", @"startPoint", @"endPoint" ]] retain];
    return keys;
}

+ (id)defaultValueForKey:(NSString *)key
{
    static NSDictionary *defaults;
    if (!defaults)
        defaults = [@{
            @"startPoint" : [NSValue valueWithPoint:CGPointMake(0.5, 0)],
            @"endPoint" : [NSValue valueWithPoint:CGPointMake(0.5, 1)],
            @"type" : kCAGradientLayerAxial,
        } retain];
    return defaults[key] ?: [super defaultValueForKey:key];
}

- (void)_ferryDrawContentWithValues:(NSDictionary *)v inContext:(CGContextRef)ctx flipped:(BOOL)flipped
{
    NSMutableArray *colors = [NSMutableArray array];
    for (id c in v[@"colors"])
        if (QIsColor(c))
            [colors addObject:c];
    if (![colors count])
        return;
    CGRect b = QRect(v, @"bounds");
    CGContextClipToRect(ctx, b);
    if ([colors count] == 1) {
        CGContextSetFillColorWithColor(ctx, (CGColorRef)colors[0]);
        CGContextFillRect(ctx, b);
        return;
    }
    NSArray *locs = v[@"locations"];
    CGFloat *at = NULL;
    if ([locs count] == [colors count]) {
        at = calloc([colors count], sizeof *at);
        for (NSUInteger i = 0; i < [colors count]; i++)
            at[i] = [locs[i] doubleValue];
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColors(cs, (CFArrayRef)colors, at);
    CGColorSpaceRelease(cs);
    free(at);
    if (!g)
        return;
    CGPoint s = QPoint(v, @"startPoint"), e = QPoint(v, @"endPoint");
    CGPoint ps = CGPointMake(b.origin.x + s.x * b.size.width, b.origin.y + s.y * b.size.height);
    CGPoint pe = CGPointMake(b.origin.x + e.x * b.size.width, b.origin.y + e.y * b.size.height);
    CGGradientDrawingOptions both = kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation;
    NSString *type = v[@"type"];
    if ([type isEqual:kCAGradientLayerRadial]) {
        double rx = fabs(pe.x - ps.x), ry = fabs(pe.y - ps.y);
        if (rx <= 0 || ry <= 0)
            rx = ry = fmax(rx, ry);
        if (rx > 0) {
            CGContextTranslateCTM(ctx, ps.x, ps.y);
            CGContextScaleCTM(ctx, 1, ry / rx);
            CGContextDrawRadialGradient(ctx, g, CGPointZero, 0, CGPointZero, rx, kCGGradientDrawsAfterEndLocation);
        }
    } else {
        if ([type isEqual:kCAGradientLayerConic])
            QWarnOnce("conic gradients (drawn as axial ones)");
        CGContextDrawLinearGradient(ctx, g, ps, pe, both);
    }
    CGGradientRelease(g);
}
@end
