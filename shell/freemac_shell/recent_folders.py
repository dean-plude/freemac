# SPDX-License-Identifier: GPL-3.0-or-later
"""Go > Recent Folders, as on a Mac: the last ten folders opened in Drawer,
newest first, shared by every Drawer window. Clear Menu empties it.

The list is kept in ~/.local/share/freemac/recent-folders, one folder per
line. Folders that have gone are left out when the menu is shown, and the
Trash and places that aren't folders (Recents, tags, searches, Network)
never go in. Original freemac code.
"""
import os

DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "freemac")
FILE = os.path.join(DATA, "recent-folders")
MOST = 10


def _read(path=FILE):
    try:
        with open(path, encoding="utf-8") as handle:
            return [line.rstrip("\n") for line in handle if line.strip()]
    except OSError:
        return []


def _write(folders, path=FILE):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        temporary = path + ".new"
        with open(temporary, "w", encoding="utf-8") as handle:
            handle.write("".join(f + "\n" for f in folders))
        os.replace(temporary, path)
    except OSError:
        pass


def listed(path=FILE):
    """The recent folders that are still there, newest first."""
    return [f for f in _read(path) if os.path.isdir(f)][:MOST]


def note(folder, path=FILE):
    """folder was opened: it goes to the top. Returns True if the list changed."""
    if not folder or "\n" in folder or not os.path.isdir(folder):
        return False
    folder = os.path.abspath(folder)
    old = _read(path)
    new = [folder] + [f for f in old if f != folder]
    new = new[:MOST]
    if new == old:
        return False
    _write(new, path)
    return True


def clear(path=FILE):
    _write([], path)


def labels(folders):
    """[(folder, words)] for the menu: each folder's name, with the folder it's
    in added where two have the same name, as a Mac does."""
    def name(f):
        return os.path.basename(f.rstrip("/")) or f
    counts = {}
    for f in folders:
        counts[name(f)] = counts.get(name(f), 0) + 1
    shown = []
    for f in folders:
        words = name(f)
        if counts[words] > 1:
            parent = os.path.basename(os.path.dirname(f.rstrip("/"))) or "/"
            words = f"{words} — {parent}"
        shown.append((f, words))
    return shown
