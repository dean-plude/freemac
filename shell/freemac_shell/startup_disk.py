# SPDX-License-Identifier: GPL-3.0-or-later
"""The systems this computer can start up from, as a Mac's Startup Disk
settings show them: freemac, Windows on another disk, another Linux, a USB
stick or a disc.

On a PC with UEFI firmware the list is the firmware's own boot entries, read
with efibootmgr (reading needs no password). Choosing one for good puts it
first in BootOrder; choosing it just once sets BootNext, which the firmware
uses for the next start-up only. Both are done by
/usr/libexec/freemac-startup-disk as root. Network boot and the firmware's
own tools (its shell, its setup screen) are left out, since nobody means to
start up from them.

Original freemac code.
"""
import os
import re
import subprocess

EFI = "/sys/firmware/efi"
ENTRY = re.compile(r"^Boot([0-9A-Fa-f]{4})(\*?)\s+(.*)$")

# What each kind is called and shown as.
KINDS = {
    "freemac": ("drive-harddisk", "freemac"),
    "windows": ("drive-harddisk", "Windows"),
    "linux": ("drive-harddisk", "Linux"),
    "disk": ("drive-harddisk", ""),
    "usb": ("drive-removable-media-usb", "USB"),
    "disc": ("media-optical", "Disc"),
}
LINUX_NAMES = ("ubuntu", "debian", "fedora", "opensuse", "arch", "mint", "pop", "elementary", "manjaro",
               "zorin", "linux", "grub", "centos", "rocky", "alma", "kali", "endeavour", "nixos")

# Words in the names firmware gives USB sticks it found by itself.
USB_NAMES = ("usb", "flash", "sandisk", "cruzer", "kingston", "datatraveler", "lexar", "transcend", "pny",
             "verbatim", "jetflash", "ultra fit", "thumb", "pen drive", "pendrive")


def has_uefi():
    return os.path.isdir(EFI)


def _efibootmgr(*args):
    try:
        return subprocess.run(["efibootmgr", *args], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def _words(text, *words):
    return any(re.search(r"\b" + word + r"\b", text) for word in words)


def kind_of(name, path):
    """What an entry starts: freemac, windows, linux, disk, usb or disc;
    None for the network and the firmware's own tools."""
    low, dev = name.lower(), path.upper()
    if any(word in dev for word in ("MAC(", "IPV4(", "IPV6(", "URI(")) or \
            _words(low, "pxe", "network", "ipv4", "ipv6", "http boot", "lan"):
        return None
    if "FV(" in dev or "FVVOL(" in dev or "FVFILE(" in dev or \
            _words(low, "uiapp", "shell", "setup", "boot menu", "boot manager menu", "diagnostics?", "bios",
                   "firmware"):
        if "windows" not in low:
            return None
    if "freemac" in low:
        return "freemac"
    if "windows" in low:
        return "windows"
    # A system named by its maker is that system, even on a disk plugged in
    # by USB; an unnamed one is the stick or disc it's on.
    if _words(low, *LINUX_NAMES):
        return "linux"
    if "USB(" in dev or _words(low, *USB_NAMES):
        return "usb"
    if "CDROM(" in dev or any(word in low for word in ("dvd", "cd-rom", "cdrom", "optical")):
        return "disc"
    return "disk"


def parse(text):
    """{"current", "next", "order": [...], "entries": [...]} from efibootmgr's
    output. Each entry has num, name, path, active and kind."""
    info = {"current": None, "next": None, "order": [], "entries": []}
    for line in text.splitlines():
        if line.startswith("BootCurrent:"):
            info["current"] = line.split(":", 1)[1].strip().upper()
        elif line.startswith("BootNext:"):
            info["next"] = line.split(":", 1)[1].strip().upper()
        elif line.startswith("BootOrder:"):
            info["order"] = [n.strip().upper() for n in line.split(":", 1)[1].split(",") if n.strip()]
        else:
            match = ENTRY.match(line)
            if not match:
                continue
            num, star, rest = match.groups()
            name, _tab, path = rest.partition("\t")
            info["entries"].append({"num": num.upper(), "name": name.strip(), "path": path.strip(),
                                    "active": bool(star), "kind": kind_of(name.strip(), path)})
    return info


def read():
    """The boot entries worth showing, in BootOrder, with which is the default
    (the first of them in BootOrder), which is running now and which is set
    for the next start-up only. None when the computer has no UEFI."""
    if not has_uefi():
        return None
    info = parse(_efibootmgr())
    order = {num: i for i, num in enumerate(info["order"])}
    shown = [e for e in info["entries"] if e["kind"] and e["active"]]
    # A live USB stick's entry is often only the firmware's own, as is the
    # drive freemac runs from; keep the one running now whatever it is.
    current = next((e for e in info["entries"] if e["num"] == info["current"]), None)
    if current and current not in shown:
        current = dict(current, kind=current["kind"] or "disk")
        shown.append(current)
    shown.sort(key=lambda e: order.get(e["num"], len(order)))
    default = shown[0]["num"] if shown else None
    for entry in shown:
        entry["default"] = entry["num"] == default
        entry["current"] = entry["num"] == info["current"]
        entry["once"] = entry["num"] == info["next"]
        entry["title"] = title(entry)
    return shown


def title(entry):
    """A name a person would know: "Windows" rather than "Windows Boot
    Manager", "freemac" for ours."""
    kind = entry["kind"]
    if kind == "freemac":
        return "freemac"
    if kind == "windows":
        return "Windows"
    name = entry["name"]
    name = re.sub(r"^UEFI( OS)?:?\s*", "", name).strip() or name
    name = re.sub(r",?\s+(Partition \d+|PART\d+)$", "", name, flags=re.I).strip(" ,")
    if kind == "linux" and name.islower():
        name = name.capitalize()
    return name or KINDS[kind][1] or "Disk"


# Used when the icon theme has no USB stick or disc of its own.
FALLBACK = {"drive-removable-media-usb": "drive-removable-media", "media-optical": "drive-optical"}


def icon(entry):
    return KINDS.get(entry["kind"], KINDS["disk"])[0]
