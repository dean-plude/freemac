# SPDX-License-Identifier: GPL-3.0-or-later
"""Bosun's shortcuts, kept in ~/.config/freemac/bosun.json.

Each shortcut has an id (eight hex digits), a name, a colour, what it takes
("nothing", "text" or "files") and its steps (bosun_actions). One that
takes words or files can be offered in the Services menu and in Drawer's
menu for files, as "bosun_<id>" in services.py, so it can have keys too.
No GTK. Original freemac code.
"""
import copy
import json
import os
import secrets

PATH = os.path.expanduser("~/.config/freemac/bosun.json")
COLOURS = ("blue", "teal", "green", "yellow", "orange", "red", "pink", "purple", "grey")
TAKES = ("nothing", "text", "files")

# The Gallery: ready-made shortcuts to start from.
STARTERS = (
    {"name": "Dark Mode On or Off", "colour": "purple", "takes": "nothing",
     "about": "Switches between light and dark mode.",
     "steps": [{"do": "appearance", "mode": "toggle"}]},
    {"name": "Speak What I Copied", "colour": "teal", "takes": "nothing",
     "about": "Reads aloud whatever was last copied.",
     "steps": [{"do": "get_clipboard"}, {"do": "speak"}]},
    {"name": "Pictures to PDF", "colour": "red", "takes": "files", "services": True,
     "about": "Puts the pictures you choose into one PDF and shows it in Drawer.",
     "steps": [{"do": "make_pdf"}, {"do": "reveal"}]},
    {"name": "Zip and Show", "colour": "orange", "takes": "files", "services": True,
     "about": "Makes a .zip of the files you choose and shows it in Drawer.",
     "steps": [{"do": "compress"}, {"do": "reveal"}]},
    {"name": "Smaller Pictures for Email", "colour": "green", "takes": "files", "services": True,
     "about": "Makes copies of the pictures no wider than 1600 pixels, beside them.",
     "steps": [{"do": "resize", "size": 1600}, {"do": "reveal"}]},
    {"name": "Quiet Time", "colour": "blue", "takes": "nothing",
     "about": "Turns on Do Not Disturb and mutes the sound.",
     "steps": [{"do": "focus", "focus": "on"}, {"do": "mute", "mute": "on"},
               {"do": "notify", "title": "Quiet Time", "body": "Do Not Disturb is on and the sound is off."}]},
    {"name": "Count the Words", "colour": "yellow", "takes": "text", "services": True,
     "about": "Counts the words you select and shows how many.",
     "steps": [{"do": "count", "what": "words"}, {"do": "show", "text": "{input} words"}]},
    {"name": "Make It Capitals", "colour": "pink", "takes": "text", "services": True,
     "about": "Copies the words you select in capitals, ready to paste.",
     "steps": [{"do": "case", "case": "upper"}, {"do": "copy"},
               {"do": "notify", "title": "Copied in capitals", "body": "{input}"}]},
    {"name": "Desktop Pictures to Pictures", "colour": "grey", "takes": "nothing",
     "about": "Copies the pictures on the Desktop into the Pictures folder.",
     "steps": [{"do": "folder_files", "folder": "~/Desktop", "kind": "pictures"},
               {"do": "copy_to", "folder": "~/Pictures"}, {"do": "count", "what": "items"},
               {"do": "notify", "title": "Pictures copied", "body": "{input} copied to Pictures."}]},
)


def _clean(item):
    if not isinstance(item, dict):
        return None
    shortcut_id = str(item.get("id", ""))
    if not (len(shortcut_id) == 8 and all(c in "0123456789abcdef" for c in shortcut_id)):
        return None
    steps = [s for s in item.get("steps", []) if isinstance(s, dict) and isinstance(s.get("do"), str)]
    return {
        "id": shortcut_id,
        "name": str(item.get("name") or "Untitled")[:120],
        "colour": item.get("colour") if item.get("colour") in COLOURS else "blue",
        "takes": item.get("takes") if item.get("takes") in TAKES else "nothing",
        "services": bool(item.get("services")) and item.get("takes") in ("text", "files"),
        "steps": steps,
    }


def load(path=PATH):
    try:
        with open(path, encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, ValueError):
        return []
    items = raw.get("shortcuts", []) if isinstance(raw, dict) else []
    return [s for s in (_clean(i) for i in items) if s]


def save(shortcuts, path=PATH):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = path + ".new"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump({"shortcuts": shortcuts}, handle, indent=2, ensure_ascii=False)
    os.replace(temporary, path)


def new_id(taken=()):
    while True:
        candidate = secrets.token_hex(4)
        if candidate not in taken:
            return candidate


def make(name="New Shortcut", shortcuts=(), **fields):
    shortcut = {"id": new_id({s["id"] for s in shortcuts}), "name": name, "colour": "blue",
                "takes": "nothing", "services": False, "steps": []}
    shortcut.update({k: copy.deepcopy(v) for k, v in fields.items() if k in shortcut})
    return _clean(shortcut)


def from_starter(starter, shortcuts=()):
    return make(starter["name"], shortcuts, colour=starter["colour"], takes=starter["takes"],
                services=starter.get("services", False), steps=starter["steps"])


def find(shortcut_id, shortcuts=None):
    for shortcut in load() if shortcuts is None else shortcuts:
        if shortcut["id"] == shortcut_id:
            return shortcut
    return None


def free_name(name, shortcuts, ignore=None):
    names = {s["name"].lower() for s in shortcuts if s["id"] != ignore}
    if name.lower() not in names:
        return name
    number = 2
    while f"{name} {number}".lower() in names:
        number += 1
    return f"{name} {number}"


def as_services(kind, shortcuts=None):
    """(service id, name) for the shortcuts offered in the Services menu that
    take this kind ("text" or "files")."""
    return [(f"bosun_{s['id']}", s["name"]) for s in (load() if shortcuts is None else shortcuts)
            if s["services"] and s["takes"] == kind]
