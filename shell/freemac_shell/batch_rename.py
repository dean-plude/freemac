# SPDX-License-Identifier: GPL-3.0-or-later
"""Rename several files at once, as Finder's Rename Items does: replace text
in their names, add text before or after the names, or give them all one
name with a number (1, 2, 3 or 00001…) or today's date.

The extension stays as it is. Names are worked out first, then checked: a
name that is empty, has a slash, is taken by another file or is given to two
files stops the whole rename, so nothing is half done. Drawer and the desktop
both use this; one Undo puts every name back. Original freemac code.
"""
import datetime
import json
import os
import re
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

from . import transfer  # noqa: E402
from .apps import DESKTOP_WINDOW  # noqa: E402

FORMATS = (("index", "Name and Index"), ("counter", "Name and Counter"), ("date", "Name and Date"))


def _split(name, is_dir):
    if is_dir:
        return name, ""
    stem, ext = os.path.splitext(name)
    if not stem:          # ".bashrc": all of it is the name
        return name, ""
    return stem, ext


def new_names(items, how):
    """items: [(name, is_dir)]. how: a dict with "mode" ("replace", "add" or
    "format") and that mode's settings. Returns the new names, in order."""
    mode = how.get("mode", "replace")
    out = []
    for i, (name, is_dir) in enumerate(items):
        stem, ext = _split(name, is_dir)
        if mode == "replace":
            find = how.get("find", "")
            stem = stem.replace(find, how.get("replace", "")) if find else stem
        elif mode == "add":
            text = how.get("text", "")
            stem = text + stem if how.get("before") else stem + text
        else:
            base = how.get("base", "")
            kind = how.get("format", "index")
            start = int(how.get("start", 1))
            if kind == "date":
                tag = datetime.date.today().isoformat()
                tag = f"{tag} {i + 1}" if len(items) > 1 else tag
            elif kind == "counter":
                tag = f"{start + i:05d}"
            else:
                tag = str(start + i)
            stem = f"{tag} {base}".strip() if how.get("before") else f"{base} {tag}".strip()
        out.append(stem + ext)
    return out


def problem(paths, names):
    """Why these new names can't be used, or None."""
    folders_seen = set()
    old = {os.path.abspath(p) for p in paths}
    for path, name in zip(paths, names):
        if not name.strip() or name in (".", ".."):
            return "A name can't be empty."
        if "/" in name:
            return "A name can't have a slash (/) in it."
        target = os.path.abspath(os.path.join(os.path.dirname(path), name))
        if target in folders_seen:
            return f"Two items would both be called “{name}”."
        folders_seen.add(target)
        if target not in old and os.path.lexists(target):
            return f"“{name}” is already taken."
    return None


def apply(paths, names, remember=True):
    """Rename paths to names (in their own folders). Goes through hidden
    temporary names first, so swapping names between items works. Returns the
    (old, new) pairs done and the first error."""
    jobs = [(p, os.path.join(os.path.dirname(p), n)) for p, n in zip(paths, names)
            if os.path.basename(p) != n]
    staged, done, error = [], [], None
    for i, (old, new) in enumerate(jobs):
        temp = os.path.join(os.path.dirname(old), f".freemac-rename-{os.getpid()}-{i}")
        try:
            os.rename(old, temp)
            staged.append((old, temp, new))
        except OSError as err:
            error = error or err
    for old, temp, new in staged:
        try:
            os.rename(temp, new)
            done.append((old, new))
        except OSError as err:
            error = error or err
            try:
                os.rename(temp, old)
            except OSError:
                pass
    if done and remember:
        transfer.note_done({"kind": "renames", "pairs": done})
    return done, error


def _in_order(path):
    """Sort as a person would: "Photo 2" before "Photo 10"."""
    name = os.path.basename(path).casefold()
    return [(0, int(part), "") if part.isdigit() else (1, 0, part) for part in re.split(r"(\d+)", name)]


def ask(parent, paths, notify=None):
    """The Rename Items window. Returns the (old, new) pairs renamed."""
    paths = sorted((os.path.abspath(p) for p in paths), key=_in_order)
    items = [(os.path.basename(p), os.path.isdir(p)) for p in paths]
    say = notify or (lambda _t: None)
    dialog = Gtk.Dialog(title=f"Rename {len(paths)} Items", transient_for=parent, modal=True)
    dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Rename", Gtk.ResponseType.OK)
    dialog.set_default_response(Gtk.ResponseType.OK)
    dialog.set_resizable(False)   # fit the rows shown, with or without a parent window
    grid = Gtk.Grid(column_spacing=8, row_spacing=8, margin=14)
    dialog.get_content_area().pack_start(grid, True, True, 0)

    mode = Gtk.ComboBoxText()
    for key, label in (("replace", "Replace Text"), ("add", "Add Text"), ("format", "Format")):
        mode.append(key, label)
    mode.set_active_id("replace")
    grid.attach(mode, 0, 0, 2, 1)

    def entry(text=""):
        e = Gtk.Entry(text=text, width_chars=28, activates_default=True)
        return e

    def label(text):
        return Gtk.Label(label=text, xalign=1)

    find, replace = entry(), entry()
    add_text = entry()
    add_where = Gtk.ComboBoxText()
    add_where.append("after", "after name")
    add_where.append("before", "before name")
    add_where.set_active_id("after")
    fmt = Gtk.ComboBoxText()
    for key, text in FORMATS:
        fmt.append(key, text)
    fmt.set_active_id("index")
    fmt_where = Gtk.ComboBoxText()
    fmt_where.append("after", "after name")
    fmt_where.append("before", "before name")
    fmt_where.set_active_id("after")
    base = entry(os.path.splitext(items[0][0])[0] if items and not items[0][1] else (items[0][0] if items else ""))
    start = Gtk.SpinButton.new_with_range(0, 999999, 1)
    start.set_value(1)
    start.set_activates_default(True)

    pages = {
        "replace": [(label("Find:"), find), (label("Replace with:"), replace)],
        "add": [(label("Add:"), add_text), (label("Where:"), add_where)],
        "format": [(label("Format:"), fmt), (label("Where:"), fmt_where),
                   (label("Custom Format:"), base), (label("Start numbers at:"), start)],
    }
    row = 1
    for rows in pages.values():
        for left, right in rows:
            grid.attach(left, 0, row, 1, 1)
            grid.attach(right, 1, row, 1, 1)
            left.set_no_show_all(True)    # only the chosen mode's rows are ever shown, so
            right.set_no_show_all(True)   # the window is never sized for all of them
            row += 1
    example = Gtk.Label(xalign=0, ellipsize=3, max_width_chars=40)
    example.get_style_context().add_class("dim-label")
    grid.attach(example, 0, row, 2, 1)
    warning = Gtk.Label(xalign=0, wrap=True, max_width_chars=40)
    warning.set_no_show_all(True)
    grid.attach(warning, 0, row + 1, 2, 1)

    def settings():
        m = mode.get_active_id()
        return {
            "mode": m, "find": find.get_text(), "replace": replace.get_text(),
            "text": add_text.get_text(),
            "before": (add_where if m == "add" else fmt_where).get_active_id() == "before",
            "format": fmt.get_active_id(), "base": base.get_text(), "start": start.get_value_as_int(),
        }

    def update(*_):
        m = mode.get_active_id()
        for key, rows in pages.items():
            for left, right in rows:
                left.set_visible(key == m)
                right.set_visible(key == m)
        start.set_sensitive(fmt.get_active_id() != "date")
        names = new_names(items, settings())
        example.set_text(f"Example: {names[0]}" if names else "")
        why = problem(paths, names)
        warning.set_text(why or "")
        warning.set_visible(bool(why))
        unchanged = all(a == b for (a, _d), b in zip(items, names))
        dialog.set_response_sensitive(Gtk.ResponseType.OK, not why and not unchanged)

    for widget in (find, replace, add_text, base):
        widget.connect("changed", update)
    for widget in (mode, add_where, fmt, fmt_where):
        widget.connect("changed", update)
    start.connect("value-changed", update)
    update()
    grid.show_all()
    renamed = []
    if dialog.run() == Gtk.ResponseType.OK:
        names = new_names(items, settings())
        why = problem(paths, names)
        if why:
            say(why)
        else:
            done, error = apply(paths, names)
            renamed = done
            if error:
                say(f"Couldn’t rename every item: {error.strerror}.")
    dialog.destroy()
    return renamed


def main(argv=None):
    """`python3 -m freemac_shell.batch_rename PATH...`: the window on its own,
    for the desktop, which gives windows it opens itself the wrong size. Prints
    the (old, new) pairs renamed as JSON."""
    paths = [p for p in (argv if argv is not None else sys.argv[1:]) if os.path.lexists(p)]
    GLib.set_prgname(DESKTOP_WINDOW)   # the desktop's window: the menu bar says Drawer
    done = ask(None, paths) if len(paths) > 1 else []
    print(json.dumps(done))
    return 0


if __name__ == "__main__":
    sys.exit(main())
