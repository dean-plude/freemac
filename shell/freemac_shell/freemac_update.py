# SPDX-License-Identifier: GPL-3.0-or-later
"""New versions of freemac, from your side: whether one is on offer, the one
downloaded and waiting for a restart, and what the last restart installed.

The work that needs root (downloading, checking and installing) is
freemac-update-helper's, in /usr/libexec; this module loads that same file
for its plain functions (reading the feed and the versions) and runs it
through pkexec to download. Dials > Software Update shows all this, and
Beacon looks once a day and says when a new version is ready. What was last
found is kept in ~/.local/state/freemac/freemac-update.json. Original freemac
code.
"""
import json
import os
import time
from importlib.machinery import SourceFileLoader

from gi.repository import Gio, GLib

HELPER = "/usr/libexec/freemac-update-helper"
_HERE = os.path.dirname(os.path.abspath(__file__))
_IN_REPO = os.path.join(_HERE, "..", "..", "build", "overlay", "usr", "libexec", "freemac-update-helper")
STATE = "/var/lib/freemac/update"
CACHE = os.path.join(GLib.get_user_state_dir(), "freemac", "freemac-update.json")
_helper = None


def helper():
    """The helper's own functions (version_key, newest, ...)."""
    global _helper
    if _helper is None:
        path = HELPER if os.path.exists(HELPER) else _IN_REPO
        _helper = SourceFileLoader("freemac_update_helper", path).load_module()
    return _helper


def available():
    """Whether this computer can update itself: freemac 1.134 or later,
    installed on a disk (the USB stick's live system can't)."""
    return os.path.exists(HELPER) and not live()


def live():
    return os.path.isdir("/run/live/medium")


def current():
    return helper().current_version()


def newer(version):
    return bool(version) and helper().version_key(version) > helper().version_key(current())


def _load(path):
    try:
        with open(path) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def cached():
    return _load(CACHE) or {}


def offer():
    """The newer version last found, as the helper's newest() gives it, or None."""
    found = cached().get("offer")
    return found if isinstance(found, dict) and newer(found.get("version")) else None


def check():
    """Ask the feed now (slow: run it on a thread). Returns the offer or
    None; raises the helper's Failed when the feed can't be reached."""
    try:
        found = helper().newest()
    except helper().Failed:
        _save({**cached(), "failed": time.time()})
        raise
    _save({**cached(), "checked": time.time(), "offer": found})
    return found


def _save(data):
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE + ".tmp", "w") as f:
            json.dump(data, f)
        os.replace(CACHE + ".tmp", CACHE)
    except OSError:
        pass


def pending():
    """The version downloaded and waiting for a restart, or None."""
    manifest = _load(os.path.join(STATE, "pending", "manifest.json"))
    return manifest.get("version") if manifest else None


def pending_whats_new():
    manifest = _load(os.path.join(STATE, "pending", "manifest.json")) or {}
    return manifest.get("whats_new") or []


def result():
    """What the last restart did: {"ok", "from", "to", "whats_new", "error",
    "undone", "time"}, or None."""
    return _load(os.path.join(STATE, "result.json"))


def previous():
    """The version Recovery's Undo Last Update would put back, or None."""
    record = _load(os.path.join(STATE, "previous", "manifest.json"))
    return record.get("version") if record else None


def size_text(size):
    if size >= 1e9:
        return f"{size / 1e9:.1f} GB"
    return f"{max(1, round(size / 1e6))} MB"


class Download:
    """Runs the helper's download through pkexec, calling
    progress(done, total), checking() and finished(ok, words) on the main loop."""

    def __init__(self, version, progress, checking, finished):
        self.finished = finished
        self.progress, self.checking = progress, checking
        self.error = None
        self.ready = False
        self.process = None
        try:
            self.process = Gio.Subprocess.new(["pkexec", HELPER, "download", version],
                                              Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE)
        except GLib.Error as error:
            message = error.message
            GLib.idle_add(lambda: finished(False, message) and False)
            return
        self.stream = Gio.DataInputStream.new(self.process.get_stdout_pipe())
        self.stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self._line)

    def _line(self, stream, task):
        try:
            line, _length = stream.read_line_finish_utf8(task)
        except GLib.Error:
            line = None
        if line is None:
            self.process.wait_async(None, self._ended)
            return
        words = line.split(" ", 1)
        if words[0] == "progress":
            try:
                done, total = (int(n) for n in words[1].split())
                self.progress(done, total)
            except (IndexError, ValueError):
                pass
        elif words[0] == "checking":
            self.checking()
        elif words[0] == "ready":
            self.ready = True
        elif words[0] == "error":
            self.error = words[1] if len(words) > 1 else None
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self._line)

    def _ended(self, process, task):
        try:
            process.wait_finish(task)
        except GLib.Error:
            pass
        if self.ready:
            self.finished(True, None)
        elif self.error:
            self.finished(False, self.error)
        elif process.get_if_exited() and process.get_exit_status() == 126:
            self.finished(False, None)     # the password was cancelled
        elif process.get_if_exited() and process.get_exit_status() == 127:
            self.finished(False, "Updating freemac needs an administrator’s name and password.")
        else:
            self.finished(False, "The update couldn’t be downloaded. Try again in a moment.")


def restart():
    try:
        Gio.Subprocess.new(["systemctl", "reboot"], Gio.SubprocessFlags.NONE)
        return True
    except GLib.Error:
        return False
