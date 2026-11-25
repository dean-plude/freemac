/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: IOSurface, shared image buffers (freemac 1.235, Ferry 0.59.0).
 * Written for freemac from Apple's public IOSurface reference; not Apple's
 * header. Every call declared here is implemented in ferry/iosurface. A
 * surface is memory of this program's own: it can be looked up by its ID
 * and its Mach port within the program, not from another program. An
 * IOSurfaceRef is the Objective-C class IOSurface, as on a Mac. */
#ifndef _FERRY_IOSURFACE_IOSURFACE_H_
#define _FERRY_IOSURFACE_IOSURFACE_H_
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOReturn.h>
#include <mach/mach.h>
#include <MacTypes.h>

__FERRY_BEGIN

#ifndef _FERRY_IOSURFACEREF_DEFINED
#define _FERRY_IOSURFACEREF_DEFINED
#if defined(__has_attribute) && __has_attribute(objc_bridge)
typedef struct __attribute__((objc_bridge(id))) __IOSurface *IOSurfaceRef;
#else
typedef struct __IOSurface *IOSurfaceRef;
#endif
#endif

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

typedef CF_ENUM(int32_t, IOSurfaceComponentName) {
    kIOSurfaceComponentNameUnknown = 0,
    kIOSurfaceComponentNameAlpha = 1,
    kIOSurfaceComponentNameRed = 2,
    kIOSurfaceComponentNameGreen = 3,
    kIOSurfaceComponentNameBlue = 4,
    kIOSurfaceComponentNameLuma = 5,
    kIOSurfaceComponentNameChromaRed = 6,
    kIOSurfaceComponentNameChromaBlue = 7,
};

enum {
    kIOSurfaceDefaultCache = 0,
    kIOSurfaceInhibitCache = 1,
    kIOSurfaceWriteThruCache = 2,
    kIOSurfaceCopybackCache = 3,
    kIOSurfaceWriteCombineCache = 4,
    kIOSurfaceCopybackInnerCache = 5,
};
enum {
    kIOSurfaceMapCacheShift = 8,
    kIOSurfaceMapDefaultCache = kIOSurfaceDefaultCache << kIOSurfaceMapCacheShift,
    kIOSurfaceMapInhibitCache = kIOSurfaceInhibitCache << kIOSurfaceMapCacheShift,
    kIOSurfaceMapWriteThruCache = kIOSurfaceWriteThruCache << kIOSurfaceMapCacheShift,
    kIOSurfaceMapCopybackCache = kIOSurfaceCopybackCache << kIOSurfaceMapCacheShift,
    kIOSurfaceMapWriteCombineCache = kIOSurfaceWriteCombineCache << kIOSurfaceMapCacheShift,
    kIOSurfaceMapCopybackInnerCache = kIOSurfaceCopybackInnerCache << kIOSurfaceMapCacheShift,
};

/* the properties a surface is made with, and those of each plane */
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
extern const CFStringRef kIOSurfacePlaneBitsPerElement;
extern const CFStringRef kIOSurfacePlaneBytesPerElement;
extern const CFStringRef kIOSurfacePlaneElementWidth;
extern const CFStringRef kIOSurfacePlaneElementHeight;
extern const CFStringRef kIOSurfaceCacheMode;
extern const CFStringRef kIOSurfaceIsGlobal;
extern const CFStringRef kIOSurfacePixelFormat;
extern const CFStringRef kIOSurfacePixelSizeCastingAllowed;
extern const CFStringRef kIOSurfacePlaneComponentBitDepths;
extern const CFStringRef kIOSurfacePlaneComponentBitOffsets;
extern const CFStringRef kIOSurfaceName;

CFTypeID IOSurfaceGetTypeID(void);
IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties) CF_RETURNS_RETAINED;
IOSurfaceRef IOSurfaceLookup(IOSurfaceID csid) CF_RETURNS_RETAINED;
IOSurfaceID IOSurfaceGetID(IOSurfaceRef buffer);
IOReturn IOSurfaceLock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t *seed);
IOReturn IOSurfaceUnlock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t *seed);
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
size_t IOSurfaceGetNumberOfComponentsOfPlane(IOSurfaceRef buffer, size_t planeIndex);
IOSurfaceComponentName IOSurfaceGetNameOfComponentOfPlane(IOSurfaceRef buffer, size_t planeIndex,
                                                          size_t componentIndex);
uint8_t IOSurfaceGetBitDepthOfComponentOfPlane(IOSurfaceRef buffer, size_t planeIndex, size_t componentIndex);
uint8_t IOSurfaceGetBitOffsetOfComponentOfPlane(IOSurfaceRef buffer, size_t planeIndex, size_t componentIndex);
void IOSurfaceSetValue(IOSurfaceRef buffer, CFStringRef key, CFTypeRef value);
CFTypeRef IOSurfaceCopyValue(IOSurfaceRef buffer, CFStringRef key) CF_RETURNS_RETAINED;
void IOSurfaceRemoveValue(IOSurfaceRef buffer, CFStringRef key);
void IOSurfaceSetValues(IOSurfaceRef buffer, CFDictionaryRef keysAndValues);
CFDictionaryRef IOSurfaceCopyAllValues(IOSurfaceRef buffer) CF_RETURNS_RETAINED;
void IOSurfaceRemoveAllValues(IOSurfaceRef buffer);
mach_port_t IOSurfaceCreateMachPort(IOSurfaceRef buffer);
IOSurfaceRef IOSurfaceLookupFromMachPort(mach_port_t port) CF_RETURNS_RETAINED;
size_t IOSurfaceGetPropertyMaximum(CFStringRef property);
size_t IOSurfaceGetPropertyAlignment(CFStringRef property);
size_t IOSurfaceAlignProperty(CFStringRef property, size_t value);
void IOSurfaceIncrementUseCount(IOSurfaceRef buffer);
void IOSurfaceDecrementUseCount(IOSurfaceRef buffer);
int32_t IOSurfaceGetUseCount(IOSurfaceRef buffer);
Boolean IOSurfaceIsInUse(IOSurfaceRef buffer);
Boolean IOSurfaceAllowsPixelSizeCasting(IOSurfaceRef buffer);
kern_return_t IOSurfaceSetPurgeable(IOSurfaceRef buffer, uint32_t newState, uint32_t *oldState);

__FERRY_END

#ifdef __OBJC__
#import <Foundation/Foundation.h>

typedef NSString *IOSurfacePropertyKey;
extern IOSurfacePropertyKey IOSurfacePropertyKeyAllocSize;
extern IOSurfacePropertyKey IOSurfacePropertyKeyWidth;
extern IOSurfacePropertyKey IOSurfacePropertyKeyHeight;
extern IOSurfacePropertyKey IOSurfacePropertyKeyBytesPerRow;
extern IOSurfacePropertyKey IOSurfacePropertyKeyBytesPerElement;
extern IOSurfacePropertyKey IOSurfacePropertyKeyElementWidth;
extern IOSurfacePropertyKey IOSurfacePropertyKeyElementHeight;
extern IOSurfacePropertyKey IOSurfacePropertyKeyOffset;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneInfo;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneWidth;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneHeight;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBytesPerRow;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneOffset;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneSize;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBase;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBytesPerElement;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneElementWidth;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPlaneElementHeight;
extern IOSurfacePropertyKey IOSurfacePropertyKeyCacheMode;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPixelFormat;
extern IOSurfacePropertyKey IOSurfacePropertyKeyPixelSizeCastingAllowed;
extern IOSurfacePropertyKey IOSurfacePropertyKeyName;

/* the same object as an IOSurfaceRef */
@interface IOSurface : NSObject <NSSecureCoding>
- (instancetype)initWithProperties:(NSDictionary<IOSurfacePropertyKey, id> *)properties;
- (kern_return_t)lockWithOptions:(IOSurfaceLockOptions)options seed:(uint32_t *)seed;
- (kern_return_t)unlockWithOptions:(IOSurfaceLockOptions)options seed:(uint32_t *)seed;
@property (readonly) NSInteger allocationSize;
@property (readonly) NSInteger width;
@property (readonly) NSInteger height;
@property (readonly) void *baseAddress;
@property (readonly) OSType pixelFormat;
@property (readonly) NSInteger bytesPerRow;
@property (readonly) NSInteger bytesPerElement;
@property (readonly) NSInteger elementWidth;
@property (readonly) NSInteger elementHeight;
@property (readonly) uint32_t seed;
@property (readonly) NSUInteger planeCount;
- (NSInteger)widthOfPlaneAtIndex:(NSUInteger)planeIndex;
- (NSInteger)heightOfPlaneAtIndex:(NSUInteger)planeIndex;
- (NSInteger)bytesPerRowOfPlaneAtIndex:(NSUInteger)planeIndex;
- (NSInteger)bytesPerElementOfPlaneAtIndex:(NSUInteger)planeIndex;
- (NSInteger)elementWidthOfPlaneAtIndex:(NSUInteger)planeIndex;
- (NSInteger)elementHeightOfPlaneAtIndex:(NSUInteger)planeIndex;
- (void *)baseAddressOfPlaneAtIndex:(NSUInteger)planeIndex;
- (void)setAttachment:(id)anObject forKey:(NSString *)key;
- (id)attachmentForKey:(NSString *)key;
- (void)removeAttachmentForKey:(NSString *)key;
- (void)setAllAttachments:(NSDictionary<NSString *, id> *)dict;
- (NSDictionary<NSString *, id> *)allAttachments;
- (void)removeAllAttachments;
@property (readonly, getter=isInUse) BOOL inUse;
- (void)incrementUseCount;
- (void)decrementUseCount;
@property (readonly) int32_t localUseCount;
@property (readonly) BOOL allowsPixelSizeCasting;
- (kern_return_t)setPurgeable:(IOSurfacePurgeabilityState)newState oldState:(IOSurfacePurgeabilityState *)oldState;
@end
#endif

#endif
