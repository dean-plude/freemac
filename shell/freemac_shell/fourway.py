# SPDX-License-Identifier: GPL-3.0-or-later
"""Fourway: four in a row.

Two players take turns dropping counters into a stand of seven columns and
six rows. A counter falls to the lowest free space in its column. The first
to line up four of their own across, down or on a slant wins.

Play the computer at three levels, or a friend on the same computer, taking
turns at the mouse. Click a column (or use the arrow keys and Return, or the
number keys 1 to 7) to drop a counter.

Original freemac code. The computer searches ahead with alpha-beta pruning
on a bitboard. The game in progress, the settings and the tally of results
are kept in ~/.local/share/freemac/fourway.json.
"""
import json
import math
import os
import random
import sys
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Fourway"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "fourway.json")
COLUMNS, ROWS = 7, 6
H1 = ROWS + 1                      # bits per column in the bitboard (one spare)
LEVELS = (("easy", "Easy"), ("medium", "Medium"), ("hard", "Hard"))
RED, YELLOW = 0, 1
NAMES = ("Red", "Yellow")
COLOURS = ((0.92, 0.25, 0.23), (0.99, 0.77, 0.16))
STAND = (0.15, 0.40, 0.85)
DROP_SPEED = 30.0                  # cells per second squared, roughly


# Engine ------------------------------------------------------------------------

def bottom(col):
    return 1 << (col * H1)


def top(col):
    return 1 << (ROWS - 1 + col * H1)


def column_mask(col):
    return ((1 << ROWS) - 1) << (col * H1)


def four(stones):
    """True when the bitboard holds four in a row."""
    for shift in (1, H1, H1 - 1, H1 + 1):
        pairs = stones & (stones >> shift)
        if pairs & (pairs >> (2 * shift)):
            return True
    return False


def _windows():
    found = []
    for col in range(COLUMNS):
        for row in range(ROWS):
            for dc, dr in ((1, 0), (0, 1), (1, 1), (1, -1)):
                cells = [(col + dc * k, row + dr * k) for k in range(4)]
                if all(0 <= c < COLUMNS and 0 <= r < ROWS for c, r in cells):
                    bits = 0
                    for c, r in cells:
                        bits |= 1 << (c * H1 + r)
                    found.append((bits, cells))
    return found


WINDOWS = _windows()
WINDOW_BITS = [w for w, _cells in WINDOWS]
ORDER = (3, 2, 4, 1, 5, 0, 6)
WEIGHT = (0, 1, 5, 40, 0)
WIN = 1000000


class Position:
    """A position as two bitboards: the stones of the player to move, and all stones."""

    def __init__(self, moves=()):
        self.mine = 0
        self.mask = 0
        self.count = 0
        for col in moves:
            self.play(col)

    def can_play(self, col):
        return not self.mask & top(col)

    def landing(self, col):
        return (self.mask + bottom(col)) & column_mask(col)

    def play(self, col):
        self.mine ^= self.mask
        self.mask |= self.mask + bottom(col)
        self.count += 1

    def wins(self, col):
        """Would playing col win for the player to move?"""
        return four(self.mine | self.landing(col))

    def copy(self):
        other = Position()
        other.mine, other.mask, other.count = self.mine, self.mask, self.count
        return other


def evaluate(mine, theirs):
    score = 0
    for bits in WINDOW_BITS:
        a = mine & bits
        b = theirs & bits
        if a and not b:
            score += WEIGHT[bin(a).count("1")]
        elif b and not a:
            score -= WEIGHT[bin(b).count("1")]
    # A little for the middle column, which takes part in the most lines.
    centre = column_mask(3)
    score += 3 * (bin(mine & centre).count("1") - bin(theirs & centre).count("1"))
    return score


class OutOfTime(Exception):
    pass


class Search:
    def __init__(self, deadline):
        self.deadline = deadline
        self.nodes = 0

    def negamax(self, mine, mask, count, depth, alpha, beta):
        self.nodes += 1
        if self.nodes & 1023 == 0 and time.monotonic() > self.deadline:
            raise OutOfTime()
        if count == COLUMNS * ROWS:
            return 0
        theirs = mine ^ mask
        playable = [c for c in ORDER if not mask & top(c)]
        for col in playable:
            if four(mine | ((mask + bottom(col)) & column_mask(col))):
                return WIN - count
        if depth == 0:
            return evaluate(mine, theirs)
        # Must block an immediate threat; two threats lose.
        threats = [c for c in playable if four(theirs | ((mask + bottom(c)) & column_mask(c)))]
        if len(threats) > 1:
            return -(WIN - count - 1)
        if threats:
            playable = threats
        best = -WIN * 2
        for col in playable:
            new_mask = mask | (mask + bottom(col))
            score = -self.negamax(theirs, new_mask, count + 1, depth - 1, -beta, -alpha)
            if score > best:
                best = score
            if score > alpha:
                alpha = score
            if alpha >= beta:
                break
        return best

    def choose(self, position, max_depth):
        """Best column by iterative deepening until the deadline or max_depth."""
        playable = [c for c in ORDER if position.can_play(c)]
        for col in playable:
            if position.wins(col):
                return col
        best = None
        for depth in range(1, max_depth + 1):
            try:
                alpha = -WIN * 2
                choice = None
                order = playable if best is None else [best] + [c for c in playable if c != best]
                for col in order:
                    mask = position.mask | (position.mask + bottom(col))
                    score = -self.negamax(position.mine ^ position.mask, mask, position.count + 1,
                                          depth - 1, -WIN * 2, -alpha)
                    # Only a strictly better score is exact; equal ones are bounds from a cut-off.
                    if score > alpha:
                        alpha, choice = score, col
            except OutOfTime:
                break
            best = choice
            if abs(alpha) >= WIN - COLUMNS * ROWS:
                break
        return best if best is not None else playable[0]


def computer_move(moves, level, rng=random):
    position = Position(moves)
    playable = [c for c in range(COLUMNS) if position.can_play(c)]
    if level == "easy":
        wins = [c for c in playable if position.wins(c)]
        if wins and rng.random() < 0.75:
            return wins[0]
        other = position.copy()
        other.mine ^= other.mask
        blocks = [c for c in playable if other.wins(c)]
        if blocks and rng.random() < 0.6:
            return blocks[0]
        if rng.random() < 0.5:
            return Search(time.monotonic() + 0.3).choose(position, 2)
        weights = [4 - abs(3 - c) for c in playable]
        return rng.choices(playable, weights)[0]
    if level == "medium":
        if rng.random() < 0.1:
            return Search(time.monotonic() + 0.3).choose(position, 2)
        return Search(time.monotonic() + 0.8).choose(position, 4)
    return Search(time.monotonic() + 1.4).choose(position, 14)


def winning_cells(grid):
    """The cells of every four-in-a-row on the grid, as a set of (col, row)."""
    cells = set()
    for _bits, window in WINDOWS:
        owners = {grid[c][r] for c, r in window}
        if len(owners) == 1 and None not in owners:
            cells.update(window)
    return cells


def grid_of(moves, starter):
    grid = [[None] * ROWS for _c in range(COLUMNS)]
    for n, col in enumerate(moves):
        row = sum(1 for v in grid[col] if v is not None)
        grid[col][row] = (starter + n) % 2
    return grid


def valid_moves(moves):
    if not isinstance(moves, list):
        return False
    heights = [0] * COLUMNS
    for col in moves:
        if not isinstance(col, int) or not 0 <= col < COLUMNS or heights[col] >= ROWS:
            return False
        heights[col] += 1
    return True


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


# Board -------------------------------------------------------------------------

class Board(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(can_focus=True)
        self.window = window
        self.hover = None
        self.falling = None          # {"col", "row", "player", "y", "v"}
        self.tick_id = 0
        self.last_tick = 0
        self.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK
                        | Gdk.EventMask.LEAVE_NOTIFY_MASK | Gdk.EventMask.KEY_PRESS_MASK)
        self.connect("draw", self._draw)
        self.connect("motion-notify-event", self._motion)
        self.connect("leave-notify-event", lambda *_a: self._set_hover(None))
        self.connect("button-press-event", self._press)
        self.connect("key-press-event", self._key)

    def layout(self):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        cell = min((w - 40) / (COLUMNS + 0.5), (h - 30) / (ROWS + 1.85))
        cell = max(cell, 10)
        width = cell * (COLUMNS + 0.5)
        height = cell * (ROWS + 0.5)
        x0 = (w - width) / 2
        y0 = (h - height - cell * 1.35) / 2 + cell * 1.1
        return cell, x0, y0, width, height

    def centre(self, col, row):
        cell, x0, y0, _w, height = self.layout()
        return (x0 + cell * 0.25 + cell * (col + 0.5),
                y0 + height - cell * 0.25 - cell * (row + 0.5))

    def column_at(self, x):
        cell, x0, _y0, width, _h = self.layout()
        if not x0 <= x <= x0 + width:
            return None
        col = int((x - x0 - cell * 0.25) // cell)
        return col if 0 <= col < COLUMNS else None

    def _set_hover(self, col):
        if col != self.hover:
            self.hover = col
            self.queue_draw()

    def _motion(self, _w, event):
        self._set_hover(self.column_at(event.x))

    def _press(self, _w, event):
        self.grab_focus()
        if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
            col = self.column_at(event.x)
            if col is not None:
                self.window.human_play(col)
        return True

    def _key(self, _w, event):
        key = event.keyval
        if key in (Gdk.KEY_Left, Gdk.KEY_Right):
            col = 3 if self.hover is None else self.hover + (1 if key == Gdk.KEY_Right else -1)
            self._set_hover(max(0, min(COLUMNS - 1, col)))
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space, Gdk.KEY_Down) and self.hover is not None:
            self.window.human_play(self.hover)
            return True
        if Gdk.KEY_1 <= key <= Gdk.KEY_7 and not event.state & Gdk.ModifierType.CONTROL_MASK:
            col = key - Gdk.KEY_1
            self._set_hover(col)
            self.window.human_play(col)
            return True
        return False

    def drop(self, col, row, player, done):
        cell, *_rest = self.layout()
        _x, target = self.centre(col, row)
        start = self.centre(col, ROWS)[1] - cell * 0.6
        self.falling = {"col": col, "row": row, "player": player, "y": start, "v": 0.0,
                        "target": target, "done": done}
        self.last_tick = time.monotonic()
        # A plain timer rather than the frame clock: on Wayland the frame clock can wait
        # for an input event before it ticks again.
        if not self.tick_id:
            self.tick_id = GLib.timeout_add(16, self._tick)
        self.queue_draw()

    def stop_drop(self):
        self.falling = None
        if self.tick_id:
            GLib.source_remove(self.tick_id)
            self.tick_id = 0
        self.queue_draw()

    def _tick(self):
        falling = self.falling
        if not falling:
            self.tick_id = 0
            return False
        now = time.monotonic()
        dt = min(now - self.last_tick, 0.05)
        self.last_tick = now
        cell = self.layout()[0]
        falling["v"] += DROP_SPEED * cell * dt * 3
        falling["y"] += falling["v"] * dt
        if falling["y"] >= falling["target"]:
            self.tick_id = 0
            self.falling = None
            self.queue_draw()
            falling["done"]()
            return False
        self.queue_draw()
        return True

    def _counter(self, cr, x, y, r, player, alpha=1.0):
        red, green, blue = COLOURS[player]
        cr.new_path()
        cr.arc(x, y, r, 0, 2 * math.pi)
        cr.set_source_rgba(red * 0.78, green * 0.78, blue * 0.78, alpha)
        cr.fill()
        cr.arc(x, y, r * 0.86, 0, 2 * math.pi)
        cr.set_source_rgba(red, green, blue, alpha)
        cr.fill()
        cr.arc(x, y, r * 0.58, 0, 2 * math.pi)
        cr.set_source_rgba(red * 0.9, green * 0.9, blue * 0.9, alpha)
        cr.set_line_width(max(1.0, r * 0.07))
        cr.stroke()
        cr.arc(x - r * 0.3, y - r * 0.32, r * 0.22, 0, 2 * math.pi)
        cr.set_source_rgba(1, 1, 1, 0.28 * alpha)
        cr.fill()

    def _draw(self, _w, cr):
        window = self.window
        cell, x0, y0, width, height = self.layout()
        r = cell * 0.40
        grid = window.grid
        # The counter about to be dropped, over the hovered column.
        if (self.hover is not None and window.human_turn() and not window.finished
                and not self.falling and window.can_play(self.hover)):
            x, _y = self.centre(self.hover, 0)
            self._counter(cr, x, y0 - cell * 0.6, r, window.to_move(), 0.9)
        # Counters behind the stand.
        for col in range(COLUMNS):
            for row in range(ROWS):
                player = grid[col][row]
                if player is not None and not (self.falling and self.falling["col"] == col
                                               and self.falling["row"] == row):
                    x, y = self.centre(col, row)
                    self._counter(cr, x, y, r, player)
        if self.falling:
            x, _y = self.centre(self.falling["col"], 0)
            self._counter(cr, x, self.falling["y"], r, self.falling["player"])
        # The stand, with a hole for every space.
        radius = cell * 0.35
        cr.new_path()
        cr.set_fill_rule(1)   # even-odd
        cr.move_to(x0 + radius, y0)
        cr.arc(x0 + width - radius, y0 + radius, radius, -math.pi / 2, 0)
        cr.arc(x0 + width - radius, y0 + height - radius, radius, 0, math.pi / 2)
        cr.arc(x0 + radius, y0 + height - radius, radius, math.pi / 2, math.pi)
        cr.arc(x0 + radius, y0 + radius, radius, math.pi, 1.5 * math.pi)
        cr.close_path()
        for col in range(COLUMNS):
            for row in range(ROWS):
                x, y = self.centre(col, row)
                cr.new_sub_path()
                cr.arc_negative(x, y, cell * 0.43, 0, -2 * math.pi)
        cr.set_source_rgb(*STAND)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.18)
        cr.set_line_width(1)
        cr.stroke()
        cr.set_fill_rule(0)
        # A soft rim inside each hole.
        for col in range(COLUMNS):
            for row in range(ROWS):
                x, y = self.centre(col, row)
                cr.new_path()
                cr.arc(x, y, cell * 0.43, math.pi * 1.05, math.pi * 1.95)
                cr.set_source_rgba(0, 0, 0, 0.22)
                cr.set_line_width(max(1.0, cell * 0.04))
                cr.stroke()
        # Feet.
        cr.set_source_rgb(STAND[0] * 0.8, STAND[1] * 0.8, STAND[2] * 0.8)
        for fx in (x0 - cell * 0.15, x0 + width - cell * 0.35):
            cr.rectangle(fx, y0 + height - cell * 0.1, cell * 0.5, cell * 0.25)
            cr.fill()
        # Rings round the winning line.
        if window.finished and window.winners and not self.falling:
            cr.set_line_width(max(2.0, cell * 0.07))
            cr.set_source_rgb(1, 1, 1)
            for col, row in window.winners:
                x, y = self.centre(col, row)
                cr.new_path()
                cr.arc(x, y, r * 0.72, 0, 2 * math.pi)
                cr.stroke()
        # Keyboard pointer.
        if self.has_focus() and window.keyboard and self.hover is not None:
            x, _y = self.centre(self.hover, 0)
            cr.set_source_rgba(0.04, 0.49, 1.0, 0.8)
            cr.set_line_width(2)
            cr.rectangle(x - cell * 0.5, y0 - cell * 1.1, cell, cell)
            cr.stroke()
        return False


# Window ------------------------------------------------------------------------

class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Fourway")
        self.set_default_size(760, 680)
        self.store = load_store()
        store = self.store
        self.mode = "friend" if store.get("mode") == "friend" else "computer"
        self.level = store.get("level") if store.get("level") in dict(LEVELS) else "medium"
        self.starter = RED if store.get("starter") not in (RED, YELLOW) else store["starter"]
        moves = store.get("moves")
        self.moves = moves if valid_moves(moves) else []
        tally = store.get("tally")
        self.tally = tally if isinstance(tally, dict) else {}
        self.thinking = False
        self.think_token = 0
        self.keyboard = False
        self.finished = False
        self.winners = set()
        self.grid = grid_of(self.moves, self.starter)

        header = Gtk.HeaderBar(show_close_button=True, title="Fourway")
        self.header = header
        self.set_titlebar(header)
        new = Gtk.Button(label="New Game")
        new.connect("clicked", lambda _b: self.new_game())
        header.pack_start(new)
        opponents = Gtk.Box()
        opponents.get_style_context().add_class("linked")
        self.vs_computer = Gtk.RadioButton.new_with_label_from_widget(None, "Computer")
        self.vs_friend = Gtk.RadioButton.new_with_label_from_widget(self.vs_computer, "Friend")
        for button in (self.vs_computer, self.vs_friend):
            button.set_mode(False)
            opponents.pack_start(button, False, False, 0)
        (self.vs_friend if self.mode == "friend" else self.vs_computer).set_active(True)
        self.vs_friend.connect("toggled", self._mode_toggled)
        header.pack_start(opponents)
        self.level_button = Gtk.MenuButton()
        level_box = Gtk.Box(spacing=4)
        self.level_label = Gtk.Label(label=dict(LEVELS)[self.level])
        level_box.pack_start(self.level_label, False, False, 0)
        level_box.pack_start(Gtk.Image.new_from_icon_name("pan-down-symbolic", Gtk.IconSize.BUTTON),
                             False, False, 0)
        self.level_button.add(level_box)
        self.level_button.set_tooltip_text("How well the computer plays")
        popover = Gtk.Popover()
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for key, label in LEVELS:
            entry = Gtk.ModelButton(text=label)
            entry.connect("clicked", lambda _b, k=key: self.choose_level(k))
            column.pack_start(entry, False, False, 0)
        column.show_all()
        popover.add(column)
        self.level_button.set_popover(popover)
        header.pack_start(self.level_button)
        undo = Gtk.Button.new_from_icon_name("edit-undo-symbolic", Gtk.IconSize.BUTTON)
        undo.set_tooltip_text("Take back a move")
        undo.connect("clicked", lambda _b: self.undo())
        self.undo_button = undo
        header.pack_end(undo)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)
        bar = Gtk.Box(spacing=20, halign=Gtk.Align.CENTER)
        bar.set_margin_top(10)
        self.turn_label = Gtk.Label()
        self.turn_label.get_style_context().add_class("fourway-turn")
        self.score_label = Gtk.Label()
        self.score_label.get_style_context().add_class("dim-label")
        bar.pack_start(self.turn_label, False, False, 0)
        bar.pack_start(self.score_label, False, False, 0)
        box.pack_start(bar, False, False, 0)
        overlay = Gtk.Overlay()
        self.board = Board(self)
        self.board.set_vexpand(True)
        overlay.add(self.board)
        self.banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                              halign=Gtk.Align.CENTER, valign=Gtk.Align.START)
        self.banner.set_margin_top(14)
        self.banner.get_style_context().add_class("fourway-banner")
        self.banner_title = Gtk.Label()
        again = Gtk.Button(label="Play Again")
        again.get_style_context().add_class("suggested-action")
        again.set_halign(Gtk.Align.CENTER)
        again.connect("clicked", lambda _b: self.new_game())
        self.banner.pack_start(self.banner_title, False, False, 0)
        self.banner.pack_start(again, False, False, 0)
        self.banner.set_no_show_all(True)
        overlay.add_overlay(self.banner)
        box.pack_start(overlay, True, True, 0)

        css = Gtk.CssProvider()
        css.load_from_data(b".fourway-banner { background-color: alpha(@theme_bg_color, 0.96); border-radius: 14px;"
                           b" padding: 14px 30px; box-shadow: 0 6px 24px alpha(black, 0.28); }"
                           b" .fourway-turn { font-size: 15px; font-weight: 600; }")
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self.connect("key-press-event", self._any_key)
        menus.add_actions(self, {"new": self.new_game, "close": self.close, "undo": self.undo,
                                 "easy": lambda: self.choose_level("easy"),
                                 "medium": lambda: self.choose_level("medium"),
                                 "hard": lambda: self.choose_level("hard"),
                                 "computer": lambda: self.vs_computer.set_active(True),
                                 "friend": lambda: self.vs_friend.set_active(True)})
        self.show_all()
        self.after_change(animate=False)
        self.board.grab_focus()

    # State --------------------------------------------------------------------

    def to_move(self):
        return (self.starter + len(self.moves)) % 2

    def human_turn(self):
        return self.mode == "friend" or self.to_move() == RED

    def can_play(self, col):
        return self.grid[col][ROWS - 1] is None

    def save(self):
        self.store.update({"mode": self.mode, "level": self.level, "starter": self.starter,
                           "moves": list(self.moves), "tally": self.tally})
        save_store(self.store)

    def tally_key(self):
        return "friend" if self.mode == "friend" else self.level

    def tally_of(self):
        entry = self.tally.get(self.tally_key())
        if not isinstance(entry, list) or len(entry) != 3 or not all(isinstance(n, int) for n in entry):
            entry = [0, 0, 0]
            self.tally[self.tally_key()] = entry
        return entry

    def update_labels(self):
        red, yellow, draws = self.tally_of()
        if self.mode == "friend":
            self.score_label.set_text(f"Red {red}  ·  Yellow {yellow}  ·  Draws {draws}")
        else:
            self.score_label.set_text(f"You {red}  ·  Computer {yellow}  ·  Draws {draws}")
        self.level_button.set_visible(self.mode == "computer")
        if self.finished:
            self.turn_label.set_text("")
        elif self.thinking:
            self.turn_label.set_text("The computer is thinking…")
        elif self.mode == "computer":
            self.turn_label.set_text("Your turn (red)")
        else:
            self.turn_label.set_text(f"{NAMES[self.to_move()]}'s turn")
        self.undo_button.set_sensitive(bool(self.moves) and not self.thinking)
        self.header.set_subtitle("Against a friend" if self.mode == "friend"
                                 else f"Against the computer, {dict(LEVELS)[self.level].lower()}")

    def outcome(self):
        """(finished, winner or None, cells)."""
        cells = winning_cells(self.grid)
        if cells:
            winner = self.grid[next(iter(cells))[0]][next(iter(cells))[1]]
            return True, winner, cells
        if len(self.moves) == COLUMNS * ROWS:
            return True, None, set()
        return False, None, set()

    def after_change(self, animate=True, record=False):
        self.finished, winner, self.winners = self.outcome()
        self.banner.hide()
        if self.finished:
            if record:
                entry = self.tally_of()
                entry[2 if winner is None else winner] += 1
            if winner is None:
                title = "It's a draw"
            elif self.mode == "friend":
                title = f"{NAMES[winner]} wins!"
            elif winner == RED:
                title = "You win!"
            else:
                title = "The computer wins"
            self.banner_title.set_markup(f"<span size='18000' weight='700'>{title}</span>")
            self.banner.show()
            for child in self.banner.get_children():
                child.show()
        self.update_labels()
        self.board.queue_draw()
        self.save()
        if not self.finished and not self.human_turn():
            self.think()

    # Play ---------------------------------------------------------------------

    def place(self, col):
        row = sum(1 for v in self.grid[col] if v is not None)
        player = self.to_move()
        self.moves.append(col)
        self.grid = grid_of(self.moves, self.starter)

        def landed():
            self.after_change(record=True)
        self.board.drop(col, row, player, landed)
        self.update_labels()

    def human_play(self, col):
        if self.finished or self.thinking or self.board.falling or not self.human_turn():
            return
        if not self.can_play(col):
            Gdk.beep()
            return
        self.place(col)

    def think(self):
        self.thinking = True
        self.think_token += 1
        token = self.think_token
        moves, level = list(self.moves), self.level
        started = time.monotonic()
        self.update_labels()

        def work():
            col = computer_move(moves, level)
            # Never answer faster than a person would see.
            pause = 0.45 - (time.monotonic() - started)
            if pause > 0:
                time.sleep(pause)
            GLib.idle_add(self._thought, token, col)
        threading.Thread(target=work, daemon=True).start()

    def _thought(self, token, col):
        if token != self.think_token:
            return False
        self.thinking = False
        if not self.finished and not self.human_turn() and self.can_play(col):
            self.place(col)
        else:
            self.update_labels()
        return False

    def cancel_thinking(self):
        self.think_token += 1
        self.thinking = False
        self.board.stop_drop()

    def new_game(self):
        self.cancel_thinking()
        if self.moves:
            self.starter = 1 - self.starter
        self.moves = []
        self.grid = grid_of(self.moves, self.starter)
        self.after_change(animate=False)
        self.board.grab_focus()

    def undo(self):
        if not self.moves or self.thinking or self.board.falling:
            return
        self.cancel_thinking()
        was_finished = self.finished
        self.moves.pop()
        # Against the computer, take back its answer and your move together.
        while self.moves and self.mode == "computer" and not self.human_turn():
            self.moves.pop()
        if was_finished:
            # A finished game that is taken back doesn't count.
            finished, winner, _cells = self.outcome()
            if finished:
                entry = self.tally_of()
                index = 2 if winner is None else winner
                entry[index] = max(0, entry[index] - 1)
        self.grid = grid_of(self.moves, self.starter)
        self.after_change(animate=False)

    def _mode_toggled(self, _button):
        mode = "friend" if self.vs_friend.get_active() else "computer"
        if mode != self.mode:
            self.mode = mode
            self.cancel_thinking()
            self.moves = []
            self.grid = grid_of(self.moves, self.starter)
            self.after_change(animate=False)

    def choose_level(self, key):
        self.level_label.set_text(dict(LEVELS)[key])
        if key != self.level:
            self.level = key
            if self.mode == "computer":
                self.new_game()
            else:
                self.update_labels()
                self.save()

    def _any_key(self, _w, event):
        if event.keyval in (Gdk.KEY_Left, Gdk.KEY_Right):
            self.keyboard = True
        return False

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Fourway")
        dialog.format_secondary_text("Fourway is four in a row, part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_Game", [[("New Game", "win.new", "<Ctrl>n"), ("Take Back Move", "win.undo", "<Ctrl>z")],
                   [("Play the Computer", "win.computer", None), ("Play a Friend", "win.friend", None)],
                   [("Easy", "win.easy", None), ("Medium", "win.medium", None), ("Hard", "win.hard", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
    ])


class Fourway(Gtk.Application):
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
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-fourway")
    return Fourway().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
