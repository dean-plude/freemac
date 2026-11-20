# SPDX-License-Identifier: GPL-3.0-or-later
"""Keel backend: install freemac from the live session onto a whole disk.

Run as root. Reads a JSON request on stdin so that the password never appears
on a command line:

    {"disk": "/dev/vda", "fullname": "Ada", "username": "ada",
     "password": "...", "hostname": "ada-pc", "timezone": "Europe/London",
     "autologin": true}

Prints one line per step, "PROGRESS <percent> <message>", then "DONE" or
"ERROR <message>". The disk is erased: GPT with a BIOS boot partition, an EFI
system partition and an ext4 root, so the result boots on BIOS and UEFI PCs.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time

TARGET = "/mnt/freemac-target"
SQUASHFS_CANDIDATES = ("/run/live/medium/live/filesystem.squashfs", "/lib/live/mount/medium/live/filesystem.squashfs")
LIVE_PACKAGES = ("live-boot", "live-boot-initramfs-tools")
USER_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,30}$")
HOST_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$")
RESERVED = {"root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail", "news", "uucp", "proxy",
            "www-data", "backup", "list", "irc", "nobody", "systemd-network", "messagebus", "_greetd", "freemac"}


class InstallError(Exception):
    pass


def progress(percent, message):
    print(f"PROGRESS {percent} {message}", flush=True)


def run(*cmd, stdin=None, chroot=False):
    if chroot:
        cmd = ("chroot", TARGET) + cmd
    result = subprocess.run(cmd, input=stdin, capture_output=True, text=True,
                            env=dict(os.environ, LC_ALL="C", DEBIAN_FRONTEND="noninteractive"))
    if result.returncode != 0:
        raise InstallError(f"{' '.join(cmd[:4])} failed: {(result.stderr or result.stdout).strip()[-400:]}")
    return result.stdout


def partition_path(disk, number):
    return f"{disk}p{number}" if disk[-1].isdigit() else f"{disk}{number}"


def disks():
    """Disks a person could install to (not the live medium, not too small)."""
    out = subprocess.run(["lsblk", "-J", "-b", "-d", "-o", "NAME,PATH,SIZE,MODEL,TYPE,RO,RM,TRAN"],
                         capture_output=True, text=True).stdout
    live = live_medium_disk()
    found = []
    for dev in json.loads(out or '{"blockdevices": []}')["blockdevices"]:
        if dev["type"] != "disk" or dev["ro"] in (True, "1") or dev["path"] == live:
            continue
        if int(dev["size"]) < 8 * 10**9:
            continue
        found.append({"path": dev["path"], "size": int(dev["size"]),
                      "model": (dev.get("model") or "").strip() or dev["name"], "removable": dev["rm"] in (True, "1")})
    return found


def live_medium_disk():
    for medium in ("/run/live/medium", "/lib/live/mount/medium"):
        out = subprocess.run(["findmnt", "-n", "-o", "SOURCE", medium], capture_output=True, text=True).stdout.strip()
        if out:
            parent = subprocess.run(["lsblk", "-n", "-d", "-o", "PKNAME", out], capture_output=True, text=True)
            name = parent.stdout.strip()
            return f"/dev/{name}" if name else out
    return None


def validate(request):
    disk = request.get("disk", "")
    if disk not in [d["path"] for d in disks()]:
        raise InstallError(f"{disk or 'No disk'} isn't a disk freemac can install to.")
    if not USER_RE.match(request.get("username", "")) or request["username"] in RESERVED:
        raise InstallError("Choose a user name made of lower-case letters, digits, - or _.")
    if not HOST_RE.match(request.get("hostname", "")):
        raise InstallError("Choose a computer name made of letters, digits and -.")
    if len(request.get("password", "")) < 4:
        raise InstallError("Choose a password of at least 4 characters.")
    tz = request.get("timezone") or "UTC"
    if not os.path.exists(os.path.join("/usr/share/zoneinfo", tz)) or ".." in tz:
        request["timezone"] = "UTC"
    for key in ("fullname",):
        request[key] = str(request.get(key, "")).replace(":", " ").replace(",", " ").strip()


def find_squashfs():
    for path in SQUASHFS_CANDIDATES:
        if os.path.exists(path):
            return path
    raise InstallError("Can't find the live system image to copy. Is this the live session?")


def unmount_all():
    subprocess.run(["umount", "-R", TARGET], capture_output=True)


def install(request):
    validate(request)
    disk = request["disk"]
    squashfs = find_squashfs()
    unmount_all()

    progress(2, f"Erasing {disk}")
    for part in subprocess.run(["lsblk", "-n", "-l", "-o", "PATH", disk], capture_output=True, text=True).stdout.split():
        subprocess.run(["umount", part], capture_output=True)
        subprocess.run(["swapoff", part], capture_output=True)
    run("wipefs", "-a", disk)
    run("sgdisk", "--zap-all", disk)
    run("sgdisk", "-n", "1:0:+1M", "-t", "1:ef02", "-c", "1:bios",
        "-n", "2:0:+512M", "-t", "2:ef00", "-c", "2:efi",
        "-n", "3:0:0", "-t", "3:8304", "-c", "3:freemac", disk)
    run("partprobe", disk)
    run("udevadm", "settle")
    time.sleep(1)
    efi, root = partition_path(disk, 2), partition_path(disk, 3)

    progress(6, "Formatting")
    run("mkfs.vfat", "-F", "32", "-n", "EFI", efi)
    run("mkfs.ext4", "-F", "-q", "-L", "freemac", root)
    os.makedirs(TARGET, exist_ok=True)
    run("mount", root, TARGET)

    progress(10, "Copying freemac to the disk (this is the long part)")
    copy_system(squashfs)

    progress(70, "Setting up the boot partition")
    os.makedirs(os.path.join(TARGET, "boot/efi"), exist_ok=True)
    run("mount", efi, os.path.join(TARGET, "boot/efi"))
    for fs in ("dev", "dev/pts", "proc", "sys", "run"):
        os.makedirs(os.path.join(TARGET, fs), exist_ok=True)
    run("mount", "--bind", "/dev", os.path.join(TARGET, "dev"))
    run("mount", "--bind", "/dev/pts", os.path.join(TARGET, "dev/pts"))
    run("mount", "-t", "proc", "proc", os.path.join(TARGET, "proc"))
    run("mount", "-t", "sysfs", "sys", os.path.join(TARGET, "sys"))
    run("mount", "-t", "tmpfs", "tmpfs", os.path.join(TARGET, "run"))
    if os.path.isdir("/sys/firmware/efi/efivars"):
        subprocess.run(["mount", "-t", "efivarfs", "efivarfs", os.path.join(TARGET, "sys/firmware/efi/efivars")],
                       capture_output=True)

    write_fstab(root, efi)

    progress(74, "Creating your account")
    configure_system(request)

    progress(80, "Removing live-session parts")
    remove_live_bits(request)

    progress(86, "Preparing the boot files")
    kernel_version = prepare_kernel()

    progress(92, "Installing the boot loader")
    install_bootloader(disk, kernel_version)

    progress(98, "Finishing")
    run("sync")
    unmount_all()
    progress(100, "freemac is installed")


def copy_system(squashfs):
    """Unpack the pristine live image (not the running session's changes)."""
    proc = subprocess.Popen(["unsquashfs", "-f", "-d", TARGET, "-percentage", squashfs],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    last = -1
    for line in proc.stdout:
        line = line.strip()
        if line.isdigit():
            percent = 10 + int(line) * 60 // 100
            if percent != last:
                progress(percent, "Copying freemac to the disk")
                last = percent
    if proc.wait() != 0:
        raise InstallError("Copying the system failed: " + proc.stderr.read().strip()[-400:])


def uuid_of(device):
    return run("blkid", "-s", "UUID", "-o", "value", device).strip()


def write_fstab(root, efi):
    with open(os.path.join(TARGET, "etc/fstab"), "w") as f:
        f.write("# freemac: created by the installer\n")
        f.write(f"UUID={uuid_of(root)}  /          ext4  errors=remount-ro  0  1\n")
        f.write(f"UUID={uuid_of(efi)}  /boot/efi  vfat  umask=0077         0  1\n")


def configure_system(request):
    user, host = request["username"], request["hostname"]
    with open(os.path.join(TARGET, "etc/hostname"), "w") as f:
        f.write(host + "\n")
    with open(os.path.join(TARGET, "etc/hosts"), "w") as f:
        f.write(f"127.0.0.1\tlocalhost\n127.0.1.1\t{host}\n::1\tlocalhost ip6-localhost ip6-loopback\n")
    zone = os.path.join(TARGET, "etc/localtime")
    if os.path.lexists(zone):
        os.remove(zone)
    os.symlink(f"/usr/share/zoneinfo/{request['timezone']}", zone)
    with open(os.path.join(TARGET, "etc/timezone"), "w") as f:
        f.write(request["timezone"] + "\n")

    # Replace the live user with the person's own account.
    if subprocess.run(["chroot", TARGET, "id", "freemac"], capture_output=True).returncode == 0:
        run("userdel", "-r", "freemac", chroot=True)
    groups = [g for g in ("sudo", "audio", "video", "render", "input", "plugdev", "netdev", "bluetooth", "lpadmin")
              if subprocess.run(["chroot", TARGET, "getent", "group", g], capture_output=True).returncode == 0]
    run("useradd", "--create-home", "--shell", "/bin/bash", "--user-group", "--groups", ",".join(groups),
        "--comment", request.get("fullname") or user, user, chroot=True)
    run("chpasswd", stdin=f"{user}:{request['password']}\n", chroot=True)
    run("passwd", "--lock", "root", chroot=True)

    greetd = os.path.join(TARGET, "etc/greetd/config.toml")
    with open(greetd, "w") as f:
        f.write("# freemac: written by the installer.\n[terminal]\nvt = 7\n\n")
        f.write("[default_session]\n# Gangway, freemac's login screen, in the cage kiosk compositor.\n")
        f.write('command = "cage -s -- freemac-gangway"\nuser = "_greetd"\n')
        if request.get("autologin"):
            f.write(f'\n[initial_session]\ncommand = "/usr/local/bin/freemac-session"\nuser = "{user}"\n')


def remove_live_bits(_request):
    for path in ("etc/sudoers.d/freemac-live",
                 "etc/systemd/system/getty@tty1.service.d/autologin.conf",
                 "etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf",
                 "usr/share/applications/freemac-keel.desktop"):
        full = os.path.join(TARGET, path)
        if os.path.exists(full):
            os.remove(full)
    with open(os.path.join(TARGET, "etc/motd"), "w") as f:
        f.write("\nWelcome to freemac. Your desktop is on VT 7 (Ctrl+Alt+F7).\n\n")
    installed = [p for p in LIVE_PACKAGES
                 if subprocess.run(["chroot", TARGET, "dpkg", "-s", p], capture_output=True).returncode == 0]
    if installed:
        run("dpkg", "--purge", *installed, chroot=True)


def prepare_kernel():
    modules = sorted(os.listdir(os.path.join(TARGET, "lib/modules")))
    if not modules:
        raise InstallError("The system image has no kernel modules.")
    version = modules[-1]
    vmlinuz = os.path.join(TARGET, "boot", f"vmlinuz-{version}")
    if not os.path.exists(vmlinuz):
        for source in ("/run/live/medium/live/vmlinuz", "/lib/live/mount/medium/live/vmlinuz"):
            if os.path.exists(source):
                shutil.copy(source, vmlinuz)
                break
    # Rebuild the initramfs now that live-boot is gone, so it boots from disk.
    mode = "-u" if os.path.exists(os.path.join(TARGET, "boot", f"initrd.img-{version}")) else "-c"
    run("update-initramfs", mode, "-k", version, chroot=True)
    return version


def install_bootloader(disk, _version):
    grub_default = os.path.join(TARGET, "etc/default/grub")
    os.makedirs(os.path.dirname(grub_default), exist_ok=True)
    with open(grub_default, "w") as f:
        # Straight to the start-up screen, like a Mac: the menu shows only
        # while Esc or Shift is held, and the kernel and systemd keep quiet.
        f.write('GRUB_DEFAULT=0\nGRUB_TIMEOUT_STYLE=hidden\nGRUB_TIMEOUT=2\nGRUB_DISTRIBUTOR="freemac"\n'
                'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 rd.udev.log_level=3 '
                'systemd.show_status=false vt.global_cursor_default=0"\nGRUB_CMDLINE_LINUX=""\n'
                'GRUB_DISABLE_OS_PROBER=true\n')
    # Both firmware types: BIOS boot code in the protective MBR and an EFI
    # loader at the removable-media path every UEFI firmware looks for.
    run("grub-install", "--target=i386-pc", "--recheck", disk, chroot=True)
    run("grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi", "--bootloader-id=freemac",
        "--removable", "--no-nvram", chroot=True)
    if os.path.isdir("/sys/firmware/efi/efivars"):
        # Also register a named boot entry; not fatal if the firmware refuses.
        subprocess.run(["chroot", TARGET, "grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi",
                        "--bootloader-id=freemac"], capture_output=True)
    run("grub-mkconfig", "-o", "/boot/grub/grub.cfg", chroot=True)


def main():
    if os.geteuid() != 0:
        print("ERROR The installer must run as root.", flush=True)
        sys.exit(1)
    if len(sys.argv) > 1 and sys.argv[1] == "--list-disks":
        print(json.dumps(disks()))
        return
    try:
        request = json.loads(sys.stdin.read())
        install(request)
    except (InstallError, ValueError, KeyError) as err:
        unmount_all()
        print(f"ERROR {err}", flush=True)
        sys.exit(1)
    print("DONE", flush=True)
