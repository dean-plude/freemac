# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Battery (or Power) > Schedule…: start up or wake at one time, and
sleep, restart or shut down at another, as a Mac's Energy settings have it.

The schedule is the whole computer's, so saving it goes through
/usr/libexec/freemac-power-schedule with pkexec, after an administrator's
password. power_schedule.py reads it.

Original freemac code.
"""
import json
import os

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, style  # noqa: E402
from . import power_schedule as ps  # noqa: E402

HELPER = "/usr/libexec/freemac-power-schedule"


class TimeBox(Gtk.Box):
    """Hours and minutes, with AM and PM unless the clock is 24-hour."""

    def __init__(self, at, h24):
        super().__init__(spacing=4)
        self.h24 = h24
        hour, minute = (int(x) for x in at.split(":"))
        if h24:
            self.hour = Gtk.SpinButton.new_with_range(0, 23, 1)
            self.hour.set_value(hour)
        else:
            self.hour = Gtk.SpinButton.new_with_range(1, 12, 1)
            self.hour.set_value((hour % 12) or 12)
        self.minute = Gtk.SpinButton.new_with_range(0, 59, 1)
        self.minute.set_value(minute)
        for spin in (self.hour, self.minute):
            spin.set_width_chars(2)
            spin.set_wrap(True)
            spin.set_orientation(Gtk.Orientation.HORIZONTAL)
        # 7:05 AM, or 07:05 on a 24-hour clock, as the menu bar shows them.
        self.minute.connect("output", self._two_digits)
        if h24:
            self.hour.connect("output", self._two_digits)
        self.pack_start(self.hour, False, False, 0)
        self.pack_start(Gtk.Label(label=":"), False, False, 0)
        self.pack_start(self.minute, False, False, 0)
        self.half = None
        if not h24:
            self.half = Gtk.ComboBoxText()
            self.half.append("am", "AM")
            self.half.append("pm", "PM")
            self.half.set_active_id("am" if hour < 12 else "pm")
            self.pack_start(self.half, False, False, 0)

    @staticmethod
    def _two_digits(spin):
        spin.set_text(f"{int(spin.get_value()):02d}")
        return True

    def get(self):
        hour = int(self.hour.get_value())
        if not self.h24:
            hour = hour % 12 + (12 if self.half.get_active_id() == "pm" else 0)
        return f"{hour:02d}:{int(self.minute.get_value()):02d}"


def days_combo(current):
    combo = Gtk.ComboBoxText()
    for key, label in ps.DAYS:
        combo.append(key, label)
    combo.set_active_id(current)
    return combo


def edit(window, changed):
    """The Schedule… sheet. changed() is called once a new schedule is saved."""
    h24 = style.prefs().get("clock") == "24"
    schedule = ps.load()
    wake = schedule["wake"] or {"days": "weekdays", "time": "07:00"}
    action = schedule["action"] or {"days": "everyday", "time": "22:00", "what": "shutdown"}
    dialog = Gtk.Dialog(title="Schedule", transient_for=window, modal=True, use_header_bar=True)
    dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
    ok = dialog.add_button("Apply", Gtk.ResponseType.OK)
    ok.get_style_context().add_class("suggested-action")
    grid = Gtk.Grid(row_spacing=12, column_spacing=10, margin=18)
    dialog.get_content_area().add(grid)

    wake_on = Gtk.CheckButton(label="Start up or wake", active=bool(schedule["wake"]))
    wake_days = days_combo(wake["days"])
    wake_time = TimeBox(wake["time"], h24)
    grid.attach(wake_on, 0, 0, 1, 1)
    grid.attach(wake_days, 1, 0, 1, 1)
    grid.attach(Gtk.Label(label="at"), 2, 0, 1, 1)
    grid.attach(wake_time, 3, 0, 1, 1)

    action_on = Gtk.CheckButton(active=bool(schedule["action"]))
    what = Gtk.ComboBoxText()
    for key, label in ps.ACTIONS:
        what.append(key, label)
    what.set_active_id(action["what"])
    first = Gtk.Box(spacing=6)
    first.pack_start(action_on, False, False, 0)
    first.pack_start(what, False, False, 0)
    action_days = days_combo(action["days"])
    action_time = TimeBox(action["time"], h24)
    grid.attach(first, 0, 1, 1, 1)
    grid.attach(action_days, 1, 1, 1, 1)
    grid.attach(Gtk.Label(label="at"), 2, 1, 1, 1)
    grid.attach(action_time, 3, 1, 1, 1)

    note = Gtk.Label(label="Anyone logged in gets ten minutes' warning, and can cancel. Starting up from off works "
                           "on most PCs; if yours doesn't, turn on the wake alarm (sometimes called RTC Alarm "
                           "or Resume by Alarm) in its firmware settings.",
                     xalign=0, wrap=True, max_width_chars=56)
    note.get_style_context().add_class("dials-caption")
    grid.attach(note, 0, 2, 4, 1)

    def update(*_):
        for widget in (wake_days, wake_time):
            widget.set_sensitive(wake_on.get_active())
        for widget in (what, action_days, action_time):
            widget.set_sensitive(action_on.get_active())

    for check in (wake_on, action_on):
        check.connect("toggled", update)
    update()
    dialog.show_all()
    answer = dialog.run()
    new = {"wake": {"days": wake_days.get_active_id(), "time": wake_time.get()} if wake_on.get_active() else None,
           "action": {"days": action_days.get_active_id(), "time": action_time.get(), "what": what.get_active_id()}
           if action_on.get_active() else None}
    dialog.destroy()
    if answer != Gtk.ResponseType.OK or new == schedule:
        return
    save(window, new, changed)


def save(window, schedule, changed):
    if not os.path.exists(HELPER):
        alert.tell(window, "The schedule can't be changed here",
                   "This copy of freemac doesn't have the helper that keeps the schedule.")
        return
    flags = Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
    try:
        proc = Gio.Subprocess.new(["pkexec", HELPER, "set"], flags)
    except GLib.Error as e:
        alert.tell(window, "The schedule wasn't changed", e.message)
        return

    def finished(p, result):
        err = ""
        try:
            _ok, _out, err = p.communicate_utf8_finish(result)
        except GLib.Error as e:
            err = e.message
        code = p.get_exit_status() if p.get_if_exited() else 1
        if code in (126, 127):
            alert.tell(window, "The schedule wasn't changed",
                       "The administrator's password wasn't given, so nothing changed.")
        elif code:
            alert.tell(window, "The schedule wasn't changed", (err or "").strip())
        else:
            changed()

    proc.communicate_utf8_async(json.dumps(schedule), None, finished)


def summary():
    text = ps.describe(ps.load(), style.prefs().get("clock") == "24")
    return text if text != "Off" else "Start up, wake, sleep, restart or shut down at set times."


def schedule_row(window, row):
    """The row for the Battery or Power page: what's scheduled, and Schedule…."""
    button = Gtk.Button(label="Schedule…")
    item = row("Schedule", button, summary())
    caption = item.get_child().get_children()[0].get_children()[1]
    button.connect("clicked", lambda *_: edit(window, lambda: caption.set_text(summary())))
    return item
