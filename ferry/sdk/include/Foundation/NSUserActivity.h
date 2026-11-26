/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSUserActivity, written from Apple's public Foundation
 * documentation; not Apple's header. An activity keeps what an app says
 * about it; Ferry has no Handoff, so becomeCurrent shares it with no other
 * device and no app is ever handed one to continue. */
#ifndef _FERRY_FOUNDATION_NSUSERACTIVITY_H_
#define _FERRY_FOUNDATION_NSUSERACTIVITY_H_
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const NSUserActivityTypeBrowsingWeb;

@protocol NSUserActivityDelegate;

@interface NSUserActivity : NSObject
- (instancetype)initWithActivityType:(NSString *)activityType;
@property (readonly, copy) NSString *activityType;
@property (copy) NSString *title;
@property (copy) NSDictionary *userInfo;
@property (copy) NSSet<NSString *> *requiredUserInfoKeys;
@property (copy) NSURL *webpageURL;
@property (copy) NSURL *referrerURL;
@property (copy) NSDate *expirationDate;
@property (copy) NSSet<NSString *> *keywords;
@property BOOL needsSave;
@property BOOL supportsContinuationStreams;
@property (getter=isEligibleForHandoff) BOOL eligibleForHandoff;
@property (getter=isEligibleForSearch) BOOL eligibleForSearch;
@property (getter=isEligibleForPublicIndexing) BOOL eligibleForPublicIndexing;
@property (assign) id<NSUserActivityDelegate> delegate;
- (void)addUserInfoEntriesFromDictionary:(NSDictionary *)otherDictionary;
- (void)becomeCurrent;
- (void)resignCurrent;
- (void)invalidate;
@end

@protocol NSUserActivityDelegate <NSObject>
@optional
- (void)userActivityWillSave:(NSUserActivity *)userActivity;
- (void)userActivityWasContinued:(NSUserActivity *)userActivity;
@end

#endif
