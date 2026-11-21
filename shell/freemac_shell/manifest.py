# SPDX-License-Identifier: GPL-3.0-or-later
"""Manifest: about this computer.

A small window with the computer at a glance (processor, graphics, memory,
storage and the version of freemac), and a full report of what is inside:
processor, memory, disks, graphics and displays, USB devices, network,
sound, battery and software. The report can be copied or saved as text.

Everything is read from files the system already shows to every user
(/proc, /sys, /etc/os-release) and from lsblk and lscpu; nothing needs a
password. Original freemac code.
"""
import json
import os
import platform
import re
import socket
import subprocess
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Manifest"
MARK = "/usr/share/freemac/freemac-mark.svg"
PCI_VENDORS = {"0x8086": "Intel", "0x1002": "AMD", "0x10de": "NVIDIA", "0x1af4": "Red Hat VirtIO",
               "0x15ad": "VMware", "0x80ee": "VirtualBox", "0x1234": "QEMU", "0x1b36": "QEMU",
               "0x1414": "Microsoft", "0x5143": "Qualcomm", "0x14e4": "Broadcom", "0x10ec": "Realtek",
               "0x168c": "Qualcomm Atheros", "0x1022": "AMD"}


def read(path, default=""):
    try:
        with open(path, errors="replace") as f:
            return f.read().strip()
    except OSError:
        return default


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def size_text(n):
    """Bytes as a size people read: 512 GB, 1.5 TB, 640 MB."""
    n = float(n)
    for unit in ("bytes", "KB", "MB", "GB", "TB", "PB"):
        if n < 1000 or unit == "PB":
            if unit == "bytes":
                return f"{int(n)} bytes"
            return f"{n:.0f} {unit}" if n >= 100 else f"{n:.1f} {unit}".replace(".0 ", " ")
        n /= 1000


def os_release():
    info = {}
    for line in read("/etc/os-release").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            info[key] = value.strip().strip('"')
    return info


def freemac_version():
    version = read("/usr/share/freemac/VERSION")
    if version:
        return version
    info = os_release()
    if info.get("ID") == "freemac" or "freemac" in info.get("NAME", "").lower():
        return info.get("VERSION", "")
    return ""


# What's inside ---------------------------------------------------------------

def computer():
    vendor = read("/sys/class/dmi/id/sys_vendor")
    product = read("/sys/class/dmi/id/product_name")
    version = read("/sys/class/dmi/id/product_version")
    junk = ("to be filled by o.e.m.", "system product name", "default string", "none", "not applicable")
    parts = [p for p in (vendor, product) if p and p.lower() not in junk]
    name = re.sub(r"\s*\([^)]*\)", "", " ".join(parts)).strip() if parts else "PC"
    return name, version if version and version.lower() not in junk else ""


def processor():
    info = read("/proc/cpuinfo")
    model = re.search(r"model name\s*:\s*(.+)", info)
    model = re.sub(r"\s+", " ", model.group(1)).strip() if model else platform.processor() or platform.machine()
    threads = os.cpu_count() or 1
    cores = threads
    lscpu = run(["lscpu", "-J"])
    details = {}
    try:
        for entry in json.loads(lscpu).get("lscpu", []):
            details[entry.get("field", "").rstrip(":")] = entry.get("data", "")
    except ValueError:
        pass
    try:
        per_core = int(details.get("Thread(s) per core", 1))
        cores = max(1, threads // max(1, per_core))
    except ValueError:
        pass
    return model, cores, threads, details


def memory():
    info = {}
    for line in read("/proc/meminfo").splitlines():
        key, _, value = line.partition(":")
        match = re.match(r"\s*(\d+)", value)
        if match:
            info[key] = int(match.group(1)) * 1024
    return info


def disks():
    out = run(["lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,MODEL,TRAN,RM,ROTA,FSTYPE,MOUNTPOINT,LABEL"])
    try:
        devices = json.loads(out).get("blockdevices", [])
    except ValueError:
        devices = []
    return [d for d in devices if d.get("type") in ("disk", "rom") and int(d.get("size") or 0) >= 1_000_000
            and not str(d.get("name", "")).startswith(("loop", "zram", "fd"))]


def volumes():
    seen, found = set(), []
    for line in read("/proc/mounts").splitlines():
        parts = line.split()
        if len(parts) < 3 or not parts[0].startswith("/dev/") or parts[1] in seen:
            continue
        if parts[2] in ("squashfs", "iso9660") or parts[1].startswith(("/snap", "/boot/efi", "/run/live")):
            continue
        seen.add(parts[1])
        try:
            st = os.statvfs(parts[1].replace("\\040", " "))
        except OSError:
            continue
        found.append((parts[1].replace("\\040", " "), parts[0], parts[2], st.f_blocks * st.f_frsize,
                      st.f_bavail * st.f_frsize))
    return found


def pci_name(device_dir):
    slot = os.path.basename(os.path.realpath(device_dir))
    line = run(["lspci", "-mm", "-s", slot]).strip()
    fields = re.findall(r'"([^"]*)"', line)
    if len(fields) >= 3:
        vendor = fields[1].replace(" Corporation", "").replace(", Inc.", "").replace(" Inc.", "")
        return f"{vendor} {fields[2]}".strip()
    vendor = read(os.path.join(device_dir, "vendor"))
    return f"{PCI_VENDORS.get(vendor, vendor or 'Unknown')} graphics ({read(os.path.join(device_dir, 'device'))})"


def graphics():
    cards = []
    try:
        names = sorted(n for n in os.listdir("/sys/class/drm") if re.fullmatch(r"card\d+", n))
    except OSError:
        names = []
    for name in names:
        device = os.path.join("/sys/class/drm", name, "device")
        driver = os.path.basename(os.path.realpath(os.path.join(device, "driver")))
        vram = read(os.path.join(device, "mem_info_vram_total"))
        cards.append({"name": pci_name(device), "driver": driver if driver != "driver" else "",
                      "memory": size_text(int(vram)) if vram.isdigit() else ""})
    return cards


def displays():
    found = []
    try:
        names = sorted(os.listdir("/sys/class/drm"))
    except OSError:
        names = []
    for name in names:
        path = os.path.join("/sys/class/drm", name)
        if "-" not in name or read(os.path.join(path, "status")) != "connected":
            continue
        modes = read(os.path.join(path, "modes")).splitlines()
        port = name.split("-", 1)[1]
        kind = "Built-in display" if port.startswith(("eDP", "LVDS", "DSI")) else "Display"
        found.append({"name": kind, "port": port, "resolution": modes[0] if modes else ""})
    return found


def usb_devices():
    found = []
    base = "/sys/bus/usb/devices"
    try:
        names = sorted(os.listdir(base))
    except OSError:
        names = []
    speeds = {"1.5": "1.5 Mb/s (low speed)", "12": "12 Mb/s (full speed)", "480": "480 Mb/s (USB 2)",
              "5000": "5 Gb/s (USB 3)", "10000": "10 Gb/s (USB 3.1)", "20000": "20 Gb/s (USB 3.2)"}
    for name in names:
        path = os.path.join(base, name)
        if ":" in name or name.startswith("usb"):
            continue          # interfaces and the controllers themselves
        product = read(os.path.join(path, "product"))
        maker = read(os.path.join(path, "manufacturer"))
        if not product and not maker:
            continue
        found.append({"name": product or "USB device", "maker": maker,
                      "id": f"{read(os.path.join(path, 'idVendor'))}:{read(os.path.join(path, 'idProduct'))}",
                      "speed": speeds.get(read(os.path.join(path, "speed")), read(os.path.join(path, "speed")))})
    return found


def network():
    addresses = {}
    try:
        for entry in json.loads(run(["ip", "-j", "addr"]) or "[]"):
            addresses[entry.get("ifname")] = [a.get("local", "") + "/" + str(a.get("prefixlen", ""))
                                              for a in entry.get("addr_info", [])]
    except ValueError:
        pass
    found = []
    try:
        names = sorted(os.listdir("/sys/class/net"))
    except OSError:
        names = []
    for name in names:
        if name == "lo":
            continue
        path = os.path.join("/sys/class/net", name)
        if not os.path.exists(os.path.join(path, "device")) and not os.path.isdir(os.path.join(path, "wireless")):
            continue          # bridges and other made-up interfaces
        wireless = os.path.isdir(os.path.join(path, "wireless"))
        speed = read(os.path.join(path, "speed"))
        found.append({"name": name, "kind": "Wi-Fi" if wireless else "Ethernet",
                      "state": "Connected" if read(os.path.join(path, "operstate")) == "up" else "Not connected",
                      "hardware": read(os.path.join(path, "address")),
                      "speed": f"{speed} Mb/s" if speed.isdigit() and int(speed) > 0 else "",
                      "addresses": ", ".join(addresses.get(name, []))})
    return found


def sound():
    cards = []
    for line in read("/proc/asound/cards").splitlines():
        match = re.match(r"\s*\d+\s+\[[^\]]*\]:\s*(.+?)\s+-\s+(.+)", line)
        if match:
            cards.append(match.group(2).strip())
    return cards


def batteries():
    found = []
    base = "/sys/class/power_supply"
    try:
        names = sorted(os.listdir(base))
    except OSError:
        names = []
    for name in names:
        path = os.path.join(base, name)
        if read(os.path.join(path, "type")) != "Battery" or read(os.path.join(path, "scope")) == "Device":
            continue
        full = read(os.path.join(path, "energy_full")) or read(os.path.join(path, "charge_full"))
        design = read(os.path.join(path, "energy_full_design")) or read(os.path.join(path, "charge_full_design"))
        health = ""
        if full.isdigit() and design.isdigit() and int(design):
            health = f"{min(100, round(int(full) * 100 / int(design)))}% of when it was new"
        found.append({"charge": (read(os.path.join(path, "capacity")) + "%") if read(os.path.join(path, "capacity"))
                      else "", "state": read(os.path.join(path, "status")), "health": health,
                      "cycles": read(os.path.join(path, "cycle_count")),
                      "maker": " ".join(p for p in (read(os.path.join(path, "manufacturer")),
                                                    read(os.path.join(path, "model_name"))) if p)})
    return found


def uptime_text():
    try:
        seconds = int(float(read("/proc/uptime").split()[0]))
    except (IndexError, ValueError):
        return ""
    days, rest = divmod(seconds, 86400)
    hours, rest = divmod(rest, 3600)
    minutes = rest // 60
    parts = []
    if days:
        parts.append(f"{days} day{'s' if days != 1 else ''}")
    if hours:
        parts.append(f"{hours} hour{'s' if hours != 1 else ''}")
    if not days:
        parts.append(f"{minutes} minute{'s' if minutes != 1 else ''}")
    return ", ".join(parts)


def report():
    """The full report: [(section, [(heading or None, [(label, value)])])]."""
    sections = []
    name, model_version = computer()
    cpu, cores, threads, details = processor()
    mem = memory()
    release = os_release()
    sections.append(("Hardware", [(None, [
        ("Computer", name), ("Model version", model_version),
        ("Processor", cpu), ("Cores", f"{cores} cores, {threads} threads" if threads != cores else f"{cores} cores"),
        ("Memory", size_text(mem.get("MemTotal", 0)) if mem else ""),
        ("Firmware", " ".join(p for p in (read("/sys/class/dmi/id/bios_vendor"),
                                          read("/sys/class/dmi/id/bios_version")) if p)),
        ("Firmware date", read("/sys/class/dmi/id/bios_date")),
        ("Starts with", "UEFI" if os.path.isdir("/sys/firmware/efi") else "BIOS"),
    ])]))
    sections.append(("Processor", [(None, [
        ("Name", cpu), ("Architecture", details.get("Architecture", platform.machine())),
        ("Cores", str(cores)), ("Threads", str(threads)),
        ("Top speed", f"{float(details['CPU max MHz']) / 1000:.2f} GHz" if details.get("CPU max MHz", "").replace(
            ".", "", 1).isdigit() else ""),
        ("Cache (L3)", details.get("L3 cache", "")), ("Virtualization", details.get("Virtualization", "")),
        ("Running in", details.get("Hypervisor vendor", "")),
    ])]))
    sections.append(("Memory", [(None, [
        ("Installed", size_text(mem.get("MemTotal", 0))), ("Available now", size_text(mem.get("MemAvailable", 0))),
        ("Swap", size_text(mem.get("SwapTotal", 0)) if mem.get("SwapTotal") else "None"),
    ])]))
    storage = []
    for disk in disks():
        kind = "Optical drive" if disk.get("type") == "rom" else "USB" if disk.get("tran") == "usb" else \
            "Removable" if disk.get("rm") in (True, "1", 1) else \
            "Hard disk" if disk.get("rota") in (True, "1", 1) else "Solid state"
        storage.append(((disk.get("model") or "").strip() or disk.get("name"), [
            ("Size", size_text(disk.get("size") or 0)), ("Kind", kind),
            ("Connection", (disk.get("tran") or "").upper()), ("Device", "/dev/" + disk.get("name", "")),
        ]))
    found = volumes()
    if not any(v[0] == "/" for v in found):
        try:
            st = os.statvfs("/")
            found.insert(0, ("/", "in memory (running from the installer)", "overlay",
                             st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize))
        except OSError:
            pass
    for mount, device, fstype, total, free in found:
        storage.append(("Volume " + ("“Computer”" if mount == "/" else mount), [
            ("Capacity", size_text(total)), ("Free", size_text(free)), ("Format", fstype), ("Device", device),
        ]))
    sections.append(("Storage", storage or [(None, [("Disks", "None found")])]))
    shown = [(card["name"], [("Driver", card["driver"]), ("Memory", card["memory"])]) for card in graphics()]
    shown += [(d["name"], [("Connected to", d["port"]), ("Resolution", d["resolution"].replace("x", " × "))])
              for d in displays()]
    sections.append(("Graphics and Displays", shown or [(None, [("Graphics", "None found")])]))
    sections.append(("USB", [(d["name"], [("Made by", d["maker"]), ("Speed", d["speed"]), ("ID", d["id"])])
                             for d in usb_devices()] or [(None, [("Devices", "Nothing plugged in")])]))
    sections.append(("Network", [(f"{n['kind']} ({n['name']})", [
        ("State", n["state"]), ("Speed", n["speed"]), ("Addresses", n["addresses"]),
        ("Hardware address", n["hardware"])]) for n in network()] or [(None, [("Network", "None found")])]))
    sections.append(("Sound", [(None, [("Sound card", c) for c in sound()] or [("Sound card", "None found")])]))
    sections.append(("Battery", [(n["maker"] or "Battery", [
        ("Charge", n["charge"]), ("State", n["state"]), ("Health", n["health"]), ("Charge cycles", n["cycles"])])
        for n in batteries()] or [(None, [("Battery", "None (this computer runs on mains power)")])]))
    sections.append(("Software", [(None, [
        ("System", f"freemac {freemac_version()}".strip()), ("Based on", release.get("UBUNTU_CODENAME") and
                                                             f"Ubuntu ({release['UBUNTU_CODENAME']})" or ""),
        ("Kernel", platform.release()), ("Computer name", socket.gethostname()),
        ("User", os.environ.get("USER", "")), ("Time since start", uptime_text()),
        ("Desktop", "Wayfire with freemac's shell"),
    ])]))
    return [(title, [(h, [(k, v) for k, v in rows if v]) for h, rows in groups]) for title, groups in sections]


def report_text(sections):
    lines = [f"freemac system report, {time.strftime('%Y-%m-%d %H:%M')}", ""]
    for title, groups in sections:
        lines.append(title.upper())
        for heading, rows in groups:
            if heading:
                lines.append(f"  {heading}")
            for key, value in rows:
                lines.append(f"    {key}: {value}" if heading else f"  {key}: {value}")
        lines.append("")
    return "\n".join(lines)


# Windows ---------------------------------------------------------------------

def info_grid(rows, label_width=None, selectable=True):
    grid = Gtk.Grid(column_spacing=14, row_spacing=6)
    for n, (key, value) in enumerate(rows):
        left = Gtk.Label(label=key, xalign=1, yalign=0)
        left.get_style_context().add_class("dim-label")
        if label_width:
            left.set_size_request(label_width, -1)
        right = Gtk.Label(label=value, xalign=0, yalign=0, selectable=selectable, wrap=True,
                          wrap_mode=Pango.WrapMode.WORD_CHAR, max_width_chars=60)
        right.set_hexpand(True)
        grid.attach(left, 0, n, 1, 1)
        grid.attach(right, 1, n, 1, 1)
    return grid


class Overview(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="About This Computer", resizable=False)
        header = Gtk.HeaderBar(show_close_button=True)
        header.set_title("")
        self.set_titlebar(header)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_border_width(26)
        box.set_size_request(380, -1)
        self.add(box)
        mark = Gtk.Image()
        try:
            mark.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_size(MARK, 112, 112))
        except GLib.Error:
            mark.set_from_icon_name("freemac-welcome", Gtk.IconSize.DIALOG)
            mark.set_pixel_size(112)
        box.pack_start(mark, False, False, 4)
        title = Gtk.Label()
        title.set_markup("<span size='24000' weight='700'>freemac</span>")
        box.pack_start(title, False, False, 0)
        version = Gtk.Label(label=f"Version {freemac_version()}" if freemac_version() else "")
        version.get_style_context().add_class("dim-label")
        box.pack_start(version, False, False, 0)
        name, _model = computer()
        cpu, cores, _threads, _details = processor()
        mem = memory()
        cards = graphics()
        try:
            st = os.statvfs("/")
            root = (st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize)
        except OSError:
            root = None
        rows = [("Computer", name), ("Processor", f"{cpu} ({cores} cores)"),
                ("Graphics", cards[0]["name"] if cards else "Unknown"),
                ("Memory", size_text(mem.get("MemTotal", 0)) if mem else "Unknown")]
        if root:
            rows.append(("Storage", f"{size_text(root[1])} free of {size_text(root[0])}"))
        rows.append(("Name", socket.gethostname()))
        grid = info_grid(rows, label_width=90, selectable=False)
        grid.set_margin_top(18)
        grid.set_halign(Gtk.Align.CENTER)
        box.pack_start(grid, False, False, 0)
        more = Gtk.Button(label="More Info…")
        more.set_halign(Gtk.Align.CENTER)
        more.set_margin_top(18)
        more.set_action_name("app.report")
        box.pack_start(more, False, False, 0)
        legal = Gtk.Label(label="Free software under the GNU GPL, version 3 or later.\n"
                                "freemac is not macOS and contains nothing from Apple.",
                          justify=Gtk.Justification.CENTER)
        legal.get_style_context().add_class("dim-label")
        legal.set_margin_top(14)
        attrs = Pango.AttrList()
        attrs.insert(Pango.attr_scale_new(0.85))
        legal.set_attributes(attrs)
        box.pack_start(legal, False, False, 0)
        menus.add_actions(self, {"close": self.close})
        self.show_all()


class Report(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="System Report")
        self.set_default_size(860, 580)
        header = Gtk.HeaderBar(show_close_button=True, title="System Report")
        self.set_titlebar(header)
        copy = Gtk.Button(label="Copy")
        copy.set_action_name("win.copy")
        copy.set_tooltip_text("Copy the whole report as text")
        header.pack_end(copy)
        refresh = Gtk.Button(label="Refresh")
        refresh.set_action_name("win.refresh")
        header.pack_end(refresh)
        body = Gtk.Box()
        self.add(body)
        self.list = Gtk.ListBox()
        self.list.get_style_context().add_class("sidebar")
        self.list.set_size_request(200, -1)
        self.list.connect("row-selected", self._chosen)
        side = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side.add(self.list)
        side.set_hexpand(False)
        body.pack_start(side, False, False, 0)
        body.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        self.pane = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.pane.set_hexpand(True)
        body.pack_start(self.pane, True, True, 0)
        menus.add_actions(self, {"copy": self.copy, "save": self.save, "refresh": self.refresh, "close": self.close})
        self.sections = []
        self.show_all()
        self.refresh()

    def refresh(self):
        row = self.list.get_selected_row()
        index = row.get_index() if row else 0
        self.sections = report()
        for child in self.list.get_children():
            self.list.remove(child)
        for title, _groups in self.sections:
            label = Gtk.Label(label=title, xalign=0)
            label.set_margin_start(14)
            label.set_margin_top(7)
            label.set_margin_bottom(7)
            row = Gtk.ListBoxRow()
            row.add(label)
            row.show_all()
            self.list.add(row)
        self.list.select_row(self.list.get_row_at_index(index))

    def _chosen(self, _list, row):
        if not row:
            return
        title, groups = self.sections[row.get_index()]
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_border_width(22)
        heading = Gtk.Label(xalign=0)
        heading.set_markup(f"<span size='16000' weight='700'>{GLib.markup_escape_text(title)}</span>")
        box.pack_start(heading, False, False, 4)
        for sub, rows in groups:
            if sub:
                label = Gtk.Label(xalign=0)
                label.set_markup(f"<b>{GLib.markup_escape_text(sub)}</b>")
                label.set_margin_top(10)
                box.pack_start(label, False, False, 0)
            if rows:
                grid = info_grid(rows, label_width=150)
                grid.set_margin_start(6)
                box.pack_start(grid, False, False, 0)
        old = self.pane.get_child()
        if old:
            self.pane.remove(old)
        self.pane.add(box)
        box.show_all()

    def copy(self):
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(report_text(self.sections), -1)

    def save(self):
        chooser = Gtk.FileChooserNative.new("Save Report", self, Gtk.FileChooserAction.SAVE, "Save", "Cancel")
        chooser.set_current_name(f"System Report {time.strftime('%Y-%m-%d')}.txt")
        chooser.set_do_overwrite_confirmation(True)
        docs = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOCUMENTS)
        if docs and os.path.isdir(docs):
            chooser.set_current_folder(docs)
        if chooser.run() == Gtk.ResponseType.ACCEPT:
            try:
                with open(chooser.get_filename(), "w") as f:
                    f.write(report_text(self.sections))
            except OSError as err:
                dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK,
                                           message_type=Gtk.MessageType.WARNING, text="The report couldn't be saved.")
                dialog.format_secondary_text(err.strerror or str(err))
                dialog.run()
                dialog.destroy()
        chooser.destroy()


def menubar():
    return menus.menubar([
        ("_File", [[("System Report…", "app.report", "<Ctrl>r")], [("Save Report…", "win.save", "<Ctrl>s")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Copy Report", "win.copy", None)]]),
    ])


class Manifest(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.overview = None
        self.report_window = None
        self.want_report = "--report" in sys.argv

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": self.quit, "report": self.show_report, "about": self.show_overview})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_accels_for_action("app.report", ["<Control>r"])
        self.set_accels_for_action("win.save", ["<Control>s"])
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.want_report:
            self.want_report = False
            self.show_report()
        else:
            self.show_overview()

    def show_overview(self):
        if self.overview is None:
            self.overview = Overview(self)
            self.overview.connect("destroy", lambda _w: setattr(self, "overview", None))
        self.overview.present()

    def show_report(self):
        if self.report_window is None:
            self.report_window = Report(self)
            self.report_window.connect("destroy", lambda _w: setattr(self, "report_window", None))
        self.report_window.present()


def main():
    GLib.set_prgname("freemac-manifest")
    args = [a for a in sys.argv if a != "--report"]
    return Manifest().run(args)


if __name__ == "__main__":
    sys.exit(main())
