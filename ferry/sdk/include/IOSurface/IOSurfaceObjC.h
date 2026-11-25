/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the IOSurface class, toll-free bridged with IOSurfaceRef as on a
 * Mac; written from Apple's public documentation, not Apple's header. */
#ifndef _FERRY_IOSURFACE_IOSURFACEOBJC_H_
#define _FERRY_IOSURFACE_IOSURFACEOBJC_H_
#include <IOSurface/IOSurfaceRef.h>
#ifdef __OBJC__
#import <Foundation/Foundation.h>
typedef NSString *IOSurfacePropertyKey;
extern IOSurfacePropertyKey const IOSurfacePropertyKeyAllocSize;
extern IOSurfacePropertyKey const IOSurfacePropertyKeyWidth;
extern IOSurfacePropertyKey const IOSurfacePropertyKeyHeight;
extern IOSurfacePropertyKey const IOSurfacePropertyKeyBytesPerRow;
extern IOSurfacePropertyKey const IOSurfacePropertyKeyBytesPerElement;
extern IOSurfacePropertyKey const IOSurfacePropertyKeyPixelFormat;
extern IOSurfacePropertyKey const IOSurfacePropertyKeyName;

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
@property (readonly, getter=isInUse) BOOL inUse;
@property (readonly) int32_t localUseCount;
- (void)incrementUseCount;
- (void)decrementUseCount;
- (id)attachmentForKey:(NSString *)key;
- (void)setAttachment:(id)anObject forKey:(NSString *)key;
- (void)removeAttachmentForKey:(NSString *)key;
@end
#endif
#endif
