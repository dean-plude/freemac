# SPDX-License-Identifier: GPL-3.0-or-later
"""Status icons for Topline: network, sound and battery.

Each one hides itself when the computer doesn't have the thing it shows (no
battery on a desktop PC, no sound server, no NetworkManager).
"""
import glob
import os
import re
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

try:
    gi.require_version("NM", "1.0")
    from gi.repository import NM  # noqa: E402
except (ValueError, ImportError):
    NM = None


def launch(*cmd):
    subprocess.Popen(cmd, start_new_session=True)


class StatusButton(Gtk.Button):
    def __init__(self):
        super().__init__()
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.image = Gtk.Image()
        self.set_image(self.image)
        self.set_no_show_all(True)
        self.shown = None

    def show_icon(self, icon, tooltip):
        # Redraw only when something changed; the bar polls every few seconds.
        if self.shown == (icon, tooltip) and self.get_visible():
            return
        self.shown = (icon, tooltip)
        self.image.set_from_icon_name(icon, Gtk.IconSize.MENU)
        self.set_tooltip_text(tooltip)
        self.show()
        self.image.show()


class Network(StatusButton):
    def __init__(self):
        super().__init__()
        self.connect("clicked", lambda *_: launch("freemac-dials", "--panel", "network"))
        self.client = None
        if NM:
            try:
                self.client = NM.Client.new(None)
            except GLib.Error:
                self.client = None
        if self.client:
            for signal in ("notify::primary-connection", "notify::state", "notify::connectivity"):
                self.client.connect(signal, lambda *_: self.update())
        GLib.timeout_add_seconds(20, lambda: self.update() or True)
        self.update()

    def update(self):
        if not self.client:
            self.hide()
            return
        active = self.client.get_primary_connection()
        if not active:
            self.show_icon("network-offline-symbolic", "Not connected")
            return
        kind = active.get_connection_type()
        name = active.get_id()
        if kind == "802-11-wireless":
            strength = 0
            for device in active.get_devices():
                ap = device.get_active_access_point() if hasattr(device, "get_active_access_point") else None
                if ap:
                    strength = ap.get_strength()
            level = "excellent" if strength > 75 else "good" if strength > 50 else "ok" if strength > 25 else "weak"
            self.show_icon(f"network-wireless-signal-{level}-symbolic", f"Wi-Fi: {name}")
        else:
            self.show_icon("network-wired-symbolic", f"Wired: {name}")


class Sound(StatusButton):
    """Volume through WirePlumber's wpctl; scroll or click to change it."""

    def __init__(self):
        super().__init__()
        # The bar is at the top of the screen, so the popover opens downwards.
        self.popover = Gtk.Popover(relative_to=self, position=Gtk.PositionType.BOTTOM)
        box = Gtk.Box(spacing=8, margin=10)
        self.mute = Gtk.ToggleButton()
        self.mute.set_image(Gtk.Image.new_from_icon_name("audio-volume-muted-symbolic", Gtk.IconSize.MENU))
        self.mute.set_tooltip_text("Mute")
        self.mute_handler = self.mute.connect("toggled", self._mute)
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 5)
        self.scale.set_draw_value(False)
        self.scale.set_size_request(180, -1)
        self.scale_handler = self.scale.connect("value-changed", self._set_volume)
        box.pack_start(self.mute, False, False, 0)
        box.pack_start(self.scale, True, True, 0)
        box.show_all()
        self.popover.add(box)
        self.connect("clicked", lambda *_: self.update() or self.popover.popup())
        self.add_events(1 << 21)  # scroll
        self.connect("scroll-event", self._scroll)
        GLib.timeout_add_seconds(10, lambda: self.update() or True)
        self.update()

    def read(self):
        if not shutil.which("wpctl"):
            return None
        try:
            out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], capture_output=True,
                                 text=True, timeout=2).stdout
        except (OSError, subprocess.SubprocessError):
            return None
        match = re.search(r"Volume:\s*([\d.]+)", out)
        return (round(float(match.group(1)) * 100), "MUTED" in out) if match else None

    def update(self):
        state = self.read()
        if state is None:
            self.hide()
            return
        volume, muted = state
        level = "muted" if muted or volume == 0 else "low" if volume < 34 else "medium" if volume < 67 else "high"
        self.show_icon(f"audio-volume-{level}-symbolic", "Muted" if muted else f"Volume {volume}%")
        if round(self.scale.get_value()) != volume:
            with self.scale.handler_block(self.scale_handler):
                self.scale.set_value(volume)
        if self.mute.get_active() != muted:
            with self.mute.handler_block(self.mute_handler):
                self.mute.set_active(muted)

    def _set_volume(self, scale):
        subprocess.run(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", f"{int(scale.get_value())}%"],
                       capture_output=True)
        self.update()

    def _mute(self, button):
        subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1" if button.get_active() else "0"],
                       capture_output=True)
        self.update()

    def _scroll(self, _widget, event):
        from gi.repository import Gdk

        step = "5%+" if event.direction == Gdk.ScrollDirection.UP else "5%-"
        if event.direction in (Gdk.ScrollDirection.UP, Gdk.ScrollDirection.DOWN):
            subprocess.run(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", step], capture_output=True)
            self.update()
        return True


class Battery(StatusButton):
    def __init__(self):
        super().__init__()
        self.set_always_show_image(True)
        GLib.timeout_add_seconds(30, lambda: self.update() or True)
        self.update()

    def update(self):
        batteries = [b for b in glob.glob("/sys/class/power_supply/*")
                     if self._read(b, "type") == "Battery" and self._read(b, "present") != "0"]
        if not batteries:
            self.hide()
            return
        capacity = int(self._read(batteries[0], "capacity") or 0)
        charging = self._read(batteries[0], "status") in ("Charging", "Full")
        level = min(100, max(0, round(capacity / 10) * 10))
        icon = f"battery-level-{level}{'-charging' if charging else ''}-symbolic"
        self.show_icon(icon, f"Battery {capacity}%{' (charging)' if charging else ''}")
        if self.get_label() != f"{capacity}%":
            self.set_label(f"{capacity}%")

    @staticmethod
    def _read(path, name):
        try:
            with open(os.path.join(path, name)) as f:
                return f.read().strip()
        except OSError:
            return None
