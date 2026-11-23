# SPDX-License-Identifier: GPL-3.0-or-later
"""Slow Keys' clicks, as on a Mac: a soft tick as a key goes down and a pop
once it has been held long enough to count.

Strata does the keys themselves (strata/shell/slow-keys.hpp) and, while
"Use click key sounds" is on in Dials > Accessibility, tells Topline over
its socket: "slow pressed" and "slow accepted".

A click comes with every key typed, so the two sounds are kept loaded and
ready in Topline (GStreamer), not started as a new program each time as
other sounds are: on a slow PC that could hold up the keyboard for long
enough that the app starts repeating the key. Original freemac code.
"""
from . import sounds

SOUNDS = {"pressed": ("tick", 35), "accepted": ("pop", 40)}


def parse(line):
    """ "pressed", "accepted" or None."""
    words = line.split()
    if len(words) == 2 and words[0] == "slow" and words[1] in SOUNDS:
        return words[1]
    return None


class Clicks:
    def __init__(self):
        self.players = {}
        try:
            import gi
            gi.require_version("Gst", "1.0")
            from gi.repository import Gst
            Gst.init(None)
            self.Gst = Gst
        except (ImportError, ValueError):
            self.Gst = None

    def _player(self, what):
        player = self.players.get(what)
        if player is None and self.Gst is not None:
            name, volume = SOUNDS[what]
            player = self.Gst.ElementFactory.make("playbin", f"slow-keys-{what}")
            if player is None:
                return None
            player.set_property("uri", "file://" + sounds.path_of(name))
            player.set_property("volume", volume / 100)
            fake = self.Gst.ElementFactory.make("fakesink", None)
            if fake is not None:
                player.set_property("video-sink", fake)
            player.set_state(self.Gst.State.PAUSED)
            self.players[what] = player
        return player

    def handle(self, line):
        what = parse(line)
        if what is None:
            return
        name, volume = SOUNDS[what]
        player = self._player(what)
        if player is None:
            sounds.play(sounds.path_of(name), volume, gap=0.02)
            return
        Gst = self.Gst
        player.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, 0)
        player.set_state(Gst.State.PLAYING)
