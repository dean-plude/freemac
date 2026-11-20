# SPDX-License-Identifier: GPL-3.0-or-later
"""Saving the Mac way: a small sheet with the file's name and where it goes,
which opens out to the full file browser when that isn't enough.

    path = savesheet.ask(window, "Untitled.txt")          # or None

The name is selected without its extension, ready to type over. Where offers
the folders people save to most (the last one used first), and Other… or the
arrow beside the name opens the full browser. Return saves, Escape or ⌘.
cancels, and saving over a file asks first. Strata shows the sheet coming
down from the window's title bar. Original freemac code.
"""
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import alert  # noqa: E402

WIDTH = 420
EXPAND, OTHER = 1, 2
_last_folder = None


def _places(current):
    """(label, icon, folder) for the Where list: the folder in use first."""
    home = GLib.get_home_dir()
    found = []

    def add(label, icon, folder):
        if folder and os.path.isdir(folder) and all(folder != f for _l, _i, f in found):
            found.append((label, icon, folder))

    if current:
        add(os.path.basename(current.rstrip("/")) or current, "folder-symbolic", current)
    for which, icon in ((GLib.UserDirectory.DIRECTORY_DOCUMENTS, "folder-documents-symbolic"),
                        (GLib.UserDirectory.DIRECTORY_DESKTOP, "user-desktop-symbolic"),
                        (GLib.UserDirectory.DIRECTORY_DOWNLOAD, "folder-download-symbolic")):
        folder = GLib.get_user_special_dir(which)
        if folder and folder != home:
            add(os.path.basename(folder), icon, folder)
    add(os.path.basename(home), "user-home-symbolic", home)
    return found


def _select_name(entry):
    """Select the name without its extension, as on a Mac."""
    text = entry.get_text()
    stem, ext = os.path.splitext(text)
    entry.grab_focus()
    entry.select_region(0, len(stem) if (ext and stem) else len(text))
    return False


def _full_browser(parent, name, folder):
    dialog = Gtk.FileChooserNative.new("Save As", parent, Gtk.FileChooserAction.SAVE, "Save", "Cancel")
    dialog.set_do_overwrite_confirmation(True)
    if folder:
        dialog.set_current_folder(folder)
    dialog.set_current_name(name)
    if dialog.run() == Gtk.ResponseType.ACCEPT:
        return dialog.get_filename()
    return None


def _confirm_replace(parent, path):
    name = os.path.basename(path)
    answer = alert.ask(parent, f"“{name}” already exists. Do you want to replace it?",
                       "A file with the same name already exists in "
                       f"“{os.path.basename(os.path.dirname(path)) or '/'}”. "
                       "Replacing it will overwrite its current contents.",
                       [("Cancel", Gtk.ResponseType.CANCEL), ("Replace", Gtk.ResponseType.OK)],
                       default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
    return answer == Gtk.ResponseType.OK


def build(parent, name, folder):
    """The sheet, its name entry and its Where list."""
    dialog = Gtk.Dialog(transient_for=parent, modal=True, title="Save")
    empty = Gtk.Box()
    empty.set_size_request(-1, 0)
    dialog.set_titlebar(empty)
    visual = dialog.get_screen().get_rgba_visual()
    if visual is not None:
        dialog.set_visual(visual)
    dialog.set_resizable(False)
    dialog.set_default_size(WIDTH, -1)
    dialog.get_style_context().add_class("freemac-alert")
    dialog.get_style_context().add_class("freemac-save")
    action = dialog.get_action_area() if hasattr(dialog, "get_action_area") else None
    if action is not None:
        action.hide()
        action.set_no_show_all(True)

    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    body.get_style_context().add_class("alert-body")
    grid = Gtk.Grid(column_spacing=8, row_spacing=10)
    save_as = Gtk.Label(label="Save As:", xalign=1)
    entry = Gtk.Entry(text=name, hexpand=True, activates_default=True)
    expand = Gtk.Button.new_from_icon_name("pan-down-symbolic", Gtk.IconSize.BUTTON)
    expand.set_tooltip_text("Show all folders")
    expand.connect("clicked", lambda _b: dialog.response(EXPAND))
    grid.attach(save_as, 0, 0, 1, 1)
    grid.attach(entry, 1, 0, 1, 1)
    grid.attach(expand, 2, 0, 1, 1)

    store = Gtk.ListStore(str, str, str)   # label, icon, folder ("" for Other…)
    for label, icon, place in _places(folder):
        store.append([label, icon, place])
    store.append(["Other…", "folder-open-symbolic", ""])
    where = Gtk.ComboBox(model=store, hexpand=True)
    icon_cell, text_cell = Gtk.CellRendererPixbuf(), Gtk.CellRendererText()
    where.pack_start(icon_cell, False)
    where.add_attribute(icon_cell, "icon-name", 1)
    where.pack_start(text_cell, True)
    where.add_attribute(text_cell, "text", 0)
    where.set_active(0)
    where.connect("changed", lambda w: (w.get_active() == len(store) - 1) and dialog.response(OTHER))
    grid.attach(Gtk.Label(label="Where:", xalign=1), 0, 1, 1, 1)
    grid.attach(where, 1, 1, 2, 1)
    body.pack_start(grid, False, False, 0)

    row = Gtk.Box(spacing=8, halign=Gtk.Align.END)
    row.get_style_context().add_class("alert-buttons")
    cancel = Gtk.Button(label="Cancel")
    cancel.connect("clicked", lambda _b: dialog.response(Gtk.ResponseType.CANCEL))
    save = Gtk.Button(label="Save", can_default=True)
    save.get_style_context().add_class("suggested-action")
    save.connect("clicked", lambda _b: dialog.response(Gtk.ResponseType.ACCEPT))
    entry.connect("changed", lambda e: save.set_sensitive(bool(e.get_text().strip())))
    row.pack_start(cancel, False, False, 0)
    row.pack_start(save, False, False, 0)
    body.pack_start(row, False, False, 4)
    dialog.get_content_area().pack_start(body, True, True, 0)
    body.show_all()

    def key(_widget, event):
        if event.keyval == Gdk.KEY_Escape:
            dialog.response(Gtk.ResponseType.CANCEL)
            return True
        return False

    dialog.connect("key-press-event", key)
    dialog.set_default(save)
    dialog.connect("map", lambda *_: GLib.idle_add(_select_name, entry))
    return dialog, entry, where, store


def ask(parent, name="Untitled", folder=None):
    """Ask where to save; the chosen path, or None if cancelled."""
    global _last_folder
    folder = folder or _last_folder or GLib.get_user_special_dir(
        GLib.UserDirectory.DIRECTORY_DOCUMENTS) or GLib.get_home_dir()
    while True:
        dialog, entry, where, store = build(parent, name, folder)
        answer = dialog.run()
        name = entry.get_text().strip() or name
        index = where.get_active()
        chosen = store[index][2] if 0 <= index < len(store) else ""
        folder = chosen or folder
        dialog.destroy()
        if answer in (EXPAND, OTHER):
            path = _full_browser(parent, name, folder)
            if path:
                _last_folder = os.path.dirname(path)
            return path
        if answer != Gtk.ResponseType.ACCEPT:
            return None
        if "/" in name:
            alert.tell(parent, "The name can’t contain “/”.", "Please use a different name.")
            continue
        path = os.path.join(folder, name)
        if os.path.exists(path) and not _confirm_replace(parent, path):
            continue
        _last_folder = folder
        return path
