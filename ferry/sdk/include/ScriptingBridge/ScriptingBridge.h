/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Scripting Bridge (freemac 1.223, Ferry 0.47.0), written from
 * Apple's public documentation; not Apple's header. On a Mac it sends
 * Apple events to another app through classes that sdp generates from the
 * app's scripting dictionary. This system has no Apple events and none of
 * the Mac's scriptable apps, so an app looked up by bundle identifier or
 * URL isn't found (the calls answer nil, as a Mac's do for an app that
 * isn't installed), and one made for a running process answers nil to
 * every property and element and does nothing for every command, and
 * reports each to its delegate as an event that failed. Served from
 * AppKit's file (appkit/ScriptingBridge.m). */
#ifndef _FERRY_SCRIPTINGBRIDGE_H_
#define _FERRY_SCRIPTINGBRIDGE_H_
#import <Foundation/Foundation.h>
#include <CoreServices/CoreServices.h>

@class SBElementArray;

@interface SBObject : NSObject <NSCoding>
- (instancetype)init;
- (instancetype)initWithProperties:(NSDictionary *)properties;
- (instancetype)initWithData:(id)data;
- (id)get;
- (NSError *)lastError;
- (SBObject *)propertyWithCode:(AEKeyword)code;
- (SBObject *)propertyWithClass:(Class)cls code:(AEKeyword)code;
- (SBElementArray *)elementArrayWithCode:(DescType)code;
- (void)setTo:(id)value;
@end

@interface SBElementArray : NSMutableArray
- (id)objectWithName:(NSString *)name;
- (id)objectWithID:(id)identifier;
- (id)objectAtLocation:(id)location;
- (NSArray *)arrayByApplyingSelector:(SEL)selector;
- (NSArray *)arrayByApplyingSelector:(SEL)selector withObject:(id)argument;
- (NSArray *)get;
- (NSError *)lastError;
@end

@protocol SBApplicationDelegate <NSObject>
- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error;
@end

@interface SBApplication : SBObject <NSCoding>
+ (instancetype)applicationWithBundleIdentifier:(NSString *)ident;
+ (instancetype)applicationWithURL:(NSURL *)url;
+ (instancetype)applicationWithProcessIdentifier:(pid_t)pid;
- (instancetype)initWithBundleIdentifier:(NSString *)ident;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithProcessIdentifier:(pid_t)pid;
- (Class)classForScriptingClass:(NSString *)className;
@property (readonly, getter=isRunning) BOOL running;
- (void)activate;
@property (strong) id<SBApplicationDelegate> delegate;
@property LSLaunchFlags launchFlags;
@property AESendMode sendMode;
@property long timeout;
@end

#endif
