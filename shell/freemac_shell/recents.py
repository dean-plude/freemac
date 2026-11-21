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


def for_app(info, limit=5):
    """Recent files for an app's menu in the Dock: ones it opened itself, by
    the list's own record, or ones it is the usual app for. Newest first."""
    if info is None:
        return []
    try:
        types = set(info.get_supported_types() or [])
    except (AttributeError, TypeError):
        types = set()
    names = {n.casefold() for n in (info.get_name(), info.get_display_name(),
                                     os.path.basename((info.get_executable() or "")),
                                     (info.get_id() or "").removesuffix(".desktop")) if n}
    own_id = info.get_id()
    defaults = {}

    def usual_app(mime):
        if mime not in defaults:
            app = Gio.AppInfo.get_default_for_type(mime, False)
            defaults[mime] = app is not None and app.get_id() == own_id
        return defaults[mime]

    found = []
    items = Gtk.RecentManager.get_default().get_items()
    items.sort(key=lambda i: max(i.get_visited(), i.get_modified()), reverse=True)
    for item in items:
        if not item.is_local():
            continue
        opened_here = any(a.casefold() in names for a in (item.get_applications() or []))
        mime = item.get_mime_type() or ""
        if not opened_here and not (mime in types and usual_app(mime)):
            continue
        path = Gio.File.new_for_uri(item.get_uri()).get_path()
        if (not path or path in found or not os.path.isfile(path)
                or path.startswith(TRASH + os.sep)):
            continue
        found.append(path)
        if len(found) >= limit:
            break
    return found
