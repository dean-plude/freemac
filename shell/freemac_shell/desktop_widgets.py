# SPDX-License-Identifier: GPL-3.0-or-later
"""Widgets, as on a Mac: small cards that show something at a glance, on the
desktop over the wallpaper and in the Notification Centre.

There are nine: a clock, today's calendar, the weather (from Sky), your
reminders (Nudge), the battery, Screen Time today (Logbook), clocks in other
cities (Chime), your newest sticky note (Stickies) and a photo from your
Pictures folder, a different one each day.

Edit Widgets… (right-click the desktop, or the button at the bottom of the
Notification Centre) opens the gallery, where each one is added to or taken
from the desktop or the Notification Centre. On the desktop, drag a widget
by any part of it to move it; a click opens its app, and the right button has
Remove Widget. What's where is kept in ~/.config/freemac/widgets.json:
"widgets" for the desktop, with each one's place, and "centre" for the
Notification Centre, in order. Backdrop and Beacon both watch that file, so
a change made in either shows in the other.

Each card is one DrawingArea drawn with cairo and Pango, so it reads on any
wallpaper: a dark, see-through card with white writing. The data comes from
the files the apps keep; nothing here asks the network for anything except
the weather, and only once a place has been added in Sky.
Original freemac code.
"""
import datetime as dt
import json
import math
import os
import subprocess
import threading

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import region  # noqa: E402

CONFIG = os.path.join(GLib.get_user_config_dir(), "freemac", "widgets.json")
SMALL = 164           # a small widget is SMALL x SMALL; a wide one is twice as wide
GAP = 16
RADIUS = 22
LEFT, TOP = 24, 48    # where the first widget goes
DRAG_SLACK = 4        # pixels the pointer moves before a press becomes a drag

# kind: (name, app to open, wide?, words for the gallery)
KINDS = {
    "clock": ("Clock", "freemac-chime", False, "The time, on a clock face"),
    "calendar": ("Calendar", "freemac-tide", True, "Today's date, the month and what's next"),
    "weather": ("Weather", "freemac-sky", False, "Now and today's high and low, from Sky"),
    "reminders": ("Reminders", "freemac-nudge", False, "What's due, from Nudge"),
    "battery": ("Battery", "freemac-dials --panel power", False, "How full the battery is, and whether it's charging"),
    "screentime": ("Screen Time", "freemac-logbook", True, "Time on the computer today, and the apps used most"),
    "world": ("World Clock", "freemac-chime", True, "The time in the cities you added in Chime"),
    "note": ("Sticky Note", "freemac-stickies", False, "Your newest sticky note"),
    "photo": ("Photo", "freemac-frame", False, "A picture from your Pictures folder, a new one each day"),
}
ORDER = ("clock", "calendar", "weather", "reminders", "battery", "screentime", "world", "note", "photo")
CENTRE_DEFAULT = ["weather", "reminders", "screentime"]

INK = (1, 1, 1)         # text and marks; dark on a light card
DIM = (1, 1, 1, 0.62)
FAINT = (1, 1, 1, 0.16)  # rings, tracks and the card's edge
CARD = (0.08, 0.1, 0.14)
LIGHT_CARDS = False
RED = (1.0, 0.36, 0.33)


def _read():
    try:
        with open(CONFIG) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _write(data):
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        with open(CONFIG + ".tmp", "w") as f:
            json.dump(data, f, indent=1)
        os.replace(CONFIG + ".tmp", CONFIG)
    except OSError:
        pass


def load():
    """The desktop's widgets: [{"kind", "x", "y"}]; x and y are None for one
    added from the Notification Centre's gallery, not yet given a place."""
    found = []
    for w in _read().get("widgets", []):
        try:
            if w.get("kind") in KINDS and w["kind"] not in (f["kind"] for f in found):
                x, y = w.get("x"), w.get("y")
                found.append({"kind": w["kind"], "x": None if x is None else int(x),
                              "y": None if y is None else int(y)})
        except (AttributeError, TypeError, ValueError):
            continue
    return found


def save(widgets):
    data = _read()
    data["widgets"] = widgets
    _write(data)


def load_centre():
    """The Notification Centre's widgets, in order."""
    data = _read()
    if not isinstance(data.get("centre"), list):
        return list(CENTRE_DEFAULT)
    return [k for i, k in enumerate(data["centre"]) if k in KINDS and k not in data["centre"][:i]]


def save_centre(kinds):
    data = _read()
    data["centre"] = list(kinds)
    _write(data)


def open_app(kind, data=None):
    """What a click on a widget does: open its app (the photo opens itself)."""
    command = KINDS[kind][1].split()
    if kind == "photo" and data:
        command.append(data)
    try:
        subprocess.Popen(command, start_new_session=True)
    except OSError:
        pass


def size_of(kind):
    return (SMALL * 2 + GAP if KINDS[kind][2] else SMALL), SMALL


def font_family():
    name = Gtk.Settings.get_default().get_property("gtk-font-name") or "Sans 10"
    return Pango.FontDescription.from_string(name).get_family() or "Sans"


def text(cr, words, x, y, size, color=INK, weight=Pango.Weight.NORMAL, width=None, align="left",
         lines=1):
    """Write words with their top left at x, y (or centred or right-aligned
    in width); returns the height used."""
    layout = PangoCairo.create_layout(cr)
    font = Pango.FontDescription()
    font.set_family(font_family())
    font.set_absolute_size(size * Pango.SCALE)
    font.set_weight(weight)
    layout.set_font_description(font)
    layout.set_text(words, -1)
    if width is not None:
        layout.set_width(int(width * Pango.SCALE))
        layout.set_ellipsize(Pango.EllipsizeMode.END)
        if lines > 1:
            layout.set_height(-lines)
            layout.set_wrap(Pango.WrapMode.WORD_CHAR)
        layout.set_alignment({"left": Pango.Alignment.LEFT, "center": Pango.Alignment.CENTER,
                              "right": Pango.Alignment.RIGHT}[align])
    cr.set_source_rgba(*color) if len(color) == 4 else cr.set_source_rgb(*color)
    cr.move_to(x, y)
    PangoCairo.show_layout(cr, layout)
    return layout.get_pixel_size()[1]


def card(cr, width, height, alpha=0.52):
    card_path(cr, width, height)
    cr.set_source_rgba(*CARD, 0.92 if LIGHT_CARDS else alpha)
    cr.fill_preserve()
    cr.set_source_rgba(*FAINT)
    cr.set_line_width(1)
    cr.stroke()


# ---- what each widget shows -------------------------------------------------
def draw_clock(cr, width, height, now):
    cx, cy, r = width / 2, height / 2, min(width, height) / 2 - 14
    cr.set_source_rgba(1, 1, 1, 0.94)
    cr.new_sub_path()
    cr.arc(cx, cy, r, 0, 2 * math.pi)
    cr.fill_preserve()
    cr.set_source_rgba(*FAINT)
    cr.set_line_width(1)
    cr.stroke()
    for hour in range(12):
        angle = hour * math.pi / 6
        x, y = cx + math.sin(angle) * (r - 13), cy - math.cos(angle) * (r - 13)
        text(cr, str(hour or 12), x - 12, y - 8, 12, (0.12, 0.12, 0.14), Pango.Weight.MEDIUM, 24, "center")

    def hand(fraction, length, thick, color):
        angle = fraction * 2 * math.pi
        cr.set_source_rgb(*color)
        cr.set_line_width(thick)
        cr.set_line_cap(1)   # round
        cr.move_to(cx - math.sin(angle) * 8, cy + math.cos(angle) * 8)
        cr.line_to(cx + math.sin(angle) * length, cy - math.cos(angle) * length)
        cr.stroke()
    seconds = now.second + now.microsecond / 1e6
    minutes = now.minute + seconds / 60
    hand(((now.hour % 12) + minutes / 60) / 12, r * 0.5, 4.5, (0.1, 0.1, 0.12))
    hand(minutes / 60, r * 0.78, 3, (0.1, 0.1, 0.12))
    hand(seconds / 60, r * 0.84, 1.4, (0.95, 0.55, 0.1))
    cr.set_source_rgb(0.95, 0.55, 0.1)
    cr.new_sub_path()
    cr.arc(cx, cy, 3.2, 0, 2 * math.pi)
    cr.fill()


def draw_calendar(cr, width, height, today, events):
    half = (width - GAP) / 2
    text(cr, today.strftime("%A").upper(), 16, 14, 12, RED, Pango.Weight.BOLD)
    text(cr, str(today.day), 14, 28, 44, INK, Pango.Weight.LIGHT)
    y = 90
    if not events:
        text(cr, "No more events today", 16, y, 12, DIM, width=half - 20, lines=2)
    for when, title in events[:3]:
        text(cr, title, 16, y, 12, INK, Pango.Weight.MEDIUM, half - 20)
        text(cr, when, 16, y + 15, 11, DIM, width=half - 20)
        y += 34
        if y > height - 30:
            break
    # The month, on the right.
    left = half + GAP
    text(cr, today.strftime("%B").upper(), left, 14, 11, RED, Pango.Weight.BOLD)
    cell_w, cell_h = (width - left - 12) / 7, 17
    week_from = region.first_weekday()
    for i, letter in enumerate(region.week_letters(week_from)):
        text(cr, letter, left + i * cell_w, 32, 10, DIM, Pango.Weight.BOLD, cell_w, "center")
    first = today.replace(day=1)
    lead = (first.weekday() - week_from) % 7   # the region's first day first
    day, row = first, 0
    while day.month == today.month:
        col = (lead + day.day - 1) % 7
        row = (lead + day.day - 1) // 7
        x, y = left + col * cell_w, 50 + row * cell_h
        if day == today:
            cr.set_source_rgb(*RED)
            cr.new_sub_path()
            cr.arc(x + cell_w / 2, y + 7.5, 8.5, 0, 2 * math.pi)
            cr.fill()
        text(cr, str(day.day), x, y, 10.5, INK if day >= today else DIM,
             Pango.Weight.BOLD if day == today else Pango.Weight.NORMAL, cell_w, "center")
        day += dt.timedelta(days=1)


def draw_weather(cr, width, height, place, forecast, note):
    if forecast is None:
        text(cr, "Weather", 16, 16, 15, INK, Pango.Weight.BOLD)
        text(cr, note, 16, 44, 12, DIM, width=width - 32, lines=4)
        return
    from . import sky_store
    text(cr, place, 16, 14, 14, INK, Pango.Weight.BOLD, width - 32)
    text(cr, sky_store.degrees(forecast.temperature), 14, 32, 40, INK, Pango.Weight.LIGHT)
    y = 98
    found = Gtk.IconTheme.get_default().lookup_icon(forecast.icon + "-symbolic", 22, 0)
    if found is not None:
        white = Gdk.RGBA()
        white.parse("white")
        try:
            icon, _symbolic = found.load_symbolic(white, None, None, None)
            Gdk.cairo_set_source_pixbuf(cr, icon, 16, y)
            cr.paint()
            y += 26
        except GLib.Error:
            pass
    today = forecast.today
    text(cr, forecast.words, 16, y, 12, INK, Pango.Weight.MEDIUM, width - 32)
    text(cr, f"H:{sky_store.degrees(today['high'])}  L:{sky_store.degrees(today['low'])}", 16, y + 16, 12, DIM,
         width=width - 32)


def draw_reminders(cr, width, height, items, count):
    text(cr, "Reminders", 16, 14, 14, (0.35, 0.65, 1.0), Pango.Weight.BOLD)
    text(cr, str(count), width - 56, 10, 22, INK, Pango.Weight.BOLD, 40, "right")
    y = 44
    if not items:
        text(cr, "Nothing due. Enjoy!", 16, y, 12, DIM, width=width - 32)
    for title, late in items[:4]:
        cr.set_source_rgba(*DIM)
        cr.set_line_width(1.3)
        cr.new_sub_path()
        cr.arc(22, y + 8, 5.5, 0, 2 * math.pi)
        cr.stroke()
        text(cr, title, 34, y, 12, RED if late else INK, width=width - 50)
        y += 26


GREEN = (0.3, 0.85, 0.45)
YELLOW = (1.0, 0.8, 0.2)
ORANGE = (0.95, 0.55, 0.1)
BLUE = (0.35, 0.65, 1.0)


def draw_battery(cr, width, height, info):
    """info: (percent, charging, words) or None when there's no battery."""
    text(cr, "Battery", 16, 14, 14, INK, Pango.Weight.BOLD)
    if info is None:
        _plug(cr, width / 2, height / 2 - 6)
        text(cr, "Power Adapter", 8, height - 46, 12, INK, Pango.Weight.MEDIUM, width - 16, "center")
        text(cr, "No battery in this computer", 8, height - 28, 10, DIM, width=width - 16, align="center")
        return
    percent, charging, words = info
    cx, cy, r = width / 2, height / 2 + 12, 42
    cr.set_line_width(9)
    cr.set_line_cap(1)
    cr.set_source_rgba(*FAINT)
    cr.new_sub_path()
    cr.arc(cx, cy, r, 0, 2 * math.pi)
    cr.stroke()
    colour = RED if percent <= 10 and not charging else YELLOW if percent <= 20 and not charging else GREEN
    cr.set_source_rgb(*colour)
    cr.new_sub_path()
    cr.arc(cx, cy, r, -math.pi / 2, -math.pi / 2 + 2 * math.pi * max(percent, 1) / 100)
    cr.stroke()
    text(cr, f"{percent}%", cx - 40, cy - 14, 20, INK, Pango.Weight.BOLD, 80, "center")
    text(cr, ("⚡ " if charging else "") + words, cx - 40, cy + 9, 10, DIM, width=80, align="center")


def _plug(cr, cx, cy):
    """A mains plug in a ring, for a computer that runs on its adapter."""
    cr.set_line_width(9)
    cr.set_source_rgba(*FAINT)
    cr.new_sub_path()
    cr.arc(cx, cy, 34, 0, 2 * math.pi)
    cr.stroke()
    cr.set_source_rgb(*GREEN)
    for dx in (-7, 7):                       # the two pins
        cr.rectangle(cx + dx - 2, cy - 17, 4, 10)
    cr.fill()
    cr.new_sub_path()                        # the body
    for x, y, a in ((cx + 8, cy - 3, -math.pi / 2), (cx + 8, cy + 3, 0),
                    (cx - 8, cy + 3, math.pi / 2), (cx - 8, cy - 3, math.pi)):
        cr.arc(x, y, 5, a, a + math.pi / 2)
    cr.close_path()
    cr.fill()
    cr.rectangle(cx - 2.5, cy + 7, 5, 12)    # the cord
    cr.fill()


def draw_screentime(cr, width, height, info):
    """info: (seconds today, [(app name, seconds)])."""
    from .logbook import duration
    total, top = info
    text(cr, "Screen Time", 16, 14, 14, BLUE, Pango.Weight.BOLD)
    text(cr, "Today", width - 116, 16, 12, DIM, width=100, align="right")
    text(cr, duration(total) if total >= 60 else "Under a minute" if total else "Nothing yet",
         16, 34, 26, INK, Pango.Weight.LIGHT, width - 32)
    y = 76
    longest = max([s for _n, s in top] or [1])
    bar_w = width - 32 - 70
    for name, seconds in top[:3]:
        text(cr, name, 16, y, 11.5, INK, Pango.Weight.MEDIUM, bar_w * 0.6)
        text(cr, duration(seconds, short=True) if seconds >= 60 else "<1m", width - 86, y, 11, DIM,
             width=70, align="right")
        cr.set_source_rgba(*FAINT)
        _round_bar(cr, 16, y + 17, bar_w + 54, 5)
        cr.set_source_rgb(*BLUE)
        _round_bar(cr, 16, y + 17, max(5, (bar_w + 54) * seconds / longest), 5)
        y += 27
    if not top:
        text(cr, "Apps you use today show here.", 16, y, 12, DIM, width=width - 32)


def _round_bar(cr, x, y, w, h):
    cr.new_sub_path()
    cr.arc(x + h / 2, y + h / 2, h / 2, math.pi / 2, 3 * math.pi / 2)
    cr.arc(x + w - h / 2, y + h / 2, h / 2, -math.pi / 2, math.pi / 2)
    cr.close_path()
    cr.fill()


def draw_world(cr, width, height, now, cities):
    """cities: [(name, hours ahead of here)], at most four."""
    if not cities:
        text(cr, "World Clock", 16, 14, 14, INK, Pango.Weight.BOLD)
        text(cr, "Add cities in Chime to see their time here.", 16, 44, 12, DIM, width=width - 32, lines=3)
        return
    shown = cities[:4]
    slot = (width - 16) / len(shown)
    for i, (name, offset) in enumerate(shown):
        there = now + dt.timedelta(hours=offset)
        x = 8 + i * slot
        cx, cy, r = x + slot / 2, 58, min(slot / 2 - 10, 40)
        day = 6 <= there.hour < 18
        face, ink = ((0.97, 0.97, 0.97), (0.1, 0.1, 0.12)) if day else ((0.12, 0.13, 0.16), (0.95, 0.95, 0.95))
        cr.set_source_rgb(*face)
        cr.new_sub_path()
        cr.arc(cx, cy, r, 0, 2 * math.pi)
        cr.fill_preserve()
        cr.set_source_rgba(*FAINT)
        cr.set_line_width(1)
        cr.stroke()
        for hour in range(12):
            angle = hour * math.pi / 6
            cr.set_source_rgba(*ink, 0.55)
            cr.new_sub_path()
            cr.arc(cx + math.sin(angle) * (r - 6), cy - math.cos(angle) * (r - 6), 1.3, 0, 2 * math.pi)
            cr.fill()
        minutes = there.minute + there.second / 60

        def hand(fraction, length, thick, colour):
            angle = fraction * 2 * math.pi
            cr.set_source_rgb(*colour)
            cr.set_line_width(thick)
            cr.set_line_cap(1)
            cr.move_to(cx, cy)
            cr.line_to(cx + math.sin(angle) * length, cy - math.cos(angle) * length)
            cr.stroke()
        hand(((there.hour % 12) + minutes / 60) / 12, r * 0.5, 3, ink)
        hand(minutes / 60, r * 0.78, 2, ink)
        cr.set_source_rgb(*ORANGE)
        cr.new_sub_path()
        cr.arc(cx, cy, 2.2, 0, 2 * math.pi)
        cr.fill()
        text(cr, name, x, 106, 11.5, INK, Pango.Weight.MEDIUM, slot, "center")
        when = "Today" if there.date() == now.date() else "Tomorrow" if there.date() > now.date() else "Yesterday"
        sign = "+" if offset >= 0 else "−"
        hours = abs(offset)
        hours_text = f"{hours:g}" if hours != int(hours) else str(int(hours))
        text(cr, f"{when}, {sign}{hours_text}h", x, 122, 10, DIM, width=slot, align="center")


def draw_note(cr, width, height, note):
    """note: (words, colour name) or None."""
    from .stickies import COLOURS
    if note is None:
        text(cr, "Sticky Note", 16, 14, 14, INK, Pango.Weight.BOLD)
        text(cr, "Make a note in Stickies and it shows here.", 16, 44, 12, DIM, width=width - 32, lines=4)
        return
    words, colour = note
    fill = Gdk.RGBA()
    fill.parse(COLOURS.get(colour, COLOURS["yellow"])[0])
    # The note fills the card, as a sticky does.
    card_path(cr, width, height)
    cr.set_source_rgb(fill.red, fill.green, fill.blue)
    cr.fill()
    text(cr, words, 16, 16, 13, (0.17, 0.17, 0.17), width=width - 32, lines=7)


def card_path(cr, width, height):
    cr.new_path()
    cr.new_sub_path()
    for cx, cy, start in ((width - RADIUS, RADIUS, -math.pi / 2), (width - RADIUS, height - RADIUS, 0),
                          (RADIUS, height - RADIUS, math.pi / 2), (RADIUS, RADIUS, math.pi)):
        cr.arc(cx, cy, RADIUS, start, start + math.pi / 2)
    cr.close_path()


def draw_photo(cr, width, height, picture):
    """picture: (path, GdkPixbuf.Pixbuf) or None."""
    if picture is None:
        text(cr, "Photo", 16, 14, 14, INK, Pango.Weight.BOLD)
        text(cr, "Put pictures in your Pictures folder and one shows here each day.", 16, 44, 12, DIM,
             width=width - 32, lines=4)
        return
    pixbuf = picture[1]
    scale = max(width / pixbuf.get_width(), height / pixbuf.get_height())
    cr.save()
    card_path(cr, width, height)
    cr.clip()
    cr.translate((width - pixbuf.get_width() * scale) / 2, (height - pixbuf.get_height() * scale) / 2)
    cr.scale(scale, scale)
    Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
    cr.paint()
    cr.restore()


SAMPLES = {
    "battery": (76, False, "On Battery"),
    "screentime": (2 * 3600 + 14 * 60, [("Tide", 2900), ("Web", 2300), ("Quill", 1500)]),
    "note": ("Pick up library books, then football at 5", "yellow"),
}


def scheme(light):
    """Light cards with dark writing (the Notification Centre in Light
    appearance), or the dark ones the desktop always has."""
    global INK, DIM, FAINT, CARD, LIGHT_CARDS
    LIGHT_CARDS = light
    if light:
        INK, DIM, FAINT, CARD = (0.11, 0.11, 0.13), (0, 0, 0, 0.55), (0, 0, 0, 0.1), (1, 1, 1)
    else:
        INK, DIM, FAINT, CARD = (1, 1, 1), (1, 1, 1, 0.62), (1, 1, 1, 0.16), (0.08, 0.1, 0.14)


def _dark():
    from . import style
    return style.is_dark()


def paint(cr, width, height, kind, data, now=None, centre=False, light=False, alpha=None):
    """Draw one widget: its card and what it shows."""
    now = now or dt.datetime.now()
    scheme(light)
    try:
        _paint(cr, width, height, kind, data, now, alpha or (0.62 if centre else 0.52))
    finally:
        scheme(False)


def _paint(cr, width, height, kind, data, now, alpha):
    if kind not in ("note", "photo") or data is None:
        card(cr, width, height, alpha)
    try:
        if kind == "clock":
            draw_clock(cr, width, height, now)
        elif kind == "calendar":
            draw_calendar(cr, width, height, now.date(), data or [])
        elif kind == "weather":
            place, forecast, note = data or ("", None, "Looking…")
            draw_weather(cr, width, height, place, forecast, note)
        elif kind == "reminders":
            items, count = data or ([], 0)
            draw_reminders(cr, width, height, items, count)
        elif kind == "battery":
            draw_battery(cr, width, height, data)
        elif kind == "screentime":
            draw_screentime(cr, width, height, data or (0, []))
        elif kind == "world":
            draw_world(cr, width, height, now, data or [])
        elif kind == "note":
            draw_note(cr, width, height, data)
        elif kind == "photo":
            draw_photo(cr, width, height, data)
    except Exception as error:   # a widget never takes the desktop down with it
        text(cr, f"Can't show this now ({type(error).__name__})", 16, 16, 12, DIM, width=width - 32, lines=3)


# ---- the widgets ---------------------------------------------------------------
class DeskWidget(Gtk.EventBox):
    def __init__(self, host, kind):
        super().__init__()
        self.host, self.kind = host, kind
        self.set_visible_window(False)
        # The drawing area has a window of its own; the box's input window
        # goes above it, or presses would fall through to the desktop.
        self.set_above_child(True)
        width, height = size_of(kind)
        self.area = Gtk.DrawingArea()
        self.area.set_size_request(width, height)
        self.area.connect("draw", self._draw)
        self.add(self.area)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)
        self.data = None
        self._grab = None   # (pointer x, pointer y, widget x, widget y, dragged?)

    # -- moving and clicking --
    def _root(self, event):
        x, y = self.translate_coordinates(self.host.layout, int(event.x), int(event.y)) or (0, 0)
        return x, y

    def _press(self, _widget, event):
        if event.type != Gdk.EventType.BUTTON_PRESS:
            return True
        if event.button == 3:
            self.host.widget_menu(self, event)
            return True
        if event.button == 1:
            x, y = self._root(event)
            wx, wy = self.host.layout.child_get(self, "x", "y")
            self._grab = [x, y, wx, wy, False]
        return True

    def _motion(self, _widget, event):
        if not self._grab:
            return False
        x, y = self._root(event)
        dx, dy = x - self._grab[0], y - self._grab[1]
        if not self._grab[4] and abs(dx) + abs(dy) < DRAG_SLACK:
            return True
        self._grab[4] = True
        self.host.place(self, self._grab[2] + dx, self._grab[3] + dy)
        return True

    def _release(self, _widget, event):
        grab, self._grab = self._grab, None
        if not grab or event.button != 1:
            return False
        if grab[4]:
            self.host.save()
        else:
            open_app(self.kind, self.data[0] if self.kind == "photo" and self.data else None)
        return True

    # -- drawing --
    def _draw(self, area, cr):
        paint(cr, area.get_allocated_width(), area.get_allocated_height(), self.kind, self.data)
        return False

    def refresh(self):
        """Read what the widget shows again (the clocks need nothing)."""
        self.data = fetch(self.kind, self)
        self.area.queue_draw()


def fetch(kind, widget):
    """What a widget of this kind shows now. widget has .data and .area, for
    the weather, which comes later."""
    if kind == "calendar":
        return calendar_events()
    if kind == "reminders":
        return reminders_due()
    if kind == "weather":
        return weather_now(widget)
    if kind == "battery":
        return battery_now()
    if kind == "screentime":
        return screen_time_today()
    if kind == "world":
        return world_clocks()
    if kind == "note":
        return newest_note()
    if kind == "photo":
        return photo_of_the_day(*size_of(kind))
    return None


def calendar_events():
    """Today's events still to come, as (when, title)."""
    from . import calendar_store
    now = dt.datetime.now()
    found = []
    for occurrence in calendar_store.on_day(calendar_store.load(), now.date()):
        if occurrence.all_day:
            found.append(("All day", occurrence.event.title))
        elif occurrence.end > now:
            found.append((calendar_store.time_text(occurrence.start), occurrence.event.title))
    return found


def reminders_due():
    """Open reminders due by the end of today (overdue first), and how many."""
    from . import reminders_store
    now = dt.datetime.now()
    open_items = [r for r in reminders_store.every(reminders_store.load()) if not r.done]
    due = [r for r in open_items if r.due is not None and r.due.date() <= now.date()]
    due.sort(key=lambda r: r.due_at())
    rest = [r for r in open_items if r.due is None or r.due.date() > now.date()]
    shown = due + sorted(rest, key=lambda r: (r.due is None, r.due_at() or now))
    return [(r.title or "New Reminder", r.overdue(now)) for r in shown], len(due) or len(open_items)


def battery_now():
    """(percent, charging?, words) or None with no battery."""
    from . import battery
    path = battery.find()
    if path is None:
        return None
    try:
        percent = max(0, min(100, int(battery.read(path, "capacity") or 0)))
    except ValueError:
        return None
    status = battery.read(path, "status") or ""
    plugged = battery.on_adapter(path)
    if status == "Full" or (plugged and percent >= 100):
        return percent, False, "Fully Charged"
    if status == "Charging":
        return percent, True, "Charging"
    return percent, False, "Power Adapter" if plugged else "On Battery"


def screen_time_today():
    """(seconds on the computer today, the three apps used most as (name, seconds))."""
    from . import apps
    from .logbook import load_day
    used = load_day(dt.date.today())["apps"]
    top = []
    for app, seconds in sorted(used.items(), key=lambda item: -item[1])[:3]:
        info = apps.app_info(app)
        top.append(((info.get_display_name() if info else None) or app.split(".")[-1].replace("-", " ").title(),
                    seconds))
    return sum(used.values()), top


def world_clocks():
    """[(city, hours ahead of here)] for Chime's cities."""
    import zoneinfo
    from . import chime
    here = dt.datetime.now().astimezone()
    found = []
    for zone in chime.load().get("cities", [])[:4]:
        try:
            there = here.astimezone(zoneinfo.ZoneInfo(zone))
        except (zoneinfo.ZoneInfoNotFoundError, ValueError, TypeError):
            continue
        offset = (there.utcoffset() - here.utcoffset()).total_seconds() / 3600
        found.append((chime.place_name(zone), offset))
    return found


def newest_note():
    """(words, colour) of the last sticky note that has any words, or None."""
    from .stickies import load as load_notes
    for note in reversed(load_notes()):
        words = (note.get("text") or "").strip()
        if words:
            return words, note.get("colour", "yellow")
    return None


PICTURE_TYPES = (".jpg", ".jpeg", ".png", ".webp")
PHOTO_TYPES = (".jpg", ".jpeg")


def photo_of_the_day(width, height):
    """(path, pixbuf) for today's picture from ~/Pictures (and folders in it),
    the same all day, or None."""
    from gi.repository import GdkPixbuf
    folder = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) or os.path.expanduser("~/Pictures")
    found = []
    for top, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        found.extend(os.path.join(top, n) for n in sorted(files) if n.lower().endswith(PICTURE_TYPES))
        if len(found) > 2000:
            break
    photos = [p for p in found if p.lower().endswith(PHOTO_TYPES)]
    found = photos or found     # camera photos first, not screenshots and scans
    if not found:
        return None
    start = dt.date.today().toordinal()
    for i in range(min(len(found), 5)):     # skip one that won't load
        path = found[(start * 7919 + i) % len(found)]
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, width * 2, height * 2, True)
            return path, pixbuf.apply_embedded_orientation() or pixbuf
        except GLib.Error:
            continue
    return None


_fetching = set()


def weather_now(widget):
    """(place name, forecast or None, words to show instead), from Sky's
    chosen place; a fresh forecast is fetched in the background when the
    kept one is old."""
    from . import sky_store
    settings = sky_store.Settings()
    place = next((p for p in settings.places if p.key == settings.chosen), None) or \
        (settings.places[0] if settings.places else None)
    if place is None:
        return "", None, "Add your town in Sky to see the weather here."
    forecast = sky_store.cached(place, settings.unit)
    if (forecast is None or forecast.stale()) and place.key not in _fetching:
        _fetching.add(place.key)

        def fetch():
            try:
                fresh = sky_store.forecast(place, settings.unit)
            except (OSError, ValueError, KeyError, TypeError):
                fresh = None
            GLib.idle_add(done, fresh)

        def done(fresh):
            _fetching.discard(place.key)
            if fresh is not None:
                widget.data = (place.name, fresh, "")
                widget.area.queue_draw()
            elif widget.data and widget.data[1] is None:
                widget.data = (place.name, None, "The weather can't be reached right now.")
                widget.area.queue_draw()
            return False
        threading.Thread(target=fetch, daemon=True).start()
    if forecast is None:
        return place.name, None, f"Getting the weather for {place.name}…"
    return place.name, forecast, ""


# ---- the host: the desktop's layout ----------------------------------------------
class WidgetHost:
    """Puts the widgets into the desktop's Gtk.Layout and keeps them there."""

    def __init__(self, layout):
        self.layout = layout
        self.widgets = []
        self.gallery = None
        self.saving = False
        for saved in load():
            if saved["x"] is None:
                self.add(saved["kind"])
            else:
                self._make(saved["kind"], saved["x"], saved["y"])
        GLib.timeout_add(1000, self._second)
        GLib.timeout_add_seconds(60, self._minute)
        self.monitor = watch(self.reload)

    def _make(self, kind, x, y):
        widget = DeskWidget(self, kind)
        self.widgets.append(widget)
        self.layout.put(widget, 0, 0)
        widget.show_all()
        self.place(widget, x, y)
        widget.refresh()
        return widget

    def place(self, widget, x, y):
        """Move a widget, kept on the screen and clear of the menu bar."""
        width, height = size_of(widget.kind)
        screen_w, screen_h = self.screen()
        x = max(4, min(int(x), screen_w - width - 4))
        y = max(32, min(int(y), screen_h - height - 4))
        self.layout.move(widget, x, y)
        self.layout.queue_resize()

    def screen(self):
        """The screen's size, even before GTK has laid the desktop out."""
        if hasattr(self.layout, "size"):
            return self.layout.size()
        return max(self.layout.get_allocated_width(), 1280), max(self.layout.get_allocated_height(), 800)

    def save(self):
        save([{"kind": w.kind, "x": self.layout.child_get(w, "x", "y")[0],
               "y": self.layout.child_get(w, "x", "y")[1]} for w in self.widgets])

    def kinds(self):
        return [w.kind for w in self.widgets]

    def add(self, kind):
        """Add a widget in the first free place down the left side."""
        if kind in self.kinds():
            return
        x, y = LEFT, TOP
        width, height = size_of(kind)
        screen_h = self.screen()[1]
        taken = [(*self.layout.child_get(w, "x", "y"), *size_of(w.kind)) for w in self.widgets]

        def clashes(x, y):
            return any(x < tx + tw + GAP and tx < x + width + GAP and y < ty + th + GAP and ty < y + height + GAP
                       for tx, ty, tw, th in taken)
        while clashes(x, y):
            y += SMALL + GAP
            if y + height > screen_h - 90:
                x, y = x + SMALL + GAP, TOP
        self._make(kind, x, y)
        self.save()

    def remove(self, kind):
        widget = next((w for w in self.widgets if w.kind == kind), None)
        if widget is not None:
            self.widgets.remove(widget)
            widget.destroy()
            self.save()
            if self.gallery:
                self.gallery.update()

    def reload(self):
        """widgets.json changed, perhaps from the Notification Centre's gallery."""
        saved = load()
        wanted = [s["kind"] for s in saved]
        for widget in list(self.widgets):
            if widget.kind not in wanted:
                self.widgets.remove(widget)
                widget.destroy()
        for spot in saved:
            if spot["kind"] in self.kinds():
                if spot["x"] is not None:        # moved in the file
                    widget = next(w for w in self.widgets if w.kind == spot["kind"])
                    self.place(widget, spot["x"], spot["y"])
                continue
            if spot["x"] is None:
                self.add(spot["kind"])
            else:
                self._make(spot["kind"], spot["x"], spot["y"])
        if self.gallery:
            self.gallery.update()

    def _second(self):
        for widget in self.widgets:
            if widget.kind == "clock":
                widget.area.queue_draw()
        return True

    def _minute(self):
        for widget in self.widgets:
            if widget.kind != "clock":
                widget.refresh()
        return True

    def widget_menu(self, widget, event):
        menu = Gtk.Menu()
        menu.attach_to_widget(self.layout, None)
        for label, action in ((f"Open {KINDS[widget.kind][0]}",
                               lambda: open_app(widget.kind, widget.data[0] if widget.kind == "photo"
                                                and widget.data else None)),
                              (None, None), ("Remove Widget", lambda: self.remove(widget.kind)),
                              ("Edit Widgets…", self.edit)):
            if label is None:
                menu.append(Gtk.SeparatorMenuItem())
                continue
            item = Gtk.MenuItem(label=label)
            item.connect("activate", lambda _i, a=action: a())
            menu.append(item)
        menu.show_all()
        menu.popup_at_pointer(event)
        self.menu = menu

    def edit(self, place="desktop"):
        if self.gallery is None:
            self.gallery = Gallery(desktop=self, centre=CentreFile())
        self.gallery.show_place(place)
        self.gallery.present()


def watch(changed):
    """Call changed() when widgets.json is changed by someone else."""
    from gi.repository import Gio
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        monitor = Gio.File.new_for_path(CONFIG).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, None)
    except GLib.Error:
        return None
    pending = []

    def later():
        pending.clear()
        changed()
        return False

    def event(_monitor, _file, _other, kind):
        if kind in (Gio.FileMonitorEvent.CHANGES_DONE_HINT, Gio.FileMonitorEvent.RENAMED,
                    Gio.FileMonitorEvent.MOVED_IN, Gio.FileMonitorEvent.CREATED,
                    Gio.FileMonitorEvent.DELETED) and not pending:
            pending.append(GLib.timeout_add(300, later))
    monitor.connect("changed", event)
    return monitor


class CentreFile:
    """The Notification Centre's widgets, as the gallery changes them from
    the desktop; Beacon sees the file change."""

    def kinds(self):
        return load_centre()

    def add(self, kind):
        kinds = load_centre()
        if kind not in kinds:
            save_centre(kinds + [kind])

    def remove(self, kind):
        save_centre([k for k in load_centre() if k != kind])


class DesktopFile:
    """The desktop's widgets, as the gallery changes them from the
    Notification Centre; Backdrop sees the file change and gives a new one
    its place."""

    def kinds(self):
        return [w["kind"] for w in load()]

    def add(self, kind):
        found = load()
        if kind not in (w["kind"] for w in found):
            save(found + [{"kind": kind, "x": None, "y": None}])

    def remove(self, kind):
        save([w for w in load() if w["kind"] != kind])


class Gallery(Gtk.Window):
    """Edit Widgets: each kind with a picture of it, and Add or Remove, for
    the desktop or the Notification Centre."""

    def __init__(self, desktop, centre):
        super().__init__(title="Widgets")
        self.places = {"desktop": desktop, "centre": centre}
        self.place = "desktop"
        self.set_default_size(600, 640)
        self.connect("delete-event", lambda *_: self.hide() or True)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
        switch = Gtk.Box(halign=Gtk.Align.CENTER)
        switch.get_style_context().add_class("linked")
        self.tabs = {}
        first = None
        for place, label in (("desktop", "Desktop"), ("centre", "Notification Centre")):
            tab = Gtk.RadioButton.new_with_label_from_widget(first, label)
            tab.set_mode(False)
            first = first or tab
            tab.connect("toggled", self._tab, place)
            self.tabs[place] = tab
            switch.pack_start(tab, False, False, 0)
        box.pack_start(switch, False, False, 0)
        self.intro = Gtk.Label(xalign=0, wrap=True)
        self.intro.get_style_context().add_class("dim-label")
        box.pack_start(self.intro, False, False, 0)
        grid = Gtk.Grid(column_spacing=18, row_spacing=14, margin_end=8)
        self.buttons, self.previews = {}, []
        for row, kind in enumerate(ORDER):
            name, _app, wide, about = KINDS[kind]
            preview = Gtk.DrawingArea()
            w, h = size_of(kind)
            preview.set_size_request(int(w * 0.5), int(h * 0.5))
            preview.set_halign(Gtk.Align.START)
            preview.connect("draw", self._draw_preview, kind)
            self.previews.append(preview)
            grid.attach(preview, 0, row, 1, 1)
            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER, hexpand=True)
            title = Gtk.Label(label=name, xalign=0)
            title.get_style_context().add_class("heading")
            words.pack_start(title, False, False, 0)
            detail = Gtk.Label(label=about, xalign=0, wrap=True, max_width_chars=30)
            detail.get_style_context().add_class("dim-label")
            words.pack_start(detail, False, False, 0)
            grid.attach(words, 1, row, 1, 1)
            button = Gtk.Button(valign=Gtk.Align.CENTER)
            button.connect("clicked", self._toggle, kind)
            self.buttons[kind] = button
            grid.attach(button, 2, row, 1, 1)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        scroller.add(grid)
        box.pack_start(scroller, True, True, 0)
        done = Gtk.Button(label="Done", halign=Gtk.Align.END)
        done.get_style_context().add_class("suggested-action")
        done.connect("clicked", lambda *_: self.hide())
        box.pack_start(done, False, False, 4)
        self.add(box)
        box.show_all()
        self.update()

    def show_place(self, place):
        self.tabs[place].set_active(True)
        self._tab(self.tabs[place], place)

    def _tab(self, tab, place):
        if not tab.get_active():
            return
        self.place = place
        self.intro.set_text("Add widgets to your desktop. Drag one to move it; click it to open its app."
                            if place == "desktop" else
                            "Add widgets to the Notification Centre, under your notifications. Click the clock "
                            "in the menu bar to see them.")
        for preview in self.previews:
            preview.queue_draw()      # light cards in a light Notification Centre
        self.update()

    def _draw_preview(self, area, cr, kind):
        cr.scale(0.5, 0.5)
        width, height = size_of(kind)
        sample = {
            "calendar": [("10:00 AM", "Swim lesson"), ("3:30 PM", "Dentist")],
            "weather": ("", None, "Sunny, with your town's high and low"),
            "reminders": ([("Library books", False), ("Call Grandma", False)], 2),
            "world": [("London", 6), ("Tokyo", 15), ("Denver", -1)],
            "photo": None,
        }
        data = SAMPLES.get(kind, sample.get(kind))
        cr.push_group()
        paint(cr, width, height, kind, data, dt.datetime(2026, 1, 1, 10, 9, 30),
              light=self.place == "centre" and not _dark(), alpha=0.86)
        cr.pop_group_to_source()
        cr.paint()
        return False

    def _toggle(self, _button, kind):
        target = self.places[self.place]
        if kind in target.kinds():
            target.remove(kind)
        else:
            target.add(kind)
        self.update()

    def update(self):
        kinds = self.places[self.place].kinds()
        for kind, button in self.buttons.items():
            button.set_label("Remove" if kind in kinds else "Add")


# ---- in the Notification Centre ---------------------------------------------------
CENTRE_WIDTH = 340     # the Notification Centre's width inside its padding
CENTRE_GAP = 12


class CentreWidget(Gtk.EventBox):
    """One widget in the Notification Centre: a click opens its app."""

    def __init__(self, kind, width, opened):
        super().__init__()
        self.kind, self.opened = kind, opened
        self.data = None
        self.area = Gtk.DrawingArea()
        self.area.set_size_request(width, SMALL)
        self.area.connect("draw", lambda area, cr: paint(cr, area.get_allocated_width(),
                                                          area.get_allocated_height(), kind, self.data,
                                                          centre=True, light=not _dark()) or False)
        self.add(self.area)
        self.connect("button-release-event", self._clicked)

    def _clicked(self, _widget, event):
        if event.button == 1:
            self.opened()
            open_app(self.kind, self.data[0] if self.kind == "photo" and self.data else None)
        return True

    def refresh(self):
        self.data = fetch(self.kind, self)
        self.area.queue_draw()


class CentreWidgets(Gtk.Box):
    """The widgets under the notifications, two small ones to a row and a
    wide one on a row of its own, with Edit Widgets… under them. opened()
    is called before a widget opens its app (Beacon hides the centre)."""

    def __init__(self, opened):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=CENTRE_GAP)
        self.opened = opened
        self.items = []
        self.gallery = None
        self.rows = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=CENTRE_GAP)
        self.pack_start(self.rows, False, False, 0)
        edit = Gtk.Button(label="Edit Widgets…", halign=Gtk.Align.CENTER)
        edit.get_style_context().add_class("beacon-more")
        edit.connect("clicked", lambda *_: self.edit())
        self.pack_start(edit, False, False, 0)
        self.build()
        self.monitor = watch(self.build)
        GLib.timeout_add(1000, self._second)

    def build(self):
        for row in self.rows.get_children():
            row.destroy()
        self.items = []
        small = (CENTRE_WIDTH - CENTRE_GAP) // 2
        row, used = None, 0
        for kind in load_centre():
            wide = KINDS[kind][2]
            if wide or row is None or used >= 2:
                row = Gtk.Box(spacing=CENTRE_GAP)
                self.rows.pack_start(row, False, False, 0)
                used = 0
            item = CentreWidget(kind, CENTRE_WIDTH if wide else small, self.opened)
            row.pack_start(item, False, False, 0)
            used = 2 if wide else used + 1
            self.items.append(item)
        self.refresh()
        self.show_all()
        if self.gallery:
            self.gallery.update()

    def refresh(self):
        """Read every widget's data again (Beacon calls this as the centre opens)."""
        for item in self.items:
            item.refresh()

    def _second(self):
        if self.get_mapped():
            for item in self.items:
                if item.kind in ("clock", "world"):
                    item.area.queue_draw()
        return True

    # the gallery's view of the Notification Centre
    def kinds(self):
        return load_centre()

    def add(self, kind):
        CentreFile().add(kind)
        self.build()

    def remove(self, kind):
        CentreFile().remove(kind)
        self.build()

    def edit(self):
        self.opened()
        if self.gallery is None:
            self.gallery = Gallery(desktop=DesktopFile(), centre=self)
        self.gallery.show_place("centre")
        self.gallery.present()
