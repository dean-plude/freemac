# SPDX-License-Identifier: GPL-3.0-or-later
"""The Wi-Fi menu, as on a Mac: click the Wi-Fi symbol in the menu bar to turn
Wi-Fi on or off, see the network you're on and join another, without opening
Dials. Hold Option (Alt) while clicking for the details of the connection:
its address, router, security, channel, signal and speed.

A computer with no Wi-Fi keeps the plain symbol, which opens Dials > Network.

Everything goes through NetworkManager (libnm), so a password typed here goes
straight to it and never appears on a command line. Original freemac code.
"""
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import alert, beacon, style  # noqa: E402

try:
    gi.require_version("NM", "1.0")
    from gi.repository import NM  # noqa: E402
except (ValueError, ImportError):
    NM = None

WIDTH = 290
MOST = 10           # other networks listed


def launch(*cmd):
    subprocess.Popen(cmd, start_new_session=True)


def ssid_of(ap):
    raw = ap.get_ssid() if ap else None
    return NM.utils_ssid_to_utf8(raw.get_data()) if raw else ""


def security_of(ap):
    """The kind of password a network asks for, in a Mac's words, or None."""
    if ap is None:
        return None
    rsn, wpa = ap.get_rsn_flags(), ap.get_wpa_flags()
    if rsn or wpa:
        flags = rsn | wpa
        enterprise = flags & getattr(NM, "80211ApSecurityFlags").KEY_MGMT_802_1X
        sae = flags & getattr(NM, "80211ApSecurityFlags").KEY_MGMT_SAE
        if enterprise:
            return "WPA2 Enterprise" if rsn else "WPA Enterprise"
        if sae:
            return "WPA3 Personal"
        return "WPA2 Personal" if rsn else "WPA Personal"
    if ap.get_flags() & getattr(NM, "80211ApFlags").PRIVACY:
        return "WEP"
    return None


def level_of(strength):
    return "excellent" if strength > 75 else "good" if strength > 50 else "ok" if strength > 25 else "weak"


def channel_words(frequency):
    """'6 (2.4 GHz)' from a frequency in MHz."""
    if not frequency:
        return "—"
    channel = NM.utils_wifi_freq_to_channel(frequency)
    band = "2.4 GHz" if frequency < 3000 else "5 GHz" if frequency < 5925 else "6 GHz"
    return f"{channel} ({band})"


def signal_dbm(iface):
    """The signal in dBm from /proc/net/wireless, as a Mac shows it, or None."""
    try:
        with open("/proc/net/wireless") as f:
            for line in f:
                name, _sep, rest = line.partition(":")
                if name.strip() == iface:
                    level = float(rest.split()[2].rstrip("."))
                    return int(level) if level < 0 else None
    except (OSError, ValueError, IndexError):
        pass
    return None


def saved_for(client, ssid):
    """NetworkManager's saved connection for this network, or None."""
    for connection in client.get_connections():
        setting = connection.get_setting_wireless()
        if setting and setting.get_ssid() and NM.utils_ssid_to_utf8(setting.get_ssid().get_data()) == ssid:
            return connection
    return None


def ask_password(ssid, security, done):
    """The Mac's join window: a password for this network. done(password) or
    nothing if it's cancelled."""
    kind = (security or "WPA2").replace(" Personal", "")
    dialog = alert.build(None, f"The Wi-Fi network “{ssid}” requires a {kind} password.",
                         "", [("Cancel", Gtk.ResponseType.CANCEL), ("Join", Gtk.ResponseType.OK)],
                         default=Gtk.ResponseType.OK, icon="network-wireless-symbolic")
    dialog.set_title(f"Join “{ssid}”")
    fields = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    for side in ("start", "end"):
        getattr(fields, "set_margin_" + side)(16)
    entry = Gtk.Entry(visibility=False, activates_default=True, placeholder_text="Password")
    fields.pack_start(entry, False, False, 0)
    show = Gtk.CheckButton(label="Show password")
    show.connect("toggled", lambda c: entry.set_visibility(c.get_active()))
    fields.pack_start(show, False, False, 0)
    area = dialog.get_content_area()
    body = area.get_children()[0] if area.get_children() else area
    # Under the question, above the buttons.
    body.pack_start(fields, False, False, 0)
    body.reorder_child(fields, len(body.get_children()) - 2)
    buttons = body.get_children()[-1].get_children() if body is not area else []
    join = next((b for b in buttons if b.get_style_context().has_class("suggested-action")), None)

    def long_enough():
        # WPA passwords are 8 to 63 characters; WEP keys can be 5.
        return len(entry.get_text()) >= (5 if security == "WEP" else 8)

    def typed(*_args):
        if join is not None:
            join.set_sensitive(long_enough())
    entry.connect("changed", typed)
    typed()

    def answered(_dialog, response):
        if response == Gtk.ResponseType.OK and not long_enough():
            return              # Return with too short a password: keep asking
        password = entry.get_text()
        dialog.destroy()
        if response == Gtk.ResponseType.OK:
            done(password)
    dialog.connect("response", answered)
    dialog.set_keep_above(True)
    dialog.show_all()
    entry.grab_focus()
    dialog.present()
    return dialog


class WifiMenu(Gtk.Button):
    """The Wi-Fi (or wired) symbol in the menu bar, with its menu."""

    def __init__(self):
        super().__init__()
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.image = Gtk.Image()
        self.set_image(self.image)
        self.set_no_show_all(True)
        self.shown = None
        self.details = False
        self.client = None
        if NM:
            try:
                self.client = NM.Client.new(None)
            except GLib.Error:
                self.client = None
        if self.client:
            for signal in ("notify::primary-connection", "notify::state", "notify::connectivity",
                           "notify::wireless-enabled", "device-added", "device-removed"):
                self.client.connect(signal, lambda *_: self._soon())
        self.watched = set()
        self.timer = None
        self._build_popup()
        self.connect("clicked", self._clicked)
        GLib.timeout_add_seconds(20, lambda: self.update() or True)
        self.update()

    # -- the symbol in the menu bar -------------------------------------------

    def wifi(self):
        """The first Wi-Fi device, or None."""
        if not self.client:
            return None
        for device in self.client.get_devices():
            # An unmanaged one is in some other program's hands (a hotspot,
            # say), not the computer's own Wi-Fi.
            if device.get_device_type() == NM.DeviceType.WIFI and device.get_managed():
                if device not in self.watched:
                    self.watched.add(device)
                    for signal in ("access-point-added", "access-point-removed", "notify::active-access-point",
                                   "state-changed"):
                        device.connect(signal, lambda *_: self._soon())
                return device
        return None

    def _soon(self):
        if self.timer is None:
            self.timer = GLib.timeout_add(250, self._later)

    def _later(self):
        self.timer = None
        self.update()
        if self.popup.get_visible():
            self.fill()
        return False

    def _show_icon(self, icon, tooltip):
        if self.shown == (icon, tooltip) and self.get_visible():
            return
        self.shown = (icon, tooltip)
        self.image.set_from_icon_name(icon, Gtk.IconSize.MENU)
        self.set_tooltip_text(tooltip)
        self.show()
        self.image.show()

    def update(self):
        if not self.client:
            self.hide()
            return
        device = self.wifi()
        active = self.client.get_primary_connection()
        kind = active.get_connection_type() if active else None
        # The Wi-Fi symbol whenever Wi-Fi is joined, as on a Mac, even while a
        # cable is the way out; the cable's symbol only when it is all there is.
        joined = device is not None and device.get_active_access_point() is not None
        if device is not None and (kind is None or kind == "802-11-wireless" or joined):
            if not self.client.wireless_get_enabled():
                self._show_icon("network-wireless-disabled-symbolic", "Wi-Fi: Off")
                return
            ap = device.get_active_access_point()
            if ap is None:
                self._show_icon("network-wireless-offline-symbolic", "Wi-Fi: Not connected")
                return
            self._show_icon(f"network-wireless-signal-{level_of(ap.get_strength())}-symbolic",
                            f"Wi-Fi: {ssid_of(ap)}")
            return
        if active is None:
            self._show_icon("network-offline-symbolic", "Not connected")
        elif kind == "802-11-wireless":
            self._show_icon("network-wireless-signal-good-symbolic", f"Wi-Fi: {active.get_id()}")
        else:
            self._show_icon("network-wired-symbolic", f"Wired: {active.get_id()}")

    # -- the menu ---------------------------------------------------------------

    def _build_popup(self):
        # As with the Sound menu, a small layer-shell window of its own, since
        # Topline's window is only as tall as the bar.
        self.popup = Gtk.Window(title="Wi-Fi")
        style.make_transparent(self.popup)
        GtkLayerShell.init_for_window(self.popup)
        GtkLayerShell.set_layer(self.popup, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self.popup, "freemac-wifi")
        GtkLayerShell.set_anchor(self.popup, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.popup, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self.popup, GtkLayerShell.Edge.TOP, 32)
        GtkLayerShell.set_keyboard_mode(self.popup, GtkLayerShell.KeyboardMode.ON_DEMAND)
        self.menu = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.menu.get_style_context().add_class("topline-popup")
        self.menu.get_style_context().add_class("sound-menu")
        self.menu.set_size_request(WIDTH, -1)
        top = Gtk.Box(spacing=8)
        title = Gtk.Label(label="Wi-Fi", xalign=0)
        title.get_style_context().add_class("sound-menu-title")
        top.pack_start(title, True, True, 0)
        self.switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.switch.set_can_focus(False)
        self.switch_handler = self.switch.connect("notify::active", self._switched)
        top.pack_end(self.switch, False, False, 6)
        self.menu.pack_start(top, False, False, 0)
        self.rows = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.menu.pack_start(self.rows, False, False, 0)
        self.menu.pack_start(Gtk.Separator(), False, False, 4)
        settings = self._item("Wi-Fi Settings…", lambda: launch("freemac-dials", "--panel", "network"))
        self.menu.pack_start(settings, False, False, 0)
        self.popup.add(self.menu)
        self.menu.show_all()
        self.popup.connect("key-press-event", self._popup_key)
        self.popup.connect("leave-notify-event", self._popup_leave)
        self.popup.connect("enter-notify-event", self._popup_enter)
        # A pointer already over the menu when it appears gets no enter
        # event, so moving in it also keeps it open.
        self.popup.add_events(Gdk.EventMask.POINTER_MOTION_MASK)
        self.popup.connect("motion-notify-event", self._popup_enter)
        self.close_timer = None
        self.plan = None

    def _item(self, words, action):
        button = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
        button.add(Gtk.Label(label=words, xalign=0))
        button.get_style_context().add_class("sound-menu-item")
        button.connect("clicked", lambda *_: (self.popup.hide(), action()))
        return button

    def _heading(self, words):
        label = Gtk.Label(label=words, xalign=0)
        label.get_style_context().add_class("sound-menu-heading")
        return label

    def _clicked(self, *_args):
        if self.popup.get_visible():
            self.popup.hide()
            return
        device = self.wifi()
        if device is None:
            launch("freemac-dials", "--panel", "network")
            return
        ok, state = Gtk.get_current_event_state()
        self.details = bool(ok and state & Gdk.ModifierType.MOD1_MASK)
        if self.client.wireless_get_enabled():
            device.request_scan_async(None, None, None)
        self.fill(force=True)
        top = self.get_toplevel()
        alloc = self.get_allocation()
        x, _y = self.translate_coordinates(top, 0, 0)
        right = top.get_allocated_width() - (x + alloc.width // 2) - WIDTH // 2
        GtkLayerShell.set_margin(self.popup, GtkLayerShell.Edge.RIGHT, max(8, right))
        self.popup.show()
        self._popup_leave()

    def fill(self, force=False):
        """Lay out the menu's rows. While it's open, NetworkManager reports each
        scan result and change of strength, so the rows are rebuilt only when
        what they show changes: a row replaced under the pointer would swallow
        the click on it."""
        device = self.wifi()
        on = bool(self.client and self.client.wireless_get_enabled())
        with self.switch.handler_block(self.switch_handler):
            self.switch.set_active(on)
        active = here = joining = None
        best = {}
        if device is not None and on:
            active = device.get_active_access_point()
            here = ssid_of(active) if active else None
            if device.get_state() in (NM.DeviceState.PREPARE, NM.DeviceState.CONFIG, NM.DeviceState.NEED_AUTH,
                                      NM.DeviceState.IP_CONFIG, NM.DeviceState.IP_CHECK):
                connection = device.get_active_connection()
                joining = connection.get_id() if connection else None
            for ap in device.get_access_points():
                ssid = ssid_of(ap)
                if ssid and (ssid not in best or ap.get_strength() > best[ssid].get_strength()):
                    best[ssid] = ap

        def by_strength(names):
            return sorted(names, key=lambda s: -best[s].get_strength())
        known = by_strength(s for s in best if s != here and saved_for(self.client, s) is not None)
        others = by_strength(s for s in best if s != here and s not in known)[:MOST]
        plan = (device is not None, on, here, joining, self.details,
                tuple((s, level_of(best[s].get_strength()), security_of(best[s]) is not None)
                      for s in [here] * bool(here) + known + others))
        if plan == self.plan and not force:
            return
        self.plan = plan
        for child in self.rows.get_children():
            child.destroy()
        if device is None or not on:
            self.rows.show_all()
            return
        if here or known:
            self.rows.pack_start(Gtk.Separator(), False, False, 4)
            self.rows.pack_start(self._heading("Known Network" if len(known) + bool(here) == 1
                                               else "Known Networks"), False, False, 0)
            if here:
                self.rows.pack_start(self._network(device, active, current=True), False, False, 0)
                if self.details:
                    self._add_details(device, active)
            for ssid in known:
                self.rows.pack_start(self._network(device, best[ssid], joining=ssid == joining), False, False, 0)
        if others:
            self.rows.pack_start(Gtk.Separator(), False, False, 4)
            self.rows.pack_start(self._heading("Other Networks"), False, False, 0)
            for ssid in others:
                self.rows.pack_start(self._network(device, best[ssid], joining=ssid == joining), False, False, 0)
        if not best:
            self.rows.pack_start(Gtk.Separator(), False, False, 4)
            looking = Gtk.Label(label="Looking for networks…", xalign=0)
            looking.get_style_context().add_class("sound-menu-heading")
            self.rows.pack_start(looking, False, False, 0)
        if self.details and here:
            self.rows.pack_start(Gtk.Separator(), False, False, 4)
            self.rows.pack_start(self._item(f"Disconnect from “{here}”", lambda: device.disconnect_async(None, None, None)),
                                 False, False, 0)
        self.rows.show_all()

    def _network(self, device, ap, current=False, joining=False):
        ssid = ssid_of(ap)
        button = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
        button.get_style_context().add_class("sound-menu-item")
        line = Gtk.Box(spacing=10)
        symbol = Gtk.Image.new_from_icon_name(f"network-wireless-signal-{level_of(ap.get_strength())}-symbolic",
                                              Gtk.IconSize.MENU)
        symbol.get_style_context().add_class("sound-device")
        if current:
            symbol.get_style_context().add_class("sound-device-on")
        line.pack_start(symbol, False, False, 0)
        line.pack_start(Gtk.Label(label=ssid, xalign=0, ellipsize=3, max_width_chars=24), True, True, 0)
        if joining:
            spinner = Gtk.Spinner(active=True)
            line.pack_end(spinner, False, False, 0)
        elif security_of(ap):
            lock = Gtk.Image.new_from_icon_name("changes-prevent-symbolic", Gtk.IconSize.MENU)
            lock.set_opacity(0.6)
            lock.set_tooltip_text(security_of(ap))
            line.pack_end(lock, False, False, 0)
        button.add(line)
        if current:
            # The network you're on shows its details (what Option-click shows on
            # a Mac; the menu bar can't always see the Option key here).
            button.connect("clicked", lambda *_: self._toggle_details())
        else:
            button.connect("clicked", lambda *_: (self.popup.hide(), self.join(device, ap)))
        return button

    def _toggle_details(self):
        self.details = not self.details
        self.fill(force=True)

    def _add_details(self, device, ap):
        """Option-click: what a Mac lists under the network you're on."""
        config = device.get_ip4_config()
        address = config.get_addresses()[0].get_address() if config and config.get_addresses() else "—"
        router = (config.get_gateway() if config else None) or "—"
        dbm = signal_dbm(device.get_iface())
        rate = device.get_bitrate()
        facts = [
            ("IP Address", address),
            ("Router", router),
            ("Security", security_of(ap) or "None"),
            ("BSSID", (ap.get_bssid() or "—").lower()),
            ("Channel", channel_words(ap.get_frequency())),
            ("Signal", f"{dbm} dBm" if dbm is not None else f"{ap.get_strength()}%"),
            ("Tx Rate", f"{rate // 1000} Mbps" if rate else "—"),
        ]
        grid = Gtk.Grid(column_spacing=8, row_spacing=1)
        grid.set_margin_start(44)
        for row, (name, value) in enumerate(facts):
            label = Gtk.Label(label=f"{name}:", xalign=0)
            label.get_style_context().add_class("sound-menu-heading")
            grid.attach(label, 0, row, 1, 1)
            data = Gtk.Label(label=value, xalign=0, selectable=False)
            data.get_style_context().add_class("sound-menu-heading")
            grid.attach(data, 1, row, 1, 1)
        self.rows.pack_start(grid, False, False, 2)

    def _switched(self, switch, _param):
        if not switch.get_active():
            for child in self.rows.get_children():
                child.destroy()
            self.plan = None
        if self.client:
            subprocess.Popen(["nmcli", "radio", "wifi", "on" if switch.get_active() else "off"],
                             start_new_session=True)
        GLib.timeout_add(600, self._later)

    # -- joining ----------------------------------------------------------------

    def join(self, device, ap):
        ssid = ssid_of(ap)
        saved = saved_for(self.client, ssid)
        if saved is not None:
            self.client.activate_connection_async(saved, device, ap.get_path(), None, self._activated, (ssid, None))
            return
        security = security_of(ap)
        if security is None:
            self._add(device, ap, ssid, None, None)
        elif "Enterprise" in security:
            # A school's or office's network asks for a user name too: Dials handles it.
            launch("freemac-dials", "--panel", "network")
        else:
            ask_password(ssid, security, lambda password: self._add(device, ap, ssid, security, password))

    def _add(self, device, ap, ssid, security, password):
        connection = NM.SimpleConnection.new()
        if password is not None:
            secure = NM.SettingWirelessSecurity.new()
            if security == "WEP":
                secure.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT, "none")
                secure.set_property(NM.SETTING_WIRELESS_SECURITY_WEP_KEY0, password)
            else:
                secure.set_property(NM.SETTING_WIRELESS_SECURITY_KEY_MGMT,
                                    "sae" if security == "WPA3 Personal" else "wpa-psk")
                secure.set_property(NM.SETTING_WIRELESS_SECURITY_PSK, password)
            connection.add_setting(secure)
        self.client.add_and_activate_connection_async(connection, device, ap.get_path(), None,
                                                      self._added, (ssid, password is not None))

    def _added(self, client, result, data):
        try:
            active = client.add_and_activate_connection_finish(result)
        except GLib.Error as e:
            self._failed(data[0], e.message, None)
            return
        self._watch(active, data)

    def _activated(self, client, result, data):
        try:
            active = client.activate_connection_finish(result)
        except GLib.Error as e:
            self._failed(data[0], e.message, None)
            return
        self._watch(active, data)

    def _watch(self, active, data):
        """Tell the person if joining fails; once joined, stop watching (a
        later disconnection, or turning Wi-Fi off, isn't a failed join)."""
        ssid, new = data
        self._soon()

        def changed(connection, _param=None):
            state = connection.get_state()
            if state == NM.ActiveConnectionState.ACTIVATED:
                connection.disconnect_by_func(changed)
            elif state == NM.ActiveConnectionState.DEACTIVATED:
                connection.disconnect_by_func(changed)
                if not self.client.wireless_get_enabled():
                    return
                why = connection.get_state_reason() if hasattr(connection, "get_state_reason") else None
                wrong = why in (NM.ActiveConnectionStateReason.NO_SECRETS,
                                NM.ActiveConnectionStateReason.LOGIN_FAILED) if why is not None else bool(new)
                # A password that didn't work isn't kept, so the next try asks again.
                remote = connection.get_connection()
                self._failed(ssid, "The password may be wrong." if wrong else None, remote if new else None)
        if active.get_state() == NM.ActiveConnectionState.ACTIVATED:
            return
        active.connect("notify::state", changed)

    def _failed(self, ssid, why, connection):
        if connection is not None:
            connection.delete_async(None, None, None)
        beacon.send(f"Couldn’t join “{ssid}”", why or "Move closer to the Wi-Fi router, or try again.",
                    "network-wireless-offline-symbolic", "Wi-Fi")
        self._soon()

    # -- closing ------------------------------------------------------------------

    def _popup_key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.popup.hide()
        return False

    def _popup_enter(self, *_args):
        if self.close_timer:
            GLib.source_remove(self.close_timer)
            self.close_timer = None

    def _popup_leave(self, _window=None, event=None):
        """Close a little after the pointer leaves the menu; one that opens and
        is never pointed at closes after a few seconds."""
        if event is not None and event.detail == Gdk.NotifyType.INFERIOR:
            return
        self._popup_enter()
        self.close_timer = GLib.timeout_add(2500 if event is not None else 6000, self._auto_close)

    def _auto_close(self):
        self.close_timer = None
        self.popup.hide()
        return False
