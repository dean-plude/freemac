# SPDX-License-Identifier: GPL-3.0-or-later
"""The battery part of Dials > Battery, as on a Mac: Low Power Mode, the
battery's health, and its level over the last 24 hours or the time spent on
battery each of the last 10 days (battery.py keeps the samples).
Original freemac code.
"""
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import battery, style  # noqa: E402

GREEN = (0.20, 0.72, 0.35)
CHART_HEIGHT = 150
AXIS = 44            # room on the right for 100% / 50% / 0%
FOOT = 22            # room below for the hours or days


def _hour_label(t, h24):
    return time.strftime("%H:%M" if h24 else "%-I %p", time.localtime(t))


class BatteryChart(Gtk.DrawingArea):
    """Bars of the battery level every 15 minutes over the last 24 hours,
    with a green strip under the times it was charging; or a bar for each of
    the last 10 days, as tall as the time it ran on battery."""

    def __init__(self):
        super().__init__()
        self.set_size_request(-1, CHART_HEIGHT + FOOT)
        self.mode = "day"
        self.samples = []
        self.now = time.time()
        self.connect("draw", self._draw)
        self.set_has_tooltip(True)
        self.connect("query-tooltip", self._tooltip)

    def show(self, mode, samples, now=None):
        self.mode, self.samples = mode, samples
        self.now = time.time() if now is None else now
        self.queue_draw()

    def _ink(self):
        colour = self.get_style_context().get_color(Gtk.StateFlags.NORMAL)
        return colour.red, colour.green, colour.blue

    def _grid(self, cr, width, top, lines, labels):
        ink = self._ink()
        cr.set_line_width(1)
        for fraction, label in zip(lines, labels):
            bottom = top + CHART_HEIGHT - 6
            y = round(bottom - (bottom - top - 6) * fraction) + 0.5
            cr.set_source_rgba(*ink, 0.12)
            cr.move_to(0, y)
            cr.line_to(width - AXIS, y)
            cr.stroke()
            cr.set_source_rgba(*ink, 0.55)
            cr.move_to(width - AXIS + 6, y + 4)
            cr.show_text(label)

    def _draw(self, widget, cr):
        width = widget.get_allocated_width()
        cr.select_font_face("sans-serif")
        cr.set_font_size(10.5)
        if self.mode == "day":
            self._draw_day(cr, width)
        else:
            self._draw_days(cr, width)

    def _draw_day(self, cr, width):
        slots = battery.levels(self.samples, self.now)
        plot = width - AXIS
        self._grid(cr, width, 0, (1, 0.5, 0), ("100%", "50%", "0%"))
        n = len(slots)
        step = plot / n
        bottom = CHART_HEIGHT - 6
        for i, slot in enumerate(slots):
            if slot is None:
                continue
            percent, charging = slot
            h = max(1.5, (bottom - 6) * percent / 100)
            cr.set_source_rgb(*GREEN)
            cr.rectangle(i * step + 0.5, bottom - h, max(1.0, step - 1), h)
            cr.fill()
            if charging:
                cr.set_source_rgba(*GREEN, 0.55)
                cr.rectangle(i * step, bottom + 2, step, 4)
                cr.fill()
        # Every 6 hours along the bottom, at the start of an hour.
        ink = self._ink()
        h24 = style.prefs().get("clock") == "24"
        start = self.now - n * 15 * 60
        first = start - (start % 3600) + 3600
        t = first
        while t < self.now:
            hour = time.localtime(t).tm_hour
            if hour % 6 == 0:
                x = (t - start) / (15 * 60) * step
                cr.set_source_rgba(*ink, 0.55)
                label = _hour_label(t, h24)
                extents = cr.text_extents(label)
                cr.move_to(min(plot - extents.width, max(0, x - extents.width / 2)), CHART_HEIGHT + 14)
                cr.show_text(label)
            t += 3600

    def _days_scale(self, days):
        most = max((seconds for _d, seconds in days), default=0)
        hours = max(4, int(-(-most // 3600)))     # round up to a whole hour, 4 at least
        hours += hours % 2                        # even, so the middle line is a whole hour
        return hours * 3600

    def _draw_days(self, cr, width):
        days = battery.days_on_battery(self.samples, self.now)
        plot = width - AXIS
        scale = self._days_scale(days)
        top_hours = scale // 3600
        self._grid(cr, width, 0, (1, 0.5, 0), (f"{top_hours} hr", f"{top_hours // 2} hr", "0 hr"))
        bottom = CHART_HEIGHT - 6
        step = plot / len(days)
        ink = self._ink()
        for i, (day, seconds) in enumerate(days):
            if seconds > 0:
                h = max(1.5, (bottom - 6) * seconds / scale)
                cr.set_source_rgb(*GREEN)
                x = i * step + step * 0.2
                cr.rectangle(x, bottom - h, step * 0.6, h)
                cr.fill()
            label = "Today" if i == len(days) - 1 else time.strftime("%a", time.localtime(day))
            extents = cr.text_extents(label)
            cr.set_source_rgba(*ink, 0.55)
            cr.move_to(i * step + (step - extents.width) / 2, CHART_HEIGHT + 14)
            cr.show_text(label)

    def _tooltip(self, widget, x, _y, _keyboard, tip):
        plot = widget.get_allocated_width() - AXIS
        if x > plot:
            return False
        h24 = style.prefs().get("clock") == "24"
        if self.mode == "day":
            slots = battery.levels(self.samples, self.now)
            i = int(x / (plot / len(slots)))
            if not 0 <= i < len(slots) or slots[i] is None:
                return False
            percent, charging = slots[i]
            when = self.now - (len(slots) - i) * 15 * 60
            tip.set_text(f"{_hour_label(when, h24)}: {percent}%" + (", charging" if charging else ""))
            return True
        days = battery.days_on_battery(self.samples, self.now)
        i = int(x / (plot / len(days)))
        if not 0 <= i < len(days):
            return False
        day, seconds = days[i]
        tip.set_text(f"{time.strftime('%A %-d %B', time.localtime(day))}: {battery.duration(seconds)} on battery")
        return True


def _when(t):
    """'Today, 10:42 AM', 'Yesterday, 18:05', 'Sat 21 Nov, 9:10 AM'."""
    h24 = style.prefs().get("clock") == "24"
    clock = time.strftime("%H:%M" if h24 else "%-I:%M %p", time.localtime(t))
    days = (time.localtime().tm_yday - time.localtime(t).tm_yday) % 366
    if days == 0:
        return f"Today, {clock}"
    if days == 1:
        return f"Yesterday, {clock}"
    return time.strftime("%a %-d %b", time.localtime(t)) + f", {clock}"


def low_power_row(window, row):
    """Low Power Mode: Never, Always, Only on Battery, Only on Power Adapter."""
    combo = Gtk.ComboBoxText()
    for value, label in battery.LOW_POWER_MODES:
        combo.append(value, label)
    mode = style.prefs().get("low_power_mode", "never")
    combo.set_active_id(mode if mode in dict(battery.LOW_POWER_MODES) else "never")

    def changed(c):
        value = c.get_active_id()
        window.save_prefs(low_power_mode=value)
        battery.apply_low_power(value, battery.on_adapter())
    combo.connect("changed", changed)
    return row("Low Power Mode", combo, "Uses less energy, so the battery lasts longer. "
                                        "The battery in the menu bar turns yellow while it's on.")


def health_row(row, info):
    words = []
    if info.get("maximum") is not None:
        words.append(f"Maximum capacity {info['maximum']}% of when it was new")
    if info.get("cycles") is not None:
        words.append(f"{info['cycles']} charge cycles")
    note = ". ".join(words)
    if info.get("condition") == "Service Recommended":
        note += (". It holds much less than it did new; a new battery would make it last "
                 "longer between charges.")
    return row("Battery Health", Gtk.Label(label=info.get("condition") or "Unknown"), note or None)


def usage_group(group, row):
    """The chart, its two choices, and when the battery was last charged."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    top = Gtk.Box(spacing=8)
    switcher = Gtk.Box(halign=Gtk.Align.START)
    switcher.get_style_context().add_class("linked")
    caption = Gtk.Label(xalign=0)
    caption.get_style_context().add_class("dials-caption")
    top.pack_start(switcher, False, False, 0)
    top.pack_end(caption, False, False, 0)
    title = Gtk.Label(xalign=0)
    title.get_style_context().add_class("battery-chart-title")
    chart = BatteryChart()

    def refresh(mode):
        samples = battery.history()
        chart.show(mode, samples)
        if mode == "day":
            title.set_text("Battery Level")
            charged = battery.last_charged(samples)
            caption.set_text(f"Last charged to {charged[0]}%  ·  {_when(charged[1])}" if charged else "")
        else:
            title.set_text("Time on Battery")
            days = battery.days_on_battery(samples)
            total = sum(seconds for _d, seconds in days)
            caption.set_text(f"{battery.duration(total)} in the last 10 days" if total else "")

    first = None
    for mode, label in (("day", "Last 24 Hours"), ("days", "Last 10 Days")):
        button = Gtk.RadioButton.new_with_label_from_widget(first, label)
        button.set_mode(False)
        first = first or button
        button.connect("toggled", lambda b, m=mode: b.get_active() and refresh(m))
        switcher.pack_start(button, False, False, 0)
    box.pack_start(top, False, False, 0)
    box.pack_start(title, False, False, 0)
    box.pack_start(chart, False, False, 0)
    refresh("day")
    for side in ("top", "bottom", "start", "end"):
        getattr(box, "set_margin_" + side)(4)
    item = Gtk.ListBoxRow(activatable=False, selectable=False)
    item.add(box)

    def tick():
        if not chart.get_mapped():
            return chart.get_parent() is not None
        refresh("day" if first.get_active() else "days")
        return True
    GLib.timeout_add_seconds(60, tick)
    return group(item)


CSS = b"""
.battery-chart-title { font-weight: bold; }
"""


def install_css():
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
