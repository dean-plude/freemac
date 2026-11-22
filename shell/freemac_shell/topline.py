# SPDX-License-Identifier: GPL-3.0-or-later
"""Topline: freemac's menu bar along the top of the screen."""
import os
import shutil
import signal
import subprocess
import time

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import (apps, beacon, dials_time, fallback_menus, held, helpsearch, mac_accel, notify_rules, quick,  # noqa: E402
               recent_items, status, style)
from .wfipc import Wayfire, is_app_window, is_minimized  # noqa: E402

MARK = "/usr/share/freemac/freemac-mark.svg"
DESKTOP_APP = "Drawer"   # the file manager, in the bar when the desktop is in front
DESKTOP_OWNED = {"freemac-pier", "org.freemac.pier"}   # windows of the Dock count as the desktop's
DESKTOP_GO = (("Home", "", "⇧⌘H"), ("Desktop", "Desktop", "⇧⌘D"),
              ("Documents", "Documents", "⇧⌘O"), ("Downloads", "Downloads", "⌥⌘L"),
              ("Pictures", "Pictures", ""), ("Music", "Music", ""))
HEIGHT = 28
HIDE_DELAY = 400     # ms after the pointer leaves a menu bar that hides itself
SLIDE_MS = 180


def run(*cmd):
    subprocess.Popen(cmd, start_new_session=True)


def _person_name():
    """The name for Log Out: the person's own name, or their user name."""
    name = GLib.get_real_name()
    return name if name and name != "Unknown" else GLib.get_user_name()


def _file_icon(path):
    try:
        info = Gio.File.new_for_path(path).query_info("standard::icon", Gio.FileQueryInfoFlags.NONE, None)
        return info.get_icon()
    except GLib.Error:
        return None


def _open_file(path):
    recent_items.recents.note(path)
    try:
        Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
    except GLib.Error:
        pass


def _trash_dir():
    return os.path.join(GLib.get_user_data_dir(), "Trash", "files")


def _trash_has_items():
    try:
        return bool(os.listdir(_trash_dir()))
    except OSError:
        return False


def _untitled_folder(parent):
    name, n = "untitled folder", 2
    while os.path.exists(os.path.join(parent, name)):
        name, n = f"untitled folder {n}", n + 1
    try:
        os.makedirs(os.path.join(parent, name))
    except OSError:
        pass


class Topline(Gtk.Window):
    def __init__(self):
        super().__init__(title="Topline")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_namespace(self, "freemac-topline")
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.auto_exclusive_zone_enable(self)
        self.set_size_request(-1, HEIGHT)

        bar = Gtk.Box(spacing=2)
        bar.get_style_context().add_class("topline")
        # The bar slides up out of sight when it hides itself (shell.json's
        # "menubar_autohide", set in Dials); the window itself stays put.
        self.revealer = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN,
                                     transition_duration=SLIDE_MS, reveal_child=True,
                                     valign=Gtk.Align.START)
        self.revealer.add(bar)
        self.add(self.revealer)
        self.autohide, self._hide_source = False, None
        self.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.connect("enter-notify-event", self._entered)
        self.connect("leave-notify-event", self._left)
        self.connect("map-event", lambda *_: self._set_input() and False)
        self.revealer.connect("notify::child-revealed", lambda *_: self._set_input())
        # The bar can be mapped before the compositor has stretched it across
        # the screen: take the pointer again once it has its full width, or
        # the status icons on the right never get a click.
        self._input_width = None
        self.connect("size-allocate", self._resized)

        # System menu behind the freemac mark.
        self.mark = Gtk.MenuButton()
        self.mark.set_image(self._mark_image())
        self.mark.set_popup(self._watch_menu(self._system_menu()))
        bar.pack_start(self.mark, False, False, 4)
        self._slide(self.mark)

        # Focused application's name and menu.
        self.app_button = Gtk.MenuButton(label="freemac")
        self.app_button.get_style_context().add_class("app-name")
        self.app_menu = self._watch_menu(Gtk.Menu())
        self.app_button.set_popup(self.app_menu)
        bar.pack_start(self.app_button, False, False, 0)
        self._slide(self.app_button)

        # The focused app's own menus (File, Edit, ...), when it publishes
        # them; Strata tells us where to find them.
        self.menus_box = Gtk.Box(spacing=0)
        self.menus_box.set_no_show_all(True)
        bar.pack_start(self.menus_box, False, False, 0)
        self._menu_key = None
        self._menubar = None
        self._app_model = None
        self._groups = {}
        self._bus = None
        # The app menus' shortcuts, watched for while a held app has no window.
        self._key_models, self._keys_sent, self._keys_queued = [], None, False
        self._own_actions = Gio.SimpleActionGroup()
        for name in ("hide", "hide-others", "show-all", "quit"):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda _a, _p, n=name: self._own_action(n))
            self._own_actions.add_action(action)
        close = Gio.SimpleAction.new("close-window", None)
        close.connect("activate", lambda *_: self._own_action("close-window"))
        self._own_actions.add_action(close)
        # Menus for apps that publish none press the app's own shortcuts.
        press = Gio.SimpleAction.new("press", GLib.VariantType.new("s"))
        press.connect("activate", lambda _a, keys: GLib.timeout_add(150, self._press, keys.get_string()))
        self._own_actions.add_action(press)

        self.window_button = Gtk.MenuButton(label="Window")
        self.window_menu = self._watch_menu(Gtk.Menu())
        self.before_place = {}   # window id -> where it was before Move & Resize
        self.window_button.set_popup(self.window_menu)
        bar.pack_start(self.window_button, False, False, 0)
        self._slide(self.window_button)

        # Help ends every app's menus: a search field that finds menu items.
        # Its button opens a panel of its own, which takes the keyboard.
        self.help_button = helpsearch.HelpButton()
        self.help = helpsearch.HelpPanel(self._searchable_menus,
                                         lambda: self.help_button.set_active(False))
        self.help_button.connect("toggled", self._help_toggled)
        bar.pack_start(self.help_button, False, False, 0)
        self._slide(self.help_button)
        # Seek asks the bar for the front app's menu items, too.
        self._found = []
        Gio.bus_own_name(Gio.BusType.SESSION, "org.freemac.Topline", Gio.BusNameOwnerFlags.REPLACE,
                         self._bus_acquired, None, None)

        # The clock opens Beacon's notification centre.
        self.clock = Gtk.Label()
        clock_button = Gtk.Button()
        clock_button.add(self.clock)
        clock_button.get_style_context().add_class("clock")
        clock_button.set_tooltip_text("Notifications and calendar")
        clock_button.connect("clicked", lambda *_: beacon.call("ToggleCenter"))
        bar.pack_end(clock_button, False, False, 0)
        quick_settings = quick.QuickSettings()
        quick_settings.get_style_context().add_class("status")
        bar.pack_end(quick_settings, False, False, 0)
        self.dnd = Gtk.Image.new_from_icon_name("notifications-disabled-symbolic", Gtk.IconSize.MENU)
        self.dnd.set_tooltip_text("Do Not Disturb is on")
        self.dnd.set_no_show_all(True)
        bar.pack_end(self.dnd, False, False, 4)
        # Status icons sit just left of the clock; each hides itself when the
        # computer has nothing to show (no battery, no sound server).
        for indicator in (status.Battery(), status.Sound(), status.Network(), status.Bluetooth(),
                          status.Printing(), status.Recording(), status.ScreenShared(), status.InUse(), status.InputMenu()):
            indicator.get_style_context().add_class("status")
            bar.pack_end(indicator, False, False, 0)
        self._seconds, self._tick_source = None, None
        self._tick()
        self._prefs_monitor = style.watch_prefs(self._prefs_changed)
        self._zone_monitor = Gio.File.new_for_path("/etc/localtime").monitor_file(Gio.FileMonitorFlags.NONE, None)
        self._zone_monitor.connect("changed", self._zone_changed)
        self._prefs_changed()

        self.focused = None
        # The app last in front, and a held app whose last window closed:
        # it stays in the bar with its menus until another app comes forward.
        self._last_app, self._windowless, self._told_strata = None, None, None
        self._refresh_queued = False
        self.held = held.Watcher(on_change=lambda: GLib.idle_add(self.refresh))
        try:
            self.wf = Wayfire(on_event=self._on_event)
        except OSError:
            self.wf = None
        # An app that came forward before the bar started (Welcome at login)
        # sent its focus event too early for us: start from what's in front.
        front = self.wf.focused() if self.wf else None
        if front is not None and (front.get("app-id") or "").lower() not in DESKTOP_OWNED:
            self._last_app = front.get("app-id")
        self.refresh()

    def _on_event(self, event):
        kind = event.get("event")
        view = event.get("view") or {}
        app_id = view.get("app-id") or ""
        if kind == "view-focused" and view:
            if is_app_window(view) and app_id.lower() not in DESKTOP_OWNED:
                if app_id != (self.focused or {}).get("app-id"):
                    # Another app came forward: take the last one's menus
                    # down now, so its name never sits over the old menus
                    # while the new app's arrive.
                    self._use_menus(None)
                self._last_app, self._windowless = app_id, None
                recent_items.note_app(app_id)   # for Recent Items in the freemac menu
                # Show the app's name at once, from the event itself: while
                # a new window opens Wayfire can take a while to answer, and
                # the full refresh below asks it several things.
                self.app_button.set_label(apps.display_name(app_id, view.get("title", "")))
                # This may be Wayfire handing the focus on as another app
                # closed its last window; Strata then takes it back so that
                # app stays in front. Look again once it has.
                GLib.timeout_add(150, self._check_windowless)
            elif app_id.lower() in DESKTOP_OWNED | {"freemac-backdrop"}:
                # The desktop came forward: the file manager is in front.
                self._last_app, self._windowless = None, None
        elif kind == "view-focused" and self._last_app:
            # Nothing has the focus: the front app may have closed its last
            # window. Wayfire has dropped the window from its list by now, or
            # very nearly, so look again in a moment too.
            self._check_windowless()
            GLib.timeout_add(250, self._check_windowless)
        if kind in ("view-focused", "view-mapped", "view-app-id-changed"):
            # A window that opens as another app is launched can be focused
            # before Wayfire knows its app: look again once it has settled.
            GLib.timeout_add(300, self._look_again)
        self._tell_strata()
        self._refresh_soon()

    def _refresh_soon(self):
        """Refresh once the bar has been drawn, and only once for a burst of
        events (a window opening sends several)."""
        if not self._refresh_queued:
            self._refresh_queued = True
            GLib.idle_add(self._queued_refresh)

    def _queued_refresh(self):
        self._refresh_queued = False
        self.refresh()
        return False

    def _look_again(self):
        front = self.wf.focused() if self.wf else None
        app_id = (front or {}).get("app-id") or ""
        if (front and is_app_window(front) and app_id.lower() not in DESKTOP_OWNED
                and app_id != self._last_app):
            self._last_app, self._windowless = app_id, None
            self._tell_strata()
        self.refresh()
        return False

    def _check_windowless(self):
        app_id = self._last_app
        # Strata keeps a held app in front when its last window closes, even
        # though another app's window had the focus for a moment.
        kept = self.wf.front_app_now() if (self.wf and not self._windowless) else ""
        if kept and self.held.is_running(kept):
            app_id = kept
        if (app_id and not self._windowless and self.held.is_running(app_id) and self.wf
                and self.wf.focused() is None and not self._views_of(app_id)):
            self._windowless = held.window_id(app_id)
            self._tell_strata()
        self.refresh()
        return False

    def _tell_strata(self):
        if self._windowless != self._told_strata and self.wf:
            self._told_strata = self._windowless
            self._keys_sent = None
            self.wf.front_app(self._windowless)
            self._queue_keys()

    def _queue_keys(self):
        if self._windowless and not self._keys_queued:
            self._keys_queued = True
            GLib.timeout_add(120, self._send_keys)

    def _send_keys(self):
        """The held app's shortcuts go on working with no window open, as on
        a Mac (⌘N for a new note): Strata carries them out, from the list of
        those its menus show. Quit is Strata's own."""
        self._keys_queued = False
        if not (self._windowless and self.wf and self._menu_key and
                held.bus_name(self._windowless) == self._menu_key[0]):
            return False
        keys = {}
        self._walk_keys(self._menubar, keys)
        if keys != self._keys_sent:
            self._keys_sent = keys
            self.wf.front_app(self._windowless, keys=keys)
        return False

    def _walk_keys(self, model, keys):
        if model is None:
            return
        if not any(model is seen for seen in self._key_models):
            self._key_models.append(model)
            model.connect("items-changed", lambda *_: self._queue_keys())
        string = GLib.VariantType.new("s")
        for i in range(model.get_n_items()):
            for link in (Gio.MENU_LINK_SECTION, Gio.MENU_LINK_SUBMENU):
                self._walk_keys(model.get_item_link(i, link), keys)
            accel = model.get_item_attribute_value(i, "accel", string)
            action = model.get_item_attribute_value(i, Gio.MENU_ATTRIBUTE_ACTION, string)
            if (accel is None or action is None or
                    model.get_item_attribute_value(i, Gio.MENU_ATTRIBUTE_TARGET, None) is not None):
                continue
            name = action.get_string()
            chord = mac_accel.chord(accel.get_string())
            if chord and name.startswith("app.") and name != "app.quit":
                keys.setdefault(chord, name[4:])

    def _mark_image(self):
        image = Gtk.Image()
        try:
            from gi.repository import GdkPixbuf

            image.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_size(MARK, 18, 18))
        except GLib.Error:
            image.set_from_icon_name("start-here", Gtk.IconSize.MENU)
        return image

    def _item(self, menu, label, callback=None, sensitive=True, shortcut="", check=None):
        """A menu item; shortcut is shown on the right in Mac symbols (it's
        only a reminder: the keys themselves are Strata's). check True or
        False puts a plain tick, or the room for one, before the name."""
        item = Gtk.MenuItem()
        if shortcut or check is not None:
            box = Gtk.Box(spacing=24 if shortcut else 0)
            if check is not None:
                tick = Gtk.Label(label="\u2713" if check else "", xalign=0)
                tick.set_size_request(18, -1)
                box.pack_start(tick, False, False, 0)
            box.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
            keys = Gtk.Label(label=shortcut, xalign=1)
            keys.get_style_context().add_class("dim-label")
            box.pack_end(keys, False, False, 0)
            item.add(box)
        else:
            item.set_label(label)
        item.set_sensitive(sensitive and callback is not None)
        if callback:
            item.connect("activate", lambda _i: callback())
        menu.append(item)
        return item

    def _system_menu(self):
        """The freemac menu, in a Mac's order: About, Settings and the app
        centre, Recent Items, Force Quit, then Sleep, Restart, Shut Down,
        Lock Screen and Log Out, which ask first (freemac-power)."""
        menu = Gtk.Menu()
        self._item(menu, "About freemac", self._about)
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Settings\u2026", lambda: run("freemac-dials"))
        self._item(menu, "Harbor\u2026", lambda: run("freemac-harbor"))
        menu.append(Gtk.SeparatorMenuItem())
        recent = Gtk.MenuItem(label="Recent Items")
        self.recent_menu = Gtk.Menu()
        recent.set_submenu(self.recent_menu)
        menu.append(recent)
        menu.connect("show", lambda _m: self._fill_recent_items())
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Force Quit\u2026", lambda: run("freemac-force-quit"), shortcut="\u2325\u2318\u238b")
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Sleep", lambda: run("freemac-power", "sleep"))
        self._item(menu, "Restart\u2026", lambda: run("freemac-power", "restart"))
        self._item(menu, "Shut Down\u2026", lambda: run("freemac-power", "shutdown"))
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Lock Screen", lambda: run("freemac-lock"), shortcut="\u2303\u2318Q")
        self._item(menu, f"Log Out {_person_name()}\u2026", lambda: run("freemac-power", "logout"),
                   shortcut="\u21e7\u2318Q")
        menu.show_all()
        return menu

    def _fill_recent_items(self):
        """Recent Items: the apps and documents used lately, then Clear Menu."""
        menu = self.recent_menu
        self._clear(menu)
        found = False
        for heading, entries in (("Applications", [(info.get_display_name() or info.get_name(),
                                                     info.get_icon(), lambda i=info: i.launch([], None))
                                                    for info in recent_items.recent_apps()]),
                                 ("Documents", [(os.path.basename(path), _file_icon(path),
                                                 lambda p=path: _open_file(p))
                                                for path in recent_items.recent_documents()])):
            if not entries:
                continue
            if found:
                menu.append(Gtk.SeparatorMenuItem())
            title = Gtk.MenuItem(label=heading, sensitive=False)
            title.get_style_context().add_class("menu-heading")
            menu.append(title)
            for label, icon, callback in entries:
                item = Gtk.MenuItem()
                line = Gtk.Box(spacing=8)
                image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.MENU) if icon else Gtk.Image()
                image.set_pixel_size(16)
                line.pack_start(image, False, False, 0)
                line.pack_start(Gtk.Label(label=label[:50], xalign=0), True, True, 0)
                item.add(line)
                item.connect("activate", lambda _i, c=callback: c())
                menu.append(item)
            found = True
        if not found:
            menu.append(Gtk.MenuItem(label="No Recent Items", sensitive=False))
        menu.append(Gtk.SeparatorMenuItem())
        clear = Gtk.MenuItem(label="Clear Menu", sensitive=found)
        clear.connect("activate", lambda _i: recent_items.clear())
        menu.append(clear)
        # Each item, not the menu itself: showing the submenu would pop it up
        # on its own while the freemac menu opens.
        for child in menu.get_children():
            child.show_all()

    def _about(self):
        if shutil.which("freemac-manifest"):
            run("freemac-manifest")
            return
        dialog = Gtk.AboutDialog(
            program_name="freemac",
            version=_os_version(),
            comments="A free desktop for your PC.",
            website="https://github.com/dean-plude/freemac",
            license_type=Gtk.License.GPL_3_0,
        )
        dialog.set_logo_icon_name("freemac-welcome")
        dialog.run()
        dialog.destroy()

    def _prefs_changed(self, *_args):
        self._show_time()
        self._use_autohide(bool(style.prefs().get("menubar_autohide")))

    # --- a menu bar that hides itself, as on a Mac ------------------------
    def _use_autohide(self, on):
        if on == self.autohide:
            return
        self.autohide = on
        if on:
            # Windows get the whole screen; the bar slides over them.
            GtkLayerShell.set_exclusive_zone(self, -1)
            self._hide_later()
        else:
            GtkLayerShell.auto_exclusive_zone_enable(self)
            self.show_now()

    def hidden(self):
        return not self.revealer.get_reveal_child()

    def show_now(self):
        if self._hide_source:
            GLib.source_remove(self._hide_source)
            self._hide_source = None
        if self.hidden():
            self.revealer.set_reveal_child(True)
        self._set_input()

    def _hide_later(self):
        if not self.autohide:
            return
        if self._hide_source:
            GLib.source_remove(self._hide_source)
        self._hide_source = GLib.timeout_add(HIDE_DELAY, self._hide_now)

    def _busy(self):
        """A menu or Help is open: the bar stays."""
        return self._menu_open() or any(b.get_active() for b in self._menu_buttons())

    def _hide_now(self):
        self._hide_source = None
        if self.autohide and not self._busy():
            self.revealer.set_reveal_child(False)
            self._set_input()
        return False

    def _resized(self, _window, allocation):
        if allocation.width != self._input_width:
            self._input_width = allocation.width
            GLib.idle_add(self._set_input)

    def _set_input(self):
        """Take the pointer over the whole bar, or, while it is hidden, only
        on the screen's top row of pixels, so it comes back from there and
        windows under it stay clickable."""
        window = self.get_window()
        if window is None:
            return False
        width = max(1, self.get_allocated_width())
        tall = 1 if self.autohide and self.hidden() else max(HEIGHT, self.get_allocated_height())
        window.input_shape_combine_region(cairo.Region(cairo.RectangleInt(0, 0, width, tall)), 0, 0)
        # Wayland takes a new input region with the next frame.
        self.queue_draw()
        return False

    def _entered(self, _widget, event):
        if self.autohide and event.detail != Gdk.NotifyType.INFERIOR:
            self.show_now()
        return False

    def _left(self, _widget, event):
        if self.autohide and event.detail != Gdk.NotifyType.INFERIOR and event.mode == Gdk.CrossingMode.NORMAL:
            self._hide_later()
        return False

    def _show_time(self, *_args):
        prefs = style.prefs()
        # The moon shows while Do Not Disturb is on, by hand or by its schedule,
        # which the clock's tick keeps up to date.
        self.dnd.set_visible(notify_rules.quiet(prefs))
        self.clock.set_text(time.strftime(dials_time.clock_format(prefs), time.localtime()))
        if prefs.get("clock_seconds") != self._seconds:
            # Seconds on: tick every second; off: on each minute.
            self._seconds = prefs.get("clock_seconds")
            self._tick()

    def _tick(self):
        if self._tick_source:
            GLib.source_remove(self._tick_source)
        self._show_time()
        wait = 1 if self._seconds else 60 - time.localtime().tm_sec
        self._tick_source = GLib.timeout_add_seconds(wait, self._tick_again)
        return False

    def _tick_again(self):
        self._tick_source = None
        return self._tick()

    def _zone_changed(self, *_args):
        # Dials > Date & Time changed the time zone: /etc/localtime now points
        # at another zone, which the C library reads again on tzset().
        time.tzset()
        self._show_time()

    def refresh(self):
        view = self.wf.focused() if self.wf else None
        # Opening one of our menus takes the focus from the app; keep showing
        # that app's menus until the menu closes.
        if self._menu_open():
            # Refilling a menu while it is open would take its rows (and an
            # open submenu) away under the pointer; it is done once it closes.
            return
        if view is not None and (view.get("app-id") or "").lower() in DESKTOP_OWNED:
            # The Dock's own windows (the Empty Trash alert) belong to the
            # file manager, as the Trash does on a Mac.
            view = None
        elif view is None and self._windowless and self.held.is_running(self._windowless):
            self._show_windowless(self._windowless)
            return
        elif view is None and self._last_app and self.wf:
            # The switcher, Seek or a panel has the keyboard, or the app's
            # windows are minimized: the app stays in the bar, as on a Mac.
            its = self._views_of(self._last_app)
            if its:
                view = max(its, key=lambda v: v.get("last-focus-timestamp", 0))
        self.focused = view
        self._fill_app_menus(view)
        app_id = view.get("app-id") if view else None
        # With no window in front (the desktop was clicked), the file manager
        # is the app in the bar, with its own menus, as on a Mac.
        self.app_button.set_label(apps.display_name(app_id, view.get("title", "") if view else "") if view
                                  else DESKTOP_APP)
        if view is None:
            self._desktop_menus()
        self._fill_app_menu(view)
        self._fill_window_menu(view)

    def _desktop_menus(self):
        """File and Go for the desktop, which belongs to Drawer."""
        if self._menu_key == ("desktop",):
            return
        self._menu_key = ("desktop",)
        for child in self.menus_box.get_children():
            self.menus_box.remove(child)
        home = GLib.get_home_dir()
        desktop = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP) or os.path.join(home, "Desktop")
        file_menu = self._watch_menu(Gtk.Menu())
        self._item(file_menu, f"New {DESKTOP_APP} Window", lambda: run("freemac-drawer", home), shortcut="⌘N")
        self._item(file_menu, "New Folder", lambda: _untitled_folder(desktop), shortcut="⇧⌘N")
        file_menu.append(Gtk.SeparatorMenuItem())
        self._item(file_menu, "Find…", lambda: run("freemac-seek"), shortcut="⌘Space")
        go_menu = self._watch_menu(Gtk.Menu())
        for label, sub, shortcut in DESKTOP_GO:
            path = os.path.join(home, sub) if sub else home
            if os.path.isdir(path):
                self._item(go_menu, label, lambda p=path: run("freemac-drawer", p), shortcut=shortcut)
        go_menu.append(Gtk.SeparatorMenuItem())
        self._item(go_menu, "Trash", lambda: run("freemac-drawer", _trash_dir()))
        for label, menu in (("File", file_menu), ("Go", go_menu)):
            menu.show_all()
            button = Gtk.MenuButton(label=label)
            button.set_popup(menu)
            menu.connect("motion-notify-event", self._menu_motion)
            self._slide(button)
            self.menus_box.pack_start(button, False, False, 0)
            button.show_all()
        self.menus_box.set_visible(True)

    def _empty_trash(self):
        from . import alert
        answer = alert.ask(None, "Are you sure you want to permanently erase the items in the Trash?",
                           "You can't undo this action.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Empty Trash", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK, icon="user-trash-full")
        if answer == Gtk.ResponseType.OK:
            # The same as the dock's Trash does.
            from . import pier
            pier.empty_trash()

    def _clear(self, menu):
        for child in menu.get_children():
            menu.remove(child)

    def _menus(self):
        yield self.app_button.get_popup()
        yield self.window_menu
        for button in self.menus_box.get_children():
            yield button.get_popup()

    def _help_toggled(self, button):
        if not button.get_active():
            self.help.close_panel()
            self._hide_later()
            return
        # Clicking Help while it's open closes it: the click first takes the
        # focus from the panel (closing it), then would open it again.
        if time.monotonic() - self.help.closed_at < 0.4:
            button.set_active(False)
            return
        spot = button.translate_coordinates(self, 0, 0)
        self.help.open_at(spot[0] if spot else 0)

    BUS_XML = """<node><interface name="org.freemac.Topline">
      <method name="SearchMenus"><arg type="s" name="query" direction="in"/>
        <arg type="a(sss)" name="found" direction="out"/>
        <arg type="s" name="app_icon" direction="out"/></method>
      <method name="RunMenuItem"><arg type="u" name="index" direction="in"/></method>
    </interface></node>"""

    def _bus_acquired(self, connection, _name):
        iface = Gio.DBusNodeInfo.new_for_xml(self.BUS_XML).interfaces[0]
        connection.register_object("/org/freemac/Topline", iface, self._bus_call, None, None)

    def _bus_call(self, _conn, _sender, _path, _iface, method, params, invocation):
        """SearchMenus gives (name, where, shortcut) of the front app's menu
        items that match, and the app's icon; RunMenuItem runs one of them by its place in that
        list, a moment later (Seek is closing and handing back the keyboard)."""
        if method == "SearchMenus":
            (query,) = params.unpack()
            # Seek finds commands, not the names of open windows in the
            # Window menu (the file itself is already among its results).
            self._found = [f for f in helpsearch.find(self._searchable_menus, query)
                           if not getattr(f[0], "fm_window", False)][:4]
            rows = [(name, helpsearch.ARROW.join(path), shortcut) for _i, path, name, shortcut in self._found]
            app_id = (self.focused or {}).get("app-id")
            icon = apps.icon_for(app_id).to_string() if app_id else "system-file-manager"
            invocation.return_value(GLib.Variant("(a(sss)s)", (rows, icon)))
        elif method == "RunMenuItem":
            (index,) = params.unpack()
            if index < len(self._found):
                item = self._found[index][0]
                GLib.timeout_add(250, lambda: item.activate() and False)
            invocation.return_value(None)

    def _searchable_menus(self):
        """(title, menu) for each menu Help searches, in the bar's order."""
        yield self.app_button.get_label() or "", self.app_button.get_popup()
        for button in self.menus_box.get_children():
            yield (button.get_label() or "").replace("_", ""), button.get_popup()
        yield "Window", self.window_menu

    def _menu_open(self):
        return any(menu is not None and menu.get_visible() for menu in self._menus())

    def _menu_buttons(self):
        yield self.mark
        yield self.app_button
        yield from self.menus_box.get_children()
        yield self.window_button
        yield self.help_button

    def _slide(self, button):
        """As on a Mac, once one menu is open, moving the pointer onto
        another title in the bar opens that menu instead, with no click."""
        button.connect("enter-notify-event", self._slide_to)
        button.connect("toggled", self._menu_toggled)
        return button

    def _menu_toggled(self, button):
        """The first click on a title right after Esc closed a menu opens the
        new menu and has it shut again at once (the compositor turns down
        its grab). A menu that closes that fast, untouched, opens again."""
        now = time.monotonic()
        if button.get_active() and self.autohide:
            self.show_now()
        if button.get_active():
            if now - getattr(button, "_fm_opened", 0) > 1:
                button._fm_retried = False
            button._fm_opened = now
            return
        if (now - getattr(button, "_fm_opened", 0) < 0.3 and not getattr(button, "_fm_retried", True)
                and not any(other.get_active() for other in self._menu_buttons())):
            button._fm_retried = True
            GLib.timeout_add(60, self._open_untouched, button)

    def _slide_to(self, button, _event):
        if any(other is not button and other.get_active() for other in self._menu_buttons()):
            self._switch_menu(button)
        return False

    def _watch_menu(self, menu):
        menu.connect("deactivate", lambda *_: GLib.idle_add(self._after_menu))
        menu.connect("motion-notify-event", self._menu_motion)
        return menu

    def _menu_motion(self, _menu, event):
        """While a menu is open it gets the pointer's moves, also those over
        the bar; over another menu title, open that menu instead."""
        # The bar sits at the screen's top left, so the pointer's place on the
        # screen is its place in the bar.
        x, y = event.x_root, event.y_root
        if y >= HEIGHT:
            return False
        for button in self._menu_buttons():
            menu = button.get_popup()
            if not button.get_visible() or (menu is not None and menu.get_visible()):
                continue
            spot = button.translate_coordinates(self, 0, 0)
            if spot is None:
                continue
            bx, by = spot
            size = button.get_allocation()
            if bx <= x < bx + size.width and by <= y < by + size.height:
                GLib.idle_add(self._switch_menu, button)
                break
        return False

    def _switch_menu(self, button):
        for other in self._menu_buttons():
            if other is button:
                continue
            menu = other.get_popup()
            if menu is not None and menu.get_visible():
                menu.popdown()
            if other.get_active():
                other.set_active(False)
            # The pointer left it during the menu's grab, so GTK never saw it
            # go: drop the hover look by hand, or every title stays lit.
            other.unset_state_flags(Gtk.StateFlags.PRELIGHT)
        return self._open_untouched(button)

    def _open_untouched(self, button):
        """Open a title's menu with nothing in it chosen yet (opened from
        code, GTK picks the first item, as if the keyboard had opened it)."""
        button.set_active(True)
        menu = button.get_popup()
        if menu is not None:
            GLib.idle_add(lambda: menu.deselect() and False)
        return False

    def _after_menu(self):
        self.refresh()
        if self.autohide:
            self._hide_later()
        return False

    # --- the app's own menus -------------------------------------------
    def _session_bus(self):
        if self._bus is None:
            self._bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        return self._bus

    def _show_windowless(self, app_id):
        """A held app with no window open: its name and menus stay in the bar,
        with only what works without a window (New, About, Quit)."""
        stand_in = {"id": None, "app-id": app_id, "title": "", "windowless": True}
        self.focused = stand_in
        name = held.bus_name(app_id)
        path = held.object_path(name)
        self._use_menus((name, path + "/menus/menubar", "", "", path))
        self.app_button.set_label(apps.display_name(app_id))
        self._fill_app_menu(stand_in)
        self._fill_window_menu(None)

    def _fill_app_menus(self, view):
        if view is None and self._menu_key == ("desktop",):
            return   # the desktop's own menus are up already
        key = self._menus_of(view)
        if view and not (key and key[1]):
            # A dialog (Save, Open, an alert) publishes no menus of its own:
            # the app's menus stay up while it's in front, as on a Mac.
            others = [v for v in self._views_of(view.get("app-id") or "")
                      if v.get("id") != view.get("id")]
            for other in sorted(others, key=lambda v: v.get("last-focus-timestamp", 0), reverse=True):
                found = self._menus_of(other)
                if found and found[1]:
                    key = found
                    break
            else:
                name = held.bus_name(view.get("app-id"))
                if name and self.held.is_running(name):
                    path = held.object_path(name)
                    key = (name, path + "/menus/menubar", "", "", path)
                elif view.get("app-id"):
                    # An app that publishes no menus still gets a menu bar,
                    # as every app on a Mac has one.
                    key = ("fallback", view.get("app-id"))
        self._use_menus(key)

    def _menus_of(self, view):
        info = self.wf.app_menus(view["id"]) if (self.wf and view and view.get("id")) else None
        if not info:
            return None
        return tuple(info.get(k) or "" for k in
                     ("bus-name", "menubar-path", "app-menu-path", "window-path", "application-path"))

    def _use_menus(self, key):
        if key == self._menu_key:
            return
        self._menu_key = key
        self._menubar = None
        self._app_model = None
        self._key_models = []
        for prefix in ("app", "win"):
            self.menus_box.insert_action_group(prefix, None)
        self._groups = {}
        if key and key[0] == "fallback":
            self._menubar = fallback_menus.menubar_for(key[1])
        elif key:
            bus_name, menubar_path, app_menu_path, window_path, application_path = key
            try:
                conn = self._session_bus()
                for prefix, path in (("app", application_path), ("win", window_path)):
                    if path:
                        self._groups[prefix] = Gio.DBusActionGroup.get(conn, bus_name, path)
                        self.menus_box.insert_action_group(prefix, self._groups[prefix])
                        # The app's About and Settings join the app menu once
                        # its actions have arrived.
                        self._groups[prefix].connect(
                            "action-added", lambda *_: GLib.idle_add(self._refill_app_menu))
                if menubar_path:
                    self._menubar = Gio.DBusMenuModel.get(conn, bus_name, menubar_path)
                    self._menubar.connect("items-changed", lambda *_: self._build_menubar())
                if app_menu_path:
                    self._app_model = Gio.DBusMenuModel.get(conn, bus_name, app_menu_path)
                    self._app_model.connect("items-changed", lambda *_: self._fill_app_menu(self.focused))
            except GLib.Error:
                self._menubar = self._app_model = None
        self._build_menubar()

    def _top_level(self, model):
        """(label, submenu) for each menu of a menu bar model; items inside
        sections count as top-level too."""
        string = GLib.VariantType.new("s")
        for i in range(model.get_n_items()):
            section = model.get_item_link(i, Gio.MENU_LINK_SECTION)
            if section is not None:
                yield from self._top_level(section)
                continue
            submenu = model.get_item_link(i, Gio.MENU_LINK_SUBMENU)
            label = model.get_item_attribute_value(i, Gio.MENU_ATTRIBUTE_LABEL, string)
            if submenu is not None and label is not None:
                yield label.get_string(), submenu

    def _menu_from_model(self, model):
        menu = mac_accel.macify(Gtk.Menu.new_from_model(model))
        menu.connect("motion-notify-event", self._menu_motion)
        for prefix, group in self._groups.items():
            menu.insert_action_group(prefix, group)
        menu.insert_action_group("topline", self._own_actions)
        return self._watch_menu(menu)

    def _build_menubar(self):
        for child in self.menus_box.get_children():
            self.menus_box.remove(child)
        # Asking for the items is also what makes the model load them; it
        # calls back (items-changed) once they've arrived.
        menus = list(self._top_level(self._menubar)) if self._menubar is not None else []
        for label, submenu in menus:
            button = Gtk.MenuButton(label=label, use_underline=True)
            menu = self._menu_from_model(submenu)
            if label.replace("_", "") == "Edit":
                self._add_emoji_item(menu)
            button.set_popup(menu)
            self._slide(button)
            self.menus_box.pack_start(button, False, False, 0)
            button.show_all()
        self.menus_box.set_visible(bool(menus))
        self._queue_keys()

    def _add_emoji_item(self, menu):
        """Every app's Edit menu ends with Emoji & Symbols, as on a Mac. It
        opens Glyph once the menu has closed, so the app keeps the keyboard
        and the emoji is typed into it."""
        separator = Gtk.SeparatorMenuItem()
        menu.append(separator)
        separator.show()
        item = Gtk.MenuItem()
        box = Gtk.Box(spacing=24)
        box.pack_start(Gtk.Label(label="Emoji & Symbols", xalign=0), True, True, 0)
        keys = Gtk.Label(label="⌃⌘Space", xalign=1)
        keys.get_style_context().add_class("dim-label")
        keys.get_style_context().add_class("accelerator")
        box.pack_end(keys, False, False, 0)
        item.add(box)
        item.connect("activate", lambda *_: GLib.timeout_add(
            150, lambda: GLib.spawn_async(["freemac-glyph"], flags=GLib.SpawnFlags.SEARCH_PATH) and False))
        menu.append(item)
        item.show_all()

    def _own_action(self, name):
        view = self.focused
        if not view or not self.wf:
            return
        if name == "hide":
            self._hide_app(view)
        elif name == "hide-others":
            self._hide_others(view)
        elif name == "show-all":
            self._show_all()
        elif name == "quit":
            self._quit(view)
        elif name == "close-window" and view.get("id"):
            self.wf.close(view["id"])

    def _press(self, keys):
        """Press a shortcut in the app in front, for the menus of apps that
        publish none. Waits until the menu has closed and the app has the
        keyboard again."""
        keyval, mods = Gtk.accelerator_parse(keys)
        keymap = Gdk.Keymap.get_for_display(Gdk.Display.get_default())
        found, entries = keymap.get_entries_for_keyval(keyval) if keyval else (False, [])
        if not found or not entries or not self.wf:
            return False
        entry = min(entries, key=lambda e: (e.group, e.level))
        shift = bool(mods & Gdk.ModifierType.SHIFT_MASK) or entry.level == 1
        self.wf.press(entry.keycode - 8, ctrl=bool(mods & Gdk.ModifierType.CONTROL_MASK), shift=shift,
                      alt=bool(mods & Gdk.ModifierType.MOD1_MASK))
        return False

    def _views_of(self, app_id, same=True):
        return [v for v in (self.wf.views() if self.wf else [])
                if ((v.get("app-id") or "") == app_id) == same]

    def _hide_app(self, view):
        for other in self._views_of(view.get("app-id") or ""):
            if not is_minimized(other):
                self.wf.hide(other["id"])

    def _hide_others(self, view):
        for other in self._views_of(view.get("app-id") or "", same=False):
            if not is_minimized(other):
                self.wf.hide(other["id"])

    def _show_all(self):
        """Bring hidden apps back; minimized windows stay in the Dock."""
        hidden = self.wf.hidden() if self.wf else set()
        for other in (self.wf.views() if self.wf else []):
            if is_minimized(other) and other["id"] in hidden:
                self.wf.set_minimized(other["id"], False)

    def _app_about(self, view):
        app_id = view.get("app-id") or ""
        name = apps.display_name(app_id)
        dialog = Gtk.AboutDialog(program_name=name, comments="")
        icon = apps.icon_for(app_id)
        theme = Gtk.IconTheme.get_default()
        info = theme.lookup_by_gicon(icon, 128, 0) if icon is not None else None
        if info is not None:
            try:
                dialog.set_logo(info.load_icon())
            except GLib.Error:
                pass
        dialog.run()
        dialog.destroy()

    def _quit(self, view):
        """Close the app's windows (it may ask to save first); with no Strata,
        end its process. An app that stays open with no window quits whole."""
        if self.held.quit(view.get("app-id") or ""):
            self._windowless = None
            return
        if self.wf and self.wf.quit(view.get("app-id") or ""):
            return
        if view.get("pid"):
            os.kill(view["pid"], signal.SIGTERM)

    SETTINGS_ACTIONS = ("preferences", "settings", "prefs", "show-preferences", "show-settings")
    ABOUT_ACTIONS = ("about", "show-about")

    def _app_action(self, names):
        """(group, name) of the first of these actions the app offers."""
        for prefix in ("app", "win"):
            group = self._groups.get(prefix)
            if group is None:
                continue
            for name in names:
                if group.has_action(name) and group.get_action_enabled(name):
                    return group, name
        return None

    def _refill_app_menu(self):
        if not self._menu_open():
            self._fill_app_menu(self.focused)
        return False

    def _fill_app_menu(self, view):
        # An app with an old-style app menu: its items, then Hide and Quit.
        if view and self._app_model is not None and self._app_model.get_n_items():
            name = apps.display_name(view.get("app-id"))
            combined = Gio.Menu()
            combined.append_section(None, self._app_model)
            hiding = Gio.Menu()
            for label, action, accel in ((f"Hide {name}", "topline.hide", "<Super>h"),
                                         ("Hide Others", "topline.hide-others", "<Super><Alt>h"),
                                         ("Show All", "topline.show-all", None)):
                item = Gio.MenuItem.new(label, action)
                if accel:
                    item.set_attribute_value("accel", GLib.Variant.new_string(accel))
                hiding.append_item(item)
            combined.append_section(None, hiding)
            quitting = Gio.Menu()
            item = Gio.MenuItem.new(f"Quit {name}", "topline.quit")
            item.set_attribute_value("accel", GLib.Variant.new_string("<Super>q"))
            quitting.append_item(item)
            combined.append_section(None, quitting)
            self.app_button.set_popup(self._menu_from_model(combined))
            return
        if self.app_button.get_popup() is not self.app_menu:
            self.app_button.set_popup(self.app_menu)
        menu = self.app_menu
        self._clear(menu)
        if not view:
            self._item(menu, f"About {DESKTOP_APP}", self._about)
            menu.append(Gtk.SeparatorMenuItem())
            self._item(menu, "Empty Trash…", self._empty_trash, sensitive=_trash_has_items(),
                       shortcut="⇧⌘⌫")
            menu.append(Gtk.SeparatorMenuItem())
            self._item(menu, "Hide Others", lambda: self._hide_others({}), shortcut="⌥⌘H")
            self._item(menu, "Show All", self._show_all)
        else:
            # The same menu in every app, as on a Mac.
            name = apps.display_name(view.get("app-id"))
            about = self._app_action(self.ABOUT_ACTIONS)
            self._item(menu, f"About {name}", (lambda: about[0].activate_action(about[1], None))
                       if about else (lambda: self._app_about(view)))
            settings = self._app_action(self.SETTINGS_ACTIONS)
            if settings:
                # Command+comma reaches the app as Ctrl+comma, the shortcut
                # most apps use for their settings.
                menu.append(Gtk.SeparatorMenuItem())
                self._item(menu, "Settings\u2026", lambda: settings[0].activate_action(settings[1], None),
                           shortcut="\u2318,")
            menu.append(Gtk.SeparatorMenuItem())
            self._item(menu, f"Hide {name}", (lambda: self._hide_app(view)) if view.get("id") else None,
                       shortcut="\u2318H")
            self._item(menu, "Hide Others", lambda: self._hide_others(view), shortcut="\u2325\u2318H")
            self._item(menu, "Show All", self._show_all)
            menu.append(Gtk.SeparatorMenuItem())
            self._item(menu, f"Quit {name}", lambda: self._quit(view), shortcut="\u2318Q")
        menu.show_all()

    def _fill_window_menu(self, view):
        """Minimize, Zoom and Bring All to Front, then the app's windows with
        a tick by the front one (other apps' windows are in the dock and
        ⌘Tab, as on a Mac)."""
        menu = self.window_menu
        self._clear(menu)
        vid = view["id"] if view else None
        self._item(menu, "Minimize", (lambda: self.wf.set_minimized(vid, True)) if view else None,
                   shortcut="\u2318M")
        self._item(menu, "Zoom", (lambda: self._zoom(vid)) if view else None)
        menu.append(Gtk.SeparatorMenuItem())
        # Fill: the whole screen but the menu bar and the Dock, without going
        # full screen. Center: the same size, in the middle.
        self._item(menu, "Fill", (lambda: self._fill(view)) if view else None)
        self._item(menu, "Center", (lambda: self._center(view)) if view else None)
        menu.append(self._move_resize_item(view))
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Bring All to Front", (lambda: self._bring_all(view)) if view else None)
        if view and self.wf:
            windows = self._views_of(view.get("app-id") or "")
            if windows:
                menu.append(Gtk.SeparatorMenuItem())
            for other in windows:
                oid = other["id"]
                title = other.get("title") or apps.display_name(other.get("app-id"))
                item = self._item(menu, title[:60], lambda oid=oid: self._front(oid), check=(oid == vid))
                item.fm_window = True   # a window's name: Help finds it, Seek doesn't
        menu.show_all()

    def _front(self, view_id):
        self.wf.set_minimized(view_id, False)
        self.wf.focus(view_id)

    def _zoom(self, view_id):
        """Fill the screen's free area, or go back (the green button's job)."""
        # Wait for the menu to close first: an app asked to change size while
        # the menu still holds the pointer can keep its old size.
        def zoom():
            self.wf.focus(view_id)
            self.wf.zoom(view_id)
            return False
        GLib.timeout_add(250, zoom)

    @staticmethod
    def _tiled(view):
        return int((view.get("state") or {}).get("tiled") or 0)

    def _fresh(self, view):
        """The window as it is now; the menu may have been built earlier."""
        return next((v for v in self.wf.views() if v["id"] == view["id"]), view)

    def _fill(self, view):
        tiled = self._tiled(self._fresh(view))
        if tiled == 15:     # already fills the screen
            return
        def fill():
            self.wf.focus(view["id"])
            if tiled:
                self.wf.zoom(view["id"])   # first back to its own size
            self.wf.zoom(view["id"])
            return False
        GLib.timeout_add(250, fill)

    def _center(self, view):
        now = self._fresh(view)
        outputs = self.wf.outputs()
        area = next((o.get("workarea") for o in outputs
                     if o.get("id") == now.get("output-id") or o.get("name") == now.get("output")), None)
        if not area and outputs:
            area = outputs[0].get("workarea")
        if not area:
            return
        def center():
            self.wf.focus(view["id"])
            if self._tiled(self._fresh(view)):
                self.wf.zoom(view["id"])   # back to its own size first
                GLib.timeout_add(250, center_now)
            else:
                center_now()
            return False
        def center_now():
            box = self._fresh(view).get("geometry") or {}
            width = min(box.get("width", 800), area["width"])
            height = min(box.get("height", 600), area["height"])
            self.wf.move_to(view["id"], area["x"] + (area["width"] - width) // 2,
                            area["y"] + (area["height"] - height) // 2, width, height)
            return False
        GLib.timeout_add(250, center)

    # Window > Move & Resize: halves and quarters of the free part of the
    # screen, as on a Mac, and back to the size it had before.
    PLACES = (("Left", "left", "\u2303\u2318\u2190"), ("Right", "right", "\u2303\u2318\u2192"),
              ("Top", "top", ""), ("Bottom", "bottom", ""), None,
              ("Top Left", "tl", ""), ("Top Right", "tr", ""),
              ("Bottom Left", "bl", ""), ("Bottom Right", "br", ""))

    def _move_resize_item(self, view):
        item = Gtk.MenuItem(label="Move & Resize")
        menu = Gtk.Menu()
        for place in self.PLACES:
            if place is None:
                menu.append(Gtk.SeparatorMenuItem())
                continue
            label, how, keys = place
            self._item(menu, label, (lambda how=how: self._place(view, how)) if view else None, shortcut=keys)
        menu.append(Gtk.SeparatorMenuItem())
        before = view is not None and view["id"] in self.before_place
        self._item(menu, "Return to Previous Size", (lambda: self._unplace(view)) if before else None)
        item.set_submenu(menu)
        item.set_sensitive(view is not None)
        return item

    def _workarea(self, view):
        outputs = self.wf.outputs()
        area = next((o.get("workarea") for o in outputs
                     if o.get("id") == view.get("output-id") or o.get("name") == view.get("output")), None)
        if not area and outputs:
            area = outputs[0].get("workarea")
        return area

    @staticmethod
    def place_rect(area, how):
        """The part of the free area (x, y, width, height) a place names."""
        x, y, w, h = area["x"], area["y"], area["width"], area["height"]
        half_w, half_h = w // 2, h // 2
        return {"left": (x, y, half_w, h), "right": (x + half_w, y, w - half_w, h),
                "top": (x, y, w, half_h), "bottom": (x, y + half_h, w, h - half_h),
                "tl": (x, y, half_w, half_h), "tr": (x + half_w, y, w - half_w, half_h),
                "bl": (x, y + half_h, half_w, h - half_h),
                "br": (x + half_w, y + half_h, w - half_w, h - half_h)}[how]

    def _place(self, view, how):
        now = self._fresh(view)
        area = self._workarea(now)
        if not area:
            return
        vid = view["id"]
        if vid not in self.before_place and not self._tiled(now):
            box = now.get("geometry") or {}
            if box:
                self.before_place[vid] = (box.get("x", 0), box.get("y", 0), box.get("width", 800),
                                          box.get("height", 600))

        def place():
            self.wf.focus(vid)
            if self._tiled(self._fresh(view)):
                self.wf.zoom(vid)   # back to its own size first
                GLib.timeout_add(250, place_now)
            else:
                place_now()
            return False

        def place_now():
            self.wf.move_to(vid, *self.place_rect(area, how))
            return False
        GLib.timeout_add(250, place)

    def _unplace(self, view):
        rect = self.before_place.pop(view["id"], None)
        if rect is None:
            return

        def back():
            self.wf.focus(view["id"])
            self.wf.move_to(view["id"], *rect)
            return False
        GLib.timeout_add(250, back)

    def _bring_all(self, view):
        # Minimized windows stay in the Dock, as on a Mac; hidden ones come back.
        hidden = self.wf.hidden() if self.wf else set()
        others = [v for v in self._views_of(view.get("app-id") or "") if v["id"] != view["id"]
                  and (not is_minimized(v) or v["id"] in hidden)]
        for other in others:
            if is_minimized(other):
                self.wf.set_minimized(other["id"], False)
            self.wf.focus(other["id"])
        self.wf.focus(view["id"])


def _os_version():
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("VERSION="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return ""


def main():
    style.apply()
    win = Topline()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
