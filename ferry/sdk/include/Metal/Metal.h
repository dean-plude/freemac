/* SPDX-License-Identifier: GPL-3.0-or-later
 * Metal, from Apple's public documentation, as far as programs that check
 * for it need. Ferry has no Metal GPU: MTLCreateSystemDefaultDevice answers
 * nil and MTLCopyAllDevices an empty list, as on a Mac whose GPU doesn't
 * support Metal, so programs take their OpenGL or software path. */
#ifndef FERRY_METAL_H
#define FERRY_METAL_H
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, MTLPixelFormat) {
    MTLPixelFormatInvalid = 0,
    MTLPixelFormatA8Unorm = 1,
    MTLPixelFormatR8Unorm = 10,
    MTLPixelFormatR16Float = 25,
    MTLPixelFormatRG8Unorm = 30,
    MTLPixelFormatRGBA8Unorm = 70,
    MTLPixelFormatRGBA8Unorm_sRGB = 71,
    MTLPixelFormatBGRA8Unorm = 80,
    MTLPixelFormatBGRA8Unorm_sRGB = 81,
    MTLPixelFormatRGB10A2Unorm = 90,
    MTLPixelFormatBGR10A2Unorm = 94,
    MTLPixelFormatRGBA16Float = 115,
    MTLPixelFormatRGBA32Float = 125,
    MTLPixelFormatDepth32Float = 252,
    MTLPixelFormatStencil8 = 253,
    MTLPixelFormatDepth24Unorm_Stencil8 = 255,
    MTLPixelFormatDepth32Float_Stencil8 = 260,
};

typedef struct { NSUInteger width, height, depth; } MTLSize;
typedef struct { NSUInteger x, y, z; } MTLOrigin;
typedef struct { MTLOrigin origin; MTLSize size; } MTLRegion;
static inline MTLSize MTLSizeMake(NSUInteger w, NSUInteger h, NSUInteger d) { MTLSize s = {w, h, d}; return s; }
static inline MTLOrigin MTLOriginMake(NSUInteger x, NSUInteger y, NSUInteger z) { MTLOrigin o = {x, y, z}; return o; }
static inline MTLRegion MTLRegionMake2D(NSUInteger x, NSUInteger y, NSUInteger w, NSUInteger h)
{ MTLRegion r = {{x, y, 0}, {w, h, 1}}; return r; }

@protocol MTLDevice;
@protocol MTLResource <NSObject>
@property (readonly) id<MTLDevice> device;
@property (copy) NSString *label;
@end
@protocol MTLTexture <MTLResource>
@property (readonly) NSUInteger width;
@property (readonly) NSUInteger height;
@property (readonly) MTLPixelFormat pixelFormat;
@end
@protocol MTLDrawable <NSObject>
- (void)present;
@end
@protocol MTLCommandBuffer <NSObject>
- (void)commit;
- (void)presentDrawable:(id<MTLDrawable>)drawable;
- (void)waitUntilCompleted;
@end
@protocol MTLCommandQueue <NSObject>
- (id<MTLCommandBuffer>)commandBuffer;
@end
@protocol MTLDevice <NSObject>
@property (readonly) NSString *name;
@property (readonly) uint64_t registryID;
@property (readonly, getter=isLowPower) BOOL lowPower;
@property (readonly, getter=isHeadless) BOOL headless;
- (id<MTLCommandQueue>)newCommandQueue;
@end

id<MTLDevice> MTLCreateSystemDefaultDevice(void);
NSArray<id<MTLDevice>> *MTLCopyAllDevices(void);

#endif
