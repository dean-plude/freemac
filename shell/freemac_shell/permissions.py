# SPDX-License-Identifier: GPL-3.0-or-later
"""Sharing and permissions, as in a Mac's Get Info window: who may open an
item and whether they may change it, for its owner, its group and everyone
else, each Read & Write, Read only or No Access.

On Linux these are the item's permission bits. A folder you can read can
also be opened (its x bit follows its r bit); a file keeps whether it is a
program. A locked item (see locks.py) has had writing taken away, so its
privileges are read from the permission it will get back when unlocked.
Apply to Enclosed Items gives everything inside a folder the folder's
privileges. Original freemac code.
"""
import grp
import os
import pwd
import stat

from . import locks

# (key, words) in the order the menu lists them.
LEVELS = (("rw", "Read & Write"), ("r", "Read only"), ("none", "No Access"))
WRITE_ONLY = ("w", "Write only (Drop Box)")
WORDS = dict(LEVELS + (WRITE_ONLY,))
# (who, how far its three bits are shifted)
SHIFTS = (("owner", 6), ("group", 3), ("everyone", 0))
SHIFT = dict(SHIFTS)


def level_of(mode, shift):
    bits = (mode >> shift) & 7
    if bits & 4 and bits & 2:
        return "rw"
    if bits & 4:
        return "r"
    if bits & 2:
        return "w"
    return "none"


def with_level(mode, shift, level, is_dir):
    """mode with one class's privilege set to level."""
    bits = (mode >> shift) & 7
    if is_dir:
        new = {"rw": 7, "r": 5, "w": 3, "none": 0}[level]
    else:
        run = bits & 1
        new = {"rw": 6 | run, "r": 4 | run, "w": 2, "none": 0}[level]
    return (mode & ~(7 << shift)) | (new << shift)


def current_mode(path):
    """The item's permission, or the one it gets back when unlocked."""
    mode = stat.S_IMODE(os.lstat(path).st_mode)
    if locks.is_locked(path):
        try:
            return int(os.getxattr(path, locks.ATTR, follow_symlinks=False).decode(), 8) & 0o7777
        except (OSError, ValueError):
            pass
    return mode


def can_change(path):
    """Only the owner changes the privileges, and not while the item is locked
    or for an alias."""
    try:
        info = os.lstat(path)
    except OSError:
        return False
    return (not stat.S_ISLNK(info.st_mode) and info.st_uid == os.getuid()
            and not locks.is_locked(path))


def names(path):
    """{who: the name shown} for the item's owner, group and everyone."""
    info = os.lstat(path)
    try:
        user = pwd.getpwuid(info.st_uid)
        owner = user.pw_name
    except KeyError:
        owner = str(info.st_uid)
    if info.st_uid == os.getuid():
        owner = f"{owner} (Me)"
    try:
        group = grp.getgrgid(info.st_gid).gr_name
    except KeyError:
        group = str(info.st_gid)
    return {"owner": owner, "group": group, "everyone": "everyone"}


def rows(path):
    """[(who, name, level)] for the Get Info table."""
    mode = current_mode(path)
    shown = names(path)
    return [(who, shown[who], level_of(mode, shift)) for who, shift in SHIFTS]


def set_level(path, who, level):
    """Set one class's privilege on path."""
    is_dir = stat.S_ISDIR(os.lstat(path).st_mode)
    mode = stat.S_IMODE(os.lstat(path).st_mode)
    os.chmod(path, with_level(mode, SHIFT[who], level, is_dir))


def apply_to_enclosed(folder, stop=None):
    """Give everything inside folder the folder's privileges, as Apply to
    Enclosed Items does. Aliases, locked items and items you don't own are
    left alone. The deepest items go first, so a folder is still open while
    its own items change. Returns (changed, skipped)."""
    mode = current_mode(folder)
    levels = {who: level_of(mode, shift) for who, shift in SHIFTS}
    changed = skipped = 0
    uid = os.getuid()
    for root, dirs, files in os.walk(folder, topdown=False, onerror=lambda _e: None):
        for name in dirs + files:
            if stop is not None and stop.is_set():
                return changed, skipped
            path = os.path.join(root, name)
            try:
                info = os.lstat(path)
            except OSError:
                skipped += 1
                continue
            if stat.S_ISLNK(info.st_mode):
                continue
            if info.st_uid != uid or locks.is_locked(path):
                skipped += 1
                continue
            is_dir = stat.S_ISDIR(info.st_mode)
            new = old = stat.S_IMODE(info.st_mode)
            for who, shift in SHIFTS:
                new = with_level(new, shift, levels[who], is_dir)
            if new != old:
                try:
                    os.chmod(path, new)
                    changed += 1
                except OSError:
                    skipped += 1
    return changed, skipped
