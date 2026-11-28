/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal.framework: the device and the objects it makes (buffers,
 * textures, samplers, depth and stencil states, fences, events, heaps) and
 * their descriptors. Written from Apple's public Metal documentation. The
 * device draws on the processor ("Ferry Software Renderer"); it is there
 * when FERRY_METAL=1, or when the program itself links Metal.framework and
 * not OpenGL.framework (a program with an OpenGL path keeps using it).
 * FERRY_METAL=0 hides it. Built without ARC. */
#import "MTLObjC.h"
#import <objc/runtime.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

NSString *const MTLLibraryErrorDomain = @"MTLLibraryErrorDomain";
NSString *const MTLCommandBufferErrorDomain = @"MTLCommandBufferErrorDomain";
NSString *const MTLRenderPipelineErrorDomain = @"MTLRenderPipelineErrorDomain";
NSString *const MTLCaptureErrorDomain = @"MTLCaptureErrorDomain";
NSString *const MTLDeviceWasAddedNotification = @"MTLDeviceWasAddedNotification";
NSString *const MTLDeviceRemovalRequestedNotification = @"MTLDeviceRemovalRequestedNotification";
NSString *const MTLDeviceWasRemovedNotification = @"MTLDeviceWasRemovedNotification";
NSString *const MTLCommandBufferEncoderInfoErrorKey = @"MTLCommandBufferEncoderInfoErrorKey";

NSError *FerryMTLError(NSString *domain, NSInteger code, NSString *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[[NSString alloc] initWithFormat:fmt arguments:ap] autorelease];
    va_end(ap);
    return [NSError errorWithDomain:domain code:code userInfo:@{NSLocalizedDescriptionKey : msg}];
}

NSUInteger FerryMTLRowBytes(MTLPixelFormat f, NSUInteger width)
{
    const struct mtl_fmt *m = mtl_format((unsigned)f);
    if (!m) return width * 4;
    if (m->kind == FK_BC) return ((width + 3) / 4) * m->bpp;
    return width * m->bpp;
}

/* ---- what isn't done yet --------------------------------------------------------------- */
/* A message no Ferry Metal class implements goes to this object, whose
 * class answers every selector with a method that does nothing. */
@interface FerryMTLMissing : NSObject
@end
static id missing_imp(id self, SEL _cmd, ...) { (void)self; (void)_cmd; return nil; }
@implementation FerryMTLMissing
+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    class_addMethod(self, sel, (IMP)missing_imp, "@@:");
    return YES;
}
@end

static pthread_mutex_t noted_lock = PTHREAD_MUTEX_INITIALIZER;
static void note_missing(id obj, SEL sel)
{
    static NSMutableSet *noted;
    const char *cls = class_getName(object_getClass(obj));
    char key[512];
    snprintf(key, sizeof key, "%s %s", cls, sel_getName(sel));
    pthread_mutex_lock(&noted_lock);
    if (!noted) noted = [[NSMutableSet alloc] init];
    NSString *k = [[NSString alloc] initWithUTF8String:key];
    BOOL first = ![noted containsObject:k];
    if (first) [noted addObject:k];
    [k release];
    pthread_mutex_unlock(&noted_lock);
    if (first) mtl_log("-[%s %s] not done yet", cls, sel_getName(sel));
}

@implementation FerryMTLObject
@synthesize label = _label;
- (void)dealloc
{
    [_label release];
    [super dealloc];
}
- (id<MTLDevice>)device { return [FerryMTLDevice shared]; }
- (id)forwardingTargetForSelector:(SEL)sel
{
    const char *n = sel_getName(sel);
    /* the runtime's and Foundation's own questions are left to them */
    if (n[0] == '_' || n[0] == '.' || !strcmp(n, "methodSignatureForSelector:") || !strcmp(n, "forwardInvocation:"))
        return nil;
    note_missing(self, sel);
    static FerryMTLMissing *missing;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ missing = [[FerryMTLMissing alloc] init]; });
    return missing;
}
- (NSString *)description
{
    return _label ? [NSString stringWithFormat:@"<%s %p \"%@\">", class_getName([self class]), self, _label]
                  : [super description];
}
@end

/* ---- the device ------------------------------------------------------------------------ */
/* Whether an image links a framework; a system framework (one whose own
 * name is under /System/Library/, as Ferry's are) counts as linking none. */
static int image_links(const struct mach_header_64 *mh, const char *framework)
{
    if (!mh || mh->magic != MH_MAGIC_64) return 0;
    const char *p = (const char *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const void *)p;
        if (lc->cmd == LC_ID_DYLIB) {
            const struct dylib_command *dc = (const void *)lc;
            if (!strncmp(p + dc->dylib.name.offset, "/System/Library/", 16)) return 0;
        }
        p += lc->cmdsize;
    }
    p = (const char *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const void *)p;
        if (lc->cmd == LC_LOAD_DYLIB || lc->cmd == LC_LOAD_WEAK_DYLIB || lc->cmd == LC_REEXPORT_DYLIB) {
            const struct dylib_command *dc = (const void *)lc;
            if (strstr(p + dc->dylib.name.offset, framework)) return 1;
        }
        p += lc->cmdsize;
    }
    return 0;
}

static int program_links(const char *framework)
{
    const struct mach_header_64 *mh = (const void *)_dyld_get_image_header(0);
    if (!mh || mh->magic != MH_MAGIC_64) return 0;
    const char *p = (const char *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const void *)p;
        if (lc->cmd == LC_LOAD_DYLIB || lc->cmd == LC_LOAD_WEAK_DYLIB || lc->cmd == LC_REEXPORT_DYLIB) {
            const struct dylib_command *dc = (const void *)lc;
            const char *name = p + dc->dylib.name.offset;
            if (strstr(name, framework)) return 1;
        }
        p += lc->cmdsize;
    }
    return 0;
}

/* On or off for the whole program, or (-1) for each library that asks: a
 * program that links neither Metal nor OpenGL, such as Python, hosts the
 * library that draws (Blender's module), so that library's own links
 * decide when it asks for a device; once one has one, it stays on. */
static int metal_on = -2;

static FerryMTLDevice *device_for(const void *caller)
{
    if (metal_on == -2) {
        const char *e = getenv("FERRY_METAL");
        if (e && *e) metal_on = strcmp(e, "0") != 0;
        else if (program_links("/Metal.framework/") || program_links("/OpenGL.framework/"))
            metal_on = program_links("/Metal.framework/") && !program_links("/OpenGL.framework/");
        else
            metal_on = -1;
        if (metal_on == 1 && mtl_verbose) mtl_log("the Ferry Software Renderer is on");
    }
    if (metal_on == -1 && caller) {
        Dl_info info;
        if (dladdr(caller, &info) && image_links(info.dli_fbase, "/Metal.framework/") &&
            !image_links(info.dli_fbase, "/OpenGL.framework/")) {
            metal_on = 1;
            if (mtl_verbose) mtl_log("the Ferry Software Renderer is on, for %s", info.dli_fname);
        }
    }
    return metal_on == 1 ? [FerryMTLDevice shared] : nil;
}

FerryMTLDevice *FerryMTLDeviceIfOn(void) { return device_for(NULL); }

@implementation FerryMTLDevice
/* QuartzCore's CAMetalLayer asks for the device this way (it doesn't link Metal). */
+ (id)ferryDeviceIfOn { return FerryMTLDeviceIfOn(); }
+ (FerryMTLDevice *)shared
{
    static FerryMTLDevice *dev;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dev = [[FerryMTLDevice alloc] init]; });
    return dev;
}
- (id)retain { return self; }
- (oneway void)release {}
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return NSUIntegerMax; }

- (NSString *)name { return @"Ferry Software Renderer (Intel compatible)"; }
- (uint64_t)registryID { return 0x100000f3a7; }
- (MTLSize)maxThreadsPerThreadgroup { return MTLSizeMake(1024, 1024, 1024); }
- (BOOL)isLowPower { return NO; }
- (BOOL)isHeadless { return NO; }
- (BOOL)isRemovable { return NO; }
- (BOOL)hasUnifiedMemory { return YES; }
- (uint64_t)recommendedMaxWorkingSetSize
{
    long pages = sysconf(_SC_PHYS_PAGES), size = sysconf(_SC_PAGESIZE);
    uint64_t total = pages > 0 && size > 0 ? (uint64_t)pages * (uint64_t)size : (uint64_t)8 << 30;
    return total / 2;
}
- (MTLDeviceLocation)location { return MTLDeviceLocationBuiltIn; }
- (NSUInteger)locationNumber { return 0; }
- (uint64_t)maxTransferRate { return 0; }
- (BOOL)isDepth24Stencil8PixelFormatSupported { return YES; }
- (MTLReadWriteTextureTier)readWriteTextureSupport { return MTLReadWriteTextureTier2; }
- (MTLArgumentBuffersTier)argumentBuffersSupport { return MTLArgumentBuffersTier2; }
- (BOOL)areRasterOrderGroupsSupported { return NO; }
- (BOOL)supports32BitFloatFiltering { return YES; }
- (BOOL)supports32BitMSAA { return NO; }
- (BOOL)supportsQueryTextureLOD { return YES; }
- (BOOL)supportsBCTextureCompression { return NO; }
- (BOOL)supportsPullModelInterpolation { return NO; }
- (BOOL)areBarycentricCoordsSupported { return NO; }
- (BOOL)supportsShaderBarycentricCoordinates { return NO; }
- (NSUInteger)currentAllocatedSize { return 0; }
- (NSUInteger)maxThreadgroupMemoryLength { return 32768; }
- (NSUInteger)maxArgumentBufferSamplerCount { return 1024; }
- (BOOL)areProgrammableSamplePositionsSupported { return NO; }
- (NSUInteger)maxBufferLength { return (NSUInteger)1 << 32; }
- (uint64_t)peerGroupID { return 0; }
- (uint32_t)peerIndex { return 0; }
- (uint32_t)peerCount { return 0; }
- (NSUInteger)sparseTileSizeInBytes { return 0; }
- (BOOL)supportsDynamicLibraries { return NO; }
- (BOOL)supportsRenderDynamicLibraries { return NO; }
- (BOOL)supportsRaytracing { return NO; }
- (BOOL)supportsFunctionPointers { return NO; }
- (BOOL)supportsFunctionPointersFromRender { return NO; }
- (BOOL)supportsRaytracingFromRender { return NO; }
- (BOOL)supportsPrimitiveMotionBlur { return NO; }
- (BOOL)shouldMaximizeConcurrentCompilation { return NO; }
- (void)setShouldMaximizeConcurrentCompilation:(BOOL)value {}
- (NSUInteger)maximumConcurrentCompilationTaskCount { return 2; }
- (NSArray *)counterSets { return @[]; }
- (BOOL)supportsFamily:(MTLGPUFamily)f
{
    switch (f) {
    case MTLGPUFamilyMac1: case MTLGPUFamilyMac2: case MTLGPUFamilyCommon1: case MTLGPUFamilyCommon2:
    case MTLGPUFamilyCommon3: case MTLGPUFamilyMacCatalyst1: case MTLGPUFamilyMacCatalyst2:
        return YES;
    default:
        return NO;
    }
}
- (BOOL)supportsFeatureSet:(MTLFeatureSet)fs { return fs >= 10000 && fs <= 10005; }
- (BOOL)supportsTextureSampleCount:(NSUInteger)n { return n == 1; }
- (BOOL)supportsVertexAmplificationCount:(NSUInteger)n { return n == 1; }
- (NSUInteger)minimumLinearTextureAlignmentForPixelFormat:(MTLPixelFormat)f { return 16; }
- (NSUInteger)minimumTextureBufferAlignmentForPixelFormat:(MTLPixelFormat)f { return 16; }
- (id<MTLCommandQueue>)newCommandQueue { return [[FerryMTLCommandQueue alloc] init]; }
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)n { return [self newCommandQueue]; }

static size_t texture_bytes(MTLTextureDescriptor *d)
{
    struct __ferry_tex t;
    memset(&t, 0, sizeof t);
    t.f = mtl_format((unsigned)d.pixelFormat);
    if (!t.f) t.f = mtl_format(MTLPixelFormatRGBA8Unorm);
    t.type = (unsigned)d.textureType;
    t.w = (unsigned)(d.width ? d.width : 1);
    t.h = (unsigned)(d.height ? d.height : 1);
    t.d = (unsigned)(d.depth ? d.depth : 1);
    t.levels = (unsigned)(d.mipmapLevelCount ? d.mipmapLevelCount : 1);
    t.layers = (unsigned)((d.arrayLength ? d.arrayLength : 1) *
                          (d.textureType == MTLTextureTypeCube || d.textureType == MTLTextureTypeCubeArray ? 6 : 1));
    return mtl_tex_layout(&t, 0);
}
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)d
{
    MTLSizeAndAlign r = {(texture_bytes(d) + 255) & ~(NSUInteger)255, 256};
    return r;
}
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{
    MTLSizeAndAlign r = {(length + 255) & ~(NSUInteger)255, 256};
    return r;
}
- (id<MTLHeap>)newHeapWithDescriptor:(MTLHeapDescriptor *)d
{
    id h = [[NSClassFromString(@"FerryMTLHeap") alloc] init];
    [h setValue:@(d.size) forKey:@"ferrySize"];
    return h;
}

static FerryMTLBuffer *new_buffer(NSUInteger length, MTLResourceOptions options)
{
    FerryMTLBuffer *b = [[FerryMTLBuffer alloc] init];
    void *p = NULL;
    size_t n = length ? length : 1;
    if (posix_memalign(&p, 256, (n + 255) & ~(size_t)255)) {
        [b release];
        mtl_log("out of memory for a buffer of %lu bytes", (unsigned long)length);
        return nil;
    }
    memset(p, 0, n);
    b->_contents = p;
    b->_length = length;
    b->_options = options;
    return b;
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{
    return new_buffer(length, options);
}
- (id<MTLBuffer>)newBufferWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options
{
    FerryMTLBuffer *b = new_buffer(length, options);
    if (b && pointer && length) memcpy(b->_contents, pointer, length);
    return b;
}
- (id<MTLBuffer>)newBufferWithBytesNoCopy:(void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options
                              deallocator:(void (^)(void *, NSUInteger))deallocator
{
    FerryMTLBuffer *b = [[FerryMTLBuffer alloc] init];
    b->_contents = pointer;
    b->_length = length;
    b->_options = options;
    b->_deallocator = deallocator ? [deallocator copy] : [^(void *p, NSUInteger n) {} copy];
    return b;
}
- (id<MTLDepthStencilState>)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)d
{
    FerryMTLDepthStencilState *s = [[FerryMTLDepthStencilState alloc] init];
    s->_label = [d.label copy];
    s->_ds.depth_func = (unsigned char)d.depthCompareFunction;
    s->_ds.depth_write = d.isDepthWriteEnabled;
    MTLStencilDescriptor *f[2] = {d.frontFaceStencil, d.backFaceStencil};
    struct mtl_stencil_face *o[2] = {&s->_ds.front, &s->_ds.back};
    for (int i = 0; i < 2; i++) {
        if (f[i]) {
            o[i]->func = (unsigned char)f[i].stencilCompareFunction;
            o[i]->fail = (unsigned char)f[i].stencilFailureOperation;
            o[i]->zfail = (unsigned char)f[i].depthFailureOperation;
            o[i]->pass = (unsigned char)f[i].depthStencilPassOperation;
            o[i]->read_mask = f[i].readMask;
            o[i]->write_mask = f[i].writeMask;
            s->_ds.stencil_enabled = 1;
        } else {
            o[i]->func = MTLCompareFunctionAlways;
            o[i]->read_mask = o[i]->write_mask = 0xff;
        }
    }
    return s;
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d { return FerryMTLNewTexture(d, NULL, 0); }
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d iosurface:(void *)iosurface plane:(NSUInteger)plane
{
    FerryMTLTexture *t = FerryMTLNewTexture(d, NULL, 0);
    if (t) { t->_iosurface = iosurface; t->_plane = plane; }
    return t;
}
- (id<MTLTexture>)newSharedTextureWithDescriptor:(MTLTextureDescriptor *)d { return FerryMTLNewTexture(d, NULL, 0); }
- (id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)d
{
    FerryMTLSampler *s = [[FerryMTLSampler alloc] init];
    s->_label = [d.label copy];
    s->_s.normalized = d.normalizedCoordinates;
    s->_s.s_address = (unsigned char)d.sAddressMode;
    s->_s.t_address = (unsigned char)d.tAddressMode;
    s->_s.r_address = (unsigned char)d.rAddressMode;
    s->_s.mag_filter = (unsigned char)d.magFilter;
    s->_s.min_filter = (unsigned char)d.minFilter;
    s->_s.mip_filter = (unsigned char)d.mipFilter;
    /* a sampler that never compares (the descriptor's Never, its default)
     * reads plain values */
    s->_s.compare = d.compareFunction == MTLCompareFunctionNever ? FERRY_CMP_NONE : (unsigned char)d.compareFunction;
    s->_s.border = (unsigned char)d.borderColor;
    s->_s.max_anisotropy = (unsigned char)(d.maxAnisotropy > 255 ? 255 : d.maxAnisotropy);
    s->_s.lod_min = d.lodMinClamp;
    s->_s.lod_max = d.lodMaxClamp;
    return s;
}

/* Libraries: compiled from source by ferry-mslc, or rebuilt from a
 * precompiled .metallib's bitcode by ferry-airc (MTLLibrary.m). */
id<MTLLibrary> FerryMTLNewLibraryWithSource(NSString *source, MTLCompileOptions *options, NSError **error);
id<MTLLibrary> FerryMTLNewLibraryWithMetallib(NSData *bytes, NSString *what, NSError **error);
static NSString *default_metallib(NSBundle *bundle)
{
    NSString *p = [bundle pathForResource:@"default" ofType:@"metallib"];
    if (!p) p = [[bundle resourcePath] stringByAppendingPathComponent:@"default.metallib"];
    return [[NSFileManager defaultManager] fileExistsAtPath:p] ? p : nil;
}
- (id<MTLLibrary>)newDefaultLibrary
{
    return [self newDefaultLibraryWithBundle:[NSBundle mainBundle] error:NULL];
}
- (id<MTLLibrary>)newDefaultLibraryWithBundle:(NSBundle *)bundle error:(NSError **)error
{
    NSString *p = default_metallib(bundle ? bundle : [NSBundle mainBundle]);
    if (!p) {
        mtl_log("the program has no default.metallib");
        if (error)
            *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorFileNotFound, @"no default library was found");
        return nil;
    }
    return [self newLibraryWithFile:p error:error];
}
- (id<MTLLibrary>)newLibraryWithFile:(NSString *)path error:(NSError **)error
{
    NSData *d = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (!d) {
        if (error)
            *error = FerryMTLError(MTLLibraryErrorDomain, MTLLibraryErrorFileNotFound, @"%@ couldn't be read", path);
        return nil;
    }
    return FerryMTLNewLibraryWithMetallib(d, [path lastPathComponent], error);
}
- (id<MTLLibrary>)newLibraryWithURL:(NSURL *)url error:(NSError **)error
{
    return [self newLibraryWithFile:[url path] error:error];
}
- (id<MTLLibrary>)newLibraryWithData:(id)data error:(NSError **)error
{
    /* dispatch data, or an NSData */
    NSData *d = nil;
    if ([data isKindOfClass:[NSData class]]) {
        d = data;
    } else if (data) {
        const void *buf = NULL;
        size_t size = 0;
        dispatch_data_t map = dispatch_data_create_map((dispatch_data_t)data, &buf, &size);
        d = [NSData dataWithBytes:buf length:size];
        dispatch_release(map);
    }
    return FerryMTLNewLibraryWithMetallib(d, @"the program's Metal library", error);
}
- (id<MTLLibrary>)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options error:(NSError **)error
{
    return FerryMTLNewLibraryWithSource(source, options, error);
}
- (void)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options
           completionHandler:(MTLNewLibraryCompletionHandler)handler
{
    source = [source copy];
    options = [options copy];
    handler = [handler copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSError *err = nil;
      id<MTLLibrary> lib = FerryMTLNewLibraryWithSource(source, options, &err);
      handler(lib, err);
      [lib release];
      [source release];
      [options release];
      [handler release];
    });
}

id<MTLRenderPipelineState> FerryMTLNewRenderPipeline(MTLRenderPipelineDescriptor *d, MTLPipelineOption options,
                                                     MTLRenderPipelineReflection **refl, NSError **error);
id<MTLComputePipelineState> FerryMTLNewComputePipeline(id<MTLFunction> f, MTLComputePipelineDescriptor *d,
                                                       MTLPipelineOption options, MTLComputePipelineReflection **refl,
                                                       NSError **error);
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d error:(NSError **)e
{
    return FerryMTLNewRenderPipeline(d, 0, NULL, e);
}
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d
                                                           options:(MTLPipelineOption)options
                                                        reflection:(MTLAutoreleasedRenderPipelineReflection *)r
                                                             error:(NSError **)e
{
    return FerryMTLNewRenderPipeline(d, options, r, e);
}
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d
                           completionHandler:(MTLNewRenderPipelineStateCompletionHandler)handler
{
    NSError *err = nil;
    id<MTLRenderPipelineState> p = FerryMTLNewRenderPipeline(d, 0, NULL, &err);
    handler(p, err);
    [p release];
}
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d options:(MTLPipelineOption)options
                           completionHandler:(MTLNewRenderPipelineStateWithReflectionCompletionHandler)handler
{
    NSError *err = nil;
    MTLRenderPipelineReflection *r = nil;
    id<MTLRenderPipelineState> p = FerryMTLNewRenderPipeline(d, options, &r, &err);
    handler(p, r, err);
    [p release];
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)f error:(NSError **)e
{
    return FerryMTLNewComputePipeline(f, nil, 0, NULL, e);
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)f options:(MTLPipelineOption)o
                                                        reflection:(MTLAutoreleasedComputePipelineReflection *)r
                                                             error:(NSError **)e
{
    return FerryMTLNewComputePipeline(f, nil, o, r, e);
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)d
                                                             options:(MTLPipelineOption)o
                                                          reflection:(MTLAutoreleasedComputePipelineReflection *)r
                                                               error:(NSError **)e
{
    return FerryMTLNewComputePipeline(d.computeFunction, d, o, r, e);
}
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)f
                          completionHandler:(MTLNewComputePipelineStateCompletionHandler)handler
{
    NSError *err = nil;
    id<MTLComputePipelineState> p = FerryMTLNewComputePipeline(f, nil, 0, NULL, &err);
    handler(p, err);
    [p release];
}
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)f options:(MTLPipelineOption)o
                          completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)handler
{
    NSError *err = nil;
    MTLComputePipelineReflection *r = nil;
    id<MTLComputePipelineState> p = FerryMTLNewComputePipeline(f, nil, o, &r, &err);
    handler(p, r, err);
    [p release];
}
/* freemac Godot work: MoltenVK makes its pipelines this way */
- (void)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)d options:(MTLPipelineOption)o
                            completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)handler
{
    NSError *err = nil;
    MTLComputePipelineReflection *r = nil;
    id<MTLComputePipelineState> p = FerryMTLNewComputePipeline(d.computeFunction, d, o, &r, &err);
    handler(p, r, err);
    [p release];
}
- (id<MTLFence>)newFence { return [[NSClassFromString(@"FerryMTLFence") alloc] init]; }
- (id<MTLEvent>)newEvent { return [[NSClassFromString(@"FerryMTLSharedEvent") alloc] init]; }
- (id<MTLSharedEvent>)newSharedEvent { return [[NSClassFromString(@"FerryMTLSharedEvent") alloc] init]; }
- (id<MTLSharedEvent>)newSharedEventWithHandle:(MTLSharedEventHandle *)h { return [self newSharedEvent]; }
id<MTLArgumentEncoder> FerryMTLNewArgumentEncoder(NSArray *arguments);
- (id<MTLArgumentEncoder>)newArgumentEncoderWithArguments:(NSArray<MTLArgumentDescriptor *> *)arguments
{
    return FerryMTLNewArgumentEncoder(arguments);
}
- (id<MTLIndirectCommandBuffer>)newIndirectCommandBufferWithDescriptor:(MTLIndirectCommandBufferDescriptor *)d
                                                        maxCommandCount:(NSUInteger)n
                                                                options:(MTLResourceOptions)o
{
    mtl_log("indirect command buffers aren't done yet");
    return nil;
}
- (void)getDefaultSamplePositions:(MTLSamplePosition *)positions count:(NSUInteger)count
{
    for (NSUInteger i = 0; i < count; i++) positions[i] = MTLSamplePositionMake(0.5f, 0.5f);
}
- (void)sampleTimestamps:(MTLTimestamp *)cpu gpuTimestamp:(MTLTimestamp *)gpu
{
    uint64_t t = mach_absolute_time();
    if (cpu) *cpu = t;
    if (gpu) *gpu = t;
}
@end

id<MTLDevice> MTLCreateSystemDefaultDevice(void) { return device_for(__builtin_return_address(0)); }
static NSArray<id<MTLDevice>> *all_devices(const void *caller)
{
    FerryMTLDevice *d = device_for(caller);
    return d ? [[NSArray alloc] initWithObjects:d, nil] : [[NSArray alloc] init];
}
NSArray<id<MTLDevice>> *MTLCopyAllDevices(void) { return all_devices(__builtin_return_address(0)); }
NSArray<id<MTLDevice>> *MTLCopyAllDevicesWithObserver(id *observer, MTLDeviceNotificationHandler handler)
{
    if (observer) *observer = [[NSObject alloc] init];
    return all_devices(__builtin_return_address(0));
}
void MTLRemoveDeviceObserver(id observer) { [observer release]; }

/* ---- buffers --------------------------------------------------------------------------- */
@implementation FerryMTLBuffer
- (void)dealloc
{
    if (_deallocator) {
        _deallocator(_contents, _length);
        [_deallocator release];
    } else if (!_heap)
        free(_contents);
    [_heap release];
    [super dealloc];
}
- (NSUInteger)length { return _length; }
- (uint64_t)gpuAddress { return (uint64_t)(uintptr_t)_contents; }
- (void *)contents { return _contents; }
- (void)didModifyRange:(NSRange)range {}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d offset:(NSUInteger)offset
                               bytesPerRow:(NSUInteger)bytesPerRow
{
    FerryMTLTexture *t = FerryMTLNewTexture(d, _contents + offset, bytesPerRow);
    if (t) {
        t->_buffer = [self retain];
        t->_bufferOffset = offset;
        t->_bufferRow = bytesPerRow;
    }
    return t;
}
- (void)addDebugMarker:(NSString *)marker range:(NSRange)range {}
- (void)removeAllDebugMarkers {}
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)(_options & 0xf); }
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_options >> 4) & 0xf); }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((_options >> 8) & 0xf); }
- (MTLResourceOptions)resourceOptions { return _options; }
- (id<MTLHeap>)heap { return _heap; }
- (NSUInteger)heapOffset { return 0; }
- (NSUInteger)allocatedSize { return (_length + 255) & ~(NSUInteger)255; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (MTLResourceID)gpuResourceID { MTLResourceID r = {(uint64_t)(uintptr_t)_contents}; return r; }
@end

/* ---- textures -------------------------------------------------------------------------- */
FerryMTLTexture *FerryMTLNewTexture(MTLTextureDescriptor *d, char *mem, NSUInteger bytesPerRow)
{
    FerryMTLTexture *tex = [[FerryMTLTexture alloc] init];
    struct __ferry_tex *t = &tex->_t;
    t->f = mtl_format((unsigned)d.pixelFormat);
    if (!t->f) {
        mtl_log("pixel format %lu isn't done yet; using RGBA8Unorm", (unsigned long)d.pixelFormat);
        t->f = mtl_format(MTLPixelFormatRGBA8Unorm);
    }
    t->type = (unsigned)d.textureType;
    t->w = (unsigned)(d.width ? d.width : 1);
    t->h = (unsigned)(d.height ? d.height : 1);
    t->d = (unsigned)(d.depth ? d.depth : 1);
    t->levels = (unsigned)(d.mipmapLevelCount ? d.mipmapLevelCount : 1);
    t->layers = (unsigned)((d.arrayLength ? d.arrayLength : 1) *
                           (t->type == MTLTextureTypeCube || t->type == MTLTextureTypeCubeArray ? 6 : 1));
    t->samples = 1; /* (multisampled textures keep one sample) */
    MTLTextureSwizzleChannels s = d.swizzle;
    t->swz[0] = s.red; t->swz[1] = s.green; t->swz[2] = s.blue; t->swz[3] = s.alpha;
    t->identity_swz = s.red == 2 && s.green == 3 && s.blue == 4 && s.alpha == 5;
    size_t bytes = mtl_tex_layout(t, bytesPerRow);
    if (mem)
        t->base = mem;
    else {
        void *p = NULL;
        if (posix_memalign(&p, 64, bytes ? bytes : 64)) {
            mtl_log("out of memory for a %ux%u texture", t->w, t->h);
            [tex release];
            return nil;
        }
        memset(p, 0, bytes);
        tex->_mem = p;
        t->base = p;
    }
    tex->_usage = d.usage;
    tex->_options = d.resourceOptions;
    return tex;
}

@implementation FerryMTLTexture
- (void)dealloc
{
    free(_mem);
    [_parent release];
    [_buffer release];
    [_heap release];
    [super dealloc];
}
- (struct __ferry_tex *)ferryTex { return &_t; }
- (id<MTLResource>)rootResource { return _parent ? [_parent rootResource] : _buffer ? (id)_buffer : (id)self; }
- (id<MTLTexture>)parentTexture { return _parent; }
- (NSUInteger)parentRelativeLevel { return _parentLevel; }
- (NSUInteger)parentRelativeSlice { return _parentSlice; }
- (id<MTLBuffer>)buffer { return _buffer; }
- (NSUInteger)bufferOffset { return _bufferOffset; }
- (NSUInteger)bufferBytesPerRow { return _bufferRow; }
- (MTLTextureType)textureType { return _t.type; }
- (MTLPixelFormat)pixelFormat { return _t.f->fmt; }
- (NSUInteger)width { return _t.w; }
- (NSUInteger)height { return _t.h; }
- (NSUInteger)depth { return _t.d; }
- (NSUInteger)mipmapLevelCount { return _t.levels; }
- (NSUInteger)sampleCount { return 1; }
- (NSUInteger)arrayLength
{
    return _t.type == MTLTextureTypeCube || _t.type == MTLTextureTypeCubeArray ? _t.layers / 6 : _t.layers;
}
- (MTLTextureUsage)usage { return _usage; }
- (BOOL)isShareable { return NO; }
- (BOOL)isFramebufferOnly { return _framebufferOnly; }
- (NSUInteger)firstMipmapInTail { return 0; }
- (NSUInteger)tailSizeInBytes { return 0; }
- (BOOL)isSparse { return NO; }
- (BOOL)allowGPUOptimizedContents { return YES; }
- (MTLTextureSwizzleChannels)swizzle
{
    return MTLTextureSwizzleChannelsMake(_t.swz[0], _t.swz[1], _t.swz[2], _t.swz[3]);
}
- (MTLResourceID)gpuResourceID { MTLResourceID r = {(uint64_t)(uintptr_t)&_t}; return r; }
- (void *)iosurface { return _iosurface; }
- (NSUInteger)iosurfacePlane { return _plane; }
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)(_options & 0xf); }
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_options >> 4) & 0xf); }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((_options >> 8) & 0xf); }
- (MTLResourceOptions)resourceOptions { return _options; }
- (id<MTLHeap>)heap { return _heap; }
- (NSUInteger)heapOffset { return 0; }
- (NSUInteger)allocatedSize
{
    struct __ferry_tex c = _t;
    return _mem ? mtl_tex_layout(&c, 0) : 0;
}
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }

/* Copy rows of texels between the texture and memory laid out the
 * caller's way. BC formats copy whole 4x4 blocks. */
static void copy_region(struct __ferry_tex *t, MTLRegion r, NSUInteger level, NSUInteger slice, char *mem,
                        NSUInteger row, NSUInteger image, int to_texture)
{
    if (level >= t->levels || slice >= t->layers) return;
    int bc = t->f->kind == FK_BC;
    NSUInteger x = r.origin.x, y = r.origin.y, w = r.size.width, h = r.size.height;
    if (bc) { x /= 4; y /= 4; w = (w + 3) / 4; h = (h + 3) / 4; }
    NSUInteger lw = bc ? (t->lw[level] + 3) / 4 : t->lw[level], lh = bc ? (t->lh[level] + 3) / 4 : t->lh[level];
    if (x >= lw || (y >= lh && t->type != MTLTextureType1DArray)) return;
    if (x + w > lw) w = lw - x;
    if (t->type != MTLTextureType1D && t->type != MTLTextureType1DArray && t->type != MTLTextureTypeTextureBuffer &&
        y + h > lh)
        h = lh - y;
    size_t bpp = t->f->bpp, bytes = w * bpp;
    if (!row) row = bytes;
    if (!image) image = row * h;
    for (NSUInteger z = 0; z < r.size.depth; z++) {
        NSUInteger zz = r.origin.z + z, layer = slice;
        if (t->type == MTLTextureType3D) {
            if (zz >= t->ld[level]) break;
        } else if (r.size.depth > 1) {
            layer = slice + z;  /* (several slices at once) */
            zz = 0;
            if (layer >= t->layers) break;
        } else
            zz = 0;
        for (NSUInteger j = 0; j < h; j++) {
            char *tp = t->base + t->off[level] + layer * t->layer_size[level] + zz * t->img[level] +
                       (y + j) * t->row[level] + x * bpp;
            char *mp = mem + z * image + j * row;
            if (to_texture) memcpy(tp, mp, bytes);
            else memcpy(mp, tp, bytes);
        }
    }
}
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image fromRegion:(MTLRegion)r
     mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice
{
    copy_region(&_t, r, level, slice, bytes, row, image, 0);
}
- (void)replaceRegion:(MTLRegion)r mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice
            withBytes:(const void *)bytes bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image
{
    copy_region(&_t, r, level, slice, (char *)bytes, row, image, 1);
}
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)row fromRegion:(MTLRegion)r mipmapLevel:(NSUInteger)level
{
    copy_region(&_t, r, level, 0, bytes, row, 0, 0);
}
- (void)replaceRegion:(MTLRegion)r mipmapLevel:(NSUInteger)level withBytes:(const void *)bytes
          bytesPerRow:(NSUInteger)row
{
    copy_region(&_t, r, level, 0, (char *)bytes, row, 0, 1);
}

- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pf textureType:(MTLTextureType)type
                                         levels:(NSRange)levels slices:(NSRange)slices
                                        swizzle:(MTLTextureSwizzleChannels)s
{
    FerryMTLTexture *v = [[FerryMTLTexture alloc] init];
    struct __ferry_tex *t = &v->_t;
    *t = _t;
    const struct mtl_fmt *f = mtl_format((unsigned)pf);
    if (f && f->bpp == _t.f->bpp) t->f = f;
    else if (f) {
        /* a depth and stencil format seen as its stencil alone, and the like */
        if (mtl_verbose) mtl_log("a view of %s as %s, which has a different size", _t.f->name, f->name);
        t->f = f;
    }
    t->type = (unsigned)type;
    NSUInteger l0 = levels.location < _t.levels ? levels.location : 0;
    NSUInteger nl = levels.length ? levels.length : 1;
    if (l0 + nl > _t.levels) nl = _t.levels - l0;
    NSUInteger s0 = slices.location < _t.layers ? slices.location : 0;
    NSUInteger ns = slices.length ? slices.length : 1;
    if (s0 + ns > _t.layers) ns = _t.layers - s0;
    t->levels = (unsigned)nl;
    t->layers = (unsigned)ns;
    for (NSUInteger l = 0; l < nl; l++) {
        NSUInteger pl = l0 + l;
        t->off[l] = _t.off[pl] + s0 * _t.layer_size[pl];
        t->layer_size[l] = _t.layer_size[pl];
        t->img[l] = _t.img[pl];
        t->row[l] = _t.row[pl];
        t->lw[l] = _t.lw[pl];
        t->lh[l] = _t.lh[pl];
        t->ld[l] = _t.ld[pl];
    }
    t->w = _t.lw[l0];
    t->h = _t.lh[l0];
    t->d = _t.ld[l0];
    /* the view's swizzle applies over this texture's own */
    unsigned char own[4] = {_t.swz[0], _t.swz[1], _t.swz[2], _t.swz[3]};
    unsigned char sw[4] = {s.red, s.green, s.blue, s.alpha};
    for (int i = 0; i < 4; i++) t->swz[i] = sw[i] >= 2 ? own[(sw[i] - 2) & 3] : sw[i];
    t->identity_swz = t->swz[0] == 2 && t->swz[1] == 3 && t->swz[2] == 4 && t->swz[3] == 5;
    v->_parent = [self retain];
    v->_parentLevel = l0;
    v->_parentSlice = s0;
    v->_usage = _usage;
    v->_options = _options;
    return v;
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pf textureType:(MTLTextureType)type
                                         levels:(NSRange)levels slices:(NSRange)slices
{
    return [self newTextureViewWithPixelFormat:pf textureType:type levels:levels slices:slices
                                       swizzle:MTLTextureSwizzleChannelsDefault];
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pf
{
    return [self newTextureViewWithPixelFormat:pf textureType:_t.type levels:NSMakeRange(0, _t.levels)
                                        slices:NSMakeRange(0, _t.layers)];
}
- (MTLSharedTextureHandle *)newSharedTextureHandle { return nil; }
@end

/* ---- samplers, depth and stencil states, fences, events, heaps ------------------------- */
@implementation FerryMTLSampler
- (MTLResourceID)gpuResourceID { MTLResourceID r = {(uint64_t)(uintptr_t)&_s}; return r; }
@end
@implementation FerryMTLDepthStencilState
@end

@interface FerryMTLFence : FerryMTLObject <MTLFence>
@end
@implementation FerryMTLFence
@end

@interface FerryMTLSharedEvent : FerryMTLObject <MTLSharedEvent> {
    uint64_t _value;
    pthread_mutex_t _lock;
    pthread_cond_t _cond;
    NSMutableArray *_waiters;
}
@end
@implementation FerryMTLSharedEvent
- (instancetype)init
{
    if ((self = [super init])) {
        pthread_mutex_init(&_lock, NULL);
        pthread_cond_init(&_cond, NULL);
        _waiters = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_waiters release];
    pthread_mutex_destroy(&_lock);
    pthread_cond_destroy(&_cond);
    [super dealloc];
}
- (uint64_t)signaledValue
{
    pthread_mutex_lock(&_lock);
    uint64_t v = _value;
    pthread_mutex_unlock(&_lock);
    return v;
}
- (void)setSignaledValue:(uint64_t)v
{
    NSMutableArray *due = [NSMutableArray array];
    pthread_mutex_lock(&_lock);
    _value = v;
    for (NSArray *w in [[_waiters copy] autorelease])
        if ([w[0] unsignedLongLongValue] <= v) {
            [due addObject:w];
            [_waiters removeObjectIdenticalTo:w];
        }
    pthread_cond_broadcast(&_cond);
    pthread_mutex_unlock(&_lock);
    for (NSArray *w in due) {
        MTLSharedEventListener *l = w[1];
        MTLSharedEventNotificationBlock b = w[2];
        dispatch_queue_t q = [l dispatchQueue] ? [l dispatchQueue] : dispatch_get_global_queue(0, 0);
        [self retain];
        dispatch_async(q, ^{
          b(self, v);
          [self release];
        });
    }
}
- (void)notifyListener:(MTLSharedEventListener *)listener atValue:(uint64_t)value
                 block:(MTLSharedEventNotificationBlock)block
{
    if (!listener) listener = [[[MTLSharedEventListener alloc] init] autorelease];
    NSArray *w = @[@(value), listener, [[block copy] autorelease]];
    pthread_mutex_lock(&_lock);
    BOOL now = _value >= value;
    if (!now) [_waiters addObject:w];
    pthread_mutex_unlock(&_lock);
    if (now) {
        dispatch_queue_t q = [listener dispatchQueue] ? [listener dispatchQueue] : dispatch_get_global_queue(0, 0);
        uint64_t v = _value;
        MTLSharedEventNotificationBlock b = w[2];
        [self retain];
        [w retain];
        dispatch_async(q, ^{
          b(self, v);
          [w release];
          [self release];
        });
    }
}
- (MTLSharedEventHandle *)newSharedEventHandle { return [[MTLSharedEventHandle alloc] init]; }
- (BOOL)waitUntilSignaledValue:(uint64_t)value timeoutMS:(uint64_t)ms
{
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += (time_t)(ms / 1000);
    ts.tv_nsec += (long)(ms % 1000) * 1000000;
    if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
    pthread_mutex_lock(&_lock);
    int rc = 0;
    while (_value < value && rc == 0) rc = pthread_cond_timedwait(&_cond, &_lock, &ts);
    BOOL ok = _value >= value;
    pthread_mutex_unlock(&_lock);
    return ok;
}
@end

@interface FerryMTLHeap : FerryMTLObject <MTLHeap> {
    NSUInteger _size, _used;
}
@end
@implementation FerryMTLHeap
- (void)setFerrySize:(NSNumber *)n { _size = [n unsignedIntegerValue]; }
- (void)setValue:(id)v forKey:(NSString *)k
{
    if ([k isEqualToString:@"ferrySize"]) [self setFerrySize:v];
    else [super setValue:v forKey:k];
}
- (MTLStorageMode)storageMode { return MTLStorageModePrivate; }
- (MTLCPUCacheMode)cpuCacheMode { return MTLCPUCacheModeDefaultCache; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeDefault; }
- (MTLResourceOptions)resourceOptions { return MTLResourceStorageModePrivate; }
- (NSUInteger)size { return _size; }
- (NSUInteger)usedSize { return _used; }
- (NSUInteger)currentAllocatedSize { return _size; }
- (MTLHeapType)type { return MTLHeapTypeAutomatic; }
- (NSUInteger)maxAvailableSizeWithAlignment:(NSUInteger)alignment { return _size > _used ? _size - _used : 0; }
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{
    _used += (length + 255) & ~(NSUInteger)255;
    return [[FerryMTLDevice shared] newBufferWithLength:length options:options];
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)d
{
    _used += texture_bytes(d);
    return FerryMTLNewTexture(d, NULL, 0);
}
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
@end

/* ---- descriptors ----------------------------------------------------------------------- */
/* A copy of a descriptor: its values, with the objects it holds retained
 * (a copy of a descriptor keeps the same texture, function and so on). */
id FerryMTLCopyDescriptor(id self, NSZone *zone)
{
    Class c = object_getClass(self);
    id copy = [[c allocWithZone:zone] init];
    for (Class k = c; k && k != [NSObject class]; k = class_getSuperclass(k)) {
        unsigned n = 0;
        Ivar *iv = class_copyIvarList(k, &n);
        for (unsigned i = 0; i < n; i++) {
            const char *type = ivar_getTypeEncoding(iv[i]);
            ptrdiff_t off = ivar_getOffset(iv[i]);
            char *dst = (char *)copy + off, *src = (char *)self + off;
            if (type && type[0] == '@') {
                id old = *(id *)dst, val = *(id *)src;
                /* arrays of sub-descriptors are copied whole */
                if ([val respondsToSelector:@selector(ferryDeepCopy)]) val = [val performSelector:@selector(ferryDeepCopy)];
                else if ([val isKindOfClass:[NSMutableArray class]] || [val isKindOfClass:[NSMutableDictionary class]])
                    val = [val mutableCopy];
                else if ([val isKindOfClass:[NSString class]] || [val isKindOfClass:[NSArray class]] ||
                         [val isKindOfClass:[NSDictionary class]])
                    val = [val copy];
                /* a descriptor inside a descriptor (a vertex descriptor, constant values) is copied too */
                else if (val && !strncmp(class_getName(object_getClass(val)), "MTL", 3) &&
                         [val respondsToSelector:@selector(copyWithZone:)])
                    val = [val copy];
                else
                    val = [val retain];
                *(id *)dst = val;
                [old release];
            } else if (type) {
                NSUInteger size = 0, align = 0;
                NSGetSizeAndAlignment(type, &size, &align);
                if (size) memcpy(dst, src, size);
            }
        }
        free(iv);
    }
    return copy;
}
/* Release every object a descriptor holds. */
void FerryMTLReleaseIvars(id self)
{
    for (Class k = object_getClass(self); k && k != [NSObject class]; k = class_getSuperclass(k)) {
        unsigned n = 0;
        Ivar *iv = class_copyIvarList(k, &n);
        for (unsigned i = 0; i < n; i++) {
            const char *type = ivar_getTypeEncoding(iv[i]);
            if (type && type[0] == '@') {
                id *p = (id *)((char *)self + ivar_getOffset(iv[i]));
                [*p release];
                *p = nil;
            }
        }
        free(iv);
    }
}

@implementation MTLTextureDescriptor
@synthesize textureType = _textureType, pixelFormat = _pixelFormat, width = _width, height = _height, depth = _depth,
            mipmapLevelCount = _mipmapLevelCount, sampleCount = _sampleCount, arrayLength = _arrayLength,
            resourceOptions = _resourceOptions, usage = _usage, allowGPUOptimizedContents = _allowGPUOptimizedContents,
            compressionType = _compressionType, swizzle = _swizzle;
- (instancetype)init
{
    if ((self = [super init])) {
        _textureType = MTLTextureType2D;
        _pixelFormat = MTLPixelFormatRGBA8Unorm;
        _width = _height = _depth = 1;
        _mipmapLevelCount = _sampleCount = _arrayLength = 1;
        _usage = MTLTextureUsageShaderRead;
        _allowGPUOptimizedContents = YES;
        _swizzle = MTLTextureSwizzleChannelsDefault;
    }
    return self;
}
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
+ (MTLTextureDescriptor *)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)pf width:(NSUInteger)w
                                                      height:(NSUInteger)h mipmapped:(BOOL)mipmapped
{
    MTLTextureDescriptor *d = [[[self alloc] init] autorelease];
    d.pixelFormat = pf;
    d.width = w;
    d.height = h;
    if (mipmapped) {
        NSUInteger m = w > h ? w : h, n = 1;
        while (m > 1) { m >>= 1; n++; }
        d.mipmapLevelCount = n;
    }
    return d;
}
+ (MTLTextureDescriptor *)textureCubeDescriptorWithPixelFormat:(MTLPixelFormat)pf size:(NSUInteger)size
                                                     mipmapped:(BOOL)mipmapped
{
    MTLTextureDescriptor *d = [self texture2DDescriptorWithPixelFormat:pf width:size height:size mipmapped:mipmapped];
    d.textureType = MTLTextureTypeCube;
    return d;
}
+ (MTLTextureDescriptor *)textureBufferDescriptorWithPixelFormat:(MTLPixelFormat)pf width:(NSUInteger)w
                                                  resourceOptions:(MTLResourceOptions)options
                                                            usage:(MTLTextureUsage)usage
{
    MTLTextureDescriptor *d = [[[self alloc] init] autorelease];
    d.textureType = MTLTextureTypeTextureBuffer;
    d.pixelFormat = pf;
    d.width = w;
    d.resourceOptions = options;
    d.usage = usage;
    return d;
}
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)(_resourceOptions & 0xf); }
- (void)setCpuCacheMode:(MTLCPUCacheMode)m { _resourceOptions = (_resourceOptions & ~(NSUInteger)0xf) | m; }
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_resourceOptions >> 4) & 0xf); }
- (void)setStorageMode:(MTLStorageMode)m { _resourceOptions = (_resourceOptions & ~(NSUInteger)0xf0) | (m << 4); }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((_resourceOptions >> 8) & 0xf); }
- (void)setHazardTrackingMode:(MTLHazardTrackingMode)m
{
    _resourceOptions = (_resourceOptions & ~(NSUInteger)0xf00) | (m << 8);
}
@end

@implementation MTLSamplerDescriptor
@synthesize minFilter = _minFilter, magFilter = _magFilter, mipFilter = _mipFilter, maxAnisotropy = _maxAnisotropy,
            sAddressMode = _sAddressMode, tAddressMode = _tAddressMode, rAddressMode = _rAddressMode,
            borderColor = _borderColor, normalizedCoordinates = _normalizedCoordinates, lodMinClamp = _lodMinClamp,
            lodMaxClamp = _lodMaxClamp, lodAverage = _lodAverage, compareFunction = _compareFunction,
            supportArgumentBuffers = _supportArgumentBuffers, label = _label;
- (instancetype)init
{
    if ((self = [super init])) {
        _maxAnisotropy = 1;
        _normalizedCoordinates = YES;
        _lodMaxClamp = 3.40282347e+38f;
        _compareFunction = MTLCompareFunctionNever;
    }
    return self;
}
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end

@implementation MTLStencilDescriptor
@synthesize stencilCompareFunction = _stencilCompareFunction, stencilFailureOperation = _stencilFailureOperation,
            depthFailureOperation = _depthFailureOperation, depthStencilPassOperation = _depthStencilPassOperation,
            readMask = _readMask, writeMask = _writeMask;
- (instancetype)init
{
    if ((self = [super init])) {
        _stencilCompareFunction = MTLCompareFunctionAlways;
        _readMask = _writeMask = 0xffffffff;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end

@implementation MTLDepthStencilDescriptor
@synthesize depthCompareFunction = _depthCompareFunction, depthWriteEnabled = _depthWriteEnabled,
            frontFaceStencil = _frontFaceStencil, backFaceStencil = _backFaceStencil, label = _label;
- (instancetype)init
{
    if ((self = [super init])) _depthCompareFunction = MTLCompareFunctionAlways;
    return self;
}
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end

@implementation MTLHeapDescriptor
@synthesize size = _size, resourceOptions = _resourceOptions, type = _type;
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_resourceOptions >> 4) & 0xf); }
- (void)setStorageMode:(MTLStorageMode)m { _resourceOptions = (_resourceOptions & ~(NSUInteger)0xf0) | (m << 4); }
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)(_resourceOptions & 0xf); }
- (void)setCpuCacheMode:(MTLCPUCacheMode)m { _resourceOptions = (_resourceOptions & ~(NSUInteger)0xf) | m; }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((_resourceOptions >> 8) & 0xf); }
- (void)setHazardTrackingMode:(MTLHazardTrackingMode)m
{
    _resourceOptions = (_resourceOptions & ~(NSUInteger)0xf00) | (m << 8);
}
@end

@implementation MTLCommandBufferDescriptor
@synthesize retainedReferences = _retainedReferences, errorOptions = _errorOptions;
- (instancetype)init
{
    if ((self = [super init])) _retainedReferences = YES;
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end

@implementation MTLIndirectCommandBufferDescriptor
@synthesize commandTypes = _commandTypes, inheritPipelineState = _inheritPipelineState,
            inheritBuffers = _inheritBuffers, maxVertexBufferBindCount = _maxVertexBufferBindCount,
            maxFragmentBufferBindCount = _maxFragmentBufferBindCount, maxKernelBufferBindCount = _maxKernelBufferBindCount;
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end

@implementation MTLArgumentDescriptor
@synthesize dataType = _dataType, index = _index, arrayLength = _arrayLength, access = _access,
            textureType = _textureType, constantBlockAlignment = _constantBlockAlignment;
+ (MTLArgumentDescriptor *)argumentDescriptor { return [[[self alloc] init] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end

@implementation MTLSharedEventListener {
    dispatch_queue_t _queue;
}
- (instancetype)initWithDispatchQueue:(dispatch_queue_t)q
{
    if ((self = [super init])) {
        _queue = q;
        if (q) dispatch_retain(q);
    }
    return self;
}
- (void)dealloc
{
    if (_queue) dispatch_release(_queue);
    [super dealloc];
}
- (dispatch_queue_t)dispatchQueue { return _queue; }
@end

@implementation MTLSharedEventHandle
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
- (NSString *)label { return nil; }
@end
@implementation MTLSharedTextureHandle
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
- (id<MTLDevice>)device { return [FerryMTLDevice shared]; }
- (NSString *)label { return nil; }
@end

/* ---- capture: none on Ferry ------------------------------------------------------------ */
@interface FerryMTLCaptureScope : FerryMTLObject <MTLCaptureScope> {
@public
    id _queue;
}
@end
@implementation FerryMTLCaptureScope
- (void)dealloc { [_queue release]; [super dealloc]; }
- (void)beginScope {}
- (void)endScope {}
- (id<MTLCommandQueue>)commandQueue { return _queue; }
@end

@implementation MTLCaptureDescriptor
@synthesize captureObject = _captureObject, destination = _destination, outputURL = _outputURL;
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
@end

@implementation MTLCaptureManager
@synthesize defaultCaptureScope = _defaultCaptureScope;
+ (MTLCaptureManager *)sharedCaptureManager
{
    static MTLCaptureManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [[MTLCaptureManager alloc] init]; });
    return m;
}
- (id<MTLCaptureScope>)newCaptureScopeWithDevice:(id<MTLDevice>)device { return [[FerryMTLCaptureScope alloc] init]; }
- (id<MTLCaptureScope>)newCaptureScopeWithCommandQueue:(id<MTLCommandQueue>)q
{
    FerryMTLCaptureScope *s = [[FerryMTLCaptureScope alloc] init];
    s->_queue = [q retain];
    return s;
}
- (BOOL)supportsDestination:(MTLCaptureDestination)d { return NO; }
- (BOOL)startCaptureWithDescriptor:(MTLCaptureDescriptor *)d error:(NSError **)error
{
    if (error)
        *error = FerryMTLError(MTLCaptureErrorDomain, MTLCaptureErrorNotSupported,
                               @"GPU captures aren't supported by the Ferry Software Renderer");
    return NO;
}
- (void)startCaptureWithDevice:(id<MTLDevice>)device {}
- (void)startCaptureWithCommandQueue:(id<MTLCommandQueue>)q {}
- (void)startCaptureWithScope:(id<MTLCaptureScope>)s {}
- (void)stopCapture {}
- (BOOL)isCapturing { return NO; }
@end
