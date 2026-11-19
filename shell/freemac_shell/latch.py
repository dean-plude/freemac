# SPDX-License-Identifier: GPL-3.0-or-later
"""Latch: freemac's lock screen.

    freemac-lock            lock the screen now (Super+L, Topline > Lock Screen)
    freemac-lock --watch    started at login: locks after the idle time set in
                            Dials > Power, and before the computer sleeps

The lock itself is gtklock (Wayland session locking with PAM), dressed with
freemac's own style: the current wallpaper, a large clock and a password
field. Idle detection is swayidle. Settings live in ~/.config/freemac/shell.json
as "lock_after" (minutes, 0 for never) and "lock_on_sleep".
"""
import os
import shutil
import signal
import subprocess
import sys

from gi.repository import GLib

from . import backdrop, style

DEFAULT_LOCK_AFTER = 5   # minutes


CSS = """
window {
    background-color: %(bg)s;
    background-size: cover;
    background-position: center;
}
#window-box {
    background-color: %(veil)s;
    border-radius: 22px;
    padding: 28px 36px;
    margin: 40px;
}
#clock-label {
    color: %(fg)s;
    font-family: "Inter", sans-serif;
    font-weight: 300;
    font-size: 72pt;
    font-feature-settings: "tnum";
}
window.focused:not(.hidden) #clock-label { font-size: 44pt; }
#input-label { color: %(dim)s; }
#input-field {
    min-width: 260px;
    min-height: 36px;
    border-radius: 18px;
    padding: 0 14px;
    background-color: %(field)s;
    color: %(fg)s;
    border: 1px solid %(edge)s;
    box-shadow: none;
}
#unlock-button {
    border-radius: 18px;
    min-height: 36px;
    padding: 0 16px;
    background-image: none;
    background-color: %(accent)s;
    color: #ffffff;
    border: none;
    box-shadow: none;
}
#error-label { color: %(error)s; font-weight: bold; }
#warning-label { color: %(warning)s; }
"""


def settings():
    prefs = style.prefs()
    try:
        after = int(prefs.get("lock_after", DEFAULT_LOCK_AFTER))
    except (TypeError, ValueError):
        after = DEFAULT_LOCK_AFTER
    return max(0, after), bool(prefs.get("lock_on_sleep", True))


def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or GLib.get_user_cache_dir()
    path = os.path.join(base, "freemac-latch")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def write_style():
    dark = style.is_dark()
    colours = {
        "bg": "#1c1e34",
        "veil": "rgba(18, 20, 38, 0.55)" if dark else "rgba(250, 249, 255, 0.62)",
        "fg": "#f4f3fb" if dark else "#1d1f33",
        "dim": "rgba(244, 243, 251, 0.7)" if dark else "rgba(29, 31, 51, 0.65)",
        "field": "rgba(255, 255, 255, 0.12)" if dark else "rgba(255, 255, 255, 0.85)",
        "edge": "rgba(255, 255, 255, 0.18)" if dark else "rgba(29, 31, 51, 0.15)",
        "accent": "#5b6cf0",
        "error": "#ffb4a8" if dark else "#a8231a",
        "warning": "#ffd58a" if dark else "#8a5a00",
    }
    path = os.path.join(runtime_dir(), "style.css")
    with open(path, "w") as f:
        f.write(CSS % colours)
    return path


def wallpaper():
    image = backdrop.read_settings().get("image") or backdrop.DEFAULT_IMAGE
    image = os.path.expanduser(image)
    return image if os.path.isfile(image) else None


def locked():
    return subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "gtklock"],
                          stdout=subprocess.DEVNULL).returncode == 0


def lock_command():
    clock = "%H:%M" if style.prefs().get("clock") == "24" else "%-I:%M"
    command = ["gtklock", "--daemonize", "--style", write_style(), "--time-format", clock,
               "--idle-hide", "--idle-timeout", "20"]
    if style.is_dark():
        command += ["--gtk-theme", "Adwaita-dark"]
    image = wallpaper()
    if image:
        command += ["--background", image]
    return command


def lock():
    if not shutil.which("gtklock"):
        print("freemac-lock: the lock screen (gtklock) isn't installed", file=sys.stderr)
        return 1
    if locked():
        return 0
    # --daemonize returns once the screen is locked, so a caller that waits
    # (swayidle before sleep) knows the lock is up before the system sleeps.
    return subprocess.run(lock_command()).returncode


def idle_command():
    after, on_sleep = settings()
    me = [shutil.which("freemac-lock") or sys.executable, *([] if shutil.which("freemac-lock") else ["-m", "freemac_shell.latch"])]
    lock_now = " ".join(GLib.shell_quote(part) for part in me)
    command = ["swayidle", "-w"]
    if after > 0:
        command += ["timeout", str(after * 60), lock_now]
    if on_sleep:
        command += ["before-sleep", lock_now, "lock", lock_now]
    return command if len(command) > 2 else None


class Watcher:
    """Runs swayidle with the current settings and restarts it when Dials
    changes them."""

    def __init__(self):
        self.child = None
        self.current = None
        self.monitor = style.watch_prefs(self.reload)
        self.reload()

    def reload(self):
        command = idle_command()
        if command == self.current and self.child and self.child.poll() is None:
            return
        self.stop()
        self.current = command
        if command:
            self.child = subprocess.Popen(command)

    def stop(self):
        if self.child and self.child.poll() is None:
            self.child.terminate()
            try:
                self.child.wait(3)
            except subprocess.TimeoutExpired:
                self.child.kill()
        self.child = None

    def check(self):
        # swayidle exits if the compositor goes away; follow it.
        if self.child and self.child.poll() is not None and self.current:
            self.child = subprocess.Popen(self.current)
        return True


def watch():
    if not shutil.which("swayidle"):
        print("freemac-lock: idle locking needs swayidle", file=sys.stderr)
        return 1
    loop = GLib.MainLoop()
    watcher = Watcher()
    GLib.timeout_add_seconds(10, watcher.check)
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, loop.quit)
    loop.run()
    watcher.stop()
    return 0


def main():
    args = sys.argv[1:]
    if args in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    if "--watch" in args:
        return watch()
    return lock()


if __name__ == "__main__":
    sys.exit(main())

