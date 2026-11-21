# SPDX-License-Identifier: GPL-3.0-or-later
"""Plot: a graphing calculator.

Type equations such as  y = x^2 - 3,  sin(2x)  or  a·cos(x)  and see them
drawn in colour. Drag the graph to move it, scroll or pinch to zoom, and
point at a curve to read its value there. An equation that uses the letter a
gets a slider for a, to watch the curve change.

Original freemac code: equations are read by its own small parser (numbers,
x, a, + - * / ^, brackets, implicit multiplication as in 2x, and the usual
functions), never by Python's eval. Equations are kept in
~/.local/share/freemac/plot.json.
"""
import json
import math
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Plot"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "plot.json")
COLOURS = ((0.04, 0.49, 1.0), (1.0, 0.27, 0.23), (0.2, 0.78, 0.35), (0.69, 0.32, 0.87),
           (1.0, 0.58, 0.0), (0.0, 0.7, 0.75), (0.95, 0.2, 0.6), (0.55, 0.45, 0.3))
EXAMPLES = ("y = x^2 - 2", "y = sin(x)")

FUNCTIONS = {
    "sin": math.sin, "cos": math.cos, "tan": math.tan, "asin": math.asin, "acos": math.acos,
    "atan": math.atan, "sinh": math.sinh, "cosh": math.cosh, "tanh": math.tanh,
    "sqrt": math.sqrt, "abs": abs, "ln": math.log, "log": math.log10, "exp": math.exp,
    "floor": math.floor, "ceil": math.ceil, "round": round, "sign": lambda v: (v > 0) - (v < 0),
}
CONSTANTS = {"pi": math.pi, "π": math.pi, "e": math.e, "tau": math.tau}


class ParseError(ValueError):
    pass


def tokens(text):
    text = (text.replace("×", "*").replace("·", "*").replace("÷", "/").replace("−", "-")
            .replace("²", "^2").replace("³", "^3").replace("√", "sqrt"))
    out, i = [], 0
    while i < len(text):
        ch = text[i]
        if ch.isspace():
            i += 1
        elif ch.isdigit() or (ch == "." and i + 1 < len(text) and text[i + 1].isdigit()):
            j = i
            while j < len(text) and (text[j].isdigit() or text[j] == "."):
                j += 1
            if j < len(text) and text[j] in "eE" and j + 1 < len(text) and (
                    text[j + 1].isdigit() or (text[j + 1] in "+-" and j + 2 < len(text) and text[j + 2].isdigit())):
                j += 2
                while j < len(text) and text[j].isdigit():
                    j += 1
            try:
                out.append(("num", float(text[i:j])))
            except ValueError:
                raise ParseError(text[i:j]) from None
            i = j
        elif ch.isalpha() or ch == "π":
            j = i
            while j < len(text) and (text[j].isalpha() or text[j] == "π"):
                j += 1
            word = text[i:j].lower()
            # Split runs such as "ax" or "xsin" into names we know.
            while word:
                for name in sorted(list(FUNCTIONS) + list(CONSTANTS) + ["x", "a"], key=len, reverse=True):
                    if word.startswith(name):
                        out.append(("name", name))
                        word = word[len(name):]
                        break
                else:
                    raise ParseError(word)
            i = j
        elif ch in "+-*/^(),|":
            out.append(("op", ch))
            i += 1
        else:
            raise ParseError(ch)
    return out


class Parser:
    """expr := term (('+'|'-') term)* ; term := unary (('*'|'/'|implicit) unary)* ;
    unary := '-' unary | power ; power := atom ('^' unary)?"""

    def __init__(self, text):
        self.toks = tokens(text)
        self.i = 0
        self.uses_a = False

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self):
        tok = self.peek()
        self.i += 1
        return tok

    def parse(self):
        if not self.toks:
            raise ParseError("empty")
        node = self.expr()
        if self.i != len(self.toks):
            raise ParseError(str(self.peek()[1]))
        return node

    def expr(self):
        node = self.term()
        while self.peek() in (("op", "+"), ("op", "-")):
            op = self.take()[1]
            right = self.term()
            node = (lambda l, r: lambda x, a: l(x, a) + r(x, a))(node, right) if op == "+" else \
                (lambda l, r: lambda x, a: l(x, a) - r(x, a))(node, right)
        return node

    def starts_atom(self):
        kind, value = self.peek()
        return kind in ("num", "name") or (kind == "op" and value in "(|")

    def term(self):
        node = self.unary()
        while True:
            tok = self.peek()
            if tok in (("op", "*"), ("op", "/")):
                self.take()
                right = self.unary()
                node = (lambda l, r: lambda x, a: l(x, a) * r(x, a))(node, right) if tok[1] == "*" else \
                    (lambda l, r: lambda x, a: l(x, a) / r(x, a))(node, right)
            elif self.starts_atom() and not (tok == ("op", "|") and self.in_bars):
                right = self.unary()
                node = (lambda l, r: lambda x, a: l(x, a) * r(x, a))(node, right)
            else:
                return node

    in_bars = False

    def unary(self):
        if self.peek() == ("op", "-"):
            self.take()
            inner = self.unary()
            return lambda x, a: -inner(x, a)
        if self.peek() == ("op", "+"):
            self.take()
            return self.unary()
        return self.power()

    def power(self):
        base = self.atom()
        if self.peek() == ("op", "^"):
            self.take()
            exponent = self.unary()
            return lambda x, a: base(x, a) ** exponent(x, a)
        return base

    def atom(self):
        kind, value = self.take()
        if kind == "num":
            return lambda x, a, v=value: v
        if kind == "name":
            if value == "x":
                return lambda x, a: x
            if value == "a":
                self.uses_a = True
                return lambda x, a: a
            if value in CONSTANTS:
                return lambda x, a, v=CONSTANTS[value]: v
            func = FUNCTIONS[value]
            if self.peek() == ("op", "("):
                self.take()
                arg = self.expr()
                if self.take() != ("op", ")"):
                    raise ParseError(")")
            else:
                arg = self.power()      # sin x, sin 2x
            return lambda x, a: func(arg(x, a))
        if (kind, value) == ("op", "("):
            node = self.expr()
            if self.take() != ("op", ")"):
                raise ParseError(")")
            return node
        if (kind, value) == ("op", "|"):
            was = self.in_bars
            self.in_bars = True
            node = self.expr()
            self.in_bars = was
            if self.take() != ("op", "|"):
                raise ParseError("|")
            return lambda x, a: abs(node(x, a))
        raise ParseError(str(value))


def compile_equation(text):
    """'y = x^2' -> (function of x and a, uses a). Raises ParseError."""
    body = text.strip()
    if "=" in body:
        left, _, right = body.partition("=")
        if left.strip().lower().replace(" ", "") not in ("y", "f(x)", "g(x)", "h(x)"):
            raise ParseError(left)
        body = right
    parser = Parser(body)
    return parser.parse(), parser.uses_a


def evaluate(func, x, a):
    try:
        y = func(x, a)
    except (ValueError, ZeroDivisionError, OverflowError, TypeError, RecursionError):
        return None
    if isinstance(y, complex) or y is None:
        return None
    try:
        y = float(y)
    except (TypeError, OverflowError, ValueError):
        return None
    return y if math.isfinite(y) else None


def nice_step(span, pixels, target=90):
    """A grid step of 1, 2 or 5 times a power of ten, about target pixels apart."""
    raw = span * target / max(1, pixels)
    power = 10 ** math.floor(math.log10(raw))
    for m in (1, 2, 5, 10):
        if m * power >= raw:
            return m * power
    return 10 * power


def label_for(v, step):
    if abs(v) < step / 1e6:
        return "0"
    digits = max(0, -int(math.floor(math.log10(step))))
    text = f"{v:.{digits}f}"
    return text.replace("-", "−")


class Equation:
    def __init__(self, text="", colour=0, shown=True):
        self.text = text
        self.colour = colour
        self.shown = shown
        self.func = None
        self.uses_a = False
        self.error = None
        self.set_text(text)

    def set_text(self, text):
        self.text = text
        self.func, self.uses_a, self.error = None, False, None
        if text.strip():
            try:
                self.func, self.uses_a = compile_equation(text)
            except (ParseError, RecursionError) as err:
                self.error = str(err)


class Graph(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__()
        self.window = window
        self.cx, self.cy, self.scale = 0.0, 0.0, 50.0     # centre and pixels per unit
        self.drag = None
        self.pointer = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.SCROLL_MASK
                        | Gdk.EventMask.SMOOTH_SCROLL_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("button-release-event", self._release)
        self.connect("motion-notify-event", self._motion)
        self.connect("scroll-event", self._scroll)
        self.connect("leave-notify-event", lambda *_a: self._set_pointer(None))
        zoom = Gtk.GestureZoom.new(self)
        zoom.connect("begin", lambda _g, _s: setattr(self, "pinch_from", self.scale))
        zoom.connect("scale-changed", lambda _g, f: self.zoom_to(self.pinch_from * f))
        self.zoom_gesture = zoom
        self.pinch_from = self.scale

    # coordinates
    def to_screen(self, x, y):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        return w / 2 + (x - self.cx) * self.scale, h / 2 - (y - self.cy) * self.scale

    def to_graph(self, sx, sy):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        return self.cx + (sx - w / 2) / self.scale, self.cy - (sy - h / 2) / self.scale

    def home(self):
        self.cx, self.cy, self.scale = 0.0, 0.0, 50.0
        self.queue_draw()

    def zoom_to(self, scale, around=None):
        scale = max(1e-3, min(1e6, scale))
        if around:
            gx, gy = self.to_graph(*around)
            self.scale = scale
            nx, ny = self.to_graph(*around)
            self.cx += gx - nx
            self.cy += gy - ny
        else:
            self.scale = scale
        self.queue_draw()

    def _press(self, _w, event):
        if event.button == 1:
            self.drag = (event.x, event.y, self.cx, self.cy)
            self.get_window().set_cursor(Gdk.Cursor.new_from_name(self.get_display(), "grabbing"))

    def _release(self, _w, _event):
        self.drag = None
        self.get_window().set_cursor(None)

    def _motion(self, _w, event):
        if self.drag:
            x0, y0, cx, cy = self.drag
            self.cx = cx - (event.x - x0) / self.scale
            self.cy = cy + (event.y - y0) / self.scale
            self.queue_draw()
        else:
            self._set_pointer((event.x, event.y))

    def _set_pointer(self, where):
        self.pointer = where
        self.queue_draw()

    def _scroll(self, _w, event):
        if event.direction == Gdk.ScrollDirection.SMOOTH:
            ok, _dx, dy = event.get_scroll_deltas()
            factor = 1.0015 ** (-dy * 40) if ok else 1
        else:
            factor = 1.2 if event.direction == Gdk.ScrollDirection.UP else 1 / 1.2
        self.zoom_to(self.scale * factor, (event.x, event.y))
        return True

    def _draw(self, _w, cr):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        dark = self.get_style_context().lookup_color("theme_bg_color")[1].red < 0.5
        bg = (0.13, 0.13, 0.15) if dark else (1, 1, 1)
        fg = (0.92, 0.92, 0.94) if dark else (0.1, 0.1, 0.12)
        cr.set_source_rgb(*bg)
        cr.paint()
        x0, y1 = self.to_graph(0, 0)
        x1, y0 = self.to_graph(w, h)
        step = nice_step(x1 - x0, w)
        minor = step / 5
        # minor and major grid
        for size, alpha in ((minor, 0.05), (step, 0.11)):
            if size * self.scale < 6:
                continue
            cr.set_source_rgba(*fg, alpha)
            cr.set_line_width(1)
            v = math.floor(x0 / size) * size
            while v <= x1:
                sx, _ = self.to_screen(v, 0)
                cr.move_to(round(sx) + 0.5, 0)
                cr.line_to(round(sx) + 0.5, h)
                v += size
            v = math.floor(y0 / size) * size
            while v <= y1:
                _, sy = self.to_screen(0, v)
                cr.move_to(0, round(sy) + 0.5)
                cr.line_to(w, round(sy) + 0.5)
                v += size
            cr.stroke()
        # axes
        ax, ay = self.to_screen(0, 0)
        cr.set_source_rgba(*fg, 0.55)
        cr.set_line_width(1.5)
        if 0 <= ax <= w:
            cr.move_to(ax, 0)
            cr.line_to(ax, h)
        if 0 <= ay <= h:
            cr.move_to(0, ay)
            cr.line_to(w, ay)
        cr.stroke()
        # curves
        a = self.window.a_value
        cr.set_line_width(2.5)
        cr.set_line_join(1)
        for eq in self.window.equations:
            if not (eq.shown and eq.func):
                continue
            cr.set_source_rgb(*COLOURS[eq.colour % len(COLOURS)])
            pen = False
            last = None
            px = 0.0
            while px <= w + 1:
                gx, _ = self.to_graph(px, 0)
                gy = evaluate(eq.func, gx, a)
                if gy is None:
                    pen = False
                    last = None
                else:
                    sy = h / 2 - (gy - self.cy) * self.scale
                    if last is not None and abs(sy - last) > h * 2:
                        pen = False      # a jump, as at tan's asymptotes
                    sy = max(-h * 4, min(h * 5, sy))
                    if pen:
                        cr.line_to(px, sy)
                    else:
                        cr.move_to(px, sy)
                        pen = True
                    last = sy
                px += 1.5
            cr.stroke()
        # labels, kept on screen when an axis is off the edge
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription.from_string("Inter 9"))

        def halo(x, y, tw, th):
            cr.set_source_rgba(*bg, 0.85)
            cr.rectangle(x - 2, y, tw + 4, th)
            cr.fill()
            cr.set_source_rgba(*fg, 0.6)

        lx_y = min(max(ay + 4, 4), h - 18)
        v = math.floor(x0 / step) * step
        while v <= x1:
            if abs(v) > step / 2:
                sx, _ = self.to_screen(v, 0)
                layout.set_text(label_for(v, step), -1)
                tw = layout.get_pixel_size()[0]
                halo(sx - tw / 2, lx_y, tw, layout.get_pixel_size()[1])
                cr.move_to(sx - tw / 2, lx_y)
                PangoCairo.show_layout(cr, layout)
            v += step
        v = math.floor(y0 / step) * step
        while v <= y1:
            if abs(v) > step / 2:
                _, sy = self.to_screen(0, v)
                layout.set_text(label_for(v, step), -1)
                tw, th = layout.get_pixel_size()
                lx = min(max(ax - tw - 5, 4), w - tw - 4)
                halo(lx, sy - th / 2, tw, th)
                cr.move_to(lx, sy - th / 2)
                PangoCairo.show_layout(cr, layout)
            v += step
        # the point under the pointer
        if self.pointer and not self.drag:
            px, py = self.pointer
            gx, _ = self.to_graph(px, 0)
            best = None
            for eq in self.window.equations:
                if not (eq.shown and eq.func):
                    continue
                gy = evaluate(eq.func, gx, a)
                if gy is None:
                    continue
                _, sy = self.to_screen(gx, gy)
                if abs(sy - py) < 40 and (best is None or abs(sy - py) < best[0]):
                    best = (abs(sy - py), eq, gy, sy)
            if best:
                _d, eq, gy, sy = best
                colour = COLOURS[eq.colour % len(COLOURS)]
                cr.set_source_rgb(*colour)
                cr.arc(px, sy, 5, 0, 2 * math.pi)
                cr.fill()
                digits = max(2, min(6, 3 - int(math.floor(math.log10(max(1e-9, 1 / self.scale * 10))))))
                text = f"({gx:.{digits}f}, {gy:.{digits}f})".replace("-", "−")
                layout.set_font_description(Pango.FontDescription.from_string("Inter 10"))
                layout.set_text(text, -1)
                tw, th = layout.get_pixel_size()
                bx = min(px + 10, w - tw - 14)
                by = max(sy - th - 16, 4)
                cr.set_source_rgba(*bg, 0.92)
                cr.rectangle(bx - 6, by - 3, tw + 12, th + 6)
                cr.fill()
                cr.set_source_rgb(*colour)
                cr.move_to(bx, by)
                PangoCairo.show_layout(cr, layout)


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Plot")
        self.set_default_size(1080, 700)
        data = self.load()
        self.a_value = float(data.get("a", 1.0)) if isinstance(data.get("a"), (int, float)) else 1.0
        texts = [t for t in data.get("equations", []) if isinstance(t, str)] or list(EXAMPLES)
        self.equations = []

        header = Gtk.HeaderBar(show_close_button=True, title="Plot")
        self.set_titlebar(header)
        home = Gtk.Button(label="Standard View")
        home.set_tooltip_text("Go back to the standard view")
        home.set_action_name("win.home")
        zoom_box = Gtk.Box()
        zoom_box.get_style_context().add_class("linked")
        for text, action, tip in (("−", "win.zoom-out", "Zoom out"), ("+", "win.zoom-in", "Zoom in")):
            button = Gtk.Button(label=text)
            button.set_size_request(34, -1)
            button.set_action_name(action)
            button.set_tooltip_text(tip)
            zoom_box.pack_start(button, False, False, 0)
        header.pack_end(home)
        header.pack_end(zoom_box)

        paned = Gtk.Box()
        self.add(paned)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        side.set_size_request(300, -1)
        side.set_hexpand(False)
        side.set_border_width(12)
        heading = Gtk.Label(xalign=0)
        heading.set_markup("<b>Equations</b>")
        side.pack_start(heading, False, False, 0)
        self.rows = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        side.pack_start(self.rows, False, False, 0)
        add = Gtk.Button(label="Add Equation")
        add.set_action_name("win.add")
        add.set_halign(Gtk.Align.START)
        side.pack_start(add, False, False, 0)
        self.a_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.a_label = Gtk.Label(xalign=0)
        self.a_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, -10, 10, 0.1)
        self.a_scale.set_value(self.a_value)
        self.a_scale.set_draw_value(False)
        self.a_scale.connect("value-changed", self._a_changed)
        self.a_box.pack_start(self.a_label, False, False, 0)
        self.a_box.pack_start(self.a_scale, False, False, 0)
        self.a_box.set_margin_top(10)
        self.a_box.set_no_show_all(True)
        side.pack_start(self.a_box, False, False, 0)
        help_text = Gtk.Label(xalign=0, wrap=True)
        help_text.set_markup("<small>Try  <b>x^2</b>,  <b>2x + 1</b>,  <b>sin(x)</b>,  <b>sqrt(x)</b>,  "
                             "<b>|x|</b>  or  <b>a·x^2</b>  (a gets a slider).\n"
                             "Drag the graph to move it, scroll to zoom.</small>")
        help_text.get_style_context().add_class("dim-label")
        side.pack_end(help_text, False, False, 0)
        paned.pack_start(side, False, False, 0)
        paned.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        self.graph = Graph(self)
        paned.pack_start(self.graph, True, True, 0)

        menus.add_actions(self, {"add": lambda: self.add_equation("", focus=True), "close": self.close,
                                 "home": self.graph.home,
                                 "zoom-in": lambda: self.graph.zoom_to(self.graph.scale * 1.5),
                                 "zoom-out": lambda: self.graph.zoom_to(self.graph.scale / 1.5),
                                 "picture": self.save_picture})
        for text in texts:
            self.add_equation(text)
        self.show_all()
        self.update_a()

    # equations
    def add_equation(self, text, focus=False):
        used = {e.colour for e in self.equations}
        colour = next((i for i in range(len(COLOURS)) if i not in used), len(self.equations))
        eq = Equation(text, colour)
        self.equations.append(eq)
        row = Gtk.Box(spacing=6)
        show = Gtk.CheckButton(active=True)
        show.set_tooltip_text("Show or hide")
        swatch = Gtk.DrawingArea()
        swatch.set_size_request(14, 14)
        swatch.set_valign(Gtk.Align.CENTER)
        swatch.connect("draw", self._swatch, eq)
        entry = Gtk.Entry(text=text, placeholder_text="y = …", hexpand=True)
        remove = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
        remove.set_relief(Gtk.ReliefStyle.NONE)
        remove.set_tooltip_text("Remove")
        row.pack_start(show, False, False, 0)
        row.pack_start(swatch, False, False, 0)
        row.pack_start(entry, True, True, 0)
        row.pack_start(remove, False, False, 0)
        self.rows.pack_start(row, False, False, 0)
        row.show_all()
        show.connect("toggled", lambda b: (setattr(eq, "shown", b.get_active()), self.graph.queue_draw()))
        entry.connect("changed", self._edited, eq)
        entry.connect("activate", lambda _e: self.add_equation("", focus=True) if eq is self.equations[-1]
                      and eq.text.strip() else None)
        remove.connect("clicked", lambda _b: self.remove_equation(eq, row))
        self._mark(entry, eq)
        if focus:
            entry.grab_focus()
        self.graph.queue_draw()
        return eq

    def _swatch(self, area, cr, eq):
        cr.set_source_rgb(*COLOURS[eq.colour % len(COLOURS)])
        size = area.get_allocated_width()
        cr.arc(size / 2, size / 2, size / 2, 0, 2 * math.pi)
        cr.fill()

    def _mark(self, entry, eq):
        if eq.error:
            entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, "dialog-warning-symbolic")
            entry.set_icon_tooltip_text(Gtk.EntryIconPosition.SECONDARY,
                                        "Plot can't read this yet. Use x for the variable, * or nothing to "
                                        "multiply, ^ for powers, and brackets after a function: sin(x).")
        else:
            entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, None)

    def _edited(self, entry, eq):
        eq.set_text(entry.get_text())
        self._mark(entry, eq)
        self.update_a()
        self.graph.queue_draw()
        self.save()

    def remove_equation(self, eq, row):
        self.equations.remove(eq)
        self.rows.remove(row)
        self.update_a()
        self.graph.queue_draw()
        self.save()

    def update_a(self):
        uses = any(e.uses_a for e in self.equations)
        self.a_label.set_markup(f"a = <b>{self.a_value:g}</b>".replace("-", "−"))
        if uses:
            for widget in (self.a_label, self.a_scale, self.a_box):
                widget.show()
        else:
            self.a_box.hide()

    def _a_changed(self, scale):
        self.a_value = round(scale.get_value(), 1)
        self.update_a()
        self.graph.queue_draw()
        self.save()

    # saving
    def load(self):
        try:
            with open(STORE) as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def save(self):
        data = {"equations": [e.text for e in self.equations if e.text.strip()], "a": self.a_value}
        os.makedirs(os.path.dirname(STORE), exist_ok=True)
        tmp = STORE + ".tmp"
        try:
            with open(tmp, "w") as f:
                json.dump(data, f)
            os.replace(tmp, STORE)
        except OSError:
            pass

    def save_picture(self):
        chooser = Gtk.FileChooserNative.new("Save Picture", self, Gtk.FileChooserAction.SAVE, "Save", "Cancel")
        chooser.set_current_name("Graph.png")
        chooser.set_do_overwrite_confirmation(True)
        pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
        if pictures and os.path.isdir(pictures):
            chooser.set_current_folder(pictures)
        if chooser.run() == Gtk.ResponseType.ACCEPT:
            path = chooser.get_filename()
            if not path.lower().endswith(".png"):
                path += ".png"
            import cairo
            w, h = self.graph.get_allocated_width(), self.graph.get_allocated_height()
            surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
            cr = cairo.Context(surface)
            pointer, self.graph.pointer = self.graph.pointer, None
            self.graph._draw(self.graph, cr)
            self.graph.pointer = pointer
            surface.write_to_png(path)
        chooser.destroy()

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Plot")
        dialog.format_secondary_text("Plot draws equations. It is part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_File", [[("Add Equation", "win.add", "<Ctrl>n")], [("Save Picture…", "win.picture", "<Ctrl>s")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_View", [[("Zoom In", "win.zoom-in", "<Ctrl>plus"), ("Zoom Out", "win.zoom-out", "<Ctrl>minus"),
                    ("Standard View", "win.home", "<Ctrl>0")]]),
    ])


class Plot(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close(),
                                 "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.add", "<Control>n"), ("win.picture", "<Control>s"), ("win.close", "<Control>w"),
                             ("win.zoom-in", "<Control>plus"), ("win.zoom-out", "<Control>minus"),
                             ("win.home", "<Control>0")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-plot")
    return Plot().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
