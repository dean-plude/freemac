/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: UserNotifications.framework (UNUserNotificationCenter and
 * the classes it takes and gives), served from AppKit's file under its own
 * framework name. Written from Apple's public documentation.
 *
 * Authorization is always granted: freemac doesn't ask the user whether an
 * app may post notifications, so the settings say authorized for alerts,
 * sounds and badges, even before the app asks. A request with no trigger
 * is delivered on the next turn of the main run loop; a time interval or
 * calendar trigger is a timer on the main run loop, so it fires while the
 * program runs (a Mac's system delivers it even after the app has quit).
 * When the app is active, the delegate's
 * userNotificationCenter:willPresentNotification:withCompletionHandler:
 * decides how a notification is presented, as on a Mac; without it, or when
 * the app isn't active, it is shown with a banner, a sound and its badge.
 *
 * A delivered notification is shown by the desktop's notification server
 * (ANotifyServer.m): its title (or the app's name), its subtitle and body,
 * and its category's actions as buttons. The first text input action of a
 * category becomes an inline reply where the server takes one, and a plain
 * button (whose response has empty text) where it doesn't. A click on the
 * notification, a button, a reply and, for a category with
 * UNNotificationCategoryOptionCustomDismissAction, a dismissal come to the
 * delegate's userNotificationCenter:didReceiveNotificationResponse:
 * withCompletionHandler: on the main thread. The content's badge goes to the
 * app's Dock tile (NSDockTile.m). Attachments are kept but not shown.
 * Completion handlers are called on a global dispatch queue, as a Mac may.
 */
#import "ANotify.h"

NSErrorDomain const UNErrorDomain = @"UNErrorDomain";
NSString *const UNNotificationDefaultActionIdentifier = @"com.apple.UNNotificationDefaultActionIdentifier";
NSString *const UNNotificationDismissActionIdentifier = @"com.apple.UNNotificationDismissActionIdentifier";

#define SET_COPY(ivar, value)                                                                                    \
    do {                                                                                                         \
        id v_ = [(value) copy];                                                                                  \
        [ivar release];                                                                                          \
        ivar = v_;                                                                                               \
    } while (0)

/* ---- sounds and attachments ------------------------------------------------------------- */

@implementation UNNotificationSound {
@public
    NSString *_name;                    /* nil for the default sound */
    BOOL _critical;
}
+ (instancetype)_sound:(NSString *)name critical:(BOOL)critical
{
    UNNotificationSound *s = [[[self alloc] init] autorelease];
    s->_name = [name copy];
    s->_critical = critical;
    return s;
}
+ (UNNotificationSound *)defaultSound { return [self _sound:nil critical:NO]; }
+ (UNNotificationSound *)defaultCriticalSound { return [self _sound:nil critical:YES]; }
+ (UNNotificationSound *)defaultCriticalSoundWithAudioVolume:(float)volume { return [self _sound:nil critical:YES]; }
+ (instancetype)soundNamed:(UNNotificationSoundName)name { return [self _sound:name critical:NO]; }
+ (instancetype)criticalSoundNamed:(UNNotificationSoundName)name { return [self _sound:name critical:YES]; }
+ (instancetype)criticalSoundNamed:(UNNotificationSoundName)name withAudioVolume:(float)volume
{
    return [self _sound:name critical:YES];
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<UNNotificationSound %@>", _name ?: @"default"];
}
@end

@implementation UNNotificationAttachment {
    NSString *_identifier, *_type;
    NSURL *_URL;
}
+ (instancetype)attachmentWithIdentifier:(NSString *)identifier URL:(NSURL *)URL options:(NSDictionary *)options
                                   error:(NSError **)error
{
    if (![URL isFileURL] || ![[NSFileManager defaultManager] fileExistsAtPath:[URL path]]) {
        if (error)
            *error = [NSError errorWithDomain:UNErrorDomain code:UNErrorCodeAttachmentInvalidURL userInfo:nil];
        return nil;
    }
    UNNotificationAttachment *a = [[[self alloc] init] autorelease];
    a->_identifier = [identifier length] ? [identifier copy] : [[[NSProcessInfo processInfo] globallyUniqueString] copy];
    a->_URL = [URL copy];
    a->_type = [@"public.data" copy];
    return a;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)dealloc
{
    [_identifier release];
    [_URL release];
    [_type release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)identifier { return _identifier; }
- (NSURL *)URL { return _URL; }
- (NSString *)type { return _type; }
@end

/* ---- content ---------------------------------------------------------------------------- */

/* The setters are made here and used by UNMutableNotificationContent. */
@interface UNNotificationContent ()
@property (copy) NSString *title, *subtitle, *body, *launchImageName, *categoryIdentifier, *threadIdentifier;
@property (copy) NSString *targetContentIdentifier, *summaryArgument, *filterCriteria;
@property (copy) NSNumber *badge;
@property (copy) UNNotificationSound *sound;
@property (copy) NSDictionary *userInfo;
@property (copy) NSArray *attachments;
@property NSUInteger summaryArgumentCount;
@property UNNotificationInterruptionLevel interruptionLevel;
@property double relevanceScore;
@end

@implementation UNNotificationContent
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init
{
    if ((self = [super init])) {
        _interruptionLevel = UNNotificationInterruptionLevelActive;
        _title = _subtitle = _body = _categoryIdentifier = _threadIdentifier = @"";
        _userInfo = [@{} retain];
        _attachments = [@[] retain];
    }
    return self;
}
- (void)dealloc
{
    [_title release];
    [_subtitle release];
    [_body release];
    [_launchImageName release];
    [_categoryIdentifier release];
    [_threadIdentifier release];
    [_targetContentIdentifier release];
    [_summaryArgument release];
    [_filterCriteria release];
    [_badge release];
    [_sound release];
    [_userInfo release];
    [_attachments release];
    [super dealloc];
}
- (id)_copyAs:(Class)cls
{
    UNNotificationContent *c = [[cls alloc] init];
    c.title = _title;
    c.subtitle = _subtitle;
    c.body = _body;
    c.launchImageName = _launchImageName;
    c.categoryIdentifier = _categoryIdentifier;
    c.threadIdentifier = _threadIdentifier;
    c.targetContentIdentifier = _targetContentIdentifier;
    c.summaryArgument = _summaryArgument;
    c.filterCriteria = _filterCriteria;
    c.badge = _badge;
    c.sound = _sound;
    c.userInfo = _userInfo;
    c.attachments = _attachments;
    c.summaryArgumentCount = _summaryArgumentCount;
    c.interruptionLevel = _interruptionLevel;
    c.relevanceScore = _relevanceScore;
    return c;
}
- (id)copyWithZone:(NSZone *)zone
{
    if ([self class] == [UNNotificationContent class])
        return [self retain];
    return [self _copyAs:[UNNotificationContent class]];
}
- (id)mutableCopyWithZone:(NSZone *)zone { return [self _copyAs:[UNMutableNotificationContent class]]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<UNNotificationContent: title \"%@\", body \"%@\">", [self title],
                                      [self body]];
}
@end

@implementation UNMutableNotificationContent
@dynamic title, subtitle, body, badge, sound, launchImageName, userInfo, attachments, categoryIdentifier;
@dynamic threadIdentifier, targetContentIdentifier, summaryArgument, summaryArgumentCount, interruptionLevel;
@dynamic relevanceScore, filterCriteria;
@end

/* ---- triggers ----------------------------------------------------------------------------- */

@implementation UNNotificationTrigger {
@public
    BOOL _repeats;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (BOOL)repeats { return _repeats; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
@end

@implementation UNPushNotificationTrigger
@end

@implementation UNTimeIntervalNotificationTrigger {
@public
    NSTimeInterval _interval;
    NSDate *_anchor;                    /* when the center took it */
}
+ (instancetype)triggerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats
{
    if (!(interval > 0))
        [NSException raise:NSInternalInconsistencyException format:@"time interval must be greater than 0"];
    if (repeats && interval < 60)
        [NSException raise:NSInternalInconsistencyException format:@"time interval must be at least 60 if repeating"];
    UNTimeIntervalNotificationTrigger *t = [[[self alloc] init] autorelease];
    t->_interval = interval;
    t->_repeats = repeats;
    return t;
}
- (void)dealloc
{
    [_anchor release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    UNTimeIntervalNotificationTrigger *t = [[UNTimeIntervalNotificationTrigger alloc] init];
    t->_interval = _interval;
    t->_repeats = _repeats;
    t->_anchor = [_anchor retain];
    return t;
}
- (NSTimeInterval)timeInterval { return _interval; }
- (void)_setAnchor:(NSDate *)date { SET_COPY(_anchor, date); }
- (NSDate *)nextTriggerDate
{
    NSDate *now = [NSDate date];
    NSDate *next = [(_anchor ?: now) dateByAddingTimeInterval:_interval];
    if (_repeats)
        while ([next timeIntervalSinceDate:now] <= 0)
            next = [next dateByAddingTimeInterval:_interval];
    return next;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<UNTimeIntervalNotificationTrigger: timeInterval %g, repeats %s>", _interval,
                                      _repeats ? "YES" : "NO"];
}
@end

@implementation UNCalendarNotificationTrigger {
    NSDateComponents *_components;
}
+ (instancetype)triggerWithDateMatchingComponents:(NSDateComponents *)components repeats:(BOOL)repeats
{
    UNCalendarNotificationTrigger *t = [[[self alloc] init] autorelease];
    t->_components = [components copy];
    t->_repeats = repeats;
    return t;
}
- (void)dealloc
{
    [_components release];
    [super dealloc];
}
- (NSDateComponents *)dateComponents { return [[_components copy] autorelease]; }
- (NSDate *)nextTriggerDate
{
    NSCalendar *cal = [[([_components calendar] ?: [NSCalendar currentCalendar]) copy] autorelease];
    if ([_components timeZone])
        [cal setTimeZone:[_components timeZone]];
    return [cal nextDateAfterDate:[NSDate date] matchingComponents:_components options:NSCalendarMatchNextTime];
}
@end

/* ---- requests and notifications ------------------------------------------------------------- */

@implementation UNNotificationRequest {
    NSString *_identifier;
    UNNotificationContent *_content;
    UNNotificationTrigger *_trigger;
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)requestWithIdentifier:(NSString *)identifier content:(UNNotificationContent *)content
                              trigger:(UNNotificationTrigger *)trigger
{
    if (!identifier || !content)
        [NSException raise:NSInvalidArgumentException format:@"a notification request needs an identifier and content"];
    UNNotificationRequest *r = [[[self alloc] init] autorelease];
    r->_identifier = [identifier copy];
    r->_content = [content copy];
    r->_trigger = [trigger copy];
    return r;
}
- (void)dealloc
{
    [_identifier release];
    [_content release];
    [_trigger release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)identifier { return _identifier; }
- (UNNotificationContent *)content { return _content; }
- (UNNotificationTrigger *)trigger { return _trigger; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<UNNotificationRequest: identifier %@>", _identifier];
}
@end

@implementation UNNotification {
    NSDate *_date;
    UNNotificationRequest *_request;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)_initWithRequest:(UNNotificationRequest *)request date:(NSDate *)date
{
    if ((self = [super init])) {
        _request = [request retain];
        _date = [date copy];
    }
    return self;
}
- (void)dealloc
{
    [_date release];
    [_request release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSDate *)date { return _date; }
- (UNNotificationRequest *)request { return _request; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<UNNotification: %@>", [_request identifier]];
}
@end

/* ---- actions and categories ------------------------------------------------------------------ */

@implementation UNNotificationAction {
@public
    NSString *_identifier, *_title;
    UNNotificationActionOptions _options;
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
                             options:(UNNotificationActionOptions)options
{
    UNNotificationAction *a = [[[self alloc] init] autorelease];
    a->_identifier = [identifier copy];
    a->_title = [title copy];
    a->_options = options;
    return a;
}
- (void)dealloc
{
    [_identifier release];
    [_title release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)identifier { return _identifier; }
- (NSString *)title { return _title; }
- (UNNotificationActionOptions)options { return _options; }
@end

@implementation UNTextInputNotificationAction {
    NSString *_button, *_placeholder;
}
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
                             options:(UNNotificationActionOptions)options
                textInputButtonTitle:(NSString *)button
                textInputPlaceholder:(NSString *)placeholder
{
    UNTextInputNotificationAction *a = [self actionWithIdentifier:identifier title:title options:options];
    a->_button = [button copy];
    a->_placeholder = [placeholder copy];
    return a;
}
- (void)dealloc
{
    [_button release];
    [_placeholder release];
    [super dealloc];
}
- (NSString *)textInputButtonTitle { return _button; }
- (NSString *)textInputPlaceholder { return _placeholder; }
@end

@implementation UNNotificationCategory {
    NSString *_identifier, *_placeholder, *_summaryFormat;
    NSArray *_actions, *_intents;
    UNNotificationCategoryOptions _options;
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)categoryWithIdentifier:(NSString *)identifier actions:(NSArray *)actions
                     intentIdentifiers:(NSArray *)intents
         hiddenPreviewsBodyPlaceholder:(NSString *)placeholder
                 categorySummaryFormat:(NSString *)format
                               options:(UNNotificationCategoryOptions)options
{
    UNNotificationCategory *c = [[[self alloc] init] autorelease];
    c->_identifier = [identifier copy];
    c->_actions = [actions ?: @[] copy];
    c->_intents = [intents ?: @[] copy];
    c->_placeholder = [placeholder copy];
    c->_summaryFormat = [format copy];
    c->_options = options;
    return c;
}
+ (instancetype)categoryWithIdentifier:(NSString *)identifier actions:(NSArray *)actions
                     intentIdentifiers:(NSArray *)intents
         hiddenPreviewsBodyPlaceholder:(NSString *)placeholder
                               options:(UNNotificationCategoryOptions)options
{
    return [self categoryWithIdentifier:identifier actions:actions intentIdentifiers:intents
          hiddenPreviewsBodyPlaceholder:placeholder categorySummaryFormat:nil options:options];
}
+ (instancetype)categoryWithIdentifier:(NSString *)identifier actions:(NSArray *)actions
                     intentIdentifiers:(NSArray *)intents
                               options:(UNNotificationCategoryOptions)options
{
    return [self categoryWithIdentifier:identifier actions:actions intentIdentifiers:intents
          hiddenPreviewsBodyPlaceholder:nil categorySummaryFormat:nil options:options];
}
- (void)dealloc
{
    [_identifier release];
    [_actions release];
    [_intents release];
    [_placeholder release];
    [_summaryFormat release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[UNNotificationCategory class]] &&
                             [[other identifier] isEqualToString:_identifier]);
}
- (NSUInteger)hash { return [_identifier hash]; }
- (NSString *)identifier { return _identifier; }
- (NSArray *)actions { return _actions; }
- (NSArray *)intentIdentifiers { return _intents; }
- (UNNotificationCategoryOptions)options { return _options; }
- (NSString *)hiddenPreviewsBodyPlaceholder { return _placeholder; }
- (NSString *)categorySummaryFormat { return _summaryFormat; }
@end

/* ---- responses and settings ---------------------------------------------------------------- */

@implementation UNNotificationResponse {
@public
    UNNotification *_notification;
    NSString *_action;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)dealloc
{
    [_notification release];
    [_action release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (UNNotification *)notification { return _notification; }
- (NSString *)actionIdentifier { return _action; }
@end

@implementation UNTextInputNotificationResponse {
@public
    NSString *_text;
}
- (void)dealloc
{
    [_text release];
    [super dealloc];
}
- (NSString *)userText { return _text; }
@end

@implementation UNNotificationSettings
+ (BOOL)supportsSecureCoding { return YES; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (UNAuthorizationStatus)authorizationStatus { return UNAuthorizationStatusAuthorized; }
- (UNNotificationSetting)soundSetting { return UNNotificationSettingEnabled; }
- (UNNotificationSetting)badgeSetting { return UNNotificationSettingEnabled; }
- (UNNotificationSetting)alertSetting { return UNNotificationSettingEnabled; }
- (UNNotificationSetting)notificationCenterSetting { return UNNotificationSettingEnabled; }
- (UNNotificationSetting)lockScreenSetting { return UNNotificationSettingNotSupported; }
- (UNNotificationSetting)carPlaySetting { return UNNotificationSettingNotSupported; }
- (UNNotificationSetting)announcementSetting { return UNNotificationSettingNotSupported; }
- (UNNotificationSetting)criticalAlertSetting { return UNNotificationSettingNotSupported; }
- (UNNotificationSetting)timeSensitiveSetting { return UNNotificationSettingNotSupported; }
- (UNNotificationSetting)scheduledDeliverySetting { return UNNotificationSettingNotSupported; }
- (UNNotificationSetting)directMessagesSetting { return UNNotificationSettingNotSupported; }
- (UNAlertStyle)alertStyle { return UNAlertStyleBanner; }
- (UNShowPreviewsSetting)showPreviewsSetting { return UNShowPreviewsSettingAlways; }
- (BOOL)providesAppNotificationSettings { return NO; }
@end

/* ---- the center ------------------------------------------------------------------------------ */

@interface UNUserNotificationCenter (FerryPrivate)
- (void)_respond:(UNNotification *)n action:(NSString *)action text:(NSString *)text foreground:(BOOL)foreground;
- (void)_gone:(UNNotification *)n;
@end

/* A notification on the server's screen: what its buttons mean, and
 * whether the user has answered it yet. */
@interface FUNShown : NSObject <ANotifyOwner> {
@public
    UNNotification *notification;
    UNNotificationCategory *category;
    NSString *replyAction;              /* the text input action shown as an inline reply */
    unsigned handle;
    BOOL answered;
}
@end

@implementation FUNShown
- (void)dealloc
{
    [notification release];
    [category release];
    [replyAction release];
    [super dealloc];
}

- (UNNotificationAction *)_action:(NSString *)ident
{
    for (UNNotificationAction *a in [category actions])
        if ([[a identifier] isEqualToString:ident])
            return a;
    return nil;
}

- (void)_notifyInvoked:(NSString *)key
{
    if (answered)
        return;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    if ([key isEqualToString:@"default"]) {
        answered = YES;
        [center _respond:notification action:UNNotificationDefaultActionIdentifier text:nil foreground:YES];
    } else if ([key hasPrefix:@"action:"]) {
        UNNotificationAction *a = [self _action:[key substringFromIndex:7]];
        if (!a)
            return;
        answered = YES;
        BOOL text = [a isKindOfClass:[UNTextInputNotificationAction class]];
        [center _respond:notification action:[a identifier] text:text ? @"" : nil
              foreground:([a options] & UNNotificationActionOptionForeground) != 0];
    }
}

- (void)_notifyReplied:(NSString *)text
{
    UNNotificationAction *a = replyAction ? [self _action:replyAction] : nil;
    if (answered || !a)
        return;
    answered = YES;
    [[UNUserNotificationCenter currentNotificationCenter]
        _respond:notification action:[a identifier] text:text ?: @""
      foreground:([a options] & UNNotificationActionOptionForeground) != 0];
}

/* Dismissed: gone from the delivered list, and a response for a category
 * that asks for one. One whose time on screen ran out stays delivered, as
 * in a Mac's Notification Center. */
- (void)_notifyClosed:(unsigned)reason
{
    handle = 0;
    if (answered || reason != 2)
        return;
    answered = YES;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    if ([category options] & UNNotificationCategoryOptionCustomDismissAction)
        [center _respond:notification action:UNNotificationDismissActionIdentifier text:nil foreground:NO];
    else
        [center _gone:notification];
}
@end

static void later(void (^block)(void))
{
    dispatch_async(dispatch_get_global_queue(0, 0), block);
}

/* Runs the call on the main thread: YES when it was sent there. */
#define ON_MAIN(...)                                                                                             \
    if (!pthread_main_np()) {                                                                                    \
        dispatch_async(dispatch_get_main_queue(), ^{                                                             \
            __VA_ARGS__;                                                                                         \
        });                                                                                                      \
        return;                                                                                                  \
    }

@implementation UNUserNotificationCenter {
    id _delegate;
    NSSet *_categories;
    NSMutableArray *_pending;           /* UNNotificationRequest, in the order added */
    NSMutableDictionary *_timers;       /* identifier -> NSTimer */
    NSMutableDictionary *_addHandlers;  /* identifier -> add handler of a request with no trigger */
    NSMutableArray *_delivered;         /* UNNotification */
    NSMutableDictionary *_shown;        /* identifier -> FUNShown */
}

+ (UNUserNotificationCenter *)currentNotificationCenter
{
    static UNUserNotificationCenter *center;
    @synchronized([UNUserNotificationCenter class]) {
        if (!center)
            center = [[UNUserNotificationCenter alloc] init];
    }
    return center;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _categories = [[NSSet alloc] init];
        _pending = [[NSMutableArray alloc] init];
        _timers = [[NSMutableDictionary alloc] init];
        _addHandlers = [[NSMutableDictionary alloc] init];
        _delivered = [[NSMutableArray alloc] init];
        _shown = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (BOOL)supportsContentExtensions { return NO; }

/* ---- authorization, settings and categories ---- */

- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options
                      completionHandler:(void (^)(BOOL granted, NSError *error))handler
{
    if (handler)
        later(^{
            handler(YES, nil);
        });
}

- (void)getNotificationSettingsWithCompletionHandler:(void (^)(UNNotificationSettings *settings))handler
{
    if (!handler)
        return;
    later(^{
        handler([[[UNNotificationSettings alloc] init] autorelease]);
    });
}

- (void)setNotificationCategories:(NSSet *)categories
{
    @synchronized(self) {
        SET_COPY(_categories, categories ?: [NSSet set]);
    }
}

- (void)getNotificationCategoriesWithCompletionHandler:(void (^)(NSSet<UNNotificationCategory *> *categories))handler
{
    if (!handler)
        return;
    NSSet *now;
    @synchronized(self) {
        now = [[_categories retain] autorelease];
    }
    later(^{
        handler(now);
    });
}

- (UNNotificationCategory *)_category:(NSString *)ident
{
    if (![ident length])
        return nil;
    @synchronized(self) {
        for (UNNotificationCategory *c in _categories)
            if ([[c identifier] isEqualToString:ident])
                return [[c retain] autorelease];
    }
    return nil;
}

/* ---- requests ---- */

- (void)_cancelPending:(NSString *)ident
{
    [[_timers objectForKey:ident] invalidate];
    [_timers removeObjectForKey:ident];
    [self _added:ident];        /* replaced or removed before it was delivered */
    for (UNNotificationRequest *r in [[_pending copy] autorelease])
        if ([[r identifier] isEqualToString:ident]) {
            @synchronized(self) {
                [_pending removeObjectIdenticalTo:r];
            }
        }
}

- (void)_arm:(UNNotificationRequest *)request at:(NSDate *)date
{
    NSTimeInterval wait = [date timeIntervalSinceNow];
    NSTimer *t = [NSTimer timerWithTimeInterval:wait > 0 ? wait : 0 target:self selector:@selector(_due:)
                                       userInfo:request repeats:NO];
    [_timers setObject:t forKey:[request identifier]];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
}

- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void (^)(NSError *error))handler
{
    ON_MAIN([self addNotificationRequest:request withCompletionHandler:handler])
    if (!request)
        return;
    NSString *ident = [request identifier];
    UNNotificationTrigger *trigger = [request trigger];
    NSDate *when;
    if (!trigger)
        when = [NSDate date];
    else if ([trigger isKindOfClass:[UNTimeIntervalNotificationTrigger class]]) {
        [(UNTimeIntervalNotificationTrigger *)trigger _setAnchor:[NSDate date]];
        when = [(UNTimeIntervalNotificationTrigger *)trigger nextTriggerDate];
    } else if ([trigger isKindOfClass:[UNCalendarNotificationTrigger class]])
        when = [(UNCalendarNotificationTrigger *)trigger nextTriggerDate];
    else
        when = nil;                     /* a push trigger: never here */
    [self _cancelPending:ident];
    NSError *error = nil;
    if (!when)
        error = [NSError errorWithDomain:UNErrorDomain code:UNErrorCodeNotificationInvalidNoDate userInfo:nil];
    else {
        if (trigger) {
            @synchronized(self) {
                [_pending addObject:request];
            }
        }
        [self _arm:request at:when];
    }
    if (handler && !error && !trigger) {
        /* A request with no trigger is delivered on the next turn of the main
           run loop; its handler is called once that has happened, so the app
           always hears of the delivery (and is asked about presenting it)
           before it hears that the request was added. */
        void (^copy)(NSError *) = [[handler copy] autorelease];
        [_addHandlers setObject:copy forKey:ident];
    } else if (handler)
        later(^{
            handler(error);
        });
}

/* Calls the waiting add handler of an immediate request, if there is one. */
- (void)_added:(NSString *)ident
{
    void (^handler)(NSError *) = [[[_addHandlers objectForKey:ident] retain] autorelease];
    if (!handler)
        return;
    [_addHandlers removeObjectForKey:ident];
    later(^{
        handler(nil);
    });
}

- (void)_due:(NSTimer *)timer
{
    UNNotificationRequest *request = [[[timer userInfo] retain] autorelease];
    NSString *ident = [request identifier];
    if ([_timers objectForKey:ident] != timer)
        return;
    [_timers removeObjectForKey:ident];
    UNNotificationTrigger *trigger = [request trigger];
    NSDate *next = nil;
    if ([trigger repeats]) {
        if ([trigger isKindOfClass:[UNTimeIntervalNotificationTrigger class]])
            next = [(UNTimeIntervalNotificationTrigger *)trigger nextTriggerDate];
        else if ([trigger isKindOfClass:[UNCalendarNotificationTrigger class]])
            next = [(UNCalendarNotificationTrigger *)trigger nextTriggerDate];
    }
    if (next)
        [self _arm:request at:next];
    else {
        @synchronized(self) {
            [_pending removeObjectIdenticalTo:request];
        }
    }
    [self _deliver:request];
    [self _added:ident];
}

- (void)getPendingNotificationRequestsWithCompletionHandler:(void (^)(NSArray<UNNotificationRequest *> *requests))handler
{
    ON_MAIN([self getPendingNotificationRequestsWithCompletionHandler:handler])
    if (!handler)
        return;
    NSArray *now;
    @synchronized(self) {
        now = [[_pending copy] autorelease];
    }
    later(^{
        handler(now);
    });
}

- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray *)identifiers
{
    ON_MAIN([self removePendingNotificationRequestsWithIdentifiers:identifiers])
    for (NSString *ident in identifiers)
        [self _cancelPending:ident];
}

- (void)removeAllPendingNotificationRequests
{
    ON_MAIN([self removeAllPendingNotificationRequests])
    for (UNNotificationRequest *r in [[_pending copy] autorelease])
        [self _cancelPending:[r identifier]];
}

/* ---- delivering ---- */

static BOOL has_text(UNNotificationContent *c)
{
    return [[c title] length] || [[c subtitle] length] || [[c body] length];
}

- (ANotifyMessage *)_message:(UNNotification *)n options:(UNNotificationPresentationOptions)options
                      shown:(FUNShown *)shown
{
    UNNotificationContent *c = [[n request] content];
    ANotifyMessage *m = [[[ANotifyMessage alloc] init] autorelease];
    [m setSummary:[[c title] length] ? [c title] : ANotifyAppName()];
    NSMutableArray *lines = [NSMutableArray array];
    if ([[c subtitle] length])
        [lines addObject:[c subtitle]];
    if ([[c body] length])
        [lines addObject:[c body]];
    [m setBody:[lines componentsJoinedByString:@"\n"]];
    NSMutableArray *actions = [NSMutableArray arrayWithObject:@[ @"default", @"Open" ]];
    for (UNNotificationAction *a in [shown->category actions]) {
        if (![[a identifier] length])
            continue;
        if ([a isKindOfClass:[UNTextInputNotificationAction class]] && !shown->replyAction &&
            ANotifyServerCan(@"inline-reply")) {
            UNTextInputNotificationAction *t = (UNTextInputNotificationAction *)a;
            shown->replyAction = [[a identifier] copy];
            [m setReplyKey:[@"action:" stringByAppendingString:[a identifier]]];
            [m setReplyButton:[[t textInputButtonTitle] length] ? [t textInputButtonTitle] : [a title]];
            [m setReplyPlaceholder:[t textInputPlaceholder]];
            continue;
        }
        [actions addObject:@[ [@"action:" stringByAppendingString:[a identifier]], [a title] ?: [a identifier] ]];
    }
    [m setActions:actions];
    UNNotificationInterruptionLevel level = [c interruptionLevel];
    [m setUrgency:level == UNNotificationInterruptionLevelPassive    ? 0
                  : level == UNNotificationInterruptionLevelCritical ? 2
                                                                     : 1];
    UNNotificationSound *sound = [c sound];
    if (!sound || !(options & UNNotificationPresentationOptionSound))
        [m setSilent:YES];
    else if (sound->_name) {
        NSString *path = [[NSBundle mainBundle] pathForResource:sound->_name ofType:nil];
        if (path)
            [m setSoundFile:path];
        else
            [m setSoundName:sound->_name];
    }
    return m;
}

- (void)_present:(UNNotification *)n options:(UNNotificationPresentationOptions)options
{
    UNNotificationContent *c = [[n request] content];
    if ((options & UNNotificationPresentationOptionBadge) && [c badge])
        ADockSetBadge([[c badge] integerValue] > 0 ? [[c badge] stringValue] : nil);
    if (!(options & (UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionAlert |
                     UNNotificationPresentationOptionList)) ||
        !has_text(c))
        return;
    NSString *ident = [[n request] identifier];
    FUNShown *old = [[[_shown objectForKey:ident] retain] autorelease];
    unsigned replaces = 0;
    if (old) {
        old->answered = YES;
        replaces = old->handle;
        [self _gone:old->notification];
    }
    FUNShown *shown = [[[FUNShown alloc] init] autorelease];
    shown->notification = [n retain];
    shown->category = [[self _category:[c categoryIdentifier]] retain];
    @synchronized(self) {
        [_delivered addObject:n];
    }
    [_shown setObject:shown forKey:ident];
    shown->handle = ANotifyShow([self _message:n options:options shown:shown], shown, replaces);
}

- (void)_deliver:(UNNotificationRequest *)request
{
    UNNotification *n = [[[UNNotification alloc] _initWithRequest:request date:[NSDate date]] autorelease];
    UNNotificationPresentationOptions standard = UNNotificationPresentationOptionBanner |
                                                 UNNotificationPresentationOptionList |
                                                 UNNotificationPresentationOptionSound |
                                                 UNNotificationPresentationOptionBadge;
    SEL ask = @selector(userNotificationCenter:willPresentNotification:withCompletionHandler:);
    if (![NSApp isActive] || ![_delegate respondsToSelector:ask]) {
        [self _present:n options:standard];
        return;
    }
    __block BOOL done = NO;
    [n retain];
    [self retain];
    void (^handler)(UNNotificationPresentationOptions) = ^(UNNotificationPresentationOptions options) {
        void (^present)(void) = ^{
            if (done)
                return;
            done = YES;
            [self _present:n options:options];
            [n release];
            [self release];
        };
        if (pthread_main_np())
            present();
        else
            dispatch_async(dispatch_get_main_queue(), present);
    };
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(_delegate, ask, self, n, handler);
}

/* ---- delivered notifications ---- */

- (void)_gone:(UNNotification *)n
{
    NSString *ident = [[n request] identifier];
    FUNShown *s = [_shown objectForKey:ident];
    if (s && s->notification == n)
        [_shown removeObjectForKey:ident];
    @synchronized(self) {
        [_delivered removeObjectIdenticalTo:n];
    }
}

- (void)_respond:(UNNotification *)n action:(NSString *)action text:(NSString *)text foreground:(BOOL)foreground
{
    [[n retain] autorelease];
    [self _gone:n];
    UNNotificationResponse *r;
    if (text) {
        UNTextInputNotificationResponse *t = [[[UNTextInputNotificationResponse alloc] init] autorelease];
        t->_text = [text copy];
        r = t;
    } else
        r = [[[UNNotificationResponse alloc] init] autorelease];
    r->_notification = [n retain];
    r->_action = [action copy];
    if (foreground)
        [NSApp activateIgnoringOtherApps:YES];
    SEL tell = @selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:);
    if ([_delegate respondsToSelector:tell])
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(_delegate, tell, self, r, ^{
        });
}

- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *notifications))handler
{
    ON_MAIN([self getDeliveredNotificationsWithCompletionHandler:handler])
    if (!handler)
        return;
    NSArray *now;
    @synchronized(self) {
        now = [[_delivered copy] autorelease];
    }
    later(^{
        handler(now);
    });
}

- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray *)identifiers
{
    ON_MAIN([self removeDeliveredNotificationsWithIdentifiers:identifiers])
    for (NSString *ident in identifiers) {
        FUNShown *s = [[[_shown objectForKey:ident] retain] autorelease];
        if (s) {
            s->answered = YES;
            ANotifyClose(s->handle);
            s->handle = 0;
        }
        for (UNNotification *n in [self _deliveredNow])
            if ([[[n request] identifier] isEqualToString:ident])
                [self _gone:n];
    }
}

- (NSArray *)_deliveredNow
{
    @synchronized(self) {
        return [[_delivered copy] autorelease];
    }
}

- (void)removeAllDeliveredNotifications
{
    ON_MAIN([self removeAllDeliveredNotifications])
    NSMutableArray *idents = [NSMutableArray array];
    for (UNNotification *n in [self _deliveredNow])
        [idents addObject:[[n request] identifier]];
    [self removeDeliveredNotificationsWithIdentifiers:idents];
}

- (void)setBadgeCount:(NSInteger)count withCompletionHandler:(void (^)(NSError *error))handler
{
    ON_MAIN([self setBadgeCount:count withCompletionHandler:handler])
    ADockSetBadge(count > 0 ? [NSString stringWithFormat:@"%ld", (long)count] : nil);
    if (handler)
        later(^{
            handler(nil);
        });
}
@end
