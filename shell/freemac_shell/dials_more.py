# SPDX-License-Identifier: GPL-3.0-or-later
"""More Dials panels: Sound, Power, Accessibility and Notifications.

Each builder takes the Dials window (for its helpers and settings) and returns
the panel widget.
"""
import glob
import os
import re
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, startup_sound, style  # noqa: E402


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return None


# ---- Sound ----------------------------------------------------------------------
def parse_wpctl_status(text):
    """Sinks and sources from `wpctl status`: {"sinks": [(id, name, default)], ...}."""
    found = {"sinks": [], "sources": []}
    section, in_audio = None, False
    for line in text.splitlines():
        stripped = line.strip(" │├└─")
        if not line.startswith(" "):
            in_audio = line.strip() == "Audio"
            section = None
            continue
        if not in_audio:
            continue
        heading = stripped.rstrip(":").strip()
        if heading in ("Sinks", "Sources"):
            section = heading.lower()
            continue
        if heading in ("Devices", "Filters", "Streams", "Sink endpoints", "Source endpoints"):
            section = None
            continue
        match = re.match(r"(\*)?\s*(\d+)\.\s+(.+?)(\s+\[vol:.*\])?$", stripped.strip())
        if section and match:
            found[section].append((int(match.group(2)), match.group(3).strip(), bool(match.group(1))))
    return found


def volume_of(target):
    result = run("wpctl", "get-volume", target)
    if not result or result.returncode != 0:
        return None, False
    match = re.search(r"Volume:\s*([\d.]+)", result.stdout)
    return (float(match.group(1)) * 100 if match else None), "MUTED" in result.stdout


def start_up_group(group, row, switch):
    def changed(on):
        startup_sound.set_enabled(on)
        if on:
            startup_sound.play()
    return group(row("Play a sound at start-up", switch(startup_sound.enabled(), changed),
                     "freemac's own chime as the desktop first appears after the computer starts."))


def sound(window):
    group, row, page, slider, switch = window.helpers
    if not shutil.which("wpctl"):
        return page("Sound", group(row("Sound isn't running", None,
                                       "freemac uses PipeWire for sound; its control tool wasn't found.")),
                    start_up_group(group, row, switch))
    status = run("wpctl", "status")
    devices = parse_wpctl_status(status.stdout if status else "")
    groups = []
    for kind, target, title in (("sinks", "@DEFAULT_AUDIO_SINK@", "Output"),
                                ("sources", "@DEFAULT_AUDIO_SOURCE@", "Input")):
        rows = []
        combo = Gtk.ComboBoxText()
        for dev_id, name, default in devices[kind]:
            combo.append(str(dev_id), name)
            if default:
                combo.set_active_id(str(dev_id))
        combo.connect("changed", lambda c: c.get_active_id() and run("wpctl", "set-default", c.get_active_id()))
        if not devices[kind]:
            groups.append(group(row(f"No {title.lower()} devices", None)))
            continue
        rows.append(row(f"{title} device", combo))
        level, muted = volume_of(target)
        if level is not None:
            rows.append(row(f"{title} volume", slider(
                0, 100, 1, level, lambda v, t=target: run("wpctl", "set-volume", "-l", "1.0", t, f"{int(v)}%"))))
            rows.append(row("Mute", switch(muted, lambda on, t=target: run(
                "wpctl", "set-mute", t, "1" if on else "0"))))
        groups.append(group(*rows))
    groups.append(start_up_group(group, row, switch))
    return page("Sound", *groups)


# ---- Power ----------------------------------------------------------------------
BLANK_CHOICES = (("-1", "Never"), ("60", "1 minute"), ("120", "2 minutes"), ("300", "5 minutes"),
                 ("600", "10 minutes"), ("900", "15 minutes"), ("1800", "30 minutes"))


def battery_state():
    for path in sorted(glob.glob("/sys/class/power_supply/*")):
        def read(name):
            try:
                with open(os.path.join(path, name)) as f:
                    return f.read().strip()
            except OSError:
                return None
        if read("type") == "Battery" and read("present") != "0":
            return read("capacity"), read("status")
    return None


LOCK_CHOICES = (("0", "Never"), ("1", "1 minute"), ("2", "2 minutes"), ("5", "5 minutes"),
                ("10", "10 minutes"), ("15", "15 minutes"), ("30", "30 minutes"))


def power(window):
    group, row, page, _slider, _switch = window.helpers
    groups = []
    battery = battery_state()
    if battery:
        capacity, state = battery
        groups.append(group(row("Battery", Gtk.Label(label=f"{capacity}%"), state or None)))
    blank = Gtk.ComboBoxText()
    for value, label in BLANK_CHOICES:
        blank.append(value, label)
    blank.set_active_id(window.ini_get("idle", "dpms_timeout", "600") or "600")
    if not blank.get_active_id():
        blank.set_active_id("600")
    blank.connect("changed", lambda c: window.ini_set("idle", "dpms_timeout", c.get_active_id()))
    groups.append(group(row("Turn the screen off after", blank,
                            "When nothing has been touched for this long.")))
    prefs = style.prefs()
    lock_after = Gtk.ComboBoxText()
    for value, label in LOCK_CHOICES:
        lock_after.append(value, label)
    lock_after.set_active_id(str(prefs.get("lock_after", 5)))
    if not lock_after.get_active_id():
        lock_after.set_active_id("5")
    lock_after.connect("changed", lambda c: window.save_prefs(lock_after=int(c.get_active_id())))
    on_sleep = _switch(bool(prefs.get("lock_on_sleep", True)),
                       lambda active: window.save_prefs(lock_on_sleep=active))
    groups.append(group(row("Lock the screen after", lock_after,
                            "You'll need your password to get back in. \u2303\u2318Q locks at once."),
                        row("Lock before sleeping", on_sleep)))
    if shutil.which("powerprofilesctl"):
        mode = Gtk.ComboBoxText()
        for value, label in (("power-saver", "Power Saver"), ("balanced", "Balanced"),
                             ("performance", "Performance")):
            mode.append(value, label)
        current = run("powerprofilesctl", "get")
        mode.set_active_id(current.stdout.strip() if current and current.returncode == 0 else "balanced")
        mode.connect("changed", lambda c: run("powerprofilesctl", "set", c.get_active_id()))
        groups.append(group(row("Power mode", mode, "Power Saver makes a battery last longer.")))
    buttons = Gtk.Box(spacing=8)
    for label, action in (("Sleep", "suspend"), ("Restart…", "reboot"), ("Shut Down…", "poweroff")):
        button = Gtk.Button(label=label)
        button.connect("clicked", lambda _b, a=action: window.confirm_power(a))
        buttons.pack_start(button, False, False, 0)
    groups.append(buttons)
    recovery = Gtk.Button(label="Restart in Recovery…")
    if can_restart_in_recovery():
        recovery.connect("clicked", lambda _b: restart_in_recovery(window))
        groups.append(group(row("freemac Recovery", recovery,
                                "Bring back files from a Lifeboat backup, reset a password or check a disk. "
                                "You can also hold Ctrl while the computer starts.")))
    else:
        groups.append(group(row("freemac Recovery", Gtk.Label(label="Hold Ctrl as it starts"),
                                "Bring back files from a Lifeboat backup, reset a password or check a disk.")))
    return page("Power", *groups)


RECOVERY_HELPER = "/usr/libexec/freemac-recovery-helper"


def can_restart_in_recovery():
    """Only a freemac installed on a disk can choose what the next start-up
    starts; a USB stick's menu can't be changed."""
    if os.path.isdir("/run/live/medium") or not os.access(RECOVERY_HELPER, os.X_OK):
        return False
    try:
        with open("/boot/grub/grub.cfg") as f:
            return "freemac-recovery" in f.read()
    except OSError:
        return os.path.exists("/boot/grub/grubenv")


def restart_in_recovery(window):
    answer = alert.ask(window, "Restart in Recovery?",
                       "The computer restarts into freemac Recovery, where you can bring back files from a "
                       "Lifeboat backup, reset a password or check a disk. It starts as usual the time after. "
                       "Unsaved work in open apps will be lost.",
                       [("Cancel", Gtk.ResponseType.CANCEL), ("Restart", Gtk.ResponseType.OK)],
                       default=Gtk.ResponseType.OK)
    if answer != Gtk.ResponseType.OK:
        return
    try:
        process = Gio.Subprocess.new(["pkexec", RECOVERY_HELPER], Gio.SubprocessFlags.STDERR_PIPE)
    except GLib.Error as error:
        alert.tell(window, "The computer couldn\u2019t restart in Recovery.", error.message)
        return

    def finished(proc, result):
        try:
            _ok, _out, err = proc.communicate_utf8_finish(result)
        except GLib.Error:
            return
        # 126 is the password dialog being cancelled: nothing to say then.
        if proc.get_exit_status() not in (0, 126):
            alert.tell(window, "The computer couldn\u2019t restart in Recovery.", (err or "").strip())
    process.communicate_utf8_async(None, None, finished)


# ---- Accessibility ---------------------------------------------------------------
def accessibility(window):
    group, row, page, _slider, switch = window.helpers
    settings = window.settings

    def get(key, default):
        try:
            return settings.get_value(key).unpack() if settings else default
        except TypeError:
            return default

    def larger_text(on):
        if settings:
            settings.set_double("text-scaling-factor", 1.25 if on else 1.0)

    def reduce_motion(on):
        if settings:
            settings.set_boolean("enable-animations", not on)
        window.ini_set("animate", "open_animation", "fade" if on else "zoom")
        window.ini_set("animate", "close_animation", "fade" if on else "zoom")
        window.ini_set("animate", "duration", "120" if on else "220")
        # Windows no longer wobble at all (that's not how a Mac behaves); this
        # only cleans it up on systems set up before 1.2.
        plugins = (window.ini_get("core", "plugins", "") or "").split()
        if "wobbly" in plugins:
            plugins.remove("wobbly")
            window.ini_set("core", "plugins", " ".join(plugins))

    def high_contrast(on):
        if settings:
            dark = style.is_dark()
            settings.set_string("gtk-theme", "HighContrast" if on else ("freemac-dark" if dark else "freemac"))

    def big_pointer(size):
        if settings:
            settings.set_int("cursor-size", size)
        window.ini_set("input", "cursor_size", str(size))

    pointer = Gtk.ComboBoxText()
    for value, label in (("24", "Default"), ("32", "Large"), ("48", "Larger"), ("64", "Largest")):
        pointer.append(value, label)
    pointer.set_active_id(str(get("cursor-size", 24)))
    if not pointer.get_active_id():
        pointer.set_active_id("24")
    pointer.connect("changed", lambda c: big_pointer(int(c.get_active_id())))
    zoom_on = "zoom" in (window.ini_get("core", "plugins", "") or "").split()
    return page("Accessibility", group(
        row("Larger text", switch(get("text-scaling-factor", 1.0) > 1.05, larger_text)),
        row("High contrast", switch(get("gtk-theme", "freemac") == "HighContrast", high_contrast),
            "Stronger borders and colours in apps."),
        row("Reduce motion", switch(not get("enable-animations", True), reduce_motion),
            "Windows fade instead of zooming and don't wobble."),
        row("Pointer size", pointer),
    ), group(
        row("Zoom", None, "Hold Super and scroll to zoom in on part of the screen."
            if zoom_on else "Screen zoom isn't turned on in this session."),
    ))


# ---- Notifications ----------------------------------------------------------------
def notifications(window):
    group, row, page, _slider, switch = window.helpers
    prefs = style.prefs()
    seconds = Gtk.ComboBoxText()
    for value, label in (("3", "3 seconds"), ("5", "5 seconds"), ("8", "8 seconds"), ("12", "12 seconds")):
        seconds.append(value, label)
    seconds.set_active_id(str(int(prefs.get("banner_seconds", 5))))
    if not seconds.get_active_id():
        seconds.set_active_id("5")
    seconds.connect("changed", lambda c: window.save_prefs(banner_seconds=int(c.get_active_id())))
    clear = Gtk.Button(label="Clear")

    def clear_history(_button):
        from . import beacon

        beacon.call("ClearAll")
        clear.set_sensitive(False)
        GLib.timeout_add_seconds(2, lambda: clear.set_sensitive(True) or False)

    clear.connect("clicked", clear_history)
    return page("Notifications", group(
        row("Do Not Disturb", switch(bool(prefs.get("dnd")), lambda on: window.save_prefs(dnd=on)),
            "Banners stay hidden; notifications still collect in the list. Urgent ones still show."),
        row("Show banners for", seconds),
    ), group(
        row("Notification history", clear, "Click the clock in the menu bar to see recent notifications."),
    ))
