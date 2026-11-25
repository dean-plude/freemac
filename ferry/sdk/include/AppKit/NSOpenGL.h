/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: AppKit's OpenGL classes (freemac 1.235, Ferry 0.59.0):
 * NSOpenGLPixelFormat and NSOpenGLContext, which draws into a view.
 * Written for freemac from Apple's public AppKit reference; not Apple's
 * header. Implemented in ferry/appkit/NSOpenGL.m. */
#ifndef _FERRY_APPKIT_NSOPENGL_H_
#define _FERRY_APPKIT_NSOPENGL_H_
#import <Foundation/Foundation.h>
#include <OpenGL/OpenGL.h>

@class NSView;

typedef uint32_t NSOpenGLPixelFormatAttribute;
enum {
    NSOpenGLPFAAllRenderers = kCGLPFAAllRenderers,
    NSOpenGLPFATripleBuffer = kCGLPFATripleBuffer,
    NSOpenGLPFADoubleBuffer = kCGLPFADoubleBuffer,
    NSOpenGLPFAStereo = kCGLPFAStereo,
    NSOpenGLPFAAuxBuffers = kCGLPFAAuxBuffers,
    NSOpenGLPFAColorSize = kCGLPFAColorSize,
    NSOpenGLPFAAlphaSize = kCGLPFAAlphaSize,
    NSOpenGLPFADepthSize = kCGLPFADepthSize,
    NSOpenGLPFAStencilSize = kCGLPFAStencilSize,
    NSOpenGLPFAAccumSize = kCGLPFAAccumSize,
    NSOpenGLPFAMinimumPolicy = kCGLPFAMinimumPolicy,
    NSOpenGLPFAMaximumPolicy = kCGLPFAMaximumPolicy,
    NSOpenGLPFAOffScreen = kCGLPFAOffScreen,
    NSOpenGLPFAFullScreen = kCGLPFAFullScreen,
    NSOpenGLPFASampleBuffers = kCGLPFASampleBuffers,
    NSOpenGLPFASamples = kCGLPFASamples,
    NSOpenGLPFAAuxDepthStencil = kCGLPFAAuxDepthStencil,
    NSOpenGLPFAColorFloat = kCGLPFAColorFloat,
    NSOpenGLPFAMultisample = kCGLPFAMultisample,
    NSOpenGLPFASupersample = kCGLPFASupersample,
    NSOpenGLPFASampleAlpha = kCGLPFASampleAlpha,
    NSOpenGLPFARendererID = kCGLPFARendererID,
    NSOpenGLPFASingleRenderer = kCGLPFASingleRenderer,
    NSOpenGLPFANoRecovery = kCGLPFANoRecovery,
    NSOpenGLPFAAccelerated = kCGLPFAAccelerated,
    NSOpenGLPFAClosestPolicy = kCGLPFAClosestPolicy,
    NSOpenGLPFARobust = kCGLPFARobust,
    NSOpenGLPFABackingStore = kCGLPFABackingStore,
    NSOpenGLPFAMPSafe = kCGLPFAMPSafe,
    NSOpenGLPFAWindow = kCGLPFAWindow,
    NSOpenGLPFAMultiScreen = kCGLPFAMultiScreen,
    NSOpenGLPFACompliant = kCGLPFACompliant,
    NSOpenGLPFAScreenMask = kCGLPFADisplayMask,
    NSOpenGLPFAPixelBuffer = kCGLPFAPBuffer,
    NSOpenGLPFARemotePixelBuffer = kCGLPFARemotePBuffer,
    NSOpenGLPFAAllowOfflineRenderers = kCGLPFAAllowOfflineRenderers,
    NSOpenGLPFAAcceleratedCompute = kCGLPFAAcceleratedCompute,
    NSOpenGLPFAOpenGLProfile = kCGLPFAOpenGLProfile,
    NSOpenGLPFAVirtualScreenCount = kCGLPFAVirtualScreenCount,
};
enum {
    NSOpenGLProfileVersionLegacy = 0x1000,
    NSOpenGLProfileVersion3_2Core = 0x3200,
    NSOpenGLProfileVersion4_1Core = 0x4100,
};

typedef NS_ENUM(NSInteger, NSOpenGLContextParameter) {
    NSOpenGLContextParameterSwapInterval = kCGLCPSwapInterval,
    NSOpenGLContextParameterSurfaceOrder = kCGLCPSurfaceOrder,
    NSOpenGLContextParameterSurfaceOpacity = kCGLCPSurfaceOpacity,
    NSOpenGLContextParameterSurfaceBackingSize = kCGLCPSurfaceBackingSize,
    NSOpenGLContextParameterReclaimResources = kCGLCPReclaimResources,
    NSOpenGLContextParameterCurrentRendererID = kCGLCPCurrentRendererID,
    NSOpenGLContextParameterGPUVertexProcessing = kCGLCPGPUVertexProcessing,
    NSOpenGLContextParameterGPUFragmentProcessing = kCGLCPGPUFragmentProcessing,
    NSOpenGLContextParameterHasDrawable = kCGLCPHasDrawable,
    NSOpenGLContextParameterMPSwapsInFlight = kCGLCPMPSwapsInFlight,
    NSOpenGLContextParameterSwapRectangle = kCGLCPSwapRectangle,
    NSOpenGLContextParameterSwapRectangleEnable = kCGLCESwapRectangle,
    NSOpenGLContextParameterRasterizationEnable = kCGLCERasterization,
    NSOpenGLContextParameterStateValidation = kCGLCEStateValidation,
    NSOpenGLContextParameterSurfaceSurfaceVolatile = kCGLCPSurfaceSurfaceVolatile,
};
/* the older names */
#define NSOpenGLCPSwapInterval NSOpenGLContextParameterSwapInterval
#define NSOpenGLCPSurfaceOrder NSOpenGLContextParameterSurfaceOrder
#define NSOpenGLCPSurfaceOpacity NSOpenGLContextParameterSurfaceOpacity
#define NSOpenGLCPSurfaceBackingSize NSOpenGLContextParameterSurfaceBackingSize
#define NSOpenGLCPHasDrawable NSOpenGLContextParameterHasDrawable
#define NSOpenGLCPCurrentRendererID NSOpenGLContextParameterCurrentRendererID
#define NSOpenGLCPSwapRectangle NSOpenGLContextParameterSwapRectangle
#define NSOpenGLCPSwapRectangleEnable NSOpenGLContextParameterSwapRectangleEnable

@interface NSOpenGLPixelFormat : NSObject <NSCoding>
- (instancetype)initWithAttributes:(const NSOpenGLPixelFormatAttribute *)attribs;
- (instancetype)initWithCGLPixelFormatObj:(CGLPixelFormatObj)format;
- (instancetype)initWithData:(NSData *)attribs;
- (void)getValues:(GLint *)vals forAttribute:(NSOpenGLPixelFormatAttribute)attrib
 forVirtualScreen:(GLint)screen;
@property (readonly) GLint numberOfVirtualScreens;
@property (readonly) CGLPixelFormatObj CGLPixelFormatObj;
@end

@interface NSOpenGLContext : NSObject <NSLocking>
- (instancetype)initWithFormat:(NSOpenGLPixelFormat *)format shareContext:(NSOpenGLContext *)share;
- (instancetype)initWithCGLContextObj:(CGLContextObj)context;
@property (readonly, strong) NSOpenGLPixelFormat *pixelFormat;
/* the view it draws into; set on any thread, read on the main one */
@property (weak) NSView *view;
- (void)setView:(NSView *)view;
- (void)update;
- (void)clearDrawable;
- (void)setOffScreen:(void *)baseaddr width:(GLsizei)width height:(GLsizei)height rowbytes:(GLint)rowbytes;
- (void)setFullScreen;
- (void)flushBuffer;
- (void)makeCurrentContext;
+ (void)clearCurrentContext;
+ (NSOpenGLContext *)currentContext;
- (void)copyAttributesFromContext:(NSOpenGLContext *)context withMask:(GLbitfield)mask;
- (void)setValues:(const GLint *)vals forParameter:(NSOpenGLContextParameter)param;
- (void)getValues:(GLint *)vals forParameter:(NSOpenGLContextParameter)param;
@property GLint currentVirtualScreen;
@property (readonly) CGLContextObj CGLContextObj;
- (void)lock;
- (void)unlock;
@end

#endif
