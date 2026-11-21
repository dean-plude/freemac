# SPDX-License-Identifier: GPL-3.0-or-later
"""Kings: draughts (checkers) on an 8 by 8 board.

Each side has twelve pieces on the dark squares. Pieces move one square
diagonally forward; a piece that reaches the far side becomes a king and
may then move backwards too. Jump over an opponent's piece to take it. Taking
is compulsory, and a piece that can jump again must keep jumping in the same
move. A piece that becomes a king ends its move. You win when the other side
has no move left. Eighty moves in a row with no piece taken and no ordinary
piece moved make a draw.

Play the computer at three levels, or a friend on the same computer. Click a
piece, then the square to move it to; the squares it can reach are marked.

Original freemac code. The game in progress, settings and results are kept
in ~/.local/share/freemac/kings.json.
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

APP_ID = "org.freemac.Kings"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "kings.json")
LEVELS = (("easy", "Easy"), ("medium", "Medium"), ("hard", "Hard"))
RED, BLACK = "r", "b"
NAMES = {RED: "Red", BLACK: "Black"}
QUIET_LIMIT = 80
WIN = 100000
LIGHT = (0.93, 0.85, 0.70)
DARK = (0.55, 0.36, 0.22)
FRAME = (0.36, 0.22, 0.12)
PIECE = {RED: (0.83, 0.18, 0.16), BLACK: (0.17, 0.17, 0.19)}
GOLD = (0.98, 0.78, 0.22)
STEP_TIME = 0.16          # seconds per square when a move is shown


# Engine ------------------------------------------------------------------------

def other(side):
    return BLACK if side == RED else RED


def start_board():
    board = [None] * 64
    for row in range(8):
        for col in range(8):
            if (row + col) % 2 == 1:
                if row < 3:
                    board[row * 8 + col] = BLACK
                elif row > 4:
                    board[row * 8 + col] = RED
    return board


def side_of(piece):
    return piece.lower() if piece else None


def is_king(piece):
    return piece is not None and piece.isupper()


def directions(piece):
    if is_king(piece):
        return ((-1, -1), (-1, 1), (1, -1), (1, 1))
    return ((-1, -1), (-1, 1)) if piece == RED else ((1, -1), (1, 1))


def crown_row(side):
    return 0 if side == RED else 7


def _jumps(board, row, col, piece, path, taken, found):
    more = False
    for dr, dc in directions(piece):
        mr, mc, lr, lc = row + dr, col + dc, row + 2 * dr, col + 2 * dc
        if not (0 <= lr < 8 and 0 <= lc < 8):
            continue
        middle = board[mr * 8 + mc]
        if (middle is None or side_of(middle) == side_of(piece) or (mr, mc) in taken
                or board[lr * 8 + lc] is not None):
            continue
        more = True
        new_path = path + ((lr, lc),)
        new_taken = taken + ((mr, mc),)
        if not is_king(piece) and lr == crown_row(piece):
            found.append((new_path, new_taken))      # crowning ends the move
        else:
            _jumps(board, lr, lc, piece, new_path, new_taken, found)
    if not more and taken:
        found.append((path, taken))


def legal_moves(board, side):
    """Every legal move as (path, taken): path is the squares visited, start first."""
    captures, steps = [], []
    for index, piece in enumerate(board):
        if side_of(piece) != side:
            continue
        row, col = divmod(index, 8)
        board[index] = None                    # the moving piece leaves its square
        _jumps(board, row, col, piece, ((row, col),), (), captures)
        board[index] = piece
        if captures:
            continue
        for dr, dc in directions(piece):
            r, c = row + dr, col + dc
            if 0 <= r < 8 and 0 <= c < 8 and board[r * 8 + c] is None:
                steps.append((((row, col), (r, c)), ()))
    return captures if captures else steps


def apply(board, move):
    """A new board after the move, and whether it was quiet (no take, no ordinary piece moved)."""
    path, taken = move
    board = list(board)
    (r0, c0), (r1, c1) = path[0], path[-1]
    piece = board[r0 * 8 + c0]
    board[r0 * 8 + c0] = None
    for r, c in taken:
        board[r * 8 + c] = None
    quiet = not taken and is_king(piece)
    if not is_king(piece) and r1 == crown_row(piece):
        piece = piece.upper()
    board[r1 * 8 + c1] = piece
    return board, quiet


CENTRE = {(3, 2), (3, 4), (4, 3), (4, 5), (3, 3), (4, 4)}


def evaluate(board, side):
    score = 0
    for index, piece in enumerate(board):
        if piece is None:
            continue
        row, col = divmod(index, 8)
        if is_king(piece):
            value = 175
        else:
            advance = (7 - row) if side_of(piece) == RED else row
            value = 100 + advance * 4
            if row == (7 if side_of(piece) == RED else 0):
                value += 8           # guarding the home row
        if (row, col) in CENTRE:
            value += 6
        score += value if side_of(piece) == side else -value
    return score


class OutOfTime(Exception):
    pass


class Search:
    def __init__(self, deadline):
        self.deadline = deadline
        self.nodes = 0

    def negamax(self, board, side, depth, alpha, beta, ply):
        self.nodes += 1
        if self.nodes & 511 == 0 and time.monotonic() > self.deadline:
            raise OutOfTime()
        moves = legal_moves(board, side)
        if not moves:
            return -WIN + ply
        capturing = bool(moves[0][1])
        if depth <= 0 and (not capturing or depth < -6):
            return evaluate(board, side)
        moves.sort(key=lambda m: -len(m[1]))
        best = -WIN * 2
        for move in moves:
            child, _quiet = apply(board, move)
            score = -self.negamax(child, other(side), depth - 1, -beta, -alpha, ply + 1)
            if score > best:
                best = score
            if score > alpha:
                alpha = score
            if alpha >= beta:
                break
        return best

    def choose(self, board, side, max_depth, rng):
        moves = legal_moves(board, side)
        if len(moves) == 1:
            return moves[0]
        rng.shuffle(moves)
        moves.sort(key=lambda m: -len(m[1]))
        best = None
        for depth in range(1, max_depth + 1):
            try:
                alpha = -WIN * 2
                choice = None
                order = moves if best is None else [best] + [m for m in moves if m != best]
                for move in order:
                    child, _quiet = apply(board, move)
                    score = -self.negamax(child, other(side), depth - 1, -WIN * 2, -alpha, 1)
                    if score > alpha:
                        alpha, choice = score, move
            except OutOfTime:
                break
            best = choice
            if abs(alpha) >= WIN - 200:
                break
        return best if best is not None else moves[0]


def computer_move(board, side, level, rng=random):
    moves = legal_moves(board, side)
    if level == "easy":
        if rng.random() < 0.45:
            return rng.choice(moves)
        return Search(time.monotonic() + 0.3).choose(board, side, 2, rng)
    if level == "medium":
        return Search(time.monotonic() + 0.8).choose(board, side, 4, rng)
    return Search(time.monotonic() + 1.6).choose(board, side, 30, rng)


def replay(history, starter):
    """Board, side to move and quiet count after a list of moves, or None if one isn't legal."""
    board, side, quiet = start_board(), starter, 0
    for item in history:
        try:
            path = tuple((int(r), int(c)) for r, c in item)
        except (TypeError, ValueError):
            return None
        match = [m for m in legal_moves(board, side) if m[0] == path]
        if not match:
            return None
        board, was_quiet = apply(board, match[0])
        quiet = quiet + 1 if was_quiet else 0
        side = other(side)
    return board, side, quiet


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

class Table(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(can_focus=True)
        self.window = window
        self.selected = None
        self.cursor = None
        self.moving = None           # {"piece", "path", "taken", "t", "done", "hidden"}
        self.timer = 0
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.KEY_PRESS_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("key-press-event", self._key)

    def layout(self):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        size = max(80, min(w, h) - 36)
        cell = size / 8.6
        board = cell * 8
        x0 = (w - board) / 2
        y0 = (h - board) / 2
        return cell, x0, y0

    def square_at(self, x, y):
        cell, x0, y0 = self.layout()
        col, row = int((x - x0) // cell), int((y - y0) // cell)
        if 0 <= row < 8 and 0 <= col < 8 and x >= x0 and y >= y0:
            return row, col
        return None

    def _press(self, _w, event):
        self.grab_focus()
        if event.button != 1 or event.type != Gdk.EventType.BUTTON_PRESS:
            return True
        square = self.square_at(event.x, event.y)
        if square:
            self.window.keyboard = False
            self.click(square)
        return True

    def click(self, square):
        window = self.window
        if not window.human_turn() or window.finished or window.thinking or self.moving:
            return
        moves = window.moves_now()
        starts = {m[0][0] for m in moves}
        if square in starts:
            self.selected = None if self.selected == square else square
            self.queue_draw()
            return
        if self.selected:
            chosen = [m for m in moves if m[0][0] == self.selected and m[0][-1] == square]
            if chosen:
                chosen.sort(key=lambda m: -len(m[1]))      # the longer jump if two paths end here
                self.selected = None
                window.play(chosen[0])
                return
        if window.board[square[0] * 8 + square[1]] and side_of(window.board[square[0] * 8 + square[1]]) == \
                window.side and moves and moves[0][1]:
            window.flash("You must take: a piece that can jump has to.")
        self.selected = None
        self.queue_draw()

    def _key(self, _w, event):
        key = event.keyval
        steps = {Gdk.KEY_Left: (0, -1), Gdk.KEY_Right: (0, 1), Gdk.KEY_Up: (-1, 0), Gdk.KEY_Down: (1, 0)}
        if key in steps:
            self.window.keyboard = True
            row, col = self.cursor or (5, 0)
            dr, dc = steps[key]
            self.cursor = (max(0, min(7, row + dr)), max(0, min(7, col + dc)))
            self.queue_draw()
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space) and self.cursor:
            self.click(self.cursor)
            return True
        if key == Gdk.KEY_Escape and self.selected:
            self.selected = None
            self.queue_draw()
            return True
        return False

    def show_move(self, piece, move, done):
        path, taken = move
        self.moving = {"piece": piece, "path": path, "taken": taken, "t": 0.0, "done": done,
                       "start": time.monotonic()}
        if not self.timer:
            self.timer = GLib.timeout_add(16, self._tick)
        self.queue_draw()

    def stop(self):
        self.moving = None
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = 0
        self.queue_draw()

    def _tick(self):
        moving = self.moving
        if not moving:
            self.timer = 0
            return False
        legs = len(moving["path"]) - 1
        moving["t"] = (time.monotonic() - moving["start"]) / (STEP_TIME * (1.4 if moving["taken"] else 1.0))
        if moving["t"] >= legs:
            self.timer = 0
            self.moving = None
            self.queue_draw()
            moving["done"]()
            return False
        self.queue_draw()
        return True

    def centre(self, row, col):
        cell, x0, y0 = self.layout()
        return x0 + cell * (col + 0.5), y0 + cell * (row + 0.5)

    def _piece(self, cr, x, y, cell, piece, alpha=1.0):
        side = side_of(piece)
        red, green, blue = PIECE[side]
        r = cell * 0.39
        cr.new_path()
        cr.arc(x + cell * 0.03, y + cell * 0.05, r, 0, 2 * math.pi)
        cr.set_source_rgba(0, 0, 0, 0.30 * alpha)
        cr.fill()
        cr.arc(x, y, r, 0, 2 * math.pi)
        cr.set_source_rgba(red * 0.75, green * 0.75, blue * 0.75, alpha)
        cr.fill()
        cr.arc(x, y - cell * 0.03, r * 0.94, 0, 2 * math.pi)
        cr.set_source_rgba(red, green, blue, alpha)
        cr.fill()
        lift = 0.10 if side == RED else 0.16
        for ring in (0.72, 0.5):
            cr.arc(x, y - cell * 0.03, r * ring, 0, 2 * math.pi)
            cr.set_source_rgba(min(1, red + lift), min(1, green + lift), min(1, blue + lift), 0.55 * alpha)
            cr.set_line_width(max(1.0, cell * 0.025))
            cr.stroke()
        if is_king(piece):
            # A small crown: a band with three points.
            w, h = r * 0.95, r * 0.6
            left, base = x - w / 2, y - cell * 0.03 + h * 0.45
            cr.move_to(left, base)
            cr.line_to(left, base - h * 0.55)
            cr.line_to(left + w * 0.18, base - h * 0.25)
            cr.line_to(left + w * 0.5, base - h)
            cr.line_to(left + w * 0.82, base - h * 0.25)
            cr.line_to(left + w, base - h * 0.55)
            cr.line_to(left + w, base)
            cr.close_path()
            cr.set_source_rgba(*GOLD, alpha)
            cr.fill_preserve()
            cr.set_source_rgba(0.55, 0.38, 0.05, alpha)
            cr.set_line_width(max(1.0, cell * 0.02))
            cr.stroke()

    def _draw(self, _w, cr):
        window = self.window
        cell, x0, y0 = self.layout()
        size = cell * 8
        border = cell * 0.3
        cr.new_path()
        cr.rectangle(x0 - border, y0 - border, size + 2 * border, size + 2 * border)
        cr.set_source_rgb(*FRAME)
        cr.fill()
        for row in range(8):
            for col in range(8):
                cr.rectangle(x0 + col * cell, y0 + row * cell, cell + 0.5, cell + 0.5)
                cr.set_source_rgb(*(DARK if (row + col) % 2 else LIGHT))
                cr.fill()
        # The last move.
        if window.last and not self.moving:
            for row, col in (window.last[0], window.last[-1]):
                cr.rectangle(x0 + col * cell, y0 + row * cell, cell, cell)
                cr.set_source_rgba(1.0, 0.85, 0.35, 0.28)
                cr.fill()
        moves = window.moves_now() if (window.human_turn() and not window.finished and not self.moving
                                       and not window.thinking) else []
        # Pieces that must take are ringed.
        if moves and moves[0][1] and not self.selected:
            for start in {m[0][0] for m in moves}:
                x, y = self.centre(*start)
                cr.new_path()
                cr.arc(x, y, cell * 0.46, 0, 2 * math.pi)
                cr.set_source_rgba(1, 0.85, 0.3, 0.9)
                cr.set_line_width(max(2.0, cell * 0.05))
                cr.stroke()
        if self.selected:
            row, col = self.selected
            cr.rectangle(x0 + col * cell, y0 + row * cell, cell, cell)
            cr.set_source_rgba(0.35, 0.65, 1.0, 0.45)
            cr.fill()
        hidden = set()
        moving = self.moving
        if moving:
            hidden.add(moving["path"][0])
            done_legs = int(moving["t"])
            hidden.update(moving["taken"][:done_legs + (1 if moving["t"] - done_legs > 0.5 else 0)])
        board = window.shown_board
        for index, piece in enumerate(board):
            if piece and divmod(index, 8) not in hidden:
                x, y = self.centre(*divmod(index, 8))
                self._piece(cr, x, y, cell, piece)
        if moving:
            leg = min(int(moving["t"]), len(moving["path"]) - 2)
            frac = moving["t"] - leg
            frac = frac * frac * (3 - 2 * frac)
            (ar, ac), (br, bc) = moving["path"][leg], moving["path"][leg + 1]
            ax, ay = self.centre(ar, ac)
            bx, by = self.centre(br, bc)
            hop = math.sin(frac * math.pi) * cell * (0.35 if moving["taken"] else 0.12)
            self._piece(cr, ax + (bx - ax) * frac, ay + (by - ay) * frac - hop, cell * 1.06, moving["piece"])
        # Where the chosen piece can go.
        if self.selected:
            for path, taken in moves:
                if path[0] == self.selected:
                    x, y = self.centre(*path[-1])
                    cr.new_path()
                    cr.arc(x, y, cell * 0.14, 0, 2 * math.pi)
                    cr.set_source_rgba(0.2, 0.55, 1.0, 0.85)
                    cr.fill()
                    for r, c in taken:
                        tx, ty = self.centre(r, c)
                        cr.new_path()
                        cr.move_to(tx - cell * 0.15, ty - cell * 0.15)
                        cr.line_to(tx + cell * 0.15, ty + cell * 0.15)
                        cr.move_to(tx + cell * 0.15, ty - cell * 0.15)
                        cr.line_to(tx - cell * 0.15, ty + cell * 0.15)
                        cr.set_source_rgba(1, 1, 1, 0.85)
                        cr.set_line_width(max(2.0, cell * 0.05))
                        cr.stroke()
        if self.has_focus() and window.keyboard and self.cursor:
            row, col = self.cursor
            cr.rectangle(x0 + col * cell + 2, y0 + row * cell + 2, cell - 4, cell - 4)
            cr.set_source_rgba(0.04, 0.49, 1.0, 0.9)
            cr.set_line_width(3)
            cr.stroke()
        return False


# Window ------------------------------------------------------------------------

class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Kings")
        self.set_default_size(760, 760)
        self.store = load_store()
        store = self.store
        self.mode = "friend" if store.get("mode") == "friend" else "computer"
        self.level = store.get("level") if store.get("level") in dict(LEVELS) else "medium"
        self.starter = store.get("starter") if store.get("starter") in (RED, BLACK) else RED
        tally = store.get("tally")
        self.tally = tally if isinstance(tally, dict) else {}
        history = store.get("history")
        state = replay(history, self.starter) if isinstance(history, list) else None
        if state is None:
            history, state = [], replay([], self.starter)
        self.history = [[tuple(sq) for sq in path] for path in history]
        self.board, self.side, self.quiet = state
        self.shown_board = self.board
        self.last = self.history[-1] if self.history else None
        self.thinking = False
        self.think_token = 0
        self.keyboard = False
        self.finished = False
        self.flash_id = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Kings")
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
        self.turn_label.get_style_context().add_class("kings-turn")
        self.score_label = Gtk.Label()
        self.score_label.get_style_context().add_class("dim-label")
        bar.pack_start(self.turn_label, False, False, 0)
        bar.pack_start(self.score_label, False, False, 0)
        box.pack_start(bar, False, False, 0)
        overlay = Gtk.Overlay()
        self.table = Table(self)
        self.table.set_vexpand(True)
        overlay.add(self.table)
        self.banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                              halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.banner.get_style_context().add_class("kings-banner")
        self.banner_title = Gtk.Label()
        self.banner_text = Gtk.Label(justify=Gtk.Justification.CENTER)
        again = Gtk.Button(label="Play Again")
        again.get_style_context().add_class("suggested-action")
        again.set_halign(Gtk.Align.CENTER)
        again.connect("clicked", lambda _b: self.new_game())
        self.banner.pack_start(self.banner_title, False, False, 0)
        self.banner.pack_start(self.banner_text, False, False, 0)
        self.banner.pack_start(again, False, False, 0)
        self.banner.set_no_show_all(True)
        overlay.add_overlay(self.banner)
        self.note = Gtk.Label(halign=Gtk.Align.CENTER, valign=Gtk.Align.END)
        self.note.get_style_context().add_class("kings-note")
        self.note.set_margin_bottom(6)
        self.note.set_no_show_all(True)
        overlay.add_overlay(self.note)
        box.pack_start(overlay, True, True, 0)

        css = Gtk.CssProvider()
        css.load_from_data(b".kings-banner { background-color: alpha(@theme_bg_color, 0.96); border-radius: 14px;"
                           b" padding: 18px 34px; box-shadow: 0 6px 24px alpha(black, 0.3); }"
                           b" .kings-turn { font-size: 15px; font-weight: 600; }"
                           b" .kings-note { background-color: alpha(black, 0.72); color: white;"
                           b" border-radius: 8px; padding: 6px 12px; }")
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        menus.add_actions(self, {"new": self.new_game, "close": self.close, "undo": self.undo,
                                 "easy": lambda: self.choose_level("easy"),
                                 "medium": lambda: self.choose_level("medium"),
                                 "hard": lambda: self.choose_level("hard"),
                                 "computer": lambda: self.vs_computer.set_active(True),
                                 "friend": lambda: self.vs_friend.set_active(True)})
        self.show_all()
        self.after_change()
        self.table.grab_focus()

    # State --------------------------------------------------------------------

    def human_turn(self):
        return self.mode == "friend" or self.side == RED

    def moves_now(self):
        return legal_moves(self.board, self.side)

    def save(self):
        self.store.update({"mode": self.mode, "level": self.level, "starter": self.starter,
                           "history": [[list(sq) for sq in path] for path in self.history],
                           "tally": self.tally})
        save_store(self.store)

    def tally_of(self):
        key = "friend" if self.mode == "friend" else self.level
        entry = self.tally.get(key)
        if not isinstance(entry, list) or len(entry) != 3 or not all(isinstance(n, int) for n in entry):
            entry = [0, 0, 0]
            self.tally[key] = entry
        return entry

    def counts(self):
        red = sum(1 for p in self.board if side_of(p) == RED)
        black = sum(1 for p in self.board if side_of(p) == BLACK)
        return red, black

    def outcome(self):
        """(finished, winner or None)."""
        if not self.moves_now():
            return True, other(self.side)
        if self.quiet >= QUIET_LIMIT:
            return True, None
        return False, None

    def update_labels(self):
        red, black, draws = self.tally_of()
        if self.mode == "friend":
            self.score_label.set_text(f"Red {red}  ·  Black {black}  ·  Draws {draws}")
        else:
            self.score_label.set_text(f"You {red}  ·  Computer {black}  ·  Draws {draws}")
        self.level_button.set_visible(self.mode == "computer")
        mine, theirs = self.counts()
        pieces = f"   {mine} red, {theirs} black"
        if self.finished:
            self.turn_label.set_text("")
        elif self.thinking:
            self.turn_label.set_text("The computer is thinking…" + pieces)
        elif self.mode == "computer":
            self.turn_label.set_text("Your turn (red)" + pieces)
        else:
            self.turn_label.set_text(f"{NAMES[self.side]}'s turn" + pieces)
        self.undo_button.set_sensitive(bool(self.history) and not self.thinking)
        self.header.set_subtitle("Against a friend" if self.mode == "friend"
                                 else f"Against the computer, {dict(LEVELS)[self.level].lower()}")

    def after_change(self, record=False):
        self.shown_board = self.board
        self.finished, winner = self.outcome()
        self.banner.hide()
        if self.finished:
            if record:
                entry = self.tally_of()
                entry[2 if winner is None else (0 if winner == RED else 1)] += 1
            if winner is None:
                title, text = "It's a draw", "Eighty moves went by with no piece taken."
            elif self.mode == "friend":
                title, text = f"{NAMES[winner]} wins!", f"{NAMES[other(winner)]} has no move left."
            elif winner == RED:
                title, text = "You win!", "The computer has no move left."
            else:
                title, text = "The computer wins", "You have no move left."
            self.banner_title.set_markup(f"<span size='18000' weight='700'>{title}</span>")
            self.banner_text.set_text(text)
            self.banner.show()
            for child in self.banner.get_children():
                child.show()
        self.update_labels()
        self.table.queue_draw()
        self.save()
        if not self.finished and not self.human_turn():
            self.think()

    def flash(self, text):
        self.note.set_text(text)
        self.note.show()
        if self.flash_id:
            GLib.source_remove(self.flash_id)
        self.flash_id = GLib.timeout_add(2600, self._hide_flash)

    def _hide_flash(self):
        self.flash_id = 0
        self.note.hide()
        return False

    # Play ---------------------------------------------------------------------

    def play(self, move):
        path, _taken = move
        piece = self.board[path[0][0] * 8 + path[0][1]]
        before = self.board
        self.board, quiet = apply(self.board, move)
        self.quiet = self.quiet + 1 if quiet else 0
        self.side = other(self.side)
        self.history.append(list(path))
        self.last = list(path)
        self.shown_board = before

        def done():
            self.after_change(record=True)
        self.table.show_move(piece, move, done)
        self.update_labels()

    def think(self):
        self.thinking = True
        self.think_token += 1
        token = self.think_token
        board, side, level = list(self.board), self.side, self.level
        started = time.monotonic()
        self.update_labels()

        def work():
            move = computer_move(board, side, level)
            pause = 0.5 - (time.monotonic() - started)
            if pause > 0:
                time.sleep(pause)
            GLib.idle_add(self._thought, token, move)
        threading.Thread(target=work, daemon=True).start()

    def _thought(self, token, move):
        if token != self.think_token:
            return False
        self.thinking = False
        if not self.finished and not self.human_turn() and move in self.moves_now():
            self.play(move)
        else:
            self.update_labels()
        return False

    def cancel(self):
        self.think_token += 1
        self.thinking = False
        self.table.stop()
        self.table.selected = None

    def restart(self):
        self.history = []
        self.board, self.side, self.quiet = replay([], self.starter)
        self.last = None
        self.after_change()

    def new_game(self):
        self.cancel()
        if self.history:
            self.starter = other(self.starter)
        self.restart()
        self.table.grab_focus()

    def undo(self):
        if not self.history or self.thinking or self.table.moving:
            return
        was_finished, winner = self.outcome()
        self.cancel()
        self.history.pop()
        while self.history and self.mode == "computer" and len(self.history) % 2 != (0 if self.starter == RED
                                                                                         else 1):
            self.history.pop()
        if was_finished:
            entry = self.tally_of()
            index = 2 if winner is None else (0 if winner == RED else 1)
            entry[index] = max(0, entry[index] - 1)
        state = replay(self.history, self.starter)
        self.board, self.side, self.quiet = state
        self.last = self.history[-1] if self.history else None
        self.after_change()

    def _mode_toggled(self, _button):
        mode = "friend" if self.vs_friend.get_active() else "computer"
        if mode != self.mode:
            self.mode = mode
            self.cancel()
            self.restart()

    def choose_level(self, key):
        self.level_label.set_text(dict(LEVELS)[key])
        if key != self.level:
            self.level = key
            if self.mode == "computer":
                self.new_game()
            else:
                self.update_labels()
                self.save()

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Kings")
        dialog.format_secondary_text("Kings is draughts (checkers), part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_Game", [[("New Game", "win.new", "<Ctrl>n"), ("Take Back Move", "win.undo", "<Ctrl>z")],
                   [("Play the Computer", "win.computer", None), ("Play a Friend", "win.friend", None)],
                   [("Easy", "win.easy", None), ("Medium", "win.medium", None), ("Hard", "win.hard", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
    ])


class Kings(Gtk.Application):
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
    GLib.set_prgname("freemac-kings")
    return Kings().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
