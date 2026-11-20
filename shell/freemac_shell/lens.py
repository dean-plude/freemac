# SPDX-License-Identifier: GPL-3.0-or-later
"""Lens: freemac's screenshot tool.

  freemac-lens --screen   the whole screen          (Print)
  freemac-lens --area     drag to pick an area      (Shift+Print)
  freemac-lens --window   the focused window        (Alt+Print)
  freemac-lens --record       start or stop recording the screen  (Ctrl+Print)
  freemac-lens --record-area  start or stop recording an area     (Ctrl+Shift+Print)
  freemac-lens            a small window to choose, with an optional delay

Pictures are saved as PNG on the Desktop, copied to the clipboard
when wl-copy is installed, and announced through Beacon; clicking the
notification opens the picture. A small picture of each new screenshot first
sits in the corner for a few seconds (lens_thumb); a click opens it. Capturing uses grim, picking an area uses
slurp.

Recordings are MP4 videos, also on the Desktop, made by wf-recorder.
While one runs, Topline shows a red stop button (status.Recording), which
runs `freemac-lens --stop`. The running recorder's process id is kept in
$XDG_RUNTIME_DIR/freemac-recording.
"""
import os
import shutil
import signal
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

# Both land on the Desktop, where they show as icons, ready to drag somewhere.
FOLDER = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP) or os.path.expanduser("~/Desktop")
VIDEOS = FOLDER
RECORDING = os.path.join(GLib.get_user_runtime_dir(), "freemac-recording")


def target_path(folder=FOLDER, now=None, kind="Screenshot", ext="png"):
    """A new, unused file name like 'Screenshot 2026-11-19 at 14.05.09.png'."""
    stamp = time.strftime("%Y-%m-%d at %H.%M.%S", time.localtime(now or time.time()))
    path = os.path.join(folder, f"{kind} {stamp}.{ext}")
    n = 2
    while os.path.exists(path):
        path = os.path.join(folder, f"{kind} {stamp} ({n}).{ext}")
        n += 1
    return path


# -- screen recording ------------------------------------------------------------
def recording():
    """(pid, path) of the recording in progress, or None."""
    try:
        with open(RECORDING) as f:
            pid_text, path = f.read().split("\n", 1)
        pid = int(pid_text)
        os.kill(pid, 0)
        return pid, path.strip()
    except (OSError, ValueError):
        return None


def start_recording(area=False):
    if not shutil.which("wf-recorder"):
        return None, "The screen recorder (wf-recorder) isn't installed."
    cmd = ["wf-recorder", "-y"]
    if area:
        if not shutil.which("slurp"):
            return None, "The area picker (slurp) isn't installed."
        picked = subprocess.run(["slurp", "-d", "-b", "00000040", "-c", "e5484dff", "-w", "2"],
                                capture_output=True, text=True)
        if picked.returncode != 0 or not picked.stdout.strip():
            return None, None
        cmd += ["-g", picked.stdout.strip()]
    os.makedirs(VIDEOS, exist_ok=True)
    path = target_path(VIDEOS, kind="Screen Recording", ext="mp4")
    log = open(os.path.join(GLib.get_user_runtime_dir(), "freemac-recording.log"), "w")
    proc = subprocess.Popen(cmd + ["-f", path], stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                            start_new_session=True)
    time.sleep(0.6)
    if proc.poll() is not None:
        return None, "The recording couldn't start."
    with open(RECORDING, "w") as f:
        f.write(f"{proc.pid}\n{path}")
    return path, None


def stop_recording():
    """Stop the recording in progress; returns its path, or None."""
    running = recording()
    try:
        os.remove(RECORDING)
    except OSError:
        pass
    if not running:
        return None
    pid, path = running
    os.kill(pid, signal.SIGINT)    # wf-recorder finishes the file on SIGINT
    for _ in range(100):
        time.sleep(0.1)
        try:
            os.kill(pid, 0)
        except OSError:
            break
    return path if os.path.exists(path) else None


def toggle_recording(area=False):
    from . import beacon

    if recording():
        path = stop_recording()
        if path:
            beacon.send("Screen recording saved", f"{os.path.basename(path)} is on the Desktop.",
                        icon="video-x-generic", app="Lens", open_path=path)
        return bool(path)
    path, error = start_recording(area)
    if error:
        beacon.send("No recording", error, icon="dialog-warning-symbolic", app="Lens")
    return bool(path)


def window_geometry():
    """'x,y wxh' for the focused window, in layout coordinates, or None."""
    try:
        from .wfipc import Wayfire

        wf = Wayfire()
        view = wf.focused()
        if not view:
            return None
        g = view.get("geometry") or view.get("bbox")
        x, y = g["x"], g["y"]
        # Wayfire reports view positions relative to their output.
        out_id = view.get("output-id", view.get("output"))
        if isinstance(out_id, int):
            try:
                outputs = wf.req.call("window-rules/list-outputs")
                for out in outputs if isinstance(outputs, list) else []:
                    if out.get("id") == out_id:
                        x += out["geometry"]["x"]
                        y += out["geometry"]["y"]
            except (OSError, ValueError, KeyError, TypeError):
                pass
        return f"{x},{y} {g['width']}x{g['height']}"
    except (OSError, ValueError, KeyError, TypeError, ConnectionError):
        return None


def capture(mode):
    """Take the screenshot; returns the saved path or None (cancelled/failed)."""
    if not shutil.which("grim"):
        return None, "The screenshot tool (grim) isn't installed."
    region = None
    if mode == "area":
        if not shutil.which("slurp"):
            return None, "The area picker (slurp) isn't installed."
        picked = subprocess.run(["slurp", "-d", "-b", "00000040", "-c", "2f7bf5ff", "-w", "2"],
                                capture_output=True, text=True)
        if picked.returncode != 0 or not picked.stdout.strip():
            return None, None  # cancelled with Escape
        region = picked.stdout.strip()
    elif mode == "window":
        region = window_geometry()
        if not region:
            return None, "There's no window to capture."
    os.makedirs(FOLDER, exist_ok=True)
    path = target_path()
    cmd = ["grim"] + (["-g", region] if region else []) + [path]
    if subprocess.run(cmd, capture_output=True).returncode != 0 or not os.path.exists(path):
        return None, "The screenshot couldn't be taken."
    if shutil.which("wl-copy"):
        # wl-copy keeps running in the background to serve the clipboard, so
        # don't wait on its output pipes.
        with open(path, "rb") as f:
            subprocess.run(["wl-copy", "--type", "image/png"], stdin=f,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    return path, None


def announce(path, error):
    from . import beacon

    if path:
        beacon.send("Screenshot saved", f"{os.path.basename(path)} is on the Desktop"
                    + (" and on the clipboard." if shutil.which("wl-copy") else "."),
                    icon=path, app="Lens", open_path=path)
    elif error:
        beacon.send("No screenshot", error, icon="dialog-warning-symbolic", app="Lens")


def shoot(mode, delay=0):
    """Take it; a small picture of it then sits in the corner for a moment, as
    the sign that it worked (a notification says so if that can't show)."""
    from . import lens_thumb

    if delay:
        time.sleep(delay)
    path, error = capture(mode)
    if not (path and lens_thumb.show(path)):
        announce(path, error)
    return path


class Picker(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Lens")
        self.set_resizable(False)
        self.set_border_width(16)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.add(box)
        row = Gtk.Box(spacing=10, homogeneous=True)
        for label, icon, mode in (("Whole Screen", "video-display-symbolic", "screen"),
                                  ("Area", "edit-select-all-symbolic", "area"),
                                  ("Window", "window-new-symbolic", "window")):
            button = Gtk.Button()
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin=8)
            image = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.DND)
            image.set_pixel_size(32)
            inner.pack_start(image, False, False, 0)
            inner.pack_start(Gtk.Label(label=label), False, False, 0)
            button.add(inner)
            button.connect("clicked", lambda _b, m=mode: self.take(m))
            row.pack_start(button, True, True, 0)
        box.pack_start(row, False, False, 0)
        record_row = Gtk.Box(spacing=10, homogeneous=True)
        for label, area in (("Record Screen", False), ("Record Area", True)):
            button = Gtk.Button(label=label, image=Gtk.Image.new_from_icon_name(
                "media-record-symbolic", Gtk.IconSize.BUTTON), always_show_image=True)
            button.connect("clicked", lambda _b, a=area: self.record(a))
            record_row.pack_start(button, True, True, 0)
        box.pack_start(record_row, False, False, 0)
        delay_row = Gtk.Box(spacing=8)
        delay_row.pack_start(Gtk.Label(label="Delay"), False, False, 0)
        self.delay = Gtk.ComboBoxText()
        for seconds in ("0", "3", "5", "10"):
            self.delay.append(seconds, "None" if seconds == "0" else f"{seconds} seconds")
        self.delay.set_active_id("0")
        delay_row.pack_start(self.delay, False, False, 0)
        folder = Gtk.Button(label="Open Folder")
        folder.connect("clicked", self.open_folder)
        delay_row.pack_end(folder, False, False, 0)
        box.pack_start(delay_row, False, False, 0)
        hint = Gtk.Label(label="\u21e7\u23183 takes the whole screen, \u21e7\u23184 an area, "
                               "\u21e7\u23185 records an area. The Print key works too.",
                         wrap=True, xalign=0)
        hint.get_style_context().add_class("dim-label")
        box.pack_start(hint, False, False, 0)

    def take(self, mode):
        delay = int(self.delay.get_active_id() or 0)
        self.hide()
        # Give the compositor a moment to remove this window from the screen.
        GLib.timeout_add(400 + delay * 1000, self._run, mode)

    def record(self, area):
        delay = int(self.delay.get_active_id() or 0)
        self.hide()
        GLib.timeout_add(400 + delay * 1000, self._record, area)

    def _record(self, area):
        toggle_recording(area)
        self.get_application().quit()
        return False

    def _run(self, mode):
        from . import lens_thumb

        path, error = capture(mode)
        if not (path and lens_thumb.show(path)):
            announce(path, error)
        self.get_application().quit()
        return False

    def open_folder(self, *_args):
        os.makedirs(FOLDER, exist_ok=True)
        try:
            Gio.AppInfo.launch_default_for_uri(GLib.filename_to_uri(FOLDER, None), None)
        except GLib.Error:
            subprocess.Popen(["xdg-open", FOLDER], start_new_session=True)


def main():
    args = sys.argv[1:]
    if "--stop" in args:
        sys.exit(0 if recording() and toggle_recording() else 1)
    if "--record" in args or "--record-area" in args:
        sys.exit(0 if toggle_recording("--record-area" in args) else 1)
    for flag in ("screen", "area", "window"):
        if f"--{flag}" in args:
            sys.exit(0 if shoot(flag) else 1)
    app = Gtk.Application(application_id="org.freemac.Lens")
    app.connect("activate", lambda a: (a.get_windows() or [Picker(a)])[0].show_all())
    app.run([sys.argv[0]])


if __name__ == "__main__":
    main()
