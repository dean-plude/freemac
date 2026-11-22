# SPDX-License-Identifier: GPL-3.0-or-later
"""Latch: freemac's lock screen.

    freemac-lock            lock the screen now (Ctrl+Command+Q, Topline > Lock Screen)
    freemac-lock --watch    started at login: locks after the idle time set in
                            Dials > Power, and before the computer sleeps;
                            starts the screen saver (Dials > Screen Saver),
                            and keeps the computer awake for those who ask
                            (awake.py: videos playing, caffeinate)
    freemac-lock --idle     what the idle timer runs: while a screen saver
                            shows, it marks the lock for when it ends instead

The lock itself is gtklock (Wayland session locking with PAM), dressed to
look like the login screen: the blurred wallpaper, the date and a large
clock, the person's picture and name, and a round password field. Idle detection is swayidle. Settings live in ~/.config/freemac/shell.json
as "lock_after" (minutes, 0 for never) and "lock_on_sleep".
"""
import os
import shutil
import signal
import subprocess
import sys
import time

from gi.repository import GLib

from . import backdrop, saver, style

DEFAULT_LOCK_AFTER = 5   # minutes


# The lock screen looks like Gangway, the login screen: the wallpaper softly
# blurred, the date and a large clock at the top, the person's picture and
# name in the lower middle over a round password field. freemac-latch.so (a
# gtklock module, strata/latch) moves gtklock's widgets into that layout;
# without it the same colours still apply to gtklock's own layout.
CSS = """
window {
    background-color: #1c1e4a;
    background-size: cover;
    background-position: center;
}
#window-box { background: none; padding: 0; }
label { color: #ffffff; text-shadow: 0 1px 3px rgba(0, 0, 0, 0.35); }
#clock-label { font-size: 84px; font-weight: 600; font-feature-settings: "tnum"; }
#date-label { font-size: 21px; font-weight: 500; color: rgba(255, 255, 255, 0.92); }
#name-label { font-size: 17px; font-weight: 600; }
#placeholder-label { color: rgba(255, 255, 255, 0.62); text-shadow: none; font-size: 14px; }
#input-label { color: rgba(255, 255, 255, 0.80); }
#latch-field { background-color: rgba(255, 255, 255, 0.22); border-radius: 18px; padding: 0 4px 0 14px; }
#latch-field #input-field { background: none; border: none; box-shadow: none; min-width: 0;
                            border-radius: 0; padding: 0; }
#input-field {
    min-height: 34px;
    border-radius: 18px;
    padding: 0 14px;
    background-color: rgba(255, 255, 255, 0.22);
    color: #ffffff;
    caret-color: #ffffff;
    font-size: 14px;
    border: none;
    box-shadow: none;
}
#unlock-button {
    min-width: 26px;
    min-height: 26px;
    padding: 0;
    border-radius: 13px;
    border: none;
    box-shadow: none;
    background-image: none;
    background-color: rgba(255, 255, 255, 0.28);
    color: #ffffff;
}
#unlock-button:hover { background-color: rgba(255, 255, 255, 0.40); }
#unlock-button:disabled { background-color: rgba(255, 255, 255, 0.12); }
#error-label { color: #ffd8d4; font-size: 13px; }
#warning-label { color: rgba(255, 255, 255, 0.80); font-size: 13px; }
"""

MODULE = "/usr/lib/gtklock/freemac-latch.so"


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
    path = os.path.join(runtime_dir(), "style.css")
    with open(path, "w") as f:
        f.write(CSS)
    return path


def wallpaper():
    image = backdrop.read_settings().get("image") or backdrop.DEFAULT_IMAGE
    image = os.path.expanduser(image)
    return image if os.path.isfile(image) else None


def soft_wallpaper():
    """The wallpaper blurred and dimmed a little, as behind the login screen.
    Kept in the runtime folder and made again when the wallpaper changes."""
    image = wallpaper()
    if not image:
        return None
    try:
        import gi
        gi.require_version("GdkPixbuf", "2.0")
        from gi.repository import GdkPixbuf
        stamp = "%s:%d" % (image, int(os.path.getmtime(image)))
        out = os.path.join(runtime_dir(), "background.png")
        mark = out + ".source"
        try:
            with open(mark) as f:
                if f.read() == stamp and os.path.isfile(out):
                    return out
        except OSError:
            pass
        picture = GdkPixbuf.Pixbuf.new_from_file(image)
        soft = style.blurred(picture, 1600, 1000)
        # The login screen lays 12% black over it.
        dim = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, soft.get_width(), soft.get_height())
        dim.fill(0x000000ff)
        dim.composite(soft, 0, 0, soft.get_width(), soft.get_height(), 0, 0, 1, 1,
                      GdkPixbuf.InterpType.NEAREST, 31)
        soft.savev(out, "png", [], [])
        with open(mark, "w") as f:
            f.write(stamp)
        return out
    except Exception:  # noqa: BLE001 - a plain wallpaper is fine too
        return image


def module_fits():
    """freemac-latch.so is built for gtklock 2.1's layout."""
    if not os.path.isfile(MODULE):
        return False
    try:
        out = subprocess.run(["gtklock", "--version"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return False
    words = (out.stdout + out.stderr).split()   # "gtklock v2.1.0"
    return bool(words) and words[-1].lstrip("v").startswith("2.1.")


def locked():
    return subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "gtklock"],
                          stdout=subprocess.DEVNULL).returncode == 0


def lock_command():
    clock = "%H:%M" if style.prefs().get("clock") == "24" else "%-I:%M"
    command = ["gtklock", "--daemonize", "--style", write_style(), "--time-format", clock,
               "--idle-hide", "--idle-timeout", "20"]
    if style.is_dark():
        command += ["--gtk-theme", "freemac-dark"]
    image = soft_wallpaper()
    if image:
        command += ["--background", image]
    if module_fits():
        command += ["--modules", MODULE]
    return command


def lock():
    if not shutil.which("gtklock"):
        print("freemac-lock: the lock screen (gtklock) isn't installed", file=sys.stderr)
        return 1
    if locked():
        return 0
    # --daemonize returns once the screen is locked, so a caller that waits
    # (swayidle before sleep) knows the lock is up before the system sleeps.
    code = subprocess.run(lock_command()).returncode
    # A screen saver under the lock would still be there after unlocking.
    saver.stop()
    return code


def idle_lock():
    """The idle time to lock has come. While a screen saver shows, leave it
    showing and lock when it ends, as a Mac asks for the password when you
    wake it, so the desktop doesn't show in between."""
    _name, saver_after = saver.settings()
    lock_after, _on_sleep = settings()
    if 0 < saver_after <= lock_after:
        # Both times may come together; give the screen saver a moment to start.
        for _ in range(30):
            if saver.running_pid():
                break
            time.sleep(0.1)
    if saver.running_pid():
        with open(saver.LOCK_MARK, "w"):
            pass
        return 0
    return lock()


def idle_command():
    after, on_sleep = settings()
    me = [shutil.which("freemac-lock") or sys.executable, *([] if shutil.which("freemac-lock") else ["-m", "freemac_shell.latch"])]
    lock_now = " ".join(GLib.shell_quote(part) for part in me)
    command = ["swayidle", "-w"]
    _name, saver_after = saver.settings()
    if saver_after > 0:
        start = shutil.which("freemac-screensaver")
        start = GLib.shell_quote(start) if start else GLib.shell_quote(sys.executable) + " -m freemac_shell.saver"
        # swayidle -w waits for each command, so the screen saver, which runs
        # until it's woken, goes in the background. It ends itself when
        # touched; a resume command would end it as it appears, since the
        # compositor counts a new surface taking the keyboard as activity.
        command += ["timeout", str(saver_after * 60), start + " >/dev/null 2>&1 &"]
    if after > 0:
        command += ["timeout", str(after * 60), lock_now + " --idle"]
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
    # What keeps the computer awake (a video playing, caffeinate) is asked
    # for here, beside the idle timers it holds back.
    from . import awake
    keep_awake = awake.Service()
    keep_awake.start()
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, loop.quit)
    loop.run()
    keep_awake.stop()
    watcher.stop()
    return 0


def main():
    args = sys.argv[1:]
    if args in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    if "--watch" in args:
        return watch()
    if "--idle" in args:
        return idle_lock()
    return lock()


if __name__ == "__main__":
    sys.exit(main())

