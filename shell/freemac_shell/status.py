# SPDX-License-Identifier: GPL-3.0-or-later
"""Status icons for Topline: sound, battery, Bluetooth, printing, and
the dot that shows an app is using the microphone or camera.

Each one hides itself when the computer doesn't have the thing it shows (no
battery on a desktop PC, no sound server, no NetworkManager, no Bluetooth
adapter, nothing printing).
"""
import glob
import os
import re
import shutil
import subprocess

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import audio, battery, beacon, sounds, style  # noqa: E402

SOUND_MENU_WIDTH = 260

try:
    import cups  # python3-cups, which system-config-printer brings along
except ImportError:
    cups = None

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


class VPN(Gtk.MenuButton):
    """The VPN menu, as on a Mac: with a VPN configuration added in Dials >
    Network, the menu bar shows the VPN (filled while one is connected), and
    its menu connects or disconnects each. Dials can hide it (pref
    "vpn_menu"). The menu is filled as things change, not as it opens, since
    a menu that opens late is refused by the compositor."""

    def __init__(self):
        super().__init__()
        from . import vpn

        self.vpn = vpn
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.image = Gtk.Image()
        self.add(self.image)
        self.set_no_show_all(True)
        self.menu = Gtk.Menu()
        self.menu.set_halign(Gtk.Align.END)
        self.set_popup(self.menu)
        self.menu.connect("hide", lambda *_: GLib.idle_add(self._refill))
        self.shown = None
        self.client = vpn.new_client()
        if self.client:
            for signal in ("connection-added", "connection-removed",
                           "active-connection-added", "active-connection-removed"):
                self.client.connect(signal, lambda *_: GLib.timeout_add(300, self._later))
        self._prefs_monitor = style.watch_prefs(self.update)
        # A connection's own state (connecting, connected) has no client
        # signal; look every few seconds.
        GLib.timeout_add_seconds(3, lambda: self.update() or True)
        self.update()

    def _later(self):
        self.update()
        return False

    def update(self):
        configs = self.vpn.configurations(self.client)
        if not configs or not self.vpn.menu_bar_shown():
            self.shown = None
            self.menu.popdown()
            self.hide()
            return
        states = [(c.get_uuid(), c.get_id(), self.vpn.state(self.client, c)) for c in configs]
        if self.shown == states:
            return
        self.shown = states
        kinds = {s for _u, _n, s in states}
        if "connected" in kinds:
            icon = "network-vpn-symbolic"
        elif "connecting" in kinds:
            icon = "network-vpn-acquiring-symbolic"
        else:
            icon = "network-vpn-disconnected-symbolic"
        self.image.set_from_icon_name(icon, Gtk.IconSize.MENU)
        on = [n for _u, n, s in states if s == "connected"]
        self.set_tooltip_text(f"VPN: connected to {', '.join(on)}" if on else "VPN: not connected")
        if self.menu.get_visible():
            return      # refill once it closes, not under the pointer
        self.fill(configs)
        self.show()
        self.image.show()

    def fill(self, configs):
        for child in self.menu.get_children():
            self.menu.remove(child)
        for connection in configs:
            now = self.vpn.state(self.client, connection)
            status = Gtk.MenuItem(label=f"{connection.get_id()}: {self.vpn.STATE_TEXT[now]}")
            status.set_sensitive(False)
            self.menu.append(status)
            if now in ("connected", "connecting"):
                action = Gtk.MenuItem(label=f"Disconnect {connection.get_id()}")
                action.connect("activate", lambda _i, c=connection: self._off(c))
            else:
                action = Gtk.MenuItem(label=f"Connect {connection.get_id()}")
                action.connect("activate", lambda _i, c=connection: self._on(c))
            self.menu.append(action)
            self.menu.append(Gtk.SeparatorMenuItem())
        settings = Gtk.MenuItem(label="Open VPN Settings…")
        settings.connect("activate", lambda *_: launch("freemac-dials", "--panel", "network"))
        self.menu.append(settings)
        self.menu.show_all()

    def _refill(self):
        self.shown = None
        self.update()
        return False

    def _on(self, connection):
        def done(error):
            if error:
                beacon.send(f"\u201c{connection.get_id()}\u201d couldn\u2019t connect", error,
                            "network-vpn-symbolic", "VPN")
            self._refill()
        self.vpn.turn_on(self.client, connection, done)

    def _off(self, connection):
        self.vpn.turn_off(self.client, connection)
        GLib.timeout_add(500, self._refill)


class Sound(StatusButton):
    """The Sound menu, as on a Mac: the volume slider, the outputs to play
    through (click one to switch) and Sound Settings…, from the speaker in the
    menu bar. Scroll on the speaker to change the volume.

    Volume goes through audio.py, which keeps the left/right balance. Topline
    also listens for the sound server's changes (`pactl subscribe`), so the
    speaker follows the volume keys and other apps at once, and keeps mono
    audio in front of whichever output plays (audio.keep_mono)."""

    def __init__(self):
        super().__init__()
        # Topline's window is only as tall as the bar, and a GTK 3 popover
        # can't draw outside its window, so the menu is a small layer-shell
        # window of its own, placed under the icon.
        self.popup = Gtk.Window(title="Sound")
        style.make_transparent(self.popup)
        GtkLayerShell.init_for_window(self.popup)
        GtkLayerShell.set_layer(self.popup, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self.popup, "freemac-volume")
        GtkLayerShell.set_anchor(self.popup, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.popup, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self.popup, GtkLayerShell.Edge.TOP, 32)
        GtkLayerShell.set_keyboard_mode(self.popup, GtkLayerShell.KeyboardMode.ON_DEMAND)
        menu = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        menu.get_style_context().add_class("topline-popup")
        menu.get_style_context().add_class("sound-menu")
        menu.set_size_request(SOUND_MENU_WIDTH, -1)
        title = Gtk.Label(label="Sound", xalign=0)
        title.get_style_context().add_class("sound-menu-title")
        menu.pack_start(title, False, False, 0)

        box = Gtk.Box(spacing=8)
        self.mute = Gtk.ToggleButton(relief=Gtk.ReliefStyle.NONE)
        # The speaker beside the slider shows the level, as on a Mac; a click
        # mutes or unmutes.
        self.mute_image = Gtk.Image.new_from_icon_name("audio-volume-high-symbolic", Gtk.IconSize.MENU)
        self.mute.set_image(self.mute_image)
        self.mute.get_style_context().add_class("sound-mute")
        self.mute.set_can_focus(False)
        self.mute.set_tooltip_text("Mute")
        self.mute_handler = self.mute.connect("toggled", self._mute)
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 5)
        self.scale.set_draw_value(False)
        self.scale_handler = self.scale.connect("value-changed", self._set_volume)
        self.scale.connect("button-release-event", lambda *_: sounds.feedback())
        box.pack_start(self.mute, False, False, 0)
        box.pack_start(self.scale, True, True, 0)
        menu.pack_start(box, False, False, 0)

        # Output: each device as a row, the one playing in the accent colour.
        self.outputs_part = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.outputs_part.set_no_show_all(True)
        self.outputs_part.pack_start(Gtk.Separator(), False, False, 4)
        heading = Gtk.Label(label="Output", xalign=0)
        heading.get_style_context().add_class("sound-menu-heading")
        self.outputs_part.pack_start(heading, False, False, 0)
        self.output_rows = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.outputs_part.pack_start(self.output_rows, False, False, 0)
        for child in self.outputs_part.get_children():
            child.show_all()
        menu.pack_start(self.outputs_part, False, False, 0)
        self.shown_outputs = None

        menu.pack_start(Gtk.Separator(), False, False, 4)
        settings = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
        settings.add(Gtk.Label(label="Sound Settings…", xalign=0))
        settings.get_style_context().add_class("sound-menu-item")
        settings.connect("clicked", lambda *_: (self.popup.hide(), launch("freemac-dials", "--panel", "sound")))
        menu.pack_start(settings, False, False, 0)
        self.popup.add(menu)
        menu.show_all()
        self.outputs_part.hide()

        self.popup.connect("key-press-event", self._popup_key)
        self.popup.connect("leave-notify-event", self._popup_leave)
        self.popup.connect("enter-notify-event", self._popup_enter)
        # A pointer already over the menu when it appears gets no enter
        # event, so moving in it also keeps it open.
        self.popup.add_events(Gdk.EventMask.POINTER_MOTION_MASK)
        self.popup.connect("motion-notify-event", self._popup_enter)
        self.close_timer = None
        self.connect("clicked", self._toggle_popup)
        self.add_events(1 << 21)  # scroll
        self.connect("scroll-event", self._scroll)
        self.changed_timer = None
        self.listener = None
        self._listen()
        GLib.timeout_add_seconds(10, lambda: self._changed() or True)
        self._changed()

    # -- following the sound server ---------------------------------------------
    def _listen(self):
        """Hear about every change to devices and volumes from `pactl subscribe`."""
        if not audio.available():
            return False
        try:
            self.listener = Gio.Subprocess.new(["pactl", "subscribe"], Gio.SubprocessFlags.STDOUT_PIPE)
        except GLib.Error:
            self.listener = None
            return False
        lines = Gio.DataInputStream.new(self.listener.get_stdout_pipe())
        lines.read_line_async(GLib.PRIORITY_DEFAULT, None, self._heard, lines)
        return False

    def _heard(self, stream, result, lines):
        try:
            line, _length = stream.read_line_finish_utf8(result)
        except GLib.Error:
            line = None
        if line is None:
            # The sound server went away: listen again once it's back.
            self.listener = None
            GLib.timeout_add_seconds(5, self._listen)
            return
        if any(word in line for word in (" sink ", " server ", " module ", " card ")):
            if self.changed_timer:
                GLib.source_remove(self.changed_timer)
            self.changed_timer = GLib.timeout_add(200, self._changed)
        lines.read_line_async(GLib.PRIORITY_DEFAULT, None, self._heard, lines)

    def _changed(self):
        self.changed_timer = None
        audio.keep_mono()
        self.update()
        return False

    # -- the menu -----------------------------------------------------------------
    def _toggle_popup(self, *_args):
        if self.popup.get_visible():
            self.popup.hide()
            return
        self.update()
        self._fill_outputs(force=True)
        top = self.get_toplevel()
        alloc = self.get_allocation()
        x, _y = self.translate_coordinates(top, 0, 0)
        right = top.get_allocated_width() - (x + alloc.width // 2) - SOUND_MENU_WIDTH // 2
        GtkLayerShell.set_margin(self.popup, GtkLayerShell.Edge.RIGHT, max(8, right))
        self.popup.show()
        self._popup_leave()   # closes by itself if the pointer never goes in

    def _fill_outputs(self, force=False):
        """One row for each output, the one playing marked."""
        devices = audio.outputs() if audio.available() else []
        playing = audio.current_output() if devices else None
        shown = (tuple(devices), playing)
        if shown == self.shown_outputs and not force:
            return
        self.shown_outputs = shown
        for child in self.output_rows.get_children():
            child.destroy()
        for name, description, icon in devices:
            button = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
            button.get_style_context().add_class("sound-menu-item")
            line = Gtk.Box(spacing=10)
            symbol = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU)
            symbol.get_style_context().add_class("sound-device")
            if name == playing:
                symbol.get_style_context().add_class("sound-device-on")
            line.pack_start(symbol, False, False, 0)
            line.pack_start(Gtk.Label(label=description, xalign=0, ellipsize=3, max_width_chars=26), True, True, 0)
            button.add(line)
            button.connect("clicked", lambda _b, n=name: self._pick(n))
            self.output_rows.pack_start(button, False, False, 0)
        self.output_rows.show_all()
        self.outputs_part.set_visible(bool(devices))

    def _pick(self, name):
        audio.set_output(name)
        self.update()
        self._fill_outputs(force=True)

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
            return   # moved onto the slider or the mute button
        self._popup_enter()
        self.close_timer = GLib.timeout_add(2500 if event is not None else 6000, self._auto_close)

    def _auto_close(self):
        self.close_timer = None
        self.popup.hide()
        return False

    def read(self):
        # pactl answers after the server has made a change; wpctl can lag it.
        state = audio.state() if audio.available() else None
        if state is not None:
            return state
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
        self.mute_image.set_from_icon_name(f"audio-volume-{level}-symbolic", Gtk.IconSize.MENU)
        self.mute.set_tooltip_text("Unmute" if muted else "Mute")
        if round(self.scale.get_value()) != volume:
            with self.scale.handler_block(self.scale_handler):
                self.scale.set_value(volume)
        if self.mute.get_active() != muted:
            with self.mute.handler_block(self.mute_handler):
                self.mute.set_active(muted)
        if self.popup.get_visible():
            self._fill_outputs()

    def _set_volume(self, scale):
        audio.set_level(int(scale.get_value()))
        self.update()

    def _mute(self, button):
        audio.set_muted(button.get_active())
        self.update()

    def _scroll(self, _widget, event):
        if event.direction in (Gdk.ScrollDirection.UP, Gdk.ScrollDirection.DOWN):
            audio.step(5 if event.direction == Gdk.ScrollDirection.UP else -5)
            sounds.feedback()
            self.update()
        return True


# Where the kernel lists batteries and chargers. FREEMAC_POWER_SUPPLY points
# somewhere else to try the warnings without a real battery.
POWER_SUPPLY = os.environ.get("FREEMAC_POWER_SUPPLY", "/sys/class/power_supply")

# The warnings a Mac gives as its battery runs down, from the highest level.
LOW_BATTERY = (
    (10, "Low Battery", "Your computer will sleep soon unless it's plugged in."),
    (5, "Reserve Battery", "Your computer is running on reserve power. Plug it in now, or it will sleep."),
)
SLEEP_AT = 2   # percent: sleep rather than run out mid-sentence


def battery_time(path, read):
    """'2:15' left on battery, or until full while charging, or None."""
    def number(name):
        try:
            return int(read(path, name) or "")
        except ValueError:
            return None
    now, rate, full = number("energy_now"), number("power_now"), number("energy_full")
    if now is None or not rate:
        now, rate, full = number("charge_now"), number("current_now"), number("charge_full")
    if now is None or not rate or rate <= 0:
        return None
    status = read(path, "status")
    if status == "Discharging":
        hours = now / rate
    elif status == "Charging" and full:
        hours = max(0, full - now) / rate
    else:
        return None
    if hours > 48:
        return None
    minutes = round(hours * 60)
    return f"{minutes // 60}:{minutes % 60:02d}"


class Battery(StatusButton):
    """The battery level, with a Mac's warnings when it runs low: at 10% and
    5% a notice to plug in, and at 2% the computer goes to sleep so nothing
    is lost. Click for Dials' Battery panel."""

    def __init__(self):
        super().__init__()
        self.set_always_show_image(True)
        self.connect("clicked", lambda *_: self._clicked())
        self.facts = None          # what update() last read, for the Battery menu
        self.warned = set()      # levels already warned about on this charge
        self.sleeping = False
        self.low_power = False
        self.low_power_for = None   # (mode, plugged in) Low Power Mode was last set for
        self._prefs_monitor = style.watch_prefs(self.update)   # Show percentage
        GLib.timeout_add_seconds(30, lambda: self.update() or True)
        self.update()

    def update(self):
        batteries = [b for b in glob.glob(os.path.join(POWER_SUPPLY, "*"))
                     if self._read(b, "type") == "Battery" and self._read(b, "present") != "0"]
        if not batteries:
            self.hide()
            return
        capacity = int(self._read(batteries[0], "capacity") or 0)
        status = self._read(batteries[0], "status")
        charging = status in ("Charging", "Full")
        level = min(100, max(0, round(capacity / 10) * 10))
        icon = f"battery-level-{level}{'-charging' if charging else ''}-symbolic"
        tooltip = f"Battery {capacity}%"
        left = battery_time(batteries[0], self._read)
        if charging:
            tooltip += f" (charging, {left} until full)" if left and status == "Charging" else " (charging)"
        elif left:
            tooltip += f" ({left} left)"
        plugged = battery.on_adapter(batteries[0])
        battery.record(capacity, plugged)
        self.facts = {"capacity": capacity, "status": status, "left": left, "plugged": plugged}
        prefs = style.prefs()
        mode = prefs.get("low_power_mode", "never")
        if (mode, plugged) != self.low_power_for:
            self.low_power_for = (mode, plugged)
            self.low_power = battery.apply_low_power(mode, plugged)
            if not self.low_power and battery.low_power_wanted(mode, plugged):
                self.low_power_for = None    # couldn't yet: try again next time
        context = self.get_style_context()
        if self.low_power:
            context.add_class("battery-low-power")
            tooltip += ", Low Power Mode"
        else:
            context.remove_class("battery-low-power")
        self.show_icon(icon, tooltip)
        label = f"{capacity}%" if prefs.get("battery_percent", True) else None
        if self.get_label() != label:
            self.set_label(label or "")
        self._warn(capacity, status == "Discharging")

    def _clicked(self):
        launch("freemac-dials", "--panel", "power")

    def _warn(self, capacity, discharging):
        if not discharging:
            self.warned.clear()   # plugged in: warn again next time it runs down
            self.sleeping = False
            return
        # One notice for the most urgent level reached, then none for the
        # levels above it.
        for threshold, title, body in sorted(LOW_BATTERY):
            if capacity <= threshold:
                if threshold not in self.warned:
                    self.warned.update(t for t, *_ in LOW_BATTERY if t >= threshold)
                    beacon.send(title, f"{capacity}% left. {body}", icon="battery-caution-symbolic")
                break
        if capacity <= SLEEP_AT and not self.sleeping:
            self.sleeping = True
            beacon.send("Going to Sleep", "The battery is almost empty, so your computer is going to sleep. "
                        "Plug it in, then wake it.", icon="battery-empty-symbolic")
            GLib.timeout_add_seconds(30, self._sleep_now)

    def _sleep_now(self):
        """Sleep, unless it was plugged in during the 30 seconds' notice."""
        batteries = [b for b in glob.glob(os.path.join(POWER_SUPPLY, "*")) if self._read(b, "type") == "Battery"]
        if batteries and self._read(batteries[0], "status") == "Discharging":
            subprocess.Popen(["systemctl", "suspend"])
        self.sleeping = False
        return False

    @staticmethod
    def _read(path, name):
        try:
            with open(os.path.join(path, name)) as f:
                return f.read().strip()
        except OSError:
            return None


class Bluetooth(StatusButton):
    """Shown when the computer has a Bluetooth adapter: on, off, or the
    devices connected right now. Click for Dials' Bluetooth panel."""

    def __init__(self):
        super().__init__()
        self.connect("clicked", lambda *_: self._clicked())
        self.manager = None
        try:
            self.manager = Gio.DBusObjectManagerClient.new_for_bus_sync(
                Gio.BusType.SYSTEM, Gio.DBusObjectManagerClientFlags.DO_NOT_AUTO_START, "org.bluez", "/",
                None, None, None)
        except GLib.Error:
            self.manager = None
        if self.manager:
            for signal in ("object-added", "object-removed", "interface-added", "interface-removed",
                           "interface-proxy-properties-changed", "notify::name-owner"):
                self.manager.connect(signal, lambda *_: self.update())
        self.update()

    @staticmethod
    def _prop(proxy, name):
        value = proxy.get_cached_property(name)
        return value.unpack() if value is not None else None

    def update(self):
        if not self.manager or not self.manager.get_name_owner():
            self.hide()
            return
        adapters, connected = [], []
        for obj in self.manager.get_objects():
            adapter = obj.get_interface("org.bluez.Adapter1")
            if adapter:
                adapters.append(adapter)
            device = obj.get_interface("org.bluez.Device1")
            if device and self._prop(device, "Connected"):
                connected.append(self._prop(device, "Alias") or self._prop(device, "Name") or "a device")
        if not adapters:
            self.hide()
            return
        if not any(self._prop(a, "Powered") for a in adapters):
            self.show_icon("bluetooth-disabled-symbolic", "Bluetooth is off")
        elif connected:
            self.show_icon("bluetooth-active-symbolic", "Connected to " + ", ".join(sorted(connected)))
        else:
            self.show_icon("bluetooth-disconnected-symbolic", "Bluetooth is on")

    def _clicked(self):
        launch("freemac-dials", "--panel", "bluetooth")


JOB_DONE, JOB_CANCELED, JOB_ABORTED = 9, 7, 8
PRINTER_STOPPED = 5


class Printing(StatusButton):
    """Shown while something is printing or waiting to print. Says so (with a
    notification) when a document has printed, didn't print, or its printer
    stopped. Click for Dials' Printers panel."""

    def __init__(self):
        super().__init__()
        self.connect("clicked", lambda *_: launch("freemac-dials", "--panel", "printers"))
        self.jobs = {}          # job id -> (document name, printer name)
        self.stopped = set()    # printers we've already said have stopped
        GLib.timeout_add_seconds(5, lambda: self.update() or True)
        self.update()

    def _connection(self):
        if not cups:
            return None
        try:
            return cups.Connection()
        except (RuntimeError, cups.IPPError):
            return None

    @staticmethod
    def _printer_of(attrs):
        uri = attrs.get("job-printer-uri", "")
        return uri.rsplit("/", 1)[-1] if uri else ""

    def update(self):
        conn = self._connection()
        if conn is None:
            self.hide()
            return
        try:
            pending = conn.getJobs(which_jobs="not-completed", my_jobs=True,
                                   requested_attributes=["job-id", "job-name", "job-printer-uri"])
            printers = conn.getPrinters()
        except cups.IPPError:
            self.hide()
            return
        for job_id, attrs in pending.items():
            self.jobs[job_id] = (attrs.get("job-name") or "Untitled", self._printer_of(attrs))
        for job_id in [j for j in self.jobs if j not in pending]:
            name, printer = self.jobs.pop(job_id)
            self._finished(conn, job_id, name, printers.get(printer, {}).get("printer-info") or printer)
        self._check_stopped(printers, {p for _n, p in self.jobs.values()})
        if not self.jobs:
            self.hide()
            return
        name, printer = next(iter(self.jobs.values()))
        info = printers.get(printer, {})
        label = info.get("printer-info") or printer
        if printer in self.stopped:
            self.show_icon("printer-error-symbolic", f"{label} has stopped")
        else:
            more = f" ({len(self.jobs)} waiting)" if len(self.jobs) > 1 else ""
            self.show_icon("printer-printing-symbolic", f"Printing “{name}” on {label}{more}")

    def _finished(self, conn, job_id, name, printer):
        try:
            attrs = conn.getJobAttributes(job_id, requested_attributes=["job-state", "job-state-message"])
        except cups.IPPError:
            return
        state = attrs.get("job-state")
        if state == JOB_DONE:
            beacon.send(f"Printed “{name}”", f"On {printer}." if printer else "", "printer-symbolic", "Printers")
        elif state == JOB_ABORTED:
            detail = attrs.get("job-state-message") or "The printer reported a problem."
            beacon.send(f"“{name}” didn’t print", detail, "printer-error-symbolic", "Printers")

    def _check_stopped(self, printers, busy):
        for printer, info in printers.items():
            stopped = info.get("printer-state") == PRINTER_STOPPED
            if stopped and printer in busy and printer not in self.stopped:
                self.stopped.add(printer)
                reason = info.get("printer-state-message") or "Documents will wait until it's working again."
                beacon.send(f"{info.get('printer-info') or printer} has stopped", reason,
                            "printer-error-symbolic", "Printers")
            elif not stopped:
                self.stopped.discard(printer)


class Recording(StatusButton):
    """A red stop button while Lens is recording the screen; click to stop."""

    def __init__(self):
        super().__init__()
        self.get_style_context().add_class("recording")
        self.connect("clicked", lambda *_: launch("freemac-lens", "--stop"))
        GLib.timeout_add(1000, lambda: self.update() or True)
        self.update()

    def update(self):
        from . import lens

        if lens.recording():
            self.show_icon("media-record-symbolic", "Recording the screen. Click to stop.")
        else:
            self.hide()


class ScreenShared(Gtk.MenuButton):
    """While someone at another computer is looking at this screen (Screen
    Sharing), an icon in the menu bar, as on a Mac: its menu says who, and
    disconnects them."""

    def __init__(self):
        super().__init__()
        from . import screen_sharing

        self.sharing = screen_sharing
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.get_style_context().add_class("screen-shared")
        self.add(Gtk.Image.new_from_icon_name("preferences-desktop-remote-desktop-symbolic",
                                              Gtk.IconSize.MENU))
        self.set_no_show_all(True)
        self.menu = Gtk.Menu()
        self.menu.set_halign(Gtk.Align.END)
        self.set_popup(self.menu)
        # The watcher keeps the list from wayvnc's events; the bar looks at
        # it on a timer, as its other icons do (shown straight from the
        # pipe's callback, the icon waited for the clock to tick to appear).
        self.watcher = screen_sharing.Watcher(lambda _viewers: None)
        self.shown = []
        GLib.timeout_add_seconds(1, self._poll)

    def _poll(self):
        viewers = list(self.watcher.viewers.values())
        if [v.get("id") for v in viewers] != [v.get("id") for v in self.shown]:
            self.shown = viewers
            self.update(viewers)
        return True

    @staticmethod
    def _who(viewer):
        user = viewer.get("username") or "Someone"
        where = viewer.get("hostname") or viewer.get("address")
        return f"{user} at {where}" if where else user

    def update(self, viewers):
        if not viewers:
            self.menu.popdown()
            self.hide()
            return
        for child in self.menu.get_children():
            self.menu.remove(child)
        for viewer in viewers:
            item = Gtk.MenuItem(label=f"{self._who(viewer)} is using this screen")
            item.set_sensitive(False)
            self.menu.append(item)
        self.menu.append(Gtk.SeparatorMenuItem())
        label = "Disconnect" if len(viewers) == 1 else "Disconnect Everyone"
        item = Gtk.MenuItem(label=label)
        item.connect("activate", lambda *_: [self.sharing.disconnect(v.get("id")) for v in viewers])
        self.menu.append(item)
        item = Gtk.MenuItem(label="Sharing Settings…")
        item.connect("activate", lambda *_: launch("freemac-dials", "--panel", "sharing"))
        self.menu.append(item)
        self.menu.show_all()
        self.set_tooltip_text("\n".join(f"{self._who(v)} is using this screen" for v in viewers))
        self.show()
        self.get_child().show()


class InUse(Gtk.MenuButton):
    """A small dot while an app is using the microphone (orange) or the camera
    (green), so nobody listens or watches unnoticed. Click it to see which
    apps."""

    COLOURS = {"microphone": (0.96, 0.60, 0.11), "camera": (0.19, 0.70, 0.31)}

    def __init__(self):
        super().__init__()
        from . import inuse

        self.inuse = inuse
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.get_style_context().add_class("in-use")
        # A picture, not a drawing area: a drawing area has a window of its
        # own, which would sit over the button and swallow its clicks.
        self.dot = Gtk.Image()
        self.add(self.dot)
        self.set_no_show_all(True)
        self.colour = None
        self.menu = Gtk.Menu()
        self.menu.set_halign(Gtk.Align.END)
        self.set_popup(self.menu)
        self.watcher = inuse.Watcher(on_change=self.update)
        self.update()

    def _paint(self, colour):
        scale = max(1, self.get_scale_factor())
        size = 10 * scale
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
        surface.set_device_scale(scale, scale)
        cr = cairo.Context(surface)
        cr.set_source_rgb(*colour)
        cr.arc(5, 5, 4, 0, 6.2832)
        cr.fill()
        self.dot.set_from_surface(surface)

    def update(self):
        users = self.watcher.users()
        uses = set().union(*users.values()) if users else set()
        if not uses:
            self.colour = None
            self.menu.popdown()
            self.hide()
            return
        colour = self.COLOURS["camera" if "camera" in uses else "microphone"]
        if colour != self.colour:
            self.colour = colour
            self._paint(colour)
        self.set_tooltip_text("\n".join(self.inuse.describe(users)))
        self._fill_menu(users)
        self.show()
        self.dot.show()

    def _fill_menu(self, users):
        """The menu is filled before it's needed: a menu button shows nothing
        for a menu that is still empty when it's clicked."""
        for child in self.menu.get_children():
            self.menu.remove(child)
        for line in self.inuse.describe(users):
            item = Gtk.MenuItem(label=line)
            item.set_sensitive(False)
            self.menu.append(item)
        self.menu.append(Gtk.SeparatorMenuItem())
        item = Gtk.MenuItem(label="Sound Settings…")
        item.connect("activate", lambda *_: launch("freemac-dials", "--panel", "sound"))
        self.menu.append(item)
        self.menu.show_all()


class InputMenu(Gtk.MenuButton):
    """The input menu, as on a Mac: with more than one input source (keyboard
    layout), the menu bar shows which one you're typing with ("US", "GB"),
    and its menu switches to another. Control-Space does the same."""

    def __init__(self):
        super().__init__()
        from . import input_sources, wfipc

        self.sources = input_sources
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.get_style_context().add_class("input-menu")
        self.label = Gtk.Label()
        self.add(self.label)
        self.set_no_show_all(True)
        self.menu = Gtk.Menu()
        self.menu.set_halign(Gtk.Align.END)
        self.set_popup(self.menu)
        try:
            self.wf = wfipc.Wayfire()
        except OSError:
            self.wf = None
        self.shown = None
        self._prefs_monitor = style.watch_prefs(self.update)
        # The source changes with Control-Space, which no event reports.
        GLib.timeout_add(1000, lambda: self.update() or True)
        self.update()

    def update(self):
        configured = self.sources.sources()
        state = self.sources.current(self.wf) if self.wf else None
        if (len(configured) < 2 or not state or len(state[0]) < 2
                or not style.prefs().get("input_menu", True)):
            self.shown = None
            self.menu.popdown()
            self.hide()
            return
        names, index = state
        index = min(max(index, 0), len(names) - 1)
        if self.shown == (tuple(names), index):
            return
        self.shown = (tuple(names), index)
        layout, variant = configured[index] if index < len(configured) else ("", "")
        self.label.set_text(self.sources.short_label(layout, variant))
        self.set_tooltip_text(f"{names[index]}\nControl-Space switches to the next one.")
        for child in self.menu.get_children():
            self.menu.remove(child)
        group = []
        for n, name in enumerate(names):
            item = Gtk.RadioMenuItem.new_with_label(group, name)
            group = item.get_group()
            item.set_active(n == index)
            item.connect("toggled", lambda i, n=n: i.get_active() and self._choose(n))
            self.menu.append(item)
        self.menu.append(Gtk.SeparatorMenuItem())
        settings = Gtk.MenuItem(label="Open Keyboard Settings…")
        settings.connect("activate", lambda *_: launch("freemac-dials", "--panel", "keyboard"))
        self.menu.append(settings)
        self.menu.show_all()
        self.show()
        self.label.show()

    def _choose(self, index):
        self.sources.choose(self.wf, index)
        GLib.timeout_add(150, lambda: self.update() and False)


class UserMenu(Gtk.MenuButton):
    """Fast user switching, as on a Mac: with more than one account, the menu
    bar shows your name, and its menu lists everyone (a tick by those
    logged in) to switch to without logging out, and Login Window….
    Dials > Users & Groups can hide it (pref "user_menu")."""

    def __init__(self):
        super().__init__()
        from . import gangway, switch_user

        self.switch, self.avatar = switch_user, gangway.avatar
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.get_style_context().add_class("user-menu")
        self.label = Gtk.Label()
        self.add(self.label)
        self.set_no_show_all(True)
        self.menu = Gtk.Menu()
        self.menu.set_halign(Gtk.Align.END)
        self.set_popup(self.menu)
        self.ticks, self.names = {}, None
        # Who's logged in can change while the menu is closed: look as it
        # opens. Only the ticks change then, so the menu keeps its size and
        # opens where it should; the people are listed again when accounts
        # are added or removed.
        self.connect("button-press-event", lambda *_: self.mark() and False)
        GLib.timeout_add_seconds(30, lambda: self.update() or True)
        self._prefs_monitor = style.watch_prefs(self.update)
        self.update()

    def update(self):
        if not style.prefs().get("user_menu", True) or not self.switch.available():
            self.hide()
            return
        me = pwd_entry()
        self.label.set_text(self.switch.full_name(me) if me else os.environ.get("USER", ""))
        names = [e.pw_name for e in self.switch.accounts()]
        if names != self.names:
            self.names = names
            self.fill()
        self.show()
        self.label.show()

    def fill(self):
        for child in self.menu.get_children():
            self.menu.remove(child)
        me = os.getuid()
        self.ticks = {}
        for entry in self.switch.accounts():
            row = Gtk.Box(spacing=8)
            tick = Gtk.Image.new_from_icon_name("object-select-symbolic", Gtk.IconSize.MENU)
            self.ticks[entry.pw_name] = (tick, entry.pw_uid == me)
            row.pack_start(tick, False, False, 0)
            row.pack_start(self.avatar(entry, 20), False, False, 0)
            row.pack_start(Gtk.Label(label=self.switch.full_name(entry), xalign=0), True, True, 0)
            item = Gtk.MenuItem()
            item.add(row)
            if entry.pw_uid == me:
                item.set_sensitive(False)
            else:
                item.connect("activate", lambda _i, n=entry.pw_name: self._go(self.switch.to_user, n))
            self.menu.append(item)
        self.menu.append(Gtk.SeparatorMenuItem())
        window = Gtk.MenuItem(label="Login Window…")
        window.connect("activate", lambda *_: self._go(self.switch.login_window))
        self.menu.append(window)
        settings = Gtk.MenuItem(label="Users & Groups Settings…")
        settings.connect("activate", lambda *_: launch("freemac-dials", "--panel", "users"))
        self.menu.append(settings)
        self.menu.show_all()
        self.mark()
        return True

    def mark(self):
        """Tick the people logged in. Asking logind takes a moment, and a
        menu that opens late is refused by the compositor (its click is
        over), so ask away from the bar and tick when the answer comes."""
        import threading

        def ask():
            logged_in = self.switch.sessions()
            GLib.idle_add(self._ticked, logged_in)
        threading.Thread(target=ask, daemon=True).start()
        return True

    def _ticked(self, logged_in):
        for name, (tick, mine) in self.ticks.items():
            tick.set_opacity(1 if mine or name in logged_in else 0)
        return False

    def _go(self, action, *args):
        """Locking waits for the lock screen; do it away from the bar."""
        import threading
        threading.Thread(target=action, args=args, daemon=True).start()


def pwd_entry():
    import pwd
    try:
        return pwd.getpwuid(os.getuid())
    except KeyError:
        return None
