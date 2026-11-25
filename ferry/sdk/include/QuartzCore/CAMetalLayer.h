/* SPDX-License-Identifier: GPL-3.0-or-later
 * CAMetalLayer, from Apple's public documentation. With no Metal device
 * (Metal/Metal.h) the layer is an ordinary layer that keeps its settings,
 * and nextDrawable answers nil, as when a Mac has no drawable to give. */
#ifndef FERRY_CAMETALLAYER_H
#define FERRY_CAMETALLAYER_H
#import <QuartzCore/CALayer.h>
#import <Metal/Metal.h>

@class CAMetalLayer;
@protocol CAMetalDrawable <MTLDrawable>
@property (readonly) id<MTLTexture> texture;
@property (readonly) CAMetalLayer *layer;
@end

@interface CAMetalLayer : CALayer
@property (retain) id<MTLDevice> device;
@property (readonly) id<MTLDevice> preferredDevice;
@property MTLPixelFormat pixelFormat;
@property BOOL framebufferOnly;
@property CGSize drawableSize;
@property NSUInteger maximumDrawableCount;
@property BOOL presentsWithTransaction;
@property CGColorSpaceRef colorspace;
@property BOOL wantsExtendedDynamicRangeContent;
@property BOOL displaySyncEnabled;
@property BOOL allowsNextDrawableTimeout;
- (id<CAMetalDrawable>)nextDrawable;
@end

#endif
