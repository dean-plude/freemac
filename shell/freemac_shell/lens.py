# SPDX-License-Identifier: GPL-3.0-or-later
"""Lens: freemac's screenshot tool.

  freemac-lens --screen   the whole screen          (Print)
  freemac-lens --area     drag to pick an area      (Shift+Print)
  freemac-lens --window   the focused window        (Alt+Print)
  freemac-lens            a small window to choose, with an optional delay

Pictures are saved as PNG in ~/Pictures/Screenshots, copied to the clipboard
when wl-copy is installed, and announced through Beacon; clicking the
notification opens the picture. Capturing uses grim, picking an area uses
slurp.
"""
import os
import shutil
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

FOLDER = os.path.join(GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
                      or os.path.expanduser("~/Pictures"), "Screenshots")


def target_path(folder=FOLDER, now=None):
    """A new, unused file name like 'Screenshot 2026-11-19 at 14.05.09.png'."""
    stamp = time.strftime("%Y-%m-%d at %H.%M.%S", time.localtime(now or time.time()))
    path = os.path.join(folder, f"Screenshot {stamp}.png")
    n = 2
    while os.path.exists(path):
        path = os.path.join(folder, f"Screenshot {stamp} ({n}).png")
        n += 1
    return path


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
        picked = subprocess.run(["slurp", "-d", "-b", "1b1e4a40", "-c", "4b5fc4ff", "-w", "2"],
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
        beacon.send("Screenshot saved", f"{os.path.basename(path)} is in Pictures › Screenshots"
                    + (" and on the clipboard." if shutil.which("wl-copy") else "."),
                    icon=path, app="Lens", open_path=path)
    elif error:
        beacon.send("No screenshot", error, icon="dialog-warning-symbolic", app="Lens")


def shoot(mode, delay=0):
    if delay:
        time.sleep(delay)
    path, error = capture(mode)
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
        hint = Gtk.Label(label="Print takes the whole screen, Shift+Print an area, Alt+Print the window.",
                         wrap=True, xalign=0)
        hint.get_style_context().add_class("dim-label")
        box.pack_start(hint, False, False, 0)

    def take(self, mode):
        delay = int(self.delay.get_active_id() or 0)
        self.hide()
        # Give the compositor a moment to remove this window from the screen.
        GLib.timeout_add(400 + delay * 1000, self._run, mode)

    def _run(self, mode):
        path, error = capture(mode)
        announce(path, error)
        self.get_application().quit()
        return False

    def open_folder(self, *_args):
        os.makedirs(FOLDER, exist_ok=True)
        subprocess.Popen(["xdg-open", FOLDER], start_new_session=True)


def main():
    args = sys.argv[1:]
    for flag in ("screen", "area", "window"):
        if f"--{flag}" in args:
            sys.exit(0 if shoot(flag) else 1)
    app = Gtk.Application(application_id="org.freemac.Lens")
    app.connect("activate", lambda a: (a.get_windows() or [Picker(a)])[0].show_all())
    app.run([sys.argv[0]])


if __name__ == "__main__":
    main()
