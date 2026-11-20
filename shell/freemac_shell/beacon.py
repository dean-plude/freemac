# SPDX-License-Identifier: GPL-3.0-or-later
"""Beacon: freemac's notifications.

Beacon owns org.freedesktop.Notifications on the session bus, so any app that
sends a desktop notification reaches it. New notifications show as banners in
the top-right corner; the notification centre (a calendar, Do Not Disturb and
the recent history) slides in from the right when the clock in Topline is
clicked. Topline talks to Beacon through the small org.freemac.Beacon
interface.

Preferences live in ~/.config/freemac/shell.json, written by Dials:
  "dnd": true/false          Do Not Disturb (banners hidden, history kept)
  "banner_seconds": 5        how long a normal banner stays
"""
import html
import json
import os
import re
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import style  # noqa: E402

BUS_NAME = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"
OWN_IFACE = "org.freemac.Beacon"
HISTORY = os.path.join(GLib.get_user_state_dir(), "freemac", "notifications.json")
KEEP = 50
MAX_BANNERS = 3

XML = f"""
<node>
  <interface name="org.freedesktop.Notifications">
    <method name="GetCapabilities"><arg type="as" direction="out"/></method>
    <method name="Notify">
      <arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
      <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/>
      <arg type="a{{sv}}" direction="in"/><arg type="i" direction="in"/>
      <arg type="u" direction="out"/>
    </method>
    <method name="CloseNotification"><arg type="u" direction="in"/></method>
    <method name="GetServerInformation">
      <arg type="s" direction="out"/><arg type="s" direction="out"/>
      <arg type="s" direction="out"/><arg type="s" direction="out"/>
    </method>
    <signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
    <signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
  </interface>
  <interface name="{OWN_IFACE}">
    <method name="ToggleCenter"/>
    <method name="ClearAll"/>
    <method name="Count"><arg type="u" direction="out"/></method>
    <method name="ShowLevel">
      <arg type="s" direction="in"/><arg type="d" direction="in"/><arg type="s" direction="in"/>
    </method>
  </interface>
</node>
"""

# Reasons for NotificationClosed, from the desktop notifications spec.
EXPIRED, DISMISSED, CLOSED_BY_CALL = 1, 2, 3

CSS = """
.beacon-card {
  background-color: @panel;
  border: 1px solid @edge;
  border-radius: 14px;
  padding: 10px 12px;
  color: @ink;
}
.beacon-card label { color: @ink; }
.beacon-card .beacon-app { color: @dim; font-size: 11px; }
.beacon-card .beacon-summary { font-weight: 700; }
.beacon-card .beacon-time { color: @dim; font-size: 11px; }
.beacon-card button.beacon-close { padding: 0; min-width: 20px; min-height: 20px; border-radius: 10px; }
.beacon-card button.beacon-action { padding: 2px 10px; }
.beacon-center {
  background-color: @panel;
  border: 1px solid @edge;
  border-radius: 16px;
  padding: 12px;
  color: @ink;
}
.beacon-center label { color: @ink; }
.beacon-center .beacon-heading { font-weight: 700; font-size: 15px; }
.beacon-center .beacon-empty { color: @dim; }
.beacon-center calendar { background: none; border: none; color: @ink; }
.beacon-level {
  background-color: @panel;
  border: 1px solid @edge;
  border-radius: 18px;
  padding: 14px 18px;
  color: @ink;
}
.beacon-level label { color: @ink; }
.beacon-level levelbar block.filled { background-color: @ink; border-radius: 3px; }
.beacon-level levelbar block.empty { background-color: alpha(@ink, 0.2); border-radius: 3px; }
"""


def plain(text):
    """Notification bodies may carry simple markup; show it as plain text."""
    text = re.sub(r"<[^>]+>", "", text or "")
    return html.unescape(text).strip()


class Note:
    def __init__(self, nid, app, icon, summary, body, actions, hints, timeout):
        self.id = nid
        self.app = app or ""
        self.icon = icon or ""
        self.summary = summary or ""
        self.body = body or ""
        # actions arrive as a flat list: [key, label, key, label, ...]
        self.actions = list(zip(actions[0::2], actions[1::2]))
        try:
            self.urgency = int(hints.get("urgency", 1))
        except (TypeError, ValueError):
            self.urgency = 1
        self.open_path = hints.get("x-freemac-open") or ""
        self.image_path = hints.get("image-path") or ""
        self.transient = bool(hints.get("transient", False))
        self.timeout = timeout
        self.when = time.time()

    def to_json(self):
        return {"id": self.id, "app": self.app, "icon": self.icon, "summary": self.summary,
                "body": self.body, "open": self.open_path, "when": self.when}

    @classmethod
    def from_json(cls, data):
        note = cls(data.get("id", 0), data.get("app"), data.get("icon"), data.get("summary"),
                   data.get("body"), [], {"x-freemac-open": data.get("open", "")}, -1)
        note.when = data.get("when", time.time())
        return note


def icon_image(note, size=32):
    """The notification's picture: an image file, an icon file, or a named icon."""
    for path in (note.image_path, note.icon):
        if path.startswith("file://"):
            path = path[7:]
        if path.startswith("/") and os.path.exists(path):
            try:
                return Gtk.Image.new_from_pixbuf(
                    GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True))
            except GLib.Error:
                pass
    name = note.icon if note.icon and "/" not in note.icon else "dialog-information-symbolic"
    image = Gtk.Image.new_from_icon_name(name, Gtk.IconSize.DND)
    image.set_pixel_size(size)
    return image


def when_text(stamp):
    age = time.time() - stamp
    if age < 60:
        return "now"
    if age < 3600:
        return f"{int(age // 60)} min ago"
    if time.localtime(stamp).tm_yday == time.localtime().tm_yday and age < 86400:
        return time.strftime("%-I:%M %p", time.localtime(stamp))
    return time.strftime("%b %-d", time.localtime(stamp))


class Card(Gtk.EventBox):
    """One notification, as a banner or as a row in the centre."""

    def __init__(self, beacon, note, in_center=False):
        super().__init__()
        self.beacon, self.note = beacon, note
        box = Gtk.Box(spacing=10)
        box.get_style_context().add_class("beacon-card")
        box.set_size_request(340, -1)
        self.add(box)
        box.pack_start(icon_image(note), False, False, 0)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        top = Gtk.Box(spacing=6)
        app = Gtk.Label(label=note.app or "Notification", xalign=0)
        app.get_style_context().add_class("beacon-app")
        top.pack_start(app, True, True, 0)
        stamp = Gtk.Label(label=when_text(note.when))
        stamp.get_style_context().add_class("beacon-time")
        top.pack_start(stamp, False, False, 0)
        text.pack_start(top, False, False, 0)
        if note.summary:
            summary = Gtk.Label(label=plain(note.summary), xalign=0, wrap=True, max_width_chars=34)
            summary.get_style_context().add_class("beacon-summary")
            text.pack_start(summary, False, False, 0)
        if note.body:
            body = Gtk.Label(label=plain(note.body), xalign=0, wrap=True, max_width_chars=38, lines=4)
            body.set_ellipsize(3)  # Pango.EllipsizeMode.END
            text.pack_start(body, False, False, 0)
        buttons = [(k, l) for k, l in note.actions if k != "default"]
        if buttons and not in_center:
            row = Gtk.Box(spacing=6, margin_top=4)
            for key, label in buttons[:3]:
                button = Gtk.Button(label=label)
                button.get_style_context().add_class("beacon-action")
                button.connect("clicked", lambda _b, k=key: beacon.invoke(note, k))
                row.pack_start(button, False, False, 0)
            text.pack_start(row, False, False, 0)
        box.pack_start(text, True, True, 0)
        close = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
        close.set_relief(Gtk.ReliefStyle.NONE)
        close.get_style_context().add_class("beacon-close")
        close.set_valign(Gtk.Align.START)
        close.set_tooltip_text("Clear" if in_center else "Close")
        close.connect("clicked", lambda *_: (beacon.forget(note) if in_center
                                             else beacon.close(note.id, DISMISSED)))
        box.pack_start(close, False, False, 0)
        self.connect("button-release-event", self._clicked)
        self.show_all()

    def _clicked(self, _widget, event):
        if event.button == 1:
            self.beacon.activate(self.note)
        return False


class Overlay(Gtk.Window):
    """A layer-shell window in the top-right corner."""

    def __init__(self, namespace, bottom=False, keyboard=False):
        super().__init__(title="Beacon")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, namespace)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        if bottom:
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
            GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, 10)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 34)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 10)
        if keyboard:
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)


class Beacon:
    def __init__(self):
        self.next_id = 1
        self.live = {}       # id -> (note, card, timer)
        self.history = self._load()
        self.connection = None
        self.banners = Overlay("freemac-beacon")
        self.banner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.banners.add(self.banner_box)
        self.center = None
        self.level = None
        self.level_timer = None
        provider = Gtk.CssProvider()
        self._provider = provider
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self._restyle()
        style.apply(on_change=lambda _dark: self._restyle())
        self._prefs_monitor = style.watch_prefs(lambda: None)
        info = Gio.DBusNodeInfo.new_for_xml(XML)
        self.interfaces = info.interfaces
        Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.REPLACE,
                         self._acquired, None, self._lost)

    # --- D-Bus -----------------------------------------------------------
    def _acquired(self, connection, _name):
        self.connection = connection
        for iface in self.interfaces:
            connection.register_object(PATH, iface, self._call, None, None)

    def _lost(self, _connection, _name):
        print("beacon: another notification service owns the bus name", file=sys.stderr)
        Gtk.main_quit()

    def _call(self, _conn, _sender, _path, iface, method, params, invocation):
        args = params.unpack()
        if method == "GetCapabilities":
            caps = ["body", "actions", "icon-static", "persistence", "body-hyperlinks"]
            invocation.return_value(GLib.Variant("(as)", (caps,)))
        elif method == "GetServerInformation":
            invocation.return_value(GLib.Variant("(ssss)", ("Beacon", "freemac", "0.5", "1.2")))
        elif method == "Notify":
            invocation.return_value(GLib.Variant("(u)", (self.notify(*args),)))
        elif method == "CloseNotification":
            self.close(args[0], CLOSED_BY_CALL)
            invocation.return_value(None)
        elif iface == OWN_IFACE and method == "ToggleCenter":
            self.toggle_center()
            invocation.return_value(None)
        elif iface == OWN_IFACE and method == "ClearAll":
            self.clear_all()
            invocation.return_value(None)
        elif iface == OWN_IFACE and method == "Count":
            invocation.return_value(GLib.Variant("(u)", (len(self.history),)))
        elif iface == OWN_IFACE and method == "ShowLevel":
            self.show_level(*args)
            invocation.return_value(None)
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

    def _emit(self, name, signature, values):
        if self.connection:
            self.connection.emit_signal(None, PATH, BUS_NAME, name, GLib.Variant(signature, values))

    # --- volume and brightness keys --------------------------------------
    def show_level(self, icon, fraction, label):
        """The panel near the bottom that shows a level after a key press."""
        if self.level is None:
            self.level = Gtk.Window(title="Level")
            style.make_transparent(self.level)
            GtkLayerShell.init_for_window(self.level)
            GtkLayerShell.set_layer(self.level, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_namespace(self.level, "freemac-level")
            GtkLayerShell.set_anchor(self.level, GtkLayerShell.Edge.BOTTOM, True)
            GtkLayerShell.set_margin(self.level, GtkLayerShell.Edge.BOTTOM, 120)
            box = Gtk.Box(spacing=12)
            box.get_style_context().add_class("beacon-level")
            self.level_icon = Gtk.Image()
            self.level_icon.set_pixel_size(24)
            self.level_bar = Gtk.LevelBar(min_value=0, max_value=1, valign=Gtk.Align.CENTER)
            self.level_bar.set_size_request(200, 6)
            self.level_label = Gtk.Label()
            box.pack_start(self.level_icon, False, False, 0)
            box.pack_start(self.level_bar, True, True, 0)
            box.pack_start(self.level_label, False, False, 0)
            self.level.add(box)
            box.show_all()
        self.level_icon.set_from_icon_name(icon or "dialog-information-symbolic", Gtk.IconSize.LARGE_TOOLBAR)
        self.level_bar.set_visible(fraction >= 0)
        self.level_bar.set_value(min(1.0, max(0.0, fraction)))
        self.level_label.set_text(label)
        self.level_label.set_visible(bool(label))
        self.level.resize(1, 1)
        self.level.show()
        if self.level_timer:
            GLib.source_remove(self.level_timer)
        self.level_timer = GLib.timeout_add(1500, self._hide_level)

    def _hide_level(self):
        self.level_timer = None
        self.level.hide()
        return False

    # --- notifications ---------------------------------------------------
    def notify(self, app, replaces, icon, summary, body, actions, hints, timeout):
        known = replaces in self.live or any(n.id == replaces for n in self.history)
        nid = replaces if replaces and known else self.next_id
        if nid == self.next_id:
            self.next_id += 1
        else:
            self._drop_banner(nid)
        note = Note(nid, app, icon, summary, body, actions, hints, timeout)
        if not note.transient:
            self.history = [n for n in self.history if n.id != nid]
            self.history.insert(0, note)
            del self.history[KEEP:]
            self._save()
        prefs = style.prefs()
        quiet = prefs.get("dnd") and note.urgency < 2
        if self.center and self.center.get_visible():
            self._fill_center()
        elif not quiet:
            self._show_banner(note, prefs)
        return nid

    def _show_banner(self, note, prefs):
        card = Card(self, note)
        self.banner_box.pack_start(card, False, False, 0)
        timer = None
        if note.urgency < 2 and note.timeout != 0:
            seconds = note.timeout / 1000 if note.timeout > 0 else float(prefs.get("banner_seconds", 5))
            timer = GLib.timeout_add(int(max(1.0, seconds) * 1000), self._expire, note.id)
        self.live[note.id] = (note, card, timer)
        cards = [c for c in self.banner_box.get_children()]
        for old in cards[:-MAX_BANNERS]:
            self._drop_banner(old.note.id)
        self.banners.show_all()

    def _expire(self, nid):
        entry = self.live.get(nid)
        if entry:
            self.live[nid] = (entry[0], entry[1], None)
            self.close(nid, EXPIRED)
        return False

    def _drop_banner(self, nid):
        entry = self.live.pop(nid, None)
        if not entry:
            return
        _note, card, timer = entry
        if timer:
            GLib.source_remove(timer)
        if card:
            card.destroy()
        if not self.banner_box.get_children():
            self.banners.hide()
        self.banners.resize(1, 1)

    def close(self, nid, reason):
        if nid in self.live:
            self._drop_banner(nid)
            self._emit("NotificationClosed", "(uu)", (nid, reason))

    def invoke(self, note, key):
        self._emit("ActionInvoked", "(us)", (note.id, key))
        self.close(note.id, DISMISSED)

    def activate(self, note):
        """A click on the notification itself."""
        if any(key == "default" for key, _label in note.actions):
            self.invoke(note, "default")
            return
        if note.open_path and os.path.exists(note.open_path):
            try:
                Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(note.open_path).get_uri(), None)
            except GLib.Error:
                pass
        self.close(note.id, DISMISSED)
        if self.center and self.center.get_visible():
            self.center.hide()

    def forget(self, note):
        self.history = [n for n in self.history if n is not note]
        self._save()
        self._fill_center()

    def clear_all(self):
        self.history = []
        self._save()
        for nid in list(self.live):
            self.close(nid, DISMISSED)
        if self.center:
            self._fill_center()

    # --- centre ----------------------------------------------------------
    def toggle_center(self):
        if self.center and self.center.get_visible():
            self.center.hide()
            return
        if not self.center:
            self._build_center()
        for nid in list(self.live):
            self._drop_banner(nid)
        self._fill_center()
        self.center.show_all()
        self.center.present()

    def _build_center(self):
        self.center = Overlay("freemac-beacon-center", bottom=True, keyboard=True)
        self.center.connect("key-press-event", self._center_key)
        self.center.connect("delete-event", lambda *_: self.center.hide() or True)
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        outer.get_style_context().add_class("beacon-center")
        outer.set_size_request(364, -1)
        self.center.add(outer)
        date = Gtk.Label(xalign=0)
        date.get_style_context().add_class("beacon-heading")
        self.date_label = date
        outer.pack_start(date, False, False, 0)
        outer.pack_start(Gtk.Calendar(), False, False, 0)
        row = Gtk.Box(spacing=8)
        heading = Gtk.Label(label="Notifications", xalign=0)
        heading.get_style_context().add_class("beacon-heading")
        row.pack_start(heading, True, True, 0)
        row.pack_start(Gtk.Label(label="Do Not Disturb"), False, False, 0)
        self.dnd = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.dnd_handler = self.dnd.connect("notify::active", self._dnd_toggled)
        row.pack_start(self.dnd, False, False, 0)
        outer.pack_start(row, False, False, 0)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_vexpand(True)
        scroller.set_min_content_height(260)
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        scroller.add(self.list_box)
        outer.pack_start(scroller, True, True, 0)
        clear = Gtk.Button(label="Clear All", halign=Gtk.Align.END)
        clear.connect("clicked", lambda *_: self.clear_all())
        outer.pack_start(clear, False, False, 0)

    def _fill_center(self):
        if not self.center:
            return
        self.date_label.set_text(time.strftime("%A, %B %-d"))
        with self.dnd.handler_block(self.dnd_handler):
            self.dnd.set_active(bool(style.prefs().get("dnd")))
        for child in self.list_box.get_children():
            child.destroy()
        if not self.history:
            empty = Gtk.Label(label="No notifications")
            empty.get_style_context().add_class("beacon-empty")
            empty.set_margin_top(24)
            self.list_box.pack_start(empty, False, False, 0)
        for note in self.history:
            self.list_box.pack_start(Card(self, note, in_center=True), False, False, 0)
        self.list_box.show_all()

    def _center_key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.center.hide()
            return True
        return False

    def _dnd_toggled(self, switch, _param):
        write_pref("dnd", switch.get_active())

    # --- storage and look ------------------------------------------------
    def _load(self):
        try:
            with open(HISTORY) as f:
                notes = [Note.from_json(d) for d in json.load(f)]
        except (OSError, ValueError, TypeError, AttributeError):
            return []
        if notes:
            self.next_id = max(n.id for n in notes) + 1
        return notes[:KEEP]

    def _save(self):
        try:
            os.makedirs(os.path.dirname(HISTORY), exist_ok=True)
            tmp = HISTORY + ".tmp"
            with open(tmp, "w") as f:
                json.dump([n.to_json() for n in self.history], f)
            os.replace(tmp, HISTORY)
        except OSError:
            pass

    def _restyle(self):
        text = CSS
        for key, value in (style.DARK if style.is_dark() else style.LIGHT).items():
            text = text.replace("@" + key + ";", value + ";")
        self._provider.load_from_data(text.encode())


def write_pref(key, value):
    """Change one key in shell.json, keeping the others."""
    data = style.prefs()
    data[key] = value
    os.makedirs(os.path.dirname(style.PREFS), exist_ok=True)
    tmp = style.PREFS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, style.PREFS)


def call(method):
    """Ask the running Beacon to do something (used by Topline and the CLI)."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        reply = bus.call_sync(BUS_NAME, PATH, OWN_IFACE, method, None, None,
                              Gio.DBusCallFlags.NONE, 2000, None)
        return reply.unpack() if reply else None
    except GLib.Error:
        return None


def send(summary, body="", icon="", app="freemac", open_path=""):
    """Send a desktop notification from freemac's own tools."""
    hints = {}
    if open_path:
        hints["x-freemac-open"] = GLib.Variant("s", open_path)
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call_sync(BUS_NAME, PATH, BUS_NAME, "Notify",
                      GLib.Variant("(susssasa{sv}i)", (app, 0, icon, summary, body, [], hints, -1)),
                      GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 2000, None)
        return True
    except GLib.Error:
        return False


def main():
    if "--center" in sys.argv[1:]:
        if call("ToggleCenter") is None:
            print("Beacon isn't running.", file=sys.stderr)
            sys.exit(1)
        return
    if "--clear" in sys.argv[1:]:
        call("ClearAll")
        return
    Beacon()
    Gtk.main()


if __name__ == "__main__":
    main()
