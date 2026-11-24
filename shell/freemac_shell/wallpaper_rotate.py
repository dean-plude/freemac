# SPDX-License-Identifier: GPL-3.0-or-later
"""Change picture, as on a Mac: the wallpaper moves on to the next picture
every few minutes, every hour, every day or each time you log in, from
freemac's own wallpapers or a folder of your pictures, in order or at random.

Dials > Wallpaper writes the choice to the [background] section of
~/.config/wf-shell.ini:

    rotate        never | 300 | 900 | 1800 | 3600 | 86400 | login
    rotate_from   a folder, or empty for freemac's own wallpapers
    rotate_random true | false
    rotate_last   when the picture last changed (seconds since 1970)

Backdrop, which runs for the whole session, calls tick() once a minute and
login() when it starts; a change is written back as the image key, so Dials
and everything that follows the wallpaper sees it. Original freemac code.
"""
import os
import random
import time

from .ini import ini_get, ini_set

CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "wf-shell.ini")
WALLPAPERS = "/usr/share/backgrounds/freemac"
# freemac's own scenes as (day, night); the same list as Backdrop's.
SCENES = (("dusk-tide.png", "night-tide.png"), ("lagoon-day.png", "lagoon-night.png"),
          ("prism-day.png", "prism-night.png"), ("harbor-day.png", "harbor-night.png"))
PICTURES = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tif", ".tiff")
# (setting, words), in the order Dials lists them.
CHOICES = (("never", "Never"), ("300", "Every 5 minutes"), ("900", "Every 15 minutes"),
           ("1800", "Every 30 minutes"), ("3600", "Every hour"), ("86400", "Every day"),
           ("login", "When logging in"))
MOST = 2000   # pictures looked at in one folder


def candidates(folder, dark=False):
    """The pictures to go through, sorted by name. freemac's own scenes count
    once each, in the version for light or dark mode."""
    if not folder:
        night = {n for _d, n in SCENES}
        found = []
        for day, night_name in SCENES:
            path = os.path.join(WALLPAPERS, night_name if dark else day)
            if os.path.exists(path):
                found.append(path)
        try:
            names = sorted(os.listdir(WALLPAPERS))
        except OSError:
            names = []
        days = {d for d, _n in SCENES}
        found += [os.path.join(WALLPAPERS, n) for n in names
                  if n.lower().endswith(PICTURES) and n not in days and n not in night]
        return found
    try:
        names = sorted((n for n in os.listdir(folder) if not n.startswith(".")), key=str.lower)
    except OSError:
        return []
    return [os.path.join(folder, n) for n in names[:MOST]
            if n.lower().endswith(PICTURES) and os.path.isfile(os.path.join(folder, n))]


def same_picture(a, b):
    """True for the same picture, counting a scene's day and night as one."""
    if a == b:
        return True
    for day, night in SCENES:
        pair = {os.path.join(WALLPAPERS, day), os.path.join(WALLPAPERS, night)}
        if a in pair and b in pair:
            return True
    return False


def next_picture(current, pictures, shuffle=False, rng=random):
    """The picture after current: the next one by name, or any other at random."""
    if not pictures:
        return None
    others = [p for p in pictures if not same_picture(p, current)]
    if not others:
        return None
    if shuffle:
        return rng.choice(others)
    for index, path in enumerate(pictures):
        if same_picture(path, current):
            return pictures[(index + 1) % len(pictures)] if len(pictures) > 1 else None
    return pictures[0]


def settings(path=CONFIG):
    every = ini_get(path, "background", "rotate", "never") or "never"
    if every not in {c for c, _w in CHOICES}:
        every = "never"
    return {"every": every,
            "folder": os.path.expanduser(ini_get(path, "background", "rotate_from", "") or ""),
            "random": (ini_get(path, "background", "rotate_random", "false") or "").lower() == "true",
            "last": float(ini_get(path, "background", "rotate_last", "0") or 0)}


def due(choice, last, now):
    """True when a timed choice has waited long enough."""
    if choice in ("never", "login"):
        return False
    return now - last >= int(choice)


def change(path=CONFIG, dark=False, now=None):
    """Move to the next picture; returns it, or None if there's no other."""
    found = settings(path)
    current = ini_get(path, "background", "image", "") or ""
    picture = next_picture(current, candidates(found["folder"], dark), found["random"])
    ini_set(path, "background", "rotate_last", str(int(now if now is not None else time.time())))
    if picture:
        ini_set(path, "background", "image", picture)
    return picture


def tick(path=CONFIG, dark=False, now=None):
    """Called once a minute: change the picture if it's time."""
    now = now if now is not None else time.time()
    found = settings(path)
    if found["every"] in ("never", "login"):
        return None
    if found["last"] <= 0 or found["last"] > now:
        # Just switched on (or the clock went back): start counting now.
        ini_set(path, "background", "rotate_last", str(int(now)))
        return None
    if due(found["every"], found["last"], now):
        return change(path, dark, now)
    return None


def login(path=CONFIG, dark=False):
    """Called when the session starts: When logging in changes it now."""
    if settings(path)["every"] == "login":
        return change(path, dark)
    return None
