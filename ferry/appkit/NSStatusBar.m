/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: menu bar items (NSStatusBar, NSStatusItem,
 * NSStatusBarButton), written from Apple's public documentation.
 *
 * On a Mac these are drawn by the system in its menu bar. Here each item is
 * offered to the desktop's menu bar through the freedesktop StatusNotifierItem
 * protocol over D-Bus (freemac's Topline shows them, as do other desktops),
 * and its menu through the dbusmenu protocol, read by the menu bar when it
 * opens. The item's picture (its image, its title, or both, as a Mac draws
 * them) is drawn here with Ferry's Core Graphics and sent as pixels.
 *
 * Each item is an object at /StatusNotifierItem/N on the program's own
 * connection to the session bus, with its menu at /MenuBar/N, registered with
 * org.kde.StatusNotifierWatcher by its object path (and again whenever the
 * watcher's owner changes, as when the menu bar restarts). An item that goes
 * away first says it is Passive, so the menu bar hides it. Without a session
 * bus the items still work as objects; nothing is shown.
 */
#import "ANotify.h"
#import <objc/message.h>

static const char *const WATCHER = "org.kde.StatusNotifierWatcher";
static const char *const ITEM_IFACE = "org.kde.StatusNotifierItem";
static const char *const MENU_IFACE = "com.canonical.dbusmenu";

static const char *const ITEM_XML =
    "<node><interface name='org.kde.StatusNotifierItem'>"
    "<method name='Activate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "<method name='SecondaryActivate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "<method name='ContextMenu'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "<method name='Scroll'><arg type='i' direction='in'/><arg type='s' direction='in'/></method>"
    "<property name='Category' type='s' access='read'/>"
    "<property name='Id' type='s' access='read'/>"
    "<property name='Title' type='s' access='read'/>"
    "<property name='Status' type='s' access='read'/>"
    "<property name='WindowId' type='i' access='read'/>"
    "<property name='IconName' type='s' access='read'/>"
    "<property name='IconPixmap' type='a(iiay)' access='read'/>"
    "<property name='AttentionIconName' type='s' access='read'/>"
    "<property name='ToolTip' type='(sa(iiay)ss)' access='read'/>"
    "<property name='ItemIsMenu' type='b' access='read'/>"
    "<property name='Menu' type='o' access='read'/>"
    "<signal name='NewTitle'/><signal name='NewIcon'/><signal name='NewToolTip'/>"
    "<signal name='NewStatus'><arg type='s'/></signal>"
    "</interface></node>";

static const char *const MENU_XML =
    "<node><interface name='com.canonical.dbusmenu'>"
    "<method name='GetLayout'><arg type='i' direction='in'/><arg type='i' direction='in'/>"
    "<arg type='as' direction='in'/><arg type='u' direction='out'/><arg type='(ia{sv}av)' direction='out'/></method>"
    "<method name='GetGroupProperties'><arg type='ai' direction='in'/><arg type='as' direction='in'/>"
    "<arg type='a(ia{sv})' direction='out'/></method>"
    "<method name='GetProperty'><arg type='i' direction='in'/><arg type='s' direction='in'/>"
    "<arg type='v' direction='out'/></method>"
    "<method name='Event'><arg type='i' direction='in'/><arg type='s' direction='in'/>"
    "<arg type='v' direction='in'/><arg type='u' direction='in'/></method>"
    "<method name='EventGroup'><arg type='a(isvu)' direction='in'/><arg type='ai' direction='out'/></method>"
    "<method name='AboutToShow'><arg type='i' direction='in'/><arg type='b' direction='out'/></method>"
    "<method name='AboutToShowGroup'><arg type='ai' direction='in'/><arg type='ai' direction='out'/>"
    "<arg type='ai' direction='out'/></method>"
    "<property name='Version' type='u' access='read'/>"
    "<property name='TextDirection' type='s' access='read'/>"
    "<property name='Status' type='s' access='read'/>"
    "<property name='IconThemePath' type='as' access='read'/>"
    "<signal name='LayoutUpdated'><arg type='u'/><arg type='i'/></signal>"
    "<signal name='ItemsPropertiesUpdated'><arg type='a(ia{sv})'/><arg type='a(ias)'/></signal>"
    "</interface></node>";

@interface NSStatusItem (FerryPrivate)
- (instancetype)_initWithBar:(NSStatusBar *)bar length:(CGFloat)length;
- (instancetype)_initServingMenuAt:(const char *)path refresh:(NSMenu *(^)(void))refresh;
- (void)_changed;
- (void)_gone;
- (GVariant *)_property:(const char *)name;
- (void)_activate;
- (GVariant *)_layoutFrom:(int)parent depth:(int)depth;
- (BOOL)_aboutToShow:(int)ident;
- (BOOL)_event:(int)ident;
- (GVariant *)_propertiesOf:(int)ident;
- (unsigned)_number;
@end

/* ---- the connection ------------------------------------------------------------------ */

static GDBusConnection *bus;
static int bus_state;               /* 0 not tried, 1 connected, -1 none */
static GDBusInterfaceInfo *item_info, *menu_info;
static NSMutableArray *live_items;  /* NSValue, non-retaining: the app keeps its items */

static NSStatusItem *item_for(void *data)
{
    for (NSValue *v in live_items)
        if ([v pointerValue] == data)
            return data;
    return nil;
}

static void item_method(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                        const char *method, GVariant *params, GDBusMethodInvocation *inv, void *data)
{
    NSStatusItem *item = item_for(data);
    if (item && !strcmp(method, "Activate"))
        [item _activate];
    /* SecondaryActivate (middle-click), ContextMenu and Scroll mean nothing to a Mac app. */
    g_dbus_method_invocation_return_value(inv, NULL);
}

static GVariant *item_get(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                          const char *prop, GError **error, void *data)
{
    NSStatusItem *item = item_for(data);
    return item ? [item _property:prop] : NULL;
}

static GVariant *tuple1(GVariant *v) { return g_variant_new_tuple(&v, 1); }

static void menu_method(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                        const char *method, GVariant *params, GDBusMethodInvocation *inv, void *data)
{
    NSStatusItem *item = item_for(data);
    if (!item) {
        g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.UnknownObject", "gone");
        return;
    }
    @autoreleasepool {
        if (!strcmp(method, "GetLayout")) {
            GVariant *a = g_variant_get_child_value(params, 0), *b = g_variant_get_child_value(params, 1);
            int parent = g_variant_get_int32(a), depth = g_variant_get_int32(b);
            g_variant_unref(a);
            g_variant_unref(b);
            GVariant *layout = [item _layoutFrom:parent depth:depth];
            if (!layout) {
                g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.InvalidArgs",
                                                           "no such menu item");
                return;
            }
            GVariant *out[2] = {g_variant_new_uint32([item _number]), layout};
            g_dbus_method_invocation_return_value(inv, g_variant_new_tuple(out, 2));
        } else if (!strcmp(method, "Event")) {
            GVariant *a = g_variant_get_child_value(params, 0), *b = g_variant_get_child_value(params, 1);
            int ident = g_variant_get_int32(a);
            BOOL clicked = !strcmp(g_variant_get_string(b, NULL), "clicked");
            g_variant_unref(a);
            g_variant_unref(b);
            g_dbus_method_invocation_return_value(inv, NULL);
            if (clicked)
                [item _event:ident];
        } else if (!strcmp(method, "EventGroup")) {
            GVariant *events = g_variant_get_child_value(params, 0);
            size_t n = g_variant_n_children(events);
            NSMutableArray *clicks = [NSMutableArray array];
            for (size_t i = 0; i < n; i++) {
                GVariant *e = g_variant_get_child_value(events, i);
                GVariant *a = g_variant_get_child_value(e, 0), *b = g_variant_get_child_value(e, 1);
                if (!strcmp(g_variant_get_string(b, NULL), "clicked"))
                    [clicks addObject:@(g_variant_get_int32(a))];
                g_variant_unref(a);
                g_variant_unref(b);
                g_variant_unref(e);
            }
            g_variant_unref(events);
            g_dbus_method_invocation_return_value(inv, tuple1(g_variant_new_array("i", NULL, 0)));
            for (NSNumber *ident in clicks)
                [item _event:[ident intValue]];
        } else if (!strcmp(method, "AboutToShow")) {
            GVariant *a = g_variant_get_child_value(params, 0);
            BOOL changed = [item _aboutToShow:g_variant_get_int32(a)];
            g_variant_unref(a);
            g_dbus_method_invocation_return_value(inv, tuple1(g_variant_new_boolean(changed)));
        } else if (!strcmp(method, "AboutToShowGroup")) {
            GVariant *ids = g_variant_get_child_value(params, 0);
            size_t n = g_variant_n_children(ids);
            for (size_t i = 0; i < n; i++) {
                GVariant *a = g_variant_get_child_value(ids, i);
                [item _aboutToShow:g_variant_get_int32(a)];
                g_variant_unref(a);
            }
            g_variant_unref(ids);
            GVariant *out[2] = {g_variant_new_array("i", NULL, 0), g_variant_new_array("i", NULL, 0)};
            g_dbus_method_invocation_return_value(inv, g_variant_new_tuple(out, 2));
        } else if (!strcmp(method, "GetGroupProperties")) {
            GVariant *ids = g_variant_get_child_value(params, 0);
            size_t n = g_variant_n_children(ids);
            GVariant **rows = calloc(n ? n : 1, sizeof *rows);
            size_t kept = 0;
            for (size_t i = 0; i < n; i++) {
                GVariant *a = g_variant_get_child_value(ids, i);
                int ident = g_variant_get_int32(a);
                g_variant_unref(a);
                GVariant *props = [item _propertiesOf:ident];
                if (props) {
                    GVariant *pair[2] = {g_variant_new_int32(ident), props};
                    rows[kept++] = g_variant_new_tuple(pair, 2);
                }
            }
            g_variant_unref(ids);
            g_dbus_method_invocation_return_value(inv, tuple1(g_variant_new_array("(ia{sv})", rows, kept)));
            free(rows);
        } else if (!strcmp(method, "GetProperty")) {
            g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.InvalidArgs",
                                                       "use GetGroupProperties");
        } else {
            g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.UnknownMethod", method);
        }
    }
}

static GVariant *menu_get(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                          const char *prop, GError **error, void *data)
{
    if (!strcmp(prop, "Version"))
        return g_variant_new_uint32(3);
    if (!strcmp(prop, "TextDirection"))
        return g_variant_new_string("ltr");
    if (!strcmp(prop, "Status"))
        return g_variant_new_string("normal");
    if (!strcmp(prop, "IconThemePath"))
        return g_variant_new_array("s", NULL, 0);
    return NULL;
}

static const GDBusInterfaceVTable item_vtable = {item_method, item_get, NULL, {0}};
static const GDBusInterfaceVTable menu_vtable = {menu_method, menu_get, NULL, {0}};

static void register_item(NSStatusItem *item)
{
    char path[64];
    snprintf(path, sizeof path, "/StatusNotifierItem/%u", [item _number]);
    GVariant *arg = g_variant_new_string(path);
    g_dbus_connection_call(bus, WATCHER, "/StatusNotifierWatcher", WATCHER, "RegisterStatusNotifierItem",
                           g_variant_new_tuple(&arg, 1), NULL, 0, 3000, NULL, NULL, NULL);
}

/* The menu bar (re)started: announce every item to it again. */
static void watcher_changed(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                            const char *signal, GVariant *params, void *data)
{
    GVariant *owner = g_variant_get_child_value(params, 2);
    BOOL there = *g_variant_get_string(owner, NULL) != 0;
    g_variant_unref(owner);
    if (!there)
        return;
    for (NSValue *v in [[live_items copy] autorelease])
        register_item([v pointerValue]);
}

static BOOL connect_bus(void)
{
    if (bus_state)
        return bus_state > 0;
    bus_state = -1;
    if (!getenv("DBUS_SESSION_BUS_ADDRESS") && !getenv("XDG_RUNTIME_DIR"))
        return NO;
    GError *error = NULL;
    bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) {
        if (error) {
            AWarnOnce("menu bar items: no session bus, so they aren't shown");
            g_error_free(error);
        }
        return NO;
    }
    GDBusNodeInfo *item_node = g_dbus_node_info_new_for_xml(ITEM_XML, NULL);
    GDBusNodeInfo *menu_node = g_dbus_node_info_new_for_xml(MENU_XML, NULL);
    item_info = item_node ? g_dbus_node_info_lookup_interface(item_node, ITEM_IFACE) : NULL;
    menu_info = menu_node ? g_dbus_node_info_lookup_interface(menu_node, MENU_IFACE) : NULL;
    if (!item_info || !menu_info)
        return NO;
    AGlibAttach();
    g_dbus_connection_signal_subscribe(bus, "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                                       "/org/freedesktop/DBus", WATCHER, 0, watcher_changed, NULL, NULL);
    bus_state = 1;
    return YES;
}

/* ---- drawing the item ------------------------------------------------------------------ */

/* The menu bar's text colour, for titles and template images. */
static NSColor *bar_ink(void)
{
    return [NSColor colorWithCalibratedWhite:0.11 alpha:1];
}

/* The item's picture, `height` pixels high: SNI's a(iiay) entry, ARGB in
 * network byte order, not premultiplied. */
static GVariant *picture(NSStatusItem *item, int height)
{
    NSImage *image = [[item button] image];
    NSString *title = [[item button] title];
    NSView *view = [item view];
    CGFloat unit = height / 22.0;           /* drawn in a Mac's 22-point menu bar, scaled */
    NSAttributedString *text = nil;
    CGFloat textWidth = 0, ascent = 0, descent = 0;
    if ([title length] && !view) {
        text = AAttributed(title, [NSFont menuBarFontOfSize:0], bar_ink());
        textWidth = ceil(ALineSize(text, &ascent, &descent).width);
    }
    NSSize imageSize = NSZeroSize;
    if (image && [image isValid] && !view) {
        imageSize = [image size];
        if (imageSize.height > 18) {        /* a Mac fits it in the bar */
            imageSize.width *= 18 / imageSize.height;
            imageSize.height = 18;
        }
    }
    CGFloat width;                          /* in points */
    if (view)
        width = [view frame].size.width;
    else if ([item length] > 0)
        width = [item length];
    else if ([item length] == NSSquareStatusItemLength)
        width = 22;
    else
        width = imageSize.width + (imageSize.width && textWidth ? 4 : 0) + textWidth;
    if (width < 1)
        return NULL;
    int w = (int)ceil(width * unit), h = height;
    if (w > 600)
        w = 600;
    size_t stride = (size_t)w * 4;
    unsigned char *pixels = calloc(stride, h);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(pixels, w, h, 8, stride, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextScaleCTM(cg, unit, unit);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:cg flipped:NO]];
    if (view) {
        /* A custom view draws itself into the bar's 22 points, as it would
         * into a bitmap of itself. */
        NSRect b = [view bounds], f = [view frame];
        CGFloat sx = b.size.width ? f.size.width / b.size.width : 1;
        CGFloat sy = b.size.height ? f.size.height / b.size.height : 1;
        CGContextTranslateCTM(cg, 0, (22 - f.size.height) / 2);
        CGContextConcatCTM(cg, [view isFlipped]
                                   ? CGAffineTransformMake(sx, 0, 0, -sy, -b.origin.x * sx, f.size.height + b.origin.y * sy)
                                   : CGAffineTransformMake(sx, 0, 0, sy, -b.origin.x * sx, -b.origin.y * sy));
        [view _drawContentInContext:cg dirty:b screen:NO];
    } else {
        CGFloat x = 0;
        if ([item length] > 0 || [item length] == NSSquareStatusItemLength)
            x = (width - (imageSize.width + (imageSize.width && textWidth ? 4 : 0) + textWidth)) / 2;
        if (imageSize.width > 0) {
            NSRect r = NSMakeRect(x, (22 - imageSize.height) / 2, imageSize.width, imageSize.height);
            if ([image isTemplate] || [[item button] appearsDisabled])
                [image _drawInControlRect:r color:bar_ink()
                                 fraction:[[item button] appearsDisabled] || ![item isEnabled] ? 0.4 : 1];
            else
                [image drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
            x += imageSize.width + (textWidth ? 4 : 0);
        }
        if (text)
            ADrawLine(text, x, floor((22 - (ascent + descent)) / 2 + descent));
    }
    [NSGraphicsContext restoreGraphicsState];
    CGContextRelease(cg);
    /* RGBA premultiplied, top row first, to ARGB straight */
    unsigned char *argb = malloc(stride * h);
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            unsigned char *p = pixels + (size_t)y * stride + (size_t)x * 4;
            unsigned char *q = argb + (size_t)y * stride + (size_t)x * 4;
            unsigned a = p[3];
            q[0] = a;
            for (int k = 0; k < 3; k++)
                q[k + 1] = a ? (unsigned char)((p[k] * 255 + a / 2) / a) : 0;
        }
    free(pixels);
    GVariant *parts[3] = {g_variant_new_int32(w), g_variant_new_int32(h),
                          g_variant_new_fixed_array("y", argb, stride * h, 1)};
    free(argb);
    return g_variant_new_tuple(parts, 3);
}

/* ---- the menu, as dbusmenu sees it ------------------------------------------------------ */

static NSString *dbus_label(NSString *title)
{
    /* dbusmenu marks an access key with "_"; a real one is "__". */
    return [title ?: @"" stringByReplacingOccurrencesOfString:@"_" withString:@"__"];
}

static BOOL item_enabled(NSMenuItem *mi)
{
    if (![mi isEnabled])
        return NO;
    if ([mi hasSubmenu] || ![[mi menu] autoenablesItems])
        return YES;
    SEL action = [mi action];
    if (!action)
        return NO;
    id target = [NSApp targetForAction:action to:[mi target] from:mi];
    if (!target)
        return NO;
    if ([target respondsToSelector:@selector(validateMenuItem:)])
        return ((BOOL(*)(id, SEL, id))objc_msgSend)(target, @selector(validateMenuItem:), mi);
    return YES;
}

static void entry(NSMutableArray *keys, NSMutableArray *values, const char *key, GVariant *value)
{
    [keys addObject:[NSValue valueWithPointer:key]];
    [values addObject:[NSValue valueWithPointer:value]];
}

static GVariant *props_of(NSMenuItem *mi)
{
    NSMutableArray *keys = [NSMutableArray array], *values = [NSMutableArray array];
    if ([mi isSeparatorItem]) {
        entry(keys, values, "type", g_variant_new_string("separator"));
    } else {
        entry(keys, values, "label", g_variant_new_string([dbus_label([mi title]) UTF8String]));
        if (!item_enabled(mi))
            entry(keys, values, "enabled", g_variant_new_boolean(0));
        NSControlStateValue state = [mi state];
        if (state != NSControlStateValueOff) {
            entry(keys, values, "toggle-type", g_variant_new_string("checkmark"));
            entry(keys, values, "toggle-state", g_variant_new_int32(state == NSControlStateValueOn ? 1 : -1));
        }
        if ([mi hasSubmenu])
            entry(keys, values, "children-display", g_variant_new_string("submenu"));
    }
    if ([mi isHidden])
        entry(keys, values, "visible", g_variant_new_boolean(0));
    size_t n = [keys count];
    GVariant **pairs = calloc(n ? n : 1, sizeof *pairs);
    for (size_t i = 0; i < n; i++)
        pairs[i] = g_variant_new_dict_entry(g_variant_new_string([keys[i] pointerValue]),
                                            g_variant_new_variant([values[i] pointerValue]));
    GVariant *dict = g_variant_new_array("{sv}", pairs, n);
    free(pairs);
    return dict;
}

static void menu_will_open(NSMenu *menu)
{
    id d = [menu delegate];
    if ([d respondsToSelector:@selector(menuNeedsUpdate:)])
        ((void (*)(id, SEL, id))objc_msgSend)(d, @selector(menuNeedsUpdate:), menu);
    if ([d respondsToSelector:@selector(menuWillOpen:)])
        ((void (*)(id, SEL, id))objc_msgSend)(d, @selector(menuWillOpen:), menu);
    [menu update];
}

/* ---- NSStatusBar ------------------------------------------------------------------------- */

@implementation NSStatusBar

+ (NSStatusBar *)systemStatusBar
{
    static NSStatusBar *shared;
    if (!shared)
        shared = [[NSStatusBar alloc] init];
    return shared;
}

- (NSStatusItem *)statusItemWithLength:(CGFloat)length
{
    return [[[NSStatusItem alloc] _initWithBar:self length:length] autorelease];
}

- (void)removeStatusItem:(NSStatusItem *)item { [item _gone]; }
- (BOOL)isVertical { return NO; }
- (CGFloat)thickness { return 22; }
@end

/* ---- NSStatusBarButton -------------------------------------------------------------------- */

@implementation NSStatusBarButton {
    BOOL _appearsDisabled;
    NSStatusItem *_item;
}
- (void)_setItem:(NSStatusItem *)item { _item = item; }
- (BOOL)appearsDisabled { return _appearsDisabled; }
- (void)setAppearsDisabled:(BOOL)f { _appearsDisabled = f; [_item _changed]; }
- (void)setImage:(NSImage *)image { [super setImage:image]; [_item _changed]; }
- (void)setAlternateImage:(NSImage *)image { [super setAlternateImage:image]; }
- (void)setTitle:(NSString *)title { [super setTitle:title]; [_item _changed]; }
- (void)setAttributedTitle:(NSAttributedString *)title { [super setAttributedTitle:title]; [_item _changed]; }
- (void)setToolTip:(NSString *)tip { [super setToolTip:tip]; [_item _changed]; }
- (void)setEnabled:(BOOL)f { [super setEnabled:f]; [_item _changed]; }
- (void)setHidden:(BOOL)f { [super setHidden:f]; [_item _changed]; }
@end

/* ---- NSStatusItem -------------------------------------------------------------------------- */

@implementation NSStatusItem {
    NSStatusBar *_bar;
    CGFloat _length;
    NSMenu *_menu;
    NSStatusBarButton *_button;
    NSStatusItemBehavior _behavior;
    BOOL _visible, _highlightMode, _gone, _queued;
    NSString *_autosaveName;
    NSView *_view;
    SEL _doubleAction;
    unsigned _number, _revision;
    unsigned _itemObject, _menuObject;
    NSMutableArray *_ids;               /* menu item id - 1 -> NSMenuItem, from the last layout */
    NSString *_shownTip, *_shownStatus;
    NSMenu *(^_refresh)(void);          /* the Dock's menu (AMenuServe) */
}

- (instancetype)_initWithBar:(NSStatusBar *)bar length:(CGFloat)length
{
    if (!(self = [super init]))
        return nil;
    static unsigned count;
    _number = ++count;
    _bar = bar;
    _length = length;
    _visible = YES;
    _revision = 1;
    _ids = [[NSMutableArray alloc] init];
    _button = [[NSStatusBarButton alloc] initWithFrame:NSMakeRect(0, 0, length > 0 ? length : 22, 22)];
    [_button setBordered:NO];
    [_button setTitle:@""]; /* a menu bar button has no title until given one */
    [_button _setItem:self];
    if (!live_items)
        live_items = [[NSMutableArray alloc] init];
    [live_items addObject:[NSValue valueWithPointer:self]];
    if (connect_bus()) {
        char path[64];
        snprintf(path, sizeof path, "/StatusNotifierItem/%u", _number);
        _itemObject = g_dbus_connection_register_object(bus, path, item_info, &item_vtable, self, NULL, NULL);
        snprintf(path, sizeof path, "/MenuBar/%u", _number);
        _menuObject = g_dbus_connection_register_object(bus, path, menu_info, &menu_vtable, self, NULL, NULL);
        register_item(self);
    }
    return self;
}

/* The Dock's menu (NSDockTile.m): only a menu, at path, asked for afresh
 * as the dock opens it. */
- (instancetype)_initServingMenuAt:(const char *)path refresh:(NSMenu *(^)(void))refresh
{
    if (!(self = [super init]))
        return nil;
    _revision = 1;
    _ids = [[NSMutableArray alloc] init];
    _refresh = [refresh copy];
    if (!live_items)
        live_items = [[NSMutableArray alloc] init];
    [live_items addObject:[NSValue valueWithPointer:self]];
    if (connect_bus())
        _menuObject = g_dbus_connection_register_object(bus, path, menu_info, &menu_vtable, self, NULL, NULL);
    return self;
}

- (void)_gone
{
    if (_gone)
        return;
    _gone = YES;
    if (bus && _menuObject && !_itemObject) {
        g_dbus_connection_unregister_object(bus, _menuObject);
        _menuObject = 0;
    }
    if (bus && _itemObject) {
        /* There is no "unregister": a Passive item is hidden by the menu bar. */
        char path[64];
        snprintf(path, sizeof path, "/StatusNotifierItem/%u", _number);
        GVariant *arg = g_variant_new_string("Passive");
        g_dbus_connection_emit_signal(bus, NULL, path, ITEM_IFACE, "NewStatus", g_variant_new_tuple(&arg, 1), NULL);
        g_dbus_connection_unregister_object(bus, _itemObject);
        g_dbus_connection_unregister_object(bus, _menuObject);
        _itemObject = _menuObject = 0;
    }
    for (NSValue *v in [[live_items copy] autorelease])
        if ([v pointerValue] == self)
            [live_items removeObject:v];
}

- (void)dealloc
{
    [self _gone];
    [_button _setItem:nil];
    [_button release];
    [_menu release];
    [_autosaveName release];
    [_view release];
    [_ids release];
    [_shownTip release];
    [_shownStatus release];
    [_refresh release];
    [super dealloc];
}

- (unsigned)_number { return _number; }

/* Something the menu bar shows changed: tell it once, after this turn of
 * the run loop, whatever else changes meanwhile. */
- (void)_changed
{
    if (_queued || _gone || !_itemObject)
        return;
    _queued = YES;
    [self performSelector:@selector(_announce) withObject:nil afterDelay:0];
}

- (void)_announce
{
    _queued = NO;
    if (_gone || !_itemObject)
        return;
    char path[64];
    snprintf(path, sizeof path, "/StatusNotifierItem/%u", _number);
    g_dbus_connection_emit_signal(bus, NULL, path, ITEM_IFACE, "NewIcon", NULL, NULL);
    NSString *tip = [_button toolTip] ?: @"";
    if (![tip isEqualToString:_shownTip ?: @""]) {
        [_shownTip release];
        _shownTip = [tip copy];
        g_dbus_connection_emit_signal(bus, NULL, path, ITEM_IFACE, "NewToolTip", NULL, NULL);
    }
    NSString *status = [self _status];
    if (![status isEqualToString:_shownStatus ?: @"Active"]) {
        [_shownStatus release];
        _shownStatus = [status copy];
        GVariant *arg = g_variant_new_string([status UTF8String]);
        g_dbus_connection_emit_signal(bus, NULL, path, ITEM_IFACE, "NewStatus", g_variant_new_tuple(&arg, 1), NULL);
    }
}

- (NSString *)_status
{
    return (_visible && ![_button isHidden]) ? @"Active" : @"Passive";
}

- (GVariant *)_property:(const char *)name
{
    if (!strcmp(name, "Category"))
        return g_variant_new_string("ApplicationStatus");
    if (!strcmp(name, "Id")) {
        NSString *ident = _autosaveName ?: [[NSBundle mainBundle] bundleIdentifier]
                                                ?: [[NSProcessInfo processInfo] processName];
        return g_variant_new_string([[NSString stringWithFormat:@"%@-%u", ident, _number] UTF8String]);
    }
    if (!strcmp(name, "Title")) {
        NSString *app = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]
                            ?: [[NSProcessInfo processInfo] processName];
        return g_variant_new_string([app ?: @"" UTF8String]);
    }
    if (!strcmp(name, "Status"))
        return g_variant_new_string([[self _status] UTF8String]);
    if (!strcmp(name, "WindowId"))
        return g_variant_new_int32(0);
    if (!strcmp(name, "IconName") || !strcmp(name, "AttentionIconName"))
        return g_variant_new_string("");
    if (!strcmp(name, "IconPixmap")) {
        GVariant *sizes[3];
        size_t n = 0;
        @autoreleasepool {
            for (int i = 0; i < 3; i++) {
                GVariant *p = picture(self, (int[]){16, 22, 32}[i]);
                if (p)
                    sizes[n++] = p;
            }
        }
        return g_variant_new_array("(iiay)", sizes, n);
    }
    if (!strcmp(name, "ToolTip")) {
        GVariant *parts[4] = {g_variant_new_string(""), g_variant_new_array("(iiay)", NULL, 0),
                              g_variant_new_string([[_button toolTip] ?: @"" UTF8String]), g_variant_new_string("")};
        return g_variant_new_tuple(parts, 4);
    }
    if (!strcmp(name, "ItemIsMenu"))
        return g_variant_new_boolean(_menu != nil);
    if (!strcmp(name, "Menu")) {
        char path[64];
        snprintf(path, sizeof path, "/MenuBar/%u", _number);
        return g_variant_new_object_path(_menu ? path : "/");
    }
    return NULL;
}

/* A click on an item without a menu: its button's action, as a click on a
 * Mac's menu bar item sends it. */
- (void)_activate
{
    if (_menu || ![_button isEnabled])
        return;
    SEL action = [_button action];
    if (action)
        [NSApp sendAction:action to:[_button target] from:_button];
}

- (GVariant *)_nodeFor:(NSMenuItem *)mi ident:(int)ident depth:(int)depth
{
    NSMenu *sub = ident == 0 ? _menu : [mi submenu];
    NSMutableArray *kids = [NSMutableArray array];
    if (sub && depth != 0) {
        for (NSMenuItem *child in [sub itemArray]) {
            NSUInteger known = [_ids indexOfObjectIdenticalTo:child];
            if (known == NSNotFound) {
                [_ids addObject:child];
                known = [_ids count] - 1;
            }
            int childIdent = (int)known + 1;
            GVariant *node = [self _nodeFor:child ident:childIdent depth:depth < 0 ? -1 : depth - 1];
            [kids addObject:[NSValue valueWithPointer:g_variant_new_variant(node)]];
        }
    }
    size_t n = [kids count];
    GVariant **children = calloc(n ? n : 1, sizeof *children);
    for (size_t i = 0; i < n; i++)
        children[i] = [kids[i] pointerValue];
    GVariant *props;
    if (ident == 0) {
        GVariant *pair = g_variant_new_dict_entry(g_variant_new_string("children-display"),
                                                  g_variant_new_variant(g_variant_new_string("submenu")));
        props = g_variant_new_array("{sv}", &pair, 1);
    } else {
        props = props_of(mi);
    }
    GVariant *parts[3] = {g_variant_new_int32(ident), props, g_variant_new_array("v", children, n)};
    free(children);
    return g_variant_new_tuple(parts, 3);
}

/* The whole menu is numbered afresh each time the menu bar reads it from
 * the top; a branch read on its own keeps the numbers it was given. */
- (GVariant *)_layoutFrom:(int)parent depth:(int)depth
{
    if (!_menu)
        return parent == 0 ? [self _nodeFor:nil ident:0 depth:0] : NULL;
    if (parent == 0) {
        [_ids removeAllObjects];
        _revision++;
        return [self _nodeFor:nil ident:0 depth:depth];
    }
    if (parent < 1 || parent > (int)[_ids count])
        return NULL;
    /* items already numbered keep their numbers; new ones get the next */
    return [self _nodeFor:_ids[parent - 1] ident:parent depth:depth];
}

- (GVariant *)_propertiesOf:(int)ident
{
    if (ident < 1 || ident > (int)[_ids count])
        return NULL;
    return props_of(_ids[ident - 1]);
}

- (BOOL)_aboutToShow:(int)ident
{
    NSMenu *fresh = ident == 0 && _refresh ? _refresh() : _menu;
    if (fresh != _menu)
        [self setMenu:fresh];
    NSMenu *menu = ident == 0 ? _menu
                   : (ident <= (int)[_ids count] ? [(NSMenuItem *)_ids[ident - 1] submenu] : nil);
    if (menu)
        menu_will_open(menu);
    return NO;
}

- (BOOL)_event:(int)ident
{
    if (ident < 1 || ident > (int)[_ids count])
        return NO;
    NSMenuItem *mi = [[_ids[ident - 1] retain] autorelease];
    if ([mi hasSubmenu] || [mi isSeparatorItem] || !item_enabled(mi))
        return NO;
    SEL action = [mi action];
    if (action)
        ASendMenuItemAction(mi);
    id d = [_menu delegate];
    if ([d respondsToSelector:@selector(menuDidClose:)])
        ((void (*)(id, SEL, id))objc_msgSend)(d, @selector(menuDidClose:), _menu);
    return YES;
}

/* ---- properties ---- */

- (NSStatusBar *)statusBar { return _bar; }
- (CGFloat)length { return _length; }
- (void)setLength:(CGFloat)l { _length = l; [self _changed]; }
- (NSMenu *)menu { return _menu; }
- (void)setMenu:(NSMenu *)menu
{
    [_menu autorelease];
    _menu = [menu retain];
    [_ids removeAllObjects];
    /* ItemIsMenu and Menu change with it; the menu bar reads them again on NewIcon */
    [self _changed];
}
- (NSStatusBarButton *)button { return _button; }
- (NSStatusItemBehavior)behavior { return _behavior; }
- (void)setBehavior:(NSStatusItemBehavior)b { _behavior = b; }
- (BOOL)isVisible { return _visible; }
- (void)setVisible:(BOOL)v { _visible = v; [self _changed]; }
- (NSString *)autosaveName { return _autosaveName; }
- (void)setAutosaveName:(NSString *)name
{
    [_autosaveName autorelease];
    _autosaveName = [name copy];
}

- (NSString *)title { return [_button title]; }
- (void)setTitle:(NSString *)t { [_button setTitle:t]; }
- (NSAttributedString *)attributedTitle { return [_button attributedTitle]; }
- (void)setAttributedTitle:(NSAttributedString *)t { [_button setAttributedTitle:t]; }
- (NSImage *)image { return [_button image]; }
- (void)setImage:(NSImage *)i { [_button setImage:i]; }
- (NSImage *)alternateImage { return [_button alternateImage]; }
- (void)setAlternateImage:(NSImage *)i { [_button setAlternateImage:i]; }
- (NSString *)toolTip { return [_button toolTip]; }
- (void)setToolTip:(NSString *)t { [_button setToolTip:t]; }
- (id)target { return [_button target]; }
- (void)setTarget:(id)t { [_button setTarget:t]; }
- (SEL)action { return [_button action]; }
- (void)setAction:(SEL)a { [_button setAction:a]; }
- (SEL)doubleAction { return _doubleAction; }
- (void)setDoubleAction:(SEL)a { _doubleAction = a; }
- (BOOL)isEnabled { return [_button isEnabled]; }
- (void)setEnabled:(BOOL)e { [_button setEnabled:e]; }
- (BOOL)highlightMode { return _highlightMode; }
- (void)setHighlightMode:(BOOL)f { _highlightMode = f; }
- (NSView *)view { return _view; }
- (void)setView:(NSView *)view
{
    [_view autorelease];
    _view = [view retain];
    [self _changed];
}
- (NSInteger)sendActionOn:(NSInteger)mask { return [_button sendActionOn:mask]; }
- (void)popUpStatusItemMenu:(NSMenu *)menu
{
    /* The desktop's menu bar opens menus itself; this one is kept, so the
     * next click on the item opens it. */
    AWarnOnce("popUpStatusItemMenu: the menu opens on the next click on the item instead");
    if (!_menu)
        [self setMenu:menu];
}
- (void)drawStatusBarBackgroundInRect:(NSRect)rect withHighlight:(BOOL)highlight {}
@end

id AMenuServe(const char *path, NSMenu *(^refresh)(void))
{
    NSStatusItem *item = [[[NSStatusItem alloc] _initServingMenuAt:path refresh:refresh] autorelease];
    [item setMenu:refresh()];
    return item;
}
