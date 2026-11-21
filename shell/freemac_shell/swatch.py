# SPDX-License-Identifier: GPL-3.0-or-later
"""Swatch: a colour picker.

Pick a colour from anywhere on the screen (a magnifying loupe shows the
pixels under the pointer), or choose one by hand, and see it as hex, RGB and
HSL, each ready to copy. Colours you like are kept in a palette along the
bottom; they are saved in ~/.local/share/freemac/swatch.json.

Picking takes a screenshot with grim and shows it on a full-screen overlay,
so nothing needs special permission. Original freemac code.
"""
import colorsys
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Swatch"
SAVE = os.path.join(GLib.get_user_data_dir(), "freemac", "swatch.json")
LIMIT = 48
LOUPE = 15            # pixels across shown in the loupe
CELL = 9              # size each pixel is drawn at in the loupe
STARTERS = ["#2f7bf5", "#34c759", "#ff9f0a", "#ff3b30", "#af52de", "#1d1d1f"]


# Colour arithmetic -------------------------------------------------------------

def parse(text):
    """'#3a7', '3a77ff', 'rgb(1, 2, 3)' or '1 2 3' -> (r, g, b) in 0..255, or None."""
    text = text.strip().lower()
    if text.startswith("rgb"):
        text = text[text.find("(") + 1:].rstrip(")")
    parts = [p for p in text.replace(",", " ").split() if p]
    if len(parts) == 3 and all(p.isdigit() for p in parts):
        values = [int(p) for p in parts]
        return tuple(values) if all(0 <= v <= 255 for v in values) else None
    text = text.lstrip("#")
    if len(text) == 3:
        text = "".join(c * 2 for c in text)
    if len(text) == 6:
        try:
            return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))
        except ValueError:
            return None
    return None


def hex_text(rgb):
    return "#{:02X}{:02X}{:02X}".format(*rgb)


def rgb_text(rgb):
    return "rgb({}, {}, {})".format(*rgb)


def hsl_text(rgb):
    h, lightness, s = colorsys.rgb_to_hls(*(v / 255 for v in rgb))
    return f"hsl({round(h * 360) % 360}, {round(s * 100)}%, {round(lightness * 100)}%)"


def luminance(rgb):
    def channel(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def name_for(rgb):
    """A plain-words name: 'dark blue', 'light grey', 'orange'."""
    h, lightness, s = colorsys.rgb_to_hls(*(v / 255 for v in rgb))
    if lightness > 0.95:
        return "white"
    if lightness < 0.06:
        return "black"
    if s < 0.12:
        return "dark grey" if lightness < 0.35 else "light grey" if lightness > 0.7 else "grey"
    hue = h * 360
    names = [(15, "red"), (40, "orange"), (65, "yellow"), (160, "green"), (195, "teal"), (250, "blue"),
             (290, "purple"), (335, "pink"), (361, "red")]
    base = next(n for limit, n in names if hue < limit)
    if base == "orange" and lightness < 0.35:
        base = "brown"
    if base == "red" and lightness > 0.7:
        return "pink"
    if base == "brown":
        return base
    if lightness < 0.3:
        return "dark " + base
    if lightness > 0.75:
        return "light " + base
    return base


def load():
    try:
        with open(SAVE) as f:
            data = json.load(f)
        colours = [hex_text(c) for c in (parse(x) for x in data.get("colours", []) if isinstance(x, str)) if c]
        current = parse(data.get("current", "")) if isinstance(data.get("current"), str) else None
        return colours[:LIMIT], current
    except (OSError, ValueError, AttributeError):
        return list(STARTERS), None


def store(colours, current):
    try:
        os.makedirs(os.path.dirname(SAVE), exist_ok=True)
        tmp = SAVE + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"colours": colours, "current": hex_text(current)}, f)
        os.replace(tmp, SAVE)
    except OSError:
        pass


# Picking from the screen -------------------------------------------------------

def grab_screen():
    """A screenshot of every screen as a GdkPixbuf, or (None, reason)."""
    if not shutil.which("grim"):
        return None, "The screen can't be read because the screenshot tool (grim) isn't installed."
    fd, path = tempfile.mkstemp(suffix=".png", prefix="swatch-")
    os.close(fd)
    try:
        if subprocess.run(["grim", path], capture_output=True, timeout=10).returncode != 0:
            return None, "The screen couldn't be read."
        return GdkPixbuf.Pixbuf.new_from_file(path), None
    except (OSError, subprocess.SubprocessError, GLib.Error):
        return None, "The screen couldn't be read."
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


class Picker:
    """One full-screen overlay per screen; a click picks, Escape cancels."""

    def __init__(self, shot, done):
        self.done = done
        self.shot = shot
        self.windows = []
        display = Gdk.Display.get_default()
        monitors = [display.get_monitor(i) for i in range(display.get_n_monitors())]
        left = min((m.get_geometry().x for m in monitors), default=0)
        top = min((m.get_geometry().y for m in monitors), default=0)
        right = max((m.get_geometry().x + m.get_geometry().width for m in monitors), default=1)
        self.ratio = shot.get_width() / max(1, right - left)
        for monitor in monitors:
            self.windows.append(PickerWindow(self, monitor, left, top))
        for window in self.windows:
            window.show_all()

    def pixel(self, x, y):
        """The colour at layout point (x, y) of the screenshot."""
        px = min(self.shot.get_width() - 1, max(0, int(x * self.ratio)))
        py = min(self.shot.get_height() - 1, max(0, int(y * self.ratio)))
        data = self.shot.get_pixels()
        at = py * self.shot.get_rowstride() + px * self.shot.get_n_channels()
        return tuple(data[at:at + 3])

    def finish(self, rgb):
        for window in self.windows:
            window.destroy()
        self.windows = []
        self.done(rgb)


class PickerWindow(Gtk.Window):
    def __init__(self, picker, monitor, left, top):
        super().__init__(title="Pick a Colour")
        self.picker = picker
        geometry = monitor.get_geometry()
        self.origin = (geometry.x - left, geometry.y - top)
        self.size = (geometry.width, geometry.height)
        self.pointer = None
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-swatch")
        GtkLayerShell.set_monitor(self, monitor)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        ratio = picker.ratio
        part = GdkPixbuf.Pixbuf.new_subpixbuf(
            picker.shot, int(self.origin[0] * ratio), int(self.origin[1] * ratio),
            min(picker.shot.get_width() - int(self.origin[0] * ratio), int(self.size[0] * ratio)),
            min(picker.shot.get_height() - int(self.origin[1] * ratio), int(self.size[1] * ratio)))
        self.background = part.scale_simple(self.size[0], self.size[1], GdkPixbuf.InterpType.BILINEAR) \
            if abs(ratio - 1) > 0.01 else part
        area = Gtk.DrawingArea()
        area.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK |
                        Gdk.EventMask.LEAVE_NOTIFY_MASK)
        area.connect("draw", self.draw)
        area.connect("motion-notify-event", self.motion)
        area.connect("leave-notify-event", self.leave)
        area.connect("button-press-event", self.press)
        area.connect("realize", self._cursor)
        self.connect("key-press-event", self.key)
        self.area = area
        self.add(area)

    def _cursor(self, area):
        area.get_window().set_cursor(Gdk.Cursor.new_from_name(area.get_display(), "crosshair"))

    def at(self, x, y):
        return self.picker.pixel(self.origin[0] + x, self.origin[1] + y)

    def draw(self, _area, cr):
        Gdk.cairo_set_source_pixbuf(cr, self.background, 0, 0)
        cr.paint()
        if self.pointer is None:
            return
        x, y = self.pointer
        half = LOUPE // 2
        radius = LOUPE * CELL / 2
        cx = x + radius + 24 if x + radius * 2 + 40 < self.size[0] else x - radius - 24
        cy = y + radius + 24 if y + radius * 2 + 70 < self.size[1] else y - radius - 50
        cr.save()
        cr.arc(cx, cy, radius, 0, 2 * math.pi)
        cr.clip()
        for row in range(LOUPE):
            for col in range(LOUPE):
                r, g, b = self.at(int(x) - half + col, int(y) - half + row)
                cr.set_source_rgb(r / 255, g / 255, b / 255)
                cr.rectangle(cx - radius + col * CELL, cy - radius + row * CELL, CELL, CELL)
                cr.fill()
        cr.set_source_rgba(0, 0, 0, 0.12)
        cr.set_line_width(1)
        for n in range(LOUPE + 1):
            cr.move_to(cx - radius + n * CELL, cy - radius)
            cr.line_to(cx - radius + n * CELL, cy + radius)
            cr.move_to(cx - radius, cy - radius + n * CELL)
            cr.line_to(cx + radius, cy - radius + n * CELL)
        cr.stroke()
        cr.restore()
        middle = (cx - CELL / 2, cy - CELL / 2)
        cr.set_line_width(2)
        cr.set_source_rgb(1, 1, 1)
        cr.rectangle(middle[0] - 1, middle[1] - 1, CELL + 2, CELL + 2)
        cr.stroke()
        cr.set_source_rgb(0, 0, 0)
        cr.set_line_width(1)
        cr.rectangle(middle[0] - 2.5, middle[1] - 2.5, CELL + 5, CELL + 5)
        cr.stroke()
        cr.arc(cx, cy, radius, 0, 2 * math.pi)
        cr.set_source_rgba(1, 1, 1, 0.95)
        cr.set_line_width(4)
        cr.stroke_preserve()
        cr.set_source_rgba(0, 0, 0, 0.35)
        cr.set_line_width(1)
        cr.stroke()
        text = hex_text(self.at(int(x), int(y)))
        cr.select_font_face("sans-serif", 0, 1)
        cr.set_font_size(13)
        extents = cr.text_extents(text)
        w, h = extents.width + 16, 22
        bx, by = cx - w / 2, cy + radius + 8
        cr.new_path()
        cr.arc(bx + 6, by + 6, 6, math.pi, 1.5 * math.pi)
        cr.arc(bx + w - 6, by + 6, 6, 1.5 * math.pi, 2 * math.pi)
        cr.arc(bx + w - 6, by + h - 6, 6, 0, 0.5 * math.pi)
        cr.arc(bx + 6, by + h - 6, 6, 0.5 * math.pi, math.pi)
        cr.close_path()
        cr.set_source_rgba(0, 0, 0, 0.75)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.move_to(bx + 8 - extents.x_bearing, by + h / 2 - extents.y_bearing - extents.height / 2)
        cr.show_text(text)

    def motion(self, area, event):
        self.pointer = (event.x, event.y)
        for window in self.picker.windows:
            if window is not self and window.pointer is not None:
                window.pointer = None
                window.area.queue_draw()
        area.queue_draw()

    def leave(self, area, _event):
        self.pointer = None
        area.queue_draw()

    def press(self, _area, event):
        if event.button == 1:
            self.picker.finish(self.at(int(event.x), int(event.y)))
        else:
            self.picker.finish(None)
        return True

    def key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.picker.finish(None)
        elif event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space) and self.pointer:
            self.picker.finish(self.at(int(self.pointer[0]), int(self.pointer[1])))
        elif event.keyval in (Gdk.KEY_Left, Gdk.KEY_Right, Gdk.KEY_Up, Gdk.KEY_Down) and self.pointer:
            dx = {Gdk.KEY_Left: -1, Gdk.KEY_Right: 1}.get(event.keyval, 0)
            dy = {Gdk.KEY_Up: -1, Gdk.KEY_Down: 1}.get(event.keyval, 0)
            x = min(self.size[0] - 1, max(0, self.pointer[0] + dx))
            y = min(self.size[1] - 1, max(0, self.pointer[1] + dy))
            self.pointer = (x, y)
            self.area.queue_draw()
        return True


# The window --------------------------------------------------------------------

class Well(Gtk.DrawingArea):
    """The big sample of the current colour."""

    def __init__(self, window):
        super().__init__()
        self.window = window
        self.set_size_request(150, 150)

    def do_draw(self, cr):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        r, g, b = self.window.rgb
        radius = 16
        cr.new_path()
        cr.arc(radius, radius, radius, math.pi, 1.5 * math.pi)
        cr.arc(w - radius, radius, radius, 1.5 * math.pi, 2 * math.pi)
        cr.arc(w - radius, h - radius, radius, 0, 0.5 * math.pi)
        cr.arc(radius, h - radius, radius, 0.5 * math.pi, math.pi)
        cr.close_path()
        cr.set_source_rgb(r / 255, g / 255, b / 255)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.15)
        cr.set_line_width(1)
        cr.stroke()
        light = contrast(self.window.rgb, (255, 255, 255)) >= contrast(self.window.rgb, (0, 0, 0))
        cr.set_source_rgb(*((1, 1, 1) if light else (0, 0, 0)))
        cr.select_font_face("sans-serif", 0, 1)
        cr.set_font_size(15)
        text = "Aa"
        extents = cr.text_extents(text)
        cr.move_to(w - extents.width - 16, h - 16)
        cr.show_text(text)


class Chip(Gtk.Button):
    """One saved colour in the palette."""

    def __init__(self, window, colour):
        super().__init__()
        self.colour = colour
        self.window = window
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.set_tooltip_text(f"{colour}  ({name_for(parse(colour))})\nRight-click to remove")
        dot = Gtk.DrawingArea()
        dot.set_size_request(28, 28)
        dot.connect("draw", self._draw)
        self.add(dot)
        self.connect("clicked", lambda _b: window.set_colour(parse(colour)))
        self.connect("button-press-event", self._press)

    def _draw(self, area, cr):
        w, h = area.get_allocated_width(), area.get_allocated_height()
        r, g, b = parse(self.colour)
        cr.arc(w / 2, h / 2, min(w, h) / 2 - 1, 0, 2 * math.pi)
        cr.set_source_rgb(r / 255, g / 255, b / 255)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.2)
        cr.set_line_width(1)
        cr.stroke()
        if parse(self.colour) == self.window.rgb:
            cr.arc(w / 2, h / 2, 4, 0, 2 * math.pi)
            light = contrast(parse(self.colour), (255, 255, 255)) >= 3
            cr.set_source_rgb(*((1, 1, 1) if light else (0, 0, 0)))
            cr.fill()

    def _press(self, _button, event):
        if event.button == 3:
            menu = Gtk.Menu()
            item = Gtk.MenuItem(label="Remove from Palette")
            item.connect("activate", lambda _i: self.window.remove(self.colour))
            menu.append(item)
            copy = Gtk.MenuItem(label=f"Copy {self.colour}")
            copy.connect("activate", lambda _i: self.window.copy_text(self.colour))
            menu.append(copy)
            menu.show_all()
            menu.attach_to_widget(self, None)
            menu.popup_at_pointer(event)
            return True
        return False


class SwatchWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Swatch")
        self.set_default_size(520, -1)
        self.set_resizable(False)
        self.colours, current = load()
        self.rgb = current or parse(self.colours[0] if self.colours else STARTERS[0])
        header = Gtk.HeaderBar(show_close_button=True, title="Swatch")
        self.set_titlebar(header)
        pick = Gtk.Button(label="Pick from Screen")
        pick.set_action_name("win.pick")
        pick.set_tooltip_text("Click anywhere on the screen to take its colour (⌘⇧C)")
        pick.get_style_context().add_class("suggested-action")
        header.pack_start(pick)
        choose = Gtk.Button(label="Choose…")
        choose.set_action_name("win.choose")
        header.pack_start(choose)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        body.set_border_width(20)
        self.add(body)
        top = Gtk.Box(spacing=20)
        body.pack_start(top, False, False, 0)
        self.well = Well(self)
        top.pack_start(self.well, False, False, 0)
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        right.set_valign(Gtk.Align.CENTER)
        top.pack_start(right, True, True, 0)
        self.name = Gtk.Label(xalign=0)
        right.pack_start(self.name, False, False, 0)
        grid = Gtk.Grid(column_spacing=10, row_spacing=6)
        right.pack_start(grid, False, False, 0)
        self.fields = {}
        for row, kind in enumerate(("Hex", "RGB", "HSL")):
            label = Gtk.Label(label=kind, xalign=1)
            label.get_style_context().add_class("dim-label")
            grid.attach(label, 0, row, 1, 1)
            entry = Gtk.Entry(width_chars=20)
            entry.set_hexpand(True)
            entry.connect("activate", self._typed)
            grid.attach(entry, 1, row, 1, 1)
            copy = Gtk.Button.new_from_icon_name("edit-copy-symbolic", Gtk.IconSize.BUTTON)
            copy.set_tooltip_text(f"Copy the {kind} value")
            copy.connect("clicked", lambda _b, e=entry: self.copy_text(e.get_text()))
            grid.attach(copy, 2, row, 1, 1)
            self.fields[kind] = entry
        self.readable = Gtk.Label(xalign=0)
        self.readable.get_style_context().add_class("dim-label")
        right.pack_start(self.readable, False, False, 0)

        line = Gtk.Box(spacing=8)
        body.pack_start(line, False, False, 0)
        title = Gtk.Label(xalign=0)
        title.set_markup("<b>Palette</b>")
        line.pack_start(title, True, True, 0)
        keep = Gtk.Button(label="Add to Palette")
        keep.set_action_name("win.keep")
        line.pack_end(keep, False, False, 0)
        self.palette = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=12,
                                   min_children_per_line=6, column_spacing=0, row_spacing=0)
        self.palette.set_homogeneous(True)
        body.pack_start(self.palette, False, False, 0)
        self.empty = Gtk.Label(label="Colours you add to the palette are kept here.", xalign=0)
        self.empty.get_style_context().add_class("dim-label")
        self.empty.set_no_show_all(True)
        body.pack_start(self.empty, False, False, 0)
        self.status = Gtk.Label(xalign=0)
        self.status.get_style_context().add_class("dim-label")
        body.pack_start(self.status, False, False, 0)

        menus.add_actions(self, {"pick": self.pick, "choose": self.choose, "keep": self.keep,
                                 "copy-hex": lambda: self.copy_text(hex_text(self.rgb)),
                                 "copy-rgb": lambda: self.copy_text(rgb_text(self.rgb)),
                                 "copy-hsl": lambda: self.copy_text(hsl_text(self.rgb)),
                                 "paste": self.paste, "clear": self.clear, "close": self.close})
        self.connect("delete-event", lambda *_a: store(self.colours, self.rgb) and False)
        self.show_all()
        self.fill_palette()
        self.show_colour()

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Swatch")
        dialog.format_secondary_text("Swatch picks colours from the screen and keeps the ones you like. "
                                     "It is part of freemac.")
        dialog.run()
        dialog.destroy()

    # Showing -------------------------------------------------------------------

    def show_colour(self):
        self.fields["Hex"].set_text(hex_text(self.rgb))
        self.fields["RGB"].set_text(rgb_text(self.rgb))
        self.fields["HSL"].set_text(hsl_text(self.rgb))
        self.name.set_markup(f"<span size='15000' weight='600'>{name_for(self.rgb).capitalize()}</span>")
        white, black = contrast(self.rgb, (255, 255, 255)), contrast(self.rgb, (0, 0, 0))
        best = "White" if white >= black else "Black"
        self.readable.set_text(f"{best} text reads best on it ({max(white, black):.1f} to 1)")
        self.well.queue_draw()
        for child in self.palette.get_children():
            child.get_child().queue_draw()

    def fill_palette(self):
        for child in self.palette.get_children():
            self.palette.remove(child)
        for colour in self.colours:
            chip = Chip(self, colour)
            self.palette.add(chip)
        self.palette.show_all()
        self.empty.set_visible(not self.colours)

    def set_colour(self, rgb, note=""):
        if rgb:
            self.rgb = tuple(rgb)
            self.show_colour()
            store(self.colours, self.rgb)
        self.status.set_text(note)

    # Actions -------------------------------------------------------------------

    def _typed(self, entry):
        rgb = parse(entry.get_text())
        if entry is self.fields["HSL"] and rgb is None:
            rgb = self._parse_hsl(entry.get_text())
        if rgb:
            self.set_colour(rgb)
        else:
            self.status.set_text("That isn't a colour Swatch understands. Try #2F7BF5 or rgb(47, 123, 245).")
            self.show_colour()

    @staticmethod
    def _parse_hsl(text):
        text = text.strip().lower()
        if text.startswith("hsl"):
            text = text[text.find("(") + 1:].rstrip(")")
        parts = [p.strip().rstrip("%") for p in text.replace(",", " ").split() if p.strip()]
        try:
            h, s, lightness = (float(p) for p in parts)
        except ValueError:
            return None
        if not (0 <= s <= 100 and 0 <= lightness <= 100):
            return None
        r, g, b = colorsys.hls_to_rgb((h % 360) / 360, lightness / 100, s / 100)
        return tuple(round(v * 255) for v in (r, g, b))

    def copy_text(self, text):
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
        self.status.set_text(f"Copied {text}")

    def paste(self):
        text = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).wait_for_text() or ""
        rgb = parse(text) or self._parse_hsl(text)
        if rgb:
            self.set_colour(rgb, f"Pasted {hex_text(rgb)}")
        else:
            self.status.set_text("There's no colour on the clipboard.")

    def keep(self):
        colour = hex_text(self.rgb)
        if colour in self.colours:
            self.colours.remove(colour)
        self.colours.insert(0, colour)
        del self.colours[LIMIT:]
        store(self.colours, self.rgb)
        self.fill_palette()
        self.status.set_text(f"Added {colour} to the palette")

    def remove(self, colour):
        if colour in self.colours:
            self.colours.remove(colour)
            store(self.colours, self.rgb)
            self.fill_palette()

    def clear(self):
        if not self.colours:
            return
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                                   buttons=Gtk.ButtonsType.NONE, text="Clear the whole palette?")
        dialog.format_secondary_text("The colours you kept will be removed. This can't be undone.")
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Clear Palette", Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            self.colours = []
            store(self.colours, self.rgb)
            self.fill_palette()
        dialog.destroy()

    def choose(self):
        dialog = Gtk.ColorChooserDialog(title="Choose a Colour", transient_for=self, modal=True)
        rgba = Gdk.RGBA()
        rgba.parse(hex_text(self.rgb))
        dialog.set_rgba(rgba)
        dialog.set_use_alpha(False)
        if dialog.run() == Gtk.ResponseType.OK:
            c = dialog.get_rgba()
            self.set_colour(tuple(round(v * 255) for v in (c.red, c.green, c.blue)))
        dialog.destroy()

    def pick(self):
        # Step out of the way so the window isn't in the picture.
        self.hide()
        GLib.timeout_add(350, self._grab)

    def _grab(self):
        shot, error = grab_screen()
        if shot is None:
            self.present()
            self.status.set_text(error)
            return False
        Picker(shot, self._picked)
        return False

    def _come_back(self):
        self.present()
        self._tries = 0
        GLib.timeout_add(100, self._take_focus)
        return False

    def _take_focus(self):
        """Wayland doesn't let a window give itself the focus, so ask Wayfire,
        trying for a moment while the window comes back on screen."""
        self._tries += 1
        try:
            from .wfipc import Wayfire
            wf = Wayfire()
            if (wf.focused() or {}).get("app-id") == "freemac-swatch":
                return False
            view = wf.own_view("freemac-swatch")
            if view is not None:
                wf.focus(view)
        except (ConnectionError, OSError, ValueError, KeyError, AttributeError):
            return False
        return self._tries < 15

    def _picked(self, rgb):
        # Come back once the overlay has gone, so the window takes the focus.
        GLib.timeout_add(120, self._come_back)
        if rgb:
            self.set_colour(rgb, f"Picked {hex_text(rgb)}")


def menubar():
    return menus.menubar([
        ("_File", [[("Pick from Screen", "win.pick", "<Shift><Ctrl>c"), ("Choose a Colour…", "win.choose", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Copy Hex", "win.copy-hex", "<Shift><Ctrl>x"), ("Copy RGB", "win.copy-rgb", None),
                    ("Copy HSL", "win.copy-hsl", None), ("Paste Colour", "win.paste", "<Shift><Ctrl>v")]]),
        ("_Palette", [[("Add to Palette", "win.keep", "<Ctrl>d")], [("Clear Palette…", "win.clear", None)]]),
    ])


class Swatch(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": self.quit, "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_accels_for_action("win.pick", ["<Shift><Control>c"])
        self.set_accels_for_action("win.copy-hex", ["<Shift><Control>x"])
        self.set_accels_for_action("win.paste", ["<Shift><Control>v"])
        self.set_accels_for_action("win.keep", ["<Control>d"])
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = SwatchWindow(self)
        self.window.present()


def main():
    GLib.set_prgname("freemac-swatch")
    return Swatch().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
