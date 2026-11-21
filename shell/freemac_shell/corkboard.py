# SPDX-License-Identifier: GPL-3.0-or-later
"""Corkboard: a big board for ideas.

Put sticky notes, text, shapes, lines, arrows and pictures anywhere on a board
that goes on as far as you like. Drag things to move them, pull the corner to
resize them, and double-click to write in them. Keep as many boards as you
like; each is saved as you go in ~/.local/share/freemac/corkboard/.

Original freemac code and drawing.
"""
import json
import math
import os
import shutil
import sys
import uuid

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, spelling, style  # noqa: E402

APP_ID = "org.freemac.Corkboard"
HOME = os.path.join(GLib.get_user_data_dir(), "freemac", "corkboard")
INDEX = os.path.join(HOME, "boards.json")
IMAGES = os.path.join(HOME, "pictures")
IMAGE_TYPES = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".tif", ".tiff")

# name: (pastel for notes, strong for lines, shapes and text)
COLOURS = {
    "yellow": ((1.0, 0.9, 0.54), (0.86, 0.65, 0.0)),
    "orange": ((1.0, 0.8, 0.58), (1.0, 0.55, 0.0)),
    "pink": ((1.0, 0.75, 0.82), (0.94, 0.27, 0.52)),
    "purple": ((0.85, 0.78, 1.0), (0.6, 0.36, 0.87)),
    "blue": ((0.68, 0.85, 1.0), (0.04, 0.49, 1.0)),
    "green": ((0.74, 0.92, 0.65), (0.2, 0.68, 0.3)),
    "gray": ((0.88, 0.88, 0.9), (0.45, 0.46, 0.5)),
    "black": ((0.8, 0.8, 0.82), (0.1, 0.1, 0.12)),
}
BOXES = ("note", "text", "rect", "oval", "image")
LINES = ("line", "arrow")
HANDLE = 7          # half the size of a resize handle, in screen pixels
MIN_SIZE = 24


def new_id():
    return uuid.uuid4().hex[:10]


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, path)
    except OSError:
        pass


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def rounded(cr, x, y, w, h, r):
    r = max(0, min(r, w / 2, h / 2))
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def segment_distance(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    length = dx * dx + dy * dy
    t = 0 if length == 0 else max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / length))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))


def clean_item(item):
    """Keep only well-formed items from a saved board."""
    if not isinstance(item, dict) or item.get("kind") not in BOXES + LINES:
        return None
    out = {"id": str(item.get("id") or new_id()), "kind": item["kind"],
           "colour": item.get("colour") if item.get("colour") in COLOURS else "yellow",
           "text": item.get("text") if isinstance(item.get("text"), str) else ""}
    keys = ("x1", "y1", "x2", "y2") if item["kind"] in LINES else ("x", "y", "w", "h")
    for key in keys:
        value = item.get(key)
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            return None
        out[key] = float(value)
    if item["kind"] in BOXES and (out["w"] < 1 or out["h"] < 1):
        return None
    if item["kind"] == "image":
        name = item.get("picture")
        if not isinstance(name, str) or os.path.basename(name) != name:
            return None
        out["picture"] = name
    return out


class Board:
    def __init__(self, board_id, name):
        self.id = board_id
        self.name = name
        self.items = []
        self.view = (0.0, 0.0, 1.0)
        self.loaded = False

    @property
    def path(self):
        return os.path.join(HOME, self.id + ".json")

    def load(self):
        data = read_json(self.path)
        data = data if isinstance(data, dict) else {}
        raw_items = data.get("items") if isinstance(data.get("items"), list) else []
        self.items = [i for i in (clean_item(raw) for raw in raw_items) if i]
        view = data.get("view")
        if isinstance(view, list) and len(view) == 3 and all(isinstance(v, (int, float)) for v in view) \
                and 0.1 <= view[2] <= 8:
            self.view = tuple(float(v) for v in view)
        self.loaded = True

    def save(self):
        if self.loaded:
            write_json(self.path, {"items": self.items, "view": list(self.view)})


class Canvas(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(can_focus=True)
        self.window = window
        self.board = None
        self.selected = None
        self.press = None          # what a drag is doing
        self.pictures = {}         # file name -> pixbuf (or None when it can't be read)
        self.editing = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.SCROLL_MASK
                        | Gdk.EventMask.SMOOTH_SCROLL_MASK | Gdk.EventMask.KEY_PRESS_MASK)
        self.fit_when_shown = False
        self.connect("draw", self._draw)
        self.connect("size-allocate", self._allocated)
        self.connect("button-press-event", self._press)
        self.connect("button-release-event", self._release)
        self.connect("motion-notify-event", self._motion)
        self.connect("scroll-event", self._scroll)
        self.connect("key-press-event", self._key)
        self.drag_dest_set(Gtk.DestDefaults.ALL, [], Gdk.DragAction.COPY)
        self.drag_dest_add_uri_targets()
        self.drag_dest_add_text_targets()
        self.connect("drag-data-received", self._dropped)
        zoom = Gtk.GestureZoom.new(self)
        zoom.connect("begin", self._pinch_begin)
        zoom.connect("scale-changed", self._pinch)
        self.zoom_gesture = zoom
        self.pinch_from = None

    def _allocated(self, _w, allocation):
        if self.fit_when_shown and allocation.width > 50:
            self.fit_when_shown = False
            GLib.idle_add(lambda: self.fit() and False)

    # view
    @property
    def view(self):
        return self.board.view if self.board else (0.0, 0.0, 1.0)

    def set_view(self, ox, oy, z):
        if self.board:
            self.board.view = (ox, oy, max(0.1, min(8.0, z)))
            self.window.changed(undoable=False)
            self.window.update_zoom()
            self.queue_draw()

    def to_board(self, sx, sy):
        ox, oy, z = self.view
        return (sx - ox) / z, (sy - oy) / z

    def to_screen(self, bx, by):
        ox, oy, z = self.view
        return bx * z + ox, by * z + oy

    def centre(self):
        return self.to_board(self.get_allocated_width() / 2, self.get_allocated_height() / 2)

    def zoom_by(self, factor, around=None):
        ox, oy, z = self.view
        if around is None:
            around = (self.get_allocated_width() / 2, self.get_allocated_height() / 2)
        bx, by = self.to_board(*around)
        nz = max(0.1, min(8.0, z * factor))
        self.set_view(around[0] - bx * nz, around[1] - by * nz, nz)

    def actual_size(self):
        bx, by = self.centre()
        self.set_view(self.get_allocated_width() / 2 - bx, self.get_allocated_height() / 2 - by, 1.0)

    def fit(self):
        if self.get_allocated_width() < 50:
            GLib.timeout_add(100, lambda: self.fit() and False)
            return
        if not (self.board and self.board.items):
            self.set_view(self.get_allocated_width() / 2, self.get_allocated_height() / 2, 1.0)
            return
        x0, y0, x1, y1 = bounds(self.board.items)
        w, h = self.get_allocated_width(), self.get_allocated_height()
        z = max(0.1, min(2.0, min((w - 80) / max(1, x1 - x0), (h - 80) / max(1, y1 - y0))))
        self.set_view(w / 2 - (x0 + x1) / 2 * z, h / 2 - (y0 + y1) / 2 * z, z)

    def _pinch_begin(self, _gesture, _seq):
        self.pinch_from = self.view[2]

    def _pinch(self, gesture, factor):
        if self.pinch_from:
            ok, x, y = gesture.get_bounding_box_center()
            target = self.pinch_from * factor
            self.zoom_by(target / self.view[2], (x, y) if ok else None)

    # finding things
    def item_at(self, sx, sy):
        if not self.board:
            return None
        bx, by = self.to_board(sx, sy)
        z = self.view[2]
        for item in reversed(self.board.items):
            if item["kind"] in LINES:
                if segment_distance(bx, by, item["x1"], item["y1"], item["x2"], item["y2"]) <= 7 / z:
                    return item
            elif item["x"] <= bx <= item["x"] + item["w"] and item["y"] <= by <= item["y"] + item["h"]:
                if item["kind"] == "oval":
                    cx, cy = item["x"] + item["w"] / 2, item["y"] + item["h"] / 2
                    if ((bx - cx) / (item["w"] / 2)) ** 2 + ((by - cy) / (item["h"] / 2)) ** 2 > 1.05:
                        continue
                return item
        return None

    def handle_at(self, sx, sy):
        """'corner', 'end1', 'end2' or None for the selected item."""
        item = self.selected
        if not item:
            return None
        if item["kind"] in LINES:
            for name, (x, y) in (("end1", (item["x1"], item["y1"])), ("end2", (item["x2"], item["y2"]))):
                hx, hy = self.to_screen(x, y)
                if abs(sx - hx) <= HANDLE + 3 and abs(sy - hy) <= HANDLE + 3:
                    return name
            return None
        hx, hy = self.to_screen(item["x"] + item["w"], item["y"] + item["h"])
        if abs(sx - hx) <= HANDLE + 3 and abs(sy - hy) <= HANDLE + 3:
            return "corner"
        return None

    def select(self, item):
        self.selected = item
        self.window.update_selection()
        self.queue_draw()

    # mouse
    def _press(self, _w, event):
        self.grab_focus()
        if not self.board:
            return False
        if event.type == Gdk.EventType._2BUTTON_PRESS and event.button == 1:
            item = self.item_at(event.x, event.y)
            if item and item["kind"] in ("note", "text", "rect", "oval"):
                self.press = None
                self.edit(item)
            elif not item:
                bx, by = self.to_board(event.x, event.y)
                self.edit(self.window.add_item("note", at=(bx, by)))
            return True
        if event.type != Gdk.EventType.BUTTON_PRESS:
            return True
        if event.button == 3:
            item = self.item_at(event.x, event.y)
            self.select(item)
            self.window.context_menu(event, item)
            return True
        handle = self.handle_at(event.x, event.y) if event.button == 1 else None
        item = None if handle else self.item_at(event.x, event.y)
        before = json.dumps(self.board.items)
        if handle:
            self.press = {"mode": handle, "start": (event.x, event.y), "item": dict(self.selected),
                          "before": before}
        elif item and event.button == 1:
            self.select(item)
            self.press = {"mode": "move", "start": (event.x, event.y), "item": dict(item), "before": before}
        else:
            if event.button == 1:
                self.select(None)
            self.press = {"mode": "pan", "start": (event.x, event.y), "view": self.view}
            self.get_window().set_cursor(Gdk.Cursor.new_from_name(self.get_display(), "grabbing"))
        return True

    def _motion(self, _w, event):
        if not self.press:
            handle = self.handle_at(event.x, event.y)
            name = {"corner": "nwse-resize", "end1": "crosshair", "end2": "crosshair"}.get(handle)
            if not name and self.item_at(event.x, event.y):
                name = "move"
            window = self.get_window()
            if window:
                window.set_cursor(Gdk.Cursor.new_from_name(self.get_display(), name) if name else None)
            return False
        buttons = Gdk.ModifierType.BUTTON1_MASK | Gdk.ModifierType.BUTTON2_MASK | Gdk.ModifierType.BUTTON3_MASK
        if not event.state & buttons:
            # the release went elsewhere (a popover or menu took it)
            self._release(None, None)
            return False
        sx0, sy0 = self.press["start"]
        z = self.view[2]
        dx, dy = (event.x - sx0) / z, (event.y - sy0) / z
        mode = self.press["mode"]
        if mode == "pan":
            ox, oy, z = self.press["view"]
            self.board.view = (ox + event.x - sx0, oy + event.y - sy0, z)
            self.queue_draw()
            return True
        item, old = self.selected, self.press["item"]
        if not item:
            return True
        if mode == "move":
            if item["kind"] in LINES:
                for key, d in (("x1", dx), ("y1", dy), ("x2", dx), ("y2", dy)):
                    item[key] = old[key] + d
            else:
                item["x"], item["y"] = old["x"] + dx, old["y"] + dy
        elif mode == "corner":
            w, h = max(MIN_SIZE, old["w"] + dx), max(MIN_SIZE, old["h"] + dy)
            if item["kind"] == "image" or event.state & Gdk.ModifierType.SHIFT_MASK:
                ratio = old["w"] / max(1e-6, old["h"])
                h = w / ratio
            item["w"], item["h"] = w, h
        elif mode in ("end1", "end2"):
            n = mode[-1]
            item["x" + n], item["y" + n] = old["x" + n] + dx, old["y" + n] + dy
        self.queue_draw()
        return True

    def _release(self, _w, _event):
        press, self.press = self.press, None
        if not press:
            return False
        if press["mode"] == "pan":
            if self.get_window():
                self.get_window().set_cursor(None)
            self.window.changed(undoable=False)
        elif json.dumps(self.board.items) != press["before"]:
            self.window.push_undo(press["before"])
            self.window.changed()
        return True

    def _scroll(self, _w, event):
        if not self.board:
            return False
        ctrl = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD4_MASK)
        if event.direction == Gdk.ScrollDirection.SMOOTH:
            ok, dx, dy = event.get_scroll_deltas()
            if not ok:
                return False
        else:
            dx, dy = {Gdk.ScrollDirection.UP: (0, -1), Gdk.ScrollDirection.DOWN: (0, 1),
                      Gdk.ScrollDirection.LEFT: (-1, 0), Gdk.ScrollDirection.RIGHT: (1, 0)}[event.direction]
        if ctrl:
            self.zoom_by(1.0015 ** (-dy * 60), (event.x, event.y))
        else:
            ox, oy, z = self.view
            if event.state & Gdk.ModifierType.SHIFT_MASK:
                dx, dy = dy, 0
            self.set_view(ox - dx * 40, oy - dy * 40, z)
        return True

    def _key(self, _w, event):
        key = event.keyval
        if not self.selected:
            if key == Gdk.KEY_Escape:
                return True
            return False
        if key in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self.window.delete_selected()
            return True
        if key == Gdk.KEY_Escape:
            self.select(None)
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and self.selected["kind"] in ("note", "text", "rect", "oval"):
            self.edit(self.selected)
            return True
        moves = {Gdk.KEY_Left: (-1, 0), Gdk.KEY_Right: (1, 0), Gdk.KEY_Up: (0, -1), Gdk.KEY_Down: (0, 1)}
        if key in moves:
            step = 10 if event.state & Gdk.ModifierType.SHIFT_MASK else 1
            self.window.push_undo()
            dx, dy = moves[key][0] * step, moves[key][1] * step
            item = self.selected
            for kx, ky in ((("x1", "y1"), ("x2", "y2")) if item["kind"] in LINES else (("x", "y"),)):
                item[kx] += dx
                item[ky] += dy
            self.window.changed()
            self.queue_draw()
            return True
        return False

    def _dropped(self, _w, _ctx, x, y, data, _info, _time):
        bx, by = self.to_board(x, y)
        uris = data.get_uris()
        if uris:
            for n, uri in enumerate(uris):
                path = Gio.File.new_for_uri(uri).get_path()
                if path and path.lower().endswith(IMAGE_TYPES):
                    self.window.add_picture(path, at=(bx + n * 24, by + n * 24))
            return
        text = data.get_text()
        if text and text.strip():
            item = self.window.add_item("note", at=(bx, by))
            item["text"] = text.strip()[:2000]
            self.window.changed()

    # writing in things
    def edit(self, item):
        if not item:
            return
        if self.press:
            self._release(None, None)
        self.select(item)
        sx, sy = self.to_screen(item["x"], item["y"])
        z = self.view[2]
        rect = Gdk.Rectangle()
        rect.x, rect.y = int(sx), int(sy)
        rect.width, rect.height = max(1, int(item["w"] * z)), max(1, int(item["h"] * z))
        popover = Gtk.Popover(relative_to=self)
        popover.set_pointing_to(rect)
        popover.set_position(Gtk.PositionType.BOTTOM)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_border_width(8)
        scroller = Gtk.ScrolledWindow()
        scroller.set_size_request(300, 140)
        scroller.set_shadow_type(Gtk.ShadowType.IN)
        view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=6, right_margin=6,
                            top_margin=6, bottom_margin=6)
        spelling.attach(view)
        view.get_buffer().set_text(item["text"])
        scroller.add(view)
        hint = Gtk.Label(label="Click outside to finish.", xalign=0)
        hint.get_style_context().add_class("dim-label")
        box.pack_start(scroller, True, True, 0)
        box.pack_start(hint, False, False, 0)
        popover.add(box)
        before = json.dumps(self.board.items)
        board = self.board

        def typed(buffer):
            item["text"] = buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False)
            self.queue_draw()

        def done(_p):
            self.editing = None
            if board is self.board:
                if item["kind"] == "text" and not item["text"].strip() and item in board.items:
                    board.items.remove(item)
                    if self.selected is item:
                        self.select(None)
                if json.dumps(board.items) != before:
                    self.window.push_undo(before)
                    self.window.changed()
            self.queue_draw()
            self.grab_focus()
            GLib.idle_add(popover.destroy)

        view.get_buffer().connect("changed", typed)
        popover.connect("closed", done)
        popover.show_all()
        view.grab_focus()
        self.editing = popover

    # drawing
    def picture(self, name):
        if name not in self.pictures:
            try:
                self.pictures[name] = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    os.path.join(IMAGES, name), 1600, 1600, True)
            except GLib.Error:
                self.pictures[name] = None
        return self.pictures[name]

    def _draw(self, _w, cr):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        dark = self.get_style_context().lookup_color("theme_bg_color")[1].red < 0.5
        bg = (0.15, 0.15, 0.17) if dark else (0.97, 0.97, 0.96)
        cr.set_source_rgb(*bg)
        cr.paint()
        if not self.board:
            return
        ox, oy, z = self.view
        # dot grid
        spacing = 24 * z
        while spacing < 14:
            spacing *= 2
        cr.set_source_rgba(*((1, 1, 1) if dark else (0, 0, 0)), 0.13)
        x = ox % spacing
        while x < w:
            y = oy % spacing
            while y < h:
                cr.rectangle(x - 0.9, y - 0.9, 1.8, 1.8)
                y += spacing
            x += spacing
        cr.fill()
        cr.save()
        cr.translate(ox, oy)
        cr.scale(z, z)
        draw_items(cr, self.board.items, self.picture, dark)
        cr.restore()
        if not self.board.items:
            layout = PangoCairo.create_layout(cr)
            layout.set_font_description(Pango.FontDescription.from_string("Inter 13"))
            layout.set_alignment(Pango.Alignment.CENTER)
            layout.set_width(int(min(w - 40, 440) * Pango.SCALE))
            layout.set_wrap(Pango.WrapMode.WORD)
            layout.set_text("This board is empty.\nAdd a note, text, a shape or a picture with the buttons "
                            "at the top, double-click anywhere for a note, or drop a picture here.", -1)
            tw, th = layout.get_pixel_size()
            cr.set_source_rgba(*((1, 1, 1) if dark else (0, 0, 0)), 0.45)
            cr.move_to((w - tw) / 2, (h - th) / 2)
            PangoCairo.show_layout(cr, layout)
        item = self.selected
        if item and item in self.board.items:
            cr.set_source_rgb(0.04, 0.49, 1.0)
            cr.set_line_width(2)
            if item["kind"] in LINES:
                points = [self.to_screen(item["x1"], item["y1"]), self.to_screen(item["x2"], item["y2"])]
            else:
                sx, sy = self.to_screen(item["x"], item["y"])
                cr.rectangle(sx - 3, sy - 3, item["w"] * z + 6, item["h"] * z + 6)
                cr.stroke()
                points = [self.to_screen(item["x"] + item["w"], item["y"] + item["h"])]
            for px, py in points:
                cr.rectangle(px - HANDLE + 1, py - HANDLE + 1, 2 * HANDLE - 2, 2 * HANDLE - 2)
                cr.set_source_rgb(1, 1, 1)
                cr.fill_preserve()
                cr.set_source_rgb(0.04, 0.49, 1.0)
                cr.stroke()


def bounds(items):
    xs, ys = [], []
    for item in items:
        if item["kind"] in LINES:
            xs += [item["x1"], item["x2"]]
            ys += [item["y1"], item["y2"]]
        else:
            xs += [item["x"], item["x"] + item["w"]]
            ys += [item["y"], item["y"] + item["h"]]
    return min(xs), min(ys), max(xs), max(ys)


def draw_text(cr, item, size, colour, centre=False, pad=12):
    if not item["text"]:
        return
    layout = PangoCairo.create_layout(cr)
    layout.set_font_description(Pango.FontDescription.from_string(f"Inter {size}"))
    layout.set_width(int(max(1, item["w"] - 2 * pad) * Pango.SCALE))
    layout.set_wrap(Pango.WrapMode.WORD_CHAR)
    layout.set_ellipsize(Pango.EllipsizeMode.END)
    layout.set_height(int(max(1, item["h"] - 2 * pad) * Pango.SCALE))
    if centre:
        layout.set_alignment(Pango.Alignment.CENTER)
    layout.set_text(item["text"], -1)
    _tw, th = layout.get_pixel_size()
    y = item["y"] + (item["h"] - th) / 2 if centre else item["y"] + pad
    cr.set_source_rgb(*colour)
    cr.move_to(item["x"] + pad, y)
    PangoCairo.show_layout(cr, layout)


def draw_items(cr, items, picture, dark=False):
    ink = (0.92, 0.92, 0.94) if dark else (0.1, 0.1, 0.12)
    for item in items:
        cr.new_path()
        kind = item["kind"]
        pastel, strong = COLOURS.get(item["colour"], COLOURS["yellow"])
        if kind == "note":
            x, y, w, h = item["x"], item["y"], item["w"], item["h"]
            cr.set_source_rgba(0, 0, 0, 0.16)
            rounded(cr, x + 1, y + 4, w, h, 4)
            cr.fill()
            cr.set_source_rgb(*pastel)
            rounded(cr, x, y, w, h, 4)
            cr.fill()
            cr.set_source_rgba(0, 0, 0, 0.06)
            cr.rectangle(x, y, w, min(18, h / 6))
            cr.fill()
            draw_text(cr, item, 14, (0.12, 0.12, 0.14), pad=14)
        elif kind == "text":
            colour = ink if item["colour"] in ("black", "yellow") else strong
            draw_text(cr, item, 20, colour, pad=4)
        elif kind in ("rect", "oval"):
            x, y, w, h = item["x"], item["y"], item["w"], item["h"]
            if kind == "rect":
                rounded(cr, x, y, w, h, 10)
            else:
                cr.save()
                cr.translate(x + w / 2, y + h / 2)
                cr.scale(w / 2, h / 2)
                cr.arc(0, 0, 1, 0, 2 * math.pi)
                cr.restore()
            cr.set_source_rgba(*strong, 0.16)
            cr.fill_preserve()
            cr.set_source_rgb(*strong)
            cr.set_line_width(3)
            cr.stroke()
            draw_text(cr, item, 16, ink, centre=True)
        elif kind == "image":
            pixbuf = picture(item.get("picture", ""))
            x, y, w, h = item["x"], item["y"], item["w"], item["h"]
            cr.set_source_rgba(0, 0, 0, 0.14)
            cr.rectangle(x + 1, y + 3, w, h)
            cr.fill()
            if pixbuf:
                cr.save()
                cr.rectangle(x, y, w, h)
                cr.clip()
                cr.translate(x, y)
                cr.scale(w / pixbuf.get_width(), h / pixbuf.get_height())
                Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
                cr.paint()
                cr.restore()
            else:
                cr.set_source_rgb(0.85, 0.85, 0.87)
                cr.rectangle(x, y, w, h)
                cr.fill()
        elif kind in LINES:
            x1, y1, x2, y2 = item["x1"], item["y1"], item["x2"], item["y2"]
            cr.set_source_rgb(*strong)
            cr.set_line_width(3)
            cr.set_line_cap(1)
            angle = math.atan2(y2 - y1, x2 - x1)
            end_x, end_y = x2, y2
            if kind == "arrow":
                end_x, end_y = x2 - 10 * math.cos(angle), y2 - 10 * math.sin(angle)
            cr.move_to(x1, y1)
            cr.line_to(end_x, end_y)
            cr.stroke()
            if kind == "arrow":
                size = 16
                cr.move_to(x2, y2)
                cr.line_to(x2 - size * math.cos(angle - 0.45), y2 - size * math.sin(angle - 0.45))
                cr.line_to(x2 - size * math.cos(angle + 0.45), y2 - size * math.sin(angle + 0.45))
                cr.close_path()
                cr.fill()


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Corkboard")
        self.set_default_size(1120, 720)
        self.boards = []
        self.undo, self.redo = [], []
        self.save_pending = None
        self.colour = "yellow"

        header = Gtk.HeaderBar(show_close_button=True, title="Corkboard")
        self.set_titlebar(header)
        tools = Gtk.Box(spacing=4)
        for label, action, tip in (("Note", "win.add-note", "Add a sticky note"),
                                   ("Text", "win.add-text", "Add text")):
            button = Gtk.Button(label=label)
            button.set_action_name(action)
            button.set_tooltip_text(tip)
            tools.pack_start(button, False, False, 0)
        shapes = Gio.Menu()
        for label, action in (("Rectangle", "win.add-rect"), ("Oval", "win.add-oval"),
                              ("Line", "win.add-line"), ("Arrow", "win.add-arrow")):
            shapes.append(label, action)
        shape_button = Gtk.MenuButton(label="Shape", menu_model=shapes)
        shape_button.set_tooltip_text("Add a shape, a line or an arrow")
        tools.pack_start(shape_button, False, False, 0)
        picture = Gtk.Button(label="Picture")
        picture.set_action_name("win.add-picture")
        picture.set_tooltip_text("Add a picture")
        tools.pack_start(picture, False, False, 0)
        self.colour_button = Gtk.MenuButton()
        self.colour_button.set_tooltip_text("Colour")
        self.swatch = Gtk.DrawingArea()
        self.swatch.set_size_request(18, 18)
        self.swatch.connect("draw", lambda a, cr: self._draw_swatch(a, cr, self.colour))
        self.colour_button.add(self.swatch)
        self.colour_button.set_popover(self._colour_popover())
        tools.pack_start(self.colour_button, False, False, 0)
        header.pack_start(tools)
        self.zoom_label = Gtk.Label(label="100%")
        self.zoom_label.set_width_chars(5)
        zoom_box = Gtk.Box()
        zoom_box.get_style_context().add_class("linked")
        for text, action, tip in (("−", "win.zoom-out", "Zoom out"), ("+", "win.zoom-in", "Zoom in")):
            button = Gtk.Button(label=text)
            button.set_action_name(action)
            button.set_tooltip_text(tip)
            button.set_size_request(34, -1)
            zoom_box.pack_start(button, False, False, 0)
        header.pack_end(zoom_box)
        header.pack_end(self.zoom_label)

        body = Gtk.Box()
        self.add(body)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.set_size_request(210, -1)
        side.set_hexpand(False)
        title = Gtk.Label(label="BOARDS", xalign=0)
        title.get_style_context().add_class("dim-label")
        title.set_margin_start(14)
        title.set_margin_top(12)
        title.set_margin_bottom(6)
        side.pack_start(title, False, False, 0)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.list = Gtk.ListBox()
        self.list.get_style_context().add_class("sidebar")
        self.list.connect("row-selected", self._board_chosen)
        scroller.add(self.list)
        side.pack_start(scroller, True, True, 0)
        add_board = Gtk.Button(label="New Board")
        add_board.set_action_name("win.new-board")
        add_board.set_margin_start(10)
        add_board.set_margin_end(10)
        add_board.set_margin_bottom(10)
        add_board.set_margin_top(6)
        side.pack_start(add_board, False, False, 0)
        body.pack_start(side, False, False, 0)
        body.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        self.canvas = Canvas(self)
        body.pack_start(self.canvas, True, True, 0)

        menus.add_actions(self, {
            "add-note": lambda: self.canvas.edit(self.add_item("note")),
            "add-text": lambda: self.canvas.edit(self.add_item("text")),
            "add-rect": lambda: self.add_item("rect"), "add-oval": lambda: self.add_item("oval"),
            "add-line": lambda: self.add_item("line"), "add-arrow": lambda: self.add_item("arrow"),
            "add-picture": self.choose_picture, "edit-text": lambda: self.canvas.edit(self.canvas.selected),
            "delete": self.delete_selected, "duplicate": self.duplicate, "undo": self.do_undo,
            "redo": self.do_redo, "front": lambda: self.restack(True), "back": lambda: self.restack(False),
            "zoom-in": lambda: self.canvas.zoom_by(1.25), "zoom-out": lambda: self.canvas.zoom_by(0.8),
            "actual-size": self.canvas.actual_size, "fit": self.canvas.fit,
            "new-board": self.new_board, "rename-board": self.rename_board, "delete-board": self.delete_board,
            "export": self.export_picture, "close": self.close,
        })
        for name in COLOURS:
            menus.add_actions(self, {"colour-" + name: (lambda n=name: self.set_colour(n))})
        self.connect("delete-event", lambda *_a: self.flush() and False)
        self.load_boards()
        self.show_all()
        self.update_selection()

    # boards
    def load_boards(self):
        data = read_json(INDEX) or {}
        for entry in data.get("boards", []) if isinstance(data.get("boards"), list) else []:
            if isinstance(entry, dict) and isinstance(entry.get("id"), str) and entry["id"].isalnum() \
                    and isinstance(entry.get("name"), str):
                self.boards.append(Board(entry["id"], entry["name"][:80] or "Untitled"))
        if not self.boards:
            self.boards.append(Board(new_id(), "My Board"))
            self.boards[0].loaded = True
            self.save_index()
        for board in self.boards:
            self.list.add(self._row(board))
        last = data.get("last")
        index = next((i for i, b in enumerate(self.boards) if b.id == last), 0)
        self.list.select_row(self.list.get_row_at_index(index))

    def _row(self, board):
        row = Gtk.ListBoxRow()
        label = Gtk.Label(label=board.name, xalign=0, ellipsize=Pango.EllipsizeMode.END)
        label.set_margin_start(14)
        label.set_margin_end(10)
        label.set_margin_top(7)
        label.set_margin_bottom(7)
        row.add(label)
        row.board = board
        row.show_all()
        return row

    def save_index(self):
        board = self.canvas.board if hasattr(self, "canvas") else None
        write_json(INDEX, {"boards": [{"id": b.id, "name": b.name} for b in self.boards],
                           "last": board.id if board else None})

    def _board_chosen(self, _list, row):
        if not row:
            return
        self.flush()
        if self.canvas.editing:
            self.canvas.editing.popdown()
        board = row.board
        if not board.loaded:
            board.load()
        self.canvas.board = board
        self.canvas.selected = None
        self.undo, self.redo = [], []
        self.set_title(board.name)
        self.get_titlebar().set_title(board.name)
        self.save_index()
        self.update_selection()
        self.update_zoom()
        if board.view == (0.0, 0.0, 1.0):
            if self.canvas.get_mapped():
                self.canvas.fit()
            else:
                self.canvas.fit_when_shown = True
        self.canvas.queue_draw()

    def new_board(self):
        names = {b.name for b in self.boards}
        n = 1
        name = "Untitled Board"
        while name in names:
            n += 1
            name = f"Untitled Board {n}"
        board = Board(new_id(), name)
        board.loaded = True
        self.boards.append(board)
        row = self._row(board)
        self.list.add(row)
        self.list.select_row(row)
        board.save()
        self.save_index()
        self.rename_board()

    def rename_board(self):
        board = self.canvas.board
        if not board:
            return
        dialog = Gtk.Dialog(title="Rename Board", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Rename", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        entry = Gtk.Entry(text=board.name, activates_default=True)
        entry.set_max_length(80)
        box = dialog.get_content_area()
        box.set_border_width(14)
        box.set_spacing(8)
        box.pack_start(Gtk.Label(label="Name of this board:", xalign=0), False, False, 0)
        box.pack_start(entry, False, False, 0)
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK and entry.get_text().strip():
            board.name = entry.get_text().strip()
            row = self.list.get_selected_row()
            if row:
                row.get_child().set_text(board.name)
            self.set_title(board.name)
            self.get_titlebar().set_title(board.name)
            self.save_index()
        dialog.destroy()

    def delete_board(self):
        board = self.canvas.board
        if not board:
            return
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                                   buttons=Gtk.ButtonsType.NONE, text=f"Delete the board “{board.name}”?")
        dialog.format_secondary_text("Its notes and pictures go to the Bin, where you can get them back.")
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Delete", Gtk.ResponseType.OK)
        answer = dialog.run()
        dialog.destroy()
        if answer != Gtk.ResponseType.OK:
            return
        self.flush()
        for path in [board.path] + [os.path.join(IMAGES, i["picture"]) for i in board.items
                                    if i["kind"] == "image" and not self.picture_used_elsewhere(i["picture"], board)]:
            if os.path.exists(path):
                try:
                    Gio.File.new_for_path(path).trash(None)
                except GLib.Error:
                    pass
        row = self.list.get_selected_row()
        index = self.boards.index(board)
        self.boards.remove(board)
        self.canvas.board = None
        if row:
            self.list.remove(row)
        if not self.boards:
            fresh = Board(new_id(), "My Board")
            fresh.loaded = True
            self.boards.append(fresh)
            self.list.add(self._row(fresh))
        self.list.select_row(self.list.get_row_at_index(min(index, len(self.boards) - 1)))
        self.save_index()

    def picture_used_elsewhere(self, name, board):
        for other in self.boards:
            if other is board:
                continue
            if not other.loaded:
                other.load()
            if any(i.get("picture") == name for i in other.items):
                return True
        return False

    # changes
    def push_undo(self, snapshot=None):
        board = self.canvas.board
        if not board:
            return
        self.undo.append(snapshot if snapshot is not None else json.dumps(board.items))
        del self.undo[:-100]
        self.redo.clear()
        self.update_selection()

    def _restore(self, snapshot):
        board = self.canvas.board
        board.items = [i for i in (clean_item(x) for x in json.loads(snapshot)) if i]
        selected = self.canvas.selected
        self.canvas.selected = next((i for i in board.items if selected and i["id"] == selected["id"]), None)
        self.changed(undoable=False)
        self.update_selection()
        self.canvas.queue_draw()

    def do_undo(self):
        if self.undo and self.canvas.board:
            self.redo.append(json.dumps(self.canvas.board.items))
            self._restore(self.undo.pop())

    def do_redo(self):
        if self.redo and self.canvas.board:
            self.undo.append(json.dumps(self.canvas.board.items))
            self._restore(self.redo.pop())

    def changed(self, undoable=True):
        if self.save_pending:
            GLib.source_remove(self.save_pending)
        self.save_pending = GLib.timeout_add(500, self.flush)

    def flush(self):
        if self.save_pending:
            GLib.source_remove(self.save_pending)
            self.save_pending = None
        if self.canvas.board:
            self.canvas.board.save()
        return False

    def update_selection(self):
        item = self.canvas.selected
        for name in ("delete", "duplicate", "front", "back"):
            self.lookup_action(name).set_enabled(bool(item))
        self.lookup_action("edit-text").set_enabled(bool(item and item["kind"] in ("note", "text", "rect", "oval")))
        self.lookup_action("undo").set_enabled(bool(self.undo))
        self.lookup_action("redo").set_enabled(bool(self.redo))
        for name in ("rename-board", "delete-board", "export"):
            self.lookup_action(name).set_enabled(self.canvas.board is not None)
        if item:
            self.colour = item["colour"]
            self.swatch.queue_draw()

    def update_zoom(self):
        self.zoom_label.set_text(f"{round(self.canvas.view[2] * 100)}%")

    # adding things
    def place(self, w, h, at=None):
        bx, by = at if at else self.canvas.centre()
        if not at:
            # step new things down and to the right so they don't stack exactly
            board = self.canvas.board
            for _ in range(20):
                if any(i.get("x") == bx - w / 2 and i.get("y") == by - h / 2 for i in board.items):
                    bx, by = bx + 24, by + 24
        return bx - w / 2, by - h / 2

    def add_item(self, kind, at=None):
        board = self.canvas.board
        if not board:
            return None
        self.push_undo()
        colour = self.colour
        if kind == "note":
            x, y = self.place(200, 180, at)
            item = {"kind": kind, "x": x, "y": y, "w": 200, "h": 180}
        elif kind == "text":
            x, y = self.place(260, 60, at)
            item = {"kind": kind, "x": x, "y": y, "w": 260, "h": 60}
            colour = "black" if colour == "yellow" else colour
        elif kind in ("rect", "oval"):
            x, y = self.place(180, 120, at)
            item = {"kind": kind, "x": x, "y": y, "w": 180, "h": 120}
            colour = "blue" if colour == "yellow" else colour
        else:
            x, y = self.place(200, 0, at)
            item = {"kind": kind, "x1": x, "y1": y + 60, "x2": x + 200, "y2": y - 20}
            colour = "black" if colour == "yellow" else colour
        item.update(id=new_id(), colour=colour, text="")
        board.items.append(item)
        self.canvas.select(item)
        self.changed()
        self.canvas.grab_focus()
        return item

    def add_picture(self, path, at=None):
        board = self.canvas.board
        if not board:
            return
        try:
            info, width, height = GdkPixbuf.Pixbuf.get_file_info(path)
        except (GLib.Error, TypeError):
            info = None
        if not info or not width or not height:
            return
        os.makedirs(IMAGES, exist_ok=True)
        ext = os.path.splitext(path)[1].lower()
        name = new_id() + ext
        try:
            shutil.copyfile(path, os.path.join(IMAGES, name))
        except OSError:
            return
        scale = min(1.0, 360 / width, 360 / height)
        w, h = max(MIN_SIZE, width * scale), max(MIN_SIZE, height * scale)
        x, y = self.place(w, h, at)
        self.push_undo()
        item = {"id": new_id(), "kind": "image", "x": x, "y": y, "w": w, "h": h, "colour": "gray",
                "text": "", "picture": name}
        board.items.append(item)
        self.canvas.select(item)
        self.changed()

    def choose_picture(self):
        chooser = Gtk.FileChooserNative.new("Add a Picture", self, Gtk.FileChooserAction.OPEN, "Add", "Cancel")
        chooser.set_select_multiple(True)
        pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
        if pictures and os.path.isdir(pictures):
            chooser.set_current_folder(pictures)
        only = Gtk.FileFilter()
        only.set_name("Pictures")
        only.add_pixbuf_formats()
        chooser.add_filter(only)
        if chooser.run() == Gtk.ResponseType.ACCEPT:
            for n, path in enumerate(chooser.get_filenames()):
                bx, by = self.canvas.centre()
                self.add_picture(path, at=(bx + n * 30, by + n * 30))
        chooser.destroy()

    # editing things
    def delete_selected(self):
        item, board = self.canvas.selected, self.canvas.board
        if item and board and item in board.items:
            self.push_undo()
            board.items.remove(item)
            self.canvas.select(None)
            self.changed()

    def duplicate(self):
        item, board = self.canvas.selected, self.canvas.board
        if not (item and board):
            return
        self.push_undo()
        copy = dict(item, id=new_id())
        for key in ("x", "x1", "x2", "y", "y1", "y2"):
            if key in copy:
                copy[key] += 24
        board.items.append(copy)
        self.canvas.select(copy)
        self.changed()

    def restack(self, front):
        item, board = self.canvas.selected, self.canvas.board
        if item and board:
            self.push_undo()
            board.items.remove(item)
            if front:
                board.items.append(item)
            else:
                board.items.insert(0, item)
            self.changed()
            self.canvas.queue_draw()

    def set_colour(self, name):
        self.colour = name
        self.swatch.queue_draw()
        item = self.canvas.selected
        if item and item["colour"] != name:
            self.push_undo()
            item["colour"] = name
            self.changed()
            self.canvas.queue_draw()
        self.colour_button.get_popover().popdown()

    def _draw_swatch(self, area, cr, name, pastel=False):
        size = min(area.get_allocated_width(), area.get_allocated_height())
        colour = COLOURS[name][0 if name == "yellow" or pastel else 1]
        cr.arc(area.get_allocated_width() / 2, area.get_allocated_height() / 2, size / 2 - 1, 0, 2 * math.pi)
        cr.set_source_rgb(*colour)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.25)
        cr.set_line_width(1)
        cr.stroke()

    def _colour_popover(self):
        popover = Gtk.Popover()
        grid = Gtk.Grid(column_spacing=6, row_spacing=6)
        grid.set_border_width(8)
        for n, name in enumerate(COLOURS):
            button = Gtk.Button()
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.set_tooltip_text(name.capitalize())
            swatch = Gtk.DrawingArea()
            swatch.set_size_request(24, 24)
            swatch.connect("draw", lambda a, cr, nm=name: self._draw_swatch(a, cr, nm))
            button.add(swatch)
            button.set_action_name("win.colour-" + name)
            grid.attach(button, n % 4, n // 4, 1, 1)
        grid.show_all()
        popover.add(grid)
        return popover

    def context_menu(self, event, item):
        menu = Gio.Menu()
        if item:
            first = Gio.Menu()
            if item["kind"] in ("note", "text", "rect", "oval"):
                first.append("Edit Text", "win.edit-text")
            first.append("Duplicate", "win.duplicate")
            menu.append_section(None, first)
            order = Gio.Menu()
            order.append("Bring to Front", "win.front")
            order.append("Send to Back", "win.back")
            menu.append_section(None, order)
            last = Gio.Menu()
            last.append("Delete", "win.delete")
            menu.append_section(None, last)
        else:
            add = Gio.Menu()
            for label, action in (("Add Note", "win.add-note"), ("Add Text", "win.add-text"),
                                  ("Add Picture…", "win.add-picture")):
                add.append(label, action)
            menu.append_section(None, add)
        popup = Gtk.Menu.new_from_model(menu)
        popup.attach_to_widget(self.canvas, None)
        popup.popup_at_pointer(event)

    def export_picture(self):
        board = self.canvas.board
        if not board or not board.items:
            return
        chooser = Gtk.FileChooserNative.new("Export as Picture", self, Gtk.FileChooserAction.SAVE, "Export",
                                            "Cancel")
        chooser.set_current_name(board.name + ".png")
        chooser.set_do_overwrite_confirmation(True)
        pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
        if pictures and os.path.isdir(pictures):
            chooser.set_current_folder(pictures)
        if chooser.run() == Gtk.ResponseType.ACCEPT:
            path = chooser.get_filename()
            if not path.lower().endswith(".png"):
                path += ".png"
            import cairo
            x0, y0, x1, y1 = bounds(board.items)
            margin = 40
            w, h = int(x1 - x0 + 2 * margin), int(y1 - y0 + 2 * margin)
            scale = min(1.0, 8000 / max(w, h))
            surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, max(1, int(w * scale)), max(1, int(h * scale)))
            cr = cairo.Context(surface)
            cr.set_source_rgb(0.97, 0.97, 0.96)
            cr.paint()
            cr.scale(scale, scale)
            cr.translate(margin - x0, margin - y0)
            draw_items(cr, board.items, self.canvas.picture)
            surface.write_to_png(path)
        chooser.destroy()

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK,
                                   text="About Corkboard")
        dialog.format_secondary_text("Corkboard is a big board for notes, shapes and pictures. "
                                     "It is part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_File", [[("New Board", "win.new-board", "<Ctrl><Shift>n")],
                   [("Rename Board…", "win.rename-board", None), ("Delete Board…", "win.delete-board", None)],
                   [("Export as Picture…", "win.export", "<Ctrl><Shift>e")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Undo", "win.undo", "<Ctrl>z"), ("Redo", "win.redo", "<Ctrl><Shift>z")],
                   [("Edit Text", "win.edit-text", None), ("Duplicate", "win.duplicate", "<Ctrl>d"),
                    ("Delete", "win.delete", None)]]),
        ("_Insert", [[("Sticky Note", "win.add-note", "<Ctrl>n"), ("Text", "win.add-text", "<Ctrl>t")],
                     [("Rectangle", "win.add-rect", None), ("Oval", "win.add-oval", None),
                      ("Line", "win.add-line", None), ("Arrow", "win.add-arrow", None)],
                     [("Picture…", "win.add-picture", "<Ctrl><Shift>i")]]),
        ("_Arrange", [[("Bring to Front", "win.front", "<Ctrl><Shift>f"),
                       ("Send to Back", "win.back", "<Ctrl><Shift>b")]]),
        ("_View", [[("Zoom In", "win.zoom-in", "<Ctrl>plus"), ("Zoom Out", "win.zoom-out", "<Ctrl>minus"),
                    ("Actual Size", "win.actual-size", "<Ctrl>0"), ("Zoom to Fit", "win.fit", "<Ctrl>9")]]),
    ])


class Corkboard(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close(),
                                 "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.new-board", "<Control><Shift>n"), ("win.export", "<Control><Shift>e"),
                             ("win.close", "<Control>w"), ("win.undo", "<Control>z"),
                             ("win.redo", "<Control><Shift>z"), ("win.duplicate", "<Control>d"),
                             ("win.add-note", "<Control>n"), ("win.add-text", "<Control>t"),
                             ("win.add-picture", "<Control><Shift>i"), ("win.front", "<Control><Shift>f"),
                             ("win.back", "<Control><Shift>b"), ("win.zoom-in", "<Control>plus"),
                             ("win.zoom-out", "<Control>minus"), ("win.actual-size", "<Control>0"),
                             ("win.fit", "<Control>9")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-corkboard")
    return Corkboard().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
