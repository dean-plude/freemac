/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSAppleScript (foundation/NSAppleScript.m), which keeps its
 * source but runs nothing, imported by Foundation.h. Written for freemac
 * from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSAPPLESCRIPT_H_
#define _FERRY_FOUNDATION_NSAPPLESCRIPT_H_
#include <Foundation/Foundation.h>

@class NSAppleEventDescriptor;

FOUNDATION_EXPORT NSString *const NSAppleScriptErrorMessage;
FOUNDATION_EXPORT NSString *const NSAppleScriptErrorNumber;
FOUNDATION_EXPORT NSString *const NSAppleScriptErrorAppName;
FOUNDATION_EXPORT NSString *const NSAppleScriptErrorBriefMessage;
FOUNDATION_EXPORT NSString *const NSAppleScriptErrorRange;

@interface NSAppleScript : NSObject <NSCopying>
- (instancetype)initWithSource:(NSString *)source;
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSDictionary<NSString *, id> **)errorInfo;
@property (readonly, copy) NSString *source;
@property (readonly, getter=isCompiled) BOOL compiled;
- (BOOL)compileAndReturnError:(NSDictionary<NSString *, id> **)errorInfo;
- (NSAppleEventDescriptor *)executeAndReturnError:(NSDictionary<NSString *, id> **)errorInfo;
- (NSAppleEventDescriptor *)executeAppleEvent:(NSAppleEventDescriptor *)event
                                        error:(NSDictionary<NSString *, id> **)errorInfo;
@end

#endif
