# SPDX-License-Identifier: GPL-3.0-or-later
"""Patience: the classic one-player card game.

Build each suit up from Ace to King on the four spaces at the top right.
On the seven columns, put cards in falling order, red on black and black on
red; only a King goes in an empty column. Click the deck to turn cards over.
Drag cards to move them, or double-click one to send it home. ⌘Z undoes,
Hint shows a move, and when every card is face up the rest finish themselves.

Original freemac code: the rules, and cards drawn with cairo in freemac's
own simple style. The game in progress is kept in
~/.local/share/freemac/patience.json.
"""
import json
import math
import os
import random
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
import cairo  # noqa: E402
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Patience"
SUITS = "♠♥♦♣"      # spades, hearts, diamonds, clubs
RANKS = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
FELT = (0.13, 0.42, 0.33)
FLY = 0.18


def red(card):
    return card[1] in (1, 2)


def store_path():
    folder = os.path.join(GLib.get_user_data_dir(), "freemac")
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, "patience.json")


# -- the game --

class Game:
    """Cards are (rank, suit). Columns hold [card, face_up] pairs."""

    def __init__(self, draw=1, seed=None):
        deck = [(rank, suit) for suit in range(4) for rank in range(1, 14)]
        random.Random(seed).shuffle(deck)
        self.draw = draw
        self.columns = []
        for i in range(7):
            column = [[deck.pop(), False] for _ in range(i + 1)]
            column[-1][1] = True
            self.columns.append(column)
        self.stock = deck
        self.waste = []
        self.homes = [[] for _ in range(4)]
        self.moves = 0
        self.started = None
        self.elapsed = 0.0

    def to_dict(self):
        return {"draw": self.draw, "columns": self.columns, "stock": self.stock, "waste": self.waste,
                "homes": self.homes, "moves": self.moves, "elapsed": self.seconds()}

    @classmethod
    def from_dict(cls, data):
        game = cls.__new__(cls)
        game.draw = 3 if data.get("draw") == 3 else 1
        game.columns = [[[tuple(c), bool(up)] for c, up in col] for col in data["columns"]]
        game.stock = [tuple(c) for c in data["stock"]]
        game.waste = [tuple(c) for c in data["waste"]]
        game.homes = [[tuple(c) for c in home] for home in data["homes"]]
        game.moves = int(data.get("moves", 0))
        game.started = None
        game.elapsed = float(data.get("elapsed", 0))
        cards = [c for col in game.columns for c, _u in col] + game.stock + game.waste + \
            [c for home in game.homes for c in home]
        if sorted(cards) != sorted((r, s) for s in range(4) for r in range(1, 14)) or len(game.columns) != 7:
            raise ValueError("not a whole deck")
        return game

    def snapshot(self):
        return json.dumps({"columns": self.columns, "stock": self.stock, "waste": self.waste,
                           "homes": self.homes, "moves": self.moves})

    def restore(self, text):
        data = json.loads(text)
        self.columns = [[[tuple(c), up] for c, up in col] for col in data["columns"]]
        self.stock = [tuple(c) for c in data["stock"]]
        self.waste = [tuple(c) for c in data["waste"]]
        self.homes = [[tuple(c) for c in home] for home in data["homes"]]
        self.moves = data["moves"]

    def seconds(self):
        return self.elapsed + (time.monotonic() - self.started if self.started else 0)

    def tick(self):
        if self.started is None and not self.won():
            self.started = time.monotonic()

    def won(self):
        return all(len(home) == 13 for home in self.homes)

    # What may go where.
    def home_for(self, card):
        for index, home in enumerate(self.homes):
            if (not home and card[0] == 1) or (home and home[-1][1] == card[1] and home[-1][0] + 1 == card[0]):
                return index
        return None

    def fits_column(self, card, index):
        column = self.columns[index]
        if not column:
            return card[0] == 13
        top, up = column[-1]
        return up and red(top) != red(card) and top[0] == card[0] + 1

    def turn_stock(self):
        if self.stock:
            for _ in range(min(self.draw, len(self.stock))):
                self.waste.append(self.stock.pop())
        elif self.waste:
            self.stock = list(reversed(self.waste))
            self.waste = []
        else:
            return False
        self.moves += 1
        return True

    def take(self, source):
        """The cards a source would give up: ("column", i, from) / ("waste",) / ("home", i)."""
        if source[0] == "column":
            return [c for c, _u in self.columns[source[1]][source[2]:]]
        if source[0] == "waste":
            return [self.waste[-1]] if self.waste else []
        return [self.homes[source[1]][-1]] if self.homes[source[1]] else []

    def can_move(self, source, target):
        cards = self.take(source)
        if not cards:
            return False
        if target[0] == "home":
            if len(cards) != 1 or source == target:
                return False
            home = self.homes[target[1]]
            card = cards[0]
            return (not home and card[0] == 1) or (bool(home) and home[-1][1] == card[1]
                                                    and home[-1][0] + 1 == card[0])
        if source[0] == "column" and source[1] == target[1]:
            return False
        return self.fits_column(cards[0], target[1])

    def move(self, source, target):
        cards = self.take(source)
        if source[0] == "column":
            del self.columns[source[1]][source[2]:]
            column = self.columns[source[1]]
            if column and not column[-1][1]:
                column[-1][1] = True
        elif source[0] == "waste":
            self.waste.pop()
        else:
            self.homes[source[1]].pop()
        if target[0] == "home":
            self.homes[target[1]].extend(cards)
        else:
            self.columns[target[1]].extend([c, True] for c in cards)
        self.moves += 1

    def sources(self):
        found = []
        if self.waste:
            found.append(("waste",))
        for i, column in enumerate(self.columns):
            for j, (_c, up) in enumerate(column):
                if up:
                    found.append(("column", i, j))
        return found

    def hint(self):
        """A useful move, or ("stock",) to turn the deck, or None."""
        # Anything that can go home.
        for source in self.sources():
            cards = self.take(source)
            if len(cards) == 1:
                index = self.home_for(cards[0])
                if index is not None:
                    return source, ("home", index)
        for source in self.sources():
            cards = self.take(source)
            for i in range(7):
                if not self.can_move(source, ("column", i)):
                    continue
                if source[0] == "column":
                    # Only worth it if it turns a card over or empties a column for a King.
                    below = self.columns[source[1]][source[2] - 1] if source[2] else None
                    if below is not None and below[1]:
                        continue
                    if below is None and cards[0][0] == 13:
                        continue
                return source, ("column", i)
        for card in self.stock + self.waste:
            if self.home_for(card) is not None or any(self.fits_column(card, i) for i in range(7)):
                return ("stock",), None
        return None

    def can_finish(self):
        return not self.stock and not self.waste and all(up for col in self.columns for _c, up in col) \
            and not self.won()


# -- drawing cards --

def rounded(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
    cr.close_path()


def _text(cr, text, x, y, size, bold=False, centre=True):
    layout = PangoCairo.create_layout(cr)
    font = Pango.FontDescription("Inter Bold" if bold else "DejaVu Sans")
    font.set_absolute_size(size * Pango.SCALE)
    layout.set_font_description(font)
    layout.set_text(text, -1)
    w, h = layout.get_pixel_size()
    cr.move_to(x - w / 2 if centre else x, y - h / 2 if centre else y)
    PangoCairo.show_layout(cr, layout)
    return w, h


def draw_card(cr, card, up, x, y, w, h, lifted=False):
    r = w * 0.08
    cr.save()
    rounded(cr, x + 1, y + (3 if lifted else 1.5), w, h, r)
    cr.set_source_rgba(0, 0, 0, 0.35 if lifted else 0.22)
    cr.fill()
    rounded(cr, x, y, w, h, r)
    if not up:
        grad = cairo.LinearGradient(x, y, x, y + h)
        grad.add_color_stop_rgb(0, 0.20, 0.42, 0.85)
        grad.add_color_stop_rgb(1, 0.12, 0.28, 0.65)
        cr.set_source(grad)
        cr.fill_preserve()
        cr.set_source_rgb(1, 1, 1)
        cr.set_line_width(max(1.5, w * 0.03))
        cr.stroke()
        # A little wave pattern of freemac's own.
        cr.save()
        rounded(cr, x + w * 0.1, y + w * 0.1, w * 0.8, h - w * 0.2, r * 0.6)
        cr.clip()
        cr.set_source_rgba(1, 1, 1, 0.22)
        cr.set_line_width(max(1, w * 0.025))
        step = w * 0.14
        row = y
        while row < y + h + step:
            cr.move_to(x, row)
            cx = x
            while cx < x + w:
                cr.curve_to(cx + step * 0.35, row - step * 0.3, cx + step * 0.65, row + step * 0.3, cx + step, row)
                cx += step
            cr.stroke()
            row += step * 0.8
        cr.restore()
        cr.restore()
        return
    cr.set_source_rgb(1, 1, 1)
    cr.fill_preserve()
    cr.set_source_rgba(0, 0, 0, 0.25)
    cr.set_line_width(1)
    cr.stroke()
    rank, suit = card
    colour = (0.85, 0.12, 0.15) if red(card) else (0.1, 0.1, 0.12)
    cr.set_source_rgb(*colour)
    corner = w * 0.2
    _text(cr, RANKS[rank], x + w * 0.06, y + w * 0.04, corner, bold=True, centre=False)
    _text(cr, SUITS[suit], x + w * 0.065, y + w * 0.04 + corner * 1.15, corner * 0.85, centre=False)
    if rank > 10:
        # Court cards: a framed panel with the letter and the suit.
        rounded(cr, x + w * 0.24, y + h * 0.2, w * 0.52, h * 0.6, w * 0.05)
        cr.set_source_rgba(*colour, 0.1)
        cr.fill_preserve()
        cr.set_source_rgba(*colour, 0.6)
        cr.set_line_width(max(1, w * 0.02))
        cr.stroke()
        cr.set_source_rgb(*colour)
        _text(cr, RANKS[rank], x + w / 2, y + h * 0.42, w * 0.32, bold=True)
        _text(cr, SUITS[suit], x + w / 2, y + h * 0.62, w * 0.22)
    else:
        _text(cr, SUITS[suit], x + w * 0.58, y + h * 0.56, w * (0.6 if rank == 1 else 0.44))
    cr.restore()


def draw_space(cr, x, y, w, h, mark=None):
    rounded(cr, x, y, w, h, w * 0.08)
    cr.set_source_rgba(0, 0, 0, 0.14)
    cr.fill_preserve()
    cr.set_source_rgba(1, 1, 1, 0.25)
    cr.set_line_width(1.5)
    cr.stroke()
    if mark:
        cr.set_source_rgba(1, 1, 1, 0.3)
        _text(cr, mark, x + w / 2, y + h / 2, w * 0.4, bold=True)


# -- the table --

class Table(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(hexpand=True, vexpand=True)
        self.window = window
        self.drag = None        # dict(source, cards, dx, dy, x, y)
        self.press = None
        self.flying = []        # [card, x0, y0, x1, y1, started]
        self.hint = None
        self.confetti = []
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)

    @property
    def game(self):
        return self.window.game

    # Where everything goes.
    def metrics(self):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        gap = max(8, width * 0.015)
        w = min((width - gap * 8) / 7, 140)
        h = w * 1.4
        left = (width - (w * 7 + gap * 6)) / 2
        top = gap * 1.5
        return left, top, w, h, gap, height

    def slot(self, index):
        left, top, w, _h, gap, _H = self.metrics()
        return left + index * (w + gap), top

    def column_positions(self, index):
        """(x, y) for each card in a column, squeezed to fit the window."""
        left, top, w, h, gap, height = self.metrics()
        x = left + index * (w + gap)
        y0 = top + h + gap * 1.5
        column = self.game.columns[index]
        down, up = h * 0.11, h * 0.27
        need = sum(up if u else down for _c, u in column[:-1])
        room = height - y0 - h - gap
        if need > room and need > 0:
            squeeze = max(0.3, room / need)
            down, up = down * squeeze, up * squeeze
        positions = []
        y = y0
        for _c, u in column:
            positions.append((x, y))
            y += up if u else down
        return positions

    def waste_positions(self):
        x, y = self.slot(1)
        _l, _t, w, _h, _g, _H = self.metrics()
        waste = self.game.waste
        shown = min(len(waste), 3 if self.game.draw == 3 else 1)
        positions = [(x, y)] * (len(waste) - shown)
        for i in range(shown):
            positions.append((x + i * w * 0.22, y))
        return positions

    def card_at(self, px, py):
        """The source under the point, if there's a face-up card there."""
        g = self.game
        _l, _t, w, h, _g, _H = self.metrics()
        for i in range(7):
            positions = self.column_positions(i)
            for j in range(len(positions) - 1, -1, -1):
                x, y = positions[j]
                if x <= px <= x + w and y <= py <= y + h:
                    return ("column", i, j) if g.columns[i][j][1] else None
        if g.waste:
            x, y = self.waste_positions()[-1]
            if x <= px <= x + w and y <= py <= y + h:
                return ("waste",)
        for i in range(4):
            x, y = self.slot(3 + i)
            if x <= px <= x + w and y <= py <= y + h and g.homes[i]:
                return ("home", i)
        return None

    def target_at(self, px, py):
        _l, _t, w, h, gap, _H = self.metrics()
        for i in range(4):
            x, y = self.slot(3 + i)
            if x - gap / 2 <= px <= x + w + gap / 2 and y <= py <= y + h:
                return ("home", i)
        for i in range(7):
            positions = self.column_positions(i)
            x = self.slot(i)[0]
            bottom = (positions[-1][1] if positions else self.metrics()[1] + h + gap * 1.5) + h
            top = self.metrics()[1] + h + gap
            if x - gap / 2 <= px <= x + w + gap / 2 and top <= py <= bottom + h * 0.5:
                return ("column", i)
        return None

    def place_of(self, where):
        """The position a card would land at."""
        _l, _t, _w, h, gap, _H = self.metrics()
        if where[0] == "home":
            return self.slot(3 + where[1])
        positions = self.column_positions(where[1])
        if positions:
            x, y = positions[-1]
            return x, y + h * 0.27
        x, _y = self.slot(where[1])
        return x, self.metrics()[1] + h + gap * 1.5

    def position_of(self, source):
        if source[0] == "column":
            return self.column_positions(source[1])[source[2]]
        if source[0] == "waste":
            return self.waste_positions()[-1]
        return self.slot(3 + source[1])

    # Animations
    def fly(self, card, start, end):
        self.flying.append([card, start[0], start[1], end[0], end[1], time.monotonic()])
        if len(self.flying) == 1:
            self.add_tick_callback(self._tick)

    def _tick(self, _w, _clock):
        now = time.monotonic()
        self.flying = [f for f in self.flying if now - f[5] < FLY]
        self.confetti = [c for c in self.confetti if now - c[6] < 4.5]
        self.queue_draw()
        return bool(self.flying or self.confetti)

    def celebrate(self):
        width = self.get_allocated_width()
        now = time.monotonic()
        colours = [(1, 0.23, 0.19), (1, 0.8, 0), (0.2, 0.78, 0.35), (0, 0.48, 1), (0.69, 0.32, 0.87),
                   (1, 0.58, 0)]
        for _ in range(140):
            self.confetti.append([random.uniform(0, width), random.uniform(-200, -10),
                                  random.uniform(-40, 40), random.uniform(120, 260), random.choice(colours),
                                  random.uniform(0, 6.28), now + random.uniform(0, 1.2)])
        self.add_tick_callback(self._tick)

    def _draw(self, _w, cr):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        grad = cairo.RadialGradient(width / 2, height * 0.4, 50, width / 2, height * 0.4, max(width, height))
        grad.add_color_stop_rgb(0, FELT[0] + 0.05, FELT[1] + 0.06, FELT[2] + 0.05)
        grad.add_color_stop_rgb(1, FELT[0] - 0.04, FELT[1] - 0.12, FELT[2] - 0.1)
        cr.set_source(grad)
        cr.paint()
        g = self.game
        _l, _t, w, h, _gap, _H = self.metrics()
        hidden = set()
        if self.drag:
            hidden.update(self.drag["cards"])
        hidden.update(f[0] for f in self.flying)
        # Deck
        x, y = self.slot(0)
        if g.stock:
            draw_card(cr, None, False, x, y, w, h)
        else:
            draw_space(cr, x, y, w, h, "↻" if g.waste else None)
        # Waste
        for card, (x, y) in zip(g.waste, self.waste_positions()):
            if card not in hidden:
                draw_card(cr, card, True, x, y, w, h)
        if not g.waste:
            x, y = self.slot(1)
            draw_space(cr, x, y, w, h)
        # Homes
        for i, home in enumerate(g.homes):
            x, y = self.slot(3 + i)
            draw_space(cr, x, y, w, h, "A")
            shown = [c for c in home if c not in hidden]
            if shown:
                draw_card(cr, shown[-1], True, x, y, w, h)
        # Columns
        for i, column in enumerate(g.columns):
            positions = self.column_positions(i)
            if not column:
                x, y = self.slot(i)
                draw_space(cr, x, self.metrics()[1] + h + self.metrics()[4] * 1.5, w, h, "K")
            for (card, up), (x, y) in zip(column, positions):
                if card not in hidden:
                    draw_card(cr, card, up, x, y, w, h)
        # A hint: a glow round the card and where it can go.
        if self.hint:
            cr.set_source_rgba(1, 0.85, 0.2, 0.95)
            cr.set_line_width(3)
            for x, y in self.hint:
                rounded(cr, x - 3, y - 3, w + 6, h + 6, w * 0.1)
                cr.stroke()
        now = time.monotonic()
        for card, x0, y0, x1, y1, started in self.flying:
            t = min(1, (now - started) / FLY)
            t = 1 - (1 - t) ** 3
            draw_card(cr, card, True, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, w, h, lifted=True)
        if self.drag:
            for k, card in enumerate(self.drag["cards"]):
                draw_card(cr, card, True, self.drag["x"] - self.drag["dx"],
                          self.drag["y"] - self.drag["dy"] + k * h * 0.27, w, h, lifted=True)
        for x, y0, vx, vy, colour, spin, start in self.confetti:
            t = now - start
            if t < 0:
                continue
            cr.save()
            cr.translate(x + vx * t, y0 + vy * t + 40 * t * t)
            cr.rotate(spin + t * 5)
            cr.set_source_rgb(*colour)
            cr.rectangle(-5, -3, 10, 6)
            cr.fill()
            cr.restore()

    def _press(self, _w, event):
        if event.button != 1:
            return False
        g = self.game
        self.hint = None
        if event.type == Gdk.EventType._2BUTTON_PRESS:
            source = self.card_at(event.x, event.y)
            if source:
                self.window.send_home(source)
            return True
        if event.type != Gdk.EventType.BUTTON_PRESS:
            return True
        _l, _t, w, h, _g, _H = self.metrics()
        x, y = self.slot(0)
        if x <= event.x <= x + w and y <= event.y <= y + h:
            self.window.turn_stock()
            return True
        source = self.card_at(event.x, event.y)
        if source:
            sx, sy = self.position_of(source)
            self.press = {"source": source, "cards": g.take(source), "dx": event.x - sx, "dy": event.y - sy,
                          "x": event.x, "y": event.y, "x0": event.x, "y0": event.y}
        self.queue_draw()
        return True

    def _motion(self, _w, event):
        if not self.press or not event.state & Gdk.ModifierType.BUTTON1_MASK:
            return False
        if self.drag or abs(event.x - self.press["x0"]) + abs(event.y - self.press["y0"]) > 4:
            self.drag = self.press
            self.drag["x"], self.drag["y"] = event.x, event.y
            self.queue_draw()
        return True

    def _release(self, _w, event):
        if event.button != 1:
            return False
        drag, self.drag = self.drag, None
        self.press = None
        if drag:
            _l, _t, w, h, _g, _H = self.metrics()
            # Judge by the middle of the dragged card's top.
            cx = event.x - drag["dx"] + w / 2
            cy = event.y - drag["dy"] + h * 0.3
            target = self.target_at(cx, cy)
            if target and self.game.can_move(drag["source"], target):
                self.window.do_move(drag["source"], target, animate=False)
            self.queue_draw()
        return True


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Patience")
        self.set_default_size(1040, 720)
        self.history = []
        self.finishing = 0
        self.note_until = 0
        header = Gtk.HeaderBar(show_close_button=True, title="Patience")
        self.header = header
        self.set_titlebar(header)
        new = Gtk.Button(label="New Game")
        new.connect("clicked", lambda _b: self.new_game())
        header.pack_start(new)
        self.undo_button = Gtk.Button.new_from_icon_name("edit-undo-symbolic", Gtk.IconSize.BUTTON)
        self.undo_button.set_tooltip_text("Undo (⌘Z)")
        self.undo_button.connect("clicked", lambda _b: self.undo())
        header.pack_start(self.undo_button)
        self.draw_switch = Gtk.ComboBoxText()
        self.draw_switch.append("1", "Draw 1")
        self.draw_switch.append("3", "Draw 3")
        self.draw_switch.set_tooltip_text("How many cards the deck turns over (starts a new game)")
        header.pack_end(self.draw_switch)
        hint = Gtk.Button(label="Hint")
        hint.connect("clicked", lambda _b: self.show_hint())
        header.pack_end(hint)
        self.finish_button = Gtk.Button(label="Finish")
        self.finish_button.get_style_context().add_class("suggested-action")
        self.finish_button.connect("clicked", lambda _b: self.finish())
        header.pack_end(self.finish_button)

        self.table = Table(self)
        self.add(self.table)
        self.game = self._load() or Game()
        self.draw_switch.set_active_id(str(self.game.draw))
        self.draw_switch.connect("changed", self._draw_changed)
        menus.add_actions(self, {"new": self.new_game, "undo": self.undo, "hint": self.show_hint,
                                 "close": self.close})
        self.connect("destroy", lambda _w: self.save())
        GLib.timeout_add(1000, self._clock)
        self.show_all()
        self.update()

    def _load(self):
        try:
            with open(store_path(), encoding="utf-8") as f:
                return Game.from_dict(json.load(f))
        except (OSError, ValueError, KeyError, TypeError):
            return None

    def save(self):
        try:
            tmp = store_path() + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.game.to_dict(), f)
            os.replace(tmp, store_path())
        except OSError:
            pass

    def _clock(self):
        if self.get_window() is None:
            return False
        self.update_subtitle()
        return True

    def update_subtitle(self):
        if time.monotonic() < self.note_until:
            return
        seconds = int(self.game.seconds())
        self.header.set_subtitle(f"{self.game.moves} moves · {seconds // 60}:{seconds % 60:02d}")

    def update(self):
        self.update_subtitle()
        self.undo_button.set_sensitive(bool(self.history))
        self.finish_button.set_visible(self.game.can_finish() and not self.finishing)
        self.table.queue_draw()

    def new_game(self, draw=None):
        self.finishing = 0
        self.game = Game(draw or self.game.draw)
        self.history = []
        self.table.hint = None
        self.table.confetti = []
        self.save()
        self.update()

    def _draw_changed(self, combo):
        draw = int(combo.get_active_id() or "1")
        if draw != self.game.draw:
            self.new_game(draw)

    def _remember(self):
        self.history.append(self.game.snapshot())
        del self.history[:-500]

    def turn_stock(self):
        if self.finishing:
            return
        self._remember()
        self.game.tick()
        if not self.game.turn_stock():
            self.history.pop()
        self.after_move()

    def do_move(self, source, target, animate=True):
        g = self.game
        if not g.can_move(source, target):
            return False
        start = self.table.position_of(source)
        end = self.table.place_of(target)
        cards = g.take(source)
        self._remember()
        g.tick()
        g.move(source, target)
        if animate and len(cards) == 1:
            self.table.fly(cards[0], start, end)
        self.after_move()
        return True

    def send_home(self, source):
        cards = self.game.take(source)
        if len(cards) != 1:
            return
        index = self.game.home_for(cards[0])
        if index is not None:
            self.do_move(source, ("home", index))

    def after_move(self):
        self.table.hint = None
        if self.game.won():
            self.game.elapsed = self.game.seconds()
            self.game.started = None
            self.table.celebrate()
            self.finishing = 0
        self.save()
        self.update()

    def undo(self):
        if self.history and not self.finishing:
            self.game.restore(self.history.pop())
            self.table.confetti = []
            self.update()
            self.save()

    def show_hint(self):
        move = self.game.hint()
        if move is None:
            self.table.hint = None
            self.note_until = time.monotonic() + 4
            self.header.set_subtitle("No moves left. Try Undo or a New Game.")
            return
        elif move[0] == ("stock",):
            self.table.hint = [self.table.slot(0)]
        else:
            source, target = move
            self.table.hint = [self.table.position_of(source), self.table.place_of(target)]
        self.table.queue_draw()

    def finish(self):
        """Send every card home, one at a time."""
        self.finishing = 1
        self.update()

        def step():
            if not self.finishing:
                return False
            g = self.game
            best = None
            for i, column in enumerate(g.columns):
                if column:
                    card = column[-1][0]
                    index = g.home_for(card)
                    if index is not None and (best is None or card[0] < best[0][0]):
                        best = (card, ("column", i, len(column) - 1), ("home", index))
            if best is None:
                self.finishing = 0
                self.update()
                return False
            self.do_move(best[1], best[2])
            return not g.won()
        GLib.timeout_add(90, step)


def menubar():
    return menus.menubar([
        ("_File", [[("New Game", "win.new", "<Ctrl>n")], [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Undo", "win.undo", "<Ctrl>z")]]),
        ("_Game", [[("Show a Hint", "win.hint", "<Ctrl>j")]]),
    ])


class Patience(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.new", "<Control>n"), ("win.close", "<Control>w"), ("win.undo", "<Control>z"),
                             ("win.hint", "<Control>j")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-patience")
    return Patience().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
