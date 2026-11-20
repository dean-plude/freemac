# SPDX-License-Identifier: GPL-3.0-or-later
"""Nudge's reminders, kept on this computer.

Each list is one iCalendar file of to-dos (VTODO) in
~/.local/share/freemac/reminders/, named for the list's id, with the list's
name and colour in the calendar's own lines. Other apps that read .ics files
can import a list. Lines we don't use are kept as they were. Original freemac
code.
"""
import datetime as dt
import os
import re
import uuid

from .calendar_store import _escape, _fold, _lines, _unescape, _when

COLORS = {"blue": "#2f7bf5", "red": "#f04d3e", "orange": "#f59a23", "yellow": "#f2c418",
          "green": "#34b85a", "purple": "#a35ee6", "brown": "#a2845e", "grey": "#8e8e93"}
PRIORITIES = {0: "None", 9: "Low", 5: "Medium", 1: "High"}   # iCalendar's numbers
MARKS = {0: "", 9: "!", 5: "!!", 1: "!!!"}
DUE_HOUR = 9   # a reminder due on a day, with no time, nudges at 9 AM


def store_dir():
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data, "freemac", "reminders")


class Reminder:
    def __init__(self, title="", list_id="", uid=None):
        self.uid = uid or f"{uuid.uuid4()}@freemac"
        self.title, self.list_id, self.notes = title, list_id, ""
        self.due = None          # a datetime, or None
        self.due_time = False    # True when the due date has a time of day
        self.done = False
        self.completed = None    # when it was ticked off
        self.flagged = False
        self.priority = 0
        self.created = dt.datetime.now().replace(microsecond=0)
        self.extra = []

    def copy(self):
        twin = Reminder(self.title, self.list_id, self.uid)
        for name in ("notes", "due", "due_time", "done", "completed", "flagged", "priority", "created"):
            setattr(twin, name, getattr(self, name))
        twin.extra = list(self.extra)
        return twin

    def due_at(self):
        """When it nudges: its time, or 9 AM on its day."""
        if self.due is None:
            return None
        return self.due if self.due_time else self.due.replace(hour=DUE_HOUR, minute=0)

    def overdue(self, now=None):
        now = now or dt.datetime.now()
        if self.done or self.due is None:
            return False
        if self.due_time:
            return self.due < now
        return self.due.date() < now.date()

    def matches(self, words):
        hay = f"{self.title} {self.notes}".lower()
        return all(w in hay for w in words.lower().split())


class ReminderList:
    def __init__(self, name="Reminders", color="blue", list_id=None):
        self.id = list_id or uuid.uuid4().hex[:12]
        self.name, self.color = name, color
        self.order = 0
        self.reminders = []
        self.extra = []

    @property
    def hex(self):
        return COLORS.get(self.color, COLORS["blue"])

    def open_items(self):
        return [r for r in self.reminders if not r.done]


def _stamp(when):
    return when.strftime("%Y%m%dT%H%M%S")


def parse(text, list_id):
    """A ReminderList from one file's text."""
    found = ReminderList(list_id=list_id)
    current = None
    nested = 0
    for line in _lines(text):
        name_part, _sep, value = line.partition(":")
        name, *param_list = name_part.split(";")
        name = name.upper()
        params = dict(p.split("=", 1) for p in param_list if "=" in p)
        if current is not None:
            if name == "BEGIN":
                nested += 1
            if nested:
                current.extra.append(line)
                if name == "END":
                    nested -= 1
                continue
            if name == "END" and value.upper() == "VTODO":
                found.reminders.append(current)
                current = None
            elif name == "UID":
                current.uid = value
            elif name == "SUMMARY":
                current.title = _unescape(value)
            elif name == "DESCRIPTION":
                current.notes = _unescape(value)
            elif name == "DUE":
                try:
                    current.due, all_day = _when(value, params)
                    current.due_time = not all_day
                except ValueError:
                    current.extra.append(line)
            elif name == "STATUS":
                current.done = value.upper() == "COMPLETED"
            elif name == "COMPLETED":
                try:
                    current.completed, _ = _when(value, params)
                    current.done = True
                except ValueError:
                    pass
            elif name == "PRIORITY":
                try:
                    number = int(value)
                except ValueError:
                    number = 0
                current.priority = 0 if number == 0 else 1 if number <= 4 else 5 if number == 5 else 9
            elif name == "X-FREEMAC-FLAGGED":
                current.flagged = value.strip() == "1"
            elif name == "CREATED":
                try:
                    current.created, _ = _when(value, params)
                except ValueError:
                    pass
            elif name in ("DTSTAMP", "LAST-MODIFIED"):
                pass
            else:
                current.extra.append(line)
            continue
        if name == "BEGIN" and value.upper() == "VTODO":
            current = Reminder(list_id=list_id)
            nested = 0
        elif name == "X-WR-CALNAME":
            found.name = _unescape(value)
        elif name == "X-FREEMAC-COLOR":
            found.color = value.strip().lower()
        elif name == "X-FREEMAC-ORDER":
            try:
                found.order = int(value)
            except ValueError:
                pass
        elif name in ("BEGIN", "END", "VERSION", "PRODID", "CALSCALE"):
            pass
        else:
            found.extra.append(line)
    return found


def dump(rlist):
    now = _stamp(dt.datetime.now())
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//freemac//Nudge//EN",
             f"X-WR-CALNAME:{_escape(rlist.name)}", f"X-FREEMAC-COLOR:{rlist.color}",
             f"X-FREEMAC-ORDER:{rlist.order}"]
    lines += rlist.extra
    for r in rlist.reminders:
        lines += ["BEGIN:VTODO", f"UID:{r.uid}", f"DTSTAMP:{now}", f"CREATED:{_stamp(r.created)}",
                  f"SUMMARY:{_escape(r.title)}"]
        if r.notes:
            lines.append(f"DESCRIPTION:{_escape(r.notes)}")
        if r.due is not None:
            lines.append(f"DUE:{_stamp(r.due)}" if r.due_time else f"DUE;VALUE=DATE:{r.due:%Y%m%d}")
        if r.done:
            lines.append("STATUS:COMPLETED")
            lines.append(f"COMPLETED:{_stamp(r.completed or dt.datetime.now())}")
        else:
            lines.append("STATUS:NEEDS-ACTION")
        if r.priority:
            lines.append(f"PRIORITY:{r.priority}")
        if r.flagged:
            lines.append("X-FREEMAC-FLAGGED:1")
        lines += r.extra
        lines.append("END:VTODO")
    lines.append("END:VCALENDAR")
    folded = []
    for line in lines:
        folded += _fold(line)
    return "\r\n".join(folded) + "\r\n"


def path_of(rlist):
    return os.path.join(store_dir(), f"{rlist.id}.ics")


def load():
    """Every list, in the user's order; one empty "Reminders" list when there
    are none yet (not saved until something is put in it)."""
    found = []
    folder = store_dir()
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        names = []
    for name in names:
        if not name.endswith(".ics") or not re.fullmatch(r"[\w.-]+\.ics", name):
            continue
        try:
            with open(os.path.join(folder, name), encoding="utf-8", errors="replace") as f:
                found.append(parse(f.read(), name[:-4]))
        except OSError:
            continue
    found.sort(key=lambda l: (l.order, l.name.lower()))
    return found or [ReminderList("Reminders", "blue")]


def save(rlist):
    folder = store_dir()
    os.makedirs(folder, exist_ok=True)
    path = path_of(rlist)
    with open(path + ".new", "w", encoding="utf-8", newline="") as f:
        f.write(dump(rlist))
    os.replace(path + ".new", path)


def remove(rlist):
    try:
        os.remove(path_of(rlist))
    except OSError:
        pass


def every(lists):
    return [r for l in lists for r in l.reminders]


def due_nudges(lists, since, until):
    """Open reminders whose time to nudge falls after since and up to until,
    soonest first."""
    found = [r for r in every(lists) if not r.done and r.due is not None and since < r.due_at() <= until]
    return sorted(found, key=lambda r: r.due_at())


def due_text(reminder, today=None):
    """Today, Tomorrow, Yesterday, Friday or 11/28/26, then the time if it
    has one: how Nudge writes a due date."""
    if reminder.due is None:
        return ""
    today = today or dt.date.today()
    day = reminder.due.date()
    gap = (day - today).days
    if gap == 0:
        words = "Today"
    elif gap == 1:
        words = "Tomorrow"
    elif gap == -1:
        words = "Yesterday"
    elif 1 < gap < 7:
        words = f"{day:%A}"
    else:
        words = f"{day.month}/{day.day}/{day:%y}"
    if reminder.due_time:
        hour = reminder.due.hour % 12 or 12
        suffix = "AM" if reminder.due.hour < 12 else "PM"
        clock = f"{hour} {suffix}" if reminder.due.minute == 0 else f"{hour}:{reminder.due.minute:02d} {suffix}"
        words += f", {clock}"
    return words


def parse_due(text, today=None):
    """A due date typed loosely: today, tomorrow, friday, 11/28, Nov 28,
    2026-11-28, each with an optional time (5pm, 17:30, at 9:15 am).
    (datetime, has_time), (None, False) for empty text, or None when it
    can't be read."""
    from .calendar_store import parse_time
    t = text.strip().lower()
    if not t:
        return None, False
    today = today or dt.date.today()
    clock = None
    m = re.search(r"(?:\bat\s+)?(\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.)|\d{1,2}:\d{2}|noon|midnight)$", t)
    if m:
        piece = m.group(1).replace(".", "")
        hm = parse_time(piece)
        if hm is None:
            return None
        clock = dt.time(*hm)
        t = t[:m.start()].strip().rstrip(",").strip()
    day = None
    if t in ("", "today"):
        day = today
    elif t == "tomorrow":
        day = today + dt.timedelta(days=1)
    else:
        names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        short = [n[:3] for n in names]
        key = t.removeprefix("next ").strip()
        if key in names or key in short:
            want = (names.index(key) if key in names else short.index(key))
            ahead = (want - today.weekday()) % 7 or 7
            day = today + dt.timedelta(days=ahead)
        else:
            for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%B %d %Y", "%b %d %Y", "%B %d, %Y", "%b %d, %Y"):
                try:
                    day = dt.datetime.strptime(t, fmt).date()
                    break
                except ValueError:
                    pass
            if day is None:
                for fmt in ("%m/%d", "%B %d", "%b %d", "%d %B", "%d %b"):
                    try:
                        found = dt.datetime.strptime(f"{t} {today.year}", fmt + " %Y").date()
                    except ValueError:
                        continue
                    day = found if found >= today else found.replace(year=today.year + 1)
                    break
    if day is None:
        return None
    if clock is None:
        return dt.datetime.combine(day, dt.time()), False
    return dt.datetime.combine(day, clock), True
