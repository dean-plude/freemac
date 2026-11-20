# SPDX-License-Identifier: GPL-3.0-or-later
"""Glyph: emoji and symbols, a key press away.

Control-⌘-Space, or Edit > Emoji & Symbols in any app, opens a small panel
over the app in front. Type to search by name or keyword, or browse by group;
a click or Enter types the emoji into the app in front (through wtype, which
uses Wayland's virtual keyboard) and remembers it under Frequently Used.
Without wtype the emoji is copied instead, ready to paste with ⌘V.

Like Seek it starts with the session (freemac-glyph --background) and stays
running with its panel hidden, so the shortcut opens it at once.

The emoji's names, keywords and groups come from GTK's own emoji data (from
Unicode's CLDR), read at run time and kept in ~/.cache/freemac as JSON, which
loads far faster. The emoji are drawn by the emoji font.
Original freemac code.
"""
import json
import os
import shutil
import subprocess
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import style  # noqa: E402
from .ready_panel import ReadyPanel  # noqa: E402

APP_ID = "org.freemac.Glyph"
RECENT_FILE = os.path.join(GLib.get_user_state_dir(), "freemac", "emoji-recent.json")
CACHE_DIR = os.path.join(GLib.get_user_cache_dir(), "freemac")
RECENT_KEEP = 24
MAX_RESULTS = 240
COLUMNS = 9
SKIN_TONES = 2   # GTK's group of skin-tone swatches, which aren't emoji to type

# GTK's group numbers, with the emoji that stands for each group on its tab.
GROUPS = ((0, "😀", "Smileys & Emotion"), (1, "👋", "People & Body"), (3, "🐻", "Animals & Nature"),
          (4, "🍔", "Food & Drink"), (5, "✈️", "Travel & Places"), (6, "⚽", "Activities"),
          (7, "💡", "Objects"), (8, "🔣", "Symbols"), (9, "🏁", "Flags"))
RECENT = -1



class Emoji:
    __slots__ = ("text", "name", "keywords", "group")

    def __init__(self, text, name, keywords, group):
        self.text, self.name, self.keywords, self.group = text, name, keywords, group

    def matches(self, words):
        hay = " ".join([self.name] + list(self.keywords)).lower()
        return all(any(part.startswith(w) for part in hay.split()) or w in self.name.lower()
                   for w in words)


def emoji_text(codes):
    """The emoji's characters: GTK's data marks with 0 where a skin tone may
    go, and we type the plain (yellow) form. A lone character gets the
    emoji-style selector, so it never shows as a black-and-white symbol."""
    chars = [chr(c) for c in codes if c]
    if len(chars) == 1 and chars[0] != "️":
        chars.append("️")
    return "".join(chars)


def cache_path():
    version = f"{Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}"
    return os.path.join(CACHE_DIR, f"emoji-gtk-{version}.json")


def load_all():
    """Every emoji GTK knows, in its order, or [] when its data isn't there.
    Read from the cache when there is one (GTK's own data takes seconds to
    unpack in Python), and the cache written when there isn't."""
    path = cache_path()
    try:
        with open(path) as f:
            return [Emoji(*row) for row in json.load(f)]
    except (OSError, ValueError, TypeError):
        pass
    found = load_from_gtk()
    if found:
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(path + ".new", "w") as f:
                json.dump([[e.text, e.name, list(e.keywords), e.group] for e in found], f, ensure_ascii=False)
            os.replace(path + ".new", path)
        except OSError:
            pass
    return found


def load_from_gtk():
    for path in ("/org/gtk/libgtk/emoji/en.data", "/org/gtk/libgtk/emoji/emoji.data"):
        try:
            data = Gio.resources_lookup_data(path, Gio.ResourceLookupFlags.NONE)
        except GLib.Error:
            continue
        table = GLib.Variant.new_from_bytes(GLib.VariantType.new("a(ausasu)"), data, True)
        found = []
        for i in range(table.n_children()):
            codes, name, keywords, group = table.get_child_value(i).unpack()
            if group != SKIN_TONES:
                found.append(Emoji(emoji_text(codes), name, keywords, group))
        return found
    return []


def search(emoji, text):
    words = text.lower().split()
    if not words:
        return []
    found = [e for e in emoji if e.matches(words)]

    # Emoji whose own name has the words come before those that only have
    # them as keywords, so "rocket" puts the rocket ahead of the astronauts.
    def rank(e):
        name = e.name.lower().split()
        return (0 if all(any(part.startswith(w) for part in name) for w in words) else 1)
    found.sort(key=rank)   # sort is stable, so the usual order stays within each
    return found[:MAX_RESULTS]


def load_recent():
    try:
        with open(RECENT_FILE) as f:
            items = json.load(f)
        return [i for i in items if isinstance(i, str)][:RECENT_KEEP]
    except (OSError, ValueError):
        return []


def remember(text, recent=None):
    """Put text first in Frequently Used and save it."""
    recent = [r for r in (load_recent() if recent is None else recent) if r != text]
    recent.insert(0, text)
    recent = recent[:RECENT_KEEP]
    try:
        os.makedirs(os.path.dirname(RECENT_FILE), exist_ok=True)
        with open(RECENT_FILE + ".new", "w") as f:
            json.dump(recent, f)
        os.replace(RECENT_FILE + ".new", RECENT_FILE)
    except OSError:
        pass
    return recent


def type_text(text):
    """Type text into the app in front; copy it instead when that can't be
    done. True when it was typed."""
    if shutil.which("wtype"):
        try:
            if subprocess.run(["wtype", "--", text], timeout=5).returncode == 0:
                return True
        except (OSError, subprocess.TimeoutExpired):
            pass
    if shutil.which("wl-copy"):
        subprocess.run(["wl-copy", "--", text], timeout=5)
        if shutil.which("notify-send"):
            subprocess.run(["notify-send", "-a", "Emoji & Symbols", "-i", "face-smile",
                            f"Copied {text}", "Paste it with ⌘V."], timeout=5)
    return False


class GlyphWindow(ReadyPanel, Gtk.Window):
    def __init__(self, app):
        super().__init__(application=app, title="Emoji & Symbols")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-glyph")
        # Like Seek, the panel sits on a see-through layer over the whole
        # screen, so a click anywhere else closes it.
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("button-press-event", self._pressed)
        self.connect("key-press-event", self._key)
        self.connect("delete-event", lambda *_: (self.close_panel(), True)[1])

        self.emoji = load_all()
        self.recent = load_recent()
        self.shown = []
        self.chosen_text = None

        box = self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                                 halign=Gtk.Align.CENTER, valign=Gtk.Align.START, margin_top=140)
        box.get_style_context().add_class("glyph")
        box.set_size_request(COLUMNS * 40 + 24, -1)
        self.add(box)

        self.entry = Gtk.SearchEntry(placeholder_text="Search")
        self.entry.connect("search-changed", lambda *_: self.refresh())
        self.entry.connect("activate", lambda *_: self.choose_first())
        box.pack_start(self.entry, False, False, 0)

        tabs = Gtk.Box(spacing=2, homogeneous=True)
        tabs.get_style_context().add_class("glyph-tabs")
        self.tabs = {}
        first = None
        for group, face, label in ((RECENT, "🕘", "Frequently Used"),) + GROUPS:
            button = Gtk.RadioButton.new_from_widget(first)
            button.set_mode(False)
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.set_label(face)
            button.set_tooltip_text(label)
            button.connect("toggled", self._tab_toggled, group)
            first = first or button
            tabs.pack_start(button, True, True, 0)
            self.tabs[group] = button
        box.pack_start(tabs, False, False, 0)

        self.heading = Gtk.Label(xalign=0)
        self.heading.get_style_context().add_class("glyph-heading")
        box.pack_start(self.heading, False, False, 0)

        self.flow = Gtk.FlowBox(valign=Gtk.Align.START, homogeneous=True,
                                min_children_per_line=COLUMNS, max_children_per_line=COLUMNS,
                                selection_mode=Gtk.SelectionMode.SINGLE, activate_on_single_click=True,
                                column_spacing=2, row_spacing=2)
        self.flow.connect("child-activated", lambda _f, child: self.choose(child.get_index()))
        self.flow.connect("selected-children-changed", lambda *_: self._show_name())
        # The name of the emoji under the pointer shows below, as on a Mac.
        self.flow.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.flow.connect("motion-notify-event", self._hover)
        self.flow.connect("leave-notify-event", lambda *_: self._show_name())
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_size_request(-1, 6 * 40)
        scroller.add(self.flow)
        self.scroller = scroller
        box.pack_start(scroller, True, True, 0)

        self.name = Gtk.Label(xalign=0, ellipsize=3)
        self.name.get_style_context().add_class("glyph-name")
        box.pack_start(self.name, False, False, 0)

        self.group = None
        self.reset()

    def reset(self):
        """Ready for next time: search cleared, on Frequently Used when
        there is anything in it."""
        self.recent = load_recent()
        group = RECENT if self.recent else GROUPS[0][0]
        self.entry.set_text("")
        if self.group == group:
            self.refresh()
        else:
            self.tabs[group].set_active(True)   # refreshes through toggled
            if self.group != group:
                self.group = group
                self.refresh()

    def open_panel(self):
        self.show_ready()
        self.entry.grab_focus()

    def close_panel(self):
        self.hide_ready()
        self.reset()

    # --- what's shown ----------------------------------------------------
    def _tab_toggled(self, button, group):
        if button.get_active():
            self.group = group
            if self.entry.get_text():
                self.entry.set_text("")   # refreshes through search-changed
            else:
                self.refresh()

    def refresh(self):
        text = self.entry.get_text().strip()
        if text:
            items = [(e.text, e.name) for e in search(self.emoji, text)]
            heading = "Results" if items else "No emoji found"
        elif self.group == RECENT:
            names = {e.text: e.name for e in self.emoji}
            items = [(t, names.get(t, "")) for t in self.recent]
            heading = "Frequently Used" if items else "Emoji you use show up here"
        else:
            items = [(e.text, e.name) for e in self.emoji if e.group == self.group]
            heading = dict((g, label) for g, _f, label in GROUPS).get(self.group, "")
        self.heading.set_text(heading)
        self.shown = items
        for child in self.flow.get_children():
            child.destroy()
        for text, name in items:
            label = Gtk.Label(label=text)
            label.get_style_context().add_class("glyph-emoji")
            self.flow.add(label)
        self.flow.show_all()
        self.scroller.get_vadjustment().set_value(0)
        if items:
            self.flow.select_child(self.flow.get_child_at_index(0))
        self._show_name()

    def _hover(self, _flow, event):
        child = self.flow.get_child_at_pos(int(event.x), int(event.y))
        index = child.get_index() if child else -1
        if 0 <= index < len(self.shown) and self.shown[index][1]:
            self.name.set_text(self.shown[index][1].capitalize())
        return False

    def _show_name(self):
        selected = self.flow.get_selected_children()
        index = selected[0].get_index() if selected else -1
        name = self.shown[index][1] if 0 <= index < len(self.shown) else ""
        self.name.set_text(name.capitalize() if name else " ")

    # --- choosing --------------------------------------------------------
    def choose_first(self):
        selected = self.flow.get_selected_children()
        self.choose(selected[0].get_index() if selected else 0)

    def choose(self, index):
        if not (0 <= index < len(self.shown)):
            return
        self.chosen_text = self.shown[index][0]
        remember(self.chosen_text)
        # Close first, so the app in front has the keyboard again, then type.
        self.close_panel()
        GLib.timeout_add(150, self._type_chosen)

    def _type_chosen(self):
        type_text(self.chosen_text)
        return False

    def _pressed(self, _w, event):
        # A press inside the emoji grid arrives from the grid's own window,
        # with its x and y counted from there, so only a press on the window
        # itself is measured against the panel.
        if event.window != self.get_window():
            return False
        inside = self.box.get_allocation()
        if not (inside.x <= event.x < inside.x + inside.width and inside.y <= event.y < inside.y + inside.height):
            self.close_panel()
        return False

    def _move(self, step):
        count = len(self.shown)
        if not count:
            return
        selected = self.flow.get_selected_children()
        index = selected[0].get_index() if selected else 0
        index = max(0, min(count - 1, index + step))
        child = self.flow.get_child_at_index(index)
        self.flow.select_child(child)
        # Keep the chosen emoji in view.
        alloc = child.get_allocation()
        adj = self.scroller.get_vadjustment()
        if alloc.y < adj.get_value():
            adj.set_value(alloc.y)
        elif alloc.y + alloc.height > adj.get_value() + adj.get_page_size():
            adj.set_value(alloc.y + alloc.height - adj.get_page_size())

    def _key(self, _w, event):
        key = event.keyval
        if key == Gdk.KEY_Escape:
            if self.entry.get_text():
                self.entry.set_text("")
            else:
                self.close_panel()
            return True
        moves = {Gdk.KEY_Left: -1, Gdk.KEY_Right: 1, Gdk.KEY_Up: -COLUMNS, Gdk.KEY_Down: COLUMNS}
        if key in moves and not (key in (Gdk.KEY_Left, Gdk.KEY_Right) and self.entry.get_text()):
            self._move(moves[key])
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.choose_first()
            return True
        if not self.entry.has_focus():
            self.entry.grab_focus_without_selecting()
            return self.entry.event(event)
        return False


class Glyph(Gtk.Application):
    """Stays running with its panel hidden, so Control-⌘-Space opens it at
    once (freemac-glyph asks the running copy over the session bus)."""

    def __init__(self, background=False):
        super().__init__(application_id=APP_ID)
        self.background = background
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()   # the panel's look (.glyph) is in style.py
        self.hold()

    def do_activate(self):
        if self.window is None:
            self.window = GlyphWindow(self)
            self.window.map_ready(self.window.box)
        if self.background:   # started with the session: wait for the shortcut
            self.background = False
            return
        if self.window.is_open:   # Control-⌘-Space again closes it.
            self.window.close_panel()
            return
        self.window.open_panel()


def main(argv=None):
    argv = sys.argv if argv is None else argv
    return Glyph(background="--background" in argv).run(None)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
