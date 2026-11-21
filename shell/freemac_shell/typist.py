# SPDX-License-Identifier: GPL-3.0-or-later
"""Typist: learn to type without looking at the keys.

Lessons start with four keys under the fingers' resting place and add two
keys at a time, first across the middle row, then the top and bottom rows,
then capital letters, numbers and whole sentences. A keyboard under the text
lights up the next key in the colour of the finger that should press it. Each
lesson keeps its best speed (in words a minute) and accuracy, and earns up to
three stars.

Original freemac code. Lesson text is made up from the keys each lesson
teaches, using freemac's own list of everyday words. Progress is kept in
~/.local/share/freemac/typist.json.
"""
import json
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

APP_ID = "org.freemac.Typist"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "typist.json")
LINES = 3          # lines in a lesson
LINE_LENGTH = 44   # about this many characters a line

# (name, new keys, kind). Each lesson uses its own keys and every key before it.
LESSONS = [
    ("Home keys: F and J", "fj", "keys"),
    ("Home keys: D and K", "dk", "keys"),
    ("Home keys: S and L", "sl", "keys"),
    ("Home keys: A and ;", "a;", "keys"),
    ("Middle row: G and H", "gh", "words"),
    ("Top row: E and I", "ei", "words"),
    ("Top row: R and U", "ru", "words"),
    ("Top row: T and O", "to", "words"),
    ("Top row: W and Y", "wy", "words"),
    ("Top row: Q and P", "qp", "words"),
    ("Bottom row: C and N", "cn", "words"),
    ("Bottom row: V and M", "vm", "words"),
    ("Bottom row: B and X", "bx", "words"),
    ("Bottom row: Z and ,", "z,", "words"),
    ("Punctuation: . and ?", ".?", "words"),
    ("Capital letters", "", "capitals"),
    ("Numbers", "1234567890", "numbers"),
    ("Sentences", "", "sentences"),
    ("Longer sentences", "", "long"),
]

WORDS = """
a about after again air all also always am an and animal any are arm as ask at away baby back bad
bag ball band bank be bear because bed been before begin best big bird black blue boat body book both
box boy bring brother brown bus but buy by cake call came can car care cat change child city class
clean close cold come cook cool could cow cup cut dad dance dark day dear deep desk did dinner do dog
door down draw dream dress drink drive duck each ear early earth east easy eat egg end even every eye
face fall family far farm fast father feel feet few field find fine fire first fish five floor fly
food foot for forest found four fox free friend frog from front fruit full fun game garden gave get
girl give glad go goat gold good grass great green ground grow had hair half hall hand happy hard has
hat have he head hear heart help her here high hill him his hold home hope horse hot house how i ice
idea if in inside is it its jam job join joke jump just keep key kid kind king kite know lake lamp
land large last late laugh lead leaf learn left leg let letter light like line lion list little live
long look lot loud love low lunch made make man many map may me meet milk mind moon more morning most
mother mouse move much music must my name near need nest net never new next nice night nine no north
nose not note now number of off often oil old on once one only open or orange other our out over own
page paint paper park part party pass pen people pet pick pie pig place plan plant play please pond
pool pot pull push put queen quick quiet quite rabbit rain read ready red rest ride right ring river
road rock roof room round run sad said sail salt same sand sat saw say school sea seat see seed sell
send set seven shall she sheep ship shoe shop short should show side sing sister sit six sky sleep
slow small smile snow so soft some song soon sound south spell spring star start stay step stick still
stop story street strong sun sure swim table tail take talk tall tea team tell ten than thank that
the their them then there these they thing think this three tide time to today together too took top
town toy tree trip true try turn two under up us use very visit wait walk wall want warm was wash
water wave way we week well went were west wet what wheel when where which white who why will win
wind window wish with wood word work world would write yard year yellow yes yet you young your zoo
""".split()

SENTENCES = [
    "The little fox jumps over a log by the river.",
    "We packed a lunch and walked up the green hill.",
    "My cat likes to sleep in the warm sun all day.",
    "Five quick frogs sat on a big lily pad.",
    "Please close the door when you come inside.",
    "Our team won the game in the very last minute.",
    "The moon looks bright and round tonight.",
    "Can you help me find my blue hat?",
    "A small boat sails across the quiet lake.",
    "We plant seeds in spring and pick beans in summer.",
    "The bus stops at the corner near my school.",
    "Zebras, yaks and wolves visit the zoo at night.",
    "Mix the eggs, milk and flour, then bake the cake.",
    "Every star in the sky is a sun far away.",
    "Jake brought six extra jars of honey to the fair.",
    "Grandma tells the best stories by the fire.",
]

LONG = [
    "When the rain stopped, we ran outside and jumped in every puddle we could find.",
    "Learning to type takes practice, so keep your eyes on the screen and trust your fingers.",
    "The old lighthouse has watched over the harbour for more than a hundred years.",
    "If you mix blue and yellow paint together, you get a bright, fresh green.",
    "Our class grew sunflowers that were taller than the teacher by the end of June.",
    "A good friend listens, shares their snacks and laughs at your worst jokes.",
]

ROWS = [
    ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"],
    ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"],
]
ROW_INDENT = [0.0, 1.5, 1.8, 2.3]     # in key widths, after the row's first wide key
SHIFTED = {"?": "/", ":": ";", '"': "'", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
           "&": "7", "*": "8", "(": "9", ")": "0", "_": "-", "+": "=", "<": ",", ">": ".", "~": "`"}
FINGERS = {}
for chars, finger in (("`1qaz", 0), ("2wsx", 1), ("3edc", 2), ("45rtfgvb", 3), ("67yuhjnm", 4),
                      ("8ik,", 5), ("9ol.", 6), ("0p;/-=[]'", 7)):
    for ch in chars:
        FINGERS[ch] = finger
FINGER_NAMES = ["left little finger", "left ring finger", "left middle finger", "left pointer finger",
                "right pointer finger", "right middle finger", "right ring finger", "right little finger"]
FINGER_COLOURS = [(0.93, 0.38, 0.45), (0.98, 0.62, 0.25), (0.96, 0.82, 0.25), (0.45, 0.8, 0.4),
                  (0.3, 0.75, 0.85), (0.42, 0.55, 0.95), (0.68, 0.48, 0.92), (0.92, 0.45, 0.8)]


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


def keys_up_to(number):
    """Every lower-case key taught by lessons 0..number."""
    keys = ""
    for _name, new, kind in LESSONS[: number + 1]:
        if kind in ("keys", "words"):
            keys += new
    return keys


def make_text(number, rng=random):
    """The lines of one lesson."""
    _name, new, kind = LESSONS[number]
    if kind == "sentences":
        return rng.sample(SENTENCES, LINES)
    if kind == "long":
        return rng.sample(LONG, 2)
    letters = set(keys_up_to(number)) - set(",.?;")
    usable = [w for w in WORDS if set(w) <= letters]
    lines = []
    for _ in range(LINES):
        parts = []
        while sum(len(p) + 1 for p in parts) < LINE_LENGTH:
            if kind == "keys" or len(usable) < 8:
                pool = new if rng.random() < 0.6 else keys_up_to(number)
                pool = pool.replace(";", "") if rng.random() < 0.7 else pool
                parts.append("".join(rng.choice(pool) for _ in range(rng.randint(2, 4))))
            elif kind == "capitals":
                parts.append(rng.choice(usable).capitalize() if rng.random() < 0.5 else rng.choice(usable))
            elif kind == "numbers":
                parts.append("".join(rng.choice(new) for _ in range(rng.randint(1, 4)))
                             if rng.random() < 0.5 else rng.choice(usable))
            else:
                # New keys come up often: prefer words that have one.
                with_new = [w for w in usable if set(w) & set(new)]
                share = 0.6 if len(with_new) >= 5 else 0.3
                parts.append(rng.choice(with_new if with_new and rng.random() < share else usable))
        taught = keys_up_to(number)
        marks = [m for m in ",." if m in taught] if kind in ("words", "capitals", "numbers") else []
        if marks:
            i = rng.randint(2, 4)
            while i < len(parts) - 1:
                parts[i] += rng.choice(marks)
                i += rng.randint(3, 5)
        if ";" in new:
            parts[len(parts) // 2] += ";"
        line = " ".join(parts)
        if kind != "keys" and "?" in taught:
            line = line.rstrip(".,") + rng.choice("?.")
        elif kind != "keys" and "." in taught:
            line = line.rstrip(".,") + "."
        lines.append(line.strip())
    return lines


def stars_for(wpm, accuracy):
    if accuracy >= 0.97 and wpm >= 20:
        return 3
    if accuracy >= 0.93 and wpm >= 10:
        return 2
    if accuracy >= 0.85:
        return 1
    return 0


class Run:
    """One go at a lesson: where the cursor is and how it's going."""

    def __init__(self, lines):
        self.lines = lines
        self.line = 0
        self.col = 0
        self.mistake = False        # the key under the cursor was mistyped
        self.typed = 0
        self.errors = 0
        self.missed = set()         # (line, col) that were mistyped at least once
        self.started = None
        self.finished = None

    @property
    def done(self):
        return self.line >= len(self.lines)

    def expected(self):
        if self.done:
            return None
        text = self.lines[self.line]
        return text[self.col] if self.col < len(text) else "\n"

    def press(self, ch):
        """A typed character. Returns True if it was right."""
        if self.done:
            return False
        if self.started is None:
            self.started = time.monotonic()
        want = self.expected()
        self.typed += 1
        if ch == want or (want == "\n" and ch in ("\n", " ")):
            self.mistake = False
            if want == "\n":
                self.line += 1
                self.col = 0
                if self.done:
                    self.finished = time.monotonic()
            else:
                self.col += 1
            return True
        self.errors += 1
        self.mistake = True
        self.missed.add((self.line, self.col))
        return False

    def seconds(self):
        if self.started is None:
            return 0.0
        return (self.finished or time.monotonic()) - self.started

    def chars_done(self):
        return sum(len(t) + 1 for t in self.lines[: self.line]) + self.col

    def wpm(self):
        minutes = self.seconds() / 60
        return (self.chars_done() / 5) / minutes if minutes > 0.02 else 0.0

    def accuracy(self):
        return (self.typed - self.errors) / self.typed if self.typed else 1.0

    def fraction(self):
        total = sum(len(t) + 1 for t in self.lines)
        return self.chars_done() / total if total else 1.0


def key_for(ch):
    """(key on the keyboard, needs Shift)."""
    if ch is None:
        return None, False
    if ch == "\n":
        return "return", False
    if ch == " ":
        return "space", False
    if ch in SHIFTED:
        return SHIFTED[ch], True
    if ch.isupper():
        return ch.lower(), True
    return ch, False


def finger_for(ch):
    base, _shift = key_for(ch)
    if base in ("space",):
        return "a thumb"
    if base == "return":
        return FINGER_NAMES[7]
    return FINGER_NAMES[FINGERS[base]] if base in FINGERS else ""


class Board(Gtk.DrawingArea):
    """The lesson's text with a keyboard underneath."""

    def __init__(self, window):
        super().__init__()
        self.window = window
        self.show_keyboard = True
        self.flash = 0.0
        self.connect("draw", self._draw)

    def _draw(self, _widget, cr):
        run = self.window.run
        width = self.get_allocated_width()
        height = self.get_allocated_height()
        dark = self.get_style_context().lookup_color("theme_bg_color")[1].red < 0.5
        fg = (0.93, 0.93, 0.95) if dark else (0.12, 0.12, 0.14)
        cr.set_source_rgb(*((0.13, 0.13, 0.15) if dark else (0.97, 0.97, 0.98)))
        cr.paint()
        if run is None:
            return
        if run.done:
            self._draw_result(cr, width, height, fg)
            return
        text_top = height * 0.12
        size = max(18, min(30, int(width / 34)))
        self._draw_line(cr, run, run.line, width, text_top, size, fg, current=True)
        if run.line + 1 < len(run.lines):
            self._draw_line(cr, run, run.line + 1, width, text_top + size * 2.6, int(size * 0.75), fg)
        hint = finger_for(run.expected())
        _base, shift = key_for(run.expected())
        tip = f"Use your {hint}" if hint else ""
        if shift:
            tip += " and hold Shift with the other hand"
        if run.expected() == "\n":
            tip = "End of the line: press Return (or Space)"
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription("Inter 13"))
        layout.set_text(tip, -1)
        tw, _th = layout.get_pixel_size()
        cr.set_source_rgba(*fg, 0.55)
        cr.move_to((width - tw) / 2, text_top + size * 4.6)
        PangoCairo.show_layout(cr, layout)
        if self.show_keyboard:
            self._draw_keyboard(cr, width, height, run.expected(), dark, fg)

    def _draw_line(self, cr, run, number, width, top, size, fg, current=False):
        text = run.lines[number]
        if current and run.col >= len(text):
            text = text + "↵"
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription(f"DejaVu Sans Mono {size}px"))
        shown = text.replace(" ", " ") if not current else text
        layout.set_text(shown, -1)
        attrs = Pango.AttrList()
        if current:
            done = len(text[: run.col].encode())
            green = Pango.attr_foreground_new(int(0.2 * 65535), int(0.62 * 65535), int(0.3 * 65535))
            green.start_index, green.end_index = 0, done
            attrs.insert(green)
            for line, col in run.missed:
                if line == number and col < run.col:
                    red = Pango.attr_foreground_new(int(0.9 * 65535), int(0.25 * 65535), int(0.2 * 65535))
                    red.start_index = len(text[:col].encode())
                    red.end_index = len(text[: col + 1].encode())
                    attrs.insert(red)
        else:
            dim = Pango.attr_foreground_alpha_new(int(0.4 * 65535))
            attrs.insert(dim)
        layout.set_attributes(attrs)
        tw, th = layout.get_pixel_size()
        left = max(16, (width - tw) / 2)
        if current:
            pos = layout.index_to_pos(len(text[: run.col].encode()))
            x = left + pos.x / Pango.SCALE
            w = max(pos.width / Pango.SCALE, size * 0.6)
            if run.mistake:
                cr.set_source_rgba(0.92, 0.25, 0.2, 0.28)
            else:
                cr.set_source_rgba(0.04, 0.49, 1.0, 0.2)
            cr.rectangle(x - 1, top - 2, w + 2, th + 4)
            cr.fill()
            cr.set_source_rgba(0.04, 0.49, 1.0, 0.95)
            cr.rectangle(x, top + th + 1, w, 3)
            cr.fill()
        cr.set_source_rgb(*fg)
        cr.move_to(left, top)
        PangoCairo.show_layout(cr, layout)

    def _draw_keyboard(self, cr, width, height, expected, dark, fg):
        base, shift = key_for(expected)
        unit = min((width - 40) / 15.2, (height * 0.42) / 5.4)
        left = (width - unit * 15) / 2
        top = height - unit * 5.4 - 16
        gap = unit * 0.1

        def key(x, y, w, label, finger=None, lit=False):
            cr.new_sub_path()
            r = unit * 0.14
            x0, y0, x1, y1 = x + gap / 2, y + gap / 2, x + w - gap / 2, y + unit - gap / 2
            cr.arc(x1 - r, y0 + r, r, -1.5708, 0)
            cr.arc(x1 - r, y1 - r, r, 0, 1.5708)
            cr.arc(x0 + r, y1 - r, r, 1.5708, 3.1416)
            cr.arc(x0 + r, y0 + r, r, 3.1416, 4.7124)
            cr.close_path()
            colour = FINGER_COLOURS[finger] if finger is not None else (0.6, 0.6, 0.62)
            if lit:
                cr.set_source_rgb(*colour)
            else:
                cr.set_source_rgba(*colour, 0.22 if dark else 0.18)
            cr.fill_preserve()
            cr.set_source_rgba(*fg, 0.25)
            cr.set_line_width(1)
            cr.stroke()
            layout = PangoCairo.create_layout(cr)
            layout.set_font_description(Pango.FontDescription(f"Inter {max(9, int(unit * 0.32))}px"))
            layout.set_text(label.upper() if len(label) == 1 else label, -1)
            lw, lh = layout.get_pixel_size()
            cr.set_source_rgba(*((0.1, 0.1, 0.12) if lit else fg), 1.0 if lit else 0.8)
            cr.move_to(x + (w - lw) / 2, y + (unit - lh) / 2)
            PangoCairo.show_layout(cr, layout)

        need_left_shift = shift and base in FINGERS and FINGERS[base] >= 4
        need_right_shift = shift and base in FINGERS and FINGERS[base] < 4
        firsts = [("", 0), ("tab", 1.5), ("caps", 1.8), ("shift", 2.3)]
        for r, row in enumerate(ROWS):
            y = top + r * unit
            label, w = firsts[r]
            x = left
            if w:
                key(x, y, w * unit, label, 0 if r == 3 else None, lit=r == 3 and need_left_shift)
                x += w * unit
            for ch in row:
                key(x, y, unit, ch, FINGERS.get(ch), lit=ch == base)
                x += unit
            rest = left + unit * 15 - x
            if r == 0:
                key(x, y, rest, "delete")
            elif r == 2:
                key(x, y, rest, "return", 7, lit=base == "return")
            elif r == 3:
                key(x, y, rest, "shift", 7, lit=need_right_shift)
            elif rest > unit * 0.3:
                key(x, y, rest, "\\", 7)
        y = top + 4 * unit
        key(left + unit * 4, y, unit * 6.5, "space", None, lit=base == "space")
        if base == "space":
            pass

    def _draw_result(self, cr, width, height, fg):
        run = self.window.run
        wpm, acc = run.wpm(), run.accuracy()
        stars = stars_for(wpm, acc)
        layout = PangoCairo.create_layout(cr)
        layout.set_alignment(Pango.Alignment.CENTER)
        layout.set_font_description(Pango.FontDescription("Inter 64px"))
        layout.set_text("★" * stars + "☆" * (3 - stars), -1)
        tw, th = layout.get_pixel_size()
        cr.set_source_rgb(0.98, 0.72, 0.1)
        cr.move_to((width - tw) / 2, height * 0.22)
        PangoCairo.show_layout(cr, layout)
        words = ["Keep practising!", "Nice work!", "Great typing!", "Superb!"][stars]
        lines = [(words, "Inter Bold 30px", 1.0),
                 (f"{wpm:.0f} words a minute  ·  {acc * 100:.0f}% right", "Inter 20px", 0.8),
                 ("Press Return for the next lesson, or Space to try again", "Inter 15px", 0.55)]
        y = height * 0.22 + th + 24
        for text, font, alpha in lines:
            layout = PangoCairo.create_layout(cr)
            layout.set_font_description(Pango.FontDescription(font))
            layout.set_text(text, -1)
            tw, lh = layout.get_pixel_size()
            cr.set_source_rgba(*fg, alpha)
            cr.move_to((width - tw) / 2, y)
            PangoCairo.show_layout(cr, layout)
            y += lh + 14


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Typist")
        self.set_default_size(1000, 700)
        self.store = load_store()
        self.store.setdefault("lessons", {})
        header = Gtk.HeaderBar(show_close_button=True, title="Typist")
        self.header = header
        self.set_titlebar(header)
        restart = Gtk.Button(label="Start Again")
        restart.connect("clicked", lambda _b: self.start(self.number))
        header.pack_start(restart)
        self.speed = Gtk.Label()
        self.speed.get_style_context().add_class("dim-label")
        header.pack_end(self.speed)

        paned = Gtk.Paned()
        self.list = Gtk.ListBox()
        self.list.connect("row-activated", lambda _l, row: self.start(row.get_index()))
        side = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side.set_size_request(250, -1)
        side.add(self.list)
        paned.pack1(side, False, False)
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.progress = Gtk.ProgressBar()
        right.pack_start(self.progress, False, False, 0)
        self.board = Board(self)
        self.board.set_can_focus(True)
        right.pack_start(self.board, True, True, 0)
        paned.pack2(right, True, False)
        self.add(paned)
        self.run = None
        self.number = 0
        self._fill_list()
        self.connect("key-press-event", self._key)
        menus.add_actions(self, {"close": self.close, "restart": lambda: self.start(self.number),
                                 "next": lambda: self.start(min(self.number + 1, len(LESSONS) - 1)),
                                 "previous": lambda: self.start(max(self.number - 1, 0))})
        menus.add_toggle(self, "keyboard", True, self._toggle_keyboard)
        last = self.store.get("last", 0)
        self.start(last if isinstance(last, int) and 0 <= last < len(LESSONS) else 0)
        GLib.timeout_add(500, self._tick)
        self.show_all()

    def _toggle_keyboard(self, on):
        self.board.show_keyboard = on
        self.board.queue_draw()

    def _fill_list(self):
        for row in self.list.get_children():
            self.list.remove(row)
        for number, (name, _new, _kind) in enumerate(LESSONS):
            best = self.store["lessons"].get(str(number), {})
            stars = best.get("stars", 0) if isinstance(best, dict) else 0
            box = Gtk.Box(spacing=8)
            box.set_border_width(6)
            title = Gtk.Label(label=f"{number + 1}. {name}", xalign=0, ellipsize=Pango.EllipsizeMode.END)
            box.pack_start(title, True, True, 0)
            mark = Gtk.Label(label="★" * stars + "☆" * (3 - stars))
            mark.get_style_context().add_class("dim-label" if not stars else "typist-stars")
            box.pack_end(mark, False, False, 0)
            row = Gtk.ListBoxRow()
            row.add(box)
            self.list.add(row)
        self.list.show_all()
        row = self.list.get_row_at_index(self.number)
        if row:
            self.list.select_row(row)

    def start(self, number):
        self.number = number
        self.store["last"] = number
        save_store(self.store)
        self.run = Run(make_text(number))
        name = LESSONS[number][0]
        self.header.set_subtitle(f"Lesson {number + 1}: {name}")
        row = self.list.get_row_at_index(number)
        if row:
            self.list.select_row(row)
        self.update()
        self.board.grab_focus()

    def _key(self, _widget, event):
        state = event.state & Gtk.accelerator_get_default_mod_mask()
        if state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK
                    | Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.META_MASK):
            return False
        if self.run is None:
            return False
        if self.run.done:
            if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                self.start(min(self.number + 1, len(LESSONS) - 1))
                return True
            if event.keyval == Gdk.KEY_space:
                self.start(self.number)
                return True
            return False
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            ch = "\n"
        else:
            code = Gdk.keyval_to_unicode(event.keyval)
            if not code:
                return False
            ch = chr(code)
        self.run.press(ch)
        if self.run.done:
            self.finished()
        self.update()
        return True

    def finished(self):
        run = self.run
        wpm, acc = run.wpm(), run.accuracy()
        stars = stars_for(wpm, acc)
        best = self.store["lessons"].get(str(self.number))
        best = best if isinstance(best, dict) else {}
        if stars > best.get("stars", -1) or (stars == best.get("stars") and wpm > best.get("wpm", 0)):
            self.store["lessons"][str(self.number)] = {"stars": stars, "wpm": round(wpm, 1),
                                                       "accuracy": round(acc, 3)}
            save_store(self.store)
            self._fill_list()

    def _tick(self):
        if self.get_window() is None:
            return False
        if self.run and self.run.started and not self.run.done:
            self.update()
        return True

    def update(self):
        run = self.run
        self.progress.set_fraction(run.fraction())
        if run.started:
            self.speed.set_text(f"{run.wpm():.0f} words a minute · {run.accuracy() * 100:.0f}% right")
        else:
            best = self.store["lessons"].get(str(self.number))
            self.speed.set_text(f"Best {best['wpm']:.0f} words a minute" if isinstance(best, dict)
                                and best.get("wpm") else "Start typing when you're ready")
        self.board.queue_draw()


CSS = b".typist-stars { color: #e5a00d; }"


def menubar():
    return menus.menubar([
        ("_File", [[("Close", "win.close", "<Ctrl>w")]]),
        ("_Lesson", [[("Start Again", "win.restart", "<Ctrl>r")],
                     [("Previous Lesson", "win.previous", "<Ctrl>bracketleft"),
                      ("Next Lesson", "win.next", "<Ctrl>bracketright")]]),
        ("_View", [[("Show Keyboard", "win.keyboard", "<Ctrl>k")]]),
    ])


class Typist(Gtk.Application):
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
        for action, keys in (("win.close", "<Control>w"), ("win.restart", "<Control>r"),
                             ("win.previous", "<Control>bracketleft"), ("win.next", "<Control>bracketright"),
                             ("win.keyboard", "<Control>k")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-typist")
    return Typist().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
