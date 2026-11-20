# SPDX-License-Identifier: GPL-3.0-or-later
"""The events Tide keeps, in one iCalendar file on this computer.

The file is ~/.local/share/freemac/calendar.ics, a standard .ics that other
calendar apps can import. Times are kept as local time with no time zone
(iCalendar's "floating" times); times written in UTC by other apps are moved
into local time when read. An event can repeat every day, week, month or
year, and can have one alert, a set time before it starts (shown by Beacon). No GTK here, so the menu bar and Seek can read events cheaply.
Original freemac code.
"""
import calendar
import datetime as dt
import os
import uuid
import zoneinfo

REPEATS = {"": "Never", "DAILY": "Every Day", "WEEKLY": "Every Week",
           "MONTHLY": "Every Month", "YEARLY": "Every Year"}
# Minutes before the start; None is no alert. An all-day event's alert
# counts back from 9 AM on its first day.
ALERTS = {None: "None", 0: "At time of event", 5: "5 minutes before", 10: "10 minutes before",
          15: "15 minutes before", 30: "30 minutes before", 60: "1 hour before",
          120: "2 hours before", 1440: "1 day before", 2880: "2 days before"}
ALL_DAY_ALERT_HOUR = 9


def store_path():
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data, "freemac", "calendar.ics")


class Event:
    """One event. start and end are datetimes; an all-day event runs from
    midnight on its first day to midnight after its last (end is excluded)."""

    def __init__(self, title="New Event", start=None, end=None, all_day=False,
                 location="", notes="", repeat="", uid=None, alert=None):
        self.uid = uid or f"{uuid.uuid4()}@freemac"
        self.title, self.location, self.notes = title, location, notes
        self.start = start or dt.datetime.now().replace(minute=0, second=0, microsecond=0)
        self.end = end or self.start + dt.timedelta(hours=1)
        self.all_day, self.repeat, self.alert = all_day, repeat, alert
        self.extra = []   # lines we don't use, kept as they were

    def copy(self):
        twin = Event(self.title, self.start, self.end, self.all_day, self.location,
                     self.notes, self.repeat, self.uid, self.alert)
        twin.extra = list(self.extra)
        return twin


class Occurrence:
    """An event on one of its dates (a repeating event has many)."""

    def __init__(self, event, start, end):
        self.event, self.start, self.end = event, start, end

    @property
    def all_day(self):
        return self.event.all_day

    def days(self):
        """The dates this occurrence touches."""
        day = self.start.date()
        last = (self.end - dt.timedelta(microseconds=1)).date() if self.end > self.start else day
        while day <= last:
            yield day
            day += dt.timedelta(days=1)


# -- reading and writing .ics ------------------------------------------------
def _unescape(text):
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            n = text[i + 1]
            out.append("\n" if n in "nN" else n)
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _escape(text):
    return (text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
            .replace("\r\n", "\\n").replace("\n", "\\n"))


def _when(value, params):
    """(datetime, all_day) from a DTSTART or DTEND value."""
    value = value.strip()
    if params.get("VALUE") == "DATE" or (len(value) == 8 and value.isdigit()):
        return dt.datetime.strptime(value[:8], "%Y%m%d"), True
    utc = value.endswith("Z")
    stamp = dt.datetime.strptime(value.rstrip("Z")[:15], "%Y%m%dT%H%M%S")
    if utc:
        stamp = stamp.replace(tzinfo=dt.timezone.utc).astimezone().replace(tzinfo=None)
    elif params.get("TZID"):
        # A time in a named zone (as online calendars write them): moved
        # into this computer's local time.
        try:
            zone = zoneinfo.ZoneInfo(params["TZID"].strip('"'))
            stamp = stamp.replace(tzinfo=zone).astimezone().replace(tzinfo=None)
        except (zoneinfo.ZoneInfoNotFoundError, ValueError):
            pass
    return stamp, False


def _lines(text):
    """The file's content lines, with folded lines joined back up."""
    lines = []
    for raw in text.splitlines():
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        elif raw:
            lines.append(raw)
    return lines


def _alarm_minutes(lines):
    """Minutes before the start from a VALARM's lines, or None when it isn't
    a plain "some time before the start" alarm."""
    for line in lines:
        name_part, _sep, value = line.partition(":")
        name, *param_list = name_part.split(";")
        params = {k.upper(): v.upper() for k, v in (p.split("=", 1) for p in param_list if "=" in p)}
        if name.upper() != "TRIGGER":
            continue
        if params.get("VALUE") == "DATE-TIME" or params.get("RELATED") == "END":
            return None
        before = -_duration(value)
        if before < dt.timedelta(0):
            return None
        return int(before.total_seconds() // 60)
    return None


def parse(text):
    events, current, alarm = [], None, None
    for line in _lines(text):
        name_part, _sep, value = line.partition(":")
        name, *param_list = name_part.split(";")
        name = name.upper()
        params = dict(p.split("=", 1) for p in param_list if "=" in p)
        if alarm is not None:
            alarm.append(line)
            if name == "END" and value.upper() == "VALARM":
                minutes = _alarm_minutes(alarm)
                if minutes is not None and current.get("alert") is None:
                    current["alert"] = minutes
                else:
                    current["extra"] += alarm   # another alarm, kept as it was
                alarm = None
        elif name == "BEGIN" and value.upper() == "VALARM" and current is not None:
            alarm = [line]
        elif name == "BEGIN" and value.upper() == "VEVENT":
            current = {"extra": []}
        elif name == "END" and value.upper() == "VEVENT" and current is not None:
            if "start" in current:
                events.append(_event_from(current))
            current = None
        elif current is not None:
            if name == "DTSTART":
                current["start"], current["all_day"] = _when(value, params)
            elif name == "DTEND":
                current["end"], _ = _when(value, params)
            elif name == "DURATION":
                current["duration"] = value
            elif name in ("SUMMARY", "LOCATION", "DESCRIPTION", "UID"):
                current[name] = _unescape(value)
            elif name == "RRULE":
                rule = dict(p.split("=", 1) for p in value.split(";") if "=" in p)
                if rule.get("FREQ") in REPEATS and not set(rule) - {"FREQ", "WKST"}:
                    current["repeat"] = rule["FREQ"]
                else:
                    current["extra"].append(line)   # a rule we can't show; kept, shown once
            elif name not in ("DTSTAMP", "LAST-MODIFIED"):
                current["extra"].append(line)
    return events


def _duration(text):
    """A simple iCalendar DURATION (P1D, PT1H30M) as a timedelta."""
    text, sign = text.strip(), 1
    if text.startswith("-"):
        sign, text = -1, text[1:]
    text = text.lstrip("+").lstrip("P")
    days = seconds = 0
    number = ""
    in_time = False
    for c in text:
        if c == "T":
            in_time = True
        elif c.isdigit():
            number += c
        elif number:
            n = int(number)
            number = ""
            if c == "W":
                days += 7 * n
            elif c == "D":
                days += n
            elif c == "H" and in_time:
                seconds += 3600 * n
            elif c == "M" and in_time:
                seconds += 60 * n
            elif c == "S" and in_time:
                seconds += n
    return sign * dt.timedelta(days=days, seconds=seconds)


def _event_from(data):
    start, all_day = data["start"], data.get("all_day", False)
    end = data.get("end")
    if end is None:
        if "duration" in data:
            end = start + _duration(data["duration"])
        else:
            end = start + (dt.timedelta(days=1) if all_day else dt.timedelta(0))
    if end < start:
        end = start
    event = Event(data.get("SUMMARY", "") or "Untitled", start, end, all_day,
                  data.get("LOCATION", ""), data.get("DESCRIPTION", ""),
                  data.get("repeat", ""), data.get("UID"), data.get("alert"))
    event.extra = data["extra"]
    return event


def _fold(line):
    out = []
    while len(line.encode()) > 74:
        cut = 74
        while len(line[:cut].encode()) > 74:
            cut -= 1
        out.append(line[:cut])
        line = " " + line[cut:]
    out.append(line)
    return out


def dump(events):
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//freemac//Tide//EN", "CALSCALE:GREGORIAN"]
    for e in events:
        lines += ["BEGIN:VEVENT", f"UID:{e.uid}", f"DTSTAMP:{stamp}"]
        if e.all_day:
            lines.append(f"DTSTART;VALUE=DATE:{e.start:%Y%m%d}")
            lines.append(f"DTEND;VALUE=DATE:{e.end:%Y%m%d}")
        else:
            lines.append(f"DTSTART:{e.start:%Y%m%dT%H%M%S}")
            lines.append(f"DTEND:{e.end:%Y%m%dT%H%M%S}")
        lines.append(f"SUMMARY:{_escape(e.title)}")
        if e.location:
            lines.append(f"LOCATION:{_escape(e.location)}")
        if e.notes:
            lines.append(f"DESCRIPTION:{_escape(e.notes)}")
        if e.repeat:
            lines.append(f"RRULE:FREQ={e.repeat}")
        lines += e.extra
        if e.alert is not None:
            lines += ["BEGIN:VALARM", "ACTION:DISPLAY", f"DESCRIPTION:{_escape(e.title)}",
                      f"TRIGGER:-PT{e.alert}M" if e.alert else "TRIGGER:PT0M", "END:VALARM"]
        lines.append("END:VEVENT")
    lines.append("END:VCALENDAR")
    folded = []
    for line in lines:
        folded += _fold(line)
    return "\r\n".join(folded) + "\r\n"


def load(path=None):
    try:
        with open(path or store_path(), encoding="utf-8", errors="replace") as f:
            return parse(f.read())
    except OSError:
        return []


def save(events, path=None):
    path = path or store_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temp = path + ".new"
    with open(temp, "w", encoding="utf-8", newline="") as f:
        f.write(dump(events))
    os.replace(temp, path)


# -- dates an event falls on ------------------------------------------------
def _add_months(day, months):
    """day moved by months, or None when that month has no such day (the 31st)."""
    month0 = day.month - 1 + months
    year, month = day.year + month0 // 12, month0 % 12 + 1
    if day.day > calendar.monthrange(year, month)[1]:
        return None
    return day.replace(year=year, month=month)


def _starts(event, until, since):
    """Start times of event's repeats from about since up to until."""
    start, step = event.start, event.repeat
    if not step:
        yield start
        return
    if step in ("DAILY", "WEEKLY"):
        days = 1 if step == "DAILY" else 7
        length = max((event.end - event.start).days + 1, 1)
        skip = max(((since - start).days - length) // days, 0)
        n = skip
        while True:
            when = start + dt.timedelta(days=days * n)
            if when >= until:
                return
            yield when
            n += 1
    months = 1 if step == "MONTHLY" else 12
    n = max(((since.year - start.year) * 12 + since.month - start.month) // months - 1, 0)
    while True:
        when = _add_months(start, months * n)
        n += 1
        if when is None:
            if n > 100000:
                return
            continue
        if when >= until:
            return
        yield when


def occurrences(events, first, last):
    """Occurrences that touch any date from first to last (dates, inclusive),
    by start time, all-day ones first on a day."""
    since = dt.datetime.combine(first, dt.time())
    until = dt.datetime.combine(last + dt.timedelta(days=1), dt.time())
    found = []
    for event in events:
        if event.start >= until:
            continue
        length = event.end - event.start
        for start in _starts(event, until, since):
            end = start + length
            if end > since or (end == start and start >= since):
                found.append(Occurrence(event, start, end))
    found.sort(key=lambda o: (o.start.date(), not o.all_day, o.start, o.event.title.lower()))
    return found


def on_day(events, day):
    return [o for o in occurrences(events, day, day) if day in set(o.days())]


def alert_time(occurrence):
    """When an occurrence's alert goes off, or None if it has none."""
    minutes = occurrence.event.alert
    if minutes is None:
        return None
    base = occurrence.start
    if occurrence.all_day:
        base += dt.timedelta(hours=ALL_DAY_ALERT_HOUR)
    return base - dt.timedelta(minutes=minutes)


def due_alerts(events, since, until):
    """Occurrences whose alert goes off after since and up to until
    (datetimes), soonest first."""
    reach = max((m for m in ALERTS if m), default=0)
    last = (until + dt.timedelta(minutes=reach, days=1)).date()
    found = []
    for occ in occurrences([e for e in events if e.alert is not None], since.date(), last):
        when = alert_time(occ)
        if when is not None and since < when <= until:
            found.append((when, occ))
    found.sort(key=lambda pair: pair[0])
    return [occ for _when, occ in found]


def time_text(when):
    """9 AM, 9:30 AM: how Tide writes a time of day."""
    hour = when.hour % 12 or 12
    suffix = "AM" if when.hour < 12 else "PM"
    return f"{hour} {suffix}" if when.minute == 0 else f"{hour}:{when.minute:02d} {suffix}"


def parse_time(text):
    """A time of day typed loosely (9, 9:30, 9.30pm, 21:30, noon) as
    (hour, minute), or None."""
    t = text.strip().lower().replace(".", ":").replace(" ", "")
    if t in ("noon", "midday"):
        return 12, 0
    if t == "midnight":
        return 0, 0
    suffix = ""
    for end in ("am", "pm", "a", "p"):
        if t.endswith(end):
            suffix, t = end[0], t[: -len(end)]
            break
    if ":" in t:
        h, _, m = t.partition(":")
    elif len(t) in (3, 4) and t.isdigit():
        h, m = t[:-2], t[-2:]
    else:
        h, m = t, "0"
    if not (h.isdigit() and m.isdigit()):
        return None
    hour, minute = int(h), int(m)
    if suffix:
        if not 1 <= hour <= 12:
            return None
        hour = hour % 12 + (12 if suffix == "p" else 0)
    if not (0 <= hour < 24 and 0 <= minute < 60):
        return None
    return hour, minute
