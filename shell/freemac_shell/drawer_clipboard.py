# SPDX-License-Identifier: GPL-3.0-or-later
"""Edit > Show Clipboard, as in a Mac's Finder: a window that shows what's
on the clipboard now (words, a picture or the files copied) and changes as
soon as something else is copied. Original freemac code.
"""
import os

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import transfer  # noqa: E402

LONGEST = 200_000      # characters of text shown; the rest is left out
PICTURE = (420, 300)   # the largest a picture is shown


def describe_text(text):
    """The line under the window for some words."""
    words = len(text.split())
    if not words:
        return "Clipboard contents: blank text"
    return f"Clipboard contents: text ({words:,} word{'s' if words != 1 else ''})"


def describe_files(paths):
    folders = sum(1 for p in paths if os.path.isdir(p))
    files = len(paths) - folders
    parts = []
    if files:
        parts.append(f"{files} file{'s' if files != 1 else ''}")
    if folders:
        parts.append(f"{folders} folder{'s' if folders != 1 else ''}")
    return "Clipboard contents: " + " and ".join(parts)


def fit(width, height, most=PICTURE):
    """width and height made small enough to show, never larger."""
    scale = min(1.0, most[0] / max(width, 1), most[1] / max(height, 1))
    return max(1, round(width * scale)), max(1, round(height * scale))


class ClipboardWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Clipboard")
        self.set_default_size(460, 340)
        self.clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        self.handler = self.clipboard.connect("owner-change", lambda *_: self.refresh())
        self.connect("destroy", lambda *_: self.clipboard.disconnect(self.handler))
        self.connect("key-press-event", self._key)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.stack = Gtk.Stack()
        self.text = Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                                 left_margin=12, right_margin=12, top_margin=10, bottom_margin=10)
        scroller = Gtk.ScrolledWindow()
        scroller.add(self.text)
        self.stack.add_named(scroller, "text")
        self.picture = Gtk.Image()
        self.stack.add_named(self.picture, "picture")
        self.files = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        files_scroller = Gtk.ScrolledWindow()
        files_scroller.add(self.files)
        self.stack.add_named(files_scroller, "files")
        self.empty = Gtk.Label(label="The clipboard is empty.")
        self.empty.get_style_context().add_class("dim-label")
        self.stack.add_named(self.empty, "empty")
        box.pack_start(self.stack, True, True, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)
        self.status = Gtk.Label(xalign=0, margin=8, margin_start=12)
        self.status.get_style_context().add_class("dim-label")
        box.pack_start(self.status, False, False, 0)
        self.add(box)
        self.refresh()

    def refresh(self):
        """Look at the clipboard again: files first, then a picture, then words."""
        self.clipboard.request_targets(self._got_targets)

    def _got_targets(self, _clipboard, atoms, _count=None):
        names = {a.name() for a in (atoms or [])}
        if not names:
            self._show_empty()
            return
        paths = transfer.pasted_files()
        if paths:
            self._show_files(paths)
        elif any(n.startswith("image/") for n in names):
            self.clipboard.request_image(lambda _c, pixbuf: self._show_picture(pixbuf))
        else:
            self.clipboard.request_text(lambda _c, text: self._show_text(text))

    def _show_empty(self):
        self.stack.set_visible_child_name("empty")
        self.status.set_text("Clipboard contents: none")

    def _show_text(self, text):
        if text is None:
            self._show_empty()
            return
        shown = text if len(text) <= LONGEST else text[:LONGEST] + "\n…"
        self.text.get_buffer().set_text(shown)
        self.stack.set_visible_child_name("text")
        self.status.set_text(describe_text(text))

    def _show_picture(self, pixbuf):
        if pixbuf is None:
            self.clipboard.request_text(lambda _c, text: self._show_text(text))
            return
        width, height = pixbuf.get_width(), pixbuf.get_height()
        shown = fit(width, height)
        self.picture.set_from_pixbuf(pixbuf.scale_simple(shown[0], shown[1], GdkPixbuf.InterpType.BILINEAR)
                                     if shown != (width, height) else pixbuf)
        self.stack.set_visible_child_name("picture")
        self.status.set_text(f"Clipboard contents: picture ({width} × {height})")

    def _show_files(self, paths):
        for child in self.files.get_children():
            child.destroy()
        for path in paths[:500]:
            row = Gtk.Box(spacing=8, margin=4, margin_start=12)
            try:
                info = Gio.File.new_for_path(path).query_info("standard::icon",
                                                              Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, None)
                icon = Gtk.Image.new_from_gicon(info.get_icon(), Gtk.IconSize.LARGE_TOOLBAR)
            except GLib.Error:
                icon = Gtk.Image.new_from_icon_name("text-x-generic", Gtk.IconSize.LARGE_TOOLBAR)
            row.pack_start(icon, False, False, 0)
            row.pack_start(Gtk.Label(label=os.path.basename(path.rstrip(os.sep)) or path, xalign=0),
                           False, False, 0)
            where = Gtk.Label(label=os.path.dirname(path), xalign=0, ellipsize=3)
            where.get_style_context().add_class("dim-label")
            row.pack_start(where, True, True, 0)
            self.files.add(row)
        self.files.show_all()
        self.stack.set_visible_child_name("files")
        self.status.set_text(describe_files(paths))

    def _key(self, _w, event):
        if event.keyval == Gdk.KEY_Escape or (event.state & Gdk.ModifierType.CONTROL_MASK and
                                              event.keyval in (Gdk.KEY_w, Gdk.KEY_W)):
            self.destroy()
            return True
        return False


WINDOW = [None]


def show(parent=None):
    """Show the Clipboard window, or bring it to the front if it's open."""
    if WINDOW[0] is None:
        window = ClipboardWindow()
        WINDOW[0] = window
        window.connect("destroy", lambda *_: WINDOW.__setitem__(0, None))
        if parent is not None and parent.get_application() is not None:
            parent.get_application().add_window(window)
        window.show_all()
    WINDOW[0].present()
    return WINDOW[0]
