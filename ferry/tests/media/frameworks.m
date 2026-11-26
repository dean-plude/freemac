/* What Qt and OBS ask of IOSurface, Accelerate, Metal, DiskArbitration and
 * Network (freemac 1.232, Ferry 0.56.0). */
#import <Foundation/Foundation.h>
#include <IOSurface/IOSurface.h>
#include <Accelerate/Accelerate.h>
#import <Metal/Metal.h>
#include <DiskArbitration/DiskArbitration.h>
#include <Network/Network.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

int main(void)
{
    @autoreleasepool {
        /* a 640x480 BGRA surface, rows aligned as on a Mac */
        NSDictionary *props = @{
            (__bridge NSString *)kIOSurfaceWidth : @641, (__bridge NSString *)kIOSurfaceHeight : @480,
            (__bridge NSString *)kIOSurfaceBytesPerElement : @4, (__bridge NSString *)kIOSurfacePixelFormat : @(0x42475241),
        };
        IOSurfaceRef s = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        printf("surface %zux%zu bpe %zu row %zu aligned %d format %08x\n", IOSurfaceGetWidth(s), IOSurfaceGetHeight(s),
               IOSurfaceGetBytesPerElement(s), IOSurfaceGetBytesPerRow(s), (int)(IOSurfaceGetBytesPerRow(s) % 16 == 0),
               IOSurfaceGetPixelFormat(s));
        printf("alloc >= rows %d planes %zu\n", (int)(IOSurfaceGetAllocSize(s) >= IOSurfaceGetBytesPerRow(s) * 480),
               IOSurfaceGetPlaneCount(s));
        uint32_t seed0 = IOSurfaceGetSeed(s), seed;
        IOSurfaceLock(s, 0, &seed);
        memset(IOSurfaceGetBaseAddress(s), 0x7f, 16);
        IOSurfaceUnlock(s, 0, &seed);
        IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
        IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, &seed);
        printf("seed went up once %d, unlock with no lock fails %d\n", (int)(seed == seed0 + 1),
               (int)(IOSurfaceUnlock(s, 0, NULL) != 0));
        IOSurfaceRef found = IOSurfaceLookup(IOSurfaceGetID(s));
        printf("lookup finds it %d byte %02x\n", (int)(found == s), ((unsigned char *)IOSurfaceGetBaseAddress(found))[3]);
        CFRelease(found);
        IOSurfaceSetValue(s, CFSTR("FerryNote"), CFSTR("hello"));
        CFTypeRef note = IOSurfaceCopyValue(s, CFSTR("FerryNote"));
        printf("value %s\n", [(__bridge NSString *)note UTF8String]);
        CFRelease(note);
        IOSurfaceIncrementUseCount(s);
        printf("in use %d\n", (int)IOSurfaceIsInUse(s));
        IOSurfaceDecrementUseCount(s);
        IOSurfaceID sid = IOSurfaceGetID(s);
        CFRelease(s);
        printf("gone after release %d\n", (int)(IOSurfaceLookup(sid) == NULL));

        /* two planes, as for NV12 video */
        NSDictionary *nv12 = @{
            (__bridge NSString *)kIOSurfaceWidth : @64, (__bridge NSString *)kIOSurfaceHeight : @32,
            (__bridge NSString *)kIOSurfacePlaneInfo : @[
                @{ (__bridge NSString *)kIOSurfacePlaneWidth : @64, (__bridge NSString *)kIOSurfacePlaneHeight : @32,
                   (__bridge NSString *)kIOSurfacePlaneBytesPerElement : @1 },
                @{ (__bridge NSString *)kIOSurfacePlaneWidth : @32, (__bridge NSString *)kIOSurfacePlaneHeight : @16,
                   (__bridge NSString *)kIOSurfacePlaneBytesPerElement : @2 },
            ],
        };
        IOSurfaceRef v = IOSurfaceCreate((__bridge CFDictionaryRef)nv12);
        ptrdiff_t gap = (char *)IOSurfaceGetBaseAddressOfPlane(v, 1) - (char *)IOSurfaceGetBaseAddressOfPlane(v, 0);
        printf("planes %zu, %zux%zu and %zux%zu, second after first %d\n", IOSurfaceGetPlaneCount(v),
               IOSurfaceGetWidthOfPlane(v, 0), IOSurfaceGetHeightOfPlane(v, 0), IOSurfaceGetWidthOfPlane(v, 1),
               IOSurfaceGetHeightOfPlane(v, 1), (int)(gap >= 64 * 32));
        CFRelease(v);

        /* vImage */
        vImage_Buffer a, b;
        vImageBuffer_Init(&a, 4, 5, 32, kvImageNoFlags);
        vImageBuffer_Init(&b, 4, 5, 32, kvImageNoFlags);
        memset(a.data, 9, a.rowBytes * 4);
        printf("vImage copy %ld rows %d\n", (long)vImageCopyBuffer(&a, &b, 4, 0), (int)(((char *)b.data)[19] == 9));
        free(a.data);
        free(b.data);

        /* a Mac's own math calls, which FFmpeg makes */
        printf("exp10 %g %g sinpi %g cospi %g\n", __exp10(3), (double)__exp10f(-1), __sinpi(0.5), __cospi(1));

        /* no Metal device, no disks */
        printf("metal device %s, devices %lu\n", MTLCreateSystemDefaultDevice() ? "yes" : "none",
               (unsigned long)[MTLCopyAllDevices() count]);
        DASessionRef da = DASessionCreate(NULL);
        printf("disk session %d, disk %d\n", (int)(da != NULL), (int)(DADiskCreateFromBSDName(NULL, da, "disk0") == NULL));
        CFRelease(da);

        /* the path monitor answers once on its queue, then is cancelled */
        dispatch_semaphore_t got = dispatch_semaphore_create(0), done = dispatch_semaphore_create(0);
        nw_path_monitor_t m = nw_path_monitor_create();
        nw_path_monitor_set_update_handler(m, ^(nw_path_t path) {
            nw_path_status_t st = nw_path_get_status(path);
            printf("path status known %d\n", (int)(st == nw_path_status_satisfied || st == nw_path_status_unsatisfied));
            dispatch_semaphore_signal(got);
        });
        nw_path_monitor_set_cancel_handler(m, ^{ dispatch_semaphore_signal(done); });
        nw_path_monitor_set_queue(m, dispatch_queue_create("net", NULL));
        nw_path_monitor_start(m);
        long w1 = dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        nw_path_monitor_cancel(m);
        long w2 = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        printf("updated %d cancelled %d\n", (int)(w1 == 0), (int)(w2 == 0));
        nw_release(m);
    }
    return 0;
}
