# SPDX-License-Identifier: GPL-3.0-or-later
"""Hover Text, as on a Mac: hold Command (or the key chosen in Dials >
Accessibility) and point at some words, and they show large in a panel just
above the pointer, for anyone who finds small text hard to read.

Strata watches the key and the pointer (strata/shell/hover-text.hpp) and
tells Topline over its socket: "hover at X Y" once the pointer rests while
the key is held, and "hover stop" when it's let go. Topline then takes a
picture of a strip of the screen around the pointer (grim), finds the words
in it with Tesseract (livetext.py, the reader behind Live Text in Frame) and
shows the line the pointer is on (Strata hides the pointer for that moment,
so the arrow doesn't cover the word). It works the same in every app, because it
reads the screen, not the app. Nothing is saved: the picture stays in memory
and is gone once read.

The text size is shell.json "hover_text_size" (Dials > Accessibility).

Speak items under the pointer (Dials > Accessibility > Spoken Content,
wayfire.ini strata-shell/hover_speak) uses the same key and the same read:
the line is read out loud in the Spoken Content voice (speak.py), with or
without the panel. Each line is read once, until the pointer moves to
another one or the key is let go.
Original freemac code.
"""
import os
import subprocess
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GdkPixbuf, GLib, Gdk, Gtk, GtkLayerShell  # noqa: E402

from . import livetext, speak, style  # noqa: E402
from .ini import ini_get  # noqa: E402
from .wfipc import Connection  # noqa: E402

# The strip of screen read around the pointer, in layout pixels.
STRIP_W, STRIP_H = 760, 64
# How far from the pointer a word may be and still count as pointed at.
NEAR = 28
GAP = 14
SIZES = (("24", "Small"), ("36", "Medium"), ("48", "Large"), ("64", "Huge"))
DEFAULT_SIZE = 36
SCALE = 3.0   # screen text is small: enlarge it for Tesseract
HIDE_SETTLE = 0.12        # without Strata's answer, a frame or two
HIDE_WAIT = 0.4          # at most this long for a frame without the pointer
FRAME = 0.016
GRAB_LOCK = threading.Lock()
PANEL_EXTRA = 50   # the panel's padding, border and margin, each side
WAYFIRE_INI = os.path.expanduser("~/.config/wayfire.ini")

CSS = b"""
window.hover-window, window.hover-window > * { background: transparent; }
window.hover-window .hover-panel {
    margin: 16px;
    padding: 6px 16px 8px 16px;
    border-radius: 12px;
    background-color: rgba(250, 250, 248, 0.97);
    border: 1px solid rgba(0, 0, 0, 0.18);
    box-shadow: 0 3px 10px rgba(0, 0, 0, 0.28);
}
window.hover-window .hover-text { color: #1d1d1f; }
"""


def parse(line):
    """("at", x, y), ("stop",) or None."""
    words = line.split()
    if words == ["hover", "stop"]:
        return ("stop",)
    if len(words) == 4 and words[:2] == ["hover", "at"]:
        try:
            return ("at", int(words[2]), int(words[3]))
        except ValueError:
            return None
    return None


def strip_around(x, y, area):
    """The strip of screen to read for a pointer at x, y, kept inside area
    (the display's x, y, width, height): (left, top, width, height)."""
    ax, ay, aw, ah = area
    w, h = min(STRIP_W, aw), min(STRIP_H, ah)
    left = min(max(x - w // 2, ax), ax + aw - w)
    top = min(max(y - h // 2, ay), ay + ah - h)
    return left, top, w, h


def line_at(words, px, py):
    """The text of the line the point px, py (in the strip) is on, or ""."""
    # The arrow itself, if it got into the picture, reads as a stray letter
    # or mark right at the pointer: never take that for the word.
    words = [word for word in words if not _stray(word)]
    if not words:
        return ""
    hit = next((word for word in words if word.contains(px, py, 3)), None)
    if hit is None:
        hit = min(words, key=lambda word: word.distance(px, py))
        if hit.distance(px, py) > NEAR:
            return ""
    key = hit.line_key()
    line = near_words([word for word in words if word.line_key() == key], hit)
    # An icon beside the words (an app's logo in the menu bar) reads as a
    # stray mark: leave those off the ends.
    while line and not any(ch.isalnum() for ch in line[0].text) and line[0] is not hit:
        line.pop(0)
    while line and not any(ch.isalnum() for ch in line[-1].text) and line[-1] is not hit:
        line.pop()
    return livetext.text_of(line)


def _stray(word):
    return word.conf < 70 and len(word.text) <= 2 and not word.text.isdigit()


def near_words(line, hit):
    """The run of words in a line around hit: a wide gap (a label and a
    button beside it, two columns) ends the run."""
    line = sorted(line, key=lambda word: word.x)
    gap = max(2.5 * max((word.h for word in line), default=10), 18)
    start = end = line.index(hit)
    while start > 0 and line[start].x - (line[start - 1].x + line[start - 1].w) <= gap:
        start -= 1
    while end < len(line) - 1 and line[end + 1].x - (line[end].x + line[end].w) <= gap:
        end += 1
    return line[start:end + 1]


def text_size():
    try:
        size = int(style.prefs().get("hover_text_size", DEFAULT_SIZE))
    except (TypeError, ValueError):
        size = DEFAULT_SIZE
    return min(max(size, 14), 120)


def modes():
    """(show, say): whether the line is shown large, read out loud, or both."""
    def on(key):
        return ini_get(WAYFIRE_INI, "strata-shell", key, "false").lower() == "true"
    return on("hover_text"), on("hover_speak")


def _pointer(hide):
    """Hide or show the pointer (Strata). After hiding, wait until every
    display has been drawn without it, up to HIDE_WAIT; a Strata too old to
    say gets the fixed HIDE_SETTLE."""
    try:
        connection = Connection()
    except OSError:
        return
    try:
        connection.call("strata/hover-cursor", hide=hide)
        if not hide:
            return
        waited = 0.0
        while waited < HIDE_WAIT:
            answer = connection.call("strata/hover-cursor", query=True)
            if "drawn" not in answer:
                time.sleep(HIDE_SETTLE)
                return
            if answer["drawn"]:
                time.sleep(FRAME)   # that frame on its way to the screen
                return
            time.sleep(FRAME)
            waited += FRAME
    except (OSError, ValueError, ConnectionError):
        pass
    finally:
        connection.sock.close()


def grab(left, top, width, height):
    """A PNG of that part of the screen, enlarged for reading, or None. The
    pointer is hidden for the moment (Strata), so it doesn't cover a word."""
    _pointer(hide=True)
    try:
        done = subprocess.run(["grim", "-g", f"{left},{top} {width}x{height}", "-t", "png", "-"],
                              capture_output=True, timeout=10, check=True)
    except (OSError, subprocess.SubprocessError):
        return None
    finally:
        _pointer(hide=False)
    try:
        loader = GdkPixbuf.PixbufLoader.new_with_type("png")
        loader.write(done.stdout)
        loader.close()
        picture = loader.get_pixbuf()
        # The picture holds whole screen pixels; on a HiDPI display it's
        # bigger than the strip asked for.
        scale = SCALE * width / max(picture.get_width(), 1)
        big = picture.scale_simple(int(picture.get_width() * scale), int(picture.get_height() * scale),
                                   GdkPixbuf.InterpType.BILINEAR)
        ok, data = big.save_to_bufferv("png", [], [])
    except GLib.Error:
        return None
    return bytes(data) if ok else None


class HoverPanel(Gtk.Window):
    def __init__(self):
        super().__init__(title="Hover Text")
        style.make_transparent(self)
        self.get_style_context().add_class("hover-window")
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-hover-text")
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.set_exclusive_zone(self, -1)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.LEFT):
            GtkLayerShell.set_anchor(self, edge, True)
        self.connect("realize", self._pass_clicks)
        box = Gtk.Box()
        box.get_style_context().add_class("hover-panel")
        self.label = Gtk.Label(xalign=0)
        self.label.get_style_context().add_class("hover-text")
        self.label.set_line_wrap(True)
        self.label.set_max_width_chars(40)
        box.pack_start(self.label, False, False, 0)
        box.show_all()
        self.add(box)
        self.reader = livetext.Reader()
        self.wanted = 0          # bumped by every request and stop
        self.shown_rect = None   # where the panel is, in layout pixels
        self.pending = 0
        self.spoken = None       # the line last read out loud, until the key is let go

    def _pass_clicks(self, _widget):
        import cairo
        self.get_window().input_shape_combine_region(cairo.Region(), 0, 0)

    def handle(self, line):
        message = parse(line)
        if message is None:
            return
        if message[0] == "stop":
            self.wanted += 1
            self.reader.stop()
            self.spoken = None
            self._hide()
            return
        self.request(message[1], message[2])

    def _hide(self):
        if self.pending:
            GLib.source_remove(self.pending)
            self.pending = 0
        self.shown_rect = None
        self.hide()

    @staticmethod
    def _display_at(x, y):
        display = Gdk.Display.get_default()
        monitor = display.get_monitor_at_point(x, y) if display else None
        if monitor is None:
            return None, (0, 0, 1280, 800)
        g = monitor.get_geometry()
        return monitor, (g.x, g.y, g.width, g.height)

    def request(self, x, y):
        self.wanted += 1
        ticket = self.wanted
        if not livetext.available():
            return
        monitor, area = self._display_at(x, y)
        strip = strip_around(x, y, area)
        if self.pending:
            GLib.source_remove(self.pending)
            self.pending = 0
        # The panel mustn't be in the picture: out of the way first.
        if self.shown_rect and _overlap(self.shown_rect, strip):
            self._hide()
            self.pending = GLib.timeout_add(60, self._start, ticket, x, y, monitor, area, strip)
        else:
            self._start(ticket, x, y, monitor, area, strip)

    def _start(self, ticket, x, y, monitor, area, strip):
        self.pending = 0
        if ticket != self.wanted:
            return False

        def work():
            # One picture at a time: a read still finishing would show the
            # pointer again in the middle of this one's picture.
            with GRAB_LOCK:
                if ticket != self.wanted:
                    return
                png = grab(*strip)
            words = self.reader.read(png, SCALE) if png else []
            text = line_at(words, x - strip[0], y - strip[1])
            GLib.idle_add(self._found, ticket, text, x, monitor, area, strip)

        threading.Thread(target=work, daemon=True).start()
        return False

    def _found(self, ticket, text, x, monitor, area, strip):
        if ticket != self.wanted:
            return False
        if not text:
            self._hide()
            return False
        show, say = modes()
        if say and text != self.spoken:
            self.spoken = text
            speak.say(text)
        if not show:
            self._hide()
            return False
        ax, ay, aw, ah = area
        markup = '<span size="{}">{}</span>'.format(text_size() * 1024 * 3 // 4, GLib.markup_escape_text(text))
        self.label.set_markup(markup)
        # A wrapping label asks for little width: give it the text's own
        # width, up to most of the display, so it wraps only when it must.
        layout = self.label.create_pango_layout(None)
        layout.set_markup(markup, -1)
        self.label.set_size_request(min(layout.get_pixel_size()[0] + 2, int(aw * 0.8) - 2 * PANEL_EXTRA), -1)
        if monitor is not None:
            GtkLayerShell.set_monitor(self, monitor)
        self.resize(1, 1)
        _min, natural = self.get_preferred_size()
        width, height = natural.width, natural.height
        left = min(max(x - width // 2, ax), ax + aw - width)
        top = strip[1] - height - GAP
        if top < ay + 28:   # no room above, under the menu bar: below instead
            top = strip[1] + strip[3] + GAP
        top = min(max(top, ay), ay + ah - height)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, left - ax)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, top - ay)
        self.shown_rect = (left, top, width, height)
        self.show()
        return False


def _overlap(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
