# SPDX-License-Identifier: GPL-3.0-or-later
"""Tangram: the seven-piece shape puzzle.

Slide and turn two large triangles, a medium triangle, two small triangles, a
square and a parallelogram until together they fill the dark outline. Click
a piece to turn it, right-click the parallelogram to flip it, and ask for a
hint when stuck. The outlines are freemac's own, and every one was checked
to be solvable (each comes with a solution, which the hint uses).

Shapes live on a grid whose unit is the short side of a small triangle; an
outline is a set of quarter cells (each grid square cut along both
diagonals), which makes checking a finished puzzle exact. Original freemac
code.
"""
import json
import math
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Tangram"
SAVE = os.path.join(GLib.get_user_data_dir(), "freemac", "tangram.json")
BOARD_W, BOARD_H = 1000, 640
UNIT = 62
R2 = math.sqrt(2)
SHAPES = {
    "large": [(0, 0), (2, 0), (0, 2)],
    "medium": [(0, 0), (R2, 0), (0, R2)],
    "small": [(0, 0), (1, 0), (0, 1)],
    "square": [(0, 0), (1, 0), (1, 1), (0, 1)],
    "parallelogram": [(0, 0), (1, 0), (2, 1), (1, 1)],
}
SET = ["large", "large", "medium", "small", "small", "square", "parallelogram"]
COLOURS = [(0.95, 0.33, 0.30), (0.20, 0.55, 0.95), (1.00, 0.76, 0.16), (0.20, 0.75, 0.45),
           (0.65, 0.40, 0.90), (1.00, 0.55, 0.20), (0.15, 0.75, 0.80)]

# Name, outline polygons (grid units), solution [kind, turns of 45 degrees, flipped, x, y].
PUZZLES = [
    ('Rectangle', [[[0,0],[4,0],[4,2],[0,2]]],
     [["large",0,0,0,0],["large",2,0,4,0],["medium",1,0,2,0],["square",0,0,1,1],["parallelogram",0,0,2,1],["small",4,0,1,2],["small",6,0,2,2]]),
    ('Square', [[[2,0],[4,2],[2,4],[0,2]]],
     [["large",0,0,2,2],["large",2,0,2,2],["medium",1,0,2,0],["square",0,0,1,1],["parallelogram",0,0,2,1],["small",4,0,1,2],["small",6,0,2,2]]),
    ('Triangle', [[[0,0],[4,0],[0,4]]],
     [["large",0,0,0,2],["large",0,0,2,0],["medium",1,0,1,1],["square",0,0,0,0],["parallelogram",2,1,2,2],["small",0,0,0,1],["small",2,0,2,0]]),
    ('House', [[[2,0],[4,2],[0,2]],[[1,2],[3,2],[3,4],[1,4]]],
     [["large",0,0,1,2],["large",4,0,3,4],["medium",1,0,2,0],["square",0,0,1,1],["parallelogram",0,0,2,1],["small",4,0,1,2],["small",6,0,2,2]]),
    ('Fish', [[[0,0],[2,2],[0,4]],[[2,0],[4,2],[2,4]]],
     [["large",0,0,0,2],["large",6,0,0,2],["medium",3,0,4,2],["square",0,0,2,1],["parallelogram",2,0,3,2],["small",0,0,2,2],["small",6,0,2,1]]),
    ('Bow Tie', [[[0,0],[2,2],[0,4]],[[4,0],[2,2],[4,4]]],
     [["large",0,0,0,2],["large",6,0,0,2],["medium",7,0,2,2],["square",0,0,3,1],["parallelogram",2,1,4,4],["small",2,0,4,2],["small",4,0,4,1]]),
    ('Letter T', [[[0,0],[4,0],[4,1],[3,1],[3,3],[1,3],[1,1],[0,1]]],
     [["large",0,0,1,0],["large",4,0,3,3],["medium",1,0,3,0],["square",0,0,0,0],["parallelogram",0,1,3,1],["small",0,0,1,2],["small",2,0,4,0]]),
    ('Steps', [[[0,4],[0,3],[1,3],[1,2],[2,2],[2,1],[3,1],[3,2],[4,2],[4,4]]],
     [["large",0,0,2,2],["large",4,0,4,4],["medium",1,0,1,3],["square",0,0,2,1],["parallelogram",2,1,2,4],["small",0,0,0,3],["small",2,0,2,2]]),
    ('Rocket', [[[0,1],[1,0],[2,1],[2,3],[3,4],[-1,4],[0,3]]],
     [["large",0,0,0,1],["large",4,0,1,4],["medium",1,0,1,0],["square",0,0,1,2],["parallelogram",0,0,1,3],["small",4,0,2,2],["small",6,0,1,4]]),
    ('Boat', [[[0,3],[5,3],[4,4],[1,4]],[[2,1],[2,3],[0,3]],[[3,1],[5,3],[3,3]]],
     [["large",4,0,2,3],["large",6,0,3,3],["medium",5,0,1,4],["square",0,0,2,3],["parallelogram",0,1,5,3],["small",0,0,3,3],["small",4,0,2,4]]),
    ('Sailboat', [[[1,3],[5,3],[4,4],[2,4]],[[3,0],[3,3],[0,3]],[[3,2],[4,3],[3,3]]],
     [["large",2,0,3,2],["large",4,0,3,2],["medium",1,0,1,2],["square",0,0,3,3],["parallelogram",0,0,1,3],["small",0,0,4,3],["small",6,0,3,3]]),
    ('Cat', [[[0,0],[1,1],[2,0],[2,2],[0,2]],[[0,2],[2,2],[3,3],[3,4],[1,4],[0,3]]],
     [["large",2,0,2,2],["large",4,0,2,2],["medium",3,0,1,1],["square",0,0,2,3],["parallelogram",0,0,0,3],["small",6,0,0,3],["small",6,0,2,3]]),
]


def transform(points, turns, flip):
    a = turns * math.pi / 4
    c, s = math.cos(a), math.sin(a)
    out = []
    for x, y in points:
        if flip:
            x = -x
        out.append((x * c - y * s, x * s + y * c))
    return out


def inside(point, poly):
    x, y = point
    hit = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def quarter_cells(i, j):
    """The four triangles of grid square (i, j): (key, corners)."""
    c = (i + 0.5, j + 0.5)
    corners = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
    return [((i, j, q), (corners[q], corners[(q + 1) % 4], c)) for q in range(4)]


def centroid(tri):
    return (sum(p[0] for p in tri) / len(tri), sum(p[1] for p in tri) / len(tri))


def covered(polys, bounds):
    """The quarter cells (inside bounds) whose middles fall in any of polys."""
    (x0, y0), (x1, y1) = bounds
    found = {}
    for i in range(math.floor(x0) - 1, math.ceil(x1) + 1):
        for j in range(math.floor(y0) - 1, math.ceil(y1) + 1):
            for key, tri in quarter_cells(i, j):
                if any(inside(centroid(tri), p) for p in polys):
                    found[key] = tri
    return found


def bounds_of(polys):
    xs = [x for p in polys for x, _ in p]
    ys = [y for p in polys for _, y in p]
    return (min(xs), min(ys)), (max(xs), max(ys))


class Piece:
    def __init__(self, kind, colour, x, y, turns=0, flip=False):
        self.kind, self.colour = kind, colour
        self.x, self.y, self.turns, self.flip = x, y, turns, flip

    def points(self):
        """Corners on the board (board pixels)."""
        return [(self.x + px * UNIT, self.y + py * UNIT) for px, py in transform(SHAPES[self.kind], self.turns,
                                                                                   self.flip)]

    def middle(self):
        pts = self.points()
        return centroid(pts)

    def turn(self, by=1, flip=False):
        mx, my = self.middle()
        if flip:
            self.flip = not self.flip
        self.turns = (self.turns + by) % 8
        nx, ny = self.middle()
        self.x += mx - nx
        self.y += my - ny

    def state(self):
        return [self.kind, self.x, self.y, self.turns, self.flip]


class Puzzle:
    """One outline on the board, and the seven pieces."""

    def __init__(self, index, saved=None):
        self.index = index
        self.name, self.outline, self.solution = PUZZLES[index]
        (x0, y0), (x1, y1) = bounds_of(self.outline)
        # Put the outline in the middle of the left part of the board.
        self.origin = (300 - (x0 + x1) / 2 * UNIT, BOARD_H / 2 - (y0 + y1) / 2 * UNIT)
        self.cells = covered(self.outline, ((x0, y0), (x1, y1)))
        self.solved = False
        self.pieces = []
        if saved and self._restore(saved):
            return
        self.scatter()

    def _restore(self, saved):
        try:
            pieces = []
            for n, (kind, x, y, turns, flip) in enumerate(saved):
                if kind != SET[n]:
                    return False
                pieces.append(Piece(kind, COLOURS[n], float(x), float(y), int(turns) % 8, bool(flip)))
        except (TypeError, ValueError, IndexError):
            return False
        if len(pieces) != len(SET):
            return False
        self.pieces = pieces
        self.solved = self.check()
        return True

    def scatter(self):
        """The pieces in a tidy tray down the right of the board."""
        spots = [(640, 60), (820, 60), (640, 250), (835, 255), (905, 255), (660, 430), (800, 440)]
        self.pieces = [Piece(kind, COLOURS[n], x, y) for n, (kind, (x, y)) in enumerate(zip(SET, spots))]
        self.solved = False

    # Grid helpers --------------------------------------------------------------

    def to_grid(self, point):
        return ((point[0] - self.origin[0]) / UNIT, (point[1] - self.origin[1]) / UNIT)

    def to_board(self, point):
        return (self.origin[0] + point[0] * UNIT, self.origin[1] + point[1] * UNIT)

    def snap(self, piece):
        """Pull a piece onto the grid when one of its corners is close to a grid point."""
        best = None
        for corner in piece.points():
            gx, gy = self.to_grid(corner)
            target = self.to_board((round(gx), round(gy)))
            d = math.hypot(target[0] - corner[0], target[1] - corner[1])
            if best is None or d < best[0]:
                best = (d, target[0] - corner[0], target[1] - corner[1])
        if best and best[0] < UNIT * 0.28:
            piece.x += best[1]
            piece.y += best[2]

    def grid_cover(self, piece):
        pts = [self.to_grid(p) for p in piece.points()]
        return frozenset(covered([pts], bounds_of([pts])))

    def check(self):
        """Finished when the pieces cover every quarter of the outline and
        nothing else."""
        target = set(self.cells)
        seen = set()
        for piece in self.pieces:
            cover = self.grid_cover(piece)
            if not cover <= target or cover & seen:
                return False
            seen |= cover
        return seen == target

    def hint(self):
        """A solution piece not yet matched by a piece in its place, as board
        corners, with the kind."""
        placed = [(p.kind, self.grid_cover(p)) for p in self.pieces]
        wanted = []
        for kind, turns, flip, x, y in self.solution:
            pts = [(px + x, py + y) for px, py in transform(SHAPES[kind], turns, flip)]
            wanted.append((kind, frozenset(covered([pts], bounds_of([pts]))), pts))
        done = {(kind, cover) for kind, cover, _pts in wanted} & set(placed)
        for kind, cover, pts in wanted:
            if (kind, cover) not in done:
                # Colour it like a piece of that kind that isn't in place yet.
                free = [p for p, got in zip(self.pieces, placed) if p.kind == kind and got not in done]
                colour = free[0].colour if free else COLOURS[SET.index(kind)]
                return colour, [self.to_board(p) for p in pts]
        return None


class Board(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__()
        self.window = window
        self.set_size_request(640, 420)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK |
                        Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.SCROLL_MASK)
        self.connect("draw", self.draw)
        self.connect("button-press-event", self.press)
        self.connect("motion-notify-event", self.motion)
        self.connect("button-release-event", self.release)
        self.connect("scroll-event", self.scroll)
        self.drag = None
        self.hinted = None

    # Board pixels <-> widget pixels.
    def scale(self):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        s = min(w / BOARD_W, h / BOARD_H)
        return s, (w - BOARD_W * s) / 2, (h - BOARD_H * s) / 2

    def to_board(self, x, y):
        s, ox, oy = self.scale()
        return (x - ox) / s, (y - oy) / s

    def piece_at(self, x, y):
        for piece in reversed(self.window.puzzle.pieces):
            if inside((x, y), piece.points()):
                return piece
        return None

    def draw(self, _area, cr):
        puzzle = self.window.puzzle
        s, ox, oy = self.scale()
        cr.set_source_rgb(0.93, 0.94, 0.96)
        cr.paint()
        cr.translate(ox, oy)
        cr.scale(s, s)
        # The outline.
        cr.set_source_rgb(0.25, 0.27, 0.31) if not puzzle.solved else cr.set_source_rgb(0.80, 0.82, 0.86)
        for poly in puzzle.outline:
            pts = [puzzle.to_board(p) for p in poly]
            cr.move_to(*pts[0])
            for p in pts[1:]:
                cr.line_to(*p)
            cr.close_path()
        cr.fill()
        if self.hinted:
            colour, pts = self.hinted
            cr.move_to(*pts[0])
            for p in pts[1:]:
                cr.line_to(*p)
            cr.close_path()
            cr.set_source_rgba(*colour, 0.55)
            cr.fill_preserve()
            cr.set_source_rgb(1, 1, 1)
            cr.set_line_width(3)
            cr.set_dash([8, 6])
            cr.stroke()
            cr.set_dash([])
        for piece in puzzle.pieces:
            pts = piece.points()
            cr.move_to(pts[0][0] + 2, pts[0][1] + 3)
            for p in pts[1:]:
                cr.line_to(p[0] + 2, p[1] + 3)
            cr.close_path()
            cr.set_source_rgba(0, 0, 0, 0.18)
            cr.fill()
            cr.move_to(*pts[0])
            for p in pts[1:]:
                cr.line_to(*p)
            cr.close_path()
            cr.set_source_rgb(*piece.colour)
            cr.fill_preserve()
            cr.set_source_rgba(1, 1, 1, 0.9)
            cr.set_line_width(2)
            cr.set_line_join(1)
            cr.stroke()

    def press(self, _area, event):
        x, y = self.to_board(event.x, event.y)
        piece = self.piece_at(x, y)
        if piece is None or self.window.puzzle.solved:
            return False
        pieces = self.window.puzzle.pieces
        pieces.remove(piece)
        pieces.append(piece)          # to the top
        if event.button == 3:
            if piece.kind == "parallelogram":
                piece.turn(0, flip=True)
                self.dropped(piece)
            return True
        if event.button == 1:
            self.drag = {"piece": piece, "start": (x, y), "from": (piece.x, piece.y), "moved": False}
        self.queue_draw()
        return True

    def motion(self, _area, event):
        if not self.drag:
            return False
        if not event.state & Gdk.ModifierType.BUTTON1_MASK:
            self.drag = None
            return False
        x, y = self.to_board(event.x, event.y)
        sx, sy = self.drag["start"]
        if not self.drag["moved"] and math.hypot(x - sx, y - sy) < 4:
            return True
        self.drag["moved"] = True
        piece = self.drag["piece"]
        piece.x = self.drag["from"][0] + x - sx
        piece.y = self.drag["from"][1] + y - sy
        self.queue_draw()
        return True

    def release(self, _area, event):
        if not self.drag or event.button != 1:
            return False
        piece, moved = self.drag["piece"], self.drag["moved"]
        self.drag = None
        if not moved:
            piece.turn(1)
        self.dropped(piece)
        return True

    def scroll(self, _area, event):
        x, y = self.to_board(event.x, event.y)
        piece = self.piece_at(x, y)
        if piece is None or self.window.puzzle.solved:
            return False
        if event.direction == Gdk.ScrollDirection.UP:
            by = -1
        elif event.direction == Gdk.ScrollDirection.DOWN:
            by = 1
        elif event.direction == Gdk.ScrollDirection.SMOOTH:
            ok, _dx, dy = event.get_scroll_deltas()
            if not ok or abs(dy) < 0.5:
                return True
            by = 1 if dy > 0 else -1
        else:
            return False
        piece.turn(by)
        self.dropped(piece)
        return True

    def dropped(self, piece):
        puzzle = self.window.puzzle
        # Keep pieces on the board.
        mx, my = piece.middle()
        piece.x += min(BOARD_W - 10, max(10, mx)) - mx
        piece.y += min(BOARD_H - 10, max(10, my)) - my
        puzzle.snap(piece)
        self.hinted = None
        self.queue_draw()
        self.window.changed()


class TangramWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Tangram")
        self.set_default_size(1000, 700)
        saved = self.load()
        self.solved_names = set(saved.get("solved", []))
        index = saved.get("index", 0)
        index = index if isinstance(index, int) and 0 <= index < len(PUZZLES) else 0
        self.puzzle = Puzzle(index, saved.get("pieces"))
        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        nav = Gtk.Box()
        nav.get_style_context().add_class("linked")
        back = Gtk.Button(label="‹")
        back.set_tooltip_text("Previous puzzle")
        back.set_action_name("win.previous")
        nav.pack_start(back, False, False, 0)
        self.chooser = Gtk.MenuButton()
        self.chooser.set_tooltip_text("Choose a puzzle")
        nav.pack_start(self.chooser, False, False, 0)
        ahead = Gtk.Button(label="›")
        ahead.set_tooltip_text("Next puzzle")
        ahead.set_action_name("win.next")
        nav.pack_start(ahead, False, False, 0)
        header.pack_start(nav)
        hint = Gtk.Button(label="Hint")
        hint.set_action_name("win.hint")
        header.pack_end(hint)
        restart = Gtk.Button(label="Start Over")
        restart.set_action_name("win.restart")
        header.pack_end(restart)
        self.header = header

        overlay = Gtk.Overlay()
        self.add(overlay)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        overlay.add(box)
        self.board = Board(self)
        box.pack_start(self.board, True, True, 0)
        tip = Gtk.Label(label="Drag pieces into the outline. Click a piece to turn it, "
                              "and right-click the parallelogram to flip it over.")
        tip.get_style_context().add_class("dim-label")
        tip.set_margin_top(6)
        tip.set_margin_bottom(8)
        box.pack_start(tip, False, False, 0)
        self.banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.banner.get_style_context().add_class("app-notification")
        self.banner.set_halign(Gtk.Align.CENTER)
        self.banner.set_valign(Gtk.Align.END)
        self.banner.set_margin_bottom(60)
        self.banner.set_border_width(18)
        self.banner_label = Gtk.Label()
        self.banner.pack_start(self.banner_label, False, False, 0)
        nxt = Gtk.Button(label="Next Puzzle")
        nxt.set_action_name("win.next")
        nxt.get_style_context().add_class("suggested-action")
        nxt.set_halign(Gtk.Align.CENTER)
        self.banner.pack_start(nxt, False, False, 0)
        self.banner.set_no_show_all(True)
        overlay.add_overlay(self.banner)

        menus.add_actions(self, {"previous": lambda: self.go(self.puzzle.index - 1),
                                 "next": lambda: self.go(self.puzzle.index + 1),
                                 "hint": self.hint, "restart": self.restart, "close": self.close})
        self.show_all()
        self.refresh()

    # Saving ---------------------------------------------------------------------

    @staticmethod
    def load():
        try:
            with open(SAVE) as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def save(self):
        try:
            os.makedirs(os.path.dirname(SAVE), exist_ok=True)
            tmp = SAVE + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"index": self.puzzle.index, "solved": sorted(self.solved_names),
                           "pieces": [p.state() for p in self.puzzle.pieces]}, f)
            os.replace(tmp, SAVE)
        except OSError:
            pass

    # Game ---------------------------------------------------------------------

    def refresh(self):
        puzzle = self.puzzle
        mark = " ✓" if puzzle.name in self.solved_names else ""
        self.chooser.set_label(f"{puzzle.index + 1}. {puzzle.name}{mark}")
        self.header.set_title("Tangram")
        menu = Gtk.Menu()
        for n, (name, _outline, _solution) in enumerate(PUZZLES):
            item = Gtk.MenuItem(label=f"{n + 1}. {name}" + ("  ✓" if name in self.solved_names else ""))
            item.connect("activate", lambda _i, n=n: self.go(n))
            menu.append(item)
        menu.show_all()
        self.chooser.set_popup(menu)
        if puzzle.solved:
            done = len(self.solved_names)
            self.banner_label.set_markup(f"<span size='20000' weight='700'>Well done!</span>\n"
                                         f"You made the {GLib.markup_escape_text(puzzle.name.lower())}. "
                                         f"{done} of {len(PUZZLES)} puzzles solved.")
            self.banner_label.set_justify(Gtk.Justification.CENTER)
            self.banner.show()
            for child in self.banner.get_children():
                child.show()
        else:
            self.banner.hide()
        self.board.queue_draw()

    def changed(self):
        if self.puzzle.check():
            self.puzzle.solved = True
            self.solved_names.add(self.puzzle.name)
        self.save()
        self.refresh()

    def go(self, index):
        self.puzzle = Puzzle(index % len(PUZZLES))
        self.board.hinted = None
        self.save()
        self.refresh()

    def restart(self):
        self.puzzle.scatter()
        self.board.hinted = None
        self.save()
        self.refresh()

    def hint(self):
        if self.puzzle.solved:
            return
        self.board.hinted = self.puzzle.hint()
        self.board.queue_draw()

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Tangram")
        dialog.format_secondary_text("Tangram is the seven-piece shape puzzle. It is part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_Game", [[("Next Puzzle", "win.next", "<Ctrl>Right"), ("Previous Puzzle", "win.previous", "<Ctrl>Left")],
                   [("Hint", "win.hint", "<Ctrl>h"), ("Start Over", "win.restart", "<Ctrl>r")],
                   [("Close", "win.close", "<Ctrl>w")]]),
    ])


class Tangram(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": self.quit, "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_accels_for_action("win.next", ["<Control>Right"])
        self.set_accels_for_action("win.previous", ["<Control>Left"])
        self.set_accels_for_action("win.hint", ["<Control>h"])
        self.set_accels_for_action("win.restart", ["<Control>r"])
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = TangramWindow(self)
        self.window.present()


def main():
    GLib.set_prgname("freemac-tangram")
    return Tangram().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
