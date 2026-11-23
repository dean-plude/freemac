# SPDX-License-Identifier: GPL-3.0-or-later
"""Mouse Keys, as on a Mac: the numeric keypad moves the pointer and clicks.

Strata does the moving and clicking (strata/shell/mouse-keys.hpp). When
Option is pressed five times in a row it tells Topline "mouse turned on" or
"mouse turned off"; Topline saves that in wayfire.ini, as Dials > Accessibility
would, and says so on screen with Sticky Keys' notice. Original freemac code.
"""
import os

from . import sounds
from .ini import ini_set

WAYFIRE_INI = os.path.join(os.path.expanduser("~/.config"), "wayfire.ini")


def parse(line):
    """True (turned on), False (turned off) or None for anything else."""
    words = line.split()
    if len(words) == 3 and words[:2] == ["mouse", "turned"] and words[2] in ("on", "off"):
        return words[2] == "on"
    return None


class Toggle:
    def __init__(self, notice):
        self.notice = notice   # shows a few words in the top-right corner

    def handle(self, line):
        on = parse(line)
        if on is None:
            return
        try:
            ini_set(WAYFIRE_INI, "strata-shell", "mouse_keys", "true" if on else "false")
        except OSError:
            pass
        sounds.play(sounds.path_of("pop"), 70, gap=0.03)
        self.notice("Mouse Keys On" if on else "Mouse Keys Off")
