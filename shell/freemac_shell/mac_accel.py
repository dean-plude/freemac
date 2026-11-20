# SPDX-License-Identifier: GPL-3.0-or-later
"""Shortcuts shown the Mac way in menus: ⇧⌘S on the right, not "Shift+Ctrl+S".

GTK draws a menu item's shortcut itself, in PC style. Topline hands each menu
it shows (the app's own menus from D-Bus, and its own) to macify(), which
swaps each item's label for one with the name on the left and the shortcut
in Mac symbols on the right. Apps' shortcuts use Ctrl; freemac's Command key
is what presses them (Strata turns ⌘ into Ctrl for apps), so Ctrl is shown
as ⌘ unless the Command key is turned off in Dials. Original freemac code.
"""
import configparser
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

CONTROL, OPTION, SHIFT, COMMAND = "⌃", "⌥", "⇧", "⌘"
SPECIAL = {
    "Return": "↩", "KP_Enter": "⌤", "BackSpace": "⌫", "Delete": "⌦",
    "Escape": "⎋", "Tab": "⇥", "ISO_Left_Tab": "⇥", "space": "Space",
    "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
    "Page_Up": "⇞", "Page_Down": "⇟", "Home": "↖", "End": "↘",
    "Print": "Print Screen",
}
WAYFIRE_INI = os.path.expanduser("~/.config/wayfire.ini")
DONE = "freemac-mac-accel"


def command_key_on():
    """Whether Strata's Command key is on (it is unless turned off in Dials)."""
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(WAYFIRE_INI)
        return parser.get("strata-shell", "command_key", fallback="true").strip().lower() != "false"
    except (configparser.Error, OSError):
        return True


def key_text(keyval):
    name = Gdk.keyval_name(keyval) or ""
    if name in SPECIAL:
        return SPECIAL[name]
    if name.startswith("F") and name[1:].isdigit():
        return name
    char = Gdk.keyval_to_unicode(Gdk.keyval_to_upper(keyval))
    if char and chr(char).isprintable() and not chr(char).isspace():
        return chr(char)
    return name.replace("_", " ")


def chord(accel):
    """A GTK shortcut ("<Primary><Shift>n") as Strata names the keys pressed
    for it: "command+shift+n". Apps' Ctrl shortcuts are pressed with ⌘.
    "" for shortcuts that don't use Ctrl."""
    keyval, mods = Gtk.accelerator_parse(accel or "")
    other = Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.MOD4_MASK | Gdk.ModifierType.META_MASK
    if not keyval or not (mods & Gdk.ModifierType.CONTROL_MASK) or (mods & other):
        return ""
    name = Gdk.keyval_name(Gdk.keyval_to_lower(keyval))
    if not name:
        return ""
    parts = ["command"]
    if mods & Gdk.ModifierType.SHIFT_MASK:
        parts.append("shift")
    if mods & Gdk.ModifierType.MOD1_MASK:
        parts.append("alt")
    return "+".join(sorted(parts) + [name])


def text(keyval, mods, command_is_ctrl=True):
    """Mac order: ⌃ ⌥ ⇧ ⌘ then the key."""
    if not keyval:
        return ""
    command = bool(mods & (Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.MOD4_MASK))
    control = bool(mods & Gdk.ModifierType.CONTROL_MASK)
    if command_is_ctrl and control:
        command, control = True, False
    # Shift with a symbol that needs it (? from /) shows the symbol alone.
    shift = bool(mods & Gdk.ModifierType.SHIFT_MASK)
    parts = [CONTROL if control else "", OPTION if mods & Gdk.ModifierType.MOD1_MASK else "",
             SHIFT if shift else "", COMMAND if command else ""]
    return "".join(parts) + key_text(keyval)


def _swap(item, command_is_ctrl):
    child = item.get_child()
    if not isinstance(child, Gtk.AccelLabel):
        return
    keyval, mods = child.get_accel()
    if not keyval:
        return
    title = child.get_label()
    child.set_accel(0, 0)  # GTK's own "Ctrl+S" goes
    box = Gtk.Box(spacing=24)
    name = Gtk.Label(label=title, use_underline=child.get_use_underline(), xalign=0)
    shortcut = Gtk.Label(label=text(keyval, mods, command_is_ctrl), xalign=1)
    shortcut.get_style_context().add_class("dim-label")
    shortcut.get_style_context().add_class("accelerator")
    box.pack_start(name, True, True, 0)
    box.pack_end(shortcut, False, False, 0)
    item.remove(child)
    item.add(box)
    box.show_all()


def _walk(menu, command_is_ctrl):
    for item in menu.get_children():
        if isinstance(item, Gtk.MenuItem):
            _swap(item, command_is_ctrl)
            sub = item.get_submenu()
            if sub is not None:
                macify(sub)


def macify(menu):
    """Show this menu's (and its submenus') shortcuts in Mac symbols, now and
    whenever it opens (items from D-Bus can arrive after it's made)."""
    if getattr(menu, DONE.replace("-", "_"), False):
        return menu
    setattr(menu, DONE.replace("-", "_"), True)
    menu.connect("show", lambda m: _walk(m, command_key_on()))
    _walk(menu, command_key_on())
    return menu
