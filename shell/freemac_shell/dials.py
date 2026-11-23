# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials: freemac's settings app.

Appearance (light and dark), wallpaper, dock, displays, trackpad and mouse,
keyboard, network, sound, power, accessibility, notifications and an About
page. Settings are written to the same files the rest of
the desktop reads (GSettings, ~/.config/wayfire.ini, ~/.config/wf-shell.ini and
~/.config/freemac/pier.json), and every running part follows the change.
"""
import glob
import json
import os
import platform
import re
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import battery, default_apps, dials_accounts, dials_backup, dials_input, dials_keys, dials_login, dials_more, dials_update, dials_people, dials_seek, dials_sharing, dials_storage, dials_time, menus, pier, screen, style, sun, update_notice  # noqa: E402
from .network import NetworkPanel  # noqa: E402

CONFIG = os.path.expanduser("~/.config")
WAYFIRE_INI = os.path.join(CONFIG, "wayfire.ini")
SHELL_INI = os.path.join(CONFIG, "wf-shell.ini")
WALLPAPERS = "/usr/share/backgrounds/freemac"
LIGHT_WALL = os.path.join(WALLPAPERS, "dusk-tide.png")
DARK_WALL = os.path.join(WALLPAPERS, "night-tide.png")
# freemac's own scenes, each with a day and a night version (art/make-wallpaper.py).
SCENES = (
    ("Tide", "dusk-tide.png", "night-tide.png"),
    ("Lagoon", "lagoon-day.png", "lagoon-night.png"),
    ("Prism", "prism-day.png", "prism-night.png"),
    ("Harbor", "harbor-day.png", "harbor-night.png"),
)


TOOLKITS = "/usr/share/freemac"  # GTK 4 and Qt colours (art/gtk-theme/make-theme.py)
GTK4_CSS = os.path.join(GLib.get_user_config_dir(), "gtk-4.0", "gtk.css")
QT_CONFS = [os.path.join(GLib.get_user_config_dir(), name, name + ".conf") for name in ("qt5ct", "qt6ct")]
KVANTUM_CONF = os.path.join(GLib.get_user_config_dir(), "Kvantum", "kvantum.kvconfig")


def _toolkit_file(folder, blue, accent):
    """The accent's own colours file, or the blue one if this computer's
    themes predate accent colours."""
    if accent != "blue":
        stem, ext = os.path.splitext(blue)
        coloured = os.path.join(TOOLKITS, folder, f"{stem}-{accent}{ext}")
        if os.path.exists(coloured):
            return coloured
    return os.path.join(TOOLKITS, folder, blue)


def apply_toolkits(dark):
    """GTK 4 (libadwaita) and Qt apps take light or dark, and the accent
    colour, from their own files. A gtk.css of the person's own (not our link)
    is left alone."""
    accent = style.accent()
    css = _toolkit_file("gtk4", "dark.css" if dark else "light.css", accent)
    if os.path.exists(css) and (os.path.islink(GTK4_CSS) or not os.path.exists(GTK4_CSS)):
        os.makedirs(os.path.dirname(GTK4_CSS), exist_ok=True)
        tmp = GTK4_CSS + ".new"
        if os.path.lexists(tmp):
            os.remove(tmp)
        os.symlink(css, tmp)
        os.replace(tmp, GTK4_CSS)
    scheme = _toolkit_file("qt", "freemac-dark.conf" if dark else "freemac.conf", accent)
    for conf in QT_CONFS:
        if os.path.exists(conf):
            ini_set(conf, "Appearance", "color_scheme_path", scheme)
    set_kvantum_theme("freemac-dark" if dark else "freemac")


def set_kvantum_theme(name):
    """Qt 5 apps' buttons and fields (freemac's Kvantum themes, light or dark).
    A Kvantum theme the person chose themselves is left alone."""
    try:
        with open(KVANTUM_CONF) as f:
            current = f.read()
    except OSError:
        current = ""
    chosen = [line.split("=", 1)[1].strip() for line in current.splitlines()
              if line.replace(" ", "").startswith("theme=")]
    if chosen and chosen[0] not in ("freemac", "freemac-dark"):
        return
    if chosen and chosen[0] == name:
        return
    os.makedirs(os.path.dirname(KVANTUM_CONF), exist_ok=True)
    if chosen:
        ini_set(KVANTUM_CONF, "General", "theme", name)
    else:
        tmp = KVANTUM_CONF + ".new"
        with open(tmp, "w") as f:
            f.write(f"[General]\ntheme={name}\n")
        os.replace(tmp, KVANTUM_CONF)


def theme_for(dark):
    """The accent colour's GTK theme, or plain freemac if this computer's
    themes predate accent colours."""
    name = style.theme_name(dark)
    for root in (os.path.join(GLib.get_user_data_dir(), "themes"), "/usr/share/themes"):
        if os.path.isdir(os.path.join(root, name)):
            return name
    return style.theme_name(dark, "blue")


def apply_appearance(dark, settings=None, follow_wallpaper=True):
    """Switch light/dark everywhere: GTK, title bars and (optionally) the wallpaper.

    Needs no window, so `freemac-dials --appearance` (used by Welcome) never
    opens Dials.
    """
    settings = settings if settings is not None else style.interface_settings()
    if settings:
        settings.set_string("color-scheme", "prefer-dark" if dark else "prefer-light")
        settings.set_string("gtk-theme", theme_for(dark))
    Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", dark)
    try:
        apply_toolkits(dark)
    except OSError:
        pass
    # Title bars the window manager draws follow the mode too.
    ini_set(WAYFIRE_INI, "decoration", "active_color", "#36363AFF" if dark else "#E9E9ECFF")
    ini_set(WAYFIRE_INI, "decoration", "inactive_color", "#2A2A2EFF" if dark else "#F5F5F7FF")
    current = ini_get(SHELL_INI, "background", "image")
    other = scene_version(current, dark)
    if follow_wallpaper and other and other != current:
        ini_set(SHELL_INI, "background", "image", other)


def scene_version(path, dark):
    """The day or night version of a built-in scene, or None for other pictures."""
    name = os.path.basename(path or "")
    if path and os.path.dirname(path) != WALLPAPERS:
        return None
    for _title, day, night in SCENES:
        if name in (day, night) or not path:
            return os.path.join(WALLPAPERS, night if dark else day)
    return None
from .dials_pages import SEARCH_WORDS  # noqa: E402  (also used by Seek)

CSS = b"""
.dials-search { margin: 10px 10px 4px 10px; }
.dials-sidebar { background-color: rgba(120, 120, 150, 0.08); }
.dials-sidebar list, .dials-sidebar list row { background: none; border: none; box-shadow: none; }
.dials-sidebar scrolledwindow, .dials-sidebar viewport { background: none; border: none; }
.dials-sidebar list row { padding: 4px 8px; border-radius: 6px; margin: 0 10px; min-height: 0; }
.dials-sidebar list row:hover { background-color: rgba(120, 120, 150, 0.12); }
.dials-sidebar list row:selected { background-color: @theme_selected_bg_color; color: #ffffff; }
.dials-gap { min-height: 10px; }
.dials-tile { border-radius: 6px; min-width: 22px; min-height: 22px; color: #ffffff; }
.dials-tile image { color: #ffffff; -gtk-icon-shadow: none; }
.dials-tile-blue { background-image: linear-gradient(#3d8bff, #1f6fe8); }
.dials-tile-teal { background-image: linear-gradient(#4cc4dc, #2aa0bd); }
.dials-tile-indigo { background-image: linear-gradient(#6e6cf0, #4f4dc9); }
.dials-tile-green { background-image: linear-gradient(#48cf6b, #2fae4f); }
.dials-tile-red { background-image: linear-gradient(#ff5a50, #e5372e); }
.dials-tile-pink { background-image: linear-gradient(#ff4f78, #e2325a); }
.dials-tile-gray { background-image: linear-gradient(#9a9aa1, #77777e); }
.dials-tile-dark { background-image: linear-gradient(#5a5a60, #3a3a3f); }
.dials-page { padding: 24px 32px; }
.dials-title { font-size: 22px; font-weight: 800; margin-bottom: 8px; }
.dials-group { border-radius: 12px; background-color: rgba(120, 120, 150, 0.08); padding: 4px 0; }
.dials-group row { padding: 10px 16px; }
.dials-caption { opacity: 0.65; font-size: 12px; }
.storage-key, .storage-key flowboxchild { background: none; padding: 0; }
/* Sound > Input level: a row of round lights, as on a Mac. */
levelbar.input-level trough { border: none; background: none; box-shadow: none; padding: 0; }
levelbar.input-level block { min-width: 9px; min-height: 9px; border-radius: 5px; margin: 0 2px;
                             border: none; box-shadow: none; }
levelbar.input-level block.empty { background-color: alpha(currentColor, 0.15); }
levelbar.input-level block.filled { background-color: @theme_selected_bg_color; }
.dials-flow, .dials-flow flowboxchild { background: none; padding: 0; }
.dials-days button:checked { background-image: none; background-color: @theme_selected_bg_color;
  color: @theme_selected_fg_color; border-color: @theme_selected_bg_color; box-shadow: none; }
.dials-days button:checked:disabled { background-color: alpha(@theme_fg_color, 0.12); color: alpha(@theme_fg_color, 0.45);
  border-color: alpha(@theme_fg_color, 0.12); }
.dials-error { color: #f04d3e; font-size: 12px; }
.dials-choice { padding: 8px; border-radius: 12px; border: 2px solid transparent; background: none; box-shadow: none; }
.dials-choice:checked { border-color: @theme_selected_bg_color; }
.dials-accent { min-width: 18px; min-height: 18px; padding: 0; border-radius: 99px; border: none;
  background-image: none; box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.15); }
.dials-accent:checked { box-shadow: 0 0 0 2px @theme_bg_color, 0 0 0 4px alpha(@theme_fg_color, 0.35); }
.dials-chosen { border-color: @theme_selected_bg_color; }
.dials-section { font-weight: bold; margin-top: 12px; }
.dials-count { background-color: #f04d3e; color: #ffffff; border-radius: 99px; min-width: 18px;
  padding: 0 5px; font-size: 11px; font-weight: bold; }
.input-badge { min-width: 30px; padding: 1px 4px; border-radius: 4px; font-size: 11px; font-weight: bold;
  border: 1px solid alpha(@theme_fg_color, 0.5); }
"""


# ---- small config helpers ---------------------------------------------------
# ini_get and ini_set live in ini.py, so Topline can use them without loading Dials.
from .ini import ini_get, ini_set  # noqa: E402,F401


def pier_config():
    return pier.load_config()


def save_pier(**changes):
    config = pier_config()
    config.update(changes)
    os.makedirs(os.path.dirname(pier.CONFIG), exist_ok=True)
    with open(pier.CONFIG, "w") as f:
        json.dump(config, f, indent=2)


# ---- widgets -----------------------------------------------------------------
def group(*rows):
    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.get_style_context().add_class("dials-group")
    for row in rows:
        listbox.add(row)
    return listbox


def row(title, widget=None, caption=None):
    line = Gtk.Box(spacing=12)
    text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    text.pack_start(Gtk.Label(label=title, xalign=0), False, False, 0)
    if caption:
        cap = Gtk.Label(label=caption, xalign=0, wrap=True)
        cap.get_style_context().add_class("dials-caption")
        text.pack_start(cap, False, False, 0)
    line.pack_start(text, True, True, 0)
    if widget is not None:
        widget.set_valign(Gtk.Align.CENTER)
        line.pack_end(widget, False, False, 0)
    item = Gtk.ListBoxRow(activatable=False)
    item.add(line)
    return item


def switch(active, on_change):
    sw = Gtk.Switch(active=active)
    sw.connect("notify::active", lambda s, _p: on_change(s.get_active()))
    return sw


def slider(low, high, step, value, on_change, width=220, marks=()):
    scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, low, high, step)
    scale.set_value(value)
    scale.set_draw_value(False)
    scale.set_size_request(width, -1)
    for mark, label in marks:
        scale.add_mark(mark, Gtk.PositionType.BOTTOM, label)
    pending = {}

    def changed(s):
        # Write once the slider settles, not on every pixel of a drag.
        if pending.get("id"):
            GLib.source_remove(pending["id"])
        pending["id"] = GLib.timeout_add(250, lambda: on_change(s.get_value()) or pending.clear() or False)

    scale.connect("value-changed", changed)
    scale.connect("scroll-event", _scroll_page)
    return scale


def _scroll_page(widget, event):
    """A scroll over a slider scrolls the page, as on a Mac, rather than
    moving the slider as the page goes by under the pointer."""
    page = widget.get_ancestor(Gtk.ScrolledWindow)
    if page is not None:
        page.event(event)
    return True


def thumbnail(path, width=180, height=110):
    try:
        return GdkPixbuf.Pixbuf.new_from_file_at_scale(path, width, height, False)
    except GLib.Error:
        return None


def page(title, *children):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    box.get_style_context().add_class("dials-page")
    heading = Gtk.Label(label=title, xalign=0)
    heading.get_style_context().add_class("dials-title")
    box.pack_start(heading, False, False, 0)
    for child in children:
        box.pack_start(child, False, False, 0)
    scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
    scroll.add(box)
    return scroll


# ---- the app -----------------------------------------------------------------
class DialsWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Dials")
        self.set_default_size(860, 580)
        self.settings = style.interface_settings()
        self.helpers = (group, row, page, slider, switch)
        header = Gtk.HeaderBar(show_close_button=True, title="Dials")
        self.set_titlebar(header)

        paned = Gtk.Paned()
        self.add(paned)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        sidebar = Gtk.ListBox()
        sidebar.get_style_context().add_class("dials-sidebar")
        sidebar.set_size_request(200, -1)
        sidebar.connect("row-selected", lambda _l, r: r and self._show_page(r.name))
        side_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side_box.get_style_context().add_class("dials-sidebar")
        # Search at the top, as on a Mac: typing narrows the list to the
        # settings whose name or usual words match, and Return opens the first.
        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.get_style_context().add_class("dials-search")
        self.search.connect("search-changed", self._search_changed)
        self.search.connect("activate", self._search_open)
        side_box.pack_start(self.search, False, False, 0)
        # The list scrolls, so that with every pane in it the window still
        # fits a small screen, as a Mac's settings sidebar does.
        side_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,
                                         vscrollbar_policy=Gtk.PolicyType.AUTOMATIC)
        side_scroll.add(sidebar)
        side_box.pack_start(side_scroll, True, True, 6)
        sidebar.set_filter_func(self._search_match)
        paned.pack1(side_box, False, False)
        paned.pack2(self.stack, True, False)
        paned.set_position(200)

        self.rows = {}
        # Each page is built the first time it's shown, so the window opens
        # at once instead of after every page (sound, power, printers...)
        # has asked the system how it is.
        self.builders = {}
        # Grouped the way a Mac's settings sidebar is: connections, then
        # alerts and sound, then how things look, power, people, and the
        # devices you hold. Each icon sits white in a small coloured tile.
        # The group number puts a little space between groups.
        for group_no, name, title, icon, colour, build in (
            (0, "network", "Network", "network-wired-symbolic", "blue", self.network),
            (0, "bluetooth", "Bluetooth", "bluetooth-active-symbolic", "blue",
             lambda: dials_people.BluetoothPanel(self, page)),
            (0, "sharing", "Sharing", "folder-publicshare-symbolic", "blue",
             lambda: dials_sharing.sharing_page(self)),
            (1, "notifications", "Notifications", "preferences-system-notifications-symbolic", "red",
             lambda: dials_more.notifications(self)),
            (1, "focus", "Focus", "freemac-focus-dnd-symbolic", "indigo", lambda: dials_more.focus(self)),
            (1, "sound", "Sound", "audio-volume-high-symbolic", "pink", lambda: dials_more.sound(self)),
            (2, "about", "About", "help-about-symbolic", "gray", self.about),
            (2, "storage", "Storage", "drive-harddisk-symbolic", "gray",
             lambda: dials_storage.storage_page(self)),
            (2, "softwareupdate", "Software Update", "freemac-software-update-symbolic", "gray",
             lambda: dials_update.software_update_page(self)),
            (2, "datetime", "Date & Time", "preferences-system-time-symbolic", "blue",
             lambda: dials_time.DateTimePanel(self, page)),
            (2, "appearance", "Appearance", "preferences-desktop-appearance-symbolic", "dark", self.appearance),
            (2, "accessibility", "Accessibility", "preferences-desktop-accessibility-symbolic", "blue",
             lambda: dials_more.accessibility(self)),
            (2, "dock", "Dock and Menu Bar", "view-app-grid-symbolic", "dark", self.dock),
            (2, "seek", "Seek", "system-search-symbolic", "gray", lambda: dials_seek.seek_page(self)),
            (2, "displays", "Displays", "video-display-symbolic", "blue", self.displays),
            (2, "wallpaper", "Wallpaper", "preferences-desktop-wallpaper-symbolic", "teal", self.wallpaper),
            (2, "screensaver", "Screen Saver", "weather-clear-night-symbolic", "indigo",
             lambda: dials_more.screen_saver(self)),
            (3, "power", "Battery" if battery.find() else "Power", "battery-good-symbolic", "green",
             lambda: dials_more.power(self)),
            (3, "lifeboat", "Lifeboat", "document-open-recent-symbolic", "teal",
             lambda: dials_backup.BackupPanel(self, page)),
            (4, "users", "Users", "system-users-symbolic", "indigo", lambda: dials_people.UsersPanel(self, page)),
            (4, "loginitems", "Login Items", "system-run-symbolic", "gray",
             lambda: dials_login.login_items_page(self)),
            (4, "accounts", "Internet Accounts", "emblem-synchronizing-symbolic", "blue",
             lambda: dials_accounts.AccountsPanel(self, page)),
            (5, "keyboard", "Keyboard", "input-keyboard-symbolic", "gray", self.keyboard),
            (5, "pointing", "Trackpad and Mouse", "input-touchpad-symbolic", "gray", self.pointing),
            (5, "printers", "Printers", "printer-symbolic", "gray", lambda: dials_people.PrintersPanel(self, page)),
        ):
            item = Gtk.ListBoxRow()
            item.name, item.group_no = name, group_no
            item.words = (title + " " + SEARCH_WORDS.get(name, "")).lower()
            line = Gtk.Box(spacing=8)
            tile = Gtk.Box(halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
            tile.get_style_context().add_class("dials-tile")
            tile.get_style_context().add_class("dials-tile-" + colour)
            image = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU)
            image.set_pixel_size(14)
            tile.set_center_widget(image)
            line.pack_start(tile, False, False, 0)
            line.pack_start(Gtk.Label(label=title, xalign=0), True, True, 0)
            if name == "softwareupdate":
                # A red count when updates are ready, as a Mac's settings show.
                self.update_count = Gtk.Label(valign=Gtk.Align.CENTER)
                self.update_count.get_style_context().add_class("dials-count")
                self.update_count.set_no_show_all(True)
                line.pack_end(self.update_count, False, False, 0)
            item.add(line)
            sidebar.add(item)
            self.rows[name] = item
            self.builders[name] = build
            self.stack.add_named(Gtk.Box(), name)

        def gap(row, before):
            if before is not None and before.group_no != row.group_no:
                if row.get_header() is None:
                    space = Gtk.Box()
                    space.get_style_context().add_class("dials-gap")
                    row.set_header(space)
            else:
                row.set_header(None)

        sidebar.set_header_func(gap)
        self.sidebar = sidebar
        self._show_update_count()
        try:
            os.makedirs(os.path.dirname(update_notice.STATE), exist_ok=True)
            folder = Gio.File.new_for_path(os.path.dirname(update_notice.STATE))
            self.update_watch = folder.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
            self.update_watch.connect("changed", lambda *_: self._show_update_count())
        except (OSError, GLib.Error):
            self.update_watch = None
        sidebar.select_row(self.rows["appearance"])
        # The stack can't show a page before the window is shown, so it
        # opened on the first one; show the selected page once it can.
        self.connect("map", lambda *_: GLib.idle_add(self._show_selected))
        actions = {"close": self.close}
        for name in self.rows:
            actions["show-" + name] = lambda n=name: self.show_panel(n)
        menus.add_actions(self, actions)
        self.connect("key-press-event", self._on_key)

    def _show_update_count(self):
        """The red count beside Software Update: the updates Beacon found."""
        count = len(update_notice.load().get("ids") or [])
        self.update_count.set_text(str(count))
        self.update_count.set_visible(count > 0)

    def _show_selected(self):
        row = self.sidebar.get_selected_row()
        if row is not None:
            self._show_page(row.name)
        return False

    def _built(self, name):
        """The page called name, built now if it hasn't been yet."""
        build = self.builders.pop(name, None)
        if build is not None:
            stand_in = self.stack.get_child_by_name(name)
            widget = build()
            self.stack.remove(stand_in)
            self.stack.add_named(widget, name)
            widget.show_all()
        return self.stack.get_child_by_name(name)

    def _show_page(self, name):
        self._built(name)
        self.stack.set_visible_child_name(name)

    def _on_key(self, _widget, event):
        if event.state & Gdk.ModifierType.CONTROL_MASK and event.keyval in (Gdk.KEY_w, Gdk.KEY_W):
            self.close()
            return True
        return False

    @staticmethod
    def ini_get(section, key, default=None):
        return ini_get(WAYFIRE_INI, section, key, default)

    @staticmethod
    def ini_set(section, key, value):
        ini_set(WAYFIRE_INI, section, key, value)

    def confirm_power(self, action):
        """Sleep, Restart… and Shut Down… ask and quit apps as the freemac
        menu does (freemac-power)."""
        words = {"suspend": "sleep", "reboot": "restart", "poweroff": "shutdown"}
        Gio.Subprocess.new(["freemac-power", words[action]], Gio.SubprocessFlags.NONE)

    def _search_match(self, row):
        text = self.search.get_text().strip().lower()
        return not text or all(part in row.words for part in text.split())

    def _search_changed(self, _entry):
        self.sidebar.invalidate_filter()
        self.sidebar.invalidate_headers()
        first = self._first_found()
        if first is not None and self.search.get_text().strip():
            self.sidebar.select_row(first)

    def _first_found(self):
        return next((row for row in self.sidebar.get_children()
                     if row.get_child_visible() and self._search_match(row)), None)

    def _search_open(self, _entry):
        if not self.search.get_text().strip():
            return
        first = self._first_found()
        if first is not None:
            self.sidebar.select_row(first)

    def show_panel(self, name):
        if name in self.rows:
            self.sidebar.select_row(self.rows[name])

    # Appearance ---------------------------------------------------------------
    def appearance(self):
        """Light, Dark or Auto (light by day and dark at night, from
        sunrise and sunset where you are; Topline does the switching)."""
        choices = Gtk.Box(spacing=10)
        first = None
        self.mode_buttons = {}
        light_pix, dark_pix = thumbnail(LIGHT_WALL, 100, 62), thumbnail(DARK_WALL, 100, 62)
        auto_pix = None
        if light_pix and dark_pix:
            # Half day, half night.
            auto_pix = light_pix.copy()
            dark_pix.copy_area(50, 0, 50, 62, auto_pix, 50, 0)
        for mode, label, pixbuf in (("light", "Light", light_pix), ("dark", "Dark", dark_pix),
                                    ("auto", "Auto", auto_pix)):
            button = Gtk.RadioButton.new_from_widget(first)
            first = first or button
            button.set_mode(False)
            button.get_style_context().add_class("dials-choice")
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            if pixbuf:
                inner.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), False, False, 0)
            inner.pack_start(Gtk.Label(label=label), False, False, 0)
            button.add(inner)
            button.handler = button.connect("toggled", lambda b, m=mode: b.get_active() and self.set_mode(m))
            self.mode_buttons[mode] = button
            choices.pack_start(button, False, False, 0)
        self._show_mode()
        if self.settings:
            # Show the change when the mode is switched from elsewhere.
            self.settings.connect("changed::color-scheme", lambda *_: self._show_mode())
        where = sun.times_today(h24=style.prefs().get("clock") == "24")
        self.auto_note = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
        self.auto_note.get_style_context().add_class("dials-caption")
        self.auto_note.set_label(
            f"Auto is light from sunrise ({where[0]}) and dark from sunset ({where[1]}) today, "
            "for your time zone in Date & Time." if where else
            "Auto needs a time zone in Date & Time to know when the sun rises and sets.")
        self.follow_wallpaper = Gtk.Switch(active=True)
        text_size = Gtk.ComboBoxText()
        for value, name in (("1.0", "Default"), ("1.15", "Large"), ("1.3", "Larger")):
            text_size.append(value, name)
        current = self.settings.get_double("text-scaling-factor") if self.settings else 1.0
        text_size.set_active_id(min(("1.0", "1.15", "1.3"), key=lambda v: abs(float(v) - current)))
        text_size.connect("changed", lambda c: self.settings and self.settings.set_double(
            "text-scaling-factor", float(c.get_active_id())))
        snap = Gtk.Switch(active=ini_get(WAYFIRE_INI, "move", "enable_snap", "true") != "false")
        snap.connect("notify::active", lambda sw, _p: ini_set(
            WAYFIRE_INI, "move", "enable_snap", "true" if sw.get_active() else "false"))
        return page("Appearance", choices, self.auto_note, group(
            row("Accent colour", self.accent_choices(),
                "Used for selections, switches and buttons in every app."),
            row("Switch wallpaper with the mode", self.follow_wallpaper,
                "freemac's own wallpapers have a day and a night version."),
            row("Text size", text_size),
        ), group(
            row("Tile windows at the screen edges", snap,
                "Drag a window to the left or right edge to fill half the screen, to a corner for a "
                "quarter, or to the top to fill it."),
        ))

    def accent_choices(self):
        """A row of coloured circles, one per accent colour, as on a Mac."""
        box = Gtk.Box(spacing=6, valign=Gtk.Align.CENTER)
        first = None
        current = style.accent()
        for name, label, colour in style.ACCENTS:
            button = Gtk.RadioButton.new_from_widget(first)
            first = first or button
            button.set_mode(False)
            button.set_tooltip_text(label)
            button.get_accessible().set_name(label)
            button.get_style_context().add_class("dials-accent")
            provider = Gtk.CssProvider()
            provider.load_from_data(f".dials-accent {{ background-color: {colour}; }}".encode())
            button.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
            button.set_active(name == current)
            button.connect("toggled", lambda b, n=name: b.get_active() and self.set_accent(n))
            box.pack_start(button, False, False, 0)
        return box

    def set_accent(self, name):
        self.save_prefs(accent=name)
        if self.settings and self.settings.get_string("gtk-theme") != "HighContrast":
            self.settings.set_string("gtk-theme", theme_for(style.is_dark()))
        try:
            apply_toolkits(style.is_dark())
        except OSError:
            pass

    def _show_mode(self):
        if style.prefs().get("appearance_auto", False):
            mode = "auto"
        else:
            mode = "dark" if style.is_dark() else "light"
        button = self.mode_buttons[mode]
        with button.handler_block(button.handler):
            button.set_active(True)

    def set_mode(self, mode):
        """Light or Dark stays as it is; Auto follows the sun from now on."""
        self.save_prefs(appearance_auto=(mode == "auto"))
        if mode == "auto":
            day = sun.is_day()
            if day is not None and day == style.is_dark():
                self.set_dark(not day)
        else:
            self.set_dark(mode == "dark")

    def set_dark(self, dark):
        self._built("appearance")
        apply_appearance(dark, self.settings, self.follow_wallpaper.get_active())
        self.refresh_wallpapers()

    # Wallpaper ----------------------------------------------------------------
    def wallpaper(self):
        self.wall_flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4,
                                     column_spacing=12, row_spacing=12, homogeneous=True)
        self.refresh_wallpapers()
        note = Gtk.Label(label="Each freemac wallpaper has a day and a night version. It follows "
                               "light and dark mode, or the sun when Dynamic is on.", xalign=0, wrap=True)
        note.get_style_context().add_class("dials-caption")
        choose = Gtk.Button(label="Choose a Picture…", halign=Gtk.Align.START)
        choose.connect("clicked", self.choose_wallpaper)
        fit = Gtk.ComboBoxText()
        fit.append("fill", "Fill screen")
        fit.append("fit", "Fit to screen")
        fit.append("stretch", "Stretch")
        fit.set_active_id(ini_get(SHELL_INI, "background", "fit", "fill"))
        fit.connect("changed", lambda c: ini_set(SHELL_INI, "background", "fit", c.get_active_id()))
        # Dynamic, as a Mac's Dynamic Desktop: the scene follows the sun (backdrop.py).
        dynamic = Gtk.Switch(active=ini_get(SHELL_INI, "background", "dynamic", "false") == "true",
                             valign=Gtk.Align.CENTER)
        dynamic.connect("notify::active", lambda s, _p: ini_set(
            SHELL_INI, "background", "dynamic", "true" if s.get_active() else "false"))
        return page("Wallpaper", self.wall_flow, note, choose,
                    group(row("Dynamic", dynamic,
                              "freemac's own wallpapers follow the sun where you are: day, "
                              "a golden sunset, then night."),
                          row("Picture fit", fit)))

    def refresh_wallpapers(self):
        """One tile per scene, showing the version for the current mode."""
        if not hasattr(self, "wall_flow"):
            return
        for child in self.wall_flow.get_children():
            self.wall_flow.remove(child)
        dark = style.is_dark()
        current = ini_get(SHELL_INI, "background", "image") or LIGHT_WALL
        tiles = []
        own = set()
        for title, day, night in SCENES:
            own.update((day, night))
            tiles.append((title, os.path.join(WALLPAPERS, night if dark else day),
                          current in (os.path.join(WALLPAPERS, day), os.path.join(WALLPAPERS, night))))
        for path in sorted(glob.glob(os.path.join(WALLPAPERS, "*.png")) + glob.glob(os.path.join(WALLPAPERS, "*.jpg"))):
            if os.path.basename(path) not in own:
                title = os.path.splitext(os.path.basename(path))[0].replace("-", " ").title()
                tiles.append((title, path, path == current))
        for title, path, chosen in tiles:
            pixbuf = thumbnail(path)
            if not pixbuf:
                continue
            button = Gtk.Button()
            button.get_style_context().add_class("dials-choice")
            if chosen:
                button.get_style_context().add_class("dials-chosen")
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            inner.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), False, False, 0)
            inner.pack_start(Gtk.Label(label=title), False, False, 0)
            button.add(inner)
            button.connect("clicked", lambda _b, p=path: self.set_wallpaper(p))
            self.wall_flow.add(button)
        self.wall_flow.show_all()

    def set_wallpaper(self, path):
        ini_set(SHELL_INI, "background", "image", path)
        self.refresh_wallpapers()

    def choose_wallpaper(self, _button):
        dialog = Gtk.FileChooserNative(title="Choose a Picture", transient_for=self,
                                       action=Gtk.FileChooserAction.OPEN)
        images = Gtk.FileFilter()
        images.set_name("Pictures")
        images.add_pixbuf_formats()
        dialog.add_filter(images)
        pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
        if pictures and os.path.isdir(pictures):
            dialog.set_current_folder(pictures)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            self.set_wallpaper(dialog.get_filename())
        dialog.destroy()

    # Dock and menu bar --------------------------------------------------------
    def dock(self):
        config = pier_config()
        size = slider(32, 80, 2, config["size"], lambda v: save_pier(size=int(v)),
                      marks=((32, "Small"), (80, "Large")))
        peak = slider(48, 128, 4, config["peak"], lambda v: save_pier(peak=int(v)),
                      marks=((48, "Less"), (128, "More")))
        peak.set_sensitive(config["magnify"])

        def magnify(on):
            save_pier(magnify=on)
            peak.set_sensitive(on)

        position = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for side in pier.SIDES:
            position.append(side, side.capitalize())
        position.set_active_id(config.get("position") if config.get("position") in pier.SIDES else "bottom")
        position.connect("changed", lambda c: save_pier(position=c.get_active_id()))

        downloads = pier.default_stacks()[0]

        def show_downloads(on):
            stacks = [f for f in pier_config()["stacks"] if f != downloads]
            save_pier(stacks=([downloads] if on else []) + stacks)

        return page("Dock and Menu Bar", group(
            row("Icon size", size),
            row("Magnification", switch(config["magnify"], magnify), "Icons grow as the pointer passes over them."),
            row("Magnified size", peak),
            row("Position on screen", position),
            row("Automatically hide and show the Dock", switch(config.get("autohide", False),
                                                                 lambda on: save_pier(autohide=on)),
                "The Dock slides away until you move the pointer to the edge of the screen it sits on. "
                "\u2325\u2318D turns this on and off."),
        ), group(
            row("Downloads", switch(downloads in config["stacks"], show_downloads),
                "A folder on the dock that shows your newest downloads."),
            row("Trash", switch(config["trash"], lambda on: save_pier(trash=on)),
                "Drop files on it to throw them away; right-click it to empty it."),
            row("Show recent apps in Dock", switch(config.get("recents", True), lambda on: save_pier(recents=on)),
                "Up to three apps you used lately stay in the Dock after they quit."),
            row("Show indicators for open apps", switch(config.get("indicators", True), lambda on: save_pier(indicators=on)),
                "A dot under each app that's open."),
            row("Show badges on Dock icons", switch(config.get("badges", True), lambda on: save_pier(badges=on)),
                "A red number on an app's icon, such as unread mail in Post or reminders due in Nudge."),
            row("Animate opening apps", switch(config.get("bounce", True), lambda on: save_pier(bounce=on)),
                "An app's icon bounces until its window appears."),
        ), group(
            row("Stage Manager", switch(config.get("stage", False), lambda on: save_pier(stage=on)),
                "The app you're using stands alone in the middle, and the apps you used just before it "
                "wait as small pictures down the left side. Click one to bring it forward."),
        ), group(
            row("Automatically hide and show the menu bar",
                switch(bool(style.prefs().get("menubar_autohide")),
                       lambda on: self.save_prefs(menubar_autohide=on)),
                "The menu bar slides away until you move the pointer to the top of the screen."),
            row("Click wallpaper to reveal desktop",
                switch(bool(style.prefs().get("click_reveal")), lambda on: self.save_prefs(click_reveal=on)),
                "Click the desktop picture and your windows step aside, so you can use the files on the "
                "desktop. Click it again to bring them back."),
        ), group(
            row("Default web browser", default_apps.chooser(default_apps.BROWSER),
                "Opens the links you click in other apps."),
            row("Default email app", default_apps.chooser(default_apps.MAIL),
                "Opens when you click an email address."),
        ), group(row("Double-click a window's title bar to", self.title_double_click()),
                 row("Minimize windows into application icon",
                     switch(config.get("minimize_into_app", False), lambda on: save_pier(minimize_into_app=on)),
                     "Off: a minimized window gets its own picture at the right end of the dock.")),
            self.hot_corners())

    # What a double-click on a title bar does: freemac's own title bars read
    # it from wayfire.ini, apps that draw their own read GNOME's setting.
    TITLE_CLICK = (("zoom", "Zoom", "toggle-maximize"), ("minimize", "Minimize", "minimize"),
                   ("none", "Do Nothing", "none"))

    def title_double_click(self):
        choice = Gtk.ComboBoxText()
        for value, label, _gnome in self.TITLE_CLICK:
            choice.append(value, label)
        choice.set_active_id(ini_get(WAYFIRE_INI, "strata-decor", "double_click", "zoom") or "zoom")
        if not choice.get_active_id():
            choice.set_active_id("zoom")

        def changed(combo):
            value = combo.get_active_id()
            ini_set(WAYFIRE_INI, "strata-decor", "double_click", value)
            gnome = dict((v, g) for v, _l, g in self.TITLE_CLICK)[value]
            source = Gio.SettingsSchemaSource.get_default()
            if source and source.lookup("org.gnome.desktop.wm.preferences", True):
                Gio.Settings.new("org.gnome.desktop.wm.preferences").set_string(
                    "action-double-click-titlebar", gnome)

        choice.connect("changed", changed)
        return choice

    def hot_corners(self):
        from . import corners

        get = lambda sec, key, default=None: ini_get(WAYFIRE_INI, sec, key, default)  # noqa: E731
        put = lambda sec, key, value: ini_set(WAYFIRE_INI, sec, key, value)  # noqa: E731
        now = corners.current(get)
        rows = []
        for corner, label in corners.CORNERS:
            choice = Gtk.ComboBoxText()
            for action in corners.ORDER:
                choice.append(action, corners.ACTIONS[action][0])
            choice.set_active_id(now[corner])
            choice.connect("changed", lambda c, k=corner: corners.assign(get, put, k, c.get_active_id()))
            rows.append(row(label, choice))
        heading = Gtk.Label(label="Hot Corners", xalign=0)
        heading.get_style_context().add_class("dials-section")
        note = Gtk.Label(label="Rest the pointer in a corner of the screen to do one of these.", xalign=0, wrap=True)
        note.get_style_context().add_class("dim-label")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.pack_start(heading, False, False, 0)
        box.pack_start(note, False, False, 0)
        box.pack_start(group(*rows), False, False, 0)
        return box

    @staticmethod
    def save_prefs(**changes):
        prefs = style.prefs()
        prefs.update(changes)
        os.makedirs(os.path.dirname(style.PREFS), exist_ok=True)
        tmp = style.PREFS + ".dials-tmp"
        with open(tmp, "w") as f:
            json.dump(prefs, f, indent=2)
        os.replace(tmp, style.PREFS)

    # Displays -----------------------------------------------------------------
    def displays(self):
        from .dials_displays import displays_page
        level = screen.brightness()
        if level is not None:
            light = group(row("Brightness", slider(0.05, 1, 0.01, level, screen.set_brightness)))
        else:
            light = group(row("Brightness", None, "This display sets its own brightness, with its buttons."))
        return displays_page(self, light, self.night_light())

    def night_light(self):
        settings = screen.night_settings()

        def changed(key, value):
            if settings.get(key) != value:
                settings[key] = value
                screen.save_night_settings(settings)

        times = [f"{h:02d}:{m:02d}" for h in range(24) for m in (0, 30)]

        def time_box(key):
            combo = Gtk.ComboBoxText()
            for t in times:
                combo.append(t, t)
            if settings[key] not in times:
                combo.append(settings[key], settings[key])
            combo.set_active_id(settings[key])
            combo.connect("changed", lambda c: changed(key, c.get_active_id()))
            return combo

        warmth = slider(2700, 5500, 100, settings["warmth"], lambda v: changed("warmth", int(v)),
                        marks=((2700, "Warmer"), (5500, "Less warm")))
        hours = Gtk.Box(spacing=6)
        hours.pack_start(time_box("from"), False, False, 0)
        hours.pack_start(Gtk.Label(label="to"), False, False, 0)
        hours.pack_start(time_box("to"), False, False, 0)
        schedule = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        schedule.append("sun", "Sunset to Sunrise")
        schedule.append("custom", "Custom")
        where = sun.times_today(h24=style.prefs().get("clock") == "24")
        if where is None:
            schedule.set_sensitive(settings["schedule"] == "sun")
        schedule.set_active_id(settings["schedule"])
        from_row = row("From", hours, "It fades in and out over half an hour.")

        def scheduled(combo):
            changed("schedule", combo.get_active_id())
            from_row.set_sensitive(combo.get_active_id() == "custom")
        schedule.connect("changed", scheduled)
        from_row.set_sensitive(settings["schedule"] == "custom")
        return group(
            row("Night Light", switch(settings["on"], lambda on: changed("on", on)),
                "Warmer colours in the evening, which are easier on the eyes at night."),
            row("Schedule", schedule,
                f"Sunset is at {where[1]} and sunrise at {where[0]} today, for your time zone."
                if where else "Sunset to Sunrise needs a time zone in Date & Time."),
            from_row,
            row("Colour", warmth),
        )

    # Trackpad and mouse -------------------------------------------------------
    def pointing(self):
        def flag(key, default):
            return ini_get(WAYFIRE_INI, "input", key, default) == "true"

        def setter(key):
            return lambda on: ini_set(WAYFIRE_INI, "input", key, "true" if on else "false")

        def speed(key):
            value = float(ini_get(WAYFIRE_INI, "input", key, "0") or 0)
            return slider(-1, 1, 0.1, value, lambda v: ini_set(WAYFIRE_INI, "input", key, f"{v:.1f}"),
                          marks=((-1, "Slow"), (1, "Fast")))

        return page("Trackpad and Mouse", group(
            row("Tap to click", switch(flag("tap_to_click", "true"), setter("tap_to_click"))),
            row("Natural scrolling", switch(flag("natural_scroll", "true"), setter("natural_scroll")),
                "Content moves the way your fingers move."),
            row("Ignore trackpad while typing", switch(flag("disable_touchpad_while_typing", "false"),
                                                       setter("disable_touchpad_while_typing"))),
            row("Trackpad speed", speed("touchpad_cursor_speed")),
        ), group(
            row("Mouse speed", speed("mouse_cursor_speed")),
            row("Left-handed buttons", switch(flag("left_handed_mode", "false"), setter("left_handed_mode"))),
        ), group(
            row("Gestures", None, "Three fingers left or right: switch desktop. Four fingers up: all windows. "
                                  "Four fingers down: the app's windows (App Exposé)."),
        ))

    # Keyboard -----------------------------------------------------------------
    def keyboard(self):
        wf_get = lambda sec, key, default=None: ini_get(WAYFIRE_INI, sec, key, default)  # noqa: E731
        wf_set = lambda sec, key, value: ini_set(WAYFIRE_INI, sec, key, value)  # noqa: E731
        sources, input_menu = dials_input.input_sources_group(self, group, row, switch, wf_get, wf_set)
        repeat = dials_input.key_repeat_group(group, row, slider, wf_get, wf_set, switch)
        sources_heading = Gtk.Label(label="Input Sources", xalign=0)
        sources_heading.get_style_context().add_class("dials-section")
        text_heading = Gtk.Label(label="Text Input", xalign=0)
        text_heading.get_style_context().add_class("dials-section")
        self.shortcuts = dials_keys.Shortcuts(
            self, lambda sec, key, default=None: ini_get(WAYFIRE_INI, sec, key, default),
            lambda sec, key, value: ini_set(WAYFIRE_INI, sec, key, value), group, row)
        heading = Gtk.Label(label="Shortcuts", xalign=0)
        heading.get_style_context().add_class("dials-section")
        from . import clips

        def history(on):
            self.save_prefs(clipboard_history=on)
            if not on:
                clips.clear()

        clear = Gtk.Button(label="Clear History")
        clear.connect("clicked", lambda _b: clips.clear())
        options = (ini_get(WAYFIRE_INI, "input", "xkb_options", "") or "").split(",")

        def command_beside_space(on):
            kept = [o for o in (ini_get(WAYFIRE_INI, "input", "xkb_options", "") or "").split(",")
                    if o.strip() and o.strip() != "altwin:swap_alt_win"]
            ini_set(WAYFIRE_INI, "input", "xkb_options", ",".join(kept + (["altwin:swap_alt_win"] if on else [])))

        return page("Keyboard", repeat, group(
            row("\u2318 Command next to the space bar",
                switch("altwin:swap_alt_win" in [o.strip() for o in options], command_beside_space),
                "On: the key beside the space bar (Alt on most PC keyboards) is \u2318 Command and the one "
                "beyond it is \u2325 Option, as on a Mac. Off: the Windows key is \u2318 Command. "
                "Turn this off for a Mac keyboard."),
            row("Command key", switch(ini_get(WAYFIRE_INI, "strata-shell", "command_key", "true") != "false",
                                      lambda on: ini_set(WAYFIRE_INI, "strata-shell", "command_key",
                                                         "true" if on else "false")),
                "\u2318C, \u2318V, \u2318Z, \u2318S and the rest work in every app. Off: apps use Ctrl."),
        ), group(
            row("Clipboard history", switch(style.prefs().get("clipboard_history", True), history),
                "Keep the last 50 things you copy, on this computer only. \u21e7\u2318V shows them. "
                "Passwords marked as secret by a password manager are never kept."),
            row("Forget what was copied", clear),
        ), sources_heading, sources, input_menu, text_heading,
            dials_input.text_input_group(self, group, row, switch), heading, self.shortcuts.widget)

    # Network ------------------------------------------------------------------
    def network(self):
        return NetworkPanel(group, row, page)

    # About --------------------------------------------------------------------
    def about(self):
        release = {}
        try:
            with open("/etc/os-release") as f:
                for line in f:
                    if "=" in line:
                        key, value = line.rstrip().split("=", 1)
                        release[key] = value.strip('"')
        except OSError:
            pass
        cpu = platform.processor()
        try:
            with open("/proc/cpuinfo") as f:
                match = re.search(r"model name\s*:\s*(.+)", f.read())
                cpu = match.group(1) if match else cpu
        except OSError:
            pass
        memory = ""
        try:
            with open("/proc/meminfo") as f:
                kb = int(re.search(r"MemTotal:\s*(\d+)", f.read()).group(1))
                memory = f"{kb / 1024 / 1024:.1f} GB"
        except (OSError, AttributeError):
            pass
        disk = os.statvfs("/")
        free = disk.f_bavail * disk.f_frsize / 1e9
        total = disk.f_blocks * disk.f_frsize / 1e9
        mark = Gtk.Image()
        try:
            mark.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_size("/usr/share/freemac/freemac-mark.svg", 96, 96))
        except GLib.Error:
            pass
        name = Gtk.Label(label=release.get("PRETTY_NAME", "freemac"))
        name.get_style_context().add_class("dials-title")
        storage_info = Gtk.Box(spacing=10)
        storage_info.pack_start(Gtk.Label(label=f"{free:.1f} GB free of {total:.1f} GB"), False, False, 0)
        more = Gtk.Button(label="Storage Settings…")
        more.connect("clicked", lambda *_: self.show_panel("storage"))
        storage_info.pack_start(more, False, False, 0)
        return page("About", mark, name, group(
            row("Processor", Gtk.Label(label=cpu or "Unknown", ellipsize=3, max_width_chars=40)),
            row("Memory", Gtk.Label(label=memory or "Unknown")),
            row("Storage", storage_info),
            row("Kernel", Gtk.Label(label=platform.release())),
            row("Licence", Gtk.Label(label="GPL-3.0-or-later")),
        ))


# The View menu, grouped; the names match DialsWindow's panels.
MENU_PANELS = (
    (("appearance", "Appearance"), ("wallpaper", "Wallpaper"), ("screensaver", "Screen Saver"),
     ("dock", "Dock and Menu Bar"), ("seek", "Seek"),
     ("notifications", "Notifications"), ("focus", "Focus")),
    (("displays", "Displays"), ("pointing", "Trackpad and Mouse"), ("keyboard", "Keyboard"),
     ("sound", "Sound"), ("power", "Power"), ("bluetooth", "Bluetooth"), ("printers", "Printers")),
    (("network", "Network"), ("sharing", "Sharing"), ("accessibility", "Accessibility"), ("users", "Users"),
     ("loginitems", "Login Items"), ("softwareupdate", "Software Update"), ("about", "About")),
)


def menubar():
    return menus.menubar([
        ("_File", [[("Close Window", "win.close", "<Ctrl>w")]]),
        ("_View", [[(title, "win.show-" + name, None) for name, title in group] for group in MENU_PANELS]),
    ])


class Dials(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.freemac.Dials", flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.add_main_option("panel", 0, GLib.OptionFlags.NONE, GLib.OptionArg.STRING,
                             "Open a panel (appearance, wallpaper, dock, displays, ...)", "NAME")
        self.add_main_option("appearance", 0, GLib.OptionFlags.NONE, GLib.OptionArg.STRING,
                             "Switch to light or dark mode without opening a window", "light|dark")

    def do_startup(self):
        Gtk.Application.do_startup(self)
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": self.quit})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_menubar(menubar())

    def do_command_line(self, command_line):
        options = command_line.get_options_dict().end().unpack()
        if options.get("appearance") in ("light", "dark"):
            window = self.get_active_window()
            if window is not None:
                window.set_dark(options["appearance"] == "dark")
            else:
                apply_appearance(options["appearance"] == "dark")
            Gio.Settings.sync()
            return 0
        window = self.get_active_window() or DialsWindow(self)
        window.show_all()
        if options.get("panel"):
            window.show_panel(options["panel"])
        window.present()
        return 0


def main():
    GLib.set_prgname("freemac-dials")
    sys.exit(Dials().run(sys.argv))
