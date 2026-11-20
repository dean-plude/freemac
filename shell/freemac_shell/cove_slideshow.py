# SPDX-License-Identifier: GPL-3.0-or-later
"""Cove's slideshow: photos one after another on the whole screen, each
fading into the next and drifting slowly closer while it shows.

Space pauses and plays, the arrow keys go to the next or previous photo,
and Escape (or a click) ends it. The pointer hides when it stops moving.
Original freemac code.
"""
import math
import threading
import time

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, PangoCairo  # noqa: E402

from . import photos_store as store  # noqa: E402

SECONDS = 4.5     # how long each photo shows
FADE = 1.0        # the cross-fade into it
DRIFT = 0.06      # how much closer it comes while it shows


class Slideshow(Gtk.Window):
    def __init__(self, parent, photos, start=0):
        super().__init__(title="Slideshow")
        # Not transient for Cove's window: Wayfire lifts a full-screen window
        # above the menu bar and Pier only when it is a window of its own.
        self.photos = list(photos)
        self.at = max(0, min(start, len(self.photos) - 1))
        self.pictures = {}          # index -> pixbuf, the shown one and its neighbours
        self.loading = set()
        self.previous = None        # the picture fading out
        self.began = time.monotonic()
        self.paused_at = None
        self.note, self.note_until = "", 0
        self.cursor_moved = time.monotonic()
        display = Gdk.Display.get_default()
        monitor = display.get_monitor_at_window(parent.get_window()) if parent.get_window() else \
            display.get_primary_monitor() or display.get_monitor(0)
        area = monitor.get_geometry()
        scale = monitor.get_scale_factor()
        self.room = (area.width * scale, area.height * scale)

        self.area = Gtk.DrawingArea()
        self.area.connect("draw", self._draw)
        self.add(self.area)
        self.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("key-press-event", self._key)
        self.connect("button-press-event", lambda *_: self.close())
        self.connect("motion-notify-event", self._moved)
        self.connect("destroy", lambda *_: (self._stop(), parent.present()))
        self.set_icon_name("freemac-cove")
        if parent.get_application() is not None:
            self.set_application(parent.get_application())
        self._load(self.at, wait=True)
        self._load(self.at + 1)
        self.timer = GLib.timeout_add(33, self._tick)
        self.fullscreen()
        self.show_all()
        self.present()

    # -- pictures ----------------------------------------------------------------
    def _index(self, n):
        return n % len(self.photos)

    def _load(self, n, wait=False):
        n = self._index(n)
        if n in self.pictures or n in self.loading:
            return
        photo = self.photos[n]
        width, height = self.room

        def read():
            try:
                return store.full_picture(photo.path, width, height)
            except GLib.Error:
                return None

        if wait:
            self.pictures[n] = read()
            return
        self.loading.add(n)

        def work():
            found = read()
            GLib.idle_add(self._loaded, n, found)
        threading.Thread(target=work, daemon=True).start()

    def _loaded(self, n, picture):
        self.loading.discard(n)
        self.pictures[n] = picture
        return False

    def _forget_far(self):
        keep = {self._index(self.at + d) for d in (-1, 0, 1)}
        for n in list(self.pictures):
            if n not in keep:
                del self.pictures[n]

    def go(self, step):
        target = self._index(self.at + step)
        if target not in self.pictures:
            self._load(target, wait=True)
        self.previous = self.pictures.get(self.at)
        self.at = target
        self.began = time.monotonic()
        if self.paused_at is not None:
            self.paused_at = self.began
        self._forget_far()
        self._load(self.at + 1)
        self._load(self.at - 1)
        self.area.queue_draw()

    # -- time --------------------------------------------------------------------
    def _elapsed(self):
        now = self.paused_at if self.paused_at is not None else time.monotonic()
        return now - self.began

    def _tick(self):
        if len(self.photos) > 1 and self.paused_at is None and self._elapsed() >= SECONDS:
            if self._index(self.at + 1) in self.pictures:
                self.go(1)
        window = self.get_window()
        if window is not None and time.monotonic() - self.cursor_moved > 2:
            window.set_cursor(Gdk.Cursor.new_for_display(window.get_display(), Gdk.CursorType.BLANK_CURSOR))
        self.area.queue_draw()
        return True

    def _stop(self):
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = 0

    def pause(self):
        if self.paused_at is None:
            self.paused_at = time.monotonic()
            self._say("Paused")
        else:
            self.began += time.monotonic() - self.paused_at
            self.paused_at = None
            self._say("Playing")

    def _say(self, words):
        self.note, self.note_until = words, time.monotonic() + 1.5

    # -- input -------------------------------------------------------------------
    def _key(self, _w, event):
        key = event.keyval
        if key in (Gdk.KEY_Escape, Gdk.KEY_q, Gdk.KEY_w) or (
                key == Gdk.KEY_period and event.state & Gdk.ModifierType.CONTROL_MASK):
            self.close()
        elif key == Gdk.KEY_space:
            self.pause()
        elif key in (Gdk.KEY_Right, Gdk.KEY_Down):
            self.go(1)
        elif key in (Gdk.KEY_Left, Gdk.KEY_Up):
            self.go(-1)
        else:
            return False
        return True

    def _moved(self, _w, _event):
        self.cursor_moved = time.monotonic()
        window = self.get_window()
        if window is not None:
            window.set_cursor(None)

    # -- drawing -----------------------------------------------------------------
    def _paint(self, cr, picture, width, height, progress, alpha):
        if picture is None or alpha <= 0:
            return
        pw, ph = picture.get_width(), picture.get_height()
        fit = min(width / pw, height / ph)
        ease = 0.5 - math.cos(math.pi * min(1, max(0, progress))) / 2
        scale = fit * (1 + DRIFT * ease)
        cr.save()
        cr.translate(width / 2, height / 2)
        cr.scale(scale, scale)
        cr.translate(-pw / 2, -ph / 2)
        Gdk.cairo_set_source_pixbuf(cr, picture, 0, 0)
        cr.get_source().set_filter(cairo.FILTER_GOOD)
        cr.paint_with_alpha(alpha)
        cr.restore()

    def _draw(self, area, cr):
        width, height = area.get_allocated_width(), area.get_allocated_height()
        cr.set_source_rgb(0, 0, 0)
        cr.paint()
        elapsed = self._elapsed()
        span = SECONDS + FADE
        current = self.pictures.get(self.at)
        if self.previous is not None and elapsed < FADE:
            self._paint(cr, self.previous, width, height, (SECONDS + FADE + elapsed) / span, 1)
            self._paint(cr, current, width, height, elapsed / span, elapsed / FADE)
        else:
            self.previous = None
            self._paint(cr, current, width, height, elapsed / span, 1)
        if current is None:
            self._label(cr, width, height, "This photo can’t be shown.")
        if self.paused_at is not None:
            self._label(cr, width, height, "Paused")
        elif time.monotonic() < self.note_until:
            self._label(cr, width, height, self.note)
        return False

    def _label(self, cr, width, height, words):
        layout = self.area.create_pango_layout(words)
        tw, th = layout.get_pixel_size()
        x, y = (width - tw) / 2, height - th - 60
        cr.set_source_rgba(0, 0, 0, 0.55)
        r = (th + 16) / 2
        cr.new_sub_path()
        cr.arc(x - 10 + r, y - 8 + r, r, math.pi / 2, 3 * math.pi / 2)
        cr.arc(x + tw + 10 - r, y - 8 + r, r, -math.pi / 2, math.pi / 2)
        cr.close_path()
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.move_to(x, y)
        PangoCairo.show_layout(cr, layout)
