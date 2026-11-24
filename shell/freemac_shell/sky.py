# SPDX-License-Identifier: GPL-3.0-or-later
"""Sky: the weather where you are and in the places you add.

The places are listed on the left with their temperature now. The chosen
place fills the rest of the window, over colours that follow its weather
and whether it's day or night there: the temperature and the sky now, the
next 24 hours, the next 10 days with each day's low and high drawn against
the whole week's, and how it feels, the wind, the humidity and the sun.

The + button finds a place by name. Right-click a place (or press Delete)
to remove it. The first time Sky opens it offers the city of the computer's
time zone.

The weather comes from Open-Meteo (sky_store.py) and is asked for again
every 15 minutes while Sky is open. Original freemac code.
"""
import datetime
import sys
import threading

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402

from . import menus, sky_store, style  # noqa: E402
from .sky_store import degrees  # noqa: E402

APP_ID = "org.freemac.Sky"
REFRESH = 15 * 60

# Colours behind the weather: (top, bottom) by look and day or night.
LOOKS = {
    ("clear", True): ("#3f8fe0", "#86c3f2"),
    ("clear", False): ("#0b1633", "#2a3a6a"),
    ("cloudy", True): ("#5d7c9c", "#a1b6c9"),
    ("cloudy", False): ("#1c2433", "#3e4a5e"),
    ("fog", True): ("#8b98a5", "#c3cbd2"),
    ("fog", False): ("#2b3138", "#4c555e"),
    ("rain", True): ("#4a5d73", "#7d8fa3"),
    ("rain", False): ("#161d29", "#33415a"),
    ("snow", True): ("#7f9bb8", "#d4e0ec"),
    ("snow", False): ("#26334a", "#56657e"),
    ("storm", True): ("#3a3f52", "#6a6f86"),
    ("storm", False): ("#121420", "#2e3146"),
}

CSS = b"""
.sky-side { background: #ececee; }
.sky-side list { background: transparent; }
.sky-side row { border-radius: 9px; margin: 2px 8px; padding: 8px 10px; }
.sky-side row:selected { background: @theme_selected_bg_color; }
.sky-side row:selected label { color: white; }
.sky-place { font-weight: 600; }
.sky-place-temp { font-size: 1.6em; font-weight: 300; }
.sky-small { font-size: 0.85em; color: alpha(currentColor, 0.65); }
.sky-main, .sky-main label { color: white; }
.sky-name { font-size: 2em; font-weight: 500; }
.sky-now { font-size: 6em; font-weight: 200; }
.sky-words { font-size: 1.25em; font-weight: 500; }
.sky-panel { background: alpha(black, 0.16); border-radius: 14px; padding: 12px 14px;
  border: 1px solid alpha(white, 0.12); }
.sky-heading { font-size: 0.78em; font-weight: 600; color: alpha(white, 0.7); }
.sky-hour-time { font-size: 0.9em; font-weight: 500; }
.sky-hour-temp { font-size: 1.1em; font-weight: 500; }
.sky-rain { font-size: 0.8em; color: #9fd5ff; font-weight: 600; }
.sky-day { font-size: 1.05em; font-weight: 500; }
.sky-low { color: alpha(white, 0.6); }
.sky-fact-value { font-size: 1.6em; font-weight: 400; }
.sky-note { font-size: 0.8em; color: alpha(white, 0.6); }
.sky-empty-title { font-size: 1.4em; font-weight: 600; }
"""


def clock_words(when):
    """3 PM, or 15:00 where the clock is 24-hour."""
    if uses_24_hours():
        return when.strftime("%H:%M")
    hour = when.hour % 12 or 12
    return f"{hour} {'AM' if when.hour < 12 else 'PM'}"


def time_words(when):
    if uses_24_hours():
        return when.strftime("%H:%M")
    hour = when.hour % 12 or 12
    return f"{hour}:{when.minute:02d} {'AM' if when.hour < 12 else 'PM'}"


def uses_24_hours():
    """The same clock as the menu bar's (Dials > Date & Time)."""
    return style.h24()


def day_words(date, today):
    if date == today:
        return "Today"
    return date.strftime("%a")


class RangeBar(Gtk.DrawingArea):
    """A day's low to high, drawn within the lowest and highest of the week."""

    def __init__(self, low, high, week_low, week_high, now=None):
        super().__init__()
        self.low, self.high = low, high
        self.week_low, self.week_high = week_low, week_high
        self.now = now
        self.set_size_request(120, 6)
        self.set_valign(Gtk.Align.CENTER)
        self.set_hexpand(True)
        self.connect("draw", self._draw)

    @staticmethod
    def _colour(t, unit):
        """Blue when cold through green and yellow to orange when hot."""
        c = (t - 32) * 5 / 9 if unit == "F" else t
        stops = [(-10, (0.35, 0.6, 1.0)), (5, (0.35, 0.8, 0.95)), (15, (0.5, 0.85, 0.5)),
                 (22, (0.98, 0.85, 0.3)), (30, (1.0, 0.55, 0.2))]
        if c <= stops[0][0]:
            return stops[0][1]
        for (a, ca), (b, cb) in zip(stops, stops[1:]):
            if c <= b:
                f = (c - a) / (b - a)
                return tuple(x + (y - x) * f for x, y in zip(ca, cb))
        return stops[-1][1]

    def _draw(self, _w, cr):
        width = self.get_allocated_width()
        height = self.get_allocated_height()
        span = max(1e-6, self.week_high - self.week_low)
        r = height / 2

        def rounded(x0, x1, colour):
            cr.new_path()
            cr.arc(x0 + r, r, r, 1.5708, 4.7124)
            cr.arc(max(x0 + r, x1 - r), r, r, 4.7124, 1.5708)
            cr.close_path()
            cr.set_source(colour) if not isinstance(colour, tuple) else cr.set_source_rgba(*colour)
            cr.fill()

        rounded(0, width, (0, 0, 0, 0.22))
        x0 = (self.low - self.week_low) / span * width
        x1 = max(x0 + height, (self.high - self.week_low) / span * width)
        import cairo
        gradient = cairo.LinearGradient(x0, 0, x1, 0)
        unit = getattr(self, "unit", "F")
        gradient.add_color_stop_rgb(0, *self._colour(self.low, unit))
        gradient.add_color_stop_rgb(1, *self._colour(self.high, unit))
        rounded(x0, x1, gradient)
        if self.now is not None and self.low <= self.now <= self.high:
            x = (self.now - self.week_low) / span * width
            cr.set_source_rgba(0, 0, 0, 0.35)
            cr.arc(x, r, r + 1.5, 0, 6.2832)
            cr.fill()
            cr.set_source_rgb(1, 1, 1)
            cr.arc(x, r, r - 0.5, 0, 6.2832)
            cr.fill()
        return False


class Backdrop(Gtk.EventBox):
    """The chosen place's colours, behind everything on the right."""

    def __init__(self):
        super().__init__()
        self.colours = LOOKS[("clear", True)]
        self.set_app_paintable(True)
        self.connect("draw", self._draw)

    def set_look(self, look, day):
        self.colours = LOOKS.get((look, day), LOOKS[("cloudy", day)])
        self.queue_draw()

    def _draw(self, _w, cr):
        import cairo
        height = self.get_allocated_height()
        gradient = cairo.LinearGradient(0, 0, 0, height)
        for at, colour in zip((0, 1), self.colours):
            rgba = Gdk.RGBA()
            rgba.parse(colour)
            gradient.add_color_stop_rgb(at, rgba.red, rgba.green, rgba.blue)
        cr.set_source(gradient)
        cr.paint()
        return False


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Sky")
        self.set_default_size(980, 680)
        self.settings = app.settings
        self.forecasts = {}       # place key -> Forecast
        self.problems = {}        # place key -> words
        self.asking = set()

        header = Gtk.HeaderBar(show_close_button=True, title="Sky")
        self.set_titlebar(header)
        add = Gtk.MenuButton()
        add.set_image(Gtk.Image.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON))
        add.set_tooltip_text("Add a Place (⌘N)")
        add.set_popover(self._build_search())
        header.pack_start(add)
        self.add_button = add
        self.spinner = Gtk.Spinner()
        header.pack_end(self.spinner)

        paned = Gtk.Paned()
        self.add(paned)
        side = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side.get_style_context().add_class("sky-side")
        side.set_size_request(250, -1)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.list.connect("row-selected", self._row_selected)
        self.list.connect("button-press-event", self._list_pressed)
        side.add(self.list)
        paned.pack1(side, False, False)

        self.backdrop = Backdrop()
        self.backdrop.get_style_context().add_class("sky-main")
        self.main_scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.backdrop.add(self.main_scroller)
        paned.pack2(self.backdrop, True, False)
        self.main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=28)
        self.main.set_halign(Gtk.Align.CENTER)
        self.main.set_size_request(560, -1)
        self.main_scroller.add(self.main)

        menus.add_actions(self, {"add-place": lambda: add.set_active(True), "remove": self.remove_chosen,
                                 "refresh": lambda: self.refresh(force=True), "close": self.close})
        self.connect("key-press-event", self._key)
        self.show_all()
        self.load_places()
        self.refresh()
        self.timer = GLib.timeout_add_seconds(60, self._tick)
        self.connect("destroy", lambda _w: GLib.source_remove(self.timer))
        if not self.settings.places and not self.settings.asked_home:
            self._offer_home()

    # -- adding a place --

    def _build_search(self):
        popover = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=10)
        self.search_entry = Gtk.SearchEntry(placeholder_text="City or town")
        self.search_entry.set_width_chars(28)
        self.search_entry.connect("search-changed", self._search_changed)
        self.search_entry.connect("activate", self._search_activate)
        box.pack_start(self.search_entry, False, False, 0)
        self.results = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.results.set_activate_on_single_click(True)
        self.results.connect("row-activated", lambda _l, row: self._chose(row.place))
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_propagate_natural_height(True)
        scroller.set_max_content_height(300)
        scroller.add(self.results)
        box.pack_start(scroller, True, True, 0)
        self.search_note = Gtk.Label(xalign=0, wrap=True, max_width_chars=34)
        self.search_note.get_style_context().add_class("dim-label")
        box.pack_start(self.search_note, False, False, 0)
        box.show_all()
        self.search_note.hide()
        scroller.hide()
        self.results_scroller = scroller
        popover.add(box)
        popover.connect("closed", lambda _p: self.search_entry.set_text(""))
        self.search_serial = 0
        return popover

    def _search_changed(self, entry):
        self.search_serial += 1
        serial = self.search_serial
        text = entry.get_text().strip()
        if len(text) < 2:
            self._show_results([], None)
            return
        GLib.timeout_add(300, lambda: self._search(text, serial) and False)

    def _search(self, text, serial):
        if serial != self.search_serial:
            return False

        def work():
            try:
                found, problem = sky_store.search(text), None
            except (OSError, ValueError) as error:
                found, problem = [], "Sky couldn't reach the weather service. Check your internet connection." \
                    if isinstance(error, OSError) else str(error)
            GLib.idle_add(lambda: serial == self.search_serial and self._show_results(found, problem, text))

        threading.Thread(target=work, daemon=True).start()
        return False

    def _show_results(self, found, problem, text=""):
        for row in self.results.get_children():
            self.results.remove(row)
        for place in found:
            row = Gtk.ListBoxRow()
            row.place = place
            line = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
            line.pack_start(Gtk.Label(label=place.name, xalign=0), False, False, 0)
            if place.where:
                where = Gtk.Label(label=place.where, xalign=0)
                where.get_style_context().add_class("dim-label")
                line.pack_start(where, False, False, 0)
            row.add(line)
            self.results.add(row)
        self.results.show_all()
        self.results_scroller.set_visible(bool(found))
        if problem:
            self.search_note.set_text(problem)
            self.search_note.show()
        elif text and not found:
            self.search_note.set_text(f"No places called “{text}” were found.")
            self.search_note.show()
        else:
            self.search_note.hide()
        first = self.results.get_row_at_index(0)
        if first:
            self.results.select_row(first)
        return False

    def _search_activate(self, _entry):
        row = self.results.get_selected_row() or self.results.get_row_at_index(0)
        if row is not None:
            self._chose(row.place)

    def _chose(self, place):
        self.add_button.set_active(False)
        self.settings.add(place)
        self.load_places()
        self.refresh()

    def _offer_home(self):
        city = sky_store.home_city()
        self.settings.asked_home = True
        self.settings.save()
        if not city:
            self.add_button.set_active(True)
            return

        def work():
            try:
                found = sky_store.search(city, count=1)
            except (OSError, ValueError):
                found = []
            GLib.idle_add(lambda: self._home_found(found))

        threading.Thread(target=work, daemon=True).start()

    def _home_found(self, found):
        if found and not self.settings.places:
            self._chose(found[0])
        elif not self.settings.places:
            self.add_button.set_active(True)
        return False

    # -- the list of places --

    def load_places(self):
        chosen = self.settings.chosen
        for row in self.list.get_children():
            self.list.remove(row)
        for place in self.settings.places:
            row = Gtk.ListBoxRow()
            row.place = place
            grid = Gtk.Grid(column_spacing=8)
            name = Gtk.Label(label=place.name, xalign=0, hexpand=True, ellipsize=Pango.EllipsizeMode.END)
            name.get_style_context().add_class("sky-place")
            row.words = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
            row.words.get_style_context().add_class("sky-small")
            row.temp = Gtk.Label(xalign=1)
            row.temp.get_style_context().add_class("sky-place-temp")
            row.range = Gtk.Label(xalign=1)
            row.range.get_style_context().add_class("sky-small")
            grid.attach(name, 0, 0, 1, 1)
            grid.attach(row.words, 0, 1, 1, 1)
            grid.attach(row.temp, 1, 0, 1, 1)
            grid.attach(row.range, 1, 1, 1, 1)
            row.add(grid)
            self.list.add(row)
            self._fill_row(row)
            if place.key == chosen:
                self.list.select_row(row)
        self.list.show_all()
        if self.list.get_selected_row() is None and self.list.get_row_at_index(0):
            self.list.select_row(self.list.get_row_at_index(0))
        if not self.settings.places:
            self._show_empty()

    def _fill_row(self, row):
        forecast = self.forecasts.get(row.place.key) or sky_store.cached(row.place, self.settings.unit)
        if forecast is None:
            row.words.set_text(row.place.where or "")
            row.temp.set_text("")
            row.range.set_text("")
            return
        self.forecasts.setdefault(row.place.key, forecast)
        row.words.set_text(forecast.words)
        row.temp.set_text(degrees(forecast.temperature))
        row.range.set_text(f"H:{degrees(forecast.today['high'])} L:{degrees(forecast.today['low'])}")

    def _row_selected(self, _list, row):
        if row is None:
            return
        self.settings.chosen = row.place.key
        self.settings.save()
        self.show_place(row.place)

    def chosen_place(self):
        row = self.list.get_selected_row()
        return row.place if row else None

    def _list_pressed(self, _list, event):
        if event.button != 3:
            return False
        row = self.list.get_row_at_y(int(event.y))
        if row is None:
            return False
        self.list.select_row(row)
        menu = Gtk.Menu()
        for label, callback in (("Move Up", lambda: self._move(-1)), ("Move Down", lambda: self._move(1)),
                                (None, None), ("Remove", self.remove_chosen)):
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if callback:
                item.connect("activate", lambda _i, c=callback: c())
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self.list, None)
        menu.popup_at_pointer(event)
        return True

    def _move(self, step):
        place = self.chosen_place()
        if place is None:
            return
        index = [p.key for p in self.settings.places].index(place.key)
        self.settings.move(place.key, index + step)
        self.load_places()

    def remove_chosen(self):
        place = self.chosen_place()
        if place is None:
            return
        self.settings.remove(place.key)
        self.forecasts.pop(place.key, None)
        self.load_places()

    # -- the weather --

    def refresh(self, force=False):
        for place in self.settings.places:
            have = self.forecasts.get(place.key) or sky_store.cached(place, self.settings.unit)
            if have is not None:
                self.forecasts[place.key] = have
            if force or have is None or have.stale():
                self._ask(place)
        self._update_spinner()

    def _ask(self, place):
        if place.key in self.asking:
            return
        self.asking.add(place.key)
        unit = self.settings.unit

        def work():
            try:
                result, problem = sky_store.forecast(place, unit), None
            except OSError:
                result, problem = None, "Sky couldn't reach the weather service. Check your internet connection."
            except (ValueError, KeyError, TypeError, IndexError):
                result, problem = None, "The weather service sent something Sky didn't understand."
            GLib.idle_add(lambda: self._answered(place, unit, result, problem))

        threading.Thread(target=work, daemon=True).start()

    def _answered(self, place, unit, result, problem):
        self.asking.discard(place.key)
        self._update_spinner()
        if unit != self.settings.unit:
            return False
        if result is not None:
            self.forecasts[place.key] = result
            self.problems.pop(place.key, None)
        else:
            self.problems[place.key] = problem
        for row in self.list.get_children():
            if row.place.key == place.key:
                self._fill_row(row)
        current = self.chosen_place()
        if current is not None and current.key == place.key:
            self.show_place(current)
        return False

    def _update_spinner(self):
        if self.asking:
            self.spinner.start()
        else:
            self.spinner.stop()

    def _tick(self):
        self.refresh()
        return True

    def set_unit(self, unit):
        if unit == self.settings.unit:
            return
        self.settings.unit = unit
        self.settings.save()
        self.forecasts.clear()
        self.load_places()
        self.refresh()
        place = self.chosen_place()
        if place:
            self.show_place(place)

    # -- the chosen place --

    def _clear_main(self):
        for child in self.main.get_children():
            self.main.remove(child)

    def _show_empty(self):
        self._clear_main()
        self.backdrop.set_look("clear", True)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        box.set_margin_top(160)
        title = Gtk.Label(label="Add a Place")
        title.get_style_context().add_class("sky-empty-title")
        box.pack_start(title, False, False, 0)
        box.pack_start(Gtk.Label(label="Click + and type the name of a city or town to see its weather.",
                                 wrap=True, justify=Gtk.Justification.CENTER), False, False, 0)
        self.main.pack_start(box, False, False, 0)
        self.main.show_all()

    def show_place(self, place):
        self._clear_main()
        forecast = self.forecasts.get(place.key)
        problem = self.problems.get(place.key)
        if forecast is None:
            self.backdrop.set_look("cloudy", True)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            box.set_margin_top(140)
            name = Gtk.Label(label=place.name)
            name.get_style_context().add_class("sky-name")
            box.pack_start(name, False, False, 0)
            box.pack_start(Gtk.Label(label=problem or "Getting the weather…", wrap=True,
                                     justify=Gtk.Justification.CENTER), False, False, 0)
            self.main.pack_start(box, False, False, 0)
            self.main.show_all()
            return
        self.backdrop.set_look(forecast.look, forecast.is_day)
        today = forecast.today

        top = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0, halign=Gtk.Align.CENTER)
        name = Gtk.Label(label=place.name)
        name.get_style_context().add_class("sky-name")
        top.pack_start(name, False, False, 0)
        now = Gtk.Label(label=degrees(forecast.temperature))
        now.get_style_context().add_class("sky-now")
        top.pack_start(now, False, False, 0)
        words = Gtk.Label(label=forecast.words)
        words.get_style_context().add_class("sky-words")
        top.pack_start(words, False, False, 0)
        top.pack_start(Gtk.Label(label=f"H:{degrees(today['high'])}   L:{degrees(today['low'])}"),
                       False, False, 0)
        self.main.pack_start(top, False, False, 6)

        self.main.pack_start(self._hours_panel(forecast), False, False, 0)
        self.main.pack_start(self._days_panel(forecast), False, False, 0)
        self.main.pack_start(self._facts_panel(forecast, today), False, False, 0)

        note = []
        if problem:
            note.append(problem)
        fetched = datetime.datetime.fromtimestamp(forecast.fetched) if forecast.fetched else None
        if fetched:
            note.append(f"Updated {time_words(fetched)}.")
        note.append("Weather data by Open-Meteo.com.")
        last = Gtk.Label(label=" ".join(note), wrap=True, justify=Gtk.Justification.CENTER)
        last.get_style_context().add_class("sky-note")
        self.main.pack_start(last, False, False, 4)
        self.main.show_all()

    def _panel(self, heading, icon):
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        panel.get_style_context().add_class("sky-panel")
        line = Gtk.Box(spacing=6)
        line.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
        label = Gtk.Label(label=heading.upper(), xalign=0)
        label.get_style_context().add_class("sky-heading")
        line.pack_start(label, False, False, 0)
        panel.pack_start(line, False, False, 0)
        panel.pack_start(Gtk.Separator(), False, False, 0)
        return panel

    def _hours_panel(self, forecast):
        panel = self._panel("Next 24 hours", "document-open-recent-symbolic")
        scroller = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_propagate_natural_height(True)
        style.sideways_wheel(scroller)
        row = Gtk.Box(spacing=4)
        items = [(h["time"], "hour", h) for h in forecast.next_hours()]
        items += [(when, "sun", words) for when, words in forecast.sun_events()]
        items.sort(key=lambda i: i[0])
        first = True
        for when, kind, what in items:
            cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            cell.set_size_request(58 if kind == "hour" else 70, -1)
            if kind == "hour":
                label = "Now" if first else clock_words(when)
                first = False
                temp = forecast.temperature if label == "Now" else what["temperature"]
                code = forecast.code if label == "Now" else what["code"]
                day = forecast.is_day if label == "Now" else what["is_day"]
                icon = sky_store.describe(code, day)[1] + "-symbolic"
                below = degrees(temp)
                rain = what.get("rain")
            else:
                label = time_words(when)
                icon = "daytime-sunrise-symbolic" if what == "Sunrise" else "daytime-sunset-symbolic"
                below = what
                rain = None
            top = Gtk.Label(label=label)
            top.get_style_context().add_class("sky-hour-time")
            cell.pack_start(top, False, False, 0)
            cell.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            chance = Gtk.Label(label=f"{rain}%" if rain and rain >= 30 else "")
            chance.get_style_context().add_class("sky-rain")
            cell.pack_start(chance, False, False, 0)
            bottom = Gtk.Label(label=below)
            bottom.get_style_context().add_class("sky-hour-temp" if kind == "hour" else "sky-small")
            cell.pack_start(bottom, False, False, 0)
            row.pack_start(cell, False, False, 0)
        scroller.add(row)
        panel.pack_start(scroller, False, False, 0)
        return panel

    def _days_panel(self, forecast):
        panel = self._panel(f"{len(forecast.days)}-day forecast", "x-office-calendar-symbolic")
        week_low = min(d["low"] for d in forecast.days)
        week_high = max(d["high"] for d in forecast.days)
        grid = Gtk.Grid(column_spacing=14, row_spacing=10)
        today = forecast.time.date()
        for i, day in enumerate(forecast.days):
            name = Gtk.Label(label=day_words(day["date"], today), xalign=0)
            name.set_size_request(60, -1)
            name.get_style_context().add_class("sky-day")
            grid.attach(name, 0, i, 1, 1)
            icons = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            icons.set_size_request(40, -1)
            icons.pack_start(Gtk.Image.new_from_icon_name(sky_store.describe(day["code"])[1] + "-symbolic",
                                                          Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            if day["rain"] and day["rain"] >= 30:
                chance = Gtk.Label(label=f"{day['rain']}%")
                chance.get_style_context().add_class("sky-rain")
                icons.pack_start(chance, False, False, 0)
            icons.set_tooltip_text(sky_store.describe(day["code"])[0])
            grid.attach(icons, 1, i, 1, 1)
            low = Gtk.Label(label=degrees(day["low"]), xalign=1)
            low.set_size_request(40, -1)
            low.get_style_context().add_class("sky-low")
            grid.attach(low, 2, i, 1, 1)
            bar = RangeBar(day["low"], day["high"], week_low, week_high,
                           forecast.temperature if day["date"] == today else None)
            bar.unit = forecast.unit
            grid.attach(bar, 3, i, 1, 1)
            high = Gtk.Label(label=degrees(day["high"]), xalign=1)
            high.set_size_request(40, -1)
            grid.attach(high, 4, i, 1, 1)
        panel.pack_start(grid, False, False, 0)
        return panel

    def _facts_panel(self, forecast, today):
        grid = Gtk.Grid(column_spacing=12, row_spacing=12, column_homogeneous=True)
        speed = "mph" if forecast.unit == "F" else "km/h"
        facts = [
            ("Feels Like", "weather-few-clouds-symbolic", degrees(forecast.feels_like),
             "Wind makes it feel colder." if forecast.feels_like is not None
             and forecast.feels_like < forecast.temperature - 2 else
             "Humidity makes it feel warmer." if forecast.feels_like is not None
             and forecast.feels_like > forecast.temperature + 2 else "Close to the actual temperature."),
            ("Wind", "weather-windy-symbolic",
             f"{round(forecast.wind)} {speed}" if forecast.wind is not None else "–", ""),
            ("Humidity", "weather-showers-scattered-symbolic",
             f"{forecast.humidity}%" if forecast.humidity is not None else "–", ""),
        ]
        # The sun: the next sunrise or sunset.
        events = forecast.sun_events(36)
        if events:
            when, words = events[0]
            facts.append((words, "daytime-sunrise-symbolic" if words == "Sunrise" else "daytime-sunset-symbolic",
                          time_words(when), ""))
        for i, (title, icon, value, note) in enumerate(facts):
            panel = self._panel(title, icon)
            label = Gtk.Label(label=value, xalign=0)
            label.get_style_context().add_class("sky-fact-value")
            panel.pack_start(label, False, False, 0)
            if note:
                small = Gtk.Label(label=note, xalign=0, wrap=True, max_width_chars=22)
                small.get_style_context().add_class("sky-note")
                panel.pack_start(small, False, False, 0)
            grid.attach(panel, i % 2, i // 2, 1, 1)
        return grid

    def _key(self, _w, event):
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        if not mods and event.keyval in (Gdk.KEY_Delete, Gdk.KEY_BackSpace) and self.list.has_focus():
            self.remove_chosen()
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("Add a Place…", "win.add-place", "<Ctrl>n")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Remove Place", "win.remove", "<Ctrl>BackSpace")]]),
        ("_View", [[("Fahrenheit", "app.fahrenheit", None), ("Celsius", "app.celsius", None)],
                   [("Refresh", "win.refresh", "<Ctrl>r")]]),
    ])


class Sky(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None
        self.settings = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.settings = sky_store.Settings()
        menus.add_actions(self, {"quit": self.quit_all})
        self.fahrenheit = menus.add_toggle(self, "fahrenheit", self.settings.unit == "F",
                                           lambda on: self._unit("F" if on else "C"))
        self.celsius = menus.add_toggle(self, "celsius", self.settings.unit == "C",
                                        lambda on: self._unit("C" if on else "F"))
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.add-place", "<Control>n"), ("win.close", "<Control>w"),
                             ("win.refresh", "<Control>r"), ("win.remove", "<Control>BackSpace")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def _unit(self, unit):
        self.fahrenheit.set_state(GLib.Variant("b", unit == "F"))
        self.celsius.set_state(GLib.Variant("b", unit == "C"))
        if self.window:
            self.window.set_unit(unit)
        else:
            self.settings.unit = unit
            self.settings.save()

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()

    def quit_all(self):
        for window in self.get_windows():
            window.close()


def main():
    GLib.set_prgname("freemac-sky")
    return Sky().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
