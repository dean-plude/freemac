# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Date & Time: the time zone, setting the clock from the internet or
by hand, and how the menu bar shows the time.

The time zone and the clock belong to the whole computer, so they go through
systemd's date and time service (org.freedesktop.timedate1 on the system
bus). It asks for an administrator's password itself, through the session's
polkit agent, and remembers the answer for a few minutes as usual. The
menu bar's clock is the user's own and lives in shell.json beside the other
shell preferences.
"""
import os
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import style  # noqa: E402

BUS_NAME = "org.freedesktop.timedate1"
OBJECT = "/org/freedesktop/timedate1"
ZONEINFO = "/usr/share/zoneinfo"
REGIONS = ("Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic", "Australia", "Europe",
           "Indian", "Pacific")


# ---- Time zones (no GTK) ---------------------------------------------------------------
def timezones(root=ZONEINFO):
    """Every "Region/City" zone under the zoneinfo folder, sorted."""
    found = []
    for region in REGIONS:
        base = os.path.join(root, region)
        for folder, _dirs, files in os.walk(base):
            for name in files:
                found.append(os.path.relpath(os.path.join(folder, name), root))
    return sorted(found) + ["UTC"]


def zone_name(zone):
    """How a zone reads in the list: "New York (America)", "Buenos Aires
    (America, Argentina)", "UTC"."""
    if "/" not in zone or zone.startswith("Etc/"):
        return zone.split("/")[-1]
    parts = zone.split("/")
    city = parts[-1].replace("_", " ")
    return f"{city} ({', '.join(p.replace('_', ' ') for p in parts[:-1])})"


def offset_text(zone, when=None):
    """The zone's offset from UTC now, as "UTC+5:30" or "UTC−8"."""
    try:
        tz = GLib.TimeZone.new_identifier(zone) if hasattr(GLib.TimeZone, "new_identifier") else GLib.TimeZone.new(zone)
    except (TypeError, GLib.Error):
        return ""
    if tz is None:
        return ""
    moment = GLib.DateTime.new_now(tz) if when is None else when.to_timezone(tz)
    seconds = moment.get_utc_offset() // 1_000_000
    if seconds == 0:
        return "UTC"
    sign = "+" if seconds > 0 else "−"
    hours, minutes = divmod(abs(seconds) // 60, 60)
    return f"UTC{sign}{hours}" + (f":{minutes:02d}" if minutes else "")


def am_pm(when=None):
    """AM or PM as the region writes it, for strftime. Some regions' formats
    have no word for it (it's left empty), so then plain AM and PM."""
    when = time.localtime() if when is None else when
    word = time.strftime("%p", when)
    return "%p" if word.strip() else ("AM" if when.tm_hour < 12 else "PM")


MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")


def clock_format(prefs, when=None):
    """The menu bar clock's strftime format from the shell preferences. The
    day and month are in English, as freemac's menus are, in the region's
    order: Tue Nov 24 in the US, Tue 24 Nov in the UK."""
    from . import region
    when = time.localtime() if when is None else when
    parts = []
    if prefs.get("clock_day", True):
        parts.append(region.WEEKDAY_NAMES[when.tm_wday][:3])
    if prefs.get("clock_date", True):
        month = MONTHS[when.tm_mon - 1]
        parts.append(f"{month} {when.tm_mday}" if region.month_first() else f"{when.tm_mday} {month}")
    hour = "%H:%M" if style.h24(prefs) else "%-I:%M " + am_pm()
    if prefs.get("clock_seconds"):
        hour = hour.replace("%M", "%M:%S")
    return ("   ".join([" ".join(parts), hour]) if parts else hour)


# ---- The page --------------------------------------------------------------------------
class DateTimePanel(Gtk.Box):
    def __init__(self, window, page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.window = window
        group, row, _page, _slider, switch = window.helpers
        self.proxy = None
        try:
            self.proxy = Gio.DBusProxy.new_for_bus_sync(Gio.BusType.SYSTEM, Gio.DBusProxyFlags.NONE, None,
                                                        BUS_NAME, OBJECT, BUS_NAME, None)
        except GLib.Error:
            pass
        self.proxy and self.proxy.connect("g-properties-changed", lambda *_: GLib.idle_add(self._show_state))

        # The computer's clock.
        self.now_label = Gtk.Label(xalign=1)
        self.now_label.get_style_context().add_class("dials-caption")
        self.auto = Gtk.Switch()
        self.auto_handler = self.auto.connect("notify::active", self._set_auto)
        self.set_button = Gtk.MenuButton(label="Set…")
        self.set_button.set_popover(self._set_popover())
        clock_row = Gtk.Box(spacing=10)
        clock_row.pack_start(self.now_label, False, False, 0)
        clock_row.pack_start(self.set_button, False, False, 0)

        # The time zone: type to find a city.
        self.zones = timezones()
        self.zone_entry = Gtk.Entry(width_chars=28, placeholder_text="Type a city")
        self.zone_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, "edit-find-symbolic")
        store = Gtk.ListStore(str, str)
        for zone in self.zones:
            store.append([zone_name(zone), zone])
        completion = Gtk.EntryCompletion(model=store, minimum_key_length=1,
                                         popup_set_width=True, inline_selection=False)
        # set_text_column (not the property) also adds the cell that draws the names.
        completion.set_text_column(0)
        completion.set_match_func(self._match, None)
        completion.connect("match-selected", lambda _c, model, it: self._set_zone(model[it][1]) or False)
        self.zone_entry.set_completion(completion)
        self.zone_entry.connect("activate", self._zone_typed)
        # A click in the box picks the whole name, so typing a city replaces it.
        self.zone_entry.connect("focus-in-event",
                                lambda e, _ev: GLib.idle_add(lambda: e.select_region(0, -1) and False))
        self.zone_entry.connect("focus-out-event", lambda *_: self._show_state() and False)
        self.zone_caption = Gtk.Label(xalign=0)
        self.zone_caption.get_style_context().add_class("dials-caption")

        # The menu bar's clock (the user's own preference).
        prefs = style.prefs()
        clock = Gtk.ComboBoxText()
        for fmt, name in (("12", "12-hour (2:30 PM)"), ("24", "24-hour (14:30)")):
            clock.append(fmt, name)
        clock.set_active_id("24" if style.h24(prefs) else "12")
        clock.connect("changed", lambda c: window.save_prefs(clock=c.get_active_id()))

        self.status = Gtk.Label(xalign=0, wrap=True, no_show_all=True)
        self.status.get_style_context().add_class("dials-caption")

        zone_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        zone_box.pack_start(self.zone_entry, False, False, 0)
        zone_box.pack_start(self.zone_caption, False, False, 0)
        self.pack_start(page("Date & Time", group(
            row("Set the time automatically", self.auto,
                "Keeps the clock right using a time server on the internet."),
            row("Date and time", clock_row),
        ), group(
            row("Time zone", zone_box),
        ), group(
            row("Time format", clock),
            row("Show the day of the week in the menu bar",
                switch(prefs.get("clock_day", True), lambda on: window.save_prefs(clock_day=on))),
            row("Show the date in the menu bar",
                switch(prefs.get("clock_date", True), lambda on: window.save_prefs(clock_date=on))),
            row("Show seconds", switch(bool(prefs.get("clock_seconds")),
                                       lambda on: window.save_prefs(clock_seconds=on))),
        ), self.status), True, True, 0)
        self._show_state()
        self._tick()
        GLib.timeout_add_seconds(1, self._tick)

    # -- reading ----------------------------------------------------------------------
    def _prop(self, name, default=None):
        if self.proxy is None:
            return default
        value = self.proxy.get_cached_property(name)
        return value.unpack() if value is not None else default

    def _show_state(self):
        zone = self._prop("Timezone") or _local_zone()
        if not self.zone_entry.has_focus():
            self.zone_entry.set_text(zone_name(zone))
        self.zone_caption.set_text(f"{offset_text(zone)}  ·  {zone}" if offset_text(zone) else zone)
        can_ntp = bool(self._prop("CanNTP", False))
        ntp = bool(self._prop("NTP", False))
        self.auto.handler_block(self.auto_handler)
        self.auto.set_active(ntp)
        self.auto.handler_unblock(self.auto_handler)
        self.auto.set_sensitive(can_ntp)
        self.set_button.set_sensitive(self.proxy is not None and not ntp)
        if self.proxy is None:
            self.say("The date and time service isn't running, so these can't be changed.")
        return False

    def _tick(self):
        time.tzset()
        fmt = "%A %-d %B %Y   %H:%M:%S" if style.h24() else "%A %-d %B %Y   %-I:%M:%S " + am_pm()
        self.now_label.set_text(time.strftime(fmt))
        return self.get_mapped() or self.get_parent() is not None

    def say(self, text):
        self.status.set_text(text or "")
        self.status.set_visible(bool(text))

    # -- changing ---------------------------------------------------------------------
    def _call(self, method, args, done_text=None):
        if self.proxy is None:
            return

        def finished(proxy, result):
            try:
                proxy.call_finish(result)
                self.say(done_text or "")
            except GLib.Error as error:
                message = error.message.split(":", 2)[-1].strip() if error.message else ""
                if "NotAuthorized" in (error.message or "") or "dismissed" in message.lower():
                    self.say("")
                else:
                    self.say(f"That couldn't be changed: {message}")
            self.proxy.call("org.freedesktop.DBus.Properties.GetAll", GLib.Variant("(s)", (BUS_NAME,)),
                            Gio.DBusCallFlags.NONE, -1, None, self._refresh_props)

        # Interactive: the polkit agent asks for an administrator's password.
        self.proxy.call(method, args, Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, 120_000, None, finished)

    def _refresh_props(self, proxy, result):
        try:
            (props,) = proxy.call_finish(result).unpack()
        except GLib.Error:
            return
        for name, value in props.items():
            if isinstance(value, bool):
                proxy.set_cached_property(name, GLib.Variant("b", value))
            elif isinstance(value, str):
                proxy.set_cached_property(name, GLib.Variant("s", value))
        self._show_state()

    def _set_auto(self, switch, _param):
        self._call("SetNTP", GLib.Variant("(bb)", (switch.get_active(), True)))

    def _match(self, completion, key, it, _data):
        model = completion.get_model()
        words = key.lower().replace("_", " ").split()
        text = (model[it][0] + " " + model[it][1]).lower().replace("_", " ")
        return all(word in text for word in words)

    def _zone_typed(self, entry):
        words = entry.get_text().lower().split()
        matches = [z for z in self.zones if all(w in (zone_name(z) + " " + z).lower().replace("_", " ")
                                                 for w in words)]
        if len(matches) == 1 or (matches and zone_name(matches[0]).lower() == entry.get_text().lower()):
            self._set_zone(matches[0])
        else:
            self.say("Choose a city from the list as you type.")

    def _set_zone(self, zone):
        self.zone_entry.set_text(zone_name(zone))
        self.window.set_focus(None)
        if zone != (self._prop("Timezone") or _local_zone()):
            self._call("SetTimezone", GLib.Variant("(sb)", (zone, True)))

    def _set_popover(self):
        popover = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=12)
        calendar = Gtk.Calendar()
        hour = Gtk.SpinButton.new_with_range(0, 23, 1)
        minute = Gtk.SpinButton.new_with_range(0, 59, 1)
        for spin in (hour, minute):
            spin.set_wrap(True)
            spin.connect("output", lambda s: s.set_text(f"{int(s.get_value()):02d}") or True)
        when = Gtk.Box(spacing=4, halign=Gtk.Align.CENTER)
        when.pack_start(hour, False, False, 0)
        when.pack_start(Gtk.Label(label=":"), False, False, 0)
        when.pack_start(minute, False, False, 0)
        set_it = Gtk.Button(label="Set", halign=Gtk.Align.END)
        set_it.get_style_context().add_class("suggested-action")

        def opened(_popover):
            now = time.localtime()
            calendar.select_month(now.tm_mon - 1, now.tm_year)
            calendar.select_day(now.tm_mday)
            hour.set_value(now.tm_hour)
            minute.set_value(now.tm_min)

        def apply(_button):
            year, month, day = calendar.get_date()
            local = time.mktime((year, month + 1, day, int(hour.get_value()), int(minute.get_value()), 0, 0, 0, -1))
            popover.popdown()
            self._call("SetTime", GLib.Variant("(xbb)", (int(local * 1_000_000), False, True)))

        popover.connect("show", opened)
        set_it.connect("clicked", apply)
        box.pack_start(calendar, False, False, 0)
        box.pack_start(when, False, False, 0)
        box.pack_start(set_it, False, False, 0)
        box.show_all()
        popover.add(box)
        return popover


def _local_zone():
    try:
        return os.readlink("/etc/localtime").split("zoneinfo/", 1)[1]
    except (OSError, IndexError):
        return "UTC"
