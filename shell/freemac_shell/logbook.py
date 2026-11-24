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

Screen Time for a family (1.138): an administrator can pick another person in
Logbook's toolbar and manage their screen time. Those settings are kept by
root in /etc/freemac/screen-time/NAME.json, so the person can see them but
not change them; a parent gives more time by typing their own password on
the person's screen (freemac-screen-time-helper, through pkexec). The
person's tracker copies each day to /var/lib/freemac/screen-time/NAME/, where
administrators can read it.

1.139: Downtime can be Custom, with its own hours (or none) for each day of
the week, and a limit can be on a category (every game, say), counting all
the apps of that kind together.

Original freemac code. Each day's times are kept in
~/.local/share/freemac/logbook/DATE.json (five weeks of them), limits and the
passcode (salted and hashed) in ~/.config/freemac/logbook.json.
"""
import calendar
import datetime
import grp
import hashlib
import json
import os
import pwd
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


# Screen Time for a family (see the helper for who writes what).
MANAGED = "/etc/freemac/screen-time"
SHARED = "/var/lib/freemac/screen-time"
HELPER = "/usr/libexec/freemac-screen-time-helper"
GRANT = "/usr/libexec/freemac-screen-time-grant"
ADMIN_GROUPS = {"sudo", "admin", "wheel"}


def me():
    return pwd.getpwuid(os.getuid()).pw_name


def managed_path(user):
    return os.path.join(MANAGED, user + ".json")


def grants_path(user):
    return os.path.join(SHARED, user + ".grants.json")


def usage_folder(user):
    return os.path.join(SHARED, user)


def is_managed(user=None):
    return os.path.exists(managed_path(user or me()))


def is_admin(user=None):
    """Whether the account is an administrator (in the sudo group)."""
    user = user or me()
    try:
        entry = pwd.getpwnam(user)
        groups = {g.gr_name for g in grp.getgrall() if user in g.gr_mem}
        groups.add(grp.getgrgid(entry.pw_gid).gr_name)
    except KeyError:
        return False
    return bool(groups & ADMIN_GROUPS)


def config_stamp(user=None):
    """Changes when any of the person's settings change."""
    user = user or me()
    stamp = []
    for path in (CONFIG, managed_path(user), grants_path(user)):
        try:
            stamp.append(os.stat(path).st_mtime)
        except OSError:
            stamp.append(0)
    return tuple(stamp)


def day_path(day, user=None):
    if user and user != me():
        return os.path.join(usage_folder(user), day.isoformat() + ".json")
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


def load_day(day, user=None):
    data = read_json(day_path(day, user))
    used = data.get("apps") if isinstance(data.get("apps"), dict) else {}
    used = {k: float(v) for k, v in used.items() if isinstance(k, str) and isinstance(v, (int, float)) and v >= 0}
    hours = data.get("hours")
    if not (isinstance(hours, list) and len(hours) == 24 and all(isinstance(h, (int, float)) for h in hours)):
        hours = [0.0] * 24
    return {"apps": used, "hours": [float(h) for h in hours]}


def load_config(user=None):
    """The person's settings: their own, or the ones a parent manages, with
    any time given today."""
    user = user or me()
    if is_managed(user):
        kept, given = read_json(managed_path(user)), read_json(grants_path(user))
        down = kept.get("downtime") if isinstance(kept.get("downtime"), dict) else {}
        data = {"limits": kept.get("limits"), "allowed": kept.get("allowed"),
                "downtime": {**down, "paused": given.get("downtime_paused")},
                "extra": {"day": given.get("day"), "apps": given.get("apps")}, "managed": True}
    else:
        data = read_json(CONFIG) if user == me() else {}
        data.pop("managed", None)
    limits = data.get("limits") if isinstance(data.get("limits"), dict) else {}
    data["limits"] = {k: int(v) for k, v in limits.items() if isinstance(v, int) and v > 0}
    allowed = data.get("allowed") if isinstance(data.get("allowed"), list) else []
    data["allowed"] = [a for a in allowed if isinstance(a, str) and a.endswith(".desktop")]
    down = data.get("downtime") if isinstance(data.get("downtime"), dict) else {}
    start, end = _minutes(down.get("start"), DOWNTIME_START), _minutes(down.get("end"), DOWNTIME_END)
    kept_days = down.get("days") if isinstance(down.get("days"), list) else []
    days = []
    for weekday in range(7):   # Monday first, as datetime counts
        day = kept_days[weekday] if weekday < len(kept_days) else {}
        if isinstance(day, dict):
            begin, finish = _minutes(day.get("start"), start), _minutes(day.get("end"), end)
            days.append((begin, finish) if begin != finish else None)
        else:
            days.append(None)   # no downtime that day
    data["downtime"] = {"on": down.get("on") is True, "start": start, "end": end,
                        "custom": down.get("custom") is True, "days": days,
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
    return when.strftime("%H:%M") if style.h24() else when.strftime("%-I:%M %p")


def day_window(down, weekday):
    """Downtime that starts on this day (0 is Monday), as (start, end) in
    minutes after midnight, or None. An end before the start is the next
    morning."""
    if down.get("custom"):
        return down["days"][weekday]
    return (down["start"], down["end"]) if down["start"] != down["end"] else None


def downtime_end(config, now=None):
    """When the downtime that's on now ends, in minutes after midnight, or
    None when it isn't on."""
    down = config["downtime"]
    now = now or datetime.datetime.now()
    if not down["on"] or down["paused"] > now.timestamp():
        return None
    minute = now.hour * 60 + now.minute
    today = day_window(down, now.weekday())
    if today:
        start, end = today
        if start <= minute < end or end < start <= minute:
            return end
    last_night = day_window(down, (now.weekday() - 1) % 7)
    if last_night and last_night[1] < last_night[0] and minute < last_night[1]:
        return last_night[1]
    return None


def in_downtime(config, now=None):
    return downtime_end(config, now) is not None


def next_downtime(config, now=None):
    """(minutes until it starts, start, end) for the next downtime, or None
    while it's on or turned off."""
    down = config["downtime"]
    now = now or datetime.datetime.now()
    if not down["on"] or in_downtime(config, now):
        return None
    minute = now.hour * 60 + now.minute
    for ahead in range(8):
        window = day_window(down, (now.weekday() + ahead) % 7)
        if window and ahead * 1440 + window[0] - minute > 0:
            return ahead * 1440 + window[0] - minute, window[0], window[1]
    return None


def minutes_to_downtime(config, now=None):
    """Minutes until downtime starts, or None while it's on or turned off."""
    coming = next_downtime(config, now)
    return coming[0] if coming else None


def downtime_kept(down):
    """Downtime as the settings file keeps it."""
    return {"on": down["on"], "start": hhmm(down["start"]), "end": hhmm(down["end"]),
            "custom": down["custom"],
            "days": [{"start": hhmm(day[0]), "end": hhmm(day[1])} if day else None for day in down["days"]]}


def desktop_id(app):
    info = apps.app_info(app)
    return info.get_id() if info else None


def always_allowed(config, app):
    if is_category(app):
        return False
    if app.lower() in ALWAYS_IDS:
        return True
    found = app if app.endswith(".desktop") else desktop_id(app)
    return bool(found) and (found in ALWAYS_DESKTOP or found in config["allowed"])


def extra_minutes(config, app, day=None):
    extra = config["extra"]
    if extra["day"] != (day or datetime.date.today()).isoformat():
        return 0
    return extra["apps"].get(app, 0)


def limit_key(config, app):
    """Where the app's limit is kept: under its window's app id, or under its
    desktop id when a parent added the limit before it was ever used."""
    if app in config["limits"] or app.endswith(".desktop") or is_category(app):
        return app
    found = desktop_id(app)
    return found if found and found in config["limits"] else app


def app_info_any(app):
    if is_category(app):
        return None
    if app.endswith(".desktop"):
        try:
            return Gio.DesktopAppInfo.new(app)
        except TypeError:
            return None
    return apps.app_info(app)


def app_name(app):
    if is_category(app):
        return category_name(app)
    info = app_info_any(app) if app.endswith(".desktop") else None
    return apps.short_name(info) if info else apps.display_name(app)


def app_icon(app):
    if is_category(app):
        return Gio.ThemedIcon.new_from_names(list(_category(app)[3]))
    info = app_info_any(app) if app.endswith(".desktop") else None
    icon = info.get_icon() if info else None
    return icon or apps.icon_for(app)


def limit_for(config, app):
    """Minutes the app may be used today, counting any time given since; None
    for no limit."""
    limit = config["limits"].get(limit_key(config, app))
    if not limit or always_allowed(config, app):
        return None
    return limit + extra_minutes(config, app)


# ---- Limits for a kind of app ------------------------------------------------------
# A limit on a category counts every app in it together. The kind comes from
# the Categories line of each app's .desktop file; the first rule that
# matches decides, so a maths game is Education and a photo editor is
# Creativity.
CATEGORIES = (
    ("reading", "Information & Reading", {"Literature", "Dictionary", "News", "WebBrowser"},
     ("accessories-dictionary-symbolic", "x-office-document-symbolic")),
    ("education", "Education", {"Education", "Math", "Science", "Languages", "ArtificialIntelligence",
                                "Astronomy", "Biology", "Chemistry", "Geography", "Geology", "Physics"},
     ("applications-science-symbolic", "accessories-calculator-symbolic")),
    ("games", "Games", {"Game"}, ("applications-games-symbolic", "input-gaming-symbolic")),
    ("social", "Social", {"InstantMessaging", "Chat", "Email", "IRCClient", "VideoConference",
                          "Telephony", "ContactManagement"},
     ("user-available-symbolic", "mail-unread-symbolic")),
    ("creativity", "Creativity", {"Graphics", "2DGraphics", "3DGraphics", "RasterGraphics", "VectorGraphics",
                                  "Photography", "AudioVideoEditing", "Recorder", "Publishing"},
     ("applications-graphics-symbolic", "image-x-generic-symbolic")),
    ("entertainment", "Entertainment", {"AudioVideo", "Audio", "Video", "Player", "TV", "Feed", "Music"},
     ("applications-multimedia-symbolic", "media-playback-start-symbolic")),
    ("productivity", "Productivity & Finance", {"Office", "Finance", "ProjectManagement", "Calendar",
                                                "Spreadsheet", "WordProcessor", "Presentation",
                                                "TextEditor", "Development", "Database"},
     ("x-office-document-symbolic", "x-office-spreadsheet-symbolic")),
    ("utilities", "Utilities", {"Utility", "System", "Settings", "Accessibility", "FileManager",
                                "TerminalEmulator", "Monitor", "Security", "Archiving", "PackageManager",
                                "Network"},
     ("emblem-system-symbolic", "applications-system-symbolic")),
)
OTHER = ("other", "Other", set(), ("applications-other-symbolic", "view-app-grid-symbolic"))
CATEGORY_PREFIX = "category:"
# Each category's tile colour, as red, green and blue from 0 to 1.
CATEGORY_COLOURS = {"reading": (0.78, 0.48, 0.23), "education": (0.08, 0.64, 0.72),
                    "games": (0.56, 0.36, 0.97), "social": (0.18, 0.70, 0.43),
                    "creativity": (0.95, 0.60, 0.20), "entertainment": (0.91, 0.34, 0.25),
                    "productivity": (0.23, 0.51, 0.96), "utilities": (0.42, 0.45, 0.50),
                    "other": (0.61, 0.64, 0.69)}
_kinds = {}


def is_category(key):
    return key.startswith(CATEGORY_PREFIX)


def _category(key):
    wanted = key[len(CATEGORY_PREFIX):]
    return next((c for c in CATEGORIES if c[0] == wanted), OTHER)


def category_of(app):
    """The category key an app counts toward: category:games, say."""
    if app not in _kinds:
        info = app_info_any(app)
        listed = set(filter(None, (info.get_categories() or "").split(";"))) if info else set()
        kind = next((c for c in CATEGORIES if c[2] & listed), OTHER)
        _kinds[app] = CATEGORY_PREFIX + kind[0]
    return _kinds[app]


def category_name(key):
    return _category(key)[1]


def category_used(config, used, key):
    """Seconds the apps of a category have had, from a day's times."""
    return sum(secs for app, secs in used.items()
               if not is_category(app) and app.lower() not in OWN_IDS
               and category_of(app) == key and not always_allowed(config, app))


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
        self.config_stamp = ()
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
            # This person's lock screen: someone else's may be up behind a
            # switch of user.
            return subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "gtklock"],
                                  capture_output=True, timeout=2).returncode == 0
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
        coming = next_downtime(self.config)
        if coming is None or coming[0] > 5:
            return
        left, start, end = coming
        key = ("downtime", self.today.isoformat(), start)
        if key in self.warned:
            return
        self.warned.add(key)
        notify(f"Downtime starts in {left} minute{'s' if left != 1 else ''}",
               f"From {clock(start)} until {clock(end)}, only the apps you always allow can be used.")

    def _reload_config(self):
        stamp = config_stamp()
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
                       f"It can be used again at {clock(downtime_end(self.config))}.")
            if self.wf:
                try:
                    self.wf.quit(app)
                except (OSError, ConnectionError, ValueError):
                    pass
            return
        # The app's own limit, then its category's: the first one used up
        # closes the app.
        checks = []
        limit = limit_for(self.config, app)
        if limit:
            checks.append((app, name, limit, self.day["apps"].get(app, 0.0)))
        kind = category_of(app)
        kind_limit = limit_for(self.config, kind) if not always_allowed(self.config, app) else None
        if kind_limit:
            checks.append((kind, category_name(kind), kind_limit,
                           category_used(self.config, self.day["apps"], kind)))
        managed = " A parent can give more time in Logbook." if self.config.get("managed") else ""
        for key, label, limit, used in checks:
            if used < limit * 60:
                continue
            now = time.monotonic()
            if now - self.stopped_at.get((key, app), -999) > 20:
                self.stopped_at[(key, app)] = now
                if key == app:
                    notify(f"Time's up for {name}",
                           f"{name} has had its {duration(limit * 60)} for today." + managed)
                else:
                    notify(f"Time's up for {label}",
                           f"{label} apps, {name} among them, have had their {duration(limit * 60)} "
                           "for today." + managed)
            if self.wf:
                try:
                    self.wf.quit(app)
                except (OSError, ConnectionError, ValueError):
                    pass
            return
        for key, label, limit, used in checks:
            if used >= limit * 60 - WARN_BEFORE and (key, limit) not in self.warned:
                self.warned.add((key, limit))
                left = max(1, round((limit * 60 - used) / 60))
                if key == app:
                    notify(f"{left} minute{'s' if left != 1 else ''} left for {name}",
                           f"{name} has a limit of {duration(limit * 60)} a day.")
                else:
                    notify(f"{left} minute{'s' if left != 1 else ''} left for {label}",
                           f"{label} apps, {name} among them, have a limit of {duration(limit * 60)} a day.")

    def _save(self):
        if self.dirty:
            day = {"apps": {k: round(v, 1) for k, v in self.day["apps"].items()},
                   "hours": [round(h, 1) for h in self.day["hours"]]}
            write_json(day_path(self.today), day)
            if self.config.get("managed") and os.path.isdir(usage_folder(me())):
                try:   # a copy for the parent to see
                    write_json(os.path.join(usage_folder(me()), self.today.isoformat() + ".json"), day)
                except OSError:
                    pass
            self.dirty = False
        return True

    def _tidy(self):
        oldest = datetime.date.today() - datetime.timedelta(days=KEEP_DAYS)
        for folder in (DATA, usage_folder(me())):
            try:
                for name in os.listdir(folder):
                    try:
                        if datetime.date.fromisoformat(name[:10]) < oldest:
                            os.remove(os.path.join(folder, name))
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


def category_tile(key, size, scale=1):
    """A category's icon: its glyph in white on a rounded tile of its colour."""
    import cairo
    pixels = size * scale
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, pixels, pixels)
    cr = cairo.Context(surface)
    radius = pixels * 0.24
    cr.new_sub_path()
    for x, y, angle in ((pixels - radius, radius, -0.5), (pixels - radius, pixels - radius, 0),
                        (radius, pixels - radius, 0.5), (radius, radius, 1)):
        cr.arc(x, y, radius, angle * 3.14159265, (angle + 0.5) * 3.14159265)
    cr.close_path()
    cr.set_source_rgb(*CATEGORY_COLOURS.get(key[len(CATEGORY_PREFIX):], CATEGORY_COLOURS["other"]))
    cr.fill()
    glyph = int(pixels * 0.56)
    info = Gtk.IconTheme.get_default().lookup_by_gicon(app_icon(key), glyph, Gtk.IconLookupFlags.FORCE_SIZE)
    if info is not None:
        white = Gdk.RGBA(1, 1, 1, 1)
        try:
            pixbuf, _was_symbolic = info.load_symbolic(white, None, None, None)
        except GLib.Error:
            pixbuf = None
        if pixbuf is not None:
            Gdk.cairo_set_source_pixbuf(cr, pixbuf, (pixels - pixbuf.get_width()) / 2,
                                        (pixels - pixbuf.get_height()) / 2)
            cr.paint()
    surface.set_device_scale(scale, scale)
    return surface


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
        bars = [(((1, 1, 1, 0.12) if dark else (0, 0, 0, 0.08)), width)]
        if self.fraction > 0:
            bars.append(((0.04, 0.49, 1.0, 1), max(height, width * self.fraction)))
        for fill, w in bars:
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
        self.person = me()
        self.root_output = ""
        self.stamp = ()
        self.config = load_config()
        self.span = "today"
        self.list = None
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
        self.people = self._people_combo()
        if self.people:
            header.pack_start(self.people)
        self.scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.add(self.scroller)
        menus.add_actions(self, {"close": self.close, "today": lambda: self.today_button.set_active(True),
                                 "week": lambda: self.week_button.set_active(True),
                                 "passcode": self.passcode_dialog})
        if not tracker_running():
            try:
                subprocess.Popen(["freemac-logbook", "--track"], start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                pass
        self._build()
        GLib.timeout_add_seconds(30, self._timer)
        self.show_all()

    # ---- Screen Time for a family -------------------------------------------------
    def _people_combo(self):
        """For an administrator: a pop-up button choosing whose screen time
        the window shows."""
        if not is_admin():
            return None
        from .switch_user import accounts, full_name
        others = [e for e in accounts() if e.pw_name != me() and e.pw_name != "guest"]
        if not others:
            return None
        button = Gtk.MenuButton(tooltip_text="Whose screen time to show")
        inner = Gtk.Box(spacing=6)
        self.people_label = Gtk.Label(label="Me")
        inner.pack_start(self.people_label, False, False, 0)
        inner.pack_start(Gtk.Image.new_from_icon_name("pan-down-symbolic", Gtk.IconSize.BUTTON), False, False, 0)
        button.add(inner)
        pop = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.set_border_width(6)
        self.people_rows = {}
        for user, label in [(me(), "Me")] + [(e.pw_name, full_name(e)) for e in others]:
            row = Gtk.ModelButton(text=label, role=Gtk.ButtonRole.RADIO, active=user == me())
            row.connect("clicked", lambda _b, u=user, t=label: (pop.popdown(), self._person_changed(u, t)))
            box.pack_start(row, False, False, 0)
            self.people_rows[user] = row
        box.show_all()
        pop.add(box)
        button.set_popover(pop)
        return button

    def _person_changed(self, person, label):
        for user, row in self.people_rows.items():
            row.set_property("active", user == person)
        if person != self.person:
            self.person = person
            self.people_label.set_text(label)
            self._build()

    def name(self, user=None):
        user = user or self.person
        try:
            entry = pwd.getpwnam(user)
        except KeyError:
            return user
        return entry.pw_gecos.split(",")[0] or user

    @property
    def locked(self):
        """The person's own window, when a parent manages their screen time."""
        return bool(self.config.get("managed")) and self.person == me()

    @property
    def mine(self):
        return self.person == me()

    def _notice(self):
        """What the top of the window says about who manages this."""
        if self.mine and not self.locked:
            return None
        name = GLib.markup_escape_text(self.name())
        box = Gtk.Box(spacing=14)
        icon = Gtk.Image.new_from_icon_name("freemac-logbook", Gtk.IconSize.DIALOG)
        icon.set_pixel_size(40)
        box.pack_start(icon, False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        title = Gtk.Label(xalign=0, wrap=True)
        note = Gtk.Label(xalign=0, wrap=True)
        note.get_style_context().add_class("dim-label")
        words.pack_start(title, False, False, 0)
        words.pack_start(note, False, False, 0)
        box.pack_start(words, True, True, 0)
        if self.locked:
            title.set_markup("<b>A parent manages your screen time</b>")
            note.set_text("You can see your limits and downtime here. For more time, a parent enters "
                          "their password on this computer.")
            return box
        if not self.config.get("managed"):
            title.set_markup(f"<b>{name}’s screen time isn’t managed</b>")
            note.set_text(f"Set daily limits, downtime and always allowed apps for {self.name()}. "
                          f"{self.name()} can see them but can’t change them, and you can see how "
                          f"{self.name()} spends time on this computer.")
            button = Gtk.Button(label=f"Manage Screen Time for {self.name()}", valign=Gtk.Align.CENTER)
            button.get_style_context().add_class("suggested-action")
            button.connect("clicked", lambda _b: self._start_managing())
            box.pack_end(button, False, False, 0)
            return box
        title.set_markup(f"<b>{name}’s screen time</b>")
        text = (f"{self.name()} can see these settings but can’t change them. They take effect "
                "within a minute, and the times below fill in while "
                f"{self.name()} uses the computer.")
        if is_admin(self.person):
            text += f" {self.name()} is an administrator, so could turn this off."
        note.set_text(text)
        stop = Gtk.Button(label="Stop Managing…", valign=Gtk.Align.CENTER)
        stop.connect("clicked", lambda _b: self._stop_managing())
        box.pack_end(stop, False, False, 0)
        return box

    def _run_root(self, command, stdin=None):
        """Run a Screen Time helper through pkexec, keeping the window drawn
        while the password dialog is up. Returns whether it worked."""
        try:
            process = Gio.Subprocess.new(["pkexec", *command],
                                         Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDOUT_PIPE
                                         | Gio.SubprocessFlags.STDERR_PIPE)
        except GLib.Error as error:
            alert.tell(self, "Logbook couldn’t change this.", error.message)
            return False
        loop = GLib.MainLoop()
        answer = {}

        def finished(proc, result):
            try:
                _ok, out, err = proc.communicate_utf8_finish(result)
            except GLib.Error:
                out = err = ""
            answer["status"], answer["err"] = proc.get_exit_status(), (err or "").strip()
            self.root_output = out or ""
            loop.quit()
        self.set_sensitive(False)
        process.communicate_utf8_async(stdin, None, finished)
        loop.run()
        self.set_sensitive(True)
        # 126 and 127: the password dialog was cancelled or the password refused.
        if answer["status"] not in (0, 126, 127):
            alert.tell(self, "Logbook couldn’t change this.", answer["err"])
        return answer["status"] == 0

    @staticmethod
    def _managed_settings(config):
        return json.dumps({"limits": config["limits"], "allowed": config["allowed"],
                           "downtime": downtime_kept(config["downtime"])})

    def _start_managing(self):
        if self._run_root([HELPER, "set", self.person], self._managed_settings(load_config(self.person))):
            self._build()
            self._warn_no_password()

    def _warn_no_password(self):
        """A parent's account with no password lets anyone give more time."""
        names = [line.split()[1] for line in self.root_output.splitlines()
                 if line.startswith("no-password ") and len(line.split()) == 2]
        if not names:
            return
        who = ", ".join(self.name(n) for n in names)
        alert.tell(self, "Give your account a password",
                   f"{who} {'has' if len(names) == 1 else 'have'} no password, so anyone at this "
                   f"computer could give {self.name()} more time. Set one in Dials › Users.")

    def _stop_managing(self):
        answer = alert.ask(self, f"Stop managing {self.name()}’s screen time?",
                           f"{self.name()}’s limits, downtime and always allowed apps are removed, "
                           "along with the times kept for you to see.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Stop Managing", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK)
        if answer == Gtk.ResponseType.OK and self._run_root([HELPER, "off", self.person]):
            self._build()

    def _grant(self, *what):
        """More time, from a parent: their password on this screen."""
        return self._run_root([GRANT, self.person, *what])

    # ---- the page ---------------------------------------------------------------
    def _build(self):
        """Lay the window out for the person it shows."""
        old = self.scroller.get_child()
        if old is not None:
            self.scroller.remove(old)
            old.destroy()
        self.config = load_config(self.person)
        self.stamp = config_stamp(self.person)
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        page.set_border_width(22)
        notice = self._notice()
        if notice is not None:
            page.pack_start(notice, False, False, 0)
            page.pack_start(Gtk.Separator(), False, False, 12)
        self.list = None
        showing = self.mine or bool(self.config.get("managed"))
        self.header.get_custom_title().set_sensitive(showing)
        if not showing:
            self.scroller.add(page)
            page.show_all()
            return
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
        self.empty = Gtk.Label(label="Nothing yet. Time spent in apps shows here." if self.mine else
                               f"Nothing yet. Time {self.name()} spends in apps shows here.")
        self.empty.get_style_context().add_class("dim-label")
        page.pack_start(self.empty, False, False, 12)
        self.empty.set_no_show_all(True)
        self.list.set_no_show_all(True)
        if not self.locked:
            add = Gtk.Button(label="Add Limit\u2026", halign=Gtk.Align.START,
                             tooltip_text="A daily limit for an app, used yet or not")
            add.connect("clicked", lambda _b: self._add_limit())
            page.pack_start(add, False, False, 4)
        # Categories: the time of every app of a kind, with a limit for them
        # all together.
        self.kinds_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        heading = Gtk.Label(xalign=0)
        heading.set_markup("<b>Categories</b>")
        self.kinds_box.pack_start(heading, False, False, 6)
        self.kinds = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.kinds.get_style_context().add_class("frame")
        self.kinds_box.pack_start(self.kinds, False, False, 0)
        if not self.locked:
            add_kind = Gtk.Button(label="Add Category Limit\u2026", halign=Gtk.Align.START,
                                  tooltip_text="One daily limit for every app of a kind, such as Games")
            add_kind.connect("clicked", lambda _b: self._add_category_limit())
            self.kinds_box.pack_start(add_kind, False, False, 4)
        self.kinds_box.set_no_show_all(True)
        page.pack_start(self.kinds_box, False, False, 12)
        page.pack_start(self._downtime_box(), False, False, 18)
        page.pack_start(self._allowed_box(), False, False, 0)
        if self.mine:   # a setting for the whole computer
            page.pack_start(self._websites_box(), False, False, 18)
        self.scroller.add(page)
        page.show_all()
        self._downtime_shown()
        self.refresh()

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
        self.downtime_mode = Gtk.ComboBoxText()
        self.downtime_mode.append("every", "Every Day")
        self.downtime_mode.append("custom", "Custom")
        self.downtime_mode.set_active_id("custom" if down["custom"] else "every")
        self.downtime_mode.connect("changed", lambda _c: self._downtime_changed())
        times.pack_start(self.downtime_mode, False, False, 0)
        self.everyday = Gtk.Box(spacing=12)
        self.everyday.pack_start(Gtk.Label(label="From"), False, False, 0)
        self.downtime_from = self._time_combo(down["start"])
        self.everyday.pack_start(self.downtime_from, False, False, 0)
        self.everyday.pack_start(Gtk.Label(label="to"), False, False, 0)
        self.downtime_to = self._time_combo(down["end"])
        self.everyday.pack_start(self.downtime_to, False, False, 0)
        times.pack_start(self.everyday, False, False, 0)
        self.everyday.set_no_show_all(True)   # shown or not by _downtime_shown
        frame.add(times)
        # Custom: each day with its own hours, or none. The week starts on
        # Sunday, as the calendar in the menu bar does.
        self.day_rows = []
        for weekday in (6, 0, 1, 2, 3, 4, 5):
            window = down["days"][weekday]
            line = self._line()
            line.set_margin_start(28)
            line.set_margin_top(3)
            line.set_margin_bottom(3)
            check = Gtk.CheckButton(label=calendar.day_name[weekday], active=window is not None)
            check.set_size_request(130, -1)
            check.connect("toggled", lambda _c: self._downtime_changed())
            line.pack_start(check, False, False, 0)
            begin = self._time_combo(window[0] if window else down["start"])
            finish = self._time_combo(window[1] if window else down["end"])
            for widget in (Gtk.Label(label="From"), begin, Gtk.Label(label="to"), finish):
                line.pack_start(widget, False, False, 0)
            row = Gtk.ListBoxRow(activatable=False)
            row.add(line)
            row.set_no_show_all(True)
            frame.add(row)
            self.day_rows.append((weekday, row, check, begin, finish))
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
        return box

    def _downtime_shown(self):
        """Put the switch and times back as they're kept, and say whether
        downtime is on now."""
        self.updating = True
        down = self.config["downtime"]
        changeable = down["on"] and not self.locked

        def show_time(combo, minutes):
            if not combo.set_active_id(hhmm(minutes)):
                combo.append(hhmm(minutes), clock(minutes))
                combo.set_active_id(hhmm(minutes))
        self.downtime_switch.set_active(down["on"])
        self.downtime_switch.set_sensitive(not self.locked)
        self.downtime_mode.set_active_id("custom" if down["custom"] else "every")
        self.downtime_mode.set_sensitive(changeable)
        for combo, minutes in ((self.downtime_from, down["start"]), (self.downtime_to, down["end"])):
            show_time(combo, minutes)
            combo.set_sensitive(changeable)
        if down["custom"]:
            self.everyday.hide()
        else:
            for child in self.everyday.get_children():
                child.show_all()
            self.everyday.show()
        for weekday, row, check, begin, finish in self.day_rows:
            window = down["days"][weekday]
            check.set_active(window is not None)
            check.set_sensitive(changeable)
            if window:
                show_time(begin, window[0])
                show_time(finish, window[1])
            begin.set_sensitive(changeable and window is not None)
            finish.set_sensitive(changeable and window is not None)
            if down["custom"]:
                row.get_child().show_all()   # the row ignores show_all
                row.show()
            else:
                row.hide()
        self.updating = False
        ends = downtime_end(self.config)
        if ends is not None:
            self.downtime_now.set_text(f"Downtime until {clock(ends)}")
            self.downtime_now_row.get_child().show_all()
            self.downtime_now_row.show()
        else:
            self.downtime_now_row.hide()

    def _change_config(self, change, ask):
        """Re-read the settings, ask for the passcode if there is one, then
        change and keep them. Returns whether it was changed. Settings a
        parent manages are kept by root, after an administrator's password."""
        self.config = load_config(self.person)
        if self.config.get("managed"):
            if self.locked:
                return False
            change(self.config)
            done = self._run_root([HELPER, "set", self.person], self._managed_settings(self.config))
            self.config = load_config(self.person)
            self.stamp = config_stamp(self.person)   # changed here: no need to rebuild the page
            return done
        if self.config.get("passcode") and not self.ask_passcode(ask):
            return False
        change(self.config)
        write_json(CONFIG, {**self.config, "downtime": {**downtime_kept(self.config["downtime"]),
                                                        "paused": self.config["downtime"]["paused"]}})
        self.config = load_config()
        self.stamp = config_stamp(self.person)
        return True

    def _downtime_changed(self):
        if getattr(self, "updating", False):
            return
        on = self.downtime_switch.get_active()
        start = _minutes(self.downtime_from.get_active_id(), DOWNTIME_START)
        end = _minutes(self.downtime_to.get_active_id(), DOWNTIME_END)
        custom = self.downtime_mode.get_active_id() == "custom"
        days = list(self.config["downtime"]["days"])
        for weekday, _row, check, begin, finish in self.day_rows:
            begin_at = _minutes(begin.get_active_id(), start)
            finish_at = _minutes(finish.get_active_id(), end)
            days[weekday] = (begin_at, finish_at) if check.get_active() and begin_at != finish_at else None

        def change(config):
            config["downtime"].update(on=on, start=start, end=end, custom=custom, days=days, paused=0)
        self._change_config(change, "Enter the passcode to change downtime.")
        self._downtime_shown()

    def _pause_downtime(self):
        if self.config.get("managed"):
            if self._grant("downtime"):
                self.config = load_config(self.person)
                self.stamp = config_stamp(self.person)
                self._downtime_shown()
            return
        until = time.time() + MORE_TIME * 60
        if self._change_config(lambda config: config["downtime"].update(paused=until),
                               f"Enter the passcode to give {MORE_TIME} more minutes."):
            self._downtime_shown()

    def _allowed_box(self):
        box, self.allowed_list = self._section("Always Allowed")
        add = Gtk.Button(label="+", tooltip_text="Always allow an app", halign=Gtk.Align.START)
        add.connect("clicked", lambda _b: self._add_allowed())
        if not self.locked:
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
            if not self.locked:
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
        if self.config.get("managed"):
            if self._grant("more", app):
                self.config = load_config(self.person)
                self.stamp = config_stamp(self.person)
                self.refresh()
            return
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
        if self.list is not None and not self._popover_open():
            if config_stamp(self.person) != self.stamp:
                # A parent changed the settings (or this window did): lay it
                # out again, keeping the place it was scrolled to.
                place = self.scroller.get_vadjustment().get_value()
                self._build()
                adjustment = self.scroller.get_vadjustment()

                def back(adj):
                    # Once the new page is tall enough, scroll back.
                    if handler and adj.get_upper() - adj.get_page_size() >= place:
                        adj.set_value(place)
                        adj.disconnect(handler.pop())

                def give_up():
                    if handler:
                        adjustment.disconnect(handler.pop())
                    return False
                handler = [adjustment.connect("changed", back)]
                GLib.timeout_add_seconds(2, give_up)
                return True
            self.config = load_config(self.person)
            self._downtime_shown()
            self.refresh()
        return True

    def _popover_open(self):
        """Whether a row's limit pop-over is showing; the rows aren't
        rebuilt under it."""
        for row in [*self.list.get_children(), *self.kinds.get_children()]:
            stack = [row]
            while stack:
                widget = stack.pop()
                if isinstance(widget, Gtk.MenuButton) and widget.get_active():
                    return True
                if isinstance(widget, Gtk.Container):
                    stack.extend(widget.get_children())
        return False

    def _span_toggled(self, button, span):
        if button.get_active():
            self.span = span
            self.refresh()

    def refresh(self):
        if self.list is None:
            return
        today = datetime.date.today()
        if self.span == "today":
            day = load_day(today, self.person)
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
                day = load_day(date, self.person)
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
        top = max([*used.values(), 1.0])
        shown = set()
        for app, secs in sorted(used.items(), key=lambda kv: -kv[1]):
            if secs < 30:
                continue
            self.list.add(self._row(app, secs, top))
            shown.add(limit_key(self.config, app))
        for key in sorted(set(self.config["limits"]) - shown, key=lambda k: app_name(k).lower()):
            if not is_category(key):
                self.list.add(self._row(key, used.get(key, 0.0), top))   # limited, not used yet
        for row in self.list.get_children():
            row.show_all()
        has = bool(self.list.get_children())
        self.list.set_visible(has)
        self.empty.set_visible(not has)
        # Categories with time in them, or a limit.
        for row in self.kinds.get_children():
            self.kinds.remove(row)
        kinds = {CATEGORY_PREFIX + c[0]: 0.0 for c in (*CATEGORIES, OTHER)}
        for key in kinds:
            kinds[key] = category_used(self.config, used, key)
        listed = [k for k in kinds if kinds[k] >= 30 or k in self.config["limits"]]
        listed.sort(key=lambda k: -kinds[k])
        top_kind = max([kinds[k] for k in listed] + [1.0])
        for key in listed:
            self.kinds.add(self._row(key, kinds[key], top_kind))
        if listed or not self.locked:
            for child in self.kinds_box.get_children():   # the box ignores show_all
                child.show_all()
            self.kinds_box.show()
            self.kinds.set_visible(bool(listed))
        else:
            self.kinds_box.hide()

    def _row(self, app, secs, top):
        box = Gtk.Box(spacing=12)
        box.set_border_width(10)
        if is_category(app):
            icon = Gtk.Image.new_from_surface(category_tile(app, 32, self.get_scale_factor()))
        else:
            icon = Gtk.Image.new_from_gicon(app_icon(app), Gtk.IconSize.DND)
            icon.set_pixel_size(32)
        box.pack_start(icon, False, False, 0)
        middle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        name = Gtk.Label(label=app_name(app), xalign=0, ellipsize=Pango.EllipsizeMode.END)
        middle.pack_start(name, False, False, 0)
        middle.pack_start(Meter(secs / top), False, False, 0)
        box.pack_start(middle, True, True, 0)
        time_label = Gtk.Label(label=duration(secs, short=True))
        time_label.set_width_chars(10)
        time_label.set_xalign(1)
        box.pack_start(time_label, False, False, 0)
        key = limit_key(self.config, app)
        if app.lower() in OWN_IDS or (self.locked and not self.config["limits"].get(key)):
            # Logbook itself is where limits are changed; and there's nothing
            # to press when a parent sets limits and this app has none.
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
        limit = self.config["limits"].get(key)
        allowance = limit_for(self.config, app)
        if allowance and self.span == "today" and secs >= allowance * 60:
            label = "Time's Up"
        else:
            label = f"Limit {duration(limit * 60)}" if limit else "Set Limit"
        if self.locked and label == "Time's Up":
            # The child's one choice: ask a parent, who types their password
            # right here.
            button = Gtk.Button(label="More Time…")
            button.set_tooltip_text(f"A parent enters their password to give {MORE_TIME} more minutes.")
            button.connect("clicked", lambda _b: self.give_more_time(app))
            button.set_size_request(118, -1)
            box.pack_start(button, False, False, 0)
            return finish_row(box)
        button = Gtk.MenuButton(label=label)
        button.set_relief(Gtk.ReliefStyle.NONE if not limit else Gtk.ReliefStyle.NORMAL)
        button.set_size_request(118, -1)
        button.set_popover(self._limit_popover(button, app, limit, key))
        box.pack_start(button, False, False, 0)
        return finish_row(box)

    def _limit_popover(self, button, app, limit, key=None):
        key = key or app
        pop = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_border_width(14)
        title = Gtk.Label(xalign=0)
        title.set_markup(f"<b>A daily limit for {GLib.markup_escape_text(app_name(app))}</b>")
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
        if self.locked:
            box.remove(line)
            title.set_markup(f"<b>{GLib.markup_escape_text(app_name(app))}: "
                             f"{GLib.markup_escape_text(duration(limit * 60))} a day</b>")
            note = Gtk.Label(label="A parent sets this limit.", xalign=0)
            note.get_style_context().add_class("dim-label")
            box.pack_start(note, False, False, 0)
            used = self.used_today(app)
            if allowance and used >= allowance * 60:
                more = Gtk.Button(label=f"{MORE_TIME} More Minutes", halign=Gtk.Align.END)
                more.get_style_context().add_class("suggested-action")
                more.connect("clicked", lambda _b: (pop.popdown(), self.give_more_time(app)))
                box.pack_start(more, False, False, 0)
            box.show_all()
            pop.add(box)
            return pop
        if allowance and self.used_today(app) >= allowance * 60:
            more = Gtk.Button(label=f"{MORE_TIME} More Minutes")
            more.connect("clicked", lambda _b: (pop.popdown(), self.give_more_time(app)))
            buttons.pack_start(more, False, False, 0)
        if limit:
            off = Gtk.Button(label="No Limit")
            off.connect("clicked", lambda _b: (pop.popdown(), self.change_limit(key, 0)))
            buttons.pack_start(off, False, False, 0)
        save = Gtk.Button(label="Set Limit")
        save.get_style_context().add_class("suggested-action")
        save.connect("clicked", lambda _b: (pop.popdown(),
                                            self.change_limit(key, int(hours.get_value()) * 60
                                                              + int(minutes.get_value()))))
        buttons.pack_start(save, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        note = Gtk.Label(label="Five minutes before the time is up, a notice says so.\n"
                               + ("At the limit, the windows of every app in it close for the rest of the day."
                                  if is_category(app) else
                                  "At the limit, the app's windows close for the rest of the day."), xalign=0)
        note.get_style_context().add_class("dim-label")
        box.pack_start(note, False, False, 0)
        box.show_all()
        pop.add(box)
        return pop

    def used_today(self, key):
        used = load_day(datetime.date.today(), self.person)["apps"]
        return category_used(self.config, used, key) if is_category(key) else used.get(key, 0.0)

    def _add_category_limit(self):
        self.config = load_config(self.person)
        dialog = Gtk.Dialog(title="Category Limit", transient_for=self, modal=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Set Limit", Gtk.ResponseType.OK).get_style_context().add_class("suggested-action")
        dialog.set_default_response(Gtk.ResponseType.OK)
        area = dialog.get_content_area()
        area.set_spacing(10)
        area.set_border_width(16)
        title = Gtk.Label(xalign=0)
        title.set_markup("<b>One daily limit for every app of a kind</b>")
        area.pack_start(title, False, False, 0)
        kind = Gtk.ComboBoxText()
        for key, label, *_rest in (*CATEGORIES, OTHER):
            kind.append(CATEGORY_PREFIX + key, label)
        free = [CATEGORY_PREFIX + c[0] for c in (*CATEGORIES, OTHER)
                if CATEGORY_PREFIX + c[0] not in self.config["limits"]]
        kind.set_active_id(CATEGORY_PREFIX + "games" if CATEGORY_PREFIX + "games" in free
                           else (free or [CATEGORY_PREFIX + "games"])[0])
        area.pack_start(kind, False, False, 0)
        line = Gtk.Box(spacing=6)
        hours = Gtk.SpinButton.new_with_range(0, 12, 1)
        minutes = Gtk.SpinButton.new_with_range(0, 55, 5)
        hours.set_value(1)
        for widget in (hours, Gtk.Label(label="h"), minutes, Gtk.Label(label="min a day")):
            line.pack_start(widget, False, False, 0)
        area.pack_start(line, False, False, 0)
        members = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
        members.get_style_context().add_class("dim-label")
        area.pack_start(members, False, False, 0)

        def show_members(_c=None):
            key = kind.get_active_id()
            names = sorted({apps.short_name(info) for info in Gio.AppInfo.get_all()
                            if info.should_show() and isinstance(info, Gio.DesktopAppInfo)
                            and category_of(info.get_id()) == key
                            and not always_allowed(self.config, info.get_id())}, key=str.lower)
            members.set_text(("Counts " + ", ".join(names[:8]) + (" and more." if len(names) > 8 else "."))
                             if names else "No apps of this kind are installed yet.")
        kind.connect("changed", show_members)
        show_members()
        area.show_all()
        answer = dialog.run()
        total = int(hours.get_value()) * 60 + int(minutes.get_value())
        key = kind.get_active_id()
        dialog.destroy()
        if answer == Gtk.ResponseType.OK and total > 0 and key:
            self.change_limit(key, total)

    def _add_limit(self):
        from .dials_login import choose_app
        self.config = load_config(self.person)
        taken = set(self.config["limits"]) | set(self.config["allowed"]) | ALWAYS_DESKTOP
        desktop = choose_app(self, "Add a Limit", taken)
        if not desktop:
            return
        dialog = Gtk.Dialog(title="Daily Limit", transient_for=self, modal=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Set Limit", Gtk.ResponseType.OK).get_style_context().add_class("suggested-action")
        dialog.set_default_response(Gtk.ResponseType.OK)
        area = dialog.get_content_area()
        area.set_spacing(10)
        area.set_border_width(16)
        title = Gtk.Label(xalign=0)
        title.set_markup(f"<b>A daily limit for {GLib.markup_escape_text(app_name(desktop))}</b>")
        area.pack_start(title, False, False, 0)
        line = Gtk.Box(spacing=6)
        hours = Gtk.SpinButton.new_with_range(0, 12, 1)
        minutes = Gtk.SpinButton.new_with_range(0, 55, 5)
        hours.set_value(1)
        for widget in (hours, Gtk.Label(label="h"), minutes, Gtk.Label(label="min a day")):
            line.pack_start(widget, False, False, 0)
        area.pack_start(line, False, False, 0)
        area.show_all()
        answer = dialog.run()
        total = int(hours.get_value()) * 60 + int(minutes.get_value())
        dialog.destroy()
        if answer == Gtk.ResponseType.OK and total > 0:
            self.change_limit(desktop, total)

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
        self.config = load_config(self.person)
        if self.config.get("managed") or not self.mine:
            alert.tell(self, "No passcode is needed here.",
                       "A parent manages this screen time, and changing it needs an administrator’s "
                       "password." if self.config.get("managed") else
                       "Choose Me in the toolbar to set a passcode for your own limits.")
            return
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
