/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSApplication, the event queue and the connection to the
 * display, plus NSScreen and NSMenu. GTK is started the first time a window
 * is shown (or the screen is asked about); after that, GLib's main context
 * is waited on together with Foundation's run loop (through a hook in
 * Ferry's NSRunLoop), so timers, file descriptors and window events all wake
 * the same loop, and nextEventMatchingMask: works as on a Mac. */
#import "AInternal.h"

NSApplication *NSApp;
NSNotificationName const NSApplicationWillFinishLaunchingNotification = @"NSApplicationWillFinishLaunchingNotification";
NSNotificationName const NSApplicationDidFinishLaunchingNotification = @"NSApplicationDidFinishLaunchingNotification";
NSNotificationName const NSApplicationWillTerminateNotification = @"NSApplicationWillTerminateNotification";
NSNotificationName const NSApplicationDidBecomeActiveNotification = @"NSApplicationDidBecomeActiveNotification";
NSNotificationName const NSApplicationDidResignActiveNotification = @"NSApplicationDidResignActiveNotification";

/* ---- the display ---------------------------------------------------------------------- */

static int display_state;           /* 0 not tried, 1 connected, -1 none */
static GMainContext *glib;
static int glib_priority;

static int glib_prepare(void *ctx, int *timeout_ms, struct pollfd *fds, int max)
{
    int timeout = -1;
    g_main_context_prepare(glib, &glib_priority);
    int n = g_main_context_query(glib, glib_priority, &timeout, (GPollFD *)fds, max);
    if (n > max)
        n = max;
    if (timeout >= 0 && timeout < *timeout_ms)
        *timeout_ms = timeout;
    return n;
}

static BOOL glib_dispatch(void *ctx, struct pollfd *fds, int count)
{
    if (!g_main_context_check(glib, glib_priority, (GPollFD *)fds, count))
        return NO;
    g_main_context_dispatch(glib);
    return YES;
}

BOOL ADisplayAvailable(void)
{
    if (display_state)
        return display_state > 0;
    display_state = -1;
    const char *wayland = getenv("WAYLAND_DISPLAY"), *x11 = getenv("DISPLAY");
    if ((!wayland || !*wayland) && (!x11 || !*x11))
        return NO;
    /* the Wayland app id: the bundle identifier, else the program's name */
    NSString *ident = [[NSBundle mainBundle] bundleIdentifier] ?: [[NSProcessInfo processInfo] processName];
    if (ident)
        g_set_prgname([ident UTF8String]);
    NSString *name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    if (name)
        g_set_application_name([name UTF8String]);
    if (!gtk_init_check(NULL, NULL)) {
        fflush(stdout);
        fprintf(stderr, "AppKit (Ferry): can't open the display; windows will only be drawn off screen\n");
        return NO;
    }
    glib = g_main_context_default();
    g_main_context_acquire(glib);
    FerryRunLoopSetPollHook(glib_prepare, glib_dispatch, NULL);
    display_state = 1;
    return YES;
}

static GdkMonitor *primary_monitor(void)
{
    if (!ADisplayAvailable())
        return NULL;
    GdkDisplay *d = gdk_display_get_default();
    GdkMonitor *m = d ? gdk_display_get_primary_monitor(d) : NULL;
    if (!m && d && gdk_display_get_n_monitors(d) > 0)
        m = gdk_display_get_monitor(d, 0);
    return m;
}

/* Without a display, a 1440 x 900 screen at scale 1. */
NSRect AScreenFrame(BOOL visibleOnly)
{
    GdkMonitor *m = primary_monitor();
    if (!m)
        return NSMakeRect(0, 0, 1440, 900);
    GdkRectangle all, work;
    gdk_monitor_get_geometry(m, &all);
    if (!visibleOnly)
        return NSMakeRect(0, 0, all.width, all.height);
    gdk_monitor_get_workarea(m, &work);
    /* screen coordinates run up from the bottom, as on a Mac */
    return NSMakeRect(work.x - all.x, (all.y + all.height) - (work.y + work.height), work.width, work.height);
}

CGFloat AScreenScale(void)
{
    GdkMonitor *m = primary_monitor();
    int s = m ? gdk_monitor_get_scale_factor(m) : 1;
    return s > 0 ? s : 1;
}

void NSBeep(void)
{
    if (display_state > 0)
        gdk_display_beep(gdk_display_get_default());
}

/* ---- NSScreen -------------------------------------------------------------------------- */

@implementation NSScreen
+ (NSScreen *)mainScreen
{
    static NSScreen *screen;
    if (!screen)
        screen = [[NSScreen alloc] init];
    return screen;
}
+ (NSArray *)screens { return @[ [self mainScreen] ]; }
- (NSRect)frame { return AScreenFrame(NO); }
- (NSRect)visibleFrame { return AScreenFrame(YES); }
- (CGFloat)backingScaleFactor { return AScreenScale(); }
- (NSString *)localizedName { return @"Display"; }
- (NSDictionary *)deviceDescription
{
    return @{@"NSScreenNumber" : @1, @"NSDeviceSize" : [NSValue valueWithSize:[self frame].size]};
}
@end

/* ---- the event queue -------------------------------------------------------------------- */

static NSMutableArray *queue;

void AEnqueueEvent(NSEvent *event)
{
    if (!queue)
        queue = [[NSMutableArray alloc] init];
    [queue addObject:event];
}

void AWindowDidClose(NSWindow *window)
{
    for (NSEvent *e in [[queue copy] autorelease])
        if ([e window] == window && [e type] != NSEventTypeApplicationDefined)
            [queue removeObjectIdenticalTo:e];
    if (window == [NSApp mainWindow] || window == [NSApp keyWindow]) {
        for (NSWindow *w in [AAllWindows() reverseObjectEnumerator])
            if ([w isVisible] && [w canBecomeKeyWindow]) {
                [w makeKeyWindow];
                [w makeMainWindow];
                break;
            }
    }
    /* the last window closing may end the program, once it is safe to */
    id delegate = [NSApp delegate];
    if ([delegate respondsToSelector:@selector(applicationShouldTerminateAfterLastWindowClosed:)] &&
        [delegate applicationShouldTerminateAfterLastWindowClosed:NSApp]) {
        for (NSWindow *w in AAllWindows())
            if ([w isVisible])
                return;
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0];
    }
}

/* ---- menus --------------------------------------------------------------------------- */

@implementation NSMenuItem {
    NSString *_title, *_key, *_tip;
    SEL _action;
    id _target, _represented;
    NSEventModifierFlags _mask;
    NSInteger _tag, _indent;
    NSControlStateValue _state;
    BOOL _enabled, _hidden, _separator;
    NSMenu *_submenu, *_menu;
    NSImage *_image;
}
+ (NSMenuItem *)separatorItem
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    item->_separator = YES;
    item->_enabled = NO;
    return [item autorelease];
}
- (instancetype)init { return [self initWithTitle:@"" action:NULL keyEquivalent:@""]; }
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key
{
    if ((self = [super init])) {
        _title = [title ?: @"" copy];
        _action = action;
        _key = [key ?: @"" copy];
        _mask = NSEventModifierFlagCommand;
        _enabled = YES;
    }
    return self;
}
- (void)dealloc
{
    [_title release];
    [_key release];
    [_tip release];
    [_represented release];
    [_submenu release];
    [_image release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSMenuItem *c = [[NSMenuItem alloc] initWithTitle:_title action:_action keyEquivalent:_key];
    c->_target = _target;
    c->_mask = _mask;
    c->_tag = _tag;
    c->_state = _state;
    c->_enabled = _enabled;
    c->_separator = _separator;
    return c;
}
- (NSString *)description { return [NSString stringWithFormat:@"<NSMenuItem: %p %@>", self, _title]; }
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t
{
    [_title release];
    _title = [t ?: @"" copy];
}
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (NSString *)keyEquivalent { return _key; }
- (void)setKeyEquivalent:(NSString *)k
{
    [_key release];
    _key = [k ?: @"" copy];
}
- (NSEventModifierFlags)keyEquivalentModifierMask { return _mask; }
- (void)setKeyEquivalentModifierMask:(NSEventModifierFlags)m { _mask = m; }
- (NSInteger)tag { return _tag; }
- (void)setTag:(NSInteger)t { _tag = t; }
- (NSControlStateValue)state { return _state; }
- (void)setState:(NSControlStateValue)s { _state = s; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)e { _enabled = e; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)h { _hidden = h; }
- (NSMenu *)submenu { return _submenu; }
- (void)setSubmenu:(NSMenu *)m
{
    [m retain];
    [_submenu setSupermenu:nil];
    [_submenu release];
    _submenu = m;
    [m setSupermenu:_menu];
}
- (BOOL)hasSubmenu { return _submenu != nil; }
- (NSMenu *)menu { return _menu; }
- (void)_setMenu:(NSMenu *)menu
{
    _menu = menu;
    [_submenu setSupermenu:menu];
}
- (BOOL)isSeparatorItem { return _separator; }
- (id)representedObject { return _represented; }
- (void)setRepresentedObject:(id)o
{
    [o retain];
    [_represented release];
    _represented = o;
}
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)image
{
    [(id)image retain];
    [(id)_image release];
    _image = image;
}
- (NSInteger)indentationLevel { return _indent; }
- (void)setIndentationLevel:(NSInteger)i { _indent = i; }
- (NSString *)toolTip { return _tip; }
- (void)setToolTip:(NSString *)t
{
    [_tip release];
    _tip = [t copy];
}
@end

@implementation NSMenu {
    NSString *_title;
    NSMutableArray *_items;
    NSMenu *_supermenu;
    BOOL _autoenables;
    id _delegate;
}
- (instancetype)init { return [self initWithTitle:@""]; }
- (instancetype)initWithTitle:(NSString *)title
{
    if ((self = [super init])) {
        _title = [title ?: @"" copy];
        _items = [[NSMutableArray alloc] init];
        _autoenables = YES;
    }
    return self;
}
- (void)dealloc
{
    for (NSMenuItem *i in _items)
        [i _setMenu:nil];
    [_title release];
    [_items release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSMenu *m = [[NSMenu alloc] initWithTitle:_title];
    for (NSMenuItem *i in _items) {
        NSMenuItem *c = [i copy];
        [m addItem:c];
        [c release];
    }
    return m;
}
- (NSString *)description { return [NSString stringWithFormat:@"<NSMenu: %p %@, %lu items>", self, _title, (unsigned long)[_items count]]; }
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t
{
    [_title release];
    _title = [t ?: @"" copy];
}
- (NSArray *)itemArray { return [[_items copy] autorelease]; }
- (NSInteger)numberOfItems { return [_items count]; }
- (NSMenu *)supermenu { return _supermenu; }
- (void)setSupermenu:(NSMenu *)m { _supermenu = m; }
- (BOOL)autoenablesItems { return _autoenables; }
- (void)setAutoenablesItems:(BOOL)f { _autoenables = f; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (void)insertItem:(NSMenuItem *)item atIndex:(NSInteger)index
{
    if (!item)
        return;
    if (index < 0 || index > (NSInteger)[_items count])
        index = [_items count];
    [_items insertObject:item atIndex:index];
    [item _setMenu:self];
}
- (void)addItem:(NSMenuItem *)item { [self insertItem:item atIndex:[_items count]]; }
- (NSMenuItem *)insertItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key
                            atIndex:(NSInteger)index
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    [self insertItem:item atIndex:index];
    return [item autorelease];
}
- (NSMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key
{
    return [self insertItemWithTitle:title action:action keyEquivalent:key atIndex:[_items count]];
}
- (void)removeItem:(NSMenuItem *)item
{
    [item _setMenu:nil];
    [_items removeObjectIdenticalTo:item];
}
- (void)removeItemAtIndex:(NSInteger)index { [self removeItem:[self itemAtIndex:index]]; }
- (void)removeAllItems
{
    for (NSMenuItem *i in _items)
        [i _setMenu:nil];
    [_items removeAllObjects];
}
- (NSMenuItem *)itemAtIndex:(NSInteger)index
{
    return index >= 0 && index < (NSInteger)[_items count] ? _items[index] : nil;
}
- (NSMenuItem *)itemWithTitle:(NSString *)title
{
    for (NSMenuItem *i in _items)
        if ([[i title] isEqualToString:title])
            return i;
    return nil;
}
- (NSMenuItem *)itemWithTag:(NSInteger)tag
{
    for (NSMenuItem *i in _items)
        if ([i tag] == tag)
            return i;
    return nil;
}
- (NSInteger)indexOfItem:(NSMenuItem *)item
{
    NSUInteger i = [_items indexOfObjectIdenticalTo:item];
    return i == NSNotFound ? -1 : (NSInteger)i;
}
- (NSInteger)indexOfItemWithTitle:(NSString *)title
{
    NSMenuItem *i = [self itemWithTitle:title];
    return i ? [self indexOfItem:i] : -1;
}
- (void)setSubmenu:(NSMenu *)menu forItem:(NSMenuItem *)item { [item setSubmenu:menu]; }
- (void)update {}

/* Whether a key press is this item's key equivalent: the same key (an
 * upper-case equivalent means Shift too) and the same modifiers. */
static BOOL matches(NSMenuItem *item, NSEvent *event)
{
    NSString *key = [item keyEquivalent];
    if (![key length])
        return NO;
    NSEventModifierFlags want = [item keyEquivalentModifierMask] &
                                (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                                 NSEventModifierFlagControl | NSEventModifierFlagShift);
    unichar k = [key characterAtIndex:0];
    if (k < 128 && isupper(k))
        want |= NSEventModifierFlagShift;
    NSEventModifierFlags have = [event modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                                                         NSEventModifierFlagControl | NSEventModifierFlagShift);
    if (want != have)
        return NO;
    NSString *typed = [event charactersIgnoringModifiers];
    return [[typed lowercaseString] isEqualToString:[key lowercaseString]];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    for (NSMenuItem *item in [[_items copy] autorelease]) {
        if ([item hasSubmenu]) {
            if ([[item submenu] performKeyEquivalent:event])
                return YES;
            continue;
        }
        if (![item isEnabled] || [item isHidden] || !matches(item, event))
            continue;
        SEL action = [item action];
        if (!action)
            return NO;
        if (_autoenables) {
            id target = [NSApp targetForAction:action to:[item target] from:item];
            if (!target)
                return NO;
            if ([target respondsToSelector:@selector(validateMenuItem:)] && ![target validateMenuItem:item])
                return NO;
        }
        [NSApp sendAction:action to:[item target] from:item];
        return YES;
    }
    return NO;
}
@end

/* ---- NSApplication --------------------------------------------------------------------- */

@implementation NSApplication {
    id _delegate;
    NSMenu *_mainMenu;
    NSMenu *_windowsMenu, *_servicesMenu, *_helpMenu;
    BOOL _running, _launched, _active;
    NSEvent *_current;
    NSApplicationActivationPolicy _policy;
    id _icon;
    NSWindow *_modal;
    NSModalResponse _modalCode;
    BOOL _modalStopped;
}

+ (NSApplication *)sharedApplication
{
    if (!NSApp) {
        [[self alloc] init];
    }
    return NSApp;
}

- (instancetype)init
{
    if (NSApp) {
        [self release];
        return NSApp;
    }
    if ((self = [super init])) {
        NSApp = self;
        _policy = NSApplicationActivationPolicyRegular;
    }
    return self;
}

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (NSMenu *)mainMenu { return _mainMenu; }
- (void)setMainMenu:(NSMenu *)menu
{
    [menu retain];
    [_mainMenu release];
    _mainMenu = menu;
}
- (NSMenu *)windowsMenu { return _windowsMenu; }
- (void)setWindowsMenu:(NSMenu *)m { _windowsMenu = m; }
- (NSMenu *)servicesMenu { return _servicesMenu; }
- (void)setServicesMenu:(NSMenu *)m { _servicesMenu = m; }
- (NSMenu *)helpMenu { return _helpMenu; }
- (void)setHelpMenu:(NSMenu *)m { _helpMenu = m; }
- (NSArray *)windows { return AAllWindows(); }
- (NSWindow *)keyWindow { return AKeyWindow(); }
- (NSWindow *)mainWindow { return AMainWindow(); }
- (BOOL)isRunning { return _running; }
- (BOOL)isActive { return _active; }
- (NSEvent *)currentEvent { return _current; }
- (id)applicationIconImage { return _icon; }
- (void)setApplicationIconImage:(id)image
{
    [image retain];
    [_icon release];
    _icon = image;
}
- (NSWindow *)modalWindow { return _modal; }
- (NSWindow *)windowWithWindowNumber:(NSInteger)number
{
    for (NSWindow *w in AAllWindows())
        if ([w windowNumber] == number)
            return w;
    return nil;
}
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)policy
{
    _policy = policy;
    return YES;
}
- (NSApplicationActivationPolicy)activationPolicy { return _policy; }

- (void)_post:(NSNotificationName)name selector:(SEL)sel
{
    NSNotification *n = [NSNotification notificationWithName:name object:self];
    if ([_delegate respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(_delegate, sel, n);
    [[NSNotificationCenter defaultCenter] postNotification:n];
}

- (void)activateIgnoringOtherApps:(BOOL)flag
{
    if (_active)
        return;
    _active = YES;
    [self _post:NSApplicationDidBecomeActiveNotification selector:@selector(applicationDidBecomeActive:)];
}
- (void)activate { [self activateIgnoringOtherApps:YES]; }
- (void)deactivate
{
    if (!_active)
        return;
    _active = NO;
    [self _post:NSApplicationDidResignActiveNotification selector:@selector(applicationDidResignActive:)];
}
- (void)hide:(id)sender
{
    for (NSWindow *w in AAllWindows())
        if ([w isVisible])
            [w miniaturize:sender];
}
- (void)unhide:(id)sender
{
    for (NSWindow *w in AAllWindows())
        if ([w isMiniaturized])
            [w deminiaturize:sender];
}
- (void)hideOtherApplications:(id)sender {}
- (void)unhideAllApplications:(id)sender {}
- (void)arrangeInFront:(id)sender {}
- (void)miniaturizeAll:(id)sender { [self hide:sender]; }
- (void)orderFrontStandardAboutPanel:(id)sender { [self orderFrontStandardAboutPanelWithOptions:@{}]; }
- (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary *)options
{
    AWarnOnce("the standard About panel");
}
- (NSInteger)requestUserAttention:(NSInteger)type { return 0; }

- (void)finishLaunching
{
    if (_launched)
        return;
    _launched = YES;
    [self _post:NSApplicationWillFinishLaunchingNotification selector:@selector(applicationWillFinishLaunching:)];
    [self activateIgnoringOtherApps:YES];
    [self _post:NSApplicationDidFinishLaunchingNotification selector:@selector(applicationDidFinishLaunching:)];
}

- (void)run
{
    [self finishLaunching];
    _running = YES;
    while (_running) {
        @autoreleasepool {
            NSEvent *e = [self nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture]
                                              inMode:NSDefaultRunLoopMode dequeue:YES];
            if (e)
                [self sendEvent:e];
        }
    }
}

/* Wakes nextEventMatchingMask: so that run notices. */
static void post_wakeup(void)
{
    NSEvent *e = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
                                   timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
    AEnqueueEvent(e);
}

- (void)stop:(id)sender
{
    if (_modal) {
        [self stopModal];
        return;
    }
    _running = NO;
    post_wakeup();
}

- (void)terminate:(id)sender
{
    if ([_delegate respondsToSelector:@selector(applicationShouldTerminate:)]) {
        NSApplicationTerminateReply r = [_delegate applicationShouldTerminate:self];
        if (r == NSTerminateCancel)
            return;
        if (r == NSTerminateLater) {
            AWarnOnce("NSTerminateLater (the program quits now)");
        }
    }
    [self _post:NSApplicationWillTerminateNotification selector:@selector(applicationWillTerminate:)];
    [[NSUserDefaults standardUserDefaults] synchronize];
    fflush(stdout);
    exit(0);
}
- (void)replyToApplicationShouldTerminate:(BOOL)shouldTerminate
{
    if (shouldTerminate)
        [self terminate:nil];
}

static BOOL wanted(NSEvent *e, NSEventMask mask) { return (mask & NSEventMaskFromType([e type])) != 0; }

- (NSEvent *)nextEventMatchingMask:(NSEventMask)mask untilDate:(NSDate *)date inMode:(NSRunLoopMode)mode
                           dequeue:(BOOL)dequeue
{
    NSTimeInterval limit = date ? [date timeIntervalSinceReferenceDate] : 0;
    for (;;) {
        for (NSEvent *e in queue) {
            if (!wanted(e, mask))
                continue;
            [[e retain] autorelease];
            if (dequeue)
                [queue removeObjectIdenticalTo:e];
            return e;
        }
        AWindowsDisplayIfNeeded();
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now >= limit)
            return nil;
        NSDate *until = [NSDate dateWithTimeIntervalSinceReferenceDate:limit];
        if (![[NSRunLoop currentRunLoop] runMode:mode ?: NSDefaultRunLoopMode beforeDate:until]) {
            /* nothing could ever wake the loop; wait as a Mac would, in slices */
            NSTimeInterval wait = fmin(limit - now, 0.05);
            if (wait > 0)
                usleep((useconds_t)(wait * 1e6));
        }
    }
}

- (void)discardEventsMatchingMask:(NSEventMask)mask beforeEvent:(NSEvent *)event
{
    for (NSEvent *e in [[queue copy] autorelease]) {
        if (event && e == event)
            break;
        if (wanted(e, mask))
            [queue removeObjectIdenticalTo:e];
    }
}

- (void)postEvent:(NSEvent *)event atStart:(BOOL)atStart
{
    if (!event)
        return;
    if (!queue)
        queue = [[NSMutableArray alloc] init];
    if (atStart)
        [queue insertObject:event atIndex:0];
    else
        [queue addObject:event];
}

- (void)sendEvent:(NSEvent *)e
{
    NSEvent *saved = _current;
    _current = e;
    NSWindow *w = [e window];
    if ([e type] == NSEventTypeKeyDown && ([e modifierFlags] & NSEventModifierFlagCommand)) {
        /* key equivalents: the key window's views, then the menus */
        NSWindow *key = AKeyWindow() ?: w;
        if (![key performKeyEquivalent:e] && ![_mainMenu performKeyEquivalent:e])
            [key ?: w sendEvent:e];
    } else if ([e type] == NSEventTypeKeyDown || [e type] == NSEventTypeKeyUp ||
               [e type] == NSEventTypeFlagsChanged) {
        [(AKeyWindow() ?: w) sendEvent:e];
    } else if (w) {
        [w sendEvent:e];
    }
    _current = saved;
}

/* The responder that will take action: the key window's responder chain,
 * the key window and its delegate, the main window and its delegate (when
 * it isn't the key window), then the application and its delegate. */
- (id)targetForAction:(SEL)action
{
    if (!action)
        return nil;
    NSMutableArray *windows = [NSMutableArray array];
    if (AKeyWindow())
        [windows addObject:AKeyWindow()];
    if (AMainWindow() && AMainWindow() != AKeyWindow())
        [windows addObject:AMainWindow()];
    for (NSWindow *w in windows) {
        for (NSResponder *r = [w firstResponder]; r; r = [r nextResponder])
            if ([r respondsToSelector:action])
                return r;
        if ([w respondsToSelector:action])
            return w;
        if ([[w delegate] respondsToSelector:action])
            return [w delegate];
    }
    if ([self respondsToSelector:action])
        return self;
    if ([_delegate respondsToSelector:action])
        return _delegate;
    return nil;
}

- (id)targetForAction:(SEL)action to:(id)target from:(id)sender
{
    if (target)
        return [target respondsToSelector:action] ? target : nil;
    return [self targetForAction:action];
}

- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender
{
    id t = [self targetForAction:action to:target from:sender];
    if (!t)
        return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(t, action, sender);
    return YES;
}

- (BOOL)tryToPerform:(SEL)action with:(id)object
{
    if ([super tryToPerform:action with:object])
        return YES;
    if ([_delegate respondsToSelector:action]) {
        ((void (*)(id, SEL, id))objc_msgSend)(_delegate, action, object);
        return YES;
    }
    return NO;
}

- (void)updateWindows { AWindowsDisplayIfNeeded(); }

/* A modal loop: only events for the modal window are handled (and those
 * that aren't for any window), until stopModal. */
- (NSModalResponse)runModalForWindow:(NSWindow *)window
{
    NSWindow *outer = _modal;
    _modal = window;
    _modalStopped = NO;
    _modalCode = NSModalResponseContinue;
    [window makeKeyAndOrderFront:nil];
    while (!_modalStopped) {
        @autoreleasepool {
            NSEvent *e = [self nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture]
                                              inMode:NSDefaultRunLoopMode dequeue:YES];
            if (!e)
                continue;
            NSWindow *w = [e window];
            BOOL key = [e type] == NSEventTypeKeyDown || [e type] == NSEventTypeKeyUp;
            if (!w || w == window || (key && AKeyWindow() == window))
                [self sendEvent:e];
        }
    }
    _modal = outer;
    _modalStopped = NO;
    return _modalCode;
}
- (void)stopModalWithCode:(NSModalResponse)code
{
    _modalCode = code;
    _modalStopped = YES;
    post_wakeup();
}
- (void)stopModal { [self stopModalWithCode:NSModalResponseStop]; }
- (void)abortModal { [self stopModalWithCode:NSModalResponseAbort]; }
@end

/* Makes the application object (the Info.plist's NSPrincipalClass, else
 * NSApplication) and runs it. Nibs come with Ferry's next milestone. */
int NSApplicationMain(int argc, const char *argv[])
{
    @autoreleasepool {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        Class cls = NSClassFromString(info[@"NSPrincipalClass"]) ?: [NSApplication class];
        [cls sharedApplication];
        NSString *nib = info[@"NSMainNibFile"] ?: info[@"NSMainStoryboardFile"];
        if (nib)
            AWarnOnce("loading the main nib or storyboard");
    }
    [NSApp run];
    return 0;
}
