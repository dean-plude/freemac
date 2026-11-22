# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Sharing, as on a Mac: the computer's name, Nearby sharing, File
Sharing (the Public folder, for other computers on the network to open),
Screen Sharing (seeing and using this screen from another computer, after
signing in) and Remote Login (SSH) for someone at another computer on the same
network. Renaming and the three kinds of sharing change the whole computer, so
each asks for an administrator's password. Original freemac code."""
import os
import pwd
import re
import shlex
import shutil
import socket

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import admin_switch, alert  # noqa: E402

MACHINE_INFO = os.environ.get("FREEMAC_MACHINE_INFO", "/etc/machine-info")
SSH_WANTS = ("/etc/systemd/system/multi-user.target.wants/ssh.service",
             "/etc/systemd/system/sockets.target.wants/ssh.socket")


def pretty_name():
    """The computer's name as people write it ("Dean's freemac"), or None."""
    try:
        with open(MACHINE_INFO) as f:
            for line in f:
                key, _, value = line.strip().partition("=")
                if key == "PRETTY_HOSTNAME" and value:
                    words = shlex.split(value)   # written shell-quoted
                    return words[0] if words else None
    except (OSError, ValueError):
        pass
    return None


def computer_name():
    return pretty_name() or socket.gethostname() or "freemac"


def local_name(name):
    """The name other computers use on the network for a computer called
    `name`: "Dean's freemac" -> "Deans-freemac", as a Mac does."""
    name = name.replace("’", "").replace("'", "")
    slug = re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-")[:63].strip("-")
    return slug or "freemac"


def mdns_on():
    """Whether this computer answers to name.local (Avahi is installed)."""
    return shutil.which("avahi-daemon") is not None or os.path.exists("/usr/sbin/avahi-daemon")


def remote_login_available():
    return os.path.exists("/usr/sbin/sshd") and os.path.exists(admin_switch.SYSTEM_HELPER)


SMB_WANTS = "/etc/systemd/system/multi-user.target.wants/smbd.service"


def file_sharing_available():
    return os.path.exists("/usr/sbin/smbd") and os.path.exists(admin_switch.SYSTEM_HELPER)


def file_sharing_on():
    return os.path.exists(SMB_WANTS)


def public_folder():
    return os.path.join(GLib.get_home_dir(), "Public")


def remote_login_on():
    return any(os.path.exists(path) for path in SSH_WANTS)


def rename(parent, new, done):
    """Rename the computer through the root helper; done() afterwards."""
    try:
        process = Gio.Subprocess.new(["pkexec", admin_switch.SYSTEM_HELPER, "computer-name", new],
                                     Gio.SubprocessFlags.STDERR_PIPE)
    except GLib.Error as error:
        alert.tell(parent, "The computer couldn’t be renamed.", error.message)
        done()
        return

    def finished(proc, result):
        try:
            _ok, _out, err = proc.communicate_utf8_finish(result)
        except GLib.Error:
            err = ""
        if proc.get_exit_status() not in (0, 126, 127):
            alert.tell(parent, "The computer couldn’t be renamed.", (err or "").strip())
        done()
    process.communicate_utf8_async(None, None, finished)


def _note(label):
    """A row holding only a caption, under the row it explains."""
    label.get_style_context().add_class("dials-caption")
    item = Gtk.ListBoxRow(activatable=False)
    item.add(label)
    return item


def sharing_page(window):
    from . import hail

    group, row, page, _slider, _switch = window.helpers
    sections = []

    entry = Gtk.Entry(text=computer_name(), width_chars=24, valign=Gtk.Align.CENTER)
    caption = Gtk.Label(xalign=0, wrap=True, max_width_chars=52)

    def describe():
        local = local_name(computer_name()) + ".local"
        words = "Nearby devices and printers see this name."
        if mdns_on():
            words += f" Other computers on your network can reach this one at {local}."
        caption.set_text(words)

    def apply(*_):
        if not entry.get_sensitive():
            return       # already asking (Return, then the focus leaving)
        new = entry.get_text().strip()
        if not new or new == computer_name():
            entry.set_text(computer_name())
            return
        if len(new) > 63:
            alert.tell(window, "That name is too long.", "Use 63 letters or fewer.")
            return
        entry.set_sensitive(False)

        def done():
            entry.set_sensitive(True)
            entry.set_text(computer_name())
            describe()
            login_caption()
            screen_caption()
        rename(window, new, done)

    entry.connect("activate", apply)
    entry.connect("focus-out-event", lambda *_: apply() and False)
    name_row = row("Computer name", entry)
    describe()
    sections.append(group(name_row, _note(caption)))

    receive = Gtk.Switch(active=hail.receiving(), valign=Gtk.Align.CENTER)
    receive.connect("notify::active", lambda s, _p: hail.set_receiving(s.get_active()))
    sections.append(group(row("Nearby sharing", receive,
                              "Lets computers and phones on this Wi-Fi offer you files, which you "
                              "accept or decline. Phones need the free LocalSend app.")))

    if file_sharing_available():
        share_note = Gtk.Label(xalign=0, wrap=True, max_width_chars=52, selectable=True)
        open_public = Gtk.Button(label="Open Public Folder", halign=Gtk.Align.START)
        open_public.connect("clicked", lambda *_: GLib.spawn_async(
            ["freemac-drawer", public_folder()], flags=GLib.SpawnFlags.SEARCH_PATH))

        def share_caption():
            host = local_name(computer_name())
            if file_sharing_on():
                share_note.set_text(
                    "Other computers on this network can open the Public folder in your home folder, "
                    f"without a password. On a Mac or freemac, it's under Network as {host}; on Windows, "
                    f"type \\\\{host}\\Public in File Explorer. They can look, but not change anything.")
            else:
                share_note.set_text("Lets other computers on this network open the Public folder in your "
                                    "home folder, without a password. Put in it what you want to share.")
            open_row.set_visible(file_sharing_on() and os.path.isdir(public_folder()))

        open_row = Gtk.ListBoxRow(activatable=False)
        open_row.add(open_public)
        open_row.set_no_show_all(True)
        open_public.show()
        share_switch = admin_switch.admin_switch(file_sharing_on,
                                                 lambda on: [admin_switch.SYSTEM_HELPER, "file-sharing",
                                                             "on" if on else "off"],
                                                 "File Sharing couldn’t be changed.")
        share_switch.connect("notify::sensitive", lambda s, _p: s.get_sensitive() and share_caption())
        share_caption()
        sections.append(group(row("File Sharing", share_switch), _note(share_note), open_row))

    from . import screen_sharing

    if screen_sharing.available() and os.path.exists(admin_switch.SYSTEM_HELPER):
        screen_note = Gtk.Label(xalign=0, wrap=True, max_width_chars=52, selectable=True)

        def screen_caption():
            try:
                user = pwd.getpwuid(os.getuid()).pw_name
            except KeyError:
                user = "your user name"
            host = local_name(computer_name())
            if screen_sharing.enabled():
                screen_note.set_text(
                    f"From another freemac on this network, open Porthole and type {host}. It asks for a "
                    f"name and password: {user} and your password. They can see and use this screen; "
                    "the menu bar shows when someone is, and you can disconnect them.")
            else:
                screen_note.set_text("Lets you see and use this computer from another one on the network, "
                                     "after signing in with your password.")

        screen_switch = admin_switch.admin_switch(
            screen_sharing.enabled,
            lambda on: [admin_switch.SYSTEM_HELPER, "screen-sharing", "on" if on else "off"],
            "Screen Sharing couldn’t be changed.",
            then=lambda on: screen_sharing.turn_on() if on else screen_sharing.turn_off())
        screen_switch.connect("notify::sensitive", lambda s, _p: s.get_sensitive() and screen_caption())
        screen_caption()
        sections.append(group(row("Screen Sharing", screen_switch), _note(screen_note)))
    else:
        def screen_caption():
            pass

    if remote_login_available():
        login_note = Gtk.Label(xalign=0, wrap=True, max_width_chars=52, selectable=True)

        def login_caption():
            try:
                user = pwd.getpwuid(os.getuid()).pw_name
            except KeyError:
                user = "you"
            host = local_name(computer_name()) + ".local" if mdns_on() else socket.gethostname()
            if remote_login_on():
                login_note.set_text(f"On another computer on this network, open Terminal and type: "
                                    f"ssh {user}@{host}. It asks for your password.")
            else:
                login_note.set_text("Lets someone at another computer on this network use this one's "
                                    "Terminal with a user name and password. Off unless you need it.")

        switch = admin_switch.admin_switch(remote_login_on,
                                           lambda on: [admin_switch.SYSTEM_HELPER, "remote-login",
                                                       "on" if on else "off"],
                                           "Remote Login couldn’t be changed.")
        # The switch comes back once the password is given and the helper is done.
        switch.connect("notify::sensitive", lambda s, _p: s.get_sensitive() and login_caption())
        login_caption()
        sections.append(group(row("Remote Login", switch), _note(login_note)))
    else:
        def login_caption():
            pass

    return page("Sharing", *sections)
