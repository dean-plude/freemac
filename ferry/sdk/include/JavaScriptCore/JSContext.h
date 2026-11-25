/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's JSContext (freemac 1.222, Ferry 0.46.0),
 * from the public documentation of JavaScriptCore's Objective-C API; not
 * Apple's header. */
#ifndef _FERRY_JSCONTEXT_H_
#define _FERRY_JSCONTEXT_H_
#import <Foundation/Foundation.h>
#include <JavaScriptCore/JSContextRef.h>

@class JSValue, JSVirtualMachine;

NS_ASSUME_NONNULL_BEGIN

@interface JSContext : NSObject
- (instancetype)init;
- (instancetype)initWithVirtualMachine:(JSVirtualMachine *)virtualMachine;
- (nullable JSValue *)evaluateScript:(NSString *)script;
- (nullable JSValue *)evaluateScript:(NSString *)script withSourceURL:(nullable NSURL *)sourceURL;
+ (nullable JSContext *)currentContext;
+ (nullable JSValue *)currentCallee;
+ (nullable JSValue *)currentThis;
+ (nullable NSArray *)currentArguments;
@property (readonly, strong) JSValue *globalObject;
@property (nullable, strong) JSValue *exception;
@property (nullable, copy) void (^exceptionHandler)(JSContext *context, JSValue *exception);
@property (readonly, strong) JSVirtualMachine *virtualMachine;
@property (nullable, copy) NSString *name;
@property (getter=isInspectable) BOOL inspectable;
@end

@interface JSContext (SubscriptSupport)
- (JSValue *)objectForKeyedSubscript:(id)key;
- (void)setObject:(nullable id)object forKeyedSubscript:(id<NSCopying>)key;
@end

@interface JSContext (JSContextRefSupport)
+ (JSContext *)contextWithJSGlobalContextRef:(JSGlobalContextRef)jsGlobalContextRef;
@property (readonly) JSGlobalContextRef JSGlobalContextRef;
@end

NS_ASSUME_NONNULL_END
#endif
