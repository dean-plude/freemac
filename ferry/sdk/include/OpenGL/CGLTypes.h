/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Core OpenGL (CGL) types and constants (freemac 1.235,
 * Ferry 0.59.0), with the values Apple's public CGL reference gives them.
 * Written for freemac; not Apple's header. */
#ifndef _FERRY_OPENGL_CGLTYPES_H_
#define _FERRY_OPENGL_CGLTYPES_H_
#include <_ferry.h>
#include <OpenGL/gltypes.h>

__FERRY_BEGIN

typedef struct _CGLContextObject *CGLContextObj;
typedef struct _CGLPixelFormatObject *CGLPixelFormatObj;
typedef struct _CGLRendererInfoObject *CGLRendererInfoObj;
typedef struct _CGLPBufferObject *CGLPBufferObj;
typedef struct _CGLShareGroupObject *CGLShareGroupObj;

typedef enum _CGLPixelFormatAttribute {
    kCGLPFAAllRenderers = 1,
    kCGLPFATripleBuffer = 3,
    kCGLPFADoubleBuffer = 5,
    kCGLPFAStereo = 6,
    kCGLPFAAuxBuffers = 7,
    kCGLPFAColorSize = 8,
    kCGLPFAAlphaSize = 11,
    kCGLPFADepthSize = 12,
    kCGLPFAStencilSize = 13,
    kCGLPFAAccumSize = 14,
    kCGLPFAMinimumPolicy = 51,
    kCGLPFAMaximumPolicy = 52,
    kCGLPFAOffScreen = 53,
    kCGLPFAFullScreen = 54,
    kCGLPFASampleBuffers = 55,
    kCGLPFASamples = 56,
    kCGLPFAAuxDepthStencil = 57,
    kCGLPFAColorFloat = 58,
    kCGLPFAMultisample = 59,
    kCGLPFASupersample = 60,
    kCGLPFASampleAlpha = 61,
    kCGLPFARendererID = 70,
    kCGLPFASingleRenderer = 71,
    kCGLPFANoRecovery = 72,
    kCGLPFAAccelerated = 73,
    kCGLPFAClosestPolicy = 74,
    kCGLPFARobust = 75,
    kCGLPFABackingStore = 76,
    kCGLPFAMPSafe = 78,
    kCGLPFAWindow = 80,
    kCGLPFAMultiScreen = 81,
    kCGLPFACompliant = 83,
    kCGLPFADisplayMask = 84,
    kCGLPFAPBuffer = 90,
    kCGLPFARemotePBuffer = 91,
    kCGLPFAAllowOfflineRenderers = 96,
    kCGLPFAAcceleratedCompute = 97,
    kCGLPFAOpenGLProfile = 99,
    kCGLPFASupportsAutomaticGraphicsSwitching = 101,
    kCGLPFAVirtualScreenCount = 128,
    kCGLPFABackingVolatile = 77,
} CGLPixelFormatAttribute;

typedef enum _CGLRendererProperty {
    kCGLRPOffScreen = 53,
    kCGLRPFullScreen = 54,
    kCGLRPRendererID = 70,
    kCGLRPAccelerated = 73,
    kCGLRPRobust = 75,
    kCGLRPBackingStore = 76,
    kCGLRPMPSafe = 78,
    kCGLRPWindow = 80,
    kCGLRPMultiScreen = 81,
    kCGLRPCompliant = 83,
    kCGLRPDisplayMask = 84,
    kCGLRPBufferModes = 100,
    kCGLRPColorModes = 103,
    kCGLRPAccumModes = 104,
    kCGLRPDepthModes = 105,
    kCGLRPStencilModes = 106,
    kCGLRPMaxAuxBuffers = 107,
    kCGLRPMaxSampleBuffers = 108,
    kCGLRPMaxSamples = 109,
    kCGLRPSampleModes = 110,
    kCGLRPSampleAlpha = 111,
    kCGLRPVideoMemory = 120,
    kCGLRPTextureMemory = 121,
    kCGLRPGPUVertProcCapable = 122,
    kCGLRPGPUFragProcCapable = 123,
    kCGLRPRendererCount = 128,
    kCGLRPOnline = 129,
    kCGLRPAcceleratedCompute = 130,
    kCGLRPVideoMemoryMegabytes = 131,
    kCGLRPTextureMemoryMegabytes = 132,
    kCGLRPMajorGLVersion = 133,
} CGLRendererProperty;

typedef enum _CGLContextEnable {
    kCGLCESwapRectangle = 201,
    kCGLCESwapLimit = 203,
    kCGLCERasterization = 221,
    kCGLCEStateValidation = 301,
    kCGLCESurfaceBackingSize = 305,
    kCGLCEDisplayListOptimization = 307,
    kCGLCEMPEngine = 313,
    kCGLCECrashOnRemovedFunctions = 316,
} CGLContextEnable;

typedef enum _CGLContextParameter {
    kCGLCPSwapRectangle = 200,
    kCGLCPSwapInterval = 222,
    kCGLCPDispatchTableSize = 224,
    kCGLCPClientStorage = 226,
    kCGLCPSurfaceTexture = 228,
    kCGLCPSurfaceOrder = 235,
    kCGLCPSurfaceOpacity = 236,
    kCGLCPSurfaceBackingSize = 304,
    kCGLCPSurfaceSurfaceVolatile = 306,
    kCGLCPReclaimResources = 308,
    kCGLCPCurrentRendererID = 309,
    kCGLCPGPUVertexProcessing = 310,
    kCGLCPGPUFragmentProcessing = 311,
    kCGLCPHasDrawable = 314,
    kCGLCPMPSwapsInFlight = 315,
    kCGLCPGPURestartStatus = 317,
    kCGLCPAbortOnGPURestartStatusBlacklisted = 318,
    kCGLCPSupportGPURestart = 319,
    kCGLCPSupportSeparateAddressSpace = 320,
    kCGLCPContextPriorityRequest = 608,
} CGLContextParameter;

typedef enum _CGLGlobalOption {
    kCGLGOFormatCacheSize = 501,
    kCGLGOClearFormatCache = 502,
    kCGLGORetainRenderers = 503,
    kCGLGOUseBuildCache = 506,
    kCGLGOResetLibrary = 504,
    kCGLGOUseErrorHandler = 505,
} CGLGlobalOption;

typedef enum _CGLOpenGLProfile {
    kCGLOGLPVersion_Legacy = 0x1000,
    kCGLOGLPVersion_3_2_Core = 0x3200,
    kCGLOGLPVersion_GL3_Core = 0x3200,
    kCGLOGLPVersion_GL4_Core = 0x4100,
} CGLOpenGLProfile;

typedef enum _CGLGPURestartStatus {
    kCGLCPGPURestartStatusNone = 0,
    kCGLCPGPURestartStatusCaused = 1,
    kCGLCPGPURestartStatusBlacklisted = 2,
} CGLGPURestartStatus;

/* the same type AppKit's header brings, under the same guard */
#ifndef _FERRY_CGLERROR_DEFINED
#define _FERRY_CGLERROR_DEFINED
typedef enum _CGLError {
    kCGLNoError = 0,
    kCGLBadAttribute = 10000,
    kCGLBadProperty = 10001,
    kCGLBadPixelFormat = 10002,
    kCGLBadRendererInfo = 10003,
    kCGLBadContext = 10004,
    kCGLBadDrawable = 10005,
    kCGLBadDisplay = 10006,
    kCGLBadState = 10007,
    kCGLBadValue = 10008,
    kCGLBadMatch = 10009,
    kCGLBadEnumeration = 10010,
    kCGLBadOffScreen = 10011,
    kCGLBadFullScreen = 10012,
    kCGLBadWindow = 10013,
    kCGLBadAddress = 10014,
    kCGLBadCodeModule = 10015,
    kCGLBadAlloc = 10016,
    kCGLBadConnection = 10017,
} CGLError;
#endif

/* buffer, colour and depth modes reported by CGLDescribeRenderer */
#define kCGLMonoscopicBit 0x00000001
#define kCGLStereoscopicBit 0x00000002
#define kCGLSingleBufferBit 0x00000004
#define kCGLDoubleBufferBit 0x00000008
#define kCGLTripleBufferBit 0x00000010
#define kCGL0Bit 0x00000001
#define kCGL8Bit 0x00000008
#define kCGL16Bit 0x00000040
#define kCGL24Bit 0x00000100
#define kCGL32Bit 0x00000200
#define kCGLRGB888Bit 0x00004000
#define kCGLARGB8888Bit 0x00008000
#define kCGLSupersampleBit 0x00000001
#define kCGLMultisampleBit 0x00000002

__FERRY_END

#endif
