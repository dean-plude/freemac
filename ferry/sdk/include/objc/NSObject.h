/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the root class NSObject, as provided by Ferry's Objective-C
 * runtime. Written for freemac from Apple's public documentation; not
 * Apple's header. Methods that need Foundation (description, which the
 * protocol declares, and NSMethodSignature) come with Ferry's Foundation. */
#ifndef _FERRY_OBJC_NSOBJECT_H_
#define _FERRY_OBJC_NSOBJECT_H_
#include <objc/objc.h>
#include <objc/NSObjCRuntime.h>

/* Never nil, as Swift's importer sees it, and nothing for Objective-C: the
 * initializers, factories and shared instances of Ferry's frameworks,
 * whose other pointers Swift sees as implicitly unwrapped (freemac 1.227). */
#ifndef FERRY_SWIFT_NONNULL
#ifdef __swift__
#define FERRY_SWIFT_NONNULL _Nonnull
#else
#define FERRY_SWIFT_NONNULL
#endif
#endif
#ifndef FERRY_SWIFT_NULLABLE
#ifdef __swift__
#define FERRY_SWIFT_NULLABLE _Nullable
#else
#define FERRY_SWIFT_NULLABLE
#endif
#endif

#ifdef __OBJC__
/* Which pointers may be nil, as a Mac's header says, so that Swift sees
 * NSObject() and -description as never nil (freemac 1.227). */
#pragma clang assume_nonnull begin
@class Protocol;
@class NSString;
typedef struct _NSZone NSZone;

@protocol NSObject
- (BOOL)isEqual:(nullable id)object;
@property (readonly) NSUInteger hash;
@property (readonly, nullable) Class superclass;
- (Class)class;
- (instancetype)self;
- (nullable id)performSelector:(SEL)aSelector;
- (nullable id)performSelector:(SEL)aSelector withObject:(nullable id)object;
- (nullable id)performSelector:(SEL)aSelector withObject:(nullable id)object1 withObject:(nullable id)object2;
- (BOOL)isProxy;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)isMemberOfClass:(Class)aClass;
- (BOOL)conformsToProtocol:(Protocol *)aProtocol;
- (BOOL)respondsToSelector:(SEL)aSelector;
- (instancetype)retain OBJC_ARC_UNAVAILABLE;
- (oneway void)release OBJC_ARC_UNAVAILABLE;
- (instancetype)autorelease OBJC_ARC_UNAVAILABLE;
- (NSUInteger)retainCount OBJC_ARC_UNAVAILABLE;
- (NSZone *)zone OBJC_ARC_UNAVAILABLE;
/* as on a Mac, so an object known only by the protocol (id<NSObject>)
 * can be described */
@property (readonly, copy) NSString *description;
@optional
@property (readonly, copy) NSString *debugDescription;
@end

OBJC_ROOT_CLASS
@interface NSObject <NSObject> {
    Class isa;
}
+ (void)load;
+ (void)initialize;
- (instancetype)init;
+ (instancetype)new;
+ (instancetype)allocWithZone:(nullable NSZone *)zone;
+ (instancetype)alloc;
- (void)dealloc;
- (id)copy;
- (id)mutableCopy;
+ (id)copyWithZone:(nullable NSZone *)zone OBJC_ARC_UNAVAILABLE;
+ (id)mutableCopyWithZone:(nullable NSZone *)zone OBJC_ARC_UNAVAILABLE;
+ (BOOL)instancesRespondToSelector:(SEL)aSelector;
+ (BOOL)conformsToProtocol:(Protocol *)protocol;
- (IMP)methodForSelector:(SEL)aSelector;
+ (IMP)instanceMethodForSelector:(SEL)aSelector;
- (void)doesNotRecognizeSelector:(SEL)aSelector;
- (nullable id)forwardingTargetForSelector:(SEL)aSelector;
+ (BOOL)resolveClassMethod:(SEL)sel;
+ (BOOL)resolveInstanceMethod:(SEL)sel;
+ (nullable Class)superclass;
+ (Class)class;
+ (BOOL)isSubclassOfClass:(Class)aClass;
+ (NSUInteger)hash;
@end
#pragma clang assume_nonnull end
#endif
#endif
