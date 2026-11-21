# SPDX-License-Identifier: GPL-3.0-or-later
"""freemac-keys: what the keyboard's volume, brightness and media keys do.

Strata (Wayfire's command plugin) runs `freemac-keys <action>` for each key.
The action is done here and Beacon shows the new level in a small panel near
the bottom of the screen. This module avoids importing GTK so a key press
answers quickly.

  volume-up, volume-down, mute, mic-mute
  brightness-up, brightness-down
  play-pause, next, previous, stop
"""
import re
import shutil
import subprocess
import sys

from gi.repository import Gio, GLib

from . import screen

STEP = 5           # percent per press
SINK = "@DEFAULT_AUDIO_SINK@"
SOURCE = "@DEFAULT_AUDIO_SOURCE@"
BEACON = ("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freemac.Beacon")


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def volume(device=SINK):
    """(percent, muted) from wpctl, or None without a sound server."""
    if not shutil.which("wpctl"):
        return None
    out = run("wpctl", "get-volume", device)
    match = re.search(r"Volume:\s*([\d.]+)", out)
    if not match:
        return None
    return round(float(match.group(1)) * 100), "[MUTED]" in out


def volume_icon(percent, muted):
    if muted or percent == 0:
        return "audio-volume-muted-symbolic"
    if percent < 34:
        return "audio-volume-low-symbolic"
    if percent < 67:
        return "audio-volume-medium-symbolic"
    return "audio-volume-high-symbolic"


def show_level(icon, fraction, label=""):
    """Ask Beacon to show a level (0..1, or -1 for no bar) with an icon."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call_sync(BEACON[0], BEACON[1], BEACON[2], "ShowLevel",
                      GLib.Variant("(sds)", (icon, float(fraction), label)), None,
                      Gio.DBusCallFlags.NO_AUTO_START, 1000, None)
        return True
    except GLib.Error:
        return False


def do(action):
    """Carry out one action. Returns (icon, fraction, label) to show, or None."""
    if action in ("volume-up", "volume-down", "mute"):
        if volume() is None:
            return None
        if action == "mute":
            run("wpctl", "set-mute", SINK, "toggle")
        else:
            run("wpctl", "set-mute", SINK, "0")
            sign = "+" if action == "volume-up" else "-"
            run("wpctl", "set-volume", "-l", "1.0", SINK, f"{STEP}%{sign}")
        percent, muted = volume()
        return volume_icon(percent, muted), 0.0 if muted else percent / 100, "Muted" if muted else ""
    if action == "mic-mute":
        if volume(SOURCE) is None:
            return None
        run("wpctl", "set-mute", SOURCE, "toggle")
        _percent, muted = volume(SOURCE)
        return ("microphone-sensitivity-muted-symbolic" if muted else "audio-input-microphone-symbolic",
                -1, "Microphone off" if muted else "Microphone on")
    if action in ("brightness-up", "brightness-down"):
        level = screen.brightness()
        if level is None:
            return None
        step = STEP / 100 if action == "brightness-up" else -STEP / 100
        level = min(1.0, max(0.05, round(level + step, 2)))
        screen.set_brightness(level)
        return "display-brightness-symbolic", level, ""
    if action == "dock-autohide":
        toggle_dock_autohide()
        return None
    if action in ("play-pause", "next", "previous", "stop"):
        from . import media   # imports GTK, so only for these keys
        media.send(action)
        return None
    raise ValueError(action)


ACTIONS = ("volume-up", "volume-down", "mute", "mic-mute", "brightness-up", "brightness-down",
           "play-pause", "next", "previous", "stop", "dock-autohide")


def toggle_dock_autohide():
    """Option-Command-D: turn the Dock's hiding on or off. The Dock and Dials
    both watch pier.json, so they follow at once."""
    import json
    import os
    path = os.path.expanduser("~/.config/freemac/pier.json")
    try:
        with open(path) as f:
            config = json.load(f)
    except (OSError, ValueError):
        config = {}
    config["autohide"] = not config.get("autohide", False)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".new", "w") as f:
        json.dump(config, f, indent=2)
    os.replace(path + ".new", path)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1 or argv[0] not in ACTIONS:
        print("usage: freemac-keys " + "|".join(ACTIONS), file=sys.stderr)
        return 2
    shown = do(argv[0])
    if shown:
        show_level(*shown)
    return 0


if __name__ == "__main__":
    sys.exit(main())
