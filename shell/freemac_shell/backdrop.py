# SPDX-License-Identifier: GPL-3.0-or-later
"""Backdrop: draws the desktop wallpaper on every screen.

One layer-shell window per monitor on the background layer, drawn under the
menu bar and the dock. The picture fills the screen at any shape by default
(cropping the edges rather than leaving bars). Dials writes the choice to the
[background] section of ~/.config/wf-shell.ini; Backdrop watches that file.

Keys: image = path, fit = fill | fit | stretch, dynamic = true | false, and
Change picture's rotate keys (wallpaper_rotate.py).

Dynamic (Dials > Wallpaper): with one of freemac's own scenes, the picture
follows the sun where you are (sun.py) instead of light and dark mode, as a
Mac's Dynamic Desktop does. The day version is shown while the sun is high,
it warms toward gold as the sun nears the horizon, and it fades into the
night version through twilight. Checked once a minute.

The first screen also shows the Desktop folder's files and the plugged-in
drives (desktop_icons.py). Backdrop runs for the whole session, so it is
also what mounts a USB drive, memory card or phone as it is plugged in.
"""
import os

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

CONFIG = os.path.join(GLib.get_user_config_dir(), "wf-shell.ini")
DEFAULT_IMAGE = "/usr/share/backgrounds/freemac/dusk-tide.png"
FALLBACK = (0.11, 0.12, 0.29)
WALLPAPERS = "/usr/share/backgrounds/freemac"
# freemac's own scenes as (day, night) files; the same list as Dials'.
SCENES = (("dusk-tide.png", "night-tide.png"), ("lagoon-day.png", "lagoon-night.png"),
          ("prism-day.png", "prism-night.png"), ("harbor-day.png", "harbor-night.png"))
DYNAMIC_SECONDS = 60
ROTATE_SECONDS = 60
GOLD = (1.0, 0.58, 0.32)


def scene_pair(path):
    """The (day, night) paths of the built-in scene a picture belongs to, or None."""
    if not path or os.path.dirname(path) != WALLPAPERS:
        return None
    name = os.path.basename(path)
    for day, night in SCENES:
        if name in (day, night):
            return os.path.join(WALLPAPERS, day), os.path.join(WALLPAPERS, night)
    return None


def sky_mix(height):
    """(night, gold) for the sun at `height` degrees: how much of the night
    picture to show (0 by day, 1 at night, eased through twilight, from 6°
    above the horizon to 6° below) and how warm the light is (strongest as
    the sun sits on the horizon)."""
    if height is None:
        return None
    t = min(1.0, max(0.0, (6.0 - height) / 12.0))
    night = t * t * (3 - 2 * t)
    gold = max(0.0, 1.0 - abs(height - 1.0) / 9.0)
    return round(night, 2), round(0.28 * gold * (1 - night * 0.6), 2)


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
            # The Desktop folder's files, over the picture (main display only).
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
        night_picture, mix = self.owner.night_picture, self.owner.mix
        key = (id(picture), id(night_picture), width, height, fit)
        if not self.cache or self.cache[0] != key:
            w, h, x, y = placement(picture.get_width(), picture.get_height(), width, height, fit)
            scaled = picture.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR)
            night = None
            if night_picture is not None:
                nw, nh, nx, ny = placement(night_picture.get_width(), night_picture.get_height(),
                                           width, height, fit)
                night = (night_picture.scale_simple(nw, nh, GdkPixbuf.InterpType.BILINEAR), nx, ny)
            self.cache = (key, scaled, x, y, night)
        _key, scaled, x, y, night = self.cache
        Gdk.cairo_set_source_pixbuf(cr, scaled, x, y)
        cr.paint()
        if mix and night_picture is not None:
            amount, gold = mix
            if gold > 0:
                # The low sun's warm light, over the day picture.
                cr.save()
                cr.set_operator(cairo.OPERATOR_SOFT_LIGHT)   # warms, keeps the contrast
                cr.set_source_rgba(*GOLD, gold)
                cr.paint()
                cr.restore()
            if amount > 0 and night:
                Gdk.cairo_set_source_pixbuf(cr, night[0], night[1], night[2])
                cr.paint_with_alpha(amount)
        return False


class Backdrop:
    def __init__(self):
        self.picture, self.fit, self.path = None, "fill", None
        self.night_picture, self.mix, self.dynamic = None, None, False
        self.windows = []
        self.load()
        display = Gdk.Display.get_default()
        display.connect("monitor-added", lambda *_: self.rebuild())
        display.connect("monitor-removed", lambda *_: self.rebuild())
        self.rebuild()
        # Dials > Displays > Use as: Main display moves the Desktop's files.
        from . import style
        self.main_watch = style.watch_prefs(self._main_changed)
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        # Watch the folder: Dials replaces the file atomically.
        self.monitor = Gio.File.new_for_path(os.path.dirname(CONFIG)).monitor_directory(
            Gio.FileMonitorFlags.WATCH_MOVES, None)
        self.monitor.connect("changed", self._changed)
        self._pending = None
        from . import volumes
        volumes.monitor().connect("volume-added", lambda _m, volume: volumes.mount_volume(volume))
        volumes.mount_new()
        GLib.timeout_add_seconds(DYNAMIC_SECONDS, self._sun_tick)
        # Change picture (Dials > Wallpaper): checked once a minute, and once
        # when the session starts for When logging in.
        GLib.timeout_add_seconds(ROTATE_SECONDS, self._rotate_tick)
        GLib.idle_add(self._rotate_login)

    def _rotate_tick(self):
        from . import style, wallpaper_rotate
        try:
            wallpaper_rotate.tick(CONFIG, style.is_dark())
        except (OSError, ValueError):
            pass
        return True

    def _rotate_login(self):
        """When logging in: once a session, not each time Backdrop restarts."""
        from . import style, wallpaper_rotate
        marker = os.path.join(GLib.get_user_runtime_dir(), "freemac-wallpaper-changed")
        if not os.path.exists(marker):
            try:
                open(marker, "w").close()
                wallpaper_rotate.login(CONFIG, style.is_dark())
            except (OSError, ValueError):
                pass
        return False

    def _sun_tick(self):
        if self.night_picture is not None and self.update_mix():
            for window in self.windows:
                window.queue_draw()
        return True

    def update_mix(self):
        """Work out the Dynamic wallpaper's light now; True if it changed."""
        from . import sun
        # FREEMAC_SUN_HEIGHT (degrees) pins the sun, to see a sunset at noon.
        pinned = os.environ.get("FREEMAC_SUN_HEIGHT")
        try:
            height = float(pinned) if pinned else sun.elevation()
        except ValueError:
            height = sun.elevation()
        mix = sky_mix(height) if self.night_picture is not None else None
        changed, self.mix = mix != self.mix, mix
        return changed

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
        dynamic = settings.get("dynamic", "false").lower() == "true"
        pair = scene_pair(path) if dynamic else None
        if pair:
            # Dynamic: the scene's day picture, with its night one to fade into.
            path = pair[0]
        if (path == self.path and fit == self.fit and self.picture
                and dynamic == self.dynamic and (pair is None) == (self.night_picture is None)):
            return False
        try:
            picture = GdkPixbuf.Pixbuf.new_from_file(path)
        except GLib.Error:
            try:
                picture = GdkPixbuf.Pixbuf.new_from_file(DEFAULT_IMAGE)
            except GLib.Error:
                picture = None
        night = None
        if pair:
            try:
                night = GdkPixbuf.Pixbuf.new_from_file(pair[1])
            except GLib.Error:
                night = None
        self.picture, self.fit, self.path, self.dynamic = picture, fit, path, dynamic
        self.night_picture = night
        self.update_mix()
        return True

    def _main_changed(self):
        from . import main_display
        if main_display.monitor() != self.main:
            self.rebuild()

    def rebuild(self):
        from . import main_display
        for window in self.windows:
            window.destroy()
        display = Gdk.Display.get_default()
        # The Desktop's files go on the main display, as on a Mac.
        self.main = main_display.monitor(display)
        self.windows = [BackdropWindow(self, display.get_monitor(i), with_icons=(display.get_monitor(i) == self.main))
                        for i in range(display.get_n_monitors())]


def main():
    Backdrop()
    Gtk.main()


if __name__ == "__main__":
    main()
