/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's JSManagedValue (freemac 1.222, Ferry
 * 0.46.0), from the public documentation of JavaScriptCore's Objective-C
 * API; not Apple's header. */
#ifndef _FERRY_JSMANAGEDVALUE_H_
#define _FERRY_JSMANAGEDVALUE_H_
#import <Foundation/Foundation.h>

@class JSValue;

NS_ASSUME_NONNULL_BEGIN
@interface JSManagedValue : NSObject
+ (JSManagedValue *)managedValueWithValue:(JSValue *)value;
+ (JSManagedValue *)managedValueWithValue:(JSValue *)value andOwner:(nullable id)owner;
- (instancetype)initWithValue:(JSValue *)value;
@property (nullable, readonly, strong) JSValue *value;
@end
NS_ASSUME_NONNULL_END
#endif
