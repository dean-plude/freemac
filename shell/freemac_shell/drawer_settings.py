# SPDX-License-Identifier: GPL-3.0-or-later
"""Drawer > Settings… (⌘,), as Finder has: what new windows show, and in
Advanced, the warning before emptying the Trash, removing items from the
Trash after 30 days, and keeping folders on top when sorting.

The choices live in ~/.config/freemac/drawer.json with Drawer's others:
"new_window" (home, desktop, documents, downloads or recents),
"warn_empty_trash", "trash_after_30_days" and "folders_on_top". Topline
does the 30 days, since it's always running (transfer.purge_old_trash).
Original freemac code.
"""
import json
import os

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

CONFIG = os.path.join(GLib.get_user_config_dir(), "freemac", "drawer.json")
DEFAULTS = {"new_window": "home", "warn_empty_trash": True, "trash_after_30_days": False,
            "folders_on_top": True}
START_PLACES = (("home", "Home"), ("desktop", "Desktop"), ("documents", "Documents"),
                ("downloads", "Downloads"), ("recents", "Recents"))


def load():
    try:
        with open(CONFIG) as f:
            config = json.load(f)
        return config if isinstance(config, dict) else {}
    except (OSError, ValueError):
        return {}


def get(key):
    value = load().get(key, DEFAULTS[key])
    return value if isinstance(value, type(DEFAULTS[key])) else DEFAULTS[key]


def put(key, value):
    config = load()
    config[key] = value
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        tmp = CONFIG + ".tmp"
        with open(tmp, "w") as f:
            json.dump(config, f, indent=2)
        os.replace(tmp, CONFIG)
    except OSError:
        pass


def start_folder(recents_place):
    """Where a new Drawer window opens."""
    choice = get("new_window")
    if choice == "recents":
        return recents_place
    special = {"desktop": GLib.UserDirectory.DIRECTORY_DESKTOP,
               "documents": GLib.UserDirectory.DIRECTORY_DOCUMENTS,
               "downloads": GLib.UserDirectory.DIRECTORY_DOWNLOAD}.get(choice)
    path = GLib.get_user_special_dir(special) if special is not None else None
    return path if path and os.path.isdir(path) else GLib.get_home_dir()


class SettingsWindow(Gtk.Window):
    """One window, two tabs, as Finder's settings."""

    def __init__(self, on_change=None):
        super().__init__(title="Drawer Settings", resizable=False)
        self.on_change = on_change or (lambda key: None)
        self.set_border_width(0)
        stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        stack.add_titled(self._general(), "general", "General")
        stack.add_titled(self._advanced(), "advanced", "Advanced")
        switcher = Gtk.StackSwitcher(stack=stack, halign=Gtk.Align.CENTER, margin_top=12)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.pack_start(switcher, False, False, 0)
        box.pack_start(stack, True, True, 0)
        self.add(box)
        self.connect("key-press-event", self._key)

    def _key(self, _widget, event):
        from gi.repository import Gdk
        if event.keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def _page(self):
        grid = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                       margin_start=28, margin_end=28, margin_bottom=24, margin_top=6)
        grid.set_size_request(420, -1)
        return grid

    def _check(self, label, key):
        check = Gtk.CheckButton(label=label, active=get(key))

        def toggled(button):
            put(key, button.get_active())
            self.on_change(key)
        check.connect("toggled", toggled)
        return check

    def _general(self):
        page = self._page()
        label = Gtk.Label(label="New Drawer windows show:", xalign=0)
        choice = Gtk.ComboBoxText()
        for value, title in START_PLACES:
            choice.append(value, title)
        choice.set_active_id(get("new_window"))

        def picked(combo):
            put("new_window", combo.get_active_id())
            self.on_change("new_window")
        choice.connect("changed", picked)
        line = Gtk.Box(spacing=10)
        line.pack_start(label, False, False, 0)
        line.pack_start(choice, False, False, 0)
        page.pack_start(line, False, False, 0)
        return page

    def _advanced(self):
        page = self._page()
        page.pack_start(self._check("Show warning before emptying the Trash", "warn_empty_trash"),
                        False, False, 0)
        page.pack_start(self._check("Remove items from the Trash after 30 days", "trash_after_30_days"),
                        False, False, 0)
        page.pack_start(self._check("Keep folders on top when sorting", "folders_on_top"),
                        False, False, 0)
        return page
