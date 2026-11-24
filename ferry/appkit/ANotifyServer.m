/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: the desktop's notification server, for NSUserNotification
 * and UNUserNotificationCenter. Written from the freedesktop.org Desktop
 * Notifications specification (version 1.2) and the inline reply addition
 * that KDE documents for it.
 *
 * Notifications go to org.freedesktop.Notifications on the session bus
 * (freemac's Beacon, or any other desktop's server): Notify with the app's
 * name, icon and desktop file, the actions as key and label pairs, and
 * hints for the sound, the urgency and an inline reply. Notify is sent
 * without waiting; its reply gives the server's id, which CloseNotification
 * and the ActionInvoked, NotificationReplied and NotificationClosed signals
 * use. Those arrive in GLib's main context, which the main run loop waits
 * on, so owners hear them on the main thread. The server's capabilities
 * are asked once, and again when another server takes the name. With no
 * session bus or no server, nothing is shown and FERRY_VERBOSE says so
 * once.
 */
#import "ANotify.h"

static const char *const SERVER = "org.freedesktop.Notifications";
static const char *const SERVER_PATH = "/org/freedesktop/Notifications";

void ANotifyVerboseOnce(const char *what)
{
    static NSMutableSet *said;
    const char *v = getenv("FERRY_VERBOSE");
    if (!v || !*v)
        return;
    if (!said)
        said = [[NSMutableSet alloc] init];
    NSString *key = @(what);
    if ([said containsObject:key])
        return;
    [said addObject:key];
    fflush(stdout);
    fprintf(stderr, "ferry: %s\n", what);
}

/* ---- the app as the desktop knows it -------------------------------------------------- */

static NSString *bundle_string(NSString *key)
{
    id v = [[NSBundle mainBundle] objectForInfoDictionaryKey:key];
    return [v isKindOfClass:[NSString class]] && [v length] ? v : nil;
}

NSString *ANotifyAppName(void)
{
    return bundle_string(@"CFBundleDisplayName") ?: bundle_string(@"CFBundleName")
               ?: [[NSProcessInfo processInfo] processName] ?: @"";
}

static NSString *app_ident(void)
{
    NSString *ident = [[NSBundle mainBundle] bundleIdentifier];
    return [ident length] ? ident : [[NSProcessInfo processInfo] processName];
}

static NSArray *data_dirs(void)
{
    NSMutableArray *dirs = [NSMutableArray array];
    const char *home = getenv("XDG_DATA_HOME"), *user = getenv("HOME"), *all = getenv("XDG_DATA_DIRS");
    if (home && *home)
        [dirs addObject:@(home)];
    else if (user && *user)
        [dirs addObject:[@(user) stringByAppendingPathComponent:@".local/share"]];
    for (NSString *d in [@(all && *all ? all : "/usr/local/share:/usr/share") componentsSeparatedByString:@":"])
        if ([d length])
            [dirs addObject:d];
    return dirs;
}

/* freemac-mac-app's name for an installed app: ferry- and the bundle
 * identifier with its dots as dashes, in lower case. */
static NSString *installed_name(void)
{
    NSString *ident = [[NSBundle mainBundle] bundleIdentifier];
    if (![ident length])
        return nil;
    return [@"ferry-" stringByAppendingString:[[ident stringByReplacingOccurrencesOfString:@"." withString:@"-"]
                                                  lowercaseString]];
}

NSArray<NSString *> *ANotifyDesktopIDs(void)
{
    NSMutableArray *ids = [NSMutableArray arrayWithObject:[app_ident() stringByAppendingString:@".desktop"]];
    NSString *installed = installed_name();
    if (installed)
        for (NSString *dir in data_dirs())
            if ([[NSFileManager defaultManager]
                    fileExistsAtPath:[dir stringByAppendingFormat:@"/applications/%@.desktop", installed]]) {
                [ids addObject:[installed stringByAppendingString:@".desktop"]];
                break;
            }
    return ids;
}

/* The icon Ferry (NSApplication.m) or freemac-mac-app put in the icon theme. */
NSString *ANotifyAppIcon(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *ident = [[NSBundle mainBundle] bundleIdentifier], *installed = installed_name();
    for (NSString *dir in data_dirs()) {
        if ([ident length] && [fm fileExistsAtPath:[dir stringByAppendingFormat:@"/icons/hicolor/256x256/apps/%@.png",
                                                                                    ident]])
            return ident;
        if (installed && [fm fileExistsAtPath:[dir stringByAppendingFormat:@"/icons/hicolor/512x512/apps/%@.png",
                                                                               installed]])
            return installed;
    }
    return @"";
}

/* ---- the bus -------------------------------------------------------------------------- */

static GDBusConnection *bus;
static int bus_state;                   /* 0 not tried, 1 connected, -1 none */

static void flush_at_exit(void)
{
    if (bus)
        g_dbus_connection_flush_sync(bus, NULL, NULL);
}

GDBusConnection *ANotifyBus(void)
{
    if (bus_state)
        return bus;
    bus_state = -1;
    if (!getenv("DBUS_SESSION_BUS_ADDRESS") && !getenv("XDG_RUNTIME_DIR")) {
        ANotifyVerboseOnce("notifications and the Dock: there is no session bus, so nothing is shown");
        return NULL;
    }
    GError *error = NULL;
    bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) {
        if (error)
            g_error_free(error);
        ANotifyVerboseOnce("notifications and the Dock: there is no session bus, so nothing is shown");
        return NULL;
    }
    AGlibAttach();
    atexit(flush_at_exit);
    bus_state = 1;
    return bus;
}

/* ---- what is shown ------------------------------------------------------------------------ */

@implementation ANotifyMessage
- (void)dealloc
{
    [_summary release];
    [_body release];
    [_soundFile release];
    [_soundName release];
    [_actions release];
    [_replyKey release];
    [_replyButton release];
    [_replyPlaceholder release];
    [super dealloc];
}
@end

/* One notification Ferry asked for: its owner, and the server's id once the
 * reply to Notify has come. */
@interface ANotifyShown : NSObject {
@public
    unsigned handle, serverID;
    id<ANotifyOwner> owner;
    BOOL closeWanted;
}
@end
@implementation ANotifyShown
- (void)dealloc
{
    [owner release];
    [super dealloc];
}
@end

static NSMutableDictionary *by_handle;  /* NSNumber handle -> ANotifyShown */
static NSMutableDictionary *by_server;  /* NSNumber server id -> ANotifyShown */
static NSSet *capabilities;
static BOOL subscribed;

static ANotifyShown *shown_with_server_id(unsigned ident)
{
    return ident ? by_server[@(ident)] : nil;
}

static void forget(ANotifyShown *s)
{
    [[s retain] autorelease];
    if (s->serverID)
        [by_server removeObjectForKey:@(s->serverID)];
    [by_handle removeObjectForKey:@(s->handle)];
}

static void close_on_server(unsigned ident)
{
    if (!ident || !bus)
        return;
    GVariant *arg = g_variant_new_uint32(ident);
    g_dbus_connection_call(bus, SERVER, SERVER_PATH, SERVER, "CloseNotification", g_variant_new_tuple(&arg, 1), NULL,
                           0, -1, NULL, NULL, NULL);
}

static uint32_t child_uint(GVariant *v, size_t i)
{
    GVariant *c = g_variant_get_child_value(v, i);
    uint32_t n = g_variant_get_uint32(c);
    g_variant_unref(c);
    return n;
}

static NSString *child_string(GVariant *v, size_t i)
{
    GVariant *c = g_variant_get_child_value(v, i);
    NSString *s = [NSString stringWithUTF8String:g_variant_get_string(c, NULL) ?: ""];
    g_variant_unref(c);
    return s ?: @"";
}

/* The server's signals. They are broadcast, so those about other programs'
 * notifications are passed over. */
static void server_signal(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                          const char *signal, GVariant *params, void *data)
{
    @autoreleasepool {
        BOOL invoked = !strcmp(signal, "ActionInvoked"), replied = !strcmp(signal, "NotificationReplied");
        BOOL closed = !strcmp(signal, "NotificationClosed");
        if (!invoked && !replied && !closed)
            return;
        if (!g_variant_is_of_type(params, closed ? "(uu)" : "(us)"))
            return;
        ANotifyShown *s = [[shown_with_server_id(child_uint(params, 0)) retain] autorelease];
        if (!s || !s->owner)
            return;
        id<ANotifyOwner> owner = [[s->owner retain] autorelease];
        if (closed) {
            unsigned reason = child_uint(params, 1);
            forget(s);
            A_REPORTING([owner _notifyClosed:reason];)
        } else if (invoked) {
            NSString *key = child_string(params, 1);
            A_REPORTING([owner _notifyInvoked:key];)
        } else {
            NSString *text = child_string(params, 1);
            A_REPORTING([owner _notifyReplied:text];)
        }
    }
}

/* Another server took the name (or the first one started): its
 * capabilities are asked again before the next notification. */
static void owner_changed(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                          const char *signal, GVariant *params, void *data)
{
    [capabilities release];
    capabilities = nil;
}

static void subscribe(void)
{
    if (subscribed)
        return;
    subscribed = YES;
    g_dbus_connection_signal_subscribe(bus, SERVER, SERVER, NULL, SERVER_PATH, NULL, 0, server_signal, NULL, NULL);
    g_dbus_connection_signal_subscribe(bus, "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                                       "/org/freedesktop/DBus", SERVER, 0, owner_changed, NULL, NULL);
}

/* The server's capabilities, asked now if not known; nil when no server
 * answers. */
static NSSet *server_capabilities(void)
{
    if (capabilities)
        return capabilities;
    if (!ANotifyBus())
        return nil;
    subscribe();
    GError *error = NULL;
    GVariant *reply = g_dbus_connection_call_sync(bus, SERVER, SERVER_PATH, SERVER, "GetCapabilities", NULL, "(as)",
                                                  0, 5000, NULL, &error);
    if (!reply) {
        if (error)
            g_error_free(error);
        ANotifyVerboseOnce("notifications: no notification server is running (org.freedesktop.Notifications), "
                           "so notifications aren't shown");
        return nil;
    }
    NSMutableSet *caps = [NSMutableSet set];
    GVariant *list = g_variant_get_child_value(reply, 0);
    for (size_t i = 0, n = g_variant_n_children(list); i < n; i++)
        [caps addObject:child_string(list, i)];
    g_variant_unref(list);
    g_variant_unref(reply);
    capabilities = [caps copy];
    return capabilities;
}

BOOL ANotifyServerCan(NSString *capability)
{
    return [server_capabilities() containsObject:capability];
}

static void notify_reply(void *source, GAsyncResult *result, void *data)
{
    @autoreleasepool {
        GError *error = NULL;
        GVariant *reply = g_dbus_connection_call_finish(bus, result, &error);
        ANotifyShown *s = [[by_handle[@((unsigned)(uintptr_t)data)] retain] autorelease];
        if (!reply) {
            if (error)
                g_error_free(error);
            ANotifyVerboseOnce("notifications: the notification server didn't take a notification, so it isn't shown");
            if (s)
                forget(s);
            return;
        }
        unsigned ident = child_uint(reply, 0);
        g_variant_unref(reply);
        if (!s)
            return;
        if (s->closeWanted) {
            close_on_server(ident);
            forget(s);
            return;
        }
        s->serverID = ident;
        by_server[@(ident)] = s;
    }
}

/* The body, with the markup some servers read in it made plain text. */
static NSString *body_text(NSString *body)
{
    if (![body length] || !ANotifyServerCan(@"body-markup"))
        return body ?: @"";
    NSMutableString *m = [[body mutableCopy] autorelease];
    [m replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [m length])];
    [m replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [m length])];
    [m replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [m length])];
    return m;
}

static void hint(NSMutableArray *hints, const char *key, GVariant *value)
{
    [hints addObject:[NSValue valueWithPointer:g_variant_new_dict_entry(g_variant_new_string(key),
                                                                        g_variant_new_variant(value))]];
}

static GVariant *pointer_array(NSArray *values, const char *type)
{
    size_t n = [values count];
    GVariant **items = calloc(n ? n : 1, sizeof *items);
    for (size_t i = 0; i < n; i++)
        items[i] = [values[i] pointerValue];
    GVariant *array = g_variant_new_array(type, items, n);
    free(items);
    return array;
}

unsigned ANotifyShow(ANotifyMessage *m, id<ANotifyOwner> owner, unsigned replaces)
{
    ANotifyShown *old = replaces ? [[by_handle[@(replaces)] retain] autorelease] : nil;
    unsigned replacesID = 0;
    if (old) {
        replacesID = old->serverID;
        if (replacesID)
            forget(old);
        else {
            /* not shown yet: closed as soon as it is */
            old->closeWanted = YES;
            [old->owner release];
            old->owner = nil;
        }
    }
    if (!server_capabilities())
        return 0;
    BOOL actions = ANotifyServerCan(@"actions"), reply = actions && [m replyKey] && ANotifyServerCan(@"inline-reply");
    NSMutableArray *strings = [NSMutableArray array];
    if (actions) {
        for (NSArray *pair in [m actions]) {
            [strings addObject:[NSValue valueWithPointer:g_variant_new_string([pair[0] UTF8String])]];
            [strings addObject:[NSValue valueWithPointer:g_variant_new_string([pair[1] UTF8String])]];
        }
        if (reply) {
            [strings addObject:[NSValue valueWithPointer:g_variant_new_string("inline-reply")]];
            [strings addObject:[NSValue valueWithPointer:g_variant_new_string([[m replyButton] ?: @"Reply" UTF8String])]];
        }
    }
    NSMutableArray *hints = [NSMutableArray array];
    NSArray *desktop = ANotifyDesktopIDs();
    hint(hints, "desktop-entry", g_variant_new_string([[desktop[0] stringByDeletingPathExtension] UTF8String]));
    hint(hints, "urgency", g_variant_new_byte((unsigned char)[m urgency]));
    if ([m silent])
        hint(hints, "suppress-sound", g_variant_new_boolean(1));
    else if ([m soundFile])
        hint(hints, "sound-file", g_variant_new_string([[m soundFile] fileSystemRepresentation]));
    else
        hint(hints, "sound-name", g_variant_new_string([[m soundName] ?: @"message-new-instant" UTF8String]));
    if (reply) {
        hint(hints, "x-kde-reply-placeholder-text", g_variant_new_string([[m replyPlaceholder] ?: @"" UTF8String]));
        if ([m replyButton])
            hint(hints, "x-kde-reply-submit-button-text", g_variant_new_string([[m replyButton] UTF8String]));
    }
    GVariant *args[8] = {
        g_variant_new_string([ANotifyAppName() UTF8String]),
        g_variant_new_uint32(replacesID),
        g_variant_new_string([ANotifyAppIcon() UTF8String]),
        g_variant_new_string([[m summary] ?: @"" UTF8String]),
        g_variant_new_string([body_text([m body]) UTF8String]),
        pointer_array(strings, "s"),
        pointer_array(hints, "{sv}"),
        g_variant_new_int32(-1),
    };
    static unsigned last;
    ANotifyShown *s = [[[ANotifyShown alloc] init] autorelease];
    s->handle = ++last;
    s->owner = [owner retain];
    if (!by_handle) {
        by_handle = [[NSMutableDictionary alloc] init];
        by_server = [[NSMutableDictionary alloc] init];
    }
    by_handle[@(s->handle)] = s;
    g_dbus_connection_call(bus, SERVER, SERVER_PATH, SERVER, "Notify", g_variant_new_tuple(args, 8), "(u)", 0, -1,
                           NULL, (void *)notify_reply, (void *)(uintptr_t)s->handle);
    return s->handle;
}

void ANotifyClose(unsigned handle)
{
    ANotifyShown *s = handle ? by_handle[@(handle)] : nil;
    if (!s)
        return;
    [s->owner release];
    s->owner = nil;
    if (s->serverID) {
        close_on_server(s->serverID);
        forget(s);
    } else {
        s->closeWanted = YES;
    }
}
