# SPDX-License-Identifier: GPL-3.0-or-later
"""Tide: a calendar kept on this computer.

Month, week and day views (⌘3, ⌘2, ⌘1), the arrows and Today in the title
bar, and ⌘N for a new event. Double-click an empty spot to add an event
there, double-click an event to change it, drag an event in the week or day
view to move it, and press Delete to remove the one chosen. Events are kept
in one .ics file (calendar_store.py) that other calendar apps can import.
Birthdays from Crew show on their days in purple; they are read from the
cards, never saved into the calendar, and double-clicking one opens the card.
The Calendars list beside the views (calendars.py) shows Home, each calendar
from an online account and Birthdays, each in its own colour: tick one to
show or hide it, right-click it for another colour, and pick an event's
calendar in its details. Original freemac code.
"""
import calendar
import datetime as dt
import math
import os
import sys
import urllib.parse

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import calendar_store as store  # noqa: E402
from . import spelling  # noqa: E402
from . import calendars, contacts_store, menus, style  # noqa: E402
from .minimonth import MiniMonth, month_weeks  # noqa: E402

APP_ID = "org.freemac.Tide"
HOUR = 48          # pixels for an hour in the week and day views
GUTTER = 58        # room for the hours on the left
DAY_HEAD = 46      # day names above the week and day views
CHIP = 19          # one line of an event in the month view and the all-day band
BLUE = (0.18, 0.48, 0.96)
RED = (0.94, 0.26, 0.24)
PURPLE = (0.62, 0.36, 0.86)
WEEKDAYS = ("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

CSS = b"""
.tide-title { font-size: 15px; font-weight: bold; }
.tide-editor entry.tide-name { font-size: 17px; font-weight: bold; border: none; box-shadow: none; background: none; }
.tide-editor .tide-label { color: alpha(currentColor, 0.6); }
.minimonth-title { font-size: 13px; }
.tide-delete { color: #e5463d; padding-left: 0; }
box.tide-sidebar { background-color: rgba(120, 120, 150, 0.08); }
list.tide-calendars { background-color: transparent; }
.tide-calendars row { padding: 3px 10px; background-color: transparent; }
.tide-calendars row:hover { background-color: rgba(120, 120, 150, 0.10); }
.tide-calendars row:selected { background-color: transparent; color: inherit; }
.tide-calendars row:selected label { color: inherit; }
.tide-calendars .tide-group { font-size: 11px; font-weight: bold; color: alpha(currentColor, 0.5); }
"""


def rounded(cr, x, y, w, h, r):
    r = max(0, min(r, w / 2, h / 2))
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def text(cr, widget, words, x, y, width, size=12, bold=False, rgba=None, align=0):
    """Draw words at x, y (top), cut with … to width; returns the height."""
    layout = PangoCairo.create_layout(cr)
    font = Pango.FontDescription(widget.get_style_context().get_font(Gtk.StateFlags.NORMAL).to_string())
    font.set_absolute_size(size * Pango.SCALE)
    font.set_weight(Pango.Weight.BOLD if bold else Pango.Weight.NORMAL)
    layout.set_font_description(font)
    layout.set_text(words, -1)
    layout.set_width(max(1, int(width)) * Pango.SCALE)
    layout.set_ellipsize(Pango.EllipsizeMode.END)
    layout.set_alignment((Pango.Alignment.LEFT, Pango.Alignment.CENTER, Pango.Alignment.RIGHT)[align])
    if rgba:
        cr.set_source_rgba(*rgba)
    cr.move_to(x, y)
    PangoCairo.show_layout(cr, layout)
    return layout.get_pixel_size()[1]


def measure(cr, widget, words, size=12):
    layout = PangoCairo.create_layout(cr)
    font = Pango.FontDescription(widget.get_style_context().get_font(Gtk.StateFlags.NORMAL).to_string())
    font.set_absolute_size(size * Pango.SCALE)
    layout.set_font_description(font)
    layout.set_text(words, -1)
    return layout.get_pixel_size()[0]


def ink_of(widget):
    c = widget.get_style_context().get_color(Gtk.StateFlags.NORMAL)
    return c.red, c.green, c.blue


def dark(widget):
    return sum(ink_of(widget)) > 1.5


def mix(hue, other, amount):
    return tuple(a + (b - a) * amount for a, b in zip(hue, other))


def words_on(hue, darkened):
    """Words in a calendar's colour that read on its own pale tint: lighter
    in Dark mode, deeper in Light."""
    return mix(hue, (1, 1, 1), 0.68) if darkened else mix(hue, (0, 0, 0), 0.5)


def all_day_colors(occ, chosen, darkened, hue=BLUE):
    """(fill rgba, words rgba) for an all-day chip in its calendar's colour."""
    fill = (*hue, 0.95 if chosen else (0.32 if darkened else 0.2))
    return fill, ((1, 1, 1, 1) if chosen else (*words_on(hue, darkened), 1))


def swatch(cr, x, y, size, hue, ticked):
    """A calendar's box in the list: filled with its colour and ticked when
    shown, an empty ring of the colour when hidden."""
    rounded(cr, x + 0.5, y + 0.5, size - 1, size - 1, 3.5)
    if ticked:
        cr.set_source_rgb(*hue)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.set_line_width(1.8)
        cr.move_to(x + size * 0.25, y + size * 0.52)
        cr.line_to(x + size * 0.43, y + size * 0.7)
        cr.line_to(x + size * 0.76, y + size * 0.3)
        cr.stroke()
    else:
        cr.set_source_rgb(*hue)
        cr.set_line_width(1.5)
        cr.stroke()


def dot_pixbuf(hue, size=12):
    import cairo
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    cr = cairo.Context(surface)
    cr.arc(size / 2, size / 2, size / 2 - 1, 0, 2 * math.pi)
    cr.set_source_rgb(*hue)
    cr.fill()
    return Gdk.pixbuf_get_from_surface(surface, 0, 0, size, size)


def birthday_events(year_from=None):
    """One all-day event a year for each card in Crew with a birthday."""
    found = []
    first = (year_from or dt.date.today().year) - 1
    for month, day, card in contacts_store.birthdays(contacts_store.load()):
        try:
            start = dt.datetime(first if (month, day) != (2, 29) else 2024, month, day)
        except ValueError:
            continue
        event = store.Event(f"{card.name}’s Birthday", start, start + dt.timedelta(days=1), True,
                            repeat="YEARLY", uid=f"birthday-{card.uid}")
        event.person = card.path
        found.append(event)
    return found


def lanes(items):
    """Side-by-side places for overlapping (start, end, item): a list of
    (item, lane, lanes in its group)."""
    items = sorted(items, key=lambda i: (i[0], -(i[1] - i[0]).total_seconds()))
    placed, group, group_end = [], [], None

    def close():
        count = max((lane for _i, lane in group), default=-1) + 1
        placed.extend((item, lane, count) for item, lane in group)

    ends = []
    for start, end, item in items:
        end = max(end, start + dt.timedelta(minutes=20))
        if group_end is not None and start >= group_end:
            close()
            group, ends, group_end = [], [], None
        lane = next((n for n, e in enumerate(ends) if e <= start), len(ends))
        if lane == len(ends):
            ends.append(end)
        else:
            ends[lane] = end
        group.append((item, lane))
        group_end = end if group_end is None else max(group_end, end)
    close()
    return placed


class MonthView(Gtk.DrawingArea):
    def __init__(self, win):
        super().__init__()
        self.win = win
        self.hits, self.cells = [], []
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)

    def _draw(self, area, cr):
        win = self.win
        width, height = area.get_allocated_width(), area.get_allocated_height()
        ink = ink_of(area)
        weeks = month_weeks(win.day.year, win.day.month)
        found = store.occurrences(win.shown(), weeks[0][0], weeks[-1][-1])
        by_day = {}
        for occ in found:
            for day in occ.days():
                by_day.setdefault(day, []).append(occ)
        top = 26
        cw, ch = width / 7, (height - top) / 6
        for col, name in enumerate(WEEKDAYS):
            text(cr, area, name, col * cw, 6, cw - 8, 12, rgba=(*ink, 0.6), align=2)
        today = dt.date.today()
        self.hits, self.cells = [], []
        for row, week in enumerate(weeks):
            for col, day in enumerate(week):
                x, y = col * cw, top + row * ch
                self.cells.append((x, y, cw, ch, day))
                if col in (0, 6):
                    cr.set_source_rgba(*ink, 0.025)
                    cr.rectangle(x, y, cw, ch)
                    cr.fill()
                if day == win.day:
                    cr.set_source_rgba(*BLUE, 0.08)
                    cr.rectangle(x, y, cw, ch)
                    cr.fill()
                faint = day.month != win.day.month
                label = f"{calendar.month_abbr[day.month]} {day.day}" if day.day == 1 else str(day.day)
                if day == today:
                    cr.set_source_rgb(*RED)
                    tw = max(22, 8 * len(label) + 8)
                    rounded(cr, x + cw - tw - 4, y + 3, tw, 20, 10)
                    cr.fill()
                    text(cr, area, label, x + cw - tw - 4, y + 5, tw, 12, bold=True, rgba=(1, 1, 1, 1), align=1)
                else:
                    text(cr, area, label, x, y + 5, cw - 10, 12, bold=day.day == 1,
                         rgba=(*ink, 0.35 if faint else 0.9), align=2)
                room = int((ch - 28) // CHIP)
                items = by_day.get(day, [])
                for n, occ in enumerate(items):
                    if n >= room - 1 and len(items) > room:
                        text(cr, area, f"{len(items) - n} more", x + 8, y + 26 + n * CHIP, cw - 12, 11,
                             rgba=(*ink, 0.55))
                        break
                    self._chip(cr, area, occ, x + 3, y + 26 + n * CHIP, cw - 6, ink, day)
        cr.set_source_rgba(*ink, 0.12)
        cr.set_line_width(1)
        for row in range(7):
            cr.move_to(0, top + row * ch + 0.5)
            cr.line_to(width, top + row * ch + 0.5)
        for col in range(1, 7):
            cr.move_to(col * cw + 0.5, top)
            cr.line_to(col * cw + 0.5, height)
        cr.stroke()
        return False

    def _chip(self, cr, area, occ, x, y, w, ink, day):
        chosen = self.win.selected == occ.event.uid
        h = CHIP - 2
        if occ.all_day:
            fill, colour = all_day_colors(occ, chosen, dark(area), self.win.hue(occ.event))
            cr.set_source_rgba(*fill)
            rounded(cr, x, y, w, h, 4)
            cr.fill()
            text(cr, area, occ.event.title, x + 6, y + 1, w - 10, 12, rgba=colour)
        else:
            hue = self.win.hue(occ.event)
            if chosen:
                cr.set_source_rgba(*hue, 0.95)
                rounded(cr, x, y, w, h, 4)
                cr.fill()
            cr.set_source_rgba(*((1, 1, 1) if chosen else hue), 1)
            cr.arc(x + 7, y + h / 2, 3.5, 0, 2 * math.pi)
            cr.fill()
            fore = (1, 1, 1, 1) if chosen else (*ink, 0.9)
            when = store.time_text(occ.start) if occ.start.date() == day else ""
            tw = measure(cr, area, when, 11) + 4 if when else 0
            text(cr, area, occ.event.title, x + 15, y + 1, w - 18 - tw, 12, rgba=fore)
            if when:
                text(cr, area, when, x + w - tw - 4, y + 1, tw, 11,
                     rgba=(1, 1, 1, 0.85) if chosen else (*ink, 0.5), align=2)
        self.hits.append((x, y, w, h, occ))

    def _press(self, _area, event):
        win = self.win
        for x, y, w, h, occ in self.hits:
            if x <= event.x <= x + w and y <= event.y <= y + h:
                win.choose(occ.event.uid)
                if event.type == Gdk.EventType._2BUTTON_PRESS:
                    win.edit(occ.event, self, (int(x), int(y), int(w), int(h)))
                return True
        for x, y, w, h, day in self.cells:
            if x <= event.x <= x + w and y <= event.y <= y + h:
                win.choose(None)
                win.go_to(day)
                if event.type == Gdk.EventType._2BUTTON_PRESS:
                    start = dt.datetime.combine(day, dt.time())
                    win.add_event(start, start + dt.timedelta(days=1), all_day=True)
                return True
        return False


class DayHeader(Gtk.DrawingArea):
    """Day names above the week or day view, and the all-day events under them."""

    def __init__(self, win, grid):
        super().__init__()
        self.win, self.grid = win, grid
        self.hits = []
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)

    def update(self):
        days = self.grid.days()
        found = [o for o in store.occurrences(self.win.shown(), days[0], days[-1]) if o.all_day]
        most = max((sum(1 for o in found if d in set(o.days())) for d in days), default=0)
        self.set_size_request(-1, DAY_HEAD + max(1, most) * CHIP + 6)
        self.queue_draw()

    def _draw(self, area, cr):
        win, days = self.win, self.grid.days()
        width = area.get_allocated_width()
        ink = ink_of(area)
        cw = (width - GUTTER) / len(days)
        today = dt.date.today()
        self.hits = []
        found = [o for o in store.occurrences(win.shown(), days[0], days[-1]) if o.all_day]
        text(cr, area, "all-day", 0, DAY_HEAD + 2, GUTTER - 8, 10, rgba=(*ink, 0.5), align=2)
        for col, day in enumerate(days):
            x = GUTTER + col * cw
            name = f"{WEEKDAYS[(day.weekday() + 1) % 7]}" if len(days) > 1 else day.strftime("%A")
            number = str(day.day)
            if day == today:
                cr.set_source_rgb(*RED)
                rounded(cr, x + cw / 2 + 2, 10, 28, 26, 13)
                cr.fill()
                text(cr, area, name, x, 14, cw / 2 - 2, 14, rgba=(*ink, 0.75), align=2)
                text(cr, area, number, x + cw / 2 + 2, 13, 28, 15, bold=True, rgba=(1, 1, 1, 1), align=1)
            else:
                text(cr, area, f"{name} {number}", x, 13, cw, 15 if len(days) > 1 else 16,
                     bold=day == win.day and len(days) > 1, rgba=(*ink, 0.85), align=1)
            row = 0
            for occ in found:
                if day not in set(occ.days()):
                    continue
                y = DAY_HEAD + row * CHIP
                chosen = win.selected == occ.event.uid
                fill, colour = all_day_colors(occ, chosen, dark(area), win.hue(occ.event))
                cr.set_source_rgba(*fill)
                rounded(cr, x + 2, y, cw - 4, CHIP - 2, 4)
                cr.fill()
                text(cr, area, occ.event.title, x + 8, y + 1, cw - 14, 12, rgba=colour)
                self.hits.append((x + 2, y, cw - 4, CHIP - 2, occ))
                row += 1
        height = area.get_allocated_height()
        cr.set_source_rgba(*ink, 0.12)
        cr.set_line_width(1)
        cr.move_to(GUTTER, height - 0.5)
        cr.line_to(width, height - 0.5)
        for col in range(len(days)):
            cr.move_to(GUTTER + col * cw + 0.5, DAY_HEAD - 4)
            cr.line_to(GUTTER + col * cw + 0.5, height)
        cr.stroke()
        return False

    def _press(self, _area, event):
        win = self.win
        for x, y, w, h, occ in self.hits:
            if x <= event.x <= x + w and y <= event.y <= y + h:
                win.choose(occ.event.uid)
                if event.type == Gdk.EventType._2BUTTON_PRESS:
                    win.edit(occ.event, self, (int(x), int(y), int(w), int(h)))
                return True
        days = self.grid.days()
        cw = (self.get_allocated_width() - GUTTER) / len(days)
        col = int((event.x - GUTTER) // cw)
        if event.x >= GUTTER and 0 <= col < len(days):
            win.choose(None)
            win.go_to(days[col], keep_view=True)
            if event.type == Gdk.EventType._2BUTTON_PRESS:
                start = dt.datetime.combine(days[col], dt.time())
                win.add_event(start, start + dt.timedelta(days=1), all_day=True)
        return True


class TimeGrid(Gtk.DrawingArea):
    """The hours of one day (day view) or seven (week view), with timed events."""

    def __init__(self, win, count):
        super().__init__()
        self.win, self.count = win, count
        self.hits = []
        self.drag = None
        self.set_size_request(-1, 24 * HOUR + 12)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)

    def days(self):
        if self.count == 1:
            return [self.win.day]
        sunday = self.win.day - dt.timedelta(days=(self.win.day.weekday() + 1) % 7)
        return [sunday + dt.timedelta(days=n) for n in range(7)]

    def y_of(self, when):
        return 6 + (when.hour + when.minute / 60) * HOUR

    def _draw(self, area, cr):
        win, days = self.win, self.days()
        width = area.get_allocated_width()
        ink = ink_of(area)
        cw = (width - GUTTER) / len(days)
        cr.set_line_width(1)
        now = dt.datetime.now()
        now_y = self.y_of(now) if dt.date.today() in days else -100
        for hour in range(25):
            y = 6 + hour * HOUR
            if 0 < hour < 24 and abs(y - now_y) > 10:
                label = store.time_text(dt.datetime(2000, 1, 1, hour))
                text(cr, area, label, 0, y - 7, GUTTER - 10, 10, rgba=(*ink, 0.5), align=2)
            cr.set_source_rgba(*ink, 0.11)
            cr.move_to(GUTTER - 4, int(y) + 0.5)
            cr.line_to(width, int(y) + 0.5)
            cr.stroke()
        for col in range(len(days) + 1):
            cr.move_to(GUTTER + col * cw + 0.5, 6)
            cr.line_to(GUTTER + col * cw + 0.5, 6 + 24 * HOUR)
        cr.stroke()
        today = dt.date.today()
        if today in days and len(days) > 1:
            col = days.index(today)
            cr.set_source_rgba(*BLUE, 0.04)
            cr.rectangle(GUTTER + col * cw, 6, cw, 24 * HOUR)
            cr.fill()
        self.hits = []
        found = [o for o in store.occurrences(win.shown(), days[0], days[-1]) if not o.all_day]
        moving = self.drag["occ"] if self.drag and self.drag.get("moved") else None
        for col, day in enumerate(days):
            start_of_day = dt.datetime.combine(day, dt.time())
            end_of_day = start_of_day + dt.timedelta(days=1)
            pieces = []
            for occ in found:
                start, end = occ.start, occ.end
                if moving is occ:
                    start, end = self.drag["start"], self.drag["start"] + (occ.end - occ.start)
                if end <= start_of_day or start >= end_of_day:
                    if not (start == end and start_of_day <= start < end_of_day):
                        continue
                pieces.append((max(start, start_of_day), min(end, end_of_day), (occ, start)))
            for (occ, start), lane, count in lanes(pieces):
                s = max(start, start_of_day)
                e = min(start + (occ.end - occ.start), end_of_day)
                y0, y1 = self.y_of(s), max(self.y_of(s) + 20, self.y_of(e) if e < end_of_day else 6 + 24 * HOUR)
                lane_w = (cw - 6) / count
                x = GUTTER + col * cw + 2 + lane * lane_w
                self._block(cr, area, occ, start, x, y0 + 1, lane_w - 2, y1 - y0 - 2, ink)
        if today in days:
            col = days.index(today)
            now = dt.datetime.now()
            y = self.y_of(now)
            cr.set_source_rgb(*RED)
            cr.set_line_width(1.5)
            cr.move_to(GUTTER + col * cw, y)
            cr.line_to(GUTTER + (col + 1) * cw, y)
            cr.stroke()
            cr.arc(GUTTER + col * cw, y, 4, 0, 2 * math.pi)
            cr.fill()
            text(cr, area, store.time_text(now), 0, y - 7, GUTTER - 10, 10, bold=True, rgba=(*RED, 1), align=2)
        return False

    def _block(self, cr, area, occ, start, x, y, w, h, ink):
        chosen = self.win.selected == occ.event.uid
        hue = self.win.hue(occ.event)
        cr.set_source_rgba(*hue, 0.92 if chosen else (0.34 if dark(area) else 0.18))
        rounded(cr, x, y, w, h, 5)
        cr.fill()
        cr.set_source_rgba(*hue, 1)
        rounded(cr, x, y, 3.5, h, 1.5)
        cr.fill()
        if chosen:
            fore, soft = (1, 1, 1, 1), (1, 1, 1, 0.85)
        else:
            deep = words_on(hue, dark(area))
            fore, soft = (*deep, 1), (*deep, 0.75)
        used = text(cr, area, occ.event.title, x + 8, y + 3, w - 12, 12, bold=True, rgba=fore)
        if h > 34:
            when = store.time_text(start)
            if occ.event.location:
                when += "  " + occ.event.location
            text(cr, area, when, x + 8, y + 3 + used, w - 12, 11, rgba=soft)
        self.hits.append((x, y, w, h, occ))

    def _hit(self, event):
        for x, y, w, h, occ in reversed(self.hits):
            if x <= event.x <= x + w and y <= event.y <= y + h:
                return (x, y, w, h), occ
        return None, None

    def _at(self, event):
        """(date, datetime) under the pointer, to the quarter hour."""
        days = self.days()
        cw = (self.get_allocated_width() - GUTTER) / len(days)
        col = min(max(int((event.x - GUTTER) // cw), 0), len(days) - 1)
        minutes = int(round((event.y - 6) / HOUR * 60 / 15) * 15)
        minutes = min(max(minutes, 0), 24 * 60 - 15)
        day = days[col]
        return day, dt.datetime.combine(day, dt.time()) + dt.timedelta(minutes=minutes)

    def _press(self, _area, event):
        if event.button != 1:
            return False
        win = self.win
        rect, occ = self._hit(event)
        if occ is not None:
            win.choose(occ.event.uid)
            if event.type == Gdk.EventType._2BUTTON_PRESS:
                self.drag = None
                win.edit(occ.event, self, tuple(int(v) for v in rect))
            else:
                self.drag = {"occ": occ, "x": event.x, "y": event.y, "start": occ.start, "moved": False}
            return True
        win.choose(None)
        day, when = self._at(event)
        win.go_to(day, keep_view=True)
        if event.type == Gdk.EventType._2BUTTON_PRESS:
            minutes = when.minute - when.minute % 30
            start = when.replace(minute=minutes)
            win.add_event(start, start + dt.timedelta(hours=1))
        return True

    def _motion(self, _area, event):
        drag = self.drag
        if not drag or not event.state & Gdk.ModifierType.BUTTON1_MASK:
            return False
        if not drag["moved"] and abs(event.y - drag["y"]) < 4 and abs(event.x - drag["x"]) < 4:
            return True
        drag["moved"] = True
        days = self.days()
        cw = (self.get_allocated_width() - GUTTER) / len(days)
        day_shift = int((event.x - GUTTER) // cw) - int((drag["x"] - GUTTER) // cw) if len(days) > 1 else 0
        minutes = round((event.y - drag["y"]) / HOUR * 60 / 15) * 15
        drag["start"] = drag["occ"].start + dt.timedelta(days=day_shift, minutes=minutes)
        self.queue_draw()
        return True

    def _release(self, _area, _event):
        drag, self.drag = self.drag, None
        if drag and drag["moved"]:
            shift = drag["start"] - drag["occ"].start
            if shift:
                self.win.move_event(drag["occ"].event, shift)
            self.queue_draw()
        return False


class DateButton(Gtk.MenuButton):
    """A date that opens a small month to choose another."""

    def __init__(self, day, changed):
        super().__init__()
        self.day, self.changed = day, changed
        self.label = Gtk.Label()
        self.add(self.label)
        pop = Gtk.Popover()
        self.month = MiniMonth(day, picked=self._picked)
        self.month.set_margin_start(8)
        self.month.set_margin_end(8)
        self.month.set_margin_top(6)
        self.month.set_margin_bottom(8)
        self.month.show_all()
        pop.add(self.month)
        self.set_popover(pop)
        self._label()

    def set_day(self, day):
        self.day = day
        self.month.show_day(day)
        self._label()

    def _picked(self, day):
        self.day = day
        self._label()
        self.get_popover().popdown()
        self.changed(day)

    def _label(self):
        self.label.set_text(f"{calendar.month_abbr[self.day.month]} {self.day.day}, {self.day.year}")


class Editor(Gtk.Popover):
    """The details of one event, changed in place; saved when it closes."""

    def __init__(self, win, event, widget, rect):
        super().__init__(relative_to=widget, position=Gtk.PositionType.RIGHT)
        self.set_pointing_to(self._rect(rect))
        self.win, self.event = win, event
        self.get_style_context().add_class("tide-editor")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=14)
        box.set_size_request(320, -1)
        self.name = Gtk.Entry(text=event.title, placeholder_text="New Event")
        self.name.get_style_context().add_class("tide-name")
        self.name.connect("activate", lambda *_: self.popdown())
        box.pack_start(self.name, False, False, 0)
        self.place = Gtk.Entry(text=event.location, placeholder_text="Add Location")
        box.pack_start(self.place, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 2)

        grid = Gtk.Grid(column_spacing=8, row_spacing=6)
        self.all_day = Gtk.CheckButton(label="All-day", active=event.all_day)
        self.all_day.connect("toggled", lambda *_: self._times())
        grid.attach(self._label("all-day:"), 0, 0, 1, 1)
        grid.attach(self.all_day, 1, 0, 2, 1)
        last = (event.end - dt.timedelta(days=1)).date() if event.all_day else event.end.date()
        self.first_day = event.start.date()
        self.start_day = DateButton(event.start.date(), self._start_moved)
        self.end_day = DateButton(max(last, event.start.date()), lambda _d: None)
        self.start_time = Gtk.Entry(text=store.time_text(event.start), width_chars=8)
        self.end_time = Gtk.Entry(text=store.time_text(event.end), width_chars=8)
        for entry in (self.start_time, self.end_time):
            entry.connect("focus-out-event", self._tidy)
            entry.connect("activate", lambda *_: self.popdown())
        grid.attach(self._label("starts:"), 0, 1, 1, 1)
        grid.attach(self.start_day, 1, 1, 1, 1)
        grid.attach(self.start_time, 2, 1, 1, 1)
        grid.attach(self._label("ends:"), 0, 2, 1, 1)
        grid.attach(self.end_day, 1, 2, 1, 1)
        grid.attach(self.end_time, 2, 2, 1, 1)
        self.repeat = Gtk.ComboBoxText()
        for key, label in store.REPEATS.items():
            self.repeat.append(key, label)
        self.repeat.set_active_id(event.repeat or "")
        grid.attach(self._label("repeat:"), 0, 3, 1, 1)
        grid.attach(self.repeat, 1, 3, 2, 1)
        self.alert = Gtk.ComboBoxText()
        for minutes, label in store.ALERTS.items():
            self.alert.append("" if minutes is None else str(minutes), label)
        if event.alert is not None and event.alert not in store.ALERTS:
            self.alert.append(str(event.alert), f"{event.alert} minutes before")
        self.alert.set_active_id("" if event.alert is None else str(event.alert))
        grid.attach(self._label("alert:"), 0, 4, 1, 1)
        grid.attach(self.alert, 1, 4, 2, 1)
        self.calendar = None
        choices = [c for c in win.calendars if c.editable]
        if len(choices) > 1:
            model = Gtk.ListStore(str, str, GdkPixbuf.Pixbuf)
            for cal in choices:
                model.append([cal.key, cal.name if cal.group == "On My Computer" else f"{cal.name} ({cal.group})",
                              dot_pixbuf(cal.rgb)])
            self.calendar = Gtk.ComboBox(model=model, id_column=0)
            dot = Gtk.CellRendererPixbuf()
            self.calendar.pack_start(dot, False)
            self.calendar.add_attribute(dot, "pixbuf", 2)
            words = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.END, max_width_chars=26)
            self.calendar.pack_start(words, True)
            self.calendar.add_attribute(words, "text", 1)
            self.calendar.set_active_id(calendars.key_of(event))
            grid.attach(self._label("calendar:"), 0, 5, 1, 1)
            grid.attach(self.calendar, 1, 5, 2, 1)
        box.pack_start(grid, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 2)

        self.notes = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=4, left_margin=4)
        spelling.attach(self.notes)
        self.notes.get_buffer().set_text(event.notes)
        frame = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, min_content_height=60)
        frame.set_shadow_type(Gtk.ShadowType.IN)
        frame.add(self.notes)
        box.pack_start(self._label("notes:", 0), False, False, 0)
        box.pack_start(frame, False, False, 0)
        delete = Gtk.Button(label="Delete Event")
        delete.set_relief(Gtk.ReliefStyle.NONE)
        delete.get_style_context().add_class("tide-delete")
        delete.connect("clicked", lambda *_: self._delete())
        delete.set_halign(Gtk.Align.START)
        box.pack_start(delete, False, False, 4)
        self.add(box)
        self.deleted = False
        self.connect("closed", lambda *_: self._closed())
        box.show_all()
        self._times()

    @staticmethod
    def _rect(rect):
        r = Gdk.Rectangle()
        r.x, r.y, r.width, r.height = rect
        return r

    def _label(self, words, xalign=1):
        label = Gtk.Label(label=words, xalign=xalign)
        label.get_style_context().add_class("tide-label")
        return label

    def _times(self):
        timed = not self.all_day.get_active()
        self.start_time.set_visible(timed)
        self.end_time.set_visible(timed)

    def _start_moved(self, day):
        """Moving the first day moves the last day with it."""
        self.end_day.set_day(max(self.end_day.day + (day - self.first_day), day))
        self.first_day = day

    def _tidy(self, entry, _event):
        found = store.parse_time(entry.get_text())
        if found:
            entry.set_text(store.time_text(dt.datetime(2000, 1, 1, *found)))
        return False

    def _delete(self):
        self.deleted = True
        self.popdown()
        self.win.delete_event(self.event)

    def _closed(self):
        if self.deleted:
            return
        e = self.event.copy()
        e.title = self.name.get_text().strip() or "New Event"
        e.location = self.place.get_text().strip()
        buffer = self.notes.get_buffer()
        e.notes = buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False).strip()
        e.repeat = self.repeat.get_active_id() or ""
        alert = self.alert.get_active_id()
        e.alert = int(alert) if alert else None
        e.all_day = self.all_day.get_active()
        if self.calendar is not None:
            key = self.calendar.get_active_id()
            if key is not None and key != calendars.key_of(e):
                calendars.move(e, key)
        first, last = self.start_day.day, max(self.end_day.day, self.start_day.day)
        if e.all_day:
            e.start = dt.datetime.combine(first, dt.time())
            e.end = dt.datetime.combine(last + dt.timedelta(days=1), dt.time())
        else:
            begin = store.parse_time(self.start_time.get_text()) or (self.event.start.hour, self.event.start.minute)
            finish = store.parse_time(self.end_time.get_text())
            e.start = dt.datetime.combine(first, dt.time(*begin))
            if finish is None:
                e.end = e.start + (self.event.end - self.event.start if not self.event.all_day
                                   else dt.timedelta(hours=1))
            else:
                e.end = dt.datetime.combine(last, dt.time(*finish))
            if e.end < e.start:
                e.end = e.start + dt.timedelta(hours=1)
        self.win.replace_event(e)
        GLib.idle_add(self.destroy)


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Tide")
        self.set_default_size(980, 660)
        self.set_icon_name("freemac-tide")
        self.events = store.load()
        self.birthdays = birthday_events()
        self.saved = [e.copy() for e in self.events]   # as last written, for Undo
        self.undos, self.redos = [], []
        self.day = dt.date.today()
        self.view = "month"
        self.selected = None
        self.editor = None
        self.written = 0
        self.load_calendars()

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        nav = Gtk.Box()
        nav.get_style_context().add_class("linked")
        for icon, step, tip in (("go-previous-symbolic", -1, "Previous (⌘←)"),
                                ("go-next-symbolic", 1, "Next (⌘→)")):
            button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
            button.set_tooltip_text(tip)
            button.connect("clicked", lambda _b, s=step: self.step(s))
            nav.pack_start(button, False, False, 0)
            if step == -1:
                today = Gtk.Button(label="Today")
                today.set_tooltip_text("Go to Today (⌘T)")
                today.connect("clicked", lambda *_: self.today())
                nav.pack_start(today, False, False, 0)
        self.list_button = Gtk.ToggleButton(label="Calendars")
        self.list_button.set_tooltip_text("Show or hide the calendar list (⌥⌘S)")
        header.pack_start(self.list_button)
        header.pack_start(nav)
        self.heading = Gtk.Label()
        self.heading.get_style_context().add_class("tide-title")
        header.set_custom_title(self.heading)
        add = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        add.set_tooltip_text("New Event (⌘N)")
        add.connect("clicked", lambda *_: self.new_event())
        header.pack_end(add)
        views = Gtk.Box()
        views.get_style_context().add_class("linked")
        self.view_buttons = {}
        for name, label, keys in (("day", "Day", "⌘1"), ("week", "Week", "⌘2"), ("month", "Month", "⌘3")):
            button = Gtk.ToggleButton(label=label)
            button.set_tooltip_text(f"{label} ({keys})")
            button.connect("toggled", lambda b, n=name: b.get_active() and self.show_view(n))
            views.pack_start(button, False, False, 0)
            self.view_buttons[name] = button
        header.pack_end(views)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        self.month = MonthView(self)
        self.stack.add_named(self.month, "month")
        self.grids, self.headers, self.scrolls = {}, {}, {}
        for name, count in (("week", 7), ("day", 1)):
            grid = TimeGrid(self, count)
            head = DayHeader(self, grid)
            scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
            scroll.add(grid)
            page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            page.pack_start(head, False, False, 0)
            page.pack_start(scroll, True, True, 0)
            self.stack.add_named(page, name)
            self.grids[name], self.headers[name], self.scrolls[name] = grid, head, scroll
        body = Gtk.Box()
        self.side = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_RIGHT,
                                 transition_duration=150)
        self.side.add(self._sidebar())
        body.pack_start(self.side, False, False, 0)
        body.pack_start(self.stack, True, True, 0)
        self.add(body)
        showing = self.settings.get("sidebar", True)
        self.side.set_reveal_child(showing)
        self.list_button.set_active(showing)
        self.list_button.connect("toggled", lambda b: self.show_list(b.get_active()))
        self.list_action = menus.add_toggle(self, "calendar-list", showing, self.show_list)

        menus.add_actions(self, {
            "new-event": self.new_event, "delete-event": self.delete_chosen,
            "undo": self.undo, "redo": lambda: self.undo(redo=True),
            "today": self.today, "previous": lambda: self.step(-1), "next": lambda: self.step(1),
            "view-day": lambda: self.show_view("day"), "view-week": lambda: self.show_view("week"),
            "view-month": lambda: self.show_view("month"), "close": self.close,
        })
        self.connect("key-press-event", self._key)
        os.makedirs(os.path.dirname(store.store_path()), exist_ok=True)
        self.monitor = Gio.File.new_for_path(store.store_path()).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", self._file_changed)
        os.makedirs(contacts_store.store_dir(), exist_ok=True)
        self.cards_monitor = Gio.File.new_for_path(contacts_store.store_dir()).monitor_directory(
            Gio.FileMonitorFlags.NONE, None)
        self.cards_monitor.connect("changed", self._cards_changed)
        GLib.timeout_add_seconds(60, self._tick)
        self.connect("focus-in-event", lambda *_: self._calendars_changed())
        header.show_all()
        body.show_all()
        self.show_view("month")

    # -- calendars ---------------------------------------------------------------
    def load_calendars(self):
        self.settings = calendars.load_settings()
        self.calendars = calendars.calendars(self.settings)
        self.hidden = calendars.hidden(self.settings)
        self.colors = {c.key: c.rgb for c in self.calendars}

    def hue(self, event):
        return self.colors.get(calendars.key_of(event), BLUE)

    def _sidebar(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.get_style_context().add_class("tide-sidebar")
        box.set_size_request(200, -1)
        self.cal_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, activate_on_single_click=True)
        self.cal_list.get_style_context().add_class("tide-calendars")
        self.cal_list.connect("row-activated", lambda _l, row: self._toggle(row))
        self.cal_list.connect("button-press-event", self._list_button)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.cal_list)
        box.pack_start(scroll, True, True, 6)
        self.mini = MiniMonth(self.day, picked=lambda d: self.go_to(d), marked=self._marked)
        self.mini.set_margin_start(10)
        self.mini.set_margin_end(10)
        self.mini.set_margin_bottom(12)
        box.pack_end(self.mini, False, False, 0)
        self._fill_list()
        return box

    def _marked(self, first, last):
        return {d for o in store.occurrences(self.shown(), first, last) for d in o.days()}

    def _fill_list(self):
        for row in self.cal_list.get_children():
            self.cal_list.remove(row)
        group = None
        for cal in self.calendars:
            if cal.group != group:
                group = cal.group
                head = Gtk.ListBoxRow(activatable=False, selectable=False)
                head.calendar = None
                label = Gtk.Label(label=group, xalign=0)
                label.get_style_context().add_class("tide-group")
                label.set_margin_top(6 if head is not None and self.cal_list.get_children() else 0)
                head.add(label)
                self.cal_list.add(head)
            row = Gtk.ListBoxRow()
            row.calendar = cal
            line = Gtk.Box(spacing=8)
            mark = Gtk.DrawingArea()
            mark.set_size_request(14, 14)
            mark.set_valign(Gtk.Align.CENTER)
            mark.connect("draw", lambda _a, cr, c=cal: swatch(cr, 0, 0, 14, c.rgb, c.key not in self.hidden))
            line.pack_start(mark, False, False, 0)
            line.pack_start(Gtk.Label(label=cal.name, xalign=0, ellipsize=Pango.EllipsizeMode.END), True, True, 0)
            row.add(line)
            self.cal_list.add(row)
        self.cal_list.show_all()

    def _toggle(self, row):
        cal = getattr(row, "calendar", None)
        if cal is not None:
            self.set_shown(cal.key, cal.key in self.hidden)

    def set_shown(self, key, shown):
        calendars.set_shown(key, shown)
        self.load_calendars()
        if not shown and self.selected and any(
                e.uid == self.selected and calendars.key_of(e) == key for e in self.shown_all()):
            self.selected = None
        self.cal_list.queue_draw()
        self.refresh()

    def _list_button(self, _list, event):
        if event.button != 3:
            return False
        row = self.cal_list.get_row_at_y(int(event.y))
        cal = getattr(row, "calendar", None) if row else None
        if cal is None:
            return False
        menu = Gtk.Menu()
        item = Gtk.MenuItem(label=f"Hide “{cal.name}”" if cal.key not in self.hidden else f"Show “{cal.name}”")
        item.connect("activate", lambda *_: self._toggle(row))
        menu.append(item)
        menu.append(Gtk.SeparatorMenuItem())
        for name, hexcode in calendars.COLORS.items():
            item = Gtk.CheckMenuItem(draw_as_radio=True, active=cal.color.lower() == hexcode)
            line = Gtk.Box(spacing=8)
            line.pack_start(Gtk.Image.new_from_pixbuf(dot_pixbuf(calendars.rgb(hexcode))), False, False, 0)
            line.pack_start(Gtk.Label(label=name.capitalize(), xalign=0), True, True, 0)
            item.add(line)
            item.connect("activate", lambda i, h=hexcode: i.get_active() and self.set_color(cal.key, h))
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self.cal_list, None)
        menu.popup_at_pointer(event)
        return True

    def set_color(self, key, hexcode):
        calendars.set_color(key, hexcode)
        self.load_calendars()
        self._fill_list()
        self.refresh()

    def show_list(self, showing):
        self.side.set_reveal_child(showing)
        if self.list_button.get_active() != showing:
            self.list_button.set_active(showing)
        if self.list_action.get_state().get_boolean() != showing:
            self.list_action.set_state(GLib.Variant("b", showing))
        if self.settings.get("sidebar", True) != showing:
            settings = calendars.load_settings()
            settings["sidebar"] = showing
            calendars.save_settings(settings)
            self.settings = settings

    def _calendars_changed(self):
        """An account came or went, or synced a new calendar: list it."""
        before = [(c.key, c.name, c.color, c.group) for c in self.calendars]
        self.load_calendars()
        if [(c.key, c.name, c.color, c.group) for c in self.calendars] != before:
            self._fill_list()
            self.refresh()
        return False

    # -- moving around ----------------------------------------------------------
    def show_view(self, name):
        self.view = name
        for key, button in self.view_buttons.items():
            if button.get_active() != (key == name):
                button.set_active(key == name)
        self.stack.set_visible_child_name(name)
        if name in self.scrolls:
            GLib.idle_add(self._scroll_to_morning, name)
        self.refresh()

    def _scroll_to_morning(self, name):
        adj = self.scrolls[name].get_vadjustment()
        if adj.get_upper() < 24 * HOUR or adj.get_page_size() <= 1:
            GLib.timeout_add(40, self._scroll_to_morning, name)   # not laid out yet
            return False
        now = dt.datetime.now()
        hours = adj.get_page_size() / HOUR
        hour = 7.5   # the working day, like a paper diary opened in the morning
        grid = self.grids[name]
        if dt.date.today() in grid.days():
            at = now.hour + now.minute / 60
            if not hour + 0.5 <= at <= hour + hours - 1:
                hour = max(at - hours / 3, 0)
        adj.set_value(min(hour * HOUR, adj.get_upper() - adj.get_page_size()))
        return False

    def go_to(self, day, keep_view=True):
        self.day = day
        self.refresh()

    def step(self, direction):
        if self.view == "month":
            index = self.day.year * 12 + self.day.month - 1 + direction
            year, month = index // 12, index % 12 + 1
            self.day = dt.date(year, month, min(self.day.day, calendar.monthrange(year, month)[1]))
        else:
            self.day += dt.timedelta(days=direction * (7 if self.view == "week" else 1))
        self.refresh()

    def today(self):
        self.day = dt.date.today()
        self.refresh()
        if self.view in self.scrolls:
            GLib.idle_add(self._scroll_to_morning, self.view)

    def refresh(self):
        day = self.day
        if self.view == "day":
            words = f"{day:%A}, {calendar.month_name[day.month]} {day.day}, {day.year}"
        elif self.view == "week":
            days = self.grids["week"].days()
            first, last = days[0], days[-1]
            if first.month == last.month:
                words = f"{calendar.month_name[first.month]} {first.year}"
            elif first.year == last.year:
                words = f"{calendar.month_abbr[first.month]} – {calendar.month_abbr[last.month]} {last.year}"
            else:
                words = f"{calendar.month_abbr[first.month]} {first.year} – {calendar.month_abbr[last.month]} {last.year}"
        else:
            words = f"{calendar.month_name[day.month]} {day.year}"
        self.heading.set_text(words)
        self.set_title(words)
        if hasattr(self, "mini"):
            self.mini.show_day(day)
        for head in self.headers.values():
            head.update()
        for grid in self.grids.values():
            grid.queue_draw()
        self.month.queue_draw()

    def shown_all(self):
        return self.events + self.birthdays

    def shown(self):
        """The events of the calendars that are ticked, birthdays from Crew
        among them."""
        return [e for e in self.shown_all() if calendars.key_of(e) not in self.hidden]

    def _cards_changed(self, *_args):
        self.birthdays = birthday_events()
        self.refresh()

    def _tick(self):
        self.refresh()
        return True

    # -- events ---------------------------------------------------------------
    def choose(self, uid):
        if self.selected != uid:
            self.selected = uid
            self.refresh()

    def _save(self, undoable=True):
        if undoable:
            self.undos = (self.undos + [self.saved])[-50:]
            self.redos = []
        self.saved = [e.copy() for e in self.events]
        store.save(self.events)
        try:
            self.written = os.stat(store.store_path()).st_mtime
        except OSError:
            pass

    def _file_changed(self, _monitor, _file, _other, kind):
        if kind not in (Gio.FileMonitorEvent.CHANGES_DONE_HINT, Gio.FileMonitorEvent.CREATED,
                        Gio.FileMonitorEvent.RENAMED, Gio.FileMonitorEvent.MOVED_IN):
            return
        try:
            if os.stat(store.store_path()).st_mtime == self.written:
                return
        except OSError:
            return
        if self.editor is None:
            self.events = store.load()
            self.saved = [e.copy() for e in self.events]
            self.undos, self.redos = [], []
            self._calendars_changed()
            self.refresh()

    def undo(self, redo=False):
        take, give = (self.redos, self.undos) if redo else (self.undos, self.redos)
        if not take:
            return
        give.append(self.saved)
        self.events = [e.copy() for e in take.pop()]
        if self.selected not in {e.uid for e in self.events}:
            self.selected = None
        self._save(undoable=False)
        self.refresh()

    def add_event(self, start, end, all_day=False):
        event = store.Event("New Event", start, end, all_day)
        key = calendars.default_key(self.settings)
        if key in self.hidden:
            # A new event goes where it can be seen.
            key = next((c.key for c in self.calendars if c.editable and c.key not in self.hidden), key)
        if key:
            calendars.move(event, key)
        self.events.append(event)
        self._save()
        self.selected = event.uid
        self.day = start.date()
        self.refresh()
        GLib.idle_add(self._edit_new, event)

    def _edit_new(self, event):
        """Open the editor beside the event just drawn."""
        page = self.view
        hits = self.month.hits if page == "month" else self.grids[page].hits + self.headers[page].hits
        widget = self.month if page == "month" else None
        for x, y, w, h, occ in hits:
            if occ.event.uid == event.uid:
                if widget is None:
                    widget = self.headers[page] if event.all_day else self.grids[page]
                self.edit(event, widget, (int(x), int(y), int(w), int(h)))
                self.editor.name.grab_focus()
                return False
        self.edit(event, self.stack, (self.stack.get_allocated_width() // 2, 80, 1, 1))
        self.editor.name.grab_focus()
        return False

    def new_event(self):
        now = dt.datetime.now()
        if self.day == now.date():
            start = (now + dt.timedelta(hours=1)).replace(minute=0, second=0, microsecond=0)
            if start.date() != self.day:
                start = dt.datetime.combine(self.day, dt.time(23))
        else:
            start = dt.datetime.combine(self.day, dt.time(9))
        if self.view != "month" and self.view in self.scrolls:
            adj = self.scrolls[self.view].get_vadjustment()
            adj.set_value(min(max(self.grids[self.view].y_of(start) - 120, 0), adj.get_upper() - adj.get_page_size()))
        self.add_event(start, start + dt.timedelta(hours=1))

    def edit(self, event, widget, rect):
        if getattr(event, "person", None):
            # A birthday belongs to its card: change it there.
            Gio.Subprocess.new(["freemac-crew", event.person], Gio.SubprocessFlags.NONE)
            return
        if self.editor is not None:
            self.editor.popdown()
        self.editor = Editor(self, event, widget, rect)
        self.editor.connect("closed", lambda *_: setattr(self, "editor", None))
        self.editor.popup()

    def replace_event(self, event):
        for n, old in enumerate(self.events):
            if old.uid == event.uid:
                self.events[n] = event
                break
        else:
            self.events.append(event)
        self._save()
        self.refresh()

    def move_event(self, event, shift):
        moved = event.copy()
        moved.start += shift
        moved.end += shift
        self.replace_event(moved)

    def delete_event(self, event):
        self.events = [e for e in self.events if e.uid != event.uid]
        if self.selected == event.uid:
            self.selected = None
        self._save()
        self.refresh()

    def delete_chosen(self):
        for event in self.events:
            if event.uid == self.selected:
                self.delete_event(event)
                return

    def _key(self, _w, event):
        focus = self.get_focus()
        typing = isinstance(focus, (Gtk.Entry, Gtk.TextView)) or self.editor is not None
        command = event.state & Gdk.ModifierType.CONTROL_MASK
        key = Gdk.keyval_to_lower(event.keyval)
        if command:
            if key == Gdk.KEY_z and not typing:
                self.undo(redo=bool(event.state & Gdk.ModifierType.SHIFT_MASK))
                return True
            actions = {Gdk.KEY_n: self.new_event, Gdk.KEY_t: self.today, Gdk.KEY_w: self.close,
                       Gdk.KEY_1: lambda: self.show_view("day"), Gdk.KEY_2: lambda: self.show_view("week"),
                       Gdk.KEY_3: lambda: self.show_view("month")}
            if not typing:
                actions[Gdk.KEY_Left] = lambda: self.step(-1)
                actions[Gdk.KEY_Right] = lambda: self.step(1)
            if key in actions:
                actions[key]()
                return True
            return False
        if typing:
            return False
        if key in (Gdk.KEY_Delete, Gdk.KEY_BackSpace) and self.selected:
            self.delete_chosen()
            return True
        if key == Gdk.KEY_Escape and self.selected:
            self.choose(None)
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and self.selected:
            page = self.view
            hits = self.month.hits if page == "month" else self.grids[page].hits + self.headers[page].hits
            for x, y, w, h, occ in hits:
                if occ.event.uid == self.selected:
                    widget = (self.month if page == "month"
                              else self.headers[page] if occ.all_day else self.grids[page])
                    self.edit(occ.event, widget, (int(x), int(y), int(w), int(h)))
                    return True
        if key in (Gdk.KEY_Left, Gdk.KEY_Right, Gdk.KEY_Up, Gdk.KEY_Down) and self.view != "day":
            jump = {Gdk.KEY_Left: -1, Gdk.KEY_Right: 1, Gdk.KEY_Up: -7, Gdk.KEY_Down: 7}[key]
            if self.view == "week" and key in (Gdk.KEY_Up, Gdk.KEY_Down):
                return False
            self.day += dt.timedelta(days=jump)
            self.refresh()
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("New Event", "win.new-event", "<Ctrl>n")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Undo", "win.undo", "<Ctrl>z"), ("Redo", "win.redo", "<Shift><Ctrl>z")],
                   [("Delete Event", "win.delete-event", "Delete")]]),
        ("_View", [[("Day", "win.view-day", "<Ctrl>1"), ("Week", "win.view-week", "<Ctrl>2"),
                    ("Month", "win.view-month", "<Ctrl>3")],
                   [("Show Calendar List", "win.calendar-list", "<Alt><Ctrl>s")],
                   [("Go to Today", "win.today", "<Ctrl>t"), ("Previous", "win.previous", "<Ctrl>Left"),
                    ("Next", "win.next", "<Ctrl>Right")]]),
    ])


class Tide(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_open(self, files, _count, _hint):
        """Opening .ics files (an invitation, another app's export) adds
        their events, once each, and shows the first of them."""
        window = self.get_active_window() or Window(self)
        known = {e.uid for e in window.events}
        added = []
        for f in files:
            if f.get_uri_scheme() == "tide-event":
                # An alert's notice was clicked: show that event on its day.
                uid, _sep, day = f.get_uri()[len("tide-event:"):].partition("@@")
                window.selected = urllib.parse.unquote(uid)
                try:
                    window.day = dt.date.fromisoformat(day)
                except ValueError:
                    pass
                window.show_view("day")
                continue
            path = f.get_path()
            for event in store.load(path) if path else []:
                if event.uid not in known:
                    known.add(event.uid)
                    window.events.append(event)
                    added.append(event)
        if added:
            window._save()
            window.selected = added[0].uid
            window.day = added[0].start.date()
            window.refresh()
        window.present()

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: GLib.idle_add(self.quit))
        self.add_action(quit_action)
        # Tide stays open with no window, as a Mac app does; Quit ends it.
        self.hold()
        self.set_menubar(menubar())

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


def main():
    return Tide().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
