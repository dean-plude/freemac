/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal.framework: the Objective-C classes behind the protocols in
 * Metal/Metal.h, as its source files share them. Written from Apple's public
 * Metal documentation. Built without ARC. */
#ifndef FERRY_MTL_OBJC_H
#define FERRY_MTL_OBJC_H
#import <Metal/Metal.h>
#include "MTLInternal.h"

/* Every Ferry Metal object: a message Ferry doesn't implement yet is noted
 * once ("Metal: -[MTLX sel] not done yet") and answers 0, so a program that
 * uses a part of Metal Ferry lacks keeps going. */
@interface FerryMTLObject : NSObject {
@public
    NSString *_label;
}
@property (copy, atomic) NSString *label;
@property (readonly) id<MTLDevice> device;
@end

@interface FerryMTLDevice : FerryMTLObject <MTLDevice>
+ (FerryMTLDevice *)shared;
@end
FerryMTLDevice *FerryMTLDeviceIfOn(void);

@interface FerryMTLBuffer : FerryMTLObject <MTLBuffer> {
@public
    char *_contents;
    NSUInteger _length;
    MTLResourceOptions _options;
    void (^_deallocator)(void *, NSUInteger);
    id _heap;
}
@end

@interface FerryMTLTexture : FerryMTLObject <MTLTexture> {
@public
    struct __ferry_tex _t;
    char *_mem;                 /* what this texture allocated, or NULL */
    FerryMTLTexture *_parent;   /* a view's texture */
    id<MTLBuffer> _buffer;      /* a texture made from a buffer */
    NSUInteger _bufferOffset, _bufferRow;
    NSUInteger _parentLevel, _parentSlice;
    MTLTextureUsage _usage;
    MTLResourceOptions _options;
    BOOL _framebufferOnly;
    void *_iosurface;
    NSUInteger _plane;
    id _heap;
}
- (struct __ferry_tex *)ferryTex;
@end
/* A new texture the size and format of a descriptor. */
FerryMTLTexture *FerryMTLNewTexture(MTLTextureDescriptor *d, char *mem, NSUInteger bytesPerRow);

@interface FerryMTLSampler : FerryMTLObject <MTLSamplerState> {
@public
    struct ferry_sampler _s;
}
@end

@interface FerryMTLDepthStencilState : FerryMTLObject <MTLDepthStencilState> {
@public
    struct mtl_dsstate _ds;
}
@end

@interface FerryMTLLibrary : FerryMTLObject <MTLLibrary> {
@public
    void *_handle;              /* the dlopen'd shader library */
    NSString *_path;
    NSDictionary *_reflection;  /* ferry-mslc's JSON */
    NSString *_source;
    MTLCompileOptions *_options;
    NSMutableDictionary *_specialized;
    int _waits;                 /* its code calls a quad exchange or a barrier */
}
@end

@interface FerryMTLFunction : FerryMTLObject <MTLFunction> {
@public
    FerryMTLLibrary *_library;
    NSDictionary *_info;        /* this function's entry in the reflection */
    struct mtl_fn _fn;
    NSString *_name;
    MTLFunctionConstantValues *_constants;
}
@end

@interface FerryMTLRenderPipelineState : FerryMTLObject <MTLRenderPipelineState> {
@public
    struct mtl_rpipe _p;
    FerryMTLFunction *_vs, *_fs;
}
@end

@interface FerryMTLComputePipelineState : FerryMTLObject <MTLComputePipelineState> {
@public
    FerryMTLFunction *_cs;
    NSUInteger _maxThreads;
}
@end

@interface FerryMTLCommandQueue : FerryMTLObject <MTLCommandQueue> {
@public
    dispatch_queue_t _queue;
}
@end

@interface MTLFunctionConstantValues () {
@public
    NSMutableDictionary *_byIndex;  /* @(index) -> NSString literal */
    NSMutableDictionary *_byName;
}
@end

/* The drawable a CAMetalLayer gives (QuartzCore asks for one by name). */
@interface FerryMTLDrawable : FerryMTLObject <MTLDrawable> {
@public
    FerryMTLTexture *_texture;
    id _layer;
    NSUInteger _drawableID;
    CFTimeInterval _presentedTime;
    NSMutableArray *_presentedHandlers;
    void *_slot;                /* the layer's dispatch_semaphore_t, signalled when we go */
}
@property (readonly) id<MTLTexture> texture;
@property (readonly) id layer;
@end

/* An array of sub-descriptors: an element is made when first asked for,
 * and setting one keeps a copy. */
#define FERRY_DESC_ARRAY(Arr, Elem, N)                                                                         \
    @interface Arr () {                                                                                        \
    @public                                                                                                    \
        Elem *_items[N];                                                                                       \
    }                                                                                                          \
    @end                                                                                                       \
    @implementation Arr                                                                                        \
    -(Elem *)objectAtIndexedSubscript : (NSUInteger)i                                                          \
    {                                                                                                          \
        if (i >= N) return nil;                                                                                \
        if (!_items[i]) _items[i] = [[Elem alloc] init];                                                       \
        return _items[i];                                                                                      \
    }                                                                                                          \
    -(void)setObject : (Elem *)o atIndexedSubscript : (NSUInteger)i                                            \
    {                                                                                                          \
        if (i >= N) return;                                                                                    \
        Elem *c = [o copy];                                                                                    \
        [_items[i] release];                                                                                   \
        _items[i] = c;                                                                                         \
    }                                                                                                          \
    -(Elem *)ferryPeek : (NSUInteger)i { return i < N ? _items[i] : nil; }                                     \
    -(id)ferryDeepCopy                                                                                         \
    {                                                                                                          \
        Arr *a = [[Arr alloc] init];                                                                           \
        for (NSUInteger i = 0; i < N; i++) a->_items[i] = [_items[i] copy];                                    \
        return a;                                                                                              \
    }                                                                                                          \
    -(void)ferryReset                                                                                          \
    {                                                                                                          \
        for (NSUInteger i = 0; i < N; i++) { [_items[i] release]; _items[i] = nil; }                           \
    }                                                                                                          \
    -(void)dealloc                                                                                             \
    {                                                                                                          \
        [self ferryReset];                                                                                     \
        [super dealloc];                                                                                       \
    }                                                                                                          \
    @end

/* Errors, as NSError in Metal's own domains. */
NSError *FerryMTLError(NSString *domain, NSInteger code, NSString *fmt, ...) NS_FORMAT_FUNCTION(3, 4);
/* A texel format's bytes per row for a width, with BC blocks counted. */
NSUInteger FerryMTLRowBytes(MTLPixelFormat f, NSUInteger width);

#endif
