/* SPDX-License-Identifier: GPL-3.0-or-later
 * Metal: shader code that never waits for a quad's other pixels or at a
 * threadgroup barrier runs its lanes one after another, without fibers
 * (freemac 1.268); code that does still waits. Each is drawn or run and
 * read back: a blended, discarding fragment function and a kernel with no
 * barrier from one library, and a derivative and a barrier reduction from
 * another. Written from Apple's public Metal documentation. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>

static NSString *const plain = @
    "#include <metal_stdlib>\nusing namespace metal;\n"
    "struct O { float4 position [[position]]; float2 uv; };\n"
    "vertex O vs_full(uint vid [[vertex_id]]) {\n"
    "  float2 c[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};\n"
    "  O o; o.position = float4(c[vid], 0, 1); o.uv = c[vid] * 0.5 + 0.5; return o; }\n"
    "fragment float4 fs_half(O in [[stage_in]]) {\n"
    "  if (in.uv.y > 0.5) discard_fragment(); return float4(0, 0, 1, 0.5); }\n"
    "kernel void twice(device float *a [[buffer(0)]], uint i [[thread_position_in_grid]]) { a[i] *= 2; }\n";
static NSString *const waiting = @
    "#include <metal_stdlib>\nusing namespace metal;\n"
    "struct O { float4 position [[position]]; float2 uv; };\n"
    "vertex O vs_full(uint vid [[vertex_id]]) {\n"
    "  float2 c[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};\n"
    "  O o; o.position = float4(c[vid], 0, 1); o.uv = c[vid] * 0.5 + 0.5; return o; }\n"
    "fragment float4 fs_slope(O in [[stage_in]]) { return float4(dfdx(in.uv.x) * 16, 0, 0, 1); }\n"
    "kernel void sum(device const float *a [[buffer(0)]], device float *out [[buffer(1)]],\n"
    "                threadgroup float *t [[threadgroup(0)]], uint i [[thread_position_in_threadgroup]],\n"
    "                uint g [[threadgroup_position_in_grid]], uint n [[threads_per_threadgroup]]) {\n"
    "  t[i] = a[g * n + i];\n"
    "  for (uint s = n / 2; s > 0; s /= 2) {\n"
    "    threadgroup_barrier(mem_flags::mem_threadgroup);\n"
    "    if (i < s) t[i] += t[i + s];\n"
    "  }\n"
    "  if (i == 0) out[g] = t[0];\n"
    "}\n";

static id<MTLTexture> target(id<MTLDevice> dev)
{
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                  width:16
                                                                                 height:16
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    return [dev newTextureWithDescriptor:td];
}
static void draw(id<MTLCommandQueue> q, id<MTLRenderPipelineState> p, id<MTLTexture> t)
{
    id<MTLCommandBuffer> cb = [q commandBuffer];
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = t;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    [e setRenderPipelineState:p];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [e endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
}
static void texel(id<MTLTexture> t, int x, int y, unsigned char out[4])
{
    [t getBytes:out bytesPerRow:4 fromRegion:MTLRegionMake2D(x, y, 1, 1) mipmapLevel:0];
}

int main(void)
{
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> q = [dev newCommandQueue];
        NSError *err = nil;
        id<MTLLibrary> a = [dev newLibraryWithSource:plain options:nil error:&err];
        id<MTLLibrary> b = [dev newLibraryWithSource:waiting options:nil error:&err];
        printf("libraries: %s\n", a && b ? "yes" : err.localizedDescription.UTF8String);
        if (!a || !b) return 1;

        /* half of a white target, blended half blue over it */
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [a newFunctionWithName:@"vs_full"];
        pd.fragmentFunction = [a newFunctionWithName:@"fs_half"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pd.colorAttachments[0].blendingEnabled = YES;
        pd.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pd.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pd.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        pd.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        id<MTLTexture> t = target(dev);
        draw(q, [dev newRenderPipelineStateWithDescriptor:pd error:&err], t);
        unsigned char top[4], bottom[4];
        texel(t, 8, 2, top);
        texel(t, 8, 13, bottom);
        /* row 0 is the top, where uv.y is above a half and the fragment is discarded */
        printf("discarded half (BGRA): %d %d %d %d, blended half: %d %d %d %d\n", top[0], top[1], top[2], top[3],
               bottom[0], bottom[1], bottom[2], bottom[3]);

        /* derivatives: uv.x grows 1/16 a pixel */
        pd.fragmentFunction = [b newFunctionWithName:@"fs_slope"];
        pd.vertexFunction = [b newFunctionWithName:@"vs_full"];
        pd.colorAttachments[0].blendingEnabled = NO;
        draw(q, [dev newRenderPipelineStateWithDescriptor:pd error:&err], t);
        unsigned char px[4];
        texel(t, 5, 5, px);
        printf("dfdx across the quad: red %d\n", px[2]);

        /* a kernel with no barrier, and one reducing in threadgroup memory */
        float in[256], two[256];
        for (int i = 0; i < 256; i++) in[i] = two[i] = (float)i;
        id<MTLBuffer> bt = [dev newBufferWithBytes:two length:sizeof two options:0];
        id<MTLBuffer> bi = [dev newBufferWithBytes:in length:sizeof in options:0];
        id<MTLBuffer> bo = [dev newBufferWithLength:4 * sizeof(float) options:0];
        id<MTLComputePipelineState> ct = [dev newComputePipelineStateWithFunction:[a newFunctionWithName:@"twice"] error:&err];
        id<MTLComputePipelineState> cs = [dev newComputePipelineStateWithFunction:[b newFunctionWithName:@"sum"] error:&err];
        id<MTLCommandBuffer> cb = [q commandBuffer];
        id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
        [ce setComputePipelineState:ct];
        [ce setBuffer:bt offset:0 atIndex:0];
        [ce dispatchThreadgroups:MTLSizeMake(4, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
        [ce setComputePipelineState:cs];
        [ce setBuffer:bi offset:0 atIndex:0];
        [ce setBuffer:bo offset:0 atIndex:1];
        [ce setThreadgroupMemoryLength:64 * sizeof(float) atIndex:0];
        [ce dispatchThreadgroups:MTLSizeMake(4, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
        [ce endEncoding];
        [cb commit];
        [cb waitUntilCompleted];
        const float *r2 = bt.contents, *rs = bo.contents;
        int doubled = 1;
        for (int i = 0; i < 256; i++) doubled &= r2[i] == 2.0f * i;
        printf("doubled: %s, sums of 64: %.0f %.0f %.0f %.0f\n", doubled ? "yes" : "no", rs[0], rs[1], rs[2], rs[3]);
    }
    return 0;
}
