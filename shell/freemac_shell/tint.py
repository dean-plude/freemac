# SPDX-License-Identifier: GPL-3.0-or-later
"""Tint: point at anything on the screen and see its colour, as a Mac's
colour meter does.

The window shows the pixels around the pointer, enlarged, with a square
marking the aperture: the pixels whose colour is averaged. Beside it are the
colour and its red, green and blue values, shown as numbers from 0 to 255,
as percentages or as hex (View menu). Color > Hold Color freezes the values
so you can move the pointer away; Lock Position keeps reading the same spot
while the screen changes under it. Copy Color as Text puts the values on the
clipboard, and Copy Color as Image a small swatch of the colour.

Strata says where the pointer is on the screen (strata/pointer), and grim
takes a picture of the small square of screen around it, a few times a
second, without the pointer in it. Nothing is saved. Original freemac code.
"""
import json
import os
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import menus, style  # noqa: E402
from .wfipc import Connection  # noqa: E402

APP_ID = "org.freemac.Tint"
SPAN = 15            # screen pixels across the enlarged view (odd: one centre)
VIEW = 165           # the enlarged view's size on screen, SPAN * 11
EVERY = 150          # ms between looks at the screen
APERTURES = (1, 3, 5, 7, 9, 11)
FORMATS = (("decimal", "As Decimal (0–255)"), ("percent", "As Percentage"), ("hex", "As Hex"))
SETTINGS = "tint.json"
HIDE_WAIT = 0.4      # s: the longest to wait for the screen to be drawn without the arrow
FRAME = 0.017

CSS = b"""
.tint-swatch { border-radius: 8px; border: 1px solid alpha(black, 0.15); }
.tint-name { font-weight: bold; min-width: 18px; }
.tint-value { font-family: monospace; font-size: 15px; }
.tint-where { color: alpha(currentColor, 0.6); font-size: 12px; }
"""


def average(pixels, channels, stride, left, top, size):
    """The mean (r, g, b), 0–255, of a size × size square of a pixbuf's
    pixel bytes starting at left, top."""
    totals, count = [0, 0, 0], 0
    for y in range(top, top + size):
        for x in range(left, left + size):
            at = y * stride + x * channels
            for i in range(3):
                totals[i] += pixels[at + i]
            count += 1
    return tuple(round(t / count) for t in totals) if count else (0, 0, 0)


def shown(value, how):
    """One channel (0–255) as the View menu asks."""
    if how == "percent":
        return f"{value / 255 * 100:.1f} %"
    if how == "hex":
        return f"{value:02X}"
    return str(value)


def as_text(rgb, how):
    """The colour as Copy Color as Text writes it."""
    if how == "hex":
        return "#%02X%02X%02X" % rgb
    if how == "percent":
        return "  ".join(f"{v / 255 * 100:.1f}%" for v in rgb)
    return "  ".join(str(v) for v in rgb)


def pointer():
    """(x, y, software) for the pointer on the screen, from Strata, or None.
    software: the display draws the arrow into its picture, so a grab there
    shows it (an older Strata doesn't say, and is taken as not)."""
    try:
        connection = Connection()
    except OSError:
        return None
    try:
        reply = connection.call("strata/pointer")
    except (OSError, ValueError, ConnectionError):
        return None
    finally:
        connection.sock.close()
    if not isinstance(reply, dict) or "x" not in reply:
        return None
    return int(reply["x"]), int(reply["y"]), bool(reply.get("software"))


def grab_hidden(x, y):
    """grab(), with the pointer hidden for that moment, as Hover Text does:
    Strata hides it and says once every display has been drawn without it."""
    try:
        connection = Connection()
    except OSError:
        return grab(x, y)
    try:
        connection.call("strata/hover-cursor", hide=True, **{"for": "meter"})
        waited = 0.0
        while waited < HIDE_WAIT:
            answer = connection.call("strata/hover-cursor", query=True)
            if answer.get("drawn", True):
                time.sleep(FRAME)   # that frame on its way to the screen
                break
            time.sleep(FRAME)
            waited += FRAME
        return grab(x, y)
    except (OSError, ValueError, ConnectionError):
        return grab(x, y)
    finally:
        try:
            connection.call("strata/hover-cursor", hide=False)
        except (OSError, ValueError, ConnectionError):
            pass
        connection.sock.close()


def grab(x, y):
    """A pixbuf of the SPAN × SPAN square of screen around (x, y) and the
    pointer's place in it, or (None, None)."""
    half = SPAN // 2
    left, top = max(0, x - half), max(0, y - half)
    try:
        done = subprocess.run(["grim", "-g", f"{left},{top} {SPAN}x{SPAN}", "-t", "ppm", "-"],
                              capture_output=True, timeout=5, check=True)
        loader = GdkPixbuf.PixbufLoader.new_with_type("pnm")
        loader.write(done.stdout)
        loader.close()
        picture = loader.get_pixbuf()
    except (OSError, subprocess.SubprocessError, GLib.Error):
        return None, None
    if picture is None:
        return None, None
    # On a HiDPI screen the picture has more pixels than the square asked for.
    display = Gdk.Display.get_default()
    monitor = display.get_monitor_at_point(x, y) if display else None
    scale = monitor.get_scale_factor() if monitor else 1
    if scale > 1:
        picture = picture.scale_simple(max(1, picture.get_width() // scale),
                                       max(1, picture.get_height() // scale),
                                       GdkPixbuf.InterpType.NEAREST)
    return picture, (x - left, y - top)


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Tint", resizable=False)
        self.set_wmclass("freemac-tint", "Tint")
        settings = app.settings
        self.how = settings.get("format") if settings.get("format") in dict(FORMATS) else "decimal"
        self.aperture = settings.get("aperture") if settings.get("aperture") in APERTURES else 1
        self.picture, self.centre, self.rgb, self.at = None, None, None, None
        self.held, self.locked, self.busy = False, None, False
        # Where the pointer was at the last look, and the spot last read
        # with the arrow out of the way (on a display that draws it).
        self.last_pointer, self.clean_at, self.picture_clean = None, None, False

        outer = Gtk.Box(spacing=18, margin=16)
        self.add(outer)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.view = Gtk.DrawingArea()
        self.view.set_size_request(VIEW, VIEW)
        self.view.connect("draw", self._draw_view)
        frame = Gtk.Frame(shadow_type=Gtk.ShadowType.IN)
        frame.add(self.view)
        left.pack_start(frame, False, False, 0)
        size_row = Gtk.Box(spacing=6)
        size_row.pack_start(Gtk.Label(label="Aperture size:"), False, False, 0)
        self.size = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, len(APERTURES) - 1, 1)
        self.size.set_draw_value(False)
        self.size.set_value(APERTURES.index(self.aperture))
        self.size.connect("value-changed", self._size_changed)
        size_row.pack_start(self.size, True, True, 0)
        left.pack_start(size_row, False, False, 0)
        outer.pack_start(left, False, False, 0)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.formats = Gtk.ComboBoxText()
        for key, title in FORMATS:
            self.formats.append(key, title)
        self.formats.set_active_id(self.how)
        self.formats.connect("changed", lambda c: self.set_format(c.get_active_id()))
        right.pack_start(self.formats, False, False, 0)
        row = Gtk.Box(spacing=14)
        self.swatch = Gtk.DrawingArea()
        self.swatch.set_size_request(64, 64)
        self.swatch.get_style_context().add_class("tint-swatch")
        self.swatch.connect("draw", self._draw_swatch)
        row.pack_start(self.swatch, False, False, 0)
        grid = Gtk.Grid(column_spacing=10, row_spacing=4, valign=Gtk.Align.CENTER)
        self.values = []
        for n, name in enumerate(("R:", "G:", "B:")):
            label = Gtk.Label(label=name, xalign=0)
            label.get_style_context().add_class("tint-name")
            value = Gtk.Label(label="–", xalign=1, width_chars=8, selectable=True)
            value.get_style_context().add_class("tint-value")
            grid.attach(label, 0, n, 1, 1)
            grid.attach(value, 1, n, 1, 1)
            self.values.append(value)
        row.pack_start(grid, False, False, 0)
        right.pack_start(row, False, False, 0)
        self.where = Gtk.Label(xalign=0)
        self.where.get_style_context().add_class("tint-where")
        right.pack_start(self.where, False, False, 0)
        self.state = Gtk.Label(xalign=0)
        self.state.get_style_context().add_class("tint-where")
        right.pack_start(self.state, False, False, 0)
        outer.pack_start(right, True, True, 0)

        for name, handler in (("copy-text", self.copy_text), ("copy-image", self.copy_image),
                              ("close", self.close)):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda *_a, h=handler: h())
            self.add_action(action)
        # Hold Color and Lock Position show a tick in the Color menu while on.
        self.toggles = {}
        for name, handler in (("hold", self.toggle_hold), ("lock", self.toggle_lock)):
            action = Gio.SimpleAction.new_stateful(name, None, GLib.Variant("b", False))
            action.connect("change-state", lambda _a, _v, h=handler: h())
            self.add_action(action)
            self.toggles[name] = action
        self.format_action = Gio.SimpleAction.new_stateful("format", GLib.VariantType.new("s"),
                                                           GLib.Variant("s", self.how))
        self.format_action.connect("activate", lambda _a, v: self.set_format(v.get_string()))
        self.add_action(self.format_action)
        self._show_state()
        self.timer = GLib.timeout_add(EVERY, self._tick)
        self.connect("destroy", lambda *_: GLib.source_remove(self.timer))
        self.show_all()

    # ---- reading the screen -------------------------------------------------
    def _tick(self):
        if not self.busy and not self.held:
            self.busy = True
            threading.Thread(target=self._look, daemon=True).start()
        return True

    def _look(self):
        now = pointer()
        if now is None:
            GLib.idle_add(self._seen, None, None, None, False)
            return
        x, y, software = now
        at = self.locked or (x, y)
        resting = (x, y) == self.last_pointer
        self.last_pointer = (x, y)
        # Where the display draws the arrow into its picture and the arrow
        # is over the spot, the arrow is in the grab. Once the pointer rests,
        # the spot is read once more with the arrow hidden for a moment.
        covered = software and abs(x - at[0]) <= SPAN and abs(y - at[1]) <= SPAN
        if covered and resting and self.clean_at != at:
            picture, centre = grab_hidden(*at)
            clean = True
        else:
            picture, centre = grab(*at)
            clean = not covered
        GLib.idle_add(self._seen, at, picture, centre, clean)

    def _seen(self, at, picture, centre, clean):
        self.busy = False
        if self.held or picture is None:
            return False
        if not clean and self.clean_at == at:
            return False   # resting: keep the reading without the arrow
        self.at, self.picture, self.centre = at, picture, centre
        self.clean_at = at if clean else None
        self.picture_clean = clean
        if clean or self.rgb is None:
            # A grab with the arrow in it still shows in the enlarged view,
            # but the values wait for one without it.
            self.rgb = self._measure()
            self.swatch.queue_draw()
        self._show_values()
        self.view.queue_draw()
        return False

    def _measure(self):
        """The average colour of the aperture around the pointer."""
        picture, (cx, cy) = self.picture, self.centre
        half = self.aperture // 2
        left = max(0, min(cx - half, picture.get_width() - self.aperture))
        top = max(0, min(cy - half, picture.get_height() - self.aperture))
        size = min(self.aperture, picture.get_width(), picture.get_height())
        return average(picture.get_pixels(), picture.get_n_channels(), picture.get_rowstride(),
                       left, top, size)

    # ---- showing it ------------------------------------------------------------
    def _show_values(self):
        for label, value in zip(self.values, self.rgb or ()):
            label.set_text(shown(value, self.how))
        if self.at:
            self.where.set_text(f"Location: {self.at[0]}, {self.at[1]}")

    def _show_state(self):
        if hasattr(self, "toggles"):
            self.toggles["hold"].set_state(GLib.Variant("b", self.held))
            self.toggles["lock"].set_state(GLib.Variant("b", bool(self.locked)))
        words = []
        if self.held:
            words.append("Color held")
        if self.locked:
            words.append("Position locked")
        self.state.set_text(" · ".join(words))

    def _draw_view(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        cr.set_source_rgb(0.5, 0.5, 0.5)
        cr.paint()
        if self.picture is None:
            return
        cell = width / SPAN
        cx, cy = self.centre
        # The pointer's pixel sits in the middle cell, even at a screen edge.
        offset_x, offset_y = SPAN // 2 - cx, SPAN // 2 - cy
        big = self.picture.scale_simple(int(self.picture.get_width() * cell),
                                        int(self.picture.get_height() * cell),
                                        GdkPixbuf.InterpType.NEAREST)
        Gdk.cairo_set_source_pixbuf(cr, big, offset_x * cell, offset_y * cell)
        cr.paint()
        # The aperture: a square round the pixels being averaged.
        side = self.aperture * cell
        start = (width - side) / 2
        for colour, inset in (((0, 0, 0), 0.5), ((1, 1, 1), 1.5)):
            cr.set_source_rgb(*colour)
            cr.set_line_width(1)
            cr.rectangle(start + inset - 1, (height - side) / 2 + inset - 1, side - 2 * inset + 2,
                         side - 2 * inset + 2)
            cr.stroke()

    def _draw_swatch(self, widget, cr):
        if self.rgb is None:
            return
        cr.set_source_rgb(*(v / 255 for v in self.rgb))
        cr.rectangle(0, 0, widget.get_allocated_width(), widget.get_allocated_height())
        cr.fill()

    # ---- the controls -----------------------------------------------------------
    def set_format(self, how):
        if how not in dict(FORMATS) or how == self.how:
            return
        self.how = how
        self.format_action.set_state(GLib.Variant("s", how))
        self.formats.set_active_id(how)
        self.get_application().save("format", how)
        if self.rgb:
            self._show_values()

    def _size_changed(self, scale):
        self.aperture = APERTURES[int(round(scale.get_value()))]
        self.get_application().save("aperture", self.aperture)
        if self.picture is not None and self.picture_clean and not self.held:
            self.rgb = self._measure()
            self._show_values()
            self.swatch.queue_draw()
        self.view.queue_draw()

    def toggle_hold(self):
        self.held = not self.held
        self._show_state()

    def toggle_lock(self):
        now = pointer()
        self.locked = None if self.locked else (self.at or (now[:2] if now else None))
        self.clean_at = None
        self._show_state()

    def copy_text(self):
        if self.rgb:
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(as_text(self.rgb, self.how), -1)

    def copy_image(self):
        if self.rgb:
            swatch = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 64, 64)
            swatch.fill((self.rgb[0] << 24) | (self.rgb[1] << 16) | (self.rgb[2] << 8) | 0xFF)
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_image(swatch)


def menubar():
    formats = [[(title, f"win.format::{key}", None) for key, title in FORMATS]]
    return menus.menubar([
        ("_File", [[("Close", "win.close", "<Ctrl>w")]]),
        ("_View", formats),
        ("_Color", [[("Hold Color", "win.hold", "<Ctrl><Shift>h"),
                     ("Lock Position", "win.lock", "<Ctrl>l")],
                    [("Copy Color as Text", "win.copy-text", "<Ctrl><Shift>c"),
                     ("Copy Color as Image", "win.copy-image", "<Ctrl><Alt>c")]]),
    ])


class Tint(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.settings = {}

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.settings = self._load()
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: GLib.idle_add(self.quit))
        self.add_action(quit_action)
        self.set_menubar(menubar())

    def _path(self):
        return os.path.join(GLib.get_user_config_dir(), "freemac", SETTINGS)

    def _load(self):
        try:
            with open(self._path(), encoding="utf-8") as handle:
                saved = json.load(handle)
            return saved if isinstance(saved, dict) else {}
        except (OSError, ValueError):
            return {}

    def save(self, key, value):
        self.settings[key] = value
        try:
            os.makedirs(os.path.dirname(self._path()), exist_ok=True)
            with open(self._path(), "w", encoding="utf-8") as handle:
                json.dump(self.settings, handle, indent=2)
        except OSError:
            pass

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


def main():
    GLib.set_prgname("freemac-tint")
    return Tint().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
