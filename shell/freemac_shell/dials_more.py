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
from gi.repository import GLib, Gtk  # noqa: E402

from . import style  # noqa: E402


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


def sound(window):
    group, row, page, slider, switch = window.helpers
    if not shutil.which("wpctl"):
        return page("Sound", group(row("Sound isn't running", None,
                                       "freemac uses PipeWire for sound; its control tool wasn't found.")))
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
        if devices[kind]:
            rows.append(row(f"{title} device", combo))
        else:
            rows.append(row(f"No {title.lower()} devices", None))
        level, muted = volume_of(target)
        if level is not None:
            rows.append(row(f"{title} volume", slider(
                0, 100, 1, level, lambda v, t=target: run("wpctl", "set-volume", "-l", "1.0", t, f"{int(v)}%"))))
            rows.append(row("Mute", switch(muted, lambda on, t=target: run(
                "wpctl", "set-mute", t, "1" if on else "0"))))
        groups.append(group(*rows))
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
    return page("Power", *groups)


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
        plugins = (window.ini_get("core", "plugins", "") or "").split()
        if on and "wobbly" in plugins:
            plugins.remove("wobbly")
        elif not on and "wobbly" not in plugins:
            plugins.append("wobbly")
        window.ini_set("core", "plugins", " ".join(plugins))

    def high_contrast(on):
        if settings:
            dark = style.is_dark()
            settings.set_string("gtk-theme", "HighContrast" if on else ("Adwaita-dark" if dark else "Adwaita"))

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
        row("High contrast", switch(get("gtk-theme", "Adwaita") == "HighContrast", high_contrast),
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
