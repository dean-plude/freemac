# SPDX-License-Identifier: GPL-3.0-or-later
"""The Accessibility Keyboard, as on a Mac: a keyboard on the screen, for
typing with the mouse, a trackpad or a touch screen alone.

Turn it on in Dials > Accessibility (shell.json "accessibility_keyboard");
it floats above the windows, never takes the keyboard from the app being
typed in, and can be dragged by its top edge. Each key is sent through the
computer's own keyboard by Strata (strata/press-key, strata/shell/
screen-keyboard.hpp), so shortcuts and every app see an ordinary key.

Shift, Control, Option and Command stay down for the next key once
clicked, as with Sticky Keys; click one twice to lock it and once more to
let it go. The keys show what the keyboard layout in use types, with
capitals while Shift is down. Original freemac code.
"""
import json
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import style  # noqa: E402
from .wfipc import Connection  # noqa: E402

PREF = "accessibility_keyboard"
UNIT = 40   # one key's width and height
GAP = 4

# Each row: (evdev key code, width in keys). The layout of a usual PC keyboard.
ROWS = (
    ((1, 1.5), (59, 1), (60, 1), (61, 1), (62, 1), (63, 1), (64, 1), (65, 1), (66, 1), (67, 1), (68, 1),
     (87, 1), (88, 1)),
    ((41, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1), (9, 1), (10, 1), (11, 1), (12, 1),
     (13, 1), (14, 1.5)),
    ((15, 1.5), (16, 1), (17, 1), (18, 1), (19, 1), (20, 1), (21, 1), (22, 1), (23, 1), (24, 1), (25, 1),
     (26, 1), (27, 1), (43, 1)),
    ((58, 1.75), (30, 1), (31, 1), (32, 1), (33, 1), (34, 1), (35, 1), (36, 1), (37, 1), (38, 1), (39, 1),
     (40, 1), (28, 1.75)),
    ((42, 2.25), (44, 1), (45, 1), (46, 1), (47, 1), (48, 1), (49, 1), (50, 1), (51, 1), (52, 1), (53, 1),
     (54, 2.25)),
    ((29, 1.25), (125, 1.25), (56, 1.25), (57, 5.5), (100, 1.25), (105, 1), (103, 1), (108, 1), (106, 1)),
)

# Keys whose label isn't a character the layout types.
NAMES = {1: "esc", 14: "⌫", 15: "⇥", 58: "⇪", 28: "↩", 57: "",
         105: "←", 106: "→", 103: "↑", 108: "↓",
         59: "F1", 60: "F2", 61: "F3", 62: "F4", 63: "F5", 64: "F6", 65: "F7", 66: "F8", 67: "F9",
         68: "F10", 87: "F11", 88: "F12"}
# What a modifier key does, by the key's name in the layout (so Option and
# Command show where the layout puts them).
MODIFIERS = {"Shift_L": "⇧", "Shift_R": "⇧", "Control_L": "⌃", "Control_R": "⌃",
             "Alt_L": "⌥", "Alt_R": "⌥", "Meta_L": "⌥", "Meta_R": "⌥",
             "Super_L": "⌘", "Super_R": "⌘", "Hyper_L": "⌘", "Hyper_R": "⌘",
             "ISO_Level3_Shift": "⌥"}

CSS = b"""
window.keys-window, window.keys-window > * { background: transparent; }
window.keys-window .keys-panel {
    margin: 26px;
    padding: 4px 10px 10px 10px;
    border-radius: 14px;
    background-color: rgba(232, 232, 236, 0.97);
    border: 1px solid rgba(0, 0, 0, 0.16);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
}
window.keys-window .keys-panel.dark {
    background-color: rgba(44, 44, 48, 0.97);
    border-color: rgba(255, 255, 255, 0.12);
}
window.keys-window .keys-title { color: rgba(0, 0, 0, 0.55); font-size: 12px; font-weight: 600; }
window.keys-window .dark .keys-title { color: rgba(255, 255, 255, 0.6); }
window.keys-window button.keys-close {
    min-width: 14px; min-height: 14px; padding: 0; border-radius: 8px;
    background: #ec5f57; border: none; box-shadow: none;
}
window.keys-window button.key {
    padding: 0; border-radius: 7px; font-size: 15px;
    background: #ffffff; color: #1d1d1f;
    border: none; box-shadow: 0 1px 1px rgba(0, 0, 0, 0.28);
}
window.keys-window button.key:hover { background: #f3f3f5; }
window.keys-window button.key:active { background: #d8d8dc; }
window.keys-window button.key.small { font-size: 12px; }
window.keys-window .dark button.key { background: #5b5b60; color: #f5f5f7; box-shadow: 0 1px 1px rgba(0, 0, 0, 0.5); }
window.keys-window .dark button.key:hover { background: #69696f; }
window.keys-window .dark button.key:active { background: #4a4a4f; }
window.keys-window button.key.latched { background: alpha(@theme_selected_bg_color, 0.35); }
window.keys-window button.key.locked { background: @theme_selected_bg_color; color: white; }
"""


def save_pref(value):
    prefs = style.prefs()
    prefs[PREF] = value
    os.makedirs(os.path.dirname(style.PREFS), exist_ok=True)
    tmp = style.PREFS + ".topline-tmp"
    with open(tmp, "w") as f:
        json.dump(prefs, f, indent=2)
    os.replace(tmp, style.PREFS)


def wanted():
    return bool(style.prefs().get(PREF, False))


def _call(method, **data):
    try:
        connection = Connection()
    except (OSError, KeyError):
        return None
    try:
        return connection.call(method, **data)
    except (OSError, ValueError, ConnectionError):
        return None
    finally:
        connection.sock.close()


class ScreenKeyboard(Gtk.Window):
    def __init__(self):
        super().__init__(title="Accessibility Keyboard")
        style.make_transparent(self)
        self.get_style_context().add_class("keys-window")
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-accessibility-keyboard")
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.set_exclusive_zone(self, -1)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.LEFT):
            GtkLayerShell.set_anchor(self, edge, True)
        self.modifiers = {}   # key code -> 1 (for the next key) or 2 (locked)
        self.buttons = {}
        self.place = None     # (left, top) margins
        self.drag_from = None

        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=GAP)
        self.panel.get_style_context().add_class("keys-panel")
        self.panel.pack_start(self._title_bar(), False, False, 0)
        for row in ROWS:
            line = Gtk.Box(spacing=GAP)
            for code, width in row:
                button = Gtk.Button(can_focus=False)
                button.get_style_context().add_class("key")
                button.set_size_request(int(UNIT * width + GAP * (width - 1)), UNIT)
                button.connect("clicked", self._clicked, code)
                self.buttons[code] = button
                line.pack_start(button, False, False, 0)
            self.panel.pack_start(line, False, False, 0)
        self.panel.show_all()
        self.add(self.panel)
        self.keymap = Gdk.Keymap.get_for_display(Gdk.Display.get_default())
        self.keymap.connect("keys-changed", lambda *_: self._label())
        self._label()
        self._monitor = style.watch_prefs(self.follow)
        self._settings = style.interface_settings()
        if self._settings is not None:
            self._settings.connect("changed::color-scheme", lambda *_: self._theme())
        GLib.idle_add(self.follow)

    # -- the title bar: close, and drag to move ---------------------------------
    def _title_bar(self):
        bar = Gtk.EventBox()
        box = Gtk.Box(spacing=8)
        close = Gtk.Button(can_focus=False, valign=Gtk.Align.CENTER)
        close.get_style_context().add_class("keys-close")
        close.connect("clicked", lambda _b: save_pref(False))
        box.pack_start(close, False, False, 2)
        title = Gtk.Label(label="Accessibility Keyboard", hexpand=True)
        title.get_style_context().add_class("keys-title")
        box.pack_start(title, True, True, 0)
        spacer = Gtk.Box()
        spacer.set_size_request(18, 1)
        box.pack_start(spacer, False, False, 0)
        box.set_size_request(-1, 22)
        bar.add(box)
        bar.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                       | Gdk.EventMask.POINTER_MOTION_MASK)
        bar.connect("button-press-event", self._drag_start)
        bar.connect("motion-notify-event", self._drag_move)
        bar.connect("button-release-event", lambda *_: setattr(self, "drag_from", None))
        return bar

    # On Wayland a window doesn't know where it is on the screen, and the
    # pointer comes in the window's own coordinates: Strata says where the
    # pointer is on the screen (strata/pointer), and the window keeps the
    # same distance from it as when it was taken.
    @staticmethod
    def _pointer():
        reply = _call("strata/pointer")
        if not reply or "x" not in reply:
            return None
        return reply["x"], reply["y"]

    def _drag_start(self, _widget, event):
        at = self._pointer() if event.button == 1 and self.place else None
        self.drag_from = (at[0], at[1], *self.place) if at else None
        return False

    def _drag_move(self, _widget, _event):
        at = self._pointer() if self.drag_from else None
        if not at:
            return False
        x0, y0, left, top = self.drag_from
        area = self._area()
        width, height = self.get_allocated_width(), self.get_allocated_height()
        left = int(min(max(left + at[0] - x0, 0), max(area.width - width, 0)))
        top = int(min(max(top + at[1] - y0, 0), max(area.height - height, 0)))
        if (left, top) != self.place:
            self._move(left, top)
        return True

    def _area(self):
        display = Gdk.Display.get_default()
        monitor = display.get_primary_monitor() or display.get_monitor(0)
        return monitor.get_geometry()

    def _move(self, left, top):
        self.place = (left, top)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, left)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, top)

    def _theme(self):
        context = self.panel.get_style_context()
        (context.add_class if style.is_dark() else context.remove_class)("dark")

    # -- shown or not ----------------------------------------------------------
    def follow(self, *_args):
        on = wanted()
        if on and not self.get_visible():
            self._theme()
            if self.place is None:
                area = self._area()
                _min, natural = self.get_preferred_size()
                # Low in the middle, just above the Dock.
                self._move(max((area.width - natural.width) // 2, 0),
                           max(area.height - natural.height - 84, 30))
            self.show()
        elif not on and self.get_visible():
            self.hide()
            self.modifiers.clear()
            _call("strata/release-keys")
            self._label()
        return False

    # -- the keys ------------------------------------------------------------------
    def _keyval(self, code, shifted):
        state = Gdk.ModifierType.SHIFT_MASK if shifted else 0
        found = self.keymap.translate_keyboard_state(code + 8, state, 0)
        return found[1] if found and found[0] else 0

    def _modifier_name(self, code):
        name = Gdk.keyval_name(self._keyval(code, False)) or ""
        return MODIFIERS.get(name)

    def _shifted(self):
        return any(self._modifier_name(code) == "⇧" for code in self.modifiers)

    def _label(self):
        shifted = self._shifted()
        for code, button in self.buttons.items():
            context = button.get_style_context()
            symbol = self._modifier_name(code)
            if code in NAMES:
                text = NAMES[code]
            elif symbol:
                text = symbol
            else:
                char = Gdk.keyval_to_unicode(self._keyval(code, shifted))
                text = chr(char) if char >= 32 else ""
            button.set_label(text)
            (context.add_class if len(text) > 1 and code not in (1,) else context.remove_class)("small")
            state = self.modifiers.get(code, 0)
            (context.add_class if state == 1 else context.remove_class)("latched")
            (context.add_class if state == 2 else context.remove_class)("locked")

    def _clicked(self, _button, code):
        if self._modifier_name(code) and code != 58:
            state = self.modifiers.get(code, 0)
            if state == 0:
                self.modifiers[code] = 1
                _call("strata/press-key", key=code, action="press")
            elif state == 1:
                self.modifiers[code] = 2
            else:
                del self.modifiers[code]
                _call("strata/press-key", key=code, action="release")
        else:
            _call("strata/press-key", key=code, action="tap")
            for held, state in list(self.modifiers.items()):
                if state == 1:
                    del self.modifiers[held]
                    _call("strata/press-key", key=held, action="release")
        self._label()
