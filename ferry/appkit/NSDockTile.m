/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: the app's tile in the Dock (NSDockTile, NSApp's dockTile,
 * requestUserAttention: and cancelUserAttentionRequest:, and the
 * delegate's applicationDockMenu:), written from Apple's public
 * documentation.
 *
 * A Mac draws the Dock itself. Here the app tells the desktop's dock what to
 * show with the com.canonical.Unity.LauncherEntry Update signal, which
 * freemac's Dock reads (shell/freemac_shell/launcher_badge.py) as many Linux
 * docks do: Update(app_uri, properties), where app_uri names the app's
 * desktop file ("application://ID.desktop") and the properties hold
 * "count" and "count-visible" for the badge, "urgent" for an attention
 * request (the icon hops until the app is used) and "quicklist", the object
 * path of a dbusmenu menu, for the Dock menu. The signal goes out for each
 * desktop file the app may be known by (see ANotifyDesktopIDs), and again
 * when freemac's Dock says it started (org.freemac.Dock Started), since it
 * forgets badges sent before it ran.
 *
 * The LauncherEntry badge is a number: a badge label that is a plain
 * number goes as "count". Any other label ("New", "!", "99+") goes as
 * "x-freemac-badge-label", which freemac's Dock shows in the badge in place
 * of the number, with "count" 1 and "count-visible" true, so other docks
 * still show that there is a badge; when it goes, an empty label is sent
 * once to take it away. A label of "0" shows no badge. A tile's
 * contentView is drawn by display, and the picture is given to GTK as the
 * windows' icon, which X11 window managers show; no dock takes a picture
 * from LauncherEntry.
 */
#import "ANotify.h"

static const char *const ENTRY_IFACE = "com.canonical.Unity.LauncherEntry";
static const char *const ENTRY_PATH = "/com/canonical/unity/launcherentry/ferry";
static const char *const DOCK_MENU_PATH = "/com/canonical/unity/launcherentry/ferry/menu";

static NSDockTile *app_tile;
static BOOL urgent, have_menu, sent, watching;
static BOOL label_sent;                 /* the dock was last sent a text label */
static NSInteger attention;             /* the standing attention request, 0 for none */
static id menu_server;                  /* the Dock menu, served over dbusmenu (NSStatusBar.m) */

@interface NSDockTile (FerryPrivate)
- (instancetype)_initWithOwner:(id)owner;
- (NSInteger)_count;
- (NSString *)_textLabel;
@end

static void send_update(void);

static void dock_started(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                         const char *signal, GVariant *params, void *data)
{
    @autoreleasepool {
        if (sent)
            send_update();
    }
}

static void entry(NSMutableArray *pairs, const char *key, GVariant *value)
{
    [pairs addObject:[NSValue valueWithPointer:g_variant_new_dict_entry(g_variant_new_string(key),
                                                                        g_variant_new_variant(value))]];
}

static void send_update(void)
{
    GDBusConnection *bus = ANotifyBus();
    if (!bus)
        return;
    if (!watching) {
        watching = YES;
        g_dbus_connection_signal_subscribe(bus, NULL, "org.freemac.Dock", "Started", "/org/freemac/Dock", NULL, 0,
                                           dock_started, NULL, NULL);
    }
    sent = YES;
    NSString *label = [app_tile _textLabel];
    NSInteger count = label ? 1 : [app_tile _count];
    BOOL clear_label = !label && label_sent;
    label_sent = label != nil;
    for (NSString *ident in ANotifyDesktopIDs()) {
        NSMutableArray *pairs = [NSMutableArray array];
        entry(pairs, "count", g_variant_new_int64(count));
        entry(pairs, "count-visible", g_variant_new_boolean(count > 0));
        entry(pairs, "urgent", g_variant_new_boolean(urgent));
        if (have_menu)
            entry(pairs, "quicklist", g_variant_new_string(DOCK_MENU_PATH));
        if (label || clear_label)
            entry(pairs, "x-freemac-badge-label", g_variant_new_string(label ? [label UTF8String] : ""));
        size_t n = [pairs count];
        GVariant **items = calloc(n, sizeof *items);
        for (size_t i = 0; i < n; i++)
            items[i] = [pairs[i] pointerValue];
        GVariant *args[2] = {
            g_variant_new_string([[@"application://" stringByAppendingString:ident] UTF8String]),
            g_variant_new_array("{sv}", items, n),
        };
        free(items);
        g_dbus_connection_emit_signal(bus, NULL, ENTRY_PATH, ENTRY_IFACE, "Update", g_variant_new_tuple(args, 2),
                                      NULL);
    }
}

static NSDockTile *the_app_tile(void)
{
    if (!app_tile)
        app_tile = [[NSDockTile alloc] _initWithOwner:NSApp];
    return app_tile;
}

void ADockSetBadge(NSString *label)
{
    [the_app_tile() setBadgeLabel:label];
}

/* The app finished launching: a delegate with a Dock menu gets it served,
 * and asked for again each time the dock opens it. */
void ADockLaunched(void)
{
    id delegate = [NSApp delegate];
    if (have_menu || ![delegate respondsToSelector:@selector(applicationDockMenu:)] || !ANotifyBus())
        return;
    have_menu = YES;
    menu_server = [AMenuServe(DOCK_MENU_PATH, ^NSMenu *(void) {
        id d = [NSApp delegate];
        if (![d respondsToSelector:@selector(applicationDockMenu:)])
            return nil;
        return ((NSMenu * (*)(id, SEL, id)) objc_msgSend)(d, @selector(applicationDockMenu:), NSApp);
    }) retain];
    send_update();
}

static void set_urgent(BOOL on)
{
    if (urgent == on)
        return;
    urgent = on;
    send_update();
}

@interface FDockAttention : NSObject
@end
@implementation FDockAttention
+ (void)appBecameActive:(NSNotification *)n
{
    attention = 0;
    set_urgent(NO);
}
+ (void)informationalEnded:(NSTimer *)timer
{
    if (attention == [[timer userInfo] integerValue]) {
        attention = 0;
        set_urgent(NO);
    }
}
@end

/* As on a Mac, an app that is already active gets no attention; an
 * informational request hops the icon for a second, a critical one until
 * the app becomes active or cancels it. */
NSInteger ADockRequestAttention(NSInteger type)
{
    if ([NSApp isActive])
        return 0;
    static NSInteger last;
    static BOOL observing;
    if (!observing) {
        observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver:[FDockAttention class]
                                                 selector:@selector(appBecameActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    attention = ++last;
    set_urgent(YES);
    if (type == NSInformationalRequest) {
        NSTimer *t = [NSTimer timerWithTimeInterval:1 target:[FDockAttention class]
                                           selector:@selector(informationalEnded:) userInfo:@(attention)
                                            repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    }
    return attention;
}

@implementation NSDockTile {
    NSView *_contentView;
    NSString *_badgeLabel;
    BOOL _showsApplicationBadge;
    id _owner;
    NSBitmapImageRep *_picture;
}

- (instancetype)_initWithOwner:(id)owner
{
    if ((self = [super init])) {
        _owner = owner;
        _showsApplicationBadge = YES;
    }
    return self;
}

- (void)dealloc
{
    [_contentView release];
    [_badgeLabel release];
    [_picture release];
    [super dealloc];
}

- (NSSize)size { return NSMakeSize(128, 128); }
- (id)owner { return _owner; }
- (NSView *)contentView { return _contentView; }
- (void)setContentView:(NSView *)view
{
    [view retain];
    [_contentView release];
    _contentView = view;
}
- (NSString *)badgeLabel { return _badgeLabel; }
- (void)setBadgeLabel:(NSString *)label
{
    if (label == _badgeLabel || [label isEqualToString:_badgeLabel])
        return;
    [_badgeLabel release];
    _badgeLabel = [label length] ? [label copy] : nil;
    if (self == app_tile)
        send_update();
}
- (BOOL)showsApplicationBadge { return _showsApplicationBadge; }
- (void)setShowsApplicationBadge:(BOOL)shows
{
    if (shows == _showsApplicationBadge)
        return;
    _showsApplicationBadge = shows;
    if (self == app_tile && _badgeLabel)
        send_update();
}

/* Whether the label is a plain number: 1 to 18 ASCII digits. */
- (BOOL)_labelIsNumber
{
    NSUInteger n = [_badgeLabel length];
    if (!n || n > 18)
        return NO;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [_badgeLabel characterAtIndex:i];
        if (c < '0' || c > '9')
            return NO;
    }
    return YES;
}

/* The number the dock can show: the label when it is a plain number. */
- (NSInteger)_count
{
    if (!_showsApplicationBadge || ![self _labelIsNumber])
        return 0;
    return [_badgeLabel integerValue];
}

/* The label as words, for a label that isn't a plain number; nil otherwise. */
- (NSString *)_textLabel
{
    if (!_showsApplicationBadge || ![_badgeLabel length] || [self _labelIsNumber])
        return nil;
    NSString *trimmed = [_badgeLabel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed length] ? trimmed : nil;
}

/* The content view drawn as the tile, at the tile's size; the picture
 * becomes the windows' icon. */
- (void)display
{
    if (!_contentView)
        return;
    @autoreleasepool {
        NSView *v = _contentView;
        if (NSIsEmptyRect([v frame]))
            [v setFrame:NSMakeRect(0, 0, 128, 128)];
        NSRect bounds = [v bounds];
        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:bounds];
        if (!rep)
            return;
        [v cacheDisplayInRect:bounds toBitmapImageRep:rep];
        [_picture release];
        _picture = [rep retain];
        if (!getenv("WAYLAND_DISPLAY") && !getenv("DISPLAY"))
            return;
        if (!ADisplayAvailable())
            return;
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        GdkPixbufLoader *loader = png ? gdk_pixbuf_loader_new() : NULL;
        if (!loader)
            return;
        gdk_pixbuf_loader_write(loader, [png bytes], [png length], NULL);
        gdk_pixbuf_loader_close(loader, NULL);
        GdkPixbuf *pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
        if (pixbuf)
            gtk_window_set_default_icon(pixbuf);
        g_object_unref(loader);
    }
}
@end

@implementation NSApplication (NSDockTile)
- (NSDockTile *)dockTile { return the_app_tile(); }
- (void)cancelUserAttentionRequest:(NSInteger)request
{
    if (!request || request != attention)
        return;
    attention = 0;
    set_urgent(NO);
}
@end
