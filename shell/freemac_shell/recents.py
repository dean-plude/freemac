# SPDX-License-Identifier: GPL-3.0-or-later
"""Recents: the files opened lately, newest first, as Finder's Recents.

They come from the desktop's shared list of recent files
(~/.local/share/recently-used.xbel, through Gtk.RecentManager), which
freemac's own apps and most other Linux apps add to when they open a
file. Drawer and the desktop add a file there too when they open it.
Original freemac code.
"""
import os

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

PLACE = "recents:"   # Drawer's name for the Recents place
LIMIT = 60
TRASH = os.path.join(GLib.get_user_data_dir(), "Trash")


def note(path):
    """Add a file that was just opened to the list."""
    try:
        Gtk.RecentManager.get_default().add_item(Gio.File.new_for_path(path).get_uri())
    except GLib.Error:
        pass


def files(limit=LIMIT):
    """The files that are still there, newest first; folders and the Trash
    are left out."""
    found, seen = [], set()
    items = Gtk.RecentManager.get_default().get_items()
    items.sort(key=lambda i: max(i.get_visited(), i.get_modified()), reverse=True)
    for item in items:
        if not item.is_local():
            continue
        path = Gio.File.new_for_uri(item.get_uri()).get_path()
        if (not path or path in seen or not os.path.isfile(path)
                or path.startswith(TRASH + os.sep)):
            continue
        seen.add(path)
        found.append(path)
        if len(found) >= limit:
            break
    return found


def forget(paths):
    """Take files off the list (the Recents menu's Remove from Recents)."""
    manager = Gtk.RecentManager.get_default()
    for path in paths:
        try:
            manager.remove_item(Gio.File.new_for_path(path).get_uri())
        except GLib.Error:
            pass
