# SPDX-License-Identifier: GPL-3.0-or-later
"""Bosun: shortcuts made of steps, as a Mac's Shortcuts app makes them.

All Shortcuts shows each shortcut as a coloured tile; click its play
button to run it, or open it to change it. A shortcut is a list of steps
from the library on the right (bosun_actions): get some files, make a PDF
of them, show it in Drawer. One that takes the words selected, or files,
can be in the Services menu and in Drawer's menu for files; any shortcut
can have keys, in Dials > Keyboard. The Gallery has ready-made ones.

    freemac-bosun                       the app
    freemac-bosun --run ID              run a shortcut (the selected words,
                                        for one that takes words)
    freemac-bosun --run ID --text T     with these words
    freemac-bosun --run ID -- FILE...   with these files

Original freemac code.
"""
import os
import sys
import threading

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert, bosun_actions, bosun_store, menus, style  # noqa: E402
from .bosun_actions import ACTIONS, CATEGORIES, CATEGORY_ICONS, INPUT  # noqa: E402

APP_ID = "org.freemac.Bosun"
TAKES_NAMES = (("nothing", "Nothing"), ("text", "Selected words"), ("files", "Files"))

CSS = b"""
.bosun-side { background: alpha(currentColor, 0.04); border-right: 1px solid alpha(currentColor, 0.1); }
.bosun-side list { background: transparent; }
.bosun-side row { border-radius: 6px; margin: 0 6px; padding: 5px 8px; background: transparent; }
.bosun-side row:selected { background: @theme_selected_bg_color; color: white; }
.bosun-heading { font-size: 1.6em; font-weight: bold; }
.bosun-dim { opacity: 0.65; }
.bosun-tiles, .bosun-tiles flowboxchild { background: transparent; padding: 0; }
.bosun-tile { border-radius: 14px; padding: 12px; color: white; min-height: 92px; }
.bosun-tile-name { font-weight: bold; font-size: 1.05em; }
.bosun-tile-count { font-size: 0.85em; opacity: 0.85; }
.bosun-tile button { border-radius: 50%; padding: 4px; min-width: 22px; min-height: 22px;
                     background: alpha(white, 0.28); border: none; box-shadow: none; color: white; }
.bosun-tile button:hover { background: alpha(white, 0.45); }
.bosun-blue { background-image: linear-gradient(to bottom, #4f9cf5, #2c6fd6); }
.bosun-teal { background-image: linear-gradient(to bottom, #44c3c0, #1f928f); }
.bosun-green { background-image: linear-gradient(to bottom, #67cf6b, #2f9e3d); }
.bosun-yellow { background-image: linear-gradient(to bottom, #f6c945, #d99a12); }
.bosun-orange { background-image: linear-gradient(to bottom, #fb9e4b, #e0661c); }
.bosun-red { background-image: linear-gradient(to bottom, #f6716a, #d23a3a); }
.bosun-pink { background-image: linear-gradient(to bottom, #f47fb4, #d4457f); }
.bosun-purple { background-image: linear-gradient(to bottom, #b484f0, #7c4fd0); }
.bosun-grey { background-image: linear-gradient(to bottom, #9aa3b0, #66707e); }
.bosun-swatch { border-radius: 50%; min-width: 18px; min-height: 18px; padding: 0; border: 2px solid transparent; }
.bosun-swatch.chosen { border-color: @theme_fg_color; }
.bosun-step { border: 1px solid alpha(currentColor, 0.14); border-radius: 10px;
              background: alpha(currentColor, 0.035); padding: 10px 12px; }
.bosun-step.running { border-color: @theme_selected_bg_color; }
.bosun-step.failed { border-color: #d23a3a; }
.bosun-step-title { font-weight: bold; }
.bosun-step-result { font-size: 0.85em; opacity: 0.7; }
.bosun-step button.flat { padding: 2px; min-width: 20px; min-height: 20px; }
.bosun-library { border-left: 1px solid alpha(currentColor, 0.1); background: alpha(currentColor, 0.03); }
.bosun-library list { background: transparent; }
.bosun-library row { padding: 5px 10px; }
.bosun-section { font-weight: bold; font-size: 0.85em; opacity: 0.55; margin: 10px 10px 2px 10px; }
.bosun-empty { opacity: 0.55; margin: 30px; }
.bosun-chip { border-radius: 9px; color: white; min-width: 34px; min-height: 34px; }
.bosun-card { border: 1px solid alpha(currentColor, 0.12); border-radius: 12px; padding: 12px; }
"""


def first_icon(shortcut):
    for step in shortcut["steps"]:
        entry = ACTIONS.get(step.get("do"))
        if entry:
            return CATEGORY_ICONS[entry[0]]
    return "media-playback-start-symbolic"


def steps_text(count):
    return "No steps" if not count else ("1 step" if count == 1 else f"{count} steps")


# Asking and telling, from any thread ------------------------------------------
class WindowUI:
    """What a step needs from the person, shown over the window (or alone
    when run by freemac-bosun --run). Steps run on a worker thread; these
    wait for the answer on the main one."""

    def __init__(self, parent=None):
        self.parent = parent
        self.stop = threading.Event()

    def _on_main(self, job):
        if threading.current_thread() is threading.main_thread():
            return job()
        done, box = threading.Event(), {}

        def call():
            box["value"] = job()
            done.set()
            return False
        GLib.idle_add(call)
        done.wait()
        return box.get("value")

    def ask(self, prompt, default):
        def job():
            dialog = alert.build(self.parent, prompt, "",
                                 [("Cancel", Gtk.ResponseType.CANCEL), ("Done", Gtk.ResponseType.OK)],
                                 default=Gtk.ResponseType.OK, icon="freemac-bosun")
            body = dialog.get_content_area().get_children()[0]
            entry = Gtk.Entry(text=default or "", activates_default=True, width_chars=28)
            body.pack_start(entry, False, False, 0)
            body.reorder_child(entry, len(body.get_children()) - 2)
            entry.show()
            entry.grab_focus()
            answer = dialog.run()
            text = entry.get_text()
            dialog.destroy()
            return text if answer == Gtk.ResponseType.OK else None
        return self._on_main(job)

    def show(self, text):
        self._on_main(lambda: alert.tell(self.parent, text or "Done", "", icon="freemac-bosun"))

    def stopped(self):
        return self.stop.is_set()


# The app's window -----------------------------------------------------------------
class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Bosun")
        self.set_default_size(1000, 640)
        self.shortcuts = bosun_store.load()
        self.editing = None          # the shortcut open in the editor
        self.cards = []
        self.running = None          # its WindowUI while one runs
        self._save_soon = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Bosun")
        self.set_titlebar(header)
        self.header = header
        self.back = Gtk.Button(label="‹ All Shortcuts", no_show_all=True)
        self.back.connect("clicked", lambda _b: self.show_list())
        header.pack_start(self.back)
        self.add_button = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        self.add_button.set_tooltip_text("New Shortcut")
        self.add_button.connect("clicked", lambda _b: self.new_shortcut())
        header.pack_start(self.add_button)
        self.run_button = Gtk.Button.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON)
        self.run_button.set_tooltip_text("Run")
        self.run_button.set_no_show_all(True)
        self.run_button.connect("clicked", lambda _b: self.run_open())
        self.stop_button = Gtk.Button.new_from_icon_name("media-playback-stop-symbolic", Gtk.IconSize.BUTTON)
        self.stop_button.set_tooltip_text("Stop")
        self.stop_button.set_no_show_all(True)
        self.stop_button.connect("clicked", lambda _b: self.stop())
        header.pack_end(self.run_button)
        header.pack_end(self.stop_button)

        paned = Gtk.Paned()
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("bosun-side")
        side.set_size_request(200, -1)
        self.sidebar = Gtk.ListBox()
        self.sidebar.set_margin_top(10)
        for key, icon, label in (("all", "view-grid-symbolic", "All Shortcuts"),
                                 ("gallery", "starred-symbolic", "Gallery")):
            row = Gtk.ListBoxRow()
            row.key = key
            box = Gtk.Box(spacing=8)
            box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
            box.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
            row.add(box)
            self.sidebar.add(row)
        self.sidebar.connect("row-selected", self._side_chosen)
        side.pack_start(self.sidebar, True, True, 0)
        paned.pack1(side, False, False)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        self.stack.add_named(self._build_list(), "all")
        self.stack.add_named(self._build_gallery(), "gallery")
        self.stack.add_named(self._build_editor(), "editor")
        paned.pack2(self.stack, True, False)
        self.add(paned)

        menus.add_actions(self, {
            "new": self.new_shortcut, "duplicate": self.duplicate, "delete": self.delete,
            "run": self.run_open, "stop": self.stop, "close": self.close,
            "all": lambda: self.sidebar.select_row(self.sidebar.get_row_at_index(0)),
            "gallery": lambda: self.sidebar.select_row(self.sidebar.get_row_at_index(1)),
            "keys": self.open_keys,
        })
        self.show_all()
        self.sidebar.select_row(self.sidebar.get_row_at_index(0))

    # The list of shortcuts ------------------------------------------------------
    def _build_list(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_start(24)
        box.set_margin_end(24)
        box.set_margin_top(18)
        heading = Gtk.Label(label="All Shortcuts", xalign=0)
        heading.get_style_context().add_class("bosun-heading")
        box.pack_start(heading, False, False, 0)
        self.tiles = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=6,
                                 min_children_per_line=2, column_spacing=14, row_spacing=14,
                                 homogeneous=True, valign=Gtk.Align.START)
        self.tiles.get_style_context().add_class("bosun-tiles")
        self.empty = Gtk.Label(label="No shortcuts yet. Click + to make one, or start from the Gallery.",
                               wrap=True, no_show_all=True)
        self.empty.get_style_context().add_class("bosun-empty")
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        inner.pack_start(self.tiles, False, False, 0)
        inner.pack_start(self.empty, False, False, 0)
        inner.set_margin_bottom(18)
        scroll.add(inner)
        box.pack_start(scroll, True, True, 0)
        self.fill_tiles()
        return box

    def fill_tiles(self):
        for child in self.tiles.get_children():
            self.tiles.remove(child)
        for shortcut in self.shortcuts:
            self.tiles.add(self._tile(shortcut))
        self.tiles.show_all()
        self.empty.set_visible(not self.shortcuts)

    def _tile(self, shortcut):
        events = Gtk.EventBox()
        tile = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        tile.set_size_request(170, 96)
        context = tile.get_style_context()
        context.add_class("bosun-tile")
        context.add_class("bosun-" + shortcut["colour"])
        top = Gtk.Box()
        top.pack_start(Gtk.Image.new_from_icon_name(first_icon(shortcut), Gtk.IconSize.LARGE_TOOLBAR),
                       False, False, 0)
        play = Gtk.Button.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.MENU)
        play.set_tooltip_text("Run")
        play.set_valign(Gtk.Align.START)
        play.connect("clicked", lambda _b, s=shortcut: self.run_shortcut(s))
        top.pack_end(play, False, False, 0)
        tile.pack_start(top, False, False, 0)
        name = Gtk.Label(label=shortcut["name"], xalign=0, wrap=True, lines=2,
                         ellipsize=Pango.EllipsizeMode.END, max_width_chars=18)
        name.get_style_context().add_class("bosun-tile-name")
        tile.pack_end(name, False, False, 0)
        count = Gtk.Label(label=steps_text(len(shortcut["steps"])), xalign=0)
        count.get_style_context().add_class("bosun-tile-count")
        tile.pack_end(count, False, False, 0)
        events.add(tile)
        events.set_tooltip_text("Double-click to change it; the play button runs it.")
        events.connect("button-press-event", self._tile_pressed, shortcut)
        return events

    def _tile_pressed(self, _widget, event, shortcut):
        if event.button == 3:
            menu = Gtk.Menu()
            for label, job in (("Run", lambda: self.run_shortcut(shortcut)),
                               ("Edit", lambda: self.open(shortcut)),
                               ("Duplicate", lambda: self.duplicate(shortcut)),
                               (None, None),
                               ("Delete…", lambda: self.delete(shortcut))):
                if label is None:
                    menu.append(Gtk.SeparatorMenuItem())
                    continue
                item = Gtk.MenuItem(label=label)
                item.connect("activate", lambda _i, j=job: j())
                menu.append(item)
            menu.show_all()
            menu.attach_to_widget(self, None)
            menu.popup_at_pointer(event)
            return True
        if event.button == 1 and event.type == Gdk.EventType._2BUTTON_PRESS:
            self.open(shortcut)
            return True
        return False

    # The Gallery ---------------------------------------------------------------
    def _build_gallery(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_start(24)
        box.set_margin_end(24)
        box.set_margin_top(18)
        heading = Gtk.Label(label="Gallery", xalign=0)
        heading.get_style_context().add_class("bosun-heading")
        box.pack_start(heading, False, False, 0)
        note = Gtk.Label(label="Shortcuts to start from. Add one, then change it as you like.", xalign=0)
        note.get_style_context().add_class("bosun-dim")
        box.pack_start(note, False, False, 0)
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=3,
                           min_children_per_line=1, column_spacing=14, row_spacing=14, homogeneous=True,
                           valign=Gtk.Align.START)
        flow.get_style_context().add_class("bosun-tiles")
        for starter in bosun_store.STARTERS:
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            card.get_style_context().add_class("bosun-card")
            top = Gtk.Box(spacing=10)
            chip = Gtk.Box()
            chip.set_size_request(34, 34)
            chip.get_style_context().add_class("bosun-chip")
            chip.get_style_context().add_class("bosun-" + starter["colour"])
            chip.set_valign(Gtk.Align.CENTER)
            icon = Gtk.Image.new_from_icon_name(first_icon(starter), Gtk.IconSize.MENU)
            chip.set_center_widget(icon)
            top.pack_start(chip, False, False, 0)
            name = Gtk.Label(label=starter["name"], xalign=0, wrap=True)
            name.get_style_context().add_class("bosun-step-title")
            top.pack_start(name, True, True, 0)
            card.pack_start(top, False, False, 0)
            about = Gtk.Label(label=starter["about"], xalign=0, wrap=True, max_width_chars=26)
            about.get_style_context().add_class("bosun-dim")
            card.pack_start(about, True, True, 0)
            add = Gtk.Button(label="Add Shortcut", halign=Gtk.Align.START)
            add.connect("clicked", lambda _b, s=starter: self.add_starter(s))
            card.pack_end(add, False, False, 0)
            flow.add(card)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        flow.set_margin_bottom(18)
        scroll.add(flow)
        box.pack_start(scroll, True, True, 0)
        return box

    def add_starter(self, starter):
        shortcut = bosun_store.from_starter(starter, self.shortcuts)
        shortcut["name"] = bosun_store.free_name(shortcut["name"], self.shortcuts)
        self.shortcuts.append(shortcut)
        self.save()
        self.fill_tiles()
        self.open(shortcut)

    # The editor ----------------------------------------------------------------
    def _build_editor(self):
        outer = Gtk.Box()
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        left.set_margin_start(24)
        left.set_margin_end(20)
        left.set_margin_top(16)
        self.name_entry = Gtk.Entry(placeholder_text="Shortcut Name")
        self.name_entry.get_style_context().add_class("bosun-heading")
        self.name_entry.connect("changed", self._renamed)
        left.pack_start(self.name_entry, False, False, 0)

        details = Gtk.Box(spacing=8)
        self.swatches = {}
        for colour in bosun_store.COLOURS:
            swatch = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
            swatch.set_tooltip_text(colour.capitalize())
            context = swatch.get_style_context()
            context.add_class("bosun-swatch")
            context.add_class("bosun-" + colour)
            swatch.connect("clicked", lambda _b, c=colour: self._recolour(c))
            self.swatches[colour] = swatch
            details.pack_start(swatch, False, False, 0)
        left.pack_start(details, False, False, 0)
        details = Gtk.Box(spacing=8)
        details.pack_start(Gtk.Label(label="Takes"), False, False, 0)
        self.takes = Gtk.ComboBoxText()
        for key, label in TAKES_NAMES:
            self.takes.append(key, label)
        self.takes.connect("changed", self._takes_changed)
        details.pack_start(self.takes, False, False, 0)
        self.in_services = Gtk.CheckButton(label="Show in Services")
        self.in_services.set_tooltip_text("In every app's Services menu (words) or Drawer's menu for files")
        self.in_services.connect("toggled", self._services_toggled)
        details.pack_start(self.in_services, False, False, 6)
        keys = Gtk.Button(label="Keyboard Shortcut…")
        keys.connect("clicked", lambda _b: self.open_keys())
        details.pack_end(keys, False, False, 0)
        left.pack_start(details, False, False, 0)

        self.steps_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.no_steps = Gtk.Label(label="Choose steps from the list on the right. Each one gets what the "
                                        "step before it made.", wrap=True, max_width_chars=40)
        self.no_steps.get_style_context().add_class("bosun-empty")
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        holder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        holder.pack_start(self.steps_box, False, False, 0)
        holder.pack_start(self.no_steps, False, False, 0)
        holder.set_margin_bottom(16)
        scroll.add(holder)
        left.pack_start(scroll, True, True, 0)
        outer.pack_start(left, True, True, 0)

        library = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        library.get_style_context().add_class("bosun-library")
        library.set_size_request(270, -1)
        self.search = Gtk.SearchEntry(placeholder_text="Search Steps")
        self.search.set_margin_start(10)
        self.search.set_margin_end(10)
        self.search.set_margin_top(12)
        self.search.connect("search-changed", lambda _e: self.library.invalidate_filter())
        library.pack_start(self.search, False, False, 0)
        self.library = Gtk.ListBox()
        for category in CATEGORIES:
            for key, entry in ACTIONS.items():
                if entry[0] != category:
                    continue
                row = Gtk.ListBoxRow()
                row.key, row.category = key, category
                line = Gtk.Box(spacing=8)
                line.pack_start(Gtk.Image.new_from_icon_name(CATEGORY_ICONS[category], Gtk.IconSize.MENU),
                                False, False, 0)
                line.pack_start(Gtk.Label(label=entry[1], xalign=0), True, True, 0)
                row.add(line)
                row.set_tooltip_text(entry[2] + " Double-click to add it.")
                self.library.add(row)
        self.library.set_header_func(self._library_header)
        self.library.set_filter_func(self._library_filter)
        self.library.connect("row-activated", lambda _l, row: self.add_step(row.key))
        library_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        library_scroll.add(self.library)
        library.pack_start(library_scroll, True, True, 0)
        outer.pack_start(library, False, False, 0)
        return outer

    def _library_header(self, row, before):
        if before is None or before.category != row.category:
            label = Gtk.Label(label=row.category.upper(), xalign=0)
            label.get_style_context().add_class("bosun-section")
            row.set_header(label)
        else:
            row.set_header(None)

    def _library_filter(self, row):
        words = self.search.get_text().strip().lower()
        if not words:
            return True
        entry = ACTIONS[row.key]
        return all(w in (entry[1] + " " + entry[2] + " " + row.category).lower() for w in words.split())

    def open(self, shortcut):
        self.editing = shortcut
        self.name_entry.set_text(shortcut["name"])
        self.takes.set_active_id(shortcut["takes"])
        self.in_services.set_active(shortcut["services"])
        self.in_services.set_sensitive(shortcut["takes"] != "nothing")
        self._show_colour()
        self.fill_steps()
        self.stack.set_visible_child_name("editor")
        self.sidebar.unselect_all()
        self.back.show()
        self.add_button.hide()
        self.run_button.show()
        self.header.set_title(shortcut["name"])

    def show_list(self):
        self.editing = None
        self.back.hide()
        self.add_button.show()
        self.run_button.hide()
        self.header.set_title("Bosun")
        self.fill_tiles()
        self.sidebar.select_row(self.sidebar.get_row_at_index(0))

    def _side_chosen(self, _list, row):
        if row is None:
            return
        if self.editing is not None:
            self.editing = None
            self.back.hide()
            self.add_button.show()
            self.run_button.hide()
            self.header.set_title("Bosun")
            self.fill_tiles()
        self.stack.set_visible_child_name(row.key)

    def _show_colour(self):
        for colour, swatch in self.swatches.items():
            context = swatch.get_style_context()
            if self.editing and colour == self.editing["colour"]:
                context.add_class("chosen")
            else:
                context.remove_class("chosen")

    def _renamed(self, entry):
        if self.editing is None:
            return
        name = entry.get_text().strip() or "Untitled"
        if name != self.editing["name"]:
            self.editing["name"] = name
            self.header.set_title(name)
            self.save_soon()

    def _recolour(self, colour):
        if self.editing:
            self.editing["colour"] = colour
            self._show_colour()
            self.save_soon()

    def _takes_changed(self, combo):
        if self.editing is None:
            return
        self.editing["takes"] = combo.get_active_id()
        nothing = self.editing["takes"] == "nothing"
        self.in_services.set_sensitive(not nothing)
        if nothing:
            self.in_services.set_active(False)
        self.save_soon()

    def _services_toggled(self, check):
        if self.editing is not None:
            self.editing["services"] = check.get_active() and self.editing["takes"] != "nothing"
            self.save_soon()

    # Steps -----------------------------------------------------------------------
    def fill_steps(self):
        for child in self.steps_box.get_children():
            self.steps_box.remove(child)
        self.cards = []
        steps = self.editing["steps"] if self.editing else []
        for index, step in enumerate(steps):
            card = self._step_card(index, step)
            self.cards.append(card)
            self.steps_box.pack_start(card, False, False, 0)
        self.steps_box.show_all()
        self.no_steps.set_visible(not steps)

    def _step_card(self, index, step):
        entry = ACTIONS.get(step.get("do"))
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        card.get_style_context().add_class("bosun-step")
        top = Gtk.Box(spacing=8)
        icon = CATEGORY_ICONS[entry[0]] if entry else "dialog-question-symbolic"
        top.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
        name = Gtk.Label(label=f"{index + 1}. {bosun_actions.title(step)}", xalign=0)
        name.get_style_context().add_class("bosun-step-title")
        top.pack_start(name, True, True, 0)
        last = len(self.editing["steps"]) - 1 if self.editing else index
        # Packed from the right: Remove at the edge, then Move Down, Move Up.
        for icon_name, tip, job, can in (
                ("window-close-symbolic", "Remove", lambda: self.remove_step(index), True),
                ("go-down-symbolic", "Move Down", lambda: self.move_step(index, 1), index < last),
                ("go-up-symbolic", "Move Up", lambda: self.move_step(index, -1), index > 0)):
            button = Gtk.Button.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
            button.set_sensitive(can)
            button.get_style_context().add_class("flat")
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.set_tooltip_text(tip)
            button.connect("clicked", lambda _b, j=job: j())
            top.pack_end(button, False, False, 0)
        card.pack_start(top, False, False, 0)
        if entry is None:
            card.pack_start(Gtk.Label(label="This version of Bosun doesn't know this step.", xalign=0),
                            False, False, 0)
        else:
            about = Gtk.Label(label=entry[2], xalign=0, wrap=True)
            about.get_style_context().add_class("bosun-dim")
            card.pack_start(about, False, False, 0)
            values = bosun_actions.params(step)
            grid = Gtk.Grid(column_spacing=10, row_spacing=6)
            for row, param in enumerate(entry[3]):
                label = Gtk.Label(label=param[2], xalign=1, valign=Gtk.Align.START)
                label.set_margin_top(5)
                grid.attach(label, 0, row, 1, 1)
                grid.attach(self._param_widget(step, param, values[param[0]]), 1, row, 1, 1)
            if entry[3]:
                card.pack_start(grid, False, False, 0)
        result = Gtk.Label(xalign=0, no_show_all=True, ellipsize=Pango.EllipsizeMode.END)
        result.get_style_context().add_class("bosun-step-result")
        card.pack_start(result, False, False, 0)
        card.result = result
        return card

    def _set(self, step, key, value):
        step[key] = value
        self.save_soon()

    def _input_button(self, insert):
        button = Gtk.Button(label="Input", valign=Gtk.Align.START)
        button.set_tooltip_text("Puts in what the step before makes, as " + INPUT)
        button.connect("clicked", lambda _b: insert())
        return button

    def _param_widget(self, step, param, value):
        key, kind = param[0], param[1]
        if kind == "text":
            view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, monospace=(step.get("do") == "shell"),
                                left_margin=6, right_margin=6, top_margin=4, bottom_margin=4)
            view.get_buffer().set_text(str(value))
            view.get_buffer().connect("changed", lambda b: self._set(
                step, key, b.get_text(b.get_start_iter(), b.get_end_iter(), False)))
            frame = Gtk.Frame()
            scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
            scroll.set_min_content_height(54)
            scroll.set_max_content_height(160)
            scroll.set_propagate_natural_height(True)
            scroll.add(view)
            frame.add(scroll)
            box = Gtk.Box(spacing=6)
            box.pack_start(frame, True, True, 0)
            box.pack_start(self._input_button(lambda: view.get_buffer().insert_at_cursor(INPUT)),
                           False, False, 0)
            box.set_hexpand(True)
            return box
        if kind == "line":
            entry = Gtk.Entry(text=str(value), hexpand=True)
            entry.connect("changed", lambda e: self._set(step, key, e.get_text()))
            box = Gtk.Box(spacing=6)
            box.pack_start(entry, True, True, 0)
            box.pack_start(self._input_button(lambda: _insert(entry, INPUT)), False, False, 0)
            return box
        if kind == "number":
            spin = Gtk.SpinButton.new_with_range(0, 100 if key in ("level",) else 100000, 1)
            spin.set_value(float(value or 0))
            spin.set_halign(Gtk.Align.START)
            spin.connect("value-changed", lambda s: self._set(step, key, int(s.get_value())))
            return spin
        if kind == "choice":
            combo = Gtk.ComboBoxText(halign=Gtk.Align.START)
            for choice, label in param[4]:
                combo.append(choice, label)
            combo.set_active_id(str(value))
            combo.connect("changed", lambda c: self._set(step, key, c.get_active_id()))
            return combo
        if kind == "switch":
            switch = Gtk.Switch(active=bool(value), halign=Gtk.Align.START)
            switch.connect("notify::active", lambda s, _p: self._set(step, key, s.get_active()))
            return switch
        if kind == "folder":
            entry = Gtk.Entry(text=str(value), hexpand=True)
            entry.connect("changed", lambda e: self._set(step, key, e.get_text()))
            choose = Gtk.Button(label="Choose…")
            choose.connect("clicked", lambda _b: self._choose_folder(entry))
            box = Gtk.Box(spacing=6)
            box.pack_start(entry, True, True, 0)
            box.pack_start(choose, False, False, 0)
            return box
        if kind == "app":
            combo = Gtk.ComboBoxText(halign=Gtk.Align.START)
            apps = sorted((a for a in Gio.AppInfo.get_all() if a.should_show() and a.get_id()),
                          key=lambda a: a.get_display_name().lower())
            for app in apps:
                combo.append(app.get_id(), app.get_display_name())
            if value:
                combo.set_active_id(value)
            combo.connect("changed", lambda c: self._set(step, key, c.get_active_id() or ""))
            return combo
        return Gtk.Label(label=str(value))

    def _choose_folder(self, entry):
        dialog = Gtk.FileChooserNative.new("Choose a Folder", self, Gtk.FileChooserAction.SELECT_FOLDER,
                                           "Choose", "Cancel")
        start = os.path.expanduser(entry.get_text() or "~")
        if os.path.isdir(start):
            dialog.set_current_folder(start)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            path = dialog.get_filename()
            home = os.path.expanduser("~")
            if path == home or path.startswith(home + os.sep):
                path = "~" + path[len(home):]
            entry.set_text(path)
        dialog.destroy()

    def add_step(self, key):
        if self.editing is None:
            return
        step = {"do": key}
        step.update(bosun_actions.defaults(key))
        self.editing["steps"].append(step)
        self.fill_steps()
        self.save()

    def move_step(self, index, by):
        steps = self.editing["steps"]
        other = index + by
        if 0 <= other < len(steps):
            steps[index], steps[other] = steps[other], steps[index]
            self.fill_steps()
            self.save()

    def remove_step(self, index):
        del self.editing["steps"][index]
        self.fill_steps()
        self.save()

    # Keeping them -------------------------------------------------------------
    def save_soon(self):
        if self._save_soon:
            GLib.source_remove(self._save_soon)
        self._save_soon = GLib.timeout_add(400, self._save_now)

    def _save_now(self):
        self._save_soon = 0
        self.save()
        return False

    def save(self):
        try:
            bosun_store.save(self.shortcuts)
        except OSError as error:
            alert.tell(self, "The shortcuts couldn't be saved", error.strerror or str(error))

    def new_shortcut(self):
        shortcut = bosun_store.make(bosun_store.free_name("New Shortcut", self.shortcuts), self.shortcuts)
        self.shortcuts.append(shortcut)
        self.save()
        self.open(shortcut)
        self.name_entry.grab_focus()

    def _current(self, shortcut=None):
        return shortcut or self.editing

    def duplicate(self, shortcut=None):
        shortcut = self._current(shortcut)
        if shortcut is None:
            return
        copy = bosun_store.make(bosun_store.free_name(shortcut["name"], self.shortcuts), self.shortcuts,
                                colour=shortcut["colour"], takes=shortcut["takes"],
                                services=shortcut["services"], steps=shortcut["steps"])
        self.shortcuts.append(copy)
        self.save()
        if self.editing:
            self.open(copy)
        else:
            self.fill_tiles()

    def delete(self, shortcut=None):
        shortcut = self._current(shortcut)
        if shortcut is None:
            return
        answer = alert.ask(self, f"Delete “{shortcut['name']}”?", "Its steps can't be brought back.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Delete", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        self.shortcuts = [s for s in self.shortcuts if s["id"] != shortcut["id"]]
        self.save()
        self.show_list()

    def open_keys(self):
        try:
            Gio.Subprocess.new(["freemac-dials", "--panel", "keyboard"], Gio.SubprocessFlags.NONE)
        except GLib.Error:
            pass

    # Running -----------------------------------------------------------------------
    def run_open(self):
        if self.editing is not None:
            self.run_shortcut(self.editing)

    def stop(self):
        if self.running:
            self.running.stop.set()

    def run_shortcut(self, shortcut):
        if self.running:
            return
        if self._save_soon:
            self._save_now()
        ui = WindowUI(self)
        self.running = ui
        showing = self.editing is not None and self.editing["id"] == shortcut["id"]
        self.run_button.set_sensitive(False)
        self.stop_button.show()
        cards = list(self.cards) if showing else []
        for card in cards:
            card.result.hide()
            for name in ("running", "failed"):
                card.get_style_context().remove_class(name)
        value = None
        if shortcut["takes"] == "text":
            value = ui.ask("What words should it use?", "")
            if value is None:
                self._finished(None, cards)
                return
        elif shortcut["takes"] == "files":
            value = self._choose_files()
            if not value:
                self._finished(None, cards)
                return

        def mark(index, made):
            def show():
                if index < len(cards):
                    cards[index].get_style_context().remove_class("running")
                    cards[index].result.set_text("Made: " + bosun_actions.describe(made))
                    cards[index].result.show()
                    if index + 1 < len(cards):
                        cards[index + 1].get_style_context().add_class("running")
                return False
            GLib.idle_add(show)

        def work():
            error = None
            try:
                bosun_actions.run(shortcut["steps"], value, ui, mark)
            except bosun_actions.Stopped:
                pass
            except bosun_actions.StepFailed as failed:
                error = str(failed)
            GLib.idle_add(self._finished, error, cards)

        if cards:
            cards[0].get_style_context().add_class("running")
        threading.Thread(target=work, daemon=True).start()

    def _choose_files(self):
        dialog = Gtk.FileChooserNative.new("Choose Files for the Shortcut", self, Gtk.FileChooserAction.OPEN,
                                           "Run", "Cancel")
        dialog.set_select_multiple(True)
        chosen = dialog.get_filenames() if dialog.run() == Gtk.ResponseType.ACCEPT else []
        dialog.destroy()
        return chosen

    def _finished(self, error, cards):
        self.running = None
        self.run_button.set_sensitive(True)
        self.stop_button.hide()
        for card in cards:
            card.get_style_context().remove_class("running")
        if error:
            failed = _step_number(error)
            if failed is not None and failed < len(cards):
                cards[failed].get_style_context().add_class("failed")
            alert.tell(self, "The shortcut stopped", error)
        return False


def _insert(entry, text):
    at = entry.get_position()
    entry.insert_text(text, at)
    entry.set_position(at + len(text))


def _step_number(message):
    """The index of the step a StepFailed message names ("Step 3, ...")."""
    if message.startswith("Step "):
        number = message[5:].split(",", 1)[0].split(" ", 1)[0]
        if number.isdigit():
            return int(number) - 1
    return None


def menubar():
    return menus.menubar([
        ("_File", [[("New Shortcut", "win.new", "<Ctrl>n"), ("Duplicate", "win.duplicate", "<Ctrl>d")],
                   [("Delete Shortcut…", "win.delete", "<Ctrl>BackSpace")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_View", [[("All Shortcuts", "win.all", "<Ctrl>1"), ("Gallery", "win.gallery", "<Ctrl>2")]]),
        ("_Shortcut", [[("Run", "win.run", "<Ctrl>r"), ("Stop", "win.stop", "<Ctrl>period")],
                       [("Keyboard Shortcut…", "win.keys", None)]]),
    ])


class Bosun(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)

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

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


# freemac-bosun --run ------------------------------------------------------------------
def run_from_command(shortcut_id, text=None, files=None):
    shortcut = bosun_store.find(shortcut_id)
    if shortcut is None:
        _tell("That shortcut isn't in Bosun any more.")
        return 1
    value = None
    if files:
        value = [os.path.abspath(f) for f in files]
    elif text is not None:
        value = text
    elif shortcut["takes"] == "text":
        from . import services
        value = services.selection()
        if not value.strip():
            _tell(f"Select some words first, then run {shortcut['name']}.")
            return 1
    style.apply()
    try:
        bosun_actions.run(shortcut["steps"], value, WindowUI(None))
    except bosun_actions.Stopped:
        return 0
    except bosun_actions.StepFailed as error:
        _tell(f"{shortcut['name']} stopped", str(error))
        return 1
    return 0


def _tell(summary, body=""):
    try:
        from . import beacon
        beacon.send(summary, body, icon="freemac-bosun", app="Bosun")
    except Exception:
        print(summary, body, file=sys.stderr)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    GLib.set_prgname("freemac-bosun")
    if argv[:1] == ["--run"]:
        if len(argv) < 2:
            print(__doc__, file=sys.stderr)
            return 2
        rest = argv[2:]
        if rest[:1] == ["--text"]:
            return run_from_command(argv[1], text=" ".join(rest[1:]))
        if rest[:1] == ["--"]:
            rest = rest[1:]
        return run_from_command(argv[1], files=rest or None)
    return Bosun().run([sys.argv[0]] + argv)


if __name__ == "__main__":
    sys.exit(main())
