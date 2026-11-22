# SPDX-License-Identifier: GPL-3.0-or-later
"""Auto appearance, as on a Mac: light while the sun is up and dark after
it sets, where you are (sun.py), when Dials > Appearance is set to Auto
(shell.json "appearance_auto").

Topline checks once a minute and switches only when the sun has just risen
or set, or Auto has just been chosen, with `freemac-dials --appearance`,
the same as the Dark Mode tile. So Dark Mode turned on by hand in the
afternoon stays on until the next sunset or sunrise switches it again.
Original freemac code.
"""
import subprocess

from gi.repository import GLib

from . import style, sun

CHECK_SECONDS = 60


def wanted_dark(day):
    """Dark when the sun is down; None (leave it) when we can't tell."""
    return None if day is None else not day


def should_switch(last_day, day, dark_now):
    """Whether to switch now: only as the sun rises or sets (or the first
    time), and only if the mode isn't already right."""
    if day is None or day == last_day:
        return False
    return wanted_dark(day) != dark_now


class Follower:
    def __init__(self):
        self.last_day = None     # whether it was day at the last check, while Auto was on
        self._monitor = None

    def start(self):
        self._monitor = style.watch_prefs(self.check)
        self.check()
        GLib.timeout_add_seconds(CHECK_SECONDS, self._tick)

    def _tick(self):
        self.check()
        return True

    def check(self):
        if not style.prefs().get("appearance_auto", False):
            self.last_day = None
            return
        day = sun.is_day()
        if should_switch(self.last_day, day, style.is_dark()):
            try:
                subprocess.Popen(["freemac-dials", "--appearance", "dark" if wanted_dark(day) else "light"],
                                 start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                pass
        self.last_day = day
