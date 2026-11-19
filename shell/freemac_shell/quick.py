# SPDX-License-Identifier: GPL-3.0-or-later
"""Quick settings: one panel from Topline for the switches people reach for
most. Wi-Fi, Bluetooth, Do Not Disturb, dark mode and night light as tiles,
with brightness and volume sliders under them. A tile is left out when the
computer doesn't have the thing (no Wi-Fi card, no Bluetooth adapter), and so
is a slider (no backlight, no sound server).
"""
import re
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import beacon, screen, style  # noqa: E402
from .status import NM, StatusButton, launch  # noqa: E402

CSS = b"""
.quick-panel { padding: 12px; }
.quick-tile { padding: 8px 10px; border-radius: 12px; min-width: 150px; }
.quick-tile:checked { background-image: none; background-color: #4b5fc4; color: white; }
.quick-tile:checked .dim-label { color: rgba(255, 255, 255, 0.8); }
.quick-tile-title { font-weight: bold; }
"""


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


class Tile(Gtk.ToggleButton):
    def __init__(self, icon, title, on_toggle):
        super().__init__()
        self.get_style_context().add_class("quick-tile")
        box = Gtk.Box(spacing=10)
        box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        heading = Gtk.Label(label=title, xalign=0)
        heading.get_style_context().add_class("quick-tile-title")
        self.detail = Gtk.Label(xalign=0, ellipsize=3, max_width_chars=14)
        self.detail.get_style_context().add_class("dim-label")
        text.pack_start(heading, False, False, 0)
        text.pack_start(self.detail, False, False, 0)
        box.pack_start(text, True, True, 0)
        self.add(box)
        self.handler = self.connect("toggled", lambda b: on_toggle(b.get_active()))

    def show_state(self, on, detail=None):
        with self.handler_block(self.handler):
            self.set_active(on)
        self.detail.set_text(detail or ("On" if on else "Off"))


class QuickSettings(StatusButton):
    def __init__(self):
        super().__init__()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.nm = None
        if NM:
            try:
                self.nm = NM.Client.new(None)
            except GLib.Error:
                self.nm = None
        try:
            self.system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        except GLib.Error:
            self.system = None

        # Like the volume slider, the panel is a layer-shell window of its own
        # because Topline's window is only as tall as the bar.
        self.popup = Gtk.Window(title="Quick Settings")
        style.make_transparent(self.popup)
        GtkLayerShell.init_for_window(self.popup)
        GtkLayerShell.set_layer(self.popup, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self.popup, "freemac-quick-settings")
        GtkLayerShell.set_anchor(self.popup, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.popup, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self.popup, GtkLayerShell.Edge.TOP, 32)
        GtkLayerShell.set_margin(self.popup, GtkLayerShell.Edge.RIGHT, 8)
        GtkLayerShell.set_keyboard_mode(self.popup, GtkLayerShell.KeyboardMode.ON_DEMAND)
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        panel.get_style_context().add_class("topline-popup")
        panel.get_style_context().add_class("quick-panel")
        self.popup.add(panel)

        self.wifi = Tile("network-wireless-symbolic", "Wi-Fi", self._set_wifi)
        self.bluetooth = Tile("bluetooth-active-symbolic", "Bluetooth", self._set_bluetooth)
        self.dnd = Tile("notifications-disabled-symbolic", "Do Not Disturb", self._set_dnd)
        self.dark = Tile("weather-clear-night-symbolic", "Dark Mode", self._set_dark)
        self.night = Tile("night-light-symbolic", "Night Light", self._set_night)
        self.tiles = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=2,
                                 min_children_per_line=2, homogeneous=True, column_spacing=8, row_spacing=8)
        for tile in (self.wifi, self.bluetooth, self.dnd, self.dark, self.night):
            self.tiles.add(tile)
        panel.pack_start(self.tiles, False, False, 0)

        self.brightness_row, self.brightness = self._slider("display-brightness-symbolic", 5, 100,
                                                            lambda v: screen.set_brightness(v / 100))
        self.volume_row, self.volume = self._slider("audio-volume-high-symbolic", 0, 100, self._set_volume)
        panel.pack_start(self.brightness_row, False, False, 0)
        panel.pack_start(self.volume_row, False, False, 0)
        more = Gtk.Button(label="Settings…", relief=Gtk.ReliefStyle.NONE, halign=Gtk.Align.END)
        more.connect("clicked", lambda *_: (self.popup.hide(), launch("freemac-dials")))
        panel.pack_start(more, False, False, 0)
        panel.show_all()

        self.popup.connect("key-press-event", self._popup_key)
        self.popup.connect("leave-notify-event", self._popup_leave)
        self.popup.connect("enter-notify-event", self._popup_enter)
        self.close_timer = None
        self.connect("clicked", self._toggle)
        self.show_icon("emblem-system-symbolic", "Quick settings")

    def _slider(self, icon, low, high, on_change):
        line = Gtk.Box(spacing=8)
        line.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, low, high, 1)
        scale.set_draw_value(False)
        scale.handler = scale.connect("value-changed", lambda s: on_change(s.get_value()))
        line.pack_start(scale, True, True, 0)
        line.set_no_show_all(True)
        scale.show()
        line.get_children()[0].show()
        return line, scale

    @staticmethod
    def _put(scale, value):
        with scale.handler_block(scale.handler):
            scale.set_value(value)

    # -- reading the state -----------------------------------------------------
    def refresh(self):
        wifi_devices = [d for d in (self.nm.get_devices() if self.nm else [])
                        if d.get_device_type() == NM.DeviceType.WIFI]
        self._child(self.wifi).set_visible(bool(wifi_devices))
        if wifi_devices:
            on = self.nm.wireless_get_enabled()
            ap = wifi_devices[0].get_active_access_point()
            ssid = ap.get_ssid() if ap else None
            name = NM.utils_ssid_to_utf8(ssid.get_data()) if ssid else None
            self.wifi.show_state(on, name if on and name else None)

        adapter = self._adapter()
        self._child(self.bluetooth).set_visible(adapter is not None)
        if adapter:
            self.bluetooth.show_state(adapter[1])

        self.dnd.show_state(bool(style.prefs().get("dnd")))
        self.dark.show_state(style.is_dark())
        night = screen.night_settings()
        self.night.show_state(night["on"], f"{night['from']} to {night['to']}" if night["on"] else None)

        level = screen.brightness()
        self.brightness_row.set_visible(level is not None)
        if level is not None:
            self._put(self.brightness, round(level * 100))
        volume = self._volume()
        self.volume_row.set_visible(volume is not None)
        if volume is not None:
            self._put(self.volume, volume)

    @staticmethod
    def _child(tile):
        return tile.get_parent()   # the FlowBoxChild that holds it

    def _adapter(self):
        """(object path, powered) of the first Bluetooth adapter, or None."""
        if not self.system:
            return None
        try:
            objects = self.system.call_sync("org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
                                            "GetManagedObjects", None, None, Gio.DBusCallFlags.NO_AUTO_START,
                                            1000, None).unpack()[0]
        except GLib.Error:
            return None
        for path, interfaces in sorted(objects.items()):
            if "org.bluez.Adapter1" in interfaces:
                return path, bool(interfaces["org.bluez.Adapter1"].get("Powered"))
        return None

    @staticmethod
    def _volume():
        if not shutil.which("wpctl"):
            return None
        match = re.search(r"Volume:\s*([\d.]+)", run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"))
        return round(float(match.group(1)) * 100) if match else None

    # -- changing it -----------------------------------------------------------
    def _set_wifi(self, on):
        run("nmcli", "radio", "wifi", "on" if on else "off")
        GLib.timeout_add(800, lambda: self.refresh() or False)

    def _set_bluetooth(self, on):
        adapter = self._adapter()
        if adapter:
            try:
                self.system.call_sync("org.bluez", adapter[0], "org.freedesktop.DBus.Properties", "Set",
                                      GLib.Variant("(ssv)", ("org.bluez.Adapter1", "Powered", GLib.Variant("b", on))),
                                      None, Gio.DBusCallFlags.NONE, 3000, None)
            except GLib.Error:
                pass
        self.refresh()

    def _set_dnd(self, on):
        beacon.write_pref("dnd", on)
        self.refresh()

    def _set_dark(self, on):
        # Dials does the whole switch: GTK theme, title bars and wallpaper.
        launch("freemac-dials", "--appearance", "dark" if on else "light")
        self.dark.detail.set_text("On" if on else "Off")

    def _set_night(self, on):
        settings = screen.night_settings()
        settings["on"] = on
        screen.save_night_settings(settings)
        self.refresh()

    def _set_volume(self, value):
        run("wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", f"{int(value)}%")

    # -- the panel -------------------------------------------------------------
    def _toggle(self, *_args):
        if self.popup.get_visible():
            self.popup.hide()
            return
        self.refresh()
        self.popup.show()
        self._popup_leave()

    def _popup_key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.popup.hide()
        return False

    def _popup_enter(self, *_args):
        if self.close_timer:
            GLib.source_remove(self.close_timer)
            self.close_timer = None

    def _popup_leave(self, _window=None, event=None):
        if event is not None and event.detail == Gdk.NotifyType.INFERIOR:
            return
        self._popup_enter()
        self.close_timer = GLib.timeout_add(2500, self._auto_close)

    def _auto_close(self):
        self.close_timer = None
        self.popup.hide()
        return False
