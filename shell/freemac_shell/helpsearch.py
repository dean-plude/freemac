# SPDX-License-Identifier: GPL-3.0-or-later
"""The Help menu: a search field at the top that finds menu items as you type.

As on a Mac, every app has Help at the end of its menu bar. Open it and just
type: the words go into the search field and the menu items that match show
under it, with the menu they're in and their shortcut. The arrow keys move
through them and Return chooses one, which does exactly what the item does
in its own menu. Guide topics that match are listed under the menu items and
open in Guide. Escape, or a click elsewhere, closes it. Original freemac code.
"""
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import guide_topics, style  # noqa: E402

MOST = 12
TOPICS = 4
BAR = 28
ARROW = " ▸ "


def _texts(item):
    """(name, shortcut) of a menu item, whichever way it was drawn."""
    child = item.get_child()
    if isinstance(child, Gtk.Label):
        return child.get_text(), ""
    if isinstance(child, Gtk.Box):
        name, shortcut = "", ""
        for part in child.get_children():
            if not isinstance(part, Gtk.Label):
                continue
            text = part.get_text()
            if part.get_style_context().has_class("dim-label"):
                shortcut = text
            elif text and text != "✓" and not name:
                name = text
        return name, shortcut
    return (item.get_label() or ""), ""


def find(sources, query):
    """Menu items whose names hold every word of the query: (item, path,
    name, shortcut), names that start with the query first."""
    words = query.lower().split()
    if not words:
        return []
    found = []

    def walk(menu, path):
        for item in menu.get_children():
            if not isinstance(item, Gtk.MenuItem) or isinstance(item, Gtk.SeparatorMenuItem):
                continue
            name, shortcut = _texts(item)
            name = name.replace("_", "")
            sub = item.get_submenu()
            if sub is not None:
                walk(sub, path + [name])
                continue
            if not name or not item.get_sensitive():
                continue
            low = name.lower()
            if all(w in low for w in words):
                found.append((not low.startswith(words[0]), len(found), item, path, name, shortcut))

    for title, menu in sources():
        if menu is not None:
            walk(menu, [title])
    found.sort(key=lambda f: (f[0], f[1]))
    return [f[2:] for f in found[:MOST]]


class HelpButton(Gtk.ToggleButton):
    """Help's title in the bar. It opens a panel, not a menu, so it has no
    popup (the bar's menu sliding asks every title for one)."""

    def __init__(self):
        super().__init__(label="Help")

    @staticmethod
    def get_popup():
        return None


class HelpPanel(Gtk.Window):
    """Help, opened under its title in the bar: a search field that has the
    keyboard at once, and the menu items found under it. sources() gives
    (title, menu) for every menu in the bar, as it is now; closed() is
    called when the panel goes away."""

    def __init__(self, sources, closed):
        super().__init__(title="Help")
        self.sources, self.closed, self.found, self.closed_at = sources, closed, [], 0.0
        self.picks = []   # what each row of the list does: a menu item, a Guide topic, or None
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-help")
        # The panel covers the whole screen, see-through but for the menu
        # itself, so a click anywhere else closes it, as a click outside an
        # open menu does on a Mac. (It has the keyboard to itself, so it
        # never hears that another window was clicked.)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        box = self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                                 halign=Gtk.Align.START, valign=Gtk.Align.START)
        box.get_style_context().add_class("menu")
        box.get_style_context().add_class("help-panel")
        self.add(box)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("button-press-event", self._pressed)
        row = Gtk.Box(spacing=8)
        row.pack_start(Gtk.Label(label="Search"), False, False, 4)
        self.entry = Gtk.SearchEntry(placeholder_text="Type to find a menu item or topic", width_chars=28)
        self.entry.connect("search-changed", lambda *_: self._fill())
        self.entry.connect("activate", lambda *_: self._run(self.list.get_selected_row()))
        row.pack_start(self.entry, True, True, 0)
        box.pack_start(row, False, False, 0)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.list.connect("row-activated", lambda _l, r: self._run(r))
        box.pack_start(self.list, False, False, 0)
        self.connect("key-press-event", self._key)
        self.connect("focus-out-event", lambda *_: self.close_panel())

    def open_at(self, x):
        self.box.set_margin_start(max(0, x))
        self.box.set_margin_top(BAR + 2)
        self.entry.set_text("")
        self._fill()
        self.show_all()
        self.list.hide()
        self.entry.grab_focus()

    def close_panel(self):
        if self.get_visible():
            self.closed_at = time.monotonic()
            self.hide()
            self.closed()
        return False

    def _fill(self):
        for child in self.list.get_children():
            self.list.remove(child)
        query = self.entry.get_text()
        self.found = find(self.sources, query)
        topics = guide_topics.matching(query)[:TOPICS]
        self.picks = []
        if self.found and topics:
            self._heading("Menu Items")
        for original, path, name, shortcut in self.found:
            line = Gtk.Box(spacing=24)
            where = Gtk.Label(label=ARROW.join(path) + ARROW, xalign=0)
            where.get_style_context().add_class("dim-label")
            names = Gtk.Box()
            names.pack_start(where, False, False, 0)
            names.pack_start(Gtk.Label(label=name, xalign=0), False, False, 0)
            line.pack_start(names, True, True, 0)
            keys = Gtk.Label(label=shortcut, xalign=1)
            keys.get_style_context().add_class("dim-label")
            line.pack_end(keys, False, False, 0)
            self._add(line, ("item", original))
        if topics:
            self._heading("Help Topics")
        for name in topics:
            line = Gtk.Box(spacing=8)
            line.pack_start(Gtk.Image.new_from_icon_name("freemac-guide", Gtk.IconSize.MENU), False, False, 0)
            line.pack_start(Gtk.Label(label=guide_topics.TOPICS[name][0], xalign=0), True, True, 0)
            self._add(line, ("topic", name))
        if query and not self.found and not topics:
            none = Gtk.Label(label="No menu items or topics match", xalign=0)
            none.get_style_context().add_class("dim-label")
            self._add(none, None)
        self.list.show_all()
        self.list.set_visible(bool(query))
        first = next((i for i, pick in enumerate(self.picks) if pick), None)
        if first is not None:
            self.list.select_row(self.list.get_row_at_index(first))

    def _heading(self, text):
        label = Gtk.Label(label=text, xalign=0)
        label.get_style_context().add_class("dim-label")
        self._add(label, None)

    def _add(self, widget, pick):
        row = Gtk.ListBoxRow(selectable=pick is not None, activatable=pick is not None)
        row.add(widget)
        self.list.add(row)
        self.picks.append(pick)

    def _pressed(self, _widget, event):
        inside = self.box.get_allocation()
        if not (inside.x <= event.x < inside.x + inside.width and inside.y <= event.y < inside.y + inside.height):
            self.close_panel()
        return False

    def _key(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            return self.close_panel() or True
        if event.keyval in (Gdk.KEY_Down, Gdk.KEY_Up) and any(self.picks):
            row = self.list.get_selected_row()
            step = 1 if event.keyval == Gdk.KEY_Down else -1
            index = row.get_index() if row else -1
            while 0 <= index + step < len(self.picks):
                index += step
                if self.picks[index]:
                    self.list.select_row(self.list.get_row_at_index(index))
                    break
            return True
        return False

    def _run(self, row):
        if row is None or row.get_index() >= len(self.picks) or not self.picks[row.get_index()]:
            return
        kind, what = self.picks[row.get_index()]
        self.close_panel()
        if kind == "topic":
            try:
                GLib.spawn_async(["freemac-guide", "--topic", what], flags=GLib.SpawnFlags.SEARCH_PATH)
            except GLib.Error:
                pass
            return
        # Once the app has the keyboard back, as if chosen in its own menu.
        GLib.timeout_add(120, lambda: what.activate() and False)
