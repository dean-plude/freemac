/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSProgress (foundation/NSCache.m). Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSPROGRESS_H_
#define _FERRY_FOUNDATION_NSPROGRESS_H_
#include <Foundation/Foundation.h>

typedef NSString *NSProgressKind;
typedef NSString *NSProgressUserInfoKey;
typedef NSString *NSProgressFileOperationKind;
FOUNDATION_EXPORT NSProgressKind const NSProgressKindFile;
FOUNDATION_EXPORT NSProgressUserInfoKey const NSProgressEstimatedTimeRemainingKey;
FOUNDATION_EXPORT NSProgressUserInfoKey const NSProgressThroughputKey;
FOUNDATION_EXPORT NSProgressUserInfoKey const NSProgressFileOperationKindKey;
FOUNDATION_EXPORT NSProgressUserInfoKey const NSProgressFileURLKey;
FOUNDATION_EXPORT NSProgressUserInfoKey const NSProgressFileTotalCountKey;
FOUNDATION_EXPORT NSProgressUserInfoKey const NSProgressFileCompletedCountKey;

@interface NSProgress : NSObject
@property (class, readonly, strong) NSProgress *currentProgress;
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)unitCount;
+ (NSProgress *)discreteProgressWithTotalUnitCount:(int64_t)unitCount;
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)unitCount parent:(NSProgress *)parent
                          pendingUnitCount:(int64_t)portionOfParentTotalUnitCount;
- (instancetype FERRY_SWIFT_NONNULL)initWithParent:(NSProgress *)parentProgressOrNil userInfo:(NSDictionary *)userInfoOrNil;
- (void)becomeCurrentWithPendingUnitCount:(int64_t)unitCount;
- (void)performAsCurrentWithPendingUnitCount:(int64_t)unitCount usingBlock:(void (^)(void))work;
- (void)resignCurrent;
- (void)addChild:(NSProgress *)child withPendingUnitCount:(int64_t)inUnitCount;

@property int64_t totalUnitCount;
@property int64_t completedUnitCount;
@property (copy) NSString *localizedDescription;
@property (copy) NSString *localizedAdditionalDescription;
@property (getter=isCancellable) BOOL cancellable;
@property (getter=isPausable) BOOL pausable;
@property (readonly, getter=isCancelled) BOOL cancelled;
@property (readonly, getter=isPaused) BOOL paused;
@property (copy) void (^cancellationHandler)(void);
@property (copy) void (^pausingHandler)(void);
@property (copy) void (^resumingHandler)(void);
- (void)setUserInfoObject:(id)objectOrNil forKey:(NSProgressUserInfoKey)key;
@property (readonly, getter=isIndeterminate) BOOL indeterminate;
@property (readonly) double fractionCompleted;
@property (readonly, getter=isFinished) BOOL finished;
- (void)cancel;
- (void)pause;
- (void)resume;
@property (readonly, copy) NSDictionary<NSProgressUserInfoKey, id> *userInfo;
@property (copy) NSProgressKind kind;
@property (copy) NSNumber *estimatedTimeRemaining;
@property (copy) NSNumber *throughput;
@property (copy) NSProgressFileOperationKind fileOperationKind;
@property (copy) NSURL *fileURL;
@property (copy) NSNumber *fileTotalCount;
@property (copy) NSNumber *fileCompletedCount;
- (void)publish;
- (void)unpublish;
+ (id)addSubscriberForFileURL:(NSURL *)url withPublishingHandler:(NSProgress *(^)(NSProgress *progress))handler;
+ (void)removeSubscriber:(id)subscriber;
@property (readonly, getter=isOld) BOOL old;
@end

@protocol NSProgressReporting <NSObject>
@property (readonly) NSProgress *progress;
@end

#endif
