# SPDX-License-Identifier: GPL-3.0-or-later
"""Apps that stay open after their last window closes, as on a Mac.

Some of freemac's own apps keep running with no window open: the app stays in
the menu bar while it's in front, keeps its dot in the Dock, and quitting it
is a separate step. Pier and Topline watch these apps on the session bus,
where each one owns its app ID as a name while it runs.

Original freemac code.
"""

import os
import signal

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

# freemac's apps that keep running windowless: the name each owns on the bus,
# and the app ID its windows carry. Drawer runs as many copies as it has
# windows, and Tally quits with its window, as a Mac's Calculator does.
# Keep strata-shell's quit_whole_apps (wayfire.ini and strata-shell.xml) in
# step, so the Command-Q key quits these as a whole too.
HELD_APPS = {"org.freemac.Quill": "freemac-quill", "org.freemac.Jot": "freemac-jot",
             "org.freemac.Tide": "freemac-tide", "org.freemac.Crew": "freemac-crew",
             "org.freemac.Nudge": "freemac-nudge", "org.freemac.Post": "freemac-post",
             "org.freemac.Cove": "freemac-cove", "org.freemac.Shanty": "freemac-shanty",
             "org.freemac.Messages": "freemac-messages"}

DBUS = "org.freedesktop.DBus"


def object_path(app_id):
    """Where a GtkApplication exports its actions and menus."""
    return "/" + app_id.replace(".", "/").replace("-", "_")


def bus_name(app_id):
    """The bus name of a held app, from its bus name or its windows' app ID;
    None for other apps."""
    lower = (app_id or "").lower()
    return next((name for name, window_id in HELD_APPS.items()
                 if lower in (name.lower(), window_id.lower())), None)


def window_id(app_id):
    """The app ID a held app's windows carry."""
    name = bus_name(app_id)
    return HELD_APPS[name] if name else app_id


class Watcher:
    """Which held apps are running; calls on_change when one starts or ends."""

    def __init__(self, on_change=None):
        self.on_change = on_change
        self.running = set()
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        except GLib.Error:
            self.bus = None
            return
        for name in HELD_APPS:
            self.bus.signal_subscribe(DBUS, DBUS, "NameOwnerChanged", "/org/freedesktop/DBus",
                                      name, Gio.DBusSignalFlags.NONE, self._owner_changed)
            self.bus.call(DBUS, "/org/freedesktop/DBus", DBUS, "NameHasOwner",
                          GLib.Variant("(s)", (name,)), GLib.VariantType("(b)"),
                          Gio.DBusCallFlags.NONE, -1, None, self._has_owner, name)

    def _has_owner(self, bus, result, name):
        try:
            owned = bus.call_finish(result).unpack()[0]
        except GLib.Error:
            return
        self._set(name, owned)

    def _owner_changed(self, _bus, _sender, _path, _iface, _signal, params):
        name, _old, new = params.unpack()
        self._set(name, bool(new))

    def _set(self, name, owned):
        if owned == (name in self.running):
            return
        if owned:
            self.running.add(name)
        else:
            self.running.discard(name)
        if self.on_change:
            self.on_change()

    def is_running(self, app_id):
        return bus_name(app_id) in self.running

    def running_ids(self):
        """The window app IDs of the held apps running now."""
        return [HELD_APPS[name] for name in sorted(self.running)]

    def quit(self, app_id):
        """Quit the whole app: its own Quit, which asks about unsaved changes.
        Falls back to ending its process. Returns whether it was running."""
        name = bus_name(app_id)
        if self.bus is None or name not in self.running:
            return False
        self.bus.call(name, object_path(name), "org.gtk.Actions", "Activate",
                      GLib.Variant("(sava{sv})", ("quit", [], {})), None,
                      Gio.DBusCallFlags.NONE, -1, None, self._quit_done, name)
        return True

    def _quit_done(self, bus, result, name):
        try:
            bus.call_finish(result)
            return
        except GLib.Error as error:
            # Still asking about unsaved changes: leave it be.
            if error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.TIMED_OUT):
                return
        # An app with no Quit of its own ends its process.
        try:
            pid = bus.call_sync(DBUS, "/org/freedesktop/DBus", DBUS, "GetConnectionUnixProcessID",
                                GLib.Variant("(s)", (name,)), GLib.VariantType("(u)"),
                                Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
            os.kill(pid, signal.SIGTERM)
        except (GLib.Error, OSError):
            pass
