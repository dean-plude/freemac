# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Language & Region, as on a Mac: the region whose way of writing
dates, times, numbers and money every app uses, the first day of the week,
Celsius or Fahrenheit, and metric or US measures, with examples of each.

region.py keeps the choices and writes the session's environment. Apps
that are already open keep the formats they started with, so the page
offers to log out; freemac's own calendars, clock and Sky follow at once.
A computer installed before 1.189 has none of the regions yet: the first
time one is chosen, freemac-system-helper makes it, after an
administrator's password. Original freemac code.
"""
import os
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, region, sky_store  # noqa: E402

HELPER = "/usr/libexec/freemac-system-helper"
NEEDS_LOGOUT = "Apps you open after you log out and back in use the new formats; freemac's own calendars and clock change now."


class RegionPanel(Gtk.Box):
    def __init__(self, window, page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.window = window
        group, row, _page, _slider, _switch = window.helpers
        self.setting = region.settings()
        self.have = region.available()
        self.busy = False

        language = Gtk.Label(label="English (US)", xalign=1)
        language.get_style_context().add_class("dials-caption")

        self.region_box = Gtk.ComboBoxText()
        for code, name in region.ordered():
            self.region_box.append(code, name)
        self.region_box.set_active_id(self.setting["region"])
        self.region_box.connect("changed", self._region_changed)

        # Each shows what's in use; changing the region puts all three back
        # to the region's own, as a Mac does.
        self.first_box = Gtk.ComboBoxText()
        for number, name in enumerate(region.WEEKDAY_NAMES):
            self.first_box.append(str(number), name)
        self.first_box.connect("changed", lambda b: self._own(
            "first_day", int(b.get_active_id()), region.REGIONS[self.setting["region"]][1]))

        self.temperature_box = Gtk.ComboBoxText()
        self.temperature_box.append("C", "Celsius (°C)")
        self.temperature_box.append("F", "Fahrenheit (°F)")
        self.temperature_box.connect("changed", self._temperature_changed)

        self.measure_box = Gtk.ComboBoxText()
        self.measure_box.append("metric", "Metric")
        self.measure_box.append("us", "US")
        self.measure_box.connect("changed", lambda b: self._own(
            "measurement", b.get_active_id(), "us" if self.setting["region"] in ("en_US.UTF-8", "es_US.UTF-8") else "metric"))

        self.date_example = self._example_label()
        self.time_example = self._example_label()
        self.number_example = self._example_label()
        self.money_example = self._example_label()

        self.note = Gtk.Label(xalign=0, wrap=True, max_width_chars=60, no_show_all=True)
        self.note.get_style_context().add_class("dials-caption")
        log_out = Gtk.Button(label="Log Out…", halign=Gtk.Align.START, no_show_all=True)
        log_out.connect("clicked", lambda _b: Gio.Subprocess.new(["freemac-power", "logout"],
                                                                Gio.SubprocessFlags.NONE))
        self.log_out = log_out
        notes = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        notes.pack_start(self.note, False, False, 0)
        notes.pack_start(log_out, False, False, 0)

        self.pack_start(page("Language & Region", group(
            row("Preferred language", language,
                "freemac's own apps and menus are in English. Apps that come with other languages "
                "can still be set in their own settings."),
        ), group(
            row("Region", self.region_box,
                "How dates, times, numbers and money are written, in every app."),
            row("Calendar", self._plain("Gregorian")),
            row("First day of week", self.first_box),
            row("Temperature", self.temperature_box),
            row("Measurement system", self.measure_box),
        ), group(
            row("Date", self.date_example),
            row("Time", self.time_example),
            row("Number", self.number_example),
            row("Currency", self.money_example),
        ), notes), True, True, 0)
        self._show()

    # -- building ---------------------------------------------------------------------
    @staticmethod
    def _example_label():
        label = Gtk.Label(xalign=1, selectable=True)
        label.get_style_context().add_class("dials-caption")
        return label

    @staticmethod
    def _plain(text):
        label = Gtk.Label(label=text, xalign=1)
        label.get_style_context().add_class("dials-caption")
        return label

    # -- showing ----------------------------------------------------------------------
    def _show(self):
        code = self.setting["region"]
        self.busy = True
        self.region_box.set_active_id(code)
        self.first_box.set_active_id(str(region.first_weekday()))
        self.temperature_box.set_active_id("F" if region.fahrenheit() else "C")
        self.measure_box.set_active_id("metric" if region.metric() else "us")
        self.busy = False
        self._examples(code)

    def _examples(self, code):
        # The examples come from glibc itself, in a short-lived Python, so
        # they are exactly what apps will show.
        def work():
            found = region.examples(code)
            GLib.idle_add(self._show_examples, code, found)
        threading.Thread(target=work, daemon=True).start()

    def _show_examples(self, code, found):
        if code != self.setting["region"]:
            return False
        date, clock, number, money = found
        missing = "—"
        self.date_example.set_text(date or missing)
        self.time_example.set_text(clock or missing)
        self.number_example.set_text(number or missing)
        self.money_example.set_text(money or missing)
        return False

    def _say(self, text, log_out=False):
        self.note.set_text(text or "")
        self.note.set_visible(bool(text))
        self.log_out.set_visible(log_out)

    # -- changing ---------------------------------------------------------------------
    def _save(self, **changes):
        if self.busy:
            return
        self.setting = region.save(**changes)
        self._show()
        self._say(NEEDS_LOGOUT, log_out=True)

    def _own(self, key, value, regions_own):
        """A choice of the person's own; the region's own choice is kept as
        "auto", so it follows the region."""
        self._save(**{key: "auto" if value == regions_own else value})

    def _temperature_changed(self, box):
        if self.busy:
            return
        own = "F" if region.REGIONS[self.setting["region"]][3] else "C"
        self._own("temperature", box.get_active_id(), own)
        sky_store.set_unit("F" if region.fahrenheit() else "C")

    def _region_changed(self, box):
        if self.busy:
            return
        code = box.get_active_id()
        if code not in region.REGIONS:
            return
        if code in self.have:
            self._choose(code)
            return
        # This computer was installed before freemac made the regions: make
        # this one, as root, after an administrator's password.
        if not os.path.exists(HELPER):
            self._show()
            alert.tell(self.window, "This region can't be added here",
                       "This copy of freemac doesn't have the helper that adds regions.")
            return
        box.set_sensitive(False)
        self._say(f"Adding {region.REGIONS[code][0]}…")
        try:
            proc = Gio.Subprocess.new(["pkexec", HELPER, "region", code], Gio.SubprocessFlags.STDERR_PIPE)
        except GLib.Error as error:
            box.set_sensitive(True)
            self._show()
            self._say("")
            alert.tell(self.window, "The region wasn't changed", error.message)
            return

        def finished(p, result):
            box.set_sensitive(True)
            err = ""
            try:
                _ok, _out, err = p.communicate_utf8_finish(result)
            except GLib.Error as error:
                err = error.message
            status = p.get_exit_status() if p.get_if_exited() else 1
            self.have = region.available()
            if status == 0 and code in self.have:
                self._choose(code)
                return
            self._show()
            self._say("")
            if status in (126, 127):
                return
            alert.tell(self.window, "The region wasn't changed", (err or "").strip())

        proc.communicate_utf8_async(None, None, finished)

    def _choose(self, code):
        self.setting = region.save(region=code, first_day="auto", temperature="auto", measurement="auto")
        self._show()
        self._say(NEEDS_LOGOUT, log_out=True)
        sky_store.set_unit("F" if region.fahrenheit() else "C")
