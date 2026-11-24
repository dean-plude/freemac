# SPDX-License-Identifier: GPL-3.0-or-later
"""The power schedule, as a Mac's Energy settings have it: start up or wake
at a set time, and sleep, restart or shut down at another, every day, on
weekdays, at weekends or on one day of the week.

The schedule lives in /etc/freemac/power-schedule.json, written by
/usr/libexec/freemac-power-schedule as root, so it holds for every account
and at the login screen. That helper sets the computer's clock alarm (the
RTC) to wake it, and a systemd timer to sleep, restart or shut it down.
When the time comes and someone is logged in, each of them sees a ten-minute
countdown (power_countdown.py) and can cancel it.

Original freemac code.
"""
import json
import time

PATH = "/etc/freemac/power-schedule.json"
RUN_DIR = "/run/freemac-power-schedule"
PENDING = RUN_DIR + "/pending"
ANSWERS = RUN_DIR + "/answers"          # anyone logged in may cancel
WARNING = 600                           # seconds of countdown when someone is logged in

DAYS = (("everyday", "Every Day"), ("weekdays", "Weekdays"), ("weekends", "Weekends"),
        ("mon", "Monday"), ("tue", "Tuesday"), ("wed", "Wednesday"), ("thu", "Thursday"),
        ("fri", "Friday"), ("sat", "Saturday"), ("sun", "Sunday"))
DAY_NUMBERS = {"everyday": range(7), "weekdays": range(5), "weekends": (5, 6),
               "mon": (0,), "tue": (1,), "wed": (2,), "thu": (3,), "fri": (4,), "sat": (5,), "sun": (6,)}
CALENDAR_DAYS = {"everyday": "", "weekdays": "Mon..Fri ", "weekends": "Sat,Sun ", "mon": "Mon ", "tue": "Tue ",
                 "wed": "Wed ", "thu": "Thu ", "fri": "Fri ", "sat": "Sat ", "sun": "Sun "}
ACTIONS = (("sleep", "Sleep"), ("restart", "Restart"), ("shutdown", "Shut Down"))
ACTION_WORDS = {"sleep": "go to sleep", "restart": "restart", "shutdown": "shut down"}


def load(path=PATH):
    """{"wake": rule or None, "action": rule or None}; a rule has days, time
    ("HH:MM") and, for action, what."""
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    return {"wake": valid(data.get("wake"), wake=True), "action": valid(data.get("action"), wake=False)}


def valid(rule, wake):
    """The rule, cleaned, or None when it isn't a whole rule."""
    if not isinstance(rule, dict):
        return None
    days, at = rule.get("days"), str(rule.get("time", ""))
    if days not in DAY_NUMBERS:
        return None
    try:
        hour, minute = (int(x) for x in at.split(":"))
    except ValueError:
        return None
    if not (0 <= hour < 24 and 0 <= minute < 60):
        return None
    clean = {"days": days, "time": f"{hour:02d}:{minute:02d}"}
    if not wake:
        if rule.get("what") not in ACTION_WORDS:
            return None
        clean["what"] = rule["what"]
    return clean


def on_calendar(rule):
    """The rule as a systemd OnCalendar line."""
    return f"{CALENDAR_DAYS[rule['days']]}*-*-* {rule['time']}:00"


def next_time(rule, after=None):
    """The next moment the rule comes round after `after`, as a timestamp."""
    after = time.time() if after is None else after
    hour, minute = (int(x) for x in rule["time"].split(":"))
    base = time.localtime(after)
    for ahead in range(8):
        day = time.localtime(time.mktime((base.tm_year, base.tm_mon, base.tm_mday + ahead, 12, 0, 0, 0, 0, -1)))
        if day.tm_wday not in DAY_NUMBERS[rule["days"]]:
            continue
        when = time.mktime((day.tm_year, day.tm_mon, day.tm_mday, hour, minute, 0, 0, 0, -1))
        if when > after:
            return when
    return None


def clock(at, h24=False):
    hour, minute = (int(x) for x in at.split(":"))
    if h24:
        return f"{hour:02d}:{minute:02d}"
    return f"{(hour % 12) or 12}:{minute:02d} {'AM' if hour < 12 else 'PM'}"


def describe(schedule, h24=False):
    """A line for Dials, such as "Starts up weekdays at 7:00 AM; shuts down every day at 10:30 PM"."""
    parts = []
    names = dict(DAYS)
    for key in ("wake", "action"):
        rule = schedule.get(key)
        if not rule:
            continue
        verb = "starts up or wakes" if key == "wake" else \
            {"sleep": "sleeps", "restart": "restarts", "shutdown": "shuts down"}[rule["what"]]
        days = names[rule["days"]]
        days = days.lower() if rule["days"] in ("everyday", "weekdays", "weekends") else "on " + days + "s"
        parts.append(f"{verb} {days} at {clock(rule['time'], h24)}")
    if not parts:
        return "Off"
    text = "; ".join(parts)
    return text[0].upper() + text[1:]
