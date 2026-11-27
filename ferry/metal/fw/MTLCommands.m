/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Metal.framework: command queues, command buffers and the render,
 * compute and blit encoders, and the drawables a CAMetalLayer gives.
 * An encoder records each command with the state it was encoded with
 * (buffers are read when the command runs, setBytes data is copied when it
 * is set, as Metal's documentation describes); committing a command buffer
 * runs its commands in order on its queue's own thread, so command buffers
 * of one queue run one after another. FERRY_METAL_SYNC=1 runs them in
 * commit instead. Written from Apple's public Metal documentation. Built
 * without ARC. */
#import "MTLObjC.h"
#import <CoreGraphics/CoreGraphics.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* (the encoders' factories are in categories next to each encoder) */
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"

@protocol FerryMTLLayerOpacity
- (BOOL)isOpaque;
@end

id FerryMTLCopyDescriptor(id self, NSZone *zone);
void FerryMTLReleaseIvars(id self);

static CFTimeInterval now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}
static int run_sync(void)
{
    static int v = -1;
    if (v < 0) {
        const char *e = getenv("FERRY_METAL_SYNC");
        v = e && *e == '1';
    }
    return v;
}

/* ---- render pass descriptors ----------------------------------------------------------- */
@implementation MTLRenderPassAttachmentDescriptor
@synthesize texture = _texture, level = _level, slice = _slice, depthPlane = _depthPlane,
            resolveTexture = _resolveTexture, resolveLevel = _resolveLevel, resolveSlice = _resolveSlice,
            resolveDepthPlane = _resolveDepthPlane, loadAction = _loadAction, storeAction = _storeAction,
            storeActionOptions = _storeActionOptions;
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end
@implementation MTLRenderPassColorAttachmentDescriptor
@synthesize clearColor = _clearColor;
- (instancetype)init
{
    if ((self = [super init])) {
        _clearColor = MTLClearColorMake(0, 0, 0, 1);
        self.storeAction = MTLStoreActionStore;
    }
    return self;
}
@end
@implementation MTLRenderPassDepthAttachmentDescriptor
@synthesize clearDepth = _clearDepth, depthResolveFilter = _depthResolveFilter;
- (instancetype)init
{
    if ((self = [super init])) _clearDepth = 1.0;
    return self;
}
@end
@implementation MTLRenderPassStencilAttachmentDescriptor
@synthesize clearStencil = _clearStencil, stencilResolveFilter = _stencilResolveFilter;
@end
FERRY_DESC_ARRAY(MTLRenderPassColorAttachmentDescriptorArray, MTLRenderPassColorAttachmentDescriptor, 8)

@interface MTLRenderPassDescriptor () {
    MTLRenderPassColorAttachmentDescriptorArray *_colorAttachments;
    MTLRenderPassDepthAttachmentDescriptor *_depthAttachment;
    MTLRenderPassStencilAttachmentDescriptor *_stencilAttachment;
    id<MTLBuffer> _visibilityResultBuffer;
    NSUInteger _renderTargetArrayLength, _imageblockSampleLength, _threadgroupMemoryLength;
    NSUInteger _tileWidth, _tileHeight, _defaultRasterSampleCount, _renderTargetWidth, _renderTargetHeight;
}
@end
@implementation MTLRenderPassDescriptor
@synthesize visibilityResultBuffer = _visibilityResultBuffer, renderTargetArrayLength = _renderTargetArrayLength,
            imageblockSampleLength = _imageblockSampleLength, threadgroupMemoryLength = _threadgroupMemoryLength,
            tileWidth = _tileWidth, tileHeight = _tileHeight, defaultRasterSampleCount = _defaultRasterSampleCount,
            renderTargetWidth = _renderTargetWidth, renderTargetHeight = _renderTargetHeight;
+ (MTLRenderPassDescriptor *)renderPassDescriptor { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    if ((self = [super init])) {
        _colorAttachments = [[MTLRenderPassColorAttachmentDescriptorArray alloc] init];
        _depthAttachment = [[MTLRenderPassDepthAttachmentDescriptor alloc] init];
        _stencilAttachment = [[MTLRenderPassStencilAttachmentDescriptor alloc] init];
    }
    return self;
}
- (void)dealloc { FerryMTLReleaseIvars(self); [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
- (MTLRenderPassColorAttachmentDescriptorArray *)colorAttachments { return _colorAttachments; }
- (MTLRenderPassDepthAttachmentDescriptor *)depthAttachment { return _depthAttachment; }
- (void)setDepthAttachment:(MTLRenderPassDepthAttachmentDescriptor *)d
{
    id c = d ? [d copy] : [[MTLRenderPassDepthAttachmentDescriptor alloc] init];
    [_depthAttachment release];
    _depthAttachment = c;
}
- (MTLRenderPassStencilAttachmentDescriptor *)stencilAttachment { return _stencilAttachment; }
- (void)setStencilAttachment:(MTLRenderPassStencilAttachmentDescriptor *)d
{
    id c = d ? [d copy] : [[MTLRenderPassStencilAttachmentDescriptor alloc] init];
    [_stencilAttachment release];
    _stencilAttachment = c;
}
- (void)setSamplePositions:(const MTLSamplePosition *)positions count:(NSUInteger)count {}
- (NSUInteger)getSamplePositions:(MTLSamplePosition *)positions count:(NSUInteger)count { return 0; }
@end

@implementation MTLComputePassDescriptor
@synthesize dispatchType = _dispatchType;
+ (MTLComputePassDescriptor *)computePassDescriptor { return [[[self alloc] init] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return FerryMTLCopyDescriptor(self, zone); }
@end
@implementation MTLBlitPassDescriptor
+ (MTLBlitPassDescriptor *)blitPassDescriptor { return [[[self alloc] init] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return [[[self class] allocWithZone:zone] init]; }
@end

/* ---- command buffers ----------------------------------------------------------------------- */
typedef void (^ferry_cmd)(void);

@interface FerryMTLCommandBuffer : FerryMTLObject <MTLCommandBuffer> {
@public
    FerryMTLCommandQueue *_queue;
    NSMutableArray *_commands;     /* ferry_cmd blocks */
    NSMutableArray *_retained;     /* what the commands use */
    NSMutableArray *_scheduled, *_completed, *_drawables;
    char **_chunks;                /* setBytes copies */
    size_t _nchunks, _chunkUsed;
    pthread_mutex_t _lock;
    pthread_cond_t _cond;
    MTLCommandBufferStatus _status;
    BOOL _retainedReferences, _encoding;
    CFTimeInterval _start, _end;
    NSError *_error;
}
- (void)ferryAdd:(ferry_cmd)cmd;
- (void)ferryKeep:(id)obj;
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)d;
- (id<MTLComputeCommandEncoder>)computeCommandEncoder;
- (id<MTLBlitCommandEncoder>)blitCommandEncoder;
- (void *)ferryCopy:(const void *)bytes length:(size_t)n;
@end

@implementation FerryMTLCommandQueue
- (instancetype)init
{
    if ((self = [super init])) _queue = dispatch_queue_create("ferry.metal.queue", NULL);
    return self;
}
- (void)dealloc
{
    if (_queue) dispatch_release(_queue);
    [super dealloc];
}
- (id<MTLCommandBuffer>)ferryBufferRetaining:(BOOL)retain
{
    FerryMTLCommandBuffer *b = [[FerryMTLCommandBuffer alloc] init];
    b->_queue = [self retain];
    b->_retainedReferences = retain;
    return [b autorelease];
}
- (id<MTLCommandBuffer>)commandBuffer { return [self ferryBufferRetaining:YES]; }
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences { return [self ferryBufferRetaining:NO]; }
- (id<MTLCommandBuffer>)commandBufferWithDescriptor:(MTLCommandBufferDescriptor *)d
{
    return [self ferryBufferRetaining:d ? d.retainedReferences : YES];
}
- (void)insertDebugCaptureBoundary {}
@end

@implementation FerryMTLCommandBuffer
- (instancetype)init
{
    if ((self = [super init])) {
        _commands = [[NSMutableArray alloc] init];
        _retained = [[NSMutableArray alloc] init];
        _scheduled = [[NSMutableArray alloc] init];
        _completed = [[NSMutableArray alloc] init];
        _drawables = [[NSMutableArray alloc] init];
        pthread_mutex_init(&_lock, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    return self;
}
- (void)dealloc
{
    [_queue release];
    [_commands release];
    [_retained release];
    [_scheduled release];
    [_completed release];
    [_drawables release];
    [_error release];
    for (size_t i = 0; i < _nchunks; i++) free(_chunks[i]);
    free(_chunks);
    pthread_mutex_destroy(&_lock);
    pthread_cond_destroy(&_cond);
    [super dealloc];
}
- (void)ferryAdd:(ferry_cmd)cmd
{
    ferry_cmd c = [cmd copy];
    [_commands addObject:c];
    [c release];
}
/* (objects are kept until the buffer completes whether or not the buffer
 * retains its references: nothing here can run after they are freed) */
- (void)ferryKeep:(id)obj
{
    if (obj) [_retained addObject:obj];
}
- (void *)ferryCopy:(const void *)bytes length:(size_t)n
{
    enum { CHUNK = 256 * 1024 };
    size_t need = (n + 255) & ~(size_t)255;
    if (need > CHUNK) {
        char *p = NULL;
        if (posix_memalign((void **)&p, 256, need)) return NULL;
        /* a big copy gets its own chunk, kept before the current one */
        _chunks = realloc(_chunks, (_nchunks + 1) * sizeof *_chunks);
        if (_nchunks) {
            _chunks[_nchunks] = _chunks[_nchunks - 1];
            _chunks[_nchunks - 1] = p;
        } else {
            _chunks[0] = p;
            _chunkUsed = CHUNK; /* (no current chunk yet) */
        }
        _nchunks++;
        if (bytes) memcpy(p, bytes, n);
        return p;
    }
    if (!_nchunks || _chunkUsed + need > CHUNK) {
        char *p = NULL;
        if (posix_memalign((void **)&p, 256, CHUNK)) return NULL;
        _chunks = realloc(_chunks, (_nchunks + 1) * sizeof *_chunks);
        _chunks[_nchunks++] = p;
        _chunkUsed = 0;
    }
    char *p = _chunks[_nchunks - 1] + _chunkUsed;
    _chunkUsed += need;
    if (bytes) memcpy(p, bytes, n);
    return p;
}
- (id<MTLDevice>)device { return [FerryMTLDevice shared]; }
- (id<MTLCommandQueue>)commandQueue { return _queue; }
- (BOOL)retainedReferences { return _retainedReferences; }
- (MTLCommandBufferErrorOption)errorOptions { return MTLCommandBufferErrorOptionNone; }
- (CFTimeInterval)kernelStartTime { return _start; }
- (CFTimeInterval)kernelEndTime { return _end; }
- (CFTimeInterval)GPUStartTime { return _start; }
- (CFTimeInterval)GPUEndTime { return _end; }
- (MTLCommandBufferStatus)status
{
    pthread_mutex_lock(&_lock);
    MTLCommandBufferStatus s = _status;
    pthread_mutex_unlock(&_lock);
    return s;
}
- (NSError *)error { return _error; }
- (id)logs { return @[]; }
- (void)ferrySetStatus:(MTLCommandBufferStatus)s
{
    pthread_mutex_lock(&_lock);
    _status = s;
    pthread_cond_broadcast(&_cond);
    pthread_mutex_unlock(&_lock);
}
- (void)enqueue
{
    pthread_mutex_lock(&_lock);
    if (_status == MTLCommandBufferStatusNotEnqueued) _status = MTLCommandBufferStatusEnqueued;
    pthread_mutex_unlock(&_lock);
}
- (void)ferryRun
{
    @autoreleasepool {
        [self ferrySetStatus:MTLCommandBufferStatusScheduled];
        _start = now();
        for (MTLCommandBufferHandler h in _scheduled) h(self);
        for (ferry_cmd c in _commands) {
            @autoreleasepool { c(); }
        }
        _end = now();
        [_commands removeAllObjects];
        for (id d in _drawables) [d present];
        [self ferrySetStatus:MTLCommandBufferStatusCompleted];
        for (MTLCommandBufferHandler h in _completed) h(self);
        [_retained removeAllObjects];
        [_scheduled removeAllObjects];
        [_completed removeAllObjects];
        [_drawables removeAllObjects];
    }
}
- (void)commit
{
    pthread_mutex_lock(&_lock);
    if (_status >= MTLCommandBufferStatusCommitted) {
        pthread_mutex_unlock(&_lock);
        mtl_log("a command buffer was committed twice");
        return;
    }
    _status = MTLCommandBufferStatusCommitted;
    pthread_mutex_unlock(&_lock);
    if (_encoding) mtl_log("a command buffer was committed while an encoder was still encoding");
    if (run_sync() || !_queue) {
        [self ferryRun];
        return;
    }
    [self retain];
    dispatch_async(_queue->_queue, ^{
      [self ferryRun];
      [self release];
    });
}
- (void)addScheduledHandler:(MTLCommandBufferHandler)block
{
    id b = [block copy];
    [_scheduled addObject:b];
    [b release];
}
- (void)addCompletedHandler:(MTLCommandBufferHandler)block
{
    id b = [block copy];
    pthread_mutex_lock(&_lock);
    BOOL done = _status == MTLCommandBufferStatusCompleted;
    if (!done) [_completed addObject:b];
    pthread_mutex_unlock(&_lock);
    if (done) ((MTLCommandBufferHandler)b)(self);
    [b release];
}
- (void)presentDrawable:(id<MTLDrawable>)drawable { if (drawable) [_drawables addObject:drawable]; }
- (void)presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)t { [self presentDrawable:drawable]; }
- (void)presentDrawable:(id<MTLDrawable>)drawable afterMinimumDuration:(CFTimeInterval)d { [self presentDrawable:drawable]; }
- (void)ferryWaitFor:(MTLCommandBufferStatus)s
{
    pthread_mutex_lock(&_lock);
    if (_status >= MTLCommandBufferStatusCommitted)
        while (_status < s) pthread_cond_wait(&_cond, &_lock);
    pthread_mutex_unlock(&_lock);
}
- (void)waitUntilScheduled { [self ferryWaitFor:MTLCommandBufferStatusScheduled]; }
- (void)waitUntilCompleted { [self ferryWaitFor:MTLCommandBufferStatusCompleted]; }
- (void)encodeWaitForEvent:(id<MTLEvent>)event value:(uint64_t)value
{
    [self ferryKeep:event];
    id<MTLSharedEvent> e = (id<MTLSharedEvent>)event;
    [self ferryAdd:^{
      if ([e respondsToSelector:@selector(waitUntilSignaledValue:timeoutMS:)])
          [e waitUntilSignaledValue:value timeoutMS:UINT64_MAX];
    }];
}
- (void)encodeSignalEvent:(id<MTLEvent>)event value:(uint64_t)value
{
    [self ferryKeep:event];
    id<MTLSharedEvent> e = (id<MTLSharedEvent>)event;
    [self ferryAdd:^{
      if ([e respondsToSelector:@selector(setSignaledValue:)]) e.signaledValue = value;
    }];
}
- (void)pushDebugGroup:(NSString *)string {}
- (void)popDebugGroup {}
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDescriptor:(MTLComputePassDescriptor *)d
{
    return [self computeCommandEncoder];
}
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDispatchType:(MTLDispatchType)t
{
    return [self computeCommandEncoder];
}
- (id<MTLBlitCommandEncoder>)blitCommandEncoderWithDescriptor:(MTLBlitPassDescriptor *)d
{
    return [self blitCommandEncoder];
}
@end

/* ---- encoders: what they share ------------------------------------------------------------ */
@interface FerryMTLEncoder : FerryMTLObject <MTLCommandEncoder> {
@public
    FerryMTLCommandBuffer *_cb;
}
@end
@implementation FerryMTLEncoder
- (void)dealloc { [_cb release]; [super dealloc]; }
- (void)endEncoding
{
    _cb->_encoding = NO;
}
- (void)insertDebugSignpost:(NSString *)string {}
- (void)pushDebugGroup:(NSString *)string {}
- (void)popDebugGroup {}
- (void)ferryEncodeWaitForFence:(id)fence {}
@end

/* Fill one stage's bindings */
static void bind_buffer(FerryMTLCommandBuffer *cb, struct mtl_bindings *b, id<MTLBuffer> buf, NSUInteger offset,
                        NSUInteger index)
{
    if (index >= FERRY_MAX_BUFFERS) return;
    [cb ferryKeep:buf];
    b->buffers[index] = buf ? (char *)[buf contents] + offset : NULL;
}
static void bind_offset(struct mtl_bindings *b, id<MTLBuffer> const *bufs, NSUInteger offset, NSUInteger index)
{
    if (index >= FERRY_MAX_BUFFERS || !bufs[index]) return;
    b->buffers[index] = (char *)[bufs[index] contents] + offset;
}
static void bind_bytes(FerryMTLCommandBuffer *cb, struct mtl_bindings *b, const void *bytes, NSUInteger n,
                       NSUInteger index)
{
    if (index >= FERRY_MAX_BUFFERS) return;
    b->buffers[index] = [cb ferryCopy:bytes length:n];
}
static void bind_texture(FerryMTLCommandBuffer *cb, struct mtl_bindings *b, id<MTLTexture> t, NSUInteger index)
{
    if (index >= FERRY_MAX_TEXTURES) return;
    [cb ferryKeep:t];
    b->textures[index] = t ? [(FerryMTLTexture *)t ferryTex] : NULL;
}
static void bind_sampler(FerryMTLCommandBuffer *cb, struct mtl_bindings *b, id<MTLSamplerState> s, NSUInteger index,
                         const float *lod)
{
    if (index >= FERRY_MAX_SAMPLERS) return;
    [cb ferryKeep:s];
    if (!s) {
        b->samplers[index] = NULL;
        return;
    }
    const struct ferry_sampler *src = &((FerryMTLSampler *)s)->_s;
    if (lod) {
        struct ferry_sampler *c = [cb ferryCopy:src length:sizeof *src];
        c->lod_min = lod[0];
        c->lod_max = lod[1];
        src = c;
    }
    b->samplers[index] = src;
}

/* ---- render encoder -------------------------------------------------------------------------- */
@interface FerryMTLRenderEncoder : FerryMTLEncoder <MTLRenderCommandEncoder> {
@public
    struct mtl_target _rt;
    struct mtl_draw_state _st;
    id<MTLBuffer> _vbufs[FERRY_MAX_BUFFERS], _fbufs[FERRY_MAX_BUFFERS];
    id _visibility;
    MTLRenderPassDescriptor *_pass;
}
@end

static void set_attachment(FerryMTLCommandBuffer *cb, struct mtl_attachment *a, MTLRenderPassAttachmentDescriptor *d)
{
    memset(a, 0, sizeof *a);
    if (!d.texture) return;
    [cb ferryKeep:d.texture];
    a->tex = [(FerryMTLTexture *)d.texture ferryTex];
    a->level = (unsigned)d.level;
    a->slice = (unsigned)d.slice;
    a->plane = (unsigned)d.depthPlane;
}

/* A pass's resolve: Ferry draws one sample, so a resolve copies. */
static void resolve(FerryMTLCommandBuffer *cb, MTLRenderPassAttachmentDescriptor *d)
{
    if (!d.texture || !d.resolveTexture) return;
    if (d.storeAction != MTLStoreActionMultisampleResolve && d.storeAction != MTLStoreActionStoreAndMultisampleResolve)
        return;
    [cb ferryKeep:d.resolveTexture];
    struct __ferry_tex *s = [(FerryMTLTexture *)d.texture ferryTex], *t = [(FerryMTLTexture *)d.resolveTexture ferryTex];
    unsigned sl = (unsigned)d.level, tl = (unsigned)d.resolveLevel;
    unsigned ss = (unsigned)d.slice, ts = (unsigned)d.resolveSlice;
    unsigned sz = (unsigned)d.depthPlane, tz = (unsigned)d.resolveDepthPlane;
    [cb ferryAdd:^{
      if (sl >= s->levels || tl >= t->levels) return;
      unsigned w = s->lw[sl] < t->lw[tl] ? s->lw[sl] : t->lw[tl];
      unsigned h = s->lh[sl] < t->lh[tl] ? s->lh[sl] : t->lh[tl];
      for (unsigned y = 0; y < h; y++)
          for (unsigned x = 0; x < w; x++) {
              float v[4];
              mtl_texel_load(s->f, mtl_texel(s, x, y, sz, ss, sl), v);
              mtl_texel_store(t->f, mtl_texel(t, x, y, tz, ts, tl), v);
          }
    }];
}

@implementation FerryMTLCommandBuffer (Render)
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)d
{
    if (!d) return nil;
    FerryMTLRenderEncoder *e = [[FerryMTLRenderEncoder alloc] init];
    e->_cb = [self retain];
    e->_pass = [d copy];
    _encoding = YES;
    struct mtl_target *rt = &e->_rt;
    for (unsigned i = 0; i < 8; i++) set_attachment(self, &rt->color[i], [d.colorAttachments ferryPeek:i]);
    set_attachment(self, &rt->depth, d.depthAttachment);
    set_attachment(self, &rt->stencil, d.stencilAttachment);
    /* the size of the first attachment, or the pass's own */
    unsigned w = (unsigned)d.renderTargetWidth, h = (unsigned)d.renderTargetHeight;
    const struct mtl_attachment *all[10];
    for (int i = 0; i < 8; i++) all[i] = &rt->color[i];
    all[8] = &rt->depth;
    all[9] = &rt->stencil;
    for (int i = 0; i < 10; i++)
        if (all[i]->tex && all[i]->level < all[i]->tex->levels) {
            unsigned aw = all[i]->tex->lw[all[i]->level], ah = all[i]->tex->lh[all[i]->level];
            if (!w || aw < w) w = aw;
            if (!h || ah < h) h = ah;
        }
    rt->width = w;
    rt->height = h;

    struct mtl_draw_state *st = &e->_st;
    st->vp[0] = 0;
    st->vp[1] = 0;
    st->vp[2] = w;
    st->vp[3] = h;
    st->vp[4] = 0;
    st->vp[5] = 1;
    st->nvp = 1;
    st->scissor[0] = 0;
    st->scissor[1] = 0;
    st->scissor[2] = (int)w;
    st->scissor[3] = (int)h;
    if (d.visibilityResultBuffer) {
        e->_visibility = [d.visibilityResultBuffer retain];
        [self ferryKeep:d.visibilityResultBuffer];
    }

    /* load actions */
    struct mtl_target R = *rt;
    for (unsigned i = 0; i < 8; i++) {
        MTLRenderPassColorAttachmentDescriptor *c = [d.colorAttachments ferryPeek:i];
        if (!c || !R.color[i].tex || c.loadAction != MTLLoadActionClear) continue;
        MTLClearColor cc = c.clearColor;
        struct mtl_attachment a = R.color[i];
        [self ferryAdd:^{
          double rgba[4] = {cc.red, cc.green, cc.blue, cc.alpha};
          mtl_clear_attachment(&a, rgba, 0, 0, 0);
        }];
    }
    if (R.depth.tex && d.depthAttachment.loadAction == MTLLoadActionClear) {
        struct mtl_attachment a = R.depth;
        double z = d.depthAttachment.clearDepth;
        [self ferryAdd:^{ double zero[4] = {0, 0, 0, 0}; mtl_clear_attachment(&a, zero, 1, z, 0); }];
    }
    if (R.stencil.tex && d.stencilAttachment.loadAction == MTLLoadActionClear) {
        struct mtl_attachment a = R.stencil;
        uint32_t s = d.stencilAttachment.clearStencil;
        [self ferryAdd:^{ double zero[4] = {0, 0, 0, 0}; mtl_clear_attachment(&a, zero, 2, 0, s); }];
    }
    return [e autorelease];
}
@end

@implementation FerryMTLRenderEncoder
- (void)dealloc
{
    [_visibility release];
    [_pass release];
    for (int i = 0; i < FERRY_MAX_BUFFERS; i++) {
        [_vbufs[i] release];
        [_fbufs[i] release];
    }
    [super dealloc];
}
- (void)endEncoding
{
    for (unsigned i = 0; i < 8; i++) resolve(_cb, [_pass.colorAttachments ferryPeek:i]);
    resolve(_cb, _pass.depthAttachment);
    resolve(_cb, _pass.stencilAttachment);
    [super endEncoding];
}
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)ps
{
    [_cb ferryKeep:ps];
    _st.p = ps ? &((FerryMTLRenderPipelineState *)ps)->_p : NULL;
}
static void keep_buf(id<MTLBuffer> *slot, id<MTLBuffer> b)
{
    [b retain];
    [*slot release];
    *slot = b;
}
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)n atIndex:(NSUInteger)i
{
    if (i < FERRY_MAX_BUFFERS) keep_buf(&_vbufs[i], nil);
    bind_bytes(_cb, &_st.vb, bytes, n, i);
}
- (void)setVertexBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i
{
    if (i < FERRY_MAX_BUFFERS) keep_buf(&_vbufs[i], b);
    bind_buffer(_cb, &_st.vb, b, o, i);
}
- (void)setVertexBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { bind_offset(&_st.vb, _vbufs, o, i); }
- (void)setVertexBuffers:(const id<MTLBuffer> __unsafe_unretained[])b offsets:(const NSUInteger[])o withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) [self setVertexBuffer:b[k] offset:o[k] atIndex:r.location + k];
}
- (void)setVertexTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { bind_texture(_cb, &_st.vb, t, i); }
- (void)setVertexTextures:(const id<MTLTexture> __unsafe_unretained[])t withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) bind_texture(_cb, &_st.vb, t[k], r.location + k);
}
- (void)setVertexSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { bind_sampler(_cb, &_st.vb, s, i, NULL); }
- (void)setVertexSamplerStates:(const id<MTLSamplerState> __unsafe_unretained[])s withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) bind_sampler(_cb, &_st.vb, s[k], r.location + k, NULL);
}
- (void)setVertexSamplerState:(id<MTLSamplerState>)s lodMinClamp:(float)a lodMaxClamp:(float)b atIndex:(NSUInteger)i
{
    float lod[2] = {a, b};
    bind_sampler(_cb, &_st.vb, s, i, lod);
}
- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)n atIndex:(NSUInteger)i
{
    if (i < FERRY_MAX_BUFFERS) keep_buf(&_fbufs[i], nil);
    bind_bytes(_cb, &_st.fb, bytes, n, i);
}
- (void)setFragmentBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i
{
    if (i < FERRY_MAX_BUFFERS) keep_buf(&_fbufs[i], b);
    bind_buffer(_cb, &_st.fb, b, o, i);
}
- (void)setFragmentBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { bind_offset(&_st.fb, _fbufs, o, i); }
- (void)setFragmentBuffers:(const id<MTLBuffer> __unsafe_unretained[])b offsets:(const NSUInteger[])o
                 withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) [self setFragmentBuffer:b[k] offset:o[k] atIndex:r.location + k];
}
- (void)setFragmentTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { bind_texture(_cb, &_st.fb, t, i); }
- (void)setFragmentTextures:(const id<MTLTexture> __unsafe_unretained[])t withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) bind_texture(_cb, &_st.fb, t[k], r.location + k);
}
- (void)setFragmentSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { bind_sampler(_cb, &_st.fb, s, i, NULL); }
- (void)setFragmentSamplerStates:(const id<MTLSamplerState> __unsafe_unretained[])s withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) bind_sampler(_cb, &_st.fb, s[k], r.location + k, NULL);
}
- (void)setFragmentSamplerState:(id<MTLSamplerState>)s lodMinClamp:(float)a lodMaxClamp:(float)b
                        atIndex:(NSUInteger)i
{
    float lod[2] = {a, b};
    bind_sampler(_cb, &_st.fb, s, i, lod);
}
- (void)setViewport:(MTLViewport)v
{
    _st.vp[0] = v.originX;
    _st.vp[1] = v.originY;
    _st.vp[2] = v.width;
    _st.vp[3] = v.height;
    _st.vp[4] = v.znear;
    _st.vp[5] = v.zfar;
    _st.nvp = 1;
}
- (void)setViewports:(const MTLViewport[])v count:(NSUInteger)n
{
    if (!n) return;
    [self setViewport:v[0]];
    if (n > 16) n = 16;
    for (NSUInteger i = 1; i < n; i++) {
        double *d = _st.vpx[i - 1];
        d[0] = v[i].originX;
        d[1] = v[i].originY;
        d[2] = v[i].width;
        d[3] = v[i].height;
        d[4] = v[i].znear;
        d[5] = v[i].zfar;
    }
    _st.nvp = (unsigned)n;
}
- (void)setFrontFacingWinding:(MTLWinding)w { _st.winding = (unsigned)w; }
- (void)setCullMode:(MTLCullMode)c { _st.cull = (unsigned)c; }
- (void)setDepthClipMode:(MTLDepthClipMode)m { _st.clip_mode = (unsigned)m; }
- (void)setDepthBias:(float)b slopeScale:(float)s clamp:(float)c
{
    _st.depth_bias = b;
    _st.slope = s;
    _st.bias_clamp = c;
}
- (void)setScissorRect:(MTLScissorRect)r
{
    /* (Metal requires the rectangle inside the target; keep it there) */
    NSUInteger x = r.x < _rt.width ? r.x : _rt.width, y = r.y < _rt.height ? r.y : _rt.height;
    NSUInteger w = r.width, h = r.height;
    if (x + w > _rt.width) w = _rt.width - x;
    if (y + h > _rt.height) h = _rt.height - y;
    _st.scissor[0] = (int)x;
    _st.scissor[1] = (int)y;
    _st.scissor[2] = (int)w;
    _st.scissor[3] = (int)h;
}
- (void)setScissorRects:(const MTLScissorRect[])r count:(NSUInteger)n
{
    if (n) [self setScissorRect:r[0]];
}
- (void)setTriangleFillMode:(MTLTriangleFillMode)m { _st.fill = (unsigned)m; }
- (void)setBlendColorRed:(float)r green:(float)g blue:(float)b alpha:(float)a
{
    _st.blend_color[0] = r;
    _st.blend_color[1] = g;
    _st.blend_color[2] = b;
    _st.blend_color[3] = a;
}
- (void)setDepthStencilState:(id<MTLDepthStencilState>)ds
{
    [_cb ferryKeep:ds];
    _st.ds = ds ? &((FerryMTLDepthStencilState *)ds)->_ds : NULL;
}
- (void)setStencilReferenceValue:(uint32_t)v { _st.stencil_ref_front = _st.stencil_ref_back = v; }
- (void)setStencilFrontReferenceValue:(uint32_t)f backReferenceValue:(uint32_t)b
{
    _st.stencil_ref_front = f;
    _st.stencil_ref_back = b;
}
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset
{
    _st.vis_mode = (unsigned)mode;
    _st.vis_counter = mode && _visibility ? (uint64_t *)((char *)[_visibility contents] + offset) : NULL;
}
- (void)setColorStoreAction:(MTLStoreAction)a atIndex:(NSUInteger)i
{
    [_pass.colorAttachments[i] setStoreAction:a];
}
- (void)setDepthStoreAction:(MTLStoreAction)a { _pass.depthAttachment.storeAction = a; }
- (void)setStencilStoreAction:(MTLStoreAction)a { _pass.stencilAttachment.storeAction = a; }

- (void)ferryDraw:(struct mtl_draw)d indirect:(const uint32_t *)args indexed:(BOOL)indexed
{
    if (!_st.p) {
        mtl_log("a draw with no render pipeline state was skipped");
        return;
    }
    struct mtl_target rt = _rt;
    struct mtl_draw_state st = _st;
    [_cb ferryAdd:^{
      struct mtl_draw dd = d;
      if (args) {
          if (indexed) {
              dd.count = args[0];
              dd.instances = args[1];
              dd.indices = (const char *)d.indices + (size_t)args[2] * d.index_size;
              dd.base_vertex = (int32_t)args[3];
              dd.base_instance = args[4];
          } else {
              dd.count = args[0];
              dd.instances = args[1];
              dd.first = args[2];
              dd.base_instance = args[3];
          }
      }
      if (dd.count && dd.instances) mtl_execute_draw(&rt, &st, &dd);
    }];
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n
         instanceCount:(NSUInteger)ni baseInstance:(NSUInteger)bi
{
    struct mtl_draw d = {(unsigned)t, (unsigned)s, (unsigned)n, (unsigned)ni, (unsigned)bi, 0, NULL, 0};
    [self ferryDraw:d indirect:NULL indexed:NO];
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n
         instanceCount:(NSUInteger)ni
{
    [self drawPrimitives:t vertexStart:s vertexCount:n instanceCount:ni baseInstance:0];
}
- (void)drawPrimitives:(MTLPrimitiveType)t vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n
{
    [self drawPrimitives:t vertexStart:s vertexCount:n instanceCount:1 baseInstance:0];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it
                  indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)off instanceCount:(NSUInteger)ni
                   baseVertex:(NSInteger)bv baseInstance:(NSUInteger)bi
{
    if (!ib) return;
    [_cb ferryKeep:ib];
    struct mtl_draw d = {(unsigned)t, 0, (unsigned)n, (unsigned)ni, (unsigned)bi, (int)bv,
                         (const char *)[ib contents] + off, it == MTLIndexTypeUInt16 ? 2u : 4u};
    [self ferryDraw:d indirect:NULL indexed:YES];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it
                  indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)off instanceCount:(NSUInteger)ni
{
    [self drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:off instanceCount:ni
                     baseVertex:0 baseInstance:0];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexCount:(NSUInteger)n indexType:(MTLIndexType)it
                  indexBuffer:(id<MTLBuffer>)ib indexBufferOffset:(NSUInteger)off
{
    [self drawIndexedPrimitives:t indexCount:n indexType:it indexBuffer:ib indexBufferOffset:off instanceCount:1
                     baseVertex:0 baseInstance:0];
}
- (void)drawPrimitives:(MTLPrimitiveType)t indirectBuffer:(id<MTLBuffer>)b indirectBufferOffset:(NSUInteger)off
{
    if (!b) return;
    [_cb ferryKeep:b];
    struct mtl_draw d = {(unsigned)t, 0, 0, 0, 0, 0, NULL, 0};
    [self ferryDraw:d indirect:(const uint32_t *)((const char *)[b contents] + off) indexed:NO];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)t indexType:(MTLIndexType)it indexBuffer:(id<MTLBuffer>)ib
            indexBufferOffset:(NSUInteger)ioff indirectBuffer:(id<MTLBuffer>)b
         indirectBufferOffset:(NSUInteger)off
{
    if (!b || !ib) return;
    [_cb ferryKeep:b];
    [_cb ferryKeep:ib];
    struct mtl_draw d = {(unsigned)t, 0, 0, 0, 0, 0, (const char *)[ib contents] + ioff,
                         it == MTLIndexTypeUInt16 ? 2u : 4u};
    [self ferryDraw:d indirect:(const uint32_t *)((const char *)[b contents] + off) indexed:YES];
}
- (void)textureBarrier {}
- (void)updateFence:(id<MTLFence>)f afterStages:(MTLRenderStages)s {}
- (void)waitForFence:(id<MTLFence>)f beforeStages:(MTLRenderStages)s {}
- (void)useResource:(id<MTLResource>)r usage:(MTLResourceUsage)u { [_cb ferryKeep:r]; }
- (void)useResources:(const id<MTLResource> __unsafe_unretained[])r count:(NSUInteger)n usage:(MTLResourceUsage)u
{
    for (NSUInteger i = 0; i < n; i++) [_cb ferryKeep:r[i]];
}
- (void)useResource:(id<MTLResource>)r usage:(MTLResourceUsage)u stages:(MTLRenderStages)s { [_cb ferryKeep:r]; }
- (void)useHeap:(id<MTLHeap>)h { [_cb ferryKeep:h]; }
- (void)useHeap:(id<MTLHeap>)h stages:(MTLRenderStages)s { [_cb ferryKeep:h]; }
- (void)memoryBarrierWithScope:(MTLBarrierScope)scope afterStages:(MTLRenderStages)a beforeStages:(MTLRenderStages)b {}
@end

/* ---- compute encoder ------------------------------------------------------------------------- */
@interface FerryMTLComputeEncoder : FerryMTLEncoder <MTLComputeCommandEncoder> {
@public
    FerryMTLComputePipelineState *_ps;
    struct mtl_bindings _b;
    size_t _tglen[16];
    id<MTLBuffer> _bufs[FERRY_MAX_BUFFERS];
}
@end

@implementation FerryMTLCommandBuffer (Compute)
- (id<MTLComputeCommandEncoder>)computeCommandEncoder
{
    FerryMTLComputeEncoder *e = [[FerryMTLComputeEncoder alloc] init];
    e->_cb = [self retain];
    _encoding = YES;
    return [e autorelease];
}
@end

@implementation FerryMTLComputeEncoder
- (void)dealloc
{
    for (int i = 0; i < FERRY_MAX_BUFFERS; i++) [_bufs[i] release];
    [super dealloc];
}
- (MTLDispatchType)dispatchType { return MTLDispatchTypeSerial; }
- (void)setComputePipelineState:(id<MTLComputePipelineState>)ps
{
    [_cb ferryKeep:ps];
    _ps = (FerryMTLComputePipelineState *)ps;
}
- (void)setBytes:(const void *)bytes length:(NSUInteger)n atIndex:(NSUInteger)i
{
    if (i < FERRY_MAX_BUFFERS) keep_buf(&_bufs[i], nil);
    bind_bytes(_cb, &_b, bytes, n, i);
}
- (void)setBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i
{
    if (i < FERRY_MAX_BUFFERS) keep_buf(&_bufs[i], b);
    bind_buffer(_cb, &_b, b, o, i);
}
- (void)setBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { bind_offset(&_b, _bufs, o, i); }
- (void)setBuffers:(const id<MTLBuffer> __unsafe_unretained[])b offsets:(const NSUInteger[])o withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) [self setBuffer:b[k] offset:o[k] atIndex:r.location + k];
}
- (void)setTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i { bind_texture(_cb, &_b, t, i); }
- (void)setTextures:(const id<MTLTexture> __unsafe_unretained[])t withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) bind_texture(_cb, &_b, t[k], r.location + k);
}
- (void)setSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i { bind_sampler(_cb, &_b, s, i, NULL); }
- (void)setSamplerStates:(const id<MTLSamplerState> __unsafe_unretained[])s withRange:(NSRange)r
{
    for (NSUInteger k = 0; k < r.length; k++) bind_sampler(_cb, &_b, s[k], r.location + k, NULL);
}
- (void)setSamplerState:(id<MTLSamplerState>)s lodMinClamp:(float)a lodMaxClamp:(float)b atIndex:(NSUInteger)i
{
    float lod[2] = {a, b};
    bind_sampler(_cb, &_b, s, i, lod);
}
- (void)setThreadgroupMemoryLength:(NSUInteger)n atIndex:(NSUInteger)i
{
    if (i < 16) _tglen[i] = n;
}
- (void)setStageInRegion:(MTLRegion)region
{
    mtl_log("a compute kernel's [[stage_in]] isn't done yet");
}
- (void)ferryDispatch:(MTLSize)groups tpg:(MTLSize)tpg grid:(MTLSize)grid nonuniform:(int)nonuniform
             indirect:(const uint32_t *)args
{
    if (!_ps) {
        mtl_log("a dispatch with no compute pipeline state was skipped");
        return;
    }
    struct mtl_dispatch d;
    memset(&d, 0, sizeof d);
    d.fn = &_ps->_cs->_fn;
    d.b = _b;
    memcpy(d.tglen, _tglen, sizeof d.tglen);
    d.groups[0] = (unsigned)groups.width;
    d.groups[1] = (unsigned)groups.height;
    d.groups[2] = (unsigned)groups.depth;
    d.tpg[0] = (unsigned)(tpg.width ? tpg.width : 1);
    d.tpg[1] = (unsigned)(tpg.height ? tpg.height : 1);
    d.tpg[2] = (unsigned)(tpg.depth ? tpg.depth : 1);
    d.grid[0] = (unsigned)grid.width;
    d.grid[1] = (unsigned)grid.height;
    d.grid[2] = (unsigned)grid.depth;
    d.nonuniform = nonuniform;
    if (d.tpg[0] * d.tpg[1] * d.tpg[2] > _ps->_maxThreads)
        mtl_log("a dispatch asks for %u threads a threadgroup, more than its pipeline's %lu",
                d.tpg[0] * d.tpg[1] * d.tpg[2], (unsigned long)_ps->_maxThreads);
    [_cb ferryAdd:^{
      struct mtl_dispatch dd = d;
      if (args)
          for (int k = 0; k < 3; k++) {
              dd.groups[k] = args[k];
              dd.grid[k] = args[k] * dd.tpg[k];
          }
      if (dd.groups[0] && dd.groups[1] && dd.groups[2]) mtl_execute_dispatch(&dd);
    }];
}
- (void)dispatchThreadgroups:(MTLSize)groups threadsPerThreadgroup:(MTLSize)tpg
{
    MTLSize grid = MTLSizeMake(groups.width * tpg.width, groups.height * tpg.height, groups.depth * tpg.depth);
    [self ferryDispatch:groups tpg:tpg grid:grid nonuniform:0 indirect:NULL];
}
- (void)dispatchThreads:(MTLSize)grid threadsPerThreadgroup:(MTLSize)tpg
{
    NSUInteger tw = tpg.width ? tpg.width : 1, th = tpg.height ? tpg.height : 1, td = tpg.depth ? tpg.depth : 1;
    MTLSize groups = MTLSizeMake((grid.width + tw - 1) / tw, (grid.height + th - 1) / th, (grid.depth + td - 1) / td);
    [self ferryDispatch:groups tpg:tpg grid:grid nonuniform:1 indirect:NULL];
}
- (void)dispatchThreadgroupsWithIndirectBuffer:(id<MTLBuffer>)b indirectBufferOffset:(NSUInteger)off
                         threadsPerThreadgroup:(MTLSize)tpg
{
    if (!b) return;
    [_cb ferryKeep:b];
    [self ferryDispatch:MTLSizeMake(1, 1, 1) tpg:tpg grid:tpg nonuniform:0
               indirect:(const uint32_t *)((const char *)[b contents] + off)];
}
- (void)updateFence:(id<MTLFence>)f {}
- (void)waitForFence:(id<MTLFence>)f {}
- (void)useResource:(id<MTLResource>)r usage:(MTLResourceUsage)u { [_cb ferryKeep:r]; }
- (void)useResources:(const id<MTLResource> __unsafe_unretained[])r count:(NSUInteger)n usage:(MTLResourceUsage)u
{
    for (NSUInteger i = 0; i < n; i++) [_cb ferryKeep:r[i]];
}
- (void)useHeap:(id<MTLHeap>)h { [_cb ferryKeep:h]; }
- (void)memoryBarrierWithScope:(MTLBarrierScope)scope {}
- (void)memoryBarrierWithResources:(const id<MTLResource> __unsafe_unretained[])r count:(NSUInteger)n {}
@end

/* ---- blit encoder ----------------------------------------------------------------------------- */
@interface FerryMTLBlitEncoder : FerryMTLEncoder <MTLBlitCommandEncoder>
@end

@implementation FerryMTLCommandBuffer (Blit)
- (id<MTLBlitCommandEncoder>)blitCommandEncoder
{
    FerryMTLBlitEncoder *e = [[FerryMTLBlitEncoder alloc] init];
    e->_cb = [self retain];
    _encoding = YES;
    return [e autorelease];
}
@end

/* Copy a box of texels between two textures of the same size of texel
 * (Metal allows copies only between such formats). */
static void copy_texels(struct __ferry_tex *s, unsigned ss, unsigned sl, MTLOrigin so, MTLSize size,
                        struct __ferry_tex *t, unsigned ts, unsigned tl, MTLOrigin to)
{
    if (sl >= s->levels || tl >= t->levels || ss >= s->layers || ts >= t->layers) return;
    int bc = s->f->kind == FK_BC;
    NSUInteger x0 = so.x, y0 = so.y, x1 = to.x, y1 = to.y, w = size.width, h = size.height;
    if (bc) {
        x0 /= 4; y0 /= 4; x1 /= 4; y1 /= 4;
        w = (w + 3) / 4;
        h = (h + 3) / 4;
    }
    size_t bpp = s->f->bpp < t->f->bpp ? s->f->bpp : t->f->bpp;
    for (NSUInteger z = 0; z < (size.depth ? size.depth : 1); z++)
        for (NSUInteger y = 0; y < h; y++) {
            char *src = mtl_texel(s, (unsigned)x0, (unsigned)(y0 + y), (unsigned)(so.z + z), ss, sl);
            char *dst = mtl_texel(t, (unsigned)x1, (unsigned)(y1 + y), (unsigned)(to.z + z), ts, tl);
            memmove(dst, src, w * bpp);
        }
}

static void box_level(struct __ferry_tex *t, unsigned layer, unsigned lvl)
{
    unsigned w = t->lw[lvl], h = t->lh[lvl], d = t->ld[lvl] ? t->ld[lvl] : 1;
    unsigned pw = t->lw[lvl - 1], ph = t->lh[lvl - 1], pd = t->ld[lvl - 1] ? t->ld[lvl - 1] : 1;
    for (unsigned z = 0; z < d; z++)
        for (unsigned y = 0; y < h; y++)
            for (unsigned x = 0; x < w; x++) {
                float acc[4] = {0, 0, 0, 0};
                int n = 0;
                for (unsigned dz = 0; dz < (pd > 1 ? 2u : 1u); dz++)
                    for (unsigned dy = 0; dy < (ph > 1 ? 2u : 1u); dy++)
                        for (unsigned dx = 0; dx < (pw > 1 ? 2u : 1u); dx++) {
                            unsigned sx = 2 * x + dx, sy = 2 * y + dy, sz = 2 * z + dz;
                            if (sx >= pw) sx = pw - 1;
                            if (sy >= ph) sy = ph - 1;
                            if (sz >= pd) sz = pd - 1;
                            float v[4];
                            mtl_texel_load(t->f, mtl_texel(t, sx, sy, sz, layer, lvl - 1), v);
                            for (int c = 0; c < 4; c++) acc[c] += v[c];
                            n++;
                        }
                for (int c = 0; c < 4; c++) acc[c] /= n;
                mtl_texel_store(t->f, mtl_texel(t, x, y, z, layer, lvl), acc);
            }
}

@implementation FerryMTLBlitEncoder
- (void)synchronizeResource:(id<MTLResource>)r {}
- (void)synchronizeTexture:(id<MTLTexture>)t slice:(NSUInteger)s level:(NSUInteger)l {}
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl
           sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)dst
       destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)dorg
{
    if (!src || !dst) return;
    [_cb ferryKeep:src];
    [_cb ferryKeep:dst];
    struct __ferry_tex *s = [(FerryMTLTexture *)src ferryTex], *t = [(FerryMTLTexture *)dst ferryTex];
    [_cb ferryAdd:^{
      copy_texels(s, (unsigned)ss, (unsigned)sl, so, size, t, (unsigned)ds, (unsigned)dl, dorg);
    }];
}
- (void)copyFromBuffer:(id<MTLBuffer>)b sourceOffset:(NSUInteger)off sourceBytesPerRow:(NSUInteger)row
   sourceBytesPerImage:(NSUInteger)image sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)t
      destinationSlice:(NSUInteger)slice destinationLevel:(NSUInteger)level destinationOrigin:(MTLOrigin)o
{
    if (!b || !t) return;
    [_cb ferryKeep:b];
    [_cb ferryKeep:t];
    [_cb ferryAdd:^{
      MTLRegion r = {o, size};
      [t replaceRegion:r mipmapLevel:level slice:slice withBytes:(const char *)[b contents] + off bytesPerRow:row
         bytesPerImage:image];
    }];
}
- (void)copyFromBuffer:(id<MTLBuffer>)b sourceOffset:(NSUInteger)off sourceBytesPerRow:(NSUInteger)row
   sourceBytesPerImage:(NSUInteger)image sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)t
      destinationSlice:(NSUInteger)slice destinationLevel:(NSUInteger)level destinationOrigin:(MTLOrigin)o
               options:(MTLBlitOption)options
{
    [self copyFromBuffer:b sourceOffset:off sourceBytesPerRow:row sourceBytesPerImage:image sourceSize:size
               toTexture:t destinationSlice:slice destinationLevel:level destinationOrigin:o];
}
- (void)copyFromTexture:(id<MTLTexture>)t sourceSlice:(NSUInteger)slice sourceLevel:(NSUInteger)level
           sourceOrigin:(MTLOrigin)o sourceSize:(MTLSize)size toBuffer:(id<MTLBuffer>)b
      destinationOffset:(NSUInteger)off destinationBytesPerRow:(NSUInteger)row
 destinationBytesPerImage:(NSUInteger)image
{
    if (!b || !t) return;
    [_cb ferryKeep:b];
    [_cb ferryKeep:t];
    [_cb ferryAdd:^{
      MTLRegion r = {o, size};
      [t getBytes:(char *)[b contents] + off bytesPerRow:row bytesPerImage:image fromRegion:r mipmapLevel:level
            slice:slice];
    }];
}
- (void)copyFromTexture:(id<MTLTexture>)t sourceSlice:(NSUInteger)slice sourceLevel:(NSUInteger)level
           sourceOrigin:(MTLOrigin)o sourceSize:(MTLSize)size toBuffer:(id<MTLBuffer>)b
      destinationOffset:(NSUInteger)off destinationBytesPerRow:(NSUInteger)row
 destinationBytesPerImage:(NSUInteger)image options:(MTLBlitOption)options
{
    [self copyFromTexture:t sourceSlice:slice sourceLevel:level sourceOrigin:o sourceSize:size toBuffer:b
        destinationOffset:off destinationBytesPerRow:row destinationBytesPerImage:image];
}
- (void)generateMipmapsForTexture:(id<MTLTexture>)tex
{
    if (!tex) return;
    [_cb ferryKeep:tex];
    struct __ferry_tex *t = [(FerryMTLTexture *)tex ferryTex];
    [_cb ferryAdd:^{
      if (t->f->kind == FK_BC || t->f->depth || t->f->stencil || t->f->is_int) {
          mtl_log("mipmaps of a %s texture can't be generated", t->f->name);
          return;
      }
      for (unsigned layer = 0; layer < t->layers; layer++)
          for (unsigned l = 1; l < t->levels; l++) box_level(t, layer, l);
    }];
}
- (void)fillBuffer:(id<MTLBuffer>)b range:(NSRange)r value:(uint8_t)v
{
    if (!b) return;
    [_cb ferryKeep:b];
    [_cb ferryAdd:^{
      if (r.location + r.length <= [b length]) memset((char *)[b contents] + r.location, v, r.length);
    }];
}
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl
              toTexture:(id<MTLTexture>)dst destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl
             sliceCount:(NSUInteger)nslices levelCount:(NSUInteger)nlevels
{
    if (!src || !dst) return;
    [_cb ferryKeep:src];
    [_cb ferryKeep:dst];
    struct __ferry_tex *s = [(FerryMTLTexture *)src ferryTex], *t = [(FerryMTLTexture *)dst ferryTex];
    [_cb ferryAdd:^{
      for (NSUInteger k = 0; k < nslices; k++)
          for (NSUInteger l = 0; l < nlevels; l++) {
              unsigned a = (unsigned)(sl + l), b = (unsigned)(dl + l);
              if (a >= s->levels || b >= t->levels) continue;
              MTLSize size = MTLSizeMake(s->lw[a], s->lh[a], s->ld[a] ? s->ld[a] : 1);
              copy_texels(s, (unsigned)(ss + k), a, MTLOriginMake(0, 0, 0), size, t, (unsigned)(ds + k), b,
                          MTLOriginMake(0, 0, 0));
          }
    }];
}
- (void)copyFromTexture:(id<MTLTexture>)src toTexture:(id<MTLTexture>)dst
{
    if (!src || !dst) return;
    struct __ferry_tex *s = [(FerryMTLTexture *)src ferryTex], *t = [(FerryMTLTexture *)dst ferryTex];
    NSUInteger layers = s->layers < t->layers ? s->layers : t->layers, levels = s->levels < t->levels ? s->levels : t->levels;
    [self copyFromTexture:src sourceSlice:0 sourceLevel:0 toTexture:dst destinationSlice:0 destinationLevel:0
               sliceCount:layers levelCount:levels];
}
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so toBuffer:(id<MTLBuffer>)dst
     destinationOffset:(NSUInteger)doff size:(NSUInteger)n
{
    if (!src || !dst) return;
    [_cb ferryKeep:src];
    [_cb ferryKeep:dst];
    [_cb ferryAdd:^{
      if (so + n <= [src length] && doff + n <= [dst length])
          memmove((char *)[dst contents] + doff, (const char *)[src contents] + so, n);
    }];
}
- (void)updateFence:(id<MTLFence>)f {}
- (void)waitForFence:(id<MTLFence>)f {}
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)t {}
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)t slice:(NSUInteger)s level:(NSUInteger)l {}
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)t {}
- (void)resetCommandsInBuffer:(id<MTLIndirectCommandBuffer>)b withRange:(NSRange)r {}
@end

/* ---- drawables ------------------------------------------------------------------------------- */
/* What a CAMetalLayer shows, from one of its drawables: the texture as a
 * picture in the layer's contents. The layer's -_ferryShowMetalImage:
 * puts it there on the main thread. */
static void release_pixels(void *info, const void *data, size_t size) { free((void *)data); }

static CGImageRef image_of(const struct __ferry_tex *t, BOOL opaque)
{
    unsigned w = t->lw[0], h = t->lh[0];
    if (!w || !h) return NULL;
    size_t row = (size_t)w * 4;
    uint8_t *px = malloc(row * h);
    if (!px) return NULL;
    if (t->f->fmt == MTLPixelFormatBGRA8Unorm || t->f->fmt == MTLPixelFormatBGRA8Unorm_sRGB) {
        for (unsigned y = 0; y < h; y++) memcpy(px + y * row, mtl_texel(t, 0, y, 0, 0, 0), row);
    } else {
        for (unsigned y = 0; y < h; y++)
            for (unsigned x = 0; x < w; x++) {
                float v[4];
                mtl_texel_load(t->f, mtl_texel(t, x, y, 0, 0, 0), v);
                uint8_t *p = px + y * row + x * 4;
                for (int c = 0; c < 4; c++) {
                    float f = v[c] < 0 ? 0 : v[c] > 1 ? 1 : v[c];
                    p[c == 3 ? 3 : 2 - c] = (uint8_t)(f * 255.0f + 0.5f);
                }
            }
    }
    if (opaque)
        for (size_t i = 3; i < row * h; i += 4) px[i] = 255;
    CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, px, row * h, release_pixels);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGImageRef img = CGImageCreate(w, h, 8, 32, row, cs,
                                   (opaque ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaPremultipliedFirst) |
                                       kCGBitmapByteOrder32Little,
                                   dp, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(dp);
    return img;
}

@implementation FerryMTLDrawable
static NSUInteger drawable_ids;
/* The layer asks for a drawable this way (QuartzCore doesn't link Metal). */
+ (instancetype)ferryDrawableForLayer:(id)layer device:(id<MTLDevice>)device width:(NSUInteger)w
                               height:(NSUInteger)h format:(MTLPixelFormat)format slot:(dispatch_semaphore_t)slot
{
    if (!w || !h || w > 16384 || h > 16384) return nil;
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h
                                                                             mipmapped:NO];
    d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> t = [(device ? device : [FerryMTLDevice shared]) newTextureWithDescriptor:d];
    if (!t) return nil;
    FerryMTLDrawable *dr = [[self alloc] init];
    dr->_texture = (FerryMTLTexture *)t;
    dr->_layer = layer; /* (not retained: the layer outlives what it shows) */
    dr->_drawableID = __atomic_add_fetch(&drawable_ids, 1, __ATOMIC_RELAXED);
    dr->_presentedHandlers = [[NSMutableArray alloc] init];
    if (slot) {
        dispatch_retain(slot);
        dr->_slot = slot;
    }
    return [dr autorelease];
}
- (void)dealloc
{
    [_texture release];
    [_presentedHandlers release];
    if (_slot) {
        dispatch_semaphore_signal((dispatch_semaphore_t)_slot);
        dispatch_release((dispatch_semaphore_t)_slot);
    }
    [super dealloc];
}
- (id<MTLTexture>)texture { return _texture; }
- (id)layer { return _layer; }
- (CFTimeInterval)presentedTime { return _presentedTime; }
- (NSUInteger)drawableID { return _drawableID; }
- (void)present
{
    if (_presentedTime) return;
    id layer = _layer;
    BOOL opaque = [layer respondsToSelector:@selector(isOpaque)] && [(id<FerryMTLLayerOpacity>)layer isOpaque];
    CGImageRef img = image_of([_texture ferryTex], opaque);
    _presentedTime = now();
    if (img) {
        NSArray *a = @[ (id)img, @(_drawableID) ];
        CGImageRelease(img);
        if ([layer respondsToSelector:@selector(_ferryShowMetalImage:)])
            [layer performSelectorOnMainThread:@selector(_ferryShowMetalImage:) withObject:a waitUntilDone:NO];
    }
    for (MTLDrawablePresentedHandler h in _presentedHandlers) h(self);
    [_presentedHandlers removeAllObjects];
}
- (void)presentAtTime:(CFTimeInterval)t { [self present]; }
- (void)presentAfterMinimumDuration:(CFTimeInterval)d { [self present]; }
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)block
{
    id b = [block copy];
    [_presentedHandlers addObject:b];
    [b release];
}
@end
