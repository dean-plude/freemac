# SPDX-License-Identifier: GPL-3.0-or-later
"""Logbook: screen time.

    freemac-logbook           the window: time spent in each app, today and
                              over the last week, and daily limits
    freemac-logbook --track   started at login: notes which app is in front
                              and keeps the limits

Time counts only while someone is using the computer: not while the screen is
locked, nor after two minutes with no typing or mouse movement (swayidle).
An app with a daily limit gets a notice five minutes before its time is up;
at the limit its windows close, and they close again if it's opened later
that day. A passcode, if one is set, is needed to change a limit.

Original freemac code. Each day's times are kept in
~/.local/share/freemac/logbook/DATE.json (five weeks of them), limits and the
passcode (salted and hashed) in ~/.config/freemac/logbook.json.
"""
import datetime
import hashlib
import json
import os
import secrets
import shutil
import signal
import subprocess
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import apps, menus, style  # noqa: E402

APP_ID = "org.freemac.Logbook"
DATA = os.path.join(GLib.get_user_data_dir(), "freemac", "logbook")
CONFIG = os.path.join(GLib.get_user_config_dir(), "freemac", "logbook.json")
PIDFILE = os.path.join(GLib.get_user_runtime_dir(), "freemac-logbook.pid")
IDLE_AFTER = 120      # seconds without input before time stops counting
KEEP_DAYS = 35
WARN_BEFORE = 300     # seconds


def day_path(day):
    return os.path.join(DATA, day.isoformat() + ".json")


def read_json(path):
    try:
        with open(path) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def load_day(day):
    data = read_json(day_path(day))
    used = data.get("apps") if isinstance(data.get("apps"), dict) else {}
    used = {k: float(v) for k, v in used.items() if isinstance(k, str) and isinstance(v, (int, float)) and v >= 0}
    hours = data.get("hours")
    if not (isinstance(hours, list) and len(hours) == 24 and all(isinstance(h, (int, float)) for h in hours)):
        hours = [0.0] * 24
    return {"apps": used, "hours": [float(h) for h in hours]}


def load_config():
    data = read_json(CONFIG)
    limits = data.get("limits") if isinstance(data.get("limits"), dict) else {}
    data["limits"] = {k: int(v) for k, v in limits.items() if isinstance(v, int) and v > 0}
    return data


def check_passcode(config, code):
    salt, digest = config.get("salt"), config.get("passcode")
    if not (isinstance(salt, str) and isinstance(digest, str)):
        return True
    return secrets.compare_digest(hashlib.sha256((salt + code).encode()).hexdigest(), digest)


def set_passcode(config, code):
    if code:
        config["salt"] = secrets.token_hex(8)
        config["passcode"] = hashlib.sha256((config["salt"] + code).encode()).hexdigest()
    else:
        config.pop("salt", None)
        config.pop("passcode", None)


def duration(seconds, short=False):
    minutes = int(seconds // 60)
    if minutes < 1:
        return "less than a minute" if not short else "< 1 min"
    hours, minutes = divmod(minutes, 60)
    if hours and minutes:
        return f"{hours} h {minutes} min"
    if hours:
        return f"{hours} h"
    return f"{minutes} min"


# ---------------------------------------------------------------- the tracker

NOT_COUNTED = {"freemac-pier", "org.freemac.pier", "freemac-topline", "org.freemac.topline",
               "freemac-strata", "org.freemac.strata", "gtklock"}


def counted(view):
    """The app a focused window belongs to, or None for the desktop itself."""
    from .wfipc import is_app_window
    app = view.get("app-id") or ""
    if not app or not is_app_window(view) or app.lower() in NOT_COUNTED:
        return None
    return app

class Tracker:
    def __init__(self):
        from . import wfipc
        self.wfipc = wfipc
        self.wf = None
        self.current = None
        self.active = True
        self.locked = False
        self.last = time.monotonic()
        self.today = datetime.date.today()
        self.day = load_day(self.today)
        self.config = load_config()
        self.config_stamp = 0
        self.warned = set()
        self.stopped_at = {}
        self.dirty = False
        self.idle = None
        self._connect()
        self._start_idle_watch()
        self._tidy()
        GLib.timeout_add_seconds(10, self._tick)
        GLib.timeout_add_seconds(30, self._save)

    def _connect(self):
        try:
            self.wf = self.wfipc.Wayfire(on_event=self._event)
            self.current = counted(self.wf.focused() or {})
        except (OSError, ConnectionError, ValueError):
            self.wf = None
            GLib.timeout_add_seconds(5, lambda: self._connect() and False)
        return self.wf is not None

    def _start_idle_watch(self):
        if not shutil.which("swayidle"):
            return
        try:
            self.idle = subprocess.Popen(["swayidle", "timeout", str(IDLE_AFTER), "echo idle",
                                          "resume", "echo active"],
                                         stdout=subprocess.PIPE, text=True, bufsize=1,
                                         preexec_fn=die_with_parent)
        except OSError:
            return
        GLib.io_add_watch(self.idle.stdout.fileno(), GLib.IO_IN | GLib.IO_HUP, self._idle_line)

    def _idle_line(self, _fd, condition):
        line = self.idle.stdout.readline() if condition & GLib.IO_IN else ""
        if not line:
            return False
        self._account()
        self.active = line.strip() != "idle"
        return True

    def _locked(self):
        try:
            return subprocess.run(["pgrep", "-x", "gtklock"], capture_output=True, timeout=2).returncode == 0
        except (OSError, subprocess.SubprocessError):
            return False

    def _account(self):
        now = time.monotonic()
        spent = min(now - self.last, 60.0)   # a long gap is a sleep, not use
        self.last = now
        if datetime.date.today() != self.today:
            self._save()
            self.today = datetime.date.today()
            self.day = load_day(self.today)
            self.warned.clear()
            self.stopped_at.clear()
        if self.active and not self.locked and self.current and spent > 0:
            self.day["apps"][self.current] = self.day["apps"].get(self.current, 0.0) + spent
            self.day["hours"][datetime.datetime.now().hour] += spent
            self.dirty = True

    def _event(self, msg):
        kind = msg.get("event")
        if kind not in ("view-focused", "view-unmapped", "view-app-id-changed"):
            return
        self._account()
        view = msg.get("view") or {}
        if kind != "view-focused" or not view:
            view = (self.wf.focused() if self.wf else None) or {}
        self.current = counted(view)
        self._check_limit()

    def _tick(self):
        self._account()
        self.locked = self._locked()
        self._check_limit()
        return True

    def _reload_config(self):
        try:
            stamp = os.stat(CONFIG).st_mtime
        except OSError:
            stamp = 0
        if stamp != self.config_stamp:
            self.config_stamp = stamp
            self.config = load_config()

    def _check_limit(self):
        app = self.current
        if not app:
            return
        self._reload_config()
        limit = self.config["limits"].get(app)
        if not limit or app.lower() in OWN_IDS:
            return
        used = self.day["apps"].get(app, 0.0)
        name = apps.display_name(app)
        if used >= limit * 60:
            now = time.monotonic()
            if now - self.stopped_at.get(app, -999) > 20:
                self.stopped_at[app] = now
                notify(f"Time's up for {name}",
                       f"{name} has had its {duration(limit * 60)} for today.")
            if self.wf:
                try:
                    self.wf.quit(app)
                except (OSError, ConnectionError, ValueError):
                    pass
        elif used >= limit * 60 - WARN_BEFORE and app not in self.warned:
            self.warned.add(app)
            left = max(1, round((limit * 60 - used) / 60))
            notify(f"{left} minute{'s' if left != 1 else ''} left for {name}",
                   f"{name} has a limit of {duration(limit * 60)} a day.")

    def _save(self):
        if self.dirty:
            write_json(day_path(self.today), {"apps": {k: round(v, 1) for k, v in self.day["apps"].items()},
                                              "hours": [round(h, 1) for h in self.day["hours"]]})
            self.dirty = False
        return True

    def _tidy(self):
        oldest = datetime.date.today() - datetime.timedelta(days=KEEP_DAYS)
        try:
            for name in os.listdir(DATA):
                try:
                    if datetime.date.fromisoformat(name[:10]) < oldest:
                        os.remove(os.path.join(DATA, name))
                except ValueError:
                    continue
        except OSError:
            pass


def die_with_parent():
    """swayidle ends with the tracker, however the tracker ends."""
    try:
        import ctypes
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG
    except (OSError, AttributeError):
        pass


def notify(summary, body):
    from . import beacon
    beacon.send(summary, body, icon="freemac-logbook", app="Logbook")


def tracker_running():
    try:
        with open(PIDFILE) as f:
            pid = int(f.read().strip())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return b"--track" in f.read()
    except (OSError, ValueError):
        return False


def track():
    if tracker_running():
        return 0
    os.makedirs(os.path.dirname(PIDFILE), exist_ok=True)
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    loop = GLib.MainLoop()
    tracker = Tracker()

    def stop(*_a):
        tracker._account()
        tracker._save()
        if tracker.idle:
            tracker.idle.terminate()
        loop.quit()

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)
    loop.run()
    return 0


# ---------------------------------------------------------------- the window

class Chart(Gtk.DrawingArea):
    """Bars: 24 hours of a day, or the last seven days."""

    def __init__(self):
        super().__init__()
        self.values = []
        self.labels = []
        self.set_size_request(-1, 170)
        self.connect("draw", self._draw)

    def set(self, values, labels):
        self.values, self.labels = values, labels
        self.queue_draw()

    def _draw(self, _w, cr):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        dark = self.get_style_context().lookup_color("theme_bg_color")[1].red < 0.5
        fg = (0.92, 0.92, 0.94) if dark else (0.12, 0.12, 0.14)
        if not self.values:
            return
        top = max(max(self.values), 60.0)
        n = len(self.values)
        left, right, bottom, head = 12, 12, 22, 10
        slot = (width - left - right) / n
        bar = max(3.0, slot * (0.62 if n > 10 else 0.5))
        for i, v in enumerate(self.values):
            h = (height - bottom - head) * v / top
            x = left + i * slot + (slot - bar) / 2
            cr.set_source_rgba(*fg, 0.08)
            cr.rectangle(x, head, bar, height - bottom - head)
            cr.fill()
            if h > 0:
                cr.set_source_rgb(0.04, 0.49, 1.0)
                r = min(bar / 2, 4)
                y = height - bottom - h
                cr.new_sub_path()
                cr.arc(x + r, y + r, r, 3.1416, 4.7124)
                cr.arc(x + bar - r, y + r, r, 4.7124, 0)
                cr.line_to(x + bar, height - bottom)
                cr.line_to(x, height - bottom)
                cr.close_path()
                cr.fill()
            label = self.labels[i] if i < len(self.labels) else ""
            if label:
                cr.set_source_rgba(*fg, 0.55)
                cr.select_font_face("Inter")
                cr.set_font_size(11)
                ext = cr.text_extents(label)
                cr.move_to(x + bar / 2 - ext.width / 2, height - 6)
                cr.show_text(label)


OWN_IDS = {"freemac-logbook", APP_ID.lower()}


def finish_row(box):
    row = Gtk.ListBoxRow(activatable=False)
    row.add(box)
    return row


class Meter(Gtk.DrawingArea):
    """A thin rounded bar: this app's share of the longest time."""

    def __init__(self, fraction):
        super().__init__()
        self.fraction = max(0.0, min(1.0, fraction))
        self.set_size_request(-1, 6)
        self.connect("draw", self._draw)

    def _draw(self, _w, cr):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        dark = self.get_style_context().lookup_color("theme_bg_color")[1].red < 0.5
        for fill, w in ((((1, 1, 1, 0.12) if dark else (0, 0, 0, 0.08)), width),
                        ((0.04, 0.49, 1.0, 1), max(height, width * self.fraction))):
            r = height / 2
            cr.new_sub_path()
            cr.arc(r, r, r, 1.5708, 4.7124)
            cr.arc(w - r, r, r, 4.7124, 1.5708)
            cr.close_path()
            cr.set_source_rgba(*fill)
            cr.fill()


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Logbook")
        self.set_default_size(720, 720)
        self.config = load_config()
        self.span = "today"
        header = Gtk.HeaderBar(show_close_button=True, title="Logbook")
        self.header = header
        self.set_titlebar(header)
        switch = Gtk.Box()
        switch.get_style_context().add_class("linked")
        self.today_button = Gtk.RadioButton.new_with_label_from_widget(None, "Today")
        self.week_button = Gtk.RadioButton.new_with_label_from_widget(self.today_button, "Last 7 Days")
        for button, span in ((self.today_button, "today"), (self.week_button, "week")):
            button.set_mode(False)
            button.connect("toggled", self._span_toggled, span)
            switch.pack_start(button, False, False, 0)
        header.set_custom_title(switch)

        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        page.set_border_width(22)
        self.total = Gtk.Label(xalign=0)
        self.total_note = Gtk.Label(xalign=0)
        self.total_note.get_style_context().add_class("dim-label")
        page.pack_start(self.total_note, False, False, 0)
        page.pack_start(self.total, False, False, 0)
        self.chart = Chart()
        page.pack_start(self.chart, False, False, 8)
        heading = Gtk.Label(xalign=0)
        heading.set_markup("<b>Apps</b>")
        page.pack_start(heading, False, False, 6)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.get_style_context().add_class("frame")
        page.pack_start(self.list, False, False, 0)
        self.empty = Gtk.Label(label="Nothing yet. Time spent in apps shows here.")
        self.empty.get_style_context().add_class("dim-label")
        page.pack_start(self.empty, False, False, 12)
        self.empty.set_no_show_all(True)
        self.list.set_no_show_all(True)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.add(page)
        self.add(scroller)
        menus.add_actions(self, {"close": self.close, "today": lambda: self.today_button.set_active(True),
                                 "week": lambda: self.week_button.set_active(True),
                                 "passcode": self.passcode_dialog})
        if not tracker_running():
            try:
                subprocess.Popen(["freemac-logbook", "--track"], start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                pass
        self.refresh()
        GLib.timeout_add_seconds(30, self._timer)
        self.show_all()

    def _timer(self):
        if self.get_window() is None:
            return False
        self.refresh()
        return True

    def _span_toggled(self, button, span):
        if button.get_active():
            self.span = span
            self.refresh()

    def refresh(self):
        today = datetime.date.today()
        if self.span == "today":
            day = load_day(today)
            used = day["apps"]
            self.chart.set([h / 60 for h in day["hours"]],
                           ["12 AM" if i == 0 else "6 AM" if i == 6 else "12 PM" if i == 12 else "6 PM" if i == 18
                            else "" for i in range(24)])
            total = sum(used.values())
            self.total_note.set_text("Today")
        else:
            used = {}
            values, labels = [], []
            for back in range(6, -1, -1):
                date = today - datetime.timedelta(days=back)
                day = load_day(date)
                for app, secs in day["apps"].items():
                    used[app] = used.get(app, 0.0) + secs
                values.append(sum(day["apps"].values()) / 60)
                labels.append("Today" if back == 0 else date.strftime("%a"))
            self.chart.set(values, labels)
            total = sum(used.values())
            self.total_note.set_text(f"A day on average: {duration(total / 7)}")
        self.total.set_markup(f"<span size='26000' weight='700'>{GLib.markup_escape_text(duration(total))}</span>")
        for row in self.list.get_children():
            self.list.remove(row)
        top = max(used.values()) if used else 1
        for app, secs in sorted(used.items(), key=lambda kv: -kv[1]):
            if secs < 30:
                continue
            self.list.add(self._row(app, secs, top))
        for row in self.list.get_children():
            row.show_all()
        has = bool(self.list.get_children())
        self.list.set_visible(has)
        self.empty.set_visible(not has)

    def _row(self, app, secs, top):
        box = Gtk.Box(spacing=12)
        box.set_border_width(10)
        icon = Gtk.Image.new_from_gicon(apps.icon_for(app), Gtk.IconSize.DND)
        icon.set_pixel_size(32)
        box.pack_start(icon, False, False, 0)
        middle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        name = Gtk.Label(label=apps.display_name(app), xalign=0, ellipsize=Pango.EllipsizeMode.END)
        middle.pack_start(name, False, False, 0)
        middle.pack_start(Meter(secs / top), False, False, 0)
        box.pack_start(middle, True, True, 0)
        time_label = Gtk.Label(label=duration(secs, short=True))
        time_label.set_width_chars(10)
        time_label.set_xalign(1)
        box.pack_start(time_label, False, False, 0)
        if app.lower() in OWN_IDS:   # Logbook itself is where limits are changed
            spacer = Gtk.Box()
            spacer.set_size_request(118, -1)
            box.pack_start(spacer, False, False, 0)
            return finish_row(box)
        limit = self.config["limits"].get(app)
        button = Gtk.MenuButton(label=f"Limit {duration(limit * 60)}" if limit else "Set Limit")
        button.set_relief(Gtk.ReliefStyle.NONE if not limit else Gtk.ReliefStyle.NORMAL)
        button.set_size_request(118, -1)
        button.set_popover(self._limit_popover(button, app, limit))
        box.pack_start(button, False, False, 0)
        return finish_row(box)

    def _limit_popover(self, button, app, limit):
        pop = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_border_width(14)
        title = Gtk.Label(xalign=0)
        title.set_markup(f"<b>A daily limit for {GLib.markup_escape_text(apps.display_name(app))}</b>")
        box.pack_start(title, False, False, 0)
        line = Gtk.Box(spacing=6)
        hours = Gtk.SpinButton.new_with_range(0, 12, 1)
        minutes = Gtk.SpinButton.new_with_range(0, 55, 5)
        current = limit or 60
        hours.set_value(current // 60)
        minutes.set_value(current % 60)
        line.pack_start(hours, False, False, 0)
        line.pack_start(Gtk.Label(label="h"), False, False, 0)
        line.pack_start(minutes, False, False, 0)
        line.pack_start(Gtk.Label(label="min a day"), False, False, 0)
        box.pack_start(line, False, False, 0)
        buttons = Gtk.Box(spacing=6, halign=Gtk.Align.END)
        if limit:
            off = Gtk.Button(label="No Limit")
            off.connect("clicked", lambda _b: (pop.popdown(), self.change_limit(app, 0)))
            buttons.pack_start(off, False, False, 0)
        save = Gtk.Button(label="Set Limit")
        save.get_style_context().add_class("suggested-action")
        save.connect("clicked", lambda _b: (pop.popdown(),
                                            self.change_limit(app, int(hours.get_value()) * 60
                                                              + int(minutes.get_value()))))
        buttons.pack_start(save, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        note = Gtk.Label(label="Five minutes before the time is up, a notice says so.\n"
                               "At the limit, the app's windows close for the rest of the day.", xalign=0)
        note.get_style_context().add_class("dim-label")
        box.pack_start(note, False, False, 0)
        box.show_all()
        pop.add(box)
        return pop

    def change_limit(self, app, minutes):
        self.config = load_config()
        if self.config.get("passcode") and not self.ask_passcode("Enter the passcode to change a limit."):
            return
        if minutes > 0:
            self.config["limits"][app] = minutes
        else:
            self.config["limits"].pop(app, None)
        write_json(CONFIG, self.config)
        self.refresh()

    def ask_passcode(self, text):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK_CANCEL,
                                   text="Passcode", secondary_text=text)
        entry = Gtk.Entry(visibility=False, input_purpose=Gtk.InputPurpose.PIN, activates_default=True)
        dialog.get_message_area().pack_start(entry, False, False, 0)
        dialog.set_default_response(Gtk.ResponseType.OK)
        entry.show()
        ok = False
        while dialog.run() == Gtk.ResponseType.OK:
            if check_passcode(self.config, entry.get_text()):
                ok = True
                break
            dialog.format_secondary_text("That passcode isn't right. Try again.")
            entry.set_text("")
        dialog.destroy()
        return ok

    def passcode_dialog(self):
        self.config = load_config()
        has = bool(self.config.get("passcode"))
        if has and not self.ask_passcode("Enter the current passcode."):
            return
        dialog = Gtk.Dialog(title="Limits Passcode", transient_for=self, modal=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        if has:
            dialog.add_button("Turn Off Passcode", 1)
        dialog.add_button("Set Passcode", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        area = dialog.get_content_area()
        area.set_spacing(8)
        area.set_border_width(16)
        note = Gtk.Label(label="With a passcode, only someone who knows it can change a limit.\n"
                               "Use four numbers or more.", xalign=0)
        area.pack_start(note, False, False, 0)
        first = Gtk.Entry(visibility=False, placeholder_text="New passcode", input_purpose=Gtk.InputPurpose.PIN)
        second = Gtk.Entry(visibility=False, placeholder_text="Again", input_purpose=Gtk.InputPurpose.PIN,
                           activates_default=True)
        area.pack_start(first, False, False, 0)
        area.pack_start(second, False, False, 0)
        problem = Gtk.Label(xalign=0)
        area.pack_start(problem, False, False, 0)
        area.show_all()
        while True:
            answer = dialog.run()
            if answer == 1:
                set_passcode(self.config, "")
                break
            if answer != Gtk.ResponseType.OK:
                dialog.destroy()
                return
            code = first.get_text()
            if len(code) < 4:
                problem.set_markup("<span foreground='#d33'>Use four numbers or more.</span>")
            elif code != second.get_text():
                problem.set_markup("<span foreground='#d33'>The two don't match.</span>")
            else:
                set_passcode(self.config, code)
                break
        dialog.destroy()
        write_json(CONFIG, self.config)


def menubar():
    return menus.menubar([
        ("_File", [[("Close", "win.close", "<Ctrl>w")]]),
        ("_View", [[("Today", "win.today", "<Ctrl>1"), ("Last 7 Days", "win.week", "<Ctrl>2")]]),
        ("_Limits", [[("Passcode…", "win.passcode", None)]]),
    ])


class Logbook(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.close", "<Control>w"), ("win.today", "<Control>1"), ("win.week", "<Control>2")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    if "--track" in sys.argv[1:]:
        GLib.set_prgname("freemac-logbook-track")
        return track()
    GLib.set_prgname("freemac-logbook")
    return Logbook().run(sys.argv[:1])


if __name__ == "__main__":
    sys.exit(main())
