# SPDX-License-Identifier: GPL-3.0-or-later
"""The countdown before a scheduled sleep, restart or shut down.

/usr/libexec/freemac-power-schedule, run by its timer as root, writes
/run/freemac-power-schedule/pending with what it will do and when. Topline
looks for that file and shows this window, as a Mac does: "Your computer
will shut down in 9:42", with Cancel and Shut Down. Cancel, or Shut Down to
do it now, leaves a file in the answers folder, which the helper reads.

Original freemac code.
"""
import json
import os
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

from . import battery, power_schedule as ps  # noqa: E402

NOW_LABEL = {"sleep": "Sleep", "restart": "Restart", "shutdown": "Shut Down"}
ICON = {"sleep": "weather-clear-night", "restart": "system-reboot", "shutdown": "system-shutdown"}


def pending():
    try:
        with open(ps.PENDING) as f:
            data = json.load(f)
        return data if data.get("what") in NOW_LABEL else None
    except (OSError, ValueError, AttributeError):
        return None


def say(word):
    """Leave an answer for the helper: 'cancel' or 'now'."""
    path = os.path.join(ps.ANSWERS, f"{word}-{os.getuid()}")
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o644)
        os.close(fd)
        return True
    except OSError:
        return False


def left_words(seconds):
    seconds = max(0, int(seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


class Countdown(Gtk.Window):
    def __init__(self, info, on_close):
        super().__init__(title="Scheduled " + NOW_LABEL[info["what"]], resizable=False)
        self.info = info
        self.on_close = on_close
        self.set_keep_above(True)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_default_size(420, -1)
        # Drawn as freemac's alerts are: an empty title bar of its own, so
        # Strata adds no window buttons, and a rounded panel with a shadow.
        empty = Gtk.Box()
        empty.set_size_request(-1, 0)
        self.set_titlebar(empty)
        visual = self.get_screen().get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)
        self.get_style_context().add_class("freemac-alert")
        box = Gtk.Box(spacing=16, margin=20)
        self.add(box)
        icon = Gtk.Image.new_from_icon_name(ICON[info["what"]], Gtk.IconSize.DIALOG)
        icon.set_valign(Gtk.Align.START)
        box.pack_start(icon, False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.pack_start(words, True, True, 0)
        self.title = Gtk.Label(xalign=0, wrap=True, max_width_chars=40)
        self.title.get_style_context().add_class("alert-title")
        words.pack_start(self.title, False, False, 0)
        where = "Battery" if battery.find() else "Power"
        note = Gtk.Label(label=f"It's set in Dials > {where} > Schedule. Save your work, or click Cancel to "
                               "stop it this time.", xalign=0, wrap=True, max_width_chars=40)
        words.pack_start(note, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin_top=8)
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_: self.answer("cancel"))
        buttons.pack_start(cancel, False, False, 0)
        now = Gtk.Button(label=NOW_LABEL[info["what"]])
        now.get_style_context().add_class("suggested-action")
        now.connect("clicked", lambda *_: self.answer("now"))
        buttons.pack_start(now, False, False, 0)
        words.pack_start(buttons, False, False, 0)
        self.connect("delete-event", lambda *_: self.answer("cancel") or True)
        self.timer = None
        self.tick()
        self.timer = GLib.timeout_add(500, self.tick)
        self.show_all()
        cancel.grab_focus()

    def tick(self):
        left = self.info["deadline"] - time.time()
        self.title.set_markup("<b>" + GLib.markup_escape_text(
            f"Your computer will {ps.ACTION_WORDS[self.info['what']]} in {left_words(left)}.") + "</b>")
        if pending() is None:
            self.finish()
            return False
        return True

    def answer(self, word):
        say(word)
        self.finish()

    def finish(self):
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = None
        self.destroy()
        self.on_close()


class Watcher:
    """Looks for a pending scheduled action every few seconds."""

    def __init__(self):
        self.window = None
        self.shown_for = None
        GLib.timeout_add_seconds(3, self.look)

    def look(self):
        info = pending()
        if info and self.window is None and info.get("deadline") != self.shown_for \
                and info["deadline"] - time.time() > 1:
            self.shown_for = info.get("deadline")
            self.window = Countdown(info, self._closed)
        return True

    def _closed(self):
        self.window = None
