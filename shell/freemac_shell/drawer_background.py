# SPDX-License-Identifier: GPL-3.0-or-later
"""View Options > Background for Drawer's icon view, as on a Mac: each folder
can show White (the usual), a colour, or a picture behind its icons.

A folder's background is its own: open another folder and you see that
folder's. The choices are kept in ~/.config/freemac/drawer-backgrounds.json,
keyed by the folder's path; a folder left at White has no entry. A picture
fills the window and stays put while the icons scroll. On a dark colour or
picture the names turn white, so they can still be read. Original freemac
code.
"""
import json
import os

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib  # noqa: E402

FILE = os.path.join(GLib.get_user_config_dir(), "freemac", "drawer-backgrounds.json")
KINDS = (("white", "White"), ("color", "Color"), ("picture", "Picture"))
DEFAULT_COLOR = "#cfe3f7"
# How bright the background may be before the names go white instead.
DARK_BELOW = 0.5
WHITE = {"kind": "white"}


def _read(path=FILE):
    try:
        with open(path, encoding="utf-8") as handle:
            saved = json.load(handle)
        return saved if isinstance(saved, dict) else {}
    except (OSError, ValueError):
        return {}


def _write(saved, path=FILE):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        temporary = path + ".new"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(saved, handle, indent=2, sort_keys=True)
        os.replace(temporary, path)
    except OSError:
        pass


def _clean(setting):
    """A saved setting as one we can draw, or White."""
    if not isinstance(setting, dict):
        return dict(WHITE)
    kind = setting.get("kind")
    if kind == "color" and parse(setting.get("color")) is not None:
        return {"kind": "color", "color": setting["color"]}
    if kind == "picture" and isinstance(setting.get("picture"), str):
        return {"kind": "picture", "picture": setting["picture"],
                "color": setting.get("color") if parse(setting.get("color")) else DEFAULT_COLOR}
    return dict(WHITE)


def of(folder, path=FILE):
    """The background setting for folder: {"kind", and "color" or "picture"}."""
    return _clean(_read(path).get(folder))


def put(folder, setting, path=FILE):
    """Keep folder's background; White takes its entry away."""
    saved = _read(path)
    setting = _clean(setting)
    if setting["kind"] == "white":
        saved.pop(folder, None)
    else:
        saved[folder] = setting
    _write(saved, path)


def moved(old, new, path=FILE):
    """A folder (or one inside it) was renamed or moved: its background goes
    with it."""
    saved = _read(path)
    changed = False
    for key in list(saved):
        if key == old or key.startswith(old.rstrip("/") + "/"):
            saved[new + key[len(old):]] = saved.pop(key)
            changed = True
    if changed:
        _write(saved, path)


def parse(text):
    """'#rrggbb' as a Gdk.RGBA, or None."""
    if not isinstance(text, str):
        return None
    rgba = Gdk.RGBA()
    return rgba if rgba.parse(text) else None


def hex_of(rgba):
    return "#%02x%02x%02x" % tuple(round(max(0.0, min(1.0, c)) * 255) for c in (rgba.red, rgba.green, rgba.blue))


def brightness(red, green, blue):
    """How light a colour looks, 0 to 1 (the usual luma weights)."""
    return 0.299 * red + 0.587 * green + 0.114 * blue


def picture_brightness(picture):
    """How light a picture looks overall, 0 to 1, or None if it can't be read."""
    try:
        small = GdkPixbuf.Pixbuf.new_from_file_at_scale(picture, 24, 24, False)
    except GLib.Error:
        return None
    data, channels, stride = small.get_pixels(), small.get_n_channels(), small.get_rowstride()
    total = count = 0
    for y in range(small.get_height()):
        for x in range(small.get_width()):
            at = y * stride + x * channels
            total += brightness(data[at] / 255, data[at + 1] / 255, data[at + 2] / 255)
            count += 1
    return total / count if count else None


def styles(setting):
    """(CSS for the scrolled window behind the icons, CSS for the icon view)
    that draw setting. White gives two empty rules, so the theme's own look
    comes back."""
    setting = _clean(setting)
    if setting["kind"] == "color":
        rgba = parse(setting["color"])
        dark = brightness(rgba.red, rgba.green, rgba.blue) < DARK_BELOW
        behind = f"scrolledwindow {{ background-color: {setting['color']}; }}"
        shadow = ""
    elif setting["kind"] == "picture" and os.path.isfile(setting["picture"]):
        light = picture_brightness(setting["picture"])
        dark = light is not None and light < DARK_BELOW
        uri = Gio.File.new_for_path(setting["picture"]).get_uri().replace('"', "%22")
        behind = ("scrolledwindow { background-color: %s; background-image: url(\"%s\");"
                  " background-size: cover; background-position: center;"
                  " background-repeat: no-repeat; }" % (setting["color"], uri))
        # Names on a picture keep a soft shadow, light or dark, to stand out.
        shadow = " text-shadow: 0 1px 2px rgba(0,0,0,0.6);" if dark else " text-shadow: 0 0 3px rgba(255,255,255,0.9);"
    else:
        return "scrolledwindow {}", "iconview {}"
    ink = "white" if dark else "#1d1d1f"
    return behind, f"iconview:not(:selected) {{ background-color: transparent; color: {ink};{shadow} }}"
