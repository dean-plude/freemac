# SPDX-License-Identifier: GPL-3.0-or-later
"""Disk images (.iso, .img): opening one as a disk, as a Mac opens a disk
image you double-click, and making one from a folder.

udisks2 attaches the file as a loop device (a disk whose contents are the
file) and mounts the file systems on it, so it shows on the Desktop and in
Drawer like a USB drive. Ejecting it unmounts it, and the loop device goes
away with it. An .iso, or a file this account can't write to, is opened
read-only; an .img that is yours opens so you can change it.

Original freemac code; no GTK here, so it can be tried from a terminal.
"""
import os
import subprocess
import time

from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.UDisks2"
ROOT = "/org/freedesktop/UDisks2"
MANAGER = "/org/freedesktop/UDisks2/Manager"
P = "org.freedesktop.UDisks2."
TYPES = (".iso", ".img", ".raw")
MIME_TYPES = ("application/x-cd-image", "application/x-iso9660-image", "application/x-raw-disk-image")
INTERACTIVE = Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION
# Folders an image is never made of: the whole system, or parts of it that
# aren't files at all.
SYSTEM_FOLDERS = ("/proc", "/sys", "/dev", "/run", "/boot", "/usr", "/etc", "/var", "/bin", "/sbin", "/lib")


class Failed(Exception):
    """Why an image couldn't be opened, in words for a person."""


def _bytes(value):
    return bytes(value).rstrip(b"\0").decode(errors="replace") if value else ""


def _bus(bus):
    return bus or Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def _objects(bus):
    reply = bus.call_sync(BUS_NAME, ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None,
                          GLib.VariantType.new("(a{oa{sa{sv}}})"), Gio.DBusCallFlags.NONE, 5000, None)
    return reply.unpack()[0]


def _call(bus, path, interface, method, args, reply_type=None, timeout=60000):
    return bus.call_sync(BUS_NAME, path, P + interface, method, args,
                         GLib.VariantType.new(reply_type) if reply_type else None, INTERACTIVE, timeout, None)


def _none():
    return GLib.Variant("(a{sv})", ({},))


def is_image(path):
    return bool(path) and path.lower().endswith(TYPES)


def opened(bus=None, objects=None):
    """{loop object path: the image file} for the images this account has open."""
    objects = objects if objects is not None else _objects(_bus(bus))
    found = {}
    for path, props in objects.items():
        loop = props.get(P + "Loop")
        if loop and loop.get("SetupByUID") == os.getuid():
            backing = _bytes(loop.get("BackingFile"))
            if backing:
                found[path] = backing
    return found


def volumes(loop, objects):
    """[(object path, label, mount points)] for the file systems on an image:
    the whole image, or each partition in it."""
    found = []
    for path, props in sorted(objects.items()):
        fs = props.get(P + "Filesystem")
        if fs is None:
            continue
        table = props.get(P + "Partition", {}).get("Table")
        if path == loop or table == loop:
            block = props.get(P + "Block", {})
            found.append((path, block.get("IdLabel", ""), [_bytes(m) for m in fs.get("MountPoints", [])]))
    return found


def read_only(path):
    return path.lower().endswith(".iso") or not os.access(path, os.W_OK)


def _words(error):
    remote = Gio.DBusError.get_remote_error(error) or ""
    Gio.DBusError.strip_remote_error(error)
    low = error.message.lower()
    if remote.endswith("NotAuthorized") or remote.endswith("NotAuthorizedCanObtain") or "not authorized" in low:
        return "You need to be an administrator to open disk images on this computer."
    if remote.endswith(".Cancelled") or "dismissed" in low:
        return None
    return error.message


def attach(path, bus=None):
    """The loop device for this image, set up now if it isn't already open.
    Raises Failed."""
    bus = _bus(bus)
    real = os.path.realpath(path)
    for loop, backing in opened(bus).items():
        if os.path.realpath(backing) == real:
            return loop
    ro = read_only(real)
    try:
        fd = os.open(real, os.O_RDONLY if ro else os.O_RDWR)
    except OSError as e:
        raise Failed(e.strerror or str(e))
    try:
        fds = Gio.UnixFDList.new()
        index = fds.append(fd)
        args = GLib.Variant("(ha{sv})", (index, {"read-only": GLib.Variant("b", ro)}))
        reply, _out = bus.call_with_unix_fd_list_sync(BUS_NAME, MANAGER, P + "Manager", "LoopSetup", args,
                                                      GLib.VariantType.new("(o)"), INTERACTIVE, 60000, fds, None)
    except GLib.Error as e:
        raise Failed(_words(e) or "")
    finally:
        os.close(fd)
    return reply.unpack()[0]


def mount(loop, bus=None, wait=6.0):
    """Mount every file system on the image (the Desktop may already have)
    and return where they are. When the image holds nothing freemac can read,
    it is closed again and Failed says so."""
    bus = _bus(bus)
    deadline = time.monotonic() + wait
    found = []
    while True:
        found = volumes(loop, _objects(bus))
        if found or time.monotonic() > deadline:
            break
        time.sleep(0.25)        # the kernel and udisks read the image's partitions
    if not found:
        detach(loop, bus)
        raise Failed("It has no files freemac can read. It may be damaged, or not be a disk image at all.")
    places, why = [], None
    for path, _label, mounts in found:
        if mounts:
            places.append(mounts[0])
            continue
        try:
            reply = _call(bus, path, "Filesystem", "Mount", _none(), "(s)")
            places.append(reply.unpack()[0])
        except GLib.Error as e:
            again = volumes(loop, _objects(bus))
            mounts = next((m for p, _l, m in again if p == path and m), None)
            if mounts:
                places.append(mounts[0])       # mounted by the Desktop meanwhile
            elif why is None:
                why = _words(e)
    if not places:
        detach(loop, bus)
        raise Failed(why or "Its disk couldn't be opened.")
    # Now that it's in use, it can go away by itself once it is ejected.
    try:
        _call(bus, loop, "Loop", "SetAutoclear", GLib.Variant("(ba{sv})", (True, {})))
    except GLib.Error:
        pass
    return places


def open_image(path, bus=None):
    """Attach and mount: the folders the image's disks are at."""
    bus = _bus(bus)
    return mount(attach(path, bus), bus)


def detach(loop, bus=None):
    """Unmount the image's disks and close it."""
    bus = _bus(bus)
    try:
        objects = _objects(bus)
    except GLib.Error:
        return
    for path, _label, mounts in volumes(loop, objects):
        if mounts:
            _call(bus, path, "Filesystem", "Unmount", _none())
    try:
        _call(bus, loop, "Loop", "Delete", _none())
    except GLib.Error as e:
        if not any(w in e.message for w in ("No such", "UnknownObject", "UnknownMethod")):
            raise


# ---- making one ---------------------------------------------------------------------

def folder_size(folder):
    total = 0
    for root, dirs, files in os.walk(folder):
        total += 4096 * (len(dirs) + 1)
        for name in files:
            try:
                total += max(4096, os.lstat(os.path.join(root, name)).st_size)
            except OSError:
                pass
    return total


def image_size(folder):
    """Room for the folder's files, the file system's own bookkeeping, and a
    little to spare, in whole megabytes."""
    want = int(folder_size(folder) * 1.2) + 16 * 1024 * 1024
    mb = 1024 * 1024
    return (want + mb - 1) // mb * mb


def label_for(name):
    """ext4 names are at most 16 bytes."""
    label = name.strip() or "Untitled"
    while len(label.encode()) > 16:
        label = label[:-1]
    return label


def make_from_folder(folder, image):
    """A disk image file holding a copy of the folder, readable by freemac
    and Linux (ext4). Raises Failed."""
    real = os.path.realpath(folder)
    if real == "/" or any(real == top or real.startswith(top + "/") for top in SYSTEM_FOLDERS):
        raise Failed("That folder belongs to the system. Choose one of your own folders, such as one in your Home folder.")
    if os.path.exists(image):
        raise Failed(f"“{os.path.basename(image)}” is already there.")
    size = image_size(folder)
    try:
        room = os.statvfs(os.path.dirname(os.path.abspath(image)))
        if size > room.f_bavail * room.f_frsize:
            raise Failed("There isn’t enough free space for it there. Save it somewhere with more room.")
    except OSError:
        pass
    try:
        with open(image, "wb") as f:
            f.truncate(size)
    except OSError as e:
        raise Failed(e.strerror or str(e))
    mkfs = next((p for p in ("/usr/sbin/mkfs.ext4", "/sbin/mkfs.ext4") if os.path.exists(p)), "mkfs.ext4")
    args = [mkfs, "-q", "-F", "-L", label_for(os.path.basename(folder.rstrip("/"))), "-d", folder,
            "-E", f"root_owner={os.getuid()}:{os.getgid()}", image]
    try:
        done = subprocess.run(args, capture_output=True, text=True, timeout=3600)
    except (OSError, subprocess.SubprocessError) as e:
        done = None
        reason = str(e)
    if done is None or done.returncode:
        try:
            os.unlink(image)
        except OSError:
            pass
        raise Failed((done.stderr.strip().splitlines() or [""])[-1] if done else reason)
    return image
