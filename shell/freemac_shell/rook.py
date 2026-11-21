# SPDX-License-Identifier: GPL-3.0-or-later
"""Rook: play chess against the computer, or with a friend on the same screen.

Click a piece to see where it can go, then click where you want it, or drag
it there. Against the computer, pick Easy, Medium or Hard and which side to
play; Hint shows a good move and Undo takes your last move back. The game is
kept as you play, so it's still there next time.

Original freemac code. The rules and the computer player are in
rook_engine.py; the computer thinks in a thread so the window stays awake.
The pieces are the chess symbols in DejaVu Sans, filled and outlined.
"""
import json
import os
import random
import sys
import threading
import time

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402
from . import rook_engine as chess  # noqa: E402

APP_ID = "org.freemac.Rook"
GLYPH = {"k": "♚", "q": "♛", "r": "♜", "b": "♝", "n": "♞", "p": "♟"}
LIGHT = (0.92, 0.90, 0.85)
DARK = (0.55, 0.64, 0.71)
LEVEL_NAMES = {"easy": "Easy", "medium": "Medium", "hard": "Hard"}
SLIDE = 0.16  # seconds a move takes to slide

CSS = b"""
.rook-side { padding: 18px; border-left: 1px solid alpha(currentColor, 0.1); }
.rook-status { font-size: 1.35em; font-weight: 600; }
.rook-small { color: alpha(currentColor, 0.6); }
.rook-moves { font-feature-settings: "tnum"; }
.rook-taken { font-size: 1.3em; }
.rook-new-title { font-weight: 600; }
.rook-promote button { font-size: 30px; padding: 0 6px; }
"""


def store_path():
    folder = os.path.join(GLib.get_user_data_dir(), "freemac")
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, "rook.json")


def draw_piece(cr, piece, x, y, size):
    """A piece centred in the square at x, y."""
    layout = PangoCairo.create_layout(cr)
    font = Pango.FontDescription("DejaVu Sans")
    font.set_absolute_size(size * 0.8 * Pango.SCALE)
    layout.set_font_description(font)
    layout.set_text(GLYPH[piece.lower()] + "︎", -1)
    _ink, logical = layout.get_pixel_extents()
    cr.save()
    cr.move_to(x + (size - logical.width) / 2, y + (size - logical.height) / 2 + size * 0.02)
    PangoCairo.layout_path(cr, layout)
    if piece.isupper():
        cr.set_source_rgb(0.99, 0.99, 0.97)
        cr.fill_preserve()
        cr.set_source_rgb(0.15, 0.15, 0.17)
    else:
        cr.set_source_rgb(0.12, 0.12, 0.14)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.6)
    cr.set_line_width(max(1.0, size / 42))
    cr.set_line_join(1)
    cr.stroke()
    cr.restore()


class Board(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(hexpand=True, vexpand=True)
        self.window = window
        self.flipped = False
        self.selected = None
        self.drag = None          # (square, x, y) while dragging a piece
        self.press_at = None
        self.hint = None
        self.slide = None         # (piece, from, to, started)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)

    def geometry(self):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        size = int(min(width, height) - 32) // 8
        size = max(size, 8)
        x = (width - size * 8) // 2
        y = (height - size * 8) // 2
        return x, y, size

    def square_box(self, sq):
        x, y, size = self.geometry()
        f, r = sq % 8, sq // 8
        if self.flipped:
            f, r = 7 - f, 7 - r
        return x + f * size, y + (7 - r) * size, size

    def square_at(self, px, py):
        x, y, size = self.geometry()
        f, r = int((px - x) // size), 7 - int((py - y) // size)
        if not (0 <= f < 8 and 0 <= r < 8):
            return None
        if self.flipped:
            f, r = 7 - f, 7 - r
        return r * 8 + f

    def start_slide(self, piece, frm, to):
        self.slide = (piece, frm, to, time.monotonic())
        self.add_tick_callback(self._tick)

    def _tick(self, _w, _clock):
        self.queue_draw()
        if self.slide and time.monotonic() - self.slide[3] >= SLIDE:
            self.slide = None
            self.queue_draw()
            return False
        return True

    def _draw(self, _w, cr):
        w = self.window
        pos = w.position
        x0, y0, size = self.geometry()
        # A soft frame under the board.
        cr.set_source_rgba(0, 0, 0, 0.18)
        cr.rectangle(x0 - 1, y0 + 2, size * 8 + 2, size * 8 + 2)
        cr.fill()
        last = w.moves[-1][0] if w.moves else None
        legal_to = {m[1] for m in w.legal if m[0] == self.selected} if self.selected is not None else set()
        check_sq = pos.king(pos.turn) if pos.in_check() else None
        for sq in range(64):
            x, y, _s = self.square_box(sq)
            light = (sq % 8 + sq // 8) % 2 == 1
            cr.set_source_rgb(*(LIGHT if light else DARK))
            cr.rectangle(x, y, size, size)
            cr.fill()
            if last and sq in (last[0], last[1]):
                cr.set_source_rgba(1.0, 0.86, 0.3, 0.45)
                cr.rectangle(x, y, size, size)
                cr.fill()
            if self.hint and sq in (self.hint[0], self.hint[1]):
                cr.set_source_rgba(0.2, 0.78, 0.35, 0.5)
                cr.rectangle(x, y, size, size)
                cr.fill()
            if sq == self.selected:
                cr.set_source_rgba(0.0, 0.48, 1.0, 0.35)
                cr.rectangle(x, y, size, size)
                cr.fill()
            if sq == check_sq:
                grad = cairo.RadialGradient(x + size / 2, y + size / 2, size * 0.1,
                                            x + size / 2, y + size / 2, size * 0.7)
                grad.add_color_stop_rgba(0, 1, 0.15, 0.1, 0.9)
                grad.add_color_stop_rgba(1, 1, 0.15, 0.1, 0)
                cr.set_source(grad)
                cr.rectangle(x, y, size, size)
                cr.fill()
        # Coordinates, small, in the corners of the edge squares.
        layout = PangoCairo.create_layout(cr)
        font = Pango.FontDescription("Inter Bold")
        font.set_absolute_size(max(8, size * 0.16) * Pango.SCALE)
        layout.set_font_description(font)
        for i in range(8):
            f_sq = i if not self.flipped else 7 - i
            sq = (0 if not self.flipped else 7) * 8 + f_sq
            x, y, _s = self.square_box(sq)
            layout.set_text(chess.FILES[f_sq], -1)
            light = (sq % 8 + sq // 8) % 2 == 1
            cr.set_source_rgb(*(DARK if light else LIGHT))
            tw, th = layout.get_pixel_size()
            cr.move_to(x + size - tw - 3, y + size - th - 1)
            PangoCairo.show_layout(cr, layout)
            r_sq = i if not self.flipped else 7 - i
            sq = r_sq * 8 + (0 if not self.flipped else 7)
            x, y, _s = self.square_box(sq)
            layout.set_text(str(r_sq + 1), -1)
            light = (sq % 8 + sq // 8) % 2 == 1
            cr.set_source_rgb(*(DARK if light else LIGHT))
            cr.move_to(x + 3, y + 1)
            PangoCairo.show_layout(cr, layout)
        # Pieces
        hidden = set()
        if self.drag:
            hidden.add(self.drag[0])
        if self.slide:
            hidden.add(self.slide[2])
        for sq, piece in enumerate(pos.board):
            if piece == "." or sq in hidden:
                continue
            x, y, _s = self.square_box(sq)
            draw_piece(cr, piece, x, y, size)
        # Where the chosen piece can go.
        for sq in legal_to:
            x, y, _s = self.square_box(sq)
            cr.set_source_rgba(0.1, 0.1, 0.15, 0.28)
            if pos.board[sq] != "." or (pos.board[self.selected].lower() == "p" and sq == pos.ep):
                cr.set_line_width(size * 0.08)
                cr.arc(x + size / 2, y + size / 2, size * 0.44, 0, 6.2832)
                cr.stroke()
            else:
                cr.arc(x + size / 2, y + size / 2, size * 0.15, 0, 6.2832)
                cr.fill()
        if self.slide:
            piece, frm, to, started = self.slide
            t = min(1.0, (time.monotonic() - started) / SLIDE)
            t = 1 - (1 - t) ** 3
            fx, fy, _s = self.square_box(frm)
            tx, ty, _s = self.square_box(to)
            draw_piece(cr, piece, fx + (tx - fx) * t, fy + (ty - fy) * t, size)
        if self.drag:
            sq, px, py = self.drag
            draw_piece(cr, pos.board[sq], px - size / 2, py - size / 2, size)

    def _press(self, _w, event):
        if event.button != 1 or event.type != Gdk.EventType.BUTTON_PRESS:
            return False
        w = self.window
        sq = self.square_at(event.x, event.y)
        if sq is None or not w.my_turn():
            return True
        piece = w.position.board[sq]
        if self.selected is not None and any(m[0] == self.selected and m[1] == sq for m in w.legal):
            w.try_move(self.selected, sq)
            return True
        if piece != "." and chess.colour(piece) == w.position.turn:
            self.selected = sq
            self.press_at = (sq, event.x, event.y)
        else:
            self.selected = None
        self.queue_draw()
        return True

    def _motion(self, _w, event):
        if not self.press_at or not event.state & Gdk.ModifierType.BUTTON1_MASK:
            return False
        sq, px, py = self.press_at
        if self.drag or abs(event.x - px) + abs(event.y - py) > 4:
            self.drag = (sq, event.x, event.y)
            self.queue_draw()
        return True

    def _release(self, _w, event):
        if event.button != 1:
            return False
        drag, self.drag = self.drag, None
        self.press_at = None
        if drag:
            to = self.square_at(event.x, event.y)
            if to is not None and any(m[0] == drag[0] and m[1] == to for m in self.window.legal):
                self.window.try_move(drag[0], to, slide=False)
            self.queue_draw()
        return True


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Rook")
        self.set_default_size(980, 700)
        self.mode = "computer"       # or "friends"
        self.level = "medium"
        self.human = chess.WHITE     # the side you play against the computer
        self.positions = [chess.Position()]
        self.moves = []              # (move, san)
        self.legal = self.position.legal_moves()
        self.thinking = 0            # the game's serial number while the computer thinks
        self.serial = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Rook")
        self.header = header
        self.set_titlebar(header)
        self.new_button = Gtk.MenuButton(label="New Game")
        self.new_button.set_popover(self._build_new_game())
        header.pack_start(self.new_button)
        self.undo_button = Gtk.Button.new_from_icon_name("edit-undo-symbolic", Gtk.IconSize.BUTTON)
        self.undo_button.set_tooltip_text("Take Back (⌘Z)")
        self.undo_button.connect("clicked", lambda _b: self.undo())
        header.pack_start(self.undo_button)
        flip = Gtk.Button(label="Flip Board")
        flip.connect("clicked", lambda _b: self.flip())
        header.pack_end(flip)
        self.hint_button = Gtk.Button(label="Hint")
        self.hint_button.connect("clicked", lambda _b: self.show_hint())
        header.pack_end(self.hint_button)

        box = Gtk.Box()
        self.add(box)
        self.board = Board(self)
        box.pack_start(self.board, True, True, 0)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        side.get_style_context().add_class("rook-side")
        side.set_size_request(250, -1)
        self.status = Gtk.Label(xalign=0, wrap=True)
        self.status.get_style_context().add_class("rook-status")
        side.pack_start(self.status, False, False, 0)
        self.players = Gtk.Label(xalign=0, wrap=True)
        self.players.get_style_context().add_class("rook-small")
        side.pack_start(self.players, False, False, 0)
        self.again = Gtk.Button(label="Play Again", halign=Gtk.Align.START)
        self.again.get_style_context().add_class("suggested-action")
        self.again.connect("clicked", lambda _b: self.new_game(self.mode, self.level, self.human_choice))
        side.pack_start(self.again, False, False, 0)
        self.taken_top = Gtk.Label(xalign=0)
        self.taken_top.get_style_context().add_class("rook-taken")
        self.taken_bottom = Gtk.Label(xalign=0)
        self.taken_bottom.get_style_context().add_class("rook-taken")
        side.pack_start(self.taken_top, False, False, 0)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        self.move_list = Gtk.Label(xalign=0, yalign=0, selectable=True)
        self.move_list.get_style_context().add_class("rook-moves")
        scroller.add(self.move_list)
        self.scroller = scroller
        side.pack_start(scroller, True, True, 0)
        side.pack_start(self.taken_bottom, False, False, 0)
        box.pack_start(side, False, False, 0)

        self.human_choice = "white"
        menus.add_actions(self, {"new": lambda: self.new_button.set_active(True), "undo": self.undo,
                                 "hint": self.show_hint, "flip": self.flip, "close": self.close})
        self.connect("destroy", lambda _w: self.save())
        self.show_all()
        self.load()

    @property
    def position(self):
        return self.positions[-1]

    # -- starting a game --

    def _build_new_game(self):
        popover = Gtk.Popover()
        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        for side in ("start", "end", "top", "bottom"):
            getattr(grid, f"set_margin_{side}")(14)
        title = Gtk.Label(label="New Game", xalign=0)
        title.get_style_context().add_class("rook-new-title")
        grid.attach(title, 0, 0, 2, 1)
        self.vs_computer = Gtk.RadioButton.new_with_label(None, "Play the computer")
        self.vs_friend = Gtk.RadioButton.new_with_label_from_widget(self.vs_computer, "Play a friend here")
        grid.attach(self.vs_computer, 0, 1, 2, 1)
        grid.attach(self.vs_friend, 0, 2, 2, 1)
        grid.attach(Gtk.Label(label="Level", xalign=1), 0, 3, 1, 1)
        self.level_combo = Gtk.ComboBoxText()
        for key, label in LEVEL_NAMES.items():
            self.level_combo.append(key, label)
        self.level_combo.set_active_id("medium")
        grid.attach(self.level_combo, 1, 3, 1, 1)
        grid.attach(Gtk.Label(label="Play as", xalign=1), 0, 4, 1, 1)
        self.side_combo = Gtk.ComboBoxText()
        for key, label in (("white", "White"), ("black", "Black"), ("random", "Either")):
            self.side_combo.append(key, label)
        self.side_combo.set_active_id("white")
        grid.attach(self.side_combo, 1, 4, 1, 1)

        def mode_changed(*_a):
            on = self.vs_computer.get_active()
            self.level_combo.set_sensitive(on)
            self.side_combo.set_sensitive(on)
        self.vs_computer.connect("toggled", mode_changed)
        start = Gtk.Button(label="Start")
        start.get_style_context().add_class("suggested-action")
        start.connect("clicked", self._start_clicked)
        grid.attach(start, 0, 5, 2, 1)
        popover.add(grid)
        grid.show_all()
        popover.connect("show", lambda _p: self._fill_new_game())
        return popover

    def _fill_new_game(self):
        (self.vs_computer if self.mode == "computer" else self.vs_friend).set_active(True)
        self.level_combo.set_active_id(self.level)
        self.side_combo.set_active_id(self.human_choice)

    def _start_clicked(self, _button):
        self.new_button.get_popover().popdown()
        mode = "computer" if self.vs_computer.get_active() else "friends"
        self.new_game(mode, self.level_combo.get_active_id() or "medium", self.side_combo.get_active_id() or "white")

    def new_game(self, mode, level, human_choice):
        self.serial += 1
        self.thinking = 0
        self.mode, self.level, self.human_choice = mode, level, human_choice
        if human_choice == "random":
            self.human = random.choice((chess.WHITE, chess.BLACK))
        else:
            self.human = chess.BLACK if human_choice == "black" else chess.WHITE
        self.positions = [chess.Position()]
        self.moves = []
        self.board.flipped = mode == "computer" and self.human == chess.BLACK
        self.changed()

    # -- playing --

    def my_turn(self):
        if self.thinking or self.game_over():
            return False
        return self.mode == "friends" or self.position.turn == self.human

    def try_move(self, frm, to, slide=True):
        options = [m for m in self.legal if m[0] == frm and m[1] == to]
        if not options:
            return
        if len(options) > 1:
            self.ask_promotion(frm, to, options)
            return
        self.make_move(options[0], slide)

    def ask_promotion(self, frm, to, options):
        popover = Gtk.Popover(relative_to=self.board)
        x, y, size = self.board.square_box(to)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(x), int(y), int(size), int(size)
        popover.set_pointing_to(rect)
        box = Gtk.Box(spacing=2)
        box.get_style_context().add_class("rook-promote")
        for side in ("start", "end", "top", "bottom"):
            getattr(box, f"set_margin_{side}")(6)
        white = self.position.turn == chess.WHITE
        for kind, label in (("q", "Queen"), ("r", "Rook"), ("b", "Bishop"), ("n", "Knight")):
            glyph = "♕♖♗♘"["qrbn".index(kind)] if white else GLYPH[kind]
            button = Gtk.Button(label=glyph + "︎", relief=Gtk.ReliefStyle.NONE, tooltip_text=label)
            button.connect("clicked", self._promote, popover, (frm, to, kind))
            box.add(button)
        popover.add(box)
        popover.connect("closed", lambda p: GLib.idle_add(p.destroy))
        popover.show_all()
        popover.popup()

    def _promote(self, _button, popover, move):
        popover.popdown()
        self.make_move(move, slide=False)

    def make_move(self, move, slide=True):
        pos = self.position
        san = pos.san(move, self.legal)
        piece = pos.board[move[0]]
        self.positions.append(pos.play(move))
        self.moves.append((move, san))
        self.board.selected = None
        self.board.hint = None
        if slide:
            self.board.start_slide(piece if not move[2] else self.position.board[move[1]], move[0], move[1])
        self.changed()

    def changed(self):
        self.legal = self.position.legal_moves()
        self.board.selected = None
        self.board.queue_draw()
        self.update_side()
        self.save()
        if self.mode == "computer" and self.position.turn != self.human and not self.game_over() \
                and not self.thinking:
            self.think()

    def think(self):
        serial = self.serial
        self.thinking = serial
        position = self.position
        history = [p.key() for p in self.positions]
        level = self.level
        started = time.monotonic()

        def work():
            move = chess.best_move(position, level, history)
            # A short pause so a quick reply doesn't feel like a jump.
            wait = 0.45 - (time.monotonic() - started)
            if wait > 0:
                time.sleep(wait)
            GLib.idle_add(self._computer_moved, serial, position, move)
        threading.Thread(target=work, daemon=True).start()
        self.update_side()

    def _computer_moved(self, serial, position, move):
        if serial != self.serial or self.thinking != serial or position is not self.position:
            return False
        self.thinking = 0
        if move:
            self.make_move(move)
        return False

    def undo(self):
        if not self.moves:
            return
        if self.mode == "computer" and not any(p.turn == self.human for p in self.positions[:-1]):
            return                 # nothing of yours to take back yet
        self.serial += 1           # forget a move the computer is working on
        self.thinking = 0
        if self.mode == "computer":
            # Back to your turn, before your last move.
            took_yours = False
            while self.moves and not (took_yours and self.position.turn == self.human):
                took_yours = took_yours or self.positions[-2].turn == self.human
                self.positions.pop()
                self.moves.pop()
        else:
            self.positions.pop()
            self.moves.pop()
        self.board.hint = None
        self.changed()

    def show_hint(self):
        if not self.my_turn():
            return
        position = self.position
        self.hint_button.set_sensitive(False)

        def work():
            move = chess.hint(position)
            GLib.idle_add(done, move)

        def done(move):
            self.hint_button.set_sensitive(True)
            if position is self.position and move:
                self.board.hint = move
                self.board.queue_draw()
            return False
        threading.Thread(target=work, daemon=True).start()

    def flip(self):
        self.board.flipped = not self.board.flipped
        self.board.queue_draw()
        self.update_side()

    # -- how the game stands --

    def game_over(self):
        return self.result() is not None

    def result(self):
        """None while the game goes on, else (headline, winner or None)."""
        pos = self.position
        if not self.legal:
            if pos.in_check():
                return ("Checkmate", chess.other(pos.turn))
            return ("Stalemate", None)
        if pos.halfmove >= 100:
            return ("Draw: 50 moves without a capture", None)
        if pos.insufficient():
            return ("Draw: not enough pieces to win", None)
        if sum(1 for p in self.positions if p.key() == pos.key()) >= 3:
            return ("Draw: the same position three times", None)
        return None

    def side_name(self, side):
        colour_name = "White" if side == chess.WHITE else "Black"
        if self.mode != "computer":
            return colour_name
        return "You" if side == self.human else "The computer"

    def update_side(self):
        pos = self.position
        result = self.result()
        if result:
            headline, winner = result
            if winner is None:
                text = f"{headline}. It's a draw."
            elif self.mode == "computer":
                text = f"{headline}. You win! 🎉" if winner == self.human else f"{headline}. The computer wins."
            else:
                text = f"{headline}. {'White' if winner == chess.WHITE else 'Black'} wins!"
        elif self.thinking:
            text = "The computer is thinking…"
        else:
            turn = pos.turn
            if self.mode == "computer":
                text = "Your move" if turn == self.human else "The computer's move"
            else:
                text = f"{'White' if turn == chess.WHITE else 'Black'} to move"
            if pos.in_check():
                text += ", and you're in check" if self.mode == "computer" and turn == self.human else ". Check!"
        self.status.set_text(text)
        self.again.set_visible(result is not None)
        if self.mode == "computer":
            you = "White" if self.human == chess.WHITE else "Black"
            self.players.set_text(f"You play {you} against the computer on {LEVEL_NAMES[self.level]}.")
            self.header.set_subtitle(f"Against the computer, {LEVEL_NAMES[self.level]}")
        else:
            self.players.set_text("Two players on one screen. Take turns.")
            self.header.set_subtitle("Two players")
        self.hint_button.set_sensitive(self.my_turn())
        self.undo_button.set_sensitive(bool(self.moves))
        # Taken pieces: what each side has captured.
        start, now = {}, {}
        for p in chess.START:
            start[p] = start.get(p, 0) + 1
        for p in pos.board:
            now[p] = now.get(p, 0) + 1
        order = "qrbnp"
        by_white = "".join(GLYPH[k] * (start[k] - now.get(k, 0)) for k in order)
        by_black = "".join("♕♖♗♘♙"[order.index(k)] * (start[k.upper()] - now.get(k.upper(), 0))
                           for k in order)
        top_side = chess.WHITE if self.board.flipped else chess.BLACK
        top, bottom = (by_white, by_black) if top_side == chess.WHITE else (by_black, by_white)
        self.taken_top.set_text(top + "︎" if top else "")
        self.taken_bottom.set_text(bottom + "︎" if bottom else "")
        # The moves so far, two to a line.
        lines = []
        for i in range(0, len(self.moves), 2):
            white = self.moves[i][1]
            black = self.moves[i + 1][1] if i + 1 < len(self.moves) else ""
            lines.append(f"{i // 2 + 1}.\t{white}\t{black}")
        self.move_list.set_text("\n".join(lines))
        GLib.idle_add(self._scroll_down)

    def _scroll_down(self):
        adj = self.scroller.get_vadjustment()
        adj.set_value(adj.get_upper())
        return False

    # -- keeping the game --

    def save(self):
        data = {"mode": self.mode, "level": self.level, "human": self.human, "human_choice": self.human_choice,
                "flipped": self.board.flipped,
                "moves": [[m[0], m[1], m[2]] for m, _san in self.moves]}
        try:
            tmp = store_path() + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f)
            os.replace(tmp, store_path())
        except OSError:
            pass

    def load(self):
        try:
            with open(store_path(), encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = None
        if not isinstance(data, dict):
            self.changed()
            return
        self.mode = data.get("mode") if data.get("mode") in ("computer", "friends") else "computer"
        self.level = data.get("level") if data.get("level") in LEVEL_NAMES else "medium"
        self.human = chess.BLACK if data.get("human") == chess.BLACK else chess.WHITE
        self.human_choice = data.get("human_choice", "white")
        self.board.flipped = bool(data.get("flipped"))
        # Replay the moves, checking each one, so a damaged file can't break the board.
        positions, moves = [chess.Position()], []
        for entry in data.get("moves", []):
            try:
                move = (int(entry[0]), int(entry[1]), entry[2] if entry[2] in ("q", "r", "b", "n") else None)
            except (TypeError, ValueError, IndexError):
                break
            legal = positions[-1].legal_moves()
            if move not in legal:
                break
            moves.append((move, positions[-1].san(move, legal)))
            positions.append(positions[-1].play(move))
        self.positions, self.moves = positions, moves
        self.changed()


def menubar():
    return menus.menubar([
        ("_File", [[("New Game…", "win.new", "<Ctrl>n")], [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Take Back Move", "win.undo", "<Ctrl>z")]]),
        ("_Game", [[("Show a Hint", "win.hint", "<Ctrl>j"), ("Flip Board", "win.flip", "<Ctrl>r")]]),
    ])


class Rook(Gtk.Application):
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
        for action, keys in (("win.new", "<Control>n"), ("win.close", "<Control>w"), ("win.undo", "<Control>z"),
                             ("win.hint", "<Control>j"), ("win.flip", "<Control>r")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-rook")
    return Rook().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
