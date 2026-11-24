# SPDX-License-Identifier: GPL-3.0-or-later
"""What Tender finds and copies, without any windows.

A source is somewhere a person's files can come from:

  backup    the newest Lifeboat backup of any computer on a drive
            (<drive>/freemac-backups/<computer>-<user>/<date>)
  windows   a Windows PC's disk, plugged in or in this computer
            (<drive>/Users/<name>)
  linux     another freemac or Linux computer's disk (<drive>/home/<name>)
  folder    any folder you choose

Each source has kinds of files to bring: Documents, Pictures, Music and so
on, each with its size, and for a freemac backup or disk also its settings
and app data. Copying merges into your home folder and never overwrites a
file: one that is already here and the same is left alone, and one with the
same name but different is kept beside it as "name 2". Settings are the
one exception, as on a Mac: they replace this account's, and the ones they
replace are kept in ~/.local/share/freemac-tender/ in case you want them back.

Original freemac code.
"""
import filecmp
import os
import shutil
import stat
import time
from fnmatch import fnmatch

from . import backup_store

# The folders a home has, and what Windows calls the same ones.
FOLDERS = (
    ("documents", "Documents", "folder-documents", ("Documents",)),
    ("pictures", "Pictures", "folder-pictures", ("Pictures",)),
    ("music", "Music", "folder-music", ("Music",)),
    ("videos", "Videos", "folder-videos", ("Videos",)),
    ("desktop", "Desktop", "user-desktop", ("Desktop",)),
    ("downloads", "Downloads", "folder-download", ("Downloads",)),
)
# OneDrive keeps its own copy of these on a Windows PC; bring them too.
ONEDRIVE = ("OneDrive", "OneDrive - Personal")
WINDOWS_NOT_PEOPLE = {"public", "default", "default user", "all users", "defaultapppool", "wdagutilityaccount"}
# Files Windows makes in every folder for itself.
WINDOWS_JUNK = {"desktop.ini", "thumbs.db", "ntuser.dat", "ntuser.ini", "ntuser.pol", "iconcache.db"}
WINDOWS_SKIP_TOP = {"appdata", "application data", "local settings", "cookies", "nethood", "printhood",
                    "recent", "sendto", "start menu", "templates", "my documents", "intelhd", "3d objects",
                    "searches", "links", "contacts", "saved games", "favorites"}

# Settings that belong to one computer, or that would do harm on another.
SETTINGS_SKIP = backup_store.SKIP + (
    ".Xauthority", ".ICEauthority", ".xsession-errors*", ".local/share/keyrings", ".local/state",
    ".local/share/freemac-tender", ".config/freemac/lifeboat.json", ".config/pulse", ".dbus",
    ".gnupg/S.*", "snap", ".local/share/recently-used.xbel",
)
HOME_FOLDERS = {name for _key, _title, _icon, names in FOLDERS for name in names}


# ---- finding sources -----------------------------------------------------------

def _listdir(path):
    try:
        return sorted(os.listdir(path))
    except OSError:
        return []


def _isdir(path):
    try:
        return stat.S_ISDIR(os.lstat(path).st_mode)
    except OSError:
        return False


def sources_on(root, drive_name):
    """The sources on the drive whose files are at root."""
    found = []
    top = os.path.join(root, backup_store.TOP)
    for computer in _listdir(top):
        base = os.path.join(top, computer)
        stamps = [(backup_store.stamp_time(n), n) for n in _listdir(base)]
        stamps = [(w, n) for w, n in stamps if w is not None and _isdir(os.path.join(base, n))]
        if stamps:
            when, name = max(stamps)
            computer_name, _sep, user = computer.rpartition("-")
            found.append({
                "kind": "backup", "path": os.path.join(base, name), "drive": drive_name,
                "title": f"Lifeboat backup of {user or computer}" + (f" on {computer_name}" if computer_name else ""),
                "detail": f"{backup_store.describe(when)}, on {drive_name}",
                "when": when,
            })
    for name in _listdir(os.path.join(root, "Users")):
        home = os.path.join(root, "Users", name)
        if name.lower() in WINDOWS_NOT_PEOPLE or name.startswith(".") or not _isdir(home):
            continue
        if not any(_isdir(os.path.join(home, f)) for f in ("Documents", "Desktop", "Pictures")):
            continue
        found.append({"kind": "windows", "path": home, "drive": drive_name,
                      "title": f"{name}'s files from Windows", "detail": f"On {drive_name}"})
    for name in _listdir(os.path.join(root, "home")):
        home = os.path.join(root, "home", name)
        if name.startswith(".") or name == "lost+found" or not _isdir(home):
            continue
        if not any(_isdir(os.path.join(home, f)) for f in HOME_FOLDERS):
            continue
        found.append({"kind": "linux", "path": home, "drive": drive_name,
                      "title": f"{name}'s files from another computer", "detail": f"On {drive_name}"})
    return found


def folder_source(path):
    return {"kind": "folder", "path": path, "drive": "",
            "title": os.path.basename(path.rstrip("/")) or path, "detail": path}


# ---- what a source holds ---------------------------------------------------------

def _windows_junk(name):
    return name.lower() in WINDOWS_JUNK or name.lower().startswith("ntuser.dat")


def kinds(source, home=None):
    """The kinds of files a source holds, as dicts with key, title, icon and
    copies: (from, to) folder pairs. The settings kind has settings=True."""
    home = home or backup_store.home()
    path, kind = source["path"], source["kind"]
    found = []
    taken = set()
    for key, title, icon, names in FOLDERS:
        copies = []
        for name in names:
            src = os.path.join(path, name)
            if _isdir(src):
                copies.append((src, os.path.join(home, title)))
                taken.add(name.lower())
            if kind == "windows":
                for drive in ONEDRIVE:
                    src = os.path.join(path, drive, name)
                    if _isdir(src):
                        copies.append((src, os.path.join(home, title)))
        if copies:
            found.append({"key": key, "title": title, "icon": icon, "copies": copies})
    # Everything else at the top of the home folder that isn't hidden.
    others = []
    for name in _listdir(path):
        full = os.path.join(path, name)
        low = name.lower()
        if name.startswith(".") or low in taken or os.path.islink(full):
            continue
        if kind == "windows" and (low in WINDOWS_SKIP_TOP or _windows_junk(name) or name in ONEDRIVE):
            continue
        if kind in ("backup", "linux") and name in ("snap",):
            continue
        others.append(name)
    if others:
        if kind == "folder" and not found:
            dest = os.path.join(home, os.path.basename(path.rstrip("/")) or "Brought Over")
            copies = [(path, dest)]
            title = f"Everything in “{os.path.basename(path.rstrip('/'))}”"
        else:
            copies = [(os.path.join(path, n), os.path.join(home, n)) for n in others]
            title = "Other files and folders"
        found.append({"key": "other", "title": title, "icon": "folder", "copies": copies,
                      "names": others})
    if kind in ("backup", "linux") and any(n.startswith(".") for n in _listdir(path)):
        found.append({"key": "settings", "title": "Settings and app data", "icon": "preferences-system",
                      "copies": [(path, home)], "settings": True})
    return found


def _skip_setting(rel):
    for pattern in SETTINGS_SKIP:
        if rel == pattern or fnmatch(rel, pattern) or rel.startswith(pattern + "/"):
            return True
    return False


def files(kind_info, windows=False):
    """Every file a kind would copy, as (source file, destination file)."""
    settings = kind_info.get("settings")
    for src_top, dst_top in kind_info["copies"]:
        if not settings and not _isdir(src_top):
            try:
                if stat.S_ISREG(os.lstat(src_top).st_mode):
                    yield src_top, dst_top
            except OSError:
                pass
            continue
        for folder, dirs, names in os.walk(src_top):
            rel_folder = os.path.relpath(folder, src_top)
            rel_folder = "" if rel_folder == "." else rel_folder
            if settings and not rel_folder:
                # At the top, only the hidden files and folders are settings.
                dirs[:] = [d for d in dirs if d.startswith(".")]
                names = [n for n in names if n.startswith(".")]
            keep = []
            for d in dirs:
                rel = os.path.join(rel_folder, d)
                full = os.path.join(folder, d)
                if os.path.islink(full):
                    continue      # Windows' "My Music" and the like point elsewhere
                if settings and _skip_setting(rel):
                    continue
                if not settings and backup_store._skipped(rel):
                    continue
                keep.append(d)
            dirs[:] = keep
            for name in names:
                rel = os.path.join(rel_folder, name)
                if windows and (_windows_junk(name) or os.path.islink(os.path.join(folder, name))):
                    continue      # Windows' links point at its own folders, not files
                if settings and _skip_setting(rel):
                    continue
                yield os.path.join(folder, name), os.path.join(dst_top, rel)


def measure(kind_info, windows=False, stop=None):
    """(bytes, files) a kind would copy."""
    total = count = 0
    for src, _dst in files(kind_info, windows):
        if stop and stop():
            break
        try:
            st = os.lstat(src)
        except OSError:
            continue
        if stat.S_ISREG(st.st_mode):
            total += st.st_size
        count += 1
    return total, count


def free_space(home=None):
    return backup_store.free(home or backup_store.home())


# ---- copying -------------------------------------------------------------------

def _same(src, dst, st):
    try:
        dt = os.lstat(dst)
    except OSError:
        return False
    if not stat.S_ISREG(dt.st_mode) or dt.st_size != st.st_size:
        return False
    if abs(dt.st_mtime - st.st_mtime) < 2:
        return True
    try:
        return filecmp.cmp(src, dst, shallow=False)
    except OSError:
        return False


def free_name(path):
    """path, or "name 2", "name 3"… beside it when that's taken."""
    folder, name = os.path.split(path)
    stem, ext = os.path.splitext(name)
    if name.startswith(".") and not ext:
        stem, ext = name, ""
    n = 2
    while os.path.lexists(path):
        path = os.path.join(folder, f"{stem} {n}{ext}")
        n += 1
    return path


def _earlier_copy(src, dst, st):
    """The "name 2", "name 3"… beside dst that is already this file, if any."""
    folder, name = os.path.split(dst)
    stem, ext = os.path.splitext(name)
    if name.startswith(".") and not ext:
        stem, ext = name, ""
    n = 2
    while True:
        candidate = os.path.join(folder, f"{stem} {n}{ext}")
        if not os.path.lexists(candidate):
            return None
        if stat.S_ISREG(st.st_mode) and _same(src, candidate, st):
            return candidate
        n += 1


class Result:
    def __init__(self):
        self.copied = 0
        self.same = 0
        self.renamed = 0
        self.replaced = 0
        self.failed = []
        self.bytes = 0
        self.kept_in = None
        self.stopped = False


def _make_dirs(path):
    """Make the folders for path; if one of them is a file here, give up."""
    try:
        os.makedirs(path, exist_ok=True)
        return True
    except (FileExistsError, NotADirectoryError):
        return False


def bring(chosen, windows=False, progress=None, stop=None, home=None):
    """Copy the chosen kinds into the home folder. progress(done_bytes, file)
    is called now and then. Returns a Result."""
    home = home or backup_store.home()
    result = Result()
    kept = os.path.join(home, ".local", "share", "freemac-tender",
                        "replaced-" + time.strftime(backup_store.STAMP))
    last = 0.0
    for kind_info in chosen:
        settings = kind_info.get("settings")
        for src, dst in files(kind_info, windows):
            if stop and stop():
                result.stopped = True
                return result
            try:
                st = os.lstat(src)
            except OSError as e:
                result.failed.append((src, e.strerror or str(e)))
                continue
            if not (stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode)):
                continue
            if not _make_dirs(os.path.dirname(dst)):
                result.failed.append((src, "A file is in the way of its folder"))
                continue
            if os.path.lexists(dst):
                if stat.S_ISREG(st.st_mode) and _same(src, dst, st):
                    result.same += 1
                    continue
                if stat.S_ISLNK(st.st_mode) and os.path.islink(dst) and os.readlink(dst) == os.readlink(src):
                    result.same += 1
                    continue
                if settings:
                    backup = os.path.join(kept, os.path.relpath(dst, home))
                    if not _make_dirs(os.path.dirname(backup)):
                        result.failed.append((src, "The current setting couldn't be kept"))
                        continue
                    try:
                        os.replace(dst, backup)
                    except OSError as e:
                        result.failed.append((src, e.strerror or str(e)))
                        continue
                    result.replaced += 1
                    result.kept_in = kept
                else:
                    # Brought over before, beside one of the same name?
                    twin = _earlier_copy(src, dst, st)
                    if twin:
                        result.same += 1
                        continue
                    dst = free_name(dst)
                    result.renamed += 1
            try:
                if stat.S_ISLNK(st.st_mode):
                    os.symlink(os.readlink(src), dst)
                else:
                    shutil.copy2(src, dst)
                    result.bytes += st.st_size
                result.copied += 1
            except OSError as e:
                result.failed.append((src, e.strerror or str(e)))
                try:
                    if os.path.lexists(dst) and not os.path.isdir(dst):
                        os.remove(dst)
                except OSError:
                    pass
            now = time.monotonic()
            if progress and now - last > 0.1:
                last = now
                progress(result.bytes, src)
    if progress:
        progress(result.bytes, "")
    return result
