/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * What the Stats system monitor's official download calls in AppKit
 * besides (freemac 1.271), written from Apple's public documentation; not
 * Apple's header. Implemented in appkit/AppKitStats.m and NSWorkspace.m.
 * Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_STATS_H_
#define _FERRY_APPKIT_STATS_H_

@interface NSView (FerryConcurrentDrawing)
/* whether the view may draw on a thread of its own; Ferry draws every view
 * on the main thread, so this is only kept */
@property BOOL canDrawConcurrently;
@end

@interface NSAttributedString (FerryDrawWithRect)
- (void)drawWithRect:(NSRect)rect options:(NSStringDrawingOptions)options;
@end

typedef NS_ENUM(NSInteger, NSColorRenderingIntent) {
    NSColorRenderingIntentDefault,
    NSColorRenderingIntentAbsoluteColorimetric,
    NSColorRenderingIntentRelativeColorimetric,
    NSColorRenderingIntentPerceptual,
    NSColorRenderingIntentSaturation,
};

@interface NSBitmapImageRep (FerryColorSpaceConversion)
/* a copy in the given colour space; Ferry keeps every bitmap as device RGB */
- (NSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:(NSColorSpace *)targetSpace
                                             renderingIntent:(NSColorRenderingIntent)renderingIntent;
- (NSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:(NSColorSpace *)newSpace;
@end

@interface NSEvent (FerryTrackEvents)
/* hands each matching event to the block until it sets *stop, or nil once
 * the timeout passes */
+ (void)trackEventsMatchingMask:(NSEventMask)mask timeout:(NSTimeInterval)timeout mode:(NSRunLoopMode)mode
                        handler:(void (^)(NSEvent *event, BOOL *stop))trackingHandler;
@end

@interface NSWorkspace (FerryEject)
/* ejects a disk with the desktop's own "gio mount -e" */
- (BOOL)unmountAndEjectDeviceAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)unmountAndEjectDeviceAtPath:(NSString *)path;
@end

#endif
