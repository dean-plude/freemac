# SPDX-License-Identifier: GPL-3.0-or-later
"""The screen reader, as on a Mac: press Command-F5 anywhere, or turn it on
in Dials > Accessibility, and the computer speaks what's on the screen: the
window and control you move to, the text under the cursor, what you type.

    freemac-screen-reader --toggle   Command-F5: turn it on or off
    freemac-screen-reader --login    Topline at login: start it if it was on
    freemac-screen-reader --settings its voice, verbosity and keys

The reader is Orca, the free screen reader that GTK and Qt apps, Firefox
and LibreOffice already speak to over the accessibility bus (AT-SPI). Its
voice is eSpeak NG, through speech-dispatcher. Whether it's on is kept in
shell.json as screen_reader, so it comes back at the next login.

Orca 46's keyboard handling (libatspi's) opens an X11 display, and stops
or hangs on a desktop with none, as freemac's is (Xwayland is off). So while
the reader is on, freemac gives Orca a private X11 display of its own: a
rootless Xwayland that shows no windows and goes when Orca does. Keys still
reach Orca through the apps (GTK's AT-SPI bridge), not through X11.
Original freemac code.
"""
import json
import os
import signal
import subprocess
import sys
import time

ORCA = "/usr/bin/orca"
XWAYLAND = "/usr/bin/Xwayland"
PREFS = os.path.expanduser("~/.config/freemac/shell.json")
KEY = "screen_reader"


def available():
    return os.access(ORCA, os.X_OK)


def _prefs():
    try:
        with open(PREFS) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    return data if isinstance(data, dict) else {}


def wanted():
    return bool(_prefs().get(KEY))


def _remember(on):
    data = _prefs()
    data[KEY] = bool(on)
    try:
        os.makedirs(os.path.dirname(PREFS), exist_ok=True)
        tmp = PREFS + ".reader-tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, PREFS)
    except OSError:
        pass


def _pids():
    """Orca processes of this user. Orca names its own process "orca"."""
    pids = []
    uid = os.getuid()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            if os.stat(f"/proc/{name}").st_uid != uid:
                continue
            with open(f"/proc/{name}/comm") as f:
                comm = f.read().strip()
        except OSError:
            continue
        if comm == "orca" and int(name) != os.getpid():
            pids.append(int(name))
    return pids


def running():
    return bool(_pids())


def _tell_apps(on):
    """Apps that look before they speak to a screen reader (GTK 4, some
    browsers) read this setting; Orca also says so on the accessibility bus."""
    subprocess.run(["gsettings", "set", "org.gnome.desktop.a11y.applications",
                    "screen-reader-enabled", "true" if on else "false"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def start():
    if not available():
        return False
    if running():
        return True
    _tell_apps(True)
    _launch("--replace")
    return True


def _launch(*args):
    subprocess.Popen([sys.executable, "-m", "freemac_shell.screen_reader", "--orca", *args],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def _private_display():
    """Start a rootless Xwayland for Orca alone; (process, ":N") or (None, None)."""
    read, write = os.pipe()
    try:
        xserver = subprocess.Popen([XWAYLAND, "-rootless", "-noreset", "-nolisten", "tcp",
                                    "-displayfd", str(write)],
                                   pass_fds=(write,), stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        os.close(read)
        os.close(write)
        return None, None
    os.close(write)
    number = b""
    with os.fdopen(read, "rb") as pipe:
        while not number.endswith(b"\n"):
            chunk = pipe.read(1)    # Xwayland writes the number once it is ready
            if not chunk:
                break
            number += chunk
    number = number.strip().decode() if number.strip().isdigit() else ""
    if not number:
        xserver.terminate()
        return None, None
    return xserver, ":" + number


def run_orca(args):
    """Run Orca with an X11 display (a private one when the desktop has
    none), and take the private one away when Orca ends."""
    env = dict(os.environ)
    xserver = None
    if not env.get("DISPLAY") and os.access(XWAYLAND, os.X_OK):
        xserver, display = _private_display()
        if display:
            env["DISPLAY"] = display
    try:
        return subprocess.call([ORCA, *args], env=env)
    finally:
        if xserver:
            xserver.terminate()
            try:
                xserver.wait(5)
            except subprocess.TimeoutExpired:
                xserver.kill()


def stop():
    _tell_apps(False)
    for pid in _pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass


def set_on(on):
    """Turn the reader on or off and remember it for the next login."""
    _remember(on)
    if on:
        return start()
    stop()
    return True


def toggle():
    on = not running()
    if on and not available():
        subprocess.Popen(["freemac-sound", "alert"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return False
    if not on:
        # The reader has already stopped by the time this is heard.
        from . import speak
        speak.say("Screen reader off")
    return set_on(on)


def at_login():
    if wanted():
        start()


def settings():
    """Orca's own window for its voice, how much it says and its keys."""
    if not available():
        return
    # Orca's settings window goes on as the reader once it closes, so the
    # running reader steps aside first: two readers at once fight over the
    # accessibility bus and leave the window you came from stuck.
    stop()
    for _ in range(50):
        if not running():
            break
        time.sleep(0.1)
    for pid in _pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    _remember(True)
    _tell_apps(True)
    _launch("--setup")


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    command = args[0] if args else "--toggle"
    if command == "--orca":
        return run_orca(args[1:])
    elif command == "--login":
        at_login()
    elif command == "--settings":
        settings()
    elif command == "--on":
        return 0 if set_on(True) else 1
    elif command == "--off":
        set_on(False)
    else:
        return 0 if toggle() else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
