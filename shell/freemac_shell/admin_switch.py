# SPDX-License-Identifier: GPL-3.0-or-later
"""A switch for a setting that changes the whole computer, such as the
firewall: flipping it runs a root helper through pkexec, which asks for an
administrator's password, and the switch then shows what the computer really
did. Cancelling the password puts it back. Original freemac code.
"""
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert  # noqa: E402

SYSTEM_HELPER = "/usr/libexec/freemac-system-helper"


def admin_switch(read, command, failed="This setting couldn’t be changed.", then=None):
    """read() -> bool says whether the setting is on; command(on) -> argv to
    run as root; then(on), if given, finishes the change as the person once
    the root part has worked. Returns the Gtk.Switch."""
    switch = Gtk.Switch(valign=Gtk.Align.CENTER, active=read())

    def show(on):
        switch.handler_block(handler)
        switch.set_active(on)
        switch.handler_unblock(handler)

    def toggled(_switch, _param):
        on = switch.get_active()
        switch.set_sensitive(False)
        try:
            process = Gio.Subprocess.new(["pkexec"] + command(on), Gio.SubprocessFlags.STDERR_PIPE)
        except GLib.Error as error:
            switch.set_sensitive(True)
            show(read())
            alert.tell(switch.get_toplevel(), failed, error.message)
            return

        def finished(proc, result):
            switch.set_sensitive(True)
            try:
                _ok, _out, err = proc.communicate_utf8_finish(result)
            except GLib.Error:
                err = ""
            if proc.get_exit_status() == 0 and then is not None:
                then(on)
            show(read())
            # 126 and 127: the password was cancelled, or not given.
            if proc.get_exit_status() not in (0, 126, 127):
                alert.tell(switch.get_toplevel(), failed, (err or "").strip())
        process.communicate_utf8_async(None, None, finished)

    handler = switch.connect("notify::active", toggled)
    return switch


def _setting(path, pattern):
    try:
        with open(path) as f:
            return pattern in f.read().replace(" ", "")
    except OSError:
        return False


def firewall_on():
    return _setting("/etc/ufw/ufw.conf", "ENABLED=yes")


def auto_updates_on():
    return _setting("/etc/apt/apt.conf.d/20auto-upgrades", 'APT::Periodic::Unattended-Upgrade"1"')


def firewall_switch():
    return admin_switch(firewall_on, lambda on: [SYSTEM_HELPER, "firewall", "on" if on else "off"],
                        "The firewall couldn’t be changed.")


def auto_updates_switch():
    return admin_switch(auto_updates_on, lambda on: [SYSTEM_HELPER, "auto-updates", "on" if on else "off"],
                        "Automatic updates couldn’t be changed.")
