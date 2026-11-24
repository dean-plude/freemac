# SPDX-License-Identifier: GPL-3.0-or-later
"""Screen savers: something calm on the screen while the computer waits.

    freemac-screensaver              start the chosen screen saver now
    freemac-screensaver NAME         start that one (drift, clock, album)
    freemac-screensaver --stop       end a running screen saver

freemac-lock --watch starts it after the idle time set in Dials > Screen
Saver (swayidle, which also ends it at the first touch), and a hot corner
can start it too. It covers every screen on the overlay layer and hides the
pointer; a key, a click or a real move of the pointer ends it.

If the time to lock the screen (Dials > Power) comes while it runs, the lock
waits: latch leaves a mark (LOCK_MARK) instead, and the touch that ends the
screen saver locks the screen first, so the desktop isn't shown in between.
That's how a Mac asks for the password when you wake it from a screen saver.

The savers are freemac's own:
  Drift   soft lights in freemac's colours drifting over a dark sky
  Clock   the time and date, large and quiet, slowly moving about
  Album   your photos (Pictures), one after another, slowly zooming;
          freemac's wallpapers when there are none
Settings live in ~/.config/freemac/shell.json as "saver" and "saver_after"
(minutes, 0 for never). Original freemac code.
"""
import math
import os
import random
import signal
import subprocess
import sys
import time

import cairo
import gi

try:
    gi.require_foreign("cairo")   # cairo contexts for PangoCairo
except ImportError:
    pass

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import style  # noqa: E402

SAVERS = (("drift", "Drift"), ("clock", "Clock"), ("album", "Album"))
DEFAULT_SAVER = "drift"
DEFAULT_AFTER = 3          # minutes; before the screen locks (5) and turns off (10)
FPS = 30
FADE_IN = 1.2              # seconds
SETTLE = 1.0               # seconds in which a pointer move doesn't count
MOVE_SLACK = 12            # pixels a pointer may wander before it counts
PHOTO_SECONDS = 9
CROSSFADE = 1.6
WALLPAPERS = "/usr/share/backgrounds/freemac"
PICTURE_TYPES = (".jpg", ".jpeg", ".png", ".webp")
MAX_PHOTOS = 400


def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or GLib.get_user_cache_dir()
    return base


PID_FILE = os.path.join(runtime_dir(), "freemac-saver.pid")
LOCK_MARK = os.path.join(runtime_dir(), "freemac-saver.lock-on-wake")


def settings():
    prefs = style.prefs()
    name = prefs.get("saver", DEFAULT_SAVER)
    if name not in dict(SAVERS):
        name = DEFAULT_SAVER
    try:
        after = max(0, int(prefs.get("saver_after", DEFAULT_AFTER)))
    except (TypeError, ValueError):
        after = DEFAULT_AFTER
    return name, after


def running_pid():
    """The pid of the screen saver that's showing, or None."""
    try:
        with open(PID_FILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
    except (OSError, ValueError):
        return None
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if b"saver" not in f.read():
                return None
    except OSError:
        return None
    return pid


def stop():
    pid = running_pid()
    if pid:
        os.kill(pid, signal.SIGTERM)
    return 0


# ---- the savers ---------------------------------------------------------------
# Each draws one frame for a time t (seconds since it started) at any size,
# so Dials can draw a still of it for its picker.

LIGHTS = (  # freemac's colours, softened
    (1.00, 0.45, 0.38), (0.55, 0.42, 0.98), (0.20, 0.78, 0.74),
    (1.00, 0.72, 0.30), (0.26, 0.55, 1.00), (0.95, 0.40, 0.72),
)


class Drift:
    def __init__(self, seed=None):
        rnd = random.Random(seed)
        self.lights = [(colour, rnd.uniform(0.04, 0.09), rnd.uniform(0.03, 0.08),
                        rnd.uniform(0, 2 * math.pi), rnd.uniform(0, 2 * math.pi),
                        rnd.uniform(0.28, 0.46)) for colour in LIGHTS]

    def draw(self, cr, w, h, t):
        bg = cairo.LinearGradient(0, 0, 0, h)
        bg.add_color_stop_rgb(0, 0.05, 0.06, 0.16)
        bg.add_color_stop_rgb(1, 0.02, 0.02, 0.07)
        cr.set_source(bg)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_ADD)
        size = max(w, h)
        for (r, g, b), fx, fy, px, py, radius in self.lights:
            x = w * (0.5 + 0.42 * math.sin(t * fx + px))
            y = h * (0.5 + 0.40 * math.sin(t * fy + py))
            rr = size * radius * (0.9 + 0.1 * math.sin(t * 0.2 + px))
            glow = cairo.RadialGradient(x, y, 0, x, y, rr)
            glow.add_color_stop_rgba(0, r, g, b, 0.42)
            glow.add_color_stop_rgba(0.5, r, g, b, 0.14)
            glow.add_color_stop_rgba(1, r, g, b, 0)
            cr.set_source(glow)
            cr.arc(x, y, rr, 0, 2 * math.pi)
            cr.fill()
        cr.set_operator(cairo.OPERATOR_OVER)


def font(size, weight=Pango.Weight.NORMAL):
    settings = Gtk.Settings.get_default()
    name = settings.get_property("gtk-font-name") if settings else "Sans 11"
    desc = Pango.FontDescription.from_string(name or "Sans 11")
    desc.set_absolute_size(size * Pango.SCALE)
    desc.set_weight(weight)
    return desc


class Clock:
    def __init__(self, seed=None):
        rnd = random.Random(seed)
        self.start = (rnd.uniform(0.2, 0.8), rnd.uniform(0.25, 0.75))
        self.velocity = (rnd.choice((-1, 1)) * 14.0, rnd.choice((-1, 1)) * 9.0)

    @staticmethod
    def bounce(start, speed, t, room):
        """Where a point moving at speed (px/s) is after t seconds, bouncing
        between 0 and room."""
        if room <= 0:
            return 0
        span = 2 * room
        p = (start * room + speed * t) % span
        return p if p <= room else span - p

    def draw(self, cr, w, h, t, now=None):
        cr.set_source_rgb(0.01, 0.01, 0.03)
        cr.paint()
        now = now or time.localtime()
        clock24 = style.h24()
        text = time.strftime("%H:%M" if clock24 else "%-I:%M", now)
        date = time.strftime("%A, %-d %B", now)
        scale = h / 800
        big = PangoCairo.create_layout(cr)
        big.set_font_description(font(150 * scale, Pango.Weight.LIGHT))
        big.set_text(text, -1)
        small = PangoCairo.create_layout(cr)
        small.set_font_description(font(26 * scale, Pango.Weight.MEDIUM))
        small.set_text(date, -1)
        bw, bh = big.get_pixel_size()
        sw, sh = small.get_pixel_size()
        box_w, box_h = max(bw, sw), bh + sh
        x = self.bounce(self.start[0], self.velocity[0] * scale, t, w - box_w)
        y = self.bounce(self.start[1], self.velocity[1] * scale, t, h - box_h)
        cr.set_source_rgba(1, 1, 1, 0.86)
        cr.move_to(x + (box_w - bw) / 2, y)
        PangoCairo.show_layout(cr, big)
        cr.set_source_rgba(1, 1, 1, 0.62)
        cr.move_to(x + (box_w - sw) / 2, y + bh)
        PangoCairo.show_layout(cr, small)


def photos():
    """Pictures to show: the person's own, else freemac's wallpapers."""
    found = []
    pictures = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) or os.path.expanduser("~/Pictures")
    for root, dirs, files in os.walk(pictures):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            if name.lower().endswith(PICTURE_TYPES) and not name.startswith("."):
                found.append(os.path.join(root, name))
                if len(found) >= MAX_PHOTOS:
                    break
        if len(found) >= MAX_PHOTOS:
            break
    if not found:
        try:
            found = [os.path.join(WALLPAPERS, n) for n in sorted(os.listdir(WALLPAPERS))
                     if n.lower().endswith(PICTURE_TYPES)]
        except OSError:
            found = []
    random.shuffle(found)
    return found


class Album:
    def __init__(self, seed=None, pictures=None):
        self.pictures = pictures if pictures is not None else photos()
        self.cache = {}
        self.size = None

    def picture(self, index, w, h):
        if not self.pictures:
            return None
        path = self.pictures[index % len(self.pictures)]
        key = (path, w, h)
        if key not in self.cache:
            if len(self.cache) > 3:
                self.cache.pop(next(iter(self.cache)))
            try:
                pix = GdkPixbuf.Pixbuf.new_from_file(path)
                pix = pix.apply_embedded_orientation() or pix
                # Big enough to cover the screen while it zooms in 10%.
                k = max(w / pix.get_width(), h / pix.get_height()) * 1.1
                pix = pix.scale_simple(max(1, int(pix.get_width() * k)), max(1, int(pix.get_height() * k)),
                                       GdkPixbuf.InterpType.BILINEAR)
            except GLib.Error:
                pix = None
            self.cache[key] = pix
        return self.cache[key]

    def show(self, cr, pix, w, h, age, index, alpha):
        if pix is None:
            return
        zoom = 1 / 1.1 + (1 - 1 / 1.1) * min(1, age / (PHOTO_SECONDS + CROSSFADE))
        pw, ph = pix.get_width() * zoom, pix.get_height() * zoom
        # Each picture drifts a little toward one corner.
        dx, dy = ((-1, -1), (1, -1), (-1, 1), (1, 1))[index % 4]
        x = (w - pw) / 2 + dx * (pw - w) / 2 * (age / (PHOTO_SECONDS + CROSSFADE) - 0.5)
        y = (h - ph) / 2 + dy * (ph - h) / 2 * (age / (PHOTO_SECONDS + CROSSFADE) - 0.5)
        cr.save()
        cr.translate(x, y)
        cr.scale(zoom, zoom)
        Gdk.cairo_set_source_pixbuf(cr, pix, 0, 0)
        cr.paint_with_alpha(alpha)
        cr.restore()

    def draw(self, cr, w, h, t):
        cr.set_source_rgb(0, 0, 0)
        cr.paint()
        if not self.pictures:
            return
        index = int(t // PHOTO_SECONDS)
        age = t - index * PHOTO_SECONDS
        if index > 0 and age < CROSSFADE:
            self.show(cr, self.picture(index - 1, w, h), w, h, age + PHOTO_SECONDS, index - 1, 1)
            self.show(cr, self.picture(index, w, h), w, h, age, index, age / CROSSFADE)
        else:
            self.show(cr, self.picture(index, w, h), w, h, age, index, 1)


def make(name, seed=None):
    return {"drift": Drift, "clock": Clock, "album": Album}.get(name, Drift)(seed)


def still(name, width, height, t=40.0):
    """A picture of a screen saver, for Dials."""
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    cr = cairo.Context(surface)
    saver = make(name, seed=7)
    if isinstance(saver, Album):
        saver.pictures = saver.pictures[:1]
        t = PHOTO_SECONDS / 2
    saver.draw(cr, width, height, t)
    return surface


# ---- the windows ----------------------------------------------------------------

class SaverWindow(Gtk.Window):
    def __init__(self, app, monitor, first):
        super().__init__(title="Screen Saver")
        self.app = app
        self.set_app_paintable(True)
        visual = self.get_screen().get_rgba_visual()
        if visual:
            self.set_visual(visual)
        try:
            gi.require_version("GtkLayerShell", "0.1")
            from gi.repository import GtkLayerShell
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_namespace(self, "freemac-saver")
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_monitor(self, monitor)
            for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                         GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
                GtkLayerShell.set_anchor(self, edge, True)
            GtkLayerShell.set_exclusive_zone(self, -1)
            if first:
                GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        except (ValueError, ImportError):
            self.fullscreen()
        self.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.ENTER_NOTIFY_MASK
                        | Gdk.EventMask.BUTTON_PRESS_MASK
                        | Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.SCROLL_MASK
                        | Gdk.EventMask.TOUCH_MASK)
        self.connect("draw", self._draw)
        self.connect("realize", self._hide_pointer)
        for signal_name in ("key-press-event", "button-press-event", "scroll-event", "touch-event"):
            self.connect(signal_name, lambda *_: app.wake())
        self.connect("motion-notify-event", self._moved)
        # The pointer arriving counts as where it rests, not as a move.
        self.connect("enter-notify-event", lambda _w, e: app.rested(e.x_root, e.y_root))
        self.saver = make(app.name)

    def _hide_pointer(self, _widget):
        window = self.get_window()
        window.set_cursor(Gdk.Cursor.new_from_name(window.get_display(), "none"))

    def _moved(self, _widget, event):
        self.app.moved(event.x_root, event.y_root)
        return False

    def _draw(self, _widget, cr):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        t = time.monotonic() - self.app.started
        fade = min(1.0, t / FADE_IN)
        if fade < 1:
            cr.push_group()
        self.saver.draw(cr, w, h, t)
        if fade < 1:
            frame = cr.pop_group()
            cr.set_operator(cairo.OPERATOR_SOURCE)
            cr.set_source_rgba(0, 0, 0, 0)
            cr.paint()
            cr.set_operator(cairo.OPERATOR_OVER)
            cr.set_source(frame)
            cr.paint_with_alpha(fade)
        return True


class Saver:
    def __init__(self, name):
        self.name = name
        self.started = time.monotonic()
        self.first_point = None
        self.ending = False
        self.windows = []
        self.loop = GLib.MainLoop()

    def run(self):
        display = Gdk.Display.get_default()
        if display is None:
            print("freemac-screensaver: no display", file=sys.stderr)
            return 1
        for i in range(display.get_n_monitors()):
            window = SaverWindow(self, display.get_monitor(i), i == 0)
            window.show_all()
            self.windows.append(window)
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
        GLib.timeout_add(1000 // FPS, self._tick)
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, self._signalled)
        self.loop.run()
        try:
            if running_pid() == os.getpid():
                os.remove(PID_FILE)
        except OSError:
            pass
        return 0

    def _tick(self):
        for window in self.windows:
            window.queue_draw()
        return not self.ending

    def _signalled(self):
        self.wake()
        return False

    def moved(self, x, y):
        if time.monotonic() - self.started < SETTLE:
            self.first_point = (x, y)
            return
        if self.first_point is None:
            self.first_point = (x, y)
            return
        if abs(x - self.first_point[0]) + abs(y - self.first_point[1]) > MOVE_SLACK:
            self.wake()

    def rested(self, x, y):
        if self.first_point is None:
            self.first_point = (x, y)
        return False

    def wake(self):
        """End the screen saver, locking the screen first if its time came."""
        if self.ending:
            return
        self.ending = True
        if os.path.exists(LOCK_MARK):
            try:
                os.remove(LOCK_MARK)
            except OSError:
                pass
            lock = GLib.find_program_in_path("freemac-lock")
            command = [lock] if lock else [sys.executable, "-m", "freemac_shell.latch"]
            try:
                # Returns once the lock is up, so the desktop never shows.
                subprocess.run(command, timeout=20)
            except (OSError, subprocess.TimeoutExpired):
                pass
        for window in self.windows:
            window.destroy()
        self.loop.quit()


def locked():
    return subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "gtklock"],
                          stdout=subprocess.DEVNULL).returncode == 0


def main():
    args = sys.argv[1:]
    if args in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    if "--stop" in args:
        return stop()
    if running_pid():
        return 0
    if locked():
        return 0   # the lock screen is up; it shows its own clock
    try:
        os.remove(LOCK_MARK)
    except OSError:
        pass
    name = args[0] if args and args[0] in dict(SAVERS) else settings()[0]
    Gtk.init([])
    return Saver(name).run()


if __name__ == "__main__":
    sys.exit(main())
