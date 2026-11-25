/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSOpenGLView (freemac 1.235, Ferry 0.59.0), a view drawn
 * with OpenGL, and the backing resolution of a view's OpenGL surface.
 * Written for freemac from Apple's public AppKit reference; not Apple's
 * header. Implemented in ferry/appkit/NSOpenGL.m. */
#ifndef _FERRY_APPKIT_NSOPENGLVIEW_H_
#define _FERRY_APPKIT_NSOPENGLVIEW_H_
#import <AppKit/NSOpenGL.h>

@interface NSOpenGLView : NSView
+ (NSOpenGLPixelFormat *)defaultPixelFormat;
- (instancetype)initWithFrame:(NSRect)frame pixelFormat:(NSOpenGLPixelFormat *)format;
@property (strong) NSOpenGLContext *openGLContext;
@property (strong) NSOpenGLPixelFormat *pixelFormat;
- (void)clearGLContext;
- (void)update;
- (void)reshape;
- (void)prepareOpenGL;
@end

@interface NSView (NSOpenGLSurfaceResolution)
/* the surface of an OpenGL context drawing into the view has one pixel
 * for each of the view's backing pixels, not each of its points */
@property BOOL wantsBestResolutionOpenGLSurface;
@property BOOL wantsExtendedDynamicRangeOpenGLSurface;
@end

#endif
