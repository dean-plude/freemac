# SPDX-License-Identifier: GPL-3.0-or-later
"""Reel: freemac's video player.

Each video opens in its own window, sized to the picture. The controls float
over the bottom of the video and fade away while it plays and the pointer
rests; moving the pointer brings them back. Space plays and pauses, Left and
Right skip back and forward 10 seconds, Up and Down change the volume, and
F (or Control+Command+F) fills the screen; Esc leaves full screen.

Where you stopped is kept for each video (~/.cache/freemac/reel.json), so
opening it again goes on from there, as a Mac's player does. Opened with no
video, Reel shows the videos in your Videos folder to choose from.

GStreamer's playbin plays the video into a gtksink, whose widget is the
picture. Original freemac code.
"""
import json
import os
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import menus, style  # noqa: E402

try:
    gi.require_version("Gst", "1.0")
    from gi.repository import Gst  # noqa: E402
    Gst.init(None)
except (ImportError, ValueError):
    Gst = None

APP_ID = "org.freemac.Reel"
SKIP = 10              # seconds for Left and Right
HIDE_AFTER = 2500      # ms of a still pointer before the controls fade
KEEP_FROM = 15         # remember the place only past this many seconds...
KEEP_TO = 20           # ...and not within this many of the end
VIDEO_TYPES = ("mp4", "m4v", "mkv", "webm", "mov", "avi", "ogv", "mpg", "mpeg", "wmv", "3gp", "ts", "mts")

CSS = b"""
.reel-video { background: black; }
.reel-hud {
  background: alpha(#1c1c1e, 0.72); border-radius: 14px; padding: 8px 14px;
  border: 1px solid alpha(white, 0.10);
}
.reel-hud, .reel-hud label { color: white; }
.reel-hud label { font-feature-settings: "tnum"; font-size: 0.92em; }
.reel-hud button { background: transparent; border: none; box-shadow: none; color: white;
  min-width: 28px; min-height: 28px; padding: 2px; }
.reel-hud button:hover { background: alpha(white, 0.12); }
.reel-hud scale trough { background: alpha(white, 0.25); min-height: 4px; border-radius: 2px; }
.reel-hud scale highlight { background: white; border-radius: 2px; }
.reel-hud scale slider { background: white; min-width: 12px; min-height: 12px; border-radius: 6px;
  border: none; box-shadow: 0 1px 2px alpha(black, 0.4); }
.reel-title { background: linear-gradient(to bottom, alpha(black, 0.6), transparent);
  color: white; padding: 10px 16px 24px 16px; }
.reel-message { color: alpha(white, 0.85); }
.reel-pick-title { font-size: 1.5em; font-weight: 600; }
"""


def state_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "freemac", "reel.json")


def load_places():
    try:
        with open(state_path()) as f:
            found = json.load(f)
        return found if isinstance(found, dict) else {}
    except (OSError, ValueError):
        return {}


def save_place(path, seconds, length):
    """Keep where the video was left, or forget it when it was watched to
    the end or hardly started."""
    places = load_places()
    if seconds > KEEP_FROM and (not length or seconds < length - KEEP_TO):
        places[path] = {"at": round(seconds, 1), "when": time.time()}
    else:
        places.pop(path, None)
    # Keep the 200 most recent.
    if len(places) > 200:
        for old in sorted(places, key=lambda p: places[p].get("when", 0))[:-200]:
            places.pop(old)
    try:
        os.makedirs(os.path.dirname(state_path()), exist_ok=True)
        tmp = state_path() + ".tmp"
        with open(tmp, "w") as f:
            json.dump(places, f)
        os.replace(tmp, state_path())
    except OSError:
        pass


def clock(seconds):
    seconds = max(0, int(seconds or 0))
    h, rest = divmod(seconds, 3600)
    m, s = divmod(rest, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def is_video(path):
    return os.path.splitext(path)[1][1:].lower() in VIDEO_TYPES


def videos_folder():
    return GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_VIDEOS) or os.path.expanduser("~/Videos")


def videos_in(folder, limit=200):
    found = []
    for here, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in files:
            if not name.startswith(".") and is_video(name):
                path = os.path.join(here, name)
                try:
                    found.append((os.path.getmtime(path), path))
                except OSError:
                    pass
        if len(found) >= limit:
            break
    return [p for _t, p in sorted(found, reverse=True)]


def icon_button(icon, tip, callback, size=Gtk.IconSize.BUTTON):
    button = Gtk.Button.new_from_icon_name(icon, size)
    button.set_tooltip_text(tip)
    button.set_relief(Gtk.ReliefStyle.NONE)
    button.set_can_focus(False)
    button.connect("clicked", lambda _b: callback())
    return button


class Window(Gtk.ApplicationWindow):
    def __init__(self, app, path=None):
        super().__init__(application=app, title="Reel")
        self.set_default_size(880, 520)
        self.path = None
        self.playbin = None
        self.length = 0
        self.full = False
        self.windowed = None   # the window's size before full screen
        self.dragging = False
        self.sized = False
        self.hide_timer = 0
        self.resume_at = 0
        self.last_saved = 0

        self.header = Gtk.HeaderBar(show_close_button=True, title="Reel")
        self.set_titlebar(self.header)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.add(self.stack)
        self.stack.add_named(self._build_picker(), "pick")
        self.stack.add_named(self._build_player(), "play")

        menus.add_actions(self, {
            "open": self.open_dialog, "close": self.close, "play-pause": self.play_pause,
            "forward": lambda: self.skip(SKIP), "back": lambda: self.skip(-SKIP),
            "louder": lambda: self.change_volume(0.1), "quieter": lambda: self.change_volume(-0.1),
            "full-screen": self.toggle_full, "to-start": lambda: self.seek(0),
            "show-in-drawer": self.show_in_drawer,
        })
        self.connect("key-press-event", self._key)
        self.connect("window-state-event", self._state)
        self.connect("delete-event", self._closing)

        targets = [Gtk.TargetEntry.new("text/uri-list", 0, 0)]
        self.drag_dest_set(Gtk.DestDefaults.ALL, targets, Gdk.DragAction.COPY)
        self.connect("drag-data-received", self._dropped)

        self.show_all()
        if path:
            self.load(path)
        else:
            self.show_picker()

    # -- the list of videos, when there's nothing open --

    def _build_picker(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=28)
        title = Gtk.Label(label="Videos", xalign=0)
        title.get_style_context().add_class("reel-pick-title")
        self.pick_note = Gtk.Label(xalign=0, wrap=True)
        self.pick_note.get_style_context().add_class("dim-label")
        top = Gtk.Box(spacing=12)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        words.pack_start(title, False, False, 0)
        words.pack_start(self.pick_note, False, False, 0)
        top.pack_start(words, True, True, 0)
        open_button = Gtk.Button(label="Open…", valign=Gtk.Align.CENTER)
        open_button.connect("clicked", lambda _b: self.open_dialog())
        top.pack_end(open_button, False, False, 0)
        box.pack_start(top, False, False, 0)

        self.pick_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.pick_list.set_activate_on_single_click(False)
        self.pick_list.connect("row-activated", lambda _l, row: self.load(row.path))
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_shadow_type(Gtk.ShadowType.IN)
        scroller.add(self.pick_list)
        box.pack_start(scroller, True, True, 0)
        return box

    def show_picker(self):
        for row in self.pick_list.get_children():
            self.pick_list.remove(row)
        folder = videos_folder()
        found = videos_in(folder)
        places = load_places()
        for path in found:
            row = Gtk.ListBoxRow()
            row.path = path
            line = Gtk.Box(spacing=10, margin=8)
            icon = Gtk.Image.new_from_gicon(self._icon(path), Gtk.IconSize.DND)
            line.pack_start(icon, False, False, 0)
            name = Gtk.Label(label=os.path.relpath(path, folder), xalign=0, ellipsize=Pango.EllipsizeMode.MIDDLE)
            line.pack_start(name, True, True, 0)
            if path in places:
                note = Gtk.Label(label=f"Stopped at {clock(places[path]['at'])}")
                note.get_style_context().add_class("dim-label")
                line.pack_end(note, False, False, 0)
            row.add(line)
            self.pick_list.add(row)
        if found:
            self.pick_note.set_text("Double-click a video to play it, or drop one here.")
        else:
            self.pick_note.set_text("There are no videos in your Videos folder yet. Click Open to "
                                    "choose one somewhere else, or drop one here.")
        self.pick_list.show_all()
        self.stack.set_visible_child_name("pick")
        self.header.set_title("Reel")
        self.header.set_subtitle(None)

    def _icon(self, path):
        try:
            info = Gio.File.new_for_path(path).query_info("standard::icon,thumbnail::path", 0, None)
            thumb = info.get_attribute_byte_string("thumbnail::path")
            if thumb:
                return Gio.FileIcon.new(Gio.File.new_for_path(thumb))
            return info.get_icon()
        except GLib.Error:
            return Gio.ThemedIcon.new("video-x-generic")

    # -- the player --

    def _build_player(self):
        overlay = Gtk.Overlay()
        overlay.get_style_context().add_class("reel-video")
        self.video_box = Gtk.EventBox()
        self.video_box.get_style_context().add_class("reel-video")
        self.video_box.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK)
        self.video_box.connect("motion-notify-event", lambda *_: self.wake_controls())
        self.video_box.connect("button-press-event", self._clicked)
        self.message = Gtk.Label(wrap=True, justify=Gtk.Justification.CENTER)
        self.message.get_style_context().add_class("reel-message")
        self.video_box.add(self.message)
        overlay.add(self.video_box)

        self.hud = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER, valign=Gtk.Align.END, margin_bottom=18)
        self.hud.get_style_context().add_class("reel-hud")
        self.hud.set_size_request(520, -1)
        self.volume = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 0.05)
        self.volume.set_draw_value(False)
        self.volume.set_size_request(70, -1)
        self.volume.set_can_focus(False)
        self.volume.set_value(self.get_application().volume)
        self.volume.connect("value-changed", lambda s: self.set_volume(s.get_value()))
        self.hud.pack_start(Gtk.Image.new_from_icon_name("audio-volume-high-symbolic", Gtk.IconSize.MENU),
                            False, False, 0)
        self.hud.pack_start(self.volume, False, False, 0)
        self.hud.pack_start(icon_button("media-seek-backward-symbolic", "Back 10 seconds (←)",
                                        lambda: self.skip(-SKIP)), False, False, 0)
        self.play_button = icon_button("media-playback-start-symbolic", "Play (Space)", self.play_pause,
                                       Gtk.IconSize.LARGE_TOOLBAR)
        self.hud.pack_start(self.play_button, False, False, 0)
        self.hud.pack_start(icon_button("media-seek-forward-symbolic", "Forward 10 seconds (→)",
                                        lambda: self.skip(SKIP)), False, False, 0)
        self.elapsed = Gtk.Label(label="0:00", width_chars=7, xalign=1)
        self.hud.pack_start(self.elapsed, False, False, 0)
        self.bar = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 1)
        self.bar.set_draw_value(False)
        self.bar.set_can_focus(False)
        self.bar.connect("button-press-event", lambda *_: setattr(self, "dragging", True) or False)
        self.bar.connect("button-release-event", self._bar_released)
        self.bar.connect("value-changed", self._bar_moved)
        self.hud.pack_start(self.bar, True, True, 0)
        self.remaining = Gtk.Label(label="-0:00", width_chars=8, xalign=0)
        self.hud.pack_start(self.remaining, False, False, 0)
        self.full_button = icon_button("view-fullscreen-symbolic", "Full Screen (F)", self.toggle_full)
        self.hud.pack_start(self.full_button, False, False, 0)
        self.hud.connect("enter-notify-event", lambda *_: self.wake_controls(stay=True))
        self.hud_revealer = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.CROSSFADE,
                                         transition_duration=350, halign=Gtk.Align.CENTER,
                                         valign=Gtk.Align.END, reveal_child=True)
        self.hud_revealer.add(self.hud)
        overlay.add_overlay(self.hud_revealer)

        # In full screen, the title shows over the top with the controls.
        self.full_title = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, valign=Gtk.Align.START)
        self.full_title.get_style_context().add_class("reel-title")
        self.title_revealer = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.CROSSFADE,
                                           transition_duration=350, valign=Gtk.Align.START,
                                           reveal_child=False)
        self.title_revealer.add(self.full_title)
        overlay.add_overlay(self.title_revealer)
        for child in (self.hud_revealer, self.title_revealer):
            overlay.set_overlay_pass_through(child, False)
        return overlay

    def _make_bin(self):
        if Gst is None:
            return None, "Videos can't be played: GStreamer isn't installed."
        playbin = Gst.ElementFactory.make("playbin", None)
        sink = Gst.ElementFactory.make("gtksink", None)
        if playbin is None or sink is None:
            return None, "Videos can't be played here: GStreamer's GTK video output is missing."
        playbin.set_property("video-sink", sink)
        widget = sink.get_property("widget")
        widget.set_hexpand(True)
        widget.set_vexpand(True)
        widget.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK)
        widget.connect("motion-notify-event", lambda *_: self.wake_controls())
        widget.connect("button-press-event", self._clicked)
        bus = playbin.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._message)
        self.video_widget = widget
        return playbin, None

    def load(self, path):
        self.stop()
        self.path = path
        self.length = 0
        self.sized = False
        self.stack.set_visible_child_name("play")
        name = os.path.basename(path)
        self.header.set_title(name)
        self.header.set_subtitle(None)
        self.set_title(name)
        self.full_title.set_text(name)
        Gtk.RecentManager.get_default().add_item(Gio.File.new_for_path(path).get_uri())
        if self.playbin is None:
            self.playbin, problem = self._make_bin()
            if self.playbin is None:
                self.message.set_text(problem)
                self.message.show()
                return
            self.video_box.remove(self.message)
            self.video_box.add(self.video_widget)
            self.video_widget.show()
        self.resume_at = load_places().get(path, {}).get("at", 0)
        self.playbin.set_property("uri", Gio.File.new_for_path(path).get_uri())
        self.playbin.set_property("volume", self.get_application().volume ** 2)
        self.playbin.set_state(Gst.State.PAUSED)
        self.wake_controls()
        GLib.timeout_add(250, self._tick)

    def stop(self):
        if self.playbin is not None and self.path:
            self.remember()
            self.playbin.set_state(Gst.State.NULL)

    def remember(self):
        if self.playbin is None or not self.path:
            return
        at = self.position()
        if at is not None:
            save_place(self.path, at, self.length)
            self.last_saved = time.monotonic()

    def _message(self, _bus, message):
        kind = message.type
        if kind == Gst.MessageType.ASYNC_DONE:
            ok, length = self.playbin.query_duration(Gst.Format.TIME)
            if ok and length > 0:
                self.length = length / Gst.SECOND
                self.bar.set_range(0, max(1, self.length))
            if not self.sized:
                self.sized = True
                self._fit_window()
                if self.resume_at and self.resume_at < self.length - KEEP_TO:
                    self.seek(self.resume_at)
                    self.resume_at = 0
                self.play()
        elif kind == Gst.MessageType.EOS:
            save_place(self.path, 0, self.length)
            self.playbin.set_state(Gst.State.PAUSED)
            self.seek(0)
            self._show_playing(False)
            self.wake_controls(stay=True)
        elif kind == Gst.MessageType.ERROR:
            error, _debug = message.parse_error()
            self.playbin.set_state(Gst.State.NULL)
            self.video_box.remove(self.video_box.get_child())
            self.video_box.add(self.message)
            self.message.set_text(f"“{os.path.basename(self.path)}” can't be played.\n{error.message}")
            self.message.show()
            self.playbin = None

    def _fit_window(self):
        """Size the window to the picture, within most of the screen."""
        pad = self.playbin.emit("get-video-pad", 0)
        caps = pad.get_current_caps() if pad else None
        if not caps or self.full or self.is_maximized():
            return
        info = caps.get_structure(0)
        ok_w, width = info.get_int("width")
        ok_h, height = info.get_int("height")
        if not (ok_w and ok_h and width and height):
            return
        ok, num, den = info.get_fraction("pixel-aspect-ratio")
        if ok and num and den:
            width = width * num // den
        monitor = Gdk.Display.get_default().get_monitor_at_window(self.get_window()) \
            if self.get_window() else None
        area = monitor.get_workarea() if monitor else None
        max_w = int((area.width if area else 1280) * 0.8)
        max_h = int((area.height if area else 800) * 0.8) - 40
        scale = min(1.0, max_w / width, max_h / height)
        self.resize(max(480, int(width * scale)), max(270, int(height * scale)))

    # -- playing --

    def playing(self):
        if self.playbin is None:
            return False
        _ok, state, pending = self.playbin.get_state(0)
        return Gst.State.PLAYING in (state, pending)

    def play(self):
        if self.playbin is not None:
            self.playbin.set_state(Gst.State.PLAYING)
            self._show_playing(True)
            self.wake_controls()

    def pause(self):
        if self.playbin is not None:
            self.playbin.set_state(Gst.State.PAUSED)
            self._show_playing(False)
            self.wake_controls(stay=True)
            self.remember()

    def play_pause(self):
        if self.stack.get_visible_child_name() != "play":
            row = self.pick_list.get_selected_row()
            if row is not None:
                self.load(row.path)
            return
        self.pause() if self.playing() else self.play()

    def _show_playing(self, on):
        name = "media-playback-pause-symbolic" if on else "media-playback-start-symbolic"
        self.play_button.get_image().set_from_icon_name(name, Gtk.IconSize.LARGE_TOOLBAR)
        self.play_button.set_tooltip_text("Pause (Space)" if on else "Play (Space)")

    def position(self):
        if self.playbin is None:
            return None
        ok, pos = self.playbin.query_position(Gst.Format.TIME)
        return pos / Gst.SECOND if ok else None

    def seek(self, seconds):
        if self.playbin is None:
            return
        seconds = max(0, min(seconds, self.length or seconds))
        self.playbin.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE,
                             int(seconds * Gst.SECOND))
        self._show_time(seconds)

    def skip(self, by):
        at = self.position()
        if at is not None:
            self.seek(at + by)
            self.wake_controls()

    def set_volume(self, value):
        value = max(0.0, min(1.0, value))
        self.get_application().volume = value
        if self.playbin is not None:
            self.playbin.set_property("volume", value ** 2)

    def change_volume(self, by):
        self.volume.set_value(max(0.0, min(1.0, self.volume.get_value() + by)))
        self.wake_controls()

    def _tick(self):
        if self.playbin is None or self.get_window() is None:
            return False
        at = self.position()
        if at is not None and not self.dragging:
            self._show_time(at)
        if self.playing() and time.monotonic() - self.last_saved > 10:
            self.remember()
        return True

    def _show_time(self, at):
        self.updating = True
        self.bar.set_value(at)
        self.updating = False
        self.elapsed.set_text(clock(at))
        self.remaining.set_text("-" + clock(max(0, self.length - at)) if self.length else "")

    def _bar_moved(self, scale):
        if getattr(self, "updating", False):
            return
        at = scale.get_value()
        self.elapsed.set_text(clock(at))
        if not self.dragging:
            self.seek(at)

    def _bar_released(self, scale, _event):
        self.dragging = False
        self.seek(scale.get_value())
        return False

    # -- controls that fade --

    def wake_controls(self, stay=False):
        self.hud_revealer.set_reveal_child(True)
        self.title_revealer.set_reveal_child(self.full)
        self._show_pointer(True)
        if self.hide_timer:
            GLib.source_remove(self.hide_timer)
            self.hide_timer = 0
        if not stay:
            self.hide_timer = GLib.timeout_add(HIDE_AFTER, self._fade)
        return False

    def _fade(self):
        self.hide_timer = 0
        if self.playing() and not self.dragging:
            self.hud_revealer.set_reveal_child(False)
            self.title_revealer.set_reveal_child(False)
            self._show_pointer(False)
        return False

    def _show_pointer(self, on):
        window = self.get_window()
        if window is None:
            return
        cursor = None if on else Gdk.Cursor.new_from_name(window.get_display(), "none")
        window.set_cursor(cursor)

    def _clicked(self, _w, event):
        if event.type == Gdk.EventType._2BUTTON_PRESS:
            self.toggle_full()
        elif event.button == 1:
            self.wake_controls()
        return False

    # -- full screen --

    def toggle_full(self):
        if self.full:
            self.unfullscreen()
            return
        # GTK keeps the size _fit_window asked for and asks for it again
        # when the controls change, which shrinks a full-screen window back.
        # Ask for the screen's size instead, and give the old size back on
        # the way out.
        self.windowed = self.get_size()
        monitor = Gdk.Display.get_default().get_monitor_at_window(self.get_window()) \
            if self.get_window() else None
        if monitor:
            area = monitor.get_geometry()
            self.resize(area.width, area.height)
        self.fullscreen()

    def _state(self, _w, event):
        was = self.full
        self.full = bool(event.new_window_state & Gdk.WindowState.FULLSCREEN)
        if was and not self.full and self.windowed:
            self.resize(*self.windowed)
            self.windowed = None
        self.full_button.get_image().set_from_icon_name(
            "view-restore-symbolic" if self.full else "view-fullscreen-symbolic", Gtk.IconSize.BUTTON)
        self.full_button.set_tooltip_text("Exit Full Screen (Esc)" if self.full else "Full Screen (F)")
        self.wake_controls()
        return False

    # -- keys, files --

    def _key(self, _w, event):
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        if mods:
            return False
        if self.stack.get_visible_child_name() != "play":
            return False
        key = event.keyval
        if key == Gdk.KEY_space:
            self.play_pause()
        elif key in (Gdk.KEY_Left, Gdk.KEY_j):
            self.skip(-SKIP)
        elif key in (Gdk.KEY_Right, Gdk.KEY_l):
            self.skip(SKIP)
        elif key == Gdk.KEY_k:
            self.play_pause()
        elif key == Gdk.KEY_Up:
            self.change_volume(0.1)
        elif key == Gdk.KEY_Down:
            self.change_volume(-0.1)
        elif key in (Gdk.KEY_f, Gdk.KEY_F11):
            self.toggle_full()
        elif key == Gdk.KEY_Escape and self.full:
            self.unfullscreen()
        elif key == Gdk.KEY_Home:
            self.seek(0)
        else:
            return False
        return True

    def open_dialog(self):
        dialog = Gtk.FileChooserNative.new("Open", self, Gtk.FileChooserAction.OPEN, "Open", "Cancel")
        videos = Gtk.FileFilter()
        videos.set_name("Videos")
        videos.add_mime_type("video/*")
        dialog.add_filter(videos)
        dialog.set_current_folder(videos_folder())
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            path = dialog.get_filename()
            if path:
                self.get_application().open_path(path, self)
        dialog.destroy()

    def show_in_drawer(self):
        if self.path:
            try:
                Gio.Subprocess.new(["freemac-drawer", self.path], Gio.SubprocessFlags.NONE)
            except GLib.Error:
                pass

    def _dropped(self, _w, _ctx, _x, _y, data, _info, _time):
        for uri in data.get_uris() or []:
            path = Gio.File.new_for_uri(uri).get_path()
            if path:
                self.get_application().open_path(path, self)
                break

    def _closing(self, *_):
        self.stop()
        if self.hide_timer:
            GLib.source_remove(self.hide_timer)
            self.hide_timer = 0
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("Open File…", "win.open", "<Ctrl>o")],
                   [("Show in Drawer", "win.show-in-drawer", "<Ctrl>r")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_View", [[("Enter Full Screen", "win.full-screen", "<Ctrl><Super>f")]]),
        ("_Controls", [[("Play/Pause", "win.play-pause", None)],
                       [("Skip Forward", "win.forward", "<Ctrl>Right"),
                        ("Skip Back", "win.back", "<Ctrl>Left"),
                        ("Go to Start", "win.to-start", "<Ctrl>Home")],
                       [("Increase Volume", "win.louder", "<Ctrl>Up"),
                        ("Decrease Volume", "win.quieter", "<Ctrl>Down")]]),
    ])


class Reel(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)
        self.volume = 0.8

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": self.quit_all})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_menubar(menubar())
        try:
            with open(os.path.join(os.path.dirname(state_path()), "reel-volume")) as f:
                self.volume = max(0.0, min(1.0, float(f.read())))
        except (OSError, ValueError):
            pass

    def quit_all(self):
        for window in self.get_windows():
            window.close()

    def do_shutdown(self):
        try:
            os.makedirs(os.path.dirname(state_path()), exist_ok=True)
            with open(os.path.join(os.path.dirname(state_path()), "reel-volume"), "w") as f:
                f.write(f"{self.volume:.2f}")
        except OSError:
            pass
        Gtk.Application.do_shutdown(self)

    def do_activate(self):
        windows = self.get_windows()
        if windows:
            windows[0].present()
        else:
            Window(self).present()

    def open_path(self, path, window=None):
        """Open in window when it has nothing playing yet, else a new one."""
        for other in self.get_windows():
            if isinstance(other, Window) and other.path == path:
                other.present()
                return
        if window is not None and window.path is None:
            window.load(path)
        else:
            Window(self, path).present()

    def do_open(self, files, _n, _hint):
        for f in files:
            if f.get_path():
                self.open_path(f.get_path())


def main():
    GLib.set_prgname("freemac-reel")
    return Reel().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
