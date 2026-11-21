# SPDX-License-Identifier: GPL-3.0-or-later
"""Sums: maths practice for children.

Pick adding, taking away, times or sharing (dividing) and a level, then
answer ten questions. Type the answer, or tap it on the keypad, and press
Return. A wrong answer gets one more try before the answer is shown. A round
earns up to three stars, and the best stars for each level are kept.

The Times Tables page shows the 12 by 12 chart; click a number along the top
to practise just that table.

Original freemac code. Results are kept in ~/.local/share/freemac/sums.json.
"""
import json
import os
import random
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Sums"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "sums.json")
ROUND = 10
OPERATIONS = (
    ("add", "Adding", "+", ("Up to 10", "Up to 20", "Up to 50", "Up to 100", "Up to 1000")),
    ("subtract", "Taking Away", "−", ("From 10", "From 20", "From 50", "From 100", "From 1000")),
    ("multiply", "Times", "×", ("2, 5 and 10", "3 and 4", "6, 7, 8 and 9", "All to 12", "Bigger")),
    ("divide", "Sharing", "÷", ("2, 5 and 10", "3 and 4", "6, 7, 8 and 9", "All to 12", "Bigger")),
)
TABLES = {0: (2, 5, 10), 1: (3, 4), 2: (6, 7, 8, 9), 3: tuple(range(2, 13))}
LIMITS = (10, 20, 50, 100, 1000)
PRAISE = ("Well done!", "Brilliant!", "Great!", "Yes!", "Super!", "Spot on!")


def question(operation, level, rng, table=None):
    """(text, answer) for one question."""
    if operation == "add":
        top = LIMITS[level]
        low = 0 if level < 2 else top // 10
        a = rng.randint(low, top - low)
        b = rng.randint(low if top - a >= low else 0, top - a)
        return f"{a} + {b}", a + b
    if operation == "subtract":
        top = LIMITS[level]
        a = rng.randint(top // 4 if level else 1, top)
        b = rng.randint(0, a)
        return f"{a} − {b}", a - b
    if table is not None:
        tables, upper = (table,), 12
    elif level == 4:
        tables, upper = tuple(range(3, 13)), 25
    else:
        tables, upper = TABLES[level], 12
    t = rng.choice(tables)
    n = rng.randint(1 if level < 4 else 11, upper)
    if operation == "multiply":
        a, b = (t, n) if rng.random() < 0.5 else (n, t)
        return f"{a} × {b}", a * b
    return f"{t * n} ÷ {t}", n


def make_round(operation, level, rng, table=None):
    """Ten different questions where possible."""
    seen, questions = set(), []
    for _attempt in range(200):
        text, answer = question(operation, level, rng, table)
        if text not in seen:
            seen.add(text)
            questions.append((text, answer))
        if len(questions) == ROUND:
            break
    while len(questions) < ROUND:
        questions.append(question(operation, level, rng, table))
    return questions


def stars_for(first_try):
    if first_try >= 9:
        return 3
    if first_try >= 7:
        return 2
    if first_try >= 5:
        return 1
    return 0


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


CSS = b"""
.sums-card { background-color: @theme_base_color; border-radius: 14px; padding: 14px 16px;
             box-shadow: 0 1px 3px alpha(black, 0.16); }
.sums-sign { font-size: 34px; font-weight: 700; color: @theme_selected_bg_color; }
.sums-op { font-size: 18px; font-weight: 700; }
.sums-level { padding: 6px 4px; min-width: 96px; }
.sums-stars { color: #f2b01e; font-size: 13px; }
.sums-question { font-size: 64px; font-weight: 700; }
.sums-answer { font-size: 44px; font-weight: 700; min-width: 180px; }
.sums-feedback { font-size: 20px; font-weight: 600; }
.sums-right { color: #1f9d4b; }
.sums-wrong { color: #d9432f; }
.sums-key { font-size: 22px; font-weight: 600; min-width: 64px; min-height: 52px; }
.sums-dot { font-size: 18px; }
.sums-result { font-size: 30px; font-weight: 700; }
.sums-big-stars { font-size: 56px; color: #f2b01e; }
.sums-chart-cell { min-width: 44px; min-height: 34px; font-size: 14px; }
.sums-chart-head { font-weight: 700; }
.sums-chart-lit { background-color: alpha(@theme_selected_bg_color, 0.18); border-radius: 4px; }
.sums-chart-hit { background-color: @theme_selected_bg_color; color: @theme_selected_fg_color; border-radius: 4px; }
"""


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Sums")
        self.set_default_size(820, 640)
        self.store = load_store()
        self.rng = random.Random()
        self.round = None

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        self.pages = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.switcher = Gtk.StackSwitcher(stack=self.pages)
        self.round_title = Gtk.Label()
        self.round_title.get_style_context().add_class("title")
        self.titles = Gtk.Stack()
        self.titles.add_named(self.switcher, "pages")
        self.titles.add_named(self.round_title, "round")
        header.set_custom_title(self.titles)
        self.back = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        self.back.set_tooltip_text("Stop this round")
        self.back.connect("clicked", lambda _b: self.go_home())
        header.pack_start(self.back)
        self.add(self.pages)

        self.pages.add_titled(self.build_home(), "home", "Practise")
        self.pages.add_titled(self.build_chart(), "chart", "Times Tables")
        self.pages.add_named(self.build_play(), "play")
        self.pages.add_named(self.build_result(), "result")

        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self.connect("key-press-event", self._key)
        menus.add_actions(self, {"close": self.close, "home": self.go_home,
                                 "chart": lambda: self.pages.set_visible_child_name("chart")})
        self.show_all()
        self.back.hide()

    # Pages --------------------------------------------------------------------

    def build_home(self):
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24)
        title = Gtk.Label(label="What would you like to practise?", xalign=0)
        title.get_style_context().add_class("sums-op")
        box.pack_start(title, False, False, 0)
        self.star_labels = {}
        for key, name, sign, levels in OPERATIONS:
            card = Gtk.Box(spacing=16)
            card.get_style_context().add_class("sums-card")
            symbol = Gtk.Label(label=sign, width_chars=2)
            symbol.get_style_context().add_class("sums-sign")
            card.pack_start(symbol, False, False, 0)
            column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            label = Gtk.Label(label=name, xalign=0)
            label.get_style_context().add_class("sums-op")
            column.pack_start(label, False, False, 0)
            row = Gtk.Box(spacing=8)
            for level, words in enumerate(levels):
                button = Gtk.Button()
                button.get_style_context().add_class("sums-level")
                inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                inner.pack_start(Gtk.Label(label=words), False, False, 0)
                stars = Gtk.Label()
                stars.get_style_context().add_class("sums-stars")
                inner.pack_start(stars, False, False, 0)
                button.add(inner)
                button.connect("clicked", lambda _b, k=key, n=level: self.start(k, n))
                self.star_labels[(key, level)] = stars
                row.pack_start(button, False, False, 0)
            column.pack_start(row, False, False, 0)
            card.pack_start(column, True, True, 0)
            box.pack_start(card, False, False, 0)
        scroller.add(box)
        self.update_stars()
        return scroller

    def build_chart(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
        tip = Gtk.Label(label="Point at a square to see its sum. Click a number along the top to practise "
                              "that table.", xalign=0)
        tip.get_style_context().add_class("dim-label")
        outer.pack_start(tip, False, False, 0)
        self.chart_sum = Gtk.Label(xalign=0)
        self.chart_sum.get_style_context().add_class("sums-op")
        outer.pack_start(self.chart_sum, False, False, 0)
        grid = Gtk.Grid(column_spacing=2, row_spacing=2, halign=Gtk.Align.CENTER)
        self.chart_cells = {}
        corner = Gtk.Label(label="×")
        corner.get_style_context().add_class("sums-chart-head")
        grid.attach(corner, 0, 0, 1, 1)
        for n in range(1, 13):
            head = Gtk.Button(label=str(n), relief=Gtk.ReliefStyle.NONE)
            head.get_style_context().add_class("sums-chart-head")
            head.set_tooltip_text(f"Practise the {n} times table")
            head.connect("clicked", lambda _b, t=n: self.start("multiply", 3, table=t))
            grid.attach(head, n, 0, 1, 1)
            side = Gtk.Label(label=str(n))
            side.get_style_context().add_class("sums-chart-head")
            grid.attach(side, 0, n, 1, 1)
        for row in range(1, 13):
            for col in range(1, 13):
                cell = Gtk.EventBox()
                label = Gtk.Label(label=str(row * col))
                label.get_style_context().add_class("sums-chart-cell")
                cell.add(label)
                cell.connect("enter-notify-event", lambda _w, _e, r=row, c=col: self.light(r, c))
                grid.attach(cell, col, row, 1, 1)
                self.chart_cells[(row, col)] = label
        grid.connect("leave-notify-event", lambda *_a: self.light(None, None))
        outer.pack_start(grid, False, False, 0)
        return outer

    def light(self, row, col):
        for (r, c), label in self.chart_cells.items():
            context = label.get_style_context()
            context.remove_class("sums-chart-lit")
            context.remove_class("sums-chart-hit")
            if row is not None and (r, c) == (row, col):
                context.add_class("sums-chart-hit")
            elif row is not None and ((r == row and c <= col) or (c == col and r <= row)):
                context.add_class("sums-chart-lit")
        self.chart_sum.set_text(f"{row} × {col} = {row * col}" if row else "")
        return False

    def build_play(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24, valign=Gtk.Align.CENTER)
        self.dots = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        self.dot_labels = []
        for _n in range(ROUND):
            dot = Gtk.Label(label="○")
            dot.get_style_context().add_class("sums-dot")
            self.dot_labels.append(dot)
            self.dots.pack_start(dot, False, False, 0)
        box.pack_start(self.dots, False, False, 0)
        line = Gtk.Box(spacing=18, halign=Gtk.Align.CENTER)
        self.question_label = Gtk.Label()
        self.question_label.get_style_context().add_class("sums-question")
        equals = Gtk.Label(label="=")
        equals.get_style_context().add_class("sums-question")
        self.answer = Gtk.Entry(xalign=0.5, width_chars=5, max_length=6)
        self.answer.get_style_context().add_class("sums-answer")
        self.answer.set_input_purpose(Gtk.InputPurpose.NUMBER)
        self.answer.connect("activate", lambda _e: self.check())
        self.answer.connect("changed", self._only_digits)
        line.pack_start(self.question_label, False, False, 0)
        line.pack_start(equals, False, False, 0)
        line.pack_start(self.answer, False, False, 0)
        box.pack_start(line, False, False, 0)
        self.feedback = Gtk.Label()
        self.feedback.get_style_context().add_class("sums-feedback")
        box.pack_start(self.feedback, False, False, 0)
        keypad = Gtk.Grid(column_spacing=8, row_spacing=8, halign=Gtk.Align.CENTER)
        keys = ("7", "8", "9", "4", "5", "6", "1", "2", "3", "⌫", "0", "OK")
        for n, key in enumerate(keys):
            button = Gtk.Button(label=key)
            button.get_style_context().add_class("sums-key")
            if key == "OK":
                button.get_style_context().add_class("suggested-action")
            button.set_can_focus(False)
            button.connect("clicked", lambda _b, k=key: self.press(k))
            keypad.attach(button, n % 3, n // 3, 1, 1)
        box.pack_start(keypad, False, False, 6)
        return box

    def build_result(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24, valign=Gtk.Align.CENTER)
        self.result_stars = Gtk.Label()
        self.result_stars.get_style_context().add_class("sums-big-stars")
        self.result_title = Gtk.Label()
        self.result_title.get_style_context().add_class("sums-result")
        self.result_text = Gtk.Label(justify=Gtk.Justification.CENTER)
        self.result_text.set_line_wrap(True)
        self.result_list = Gtk.Label(justify=Gtk.Justification.CENTER)
        self.result_list.get_style_context().add_class("dim-label")
        buttons = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER)
        again = Gtk.Button(label="Play Again")
        again.connect("clicked", lambda _b: self.start(*self.round["what"], table=self.round["table"]))
        self.next_button = Gtk.Button(label="Next Level")
        self.next_button.get_style_context().add_class("suggested-action")
        self.next_button.connect("clicked", lambda _b: self.start(self.round["what"][0], self.round["what"][1] + 1))
        done = Gtk.Button(label="Choose Something Else")
        done.connect("clicked", lambda _b: self.go_home())
        for button in (done, again, self.next_button):
            buttons.pack_start(button, False, False, 0)
        for widget in (self.result_stars, self.result_title, self.result_text, self.result_list):
            box.pack_start(widget, False, False, 0)
        box.pack_start(buttons, False, False, 10)
        return box

    # Rounds -------------------------------------------------------------------

    def update_stars(self):
        best = self.store.get("best") if isinstance(self.store.get("best"), dict) else {}
        for (key, level), label in self.star_labels.items():
            stars = best.get(f"{key}:{level}")
            stars = stars if isinstance(stars, int) and 0 <= stars <= 3 else None
            label.set_text("☆☆☆" if stars is None else "★" * stars + "☆" * (3 - stars))

    def start(self, operation, level, table=None):
        self.round = {"what": (operation, level), "table": table,
                      "questions": make_round(operation, level, self.rng, table),
                      "index": 0, "tries": 0, "first": 0, "missed": []}
        for dot in self.dot_labels:
            dot.set_text("○")
            dot.get_style_context().remove_class("sums-right")
            dot.get_style_context().remove_class("sums-wrong")
        self.show_question()
        self.pages.set_visible_child_name("play")
        name, words = self.describe(operation, level, table)
        self.round_title.set_text(f"{name}: {words}")
        self.titles.set_visible_child_name("round")
        self.back.show()
        self.answer.grab_focus()

    @staticmethod
    def describe(operation, level, table):
        for key, name, _sign, levels in OPERATIONS:
            if key == operation:
                return name, (f"the {table} times table" if table else levels[level])
        return "", ""

    def show_question(self):
        text, _answer = self.round["questions"][self.round["index"]]
        self.question_label.set_text(text)
        self.answer.set_text("")
        self.answer.set_sensitive(True)
        self.feedback.set_text("")
        dot = self.dot_labels[self.round["index"]]
        dot.set_text("●")
        self.answer.grab_focus()

    def _only_digits(self, entry):
        text = entry.get_text()
        digits = "".join(ch for ch in text if ch.isdigit())
        if digits != text:
            GLib.idle_add(entry.set_text, digits)

    def press(self, key):
        if self.pages.get_visible_child_name() != "play" or not self.answer.get_sensitive():
            return
        if key == "OK":
            self.check()
        elif key == "⌫":
            self.answer.set_text(self.answer.get_text()[:-1])
        elif len(self.answer.get_text()) < 6:
            self.answer.set_text(self.answer.get_text() + key)
        self.answer.grab_focus()
        self.answer.set_position(-1)

    def _feedback(self, text, good):
        context = self.feedback.get_style_context()
        context.remove_class("sums-right")
        context.remove_class("sums-wrong")
        context.add_class("sums-right" if good else "sums-wrong")
        self.feedback.set_text(text)

    def check(self):
        round_ = self.round
        if not round_ or not self.answer.get_sensitive():
            return
        typed = self.answer.get_text().strip()
        if not typed:
            return
        text, answer = round_["questions"][round_["index"]]
        dot = self.dot_labels[round_["index"]]
        if int(typed) == answer:
            if round_["tries"] == 0:
                round_["first"] += 1
            dot.set_text("●")
            dot.get_style_context().add_class("sums-right")
            self._feedback(self.rng.choice(PRAISE), True)
            self.answer.set_sensitive(False)
            GLib.timeout_add(700, self.next_question)
        elif round_["tries"] == 0:
            round_["tries"] = 1
            self._feedback("Not quite. Have another go.", False)
            self.answer.set_text("")
            self.answer.grab_focus()
        else:
            dot.set_text("●")
            dot.get_style_context().add_class("sums-wrong")
            round_["missed"].append(f"{text} = {answer}")
            self._feedback(f"It's {answer}.", False)
            self.answer.set_text(str(answer))
            self.answer.set_sensitive(False)
            GLib.timeout_add(1800, self.next_question)

    def next_question(self):
        round_ = self.round
        if not round_ or self.pages.get_visible_child_name() != "play":
            return False
        round_["index"] += 1
        round_["tries"] = 0
        if round_["index"] >= ROUND:
            self.finish()
        else:
            self.show_question()
        return False

    def finish(self):
        round_ = self.round
        first = round_["first"]
        stars = stars_for(first)
        operation, level = round_["what"]
        if round_["table"] is None:
            best = self.store.setdefault("best", {})
            if not isinstance(best, dict):
                best = self.store["best"] = {}
            key = f"{operation}:{level}"
            if not isinstance(best.get(key), int) or stars > best[key]:
                best[key] = stars
            save_store(self.store)
            self.update_stars()
        self.result_stars.set_text("★" * stars + "☆" * (3 - stars))
        self.result_title.set_text(("Fantastic!", "Good work!", "Well done!", "Keep practising!")[3 - stars]
                                   if stars else "Keep practising!")
        self.result_text.set_text(f"You got {first} of {ROUND} right first time.")
        missed = round_["missed"]
        self.result_list.set_text(("Ones to look at again:\n" + "\n".join(missed)) if missed else "")
        self.next_button.set_visible(round_["table"] is None and level < 4 and stars >= 2)
        self.pages.set_visible_child_name("result")
        self.back.hide()

    def go_home(self):
        self.round = None
        self.pages.set_visible_child_name("home")
        self.titles.set_visible_child_name("pages")
        self.back.hide()

    def _key(self, _w, event):
        if self.pages.get_visible_child_name() == "play" and event.keyval == Gdk.KEY_Escape:
            self.go_home()
            return True
        return False

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Sums")
        dialog.format_secondary_text("Sums is maths practice for children, part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_Practice", [[("Choose a Round", "win.home", "<Ctrl>1"), ("Times Tables", "win.chart", "<Ctrl>2")],
                       [("Close", "win.close", "<Ctrl>w")]]),
    ])


class Sums(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close(),
                                 "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_accels_for_action("win.home", ["<Control>1"])
        self.set_accels_for_action("win.chart", ["<Control>2"])
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-sums")
    return Sums().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
