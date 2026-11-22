# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Seek, as a Mac's Spotlight settings: Search Results, a switch for
each kind of thing Seek lists, and Privacy, the folders Seek and Drawer's
searches leave alone, with + and − to change the list. Rebuild Index reads
your documents again from the start. Original freemac code."""
import os
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

from . import seek_index, seek_settings  # noqa: E402


def _short(path):
    home = GLib.get_home_dir()
    if path == home:
        return "Home"
    if path.startswith(home + os.sep):
        return "~" + path[len(home):]
    return path


def choose_folder(parent):
    dialog = Gtk.FileChooserDialog(title="Keep a Folder Private", transient_for=parent, modal=True,
                                   action=Gtk.FileChooserAction.SELECT_FOLDER)
    dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
    dialog.add_button("Choose", Gtk.ResponseType.OK).get_style_context().add_class("suggested-action")
    dialog.set_current_folder(GLib.get_home_dir())
    answer = dialog.run()
    path = dialog.get_filename()
    dialog.destroy()
    return path if answer == Gtk.ResponseType.OK and path else None


def _reindex(button, label):
    button.set_sensitive(False)
    label.set_text("Reading your documents…")

    def work():
        try:
            os.remove(seek_index.DB)
        except OSError:
            pass
        try:
            count = seek_index.update()
            text = (f"Read {count} document{'s' if count != 1 else ''}."
                    if seek_settings.shown("contents") else "Words inside documents is off.")
        except Exception:   # noqa: BLE001 — say so rather than crash Dials
            text = "Couldn't read your documents."
        GLib.idle_add(lambda: (label.set_text(text), button.set_sensitive(True), False)[-1])

    threading.Thread(target=work, daemon=True).start()


def seek_page(window):
    group, row, page, _slider, switch = window.helpers

    results_heading = Gtk.Label(label="Search Results", xalign=0)
    results_heading.get_style_context().add_class("dials-caption")
    results = group(*[row(title, switch(seek_settings.shown(name),
                                        lambda on, name=name: seek_settings.set_shown(name, on)))
                      for name, title in seek_settings.CATEGORIES])
    results_caption = Gtk.Label(label="Only the kinds turned on here show up when you search with Seek "
                                      "(⌘Space). Turning off Words inside documents also forgets what "
                                      "Seek has read from them.", xalign=0, wrap=True)
    results_caption.get_style_context().add_class("dials-caption")

    privacy_heading = Gtk.Label(label="Privacy", xalign=0)
    privacy_heading.get_style_context().add_class("dials-caption")
    folders = group()

    def refresh():
        for child in folders.get_children():
            folders.remove(child)
        kept = seek_settings.private()
        if not kept:
            empty = Gtk.Label(label="No private folders.", xalign=0)
            empty.get_style_context().add_class("dim-label")
            item = Gtk.ListBoxRow(activatable=False)
            item.add(empty)
            folders.add(item)
        for path in kept:
            line = Gtk.Box(spacing=10)
            line.pack_start(Gtk.Image.new_from_icon_name("folder-symbolic", Gtk.IconSize.LARGE_TOOLBAR),
                            False, False, 0)
            line.pack_start(Gtk.Label(label=_short(path), xalign=0, tooltip_text=path,
                                      ellipsize=3), True, True, 0)
            remove = Gtk.Button(label="−", tooltip_text="Let Seek look in this folder again")
            remove.set_relief(Gtk.ReliefStyle.NONE)
            remove.set_valign(Gtk.Align.CENTER)
            remove.connect("clicked", lambda *_, p=path: (seek_settings.remove_private(p), refresh()))
            line.pack_end(remove, False, False, 0)
            item = Gtk.ListBoxRow(activatable=False)
            item.add(line)
            folders.add(item)
        folders.show_all()

    def add_clicked(*_):
        path = choose_folder(window)
        if path:
            seek_settings.add_private(path)
            refresh()

    refresh()
    add = Gtk.Button(label="+", tooltip_text="Keep a folder private")
    add.connect("clicked", add_clicked)
    buttons = Gtk.Box(spacing=6, halign=Gtk.Align.START)
    buttons.pack_start(add, False, False, 0)
    privacy_caption = Gtk.Label(label="Seek and Drawer's searches leave these folders out, and Seek "
                                      "forgets what it read inside them.", xalign=0, wrap=True)
    privacy_caption.get_style_context().add_class("dials-caption")

    status = Gtk.Label(label="", xalign=0)
    status.get_style_context().add_class("dials-caption")
    rebuild = Gtk.Button(label="Rebuild Index")
    rebuild.connect("clicked", lambda b: _reindex(b, status))
    index_row = group(row("Words inside documents", rebuild,
                          "If Seek misses a document you know is there, read them all again."))

    return page("Seek", results_heading, results, results_caption,
                privacy_heading, folders, buttons, privacy_caption, index_row, status)
