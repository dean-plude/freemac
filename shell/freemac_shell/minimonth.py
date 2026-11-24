# SPDX-License-Identifier: GPL-3.0-or-later
"""A small month calendar: the month's name with arrows, then the days in
weeks from the region's first day (Sunday in the US, Monday in much of
the world: Dials > Language & Region). Today has a red circle; the chosen day a grey one; days
with events a dot under them. Used by the menu bar's clock and by Tide's
date picker. Original freemac code.
"""
import calendar
import datetime as dt

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

from . import region  # noqa: E402

CELL = 30
RED = (0.94, 0.26, 0.24)


def month_weeks(year, month, first_day=None):
    """Six weeks of dates that show the month, each week from the region's
    first day (first_day as datetime counts, Monday 0)."""
    start = region.start_of_week(dt.date(year, month, 1), first_day)
    return [[start + dt.timedelta(days=7 * w + d) for d in range(7)] for w in range(6)]


class MiniMonth(Gtk.Box):
    """picked(date) is called when a day is clicked; marked(first, last)
    returns the set of dates that get a dot."""

    def __init__(self, day=None, picked=None, marked=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.day = day or dt.date.today()
        self.shown = self.day.replace(day=1)
        self.picked, self.marked = picked, marked
        head = Gtk.Box(spacing=4)
        self.title = Gtk.Label(xalign=0)
        self.title.get_style_context().add_class("minimonth-title")
        head.pack_start(self.title, True, True, 4)
        for icon, step, tip in (("go-previous-symbolic", -1, "Previous Month"),
                                ("go-next-symbolic", 1, "Next Month")):
            button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.MENU)
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.set_tooltip_text(tip)
            button.connect("clicked", lambda _b, s=step: self.move(s))
            head.pack_start(button, False, False, 0)
        self.pack_start(head, False, False, 0)
        self.area = Gtk.DrawingArea()
        self.area.set_size_request(7 * CELL, 7 * CELL - 6)
        self.area.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.area.connect("draw", self._draw)
        self.area.connect("button-press-event", self._press)
        self.pack_start(self.area, False, False, 0)
        self._title()

    def move(self, months):
        index = self.shown.year * 12 + self.shown.month - 1 + months
        self.shown = dt.date(index // 12, index % 12 + 1, 1)
        self._title()
        self.area.queue_draw()

    def show_day(self, day):
        self.day = day
        self.shown = day.replace(day=1)
        self._title()
        self.area.queue_draw()

    def _title(self):
        self.title.set_markup(f"<b>{calendar.month_name[self.shown.month]}</b> {self.shown.year}")

    def _press(self, _area, event):
        if event.y < CELL - 6:
            return False
        row, col = int((event.y - (CELL - 6)) // CELL), int(event.x // CELL)
        if 0 <= row < 6 and 0 <= col < 7:
            day = month_weeks(self.shown.year, self.shown.month)[row][col]
            self.day = day
            if day.month != self.shown.month:
                self.shown = day.replace(day=1)
                self._title()
            self.area.queue_draw()
            if self.picked:
                self.picked(day)
        return True

    def _draw(self, area, cr):
        ink = area.get_style_context().get_color(Gtk.StateFlags.NORMAL)
        weeks = month_weeks(self.shown.year, self.shown.month)
        dots = self.marked(weeks[0][0], weeks[-1][-1]) if self.marked else set()
        today = dt.date.today()
        cr.select_font_face("Sans")
        cr.set_font_size(10)
        cr.set_source_rgba(ink.red, ink.green, ink.blue, 0.5)
        for col, name in enumerate(region.week_letters()):
            ext = cr.text_extents(name)
            cr.move_to(col * CELL + (CELL - ext.width) / 2 - ext.x_bearing, 14)
            cr.show_text(name)
        cr.set_font_size(12)
        for row, week in enumerate(weeks):
            for col, day in enumerate(week):
                cx, cy = col * CELL + CELL / 2, (CELL - 6) + row * CELL + CELL / 2
                if day == today:
                    cr.set_source_rgb(*RED)
                    cr.arc(cx, cy, 12, 0, 6.2832)
                    cr.fill()
                elif day == self.day:
                    cr.set_source_rgba(ink.red, ink.green, ink.blue, 0.14)
                    cr.arc(cx, cy, 12, 0, 6.2832)
                    cr.fill()
                if day == today:
                    cr.set_source_rgb(1, 1, 1)
                else:
                    cr.set_source_rgba(ink.red, ink.green, ink.blue, 1.0 if day.month == self.shown.month else 0.35)
                text = str(day.day)
                ext = cr.text_extents(text)
                cr.move_to(cx - ext.width / 2 - ext.x_bearing, cy - ext.height / 2 - ext.y_bearing)
                cr.show_text(text)
                if day in dots:
                    if day == today:
                        cr.set_source_rgb(1, 1, 1)
                    else:
                        cr.set_source_rgba(ink.red, ink.green, ink.blue, 0.45)
                    cr.arc(cx, cy + 8, 1.6, 0, 6.2832)
                    cr.fill()
        return False
