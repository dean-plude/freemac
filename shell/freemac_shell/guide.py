# SPDX-License-Identifier: GPL-3.0-or-later
"""Guide: short how-to topics for freemac.

Help in the menu bar and Seek open it at a topic (freemac-guide --topic
NAME); opened from the Dock or F4 it shows the first topic. The topics, on the
left, narrow as you type in the search field. The text is in guide_topics.py.
Original freemac code.
"""
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import menus, style  # noqa: E402
from .guide_topics import TOPICS, matching  # noqa: E402

APP_ID = "org.freemac.Guide"

CSS = b"""
.guide-sidebar { border-right: 1px solid alpha(currentColor, 0.12); }
.guide-title { font-size: 22px; font-weight: bold; }
.guide-text { font-size: 15px; }
"""


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Guide")
        self.set_default_size(780, 520)
        self.set_icon_name("freemac-guide")
        paned = Gtk.Paned()
        self.add(paned)

        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("guide-sidebar")
        side.set_size_request(240, -1)
        self.search = Gtk.SearchEntry(placeholder_text="Search the Guide", margin=8)
        self.search.connect("search-changed", lambda *_: self._narrow())
        self.search.connect("activate", lambda *_: self._first())
        side.pack_start(self.search, False, False, 0)
        self.listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.rows = {}
        for name, (title, _usual, _body) in TOPICS.items():
            row = Gtk.ListBoxRow()
            row.name = name
            row.add(Gtk.Label(label=title, xalign=0, margin_start=12, margin_end=12, margin_top=6,
                              margin_bottom=6, ellipsize=Pango.EllipsizeMode.END))
            self.listbox.add(row)
            self.rows[name] = row
        self.shown = set(TOPICS)
        self.listbox.set_filter_func(lambda row: row.name in self.shown)
        self.listbox.connect("row-selected", lambda _l, row: row is not None and self.show_topic(row.name))
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.listbox)
        side.pack_start(scroll, True, True, 0)
        paned.pack1(side, False, False)

        self.page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=28)
        self.page_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.page_scroll.add(self.page)
        paned.pack2(self.page_scroll, True, False)

        menus.add_actions(self, {"close": self.close, "find": self.search.grab_focus})
        self.connect("key-press-event", self._key)
        paned.show_all()
        self.open_topic(next(iter(TOPICS)))

    def open_topic(self, name):
        """Show a topic and choose it in the list, clearing a search that hides it."""
        if name not in TOPICS:
            return
        if name not in self.shown:
            self.search.set_text("")
            self.shown = set(TOPICS)
            self.listbox.invalidate_filter()
        self.listbox.select_row(self.rows[name])
        self.show_topic(name)

    def show_topic(self, name):
        for child in self.page.get_children():
            self.page.remove(child)
        title, _usual, body = TOPICS[name]
        self.set_title(title)
        heading = Gtk.Label(label=title, xalign=0, wrap=True)
        heading.get_style_context().add_class("guide-title")
        self.page.pack_start(heading, False, False, 0)
        for paragraph in body:
            line = paragraph[2:] if paragraph.startswith("- ") else paragraph
            label = Gtk.Label(label=line, xalign=0, wrap=True, selectable=True, max_width_chars=60)
            label.get_style_context().add_class("guide-text")
            if paragraph.startswith("- "):
                row = Gtk.Box(spacing=8, margin_start=8)
                row.pack_start(Gtk.Label(label="•", yalign=0), False, False, 0)
                row.pack_start(label, True, True, 0)
                self.page.pack_start(row, False, False, 0)
            else:
                self.page.pack_start(label, False, False, 0)
        self.page.show_all()
        self.page_scroll.get_vadjustment().set_value(0)

    def _narrow(self):
        query = self.search.get_text().strip()
        self.shown = set(matching(query)) if query else set(TOPICS)
        self.listbox.invalidate_filter()
        row = self.listbox.get_selected_row()
        if (row is None or row.name not in self.shown) and self.shown:
            self._first()

    def _first(self):
        query = self.search.get_text().strip()
        found = matching(query) if query else list(TOPICS)
        if found:
            self.listbox.select_row(self.rows[found[0]])

    def _key(self, _w, event):
        if event.state & Gdk.ModifierType.CONTROL_MASK:
            key = Gdk.keyval_to_lower(event.keyval)
            if key == Gdk.KEY_w:
                self.close()
                return True
            if key == Gdk.KEY_f:
                self.search.grab_focus()
                return True
        if event.keyval == Gdk.KEY_Escape and self.search.get_text():
            self.search.set_text("")
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Find", "win.find", "<Ctrl>f")]]),
    ])


class Guide(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)

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
        self.set_menubar(menubar())

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        window = self.get_active_window() or Window(self)
        if "--topic" in args and args.index("--topic") + 1 < len(args):
            window.open_topic(args[args.index("--topic") + 1])
        window.present()
        return 0


def main():
    return Guide().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
