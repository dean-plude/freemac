# SPDX-License-Identifier: GPL-3.0-or-later
"""Markup for Frame: drawing, boxes, text and a signature on a picture or a
PDF page, kept as marks (plain data) in the picture's own pixels and drawn
with cairo, on screen and into the saved copy.

A mark is a dict:
    {"kind": "ink",  "color": (r, g, b), "width": w, "points": [(x, y), ...]}
    {"kind": "box",  "color": (r, g, b), "width": w, "rect": (x, y, w, h)}
    {"kind": "text", "color": (r, g, b), "size": s, "x": x, "y": y, "text": "..."}
    {"kind": "sign", "color": (r, g, b), "width": w, "x": x, "y": y, "w": w,
     "strokes": [[(u, v), ...], ...]}   (u, v from 0 to 1 across the signature)

Signatures are drawn once on a pad and kept in
~/.local/share/freemac/signatures.json. Original freemac code.
"""
import json
import math
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, Gtk, Pango, PangoCairo  # noqa: E402

COLORS = [("Red", (0.90, 0.22, 0.20)), ("Blue", (0.16, 0.45, 0.92)), ("Green", (0.18, 0.62, 0.32)),
          ("Yellow", (0.98, 0.78, 0.10)), ("Black", (0.08, 0.08, 0.09))]
INK = (0.08, 0.10, 0.30)   # signatures: dark blue ink


def signatures_path():
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data, "freemac", "signatures.json")


def load_signatures():
    try:
        with open(signatures_path()) as f:
            found = json.load(f)
        return [s for s in found if isinstance(s, dict) and s.get("strokes")]
    except (OSError, ValueError):
        return []


def save_signatures(signatures):
    path = signatures_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".new", "w") as f:
        json.dump(signatures, f)
    os.replace(path + ".new", path)


def line_width(width, height):
    """A pen width that looks the same on any size of picture."""
    return max(2.0, max(width, height) / 350)


# -- drawing ----------------------------------------------------------------
def _smooth(cr, points):
    if len(points) == 1:
        x, y = points[0]
        cr.move_to(x, y)
        cr.line_to(x + 0.01, y)
        return
    cr.move_to(*points[0])
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        cr.curve_to(x0, y0, x0, y0, (x0 + x1) / 2, (y0 + y1) / 2)
    cr.line_to(*points[-1])


def text_layout(cr, mark):
    layout = PangoCairo.create_layout(cr)
    font = Pango.FontDescription("Sans")
    font.set_absolute_size(mark["size"] * Pango.SCALE)
    layout.set_font_description(font)
    layout.set_text(mark["text"], -1)
    return layout


def sign_height(mark):
    """A signature's height, from its width and the shape it was drawn in."""
    return mark["w"] * mark.get("aspect", 0.4)


def draw_mark(cr, mark):
    cr.save()
    cr.set_source_rgb(*mark["color"])
    cr.set_line_cap(1)   # round
    cr.set_line_join(1)
    kind = mark["kind"]
    if kind == "ink":
        cr.set_line_width(mark["width"])
        _smooth(cr, mark["points"])
        cr.stroke()
    elif kind == "box":
        cr.set_line_width(mark["width"])
        x, y, w, h = mark["rect"]
        cr.rectangle(x, y, w, h)
        cr.stroke()
    elif kind == "text":
        cr.move_to(mark["x"], mark["y"])
        PangoCairo.show_layout(cr, text_layout(cr, mark))
    elif kind == "sign":
        cr.set_line_width(mark["width"])
        w, h = mark["w"], sign_height(mark)
        for stroke in mark["strokes"]:
            _smooth(cr, [(mark["x"] + u * w, mark["y"] + v * h) for u, v in stroke])
            cr.stroke()
    cr.restore()


def draw_marks(cr, marks):
    for mark in marks:
        draw_mark(cr, mark)


def bounds(mark, cr=None):
    """(x, y, w, h) around a mark."""
    kind = mark["kind"]
    if kind == "ink":
        xs = [p[0] for p in mark["points"]]
        ys = [p[1] for p in mark["points"]]
        pad = mark["width"]
        return min(xs) - pad, min(ys) - pad, max(xs) - min(xs) + 2 * pad, max(ys) - min(ys) + 2 * pad
    if kind == "box":
        x, y, w, h = mark["rect"]
        return x, y, w, h
    if kind == "text":
        width = len(mark["text"]) * mark["size"] * 0.6
        if cr is not None:
            ink, logical = text_layout(cr, mark).get_pixel_extents()
            width = logical.width
        return mark["x"], mark["y"], width, mark["size"] * 1.3
    return mark["x"], mark["y"], mark["w"], sign_height(mark)


def hit(marks, x, y, slack, cr=None):
    """The topmost mark at (x, y), or None."""
    for mark in reversed(marks):
        bx, by, bw, bh = bounds(mark, cr)
        if mark["kind"] == "box":
            inside = bx - slack <= x <= bx + bw + slack and by - slack <= y <= by + bh + slack
            near_edge = min(abs(x - bx), abs(x - bx - bw), abs(y - by), abs(y - by - bh)) <= slack
            if inside and near_edge:
                return mark
        elif mark["kind"] == "ink":
            for px, py in mark["points"]:
                if math.hypot(px - x, py - y) <= slack + mark["width"]:
                    return mark
        elif bx - slack <= x <= bx + bw + slack and by - slack <= y <= by + bh + slack:
            return mark
    return None


def move(mark, dx, dy):
    kind = mark["kind"]
    if kind == "ink":
        mark["points"] = [(x + dx, y + dy) for x, y in mark["points"]]
    elif kind == "box":
        x, y, w, h = mark["rect"]
        mark["rect"] = (x + dx, y + dy, w, h)
    else:
        mark["x"] += dx
        mark["y"] += dy


def outline(cr, mark, scale):
    """The dashed frame shown around the chosen mark."""
    x, y, w, h = bounds(mark, cr)
    pad = 4 / scale
    cr.save()
    cr.set_source_rgba(0.16, 0.45, 0.92, 0.9)
    cr.set_line_width(1.5 / scale)
    cr.set_dash([4 / scale, 3 / scale])
    cr.rectangle(x - pad, y - pad, w + 2 * pad, h + 2 * pad)
    cr.stroke()
    cr.restore()


# -- the signature pad ------------------------------------------------------
class SignaturePad(Gtk.Dialog):
    """Draw a signature with the trackpad or mouse; Done keeps it."""

    def __init__(self, parent):
        super().__init__(title="New Signature", transient_for=parent, modal=True, use_header_bar=True)
        self.set_default_size(520, 300)
        self.add_button("Cancel", Gtk.ResponseType.CANCEL)
        self.add_button("Done", Gtk.ResponseType.OK)
        self.set_default_response(Gtk.ResponseType.OK)
        self.get_widget_for_response(Gtk.ResponseType.OK).get_style_context().add_class("suggested-action")
        self.strokes = []
        box = self.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)
        hint = Gtk.Label(label="Sign your name on the line with the trackpad or mouse.")
        hint.get_style_context().add_class("dim-label")
        box.pack_start(hint, False, False, 0)
        self.area = Gtk.DrawingArea()
        self.area.set_size_request(480, 190)
        self.area.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_MOTION_MASK
                             | Gdk.EventMask.BUTTON_RELEASE_MASK)
        self.area.connect("draw", self._draw)
        self.area.connect("button-press-event", self._press)
        self.area.connect("motion-notify-event", self._motion)
        box.pack_start(self.area, True, True, 0)
        clear = Gtk.Button(label="Clear", halign=Gtk.Align.START)
        clear.connect("clicked", lambda *_: (self.strokes.clear(), self.area.queue_draw()))
        box.pack_start(clear, False, False, 0)
        self.show_all()

    def _press(self, _w, event):
        self.strokes.append([(event.x, event.y)])
        self.area.queue_draw()

    def _motion(self, _w, event):
        if self.strokes:
            self.strokes[-1].append((event.x, event.y))
            self.area.queue_draw()

    def _draw(self, area, cr):
        w, h = area.get_allocated_width(), area.get_allocated_height()
        cr.set_source_rgb(1, 1, 1)
        cr.rectangle(0, 0, w, h)
        cr.fill()
        cr.set_source_rgba(0, 0, 0, 0.25)
        cr.set_line_width(1)
        cr.move_to(24, h - 40)
        cr.line_to(w - 24, h - 40)
        cr.stroke()
        cr.set_source_rgb(*INK)
        cr.set_line_width(3)
        cr.set_line_cap(1)
        cr.set_line_join(1)
        for stroke in self.strokes:
            _smooth(cr, stroke)
            cr.stroke()
        return False

    def signature(self):
        """The strokes fitted to a box from 0 to 1, with the box's shape:
        (strokes, aspect), or None if nothing was drawn."""
        points = [p for s in self.strokes for p in s]
        if len(points) < 3:
            return None
        x0, y0 = min(p[0] for p in points), min(p[1] for p in points)
        w = max(max(p[0] for p in points) - x0, 1)
        h = max(max(p[1] for p in points) - y0, 1)
        strokes = [[(round((x - x0) / w, 4), round((y - y0) / h, 4)) for x, y in s] for s in self.strokes]
        return {"strokes": strokes, "aspect": round(h / w, 4)}


def ask_signature(parent):
    """Show the pad; the new signature, saved for next time, or None."""
    pad = SignaturePad(parent)
    answer = pad.run()
    signature = pad.signature() if answer == Gtk.ResponseType.OK else None
    pad.destroy()
    if signature:
        saved = load_signatures()
        save_signatures([signature] + saved[:4])
    return signature
