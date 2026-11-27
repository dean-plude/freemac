/* SPDX-License-Identifier: GPL-3.0-or-later
 * Metal: the device, a shader library compiled from source,
 * a render pipeline drawing a triangle into a cleared texture (read back
 * texel by texel), indexed drawing with a depth test and blending, a texture
 * sampled in a fragment function, a compute kernel adding two buffers,
 * blits, and a command buffer's handlers. Written from Apple's public Metal
 * documentation; built with ARC, as most Metal programs are. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>

static int fails;
static void check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    if (!ok) fails++;
}

static NSString *const source = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct V { float2 pos [[attribute(0)]]; float4 col [[attribute(1)]]; };\n"
    "struct O { float4 position [[position]]; float4 col; float2 uv; };\n"
    "vertex O vs_tri(V in [[stage_in]], constant float &depth [[buffer(2)]]) {\n"
    "  O o; o.position = float4(in.pos, depth, 1); o.col = in.col; o.uv = in.pos * 0.5 + 0.5; return o;\n"
    "}\n"
    "fragment float4 fs_col(O in [[stage_in]]) { return in.col; }\n"
    "fragment float4 fs_tex(O in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {\n"
    "  return t.sample(s, in.uv);\n"
    "}\n"
    "kernel void add(device float *a [[buffer(0)]], device const float *b [[buffer(1)]],\n"
    "                uint gid [[thread_position_in_grid]]) { a[gid] += b[gid]; }\n";

typedef struct {
    float pos[2];
    float col[4];
} Vert;

static void texel(id<MTLTexture> t, int x, int y, unsigned char out[4])
{
    [t getBytes:out bytesPerRow:4 fromRegion:MTLRegionMake2D(x, y, 1, 1) mipmapLevel:0];
}

static int near(const unsigned char p[4], int b, int g, int r, int a)
{
    int w[4] = {b, g, r, a};
    for (int i = 0; i < 4; i++)
        if (p[i] < w[i] - 2 || p[i] > w[i] + 2) return 0;
    return 1;
}

int main(void)
{
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        check("a device", dev != nil);
        if (!dev) return 1;
        check("a name", dev.name.length > 0);
        check("devices lists it", [MTLCopyAllDevices() containsObject:dev]);
        check("unified memory", dev.hasUnifiedMemory);

        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:source options:nil error:&err];
        check("a library from source", lib != nil);
        if (!lib) {
            printf("  %s\n", err.localizedDescription.UTF8String);
            return 1;
        }
        NSArray *names = [lib.functionNames sortedArrayUsingSelector:@selector(compare:)];
        check("its functions", [names isEqual:(@[ @"add", @"fs_col", @"fs_tex", @"vs_tri" ])]);
        id<MTLFunction> vs = [lib newFunctionWithName:@"vs_tri"];
        check("a vertex function", vs && vs.functionType == MTLFunctionTypeVertex);
        check("a missing function is nil", [lib newFunctionWithName:@"nope"] == nil);
        id<MTLLibrary> bad = [dev newLibraryWithSource:@"kernel void k( { }" options:nil error:&err];
        check("bad source gives an error", bad == nil && err != nil);

        MTLVertexDescriptor *vd = [MTLVertexDescriptor vertexDescriptor];
        vd.attributes[0].format = MTLVertexFormatFloat2;
        vd.attributes[0].offset = 0;
        vd.attributes[0].bufferIndex = 0;
        vd.attributes[1].format = MTLVertexFormatFloat4;
        vd.attributes[1].offset = 8;
        vd.attributes[1].bufferIndex = 0;
        vd.layouts[0].stride = sizeof(Vert);

        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = vs;
        pd.fragmentFunction = [lib newFunctionWithName:@"fs_col"];
        pd.vertexDescriptor = vd;
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        id<MTLRenderPipelineState> pipe = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        check("a render pipeline", pipe != nil);
        if (!pipe) {
            printf("  %s\n", err.localizedDescription.UTF8String);
            return 1;
        }

        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                      width:32
                                                                                     height:32
                                                                                  mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        id<MTLTexture> target = [dev newTextureWithDescriptor:td];
        MTLTextureDescriptor *dd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                      width:32
                                                                                     height:32
                                                                                  mipmapped:NO];
        dd.usage = MTLTextureUsageRenderTarget;
        dd.storageMode = MTLStorageModePrivate;
        id<MTLTexture> depth = [dev newTextureWithDescriptor:dd];
        check("textures", target && depth && target.width == 32);

        /* a red triangle over the lower half, then a green one in front of
         * part of it, and a blue one behind that the depth test hides */
        Vert tri[] = {
            {{-1, -1}, {1, 0, 0, 1}}, {{1, -1}, {1, 0, 0, 1}}, {{0, 1}, {1, 0, 0, 1}},
        };
        Vert quad[] = {
            {{-1, -1}, {0, 1, 0, 1}}, {{0, -1}, {0, 1, 0, 1}}, {{0, 0}, {0, 1, 0, 1}}, {{-1, 0}, {0, 1, 0, 1}},
        };
        uint16_t idx[] = {0, 1, 2, 0, 2, 3};
        id<MTLBuffer> vb = [dev newBufferWithBytes:tri length:sizeof tri options:MTLResourceStorageModeShared];
        id<MTLBuffer> qb = [dev newBufferWithBytes:quad length:sizeof quad options:0];
        id<MTLBuffer> ib = [dev newBufferWithBytes:idx length:sizeof idx options:0];
        check("buffers", vb && qb && ib && vb.length == sizeof tri && !memcmp(vb.contents, tri, sizeof tri));

        MTLDepthStencilDescriptor *dsd = [MTLDepthStencilDescriptor new];
        dsd.depthCompareFunction = MTLCompareFunctionLess;
        dsd.depthWriteEnabled = YES;
        id<MTLDepthStencilState> ds = [dev newDepthStencilStateWithDescriptor:dsd];

        id<MTLCommandQueue> q = [dev newCommandQueue];
        id<MTLCommandBuffer> cb = [q commandBuffer];
        __block int scheduled = 0, completed = 0;
        [cb addScheduledHandler:^(id<MTLCommandBuffer> b) { scheduled++; }];
        [cb addCompletedHandler:^(id<MTLCommandBuffer> b) { completed++; }];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = target;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0.5, 1);
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.depthAttachment.texture = depth;
        rp.depthAttachment.loadAction = MTLLoadActionClear;
        rp.depthAttachment.clearDepth = 1.0;
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:pipe];
        [enc setDepthStencilState:ds];
        float z = 0.5f;
        [enc setVertexBytes:&z length:sizeof z atIndex:2];
        [enc setVertexBuffer:vb offset:0 atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        z = 0.25f;
        [enc setVertexBytes:&z length:sizeof z atIndex:2];
        [enc setVertexBuffer:qb offset:0 atIndex:0];
        [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                        indexCount:6
                         indexType:MTLIndexTypeUInt16
                       indexBuffer:ib
                 indexBufferOffset:0];
        /* behind both: hidden where they are */
        z = 0.75f;
        for (int i = 0; i < 4; i++) quad[i].col[1] = 0, quad[i].col[2] = 1;
        [enc setVertexBytes:quad length:sizeof quad atIndex:0];
        [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                        indexCount:6
                         indexType:MTLIndexTypeUInt16
                       indexBuffer:ib
                 indexBufferOffset:0];
        [enc endEncoding];
        [cb commit];
        [cb waitUntilCompleted];
        check("the command buffer completed", cb.status == MTLCommandBufferStatusCompleted && cb.error == nil);
        check("its handlers ran", scheduled == 1 && completed == 1);

        unsigned char p[4];
        texel(target, 1, 1, p); /* top left: the clear */
        check("the clear color", near(p, 128, 0, 0, 255));
        texel(target, 16, 20, p); /* lower middle: the red triangle */
        check("the triangle", near(p, 0, 0, 255, 255));
        texel(target, 4, 28, p); /* lower left: the green quad in front */
        check("the quad in front", near(p, 0, 255, 0, 255));
        texel(target, 28, 10, p); /* right of the triangle's top */
        check("outside the triangle", near(p, 128, 0, 0, 255));

        /* a 2x2 texture sampled, nearest, over a whole target */
        MTLTextureDescriptor *sd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                      width:2
                                                                                     height:2
                                                                                  mipmapped:NO];
        id<MTLTexture> small = [dev newTextureWithDescriptor:sd];
        unsigned char px[16] = {255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255};
        [small replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:px bytesPerRow:8];
        MTLSamplerDescriptor *smp = [MTLSamplerDescriptor new];
        smp.minFilter = smp.magFilter = MTLSamplerMinMagFilterNearest;
        id<MTLSamplerState> sampler = [dev newSamplerStateWithDescriptor:smp];
        pd.fragmentFunction = [lib newFunctionWithName:@"fs_tex"];
        pd.depthAttachmentPixelFormat = MTLPixelFormatInvalid;
        id<MTLRenderPipelineState> texPipe = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        check("a texturing pipeline", texPipe != nil);
        Vert full[] = {{{-1, -1}, {0}}, {{3, -1}, {0}}, {{-1, 3}, {0}}};
        cb = [q commandBuffer];
        rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = target;
        rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        enc = [cb renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:texPipe];
        z = 0;
        [enc setVertexBytes:&z length:sizeof z atIndex:2];
        [enc setVertexBytes:full length:sizeof full atIndex:0];
        [enc setFragmentTexture:small atIndex:0];
        [enc setFragmentSamplerState:sampler atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
        [cb commit];
        [cb waitUntilCompleted];
        /* uv.y grows upward on screen, row 0 of the texture is at the bottom */
        texel(target, 4, 28, p);
        check("sampled bottom left", near(p, 0, 0, 255, 255));
        texel(target, 28, 28, p);
        check("sampled bottom right", near(p, 0, 255, 0, 255));
        texel(target, 4, 4, p);
        check("sampled top left", near(p, 255, 0, 0, 255));
        texel(target, 28, 4, p);
        check("sampled top right", near(p, 255, 255, 255, 255));

        /* a compute kernel */
        id<MTLComputePipelineState> cp = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"add"]
                                                                            error:&err];
        check("a compute pipeline", cp != nil && cp.maxTotalThreadsPerThreadgroup > 0);
        enum { N = 1000 };
        id<MTLBuffer> a = [dev newBufferWithLength:N * 4 options:0], b = [dev newBufferWithLength:N * 4 options:0];
        float *fa = a.contents, *fb = b.contents;
        for (int i = 0; i < N; i++) fa[i] = i, fb[i] = 2 * i;
        cb = [q commandBuffer];
        id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
        [ce setComputePipelineState:cp];
        [ce setBuffer:a offset:0 atIndex:0];
        [ce setBuffer:b offset:0 atIndex:1];
        [ce dispatchThreads:MTLSizeMake(N, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
        [ce endEncoding];

        /* blits: a buffer filled, copied to another, and the target into a buffer */
        id<MTLBuffer> c = [dev newBufferWithLength:64 options:0], d = [dev newBufferWithLength:64 options:0];
        id<MTLBuffer> out = [dev newBufferWithLength:32 * 32 * 4 options:0];
        id<MTLBlitCommandEncoder> be = [cb blitCommandEncoder];
        [be fillBuffer:c range:NSMakeRange(0, 64) value:7];
        [be copyFromBuffer:c sourceOffset:0 toBuffer:d destinationOffset:0 size:64];
        [be copyFromTexture:target
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(32, 32, 1)
                        toBuffer:out
               destinationOffset:0
          destinationBytesPerRow:128
        destinationBytesPerImage:128 * 32];
        [be endEncoding];
        [cb commit];
        [cb waitUntilCompleted];
        int ok = 1;
        for (int i = 0; i < N; i++)
            if (fa[i] != 3 * i) ok = 0;
        check("the kernel added", ok);
        check("a filled and copied buffer", ((unsigned char *)d.contents)[63] == 7);
        check("the texture copied to a buffer", near((unsigned char *)out.contents + (4 * 32 + 4) * 4, 255, 0, 0, 255));
    }
    return fails != 0;
}
