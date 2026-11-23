# SPDX-License-Identifier: GPL-3.0-or-later
"""Apps that open at login, kept the freedesktop way in ~/.config/autostart.

Pier's "Options > Open at Login" turns an app on or off here, and
freemac-login-items (started with the session) opens each one that's on.
Original freemac code.

    freemac-login-items        open the apps set to open at login
"""
import os
import shutil
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

FOLDER = os.path.join(GLib.get_user_config_dir(), "autostart")


def _path(desktop_id):
    return os.path.join(FOLDER, desktop_id)


def is_on(desktop_id):
    if not desktop_id:
        return False
    path = _path(desktop_id)
    if not os.path.exists(path):
        return False
    keyfile = GLib.KeyFile()
    try:
        keyfile.load_from_file(path, GLib.KeyFileFlags.NONE)
        return not keyfile.get_boolean("Desktop Entry", "Hidden")
    except GLib.Error:
        return True


def set_on(desktop_id, on):
    """Open (or stop opening) this app at login. Returns whether it's now on."""
    if not desktop_id:
        return False
    path = _path(desktop_id)
    if not on:
        try:
            os.remove(path)
        except OSError:
            pass
        return False
    info = Gio.DesktopAppInfo.new(desktop_id)
    if info is None or not info.get_filename():
        return False
    os.makedirs(FOLDER, exist_ok=True)
    shutil.copyfile(info.get_filename(), path)
    return True


def items(listed_only=False):
    """The desktop files set to open at login, by name. listed_only leaves
    out quiet helpers that aren't shown as apps (Chime's alarm watcher),
    for Dials' list; they still open at login."""
    try:
        names = sorted(os.listdir(FOLDER))
    except OSError:
        return []
    found = []
    for name in names:
        if not name.endswith(".desktop"):
            continue
        try:
            info = Gio.DesktopAppInfo.new_from_filename(_path(name))
        except TypeError:
            info = None
        if info is None or info.get_is_hidden():
            continue
        if not info.get_show_in(None):  # OnlyShowIn/NotShowIn, by XDG_CURRENT_DESKTOP
            continue
        if listed_only and info.get_nodisplay():
            continue
        found.append(info)
    return found


def open_all():
    for info in items():
        try:
            info.launch([], None)
        except GLib.Error as error:
            print(f"freemac-login-items: couldn't open {info.get_id()}: {error.message}", file=sys.stderr)


def main():
    # A login with no password (automatic login) opens no keychain; make one
    # without a password, so the first saved password doesn't ask for one.
    try:
        from . import keychain
        keychain.ensure_login()
    except Exception:   # never keep login items from opening
        pass
    open_all()


if __name__ == "__main__":
    main()
