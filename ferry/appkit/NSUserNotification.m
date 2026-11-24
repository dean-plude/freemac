/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSUserNotification, NSUserNotificationAction and
 * NSUserNotificationCenter, the notification calls Mac apps used before
 * UserNotifications.framework (and many still use), written from Apple's
 * public documentation. On a Mac they are in Foundation; here they are in
 * AppKit's file, beside the D-Bus calls they need (ANotifyServer.m).
 *
 * A delivered notification is shown by the desktop's notification server:
 * its title as the summary (the app's name when it has none), its subtitle
 * and informative text as the body, and its buttons as actions. As on a Mac,
 * whose banners show no buttons unless the app asks for the alert style
 * (NSUserNotificationAlertStyle "alert" in Info.plist), the action and
 * other buttons are offered when the app gave them a title of its own or
 * asked for alerts; additional actions always are. The reply button becomes
 * an inline reply where the server takes one (the "inline-reply"
 * capability), and is left out otherwise. A click on the notification,
 * a button or a reply comes back to the delegate's
 * userNotificationCenter:didActivateNotification:; the other button just
 * closes it. When the app is active, the delegate's
 * userNotificationCenter:shouldPresentNotification: decides whether it is
 * shown, as on a Mac; it is delivered either way. Scheduled notifications
 * are delivered by timers on the main run loop, while the program runs.
 */
#import "ANotify.h"

NSString *const NSUserNotificationDefaultSoundName = @"DefaultSoundName";

@implementation NSUserNotificationAction {
    NSString *_identifier, *_title;
}
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
{
    NSUserNotificationAction *a = [[[self alloc] init] autorelease];
    a->_identifier = [identifier copy];
    a->_title = [title copy];
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
- (NSString *)description { return [NSString stringWithFormat:@"<NSUserNotificationAction %@>", _identifier]; }
@end

@interface NSUserNotification () <ANotifyOwner>
@property (readwrite, copy) NSDate *actualDeliveryDate;
@property (readwrite, getter=isPresented) BOOL presented;
@property (readwrite) NSUserNotificationActivationType activationType;
@property (readwrite, copy) NSAttributedString *response;
@property (readwrite, copy) NSUserNotificationAction *additionalActivationAction;
@end

@interface NSUserNotificationCenter (FerryPrivate)
- (void)_invoked:(NSUserNotification *)n key:(NSString *)key;
- (void)_replied:(NSUserNotification *)n text:(NSString *)text;
- (void)_closed:(NSUserNotification *)n reason:(unsigned)reason;
@end

@implementation NSUserNotification {
@public
    unsigned _handle;                   /* on screen (ANotifyShow), 0 when not */
    NSTimer *_timer;                    /* scheduled */
    NSString *_actionButtonTitle, *_otherButtonTitle;
    BOOL _titledAction, _titledOther;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _hasActionButton = YES;
        _actionButtonTitle = [@"Show" copy];
        _otherButtonTitle = [@"Close" copy];
    }
    return self;
}

- (void)dealloc
{
    [_title release];
    [_subtitle release];
    [_informativeText release];
    [_actionButtonTitle release];
    [_otherButtonTitle release];
    [_userInfo release];
    [_deliveryDate release];
    [_deliveryTimeZone release];
    [_deliveryRepeatInterval release];
    [_actualDeliveryDate release];
    [_soundName release];
    [_contentImage release];
    [_identifier release];
    [_responsePlaceholder release];
    [_response release];
    [_additionalActions release];
    [_additionalActivationAction release];
    [_timer invalidate];
    [_timer release];
    [super dealloc];
}

- (NSString *)actionButtonTitle { return [[_actionButtonTitle retain] autorelease]; }
- (NSString *)otherButtonTitle { return [[_otherButtonTitle retain] autorelease]; }
- (void)setActionButtonTitle:(NSString *)title
{
    [_actionButtonTitle autorelease];
    _actionButtonTitle = [title copy];
    _titledAction = YES;
}
- (void)setOtherButtonTitle:(NSString *)title
{
    [_otherButtonTitle autorelease];
    _otherButtonTitle = [title copy];
    _titledOther = YES;
}

- (id)copyWithZone:(NSZone *)zone
{
    NSUserNotification *c = [[NSUserNotification alloc] init];
    c.title = _title;
    c.subtitle = _subtitle;
    c.informativeText = _informativeText;
    c.actionButtonTitle = _actionButtonTitle;
    c.otherButtonTitle = _otherButtonTitle;
    c->_titledAction = _titledAction;
    c->_titledOther = _titledOther;
    c.userInfo = _userInfo;
    c.deliveryDate = _deliveryDate;
    c.deliveryTimeZone = _deliveryTimeZone;
    c.deliveryRepeatInterval = _deliveryRepeatInterval;
    c.actualDeliveryDate = _actualDeliveryDate;
    c.presented = _presented;
    c.soundName = _soundName;
    c.hasActionButton = _hasActionButton;
    c.activationType = _activationType;
    c.contentImage = _contentImage;
    c.identifier = _identifier;
    c.hasReplyButton = _hasReplyButton;
    c.responsePlaceholder = _responsePlaceholder;
    c.response = _response;
    c.additionalActions = _additionalActions;
    c.additionalActivationAction = _additionalActivationAction;
    return c;
}

- (BOOL)isRemote { return NO; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSUserNotification %p: title \"%@\">", self, _title ?: @""];
}

/* ---- as the server shows it ---- */

- (ANotifyMessage *)_message
{
    ANotifyMessage *m = [[[ANotifyMessage alloc] init] autorelease];
    [m setSummary:[_title length] ? _title : ANotifyAppName()];
    NSMutableArray *lines = [NSMutableArray array];
    if ([_subtitle length])
        [lines addObject:_subtitle];
    if ([_informativeText length])
        [lines addObject:_informativeText];
    [m setBody:[lines componentsJoinedByString:@"\n"]];
    id style = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSUserNotificationAlertStyle"];
    BOOL alerts = [style isKindOfClass:[NSString class]] && [style isEqualToString:@"alert"];
    NSMutableArray *actions = [NSMutableArray arrayWithObject:@[ @"default", @"Show" ]];
    if (_hasReplyButton) {
        [m setReplyKey:@"reply"];
        [m setReplyButton:@"Reply"];
        [m setReplyPlaceholder:_responsePlaceholder];
    } else if (_hasActionButton && (_titledAction || alerts) && [_actionButtonTitle length]) {
        [actions addObject:@[ @"action", _actionButtonTitle ]];
    }
    for (NSUserNotificationAction *a in _additionalActions)
        if ([[a identifier] length])
            [actions addObject:@[ [@"more:" stringByAppendingString:[a identifier]], [a title] ?: [a identifier] ]];
    if ((_titledOther || alerts) && [_otherButtonTitle length])
        [actions addObject:@[ @"other", _otherButtonTitle ]];
    [m setActions:actions];
    [m setUrgency:1];
    if (!_soundName)
        [m setSilent:YES];
    else if (![_soundName isEqualToString:NSUserNotificationDefaultSoundName]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:_soundName ofType:nil];
        for (NSString *ext in @[ @"aiff", @"aif", @"wav", @"caf" ])
            if (!path)
                path = [[NSBundle mainBundle] pathForResource:_soundName ofType:ext];
        if (path)
            [m setSoundFile:path];
        else
            [m setSoundName:_soundName];
    }
    return m;
}

- (void)_notifyInvoked:(NSString *)key
{
    [[NSUserNotificationCenter defaultUserNotificationCenter] _invoked:self key:key];
}
- (void)_notifyReplied:(NSString *)text
{
    [[NSUserNotificationCenter defaultUserNotificationCenter] _replied:self text:text];
}
- (void)_notifyClosed:(unsigned)reason
{
    [[NSUserNotificationCenter defaultUserNotificationCenter] _closed:self reason:reason];
}
@end

@implementation NSUserNotificationCenter {
    id _delegate;
    NSMutableArray *_scheduled, *_delivered;
}

+ (NSUserNotificationCenter *)defaultUserNotificationCenter
{
    static NSUserNotificationCenter *center;
    @synchronized([NSUserNotificationCenter class]) {
        if (!center)
            center = [[NSUserNotificationCenter alloc] init];
    }
    return center;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _scheduled = [[NSMutableArray alloc] init];
        _delivered = [[NSMutableArray alloc] init];
    }
    return self;
}

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }

- (NSArray *)deliveredNotifications
{
    @synchronized(self) {
        return [[_delivered copy] autorelease];
    }
}

- (NSArray *)scheduledNotifications
{
    @synchronized(self) {
        return [[_scheduled copy] autorelease];
    }
}

/* Changes happen on the main thread, where the server's answers come. */
- (BOOL)_onMain:(SEL)sel with:(id)arg
{
    if (pthread_main_np())
        return NO;
    [self performSelectorOnMainThread:sel withObject:arg waitUntilDone:NO];
    return YES;
}

static NSUserNotification *same_as(NSArray *list, NSUserNotification *n)
{
    for (NSUserNotification *d in list)
        if (d == n || ([[n identifier] length] && [[d identifier] isEqualToString:[n identifier]]))
            return d;
    return nil;
}

/* ---- delivering ---- */

- (BOOL)_shouldPresent:(NSUserNotification *)n
{
    if (![NSApp isActive])
        return YES;
    if (![_delegate respondsToSelector:@selector(userNotificationCenter:shouldPresentNotification:)])
        return NO;
    return ((BOOL (*)(id, SEL, id, id))objc_msgSend)(_delegate, @selector(userNotificationCenter:
                                                                       shouldPresentNotification:),
                                                     self, n);
}

- (void)_tellDelivered:(NSUserNotification *)n
{
    if ([_delegate respondsToSelector:@selector(userNotificationCenter:didDeliverNotification:)])
        ((void (*)(id, SEL, id, id))objc_msgSend)(_delegate, @selector(userNotificationCenter:didDeliverNotification:),
                                                  self, n);
}

- (void)deliverNotification:(NSUserNotification *)n
{
    if (!n || [self _onMain:_cmd with:n])
        return;
    [[n retain] autorelease];
    unsigned replaces = 0;
    @synchronized(self) {
        NSUserNotification *old = same_as(_delivered, n);
        if (old) {
            replaces = old->_handle;
            old->_handle = 0;
            [_delivered removeObjectIdenticalTo:old];
        }
    }
    n.actualDeliveryDate = [NSDate date];
    n.activationType = NSUserNotificationActivationTypeNone;
    n.response = nil;
    n.additionalActivationAction = nil;
    BOOL present = [self _shouldPresent:n];
    n.presented = present;
    @synchronized(self) {
        [_delivered addObject:n];
    }
    if (present)
        n->_handle = ANotifyShow([n _message], n, replaces);
    else
        ANotifyClose(replaces);
    /* the delegate hears of it once this turn of the run loop is over */
    [self performSelector:@selector(_tellDelivered:) withObject:n afterDelay:0];
}

- (void)_forget:(NSUserNotification *)n close:(BOOL)close
{
    if (close)
        ANotifyClose(n->_handle);
    n->_handle = 0;
    @synchronized(self) {
        [_delivered removeObjectIdenticalTo:n];
    }
}

- (void)removeDeliveredNotification:(NSUserNotification *)n
{
    if (!n || [self _onMain:_cmd with:n])
        return;
    NSUserNotification *d;
    @synchronized(self) {
        d = [[same_as(_delivered, n) retain] autorelease];
    }
    if (d)
        [self _forget:d close:YES];
}

- (void)removeAllDeliveredNotifications
{
    if ([self _onMain:_cmd with:nil])
        return;
    for (NSUserNotification *d in [self deliveredNotifications])
        [self _forget:d close:YES];
}

/* ---- what the user did ---- */

- (void)_activated:(NSUserNotification *)n
{
    [self _forget:n close:NO];
    [NSApp activateIgnoringOtherApps:YES];
    if ([_delegate respondsToSelector:@selector(userNotificationCenter:didActivateNotification:)])
        ((void (*)(id, SEL, id, id))objc_msgSend)(_delegate,
                                                  @selector(userNotificationCenter:didActivateNotification:), self, n);
}

- (void)_invoked:(NSUserNotification *)n key:(NSString *)key
{
    if ([key isEqualToString:@"other"]) {
        [self _forget:n close:YES];
        return;
    }
    if ([key isEqualToString:@"default"])
        n.activationType = NSUserNotificationActivationTypeContentsClicked;
    else if ([key isEqualToString:@"action"])
        n.activationType = NSUserNotificationActivationTypeActionButtonClicked;
    else if ([key hasPrefix:@"more:"]) {
        NSString *ident = [key substringFromIndex:5];
        for (NSUserNotificationAction *a in [n additionalActions])
            if ([[a identifier] isEqualToString:ident])
                n.additionalActivationAction = a;
        if (!n.additionalActivationAction)
            return;
        n.activationType = NSUserNotificationActivationTypeAdditionalActionClicked;
    } else
        return;
    [self _activated:n];
}

- (void)_replied:(NSUserNotification *)n text:(NSString *)text
{
    n.activationType = NSUserNotificationActivationTypeReplied;
    n.response = [[[NSAttributedString alloc] initWithString:text ?: @""] autorelease];
    [self _activated:n];
}

/* Dismissed by the user: gone from the list, as from a Mac's Notification
 * Center. A notification whose time on screen ran out stays delivered. */
- (void)_closed:(NSUserNotification *)n reason:(unsigned)reason
{
    n->_handle = 0;
    if (reason == 2) {
        @synchronized(self) {
            [_delivered removeObjectIdenticalTo:n];
        }
    }
}

/* ---- scheduling ---- */

- (void)_arm:(NSUserNotification *)n
{
    [n->_timer invalidate];
    [n->_timer release];
    NSTimeInterval wait = [n deliveryDate] ? [[n deliveryDate] timeIntervalSinceNow] : 0;
    n->_timer = [[NSTimer timerWithTimeInterval:wait > 0 ? wait : 0 target:self selector:@selector(_due:)
                                       userInfo:n repeats:NO] retain];
    [[NSRunLoop mainRunLoop] addTimer:n->_timer forMode:NSRunLoopCommonModes];
}

- (void)_disarm:(NSUserNotification *)n
{
    [n->_timer invalidate];
    [n->_timer release];
    n->_timer = nil;
}

- (void)_due:(NSTimer *)timer
{
    NSUserNotification *n = [[[timer userInfo] retain] autorelease];
    [n->_timer release];
    n->_timer = nil;
    NSDateComponents *interval = [n deliveryRepeatInterval];
    NSDate *next = nil;
    if (interval) {
        NSCalendar *cal = [[[NSCalendar currentCalendar] copy] autorelease];
        if ([n deliveryTimeZone])
            [cal setTimeZone:[n deliveryTimeZone]];
        next = [n deliveryDate] ?: [NSDate date];
        NSDate *now = [NSDate date];
        for (int i = 0; next && [next timeIntervalSinceDate:now] <= 0 && i < 100000; i++)
            next = [cal dateByAddingComponents:interval toDate:next options:0];
        if (next && [next timeIntervalSinceDate:now] <= 0)
            next = nil;
    }
    if (next) {
        n.deliveryDate = next;
        [self _arm:n];
        [self deliverNotification:[[n copy] autorelease]];
    } else {
        @synchronized(self) {
            [_scheduled removeObjectIdenticalTo:n];
        }
        [self deliverNotification:n];
    }
}

- (void)scheduleNotification:(NSUserNotification *)n
{
    if (!n || [self _onMain:_cmd with:n])
        return;
    [[n retain] autorelease];
    @synchronized(self) {
        NSUserNotification *old = same_as(_scheduled, n);
        if (old) {
            [self _disarm:old];
            [_scheduled removeObjectIdenticalTo:old];
        }
        [_scheduled addObject:n];
    }
    [self _arm:n];
}

- (void)removeScheduledNotification:(NSUserNotification *)n
{
    if (!n || [self _onMain:_cmd with:n])
        return;
    @synchronized(self) {
        NSUserNotification *old = same_as(_scheduled, n);
        if (old) {
            [self _disarm:old];
            [_scheduled removeObjectIdenticalTo:old];
        }
    }
}

- (void)setScheduledNotifications:(NSArray *)list
{
    if ([self _onMain:_cmd with:[[list copy] autorelease]])
        return;
    for (NSUserNotification *n in [self scheduledNotifications])
        [self removeScheduledNotification:n];
    for (NSUserNotification *n in list)
        [self scheduleNotification:n];
}
@end
