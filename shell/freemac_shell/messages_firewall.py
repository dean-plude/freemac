# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages and the firewall (no GTK).

With Dials > Network > Firewall on, nothing on the network can start a
connection to this computer, and an Android phone running KDE Connect can't
reach Messages: it finds the computer over UDP 1716 and then connects to one
of TCP 1716-1764. When "Use an Android phone for texts" is turned on, Messages
asks freemac's system helper (the same root helper Dials' firewall, Remote
Login, File Sharing and Screen Sharing switches use, through pkexec and the
org.freemac.system.settings polkit action, after an administrator's
password) to let exactly those ports in from the local network only:

    freemac-system-helper kde-connect on    UDP 1716, TCP 1716:1764 from 10/8, 172.16/12, 192.168/16
    freemac-system-helper kde-connect off   the same rules taken out again

The helper leaves a note, /var/lib/freemac/kde-connect, while they're open,
so turning the firewall on later in Dials opens them again, and so Messages
can tell whether they're open. Nothing else about the firewall changes.

Original freemac code.
"""
import os
import shutil

HELPER = "/usr/libexec/freemac-system-helper"
UFW_CONF = "/etc/ufw/ufw.conf"
MARK = "/var/lib/freemac/kde-connect"


def firewall_on():
    """Whether Dials' Firewall is on (ufw enabled), as admin_switch reads it."""
    try:
        with open(UFW_CONF) as f:
            return "ENABLED=yes" in f.read().replace(" ", "")
    except OSError:
        return False


def ports_open():
    """Whether the helper has let KDE Connect's ports in."""
    return os.path.exists(MARK)


def available():
    return os.path.exists(HELPER) and shutil.which("pkexec") is not None


def change_for(phone_on):
    """What to ask the helper for when the phone setting is phone_on: True
    (open the ports), False (close them) or None (nothing to do). Ports are
    opened only while the firewall is on; they're closed whenever they're
    open and the phone is turned off."""
    if phone_on:
        return True if firewall_on() and not ports_open() else None
    return False if ports_open() else None


def command(on):
    return ["pkexec", HELPER, "kde-connect", "on" if on else "off"]


def run(on, done=None):
    """Runs the helper without waiting; done(ok, error text) on the main loop.
    A cancelled password is not ok, with no error text."""
    from gi.repository import Gio, GLib
    try:
        process = Gio.Subprocess.new(command(on), Gio.SubprocessFlags.STDERR_PIPE)
    except GLib.Error as error:
        if done:
            done(False, error.message)
        return

    def finished(proc, result):
        try:
            _ok, _out, err = proc.communicate_utf8_finish(result)
        except GLib.Error:
            err = ""
        status = proc.get_exit_status()
        if done:
            # 126 and 127: the password was cancelled, or not given.
            done(status == 0, "" if status in (0, 126, 127) else (err or "").strip())
    process.communicate_utf8_async(None, None, finished)
