# SPDX-License-Identifier: GPL-3.0-or-later
"""Pose: take pictures of yourself with the computer's camera.

The camera's picture fills the window, shown as a mirror would show you.
The round button under it takes a picture after a 3, 2, 1 countdown (or at
once, with the countdown turned off), with a flash of white and a shutter
sound. Effects bends, colours and plays with the picture: pick one in the
strip that the Effects button shows, and pictures are taken with it.

Pictures are saved in Pictures/Pose and shown in a strip along the bottom,
newest first: double-click one to open it, or right-click it to show it in
Drawer or move it to the Trash.

GStreamer does the work: the camera (v4l2src) goes through videoflip for the
mirror, then the chosen effect, into a gtksink whose widget is the picture.
A picture is the last frame the sink showed. Effects are swapped while the
camera runs, by holding the stream for a moment just before the effect.

FREEMAC_POSE_TEST=1 shows a moving test picture in place of a camera, and
FREEMAC_POSE_TEST=/path/to/picture.png shows that picture.

Original freemac code.
"""
import os
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import menus, style  # noqa: E402

try:
    gi.require_version("Gst", "1.0")
    gi.require_version("GstVideo", "1.0")
    from gi.repository import Gst, GstVideo  # noqa: E402
    Gst.init(None)
except (ImportError, ValueError):
    Gst = GstVideo = None

APP_ID = "org.freemac.Pose"
COUNT_FROM = 3
THUMB = 76               # height of the pictures in the strip
SHOWN = 60               # how many of the newest pictures the strip shows
SOUNDS = "/usr/share/sounds/freemac"

# (name, the elements between two videoconverts, elements it needs)
EFFECTS = [
    ("Normal", "identity", ()),
    ("Black & White", "videobalance saturation=0 contrast=1.1", ("videobalance",)),
    ("Bright", "videobalance saturation=1.9 contrast=1.15 brightness=0.04", ("videobalance",)),
    ("Sepia", "coloreffects preset=sepia", ("coloreffects",)),
    ("Heat", "coloreffects preset=heat", ("coloreffects",)),
    ("X-Ray", "coloreffects preset=xray", ("coloreffects",)),
    ("Comic", "edgetv", ("edgetv",)),
    ("Old Movie", "agingtv", ("agingtv",)),
    ("Bulge", "bulge", ("bulge",)),
    ("Squeeze", "pinch intensity=0.5", ("pinch",)),
    ("Twirl", "twirl angle=2.4", ("twirl",)),
    ("Fish Eye", "fisheye", ("fisheye",)),
    ("Stretch", "stretch intensity=0.5", ("stretch",)),
    ("Tunnel", "tunnel", ("tunnel",)),
    ("Mirror", "mirror mode=left", ("mirror",)),
    ("Kaleidoscope", "kaleidoscope", ("kaleidoscope",)),
    ("Marble", "marble", ("marble",)),
    ("Wobble", "warptv", ("warptv",)),
    ("Spin", "vertigotv", ("vertigotv",)),
    ("Ripple", "rippletv mode=1", ("rippletv",)),
    ("Dice", "dicetv", ("dicetv",)),
    ("Disco", "shagadelictv", ("shagadelictv",)),
    ("Trails", "streaktv", ("streaktv",)),
    ("Glow", "radioactv", ("radioactv",)),
]

CSS = b"""
.pose-view { background: black; }
.pose-message { color: alpha(white, 0.8); font-size: 1.1em; }
.pose-count { color: white; font-size: 96px; font-weight: 700;
  text-shadow: 0 2px 12px alpha(black, 0.6); }
.pose-flash { background: white; }
.pose-bar { background: #2a2a2c; border-top: 1px solid alpha(black, 0.5); padding: 8px 14px; }
.pose-bar button.pose-tool { background: alpha(white, 0.08); color: #e8e8ea; border: none;
  box-shadow: none; border-radius: 7px; padding: 4px 12px; }
.pose-bar button.pose-tool:hover { background: alpha(white, 0.16); }
.pose-bar button.pose-tool:checked { background: #2f7bf5; color: white; }
.pose-shutter { background: #e5342f; border-radius: 999px; min-width: 52px; min-height: 52px;
  padding: 0; border: 3px solid alpha(white, 0.85); box-shadow: 0 1px 3px alpha(black, 0.5);
  color: white; }
.pose-shutter:hover { background: #f0473f; }
.pose-shutter:active { background: #c62a25; }
.pose-shutter:disabled { background: #6a3a38; color: alpha(white, 0.5); }
.pose-effects { background: #1e1e20; padding: 8px 10px; }
.pose-effects button { background: alpha(white, 0.07); color: #e8e8ea; border: none; box-shadow: none;
  border-radius: 14px; padding: 4px 12px; margin: 0 3px; }
.pose-effects button:hover { background: alpha(white, 0.15); }
.pose-effects button:checked { background: #2f7bf5; color: white; }
.pose-strip { background: #1e1e20; }
.pose-strip flowboxchild { padding: 3px; border-radius: 5px; }
.pose-strip flowboxchild:selected { background: #2f7bf5; }
.pose-strip-note { color: alpha(white, 0.5); }
"""


def has(element):
    return Gst is not None and Gst.ElementFactory.find(element) is not None


def effects():
    """The effects this computer can show."""
    return [(name, desc) for name, desc, needs in EFFECTS if all(has(n) for n in needs)]


def pictures_folder():
    base = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES) or os.path.expanduser("~/Pictures")
    return os.path.join(base, "Pose")


def picture_name(when=None):
    """Pose 2026-11-21 at 09.15.02.jpg, as screenshots are named."""
    stamp = time.localtime(when or time.time())
    return time.strftime("Pose %Y-%m-%d at %H.%M.%S", stamp) + ".jpg"


def free_path(folder, name):
    path = os.path.join(folder, name)
    stem, ext = os.path.splitext(path)
    n = 2
    while os.path.exists(path):
        path = f"{stem} {n}{ext}"
        n += 1
    return path


def saved_pictures(folder):
    try:
        names = [n for n in os.listdir(folder) if n.lower().endswith((".jpg", ".jpeg", ".png"))
                 and not n.startswith(".")]
    except OSError:
        return []
    found = []
    for name in names:
        path = os.path.join(folder, name)
        try:
            found.append((os.path.getmtime(path), path))
        except OSError:
            pass
    return [p for _t, p in sorted(found, reverse=True)]


def play_sound(name):
    path = os.path.join(SOUNDS, name)
    if not os.path.exists(path):
        return
    for player in ("pw-play", "paplay"):
        try:
            Gio.Subprocess.new([player, path], Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE)
            return
        except GLib.Error:
            continue


class Cameras:
    """The cameras plugged in, as (name, Gst.Device), kept up to date."""

    def __init__(self, changed):
        self.changed = changed
        self.monitor = None
        self.found = []
        if Gst is None:
            return
        self.monitor = Gst.DeviceMonitor.new()
        self.monitor.add_filter("Video/Source", None)
        bus = self.monitor.get_bus()
        bus.add_watch(GLib.PRIORITY_DEFAULT, self._message)
        try:
            self.monitor.start()
        except GLib.Error:
            self.monitor = None
            return
        self._read()

    def _read(self):
        found, seen = [], set()
        for device in self.monitor.get_devices() if self.monitor else []:
            props = device.get_properties()
            path = props.get_string("device.path") or props.get_string("api.v4l2.path") if props else None
            api = props.get_string("device.api") if props else None
            # PipeWire offers the same cameras again; keep one of each, the
            # camera's own (v4l2) where both are offered.
            key = path or device.get_display_name()
            if key in seen:
                continue
            if api and api != "v4l2" and any(
                    (d.get_properties() and (d.get_properties().get_string("device.path") == path))
                    for d in self.monitor.get_devices() if d is not device):
                continue
            seen.add(key)
            found.append((device.get_display_name(), device))
        self.found = sorted(found, key=lambda f: f[0])

    def _message(self, _bus, message):
        if message.type in (Gst.MessageType.DEVICE_ADDED, Gst.MessageType.DEVICE_REMOVED):
            self._read()
            self.changed()
        return True

    def stop(self):
        if self.monitor:
            self.monitor.stop()


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Pose")
        self.set_default_size(900, 680)
        self.pipeline = None
        self.effect_bin = None
        self.flip = None
        self.sink = None
        self.effect = "Normal"
        self.mirror = True
        self.countdown_on = True
        self.counting = 0
        self.camera_name = None
        self.test = bool(os.environ.get("FREEMAC_POSE_TEST"))
        self.folder = pictures_folder()

        header = Gtk.HeaderBar(show_close_button=True, title="Pose")
        self.set_titlebar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)

        self.overlay = Gtk.Overlay()
        self.overlay.get_style_context().add_class("pose-view")
        self.view = Gtk.EventBox()
        self.view.get_style_context().add_class("pose-view")
        self.message = Gtk.Label(wrap=True, justify=Gtk.Justification.CENTER, max_width_chars=40)
        self.message.get_style_context().add_class("pose-message")
        self.view.add(self.message)
        self.overlay.add(self.view)
        self.count = Gtk.Label(halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.count.get_style_context().add_class("pose-count")
        self.overlay.add_overlay(self.count)
        self.overlay.set_overlay_pass_through(self.count, True)
        self.flash = Gtk.EventBox()
        self.flash.get_style_context().add_class("pose-flash")
        self.flash.set_no_show_all(True)
        self.overlay.add_overlay(self.flash)
        self.overlay.set_overlay_pass_through(self.flash, True)
        box.pack_start(self.overlay, True, True, 0)

        self.effects_revealer = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_UP,
                                             transition_duration=200)
        self.effects_revealer.add(self._build_effects())
        box.pack_start(self.effects_revealer, False, False, 0)

        bar = Gtk.Box()
        bar.get_style_context().add_class("pose-bar")
        self.effects_button = Gtk.ToggleButton(label="Effects")
        self.effects_button.get_style_context().add_class("pose-tool")
        self.effects_button.set_can_focus(False)
        self.effects_button.set_valign(Gtk.Align.CENTER)
        self.effects_button.connect("toggled", lambda b: self.show_effects(b.get_active()))
        bar.pack_start(self.effects_button, False, False, 0)
        self.shutter = Gtk.Button()
        self.shutter.set_image(Gtk.Image.new_from_icon_name("camera-photo-symbolic", Gtk.IconSize.LARGE_TOOLBAR))
        self.shutter.get_style_context().add_class("pose-shutter")
        self.shutter.set_tooltip_text("Take Photo (Space)")
        self.shutter.set_can_focus(False)
        self.shutter.set_valign(Gtk.Align.CENTER)
        self.shutter.connect("clicked", lambda _b: self.take())
        bar.set_center_widget(self.shutter)
        self.timer_button = Gtk.ToggleButton()
        self.timer_button.set_image(Gtk.Image.new_from_icon_name("alarm-symbolic", Gtk.IconSize.BUTTON))
        self.timer_button.set_always_show_image(True)
        self.timer_button.set_label("3 seconds")
        self.timer_button.get_style_context().add_class("pose-tool")
        self.timer_button.set_tooltip_text("Count down from 3 before taking a picture")
        self.timer_button.set_can_focus(False)
        self.timer_button.set_valign(Gtk.Align.CENTER)
        self.timer_button.set_active(True)
        self.timer_button.connect("toggled", lambda b: self.set_countdown(b.get_active()))
        bar.pack_end(self.timer_button, False, False, 0)
        box.pack_start(bar, False, False, 0)

        box.pack_start(self._build_strip(), False, False, 0)

        menus.add_actions(self, {
            "take": self.take, "close": self.close, "trash": self.trash_selected,
            "show-in-drawer": self.show_in_drawer, "open-picture": self.open_selected,
            "show-folder": self.show_folder,
        })
        self.mirror_action = menus.add_toggle(self, "mirror", True, self.set_mirror)
        self.countdown_action = menus.add_toggle(self, "countdown", True,
                                                 lambda on: self.timer_button.set_active(on))
        self.effects_action = menus.add_toggle(self, "effects", False,
                                               lambda on: self.effects_button.set_active(on))
        self.connect("key-press-event", self._key)
        self.connect("delete-event", self._closing)

        self.cameras = Cameras(self._cameras_changed)
        self.folder_watch = None
        self._watch_folder()
        self.show_all()
        self.load_strip()
        self.start()

    # -- effects --

    def _build_effects(self):
        scroller = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER,
                                      hscrollbar_policy=Gtk.PolicyType.AUTOMATIC)
        scroller.get_style_context().add_class("pose-effects")
        style.sideways_wheel(scroller)
        row = Gtk.Box()
        self.effect_buttons = {}
        for name, _desc in effects():
            button = Gtk.ToggleButton(label=name)
            button.set_can_focus(False)
            button.connect("toggled", self._effect_toggled, name)
            row.pack_start(button, False, False, 0)
            self.effect_buttons[name] = button
        self.effect_buttons["Normal"].set_active(True)
        scroller.add(row)
        return scroller

    def _effect_toggled(self, button, name):
        if getattr(self, "_setting", False):
            return
        if not button.get_active():
            if name == self.effect:
                # The chosen effect stays chosen; pick another to change it.
                self._setting = True
                button.set_active(True)
                self._setting = False
            return
        self.set_effect(name)

    def set_effect(self, name):
        self._setting = True
        for other, button in self.effect_buttons.items():
            button.set_active(other == name)
        self._setting = False
        self.effect = name
        self._swap_effect()
        header = self.get_titlebar()
        header.set_subtitle(name if name != "Normal" else None)

    def show_effects(self, on):
        self.effects_revealer.set_reveal_child(on)
        if self.effects_action.get_state().get_boolean() != on:
            self.effects_action.set_state(GLib.Variant("b", on))

    def _effect_description(self):
        for name, desc in effects():
            if name == self.effect:
                return desc
        return "identity"

    def _make_effect(self):
        return Gst.parse_bin_from_description(
            f"videoconvert ! {self._effect_description()} ! videoconvert", True)

    def _swap_effect(self):
        """Put the chosen effect in place while the camera keeps running."""
        if self.pipeline is None or self.flip is None:
            return
        pad = self.flip.get_static_pad("src")
        new = self._make_effect()

        def blocked(pad, info):
            old = self.effect_bin
            after = self.convert
            if old is not None:
                self.flip.unlink(old)
                old.unlink(after)
                self.pipeline.remove(old)
                old.set_state(Gst.State.NULL)
            self.pipeline.add(new)
            self.flip.link(new)
            new.link(after)
            new.sync_state_with_parent()
            self.effect_bin = new
            return Gst.PadProbeReturn.REMOVE

        if self.pipeline.get_state(0)[1] != Gst.State.PLAYING:
            # Nothing flows, so nothing to hold: swap straight away.
            blocked(pad, None)
            return
        pad.add_probe(Gst.PadProbeType.BLOCK_DOWNSTREAM | Gst.PadProbeType.IDLE, blocked)

    # -- the camera --

    def _source(self):
        """The camera (or the test picture) as a bin with one source pad."""
        if self.test:
            picture = os.environ.get("FREEMAC_POSE_TEST", "")
            if os.path.isfile(picture):
                # A still picture standing in for the camera, for trying effects.
                return Gst.parse_bin_from_description(
                    f"filesrc location=\"{picture}\" ! pngdec ! videoconvert ! imagefreeze is-live=true ! videoconvert",
                    True), "Test Picture"
            return Gst.parse_bin_from_description(
                "videotestsrc is-live=true pattern=ball background-color=0xff3060a0 ! "
                "video/x-raw,width=960,height=540,framerate=30/1 ! videoconvert", True), "Test Picture"
        if not self.cameras.found:
            return None, None
        name, device = self.cameras.found[0]
        for found_name, found_device in self.cameras.found:
            if found_name == self.camera_name:
                name, device = found_name, found_device
        element = device.create_element(None)
        if element is None:
            return None, None
        source = Gst.Bin.new("camera")
        caps = Gst.ElementFactory.make("capsfilter", None)
        # Most cameras offer a size near 720p; bigger ones make the effects slow.
        caps.set_property("caps", Gst.Caps.from_string(
            "video/x-raw,width=(int)[1,1280],height=(int)[1,720];"
            "image/jpeg,width=(int)[1,1280],height=(int)[1,720]"))
        decode = Gst.ElementFactory.make("decodebin", None)
        convert = Gst.ElementFactory.make("videoconvert", None)
        for part in (element, caps, decode, convert):
            source.add(part)
        element.link(caps)
        caps.link(decode)
        decode.connect("pad-added", lambda _d, pad: pad.link(convert.get_static_pad("sink")))
        source.add_pad(Gst.GhostPad.new("src", convert.get_static_pad("src")))
        return source, name

    def start(self):
        self.stop()
        if Gst is None:
            self.say("Pose can't use the camera: GStreamer isn't installed.")
            return
        sink = Gst.ElementFactory.make("gtksink", None)
        if sink is None:
            self.say("Pose can't show the camera: GStreamer's GTK video output is missing.")
            return
        source, name = self._source()
        if source is None:
            self.say("No camera is connected.\n\nPlug one in, and you'll see yourself here.")
            return
        self.camera_name = name
        pipeline = Gst.Pipeline.new("pose")
        self.flip = Gst.ElementFactory.make("videoflip", None)
        self.flip.set_property("method", "horizontal-flip" if self.mirror else "none")
        self.convert = Gst.ElementFactory.make("videoconvert", None)
        for part in (source, self.flip, self.convert, sink):
            pipeline.add(part)
        source.link(self.flip)
        self.convert.link(sink)
        self.pipeline = pipeline
        self.effect_bin = None
        self.sink = sink
        self._swap_effect()
        widget = sink.get_property("widget")
        widget.set_hexpand(True)
        widget.set_vexpand(True)
        child = self.view.get_child()
        if child is not None:
            self.view.remove(child)
        self.view.add(widget)
        widget.show()
        bus = pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._message)
        pipeline.set_state(Gst.State.PLAYING)
        self.shutter.set_sensitive(True)

    def stop(self):
        if self.pipeline is not None:
            self.pipeline.get_bus().remove_signal_watch()
            self.pipeline.set_state(Gst.State.NULL)
        self.pipeline = self.sink = self.flip = self.effect_bin = None

    def say(self, words):
        self.stop()
        child = self.view.get_child()
        if child is not self.message:
            if child is not None:
                self.view.remove(child)
            self.view.add(self.message)
        self.message.set_text(words)
        self.message.show()
        self.shutter.set_sensitive(False)

    def _message(self, _bus, message):
        if message.type == Gst.MessageType.ERROR:
            error, debug = message.parse_error()
            print(f"pose: {error.message} ({debug})", file=sys.stderr)
            busy = "busy" in (error.message or "").lower() or "resource" in (error.message or "").lower()
            if busy:
                self.say("The camera is being used by another app.\n\nQuit that app, then try again.")
            else:
                self.say(f"The camera stopped working.\n\n{error.message}")
            GLib.timeout_add_seconds(4, self._retry)

    def _retry(self):
        if self.pipeline is None and (self.cameras.found or self.test):
            self.start()
        return False

    def _cameras_changed(self):
        if self.pipeline is None and self.cameras.found:
            self.start()
        elif self.pipeline is not None and not self.test and \
                self.camera_name not in [n for n, _d in self.cameras.found]:
            if self.cameras.found:
                self.start()
            else:
                self.say("The camera was disconnected.\n\nPlug it in again to go on.")
        self.get_application().update_cameras()

    def use_camera(self, name):
        self.camera_name = name
        self.start()

    def set_mirror(self, on):
        self.mirror = on
        if self.flip is not None:
            self.flip.set_property("method", "horizontal-flip" if on else "none")

    def set_countdown(self, on):
        self.countdown_on = on
        if self.countdown_action.get_state().get_boolean() != on:
            self.countdown_action.set_state(GLib.Variant("b", on))

    # -- taking a picture --

    def take(self):
        if self.pipeline is None or self.counting:
            return
        self.shutter.set_sensitive(False)
        if not self.countdown_on:
            self._snap()
            return
        self.counting = COUNT_FROM
        self._show_count()
        GLib.timeout_add(1000, self._tick)

    def _show_count(self):
        self.count.set_text(str(self.counting))
        self.count.show()
        play_sound("tick.wav")

    def _tick(self):
        self.counting -= 1
        if self.counting > 0:
            self._show_count()
            return True
        self.count.set_text("")
        self._snap()
        return False

    def _snap(self):
        self.counting = 0
        frame = self._frame()
        play_sound("shutter.wav")
        self.flash.show()
        self.flash.set_opacity(1.0)
        start = time.monotonic()

        def fade():
            left = 1.0 - (time.monotonic() - start) / 0.45
            if left <= 0:
                self.flash.hide()
                return False
            self.flash.set_opacity(left)
            return True

        GLib.timeout_add(16, fade)
        if self.pipeline is not None:
            self.shutter.set_sensitive(True)
        if frame is None:
            self._problem("The picture couldn't be taken.", "The camera didn't give Pose a picture. Try again.")
            return
        try:
            os.makedirs(self.folder, exist_ok=True)
            path = free_path(self.folder, picture_name())
            frame.savev(path, "jpeg", ["quality"], ["92"])
        except (GLib.Error, OSError) as error:
            self._problem("The picture couldn't be saved.", str(error))
            return
        self.load_strip(select=path)

    def _frame(self):
        """The picture the camera is showing now, as a GdkPixbuf."""
        if self.sink is None or GstVideo is None:
            return None
        sample = self.sink.get_property("last-sample")
        if sample is None:
            return None
        caps = Gst.Caps.from_string("video/x-raw,format=RGB")
        try:
            converted = GstVideo.video_convert_sample(sample, caps, Gst.SECOND)
        except GLib.Error:
            return None
        if converted is None:
            return None
        info = GstVideo.VideoInfo.new_from_caps(converted.get_caps()) \
            if hasattr(GstVideo.VideoInfo, "new_from_caps") else None
        structure = converted.get_caps().get_structure(0)
        width = structure.get_value("width")
        height = structure.get_value("height")
        stride = info.stride[0] if info is not None else (width * 3 + 3) & ~3
        buffer = converted.get_buffer()
        ok, mapped = buffer.map(Gst.MapFlags.READ)
        if not ok:
            return None
        try:
            data = GLib.Bytes.new(bytes(mapped.data))
        finally:
            buffer.unmap(mapped)
        return GdkPixbuf.Pixbuf.new_from_bytes(data, GdkPixbuf.Colorspace.RGB, False, 8,
                                               width, height, stride).copy()

    def _problem(self, title, detail):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                                   buttons=Gtk.ButtonsType.OK, text=title, secondary_text=detail)
        dialog.run()
        dialog.destroy()

    # -- the pictures taken --

    def _build_strip(self):
        self.strip = Gtk.FlowBox(orientation=Gtk.Orientation.VERTICAL, min_children_per_line=1,
                                 max_children_per_line=1, selection_mode=Gtk.SelectionMode.SINGLE,
                                 activate_on_single_click=False, homogeneous=False)
        self.strip.connect("child-activated", lambda _s, _c: self.open_selected())
        self.strip.connect("button-press-event", self._strip_pressed)
        self.strip.get_style_context().add_class("pose-strip")
        self.strip.set_halign(Gtk.Align.START)
        self.strip.set_valign(Gtk.Align.CENTER)
        self.strip_note = Gtk.Label(label="Pictures you take show up here.")
        self.strip_note.get_style_context().add_class("pose-strip-note")
        self.strip_stack = Gtk.Stack()
        scroller = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER,
                                      hscrollbar_policy=Gtk.PolicyType.AUTOMATIC)
        scroller.add(self.strip)
        style.sideways_wheel(scroller)
        self.strip_stack.add_named(scroller, "pictures")
        self.strip_stack.add_named(self.strip_note, "empty")
        self.strip_stack.set_size_request(-1, THUMB + 18)
        self.strip_stack.get_style_context().add_class("pose-strip")
        frame = Gtk.EventBox()
        frame.get_style_context().add_class("pose-strip")
        frame.add(self.strip_stack)
        return frame

    def load_strip(self, select=None):
        for child in self.strip.get_children():
            self.strip.remove(child)
        paths = saved_pictures(self.folder)[:SHOWN]
        for path in paths:
            try:
                picture = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, -1, THUMB, True)
            except GLib.Error:
                continue
            image = Gtk.Image.new_from_pixbuf(picture)
            image.set_tooltip_text(os.path.basename(path))
            child = Gtk.FlowBoxChild()
            child.path = path
            child.add(image)
            self.strip.add(child)
            if path == select:
                self.strip.select_child(child)
        self.strip.show_all()
        self.strip_stack.set_visible_child_name("pictures" if paths else "empty")

    def _watch_folder(self):
        try:
            os.makedirs(self.folder, exist_ok=True)
            self.folder_watch = Gio.File.new_for_path(self.folder).monitor_directory(
                Gio.FileMonitorFlags.WATCH_MOVES, None)
        except (GLib.Error, OSError):
            return
        self.folder_watch.set_rate_limit(500)
        self._reload_soon = 0

        def changed(*_):
            if not self._reload_soon:
                self._reload_soon = GLib.timeout_add(400, self._reload)

        self.folder_watch.connect("changed", changed)

    def _reload(self):
        self._reload_soon = 0
        chosen = self.selected()
        self.load_strip(select=chosen)
        return False

    def selected(self):
        chosen = self.strip.get_selected_children()
        return chosen[0].path if chosen else None

    def _strip_pressed(self, _strip, event):
        if event.button != 3:
            return False
        child = self.strip.get_child_at_pos(int(event.x), int(event.y))
        if child is None:
            return False
        self.strip.select_child(child)
        menu = Gtk.Menu()
        for label, callback in (("Open", self.open_selected), ("Show in Drawer", self.show_in_drawer),
                                (None, None), ("Move to Trash", self.trash_selected)):
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if callback:
                item.connect("activate", lambda _i, c=callback: c())
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self.strip, None)
        menu.popup_at_pointer(event)
        return True

    def open_selected(self):
        path = self.selected()
        if path:
            try:
                Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
            except GLib.Error:
                pass

    def show_in_drawer(self):
        path = self.selected()
        try:
            Gio.Subprocess.new(["freemac-drawer", path or self.folder], Gio.SubprocessFlags.NONE)
        except GLib.Error:
            pass

    def show_folder(self):
        os.makedirs(self.folder, exist_ok=True)
        try:
            Gio.Subprocess.new(["freemac-drawer", self.folder], Gio.SubprocessFlags.NONE)
        except GLib.Error:
            pass

    def trash_selected(self):
        path = self.selected()
        if not path:
            return
        try:
            Gio.File.new_for_path(path).trash(None)
        except GLib.Error as error:
            self._problem("The picture couldn't be moved to the Trash.", error.message)
            return
        self.load_strip()

    # -- keys --

    def _key(self, _w, event):
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        key = event.keyval
        if not mods and key in (Gdk.KEY_space, Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.take()
            return True
        if not mods and key == Gdk.KEY_Escape and self.counting:
            self.counting = 0
            self.count.set_text("")
            self.shutter.set_sensitive(self.pipeline is not None)
            return True
        if not mods and key == Gdk.KEY_Delete:
            self.trash_selected()
            return True
        return False

    def _closing(self, *_):
        self.stop()
        self.cameras.stop()
        return False


def menubar(camera_menu):
    bar = menus.menubar([
        ("_File", [[("Take Photo", "win.take", "<Ctrl>t")],
                   [("Open Picture", "win.open-picture", "<Ctrl>o"),
                    ("Show in Drawer", "win.show-in-drawer", "<Ctrl>r"),
                    ("Show All Pictures", "win.show-folder", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Move to Trash", "win.trash", "<Ctrl>BackSpace")]]),
        ("_View", [[("Show Effects", "win.effects", None)],
                   [("Mirror Picture", "win.mirror", None),
                    ("Countdown", "win.countdown", None)]]),
    ])
    # The Camera menu is kept and changed in place, as cameras come and go.
    bar.append_submenu("_Camera", camera_menu)
    return bar


class Pose(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": self.quit_all})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.take", "<Control>t"), ("win.close", "<Control>w"),
                             ("win.open-picture", "<Control>o"), ("win.show-in-drawer", "<Control>r"),
                             ("win.trash", "<Control>BackSpace")):
            self.set_accels_for_action(action, [keys])
        self.camera_menu = Gio.Menu()
        self.camera_menu.append("No Camera", "win.no-camera")
        self.set_menubar(menubar(self.camera_menu))

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
            self.update_cameras()
        self.window.present()

    def update_cameras(self):
        window = self.window
        if window is None:
            return
        names = [n for n, _d in window.cameras.found]
        for i, name in enumerate(names):
            action_name = f"camera-{i}"
            if window.lookup_action(action_name) is None:
                action = Gio.SimpleAction.new(action_name, None)
                window.add_action(action)
            action = window.lookup_action(action_name)
            try:
                action.disconnect_by_func(window.use_camera)
            except TypeError:
                pass
            action.connect("activate", lambda _a, _p, n=name: window.use_camera(n))
        if window.lookup_action("no-camera") is None:
            idle = Gio.SimpleAction.new("no-camera", None)
            idle.set_enabled(False)
            window.add_action(idle)
        self.camera_menu.remove_all()
        for i, name in enumerate(names):
            self.camera_menu.append(name, f"win.camera-{i}")
        if not names:
            self.camera_menu.append("No Camera", "win.no-camera")

    def quit_all(self):
        for window in self.get_windows():
            window.close()


def main():
    GLib.set_prgname("freemac-pose")
    return Pose().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
