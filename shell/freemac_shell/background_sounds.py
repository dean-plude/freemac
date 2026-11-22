# SPDX-License-Identifier: GPL-3.0-or-later
"""Background sounds, as on a Mac (Dials > Accessibility > Background
sounds): a steady sound, such as rain or the ocean, that plays quietly
behind everything else to mask other noise and help you focus or rest.

The sounds are freemac's own, made by art/sounds/make-background-sounds.py
into /usr/share/sounds/freemac/background, each a loop that repeats with no
seam. Topline plays the chosen one with GStreamer for as long as it's on,
starting it again from the top just as it ends, and follows the choices in
~/.config/freemac/shell.json as Dials changes them:
    "background_sounds": true, "background_sound": "rain", "background_volume": 40

It can be turned on and off from the menu bar too (Topline's quick settings).
Original freemac code.
"""
import os

from . import style

DIR = "/usr/share/sounds/freemac/background"
# In the order Dials lists them.
SOUNDS = (("balanced", "Balanced noise"), ("bright", "Bright noise"), ("dark", "Dark noise"),
          ("ocean", "Ocean"), ("rain", "Rain"), ("stream", "Stream"))
DEFAULT_SOUND = "rain"
DEFAULT_VOLUME = 40


def wanted(prefs=None):
    """(on, sound, volume 0–100) from shell.json."""
    prefs = style.prefs() if prefs is None else prefs
    sound = prefs.get("background_sound", DEFAULT_SOUND)
    if sound not in dict(SOUNDS):
        sound = DEFAULT_SOUND
    try:
        volume = max(0, min(100, int(prefs.get("background_volume", DEFAULT_VOLUME))))
    except (TypeError, ValueError):
        volume = DEFAULT_VOLUME
    return bool(prefs.get("background_sounds", False)), sound, volume


def path_of(sound):
    return os.path.join(DIR, f"{sound}.wav")


def gain(volume):
    """GStreamer's linear volume for a 0–100 slider that sounds even."""
    return (volume / 100) ** 2


class Player:
    """Plays the chosen background sound while it's on."""

    def __init__(self):
        self.bin = None
        self.playing = None      # the sound now playing, or None
        self._monitor = None
        try:
            import gi
            gi.require_version("Gst", "1.0")
            from gi.repository import Gst
            Gst.init(None)
            self.Gst = Gst
        except (ImportError, ValueError):
            self.Gst = None

    def start(self):
        """Follow shell.json from now on."""
        self._monitor = style.watch_prefs(self.apply)
        self.apply()

    def apply(self):
        on, sound, volume = wanted()
        if not on or not os.path.exists(path_of(sound)) or not self.Gst:
            self.stop()
            return
        if self.bin is None:
            self.bin = self.Gst.ElementFactory.make("playbin", "background-sounds")
            if self.bin is None:
                return
            fake = self.Gst.ElementFactory.make("fakesink", None)
            if fake:
                self.bin.set_property("video-sink", fake)
            # Queue the same file again just before it ends, so it loops
            # with no gap.
            self.bin.connect("about-to-finish", self._again)
            bus = self.bin.get_bus()
            bus.add_signal_watch()
            bus.connect("message::error", self._error)
        self.bin.set_property("volume", gain(volume))
        if sound != self.playing:
            self.bin.set_state(self.Gst.State.NULL)
            self.bin.set_property("uri", "file://" + path_of(sound))
            self.playing = sound
            self.bin.set_state(self.Gst.State.PLAYING)

    def stop(self):
        if self.bin is not None:
            self.bin.set_state(self.Gst.State.NULL)
        self.playing = None

    def _again(self, playbin):
        if self.playing:
            playbin.set_property("uri", "file://" + path_of(self.playing))

    def _error(self, _bus, _message):
        # The sound couldn't play (no audio device, say): try again from the
        # top the next time the choices change.
        self.stop()
