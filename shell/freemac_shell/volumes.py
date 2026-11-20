# SPDX-License-Identifier: GPL-3.0-or-later
"""USB drives, memory cards, discs and phones: the disks that come and go.

Backdrop mounts each one as it is plugged in (and shows it on the Desktop),
Drawer lists them under Locations with an Eject button, and both eject them
the same way, with the same alert when a disk is still in use. GIO and
udisks2 do the work; gvfs adds phones and cameras. Original freemac code.
"""
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

# Disks the system keeps for itself, never shown as drives.
SYSTEM = ("/", "/boot", "/boot/efi", "/efi", "/home", "/usr", "/var", "/run/live/medium")
SCHEMES = ("file", "mtp", "gphoto2", "afc")


_monitor = None


def monitor():
    # Kept here: GIO drops the monitor, and every signal on it, once no one holds it.
    global _monitor
    if _monitor is None:
        _monitor = Gio.VolumeMonitor.get()
    return _monitor


def is_drive(mount):
    """True for a disk worth showing: not the system's own, not hidden."""
    if mount.is_shadowed():
        return False
    root = mount.get_root()
    if root.get_uri_scheme() not in SCHEMES:
        return False
    path = root.get_path()
    if path and (path in SYSTEM or path.startswith("/snap/") or path.startswith("/boot/")):
        return False
    volume = mount.get_volume()
    drive = mount.get_drive()
    if volume is None and drive is None and root.get_uri_scheme() == "file":
        return False   # a bind or network mount the system made, not a disk
    return True


def drives():
    """The mounted drives, in the order they came."""
    return [m for m in monitor().get_mounts() if is_drive(m)]


def path_of(mount):
    """Where the drive's files are; for a phone, the gvfs folder if there is one."""
    return mount.get_root().get_path()


def key_of(mount):
    return mount.get_root().get_uri()


def mount_of(path):
    """The drive that holds this path, or None."""
    if not path:
        return None
    best = None
    for mount in drives():
        root = path_of(mount)
        if root and (path == root or path.startswith(root.rstrip("/") + "/")):
            if best is None or len(root) > len(path_of(best)):
                best = mount
    return best


def mount_new(parent=None):
    """Mount every plugged-in disk that should mount by itself and hasn't yet."""
    for volume in monitor().get_volumes():
        mount_volume(volume, parent)


def mount_volume(volume, parent=None):
    if volume.get_mount() is not None or not volume.should_automount() or not volume.can_mount():
        return
    operation = Gtk.MountOperation(parent=parent)
    volume.mount(Gio.MountMountFlags.NONE, operation, None, _mounted, None)


def _mounted(volume, result, _data):
    try:
        volume.mount_finish(result)
    except GLib.Error:
        pass


def eject(mount, parent=None, done=None):
    """Eject the drive (or unmount it when it can't be ejected). On failure,
    an alert says why, the way a Mac does."""
    name, icon = mount.get_name(), mount.get_icon()
    operation = Gtk.MountOperation(parent=parent)

    def finished(source, result, _data):
        try:
            (source.eject_with_operation_finish if ejecting else source.unmount_with_operation_finish)(result)
        except GLib.Error as error:
            if not error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.FAILED_HANDLED):
                _tell_failed(parent, name, icon, error)
            if done:
                done(False)
            return
        if done:
            done(True)

    ejecting = mount.can_eject()
    if ejecting:
        mount.eject_with_operation(Gio.MountUnmountFlags.NONE, operation, None, finished, None)
    elif mount.can_unmount():
        mount.unmount_with_operation(Gio.MountUnmountFlags.NONE, operation, None, finished, None)
    elif done:
        done(False)


def _tell_failed(parent, name, icon, error):
    from . import alert
    busy = error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.BUSY) or "busy" in error.message.lower()
    if busy:
        text = "One or more apps may be using it. Quit them, or close their files on the disk, and try again."
    else:
        text = error.message
    alert.tell(parent, f"The disk “{name}” wasn’t ejected.", text, icon=icon)


def watch(callback):
    """Call callback() whenever a drive comes or goes. Returns the handler ids."""
    vm = monitor()
    return [vm.connect(signal, lambda *_: callback()) for signal in
            ("mount-added", "mount-removed", "mount-changed")]
