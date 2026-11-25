/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's JSValue (freemac 1.222, Ferry 0.46.0), from
 * the public documentation of JavaScriptCore's Objective-C API; not
 * Apple's header. */
#ifndef _FERRY_JSVALUE_H_
#define _FERRY_JSVALUE_H_
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <JavaScriptCore/JSValueRef.h>

@class JSContext;

NS_ASSUME_NONNULL_BEGIN

@interface JSValue : NSObject
@property (readonly, strong) JSContext *context;
+ (JSValue *)valueWithObject:(nullable id)value inContext:(JSContext *)context;
+ (JSValue *)valueWithBool:(BOOL)value inContext:(JSContext *)context;
+ (JSValue *)valueWithDouble:(double)value inContext:(JSContext *)context;
+ (JSValue *)valueWithInt32:(int32_t)value inContext:(JSContext *)context;
+ (JSValue *)valueWithUInt32:(uint32_t)value inContext:(JSContext *)context;
+ (JSValue *)valueWithNewObjectInContext:(JSContext *)context;
+ (JSValue *)valueWithNewArrayInContext:(JSContext *)context;
+ (JSValue *)valueWithNewRegularExpressionFromPattern:(NSString *)pattern
                                                flags:(NSString *)flags
                                            inContext:(JSContext *)context;
+ (JSValue *)valueWithNewErrorFromMessage:(NSString *)message inContext:(JSContext *)context;
+ (JSValue *)valueWithNewSymbolFromDescription:(NSString *)description inContext:(JSContext *)context;
+ (JSValue *)valueWithNullInContext:(JSContext *)context;
+ (JSValue *)valueWithUndefinedInContext:(JSContext *)context;
- (nullable id)toObject;
- (nullable id)toObjectOfClass:(Class)expectedClass;
- (BOOL)toBool;
- (double)toDouble;
- (int32_t)toInt32;
- (uint32_t)toUInt32;
- (nullable NSNumber *)toNumber;
- (nullable NSString *)toString;
- (nullable NSDate *)toDate;
- (nullable NSArray *)toArray;
- (nullable NSDictionary *)toDictionary;
@property (readonly) BOOL isUndefined;
@property (readonly) BOOL isNull;
@property (readonly) BOOL isBoolean;
@property (readonly) BOOL isNumber;
@property (readonly) BOOL isString;
@property (readonly) BOOL isObject;
@property (readonly) BOOL isArray;
@property (readonly) BOOL isDate;
@property (readonly) BOOL isSymbol;
- (BOOL)isEqualToObject:(nullable id)value;
- (BOOL)isEqualWithTypeCoercionToObject:(nullable id)value;
- (BOOL)isInstanceOf:(nullable id)value;
- (nullable JSValue *)callWithArguments:(nullable NSArray *)arguments;
- (nullable JSValue *)constructWithArguments:(nullable NSArray *)arguments;
- (nullable JSValue *)invokeMethod:(NSString *)method withArguments:(nullable NSArray *)arguments;
@end

@interface JSValue (StructSupport)
+ (JSValue *)valueWithPoint:(CGPoint)point inContext:(JSContext *)context;
+ (JSValue *)valueWithRange:(NSRange)range inContext:(JSContext *)context;
+ (JSValue *)valueWithRect:(CGRect)rect inContext:(JSContext *)context;
+ (JSValue *)valueWithSize:(CGSize)size inContext:(JSContext *)context;
- (CGPoint)toPoint;
- (NSRange)toRange;
- (CGRect)toRect;
- (CGSize)toSize;
@end

@interface JSValue (PropertyAccess)
- (nullable JSValue *)valueForProperty:(id)property;
- (void)setValue:(nullable id)value forProperty:(id)property;
- (BOOL)deleteProperty:(id)property;
- (BOOL)hasProperty:(id)property;
- (void)defineProperty:(id)property descriptor:(nullable id)descriptor;
- (nullable JSValue *)valueAtIndex:(NSUInteger)index;
- (void)setValue:(nullable id)value atIndex:(NSUInteger)index;
@end

@interface JSValue (SubscriptSupport)
- (JSValue *)objectForKeyedSubscript:(id)key;
- (JSValue *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(nullable id)object forKeyedSubscript:(id)key;
- (void)setObject:(nullable id)object atIndexedSubscript:(NSUInteger)index;
@end

@interface JSValue (JSValueRefSupport)
+ (JSValue *)valueWithJSValueRef:(JSValueRef)value inContext:(JSContext *)context;
@property (readonly) JSValueRef JSValueRef;
@end

FOUNDATION_EXPORT NSString *const JSPropertyDescriptorWritableKey;
FOUNDATION_EXPORT NSString *const JSPropertyDescriptorEnumerableKey;
FOUNDATION_EXPORT NSString *const JSPropertyDescriptorConfigurableKey;
FOUNDATION_EXPORT NSString *const JSPropertyDescriptorValueKey;
FOUNDATION_EXPORT NSString *const JSPropertyDescriptorGetKey;
FOUNDATION_EXPORT NSString *const JSPropertyDescriptorSetKey;

NS_ASSUME_NONNULL_END
#endif
