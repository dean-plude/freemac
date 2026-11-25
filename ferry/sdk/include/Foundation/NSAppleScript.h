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

/* Cocoa scripting's commands (freemac 1.221, Ferry 0.45.0). Ferry receives
 * no Apple events, so it never makes a command for an app: the class is
 * here for the apps that handle commands and for their own subclasses. A
 * command made in the program runs performDefaultImplementation, which
 * answers nil. */
@class NSScriptCommandDescription;
enum {
    NSNoScriptError = 0, NSReceiverEvaluationScriptError = 1, NSKeySpecifierEvaluationScriptError = 2,
    NSArgumentEvaluationScriptError = 3, NSReceiversCantHandleCommandScriptError = 4,
    NSRequiredArgumentsMissingScriptError = 5, NSArgumentsWrongScriptError = 6, NSUnknownKeyScriptError = 7,
    NSInternalScriptError = 8, NSOperationNotSupportedForKeyScriptError = 9, NSCannotCreateScriptCommandError = 10,
};
@interface NSScriptCommand : NSObject <NSCoding>
+ (NSScriptCommand *)currentCommand;
- (instancetype)initWithCommandDescription:(NSScriptCommandDescription *)commandDef;
@property (readonly, retain) NSScriptCommandDescription *commandDescription;
@property (retain) id directParameter;
@property (copy) NSDictionary<NSString *, id> *arguments;
@property (readonly, copy) NSDictionary<NSString *, id> *evaluatedArguments;
@property (readonly) id evaluatedReceivers;
@property (readonly, getter=isWellFormed) BOOL wellFormed;
@property NSInteger scriptErrorNumber;
@property (copy) NSString *scriptErrorString;
@property (retain) id scriptErrorExpectedTypeDescriptor;
@property (retain) NSAppleEventDescriptor *scriptErrorOffendingObjectDescriptor;
@property (readonly, retain) NSAppleEventDescriptor *appleEvent;
- (id)performDefaultImplementation;
- (id)executeCommand;
- (void)suspendExecution;
- (void)resumeExecutionWithResult:(id)result;
@end

#endif
