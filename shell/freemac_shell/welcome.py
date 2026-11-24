# SPDX-License-Identifier: GPL-3.0-or-later
"""Welcome: the first thing a new account sees.

A few short steps before getting to work: light or dark, a wallpaper,
Wi-Fi (only when the computer has it), and a last page with the account,
the shortcuts worth knowing and, on the live system, the installer. Every
choice can be changed later in Dials.

At login it runs once per account (it remembers in
~/.config/freemac/welcome-seen); on the live system it runs every time.
"--always" (the menu entry) shows it whatever.
"""
import os
import pwd
import shutil
import subprocess
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import guest_user, style  # noqa: E402

LIVE = os.path.isdir("/run/live/medium")
SEEN = os.path.join(GLib.get_user_config_dir(), "freemac", "welcome-seen")
MARK = "/usr/share/freemac/freemac-mark.svg"
# \u2318 Command is the key next to the space bar (Dials > Keyboard can make
# it the Windows key instead).
SHORTCUTS = [
    ("\u2318 Command", "The key next to the space bar: \u2318C copies, \u2318V pastes"),
    ("\u2318Space", "Search apps, files and what's in them"),
    ("\u2318Tab", "Switch apps"),
    ("\u2318Q / \u2318H", "Quit or hide the app"),
    ("\u2303\u2191 or 4-finger swipe up", "Show all windows"),
    ("\u21e7\u23183 / \u21e7\u23184", "Screenshot of the screen / an area"),
    ("\u2303\u2318Q", "Lock the screen"),
]
CSS = b"""
.welcome-title { font-size: 26px; font-weight: 800; }
.welcome-text { font-size: 14px; opacity: 0.8; }
.welcome-choice { padding: 8px; border-radius: 14px; border: 3px solid transparent; background: none; box-shadow: none; }
.welcome-choice:checked { border-color: @theme_selected_bg_color; }
.welcome-dot { font-size: 10px; opacity: 0.3; }
.welcome-dot.current { opacity: 1; color: @theme_selected_bg_color; }
"""


def has_wifi():
    try:
        gi.require_version("NM", "1.0")
        from gi.repository import NM
        client = NM.Client.new(None)
    except (ValueError, ImportError, GLib.Error):
        return False
    return any(d.get_device_type() == NM.DeviceType.WIFI for d in client.get_devices())


def heading(title, text):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    label = Gtk.Label(label=title)
    label.get_style_context().add_class("welcome-title")
    box.pack_start(label, False, False, 0)
    if text:
        line = Gtk.Label(label=text, wrap=True, justify=Gtk.Justification.CENTER, max_width_chars=60)
        line.get_style_context().add_class("welcome-text")
        box.pack_start(line, False, False, 0)
    return box


class Welcome(Gtk.Window):
    def __init__(self):
        super().__init__(title="Welcome to freemac")
        self.set_default_size(760, 560)
        self.set_position(Gtk.WindowPosition.CENTER)
        header = Gtk.HeaderBar(show_close_button=True, title="Welcome to freemac")
        self.set_titlebar(header)
        self.back = Gtk.Button(label="Back")
        self.back.connect("clicked", lambda *_: self.go(-1))
        header.pack_start(self.back)
        self.next = Gtk.Button(label="Continue")
        self.next.get_style_context().add_class("suggested-action")
        self.next.connect("clicked", lambda *_: self.go(1))
        header.pack_end(self.next)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=24)
        self.add(outer)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
                               transition_duration=220)
        outer.pack_start(self.stack, True, True, 0)
        self.pages = [("hello", self.hello()), ("look", self.look()), ("wallpaper", self.wallpaper())]
        if has_wifi():
            self.pages.append(("wifi", self.wifi()))
        self.pages.append(("ready", self.ready()))
        for name, widget in self.pages:
            self.stack.add_named(widget, name)
        self.dots = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER, margin_top=12)
        for _ in self.pages:
            dot = Gtk.Label(label="●")
            dot.get_style_context().add_class("welcome-dot")
            self.dots.pack_start(dot, False, False, 0)
        outer.pack_start(self.dots, False, False, 0)
        self.index = 0
        self.connect("key-press-event", self._key)
        self.show_page()

    # -- moving between pages --------------------------------------------------
    def go(self, by):
        if self.index + by >= len(self.pages):
            self.close()
            return
        self.index = max(0, self.index + by)
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT if by > 0
                                       else Gtk.StackTransitionType.SLIDE_RIGHT)
        self.show_page()

    def show_page(self):
        self.stack.set_visible_child_name(self.pages[self.index][0])
        self.back.set_visible(self.index > 0)
        last = self.index == len(self.pages) - 1
        self.next.set_label("Start Using freemac" if last else ("Get Started" if self.index == 0 else "Continue"))
        for number, dot in enumerate(self.dots.get_children()):
            context = dot.get_style_context()
            (context.add_class if number == self.index else context.remove_class)("current")

    def _key(self, _w, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    # -- the pages ---------------------------------------------------------------
    def hello(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, valign=Gtk.Align.CENTER)
        if os.path.exists(MARK):
            box.pack_start(Gtk.Image.new_from_file(MARK), False, False, 0)
        text = ("You're trying freemac from the live system. Nothing is saved until you install it."
                if LIVE else "A free desktop for your PC. A few quick choices and you're ready.")
        box.pack_start(heading("Welcome to freemac", text), False, False, 0)
        return box

    def look(self):
        from . import dials
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24, valign=Gtk.Align.CENTER)
        box.pack_start(heading("Light or dark?", "You can switch any time in Dials or quick settings."),
                       False, False, 0)
        choices = Gtk.Box(spacing=24, halign=Gtk.Align.CENTER)
        first = None
        dark_now = style.is_dark()
        for label, dark, wall in (("Light", False, dials.LIGHT_WALL), ("Dark", True, dials.DARK_WALL)):
            button = Gtk.RadioButton.new_from_widget(first)
            first = first or button
            button.set_mode(False)
            button.get_style_context().add_class("welcome-choice")
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            picture = dials.thumbnail(wall, 240, 150)
            if picture:
                inner.pack_start(Gtk.Image.new_from_pixbuf(picture), False, False, 0)
            inner.pack_start(Gtk.Label(label=label), False, False, 0)
            button.add(inner)
            button.set_active(dark == dark_now)
            button.connect("toggled", lambda b, d=dark: b.get_active() and self.set_dark(d))
            choices.pack_start(button, False, False, 0)
        box.pack_start(choices, False, False, 0)
        return box

    def set_dark(self, dark):
        subprocess.Popen(["freemac-dials", "--appearance", "dark" if dark else "light"],
                         start_new_session=True)
        GLib.timeout_add(900, lambda: self.fill_wallpapers() or False)

    def wallpaper(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20, valign=Gtk.Align.CENTER)
        box.pack_start(heading("Pick a wallpaper", "Each one has a day and a night version, "
                               "and follows light and dark."), False, False, 0)
        self.walls = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4,
                                 min_children_per_line=2, column_spacing=12, row_spacing=12,
                                 homogeneous=True, halign=Gtk.Align.CENTER)
        box.pack_start(self.walls, False, False, 0)
        self.fill_wallpapers()
        return box

    def fill_wallpapers(self):
        from . import dials
        for child in self.walls.get_children():
            self.walls.remove(child)
        dark = style.is_dark()
        current = dials.ini_get(dials.SHELL_INI, "background", "image") or dials.LIGHT_WALL
        first = None
        for title, day, night in dials.SCENES:
            path = os.path.join(dials.WALLPAPERS, night if dark else day)
            picture = dials.thumbnail(path, 150, 94)
            if not picture:
                continue
            button = Gtk.RadioButton.new_from_widget(first)
            first = first or button
            button.set_mode(False)
            button.get_style_context().add_class("welcome-choice")
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            inner.pack_start(Gtk.Image.new_from_pixbuf(picture), False, False, 0)
            inner.pack_start(Gtk.Label(label=title), False, False, 0)
            button.add(inner)
            button.set_active(os.path.basename(current) in (day, night))
            button.connect("toggled", lambda b, p=path: b.get_active() and dials.ini_set(
                dials.SHELL_INI, "background", "image", p))
            self.walls.add(button)
        self.walls.show_all()

    def wifi(self):
        from . import dials, network
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.pack_start(heading("Get online", "Choose a Wi-Fi network, or skip this and connect later "
                               "from the menu bar."), False, False, 0)

        def page(_title, *children):
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            for child in children:
                inner.pack_start(child, False, False, 0)
            return inner
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(network.NetworkPanel(dials.group, dials.row, page))
        box.pack_start(scroll, True, True, 0)
        return box

    def ready(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, valign=Gtk.Align.CENTER)
        me = pwd.getpwuid(os.getuid())
        name = me.pw_gecos.split(",")[0] or me.pw_name
        if LIVE:
            text = "Install freemac to keep your files and settings. It takes a few minutes."
        else:
            text = f"You're signed in as {name} ({me.pw_name}). Add people or change your password in Dials > Users."
        box.pack_start(heading("You're all set", text), False, False, 0)
        grid = Gtk.Grid(column_spacing=24, row_spacing=8, halign=Gtk.Align.CENTER)
        for row, (keys, action) in enumerate(SHORTCUTS):
            key = Gtk.Label(xalign=1)
            key.set_markup(f"<b>{GLib.markup_escape_text(keys)}</b>")
            grid.attach(key, 0, row, 1, 1)
            grid.attach(Gtk.Label(label=action, xalign=0), 1, row, 1, 1)
        box.pack_start(grid, False, False, 0)
        buttons = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER)
        people = Gtk.Button(label="Open Dials")
        people.connect("clicked", lambda *_: subprocess.Popen(
            ["freemac-dials"] + ([] if LIVE else ["--panel", "users"]), start_new_session=True))
        buttons.pack_start(people, False, False, 0)
        guide = Gtk.Button(label="Open the Guide")
        guide.set_tooltip_text("Short how-tos: windows, files, screenshots, Wi-Fi and more")
        guide.connect("clicked", lambda *_: subprocess.Popen(["freemac-guide"], start_new_session=True))
        buttons.pack_start(guide, False, False, 0)
        if not LIVE and shutil.which("freemac-tender"):
            bring = Gtk.Button(label="Bring Files Over…")
            bring.set_tooltip_text("Copy your files from a Lifeboat backup, a Windows PC or another computer")
            bring.connect("clicked", lambda *_: subprocess.Popen(["freemac-tender"], start_new_session=True))
            buttons.pack_start(bring, False, False, 0)
        if LIVE and shutil.which("freemac-keel"):
            install = Gtk.Button(label="Install freemac…")
            install.get_style_context().add_class("suggested-action")
            install.connect("clicked", lambda *_: subprocess.Popen(["freemac-keel"], start_new_session=True))
            buttons.pack_start(install, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        return box


def finished(*_args):
    if not LIVE:
        os.makedirs(os.path.dirname(SEEN), exist_ok=True)
        open(SEEN, "w").close()
    Gtk.main_quit()


def main():
    GLib.set_prgname("freemac-welcome")
    if guest_user.is_guest(pwd.getpwuid(os.getuid()).pw_name) and "--always" not in sys.argv:
        return 0   # a guest's things are erased anyway; no tour each time
    if not LIVE and os.path.exists(SEEN) and "--always" not in sys.argv:
        return 0   # an installed system shows Welcome once per account
    style.apply()
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    window = Welcome()
    window.connect("destroy", finished)
    window.show_all()
    window.show_page()
    Gtk.main()
    return 0
