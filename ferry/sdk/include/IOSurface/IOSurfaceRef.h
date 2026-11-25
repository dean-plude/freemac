/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: IOSurface, written from Apple's public IOSurface documentation;
 * not Apple's header. Ferry's surfaces are plain memory in this program
 * (media/IOSurface.m): they can be made, locked, read and written, and
 * shared between the program's own threads and layers, but not between
 * programs, and a surface's global ID finds it only in this program. */
#ifndef _FERRY_IOSURFACE_IOSURFACEREF_H_
#define _FERRY_IOSURFACE_IOSURFACEREF_H_
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <MacTypes.h>
__FERRY_BEGIN

typedef struct CF_BRIDGED_TYPE(IOSurface) __IOSurface *IOSurfaceRef;
typedef uint32_t IOSurfaceID;

typedef CF_OPTIONS(uint32_t, IOSurfaceLockOptions) {
    kIOSurfaceLockReadOnly = 0x00000001,
    kIOSurfaceLockAvoidSync = 0x00000002,
};
typedef CF_OPTIONS(uint32_t, IOSurfacePurgeabilityState) {
    kIOSurfacePurgeableNonVolatile = 0,
    kIOSurfacePurgeableVolatile = 1,
    kIOSurfacePurgeableEmpty = 2,
    kIOSurfacePurgeableKeepCurrent = 3,
};
enum { kIOSurfaceSuccess = 0 };

extern const CFStringRef kIOSurfaceAllocSize;
extern const CFStringRef kIOSurfaceWidth;
extern const CFStringRef kIOSurfaceHeight;
extern const CFStringRef kIOSurfaceBytesPerRow;
extern const CFStringRef kIOSurfaceBytesPerElement;
extern const CFStringRef kIOSurfaceElementWidth;
extern const CFStringRef kIOSurfaceElementHeight;
extern const CFStringRef kIOSurfaceOffset;
extern const CFStringRef kIOSurfacePlaneInfo;
extern const CFStringRef kIOSurfacePlaneWidth;
extern const CFStringRef kIOSurfacePlaneHeight;
extern const CFStringRef kIOSurfacePlaneBytesPerRow;
extern const CFStringRef kIOSurfacePlaneOffset;
extern const CFStringRef kIOSurfacePlaneSize;
extern const CFStringRef kIOSurfacePlaneBase;
extern const CFStringRef kIOSurfacePlaneBytesPerElement;
extern const CFStringRef kIOSurfacePlaneElementWidth;
extern const CFStringRef kIOSurfacePlaneElementHeight;
extern const CFStringRef kIOSurfaceCacheMode;
extern const CFStringRef kIOSurfaceIsGlobal;
extern const CFStringRef kIOSurfacePixelFormat;
extern const CFStringRef kIOSurfaceName;
extern const CFStringRef kIOSurfaceColorSpace;
extern const CFStringRef kIOSurfaceICCProfile;

CFTypeID IOSurfaceGetTypeID(void);
IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties) CF_RETURNS_RETAINED;
IOSurfaceRef IOSurfaceLookup(IOSurfaceID csid) CF_RETURNS_RETAINED;
IOSurfaceID IOSurfaceGetID(IOSurfaceRef buffer);
kern_return_t IOSurfaceLock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t *seed);
kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t *seed);
size_t IOSurfaceGetAllocSize(IOSurfaceRef buffer);
size_t IOSurfaceGetWidth(IOSurfaceRef buffer);
size_t IOSurfaceGetHeight(IOSurfaceRef buffer);
size_t IOSurfaceGetBytesPerElement(IOSurfaceRef buffer);
size_t IOSurfaceGetBytesPerRow(IOSurfaceRef buffer);
void *IOSurfaceGetBaseAddress(IOSurfaceRef buffer);
size_t IOSurfaceGetElementWidth(IOSurfaceRef buffer);
size_t IOSurfaceGetElementHeight(IOSurfaceRef buffer);
OSType IOSurfaceGetPixelFormat(IOSurfaceRef buffer);
uint32_t IOSurfaceGetSeed(IOSurfaceRef buffer);
size_t IOSurfaceGetPlaneCount(IOSurfaceRef buffer);
size_t IOSurfaceGetWidthOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetHeightOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetBytesPerElementOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetBytesPerRowOfPlane(IOSurfaceRef buffer, size_t planeIndex);
void *IOSurfaceGetBaseAddressOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetElementWidthOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetElementHeightOfPlane(IOSurfaceRef buffer, size_t planeIndex);
void IOSurfaceSetValue(IOSurfaceRef buffer, CFStringRef key, CFTypeRef value);
CFTypeRef IOSurfaceCopyValue(IOSurfaceRef buffer, CFStringRef key) CF_RETURNS_RETAINED;
void IOSurfaceRemoveValue(IOSurfaceRef buffer, CFStringRef key);
void IOSurfaceSetValues(IOSurfaceRef buffer, CFDictionaryRef keysAndValues);
CFDictionaryRef IOSurfaceCopyAllValues(IOSurfaceRef buffer) CF_RETURNS_RETAINED;
void IOSurfaceRemoveAllValues(IOSurfaceRef buffer);
size_t IOSurfaceGetPropertyMaximum(CFStringRef property);
size_t IOSurfaceGetPropertyAlignment(CFStringRef property);
size_t IOSurfaceAlignProperty(CFStringRef property, size_t value);
void IOSurfaceIncrementUseCount(IOSurfaceRef buffer);
void IOSurfaceDecrementUseCount(IOSurfaceRef buffer);
int32_t IOSurfaceGetUseCount(IOSurfaceRef buffer);
Boolean IOSurfaceIsInUse(IOSurfaceRef buffer);
Boolean IOSurfaceAllowsPixelSizeCasting(IOSurfaceRef buffer);
kern_return_t IOSurfaceSetPurgeable(IOSurfaceRef buffer, uint32_t newState, uint32_t *oldState);
mach_port_t IOSurfaceCreateMachPort(IOSurfaceRef buffer);
IOSurfaceRef IOSurfaceLookupFromMachPort(mach_port_t port) CF_RETURNS_RETAINED;

__FERRY_END
#endif
