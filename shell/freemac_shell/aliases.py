# SPDX-License-Identifier: GPL-3.0-or-later
"""Aliases, as on a Mac: a small stand-in for a file, folder or app that opens
the original from anywhere, made with File > Make Alias
in Drawer or on the Desktop.

An alias here is a symbolic link to the original's full path, named as a
Mac names one ("Report.pdf alias", then "Report.pdf alias 2"). Its icon is
the original's with a small curved arrow in the corner. If the original is
moved away the alias is broken: opening it says so and offers to delete the
alias or choose a new original. Original freemac code.
"""
import math
import os

ARROW_SHARE = 0.36    # the badge's size, as a share of the icon


def is_alias(path):
    return os.path.islink(path)


def target(path):
    """The full path the alias points at, whether or not it is still there."""
    try:
        to = os.readlink(path)
    except OSError:
        return None
    return os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(path)), to))


def original(path):
    """The original's path, or None when the alias is broken."""
    if not is_alias(path):
        return None
    real = os.path.realpath(path)
    return real if os.path.exists(real) else None


def is_broken(path):
    return is_alias(path) and original(path) is None


def alias_name(path, folder=None):
    """A free name for an alias of path in folder: "name alias", then
    "name alias 2", "name alias 3" and so on."""
    folder = folder or os.path.dirname(os.path.abspath(path))
    base = os.path.basename(os.path.abspath(path).rstrip("/")) or "Computer"
    name = f"{base} alias"
    number = 2
    while os.path.lexists(os.path.join(folder, name)):
        name = f"{base} alias {number}"
        number += 1
    return os.path.join(folder, name)


def make(paths, folder=None):
    """Make an alias of each path, beside it or in folder; returns the
    aliases made. An alias of an alias points at the same original."""
    made = []
    for path in paths:
        full = os.path.abspath(path)
        if is_alias(full):
            full = target(full) or full
        where = alias_name(full, folder or os.path.dirname(os.path.abspath(path)))
        os.symlink(full, where)
        made.append(where)
    return made


def repoint(path, new_original):
    """Fix a broken alias (or change any alias) to point at new_original,
    keeping its name and place."""
    if not is_alias(path):
        raise OSError(22, "This item isn’t an alias.")
    spare = path + ".freemac-repoint"
    os.symlink(os.path.abspath(new_original), spare)
    os.replace(spare, path)


def badge(pixbuf):
    """The icon with an alias's arrow drawn in its lower-left corner."""
    if pixbuf is None:
        return None
    import cairo
    import gi
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk
    w, h = pixbuf.get_width(), pixbuf.get_height()
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    cr = cairo.Context(surface)
    Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
    cr.paint()
    draw_arrow(cr, 0, h - max(8, round(min(w, h) * ARROW_SHARE)), max(8, round(min(w, h) * ARROW_SHARE)))
    return Gdk.pixbuf_get_from_surface(surface, 0, 0, w, h)


def draw_arrow(cr, x, y, size):
    """A white rounded square with a black arrow curving up and to the right."""
    r = size * 0.22
    cr.save()
    cr.new_sub_path()
    cr.arc(x + size - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + size - r, y + size - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + size - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()
    cr.set_source_rgb(1, 1, 1)
    cr.fill_preserve()
    cr.set_source_rgba(0, 0, 0, 0.35)
    cr.set_line_width(max(0.6, size / 24))
    cr.stroke()
    # The shaft: from the lower left, curving up to the right.
    cr.set_source_rgb(0.08, 0.08, 0.1)
    cr.set_line_width(max(1.2, size * 0.13))
    cr.set_line_cap(cairo_round())
    cr.move_to(x + size * 0.28, y + size * 0.80)
    cr.curve_to(x + size * 0.28, y + size * 0.48, x + size * 0.40, y + size * 0.38, x + size * 0.60, y + size * 0.38)
    cr.stroke()
    # The head, pointing right.
    cr.move_to(x + size * 0.82, y + size * 0.38)
    cr.line_to(x + size * 0.56, y + size * 0.16)
    cr.line_to(x + size * 0.56, y + size * 0.60)
    cr.close_path()
    cr.fill()
    cr.restore()


def cairo_round():
    import cairo
    return cairo.LINE_CAP_ROUND


# ---- in windows ----------------------------------------------------------

DELETE_ALIAS, FIX_ALIAS = 1, 2


def choose_original(parent, path):
    """Ask for a new original for the alias at path and point it there;
    returns the new original, or None if none was chosen."""
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
    old = target(path) or ""
    # Guessed from the old name: "Notes.txt" was a file, "Photos" a folder.
    folder = not os.path.splitext(os.path.basename(old))[1]
    chooser = Gtk.FileChooserDialog(
        title="Select New Original", transient_for=parent, modal=True,
        action=Gtk.FileChooserAction.SELECT_FOLDER if folder else Gtk.FileChooserAction.OPEN)
    chooser.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Choose", Gtk.ResponseType.OK)
    chooser.set_default_response(Gtk.ResponseType.OK)
    start = os.path.dirname(old)
    while start and not os.path.isdir(start):
        start = os.path.dirname(start) if start != "/" else ""
    chooser.set_current_folder(start or os.path.expanduser("~"))
    chosen = chooser.get_filename() if chooser.run() == Gtk.ResponseType.OK else None
    chooser.destroy()
    if not chosen:
        return None
    try:
        repoint(path, chosen)
    except OSError as err:
        from . import alert
        alert.tell(parent, f"The alias “{os.path.basename(path)}” couldn’t be fixed.", err.strerror or "")
        return None
    return chosen


def ask_broken(parent, path):
    """Say that a broken alias can't be opened, as a Mac does, and offer to
    delete it or fix it. Returns the new original if it was fixed."""
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gio, GLib, Gtk
    from . import alert
    name = os.path.basename(path)
    answer = alert.ask(parent, f"The alias “{name}” can’t be opened because the original item can’t be found.",
                       "", [("Delete Alias", DELETE_ALIAS), ("Fix Alias…", FIX_ALIAS),
                            ("OK", Gtk.ResponseType.OK)], default=Gtk.ResponseType.OK)
    if answer == DELETE_ALIAS:
        try:
            Gio.File.new_for_path(path).trash(None)
        except GLib.Error as err:
            alert.tell(parent, f"The alias “{name}” couldn’t be moved to the Trash.", err.message)
        return None
    if answer == FIX_ALIAS:
        return choose_original(parent, path)
    return None
