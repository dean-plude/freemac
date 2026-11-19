# SPDX-License-Identifier: GPL-3.0-or-later
"""Tally: freemac's calculator.

A keypad calculator with a running tape. Type with the keyboard or click
the keys; Enter or = works out the line, Escape clears it, Backspace deletes
a character, Ctrl+C copies the answer. The Scientific switch adds powers,
roots, trigonometry and logarithms.

Expressions are worked out by a small parser of our own (never Python's
eval), with exact decimal arithmetic for + - x / so 0.1 + 0.2 gives 0.3.
"""
import decimal
import math
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Tally"
D = decimal.Decimal
CTX = decimal.Context(prec=34)


class CalcError(Exception):
    """Something the user typed can't be worked out; the message says what."""


FUNCTIONS = {
    "sqrt": lambda x, deg: _real(math.sqrt, x),
    "sin": lambda x, deg: math.sin(math.radians(x) if deg else x),
    "cos": lambda x, deg: math.cos(math.radians(x) if deg else x),
    "tan": lambda x, deg: _tan(x, deg),
    "asin": lambda x, deg: _angle(math.asin, x, deg),
    "acos": lambda x, deg: _angle(math.acos, x, deg),
    "atan": lambda x, deg: _angle(math.atan, x, deg),
    "ln": lambda x, deg: _real(math.log, x),
    "log": lambda x, deg: _real(math.log10, x),
    "abs": lambda x, deg: abs(x),
}
CONSTANTS = {"pi": math.pi, "π": math.pi, "e": math.e}


def _real(fn, x):
    try:
        return fn(x)
    except ValueError:
        raise CalcError("Not a real number") from None


def _angle(fn, x, deg):
    value = _real(fn, x)
    return math.degrees(value) if deg else value


def _tan(x, deg):
    if deg and float(x) % 180 == 90:
        raise CalcError("Can't divide by zero")
    return math.tan(math.radians(x) if deg else x)


def tokenize(text):
    """Split an expression into numbers, names and operators."""
    text = (text.replace("×", "*").replace("÷", "/").replace("−", "-")
            .replace("^", "**").replace("√", "sqrt").replace(",", ""))
    tokens, i = [], 0
    while i < len(text):
        c = text[i]
        if c.isspace():
            i += 1
        elif c.isdigit() or c == ".":
            j = i
            while j < len(text) and (text[j].isdigit() or text[j] == "."):
                j += 1
            if j < len(text) and text[j] in "eE" and j + 1 < len(text) and (
                    text[j + 1].isdigit() or (text[j + 1] in "+-" and j + 2 < len(text) and text[j + 2].isdigit())):
                j += 2
                while j < len(text) and text[j].isdigit():
                    j += 1
            number = text[i:j]
            if number.count(".") > 1 or number == ".":
                raise CalcError("That number has too many points")
            tokens.append(("num", D(number)))
            i = j
        elif c.isalpha() or c == "π":
            j = i + 1
            while j < len(text) and text[j].isalpha():
                j += 1
            tokens.append(("name", text[i:j].lower()))
            i = j
        elif text.startswith("**", i):
            tokens.append(("op", "**"))
            i += 2
        elif c in "+-*/%()!":
            tokens.append(("op", c))
            i += 1
        else:
            raise CalcError(f"Tally doesn't know “{c}”")
    return tokens


class Parser:
    """Recursive descent over:  sum := product (('+'|'-') product)*
    product := unary (('*'|'/') unary | implicit)*,  unary := '-' unary | power,
    power := postfix ('**' unary)?,  postfix := atom ('!' | '%')*."""

    def __init__(self, tokens, degrees=True, answer=None):
        self.tokens, self.pos, self.degrees, self.answer = tokens, 0, degrees, answer

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else (None, None)

    def take(self, kind=None, value=None):
        tok = self.peek()
        if tok[0] is None or (kind and tok[0] != kind) or (value and tok[1] != value):
            return None
        self.pos += 1
        return tok

    def parse(self):
        if not self.tokens:
            raise CalcError("Nothing to work out")
        value = self.sum()
        if self.pos != len(self.tokens):
            raise CalcError("That doesn't look finished")
        return value

    def sum(self):
        value = self.product()
        while True:
            if self.take("op", "+"):
                value = add(value, self.product())
            elif self.take("op", "-"):
                value = add(value, neg(self.product()))
            else:
                return value

    def product(self):
        value = self.unary()
        while True:
            if self.take("op", "*"):
                value = mul(value, self.unary())
            elif self.take("op", "/"):
                value = div(value, self.unary())
            elif self.peek()[0] in ("num", "name") or self.peek() == ("op", "("):
                value = mul(value, self.power())  # 2pi, 3(4+1), 2sqrt9
            else:
                return value

    def unary(self):
        if self.take("op", "-"):
            return neg(self.unary())
        if self.take("op", "+"):
            return self.unary()
        return self.power()

    def power(self):
        base = self.postfix()
        if self.take("op", "**"):
            return pow_(base, self.unary())
        return base

    def postfix(self):
        value = self.atom()
        while True:
            if self.take("op", "!"):
                value = factorial(value)
            elif self.take("op", "%"):
                value = div(value, D(100))
            else:
                return value

    def atom(self):
        tok = self.peek()
        if self.take("num"):
            return tok[1]
        if self.take("op", "("):
            value = self.sum()
            self.take("op", ")")  # a missing closing bracket is forgiven
            return value
        if self.take("name"):
            name = tok[1]
            if name == "ans":
                if self.answer is None:
                    raise CalcError("There's no answer yet")
                return self.answer
            if name in CONSTANTS:
                return CONSTANTS[name]
            if name in FUNCTIONS:
                arg = self.power() if self.peek() != ("op", "(") else self.atom()
                return FUNCTIONS[name](float(arg), self.degrees)
            raise CalcError(f"Tally doesn't know “{name}”")
        raise CalcError("That doesn't look finished")


def _float(v):
    return float(v) if isinstance(v, D) else v


def add(a, b):
    if isinstance(a, D) and isinstance(b, D):
        return CTX.add(a, b)
    return _float(a) + _float(b)


def neg(a):
    return -a


def mul(a, b):
    if isinstance(a, D) and isinstance(b, D):
        return CTX.multiply(a, b)
    return _float(a) * _float(b)


def div(a, b):
    if b == 0:
        raise CalcError("Can't divide by zero")
    if isinstance(a, D) and isinstance(b, D):
        return CTX.divide(a, b)
    return _float(a) / _float(b)


def pow_(a, b):
    if isinstance(a, D) and isinstance(b, D) and b == b.to_integral_value() and abs(b) <= 1000:
        if a == 0 and b < 0:
            raise CalcError("Can't divide by zero")
        return CTX.power(a, int(b))
    try:
        result = math.pow(_float(a), _float(b))
    except (ValueError, OverflowError):
        raise CalcError("Too big, or not a real number") from None
    return result


def factorial(a):
    f = _float(a)
    if f < 0 or f != int(f):
        raise CalcError("Factorial needs a whole number")
    if f > 1000:
        raise CalcError("Too big")
    return D(math.factorial(int(f)))


def evaluate(text, degrees=True, answer=None):
    value = Parser(tokenize(text), degrees, answer).parse()
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            raise CalcError("Too big, or not a real number")
        value = D(repr(value))
    return value


def show(value):
    """A number as people write it: no trailing zeros, grouped thousands,
    scientific notation only for very large or very small values."""
    if value == 0:
        return "0"
    rounded = value.quantize(D("1e-12"), context=CTX) if abs(value) < D("1e21") else value
    if abs(value) >= D("1e15") or abs(rounded) < D("1e-9"):
        mantissa, exponent = f"{value:.10E}".split("E")
        mantissa = mantissa.rstrip("0").rstrip(".")
        return f"{mantissa}×10^{int(exponent)}"
    text = format(rounded.normalize(), "f")
    whole, _, frac = text.partition(".")
    sign = "−" if whole.startswith("-") else ""
    whole = f"{int(whole.lstrip('-')):,}"
    return sign + whole + ("." + frac if frac else "")


BASIC_KEYS = [
    [("C", "clear"), ("( )", "paren"), ("%", "%"), ("÷", "÷")],
    [("7", "7"), ("8", "8"), ("9", "9"), ("×", "×")],
    [("4", "4"), ("5", "5"), ("6", "6"), ("−", "−")],
    [("1", "1"), ("2", "2"), ("3", "3"), ("+", "+")],
    [("±", "negate"), ("0", "0"), (".", "."), ("=", "equals")],
]
SCIENCE_KEYS = [
    [("sin", "sin("), ("cos", "cos("), ("tan", "tan("), ("π", "π")],
    [("ln", "ln("), ("log", "log("), ("√", "√("), ("e", "e")],
    [("x²", "^2"), ("xʸ", "^"), ("n!", "!"), ("Ans", "Ans")],
]


class Calculator(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Tally")
        self.set_default_size(340, 520)
        self.answer = None
        self.just_answered = False

        header = Gtk.HeaderBar(show_close_button=True, title="Tally")
        self.set_titlebar(header)
        self.science = Gtk.ToggleButton(label="Scientific")
        self.science.set_tooltip_text("Show powers, roots, trigonometry and logarithms")
        self.science.connect("toggled", self.on_science)
        header.pack_start(self.science)
        self.angle = Gtk.Button(label="Degrees")
        self.angle.set_tooltip_text("Switch between degrees and radians")
        self.angle.connect("clicked", self.on_angle)
        self.degrees = True
        header.pack_end(self.angle)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=12)
        self.add(box)

        self.tape = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.tape.get_style_context().add_class("tally-tape")
        self.tape.connect("row-activated", self.on_tape_row)
        self.tape.set_activate_on_single_click(True)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        scroller.set_min_content_height(64)
        scroller.add(self.tape)
        self.tape_scroller = scroller
        box.pack_start(scroller, True, True, 0)

        self.entry = Gtk.Entry(xalign=1)
        self.entry.get_style_context().add_class("tally-entry")
        self.entry.set_placeholder_text("0")
        self.entry.connect("activate", lambda _e: self.equals())
        self.entry.connect("changed", self.on_changed)
        box.pack_start(self.entry, False, False, 0)
        self.preview = Gtk.Label(xalign=1)
        self.preview.get_style_context().add_class("dim-label")
        box.pack_start(self.preview, False, False, 0)

        self.science_grid = self.keypad(SCIENCE_KEYS)
        self.science_grid.set_no_show_all(True)
        box.pack_start(self.science_grid, False, False, 0)
        box.pack_start(self.keypad(BASIC_KEYS), False, False, 0)

        self.connect("key-press-event", self.on_key)
        self._add_actions()
        css = Gtk.CssProvider()
        css.load_from_data(b"""
            .tally-entry { font-size: 26px; padding: 6px 8px; }
            .tally-tape row { padding: 2px 6px; }
            .tally-key { min-height: 36px; font-size: 15px; }
            .tally-op { font-weight: bold; }
        """)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.show_all()
        self.entry.grab_focus()

    def _add_actions(self):
        menus.add_actions(self, {
            "close": self.close,
            "copy-answer": self.copy_answer,
            "paste": lambda: self.entry.paste_clipboard(),
            "clear": self.clear,
            "clear-tape": self.clear_tape,
        })
        self.science_action = menus.add_toggle(self, "scientific", False, self.science.set_active)
        self.radians_action = menus.add_toggle(self, "radians", False,
                                               lambda on: on == self.degrees and self.on_angle(self.angle))

    def copy_answer(self):
        if self.answer is not None:
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(show(self.answer).replace(",", ""), -1)

    def clear_tape(self):
        for row in self.tape.get_children():
            self.tape.remove(row)

    def keypad(self, rows):
        grid = Gtk.Grid(row_spacing=6, column_spacing=6, column_homogeneous=True, row_homogeneous=True)
        for r, row in enumerate(rows):
            for c, (label, action) in enumerate(row):
                button = Gtk.Button(label=label, can_focus=False)
                ctx = button.get_style_context()
                ctx.add_class("tally-key")
                if action in ("÷", "×", "−", "+"):
                    ctx.add_class("tally-op")
                if action == "equals":
                    ctx.add_class("suggested-action")
                button.connect("clicked", lambda _b, a=action: self.press(a))
                grid.attach(button, c, r, 1, 1)
                button.show()
        # Only the keys: the scientific grid itself stays hidden until asked for.
        return grid

    # -- typing --------------------------------------------------------------
    def insert(self, text):
        if self.just_answered:
            # After an answer, an operator continues from it; a digit starts afresh.
            if text[:1] in "+−×÷^!%":
                self.entry.set_text("Ans")
            else:
                self.entry.set_text("")
            self.just_answered = False
            self.entry.set_position(-1)
        pos = self.entry.get_position()
        self.entry.insert_text(text, pos)
        self.entry.set_position(pos + len(text))
        self.entry.grab_focus_without_selecting()

    def press(self, action):
        if action == "clear":
            self.clear()
        elif action == "equals":
            self.equals()
        elif action == "negate":
            text = self.entry.get_text() or "0"
            self.entry.set_text(text[1:] if text.startswith("−") else "−(" + text + ")" if any(
                op in text for op in "+−×÷") else "−" + text)
            self.just_answered = False
        elif action == "paren":
            text = self.entry.get_text()
            opened = text.count("(") - text.count(")")
            self.insert(")" if opened > 0 and text and text[-1] not in "(+−×÷^" else "(")
        else:
            self.insert(action)

    def clear(self):
        if not self.entry.get_text():
            self.clear_tape()
        self.entry.set_text("")
        self.just_answered = False

    def on_changed(self, entry):
        text = entry.get_text().strip()
        if not text or self.just_answered:
            self.preview.set_text("")
            return
        try:
            self.preview.set_text("= " + show(evaluate(text, self.degrees, self.answer)))
        except (CalcError, decimal.DecimalException, ValueError, OverflowError):
            self.preview.set_text("")

    def equals(self):
        text = self.entry.get_text().strip()
        if not text:
            return
        try:
            value = evaluate(text, self.degrees, self.answer)
        except CalcError as err:
            self.preview.set_text(str(err))
            return
        except (decimal.DecimalException, ValueError, OverflowError):
            self.preview.set_text("Too big, or not a real number")
            return
        self.answer = value
        self.add_tape(text, show(value))
        self.entry.set_text(show(value).replace(",", "").replace("×10^", "e"))
        self.entry.set_position(-1)
        self.preview.set_text("")
        self.just_answered = True

    def add_tape(self, expression, result):
        row = Gtk.ListBoxRow()
        row.result = result
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        top = Gtk.Label(label=expression, xalign=1)
        top.get_style_context().add_class("dim-label")
        bottom = Gtk.Label(label="= " + result, xalign=1, selectable=False)
        box.pack_start(top, False, False, 0)
        box.pack_start(bottom, False, False, 0)
        row.add(box)
        row.set_tooltip_text("Click to use this answer")
        self.tape.add(row)
        row.show_all()
        adj = self.tape_scroller.get_vadjustment()
        adj.set_value(adj.get_upper())

    def on_tape_row(self, _box, row):
        self.insert(row.result.replace(",", "").replace("×10^", "e"))

    def on_key(self, _w, event):
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        key = Gdk.keyval_name(event.keyval)
        if key == "Escape":
            self.clear()
            return True
        if ctrl and key in ("c", "C") and not self.entry.get_selection_bounds():
            self.copy_answer()
            return True
        if ctrl and key in ("w", "W"):
            self.close()
            return True
        if ctrl and key in ("n", "N"):
            self.get_application().activate_action("new-window", None)
            return True
        if key == "equal" and not ctrl:
            self.equals()
            return True
        if not ctrl and self.just_answered and event.string and event.string in "0123456789.(":
            self.insert(event.string)
            return True
        if not ctrl and self.just_answered and event.string and event.string in "+-*/^!%":
            self.insert({"-": "−", "*": "×", "/": "÷"}.get(event.string, event.string))
            return True
        if not ctrl and event.string and event.string in "*/-" and not self.just_answered:
            self.insert({"-": "−", "*": "×", "/": "÷"}[event.string])
            return True
        return False

    def on_science(self, button):
        self.science_grid.set_visible(button.get_active())
        self.angle.set_visible(True)
        if self.science_action.get_state().get_boolean() != button.get_active():
            self.science_action.set_state(GLib.Variant("b", button.get_active()))

    def on_angle(self, button):
        self.degrees = not self.degrees
        button.set_label("Degrees" if self.degrees else "Radians")
        self.radians_action.set_state(GLib.Variant("b", not self.degrees))
        self.on_changed(self.entry)


def menubar():
    return menus.menubar([
        ("_File", [[("New Window", "app.new-window", "<Ctrl>n")], [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [
            [("Copy Answer", "win.copy-answer", "<Ctrl>c"), ("Paste", "win.paste", "<Ctrl>v")],
            [("Clear", "win.clear", "Escape"), ("Clear Tape", "win.clear-tape", None)],
        ]),
        ("_View", [[("Scientific", "win.scientific", None), ("Radians", "win.radians", None)]]),
    ])


class Tally(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        self.set_accels_for_action("app.quit", ["<Control>q"])
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: self.quit())
        self.add_action(quit_action)
        menus.add_actions(self, {"new-window": lambda: Calculator(self).present()})
        self.set_menubar(menubar())

    def do_activate(self):
        window = self.get_active_window() or Calculator(self)
        window.present()


def main():
    Tally().run(sys.argv)


if __name__ == "__main__":
    main()
