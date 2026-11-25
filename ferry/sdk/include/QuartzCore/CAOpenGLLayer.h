/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CAOpenGLLayer (freemac 1.235, Ferry 0.59.0), a layer whose
 * contents are drawn with OpenGL. Written for freemac from Apple's public
 * Core Animation reference; not Apple's header. Implemented in
 * ferry/quartzcore/CAOpenGLLayer.m. */
#ifndef _FERRY_QUARTZCORE_CAOPENGLLAYER_H_
#define _FERRY_QUARTZCORE_CAOPENGLLAYER_H_
#import <QuartzCore/QuartzCore.h>
#include <OpenGL/OpenGL.h>
#include <CoreVideo/CoreVideo.h>

@interface CAOpenGLLayer : CALayer
/* drawn again each display refresh, when canDrawInCGLContext: says so */
@property (getter=isAsynchronous) BOOL asynchronous;
@property CGColorSpaceRef colorspace;
@property BOOL wantsExtendedDynamicRangeContent;

- (BOOL)canDrawInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf
               forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts;
- (void)drawInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf
            forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts;
- (CGLPixelFormatObj)copyCGLPixelFormatForDisplayMask:(uint32_t)mask;
- (void)releaseCGLPixelFormat:(CGLPixelFormatObj)pf;
- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pf;
- (void)releaseCGLContext:(CGLContextObj)ctx;
@end

/* the part of a layer seen through its superlayers' bounds (CAScrollLayer.h) */
@interface CALayer (CALayerScrolling)
- (void)scrollPoint:(CGPoint)p;
- (void)scrollRectToVisible:(CGRect)r;
@property (readonly) CGRect visibleRect;
@end

#endif
