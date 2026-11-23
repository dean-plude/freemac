# SPDX-License-Identifier: GPL-3.0-or-later
"""Beacon: freemac's notifications.

Beacon owns org.freedesktop.Notifications on the session bus, so any app that
sends a desktop notification reaches it. New notifications show as banners in
the top-right corner; the notification centre (a calendar, Focus and
the recent history) slides in from the right when the clock in Topline is
clicked. Topline talks to Beacon through the small org.freemac.Beacon
interface.

Preferences live in ~/.config/freemac/shell.json, written by Dials:
  "focus", "dnd"             the Focus on by hand (banners hidden, history kept,
                             except for the apps that Focus allows)
  "banner_seconds": 5        how long a normal banner stays
  "dnd_schedule", "focus_settings", "notify_apps"
                             each Focus's schedule and allowed apps, and each
                             app's choice (see notify_rules.py)
"""
import datetime as dt
import html
import json
import os
import re
import sys
import time
import urllib.parse

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import announce, calendar_store, minimonth, notify_rules, reminders_store, style, update_notice  # noqa: E402

BUS_NAME = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"
OWN_IFACE = "org.freemac.Beacon"
SNOOZE, SNOOZE_MINUTES = "x-freemac-snooze", 5
DONE = "x-freemac-done"   # Nudge: mark the reminder completed
HISTORY = os.path.join(GLib.get_user_state_dir(), "freemac", "notifications.json")
APPS = os.path.join(GLib.get_user_state_dir(), "freemac", "notification-apps.json")
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
    <method name="UpdatesChanged"/>
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
.beacon-center .beacon-group { font-weight: 700; font-size: 13px; }
.beacon-center button.beacon-more { padding: 1px 8px; border-radius: 10px; font-size: 12px; }
.beacon-center button.beacon-close { padding: 0; min-width: 20px; min-height: 20px; border-radius: 10px; }
.beacon-center .beacon-stack-1, .beacon-center .beacon-stack-2 {
  background-color: alpha(@ink, 0.05);
  border: 1px solid @edge;
  border-top: none;
  border-radius: 0 0 12px 12px;
}
.beacon-center .beacon-stack-1 { margin: 0 8px; }
.beacon-center .beacon-stack-2 { margin: 0 16px; opacity: 0.7; }
.beacon-center .beacon-day { color: @dim; font-size: 12px; font-weight: 700; }
.beacon-center button.beacon-event { padding: 3px 6px; border-radius: 8px; }
.beacon-center .beacon-event-time { color: @dim; font-size: 12px; }
.beacon-center .beacon-dot { color: @theme_selected_bg_color; }
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
        self.open_uri = hints.get("x-freemac-uri") or ""   # passed to app_command
        self.image_path = hints.get("image-path") or ""
        self.transient = bool(hints.get("transient", False))
        self.timeout = timeout
        self.when = time.time()

    def to_json(self):
        return {"id": self.id, "app": self.app, "icon": self.icon, "summary": self.summary,
                "body": self.body, "open": self.open_path, "uri": self.open_uri, "when": self.when}

    @classmethod
    def from_json(cls, data):
        note = cls(data.get("id", 0), data.get("app"), data.get("icon"), data.get("summary"),
                   data.get("body"), [], {"x-freemac-open": data.get("open", ""),
                                          "x-freemac-uri": data.get("uri", "")}, -1)
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
    # GLib apps send a named icon as image-path; the icon itself may be empty.
    name = next((n for n in (note.image_path, note.icon) if n and "/" not in n), "dialog-information-symbolic")
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

    on_click = None

    def _clicked(self, _widget, event):
        if event.button == 1 and self.on_click:
            self.on_click()
        elif event.button == 1:
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
        self.expanded = set()   # apps whose notifications are spread out in the centre
        self.history = self._load()
        self.events = []
        self.alert_events, self.alert_stamp = [], None
        self.reminder_lists, self.reminder_stamp = [], None
        self.alerts_until = dt.datetime.now() - dt.timedelta(minutes=1)
        GLib.timeout_add_seconds(15, self._check_alerts)
        self.updates = update_notice.Watch(self._updates_ready, self._freemac_ready, self._freemac_installed)
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
        elif iface == OWN_IFACE and method == "UpdatesChanged":
            self.updates.look(refresh=False)   # Harbor checked or installed: count again
            invocation.return_value(None)
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
        prefs = style.prefs()
        notify_rules.remember_app(APPS, note.app, note.icon)
        choice = notify_rules.app_style(prefs, note.app)
        if choice == "off" and note.urgency < 2:
            return nid          # turned off for this app in Dials: not shown, not kept
        if not note.transient:
            self.history = [n for n in self.history if n.id != nid]
            self.history.insert(0, note)
            del self.history[KEEP:]
            self._save()
        quiet = (not notify_rules.allowed(prefs, note.app) or choice == "list") and note.urgency < 2
        if self.center and self.center.get_visible():
            self._fill_center()
        elif not quiet:
            self._show_banner(note, prefs)
            announce.notification(prefs, note.app, note.summary)
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
        if key == SNOOZE:
            # Tide's alerts and Nudge's reminders: show it again in a few minutes.
            self.close(note.id, DISMISSED)
            actions = [part for pair in note.actions for part in pair]
            GLib.timeout_add_seconds(SNOOZE_MINUTES * 60, lambda: self.notify(
                note.app, 0, note.icon, note.summary, note.body, actions,
                {"x-freemac-uri": note.open_uri}, 0) and False)
            return
        if key == DONE and note.open_uri.startswith("nudge-reminder:"):
            self._complete_reminder(urllib.parse.unquote(note.open_uri.split(":", 1)[1]))
            self.close(note.id, DISMISSED)
            return
        self._emit("ActionInvoked", "(us)", (note.id, key))
        self.close(note.id, DISMISSED)

    def activate(self, note):
        """A click on the notification itself."""
        if any(key == "default" for key, _label in note.actions):
            self.invoke(note, "default")
            return
        if note.open_uri == "harbor:updates":
            try:
                GLib.spawn_async(["freemac-harbor", "--updates"], flags=GLib.SpawnFlags.SEARCH_PATH)
            except GLib.Error:
                pass
        elif note.open_uri == "dials:softwareupdate":
            try:
                GLib.spawn_async(["freemac-dials", "--panel", "softwareupdate"], flags=GLib.SpawnFlags.SEARCH_PATH)
            except GLib.Error:
                pass
        elif note.open_uri.startswith(("tide-event:", "nudge-reminder:")):
            program = "freemac-tide" if note.open_uri.startswith("tide-event:") else "freemac-nudge"
            try:
                GLib.spawn_async([program, note.open_uri], flags=GLib.SpawnFlags.SEARCH_PATH)
            except GLib.Error:
                pass
        elif note.open_path and os.path.exists(note.open_path):
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

    def forget_app(self, app):
        """The x on an app's group in the centre: clear all of its notifications."""
        self.history = [n for n in self.history if (n.app or "") != app]
        self.expanded.discard(app)
        self._save()
        self._fill_center()

    def toggle_group(self, app):
        if app in self.expanded:
            self.expanded.discard(app)
        else:
            self.expanded.add(app)
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
        # The month, with a dot under days that have events in Tide, and
        # the chosen day's events under it; a click on one opens Tide.
        self.month = minimonth.MiniMonth(picked=self._show_events, marked=self._event_days)
        self.month.set_halign(Gtk.Align.CENTER)
        outer.pack_start(self.month, False, False, 0)
        self.events_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        outer.pack_start(self.events_box, False, False, 0)
        row = Gtk.Box(spacing=8)
        heading = Gtk.Label(label="Notifications", xalign=0)
        heading.get_style_context().add_class("beacon-heading")
        row.pack_start(heading, True, True, 0)
        # Focus, as on a Mac: Do Not Disturb, Sleep, Work or Personal.
        row.pack_start(Gtk.Label(label="Focus"), False, False, 0)
        self.dnd = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        self.dnd.append("", "Off")
        for focus, name, _icon, _start in notify_rules.FOCUSES:
            self.dnd.append(focus, name)
        self.dnd_handler = self.dnd.connect("changed", self._dnd_toggled)
        row.pack_start(self.dnd, False, False, 0)
        outer.pack_start(row, False, False, 0)
        self.dnd_note = Gtk.Label(xalign=1)
        self.dnd_note.get_style_context().add_class("beacon-empty")
        self.dnd_note.set_no_show_all(True)
        outer.pack_start(self.dnd_note, False, False, 0)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_vexpand(True)
        scroller.set_min_content_height(260)
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        scroller.add(self.list_box)
        outer.pack_start(scroller, True, True, 0)
        clear = Gtk.Button(label="Clear All", halign=Gtk.Align.END)
        clear.connect("clicked", lambda *_: self.clear_all())
        outer.pack_start(clear, False, False, 0)

    def _event_days(self, first, last):
        days = set()
        for occ in calendar_store.occurrences(self.events, first, last):
            days.update(occ.days())
        return days

    def _show_events(self, day):
        for child in self.events_box.get_children():
            child.destroy()
        today = dt.date.today()
        name = "Today" if day == today else "Tomorrow" if day == today + dt.timedelta(days=1) \
            else f"{day:%A, %B} {day.day}"
        heading = Gtk.Label(label=name, xalign=0)
        heading.get_style_context().add_class("beacon-day")
        self.events_box.pack_start(heading, False, False, 2)
        found = calendar_store.on_day(self.events, day)
        if not found:
            empty = Gtk.Label(label="No events", xalign=0)
            empty.get_style_context().add_class("beacon-empty")
            self.events_box.pack_start(empty, False, False, 0)
        for occ in found[:5]:
            button = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
            button.get_style_context().add_class("beacon-event")
            row = Gtk.Box(spacing=8)
            dot = Gtk.Label(label="●")
            dot.get_style_context().add_class("beacon-dot")
            row.pack_start(dot, False, False, 0)
            title = Gtk.Label(label=occ.event.title, xalign=0, ellipsize=3)
            row.pack_start(title, True, True, 0)
            when = Gtk.Label(label="all-day" if occ.all_day else calendar_store.time_text(occ.start))
            when.get_style_context().add_class("beacon-event-time")
            row.pack_start(when, False, False, 0)
            button.add(row)
            button.connect("clicked", lambda *_: self._open_calendar())
            self.events_box.pack_start(button, False, False, 0)
        if len(found) > 5:
            more = Gtk.Label(label=f"{len(found) - 5} more", xalign=0)
            more.get_style_context().add_class("beacon-empty")
            self.events_box.pack_start(more, False, False, 0)
        self.events_box.show_all()

    # --- Tide's alerts ----------------------------------------------------
    def _check_alerts(self):
        """Show a notice for each event whose alert time has come since the
        last look. Alerts missed while the computer was off or asleep for
        more than an hour are skipped rather than shown all at once."""
        try:
            stamp = os.stat(calendar_store.store_path()).st_mtime
        except OSError:
            stamp = None
        if stamp != self.alert_stamp:
            self.alert_stamp = stamp
            self.alert_events = calendar_store.load() if stamp else []
        now = dt.datetime.now()
        since = max(self.alerts_until, now - dt.timedelta(hours=1))
        self.alerts_until = now
        for occ in calendar_store.due_alerts(self.alert_events, since, now):
            # Stays up until it's closed, clicked or snoozed, as a calendar alert should.
            self.notify("Tide", 0, "freemac-tide", occ.event.title, self._alert_body(occ, now),
                        [SNOOZE, "Snooze"],
                        {"x-freemac-uri": "tide-event:" + urllib.parse.quote(occ.event.uid, safe="")
                         + "@@" + occ.start.date().isoformat()}, 0)
        self._check_reminders(since, now)
        return True

    # --- Software updates -------------------------------------------------
    def _updates_ready(self, count):
        self.notify("Software Update", 0, "freemac-harbor", "Software updates are ready",
                    f"{update_notice.summary(count)} for this computer. Click to see them in Harbor.",
                    [], {"x-freemac-uri": "harbor:updates"}, -1)

    def _freemac_ready(self, offer):
        body = "A new version of freemac is ready to download. Click to see what's new and install it."
        self.notify("Software Update", 0, "freemac-dials", f"freemac {offer['version']} is available",
                    body, [], {"x-freemac-uri": "dials:softwareupdate"}, -1)

    def _freemac_installed(self, done):
        if done.get("undone"):
            title, body = f"freemac {done.get('to')} is back", "The last update was undone in Recovery."
        elif done.get("ok"):
            title = f"freemac {done.get('to')} is installed"
            body = f"Your computer was updated from freemac {done.get('from')}. " \
                "Dials > Software Update shows what's new."
        else:
            title = "freemac couldn't be updated"
            body = f"{done.get('error') or 'Something went wrong.'} Your computer is as it was."
        self.notify("Software Update", 0, "freemac-dials", title, body, [],
                    {"x-freemac-uri": "dials:softwareupdate"}, -1)

    # --- Nudge's reminders ------------------------------------------------
    def _reminder_files(self):
        folder = reminders_store.store_dir()
        try:
            return tuple(sorted((n, os.stat(os.path.join(folder, n)).st_mtime)
                                for n in os.listdir(folder) if n.endswith(".ics")))
        except OSError:
            return ()

    def _check_reminders(self, since, now):
        stamp = self._reminder_files()
        if stamp != self.reminder_stamp:
            self.reminder_stamp = stamp
            self.reminder_lists = reminders_store.load() if stamp else []
        for reminder in reminders_store.due_nudges(self.reminder_lists, since, now):
            owner = next((l for l in self.reminder_lists if l.id == reminder.list_id), None)
            body = owner.name if owner else ""
            if reminder.notes:
                body = f"{body}\n{reminder.notes.splitlines()[0]}" if body else reminder.notes.splitlines()[0]
            self.notify("Nudge", 0, "freemac-nudge", reminder.title or "New Reminder", body,
                        [DONE, "Mark as Completed", SNOOZE, "Snooze"],
                        {"x-freemac-uri": "nudge-reminder:" + urllib.parse.quote(reminder.uid, safe="")}, 0)

    @staticmethod
    def _complete_reminder(uid):
        for rlist in reminders_store.load():
            for reminder in rlist.reminders:
                if reminder.uid == uid and not reminder.done:
                    reminder.done = True
                    reminder.completed = dt.datetime.now().replace(microsecond=0)
                    reminders_store.save(rlist)
                    return

    @staticmethod
    def _alert_body(occ, now):
        day = occ.start.date()
        today = now.date()
        name = "Today" if day == today else "Tomorrow" if day == today + dt.timedelta(days=1) \
            else f"{day:%A, %B} {day.day}"
        if occ.all_day:
            when = f"{name}, all day"
        else:
            when = f"{name}, {calendar_store.time_text(occ.start)} to {calendar_store.time_text(occ.end)}"
        place = occ.event.location.strip()
        return f"{when}\n{place}" if place else when

    def _open_calendar(self):
        self.center.hide()
        info = Gio.DesktopAppInfo.new("freemac-tide.desktop")
        if info:
            info.launch([], None)

    def _fill_center(self):
        if not self.center:
            return
        self.date_label.set_text(time.strftime("%A, %B %-d"))
        self.events = calendar_store.load()
        self.month.show_day(dt.date.today())
        self._show_events(dt.date.today())
        with self.dnd.handler_block(self.dnd_handler):
            self.dnd.set_active_id(notify_rules.active_focus(style.prefs()) or "")
        for child in self.list_box.get_children():
            child.destroy()
        if not self.history:
            empty = Gtk.Label(label="No notifications")
            empty.get_style_context().add_class("beacon-empty")
            empty.set_margin_top(24)
            self.list_box.pack_start(empty, False, False, 0)
        until = notify_rules.until(style.prefs())
        if until:
            self.dnd_note.set_text(f"On by schedule {until}")
            self.dnd_note.show()
        else:
            self.dnd_note.hide()
        for app, notes in notify_rules.grouped(self.history):
            if len(notes) == 1:
                self.list_box.pack_start(Card(self, notes[0], in_center=True), False, False, 0)
                continue
            self.list_box.pack_start(self._group(app, notes), False, False, 0)
        self.list_box.show_all()

    def _group(self, app, notes):
        """Several notifications from one app: the newest on top of a stack,
        spread out by a click, as a Mac's notification centre does."""
        open_ = app in self.expanded
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        head = Gtk.Box(spacing=6)
        name = Gtk.Label(label=app or "Notifications", xalign=0)
        name.get_style_context().add_class("beacon-group")
        head.pack_start(name, True, True, 0)
        more = Gtk.Button(label="Show Less" if open_ else f"Show All ({len(notes)})")
        more.set_relief(Gtk.ReliefStyle.NONE)
        more.get_style_context().add_class("beacon-more")
        more.connect("clicked", lambda *_: self.toggle_group(app))
        head.pack_start(more, False, False, 0)
        clear = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
        clear.set_relief(Gtk.ReliefStyle.NONE)
        clear.set_tooltip_text(f"Clear {app or 'these'} notifications")
        clear.get_style_context().add_class("beacon-close")
        clear.connect("clicked", lambda *_: self.forget_app(app))
        head.pack_start(clear, False, False, 0)
        box.pack_start(head, False, False, 0)
        if open_:
            for note in notes:
                box.pack_start(Card(self, note, in_center=True), False, False, 0)
            return box
        top = Card(self, notes[0], in_center=True)
        top.on_click = lambda: self.toggle_group(app)   # a click spreads the stack out
        box.pack_start(top, False, False, 0)
        # The edges of the ones under it, peeking out below.
        for depth in range(min(2, len(notes) - 1)):
            edge = Gtk.Box()
            edge.get_style_context().add_class(f"beacon-stack-{depth + 1}")
            edge.set_size_request(-1, 6)
            box.pack_start(edge, False, False, 0)
        box.set_spacing(0)
        head.set_margin_bottom(6)
        return box

    def _center_key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.center.hide()
            return True
        return False

    def _dnd_toggled(self, combo):
        write_prefs(**notify_rules.focus_writes(combo.get_active_id() or None, style.prefs()))

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
        for key, value in style.palette().items():
            text = text.replace("@" + key + ";", value + ";")
        self._provider.load_from_data(text.encode())


def write_pref(key, value):
    """Change one key in shell.json, keeping the others."""
    write_prefs(**{key: value})


def write_prefs(**changes):
    """Change some keys in shell.json, keeping the others."""
    data = style.prefs()
    data.update(changes)
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
