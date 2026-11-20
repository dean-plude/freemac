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

from . import alert, dials_keys, dials_more, dials_people, menus, pier, screen, style  # noqa: E402
from .network import NetworkPanel  # noqa: E402
from .wfipc import Connection  # noqa: E402

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


def apply_toolkits(dark):
    """GTK 4 (libadwaita) and Qt apps take light or dark from their own files.
    A gtk.css of the person's own (not our link) is left alone."""
    css = os.path.join(TOOLKITS, "gtk4", "dark.css" if dark else "light.css")
    if os.path.exists(css) and (os.path.islink(GTK4_CSS) or not os.path.exists(GTK4_CSS)):
        os.makedirs(os.path.dirname(GTK4_CSS), exist_ok=True)
        tmp = GTK4_CSS + ".new"
        if os.path.lexists(tmp):
            os.remove(tmp)
        os.symlink(css, tmp)
        os.replace(tmp, GTK4_CSS)
    scheme = os.path.join(TOOLKITS, "qt", "freemac-dark.conf" if dark else "freemac.conf")
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


def apply_appearance(dark, settings=None, follow_wallpaper=True):
    """Switch light/dark everywhere: GTK, title bars and (optionally) the wallpaper.

    Needs no window, so `freemac-dials --appearance` (used by Welcome) never
    opens Dials.
    """
    settings = settings if settings is not None else style.interface_settings()
    if settings:
        settings.set_string("color-scheme", "prefer-dark" if dark else "prefer-light")
        settings.set_string("gtk-theme", "freemac-dark" if dark else "freemac")
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
.dials-sidebar list row { padding: 4px 8px; border-radius: 6px; margin: 0 10px; min-height: 0; }
.dials-sidebar list row:hover { background-color: rgba(120, 120, 150, 0.12); }
.dials-sidebar list row:selected { background-color: #2f7bf5; color: #ffffff; }
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
.dials-choice { padding: 8px; border-radius: 12px; border: 2px solid transparent; background: none; box-shadow: none; }
.dials-choice:checked { border-color: #2f7bf5; }
.dials-chosen { border-color: #2f7bf5; }
.dials-section { font-weight: bold; margin-top: 12px; }
"""


# ---- small config helpers ---------------------------------------------------
def ini_get(path, section, key, default=None):
    """Read one value from a Wayfire-style ini file."""
    current = None
    try:
        with open(path) as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("[") and stripped.endswith("]"):
                    current = stripped[1:-1]
                elif current == section and "=" in stripped and not stripped.startswith("#"):
                    name, value = stripped.split("=", 1)
                    if name.strip() == key:
                        return value.strip().replace("\\#", "#")
    except OSError:
        pass
    return default


def ini_set(path, section, key, value):
    """Set one value in a Wayfire-style ini file, keeping comments and order.

    Wayfire and Backdrop watch their files and apply the change at once.
    """
    value = str(value).replace("#", "\\#")
    try:
        with open(path) as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    current, section_end, done = None, None, False
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if current == section:
                section_end = index
            current = stripped[1:-1]
            continue
        if current == section and "=" in stripped and not stripped.startswith("#"):
            if stripped.split("=", 1)[0].strip() == key:
                lines[index] = f"{key} = {value}"
                done = True
                break
    if not done:
        if current == section and section_end is None:
            section_end = len(lines)
        if section_end is None:
            if lines and lines[-1].strip():
                lines.append("")
            lines += [f"[{section}]", f"{key} = {value}"]
        else:
            # Insert after the section's last non-blank line.
            at = section_end
            while at > 0 and not lines[at - 1].strip():
                at -= 1
            lines.insert(at, f"{key} = {value}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Write the file in place rather than replacing it: Wayfire watches the
    # file itself for a finished write, and loses track of it when a new file
    # is renamed over it, so later changes would only apply after logging in
    # again.
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def pier_config():
    return pier.load_config()


def save_pier(**changes):
    config = pier_config()
    config.update(changes)
    os.makedirs(os.path.dirname(pier.CONFIG), exist_ok=True)
    with open(pier.CONFIG, "w") as f:
        json.dump(config, f, indent=2)


def wayfire_outputs():
    try:
        return Connection().call("window-rules/list-outputs")
    except (OSError, ValueError):
        return []


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
    return scale


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
        sidebar.connect("row-selected", lambda _l, r: r and self.stack.set_visible_child_name(r.name))
        side_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side_box.get_style_context().add_class("dials-sidebar")
        # Search at the top, as on a Mac: typing narrows the list to the
        # settings whose name or usual words match, and Return opens the first.
        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.get_style_context().add_class("dials-search")
        self.search.connect("search-changed", self._search_changed)
        self.search.connect("activate", self._search_open)
        side_box.pack_start(self.search, False, False, 0)
        side_box.pack_start(sidebar, True, True, 6)
        sidebar.set_filter_func(self._search_match)
        paned.pack1(side_box, False, False)
        paned.pack2(self.stack, True, False)
        paned.set_position(200)

        self.rows = {}
        # Grouped the way a Mac's settings sidebar is: connections, then
        # alerts and sound, then how things look, power, people, and the
        # devices you hold. Each icon sits white in a small coloured tile.
        # The group number puts a little space between groups.
        for group_no, name, title, icon, colour, build in (
            (0, "network", "Network", "network-wired-symbolic", "blue", self.network),
            (0, "bluetooth", "Bluetooth", "bluetooth-active-symbolic", "blue",
             lambda: dials_people.BluetoothPanel(self, page)),
            (1, "notifications", "Notifications", "preferences-system-notifications-symbolic", "red",
             lambda: dials_more.notifications(self)),
            (1, "sound", "Sound", "audio-volume-high-symbolic", "pink", lambda: dials_more.sound(self)),
            (2, "about", "About", "help-about-symbolic", "gray", self.about),
            (2, "appearance", "Appearance", "preferences-desktop-appearance-symbolic", "dark", self.appearance),
            (2, "accessibility", "Accessibility", "preferences-desktop-accessibility-symbolic", "blue",
             lambda: dials_more.accessibility(self)),
            (2, "dock", "Dock and Menu Bar", "view-app-grid-symbolic", "dark", self.dock),
            (2, "displays", "Displays", "video-display-symbolic", "blue", self.displays),
            (2, "wallpaper", "Wallpaper", "preferences-desktop-wallpaper-symbolic", "teal", self.wallpaper),
            (3, "power", "Power", "battery-good-symbolic", "green", lambda: dials_more.power(self)),
            (4, "users", "Users", "system-users-symbolic", "indigo", lambda: dials_people.UsersPanel(self, page)),
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
            item.add(line)
            sidebar.add(item)
            self.rows[name] = item
            self.stack.add_named(build(), name)

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
        sidebar.select_row(self.rows["appearance"])
        # The stack can't show a page before the window is shown, so it
        # opened on the first one; show the selected page once it can.
        self.connect("map", lambda *_: GLib.idle_add(self._show_selected))
        actions = {"close": self.close}
        for name in self.rows:
            actions["show-" + name] = lambda n=name: self.show_panel(n)
        menus.add_actions(self, actions)
        self.connect("key-press-event", self._on_key)

    def _show_selected(self):
        row = self.sidebar.get_selected_row()
        if row is not None:
            self.stack.set_visible_child_name(row.name)
        return False

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
        if action != "suspend":
            words = {"reboot": ("Restart now?", "Restart"), "poweroff": ("Shut down now?", "Shut Down")}[action]
            answer = alert.ask(self, words[0], "Unsaved work in open apps will be lost.",
                               [("Cancel", Gtk.ResponseType.CANCEL), (words[1], Gtk.ResponseType.OK)],
                               default=Gtk.ResponseType.OK)
            if answer != Gtk.ResponseType.OK:
                return
        Gio.Subprocess.new(["systemctl", action], Gio.SubprocessFlags.NONE)

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
        dark = style.is_dark()
        choices = Gtk.Box(spacing=16)
        light_button = None
        self.mode_buttons = {}
        for label, is_dark, wall in (("Light", False, LIGHT_WALL), ("Dark", True, DARK_WALL)):
            button = Gtk.RadioButton.new_from_widget(light_button)
            light_button = light_button or button
            button.set_mode(False)
            button.get_style_context().add_class("dials-choice")
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            pixbuf = thumbnail(wall, 160, 96)
            if pixbuf:
                inner.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), False, False, 0)
            inner.pack_start(Gtk.Label(label=label), False, False, 0)
            button.add(inner)
            button.set_active(is_dark == dark)
            button.handler = button.connect("toggled", lambda b, d=is_dark: b.get_active() and self.set_dark(d))
            self.mode_buttons[is_dark] = button
            choices.pack_start(button, False, False, 0)
        if self.settings:
            # Show the change when the mode is switched from elsewhere.
            self.settings.connect("changed::color-scheme", lambda *_: self._show_mode())
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
        return page("Appearance", choices, group(
            row("Switch wallpaper with the mode", self.follow_wallpaper,
                "freemac's own wallpapers have a day and a night version."),
            row("Text size", text_size),
        ), group(
            row("Tile windows at the screen edges", snap,
                "Drag a window to the left or right edge to fill half the screen, to a corner for a "
                "quarter, or to the top to fill it."),
        ))

    def _show_mode(self):
        button = self.mode_buttons[style.is_dark()]
        with button.handler_block(button.handler):
            button.set_active(True)

    def set_dark(self, dark):
        apply_appearance(dark, self.settings, self.follow_wallpaper.get_active())
        self.refresh_wallpapers()

    # Wallpaper ----------------------------------------------------------------
    def wallpaper(self):
        self.wall_flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4,
                                     column_spacing=12, row_spacing=12, homogeneous=True)
        self.refresh_wallpapers()
        note = Gtk.Label(label="Each freemac wallpaper has a day and a night version, "
                               "and follows light and dark mode.", xalign=0, wrap=True)
        note.get_style_context().add_class("dials-caption")
        choose = Gtk.Button(label="Choose a Picture…", halign=Gtk.Align.START)
        choose.connect("clicked", self.choose_wallpaper)
        fit = Gtk.ComboBoxText()
        fit.append("fill", "Fill screen")
        fit.append("fit", "Fit to screen")
        fit.append("stretch", "Stretch")
        fit.set_active_id(ini_get(SHELL_INI, "background", "fit", "fill"))
        fit.connect("changed", lambda c: ini_set(SHELL_INI, "background", "fit", c.get_active_id()))
        return page("Wallpaper", self.wall_flow, note, choose, group(row("Picture fit", fit)))

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

        downloads = pier.default_stacks()[0]

        def show_downloads(on):
            stacks = [f for f in pier_config()["stacks"] if f != downloads]
            save_pier(stacks=([downloads] if on else []) + stacks)

        clock = Gtk.ComboBoxText()
        for fmt, name in (("12", "12-hour (2:30 PM)"), ("24", "24-hour (14:30)")):
            clock.append(fmt, name)
        clock.set_active_id(style.prefs().get("clock", "12"))
        clock.connect("changed", lambda c: self.save_prefs(clock=c.get_active_id()))
        return page("Dock and Menu Bar", group(
            row("Icon size", size),
            row("Magnification", switch(config["magnify"], magnify), "Icons grow as the pointer passes over them."),
            row("Magnified size", peak),
        ), group(
            row("Downloads", switch(downloads in config["stacks"], show_downloads),
                "A folder on the dock that shows your newest downloads."),
            row("Trash", switch(config["trash"], lambda on: save_pier(trash=on)),
                "Drop files on it to throw them away; right-click it to empty it."),
        ), group(row("Double-click a window's title bar to", self.title_double_click()),
                 row("Minimize windows into application icon",
                     switch(config.get("minimize_into_app", False), lambda on: save_pier(minimize_into_app=on)),
                     "Off: a minimized window gets its own picture at the right end of the dock.")),
            group(row("Clock", clock)), self.hot_corners())

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
        outputs = wayfire_outputs()
        rows = []
        for output in outputs:
            name = output.get("name", "?")
            geo = output.get("geometry", {})
            scale = Gtk.ComboBoxText()
            for value in ("1", "1.25", "1.5", "1.75", "2"):
                scale.append(value, f"{int(float(value) * 100)}%")
            scale.set_active_id(ini_get(WAYFIRE_INI, f"output:{name}", "scale", "1"))
            scale.connect("changed", lambda c, n=name: ini_set(WAYFIRE_INI, f"output:{n}", "scale", c.get_active_id()))
            caption = f"{geo.get('width', '?')} × {geo.get('height', '?')}" if geo else None
            rows.append(row(f"{name} scale", scale, caption))
        if not rows:
            rows.append(row("No displays found", None, "Dials reads displays from the window manager."))
        level = screen.brightness()
        if level is not None:
            rows.insert(0, row("Brightness", slider(0.05, 1, 0.01, level, screen.set_brightness)))
        else:
            rows.append(row("Brightness", None, "This display sets its own brightness, with its buttons."))
        return page("Displays", group(*rows), self.night_light())

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
        return group(
            row("Night Light", switch(settings["on"], lambda on: changed("on", on)),
                "Warmer colours in the evening, which are easier on the eyes at night."),
            row("From", hours, "It fades in and out over half an hour."),
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
                                  "Four fingers down: all desktops."),
        ))

    # Keyboard -----------------------------------------------------------------
    def keyboard(self):
        layout = Gtk.Entry(text=ini_get(WAYFIRE_INI, "input", "xkb_layout", "us") or "us", width_chars=10)
        layout.connect("activate", lambda e: ini_set(WAYFIRE_INI, "input", "xkb_layout", e.get_text().strip() or "us"))
        layout.connect("focus-out-event", lambda e, _ev: ini_set(
            WAYFIRE_INI, "input", "xkb_layout", e.get_text().strip() or "us") or False)
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

        return page("Keyboard", group(
            row("Layout", layout, "An XKB layout code such as us, gb, de or fr. Press Enter to apply."),
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
        ), heading, self.shortcuts.widget)

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
        return page("About", mark, name, group(
            row("Processor", Gtk.Label(label=cpu or "Unknown", ellipsize=3, max_width_chars=40)),
            row("Memory", Gtk.Label(label=memory or "Unknown")),
            row("Storage", Gtk.Label(label=f"{free:.1f} GB free of {total:.1f} GB")),
            row("Kernel", Gtk.Label(label=platform.release())),
            row("Licence", Gtk.Label(label="GPL-3.0-or-later")),
        ))


# The View menu, grouped; the names match DialsWindow's panels.
MENU_PANELS = (
    (("appearance", "Appearance"), ("wallpaper", "Wallpaper"), ("dock", "Dock and Menu Bar"),
     ("notifications", "Notifications")),
    (("displays", "Displays"), ("pointing", "Trackpad and Mouse"), ("keyboard", "Keyboard"),
     ("sound", "Sound"), ("power", "Power"), ("bluetooth", "Bluetooth"), ("printers", "Printers")),
    (("network", "Network"), ("accessibility", "Accessibility"), ("users", "Users"), ("about", "About")),
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
