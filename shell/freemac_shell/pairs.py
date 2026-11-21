# SPDX-License-Identifier: GPL-3.0-or-later
"""Pairs: a memory game.

Cards lie face down. Turn over two: if they match they stay up, if not they
turn back. Find every pair in as few turns as you can, or play with someone
else, taking turns: a pair found earns another go.

Original freemac code. The pictures are emoji from the system's emoji font.
Best results for each size are kept in ~/.local/share/freemac/pairs.json.
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
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Pairs"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "pairs.json")
SIZES = (("small", "Small", 4, 3), ("medium", "Medium", 4, 4), ("large", "Large", 6, 4), ("huge", "Huge", 6, 6))
THEMES = {
    "animals": ("Animals", "🐶🐱🐭🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🐔🐧🐢🐙🦉🦋"),
    "food": ("Food", "🍎🍌🍇🍓🍉🍒🍍🥝🥕🌽🍕🍔🍩🍪🧁🍦🥨🧀🍋🥑"),
    "things": ("Things", "⚽🏀🎈🎁🎨🎸🚗🚀⛵🚂🌈⭐🌙🌞🔔🎲🧸🪁🎺📚"),
}
PLAYER_COLOURS = ((0.04, 0.49, 1.0), (1.0, 0.42, 0.21))
FLIP_TIME = 0.22
SHOW_TIME = 900      # ms a wrong pair stays face up


def load_store():
    try:
        with open(STORE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_store(data):
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    tmp = STORE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, STORE)


class Card:
    def __init__(self, picture):
        self.picture = picture
        self.up = False
        self.found = False
        self.flip_start = None     # when the turn-over animation began
        self.flip_to = False

    def turn(self, up):
        if up != self.up:
            self.flip_start = time.monotonic()
            self.flip_to = up
            self.up = up

    def width_factor(self):
        """How wide the card looks during its turn (1 flat, 0 edge on), and
        which side shows."""
        if self.flip_start is None:
            return 1.0, self.up
        t = (time.monotonic() - self.flip_start) / FLIP_TIME
        if t >= 1:
            self.flip_start = None
            return 1.0, self.up
        if t < 0.5:
            return 1 - t * 2, not self.flip_to
        return t * 2 - 1, self.flip_to


class Game:
    def __init__(self, columns, rows, theme, players):
        pictures = list(THEMES[theme][1].replace("️", ""))
        random.shuffle(pictures)
        chosen = pictures[:columns * rows // 2]
        deck = [Card(p) for p in chosen + chosen]
        random.shuffle(deck)
        self.columns, self.rows = columns, rows
        self.cards = deck
        self.players = players
        self.turn = 0
        self.scores = [0] * players
        self.moves = 0
        self.open = []
        self.started = None
        self.finished = None

    def pairs_left(self):
        return sum(1 for c in self.cards if not c.found) // 2

    def pick(self, index):
        """Turn a card over. Returns "wait" when two unmatched cards are up,
        "match", "miss" or None."""
        card = self.cards[index]
        if card.found or card.up or len(self.open) >= 2:
            return None
        if self.started is None:
            self.started = time.monotonic()
        card.turn(True)
        self.open.append(card)
        if len(self.open) < 2:
            return None
        self.moves += 1
        a, b = self.open
        if a.picture == b.picture:
            a.found = b.found = True
            self.scores[self.turn] += 1
            self.open = []
            if self.pairs_left() == 0:
                self.finished = time.monotonic()
            return "match"
        return "miss"

    def hide_open(self):
        for card in self.open:
            card.turn(False)
        self.open = []
        self.turn = (self.turn + 1) % self.players

    def seconds(self):
        if self.started is None:
            return 0
        return int((self.finished or time.monotonic()) - self.started)


class Table(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(can_focus=True)
        self.window = window
        self.hover = None
        self.focus_index = 0
        self.ticking = False
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.POINTER_MOTION_MASK
                        | Gdk.EventMask.LEAVE_NOTIFY_MASK | Gdk.EventMask.KEY_PRESS_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("leave-notify-event", lambda *_a: self._set_hover(None))
        self.connect("key-press-event", self._key)

    def layout(self):
        game = self.window.game
        width, height = self.get_allocated_width(), self.get_allocated_height()
        gap = 14
        cell = min((width - gap * (game.columns + 1)) / game.columns,
                   (height - gap * (game.rows + 1)) / (game.rows * 1.25))
        card_w, card_h = cell, cell * 1.25
        left = (width - game.columns * card_w - (game.columns - 1) * gap) / 2
        top = (height - game.rows * card_h - (game.rows - 1) * gap) / 2
        return left, top, card_w, card_h, gap

    def card_at(self, x, y):
        game = self.window.game
        left, top, w, h, gap = self.layout()
        col = int((x - left) // (w + gap))
        row = int((y - top) // (h + gap))
        if not (0 <= col < game.columns and 0 <= row < game.rows):
            return None
        if x - left - col * (w + gap) > w or y - top - row * (h + gap) > h:
            return None
        return row * game.columns + col

    def animate(self):
        if not self.ticking:
            self.ticking = True
            self.add_tick_callback(self._tick)
        # One more drawing once the turn is over, in case the frame clock
        # stops early (an idle or covered window).
        GLib.timeout_add(int(FLIP_TIME * 1000) + 80, lambda: self.queue_draw() and False)

    def _tick(self, _w, _clock):
        self.queue_draw()
        if any(c.flip_start is not None for c in self.window.game.cards):
            return True
        self.ticking = False
        return False

    def _set_hover(self, index):
        if index != self.hover:
            self.hover = index
            self.queue_draw()

    def _motion(self, _w, event):
        self._set_hover(self.card_at(event.x, event.y))

    def _press(self, _w, event):
        self.grab_focus()
        if event.button != 1:
            return
        index = self.card_at(event.x, event.y)
        if index is not None:
            self.focus_index = index
            self.window.pick(index)

    def _key(self, _w, event):
        game = self.window.game
        key = event.keyval
        col, row = self.focus_index % game.columns, self.focus_index // game.columns
        moves = {Gdk.KEY_Left: (-1, 0), Gdk.KEY_Right: (1, 0), Gdk.KEY_Up: (0, -1), Gdk.KEY_Down: (0, 1)}
        if key in moves:
            dx, dy = moves[key]
            col = (col + dx) % game.columns
            row = (row + dy) % game.rows
            self.focus_index = row * game.columns + col
            self.queue_draw()
            return True
        if key in (Gdk.KEY_space, Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.window.pick(self.focus_index)
            return True
        return False

    def _rounded(self, cr, x, y, w, h, r):
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def _draw(self, _w, cr):
        game = self.window.game
        left, top, w, h, gap = self.layout()
        if w <= 4:
            return
        dark = self.get_style_context().lookup_color("theme_bg_color")[1].red < 0.5
        colour = PLAYER_COLOURS[game.turn % 2] if game.players > 1 else PLAYER_COLOURS[0]
        for i, card in enumerate(game.cards):
            col, row = i % game.columns, i // game.columns
            x, y = left + col * (w + gap), top + row * (h + gap)
            factor, face_up = card.width_factor()
            cw = max(1.0, w * factor)
            cx = x + (w - cw) / 2
            r = min(w, h) * 0.1
            if card.found and card.flip_start is None:
                alpha = 0.45
            else:
                alpha = 1.0
            cr.save()
            # shadow
            self._rounded(cr, cx + 1, y + 3, cw, h, r)
            cr.set_source_rgba(0, 0, 0, 0.18 * alpha)
            cr.fill()
            self._rounded(cr, cx, y, cw, h, r)
            if face_up:
                if dark:
                    cr.set_source_rgba(0.24, 0.24, 0.27, alpha)
                else:
                    cr.set_source_rgba(1, 1, 1, alpha)
                cr.fill_preserve()
                cr.set_source_rgba(0, 0, 0, 0.12)
                cr.set_line_width(1)
                cr.stroke()
                if factor > 0.05:
                    cr.save()
                    cr.translate(cx + cw / 2, y + h / 2)
                    cr.scale(factor, 1)
                    layout = PangoCairo.create_layout(cr)
                    desc = Pango.FontDescription.from_string("Noto Color Emoji")
                    desc.set_absolute_size(w * 0.58 * Pango.SCALE)
                    layout.set_font_description(desc)
                    layout.set_text(card.picture, -1)
                    _ink, logical = layout.get_pixel_extents()
                    cr.move_to(-logical.width / 2 - logical.x, -logical.height / 2 - logical.y)
                    cr.push_group()
                    PangoCairo.show_layout(cr, layout)
                    cr.pop_group_to_source()
                    cr.paint_with_alpha(alpha)
                    cr.restore()
            else:
                cr.set_source_rgb(*colour)
                cr.fill()
                # a simple pattern of dots on the back
                cr.save()
                self._rounded(cr, cx, y, cw, h, r)
                cr.clip()
                cr.set_source_rgba(1, 1, 1, 0.18)
                step = max(8.0, w / 6)
                yy = y + step / 2
                n = 0
                while yy < y + h:
                    xx = cx + (step / 2 if n % 2 else 0)
                    while xx < cx + cw + step:
                        cr.arc(xx, yy, step * 0.16, 0, 2 * math.pi)
                        cr.fill()
                        xx += step
                    yy += step / 2
                    n += 1
                cr.restore()
                cr.set_source_rgba(1, 1, 1, 0.85)
                cr.set_line_width(max(2.0, w * 0.03))
                self._rounded(cr, cx + w * 0.07 * factor, y + w * 0.07, max(1, cw - w * 0.14 * factor),
                              h - w * 0.14, r * 0.6)
                cr.stroke()
            if i == self.hover and not card.found and not card.up:
                self._rounded(cr, cx, y, cw, h, r)
                cr.set_source_rgba(1, 1, 1, 0.18)
                cr.fill()
            if self.has_focus() and i == self.focus_index and self.window.keyboard_used:
                self._rounded(cr, cx - 4, y - 4, cw + 8, h + 8, r + 3)
                cr.set_source_rgba(*colour, 0.9)
                cr.set_line_width(3)
                cr.stroke()
            cr.restore()


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Pairs")
        self.set_default_size(820, 700)
        self.store = load_store()
        self.size_key = self.store.get("size") if self.store.get("size") in {s[0] for s in SIZES} else "medium"
        self.theme = self.store.get("theme") if self.store.get("theme") in THEMES else "animals"
        self.players = 2 if self.store.get("players") == 2 else 1
        self.keyboard_used = False
        self.hide_id = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Pairs")
        self.header = header
        self.set_titlebar(header)
        new = Gtk.Button(label="New Game")
        new.connect("clicked", lambda _b: self.new_game())
        header.pack_start(new)
        self.size_combo = Gtk.ComboBoxText()
        for key, label, cols, rows in SIZES:
            self.size_combo.append(key, f"{label} ({cols * rows // 2} pairs)")
        self.size_combo.set_active_id(self.size_key)
        self.size_combo.connect("changed", self._size_changed)
        header.pack_start(self.size_combo)
        self.theme_combo = Gtk.ComboBoxText()
        for key, (label, _p) in THEMES.items():
            self.theme_combo.append(key, label)
        self.theme_combo.set_active_id(self.theme)
        self.theme_combo.connect("changed", self._theme_changed)
        header.pack_start(self.theme_combo)
        players = Gtk.Box()
        players.get_style_context().add_class("linked")
        self.one = Gtk.RadioButton.new_with_label_from_widget(None, "1 Player")
        self.two = Gtk.RadioButton.new_with_label_from_widget(self.one, "2 Players")
        for button in (self.one, self.two):
            button.set_mode(False)
            players.pack_start(button, False, False, 0)
        (self.two if self.players == 2 else self.one).set_active(True)
        self.two.connect("toggled", self._players_changed)
        header.pack_end(players)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)
        self.score_bar = Gtk.Box(spacing=24, halign=Gtk.Align.CENTER)
        self.score_bar.set_margin_top(10)
        self.score_bar.set_margin_bottom(4)
        self.score_labels = []
        box.pack_start(self.score_bar, False, False, 0)
        overlay = Gtk.Overlay()
        self.table = Table(self)
        self.table.set_vexpand(True)
        overlay.add(self.table)
        self.banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                              halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.banner.get_style_context().add_class("pairs-banner")
        self.banner_title = Gtk.Label()
        self.banner_text = Gtk.Label(justify=Gtk.Justification.CENTER)
        again = Gtk.Button(label="Play Again")
        again.get_style_context().add_class("suggested-action")
        again.set_halign(Gtk.Align.CENTER)
        again.connect("clicked", lambda _b: self.new_game())
        self.banner.pack_start(self.banner_title, False, False, 0)
        self.banner.pack_start(self.banner_text, False, False, 0)
        self.banner.pack_start(again, False, False, 4)
        self.banner.set_no_show_all(True)
        overlay.add_overlay(self.banner)
        box.pack_start(overlay, True, True, 0)
        css = Gtk.CssProvider()
        css.load_from_data(b".pairs-banner { background-color: alpha(@theme_bg_color, 0.96); border-radius: 16px;"
                           b" padding: 26px 40px; box-shadow: 0 8px 30px alpha(black, 0.3); }"
                           b" .pairs-score { font-size: 15px; font-weight: 600; }"
                           b" .pairs-turn { font-size: 15px; }")
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.connect("key-press-event", self._any_key)
        menus.add_actions(self, {"new": self.new_game, "close": self.close, "best": self.show_best})
        self.new_game()
        GLib.timeout_add_seconds(1, self._clock)
        self.show_all()
        self.table.grab_focus()

    def _any_key(self, _w, event):
        if event.keyval in (Gdk.KEY_Left, Gdk.KEY_Right, Gdk.KEY_Up, Gdk.KEY_Down, Gdk.KEY_Tab):
            self.keyboard_used = True
        return False

    def _size_changed(self, combo):
        self.size_key = combo.get_active_id()
        self.new_game()

    def _theme_changed(self, combo):
        self.theme = combo.get_active_id()
        self.new_game()

    def _players_changed(self, button):
        self.players = 2 if button.get_active() else 1
        self.new_game()

    def new_game(self):
        if self.hide_id:
            GLib.source_remove(self.hide_id)
            self.hide_id = 0
        _key, _label, cols, rows = next(s for s in SIZES if s[0] == self.size_key)
        self.game = Game(cols, rows, self.theme, self.players)
        self.store.update(size=self.size_key, theme=self.theme, players=self.players)
        save_store(self.store)
        self.banner.hide()
        self.table.focus_index = 0
        self.update_scores()
        self.table.queue_draw()

    def pick(self, index):
        if self.game.finished:
            return
        if len(self.game.open) == 2:
            # Clicking again while a wrong pair shows turns it back at once.
            self._hide_now()
        result = self.game.pick(index)
        self.table.animate()
        if result == "miss":
            self.hide_id = GLib.timeout_add(SHOW_TIME, self._hide_now)
        if result:
            self.update_scores()
        if self.game.finished:
            GLib.timeout_add(450, self._won)

    def _hide_now(self):
        if self.hide_id:
            GLib.source_remove(self.hide_id)
            self.hide_id = 0
        if len(self.game.open) == 2:
            self.game.hide_open()
            self.table.animate()
            self.update_scores()
        return False

    def update_scores(self):
        for child in self.score_bar.get_children():
            self.score_bar.remove(child)
        game = self.game
        if game.players == 1:
            text = (f"Turns: {game.moves}     Pairs left: {game.pairs_left()}     "
                    f"Time: {game.seconds() // 60}:{game.seconds() % 60:02d}")
            label = Gtk.Label(label=text)
            label.get_style_context().add_class("pairs-turn")
            self.score_bar.pack_start(label, False, False, 0)
        else:
            for player in range(2):
                r, g, b = PLAYER_COLOURS[player]
                mark = "▶ " if player == game.turn and not game.finished else ""
                label = Gtk.Label()
                label.set_markup(f"<span foreground='#{int(r * 255):02x}{int(g * 255):02x}{int(b * 255):02x}'>"
                                 f"{mark}Player {player + 1}: {game.scores[player]}</span>")
                label.get_style_context().add_class("pairs-score")
                self.score_bar.pack_start(label, False, False, 0)
        self.score_bar.show_all()

    def _clock(self):
        if self.game.players == 1 and self.game.started and not self.game.finished:
            self.update_scores()
        return True

    def _won(self):
        game = self.game
        if game.players == 1:
            best = self.store.setdefault("best", {}).get(self.size_key)
            record = not best or game.moves < best.get("moves", 1e9) or (
                game.moves == best.get("moves") and game.seconds() < best.get("seconds", 1e9))
            if record:
                self.store["best"][self.size_key] = {"moves": game.moves, "seconds": game.seconds()}
                save_store(self.store)
            self.banner_title.set_markup("<span size='20000' weight='700'>All pairs found!</span>")
            more = f"{game.moves} turns in {game.seconds() // 60}:{game.seconds() % 60:02d}"
            if record:
                more += "\nThat's your best yet."
            self.banner_text.set_text(more)
        else:
            a, b = game.scores
            if a == b:
                title, more = "It's a tie!", f"{a} pairs each"
            else:
                winner = 1 if a > b else 2
                title, more = f"Player {winner} wins!", f"{max(a, b)} pairs to {min(a, b)}"
            self.banner_title.set_markup(f"<span size='20000' weight='700'>{title}</span>")
            self.banner_text.set_text(more)
        self.banner_title.show()
        self.banner_text.show()
        for child in self.banner.get_children():
            child.show()
        self.banner.show()
        self.update_scores()
        return False

    def show_best(self):
        best = self.store.get("best", {})
        lines = []
        for key, label, cols, rows in SIZES:
            entry = best.get(key)
            if entry:
                s = entry.get("seconds", 0)
                lines.append(f"{label}: {entry.get('moves')} turns, {s // 60}:{s % 60:02d}")
            else:
                lines.append(f"{label}: not played yet")
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="Best Results")
        dialog.format_secondary_text("\n".join(lines) + "\n\nFewest turns count first, then the time.")
        dialog.run()
        dialog.destroy()

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Pairs")
        dialog.format_secondary_text("Pairs is a memory game, part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_Game", [[("New Game", "win.new", "<Ctrl>n")], [("Best Results", "win.best", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
    ])


class Pairs(Gtk.Application):
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
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-pairs")
    return Pairs().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
