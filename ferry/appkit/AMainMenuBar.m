/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: a Mac app's main menu (NSApp.mainMenu) in the desktop's
 * menu bar (freemac 1.244, Ferry 0.67.0). Original freemac code.
 *
 * On a Mac the system draws the front app's main menu across the top of the
 * screen. freemac's menu bar, Topline, shows the menus GTK apps publish on
 * the session bus as GIO menu models (org.gtk.Menus, with their actions as
 * org.gtk.Actions), found through the compositor: each window tells it where
 * they are (gtk_shell1's set_dbus_properties, which GDK sends). Ferry does
 * the same for every window of a Mac app:
 *
 *   /org/ferry/menus/appmenu   the application menu (About, Settings, Check
 *                              for Updates...), without Services, Hide, Hide
 *                              Others, Show All and Quit, which Topline adds
 *                              to every app's menu itself
 *   /org/ferry/menus/menubar   File, Edit, View... Help
 *   /org/ferry                 the actions ("app.N" for each item, and
 *                              "app.quit"), which Topline activates
 *
 * A separator starts a new section. An item's key equivalent is shown with
 * it (Topline draws it the Mac way); the key itself still reaches the app's
 * windows as before, so nothing is done twice. Items Topline already has in
 * its own menus (Minimize, Zoom, Bring All to Front and the window list in
 * Window, Emoji & Symbols and Start Dictation in Edit) are left out.
 *
 * Mac menus are checked as they open (validateMenuItem:, and the delegate's
 * menuNeedsUpdate:). Topline opens them itself, so the checks are made here
 * every half second while the app is in front, and when it comes to the
 * front; what changed is sent on (an item turning on or off, a tick coming
 * or going). A change in the menus themselves (an item added, renamed or
 * hidden) sends them again.
 *
 * Without a session bus, or outside a Wayland session, nothing is shown and
 * the menus work as before: their key equivalents still do.
 */
#import "AInternal.h"

static const char *const APP_PATH = "/org/ferry";
static const char *const APP_MENU_PATH = "/org/ferry/menus/appmenu";
static const char *const BAR_PATH = "/org/ferry/menus/menubar";

static int state;                   /* 0 not tried, 1 exported, -1 none */
static GDBusConnection *bus;
static GMenu *app_menu, *bar_menu;
static GSimpleActionGroup *actions;
static NSMutableArray *items;       /* the NSMenuItem behind app.N, at N */
static NSMutableArray *enabled;     /* NSNumber: what app.N was last sent as */
static NSUInteger action_count;
static NSString *shape;             /* the menus as last sent, to see when they change */
static BOOL was_active;
static id ticker;

/* ---- what goes in --------------------------------------------------------------------- */

/* Items Topline has in its own app, Window and Edit menus. */
static BOOL topline_has(NSMenuItem *item, BOOL app_menu_item)
{
    SEL a = [item action];
    if (app_menu_item) {
        if (a == @selector(hide:) || a == @selector(hideOtherApplications:) ||
            a == @selector(unhideAllApplications:) || a == @selector(terminate:))
            return YES;
        NSMenu *sub = [item submenu];
        if (sub && (sub == [NSApp servicesMenu] || [[item title] isEqualToString:@"Services"]))
            return YES;
    }
    return a == @selector(performMiniaturize:) || a == @selector(miniaturize:) ||
           a == @selector(miniaturizeAll:) || a == @selector(performZoom:) || a == @selector(zoom:) ||
           a == @selector(arrangeInFront:) || a == @selector(makeKeyAndOrderFront:) ||
           a == @selector(selectNextTab:) || a == @selector(selectPreviousTab:) ||
           a == @selector(mergeAllWindows:) || a == @selector(moveTabToNewWindow:) ||
           a == @selector(toggleTabBar:) || a == @selector(toggleTabOverview:) ||
           a == @selector(orderFrontCharacterPalette:) || a == @selector(startDictation:);
}

static BOOL shown(NSMenuItem *item, BOOL app_menu_item)
{
    return ![item isHidden] && ![item view] && !topline_has(item, app_menu_item);
}

/* GTK reads an underscore in a label as the key that picks it. */
static NSString *label(NSString *title)
{
    return [title ?: @"" stringByReplacingOccurrencesOfString:@"_" withString:@"__"];
}

/* The key equivalent as a GTK accelerator: Command is pressed as Control
 * in freemac (Strata turns ⌘ into it), which Topline shows as ⌘. NULL for
 * none, or one Topline can't show. */
NSString *AMenuAccelerator(NSString *key, NSEventModifierFlags mask)
{
    if (![key length] || !(mask & NSEventModifierFlagCommand) || (mask & NSEventModifierFlagControl))
        return nil;
    unichar k = [key characterAtIndex:0];
    BOOL shift = (mask & NSEventModifierFlagShift) != 0;
    NSString *name = nil;
    static const struct { unichar c; const char *name; } named[] = {
        {',', "comma"},       {'.', "period"},        {'/', "slash"},      {';', "semicolon"},
        {'\'', "apostrophe"}, {'[', "bracketleft"},   {']', "bracketright"}, {'\\', "backslash"},
        {'-', "minus"},       {'=', "equal"},         {'`', "grave"},      {'+', "plus"},
        {'?', "question"},    {'<', "less"},          {'>', "greater"},    {':', "colon"},
        {'{', "braceleft"},   {'}', "braceright"},    {'|', "bar"},        {'!', "exclam"},
        {'@', "at"},          {'#', "numbersign"},    {'$', "dollar"},     {'%', "percent"},
        {'^', "asciicircum"}, {'&', "ampersand"},     {'*', "asterisk"},   {'(', "parenleft"},
        {')', "parenright"},  {'"', "quotedbl"},      {'~', "asciitilde"}, {'_', "underscore"},
        {' ', "space"},       {'\r', "Return"},       {3, "KP_Enter"},     {'\t', "Tab"},
        {27, "Escape"},       {8, "BackSpace"},       {127, "BackSpace"},  {0xF728, "Delete"},
        {0xF700, "Up"},       {0xF701, "Down"},       {0xF702, "Left"},    {0xF703, "Right"},
        {0xF729, "Home"},     {0xF72B, "End"},        {0xF72C, "Page_Up"}, {0xF72D, "Page_Down"},
    };
    if (k < 128 && isalnum(k)) {
        if (isupper(k))
            shift = YES;
        name = [NSString stringWithFormat:@"%c", (char)tolower(k)];
    } else if (k >= 0xF704 && k <= 0xF70F) {
        name = [NSString stringWithFormat:@"F%d", k - 0xF704 + 1];
    } else {
        for (size_t i = 0; i < sizeof named / sizeof named[0]; i++)
            if (named[i].c == k) {
                name = @(named[i].name);
                break;
            }
    }
    if (!name)
        return nil;
    return [NSString stringWithFormat:@"%@%@<Control>%@", shift ? @"<Shift>" : @"",
                                      (mask & NSEventModifierFlagOption) ? @"<Alt>" : @"", name];
}

/* The menus' shape: everything that, changed, means sending them again. */
static void describe(NSMenu *menu, BOOL app_menu_item, NSMutableString *out)
{
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item isSeparatorItem]) {
            [out appendString:@"|"];
            continue;
        }
        if (!shown(item, app_menu_item))
            continue;
        [out appendFormat:@"<%@\x1f%@\x1f%lu\x1f%d", [item title], [item keyEquivalent],
                          (unsigned long)[item keyEquivalentModifierMask], [item state] != NSControlStateValueOff];
        if ([item submenu])
            describe([item submenu], NO, out);
        [out appendString:@">"];
    }
}

static NSMenuItem *app_menu_item(NSMenu *main)
{
    NSMenuItem *first = [main numberOfItems] ? [main itemAtIndex:0] : nil;
    return [first submenu] ? first : nil;
}

/* ---- building the models ---------------------------------------------------------------- */

static void activated(GSimpleAction *action, GVariant *parameter, void *data);

static void quit_activated(GSimpleAction *action, GVariant *parameter, void *data)
{
    @autoreleasepool {
        [NSApp terminate:nil];
    }
}

static GMenu *model(NSMenu *menu, BOOL app_menu_item)
{
    GMenu *outer = g_menu_new(), *section = g_menu_new();
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item isSeparatorItem]) {
            if (g_menu_model_get_n_items(section)) {
                GMenuItem *s = g_menu_item_new(NULL, NULL);
                g_menu_item_set_section(s, section);
                g_menu_append_item(outer, s);
                g_object_unref(s);
                g_object_unref(section);
                section = g_menu_new();
            }
            continue;
        }
        if (!shown(item, app_menu_item))
            continue;
        GMenuItem *entry;
        if ([item submenu]) {
            GMenu *sub = model([item submenu], NO);
            entry = g_menu_item_new([label([item title]) UTF8String], NULL);
            g_menu_item_set_submenu(entry, sub);
            g_object_unref(sub);
        } else {
            NSUInteger n = [items count];
            char name[32];
            snprintf(name, sizeof name, "%lu", (unsigned long)n);
            BOOL tick = [item state] != NSControlStateValueOff;
            GSimpleAction *action = tick ? g_simple_action_new_stateful(name, NULL, g_variant_new_boolean(1))
                                         : g_simple_action_new(name, NULL);
            g_signal_connect_data(action, "activate", (GCallback)activated, (void *)(uintptr_t)n, NULL, 0);
            g_simple_action_set_enabled(action, [item isEnabled]);
            g_action_map_add_action(actions, action);
            g_object_unref(action);
            [items addObject:item];
            [enabled addObject:@([item isEnabled])];
            char detailed[40];
            snprintf(detailed, sizeof detailed, "app.%s", name);
            entry = g_menu_item_new([label([item title]) UTF8String], detailed);
            NSString *accel = AMenuAccelerator([item keyEquivalent], [item keyEquivalentModifierMask]);
            if (accel)
                g_menu_item_set_attribute_value(entry, "accel", g_variant_new_string([accel UTF8String]));
        }
        g_menu_append_item(section, entry);
        g_object_unref(entry);
    }
    if (g_menu_model_get_n_items(section)) {
        GMenuItem *s = g_menu_item_new(NULL, NULL);
        g_menu_item_set_section(s, section);
        g_menu_append_item(outer, s);
        g_object_unref(s);
    }
    g_object_unref(section);
    return outer;
}

static void rebuild(NSMenu *main)
{
    for (NSUInteger i = 0; i < action_count; i++) {
        char name[32];
        snprintf(name, sizeof name, "%lu", (unsigned long)i);
        g_action_map_remove_action(actions, name);
    }
    [items removeAllObjects];
    [enabled removeAllObjects];
    g_menu_remove_all(app_menu);
    g_menu_remove_all(bar_menu);

    NSMenuItem *first = app_menu_item(main);
    if (first) {
        GMenu *m = model([first submenu], YES);
        GMenuItem *s = g_menu_item_new(NULL, NULL);
        g_menu_item_set_section(s, m);
        g_menu_append_item(app_menu, s);
        g_object_unref(s);
        g_object_unref(m);
    }
    for (NSMenuItem *top in [main itemArray]) {
        if (top == first || ![top submenu] || [top isHidden])
            continue;
        GMenu *m = model([top submenu], NO);
        /* a menu with nothing left in it (a Window menu of only what
         * Topline's own has) isn't shown */
        if (g_menu_model_get_n_items(m)) {
            NSString *title = [[top title] length] ? [top title] : [[top submenu] title];
            GMenuItem *entry = g_menu_item_new([label(title) UTF8String], NULL);
            g_menu_item_set_submenu(entry, m);
            g_menu_append_item(bar_menu, entry);
            g_object_unref(entry);
        }
        g_object_unref(m);
    }
    action_count = [items count];
}

/* ---- keeping them up to date -------------------------------------------------------------- */

static void check(NSMenu *menu, BOOL ask_delegate)
{
    id delegate = [menu delegate];
    if (ask_delegate && [delegate respondsToSelector:@selector(menuNeedsUpdate:)])
        [delegate menuNeedsUpdate:menu];
    [menu update];
    for (NSMenuItem *item in [menu itemArray])
        if ([item submenu])
            check([item submenu], ask_delegate);
}

static void refresh(BOOL ask_delegate)
{
    NSMenu *main = [NSApp mainMenu];
    if (state <= 0)
        return;
    if (main)
        check(main, ask_delegate);
    NSMutableString *now = [NSMutableString string];
    if (main)
        describe(main, NO, now);
    if (![now isEqualToString:shape ?: @""]) {
        [shape release];
        shape = [now copy];
        rebuild(main);
        return;
    }
    for (NSUInteger i = 0; i < [items count]; i++) {
        NSMenuItem *item = items[i];
        char name[32];
        snprintf(name, sizeof name, "%lu", (unsigned long)i);
        BOOL on = [item isEnabled];
        if (on != [enabled[i] boolValue]) {
            enabled[i] = @(on);
            void *action = g_action_map_lookup_action(actions, name);
            if (action)
                g_simple_action_set_enabled(action, on);
        }
    }
}

static void activated(GSimpleAction *action, GVariant *parameter, void *data)
{
    @autoreleasepool {
        NSUInteger n = (uintptr_t)data;
        if (n >= [items count])
            return;
        NSMenuItem *item = [[items[n] retain] autorelease];
        /* checked again now, as a Mac does when the item is chosen */
        NSMenu *menu = [item menu];
        if ([menu autoenablesItems]) {
            SEL a = [item action];
            id target = a ? [NSApp targetForAction:a to:[item target] from:item] : nil;
            if (!target || !AValidateItem(target, item))
                return;
        } else if (![item isEnabled]) {
            return;
        }
        ASendMenuItemAction(item);
        refresh(YES);
    }
}

@interface AMainMenuTicker : NSObject
@end
@implementation AMainMenuTicker
- (void)tick:(NSTimer *)timer
{
    BOOL active = [NSApp isActive] || [NSApp keyWindow] != nil;
    if (active || !shape)
        refresh(active && !was_active);
    was_active = active;
}
@end

/* ---- exporting them, and telling the compositor ------------------------------------------- */

static BOOL export_menus(void)
{
    if (state)
        return state > 0;
    state = -1;
    if (getenv("FERRY_NO_MENU_BAR") && *getenv("FERRY_NO_MENU_BAR"))
        return NO;
    if (!getenv("DBUS_SESSION_BUS_ADDRESS") && !getenv("XDG_RUNTIME_DIR"))
        return NO;
    GError *error = NULL;
    bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) {
        if (error)
            g_error_free(error);
        AWarnOnce("the app's menus: no session bus, so they aren't in the menu bar");
        return NO;
    }
    app_menu = g_menu_new();
    bar_menu = g_menu_new();
    actions = g_simple_action_group_new();
    GSimpleAction *quit = g_simple_action_new("quit", NULL);
    g_signal_connect_data(quit, "activate", (GCallback)quit_activated, NULL, NULL, 0);
    g_action_map_add_action(actions, quit);
    g_object_unref(quit);
    items = [[NSMutableArray alloc] init];
    enabled = [[NSMutableArray alloc] init];
    if (!g_dbus_connection_export_action_group(bus, APP_PATH, actions, &error) ||
        !g_dbus_connection_export_menu_model(bus, APP_MENU_PATH, app_menu, &error) ||
        !g_dbus_connection_export_menu_model(bus, BAR_PATH, bar_menu, &error)) {
        if (error)
            g_error_free(error);
        AWarnOnce("the app's menus: they couldn't be offered on the session bus");
        return NO;
    }
    AGlibAttach();
    state = 1;
    refresh(YES);
    ticker = [[AMainMenuTicker alloc] init];
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 target:ticker selector:@selector(tick:) userInfo:nil
                                            repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    return YES;
}

/* A window of the app is on screen: it tells the compositor where the app's
 * menus are, as a GTK app's windows do. */
void AMainMenuBarAttach(GdkWindow *window)
{
    if (!window || [NSApp activationPolicy] != NSApplicationActivationPolicyRegular)
        return;
    if (!g_type_check_instance_is_a(window, gdk_wayland_window_get_type()))
        return;   /* an X11 session: its desktop has no such note */
    if (!export_menus())
        return;
    NSString *ident = [[NSBundle mainBundle] bundleIdentifier] ?: [[NSProcessInfo processInfo] processName];
    gdk_wayland_window_set_dbus_properties_libgtk_only(window, [ident UTF8String], APP_MENU_PATH, BAR_PATH, NULL,
                                                       APP_PATH, g_dbus_connection_get_unique_name(bus));
}

/* The menus are looked at again soon: the main menu was set or changed. */
void AMainMenuBarChanged(void)
{
    if (state > 0)
        [ticker performSelector:@selector(tick:) withObject:nil afterDelay:0];
}
