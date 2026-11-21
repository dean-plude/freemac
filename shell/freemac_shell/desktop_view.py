# SPDX-License-Identifier: GPL-3.0-or-later
"""The desktop's View Options, as a Mac's Show View Options (⌘J) on the
desktop: icon size, grid spacing, text size and Show item info.

They are kept in ~/.config/freemac/desktop-view.json. The panel runs as its
own small process (`python3 -m freemac_shell.desktop_view`), since windows
the layer-shell desktop opens itself get the wrong frame; it writes the file
as each setting changes and the desktop, watching that file, redraws its
icons. Original freemac code.
"""
import json
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from .apps import DESKTOP_WINDOW  # noqa: E402

PATH = os.path.join(GLib.get_user_config_dir(), "freemac", "desktop-view.json")
TEXT_SIZES = (10, 11, 12, 13, 14, 15, 16)   # pixels
DEFAULTS = {"icon_size": 64, "grid_spacing": 0, "text_size": 12}


def _clamp(value, low, high, default, step=1):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return default
    return min(high, max(low, int(value) // step * step))


def load():
    """The settings, with anything missing or odd replaced by its default.
    item_info is None when it has never been set here."""
    try:
        with open(PATH) as fh:
            data = json.load(fh)
        data = data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        data = {}
    item_info = data.get("item_info")
    return {
        "icon_size": _clamp(data.get("icon_size"), 32, 128, DEFAULTS["icon_size"], 4),
        "grid_spacing": _clamp(data.get("grid_spacing"), 0, 60, DEFAULTS["grid_spacing"]),
        "text_size": data.get("text_size") if data.get("text_size") in TEXT_SIZES else DEFAULTS["text_size"],
        "item_info": item_info if isinstance(item_info, bool) else None,
    }


def save(**changes):
    settings = load()
    settings.update(changes)
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    tmp = PATH + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(settings, fh, indent=1)
    os.replace(tmp, PATH)


def cell_size(settings):
    """One place on the desktop's grid, (width, height), for these settings:
    room for the icon, two lines of its name and the gap between places."""
    icon, gap, text = settings["icon_size"], settings["grid_spacing"], settings["text_size"]
    return max(100, icon + 36) + gap, icon + 40 + 2 * (text - 12) + gap


def panel(item_info_now=False):
    """The View Options window. Changes are written as they are made."""
    settings = load()
    window = Gtk.Window(title="Desktop", resizable=False, type_hint=Gdk.WindowTypeHint.DIALOG)
    window.set_position(Gtk.WindowPosition.CENTER)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=14)
    box.set_size_request(260, -1)
    window.add(box)

    def slider(title, low, high, step, value, icons, changed):
        label = Gtk.Label(label=title, xalign=0)
        label.get_style_context().add_class("dim-label")
        box.pack_start(label, False, False, 0)
        row = Gtk.Box(spacing=6)
        row.pack_start(Gtk.Image.new_from_icon_name(icons, Gtk.IconSize.MENU), False, False, 0)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, low, high, step)
        scale.set_draw_value(False)
        scale.set_value(value)
        scale.connect("value-changed", changed)
        row.pack_start(scale, True, True, 0)
        row.pack_start(Gtk.Image.new_from_icon_name(icons, Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
        box.pack_start(row, False, False, 0)
        return scale

    pending = {}

    def later(**change):
        # A slider sends many values as it moves; write a moment after it rests.
        pending.update(change)
        if not pending.get("_timer"):
            pending["_timer"] = GLib.timeout_add(150, flush)

    def flush():
        pending.pop("_timer", None)
        if pending:
            save(**pending)
            pending.clear()
        return False

    icon_scale = slider("Icon size:", 32, 128, 4, settings["icon_size"], "image-x-generic-symbolic",
           lambda s: later(icon_size=int(round(s.get_value() / 4)) * 4))
    gap_scale = slider("Grid spacing:", 0, 60, 2, settings["grid_spacing"], "view-grid-symbolic",
           lambda s: later(grid_spacing=int(s.get_value())))
    row = Gtk.Box(spacing=8)
    row.pack_start(Gtk.Label(label="Text size:", xalign=0), False, False, 0)
    sizes = Gtk.ComboBoxText()
    for size in TEXT_SIZES:
        sizes.append(str(size), str(size))
    sizes.set_active_id(str(settings["text_size"]))
    sizes.connect("changed", lambda c: save(text_size=int(c.get_active_id())))
    row.pack_end(sizes, False, False, 0)
    box.pack_start(row, False, False, 4)
    shown = settings["item_info"] if settings["item_info"] is not None else item_info_now
    info = Gtk.CheckButton(label="Show item info", active=shown)
    info.connect("toggled", lambda b: save(item_info=b.get_active()))
    box.pack_start(info, False, False, 0)
    defaults = Gtk.Button(label="Use Defaults", halign=Gtk.Align.END)

    def use_defaults(_button):
        icon_scale.set_value(DEFAULTS["icon_size"])
        gap_scale.set_value(DEFAULTS["grid_spacing"])
        sizes.set_active_id(str(DEFAULTS["text_size"]))
    defaults.connect("clicked", use_defaults)
    box.pack_start(defaults, False, False, 6)

    def done(*_):
        flush()
        Gtk.main_quit()
    window.connect("destroy", done)
    window.connect("key-press-event", lambda w, e: (e.keyval == Gdk.KEY_Escape or (
        e.keyval in (Gdk.KEY_w, Gdk.KEY_j) and e.state & Gdk.ModifierType.CONTROL_MASK)) and (w.destroy() or True))
    window.show_all()
    return window


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    GLib.set_prgname(DESKTOP_WINDOW)   # the desktop's window: the menu bar says Drawer
    panel(item_info_now="--item-info" in argv)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
