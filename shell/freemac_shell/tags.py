# SPDX-License-Identifier: GPL-3.0-or-later
"""Tags: coloured labels on files, as a Mac has.

A file's tags are kept with the file itself, the freedesktop way: the
user.xdg.tags extended attribute holds their names, comma-separated
("Red,Blue"). They stay with the file when it is renamed or moved on the
same disk, and other Linux file managers can read them. A drive that can't
keep extended attributes (FAT memory cards) can't keep tags either.

So that Drawer can show every file with a tag at once without searching the
whole disk, an index (~/.local/share/freemac/tags.json) notes where tagged
files were last seen. Tagging a file notes it; every folder Drawer or the
desktop reads brings the index up to date for that folder; and listing a
tag drops whatever has lost the tag or gone.

Drawer and the desktop both use this. Original freemac code.
"""
import json
import math
import os
from html import escape

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

ATTR = "user.xdg.tags"
COLORS = (("Red", "#f0453a"), ("Orange", "#f7962f"), ("Yellow", "#f2c12e"), ("Green", "#4cbf57"),
          ("Blue", "#3a8ef6"), ("Purple", "#a65fd6"), ("Gray", "#9a9aa0"))
COLOR = dict(COLORS)
INDEX = os.path.join(GLib.get_user_data_dir(), "freemac", "tags.json")
PREFIX = "tag:"   # Drawer's name for the place that lists one tag's files: "tag:Red"


def get(path):
    """The file's tags, in the order they were added."""
    try:
        raw = os.getxattr(path, ATTR, follow_symlinks=False)
    except OSError:
        return []
    return [t for t in (part.strip() for part in raw.decode("utf-8", "replace").split(",")) if t]


def put(path, names):
    """Set the file's tags; raises OSError when the disk can't keep them."""
    if names:
        os.setxattr(path, ATTR, ",".join(names).encode(), follow_symlinks=False)
    else:
        try:
            os.removexattr(path, ATTR, follow_symlinks=False)
        except OSError as err:
            if err.errno not in (61, 95):   # no tags there already, or none possible
                raise


def toggle(paths, name, adding=None):
    """Add the tag to every file, or take it off them all when all have it,
    as a click on a colour does in Finder (adding=True only adds). Returns
    the first error or None."""
    have = [name in get(p) for p in paths]
    if adding is None:
        adding = not all(have)
    error = None
    for path, had in zip(paths, have):
        current = get(path)
        if adding and not had:
            current.append(name)
        elif not adding:
            current = [t for t in current if t != name]
        else:
            continue
        try:
            put(path, current)
        except OSError as err:
            error = error or err
            continue
        note(path, current)
    return error


# ---- the index --------------------------------------------------------------
def _load():
    try:
        with open(INDEX) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _save(data):
    try:
        os.makedirs(os.path.dirname(INDEX), exist_ok=True)
        with open(INDEX + ".new", "w") as f:
            json.dump(data, f)
        os.replace(INDEX + ".new", INDEX)
    except OSError:
        pass


def note(path, names):
    data = _load()
    path = os.path.abspath(path)
    if names:
        data[path] = names
    else:
        data.pop(path, None)
    _save(data)


def note_folder(folder, found):
    """found: {path: tags} for the tagged files just read in folder. Brings
    the index up to date for that folder, writing only when it changed."""
    data = _load()
    folder = os.path.abspath(folder)
    changed = False
    for path in [p for p in data if os.path.dirname(p) == folder and p not in found]:
        del data[path]
        changed = True
    for path, names in found.items():
        if data.get(path) != names:
            data[path] = names
            changed = True
    if changed:
        _save(data)


def tagged(name):
    """Every file the index knows with this tag, checked against the file."""
    data = _load()
    out, changed = [], False
    for path in list(data):
        names = get(path) if os.path.lexists(path) else []
        if names != data[path]:
            changed = True
            if names:
                data[path] = names
            else:
                del data[path]
        if name in names:
            out.append(path)
    if changed:
        _save(data)
    return sorted(out, key=lambda p: os.path.basename(p).lower())


def used():
    """The tags in use that aren't one of the seven colours, for the sidebar."""
    extra = []
    for names in _load().values():
        for n in names:
            if n not in COLOR and n not in extra:
                extra.append(n)
    return sorted(extra, key=str.lower)


# ---- showing them -----------------------------------------------------------
def markup(name, names):
    """The file's name with a coloured dot for each tag, for Pango."""
    dots = "".join(f' <span foreground="{COLOR.get(n, "#9a9aa0")}">●</span>' for n in names[:3])
    return escape(name) + dots


def draw_dot(cr, x, y, radius, color, ring=False, tick=False):
    rgba = Gdk.RGBA()
    rgba.parse(color)
    cr.arc(x, y, radius, 0, 2 * math.pi)
    cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, 1)
    cr.fill_preserve()
    cr.set_source_rgba(0, 0, 0, 0.18)
    cr.set_line_width(1)
    cr.stroke()
    if ring:   # the one under the pointer
        cr.arc(x, y, radius + 2.5, 0, 2 * math.pi)
        cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, 0.55)
        cr.set_line_width(1.5)
        cr.stroke()
    if tick:   # every chosen file has it
        cr.set_source_rgba(1, 1, 1, 1)
        cr.set_line_width(1.8)
        cr.move_to(x - radius * 0.45, y)
        cr.line_to(x - radius * 0.1, y + radius * 0.38)
        cr.line_to(x + radius * 0.48, y - radius * 0.38)
        cr.stroke()


def dot(color, size=12):
    """A small coloured dot widget, for the sidebar and the path bar."""
    area = Gtk.DrawingArea()
    area.set_size_request(size + 4, size + 4)
    area.set_valign(Gtk.Align.CENTER)
    area.connect("draw", lambda w, cr: draw_dot(cr, w.get_allocated_width() / 2, w.get_allocated_height() / 2,
                                                 size / 2 - 0.5, color) or False)
    return area


_styled = []


def _style():
    """The row of colours doesn't light up as a whole; the dot under the
    pointer gets a ring instead."""
    if _styled:
        return
    provider = Gtk.CssProvider()
    provider.load_from_data(b"menuitem.tag-row:hover, menu menuitem.tag-row:hover "
                            b"{ background-color: transparent; background-image: none; color: inherit; }\n"
                            b"menuitem.tag-row:hover label { color: #8a8a90; }")
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
    _styled.append(provider)


def menu_item(paths, done):
    """A menu row of the seven colours, as in Finder's menu: a click on one
    adds that tag to the chosen files, or takes it off. done(error) after."""
    _style()
    item = Gtk.MenuItem()
    item.get_style_context().add_class("tag-row")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    title = Gtk.Label(label="Tags", xalign=0)
    title.get_style_context().add_class("dim-label")
    box.pack_start(title, False, False, 0)
    area = Gtk.DrawingArea()
    step, radius = 22, 7.5
    area.set_size_request(step * len(COLORS), 20)
    box.pack_start(area, False, False, 0)
    item.add(box)
    every = [set(get(p)) for p in paths]
    state = {"over": None}

    def which():
        # Where the pointer is over the row of dots (the event's own x may be
        # from the menu's window or the dots' own).
        window = area.get_window()
        seat = Gdk.Display.get_default().get_default_seat()
        if window is None or seat is None:
            return None
        x, y = window.get_device_position(seat.get_pointer())[1:3]
        index = int(x // step) if x >= 0 and -6 <= y <= area.get_allocated_height() + 6 else -1
        return index if 0 <= index < len(COLORS) else None

    def draw(_w, cr):
        for i, (name, color) in enumerate(COLORS):
            draw_dot(cr, i * step + step / 2, 10, radius, color, ring=i == state["over"],
                     tick=bool(every) and all(name in s for s in every))
        return False

    def motion(_w, event):
        over = which()
        if over != state["over"]:
            state["over"] = over
            area.queue_draw()
        return False

    def release(_w, event):
        index = which()
        if index is None:
            return True   # a click beside the dots does nothing
        error = toggle(paths, COLORS[index][0])
        menu = item.get_parent()
        if menu is not None:
            menu.popdown()
        done(error)
        return True

    area.connect("draw", draw)
    item.connect("motion-notify-event", motion)
    item.connect("leave-notify-event", lambda *_: (state.update(over=None), area.queue_draw()) and False)
    item.connect("button-release-event", release)
    return item
