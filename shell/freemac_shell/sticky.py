# SPDX-License-Identifier: GPL-3.0-or-later
"""Sticky Keys on screen, as on a Mac: while a modifier key is set, its
symbol shows in the top-right corner of the screen (⌃ ⌥ ⇧ ⌘), dimmer while it
waits for the next key and on a filled tile once it's locked, and a soft
click sounds as each one is set.

Strata does the keys themselves (strata/shell/sticky-keys.hpp) and tells
Topline over its socket: "sticky state SHIFT CONTROL OPTION COMMAND", each
0, 1 (for the next key) or 2 (locked), and "sticky turned on" or "off" when
Shift was pressed five times. Topline then saves the choice in wayfire.ini,
as Dials > Accessibility would, and says so on screen.

The click and the symbols can each be turned off in Dials > Accessibility
(shell.json "sticky_beep" and "sticky_show"). Original freemac code.
"""
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GLib, Gdk, Gtk, GtkLayerShell  # noqa: E402

from . import sounds, style  # noqa: E402
from .ini import ini_set  # noqa: E402

# The order a Mac shows them in, by Strata's order (shift, control, option, command).
SYMBOLS = (("⌃", 1), ("⌥", 2), ("⇧", 0), ("⌘", 3))
WAYFIRE_INI = os.path.join(os.path.expanduser("~/.config"), "wayfire.ini")
NOTICE_MS = 1800

CSS = b"""
window.sticky-window, window.sticky-window > * { background: transparent; }
window.sticky-window .sticky-panel {
    margin: 6px 14px 16px 14px;
    padding: 6px 10px;
    border-radius: 12px;
    background-color: rgba(30, 30, 34, 0.72);
    box-shadow: 0 3px 10px rgba(0, 0, 0, 0.25);
}
.sticky-key { color: rgba(255, 255, 255, 0.55); font-size: 26px; min-width: 34px;
              padding: 0 4px; border-radius: 7px; }
.sticky-key.set { color: white; }
.sticky-key.locked { color: white; background-color: rgba(255, 255, 255, 0.22); }
.sticky-notice { color: white; font-size: 15px; font-weight: 600; padding: 4px 6px; }
"""


def parse(line):
    """("state", [shift, control, option, command]) or ("turned", on);
    None for anything else."""
    words = line.split()
    if len(words) == 6 and words[:2] == ["sticky", "state"]:
        try:
            values = [int(word) for word in words[2:]]
        except ValueError:
            return None
        if all(value in (0, 1, 2) for value in values):
            return ("state", values)
        return None
    if len(words) == 3 and words[:2] == ["sticky", "turned"] and words[2] in ("on", "off"):
        return ("turned", words[2] == "on")
    return None


def newly_set(before, after):
    """Whether any modifier was set, or locked, by this change."""
    return any(new > old for old, new in zip(before, after))


def save_enabled(on):
    """Sticky Keys on or off in wayfire.ini, as Dials writes it."""
    ini_set(WAYFIRE_INI, "strata-shell", "sticky_keys", "true" if on else "false")


class StickyPanel(Gtk.Window):
    def __init__(self):
        super().__init__(title="Sticky Keys")
        style.make_transparent(self)
        self.get_style_context().add_class("sticky-window")
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-sticky-keys")
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.set_exclusive_zone(self, -1)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 30)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 6)
        self.connect("realize", self._pass_clicks)
        self.state = [0, 0, 0, 0]
        self.notice_timer = 0

    def _pass_clicks(self, _widget):
        # Clicks go through to whatever is under it.
        import cairo
        self.get_window().input_shape_combine_region(cairo.Region(), 0, 0)

    def handle(self, line):
        message = parse(line)
        if message is None:
            return
        prefs = style.prefs()
        if message[0] == "state":
            before, self.state = self.state, message[1]
            if prefs.get("sticky_beep", True) and newly_set(before, self.state):
                sounds.play(sounds.path_of("pop"), 45, gap=0.03)
            if not self.notice_timer:
                self._show_state(prefs.get("sticky_show", True))
        else:
            on = message[1]
            try:
                save_enabled(on)
            except OSError:
                pass
            self.state = [0, 0, 0, 0]
            sounds.play(sounds.path_of("pop"), 70, gap=0.03)
            self._show_notice("Sticky Keys On" if on else "Sticky Keys Off")

    def _panel(self, *children):
        child = self.get_child()
        if child:
            self.remove(child)
        panel = Gtk.Box(spacing=2)
        panel.get_style_context().add_class("sticky-panel")
        for widget in children:
            panel.pack_start(widget, False, False, 0)
        self.add(panel)
        self.show_all()

    def _show_state(self, show=True):
        if not show or not any(self.state):
            self.hide()
            return
        keys = []
        for symbol, index in SYMBOLS:
            value = self.state[index]
            if not value:
                continue
            label = Gtk.Label(label=symbol)
            context = label.get_style_context()
            context.add_class("sticky-key")
            context.add_class("locked" if value == 2 else "set")
            keys.append(label)
        self._panel(*keys)

    def _show_notice(self, text):
        label = Gtk.Label(label=text)
        label.get_style_context().add_class("sticky-notice")
        self._panel(label)
        if self.notice_timer:
            GLib.source_remove(self.notice_timer)
        self.notice_timer = GLib.timeout_add(NOTICE_MS, self._notice_over)

    def _notice_over(self):
        self.notice_timer = 0
        self._show_state(style.prefs().get("sticky_show", True))
        return False
