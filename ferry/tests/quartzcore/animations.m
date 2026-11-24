/* Ferry test: Core Animation's transforms, timing, transactions and
 * animations. Apart from one short animation run on the real clock through
 * the run loop, the clock is Ferry's test hook: it stands still until the
 * test moves it, and each move steps the animations at once. */
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>

/* Ferry's test hooks (QuartzCore exports them; a Mac's doesn't have them). */
extern void FerryCASetManualClock(CFTimeInterval now);
extern void FerryCAAdvanceTime(CFTimeInterval seconds);
extern void FerryCALayerRender(CALayer *layer, CGContextRef ctx, BOOL presentation, BOOL flipped,
                               void (^content)(CGContextRef ctx));

static const char *yes(BOOL b) { return b ? "yes" : "no"; }

static NSMutableArray *events;

@interface Watcher : NSObject <CAAnimationDelegate>
@end
@implementation Watcher
- (void)animationDidStart:(CAAnimation *)anim
{
    [events addObject:[NSString stringWithFormat:@"start %@", [anim valueForKey:@"tag"]]];
}
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    [events addObject:[NSString stringWithFormat:@"stop %@ %@", [anim valueForKey:@"tag"], flag ? @"finished" : @"cut short"]];
}
@end

static Watcher *watcher;

static void show_events(void)
{
    printf("  events: %s\n", [events count] ? [[events componentsJoinedByString:@", "] UTF8String] : "none");
    [events removeAllObjects];
}

static CABasicAnimation *basic(NSString *path, id from, id to, double duration, NSString *tag)
{
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:path];
    a.fromValue = from;
    a.toValue = to;
    a.duration = duration;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    a.delegate = watcher;
    [a setValue:tag forKey:@"tag"];
    return a;
}

static double shownX(CALayer *l) { return l.presentationLayer.position.x; }
static double shown(CALayer *l, NSString *path) { return [[l.presentationLayer valueForKeyPath:path] doubleValue]; }

static void point(const char *what, CGAffineTransform t, CGPoint p)
{
    p = CGPointApplyAffineTransform(p, t);
    printf("%s: %.3g %.3g\n", what, fabs(p.x) < 1e-9 ? 0 : p.x, fabs(p.y) < 1e-9 ? 0 : p.y);
}

@interface Mover : NSObject <CALayerDelegate>
@end
@implementation Mover
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    if ([event isEqualToString:@"position"]) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:event];
        a.duration = 2;
        return a;
    }
    if ([event isEqualToString:@"opacity"])
        return (id)[NSNull null];
    return nil;
}
@end

@interface Gauge : CALayer
@property CGFloat level;
@end
@implementation Gauge
@dynamic level;
+ (BOOL)needsDisplayForKey:(NSString *)key { return [key isEqualToString:@"level"] || [super needsDisplayForKey:key]; }
- (void)drawInContext:(CGContextRef)ctx
{
    CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, self.bounds.size.width * self.level, self.bounds.size.height));
}
@end

static int red_columns(CGContextRef c)
{
    const unsigned char *d = CGBitmapContextGetData(c);
    size_t bpr = CGBitmapContextGetBytesPerRow(c);
    int n = 0;
    for (int x = 0; x < 64; x++)
        if (d[32 * bpr + x * 4] > 200 && d[32 * bpr + x * 4 + 1] < 50)
            n++;
    return n;
}

static CGContextRef canvas(void)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, 64, 64, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 64, 64));
    return c;
}

int main(void)
{
    @autoreleasepool {
        events = [NSMutableArray new];
        watcher = [Watcher new];

        /* ---- on the real clock, through the run loop ---- */
        {
            CALayer *l = [CALayer layer];
            [CATransaction flush];
            __block BOOL done = NO;
            [CATransaction begin];
            [CATransaction setCompletionBlock:^{
              done = YES;
            }];
            [l addAnimation:basic(@"opacity", @1, @0, 0.05, @"realtime") forKey:@"fade"];
            [CATransaction commit];
            NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
            while (!done && [limit timeIntervalSinceNow] > 0)
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            printf("real clock: completed %s, animation gone %s\n", yes(done), yes([l animationKeys] == nil));
            show_events();
            double t0 = CACurrentMediaTime();
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            printf("media time goes on: %s\n", yes(CACurrentMediaTime() > t0));
        }

        /* ---- transforms ---- */
        CATransform3D r = CATransform3DMakeRotation(M_PI / 2, 0, 0, 1);
        point("rotated (1,0)", CATransform3DGetAffineTransform(r), CGPointMake(1, 0));
        CATransform3D st = CATransform3DConcat(CATransform3DMakeScale(2, 2, 1), CATransform3DMakeTranslation(10, 0, 0));
        point("scaled then moved (1,1)", CATransform3DGetAffineTransform(st), CGPointMake(1, 1));
        CATransform3D ts = CATransform3DTranslate(CATransform3DMakeScale(2, 2, 1), 10, 0, 0);
        point("CATransform3DTranslate of a scale, (0,0)", CATransform3DGetAffineTransform(ts), CGPointMake(0, 0));
        CATransform3D rs = CATransform3DRotate(CATransform3DMakeTranslation(5, 0, 0), M_PI, 0, 0, 1);
        point("CATransform3DRotate of a move, (1,0)", CATransform3DGetAffineTransform(rs), CGPointMake(1, 0));
        CATransform3D inv = CATransform3DInvert(st);
        printf("inverse undoes it: %s\n", yes(CATransform3DIsIdentity(CATransform3DConcat(st, inv))));
        printf("identity: %s, equal: %s, affine: %s, about x affine: %s\n", yes(CATransform3DIsIdentity(CATransform3DIdentity)),
               yes(CATransform3DEqualToTransform(st, st)), yes(CATransform3DIsAffine(st)),
               yes(CATransform3DIsAffine(CATransform3DMakeRotation(0.5, 1, 0, 0))));
        CGAffineTransform at = CGAffineTransformMake(1, 2, 3, 4, 5, 6);
        CGAffineTransform back = CATransform3DGetAffineTransform(CATransform3DMakeAffineTransform(at));
        printf("affine round trip: %g %g %g %g %g %g\n", back.a, back.b, back.c, back.d, back.tx, back.ty);
        NSValue *v = [NSValue valueWithCATransform3D:st];
        printf("in an NSValue: %s, equal %s\n", yes(CATransform3DEqualToTransform([v CATransform3DValue], st)),
               yes([v isEqual:[NSValue valueWithCATransform3D:st]]));
        CATransform3D p = CATransform3DIdentity;
        p.m34 = -1.0 / 500;
        printf("perspective is not affine: %s\n", yes(!CATransform3DIsAffine(p)));

        /* ---- timing functions ---- */
        float cp[2];
        CAMediaTimingFunction *ease = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        [ease getControlPointAtIndex:1 values:cp];
        printf("ease in, first control point: %g %g\n", cp[0], cp[1]);
        [[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault] getControlPointAtIndex:2 values:cp];
        printf("default, second control point: %g %g\n", cp[0], cp[1]);

        FerryCASetManualClock(1000);
        printf("manual clock: %g\n", CACurrentMediaTime());

        CALayer *layer = [CALayer layer];
        layer.bounds = CGRectMake(0, 0, 10, 10);
        printf("not animated before the layer is committed: %s\n", yes([layer animationKeys] == nil));
        [CATransaction flush];

        NSArray *names = @[ kCAMediaTimingFunctionLinear, kCAMediaTimingFunctionEaseIn, kCAMediaTimingFunctionEaseOut,
                            kCAMediaTimingFunctionEaseInEaseOut, kCAMediaTimingFunctionDefault ];
        for (NSString *n in names) {
            CABasicAnimation *a = basic(@"position.x", @0, @100, 1, n);
            a.delegate = nil;
            a.timingFunction = [CAMediaTimingFunction functionWithName:n];
            [layer addAnimation:a forKey:@"t"];
            FerryCAAdvanceTime(0.25);
            double q = shownX(layer);
            FerryCAAdvanceTime(0.25);
            printf("%s: at a quarter %.1f, at a half %.1f\n", [n UTF8String], q, shownX(layer));
            [layer removeAnimationForKey:@"t"];
        }
        CAMediaTimingFunction *custom = [CAMediaTimingFunction functionWithControlPoints:0.0f :1.0f :0.0f :1.0f];
        CABasicAnimation *ca = basic(@"position.x", @0, @100, 1, @"custom");
        ca.delegate = nil;
        ca.timingFunction = custom;
        [layer addAnimation:ca forKey:@"t"];
        FerryCAAdvanceTime(0.5);
        printf("control points (0,1) (0,1) at a half: %.1f\n", shownX(layer));
        [layer removeAnimationForKey:@"t"];

        /* ---- implicit animations and transactions ---- */
        layer.position = CGPointMake(100, 0);
        printf("implicit: keys %s, shown x %g, model x %g\n", [[[layer animationKeys] description] UTF8String],
               shownX(layer), layer.position.x);
        CABasicAnimation *imp = (CABasicAnimation *)[layer animationForKey:@"position"];
        printf("  a basic animation %s, duration %g, from %s\n", yes([imp isKindOfClass:[CABasicAnimation class]]),
               imp.duration, [[imp.fromValue description] UTF8String]);
        FerryCAAdvanceTime(0.125);
        printf("  halfway (default timing): %.1f\n", shownX(layer));
        FerryCAAdvanceTime(0.125);
        printf("  at the end: %g, keys %s\n", shownX(layer), [layer animationKeys] ? "left" : "none");

        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layer.position = CGPointMake(50, 0);
        [CATransaction commit];
        printf("actions disabled: keys %s, shown %g\n", [layer animationKeys] ? "left" : "none", shownX(layer));

        __block int completions = 0;
        [CATransaction begin];
        [CATransaction setAnimationDuration:1];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        [CATransaction setCompletionBlock:^{
          completions++;
        }];
        layer.opacity = 0;
        layer.backgroundColor = CGColorCreateSRGB(1, 0, 0, 1);
        [CATransaction commit];
        printf("transaction of a second: duration %g, completions %d\n", [layer animationForKey:@"opacity"].duration,
               completions);
        FerryCAAdvanceTime(0.5);
        CGColorRef bg = layer.presentationLayer.backgroundColor;
        printf("  at a half: opacity %g, background from nothing %.2f %.2f %.2f alpha %.2f, completions %d\n",
               layer.presentationLayer.opacity, CGColorGetComponents(bg)[0], CGColorGetComponents(bg)[1],
               CGColorGetComponents(bg)[2], CGColorGetAlpha(bg), completions);
        FerryCAAdvanceTime(0.5);
        printf("  at the end: opacity %g, completions %d\n", layer.presentationLayer.opacity, completions);
        [CATransaction begin];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        layer.backgroundColor = CGColorCreateSRGB(0, 0, 1, 1);
        layer.bounds = CGRectMake(0, 0, 110, 10);
        layer.transform = CATransform3DMakeRotation(M_PI / 2, 0, 0, 1);
        [CATransaction commit];
        FerryCAAdvanceTime(0.125);
        bg = layer.presentationLayer.backgroundColor;
        printf("colour halfway: %.2f %.2f %.2f, width %g, turned %.3f\n", CGColorGetComponents(bg)[0],
               CGColorGetComponents(bg)[1], CGColorGetComponents(bg)[2], layer.presentationLayer.bounds.size.width,
               shown(layer, @"transform.rotation.z"));
        FerryCAAdvanceTime(0.125);

        [CATransaction begin];
        [CATransaction setCompletionBlock:^{
          completions++;
        }];
        [CATransaction commit];
        printf("a transaction with nothing to wait for completes at once: %d\n", completions);
        [CATransaction begin];
        [CATransaction setAnimationDuration:2];
        [CATransaction begin];
        printf("nested: duration from outside %g\n", [CATransaction animationDuration]);
        [CATransaction commit];
        [CATransaction commit];
        printf("outside: default duration %g\n", [CATransaction animationDuration]);

        layer.actions = @{@"opacity" : [NSNull null]};
        layer.opacity = 1;
        printf("NSNull in actions: keys %s\n", [layer animationKeys] ? "left" : "none");
        layer.actions = nil;
        Mover *mover = [Mover new];
        layer.delegate = mover;
        layer.position = CGPointMake(10, 0);
        layer.opacity = 0.5;
        printf("delegate's action: position duration %g, opacity animated %s\n",
               [layer animationForKey:@"position"].duration, yes([layer animationForKey:@"opacity"] != nil));
        [layer removeAllAnimations];
        layer.delegate = nil;
        CALayer *parent = [CALayer layer];
        layer.actions = @{kCAOnOrderIn : basic(@"opacity", @0, @1, 1, @"in")};
        [parent addSublayer:layer];
        printf("on order in: %s\n", [[[layer animationKeys] description] UTF8String]);
        [layer removeAllAnimations];
        show_events();
        layer.actions = nil;
        [CATransaction setDisableActions:YES];
        layer.position = CGPointMake(100, 0);
        layer.opacity = 1;
        [CATransaction flush];

        /* ---- basic animations ---- */
        [layer addAnimation:basic(@"position.x", @0, @200, 1, @"move") forKey:@"move"];
        printf("added: model x %g, shown %g\n", layer.position.x, shownX(layer));
        FerryCAAdvanceTime(0);
        show_events();
        FerryCAAdvanceTime(0.25);
        printf("a quarter in: %g\n", shownX(layer));
        FerryCAAdvanceTime(1);
        printf("over: %g, keys %s\n", shownX(layer), [layer animationKeys] ? "left" : "none");
        show_events();

        CABasicAnimation *keep = basic(@"position.x", @0, @300, 1, @"keep");
        keep.removedOnCompletion = NO;
        keep.fillMode = kCAFillModeForwards;
        [layer addAnimation:keep forKey:@"keep"];
        FerryCAAdvanceTime(2);
        printf("kept with fill forwards: %g, keys %s\n", shownX(layer), [[[layer animationKeys] description] UTF8String]);
        [layer removeAnimationForKey:@"keep"];
        printf("removed: %g\n", shownX(layer));
        show_events();

        [layer addAnimation:basic(@"position.x", @0, @200, 1, @"early") forKey:@"x"];
        FerryCAAdvanceTime(0.5);
        [layer addAnimation:basic(@"position.x", @0, @200, 1, @"second") forKey:@"x"];
        FerryCAAdvanceTime(0.5);
        [layer removeAnimationForKey:@"x"];
        printf("replaced and removed:\n");
        show_events();

        CABasicAnimation *by = basic(@"position.x", nil, nil, 1, @"by");
        by.byValue = @50;
        [layer addAnimation:by forKey:@"by"];
        FerryCAAdvanceTime(0.5);
        printf("by 50 from the model's 100, at a half: %g\n", shownX(layer));
        [layer removeAnimationForKey:@"by"];
        CABasicAnimation *add = basic(@"position.x", @0, @10, 1, @"add");
        add.additive = YES;
        [layer addAnimation:add forKey:@"add"];
        [layer addAnimation:basic(@"position.x", nil, @0, 1, @"to") forKey:@"to"];
        FerryCAAdvanceTime(0.5);
        printf("to 0 (from the value beneath), at a half, after an additive 0 to 10: %g\n", shownX(layer));
        [layer removeAllAnimations];

        CABasicAnimation *rev = basic(@"position.x", @0, @100, 1, @"rev");
        rev.autoreverses = YES;
        rev.repeatCount = 2;
        [layer addAnimation:rev forKey:@"rev"];
        NSMutableString *trail = [NSMutableString string];
        for (int i = 0; i < 9; i++) {
            [trail appendFormat:@" %g", shownX(layer)];
            FerryCAAdvanceTime(0.5);
        }
        printf("autoreversing twice:%s\n", [trail UTF8String]);
        show_events();

        CABasicAnimation *cum = basic(@"position.x", @0, @10, 1, @"cum");
        cum.cumulative = YES;
        cum.repeatCount = 3;
        [layer addAnimation:cum forKey:@"cum"];
        trail = [NSMutableString string];
        for (int i = 0; i < 6; i++) {
            [trail appendFormat:@" %g", shownX(layer)];
            FerryCAAdvanceTime(0.5);
        }
        printf("cumulative, three times:%s\n", [trail UTF8String]);
        [layer removeAllAnimations];

        CABasicAnimation *late = basic(@"position.x", @0, @10, 1, @"late");
        late.beginTime = CACurrentMediaTime() + 1;
        [layer addAnimation:late forKey:@"late"];
        CABasicAnimation *lateb = basic(@"opacity", @0, @1, 1, @"lateb");
        lateb.beginTime = CACurrentMediaTime() + 1;
        lateb.fillMode = kCAFillModeBackwards;
        [layer addAnimation:lateb forKey:@"lateb"];
        FerryCAAdvanceTime(0.5);
        printf("before a later start: x %g (the model's), opacity %g (filled backwards)\n", shownX(layer),
               layer.presentationLayer.opacity);
        show_events();
        FerryCAAdvanceTime(1);
        printf("half way through it: x %g, opacity %g\n", shownX(layer), layer.presentationLayer.opacity);
        show_events();
        [layer removeAllAnimations];
        show_events();

        CABasicAnimation *fast = basic(@"position.x", @0, @100, 1, @"fast");
        fast.speed = 2;
        [layer addAnimation:fast forKey:@"fast"];
        FerryCAAdvanceTime(0.25);
        printf("at twice the speed, a quarter second in: %g\n", shownX(layer));
        [layer removeAllAnimations];

        CABasicAnimation *spin = basic(@"transform.rotation.z", @0, @(2 * M_PI), 1, @"spin");
        [layer addAnimation:spin forKey:@"spin"];
        FerryCAAdvanceTime(0.25);
        printf("a full turn, a quarter in: %.4f\n", shown(layer, @"transform.rotation.z"));
        [layer removeAllAnimations];
        show_events();

        /* ---- keyframe animations ---- */
        CAKeyframeAnimation *k = [CAKeyframeAnimation animationWithKeyPath:@"position.x"];
        k.values = @[ @0, @10, @30 ];
        k.duration = 1;
        NSArray *modes = @[ kCAAnimationLinear, kCAAnimationDiscrete, kCAAnimationPaced, kCAAnimationCubic ];
        for (NSString *mode in modes) {
            k.calculationMode = mode;
            [layer addAnimation:k forKey:@"k"];
            trail = [NSMutableString string];
            for (int i = 0; i < 4; i++) {
                FerryCAAdvanceTime(0.25);
                [trail appendFormat:@" %g", round(shownX(layer) * 100) / 100];
            }
            printf("keyframes, %s:%s\n", [mode UTF8String], [trail UTF8String]);
            [layer removeAllAnimations];
        }
        k.calculationMode = kCAAnimationLinear;
        k.keyTimes = @[ @0, @0.8, @1 ];
        [layer addAnimation:k forKey:@"k"];
        FerryCAAdvanceTime(0.4);
        printf("key times 0, 0.8, 1, at 0.4: %g\n", shownX(layer));
        [layer removeAllAnimations];
        k.keyTimes = nil;
        k.timingFunctions = @[ [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn],
                               [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear] ];
        [layer addAnimation:k forKey:@"k"];
        FerryCAAdvanceTime(0.25);
        printf("eased first segment, at a quarter: %.2f\n", shownX(layer));
        [layer removeAllAnimations];

        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, 100, 0);
        CGPathAddLineToPoint(path, NULL, 100, 300);
        CAKeyframeAnimation *along = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        along.path = path;
        along.duration = 1;
        [layer addAnimation:along forKey:@"along"];
        FerryCAAdvanceTime(0.25);
        CGPoint pp = layer.presentationLayer.position;
        printf("along a path, a segment each half, at a quarter: %g %g\n", pp.x, pp.y);
        [layer removeAllAnimations];
        along.calculationMode = kCAAnimationPaced;
        [layer addAnimation:along forKey:@"along"];
        FerryCAAdvanceTime(0.5);
        pp = layer.presentationLayer.position;
        printf("paced along it, at a half: %g %g\n", pp.x, pp.y);
        [layer removeAllAnimations];

        /* ---- groups ---- */
        CAAnimationGroup *g = [CAAnimationGroup animation];
        CABasicAnimation *fade = basic(@"opacity", @1, @0, 1, @"fade");
        CABasicAnimation *slide = basic(@"position.x", @0, @100, 2, @"slide");
        g.animations = @[ fade, slide ];
        g.duration = 1.5;
        g.delegate = watcher;
        [g setValue:@"group" forKey:@"tag"];
        [layer addAnimation:g forKey:@"g"];
        FerryCAAdvanceTime(0.5);
        printf("group at 0.5: opacity %g, x %g\n", layer.presentationLayer.opacity, shownX(layer));
        FerryCAAdvanceTime(0.75);
        printf("group at 1.25: opacity %g (the fade is over), x %g\n", layer.presentationLayer.opacity, shownX(layer));
        FerryCAAdvanceTime(0.5);
        printf("group over: x %g, keys %s\n", shownX(layer), [layer animationKeys] ? "left" : "none");
        show_events();

        /* ---- springs ---- */
        CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"position.x"];
        printf("spring defaults: mass %g, stiffness %g, damping %g, velocity %g\n", spring.mass, spring.stiffness,
               spring.damping, spring.initialVelocity);
        spring.fromValue = @0;
        spring.toValue = @100;
        printf("settling duration: %.2f\n", spring.settlingDuration);
        spring.duration = spring.settlingDuration;
        [layer addAnimation:spring forKey:@"spring"];
        trail = [NSMutableString string];
        for (int i = 0; i < 4; i++) {
            FerryCAAdvanceTime(0.25);
            [trail appendFormat:@" %.1f", shownX(layer)];
        }
        printf("spring every quarter second:%s\n", [trail UTF8String]);
        FerryCAAdvanceTime(spring.settlingDuration);
        printf("spring settled: %g, keys %s\n", shownX(layer), [layer animationKeys] ? "left" : "none");
        spring.damping = 20;
        printf("critically damped settles in %.2f\n", spring.settlingDuration);

        /* ---- the layer that's shown, drawn ---- */
        CALayer *root = [CALayer layer];
        root.frame = CGRectMake(0, 0, 64, 64);
        Gauge *gauge = [Gauge layer];
        gauge.frame = CGRectMake(0, 0, 64, 64);
        [root addSublayer:gauge];
        [CATransaction flush];
        [gauge addAnimation:basic(@"level", @0, @1, 1, @"level") forKey:@"level"];
        FerryCAAdvanceTime(0.25);
        CGContextRef c = canvas();
        FerryCALayerRender(root, c, YES, NO, nil);
        printf("a property drawn while it animates, at a quarter: %d of 64 columns\n", red_columns(c));
        CGContextRelease(c);
        FerryCAAdvanceTime(0.5);
        c = canvas();
        FerryCALayerRender(root, c, YES, NO, nil);
        printf("  at three quarters: %d\n", red_columns(c));
        CGContextRelease(c);
        c = canvas();
        [root renderInContext:c];
        printf("  renderInContext: draws the model: %d\n", red_columns(c));
        CGContextRelease(c);
        FerryCAAdvanceTime(1);
        show_events();
        CALayer *dot = [CALayer layer];
        dot.backgroundColor = CGColorCreateSRGB(1, 0, 0, 1);
        dot.frame = CGRectMake(0, 0, 8, 64);
        [root addSublayer:dot];
        c = canvas();
        FerryCALayerRender(root, c, YES, NO, nil);
        CGContextRelease(c);
        dot.position = CGPointMake(60, 32);
        FerryCAAdvanceTime(0.125);
        c = canvas();
        FerryCALayerRender(root, c, YES, NO, nil);
        double x = shownX(dot);
        const unsigned char *row = (unsigned char *)CGBitmapContextGetData(c) + 32 * CGBitmapContextGetBytesPerRow(c);
        printf("a moving layer, halfway with the default timing: shown at %.1f, drawn there %s, %d columns wide, "
               "not at the start %s\n",
               x, yes(row[(int)x * 4] > 200 && row[(int)x * 4 + 1] < 50), red_columns(c), yes(row[4 * 4 + 1] > 200));
        CGContextRelease(c);
        CALayer *shownDot = dot.presentationLayer;
        printf("presentation's model is the layer: %s; a presentation's presentation is itself: %s\n",
               yes(shownDot.modelLayer == dot), yes(shownDot.presentationLayer == shownDot));
    }
    return 0;
}
