# SPDX-License-Identifier: GPL-3.0-or-later
"""Now Playing in the menu bar, as on a Mac: while an app is playing music
or a video (or has it paused), a symbol shows in the menu bar, and a click
on it shows the album cover, the track, the artist and the app, how far it
has got, and back, play or pause, and forward. The players are found over
MPRIS (media.py); the symbol follows their PropertiesChanged signals rather
than asking every few seconds. Also Seek's magnifying glass, which opens
Seek as Spotlight's does on a Mac. Original freemac code.
"""
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango

from . import media  # noqa: E402
from .menubar_popup import Popup  # noqa: E402
from .status import StatusButton, launch  # noqa: E402

ART = 64


def clock(microseconds):
    seconds = max(0, microseconds // 1_000_000)
    hours, rest = divmod(seconds, 3600)
    return f"{hours}:{rest // 60:02d}:{rest % 60:02d}" if hours else f"{rest // 60}:{rest % 60:02d}"


class Seek(StatusButton):
    def __init__(self):
        super().__init__()
        self.connect("clicked", lambda *_: launch("freemac-seek"))
        self.show_icon("system-search-symbolic", "Seek (⌘Space)")


class NowPlayingMenu(StatusButton):
    def __init__(self):
        super().__init__()
        self.popup = Popup("freemac-now-playing", width=300)
        self.bus = media.session()
        self.player = None
        self.pending = None
        self.ticker = None
        self.connect("clicked", lambda *_: self._clicked())
        if self.bus is not None:
            self.bus.signal_subscribe(None, "org.freedesktop.DBus.Properties", "PropertiesChanged", media.PATH,
                                      None, Gio.DBusSignalFlags.NONE, self._changed)
            self.bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                                      "/org/freedesktop/DBus", None, Gio.DBusSignalFlags.NONE, self._owner)
        self.update()

    # -- following the players ------------------------------------------------

    def _owner(self, _conn, _sender, _path, _iface, _signal, params):
        if params.unpack()[0].startswith(media.PREFIX):
            self._changed()

    def _changed(self, *_args):
        # Players send several changes at once (title, cover, length): one look.
        if self.pending is None:
            self.pending = GLib.timeout_add(250, self._settle)

    def _settle(self):
        self.pending = None
        self.update()
        return False

    def update(self):
        self.player = media.current(self.bus) if self.bus is not None else None
        p = self.player
        if p is None or p["status"] == "Stopped":
            self.shown = None
            self.popup.hide()
            self.hide()
            return
        words = " — ".join(x for x in (p["title"], p["artist"]) if x) or p["app"]
        self.show_icon("freemac-now-playing-symbolic" if Gtk.IconTheme.get_default().has_icon(
            "freemac-now-playing-symbolic") else "audio-x-generic-symbolic", words)
        if self.popup.visible():
            self.fill()

    # -- the menu -------------------------------------------------------------

    def _clicked(self):
        if self.popup.visible():
            self.popup.hide()
            return
        self.update()
        if self.player is None:
            return
        self.fill()
        self.popup.show_under(self)
        if self.ticker is None:
            self.ticker = GLib.timeout_add_seconds(1, self._tick)

    def fill(self):
        p, pop = self.player, self.popup
        pop.clear()
        top = Gtk.Box(spacing=12)
        top.pack_start(self._art(p.get("art") or ""), False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER, spacing=1)
        for text, cls in ((p["title"] or p["app"], "sound-menu-title"),
                          (" — ".join(x for x in (p["artist"], p.get("album")) if x), None),
                          (p["app"] if p["title"] else "", "sound-menu-heading")):
            if not text:
                continue
            label = Gtk.Label(label=text, xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=24)
            if cls:
                label.get_style_context().add_class(cls)
            words.pack_start(label, False, False, 0)
        top.pack_start(words, True, True, 0)
        pop.add(top, 4)

        self.bar = None
        if p.get("length"):
            self.bar = Gtk.ProgressBar()
            self.bar.get_style_context().add_class("now-playing-progress")
            times = Gtk.Box()
            self.elapsed = Gtk.Label(xalign=0)
            self.left = Gtk.Label(xalign=1)
            for label in (self.elapsed, self.left):
                # Room for "-1:23:45" from the start, so the times don't
                # shuffle the line as they count.
                label.set_width_chars(8)
                label.get_style_context().add_class("sound-menu-heading")
                label.get_style_context().add_class("now-playing-time")
            times.pack_start(self.elapsed, True, True, 0)
            times.pack_end(self.left, True, True, 0)
            column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            column.pack_start(self.bar, False, False, 0)
            column.pack_start(times, False, False, 0)
            pop.add(column, 2)
            self._show_position(p.get("position") or 0)

        controls = Gtk.Box(spacing=18, halign=Gtk.Align.CENTER)
        playing = p["status"] == "Playing"
        for icon, tip, action, can in (
                ("media-skip-backward-symbolic", "Previous", "previous", p["can_previous"]),
                ("media-playback-pause-symbolic" if playing else "media-playback-start-symbolic",
                 "Pause" if playing else "Play", "play-pause", p["can_play"]),
                ("media-skip-forward-symbolic", "Next", "next", p["can_next"])):
            button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR)
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.set_tooltip_text(tip)
            button.set_sensitive(can)
            button.get_style_context().add_class("now-playing-control")
            button.connect("clicked", lambda _b, action=action: self._send(action))
            controls.pack_start(button, False, False, 0)
        pop.add(controls, 2)
        pop.menu.show_all()

    def _art(self, art):
        """The cover the player gives, rounded off, or the music symbol."""
        scale = self.get_scale_factor()
        path = Gio.File.new_for_uri(art).get_path() if art.startswith("file://") else None
        if path:
            try:
                picture = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, ART * scale, ART * scale, True)
                image = Gtk.Image.new_from_surface(Gdk.cairo_surface_create_from_pixbuf(picture, scale, None))
                image.get_style_context().add_class("now-playing-art")
                return image
            except GLib.Error:
                pass
        image = Gtk.Image.new_from_icon_name("audio-x-generic-symbolic", Gtk.IconSize.DIALOG)
        image.set_pixel_size(32)
        image.set_size_request(ART, ART)
        image.get_style_context().add_class("now-playing-blank")
        return image

    def _show_position(self, position):
        length = (self.player or {}).get("length") or 0
        if not self.bar or not length:
            return
        position = min(position, length)
        self.bar.set_fraction(position / length)
        self.elapsed.set_text(clock(position))
        self.left.set_text("-" + clock(length - position))
        # The whole menu, not just the bar and the times: the menu's window
        # is see-through, and a redraw of a corner of it can leave the
        # desktop showing through on some screens.
        self.popup.window.queue_draw()

    def _tick(self):
        if not self.popup.visible():
            self.ticker = None
            return False
        if self.player and self.player["status"] == "Playing" and self.bar:
            try:
                value = self.bus.call_sync(self.player["name"], media.PATH, "org.freedesktop.DBus.Properties",
                                           "Get", GLib.Variant("(ss)", (media.PLAYER, "Position")), None,
                                           Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
                self._show_position(int(value))
            except (GLib.Error, TypeError, ValueError):
                pass
        return True

    def _send(self, action):
        if self.player and media.send(action, self.bus, self.player["name"]):
            self._changed()
