# SPDX-License-Identifier: GPL-3.0-or-later
"""Now playing: what music or video is playing, and buttons to control it.

Players that follow the MPRIS standard (most Linux music and video players,
and web browsers) publish themselves on the session bus as
org.mpris.MediaPlayer2.<name>. This module finds them, reads the title,
artist and play state of the one that matters most (playing beats paused,
then the most recently seen), and sends Play/Pause, Next and Previous.

Quick settings shows the player (quick.NowPlaying); the media keys go through
freemac-keys. This module only needs Gio, so a key press stays quick.
"""
import sys

from gi.repository import Gio, GLib

PREFIX = "org.mpris.MediaPlayer2."
PATH = "/org/mpris/MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
ACTIONS = {"play-pause": "PlayPause", "next": "Next", "previous": "Previous", "stop": "Stop"}


def session():
    try:
        return Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error:
        return None


def player_names(bus):
    try:
        names = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                              "ListNames", None, None, Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
    except GLib.Error:
        return []
    return sorted(n for n in names if n.startswith(PREFIX))


def _get_all(bus, name, interface):
    try:
        return bus.call_sync(name, PATH, "org.freedesktop.DBus.Properties", "GetAll",
                             GLib.Variant("(s)", (interface,)), None, Gio.DBusCallFlags.NONE,
                             1000, None).unpack()[0]
    except GLib.Error:
        return {}


def describe(bus, name):
    """A dict about one player: name, app, title, artist, status, can_* flags."""
    props = _get_all(bus, name, PLAYER)
    if not props:
        return None
    meta = props.get("Metadata") or {}
    artist = meta.get("xesam:artist") or []
    if isinstance(artist, str):
        artist = [artist]
    app = _get_all(bus, name, "org.mpris.MediaPlayer2").get("Identity") or name[len(PREFIX):].split(".")[0]
    return {
        "name": name,
        "app": app,
        "title": meta.get("xesam:title") or "",
        "artist": ", ".join(a for a in artist if a),
        "art": meta.get("mpris:artUrl") or "",
        "album": meta.get("xesam:album") or "",
        # Microseconds; 0 when the player doesn't say.
        "length": int(meta.get("mpris:length") or 0),
        "position": int(props.get("Position") or 0),
        "status": props.get("PlaybackStatus") or "Stopped",
        "can_play": bool(props.get("CanPlay", True)) or bool(props.get("CanPause", True)),
        "can_next": bool(props.get("CanGoNext", False)),
        "can_previous": bool(props.get("CanGoPrevious", False)),
    }


def pick(players):
    """The player to show and control: one that is playing, else paused, else any with a title."""
    order = {"Playing": 0, "Paused": 1, "Stopped": 2}
    found = [p for p in players if p and (p["title"] or p["status"] != "Stopped")]
    if not found:
        return None
    return sorted(found, key=lambda p: order.get(p["status"], 3))[0]


def current(bus=None):
    bus = bus or session()
    if bus is None:
        return None
    return pick([describe(bus, n) for n in player_names(bus)])


def send(action, bus=None, name=None):
    bus = bus or session()
    if bus is None:
        return False
    if name is None:
        playing = current(bus)
        if playing is None:
            return False
        name = playing["name"]
    try:
        bus.call_sync(name, PATH, PLAYER, ACTIONS[action], None, None, Gio.DBusCallFlags.NONE, 2000, None)
        return True
    except GLib.Error:
        return False


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in ACTIONS:
        playing = current()
        if playing is None:
            print("Nothing is playing.")
        else:
            print(f"{playing['status']}: {playing['title'] or '(untitled)'}"
                  + (f" by {playing['artist']}" if playing["artist"] else "") + f" in {playing['app']}")
        return 0 if not argv else 2
    return 0 if send(argv[0]) else 1


if __name__ == "__main__":
    sys.exit(main())
