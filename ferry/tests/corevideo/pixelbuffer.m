/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Video's pixel buffers (freemac 1.235, Ferry 0.59.0), with no
 * OpenGL: the layout of a 4:2:0 bi-planar buffer ('420v') and of the other
 * formats VLC and OBS use, the IOSurface under each, attachments, pools
 * and pixel format descriptions. */
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#include <IOSurface/IOSurface.h>
#include <stdio.h>
#include <string.h>

static int check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    return ok;
}

static void released(void *refCon, const void *base) { *(int *)refCon = 1; }

int main(void)
{
    @autoreleasepool {
        /* 420v: Y at full size, CbCr pairs at half */
        CVPixelBufferRef pb = NULL;
        CVReturn r = CVPixelBufferCreate(NULL, 640, 480, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pb);
        check("a 640 by 480 420v buffer", r == kCVReturnSuccess && pb);
        check("its type", CFGetTypeID(pb) == CVPixelBufferGetTypeID());
        check("planar, two planes", CVPixelBufferIsPlanar(pb) && CVPixelBufferGetPlaneCount(pb) == 2);
        check("Y plane 640 by 480, 640 bytes a row",
              CVPixelBufferGetWidthOfPlane(pb, 0) == 640 && CVPixelBufferGetHeightOfPlane(pb, 0) == 480 &&
                  CVPixelBufferGetBytesPerRowOfPlane(pb, 0) == 640);
        check("CbCr plane 320 by 240, 640 bytes a row",
              CVPixelBufferGetWidthOfPlane(pb, 1) == 320 && CVPixelBufferGetHeightOfPlane(pb, 1) == 240 &&
                  CVPixelBufferGetBytesPerRowOfPlane(pb, 1) == 640);
        check("no plane 2", CVPixelBufferGetBaseAddressOfPlane(pb, 2) == NULL);
        check("bytes per row 0 for a planar buffer", CVPixelBufferGetBytesPerRow(pb) == 0);
        CVPixelBufferLockBaseAddress(pb, 0);
        unsigned char *base = CVPixelBufferGetBaseAddress(pb);
        unsigned char *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
        check("Y after the plane table", y > base && (y - base) % 64 == 0);
        check("CbCr after Y", uv >= y + 640 * 480 && (uv - base) % 64 == 0);
        CVPlanarPixelBufferInfo_YCbCrBiPlanar *info = (void *)base;
        check("plane table: Y's offset and row bytes, big-endian",
              (unsigned char *)base + CFSwapInt32BigToHost((uint32_t)info->componentInfoY.offset) == y &&
                  CFSwapInt32BigToHost(info->componentInfoY.rowBytes) == 640);
        check("plane table: CbCr's",
              (unsigned char *)base + CFSwapInt32BigToHost((uint32_t)info->componentInfoCbCr.offset) == uv &&
                  CFSwapInt32BigToHost(info->componentInfoCbCr.rowBytes) == 640);
        check("data size covers both planes", CVPixelBufferGetDataSize(pb) >= (size_t)(uv - base) + 640 * 240);
        memset(y, 16, 640 * 480);
        memset(uv, 128, 640 * 240);
        y[639] = 235;
        uv[640 * 239 + 639] = 240;
        CVPixelBufferUnlockBaseAddress(pb, 0);
        check("one unlock too many fails", CVPixelBufferUnlockBaseAddress(pb, 0) != kCVReturnSuccess);

        /* the IOSurface under it */
        IOSurfaceRef s = CVPixelBufferGetIOSurface(pb);
        check("on an IOSurface", s != NULL);
        check("the surface's planes are the buffer's",
              IOSurfaceGetPlaneCount(s) == 2 && IOSurfaceGetBaseAddressOfPlane(s, 0) == y &&
                  IOSurfaceGetBaseAddressOfPlane(s, 1) == uv && IOSurfaceGetBytesPerRowOfPlane(s, 1) == 640 &&
                  IOSurfaceGetWidthOfPlane(s, 1) == 320 && IOSurfaceGetHeightOfPlane(s, 1) == 240);
        check("the surface's format and size", IOSurfaceGetPixelFormat(s) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange &&
                                                  IOSurfaceGetWidth(s) == 640 && IOSurfaceGetHeight(s) == 480);
        IOSurfaceRef found = IOSurfaceLookup(IOSurfaceGetID(s));
        check("found by its ID", found == s);
        if (found)
            CFRelease(found);
        CVPixelBufferRef again = NULL;
        CVPixelBufferCreateWithIOSurface(NULL, s, NULL, &again);
        check("a buffer made from the surface sees the same pixels",
              again && CVPixelBufferGetPlaneCount(again) == 2 &&
                  ((unsigned char *)CVPixelBufferGetBaseAddressOfPlane(again, 0))[639] == 235 &&
                  ((unsigned char *)CVPixelBufferGetBaseAddressOfPlane(again, 1))[640 * 239 + 639] == 240 &&
                  CVPixelBufferGetIOSurface(again) == s);
        CVPixelBufferRelease(again);

        /* attachments */
        CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                              kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(pb, CFSTR("Mine"), CFSTR("not passed on"), kCVAttachmentMode_ShouldNotPropagate);
        CVAttachmentMode mode = 99;
        CFTypeRef m = CVBufferGetAttachment(pb, kCVImageBufferYCbCrMatrixKey, &mode);
        check("an attachment and its mode",
              m && CFEqual(m, CFSTR("ITU_R_709_2")) && mode == kCVAttachmentMode_ShouldPropagate);
        CFDictionaryRef all = CVBufferGetAttachments(pb, kCVAttachmentMode_ShouldNotPropagate);
        check("the ones not passed on", all && CFDictionaryGetCount(all) == 1);
        CVPixelBufferRef other = NULL;
        CVPixelBufferCreate(NULL, 16, 16, kCVPixelFormatType_32BGRA, NULL, &other);
        CVBufferPropagateAttachments(pb, other);
        check("propagated: only the propagating ones", CVBufferHasAttachment(other, kCVImageBufferYCbCrMatrixKey) &&
                                                           !CVBufferHasAttachment(other, CFSTR("Mine")));
        CVBufferRemoveAttachment(pb, CFSTR("Mine"));
        check("removed", !CVBufferHasAttachment(pb, CFSTR("Mine")));
        CVBufferSetAttachment(pb, kCVImageBufferPixelAspectRatioKey,
                              (CFDictionaryRef) @{@"HorizontalSpacing" : @4, @"VerticalSpacing" : @3},
                              kCVAttachmentMode_ShouldPropagate);
        CGSize ds = CVImageBufferGetDisplaySize(pb);
        check("display size from the pixel aspect ratio", ds.width == 640 * 4 / 3.0 && ds.height == 480);
        CVPixelBufferRelease(other);
        CVPixelBufferRelease(pb);

        /* odd sizes round the chroma planes up */
        CVPixelBufferCreate(NULL, 641, 481, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, NULL, &pb);
        check("420f 641 by 481: CbCr 321 by 241, rows of 704 bytes",
              CVPixelBufferGetWidthOfPlane(pb, 1) == 321 && CVPixelBufferGetHeightOfPlane(pb, 1) == 241 &&
                  CVPixelBufferGetBytesPerRowOfPlane(pb, 0) == 704 && CVPixelBufferGetBytesPerRowOfPlane(pb, 1) == 704);
        CVPixelBufferRelease(pb);

        /* y420: three planes */
        CVPixelBufferCreate(NULL, 320, 240, kCVPixelFormatType_420YpCbCr8Planar, NULL, &pb);
        check("y420: three planes, 320, 160 and 160 wide",
              CVPixelBufferGetPlaneCount(pb) == 3 && CVPixelBufferGetWidthOfPlane(pb, 0) == 320 &&
                  CVPixelBufferGetWidthOfPlane(pb, 1) == 160 && CVPixelBufferGetHeightOfPlane(pb, 2) == 120 &&
                  CVPixelBufferGetBaseAddressOfPlane(pb, 2) > CVPixelBufferGetBaseAddressOfPlane(pb, 1));
        CVPixelBufferRelease(pb);

        /* packed formats */
        CVPixelBufferCreate(NULL, 100, 10, kCVPixelFormatType_32BGRA, NULL, &pb);
        check("BGRA 100 wide: 448 bytes a row, not planar", CVPixelBufferGetBytesPerRow(pb) == 448 &&
                                                                !CVPixelBufferIsPlanar(pb) &&
                                                                CVPixelBufferGetPlaneCount(pb) == 0);
        check("BGRA's base address is the surface's",
              CVPixelBufferGetBaseAddress(pb) == IOSurfaceGetBaseAddress(CVPixelBufferGetIOSurface(pb)));
        CVPixelBufferRelease(pb);
        CVPixelBufferCreate(NULL, 100, 10, kCVPixelFormatType_32BGRA,
                            (CFDictionaryRef) @{(id)kCVPixelBufferBytesPerRowAlignmentKey : @16}, &pb);
        check("aligned to 16 when asked: 400 bytes a row", CVPixelBufferGetBytesPerRow(pb) == 400);
        CFDictionaryRef ca = CVPixelBufferCopyCreationAttributes(pb);
        check("creation attributes", ca && [[(NSDictionary *)ca objectForKey:@"Width"] intValue] == 100);
        if (ca)
            CFRelease(ca);
        CVPixelBufferRelease(pb);
        CVPixelBufferCreate(NULL, 99, 4, kCVPixelFormatType_422YpCbCr8, NULL, &pb);
        check("2vuy 99 wide: 200 bytes of pixels in a 256-byte row", CVPixelBufferGetBytesPerRow(pb) == 256);
        CVPixelBufferRelease(pb);
        check("an unknown format refused",
              CVPixelBufferCreate(NULL, 8, 8, 'zzzz', NULL, &pb) == kCVReturnInvalidPixelFormat && !pb);
        check("no size refused", CVPixelBufferCreate(NULL, 0, 8, kCVPixelFormatType_32BGRA, NULL, &pb) ==
                                     kCVReturnInvalidSize);

        /* the program's own memory */
        static unsigned char mine[64 * 8];
        int freed = 0;
        CVPixelBufferCreateWithBytes(NULL, 16, 8, kCVPixelFormatType_32BGRA, mine, 64, released, &freed, NULL, &pb);
        check("a buffer of the program's memory", CVPixelBufferGetBaseAddress(pb) == mine &&
                                                      CVPixelBufferGetBytesPerRow(pb) == 64 &&
                                                      CVPixelBufferGetIOSurface(pb) == NULL);
        CVPixelBufferRelease(pb);
        check("its release callback called", freed);

        /* pools: a buffer let go is used again */
        CVPixelBufferPoolRef pool = NULL;
        NSDictionary *attrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferWidthKey : @1280,
            (id)kCVPixelBufferHeightKey : @720,
            (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
        };
        r = CVPixelBufferPoolCreate(NULL, NULL, (CFDictionaryRef)attrs, &pool);
        check("a pool", r == kCVReturnSuccess && pool);
        CVPixelBufferRef a = NULL, b = NULL, c = NULL;
        CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &a);
        CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &b);
        check("two buffers from it, 1280 by 720, different", a && b && a != b && CVPixelBufferGetWidth(a) == 1280 &&
                                                                  CVPixelBufferGetPlaneCount(b) == 2);
        CVBufferSetAttachment(a, CFSTR("Old"), kCFBooleanTrue, kCVAttachmentMode_ShouldPropagate);
        CVPixelBufferRelease(a);
        CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &c);
        check("the one let go comes back, without its attachments", c == a && !CVBufferHasAttachment(c, CFSTR("Old")));
        CVPixelBufferRef d = NULL;
        r = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            NULL, pool, (CFDictionaryRef) @{(id)kCVPixelBufferPoolAllocationThresholdKey : @2}, &d);
        check("the allocation threshold", r == kCVReturnWouldExceedAllocationThreshold && !d);
        check("the pool's buffer attributes",
              [[(NSDictionary *)CVPixelBufferPoolGetPixelBufferAttributes(pool) objectForKey:@"Width"] intValue] == 1280);
        CVPixelBufferRelease(b);
        CVPixelBufferRelease(c);
        CVPixelBufferPoolFlush(pool, kCVPixelBufferPoolFlushExcessBuffers);
        CVPixelBufferPoolRelease(pool);

        /* pixel format descriptions */
        NSDictionary *desc = (NSDictionary *)CVPixelFormatDescriptionCreateWithPixelFormatType(
            NULL, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
        check("420v's description: YCbCr, two planes, the second subsampled",
              [[desc objectForKey:(id)kCVPixelFormatContainsYCbCr] boolValue] &&
                  [[desc objectForKey:(id)kCVPixelFormatPlanes] count] == 2 &&
                  [[[[desc objectForKey:(id)kCVPixelFormatPlanes] objectAtIndex:1]
                      objectForKey:(id)kCVPixelFormatVerticalSubsampling] intValue] == 2);
        [desc release];
        desc = (NSDictionary *)CVPixelFormatDescriptionCreateWithPixelFormatType(NULL, kCVPixelFormatType_32BGRA);
        check("BGRA's: 32 bits, alpha, OpenGL's BGRA", [[desc objectForKey:(id)kCVPixelFormatBitsPerBlock] intValue] == 32 &&
                                                          [[desc objectForKey:(id)kCVPixelFormatContainsAlpha] boolValue] &&
                                                          [[desc objectForKey:(id)kCVPixelFormatOpenGLFormat] intValue] == 0x80E1);
        [desc release];
        NSArray *every = (NSArray *)CVPixelFormatDescriptionArrayCreateWithAllPixelFormatTypes(NULL);
        check("every format listed, 420v and y420 among them",
              [every containsObject:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)] &&
                  [every containsObject:@(kCVPixelFormatType_420YpCbCr8Planar)]);
        [every release];

        /* host time */
        uint64_t t0 = CVGetCurrentHostTime();
        usleep(20000);
        double took = (double)(CVGetCurrentHostTime() - t0) / CVGetHostClockFrequency();
        check("host time runs at its frequency", took > 0.015 && took < 0.5);
    }
    return 0;
}
