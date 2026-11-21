# SPDX-License-Identifier: GPL-3.0-or-later
"""Lifeboat's backups, with no GTK, so the watcher, Dials and the Lifeboat
window share one way of reading and making them.

Each backup is a whole copy of the home folder in its own dated folder on
the drive, under freemac-backups/<computer>-<user>/2026-11-21-153000. A
file that hasn't changed since the backup before is a hard link to the copy
already there, so it takes no more room: an hourly backup costs only what
changed. A backup is made in a folder ending in .inprogress and renamed
when it's whole, so a half-made one is never shown or linked to.

Old backups thin out the way a Mac's do: every backup of the last day, the
last one of each day for a month, and one a week before that. When the
drive is full, the oldest go first; the newest is always kept.

Original freemac code.
"""
import getpass
import json
import os
import shutil
import socket
import stat
import time

TOP = "freemac-backups"
STAMP = "%Y-%m-%d-%H%M%S"
WORKING = ".inprogress"
EVERY = 3600                 # seconds between automatic backups
ROOM = 200 * 1024 * 1024     # free space always left on the drive
CHUNK = 1024 * 1024

# Folders inside home that are never backed up: caches and the Trash can
# be made again, and a backup of the backups would never end.
SKIP = (".cache", ".local/share/Trash", ".thumbnails", ".local/share/gvfs-metadata",
        ".var/app/*/cache", "snap/*/*/.cache")


class NoRoom(Exception):
    """The drive is full even after the oldest backups went."""


class Stopped(Exception):
    pass


def home():
    return os.path.expanduser("~")


def _config_dir():
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(home(), ".config"), "freemac")


def _cache_dir():
    return os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(home(), ".cache"), "freemac")


def _read(path, empty):
    try:
        with open(path) as f:
            data = json.load(f)
        return data if isinstance(data, type(empty)) else empty
    except (OSError, ValueError):
        return empty


def _write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, path)


# -- settings: which drive, and whether to back up by itself ---------------

def settings_path():
    return os.path.join(_config_dir(), "lifeboat.json")


def settings():
    found = _read(settings_path(), {})
    found.setdefault("drive", None)     # the drive's uuid (or its path when it has none)
    found.setdefault("name", "")
    found.setdefault("auto", True)
    return found


def save_settings(**changes):
    found = settings()
    found.update(changes)
    _write(settings_path(), found)
    return found


# -- what the watcher is doing, for Dials and the window -------------------

def status_path():
    return os.path.join(_cache_dir(), "lifeboat-status.json")


def status():
    return _read(status_path(), {})


def save_status(**changes):
    found = status()
    found.update(changes)
    found["at"] = time.time()
    _write(status_path(), found)
    return found


# -- the backups on a drive ---------------------------------------------------

def machine():
    host = socket.gethostname() or "computer"
    try:
        user = getpass.getuser()
    except (KeyError, OSError):
        user = str(os.getuid())
    return f"{host}-{user}"


def folder_on(root):
    """Where this computer's backups go on the drive mounted at root."""
    return os.path.join(root, TOP, machine())


def stamp_time(name):
    try:
        return time.mktime(time.strptime(name, STAMP))
    except (ValueError, OverflowError):
        return None


def backups(root):
    """The whole backups on the drive, oldest first, as (time, path)."""
    base = folder_on(root)
    try:
        names = os.listdir(base)
    except OSError:
        return []
    found = []
    for name in names:
        when = stamp_time(name)
        if when is not None and os.path.isdir(os.path.join(base, name)):
            found.append((when, os.path.join(base, name)))
    return sorted(found)


def latest(root):
    found = backups(root)
    return found[-1] if found else None


def can_link(root):
    """True when the drive can hold hard links (ext4, btrfs, NTFS...), which
    backups need; FAT and exFAT drives can't."""
    test = os.path.join(root, TOP, ".link-test")
    try:
        os.makedirs(os.path.dirname(test), exist_ok=True)
        with open(test, "w") as f:
            f.write("x")
        os.link(test, test + "2")
        ok = os.stat(test).st_nlink == 2
    except OSError:
        ok = False
    for path in (test, test + "2"):
        try:
            os.unlink(path)
        except OSError:
            pass
    return ok


def free(root):
    try:
        found = os.statvfs(root)
    except OSError:
        return 0
    return found.f_bavail * found.f_frsize


def _skipped(rel):
    from fnmatch import fnmatch
    for pattern in SKIP:
        if rel == pattern or fnmatch(rel, pattern) or rel.startswith(pattern + "/"):
            return True
    return False


def _same(st, old):
    return (old is not None and stat.S_ISREG(old.st_mode) and old.st_size == st.st_size
            and abs(old.st_mtime - st.st_mtime) < 1)


def _copy(src, dst, st, stop, room):
    with open(src, "rb") as fin, open(dst, "wb") as fout:
        while True:
            if stop is not None and stop.is_set():
                raise Stopped()
            chunk = fin.read(CHUNK)
            if not chunk:
                break
            room(len(chunk))
            fout.write(chunk)
    os.chmod(dst, stat.S_IMODE(st.st_mode))
    os.utime(dst, ns=(st.st_atime_ns, st.st_mtime_ns))


def back_up(root, progress=None, stop=None, source=None):
    """Make one backup of the home folder (or source) on the drive at root.

    progress(files, copied_bytes, rel) is called now and then from this
    thread. stop is a threading.Event. Returns a summary dict; raises
    NoRoom, Stopped or OSError."""
    source = source or home()
    base = folder_on(root)
    os.makedirs(base, exist_ok=True)
    for name in os.listdir(base):
        if name.endswith(WORKING):
            shutil.rmtree(os.path.join(base, name), ignore_errors=True)
    before = latest(root)
    previous = before[1] if before else None
    name = time.strftime(STAMP)
    while os.path.exists(os.path.join(base, name)):
        time.sleep(1)
        name = time.strftime(STAMP)
    work = os.path.join(base, name + WORKING)
    os.makedirs(work)
    drive_root = os.path.realpath(root)
    summary = {"files": 0, "copied": 0, "linked": 0, "bytes": 0, "errors": []}
    told = [0.0]

    def room(size):
        if free(root) - size >= ROOM:
            return
        make_room(root, size + ROOM, keep=previous)
        if free(root) - size < ROOM:
            raise NoRoom()

    def tell(rel):
        now = time.monotonic()
        if progress is not None and now - told[0] > 0.25:
            told[0] = now
            progress(summary["files"], summary["bytes"], rel)

    folders = []
    for here, dirs, files in os.walk(source, onerror=None):
        if stop is not None and stop.is_set():
            raise Stopped()
        rel_here = os.path.relpath(here, source)
        rel_here = "" if rel_here == "." else rel_here
        keep = []
        for d in dirs:
            rel = os.path.join(rel_here, d)
            full = os.path.join(here, d)
            if _skipped(rel) or os.path.realpath(full) == drive_root:
                continue
            if os.path.islink(full):
                files.append(d)      # copied as the link it is
                continue
            keep.append(d)
        dirs[:] = keep
        target = os.path.join(work, rel_here)
        if rel_here:
            try:
                os.makedirs(target, exist_ok=True)
                folders.append((here, target))
            except OSError as error:
                summary["errors"].append((rel_here, error.strerror or str(error)))
                dirs[:] = []
                continue
        for f in files:
            rel = os.path.join(rel_here, f)
            if _skipped(rel):
                continue
            src, dst = os.path.join(here, f), os.path.join(target, f)
            try:
                st = os.lstat(src)
                if stat.S_ISLNK(st.st_mode):
                    os.symlink(os.readlink(src), dst)
                elif stat.S_ISREG(st.st_mode):
                    old_path = os.path.join(previous, rel) if previous else None
                    try:
                        old = os.lstat(old_path) if old_path else None
                    except OSError:
                        old = None
                    linked = False
                    if _same(st, old):
                        try:
                            os.link(old_path, dst)
                            linked = True
                        except OSError:
                            linked = False
                    if linked:
                        summary["linked"] += 1
                    else:
                        _copy(src, dst, st, stop, room)
                        summary["copied"] += 1
                        summary["bytes"] += st.st_size
                else:
                    continue         # sockets, pipes and devices aren't files to keep
                summary["files"] += 1
            except (NoRoom, Stopped):
                raise
            except OSError as error:
                if len(summary["errors"]) < 200:
                    summary["errors"].append((rel, error.strerror or str(error)))
            tell(rel)
    for here, target in reversed(folders):
        try:
            st = os.stat(here)
            os.chmod(target, stat.S_IMODE(st.st_mode))
            os.utime(target, ns=(st.st_atime_ns, st.st_mtime_ns))
        except OSError:
            pass
    final = os.path.join(base, name)
    os.rename(work, final)
    summary["path"] = final
    summary["time"] = stamp_time(name)
    thin(root)
    return summary


def thin(root, now=None):
    """Take away backups no longer kept: after a day, all but each day's
    last; after a month, all but each week's last. Returns what went."""
    now = now or time.time()
    found = backups(root)
    if len(found) < 2:
        return []
    keep, seen_days, seen_weeks = set(), set(), set()
    for when, path in reversed(found):
        age = now - when
        if age < 86400:
            keep.add(path)
            continue
        day = time.strftime("%Y-%m-%d", time.localtime(when))
        week = time.strftime("%G-%V", time.localtime(when))
        if age < 31 * 86400:
            if day not in seen_days:
                seen_days.add(day)
                keep.add(path)
        elif week not in seen_weeks:
            seen_weeks.add(week)
            keep.add(path)
    keep.add(found[-1][1])
    gone = [path for _when, path in found if path not in keep]
    for path in gone:
        remove(path)
    return gone


def make_room(root, need, keep=None):
    """Take away the oldest backups until need bytes are free, never the
    newest one nor keep."""
    found = backups(root)
    for _when, path in found[:-1]:
        if free(root) >= need:
            return
        if path != keep:
            remove(path)


def remove(path):
    # Backups are made read-only by nobody, but a folder copied from a
    # read-only one is; give write back so its files can go.
    def unlock(func, failed, _info):
        try:
            os.chmod(os.path.dirname(failed), 0o700)
            func(failed)
        except OSError:
            pass
    shutil.rmtree(path, onerror=unlock)


def describe(when, now=None):
    """'Today, 3:14 PM', 'Yesterday, 9:02 AM' or 'Friday 14 November, 6:00 PM'."""
    now = now or time.time()
    t = time.localtime(when)
    clock = time.strftime("%I:%M %p", t).lstrip("0")
    today = time.localtime(now)
    days = (time.mktime(today[:3] + (0, 0, 0, 0, 0, -1)) - time.mktime(t[:3] + (0, 0, 0, 0, 0, -1))) / 86400
    if round(days) == 0:
        return f"Today, {clock}"
    if round(days) == 1:
        return f"Yesterday, {clock}"
    day = time.strftime("%A %d %B", t).replace(" 0", " ")
    if t.tm_year != today.tm_year:
        day += time.strftime(" %Y", t)
    return f"{day}, {clock}"


def size_words(n):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1000
    return ""


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("usage: python3 -m freemac_shell.backup_store DRIVE [SOURCE]")
        sys.exit(2)
    start = time.time()
    result = back_up(sys.argv[1], source=sys.argv[2] if len(sys.argv) > 2 else None,
                     progress=lambda n, b, rel: None)
    print(json.dumps({k: v for k, v in result.items() if k != "errors"}), len(result["errors"]), "errors",
          f"{time.time() - start:.1f}s")
