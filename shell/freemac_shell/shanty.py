# SPDX-License-Identifier: GPL-3.0-or-later
"""Shanty: your music.

The songs in the Music folder (music_store.py reads them), by album, by
artist and as one long list of songs, with Recently Added for the albums
that came in this month. Albums show as covers; clicking one opens it with
its songs, and Play or Shuffle plays it from the start. Double-click (or
Return on) a song to play from there.

The toolbar has shuffle, back, play, forward and repeat (off, all, one),
and in the middle what's playing, with its cover and a bar to move through
the song. Space plays and pauses. Songs follow on without a gap. The volume
and what was playing, and where, are kept for next time.

Shanty is an MPRIS player (org.mpris.MediaPlayer2.shanty), so the media
keys and the what's-playing row in Quick Settings show and control it,
with its window closed too: the app keeps playing until it is quit.
Dropping songs or folders on the window copies them into the Music folder.
Original freemac code.
"""
import hashlib
import math
import os
import random
import subprocess
import sys
import threading
import time

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert, menus, style, transfer  # noqa: E402
from . import music_store as store  # noqa: E402

try:
    gi.require_version("Gst", "1.0")
    from gi.repository import Gst  # noqa: E402
    Gst.init(None)
except (ImportError, ValueError):
    Gst = None

APP_ID = "org.freemac.Shanty"
BUS_NAME = "org.mpris.MediaPlayer2.shanty"
MPRIS_PATH = "/org/mpris/MediaPlayer2"
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
TILE = 168            # album cover size in the grid
BIG_COVER = 230
RESTART_AFTER = 3     # seconds into a song after which Back starts it again
REPEATS = ("off", "all", "one")
ACCENT = "#ea6a2e"

CSS = b"""
.shanty-side { background: alpha(currentColor, 0.04); }
list.shanty-side { background: transparent; }
.shanty-side row { padding: 5px 10px; border-radius: 7px; margin: 0 6px; background: transparent; }
.shanty-side row:selected { background: alpha(@theme_fg_color, 0.12); }
.shanty-side row:selected label { color: @theme_fg_color; }
.shanty-side image { color: #ea6a2e; }
.shanty-side-head { font-size: 12px; font-weight: 700; color: alpha(currentColor, 0.5); padding: 12px 14px 2px 14px; }
.shanty-page { background: @theme_base_color; }
.shanty-title { font-size: 24px; font-weight: 700; }
.shanty-album-title { font-size: 26px; font-weight: 700; }
.shanty-album-artist { font-size: 22px; color: #ea6a2e; }
.shanty-dim { color: alpha(currentColor, 0.55); font-size: 12px; }
.shanty-tile-title { font-size: 13px; font-weight: 600; }
.shanty-tile-artist { font-size: 13px; color: alpha(currentColor, 0.55); }
.shanty-page flowboxchild { padding: 0; background: transparent; outline: none; border-radius: 8px; }
.shanty-page flowboxchild:selected { background: alpha(@theme_fg_color, 0.08); }
.shanty-songs row { padding: 6px 10px; border-radius: 6px; }
.shanty-songs row:nth-child(even) { background: alpha(currentColor, 0.03); }
.shanty-songs row:selected { background: alpha(#ea6a2e, 0.85); }
.shanty-songs row:selected label, .shanty-songs row:selected image { color: #ffffff; }
.shanty-songs { background: transparent; }
.shanty-number { color: alpha(currentColor, 0.5); font-feature-settings: "tnum"; }
.shanty-playing image, .shanty-playing-title { color: #ea6a2e; }
.shanty-lcd { background: alpha(currentColor, 0.06); border-radius: 7px; padding: 2px 8px; }
.shanty-lcd-title { font-size: 12px; font-weight: 600; }
.shanty-lcd-sub { font-size: 11px; color: alpha(currentColor, 0.6); }
.shanty-lcd-time { font-size: 10px; color: alpha(currentColor, 0.55); font-feature-settings: "tnum"; }
.shanty-lcd scale { padding: 0; margin: 0; min-height: 10px; }
.shanty-lcd scale trough { min-height: 3px; }
.shanty-lcd scale slider { min-width: 8px; min-height: 8px; margin: -3px; }
.shanty-lcd scale highlight { background: alpha(currentColor, 0.5); }
.shanty-round { border-radius: 99px; padding: 6px; min-width: 0; min-height: 0; }
.shanty-on, .shanty-on image { color: #ea6a2e; }
.shanty-play-button { background: #ea6a2e; color: #ffffff; border: none; padding: 5px 18px; border-radius: 7px; font-weight: 600; }
.shanty-play-button image { color: #ffffff; }
.shanty-light-button { padding: 5px 18px; border-radius: 7px; font-weight: 600; color: #ea6a2e; }
.shanty-light-button image { color: #ea6a2e; }
.shanty-empty-title { font-size: 20px; font-weight: 700; color: alpha(currentColor, 0.55); }
.shanty-empty-text { font-size: 13px; color: alpha(currentColor, 0.5); }
.shanty-drop { box-shadow: inset 0 0 0 3px alpha(#ea6a2e, 0.7); }
treeview.shanty-tree { background: @theme_base_color; }
treeview.shanty-tree:selected { background: #ea6a2e; color: #ffffff; }
"""


def plural(n, one, many=None):
    return f"{n} {one if n == 1 else (many or one + 's')}"


# --- covers ------------------------------------------------------------------

def _hue(text):
    return int(hashlib.md5(text.encode("utf-8")).hexdigest()[:4], 16) / 0xFFFF


def _rounded(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def _hsv(h, s, v):
    import colorsys
    return colorsys.hsv_to_rgb(h % 1, s, v)


def draw_placeholder(cr, size, key):
    """An album with no cover: a soft two-colour square with a note on it."""
    h = _hue(key)
    grad = cairo.LinearGradient(0, 0, size, size)
    grad.add_color_stop_rgb(0, *_hsv(h, 0.35, 0.92))
    grad.add_color_stop_rgb(1, *_hsv(h + 0.08, 0.55, 0.70))
    cr.set_source(grad)
    cr.paint()
    cr.set_source_rgba(1, 1, 1, 0.85)
    s = size / 100
    cr.save()
    cr.translate(size / 2 - 14 * s, size / 2 - 22 * s)
    cr.set_line_width(5 * s)
    cr.move_to(10 * s, 32 * s)
    cr.line_to(10 * s, 0)
    cr.line_to(34 * s, -6 * s)
    cr.line_to(34 * s, 26 * s)
    cr.stroke()
    cr.rectangle(8 * s, -2 * s, 28 * s, 7 * s)
    cr.fill()
    for cx, cy in ((4 * s, 34 * s), (28 * s, 28 * s)):
        cr.save()
        cr.translate(cx, cy)
        cr.scale(1.25, 1)
        cr.arc(0, 0, 6.5 * s, 0, 2 * math.pi)
        cr.restore()
        cr.fill()
    cr.restore()


class Covers:
    """Album covers scaled to a size, read on a thread, kept in memory."""

    def __init__(self):
        self.kept = {}
        self.waiting = []
        self.wanted = threading.Event()
        self.lock = threading.Lock()
        threading.Thread(target=self._work, daemon=True).start()

    def get(self, path, size, widget):
        if not path:
            return None
        key = (path, size)
        found = self.kept.get(key)
        if found is not None:
            return found or None
        with self.lock:
            if not any(w[0] == key for w in self.waiting):
                self.waiting.append((key, widget))
        self.wanted.set()
        return None

    def _work(self):
        while True:
            self.wanted.wait()
            with self.lock:
                if not self.waiting:
                    self.wanted.clear()
                    continue
                key, widget = self.waiting.pop(0)
            path, size = key
            try:
                picture = GdkPixbuf.Pixbuf.new_from_file(path)
                w, h = picture.get_width(), picture.get_height()
                side = min(w, h)
                if w != h:
                    picture = picture.new_subpixbuf((w - side) // 2, (h - side) // 2, side, side)
                picture = picture.scale_simple(size, size, GdkPixbuf.InterpType.BILINEAR)
            except GLib.Error:
                picture = False
            GLib.idle_add(self._done, key, picture, widget)

    def _done(self, key, picture, widget):
        self.kept[key] = picture
        if len(self.kept) > 600:
            for old in list(self.kept)[:200]:
                del self.kept[old]
        widget.queue_draw()
        return False


COVERS = None


def draw_cover(widget, cr, album_key, cover, size, radius=6):
    scale = widget.get_scale_factor()
    cr.save()
    _rounded(cr, 0, 0, size, size, radius)
    cr.clip()
    picture = COVERS.get(cover, size * scale, widget) if cover else None
    if picture is not None:
        cr.scale(1 / scale, 1 / scale)
        Gdk.cairo_set_source_pixbuf(cr, picture, 0, 0)
        cr.paint()
        cr.scale(scale, scale)
    else:
        draw_placeholder(cr, size, album_key)
    cr.restore()
    cr.save()
    _rounded(cr, 0.5, 0.5, size - 1, size - 1, radius)
    cr.set_source_rgba(0, 0, 0, 0.12)
    cr.set_line_width(1)
    cr.stroke()
    cr.restore()


def cover_area(album_key, cover, size, radius=6):
    area = Gtk.DrawingArea()
    area.set_size_request(size, size)
    area.connect("draw", lambda w, cr: draw_cover(w, cr, album_key, cover, size, radius))
    return area


# --- playing -------------------------------------------------------------------

class Player:
    """A queue of songs played one after another with GStreamer's playbin.
    changed(what) is called on the main thread with "song", "status",
    "queue" or "seeked"."""

    def __init__(self, changed):
        self.changed = changed
        self.queue = []        # songs, in the order they were given
        self.order = []        # indexes into queue, in the order they play
        self.at = -1           # where in order the current song is
        self.status = "Stopped"
        self.shuffle = False
        self.repeat = "off"
        self.volume = 0.7
        self.lock = threading.Lock()
        self.next_at = None    # set when the next song was handed over early, for no gap
        self.resume = 0        # seconds to start the first song at
        self.then_play = False
        self.errors = 0
        self.bin = Gst.ElementFactory.make("playbin", "shanty") if Gst else None
        if self.bin is not None:
            fake = Gst.ElementFactory.make("fakesink", None)
            if fake is not None:
                self.bin.set_property("video-sink", fake)
            self.bin.connect("about-to-finish", self._about_to_finish)
            bus = self.bin.get_bus()
            bus.add_signal_watch()
            bus.connect("message", self._message)
            self.set_volume(self.volume)

    @property
    def song(self):
        if 0 <= self.at < len(self.order):
            return self.queue[self.order[self.at]]
        return None

    def can_play(self):
        return self.bin is not None

    # the queue

    def _make_order(self, first):
        order = list(range(len(self.queue)))
        if self.shuffle:
            rest = [i for i in order if i != first]
            random.shuffle(rest)
            order = ([first] if first is not None and 0 <= first < len(self.queue) else []) + rest
        return order

    def play_songs(self, songs, first=0, shuffle=None):
        """Play these songs, starting with songs[first]."""
        if not songs:
            return
        if shuffle is not None:
            self.shuffle = shuffle
            if shuffle:
                first = random.randrange(len(songs))
        with self.lock:
            self.queue = list(songs)
            self.order = self._make_order(first)
            self.at = self.order.index(first) if first in self.order else 0
        self.changed("queue")
        self._start(self.song, 0)

    def play_next(self, songs):
        """Put songs right after the one playing."""
        if not self.queue:
            self.play_songs(songs)
            return
        with self.lock:
            start = len(self.queue)
            self.queue.extend(songs)
            new = list(range(start, start + len(songs)))
            self.order[self.at + 1:self.at + 1] = new
        self.changed("queue")

    def set_shuffle(self, on):
        if on == self.shuffle:
            return
        self.shuffle = on
        with self.lock:
            current = self.order[self.at] if self.song else None
            if on:
                self.order = self._make_order(current)
                self.at = 0 if current is not None else -1
            else:
                self.order = list(range(len(self.queue)))
                self.at = current if current is not None else -1
        self.changed("queue")

    def set_repeat(self, mode):
        self.repeat = mode if mode in REPEATS else "off"
        self.changed("queue")

    def _following(self, step=1, user=False):
        """Where in order the next (or previous) song is, or None."""
        if not self.order:
            return None
        if self.repeat == "one" and not user:
            return self.at
        target = self.at + step
        if 0 <= target < len(self.order):
            return target
        if self.repeat != "off" or (user and step < 0):
            return target % len(self.order)
        return None

    def has_next(self):
        return bool(self.order) and (self._following(1, True) is not None)

    def has_previous(self):
        return bool(self.order)

    # playing

    def _start(self, song, at_seconds, play=True):
        if self.bin is None or song is None:
            return
        self.next_at = None
        self.bin.set_state(Gst.State.READY)
        self.bin.set_property("uri", store.uri(song["path"]))
        self.resume = at_seconds
        self.then_play = play
        self.bin.set_state(Gst.State.PAUSED)
        self.status = "Playing" if play else "Paused"
        self.changed("song")
        self.changed("status")

    def load(self, songs, at_index, position):
        """Get ready to go on from where it was, without playing yet."""
        self.queue = list(songs)
        self.order = list(range(len(songs)))
        self.at = at_index if 0 <= at_index < len(songs) else 0
        self.resume = position
        self.status = "Paused"
        self.changed("queue")
        self.changed("song")

    def play(self):
        if self.bin is None or self.song is None:
            return
        state = self.bin.get_state(0)[1]
        if state in (Gst.State.NULL, Gst.State.READY):
            self._start(self.song, self.resume)
            return
        self.bin.set_state(Gst.State.PLAYING)
        self.status = "Playing"
        self.changed("status")

    def pause(self):
        if self.bin is None or self.status != "Playing":
            return
        self.bin.set_state(Gst.State.PAUSED)
        self.status = "Paused"
        self.changed("status")

    def play_pause(self):
        if self.status == "Playing":
            self.pause()
        else:
            self.play()

    def stop(self):
        if self.bin is None:
            return
        self.bin.set_state(Gst.State.READY)
        self.resume = 0
        self.status = "Stopped"
        self.changed("status")

    def next(self):
        target = self._following(1, True)
        if target is None:
            return
        playing = self.status == "Playing"
        self.at = target
        self._start(self.song, 0, play=playing)

    def previous(self):
        if self.song is None:
            return
        if self.position() > RESTART_AFTER:
            self.seek(0)
            return
        target = self._following(-1, True)
        if target is None:
            self.seek(0)
            return
        playing = self.status == "Playing"
        self.at = target
        self._start(self.song, 0, play=playing)

    def jump(self, order_at):
        if 0 <= order_at < len(self.order):
            self.at = order_at
            self._start(self.song, 0)

    def position(self):
        if self.bin is None:
            return 0
        if self.status == "Stopped":
            return 0
        ok, pos = self.bin.query_position(Gst.Format.TIME)
        if ok and pos >= 0:
            return pos / Gst.SECOND
        return self.resume or 0

    def duration(self):
        song = self.song
        if song and song.get("duration"):
            return song["duration"]
        if self.bin is not None:
            ok, length = self.bin.query_duration(Gst.Format.TIME)
            if ok and length > 0:
                return length / Gst.SECOND
        return 0

    def seek(self, seconds):
        if self.bin is None or self.song is None:
            return
        seconds = max(0, min(seconds, self.duration() or seconds))
        state = self.bin.get_state(0)[1]
        if state in (Gst.State.NULL, Gst.State.READY):
            self.resume = seconds
        else:
            self.bin.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT,
                                 int(seconds * Gst.SECOND))
        self.changed("seeked")

    def set_volume(self, value):
        self.volume = max(0.0, min(1.0, value))
        if self.bin is not None:
            self.bin.set_property("volume", self.volume ** 3)

    # GStreamer's side

    def _about_to_finish(self, playbin):
        # On GStreamer's own thread: hand over the next song now so it
        # follows without a gap.
        with self.lock:
            target = self._following(1)
            if target is None:
                return
            self.next_at = target
            song = self.queue[self.order[target]]
        playbin.set_property("uri", store.uri(song["path"]))

    def _message(self, _bus, message):
        kind = message.type
        if kind == Gst.MessageType.STREAM_START:
            self.errors = 0
            if self.next_at is not None:
                self.at, self.next_at = self.next_at, None
                self.changed("song")
        elif kind == Gst.MessageType.ASYNC_DONE:
            if self.resume:
                at, self.resume = self.resume, 0
                self.bin.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT,
                                     int(at * Gst.SECOND))
                self.changed("seeked")
            if self.then_play:
                self.then_play = False
                self.bin.set_state(Gst.State.PLAYING)
        elif kind == Gst.MessageType.EOS:
            self.next_at = None
            self.bin.set_state(Gst.State.READY)
            self.status = "Stopped"
            self.changed("status")
        elif kind == Gst.MessageType.ERROR:
            error, _debug = message.parse_error()
            print(f"shanty: couldn't play {self.song and self.song['path']}: {error.message}", file=sys.stderr)
            self.errors += 1
            self.bin.set_state(Gst.State.READY)
            target = self._following(1)
            if target is not None and self.errors < len(self.order):
                self.at = target
                self._start(self.song, 0)
            else:
                self.status = "Stopped"
                self.changed("status")


# --- MPRIS ----------------------------------------------------------------------

MPRIS_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""
LOOPS = {"off": "None", "all": "Playlist", "one": "Track"}
MIME_TYPES = ["audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/flac", "audio/ogg", "audio/x-vorbis+ogg",
              "audio/x-opus+ogg", "audio/x-wav", "audio/aac", "audio/x-aiff"]


class Mpris:
    def __init__(self, app):
        self.app = app
        self.connection = None
        self.track_ids = {}
        Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE,
                         self._acquired, None, None)

    def _acquired(self, connection, _name):
        self.connection = connection
        info = Gio.DBusNodeInfo.new_for_xml(MPRIS_XML)
        for iface in info.interfaces:
            connection.register_object(MPRIS_PATH, iface, self._call, self._get, self._set)

    @property
    def player(self):
        return self.app.player

    def track_id(self, song):
        if song is None:
            return "/org/mpris/MediaPlayer2/TrackList/NoTrack"
        key = song["path"]
        if key not in self.track_ids:
            self.track_ids[key] = f"/org/freemac/Shanty/track/{len(self.track_ids) + 1}"
        return self.track_ids[key]

    def metadata(self):
        song = self.player.song
        meta = {"mpris:trackid": GLib.Variant("o", self.track_id(song))}
        if song is None:
            return meta
        meta.update({
            "xesam:title": GLib.Variant("s", song["title"]),
            "xesam:artist": GLib.Variant("as", [song["artist"]]),
            "xesam:album": GLib.Variant("s", song["album"]),
            "xesam:albumArtist": GLib.Variant("as", [song["album_artist"]]),
            "xesam:url": GLib.Variant("s", store.uri(song["path"])),
            "mpris:length": GLib.Variant("x", int((song.get("duration") or 0) * 1_000_000)),
        })
        if song.get("track"):
            meta["xesam:trackNumber"] = GLib.Variant("i", int(song["track"]))
        cover = self.app.cover_of(song)
        if cover:
            meta["mpris:artUrl"] = GLib.Variant("s", store.uri(cover))
        return meta

    def _value(self, iface, name):
        p = self.player
        if iface == ROOT_IFACE:
            return {
                "CanQuit": GLib.Variant("b", True), "CanRaise": GLib.Variant("b", True),
                "HasTrackList": GLib.Variant("b", False), "Identity": GLib.Variant("s", "Shanty"),
                "DesktopEntry": GLib.Variant("s", "freemac-shanty"),
                "SupportedUriSchemes": GLib.Variant("as", ["file"]),
                "SupportedMimeTypes": GLib.Variant("as", MIME_TYPES),
            }.get(name)
        values = {
            "PlaybackStatus": lambda: GLib.Variant("s", p.status),
            "LoopStatus": lambda: GLib.Variant("s", LOOPS[p.repeat]),
            "Rate": lambda: GLib.Variant("d", 1.0),
            "Shuffle": lambda: GLib.Variant("b", p.shuffle),
            "Metadata": lambda: GLib.Variant("a{sv}", self.metadata()),
            "Volume": lambda: GLib.Variant("d", p.volume),
            "Position": lambda: GLib.Variant("x", int(p.position() * 1_000_000)),
            "MinimumRate": lambda: GLib.Variant("d", 1.0),
            "MaximumRate": lambda: GLib.Variant("d", 1.0),
            "CanGoNext": lambda: GLib.Variant("b", p.has_next()),
            "CanGoPrevious": lambda: GLib.Variant("b", p.has_previous()),
            "CanPlay": lambda: GLib.Variant("b", p.can_play() and (p.song is not None or bool(self.app.songs))),
            "CanPause": lambda: GLib.Variant("b", p.can_play()),
            "CanSeek": lambda: GLib.Variant("b", p.song is not None),
            "CanControl": lambda: GLib.Variant("b", True),
        }
        found = values.get(name)
        return found() if found else None

    def _get(self, _conn, _sender, _path, iface, name):
        return self._value(iface, name)

    def _set(self, _conn, _sender, _path, iface, name, value):
        if iface != PLAYER_IFACE:
            return False
        value = value.unpack()
        if name == "LoopStatus":
            mode = {v: k for k, v in LOOPS.items()}.get(value, "off")
            GLib.idle_add(lambda: self.app.set_repeat(mode) and False)
        elif name == "Shuffle":
            GLib.idle_add(lambda: self.app.set_shuffle(bool(value)) and False)
        elif name == "Volume":
            GLib.idle_add(lambda: self.app.set_volume(float(value)) and False)
        return True

    def _call(self, _conn, _sender, _path, iface, method, params, invocation):
        app, p = self.app, self.player
        if iface == ROOT_IFACE:
            if method == "Raise":
                app.activate()
            elif method == "Quit":
                GLib.idle_add(app.quit)
        else:
            args = params.unpack()
            if method == "PlayPause":
                app.play_pause()
            elif method == "Play":
                app.play()
            elif method == "Pause":
                p.pause()
            elif method == "Stop":
                p.stop()
            elif method == "Next":
                p.next()
            elif method == "Previous":
                p.previous()
            elif method == "Seek":
                p.seek(p.position() + args[0] / 1_000_000)
            elif method == "SetPosition":
                if args[0] == self.track_id(p.song):
                    p.seek(args[1] / 1_000_000)
            elif method == "OpenUri":
                path = Gio.File.new_for_uri(args[0]).get_path()
                if path:
                    app.open_paths([path])
        invocation.return_value(None)

    def changed(self, *names):
        if self.connection is None:
            return
        values = {}
        for name in names:
            value = self._value(PLAYER_IFACE, name)
            if value is not None:
                values[name] = value
        try:
            self.connection.emit_signal(None, MPRIS_PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                        GLib.Variant("(sa{sv}as)", (PLAYER_IFACE, values, [])))
        except GLib.Error:
            pass

    def seeked(self):
        if self.connection is None:
            return
        try:
            self.connection.emit_signal(None, MPRIS_PATH, PLAYER_IFACE, "Seeked",
                                        GLib.Variant("(x)", (int(self.player.position() * 1_000_000),)))
        except GLib.Error:
            pass


# --- the window ------------------------------------------------------------------

class AlbumTile(Gtk.FlowBoxChild):
    def __init__(self, album):
        super().__init__()
        self.album = album
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_start(6)
        box.set_margin_end(6)
        box.set_margin_top(6)
        box.set_margin_bottom(8)
        box.pack_start(cover_area(album["key"], album["cover"], TILE), False, False, 4)
        title = Gtk.Label(label=album["title"], xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=1)
        title.set_size_request(TILE, -1)
        title.get_style_context().add_class("shanty-tile-title")
        artist = Gtk.Label(label=album["artist"], xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=1)
        artist.set_size_request(TILE, -1)
        artist.get_style_context().add_class("shanty-tile-artist")
        box.pack_start(title, False, False, 0)
        box.pack_start(artist, False, False, 0)
        self.add(box)
        self.set_tooltip_text(f"{album['title']}\n{album['artist']}")


class SongRow(Gtk.ListBoxRow):
    def __init__(self, song, number, show_artist):
        super().__init__()
        self.song = song
        box = Gtk.Box(spacing=12)
        self.number = Gtk.Label(label=str(number) if number else "", xalign=1, width_chars=3)
        self.number.get_style_context().add_class("shanty-number")
        self.icon = Gtk.Image.new_from_icon_name("audio-volume-high-symbolic", Gtk.IconSize.MENU)
        self.icon.set_no_show_all(True)
        self.icon.set_size_request(30, -1)
        lead = Gtk.Box()
        lead.set_size_request(30, -1)
        lead.pack_start(self.number, True, True, 0)
        lead.pack_start(self.icon, True, True, 0)
        box.pack_start(lead, False, False, 0)
        self.title = Gtk.Label(label=song["title"], xalign=0, ellipsize=Pango.EllipsizeMode.END)
        box.pack_start(self.title, True, True, 0)
        if show_artist:
            artist = Gtk.Label(label=song["artist"], xalign=0, ellipsize=Pango.EllipsizeMode.END,
                               width_chars=18, max_width_chars=26)
            artist.get_style_context().add_class("shanty-dim")
            box.pack_start(artist, False, False, 0)
        length = Gtk.Label(label=store.clock(song.get("duration")), xalign=1, width_chars=6)
        length.get_style_context().add_class("shanty-number")
        box.pack_start(length, False, False, 0)
        self.add(box)

    def mark(self, playing):
        self.number.set_visible(not playing)
        self.icon.set_visible(playing)
        ctx = self.title.get_style_context()
        (ctx.add_class if playing else ctx.remove_class)("shanty-playing-title")
        self.icon.get_style_context().add_class("shanty-on")


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Shanty")
        self.app = app
        self.set_default_size(1080, 720)
        self.set_icon_name("freemac-shanty")
        self.view = "albums"
        self.album_shown = None
        self.artist_shown = None
        self.song_rows = []
        self.dragging_bar = False
        self.search_words = []

        header = Gtk.HeaderBar(show_close_button=True)
        self.back = self._flat("go-previous-symbolic", "Back", self.go_back)
        self.back.set_no_show_all(True)
        header.pack_start(self.back)
        controls = Gtk.Box(spacing=2)
        self.shuffle_button = Gtk.ToggleButton()
        self.shuffle_button.add(Gtk.Image(icon_name="media-playlist-shuffle-symbolic", visible=True))
        self.shuffle_button.set_relief(Gtk.ReliefStyle.NONE)
        self.shuffle_button.set_tooltip_text("Shuffle")
        self.shuffle_handler = self.shuffle_button.connect("toggled", lambda b: app.set_shuffle(b.get_active()))
        self.previous_button = self._flat("media-skip-backward-symbolic", "Previous (⌘←)", app.player.previous)
        self.play_button = self._flat("media-playback-start-symbolic", "Play (Space)", app.play_pause)
        self.play_button.icon.set_pixel_size(24)
        self.next_button = self._flat("media-skip-forward-symbolic", "Next (⌘→)", app.player.next)
        self.repeat_button = self._flat("media-playlist-repeat-symbolic", "Repeat", app.cycle_repeat)
        for widget in (self.shuffle_button, self.previous_button, self.play_button, self.next_button,
                       self.repeat_button):
            controls.pack_start(widget, False, False, 0)
        header.pack_start(controls)

        self.lcd_stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.lcd_stack.get_style_context().add_class("shanty-lcd")
        self.lcd_stack.set_size_request(440, 44)
        idle = Gtk.Image.new_from_icon_name("freemac-shanty", Gtk.IconSize.DND)
        idle.set_pixel_size(26)
        idle.set_opacity(0.55)
        self.lcd_stack.add_named(idle, "idle")
        lcd = Gtk.Box(spacing=8)
        self.lcd_cover = Gtk.DrawingArea()
        self.lcd_cover.set_size_request(38, 38)
        self.lcd_cover.set_valign(Gtk.Align.CENTER)
        self.lcd_cover.connect("draw", self._draw_lcd_cover)
        lcd.pack_start(self.lcd_cover, False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.lcd_title = Gtk.Label(xalign=0.5, ellipsize=Pango.EllipsizeMode.END)
        self.lcd_title.get_style_context().add_class("shanty-lcd-title")
        self.lcd_sub = Gtk.Label(xalign=0.5, ellipsize=Pango.EllipsizeMode.END)
        self.lcd_sub.get_style_context().add_class("shanty-lcd-sub")
        bar_row = Gtk.Box(spacing=6)
        self.elapsed = Gtk.Label(label="", width_chars=5, xalign=1)
        self.remaining = Gtk.Label(label="", width_chars=6, xalign=0)
        for label in (self.elapsed, self.remaining):
            label.get_style_context().add_class("shanty-lcd-time")
        self.bar = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 1)
        self.bar.set_draw_value(False)
        self.bar.connect("button-press-event", self._bar_pressed)
        self.bar.connect("button-release-event", self._bar_released)
        self.bar.connect("change-value", self._bar_moved)
        bar_row.pack_start(self.elapsed, False, False, 0)
        bar_row.pack_start(self.bar, True, True, 0)
        bar_row.pack_start(self.remaining, False, False, 0)
        words.pack_start(self.lcd_title, False, False, 0)
        words.pack_start(self.lcd_sub, False, False, 0)
        words.pack_start(bar_row, False, False, 0)
        lcd.pack_start(words, True, True, 0)
        self.lcd_stack.add_named(lcd, "playing")
        self.lcd_stack.show_all()
        self.lcd_stack.set_visible_child_name("idle")
        header.set_custom_title(self.lcd_stack)

        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.set_width_chars(16)
        self.search.connect("search-changed", self._searched)
        header.pack_end(self.search)
        self.volume = Gtk.VolumeButton()
        self.volume.set_value(app.player.volume)
        self.volume_handler = self.volume.connect("value-changed", lambda _b, v: app.set_volume(v))
        header.pack_end(self.volume)
        self.set_titlebar(header)

        paned = Gtk.Paned()
        side_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side_scroll.get_style_context().add_class("shanty-side")
        side_scroll.set_size_request(190, -1)
        self.sidebar = Gtk.ListBox()
        self.sidebar.get_style_context().add_class("shanty-side")
        self.sidebar.set_header_func(self._side_header)
        self.side_rows = {}
        for key, label, icon in (("recent", "Recently Added", "document-open-recent-symbolic"),
                                 ("artists", "Artists", "avatar-default-symbolic"),
                                 ("albums", "Albums", "media-optical-symbolic"),
                                 ("songs", "Songs", "audio-x-generic-symbolic")):
            row = Gtk.ListBoxRow()
            row.key = key
            box = Gtk.Box(spacing=8)
            box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
            box.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
            row.add(box)
            self.sidebar.add(row)
            self.side_rows[key] = row
        self.sidebar.connect("row-selected", self._side_selected)
        side_scroll.add(self.sidebar)
        paned.pack1(side_scroll, False, False)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        self.pages = {}
        for name in ("albums", "album", "songs"):
            scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
            scroll.get_style_context().add_class("shanty-page")
            self.pages[name] = scroll
            self.stack.add_named(scroll, name)
        self.artist_list = Gtk.ListBox()
        self.artist_list.get_style_context().add_class("shanty-side")
        self.artist_list.connect("row-selected", self._artist_selected)
        artists_box = Gtk.Paned()
        left = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        left.set_size_request(200, -1)
        left.get_style_context().add_class("shanty-page")
        left.add(self.artist_list)
        artists_box.pack1(left, False, False)
        self.artist_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.artist_scroll.get_style_context().add_class("shanty-page")
        artists_box.pack2(self.artist_scroll, True, False)
        self.pages["artists"] = artists_box
        self.stack.add_named(artists_box, "artists")
        self._make_songs_page()
        self._make_empty_pages()
        paned.pack2(self.stack, True, False)
        self.add(paned)

        self.drag_dest_set(Gtk.DestDefaults.ALL, [Gtk.TargetEntry.new("text/uri-list", 0, 0)],
                           Gdk.DragAction.COPY)
        self.connect("drag-data-received", self._dropped)
        self.connect("key-press-event", self._key)
        menus.add_actions(self, {
            "close": self.close, "find": self.search.grab_focus,
            "recent": lambda: self.choose("recent"), "artists": lambda: self.choose("artists"),
            "albums": lambda: self.choose("albums"), "songs": lambda: self.choose("songs"),
            "show-folder": self.show_in_drawer, "add": self.add_from_chooser,
            "go-to-playing": self.go_to_playing,
        })
        self.show_all()
        self.sidebar.select_row(self.side_rows["albums"])
        GLib.timeout_add(250, self._tick)

    def _flat(self, icon, tip, callback):
        button = Gtk.Button()
        button.icon = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
        button.add(button.icon)
        button.icon.show()
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_tooltip_text(tip)
        button.connect("clicked", lambda *_: callback())
        return button

    def _side_header(self, row, before):
        if before is None:
            label = Gtk.Label(label="Library", xalign=0)
            label.get_style_context().add_class("shanty-side-head")
            row.set_header(label)

    def _make_songs_page(self):
        # path, title, artist, album, time, length (for sorting), weight, track sort key
        self.song_store = Gtk.ListStore(str, str, str, str, str, float, int, str)
        self.song_filter = self.song_store.filter_new()
        self.song_filter.set_visible_func(self._song_visible)
        self.song_sorted = Gtk.TreeModelSort(model=self.song_filter)
        # By artist, an artist's songs come album by album, in track order.
        self.song_sorted.set_sort_func(2, self._by_artist)
        tree = Gtk.TreeView(model=self.song_sorted, headers_clickable=True, enable_search=False)
        tree.get_style_context().add_class("shanty-tree")
        tree.set_rubber_banding(True)
        tree.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        for at, (title, column, width, sort) in enumerate((("Title", 1, 280, 1), ("Artist", 2, 180, 2),
                                                           ("Album", 3, 200, 7), ("Time", 4, 60, 5))):
            cell = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.END)
            if title == "Time":
                cell.set_property("xalign", 1)
            col = Gtk.TreeViewColumn(title, cell, text=column, weight=6)
            col.set_resizable(True)
            col.set_expand(title != "Time")
            col.set_min_width(width // 2)
            col.set_fixed_width(width)
            col.set_sort_column_id(sort)
            tree.append_column(col)
        tree.connect("row-activated", self._song_activated)
        tree.connect("button-press-event", self._song_button)
        self.song_tree = tree
        self.pages["songs"].add(tree)

    @staticmethod
    def _by_artist(model, a, b, _data=None):
        one = ((model[a][2] or "").lower(), model[a][7] or "")
        two = ((model[b][2] or "").lower(), model[b][7] or "")
        return (one > two) - (one < two)

    def _make_empty_pages(self):
        empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        empty.get_style_context().add_class("shanty-page")
        icon = Gtk.Image.new_from_icon_name("audio-x-generic-symbolic", Gtk.IconSize.DIALOG)
        icon.set_pixel_size(64)
        icon.set_opacity(0.3)
        self.empty_title = Gtk.Label()
        self.empty_title.get_style_context().add_class("shanty-empty-title")
        self.empty_text = Gtk.Label(wrap=True, max_width_chars=50, justify=Gtk.Justification.CENTER)
        self.empty_text.get_style_context().add_class("shanty-empty-text")
        for widget in (icon, self.empty_title, self.empty_text):
            empty.pack_start(widget, False, False, 0)
        self.stack.add_named(empty, "empty")
        busy = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER)
        busy.get_style_context().add_class("shanty-page")
        spinner = Gtk.Spinner(active=True)
        spinner.set_size_request(32, 32)
        self.busy_label = Gtk.Label()
        self.busy_label.get_style_context().add_class("shanty-empty-text")
        self.busy_bar = Gtk.ProgressBar(halign=Gtk.Align.CENTER)
        self.busy_bar.set_size_request(260, -1)
        for widget in (spinner, self.busy_label, self.busy_bar):
            busy.pack_start(widget, False, False, 0)
        self.stack.add_named(busy, "busy")

    # showing the library

    def library_changed(self):
        self.song_store.clear()
        for song in self.app.songs:
            self.song_store.append([song["path"], song["title"], song["artist"], song["album"],
                                    store.clock(song.get("duration")), song.get("duration") or 0, 400,
                                    f"{song['album'].lower()}\x1f{song['disc']:03d}{song['track'] or 999:04d}"])
        self.song_sorted.set_sort_column_id(2, Gtk.SortType.ASCENDING)
        self.artist_list.foreach(lambda w: w.destroy())
        for name in self.app.artists:
            row = Gtk.ListBoxRow()
            row.artist = name
            label = Gtk.Label(label=name, xalign=0, ellipsize=Pango.EllipsizeMode.END)
            label.set_margin_top(3)
            label.set_margin_bottom(3)
            row.add(label)
            self.artist_list.add(row)
        self.artist_list.show_all()
        if self.album_shown is not None:
            again = next((a for a in self.app.albums if a["key"] == self.album_shown["key"]), None)
            self.album_shown = again
        self.show_view()
        self.mark_playing()

    def show_busy(self, done, total):
        if self.app.songs:
            return
        self.busy_label.set_text(f"Reading your music… {done} of {total}")
        self.busy_bar.set_fraction(done / total if total else 0)
        self.stack.set_visible_child_name("busy")

    def choose(self, view):
        row = self.side_rows.get(view)
        if row is not None and self.sidebar.get_selected_row() is not row:
            self.sidebar.select_row(row)
        else:
            self.view = view
            self.album_shown = None
            self.show_view()

    def _side_selected(self, _box, row):
        if row is None:
            return
        self.view = row.key
        self.album_shown = None
        if self.search.get_text():
            self.search.set_text("")
        self.show_view()

    def show_view(self):
        if not self.app.songs:
            if self.app.scanning:
                return
            self.empty_title.set_text("No music yet")
            self.empty_text.set_text("Put songs in the Music folder in your home folder, "
                                     "or drag them here to copy them in.")
            self.stack.set_visible_child_name("empty")
            self.back.hide()
            return
        if self.album_shown is not None:
            self._show_album(self.album_shown)
            return
        self.back.hide()
        if self.search_words:
            self._show_search()
        elif self.view == "recent":
            found = store.recent(self.app.albums)
            self._show_albums("Recently Added", found or sorted(self.app.albums, key=lambda a: -a["added"])[:24])
        elif self.view == "artists":
            self.stack.set_visible_child_name("artists")
            if self.artist_list.get_selected_row() is None:
                first = self.artist_list.get_row_at_index(0)
                if first is not None:
                    self.artist_list.select_row(first)
            else:
                self._artist_selected(self.artist_list, self.artist_list.get_selected_row())
        elif self.view == "songs":
            self.song_filter.refilter()
            self.stack.set_visible_child_name("songs")
        else:
            self._show_albums("Albums", self.app.albums)

    def _page_box(self, name):
        scroll = self.pages[name] if name != "artist" else self.artist_scroll
        child = scroll.get_child()
        if child is not None:
            scroll.remove(child)
            child.destroy()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_margin_start(24)
        box.set_margin_end(24)
        box.set_margin_top(18)
        box.set_margin_bottom(24)
        scroll.add(box)
        return box

    def _album_flow(self, albums):
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.SINGLE, homogeneous=True, column_spacing=6,
                           row_spacing=6, max_children_per_line=12, valign=Gtk.Align.START)
        flow.set_activate_on_single_click(True)
        for album in albums:
            flow.add(AlbumTile(album))
        flow.connect("child-activated", lambda _f, tile: self.open_album(tile.album))
        flow.connect("button-press-event", self._album_button)
        return flow

    def _show_albums(self, title, albums):
        box = self._page_box("albums")
        heading = Gtk.Label(label=title, xalign=0)
        heading.get_style_context().add_class("shanty-title")
        box.pack_start(heading, False, False, 0)
        box.pack_start(self._album_flow(albums), False, False, 0)
        box.show_all()
        self.stack.set_visible_child_name("albums")

    def _show_search(self):
        words = self.search_words
        box = self._page_box("albums")
        albums = [a for a in self.app.albums
                  if all(w in (a["title"] + " " + a["artist"]).lower() for w in words)]
        songs = [s for s in self.app.songs if store.matches(s, words)]
        if not albums and not songs:
            label = Gtk.Label(label=f"Nothing matches “{self.search.get_text()}”.", xalign=0)
            label.get_style_context().add_class("shanty-empty-text")
            box.pack_start(label, False, False, 0)
        if albums:
            heading = Gtk.Label(label="Albums", xalign=0)
            heading.get_style_context().add_class("shanty-title")
            box.pack_start(heading, False, False, 0)
            box.pack_start(self._album_flow(albums[:24]), False, False, 0)
        if songs:
            heading = Gtk.Label(label="Songs", xalign=0)
            heading.get_style_context().add_class("shanty-title")
            box.pack_start(heading, False, False, 6)
            box.pack_start(self._song_list(songs[:200], show_artist=True, numbers=False), False, False, 0)
        box.show_all()
        self.mark_playing()
        self.stack.set_visible_child_name("albums")

    def _song_list(self, songs, show_artist, numbers=True):
        listing = Gtk.ListBox(activate_on_single_click=False)
        listing.get_style_context().add_class("shanty-songs")
        for song in songs:
            row = SongRow(song, song.get("track") if numbers else 0, show_artist)
            listing.add(row)
            self.song_rows.append(row)
        listing.connect("row-activated", lambda lb, row: self._row_activated(lb, row))
        listing.connect("button-press-event", self._list_button)
        return listing

    def _row_activated(self, listing, row):
        songs = [r.song for r in listing.get_children()]
        self.app.player.play_songs(songs, songs.index(row.song))

    def open_album(self, album):
        self.album_shown = album
        self._show_album(album)

    def _show_album(self, album):
        self.song_rows = [r for r in self.song_rows if r.get_parent() is not None]
        box = self._page_box("album")
        top = Gtk.Box(spacing=24)
        top.pack_start(cover_area(album["key"], album["cover"], BIG_COVER, 8), False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.END)
        title = Gtk.Label(label=album["title"], xalign=0, wrap=True, max_width_chars=40)
        title.get_style_context().add_class("shanty-album-title")
        artist = Gtk.Label(label=album["artist"], xalign=0, wrap=True)
        artist.get_style_context().add_class("shanty-album-artist")
        facts = " · ".join(x for x in (album.get("genre", "").upper(), str(album["year"]) if album["year"] else "")
                           if x)
        about = Gtk.Label(label=facts, xalign=0)
        about.get_style_context().add_class("shanty-dim")
        buttons = Gtk.Box(spacing=10)
        buttons.set_margin_top(14)
        play = Gtk.Button(label=" Play", image=Gtk.Image.new_from_icon_name("media-playback-start-symbolic",
                                                                            Gtk.IconSize.BUTTON),
                          always_show_image=True)
        play.get_style_context().add_class("shanty-play-button")
        play.connect("clicked", lambda *_: self.app.player.play_songs(album["songs"], 0, shuffle=False))
        shuffle = Gtk.Button(label=" Shuffle", image=Gtk.Image.new_from_icon_name(
            "media-playlist-shuffle-symbolic", Gtk.IconSize.BUTTON), always_show_image=True)
        shuffle.get_style_context().add_class("shanty-light-button")
        shuffle.connect("clicked", lambda *_: self.app.player.play_songs(album["songs"], 0, shuffle=True))
        buttons.pack_start(play, False, False, 0)
        buttons.pack_start(shuffle, False, False, 0)
        for widget in (title, artist, about, buttons):
            words.pack_start(widget, False, False, 0)
        top.pack_start(words, True, True, 0)
        box.pack_start(top, False, False, 0)
        various = len({s["artist"] for s in album["songs"]}) > 1
        discs = sorted({s.get("disc", 1) for s in album["songs"]})
        for disc in discs:
            members = [s for s in album["songs"] if s.get("disc", 1) == disc]
            if len(discs) > 1:
                label = Gtk.Label(label=f"Disc {disc}", xalign=0)
                label.get_style_context().add_class("shanty-side-head")
                box.pack_start(label, False, False, 4)
            box.pack_start(self._song_list(members, various), False, False, 6 if len(discs) == 1 else 0)
        summary = Gtk.Label(label=f"{plural(len(album['songs']), 'song')}, "
                                  f"{store.length_words(album['duration'])}", xalign=0)
        summary.get_style_context().add_class("shanty-dim")
        box.pack_start(summary, False, False, 4)
        box.show_all()
        self.back.show()
        self.stack.set_visible_child_name("album")
        self.mark_playing()

    def go_back(self):
        self.album_shown = None
        self.show_view()

    def _artist_selected(self, _box, row):
        if row is None:
            return
        self.artist_shown = row.artist
        box = self._page_box("artist")
        heading = Gtk.Label(label=row.artist, xalign=0, ellipsize=Pango.EllipsizeMode.END)
        heading.get_style_context().add_class("shanty-title")
        box.pack_start(heading, False, False, 0)
        albums = self.app.artists.get(row.artist, [])
        count = sum(len(a["songs"]) for a in albums)
        line = Gtk.Box(spacing=10)
        sub = Gtk.Label(label=f"{plural(len(albums), 'album')}, {plural(count, 'song')}", xalign=0)
        sub.get_style_context().add_class("shanty-dim")
        line.pack_start(sub, False, False, 0)
        shuffle = Gtk.Button(label=" Shuffle", image=Gtk.Image.new_from_icon_name(
            "media-playlist-shuffle-symbolic", Gtk.IconSize.BUTTON), always_show_image=True)
        shuffle.get_style_context().add_class("shanty-light-button")
        every = [s for a in albums for s in a["songs"]]
        shuffle.connect("clicked", lambda *_: self.app.player.play_songs(every, 0, shuffle=True))
        line.pack_end(shuffle, False, False, 0)
        box.pack_start(line, False, False, 0)
        box.pack_start(self._album_flow(albums), False, False, 6)
        box.show_all()

    def _song_visible(self, model, it, _data):
        if not self.search_words:
            return True
        text = " ".join((model[it][1], model[it][2], model[it][3])).lower()
        return all(w in text for w in self.search_words)

    def _song_activated(self, tree, path, _column):
        model = tree.get_model()
        paths = [row[0] for row in model]
        by_path = self.app.by_path
        songs = [by_path[p] for p in paths if p in by_path]
        chosen = model[path][0]
        index = next((i for i, s in enumerate(songs) if s["path"] == chosen), 0)
        self.app.player.play_songs(songs, index)

    def _searched(self, entry):
        self.search_words = entry.get_text().lower().split()
        self.album_shown = None
        if self.view == "songs":
            self.song_filter.refilter()
            self.stack.set_visible_child_name("songs")
        else:
            self.show_view()

    # menus on songs and albums

    def _popup(self, event, entries):
        menu = Gtk.Menu()
        for label, callback in entries:
            if label is None:
                menu.append(Gtk.SeparatorMenuItem())
                continue
            item = Gtk.MenuItem(label=label)
            item.connect("activate", lambda _i, c=callback: c())
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self, None)
        menu.popup_at_pointer(event)

    def _song_menu(self, event, songs):
        self._popup(event, [("Play", lambda: self.app.player.play_songs(songs, 0, shuffle=False)),
                            ("Play Next", lambda: self.app.player.play_next(songs)),
                            (None, None),
                            ("Show in Drawer", lambda: self.show_in_drawer(songs[0]["path"]))])

    def _list_button(self, listing, event):
        if event.button != 3:
            return False
        row = listing.get_row_at_y(int(event.y))
        if row is None:
            return False
        listing.select_row(row)
        self._song_menu(event, [row.song])
        return True

    def _song_button(self, tree, event):
        if event.button != 3:
            return False
        found = tree.get_path_at_pos(int(event.x), int(event.y))
        if found is None:
            return False
        selection = tree.get_selection()
        if not selection.path_is_selected(found[0]):
            selection.unselect_all()
            selection.select_path(found[0])
        model, paths = selection.get_selected_rows()
        songs = [self.app.by_path[model[p][0]] for p in paths if model[p][0] in self.app.by_path]
        if songs:
            self._song_menu(event, songs)
        return True

    def _album_button(self, flow, event):
        if event.button != 3:
            return False
        tile = flow.get_child_at_pos(int(event.x), int(event.y))
        if tile is None:
            return False
        flow.select_child(tile)
        album = tile.album
        self._popup(event, [("Play", lambda: self.app.player.play_songs(album["songs"], 0, shuffle=False)),
                            ("Shuffle", lambda: self.app.player.play_songs(album["songs"], 0, shuffle=True)),
                            ("Play Next", lambda: self.app.player.play_next(album["songs"])),
                            (None, None),
                            ("Show in Drawer", lambda: self.show_in_drawer(album["songs"][0]["path"]))])
        return True

    # what's playing

    def mark_playing(self):
        song = self.app.player.song
        path = song["path"] if song else None
        self.song_rows = [r for r in self.song_rows if r.get_parent() is not None]
        for row in self.song_rows:
            row.mark(row.song["path"] == path)
        for row in self.song_store:
            row[6] = 700 if row[0] == path else 400

    def player_changed(self, what):
        p = self.app.player
        if what in ("song", "queue"):
            song = p.song
            self.lcd_stack.set_visible_child_name("idle" if song is None else "playing")
            if song is None:
                self.lcd_title.set_text("")
                self.lcd_sub.set_text("")
            else:
                self.lcd_title.set_text(song["title"])
                self.lcd_sub.set_text(f"{song['artist']} — {song['album']}")
            self.lcd_cover.queue_draw()
            self.mark_playing()
            self.next_button.set_sensitive(p.has_next())
            self.previous_button.set_sensitive(p.song is not None)
            self._tick()
        if what in ("status", "song"):
            playing = p.status == "Playing"
            self.play_button.icon.set_from_icon_name(
                "media-playback-pause-symbolic" if playing else "media-playback-start-symbolic",
                Gtk.IconSize.BUTTON)
            self.play_button.set_tooltip_text("Pause (Space)" if playing else "Play (Space)")
        if what == "queue":
            self.shuffle_button.handler_block(self.shuffle_handler)
            self.shuffle_button.set_active(p.shuffle)
            self.shuffle_button.handler_unblock(self.shuffle_handler)
            ctx = self.shuffle_button.get_style_context()
            (ctx.add_class if p.shuffle else ctx.remove_class)("shanty-on")
            ctx = self.repeat_button.get_style_context()
            (ctx.add_class if p.repeat != "off" else ctx.remove_class)("shanty-on")
            self.repeat_button.icon.set_from_icon_name(
                "media-playlist-repeat-song-symbolic" if p.repeat == "one" else "media-playlist-repeat-symbolic",
                Gtk.IconSize.BUTTON)
            self.repeat_button.set_tooltip_text({"off": "Repeat: Off", "all": "Repeat: All",
                                                 "one": "Repeat: One"}[p.repeat])
        if what == "seeked":
            self._tick()

    def volume_changed(self, value):
        self.volume.handler_block(self.volume_handler)
        self.volume.set_value(value)
        self.volume.handler_unblock(self.volume_handler)

    def _draw_lcd_cover(self, area, cr):
        song = self.app.player.song
        if song is None:
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.15)
            _rounded(cr, 0, 0, 38, 38, 4)
            cr.fill()
            return
        album = self.app.album_of(song)
        draw_cover(area, cr, album["key"] if album else song["path"], self.app.cover_of(song), 38, 4)

    def _tick(self):
        p = self.app.player
        if p.song is None:
            self.bar.set_sensitive(False)
            self.bar.set_range(0, 1)
            self.bar.set_value(0)
            self.elapsed.set_text("")
            self.remaining.set_text("")
            return True
        length = p.duration() or 1
        if not self.dragging_bar:
            at = p.position()
            self.bar.set_sensitive(True)
            self.bar.set_range(0, max(length, 1))
            self.bar.set_value(min(at, length))
            self.elapsed.set_text(store.clock(at))
            self.remaining.set_text("−" + store.clock(max(0, length - at)))
        return True

    def _bar_pressed(self, *_):
        self.dragging_bar = True
        return False

    def _bar_released(self, *_):
        self.dragging_bar = False
        self.app.player.seek(self.bar.get_value())
        return False

    def _bar_moved(self, _scale, _scroll, value):
        length = self.app.player.duration()
        self.elapsed.set_text(store.clock(value))
        self.remaining.set_text("−" + store.clock(max(0, length - value)))
        if not self.dragging_bar:
            self.app.player.seek(value)
        return False

    def go_to_playing(self):
        song = self.app.player.song
        album = self.app.album_of(song) if song else None
        if album:
            self.open_album(album)

    # files

    def show_in_drawer(self, path=None):
        """Drawer, with the song chosen in its folder (or the Music folder)."""
        target = path or (self.app.player.song or {}).get("path") or store.music_dir()
        try:
            subprocess.Popen(["freemac-drawer", target], start_new_session=True)
        except OSError:
            pass

    def _dropped(self, _w, _ctx, _x, _y, data, _info, _time):
        paths = [Gio.File.new_for_uri(u).get_path() for u in data.get_uris() or []]
        self.add_files([p for p in paths if p])

    def add_files(self, paths):
        root = store.music_dir()
        wanted = [p for p in paths if (os.path.isdir(p) or store.is_audio(p))
                  and not transfer.inside(p, root)]
        if not wanted:
            if paths:
                alert.tell(self, "There’s nothing to add.",
                           "Only songs, and folders with songs in them, can be added to the Music folder.")
            return
        os.makedirs(root, exist_ok=True)
        transfer.Job(wanted, root, move=False, parent=self, done=lambda _job: self.app.rescan()).start()

    def add_from_chooser(self):
        chooser = Gtk.FileChooserNative.new("Add to Library", self, Gtk.FileChooserAction.OPEN, "Add", None)
        chooser.set_select_multiple(True)
        audio = Gtk.FileFilter()
        audio.set_name("Music")
        for ending in sorted(store.AUDIO_ENDINGS):
            audio.add_pattern("*" + ending)
            audio.add_pattern("*" + ending.upper())
        chooser.add_filter(audio)
        if chooser.run() == Gtk.ResponseType.ACCEPT:
            self.add_files(chooser.get_filenames())
        chooser.destroy()

    def _key(self, _w, event):
        if self.search.has_focus():
            if event.keyval == Gdk.KEY_Escape:
                self.search.set_text("")
                self.sidebar.grab_focus()
                return True
            return False
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        if event.keyval == Gdk.KEY_space and not mods:
            self.app.play_pause()
            return True
        if event.keyval == Gdk.KEY_Escape and self.album_shown is not None:
            self.go_back()
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("Add to Library…", "win.add", "<Ctrl>o")],
                   [("Show in Drawer", "win.show-folder", "<Ctrl>r")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Find", "win.find", "<Ctrl>f")]]),
        ("_Song", [[("Go to Current Song", "win.go-to-playing", "<Ctrl>l")]]),
        ("_View", [[("Recently Added", "win.recent", "<Ctrl>1"), ("Artists", "win.artists", "<Ctrl>2"),
                    ("Albums", "win.albums", "<Ctrl>3"), ("Songs", "win.songs", "<Ctrl>4")]]),
        ("_Controls", [[("Play", "app.play-pause", None), ("Next", "app.next", "<Ctrl>Right"),
                        ("Previous", "app.previous", "<Ctrl>Left")],
                       [("Shuffle", "app.shuffle", None), ("Repeat", "app.cycle-repeat", None)],
                       [("Increase Volume", "app.louder", "<Ctrl>Up"),
                        ("Decrease Volume", "app.quieter", "<Ctrl>Down")]]),
    ])


class Shanty(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)
        self.songs, self.albums, self.artists, self.by_path = [], [], {}, {}
        self.album_by_key = {}
        self.scanning = False
        self.last_scan = 0
        self.player = None
        self.mpris = None
        self.window = None
        self.pending_paths = []
        self.restored = False

    def do_startup(self):
        Gtk.Application.do_startup(self)
        global COVERS
        COVERS = Covers()
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.player = Player(self._player_changed)
        state = store.load_state()
        self.player.shuffle = bool(state.get("shuffle"))
        self.player.repeat = state.get("repeat") if state.get("repeat") in REPEATS else "off"
        self.player.set_volume(float(state.get("volume", 0.7)))
        menus.add_actions(self, {
            "quit": lambda: GLib.idle_add(self.quit), "play-pause": self.play_pause,
            "next": self.player.next, "previous": self.player.previous,
            "shuffle": lambda: self.set_shuffle(not self.player.shuffle), "cycle-repeat": self.cycle_repeat,
            "louder": lambda: self.set_volume(self.player.volume + 0.1),
            "quieter": lambda: self.set_volume(self.player.volume - 0.1),
        })
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.hold()   # keeps playing with no window, as a Mac app does; Quit ends it
        self.set_menubar(menubar())
        self.mpris = Mpris(self)
        self.connect("shutdown", lambda *_: self._save())
        GLib.timeout_add_seconds(15, lambda: self._save() or True)
        self.rescan()

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda *_: setattr(self, "window", None))
            self.window.connect("notify::is-active", self._activated)
            if self.songs:
                self.window.library_changed()
            elif self.scanning:
                self.window.show_busy(0, 0)
            self._player_changed("queue")
            self._player_changed("status")
        self.window.present()

    def do_open(self, files, _n, _hint):
        self.activate()
        self.open_paths([f.get_path() for f in files if f.get_path()])

    def open_paths(self, paths):
        """Play files opened from Drawer or elsewhere: songs from the library
        as they are, others read just for this."""
        songs = []
        for path in paths:
            if path in self.by_path:
                songs.append(self.by_path[path])
            elif store.is_audio(path):
                try:
                    stat = os.stat(path)
                except OSError:
                    continue
                songs.append(store._song(path, stat, os.path.dirname(path), store.read_tags(path)))
        if songs:
            self.player.play_songs(songs, 0, shuffle=False)

    def _activated(self, window, _param):
        if window.is_active() and time.time() - self.last_scan > 20:
            self.rescan()

    def rescan(self):
        if self.scanning:
            return
        self.scanning = True
        self.last_scan = time.time()

        def progress(done, total):
            GLib.idle_add(lambda: self.window and self.window.show_busy(done, total) and False)

        def work():
            try:
                found = store.scan(progress=progress)
            except OSError:
                found = []
            GLib.idle_add(self._scanned, found)
        threading.Thread(target=work, daemon=True).start()

    def _scanned(self, songs):
        self.scanning = False
        self.songs = sorted(songs, key=lambda s: (s["title"].lower(), s["path"]))
        self.by_path = {s["path"]: s for s in songs}
        self.albums = store.albums(songs)
        self.album_by_key = {store.album_key(s): a for a in self.albums for s in a["songs"][:1]}
        self.artists = store.artists(self.albums)
        if not self.restored:
            self.restored = True
            self._restore()
        if self.window is not None:
            self.window.library_changed()
        return False

    def album_of(self, song):
        return self.album_by_key.get(store.album_key(song)) if song else None

    def cover_of(self, song):
        if song is None:
            return None
        if song.get("cover"):
            return song["cover"]
        album = self.album_of(song)
        return album["cover"] if album else store.folder_cover(os.path.dirname(song["path"]))

    # controls shared by the window, the menus and MPRIS

    def play_pause(self):
        if self.player.song is None:
            self.play()
        else:
            self.player.play_pause()

    def play(self):
        if not self.player.can_play():
            if self.window:
                alert.tell(self.window, "Shanty can’t play music on this computer.",
                           "GStreamer, which plays the songs, isn’t installed.")
            return
        if self.player.song is None:
            if self.songs:
                self.player.play_songs(self.songs, 0)
            return
        self.player.play()

    def set_shuffle(self, on):
        self.player.set_shuffle(on)

    def cycle_repeat(self):
        self.set_repeat(REPEATS[(REPEATS.index(self.player.repeat) + 1) % len(REPEATS)])

    def set_repeat(self, mode):
        self.player.set_repeat(mode)

    def set_volume(self, value):
        self.player.set_volume(value)
        if self.window is not None:
            self.window.volume_changed(self.player.volume)
        if self.mpris:
            self.mpris.changed("Volume")

    def _player_changed(self, what):
        if self.window is not None:
            self.window.player_changed(what)
        if self.mpris is None:
            return
        if what == "song":
            self.mpris.changed("Metadata", "CanGoNext", "CanGoPrevious", "CanSeek", "PlaybackStatus")
        elif what == "status":
            self.mpris.changed("PlaybackStatus", "CanPlay")
        elif what == "queue":
            self.mpris.changed("Shuffle", "LoopStatus", "CanGoNext", "CanGoPrevious")
        elif what == "seeked":
            self.mpris.seeked()
        if what in ("song", "status", "queue"):
            self._save()

    # kept between starts

    def _save(self):
        p = self.player
        if p is None:
            return
        state = {"shuffle": p.shuffle, "repeat": p.repeat, "volume": round(p.volume, 3)}
        if p.song is not None:
            state["queue"] = [p.queue[i]["path"] for i in p.order][:2000]
            state["at"] = p.at
            state["position"] = round(p.position(), 1) if p.status != "Stopped" else 0
        store.save_state(state)

    def _restore(self):
        state = store.load_state()
        paths = state.get("queue") or []
        songs = [self.by_path[p] for p in paths if p in self.by_path]
        if not songs:
            return
        at = state.get("at", 0)
        wanted = paths[at] if 0 <= at < len(paths) else None
        index = next((i for i, s in enumerate(songs) if s["path"] == wanted), 0)
        shuffle = self.player.shuffle
        self.player.shuffle = False   # the saved order already is the shuffled one
        self.player.load(songs, index, float(state.get("position") or 0))
        self.player.shuffle = shuffle


def main():
    return Shanty().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
