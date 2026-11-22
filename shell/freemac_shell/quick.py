# SPDX-License-Identifier: GPL-3.0-or-later
"""Quick settings: one panel from Topline for the switches people reach for
most. Wi-Fi, Bluetooth, Do Not Disturb, dark mode, night light and Stage Manager as tiles,
what's playing (with back, play/pause and forward) when a player is open,
and brightness and volume sliders under them. A tile is left out when the
computer doesn't have the thing (no Wi-Fi card, no Bluetooth adapter), and so
is a slider (no backlight, no sound server).
"""
import re
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, GtkLayerShell, Pango  # noqa: E402

from . import beacon, media, screen, stage, style  # noqa: E402
from .status import NM, StatusButton, launch  # noqa: E402

CSS = b"""
.quick-panel { padding: 12px; }
.quick-panel flowbox, .quick-panel flowboxchild { background: none; }
.quick-tile { padding: 8px 10px; border-radius: 12px; min-width: 150px; }
.quick-tile:checked { background-image: none; background-color: @theme_selected_bg_color; color: white; }
.quick-tile:checked .dim-label { color: rgba(255, 255, 255, 0.8); }
.quick-tile-title { font-weight: bold; }
.now-playing { padding: 6px 4px; border-top: 1px solid alpha(currentColor, 0.12); }
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


class NowPlaying(Gtk.Box):
    """A row with the track, the app it plays in, and back / play / forward."""

    def __init__(self):
        super().__init__(spacing=8)
        self.get_style_context().add_class("now-playing")
        self.bus = media.session()
        self.player = None
        self.icon = Gtk.Image.new_from_icon_name("audio-x-generic-symbolic", Gtk.IconSize.LARGE_TOOLBAR)
        self.pack_start(self.icon, False, False, 0)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.title = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=22)
        self.title.get_style_context().add_class("quick-tile-title")
        self.subtitle = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=22)
        self.subtitle.get_style_context().add_class("dim-label")
        text.pack_start(self.title, False, False, 0)
        text.pack_start(self.subtitle, False, False, 0)
        self.pack_start(text, True, True, 0)
        self.previous = self._button("media-skip-backward-symbolic", "Previous", "previous")
        self.play = self._button("media-playback-start-symbolic", "Play", "play-pause")
        self.next = self._button("media-skip-forward-symbolic", "Next", "next")
        for button in (self.previous, self.play, self.next):
            self.pack_start(button, False, False, 0)
        self.set_no_show_all(True)
        for child in self.get_children():
            child.show_all()

    def _button(self, icon, tip, action):
        button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_tooltip_text(tip)
        button.connect("clicked", lambda *_: self._send(action))
        return button

    def _send(self, action):
        if self.player and media.send(action, self.bus, self.player["name"]):
            GLib.timeout_add(300, lambda: self.refresh() or False)

    def _show_art(self, art):
        """The album cover the player gives, or the music symbol."""
        if art == getattr(self, "art_shown", None):
            return
        self.art_shown = art
        path = Gio.File.new_for_uri(art).get_path() if art.startswith("file://") else None
        size = 32 * self.get_scale_factor()
        if path:
            try:
                picture = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True)
                surface = Gdk.cairo_surface_create_from_pixbuf(picture, self.get_scale_factor(), None)
                self.icon.set_from_surface(surface)
                return
            except GLib.Error:
                pass
        self.icon.set_from_icon_name("audio-x-generic-symbolic", Gtk.IconSize.LARGE_TOOLBAR)

    def refresh(self):
        self.player = media.current(self.bus) if self.bus else None
        self.set_visible(self.player is not None)
        if not self.player:
            return
        p = self.player
        self._show_art(p.get("art") or "")
        self.title.set_text(p["title"] or p["app"])
        self.subtitle.set_text(" · ".join(x for x in (p["artist"], p["app"]) if x and x != self.title.get_text()))
        playing = p["status"] == "Playing"
        self.play.set_image(Gtk.Image.new_from_icon_name(
            "media-playback-pause-symbolic" if playing else "media-playback-start-symbolic", Gtk.IconSize.BUTTON))
        self.play.set_tooltip_text("Pause" if playing else "Play")
        self.previous.set_sensitive(p["can_previous"])
        self.next.set_sensitive(p["can_next"])


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
        self.stage = Tile("freemac-stage-manager-symbolic", "Stage Manager", self._set_stage)
        self.tiles = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=2,
                                 min_children_per_line=2, homogeneous=True, column_spacing=8, row_spacing=8)
        for tile in (self.wifi, self.bluetooth, self.dnd, self.dark, self.night, self.stage):
            self.tiles.add(tile)
        panel.pack_start(self.tiles, False, False, 0)
        self.now_playing = NowPlaying()
        panel.pack_start(self.now_playing, False, False, 0)

        self.brightness_row, self.brightness = self._slider("display-brightness-symbolic", 5, 100,
                                                            lambda v: screen.set_brightness(v / 100))
        self.volume_row, self.volume = self._slider("audio-volume-high-symbolic", 0, 100, self._set_volume)
        if self.volume is not None:
            from . import sounds
            self.volume.connect("button-release-event", lambda *_: sounds.feedback())
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

        self.now_playing.refresh()
        self.dnd.show_state(bool(style.prefs().get("dnd")))
        self.dark.show_state(style.is_dark())
        self.stage.show_state(stage.is_on())
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

    def _set_stage(self, on):
        # The Dock watches its settings and turns Stage Manager on or off.
        stage.set_on(on)
        self.stage.detail.set_text("On" if on else "Off")

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
