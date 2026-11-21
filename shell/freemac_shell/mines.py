# SPDX-License-Identifier: GPL-3.0-or-later
"""Mines: clear a field without setting off a mine.

Click a square to open it. A number tells how many of the eight squares
around it hide a mine. Right-click (or Control-click) to put a flag where you
think a mine is. Click a number whose mines are all flagged to open the
squares around it. The first click is always safe. Open every square that
isn't a mine to win.

Original freemac code and artwork. Best times are kept in
~/.local/share/freemac/mines.json.
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

APP_ID = "org.freemac.Mines"
SIZES = {
    "small": ("Small", 9, 9, 10),
    "medium": ("Medium", 16, 16, 40),
    "large": ("Large", 30, 16, 99),
}
NUMBER_COLOURS = {
    1: (0.0, 0.48, 1.0), 2: (0.2, 0.62, 0.25), 3: (0.92, 0.2, 0.2), 4: (0.45, 0.25, 0.75),
    5: (0.72, 0.36, 0.05), 6: (0.0, 0.6, 0.6), 7: (0.15, 0.15, 0.15), 8: (0.5, 0.5, 0.5),
}


def store_path():
    folder = os.path.join(GLib.get_user_data_dir(), "freemac")
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, "mines.json")


def load_store():
    try:
        with open(store_path(), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_store(data):
    try:
        tmp = store_path() + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, store_path())
    except OSError:
        pass


class Field:
    def __init__(self, cols, rows, count):
        self.cols, self.rows, self.count = cols, rows, count
        self.mines = set()
        self.opened = set()
        self.flags = set()
        self.state = "ready"        # ready, playing, won, lost
        self.boom = None
        self.started = None
        self.finished = None

    def neighbours(self, cell):
        c, r = cell
        for dc in (-1, 0, 1):
            for dr in (-1, 0, 1):
                if (dc or dr) and 0 <= c + dc < self.cols and 0 <= r + dr < self.rows:
                    yield c + dc, r + dr

    def around(self, cell):
        return sum(1 for n in self.neighbours(cell) if n in self.mines)

    def _lay(self, first, rng=random):
        keep = {first, *self.neighbours(first)}
        spots = [(c, r) for c in range(self.cols) for r in range(self.rows) if (c, r) not in keep]
        if len(spots) < self.count:     # very small fields: only the first square is kept clear
            spots = [(c, r) for c in range(self.cols) for r in range(self.rows) if (c, r) != first]
        self.mines = set(rng.sample(spots, self.count))
        self.state = "playing"
        self.started = time.monotonic()

    def seconds(self):
        if self.started is None:
            return 0
        return int((self.finished or time.monotonic()) - self.started)

    def open(self, cell):
        """Open a square (and the empty area around it). Returns the squares opened."""
        if self.state == "ready":
            self._lay(cell)
        if self.state != "playing" or cell in self.flags or cell in self.opened:
            return []
        if cell in self.mines:
            self.state, self.boom, self.finished = "lost", cell, time.monotonic()
            return [cell]
        opened = []
        todo = [cell]
        while todo:
            here = todo.pop()
            if here in self.opened or here in self.flags:
                continue
            self.opened.add(here)
            opened.append(here)
            if self.around(here) == 0:
                todo.extend(n for n in self.neighbours(here) if n not in self.opened)
        if len(self.opened) == self.cols * self.rows - self.count:
            self.state, self.finished = "won", time.monotonic()
            self.flags = set(self.mines)
        return opened

    def chord(self, cell):
        """On an opened number with enough flags around it, open the rest."""
        if self.state != "playing" or cell not in self.opened:
            return []
        near = list(self.neighbours(cell))
        if sum(1 for n in near if n in self.flags) != self.around(cell):
            return []
        opened = []
        for n in near:
            if n not in self.flags and n not in self.opened:
                opened += self.open(n)
                if self.state == "lost":
                    break
        return opened

    def flag(self, cell):
        if self.state not in ("ready", "playing") or cell in self.opened:
            return
        self.flags.symmetric_difference_update({cell})


# -- drawing --

def rounded(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
    cr.close_path()


def draw_mine(cr, x, y, s):
    cx, cy, r = x + s / 2, y + s / 2, s * 0.22
    cr.set_source_rgb(0.12, 0.12, 0.14)
    cr.set_line_width(max(1.5, s * 0.07))
    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    for i in range(8):
        a = i * math.pi / 4
        cr.move_to(cx + math.cos(a) * r * 0.6, cy + math.sin(a) * r * 0.6)
        cr.line_to(cx + math.cos(a) * r * 1.55, cy + math.sin(a) * r * 1.55)
    cr.stroke()
    cr.arc(cx, cy, r, 0, 2 * math.pi)
    cr.fill()
    cr.set_source_rgba(1, 1, 1, 0.8)
    cr.arc(cx - r * 0.35, cy - r * 0.35, r * 0.25, 0, 2 * math.pi)
    cr.fill()


def draw_flag(cr, x, y, s):
    cr.set_source_rgb(0.25, 0.25, 0.28)
    cr.set_line_width(max(1.5, s * 0.07))
    cr.move_to(x + s * 0.38, y + s * 0.22)
    cr.line_to(x + s * 0.38, y + s * 0.78)
    cr.stroke()
    cr.move_to(x + s * 0.26, y + s * 0.78)
    cr.line_to(x + s * 0.6, y + s * 0.78)
    cr.stroke()
    cr.move_to(x + s * 0.4, y + s * 0.22)
    cr.line_to(x + s * 0.76, y + s * 0.36)
    cr.line_to(x + s * 0.4, y + s * 0.5)
    cr.close_path()
    cr.set_source_rgb(1, 0.23, 0.19)
    cr.fill()


class Board(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(hexpand=True, vexpand=True)
        self.window = window
        self.pressed = None
        self.hover = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("button-release-event", self._release)
        self.connect("motion-notify-event", self._motion)
        self.connect("leave-notify-event", lambda *_a: self._set_hover(None))

    @property
    def field(self):
        return self.window.field

    def layout(self):
        f = self.field
        width, height = self.get_allocated_width(), self.get_allocated_height()
        pad = 16
        size = max(14, min((width - pad * 2) / f.cols, (height - pad * 2) / f.rows, 48))
        left = (width - size * f.cols) / 2
        top = (height - size * f.rows) / 2
        return left, top, size

    def cell_at(self, x, y):
        left, top, size = self.layout()
        c, r = int((x - left) // size), int((y - top) // size)
        if 0 <= c < self.field.cols and 0 <= r < self.field.rows and x >= left and y >= top:
            return c, r
        return None

    def _set_hover(self, cell):
        if cell != self.hover:
            self.hover = cell
            self.queue_draw()

    def _draw(self, _w, cr):
        f = self.field
        width, height = self.get_allocated_width(), self.get_allocated_height()
        cr.set_source_rgb(0.93, 0.93, 0.95)
        cr.paint()
        left, top, size = self.layout()
        gap = max(1, size * 0.06)
        rounded(cr, left - 6, top - 6, size * f.cols + 12, size * f.rows + 12, 10)
        cr.set_source_rgb(0.80, 0.81, 0.85)
        cr.fill()
        font = Pango.FontDescription("Inter Bold")
        font.set_absolute_size(size * 0.55 * Pango.SCALE)
        over = f.state in ("won", "lost")
        held = set()
        if self.pressed and self.pressed[1] == "chord":
            held = {n for n in f.neighbours(self.pressed[0]) if n not in f.opened and n not in f.flags}
        elif self.pressed:
            held = {self.pressed[0]}
        for c in range(f.cols):
            for r in range(f.rows):
                cell = (c, r)
                x, y = left + c * size + gap / 2, top + r * size + gap / 2
                s = size - gap
                if cell in f.opened or (over and cell in f.mines and cell not in f.flags):
                    rounded(cr, x, y, s, s, s * 0.14)
                    if cell == f.boom:
                        cr.set_source_rgb(1, 0.42, 0.38)
                    else:
                        cr.set_source_rgb(0.98, 0.98, 0.99)
                    cr.fill()
                    if cell in f.mines:
                        draw_mine(cr, x, y, s)
                        continue
                    n = f.around(cell)
                    if n:
                        layout = PangoCairo.create_layout(cr)
                        layout.set_font_description(font)
                        layout.set_text(str(n), -1)
                        tw, th = layout.get_pixel_size()
                        cr.set_source_rgb(*NUMBER_COLOURS[n])
                        cr.move_to(x + (s - tw) / 2, y + (s - th) / 2)
                        PangoCairo.show_layout(cr, layout)
                    continue
                down = cell in held and not over
                rounded(cr, x, y, s, s, s * 0.14)
                grad = cairo.LinearGradient(x, y, x, y + s)
                if down:
                    grad.add_color_stop_rgb(0, 0.82, 0.84, 0.88)
                    grad.add_color_stop_rgb(1, 0.86, 0.88, 0.91)
                elif cell == self.hover and not over:
                    grad.add_color_stop_rgb(0, 0.62, 0.78, 1.0)
                    grad.add_color_stop_rgb(1, 0.45, 0.65, 0.98)
                else:
                    grad.add_color_stop_rgb(0, 0.55, 0.70, 0.96)
                    grad.add_color_stop_rgb(1, 0.36, 0.55, 0.90)
                cr.set_source(grad)
                cr.fill_preserve()
                cr.set_source_rgba(1, 1, 1, 0.35)
                cr.set_line_width(1)
                cr.stroke()
                if cell in f.flags:
                    rounded(cr, x + s * 0.12, y + s * 0.12, s * 0.76, s * 0.76, s * 0.12)
                    cr.set_source_rgba(1, 1, 1, 0.9)
                    cr.fill()
                    draw_flag(cr, x, y, s)
                    if over and cell not in f.mines:
                        cr.set_source_rgb(0.9, 0.1, 0.1)
                        cr.set_line_width(max(2, s * 0.08))
                        cr.move_to(x + s * 0.2, y + s * 0.2)
                        cr.line_to(x + s * 0.8, y + s * 0.8)
                        cr.move_to(x + s * 0.8, y + s * 0.2)
                        cr.line_to(x + s * 0.2, y + s * 0.8)
                        cr.stroke()
        if f.state == "won":
            self._banner(cr, width, height, "You cleared the field!")
        elif f.state == "lost":
            self._banner(cr, width, height, "Boom! Click New Game to try again.")

    def _banner(self, cr, width, height, text):
        layout = PangoCairo.create_layout(cr)
        font = Pango.FontDescription("Inter Bold")
        font.set_absolute_size(18 * Pango.SCALE)
        layout.set_font_description(font)
        layout.set_text(text, -1)
        tw, th = layout.get_pixel_size()
        x, y = (width - tw) / 2 - 18, height - th - 34
        rounded(cr, x, y, tw + 36, th + 18, (th + 18) / 2)
        cr.set_source_rgba(0.1, 0.1, 0.12, 0.82)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.move_to(x + 18, y + 9)
        PangoCairo.show_layout(cr, layout)

    def _press(self, _w, event):
        if event.type != Gdk.EventType.BUTTON_PRESS:
            return True
        cell = self.cell_at(event.x, event.y)
        if cell is None:
            return True
        f = self.field
        flagging = event.button == 3 or (event.button == 1 and event.state & Gdk.ModifierType.CONTROL_MASK)
        if flagging:
            if cell not in f.opened:
                f.flag(cell)
                self.window.changed()
            return True
        if event.button == 1:
            self.pressed = (cell, "chord" if cell in f.opened else "open")
            self.queue_draw()
        return True

    def _motion(self, _w, event):
        cell = self.cell_at(event.x, event.y)
        self._set_hover(cell)
        if self.pressed and cell != self.pressed[0]:
            self.pressed = (cell, "chord" if cell in self.field.opened else "open") if cell else None
            self.queue_draw()
        return True

    def _release(self, _w, event):
        if event.button != 1 or not self.pressed:
            return True
        cell, kind = self.pressed
        self.pressed = None
        if kind == "chord":
            self.field.chord(cell)
        else:
            self.field.open(cell)
        self.window.changed()
        return True


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Mines")
        self.store = load_store()
        self.size = self.store.get("size") if self.store.get("size") in SIZES else "small"
        header = Gtk.HeaderBar(show_close_button=True, title="Mines")
        self.header = header
        self.set_titlebar(header)
        new = Gtk.Button(label="New Game")
        new.connect("clicked", lambda _b: self.new_game())
        header.pack_start(new)
        self.size_box = Gtk.Box(spacing=0)
        self.size_box.get_style_context().add_class("linked")
        self.size_buttons = {}
        group = None
        for key, (label, *_rest) in SIZES.items():
            button = Gtk.RadioButton.new_with_label_from_widget(group, label)
            button.set_mode(False)
            group = group or button
            button.connect("toggled", self._size_toggled, key)
            self.size_box.pack_start(button, False, False, 0)
            self.size_buttons[key] = button
        header.pack_end(self.size_box)
        self.counter = Gtk.Label()
        self.counter.get_style_context().add_class("dim-label")
        header.pack_start(self.counter)

        self.board = Board(self)
        self.add(self.board)
        self.field = None
        self.size_buttons[self.size].set_active(True)
        self.new_game()
        menus.add_actions(self, {"new": self.new_game, "close": self.close, "small": lambda: self.pick("small"),
                                 "medium": lambda: self.pick("medium"), "large": lambda: self.pick("large"),
                                 "best": self.show_best})
        GLib.timeout_add(500, self._clock)
        self.show_all()

    def pick(self, size):
        self.size_buttons[size].set_active(True)

    def _size_toggled(self, button, key):
        if button.get_active() and key != self.size:
            self.size = key
            self.store["size"] = key
            save_store(self.store)
            self.new_game()

    def new_game(self):
        _label, cols, rows, count = SIZES[self.size]
        self.field = Field(cols, rows, count)
        width = {"small": 660, "medium": 760, "large": 1180}[self.size]
        height = {"small": 600, "medium": 820, "large": 680}[self.size]
        self.resize(width, height)
        self.update()

    def _clock(self):
        if self.get_window() is None:
            return False
        if self.field.state == "playing":
            self.update()
        return True

    def update(self):
        f = self.field
        left = f.count - len(f.flags)
        seconds = f.seconds()
        self.counter.set_text(f"⚑ {left}   ⏱ {seconds // 60}:{seconds % 60:02d}")
        best = self.store.get("best", {}).get(self.size)
        self.header.set_subtitle(f"Best {best // 60}:{best % 60:02d}" if best is not None else
                                 f"{f.count} mines")
        self.board.queue_draw()

    def changed(self):
        f = self.field
        if f.state == "won":
            best = self.store.setdefault("best", {})
            if self.size not in best or f.seconds() < best[self.size]:
                best[self.size] = f.seconds()
                save_store(self.store)
                self.update()
                self.header.set_subtitle("A new best time!")
                return
        self.update()

    def show_best(self):
        best = self.store.get("best", {})
        lines = []
        for key, (label, *_rest) in SIZES.items():
            t = best.get(key)
            lines.append(f"{label}: {t // 60}:{t % 60:02d}" if t is not None else f"{label}: not yet")
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK,
                                   text="Best Times", secondary_text="\n".join(lines))
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_File", [[("New Game", "win.new", "<Ctrl>n")], [("Close", "win.close", "<Ctrl>w")]]),
        ("_Game", [[("Small Field", "win.small", "<Ctrl>1"), ("Medium Field", "win.medium", "<Ctrl>2"),
                    ("Large Field", "win.large", "<Ctrl>3")], [("Best Times", "win.best", None)]]),
    ])


class Mines(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.new", "<Control>n"), ("win.close", "<Control>w"), ("win.small", "<Control>1"),
                             ("win.medium", "<Control>2"), ("win.large", "<Control>3")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-mines")
    return Mines().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
