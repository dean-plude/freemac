# SPDX-License-Identifier: GPL-3.0-or-later
"""Frame: freemac's image viewer.

Opens a picture and lets you step through the others in the same folder.
Keys: Left/Right previous/next, + / - zoom, 0 or F fit, 1 actual size,
R rotate right, Shift+R rotate left, Delete move to Trash, F11 full screen.
"""
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import style  # noqa: E402

APP_ID = "org.freemac.Frame"


def readable_types():
    exts = set()
    for fmt in GdkPixbuf.Pixbuf.get_formats():
        exts.update(e.lower() for e in fmt.get_extensions())
    return exts


def siblings(path, exts=None):
    """Pictures in the same folder as path, in name order."""
    exts = exts or readable_types()
    folder = os.path.dirname(path) or "."
    try:
        names = sorted(os.listdir(folder), key=str.lower)
    except OSError:
        return [path]
    found = [os.path.join(folder, n) for n in names
             if not n.startswith(".") and os.path.splitext(n)[1][1:].lower() in exts]
    return found or [path]


class Viewer(Gtk.ApplicationWindow):
    def __init__(self, app, path=None):
        super().__init__(application=app, title="Frame")
        self.set_default_size(960, 680)
        self.files, self.index = [], 0
        self.original = None   # the picture as loaded (after rotation)
        self.animation = None
        self.zoom = None        # None means "fit to window"
        self.fullscreen_on = False

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        self.header = header
        nav = Gtk.Box()
        nav.get_style_context().add_class("linked")
        for icon, tip, step in (("go-previous-symbolic", "Previous", -1), ("go-next-symbolic", "Next", 1)):
            button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
            button.set_tooltip_text(tip)
            button.connect("clicked", lambda _b, s=step: self.step(s))
            nav.pack_start(button, False, False, 0)
        header.pack_start(nav)
        for icon, tip, callback in (("object-rotate-right-symbolic", "Rotate", lambda: self.rotate(-90)),
                                    ("zoom-fit-best-symbolic", "Fit to Window", lambda: self.set_zoom(None)),
                                    ("zoom-in-symbolic", "Zoom In", lambda: self.zoom_by(1.25)),
                                    ("zoom-out-symbolic", "Zoom Out", lambda: self.zoom_by(0.8))):
            button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
            button.set_tooltip_text(tip)
            button.connect("clicked", lambda _b, c=callback: c())
            header.pack_end(button)
        opener = Gtk.Button(label="Open")
        opener.connect("clicked", lambda *_: self.open_dialog())
        header.pack_start(opener)

        self.scroller = Gtk.ScrolledWindow()
        self.scroller.connect("size-allocate", lambda *_: self._refit())
        self.image = Gtk.Image()
        self.scroller.add(self.image)
        self.empty = Gtk.Label(label="Open a picture, or drop one here.")
        self.empty.get_style_context().add_class("dim-label")
        self.stack = Gtk.Stack()
        self.stack.add_named(self.empty, "empty")
        self.stack.add_named(self.scroller, "image")
        self.add(self.stack)
        # A stack only switches to children that are already shown.
        self.stack.show_all()
        self._last_size = None

        self.drag_dest_set(Gtk.DestDefaults.ALL, [], Gdk.DragAction.COPY)
        self.drag_dest_add_uri_targets()
        self.connect("drag-data-received", self._dropped)
        self.connect("key-press-event", self._on_key)
        self.connect("scroll-event", self._on_scroll)
        self.add_events(Gdk.EventMask.SCROLL_MASK)
        if path:
            self.open_path(path)

    # --- files -----------------------------------------------------------
    def open_path(self, path):
        path = os.path.abspath(path)
        self.files = siblings(path)
        self.index = self.files.index(path) if path in self.files else 0
        if path not in self.files:
            self.files.insert(0, path)
        self.show_current()

    def show_current(self):
        if not self.files:
            self.stack.set_visible_child_name("empty")
            self.header.set_title("Frame")
            self.header.set_subtitle(None)
            return
        path = self.files[self.index]
        self.animation = None
        try:
            if path.lower().endswith(".gif"):
                anim = GdkPixbuf.PixbufAnimation.new_from_file(path)
                if not anim.is_static_image():
                    self.animation = anim
                pixbuf = anim.get_static_image()
            else:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
                pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
        except GLib.Error:
            self.original = None
            self.image.clear()
            self.empty.set_text(f"“{os.path.basename(path)}” can’t be shown.")
            self.stack.set_visible_child_name("empty")
            self.header.set_title(os.path.basename(path))
            return
        self.original = pixbuf
        self.zoom = None
        self.stack.set_visible_child_name("image")
        self.header.set_title(os.path.basename(path))
        self.header.set_subtitle(f"{pixbuf.get_width()} × {pixbuf.get_height()}   "
                                 f"{self.index + 1} of {len(self.files)}")
        self._last_size = None
        self._render()

    def step(self, delta):
        if len(self.files) > 1:
            self.index = (self.index + delta) % len(self.files)
            self.show_current()

    def open_dialog(self):
        dialog = Gtk.FileChooserNative.new("Open Picture", self, Gtk.FileChooserAction.OPEN, "Open", "Cancel")
        pictures = Gtk.FileFilter()
        pictures.set_name("Pictures")
        pictures.add_pixbuf_formats()
        dialog.add_filter(pictures)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            self.open_path(dialog.get_filename())

    def trash(self):
        if not self.files:
            return
        path = self.files[self.index]
        try:
            Gio.File.new_for_path(path).trash(None)
        except GLib.Error:
            return
        del self.files[self.index]
        self.index = min(self.index, len(self.files) - 1)
        self.show_current()

    def _dropped(self, _widget, _context, _x, _y, data, _info, _time):
        uris = data.get_uris()
        if uris:
            path = Gio.File.new_for_uri(uris[0]).get_path()
            if path:
                self.open_path(path)

    # --- zoom and rotate ---------------------------------------------------
    def fit_scale(self):
        alloc = self.scroller.get_allocation()
        if not self.original or alloc.width < 2:
            return 1.0
        return min(1.0, alloc.width / self.original.get_width(), alloc.height / self.original.get_height())

    def set_zoom(self, value):
        self.zoom = value
        self._render()

    def zoom_by(self, factor):
        current = self.zoom or self.fit_scale()
        self.set_zoom(max(0.05, min(16.0, current * factor)))

    def rotate(self, degrees):
        if not self.original:
            return
        angle = GdkPixbuf.PixbufRotation.CLOCKWISE if degrees < 0 else GdkPixbuf.PixbufRotation.COUNTERCLOCKWISE
        self.original = self.original.rotate_simple(angle)
        self.animation = None
        self._render()

    def _refit(self):
        alloc = self.scroller.get_allocation()
        size = (alloc.width, alloc.height)
        if self.zoom is None and size != self._last_size:
            self._last_size = size
            GLib.idle_add(self._render)

    def _render(self):
        if not self.original:
            return False
        if self.animation and self.zoom is None and self.fit_scale() >= 1.0:
            self.image.set_from_animation(self.animation)
            return False
        scale = self.zoom or self.fit_scale()
        w = max(1, round(self.original.get_width() * scale))
        h = max(1, round(self.original.get_height() * scale))
        interp = GdkPixbuf.InterpType.BILINEAR if scale < 1 else GdkPixbuf.InterpType.NEAREST \
            if scale >= 3 else GdkPixbuf.InterpType.BILINEAR
        self.image.set_from_pixbuf(self.original.scale_simple(w, h, interp))
        return False

    # --- input -----------------------------------------------------------
    def _on_key(self, _widget, event):
        key = event.keyval
        shift = event.state & Gdk.ModifierType.SHIFT_MASK
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        if ctrl and key in (Gdk.KEY_o, Gdk.KEY_O):
            self.open_dialog()
        elif ctrl and key in (Gdk.KEY_w, Gdk.KEY_W):
            self.close()
        elif key in (Gdk.KEY_Right, Gdk.KEY_Page_Down, Gdk.KEY_space):
            self.step(1)
        elif key in (Gdk.KEY_Left, Gdk.KEY_Page_Up, Gdk.KEY_BackSpace):
            self.step(-1)
        elif key in (Gdk.KEY_plus, Gdk.KEY_equal, Gdk.KEY_KP_Add):
            self.zoom_by(1.25)
        elif key in (Gdk.KEY_minus, Gdk.KEY_KP_Subtract):
            self.zoom_by(0.8)
        elif key in (Gdk.KEY_0, Gdk.KEY_f, Gdk.KEY_F):
            self.set_zoom(None)
        elif key == Gdk.KEY_1:
            self.set_zoom(1.0)
        elif key in (Gdk.KEY_r, Gdk.KEY_R):
            self.rotate(90 if shift else -90)
        elif key == Gdk.KEY_Delete:
            self.trash()
        elif key == Gdk.KEY_F11 or (key == Gdk.KEY_Escape and self.fullscreen_on):
            self.fullscreen_on = not self.fullscreen_on
            (self.fullscreen if self.fullscreen_on else self.unfullscreen)()
        else:
            return False
        return True

    def _on_scroll(self, _widget, event):
        if event.state & Gdk.ModifierType.CONTROL_MASK:
            ok, _dx, dy = event.get_scroll_deltas()
            up = event.direction == Gdk.ScrollDirection.UP or (ok and dy < 0)
            self.zoom_by(1.1 if up else 1 / 1.1)
            return True
        return False


class Frame(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()

    def do_activate(self):
        Viewer(self).show_all()

    def do_open(self, files, _n, _hint):
        for f in files:
            if f.get_path():
                Viewer(self, f.get_path()).show_all()


def main():
    Frame().run(sys.argv)


if __name__ == "__main__":
    main()
