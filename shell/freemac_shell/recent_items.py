# SPDX-License-Identifier: GPL-3.0-or-later
"""Recent Items in the freemac menu: the apps and documents used lately, as
under a Mac's Apple menu. Topline notes each app that comes to the front;
documents come from the desktop's shared list of recent files (recents.py).
Clear Menu empties this menu only: Drawer's Recents keeps its files.
Original freemac code.
"""
import json
import os
import time

from gi.repository import Gio, GLib

from . import apps, recents

FILE = os.path.join(GLib.get_user_state_dir(), "freemac", "recent-items.json")
LIMIT = 10
# The shell's own windows aren't apps a person opens.
SKIP = {"freemac-pier.desktop", "freemac-topline.desktop", "freemac-force-quit.desktop",
        "freemac-backdrop.desktop", "freemac-power.desktop"}


def _load():
    try:
        with open(FILE) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    ids = data.get("apps")
    data["apps"] = [i for i in ids if isinstance(i, str)] if isinstance(ids, list) else []
    if not isinstance(data.get("cleared"), (int, float)):
        data["cleared"] = 0
    return data


def _save(data):
    try:
        os.makedirs(os.path.dirname(FILE), exist_ok=True)
        tmp = FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, FILE)
    except OSError:
        pass


def note_app(app_id):
    """An app's window came to the front: it goes first in the list."""
    info = apps.app_info(app_id)
    desktop_id = info.get_id() if info else None
    if not desktop_id or desktop_id in SKIP or not info.should_show():
        return
    data = _load()
    if data["apps"][:1] == [desktop_id]:
        return
    data["apps"] = ([desktop_id] + [i for i in data["apps"] if i != desktop_id])[:LIMIT]
    _save(data)


def recent_apps():
    """[Gio.DesktopAppInfo] of the apps used lately that are still installed."""
    found = []
    for desktop_id in _load()["apps"]:
        try:
            info = Gio.DesktopAppInfo.new(desktop_id)
        except TypeError:
            info = None
        if info:
            found.append(info)
    return found


def recent_documents(limit=LIMIT):
    """Paths of the files opened lately, since the menu was last cleared."""
    cleared = _load()["cleared"]
    if not cleared:
        return recents.files(limit)
    return [p for p in recents.files(limit * 3) if _opened(p) > cleared][:limit]


def _opened(path):
    """When a file on the shared list was last opened, in seconds."""
    from gi.repository import Gtk
    try:
        item = Gtk.RecentManager.get_default().lookup_item(Gio.File.new_for_path(path).get_uri())
    except GLib.Error:
        return 0
    return max(item.get_visited(), item.get_modified()) if item else 0


def clear():
    _save({"apps": [], "cleared": time.time()})
