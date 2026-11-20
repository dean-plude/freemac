# SPDX-License-Identifier: GPL-3.0-or-later
"""The little picture of a new screenshot that sits in the screen's corner.

Right after a screenshot, a small copy of it slides in at the bottom right
for a few seconds. Clicking it opens the picture; dragging it drops the file
into another app or folder; it goes by itself after a few seconds, leaving
the file on the Desktop. Original freemac code.
"""
import os
import subprocess

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

SHOW_SECONDS = 5
WIDTH = 220
MARGIN = 22
CSS = b"""
.lens-thumb { background: transparent; }
.lens-thumb-frame {
  background-color: white; border-radius: 8px; padding: 4px;
  border: 1px solid rgba(0, 0, 0, 0.18);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.35);
}
"""


def thumb_size(width, height, most=WIDTH):
    """Fit a picture into most x most, keeping its shape."""
    if width <= 0 or height <= 0:
        return most, most
    scale = most / max(width, height)
    return max(1, round(width * scale)), max(1, round(height * scale))


class Thumb(Gtk.Window):
    def __init__(self, path, on_done):
        super().__init__(title="Screenshot")
        self.path, self.on_done, self.left = path, on_done, False
        style = Gtk.CssProvider()
        style.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), style,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.get_style_context().add_class("lens-thumb")
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-lens-thumb")
        for edge in (GtkLayerShell.Edge.BOTTOM, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
            GtkLayerShell.set_margin(self, edge, MARGIN - 14)
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)
        self.set_app_paintable(True)
        picture = GdkPixbuf.Pixbuf.new_from_file(path)
        width, height = thumb_size(picture.get_width(), picture.get_height())
        image = Gtk.Image.new_from_pixbuf(picture.scale_simple(width, height, GdkPixbuf.InterpType.BILINEAR))
        # The white border and the shadow are drawn by a box (an EventBox
        # draws nothing); the outer margin leaves room for the shadow.
        border = Gtk.Box(margin=14)
        border.get_style_context().add_class("lens-thumb-frame")
        border.add(image)
        frame = Gtk.EventBox()
        frame.set_visible_window(False)
        frame.add(border)
        frame.set_tooltip_text("Click to open; drag it into a folder or an app")
        frame.connect("button-release-event", self.open)
        frame.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [], Gdk.DragAction.COPY)
        frame.drag_source_add_uri_targets()
        frame.drag_source_set_icon_pixbuf(picture.scale_simple(max(1, width // 2), max(1, height // 2),
                                                               GdkPixbuf.InterpType.BILINEAR))
        frame.connect("drag-data-get", self.drag_data)
        frame.connect("drag-begin", lambda *_a: setattr(self, "left", True))
        frame.connect("drag-end", lambda *_a: self.finish())
        self.add(frame)
        GLib.timeout_add_seconds(SHOW_SECONDS, self.timed_out)

    def drag_data(self, _widget, _context, data, _info, _time):
        data.set_uris([GLib.filename_to_uri(self.path, None)])

    def open(self, _widget, event):
        if self.left or event.button != 1:
            return False
        try:
            Gio.AppInfo.launch_default_for_uri(GLib.filename_to_uri(self.path, None), None)
        except GLib.Error:
            subprocess.Popen(["xdg-open", self.path], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.finish()
        return True

    def timed_out(self):
        if not self.left:
            self.finish()
        return False

    def finish(self):
        self.hide()
        self.on_done()


def show(path):
    """Show the thumbnail and wait until it goes; False if it couldn't show
    (no screen, or the picture can't be read)."""
    if not path or not os.path.exists(path) or not Gtk.init_check()[0]:
        return False
    try:
        if not GtkLayerShell.is_supported():
            return False
        loop = GLib.MainLoop()
        thumb = Thumb(path, loop.quit)
    except GLib.Error:
        return False
    thumb.show_all()
    loop.run()
    return True
