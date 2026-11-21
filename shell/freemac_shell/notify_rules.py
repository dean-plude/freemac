# SPDX-License-Identifier: GPL-3.0-or-later
"""What Beacon does with a notification: the rules people set in Dials >
Notifications, kept apart from GTK so they are easy to check.

shell.json keys (written by Dials):
  "dnd": true/false                        Do Not Disturb, by hand
  "dnd_schedule": {"on": true, "from": "22:00", "to": "07:00"}
                                            Do Not Disturb every day between
                                            two times (it may cross midnight)
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


def _minutes(text, default):
    try:
        hours, minutes = (int(part) for part in str(text).split(":"))
        if 0 <= hours < 24 and 0 <= minutes < 60:
            return hours * 60 + minutes
    except ValueError:
        pass
    return default


def schedule(prefs):
    """The Do Not Disturb schedule, with anything odd replaced by its default."""
    data = prefs.get("dnd_schedule")
    data = data if isinstance(data, dict) else {}
    out = dict(DEFAULT_SCHEDULE)
    out["on"] = bool(data.get("on", False))
    for key in ("from", "to"):
        minutes = _minutes(data.get(key), _minutes(DEFAULT_SCHEDULE[key], 0))
        out[key] = f"{minutes // 60:02d}:{minutes % 60:02d}"
    return out


def scheduled_quiet(prefs, now=None):
    """Whether the schedule says Do Not Disturb is on at this moment."""
    rule = schedule(prefs)
    if not rule["on"]:
        return False
    now = now or dt.datetime.now()
    at = now.hour * 60 + now.minute
    start, end = _minutes(rule["from"], 0), _minutes(rule["to"], 0)
    if start == end:
        return False
    if start < end:
        return start <= at < end
    return at >= start or at < end        # crosses midnight: 22:00 to 07:00


def quiet(prefs, now=None):
    """Do Not Disturb is on, by hand or by the schedule."""
    return bool(prefs.get("dnd")) or scheduled_quiet(prefs, now)


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
