# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Login Items: the apps that open by themselves when you log in,
with + to add one and − to take one off, as on a Mac. The same list the
Dock's Options > Open at Login ticks. Original freemac code."""
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, Gtk  # noqa: E402

from . import login_items  # noqa: E402


def _app_row(info):
    line = Gtk.Box(spacing=10)
    icon = info.get_icon()
    image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.DND) if icon else Gtk.Image()
    image.set_pixel_size(28)
    line.pack_start(image, False, False, 0)
    line.pack_start(Gtk.Label(label=info.get_display_name() or info.get_name(), xalign=0), True, True, 0)
    return line


def choose_app(parent, title="Add Login Item", already=None):
    """Ask which app to add. Returns its desktop id, or None. Apps whose
    desktop ids are in `already` (the login items, unless given) aren't
    offered."""
    dialog = Gtk.Dialog(title=title, transient_for=parent, modal=True)
    dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
    add = dialog.add_button("Add", Gtk.ResponseType.OK)
    add.get_style_context().add_class("suggested-action")
    add.set_sensitive(False)
    dialog.set_default_response(Gtk.ResponseType.OK)
    dialog.set_default_size(380, 460)
    box = dialog.get_content_area()
    box.set_spacing(8)
    for side in ("top", "bottom", "start", "end"):
        getattr(box, "set_margin_" + side)(12)
    search = Gtk.SearchEntry(placeholder_text="Search apps")
    box.pack_start(search, False, False, 0)
    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
    if already is None:
        already = {info.get_id() for info in login_items.items()}
    apps = sorted((a for a in Gio.AppInfo.get_all() if a.should_show() and a.get_id() not in already),
                  key=lambda a: (a.get_display_name() or a.get_name() or "").lower())
    for info in apps:
        row = Gtk.ListBoxRow()
        row.add(_app_row(info))
        row.app_id = info.get_id()
        row.words = " ".join(filter(None, (info.get_display_name(), info.get_name(), info.get_id()))).lower()
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
    if answer == Gtk.ResponseType.OK and row is not None:
        return row.app_id
    return None


def login_items_page(window):
    group, row, page, _slider, _switch = window.helpers
    listbox = group()

    def refresh():
        for child in listbox.get_children():
            listbox.remove(child)
        found = login_items.items(listed_only=True)
        if not found:
            empty = Gtk.Label(label="No apps open at login.", xalign=0)
            empty.get_style_context().add_class("dim-label")
            item = Gtk.ListBoxRow(activatable=False)
            item.add(empty)
            listbox.add(item)
        for info in found:
            line = _app_row(info)
            remove = Gtk.Button(label="−", tooltip_text="Don't open at login")
            remove.set_relief(Gtk.ReliefStyle.NONE)
            remove.set_valign(Gtk.Align.CENTER)
            remove.connect("clicked", lambda *_, app_id=info.get_id(): (login_items.set_on(app_id, False), refresh()))
            line.pack_end(remove, False, False, 0)
            item = Gtk.ListBoxRow(activatable=False)
            item.add(line)
            listbox.add(item)
        listbox.show_all()

    def add_clicked(*_):
        app_id = choose_app(window)
        if app_id:
            login_items.set_on(app_id, True)
            refresh()

    refresh()
    add = Gtk.Button(label="+", tooltip_text="Add an app")
    add.connect("clicked", add_clicked)
    buttons = Gtk.Box(spacing=6, halign=Gtk.Align.START)
    buttons.pack_start(add, False, False, 0)
    heading = Gtk.Label(label="Open at Login", xalign=0)
    heading.get_style_context().add_class("dials-caption")
    caption = Gtk.Label(label="These apps open by themselves when you log in. You can also choose "
                              "Options > Open at Login on an app's Dock icon.", xalign=0, wrap=True)
    caption.get_style_context().add_class("dials-caption")
    # Refresh when the page comes back into view: the Dock may have changed it.
    listbox.connect("map", lambda *_: refresh())
    return page("Login Items", heading, listbox, buttons, caption)
