# SPDX-License-Identifier: GPL-3.0-or-later
"""PDF pages as pictures, through the Poppler library, for Frame (which
opens PDFs), Seek's preview and Drawer's Glance. Without Poppler, nothing
here opens a PDF and the callers fall back to an icon. Original freemac code.
"""
import gi

gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib  # noqa: E402

try:
    gi.require_version("Poppler", "0.18")
    from gi.repository import Poppler  # noqa: E402
    import cairo  # noqa: E402
except (ValueError, ImportError):
    Poppler = None

LARGEST = 2400   # most pixels a page is drawn across


def is_pdf(path):
    kind, _uncertain = Gio.content_type_guess(path, None)
    return path.lower().endswith(".pdf") or Gio.content_type_is_a(kind or "", "application/pdf")


def open_document(path):
    """The PDF at path, or None (not a PDF, locked, or no Poppler)."""
    if Poppler is None:
        return None
    try:
        return Poppler.Document.new_from_file(Gio.File.new_for_path(path).get_uri(), None)
    except GLib.Error:
        return None


def page_pixbuf(document, index, size):
    """Page index (from 0) drawn on white so that its longer side is about
    size pixels (at most LARGEST), as a GdkPixbuf; None if it can't be."""
    if document is None or not 0 <= index < document.get_n_pages():
        return None
    page = document.get_page(index)
    width, height = page.get_size()
    if width <= 0 or height <= 0:
        return None
    scale = min(size, LARGEST) / max(width, height)
    w, h = max(1, round(width * scale)), max(1, round(height * scale))
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(surface)
    ctx.set_source_rgb(1, 1, 1)
    ctx.paint()
    ctx.scale(scale, scale)
    page.render(ctx)
    surface.flush()
    return Gdk.pixbuf_get_from_surface(surface, 0, 0, w, h)


def first_page(path, size):
    """The first page of the PDF at path as a picture, or None."""
    return page_pixbuf(open_document(path), 0, size)
