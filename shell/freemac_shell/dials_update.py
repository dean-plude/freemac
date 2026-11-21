# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Software Update, as on a Mac: which freemac this is, a button to
look for updates now (Harbor's Updates page), and a switch that installs
important (security) updates by themselves in the background, through
Ubuntu's unattended-upgrades. Original freemac code."""
import os

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import admin_switch  # noqa: E402


def _release():
    found = {}
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if "=" in line:
                    key, value = line.rstrip().split("=", 1)
                    found[key] = value.strip('"')
    except OSError:
        pass
    return found


def software_update_page(window):
    group, row, page, _slider, _switch = window.helpers
    release = _release()
    name = release.get("PRETTY_NAME") or "freemac"
    check = Gtk.Button(label="Check for Updates…")

    def open_updates(_button):
        try:
            Gio.Subprocess.new(["freemac-harbor", "--updates"], Gio.SubprocessFlags.NONE)
        except GLib.Error:
            pass
    check.connect("clicked", open_updates)
    rows = [row(name, check, "freemac looks for updates once a day and tells you when some are ready. "
                             "Harbor installs them.")]
    if os.path.exists("/usr/bin/unattended-upgrade") and os.path.exists(admin_switch.SYSTEM_HELPER):
        rows.append(row("Install important updates automatically", admin_switch.auto_updates_switch(),
                        "Security fixes are installed in the background, so the computer stays safe "
                        "without you doing anything. Other updates still wait for you in Harbor."))
    return page("Software Update", group(*rows))
