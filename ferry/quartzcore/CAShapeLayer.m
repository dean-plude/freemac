/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CAShapeLayer, a path filled and stroked in the
 * layer's bounds space, over its contents and under its sublayers, with
 * the defaults Apple's documentation gives (a black fill, no stroke, a
 * line width of 1, a miter limit of 10). strokeStart and strokeEnd stroke
 * only the part of the path between those fractions of its length. */
#import "QInternal.h"

CAShapeLayerFillRule const kCAFillRuleNonZero = @"non-zero";
CAShapeLayerFillRule const kCAFillRuleEvenOdd = @"even-odd";
CAShapeLayerLineJoin const kCALineJoinMiter = @"miter";
CAShapeLayerLineJoin const kCALineJoinRound = @"round";
CAShapeLayerLineJoin const kCALineJoinBevel = @"bevel";
CAShapeLayerLineCap const kCALineCapButt = @"butt";
CAShapeLayerLineCap const kCALineCapRound = @"round";
CAShapeLayerLineCap const kCALineCapSquare = @"square";

/* ---- pieces of a path, by length ------------------------------------------------- */

/* The path as runs of straight segments (curves cut into 16), each run a
 * subpath. */
struct run {
    CGPoint *pts;
    size_t n, cap;
};
struct runs {
    struct run *r;
    size_t n, cap;
    CGPoint start, current;
};

static void run_add(struct runs *z, CGPoint p)
{
    if (!z->n) {
        z->r = calloc(4, sizeof *z->r);
        z->cap = 4;
        z->n = 1;
    }
    struct run *r = &z->r[z->n - 1];
    if (r->n == r->cap) {
        r->cap = r->cap ? r->cap * 2 : 16;
        r->pts = realloc(r->pts, r->cap * sizeof *r->pts);
    }
    r->pts[r->n++] = p;
    z->current = p;
}

static void run_new(struct runs *z, CGPoint p)
{
    if (z->n == z->cap) {
        z->cap = z->cap ? z->cap * 2 : 4;
        z->r = realloc(z->r, z->cap * sizeof *z->r);
    }
    z->r[z->n++] = (struct run){0};
    z->start = p;
    run_add(z, p);
}

static void flatten(void *info, const CGPathElement *e)
{
    struct runs *z = info;
    CGPoint a = z->current;
    switch (e->type) {
    case kCGPathElementMoveToPoint: run_new(z, e->points[0]); break;
    case kCGPathElementAddLineToPoint:
        if (!z->n)
            run_new(z, a);
        run_add(z, e->points[0]);
        break;
    case kCGPathElementAddQuadCurveToPoint:
        if (!z->n)
            run_new(z, a);
        for (int i = 1; i <= 16; i++) {
            double t = i / 16.0, u = 1 - t;
            run_add(z, CGPointMake(u * u * a.x + 2 * u * t * e->points[0].x + t * t * e->points[1].x,
                                   u * u * a.y + 2 * u * t * e->points[0].y + t * t * e->points[1].y));
        }
        break;
    case kCGPathElementAddCurveToPoint:
        if (!z->n)
            run_new(z, a);
        for (int i = 1; i <= 16; i++) {
            double t = i / 16.0, u = 1 - t;
            run_add(z, CGPointMake(u * u * u * a.x + 3 * u * u * t * e->points[0].x + 3 * u * t * t * e->points[1].x +
                                       t * t * t * e->points[2].x,
                                   u * u * u * a.y + 3 * u * u * t * e->points[0].y + 3 * u * t * t * e->points[1].y +
                                       t * t * t * e->points[2].y));
        }
        break;
    case kCGPathElementCloseSubpath:
        if (z->n)
            run_add(z, z->start);
        z->current = z->start;
        break;
    }
}

CGPathRef QPathPiece(CGPathRef path, double start, double end)
{
    if (!path)
        return NULL;
    start = fmax(0, fmin(1, start)), end = fmax(0, fmin(1, end));
    if (start <= 0 && end >= 1)
        return CGPathRetain(path);
    CGMutablePathRef out = CGPathCreateMutable();
    if (end <= start)
        return out;
    struct runs z = {0};
    CGPathApply(path, &z, flatten);
    double total = 0;
    for (size_t i = 0; i < z.n; i++)
        for (size_t j = 1; j < z.r[i].n; j++)
            total += hypot(z.r[i].pts[j].x - z.r[i].pts[j - 1].x, z.r[i].pts[j].y - z.r[i].pts[j - 1].y);
    double from = start * total, to = end * total, at = 0;
    for (size_t i = 0; i < z.n; i++) {
        BOOL drawing = NO;
        for (size_t j = 1; j < z.r[i].n; j++) {
            CGPoint a = z.r[i].pts[j - 1], b = z.r[i].pts[j];
            double len = hypot(b.x - a.x, b.y - a.y), next = at + len;
            if (next > from && at < to && len > 0) {
                double t0 = fmax(0, (from - at) / len), t1 = fmin(1, (to - at) / len);
                CGPoint p0 = CGPointMake(a.x + (b.x - a.x) * t0, a.y + (b.y - a.y) * t0);
                CGPoint p1 = CGPointMake(a.x + (b.x - a.x) * t1, a.y + (b.y - a.y) * t1);
                if (!drawing)
                    CGPathMoveToPoint(out, NULL, p0.x, p0.y);
                CGPathAddLineToPoint(out, NULL, p1.x, p1.y);
                drawing = t1 >= 1;
            } else {
                drawing = NO;
            }
            at = next;
        }
        free(z.r[i].pts);
    }
    free(z.r);
    return out;
}

/* ---- the layer --------------------------------------------------------------------- */

@implementation CAShapeLayer
@dynamic path, fillColor, fillRule, strokeColor, strokeStart, strokeEnd, lineWidth, miterLimit, lineCap, lineJoin,
    lineDashPhase, lineDashPattern;

+ (NSSet *)_ferryKnownKeys
{
    static NSSet *keys;
    if (!keys)
        keys = [[[super _ferryKnownKeys] setByAddingObjectsFromArray:@[
            @"path", @"fillColor", @"fillRule", @"strokeColor", @"strokeStart", @"strokeEnd", @"lineWidth",
            @"miterLimit", @"lineCap", @"lineJoin", @"lineDashPhase", @"lineDashPattern"
        ]] retain];
    return keys;
}

+ (NSSet *)_ferryAnimatableKeys
{
    static NSSet *keys;
    if (!keys)
        keys = [[[super _ferryAnimatableKeys] setByAddingObjectsFromArray:@[
            @"path", @"fillColor", @"strokeColor", @"strokeStart", @"strokeEnd", @"lineWidth", @"miterLimit",
            @"lineDashPhase", @"lineDashPattern"
        ]] retain];
    return keys;
}

+ (id)defaultValueForKey:(NSString *)key
{
    static NSDictionary *defaults;
    if (!defaults) {
        CGColorRef black = CGColorCreateSRGB(0, 0, 0, 1);
        defaults = [@{
            @"fillColor" : (id)black,
            @"fillRule" : kCAFillRuleNonZero,
            @"strokeStart" : @0.0,
            @"strokeEnd" : @1.0,
            @"lineWidth" : @1.0,
            @"miterLimit" : @10.0,
            @"lineCap" : kCALineCapButt,
            @"lineJoin" : kCALineJoinMiter,
            @"lineDashPhase" : @0.0,
        } retain];
        CGColorRelease(black);
    }
    return defaults[key] ?: [super defaultValueForKey:key];
}

- (void)_ferryDrawContentWithValues:(NSDictionary *)v inContext:(CGContextRef)ctx flipped:(BOOL)flipped
{
    id path = v[@"path"];
    if (!QIsPath(path))
        return;
    CGPathRef p = (CGPathRef)path;
    CGColorRef fill = QColor(v, @"fillColor");
    if (fill && CGColorGetAlpha(fill) > 0) {
        CGContextSetFillColorWithColor(ctx, fill);
        CGContextBeginPath(ctx);
        CGContextAddPath(ctx, p);
        if ([v[@"fillRule"] isEqual:kCAFillRuleEvenOdd])
            CGContextEOFillPath(ctx);
        else
            CGContextFillPath(ctx);
    }
    CGColorRef stroke = QColor(v, @"strokeColor");
    double width = QNum(v, @"lineWidth");
    if (!stroke || CGColorGetAlpha(stroke) <= 0 || width <= 0)
        return;
    CGPathRef piece = QPathPiece(p, QNum(v, @"strokeStart"), QNum(v, @"strokeEnd"));
    if (!piece)
        return;
    CGContextSetStrokeColorWithColor(ctx, stroke);
    CGContextSetLineWidth(ctx, width);
    CGContextSetMiterLimit(ctx, QNum(v, @"miterLimit"));
    NSString *cap = v[@"lineCap"], *join = v[@"lineJoin"];
    CGContextSetLineCap(ctx, [cap isEqual:kCALineCapRound]    ? kCGLineCapRound
                             : [cap isEqual:kCALineCapSquare] ? kCGLineCapSquare
                                                              : kCGLineCapButt);
    CGContextSetLineJoin(ctx, [join isEqual:kCALineJoinRound]    ? kCGLineJoinRound
                              : [join isEqual:kCALineJoinBevel] ? kCGLineJoinBevel
                                                                : kCGLineJoinMiter);
    NSArray *dashes = v[@"lineDashPattern"];
    if ([dashes count]) {
        CGFloat *d = calloc([dashes count], sizeof *d);
        for (NSUInteger i = 0; i < [dashes count]; i++)
            d[i] = [dashes[i] doubleValue];
        CGContextSetLineDash(ctx, QNum(v, @"lineDashPhase"), d, [dashes count]);
        free(d);
    }
    CGContextBeginPath(ctx);
    CGContextAddPath(ctx, piece);
    CGContextStrokePath(ctx);
    CGPathRelease(piece);
}
@end
