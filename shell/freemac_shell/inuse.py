# SPDX-License-Identifier: GPL-3.0-or-later
"""Which apps are using the microphone or the camera right now, for the dot
in the menu bar: orange while something listens, green while something
watches (as a camera usually listens too, green wins).

The sound server, PipeWire, tells us about every recording stream as it
starts and stops (pw-dump --monitor), so the dot comes on at once. A camera
can also be opened straight from /dev/video*, so every few seconds the apps
of the person at the screen are checked for an open camera too. Original
freemac code.
"""
import codecs
import glob
import json
import os
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib  # noqa: E402

from . import apps  # noqa: E402

MIC, CAMERA = "microphone", "camera"
# The sound server and its helper hold cameras open for the apps that ask
# through them; those apps are found from their own streams instead.
SERVERS = {"pipewire", "wireplumber", "pipewire-pulse"}
CAMERA_EVERY = 3   # seconds


def _name(props):
    """The app's name as the Dock shows it."""
    binary = props.get("application.process.binary") or ""
    if binary and apps.app_info(binary):
        return apps.display_name(binary)
    return props.get("application.name") or binary.replace("-", " ").title() or "An app"


def _uses(info):
    """MIC, CAMERA or None for one PipeWire node."""
    if not info or info.get("state") != "running":
        return None
    props = info.get("props") or {}
    kind = props.get("media.class")
    if kind == "Stream/Input/Audio" and props.get("stream.capture.sink") not in ("true", True):
        return MIC   # recording the speakers, as a screen recorder does, isn't listening
    if kind == "Stream/Input/Video":
        return CAMERA
    return None


def _proc_name(pid):
    try:
        with open(f"/proc/{pid}/comm") as comm:
            name = comm.read().strip()
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return None
    return exe or name


def camera_users():
    """Names of the apps holding a camera open themselves."""
    if not glob.glob("/dev/video*"):
        return set()
    found, me = set(), os.getuid()
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != me:
                continue
            fds = os.scandir(f"/proc/{entry.name}/fd")
            holding = any(os.readlink(fd.path).startswith("/dev/video") for fd in fds)
        except OSError:
            continue
        if not holding:
            continue
        binary = _proc_name(entry.name)
        if binary and binary not in SERVERS:
            found.add(apps.display_name(binary) if apps.app_info(binary) else binary.title())
    return found


class Watcher:
    """Calls on_change() whenever the set of apps using the microphone or
    camera changes. users() is {name: {MIC, CAMERA}}."""

    def __init__(self, on_change):
        self.on_change = on_change
        self.nodes = {}       # PipeWire node id -> (MIC or CAMERA, app name)
        self.cameras = set()
        self._shown = None
        self._buffer, self._decoder = "", json.JSONDecoder()
        self.proc = None
        self._start()
        GLib.timeout_add_seconds(CAMERA_EVERY, self._check_cameras)

    def _start(self):
        if not shutil.which("pw-dump"):
            return False
        try:
            self.proc = subprocess.Popen(["pw-dump", "--monitor", "--no-colors"], stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, text=True, bufsize=1)
        except OSError:
            return False
        self._buffer, self._utf8 = "", codecs.getincrementaldecoder("utf-8")("replace")
        self.nodes = {}
        channel = GLib.IOChannel.unix_new(self.proc.stdout.fileno())
        GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP,
                          self._read)
        return False

    def _read(self, _channel, condition):
        data = os.read(self.proc.stdout.fileno(), 65536) if condition & GLib.IOCondition.IN else b""
        if not data:
            # The sound server restarted: start watching it again shortly.
            self.proc.wait()
            self.nodes = {}
            self._changed()
            GLib.timeout_add_seconds(5, self._start)
            return False
        self._buffer += self._utf8.decode(data)
        while True:
            text = self._buffer.lstrip()
            if not text:
                self._buffer = ""
                break
            try:
                objects, end = self._decoder.raw_decode(text)
            except ValueError:
                self._buffer = text
                break   # wait for the rest of this update
            self._buffer = text[end:]
            for obj in objects if isinstance(objects, list) else ():
                self._apply(obj)
        self._changed()
        return True

    def _apply(self, obj):
        node = obj.get("id")
        info = obj.get("info")
        if info is None:          # gone
            self.nodes.pop(node, None)
            return
        if obj.get("type") != "PipeWire:Interface:Node":
            return
        use = _uses(info)
        if use:
            self.nodes[node] = (use, _name(info.get("props") or {}))
        else:
            self.nodes.pop(node, None)

    def _check_cameras(self):
        self.cameras = camera_users()
        self._changed()
        return True

    def users(self):
        found = {}
        for use, name in self.nodes.values():
            found.setdefault(name, set()).add(use)
        for name in self.cameras:
            found.setdefault(name, set()).add(CAMERA)
        return found

    def _changed(self):
        now = self.users()
        if now != self._shown:
            self._shown = now
            self.on_change()


def describe(users):
    """'Web is using the microphone.' lines, one per app, for the menu."""
    lines = []
    for name in sorted(users):
        uses = users[name]
        what = "the camera and microphone" if uses == {MIC, CAMERA} else f"the {next(iter(uses))}"
        lines.append(f"{name} is using {what}")
    return lines
