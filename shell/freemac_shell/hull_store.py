# SPDX-License-Identifier: GPL-3.0-or-later
"""The drives Hull shows, read from udisks2, and what it does to them.

A Drive is a physical disk (or a memory card reader's card, or a disc);
its volumes are the file systems on it, one per partition or one for the
whole disk. Space used comes from the file system itself while it's
mounted. Everything that changes a disk goes through udisks2, which asks
for an administrator's password (polkit) when the disk isn't the user's
to change.

The disk freemac is running from is the system disk: Hull shows it but
won't unmount, rename, erase or eject it.

Original freemac code; no GTK here, so it can be tried from a terminal.
"""
import os

from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.UDisks2"
ROOT = "/org/freedesktop/UDisks2"
P = "org.freedesktop.UDisks2."
TIMEOUT = 15 * 60 * 1000          # erasing a big drive takes a while

# Where the running system lives: the drives holding these are left alone.
SYSTEM_MOUNTS = ("/", "/boot", "/boot/efi", "/efi", "/home", "/usr", "/var", "/run/live/medium")

# What Erase can make, as (name, udisks type, what it's for, longest name).
FORMATS = [
    ("ExFAT", "exfat", "Works with Mac and Windows computers too, for files of any size.", 15),
    ("MS-DOS (FAT)", "vfat", "Works with almost anything, but no single file can be over 4 GB.", 11),
    ("freemac (ext4)", "ext4", "Fastest, for a drive you'll only use with freemac and Linux.", 16),
]

FS_NAMES = {
    "exfat": "ExFAT", "ntfs": "Windows NT File System (NTFS)", "ext4": "Linux (ext4)",
    "ext3": "Linux (ext3)", "ext2": "Linux (ext2)", "btrfs": "Btrfs", "xfs": "XFS",
    "hfsplus": "Mac OS Extended", "apfs": "APFS", "iso9660": "ISO 9660 (CD/DVD)", "udf": "UDF (DVD)",
    "crypto_LUKS": "Encrypted", "swap": "Swap", "squashfs": "Compressed (squashfs)",
}

BUSES = {"usb": "USB", "sdio": "Secure Digital", "ieee1394": "FireWire", "nvme": "PCI-Express (NVMe)",
         "ata": "SATA", "scsi": "SCSI", "virtio": "Virtual"}


def _bytes(value):
    """udisks paths are NUL-terminated byte arrays."""
    return bytes(value).rstrip(b"\0").decode(errors="replace") if value else ""


def size_words(n):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1000
    return ""


def fs_name(fstype, version=""):
    if fstype == "vfat":
        return f"MS-DOS ({version})" if version else "MS-DOS (FAT)"
    return FS_NAMES.get(fstype, fstype.upper() if fstype else "Unknown")


def _system_disks():
    """Kernel names of the whole disks the running system is on (sda, nvme0n1,
    sr0), following partitions, encryption and LVM down to the disk."""
    found = set()
    try:
        with open("/proc/self/mounts") as f:
            mounts = [line.split()[:2] for line in f]
    except OSError:
        return found
    todo = []
    for source, target in mounts:
        if target in SYSTEM_MOUNTS and source.startswith("/dev/"):
            todo.append(os.path.basename(os.path.realpath(source)))
    seen = set()
    while todo:
        name = todo.pop()
        if name in seen:
            continue
        seen.add(name)
        sys_path = os.path.realpath(f"/sys/class/block/{name}")
        try:
            slaves = os.listdir(os.path.join(sys_path, "slaves"))
        except OSError:
            slaves = []
        todo.extend(slaves)
        if os.path.exists(os.path.join(sys_path, "partition")):
            found.add(os.path.basename(os.path.dirname(sys_path)))
        elif not slaves:
            found.add(name)
    return found


class Volume:
    def __init__(self, path, props):
        block = props[P + "Block"]
        self.path = path
        self.device = _bytes(block.get("PreferredDevice") or block.get("Device"))
        self.size = block.get("Size", 0)
        self.fstype = block.get("IdType", "")
        self.usage = block.get("IdUsage", "")
        self.version = block.get("IdVersion", "")
        self.label = block.get("IdLabel", "")
        self.drive_path = block.get("Drive", "/")
        self.crypto_backing = block.get("CryptoBackingDevice", "/")
        self.has_fs = P + "Filesystem" in props
        self.mounts = [_bytes(m) for m in props.get(P + "Filesystem", {}).get("MountPoints", [])]
        part = props.get(P + "Partition")
        self.number = part.get("Number", 0) if part else 0
        self.offset = part.get("Offset", 0) if part else 0
        self.is_partition = part is not None
        self.table = props.get(P + "PartitionTable", {}).get("Type", "") if P + "PartitionTable" in props else None
        self.is_table = P + "PartitionTable" in props
        self.drive = None
        self.system = False

    @property
    def name(self):
        if self.label:
            return self.label
        if self.fstype:
            return f"{size_words(self.size)} {fs_name(self.fstype, self.version)} Volume" \
                if self.usage == "filesystem" else fs_name(self.fstype)
        return "Untitled"

    @property
    def mount_point(self):
        return self.mounts[0] if self.mounts else ""

    def space(self):
        """(capacity, used, free) in bytes while mounted, else None."""
        if not self.mount_point:
            return None
        try:
            st = os.statvfs(self.mount_point)
        except OSError:
            return None
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        return total, max(0, total - st.f_bfree * st.f_frsize), free

    @property
    def kind(self):
        return fs_name(self.fstype, self.version) if self.fstype else "Free space or unknown"


class Drive:
    def __init__(self, path, props):
        d = props[P + "Drive"]
        self.path = path
        vendor, model = d.get("Vendor", "").strip(), d.get("Model", "").strip()
        self.size = d.get("Size", 0)
        self.removable = bool(d.get("Removable") or d.get("MediaRemovable"))
        self.ejectable = bool(d.get("Ejectable"))
        self.can_power_off = bool(d.get("CanPowerOff"))
        self.bus = d.get("ConnectionBus", "")
        self.optical = bool(d.get("Optical")) or any(m.startswith("optical") for m in d.get("MediaCompatibility", []))
        self.media = bool(d.get("MediaAvailable", True))
        self.rotation = d.get("RotationRate", -1)
        if vendor and model.lower().startswith(vendor.lower()):
            vendor = ""        # "QEMU QEMU HARDDISK", "WDC WDC WD10..."
        self.model = " ".join(p for p in (vendor, model) if p) or f"{size_words(self.size)} Disk"
        self.whole = None          # the Volume for the whole disk
        self.volumes = []          # file systems on it, partitions in order
        self.system = False

    @property
    def external(self):
        return self.bus in ("usb", "sdio", "ieee1394") or (self.removable and not self.optical)

    @property
    def name(self):
        return f"{self.model} Media" if self.external and not self.optical else self.model

    @property
    def connection(self):
        return BUSES.get(self.bus, self.bus.upper() if self.bus else "")

    @property
    def scheme(self):
        if self.whole is None or not self.whole.is_table:
            return "None" if self.whole is not None and self.whole.has_fs else "—"
        return {"gpt": "GUID Partition Map", "dos": "Master Boot Record"}.get(self.whole.table, self.whole.table)

    @property
    def medium(self):
        if self.optical:
            return "Optical disc"
        return {0: "Solid state"}.get(self.rotation, "Hard disk" if self.rotation and self.rotation > 0 else "")

    @property
    def mounted(self):
        return [v for v in self.volumes if v.mounts]


class ImageDrive(Drive):
    """A disk image this account has open (disk_images): shown as a drive of
    its own, ejected by closing it."""

    def __init__(self, path, props, backing):
        block = props[P + "Block"]
        self.path = path
        self.image = backing
        self.size = block.get("Size", 0)
        self.removable = True
        self.ejectable = True
        self.can_power_off = False
        self.bus = ""
        self.optical = False
        self.media = True
        self.rotation = -1
        self.model = os.path.basename(backing)
        self.read_only = bool(block.get("ReadOnly"))
        self.whole = None
        self.volumes = []
        self.system = False

    @property
    def external(self):
        return False

    @property
    def name(self):
        return self.model

    @property
    def medium(self):
        return "Disk image"


def read(bus=None):
    """The drives udisks knows, internal first, then external, each with its
    volumes. Disks the system hides (and loop and RAM disks) are left out."""
    bus = bus or Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    reply = bus.call_sync(BUS_NAME, ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
                          None, GLib.VariantType.new("(a{oa{sa{sv}}})"), Gio.DBusCallFlags.NONE, 5000, None)
    objects = reply.unpack()[0]
    drives = {path: Drive(path, props) for path, props in objects.items() if P + "Drive" in props}
    for path, props in objects.items():
        loop = props.get(P + "Loop")
        if loop and P + "Block" in props and loop.get("SetupByUID") == os.getuid() and loop.get("BackingFile"):
            drives[path] = ImageDrive(path, props, _bytes(loop["BackingFile"]))
    system = _system_disks()
    for path, props in sorted(objects.items()):
        if P + "Block" not in props:
            continue
        block = props[P + "Block"]
        owner = block.get("Drive", "/")
        if path in drives:
            owner = path                       # an open disk image's own block
        elif props.get(P + "Partition", {}).get("Table") in drives and \
                isinstance(drives[props[P + "Partition"]["Table"]], ImageDrive):
            owner = props[P + "Partition"]["Table"]
        if block.get("HintIgnore") or owner not in drives:
            continue
        vol = Volume(path, props)
        vol.drive_path = owner
        drive = drives[owner]
        vol.drive = drive
        if not vol.is_partition:
            drive.whole = vol
            if vol.is_table or not (vol.has_fs or vol.fstype):
                continue           # the disk itself; its partitions are the volumes
        if vol.is_partition and not vol.fstype and vol.size < 10 * 1024 * 1024:
            continue               # a small gap or boot partition with nothing in it
        drive.volumes.append(vol)
    for drive in drives.values():
        name = os.path.basename(drive.whole.device) if drive.whole else ""
        drive.system = name in system and not isinstance(drive, ImageDrive)
        for vol in drive.volumes:
            vol.system = drive.system
        drive.volumes.sort(key=lambda v: (v.offset, v.number))
    # An empty card reader, disc drive or floppy drive has nothing to show.
    shown = [d for d in drives.values() if d.size and (d.whole is not None or d.volumes)]
    return sorted(shown, key=lambda d: (isinstance(d, ImageDrive), d.optical, d.external, d.model))


class Actions:
    """Changes to disks, each finished with done(error_text or None). Calls
    are allowed to ask for an administrator's password."""

    def __init__(self, bus=None):
        self.bus = bus or Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def _call(self, path, interface, method, args, then):
        def finished(source, result, _data):
            try:
                value = source.call_finish(result)
            except GLib.Error as error:
                then(None, error)
                return
            then(value, None)

        self.bus.call(BUS_NAME, path, P + interface, method, args, None,
                      Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, TIMEOUT, None, finished, None)

    @staticmethod
    def words(error):
        """What went wrong, for a person; None when they cancelled it."""
        if error is None:
            return ""
        remote = Gio.DBusError.get_remote_error(error) or ""
        Gio.DBusError.strip_remote_error(error)
        text = error.message
        low = text.lower()
        if remote.endswith(".Cancelled") or "dismissed" in low or "cancel" in low:
            return None
        if remote.endswith("NotAuthorized") or remote.endswith("NotAuthorizedCanObtain") \
                or "not authorized" in low:
            return "You need to be an administrator to change this disk."
        if "busy" in low or "target is busy" in low:
            return "One or more apps may be using it. Quit them, or close their files on the disk, and try again."
        return text

    def _steps(self, steps, done):
        """Run calls one after another; stop at the first that fails."""
        steps = list(steps)

        def next_step(_value=None, error=None):
            if error is not None:
                done(error)
                return
            if not steps:
                done(None)
                return
            step = steps.pop(0)
            if callable(step):
                step(next_step)
            else:
                self._call(*step, next_step)
        next_step()

    @staticmethod
    def _none():
        return GLib.Variant("(a{sv})", ({},))

    def mount(self, vol, done):
        self._call(vol.path, "Filesystem", "Mount", self._none(), lambda _v, e: done(e))

    def unmount(self, vol, done):
        self._call(vol.path, "Filesystem", "Unmount", self._none(), lambda _v, e: done(e))

    def _unmount_all(self, volumes):
        return [(v.path, "Filesystem", "Unmount", self._none()) for v in volumes if v.mounts]

    def eject(self, drive, done):
        """Unmount everything on it, then power it off (a USB drive) or open
        the tray (a disc)."""
        steps = self._unmount_all(drive.volumes)
        if isinstance(drive, ImageDrive):
            def close(next_step):
                # An image opened by Hatch closes by itself once unmounted.
                def closed(_value, error):
                    if error is not None and ("No such" in error.message or "UnknownObject" in error.message
                                              or "UnknownMethod" in error.message):
                        error = None
                    next_step(None, error)
                self._call(drive.path, "Loop", "Delete", self._none(), closed)
            steps.append(close)
            self._steps(steps, done)
            return
        if drive.ejectable and drive.optical:
            steps.append((drive.path, "Drive", "Eject", self._none()))
        elif drive.can_power_off:
            steps.append((drive.path, "Drive", "PowerOff", self._none()))
        elif drive.ejectable:
            steps.append((drive.path, "Drive", "Eject", self._none()))
        self._steps(steps, done)

    def rename(self, vol, label, done):
        """Some file systems can only be renamed while unmounted: then unmount,
        rename and mount again."""
        set_label = (vol.path, "Filesystem", "SetLabel", GLib.Variant("(sa{sv})", (label, {})))

        def remounted(_value, _error):
            done(None)

        def moved(_value, error):
            # Mounted again under its new name, as the Desktop and Drawer show it;
            # if something is using it, it stays where it was until next time.
            if error is None:
                self._call(vol.path, "Filesystem", "Mount", self._none(), remounted)
            else:
                done(None)

        def tried(_value, error):
            remote = Gio.DBusError.get_remote_error(error) or "" if error else ""
            if error is None and vol.mounts:
                self._call(vol.path, "Filesystem", "Unmount", self._none(), moved)
                return
            if error is None or not vol.mounts or "NotAuthorized" in remote:
                done(error)
                return

            def finished(error2):
                if error2 is not None:
                    # Put it back as it was before saying it failed.
                    self._call(vol.path, "Filesystem", "Mount", self._none(), lambda _v, _e: done(error2))
                else:
                    done(None)
            self._steps([(vol.path, "Filesystem", "Unmount", self._none()), set_label,
                         (vol.path, "Filesystem", "Mount", self._none())], finished)
        self._call(*set_label, tried)

    @staticmethod
    def _format_options(fstype, label):
        options = {"label": GLib.Variant("s", label), "update-partition-type": GLib.Variant("b", True)}
        if fstype == "ext4":
            options["take-ownership"] = GLib.Variant("b", True)
        return options

    def erase_volume(self, vol, fstype, label, done):
        """Make a new, empty file system in this volume's place, and mount it."""
        steps = self._unmount_all([vol])
        steps.append((vol.path, "Block", "Format",
                      GLib.Variant("(sa{sv})", (fstype, self._format_options(fstype, label)))))
        steps.append((vol.path, "Filesystem", "Mount", self._none()))
        self._steps(steps, done)

    def erase_drive(self, drive, fstype, label, done):
        """Wipe the whole drive: a new partition map with one volume filling it."""
        whole = drive.whole
        scheme = "gpt" if fstype == "ext4" or drive.size > 2 * 1000 ** 4 else "dos"
        created = []

        def make_partition(then):
            args = GLib.Variant("(ttssa{sv}sa{sv})", (1024 * 1024, 0, "", "", {}, fstype,
                                                      self._format_options(fstype, label)))

            def made(value, error):
                if value is not None:
                    created.append(value.unpack()[0])
                then(value, error)
            self._call(whole.path, "PartitionTable", "CreatePartitionAndFormat", args, made)

        def mount_new(then):
            if not created:
                then()
                return
            self._call(created[0], "Filesystem", "Mount", self._none(), then)

        steps = self._unmount_all(drive.volumes)
        steps.append((whole.path, "Block", "Format",
                      GLib.Variant("(sa{sv})", (scheme, {}))))
        steps += [make_partition, mount_new]
        self._steps(steps, done)

    def partition_drive(self, drive, layout, done):
        """Wipe the whole drive and divide it as the partition_plan.Layout
        says: a GUID partition map, then each volume in order, made, named
        and mounted."""
        whole = drive.whole
        created = []

        def maker(part, offset, size):
            def make(then):
                args = GLib.Variant("(ttssa{sv}sa{sv})", (offset, size, "", part.name, {}, part.fstype,
                                                          self._format_options(part.fstype, part.name)))

                def made(value, error):
                    if value is not None:
                        created.append(value.unpack()[0])
                    then(value, error)
                self._call(whole.path, "PartitionTable", "CreatePartitionAndFormat", args, made)
            return make

        def mount_all(then):
            def one(left):
                if not left:
                    then()
                    return
                # A volume that won't mount is still made; it shows unmounted.
                self._call(left[0], "Filesystem", "Mount", self._none(), lambda _v, _e: one(left[1:]))
            one(list(created))

        steps = self._unmount_all(drive.volumes)
        steps.append((whole.path, "Block", "Format", GLib.Variant("(sa{sv})", ("gpt", {}))))
        steps += [maker(part, offset, size) for part, (offset, size) in zip(layout.parts, layout.offsets())]
        steps.append(mount_all)
        self._steps(steps, done)


# ---- First Aid ---------------------------------------------------------------------

OK, REPAIRED, BROKEN, UNSUPPORTED = "ok", "repaired", "broken", "unsupported"


def _sync(bus, path, interface, method, args, reply_type=None):
    return bus.call_sync(BUS_NAME, path, P + interface, method, args,
                         GLib.VariantType.new(reply_type) if reply_type else None,
                         Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, TIMEOUT, None)


def _can(bus, what, fstype):
    try:
        reply = _sync(bus, ROOT + "/Manager", "Manager", what, GLib.Variant("(s)", (fstype,)), "((bs))")
        return reply.unpack()[0][0]
    except GLib.Error:
        return False


def first_aid(path, fstype, mounted, bus=None):
    """Check a volume's file system for errors and repair them if there are
    any, as a Mac's Disk Utility First Aid does: unmounted while it runs,
    mounted again afterwards if it was. One of OK, REPAIRED, BROKEN or
    UNSUPPORTED; GLib.Error when udisks says no (busy, not allowed)."""
    bus = bus or Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    if not _can(bus, "CanCheck", fstype):
        return UNSUPPORTED
    none = GLib.Variant("(a{sv})", ({},))
    if mounted:
        _sync(bus, path, "Filesystem", "Unmount", none)
    try:
        sound = _sync(bus, path, "Filesystem", "Check", none, "(b)").unpack()[0]
        if sound:
            result = OK
        elif not _can(bus, "CanRepair", fstype):
            result = BROKEN
        else:
            fixed = _sync(bus, path, "Filesystem", "Repair", none, "(b)").unpack()[0]
            result = REPAIRED if fixed else BROKEN
    finally:
        if mounted:
            try:
                _sync(bus, path, "Filesystem", "Mount", none, "(s)")
            except GLib.Error:
                pass
    return result


def watch(callback, bus=None):
    """Call callback() when a drive or volume comes, goes or changes."""
    bus = bus or Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    ids = []
    for interface, member in (("org.freedesktop.DBus.ObjectManager", "InterfacesAdded"),
                              ("org.freedesktop.DBus.ObjectManager", "InterfacesRemoved"),
                              ("org.freedesktop.DBus.Properties", "PropertiesChanged")):
        ids.append(bus.signal_subscribe(BUS_NAME, interface, member, None, None,
                                        Gio.DBusSignalFlags.NONE, lambda *_: callback()))
    return bus, ids


if __name__ == "__main__":
    for drive in read():
        flags = " ".join(f for f, on in (("external", drive.external), ("system", drive.system),
                                         ("optical", drive.optical)) if on)
        print(f"{drive.name}  {size_words(drive.size)}  {drive.connection}  {drive.scheme}  [{flags}]")
        for vol in drive.volumes:
            space = vol.space()
            used = f"  used {size_words(space[1])} of {size_words(space[0])}" if space else ""
            print(f"    {vol.name}  {vol.kind}  {vol.device}  {vol.mount_point or 'not mounted'}{used}")
