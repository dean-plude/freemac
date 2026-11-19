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

from . import dials_more, dials_people, menus, pier, style  # noqa: E402
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


def scene_version(path, dark):
    """The day or night version of a built-in scene, or None for other pictures."""
    name = os.path.basename(path or "")
    if path and os.path.dirname(path) != WALLPAPERS:
        return None
    for _title, day, night in SCENES:
        if name in (day, night) or not path:
            return os.path.join(WALLPAPERS, night if dark else day)
    return None
CSS = b"""
.dials-sidebar { background-color: rgba(120, 120, 150, 0.08); }
.dials-sidebar row { padding: 7px 12px; border-radius: 8px; margin: 1px 8px; }
.dials-page { padding: 24px 32px; }
.dials-title { font-size: 22px; font-weight: 800; margin-bottom: 8px; }
.dials-group { border-radius: 12px; background-color: rgba(120, 120, 150, 0.08); padding: 4px 0; }
.dials-group row { padding: 10px 16px; }
.dials-caption { opacity: 0.65; font-size: 12px; }
.dials-choice { padding: 8px; border-radius: 12px; border: 2px solid transparent; background: none; box-shadow: none; }
.dials-choice:checked { border-color: #4b5fc4; }
.dials-chosen { border-color: #4b5fc4; }
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
        side_box.pack_start(sidebar, True, True, 6)
        paned.pack1(side_box, False, False)
        paned.pack2(self.stack, True, False)
        paned.set_position(200)

        self.rows = {}
        for name, title, icon, build in (
            ("appearance", "Appearance", "preferences-desktop-appearance-symbolic", self.appearance),
            ("wallpaper", "Wallpaper", "preferences-desktop-wallpaper-symbolic", self.wallpaper),
            ("dock", "Dock and Menu Bar", "view-app-grid-symbolic", self.dock),
            ("displays", "Displays", "video-display-symbolic", self.displays),
            ("pointing", "Trackpad and Mouse", "input-touchpad-symbolic", self.pointing),
            ("keyboard", "Keyboard", "input-keyboard-symbolic", self.keyboard),
            ("network", "Network", "network-wired-symbolic", self.network),
            ("sound", "Sound", "audio-volume-high-symbolic", lambda: dials_more.sound(self)),
            ("power", "Power", "battery-good-symbolic", lambda: dials_more.power(self)),
            ("notifications", "Notifications", "preferences-system-notifications-symbolic",
             lambda: dials_more.notifications(self)),
            ("accessibility", "Accessibility", "preferences-desktop-accessibility-symbolic",
             lambda: dials_more.accessibility(self)),
            ("bluetooth", "Bluetooth", "bluetooth-active-symbolic",
             lambda: dials_people.BluetoothPanel(self, page)),
            ("printers", "Printers", "printer-symbolic", lambda: dials_people.PrintersPanel(self, page)),
            ("users", "Users", "system-users-symbolic", lambda: dials_people.UsersPanel(self, page)),
            ("about", "About", "help-about-symbolic", self.about),
        ):
            item = Gtk.ListBoxRow()
            item.name = name
            line = Gtk.Box(spacing=10)
            line.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
            line.pack_start(Gtk.Label(label=title, xalign=0), True, True, 0)
            item.add(line)
            sidebar.add(item)
            self.rows[name] = item
            self.stack.add_named(build(), name)
        self.sidebar = sidebar
        sidebar.select_row(self.rows["appearance"])
        actions = {"close": self.close}
        for name in self.rows:
            actions["show-" + name] = lambda n=name: self.show_panel(n)
        menus.add_actions(self, actions)
        self.connect("key-press-event", self._on_key)

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
            dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                                       text=words[0], secondary_text="Unsaved work in open apps will be lost.")
            dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, words[1], Gtk.ResponseType.OK)
            answer = dialog.run()
            dialog.destroy()
            if answer != Gtk.ResponseType.OK:
                return
        Gio.Subprocess.new(["systemctl", action], Gio.SubprocessFlags.NONE)

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
        if self.settings:
            self.settings.set_string("color-scheme", "prefer-dark" if dark else "prefer-light")
            self.settings.set_string("gtk-theme", "Adwaita-dark" if dark else "Adwaita")
        Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", dark)
        # Title bars the window manager draws follow the mode too.
        ini_set(WAYFIRE_INI, "decoration", "active_color", "#2A2C48FF" if dark else "#E9E7EFFF")
        ini_set(WAYFIRE_INI, "decoration", "inactive_color", "#22243AFF" if dark else "#F4F3F7FF")
        current = ini_get(SHELL_INI, "background", "image")
        other = scene_version(current, dark)
        if self.follow_wallpaper.get_active() and other and other != current:
            self.set_wallpaper(other)
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

        clock = Gtk.ComboBoxText()
        for fmt, name in (("12", "12-hour (2:30 PM)"), ("24", "24-hour (14:30)")):
            clock.append(fmt, name)
        clock.set_active_id(style.prefs().get("clock", "12"))
        clock.connect("changed", lambda c: self.save_prefs(clock=c.get_active_id()))
        return page("Dock and Menu Bar", group(
            row("Icon size", size),
            row("Magnification", switch(config["magnify"], magnify), "Icons grow as the pointer passes over them."),
            row("Magnified size", peak),
        ), group(row("Clock", clock)))

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
        return page("Displays", group(*rows))

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
        shortcuts = [
            ("Super+Space", "Seek"), ("Ctrl+Up or Super+Tab", "All windows"), ("Ctrl+Down", "All desktops"),
            ("Ctrl+Left / Right", "Switch desktop"), ("Alt+Tab", "Switch windows"), ("Super+Enter", "Terminal"),
            ("Super+Q", "Close window"), ("Super+M", "Minimize"), ("Super+D", "Show desktop"),
        ]
        return page("Keyboard", group(
            row("Layout", layout, "An XKB layout code such as us, gb, de or fr. Press Enter to apply."),
        ), group(*[row(action, Gtk.Label(label=keys)) for keys, action in shortcuts]))

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
            window = self.get_active_window() or DialsWindow(self)
            window.set_dark(options["appearance"] == "dark")
            Gio.Settings.sync()
            if not window.get_visible():
                window.destroy()
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
