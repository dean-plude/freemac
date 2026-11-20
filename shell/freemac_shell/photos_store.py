# SPDX-License-Identifier: GPL-3.0-or-later
"""Cove's library: the photos in the Pictures folder, their dates, small
copies and favourites, and importing from cameras and phones. No GTK, so
it can be tried without a screen.

A photo's date is when it was taken, read from the picture's own EXIF data
(JPEG and TIFF), or else the file's date. What was learned about each file
is kept in ~/.cache/freemac/photos.json so the next start is quick. Small
copies follow the freedesktop.org thumbnail rules (~/.cache/thumbnails), so
other apps can use them too. Favourites, albums and what was imported from
which device are in ~/.local/share/freemac/photos.json; an album is a name
and a list of photos, so a photo can be in many albums and is never copied.
Original freemac code.
"""
import hashlib
import json
import os
import struct
import time
import uuid

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gio, GLib  # noqa: E402

PICTURE_ENDINGS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif", ".tif", ".tiff", ".bmp"}
THUMB = 256          # the "large" size of the thumbnail rules
RECENT_DAYS = 30


def library_dir():
    return GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) or os.path.expanduser("~/Pictures")


def _cache_path():
    return os.path.join(GLib.get_user_cache_dir(), "freemac", "photos.json")


def _data_path():
    return os.path.join(GLib.get_user_data_dir(), "freemac", "photos.json")


def _read_json(path, empty):
    try:
        with open(path, encoding="utf-8") as f:
            found = json.load(f)
        return found if isinstance(found, type(empty)) else empty
    except (OSError, ValueError):
        return empty


def _write_json(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    new = path + ".new"
    with open(new, "w", encoding="utf-8") as f:
        json.dump(value, f)
    os.replace(new, path)


def is_picture(name):
    return os.path.splitext(name)[1].lower() in PICTURE_ENDINGS and not name.startswith(".")


# -- dates from EXIF ----------------------------------------------------------

def _exif_dates(tiff):
    """The DateTimeOriginal (or DateTime) in a TIFF-shaped EXIF block."""
    if len(tiff) < 8 or tiff[:2] not in (b"II", b"MM"):
        return None
    order = "<" if tiff[:2] == b"II" else ">"

    def ifd(offset):
        entries = {}
        if offset + 2 > len(tiff):
            return entries
        count = struct.unpack_from(order + "H", tiff, offset)[0]
        for n in range(min(count, 512)):
            at = offset + 2 + n * 12
            if at + 12 > len(tiff):
                break
            tag, kind, number = struct.unpack_from(order + "HHI", tiff, at)
            if kind == 2:   # text
                start = at + 8 if number <= 4 else struct.unpack_from(order + "I", tiff, at + 8)[0]
                entries[tag] = tiff[start:start + number].split(b"\0")[0].decode("ascii", "replace")
            elif kind == 4:  # a 32-bit number (offsets to other blocks)
                entries[tag] = struct.unpack_from(order + "I", tiff, at + 8)[0]
        return entries

    first = ifd(struct.unpack_from(order + "I", tiff, 4)[0])
    text = None
    if isinstance(first.get(0x8769), int):
        text = ifd(first[0x8769]).get(0x9003)
    text = text or first.get(0x0132)
    if not isinstance(text, str):
        return None
    try:
        return time.mktime(time.strptime(text.strip()[:19], "%Y:%m:%d %H:%M:%S"))
    except (ValueError, OverflowError):
        return None


def taken_date(path):
    """When the photo was taken, from its EXIF data, or None."""
    try:
        with open(path, "rb") as f:
            head = f.read(2)
            if head in (b"II", b"MM"):
                return _exif_dates(head + f.read(256 * 1024))
            if head != b"\xff\xd8":
                return None
            while True:
                marker = f.read(2)
                if len(marker) < 2 or marker[0] != 0xFF or marker[1] in (0xD9, 0xDA):
                    return None
                size = struct.unpack(">H", f.read(2))[0]
                if marker[1] == 0xE1:
                    block = f.read(size - 2)
                    if block.startswith(b"Exif\0\0"):
                        return _exif_dates(block[6:])
                else:
                    f.seek(size - 2, 1)
    except (OSError, struct.error):
        return None


# -- the library --------------------------------------------------------------

class Photo:
    __slots__ = ("path", "taken", "mtime", "size", "added")

    def __init__(self, path, taken, mtime, size, added):
        self.path, self.taken, self.mtime, self.size, self.added = path, taken, mtime, size, added

    @property
    def name(self):
        return os.path.basename(self.path)

    def month(self):
        return time.strftime("%Y-%m", time.localtime(self.taken))


def scan():
    """Every photo in the Pictures folder (and its folders), newest first."""
    known = _read_json(_cache_path(), {})
    seen, photos = {}, []
    now = time.time()
    first_time = not known
    for folder, dirs, files in os.walk(library_dir()):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in files:
            if not is_picture(name):
                continue
            path = os.path.join(folder, name)
            try:
                info = os.stat(path)
            except OSError:
                continue
            old = known.get(path)
            if old and old.get("m") == info.st_mtime and old.get("s") == info.st_size:
                entry = old
            else:
                taken = taken_date(path) or info.st_mtime
                added = old.get("a") if old else (info.st_mtime if first_time else now)
                entry = {"m": info.st_mtime, "s": info.st_size, "t": taken, "a": added}
            seen[path] = entry
            photos.append(Photo(path, entry["t"], entry["m"], entry["s"], entry["a"]))
    if seen != known:
        try:
            _write_json(_cache_path(), seen)
        except OSError:
            pass
    photos.sort(key=lambda p: (p.taken, p.path), reverse=True)
    return photos


def recently_added(photos, days=RECENT_DAYS):
    since = time.time() - days * 86400
    return sorted((p for p in photos if p.added >= since), key=lambda p: p.added, reverse=True)


# -- favourites and import records -------------------------------------------

def _data():
    found = _read_json(_data_path(), {})
    found.setdefault("favourites", [])
    found.setdefault("imported", {})
    found.setdefault("albums", [])
    return found


def favourites():
    return set(_data()["favourites"])


def set_favourite(path, on):
    data = _data()
    marks = set(data["favourites"])
    (marks.add if on else marks.discard)(path)
    data["favourites"] = sorted(marks)
    _write_json(_data_path(), data)


def forget(path):
    """A photo went to the Trash: drop its favourite mark and take it out
    of every album."""
    data = _data()
    changed = False
    if path in data["favourites"]:
        data["favourites"].remove(path)
        changed = True
    for album in data["albums"]:
        if path in album.get("paths", []):
            album["paths"].remove(path)
            changed = True
    if changed:
        _write_json(_data_path(), data)


# -- albums -------------------------------------------------------------------

class Album:
    def __init__(self, ident, name, paths):
        self.id, self.name, self.paths = ident, name, list(paths)

    def __repr__(self):
        return f"Album({self.name!r}, {len(self.paths)} photos)"


def albums():
    """Every album, in the order they were made."""
    return [Album(a.get("id", ""), a.get("name", "Album"), a.get("paths", []))
            for a in _data()["albums"] if isinstance(a, dict) and a.get("id")]


def album(ident):
    return next((a for a in albums() if a.id == ident), None)


def free_album_name(name="Untitled Album"):
    taken = {a.name.lower() for a in albums()}
    if name.lower() not in taken:
        return name
    n = 2
    while f"{name} {n}".lower() in taken:
        n += 1
    return f"{name} {n}"


def _change_album(ident, change):
    data = _data()
    for entry in data["albums"]:
        if entry.get("id") == ident:
            change(entry)
            _write_json(_data_path(), data)
            return True
    return False


def new_album(name=None, paths=()):
    """Make an album (with these photos in it); returns its id."""
    data = _data()
    ident = uuid.uuid4().hex[:12]
    name = (name or "").strip() or free_album_name()
    seen = []
    for path in paths:
        if path not in seen:
            seen.append(path)
    data["albums"].append({"id": ident, "name": name, "paths": seen})
    _write_json(_data_path(), data)
    return ident


def rename_album(ident, name):
    name = name.strip()
    return bool(name) and _change_album(ident, lambda e: e.__setitem__("name", name))


def delete_album(ident):
    """The album goes; its photos stay in the library."""
    data = _data()
    data["albums"] = [a for a in data["albums"] if a.get("id") != ident]
    _write_json(_data_path(), data)


def add_to_album(ident, paths):
    """Add photos at the end of an album; returns how many were new to it."""
    added = []

    def change(entry):
        have = entry.setdefault("paths", [])
        for path in paths:
            if path not in have and path not in added:
                added.append(path)
        have.extend(added)
    _change_album(ident, change)
    return len(added)


def remove_from_album(ident, paths):
    gone = set(paths)
    return _change_album(ident, lambda e: e.__setitem__("paths", [p for p in e.get("paths", []) if p not in gone]))


# -- small copies ------------------------------------------------------------

def thumbnail_path(path):
    uri = Gio.File.new_for_path(path).get_uri()
    return os.path.join(GLib.get_user_cache_dir(), "thumbnails", "large",
                        hashlib.md5(uri.encode()).hexdigest() + ".png")


def thumbnail(path, mtime):
    """A small copy of the photo (made now if missing or old), as a pixbuf,
    or None when the picture can't be read."""
    small = thumbnail_path(path)
    try:
        found = GdkPixbuf.Pixbuf.new_from_file(small)
        if found.get_option("tEXt::Thumb::MTime") == str(int(mtime)):
            return found
    except GLib.Error:
        pass
    try:
        picture = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, THUMB, THUMB, True)
    except GLib.Error:
        return None
    picture = picture.apply_embedded_orientation() or picture
    try:
        os.makedirs(os.path.dirname(small), mode=0o700, exist_ok=True)
        picture.savev(small + ".new", "png", ["tEXt::Thumb::URI", "tEXt::Thumb::MTime"],
                      [Gio.File.new_for_path(path).get_uri(), str(int(mtime))])
        os.replace(small + ".new", small)
    except (GLib.Error, OSError):
        pass
    return picture


def full_picture(path, width, height):
    """The photo scaled to fit width x height, turned the right way up."""
    picture = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, width, height, True)
    picture = picture.apply_embedded_orientation() or picture
    if picture.get_width() > width or picture.get_height() > height:   # turned on its side
        scale = min(width / picture.get_width(), height / picture.get_height())
        picture = picture.scale_simple(max(1, int(picture.get_width() * scale)),
                                       max(1, int(picture.get_height() * scale)),
                                       GdkPixbuf.InterpType.BILINEAR)
    return picture


def picture_size(path):
    info = GdkPixbuf.Pixbuf.get_file_info(path)
    return (info[1], info[2]) if info and info[0] else (0, 0)


# -- cameras and phones --------------------------------------------------------

class Device:
    """A camera, phone or memory card with a DCIM folder."""

    def __init__(self, mount, dcim):
        self.mount, self.dcim = mount, dcim
        self.name = mount.get_name()
        self.key = mount.get_root().get_uri()

    def icon(self):
        return self.mount.get_symbolic_icon()


def _dcim_in(folder):
    child = folder.get_child("DCIM")
    try:
        if child.query_file_type(Gio.FileQueryInfoFlags.NONE, None) == Gio.FileType.DIRECTORY:
            return child
    except GLib.Error:
        pass
    return None


def devices():
    """Mounted cameras, phones and cards. A phone keeps DCIM one folder down
    (in its storage), a camera or card at the top."""
    found = []
    for mount in Gio.VolumeMonitor.get().get_mounts():
        root = mount.get_root()
        dcim = _dcim_in(root)
        if dcim is None and root.get_uri_scheme() in ("mtp", "gphoto2", "afc"):
            try:
                for info in root.enumerate_children("standard::name,standard::type", 0, None):
                    if info.get_file_type() == Gio.FileType.DIRECTORY:
                        dcim = _dcim_in(root.get_child(info.get_name()))
                        if dcim:
                            break
            except GLib.Error:
                pass
        if dcim is not None:
            found.append(Device(mount, dcim))
    return found


class DeviceItem:
    __slots__ = ("file", "name", "size", "mtime")

    def __init__(self, file, name, size, mtime):
        self.file, self.name, self.size, self.mtime = file, name, size, mtime

    def key(self):
        return f"{self.name}:{self.size}"


def device_items(device):
    """The pictures on a device, newest first. Can take a while on a phone."""
    items, folders = [], [device.dcim]
    attrs = "standard::name,standard::type,standard::size,time::modified"
    while folders:
        folder = folders.pop()
        try:
            children = list(folder.enumerate_children(attrs, Gio.FileQueryInfoFlags.NONE, None))
        except GLib.Error:
            continue
        for info in children:
            name = info.get_name()
            if info.get_file_type() == Gio.FileType.DIRECTORY:
                if not name.startswith("."):
                    folders.append(folder.get_child(name))
            elif is_picture(name):
                items.append(DeviceItem(folder.get_child(name), name, info.get_size(),
                                        info.get_attribute_uint64("time::modified")))
    items.sort(key=lambda i: (i.mtime, i.name), reverse=True)
    return items


def device_thumbnail(item):
    try:
        stream = item.file.read(None)
        try:
            picture = GdkPixbuf.Pixbuf.new_from_stream_at_scale(stream, THUMB, THUMB, True, None)
        finally:
            stream.close(None)
    except GLib.Error:
        return None
    return picture.apply_embedded_orientation() or picture


def already_imported(device):
    return set(_data()["imported"].get(device.key, []))


def _free_name(folder, name):
    stem, ending = os.path.splitext(name)
    path, n = os.path.join(folder, name), 2
    while os.path.exists(path):
        path = os.path.join(folder, f"{stem} {n}{ending}")
        n += 1
    return path


def import_items(device, items, progress=None):
    """Copy items into Pictures/<year>/<year-month-day>/, by the day each was
    taken. Returns the new paths. progress(done, total) is called as it goes."""
    done, made = 0, []
    os.makedirs(library_dir(), exist_ok=True)
    for item in items:
        # Copied in under a hidden name first, so the photo's own date (not
        # the device's file date, which copying can change) picks its folder.
        landing = os.path.join(library_dir(), ".cove-import-" + item.name)
        try:
            item.file.copy(Gio.File.new_for_path(landing),
                           Gio.FileCopyFlags.OVERWRITE | Gio.FileCopyFlags.TARGET_DEFAULT_PERMS, None, None, None)
        except GLib.Error:
            continue
        taken = taken_date(landing) or item.mtime or time.time()
        when = time.localtime(taken)
        folder = os.path.join(library_dir(), time.strftime("%Y", when), time.strftime("%Y-%m-%d", when))
        try:
            os.makedirs(folder, exist_ok=True)
            target = _free_name(folder, item.name)
            os.replace(landing, target)
            os.utime(target, (taken, taken))   # the file's own date, so other apps sort it right too
        except OSError:
            continue
        made.append(target)
        data = _data()   # each one recorded at once, so stopping halfway loses nothing
        data["imported"].setdefault(device.key, [])
        if item.key() not in data["imported"][device.key]:
            data["imported"][device.key].append(item.key())
        _write_json(_data_path(), data)
        done += 1
        if progress:
            progress(done, len(items))
    return made

