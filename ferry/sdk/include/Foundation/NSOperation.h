/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSOperation and NSOperationQueue, and the locks
 * (foundation/NSOperation.m). A queue's operations run on libdispatch's
 * worker threads, as many at once as maxConcurrentOperationCount allows;
 * the main queue's run on the main thread. Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSOPERATION_H_
#define _FERRY_FOUNDATION_NSOPERATION_H_
#include <Foundation/Foundation.h>

@class NSProgress;

typedef NS_ENUM(NSInteger, NSQualityOfService) {
    NSQualityOfServiceUserInteractive = 0x21,
    NSQualityOfServiceUserInitiated = 0x19,
    NSQualityOfServiceUtility = 0x11,
    NSQualityOfServiceBackground = 0x09,
    NSQualityOfServiceDefault = -1,
};

typedef NS_ENUM(NSInteger, NSOperationQueuePriority) {
    NSOperationQueuePriorityVeryLow = -8,
    NSOperationQueuePriorityLow = -4,
    NSOperationQueuePriorityNormal = 0,
    NSOperationQueuePriorityHigh = 4,
    NSOperationQueuePriorityVeryHigh = 8,
};

@interface NSOperation : NSObject
- (void)start;
- (void)main;
@property (readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
@property (readonly, getter=isExecuting) BOOL executing;
@property (readonly, getter=isFinished) BOOL finished;
@property (readonly, getter=isConcurrent) BOOL concurrent;
@property (readonly, getter=isAsynchronous) BOOL asynchronous;
@property (readonly, getter=isReady) BOOL ready;
- (void)addDependency:(NSOperation *)op;
- (void)removeDependency:(NSOperation *)op;
@property (readonly, copy) NSArray<NSOperation *> *dependencies;
@property NSOperationQueuePriority queuePriority;
@property (copy) void (^completionBlock)(void);
- (void)waitUntilFinished;
@property double threadPriority;
@property NSQualityOfService qualityOfService;
@property (copy) NSString *name;
@end

@interface NSBlockOperation : NSOperation
+ (instancetype)blockOperationWithBlock:(void (^)(void))block;
- (void)addExecutionBlock:(void (^)(void))block;
@property (readonly, copy) NSArray<void (^)(void)> *executionBlocks;
@end

FOUNDATION_EXPORT NSExceptionName const NSInvocationOperationVoidResultException;
FOUNDATION_EXPORT NSExceptionName const NSInvocationOperationCancelledException;

@interface NSInvocationOperation : NSOperation
- (instancetype)initWithTarget:(id)target selector:(SEL)sel object:(id)arg;
- (instancetype)initWithInvocation:(NSInvocation *)inv;
@property (readonly, retain) NSInvocation *invocation;
@property (readonly, retain) id result;
@end

#define NSOperationQueueDefaultMaxConcurrentOperationCount (-1)

@interface NSOperationQueue : NSObject
+ (NSOperationQueue *)currentQueue;
+ (NSOperationQueue *)mainQueue;
- (void)addOperation:(NSOperation *)op;
- (void)addOperations:(NSArray<NSOperation *> *)ops waitUntilFinished:(BOOL)wait;
- (void)addOperationWithBlock:(void (^)(void))block;
- (void)addBarrierBlock:(void (^)(void))barrier;
@property NSInteger maxConcurrentOperationCount;
@property (getter=isSuspended) BOOL suspended;
@property (copy) NSString *name;
@property NSQualityOfService qualityOfService;
@property (retain) id underlyingQueue; /* a dispatch queue: the operations run on it */
- (void)cancelAllOperations;
- (void)waitUntilAllOperationsAreFinished;
@property (readonly, copy) NSArray<__kindof NSOperation *> *operations;
@property (readonly) NSUInteger operationCount;
@property (readonly, retain) NSProgress *progress;
@end

/* ---- locks, on pthread mutexes and condition variables */

@protocol NSLocking
- (void)lock;
- (void)unlock;
@end

@interface NSLock : NSObject <NSLocking>
- (BOOL)tryLock;
- (BOOL)lockBeforeDate:(NSDate *)limit;
@property (copy) NSString *name;
@end

@interface NSRecursiveLock : NSObject <NSLocking>
- (BOOL)tryLock;
- (BOOL)lockBeforeDate:(NSDate *)limit;
@property (copy) NSString *name;
@end

@interface NSCondition : NSObject <NSLocking>
- (void)wait;
- (BOOL)waitUntilDate:(NSDate *)limit;
- (void)signal;
- (void)broadcast;
@property (copy) NSString *name;
@end

@interface NSConditionLock : NSObject <NSLocking>
- (instancetype)initWithCondition:(NSInteger)condition;
@property (readonly) NSInteger condition;
- (void)lockWhenCondition:(NSInteger)condition;
- (BOOL)tryLock;
- (BOOL)tryLockWhenCondition:(NSInteger)condition;
- (void)unlockWithCondition:(NSInteger)condition;
- (BOOL)lockBeforeDate:(NSDate *)limit;
- (BOOL)lockWhenCondition:(NSInteger)condition beforeDate:(NSDate *)limit;
@property (copy) NSString *name;
@end

#endif
