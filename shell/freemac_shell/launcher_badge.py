"""Badges on Dock icons, as on a Mac: the red count on Post for unread mail,
on Nudge for reminders due today, and on any app that reports one.

Apps say what to show with the LauncherEntry signal that many Linux apps
already send (Thunderbird, Telegram, Firefox's downloads and others):
Update(app_uri, properties) on the session bus, where app_uri is
"application://name.desktop" and properties can hold "count" with
"count-visible", "progress" (0 to 1) with "progress-visible", and "urgent",
which makes the icon hop until you go to the app. The Dock
listens for it and draws the badge; when the app quits, its badge goes.
"""

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

INTERFACE = "com.canonical.Unity.LauncherEntry"
PATH = "/com/canonical/unity/launcherentry/freemac"
# The Dock says when it starts, so apps already open send their badges again.
DOCK_INTERFACE = "org.freemac.Dock"
DOCK_PATH = "/org/freemac/Dock"

_last = {}
_watching = False


def set_count(desktop_id, count, force=False):
    """Show count on the app's Dock icon, or no badge for 0. force sends it
    even when it hasn't changed, for a Dock that started since."""
    count = max(0, int(count or 0))
    if _last.get(desktop_id) == count and not force:
        return
    _last[desktop_id] = count
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        _watch_dock(bus)
        props = {"count": GLib.Variant("x", count), "count-visible": GLib.Variant("b", count > 0)}
        bus.emit_signal(None, PATH, INTERFACE, "Update",
                        GLib.Variant("(sa{sv})", ("application://" + desktop_id, props)))
    except GLib.Error:
        pass   # no session bus: no badge, nothing else changes


def _watch_dock(bus):
    """Once per app: when the Dock starts again, send every badge again."""
    global _watching
    if _watching:
        return
    _watching = True
    bus.signal_subscribe(None, DOCK_INTERFACE, "Started", DOCK_PATH, None,
                         Gio.DBusSignalFlags.NONE, _resend)


def _resend(*_args):
    for desktop_id, count in list(_last.items()):
        if count:
            set_count(desktop_id, count, force=True)


def dock_started(bus):
    """Called by the Dock when it starts: apps send their badges again."""
    try:
        bus.emit_signal(None, DOCK_PATH, DOCK_INTERFACE, "Started", None)
    except GLib.Error:
        pass


def badge_text(count):
    """What the badge says: the number, shortened when it runs long."""
    if count >= 10000:
        return f"{count // 1000}K"
    return str(count)


def desktop_id_of(app_uri):
    """'application://name.desktop' to 'name.desktop'; None for anything else."""
    if not app_uri.startswith("application://"):
        return None
    name = app_uri[len("application://"):]
    return name if name.endswith(".desktop") else name + ".desktop"


class Listener:
    """Keeps the latest badge of every app that sent one, and forgets an
    app's badge when it leaves the bus. changed() is called after each."""

    def __init__(self, changed):
        self.changed = changed
        self.badges = {}    # desktop id -> {"count", "progress"}
        self.senders = {}   # bus name -> set of desktop ids
        self.watches = {}   # bus name -> watch id
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        except GLib.Error:
            self.bus = None
            return
        self.bus.signal_subscribe(None, INTERFACE, "Update", None, None,
                                  Gio.DBusSignalFlags.NONE, self._update)

    def get(self, desktop_id):
        return self.badges.get(desktop_id) if desktop_id else None

    def _update(self, _bus, sender, _path, _interface, _signal, params):
        try:
            uri, props = params.unpack()
        except (TypeError, ValueError):
            return
        desktop_id = desktop_id_of(uri or "")
        if not desktop_id:
            return
        badge = dict(self.badges.get(desktop_id) or {})
        if "count" in props:
            badge["count"] = max(0, int(props["count"]))
        if "count-visible" in props:
            badge["count-visible"] = bool(props["count-visible"])
        if "progress" in props:
            badge["progress"] = min(1.0, max(0.0, float(props["progress"])))
        if "progress-visible" in props:
            badge["progress-visible"] = bool(props["progress-visible"])
        if "urgent" in props:
            badge["urgent"] = bool(props["urgent"])
        self.badges[desktop_id] = badge
        if sender:
            self.senders.setdefault(sender, set()).add(desktop_id)
            if sender not in self.watches:
                self.watches[sender] = Gio.bus_watch_name_on_connection(
                    self.bus, sender, Gio.BusNameWatcherFlags.NONE, None, self._gone)
        self.changed()

    def _gone(self, _bus, sender):
        watch = self.watches.pop(sender, None)
        if watch:
            Gio.bus_unwatch_name(watch)
        for desktop_id in self.senders.pop(sender, ()):
            self.badges.pop(desktop_id, None)
        self.changed()


def shown(badge):
    """(count or 0, progress or None) for a badge as the Dock should draw it."""
    if not badge:
        return 0, None
    count = badge.get("count", 0) if badge.get("count-visible", True) else 0
    progress = badge.get("progress") if badge.get("progress-visible") else None
    return count, progress
