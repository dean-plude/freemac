# SPDX-License-Identifier: GPL-3.0-or-later
"""Easel: draw on a big canvas.

Pick a pen, a highlighter, a shape, text, a sticker or the eraser from the
toolbar, then a colour and a size, and draw. Shapes take Shift for a square,
a circle or a straight 45° line. The arrow tool picks up anything you drew
and moves it, and Delete throws the picked thing away. Every drawing is kept
as you go, listed on the left with a little picture of it, and File > Export
as Picture saves a PNG for sharing.

Original freemac code. A drawing is a list of strokes, shapes, texts and
stickers in a JSON file in ~/.local/share/freemac/easel, drawn with cairo on
a 1600 × 1000 page that's scaled to fit the window. The finished strokes are
kept in one picture so a long drawing stays quick, and the eraser clears that
picture where it goes, so the paper colour can still change underneath.
"""
import json
import math
import os
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
import cairo  # noqa: E402
from gi.repository import Gdk, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Easel"
WIDTH, HEIGHT = 1600, 1000

COLOURS = ["#1d1d1f", "#ffffff", "#ff3b30", "#ff9500", "#ffcc00", "#34c759",
           "#00c7be", "#007aff", "#af52de", "#ff2d55", "#a2845e"]
SIZES = {"pen": (3, 8, 18), "highlight": (16, 30, 52), "erase": (16, 40, 90),
         "shape": (3, 7, 14), "text": (30, 52, 90), "sticker": (60, 110, 180)}
PAPERS = {"white": ("White", (1, 1, 1)), "cream": ("Cream", (0.99, 0.96, 0.88)),
          "night": ("Night", (0.11, 0.12, 0.15))}
STICKERS = "⭐ ❤️ 😀 😎 🥳 🦄 🐶 🐱 🦊 🐸 🐢 🦋 🌈 ☀️ 🌙 ⚡ 🌸 🌻 🍕 🍦 🎈 🎁 🚀 ⚽ 🏆 👑 💎 🎵 👍 ✅".split()
SHAPES = ("line", "arrow", "rect", "oval")
TOOLS = [  # name, tip, key
    ("move", "Pick Up and Move (V)", "v"), ("pen", "Pen (P)", "p"), ("highlight", "Highlighter (H)", "h"),
    ("erase", "Eraser (E)", "e"), ("line", "Line (L)", "l"), ("arrow", "Arrow (A)", "a"),
    ("rect", "Rectangle (R)", "r"), ("oval", "Oval (O)", "o"), ("text", "Text (T)", "t"),
    ("sticker", "Sticker (S)", "s"),
]

CSS = b"""
.easel-side { background: @theme_bg_color; }
.easel-side list { background: transparent; }
.easel-side row { padding: 8px; border-radius: 8px; }
.easel-thumb-name { font-size: 0.9em; }
.easel-small { font-size: 0.8em; color: alpha(currentColor, 0.6); }
.easel-tools { padding: 6px 10px; border-bottom: 1px solid alpha(currentColor, 0.1); }
.easel-tools button, .easel-tools radiobutton { padding: 3px; min-width: 0; min-height: 0; margin: 0; }
.easel-sep { min-width: 1px; background: alpha(currentColor, 0.15); margin: 4px 6px; }
.easel-canvas { background: alpha(currentColor, 0.06); }
.easel-sticker-grid button { font-size: 22px; padding: 2px 6px; }
"""


# -- the files --

def folder():
    path = os.path.join(GLib.get_user_data_dir(), "freemac", "easel")
    os.makedirs(path, exist_ok=True)
    return path


def drawings():
    """Every drawing, the one changed last first."""
    found = []
    for name in os.listdir(folder()):
        if name.endswith(".json"):
            path = os.path.join(folder(), name)
            try:
                found.append((os.path.getmtime(path), path))
            except OSError:
                pass
    return [path for _m, path in sorted(found, reverse=True)]


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(doc, dict):
        return None
    doc.setdefault("name", "Drawing")
    doc.setdefault("paper", "white")
    doc["items"] = [item for item in doc.get("items", []) if isinstance(item, dict)]
    return doc


def save(path, doc):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, separators=(",", ":"))
    os.replace(tmp, path)


def new_drawing():
    taken = set()
    for path in drawings():
        doc = load(path)
        if doc:
            taken.add(doc["name"])
    number = 1
    while f"Drawing {number}" in taken:
        number += 1
    path = os.path.join(folder(), f"{int(time.time() * 1000)}.json")
    doc = {"name": f"Drawing {number}", "paper": "white", "items": []}
    save(path, doc)
    return path


def _hsv(hue):
    i = int(hue * 6) % 6
    f = hue * 6 - int(hue * 6)
    return [(1, f, 0), (1 - f, 1, 0), (0, 1, f), (0, 1 - f, 1), (f, 0, 1), (1, 0, 1 - f)][i]


def rgb(hex_colour):
    hex_colour = hex_colour.lstrip("#")
    try:
        return tuple(int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except ValueError:
        return (0, 0, 0)


# -- drawing --

def _path(cr, points):
    """A smooth path through the points: quadratic curves between midpoints."""
    if len(points) == 1:
        x, y = points[0]
        cr.move_to(x, y)
        cr.line_to(x + 0.01, y)
        return
    cr.move_to(*points[0])
    for (x1, y1), (x2, y2) in zip(points[1:-1], points[2:]):
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        cx, cy = cr.get_current_point()
        # A quadratic curve written as a cubic.
        cr.curve_to(cx + 2 / 3 * (x1 - cx), cy + 2 / 3 * (y1 - cy),
                    mx + 2 / 3 * (x1 - mx), my + 2 / 3 * (y1 - my), mx, my)
    cr.line_to(*points[-1])


def shape_corners(item):
    return item["x1"], item["y1"], item["x2"], item["y2"]


def _text_layout(cr, item):
    layout = PangoCairo.create_layout(cr)
    font = Pango.FontDescription("Sans Bold" if item["kind"] == "text" else "Noto Color Emoji")
    font.set_absolute_size(item["size"] * Pango.SCALE)
    layout.set_font_description(font)
    layout.set_text(item["text"], -1)
    return layout


def text_size(item):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
    w, h = _text_layout(cairo.Context(surface), item).get_pixel_size()
    return w, h


def draw_item(cr, item):
    kind = item.get("kind")
    cr.save()
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)
    r, g, b = rgb(item.get("color", "#000000"))
    if kind in ("pen", "highlight", "erase"):
        points = item.get("points") or []
        if points:
            _path(cr, points)
            cr.set_line_width(item.get("width", 6))
            if kind == "erase":
                cr.set_operator(cairo.OPERATOR_CLEAR)
            elif kind == "highlight":
                cr.set_line_cap(cairo.LINE_CAP_SQUARE)
                cr.set_source_rgba(r, g, b, 0.38)
            else:
                cr.set_source_rgb(r, g, b)
            cr.stroke()
    elif kind in SHAPES:
        x1, y1, x2, y2 = shape_corners(item)
        cr.set_line_width(item.get("width", 6))
        cr.set_source_rgb(r, g, b)
        if kind in ("line", "arrow"):
            cr.move_to(x1, y1)
            cr.line_to(x2, y2)
            cr.stroke()
            if kind == "arrow" and (x1, y1) != (x2, y2):
                angle = math.atan2(y2 - y1, x2 - x1)
                head = 14 + item.get("width", 6) * 2.2
                for side in (-0.45, 0.45):
                    cr.move_to(x2, y2)
                    cr.line_to(x2 - head * math.cos(angle + side), y2 - head * math.sin(angle + side))
                cr.stroke()
        else:
            x, y, w, h = min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1)
            if kind == "rect":
                radius = min(12, w / 2, h / 2)
                cr.new_sub_path()
                cr.arc(x + w - radius, y + radius, radius, -math.pi / 2, 0)
                cr.arc(x + w - radius, y + h - radius, radius, 0, math.pi / 2)
                cr.arc(x + radius, y + h - radius, radius, math.pi / 2, math.pi)
                cr.arc(x + radius, y + radius, radius, math.pi, 1.5 * math.pi)
                cr.close_path()
            elif w > 0 and h > 0:
                cr.save()
                cr.translate(x + w / 2, y + h / 2)
                cr.scale(w / 2, h / 2)
                cr.arc(0, 0, 1, 0, 2 * math.pi)
                cr.restore()
            if item.get("fill"):
                cr.fill_preserve()
            cr.stroke()
    elif kind in ("text", "sticker"):
        layout = _text_layout(cr, item)
        cr.move_to(item["x"], item["y"])
        cr.set_source_rgb(r, g, b)
        PangoCairo.show_layout(cr, layout)
    cr.restore()


def bounds(item):
    """The box an item covers, or None for one that can't be picked up."""
    kind = item.get("kind")
    if kind in ("pen", "highlight"):
        points = item.get("points") or []
        if not points:
            return None
        pad = item.get("width", 6) / 2
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        return min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad
    if kind in SHAPES:
        x1, y1, x2, y2 = shape_corners(item)
        pad = item.get("width", 6) / 2 + (14 + item.get("width", 6) * 2.2 if kind == "arrow" else 0)
        return min(x1, x2) - pad, min(y1, y2) - pad, max(x1, x2) + pad, max(y1, y2) + pad
    if kind in ("text", "sticker"):
        w, h = text_size(item)
        return item["x"], item["y"], item["x"] + w, item["y"] + h
    return None


def moved(item, dx, dy):
    """A copy of an item, moved."""
    copy = dict(item)
    if "points" in copy:
        copy["points"] = [[x + dx, y + dy] for x, y in copy["points"]]
    for key in ("x1", "x2", "x"):
        if key in copy:
            copy[key] += dx
    for key in ("y1", "y2", "y"):
        if key in copy:
            copy[key] += dy
    return copy


def render(doc, scale=1.0, layer=None):
    """The whole drawing as a picture, paper included."""
    surface = cairo.ImageSurface(cairo.FORMAT_RGB24, max(1, int(WIDTH * scale)), max(1, int(HEIGHT * scale)))
    cr = cairo.Context(surface)
    cr.set_source_rgb(*PAPERS.get(doc.get("paper"), PAPERS["white"])[1])
    cr.paint()
    cr.scale(scale, scale)
    cr.set_source_surface(layer or draw_layer(doc["items"]), 0, 0)
    cr.paint()
    return surface


def draw_layer(items):
    """Everything drawn so far, on clear paper, so the eraser can clear it."""
    layer = cairo.ImageSurface(cairo.FORMAT_ARGB32, WIDTH, HEIGHT)
    cr = cairo.Context(layer)
    for item in items:
        draw_item(cr, item)
    return layer


# -- the toolbar's little pictures --

def draw_tool_icon(cr, tool, size, colour):
    cr.set_source_rgba(*colour)
    cr.set_line_width(1.6)
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)
    s = size
    if tool == "move":
        cr.move_to(s * 0.3, s * 0.18)
        for x, y in ((0.3, 0.78), (0.44, 0.64), (0.56, 0.86), (0.64, 0.82), (0.53, 0.6), (0.74, 0.6)):
            cr.line_to(s * x, s * y)
        cr.close_path()
        cr.fill()
    elif tool in ("pen", "highlight"):
        cr.save()
        cr.translate(s / 2, s / 2)
        cr.rotate(math.pi / 4)
        w = 0.16 if tool == "pen" else 0.26
        cr.rectangle(-s * w / 2, -s * 0.38, s * w, s * 0.5)
        cr.stroke()
        cr.move_to(-s * w / 2, s * 0.12)
        cr.line_to(0, s * (0.3 if tool == "pen" else 0.22))
        cr.line_to(s * w / 2, s * 0.12)
        if tool == "highlight":
            cr.close_path()
        cr.stroke()
        cr.restore()
        if tool == "highlight":
            cr.set_source_rgba(1, 0.8, 0, 0.75)
            cr.set_line_width(s * 0.14)
            cr.move_to(s * 0.15, s * 0.86)
            cr.line_to(s * 0.55, s * 0.86)
            cr.stroke()
    elif tool == "erase":
        cr.save()
        cr.translate(s / 2, s / 2)
        cr.rotate(-math.pi / 4)
        cr.rectangle(-s * 0.36, -s * 0.16, s * 0.72, s * 0.32)
        cr.stroke()
        cr.rectangle(-s * 0.36, -s * 0.16, s * 0.28, s * 0.32)
        cr.fill()
        cr.restore()
    elif tool == "line":
        cr.move_to(s * 0.2, s * 0.8)
        cr.line_to(s * 0.8, s * 0.2)
        cr.stroke()
    elif tool == "arrow":
        cr.move_to(s * 0.2, s * 0.8)
        cr.line_to(s * 0.8, s * 0.2)
        cr.move_to(s * 0.45, s * 0.2)
        cr.line_to(s * 0.8, s * 0.2)
        cr.line_to(s * 0.8, s * 0.55)
        cr.stroke()
    elif tool == "rect":
        cr.rectangle(s * 0.18, s * 0.26, s * 0.64, s * 0.48)
        cr.stroke()
    elif tool == "oval":
        cr.save()
        cr.translate(s / 2, s / 2)
        cr.scale(s * 0.34, s * 0.26)
        cr.arc(0, 0, 1, 0, 2 * math.pi)
        cr.restore()
        cr.stroke()
    elif tool == "text":
        layout = PangoCairo.create_layout(cr)
        font = Pango.FontDescription("Serif Bold")
        font.set_absolute_size(s * 0.7 * Pango.SCALE)
        layout.set_font_description(font)
        layout.set_text("A", -1)
        w, h = layout.get_pixel_size()
        cr.move_to((s - w) / 2, (s - h) / 2)
        PangoCairo.show_layout(cr, layout)
    elif tool == "sticker":
        cr.arc(s / 2, s / 2, s * 0.34, 0, 2 * math.pi)
        cr.stroke()
        cr.arc(s * 0.38, s * 0.42, s * 0.04, 0, 2 * math.pi)
        cr.fill()
        cr.arc(s * 0.62, s * 0.42, s * 0.04, 0, 2 * math.pi)
        cr.fill()
        cr.arc(s / 2, s * 0.5, s * 0.18, 0.2 * math.pi, 0.8 * math.pi)
        cr.stroke()


class ToolIcon(Gtk.DrawingArea):
    def __init__(self, tool):
        super().__init__()
        self.tool = tool
        self.set_size_request(22, 22)
        self.connect("draw", self._draw)

    def _draw(self, _w, cr):
        colour = self.get_style_context().get_color(self.get_state_flags())
        draw_tool_icon(cr, self.tool, 22, (colour.red, colour.green, colour.blue, colour.alpha))


class Swatch(Gtk.DrawingArea):
    """A round colour, ringed when it's the one in use."""

    def __init__(self, colour, chosen):
        super().__init__()
        self.colour = colour
        self.chosen = chosen
        self.set_size_request(22, 22)
        self.connect("draw", self._draw)

    def _draw(self, _w, cr):
        r, g, b = rgb(self.colour)
        cr.arc(11, 11, 8, 0, 2 * math.pi)
        cr.set_source_rgb(r, g, b)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.25)
        cr.set_line_width(1)
        cr.stroke()
        if self.chosen():
            fg = self.get_style_context().get_color(Gtk.StateFlags.NORMAL)
            cr.arc(11, 11, 10.5, 0, 2 * math.pi)
            cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.8)
            cr.set_line_width(1.5)
            cr.stroke()


class SizeDot(Gtk.DrawingArea):
    def __init__(self, index, chosen):
        super().__init__()
        self.index = index
        self.chosen = chosen
        self.set_size_request(22, 22)
        self.connect("draw", self._draw)

    def _draw(self, _w, cr):
        fg = self.get_style_context().get_color(Gtk.StateFlags.NORMAL)
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 1 if self.chosen() else 0.45)
        cr.arc(11, 11, (2.5, 4.5, 7)[self.index], 0, 2 * math.pi)
        cr.fill()


# -- the canvas --

class Canvas(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(can_focus=True, hexpand=True, vexpand=True)
        self.window = window
        self.layer = None
        self.current = None        # the item being drawn
        self.picked = None         # index of the item picked up with the arrow
        self.drag_from = None
        self.drag_item = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)
        self.connect("realize", self._realized)
        self.view = None           # the finished strokes, at the size they're shown

    def _realized(self, _w):
        # Every movement of the pen, not just one a frame, so quick strokes stay curvy.
        self.get_window().set_event_compression(False)
        self.update_cursor()

    # The page sits in the middle, as big as fits.
    def page_box(self):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        scale = max(0.05, min((width - 32) / WIDTH, (height - 32) / HEIGHT))
        x = (width - WIDTH * scale) / 2
        y = (height - HEIGHT * scale) / 2
        return x, y, scale

    def to_page(self, event):
        x, y, scale = self.page_box()
        return (event.x - x) / scale, (event.y - y) / scale

    def from_page(self, px, py):
        x, y, scale = self.page_box()
        return x + px * scale, y + py * scale

    def invalidate(self):
        self.layer = None
        self.view = None
        self.queue_draw()

    def _view(self, scale):
        """The finished strokes scaled to the window once, not on every frame."""
        if self.view is None or self.view[0] != scale:
            surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, max(1, round(WIDTH * scale)),
                                         max(1, round(HEIGHT * scale)))
            cr = cairo.Context(surface)
            cr.scale(scale, scale)
            cr.set_source_surface(self.layer, 0, 0)
            cr.paint()
            self.view = (scale, surface)
        return self.view[1]

    def update_cursor(self):
        window = self.get_window()
        if window is None:
            return
        tool = self.window.tool
        name = {"move": "default", "text": "text", "sticker": "copy"}.get(tool, "crosshair")
        window.set_cursor(Gdk.Cursor.new_from_name(self.get_display(), name))

    def _draw(self, _w, cr):
        doc = self.window.doc
        if doc is None:
            return
        x, y, scale = self.page_box()
        x, y = round(x), round(y)
        cr.save()
        cr.translate(x, y)
        cr.save()
        cr.scale(scale, scale)
        # A soft shadow, then the paper.
        cr.set_source_rgba(0, 0, 0, 0.12)
        cr.rectangle(2 / scale, 4 / scale, WIDTH, HEIGHT)
        cr.fill()
        cr.set_source_rgb(*PAPERS.get(doc["paper"], PAPERS["white"])[1])
        cr.rectangle(0, 0, WIDTH, HEIGHT)
        cr.fill()
        cr.restore()
        if self.layer is None:
            items = list(doc["items"])
            if self.drag_item is not None and self.picked is not None:
                items[self.picked] = self.drag_item
            self.layer = draw_layer(items)
        view = self._view(scale)
        cr.rectangle(0, 0, view.get_width(), view.get_height())
        cr.clip()
        erasing = self.current is not None and self.current["kind"] == "erase"
        if erasing:
            cr.push_group()
        cr.set_source_surface(view, 0, 0)
        cr.paint()
        if self.current is not None:
            cr.save()
            cr.scale(scale, scale)
            draw_item(cr, self.current)
            cr.restore()
        if erasing:
            cr.pop_group_to_source()
            cr.paint()
        cr.scale(scale, scale)
        if self.picked is not None and self.picked < len(doc["items"]):
            box = bounds(self.drag_item or doc["items"][self.picked])
            if box:
                cr.set_source_rgba(0, 0.48, 1, 0.9)
                cr.set_line_width(2 / scale)
                cr.set_dash([6 / scale, 4 / scale])
                cr.rectangle(box[0] - 4, box[1] - 4, box[2] - box[0] + 8, box[3] - box[1] + 8)
                cr.stroke()
        cr.restore()

    def _press(self, _w, event):
        if self.window.doc is None or event.type != Gdk.EventType.BUTTON_PRESS:
            return False
        self.grab_focus()
        if event.button == 3:
            return False
        px, py = self.to_page(event)
        tool = self.window.tool
        w = self.window
        if tool == "move":
            self.picked = self._hit(px, py)
            self.drag_from = (px, py) if self.picked is not None else None
            self.drag_item = None
            self.queue_draw()
        elif tool in ("pen", "highlight", "erase"):
            self.current = {"kind": tool, "color": w.colour, "width": w.width(tool),
                            "points": [[round(px, 1), round(py, 1)]]}
        elif tool in SHAPES:
            self.current = {"kind": tool, "color": w.colour, "width": w.width("shape"),
                            "fill": w.fill and tool in ("rect", "oval"),
                            "x1": round(px, 1), "y1": round(py, 1), "x2": round(px, 1), "y2": round(py, 1)}
        elif tool == "text":
            w.ask_text(px, py, event)
        elif tool == "sticker":
            size = w.width("sticker")
            item = {"kind": "sticker", "text": w.sticker, "size": size, "color": "#000000", "x": 0, "y": 0}
            tw, th = text_size(item)
            item["x"], item["y"] = round(px - tw / 2), round(py - th / 2)
            w.add_item(item)
        self.queue_draw()
        return True

    def _hit(self, px, py):
        items = self.window.doc["items"]
        for index in range(len(items) - 1, -1, -1):
            box = bounds(items[index])
            if box and box[0] - 6 <= px <= box[2] + 6 and box[1] - 6 <= py <= box[3] + 6:
                return index
        return None

    def _motion(self, _w, event):
        if not event.state & Gdk.ModifierType.BUTTON1_MASK:
            return False
        px, py = self.to_page(event)
        if self.current is not None:
            kind = self.current["kind"]
            if kind in ("pen", "highlight", "erase"):
                last = self.current["points"][-1]
                if abs(last[0] - px) + abs(last[1] - py) >= 1.5:
                    self.current["points"].append([round(px, 1), round(py, 1)])
            else:
                if event.state & Gdk.ModifierType.SHIFT_MASK:
                    px, py = self._constrain(kind, px, py)
                self.current["x2"], self.current["y2"] = round(px, 1), round(py, 1)
            self.queue_draw()
        elif self.drag_from is not None:
            dx, dy = px - self.drag_from[0], py - self.drag_from[1]
            self.drag_item = moved(self.window.doc["items"][self.picked], round(dx, 1), round(dy, 1))
            self.invalidate()
        return True

    def _constrain(self, kind, px, py):
        x1, y1 = self.current["x1"], self.current["y1"]
        dx, dy = px - x1, py - y1
        if kind in ("rect", "oval"):
            side = max(abs(dx), abs(dy))
            return x1 + math.copysign(side, dx or 1), y1 + math.copysign(side, dy or 1)
        angle = round(math.atan2(dy, dx) / (math.pi / 4)) * (math.pi / 4)
        length = math.hypot(dx, dy)
        return x1 + length * math.cos(angle), y1 + length * math.sin(angle)

    def _release(self, _w, event):
        if event.button != 1:
            return False
        if self.current is not None:
            item, self.current = self.current, None
            if item["kind"] in SHAPES and math.hypot(item["x2"] - item["x1"], item["y2"] - item["y1"]) < 3:
                self.queue_draw()
                return True
            self.window.add_item(item)
        elif self.drag_item is not None:
            item, self.drag_item = self.drag_item, None
            self.drag_from = None
            self.window.replace(self.picked, item)
        self.drag_from = None
        return True


# -- the window --

class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Easel")
        self.set_default_size(1180, 760)
        self.path = None
        self.doc = None
        self.undo = []
        self.redo = []
        self.save_timer = 0
        self.tool = "pen"
        self.colour = COLOURS[7]
        self.size = 1
        self.fill = False
        self.sticker = STICKERS[0]
        self.thumbs = {}

        header = Gtk.HeaderBar(show_close_button=True, title="Easel")
        self.set_titlebar(header)
        self.header = header
        new = Gtk.Button.new_from_icon_name("document-new-symbolic", Gtk.IconSize.BUTTON)
        new.set_tooltip_text("New Drawing (⌘N)")
        new.connect("clicked", lambda _b: self.start_new())
        header.pack_start(new)
        self.undo_button = Gtk.Button.new_from_icon_name("edit-undo-symbolic", Gtk.IconSize.BUTTON)
        self.undo_button.set_tooltip_text("Undo (⌘Z)")
        self.undo_button.connect("clicked", lambda _b: self.do_undo())
        self.redo_button = Gtk.Button.new_from_icon_name("edit-redo-symbolic", Gtk.IconSize.BUTTON)
        self.redo_button.set_tooltip_text("Redo (⇧⌘Z)")
        self.redo_button.connect("clicked", lambda _b: self.do_redo())
        pair = Gtk.Box()
        pair.get_style_context().add_class("linked")
        pair.add(self.undo_button)
        pair.add(self.redo_button)
        header.pack_start(pair)
        export = Gtk.Button(label="Export")
        export.set_tooltip_text("Save the drawing as a picture (⌘E)")
        export.connect("clicked", lambda _b: self.export())
        header.pack_end(export)

        paned = Gtk.Paned()
        self.add(paned)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("easel-side")
        side.set_size_request(190, -1)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.list.connect("row-selected", self._row_selected)
        self.list.connect("button-press-event", self._list_pressed)
        scroller.add(self.list)
        side.pack_start(scroller, True, True, 0)
        paned.pack1(side, False, False)

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.canvas = Canvas(self)
        main.pack_start(self._build_tools(), False, False, 0)
        self.canvas.get_style_context().add_class("easel-canvas")
        main.pack_start(self.canvas, True, True, 0)
        paned.pack2(main, True, False)

        self.text_popover = None
        menus.add_actions(self, {
            "new": self.start_new, "export": self.export, "undo": self.do_undo, "redo": self.do_redo,
            "clear": self.clear, "delete-item": self.delete_picked, "duplicate": self.duplicate,
            "rename": self.rename, "trash": self.trash_drawing, "close": self.close})
        for key, (name, _colour) in PAPERS.items():
            menus.add_actions(self, {f"paper-{key}": lambda key=key: self.set_paper(key)})
        menus.add_toggle(self, "fill", False, self._fill_changed)
        self.connect("key-press-event", self._key)
        self.connect("destroy", self._closing)
        self.show_all()
        self.reload()

    def _build_tools(self):
        bar = Gtk.Box(spacing=1)
        bar.get_style_context().add_class("easel-tools")
        self.tool_buttons = {}
        group = None
        for name, tip, _key in TOOLS:
            button = Gtk.RadioButton.new_from_widget(group)
            group = group or button
            button.set_mode(False)
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.set_tooltip_text(tip)
            button.add(ToolIcon(name))
            button.connect("toggled", self._tool_toggled, name)
            self.tool_buttons[name] = button
            bar.pack_start(button, False, False, 0)
        self.tool_buttons["pen"].set_active(True)

        self.sticker_popover = Gtk.Popover(relative_to=self.tool_buttons["sticker"],
                                           position=Gtk.PositionType.BOTTOM)
        grid = Gtk.Grid(column_spacing=2, row_spacing=2)
        grid.get_style_context().add_class("easel-sticker-grid")
        for index, emoji in enumerate(STICKERS):
            choice = Gtk.Button(label=emoji, relief=Gtk.ReliefStyle.NONE)
            choice.connect("clicked", self._sticker_chosen, emoji)
            grid.attach(choice, index % 6, index // 6, 1, 1)
        grid.set_margin_start(6)
        grid.set_margin_end(6)
        grid.set_margin_top(6)
        grid.set_margin_bottom(6)
        self.sticker_popover.add(grid)
        grid.show_all()
        self.tool_buttons["sticker"].connect("button-press-event", self._sticker_pressed)

        bar.pack_start(self._sep(), False, False, 0)
        self.swatches = []
        for colour in COLOURS:
            bar.pack_start(self._swatch_button(colour), False, False, 0)
        picker = Gtk.Button(relief=Gtk.ReliefStyle.NONE, tooltip_text="More Colours")
        rainbow = Gtk.DrawingArea()
        rainbow.set_size_request(22, 22)
        rainbow.connect("draw", self._draw_rainbow)
        picker.add(rainbow)
        picker.connect("clicked", lambda _b: self._more_colours())
        bar.pack_start(picker, False, False, 0)

        bar.pack_start(self._sep(), False, False, 0)
        self.size_dots = []
        for index, tip in enumerate(("Thin", "Medium", "Thick")):
            button = Gtk.Button(relief=Gtk.ReliefStyle.NONE, tooltip_text=tip)
            dot = SizeDot(index, lambda index=index: self.size == index)
            button.add(dot)
            button.connect("clicked", self._size_chosen, index)
            self.size_dots.append(dot)
            bar.pack_start(button, False, False, 0)
        bar.pack_start(self._sep(), False, False, 0)
        self.fill_check = Gtk.CheckButton(label="Fill shapes")
        self.fill_check.connect("toggled", lambda b: self._fill_changed(b.get_active()))
        bar.pack_start(self.fill_check, False, False, 0)
        return bar

    def _sep(self):
        sep = Gtk.Box()
        sep.get_style_context().add_class("easel-sep")
        return sep

    def _swatch_button(self, colour):
        button = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
        swatch = Swatch(colour, lambda: self.colour == colour)
        button.add(swatch)
        button.connect("clicked", lambda _b: self.set_colour(colour))
        self.swatches.append(swatch)
        return button

    # -- choosing --

    def _tool_toggled(self, button, name):
        if button.get_active():
            self.tool = name
            if name != "move":
                self.canvas.picked = None
                self.canvas.queue_draw()
            self.canvas.update_cursor()

    def choose_tool(self, name):
        self.tool_buttons[name].set_active(True)
        if name == "sticker":
            self.sticker_popover.popup()

    def _sticker_pressed(self, _button, event):
        if event.button == 1 and self.tool == "sticker":
            self.sticker_popover.popup()
        elif event.button == 1:
            GLib.idle_add(self.sticker_popover.popup)
        return False

    def _sticker_chosen(self, _button, emoji):
        self.sticker = emoji
        self.sticker_popover.popdown()
        self.choose_tool("sticker")
        self.sticker_popover.popdown()

    def set_colour(self, colour):
        self.colour = colour
        for swatch in self.swatches:
            swatch.queue_draw()
        if self.canvas.picked is not None and self.doc:
            item = self.doc["items"][self.canvas.picked]
            if item.get("kind") not in ("sticker", "erase") and item.get("color") != colour:
                copy = dict(item)
                copy["color"] = colour
                self.replace(self.canvas.picked, copy)
        if self.tool in ("erase", "move"):
            return
        self.canvas.update_cursor()

    def _draw_rainbow(self, _w, cr):
        for step in range(36):
            hue = step / 36
            r, g, b = _hsv(hue)
            cr.move_to(11, 11)
            cr.arc(11, 11, 9, hue * 2 * math.pi - math.pi / 2, (hue + 1 / 36 + 0.005) * 2 * math.pi - math.pi / 2)
            cr.close_path()
            cr.set_source_rgb(r, g, b)
            cr.fill()
        cr.arc(11, 11, 3.5, 0, 2 * math.pi)
        cr.set_source_rgb(1, 1, 1)
        cr.fill()

    def _more_colours(self):
        dialog = Gtk.ColorChooserDialog(title="Choose a Colour", transient_for=self, modal=True)
        dialog.set_use_alpha(False)
        chosen = Gdk.RGBA()
        chosen.parse(self.colour)
        dialog.set_rgba(chosen)
        if dialog.run() == Gtk.ResponseType.OK:
            rgba = dialog.get_rgba()
            self.set_colour("#%02x%02x%02x" % (round(rgba.red * 255), round(rgba.green * 255),
                                                round(rgba.blue * 255)))
        dialog.destroy()

    def _size_chosen(self, _button, index):
        self.size = index
        for dot in self.size_dots:
            dot.queue_draw()

    def width(self, kind):
        return SIZES[kind][self.size]

    def _fill_changed(self, active):
        self.fill = bool(active)
        if self.fill_check.get_active() != self.fill:
            self.fill_check.set_active(self.fill)
        action = self.lookup_action("fill")
        if action and action.get_state().get_boolean() != self.fill:
            action.set_state(GLib.Variant("b", self.fill))

    # -- the list of drawings --

    def reload(self, choose=None):
        paths = drawings()
        if not paths:
            paths = [new_drawing()]
        choose = choose or self.path or paths[0]
        if choose not in paths:
            choose = paths[0]
        for row in self.list.get_children():
            self.list.remove(row)
        for path in paths:
            self.list.add(self._row(path))
        self.list.show_all()
        for row in self.list.get_children():
            if row.path == choose:
                self.list.select_row(row)

    def _row(self, path):
        row = Gtk.ListBoxRow()
        row.path = path
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        row.picture = Gtk.Image()
        row.label = Gtk.Label(xalign=0.5, ellipsize=Pango.EllipsizeMode.END)
        row.label.get_style_context().add_class("easel-thumb-name")
        box.pack_start(row.picture, False, False, 0)
        box.pack_start(row.label, False, False, 0)
        row.add(box)
        doc = load(path) or {"name": "Drawing", "paper": "white", "items": []}
        self._fill_row(row, doc)
        return row

    def _fill_row(self, row, doc, layer=None):
        surface = render(doc, 150 / WIDTH, layer)
        pixbuf = Gdk.pixbuf_get_from_surface(surface, 0, 0, surface.get_width(), surface.get_height())
        row.picture.set_from_pixbuf(pixbuf)
        row.label.set_text(doc["name"])

    def _current_row(self):
        for row in self.list.get_children():
            if row.path == self.path:
                return row
        return None

    def _row_selected(self, _list, row):
        if row is None or row.path == self.path:
            return
        self.flush()
        doc = load(row.path)
        if doc is None:
            return
        self.path, self.doc = row.path, doc
        self.undo, self.redo = [], []
        self.canvas.picked = None
        self.canvas.current = None
        self.header.set_subtitle(doc["name"])
        self._update_buttons()
        self.canvas.invalidate()

    def _list_pressed(self, _list, event):
        if event.button != 3:
            return False
        row = self.list.get_row_at_y(int(event.y))
        if row is None:
            return False
        self.list.select_row(row)
        menu = Gtk.Menu()
        for label, callback in (("Rename…", self.rename), ("Duplicate", self.duplicate),
                                (None, None), ("Move to Trash", self.trash_drawing)):
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if callback:
                item.connect("activate", lambda _i, c=callback: c())
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self.list, None)
        menu.popup_at_pointer(event)
        return True

    # -- changing the drawing --

    def _remember(self):
        self.undo.append((list(self.doc["items"]), self.doc["paper"]))
        del self.undo[:-200]
        self.redo.clear()

    def changed(self):
        self.canvas.invalidate()
        self._update_buttons()
        if self.save_timer:
            GLib.source_remove(self.save_timer)
        self.save_timer = GLib.timeout_add(500, self.flush)

    def add_item(self, item):
        self._remember()
        self.doc["items"].append(item)
        self.changed()

    def replace(self, index, item):
        self._remember()
        self.doc["items"][index] = item
        self.changed()

    def delete_picked(self):
        index = self.canvas.picked
        if index is None or self.doc is None or index >= len(self.doc["items"]):
            return
        self._remember()
        del self.doc["items"][index]
        self.canvas.picked = None
        self.changed()

    def clear(self):
        if self.doc and self.doc["items"]:
            self._remember()
            self.doc["items"] = []
            self.canvas.picked = None
            self.changed()

    def set_paper(self, key):
        if self.doc and self.doc["paper"] != key:
            self._remember()
            self.doc["paper"] = key
            self.changed()

    def do_undo(self):
        if self.undo:
            self.redo.append((list(self.doc["items"]), self.doc["paper"]))
            items, paper = self.undo.pop()
            self.doc["items"], self.doc["paper"] = list(items), paper
            self.canvas.picked = None
            self.changed()

    def do_redo(self):
        if self.redo:
            self.undo.append((list(self.doc["items"]), self.doc["paper"]))
            items, paper = self.redo.pop()
            self.doc["items"], self.doc["paper"] = list(items), paper
            self.canvas.picked = None
            self.changed()

    def _update_buttons(self):
        self.undo_button.set_sensitive(bool(self.undo))
        self.redo_button.set_sensitive(bool(self.redo))
        for name, enabled in (("undo", bool(self.undo)), ("redo", bool(self.redo))):
            action = self.lookup_action(name)
            if action:
                action.set_enabled(enabled)

    def flush(self):
        if self.save_timer:
            GLib.source_remove(self.save_timer)
            self.save_timer = 0
        if self.doc is not None and self.path:
            try:
                save(self.path, self.doc)
            except OSError:
                pass
            row = self._current_row()
            if row:
                layer = self.canvas.layer if self.canvas.drag_item is None else None
                self._fill_row(row, self.doc, layer)
        return False

    # -- text --

    def ask_text(self, px, py, event):
        if self.text_popover:
            self.text_popover.destroy()
        popover = Gtk.Popover(relative_to=self.canvas)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(event.x), int(event.y), 1, 1
        popover.set_pointing_to(rect)
        box = Gtk.Box(spacing=6)
        for side in ("start", "end", "top", "bottom"):
            getattr(box, f"set_margin_{side}")(8)
        entry = Gtk.Entry(placeholder_text="Type, then press Return", width_chars=28)
        box.add(entry)
        add = Gtk.Button(label="Add")
        add.get_style_context().add_class("suggested-action")
        box.add(add)
        popover.add(box)

        def done(*_a):
            text = entry.get_text().strip()
            if text:
                self.add_item({"kind": "text", "text": text, "size": self.width("text"), "color": self.colour,
                          "x": round(px), "y": round(py)})
            popover.popdown()

        entry.connect("activate", done)
        add.connect("clicked", done)
        popover.connect("closed", lambda p: GLib.idle_add(p.destroy))
        self.text_popover = popover
        popover.show_all()
        popover.popup()
        entry.grab_focus()

    # -- the drawing as a whole --

    def start_new(self):
        self.flush()
        path = new_drawing()
        self.reload(path)

    def duplicate(self):
        if self.doc is None:
            return
        self.flush()
        path = new_drawing()
        copy = json.loads(json.dumps(self.doc))
        copy["name"] = f"{self.doc['name']} copy"
        save(path, copy)
        self.reload(path)

    def rename(self):
        if self.doc is None:
            return
        dialog = Gtk.Dialog(title="Rename Drawing", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Rename", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        entry = Gtk.Entry(text=self.doc["name"], activates_default=True)
        area = dialog.get_content_area()
        for side in ("start", "end", "top", "bottom"):
            getattr(area, f"set_margin_{side}")(12)
        area.add(entry)
        dialog.show_all()
        answer = dialog.run()
        name = entry.get_text().strip()
        dialog.destroy()
        if answer == Gtk.ResponseType.OK and name:
            self.doc["name"] = name
            self.header.set_subtitle(name)
            self.flush()

    def trash_drawing(self):
        if self.path is None:
            return
        path = self.path
        self.flush()
        try:
            Gio.File.new_for_path(path).trash(None)
        except GLib.Error:
            try:
                os.remove(path)
            except OSError:
                return
        self.path, self.doc = None, None
        self.reload()

    def export(self):
        if self.doc is None:
            return
        dialog = Gtk.FileChooserNative.new("Export as Picture", self, Gtk.FileChooserAction.SAVE, "Export", None)
        dialog.set_do_overwrite_confirmation(True)
        pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) or GLib.get_home_dir()
        dialog.set_current_folder(pictures)
        dialog.set_current_name(f"{self.doc['name']}.png")
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            path = dialog.get_filename()
            if not path.lower().endswith(".png"):
                path += ".png"
            try:
                render(self.doc).write_to_png(path)
            except (OSError, cairo.Error) as error:
                self._problem("Easel couldn't save the picture.", str(error))
        dialog.destroy()

    def _problem(self, text, detail):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                                   buttons=Gtk.ButtonsType.OK, text=text, secondary_text=detail)
        dialog.connect("response", lambda d, _r: d.destroy())
        dialog.show()

    def _key(self, _w, event):
        if isinstance(self.get_focus(), Gtk.Entry):
            return False
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        if mods:
            return False
        if event.keyval in (Gdk.KEY_Delete, Gdk.KEY_BackSpace) and self.canvas.picked is not None:
            self.delete_picked()
            return True
        if event.keyval == Gdk.KEY_Escape and self.canvas.picked is not None:
            self.canvas.picked = None
            self.canvas.queue_draw()
            return True
        key = Gdk.keyval_name(Gdk.keyval_to_lower(event.keyval)) or ""
        for name, _tip, letter in TOOLS:
            if key == letter:
                self.choose_tool(name)
                return True
        return False

    def _closing(self, *_a):
        self.flush()


def menubar():
    return menus.menubar([
        ("_File", [[("New Drawing", "win.new", "<Ctrl>n"), ("Duplicate", "win.duplicate", None)],
                   [("Export as Picture…", "win.export", "<Ctrl>e")],
                   [("Rename…", "win.rename", None), ("Move to Trash", "win.trash", "<Ctrl>BackSpace")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Undo", "win.undo", "<Ctrl>z"), ("Redo", "win.redo", "<Shift><Ctrl>z")],
                   [("Delete Picked Thing", "win.delete-item", None), ("Clear Drawing", "win.clear", None)]]),
        ("_Format", [[("Fill Shapes", "win.fill", None)],
                     [(f"{label} Paper", f"win.paper-{key}", None) for key, (label, _c) in PAPERS.items()]]),
    ])


class Easel(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.new", "<Control>n"), ("win.close", "<Control>w"),
                             ("win.export", "<Control>e"), ("win.undo", "<Control>z"),
                             ("win.redo", "<Shift><Control>z"), ("win.trash", "<Control>BackSpace")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-easel")
    return Easel().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
