# SPDX-License-Identifier: GPL-3.0-or-later
"""Menu bar extras: the icons that apps put in the menu bar, as on a Mac.

Linux apps (chat apps, cloud storage, password managers, Ferry's Mac apps)
show these through the freedesktop StatusNotifierItem protocol and give their
menus through the dbusmenu protocol. Topline is the StatusNotifierWatcher
that apps register with, and the host that shows them: each extra is a button
in the menu bar, left of freemac's own symbols, newest furthest left.
Clicking one opens its menu, or asks the app to open its window when the app
has no menu. Written from the public protocol descriptions; original code.
"""
import re

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
ITEM = "org.kde.StatusNotifierItem"
DBUSMENU = "com.canonical.dbusmenu"
SIZE = 16

WATCHER_XML = """
<node>
  <interface name="org.kde.StatusNotifierWatcher">
    <method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method>
    <method name="RegisterStatusNotifierHost"><arg type="s" direction="in"/></method>
    <property name="RegisteredStatusNotifierItems" type="as" access="read"/>
    <property name="IsStatusNotifierHostRegistered" type="b" access="read"/>
    <property name="ProtocolVersion" type="i" access="read"/>
    <signal name="StatusNotifierItemRegistered"><arg type="s"/></signal>
    <signal name="StatusNotifierItemUnregistered"><arg type="s"/></signal>
    <signal name="StatusNotifierHostRegistered"/>
    <signal name="StatusNotifierHostUnregistered"/>
  </interface>
</node>
"""


def split_service(service, sender):
    """An item registers with its bus name (its object is then at
    /StatusNotifierItem) or with an object path on the sender's own name."""
    if service.startswith("/"):
        return sender, service
    if "/" in service:
        name, path = service.split("/", 1)
        return name, "/" + path
    return service, "/StatusNotifierItem"


def plain_label(text):
    """dbusmenu marks the access key with "_" and writes a real one as "__".
    Mac menus show no access keys."""
    return (text or "").replace("__", "\0").replace("_", "").replace("\0", "_")


def plain_text(markup):
    """Tooltip text may hold simple HTML-like markup."""
    text = re.sub(r"<br\s*/?>", "\n", markup or "", flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    return (text.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"')
            .replace("&apos;", "'").replace("&amp;", "&")).strip()


def pixmap_to_pixbuf(pixmaps, size=SIZE):
    """IconPixmap is a list of (width, height, ARGB32 bytes, big-endian):
    the smallest one at least as big as needed, scaled to the bar."""
    best = None
    for width, height, data in pixmaps or []:
        if width <= 0 or height <= 0 or len(data) < width * height * 4:
            continue
        if best is None or (best[0] < size <= width) or (width >= size and width < best[0]) \
                or (best[0] < size and width > best[0]):
            best = (width, height, bytes(data))
    if best is None:
        return None
    width, height, data = best
    rgba = bytearray(len(data))
    rgba[0::4], rgba[1::4], rgba[2::4], rgba[3::4] = data[1::4], data[2::4], data[3::4], data[0::4]
    pixbuf = GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(bytes(rgba)), GdkPixbuf.Colorspace.RGB,
                                             True, 8, width, height, width * 4)
    if width != size or height != size:
        scale = size / max(width, height)
        pixbuf = pixbuf.scale_simple(max(1, round(width * scale)), max(1, round(height * scale)),
                                     GdkPixbuf.InterpType.BILINEAR)
    return pixbuf


class Watcher:
    """The registry apps announce their items to. If another program already
    keeps it, Topline only reads that one."""

    def __init__(self, on_added, on_removed):
        self.on_added, self.on_removed = on_added, on_removed
        self.items = []             # "name/path" in the order they came
        self.watches = {}
        self.conn = None
        self.registration = None
        self.outside = None
        info = Gio.DBusNodeInfo.new_for_xml(WATCHER_XML)
        self.iface = info.interfaces[0]
        self.owner = Gio.bus_own_name(Gio.BusType.SESSION, WATCHER,
                                      Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT | Gio.BusNameOwnerFlags.REPLACE,
                                      self._bus_acquired, None, self._name_lost)

    # -- keeping it ---------------------------------------------------------

    def _bus_acquired(self, conn, _name):
        self.conn = conn
        try:
            self.registration = conn.register_object(WATCHER_PATH, self.iface, self._call, self._get, None)
        except GLib.Error:
            self.registration = None

    def _name_lost(self, conn, _name):
        """Someone else keeps the registry: show the items it knows of."""
        if conn is None or self.outside is not None:
            return
        self.conn = conn
        if self.registration:
            conn.unregister_object(self.registration)
            self.registration = None
        try:
            self.outside = Gio.DBusProxy.new_sync(conn, Gio.DBusProxyFlags.NONE, None, WATCHER,
                                                  WATCHER_PATH, WATCHER, None)
            self.outside.call_sync("RegisterStatusNotifierHost",
                                   GLib.Variant("(s)", ("org.freedesktop.StatusNotifierHost-topline",)),
                                   Gio.DBusCallFlags.NONE, 1000, None)
        except GLib.Error:
            self.outside = None
            return
        self.outside.connect("g-signal", self._outside_signal)
        found = self.outside.get_cached_property("RegisteredStatusNotifierItems")
        for service in found.unpack() if found else []:
            name, path = split_service(service, None)
            if name:
                self._add(name, path)

    def _outside_signal(self, _proxy, _sender, signal, params):
        service = params.unpack()[0] if params.n_children() else ""
        name, path = split_service(service, None)
        if signal == "StatusNotifierItemRegistered" and name:
            self._add(name, path)
        elif signal == "StatusNotifierItemUnregistered" and name:
            self._remove(f"{name}{path}")

    def _call(self, conn, sender, _path, _iface, method, params, invocation):
        if method == "RegisterStatusNotifierItem":
            name, path = split_service(params.unpack()[0], sender)
            if name:
                self._add(name, path)
            invocation.return_value(None)
        elif method == "RegisterStatusNotifierHost":
            invocation.return_value(None)
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

    def _get(self, _conn, _sender, _path, _iface, prop):
        if prop == "RegisteredStatusNotifierItems":
            return GLib.Variant("as", self.items)
        if prop == "IsStatusNotifierHostRegistered":
            return GLib.Variant("b", True)
        if prop == "ProtocolVersion":
            return GLib.Variant("i", 0)
        return None

    def _emit(self, signal, *args):
        if self.conn is None or self.registration is None:
            return
        params = GLib.Variant("(s)", args) if args else None
        try:
            self.conn.emit_signal(None, WATCHER_PATH, WATCHER, signal, params)
        except GLib.Error:
            pass

    # -- the list -----------------------------------------------------------

    def _add(self, name, path):
        key = f"{name}{path}"
        if key in self.items:
            return
        self.items.append(key)
        # An app that quits, or crashes, takes its item with it.
        if name not in self.watches:
            self.watches[name] = self.conn.signal_subscribe(
                "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus",
                name, Gio.DBusSignalFlags.NONE, self._owner_changed)
        self._emit("StatusNotifierItemRegistered", key)
        self.on_added(key, name, path)

    def _owner_changed(self, _conn, _sender, _path, _iface, _signal, params):
        name, _old, new = params.unpack()
        if new:
            return
        for key in [k for k in self.items if k.split("/", 1)[0] == name]:
            self._remove(key)
        watch = self.watches.pop(name, None)
        if watch:
            self.conn.signal_unsubscribe(watch)

    def _remove(self, key):
        if key not in self.items:
            return
        self.items.remove(key)
        self._emit("StatusNotifierItemUnregistered", key)
        self.on_removed(key)


class DBusMenu:
    """An app's menu, read through dbusmenu each time it opens."""

    def __init__(self, conn, name, path):
        self.conn, self.name, self.path = conn, name, path

    def _call(self, method, params, reply="", timeout=1500):
        return self.conn.call_sync(self.name, self.path, DBUSMENU, method, params,
                                   GLib.VariantType.new(reply) if reply else None,
                                   Gio.DBusCallFlags.NONE, timeout, None)

    def layout(self):
        try:
            self._call("AboutToShow", GLib.Variant("(i)", (0,)), "(b)", 500)
        except GLib.Error:
            pass
        try:
            _revision, tree = self._call("GetLayout", GLib.Variant("(iias)", (0, -1, [])),
                                         "(u(ia{sv}av))").unpack()
        except GLib.Error:
            return None
        return tree

    def clicked(self, item_id):
        try:
            self.conn.call(self.name, self.path, DBUSMENU, "Event",
                           GLib.Variant("(isvu)", (item_id, "clicked", GLib.Variant("i", 0),
                                                   int(GLib.get_monotonic_time() // 1000) & 0xFFFFFFFF)),
                           None, Gio.DBusCallFlags.NONE, 1500, None, None)
        except GLib.Error:
            pass

    def opened(self, item_id):
        try:
            self._call("AboutToShow", GLib.Variant("(i)", (item_id,)), "(b)", 500)
        except GLib.Error:
            pass

    def fill(self, menu, tree):
        """Fill a Gtk.Menu with the items under tree, (id, properties, children).
        Check and radio items show a plain tick before their name, as Mac
        menus do, and every item in such a menu leaves room for one."""
        for child in menu.get_children():
            menu.remove(child)
        shown = [entry for entry in tree[2] if entry[1].get("visible", True)]
        ticks = any(entry[1].get("toggle-type") in ("checkmark", "radio") for entry in shown)
        for entry in shown:
            item_id, props, children = entry
            if props.get("type") == "separator":
                menu.append(Gtk.SeparatorMenuItem())
                continue
            label = plain_label(props.get("label", ""))
            item = Gtk.MenuItem()
            line = Gtk.Box(spacing=0)
            if ticks:
                on = props.get("toggle-type") in ("checkmark", "radio") and props.get("toggle-state", 0) == 1
                tick = Gtk.Label(label="\u2713" if on else "", xalign=0)
                tick.set_size_request(18, -1)
                line.pack_start(tick, False, False, 0)
            line.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
            item.add(line)
            item.set_sensitive(props.get("enabled", True))
            if children or props.get("children-display") == "submenu":
                sub = Gtk.Menu()
                self.fill(sub, entry)
                sub.connect("show", lambda _m, i=item_id: self.opened(i))
                item.set_submenu(sub)
            else:
                item.connect("activate", lambda _w, i=item_id: self.clicked(i))
            menu.append(item)
        menu.show_all()


class Extra(Gtk.Button):
    """One app's icon in the menu bar."""

    def __init__(self, conn, name, path):
        super().__init__()
        self.conn, self.name, self.path = conn, name, path
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.get_style_context().add_class("status")
        self.get_style_context().add_class("menu-extra")
        self.image = Gtk.Image()
        self.image.set_pixel_size(SIZE)
        self.add(self.image)
        self.set_no_show_all(True)
        self.props = {}
        self.menu = Gtk.Menu()
        self.menu.set_halign(Gtk.Align.END)
        self.menu.connect("hide", lambda *_: self.get_style_context().remove_class("open"))
        self.connect("button-press-event", self._pressed)
        self.connect("scroll-event", self._scrolled)
        self.subscription = conn.signal_subscribe(name, ITEM, None, path, None, Gio.DBusSignalFlags.NONE,
                                                  lambda *_a: self._refresh_soon())
        self._queued = False
        self.refresh()

    def gone(self):
        self.conn.signal_unsubscribe(self.subscription)
        self.menu.popdown()
        self.destroy()

    # -- what it shows -----------------------------------------------------

    def _refresh_soon(self):
        # Apps often send several New... signals at once.
        if not self._queued:
            self._queued = True
            GLib.timeout_add(80, self.refresh)

    def refresh(self):
        self._queued = False
        self.conn.call(self.name, self.path, "org.freedesktop.DBus.Properties", "GetAll",
                       GLib.Variant("(s)", (ITEM,)), GLib.VariantType.new("(a{sv})"),
                       Gio.DBusCallFlags.NONE, 2000, None, self._got)
        return False

    def _got(self, conn, result):
        try:
            self.props = conn.call_finish(result).unpack()[0]
        except GLib.Error:
            return
        self.show_props()

    def show_props(self):
        props = self.props
        status = props.get("Status", "Active")
        if status == "Passive":
            self.hide()
            return
        theme_path = props.get("IconThemePath") or ""
        if theme_path and theme_path not in Gtk.IconTheme.get_default().get_search_path():
            Gtk.IconTheme.get_default().append_search_path(theme_path)
        if status == "NeedsAttention" and (props.get("AttentionIconName") or props.get("AttentionIconPixmap")):
            name, pixmaps = props.get("AttentionIconName"), props.get("AttentionIconPixmap")
        else:
            name, pixmaps = props.get("IconName"), props.get("IconPixmap")
        self._set_icon(name, pixmaps)
        tip = props.get("ToolTip")
        words = ""
        if tip and len(tip) >= 4:
            words = "\n".join(w for w in (plain_text(tip[2]), plain_text(tip[3])) if w)
        self.set_tooltip_text(words or props.get("Title") or None)
        self.show()
        self.image.show()

    def _set_icon(self, name, pixmaps):
        if name and name.startswith("/"):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(name, SIZE, SIZE)
                self.image.set_from_pixbuf(pixbuf)
                return
            except GLib.Error:
                pass
        theme = Gtk.IconTheme.get_default()
        if name and theme.has_icon(name):
            self.image.set_from_icon_name(name, Gtk.IconSize.MENU)
            self.image.set_pixel_size(SIZE)
            return
        pixbuf = pixmap_to_pixbuf(pixmaps)
        if pixbuf is not None:
            self.image.set_from_pixbuf(pixbuf)
        else:
            self.image.set_from_icon_name("application-x-executable-symbolic", Gtk.IconSize.MENU)
            self.image.set_pixel_size(SIZE)

    # -- clicks --------------------------------------------------------------

    def _menu_path(self):
        path = self.props.get("Menu")
        return path if path and path != "/" else None

    def _pressed(self, _widget, event):
        if event.type != Gdk.EventType.BUTTON_PRESS:
            return True
        if event.button == 2:
            self._item_call("SecondaryActivate", GLib.Variant("(ii)", (0, 0)))
            return True
        wants_menu = event.button == 3 or self.props.get("ItemIsMenu", False)
        if self._menu_path() and wants_menu:
            self.open_menu(event)
        elif event.button == 3:
            self._item_call("ContextMenu", GLib.Variant("(ii)", (0, 0)))
        else:
            # No menu, or an app that opens its window on a click; if it
            # doesn't answer Activate, its menu opens instead.
            self._item_call("Activate", GLib.Variant("(ii)", (0, 0)),
                            fallback=(lambda: self.open_menu(event)) if self._menu_path() else None)
        return True

    def _scrolled(self, _widget, event):
        ok, dx, dy = event.get_scroll_deltas()
        if not ok:
            return False
        if dy:
            self._item_call("Scroll", GLib.Variant("(is)", (int(dy * 10) or (1 if dy > 0 else -1), "vertical")))
        if dx:
            self._item_call("Scroll", GLib.Variant("(is)", (int(dx * 10) or (1 if dx > 0 else -1), "horizontal")))
        return True

    def _item_call(self, method, params, fallback=None):
        def done(conn, result):
            try:
                conn.call_finish(result)
            except GLib.Error:
                if fallback:
                    fallback()
        self.conn.call(self.name, self.path, ITEM, method, params, None,
                       Gio.DBusCallFlags.NONE, 1500, None, done)

    def open_menu(self, event=None):
        menu = DBusMenu(self.conn, self.name, self._menu_path())
        tree = menu.layout()
        if not tree or not tree[2]:
            return
        menu.fill(self.menu, tree)
        self.get_style_context().add_class("open")
        self.menu.popup_at_widget(self, 8, 2, event)    # GDK_GRAVITY_SOUTH_EAST, NORTH_EAST


class Extras(Gtk.Box):
    """The menu bar's extras, left of freemac's own symbols."""

    def __init__(self):
        super().__init__(spacing=0)
        self.buttons = {}
        self.conn = None
        self.watcher = Watcher(self._added, self._removed)

    def _added(self, key, name, path):
        conn = self.watcher.conn or Gio.bus_get_sync(Gio.BusType.SESSION, None)
        button = Extra(conn, name, path)
        self.buttons[key] = button
        # Newest furthest left, as on a Mac.
        self.pack_end(button, False, False, 0)
        self.show()

    def _removed(self, key):
        button = self.buttons.pop(key, None)
        if button is not None:
            button.gone()
