# SPDX-License-Identifier: GPL-3.0-or-later
"""Chime: freemac's clock app.

Four pages: World (the time in other places), Alarms, Timer and Stopwatch.
Alarms and a running timer keep working after the window is closed: Chime
stays in the background while it has something to ring for, and starts
quietly at login (freemac-chime --background) when an alarm is switched on.
Ringing shows a Beacon notification and plays the freedesktop alarm sound.

Settings live in ~/.config/freemac/chime.json.
"""
import datetime
import json
import os
import shutil
import subprocess
import sys
import time
import zoneinfo

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

from . import beacon, menus, style  # noqa: E402

APP_ID = "org.freemac.Chime"
CONFIG = os.path.join(GLib.get_user_config_dir(), "freemac", "chime.json")
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
SOUNDS = ["/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
          "/usr/share/sounds/freedesktop/stereo/complete.oga"]


# -- settings ----------------------------------------------------------------
def load():
    data = {"cities": [], "alarms": [], "clock24": None}
    try:
        with open(CONFIG) as f:
            data.update(json.load(f))
    except (OSError, ValueError):
        pass
    return data


def save(data):
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    tmp = CONFIG + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, CONFIG)


def all_zones():
    try:
        return sorted(z for z in zoneinfo.available_timezones() if "/" in z and not z.startswith(("Etc/", "SystemV/")))
    except Exception:  # noqa: BLE001  (no tzdata installed)
        return []


def place_name(zone):
    return zone.rsplit("/", 1)[-1].replace("_", " ")


def uses_24h(data):
    """Follow the clock format chosen in Dials > Date & Time."""
    if data.get("clock24") is not None:
        return bool(data["clock24"])
    return style.h24()


def clock_text(dt, h24, seconds=False):
    if h24:
        return dt.strftime("%H:%M:%S" if seconds else "%H:%M")
    text = dt.strftime("%I:%M:%S %p" if seconds else "%I:%M %p")
    return text.lstrip("0")


def duration_text(seconds, hundredths=False):
    seconds = max(0.0, seconds)
    whole = int(seconds)
    h, rest = divmod(whole, 3600)
    m, s = divmod(rest, 60)
    text = f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"
    if hundredths:
        text += f".{int((seconds - whole) * 100):02d}"
    return text


def next_ring(alarm, now):
    """When an alarm next goes off after now (a naive local datetime)."""
    hour, minute = alarm["hour"], alarm["minute"]
    days = alarm.get("days") or []
    for ahead in range(0, 8):
        day = now.date() + datetime.timedelta(days=ahead)
        when = datetime.datetime.combine(day, datetime.time(hour, minute))
        if when <= now:
            continue
        if not days or day.weekday() in days:
            return when
    return None


def ring_sound():
    for path in SOUNDS:
        if os.path.exists(path):
            for player in ("pw-play", "paplay"):
                if shutil.which(player):
                    try:
                        subprocess.Popen([player, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        return
                    except OSError:
                        pass
    display = Gdk.Display.get_default()
    if display:
        display.beep()


def set_autostart(enabled):
    """Start Chime quietly at login only while an alarm is on."""
    folder = os.path.join(GLib.get_user_config_dir(), "autostart")
    path = os.path.join(folder, "freemac-chime-alarms.desktop")
    # Before 1.66 this watcher used Chime's own name, which Login Items
    # needs for Chime the app.
    old = os.path.join(folder, "freemac-chime.desktop")
    try:
        with open(old) as f:
            if "--background" in f.read():
                os.remove(old)
    except OSError:
        pass
    if enabled:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write("[Desktop Entry]\nType=Application\nName=Chime alarms\n"
                    "Exec=freemac-chime --background\nNoDisplay=true\n")
    else:
        try:
            os.remove(path)
        except OSError:
            pass


def heading(text):
    label = Gtk.Label(label=text, xalign=0)
    label.get_style_context().add_class("chime-heading")
    return label


def big(text=""):
    label = Gtk.Label(label=text)
    label.get_style_context().add_class("chime-big")
    return label


# -- pages -------------------------------------------------------------------
def placeholder(text):
    # A list's placeholder isn't one of its children, so show_all() misses it.
    label = Gtk.Label(label=text, margin=18)
    label.get_style_context().add_class("dim-label")
    label.show()
    return label


class WorldPage(Gtk.Box):
    def __init__(self, app):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        self.app = app
        self.here = big()
        self.here_date = Gtk.Label()
        self.here_date.get_style_context().add_class("dim-label")
        self.pack_start(self.here, False, False, 0)
        self.pack_start(self.here_date, False, False, 0)

        add_box = Gtk.Box(spacing=6)
        self.search = Gtk.Entry(placeholder_text="Add a city, such as Tokyo or New York", hexpand=True)
        completion = Gtk.EntryCompletion(inline_completion=False, minimum_key_length=2)
        store = Gtk.ListStore(str, str)
        for zone in all_zones():
            store.append([f"{place_name(zone)}  ·  {zone.split('/')[0].replace('_', ' ')}", zone])
        completion.set_model(store)
        completion.set_text_column(0)
        completion.set_match_func(lambda c, key, it: key.lower() in store[it][0].lower())
        completion.connect("match-selected", self.on_pick)
        self.search.set_completion(completion)
        self.search.connect("activate", self.on_enter)
        self.store = store
        add_box.pack_start(self.search, True, True, 0)
        self.pack_start(add_box, False, False, 0)

        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.get_style_context().add_class("frame")
        self.list.set_placeholder(placeholder("No other cities yet"))
        scroller = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.add(self.list)
        self.pack_start(scroller, True, True, 0)
        self.rebuild()

    def on_pick(self, _completion, model, it):
        self.add_zone(model[it][1])
        return True

    def on_enter(self, entry):
        text = entry.get_text().strip().lower()
        for label, zone in self.store:
            if place_name(zone).lower() == text or zone.lower() == text:
                self.add_zone(zone)
                return
        for label, zone in self.store:
            if text and text in label.lower():
                self.add_zone(zone)
                return

    def add_zone(self, zone):
        cities = self.app.data["cities"]
        if zone not in cities:
            cities.append(zone)
            self.app.save()
        self.search.set_text("")
        self.rebuild()

    def remove_zone(self, zone):
        self.app.data["cities"].remove(zone)
        self.app.save()
        self.rebuild()

    def rebuild(self):
        for row in self.list.get_children():
            self.list.remove(row)
        self.rows = []
        for zone in self.app.data["cities"]:
            row = Gtk.ListBoxRow(activatable=False)
            box = Gtk.Box(spacing=12, margin=10)
            names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            names.pack_start(Gtk.Label(label=place_name(zone), xalign=0), False, False, 0)
            diff = Gtk.Label(xalign=0)
            diff.get_style_context().add_class("dim-label")
            names.pack_start(diff, False, False, 0)
            box.pack_start(names, True, True, 0)
            clock = Gtk.Label()
            clock.get_style_context().add_class("chime-city")
            box.pack_start(clock, False, False, 0)
            remove = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON)
            remove.set_relief(Gtk.ReliefStyle.NONE)
            remove.set_tooltip_text(f"Remove {place_name(zone)}")
            remove.connect("clicked", lambda _b, z=zone: self.remove_zone(z))
            box.pack_start(remove, False, False, 0)
            row.add(box)
            self.list.add(row)
            self.rows.append((zone, clock, diff))
        self.list.show_all()
        self.tick()

    def tick(self):
        h24 = uses_24h(self.app.data)
        now = datetime.datetime.now().astimezone()
        self.here.set_text(clock_text(now, h24, seconds=True))
        self.here_date.set_text(now.strftime("%A %-d %B"))
        for zone, clock, diff in self.rows:
            try:
                there = now.astimezone(zoneinfo.ZoneInfo(zone))
            except Exception:  # noqa: BLE001
                continue
            clock.set_text(clock_text(there, h24))
            offset = (there.utcoffset() - now.utcoffset()).total_seconds() / 3600
            day = {0: "Today", 1: "Tomorrow", -1: "Yesterday"}.get((there.date() - now.date()).days, "")
            if offset == 0:
                diff.set_text(f"{day}, same time")
            else:
                hours = f"{abs(offset):g} hour{'s' if abs(offset) != 1 else ''}"
                diff.set_text(f"{day}, {hours} {'ahead' if offset > 0 else 'behind'}")


class AlarmDialog(Gtk.Dialog):
    def __init__(self, parent, alarm=None):
        super().__init__(title="Alarm", transient_for=parent, modal=True, use_header_bar=True)
        self.add_button("Cancel", Gtk.ResponseType.CANCEL)
        self.add_button("Save", Gtk.ResponseType.OK).get_style_context().add_class("suggested-action")
        alarm = alarm or {"hour": 7, "minute": 0, "label": "", "days": []}
        grid = Gtk.Grid(row_spacing=10, column_spacing=10, margin=18)
        self.get_content_area().add(grid)
        self.hour = Gtk.SpinButton.new_with_range(0, 23, 1)
        self.minute = Gtk.SpinButton.new_with_range(0, 59, 1)
        for spin in (self.hour, self.minute):
            spin.set_wrap(True)
            spin.set_orientation(Gtk.Orientation.VERTICAL)
            spin.connect("output", self.two_digits)
        self.hour.set_value(alarm["hour"])
        self.minute.set_value(alarm["minute"])
        time_box = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        time_box.pack_start(self.hour, False, False, 0)
        time_box.pack_start(Gtk.Label(label=":"), False, False, 0)
        time_box.pack_start(self.minute, False, False, 0)
        grid.attach(time_box, 0, 0, 2, 1)
        grid.attach(Gtk.Label(label="Label", xalign=1), 0, 1, 1, 1)
        self.label = Gtk.Entry(text=alarm.get("label", ""), placeholder_text="Alarm", hexpand=True)
        grid.attach(self.label, 1, 1, 1, 1)
        grid.attach(Gtk.Label(label="Repeat", xalign=1), 0, 2, 1, 1)
        days_box = Gtk.Box()
        days_box.get_style_context().add_class("linked")
        self.days = []
        for i, name in enumerate(DAYS):
            toggle = Gtk.ToggleButton(label=name, active=i in alarm.get("days", []))
            days_box.pack_start(toggle, False, False, 0)
            self.days.append(toggle)
        grid.attach(days_box, 1, 2, 1, 1)
        hint = Gtk.Label(label="With no days chosen, the alarm rings once.", xalign=0)
        hint.get_style_context().add_class("dim-label")
        grid.attach(hint, 1, 3, 1, 1)
        self.show_all()

    @staticmethod
    def two_digits(spin):
        spin.set_text(f"{int(spin.get_value()):02d}")
        return True

    def result(self):
        return {"hour": int(self.hour.get_value()), "minute": int(self.minute.get_value()),
                "label": self.label.get_text().strip(),
                "days": [i for i, t in enumerate(self.days) if t.get_active()], "on": True}


class AlarmsPage(Gtk.Box):
    def __init__(self, app):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        self.app = app
        top = Gtk.Box()
        top.pack_start(heading("Alarms"), True, True, 0)
        add = Gtk.Button(label="Add Alarm")
        add.connect("clicked", lambda _b: self.edit(None))
        top.pack_start(add, False, False, 0)
        self.pack_start(top, False, False, 0)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.get_style_context().add_class("frame")
        self.list.set_placeholder(placeholder("No alarms"))
        self.list.connect("row-activated", lambda _l, row: self.edit(row.index))
        scroller = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.add(self.list)
        self.pack_start(scroller, True, True, 0)
        self.rebuild()

    def edit(self, index):
        alarms = self.app.data["alarms"]
        dialog = AlarmDialog(self.get_toplevel(), alarms[index] if index is not None else None)
        if dialog.run() == Gtk.ResponseType.OK:
            if index is None:
                alarms.append(dialog.result())
            else:
                alarms[index] = dialog.result()
            alarms.sort(key=lambda a: (a["hour"], a["minute"]))
            self.app.alarms_changed()
        dialog.destroy()

    def rebuild(self):
        for row in self.list.get_children():
            self.list.remove(row)
        h24 = uses_24h(self.app.data)
        for i, alarm in enumerate(self.app.data["alarms"]):
            row = Gtk.ListBoxRow()
            row.index = i
            box = Gtk.Box(spacing=12, margin=10)
            texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            when = big(clock_text(datetime.datetime(2000, 1, 1, alarm["hour"], alarm["minute"]), h24))
            when.set_xalign(0)
            when.get_style_context().add_class("chime-alarm")
            texts.pack_start(when, False, False, 0)
            days = alarm.get("days") or []
            repeat = ("Every day" if len(days) == 7 else "Weekdays" if days == [0, 1, 2, 3, 4]
                      else "Weekends" if days == [5, 6] else ", ".join(DAYS[d] for d in days) or "Once")
            sub = Gtk.Label(label=" · ".join(filter(None, [alarm.get("label"), repeat])), xalign=0)
            sub.get_style_context().add_class("dim-label")
            texts.pack_start(sub, False, False, 0)
            box.pack_start(texts, True, True, 0)
            switch = Gtk.Switch(active=alarm.get("on", True), valign=Gtk.Align.CENTER)
            switch.connect("notify::active", self.on_switch, i)
            box.pack_start(switch, False, False, 0)
            delete = Gtk.Button.new_from_icon_name("user-trash-symbolic", Gtk.IconSize.BUTTON)
            delete.set_relief(Gtk.ReliefStyle.NONE)
            delete.set_valign(Gtk.Align.CENTER)
            delete.set_tooltip_text("Delete this alarm")
            delete.connect("clicked", self.on_delete, i)
            box.pack_start(delete, False, False, 0)
            row.add(box)
            self.list.add(row)
        self.list.show_all()

    def on_switch(self, switch, _param, index):
        self.app.data["alarms"][index]["on"] = switch.get_active()
        self.app.alarms_changed(rebuild=False)

    def on_delete(self, _button, index):
        del self.app.data["alarms"][index]
        self.app.alarms_changed()


class TimerPage(Gtk.Box):
    def __init__(self, app):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin=18, valign=Gtk.Align.CENTER)
        self.app = app
        self.setter = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        self.spins = []
        for i, (top, unit) in enumerate(((23, "h"), (59, "m"), (59, "s"))):
            spin = Gtk.SpinButton.new_with_range(0, top, 1)
            spin.set_orientation(Gtk.Orientation.VERTICAL)
            spin.set_value(5 if unit == "m" else 0)
            spin.connect("output", AlarmDialog.two_digits)
            self.setter.pack_start(spin, False, False, 0)
            self.setter.pack_start(Gtk.Label(label=unit), False, False, 0)
            self.spins.append(spin)
        self.pack_start(self.setter, False, False, 0)
        self.display = big()
        self.display.set_no_show_all(True)
        self.pack_start(self.display, False, False, 0)
        presets = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        for minutes in (1, 3, 5, 10, 15, 30):
            button = Gtk.Button(label=f"{minutes} min")
            button.connect("clicked", lambda _b, m=minutes: self.start(m * 60))
            presets.pack_start(button, False, False, 0)
        self.presets = presets
        self.pack_start(presets, False, False, 0)
        buttons = Gtk.Box(spacing=12, halign=Gtk.Align.CENTER)
        self.go = Gtk.Button(label="Start")
        self.go.get_style_context().add_class("suggested-action")
        self.go.connect("clicked", self.on_go)
        self.reset = Gtk.Button(label="Cancel", sensitive=False)
        self.reset.connect("clicked", lambda _b: self.cancel())
        buttons.pack_start(self.reset, False, False, 0)
        buttons.pack_start(self.go, False, False, 0)
        self.pack_start(buttons, False, False, 0)
        self.end = None       # monotonic time it rings, while running
        self.left = None      # seconds left, while paused
        self.length = 0

    def start(self, seconds):
        if seconds <= 0:
            return
        self.length = seconds
        self.end = time.monotonic() + seconds
        self.left = None
        self.app.hold_for("timer", True)
        self.refresh()

    def on_go(self, _button):
        if self.end is not None:          # pause
            self.left = self.end - time.monotonic()
            self.end = None
        elif self.left is not None:       # resume
            self.end = time.monotonic() + self.left
            self.left = None
        else:
            h, m, s = (int(sp.get_value()) for sp in self.spins)
            self.start(h * 3600 + m * 60 + s)
        self.refresh()

    def cancel(self):
        self.end = self.left = None
        self.app.hold_for("timer", False)
        self.refresh()

    def refresh(self):
        idle = self.end is None and self.left is None
        self.setter.set_visible(idle)
        self.presets.set_visible(idle)
        self.display.set_visible(not idle)
        self.reset.set_sensitive(not idle)
        self.go.set_label("Start" if idle else "Pause" if self.end is not None else "Resume")
        self.tick()

    def tick(self):
        if self.end is not None:
            remaining = self.end - time.monotonic()
            if remaining <= 0:
                self.cancel()
                self.app.ring("Timer done", f"{duration_text(self.length)} timer finished")
                return
            self.display.set_text(duration_text(remaining + 0.999))
        elif self.left is not None:
            self.display.set_text(duration_text(self.left + 0.999))


class StopwatchPage(Gtk.Box):
    def __init__(self, app):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        self.display = big("00:00.00")
        self.display.set_margin_top(12)
        self.pack_start(self.display, False, False, 0)
        buttons = Gtk.Box(spacing=12, halign=Gtk.Align.CENTER)
        self.lap = Gtk.Button(label="Lap", sensitive=False)
        self.lap.connect("clicked", self.on_lap)
        self.go = Gtk.Button(label="Start")
        self.go.get_style_context().add_class("suggested-action")
        self.go.connect("clicked", self.on_go)
        buttons.pack_start(self.lap, False, False, 0)
        buttons.pack_start(self.go, False, False, 0)
        self.pack_start(buttons, False, False, 0)
        self.laps = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        scroller = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.add(self.laps)
        self.pack_start(scroller, True, True, 0)
        self.started = None   # monotonic start while running
        self.banked = 0.0     # time from earlier runs before a pause
        self.lap_marks = []

    def elapsed(self):
        return self.banked + (time.monotonic() - self.started if self.started is not None else 0)

    def on_go(self, _button):
        if self.started is None:
            self.started = time.monotonic()
            self.go.set_label("Stop")
            self.lap.set_label("Lap")
            self.lap.set_sensitive(True)
        else:
            self.banked = self.elapsed()
            self.started = None
            self.go.set_label("Start")
            self.lap.set_label("Reset")
        self.go.get_style_context().remove_class("suggested-action" if self.started is not None else "destructive-action")
        self.go.get_style_context().add_class("destructive-action" if self.started is not None else "suggested-action")

    def reset(self):
        if self.started is not None:
            self.on_go(None)
        self.banked = 0.0
        self.lap_marks = []
        for row in self.laps.get_children():
            self.laps.remove(row)
        self.lap.set_sensitive(False)
        self.lap.set_label("Lap")
        self.tick()

    def on_lap(self, _button):
        if self.started is None:      # Reset
            if self.banked:
                self.reset()
            return
        total = self.elapsed()
        split = total - (self.lap_marks[-1] if self.lap_marks else 0)
        self.lap_marks.append(total)
        row = Gtk.Box(spacing=12, margin=8)
        row.pack_start(Gtk.Label(label=f"Lap {len(self.lap_marks)}", xalign=0), True, True, 0)
        row.pack_start(Gtk.Label(label=duration_text(split, True)), False, False, 0)
        total_label = Gtk.Label(label=duration_text(total, True))
        total_label.get_style_context().add_class("dim-label")
        row.pack_start(total_label, False, False, 0)
        self.laps.insert(row, 0)
        self.laps.show_all()

    def tick(self):
        self.display.set_text(duration_text(self.elapsed(), True))


# -- window and app ----------------------------------------------------------
class ClockWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Chime")
        self.set_default_size(520, 560)
        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.world = WorldPage(app)
        self.alarms = AlarmsPage(app)
        self.timer = TimerPage(app)
        self.stopwatch = StopwatchPage(app)
        for page, name, title in ((self.world, "world", "World"), (self.alarms, "alarms", "Alarms"),
                                  (self.timer, "timer", "Timer"), (self.stopwatch, "stopwatch", "Stopwatch")):
            self.stack.add_titled(page, name, title)
        header.set_custom_title(Gtk.StackSwitcher(stack=self.stack))
        self.add(self.stack)
        self.show_all()
        self.timer.refresh()
        # Start with nothing focused so the city field shows its hint.
        GLib.idle_add(self.set_focus, None)
        self.connect("delete-event", self.on_close)
        self.connect("key-press-event", self.on_key)
        actions = {
            "close": self.on_close,
            "new-alarm": self.new_alarm,
            "timer-go": lambda: self.show_page("timer") or self.timer.on_go(None),
            "timer-cancel": self.timer.cancel,
            "stopwatch-go": lambda: self.show_page("stopwatch") or self.stopwatch.on_go(None),
            "stopwatch-lap": lambda: self.stopwatch.started is not None and self.stopwatch.on_lap(None),
            "stopwatch-reset": self.stopwatch.reset,
        }
        for name in self.PAGES:
            actions["show-" + name] = lambda n=name: self.show_page(n)
        menus.add_actions(self, actions)

    PAGES = ("world", "alarms", "timer", "stopwatch")

    def show_page(self, name):
        self.stack.set_visible_child_name(name)

    def new_alarm(self):
        self.show_page("alarms")
        self.alarms.edit(None)

    def on_key(self, _widget, event):
        if not event.state & Gdk.ModifierType.CONTROL_MASK:
            return False
        key = Gdk.keyval_name(event.keyval).lower()
        if key in ("1", "2", "3", "4"):
            self.show_page(self.PAGES[int(key) - 1])
        elif key == "n":
            self.new_alarm()
        elif key == "w":
            self.on_close()
        else:
            return False
        return True

    def on_close(self, *_args):
        # Keep the timer and stopwatch state; the app decides whether to stay.
        self.hide()
        self.get_application().window_closed()
        return True

    def tick(self):
        page = self.stack.get_visible_child()
        if page is self.world:
            self.world.tick()
        self.stopwatch.tick()


def menubar():
    return menus.menubar([
        ("_File", [[("New Alarm…", "win.new-alarm", "<Ctrl>n")], [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_View", [[("World", "win.show-world", "<Ctrl>1"), ("Alarms", "win.show-alarms", "<Ctrl>2"),
                    ("Timer", "win.show-timer", "<Ctrl>3"), ("Stopwatch", "win.show-stopwatch", "<Ctrl>4")]]),
        ("_Controls", [
            [("Start or Pause Timer", "win.timer-go", None), ("Cancel Timer", "win.timer-cancel", None)],
            [("Start or Stop Stopwatch", "win.stopwatch-go", None), ("Lap", "win.stopwatch-lap", None),
             ("Reset Stopwatch", "win.stopwatch-reset", None)],
        ]),
    ])


class Chime(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.data = load()
        self.window = None
        self.holds = set()
        self.last_check = datetime.datetime.now().replace(second=0, microsecond=0)
        self.css = Gtk.CssProvider()

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        self.css.load_from_data(b"""
            .chime-big { font-size: 52px; font-weight: 300; font-feature-settings: "tnum"; }
            .chime-alarm { font-size: 30px; }
            .chime-city { font-size: 22px; font-feature-settings: "tnum"; }
            .chime-heading { font-size: 18px; font-weight: bold; }
        """)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), self.css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        for name, accel, callback in (("quit", "<Control>q", lambda *_: self.quit()),):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", callback)
            self.add_action(action)
            self.set_accels_for_action(f"app.{name}", [accel])
        self.set_menubar(menubar())
        GLib.timeout_add(50, self.tick)
        self.hold_for("alarms", self.alarms_on())

    def do_command_line(self, command_line):
        if "--background" not in command_line.get_arguments()[1:]:
            self.do_activate()
        elif not self.alarms_on():
            self.quit_if_idle()
        return 0

    def do_activate(self):
        if self.window is None:
            self.window = ClockWindow(self)
        self.window.present()

    def save(self):
        save(self.data)

    def alarms_on(self):
        return any(a.get("on", True) for a in self.data["alarms"])

    def alarms_changed(self, rebuild=True):
        self.save()
        set_autostart(self.alarms_on())
        self.hold_for("alarms", self.alarms_on())
        if rebuild and self.window:
            self.window.alarms.rebuild()

    def hold_for(self, reason, wanted):
        """Stay running without a window while an alarm or timer is pending."""
        if wanted and reason not in self.holds:
            self.holds.add(reason)
            self.hold()
        elif not wanted and reason in self.holds:
            self.holds.discard(reason)
            self.release()

    def window_closed(self):
        self.quit_if_idle()

    def quit_if_idle(self):
        visible = self.window is not None and self.window.get_visible()
        if not self.holds and not visible:
            GLib.idle_add(self.quit)

    def ring(self, title, body):
        ring_sound()
        beacon.send(title, body, icon="freemac-chime", app="Chime")

    def tick(self):
        now = datetime.datetime.now()
        minute = now.replace(second=0, microsecond=0)
        if minute != self.last_check:
            # Check every minute that passed, so a busy or suspended moment
            # doesn't skip an alarm by more than it has to.
            changed = False
            for alarm in self.data["alarms"]:
                if not alarm.get("on", True):
                    continue
                due = next_ring(alarm, self.last_check)
                if due is not None and self.last_check < due <= minute and minute - due < datetime.timedelta(minutes=5):
                    self.ring(alarm.get("label") or "Alarm", clock_text(due, uses_24h(self.data)))
                    if not alarm.get("days"):
                        alarm["on"] = False
                        changed = True
            self.last_check = minute
            if changed:
                self.alarms_changed()
        if self.window is not None:
            self.window.timer.tick()
            if self.window.get_visible():
                self.window.tick()
        return True


def main():
    Chime().run(sys.argv)


if __name__ == "__main__":
    main()
