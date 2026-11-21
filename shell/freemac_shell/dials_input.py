# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Keyboard's Input Sources and key repeat, as on a Mac: the layouts
you type with, by name, with + to add one and − to take one off; whether the
menu bar shows the input menu; and how fast a held key repeats.
Original freemac code."""
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

from . import input_sources, style  # noqa: E402


def choose_source(parent, have):
    """Ask which input source to add. Returns (layout, variant), or None."""
    dialog = Gtk.Dialog(title="Add Input Source", transient_for=parent, modal=True)
    dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
    add = dialog.add_button("Add", Gtk.ResponseType.OK)
    add.get_style_context().add_class("suggested-action")
    add.set_sensitive(False)
    dialog.set_default_response(Gtk.ResponseType.OK)
    dialog.set_default_size(400, 480)
    box = dialog.get_content_area()
    box.set_spacing(8)
    for side in ("top", "bottom", "start", "end"):
        getattr(box, "set_margin_" + side)(12)
    search = Gtk.SearchEntry(placeholder_text="Search languages and layouts")
    box.pack_start(search, False, False, 0)
    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
    for layout, variant, name in sorted(input_sources.catalogue(), key=lambda c: c[2].lower()):
        if (layout, variant) in have:
            continue
        row = Gtk.ListBoxRow()
        row.add(Gtk.Label(label=name, xalign=0, margin=4))
        row.source = (layout, variant)
        row.words = f"{name} {layout} {variant}".lower()
        listbox.add(row)
    listbox.set_filter_func(lambda row: all(w in row.words for w in search.get_text().lower().split()))
    search.connect("search-changed", lambda *_: listbox.invalidate_filter())
    listbox.connect("row-selected", lambda _l, row: add.set_sensitive(row is not None))
    listbox.connect("row-activated", lambda *_: dialog.response(Gtk.ResponseType.OK))
    scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
    scroll.set_shadow_type(Gtk.ShadowType.IN)
    scroll.add(listbox)
    box.pack_start(scroll, True, True, 0)
    dialog.show_all()
    search.grab_focus()
    answer = dialog.run()
    row = listbox.get_selected_row()
    dialog.destroy()
    return row.source if answer == Gtk.ResponseType.OK and row is not None else None


def input_sources_group(window, group, row, switch, ini_get, ini_set):
    """The Input Sources list, its + button and the input menu switch."""
    listbox = group()

    def save(items):
        input_sources.save(items, ini_set, ini_get)
        refresh()

    def refresh():
        for child in listbox.get_children():
            listbox.remove(child)
        items = input_sources.sources()
        for n, (layout, variant) in enumerate(items):
            line = Gtk.Box(spacing=10)
            badge = Gtk.Label(label=input_sources.short_label(layout, variant))
            badge.get_style_context().add_class("input-badge")
            line.pack_start(badge, False, False, 0)
            line.pack_start(Gtk.Label(label=input_sources.name_of(layout, variant), xalign=0), True, True, 0)
            if len(items) > 1:
                remove = Gtk.Button(label="−", tooltip_text="Remove this input source")
                remove.set_relief(Gtk.ReliefStyle.NONE)
                remove.set_valign(Gtk.Align.CENTER)
                remove.connect("clicked", lambda *_, n=n: save(items[:n] + items[n + 1:]))
                line.pack_end(remove, False, False, 0)
            item = Gtk.ListBoxRow(activatable=False)
            item.add(line)
            listbox.add(item)
        more = Gtk.Button(label="Add Input Source…", halign=Gtk.Align.START)
        more.set_relief(Gtk.ReliefStyle.NONE)
        full = len(items) >= input_sources.MAX_SOURCES
        more.set_sensitive(not full)
        more.set_tooltip_text("Up to four at a time" if full else None)

        def add(*_):
            chosen = choose_source(window, set(items))
            if chosen:
                save(items + [chosen])
        more.connect("clicked", add)
        item = Gtk.ListBoxRow(activatable=False)
        item.add(more)
        listbox.add(item)
        listbox.show_all()

    refresh()
    menu = group(row("Show Input menu in menu bar",
                     switch(style.prefs().get("input_menu", True),
                            lambda on: window.save_prefs(input_menu=on)),
                     "With more than one input source, the menu bar shows which one you're typing "
                     "with. Control-Space switches to the next."))
    return listbox, menu


def key_repeat_group(group, row, slider, ini_get, ini_set):
    """Key repeat rate and Delay until repeat, as on a Mac."""
    def number(key, default):
        try:
            return int(float(ini_get("input", key, default) or default))
        except ValueError:
            return default

    rate = slider(10, 60, 5, number("kb_repeat_rate", 40),
                  lambda v: ini_set("input", "kb_repeat_rate", str(int(v))), marks=((10, "Slow"), (60, "Fast")))
    # A longer delay is further left, as on a Mac (Long ... Short).
    delay = slider(-1000, -150, 50, -number("kb_repeat_delay", 400),
                   lambda v: ini_set("input", "kb_repeat_delay", str(int(-v))),
                   marks=((-1000, "Long"), (-150, "Short")))
    return group(row("Key repeat rate", rate), row("Delay until repeat", delay,
                                                   "How long to hold a key before it starts repeating."))


def spelling_group(window, group, row, switch):
    """Check spelling while typing, for every app where you write."""
    from . import spelling

    caption = ("Underlines misspelled words in red in Jot, Post, Stickies, Quill and the notes in "
               "other apps. Right-click one for suggestions, or to add it to the dictionary.")
    if not spelling.available():
        caption = "Spell checking isn't installed on this computer."
    toggle = switch(spelling.wanted(), lambda on: window.save_prefs(check_spelling=on))
    toggle.set_sensitive(spelling.available())
    return group(row("Check spelling while typing", toggle, caption))
