# SPDX-License-Identifier: GPL-3.0-or-later
"""Lens: freemac's screenshot tool.

  freemac-lens --screen   the whole screen          (Print)
  freemac-lens --area     drag to pick an area      (Shift+Print)
  freemac-lens --window   the focused window        (Alt+Print)
  freemac-lens --record       start or stop recording the screen  (Ctrl+Print)
  freemac-lens --record-area  start or stop recording an area     (Ctrl+Shift+Print)
  freemac-lens            the Screenshot toolbar (⇧⌘5), or stop a recording

Pictures are saved as PNG on the Desktop (or where the toolbar's Options
say: Documents, Pictures or only the clipboard), copied to the clipboard
when wl-copy is installed, and announced through Beacon; clicking the
notification opens the picture. A small picture of each new screenshot first
sits in the corner for a few seconds (lens_thumb); a click opens it. Capturing uses grim, picking an area uses
slurp.

Recordings are MP4 videos, also on the Desktop, made by wf-recorder.
While one runs, Topline shows a red stop button (status.Recording), which
runs `freemac-lens --stop`. The running recorder's process id is kept in
$XDG_RUNTIME_DIR/freemac-recording.
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import style  # noqa: E402

# Both land on the Desktop, where they show as icons, ready to drag somewhere.
FOLDER = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP) or os.path.expanduser("~/Desktop")
VIDEOS = FOLDER
RECORDING = os.path.join(GLib.get_user_runtime_dir(), "freemac-recording")

# Where the toolbar's Options can save to: (pref, label, special folder).
SAVE_TO = (("desktop", "Desktop", GLib.UserDirectory.DIRECTORY_DESKTOP),
           ("documents", "Documents", GLib.UserDirectory.DIRECTORY_DOCUMENTS),
           ("pictures", "Pictures", GLib.UserDirectory.DIRECTORY_PICTURES),
           ("clipboard", "Clipboard", None))
TIMERS = ((0, "None"), (5, "5 Seconds"), (10, "10 Seconds"))


def save_to():
    """The pref name of where pictures go ("desktop" unless changed)."""
    chosen = style.prefs().get("lens_save", "desktop")
    return chosen if chosen in {k for k, _l, _d in SAVE_TO} else "desktop"


def save_folder(for_video=False):
    """(folder, its name) for new pictures; videos can't go on the clipboard,
    so they go on the Desktop then."""
    chosen = save_to()
    for key, label, special in SAVE_TO:
        if key == chosen and special is not None:
            folder = GLib.get_user_special_dir(special) or os.path.expanduser(f"~/{label}")
            return folder, label
    return FOLDER, "Desktop"


def thumbnail_on():
    return bool(style.prefs().get("lens_thumbnail", True))


def save_pref(**changes):
    prefs = style.prefs()
    prefs.update(changes)
    os.makedirs(os.path.dirname(style.PREFS), exist_ok=True)
    with open(style.PREFS + ".lens-tmp", "w") as f:
        json.dump(prefs, f, indent=2)
    os.replace(style.PREFS + ".lens-tmp", style.PREFS)


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
    folder, _name = save_folder(for_video=True)
    os.makedirs(folder, exist_ok=True)
    path = target_path(folder, kind="Screen Recording", ext="mp4")
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
            where = os.path.basename(os.path.dirname(path)) or "Desktop"
            beacon.send("Screen recording saved", f"{os.path.basename(path)} is in {where}."
                        if where != os.path.basename(FOLDER) else f"{os.path.basename(path)} is on the Desktop.",
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
    only_clipboard = save_to() == "clipboard" and shutil.which("wl-copy")
    folder = GLib.get_user_runtime_dir() if only_clipboard else save_folder()[0]
    os.makedirs(folder, exist_ok=True)
    path = target_path(folder)
    cmd = ["grim"] + (["-g", region] if region else []) + [path]
    if subprocess.run(cmd, capture_output=True).returncode != 0 or not os.path.exists(path):
        return None, "The screenshot couldn't be taken."
    if shutil.which("wl-copy"):
        # wl-copy keeps running in the background to serve the clipboard, so
        # don't wait on its output pipes.
        with open(path, "rb") as f:
            subprocess.run(["wl-copy", "--type", "image/png"], stdin=f,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    if only_clipboard:
        os.remove(path)
        return CLIPBOARD, None
    return path, None


CLIPBOARD = "clipboard"   # capture()'s answer when the picture went only to the clipboard


def announce(path, error):
    from . import beacon

    if path == CLIPBOARD:
        beacon.send("Screenshot copied", "Paste it into a message or a document.",
                    icon="edit-paste-symbolic", app="Lens")
    elif path:
        where = os.path.dirname(path)
        place = "on the Desktop" if where == FOLDER else f"in {os.path.basename(where)}"
        beacon.send("Screenshot saved", f"{os.path.basename(path)} is {place}"
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
    if not (path and path != CLIPBOARD and thumbnail_on() and lens_thumb.show(path)):
        announce(path, error)
    return path


MODES = (  # (mode, icon, tooltip, records)
    ("screen", "video-display-symbolic", "Capture Entire Screen", False),
    ("window", "window-new-symbolic", "Capture Selected Window", False),
    ("area", "edit-select-all-symbolic", "Capture Selected Portion", False),
    ("record", "camera-video-symbolic", "Record Entire Screen", True),
    ("record-area", "media-record-symbolic", "Record Selected Portion", True),
)

TOOLBAR_CSS = b"""
.lens-toolbar { background: alpha(@theme_bg_color, 0.92); border-radius: 12px;
                border: 1px solid alpha(@theme_fg_color, 0.15); padding: 6px 8px; }
.lens-toolbar button.lens-mode { min-width: 34px; min-height: 30px; padding: 4px 8px; border-radius: 7px; }
.lens-toolbar button.lens-mode:checked { background: alpha(@theme_fg_color, 0.16); }
.lens-toolbar .lens-split { background: alpha(@theme_fg_color, 0.2); min-width: 1px; margin: 4px 6px; }
.lens-count { font-size: 64px; font-weight: bold; color: white; background: rgba(0,0,0,0.55);
              border-radius: 22px; padding: 6px 34px; }
"""


class Toolbar(Gtk.ApplicationWindow):
    """The Screenshot toolbar, as on a Mac (⇧⌘5): pick what to capture or
    record, set Options (where to save, a timer, the thumbnail), then
    Capture. Escape closes it; Return captures."""

    def __init__(self, app):
        super().__init__(application=app, title="Screenshot")
        provider = Gtk.CssProvider()
        provider.load_from_data(TOOLBAR_CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        style.apply()
        if GtkLayerShell.is_supported():
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_namespace(self, "freemac-lens-toolbar")
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
            GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, 120)
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        visual = self.get_screen().get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)
        self.set_app_paintable(True)
        self.mode = style.prefs().get("lens_mode", "area")
        if self.mode not in {m for m, *_ in MODES}:
            self.mode = "area"
        bar = Gtk.Box(spacing=2)
        bar.get_style_context().add_class("lens-toolbar")
        close = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON)
        close.set_relief(Gtk.ReliefStyle.NONE)
        close.set_tooltip_text("Close (Esc)")
        close.connect("clicked", lambda *_: self.close())
        bar.pack_start(close, False, False, 0)
        self.buttons = {}
        group = None
        for n, (mode, icon, tip, _records) in enumerate(MODES):
            if n in (0, 3):
                split = Gtk.Box()
                split.get_style_context().add_class("lens-split")
                bar.pack_start(split, False, False, 0)
            button = Gtk.RadioButton.new_from_widget(group)
            group = group or button
            button.set_mode(False)       # drawn as a button, not a dot
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.get_style_context().add_class("lens-mode")
            button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR))
            button.set_tooltip_text(tip)
            button.set_active(mode == self.mode)
            button.connect("toggled", self._picked, mode)
            self.buttons[mode] = button
            bar.pack_start(button, False, False, 0)
        split = Gtk.Box()
        split.get_style_context().add_class("lens-split")
        bar.pack_start(split, False, False, 0)
        options = Gtk.MenuButton(label="Options")
        options.set_relief(Gtk.ReliefStyle.NONE)
        options.set_popup(self._options_menu())
        bar.pack_start(options, False, False, 0)
        self.go = Gtk.Button()
        self.go.get_style_context().add_class("suggested-action")
        self.go.connect("clicked", lambda *_: self.capture())
        bar.pack_start(self.go, False, False, 6)
        self.add(bar)
        self._label_go()
        self.connect("key-press-event", self._key)

    def _options_menu(self):
        menu = Gtk.Menu()

        def heading(text):
            item = Gtk.MenuItem(label=text, sensitive=False)
            menu.append(item)

        def choices(items, current, on_pick):
            group = []
            for value, label in items:
                item = Gtk.RadioMenuItem.new_with_label(group, label)
                group = item.get_group()
                item.set_active(value == current)
                item.connect("toggled", lambda i, v=value: i.get_active() and on_pick(v))
                menu.append(item)

        heading("Save to")
        choices([(k, label) for k, label, _d in SAVE_TO], save_to(), lambda v: save_pref(lens_save=v))
        menu.append(Gtk.SeparatorMenuItem())
        heading("Timer")
        choices(TIMERS, int(style.prefs().get("lens_timer", 0) or 0), lambda v: save_pref(lens_timer=v))
        menu.append(Gtk.SeparatorMenuItem())
        heading("Options")
        thumb = Gtk.CheckMenuItem(label="Show Floating Thumbnail")
        thumb.set_active(thumbnail_on())
        thumb.connect("toggled", lambda i: save_pref(lens_thumbnail=i.get_active()))
        menu.append(thumb)
        menu.show_all()
        return menu

    def _picked(self, button, mode):
        if button.get_active():
            self.mode = mode
            save_pref(lens_mode=mode)
            self._label_go()

    def _label_go(self):
        records = dict((m, r) for m, _i, _t, r in MODES)[self.mode]
        self.go.set_label("Record" if records else "Capture")

    def _key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()
            return True
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.capture()
            return True
        return False

    def capture(self):
        delay = int(style.prefs().get("lens_timer", 0) or 0)
        self.hide()
        mode = self.mode
        # Give the compositor a moment to take the toolbar off the screen.
        if delay:
            Countdown(self.get_application(), delay, lambda: self._run(mode))
        else:
            GLib.timeout_add(400, self._run, mode)

    def _run(self, mode):
        from . import lens_thumb

        app = self.get_application()
        if mode in ("record", "record-area"):
            toggle_recording(mode == "record-area")
        else:
            path, error = capture(mode)
            if not (path and path != CLIPBOARD and thumbnail_on() and lens_thumb.show(path)):
                announce(path, error)
        app.quit()
        return False


class Countdown(Gtk.Window):
    """The timer's big number in the middle of the screen."""

    def __init__(self, app, seconds, then):
        super().__init__(application=app)
        self.left, self.then = seconds, then
        if GtkLayerShell.is_supported():
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_namespace(self, "freemac-lens-countdown")
        visual = self.get_screen().get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)
        self.set_app_paintable(True)
        self.label = Gtk.Label(label=str(seconds))
        self.label.get_style_context().add_class("lens-count")
        self.add(self.label)
        self.show_all()
        GLib.timeout_add(1000, self._tick)

    def _tick(self):
        self.left -= 1
        if self.left > 0:
            self.label.set_text(str(self.left))
            return True
        self.hide()
        GLib.timeout_add(400, lambda: self.then() and False)
        return False


def main():
    args = sys.argv[1:]
    if "--stop" in args:
        sys.exit(0 if recording() and toggle_recording() else 1)
    if "--record" in args or "--record-area" in args:
        sys.exit(0 if toggle_recording("--record-area" in args) else 1)
    for flag in ("screen", "area", "window"):
        if f"--{flag}" in args:
            sys.exit(0 if shoot(flag) else 1)
    if recording():
        # ⇧⌘5 while recording stops it, as the menu bar's stop button does.
        sys.exit(0 if toggle_recording() else 1)
    app = Gtk.Application(application_id="org.freemac.Lens")
    app.connect("activate", lambda a: (a.get_windows() or [Toolbar(a)])[0].show_all())
    app.run([sys.argv[0]])


if __name__ == "__main__":
    main()
