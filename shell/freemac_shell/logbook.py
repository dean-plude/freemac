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
that day, unless someone gives it more time. Downtime is a part of each day
(bedtime, say) when only the apps you always allow can be used, with a notice
five minutes before it starts; freemac's own Drawer, Dials, Guide and Logbook
always work. Apps you always allow have no daily limit either. A passcode, if
one is set, is needed to change any of this.

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

from . import alert, apps, menus, style  # noqa: E402

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
    allowed = data.get("allowed") if isinstance(data.get("allowed"), list) else []
    data["allowed"] = [a for a in allowed if isinstance(a, str) and a.endswith(".desktop")]
    down = data.get("downtime") if isinstance(data.get("downtime"), dict) else {}
    data["downtime"] = {"on": down.get("on") is True,
                        "start": _minutes(down.get("start"), DOWNTIME_START),
                        "end": _minutes(down.get("end"), DOWNTIME_END),
                        "paused": down.get("paused") if isinstance(down.get("paused"), (int, float)) else 0}
    extra = data.get("extra") if isinstance(data.get("extra"), dict) else {}
    given = extra.get("apps") if isinstance(extra.get("apps"), dict) else {}
    data["extra"] = {"day": extra.get("day") if isinstance(extra.get("day"), str) else "",
                     "apps": {k: int(v) for k, v in given.items() if isinstance(v, int) and v > 0}}
    return data


# ---- Downtime and Always Allowed --------------------------------------------------
DOWNTIME_START = 22 * 60   # minutes after midnight
DOWNTIME_END = 7 * 60
MORE_TIME = 15             # minutes, for "15 More Minutes"

# freemac's own apps, which keep working in downtime and have no limit: the
# desktop and Drawer, Dials, Guide, Logbook, Force Quit, the password and
# Restart questions, and Seek.
ALWAYS_IDS = {"freemac-drawer", "org.freemac.drawer", "freemac-backdrop", "freemac-desktop-window",
              "freemac-dials", "org.freemac.dials", "freemac-guide", "org.freemac.guide",
              "freemac-logbook", "org.freemac.logbook", "freemac-force-quit", "org.freemac.forcequit",
              "freemac-power", "freemac-seek", "freemac-hail", "gtklock",
              "polkit-mate-authentication-agent-1"}
ALWAYS_DESKTOP = {"freemac-drawer.desktop", "freemac-dials.desktop", "freemac-guide.desktop",
                  "freemac-logbook.desktop", "freemac-force-quit.desktop"}


def _minutes(text, fallback):
    """"21:30" -> 1290 minutes after midnight (a number is taken as minutes)."""
    if isinstance(text, int) and not isinstance(text, bool):
        return text if 0 <= text < 1440 else fallback
    try:
        hour, minute = (int(part) for part in str(text).split(":"))
    except (TypeError, ValueError):
        return fallback
    return hour * 60 + minute if 0 <= hour < 24 and 0 <= minute < 60 else fallback


def hhmm(minutes):
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def clock(minutes):
    """How the menu bar would write the time: 9:30 PM, or 21:30."""
    when = datetime.time(minutes // 60 % 24, minutes % 60)
    return when.strftime("%H:%M") if style.prefs().get("clock") == "24" else when.strftime("%-I:%M %p")


def in_downtime(config, now=None):
    down = config["downtime"]
    now = now or datetime.datetime.now()
    if not down["on"] or down["start"] == down["end"] or down["paused"] > now.timestamp():
        return False
    minute = now.hour * 60 + now.minute
    if down["start"] < down["end"]:
        return down["start"] <= minute < down["end"]
    return minute >= down["start"] or minute < down["end"]   # past midnight


def minutes_to_downtime(config, now=None):
    """Minutes until downtime starts, or None while it's on or turned off."""
    down = config["downtime"]
    now = now or datetime.datetime.now()
    if not down["on"] or down["start"] == down["end"] or in_downtime(config, now):
        return None
    return (down["start"] - (now.hour * 60 + now.minute)) % 1440


def desktop_id(app):
    info = apps.app_info(app)
    return info.get_id() if info else None


def always_allowed(config, app):
    if app.lower() in ALWAYS_IDS:
        return True
    found = desktop_id(app)
    return bool(found) and (found in ALWAYS_DESKTOP or found in config["allowed"])


def extra_minutes(config, app, day=None):
    extra = config["extra"]
    if extra["day"] != (day or datetime.date.today()).isoformat():
        return 0
    return extra["apps"].get(app, 0)


def limit_for(config, app):
    """Minutes the app may be used today, counting any time given since; None
    for no limit."""
    limit = config["limits"].get(app)
    if not limit or always_allowed(config, app):
        return None
    return limit + extra_minutes(config, app)


# Limit adult websites: a NetworkManager setting written by the helper.
FAMILY_CONF = "/etc/NetworkManager/conf.d/90-freemac-family.conf"
FAMILY_HELPER = "/usr/libexec/freemac-family-helper"


def websites_limited():
    return os.path.exists(FAMILY_CONF)


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
        self._warn_downtime()
        return True

    def _warn_downtime(self):
        self._reload_config()
        left = minutes_to_downtime(self.config)
        if left is None or left > 5:
            return
        key = ("downtime", self.today.isoformat(), self.config["downtime"]["start"])
        if key in self.warned:
            return
        self.warned.add(key)
        down = self.config["downtime"]
        notify(f"Downtime starts in {left} minute{'s' if left != 1 else ''}" if left else "Downtime is starting",
               f"From {clock(down['start'])} until {clock(down['end'])}, only the apps you always allow "
               "can be used.")

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
        if app.lower() in OWN_IDS:
            return
        name = apps.display_name(app)
        if in_downtime(self.config) and not always_allowed(self.config, app):
            now = time.monotonic()
            if now - self.stopped_at.get(("downtime", app), -999) > 20:
                self.stopped_at[("downtime", app)] = now
                notify(f"{name} is off during downtime",
                       f"It can be used again at {clock(self.config['downtime']['end'])}.")
            if self.wf:
                try:
                    self.wf.quit(app)
                except (OSError, ConnectionError, ValueError):
                    pass
            return
        limit = limit_for(self.config, app)
        if not limit:
            return
        used = self.day["apps"].get(app, 0.0)
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
        elif used >= limit * 60 - WARN_BEFORE and (app, limit) not in self.warned:
            self.warned.add((app, limit))
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
        page.pack_start(self._downtime_box(), False, False, 18)
        page.pack_start(self._allowed_box(), False, False, 0)
        page.pack_start(self._websites_box(), False, False, 18)
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

    # ---- Downtime and Always Allowed ----------------------------------------------
    def _section(self, title):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        heading = Gtk.Label(xalign=0)
        heading.set_markup(f"<b>{title}</b>")
        box.pack_start(heading, False, False, 0)
        frame = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        frame.get_style_context().add_class("frame")
        box.pack_start(frame, False, False, 0)
        return box, frame

    @staticmethod
    def _line():
        line = Gtk.Box(spacing=12)
        for side in ("top", "bottom", "start", "end"):
            getattr(line, "set_margin_" + side)(10)
        return line

    def _time_combo(self, minutes):
        combo = Gtk.ComboBoxText()
        for step in range(0, 1440, 30):
            combo.append(hhmm(step), clock(step))
        if minutes % 30:
            combo.append(hhmm(minutes), clock(minutes))
        combo.set_active_id(hhmm(minutes))
        combo.connect("changed", lambda _c: self._downtime_changed())
        return combo

    def _downtime_box(self):
        box, frame = self._section("Downtime")
        down = self.config["downtime"]
        line = self._line()
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        words.pack_start(Gtk.Label(label="Downtime", xalign=0), False, False, 0)
        note = Gtk.Label(label="Time away from the screen. Only the apps you always allow, and freemac's own "
                               "Drawer, Dials and Guide, can be used. A notice comes five minutes before.",
                         xalign=0, wrap=True)
        note.get_style_context().add_class("dim-label")
        words.pack_start(note, False, False, 0)
        line.pack_start(words, True, True, 0)
        self.downtime_switch = Gtk.Switch(active=down["on"], valign=Gtk.Align.CENTER)
        self.downtime_switch.connect("notify::active", lambda *_: self._downtime_changed())
        line.pack_end(self.downtime_switch, False, False, 0)
        frame.add(line)
        times = self._line()
        times.pack_start(Gtk.Label(label="From"), False, False, 0)
        self.downtime_from = self._time_combo(down["start"])
        times.pack_start(self.downtime_from, False, False, 0)
        times.pack_start(Gtk.Label(label="to"), False, False, 0)
        self.downtime_to = self._time_combo(down["end"])
        times.pack_start(self.downtime_to, False, False, 0)
        times.pack_start(Gtk.Label(label="every day"), False, False, 0)
        frame.add(times)
        now = self._line()
        self.downtime_now = Gtk.Label(xalign=0)
        now.pack_start(self.downtime_now, True, True, 0)
        more = Gtk.Button(label=f"{MORE_TIME} More Minutes")
        more.connect("clicked", lambda _b: self._pause_downtime())
        now.pack_end(more, False, False, 0)
        self.downtime_now_row = Gtk.ListBoxRow(activatable=False)
        self.downtime_now_row.add(now)
        self.downtime_now_row.set_no_show_all(True)
        frame.add(self.downtime_now_row)
        self._downtime_shown()
        return box

    def _downtime_shown(self):
        """Put the switch and times back as they're kept, and say whether
        downtime is on now."""
        self.updating = True
        down = self.config["downtime"]
        self.downtime_switch.set_active(down["on"])
        for combo, minutes in ((self.downtime_from, down["start"]), (self.downtime_to, down["end"])):
            if not combo.set_active_id(hhmm(minutes)):
                combo.append(hhmm(minutes), clock(minutes))
                combo.set_active_id(hhmm(minutes))
            combo.set_sensitive(down["on"])
        self.updating = False
        if in_downtime(self.config):
            self.downtime_now.set_text(f"Downtime until {clock(down['end'])}")
            self.downtime_now_row.get_child().show_all()   # the row ignores show_all
            self.downtime_now_row.show()
        else:
            self.downtime_now_row.hide()

    def _change_config(self, change, ask):
        """Re-read the settings, ask for the passcode if there is one, then
        change and keep them. Returns whether it was changed."""
        self.config = load_config()
        if self.config.get("passcode") and not self.ask_passcode(ask):
            return False
        change(self.config)
        write_json(CONFIG, {**self.config, "downtime": {**self.config["downtime"],
                                                        "start": hhmm(self.config["downtime"]["start"]),
                                                        "end": hhmm(self.config["downtime"]["end"])}})
        self.config = load_config()
        return True

    def _downtime_changed(self):
        if getattr(self, "updating", False):
            return
        on = self.downtime_switch.get_active()
        start = _minutes(self.downtime_from.get_active_id(), DOWNTIME_START)
        end = _minutes(self.downtime_to.get_active_id(), DOWNTIME_END)

        def change(config):
            config["downtime"].update(on=on, start=start, end=end, paused=0)
        self._change_config(change, "Enter the passcode to change downtime.")
        self._downtime_shown()

    def _pause_downtime(self):
        until = time.time() + MORE_TIME * 60
        if self._change_config(lambda config: config["downtime"].update(paused=until),
                               f"Enter the passcode to give {MORE_TIME} more minutes."):
            self._downtime_shown()

    def _allowed_box(self):
        box, self.allowed_list = self._section("Always Allowed")
        add = Gtk.Button(label="+", tooltip_text="Always allow an app", halign=Gtk.Align.START)
        add.connect("clicked", lambda _b: self._add_allowed())
        box.pack_start(add, False, False, 0)
        note = Gtk.Label(label="These apps can be used during downtime, and have no daily limit.",
                         xalign=0, wrap=True)
        note.get_style_context().add_class("dim-label")
        box.pack_start(note, False, False, 0)
        self._fill_allowed()
        return box

    def _fill_allowed(self):
        for row in self.allowed_list.get_children():
            self.allowed_list.remove(row)
        found = []
        for desktop in self.config["allowed"]:
            try:
                info = Gio.DesktopAppInfo.new(desktop)
            except TypeError:
                info = None
            if info:
                found.append(info)
        if not found:
            empty = Gtk.Label(label="No apps yet. Drawer, Dials, Guide and Logbook always work.", xalign=0)
            empty.get_style_context().add_class("dim-label")
            line = self._line()
            line.pack_start(empty, True, True, 0)
            self.allowed_list.add(line)
        for info in sorted(found, key=lambda i: (i.get_display_name() or "").lower()):
            line = self._line()
            icon = info.get_icon()
            image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.DND) if icon else Gtk.Image()
            image.set_pixel_size(28)
            line.pack_start(image, False, False, 0)
            line.pack_start(Gtk.Label(label=info.get_display_name() or info.get_name(), xalign=0), True, True, 0)
            remove = Gtk.Button(label="\u2212", tooltip_text="Don't always allow it")
            remove.set_relief(Gtk.ReliefStyle.NONE)
            remove.connect("clicked", lambda _b, d=info.get_id(): self._remove_allowed(d))
            line.pack_end(remove, False, False, 0)
            self.allowed_list.add(line)
        self.allowed_list.show_all()

    def _add_allowed(self):
        from .dials_login import choose_app
        desktop = choose_app(self, "Always Allow", set(self.config["allowed"]) | ALWAYS_DESKTOP)
        if desktop and self._change_config(
                lambda config: config["allowed"].append(desktop) if desktop not in config["allowed"] else None,
                "Enter the passcode to always allow an app."):
            self._fill_allowed()
            self.refresh()

    def _remove_allowed(self, desktop):
        if self._change_config(lambda config: config.update(allowed=[a for a in config["allowed"] if a != desktop]),
                               "Enter the passcode to change Always Allowed."):
            self._fill_allowed()
            self.refresh()

    def give_more_time(self, app):
        today = datetime.date.today().isoformat()

        def change(config):
            if config["extra"]["day"] != today:
                config["extra"] = {"day": today, "apps": {}}
            config["extra"]["apps"][app] = config["extra"]["apps"].get(app, 0) + MORE_TIME
        if self._change_config(change, f"Enter the passcode to give {MORE_TIME} more minutes."):
            self.refresh()

    # ---- Limit adult websites --------------------------------------------------------
    def _websites_box(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        heading = Gtk.Label(xalign=0)
        heading.set_markup("<b>Content</b>")
        box.pack_start(heading, False, False, 0)
        frame = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        frame.get_style_context().add_class("frame")
        line = Gtk.Box(spacing=12)
        for side in ("top", "bottom", "start", "end"):
            getattr(line, "set_margin_" + side)(10)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        words.pack_start(Gtk.Label(label="Limit adult websites", xalign=0), False, False, 0)
        note = Gtk.Label(label="Websites for grown-ups, and ones known to spread harm, won't open in any "
                               "browser on this computer, for everyone who uses it.", xalign=0, wrap=True)
        note.get_style_context().add_class("dim-label")
        words.pack_start(note, False, False, 0)
        line.pack_start(words, True, True, 0)
        self.websites = Gtk.Switch(active=websites_limited(), valign=Gtk.Align.CENTER)
        self.websites_handler = self.websites.connect("notify::active", self._websites_toggled)
        line.pack_end(self.websites, False, False, 0)
        frame.add(line)
        box.pack_start(frame, False, False, 0)
        return box

    def _websites_set(self, on):
        with self.websites.handler_block(self.websites_handler):
            self.websites.set_active(on)

    def _websites_toggled(self, switch, _param):
        on = switch.get_active()
        if self.config.get("passcode") and not self.ask_passcode("Enter the passcode to change this."):
            self._websites_set(not on)
            return
        switch.set_sensitive(False)
        try:
            process = Gio.Subprocess.new(["pkexec", FAMILY_HELPER, "on" if on else "off"],
                                         Gio.SubprocessFlags.STDERR_PIPE)
        except GLib.Error as error:
            switch.set_sensitive(True)
            self._websites_set(not on)
            alert.tell(self, "Logbook couldn\u2019t change this.", error.message)
            return

        def finished(proc, result):
            switch.set_sensitive(True)
            try:
                _ok, _out, err = proc.communicate_utf8_finish(result)
            except GLib.Error:
                err = ""
            status = proc.get_exit_status()
            self._websites_set(websites_limited())
            # 126 is the password dialog being cancelled: nothing to say then.
            if status not in (0, 126):
                alert.tell(self, "Logbook couldn\u2019t change this.", (err or "").strip())
        process.communicate_utf8_async(None, None, finished)

    def _timer(self):
        if self.get_window() is None:
            return False
        self.config = load_config()
        self._downtime_shown()
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
        if always_allowed(self.config, app):
            allowed = Gtk.Label(label="Always Allowed")
            allowed.get_style_context().add_class("dim-label")
            allowed.set_size_request(118, -1)
            box.pack_start(allowed, False, False, 0)
            return finish_row(box)
        limit = self.config["limits"].get(app)
        allowance = limit_for(self.config, app)
        if allowance and self.span == "today" and secs >= allowance * 60:
            label = "Time's Up"
        else:
            label = f"Limit {duration(limit * 60)}" if limit else "Set Limit"
        button = Gtk.MenuButton(label=label)
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
        allowance = limit_for(self.config, app)
        if allowance and load_day(datetime.date.today())["apps"].get(app, 0.0) >= allowance * 60:
            more = Gtk.Button(label=f"{MORE_TIME} More Minutes")
            more.connect("clicked", lambda _b: (pop.popdown(), self.give_more_time(app)))
            buttons.pack_start(more, False, False, 0)
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
        def change(config):
            if minutes > 0:
                config["limits"][app] = minutes
            else:
                config["limits"].pop(app, None)
        if self._change_config(change, "Enter the passcode to change a limit."):
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
