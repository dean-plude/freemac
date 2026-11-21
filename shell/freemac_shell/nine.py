# SPDX-License-Identifier: GPL-3.0-or-later
"""Nine: a number puzzle.

Fill the grid so that every row, every column and every 3 × 3 box holds the
numbers 1 to 9 once each. Click a square and type a number, or click one of
the numbers under the grid. Pencil marks (type with the pencil on, or hold
Shift) note the numbers a square might be. Every puzzle has exactly one
answer, made fresh by Nine at four levels.

Original freemac code. The game in progress and best times are kept in
~/.local/share/freemac/nine.json.
"""
import json
import os
import random
import sys
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Nine"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "nine.json")
LEVELS = {"easy": ("Easy", 40), "medium": ("Medium", 32), "hard": ("Hard", 27), "expert": ("Expert", 23)}
ALL = 0x3FE   # bits 1..9
PEERS = []
for _cell in range(81):
    _r, _c = divmod(_cell, 9)
    _br, _bc = _r // 3 * 3, _c // 3 * 3
    _peers = {_r * 9 + i for i in range(9)} | {i * 9 + _c for i in range(9)} \
        | {(_br + i) * 9 + _bc + j for i in range(3) for j in range(3)}
    _peers.discard(_cell)
    PEERS.append(tuple(sorted(_peers)))


def candidates(grid, cell):
    used = 0
    for p in PEERS[cell]:
        used |= 1 << grid[p]
    return ALL & ~used


def solve(grid, limit=2, rng=None):
    """Count answers up to limit; the first is written into grid if found.
    grid: list of 81 ints, 0 for empty."""
    work = list(grid)
    found = []

    def search():
        best, best_mask, best_count = -1, 0, 10
        for cell in range(81):
            if work[cell] == 0:
                mask = candidates(work, cell)
                count = bin(mask).count("1")
                if count == 0:
                    return False
                if count < best_count:
                    best, best_mask, best_count = cell, mask, count
                    if count == 1:
                        break
        if best < 0:
            found.append(list(work))
            return len(found) >= limit
        digits = [d for d in range(1, 10) if best_mask >> d & 1]
        if rng:
            rng.shuffle(digits)
        for d in digits:
            work[best] = d
            if search():
                return True
        work[best] = 0
        return False

    search()
    if found:
        grid[:] = found[0]
    return len(found)


def make_puzzle(level, rng=random):
    """(puzzle, answer): puzzle has 0 for the squares to fill."""
    answer = [0] * 81
    solve(answer, limit=1, rng=rng)
    puzzle = list(answer)
    givens = LEVELS[level][1]
    cells = list(range(81))
    rng.shuffle(cells)
    filled = 81
    for cell in cells:
        if filled <= givens:
            break
        keep = puzzle[cell]
        puzzle[cell] = 0
        test = list(puzzle)
        if solve(test, limit=2) != 1:
            puzzle[cell] = keep
        else:
            filled -= 1
    return puzzle, answer


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


def valid_game(data):
    try:
        ok = (data["level"] in LEVELS and len(data["puzzle"]) == 81 and len(data["answer"]) == 81
              and len(data["entries"]) == 81 and len(data["notes"]) == 81)
        ok = ok and all(isinstance(v, int) and 0 <= v <= 9 for v in data["puzzle"] + data["answer"] + data["entries"])
        ok = ok and all(isinstance(v, int) and 0 <= v <= ALL for v in data["notes"])
        return ok
    except (KeyError, TypeError):
        return False


class Game:
    def __init__(self, level, puzzle, answer):
        self.level = level
        self.puzzle = puzzle
        self.answer = answer
        self.entries = [0] * 81
        self.notes = [0] * 81
        self.hints = 0
        self.seconds = 0.0
        self.won = False
        self.undo = []
        self.redo = []

    def value(self, cell):
        return self.puzzle[cell] or self.entries[cell]

    def snapshot(self):
        return (list(self.entries), list(self.notes))

    def remember(self):
        self.undo.append(self.snapshot())
        del self.undo[:-200]
        self.redo.clear()

    def set_number(self, cell, digit):
        if self.puzzle[cell] or self.won:
            return False
        self.remember()
        self.entries[cell] = 0 if self.entries[cell] == digit else digit
        if self.entries[cell]:
            self.notes[cell] = 0
            for p in PEERS[cell]:
                self.notes[p] &= ~(1 << digit)
        self.won = all(self.value(i) == self.answer[i] for i in range(81))
        return True

    def toggle_note(self, cell, digit):
        if self.value(cell) or self.won:
            return False
        self.remember()
        self.notes[cell] ^= 1 << digit
        return True

    def clear(self, cell):
        if self.puzzle[cell] or self.won or not (self.entries[cell] or self.notes[cell]):
            return False
        self.remember()
        self.entries[cell] = 0
        self.notes[cell] = 0
        return True

    def step(self, back):
        source, target = (self.undo, self.redo) if back else (self.redo, self.undo)
        if not source or self.won:
            return False
        target.append(self.snapshot())
        self.entries, self.notes = source.pop()
        return True

    def hint(self, cell):
        """Fill one square with its answer: the chosen one if it's empty or
        wrong, otherwise the empty square with fewest possibilities."""
        if self.won:
            return None
        if cell is None or self.puzzle[cell] or self.entries[cell] == self.answer[cell]:
            grid = [self.value(i) if self.value(i) == self.answer[i] else 0 for i in range(81)]
            empty = [i for i in range(81) if self.value(i) != self.answer[i]]
            if not empty:
                return None
            cell = min(empty, key=lambda i: bin(candidates(grid, i)).count("1"))
        self.set_number(cell, self.answer[cell])
        self.hints += 1
        return cell

    def wrong(self, cell):
        return bool(self.entries[cell]) and self.entries[cell] != self.answer[cell]

    def clash(self, cell):
        v = self.value(cell)
        return bool(v) and not self.puzzle[cell] and any(self.value(p) == v for p in PEERS[cell])

    def placed(self, digit):
        return sum(1 for i in range(81) if self.value(i) == digit)

    def to_dict(self):
        return {"level": self.level, "puzzle": self.puzzle, "answer": self.answer, "entries": self.entries,
                "notes": self.notes, "hints": self.hints, "seconds": round(self.seconds, 1), "won": self.won}

    @classmethod
    def from_dict(cls, data):
        game = cls(data["level"], list(data["puzzle"]), list(data["answer"]))
        game.entries = list(data["entries"])
        game.notes = list(data["notes"])
        game.hints = int(data.get("hints", 0))
        game.seconds = float(data.get("seconds", 0))
        game.won = bool(data.get("won"))
        return game


class Board(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__()
        self.window = window
        self.selected = 40
        self.set_can_focus(True)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)

    def geometry(self):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        size = min(width, height) - 24
        cell = size // 9
        size = cell * 9
        return (width - size) / 2, (height - size) / 2, cell

    def _press(self, _w, event):
        x0, y0, cell = self.geometry()
        c, r = int((event.x - x0) // cell), int((event.y - y0) // cell)
        if 0 <= r < 9 and 0 <= c < 9:
            self.selected = r * 9 + c
            self.grab_focus()
            self.window.update()
        return True

    def _draw(self, _w, cr):
        game = self.window.game
        dark = self.get_style_context().lookup_color("theme_bg_color")[1].red < 0.5
        fg = (0.92, 0.92, 0.94) if dark else (0.1, 0.1, 0.12)
        cr.set_source_rgb(*((0.13, 0.13, 0.15) if dark else (0.96, 0.96, 0.97)))
        cr.paint()
        x0, y0, cell = self.geometry()
        cr.set_source_rgb(*((0.18, 0.18, 0.2) if dark else (1, 1, 1)))
        cr.rectangle(x0, y0, cell * 9, cell * 9)
        cr.fill()
        if game is None:
            self._text(cr, "Making a puzzle…", x0 + cell * 4.5, y0 + cell * 4.5, cell * 0.35, fg, 0.6)
            return
        sel = self.selected
        sr, sc = divmod(sel, 9)
        sel_value = game.value(sel)
        show_mistakes = self.window.show_mistakes
        for i in range(81):
            r, c = divmod(i, 9)
            x, y = x0 + c * cell, y0 + r * cell
            tint = None
            if i == sel:
                tint = (0.04, 0.49, 1.0, 0.35)
            elif sel_value and game.value(i) == sel_value:
                tint = (0.04, 0.49, 1.0, 0.2)
            elif r == sr or c == sc or (r // 3 == sr // 3 and c // 3 == sc // 3):
                tint = (0.04, 0.49, 1.0, 0.08)
            if (show_mistakes and game.wrong(i)) or game.clash(i):
                tint = (0.92, 0.25, 0.2, 0.22)
            if tint:
                cr.set_source_rgba(*tint)
                cr.rectangle(x, y, cell, cell)
                cr.fill()
            v = game.value(i)
            if v:
                if game.puzzle[i]:
                    colour = fg
                elif (show_mistakes and game.wrong(i)) or game.clash(i):
                    colour = (0.86, 0.2, 0.16)
                else:
                    colour = (0.25, 0.6, 1.0) if dark else (0.0, 0.38, 0.85)
                self._text(cr, str(v), x + cell / 2, y + cell / 2, cell * 0.55, colour, 1.0,
                           bold=bool(game.puzzle[i]))
            elif game.notes[i]:
                for d in range(1, 10):
                    if game.notes[i] >> d & 1:
                        nr, nc = divmod(d - 1, 3)
                        hit = sel_value == d
                        self._text(cr, str(d), x + cell * (nc + 0.5) / 3, y + cell * (nr + 0.5) / 3,
                                   cell * 0.22, (0.04, 0.49, 1.0) if hit else fg, 1.0 if hit else 0.6)
        for k in range(10):
            thick = k % 3 == 0
            cr.set_source_rgba(*fg, 0.85 if thick else 0.22)
            cr.set_line_width(2.4 if thick else 1)
            cr.move_to(x0 + k * cell, y0)
            cr.line_to(x0 + k * cell, y0 + 9 * cell)
            cr.move_to(x0, y0 + k * cell)
            cr.line_to(x0 + 9 * cell, y0 + k * cell)
            cr.stroke()
        if game.won:
            cr.set_source_rgba(0, 0, 0, 0.45)
            cr.rectangle(x0, y0 + cell * 3.3, cell * 9, cell * 2.4)
            cr.fill()
            secs = int(game.seconds)
            self._text(cr, "Solved!", x0 + cell * 4.5, y0 + cell * 4.15, cell * 0.6, (1, 1, 1), 1, bold=True)
            hints = f" with {game.hints} hint{'s' if game.hints != 1 else ''}" if game.hints else ""
            self._text(cr, f"{secs // 60}:{secs % 60:02d}{hints}  ·  New Game for another",
                       x0 + cell * 4.5, y0 + cell * 5.0, cell * 0.26, (1, 1, 1), 0.9)

    def _text(self, cr, text, cx, cy, size, colour, alpha, bold=False):
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription(f"Inter {'Bold ' if bold else ''}{max(6, int(size))}px"))
        layout.set_text(text, -1)
        w, h = layout.get_pixel_size()
        cr.set_source_rgba(*colour, alpha)
        cr.move_to(cx - w / 2, cy - h / 2)
        PangoCairo.show_layout(cr, layout)


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Nine")
        self.set_default_size(640, 760)
        self.store = load_store()
        self.show_mistakes = bool(self.store.get("mistakes", False))
        self.level = self.store.get("level") if self.store.get("level") in LEVELS else "easy"
        self.game = None
        self.pencil = False
        header = Gtk.HeaderBar(show_close_button=True, title="Nine")
        self.header = header
        self.set_titlebar(header)
        new = Gtk.Button(label="New Game")
        new.connect("clicked", lambda _b: self.new_game())
        header.pack_start(new)
        self.level_combo = Gtk.ComboBoxText()
        for key, (label, _g) in LEVELS.items():
            self.level_combo.append(key, label)
        self.level_combo.set_active_id(self.level)
        self.level_combo.connect("changed", self._level_changed)
        header.pack_start(self.level_combo)
        undo = Gtk.Button.new_from_icon_name("edit-undo-symbolic", Gtk.IconSize.BUTTON)
        undo.set_tooltip_text("Undo")
        undo.connect("clicked", lambda _b: self.step(True))
        hint = Gtk.Button(label="Hint")
        hint.connect("clicked", lambda _b: self.hint())
        self.pencil_button = Gtk.ToggleButton()
        self.pencil_button.add(Gtk.Image.new_from_icon_name("document-edit-symbolic", Gtk.IconSize.BUTTON))
        self.pencil_button.set_tooltip_text("Pencil marks (P)")
        self.pencil_button.connect("toggled", self._pencil_toggled)
        header.pack_end(hint)
        header.pack_end(self.pencil_button)
        header.pack_end(undo)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.board = Board(self)
        box.pack_start(self.board, True, True, 0)
        pad = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        pad.set_border_width(14)
        self.digit_buttons = {}
        for d in range(1, 10):
            button = Gtk.Button()
            label = Gtk.Label()
            button.add(label)
            button.set_size_request(52, 52)
            button.connect("clicked", lambda _b, d=d: self.type_digit(d))
            pad.pack_start(button, False, False, 0)
            self.digit_buttons[d] = (button, label)
        box.pack_start(pad, False, False, 0)
        self.add(box)
        self.connect("key-press-event", self._key)
        self.connect("delete-event", lambda *_a: self.save() or False)
        menus.add_actions(self, {"new": self.new_game, "close": self.close, "undo": lambda: self.step(True),
                                 "redo": lambda: self.step(False), "hint": self.hint,
                                 "pencil": lambda: self.pencil_button.set_active(not self.pencil),
                                 "best": self.show_best})
        menus.add_toggle(self, "mistakes", self.show_mistakes, self._mistakes)
        saved = self.store.get("game")
        if isinstance(saved, dict) and valid_game(saved) and not saved.get("won"):
            self.game = Game.from_dict(saved)
            self.level = self.game.level
            self.level_combo.set_active_id(self.level)
            self.update()
        else:
            self.new_game()
        self.last_tick = time.monotonic()
        GLib.timeout_add(1000, self._tick)
        self.show_all()

    def _level_changed(self, combo):
        level = combo.get_active_id()
        if level and level != self.level:
            self.level = level
            self.store["level"] = level
            self.new_game()

    def _pencil_toggled(self, button):
        self.pencil = button.get_active()
        self.update()

    def _mistakes(self, on):
        self.show_mistakes = on
        self.store["mistakes"] = on
        save_store(self.store)
        self.board.queue_draw()

    def new_game(self):
        self.game = None
        self.update()
        level = self.level

        def work():
            puzzle, answer = make_puzzle(level)
            GLib.idle_add(self._made, level, puzzle, answer)

        threading.Thread(target=work, daemon=True).start()

    def _made(self, level, puzzle, answer):
        if level != self.level:
            return False
        self.game = Game(level, puzzle, answer)
        self.board.selected = 40
        self.save()
        self.update()
        return False

    def _tick(self):
        if self.get_window() is None:
            return False
        now = time.monotonic()
        if self.game and not self.game.won and self.is_active():
            self.game.seconds += now - self.last_tick
            self._subtitle()
        self.last_tick = now
        return True

    def _subtitle(self):
        g = self.game
        if g is None:
            self.header.set_subtitle(LEVELS[self.level][0])
            return
        secs = int(g.seconds)
        self.header.set_subtitle(f"{LEVELS[g.level][0]} · {secs // 60}:{secs % 60:02d}")

    def type_digit(self, digit, pencil=False):
        g = self.game
        if g is None:
            return
        cell = self.board.selected
        changed = g.toggle_note(cell, digit) if (self.pencil or pencil) else g.set_number(cell, digit)
        if changed:
            if g.won:
                self.finished()
            self.save()
            self.update()

    def step(self, back):
        if self.game and self.game.step(back):
            self.save()
            self.update()

    def hint(self):
        if self.game:
            cell = self.game.hint(self.board.selected)
            if cell is not None:
                self.board.selected = cell
                if self.game.won:
                    self.finished()
                self.save()
                self.update()

    def finished(self):
        g = self.game
        best = self.store.setdefault("best", {})
        if not g.hints and (g.level not in best or g.seconds < best[g.level]):
            best[g.level] = int(g.seconds)

    def save(self):
        if self.game:
            self.store["game"] = self.game.to_dict()
        save_store(self.store)

    def _key(self, _w, event):
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        if mods & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK | Gdk.ModifierType.SUPER_MASK):
            return False
        sel = self.board.selected
        r, c = divmod(sel, 9)
        moves = {Gdk.KEY_Left: (0, -1), Gdk.KEY_Right: (0, 1), Gdk.KEY_Up: (-1, 0), Gdk.KEY_Down: (1, 0)}
        if event.keyval in moves:
            dr, dc = moves[event.keyval]
            self.board.selected = (r + dr) % 9 * 9 + (c + dc) % 9
            self.update()
            return True
        code = Gdk.keyval_to_unicode(event.keyval)
        ch = chr(code) if code else ""
        shifted = {"!": 1, "@": 2, "#": 3, "$": 4, "%": 5, "^": 6, "&": 7, "*": 8, "(": 9}
        if ch in shifted:
            self.type_digit(shifted[ch], pencil=True)
            return True
        if ch.isdigit() and ch != "0":
            self.type_digit(int(ch), pencil=bool(mods & Gdk.ModifierType.SHIFT_MASK))
            return True
        if event.keyval in (Gdk.KEY_BackSpace, Gdk.KEY_Delete) or ch == "0":
            if self.game and self.game.clear(sel):
                self.save()
                self.update()
            return True
        if ch.lower() == "p":
            self.pencil_button.set_active(not self.pencil)
            return True
        return False

    def update(self):
        g = self.game
        for d, (button, label) in self.digit_buttons.items():
            left = 9 - g.placed(d) if g else 9
            size = "16" if self.pencil else "22"
            label.set_markup(f"<span size='{size}000' weight='600'>{d}</span>"
                             + (f"\n<span size='8000' alpha='60%'>{left}</span>" if left and g else ""))
            label.set_justify(Gtk.Justification.CENTER)
            button.set_sensitive(bool(g) and left > 0 and not g.won)
        self._subtitle()
        self.board.queue_draw()

    def show_best(self):
        best = self.store.get("best", {})
        lines = []
        for key, (label, _g) in LEVELS.items():
            t = best.get(key)
            lines.append(f"{label}: {t // 60}:{t % 60:02d}" if isinstance(t, int) else f"{label}: not yet")
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK,
                                   text="Best Times", secondary_text="\n".join(lines)
                                   + "\n\nGames solved with a hint don't count.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_File", [[("New Game", "win.new", "<Ctrl>n")], [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Undo", "win.undo", "<Ctrl>z"), ("Redo", "win.redo", "<Shift><Ctrl>z")]]),
        ("_Game", [[("Hint", "win.hint", "<Ctrl>h"), ("Pencil Marks", "win.pencil", "P")],
                   [("Show Mistakes", "win.mistakes", None)], [("Best Times", "win.best", None)]]),
    ])


class Nine(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.new", "<Control>n"), ("win.close", "<Control>w"), ("win.undo", "<Control>z"),
                             ("win.redo", "<Shift><Control>z"), ("win.hint", "<Control>h")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-nine")
    return Nine().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
