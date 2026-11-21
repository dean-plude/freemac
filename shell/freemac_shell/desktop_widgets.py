# SPDX-License-Identifier: GPL-3.0-or-later
"""Widgets on the desktop: a clock, today's calendar, the weather and your
reminders, as small cards over the wallpaper.

Right-click the desktop and choose Edit Widgets… to add or take one away.
Drag a widget by any part of it to move it (the places are kept in
~/.config/freemac/widgets.json); a click opens its app (Chime, Tide, Sky or
Nudge), and the right button has Remove Widget.

Each card is one DrawingArea drawn with cairo and Pango, so it reads on any
wallpaper: a dark, see-through card with white writing. The weather comes
from Sky's chosen place (sky_store), only once a place has been added there;
the calendar and reminders read the files Tide and Nudge keep.
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
}
ORDER = ("clock", "calendar", "weather", "reminders")

WHITE = (1, 1, 1)
DIM = (1, 1, 1, 0.62)
RED = (1.0, 0.36, 0.33)


def load():
    try:
        with open(CONFIG) as f:
            data = json.load(f)
        return [{"kind": w["kind"], "x": int(w["x"]), "y": int(w["y"])}
                for w in data.get("widgets", []) if w.get("kind") in KINDS]
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return []


def save(widgets):
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        with open(CONFIG + ".tmp", "w") as f:
            json.dump({"widgets": widgets}, f, indent=1)
        os.replace(CONFIG + ".tmp", CONFIG)
    except OSError:
        pass


def size_of(kind):
    return (SMALL * 2 + GAP if KINDS[kind][2] else SMALL), SMALL


def font_family():
    name = Gtk.Settings.get_default().get_property("gtk-font-name") or "Sans 10"
    return Pango.FontDescription.from_string(name).get_family() or "Sans"


def text(cr, words, x, y, size, color=WHITE, weight=Pango.Weight.NORMAL, width=None, align="left",
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
    cr.new_path()
    cr.new_sub_path()
    for cx, cy, start in ((width - RADIUS, RADIUS, -math.pi / 2), (width - RADIUS, height - RADIUS, 0),
                          (RADIUS, height - RADIUS, math.pi / 2), (RADIUS, RADIUS, math.pi)):
        cr.arc(cx, cy, RADIUS, start, start + math.pi / 2)
    cr.close_path()
    cr.set_source_rgba(0.08, 0.1, 0.14, alpha)
    cr.fill_preserve()
    cr.set_source_rgba(1, 1, 1, 0.16)
    cr.set_line_width(1)
    cr.stroke()


# ---- what each widget shows -------------------------------------------------
def draw_clock(cr, width, height, now):
    cx, cy, r = width / 2, height / 2, min(width, height) / 2 - 14
    cr.set_source_rgba(1, 1, 1, 0.94)
    cr.new_sub_path()
    cr.arc(cx, cy, r, 0, 2 * math.pi)
    cr.fill()
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
    text(cr, str(today.day), 14, 28, 44, WHITE, Pango.Weight.LIGHT)
    y = 90
    if not events:
        text(cr, "No more events today", 16, y, 12, DIM, width=half - 20, lines=2)
    for when, title in events[:3]:
        text(cr, title, 16, y, 12, WHITE, Pango.Weight.MEDIUM, half - 20)
        text(cr, when, 16, y + 15, 11, DIM, width=half - 20)
        y += 34
        if y > height - 30:
            break
    # The month, on the right.
    left = half + GAP
    text(cr, today.strftime("%B").upper(), left, 14, 11, RED, Pango.Weight.BOLD)
    cell_w, cell_h = (width - left - 12) / 7, 17
    for i, letter in enumerate("SMTWTFS"):
        text(cr, letter, left + i * cell_w, 32, 10, DIM, Pango.Weight.BOLD, cell_w, "center")
    first = today.replace(day=1)
    lead = (first.weekday() + 1) % 7   # Sunday first
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
        text(cr, str(day.day), x, y, 10.5, WHITE if day >= today else DIM,
             Pango.Weight.BOLD if day == today else Pango.Weight.NORMAL, cell_w, "center")
        day += dt.timedelta(days=1)


def draw_weather(cr, width, height, place, forecast, note):
    if forecast is None:
        text(cr, "Weather", 16, 16, 15, WHITE, Pango.Weight.BOLD)
        text(cr, note, 16, 44, 12, DIM, width=width - 32, lines=4)
        return
    from . import sky_store
    text(cr, place, 16, 14, 14, WHITE, Pango.Weight.BOLD, width - 32)
    text(cr, sky_store.degrees(forecast.temperature), 14, 32, 40, WHITE, Pango.Weight.LIGHT)
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
    text(cr, forecast.words, 16, y, 12, WHITE, Pango.Weight.MEDIUM, width - 32)
    text(cr, f"H:{sky_store.degrees(today['high'])}  L:{sky_store.degrees(today['low'])}", 16, y + 16, 12, DIM,
         width=width - 32)


def draw_reminders(cr, width, height, items, count):
    text(cr, "Reminders", 16, 14, 14, (0.35, 0.65, 1.0), Pango.Weight.BOLD)
    text(cr, str(count), width - 56, 10, 22, WHITE, Pango.Weight.BOLD, 40, "right")
    y = 44
    if not items:
        text(cr, "Nothing due. Enjoy!", 16, y, 12, DIM, width=width - 32)
    for title, late in items[:4]:
        cr.set_source_rgba(1, 1, 1, 0.7)
        cr.set_line_width(1.3)
        cr.new_sub_path()
        cr.arc(22, y + 8, 5.5, 0, 2 * math.pi)
        cr.stroke()
        text(cr, title, 34, y, 12, RED if late else WHITE, width=width - 50)
        y += 26


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
            subprocess.Popen([KINDS[self.kind][1]], start_new_session=True)
        return True

    # -- drawing --
    def _draw(self, area, cr):
        width, height = area.get_allocated_width(), area.get_allocated_height()
        card(cr, width, height)
        try:
            if self.kind == "clock":
                draw_clock(cr, width, height, dt.datetime.now())
            elif self.kind == "calendar":
                draw_calendar(cr, width, height, dt.date.today(), self.data or [])
            elif self.kind == "weather":
                place, forecast, note = self.data or ("", None, "Looking…")
                draw_weather(cr, width, height, place, forecast, note)
            elif self.kind == "reminders":
                items, count = self.data or ([], 0)
                draw_reminders(cr, width, height, items, count)
        except Exception as error:   # a widget never takes the desktop down with it
            text(cr, f"Can't show this now ({type(error).__name__})", 16, 16, 12, DIM, width=width - 32, lines=3)
        return False

    def refresh(self):
        """Read what the widget shows again (the clock needs nothing)."""
        if self.kind == "calendar":
            self.data = calendar_events()
        elif self.kind == "reminders":
            self.data = reminders_due()
        elif self.kind == "weather":
            self.data = weather_now(self)
        self.area.queue_draw()


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
        for saved in load():
            self._make(saved["kind"], saved["x"], saved["y"])
        GLib.timeout_add(1000, self._second)
        GLib.timeout_add_seconds(60, self._minute)

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
        return {w.kind for w in self.widgets}

    def add(self, kind):
        """Add a widget in the first free place down the left side."""
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

    def remove(self, widget):
        if widget in self.widgets:
            self.widgets.remove(widget)
            widget.destroy()
            self.save()
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
        for label, action in ((f"Open {KINDS[widget.kind][0]}", lambda: subprocess.Popen(
                                  [KINDS[widget.kind][1]], start_new_session=True)),
                              (None, None), ("Remove Widget", lambda: self.remove(widget)),
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

    def edit(self):
        if self.gallery is None:
            self.gallery = Gallery(self)
        self.gallery.update()
        self.gallery.present()


class Gallery(Gtk.Window):
    """Edit Widgets: each kind with a picture of it and Add or Remove."""

    def __init__(self, host):
        super().__init__(title="Widgets")
        self.host = host
        self.set_default_size(560, -1)
        self.set_resizable(False)
        self.connect("delete-event", lambda *_: self.hide() or True)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
        intro = Gtk.Label(label="Add widgets to your desktop. Drag one to move it; click it to open its app.",
                          xalign=0, wrap=True)
        intro.get_style_context().add_class("dim-label")
        box.pack_start(intro, False, False, 0)
        grid = Gtk.Grid(column_spacing=18, row_spacing=14)
        self.buttons = {}
        for row, kind in enumerate(ORDER):
            name, _app, wide, about = KINDS[kind]
            preview = Gtk.DrawingArea()
            w, h = size_of(kind)
            preview.set_size_request(int(w * 0.5), int(h * 0.5))
            preview.set_halign(Gtk.Align.START)
            preview.connect("draw", self._draw_preview, kind)
            grid.attach(preview, 0, row, 1, 1)
            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
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
        box.pack_start(grid, False, False, 0)
        done = Gtk.Button(label="Done", halign=Gtk.Align.END)
        done.get_style_context().add_class("suggested-action")
        done.connect("clicked", lambda *_: self.hide())
        box.pack_start(done, False, False, 4)
        self.add(box)
        box.show_all()

    def _draw_preview(self, area, cr, kind):
        cr.scale(0.5, 0.5)
        width, height = size_of(kind)
        card(cr, width, height, 0.82)   # as it looks over the wallpaper
        sample = {"clock": lambda: draw_clock(cr, width, height, dt.datetime(2026, 1, 1, 10, 9, 30)),
                  "calendar": lambda: draw_calendar(cr, width, height, dt.date.today(),
                                                    [("10:00 AM", "Swim lesson"), ("3:30 PM", "Dentist")]),
                  "weather": lambda: draw_weather(cr, width, height, "", None, "Sunny, with your town's "
                                                  "high and low"),
                  "reminders": lambda: draw_reminders(cr, width, height,
                                                      [("Library books", False), ("Call Grandma", False)], 2)}
        sample[kind]()
        return False

    def _toggle(self, _button, kind):
        found = next((w for w in self.host.widgets if w.kind == kind), None)
        if found:
            self.host.remove(found)
        else:
            self.host.add(kind)
        self.update()

    def update(self):
        kinds = self.host.kinds()
        for kind, button in self.buttons.items():
            button.set_label("Remove" if kind in kinds else "Add")
