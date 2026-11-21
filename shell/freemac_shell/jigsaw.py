# SPDX-License-Identifier: GPL-3.0-or-later
"""Jigsaw: a jigsaw puzzle.

Pick a picture (one of freemac's own, or any photo) and how many pieces, and
the picture is cut into real-shaped pieces scattered round the table. Drag
pieces into the frame; pieces that belong together click into place when you
bring them close. A puzzle you leave is kept for next time in
~/.local/share/freemac/jigsaw.json.

Original freemac code: the piece shapes are drawn with freemac's own curves.
"""
import json
import math
import os
import random
import sys
import time

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Jigsaw"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "jigsaw.json")
BUILT_IN = "/usr/share/backgrounds/freemac"
PICTURE_TYPES = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff")
SIZES = (12, 24, 48, 100)
BOARD_W, BOARD_H = 1600.0, 1000.0     # the table, in its own units
FRAME_W, FRAME_H = 960.0, 620.0       # the largest the finished picture may be
SNAP = 20.0

# One edge's tab, as (along, out) points of cubic curves on an edge of length 1;
# "out" is measured in units of the shorter side of a piece.
TAB = (
    ((0.40, 0.0), (0.43, 0.05), (0.39, 0.11)),
    ((0.33, 0.21), (0.41, 0.29), (0.50, 0.29)),
    ((0.59, 0.29), (0.67, 0.21), (0.61, 0.11)),
    ((0.57, 0.05), (0.60, 0.0), (0.66, 0.0)),
)


def grid_for(count, aspect):
    """Columns and rows near count pieces, each piece close to square."""
    best = None
    for cols in range(2, 16):
        rows = max(2, min(15, round(cols / aspect)))
        score = abs(cols * rows - count) + abs((aspect * rows / cols) - 1) * 6
        if best is None or score < best[0]:
            best = (score, cols, rows)
    return best[1], best[2]


def built_in_pictures():
    found = []
    for folder in (BUILT_IN, GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) or ""):
        try:
            names = sorted(os.listdir(folder))
        except OSError:
            continue
        for name in names:
            if name.lower().endswith(PICTURE_TYPES) and not name.startswith("."):
                found.append(os.path.join(folder, name))
            if len(found) >= 18:
                return found
    return found


def edge(cr, ax, ay, bx, by, sign, depth):
    if not sign:
        cr.line_to(bx, by)
        return
    dx, dy = bx - ax, by - ay
    nx, ny = dy, -dx
    length = math.hypot(dx, dy) or 1
    nx, ny = nx / length * depth * sign, ny / length * depth * sign

    def at(t, n):
        return ax + dx * t + nx * n, ay + dy * t + ny * n

    cr.line_to(*at(0.34, 0))
    for c1, c2, end in TAB:
        cr.curve_to(*at(*c1), *at(*c2), *at(*end))
    cr.line_to(bx, by)


class Puzzle:
    """The cut picture and where every piece is."""

    def __init__(self, path, cols, rows, state=None):
        self.path = path
        self.cols, self.rows = cols, rows
        pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
        pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
        scale = min(FRAME_W / pixbuf.get_width(), FRAME_H / pixbuf.get_height())
        self.w, self.h = pixbuf.get_width() * scale, pixbuf.get_height() * scale
        self.pw, self.ph = self.w / cols, self.h / rows
        self.margin = math.ceil(min(self.pw, self.ph) * 0.32) + 3
        self.frame = ((BOARD_W - self.w) / 2, (BOARD_H - self.h) / 2)
        scaled = pixbuf.scale_simple(max(1, round(self.w)), max(1, round(self.h)), GdkPixbuf.InterpType.BILINEAR)
        self.image = cairo.ImageSurface(cairo.FORMAT_ARGB32, scaled.get_width(), scaled.get_height())
        cr = cairo.Context(self.image)
        Gdk.cairo_set_source_pixbuf(cr, scaled, 0, 0)
        cr.paint()
        if state:
            self.across, self.down = state["across"], state["down"]
            self.groups = state["groups"]
            self.seconds = state.get("seconds", 0)
        else:
            # +1: the tab sticks out right (across) or down (down)
            self.across = [[random.choice((-1, 1)) for _r in range(rows)] for _c in range(cols - 1)]
            self.down = [[random.choice((-1, 1)) for _r in range(rows - 1)] for _c in range(cols)]
            self.groups = []
            self.seconds = 0
            self.scatter(all_pieces=True)
        self.surfaces = {}
        self.started = time.monotonic()
        self.finished = self.done()

    # shape
    def sides(self, c, r):
        top = -self.down[c][r - 1] if r > 0 else 0
        right = self.across[c][r] if c < self.cols - 1 else 0
        bottom = self.down[c][r] if r < self.rows - 1 else 0
        left = -self.across[c - 1][r] if c > 0 else 0
        return top, right, bottom, left

    def outline(self, cr, c, r):
        pw, ph = self.pw, self.ph
        depth = min(pw, ph)
        top, right, bottom, left = self.sides(c, r)
        cr.new_path()
        cr.move_to(0, 0)
        edge(cr, 0, 0, pw, 0, top, depth)
        edge(cr, pw, 0, pw, ph, right, depth)
        edge(cr, pw, ph, 0, ph, bottom, depth)
        edge(cr, 0, ph, 0, 0, left, depth)
        cr.close_path()

    def surface(self, c, r):
        key = (c, r)
        if key not in self.surfaces:
            m = self.margin
            surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, math.ceil(self.pw + 2 * m), math.ceil(self.ph + 2 * m))
            cr = cairo.Context(surface)
            cr.translate(m, m)
            self.outline(cr, c, r)
            cr.save()
            cr.clip_preserve()
            cr.set_source_surface(self.image, -c * self.pw, -r * self.ph)
            cr.paint()
            cr.restore()
            cr.set_line_width(1.4)
            cr.set_source_rgba(1, 1, 1, 0.35)
            cr.stroke_preserve()
            cr.set_line_width(0.8)
            cr.set_source_rgba(0, 0, 0, 0.35)
            cr.stroke()
            self.surfaces[key] = surface
        return self.surfaces[key]

    def hits(self, c, r, x, y):
        """Is the point (relative to the piece's corner) on the piece?"""
        surface = self.surface(c, r)
        m = self.margin
        px, py = int(x + m), int(y + m)
        if not (0 <= px < surface.get_width() and 0 <= py < surface.get_height()):
            return False
        surface.flush()
        data = surface.get_data()
        return data[py * surface.get_stride() + px * 4 + 3] > 40

    # places
    def scatter(self, all_pieces=False):
        """Spread loose pieces round the frame (or every piece, at the start)."""
        fx, fy = self.frame
        spots = []
        step_x, step_y = self.pw * 1.25, self.ph * 1.25
        edge_gap = self.margin + 4
        y = edge_gap
        while y + self.ph < BOARD_H - edge_gap:
            x = edge_gap
            while x + self.pw < BOARD_W - edge_gap:
                inside = fx - self.pw * 0.9 < x < fx + self.w and fy - self.ph * 0.9 < y < fy + self.h
                if not inside:
                    spots.append((x, y))
                x += step_x
            y += step_y
        random.shuffle(spots)
        if all_pieces:
            pieces = [(c, r) for c in range(self.cols) for r in range(self.rows)]
            random.shuffle(pieces)
            self.groups = []
            for n, (c, r) in enumerate(pieces):
                sx, sy = spots[n % len(spots)] if spots else (random.uniform(0, BOARD_W), random.uniform(0, BOARD_H))
                sx += random.uniform(-6, 6)
                sy += random.uniform(-6, 6)
                self.groups.append({"pieces": [[c, r]], "x": sx - c * self.pw, "y": sy - r * self.ph,
                                    "placed": False})
        else:
            n = 0
            for group in self.groups:
                if group["placed"] or len(group["pieces"]) > 1:
                    continue
                c, r = group["pieces"][0]
                if spots:
                    sx, sy = spots[n % len(spots)]
                    group["x"], group["y"] = sx - c * self.pw, sy - r * self.ph
                    n += 1

    def group_at(self, x, y):
        for group in reversed(self.ordered()):
            if group["placed"]:
                continue
            for c, r in group["pieces"]:
                if self.hits(c, r, x - group["x"] - c * self.pw, y - group["y"] - r * self.ph):
                    return group
        return None

    def ordered(self):
        return [g for g in self.groups if g["placed"]] + [g for g in self.groups if not g["placed"]]

    def drop(self, group):
        """Join neighbours that are close and lock into the frame when close. True if it joined."""
        joined = False
        changed = True
        while changed:
            changed = False
            mine = {tuple(p) for p in group["pieces"]}
            for other in self.groups:
                if other is group:
                    continue
                theirs = {tuple(p) for p in other["pieces"]}
                touching = any((c + dc, r + dr) in theirs for c, r in mine
                               for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if touching and math.hypot(group["x"] - other["x"], group["y"] - other["y"]) < SNAP:
                    other["pieces"] += group["pieces"]
                    self.groups.remove(group)
                    group = other
                    joined = changed = True
                    break
        fx, fy = self.frame
        if not group["placed"] and math.hypot(group["x"] - fx, group["y"] - fy) < SNAP:
            group["x"], group["y"], group["placed"] = fx, fy, True
            joined = True
        if group["placed"]:
            # every placed group is part of the finished picture
            for other in [g for g in self.groups if g["placed"] and g is not group]:
                group["pieces"] += other["pieces"]
                self.groups.remove(other)
        return joined

    def raise_group(self, group):
        self.groups.remove(group)
        self.groups.append(group)

    def done(self):
        return len(self.groups) == 1 and self.groups[0]["placed"]

    def placed_count(self):
        return sum(len(g["pieces"]) for g in self.groups if g["placed"])

    def elapsed(self):
        if self.finished:
            return self.seconds
        return self.seconds + (time.monotonic() - self.started)

    def state(self):
        return {"path": self.path, "cols": self.cols, "rows": self.rows, "across": self.across,
                "down": self.down, "groups": self.groups, "seconds": int(self.elapsed())}


def valid_state(data):
    try:
        cols, rows = int(data["cols"]), int(data["rows"])
        if not (2 <= cols <= 20 and 2 <= rows <= 20 and isinstance(data["path"], str)):
            return False
        if len(data["across"]) != cols - 1 or any(len(a) != rows for a in data["across"]):
            return False
        if len(data["down"]) != cols or any(len(d) != rows - 1 for d in data["down"]):
            return False
        seen = set()
        for g in data["groups"]:
            float(g["x"]), float(g["y"]), bool(g["placed"])
            for c, r in g["pieces"]:
                if not (isinstance(c, int) and isinstance(r, int)) or not (0 <= c < cols and 0 <= r < rows) or (c, r) in seen:
                    return False
                seen.add((c, r))
        return len(seen) == cols * rows and os.path.isfile(data["path"])
    except (KeyError, TypeError, ValueError):
        return False


class Table(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(can_focus=True)
        self.window = window
        self.drag = None
        self.peek = False
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("button-release-event", self._release)
        self.connect("motion-notify-event", self._motion)

    def transform(self):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        scale = min(w / BOARD_W, h / BOARD_H)
        return scale, (w - BOARD_W * scale) / 2, (h - BOARD_H * scale) / 2

    def to_board(self, x, y):
        scale, ox, oy = self.transform()
        return (x - ox) / scale, (y - oy) / scale

    def _press(self, _w, event):
        puzzle = self.window.puzzle
        if event.button != 1 or not puzzle or puzzle.done():
            return False
        bx, by = self.to_board(event.x, event.y)
        group = puzzle.group_at(bx, by)
        if group:
            puzzle.raise_group(group)
            self.drag = (group, bx - group["x"], by - group["y"])
            self.get_window().set_cursor(Gdk.Cursor.new_from_name(self.get_display(), "grabbing"))
            self.queue_draw()
        return True

    def _motion(self, _w, event):
        if not self.drag:
            puzzle = self.window.puzzle
            if puzzle and not puzzle.done():
                bx, by = self.to_board(event.x, event.y)
                name = "grab" if puzzle.group_at(bx, by) else None
                self.get_window().set_cursor(Gdk.Cursor.new_from_name(self.get_display(), name) if name else None)
            return False
        if not event.state & Gdk.ModifierType.BUTTON1_MASK:
            self._release(None, None)
            return False
        group, dx, dy = self.drag
        bx, by = self.to_board(event.x, event.y)
        bx = max(0.0, min(BOARD_W, bx))
        by = max(0.0, min(BOARD_H, by))
        group["x"], group["y"] = bx - dx, by - dy
        self.queue_draw()
        return True

    def _release(self, _w, _event):
        if not self.drag:
            return False
        group = self.drag[0]
        self.drag = None
        if self.get_window():
            self.get_window().set_cursor(None)
        puzzle = self.window.puzzle
        if group in puzzle.groups and puzzle.drop(group):
            self.window.clicked()
        self.window.moved()
        self.queue_draw()
        return True

    def _draw(self, _w, cr):
        dark = self.get_style_context().lookup_color("theme_bg_color")[1].red < 0.5
        cr.set_source_rgb(*((0.16, 0.2, 0.19) if dark else (0.36, 0.5, 0.45)))
        cr.paint()
        puzzle = self.window.puzzle
        if not puzzle:
            return
        scale, ox, oy = self.transform()
        cr.translate(ox, oy)
        cr.scale(scale, scale)
        # the frame the picture goes in
        fx, fy = puzzle.frame
        cr.rectangle(fx, fy, puzzle.w, puzzle.h)
        cr.set_source_rgba(0, 0, 0, 0.22)
        cr.fill_preserve()
        if self.peek:
            cr.save()
            cr.clip_preserve()
            cr.set_source_surface(puzzle.image, fx, fy)
            cr.paint_with_alpha(0.28)
            cr.restore()
        cr.set_source_rgba(1, 1, 1, 0.3)
        cr.set_line_width(2)
        cr.stroke()
        if puzzle.finished:
            cr.set_source_surface(puzzle.image, fx, fy)
            cr.paint()
            return
        m = puzzle.margin
        dragging = self.drag[0] if self.drag else None
        for group in puzzle.ordered():
            lifted = group is dragging
            for c, r in group["pieces"]:
                surface = puzzle.surface(c, r)
                x = group["x"] + c * puzzle.pw - m
                y = group["y"] + r * puzzle.ph - m
                if not group["placed"]:
                    cr.set_source_rgba(0, 0, 0, 0.35 if lifted else 0.25)
                    cr.mask_surface(surface, x + (4 if lifted else 1.5), y + (6 if lifted else 2.5))
                cr.set_source_surface(surface, x, y)
                cr.paint()


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Jigsaw")
        self.set_default_size(1160, 760)
        self.puzzle = None
        self.save_pending = None

        header = Gtk.HeaderBar(show_close_button=True, title="Jigsaw")
        self.set_titlebar(header)
        new = Gtk.Button(label="New Puzzle…")
        new.set_action_name("win.new")
        header.pack_start(new)
        self.peek_button = Gtk.ToggleButton(label="Peek")
        self.peek_button.set_tooltip_text("Show the picture faintly in the frame")
        self.peek_button.connect("toggled", self._peek)
        header.pack_start(self.peek_button)
        spread = Gtk.Button(label="Spread Out")
        spread.set_action_name("win.spread")
        spread.set_tooltip_text("Spread the loose pieces out round the frame")
        header.pack_start(spread)
        self.progress = Gtk.Label()
        self.clock = Gtk.Label()
        self.clock.get_style_context().add_class("dim-label")
        header.pack_end(self.clock)
        header.pack_end(self.progress)

        overlay = Gtk.Overlay()
        self.add(overlay)
        self.table = Table(self)
        overlay.add(self.table)
        self.banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                              halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.banner.get_style_context().add_class("jigsaw-banner")
        self.banner_title = Gtk.Label()
        self.banner_title.set_markup("<span size='20000' weight='700'>Well done!</span>")
        self.banner_text = Gtk.Label(justify=Gtk.Justification.CENTER)
        again = Gtk.Button(label="New Puzzle…")
        again.get_style_context().add_class("suggested-action")
        again.set_halign(Gtk.Align.CENTER)
        again.set_action_name("win.new")
        for widget in (self.banner_title, self.banner_text, again):
            self.banner.pack_start(widget, False, False, 0)
        self.banner.set_no_show_all(True)
        self.banner.set_margin_bottom(40)
        self.banner.set_valign(Gtk.Align.END)
        overlay.add_overlay(self.banner)
        css = Gtk.CssProvider()
        css.load_from_data(b".jigsaw-banner { background-color: alpha(@theme_bg_color, 0.96); border-radius: 16px;"
                           b" padding: 20px 40px; box-shadow: 0 8px 30px alpha(black, 0.3); }")
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        menus.add_actions(self, {"new": self.choose, "spread": self.spread, "close": self.close,
                                 "peek": lambda: self.peek_button.set_active(not self.peek_button.get_active())})
        self.connect("delete-event", lambda *_a: self.save() and False)
        self.show_all()
        if not self.resume():
            pictures = built_in_pictures()
            if pictures:
                self.start(pictures[0], 24)
        GLib.timeout_add_seconds(1, self._tick)

    # games
    def resume(self):
        try:
            with open(STORE) as f:
                data = json.load(f)
        except (OSError, ValueError):
            return False
        if not isinstance(data, dict) or not valid_state(data):
            return False
        try:
            self.puzzle = Puzzle(data["path"], int(data["cols"]), int(data["rows"]), state=data)
        except (GLib.Error, KeyError, TypeError, ValueError):
            self.puzzle = None
            return False
        self.after_start()
        return True

    def start(self, path, count):
        try:
            info, width, height = GdkPixbuf.Pixbuf.get_file_info(path)
        except (GLib.Error, TypeError):
            info = None
        if not info:
            self.problem(path)
            return
        cols, rows = grid_for(count, width / max(1, height))
        try:
            self.puzzle = Puzzle(path, cols, rows)
        except GLib.Error:
            self.problem(path)
            return
        self.after_start()
        self.save()

    def problem(self, path):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                                   buttons=Gtk.ButtonsType.OK,
                                   text=f"Jigsaw can't open “{os.path.basename(path)}”.")
        dialog.format_secondary_text("Try another picture.")
        dialog.run()
        dialog.destroy()

    def after_start(self):
        self.banner.hide()
        self.peek_button.set_active(False)
        self.lookup_action("spread").set_enabled(True)
        self.update_progress()
        self.table.queue_draw()
        if self.puzzle.done():
            self.won(quiet=True)

    def spread(self):
        if self.puzzle and not self.puzzle.done():
            self.puzzle.scatter()
            self.table.queue_draw()
            self.moved()

    def _peek(self, button):
        self.table.peek = button.get_active()
        self.table.queue_draw()

    def clicked(self):
        self.update_progress()
        if self.puzzle.done():
            self.won()

    def moved(self):
        if self.save_pending:
            GLib.source_remove(self.save_pending)
        self.save_pending = GLib.timeout_add(800, self.save)

    def save(self):
        if self.save_pending:
            GLib.source_remove(self.save_pending)
            self.save_pending = None
        if self.puzzle:
            os.makedirs(os.path.dirname(STORE), exist_ok=True)
            tmp = STORE + ".tmp"
            try:
                with open(tmp, "w") as f:
                    json.dump(self.puzzle.state(), f)
                os.replace(tmp, STORE)
            except OSError:
                pass
        return False

    def won(self, quiet=False):
        puzzle = self.puzzle
        if not puzzle.finished:
            puzzle.seconds = int(puzzle.elapsed())
            puzzle.finished = True
        minutes, seconds = divmod(puzzle.seconds, 60)
        self.banner_text.set_text(f"All {puzzle.cols * puzzle.rows} pieces in {minutes}:{seconds:02d}.")
        for child in self.banner.get_children():
            child.show()
        self.banner.show()
        self.lookup_action("spread").set_enabled(False)
        self.peek_button.set_active(False)
        self.update_progress()
        self.save()

    def update_progress(self):
        puzzle = self.puzzle
        if puzzle:
            total = puzzle.cols * puzzle.rows
            self.progress.set_text(f"{puzzle.placed_count()} of {total} in place")
        self._tick()

    def _tick(self):
        puzzle = self.puzzle
        if puzzle:
            seconds = int(puzzle.elapsed())
            minutes, seconds = divmod(seconds, 60)
            self.clock.set_text(f"{minutes}:{seconds:02d}")
        return True

    # choosing a picture
    def choose(self):
        dialog = Gtk.Dialog(title="New Puzzle", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Start", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        dialog.set_default_size(720, 520)
        box = dialog.get_content_area()
        box.set_border_width(14)
        box.set_spacing(10)
        heading = Gtk.Label(xalign=0)
        heading.set_markup("<b>Choose a picture</b>")
        box.pack_start(heading, False, False, 0)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_vexpand(True)
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.SINGLE, max_children_per_line=4,
                           homogeneous=True, row_spacing=8, column_spacing=8)
        flow.set_valign(Gtk.Align.START)
        scroller.add(flow)
        box.pack_start(scroller, True, True, 0)

        def add_thumb(path, select=False):
            try:
                thumb = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 150, 100, True)
            except GLib.Error:
                return
            image = Gtk.Image.new_from_pixbuf(thumb)
            image.set_size_request(156, 104)
            image.path = path
            child = Gtk.FlowBoxChild()
            child.add(image)
            child.path = path
            child.show_all()
            flow.add(child)
            if select:
                flow.select_child(child)

        current = self.puzzle.path if self.puzzle else None
        paths = built_in_pictures()
        if current and current not in paths:
            paths.insert(0, current)
        for path in paths:
            add_thumb(path, select=(path == current))
        if not flow.get_selected_children() and flow.get_child_at_index(0):
            flow.select_child(flow.get_child_at_index(0))
        flow.connect("child-activated", lambda _f, _c: dialog.response(Gtk.ResponseType.OK))

        def browse(_b):
            chooser = Gtk.FileChooserNative.new("Choose a Photo", dialog, Gtk.FileChooserAction.OPEN, "Choose",
                                                "Cancel")
            only = Gtk.FileFilter()
            only.set_name("Pictures")
            only.add_pixbuf_formats()
            chooser.add_filter(only)
            pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
            if pictures and os.path.isdir(pictures):
                chooser.set_current_folder(pictures)
            if chooser.run() == Gtk.ResponseType.ACCEPT:
                add_thumb(chooser.get_filename(), select=True)
            chooser.destroy()

        row = Gtk.Box(spacing=10)
        other = Gtk.Button(label="Choose a Photo…")
        other.connect("clicked", browse)
        row.pack_start(other, False, False, 0)
        row.pack_end(self._pieces_buttons(), False, False, 0)
        row.pack_end(Gtk.Label(label="Pieces:"), False, False, 0)
        box.pack_start(row, False, False, 0)
        dialog.show_all()
        chosen = [c for c in flow.get_children() if c.path == current]
        if chosen:
            GLib.idle_add(lambda: flow.select_child(chosen[0]) and False)
        if dialog.run() == Gtk.ResponseType.OK and flow.get_selected_children():
            path = flow.get_selected_children()[0].path
            dialog.destroy()
            self.save()
            self.start(path, self.piece_count)
        else:
            dialog.destroy()

    def _pieces_buttons(self):
        box = Gtk.Box()
        box.get_style_context().add_class("linked")
        if not hasattr(self, "piece_count"):
            total = self.puzzle.cols * self.puzzle.rows if self.puzzle else 24
            self.piece_count = min(SIZES, key=lambda s: abs(s - total))
        group = None
        for size in SIZES:
            button = Gtk.RadioButton.new_with_label_from_widget(group, str(size))
            button.set_mode(False)
            group = group or button
            button.set_active(size == self.piece_count)
            button.connect("toggled", lambda b, s=size: b.get_active() and setattr(self, "piece_count", s))
            box.pack_start(button, False, False, 0)
        return box

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Jigsaw")
        dialog.format_secondary_text("Jigsaw cuts pictures into puzzles. It is part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_Game", [[("New Puzzle…", "win.new", "<Ctrl>n")],
                   [("Peek at the Picture", "win.peek", "<Ctrl>p"), ("Spread Out Pieces", "win.spread", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
    ])


class Jigsaw(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close(),
                                 "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_accels_for_action("win.new", ["<Control>n"])
        self.set_accels_for_action("win.peek", ["<Control>p"])
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-jigsaw")
    return Jigsaw().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
