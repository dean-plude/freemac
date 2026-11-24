# SPDX-License-Identifier: GPL-3.0-or-later
"""Announcements, as on a Mac (Dials > Accessibility > Spoken Content): the
computer says the time on the hour, half hour or quarter hour, and reads
out each notification as its banner shows, in the Spoken Content voice
(speak.py).

    shell.json "announce_time"            "off", "hour", "half" or "quarter"
    shell.json "announce_notifications"   true to read out banners

Topline's clock says the time (topline.py), Beacon reads its banners
(beacon.py). Neither speaks while a Focus is on: a Focus is for quiet, and
a notification it holds back has no banner to read. Original freemac code.
"""
import time

from . import notify_rules, speak, style

EVERY = (("off", "Off"), ("hour", "On the hour"), ("half", "On the half hour"),
         ("quarter", "On the quarter hour"))
STEP = {"hour": 60, "half": 30, "quarter": 15}


def time_every(prefs=None):
    prefs = style.prefs() if prefs is None else prefs
    value = prefs.get("announce_time", "off")
    return value if value in STEP else "off"


def due(minute, every):
    """Whether the time is said at this minute past the hour."""
    step = STEP.get(every)
    return bool(step) and minute % step == 0


def time_words(moment, twenty_four=False):
    """What is said: "It's 3 o'clock", "It's 3:15 PM", "It's 15:15"."""
    hour, minute = moment.tm_hour, moment.tm_min
    if twenty_four:
        if minute == 0:
            return f"It's {hour} hundred"
        return f"It's {hour}:{minute:02d}"
    twelve = hour % 12 or 12
    if minute == 0:
        return f"It's {twelve} o'clock"
    return f"It's {twelve}:{minute:02d} {'AM' if hour < 12 else 'PM'}"


class Clock:
    """Says the time once at each due minute. tick() is called by Topline's
    clock, every minute or every second."""

    def __init__(self):
        self.last = None

    def tick(self, prefs, moment=None):
        moment = time.localtime() if moment is None else moment
        every = time_every(prefs)
        key = (moment.tm_yday, moment.tm_hour, moment.tm_min)
        if key == self.last or not due(moment.tm_min, every):
            return None
        self.last = key
        if notify_rules.active_focus(prefs) or not speak.available():
            return None
        words = time_words(moment, style.h24(prefs))
        speak.say(words)
        return words


def notification_words(app, summary):
    """What is said for a banner: "Nudge: Call Sam back"."""
    summary = " ".join((summary or "").split())
    app = " ".join((app or "").split())
    if app and summary:
        return f"{app}: {summary}"
    return app or summary


def notification(prefs, app, summary):
    """Read out a banner that just showed, if Dials says to."""
    if not prefs.get("announce_notifications") or not speak.available():
        return None
    words = notification_words(app, summary)
    if words:
        speak.say(words)
    return words or None
