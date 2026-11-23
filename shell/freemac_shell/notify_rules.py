# SPDX-License-Identifier: GPL-3.0-or-later
"""What Beacon does with a notification: the rules people set in Dials >
Notifications, kept apart from GTK so they are easy to check.

shell.json keys (written by Dials, Quick Settings and Beacon):
  "focus": "dnd" | "sleep" | "work" | "personal" | ""
                                            the Focus turned on by hand
  "dnd": true/false                        kept in step with "focus" (true
                                            for Do Not Disturb), as before Focus
  "dnd_schedule": {"on": true, "from": "22:00", "to": "07:00", "days": [0..6]}
                                            Do Not Disturb at set times (it may
                                            cross midnight; days 0 = Monday)
  "focus_settings": {"work": {"schedule": {...}, "allow": ["Tide", ...]}, ...}
                                            each other Focus's schedule, and
                                            for every Focus the apps whose
                                            notifications still show
  "notify_apps": {"Tide": "list", ...}      each app's choice: "banners"
                                            (the default), "list" (only in
                                            the notification centre) or "off"

Beacon remembers which apps have sent notifications, so Dials can list them,
in ~/.local/state/freemac/notification-apps.json. Original freemac code.
"""
import datetime as dt
import json
import os

STYLES = (("banners", "Banners"), ("list", "In Notification Centre only"), ("off", "Off"))
DEFAULT_SCHEDULE = {"on": False, "from": "22:00", "to": "07:00"}
EVERY_DAY = [0, 1, 2, 3, 4, 5, 6]
DAY_NAMES = ("M", "T", "W", "T", "F", "S", "S")
# Focus, as on a Mac: (id, name, icon, the schedule it starts with).
FOCUSES = (
    ("dnd", "Do Not Disturb", "freemac-focus-dnd-symbolic", {"from": "22:00", "to": "07:00"}),
    ("sleep", "Sleep", "freemac-focus-sleep-symbolic", {"from": "22:30", "to": "07:00"}),
    ("work", "Work", "freemac-focus-work-symbolic", {"from": "09:00", "to": "17:00", "days": [0, 1, 2, 3, 4]}),
    ("personal", "Personal", "freemac-focus-personal-symbolic", {"from": "18:00", "to": "22:00"}),
)
FOCUS_IDS = tuple(focus[0] for focus in FOCUSES)


def _minutes(text, default):
    try:
        hours, minutes = (int(part) for part in str(text).split(":"))
        if 0 <= hours < 24 and 0 <= minutes < 60:
            return hours * 60 + minutes
    except ValueError:
        pass
    return default


def _settings(prefs, focus):
    data = prefs.get("focus_settings")
    data = data.get(focus) if isinstance(data, dict) else None
    return data if isinstance(data, dict) else {}


def schedule(prefs, focus="dnd"):
    """A Focus's schedule, with anything odd replaced by its default.
    Do Not Disturb keeps its schedule in "dnd_schedule", as it always has."""
    start = dict(DEFAULT_SCHEDULE)
    start.update(next((f[3] for f in FOCUSES if f[0] == focus), {}))
    data = prefs.get("dnd_schedule") if focus == "dnd" else _settings(prefs, focus).get("schedule")
    data = data if isinstance(data, dict) else {}
    out = {"on": bool(data.get("on", False))}
    for key in ("from", "to"):
        minutes = _minutes(data.get(key), _minutes(start[key], 0))
        out[key] = f"{minutes // 60:02d}:{minutes % 60:02d}"
    days = data.get("days", start.get("days", EVERY_DAY))
    days = sorted({d for d in days if isinstance(d, int) and 0 <= d < 7}) if isinstance(days, list) else []
    out["days"] = days if days or "days" in data else list(EVERY_DAY)
    return out


def _occurrence(rule, now):
    """The day the schedule's current stretch began ("2026-11-23"), or None
    when the schedule doesn't have its Focus on at this moment."""
    if not rule["on"] or not rule["days"]:
        return None
    at = now.hour * 60 + now.minute
    start, end = _minutes(rule["from"], 0), _minutes(rule["to"], 0)
    if start == end:
        return None
    day = now.date()
    if start < end:
        on = start <= at < end
    elif at >= start:
        on = True
    else:
        # Crosses midnight (22:00 to 07:00): the early hours belong to the
        # night that began the day before.
        on = at < end
        day -= dt.timedelta(days=1)
    return day.isoformat() if on and day.weekday() in rule["days"] else None


def _in_schedule(rule, now):
    return _occurrence(rule, now) is not None


def scheduled_focus(prefs, now=None):
    """The first Focus whose schedule says it's on at this moment, or None.
    A scheduled Focus turned off by hand stays off until its next time."""
    now = now or dt.datetime.now()
    skip = prefs.get("focus_skip")
    for focus in FOCUS_IDS:
        when = _occurrence(schedule(prefs, focus), now)
        if when and skip != f"{focus}@{when}":
            return focus
    return None


def scheduled_quiet(prefs, now=None):
    """Whether a schedule has a Focus on at this moment."""
    return scheduled_focus(prefs, now) is not None


def manual_focus(prefs):
    """The Focus turned on by hand, or None."""
    focus = prefs.get("focus")
    if focus in FOCUS_IDS:
        return focus
    return "dnd" if prefs.get("dnd") else None


def active_focus(prefs, now=None):
    """The Focus on now, by hand or by its schedule, or None."""
    return manual_focus(prefs) or scheduled_focus(prefs, now)


def quiet(prefs, now=None):
    """A Focus is on, by hand or by a schedule."""
    return active_focus(prefs, now) is not None


def focus_writes(focus, prefs=None, now=None):
    """The shell.json changes that turn this Focus on by hand (None: off).
    Turned off while a schedule has a Focus on, that Focus stays off until
    its schedule next comes round, as on a Mac."""
    focus = focus if focus in FOCUS_IDS else None
    out = {"focus": focus or "", "dnd": focus == "dnd"}
    if focus is None and prefs is not None:
        now = now or dt.datetime.now()
        on = scheduled_focus(prefs, now)
        if on:
            out["focus_skip"] = f"{on}@{_occurrence(schedule(prefs, on), now)}"
    return out


def focus_name(focus):
    return next((f[1] for f in FOCUSES if f[0] == focus), "Focus")


def focus_icon(focus):
    return next((f[2] for f in FOCUSES if f[0] == focus), "freemac-focus-dnd-symbolic")


def allowed_apps(prefs, focus):
    """The apps whose notifications still show while this Focus is on."""
    apps = _settings(prefs, focus).get("allow")
    return [str(app) for app in apps if app] if isinstance(apps, list) else []


def allowed(prefs, app, now=None):
    """Whether this app's banners show now: no Focus is on, or the Focus on
    lets this app through."""
    focus = active_focus(prefs, now)
    return focus is None or (bool(app) and app in allowed_apps(prefs, focus))


def with_focus_setting(prefs, focus, key, value):
    """The whole "focus_settings" value with one Focus's key changed."""
    data = prefs.get("focus_settings")
    data = {k: dict(v) for k, v in data.items() if isinstance(v, dict)} if isinstance(data, dict) else {}
    data.setdefault(focus, {})[key] = value
    return data


def until(prefs, now=None):
    """"until 07:00" when the Focus on now came on by its schedule, else ""."""
    if manual_focus(prefs):
        return ""
    focus = scheduled_focus(prefs, now)
    return f"until {schedule(prefs, focus)['to']}" if focus else ""


def app_style(prefs, app):
    """"banners", "list" or "off" for this app."""
    choices = prefs.get("notify_apps")
    choice = choices.get(app) if isinstance(choices, dict) else None
    return choice if choice in dict(STYLES) else "banners"


def known_apps(path):
    """{app name: icon} for the apps that have sent notifications."""
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {str(k): str(v or "") for k, v in data.items() if k}


def remember_app(path, app, icon):
    """Add an app to the list. Returns True when it was new or its icon changed."""
    if not app:
        return False
    apps = known_apps(path)
    value = icon or apps.get(app, "")
    if app in apps and apps[app] == value:
        return False
    apps[app] = value
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(apps, fh, indent=1)
        os.replace(tmp, path)
    except OSError:
        return False
    return True


def grouped(notes):
    """Notes (newest first) as [(app, [notes])], the app with the newest
    notification first."""
    groups, order = {}, []
    for note in notes:
        key = note.app or ""
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(note)
    return [(key, groups[key]) for key in order]
