# SPDX-License-Identifier: GPL-3.0-or-later
"""The Bluetooth menu in the menu bar, as on a Mac: a switch to turn
Bluetooth on or off, the devices paired with this computer (connected ones
first, with their battery when they report it), a click to connect or
disconnect one, and Bluetooth Settings for pairing a new one. The symbol
itself is status.Bluetooth; everything goes through BlueZ on the system bus.
Original freemac code.
"""
from gi.repository import Gio, GLib, Gtk

from . import beacon  # noqa: E402
from .menubar_popup import Popup  # noqa: E402
from .status import Bluetooth, launch  # noqa: E402

DEVICE_ICONS = {
    "audio-headset": "audio-headset-symbolic", "audio-headphones": "audio-headphones-symbolic",
    "audio-card": "audio-speakers-symbolic", "input-keyboard": "input-keyboard-symbolic",
    "input-mouse": "input-mouse-symbolic", "input-tablet": "input-tablet-symbolic",
    "input-gaming": "input-gaming-symbolic", "phone": "phone-symbolic",
    "computer": "computer-symbolic", "printer": "printer-symbolic",
}


def device_name(props):
    return props.get("Alias") or props.get("Name") or "Unknown Device"


def battery_words(percent):
    return f"{percent}%" if percent is not None else None


class BluetoothMenu(Bluetooth):
    def __init__(self):
        self.popup = None
        self.busy = set()           # devices being connected or disconnected
        super().__init__()
        self.popup = Popup("freemac-bluetooth")

    def update(self):
        super().update()
        if self.popup is not None and self.popup.visible():
            self.fill()

    # -- what BlueZ knows ---------------------------------------------------------

    def _props(self, obj, name):
        proxy = obj.get_interface(name)
        if proxy is None:
            return None
        return {key: self._prop(proxy, key) for key in proxy.get_cached_property_names()}

    def _adapter(self):
        """(object path, properties) of the first adapter, or None."""
        found = []
        for obj in self.manager.get_objects() if self.manager else []:
            props = self._props(obj, "org.bluez.Adapter1")
            if props is not None:
                found.append((obj.get_object_path(), props))
        return sorted(found)[0] if found else None

    def _devices(self, adapter):
        """[(path, properties, battery percent)] of the paired devices,
        connected ones first, then by name."""
        found = []
        for obj in self.manager.get_objects():
            path = obj.get_object_path()
            props = self._props(obj, "org.bluez.Device1")
            if not props or not props.get("Paired") or not path.startswith(adapter + "/"):
                continue
            battery = self._props(obj, "org.bluez.Battery1") or {}
            found.append((path, props, battery.get("Percentage")))
        return sorted(found, key=lambda d: (not d[1].get("Connected"), device_name(d[1]).lower()))

    # -- the menu -----------------------------------------------------------------

    def _clicked(self):
        if self.popup.visible():
            self.popup.hide()
            return
        if self._adapter() is None:
            launch("freemac-dials", "--panel", "bluetooth")
            return
        self.fill()
        self.popup.show_under(self)

    def fill(self):
        p = self.popup
        adapter = self._adapter()
        p.clear()
        if adapter is None:
            p.title("Bluetooth")
            p.note("This computer has no Bluetooth.")
            p.menu.show_all()
            return
        path, props = adapter
        on = bool(props.get("Powered"))
        switch = Gtk.Switch(active=on, valign=Gtk.Align.CENTER)
        switch.set_can_focus(False)
        switch.connect("notify::active", lambda s, _p: self._power(path, s.get_active()))
        p.title("Bluetooth", switch)
        if on:
            devices = self._devices(path)
            p.separator()
            if devices:
                p.heading("Devices")
                for device, info, percent in devices:
                    self._device_row(device, info, percent)
            else:
                p.note("No devices paired yet.")
        p.separator()
        p.item("Bluetooth Settings…", lambda: launch("freemac-dials", "--panel", "bluetooth"))
        p.menu.show_all()

    def _device_row(self, path, props, percent):
        connected = bool(props.get("Connected"))
        name = device_name(props)
        icon = DEVICE_ICONS.get(props.get("Icon") or "", "bluetooth-active-symbolic")
        button = self.popup.item(name, lambda: self._toggle(path, name, connected),
                                 icon=icon, round_icon=True, on=connected)
        line = button.get_child()
        if path in self.busy:
            line.pack_end(Gtk.Spinner(active=True), False, False, 0)
        elif connected and percent is not None:
            # A Mac shows the device's battery beside its name.
            level = "full" if percent > 80 else "good" if percent > 40 else "low" if percent > 15 else "caution"
            gauge = Gtk.Box(spacing=3)
            gauge.pack_start(Gtk.Label(label=battery_words(percent)), False, False, 0)
            gauge.pack_start(Gtk.Image.new_from_icon_name(f"battery-{level}-symbolic", Gtk.IconSize.MENU),
                             False, False, 0)
            gauge.get_style_context().add_class("sound-menu-heading")
            line.pack_end(gauge, False, False, 0)
        button.set_tooltip_text(f"Disconnect {name}" if connected else f"Connect {name}")

    # -- doing things -------------------------------------------------------------

    def _power(self, path, on):
        self._call(path, "org.freedesktop.DBus.Properties", "Set",
                   GLib.Variant("(ssv)", ("org.bluez.Adapter1", "Powered", GLib.Variant("b", on))),
                   lambda error: error and self._failed("Bluetooth couldn’t be turned " + ("on" if on else "off"),
                                                         error))

    def _toggle(self, path, name, connected):
        self.busy.add(path)

        def done(error):
            self.busy.discard(path)
            if error:
                self._failed(f"Couldn’t {'disconnect' if connected else 'connect'} {name}", error)
            self.update()
        self._call(path, "org.bluez.Device1", "Disconnect" if connected else "Connect", None, done, 30000)

    def _call(self, path, iface, method, args, done, timeout=5000):
        def finished(bus, result):
            try:
                bus.call_finish(result)
            except GLib.Error as e:
                Gio.DBusError.strip_remote_error(e)    # leaves just BlueZ's words
                done(e.message or "failed")
                return
            done(None)
        try:
            bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        except GLib.Error as e:
            done(e.message)
            return
        bus.call("org.bluez", path, iface, method, args, None, Gio.DBusCallFlags.NONE, timeout, None, finished)

    @staticmethod
    def _failed(title, why):
        # BlueZ's reasons ("br-connection-page-timeout") mean little to a person.
        words = "Make sure the device is on and nearby, then try again."
        if "NotReady" in (why or "") or "not ready" in (why or "").lower():
            words = "Bluetooth isn’t ready yet. Try again in a moment."
        beacon.send(title, words, "bluetooth-disabled-symbolic", "Bluetooth")
