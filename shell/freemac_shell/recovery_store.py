# SPDX-License-Identifier: GPL-3.0-or-later
"""What freemac Recovery does to the computer, with no GTK, so it can be
tested on its own. Everything here runs as root.

Recovery starts in one of two ways:

- from the disk freemac is installed on (Ctrl held at start-up, the freemac
  Recovery entry in the start-up menu, or Restart in Recovery in Dials). The
  system to fix is then the one running: its root is "/".
- from a freemac USB stick (the live system). The system to fix is a freemac
  installed on one of the computer's disks, found by looking for a partition
  whose /etc/os-release says ID=freemac, and mounted under RUN.

Original freemac code.
"""
import json
import os
import shutil
import stat
import subprocess

from . import backup_store

RUN = "/run/freemac-recovery"
LIVE_MEDIUM = "/run/live/medium"
CHECKABLE = ("ext2", "ext3", "ext4", "vfat", "exfat")
MOUNTABLE = ("ext2", "ext3", "ext4", "vfat", "exfat", "ntfs", "ntfs3", "btrfs", "xfs")

_mounted = []        # mount points this process made, newest last


def live():
    """True when Recovery is running from a freemac USB stick."""
    return os.path.isdir(LIVE_MEDIUM)


def _run(*cmd, stdin=None, timeout=None):
    return subprocess.run(list(cmd), input=stdin, capture_output=True, text=True, timeout=timeout)


def human(size):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            return f"{size:.0f} {unit}" if unit == "bytes" else f"{size:.1f} {unit}".replace(".0 ", " ")
        size /= 1000
    return ""


# -- disks ----------------------------------------------------------------------

def partitions():
    """Every partition (and whole disk with a file system) the kernel knows,
    as dicts: path, name, fstype, label, size, mountpoints, model, removable."""
    result = _run("lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,FSTYPE,LABEL,SIZE,MOUNTPOINTS,MODEL,RM,RO")
    try:
        tree = json.loads(result.stdout or "{}").get("blockdevices", [])
    except ValueError:
        return []
    found = []

    def walk(nodes, disk):
        for node in nodes:
            parent = node if node.get("type") == "disk" else disk
            if node.get("fstype") and node.get("type") in ("part", "disk", "crypt", "lvm", "loop"):
                found.append({
                    "path": node.get("path"),
                    "name": node.get("name"),
                    "fstype": node.get("fstype"),
                    "label": node.get("label") or "",
                    "size": int(node.get("size") or 0),
                    "mountpoints": [m for m in (node.get("mountpoints") or []) if m],
                    "model": ((parent or {}).get("model") or "").strip(),
                    "removable": bool((parent or {}).get("rm")),
                    "readonly": bool(node.get("ro")),
                })
            walk(node.get("children") or [], parent)

    walk(tree, None)
    return found


def describe(part):
    """A name a person recognises: the volume's label, or the drive's model
    and how big it is."""
    size = human(part["size"]) if part["size"] else ""
    if part["label"]:
        return f"{part['label']} ({size})" if size else part["label"]
    model = part["model"] or "Disk"
    return f"{model} — {size}" if size else model


def mount(part, readonly=True):
    """Mount a partition under RUN and return where; reuse an existing mount."""
    if part["mountpoints"]:
        return part["mountpoints"][0]
    point = os.path.join(RUN, "drives", part["name"])
    os.makedirs(point, exist_ok=True)
    options = ["-o", "ro"] if readonly else []
    result = _run("mount", *options, part["path"], point)
    if result.returncode != 0:
        try:
            os.rmdir(point)
        except OSError:
            pass
        raise OSError(result.stderr.strip() or f"{part['path']} couldn't be opened.")
    _mounted.append(point)
    part["mountpoints"] = [point]
    return point


def unmount_all():
    """Unmount everything this process mounted, newest first."""
    while _mounted:
        point = _mounted.pop()
        _run("umount", point)
        try:
            os.rmdir(point)
        except OSError:
            pass


def _os_release(root):
    values = {}
    try:
        with open(os.path.join(root, "etc/os-release")) as f:
            for line in f:
                key, _, value = line.strip().partition("=")
                values[key] = value.strip('"')
    except OSError:
        pass
    return values


# -- the system being fixed -------------------------------------------------------

class System:
    """A freemac to fix: its root folder and a name for it."""

    def __init__(self, root, name, part=None):
        self.root = root
        self.name = name
        self.part = part

    def path(self, *parts):
        return os.path.join(self.root, *[p.lstrip("/") for p in parts])

    def users(self):
        """People's accounts on this system, as pwd-like tuples
        (name, uid, gid, full name, home inside this root)."""
        people = []
        try:
            with open(self.path("etc/passwd")) as f:
                lines = f.read().splitlines()
        except OSError:
            return people
        for line in lines:
            fields = line.split(":")
            if len(fields) < 7:
                continue
            name, _x, uid, gid, gecos, home, shell = fields[:7]
            try:
                uid, gid = int(uid), int(gid)
            except ValueError:
                continue
            if 1000 <= uid < 60000 and not shell.endswith(("nologin", "false")):
                people.append((name, uid, gid, gecos.split(",")[0] or name, self.path(home)))
        return people


def systems():
    """The freemac systems Recovery can fix. Running from the disk, that's the
    one running. From a USB stick, every installed freemac found on a disk."""
    if not live():
        release = _os_release("/")
        return [System("/", release.get("PRETTY_NAME", "freemac"))]
    found = []
    for part in partitions():
        if part["fstype"] not in ("ext4", "ext3", "btrfs", "xfs") or part["removable"]:
            continue
        was_mounted = bool(part["mountpoints"])
        try:
            root = mount(part, readonly=True)
        except OSError:
            continue
        release = _os_release(root)
        if release.get("ID") == "freemac":
            found.append(System(root, f"{release.get('PRETTY_NAME', 'freemac')} on {describe(part)}", part))
        elif not was_mounted:
            _run("umount", root)
            if root in _mounted:
                _mounted.remove(root)
            part["mountpoints"] = []
    return found


def writable(system):
    """Make sure a system found on a disk can be changed (it is first mounted
    read-only while Recovery looks around)."""
    if system.root == "/" or not system.part:
        return
    result = _run("mount", "-o", "remount,rw", system.root)
    if result.returncode != 0:
        raise OSError(result.stderr.strip() or "The disk couldn't be opened for changes.")


# -- undoing an update -----------------------------------------------------------

UPDATE_HELPER = "/usr/libexec/freemac-update-helper"


def update_undo(system):
    """(the version Undo Last Update puts back, the version now) or (None, now)."""
    now = _os_release(system.root).get("VERSION_ID", "")
    try:
        with open(system.path("var/lib/freemac/update/previous/manifest.json")) as f:
            before = json.load(f).get("version")
    except (OSError, ValueError, AttributeError):
        before = None
    return before, now


def undo_update(system):
    writable(system)
    helper = UPDATE_HELPER if os.path.exists(UPDATE_HELPER) else system.path(UPDATE_HELPER.lstrip("/"))
    result = _run("python3", helper, "--root", system.root, "rollback", timeout=1200)
    if result.returncode != 0:
        words = (result.stdout or "").strip().removeprefix("error ").strip()
        raise OSError(words or "Something went wrong.")
    return True


# -- passwords --------------------------------------------------------------------

ADMIN_GROUPS = ("sudo", "admin", "wheel")


def administrators(system):
    """The people on a system who are administrators, as users() gives them."""
    members = set()
    try:
        with open(system.path("etc/group")) as f:
            for line in f:
                fields = line.strip().split(":")
                if len(fields) >= 4 and fields[0] in ADMIN_GROUPS:
                    members.update(name for name in fields[3].split(",") if name)
    except OSError:
        pass
    return [person for person in system.users() if person[0] in members]


def _crypt(password, setting):
    import ctypes
    import ctypes.util

    name = ctypes.util.find_library("crypt") or "libcrypt.so.1"
    library = ctypes.CDLL(name)
    library.crypt.restype = ctypes.c_char_p
    library.crypt.argtypes = (ctypes.c_char_p, ctypes.c_char_p)
    result = library.crypt(password.encode(), setting.encode())
    return result.decode() if result else None


def password_matches(system, user, password):
    """True when password is the user's password on that system."""
    try:
        with open(system.path("etc/shadow")) as f:
            lines = f.read().splitlines()
    except OSError:
        return False
    for line in lines:
        fields = line.split(":")
        if len(fields) > 1 and fields[0] == user:
            stored = fields[1]
            if not stored or stored[0] in "!*":
                return False
            try:
                return _crypt(password, stored) == stored
            except OSError:
                return False
    return False

def reset_password(system, user, password):
    if not password or "\n" in password or ":" in user:
        raise ValueError("That password can't be used.")
    writable(system)
    command = ["chpasswd"] if system.root == "/" else ["chpasswd", "-R", system.root]
    result = _run(*command, stdin=f"{user}:{password}\n")
    if result.returncode != 0:
        raise OSError(result.stderr.strip() or "The password couldn't be changed.")


# -- Lifeboat backups --------------------------------------------------------------

class BackupSet:
    """One computer-and-person's backups on a drive."""

    def __init__(self, drive, folder):
        self.drive = drive                       # the partition dict
        self.folder = folder                     # .../freemac-backups/host-user
        self.label = os.path.basename(folder)    # host-user

    @property
    def user(self):
        return self.label.rsplit("-", 1)[-1]

    @property
    def computer(self):
        return self.label.rsplit("-", 1)[0]

    def backups(self):
        """(time, path) newest first."""
        found = []
        try:
            names = os.listdir(self.folder)
        except OSError:
            return found
        for name in names:
            when = backup_store.stamp_time(name)
            if when is not None and os.path.isdir(os.path.join(self.folder, name)):
                found.append((when, os.path.join(self.folder, name)))
        return sorted(found, reverse=True)


def backup_sets():
    """Every set of Lifeboat backups on the drives plugged in. Drives that
    aren't mounted are mounted read-only to look."""
    sets = []
    for part in partitions():
        if part["fstype"] not in MOUNTABLE:
            continue
        if any(m in ("/", "/boot/efi") for m in part["mountpoints"]):
            continue
        try:
            root = mount(part, readonly=True)
        except OSError:
            continue
        top = os.path.join(root, backup_store.TOP)
        try:
            names = sorted(os.listdir(top))
        except OSError:
            continue
        for name in names:
            folder = os.path.join(top, name)
            if os.path.isdir(folder):
                found = BackupSet(part, folder)
                if found.backups():
                    sets.append(found)
    return sets


def count_files(source):
    total = 0
    for _root, dirs, files in os.walk(source):
        total += len(files) + len(dirs)
    return total


def restore(source, home, uid, gid, progress=None, stop=None):
    """Copy a whole backup back into a home folder. Files in the backup replace
    the ones of the same name; anything made since the backup is kept. Every
    copy is given to the person (uid, gid). Returns how many files came back."""
    total = max(1, count_files(source))
    done = 0
    copied = 0
    os.makedirs(home, exist_ok=True)
    os.chown(home, uid, gid)
    for root, dirs, files in os.walk(source):
        if stop and stop():
            raise backup_store.Stopped()
        rel = os.path.relpath(root, source)
        target_dir = home if rel == "." else os.path.join(home, rel)
        for name in dirs:
            done += 1
            path = os.path.join(target_dir, name)
            src = os.path.join(root, name)
            if os.path.islink(src):
                continue
            if os.path.lexists(path) and not os.path.isdir(path):
                os.remove(path)
            os.makedirs(path, exist_ok=True)
            os.chown(path, uid, gid)
            shutil.copystat(src, path)
        # os.walk lists links to folders as folders; copy those as links.
        names = files + [d for d in dirs if os.path.islink(os.path.join(root, d))]
        for name in names:
            done += 1
            src = os.path.join(root, name)
            dst = os.path.join(target_dir, name)
            try:
                st = os.lstat(src)
                if os.path.isdir(dst) and not os.path.islink(dst):
                    shutil.rmtree(dst)
                elif os.path.lexists(dst):
                    os.remove(dst)
                if stat.S_ISLNK(st.st_mode):
                    os.symlink(os.readlink(src), dst)
                elif stat.S_ISREG(st.st_mode):
                    shutil.copy2(src, dst)
                else:
                    continue
                os.lchown(dst, uid, gid)
                copied += 1
            except OSError:
                continue
            if progress and done % 50 == 0:
                progress(done / total, os.path.join(rel, name) if rel != "." else name)
    if progress:
        progress(1.0, "")
    return copied


# -- checking disks ----------------------------------------------------------------

def checkable():
    """Volumes that can be checked now: a known file system, not in use."""
    return [p for p in partitions()
            if p["fstype"] in CHECKABLE and not p["mountpoints"] and not p["readonly"]]


def check(part):
    """Check a volume and fix what can be fixed. Returns (state, words):
    state is "ok", "fixed" or "problem"."""
    fstype = part["fstype"]
    if fstype.startswith("ext"):
        cmd = ["e2fsck", "-f", "-y", part["path"]]
    elif fstype == "vfat":
        cmd = ["fsck.vfat", "-a", "-w", part["path"]]
    elif fstype == "exfat":
        cmd = ["fsck.exfat", "-y", part["path"]]
    else:
        return "problem", "freemac can't check this kind of volume."
    if not shutil.which(cmd[0]):
        return "problem", "The tool for checking this kind of volume isn't installed."
    try:
        result = _run(*cmd, timeout=3600)
    except subprocess.TimeoutExpired:
        return "problem", "Checking took too long and was stopped."
    code = result.returncode
    if code == 0:
        return "ok", f"“{describe(part)}” looks fine. No problems were found."
    if code in (1, 2, 3):
        return "fixed", f"Problems on “{describe(part)}” were found and fixed."
    last = [line for line in (result.stdout + result.stderr).splitlines() if line.strip()]
    detail = last[-1] if last else ""
    return "problem", (f"“{describe(part)}” has problems that couldn't be fixed. Copy what you can "
                       "off it, then erase it in Drives." + (f"\n\n{detail}" if detail else ""))


# -- start-up ---------------------------------------------------------------------

def restart(into_recovery=False):
    if into_recovery and not live() and shutil.which("grub-reboot"):
        _run("grub-reboot", "freemac-recovery")
    _run("systemctl", "reboot")


def shut_down():
    _run("systemctl", "poweroff")


# -- Wi-Fi ------------------------------------------------------------------------

def networks():
    """Wi-Fi networks in reach: (name, signal 0-100, secured, connected)."""
    if not shutil.which("nmcli"):
        return []
    result = _run("nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto",
                  timeout=20)
    seen = {}
    for line in result.stdout.splitlines():
        parts = line.replace("\\:", "\0").split(":")
        if len(parts) < 4:
            continue
        in_use, ssid, signal, security = (p.replace("\0", ":") for p in parts[:4])
        if not ssid:
            continue
        try:
            signal = int(signal)
        except ValueError:
            signal = 0
        entry = (ssid, signal, bool(security and security != "--"), in_use == "*")
        if ssid not in seen or entry[3] or signal > seen[ssid][1]:
            seen[ssid] = entry
    return sorted(seen.values(), key=lambda e: (not e[3], -e[1]))


def join(ssid, password=None):
    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if password:
        cmd += ["password", password]
    result = _run(*cmd, timeout=60)
    if result.returncode != 0:
        raise OSError(result.stderr.strip() or result.stdout.strip() or "Couldn't join the network.")


def online():
    """True when NetworkManager says the computer can reach the internet."""
    if not shutil.which("nmcli"):
        return False
    try:
        result = _run("nmcli", "-t", "-f", "CONNECTIVITY", "general", timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.stdout.strip() in ("full", "limited", "portal")


def connection():
    """"wifi" or "ethernet" for the kind of network in use, or None."""
    if not shutil.which("nmcli"):
        return None
    try:
        result = _run("nmcli", "-t", "-f", "TYPE,STATE", "device", timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        return None
    kinds = [line.split(":")[0] for line in result.stdout.splitlines()
             if line.endswith(":connected")]
    for kind in ("ethernet", "wifi"):
        if kind in kinds:
            return kind
    return None