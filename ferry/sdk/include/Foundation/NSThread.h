/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSThread and the performs that cross threads
 * (foundation/NSThread.m), on Ferry's real threads. Written for freemac
 * from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSTHREAD_H_
#define _FERRY_FOUNDATION_NSTHREAD_H_
#include <Foundation/Foundation.h>
#include <Foundation/NSOperation.h>

@interface NSThread : NSObject
@property (class, readonly, retain) NSThread * FERRY_SWIFT_NONNULL currentThread;
@property (class, readonly, retain) NSThread * FERRY_SWIFT_NONNULL mainThread;
@property (class, readonly) BOOL isMainThread;
+ (void)detachNewThreadWithBlock:(void (^)(void))block;
+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument;
+ (BOOL)isMultiThreaded;
+ (void)sleepUntilDate:(NSDate *)date;
+ (void)sleepForTimeInterval:(NSTimeInterval)ti;
+ (void)exit;
+ (double)threadPriority;
+ (BOOL)setThreadPriority:(double)p;
@property (class, readonly, copy) NSArray<NSNumber *> *callStackReturnAddresses;
@property (class, readonly, copy) NSArray<NSString *> *callStackSymbols;

- (instancetype FERRY_SWIFT_NONNULL)init;
- (instancetype FERRY_SWIFT_NONNULL)initWithTarget:(id)target selector:(SEL)selector object:(id)argument;
- (instancetype FERRY_SWIFT_NONNULL)initWithBlock:(void (^)(void))block;
@property (readonly, retain) NSMutableDictionary *threadDictionary;
@property double threadPriority;
@property NSQualityOfService qualityOfService;
@property (copy) NSString *name;
@property NSUInteger stackSize;
@property (readonly) BOOL isMainThread;
@property (readonly, getter=isExecuting) BOOL executing;
@property (readonly, getter=isFinished) BOOL finished;
@property (readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
- (void)start;
- (void)main;
@end

FOUNDATION_EXPORT NSNotificationName const NSWillBecomeMultiThreadedNotification;
FOUNDATION_EXPORT NSNotificationName const NSDidBecomeSingleThreadedNotification;
FOUNDATION_EXPORT NSNotificationName const NSThreadWillExitNotification;

@interface NSObject (NSThreadPerformAdditions)
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(id)arg waitUntilDone:(BOOL)wait
                              modes:(NSArray<NSString *> *)modes;
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(id)arg waitUntilDone:(BOOL)wait;
- (void)performSelector:(SEL)aSelector onThread:(NSThread *)thread withObject:(id)arg waitUntilDone:(BOOL)wait
                  modes:(NSArray<NSString *> *)modes;
- (void)performSelector:(SEL)aSelector onThread:(NSThread *)thread withObject:(id)arg waitUntilDone:(BOOL)wait;
- (void)performSelectorInBackground:(SEL)aSelector withObject:(id)arg;
@end

#endif
