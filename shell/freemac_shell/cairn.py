# SPDX-License-Identifier: GPL-3.0-or-later
"""Cairn: a tile-matching solitaire.

Picture tiles are stacked in a layout. Click two free tiles with the same
picture to take them away; clear every tile to win. A tile is free when
nothing lies on top of it and its left or right side is open.

Every deal can be cleared: tiles are dealt by taking pairs away from the
full layout in reverse, so at least one way through exists. Hint shows a
pair you can take, Shuffle mixes the tiles that are left (keeping the game
winnable), and Undo puts pairs back.

Original freemac code and layouts. The pictures are emoji from the system's
emoji font. The game in progress and best times are kept in
~/.local/share/freemac/cairn.json.
"""
import json
import math
import os
import random
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Cairn"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "cairn.json")
PICTURES = ("🍎", "🍊", "🍋", "🍇", "🍓", "🍒", "🍉", "🍍", "🥝", "🥕", "🌽", "🍄",
            "🐶", "🐱", "🐰", "🦊", "🐻", "🐼", "🐸", "🐵", "🐧", "🐢", "🐙", "🦋",
            "⚽", "🎈", "🎁", "🎨", "🚗", "🚀", "⛵", "🌈", "⭐", "🌙", "🌻", "🔔")
TILE_W, TILE_H = 1.0, 1.28          # a tile's face, in tile widths
DEPTH = 0.13                        # how far each layer is lifted, in tile widths


def rect(x, y, cols, rows, z, skip=()):
    """Tiles in a block. x and y count half tiles; a tile is two halves wide and high."""
    return [(x + 2 * i, y + 2 * j, z) for j in range(rows) for i in range(cols) if (i, j) not in skip]


def _pyramid():
    return rect(0, 0, 6, 6, 0) + rect(2, 2, 4, 4, 1) + rect(4, 4, 2, 2, 2)


def _bridge():
    return (rect(0, 2, 12, 4, 0) + rect(4, 3, 8, 2, 1)
            + rect(0, 0, 2, 1, 0) + rect(20, 0, 2, 1, 0) + rect(0, 10, 2, 1, 0) + rect(20, 10, 2, 1, 0)
            + rect(8, 4, 4, 1, 2))


def _cross():
    tiles = rect(0, 8, 10, 2, 0)
    tiles += [t for t in rect(8, 0, 2, 10, 0) if not (8 <= t[1] < 12)]
    tiles += rect(4, 8, 6, 2, 1)
    tiles += [t for t in rect(8, 4, 2, 6, 1) if not (8 <= t[1] < 12)]
    tiles += rect(8, 8, 2, 2, 2)
    return tiles


def _harbour():
    return (rect(0, 0, 10, 6, 0) + rect(2, 2, 8, 4, 1) + rect(6, 4, 4, 2, 2) + rect(8, 5, 2, 1, 3)
            + [(-2, 5, 0), (20, 5, 0)])


LAYOUTS = (
    ("pyramid", "Pyramid", _pyramid()),
    ("cross", "Cross", _cross()),
    ("bridge", "Bridge", _bridge()),
    ("harbour", "Harbour", _harbour()),
)


def _check_layouts():
    for key, _name, tiles in LAYOUTS:
        assert len(set(tiles)) == len(tiles), key
        assert len(tiles) % 4 == 0 and len(tiles) // 4 <= len(PICTURES), (key, len(tiles))


_check_layouts()


# Rules -------------------------------------------------------------------------

def covers(upper, lower):
    return upper[2] == lower[2] + 1 and abs(upper[0] - lower[0]) < 2 and abs(upper[1] - lower[1]) < 2


def free_positions(positions):
    """The positions in a collection that could be taken now."""
    present = set(positions)
    by_layer = {}
    for p in present:
        by_layer.setdefault(p[2], []).append(p)
    free = []
    for p in present:
        x, y, z = p
        if any(covers(q, p) for q in by_layer.get(z + 1, ())):
            continue
        same = by_layer[z]
        left = any(q[0] == x - 2 and abs(q[1] - y) < 2 for q in same)
        right = any(q[0] == x + 2 and abs(q[1] - y) < 2 for q in same)
        if not (left and right):
            free.append(p)
    return free


def deal(positions, rng, kinds=None):
    """Pictures for positions such that the tiles can all be cleared, or None if unlucky.

    Pairs are taken from the full layout in reverse: two free positions get the same
    picture and are removed, until none are left; that order is then a way through.
    """
    positions = list(positions)
    if kinds is None:
        count = len(positions) // 4
        chosen = rng.sample(range(len(PICTURES)), count)
        kinds = [k for k in chosen for _twice in range(2)]       # one entry per pair
    else:
        kinds = list(kinds)
    rng.shuffle(kinds)
    left = set(positions)
    result = {}
    for kind in kinds:
        free = free_positions(left)
        if len(free) < 2:
            return None
        # Prefer pairs that lie apart, so the solution isn't simply neighbours.
        a, b = rng.sample(free, 2)
        result[a] = kind
        result[b] = kind
        left.discard(a)
        left.discard(b)
    return result


def deal_until(positions, rng, kinds=None):
    for _attempt in range(400):
        tiles = deal(positions, rng, kinds)
        if tiles is not None:
            return tiles
    return None


def matching_pairs(tiles):
    free = free_positions(tiles.keys())
    pairs = []
    for i, a in enumerate(free):
        for b in free[i + 1:]:
            if tiles[a] == tiles[b]:
                pairs.append((a, b))
    return pairs


# Store -------------------------------------------------------------------------

def load_store():
    try:
        with open(STORE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_store(data):
    try:
        os.makedirs(os.path.dirname(STORE), exist_ok=True)
        tmp = STORE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, STORE)
    except OSError:
        pass


def clock(seconds):
    seconds = int(seconds)
    return f"{seconds // 60}:{seconds % 60:02d}"


# Table -------------------------------------------------------------------------

class Table(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(can_focus=True)
        self.window = window
        self.hover = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.POINTER_MOTION_MASK
                        | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("leave-notify-event", lambda *_a: self._set_hover(None))

    def geometry(self):
        """Tile width in pixels and the origin, fitted to the whole layout (not just what's left)."""
        layout = self.window.layout_positions
        xs = [p[0] for p in layout]
        ys = [p[1] for p in layout]
        zmax = max(p[2] for p in layout)
        cols = (max(xs) - min(xs)) / 2 + 1
        rows = (max(ys) - min(ys)) / 2 + 1
        w, h = self.get_allocated_width(), self.get_allocated_height()
        width_units = cols * TILE_W + DEPTH * (zmax + 1) + 0.2
        height_units = rows * TILE_H + DEPTH * (zmax + 1) + 0.2
        unit = min((w - 30) / width_units, (h - 30) / height_units)
        unit = max(unit, 12)
        x0 = (w - width_units * unit) / 2 + DEPTH * (zmax + 1) * unit - min(xs) / 2 * TILE_W * unit
        y0 = (h - height_units * unit) / 2 + DEPTH * (zmax + 1) * unit - min(ys) / 2 * TILE_H * unit
        return unit, x0, y0

    def face(self, position, geometry=None):
        unit, x0, y0 = geometry or self.geometry()
        x, y, z = position
        left = x0 + x / 2 * TILE_W * unit - z * DEPTH * unit
        top = y0 + y / 2 * TILE_H * unit - z * DEPTH * unit
        return left, top, TILE_W * unit, TILE_H * unit

    @staticmethod
    def order(position):
        x, y, z = position
        return (z, -x, y)

    def tile_at(self, px, py):
        geometry = self.geometry()
        for position in sorted(self.window.tiles, key=self.order, reverse=True):
            left, top, w, h = self.face(position, geometry)
            if left <= px <= left + w and top <= py <= top + h:
                return position
        return None

    def _set_hover(self, position):
        if position != self.hover:
            self.hover = position
            self.queue_draw()

    def _motion(self, _w, event):
        self._set_hover(self.tile_at(event.x, event.y))

    def _press(self, _w, event):
        self.grab_focus()
        if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
            self.window.click(self.tile_at(event.x, event.y))
        return True

    def _rounded(self, cr, x, y, w, h, r):
        cr.new_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
        cr.close_path()

    def _draw(self, _w, cr):
        window = self.window
        if not window.tiles:
            return False
        geometry = self.geometry()
        unit = geometry[0]
        free = set(free_positions(window.tiles.keys()))
        radius = unit * 0.11
        side = DEPTH * unit
        for position in sorted(window.tiles, key=self.order):
            left, top, w, h = self.face(position, geometry)
            # Shadow, then the tile's thickness below and to the left, then its face.
            self._rounded(cr, left - side * 0.6, top + side * 1.6, w, h, radius)
            cr.set_source_rgba(0, 0, 0, 0.18)
            cr.fill()
            self._rounded(cr, left - side, top + side, w, h, radius)
            cr.set_source_rgb(0.80, 0.72, 0.58)
            cr.fill()
            self._rounded(cr, left - side * 0.5, top + side * 0.5, w, h, radius)
            cr.set_source_rgb(0.90, 0.84, 0.72)
            cr.fill()
            self._rounded(cr, left, top, w, h, radius)
            if position == window.selected:
                cr.set_source_rgb(0.70, 0.84, 1.0)
            elif position in window.hinted:
                cr.set_source_rgb(1.0, 0.90, 0.55)
            else:
                cr.set_source_rgb(0.99, 0.97, 0.92)
            cr.fill_preserve()
            cr.set_source_rgba(0, 0, 0, 0.22)
            cr.set_line_width(1)
            cr.stroke()
            layout = PangoCairo.create_layout(cr)
            desc = Pango.FontDescription.from_string("Noto Color Emoji")
            desc.set_absolute_size(w * 0.62 * Pango.SCALE)
            layout.set_font_description(desc)
            layout.set_text(window.tiles[position], -1)
            _ink, logical = layout.get_pixel_extents()
            cr.move_to(left + (w - logical.width) / 2, top + (h - logical.height) / 2)
            PangoCairo.show_layout(cr, layout)
            if position not in free and window.dim_blocked:
                self._rounded(cr, left, top, w, h, radius)
                cr.set_source_rgba(0.25, 0.2, 0.1, 0.22)
                cr.fill()
            elif position == self.hover and position in free and position != window.selected:
                self._rounded(cr, left, top, w, h, radius)
                cr.set_source_rgba(0.04, 0.49, 1.0, 0.10)
                cr.fill()
        return False


# Window ------------------------------------------------------------------------

class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Cairn")
        self.set_default_size(980, 720)
        self.store = load_store()
        self.rng = random.Random()
        self.layout_key = self.store.get("layout") if self.store.get("layout") in {k for k, _n, _t in LAYOUTS} \
            else "pyramid"
        self.dim_blocked = bool(self.store.get("dim", True))
        self.tiles = {}
        self.taken = []              # pairs taken, [(position, picture), (position, picture)]
        self.selected = None
        self.hinted = set()
        self.hint_id = 0
        self.seconds = 0.0
        self.finished = False
        self.stuck = False

        header = Gtk.HeaderBar(show_close_button=True, title="Cairn")
        self.header = header
        self.set_titlebar(header)
        new = Gtk.Button(label="New Game")
        new.connect("clicked", lambda _b: self.new_game())
        header.pack_start(new)
        self.layout_button = Gtk.MenuButton()
        box = Gtk.Box(spacing=4)
        self.layout_label = Gtk.Label()
        box.pack_start(self.layout_label, False, False, 0)
        box.pack_start(Gtk.Image.new_from_icon_name("pan-down-symbolic", Gtk.IconSize.BUTTON), False, False, 0)
        self.layout_button.add(box)
        popover = Gtk.Popover()
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for key, name, positions in LAYOUTS:
            entry = Gtk.ModelButton(text=f"{name}  ({len(positions)} tiles)")
            entry.connect("clicked", lambda _b, k=key: self.choose_layout(k))
            column.pack_start(entry, False, False, 0)
        column.show_all()
        popover.add(column)
        self.layout_button.set_popover(popover)
        header.pack_start(self.layout_button)
        self.time_label = Gtk.Label()
        self.time_label.get_style_context().add_class("cairn-time")
        header.pack_end(self.time_label)
        hint = Gtk.Button(label="Hint")
        hint.set_tooltip_text("Show a pair you can take (adds 15 seconds to your time)")
        hint.connect("clicked", lambda _b: self.hint())
        header.pack_end(hint)
        shuffle = Gtk.Button(label="Shuffle")
        shuffle.connect("clicked", lambda _b: self.shuffle())
        header.pack_end(shuffle)
        undo = Gtk.Button.new_from_icon_name("edit-undo-symbolic", Gtk.IconSize.BUTTON)
        undo.set_tooltip_text("Put the last pair back")
        undo.connect("clicked", lambda _b: self.undo())
        self.undo_button = undo
        header.pack_end(undo)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)
        self.status = Gtk.Label()
        self.status.get_style_context().add_class("dim-label")
        self.status.set_margin_top(8)
        outer.pack_start(self.status, False, False, 0)
        overlay = Gtk.Overlay()
        self.table = Table(self)
        self.table.set_vexpand(True)
        overlay.add(self.table)
        self.banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                              halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.banner.get_style_context().add_class("cairn-banner")
        self.banner_title = Gtk.Label()
        self.banner_text = Gtk.Label(justify=Gtk.Justification.CENTER)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        self.banner_shuffle = Gtk.Button(label="Shuffle")
        self.banner_shuffle.connect("clicked", lambda _b: self.shuffle())
        self.banner_undo = Gtk.Button(label="Undo")
        self.banner_undo.connect("clicked", lambda _b: self.undo())
        again = Gtk.Button(label="New Game")
        again.get_style_context().add_class("suggested-action")
        again.connect("clicked", lambda _b: self.new_game())
        for button in (self.banner_undo, self.banner_shuffle, again):
            buttons.pack_start(button, False, False, 0)
        self.banner.pack_start(self.banner_title, False, False, 0)
        self.banner.pack_start(self.banner_text, False, False, 0)
        self.banner.pack_start(buttons, False, False, 4)
        self.banner.set_no_show_all(True)
        overlay.add_overlay(self.banner)
        outer.pack_start(overlay, True, True, 0)

        css = Gtk.CssProvider()
        css.load_from_data(b".cairn-banner { background-color: alpha(@theme_bg_color, 0.96); border-radius: 14px;"
                           b" padding: 18px 34px; box-shadow: 0 6px 24px alpha(black, 0.3); }"
                           b" .cairn-time { font-feature-settings: 'tnum'; font-weight: 600; }")
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        menus.add_actions(self, {"new": self.new_game, "close": self.close, "undo": self.undo,
                                 "hint": self.hint, "shuffle": self.shuffle, "best": self.show_best})
        self.connect("notify::is-active", lambda *_a: self.update_labels())
        if not self.restore() or not self.tiles:
            self.new_game(save=False)
        GLib.timeout_add(1000, self._clock)
        self.show_all()
        self.after_change()
        self.table.grab_focus()

    # State --------------------------------------------------------------------

    @property
    def layout_positions(self):
        return next(t for k, _n, t in LAYOUTS if k == self.layout_key)

    def layout_name(self):
        return next(n for k, n, _t in LAYOUTS if k == self.layout_key)

    def restore(self):
        game = self.store.get("game")
        if not isinstance(game, dict) or game.get("layout") != self.layout_key:
            return False
        try:
            tiles = {tuple(int(v) for v in pos): pic for pos, pic in game["tiles"]}
            taken = [[(tuple(int(v) for v in pos), pic) for pos, pic in pair] for pair in game["taken"]]
            seconds = float(game.get("seconds", 0))
        except (KeyError, TypeError, ValueError):
            return False
        everything = set(tiles) | {pos for pair in taken for pos, _pic in pair}
        if (everything != set(self.layout_positions) or len(everything) != len(tiles) + 2 * len(taken)
                or not all(p in PICTURES for p in tiles.values())
                or any(len(pair) != 2 or pair[0][1] != pair[1][1] for pair in taken)):
            return False
        self.tiles, self.taken, self.seconds = tiles, taken, seconds
        return True

    def save(self):
        self.store["layout"] = self.layout_key
        self.store["dim"] = self.dim_blocked
        self.store["game"] = {"layout": self.layout_key, "seconds": self.seconds,
                              "tiles": [[list(p), pic] for p, pic in self.tiles.items()],
                              "taken": [[[list(p), pic] for p, pic in pair] for pair in self.taken]}
        save_store(self.store)

    def bests(self):
        bests = self.store.get("best")
        if not isinstance(bests, dict):
            bests = {}
            self.store["best"] = bests
        return bests

    def update_labels(self):
        self.layout_label.set_text(self.layout_name())
        left = len(self.tiles)
        pairs = len(matching_pairs(self.tiles)) if self.tiles else 0
        if self.finished:
            self.status.set_text("")
        else:
            self.status.set_text(f"{left} tiles left  ·  {pairs} pair{'s' if pairs != 1 else ''} you can take now")
        self.time_label.set_text(clock(self.seconds))
        self.undo_button.set_sensitive(bool(self.taken))

    def after_change(self):
        self.finished = not self.tiles
        self.stuck = bool(self.tiles) and not matching_pairs(self.tiles)
        self.banner.hide()
        if self.finished:
            bests = self.bests()
            old = bests.get(self.layout_key)
            if not isinstance(old, (int, float)) or self.seconds < old:
                bests[self.layout_key] = int(self.seconds)
                text = f"You cleared {self.layout_name()} in {clock(self.seconds)}, your best time."
            else:
                text = f"You cleared {self.layout_name()} in {clock(self.seconds)}. Your best is {clock(old)}."
            self._show_banner("All clear!", text, stuck=False)
        elif self.stuck:
            self._show_banner("No more pairs", "None of the free tiles match. Shuffle the tiles that are left, "
                              "or undo and try another way.", stuck=True)
        self.update_labels()
        self.table.queue_draw()
        self.save()

    def _show_banner(self, title, text, stuck):
        self.banner_title.set_markup(f"<span size='18000' weight='700'>{GLib.markup_escape_text(title)}</span>")
        self.banner_text.set_text(text)
        self.banner_text.set_line_wrap(True)
        self.banner_text.set_max_width_chars(42)
        self.banner.show()
        for child in self.banner.get_children():
            child.show_all()
        self.banner_shuffle.set_visible(stuck)
        self.banner_undo.set_visible(stuck and bool(self.taken))

    def _clock(self):
        if not self.finished and not self.stuck and self.is_active() and self.taken:
            self.seconds += 1
            self.time_label.set_text(clock(self.seconds))
            if int(self.seconds) % 10 == 0:
                self.save()
        return True

    # Play ---------------------------------------------------------------------

    def click(self, position):
        if self.finished or position is None:
            if position is None and self.selected:
                self.selected = None
                self.table.queue_draw()
            return
        free = free_positions(self.tiles.keys())
        if position not in free:
            Gdk.beep()
            return
        self.clear_hint()
        if self.selected is None or self.selected == position:
            self.selected = None if self.selected == position else position
        elif self.tiles[self.selected] == self.tiles[position]:
            pair = [(self.selected, self.tiles.pop(self.selected)), (position, self.tiles.pop(position))]
            self.taken.append(pair)
            self.selected = None
            self.after_change()
            return
        else:
            self.selected = position
        self.table.queue_draw()

    def undo(self):
        if not self.taken:
            return
        self.clear_hint()
        for position, picture in self.taken.pop():
            self.tiles[position] = picture
        self.selected = None
        self.after_change()

    def clear_hint(self):
        self.hinted = set()
        if self.hint_id:
            GLib.source_remove(self.hint_id)
            self.hint_id = 0

    def hint(self):
        pairs = matching_pairs(self.tiles)
        if not pairs:
            return
        self.clear_hint()
        self.hinted = set(self.rng.choice(pairs))
        self.seconds += 15                       # a small cost, as a hint should have
        self.hint_id = GLib.timeout_add(2200, self._end_hint)
        self.update_labels()
        self.table.queue_draw()

    def _end_hint(self):
        self.hint_id = 0
        self.hinted = set()
        self.table.queue_draw()
        return False

    def shuffle(self):
        if not self.tiles:
            return
        self.clear_hint()
        pictures = sorted(self.tiles.values())
        kinds = pictures[::2]                    # one entry per pair
        tiles = deal_until(list(self.tiles), self.rng, kinds)
        if tiles is None:
            return
        self.tiles = tiles
        self.selected = None
        self.after_change()

    def new_game(self, save=True):
        self.clear_hint()
        tiles = deal_until(self.layout_positions, self.rng)
        self.tiles = {p: PICTURES[k] for p, k in tiles.items()}
        self.taken = []
        self.selected = None
        self.seconds = 0.0
        if save:
            self.after_change()

    def choose_layout(self, key):
        if key != self.layout_key:
            self.layout_key = key
            self.new_game()

    def show_best(self):
        bests = self.bests()
        lines = [f"{name}: {clock(bests[key]) if isinstance(bests.get(key), (int, float)) else 'not cleared yet'}"
                 for key, name, _t in LAYOUTS]
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="Best Times")
        dialog.format_secondary_text("\n".join(lines))
        dialog.run()
        dialog.destroy()

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Cairn")
        dialog.format_secondary_text("Cairn is a tile-matching solitaire, part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_Game", [[("New Game", "win.new", "<Ctrl>n"), ("Undo", "win.undo", "<Ctrl>z")],
                   [("Hint", "win.hint", "<Ctrl>h"), ("Shuffle", "win.shuffle", None)],
                   [("Best Times", "win.best", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
    ])


class Cairn(Gtk.Application):
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
        self.set_accels_for_action("win.undo", ["<Control>z"])
        self.set_accels_for_action("win.hint", ["<Control>h"])
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-cairn")
    return Cairn().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
