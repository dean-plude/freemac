# SPDX-License-Identifier: GPL-3.0-or-later
"""Nudge: reminders, kept on this computer.

On the left, four tiles (Today, Scheduled, All and Flagged) with how many
reminders each holds, then your own lists, each in its colour. On the right,
the chosen list: a round button to tick each reminder off, its title to type
straight into, and a line under it with its due date and notes. Return adds
the next reminder, ⌘N adds one, ⇧⌘N a new list, ⌘⌫ deletes the reminder
you're on, and the ⓘ button beside it sets its notes, due date, priority,
flag and list. A reminder with a due date nudges you then (Beacon shows it).
Each list is one .ics file (reminders_store.py). Original freemac code.
"""
import datetime as dt
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import alert, launcher_badge, menus, spelling, style  # noqa: E402
from . import reminders_store as store  # noqa: E402

APP_ID = "org.freemac.Nudge"
SMART = {   # id: (name, colour, glyph drawn on the tile's circle)
    "today": ("Today", "#2f7bf5", "day"),
    "scheduled": ("Scheduled", "#f04d3e", "calendar"),
    "all": ("All", "#5b5b60", "tray"),
    "flagged": ("Flagged", "#f59a23", "flag"),
}
CSS = b"""
.nudge-side { background: alpha(currentColor, 0.04); }
.nudge-tile { border-radius: 10px; padding: 8px 10px; background: alpha(currentColor, 0.07);
              border: none; box-shadow: none; }
.nudge-tile:checked { background: @theme_selected_bg_color; color: white; }
.nudge-tile-count { font-size: 22px; font-weight: 700; }
.nudge-tile-name { font-weight: 600; color: alpha(currentColor, 0.7); }
.nudge-tile:checked .nudge-tile-name { color: white; }
.nudge-section { font-size: 12px; font-weight: 700; color: alpha(currentColor, 0.5); padding: 10px 14px 4px 14px; }
.nudge-lists row { padding: 5px 10px; border-radius: 7px; }
.nudge-lists row:selected { background: alpha(@theme_fg_color, 0.12); }
.nudge-lists row:selected label { color: @theme_fg_color; }
.nudge-lists row:selected label.nudge-count { color: alpha(@theme_fg_color, 0.5); }
.nudge-count { color: alpha(currentColor, 0.5); }
.nudge-title { font-size: 26px; font-weight: 700; }
.nudge-big-count { font-size: 26px; font-weight: 600; }
.nudge-main, .nudge-items { background: @theme_base_color; }
.nudge-items row { padding: 2px 6px; }
.nudge-items row .nudge-info-button { opacity: 0; padding: 2px; min-height: 0; min-width: 0; }
.nudge-items row:hover .nudge-info-button, .nudge-items row:selected .nudge-info-button { opacity: 1; }
.nudge-items row:selected { background: alpha(@theme_selected_bg_color, 0.12); }
.nudge-items row:selected label, .nudge-items row:selected entry { color: @theme_fg_color; }
.nudge-items row:selected label.nudge-meta { color: alpha(@theme_fg_color, 0.55); }
.nudge-items entry.nudge-name { border: none; box-shadow: none; background: none; padding: 2px 0;
                                min-height: 22px; font-size: 14px; }
.nudge-items .nudge-done entry.nudge-name { color: alpha(currentColor, 0.45); }
.nudge-meta { font-size: 12px; color: alpha(currentColor, 0.55); }
.nudge-overdue { color: #f04d3e; }
.nudge-head { font-size: 15px; font-weight: 700; padding: 14px 6px 4px 6px; }
.nudge-empty { color: alpha(currentColor, 0.4); font-size: 16px; }
.nudge-info entry { min-height: 26px; }
.nudge-add-list { color: alpha(currentColor, 0.65); }
"""


def _rgba(hexcode, alpha=1.0):
    colour = Gdk.RGBA()
    colour.parse(hexcode)
    colour.alpha = alpha
    return colour


def dot(hexcode, size=26, glyph="list"):
    """A filled circle in a colour with a small white glyph, drawn."""
    area = Gtk.DrawingArea()
    area.set_size_request(size, size)
    area.set_valign(Gtk.Align.CENTER)

    def draw(_w, cr):
        c = _rgba(hexcode)
        r = size / 2
        cr.arc(r, r, r, 0, 6.2832)
        cr.set_source_rgba(c.red, c.green, c.blue, 1)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        s = size / 26
        if glyph == "list":
            for i, y in enumerate((8.5, 13, 17.5)):
                cr.arc(8.5 * s, y * s, 1.3 * s, 0, 6.2832)
                cr.fill()
                cr.rectangle(11 * s, (y - 0.9) * s, 8 * s, 1.8 * s)
                cr.fill()
        elif glyph == "flag":
            cr.rectangle(8 * s, 6 * s, 1.8 * s, 14 * s)
            cr.fill()
            cr.move_to(9.8 * s, 6.5 * s)
            cr.line_to(18.5 * s, 9.5 * s)
            cr.line_to(9.8 * s, 12.8 * s)
            cr.close_path()
            cr.fill()
        elif glyph == "tray":
            cr.set_line_width(1.8 * s)
            cr.rectangle(7 * s, 8 * s, 12 * s, 10 * s)
            cr.stroke()
            cr.move_to(7 * s, 13 * s)
            cr.line_to(10.5 * s, 13 * s)
            cr.line_to(11.5 * s, 15 * s)
            cr.line_to(14.5 * s, 15 * s)
            cr.line_to(15.5 * s, 13 * s)
            cr.line_to(19 * s, 13 * s)
            cr.stroke()
        else:   # day, calendar: a little page with the date or a grid
            cr.set_line_width(1.8 * s)
            cr.rectangle(7 * s, 8 * s, 12 * s, 11 * s)
            cr.stroke()
            cr.rectangle(7 * s, 8 * s, 12 * s, 3 * s)
            cr.fill()
            if glyph == "day":
                layout = area.create_pango_layout(str(dt.date.today().day))
                font = Pango.FontDescription("Sans Bold")
                font.set_absolute_size(6.5 * s * Pango.SCALE)
                layout.set_font_description(font)
                w, h = layout.get_pixel_size()
                cr.move_to(13 * s - w / 2, 15.2 * s - h / 2)
                PangoCairo.show_layout(cr, layout)
            else:
                for gx in (9.5, 13, 16.5):
                    cr.arc(gx * s, 15 * s, 0.9 * s, 0, 6.2832)
                    cr.fill()
        return False
    area.connect("draw", draw)
    return area


def info_mark(size=18):
    """A small blue ring with an i in it: the reminder's details."""
    area = Gtk.DrawingArea()
    area.set_size_request(size, size)

    def draw(_w, cr):
        r = size / 2
        cr.set_source_rgb(0.18, 0.48, 0.96)
        cr.set_line_width(1.4)
        cr.arc(r, r, r - 1, 0, 6.2832)
        cr.stroke()
        cr.arc(r, r * 0.55, size / 14, 0, 6.2832)
        cr.fill()
        cr.rectangle(r - size / 18, r * 0.8, size / 9, r * 0.75)
        cr.fill()
        return False
    area.connect("draw", draw)
    return area


class Check(Gtk.DrawingArea):
    """The round button that ticks a reminder off."""

    def __init__(self, hexcode, done, toggled):
        super().__init__()
        self.hex, self.done, self.toggled = hexcode, done, toggled
        self.set_size_request(24, 24)
        self.set_valign(Gtk.Align.START)
        self.set_margin_top(3)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", lambda *_: (self.toggled(), True)[1])
        self.set_tooltip_text("Mark as Completed")

    def _draw(self, _w, cr):
        c = _rgba(self.hex)
        ink = self.get_style_context().get_color(Gtk.StateFlags.NORMAL)
        cr.set_line_width(1.5)
        cr.arc(12, 12, 9, 0, 6.2832)
        if self.done:
            cr.set_source_rgba(c.red, c.green, c.blue, 1)
            cr.stroke()
            cr.arc(12, 12, 6, 0, 6.2832)
            cr.fill()
        else:
            cr.set_source_rgba(ink.red, ink.green, ink.blue, 0.35)
            cr.stroke()
        return False


class Info(Gtk.Popover):
    """A reminder's details: notes, due date, priority, flag and list."""

    def __init__(self, win, reminder, relative_to):
        super().__init__(relative_to=relative_to, position=Gtk.PositionType.LEFT)
        self.win, self.reminder = win, reminder
        self.get_style_context().add_class("nudge-info")
        grid = Gtk.Grid(column_spacing=10, row_spacing=8, margin=14)
        self.add(grid)
        title = Gtk.Label(xalign=0)
        title.set_markup(f"<b>{GLib.markup_escape_text(reminder.title or 'New Reminder')}</b>")
        title.set_ellipsize(Pango.EllipsizeMode.END)
        title.set_max_width_chars(30)
        grid.attach(title, 0, 0, 2, 1)
        self.notes = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR)
        spelling.attach(self.notes)
        self.notes.get_buffer().set_text(reminder.notes)
        frame = Gtk.ScrolledWindow(min_content_height=60, min_content_width=240)
        frame.set_shadow_type(Gtk.ShadowType.IN)
        frame.add(self.notes)
        self._row(grid, 1, "notes", frame)
        self.due = Gtk.Entry(placeholder_text="e.g. tomorrow 5 PM")
        if reminder.due is not None:
            self.due.set_text(self._due_words(reminder))
        self.due.connect("changed", self._check_due)
        self.due.connect("activate", lambda *_: self.popdown())
        self.due_hint = Gtk.Label(xalign=0)
        self.due_hint.get_style_context().add_class("nudge-meta")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        box.pack_start(self.due, False, False, 0)
        box.pack_start(self.due_hint, False, False, 0)
        self._row(grid, 2, "due", box)
        self.priority = Gtk.ComboBoxText()
        for number in (0, 9, 5, 1):
            self.priority.append(str(number), store.PRIORITIES[number])
        self.priority.set_active_id(str(reminder.priority))
        self._row(grid, 3, "priority", self.priority)
        self.flag = Gtk.CheckButton(label="Flagged", active=reminder.flagged)
        self._row(grid, 4, "flag", self.flag)
        self.list_choice = Gtk.ComboBoxText()
        for rlist in win.lists:
            self.list_choice.append(rlist.id, rlist.name)
        self.list_choice.set_active_id(reminder.list_id)
        self._row(grid, 5, "list", self.list_choice)
        self._check_due()
        self.connect("closed", self._closed)
        grid.show_all()

    @staticmethod
    def _due_words(r):
        words = f"{r.due:%Y-%m-%d}"
        if r.due_time:
            hour = r.due.hour % 12 or 12
            words += f" {hour}:{r.due.minute:02d} {'AM' if r.due.hour < 12 else 'PM'}"
        return words

    @staticmethod
    def _row(grid, row, words, widget):
        label = Gtk.Label(label=words + ":", xalign=1, valign=Gtk.Align.START)
        label.get_style_context().add_class("nudge-meta")
        label.set_margin_top(4)
        grid.attach(label, 0, row, 1, 1)
        grid.attach(widget, 1, row, 1, 1)

    def _check_due(self, *_args):
        found = store.parse_due(self.due.get_text())
        if found is None:
            self.due_hint.set_text("Try a day and a time, like Friday 9 AM.")
        elif found[0] is None:
            self.due_hint.set_text("No due date")
        else:
            probe = store.Reminder()
            probe.due, probe.due_time = found
            self.due_hint.set_text(f"{probe.due:%A, %B} {probe.due.day}" + (
                f", {store.due_text(probe).split(', ', 1)[1]}" if probe.due_time else ""))

    def _closed(self, *_args):
        r = self.reminder.copy()
        buffer = self.notes.get_buffer()
        r.notes = buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False).strip()
        found = store.parse_due(self.due.get_text())
        if found is not None:
            r.due, r.due_time = found
        r.priority = int(self.priority.get_active_id() or 0)
        r.flagged = self.flag.get_active()
        r.list_id = self.list_choice.get_active_id() or r.list_id
        self.win.replace(self.reminder, r)


class Row(Gtk.ListBoxRow):
    def __init__(self, win, reminder, hexcode):
        super().__init__()
        self.win, self.reminder = win, reminder
        box = Gtk.Box(spacing=10)
        box.set_margin_start(6)
        box.set_margin_end(6)
        self.add(box)
        box.pack_start(Check(hexcode, reminder.done, lambda: win.toggle_done(reminder)), False, False, 0)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.pack_start(texts, True, True, 0)
        line = Gtk.Box(spacing=4)
        texts.pack_start(line, False, False, 0)
        if reminder.priority:
            marks = Gtk.Label()
            marks.set_markup(f"<span foreground='{hexcode}' weight='bold'>{store.MARKS[reminder.priority]}</span>")
            line.pack_start(marks, False, False, 0)
        self.entry = Gtk.Entry(text=reminder.title, hexpand=True)
        self.entry.get_style_context().add_class("nudge-name")
        self.entry.connect("activate", lambda *_: win.after_return(self))
        self.entry.connect("focus-out-event", lambda *_: (win.commit(self), False)[1])
        self.entry.connect("focus-in-event", lambda *_: (win.listbox.select_row(self), False)[1])
        line.pack_start(self.entry, True, True, 0)
        meta = []
        if win.showing in SMART or win.showing == "search":
            owner = win.list_of(reminder)
            if owner is not None and win.showing != "all":
                meta.append(GLib.markup_escape_text(owner.name))
        if reminder.due is not None:
            words = GLib.markup_escape_text(store.due_text(reminder))
            meta.append(f"<span foreground='#f04d3e'>{words}</span>" if reminder.overdue() else words)
        if reminder.notes:
            meta.append(GLib.markup_escape_text(reminder.notes.splitlines()[0][:80]))
        if meta:
            label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
            label.set_markup("  ·  ".join(meta))
            label.get_style_context().add_class("nudge-meta")
            texts.pack_start(label, False, False, 0)
        if reminder.flagged:
            box.pack_start(dot(SMART["flagged"][1], 18, "flag"), False, False, 0)
        info = Gtk.Button()
        info.add(info_mark())
        info.set_relief(Gtk.ReliefStyle.NONE)
        info.get_style_context().add_class("nudge-info-button")
        info.set_valign(Gtk.Align.START)
        info.set_tooltip_text("Show Info")
        info.connect("clicked", lambda b: win.show_info(self, b))
        box.pack_end(info, False, False, 0)
        if reminder.done:
            self.get_style_context().add_class("nudge-done")


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Nudge")
        self.set_default_size(860, 580)
        self.set_icon_name("freemac-nudge")
        self.lists = store.load()
        self.showing = "today"
        self.show_completed = False
        self.written = 0
        self.focus_uid = None   # the reminder to put the cursor in after a refill
        self.pending_reload = False

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        add = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        add.set_tooltip_text("New Reminder (⌘N)")
        add.connect("clicked", lambda *_: self.new_reminder())
        header.pack_end(add)

        paned = Gtk.Paned()
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("nudge-side")
        side.set_size_request(250, -1)
        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.set_margin_start(10)
        self.search.set_margin_end(10)
        self.search.set_margin_top(10)
        self.search.connect("search-changed", lambda *_: self._searched())
        side.pack_start(self.search, False, False, 0)
        tiles = Gtk.Grid(column_spacing=8, row_spacing=8, column_homogeneous=True, margin=10)
        self.tiles = {}
        for n, (key, (name, colour, glyph)) in enumerate(SMART.items()):
            tile = Gtk.ToggleButton()
            tile.get_style_context().add_class("nudge-tile")
            grid = Gtk.Grid(row_spacing=4)
            grid.attach(dot(colour, 26, glyph), 0, 0, 1, 1)
            count = Gtk.Label(xalign=1, hexpand=True)
            count.get_style_context().add_class("nudge-tile-count")
            grid.attach(count, 1, 0, 1, 1)
            label = Gtk.Label(label=name, xalign=0)
            label.get_style_context().add_class("nudge-tile-name")
            grid.attach(label, 0, 1, 2, 1)
            tile.add(grid)
            tile.count = count
            tile.connect("button-press-event", lambda _t, _e, k=key: (self.show(k), True)[1])
            tiles.attach(tile, n % 2, n // 2, 1, 1)
            self.tiles[key] = tile
        side.pack_start(tiles, False, False, 0)
        section = Gtk.Label(label="My Lists", xalign=0)
        section.get_style_context().add_class("nudge-section")
        side.pack_start(section, False, False, 0)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.side_lists = Gtk.ListBox()
        self.side_lists.get_style_context().add_class("nudge-lists")
        self.side_lists.set_margin_start(6)
        self.side_lists.set_margin_end(6)
        self.side_lists.connect("row-activated", lambda _b, row: self.show(row.rlist.id))
        self.side_lists.connect("button-press-event", self._side_press)
        scroll.add(self.side_lists)
        side.pack_start(scroll, True, True, 0)
        add_list = Gtk.Button()
        add_list.set_relief(Gtk.ReliefStyle.NONE)
        add_list.set_halign(Gtk.Align.START)
        inner = Gtk.Box(spacing=6)
        inner.pack_start(Gtk.Image.new_from_icon_name("list-add-symbolic", Gtk.IconSize.MENU), False, False, 0)
        inner.pack_start(Gtk.Label(label="Add List"), False, False, 0)
        add_list.add(inner)
        add_list.get_style_context().add_class("nudge-add-list")
        add_list.set_margin_start(8)
        add_list.set_margin_bottom(8)
        add_list.connect("clicked", lambda *_: self.new_list())
        side.pack_start(add_list, False, False, 0)
        paned.pack1(side, False, False)

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        main.get_style_context().add_class("nudge-main")
        top = Gtk.Box(spacing=10)
        top.set_margin_start(24)
        top.set_margin_end(24)
        top.set_margin_top(16)
        self.title = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.title.get_style_context().add_class("nudge-title")
        top.pack_start(self.title, True, True, 0)
        self.big_count = Gtk.Label()
        self.big_count.get_style_context().add_class("nudge-big-count")
        top.pack_end(self.big_count, False, False, 0)
        main.pack_start(top, False, False, 0)
        self.main_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.listbox = Gtk.ListBox()
        self.listbox.get_style_context().add_class("nudge-items")
        self.listbox.set_margin_start(16)
        self.listbox.set_margin_end(16)
        self.listbox.set_header_func(self._header)
        self.listbox.set_placeholder(self._empty())
        events = Gtk.EventBox()
        events.add(self.listbox)
        events.connect("button-press-event", self._blank_press)
        self.main_scroll.add(events)
        main.pack_start(self.main_scroll, True, True, 0)
        paned.pack2(main, True, False)
        self.add(paned)

        menus.add_actions(self, {
            "new-reminder": self.new_reminder, "new-list": self.new_list,
            "delete": self.delete_current, "find": self.search.grab_focus,
            "close": self.close, "show-info": self._info_for_current,
            "today": lambda: self.show("today"), "scheduled": lambda: self.show("scheduled"),
            "all": lambda: self.show("all"), "flagged": lambda: self.show("flagged"),
        })
        menus.add_toggle(self, "show-completed", False, self._completed_toggled)
        self.connect("key-press-event", self._key)
        os.makedirs(store.store_dir(), exist_ok=True)
        self.monitor = Gio.File.new_for_path(store.store_dir()).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", self._files_changed)
        self.show_all()
        self.fill_side()
        self.show("today" if any(self._in_today(r) for r in store.every(self.lists)) or not self.lists[0].reminders
                  else self.lists[0].id)
        GLib.timeout_add_seconds(60, self._tick)

    # -- what's in each view ----------------------------------------------
    @staticmethod
    def _in_today(r):
        return not r.done and r.due is not None and r.due.date() <= dt.date.today()

    def list_of(self, reminder):
        return next((l for l in self.lists if l.id == reminder.list_id), None)

    def _items(self, key):
        """(reminders, colour) for a view."""
        everything = store.every(self.lists)
        keep = (lambda r: True) if self.show_completed else (lambda r: not r.done)
        if key == "search":
            words = self.search.get_text().strip()
            return [r for r in everything if r.matches(words)], "#2f7bf5"
        if key == "today":
            found = [r for r in everything if self._in_today(r) or (
                self.show_completed and r.done and r.due is not None and r.due.date() == dt.date.today())]
            return sorted(found, key=lambda r: r.due_at()), SMART["today"][1]
        if key == "scheduled":
            found = [r for r in everything if r.due is not None and keep(r)]
            return sorted(found, key=lambda r: r.due_at()), SMART["scheduled"][1]
        if key == "all":
            return [r for r in everything if keep(r)], SMART["all"][1]
        if key == "flagged":
            return [r for r in everything if r.flagged and keep(r)], SMART["flagged"][1]
        rlist = next((l for l in self.lists if l.id == key), self.lists[0])
        return [r for r in rlist.reminders if keep(r)], rlist.hex

    def _count(self, key):
        saved, self.show_completed = self.show_completed, False
        try:
            return len(self._items(key)[0])
        finally:
            self.show_completed = saved

    # -- the sidebar ------------------------------------------------------
    def fill_side(self):
        for key, tile in self.tiles.items():
            tile.count.set_text(str(self._count(key)))
            tile.set_active(self.showing == key)
        # The Dock icon shows what's due today or late, as on a Mac.
        launcher_badge.set_count("freemac-nudge.desktop", self._count("today"))
        for row in self.side_lists.get_children():
            row.destroy()
        for rlist in self.lists:
            row = Gtk.ListBoxRow()
            row.rlist = rlist
            box = Gtk.Box(spacing=8)
            box.pack_start(dot(rlist.hex, 26, "list"), False, False, 0)
            name = Gtk.Label(label=rlist.name, xalign=0, ellipsize=Pango.EllipsizeMode.END)
            box.pack_start(name, True, True, 0)
            count = Gtk.Label(label=str(len(rlist.open_items())))
            count.get_style_context().add_class("nudge-count")
            box.pack_end(count, False, False, 0)
            row.add(box)
            self.side_lists.add(row)
            if self.showing == rlist.id:
                self.side_lists.select_row(row)
        if self.showing in SMART or self.showing == "search":
            self.side_lists.unselect_all()
        self.side_lists.show_all()

    def show(self, key):
        self.commit_all()
        if key != "search" and self.search.get_text():
            self.search.set_text("")
        self.showing = key
        self.fill_side()
        self.fill()

    def _searched(self):
        if self.search.get_text().strip():
            self.commit_all()
            self.showing = "search"
            self.fill_side()
            self.fill()
        elif self.showing == "search":
            self.show("today")

    # -- the reminders ----------------------------------------------------
    def fill(self):
        for row in self.listbox.get_children():
            row.destroy()
        items, colour = self._items(self.showing)
        if self.showing in SMART:
            name = SMART[self.showing][0]
        elif self.showing == "search":
            name = f"Results for “{self.search.get_text().strip()}”"
        else:
            name = (self.list_of(store.Reminder(list_id=self.showing)) or self.lists[0]).name
        self.title.set_markup(f"<span foreground='{colour}'>{GLib.markup_escape_text(name)}</span>")
        self.big_count.set_markup(f"<span foreground='{colour}'>{len([r for r in items if not r.done and r.title.strip()])}</span>")
        focus_row = None
        for r in items:
            owner = self.list_of(r)
            row = Row(self, r, owner.hex if owner else colour)
            self.listbox.add(row)
            if r.uid == self.focus_uid:
                focus_row = row
        self.listbox.show_all()
        if focus_row is not None:
            self.focus_uid = None
            self.listbox.select_row(focus_row)
            focus_row.entry.grab_focus()
            GLib.idle_add(lambda: (self._scroll_to(focus_row), False)[1])

    def _scroll_to(self, row):
        alloc = row.get_allocation()
        adj = self.main_scroll.get_vadjustment()
        if alloc.y < adj.get_value() or alloc.y + alloc.height > adj.get_value() + adj.get_page_size():
            adj.set_value(max(0, alloc.y - adj.get_page_size() / 3))

    def _header(self, row, before):
        r = row.reminder
        if self.showing == "scheduled":
            day = r.due.date()
            if before is not None and before.reminder.due.date() == day:
                row.set_header(None)
                return
            today = dt.date.today()
            words = ("Past Due" if day < today and not r.done else "Today" if day == today
                     else "Tomorrow" if day == today + dt.timedelta(days=1) else f"{day:%A, %B} {day.day}")
            if day < today and before is not None and before.reminder.due.date() < today:
                row.set_header(None)
                return
        elif self.showing in ("all", "search"):
            if before is not None and before.reminder.list_id == r.list_id:
                row.set_header(None)
                return
            owner = self.list_of(r)
            words = owner.name if owner else ""
        else:
            row.set_header(None)
            return
        label = Gtk.Label(label=words, xalign=0)
        label.get_style_context().add_class("nudge-head")
        if self.showing in ("all", "search") and self.list_of(r):
            label.set_markup(f"<span foreground='{self.list_of(r).hex}'>{GLib.markup_escape_text(words)}</span>")
        row.set_header(label)

    def _empty(self):
        label = Gtk.Label(label="No Reminders", margin=40)
        label.get_style_context().add_class("nudge-empty")
        label.show()
        return label

    def _blank_press(self, _box, event):
        """A click below the last reminder adds a new one, as on a Mac."""
        if event.button != 1:
            return False
        last = self.listbox.get_children()[-1:] if self.listbox.get_children() else []
        if last and event.y < last[0].get_allocation().y + last[0].get_allocation().height:
            return False
        if last and not last[0].reminder.title.strip() and not last[0].entry.get_text().strip():
            last[0].entry.grab_focus()
            return True
        self.new_reminder()
        return True

    def _target_list(self):
        if self.showing not in SMART and self.showing != "search":
            return next((l for l in self.lists if l.id == self.showing), self.lists[0])
        return self.lists[0]

    def new_reminder(self, after=None):
        self.commit_all()
        rlist = self.list_of(after) if after is not None else self._target_list()
        r = store.Reminder("", rlist.id)
        if self.showing in ("today", "scheduled"):
            r.due = dt.datetime.combine(dt.date.today(), dt.time())
        if self.showing == "flagged":
            r.flagged = True
        if after is not None and after in rlist.reminders:
            rlist.reminders.insert(rlist.reminders.index(after) + 1, r)
        else:
            rlist.reminders.append(r)
        if self.showing == "search":
            self.search.set_text("")
            self.showing = rlist.id
        self.focus_uid = r.uid
        self.fill_side()
        self.fill()

    def after_return(self, row):
        """Return in a reminder's title: keep it and start the next one."""
        self.commit(row)
        if row.reminder.title.strip():
            self.new_reminder(after=row.reminder)

    def commit(self, row):
        """Save a title typed into a row; drop a new reminder left empty."""
        r = row.reminder
        rlist = self.list_of(r)
        if rlist is None or r not in rlist.reminders:
            return
        text = row.entry.get_text().strip()
        if not text:
            if not r.title.strip():
                rlist.reminders.remove(r)
                self._save(rlist)
                GLib.idle_add(self._refill_unless_typing)
            else:
                row.entry.set_text(r.title)
            return
        if text != r.title:
            r.title = text
            self._save(rlist)
        if self.pending_reload:
            GLib.idle_add(self.reload)

    def commit_all(self):
        for row in self.listbox.get_children():
            if isinstance(row, Row):
                self.commit(row)

    def _refill_unless_typing(self):
        focus = self.get_focus()
        if not isinstance(focus, Gtk.Entry) or focus is self.search:
            self.fill_side()
            self.fill()
        return False

    def toggle_done(self, reminder):
        rlist = self.list_of(reminder)
        if rlist is None:
            return
        for row in self.listbox.get_children():
            if row.reminder is reminder:
                self.commit(row)
        reminder.done = not reminder.done
        reminder.completed = dt.datetime.now().replace(microsecond=0) if reminder.done else None
        self._save(rlist)
        for row in self.listbox.get_children():
            if row.reminder is reminder:
                for child in row.get_child().get_children():
                    if isinstance(child, Check):
                        child.done = reminder.done
                        child.queue_draw()
                (row.get_style_context().add_class if reminder.done else
                 row.get_style_context().remove_class)("nudge-done")
        self.fill_side()
        # Ticked-off reminders stay a moment, then leave the list.
        GLib.timeout_add(1200, self._refill_unless_typing)

    def replace(self, old, new):
        """Put a changed reminder in its place (another list, if moved)."""
        source, target = self.list_of(old), self.list_of(new)
        if source is None or target is None:
            return
        if source is target:
            source.reminders[source.reminders.index(old)] = new
            self._save(source)
        else:
            source.reminders.remove(old)
            target.reminders.append(new)
            self._save(source)
            self._save(target)
        self.fill_side()
        self.fill()

    def current_row(self):
        focus = self.get_focus()
        for row in self.listbox.get_children():
            if isinstance(row, Row) and (row.entry is focus):
                return row
        return self.listbox.get_selected_row()

    def delete_current(self):
        row = self.current_row()
        if row is None:
            return
        rlist = self.list_of(row.reminder)
        if rlist is not None and row.reminder in rlist.reminders:
            index = self.listbox.get_children().index(row)
            rlist.reminders.remove(row.reminder)
            self._save(rlist)
            self.fill_side()
            self.fill()
            rows = self.listbox.get_children()
            if rows:
                self.listbox.select_row(rows[min(index, len(rows) - 1)])

    def show_info(self, row, widget):
        self.commit(row)
        popover = Info(self, row.reminder, widget)
        popover.popup()

    def _info_for_current(self):
        row = self.current_row()
        if row is not None:
            buttons = [w for w in row.get_child().get_children() if isinstance(w, Gtk.Button)]
            self.show_info(row, buttons[0] if buttons else row)

    def _completed_toggled(self, value):
        self.show_completed = value
        self.fill()

    # -- lists ------------------------------------------------------------
    def new_list(self):
        used = {l.color for l in self.lists}
        colour = next((c for c in store.COLORS if c not in used), "blue")
        rlist = store.ReminderList(self._ask_name("New List", "List name:", "New List") or "", colour)
        if not rlist.name:
            return
        rlist.order = max((l.order for l in self.lists), default=0) + 1
        self.lists.append(rlist)
        self._save(rlist)
        self.show(rlist.id)

    def _ask_name(self, title, words, name):
        dialog = Gtk.Dialog(title=title, transient_for=self, modal=True, use_header_bar=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("OK", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        box = dialog.get_content_area()
        box.set_border_width(14)
        box.set_spacing(8)
        box.pack_start(Gtk.Label(label=words, xalign=0), False, False, 0)
        entry = Gtk.Entry(text=name, activates_default=True)
        box.pack_start(entry, False, False, 0)
        dialog.show_all()
        answer = dialog.run()
        text = entry.get_text().strip()
        dialog.destroy()
        return text if answer == Gtk.ResponseType.OK else None

    def _side_press(self, box, event):
        if event.button != 3:
            return False
        row = box.get_row_at_y(int(event.y))
        if row is None:
            return False
        menu = Gtk.Menu()
        rename = Gtk.MenuItem(label="Rename…")
        rename.connect("activate", lambda *_: self._rename(row.rlist))
        menu.append(rename)
        colours = Gtk.MenuItem(label="Colour")
        sub = Gtk.Menu()
        for name in store.COLORS:
            item = Gtk.CheckMenuItem(label=name.capitalize(), active=row.rlist.color == name)
            item.set_draw_as_radio(True)
            item.connect("activate", lambda _i, n=name: self._recolour(row.rlist, n))
            sub.append(item)
        colours.set_submenu(sub)
        menu.append(colours)
        menu.append(Gtk.SeparatorMenuItem())
        delete = Gtk.MenuItem(label="Delete List…")
        delete.set_sensitive(len(self.lists) > 1)
        delete.connect("activate", lambda *_: self._delete_list(row.rlist))
        menu.append(delete)
        menu.show_all()
        menu.attach_to_widget(box, None)
        menu.popup_at_pointer(event)
        return True

    def _rename(self, rlist):
        name = self._ask_name("Rename List", "List name:", rlist.name)
        if name:
            rlist.name = name
            self._save(rlist)
            self.fill_side()
            self.fill()

    def _recolour(self, rlist, colour):
        rlist.color = colour
        self._save(rlist)
        self.fill_side()
        self.fill()

    def _delete_list(self, rlist):
        count = len(rlist.reminders)
        answer = alert.ask(self, f"Delete “{rlist.name}”?",
                           f"This will delete all {count} reminders in this list." if count else
                           "This list is empty.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Delete", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        self.lists.remove(rlist)
        store.remove(rlist)
        self.show("today" if self.showing == rlist.id else self.showing)

    # -- files ------------------------------------------------------------
    def _save(self, rlist):
        if rlist not in self.lists:
            return
        if not rlist.reminders and not os.path.exists(store.path_of(rlist)) and len(self.lists) == 1:
            pass   # don't make a file for the first, still empty list
        else:
            store.save(rlist)
        self.written = GLib.get_monotonic_time()

    def _files_changed(self, _monitor, _file, _other, kind):
        if kind not in (Gio.FileMonitorEvent.CHANGES_DONE_HINT, Gio.FileMonitorEvent.CREATED,
                        Gio.FileMonitorEvent.DELETED, Gio.FileMonitorEvent.RENAMED,
                        Gio.FileMonitorEvent.MOVED_IN):
            return
        if GLib.get_monotonic_time() - self.written < 1_500_000:
            return   # our own save
        self.reload()

    def reload(self):
        """Read the lists again (another app, or a notice, changed them).
        A title being typed and not yet kept waits until it's kept."""
        focus = self.get_focus()
        row = next((r for r in self.listbox.get_children()
                    if isinstance(r, Row) and r.entry is focus), None)
        if row is not None and row.entry.get_text().strip() != row.reminder.title:
            self.pending_reload = True
            return False
        self.pending_reload = False
        if row is not None:
            self.focus_uid = row.reminder.uid
        self.lists = store.load()
        if self.showing not in SMART and self.showing != "search" and \
                not any(l.id == self.showing for l in self.lists):
            self.showing = "today"
        self.fill_side()
        self.fill()
        return False

    def _tick(self):
        """Today moves on at midnight, and due dates turn red."""
        if not isinstance(self.get_focus(), Gtk.Entry):
            self.fill_side()
            self.fill()
        return True

    def reveal(self, uid):
        """Show a reminder (from a notice): its list, with it chosen."""
        for rlist in self.lists:
            if any(r.uid == uid for r in rlist.reminders):
                self.show(rlist.id)
                for row in self.listbox.get_children():
                    if row.reminder.uid == uid:
                        self.listbox.select_row(row)
                return

    def _key(self, _w, event):
        command = event.state & Gdk.ModifierType.CONTROL_MASK
        shift = event.state & Gdk.ModifierType.SHIFT_MASK
        key = Gdk.keyval_to_lower(event.keyval)
        if command and shift and key == Gdk.KEY_n:
            self.new_list()
            return True
        if command and shift and key == Gdk.KEY_h:
            action = self.lookup_action("show-completed")
            action.change_state(GLib.Variant("b", not self.show_completed))
            return True
        if command and key == Gdk.KEY_n:
            self.new_reminder()
            return True
        if command and key == Gdk.KEY_f:
            self.search.grab_focus()
            return True
        if command and key == Gdk.KEY_w:
            self.close()
            return True
        if command and key == Gdk.KEY_i:
            self._info_for_current()
            return True
        if command and key in (Gdk.KEY_BackSpace, Gdk.KEY_Delete):
            self.delete_current()
            return True
        if command and key in (Gdk.KEY_1, Gdk.KEY_2, Gdk.KEY_3, Gdk.KEY_4):
            self.show(list(SMART)[key - Gdk.KEY_1])
            return True
        if key == Gdk.KEY_Escape and self.get_focus() is self.search:
            self.search.set_text("")
            return True
        if key == Gdk.KEY_Escape and isinstance(self.get_focus(), Gtk.Entry):
            # Esc while typing a title: put the old title back (a new
            # reminder still empty goes away) and stop editing.
            row = self.get_focus().get_ancestor(Row)
            if row is not None:
                if row.reminder.title.strip():
                    row.entry.set_text(row.reminder.title)
                else:
                    row.entry.set_text("")
                self.set_focus(None)
                self.commit(row)
                return True
        typing = isinstance(self.get_focus(), Gtk.Entry)
        if not typing and key in (Gdk.KEY_BackSpace, Gdk.KEY_Delete):
            self.delete_current()
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("New Reminder", "win.new-reminder", "<Ctrl>n"), ("New List", "win.new-list", "<Ctrl><Shift>n")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Delete", "win.delete", "<Ctrl>BackSpace")],
                   [("Find", "win.find", "<Ctrl>f")]]),
        ("_View", [[("Today", "win.today", "<Ctrl>1"), ("Scheduled", "win.scheduled", "<Ctrl>2"),
                    ("All", "win.all", "<Ctrl>3"), ("Flagged", "win.flagged", "<Ctrl>4")],
                   [("Show Completed", "win.show-completed", "<Ctrl><Shift>h"),
                    ("Show Info", "win.show-info", "<Ctrl>i")]]),
    ])


class Nudge(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_open(self, files, _count, _hint):
        """nudge-reminder:<uid> (from a notice) shows that reminder."""
        window = self.get_active_window() or Window(self)
        for f in files:
            uri = f.get_uri()
            if uri.startswith("nudge-reminder:"):
                from urllib.parse import unquote
                window.reveal(unquote(uri.split(":", 1)[1]))
        window.present()

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: GLib.idle_add(self.quit))
        self.add_action(quit_action)
        # Nudge stays open with no window, as a Mac app does; Quit ends it.
        self.hold()
        self.set_menubar(menubar())

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


def main():
    return Nudge().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
