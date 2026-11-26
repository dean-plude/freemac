# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Privacy & Security: whether the start-up disk is encrypted, as a
Mac's FileVault shows it, with Change Disk Password… and New Recovery Key….
Below it, Control Other Windows: the Mac apps that asked to move and resize
other apps' windows (window_control.py), each with a switch, and Forget to
have it asked again (freemac 1.215, Ferry 0.41.0); from freemac 1.220 the
same answer covers listing other apps' windows and pressing keys in them.
From freemac 1.241 the other questions Mac apps ask through Ferry have
sections of their own once an app has asked: Screen Recording, Microphone
and Camera.

Keel, the installer, encrypts the disk when "Encrypt the disk" is on. The
changes go through /usr/libexec/freemac-disk-helper with pkexec, so an
administrator's password is asked first; the disk's own password is asked
too, since only a key the disk already knows can add or change one.

Original freemac code.
"""
import json
import os
import subprocess

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, window_control  # noqa: E402

HELPER = "/usr/libexec/freemac-disk-helper"


def disk_status():
    """{"encrypted": bool, ...} for the start-up disk."""
    if not os.path.exists(HELPER):
        return {"encrypted": False}
    try:
        out = subprocess.run([HELPER, "status"], capture_output=True, text=True, timeout=5).stdout
        return json.loads(out)
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"encrypted": False}


def caption(text):
    label = Gtk.Label(label=text, xalign=0, wrap=True)
    label.get_style_context().add_class("dials-caption")
    return label


def password_dialog(window, title, action, lines, fields):
    """Ask for passwords: fields is [(label, needs confirming)]. Returns the
    typed values, or None when cancelled."""
    dialog = Gtk.Dialog(title=title, transient_for=window, modal=True, use_header_bar=True)
    dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
    ok = dialog.add_button(action, Gtk.ResponseType.OK)
    ok.get_style_context().add_class("suggested-action")
    dialog.set_default_response(Gtk.ResponseType.OK)
    grid = Gtk.Grid(row_spacing=10, column_spacing=12, margin=18)
    dialog.get_content_area().add(grid)
    text = caption(lines)
    text.set_max_width_chars(46)
    grid.attach(text, 0, 0, 2, 1)
    entries, checks = [], []
    top = 1
    for label, confirm in fields:
        entry = Gtk.Entry(visibility=False, activates_default=True, hexpand=True)
        grid.attach(Gtk.Label(label=label, xalign=1), 0, top, 1, 1)
        grid.attach(entry, 1, top, 1, 1)
        entries.append(entry)
        top += 1
        if confirm:
            again = Gtk.Entry(visibility=False, activates_default=True)
            grid.attach(Gtk.Label(label="Verify", xalign=1), 0, top, 1, 1)
            grid.attach(again, 1, top, 1, 1)
            checks.append((entry, again))
            top += 1

    def update(*_):
        filled = all(e.get_text() for e in entries)
        same = all(a.get_text() == b.get_text() for a, b in checks)
        long_enough = all(len(a.get_text()) >= 4 for a, _b in checks)
        ok.set_sensitive(filled and same and long_enough)

    for entry in entries + [b for _a, b in checks]:
        entry.connect("changed", update)
    update()
    dialog.show_all()
    answer = dialog.run()
    values = [e.get_text() for e in entries]
    dialog.destroy()
    return values if answer == Gtk.ResponseType.OK else None


def run_helper(window, args, stdin, done, status):
    """Run the disk helper through pkexec without freezing Dials."""
    status.set_text("Waiting for an administrator's password…")
    flags = Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
    try:
        proc = Gio.Subprocess.new(["pkexec", HELPER, *args], flags)
    except GLib.Error as e:
        status.set_text("")
        alert.tell(window, "That didn't work", e.message)
        return

    def finished(p, result):
        out, err = "", ""
        try:
            _ok, out, err = p.communicate_utf8_finish(result)
        except GLib.Error as e:
            err = e.message
        status.set_text("")
        code = p.get_exit_status() if p.get_if_exited() else 1
        if code in (126, 127):
            err = "The administrator's password wasn't given, so nothing changed."
        if code:
            alert.tell(window, "That didn't work", (err or "").strip())
            return
        done(out or "")

    proc.communicate_utf8_async(stdin, None, finished)


def show_key(window, key):
    """Show a new recovery key once, with a box to tick before closing."""
    dialog = Gtk.Dialog(title="New Recovery Key", transient_for=window, modal=True, use_header_bar=True)
    done = dialog.add_button("Done", Gtk.ResponseType.OK)
    done.get_style_context().add_class("suggested-action")
    done.set_sensitive(False)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
    dialog.get_content_area().add(box)
    text = caption("Write this key down and keep it somewhere safe, away from the computer. It is shown "
                   "only once. The old recovery key doesn't work any more.")
    text.set_max_width_chars(46)
    box.pack_start(text, False, False, 0)
    label = Gtk.Label(label=key, selectable=True, xalign=0)
    label.get_style_context().add_class("dials-recovery-key")
    box.pack_start(label, False, False, 0)
    wrote = Gtk.CheckButton(label="I've written down my recovery key")
    wrote.connect("toggled", lambda b: done.set_sensitive(b.get_active()))
    box.pack_start(wrote, False, False, 0)
    dialog.connect("delete-event", lambda *_: not wrote.get_active())
    dialog.show_all()
    dialog.run()
    dialog.destroy()


def security_page(window):
    group, row, page, _slider, _switch = window.helpers
    info = disk_status()
    status = caption("")
    if info.get("encrypted"):
        state = Gtk.Label(label="On", xalign=1)
        state.get_style_context().add_class("dim-label")
        summary = row("Disk Encryption", state,
                      "Your start-up disk is encrypted. Nobody can read its files without your password "
                      "or the recovery key, even by taking the disk out of the computer.")

        def change(*_):
            values = password_dialog(
                window, "Change Disk Password", "Change",
                "This is the password typed on the start-up screen. Changing your own login password in "
                "Users changes it too, if the two were the same.",
                [("Current", False), ("New", True)])
            if values:
                run_helper(window, ["password"], f"{values[0]}\n{values[1]}\n",
                           lambda _out: alert.tell(window, "The disk's password was changed",
                                                   "Type the new password the next time the computer starts."),
                           status)

        def recovery(*_):
            values = password_dialog(
                window, "New Recovery Key", "Make Key",
                "A new recovery key replaces the old one, which stops working. Type the disk's password "
                "to make it.",
                [("Disk password", False)])
            if values:
                run_helper(window, ["recovery"], values[0] + "\n",
                           lambda out: show_key(window, out.strip().splitlines()[-1]), status)

        change_button = Gtk.Button(label="Change Disk Password…")
        change_button.connect("clicked", change)
        key_button = Gtk.Button(label="New Recovery Key…")
        key_button.connect("clicked", recovery)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.START)
        buttons.pack_start(change_button, False, False, 0)
        buttons.pack_start(key_button, False, False, 0)
        listbox = group(summary)
        children = [listbox, buttons]
    else:
        state = Gtk.Label(label="Off", xalign=1)
        state.get_style_context().add_class("dim-label")
        listbox = group(row("Disk Encryption", state,
                            "Your start-up disk isn't encrypted, so someone with the computer could take "
                            "out the disk and read its files."))
        children = [listbox, caption(
            "The disk is encrypted when freemac is installed. To turn it on, back up with Lifeboat, then "
            "install freemac again from its USB stick and turn on “Encrypt the disk”.")]
    children += control_section(window)
    return page("Privacy & Security", *children, status)


# The questions Mac apps ask through Ferry, as Dials lists them: the heading,
# the caption, and whether the section shows before any app has asked.
KIND_SECTIONS = (
    ("control", "Control Other Windows",
     "These Mac apps asked to move and resize the windows of other apps, list them, and press keys in "
     "them, as window managers such as Spectacle and clipboard managers such as Flycut do. An app that "
     "is off can't. Forget takes an app off the list, and it asks again the next time.", True),
    ("screen-recording", "Screen Recording",
     "These Mac apps asked to record the screen and other apps' windows, as OBS Studio does. An app that "
     "is off can't. Forget takes an app off the list, and it asks again the next time.", False),
    ("microphone", "Microphone",
     "These Mac apps asked to use the microphone. An app that is off hears nothing. Forget takes an app "
     "off the list, and it asks again the next time.", False),
    ("camera", "Camera",
     "These Mac apps asked to use the camera. An app that is off sees nothing. Forget takes an app off "
     "the list, and it asks again the next time.", False),
)


def control_section(window):
    """A section for each question Mac apps ask (controlling other windows,
    recording the screen, the microphone, the camera): a heading, a group
    with a row for each app that asked, and a caption. Control Other Windows
    always shows; the others once an app has asked."""
    widgets = []
    for kind, title, text, always in KIND_SECTIONS:
        if always or window_control.apps(kind):
            widgets += kind_section(window, kind, title, text)
    return widgets


def kind_section(window, kind, title, text):
    group, row, _page, _slider, switch = window.helpers
    heading = Gtk.Label(label=title, xalign=0)
    heading.get_style_context().add_class("dials-caption")
    listbox = group()

    def fill():
        for child in listbox.get_children():
            listbox.remove(child)
        rows = window_control.apps(kind)
        if not rows:
            listbox.add(row("No Mac app has asked yet"))
        for app_id, name, allowed in rows:
            box = Gtk.Box(spacing=8)
            forget = Gtk.Button(label="Forget")
            forget.connect("clicked", lambda _b, a=app_id: (window_control.forget(a, kind), fill()))
            box.pack_start(forget, False, False, 0)
            box.pack_start(switch(allowed, lambda on, a=app_id, n=name: window_control.set_allowed(a, on, n, kind)),
                           False, False, 0)
            listbox.add(row(name, box, app_id))
        listbox.show_all()

    fill()
    return [heading, listbox, caption(text)]
