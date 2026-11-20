# SPDX-License-Identifier: GPL-3.0-or-later
"""Tide's calendars: Home, kept on this computer, each calendar from an
online account (Dials > Internet Accounts), and Birthdays from Crew.

Every event belongs to one of them: an event from an account carries the
account and collection it came from (X-FREEMAC-SOURCE, see dav_sync.py);
an event without that mark is in Home. Each calendar has a colour (an
account's own, until the user picks another) and can be shown or hidden.
Those choices are kept in ~/.config/freemac/calendars.json. No GTK.
Original freemac code.
"""
import os

from . import dav_sync

HOME = ""                 # the key of the calendar on this computer
BIRTHDAYS = "birthdays"
COLORS = {"red": "#f04d3e", "orange": "#f59a23", "yellow": "#f2c418", "green": "#34b85a",
          "blue": "#2f7bf5", "purple": "#a35ee6", "brown": "#a2845e"}
# Colours for calendars that come with none, in the order they are handed out.
ROTATION = ("green", "orange", "red", "yellow", "brown", "purple", "blue")


class Calendar:
    def __init__(self, key, name, color, group):
        self.key, self.name, self.color, self.group = key, name, color, group

    @property
    def rgb(self):
        return rgb(self.color)

    @property
    def editable(self):
        return self.key != BIRTHDAYS

    def __repr__(self):
        return f"Calendar({self.key!r}, {self.name!r}, {self.color!r}, {self.group!r})"


def rgb(hexcode):
    h = (hexcode or "").lstrip("#")
    try:
        return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except ValueError:
        return rgb(COLORS["blue"])


def _hex(value):
    """A CalDAV colour (#RRGGBB or #RRGGBBAA) as #rrggbb, or None."""
    h = (value or "").strip().lstrip("#")
    if len(h) in (6, 8) and all(c in "0123456789abcdefABCDEF" for c in h):
        return "#" + h[:6].lower()
    return None


def settings_path():
    return os.path.join(dav_sync.config_dir(), "calendars.json")


def load_settings():
    found = dav_sync._read(settings_path(), {})
    return found if isinstance(found, dict) else {}


def save_settings(settings):
    dav_sync._write(settings_path(), settings)


def calendars(settings=None):
    """Every calendar, in the order the list shows them."""
    settings = settings if settings is not None else load_settings()
    chosen = settings.get("colors", {})
    found = [Calendar(HOME, "Home", chosen.get(HOME, COLORS["blue"]), "On My Computer")]
    spare = 0
    for account in dav_sync.load_accounts():
        if not account.calendars:
            continue
        state = dav_sync.load_state(account)
        for url, entry in state.items():
            if not isinstance(entry, dict) or entry.get("kind") != "events":
                continue
            key = dav_sync._key(account, url)
            color = chosen.get(key) or _hex(entry.get("color"))
            if not color:
                color = COLORS[ROTATION[spare % len(ROTATION)]]
                spare += 1
            found.append(Calendar(key, entry.get("name") or "Calendar", color, account.title))
    found.append(Calendar(BIRTHDAYS, "Birthdays", chosen.get(BIRTHDAYS, COLORS["purple"]), "Other"))
    return found


def key_of(event):
    """The calendar an event is in."""
    if getattr(event, "person", None):
        return BIRTHDAYS
    return dav_sync._source_of(event.extra) or HOME


def hidden(settings=None):
    settings = settings if settings is not None else load_settings()
    return set(settings.get("hidden", []))


def set_shown(key, shown):
    settings = load_settings()
    off = set(settings.get("hidden", []))
    (off.discard if shown else off.add)(key)
    settings["hidden"] = sorted(off)
    save_settings(settings)


def set_color(key, hexcode):
    settings = load_settings()
    settings.setdefault("colors", {})[key] = hexcode
    save_settings(settings)


def default_key(settings=None):
    """Where a new event goes: the first account's first calendar, as
    freemac-sync would send it, or Home when there are no accounts."""
    remote = [c for c in calendars(settings) if c.key not in (HOME, BIRTHDAYS)]
    return remote[0].key if remote else HOME


def move(event, key):
    """Put an event (a copy, changed in place) in another calendar. Moving
    one to Home keeps it here: no account takes it the next time they sync."""
    event.extra = dav_sync._set_source(event.extra, key or None)
    if key == HOME:
        accounts = dav_sync.load_accounts()
        for account in accounts:
            stay = set(account.local_only.get("events", []))
            if event.uid not in stay:
                account.local_only = dict(account.local_only, events=sorted(stay | {event.uid}))
        if accounts:
            dav_sync.save_accounts(accounts)
    return event
