# SPDX-License-Identifier: GPL-3.0-or-later
"""Quick Actions: small jobs on pictures, straight from a file's menu, as
Finder's Quick Actions are: Rotate Left, Rotate Right, and Create PDF, which
puts the pictures into one PDF, a page each.

A rotated picture is saved back in its own format (JPEG, PNG, TIFF, BMP);
pictures GdkPixbuf can't write (GIF, SVG, WebP) can't be rotated here, though
they can go into a PDF. Drawer and the desktop both use this. Original
freemac code.
"""
import os

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib  # noqa: E402

from . import transfer  # noqa: E402

SAVE_AS = {".jpg": "jpeg", ".jpeg": "jpeg", ".png": "png", ".tif": "tiff", ".tiff": "tiff", ".bmp": "bmp"}
PAGE_LONG = 842   # points: an A4 page's long side; each picture fits a page this size


def is_picture(path):
    if not os.path.isfile(path):
        return False
    kind, _uncertain = Gio.content_type_guess(path, None)
    return bool(kind) and kind.startswith("image/")


def can_rotate(paths):
    return bool(paths) and all(is_picture(p) and os.path.splitext(p)[1].lower() in SAVE_AS for p in paths)


def can_make_pdf(paths):
    return bool(paths) and all(is_picture(p) for p in paths)


def rotate(paths, clockwise):
    """Turn each picture a quarter turn and save it in place. Returns the
    first error, or None."""
    angle = GdkPixbuf.PixbufRotation.CLOCKWISE if clockwise else GdkPixbuf.PixbufRotation.COUNTERCLOCKWISE
    error = None
    for path in paths:
        kind = SAVE_AS.get(os.path.splitext(path)[1].lower())
        if kind is None:
            continue
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
            pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
            turned = pixbuf.rotate_simple(angle)
            keys, values = (["quality"], ["92"]) if kind == "jpeg" else ([], [])
            temp = os.path.join(os.path.dirname(path), f".{os.path.basename(path)}.turning")
            turned.savev(temp, kind, keys, values)
            os.replace(temp, path)
        except (GLib.Error, OSError) as err:
            error = error or err
    return error


def make_pdf(paths):
    """One PDF beside the pictures with a page for each, in the order given.
    Returns the PDF's path (or None) and the first error."""
    if not paths:
        return None, None
    folder = os.path.dirname(os.path.abspath(paths[0]))
    stem = os.path.splitext(os.path.basename(paths[0]))[0] if len(paths) == 1 else "Pictures"
    target = os.path.join(folder, transfer.free_name(folder, stem + ".pdf"))
    surface, error, pages = None, None, 0
    try:
        for path in paths:
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
            except GLib.Error as err:
                error = error or err
                continue
            pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
            w, h = pixbuf.get_width(), pixbuf.get_height()
            scale = min(1.0, PAGE_LONG / max(w, h))
            page_w, page_h = w * scale, h * scale
            if surface is None:
                surface = cairo.PDFSurface(target, page_w, page_h)
            else:
                surface.set_size(page_w, page_h)
            cr = cairo.Context(surface)
            cr.scale(scale, scale)
            Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
            cr.paint()
            cr.show_page()
            pages += 1
        if surface is not None:
            surface.finish()
    except (cairo.Error, OSError) as err:
        error = error or err
    if not pages:
        try:
            os.unlink(target)
        except OSError:
            pass
        return None, error
    transfer.note_done({"kind": "copy", "made": [target], "replaced": []})
    return target, error
