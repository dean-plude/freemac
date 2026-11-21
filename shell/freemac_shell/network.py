# SPDX-License-Identifier: GPL-3.0-or-later
"""Network panel for Dials: wired status and joining Wi-Fi through NetworkManager.

Uses libnm over D-Bus, so Wi-Fi passwords go straight to NetworkManager and
never appear on a command line.
"""
import os
import subprocess

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

from . import admin_switch  # noqa: E402

try:
    gi.require_version("NM", "1.0")
    from gi.repository import NM  # noqa: E402
except (ValueError, ImportError):
    NM = None

STATES = {}
if NM:
    STATES = {
        NM.DeviceState.ACTIVATED: "Connected",
        NM.DeviceState.DISCONNECTED: "Not connected",
        NM.DeviceState.UNAVAILABLE: "Unavailable",
        NM.DeviceState.UNMANAGED: "Not managed",
        NM.DeviceState.PREPARE: "Connecting…",
        NM.DeviceState.CONFIG: "Connecting…",
        NM.DeviceState.NEED_AUTH: "Needs a password",
        NM.DeviceState.IP_CONFIG: "Getting an address…",
        NM.DeviceState.FAILED: "Couldn’t connect",
    }


def addresses(device):
    config = device.get_ip4_config()
    return [a.get_address() for a in config.get_addresses()] if config else []


def ssid_of(ap):
    raw = ap.get_ssid()
    return NM.utils_ssid_to_utf8(raw.get_data()) if raw else ""


def is_secure(ap):
    return bool(ap.get_wpa_flags() or ap.get_rsn_flags() or
                ap.get_flags() & getattr(NM, "80211ApFlags").PRIVACY)


class NetworkPanel(Gtk.Box):
    """Builds its rows from NetworkManager and refreshes when devices change."""

    def __init__(self, make_group, make_row, make_page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.group, self.row, self.page = make_group, make_row, make_page
        self.client = None
        if NM:
            try:
                self.client = NM.Client.new(None)
            except GLib.Error:
                self.client = None
        if self.client:
            for device in self.client.get_devices():
                device.connect("state-changed", lambda *_: GLib.idle_add(self.rebuild))
                if device.get_device_type() == NM.DeviceType.WIFI:
                    device.connect("access-point-added", lambda *_: self.schedule())
                    device.connect("access-point-removed", lambda *_: self.schedule())
        self._pending = None
        self.rebuild()

    def schedule(self):
        if not self._pending:
            self._pending = GLib.timeout_add(800, self.rebuild)

    def rebuild(self):
        self._pending = None
        for child in self.get_children():
            self.remove(child)
        self.pack_start(self.page("Network", *self.sections()), True, True, 0)
        self.show_all()
        return False

    def sections(self):
        return self.network_sections() + self.firewall_sections()

    def firewall_sections(self):
        """Network > Firewall, as on a Mac: turns away connections that other
        computers start. Changing it asks for an administrator's password."""
        if not os.path.exists("/usr/sbin/ufw") or not os.path.exists(admin_switch.SYSTEM_HELPER):
            return []
        return [self.group(self.row("Firewall", admin_switch.firewall_switch(),
                                    "Turns away connections that other computers try to start. "
                                    "Browsing, mail and everything this computer starts carry on as usual."))]

    def network_sections(self):
        if not self.client:
            return [self.group(*self.fallback_rows())]
        wired, wifi = [], []
        for device in self.client.get_devices():
            kind = device.get_device_type()
            state = STATES.get(device.get_state(), device.get_state().value_nick.replace("-", " ").title())
            if kind == NM.DeviceType.ETHERNET:
                caption = ", ".join(addresses(device)) or None
                wired.append(self.row(f"Wired ({device.get_iface()})", Gtk.Label(label=state), caption))
            elif kind == NM.DeviceType.WIFI:
                wifi.append(device)
        sections = [self.group(*wired)] if wired else []
        for device in wifi:
            sections.append(self.wifi_group(device))
        if not sections:
            sections.append(self.group(self.row("No network hardware found", None)))
        return sections

    def wifi_group(self, device):
        active = device.get_active_access_point()
        active_ssid = ssid_of(active) if active else None
        scan = Gtk.Button(label="Scan")
        scan.connect("clicked", lambda _b: device.request_scan_async(None, None, None))
        header = self.row(f"Wi-Fi ({device.get_iface()})", scan,
                          f"Connected to {active_ssid}" if active_ssid else "Not connected")
        rows = [header]
        best = {}
        for ap in device.get_access_points():
            ssid = ssid_of(ap)
            if ssid and (ssid not in best or ap.get_strength() > best[ssid].get_strength()):
                best[ssid] = ap
        for ssid, ap in sorted(best.items(), key=lambda kv: -kv[1].get_strength())[:12]:
            bars = "▂▄▆█"[:max(1, round(ap.get_strength() / 25))]
            caption = f"{bars}  {'Secured' if is_secure(ap) else 'Open'}"
            if ssid == active_ssid:
                widget = Gtk.Label(label="Connected")
            else:
                widget = Gtk.Button(label="Join")
                widget.connect("clicked", lambda _b, d=device, a=ap: self.join(d, a))
            rows.append(self.row(ssid, widget, caption))
        return self.group(*rows)

    def join(self, device, ap):
        ssid = ssid_of(ap)
        # A network we've joined before has a saved connection: just use it.
        for connection in self.client.get_connections():
            setting = connection.get_setting_wireless()
            if setting and setting.get_ssid() and NM.utils_ssid_to_utf8(setting.get_ssid().get_data()) == ssid:
                self.client.activate_connection_async(connection, device, ap.get_path(), None, None, None)
                return
        connection = NM.SimpleConnection.new()
        if is_secure(ap):
            password = self.ask_password(ssid)
            if password is None:
                return
            security = NM.SettingWirelessSecurity.new()
            security.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "wpa-psk")
            security.set_property(NM.SETTING_WIRELESS_SECURITY_PSK, password)
            connection.add_setting(security)
        self.client.add_and_activate_connection_async(connection, device, ap.get_path(), None, None, None)

    def ask_password(self, ssid):
        dialog = Gtk.Dialog(title=f"Join “{ssid}”", transient_for=self.get_toplevel(), modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Join", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(12)
        box.pack_start(Gtk.Label(label="Enter the Wi-Fi password", xalign=0), False, False, 0)
        entry = Gtk.Entry(visibility=False, activates_default=True, width_chars=28)
        box.pack_start(entry, False, False, 0)
        show = Gtk.CheckButton(label="Show password")
        show.connect("toggled", lambda c: entry.set_visibility(c.get_active()))
        box.pack_start(show, False, False, 0)
        dialog.show_all()
        response = dialog.run()
        password = entry.get_text()
        dialog.destroy()
        return password if response == Gtk.ResponseType.OK and len(password) >= 8 else None

    def fallback_rows(self):
        """Without NetworkManager, show what `ip` knows."""
        rows = []
        try:
            out = subprocess.run(["ip", "-brief", "address"], capture_output=True, text=True, timeout=3).stdout
        except (OSError, subprocess.SubprocessError):
            out = ""
        for line in out.splitlines():
            parts = line.split()
            if len(parts) < 2 or parts[0] == "lo":
                continue
            found = [a.split("/")[0] for a in parts[2:]]
            state = {"UP": "Connected", "DOWN": "Not connected"}.get(parts[1], parts[1].title())
            rows.append(self.row(parts[0], Gtk.Label(label=state), ", ".join(found) or None))
        return rows or [self.row("No network connections", None)]
