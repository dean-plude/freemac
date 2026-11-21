# SPDX-License-Identifier: GPL-3.0-or-later
"""Ledger: freemac's spreadsheet.

One sheet per window. Type in a cell, or start with = for a formula; the
formulas are in ledger_calc. Arrow keys move, Shift extends the selection,
Return and Tab move on after typing, double-click or F2 edits what's there.
While typing a formula, clicking a cell puts its address in. Files are kept
as .ledger (JSON); CSV files open and save too. Original freemac code.
"""
import json
import locale
import math
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import alert, menus, savesheet, style  # noqa: E402
from .ledger_calc import (ERRORS, Sheet, address, column_name, format_value, insert_or_delete,  # noqa: E402
                          parse_address, shift_formula)

APP_ID = "org.freemac.Ledger"
ROW_H = 24
HEAD_H = 24
ROW_HEAD_W = 46
COL_W = 96
MIN_COLS, MIN_ROWS = 26, 60
FORMAT_NAMES = (("general", "Automatic"), ("number", "Number (1,234.56)"),
                ("currency", "Currency"), ("percent", "Percentage"))
SERIES_COLOURS = ((0.16, 0.47, 0.94), (0.98, 0.58, 0.13), (0.20, 0.70, 0.36), (0.85, 0.26, 0.42))


def currency_symbol():
    try:
        locale.setlocale(locale.LC_MONETARY, "")
        symbol = locale.localeconv().get("currency_symbol")
    except (locale.Error, ValueError):
        symbol = None
    return symbol or "$"


SYMBOL = currency_symbol()

CSS = b"""
.ledger-bar { padding: 4px 8px; border-bottom: 1px solid alpha(@theme_fg_color, 0.12); }
.ledger-where { font-weight: 600; min-width: 56px; color: alpha(@theme_fg_color, 0.75); }
.ledger-status { padding: 3px 10px; font-size: 12px; color: alpha(@theme_fg_color, 0.65);
                 border-top: 1px solid alpha(@theme_fg_color, 0.12); }
entry.ledger-cell { border-radius: 0; min-height: 0; padding: 0 4px; border: 2px solid @theme_selected_bg_color;
                    box-shadow: 0 2px 6px alpha(black, 0.18); }
"""


class Grid(Gtk.DrawingArea):
    """The cells, with the column letters along the top and the row numbers
    down the side, drawn for the part scrolled into view."""

    def __init__(self, window):
        super().__init__()
        self.win = window
        self.set_can_focus(True)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK |
                        Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.SCROLL_MASK |
                        Gdk.EventMask.SMOOTH_SCROLL_MASK | Gdk.EventMask.KEY_PRESS_MASK)
        self.connect("draw", self._draw)

    # geometry
    def col_width(self, col):
        return self.win.sheet.widths.get(col, COL_W)

    def col_x(self, col):
        """Left edge of a column in sheet pixels (before scrolling)."""
        widths = self.win.sheet.widths
        if not widths:
            return col * COL_W
        return col * COL_W + sum(w - COL_W for c, w in widths.items() if c < col)

    def col_at(self, x):
        """Column under sheet-pixel x."""
        col = int(x // COL_W) if not self.win.sheet.widths else 0
        if self.win.sheet.widths:
            edge = 0
            while edge + self.col_width(col) <= x:
                edge += self.col_width(col)
                col += 1
        return max(0, col)

    def cell_rect(self, col, row):
        """(x, y, w, h) on screen."""
        x = ROW_HEAD_W + self.col_x(col) - self.win.hadj.get_value()
        y = HEAD_H + row * ROW_H - self.win.vadj.get_value()
        return x, y, self.col_width(col), ROW_H

    def hit(self, x, y):
        """(col, row) under a point, -1 for the headers."""
        col = self.col_at(x - ROW_HEAD_W + self.win.hadj.get_value()) if x >= ROW_HEAD_W else -1
        row = int((y - HEAD_H + self.win.vadj.get_value()) // ROW_H) if y >= HEAD_H else -1
        return col, max(-1, row)

    def border_at(self, x, y):
        """A column whose right edge is under the pointer in the header, for resizing."""
        if y >= HEAD_H or x < ROW_HEAD_W:
            return None
        col = self.col_at(x - ROW_HEAD_W + self.win.hadj.get_value())
        for c in (col - 1, col):
            if c >= 0:
                cx, _y, w, _h = self.cell_rect(c, 0)
                if abs(cx + w - x) <= 4:
                    return c
        return None

    # drawing
    def _draw(self, _widget, cr):
        win = self.win
        sheet = win.sheet
        width, height = self.get_allocated_width(), self.get_allocated_height()
        ctx = self.get_style_context()
        dark = style.is_dark()
        fg = (0.92, 0.92, 0.93) if dark else (0.11, 0.11, 0.12)
        bg = (0.13, 0.13, 0.14) if dark else (1, 1, 1)
        head_bg = (0.19, 0.19, 0.20) if dark else (0.965, 0.965, 0.97)
        line = (1, 1, 1, 0.09) if dark else (0, 0, 0, 0.09)
        accent = ctx.lookup_color("theme_selected_bg_color")
        accent = (accent[1].red, accent[1].green, accent[1].blue) if accent[0] else (0.16, 0.47, 0.94)

        cr.set_source_rgb(*bg)
        cr.paint()
        sx, sy = win.hadj.get_value(), win.vadj.get_value()
        first_row = int(sy // ROW_H)
        last_row = int((sy + height - HEAD_H) // ROW_H) + 1
        first_col = self.col_at(sx)
        cols = []
        col = first_col
        while True:
            x, _y, w, _h = self.cell_rect(col, 0)
            if x > width:
                break
            cols.append((col, x, w))
            col += 1
        (c1, r1), (c2, r2) = win.selection()

        # selection fill
        x1, y1, _w, _h = self.cell_rect(c1, r1)
        x2, y2, w2, h2 = self.cell_rect(c2, r2)
        if (c1, r1) != (c2, r2):
            cr.set_source_rgba(*accent, 0.12)
            cr.rectangle(x1, y1, x2 + w2 - x1, y2 + h2 - y1)
            cr.fill()

        # grid lines
        cr.set_source_rgba(*line)
        cr.set_line_width(1)
        for col, x, w in cols:
            cr.move_to(int(x + w) + 0.5, HEAD_H)
            cr.line_to(int(x + w) + 0.5, height)
        for row in range(first_row, last_row + 1):
            y = HEAD_H + (row + 1) * ROW_H - sy
            cr.move_to(ROW_HEAD_W, int(y) + 0.5)
            cr.line_to(width, int(y) + 0.5)
        cr.stroke()

        # cells
        layout = PangoCairo.create_layout(cr)
        font = self.get_pango_context().get_font_description().copy()
        font.set_absolute_size(13 * Pango.SCALE)
        bold = font.copy()
        bold.set_weight(Pango.Weight.BOLD)
        editing = win.editing
        for row in range(first_row, last_row):
            for col, x, w in cols:
                if (col, row) not in sheet.cells or ((col, row) == editing):
                    continue
                value = sheet.value(col, row)
                text = format_value(value, sheet.formats.get((col, row), "general"), SYMBOL)
                if not text:
                    continue
                y = HEAD_H + row * ROW_H - sy
                layout.set_font_description(bold if (col, row) in sheet.bold else font)
                layout.set_text(text, -1)
                tw, th = (v / Pango.SCALE for v in layout.get_size())
                fmt = sheet.formats.get((col, row), "general")
                if isinstance(value, float) and fmt == "general" and tw > w - 10:
                    for digits in range(9, 2, -1):
                        text = format_value(value, fmt, SYMBOL, digits)
                        layout.set_text(text, -1)
                        tw, th = (v / Pango.SCALE for v in layout.get_size())
                        if tw <= w - 10:
                            break
                if isinstance(value, float) and tw > w - 4:
                    layout.set_text("###", -1)
                    tw, th = (v / Pango.SCALE for v in layout.get_size())
                if isinstance(value, float):
                    tx = x + w - 6 - tw
                elif isinstance(value, bool) or (isinstance(value, str) and value in ERRORS):
                    tx = x + (w - tw) / 2
                else:
                    tx = x + 6
                cr.save()
                cr.rectangle(x + 1, y, w - 2, ROW_H)
                cr.clip()
                if isinstance(value, str) and value in ERRORS:
                    cr.set_source_rgb(0.85, 0.2, 0.2)
                else:
                    cr.set_source_rgb(*fg)
                cr.move_to(tx, y + (ROW_H - th) / 2)
                PangoCairo.show_layout(cr, layout)
                cr.restore()

        # headers
        cr.set_source_rgb(*head_bg)
        cr.rectangle(0, 0, width, HEAD_H)
        cr.rectangle(0, 0, ROW_HEAD_W, height)
        cr.fill()
        small = font.copy()
        small.set_absolute_size(11 * Pango.SCALE)
        layout.set_font_description(small)
        for col, x, w in cols:
            chosen = c1 <= col <= c2
            if chosen:
                cr.set_source_rgba(*accent, 0.18)
                cr.rectangle(x, 0, w, HEAD_H)
                cr.fill()
            layout.set_text(column_name(col), -1)
            tw, th = (v / Pango.SCALE for v in layout.get_size())
            cr.set_source_rgba(*fg, 0.9 if chosen else 0.55)
            cr.move_to(x + (w - tw) / 2, (HEAD_H - th) / 2)
            PangoCairo.show_layout(cr, layout)
        for row in range(first_row, last_row):
            y = HEAD_H + row * ROW_H - sy
            if y + ROW_H < HEAD_H:
                continue
            chosen = r1 <= row <= r2
            if chosen:
                cr.set_source_rgba(*accent, 0.18)
                cr.rectangle(0, y, ROW_HEAD_W, ROW_H)
                cr.fill()
            layout.set_text(str(row + 1), -1)
            tw, th = (v / Pango.SCALE for v in layout.get_size())
            cr.set_source_rgba(*fg, 0.9 if chosen else 0.55)
            cr.move_to(ROW_HEAD_W - 8 - tw, y + (ROW_H - th) / 2)
            PangoCairo.show_layout(cr, layout)
        cr.set_source_rgba(*line)
        for col, x, w in cols:
            cr.move_to(int(x + w) + 0.5, 4)
            cr.line_to(int(x + w) + 0.5, HEAD_H - 4)
        cr.move_to(0, HEAD_H - 0.5)
        cr.line_to(width, HEAD_H - 0.5)
        cr.move_to(ROW_HEAD_W - 0.5, 0)
        cr.line_to(ROW_HEAD_W - 0.5, height)
        cr.stroke()
        # the header corner covers cells scrolled under it
        cr.set_source_rgb(*head_bg)
        cr.rectangle(0, 0, ROW_HEAD_W - 1, HEAD_H - 1)
        cr.fill()

        # the selection's outline and the cursor cell
        cr.save()
        cr.rectangle(ROW_HEAD_W, HEAD_H, width - ROW_HEAD_W, height - HEAD_H)
        cr.clip()
        cr.set_source_rgb(*accent)
        cr.set_line_width(2)
        cr.rectangle(x1 + 0.5, y1 + 0.5, x2 + w2 - x1 - 1, y2 + h2 - y1 - 1)
        cr.stroke()
        if win.pointing is not None:
            (p1, q1), (p2, q2) = win.pointing
            px1, py1, _w, _h = self.cell_rect(p1, q1)
            px2, py2, pw, ph = self.cell_rect(p2, q2)
            cr.set_source_rgb(0.95, 0.55, 0.1)
            cr.set_dash([4, 3])
            cr.rectangle(px1 + 1, py1 + 1, px2 + pw - px1 - 2, py2 + ph - py1 - 2)
            cr.stroke()
        cr.restore()
        return False


class ChartWindow(Gtk.Window):
    """A bar or line chart of the cells selected when it opened."""

    def __init__(self, parent, labels, series):
        super().__init__(title="Chart", transient_for=parent)
        self.set_default_size(620, 420)
        self.labels, self.series, self.kind = labels, series, "bar"
        header = Gtk.HeaderBar(show_close_button=True, title="Chart")
        self.set_titlebar(header)
        kinds = Gtk.Box(spacing=0)
        kinds.get_style_context().add_class("linked")
        first = None
        for kind, label in (("bar", "Bars"), ("line", "Line")):
            button = Gtk.RadioButton.new_with_label_from_widget(first, label)
            button.set_mode(False)
            button.connect("toggled", self._kind, kind)
            first = first or button
            kinds.pack_start(button, False, False, 0)
        header.pack_start(kinds)
        save = Gtk.Button(label="Save as Picture…")
        save.connect("clicked", lambda _b: self.save())
        header.pack_end(save)
        self.area = Gtk.DrawingArea()
        self.area.connect("draw", lambda _w, cr: self.paint(cr, self.area.get_allocated_width(),
                                                             self.area.get_allocated_height()))
        self.add(self.area)

    def _kind(self, button, kind):
        if button.get_active():
            self.kind = kind
            self.area.queue_draw()

    def paint(self, cr, width, height, for_file=False):
        dark = style.is_dark() and not for_file
        fg = (0.92, 0.92, 0.93) if dark else (0.15, 0.15, 0.17)
        cr.set_source_rgb(*((0.13, 0.13, 0.14) if dark else (1, 1, 1)))
        cr.paint()
        values = [v for _name, vals in self.series for v in vals]
        top = max(values + [0.0])
        bottom = min(values + [0.0])
        if top == bottom:
            top = bottom + 1
        step = nice_step((top - bottom) / 5)
        top = math.ceil(top / step) * step
        bottom = math.floor(bottom / step) * step
        layout = PangoCairo.create_layout(cr)
        font = Pango.FontDescription.from_string("Sans")
        font.set_absolute_size(12 * Pango.SCALE)
        layout.set_font_description(font)
        left, right, upper = 64, width - 20, 20
        legend = 28 if len(self.series) > 1 or self.series[0][0] else 0
        lower = height - 36 - legend
        span = top - bottom

        def y_of(v):
            return lower - (v - bottom) / span * (lower - upper)

        # gridlines and their numbers
        v = bottom
        while v <= top + step / 2:
            y = y_of(v)
            cr.set_source_rgba(*fg, 0.12 if abs(v) > 1e-12 else 0.4)
            cr.set_line_width(1)
            cr.move_to(left, int(y) + 0.5)
            cr.line_to(right, int(y) + 0.5)
            cr.stroke()
            layout.set_text(format_value(round(v, 10)), -1)
            tw, th = (n / Pango.SCALE for n in layout.get_size())
            cr.set_source_rgba(*fg, 0.7)
            cr.move_to(left - 8 - tw, y - th / 2)
            PangoCairo.show_layout(cr, layout)
            v += step
        count = len(self.labels)
        slot = (right - left) / max(1, count)
        for i, label in enumerate(self.labels):
            layout.set_text(label, -1)
            layout.set_width(int(max(10, slot - 4) * Pango.SCALE))
            layout.set_ellipsize(Pango.EllipsizeMode.END)
            layout.set_alignment(Pango.Alignment.CENTER)
            cr.set_source_rgba(*fg, 0.8)
            cr.move_to(left + i * slot + 2, lower + 8)
            PangoCairo.show_layout(cr, layout)
        layout.set_width(-1)
        layout.set_alignment(Pango.Alignment.LEFT)
        zero = y_of(max(bottom, min(0.0, top)))
        n = len(self.series)
        for s, (_name, vals) in enumerate(self.series):
            colour = SERIES_COLOURS[s % len(SERIES_COLOURS)]
            cr.set_source_rgb(*colour)
            if self.kind == "bar":
                bar = slot * 0.7 / n
                for i, v in enumerate(vals):
                    x = left + i * slot + slot * 0.15 + s * bar
                    y = y_of(v)
                    cr.rectangle(x, min(y, zero), max(1, bar - 2), abs(zero - y))
                cr.fill()
            else:
                cr.set_line_width(2.5)
                for i, v in enumerate(vals):
                    x, y = left + (i + 0.5) * slot, y_of(v)
                    (cr.line_to if i else cr.move_to)(x, y)
                cr.stroke()
                for i, v in enumerate(vals):
                    cr.arc(left + (i + 0.5) * slot, y_of(v), 3.5, 0, 2 * math.pi)
                    cr.fill()
        if legend:
            x = left
            for s, (name, _vals) in enumerate(self.series):
                cr.set_source_rgb(*SERIES_COLOURS[s % len(SERIES_COLOURS)])
                cr.rectangle(x, height - legend + 2, 12, 12)
                cr.fill()
                layout.set_text(name or f"Series {s + 1}", -1)
                tw, th = (n / Pango.SCALE for n in layout.get_size())
                cr.set_source_rgba(*fg, 0.85)
                cr.move_to(x + 18, height - legend + 8 - th / 2)
                PangoCairo.show_layout(cr, layout)
                x += 18 + tw + 20

    def save(self):
        path = savesheet.ask(self, "Chart.png")
        if not path:
            return
        import cairo
        surface = cairo.ImageSurface(cairo.FORMAT_RGB24, 1200, 800)
        cr = cairo.Context(surface)
        cr.scale(2, 2)
        self.paint(cr, 600, 400, for_file=True)
        try:
            surface.write_to_png(path)
        except (OSError, cairo.Error) as err:
            alert.tell(self, "The chart couldn't be saved.", str(err))


def nice_step(raw):
    if raw <= 0:
        return 1.0
    power = 10 ** math.floor(math.log10(raw))
    for m in (1, 2, 2.5, 5, 10):
        if m * power >= raw:
            return m * power
    return 10 * power


def chart_data(sheet, c1, r1, c2, r2):
    """(labels, [(name, values)]) from a block of cells: a first column of
    text gives the labels and a first row of text the series' names."""
    def is_num(c, r):
        return isinstance(sheet.value(c, r), float)

    label_col = c2 > c1 and not any(is_num(c1, r) for r in range(r1, r2 + 1))
    first_data_col = c1 + 1 if label_col else c1
    name_row = r2 > r1 and not any(is_num(c, r1) for c in range(first_data_col, c2 + 1))
    first_data_row = r1 + 1 if name_row else r1
    rows = range(first_data_row, r2 + 1)
    if label_col:
        labels = [format_value(sheet.value(c1, r)) for r in rows]
    else:
        labels = [str(r + 1) for r in rows]
    series = []
    for c in range(first_data_col, c2 + 1):
        values = [sheet.value(c, r) for r in rows]
        if not any(isinstance(v, float) for v in values):
            continue
        name = format_value(sheet.value(c, r1)) if name_row else ""
        series.append((name, [v if isinstance(v, float) else 0.0 for v in values]))
    return labels, series[:4]


class Window(Gtk.ApplicationWindow):
    def __init__(self, app, path=None):
        super().__init__(application=app, title="Untitled")
        self.set_default_size(980, 640)
        self.sheet = Sheet()
        self.path = None
        self.modified = False
        self.cursor = (0, 0)
        self.anchor = (0, 0)
        self.editing = None          # the cell being typed in
        self.pointing = None         # a range being pointed at while typing a formula
        self.drag = None
        self.undo_stack, self.redo_stack = [], []

        header = Gtk.HeaderBar(show_close_button=True)
        self.header = header
        self.set_titlebar(header)
        open_button = Gtk.Button(label="Open")
        open_button.connect("clicked", lambda _b: self.open_dialog())
        header.pack_start(open_button)
        save = Gtk.Button(label="Save")
        save.get_style_context().add_class("suggested-action")
        save.connect("clicked", lambda _b: self.save())
        header.pack_end(save)
        header.pack_end(self._tool("Chart", "x-office-presentation-symbolic", self.show_chart,
                                   "Make a chart of the selected cells"))
        header.pack_end(self._menu_tool("Sort", "view-sort-ascending-symbolic",
                                        [("Sort A to Z (Smallest First)", lambda: self.sort(False)),
                                         ("Sort Z to A (Largest First)", lambda: self.sort(True))]))
        header.pack_end(self._tool("Sum", "accessories-calculator-symbolic", self.autosum,
                                   "Add up the cells above or to the left"))
        header.pack_end(self._menu_tool("Format", "preferences-desktop-locale-symbolic",
                                        [(label, lambda f=fmt: self.set_format(f)) for fmt, label in FORMAT_NAMES]))
        self.bold_button = Gtk.ToggleButton()
        bold_label = Gtk.Label()
        bold_label.set_markup("<b>B</b>")
        self.bold_button.add(bold_label)
        self.bold_button.set_tooltip_text("Bold (⌘B)")
        self.bold_handler = self.bold_button.connect("toggled", lambda b: self.set_bold(b.get_active()))
        header.pack_end(self.bold_button)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)
        bar = Gtk.Box(spacing=8)
        bar.get_style_context().add_class("ledger-bar")
        self.where = Gtk.Label(label="A1", xalign=0.5)
        self.where.get_style_context().add_class("ledger-where")
        bar.pack_start(self.where, False, False, 0)
        fx = Gtk.Label(label="ƒx")
        fx.set_opacity(0.55)
        bar.pack_start(fx, False, False, 0)
        self.formula = Gtk.Entry(placeholder_text="Type a number, words, or = and a formula such as =SUM(A1:A9)")
        self.formula.connect("activate", lambda _e: self.commit_from(self.formula, (0, 1)))
        self.formula.connect("changed", self._formula_changed)
        self.formula.connect("key-press-event", self._entry_key)
        self.formula.connect("focus-in-event", lambda *_: self._begin_from_bar())
        bar.pack_start(self.formula, True, True, 0)
        outer.pack_start(bar, False, False, 0)

        self.hadj = Gtk.Adjustment(value=0, lower=0, upper=1, step_increment=COL_W / 2, page_increment=400)
        self.vadj = Gtk.Adjustment(value=0, lower=0, upper=1, step_increment=ROW_H * 3, page_increment=400)
        self.grid = Grid(self)
        self.grid.connect("button-press-event", self._press)
        self.grid.connect("button-release-event", self._release)
        self.grid.connect("motion-notify-event", self._motion)
        self.grid.connect("scroll-event", self._scroll)
        self.grid.connect("key-press-event", self._grid_key)
        self.grid.connect("size-allocate", lambda *_: self._update_extent())
        for adj in (self.hadj, self.vadj):
            adj.connect("value-changed", lambda *_: self._moved_view())
        self.cell_entry = Gtk.Entry()
        self.cell_entry.get_style_context().add_class("ledger-cell")
        self.cell_entry.set_halign(Gtk.Align.START)
        self.cell_entry.set_valign(Gtk.Align.START)
        self.cell_entry.set_has_frame(True)
        self.cell_entry.connect("key-press-event", self._entry_key)
        self.cell_entry.connect("changed", self._cell_changed)
        self.cell_entry.connect("activate", lambda _e: self.commit_from(self.cell_entry, (0, 1)))
        self.cell_entry.set_no_show_all(True)
        overlay = Gtk.Overlay()
        overlay.add(self.grid)
        overlay.add_overlay(self.cell_entry)
        table = Gtk.Grid()
        table.attach(overlay, 0, 0, 1, 1)
        overlay.set_hexpand(True)
        overlay.set_vexpand(True)
        table.attach(Gtk.Scrollbar(orientation=Gtk.Orientation.VERTICAL, adjustment=self.vadj), 1, 0, 1, 1)
        table.attach(Gtk.Scrollbar(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.hadj), 0, 1, 1, 1)
        outer.pack_start(table, True, True, 0)
        self.status = Gtk.Label(xalign=1)
        self.status.get_style_context().add_class("ledger-status")
        outer.pack_start(self.status, False, False, 0)

        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self._add_actions()
        self.connect("delete-event", lambda *_: not self.confirm_close())
        self.connect("key-press-event", self._window_key)
        if path:
            self.load(path)
        self._selection_changed()
        self.grid.grab_focus()

    def _tool(self, label, icon, callback, tip):
        button = Gtk.Button()
        box = Gtk.Box(spacing=4)
        box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON), False, False, 0)
        box.pack_start(Gtk.Label(label=label), False, False, 0)
        button.add(box)
        button.set_tooltip_text(tip)
        button.connect("clicked", lambda _b: callback())
        return button

    def _menu_tool(self, label, icon, entries):
        button = Gtk.MenuButton()
        box = Gtk.Box(spacing=4)
        box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON), False, False, 0)
        box.pack_start(Gtk.Label(label=label), False, False, 0)
        box.pack_start(Gtk.Image.new_from_icon_name("pan-down-symbolic", Gtk.IconSize.MENU), False, False, 0)
        button.add(box)
        popover = Gtk.Popover()
        items = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for text, callback in entries:
            item = Gtk.ModelButton(text=text)
            item.connect("clicked", lambda _b, c=callback: (popover.popdown(), c()))
            items.pack_start(item, False, False, 0)
        items.show_all()
        popover.add(items)
        button.set_popover(popover)
        return button

    def _add_actions(self):
        menus.add_actions(self, {
            "open": self.open_dialog, "save": self.save, "save-as": self.save_as,
            "export-csv": self.export_csv, "close": self.close,
            "undo": self.undo, "redo": self.redo, "cut": lambda: self.copy(cut=True), "copy": self.copy,
            "paste": self.paste, "clear": self.clear, "select-all": self.select_all,
            "fill-down": lambda: self.fill(down=True), "fill-right": lambda: self.fill(down=False),
            "bold": lambda: self.set_bold(not self._all_bold()), "sum": self.autosum, "chart": self.show_chart,
            "sort-up": lambda: self.sort(False), "sort-down": lambda: self.sort(True),
            "row-above": lambda: self.insert(1, 0), "row-below": lambda: self.insert(1, 1),
            "col-left": lambda: self.insert(0, 0), "col-right": lambda: self.insert(0, 1),
            "delete-rows": lambda: self.delete(1), "delete-cols": lambda: self.delete(0),
            "format-general": lambda: self.set_format("general"), "format-number": lambda: self.set_format("number"),
            "format-currency": lambda: self.set_format("currency"),
            "format-percent": lambda: self.set_format("percent"),
        })

    # --- selection and view ---------------------------------------------------
    def selection(self):
        (a, b), (c, d) = self.anchor, self.cursor
        return (min(a, c), min(b, d)), (max(a, c), max(b, d))

    def select(self, cell, extend=False):
        col, row = max(0, cell[0]), max(0, cell[1])
        self.cursor = (col, row)
        if not extend:
            self.anchor = (col, row)
        self.scroll_to(col, row)
        self._selection_changed()

    def select_all(self):
        cols, rows = self.sheet.extent()
        self.anchor, self.cursor = (0, 0), (max(0, cols - 1), max(0, rows - 1))
        self._selection_changed()

    def scroll_to(self, col, row):
        x, y, w, h = self.grid.cell_rect(col, row)
        width, height = self.grid.get_allocated_width(), self.grid.get_allocated_height()
        self._update_extent(col, row)
        if x < ROW_HEAD_W:
            self.hadj.set_value(self.hadj.get_value() - (ROW_HEAD_W - x))
        elif x + w > width:
            self.hadj.set_value(self.hadj.get_value() + (x + w - width))
        if y < HEAD_H:
            self.vadj.set_value(self.vadj.get_value() - (HEAD_H - y))
        elif y + h > height:
            self.vadj.set_value(self.vadj.get_value() + (y + h - height))

    def _update_extent(self, col=0, row=0):
        cols, rows = self.sheet.extent()
        cols = max(MIN_COLS, cols + 5, col + 5, self.cursor[0] + 5)
        rows = max(MIN_ROWS, rows + 30, row + 30, self.cursor[1] + 30)
        width = self.grid.col_x(cols) + ROW_HEAD_W
        height = rows * ROW_H + HEAD_H
        view_w, view_h = self.grid.get_allocated_width(), self.grid.get_allocated_height()
        self.hadj.configure(min(self.hadj.get_value(), max(0, width - view_w)), 0, width, COL_W / 2,
                            view_w * 0.9, view_w)
        self.vadj.configure(min(self.vadj.get_value(), max(0, height - view_h)), 0, height, ROW_H * 3,
                            view_h * 0.9, view_h)

    def _moved_view(self):
        self._place_entry()
        self.grid.queue_draw()

    def _selection_changed(self):
        col, row = self.cursor
        (c1, r1), (c2, r2) = self.selection()
        self.where.set_text(address(col, row) if (c1, r1) == (c2, r2)
                            else f"{address(c1, r1)}:{address(c2, r2)}")
        if self.editing is None:
            self._set_quietly(self.formula, self.sheet.get(col, row))
        self.bold_button.handler_block(self.bold_handler)
        self.bold_button.set_active(self._all_bold())
        self.bold_button.handler_unblock(self.bold_handler)
        self._update_status()
        self.grid.queue_draw()

    def _update_status(self):
        (c1, r1), (c2, r2) = self.selection()
        numbers, filled = [], 0
        if (c2 - c1 + 1) * (r2 - r1 + 1) <= 100000:
            for (c, r) in self.sheet.cells:
                if c1 <= c <= c2 and r1 <= r <= r2:
                    filled += 1
                    v = self.sheet.value(c, r)
                    if isinstance(v, float):
                        numbers.append(v)
        if len(numbers) >= 1 and (c1, r1) != (c2, r2):
            total = math.fsum(numbers)
            fmt = self.sheet.formats.get(self.cursor, "general")
            self.status.set_text(f"Sum: {format_value(total, fmt, SYMBOL)}    "
                                 f"Average: {format_value(total / len(numbers), fmt, SYMBOL)}    "
                                 f"Count: {filled}")
        else:
            self.status.set_text("")

    def _all_bold(self):
        (c1, r1), (c2, r2) = self.selection()
        if (c2 - c1 + 1) * (r2 - r1 + 1) > 5000:
            return False
        return all((c, r) in self.sheet.bold for c in range(c1, c2 + 1) for r in range(r1, r2 + 1))

    # --- mouse -------------------------------------------------------------------
    def _press(self, _widget, event):
        self.grid.grab_focus() if self.editing is None else None
        if event.button != 1 and event.button != 3:
            return False
        border = self.grid.border_at(event.x, event.y)
        if border is not None and event.button == 1:
            self.drag = ("resize", border, event.x, self.grid.col_width(border))
            return True
        col, row = self.grid.hit(event.x, event.y)
        if event.button == 3:
            if col >= 0 and row >= 0:
                (c1, r1), (c2, r2) = self.selection()
                if not (c1 <= col <= c2 and r1 <= row <= r2):
                    self.select((col, row))
            self._context_menu(event, col, row)
            return True
        if self.editing is not None and self._wants_reference() and col >= 0 and row >= 0:
            self.pointing = ((col, row), (col, row))
            self.drag = ("point", (col, row))
            self._insert_reference()
            return True
        if self.editing is not None:
            self.commit_from(self._active_entry(), None)
        extend = bool(event.state & Gdk.ModifierType.SHIFT_MASK)
        if col < 0 and row < 0:
            self.select_all()
            return True
        if row < 0:      # a column letter: the whole column
            self.anchor, self.cursor = (col, 0), (col, max(MIN_ROWS, self.sheet.extent()[1]) - 1)
            if extend:
                self.anchor = (min(col, self.anchor[0]), 0)
            self.drag = ("cols", col)
            self._selection_changed()
            return True
        if col < 0:
            self.anchor, self.cursor = (0, row), (max(MIN_COLS, self.sheet.extent()[0]) - 1, row)
            self.drag = ("rows", row)
            self._selection_changed()
            return True
        if event.type == Gdk.EventType._2BUTTON_PRESS:
            self.begin_edit()
            return True
        self.select((col, row), extend)
        self.drag = ("select",)
        return True

    def _motion(self, _widget, event):
        if self.drag is None:
            window = self.grid.get_window()
            if window:
                border = self.grid.border_at(event.x, event.y)
                cursor = Gdk.Cursor.new_from_name(window.get_display(), "col-resize") if border is not None else None
                window.set_cursor(cursor)
            return False
        col, row = self.grid.hit(event.x, event.y)
        kind = self.drag[0]
        if kind == "resize":
            _k, which, start_x, start_w = self.drag
            self.sheet.widths[which] = max(30, int(start_w + event.x - start_x))
            self._mark_modified()
            self._update_extent()
            self.grid.queue_draw()
        elif kind == "point" and col >= 0 and row >= 0:
            self.pointing = (self.drag[1], (col, row))
            self._insert_reference(replace=True)
        elif kind == "select" and col >= 0 and row >= 0:
            if (col, row) != self.cursor:
                self.cursor = (col, row)
                self.scroll_to(col, row)
                self._selection_changed()
        elif kind == "cols" and col >= 0:
            self.cursor = (col, self.cursor[1])
            self._selection_changed()
        elif kind == "rows" and row >= 0:
            self.cursor = (self.cursor[0], row)
            self._selection_changed()
        return True

    def _release(self, *_):
        if self.drag and self.drag[0] == "point":
            entry = self._active_entry()
            entry.grab_focus_without_selecting()
            entry.set_position(-1)
        self.drag = None
        return False

    def _scroll(self, _widget, event):
        ok, dx, dy = event.get_scroll_deltas()
        if not ok:
            direction = event.direction
            dx = {Gdk.ScrollDirection.LEFT: -1, Gdk.ScrollDirection.RIGHT: 1}.get(direction, 0)
            dy = {Gdk.ScrollDirection.UP: -1, Gdk.ScrollDirection.DOWN: 1}.get(direction, 0)
        if event.state & Gdk.ModifierType.SHIFT_MASK:
            dx, dy = dy, dx
        self.hadj.set_value(self.hadj.get_value() + dx * 60)
        self.vadj.set_value(self.vadj.get_value() + dy * 60)
        return True

    def _context_menu(self, event, col, row):
        menu = Gtk.Popover(relative_to=self.grid)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(event.x), int(event.y), 1, 1
        menu.set_pointing_to(rect)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        entries = [("Cut", "win.cut"), ("Copy", "win.copy"), ("Paste", "win.paste"), ("Clear", "win.clear"), None,
                   ("Add Row Above", "win.row-above"), ("Add Row Below", "win.row-below"),
                   ("Add Column Before", "win.col-left"), ("Add Column After", "win.col-right"), None,
                   ("Delete Rows", "win.delete-rows"), ("Delete Columns", "win.delete-cols")]
        for entry in entries:
            if entry is None:
                box.pack_start(Gtk.Separator(margin_top=4, margin_bottom=4), False, False, 0)
                continue
            item = Gtk.ModelButton(text=entry[0])
            item.set_action_name(entry[1])
            box.pack_start(item, False, False, 0)
        box.show_all()
        menu.add(box)
        menu.popup()

    # --- keys -------------------------------------------------------------------------
    def _window_key(self, _widget, event):
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        shift = event.state & Gdk.ModifierType.SHIFT_MASK
        name = Gdk.keyval_name(Gdk.keyval_to_lower(event.keyval)) or ""
        if not ctrl:
            return False
        in_text = self.editing is not None or self.formula.has_focus()
        if in_text and name in ("c", "x", "v", "a"):
            # text editing keys belong to the entry being typed in, not the sheet
            self.propagate_key_event(event)
            return True
        actions = {"o": "open", "s": "save-as" if shift else "save", "w": "close", "b": "bold",
                   "z": "redo" if shift else "undo", "y": "redo", "d": "fill-down", "r": "fill-right",
                   "equal": "sum"}
        if not in_text:
            actions.update({"c": "copy", "x": "cut", "v": "paste", "a": "select-all"})
        action = actions.get(name)
        if action and in_text and action in ("undo", "redo", "fill-down", "fill-right"):
            return True
        if action:
            if in_text and action in ("bold", "sum"):
                self.commit_from(self._active_entry(), None)
            self.activate_action(action, None)
            return True
        return False

    def _grid_key(self, _widget, event):
        if event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK):
            return False
        shift = bool(event.state & Gdk.ModifierType.SHIFT_MASK)
        key = event.keyval
        col, row = self.cursor
        moves = {Gdk.KEY_Up: (0, -1), Gdk.KEY_Down: (0, 1), Gdk.KEY_Left: (-1, 0), Gdk.KEY_Right: (1, 0),
                 Gdk.KEY_Page_Up: (0, -20), Gdk.KEY_Page_Down: (0, 20)}
        if key in moves:
            dc, dr = moves[key]
            self.select((col + dc, row + dr), extend=shift)
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.select((col, row - 1 if shift else row + 1))
            return True
        if key in (Gdk.KEY_Tab, Gdk.KEY_ISO_Left_Tab):
            self.select((col - 1 if shift or key == Gdk.KEY_ISO_Left_Tab else col + 1, row))
            return True
        if key == Gdk.KEY_Home:
            self.select((0, row), extend=shift)
            return True
        if key in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self.clear()
            return True
        if key == Gdk.KEY_F2:
            self.begin_edit()
            return True
        if key == Gdk.KEY_Escape:
            self.anchor = self.cursor
            self._selection_changed()
            return True
        char = chr(Gdk.keyval_to_unicode(key)) if Gdk.keyval_to_unicode(key) else ""
        if char and char.isprintable():
            self.begin_edit(char)
            return True
        return False

    def _entry_key(self, entry, event):
        key = event.keyval
        if key == Gdk.KEY_Escape:
            self.cancel_edit()
            return True
        if key in (Gdk.KEY_Tab, Gdk.KEY_ISO_Left_Tab):
            back = key == Gdk.KEY_ISO_Left_Tab or event.state & Gdk.ModifierType.SHIFT_MASK
            self.commit_from(entry, (-1 if back else 1, 0))
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and event.state & Gdk.ModifierType.SHIFT_MASK:
            self.commit_from(entry, (0, -1))
            return True
        if entry is self.cell_entry and key in (Gdk.KEY_Up, Gdk.KEY_Down) and not self._wants_reference():
            self.commit_from(entry, (0, -1 if key == Gdk.KEY_Up else 1))
            return True
        return False

    # --- typing in cells ----------------------------------------------------------------
    def begin_edit(self, typed=None):
        self.anchor = self.cursor
        self.editing = self.cursor
        text = self.sheet.get(*self.cursor) if typed is None else typed
        self._set_quietly(self.cell_entry, text)
        self._set_quietly(self.formula, text)
        self._place_entry()
        self.cell_entry.show()
        self.cell_entry.grab_focus_without_selecting()
        self.cell_entry.set_position(-1)
        self._selection_changed()

    def _begin_from_bar(self):
        if self.editing is None:
            self.anchor = self.cursor
            self.editing = self.cursor
            self.grid.queue_draw()
        return False

    def _place_entry(self):
        if self.editing is None or not self.cell_entry.get_visible() and self.cell_entry.get_parent() is None:
            return
        x, y, w, h = self.grid.cell_rect(*self.editing)
        text_w = len(self.cell_entry.get_text()) * 8 + 24
        self.cell_entry.set_margin_start(max(0, int(x) - 1))
        self.cell_entry.set_margin_top(max(0, int(y) - 1))
        self.cell_entry.set_size_request(max(int(w) + 2, min(text_w, 420)), int(h) + 2)

    def _cell_changed(self, entry):
        self._set_quietly(self.formula, entry.get_text())
        self._place_entry()

    def _formula_changed(self, entry):
        if self.cell_entry.get_visible():
            self._set_quietly(self.cell_entry, entry.get_text())

    @staticmethod
    def _set_quietly(entry, text):
        if entry.get_text() != text:
            entry.set_text(text)

    def _active_entry(self):
        return self.cell_entry if self.cell_entry.get_visible() else self.formula

    def _wants_reference(self):
        """Typing a formula, with the cursor just after an operator or bracket."""
        entry = self._active_entry()
        text = entry.get_text()
        if not text.startswith("="):
            return False
        if self.pointing is not None:
            return True
        before = text[:entry.get_position()].rstrip()
        return before == "=" or before[-1:] in "(,+-*/^&<>=:"

    def _insert_reference(self, replace=False):
        entry = self._active_entry()
        (a, b) = self.pointing
        c1, r1 = min(a[0], b[0]), min(a[1], b[1])
        c2, r2 = max(a[0], b[0]), max(a[1], b[1])
        ref = address(c1, r1) if (c1, r1) == (c2, r2) else f"{address(c1, r1)}:{address(c2, r2)}"
        text = entry.get_text()
        pos = entry.get_position()
        if replace and getattr(self, "_ref_span", None):
            start, end = self._ref_span
            text = text[:start] + text[end:]
            pos = start
        entry.set_text(text[:pos] + ref + text[pos:])
        self._ref_span = (pos, pos + len(ref))
        entry.set_position(pos + len(ref))
        self.grid.queue_draw()

    def commit_from(self, entry, move):
        if self.editing is None:
            self.editing = self.cursor
        col, row = self.editing
        text = entry.get_text()
        self._end_edit()
        if text != self.sheet.get(col, row):
            self.change({(col, row): (text, self.sheet.formats.get((col, row)), (col, row) in self.sheet.bold)})
        if move:
            self.select((col + move[0], row + move[1]))
        else:
            self._selection_changed()
        self.grid.grab_focus()

    def cancel_edit(self):
        self._end_edit()
        self._selection_changed()
        self.grid.grab_focus()

    def _end_edit(self):
        self.editing = None
        self.pointing = None
        self._ref_span = None
        self.cell_entry.hide()

    # --- changes and undo -----------------------------------------------------------------
    def _state(self, key):
        return (self.sheet.get(*key), self.sheet.formats.get(key), key in self.sheet.bold)

    def _apply(self, key, state):
        text, fmt, bold = state
        self.sheet.set(key[0], key[1], text)
        if fmt and fmt != "general":
            self.sheet.formats[key] = fmt
        else:
            self.sheet.formats.pop(key, None)
        if bold:
            self.sheet.bold.add(key)
        else:
            self.sheet.bold.discard(key)

    def change(self, new_states, whole=None):
        """Apply {cell: (text, format, bold)} as one step that ⌘Z takes back.
        `whole` replaces the sheet's cells entirely (rows or columns added or
        taken away), as (before, after) snapshots."""
        if whole is not None:
            self.undo_stack.append(("whole", whole[0], whole[1]))
            self._restore(whole[1])
        else:
            step = [(key, self._state(key), state) for key, state in new_states.items() if self._state(key) != state]
            if not step:
                return
            for key, _before, after in step:
                self._apply(key, after)
            self.undo_stack.append(("cells", step))
        del self.undo_stack[:-200]
        self.redo_stack.clear()
        self._mark_modified()
        self._selection_changed()

    def _snapshot(self):
        return (dict(self.sheet.cells), dict(self.sheet.formats), set(self.sheet.bold), dict(self.sheet.widths))

    def _restore(self, snap):
        cells, formats, bold, widths = snap
        self.sheet.cells, self.sheet.formats = dict(cells), dict(formats)
        self.sheet.bold, self.sheet.widths = set(bold), dict(widths)
        self.sheet._parsed, self.sheet._values = {}, {}

    def undo(self):
        self._swap(self.undo_stack, self.redo_stack, back=True)

    def redo(self):
        self._swap(self.redo_stack, self.undo_stack, back=False)

    def _swap(self, source, target, back):
        if self.editing is not None:
            self.cancel_edit()
        if not source:
            return
        step = source.pop()
        if step[0] == "whole":
            self._restore(step[1] if back else step[2])
        else:
            for key, before, after in step[1]:
                self._apply(key, before if back else after)
            first = step[1][0][0]
            self.anchor = self.cursor = first
        target.append(step)
        self._mark_modified()
        self._update_extent()
        self._selection_changed()

    def _mark_modified(self):
        self.modified = True
        self._update_title()

    # --- commands ------------------------------------------------------------------------
    def _cells_in_selection(self):
        (c1, r1), (c2, r2) = self.selection()
        return [(c, r) for r in range(r1, r2 + 1) for c in range(c1, c2 + 1)]

    def _limit_selection(self):
        (c1, r1), (c2, r2) = self.selection()
        cols, rows = self.sheet.extent()
        return (c1, r1), (min(c2, max(c1, cols - 1)), min(r2, max(r1, rows - 1)))

    def clear(self):
        (c1, r1), (c2, r2) = self._limit_selection()
        keys = [k for k in list(self.sheet.cells) + list(self.sheet.formats) + list(self.sheet.bold)
                if c1 <= k[0] <= c2 and r1 <= k[1] <= r2]
        self.change({k: ("", None, False) for k in keys})

    def set_format(self, fmt):
        (c1, r1), (c2, r2) = self._limit_selection()
        self.change({(c, r): (self.sheet.get(c, r), fmt, (c, r) in self.sheet.bold)
                     for r in range(r1, r2 + 1) for c in range(c1, c2 + 1)})

    def set_bold(self, bold):
        (c1, r1), (c2, r2) = self._limit_selection()
        self.change({(c, r): (self.sheet.get(c, r), self.sheet.formats.get((c, r)), bold)
                     for r in range(r1, r2 + 1) for c in range(c1, c2 + 1)})

    def autosum(self):
        """=SUM of the numbers just above the cell (or to its left), as on a Mac."""
        if self.editing is not None:
            self.commit_from(self._active_entry(), None)
        col, row = self.cursor
        (c1, r1), (c2, r2) = self.selection()
        if (c1, r1) != (c2, r2):
            # a block selected: sum each column into the row under it
            target = r2 + 1
            states = {(c, target): (f"=SUM({address(c, r1)}:{address(c, r2)})", None, False)
                      for c in range(c1, c2 + 1)}
            self.change(states)
            self.select((c1, target))
            return

        def numeric(c, r):
            return isinstance(self.sheet.value(c, r), float)

        r = row - 1
        while r >= 0 and numeric(col, r):
            r -= 1
        if r < row - 1:
            formula = f"=SUM({address(col, r + 1)}:{address(col, row - 1)})"
        else:
            c = col - 1
            while c >= 0 and numeric(c, row):
                c -= 1
            formula = f"=SUM({address(c + 1, row)}:{address(col - 1, row)})" if c < col - 1 else "=SUM()"
        self.begin_edit(formula)
        if formula == "=SUM()":
            self.cell_entry.set_position(len(formula) - 1)

    def copy(self, cut=False):
        (c1, r1), (c2, r2) = self._limit_selection()
        rows = []
        cells = {}
        for r in range(r1, r2 + 1):
            line = []
            for c in range(c1, c2 + 1):
                line.append(format_value(self.sheet.value(c, r), self.sheet.formats.get((c, r), "general"), SYMBOL)
                            .replace("\t", " ").replace("\n", " "))
                cells[(c - c1, r - r1)] = self._state((c, r))
            rows.append("\t".join(line))
        text = "\n".join(rows)
        app = self.get_application()
        app.clip = {"text": text, "origin": (c1, r1), "cells": cells}
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
        if cut:
            self.clear()

    def paste(self):
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        text = clipboard.wait_for_text()
        if text is None:
            return
        app = self.get_application()
        clip = getattr(app, "clip", None)
        col, row = self.selection()[0]
        states = {}
        if clip and clip["text"] == text:
            oc, orow = clip["origin"]
            for (dc, dr), (raw, fmt, bold) in clip["cells"].items():
                states[(col + dc, row + dr)] = (shift_formula(raw, col - oc, row - orow), fmt, bold)
        else:
            for dr, line in enumerate(text.rstrip("\n").split("\n")[:20000]):
                for dc, cell in enumerate(line.rstrip("\r").split("\t")[:700]):
                    key = (col + dc, row + dr)
                    states[key] = (cell, self.sheet.formats.get(key), key in self.sheet.bold)
        self.change(states)
        if states:
            last = max(states)
            self.anchor = (col, row)
            self.cursor = (max(k[0] for k in states), max(k[1] for k in states)) if last else (col, row)
            self._selection_changed()

    def fill(self, down=True):
        (c1, r1), (c2, r2) = self.selection()
        if (down and r1 == r2) or (not down and c1 == c2):
            return
        states = {}
        if down:
            for c in range(c1, c2 + 1):
                raw, fmt, bold = self._state((c, r1))
                for r in range(r1 + 1, r2 + 1):
                    states[(c, r)] = (shift_formula(raw, 0, r - r1), fmt, bold)
        else:
            for r in range(r1, r2 + 1):
                raw, fmt, bold = self._state((c1, r))
                for c in range(c1 + 1, c2 + 1):
                    states[(c, r)] = (shift_formula(raw, c - c1, 0), fmt, bold)
        self.change(states)

    def sort(self, descending):
        """Sort the rows of the selected block, or of the whole table when one
        cell is selected, by the cursor's column. A first row of headings stays."""
        if self.editing is not None:
            self.commit_from(self._active_entry(), None)
        (c1, r1), (c2, r2) = self.selection()
        cols, rows = self.sheet.extent()
        if (c1, r1) == (c2, r2) or r2 - r1 >= rows:
            # the block of rows around the cursor, up to the empty rows above and below it
            filled_rows = {r for (_c, r), text in self.sheet.cells.items() if text != ""}
            r1 = r2 = self.cursor[1]
            while r1 - 1 in filled_rows:
                r1 -= 1
            while r2 + 1 in filled_rows:
                r2 += 1
            c1, c2 = 0, max(0, cols - 1)
            first = [self.sheet.value(c, r1) for c in range(cols)]
            later = [self.sheet.value(c, r) for r in range(r1 + 1, r2 + 1) for c in range(cols)]
            if any(isinstance(v, str) for v in first) and not any(isinstance(v, float) for v in first) \
                    and any(isinstance(v, float) for v in later):
                r1 += 1
        if r2 <= r1:
            return
        key_col = self.cursor[0]

        def sort_key(r):
            v = self.sheet.value(key_col, r)
            if v is None or v == "":
                return (2, 0, "")
            if isinstance(v, float):
                return (0, v, "")
            return (1, 0, str(v).lower())

        order = list(range(r1, r2 + 1))
        filled = [r for r in order if sort_key(r)[0] < 2]
        empty = [r for r in order if sort_key(r)[0] == 2]
        filled.sort(key=sort_key, reverse=descending)
        if descending:
            nums = [r for r in filled if sort_key(r)[0] == 0]
            words = [r for r in filled if sort_key(r)[0] == 1]
            filled = nums + words
        new_order = filled + empty
        states = {}
        for target, source in zip(order, new_order):
            for c in range(c1, c2 + 1):
                raw, fmt, bold = self._state((c, source))
                states[(c, target)] = (shift_formula(raw, 0, target - source), fmt, bold)
        self.change(states)

    def insert(self, axis, after):
        """Add a row (axis 1) or column (axis 0) before or after the selection."""
        (c1, r1), (c2, r2) = self.selection()
        at = (r2 + 1 if after else r1) if axis == 1 else (c2 + 1 if after else c1)
        self._reshape(axis, at, 1)

    def delete(self, axis):
        (c1, r1), (c2, r2) = self.selection()
        if axis == 1:
            self._reshape(1, r1, -(r2 - r1 + 1))
        else:
            self._reshape(0, c1, -(c2 - c1 + 1))
        self.anchor = self.cursor = (c1, r1)
        self._selection_changed()

    def _reshape(self, axis, at, delta):
        if self.editing is not None:
            self.commit_from(self._active_entry(), None)
        before = self._snapshot()
        gone_end = at - delta if delta < 0 else at

        def move(key):
            n = key[axis]
            if n < at:
                return key
            if delta < 0 and n < gone_end:
                return None
            moved = list(key)
            moved[axis] = n + delta
            return tuple(moved)

        cells, formats, bold, widths = before
        new_cells = {}
        for key, text in cells.items():
            target = move(key)
            if target is not None:
                new_cells[target] = insert_or_delete(text, axis, at, delta)
        new_formats = {move(k): f for k, f in formats.items() if move(k) is not None}
        new_bold = {move(k) for k in bold if move(k) is not None}
        new_widths = dict(widths)
        if axis == 0:
            new_widths = {}
            for c, w in widths.items():
                target = move((c, 0))
                if target is not None:
                    new_widths[target[0]] = w
        self.change(None, whole=(before, (new_cells, new_formats, new_bold, new_widths)))
        self._update_extent()

    def show_chart(self):
        if self.editing is not None:
            self.commit_from(self._active_entry(), None)
        (c1, r1), (c2, r2) = self._limit_selection()
        labels, series = chart_data(self.sheet, c1, r1, c2, r2)
        if not series or not labels:
            alert.tell(self, "Select some numbers to chart",
                       "Select the cells with your numbers, and the words beside or above them for labels, "
                       "then click Chart.")
            return
        ChartWindow(self, labels[:60], [(n, v[:60]) for n, v in series]).show_all()

    # --- files -------------------------------------------------------------------------
    def _update_title(self):
        name = os.path.basename(self.path) if self.path else "Untitled"
        self.set_title(("• " if self.modified else "") + name)
        self.header.set_title(name)
        self.header.set_subtitle("Edited" if self.modified else None)

    def load(self, path):
        try:
            with open(path, "rb") as f:
                raw = f.read(50 * 1024 * 1024)
        except OSError as err:
            alert.tell(self, f"“{os.path.basename(path)}” couldn’t be opened.", str(err.strerror or err))
            return False
        try:
            if path.lower().endswith(".csv") or path.lower().endswith(".tsv") or not raw.lstrip().startswith(b"{"):
                try:
                    text = raw.decode("utf-8-sig")
                except UnicodeDecodeError:
                    text = raw.decode("latin-1")
                sheet = Sheet.from_csv(text)
            else:
                sheet = Sheet.from_json(json.loads(raw.decode("utf-8")))
        except (ValueError, AttributeError, TypeError):
            alert.tell(self, f"“{os.path.basename(path)}” isn’t a spreadsheet Ledger can read.",
                       "Ledger opens its own files and CSV files.")
            return False
        self.sheet = sheet
        self.path = os.path.abspath(path)
        self.modified = False
        self.undo_stack.clear()
        self.redo_stack.clear()
        self.anchor = self.cursor = (0, 0)
        Gtk.RecentManager.get_default().add_item(Gio.File.new_for_path(self.path).get_uri())
        self._update_title()
        self._update_extent()
        self._selection_changed()
        return True

    def write(self, path):
        csv_file = path.lower().endswith(".csv")
        data = self.sheet.to_csv() if csv_file else json.dumps(self.sheet.to_json(), indent=1, ensure_ascii=False)
        tmp = path + ".ledger-tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(data)
            os.replace(tmp, path)
        except OSError as err:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            alert.tell(self, f"“{os.path.basename(path)}” couldn’t be saved.", str(err.strerror or err))
            return False
        return True

    def save(self):
        if self.editing is not None:
            self.commit_from(self._active_entry(), None)
        if not self.path or self.path.lower().endswith(".csv") and not self._csv_is_enough():
            return self.save_as()
        if self.write(self.path):
            self.modified = False
            self._update_title()
            return True
        return False

    def _csv_is_enough(self):
        """A CSV file keeps only what cells show: ask before losing formulas."""
        lost = any(t.startswith("=") for t in self.sheet.cells.values()) or self.sheet.formats or self.sheet.bold
        if not lost:
            return True
        answer = alert.ask(self, "Keep this as a CSV file?",
                           "A CSV file keeps only what the cells show: formulas, formats and bold are lost. "
                           "Save as a Ledger file to keep them.",
                           [("Save as Ledger File…", Gtk.ResponseType.NO), ("Keep CSV", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.NO)
        return answer == Gtk.ResponseType.OK

    def save_as(self):
        if self.editing is not None:
            self.commit_from(self._active_entry(), None)
        stem = os.path.splitext(os.path.basename(self.path))[0] if self.path else "Untitled"
        folder = os.path.dirname(self.path) if self.path else None
        path = savesheet.ask(self, stem + ".ledger", folder)
        if not path:
            return False
        if not path.lower().endswith((".ledger", ".csv")):
            path += ".ledger"
        if self.write(path):
            self.path = os.path.abspath(path)
            self.modified = False
            self._update_title()
            return True
        return False

    def export_csv(self):
        stem = os.path.splitext(os.path.basename(self.path))[0] if self.path else "Untitled"
        path = savesheet.ask(self, stem + ".csv", os.path.dirname(self.path) if self.path else None)
        if path:
            if not path.lower().endswith(".csv"):
                path += ".csv"
            self.write(path)

    def open_dialog(self):
        dialog = Gtk.FileChooserNative.new("Open", self, Gtk.FileChooserAction.OPEN, "Open", "Cancel")
        sheets = Gtk.FileFilter()
        sheets.set_name("Spreadsheets")
        for pattern in ("*.ledger", "*.csv", "*.tsv", "*.CSV"):
            sheets.add_pattern(pattern)
        dialog.add_filter(sheets)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            path = dialog.get_filename()
            if self.path is None and not self.modified and not self.sheet.cells:
                self.load(path)
            else:
                Window(self.get_application(), path).show_all()

    def confirm_close(self):
        if self.editing is not None:
            self.commit_from(self._active_entry(), None)
        if not self.modified:
            return True
        name = os.path.basename(self.path) if self.path else "Untitled"
        answer = alert.ask(self, f"Do you want to keep the changes you made to “{name}”?",
                           "Your changes will be lost if you don’t save them.",
                           [("Save", Gtk.ResponseType.ACCEPT), ("Cancel", Gtk.ResponseType.CANCEL),
                            ("Don’t Save", Gtk.ResponseType.REJECT)],
                           default=Gtk.ResponseType.ACCEPT)
        if answer == Gtk.ResponseType.ACCEPT:
            return self.save()
        return answer == Gtk.ResponseType.REJECT


def menubar():
    return menus.menubar([
        ("_File", [
            [("New", "app.new", "<Ctrl>n"), ("Open…", "win.open", "<Ctrl>o")],
            [("Save", "win.save", "<Ctrl>s"), ("Save As…", "win.save-as", "<Ctrl><Shift>s"),
             ("Export as CSV…", "win.export-csv", None)],
            [("Close", "win.close", "<Ctrl>w")],
        ]),
        ("_Edit", [
            [("Undo", "win.undo", "<Ctrl>z"), ("Redo", "win.redo", "<Ctrl><Shift>z")],
            [("Cut", "win.cut", "<Ctrl>x"), ("Copy", "win.copy", "<Ctrl>c"), ("Paste", "win.paste", "<Ctrl>v"),
             ("Clear", "win.clear", None), ("Select All", "win.select-all", "<Ctrl>a")],
            [("Fill Down", "win.fill-down", "<Ctrl>d"), ("Fill Right", "win.fill-right", "<Ctrl>r")],
        ]),
        ("_Table", [
            [("Add Row Above", "win.row-above", None), ("Add Row Below", "win.row-below", None),
             ("Add Column Before", "win.col-left", None), ("Add Column After", "win.col-right", None)],
            [("Delete Rows", "win.delete-rows", None), ("Delete Columns", "win.delete-cols", None)],
            [("Sort A to Z", "win.sort-up", None), ("Sort Z to A", "win.sort-down", None)],
            [("Add Up (Sum)", "win.sum", "<Ctrl>equal"), ("Chart of Selected Cells", "win.chart", None)],
        ]),
        ("F_ormat", [
            [("Bold", "win.bold", "<Ctrl>b")],
            [("Automatic", "win.format-general", None), ("Number", "win.format-number", None),
             ("Currency", "win.format-currency", None), ("Percentage", "win.format-percent", None)],
        ]),
    ])


class Ledger(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)
        self.clip = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"new": lambda: Window(self).show_all(), "quit": self._quit})
        self.set_menubar(menubar())

    def _quit(self):
        for window in list(self.get_windows()):
            if isinstance(window, Window):
                window.present()
                if not window.confirm_close():
                    return
                window.destroy()
        self.quit()

    def do_activate(self):
        Window(self).show_all()

    def do_open(self, files, _n, _hint):
        for f in files:
            path = f.get_path()
            if path:
                Window(self, path).show_all()


def main():
    GLib.set_prgname("freemac-ledger")
    Ledger().run(sys.argv)


if __name__ == "__main__":
    main()
