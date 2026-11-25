/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSUserActivity: an activity keeps what the app says about it. Ferry has no
 * Handoff, so becoming current shares it nowhere. */
#import <Foundation/Foundation.h>

NSString *const NSUserActivityTypeBrowsingWeb = @"NSUserActivityTypeBrowsingWeb";

@implementation NSUserActivity {
    NSString *_activityType;
    NSMutableDictionary *_userInfo;
}
@synthesize title = _title, requiredUserInfoKeys = _requiredUserInfoKeys, webpageURL = _webpageURL,
            referrerURL = _referrerURL, expirationDate = _expirationDate, keywords = _keywords,
            needsSave = _needsSave, supportsContinuationStreams = _supportsContinuationStreams,
            eligibleForHandoff = _eligibleForHandoff, eligibleForSearch = _eligibleForSearch,
            eligibleForPublicIndexing = _eligibleForPublicIndexing, delegate = _delegate;

- (instancetype)initWithActivityType:(NSString *)activityType
{
    if ((self = [super init])) {
        _activityType = [activityType copy];
        _userInfo = [[NSMutableDictionary alloc] init];
        _eligibleForHandoff = YES;
    }
    return self;
}
- (instancetype)init { return [self initWithActivityType:@""]; }

- (void)dealloc
{
    [_activityType release];
    [_userInfo release];
    [_title release];
    [_requiredUserInfoKeys release];
    [_webpageURL release];
    [_referrerURL release];
    [_expirationDate release];
    [_keywords release];
    [super dealloc];
}

- (NSString *)activityType { return _activityType; }
- (NSDictionary *)userInfo { return [[_userInfo copy] autorelease]; }
- (void)setUserInfo:(NSDictionary *)userInfo
{
    [_userInfo removeAllObjects];
    if (userInfo)
        [_userInfo addEntriesFromDictionary:userInfo];
}
- (void)addUserInfoEntriesFromDictionary:(NSDictionary *)other
{
    if (other)
        [_userInfo addEntriesFromDictionary:other];
}
- (void)becomeCurrent { }
- (void)resignCurrent { }
- (void)invalidate { }
@end
