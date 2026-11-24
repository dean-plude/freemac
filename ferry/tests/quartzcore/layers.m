/* Ferry test: Core Animation layers. Geometry, key-value coding, the tree,
 * and layer trees drawn with renderInContext: into bitmap contexts, checked
 * pixel by pixel away from antialiased edges. */
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define W 64
#define H 64

static const char *yes(BOOL b) { return b ? "yes" : "no"; }

static CGColorRef rgb(double r, double g, double b, double a)
{
    static NSMutableArray *keep;
    if (!keep)
        keep = [NSMutableArray new];
    CGColorRef c = CGColorCreateSRGB(r, g, b, a);
    [keep addObject:(__bridge id)c];
    CGColorRelease(c);
    return c;
}

static CGContextRef canvas(void)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    return c;
}

/* the pixel at (x, y), y counting up from the bottom */
static const unsigned char *pixel(CGContextRef c, int x, int y)
{
    const unsigned char *d = CGBitmapContextGetData(c);
    return d + (H - 1 - y) * CGBitmapContextGetBytesPerRow(c) + x * 4;
}

/* a colour's name, roughly */
static const char *name(CGContextRef c, int x, int y)
{
    const unsigned char *p = pixel(c, x, y);
    static char buf[32];
    struct { const char *n; int r, g, b; } known[] = {
        {"white", 255, 255, 255}, {"red", 255, 0, 0}, {"green", 0, 255, 0}, {"blue", 0, 0, 255},
        {"black", 0, 0, 0}, {"pink", 255, 128, 128}, {"yellow", 255, 255, 0},
    };
    for (size_t i = 0; i < sizeof known / sizeof *known; i++)
        if (abs(p[0] - known[i].r) <= 3 && abs(p[1] - known[i].g) <= 3 && abs(p[2] - known[i].b) <= 3)
            return known[i].n;
    snprintf(buf, sizeof buf, "%d,%d,%d", p[0], p[1], p[2]);
    return buf;
}

static CGContextRef draw(CALayer *layer)
{
    CGContextRef c = canvas();
    [layer renderInContext:c];
    return c;
}

static void rect(const char *what, CGRect r)
{
    printf("%s: %g %g %g %g\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}

/* a 2x2 image: red over green on the left, blue over yellow on the right
 * (its first row is its top) */
static CGImageRef quad_image(void)
{
    static const unsigned char px[] = {255, 0, 0, 255, 0, 0, 255, 255, 0, 255, 0, 255, 255, 255, 0, 255};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, px, sizeof px, NULL);
    CGImageRef img = CGImageCreate(2, 2, 8, 32, 8, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast, dp, NULL, false,
                                   kCGRenderingIntentDefault);
    CGDataProviderRelease(dp);
    CGColorSpaceRelease(cs);
    return img;
}

@interface Painter : NSObject <CALayerDelegate>
@property int draws;
@end
@implementation Painter
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx
{
    self.draws++;
    CGContextSetRGBFillColor(ctx, 0, 0, 1, 1);
    /* the bottom half, in the layer's y-up space */
    CGRect b = layer.bounds;
    CGContextFillRect(ctx, CGRectMake(b.origin.x, b.origin.y, b.size.width, b.size.height / 2));
}
@end

@interface Setter : NSObject <CALayerDelegate>
@end
@implementation Setter
- (void)displayLayer:(CALayer *)layer { layer.contents = (__bridge id)quad_image(); }
@end

/* a layer with a property of its own, kept by the layer */
@interface Dial : CALayer
@property CGFloat level;
@property (copy) NSString *label;
@end
@implementation Dial
@dynamic level, label;
+ (BOOL)needsDisplayForKey:(NSString *)key
{
    return [key isEqualToString:@"level"] || [super needsDisplayForKey:key];
}
+ (id)defaultValueForKey:(NSString *)key
{
    if ([key isEqualToString:@"level"])
        return @0.25;
    return [super defaultValueForKey:key];
}
- (void)drawInContext:(CGContextRef)ctx
{
    CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, self.bounds.size.width * self.level, self.bounds.size.height));
}
@end

int main(void)
{
    @autoreleasepool {
        /* ---- geometry ---- */
        CALayer *l = [CALayer layer];
        rect("new bounds", l.bounds);
        printf("anchor %g %g, opacity %g, hidden %s, scale %g, gravity %s\n", l.anchorPoint.x, l.anchorPoint.y,
               l.opacity, yes(l.hidden), l.contentsScale, [l.contentsGravity UTF8String]);
        printf("border colour alpha %g, background %s\n", CGColorGetAlpha(l.borderColor),
               l.backgroundColor ? "set" : "none");
        l.frame = CGRectMake(10, 20, 30, 40);
        rect("bounds", l.bounds);
        printf("position: %g %g\n", l.position.x, l.position.y);
        l.anchorPoint = CGPointMake(0, 0);
        rect("frame, anchor at the corner", l.frame);
        l.anchorPoint = CGPointMake(0.5, 0.5);
        l.transform = CATransform3DMakeScale(2, 2, 1);
        rect("frame, scaled twice", l.frame);
        l.transform = CATransform3DIdentity;
        l.affineTransform = CGAffineTransformMakeRotation(M_PI / 2);
        CGRect f = l.frame;
        printf("frame, turned: %.0f %.0f %.0f %.0f\n", f.origin.x, f.origin.y, f.size.width, f.size.height);
        printf("transform is affine: %s\n", yes(CATransform3DIsAffine(l.transform)));
        l.transform = CATransform3DIdentity;

        /* ---- key-value coding ---- */
        printf("position.x: %g\n", [[l valueForKeyPath:@"position.x"] doubleValue]);
        [l setValue:@50 forKeyPath:@"bounds.size.width"];
        rect("bounds after bounds.size.width", l.bounds);
        [l setValue:@0.5 forKey:@"opacity"];
        printf("opacity by key: %g\n", l.opacity);
        [l setValue:@"kept" forKey:@"myOwnKey"];
        printf("a key of its own: %s\n", [[l valueForKey:@"myOwnKey"] UTF8String]);
        printf("frame by key: %s\n", [[l valueForKey:@"frame"] isKindOfClass:[NSValue class]] ? "an NSValue" : "?");
        Dial *dial = [Dial layer];
        printf("dynamic property default: %g\n", dial.level);
        dial.level = 0.75;
        dial.label = @"volume";
        printf("dynamic properties: %g %s, by key %g\n", dial.level, [dial.label UTF8String],
               [[dial valueForKey:@"level"] doubleValue]);
        printf("needs display after the change: %s\n", yes([dial needsDisplay]));

        /* ---- the tree ---- */
        CALayer *root = [CALayer layer], *a = [CALayer layer], *b = [CALayer layer], *c = [CALayer layer];
        a.name = @"a", b.name = @"b", c.name = @"c";
        [root addSublayer:a];
        [root addSublayer:c];
        [root insertSublayer:b below:c];
        NSMutableString *order = [NSMutableString string];
        for (CALayer *s in root.sublayers)
            [order appendString:s.name];
        printf("order: %s, superlayer is root: %s\n", [order UTF8String], yes(b.superlayer == root));
        [b removeFromSuperlayer];
        [root replaceSublayer:a with:b];
        order = [NSMutableString string];
        for (CALayer *s in root.sublayers)
            [order appendString:s.name];
        printf("after replacing: %s, a has no superlayer: %s\n", [order UTF8String], yes(a.superlayer == nil));

        /* ---- converting and hit testing ---- */
        root = [CALayer layer];
        root.frame = CGRectMake(0, 0, 64, 64);
        CALayer *child = [CALayer layer];
        child.frame = CGRectMake(10, 20, 20, 20);
        [root addSublayer:child];
        CGPoint p = [child convertPoint:CGPointMake(5, 5) toLayer:root];
        printf("child (5,5) in root: %g %g\n", p.x, p.y);
        p = [root convertPoint:CGPointMake(15, 25) toLayer:child];
        printf("root (15,25) in child: %g %g\n", p.x, p.y);
        printf("hit at (15,25): %s, at (50,50): %s, outside: %s\n", [root hitTest:CGPointMake(15, 25)] == child ? "child" : "?",
               [root hitTest:CGPointMake(50, 50)] == root ? "root" : "?", [root hitTest:CGPointMake(70, 5)] ? "?" : "none");

        /* ---- drawing ---- */
        root = [CALayer layer];
        root.frame = CGRectMake(0, 0, W, H);
        CALayer *box = [CALayer layer];
        box.frame = CGRectMake(8, 8, 48, 48);
        box.backgroundColor = rgb(1, 0, 0, 1);
        [root addSublayer:box];
        CGContextRef ctx = draw(root);
        printf("background: inside %s, outside %s\n", name(ctx, 32, 32), name(ctx, 4, 4));
        CGContextRelease(ctx);

        box.borderWidth = 4;
        box.borderColor = rgb(0, 0, 1, 1);
        ctx = draw(root);
        printf("border: edge %s, inside %s\n", name(ctx, 10, 32), name(ctx, 32, 32));
        CGContextRelease(ctx);

        box.borderWidth = 0;
        box.cornerRadius = 16;
        ctx = draw(root);
        printf("rounded: corner %s, edge %s\n", name(ctx, 10, 10), name(ctx, 32, 10));
        CGContextRelease(ctx);
        box.maskedCorners = kCALayerMaxXMaxYCorner;
        ctx = draw(root);
        printf("one corner rounded: bottom left %s, top right %s\n", name(ctx, 10, 10), name(ctx, 53, 53));
        CGContextRelease(ctx);
        box.cornerRadius = 0;

        box.opacity = 0.5;
        ctx = draw(root);
        printf("half opacity: %s\n", name(ctx, 32, 32));
        CGContextRelease(ctx);
        /* a group: the sublayer over the layer is not seen through it */
        CALayer *over = [CALayer layer];
        over.frame = CGRectMake(0, 0, 24, 48);
        over.backgroundColor = rgb(0, 1, 0, 1);
        [box addSublayer:over];
        ctx = draw(root);
        printf("half opacity, as a group: %s and %s\n", name(ctx, 16, 32), name(ctx, 48, 32));
        CGContextRelease(ctx);
        box.opacity = 1;
        box.hidden = YES;
        ctx = draw(root);
        printf("hidden: %s %s\n", name(ctx, 16, 32), name(ctx, 48, 32));
        CGContextRelease(ctx);
        box.hidden = NO;

        /* sublayers outside their superlayer, cut off by masksToBounds */
        over.frame = CGRectMake(-8, 0, 16, 48);
        ctx = draw(root);
        printf("sticking out: %s\n", name(ctx, 4, 32));
        CGContextRelease(ctx);
        box.masksToBounds = YES;
        ctx = draw(root);
        printf("masked: %s, inside %s\n", name(ctx, 4, 32), name(ctx, 12, 32));
        CGContextRelease(ctx);
        box.masksToBounds = NO;
        [over removeFromSuperlayer];

        /* transforms, about the anchor point */
        box.frame = CGRectMake(0, 0, 32, 16);
        ctx = draw(root);
        printf("before turning: (8,24) %s, (24,8) %s\n", name(ctx, 8, 24), name(ctx, 24, 8));
        CGContextRelease(ctx);
        box.anchorPoint = CGPointMake(0, 0);
        box.position = CGPointMake(32, 16);
        box.transform = CATransform3DMakeRotation(M_PI / 2, 0, 0, 1);
        ctx = draw(root);
        printf("turned a quarter about its corner: (24,32) %s, (40,24) %s\n", name(ctx, 24, 32), name(ctx, 40, 24));
        CGContextRelease(ctx);
        box.transform = CATransform3DMakeTranslation(16, 16, 0);
        ctx = draw(root);
        printf("moved: (52,36) %s, (36,20) %s\n", name(ctx, 52, 36), name(ctx, 36, 20));
        CGContextRelease(ctx);
        box.transform = CATransform3DIdentity;
        box.anchorPoint = CGPointMake(0.5, 0.5);

        /* sublayerTransform and geometryFlipped */
        box.frame = CGRectMake(0, 0, 16, 16);
        root.sublayerTransform = CATransform3DMakeTranslation(0, 32, 0);
        ctx = draw(root);
        printf("sublayer transform: (8,40) %s, (8,8) %s\n", name(ctx, 8, 40), name(ctx, 8, 8));
        CGContextRelease(ctx);
        root.sublayerTransform = CATransform3DIdentity;
        root.geometryFlipped = YES;
        ctx = draw(root);
        printf("geometry flipped: top left %s, bottom left %s\n", name(ctx, 8, 56), name(ctx, 8, 8));
        printf("contents flipped: root %s, box %s\n", yes([root contentsAreFlipped]), yes([box contentsAreFlipped]));
        CGContextRelease(ctx);
        root.geometryFlipped = NO;

        /* zPosition draws above the order */
        CALayer *front = [CALayer layer], *back = [CALayer layer];
        front.frame = back.frame = CGRectMake(32, 32, 16, 16);
        front.backgroundColor = rgb(0, 1, 0, 1);
        back.backgroundColor = rgb(0, 0, 1, 1);
        [root addSublayer:front];
        [root addSublayer:back];
        ctx = draw(root);
        printf("in order: %s\n", name(ctx, 40, 40));
        CGContextRelease(ctx);
        front.zPosition = 1;
        ctx = draw(root);
        printf("with zPosition: %s\n", name(ctx, 40, 40));
        CGContextRelease(ctx);
        [front removeFromSuperlayer];
        [back removeFromSuperlayer];

        /* contents: an image, the right way up, placed by the gravity */
        CGImageRef img = quad_image();
        box.backgroundColor = NULL;
        box.frame = CGRectMake(0, 0, 64, 64);
        box.contents = (__bridge id)img;
        ctx = draw(root);
        printf("contents: top left %s, top right %s, bottom left %s, bottom right %s\n", name(ctx, 16, 48),
               name(ctx, 48, 48), name(ctx, 16, 16), name(ctx, 48, 16));
        CGContextRelease(ctx);
        root.geometryFlipped = YES;
        ctx = draw(root);
        printf("in a flipped superlayer: top left %s, bottom left %s\n", name(ctx, 16, 48), name(ctx, 16, 16));
        CGContextRelease(ctx);
        root.geometryFlipped = NO;
        box.contentsScale = 1.0 / 8;
        box.contentsGravity = kCAGravityBottomLeft;
        ctx = draw(root);
        printf("bottom left gravity: (4,12) %s, (12,4) %s, (40,40) %s\n", name(ctx, 4, 12), name(ctx, 12, 4),
               name(ctx, 40, 40));
        CGContextRelease(ctx);
        box.contentsGravity = kCAGravityTopRight;
        ctx = draw(root);
        printf("top right gravity: (52,60) %s, (60,52) %s, (8,8) %s\n", name(ctx, 52, 60), name(ctx, 60, 52),
               name(ctx, 8, 8));
        CGContextRelease(ctx);
        box.contentsGravity = kCAGravityCenter;
        ctx = draw(root);
        printf("centred: (28,36) %s, (36,28) %s, (4,4) %s\n", name(ctx, 28, 36), name(ctx, 36, 28), name(ctx, 4, 4));
        CGContextRelease(ctx);
        box.contentsScale = 1;
        box.bounds = CGRectMake(0, 0, 64, 32);
        box.contentsGravity = kCAGravityResizeAspect;
        ctx = draw(root);
        printf("aspect fit: (20,40) %s, (44,24) %s, (4,32) %s\n", name(ctx, 20, 40), name(ctx, 44, 24), name(ctx, 4, 32));
        CGContextRelease(ctx);
        box.contents = nil;
        box.contentsGravity = kCAGravityResize;

        /* a delegate that draws, and one that sets the contents */
        Painter *painter = [Painter new];
        box.frame = CGRectMake(0, 0, 64, 64);
        box.delegate = painter;
        ctx = draw(root);
        printf("before setNeedsDisplay: draws %d, %s\n", painter.draws, name(ctx, 32, 16));
        CGContextRelease(ctx);
        [box setNeedsDisplay];
        ctx = draw(root);
        printf("after: draws %d, bottom %s, top %s, contents is an image: %s\n", painter.draws, name(ctx, 32, 16),
               name(ctx, 32, 48), yes(box.contents != nil));
        CGContextRelease(ctx);
        ctx = draw(root);
        printf("drawn again without asking: draws %d\n", painter.draws);
        CGContextRelease(ctx);
        box.geometryFlipped = YES;
        root.geometryFlipped = YES;
        [box setNeedsDisplay];
        ctx = draw(root);
        printf("drawn flipped: draws %d, contents flipped %s, top %s, bottom %s\n", painter.draws,
               yes([box contentsAreFlipped]), name(ctx, 32, 48), name(ctx, 32, 16));
        CGContextRelease(ctx);
        root.geometryFlipped = NO;
        box.geometryFlipped = NO;
        box.needsDisplayOnBoundsChange = YES;
        [box displayIfNeeded];
        box.bounds = CGRectMake(0, 0, 32, 32);
        printf("needs display on a bounds change: %s\n", yes([box needsDisplay]));
        Setter *setter = [Setter new];
        box.delegate = setter;
        box.frame = CGRectMake(0, 0, 64, 64);
        [box setNeedsDisplay];
        ctx = draw(root);
        printf("displayLayer: top left %s\n", name(ctx, 16, 48));
        CGContextRelease(ctx);
        box.delegate = nil;
        box.contents = nil;

        /* a subclass that draws with a property of its own */
        dial.frame = CGRectMake(0, 0, 64, 64);
        dial.level = 0.5;
        [root addSublayer:dial];
        ctx = draw(root);
        printf("dial at a half: (16,32) %s, (48,32) %s\n", name(ctx, 16, 32), name(ctx, 48, 32));
        CGContextRelease(ctx);
        [dial removeFromSuperlayer];

        /* ---- shape layers ---- */
        CAShapeLayer *shape = [CAShapeLayer layer];
        printf("shape defaults: fill alpha %g, stroke %s, line width %g, miter %g, end %g, cap %s\n",
               CGColorGetAlpha(shape.fillColor), shape.strokeColor ? "set" : "none", shape.lineWidth,
               shape.miterLimit, shape.strokeEnd, [shape.lineCap UTF8String]);
        shape.frame = CGRectMake(0, 0, 64, 64);
        CGPathRef circle = CGPathCreateWithEllipseInRect(CGRectMake(8, 8, 48, 48), NULL);
        shape.path = circle;
        shape.fillColor = rgb(1, 0, 0, 1);
        [box removeFromSuperlayer];
        [root addSublayer:shape];
        ctx = draw(root);
        printf("filled circle: centre %s, corner %s\n", name(ctx, 32, 32), name(ctx, 10, 10));
        CGContextRelease(ctx);
        shape.fillColor = NULL;
        shape.strokeColor = rgb(0, 0, 1, 1);
        shape.lineWidth = 6;
        ctx = draw(root);
        printf("stroked: edge %s, centre %s, top %s\n", name(ctx, 8, 32), name(ctx, 32, 32), name(ctx, 32, 56));
        CGContextRelease(ctx);
        CGMutablePathRef line = CGPathCreateMutable();
        CGPathMoveToPoint(line, NULL, 4, 32);
        CGPathAddLineToPoint(line, NULL, 60, 32);
        shape.path = line;
        shape.strokeEnd = 0.5;
        ctx = draw(root);
        printf("stroke end at a half: (16,32) %s, (48,32) %s\n", name(ctx, 16, 32), name(ctx, 48, 32));
        CGContextRelease(ctx);
        shape.strokeStart = 0.5;
        shape.strokeEnd = 1;
        ctx = draw(root);
        printf("stroke start at a half: (16,32) %s, (48,32) %s\n", name(ctx, 16, 32), name(ctx, 48, 32));
        CGContextRelease(ctx);
        shape.strokeStart = 0;
        shape.lineDashPattern = @[ @8, @8 ];
        ctx = draw(root);
        printf("dashed: (8,32) %s, (16,32) %s\n", name(ctx, 8, 32), name(ctx, 16, 32));
        CGContextRelease(ctx);
        CGMutablePathRef rings = CGPathCreateMutable();
        CGPathAddRect(rings, NULL, CGRectMake(8, 8, 48, 48));
        CGPathAddRect(rings, NULL, CGRectMake(24, 24, 16, 16));
        shape.path = rings;
        shape.strokeColor = NULL;
        shape.fillColor = rgb(0, 1, 0, 1);
        shape.fillRule = kCAFillRuleEvenOdd;
        ctx = draw(root);
        printf("even-odd: ring %s, hole %s\n", name(ctx, 12, 32), name(ctx, 32, 32));
        CGContextRelease(ctx);
        [shape removeFromSuperlayer];

        /* ---- gradient layers ---- */
        CAGradientLayer *grad = [CAGradientLayer layer];
        printf("gradient defaults: start %g %g, end %g %g, type %s\n", grad.startPoint.x, grad.startPoint.y,
               grad.endPoint.x, grad.endPoint.y, [grad.type UTF8String]);
        grad.frame = CGRectMake(0, 0, 64, 64);
        grad.colors = @[ (__bridge id)rgb(1, 0, 0, 1), (__bridge id)rgb(0, 0, 1, 1) ];
        [root addSublayer:grad];
        ctx = draw(root);
        const unsigned char *lo = pixel(ctx, 32, 1), *mid = pixel(ctx, 32, 32), *hi = pixel(ctx, 32, 62);
        printf("axial: bottom red %s, top blue %s, middle between %s\n", yes(lo[0] > 240 && lo[2] < 15),
               yes(hi[2] > 240 && hi[0] < 15), yes(mid[0] > 100 && mid[0] < 155 && mid[2] > 100 && mid[2] < 155));
        CGContextRelease(ctx);
        grad.startPoint = CGPointMake(0, 0.5);
        grad.endPoint = CGPointMake(1, 0.5);
        grad.locations = @[ @0.5, @0.5 ];
        ctx = draw(root);
        printf("sideways, a hard edge at the middle: (16,32) %s, (48,32) %s\n", name(ctx, 16, 32), name(ctx, 48, 32));
        CGContextRelease(ctx);
        grad.type = kCAGradientLayerRadial;
        grad.locations = nil;
        grad.startPoint = CGPointMake(0.5, 0.5);
        grad.endPoint = CGPointMake(1, 1);
        ctx = draw(root);
        const unsigned char *centre = pixel(ctx, 32, 32);
        printf("radial: centre red %s, corner %s\n", yes(centre[0] > 230 && centre[2] < 30), name(ctx, 1, 1));
        CGContextRelease(ctx);
        [grad removeFromSuperlayer];

        /* ---- text layers ---- */
        CATextLayer *text = [CATextLayer layer];
        printf("text defaults: size %g, colour white %s, wrapped %s\n", text.fontSize,
               yes(CGColorGetAlpha(text.foregroundColor) == 1 && CGColorGetComponents(text.foregroundColor)[0] == 1),
               yes(text.wrapped));
        text.frame = CGRectMake(0, 0, 64, 64);
        text.string = @"Hi";
        text.fontSize = 24;
        text.foregroundColor = rgb(0, 0, 0, 1);
        [root addSublayer:text];
        ctx = draw(root);
        int top = 0, bottom = 0;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
                if (pixel(ctx, x, y)[0] < 128)
                    *(y >= 32 ? &top : &bottom) += 1;
        printf("text: ink at the top %s, none at the bottom %s\n", yes(top > 20), yes(bottom == 0));
        CGContextRelease(ctx);
        text.alignmentMode = kCAAlignmentRight;
        ctx = draw(root);
        int left = 0, right = 0;
        for (int y = 32; y < H; y++)
            for (int x = 0; x < W; x++)
                if (pixel(ctx, x, y)[0] < 128)
                    *(x >= 32 ? &right : &left) += 1;
        printf("right aligned: ink on the right %s, none on the left %s\n", yes(right > 20), yes(left == 0));
        CGContextRelease(ctx);
    }
    return 0;
}
