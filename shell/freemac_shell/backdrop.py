# SPDX-License-Identifier: GPL-3.0-or-later
"""Backdrop: draws the desktop wallpaper on every screen.

One layer-shell window per monitor on the background layer, drawn under the
menu bar and the dock. The picture fills the screen at any shape by default
(cropping the edges rather than leaving bars). Dials writes the choice to the
[background] section of ~/.config/wf-shell.ini; Backdrop watches that file.

Keys: image = path, fit = fill | fit | stretch.

The first screen also shows the Desktop folder's files (desktop_icons.py).
"""
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

CONFIG = os.path.join(GLib.get_user_config_dir(), "wf-shell.ini")
DEFAULT_IMAGE = "/usr/share/backgrounds/freemac/dusk-tide.png"
FALLBACK = (0.11, 0.12, 0.29)


def read_settings(path=CONFIG):
    """The [background] section as a dict, with # unescaped."""
    values, section = {}, None
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1]
                elif section == "background" and "=" in line and not line.startswith("#"):
                    key, value = line.split("=", 1)
                    values[key.strip()] = value.strip().replace("\\#", "#")
    except OSError:
        pass
    return values


def placement(img_w, img_h, area_w, area_h, fit):
    """Size and offset of the picture inside the area for a fit mode."""
    if fit == "stretch":
        return area_w, area_h, 0, 0
    pick = min if fit == "fit" else max
    scale = pick(area_w / img_w, area_h / img_h)
    w, h = max(1, round(img_w * scale)), max(1, round(img_h * scale))
    return w, h, (area_w - w) // 2, (area_h - h) // 2


class BackdropWindow(Gtk.Window):
    def __init__(self, owner, monitor, with_icons=False):
        super().__init__(title="Backdrop")
        self.owner = owner
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.BACKGROUND)
        GtkLayerShell.set_namespace(self, "freemac-backdrop")
        GtkLayerShell.set_monitor(self, monitor)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)
        self.cache = None
        self.area = Gtk.DrawingArea()
        self.area.connect("draw", self.draw)
        self.icons = None
        if with_icons:
            # The Desktop folder's files, over the picture (first screen only).
            from .desktop_icons import DesktopIcons
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
            overlay = Gtk.Overlay()
            overlay.add(self.area)
            self.icons = DesktopIcons(monitor)
            overlay.add_overlay(self.icons)
            self.add(overlay)
        else:
            self.add(self.area)
        self.show_all()

    def draw(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        cr.set_source_rgb(*FALLBACK)
        cr.paint()
        picture, fit = self.owner.picture, self.owner.fit
        if not picture or width < 2 or height < 2:
            return False
        key = (id(picture), width, height, fit)
        if not self.cache or self.cache[0] != key:
            w, h, x, y = placement(picture.get_width(), picture.get_height(), width, height, fit)
            self.cache = (key, picture.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR), x, y)
        _key, scaled, x, y = self.cache
        Gdk.cairo_set_source_pixbuf(cr, scaled, x, y)
        cr.paint()
        return False


class Backdrop:
    def __init__(self):
        self.picture, self.fit, self.path = None, "fill", None
        self.windows = []
        self.load()
        display = Gdk.Display.get_default()
        display.connect("monitor-added", lambda *_: self.rebuild())
        display.connect("monitor-removed", lambda *_: self.rebuild())
        self.rebuild()
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        # Watch the folder: Dials replaces the file atomically.
        self.monitor = Gio.File.new_for_path(os.path.dirname(CONFIG)).monitor_directory(
            Gio.FileMonitorFlags.WATCH_MOVES, None)
        self.monitor.connect("changed", self._changed)
        self._pending = None

    def _changed(self, _monitor, file, other, _event):
        names = {f.get_basename() for f in (file, other) if f}
        if os.path.basename(CONFIG) in names and not self._pending:
            self._pending = GLib.timeout_add(200, self._reload)

    def _reload(self):
        self._pending = None
        if self.load():
            for window in self.windows:
                window.queue_draw()
        return False

    def load(self):
        settings = read_settings()
        path = os.path.expanduser(settings.get("image") or DEFAULT_IMAGE)
        fit = settings.get("fit", "fill")
        fit = fit if fit in ("fill", "fit", "stretch") else "fill"
        if path == self.path and fit == self.fit and self.picture:
            return False
        try:
            picture = GdkPixbuf.Pixbuf.new_from_file(path)
        except GLib.Error:
            try:
                picture = GdkPixbuf.Pixbuf.new_from_file(DEFAULT_IMAGE)
            except GLib.Error:
                picture = None
        self.picture, self.fit, self.path = picture, fit, path
        return True

    def rebuild(self):
        for window in self.windows:
            window.destroy()
        display = Gdk.Display.get_default()
        self.windows = [BackdropWindow(self, display.get_monitor(i), with_icons=(i == 0))
                        for i in range(display.get_n_monitors())]


def main():
    Backdrop()
    Gtk.main()


if __name__ == "__main__":
    main()
