/* SPDX-License-Identifier: GPL-3.0-or-later
 * What the Stats system monitor's official download calls in AppKit
 * besides (freemac 1.271, Ferry 0.94.0). Written from Apple's public
 * documentation and from Stats' own open-source code, which shows how it
 * uses each call; no Apple code was read. Built without ARC. */
#import "AInternal.h"

/* ---- drawing on a thread of its own ---------------------------------------------------- *
 * A Mac may draw such a view off the main thread; Ferry draws every view on
 * the main thread, which is always allowed, so the flag is only kept. */

static char concurrent_key;

@implementation NSView (FerryConcurrentDrawing)
- (BOOL)canDrawConcurrently { return [objc_getAssociatedObject(self, &concurrent_key) boolValue]; }
- (void)setCanDrawConcurrently:(BOOL)flag
{
    objc_setAssociatedObject(self, &concurrent_key, flag ? [NSNumber numberWithBool:YES] : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* ---- an attributed string drawn in a rectangle ------------------------------------------ */

@implementation NSAttributedString (FerryDrawWithRect)
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options
{
    /* without NSStringDrawingUsesLineFragmentOrigin, a Mac draws one line
     * with the rectangle's origin on its baseline; drawing in the rectangle
     * looks the same for a single line */
    (void)options;
    [self drawInRect:rect];
}
@end

/* ---- a bitmap in another colour space --------------------------------------------------- *
 * Ferry keeps a bitmap's pixels as device RGB and draws them as sRGB, so a
 * converted bitmap is a copy of the same pixels. */

@implementation NSBitmapImageRep (FerryColorSpaceConversion)
- (NSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:(NSColorSpace *)targetSpace
                                             renderingIntent:(NSColorRenderingIntent)renderingIntent
{
    (void)renderingIntent;
    if (!targetSpace)
        return nil;
    CGImageRef image = [self CGImage];
    if (!image)
        return nil;
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
    [rep setSize:[self size]];
    return rep;
}
- (NSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:(NSColorSpace *)newSpace
{
    return [self bitmapImageRepByConvertingToColorSpace:newSpace renderingIntent:NSColorRenderingIntentDefault];
}
@end

/* ---- following the mouse until the block says stop -------------------------------------- */

@implementation NSEvent (FerryTrackEvents)
+ (void)trackEventsMatchingMask:(NSEventMask)mask timeout:(NSTimeInterval)timeout mode:(NSRunLoopMode)mode
                        handler:(void (^)(NSEvent *event, BOOL *stop))trackingHandler
{
    if (!trackingHandler)
        return;
    NSDate *deadline = timeout > 0 && timeout < 1e9 ? [NSDate dateWithTimeIntervalSinceNow:timeout]
                                                    : [NSDate distantFuture];
    BOOL stop = NO;
    while (!stop) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSEvent *event = [NSApp nextEventMatchingMask:mask untilDate:deadline
                                               inMode:mode ?: NSEventTrackingRunLoopMode dequeue:YES];
        trackingHandler(event, &stop);
        if (!event)
            stop = YES;
        [pool drain];
    }
}
@end
