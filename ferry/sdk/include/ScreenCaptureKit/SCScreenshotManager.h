/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: ScreenCaptureKit's single pictures (freemac 1.238, Ferry
 * 0.62.0). Written for freemac from Apple's public ScreenCaptureKit
 * reference; not Apple's header. One frame of what a filter shows, as a
 * stream with that configuration would make it; the completion handler is
 * called on a queue of ScreenCaptureKit's own. */
#import <ScreenCaptureKit/SCStream.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCScreenshotManager : NSObject
+ (void)captureSampleBufferWithFilter:(SCContentFilter *)contentFilter
                        configuration:(SCStreamConfiguration *)config
                    completionHandler:(nullable void (^)(CMSampleBufferRef _Nullable sampleBuffer,
                                                         NSError *_Nullable error))completionHandler;
+ (void)captureImageWithFilter:(SCContentFilter *)contentFilter
                 configuration:(SCStreamConfiguration *)config
             completionHandler:(nullable void (^)(CGImageRef _Nullable image,
                                                  NSError *_Nullable error))completionHandler;
@end

NS_ASSUME_NONNULL_END
