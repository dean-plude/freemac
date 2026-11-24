# SPDX-License-Identifier: GPL-3.0-or-later
"""The installed apps as Drawer's Applications folder shows them, and
whether a .desktop file is an installed app (opened as the app) or just a
file. Original freemac code.
"""
import os
import subprocess

from gi.repository import Gio, GLib

from . import macapps


def app_folders():
    """Where installed apps' .desktop files are."""
    dirs = [GLib.get_user_data_dir()] + list(GLib.get_system_data_dirs())
    return [os.path.join(d, "applications") + "/" for d in dirs]


def is_installed_app(path):
    """An installed app's .desktop file. Only these are opened as apps; a
    .desktop file anywhere else, such as one downloaded, is just a file."""
    if not path or not path.endswith(".desktop"):
        return False
    real = os.path.realpath(path)
    return any(real.startswith(os.path.realpath(d) + "/") for d in app_folders())


def installed_apps():
    """[(name, .desktop path, icon)] for the apps in Marina, without the
    Mac apps Ferry added (they show as themselves)."""
    found, seen = [], set()
    for app in Gio.AppInfo.get_all():
        if not app.should_show():
            continue
        filename = getattr(app, "get_filename", lambda: None)()
        if not filename or os.path.basename(filename).startswith(macapps.ICON_PREFIX):
            continue
        if app.get_id() in seen:
            continue
        seen.add(app.get_id())
        found.append((app.get_display_name() or app.get_name(), filename, app.get_icon()))
    return found


def package_of(path):
    """(package, version, installed size in bytes) for the app's .desktop
    file, or None when no package owns it (an app added by hand)."""
    if os.path.basename(path).startswith("freemac-"):
        # freemac's own apps come with freemac, at its version.
        from . import manifest
        return "freemac", manifest.freemac_version(), 0
    try:
        out = subprocess.run(["dpkg-query", "-S", os.path.realpath(path)], capture_output=True, text=True,
                             timeout=15)
        if out.returncode:
            return None
        package = out.stdout.split(":", 1)[0].strip().split(",")[0].strip()
        out = subprocess.run(["dpkg-query", "-W", "-f", "${Version}\t${Installed-Size}", package],
                             capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode or "\t" not in out.stdout:
        return None
    version, _, kb = out.stdout.partition("\t")
    try:
        size = int(kb) * 1024
    except ValueError:
        size = 0
    return package, version.strip(), size
