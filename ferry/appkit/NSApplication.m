/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSApplication, the event queue and the connection to the
 * display, plus NSScreen and NSMenu. GTK is started the first time a window
 * is shown (or the screen is asked about); after that, GLib's main context
 * is waited on together with Foundation's run loop (through a hook in
 * Ferry's NSRunLoop), so timers, file descriptors and window events all wake
 * the same loop, and nextEventMatchingMask: works as on a Mac. */
#import "AInternal.h"
#import "ANotify.h"
#import "AWayfire.h"
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

void FerryRunLoopAddDescriptor(int fd, void (*callback)(int, void *), void *ctx);

NSApplication *NSApp;
NSNotificationName const NSApplicationWillFinishLaunchingNotification = @"NSApplicationWillFinishLaunchingNotification";
NSNotificationName const NSApplicationDidFinishLaunchingNotification = @"NSApplicationDidFinishLaunchingNotification";
NSNotificationName const NSApplicationDidFinishRestoringWindowsNotification =
    @"NSApplicationDidFinishRestoringWindowsNotification";
NSNotificationName const NSApplicationWillTerminateNotification = @"NSApplicationWillTerminateNotification";
NSNotificationName const NSApplicationDidBecomeActiveNotification = @"NSApplicationDidBecomeActiveNotification";
NSNotificationName const NSApplicationDidResignActiveNotification = @"NSApplicationDidResignActiveNotification";
NSNotificationName const NSApplicationWillBecomeActiveNotification = @"NSApplicationWillBecomeActiveNotification";
NSNotificationName const NSApplicationWillResignActiveNotification = @"NSApplicationWillResignActiveNotification";

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
    AGlibAttach();
    display_state = 1;
    return YES;
}

/* Has the run loop wait on GLib's main context too: for windows, and for
 * D-Bus (menu bar items), which needs no display. */
void AGlibAttach(void)
{
    if (glib)
        return;
    glib = g_main_context_default();
    g_main_context_acquire(glib);
    FerryRunLoopSetPollHook(glib_prepare, glib_dispatch, NULL);
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

static NSUInteger beeps;
NSUInteger ABeepCount(void) { return beeps; }

void NSBeep(void)
{
    beeps++;
    if (display_state > 0)
        gdk_display_beep(gdk_display_get_default());
}

/* ---- NSScreen -------------------------------------------------------------------------- */

/* From freemac 1.215 (Ferry 0.41.0), on freemac's own compositor, every
 * display Wayfire has is a screen, the main display first, with its visible
 * frame from Wayfire's work area (less the menu bar and the Dock). GTK
 * can't give a work area on Wayland. The frames are in a Mac's screen
 * coordinates: the first screen's bottom left is the origin and y runs up.
 * Without Wayfire (or under another compositor), one screen from GTK, as
 * before. Wayfire's answer is kept for half a second. */
void GContextSyncAll(void);   /* CoreGraphics */

NSString *const NSDeviceResolution = @"NSDeviceResolution";
NSString *const NSDeviceColorSpaceName = @"NSDeviceColorSpaceName";
NSString *const NSDeviceBitsPerSample = @"NSDeviceBitsPerSample";
NSString *const NSDeviceIsScreen = @"NSDeviceIsScreen";
NSString *const NSDeviceIsPrinter = @"NSDeviceIsPrinter";
NSString *const NSDeviceSize = @"NSDeviceSize";

@implementation NSScreen {
    NSRect _frame, _visible;
    NSString *_name;
    NSInteger _number;
    BOOL _wayfire;
}

static NSMutableArray *wayfire_screens;
static NSTimeInterval wayfire_screens_read;

/* Wayfire's displays are used only when they are the ones GTK shows (a
 * program run under another compositor in a freemac session isn't on
 * them), or when the tests name a stand-in Wayfire. */
static BOOL wayfire_matches_gtk(NSArray *outputs)
{
    const char *forced = getenv("FERRY_WAYFIRE_SOCKET");
    if (forced && *forced)
        return YES;
    if (!ADisplayAvailable())
        return NO;
    NSRect gtk = AScreenFrame(NO);
    for (NSDictionary *o in outputs) {
        NSRect f = [o[@"frame"] rectValue];
        if (f.size.width == gtk.size.width && f.size.height == gtk.size.height)
            return YES;
    }
    return NO;
}

static NSArray *screens_from_wayfire(void)
{
    NSTimeInterval now = [[NSProcessInfo processInfo] systemUptime];
    if (wayfire_screens && now - wayfire_screens_read < 0.5)
        return [wayfire_screens count] ? wayfire_screens : nil;
    wayfire_screens_read = now;
    NSArray *outputs = AWayfireAvailable() ? AWayfireOutputs() : nil;
    if (!outputs || !wayfire_matches_gtk(outputs)) {
        [wayfire_screens removeAllObjects];
        return nil;
    }
    NSMutableArray *old = wayfire_screens ?: [NSMutableArray array];
    NSMutableArray *list = [NSMutableArray array];
    NSRect main = [outputs[0][@"frame"] rectValue];
    for (NSDictionary *o in outputs) {
        NSScreen *s = nil;
        for (NSScreen *was in old)
            if ([was->_name isEqual:o[@"name"]])
                s = was;
        if (!s) {
            s = [[[NSScreen alloc] init] autorelease];
            s->_name = [o[@"name"] copy];
            s->_wayfire = YES;
        }
        NSRect f = [o[@"frame"] rectValue], w = [o[@"work"] rectValue];
        /* Wayfire's layout runs down from the top left; a Mac's screens run
         * up from the first screen's bottom left */
        s->_frame = NSMakeRect(f.origin.x - main.origin.x, NSMaxY(main) - NSMaxY(f), f.size.width, f.size.height);
        s->_visible = NSMakeRect(w.origin.x - main.origin.x, NSMaxY(main) - NSMaxY(w), w.size.width, w.size.height);
        s->_number = [o[@"id"] integerValue];
        [list addObject:s];
    }
    if (!wayfire_screens)
        wayfire_screens = [[NSMutableArray alloc] init];
    [wayfire_screens setArray:list];
    return wayfire_screens;
}

+ (NSScreen *)mainScreen
{
    NSArray *w = screens_from_wayfire();
    if (w)
        return w[0];
    static NSScreen *screen;
    if (!screen)
        screen = [[NSScreen alloc] init];
    return screen;
}
+ (NSArray *)screens { return screens_from_wayfire() ?: @[ [self mainScreen] ]; }
- (NSRect)frame { return _wayfire ? _frame : AScreenFrame(NO); }
- (NSRect)visibleFrame { return _wayfire ? _visible : AScreenFrame(YES); }
- (CGFloat)backingScaleFactor { return AScreenScale(); }
- (NSString *)localizedName { return _wayfire && [_name length] ? _name : @"Display"; }
- (NSDictionary *)deviceDescription
{
    CGFloat dpi = 72 * [self backingScaleFactor];
    return @{
        @"NSScreenNumber" : @(_wayfire ? _number : 1),
        NSDeviceSize : [NSValue valueWithSize:[self frame].size],
        NSDeviceResolution : [NSValue valueWithSize:NSMakeSize(dpi, dpi)],
        NSDeviceIsScreen : @"YES",
        NSDeviceBitsPerSample : @8,
        NSDeviceColorSpaceName : @"NSCalibratedRGBColorSpace",
    };
}
- (void)dealloc
{
    [_name release];
    [super dealloc];
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

BOOL AValidateItem(id target, id item)
{
    if ([item isKindOfClass:[NSMenuItem class]] && [target respondsToSelector:@selector(validateMenuItem:)])
        return ((BOOL(*)(id, SEL, id))objc_msgSend)(target, @selector(validateMenuItem:), item);
    if ([target respondsToSelector:@selector(validateUserInterfaceItem:)])
        return ((BOOL(*)(id, SEL, id))objc_msgSend)(target, @selector(validateUserInterfaceItem:), item);
    return YES;
}

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
    NSView *_view;
    BOOL _noAutoLocalize, _noAutoMirror;
    BOOL _alternate;
}
- (BOOL)allowsAutomaticKeyEquivalentLocalization { return !_noAutoLocalize; }
- (void)setAllowsAutomaticKeyEquivalentLocalization:(BOOL)on { _noAutoLocalize = !on; }
- (BOOL)allowsAutomaticKeyEquivalentMirroring { return !_noAutoMirror; }
- (void)setAllowsAutomaticKeyEquivalentMirroring:(BOOL)on { _noAutoMirror = !on; }
+ (NSMenuItem *)separatorItem
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    item->_separator = YES;
    item->_enabled = NO;
    return [item autorelease];
}
- (instancetype)init { return [self initWithTitle:@"" action:NULL keyEquivalent:@""]; }

/* From a nib: the title, key equivalent and its modifiers, action, target,
 * tag, state, submenu and the separator, disabled and hidden switches. */
- (instancetype)initWithCoder:(NSCoder *)c
{
    if (!(self = [self initWithTitle:@"" action:NULL keyEquivalent:@""]))
        return nil;
    NSString *title = [c decodeObjectForKey:@"NSTitle"];
    if ([title isKindOfClass:[NSString class]])
        [self setTitle:title];
    NSString *key = [c decodeObjectForKey:@"NSKeyEquiv"];
    if ([key isKindOfClass:[NSString class]])
        [self setKeyEquivalent:key];
    if ([c containsValueForKey:@"NSKeyEquivModMask"])
        _mask = (NSEventModifierFlags)[c decodeInt64ForKey:@"NSKeyEquivModMask"];
    NSString *action = [c decodeObjectForKey:@"NSAction"];
    if ([action isKindOfClass:[NSString class]])
        _action = NSSelectorFromString(action);
    _target = [c decodeObjectForKey:@"NSTarget"];
    _tag = [c decodeIntegerForKey:@"NSTag"];
    _state = [c decodeIntegerForKey:@"NSState"];
    _separator = [c decodeBoolForKey:@"NSIsSeparator"];
    _enabled = !_separator && ![c decodeBoolForKey:@"NSIsDisabled"];
    _hidden = [c decodeBoolForKey:@"NSIsHidden"];
    NSMenu *sub = [c decodeObjectForKey:@"NSSubmenu"];
    if ([sub isKindOfClass:[NSMenu class]])
        [self setSubmenu:sub];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_title forKey:@"NSTitle"];
    [c encodeObject:_key forKey:@"NSKeyEquiv"];
    [c encodeInt64:(int64_t)_mask forKey:@"NSKeyEquivModMask"];
    if (_action)
        [c encodeObject:NSStringFromSelector(_action) forKey:@"NSAction"];
    if (_target)
        [c encodeConditionalObject:_target forKey:@"NSTarget"];
    [c encodeInteger:_tag forKey:@"NSTag"];
    [c encodeInteger:_state forKey:@"NSState"];
    [c encodeBool:_separator forKey:@"NSIsSeparator"];
    [c encodeBool:!_enabled forKey:@"NSIsDisabled"];
    [c encodeBool:_hidden forKey:@"NSIsHidden"];
    if (_submenu)
        [c encodeObject:_submenu forKey:@"NSSubmenu"];
}
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
    [_view release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSMenuItem *c = [[NSMenuItem alloc] initWithTitle:_title action:_action keyEquivalent:_key];
    c->_target = _target;
    c->_mask = _mask;
    c->_tag = _tag;
    c->_indent = _indent;
    c->_state = _state;
    c->_enabled = _enabled;
    c->_hidden = _hidden;
    c->_separator = _separator;
    c->_alternate = _alternate;
    c->_noAutoLocalize = _noAutoLocalize;
    c->_noAutoMirror = _noAutoMirror;
    c->_tip = [_tip copy];
    c->_represented = [_represented retain];
    c->_image = [_image retain];
    /* a copied item has a copy of the submenu, as on a Mac: MacVim copies its
     * whole menu before it hands it to NSApp (freemac 1.NEXT) */
    if (_submenu) {
        NSMenu *sub = [_submenu copy];
        [c setSubmenu:sub];
        [sub release];
    }
    return c;
}
- (NSString *)description { return [NSString stringWithFormat:@"<NSMenuItem: %p %@>", self, _title]; }
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t
{
    id wasTitle = _title;
    _title = [t ?: @"" copy];
    [wasTitle release];
}
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (NSString *)keyEquivalent { return _key; }
- (void)setKeyEquivalent:(NSString *)k
{
    id wasKey = _key;
    _key = [k ?: @"" copy];
    [wasKey release];
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
/* On a Mac an alternate item stands in for the item before it while the
 * user holds the extra modifier keys of its key equivalent. freemac's menu
 * bar has no such switch, so an alternate is left out of the menus it
 * shows (it would look like a copy of the item before it) and keeps its
 * key equivalent, which still works from the keyboard. */
- (BOOL)isAlternate { return _alternate; }
- (void)setAlternate:(BOOL)alternate { _alternate = alternate; }
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
/* A view shown in place of the title (AMenuView draws it). */
- (NSView *)view { return _view; }
- (void)setView:(NSView *)view
{
    [view retain];
    [_view release];
    _view = view;
}
- (NSInteger)indentationLevel { return _indent; }
- (void)setIndentationLevel:(NSInteger)i { _indent = i; }
- (NSString *)toolTip { return _tip; }
- (void)setToolTip:(NSString *)t
{
    id wasTip = _tip;
    _tip = [t copy];
    [wasTip release];
}
@end

@implementation NSMenu {
    NSString *_title;
    NSMutableArray *_items;
    NSMenu *_supermenu;
    BOOL _autoenables;
    BOOL _noChangeMessages;
    id _delegate;
}
- (instancetype)init { return [self initWithTitle:@""]; }
/* Whether changes post NSMenuDid...ItemNotifications; Ferry posts none, so
 * this is only kept. */
- (BOOL)menuChangedMessagesEnabled { return !_noChangeMessages; }
- (void)setMenuChangedMessagesEnabled:(BOOL)flag { _noChangeMessages = !flag; }

/* From a nib: the title, the items, and a name for the special menus
 * ("_NSMainMenu", "_NSWindowsMenu"...). */
- (instancetype)initWithCoder:(NSCoder *)c
{
    NSString *title = [c decodeObjectForKey:@"NSTitle"];
    if (!(self = [self initWithTitle:[title isKindOfClass:[NSString class]] ? title : @""]))
        return nil;
    for (NSMenuItem *item in [c decodeObjectForKey:@"NSMenuItems"])
        if ([item isKindOfClass:[NSMenuItem class]])
            [self addItem:item];
    if ([c containsValueForKey:@"NSNoAutoenable"])
        _autoenables = ![c decodeBoolForKey:@"NSNoAutoenable"];
    NSString *name = [c decodeObjectForKey:@"NSName"];
    if ([name isKindOfClass:[NSString class]])
        ANibNoteNamedMenu(self, name);
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_title forKey:@"NSTitle"];
    [c encodeObject:_items forKey:@"NSMenuItems"];
    [c encodeBool:!_autoenables forKey:@"NSNoAutoenable"];
}
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
    m->_autoenables = _autoenables;
    m->_noChangeMessages = _noChangeMessages;
    m->_delegate = _delegate;
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
    id wasTitle = _title;
    _title = [t ?: @"" copy];
    [wasTitle release];
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
- (void)setItemArray:(NSArray *)items
{
    [self removeAllItems];
    for (NSMenuItem *item in items)
        [self addItem:item];
}
- (NSArray *)items { return [self itemArray]; }
- (void)setItems:(NSArray *)items { [self setItemArray:items]; }
- (void)setSubmenu:(NSMenu *)menu forItem:(NSMenuItem *)item { [item setSubmenu:menu]; }

/* With autoenablesItems (the default), each item is enabled when something
 * in the responder chain takes its action and agrees in its validation,
 * as on a Mac; an item with a submenu stays enabled. */
- (void)update
{
    if (!_autoenables)
        return;
    for (NSMenuItem *item in [[_items copy] autorelease]) {
        if ([item isSeparatorItem] || [item hasSubmenu])
            continue;
        SEL action = [item action];
        id target = action ? [NSApp targetForAction:action to:[item target] from:item] : nil;
        [item setEnabled:target && AValidateItem(target, item)];
    }
}

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
        if ((!_autoenables && ![item isEnabled]) || [item isHidden] || !matches(item, event))
            continue;
        SEL action = [item action];
        if (!action)
            return NO;
        if (_autoenables) {
            id target = [NSApp targetForAction:action to:[item target] from:item];
            if (!target || !AValidateItem(target, item))
                return NO;
        }
        ASendMenuItemAction(item);
        return YES;
    }
    return NO;
}
@end

/* ---- NSApplication --------------------------------------------------------------------- */

/* the About panel's content, laid out from the top */
@interface AAboutView : NSView
@end
@implementation AAboutView
- (BOOL)isFlipped { return YES; }
@end

@interface NSApplication (AOpenRequests)
- (BOOL)_openFiles:(NSArray *)files;
- (void)_openUntitledIfWanted;
- (void)_openRequested:(NSArray *)files;
@end

@implementation NSApplication {
    id _delegate;
    NSMenu *_mainMenu;
    NSMenu *_windowsMenu, *_servicesMenu, *_helpMenu;
    id _servicesProvider;
    BOOL _running, _launched, _active;
    NSEvent *_current;
    NSApplicationActivationPolicy _policy;
    id _icon;
    NSWindow *_modal;
    NSModalResponse _modalCode;
    BOOL _modalStopped, _waitingToTerminate;
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
        /* As on a Mac, an agent app (LSUIElement) has no Dock icon or menu
         * bar of its own, and one that is only a background program
         * (LSBackgroundOnly) none at all (freemac 1.224, Ferry 0.48.0). */
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        if ([info[@"LSBackgroundOnly"] respondsToSelector:@selector(boolValue)] && [info[@"LSBackgroundOnly"] boolValue])
            _policy = NSApplicationActivationPolicyProhibited;
        else if ([info[@"LSUIElement"] respondsToSelector:@selector(boolValue)] && [info[@"LSUIElement"] boolValue])
            _policy = NSApplicationActivationPolicyAccessory;
        else
            _policy = NSApplicationActivationPolicyRegular;
        /* light or dark, as freemac is (AppKitMore.m, freemac 1.245) */
        AAppearanceFollow();
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
    AMainMenuBarChanged();
}
- (NSMenu *)windowsMenu { return _windowsMenu; }
- (void)setWindowsMenu:(NSMenu *)m { _windowsMenu = m; }
/* The application menu, which older programs (wxWidgets among them) name
 * this way: on freemac it is the main menu's first item, so nothing to keep. */
- (void)setAppleMenu:(NSMenu *)m { (void)m; }
- (NSMenu *)servicesMenu { return _servicesMenu; }
- (void)setServicesMenu:(NSMenu *)m { _servicesMenu = m; }
/* The Services menu's providers and types: kept, but nothing offers services here. */
- (id)servicesProvider { return _servicesProvider; }
- (void)setServicesProvider:(id)p { _servicesProvider = p; }
- (void)registerServicesMenuSendTypes:(NSArray *)send returnTypes:(NSArray *)ret {}
- (NSMenu *)helpMenu { return _helpMenu; }
- (void)setHelpMenu:(NSMenu *)m { _helpMenu = m; }
- (NSArray *)windows { return AAllWindows(); }
- (NSWindow *)keyWindow { return AKeyWindow(); }
- (NSWindow *)mainWindow { return AMainWindow(); }
- (BOOL)isRunning { return _running; }
- (BOOL)isActive { return _active; }
- (NSEvent *)currentEvent { return _current; }
- (id)applicationIconImage { return _icon ?: [NSImage imageNamed:NSImageNameApplicationIcon]; }
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
    [self _post:NSApplicationWillBecomeActiveNotification selector:@selector(applicationWillBecomeActive:)];
    _active = YES;
    for (NSWindow *w in [[AAllWindows() copy] autorelease])
        [w _appDidBecomeActive];
    [self _post:NSApplicationDidBecomeActiveNotification selector:@selector(applicationDidBecomeActive:)];
}
- (void)activate { [self activateIgnoringOtherApps:YES]; }
- (void)deactivate
{
    if (!_active)
        return;
    [self _post:NSApplicationWillResignActiveNotification selector:@selector(applicationWillResignActive:)];
    _active = NO;
    for (NSWindow *w in [[AAllWindows() copy] autorelease])   /* panels that hide on deactivation */
        [w _appDidResignActive];
    [self _post:NSApplicationDidResignActiveNotification selector:@selector(applicationDidResignActive:)];
}
- (void)hide:(id)sender
{
    for (NSWindow *w in AAllWindows())
        if ([w isVisible] && [w canHide])
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
/* The standard About panel (freemac 1.231): the app's icon, its name,
 * its version and build, any credits and its copyright, centred in a small
 * titled panel, from the options given or else the bundle's Info.plist.
 * One panel is kept and brought back to the front. */
- (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary *)options
{
    static NSPanel *panel;
    if (panel) {
        [panel close];
        [panel release];
        panel = nil;
    }
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *name = options[@"ApplicationName"] ?: info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"]
        ?: [[NSProcessInfo processInfo] processName];
    NSString *shortVersion = options[@"ApplicationVersion"] ?: info[@"CFBundleShortVersionString"];
    NSString *build = options[@"Version"] ?: info[@"CFBundleVersion"];
    NSString *version = shortVersion ? [NSString stringWithFormat:@"Version %@", shortVersion] : nil;
    if (build && version && ![build isEqual:shortVersion])
        version = [version stringByAppendingFormat:@" (%@)", build];
    else if (build && !version)
        version = [NSString stringWithFormat:@"Version %@", build];
    id credits = options[@"Credits"];
    NSString *copyright = options[@"Copyright"] ?: info[@"NSHumanReadableCopyright"];
    NSImage *icon = options[@"ApplicationIcon"] ?: [self applicationIconImage];

    const CGFloat width = 280, inner = width - 40;
    NSView *v = [[[AAboutView alloc] initWithFrame:NSMakeRect(0, 0, width, 100)] autorelease];
    CGFloat y = 20;
    if (icon) {
        NSImageView *iv = [NSImageView imageViewWithImage:icon];
        [iv setImageScaling:NSImageScaleProportionallyUpOrDown];
        [iv setFrame:NSMakeRect((width - 64) / 2, y, 64, 64)];
        [v addSubview:iv];
        y += 64 + 12;
    }
    NSArray *rows = @[ @[ name ?: @"", [NSFont boldSystemFontOfSize:14] ],
                       @[ version ?: @"", [NSFont systemFontOfSize:11] ],
                       @[ credits ?: @"", [NSFont systemFontOfSize:11] ],
                       @[ copyright ?: @"", [NSFont systemFontOfSize:10] ] ];
    for (NSArray *row in rows) {
        id text = row[0];
        NSString *plain = [text isKindOfClass:[NSAttributedString class]] ? [text string] : text;
        if (![plain length])
            continue;
        NSFont *font = row[1];
        NSRect r = [plain boundingRectWithSize:NSMakeSize(inner - 4, 1e6) options:NSStringDrawingUsesLineFragmentOrigin
                                    attributes:@{NSFontAttributeName : font}];
        CGFloat h = ceil(r.size.height) + 2;
        NSTextField *f = [NSTextField wrappingLabelWithString:plain];
        [f setFont:font];
        [f setAlignment:NSTextAlignmentCenter];
        [f setSelectable:YES];
        if (font != rows[0][1])
            [f setTextColor:[NSColor secondaryLabelColor]];
        [f setFrame:NSMakeRect(20, y, inner, h)];
        [v addSubview:f];
        y += h + 6;
    }
    y += 14;
    [v setFrame:NSMakeRect(0, 0, width, y)];
    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, y)
                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                         backing:NSBackingStoreBuffered defer:YES];
    [panel setReleasedWhenClosed:NO];
    [panel setHidesOnDeactivate:NO];
    [panel setTitle:@""];
    [panel setContentView:v];
    [panel center];
    [self activateIgnoringOtherApps:YES];
    [panel makeKeyAndOrderFront:nil];
}
- (NSInteger)requestUserAttention:(NSInteger)type { return ADockRequestAttention(type); }

/* ---- the app's icon in the dock ---------------------------------------------------------
 * A Wayland dock finds an app's icon through a desktop entry named after
 * the app's id (the bundle identifier here), so an app bundle with an icon
 * gets a hidden one in the user's own data folder, as other compatibility
 * layers do, with the icon beside it; FERRY_NO_DESKTOP_ENTRY=1 turns that
 * off. X11 window managers take the icon from the windows themselves. */

static NSData *icon_png(NSImage *icon, CGFloat side)
{
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)side
        pixelsHigh:(NSInteger)side bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [icon drawInRect:NSMakeRect(0, 0, side, side) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
            fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static BOOL write_if_changed(NSString *path, NSData *data)
{
    if ([[NSData dataWithContentsOfFile:path] isEqualToData:data])
        return YES;
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    return [data writeToFile:path atomically:YES];
}

/* The desktop entry format quotes arguments with double quotes, escaping
 * ", `, $ and \ inside them with a backslash, itself escaped once more
 * because the whole value is an escaped string; % is doubled. */
static NSString *desktop_quoted(NSString *s)
{
    NSMutableString *q = [NSMutableString stringWithString:@"\""];
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '"' || c == '`' || c == '$' || c == '\\')
            [q appendString:@"\\\\"];
        if (c == '\n')
            continue;
        if (c == '%')
            [q appendString:@"%"]; /* a field code otherwise */
        [q appendFormat:@"%C", c];
    }
    [q appendString:@"\""];
    return q;
}

static void register_app_icon(void)
{
    NSBundle *main = [NSBundle mainBundle];
    NSString *ident = [main bundleIdentifier];
    NSString *file = [main objectForInfoDictionaryKey:@"CFBundleIconFile"];
    if (![ident length] || ![file isKindOfClass:[NSString class]] || ![file length])
        return;
    NSImage *icon = [NSApp applicationIconImage];
    if (![icon isValid])
        return;
    NSData *png = icon_png(icon, 256);
    if (!png)
        return;
    GdkPixbufLoader *loader = gdk_pixbuf_loader_new();
    if (loader) {
        gdk_pixbuf_loader_write(loader, [png bytes], [png length], NULL);
        gdk_pixbuf_loader_close(loader, NULL);
        GdkPixbuf *pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
        if (pixbuf)
            gtk_window_set_default_icon(pixbuf);
        g_object_unref(loader);
    }
    const char *off = getenv("FERRY_NO_DESKTOP_ENTRY");
    if (off && *off && strcmp(off, "0"))
        return;
    const char *data = getenv("XDG_DATA_HOME"), *home = getenv("HOME");
    NSString *share = data && *data ? [NSString stringWithUTF8String:data]
                      : home && *home ? [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@".local/share"]
                                      : nil;
    if (!share)
        return;
    NSString *iconPath = [share stringByAppendingFormat:@"/icons/hicolor/256x256/apps/%@.png", ident];
    if (!write_if_changed(iconPath, png))
        return;
    NSString *name = [main objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                         ?: [main objectForInfoDictionaryKey:@"CFBundleName"]
                         ?: [[[main bundlePath] lastPathComponent] stringByDeletingPathExtension];
    NSString *entry = [NSString stringWithFormat:@"[Desktop Entry]\n"
                                                  "Type=Application\n"
                                                  "Name=%@\n"
                                                  "Comment=A Mac app, run by Ferry\n"
                                                  "Exec=ferry %@\n"
                                                  "Icon=%@\n"
                                                  "StartupWMClass=%@\n"
                                                  "NoDisplay=true\n"
                                                  "X-Ferry-Bundle=%@\n",
                                                  [[name componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "],
                                                  desktop_quoted([main executablePath]), ident, ident,
                                                  [main bundlePath]];
    write_if_changed([share stringByAppendingFormat:@"/applications/%@.desktop", ident],
                     [entry dataUsingEncoding:NSUTF8StringEncoding]);
}

/* ---- opening files in the copy that's already running ------------------------------- */

/* On a Mac, opening a document (a double-click in the Finder, a file dropped
 * on the app's Dock icon) when its app is already open gives the document to
 * that copy of the app, and opening the app again only brings it to the
 * front. Here the desktop opens a Mac app through freemac-mac-app, which
 * first asks the running copy (freemac 1.NEXT): each app with a bundle
 * identifier listens on $XDG_RUNTIME_DIR/ferry/<identifier>.open, a Unix
 * socket, for the absolute paths of the files to open, one to a line, and
 * answers "ok". No paths means "come to the front". A copy started by hand
 * while another one is listening leaves that one be, as a second copy
 * started from a Mac's Terminal would. */

static char open_socket[sizeof(((struct sockaddr_un *)0)->sun_path)];
static pid_t open_socket_owner;

static void forget_open_socket(void)
{
    if (open_socket[0] && getpid() == open_socket_owner)
        unlink(open_socket);
}

static void open_request(int listener, void *ctx)
{
    int fd = accept(listener, NULL, NULL);
    if (fd < 0)
        return;
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
    struct timeval wait = {2, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof wait);
    NSMutableData *got = [NSMutableData data];
    char buf[4096];
    ssize_t n;
    while ([got length] < 1 << 20 && (n = read(fd, buf, sizeof buf)) > 0)
        [got appendBytes:buf length:n];
    (void)!write(fd, "ok\n", 3);
    close(fd);
    NSString *text = [[[NSString alloc] initWithData:got encoding:NSUTF8StringEncoding] autorelease];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *path = [line stringByStandardizingPath];
        if ([path isAbsolutePath] && [[NSFileManager defaultManager] fileExistsAtPath:path])
            [files addObject:path];
    }
    @autoreleasepool {
        @try {
            [NSApp _openRequested:files];
        } @catch (NSException *x) {
            [NSApp reportException:x];
        }
    }
}

static void listen_for_open_requests(void)
{
    NSString *ident = [[NSBundle mainBundle] bundleIdentifier];
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    if (![ident length] || !runtime || *runtime != '/')
        return;
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < [ident length]; i++) {
        unichar c = [ident characterAtIndex:i];
        BOOL plain = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' ||
                     c == '_' || c == '-';
        unichar out = plain ? c : (unichar)'-';
        [name appendFormat:@"%C", out];
    }
    char dir[sizeof open_socket];
    if (snprintf(dir, sizeof dir, "%s/ferry", runtime) >= (int)sizeof dir)
        return;
    mkdir(dir, 0700);
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_len = sizeof addr;
    addr.sun_family = AF_UNIX;
    if (snprintf(addr.sun_path, sizeof addr.sun_path, "%s/%s.open", dir, [name UTF8String]) >=
        (int)sizeof addr.sun_path)
        return;
    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe < 0)
        return;
    BOOL taken = connect(probe, (struct sockaddr *)&addr, sizeof addr) == 0;   /* another copy listens */
    close(probe);
    if (taken)
        return;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return;
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    unlink(addr.sun_path);
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(fd, 8) != 0) {
        close(fd);
        return;
    }
    memcpy(open_socket, addr.sun_path, sizeof open_socket);
    open_socket_owner = getpid();
    atexit(forget_open_socket);
    FerryRunLoopAddDescriptor(fd, open_request, NULL);
}

- (void)finishLaunching
{
    if (_launched)
        return;
    _launched = YES;
    if (ADisplayAvailable())
        register_app_icon();
    [self _post:NSApplicationWillFinishLaunchingNotification selector:@selector(applicationWillFinishLaunching:)];
    /* An app that declares document types gets a document controller (its
     * own subclass, if one was made already, for instance in the nib). */
    id types = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"];
    if ([types isKindOfClass:[NSArray class]] && [types count])
        [NSDocumentController sharedDocumentController];
    /* An agent app isn't made active by starting, as on a Mac: the app in
     * front stays in front (freemac 1.224, Ferry 0.48.0). */
    if (_policy == NSApplicationActivationPolicyRegular)
        [self activateIgnoringOtherApps:YES];
    [self _openLaunchFiles];
    if (_policy == NSApplicationActivationPolicyRegular)
        listen_for_open_requests();
    /* No windows are restored, so restoring them is done at once
     * (freemac 1.225, Ferry 0.49.0): MacPass waits for this and for the
     * launch before it shows its welcome window. */
    [[NSNotificationCenter defaultCenter] postNotificationName:NSApplicationDidFinishRestoringWindowsNotification
                                                        object:self];
    [self _post:NSApplicationDidFinishLaunchingNotification selector:@selector(applicationDidFinishLaunching:)];
    ADockLaunched();
}

/* The files named on the command line (after the program's own options,
 * "-Key value" pairs that go to the user defaults), then, when none were
 * opened, an untitled document if the app wants one. */
- (void)_openLaunchFiles
{
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    NSMutableArray *files = [NSMutableArray array];
    for (NSUInteger i = 1; i < [args count]; i++) {
        NSString *a = args[i];
        if ([a hasPrefix:@"-psn_"])
            continue;
        if ([a hasPrefix:@"-"] && [a length] > 1) {
            i++;   /* its value */
            continue;
        }
        NSString *path = [a stringByStandardizingPath];
        if (![path isAbsolutePath])
            path = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:path];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            [files addObject:[path stringByStandardizingPath]];
    }
    if ([self _openFiles:files])
        return;
    [self _openUntitledIfWanted];
}

/* Files the app is asked to open, given to its delegate as a Mac's AppKit
 * gives them (as URLs, as paths, one by one), else to its document
 * controller. NO when nothing took them. */
- (BOOL)_openFiles:(NSArray *)files
{
    NSDocumentController *documents = [NSDocumentController _existingSharedController];
    BOOL opened = NO;
    if ([files count]) {
        opened = YES;
        if ([_delegate respondsToSelector:@selector(application:openURLs:)]) {
            NSMutableArray *urls = [NSMutableArray array];
            for (NSString *f in files)
                [urls addObject:[NSURL fileURLWithPath:f]];
            [_delegate application:self openURLs:urls];
        } else if ([_delegate respondsToSelector:@selector(application:openFiles:)]) {
            [_delegate application:self openFiles:files];
        } else if ([_delegate respondsToSelector:@selector(application:openFile:)]) {
            for (NSString *f in files)
                [_delegate application:self openFile:f];
        } else if (documents) {
            for (NSString *f in files)
                [documents openDocumentWithContentsOfURL:[NSURL fileURLWithPath:f] display:YES
                                       completionHandler:^(NSDocument *d, BOOL already, NSError *error) {
                                           if (!d && error)
                                               [documents presentError:error];
                                       }];
        } else {
            opened = NO;
        }
    }
    return opened;
}

- (void)_openUntitledIfWanted
{
    NSDocumentController *documents = [NSDocumentController _existingSharedController];
    /* Only a document-based app, one with a type it edits and a document
     * class for it, opens an untitled document by itself. An app that
     * keeps the shared controller only for its recent documents, as
     * VLC does, opens nothing (and shows no error). */
    BOOL untitled = documents != nil && [documents defaultType] != nil;
    if ([_delegate respondsToSelector:@selector(applicationShouldOpenUntitledFile:)])
        untitled = [_delegate applicationShouldOpenUntitledFile:self];
    if (!untitled)
        return;
    if ([_delegate respondsToSelector:@selector(applicationOpenUntitledFile:)]) {
        [_delegate applicationOpenUntitledFile:self];
    } else if (documents) {
        NSError *error = nil;
        if (![documents openUntitledDocumentAndDisplay:YES error:&error] && error)
            [documents presentError:error];
    }
}

/* What the desktop asked of the running copy (see open_request): files to
 * open, or, with none, to come back to the front, which a Mac gives the
 * delegate as a "reopen" (it may say no); then a hidden or minimized app
 * shows its windows again, and one with no windows at all may open an
 * untitled document. */
- (void)_openRequested:(NSArray *)files
{
    BOOL visible = NO;
    for (NSWindow *w in AAllWindows())
        if ([w isVisible] && ![w isMiniaturized])
            visible = YES;
    if ([files count]) {
        [self _openFiles:files];
    } else {
        BOOL reopen = YES;
        if ([_delegate respondsToSelector:@selector(applicationShouldHandleReopen:hasVisibleWindows:)])
            reopen = [_delegate applicationShouldHandleReopen:self hasVisibleWindows:visible];
        if (reopen && !visible) {
            BOOL any = NO;
            for (NSWindow *w in [[AAllWindows() copy] autorelease])
                if ([w isMiniaturized]) {
                    [w deminiaturize:nil];
                    any = YES;
                }
            if (!any)
                [self _openUntitledIfWanted];
        }
    }
    [self activateIgnoringOtherApps:YES];
    NSWindow *front = [self keyWindow] ?: [self mainWindow];
    if ([front isVisible])
        [front makeKeyAndOrderFront:nil];
}

- (void)run
{
    /* Running from before the launch is finished, so that a stop: the
     * delegate sends from applicationDidFinishLaunching: (wxWidgets does, to
     * return to its own event loop) ends this run, as on a Mac. */
    _running = YES;
    [self finishLaunching];
    while (_running) {
        @autoreleasepool {
            /* As on a Mac, an exception the app's code raises while handling
             * an event (or a timer) is reported, and the app carries on. */
            @try {
                NSEvent *e = [self nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture]
                                                  inMode:NSDefaultRunLoopMode dequeue:YES];
                if (e)
                    [self sendEvent:e];
            } @catch (NSException *x) {
                [self reportException:x];
            }
        }
    }
}

- (void)reportException:(NSException *)x
{
    fflush(stdout);
    fprintf(stderr, "ferry: the app raised %s (%s) and didn't catch it; carrying on, as a Mac app does\n",
            [[x name] UTF8String], [[x reason] UTF8String]);
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

/* Quitting: documents with unsaved changes are reviewed first, then the
 * delegate is asked; NSTerminateLater waits for
 * replyToApplicationShouldTerminate:. */
- (void)terminate:(id)sender
{
    if (_waitingToTerminate)
        return;
    NSDocumentController *documents = [NSDocumentController _existingSharedController];
    if ([documents hasEditedDocuments]) {
        [documents reviewUnsavedDocumentsWithAlertTitle:nil cancellable:YES delegate:self
                                   didReviewAllSelector:@selector(_documentController:didReviewAll:contextInfo:)
                                            contextInfo:NULL];
        return;
    }
    [self _askDelegateToTerminate];
}
- (void)_documentController:(NSDocumentController *)dc didReviewAll:(BOOL)all contextInfo:(void *)info
{
    if (all)
        [self _askDelegateToTerminate];
}
- (void)_askDelegateToTerminate
{
    if ([_delegate respondsToSelector:@selector(applicationShouldTerminate:)]) {
        NSApplicationTerminateReply r = [_delegate applicationShouldTerminate:self];
        if (r == NSTerminateCancel)
            return;
        if (r == NSTerminateLater) {
            _waitingToTerminate = YES;
            return;
        }
    }
    [self _terminateNow];
}
- (void)_terminateNow
{
    [self _post:NSApplicationWillTerminateNotification selector:@selector(applicationWillTerminate:)];
    [[NSUserDefaults standardUserDefaults] synchronize];
    fflush(stdout);
    exit(0);
}
- (void)replyToApplicationShouldTerminate:(BOOL)shouldTerminate
{
    if (!_waitingToTerminate)
        return;
    _waitingToTerminate = NO;
    if (shouldTerminate)
        [self _terminateNow];
}

/* ---- the old sheet calls: a modal delegate and a did-end selector ---- */
- (void)beginSheet:(NSWindow *)sheet modalForWindow:(NSWindow *)window modalDelegate:(id)delegate
    didEndSelector:(SEL)didEnd contextInfo:(void *)context
{
    [sheet _setLegacySheet:YES];
    [window beginSheet:sheet completionHandler:^(NSModalResponse code) {
        if (delegate && didEnd)
            ((void (*)(id, SEL, id, NSInteger, void *))objc_msgSend)(delegate, didEnd, sheet, code, context);
    }];
}
- (void)endSheet:(NSWindow *)sheet { [[sheet sheetParent] endSheet:sheet]; }
- (void)endSheet:(NSWindow *)sheet returnCode:(NSInteger)code { [[sheet sheetParent] endSheet:sheet returnCode:code]; }

/* Errors: the delegate may change one before it's shown. */
- (BOOL)presentError:(NSError *)error
{
    if ([_delegate respondsToSelector:@selector(application:willPresentError:)])
        error = [_delegate application:self willPresentError:error];
    return [[NSAlert alertWithError:error] runModal] == NSAlertFirstButtonReturn;
}
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
    didPresentSelector:(SEL)did contextInfo:(void *)context
{
    if ([_delegate respondsToSelector:@selector(application:willPresentError:)])
        error = [_delegate application:self willPresentError:error];
    NSAlert *alert = [NSAlert alertWithError:error];
    void (^done)(NSModalResponse) = ^(NSModalResponse r) {
        if (delegate && did)
            ((void (*)(id, SEL, BOOL, void *))objc_msgSend)(delegate, did, NO, context);
    };
    if (window)
        [alert beginSheetModalForWindow:window completionHandler:done];
    else
        done([alert runModal]);
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
        BOOL done = NO;
        /* each turn has a pool of its own: the loop can turn many times (timers, redraws) before an event */
        @autoreleasepool {
            AWindowsDisplayIfNeeded();
            GContextSyncAll();   /* bitmap contexts' drawing out to their memory (CGContext.m) */
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            if (now >= limit) {
                done = YES;
            } else {
                NSDate *until = [NSDate dateWithTimeIntervalSinceReferenceDate:limit];
                if (![[NSRunLoop currentRunLoop] runMode:mode ?: NSDefaultRunLoopMode beforeDate:until]) {
                    /* nothing could ever wake the loop; wait as a Mac would, in slices */
                    NSTimeInterval wait = fmin(limit - now, 0.05);
                    if (wait > 0)
                        usleep((useconds_t)(wait * 1e6));
                }
            }
        }
        if (done)
            return nil;
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
    /* Apple's documentation allows posting from any thread, and programs
     * wake their main loop this way (GLFW, in kitty, posts an empty
     * application-defined event when its other threads have work for it).
     * The queue belongs to the main thread, so the event is handed there,
     * which also wakes the main run loop out of its wait (freemac 1.268). */
    if (![NSThread isMainThread]) {
        [event retain];
        [[NSRunLoop mainRunLoop] performBlock:^{
          [self postEvent:event atStart:atStart];
          [event release];
        }];
        return;
    }
    if (!queue)
        queue = [[NSMutableArray alloc] init];
    if (atStart)
        [queue insertObject:event atIndex:0];
    else
        [queue addObject:event];
}

- (void)sendEvent:(NSEvent *)e
{
    if (!(e = ALocalMonitorsFilter(e)))
        return;
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
    AWindowsNeedUpdate();
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
        /* the window controller is in the chain already; then its document */
        id doc = [[w windowController] document];
        if ([doc respondsToSelector:action])
            return doc;
    }
    if ([self respondsToSelector:action])
        return self;
    if ([_delegate respondsToSelector:action])
        return _delegate;
    id documents = [NSDocumentController _existingSharedController];
    if ([documents respondsToSelector:action])
        return documents;
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

- (void)updateWindows
{
    AWindowsUpdate();
    AWindowsDisplayIfNeeded();
}
- (void)setWindowsNeedUpdate:(BOOL)flag
{
    if (flag)
        AWindowsNeedUpdate();
}

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
            @try {
                if (!w || w == window || (key && AKeyWindow() == window))
                    [self sendEvent:e];
            } @catch (NSException *x) {
                [self reportException:x];
            }
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

/* Modal sessions (freemac 1.221, Ferry 0.45.0): the modal loop above, a
 * turn at a time, for a program that does its own work between turns. A
 * session remembers the modal window it replaced. */
struct _NSModalSession {
    NSWindow *window, *outer;
    NSModalResponse code;
    BOOL stopped;
};
- (NSModalSession)beginModalSessionForWindow:(NSWindow *)window
{
    NSModalSession session = calloc(1, sizeof *session);
    session->window = [window retain];
    session->outer = _modal;
    _modal = window;
    _modalStopped = NO;
    _modalCode = NSModalResponseContinue;
    [window makeKeyAndOrderFront:nil];
    return session;
}
- (NSModalResponse)runModalSession:(NSModalSession)session
{
    if (!session)
        return NSModalResponseAbort;
    if (session->stopped)
        return session->code;
    NSWindow *window = session->window;
    for (;;) {
        @autoreleasepool {
            NSEvent *e = [self nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantPast]
                                              inMode:NSModalPanelRunLoopMode dequeue:YES];
            if (!e)
                break;
            NSWindow *w = [e window];
            BOOL key = [e type] == NSEventTypeKeyDown || [e type] == NSEventTypeKeyUp;
            @try {
                if (!w || w == window || (key && AKeyWindow() == window))
                    [self sendEvent:e];
            } @catch (NSException *x) {
                [self reportException:x];
            }
        }
        if (_modalStopped)
            break;
    }
    if (_modalStopped) {
        session->stopped = YES;
        session->code = _modalCode;
        _modalStopped = NO;
        return session->code;
    }
    return NSModalResponseContinue;
}
- (void)endModalSession:(NSModalSession)session
{
    if (!session)
        return;
    if (_modal == session->window)
        _modal = session->outer;
    _modalStopped = NO;
    [session->window release];
    free(session);
}
@end

/* Makes the application object (the Info.plist's NSPrincipalClass, else
 * NSApplication), loads the main nib or main storyboard, and runs it. */
int NSApplicationMain(int argc, const char *argv[])
{
    @autoreleasepool {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        Class cls = NSClassFromString(info[@"NSPrincipalClass"]) ?: [NSApplication class];
        [cls sharedApplication];
        NSString *nib = info[@"NSMainNibFile"];
        if ([nib isKindOfClass:[NSString class]] && [nib length]) {
            if (![NSBundle loadNibNamed:nib owner:NSApp])
                fprintf(stderr, "ferry: the app's main nib, %s, couldn't be loaded\n", [nib UTF8String]);
        } else if ([info[@"NSMainStoryboardFile"] isKindOfClass:[NSString class]]) {
            ALoadMainStoryboard();
        }
    }
    [NSApp run];
    return 0;
}

/* Full keyboard access: a Mac keeps it as bit 2 of the "AppleKeyboardUIMode"
 * default, and with it on, Tab reaches buttons, pop-ups and segmented
 * controls as well as text fields and lists. */
@implementation NSApplication (FerryKeyboardAccess)
- (BOOL)isFullKeyboardAccessEnabled
{
    return ([[NSUserDefaults standardUserDefaults] integerForKey:@"AppleKeyboardUIMode"] & 2) != 0;
}
@end

/* How many times NSBeep has been called: a Ferry addition, for tests that
 * check a refused edit beeps (there is no sound with no display). */
@implementation NSApplication (FerryBeeps)
- (NSUInteger)_ferryBeepCount { return beeps; }
@end
