/* SPDX-License-Identifier: GPL-3.0-or-later
 * Metal: drawables, from Apple's public Metal documentation. Metal/Metal.h
 * includes it; QuartzCore's CAMetalLayer.h includes only this, as on a Mac. */
/* Ferry submodule: MTLDrawable (freemac 1.262), so that a header that brings in
 * only this one (CAMetalLayer.h) doesn't bring in all of Metal.h with it. */
#ifndef FERRY_MTLDRAWABLE_H
#define FERRY_MTLDRAWABLE_H
#import <Foundation/Foundation.h>

@protocol MTLDrawable;
typedef void (^MTLDrawablePresentedHandler)(id<MTLDrawable>);
@protocol MTLDrawable <NSObject>
@property (readonly) CFTimeInterval presentedTime;
@property (readonly) NSUInteger drawableID;
- (void)present;
- (void)presentAtTime:(CFTimeInterval)presentationTime;
- (void)presentAfterMinimumDuration:(CFTimeInterval)duration;
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)block;
@end

#endif
