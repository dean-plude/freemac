# SPDX-License-Identifier: GPL-3.0-or-later
"""Menu bars for freemac's own apps.

Each app publishes a menu bar through GtkApplication. On freemac, Topline
shows it at the top of the screen (Strata's strata-shell passes on where to
find it); elsewhere GTK shows it inside the window.

A menu bar is written as a list of (title, sections), each section a list of
(label, action, keys) where keys is shown next to the item ("<Ctrl>s") or
None. The keys are only shown: each app handles its own keys, so typing in a
text field keeps working as usual.
"""
from gi.repository import Gio, GLib


def section(entries):
    menu = Gio.Menu()
    for label, action, keys in entries:
        item = Gio.MenuItem.new(label, action)
        if keys:
            item.set_attribute_value("accel", GLib.Variant("s", keys))
        menu.append_item(item)
    return menu


def menubar(spec):
    bar = Gio.Menu()
    for title, sections in spec:
        menu = Gio.Menu()
        for entries in sections:
            menu.append_section(None, section(entries))
        bar.append_submenu(title, menu)
    return bar


def add_actions(target, actions):
    """target: a Gtk.ApplicationWindow or Gtk.Application. actions: name ->
    callback taking no arguments."""
    for name, callback in actions.items():
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", lambda _a, _p, c=callback: c())
        target.add_action(action)


def add_toggle(target, name, state, callback):
    """A checkbox item; callback(new_bool)."""
    action = Gio.SimpleAction.new_stateful(name, None, GLib.Variant("b", state))

    def changed(act, value):
        act.set_state(value)
        callback(value.get_boolean())

    action.connect("change-state", changed)
    target.add_action(action)
    return action
