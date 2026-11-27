/* SPDX-License-Identifier: GPL-3.0-or-later
 * A layer shown through a context (freemac, Godot work): a CAContext gives
 * a layer tree an ID; a CALayerHost with that ID shows the tree as its own
 * sublayer, placed by the tree's anchor point and position, and follows its
 * changes; an invalidated context leaves the host blank. Drawn with
 * renderInContext: and checked pixel by pixel. */
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CAContext.h>
#include <stdio.h>
#include <unistd.h>

#define W 64
#define H 64

static CGColorRef rgb(double r, double g, double b)
{
    static NSMutableArray *keep;
    if (!keep)
        keep = [NSMutableArray new];
    CGColorRef c = CGColorCreateSRGB(r, g, b, 1);
    [keep addObject:(__bridge id)c];
    CGColorRelease(c);
    return c;
}

static void spin(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]]; }

/* the colour at (x, y), y counted up from the bottom, as r g b letters */
static const char *at(CALayer *root, int x, int y)
{
    static char out[8];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    [root renderInContext:c];
    const uint8_t *p = (const uint8_t *)CGBitmapContextGetData(c) + (H - 1 - y) * CGBitmapContextGetBytesPerRow(c) + x * 4;
    snprintf(out, sizeof out, "%c%c%c", p[0] > 128 ? 'r' : '-', p[1] > 128 ? 'g' : '-', p[2] > 128 ? 'b' : '-');
    CGContextRelease(c);
    return out;
}

int main(void)
{
    @autoreleasepool {
        CAContext *ctx = [CAContext contextWithCGSConnection:1 options:@{kCAContextCIFilterBehavior : @"ignore"}];
        printf("context id given: %s, listed: %s\n", ctx.contextId ? "yes" : "no",
               [[CAContext allContexts] containsObject:ctx] ? "yes" : "no");
        CAContext *other = [CAContext remoteContextWithOptions:@{}];
        printf("ids differ: %s\n", other.contextId != ctx.contextId ? "yes" : "no");

        /* the shown tree: 20 x 10 red, its top-left corner at its position */
        CALayer *tree = [CALayer layer];
        tree.bounds = CGRectMake(0, 0, 20, 10);
        tree.anchorPoint = CGPointMake(0, 1);
        tree.backgroundColor = rgb(1, 0, 0);
        CALayer *dot = [CALayer layer];   /* a blue sublayer at its left */
        dot.frame = CGRectMake(0, 0, 5, 10);
        dot.backgroundColor = rgb(0, 0, 1);
        [tree addSublayer:dot];
        ctx.layer = tree;
        printf("layer kept: %s\n", ctx.layer == tree ? "yes" : "no");

        CALayer *root = [CALayer layer];
        root.frame = CGRectMake(0, 0, W, H);
        CALayerHost *host = [CALayerHost new];
        host.position = CGPointMake(10, 40);   /* the tree's top-left at (10, 40); set before it joins */
        [root addSublayer:host];                /* the tree, so it doesn't animate there */
        host.contextId = ctx.contextId;
        printf("host id kept: %s\n", host.contextId == ctx.contextId ? "yes" : "no");
        spin();
        printf("shown: inside %s,", at(root, 25, 35));   /* (one at a time: at() reuses its buffer) */
        printf(" its blue part %s,", at(root, 12, 35));
        printf(" below it %s,", at(root, 25, 25));
        printf(" right of it %s\n", at(root, 35, 35));

        tree.backgroundColor = rgb(0, 1, 0);   /* followed */
        spin();
        printf("after a change: %s\n", at(root, 25, 35));

        tree.bounds = CGRectMake(0, 0, 40, 10);   /* grown */
        spin();
        printf("grown: %s\n", at(root, 45, 35));

        [ctx invalidate];
        spin();
        printf("after invalidate: %s, valid %s\n", at(root, 25, 35), ctx.valid ? "yes" : "no");

        CALayerHost *none = [CALayerHost new];
        none.contextId = 12345;   /* nobody's */
        [root addSublayer:none];
        spin();
        printf("unknown id shows nothing: %s\n", at(root, 1, 1));
        none.contextId = 0;
    }
    return 0;
}
