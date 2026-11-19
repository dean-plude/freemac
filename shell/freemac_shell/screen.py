# SPDX-License-Identifier: GPL-3.0-or-later
"""Screen brightness and night light, shared by Dials and Topline.

Brightness: the laptop panel's backlight in /sys/class/backlight, set through
logind (org.freedesktop.login1.Session.SetBrightness), which lets the person
at the seat change it without a password. Desktop monitors set their own
brightness and have no backlight here.

Night light: wlsunset (Wayland's gamma control) makes colours warmer between
two times of day. The settings live in ~/.config/freemac/nightlight.json;
freemac-nightlight runs at login and starts wlsunset when it's on.
"""
import json
import os
import subprocess
import sys

from gi.repository import Gio, GLib

BACKLIGHT = "/sys/class/backlight"
CONFIG = os.path.join(GLib.get_user_config_dir(), "freemac", "nightlight.json")
DEFAULTS = {"on": False, "from": "20:00", "to": "07:00", "warmth": 4000}
DAYLIGHT = 6500   # colour temperature (kelvin) outside night light hours


# -- brightness ----------------------------------------------------------------
def backlight():
    """(name, max) of the backlight to use, or None. Firmware and raw devices
    are picked over platform ones, as most desktops do."""
    try:
        names = sorted(os.listdir(BACKLIGHT))
    except OSError:
        return None
    best = None
    for name in names:
        try:
            with open(os.path.join(BACKLIGHT, name, "type")) as f:
                kind = f.read().strip()
            with open(os.path.join(BACKLIGHT, name, "max_brightness")) as f:
                top = int(f.read())
        except (OSError, ValueError):
            continue
        rank = {"firmware": 0, "platform": 1, "raw": 2}.get(kind, 3)
        if top > 0 and (best is None or rank < best[0]):
            best = (rank, name, top)
    return best and (best[1], best[2])


def brightness():
    """Brightness as 0..1, or None without a backlight."""
    device = backlight()
    if not device:
        return None
    try:
        with open(os.path.join(BACKLIGHT, device[0], "brightness")) as f:
            return int(f.read()) / device[1]
    except (OSError, ValueError):
        return None


def set_brightness(fraction):
    device = backlight()
    if not device:
        return False
    # Never all the way to black: a screen at 0 can look switched off.
    value = max(1, round(max(0.0, min(1.0, fraction)) * device[1]))
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        bus.call_sync("org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                      "org.freedesktop.login1.Session", "SetBrightness",
                      GLib.Variant("(ssu)", ("backlight", device[0], value)),
                      None, Gio.DBusCallFlags.NONE, 2000, None)
        return True
    except GLib.Error:
        return False


# -- night light ---------------------------------------------------------------
def night_settings():
    settings = dict(DEFAULTS)
    try:
        with open(CONFIG) as f:
            settings.update({k: v for k, v in json.load(f).items() if k in DEFAULTS})
    except (OSError, ValueError, AttributeError):
        pass
    return settings


def save_night_settings(settings):
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    with open(CONFIG, "w") as f:
        json.dump({k: settings.get(k, v) for k, v in DEFAULTS.items()}, f, indent=2)
    restart_night_light()


def wlsunset_command(settings):
    warmth = max(2500, min(DAYLIGHT - 100, int(settings["warmth"])))
    # -s is when it gets warm (sunset), -S when it goes back (sunrise);
    # -d spreads the change over half an hour.
    return ["wlsunset", "-t", str(warmth), "-T", str(DAYLIGHT),
            "-s", settings["from"], "-S", settings["to"], "-d", "1800"]


def restart_night_light():
    """Stop this user's wlsunset and start it again with the saved settings."""
    subprocess.run(["pkill", "-u", str(os.getuid()), "-x", "wlsunset"], check=False)
    try:
        subprocess.Popen(["freemac-nightlight"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def main():
    """freemac-nightlight: become wlsunset if night light is on."""
    settings = night_settings()
    if not settings["on"]:
        return 0
    try:
        os.execvp("wlsunset", wlsunset_command(settings))
    except OSError:
        print("freemac-nightlight: wlsunset isn't installed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
