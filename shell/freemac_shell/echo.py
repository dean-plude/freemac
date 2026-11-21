# SPDX-License-Identifier: GPL-3.0-or-later
"""Echo: record your voice, play it back and keep the good part.

Click the big red button to record and again to stop. Your recordings are
listed on the left, newest first, with when they were made and how long they
last. The chosen one is drawn as a waveform: click it to jump there, press
Space to play or pause, and skip back or forward 15 seconds. Click its name
to rename it. Trim keeps only the part between two handles. Recordings are
Ogg Opus files in Music/Echo, so other apps can play them too.

Original freemac code. GStreamer does the work: a microphone (or, with
FREEMAC_ECHO_TEST set, a test sound) through `level`, for the moving
waveform, into `opusenc`; playbin plays; and `level` over a fast decode
draws a recording's waveform, which is kept in ~/.cache/freemac/echo.
"""
import hashlib
import json
import os
import sys
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gst", "1.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gst, Gtk, Pango  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Echo"
EXT = ".ogg"
STEP = 0.05                  # seconds between waveform samples
SKIP = 15

CSS = b"""
.echo-side { background: @theme_bg_color; }
.echo-side list { background: transparent; }
.echo-side row { padding: 8px 12px; border-bottom: 1px solid alpha(currentColor, 0.08); }
.echo-row-name { font-weight: 600; }
.echo-small { font-size: 0.85em; color: alpha(currentColor, 0.6); }
.echo-name, .echo-name:focus { font-size: 1.6em; font-weight: 600; background: none; border-color: transparent;
  box-shadow: none; padding: 0; }
.echo-name:focus { border-bottom: 2px solid @theme_selected_bg_color; }
.echo-time { font-size: 1.1em; font-feature-settings: "tnum"; }
.echo-clock { font-size: 3.2em; font-weight: 300; font-feature-settings: "tnum"; }
.echo-record { min-width: 56px; min-height: 56px; border-radius: 32px; padding: 0;
  background: white; border: 3px solid alpha(black, 0.18); box-shadow: none; }
.echo-record-dot { min-width: 40px; min-height: 40px; border-radius: 20px; background: #ff3b30; }
.echo-recording .echo-record-dot { min-width: 22px; min-height: 22px; border-radius: 5px; }
.echo-round { border-radius: 30px; min-width: 44px; min-height: 44px; padding: 0; }
.echo-empty-title { font-size: 1.4em; font-weight: 600; }
.echo-bar { padding: 12px; border-top: 1px solid alpha(currentColor, 0.1); }
"""


# -- the files --

def folder():
    music = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_MUSIC) or os.path.expanduser("~/Music")
    return os.path.join(music, "Echo")


def recordings():
    """(path, modified) for each recording, newest first."""
    try:
        names = [n for n in os.listdir(folder()) if n.endswith(EXT) and not n.startswith(".")]
    except OSError:
        return []
    found = []
    for name in names:
        path = os.path.join(folder(), name)
        try:
            found.append((path, os.stat(path).st_mtime))
        except OSError:
            pass
    return sorted(found, key=lambda f: f[1], reverse=True)


def title(path):
    return os.path.basename(path)[:-len(EXT)]


def new_path():
    taken = {title(p) for p, _m in recordings()}
    n = 1
    while True:
        name = "New Recording" if n == 1 else f"New Recording {n}"
        if name not in taken and not os.path.exists(os.path.join(folder(), name + EXT)):
            return os.path.join(folder(), name + EXT)
        n += 1


def clean_name(text):
    text = " ".join(text.replace("/", "-").split()).strip(". ")
    return text[:120]


def clock(seconds):
    seconds = max(0, int(seconds + 0.5))
    hours, rest = divmod(seconds, 3600)
    return f"{hours}:{rest // 60:02d}:{rest % 60:02d}" if hours else f"{rest // 60}:{rest % 60:02d}"


def when_words(stamp):
    then = time.localtime(stamp)
    now = time.localtime()
    hour = time.strftime("%H:%M", then) if style.prefs().get("clock") == "24" else \
        time.strftime("%I:%M %p", then).lstrip("0")
    if then.tm_yday == now.tm_yday and then.tm_year == now.tm_year:
        return f"Today, {hour}"
    if time.mktime(now) - stamp < 6 * 86400:
        return time.strftime("%A", then)
    return time.strftime("%b %-d, %Y", then)


def _db_to_level(values):
    loudest = max(values) if values else -90.0
    return max(0.0, min(1.0, (loudest + 50.0) / 50.0))   # -50 dB .. 0 dB


# -- waveforms --

def _cache_path(path):
    try:
        st = os.stat(path)
    except OSError:
        return None
    key = hashlib.sha1(f"{path}|{st.st_size}|{st.st_mtime}".encode()).hexdigest()
    return os.path.join(GLib.get_user_cache_dir(), "freemac", "echo", key + ".json")


def waveform(path):
    """(levels 0..1 every STEP seconds, length in seconds), from the cache or
    by decoding the file. Runs in a worker thread."""
    cache = _cache_path(path)
    if cache:
        try:
            with open(cache) as f:
                data = json.load(f)
            return data["levels"], data["length"]
        except (OSError, ValueError, KeyError):
            pass
    pipeline = Gst.parse_launch(
        f'filesrc location="{path}" ! decodebin ! audioconvert ! audio/x-raw,channels=1 ! '
        f'level interval={int(STEP * Gst.SECOND)} post-messages=true ! fakesink sync=false')
    levels = []
    bus = pipeline.get_bus()
    pipeline.set_state(Gst.State.PLAYING)
    try:
        while True:
            message = bus.timed_pop_filtered(10 * Gst.SECOND, Gst.MessageType.ELEMENT | Gst.MessageType.EOS
                                             | Gst.MessageType.ERROR)
            if message is None or message.type in (Gst.MessageType.EOS, Gst.MessageType.ERROR):
                break
            structure = message.get_structure()
            if structure and structure.get_name() == "level":
                levels.append(_db_to_level(list(structure.get_value("rms"))))
    finally:
        pipeline.set_state(Gst.State.NULL)
    length = len(levels) * STEP
    if cache and levels:
        try:
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            with open(cache, "w") as f:
                json.dump({"levels": [round(v, 3) for v in levels], "length": length}, f)
        except OSError:
            pass
    return levels, length


def trim(path, start, end):
    """Keep only start..end seconds of the recording. Raises RuntimeError."""
    temp = os.path.join(os.path.dirname(path), "." + os.path.basename(path) + ".trim")
    pipeline = Gst.parse_launch(
        f'filesrc location="{path}" ! oggdemux ! opusdec ! audioconvert ! audioresample ! '
        f'opusenc bitrate=64000 ! oggmux ! filesink location="{temp}"')
    bus = pipeline.get_bus()
    try:
        pipeline.set_state(Gst.State.PAUSED)
        if pipeline.get_state(10 * Gst.SECOND)[0] == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("The recording couldn't be read.")
        pipeline.seek(1.0, Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE,
                      Gst.SeekType.SET, int(start * Gst.SECOND), Gst.SeekType.SET, int(end * Gst.SECOND))
        pipeline.set_state(Gst.State.PLAYING)
        message = bus.timed_pop_filtered(120 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR)
        if message is None or message.type == Gst.MessageType.ERROR:
            raise RuntimeError("The recording couldn't be trimmed.")
    finally:
        pipeline.set_state(Gst.State.NULL)
    os.replace(temp, path)


# -- widgets --

class Wave(Gtk.DrawingArea):
    """A recording's loudness as bars, with the playhead, and in trim mode two
    handles. Click or drag to move the playhead (or the nearest handle)."""

    def __init__(self, on_seek):
        super().__init__()
        self.levels = []
        self.length = 0.0
        self.position = 0.0
        self.trimming = False
        self.trim = [0.0, 0.0]
        self.live = False          # recording: the newest levels on the right
        self.on_seek = on_seek
        self.grabbed = None
        self.set_size_request(-1, 150)
        self.set_hexpand(True)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", lambda *_a: setattr(self, "grabbed", None))

    def show(self, levels, length):
        self.levels, self.length = levels, length
        self.trim = [0.0, length]
        self.queue_draw()

    def _seconds(self, x):
        width = max(1, self.get_allocated_width())
        return max(0.0, min(self.length, x / width * self.length))

    def _press(self, _w, event):
        if self.live or not self.length or event.button != 1:
            return False
        at = self._seconds(event.x)
        if self.trimming:
            self.grabbed = 0 if abs(at - self.trim[0]) < abs(at - self.trim[1]) else 1
            self._move_handle(at)
        else:
            self.grabbed = "head"
            self.on_seek(at)
        return True

    def _motion(self, _w, event):
        if self.grabbed is None:
            return False
        at = self._seconds(event.x)
        if self.grabbed == "head":
            self.on_seek(at)
        else:
            self._move_handle(at)
        return True

    def _move_handle(self, at):
        gap = min(1.0, self.length / 4)
        if self.grabbed == 0:
            self.trim[0] = min(at, self.trim[1] - gap)
        else:
            self.trim[1] = max(at, self.trim[0] + gap)
        self.trim = [max(0.0, self.trim[0]), min(self.length, self.trim[1])]
        self.queue_draw()

    def _draw(self, _w, cr):
        width, height = self.get_allocated_width(), self.get_allocated_height()
        colour = self.get_style_context().get_color(Gtk.StateFlags.NORMAL)
        accent = Gdk.RGBA()
        accent.parse("#ff3b30" if self.live else "#2f7bf5")
        middle = height / 2
        bar, gap = 3, 2
        count = max(1, width // (bar + gap))
        if self.live:
            shown = self.levels[-count:]
            columns = [(width - (len(shown) - i) * (bar + gap), v) for i, v in enumerate(shown)]
        elif self.levels:
            per = len(self.levels) / count
            columns = []
            for i in range(count):
                chunk = self.levels[int(i * per):max(int(i * per) + 1, int((i + 1) * per))]
                columns.append((i * (bar + gap), max(chunk) if chunk else 0))
        else:
            columns = []
        played = self.position / self.length * width if self.length else 0
        for x, value in columns:
            h = max(2, value * (height - 16))
            if self.live or x < played:
                cr.set_source_rgba(accent.red, accent.green, accent.blue, 1)
            else:
                cr.set_source_rgba(colour.red, colour.green, colour.blue, 0.35)
            cr.rectangle(x, middle - h / 2, bar, h)
            cr.fill()
        if self.trimming and self.length:
            x0, x1 = self.trim[0] / self.length * width, self.trim[1] / self.length * width
            cr.set_source_rgba(0, 0, 0, 0.35)
            cr.rectangle(0, 0, x0, height)
            cr.rectangle(x1, 0, width - x1, height)
            cr.fill()
            cr.set_source_rgb(1.0, 0.8, 0.0)
            cr.set_line_width(3)
            cr.rectangle(x0 + 1.5, 1.5, max(3, x1 - x0 - 3), height - 3)
            cr.stroke()
            for x in (x0, x1):
                cr.rectangle(x - 4 if x > x0 else x, 0, 8, height)
                cr.fill()
        elif self.length and not self.live:
            cr.set_source_rgba(accent.red, accent.green, accent.blue, 1)
            cr.rectangle(played - 1, 0, 2, height)
            cr.fill()
        return False


class RecordButton(Gtk.Button):
    def __init__(self):
        super().__init__()
        self.get_style_context().add_class("echo-record")
        self.set_halign(Gtk.Align.CENTER)
        dot = Gtk.Box(halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        dot.get_style_context().add_class("echo-record-dot")
        self.add(dot)
        self.set_tooltip_text("Record")


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Echo")
        self.set_default_size(900, 560)
        self.recorder = None
        self.record_path = None
        self.record_started = 0
        self.live_levels = []
        self.player = Gst.ElementFactory.make("playbin", None)
        self.player.set_property("video-sink", Gst.ElementFactory.make("fakesink", None))
        bus = self.player.get_bus()
        bus.add_signal_watch()
        bus.connect("message::eos", self._ended)
        bus.connect("message::error", self._play_error)
        self.playing = False
        self.current = None
        self.serial = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Echo")
        self.set_titlebar(header)

        paned = Gtk.Paned()
        self.add(paned)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("echo-side")
        side.set_size_request(260, -1)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.list.connect("row-selected", self._row_selected)
        self.list.connect("button-press-event", self._list_pressed)
        scroller.add(self.list)
        side.pack_start(scroller, True, True, 0)
        bar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        bar.get_style_context().add_class("echo-bar")
        self.record_button = RecordButton()
        self.record_button.connect("clicked", lambda _b: self.toggle_record())
        bar.pack_start(self.record_button, False, False, 0)
        side.pack_end(bar, False, False, 0)
        paned.pack1(side, False, False)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        paned.pack2(self.stack, True, False)
        self.stack.add_named(self._build_empty(), "empty")
        self.stack.add_named(self._build_detail(), "detail")
        self.stack.add_named(self._build_recording(), "recording")

        menus.add_actions(self, {
            "record": self.toggle_record, "play": self.toggle_play, "back": lambda: self.skip(-SKIP),
            "forward": lambda: self.skip(SKIP), "trim": self.start_trim, "trash": self.trash_selected,
            "rename": lambda: self.name_entry.grab_focus(), "show-in-drawer": self.show_in_drawer,
            "close": self.close})
        self.connect("key-press-event", self._key)
        self.connect("destroy", self._closing)
        self.show_all()
        self.trim_bar.hide()
        self.load()
        self.list.grab_focus()
        self.ticker = GLib.timeout_add(50, self._tick)

    # -- pages --

    def _build_empty(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        label = Gtk.Label(label="No Recordings")
        label.get_style_context().add_class("echo-empty-title")
        box.pack_start(label, False, False, 0)
        self.empty_note = Gtk.Label(label="Click the red button to record your voice.", wrap=True,
                                    justify=Gtk.Justification.CENTER)
        self.empty_note.get_style_context().add_class("dim-label")
        box.pack_start(self.empty_note, False, False, 0)
        return box

    def _build_detail(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=24)
        self.name_entry = Gtk.Entry()
        self.name_entry.get_style_context().add_class("echo-name")
        self.name_entry.set_tooltip_text("Click to rename")
        self.name_entry.connect("activate", lambda _e: self._rename())
        self.name_entry.connect("focus-out-event", lambda *_a: self._rename() and False)
        box.pack_start(self.name_entry, False, False, 0)
        self.when_label = Gtk.Label(xalign=0)
        self.when_label.get_style_context().add_class("echo-small")
        box.pack_start(self.when_label, False, False, 0)

        self.wave = Wave(self.seek)
        self.wave.set_vexpand(True)
        self.wave.set_margin_top(20)
        box.pack_start(self.wave, True, True, 0)
        times = Gtk.Box()
        self.at_label = Gtk.Label(xalign=0)
        self.length_label = Gtk.Label(xalign=1)
        for label in (self.at_label, self.length_label):
            label.get_style_context().add_class("echo-time")
            label.get_style_context().add_class("dim-label")
        times.pack_start(self.at_label, False, False, 0)
        times.pack_end(self.length_label, False, False, 0)
        box.pack_start(times, False, False, 0)

        controls = Gtk.Box(spacing=18, halign=Gtk.Align.CENTER)
        controls.set_margin_top(6)
        back = self._round("media-seek-backward-symbolic", f"Back {SKIP} Seconds", lambda: self.skip(-SKIP))
        self.play_button = self._round("media-playback-start-symbolic", "Play", self.toggle_play)
        self.play_button.get_style_context().add_class("suggested-action")
        forward = self._round("media-seek-forward-symbolic", f"Forward {SKIP} Seconds", lambda: self.skip(SKIP))
        for widget in (back, self.play_button, forward):
            controls.pack_start(widget, False, False, 0)
        box.pack_start(controls, False, False, 0)

        actions = Gtk.Box(spacing=8)
        actions.set_margin_top(10)
        self.trim_button = Gtk.Button(label="Trim")
        self.trim_button.connect("clicked", lambda _b: self.start_trim())
        actions.pack_start(self.trim_button, False, False, 0)
        drawer = Gtk.Button(label="Show in Drawer")
        drawer.connect("clicked", lambda _b: self.show_in_drawer())
        actions.pack_start(drawer, False, False, 0)
        trash = Gtk.Button()
        trash.set_image(Gtk.Image.new_from_icon_name("user-trash-symbolic", Gtk.IconSize.BUTTON))
        trash.set_tooltip_text("Move to Trash")
        trash.connect("clicked", lambda _b: self.trash_selected())
        actions.pack_end(trash, False, False, 0)
        box.pack_start(actions, False, False, 0)

        self.trim_bar = Gtk.InfoBar(message_type=Gtk.MessageType.OTHER)
        self.trim_bar.get_content_area().add(
            Gtk.Label(label="Drag the yellow handles to the part you want to keep.", wrap=True, xalign=0))
        self.trim_bar.add_button("Cancel", Gtk.ResponseType.CANCEL)
        self.trim_bar.add_button("Trim", Gtk.ResponseType.OK).get_style_context().add_class("suggested-action")
        self.trim_bar.connect("response", self._trim_answer)
        box.pack_start(self.trim_bar, False, False, 0)
        return box

    def _build_recording(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=24)
        self.rec_title = Gtk.Label(xalign=0)
        self.rec_title.get_style_context().add_class("echo-name")
        box.pack_start(self.rec_title, False, False, 0)
        self.live_wave = Wave(lambda _s: None)
        self.live_wave.live = True
        self.live_wave.set_vexpand(True)
        box.pack_start(self.live_wave, True, True, 0)
        self.rec_clock = Gtk.Label(label="0:00")
        self.rec_clock.get_style_context().add_class("echo-clock")
        box.pack_start(self.rec_clock, False, False, 0)
        stop = Gtk.Button(label="Done", halign=Gtk.Align.CENTER)
        stop.get_style_context().add_class("destructive-action")
        stop.connect("clicked", lambda _b: self.toggle_record())
        box.pack_start(stop, False, False, 0)
        return box

    def _round(self, icon, tip, callback):
        button = Gtk.Button()
        button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR))
        button.get_style_context().add_class("echo-round")
        button.set_tooltip_text(tip)
        button.connect("clicked", lambda _b: callback())
        return button

    # -- the list --

    def load(self, choose=None):
        chosen = choose or (self.current and self.current["path"])
        for row in self.list.get_children():
            self.list.remove(row)
        for path, modified in recordings():
            row = Gtk.ListBoxRow()
            row.path = path
            grid = Gtk.Grid(row_spacing=2)
            name = Gtk.Label(label=title(path), xalign=0, hexpand=True, ellipsize=Pango.EllipsizeMode.END)
            name.get_style_context().add_class("echo-row-name")
            grid.attach(name, 0, 0, 2, 1)
            when = Gtk.Label(label=when_words(modified), xalign=0, hexpand=True)
            when.get_style_context().add_class("echo-small")
            grid.attach(when, 0, 1, 1, 1)
            row.length_label = Gtk.Label(xalign=1)
            row.length_label.get_style_context().add_class("echo-small")
            grid.attach(row.length_label, 1, 1, 1, 1)
            row.add(grid)
            self.list.add(row)
            self._measure(row)
            if path == chosen:
                self.list.select_row(row)
        self.list.show_all()
        if self.list.get_selected_row() is None and self.list.get_row_at_index(0):
            self.list.select_row(self.list.get_row_at_index(0))
        if self.recorder is None and self.list.get_row_at_index(0) is None:
            self.current = None
            self.stack.set_visible_child_name("empty")

    def _measure(self, row):
        path = row.path

        def work():
            levels, length = waveform(path)
            GLib.idle_add(lambda: self._measured(row, path, levels, length))

        threading.Thread(target=work, daemon=True).start()

    def _measured(self, row, path, levels, length):
        if row.get_parent() is not None:
            row.length_label.set_text(clock(length))
        if self.current and self.current["path"] == path:
            self.current.update(levels=levels, length=length)
            self.wave.show(levels, length)
            self._update_times()
        return False

    def _row_selected(self, _list, row):
        if row is None or self.recorder is not None:
            return
        if self.current and self.current["path"] == row.path:
            return
        self.stop_playing()
        self.end_trim()
        self.current = {"path": row.path, "levels": [], "length": 0.0}
        self.name_entry.set_text(title(row.path))
        try:
            self.when_label.set_text(when_words(os.stat(row.path).st_mtime))
        except OSError:
            self.when_label.set_text("")
        self.wave.position = 0
        self.wave.show([], 0)
        self.player.set_property("uri", Gio.File.new_for_path(row.path).get_uri())
        self.stack.set_visible_child_name("detail")
        self._measure(row)

    def _list_pressed(self, _list, event):
        if event.button != 3:
            return False
        row = self.list.get_row_at_y(int(event.y))
        if row is None:
            return False
        self.list.select_row(row)
        menu = Gtk.Menu()
        for label, callback in (("Play", self.toggle_play), ("Rename", lambda: self.name_entry.grab_focus()),
                                ("Trim", self.start_trim), ("Show in Drawer", self.show_in_drawer),
                                (None, None), ("Move to Trash", self.trash_selected)):
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if callback:
                item.connect("activate", lambda _i, c=callback: c())
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self.list, None)
        menu.popup_at_pointer(event)
        return True

    # -- recording --

    def toggle_record(self):
        if self.recorder is None:
            self.start_recording()
        else:
            self.stop_recording()

    def start_recording(self):
        self.stop_playing()
        self.end_trim()
        try:
            os.makedirs(folder(), exist_ok=True)
        except OSError as error:
            self._problem("Echo couldn't make the Echo folder in Music.", str(error))
            return
        self.record_path = new_path()
        test = os.environ.get("FREEMAC_ECHO_TEST")
        source = ("audiotestsrc is-live=true wave=pink-noise volume=0.4 ! "
                  "volume name=wobble" if test else "autoaudiosrc")
        description = (f"{source} ! audioconvert ! audioresample ! audio/x-raw,channels=1,rate=48000 ! "
                       f"level interval={int(STEP * Gst.SECOND)} post-messages=true ! "
                       f'opusenc bitrate=64000 ! oggmux ! filesink location="{self.record_path}"')
        try:
            self.recorder = Gst.parse_launch(description)
        except GLib.Error as error:
            self._problem("Echo couldn't start recording.", error.message)
            return
        bus = self.recorder.get_bus()
        bus.add_signal_watch()
        bus.connect("message::element", self._recorder_level)
        bus.connect("message::eos", self._recorder_done)
        bus.connect("message::error", self._recorder_error)
        self.live_levels = []
        self.live_wave.levels = self.live_levels
        self.live_wave.queue_draw()
        self.rec_title.set_text(title(self.record_path))
        self.rec_clock.set_text("0:00")
        self.record_started = time.monotonic()
        self.recorder.set_state(Gst.State.PLAYING)
        self.stack.set_visible_child_name("recording")
        self.record_button.get_style_context().add_class("echo-recording")
        self.record_button.set_tooltip_text("Stop Recording")
        self.list.set_sensitive(False)

    def _recorder_level(self, _bus, message):
        structure = message.get_structure()
        if structure and structure.get_name() == "level":
            value = _db_to_level(list(structure.get_value("rms")))
            wobble = self.recorder.get_by_name("wobble") if self.recorder else None
            if wobble is not None:   # the test sound: make it rise and fall like talking
                t = time.monotonic()
                wobble.set_property("volume", abs(((t * 1.7) % 2) - 1) * (0.4 + 0.6 * abs(((t * 0.31) % 2) - 1)))
            self.live_levels.append(value)

    def stop_recording(self):
        if self.recorder is None:
            return
        self.record_button.set_sensitive(False)
        self.recorder.send_event(Gst.Event.new_eos())

    def _recorder_done(self, *_a):
        self._finish_recording()

    def _recorder_error(self, _bus, message):
        error, debug = message.parse_error()
        print(f"echo: {error.message} ({debug})", file=sys.stderr)
        path = self.record_path
        self._finish_recording()
        if path and os.path.exists(path) and os.path.getsize(path) < 1024:
            try:
                os.remove(path)
            except OSError:
                pass
        self.load()
        self._problem("Echo couldn't hear a microphone.",
                      "Plug one in, or choose one in Dials > Sound, then try again.")

    def _finish_recording(self):
        recorder, self.recorder = self.recorder, None
        if recorder is not None:
            recorder.get_bus().remove_signal_watch()
            recorder.set_state(Gst.State.NULL)
        self.record_button.get_style_context().remove_class("echo-recording")
        self.record_button.set_tooltip_text("Record")
        self.record_button.set_sensitive(True)
        self.list.set_sensitive(True)
        path, self.record_path = self.record_path, None
        self.current = None
        self.stack.set_visible_child_name("detail")
        self.load(choose=path)

    # -- playing --

    def toggle_play(self):
        if not self.current or self.recorder is not None:
            return
        if self.playing:
            self.player.set_state(Gst.State.PAUSED)
            self.playing = False
        else:
            if self.current["length"] and self.wave.position >= self.current["length"] - 0.1:
                self.seek(0)
            self.player.set_state(Gst.State.PLAYING)
            self.playing = True
        self._update_play_button()

    def stop_playing(self):
        self.player.set_state(Gst.State.NULL)
        self.playing = False
        self._update_play_button()

    def _update_play_button(self):
        icon = "media-playback-pause-symbolic" if self.playing else "media-playback-start-symbolic"
        self.play_button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR))
        self.play_button.set_tooltip_text("Pause" if self.playing else "Play")

    def seek(self, seconds):
        if not self.current:
            return
        state = self.player.get_state(0)[1]
        if state in (Gst.State.NULL, Gst.State.READY):
            self.player.set_state(Gst.State.PAUSED)
            self.player.get_state(2 * Gst.SECOND)
        self.player.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE,
                                int(max(0, seconds) * Gst.SECOND))
        self.wave.position = seconds
        self.wave.queue_draw()
        self._update_times()

    def skip(self, seconds):
        if self.current:
            length = self.current["length"] or 0
            self.seek(max(0, min(length, self.wave.position + seconds)))

    def _ended(self, *_a):
        self.playing = False
        self.player.set_state(Gst.State.PAUSED)
        self.wave.position = self.current["length"] if self.current else 0
        self.wave.queue_draw()
        self._update_play_button()
        self._update_times()

    def _play_error(self, _bus, message):
        error, _debug = message.parse_error()
        self.stop_playing()
        self._problem("This recording couldn't be played.", error.message)

    def _tick(self):
        if self.recorder is not None:
            self.rec_clock.set_text(clock(time.monotonic() - self.record_started))
            self.live_wave.queue_draw()
        elif self.playing:
            ok, position = self.player.query_position(Gst.Format.TIME)
            if ok:
                self.wave.position = position / Gst.SECOND
                self.wave.queue_draw()
                self._update_times()
        return True

    def _update_times(self):
        length = self.current["length"] if self.current else 0
        self.at_label.set_text(clock(self.wave.position))
        self.length_label.set_text(f"-{clock(max(0, length - self.wave.position))}")

    # -- changing a recording --

    def _rename(self):
        if not self.current:
            return False
        name = clean_name(self.name_entry.get_text())
        old = self.current["path"]
        if not name or name == title(old):
            self.name_entry.set_text(title(old))
            return False
        new = os.path.join(os.path.dirname(old), name + EXT)
        if os.path.exists(new):
            self._problem(f"There's already a recording called “{name}”.", "Choose another name.")
            self.name_entry.set_text(title(old))
            return False
        try:
            self.stop_playing()
            os.rename(old, new)
        except OSError as error:
            self._problem("The recording couldn't be renamed.", str(error))
            self.name_entry.set_text(title(old))
            return False
        self.current = None
        self.load(choose=new)
        return False

    def start_trim(self):
        if not self.current or not self.current["length"]:
            return
        self.stop_playing()
        self.wave.trimming = True
        self.wave.trim = [0.0, self.current["length"]]
        self.wave.queue_draw()
        self.trim_bar.show_all()
        self.trim_button.set_sensitive(False)

    def end_trim(self):
        self.wave.trimming = False
        self.wave.queue_draw()
        self.trim_bar.hide()
        self.trim_button.set_sensitive(True)

    def _trim_answer(self, _bar, response):
        start, end = self.wave.trim
        self.end_trim()
        if response != Gtk.ResponseType.OK or not self.current:
            return
        length = self.current["length"]
        if start <= 0.05 and end >= length - 0.05:
            return
        path = self.current["path"]
        self.stop_playing()
        self.set_sensitive(False)

        def work():
            try:
                trim(path, start, end)
                problem = None
            except RuntimeError as error:
                problem = str(error)
            GLib.idle_add(lambda: self._trimmed(path, problem))

        threading.Thread(target=work, daemon=True).start()

    def _trimmed(self, path, problem):
        self.set_sensitive(True)
        if problem:
            self._problem("The recording couldn't be trimmed.", problem)
        self.current = None
        self.load(choose=path)
        return False

    def trash_selected(self):
        if not self.current or self.recorder is not None:
            return
        self.stop_playing()
        try:
            Gio.File.new_for_path(self.current["path"]).trash(None)
        except GLib.Error as error:
            self._problem("The recording couldn't be moved to the Trash.", error.message)
            return
        self.current = None
        self.load()

    def show_in_drawer(self):
        path = self.current["path"] if self.current else folder()
        try:
            Gio.Subprocess.new(["freemac-drawer", path], Gio.SubprocessFlags.NONE)
        except GLib.Error:
            pass

    def _problem(self, text, detail):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                                   buttons=Gtk.ButtonsType.OK, text=text, secondary_text=detail)
        dialog.connect("response", lambda d, _r: d.destroy())
        dialog.show()

    def _key(self, _w, event):
        if self.name_entry.has_focus():
            if event.keyval == Gdk.KEY_Escape:
                self.name_entry.set_text(title(self.current["path"]) if self.current else "")
                self.list.grab_focus()
                return True
            return False
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        if mods:
            return False
        if event.keyval == Gdk.KEY_space:
            self.toggle_play()
            return True
        if event.keyval == Gdk.KEY_Left:
            self.skip(-SKIP)
            return True
        if event.keyval == Gdk.KEY_Right:
            self.skip(SKIP)
            return True
        if event.keyval in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self.trash_selected()
            return True
        if event.keyval == Gdk.KEY_Escape and self.wave.trimming:
            self.end_trim()
            return True
        return False

    def _closing(self, *_a):
        GLib.source_remove(self.ticker)
        if self.recorder is not None:
            # Finish the file properly before the window goes.
            self.recorder.send_event(Gst.Event.new_eos())
            self.recorder.get_bus().timed_pop_filtered(3 * Gst.SECOND,
                                                       Gst.MessageType.EOS | Gst.MessageType.ERROR)
            self.recorder.set_state(Gst.State.NULL)
        self.player.set_state(Gst.State.NULL)


def menubar():
    return menus.menubar([
        ("_File", [[("New Recording", "win.record", "<Ctrl>n")],
                   [("Show in Drawer", "win.show-in-drawer", "<Ctrl>r")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Rename", "win.rename", None), ("Trim Recording", "win.trim", "<Ctrl>t")],
                   [("Move to Trash", "win.trash", "<Ctrl>BackSpace")]]),
        ("_Controls", [[("Play/Pause", "win.play", "space")],
                       [(f"Skip Back {SKIP} Seconds", "win.back", "Left"),
                        (f"Skip Forward {SKIP} Seconds", "win.forward", "Right")]]),
    ])


class Echo(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        Gst.init(None)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.record", "<Control>n"), ("win.close", "<Control>w"),
                             ("win.trim", "<Control>t"), ("win.trash", "<Control>BackSpace"),
                             ("win.show-in-drawer", "<Control>r")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-echo")
    return Echo().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
