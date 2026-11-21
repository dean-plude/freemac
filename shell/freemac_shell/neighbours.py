# SPDX-License-Identifier: GPL-3.0-or-later
"""Drawer's Network place, as in a Mac's Finder (Go > Network, ⇧⌘K): the
computers and shared drives on the local network, found as they announce
themselves (Windows and Mac shared folders, network drives, freemac computers
with File Sharing or Remote Login). Opening one connects to it, as Connect to
Server does; a computer that shares several folders shows them, to pick one.
GVfs's network:/// does the finding. Original freemac code."""
from gi.repository import Gio, GLib

PLACE = "network:"            # Drawer's name for the place
PREFIX = "network-item:"      # a row's path: PREFIX + the address to connect to
ROOT = "network:///"
ATTRS = "standard::name,standard::display-name,standard::target-uri,standard::icon"


NAMES = {}                    # a computer's address -> the name it was shown with


def address_of(path):
    return path[len(PREFIX):] if path.startswith(PREFIX) else None


def is_place(path):
    """Network itself, or one computer's shared folders ("network:smb://pc/")."""
    return bool(path) and path.startswith(PLACE)


def place_for(address):
    return PLACE + address


def uri_of(place):
    return place[len(PLACE):] or ROOT


def title(place):
    uri = uri_of(place)
    if uri == ROOT:
        return "Network"
    return NAMES.get(uri) or uri.split("://", 1)[-1].split("/", 1)[0].rsplit("@", 1)[-1].split(":")[0]


def browse(found, finished, cancellable=None, uri=ROOT):
    """Call found(name, address, icon) for each computer (or each folder a
    computer shares), then finished()."""
    root = Gio.File.new_for_uri(uri)

    def next_batch(enum, result, _data):
        try:
            infos = enum.next_files_finish(result)
        except GLib.Error:
            infos = []
        for info in infos:
            address = info.get_attribute_string("standard::target-uri")
            if not address:
                address = root.get_child(info.get_name()).get_uri()
            name = info.get_display_name()
            if name.endswith("$"):
                continue        # hidden admin shares such as print$ and C$, as Finder hides them
            found(name, address, info.get_icon())
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


def watch(changed, uri=ROOT):
    """A monitor that calls changed() when computers come and go; keep it."""
    try:
        monitor = Gio.File.new_for_uri(uri).monitor_directory(Gio.FileMonitorFlags.NONE, None)
    except GLib.Error:
        return None
    monitor.connect("changed", lambda *_: changed())
    return monitor
