# SPDX-License-Identifier: GPL-3.0-or-later
"""Drawer's Network place, as in a Mac's Finder (Go > Network, ⇧⌘K): the
computers and shared drives on the local network, found as they announce
themselves (Windows and Mac shared folders, network drives, freemac computers
with Remote Login). Opening one connects to it, as Connect to Server does.
GVfs's network:/// does the finding. Original freemac code."""
from gi.repository import Gio, GLib

PLACE = "network:"            # Drawer's name for the place
PREFIX = "network-item:"      # a row's path: PREFIX + the address to connect to
ROOT = "network:///"
ATTRS = "standard::name,standard::display-name,standard::target-uri,standard::icon"


def address_of(path):
    return path[len(PREFIX):] if path.startswith(PREFIX) else None


def browse(found, finished, cancellable=None):
    """Call found(name, address, icon) for each computer, then finished()."""
    root = Gio.File.new_for_uri(ROOT)

    def next_batch(enum, result, _data):
        try:
            infos = enum.next_files_finish(result)
        except GLib.Error:
            infos = []
        for info in infos:
            address = info.get_attribute_string("standard::target-uri")
            if not address:
                address = root.get_child(info.get_name()).get_uri()
            found(info.get_display_name(), address, info.get_icon())
        if infos:
            enum.next_files_async(32, GLib.PRIORITY_DEFAULT, cancellable, next_batch, None)
        else:
            enum.close_async(GLib.PRIORITY_DEFAULT, None, None, None)
            finished()

    def opened(source, result, _data):
        try:
            enum = source.enumerate_children_finish(result)
        except GLib.Error:
            finished()
            return
        enum.next_files_async(32, GLib.PRIORITY_DEFAULT, cancellable, next_batch, None)

    root.enumerate_children_async(ATTRS, Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_DEFAULT,
                                  cancellable, opened, None)


def watch(changed):
    """A monitor that calls changed() when computers come and go; keep it."""
    try:
        monitor = Gio.File.new_for_uri(ROOT).monitor_directory(Gio.FileMonitorFlags.NONE, None)
    except GLib.Error:
        return None
    monitor.connect("changed", lambda *_: changed())
    return monitor
