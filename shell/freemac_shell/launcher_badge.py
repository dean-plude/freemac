"""Badges on Dock icons, as on a Mac: the red count on Post for unread mail,
on Nudge for reminders due today, and on any app that reports one.

Apps say what to show with the LauncherEntry signal that many Linux apps
already send (Thunderbird, Telegram, Firefox's downloads and others):
Update(app_uri, properties) on the session bus, where app_uri is
"application://name.desktop" and properties can hold "count" with
"count-visible", "progress" (0 to 1) with "progress-visible", and "urgent",
which makes the icon hop until you go to the app. The Dock
listens for it and draws the badge; when the app quits, its badge goes.

Two more properties give a Mac's Dock the rest of what it shows:
"x-freemac-badge-label", a short text such as "New" or "!" shown in the
red badge in place of the number (Ferry sends it for a Mac app's badge
label that isn't a number), and "quicklist", the object path of a menu the
app serves over dbusmenu, whose items go at the top of the app's
right-click menu in the Dock (see dock_menu).
"""

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

INTERFACE = "com.canonical.Unity.LauncherEntry"
PATH = "/com/canonical/unity/launcherentry/freemac"
# The Dock says when it starts, so apps already open send their badges again.
DOCK_INTERFACE = "org.freemac.Dock"
DOCK_PATH = "/org/freemac/Dock"

# The badge's own text, for apps that send words rather than a number.
LABEL_KEY = "x-freemac-badge-label"
# Longer labels are cut, with an ellipsis, so the badge stays a badge.
LABEL_LIMIT = 8

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


def label_text(label):
    """A badge label as the badge shows it: on one line, and cut with an
    ellipsis past LABEL_LIMIT characters. None when there's nothing to show."""
    text = " ".join(str(label or "").split())
    if not text:
        return None
    if len(text) > LABEL_LIMIT:
        text = text[:LABEL_LIMIT - 1].rstrip() + "\u2026"
    return text


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
        self.badges = {}    # desktop id -> its badge (see merge)
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
        if not desktop_id or not isinstance(props, dict):
            return
        self.badges[desktop_id] = merge(self.badges.get(desktop_id), props, sender)
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


def merge(badge, props, sender=None):
    """The badge an app has after an Update with these properties: each one
    sent replaces the one before, and the rest stay as they were. A value
    of the wrong type is passed over, as other docks do."""
    badge = dict(badge or {})

    def take(key, convert):
        if key in props:
            try:
                return convert(props[key])
            except (TypeError, ValueError, OverflowError):
                pass
        return None

    count = take("count", lambda v: max(0, int(v)))
    if count is not None:
        badge["count"] = count
    for key in ("count-visible", "progress-visible", "urgent"):
        if key in props and isinstance(props[key], (bool, int)):
            badge[key] = bool(props[key])
    progress = take("progress", lambda v: min(1.0, max(0.0, float(v))))
    if progress is not None and progress == progress:   # not NaN
        badge["progress"] = progress
    if LABEL_KEY in props and isinstance(props[LABEL_KEY], str):
        if props[LABEL_KEY].strip():
            badge["label"] = props[LABEL_KEY]
        else:
            badge.pop("label", None)
    if "quicklist" in props and isinstance(props["quicklist"], str):
        # An object path ("o", as the spec has it, or "s", as libunity sends it);
        # empty or "/" takes the menu away.
        path = props["quicklist"]
        if path and path != "/" and path.startswith("/"):
            badge["quicklist"] = path
        else:
            badge.pop("quicklist", None)
    if sender:
        badge["sender"] = sender
    return badge


def text_of(badge):
    """The words or number the red badge shows, or None for no badge: the
    app's label when it sent one, else its count."""
    if not badge or not badge.get("count-visible", True):
        return None
    label = label_text(badge.get("label"))
    if label:
        return label
    count = badge.get("count", 0)
    return badge_text(count) if count else None


def menu_of(badge):
    """(bus name, object path) of the app's Dock menu, or None."""
    if not badge or not badge.get("quicklist") or not badge.get("sender"):
        return None
    return badge["sender"], badge["quicklist"]


def still_urgent(desktop_id, badge, active, seen):
    """Whether an app's icon should still hop for its "urgent": as on a Mac,
    until you go to the app. seen holds the apps you went to since they
    asked; it is kept up to date here, and an app that asks again after
    it stopped asking hops again."""
    if not (badge or {}).get("urgent"):
        seen.discard(desktop_id)
        return False
    if active:
        seen.add(desktop_id)
    return desktop_id not in seen


def shown(badge):
    """(count or 0, progress or None) for a badge as the Dock should draw it."""
    if not badge:
        return 0, None
    count = badge.get("count", 0) if badge.get("count-visible", True) else 0
    progress = badge.get("progress") if badge.get("progress-visible") else None
    return count, progress
