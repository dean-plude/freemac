# SPDX-License-Identifier: GPL-3.0-or-later
"""Services, as on a Mac: small jobs one app does for what's selected in another.

Select some words in any app and open the app's menu in the menu bar
(Topline): Services lists what can be done with them, such as Make New
Sticky Note, Look Up in Words or Search With Seek. Right-click files in
Drawer for the ones that work on files, such as New Terminal at Folder.
Each can have a keyboard shortcut (Dials > Keyboard > Services), and
Make New Sticky Note has ⇧⌘Y, as on a Mac.

    freemac-service ID              do it with the selected words
    freemac-service ID PATH...      do it with these files

The selected words come from Wayland's primary selection, which every app
keeps up to date as you select. The apps that do the work are asked over
the session bus, through the app actions every GApplication publishes
(org.gtk.Actions), and started first when they aren't running.
Which services show is kept in ~/.config/freemac/shell.json
("services_off"). Original freemac code.
"""
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import time

PREFS = os.path.expanduser("~/.config/freemac/shell.json")
SHELL_INI = os.path.expanduser("~/.config/wf-shell.ini")
LONGEST = 20000          # characters taken from the selection
URL = re.compile(r"^(https?://|www\.)[^\s<>\"]+$", re.I)


def _words(text, most):
    return 0 < len(text.split()) <= most


def _url(text):
    return bool(URL.match(text))


def _path(text):
    path = os.path.expanduser(text)
    return os.path.isabs(path) and len(text) < 4096 and os.path.exists(path)


def _folder(paths):
    return len(paths) == 1 and os.path.isdir(paths[0])


def _picture(paths):
    return len(paths) == 1 and os.path.isfile(paths[0]) and \
        (mimetypes.guess_type(paths[0])[0] or "").startswith("image/")


# (id, title, kind, does it suit what's selected, shortcut as freemac ships it)
SERVICES = (
    ("sticky", "Make New Sticky Note", "text", lambda t: bool(t.strip()), "<super> <shift> KEY_Y"),
    ("jot", "New Jot Note With Selection", "text", lambda t: bool(t.strip()), ""),
    ("words", "Look Up in Words", "text", lambda t: _words(t, 4) and len(t) <= 80, ""),
    ("seek", "Search With Seek", "text", lambda t: _words(t, 12) and len(t) <= 200, ""),
    ("speak", "Speak Text", "text", lambda t: bool(t.strip()), ""),
    ("url", "Open URL", "text", lambda t: _url(t.strip()), ""),
    ("reveal", "Show in Drawer", "text", lambda t: _path(t.strip()), ""),
    ("terminal", "New Terminal at Folder", "files", _folder, ""),
    ("wallpaper", "Set Desktop Picture", "files", _picture, ""),
)
BY_ID = {s[0]: s for s in SERVICES}


def prefs():
    try:
        with open(PREFS) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    return data if isinstance(data, dict) else {}


def turned_off():
    off = prefs().get("services_off")
    return set(off) if isinstance(off, list) else set()


def set_on(service_id, on):
    data = prefs()
    off = turned_off()
    if on:
        off.discard(service_id)
    else:
        off.add(service_id)
    data["services_off"] = sorted(off)
    os.makedirs(os.path.dirname(PREFS), exist_ok=True)
    tmp = PREFS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, PREFS)


def shown(kind):
    """The services of this kind ("text" or "files") that are turned on."""
    off = turned_off()
    return [s for s in SERVICES if s[2] == kind and s[0] not in off]


def suits(service_id, what):
    service = BY_ID.get(service_id)
    if service is None or what is None:
        return False
    try:
        return bool(service[3](what))
    except (TypeError, ValueError, OSError):
        return False


def selection():
    """The words selected in any app (the primary selection), or ""."""
    if not shutil.which("wl-paste"):
        return ""
    try:
        result = subprocess.run(["wl-paste", "--primary", "--no-newline", "--type", "text"],
                                capture_output=True, timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode:
        return ""
    return result.stdout[:LONGEST * 4].decode("utf-8", "replace")[:LONGEST]


# Asking the app that does the work ------------------------------------------
def _bus():
    from gi.repository import Gio
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def _running(bus, name):
    from gi.repository import GLib
    try:
        reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                              "NameHasOwner", GLib.Variant("(s)", (name,)), GLib.VariantType("(b)"),
                              0, 2000, None)
        return reply.unpack()[0]
    except GLib.Error:
        return False


def ask_app(app_id, command, action, text, wait=10.0):
    """Activate the app's own action with this text, starting the app
    (command, a list) first if it isn't running. True if it was asked."""
    from gi.repository import GLib
    bus = _bus()
    if not _running(bus, app_id):
        try:
            subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except OSError:
            return False
        end = time.monotonic() + wait
        while not _running(bus, app_id):
            if time.monotonic() > end:
                return False
            time.sleep(0.15)
        time.sleep(0.3)   # its actions are published a moment after its name
    path = "/" + app_id.replace(".", "/")
    for _ in range(10):
        try:
            bus.call_sync(app_id, path, "org.gtk.Actions", "Activate",
                          GLib.Variant("(sava{sv})", (action, [GLib.Variant("s", text)], {})),
                          None, 0, 5000, None)
            return True
        except GLib.Error:
            time.sleep(0.3)
    return False


def _launch(*argv):
    try:
        subprocess.Popen(list(argv), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        return True
    except OSError:
        return False


def run(service_id, what):
    """Do the service with this text (or list of paths). True if it was done."""
    if not suits(service_id, what):
        return False
    if service_id == "sticky":
        return ask_app("org.freemac.Stickies", ["freemac-stickies", "--restore"], "service", what.strip())
    if service_id == "jot":
        return ask_app("org.freemac.Jot", ["freemac-jot"], "service", what.strip())
    if service_id == "words":
        return ask_app("org.freemac.Words", ["freemac-words"], "service", what.strip())
    if service_id == "seek":
        return ask_app("org.freemac.Seek", ["freemac-seek", "--background"], "service", " ".join(what.split()))
    if service_id == "speak":
        return _launch("freemac-speak", what)
    if service_id == "url":
        url = what.strip()
        return _launch("xdg-open", url if "://" in url else "https://" + url)
    if service_id == "reveal":
        # Drawer opens a file's folder with the file chosen, as on a Mac.
        return _launch("freemac-drawer", os.path.expanduser(what.strip()))
    if service_id == "terminal":
        return _launch("foot", "--working-directory", what[0])
    if service_id == "wallpaper":
        from .ini import ini_set
        ini_set(SHELL_INI, "background", "image", os.path.abspath(what[0]))
        return True
    return False


def _tell(summary, body=""):
    try:
        from . import beacon
        beacon.send(summary, body, icon="applications-system-symbolic", app="Services")
    except Exception:   # no Beacon: say it where it was run from
        print(summary, file=sys.stderr)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in BY_ID:
        print(__doc__, file=sys.stderr)
        return 2
    service = BY_ID[argv[0]]
    if service[2] == "files":
        what = [os.path.abspath(p) for p in argv[1:]]
    else:
        what = " ".join(argv[1:]) if len(argv) > 1 else selection()
    if not suits(service[0], what):
        if service[2] == "files":
            _tell(f"{service[1]} can't use what's chosen.")
        elif not (what or "").strip():
            _tell(f"Select some words first, then use {service[1]}.")
        else:
            _tell(f"{service[1]} can't use the words selected.")
        return 1
    if not run(service[0], what):
        _tell(f"{service[1]} couldn't be done just now.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
