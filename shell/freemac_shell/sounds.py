# SPDX-License-Identifier: GPL-3.0-or-later
"""Sound effects, as a Mac's Sound settings have them (Dials > Sound):

- the alert sound, played when something can't be done (a key that does
  nothing, a move that isn't allowed, an alert that warns), chosen from
  freemac's own sounds and played at its own alert volume;
- feedback as the volume changes, a little pop at the new level;
- interface sounds: a paper crumple when the Trash is emptied and a shutter
  for a screenshot.

The sounds are made by art/sounds/make-sounds.py. The choices are kept in
~/.config/freemac/shell.json:
    "alert_sound": "pebble", "alert_volume": 70,
    "volume_feedback": true, "ui_sounds": true, "flash_screen": false

With "flash_screen" on (Dials > Accessibility, "Flash the screen when an
alert sound occurs"), every display also flashes white with the alert
sound, through Strata's IPC method strata/flash, even with the alert
volume turned all the way down.

Every GTK app's own alert (a Backspace with nothing to delete, say) reaches
the compositor as gtk_shell1's system bell, and Strata's shell plugin runs
`freemac-sound alert` for it, so those play the same sound:

    freemac-sound alert            the chosen alert sound
    freemac-sound flash            flash the screen, as the alert can
    freemac-sound preview NAME     an alert sound by name, at the alert volume
    freemac-sound pop | trash | shutter

This module reads shell.json itself rather than through style, so the
command starts without loading GTK. Original freemac code.
"""
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import time

PREFS = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                     "freemac", "shell.json")

DIR = "/usr/share/sounds/freemac"

# In the order Dials lists them.
ALERTS = (("pebble", "Pebble"), ("droplet", "Droplet"), ("knock", "Knock"),
          ("chirp", "Chirp"), ("bell", "Bell"), ("hum", "Hum"))
DEFAULT_ALERT = "pebble"
DEFAULT_VOLUME = 70

_last = {}


def _prefs():
    try:
        with open(PREFS, encoding="utf-8") as f:
            value = json.load(f)
    except (OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def alert_name():
    name = _prefs().get("alert_sound", DEFAULT_ALERT)
    return name if name in dict(ALERTS) else DEFAULT_ALERT


def alert_volume():
    try:
        return max(0, min(100, int(_prefs().get("alert_volume", DEFAULT_VOLUME))))
    except (TypeError, ValueError):
        return DEFAULT_VOLUME


def volume_feedback():
    return bool(_prefs().get("volume_feedback", True))


def ui_sounds():
    return bool(_prefs().get("ui_sounds", True))


def flash_screen():
    return bool(_prefs().get("flash_screen", False))


def flash():
    """Flash every display once (Strata's strata/flash); False if Strata
    couldn't be asked. Talks to Wayfire's socket directly, as wfipc does,
    so that `freemac-sound alert` still starts without GTK."""
    runtime = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/nonexistent", "wayfire.socket")
    path = os.environ.get("WAYFIRE_SOCKET") or (runtime if os.path.exists(runtime) else
                                                 f"/tmp/wayfire-{os.environ.get('WAYLAND_DISPLAY', 'wayland-1')}.socket")
    raw = json.dumps({"method": "strata/flash", "data": {}}).encode()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(1)
            sock.connect(path)
            sock.sendall(struct.pack("<I", len(raw)) + raw)
            sock.recv(64)
    except OSError:
        return False
    return True


def path_of(name):
    return os.path.join(DIR, f"{name}.wav")


def _first(key, gap=0.12):
    """True unless `key` was asked for within `gap` seconds."""
    now = time.monotonic()
    if now - _last.get(key, -gap) < gap:
        return False
    _last[key] = now
    return True


def play(path, volume=100, gap=0.12):
    """Play a sound without waiting for it; False if it couldn't be.
    The same sound asked for again within `gap` seconds plays once."""
    if volume <= 0 or not os.path.exists(path):
        return False
    if not _first(path, gap):
        return True
    level = volume / 100
    for cmd in (["pw-play", f"--volume={level:.2f}", path],
                ["paplay", f"--volume={int(level * 65536)}", path],
                ["aplay", "-q", path]):
        if shutil.which(cmd[0]):
            try:
                subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
                return True
            except OSError:
                continue
    return False


def alert(name=None, volume=None):
    """The alert sound: what a Mac plays when something can't be done."""
    if name is None and flash_screen() and _first("flash"):
        flash()
    return play(path_of("alert-" + (name or alert_name())),
                alert_volume() if volume is None else volume)


def beep(*_args):
    """In place of Gdk.beep(), which makes no sound under Wayland."""
    alert()


def feedback():
    """A pop at the new level after the volume changes, when that's on."""
    if volume_feedback():
        play(path_of("pop"), 100, gap=0.05)


def effect(name):
    """An interface sound ("trash", "shutter"), when those are on."""
    if ui_sounds():
        play(path_of(name), 100)


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    what = args[0] if args else "alert"
    if what == "alert":
        alert()
    elif what == "preview" and len(args) > 1 and args[1] in dict(ALERTS):
        alert(args[1])
    elif what == "flash":
        return 0 if flash() else 1
    elif what == "pop":
        feedback()
    elif what in ("trash", "shutter"):
        effect(what)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0
