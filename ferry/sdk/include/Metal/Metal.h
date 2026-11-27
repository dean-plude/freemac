/* SPDX-License-Identifier: GPL-3.0-or-later
 * Metal for Ferry (freemac 1.NEXT), from Apple's public Metal documentation.
 * Ferry's Metal draws on the processor: shaders are compiled to ordinary
 * code by ferry-mslc (ferry/metal), and Metal.framework rasterizes and runs
 * them. The names, numbers and structures here are the ones Apple's
 * documentation gives, so programs built for a Mac pass the same values. */
#ifndef FERRY_METAL_H
#define FERRY_METAL_H
#import <Foundation/Foundation.h>
#include <stdint.h>

#ifndef MTL_EXTERN
#ifdef __cplusplus
#define MTL_EXTERN extern "C"
#else
#define MTL_EXTERN extern
#endif
#endif

/* ---- pixel formats --------------------------------------------------------------- */
#import <Metal/MTLPixelFormat.h>
#import <Metal/MTLDrawable.h>

/* ---- plain structures ------------------------------------------------------------ */
typedef struct { NSUInteger width, height, depth; } MTLSize;
typedef struct { NSUInteger x, y, z; } MTLOrigin;
typedef struct { MTLOrigin origin; MTLSize size; } MTLRegion;
typedef struct { NSUInteger location, length; } MTLRange_;
typedef struct { double red, green, blue, alpha; } MTLClearColor;
typedef struct { double originX, originY, width, height, znear, zfar; } MTLViewport;
typedef struct { NSUInteger x, y, width, height; } MTLScissorRect;
typedef struct { float x, y; } MTLSamplePosition;
typedef struct { uint32_t vertexCount, instanceCount, vertexStart, baseInstance; } MTLDrawPrimitivesIndirectArguments;
typedef struct { uint32_t indexCount, instanceCount, indexStart; int32_t baseVertex; uint32_t baseInstance; }
    MTLDrawIndexedPrimitivesIndirectArguments;
typedef struct { uint32_t threadgroupsPerGrid[3]; } MTLDispatchThreadgroupsIndirectArguments;
typedef struct { uint64_t location, length; } MTLResourceID_;
typedef struct { uint64_t _impl; } MTLResourceID;
typedef struct { NSUInteger width, height, depth; } MTLSizeAndAlign_;
typedef struct { NSUInteger size, align; } MTLSizeAndAlign;

static inline MTLSize MTLSizeMake(NSUInteger w, NSUInteger h, NSUInteger d) { MTLSize s = {w, h, d}; return s; }
static inline MTLOrigin MTLOriginMake(NSUInteger x, NSUInteger y, NSUInteger z) { MTLOrigin o = {x, y, z}; return o; }
static inline MTLRegion MTLRegionMake1D(NSUInteger x, NSUInteger w) { MTLRegion r = {{x, 0, 0}, {w, 1, 1}}; return r; }
static inline MTLRegion MTLRegionMake2D(NSUInteger x, NSUInteger y, NSUInteger w, NSUInteger h)
{ MTLRegion r = {{x, y, 0}, {w, h, 1}}; return r; }
static inline MTLRegion MTLRegionMake3D(NSUInteger x, NSUInteger y, NSUInteger z, NSUInteger w, NSUInteger h, NSUInteger d)
{ MTLRegion r = {{x, y, z}, {w, h, d}}; return r; }
static inline MTLClearColor MTLClearColorMake(double r, double g, double b, double a)
{ MTLClearColor c = {r, g, b, a}; return c; }
static inline MTLSamplePosition MTLSamplePositionMake(float x, float y) { MTLSamplePosition p = {x, y}; return p; }

/* ---- enumerations ---------------------------------------------------------------- */
typedef NS_ENUM(NSUInteger, MTLPrimitiveType) {
    MTLPrimitiveTypePoint = 0, MTLPrimitiveTypeLine = 1, MTLPrimitiveTypeLineStrip = 2,
    MTLPrimitiveTypeTriangle = 3, MTLPrimitiveTypeTriangleStrip = 4,
};
typedef NS_ENUM(NSUInteger, MTLPrimitiveTopologyClass) {
    MTLPrimitiveTopologyClassUnspecified = 0, MTLPrimitiveTopologyClassPoint = 1,
    MTLPrimitiveTopologyClassLine = 2, MTLPrimitiveTopologyClassTriangle = 3,
};
typedef NS_ENUM(NSUInteger, MTLIndexType) { MTLIndexTypeUInt16 = 0, MTLIndexTypeUInt32 = 1 };
typedef NS_ENUM(NSUInteger, MTLLoadAction) { MTLLoadActionDontCare = 0, MTLLoadActionLoad = 1, MTLLoadActionClear = 2 };
typedef NS_ENUM(NSUInteger, MTLStoreAction) {
    MTLStoreActionDontCare = 0, MTLStoreActionStore = 1, MTLStoreActionMultisampleResolve = 2,
    MTLStoreActionStoreAndMultisampleResolve = 3, MTLStoreActionUnknown = 4, MTLStoreActionCustomSampleDepthStore = 5,
};
typedef NS_OPTIONS(NSUInteger, MTLStoreActionOptions) {
    MTLStoreActionOptionNone = 0, MTLStoreActionOptionCustomSamplePositions = 1,
};
typedef NS_ENUM(NSUInteger, MTLMultisampleDepthResolveFilter) {
    MTLMultisampleDepthResolveFilterSample0 = 0, MTLMultisampleDepthResolveFilterMin = 1,
    MTLMultisampleDepthResolveFilterMax = 2,
};
typedef NS_ENUM(NSUInteger, MTLMultisampleStencilResolveFilter) {
    MTLMultisampleStencilResolveFilterSample0 = 0, MTLMultisampleStencilResolveFilterDepthResolvedSample = 1,
};
typedef NS_ENUM(NSUInteger, MTLCompareFunction) {
    MTLCompareFunctionNever = 0, MTLCompareFunctionLess = 1, MTLCompareFunctionEqual = 2,
    MTLCompareFunctionLessEqual = 3, MTLCompareFunctionGreater = 4, MTLCompareFunctionNotEqual = 5,
    MTLCompareFunctionGreaterEqual = 6, MTLCompareFunctionAlways = 7,
};
typedef NS_ENUM(NSUInteger, MTLStencilOperation) {
    MTLStencilOperationKeep = 0, MTLStencilOperationZero = 1, MTLStencilOperationReplace = 2,
    MTLStencilOperationIncrementClamp = 3, MTLStencilOperationDecrementClamp = 4, MTLStencilOperationInvert = 5,
    MTLStencilOperationIncrementWrap = 6, MTLStencilOperationDecrementWrap = 7,
};
typedef NS_ENUM(NSUInteger, MTLBlendFactor) {
    MTLBlendFactorZero = 0, MTLBlendFactorOne = 1, MTLBlendFactorSourceColor = 2,
    MTLBlendFactorOneMinusSourceColor = 3, MTLBlendFactorSourceAlpha = 4, MTLBlendFactorOneMinusSourceAlpha = 5,
    MTLBlendFactorDestinationColor = 6, MTLBlendFactorOneMinusDestinationColor = 7,
    MTLBlendFactorDestinationAlpha = 8, MTLBlendFactorOneMinusDestinationAlpha = 9,
    MTLBlendFactorSourceAlphaSaturated = 10, MTLBlendFactorBlendColor = 11, MTLBlendFactorOneMinusBlendColor = 12,
    MTLBlendFactorBlendAlpha = 13, MTLBlendFactorOneMinusBlendAlpha = 14, MTLBlendFactorSource1Color = 15,
    MTLBlendFactorOneMinusSource1Color = 16, MTLBlendFactorSource1Alpha = 17, MTLBlendFactorOneMinusSource1Alpha = 18,
};
typedef NS_ENUM(NSUInteger, MTLBlendOperation) {
    MTLBlendOperationAdd = 0, MTLBlendOperationSubtract = 1, MTLBlendOperationReverseSubtract = 2,
    MTLBlendOperationMin = 3, MTLBlendOperationMax = 4,
};
typedef NS_OPTIONS(NSUInteger, MTLColorWriteMask) {
    MTLColorWriteMaskNone = 0, MTLColorWriteMaskRed = 0x1 << 3, MTLColorWriteMaskGreen = 0x1 << 2,
    MTLColorWriteMaskBlue = 0x1 << 1, MTLColorWriteMaskAlpha = 0x1 << 0, MTLColorWriteMaskAll = 0xf,
};
typedef NS_ENUM(NSUInteger, MTLCullMode) { MTLCullModeNone = 0, MTLCullModeFront = 1, MTLCullModeBack = 2 };
typedef NS_ENUM(NSUInteger, MTLWinding) { MTLWindingClockwise = 0, MTLWindingCounterClockwise = 1 };
typedef NS_ENUM(NSUInteger, MTLDepthClipMode) { MTLDepthClipModeClip = 0, MTLDepthClipModeClamp = 1 };
typedef NS_ENUM(NSUInteger, MTLTriangleFillMode) { MTLTriangleFillModeFill = 0, MTLTriangleFillModeLines = 1 };
typedef NS_ENUM(NSUInteger, MTLVisibilityResultMode) {
    MTLVisibilityResultModeDisabled = 0, MTLVisibilityResultModeBoolean = 1, MTLVisibilityResultModeCounting = 2,
};
typedef NS_ENUM(NSUInteger, MTLVertexFormat) {
    MTLVertexFormatInvalid = 0,
    MTLVertexFormatUChar2 = 1, MTLVertexFormatUChar3 = 2, MTLVertexFormatUChar4 = 3,
    MTLVertexFormatChar2 = 4, MTLVertexFormatChar3 = 5, MTLVertexFormatChar4 = 6,
    MTLVertexFormatUChar2Normalized = 7, MTLVertexFormatUChar3Normalized = 8, MTLVertexFormatUChar4Normalized = 9,
    MTLVertexFormatChar2Normalized = 10, MTLVertexFormatChar3Normalized = 11, MTLVertexFormatChar4Normalized = 12,
    MTLVertexFormatUShort2 = 13, MTLVertexFormatUShort3 = 14, MTLVertexFormatUShort4 = 15,
    MTLVertexFormatShort2 = 16, MTLVertexFormatShort3 = 17, MTLVertexFormatShort4 = 18,
    MTLVertexFormatUShort2Normalized = 19, MTLVertexFormatUShort3Normalized = 20, MTLVertexFormatUShort4Normalized = 21,
    MTLVertexFormatShort2Normalized = 22, MTLVertexFormatShort3Normalized = 23, MTLVertexFormatShort4Normalized = 24,
    MTLVertexFormatHalf2 = 25, MTLVertexFormatHalf3 = 26, MTLVertexFormatHalf4 = 27,
    MTLVertexFormatFloat = 28, MTLVertexFormatFloat2 = 29, MTLVertexFormatFloat3 = 30, MTLVertexFormatFloat4 = 31,
    MTLVertexFormatInt = 32, MTLVertexFormatInt2 = 33, MTLVertexFormatInt3 = 34, MTLVertexFormatInt4 = 35,
    MTLVertexFormatUInt = 36, MTLVertexFormatUInt2 = 37, MTLVertexFormatUInt3 = 38, MTLVertexFormatUInt4 = 39,
    MTLVertexFormatInt1010102Normalized = 40, MTLVertexFormatUInt1010102Normalized = 41,
    MTLVertexFormatUChar4Normalized_BGRA = 42,
    MTLVertexFormatUChar = 45, MTLVertexFormatChar = 46, MTLVertexFormatUCharNormalized = 47,
    MTLVertexFormatCharNormalized = 48, MTLVertexFormatUShort = 49, MTLVertexFormatShort = 50,
    MTLVertexFormatUShortNormalized = 51, MTLVertexFormatShortNormalized = 52, MTLVertexFormatHalf = 53,
    MTLVertexFormatFloatRG11B10 = 54, MTLVertexFormatFloatRGB9E5 = 55,
};
typedef MTLVertexFormat MTLAttributeFormat;
/* a buffer binding that keeps the pipeline's own stride (attributeStride:) */
static const NSUInteger MTLAttributeStrideStatic = NSUIntegerMax;
typedef NS_ENUM(NSUInteger, MTLVertexStepFunction) {
    MTLVertexStepFunctionConstant = 0, MTLVertexStepFunctionPerVertex = 1, MTLVertexStepFunctionPerInstance = 2,
    MTLVertexStepFunctionPerPatch = 3, MTLVertexStepFunctionPerPatchControlPoint = 4,
};
typedef NS_ENUM(NSUInteger, MTLStepFunction) {
    MTLStepFunctionConstant = 0, MTLStepFunctionPerVertex = 1, MTLStepFunctionPerInstance = 2,
    MTLStepFunctionPerPatch = 3, MTLStepFunctionPerPatchControlPoint = 4, MTLStepFunctionThreadPositionInGridX = 5,
    MTLStepFunctionThreadPositionInGridY = 6,
};
typedef NS_ENUM(NSUInteger, MTLSamplerMinMagFilter) { MTLSamplerMinMagFilterNearest = 0, MTLSamplerMinMagFilterLinear = 1 };
typedef NS_ENUM(NSUInteger, MTLSamplerMipFilter) {
    MTLSamplerMipFilterNotMipmapped = 0, MTLSamplerMipFilterNearest = 1, MTLSamplerMipFilterLinear = 2,
};
typedef NS_ENUM(NSUInteger, MTLSamplerAddressMode) {
    MTLSamplerAddressModeClampToEdge = 0, MTLSamplerAddressModeMirrorClampToEdge = 1, MTLSamplerAddressModeRepeat = 2,
    MTLSamplerAddressModeMirrorRepeat = 3, MTLSamplerAddressModeClampToZero = 4, MTLSamplerAddressModeClampToBorderColor = 5,
};
typedef NS_ENUM(NSUInteger, MTLSamplerBorderColor) {
    MTLSamplerBorderColorTransparentBlack = 0, MTLSamplerBorderColorOpaqueBlack = 1, MTLSamplerBorderColorOpaqueWhite = 2,
};
typedef NS_ENUM(NSUInteger, MTLTextureType) {
    MTLTextureType1D = 0, MTLTextureType1DArray = 1, MTLTextureType2D = 2, MTLTextureType2DArray = 3,
    MTLTextureType2DMultisample = 4, MTLTextureTypeCube = 5, MTLTextureTypeCubeArray = 6, MTLTextureType3D = 7,
    MTLTextureType2DMultisampleArray = 8, MTLTextureTypeTextureBuffer = 9,
};
typedef NS_OPTIONS(NSUInteger, MTLTextureUsage) {
    MTLTextureUsageUnknown = 0x0000, MTLTextureUsageShaderRead = 0x0001, MTLTextureUsageShaderWrite = 0x0002,
    MTLTextureUsageRenderTarget = 0x0004, MTLTextureUsagePixelFormatView = 0x0010, MTLTextureUsageShaderAtomic = 0x0020,
};
typedef NS_ENUM(uint8_t, MTLTextureSwizzle) {
    MTLTextureSwizzleZero = 0, MTLTextureSwizzleOne = 1, MTLTextureSwizzleRed = 2, MTLTextureSwizzleGreen = 3,
    MTLTextureSwizzleBlue = 4, MTLTextureSwizzleAlpha = 5,
};
typedef struct { MTLTextureSwizzle red, green, blue, alpha; } MTLTextureSwizzleChannels;
static inline MTLTextureSwizzleChannels MTLTextureSwizzleChannelsMake(MTLTextureSwizzle r, MTLTextureSwizzle g,
                                                                      MTLTextureSwizzle b, MTLTextureSwizzle a)
{ MTLTextureSwizzleChannels s = {r, g, b, a}; return s; }
#define MTLTextureSwizzleChannelsDefault (MTLTextureSwizzleChannelsMake(MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha))
typedef NS_ENUM(NSUInteger, MTLTextureCompressionType) { MTLTextureCompressionTypeLossless = 0, MTLTextureCompressionTypeLossy = 1 };

typedef NS_ENUM(NSUInteger, MTLCPUCacheMode) { MTLCPUCacheModeDefaultCache = 0, MTLCPUCacheModeWriteCombined = 1 };
typedef NS_ENUM(NSUInteger, MTLStorageMode) {
    MTLStorageModeShared = 0, MTLStorageModeManaged = 1, MTLStorageModePrivate = 2, MTLStorageModeMemoryless = 3,
};
typedef NS_ENUM(NSUInteger, MTLHazardTrackingMode) {
    MTLHazardTrackingModeDefault = 0, MTLHazardTrackingModeUntracked = 1, MTLHazardTrackingModeTracked = 2,
};
#define MTLResourceCPUCacheModeShift 0
#define MTLResourceStorageModeShift 4
#define MTLResourceHazardTrackingModeShift 8
typedef NS_OPTIONS(NSUInteger, MTLResourceOptions) {
    MTLResourceCPUCacheModeDefaultCache = MTLCPUCacheModeDefaultCache << MTLResourceCPUCacheModeShift,
    MTLResourceCPUCacheModeWriteCombined = MTLCPUCacheModeWriteCombined << MTLResourceCPUCacheModeShift,
    MTLResourceStorageModeShared = MTLStorageModeShared << MTLResourceStorageModeShift,
    MTLResourceStorageModeManaged = MTLStorageModeManaged << MTLResourceStorageModeShift,
    MTLResourceStorageModePrivate = MTLStorageModePrivate << MTLResourceStorageModeShift,
    MTLResourceStorageModeMemoryless = MTLStorageModeMemoryless << MTLResourceStorageModeShift,
    MTLResourceHazardTrackingModeDefault = MTLHazardTrackingModeDefault << MTLResourceHazardTrackingModeShift,
    MTLResourceHazardTrackingModeUntracked = MTLHazardTrackingModeUntracked << MTLResourceHazardTrackingModeShift,
    MTLResourceHazardTrackingModeTracked = MTLHazardTrackingModeTracked << MTLResourceHazardTrackingModeShift,
    MTLResourceOptionCPUCacheModeDefault = MTLResourceCPUCacheModeDefaultCache,
    MTLResourceOptionCPUCacheModeWriteCombined = MTLResourceCPUCacheModeWriteCombined,
};
typedef NS_ENUM(NSUInteger, MTLPurgeableState) {
    MTLPurgeableStateKeepCurrent = 1, MTLPurgeableStateNonVolatile = 2, MTLPurgeableStateVolatile = 3,
    MTLPurgeableStateEmpty = 4,
};
typedef NS_OPTIONS(NSUInteger, MTLResourceUsage) {
    MTLResourceUsageRead = 1 << 0, MTLResourceUsageWrite = 1 << 1, MTLResourceUsageSample = 1 << 2,
};
typedef NS_OPTIONS(NSUInteger, MTLBarrierScope) {
    MTLBarrierScopeBuffers = 1 << 0, MTLBarrierScopeTextures = 1 << 1, MTLBarrierScopeRenderTargets = 1 << 2,
};
typedef NS_OPTIONS(NSUInteger, MTLRenderStages) {
    MTLRenderStageVertex = 1 << 0, MTLRenderStageFragment = 1 << 1, MTLRenderStageTile = 1 << 2,
    MTLRenderStageObject = 1 << 3, MTLRenderStageMesh = 1 << 4,
};
typedef NS_ENUM(NSUInteger, MTLDispatchType) { MTLDispatchTypeSerial = 0, MTLDispatchTypeConcurrent = 1 };
typedef NS_ENUM(NSInteger, MTLGPUFamily) {
    MTLGPUFamilyApple1 = 1001, MTLGPUFamilyApple2 = 1002, MTLGPUFamilyApple3 = 1003, MTLGPUFamilyApple4 = 1004,
    MTLGPUFamilyApple5 = 1005, MTLGPUFamilyApple6 = 1006, MTLGPUFamilyApple7 = 1007, MTLGPUFamilyApple8 = 1008,
    MTLGPUFamilyApple9 = 1009,
    MTLGPUFamilyMac1 = 2001, MTLGPUFamilyMac2 = 2002,
    MTLGPUFamilyCommon1 = 3001, MTLGPUFamilyCommon2 = 3002, MTLGPUFamilyCommon3 = 3003,
    MTLGPUFamilyMacCatalyst1 = 4001, MTLGPUFamilyMacCatalyst2 = 4002,
    MTLGPUFamilyMetal3 = 5001,
};
typedef NS_ENUM(NSUInteger, MTLFeatureSet) {
    MTLFeatureSet_macOS_GPUFamily1_v1 = 10000, MTLFeatureSet_macOS_GPUFamily1_v2 = 10001,
    MTLFeatureSet_macOS_ReadWriteTextureTier2 = 10002, MTLFeatureSet_macOS_GPUFamily1_v3 = 10003,
    MTLFeatureSet_macOS_GPUFamily1_v4 = 10004, MTLFeatureSet_macOS_GPUFamily2_v1 = 10005,
};
typedef NS_ENUM(NSUInteger, MTLArgumentBuffersTier) { MTLArgumentBuffersTier1 = 0, MTLArgumentBuffersTier2 = 1 };
typedef NS_ENUM(NSUInteger, MTLReadWriteTextureTier) {
    MTLReadWriteTextureTierNone = 0, MTLReadWriteTextureTier1 = 1, MTLReadWriteTextureTier2 = 2,
};
typedef NS_ENUM(NSUInteger, MTLDeviceLocation) {
    MTLDeviceLocationBuiltIn = 0, MTLDeviceLocationSlot = 1, MTLDeviceLocationExternal = 2,
    MTLDeviceLocationUnspecified = NSUIntegerMax,
};
typedef NS_ENUM(NSUInteger, MTLLanguageVersion) {
    MTLLanguageVersion1_0 = (1 << 16), MTLLanguageVersion1_1 = (1 << 16) + 1, MTLLanguageVersion1_2 = (1 << 16) + 2,
    MTLLanguageVersion2_0 = (2 << 16), MTLLanguageVersion2_1 = (2 << 16) + 1, MTLLanguageVersion2_2 = (2 << 16) + 2,
    MTLLanguageVersion2_3 = (2 << 16) + 3, MTLLanguageVersion2_4 = (2 << 16) + 4, MTLLanguageVersion3_0 = (3 << 16),
    MTLLanguageVersion3_1 = (3 << 16) + 1, MTLLanguageVersion3_2 = (3 << 16) + 2,
};
typedef NS_ENUM(NSInteger, MTLLibraryType) { MTLLibraryTypeExecutable = 0, MTLLibraryTypeDynamic = 1 };
typedef NS_ENUM(NSInteger, MTLLibraryOptimizationLevel) {
    MTLLibraryOptimizationLevelDefault = 0, MTLLibraryOptimizationLevelSize = 1,
};
typedef NS_ENUM(NSInteger, MTLCompileSymbolVisibility) {
    MTLCompileSymbolVisibilityDefault = 0, MTLCompileSymbolVisibilityHidden = 1,
};
typedef NS_ENUM(NSInteger, MTLMathMode) { MTLMathModeSafe = 0, MTLMathModeRelaxed = 1, MTLMathModeFast = 2 };
typedef NS_ENUM(NSInteger, MTLMathFloatingPointFunctions) {
    MTLMathFloatingPointFunctionsFast = 0, MTLMathFloatingPointFunctionsPrecise = 1,
};
typedef NS_ENUM(NSUInteger, MTLFunctionType) {
    MTLFunctionTypeVertex = 1, MTLFunctionTypeFragment = 2, MTLFunctionTypeKernel = 3,
    MTLFunctionTypeVisible = 5, MTLFunctionTypeIntersection = 6, MTLFunctionTypeMesh = 7, MTLFunctionTypeObject = 8,
};
typedef NS_ENUM(NSUInteger, MTLPatchType) { MTLPatchTypeNone = 0, MTLPatchTypeTriangle = 1, MTLPatchTypeQuad = 2 };
typedef NS_ENUM(NSUInteger, MTLDataType) {
    MTLDataTypeNone = 0, MTLDataTypeStruct = 1, MTLDataTypeArray = 2,
    MTLDataTypeFloat = 3, MTLDataTypeFloat2 = 4, MTLDataTypeFloat3 = 5, MTLDataTypeFloat4 = 6,
    MTLDataTypeFloat2x2 = 7, MTLDataTypeFloat2x3 = 8, MTLDataTypeFloat2x4 = 9,
    MTLDataTypeFloat3x2 = 10, MTLDataTypeFloat3x3 = 11, MTLDataTypeFloat3x4 = 12,
    MTLDataTypeFloat4x2 = 13, MTLDataTypeFloat4x3 = 14, MTLDataTypeFloat4x4 = 15,
    MTLDataTypeHalf = 16, MTLDataTypeHalf2 = 17, MTLDataTypeHalf3 = 18, MTLDataTypeHalf4 = 19,
    MTLDataTypeHalf2x2 = 20, MTLDataTypeHalf2x3 = 21, MTLDataTypeHalf2x4 = 22,
    MTLDataTypeHalf3x2 = 23, MTLDataTypeHalf3x3 = 24, MTLDataTypeHalf3x4 = 25,
    MTLDataTypeHalf4x2 = 26, MTLDataTypeHalf4x3 = 27, MTLDataTypeHalf4x4 = 28,
    MTLDataTypeInt = 29, MTLDataTypeInt2 = 30, MTLDataTypeInt3 = 31, MTLDataTypeInt4 = 32,
    MTLDataTypeUInt = 33, MTLDataTypeUInt2 = 34, MTLDataTypeUInt3 = 35, MTLDataTypeUInt4 = 36,
    MTLDataTypeShort = 37, MTLDataTypeShort2 = 38, MTLDataTypeShort3 = 39, MTLDataTypeShort4 = 40,
    MTLDataTypeUShort = 41, MTLDataTypeUShort2 = 42, MTLDataTypeUShort3 = 43, MTLDataTypeUShort4 = 44,
    MTLDataTypeChar = 45, MTLDataTypeChar2 = 46, MTLDataTypeChar3 = 47, MTLDataTypeChar4 = 48,
    MTLDataTypeUChar = 49, MTLDataTypeUChar2 = 50, MTLDataTypeUChar3 = 51, MTLDataTypeUChar4 = 52,
    MTLDataTypeBool = 53, MTLDataTypeBool2 = 54, MTLDataTypeBool3 = 55, MTLDataTypeBool4 = 56,
    MTLDataTypeTexture = 58, MTLDataTypeSampler = 59, MTLDataTypePointer = 60,
    MTLDataTypeR8Unorm = 62, MTLDataTypeR8Snorm = 63, MTLDataTypeR16Unorm = 64, MTLDataTypeR16Snorm = 65,
    MTLDataTypeRG8Unorm = 66, MTLDataTypeRG8Snorm = 67, MTLDataTypeRG16Unorm = 68, MTLDataTypeRG16Snorm = 69,
    MTLDataTypeRGBA8Unorm = 70, MTLDataTypeRGBA8Unorm_sRGB = 71, MTLDataTypeRGBA8Snorm = 72,
    MTLDataTypeRGBA16Unorm = 73, MTLDataTypeRGBA16Snorm = 74, MTLDataTypeRGB10A2Unorm = 75,
    MTLDataTypeRG11B10Float = 76, MTLDataTypeRGB9E5Float = 77, MTLDataTypeRenderPipeline = 78,
    MTLDataTypeComputePipeline = 79, MTLDataTypeIndirectCommandBuffer = 80,
    MTLDataTypeLong = 81, MTLDataTypeLong2 = 82, MTLDataTypeLong3 = 83, MTLDataTypeLong4 = 84,
    MTLDataTypeULong = 85, MTLDataTypeULong2 = 86, MTLDataTypeULong3 = 87, MTLDataTypeULong4 = 88,
    MTLDataTypeVisibleFunctionTable = 115, MTLDataTypeIntersectionFunctionTable = 116,
    MTLDataTypePrimitiveAccelerationStructure = 117, MTLDataTypeInstanceAccelerationStructure = 118,
    MTLDataTypeBFloat = 121, MTLDataTypeBFloat2 = 122, MTLDataTypeBFloat3 = 123, MTLDataTypeBFloat4 = 124,
};
typedef NS_ENUM(NSUInteger, MTLArgumentType) {
    MTLArgumentTypeBuffer = 0, MTLArgumentTypeThreadgroupMemory = 1, MTLArgumentTypeTexture = 2,
    MTLArgumentTypeSampler = 3, MTLArgumentTypeImageblockData = 16, MTLArgumentTypeImageblock = 17,
    MTLArgumentTypeVisibleFunctionTable = 24, MTLArgumentTypePrimitiveAccelerationStructure = 25,
    MTLArgumentTypeInstanceAccelerationStructure = 26, MTLArgumentTypeIntersectionFunctionTable = 27,
};
typedef NS_ENUM(NSUInteger, MTLBindingType) {
    MTLBindingTypeBuffer = 0, MTLBindingTypeThreadgroupMemory = 1, MTLBindingTypeTexture = 2,
    MTLBindingTypeSampler = 3, MTLBindingTypeImageblockData = 16, MTLBindingTypeImageblock = 17,
    MTLBindingTypeVisibleFunctionTable = 24, MTLBindingTypePrimitiveAccelerationStructure = 25,
    MTLBindingTypeInstanceAccelerationStructure = 26, MTLBindingTypeIntersectionFunctionTable = 27,
    MTLBindingTypeObjectPayload = 34,
};
typedef NS_ENUM(NSUInteger, MTLBindingAccess) {
    MTLBindingAccessReadOnly = 0, MTLBindingAccessReadWrite = 1, MTLBindingAccessWriteOnly = 2,
};
typedef MTLBindingAccess MTLArgumentAccess;
#define MTLArgumentAccessReadOnly MTLBindingAccessReadOnly
#define MTLArgumentAccessReadWrite MTLBindingAccessReadWrite
#define MTLArgumentAccessWriteOnly MTLBindingAccessWriteOnly
typedef NS_OPTIONS(NSUInteger, MTLPipelineOption) {
    MTLPipelineOptionNone = 0, MTLPipelineOptionArgumentInfo = 1 << 0, MTLPipelineOptionBindingInfo = 1 << 0,
    MTLPipelineOptionBufferTypeInfo = 1 << 1, MTLPipelineOptionFailOnBinaryArchiveMiss = 1 << 2,
};
typedef NS_ENUM(NSUInteger, MTLMutability) { MTLMutabilityDefault = 0, MTLMutabilityMutable = 1, MTLMutabilityImmutable = 2 };
typedef NS_ENUM(NSUInteger, MTLShaderValidation) { MTLShaderValidationDefault = 0, MTLShaderValidationEnabled = 1, MTLShaderValidationDisabled = 2 };
typedef NS_ENUM(NSUInteger, MTLCommandBufferStatus) {
    MTLCommandBufferStatusNotEnqueued = 0, MTLCommandBufferStatusEnqueued = 1, MTLCommandBufferStatusCommitted = 2,
    MTLCommandBufferStatusScheduled = 3, MTLCommandBufferStatusCompleted = 4, MTLCommandBufferStatusError = 5,
};
typedef NS_OPTIONS(NSUInteger, MTLCommandBufferErrorOption) {
    MTLCommandBufferErrorOptionNone = 0, MTLCommandBufferErrorOptionEncoderExecutionStatus = 1 << 0,
};
typedef NS_ENUM(NSUInteger, MTLCommandBufferError) {
    MTLCommandBufferErrorNone = 0, MTLCommandBufferErrorInternal = 1, MTLCommandBufferErrorTimeout = 2,
    MTLCommandBufferErrorPageFault = 3, MTLCommandBufferErrorAccessRevoked = 4, MTLCommandBufferErrorNotPermitted = 7,
    MTLCommandBufferErrorOutOfMemory = 8, MTLCommandBufferErrorInvalidResource = 9, MTLCommandBufferErrorMemoryless = 10,
    MTLCommandBufferErrorStackOverflow = 12,
};
typedef NS_ENUM(NSUInteger, MTLLibraryError) {
    MTLLibraryErrorUnsupported = 1, MTLLibraryErrorInternal = 2, MTLLibraryErrorCompileFailure = 3,
    MTLLibraryErrorCompileWarning = 4, MTLLibraryErrorFunctionNotFound = 5, MTLLibraryErrorFileNotFound = 6,
};
typedef NS_ENUM(NSUInteger, MTLRenderPipelineError) {
    MTLRenderPipelineErrorInternal = 1, MTLRenderPipelineErrorUnsupported = 2, MTLRenderPipelineErrorInvalidInput = 3,
};
typedef NS_ENUM(NSUInteger, MTLCaptureDestination) {
    MTLCaptureDestinationDeveloperTools = 1, MTLCaptureDestinationGPUTraceDocument = 2,
};
typedef NS_ENUM(NSInteger, MTLCaptureError) {
    MTLCaptureErrorNotSupported = 1, MTLCaptureErrorAlreadyCapturing = 2, MTLCaptureErrorInvalidDescriptor = 3,
};
typedef NS_ENUM(NSUInteger, MTLHeapType) { MTLHeapTypeAutomatic = 0, MTLHeapTypePlacement = 1, MTLHeapTypeSparse = 2 };
typedef NS_ENUM(NSUInteger, MTLBlitOption) {
    MTLBlitOptionNone = 0, MTLBlitOptionDepthFromDepthStencil = 1 << 0, MTLBlitOptionStencilFromDepthStencil = 1 << 1,
    MTLBlitOptionRowLinearPVRTC = 1 << 2,
};
typedef NS_ENUM(NSUInteger, MTLCounterSampleBufferError) { MTLCounterSampleBufferErrorOutOfMemory = 0 };
typedef NS_ENUM(NSInteger, MTLIOCompressionMethod) { MTLIOCompressionMethodZlib = 0 };
typedef NS_ENUM(NSUInteger, MTLSparseTextureRegionAlignmentMode) {
    MTLSparseTextureRegionAlignmentModeOutward = 0, MTLSparseTextureRegionAlignmentModeInward = 1,
};
typedef NS_ENUM(NSUInteger, MTLIndirectCommandType) {
    MTLIndirectCommandTypeDraw = 1 << 0, MTLIndirectCommandTypeDrawIndexed = 1 << 1,
    MTLIndirectCommandTypeConcurrentDispatch = 1 << 5,
};
typedef NS_ENUM(NSUInteger, MTLTessellationPartitionMode) { MTLTessellationPartitionModePow2 = 0 };
typedef NS_ENUM(NSUInteger, MTLPrimitiveTopology_) { MTLPrimitiveTopology_Unused = 0 };
typedef NS_ENUM(NSInteger, MTLGPUFamilyLegacy_) { MTLGPUFamilyLegacy_Unused = 0 };
typedef NSUInteger MTLColorSpace_;
typedef uint64_t MTLTimestamp;

MTL_EXTERN NSString *const MTLLibraryErrorDomain;
MTL_EXTERN NSString *const MTLCommandBufferErrorDomain;
MTL_EXTERN NSString *const MTLRenderPipelineErrorDomain;
MTL_EXTERN NSString *const MTLCaptureErrorDomain;
MTL_EXTERN NSString *const MTLDeviceWasAddedNotification;
MTL_EXTERN NSString *const MTLDeviceRemovalRequestedNotification;
MTL_EXTERN NSString *const MTLDeviceWasRemovedNotification;
MTL_EXTERN NSString *const MTLCommandBufferEncoderInfoErrorKey;

/* ---- protocols ------------------------------------------------------------------- */
@protocol MTLDevice, MTLCommandQueue, MTLCommandBuffer, MTLBuffer, MTLTexture, MTLHeap, MTLLibrary, MTLFunction;
@protocol MTLRenderPipelineState, MTLComputePipelineState, MTLDepthStencilState, MTLSamplerState;
@protocol MTLArgumentEncoder, MTLFence, MTLEvent, MTLSharedEvent, MTLDrawable, MTLIndirectCommandBuffer;
@class MTLCompileOptions, MTLFunctionConstantValues, MTLRenderPipelineDescriptor, MTLComputePipelineDescriptor;
@class MTLRenderPassDescriptor, MTLTextureDescriptor, MTLSamplerDescriptor, MTLDepthStencilDescriptor;
@class MTLRenderPipelineReflection, MTLComputePipelineReflection, MTLHeapDescriptor, MTLArgumentDescriptor;
@class MTLCommandBufferDescriptor, MTLSharedEventHandle, MTLSharedEventListener, MTLStructType, MTLArrayType;
@class MTLPointerType, MTLTextureReferenceType, MTLType, MTLFunctionDescriptor, MTLComputePassDescriptor;
@class MTLBlitPassDescriptor, MTLIndirectCommandBufferDescriptor, MTLSharedTextureHandle, MTLFunctionConstant;
@class MTLVertexAttribute, MTLAttribute, MTLArgument, MTLTileRenderPipelineDescriptor;

typedef MTLRenderPipelineReflection *MTLAutoreleasedRenderPipelineReflection;
typedef MTLComputePipelineReflection *MTLAutoreleasedComputePipelineReflection;
typedef MTLArgument *MTLAutoreleasedArgument;
typedef void (^MTLCommandBufferHandler)(id<MTLCommandBuffer>);
typedef void (^MTLNewLibraryCompletionHandler)(id<MTLLibrary> library, NSError *error);
typedef void (^MTLNewRenderPipelineStateCompletionHandler)(id<MTLRenderPipelineState>, NSError *);
typedef void (^MTLNewRenderPipelineStateWithReflectionCompletionHandler)(id<MTLRenderPipelineState>,
                                                                          MTLRenderPipelineReflection *, NSError *);
typedef void (^MTLNewComputePipelineStateCompletionHandler)(id<MTLComputePipelineState>, NSError *);
typedef void (^MTLNewComputePipelineStateWithReflectionCompletionHandler)(id<MTLComputePipelineState>,
                                                                           MTLComputePipelineReflection *, NSError *);
typedef void (^MTLSharedEventNotificationBlock)(id<MTLSharedEvent>, uint64_t value);
typedef void (^MTLDeviceNotificationHandler)(id<MTLDevice>, NSString *);

@protocol MTLResource <NSObject>
@property (readonly) id<MTLDevice> device;
@property (copy, atomic) NSString *label;
@property (readonly) MTLCPUCacheMode cpuCacheMode;
@property (readonly) MTLStorageMode storageMode;
@property (readonly) MTLHazardTrackingMode hazardTrackingMode;
@property (readonly) MTLResourceOptions resourceOptions;
@property (readonly) id<MTLHeap> heap;
@property (readonly) NSUInteger heapOffset;
@property (readonly) NSUInteger allocatedSize;
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state;
- (void)makeAliasable;
- (BOOL)isAliasable;
@end
typedef id<MTLResource> MTLAllocation_;

@protocol MTLBuffer <MTLResource>
@property (readonly) NSUInteger length;
@property (readonly) uint64_t gpuAddress;
- (void *)contents;
- (void)didModifyRange:(NSRange)range;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset
                               bytesPerRow:(NSUInteger)bytesPerRow;
- (void)addDebugMarker:(NSString *)marker range:(NSRange)range;
- (void)removeAllDebugMarkers;
@end

@protocol MTLTexture <MTLResource>
@property (readonly) id<MTLResource> rootResource;
@property (readonly) id<MTLTexture> parentTexture;
@property (readonly) NSUInteger parentRelativeLevel;
@property (readonly) NSUInteger parentRelativeSlice;
@property (readonly) id<MTLBuffer> buffer;
@property (readonly) NSUInteger bufferOffset;
@property (readonly) NSUInteger bufferBytesPerRow;
@property (readonly) MTLTextureType textureType;
@property (readonly) MTLPixelFormat pixelFormat;
@property (readonly) NSUInteger width;
@property (readonly) NSUInteger height;
@property (readonly) NSUInteger depth;
@property (readonly) NSUInteger mipmapLevelCount;
@property (readonly) NSUInteger sampleCount;
@property (readonly) NSUInteger arrayLength;
@property (readonly) MTLTextureUsage usage;
@property (readonly, getter=isShareable) BOOL shareable;
@property (readonly, getter=isFramebufferOnly) BOOL framebufferOnly;
@property (readonly) NSUInteger firstMipmapInTail;
@property (readonly) NSUInteger tailSizeInBytes;
@property (readonly) BOOL isSparse;
@property (readonly) BOOL allowGPUOptimizedContents;
@property (readonly) MTLTextureSwizzleChannels swizzle;
@property (readonly) MTLResourceID gpuResourceID;
@property (readonly) void *iosurface;
@property (readonly) NSUInteger iosurfacePlane;
- (void)getBytes:(void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow bytesPerImage:(NSUInteger)bytesPerImage
      fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice;
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice
            withBytes:(const void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow bytesPerImage:(NSUInteger)bytesPerImage;
- (void)getBytes:(void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow fromRegion:(MTLRegion)region
     mipmapLevel:(NSUInteger)level;
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void *)pixelBytes
          bytesPerRow:(NSUInteger)bytesPerRow;
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat;
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat textureType:(MTLTextureType)textureType
                                         levels:(NSRange)levelRange slices:(NSRange)sliceRange;
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat textureType:(MTLTextureType)textureType
                                         levels:(NSRange)levelRange slices:(NSRange)sliceRange
                                        swizzle:(MTLTextureSwizzleChannels)swizzle;
- (MTLSharedTextureHandle *)newSharedTextureHandle;
@end

@protocol MTLSamplerState <NSObject>
@property (readonly) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) MTLResourceID gpuResourceID;
@end
@protocol MTLDepthStencilState <NSObject>
@property (readonly) NSString *label;
@property (readonly) id<MTLDevice> device;
@end
@protocol MTLFence <NSObject>
@property (readonly) id<MTLDevice> device;
@property (copy, atomic) NSString *label;
@end
@protocol MTLEvent <NSObject>
@property (readonly) id<MTLDevice> device;
@property (copy, atomic) NSString *label;
@end
@protocol MTLSharedEvent <MTLEvent>
@property (readwrite) uint64_t signaledValue;
- (void)notifyListener:(MTLSharedEventListener *)listener atValue:(uint64_t)value block:(MTLSharedEventNotificationBlock)block;
- (MTLSharedEventHandle *)newSharedEventHandle;
- (BOOL)waitUntilSignaledValue:(uint64_t)value timeoutMS:(uint64_t)milliseconds;
@end

@protocol MTLFunction <NSObject>
@property (copy, atomic) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) MTLFunctionType functionType;
@property (readonly) MTLPatchType patchType;
@property (readonly) NSInteger patchControlPointCount;
@property (readonly) NSArray<MTLVertexAttribute *> *vertexAttributes;
@property (readonly) NSArray<MTLAttribute *> *stageInputAttributes;
@property (readonly) NSString *name;
@property (readonly) NSDictionary<NSString *, MTLFunctionConstant *> *functionConstantsDictionary;
@property (readonly) NSUInteger options;
- (id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex:(NSUInteger)bufferIndex;
- (id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex:(NSUInteger)bufferIndex
                                                 reflection:(MTLAutoreleasedArgument *)reflection;
@end

@protocol MTLLibrary <NSObject>
@property (copy, atomic) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) NSArray<NSString *> *functionNames;
@property (readonly) MTLLibraryType type;
@property (readonly) NSString *installName;
- (id<MTLFunction>)newFunctionWithName:(NSString *)functionName;
- (id<MTLFunction>)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)constantValues
                                 error:(NSError **)error;
- (void)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)constantValues
          completionHandler:(void (^)(id<MTLFunction> function, NSError *error))completionHandler;
- (id<MTLFunction>)newFunctionWithDescriptor:(MTLFunctionDescriptor *)descriptor error:(NSError **)error;
@end

@protocol MTLRenderPipelineState <NSObject>
@property (readonly) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) NSUInteger maxTotalThreadsPerThreadgroup;
@property (readonly) BOOL threadgroupSizeMatchesTileSize;
@property (readonly) NSUInteger imageblockSampleLength;
@property (readonly) BOOL supportIndirectCommandBuffers;
@property (readonly) MTLResourceID gpuResourceID;
@end
@protocol MTLComputePipelineState <NSObject>
@property (readonly) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) NSUInteger maxTotalThreadsPerThreadgroup;
@property (readonly) NSUInteger threadExecutionWidth;
@property (readonly) NSUInteger staticThreadgroupMemoryLength;
@property (readonly) BOOL supportIndirectCommandBuffers;
@property (readonly) MTLResourceID gpuResourceID;
- (NSUInteger)imageblockMemoryLengthForDimensions:(MTLSize)imageblockDimensions;
@end

@protocol MTLArgumentEncoder <NSObject>
@property (readonly) id<MTLDevice> device;
@property (copy, atomic) NSString *label;
@property (readonly) NSUInteger encodedLength;
@property (readonly) NSUInteger alignment;
- (void)setArgumentBuffer:(id<MTLBuffer>)argumentBuffer offset:(NSUInteger)offset;
- (void)setArgumentBuffer:(id<MTLBuffer>)argumentBuffer startOffset:(NSUInteger)startOffset arrayElement:(NSUInteger)arrayElement;
- (void)setBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setBuffers:(const id<MTLBuffer> __unsafe_unretained[])buffers offsets:(const NSUInteger[])offsets withRange:(NSRange)range;
- (void)setTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)setTextures:(const id<MTLTexture> __unsafe_unretained[])textures withRange:(NSRange)range;
- (void)setSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index;
- (void)setSamplerStates:(const id<MTLSamplerState> __unsafe_unretained[])samplers withRange:(NSRange)range;
- (void *)constantDataAtIndex:(NSUInteger)index;
- (id<MTLArgumentEncoder>)newArgumentEncoderForBufferAtIndex:(NSUInteger)index;
@end

@protocol MTLHeap <NSObject>
@property (copy, atomic) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) MTLStorageMode storageMode;
@property (readonly) MTLCPUCacheMode cpuCacheMode;
@property (readonly) MTLHazardTrackingMode hazardTrackingMode;
@property (readonly) MTLResourceOptions resourceOptions;
@property (readonly) NSUInteger size;
@property (readonly) NSUInteger usedSize;
@property (readonly) NSUInteger currentAllocatedSize;
@property (readonly) MTLHeapType type;
- (NSUInteger)maxAvailableSizeWithAlignment:(NSUInteger)alignment;
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state;
@end

@protocol MTLCommandEncoder <NSObject>
@property (readonly) id<MTLDevice> device;
@property (copy, atomic) NSString *label;
- (void)endEncoding;
- (void)insertDebugSignpost:(NSString *)string;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
@end

@protocol MTLRenderCommandEncoder <MTLCommandEncoder>
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)pipelineState;
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setVertexBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setVertexBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setVertexBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset attributeStride:(NSUInteger)stride
               atIndex:(NSUInteger)index;
- (void)setVertexBufferOffset:(NSUInteger)offset attributeStride:(NSUInteger)stride atIndex:(NSUInteger)index;
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length attributeStride:(NSUInteger)stride
              atIndex:(NSUInteger)index;
- (void)setVertexBuffers:(const id<MTLBuffer> __unsafe_unretained[])buffers
                 offsets:(const NSUInteger[])offsets attributeStrides:(const NSUInteger[])strides
               withRange:(NSRange)range;
- (void)setVertexBuffers:(const id<MTLBuffer> __unsafe_unretained[])buffers offsets:(const NSUInteger[])offsets
               withRange:(NSRange)range;
- (void)setVertexTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)setVertexTextures:(const id<MTLTexture> __unsafe_unretained[])textures withRange:(NSRange)range;
- (void)setVertexSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index;
- (void)setVertexSamplerStates:(const id<MTLSamplerState> __unsafe_unretained[])samplers withRange:(NSRange)range;
- (void)setVertexSamplerState:(id<MTLSamplerState>)sampler lodMinClamp:(float)lodMinClamp lodMaxClamp:(float)lodMaxClamp
                      atIndex:(NSUInteger)index;
- (void)setViewport:(MTLViewport)viewport;
- (void)setViewports:(const MTLViewport[])viewports count:(NSUInteger)count;
- (void)setFrontFacingWinding:(MTLWinding)frontFacingWinding;
- (void)setCullMode:(MTLCullMode)cullMode;
- (void)setDepthClipMode:(MTLDepthClipMode)depthClipMode;
- (void)setDepthBias:(float)depthBias slopeScale:(float)slopeScale clamp:(float)clamp;
- (void)setScissorRect:(MTLScissorRect)rect;
- (void)setScissorRects:(const MTLScissorRect[])scissorRects count:(NSUInteger)count;
- (void)setTriangleFillMode:(MTLTriangleFillMode)fillMode;
- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setFragmentBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setFragmentBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setFragmentBuffers:(const id<MTLBuffer> __unsafe_unretained[])buffers offsets:(const NSUInteger[])offsets
                 withRange:(NSRange)range;
- (void)setFragmentTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)setFragmentTextures:(const id<MTLTexture> __unsafe_unretained[])textures withRange:(NSRange)range;
- (void)setFragmentSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index;
- (void)setFragmentSamplerStates:(const id<MTLSamplerState> __unsafe_unretained[])samplers withRange:(NSRange)range;
- (void)setFragmentSamplerState:(id<MTLSamplerState>)sampler lodMinClamp:(float)lodMinClamp
                    lodMaxClamp:(float)lodMaxClamp atIndex:(NSUInteger)index;
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
- (void)setDepthStencilState:(id<MTLDepthStencilState>)depthStencilState;
- (void)setStencilReferenceValue:(uint32_t)referenceValue;
- (void)setStencilFrontReferenceValue:(uint32_t)frontReferenceValue backReferenceValue:(uint32_t)backReferenceValue;
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset;
- (void)setColorStoreAction:(MTLStoreAction)storeAction atIndex:(NSUInteger)colorAttachmentIndex;
- (void)setDepthStoreAction:(MTLStoreAction)storeAction;
- (void)setStencilStoreAction:(MTLStoreAction)storeAction;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart
           vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart
           vertexCount:(NSUInteger)vertexCount;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount
                    indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer
            indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount
                    indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer
            indexBufferOffset:(NSUInteger)indexBufferOffset;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart
           vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount
          baseInstance:(NSUInteger)baseInstance;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount
                    indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer
            indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount
                   baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType indirectBuffer:(id<MTLBuffer>)indirectBuffer
  indirectBufferOffset:(NSUInteger)indirectBufferOffset;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexType:(MTLIndexType)indexType
                  indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset
               indirectBuffer:(id<MTLBuffer>)indirectBuffer indirectBufferOffset:(NSUInteger)indirectBufferOffset;
- (void)textureBarrier;
- (void)updateFence:(id<MTLFence>)fence afterStages:(MTLRenderStages)stages;
- (void)waitForFence:(id<MTLFence>)fence beforeStages:(MTLRenderStages)stages;
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage;
- (void)useResources:(const id<MTLResource> __unsafe_unretained[])resources count:(NSUInteger)count
               usage:(MTLResourceUsage)usage;
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage stages:(MTLRenderStages)stages;
- (void)useHeap:(id<MTLHeap>)heap;
- (void)useHeap:(id<MTLHeap>)heap stages:(MTLRenderStages)stages;
- (void)memoryBarrierWithScope:(MTLBarrierScope)scope afterStages:(MTLRenderStages)after
                  beforeStages:(MTLRenderStages)before;
@end

@protocol MTLComputeCommandEncoder <MTLCommandEncoder>
@property (readonly) MTLDispatchType dispatchType;
- (void)setComputePipelineState:(id<MTLComputePipelineState>)state;
- (void)setBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setBuffers:(const id<MTLBuffer> __unsafe_unretained[])buffers offsets:(const NSUInteger[])offsets
         withRange:(NSRange)range;
- (void)setTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)setTextures:(const id<MTLTexture> __unsafe_unretained[])textures withRange:(NSRange)range;
- (void)setSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index;
- (void)setSamplerStates:(const id<MTLSamplerState> __unsafe_unretained[])samplers withRange:(NSRange)range;
- (void)setSamplerState:(id<MTLSamplerState>)sampler lodMinClamp:(float)lodMinClamp lodMaxClamp:(float)lodMaxClamp
                atIndex:(NSUInteger)index;
- (void)setThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setStageInRegion:(MTLRegion)region;
- (void)dispatchThreadgroups:(MTLSize)threadgroupsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)dispatchThreadgroupsWithIndirectBuffer:(id<MTLBuffer>)indirectBuffer
                          indirectBufferOffset:(NSUInteger)indirectBufferOffset
                         threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)dispatchThreads:(MTLSize)threadsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)updateFence:(id<MTLFence>)fence;
- (void)waitForFence:(id<MTLFence>)fence;
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage;
- (void)useResources:(const id<MTLResource> __unsafe_unretained[])resources count:(NSUInteger)count
               usage:(MTLResourceUsage)usage;
- (void)useHeap:(id<MTLHeap>)heap;
- (void)memoryBarrierWithScope:(MTLBarrierScope)scope;
- (void)memoryBarrierWithResources:(const id<MTLResource> __unsafe_unretained[])resources count:(NSUInteger)count;
@end

@protocol MTLBlitCommandEncoder <MTLCommandEncoder>
- (void)synchronizeResource:(id<MTLResource>)resource;
- (void)synchronizeTexture:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice
            sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize
              toTexture:(id<MTLTexture>)destinationTexture destinationSlice:(NSUInteger)destinationSlice
       destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin;
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset
     sourceBytesPerRow:(NSUInteger)sourceBytesPerRow sourceBytesPerImage:(NSUInteger)sourceBytesPerImage
            sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture
      destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel
     destinationOrigin:(MTLOrigin)destinationOrigin;
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset
     sourceBytesPerRow:(NSUInteger)sourceBytesPerRow sourceBytesPerImage:(NSUInteger)sourceBytesPerImage
            sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture
      destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel
     destinationOrigin:(MTLOrigin)destinationOrigin options:(MTLBlitOption)options;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice
            sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize
               toBuffer:(id<MTLBuffer>)destinationBuffer destinationOffset:(NSUInteger)destinationOffset
 destinationBytesPerRow:(NSUInteger)destinationBytesPerRow destinationBytesPerImage:(NSUInteger)destinationBytesPerImage;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice
            sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize
               toBuffer:(id<MTLBuffer>)destinationBuffer destinationOffset:(NSUInteger)destinationOffset
 destinationBytesPerRow:(NSUInteger)destinationBytesPerRow destinationBytesPerImage:(NSUInteger)destinationBytesPerImage
                options:(MTLBlitOption)options;
- (void)generateMipmapsForTexture:(id<MTLTexture>)texture;
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice
            sourceLevel:(NSUInteger)sourceLevel toTexture:(id<MTLTexture>)destinationTexture
       destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel
             sliceCount:(NSUInteger)sliceCount levelCount:(NSUInteger)levelCount;
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture toTexture:(id<MTLTexture>)destinationTexture;
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset
              toBuffer:(id<MTLBuffer>)destinationBuffer destinationOffset:(NSUInteger)destinationOffset
                  size:(NSUInteger)size;
- (void)updateFence:(id<MTLFence>)fence;
- (void)waitForFence:(id<MTLFence>)fence;
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture;
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level;
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)texture;
- (void)resetCommandsInBuffer:(id<MTLIndirectCommandBuffer>)buffer withRange:(NSRange)range;
@end

@protocol MTLCommandBuffer <NSObject>
@property (readonly) id<MTLDevice> device;
@property (readonly) id<MTLCommandQueue> commandQueue;
@property (readonly) BOOL retainedReferences;
@property (readonly) MTLCommandBufferErrorOption errorOptions;
@property (copy, atomic) NSString *label;
@property (readonly) CFTimeInterval kernelStartTime;
@property (readonly) CFTimeInterval kernelEndTime;
@property (readonly) CFTimeInterval GPUStartTime;
@property (readonly) CFTimeInterval GPUEndTime;
@property (readonly) MTLCommandBufferStatus status;
@property (readonly) NSError *error;
@property (readonly) id logs;
- (void)enqueue;
- (void)commit;
- (void)addScheduledHandler:(MTLCommandBufferHandler)block;
- (void)presentDrawable:(id<MTLDrawable>)drawable;
- (void)presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)presentationTime;
- (void)presentDrawable:(id<MTLDrawable>)drawable afterMinimumDuration:(CFTimeInterval)duration;
- (void)waitUntilScheduled;
- (void)addCompletedHandler:(MTLCommandBufferHandler)block;
- (void)waitUntilCompleted;
- (id<MTLBlitCommandEncoder>)blitCommandEncoder;
- (id<MTLBlitCommandEncoder>)blitCommandEncoderWithDescriptor:(MTLBlitPassDescriptor *)blitPassDescriptor;
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor;
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDescriptor:(MTLComputePassDescriptor *)computePassDescriptor;
- (id<MTLComputeCommandEncoder>)computeCommandEncoder;
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDispatchType:(MTLDispatchType)dispatchType;
- (void)encodeWaitForEvent:(id<MTLEvent>)event value:(uint64_t)value;
- (void)encodeSignalEvent:(id<MTLEvent>)event value:(uint64_t)value;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
@end

@protocol MTLCommandQueue <NSObject>
@property (copy, atomic) NSString *label;
@property (readonly) id<MTLDevice> device;
- (id<MTLCommandBuffer>)commandBuffer;
- (id<MTLCommandBuffer>)commandBufferWithDescriptor:(MTLCommandBufferDescriptor *)descriptor;
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences;
- (void)insertDebugCaptureBoundary;
@end

@protocol MTLDevice <NSObject>
@property (readonly) NSString *name;
@property (readonly) uint64_t registryID;
@property (readonly) MTLSize maxThreadsPerThreadgroup;
@property (readonly, getter=isLowPower) BOOL lowPower;
@property (readonly, getter=isHeadless) BOOL headless;
@property (readonly, getter=isRemovable) BOOL removable;
@property (readonly) BOOL hasUnifiedMemory;
@property (readonly) uint64_t recommendedMaxWorkingSetSize;
@property (readonly) MTLDeviceLocation location;
@property (readonly) NSUInteger locationNumber;
@property (readonly) uint64_t maxTransferRate;
@property (readonly, getter=isDepth24Stencil8PixelFormatSupported) BOOL depth24Stencil8PixelFormatSupported;
@property (readonly) MTLReadWriteTextureTier readWriteTextureSupport;
@property (readonly) MTLArgumentBuffersTier argumentBuffersSupport;
@property (readonly, getter=areRasterOrderGroupsSupported) BOOL rasterOrderGroupsSupported;
@property (readonly) BOOL supports32BitFloatFiltering;
@property (readonly) BOOL supports32BitMSAA;
@property (readonly) BOOL supportsQueryTextureLOD;
@property (readonly) BOOL supportsBCTextureCompression;
@property (readonly) BOOL supportsPullModelInterpolation;
@property (readonly, getter=areBarycentricCoordsSupported) BOOL barycentricCoordsSupported;
@property (readonly) BOOL supportsShaderBarycentricCoordinates;
@property (readonly) NSUInteger currentAllocatedSize;
@property (readonly) NSUInteger maxThreadgroupMemoryLength;
@property (readonly) NSUInteger maxArgumentBufferSamplerCount;
@property (readonly, getter=areProgrammableSamplePositionsSupported) BOOL programmableSamplePositionsSupported;
@property (readonly) NSUInteger maxBufferLength;
@property (readonly) uint64_t peerGroupID;
@property (readonly) uint32_t peerIndex;
@property (readonly) uint32_t peerCount;
@property (readonly) NSUInteger sparseTileSizeInBytes;
@property (readonly) BOOL supportsDynamicLibraries;
@property (readonly) BOOL supportsRenderDynamicLibraries;
@property (readonly) BOOL supportsRaytracing;
@property (readonly) BOOL supportsFunctionPointers;
@property (readonly) BOOL supportsFunctionPointersFromRender;
@property (readonly) BOOL supportsRaytracingFromRender;
@property (readonly) BOOL supportsPrimitiveMotionBlur;
@property (readonly) BOOL shouldMaximizeConcurrentCompilation;
@property (readonly) NSUInteger maximumConcurrentCompilationTaskCount;
@property (readonly) NSArray *counterSets;
- (void)setShouldMaximizeConcurrentCompilation:(BOOL)value;
- (BOOL)supportsFamily:(MTLGPUFamily)gpuFamily;
- (BOOL)supportsFeatureSet:(MTLFeatureSet)featureSet;
- (BOOL)supportsTextureSampleCount:(NSUInteger)sampleCount;
- (BOOL)supportsVertexAmplificationCount:(NSUInteger)count;
- (NSUInteger)minimumLinearTextureAlignmentForPixelFormat:(MTLPixelFormat)format;
- (NSUInteger)minimumTextureBufferAlignmentForPixelFormat:(MTLPixelFormat)format;
- (id<MTLCommandQueue>)newCommandQueue;
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)maxCommandBufferCount;
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)desc;
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
- (id<MTLHeap>)newHeapWithDescriptor:(MTLHeapDescriptor *)descriptor;
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
- (id<MTLBuffer>)newBufferWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options;
- (id<MTLBuffer>)newBufferWithBytesNoCopy:(void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options
                              deallocator:(void (^)(void *pointer, NSUInteger length))deallocator;
- (id<MTLDepthStencilState>)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)descriptor;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor iosurface:(void *)iosurface
                                     plane:(NSUInteger)plane;
- (id<MTLTexture>)newSharedTextureWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)descriptor;
- (id<MTLLibrary>)newDefaultLibrary;
- (id<MTLLibrary>)newDefaultLibraryWithBundle:(NSBundle *)bundle error:(NSError **)error;
- (id<MTLLibrary>)newLibraryWithFile:(NSString *)filepath error:(NSError **)error;
- (id<MTLLibrary>)newLibraryWithURL:(NSURL *)url error:(NSError **)error;
- (id<MTLLibrary>)newLibraryWithData:(id)data error:(NSError **)error;
- (id<MTLLibrary>)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options error:(NSError **)error;
- (void)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options
           completionHandler:(MTLNewLibraryCompletionHandler)completionHandler;
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                                                             error:(NSError **)error;
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                                                           options:(MTLPipelineOption)options
                                                        reflection:(MTLAutoreleasedRenderPipelineReflection *)reflection
                                                             error:(NSError **)error;
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                           completionHandler:(MTLNewRenderPipelineStateCompletionHandler)completionHandler;
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)computeFunction
                                                             error:(NSError **)error;
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)computeFunction
                                                           options:(MTLPipelineOption)options
                                                        reflection:(MTLAutoreleasedComputePipelineReflection *)reflection
                                                             error:(NSError **)error;
- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)descriptor
                                                             options:(MTLPipelineOption)options
                                                          reflection:(MTLAutoreleasedComputePipelineReflection *)reflection
                                                               error:(NSError **)error;
- (void)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)descriptor
                                      options:(MTLPipelineOption)options
                            completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)completionHandler;
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)computeFunction
                          completionHandler:(MTLNewComputePipelineStateCompletionHandler)completionHandler;
- (id<MTLFence>)newFence;
- (id<MTLEvent>)newEvent;
- (id<MTLSharedEvent>)newSharedEvent;
- (id<MTLSharedEvent>)newSharedEventWithHandle:(MTLSharedEventHandle *)sharedEventHandle;
- (id<MTLArgumentEncoder>)newArgumentEncoderWithArguments:(NSArray<MTLArgumentDescriptor *> *)arguments;
- (id<MTLIndirectCommandBuffer>)newIndirectCommandBufferWithDescriptor:(MTLIndirectCommandBufferDescriptor *)descriptor
                                                        maxCommandCount:(NSUInteger)maxCount
                                                                options:(MTLResourceOptions)options;
- (void)getDefaultSamplePositions:(MTLSamplePosition *)positions count:(NSUInteger)count;
- (void)sampleTimestamps:(MTLTimestamp *)cpuTimestamp gpuTimestamp:(MTLTimestamp *)gpuTimestamp;
@end

@protocol MTLIndirectCommandBuffer <MTLResource>
@property (readonly) NSUInteger size;
@end

/* ---- descriptors and other classes ----------------------------------------------- */
@interface MTLCompileOptions : NSObject <NSCopying>
@property (copy) NSDictionary<NSString *, NSObject *> *preprocessorMacros;
@property (assign) BOOL fastMathEnabled;
@property (assign) MTLMathMode mathMode;
@property (assign) MTLMathFloatingPointFunctions mathFloatingPointFunctions;
@property (assign) MTLLanguageVersion languageVersion;
@property (assign) MTLLibraryType libraryType;
@property (copy) NSString *installName;
@property (copy) NSArray *libraries;
@property (assign) BOOL preserveInvariance;
@property (assign) MTLLibraryOptimizationLevel optimizationLevel;
@property (assign) MTLCompileSymbolVisibility compileSymbolVisibility;
@property (assign) BOOL allowReferencingUndefinedSymbols;
@property (assign) NSUInteger maxTotalThreadsPerThreadgroup;
@property (assign) BOOL enableLogging;
@end

@interface MTLFunctionConstantValues : NSObject <NSCopying>
- (void)setConstantValue:(const void *)value type:(MTLDataType)type atIndex:(NSUInteger)index;
- (void)setConstantValues:(const void *)values type:(MTLDataType)type withRange:(NSRange)range;
- (void)setConstantValue:(const void *)value type:(MTLDataType)type withName:(NSString *)name;
- (void)reset;
@end

@interface MTLFunctionConstant : NSObject
@property (readonly) NSString *name;
@property (readonly) MTLDataType type;
@property (readonly) NSUInteger index;
@property (readonly) BOOL required;
@end

@interface MTLFunctionDescriptor : NSObject <NSCopying>
+ (MTLFunctionDescriptor *)functionDescriptor;
@property (copy) NSString *name;
@property (copy) NSString *specializedName;
@property (copy) MTLFunctionConstantValues *constantValues;
@property (assign) NSUInteger options;
@end

@interface MTLVertexAttribute : NSObject
@property (readonly) NSString *name;
@property (readonly) NSUInteger attributeIndex;
@property (readonly) MTLDataType attributeType;
@property (readonly, getter=isActive) BOOL active;
@end
@interface MTLAttribute : NSObject
@property (readonly) NSString *name;
@property (readonly) NSUInteger attributeIndex;
@property (readonly) MTLDataType attributeType;
@property (readonly, getter=isActive) BOOL active;
@end

@interface MTLType : NSObject
@property (readonly) MTLDataType dataType;
@end
@interface MTLStructMember : NSObject
@property (readonly) NSString *name;
@property (readonly) NSUInteger offset;
@property (readonly) MTLDataType dataType;
@property (readonly) NSUInteger argumentIndex;
- (MTLStructType *)structType;
- (MTLArrayType *)arrayType;
@end
@interface MTLStructType : MTLType
@property (readonly) NSArray<MTLStructMember *> *members;
- (MTLStructMember *)memberByName:(NSString *)name;
@end
@interface MTLArrayType : MTLType
@property (readonly) MTLDataType elementType;
@property (readonly) NSUInteger arrayLength;
@property (readonly) NSUInteger stride;
@property (readonly) NSUInteger argumentIndexStride;
- (MTLStructType *)elementStructType;
- (MTLArrayType *)elementArrayType;
@end
@interface MTLPointerType : MTLType
@property (readonly) MTLDataType elementType;
@property (readonly) MTLArgumentAccess access;
@property (readonly) NSUInteger alignment;
@property (readonly) NSUInteger dataSize;
@property (readonly) BOOL elementIsArgumentBuffer;
@end

@interface MTLArgument : NSObject
@property (readonly) NSString *name;
@property (readonly) MTLArgumentType type;
@property (readonly) MTLArgumentAccess access;
@property (readonly) NSUInteger index;
@property (readonly, getter=isActive) BOOL active;
@property (readonly) NSUInteger bufferAlignment;
@property (readonly) NSUInteger bufferDataSize;
@property (readonly) MTLDataType bufferDataType;
@property (readonly) MTLStructType *bufferStructType;
@property (readonly) MTLPointerType *bufferPointerType;
@property (readonly) NSUInteger threadgroupMemoryAlignment;
@property (readonly) NSUInteger threadgroupMemoryDataSize;
@property (readonly) MTLTextureType textureType;
@property (readonly) MTLDataType textureDataType;
@property (readonly) BOOL isDepthTexture;
@property (readonly) NSUInteger arrayLength;
@end

@interface MTLRenderPipelineReflection : NSObject
@property (readonly) NSArray<MTLArgument *> *vertexArguments;
@property (readonly) NSArray<MTLArgument *> *fragmentArguments;
@property (readonly) NSArray<MTLArgument *> *tileArguments;
@property (readonly) NSArray *vertexBindings;
@property (readonly) NSArray *fragmentBindings;
@end
@interface MTLComputePipelineReflection : NSObject
@property (readonly) NSArray<MTLArgument *> *arguments;
@property (readonly) NSArray *bindings;
@end

@interface MTLArgumentDescriptor : NSObject <NSCopying>
+ (MTLArgumentDescriptor *)argumentDescriptor;
@property (assign) MTLDataType dataType;
@property (assign) NSUInteger index;
@property (assign) NSUInteger arrayLength;
@property (assign) MTLArgumentAccess access;
@property (assign) MTLTextureType textureType;
@property (assign) NSUInteger constantBlockAlignment;
@end

@interface MTLVertexAttributeDescriptor : NSObject <NSCopying>
@property (assign) MTLVertexFormat format;
@property (assign) NSUInteger offset;
@property (assign) NSUInteger bufferIndex;
@end
@interface MTLVertexAttributeDescriptorArray : NSObject
- (MTLVertexAttributeDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(MTLVertexAttributeDescriptor *)attributeDesc atIndexedSubscript:(NSUInteger)index;
@end
@interface MTLVertexBufferLayoutDescriptor : NSObject <NSCopying>
@property (assign) NSUInteger stride;
@property (assign) MTLVertexStepFunction stepFunction;
@property (assign) NSUInteger stepRate;
@end
@interface MTLVertexBufferLayoutDescriptorArray : NSObject
- (MTLVertexBufferLayoutDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(MTLVertexBufferLayoutDescriptor *)bufferDesc atIndexedSubscript:(NSUInteger)index;
@end
@interface MTLVertexDescriptor : NSObject <NSCopying>
+ (MTLVertexDescriptor *)vertexDescriptor;
@property (readonly) MTLVertexBufferLayoutDescriptorArray *layouts;
@property (readonly) MTLVertexAttributeDescriptorArray *attributes;
- (void)reset;
@end

@interface MTLRenderPipelineColorAttachmentDescriptor : NSObject <NSCopying>
@property (assign) MTLPixelFormat pixelFormat;
@property (assign, getter=isBlendingEnabled) BOOL blendingEnabled;
@property (assign) MTLBlendFactor sourceRGBBlendFactor;
@property (assign) MTLBlendFactor destinationRGBBlendFactor;
@property (assign) MTLBlendOperation rgbBlendOperation;
@property (assign) MTLBlendFactor sourceAlphaBlendFactor;
@property (assign) MTLBlendFactor destinationAlphaBlendFactor;
@property (assign) MTLBlendOperation alphaBlendOperation;
@property (assign) MTLColorWriteMask writeMask;
@end
@interface MTLRenderPipelineColorAttachmentDescriptorArray : NSObject
- (MTLRenderPipelineColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)attachmentIndex;
- (void)setObject:(MTLRenderPipelineColorAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)attachmentIndex;
@end
@interface MTLPipelineBufferDescriptor : NSObject <NSCopying>
@property (assign) MTLMutability mutability;
@end
@interface MTLPipelineBufferDescriptorArray : NSObject
- (MTLPipelineBufferDescriptor *)objectAtIndexedSubscript:(NSUInteger)bufferIndex;
- (void)setObject:(MTLPipelineBufferDescriptor *)buffer atIndexedSubscript:(NSUInteger)bufferIndex;
@end
@interface MTLRenderPipelineDescriptor : NSObject <NSCopying>
@property (copy, nonatomic) NSString *label;
@property (retain, nonatomic) id<MTLFunction> vertexFunction;
@property (retain, nonatomic) id<MTLFunction> fragmentFunction;
@property (copy, nonatomic) MTLVertexDescriptor *vertexDescriptor;
@property (assign) NSUInteger sampleCount;
@property (assign) NSUInteger rasterSampleCount;
@property (assign, getter=isAlphaToCoverageEnabled) BOOL alphaToCoverageEnabled;
@property (assign, getter=isAlphaToOneEnabled) BOOL alphaToOneEnabled;
@property (assign, getter=isRasterizationEnabled) BOOL rasterizationEnabled;
@property (assign) NSUInteger maxVertexAmplificationCount;
@property (readonly) MTLRenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@property (assign) MTLPixelFormat depthAttachmentPixelFormat;
@property (assign) MTLPixelFormat stencilAttachmentPixelFormat;
@property (assign) MTLPrimitiveTopologyClass inputPrimitiveTopology;
@property (assign) NSUInteger maxTessellationFactor;
@property (assign, getter=isTessellationFactorScaleEnabled) BOOL tessellationFactorScaleEnabled;
@property (assign) BOOL supportIndirectCommandBuffers;
@property (readonly) MTLPipelineBufferDescriptorArray *vertexBuffers;
@property (readonly) MTLPipelineBufferDescriptorArray *fragmentBuffers;
@property (assign) BOOL supportAddingVertexBinaryFunctions;
@property (assign) BOOL supportAddingFragmentBinaryFunctions;
@property (assign) NSUInteger maxVertexCallStackDepth;
@property (assign) NSUInteger maxFragmentCallStackDepth;
@property (assign) MTLShaderValidation shaderValidation;
- (void)reset;
@end

@interface MTLStageInputOutputDescriptor : NSObject <NSCopying>
+ (MTLStageInputOutputDescriptor *)stageInputOutputDescriptor;
@end
@interface MTLComputePipelineDescriptor : NSObject <NSCopying>
@property (copy, atomic) NSString *label;
@property (retain, nonatomic) id<MTLFunction> computeFunction;
@property (assign) BOOL threadGroupSizeIsMultipleOfThreadExecutionWidth;
@property (assign) NSUInteger maxTotalThreadsPerThreadgroup;
@property (copy, nonatomic) MTLStageInputOutputDescriptor *stageInputDescriptor;
@property (readonly) MTLPipelineBufferDescriptorArray *buffers;
@property (assign) BOOL supportIndirectCommandBuffers;
@property (assign) NSUInteger maxCallStackDepth;
@property (assign) MTLShaderValidation shaderValidation;
- (void)reset;
@end

@interface MTLRenderPassAttachmentDescriptor : NSObject <NSCopying>
@property (retain, nonatomic) id<MTLTexture> texture;
@property (assign) NSUInteger level;
@property (assign) NSUInteger slice;
@property (assign) NSUInteger depthPlane;
@property (retain, nonatomic) id<MTLTexture> resolveTexture;
@property (assign) NSUInteger resolveLevel;
@property (assign) NSUInteger resolveSlice;
@property (assign) NSUInteger resolveDepthPlane;
@property (assign) MTLLoadAction loadAction;
@property (assign) MTLStoreAction storeAction;
@property (assign) MTLStoreActionOptions storeActionOptions;
@end
@interface MTLRenderPassColorAttachmentDescriptor : MTLRenderPassAttachmentDescriptor
@property (assign) MTLClearColor clearColor;
@end
@interface MTLRenderPassDepthAttachmentDescriptor : MTLRenderPassAttachmentDescriptor
@property (assign) double clearDepth;
@property (assign) MTLMultisampleDepthResolveFilter depthResolveFilter;
@end
@interface MTLRenderPassStencilAttachmentDescriptor : MTLRenderPassAttachmentDescriptor
@property (assign) uint32_t clearStencil;
@property (assign) MTLMultisampleStencilResolveFilter stencilResolveFilter;
@end
@interface MTLRenderPassColorAttachmentDescriptorArray : NSObject
- (MTLRenderPassColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)attachmentIndex;
- (void)setObject:(MTLRenderPassColorAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)attachmentIndex;
@end
@interface MTLRenderPassDescriptor : NSObject <NSCopying>
+ (MTLRenderPassDescriptor *)renderPassDescriptor;
@property (readonly) MTLRenderPassColorAttachmentDescriptorArray *colorAttachments;
@property (copy, nonatomic) MTLRenderPassDepthAttachmentDescriptor *depthAttachment;
@property (copy, nonatomic) MTLRenderPassStencilAttachmentDescriptor *stencilAttachment;
@property (retain, nonatomic) id<MTLBuffer> visibilityResultBuffer;
@property (assign) NSUInteger renderTargetArrayLength;
@property (assign) NSUInteger imageblockSampleLength;
@property (assign) NSUInteger threadgroupMemoryLength;
@property (assign) NSUInteger tileWidth;
@property (assign) NSUInteger tileHeight;
@property (assign) NSUInteger defaultRasterSampleCount;
@property (assign) NSUInteger renderTargetWidth;
@property (assign) NSUInteger renderTargetHeight;
- (void)setSamplePositions:(const MTLSamplePosition *)positions count:(NSUInteger)count;
- (NSUInteger)getSamplePositions:(MTLSamplePosition *)positions count:(NSUInteger)count;
@end
@interface MTLComputePassDescriptor : NSObject <NSCopying>
+ (MTLComputePassDescriptor *)computePassDescriptor;
@property (assign) MTLDispatchType dispatchType;
@end
@interface MTLBlitPassDescriptor : NSObject <NSCopying>
+ (MTLBlitPassDescriptor *)blitPassDescriptor;
@end

@interface MTLTextureDescriptor : NSObject <NSCopying>
+ (MTLTextureDescriptor *)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)pixelFormat width:(NSUInteger)width
                                                      height:(NSUInteger)height mipmapped:(BOOL)mipmapped;
+ (MTLTextureDescriptor *)textureCubeDescriptorWithPixelFormat:(MTLPixelFormat)pixelFormat size:(NSUInteger)size
                                                     mipmapped:(BOOL)mipmapped;
+ (MTLTextureDescriptor *)textureBufferDescriptorWithPixelFormat:(MTLPixelFormat)pixelFormat width:(NSUInteger)width
                                                  resourceOptions:(MTLResourceOptions)resourceOptions
                                                            usage:(MTLTextureUsage)usage;
@property (assign) MTLTextureType textureType;
@property (assign) MTLPixelFormat pixelFormat;
@property (assign) NSUInteger width;
@property (assign) NSUInteger height;
@property (assign) NSUInteger depth;
@property (assign) NSUInteger mipmapLevelCount;
@property (assign) NSUInteger sampleCount;
@property (assign) NSUInteger arrayLength;
@property (assign) MTLResourceOptions resourceOptions;
@property (assign) MTLCPUCacheMode cpuCacheMode;
@property (assign) MTLStorageMode storageMode;
@property (assign) MTLHazardTrackingMode hazardTrackingMode;
@property (assign) MTLTextureUsage usage;
@property (assign) BOOL allowGPUOptimizedContents;
@property (assign) MTLTextureCompressionType compressionType;
@property (assign) MTLTextureSwizzleChannels swizzle;
@end

@interface MTLSamplerDescriptor : NSObject <NSCopying>
@property (assign) MTLSamplerMinMagFilter minFilter;
@property (assign) MTLSamplerMinMagFilter magFilter;
@property (assign) MTLSamplerMipFilter mipFilter;
@property (assign) NSUInteger maxAnisotropy;
@property (assign) MTLSamplerAddressMode sAddressMode;
@property (assign) MTLSamplerAddressMode tAddressMode;
@property (assign) MTLSamplerAddressMode rAddressMode;
@property (assign) MTLSamplerBorderColor borderColor;
@property (assign) BOOL normalizedCoordinates;
@property (assign) float lodMinClamp;
@property (assign) float lodMaxClamp;
@property (assign) BOOL lodAverage;
@property (assign) MTLCompareFunction compareFunction;
@property (assign) BOOL supportArgumentBuffers;
@property (copy, nonatomic) NSString *label;
@end

@interface MTLStencilDescriptor : NSObject <NSCopying>
@property (assign) MTLCompareFunction stencilCompareFunction;
@property (assign) MTLStencilOperation stencilFailureOperation;
@property (assign) MTLStencilOperation depthFailureOperation;
@property (assign) MTLStencilOperation depthStencilPassOperation;
@property (assign) uint32_t readMask;
@property (assign) uint32_t writeMask;
@end
@interface MTLDepthStencilDescriptor : NSObject <NSCopying>
@property (assign) MTLCompareFunction depthCompareFunction;
@property (assign, getter=isDepthWriteEnabled) BOOL depthWriteEnabled;
@property (copy, nonatomic) MTLStencilDescriptor *frontFaceStencil;
@property (copy, nonatomic) MTLStencilDescriptor *backFaceStencil;
@property (copy, nonatomic) NSString *label;
@end

@interface MTLHeapDescriptor : NSObject <NSCopying>
@property (assign) NSUInteger size;
@property (assign) MTLStorageMode storageMode;
@property (assign) MTLCPUCacheMode cpuCacheMode;
@property (assign) MTLHazardTrackingMode hazardTrackingMode;
@property (assign) MTLResourceOptions resourceOptions;
@property (assign) MTLHeapType type;
@end

@interface MTLCommandBufferDescriptor : NSObject <NSCopying>
@property (assign) BOOL retainedReferences;
@property (assign) MTLCommandBufferErrorOption errorOptions;
@end

@interface MTLIndirectCommandBufferDescriptor : NSObject <NSCopying>
@property (assign) MTLIndirectCommandType commandTypes;
@property (assign) BOOL inheritPipelineState;
@property (assign) BOOL inheritBuffers;
@property (assign) NSUInteger maxVertexBufferBindCount;
@property (assign) NSUInteger maxFragmentBufferBindCount;
@property (assign) NSUInteger maxKernelBufferBindCount;
@end

@interface MTLSharedEventListener : NSObject
- (instancetype)initWithDispatchQueue:(dispatch_queue_t)dispatchQueue;
@property (readonly) dispatch_queue_t dispatchQueue;
@end
@interface MTLSharedEventHandle : NSObject <NSSecureCoding>
@property (readonly) NSString *label;
@end
@interface MTLSharedTextureHandle : NSObject <NSSecureCoding>
@property (readonly) id<MTLDevice> device;
@property (readonly) NSString *label;
@end

/* ---- capture (no captures on Ferry: start answers an error) ---------------------- */
@protocol MTLCaptureScope <NSObject>
- (void)beginScope;
- (void)endScope;
@property (copy, atomic) NSString *label;
@property (readonly) id<MTLDevice> device;
@property (readonly) id<MTLCommandQueue> commandQueue;
@end
@interface MTLCaptureDescriptor : NSObject
@property (retain) id captureObject;
@property (assign) MTLCaptureDestination destination;
@property (copy) NSURL *outputURL;
@end
@interface MTLCaptureManager : NSObject
+ (MTLCaptureManager *)sharedCaptureManager;
- (id<MTLCaptureScope>)newCaptureScopeWithDevice:(id<MTLDevice>)device;
- (id<MTLCaptureScope>)newCaptureScopeWithCommandQueue:(id<MTLCommandQueue>)commandQueue;
- (BOOL)supportsDestination:(MTLCaptureDestination)destination;
- (BOOL)startCaptureWithDescriptor:(MTLCaptureDescriptor *)descriptor error:(NSError **)error;
- (void)startCaptureWithDevice:(id<MTLDevice>)device;
- (void)startCaptureWithCommandQueue:(id<MTLCommandQueue>)commandQueue;
- (void)startCaptureWithScope:(id<MTLCaptureScope>)captureScope;
- (void)stopCapture;
@property (retain) id<MTLCaptureScope> defaultCaptureScope;
@property (readonly) BOOL isCapturing;
@end

MTL_EXTERN id<MTLDevice> MTLCreateSystemDefaultDevice(void);
MTL_EXTERN NSArray<id<MTLDevice>> *MTLCopyAllDevices(void);
MTL_EXTERN NSArray<id<MTLDevice>> *MTLCopyAllDevicesWithObserver(id *observer, MTLDeviceNotificationHandler handler);
MTL_EXTERN void MTLRemoveDeviceObserver(id observer);

#endif
