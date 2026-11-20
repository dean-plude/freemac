# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Keyboard: the desktop's shortcuts, and changing them.

Each shortcut is a Wayfire option in ~/.config/wayfire.ini, written as
"<super> KEY_SPACE" and so on, with alternatives separated by "|" (a
touchpad swipe can be one). Changing a shortcut replaces its first key
combination and keeps the others; Wayfire applies the change at once.
"""
import ctypes

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

# (section, option, what it does, Wayfire value as freemac ships it)
SHORTCUTS = (
    ("command", "binding_seek", "Seek", "<super> KEY_SPACE"),
    ("command", "binding_clips", "Clipboard history", "<super> <shift> KEY_V"),
    ("fast-switcher", "activate", "Switch windows", "<alt> KEY_TAB"),
    ("scale", "toggle", "All windows", "<ctrl> KEY_UP | swipe up 4"),
    ("scale", "toggle_all", "All windows on every desktop", "<super> KEY_TAB"),
    ("expo", "toggle", "All desktops", "<ctrl> KEY_DOWN | swipe down 4"),
    ("vswitch", "binding_left", "Desktop to the left", "<ctrl> KEY_LEFT"),
    ("vswitch", "binding_right", "Desktop to the right", "<ctrl> KEY_RIGHT"),
    ("wm-actions", "toggle_showdesktop", "Show the desktop", "<super> KEY_D"),
    ("core", "close_top_view", "Close window", "<super> KEY_Q | <alt> KEY_F4"),
    ("wm-actions", "minimize", "Minimize window", "<super> KEY_M"),
    ("wm-actions", "toggle_fullscreen", "Full screen", "<super> <ctrl> KEY_F"),
    ("grid", "slot_l", "Fill the left half", "<super> KEY_LEFT | <super> KEY_KP4"),
    ("grid", "slot_r", "Fill the right half", "<super> KEY_RIGHT | <super> KEY_KP6"),
    ("grid", "slot_c", "Fill the screen", "<super> KEY_UP | <super> KEY_KP5"),
    ("grid", "restore", "Back to its own size", "<super> KEY_DOWN | <super> KEY_KP0"),
    ("command", "binding_terminal", "Open a terminal", "<super> KEY_ENTER"),
    ("command", "binding_lock", "Lock the screen", "<super> KEY_L"),
    ("command", "binding_lens_screen", "Screenshot", "KEY_SYSRQ"),
    ("command", "binding_lens_area", "Screenshot of an area", "<shift> KEY_SYSRQ"),
    ("command", "binding_lens_window", "Screenshot of a window", "<alt> KEY_SYSRQ"),
    ("command", "binding_lens_record", "Start or stop recording the screen", "<ctrl> KEY_SYSRQ"),
    ("command", "binding_lens_record_area", "Start or stop recording an area", "<ctrl> <shift> KEY_SYSRQ"),
)

MODIFIERS = (("<super>", "Super"), ("<ctrl>", "Ctrl"), ("<alt>", "Alt"), ("<shift>", "Shift"))
NAMES = {"SYSRQ": "Print Screen", "ENTER": "Enter", "ESC": "Escape", "PAGEUP": "Page Up",
         "PAGEDOWN": "Page Down", "BACKSPACE": "Backspace", "LEFTBRACE": "[", "RIGHTBRACE": "]",
         "SEMICOLON": ";", "APOSTROPHE": "'", "GRAVE": "`", "BACKSLASH": "\\", "COMMA": ",",
         "DOT": ".", "SLASH": "/", "MINUS": "-", "EQUAL": "=", "CAPSLOCK": "Caps Lock"}
# Used when libevdev isn't there: GDK key names for the keys people pick most.
FALLBACK = {"space": "SPACE", "Return": "ENTER", "Tab": "TAB", "Escape": "ESC", "BackSpace": "BACKSPACE",
            "Delete": "DELETE", "Print": "SYSRQ", "Up": "UP", "Down": "DOWN", "Left": "LEFT", "Right": "RIGHT",
            "Home": "HOME", "End": "END", "Page_Up": "PAGEUP", "Page_Down": "PAGEDOWN", "minus": "MINUS",
            "equal": "EQUAL", "comma": "COMMA", "period": "DOT", "slash": "SLASH"}

try:
    _evdev = ctypes.CDLL("libevdev.so.2")
    _evdev.libevdev_event_code_get_name.restype = ctypes.c_char_p
    _evdev.libevdev_event_code_get_name.argtypes = (ctypes.c_uint, ctypes.c_uint)
except OSError:
    _evdev = None


def alternatives(value):
    return [part.strip() for part in (value or "").split("|") if part.strip()]


def describe(binding):
    """"<super> KEY_SPACE" -> "Super+Space"."""
    words = binding.split()
    if not words or not words[-1].startswith("KEY_"):
        return None
    parts = [label for tag, label in MODIFIERS if tag in words[:-1]]
    key = words[-1][4:]
    if key.startswith("KP") and len(key) > 2:
        name = "Keypad " + key[2:].title()
    else:
        plain = len(key) == 1 or (key[0] == "F" and key[1:].isdigit())
        name = NAMES.get(key) or (key if plain else key.replace("_", " ").title())
    return "+".join(parts + [name])


def describe_all(value):
    keys = [d for d in (describe(b) for b in alternatives(value)) if d and "Keypad" not in d]
    swipes = [b for b in alternatives(value) if b.startswith("swipe")]
    text = " or ".join(keys) if keys else "Off"
    if swipes:
        fingers = swipes[0].split()[-1]
        text += f", or swipe {swipes[0].split()[1]} with {fingers} fingers"
    return text


def key_name(event):
    """The evdev name of the key pressed, such as KEY_A, whatever the layout."""
    if _evdev is not None:
        name = _evdev.libevdev_event_code_get_name(1, event.hardware_keycode - 8)
        if name:
            return name.decode()
    keyval = Gdk.keyval_name(Gdk.keyval_to_lower(event.keyval)) or ""
    if len(keyval) == 1 and keyval.isalnum():
        return "KEY_" + keyval.upper()
    if keyval.startswith("F") and keyval[1:].isdigit():
        return "KEY_" + keyval
    return "KEY_" + FALLBACK[keyval] if keyval in FALLBACK else None


def binding_from(event):
    if Gdk.keyval_name(event.keyval) in ("Shift_L", "Shift_R", "Control_L", "Control_R", "Alt_L", "Alt_R",
                                         "Super_L", "Super_R", "Meta_L", "Meta_R", "ISO_Level3_Shift"):
        return None
    key = key_name(event)
    if not key:
        return None
    state = event.state
    tags = []
    if state & (Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.MOD4_MASK):
        tags.append("<super>")
    if state & Gdk.ModifierType.CONTROL_MASK:
        tags.append("<ctrl>")
    if state & Gdk.ModifierType.MOD1_MASK:
        tags.append("<alt>")
    if state & Gdk.ModifierType.SHIFT_MASK:
        tags.append("<shift>")
    return " ".join(tags + [key])


def same(a, b):
    return sorted(a.split()) == sorted(b.split())


class Shortcuts:
    """The shortcut rows for the Keyboard panel."""

    def __init__(self, window, ini_get, ini_set, group, row):
        self.window, self.ini_get, self.ini_set = window, ini_get, ini_set
        self.labels = {}
        rows = []
        for section, option, title, default in SHORTCUTS:
            label = Gtk.Label(label=describe_all(self.value(section, option, default)), xalign=1)
            label.get_style_context().add_class("dim-label")
            self.labels[(section, option)] = label
            change = Gtk.Button(label="Change…")
            change.connect("clicked", lambda _b, s=section, o=option, t=title, d=default: self.change(s, o, t, d))
            box = Gtk.Box(spacing=12)
            box.pack_start(label, False, False, 0)
            box.pack_start(change, False, False, 0)
            rows.append(row(title, box))
        reset = Gtk.Button(label="Restore All Shortcuts")
        reset.connect("clicked", lambda _b: self.reset_all())
        rows.append(row("Shortcuts as freemac ships them", reset))
        self.widget = group(*rows)

    def value(self, section, option, default):
        current = self.ini_get(section, option, None)
        return default if current is None else current

    def owner(self, binding, skip):
        for section, option, title, default in SHORTCUTS:
            if (section, option) == skip:
                continue
            if any(same(binding, b) for b in alternatives(self.value(section, option, default))):
                return title
        return None

    def change(self, section, option, title, default):
        dialog = Gtk.Dialog(title=f"Shortcut for {title}", transient_for=self.window, modal=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Turn Off", Gtk.ResponseType.REJECT)
        box = dialog.get_content_area()
        box.set_spacing(10)
        box.set_border_width(18)
        prompt = Gtk.Label(label=f"Press the keys for “{title}”.", xalign=0)
        hint = Gtk.Label(label="Hold Super, Ctrl, Alt or Shift and press a key. Escape cancels.", xalign=0)
        hint.get_style_context().add_class("dim-label")
        box.pack_start(prompt, False, False, 0)
        box.pack_start(hint, False, False, 0)
        chosen = {}

        def pressed(_widget, event):
            if Gdk.keyval_name(event.keyval) == "Escape" and not event.state & Gdk.ModifierType.MODIFIER_MASK:
                dialog.response(Gtk.ResponseType.CANCEL)
                return True
            binding = binding_from(event)
            if binding is None:
                return True
            if "<" not in binding and not binding.split()[-1].startswith(("KEY_F", "KEY_SYSRQ")):
                hint.set_text(f"{describe(binding)} on its own is for typing; hold Super, Ctrl or Alt with it.")
                return True
            taken = self.owner(binding, (section, option))
            if taken:
                hint.set_text(f"{describe(binding)} is already used for “{taken}”.")
                return True
            chosen["binding"] = binding
            dialog.response(Gtk.ResponseType.OK)
            return True

        dialog.connect("key-press-event", pressed)
        dialog.show_all()
        answer = dialog.run()
        dialog.destroy()
        current = alternatives(self.value(section, option, default))
        keys = [b for b in current if "KEY_" in b]
        others = [b for b in current if b not in keys[:1]]
        if answer == Gtk.ResponseType.OK:
            self.store(section, option, [chosen["binding"]] + others)
        elif answer == Gtk.ResponseType.REJECT:
            self.store(section, option, [b for b in current if "KEY_" not in b])

    def store(self, section, option, parts):
        value = " | ".join(parts)
        self.ini_set(section, option, value)
        self.labels[(section, option)].set_text(describe_all(value))

    def reset_all(self):
        for section, option, _title, default in SHORTCUTS:
            if self.ini_get(section, option, None) is not None:
                self.store(section, option, alternatives(default))
