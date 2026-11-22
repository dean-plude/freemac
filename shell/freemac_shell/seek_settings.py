# SPDX-License-Identifier: GPL-3.0-or-later
"""What Seek shows, and the folders it leaves alone (Dials > Seek), as a
Mac's Spotlight settings have Search results and Privacy.

Kept in ~/.config/freemac/seek.json:
    {"off": ["events", ...], "private": ["/home/dean/Taxes", ...]}

Seek reads it each time you type, so a change counts at once. A private
folder is left out of Seek's names and of the index of words inside
documents (what was read from it before is dropped), and Drawer's This Mac
searches and Smart Folders leave it out too. Turning off Words inside
documents empties that index and stops it being kept. Original freemac code.
"""
import json
import os

from gi.repository import GLib

FILE = os.path.join(GLib.get_user_config_dir(), "freemac", "seek.json")

# In the order Seek lists them.
CATEGORIES = (
    ("apps", "Applications"),
    ("calculator", "Calculator and conversions"),
    ("settings", "Settings"),
    ("guide", "Guide topics"),
    ("menus", "Menu items"),
    ("contacts", "Contacts"),
    ("events", "Events"),
    ("reminders", "Reminders"),
    ("files", "Files and folders"),
    ("contents", "Words inside documents"),
)

_cache = {"stamp": None, "value": None}


def load():
    """{"off": set of category names, "private": [absolute folder paths]}"""
    try:
        stamp = os.stat(FILE).st_mtime_ns
    except OSError:
        stamp = None
    if stamp is not None and stamp == _cache["stamp"]:
        return _cache["value"]
    value = {"off": set(), "private": []}
    if stamp is not None:
        try:
            with open(FILE, encoding="utf-8") as f:
                raw = json.load(f)
        except (OSError, ValueError):
            raw = {}
        if isinstance(raw, dict):
            known = dict(CATEGORIES)
            value["off"] = {c for c in raw.get("off", []) if c in known}
            value["private"] = [os.path.abspath(p) for p in raw.get("private", [])
                                if isinstance(p, str) and p.strip()]
    _cache.update(stamp=stamp, value=value)
    return value


def _store(value):
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    temp = FILE + ".new"
    with open(temp, "w", encoding="utf-8") as f:
        json.dump({"off": sorted(value["off"]), "private": value["private"]}, f, indent=1, ensure_ascii=False)
    os.replace(temp, FILE)
    _cache["stamp"] = None


def shown(category):
    return category not in load()["off"]


def set_shown(category, on):
    value = load()
    off = set(value["off"])
    (off.discard if on else off.add)(category)
    _store({"off": off, "private": list(value["private"])})


def private():
    return list(load()["private"])


def add_private(path):
    value = load()
    path = os.path.abspath(path)
    if path not in value["private"]:
        _store({"off": set(value["off"]), "private": value["private"] + [path]})


def remove_private(path):
    value = load()
    _store({"off": set(value["off"]), "private": [p for p in value["private"] if p != path]})


def is_private(path, folders=None):
    """Whether the path is one of the private folders or inside one."""
    path = os.path.abspath(path)
    for folder in private() if folders is None else folders:
        if path == folder or path.startswith(folder.rstrip(os.sep) + os.sep):
            return True
    return False
