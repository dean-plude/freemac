# SPDX-License-Identifier: GPL-3.0-or-later
"""What is filling the disk, as a Mac's Storage settings show it: how much
apps, documents, pictures, music, films, downloads, the Trash and the
system itself take, how much is left, and the biggest files in your home
folder (Dials > Storage, dials_storage.py).

Sizes are what the files take on the disk, counted once even when a file is
reached twice, and in the units a Mac uses (1 GB is 1,000,000,000 bytes).
Applications are the packages that put an app in the app grid, at the size
the package manager gives, plus any Flatpak apps. "System" is the rest of
what's in use, and never less than freemac's own packages. This module imports
no GTK, so it can be measured on a thread. Original freemac code.
"""
import os
import stat

HOME = os.path.expanduser("~")
TRASH = os.path.join(HOME, ".local", "share", "Trash")
DPKG_STATUS = "/var/lib/dpkg/status"
DPKG_INFO = "/var/lib/dpkg/info"
FLATPAK = ("/var/lib/flatpak", os.path.join(HOME, ".local", "share", "flatpak"))

# key: (title, colour, folders under home). In the order the bar shows them.
CATEGORIES = (
    ("apps", "Applications", "#3b82f6", ()),
    ("documents", "Documents", "#f59e0b", ("Documents", "Desktop")),
    ("pictures", "Pictures", "#ec4899", ("Pictures",)),
    ("music", "Music", "#ef4444", ("Music",)),
    ("movies", "Movies", "#8b5cf6", ("Videos",)),
    ("downloads", "Downloads", "#14b8a6", ("Downloads",)),
    ("trash", "Trash", "#78716c", ()),
    ("system", "System", "#9ca3af", ()),
)
TITLES = {key: title for key, title, _c, _f in CATEGORIES}
COLOURS = {key: colour for key, _t, colour, _f in CATEGORIES}
LARGE = 50 * 1000 * 1000   # Review Files lists files at least this big


def human(size):
    """"12.4 GB", "512 MB", "3 KB", "Zero KB", as Finder writes sizes."""
    if size <= 0:
        return "Zero KB"
    for unit, scale in (("TB", 1e12), ("GB", 1e9), ("MB", 1e6)):
        if size >= scale:
            value = size / scale
            return f"{value:.1f} {unit}" if value < 100 else f"{value:.0f} {unit}"
    return f"{max(1, round(size / 1e3))} KB"


def folder_size(path, seen=None, device=None):
    """Bytes a folder takes on the disk: every file under it, on the same
    disk, without following links, counting hard links once."""
    seen = set() if seen is None else seen
    total = 0
    try:
        top = os.lstat(path)
    except OSError:
        return 0
    device = top.st_dev if device is None else device
    stack = [path]
    while stack:
        folder = stack.pop()
        try:
            entries = os.scandir(folder)
        except OSError:
            continue
        with entries:
            for entry in entries:
                try:
                    info = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if info.st_dev != device:
                    continue
                if stat.S_ISDIR(info.st_mode):
                    stack.append(entry.path)
                    continue
                key = (info.st_dev, info.st_ino)
                if info.st_nlink > 1:
                    if key in seen:
                        continue
                    seen.add(key)
                total += info.st_blocks * 512
    return total


def packages(status=DPKG_STATUS):
    """{package: bytes} of the installed packages, by their Installed-Size."""
    sizes, name, installed, size = {}, None, False, 0
    try:
        with open(status, errors="replace") as f:
            lines = f.read().splitlines() + [""]
    except OSError:
        return {}
    for line in lines:
        if line.startswith("Package:"):
            name = line.split(":", 1)[1].strip()
        elif line.startswith("Status:"):
            installed = line.split()[-1] == "installed"
        elif line.startswith("Installed-Size:"):
            try:
                size = int(line.split(":", 1)[1]) * 1024
            except ValueError:
                size = 0
        elif not line.strip():
            if name and installed:
                sizes[name] = size
            name, installed, size = None, False, 0
    return sizes


def app_packages(info=DPKG_INFO):
    """Names of the packages that put an app in the app grid: those whose
    file list has a .desktop file in /usr/share/applications."""
    found = set()
    try:
        lists = [n for n in os.listdir(info) if n.endswith(".list")]
    except OSError:
        return found
    for entry in lists:
        try:
            with open(os.path.join(info, entry), errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        if "/usr/share/applications/" in text and ".desktop\n" in text:
            found.add(entry[:-5].split(":")[0])
    return found


def disk(path=HOME):
    """(total, free) bytes of the disk the home folder is on."""
    try:
        info = os.statvfs(path)
    except OSError:
        return 0, 0
    return info.f_blocks * info.f_frsize, info.f_bavail * info.f_frsize


def measure(home=HOME):
    """{"total", "free", "used", "sizes": {category: bytes}} for the disk
    the home folder is on."""
    total, free = disk(home)
    # The root's reserved blocks aren't free to you, nor counted as used.
    used = max(0, total - free)
    sizes = {}
    seen = set()
    for key, _title, _colour, folders in CATEGORIES:
        if folders:
            sizes[key] = sum(folder_size(os.path.join(home, name), seen) for name in folders)
    sizes["trash"] = folder_size(os.path.join(home, ".local", "share", "Trash", "files"), seen)
    installed = packages()
    with_apps = app_packages()
    apps = sum(size for name, size in installed.items() if name in with_apps)
    for place in FLATPAK:
        if os.path.isdir(place):
            apps += folder_size(place, seen)
    sizes["apps"] = apps
    counted = sum(sizes.values())
    # The system is freemac itself and what it keeps (logs, caches, other
    # people's folders): the rest of what's used, and at least its own
    # packages, which on the live system sit on the USB stick, not this disk.
    own = sum(size for name, size in installed.items() if name not in with_apps)
    sizes["system"] = max(used - counted, own)
    used = max(used, counted + sizes["system"])
    return {"total": max(total, used + free), "free": free, "used": used, "sizes": sizes}


def large_files(home=HOME, minimum=LARGE, limit=200):
    """[(bytes, modified, path)] of the biggest files in the home folder,
    biggest first: not in hidden folders (apps' own data) or the Trash."""
    found = []
    stack = [home]
    while stack:
        folder = stack.pop()
        try:
            entries = os.scandir(folder)
        except OSError:
            continue
        with entries:
            for entry in entries:
                if entry.name.startswith("."):
                    continue
                try:
                    info = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISDIR(info.st_mode):
                    stack.append(entry.path)
                elif stat.S_ISREG(info.st_mode) and info.st_size >= minimum:
                    found.append((info.st_size, info.st_mtime, entry.path))
    found.sort(reverse=True)
    return found[:limit]
