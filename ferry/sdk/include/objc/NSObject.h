/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the root class NSObject, as provided by Ferry's Objective-C
 * runtime. Written for freemac from Apple's public documentation; not
 * Apple's header. Methods that need Foundation (description, NSString,
 * NSMethodSignature) come with Ferry's Foundation. */
#ifndef _FERRY_OBJC_NSOBJECT_H_
#define _FERRY_OBJC_NSOBJECT_H_
#include <objc/objc.h>
#include <objc/NSObjCRuntime.h>

#ifdef __OBJC__
@class Protocol;
typedef struct _NSZone NSZone;

@protocol NSObject
- (BOOL)isEqual:(id)object;
@property (readonly) NSUInteger hash;
@property (readonly) Class superclass;
- (Class)class;
- (instancetype)self;
- (id)performSelector:(SEL)aSelector;
- (id)performSelector:(SEL)aSelector withObject:(id)object;
- (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2;
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
@end

OBJC_ROOT_CLASS
@interface NSObject <NSObject> {
    Class isa;
}
+ (void)load;
+ (void)initialize;
- (instancetype)init;
+ (instancetype)new;
+ (instancetype)allocWithZone:(NSZone *)zone;
+ (instancetype)alloc;
- (void)dealloc;
- (id)copy;
- (id)mutableCopy;
+ (id)copyWithZone:(NSZone *)zone OBJC_ARC_UNAVAILABLE;
+ (id)mutableCopyWithZone:(NSZone *)zone OBJC_ARC_UNAVAILABLE;
+ (BOOL)instancesRespondToSelector:(SEL)aSelector;
+ (BOOL)conformsToProtocol:(Protocol *)protocol;
- (IMP)methodForSelector:(SEL)aSelector;
+ (IMP)instanceMethodForSelector:(SEL)aSelector;
- (void)doesNotRecognizeSelector:(SEL)aSelector;
- (id)forwardingTargetForSelector:(SEL)aSelector;
+ (BOOL)resolveClassMethod:(SEL)sel;
+ (BOOL)resolveInstanceMethod:(SEL)sel;
+ (Class)superclass;
+ (Class)class;
+ (BOOL)isSubclassOfClass:(Class)aClass;
+ (NSUInteger)hash;
@end
#endif
#endif
