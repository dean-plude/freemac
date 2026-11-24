/* SPDX-License-Identifier: GPL-3.0-or-later
 * AppKit with Core Animation, without a display: layer-backed and
 * layer-hosting views drawn with cacheDisplayInRect:, NSAnimationContext
 * groups and the views' animator proxies, stepped by Core Animation's
 * test clock (Ferry's own hook) so that every step is the same each run. */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

extern void FerryCASetManualClock(CFTimeInterval now);
extern void FerryCAAdvanceTime(CFTimeInterval seconds);

static const char *yes(BOOL b) { return b ? "yes" : "no"; }
static void show(const char *what, NSString *s) { printf("%s: %s\n", what, [s UTF8String]); }

/* A pixel by name, rows counted from the top. */
static const char *colour_at(NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:y] getRed:&r green:&g blue:&b
                                                alpha:&a];
    static char buf[64];
    if (a < 0.05)
        return "clear";
    if (a < 0.95) {
        snprintf(buf, sizeof buf, "alpha %.1f", a);
        return buf;
    }
    struct { const char *name; double r, g, b; } named[] = {
        {"red", 1, 0, 0},   {"green", 0, 1, 0},  {"blue", 0, 0, 1},    {"white", 1, 1, 1},
        {"black", 0, 0, 0}, {"yellow", 1, 1, 0}, {"purple", 0.5, 0, 0.5},
    };
    for (unsigned i = 0; i < sizeof named / sizeof *named; i++)
        if (fabs(r - named[i].r) < 0.1 && fabs(g - named[i].g) < 0.1 && fabs(b - named[i].b) < 0.1)
            return named[i].name;
    snprintf(buf, sizeof buf, "%.2f %.2f %.2f", r, g, b);
    return buf;
}

static NSBitmapImageRep *snapshot(NSView *v)
{
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    return rep;
}

static CGColorRef rgb(double r, double g, double b) { return [[NSColor colorWithDeviceRed:r green:g blue:b alpha:1] CGColor]; }

/* Fills a 10x10 square in the middle of its bounds with green. */
@interface Filler : NSView
@property int draws;
@property BOOL flip;
@end
@implementation Filler
- (BOOL)isFlipped { return self.flip; }
- (void)drawRect:(NSRect)dirty
{
    self.draws++;
    NSRect b = self.bounds;
    [[NSColor greenColor] set];
    NSRectFill(NSMakeRect(NSMidX(b) - 5, NSMidY(b) - 5, 10, 10));
}
@end

@interface Shaped : NSView
@end
@implementation Shaped
- (CALayer *)makeBackingLayer { return [CAShapeLayer layer]; }
@end

/* Sets its layer's colour in updateLayer instead of drawing. */
@interface Updater : NSView
@property int updates, draws;
@end
@implementation Updater
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer
{
    self.updates++;
    self.layer.backgroundColor = rgb(1, 1, 0);
}
- (void)drawRect:(NSRect)dirty { self.draws++; }
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        /* ---- the backing layer ---- */
        Filler *v = [[Filler alloc] initWithFrame:NSMakeRect(10, 20, 40, 30)];
        printf("no layer before wantsLayer: %s\n", yes(v.layer == nil));
        v.wantsLayer = YES;
        CALayer *l = v.layer;
        printf("backing layer: %s, delegate is the view: %s\n", [NSStringFromClass([l class]) UTF8String],
               yes(l.delegate == (id)v));
        show("layer frame", NSStringFromRect(l.frame));
        show("layer anchor", NSStringFromPoint(l.anchorPoint));
        [v setFrame:NSMakeRect(5, 6, 50, 40)];
        show("layer frame after the view moved", NSStringFromRect(l.frame));
        printf("no animation for that change: %s\n", yes(l.animationKeys.count == 0));
        v.alphaValue = 0.5;
        printf("alphaValue 0.5: opacity %.2f\n", l.opacity);
        v.alphaValue = 1;
        v.hidden = YES;
        printf("hidden view, hidden layer: %s\n", yes(l.hidden));
        v.hidden = NO;
        Shaped *shaped = [[Shaped alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        shaped.wantsLayer = YES;
        printf("makeBackingLayer: %s\n", [NSStringFromClass([shaped.layer class]) UTF8String]);
        shaped.wantsLayer = NO;
        printf("wantsLayer NO drops it: %s\n", yes(shaped.layer == nil));

        /* ---- drawing: the layer's background, the view's drawing, the border on top ---- */
        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
        [v setFrame:NSMakeRect(10, 10, 40, 40)];
        [box addSubview:v];
        l.backgroundColor = rgb(1, 0, 0);
        l.borderColor = rgb(0, 0, 1);
        l.borderWidth = 2;
        NSBitmapImageRep *rep = snapshot(box);
        /* the view covers x 10..50 and, from the top, y 10..50 */
        printf("drawn: border %s, background %s, drawRect %s, outside %s; drawRect calls %d\n",
               colour_at(rep, 11, 30), colour_at(rep, 15, 30), colour_at(rep, 30, 30), colour_at(rep, 60, 30), v.draws);
        CALayer *dot = [CALayer layer];
        dot.frame = CGRectMake(4, 4, 6, 6);
        dot.backgroundColor = rgb(1, 1, 1);
        [l addSublayer:dot];
        rep = snapshot(box);
        printf("a sublayer at (4,4), above the drawing, from the bottom: %s; top-left stays %s\n",
               colour_at(rep, 16, 42), colour_at(rep, 16, 16));
        v.flip = YES;
        [v setNeedsDisplay:YES];
        rep = snapshot(box);
        printf("in a flipped view the sublayer is at the top: %s; the bottom-left is %s\n", colour_at(rep, 16, 16),
               colour_at(rep, 16, 42));
        v.flip = NO;
        [dot removeFromSuperlayer];
        v.alphaValue = 0.5;
        rep = snapshot(box);
        printf("alphaValue 0.5 drawn: background %s, drawRect %s\n", colour_at(rep, 15, 30), colour_at(rep, 30, 30));
        v.alphaValue = 1;
        l.cornerRadius = 10;
        l.borderWidth = 0;
        rep = snapshot(box);
        printf("cornerRadius 10: the corner %s, the edge's middle %s\n", colour_at(rep, 10, 10), colour_at(rep, 10, 30));
        l.cornerRadius = 0;

        /* ---- updateLayer ---- */
        Updater *u = [[Updater alloc] initWithFrame:NSMakeRect(60, 10, 30, 30)];
        u.wantsLayer = YES;
        [box addSubview:u];
        rep = snapshot(box);
        printf("updateLayer: %d calls, drawRect %d calls, drawn %s\n", u.updates, u.draws, colour_at(rep, 75, 35));
        snapshot(box);
        printf("not needing display: still %d calls\n", u.updates);
        [u setNeedsDisplay:YES];
        snapshot(box);
        printf("after setNeedsDisplay: %d calls\n", u.updates);
        [u removeFromSuperview];

        /* ---- a hosted layer ---- */
        Filler *host = [[Filler alloc] initWithFrame:NSMakeRect(60, 10, 30, 30)];
        CALayer *hosted = [CALayer layer];
        hosted.backgroundColor = rgb(0.5, 0, 0.5);
        host.layer = hosted;
        host.wantsLayer = YES;
        [box addSubview:host];
        rep = snapshot(box);
        printf("hosted layer: kept %s, delegate not the view %s, frame %s, drawn %s, drawRect calls %d\n",
               yes(host.layer == hosted), yes(hosted.delegate != (id)host), [NSStringFromRect(hosted.frame) UTF8String],
               colour_at(rep, 75, 35), host.draws);
        [host removeFromSuperview];

        /* ---- NSAnimationContext and the animator ---- */
        FerryCASetManualClock(1000);
        NSAnimationContext *outside = [NSAnimationContext currentContext];
        printf("the context outside a group: duration %.2f, implicit %s\n", outside.duration,
               yes(outside.allowsImplicitAnimation));
        printf("default animations: frame %s, alphaValue %s, toolTip %s\n",
               [NSStringFromClass([[v animationForKey:@"frame"] class]) UTF8String],
               [NSStringFromClass([[v animationForKey:@"alphaValue"] class]) UTF8String],
               yes([v animationForKey:@"toolTip"] == nil));
        __block int completions = 0;
        [v setFrame:NSMakeRect(0, 0, 20, 20)];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
          context.duration = 1;
          context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
          printf("in the group: duration %.2f, the transaction's %.2f, current %s\n", context.duration,
                 [CATransaction animationDuration], yes(context == [NSAnimationContext currentContext]));
          [[v animator] setFrame:NSMakeRect(40, 20, 60, 40)];
          [v animator].alphaValue = 0.25;
        } completionHandler:^{
          completions++;
        }];
        show("frame right after", NSStringFromRect(v.frame));
        FerryCAAdvanceTime(0.5);
        show("frame halfway", NSStringFromRect(v.frame));
        printf("alpha halfway %.3f, layer opacity %.3f, done %d\n", v.alphaValue, l.opacity, completions);
        FerryCAAdvanceTime(0.6);
        show("frame at the end", NSStringFromRect(v.frame));
        printf("alpha at the end %.3f, completion handler ran %d time(s)\n", v.alphaValue, completions);
        FerryCAAdvanceTime(0.5);
        printf("and not again: %d\n", completions);

        [v animator].alphaValue = 1;
        FerryCAAdvanceTime(0.125);
        printf("animator outside a group (a quarter second, default timing): after 1/8 s %.3f, ", v.alphaValue);
        FerryCAAdvanceTime(0.2);
        printf("after 0.325 s %.3f\n", v.alphaValue);
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
          context.duration = 0;
          [[v animator] setFrameOrigin:NSMakePoint(7, 8)];
        }];
        show("duration 0 sets it at once", NSStringFromRect(v.frame));
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
          context.duration = 1;
          [[v animator] setFrameOrigin:NSMakePoint(30, 8)];
        }];
        FerryCAAdvanceTime(0.5);
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
          context.duration = 1;
          context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
          [[v animator] setFrameOrigin:NSMakePoint(0, 8)];
        }];
        FerryCAAdvanceTime(0.5);
        printf("a new animation of the same property takes over: x %.1f (halfway from %s)\n", v.frame.origin.x,
               v.frame.origin.x < 30 ? "where it was" : "?");
        FerryCAAdvanceTime(0.6);
        show("and ends where it was sent", NSStringFromRect(v.frame));
        v.animations = @{@"frameOrigin" : [NSNull null]};
        [[v animator] setFrameOrigin:NSMakePoint(9, 9)];
        show("an animations entry of NSNull: set at once", NSStringFromPoint(v.frame.origin));
        v.animations = @{};
        [[v animator] setToolTip:@"tip"];
        printf("other messages go to the view: %s\n", [[v toolTip] UTF8String]);

        /* ---- implicit animations of the backing layer ---- */
        [v setFrame:NSMakeRect(10, 10, 40, 40)];
        snapshot(box);
        [v setFrameOrigin:NSMakePoint(20, 10)];
        printf("frame change outside a group animates the layer: %s\n", yes([l animationForKey:@"position"] != nil));
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
          context.duration = 1;
          context.allowsImplicitAnimation = YES;
          context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
          [v setFrameOrigin:NSMakePoint(50, 10)];
        }];
        printf("with allowsImplicitAnimation it does: %s, over %.2f s\n",
               yes([l animationForKey:@"position"] != nil), [l animationForKey:@"position"].duration);
        FerryCAAdvanceTime(0.5);
        rep = snapshot(box);
        printf("halfway (linear) shown at x %.1f, drawn there: x 38 %s, x 55 %s, x 32 %s, x 78 %s\n",
               l.presentationLayer.position.x, colour_at(rep, 38, 30), colour_at(rep, 55, 30),
               colour_at(rep, 32, 30), colour_at(rep, 78, 30));
        FerryCAAdvanceTime(1);
        printf("finished: animation gone %s\n", yes([l animationForKey:@"position"] == nil));

        /* ---- an explicit animation of a view's layer ---- */
        [v setFrameOrigin:NSMakePoint(10, 10)];
        CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"position.x"];
        slide.fromValue = @50;
        slide.toValue = @50;
        slide.duration = 10;
        [l addAnimation:slide forKey:@"slide"];
        FerryCAAdvanceTime(0.1);
        rep = snapshot(box);
        printf("drawn where its layer is shown: x 50..90 %s, x 20 %s; the view's frame stays %s\n",
               colour_at(rep, 70, 30), colour_at(rep, 20, 30), [NSStringFromRect(v.frame) UTF8String]);
        FerryCAAdvanceTime(10);
        rep = snapshot(box);
        printf("after it: x 20 %s, x 70 %s\n", colour_at(rep, 20, 30), colour_at(rep, 70, 30));

        /* ---- a window draws layer-backed views ---- */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 100, 60)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w setReleasedWhenClosed:NO];
        [w.contentView setWantsLayer:YES];
        [[w.contentView layer] setBackgroundColor:rgb(0, 0, 1)];
        [w display];
        rep = snapshot(w.contentView);
        printf("a window's layer-backed content view: %s\n", colour_at(rep, 50, 30));
        [w close];
    }
    return 0;
}
