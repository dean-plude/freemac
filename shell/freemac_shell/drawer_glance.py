# SPDX-License-Identifier: GPL-3.0-or-later
"""Glance: Drawer's preview of the selected file, opened and closed with Space.

Pictures are shown scaled to fit, text files show their first lines, folders
say how much is in them, and anything else shows its icon and details. The
button at the bottom opens the file in its usual app.
"""
import os
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

TEXT_BYTES = 64 * 1024
WIDTH, HEIGHT = 560, 420


def human_size(size):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            return f"{size} {unit}" if unit == "bytes" else f"{size:.1f} {unit}"
        size /= 1000
    return ""


def content_type(path):
    try:
        info = Gio.File.new_for_path(path).query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
        return info.get_content_type() or ""
    except GLib.Error:
        return Gio.content_type_guess(path, None)[0] or ""


def is_text(kind, path):
    if Gio.content_type_is_a(kind, "text/plain"):
        return True
    try:
        with open(path, "rb") as f:
            head = f.read(4096)
    except OSError:
        return False
    return bool(head) and b"\0" not in head and kind in ("application/octet-stream", "application/x-zerosize", "")


class Glance(Gtk.Window):
    def __init__(self, parent, on_open):
        super().__init__(title="Glance", transient_for=parent, destroy_with_parent=True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_default_size(WIDTH, HEIGHT)
        self.on_open = on_open
        self.path = None
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=14)
        self.add(outer)
        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.pack_start(self.body, True, True, 0)
        footer = Gtk.Box(spacing=8)
        self.details = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
        self.details.get_style_context().add_class("dim-label")
        footer.pack_start(self.details, True, True, 0)
        self.open_button = Gtk.Button(label="Open")
        self.open_button.connect("clicked", lambda *_: self.on_open(self.path))
        footer.pack_end(self.open_button, False, False, 0)
        outer.pack_start(footer, False, False, 0)
        self.connect("key-press-event", self._key)
        self.connect("delete-event", lambda *_: self.hide() or True)

    def _key(self, _w, event):
        if event.keyval in (Gdk.KEY_space, Gdk.KEY_Escape):
            self.hide()
            return True
        return False

    def show_path(self, path):
        self.path = path
        for child in self.body.get_children():
            self.body.remove(child)
        name = os.path.basename(path) or path
        self.set_title(name)
        try:
            st = os.stat(path)
        except OSError:
            st = None
        stamp = time.strftime("%b %-d, %Y %-I:%M %p", time.localtime(st.st_mtime)) if st else ""
        if os.path.isdir(path):
            try:
                count = len([n for n in os.listdir(path) if not n.startswith(".")])
            except OSError:
                count = 0
            self._icon_and_text("folder", name, f"{count} item{'s' if count != 1 else ''}")
            self.details.set_text(f"Folder · Modified {stamp}")
            self.open_button.set_label("Open Folder")
        else:
            kind = content_type(path)
            description = Gio.content_type_get_description(kind) if kind else "File"
            size = human_size(st.st_size) if st else ""
            shown = False
            if kind.startswith("image/"):
                try:
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, WIDTH - 40, HEIGHT - 90, True)
                    image = Gtk.Image.new_from_pixbuf(pixbuf)
                    self.body.pack_start(image, True, True, 0)
                    shown = True
                    _format, width, height = GdkPixbuf.Pixbuf.get_file_info(path)
                    if width:
                        description += f", {width}×{height}"
                except GLib.Error:
                    shown = False
            elif Gio.content_type_is_a(kind or "", "application/pdf"):
                from . import pdf   # Poppler loads only when a PDF is shown
                document = pdf.open_document(path)
                pixbuf = pdf.page_pixbuf(document, 0, HEIGHT - 90)
                if pixbuf is not None:
                    if pixbuf.get_width() > WIDTH - 40:
                        ratio = (WIDTH - 40) / pixbuf.get_width()
                        pixbuf = pixbuf.scale_simple(WIDTH - 40, max(1, round(pixbuf.get_height() * ratio)),
                                                     GdkPixbuf.InterpType.BILINEAR)
                    self.body.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), True, True, 0)
                    shown = True
                    pages = document.get_n_pages()
                    description += f", {pages} page{'s' if pages != 1 else ''}"
            elif is_text(kind, path):
                try:
                    with open(path, "rb") as f:
                        text = f.read(TEXT_BYTES).decode("utf-8", "replace")
                    view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                        wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=8, top_margin=8)
                    view.get_buffer().set_text(text)
                    scroll = Gtk.ScrolledWindow()
                    scroll.add(view)
                    self.body.pack_start(scroll, True, True, 0)
                    shown = True
                except OSError:
                    shown = False
            if not shown:
                icon = Gio.content_type_get_icon(kind) if kind else Gio.ThemedIcon.new("text-x-generic")
                self._icon_and_text(icon, name, description)
            self.details.set_text(" · ".join(p for p in (description if shown else "", size,
                                                         f"Modified {stamp}" if stamp else "") if p))
            app = Gio.AppInfo.get_default_for_type(kind, False) if kind else None
            self.open_button.set_label(f"Open with {app.get_name()}" if app else "Open")
        self.get_child().show_all()
        self.present()

    def _icon_and_text(self, icon, title, subtitle):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        gicon = Gio.ThemedIcon.new(icon) if isinstance(icon, str) else icon
        image = Gtk.Image.new_from_gicon(gicon, Gtk.IconSize.DIALOG)
        image.set_pixel_size(128)
        box.pack_start(image, False, False, 0)
        heading = Gtk.Label(label=title, wrap=True, max_width_chars=40)
        heading.get_style_context().add_class("drawer-preview-name")
        box.pack_start(heading, False, False, 0)
        line = Gtk.Label(label=subtitle)
        line.get_style_context().add_class("dim-label")
        box.pack_start(line, False, False, 0)
        self.body.pack_start(box, True, True, 0)
