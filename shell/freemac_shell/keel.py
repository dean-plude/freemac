# SPDX-License-Identifier: GPL-3.0-or-later
"""Keel: freemac's installer.

Walks through choosing a disk and creating an account, then runs the Keel
backend (freemac-install) as root and shows its progress.
"""
import json
import os
import re
import subprocess

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import keel_backend  # noqa: E402

BACKEND = "/usr/bin/freemac-install"
REGIONS = ("Africa", "America", "Antarctica", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific")
CSS = b"""
.keel-page { padding: 28px 36px; }
.keel-title { font-size: 24px; font-weight: 800; }
.keel-lead { font-size: 14px; }
.keel-warning { color: #b3261e; font-weight: 600; }
.keel-disk { padding: 10px 14px; border-radius: 10px; }
.keel-caption { opacity: 0.65; font-size: 12px; }
"""


def human(size):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            return f"{size:.0f} {unit}"
        size /= 1000
    return ""


def timezones():
    zones = ["UTC"]
    for region in REGIONS:
        base = os.path.join("/usr/share/zoneinfo", region)
        for root, _dirs, files in os.walk(base):
            for name in files:
                zones.append(os.path.relpath(os.path.join(root, name), "/usr/share/zoneinfo"))
    return sorted(set(zones))


def current_timezone():
    try:
        target = os.readlink("/etc/localtime")
        return target.split("zoneinfo/", 1)[1]
    except (OSError, IndexError):
        return "UTC"


def page(title, lead=None):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    box.get_style_context().add_class("keel-page")
    heading = Gtk.Label(label=title, xalign=0)
    heading.get_style_context().add_class("keel-title")
    box.pack_start(heading, False, False, 0)
    if lead:
        text = Gtk.Label(label=lead, xalign=0, wrap=True, max_width_chars=70)
        text.get_style_context().add_class("keel-lead")
        box.pack_start(text, False, False, 0)
    return box


class Keel(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Install freemac")
        self.set_default_size(720, 520)
        header = Gtk.HeaderBar(show_close_button=True, title="Install freemac")
        self.set_titlebar(header)
        self.back = Gtk.Button(label="Back")
        self.back.connect("clicked", lambda *_: self.go(-1))
        header.pack_start(self.back)
        self.next = Gtk.Button(label="Continue")
        self.next.get_style_context().add_class("suggested-action")
        self.next.connect("clicked", lambda *_: self.go(+1))
        header.pack_end(self.next)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.add(self.stack)
        self.pages = ["welcome", "disk", "account", "confirm", "progress", "done"]
        self.index = 0
        self.ready = False
        self.stack.add_named(self.welcome_page(), "welcome")
        self.stack.add_named(self.disk_page(), "disk")
        self.stack.add_named(self.account_page(), "account")
        self.stack.add_named(self.confirm_page(), "confirm")
        self.stack.add_named(self.progress_page(), "progress")
        self.stack.add_named(self.done_page(), "done")
        self.ready = True
        self.update_buttons()

    # Pages --------------------------------------------------------------------
    def welcome_page(self):
        box = page("Install freemac",
                   "Keel copies freemac from this live session onto your computer's disk, sets up your "
                   "account, and makes the disk start up on its own. It takes a few minutes.")
        for line in ("The disk you choose is erased completely. Back up anything you need first.",
                     "freemac installs on the whole disk; sharing a disk with another system isn't supported yet.",
                     "On PCs with Secure Boot turned on, turn it off in the firmware settings first."):
            label = Gtk.Label(label="•  " + line, xalign=0, wrap=True, max_width_chars=70)
            box.pack_start(label, False, False, 0)
        return box

    def disk_page(self):
        box = page("Choose a disk", "freemac will erase this disk and use all of it.")
        self.disk_list = Gtk.ListBox()
        self.disk_list.connect("row-selected", lambda *_: self.update_buttons())
        frame = Gtk.Frame()
        frame.add(self.disk_list)
        box.pack_start(frame, False, False, 0)
        self.no_disks = Gtk.Label(label="No disk of 8 GB or more was found.", xalign=0)
        box.pack_start(self.no_disks, False, False, 0)
        refresh = Gtk.Button(label="Look Again", halign=Gtk.Align.START)
        refresh.connect("clicked", lambda *_: self.load_disks())
        box.pack_start(refresh, False, False, 0)
        self.load_disks()
        return box

    def load_disks(self):
        for child in self.disk_list.get_children():
            self.disk_list.remove(child)
        try:
            found = keel_backend.disks()
        except (OSError, ValueError):
            found = []
        for disk in found:
            row = Gtk.ListBoxRow()
            row.disk = disk
            line = Gtk.Box(spacing=12)
            line.get_style_context().add_class("keel-disk")
            icon = "drive-removable-media-symbolic" if disk["removable"] else "drive-harddisk-symbolic"
            line.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.DND), False, False, 0)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            text.pack_start(Gtk.Label(label=f"{disk['model']}  —  {human(disk['size'])}", xalign=0), False, False, 0)
            caption = Gtk.Label(label=disk["path"] + ("  (removable)" if disk["removable"] else ""), xalign=0)
            caption.get_style_context().add_class("keel-caption")
            text.pack_start(caption, False, False, 0)
            line.pack_start(text, True, True, 0)
            row.add(line)
            self.disk_list.add(row)
        self.disk_list.show_all()
        self.no_disks.set_visible(not found)
        self.no_disks.set_no_show_all(True)
        if len(found) == 1:
            self.disk_list.select_row(self.disk_list.get_row_at_index(0))
        self.update_buttons()

    def account_page(self):
        box = page("Create your account", "You'll use this name and password to log in and to make changes.")
        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        self.fullname = Gtk.Entry(placeholder_text="Ada Lovelace")
        self.username = Gtk.Entry(placeholder_text="ada")
        self.hostname = Gtk.Entry(placeholder_text="ada-pc")
        self.password = Gtk.Entry(visibility=False)
        self.password2 = Gtk.Entry(visibility=False)
        self.username_edited = self.hostname_edited = False
        self.fullname.connect("changed", self._name_changed)
        self.username.connect("changed", self._username_changed)
        self.hostname.connect("changed", lambda *_: setattr(self, "hostname_edited", self.hostname.has_focus())
                              or self.update_buttons())
        for widget in (self.password, self.password2):
            widget.connect("changed", lambda *_: self.update_buttons())
        self.zone = Gtk.ComboBoxText.new_with_entry()
        for zone in timezones():
            self.zone.append(zone, zone.replace("_", " "))
        if not self.zone.set_active_id(current_timezone()):
            self.zone.set_active_id("UTC")
        completion = Gtk.EntryCompletion(model=self.zone.get_model(), text_column=0, minimum_key_length=2)
        completion.set_match_func(lambda c, key, it, _d: key.lower() in c.get_model()[it][0].lower(), None)
        self.zone.get_child().set_completion(completion)
        self.autologin = Gtk.Switch(active=True, halign=Gtk.Align.START)
        rows = (("Full name", self.fullname), ("User name", self.username), ("Computer name", self.hostname),
                ("Password", self.password), ("Confirm password", self.password2), ("Time zone", self.zone),
                ("Log in automatically", self.autologin))
        for index, (label, widget) in enumerate(rows):
            grid.attach(Gtk.Label(label=label, xalign=1), 0, index, 1, 1)
            widget.set_hexpand(True)
            grid.attach(widget, 1, index, 1, 1)
        box.pack_start(grid, False, False, 0)
        self.account_hint = Gtk.Label(xalign=0, wrap=True)
        self.account_hint.get_style_context().add_class("keel-caption")
        box.pack_start(self.account_hint, False, False, 0)
        return box

    def _name_changed(self, entry):
        if not self.username_edited:
            first = (entry.get_text().strip().split() or [""])[0].lower()
            self.username.set_text(re.sub(r"[^a-z0-9_-]", "", first)[:31])
            self.username_edited = False
        self.update_buttons()

    def _username_changed(self, entry):
        if entry.has_focus():
            self.username_edited = True
        if not self.hostname_edited and entry.get_text():
            self.hostname.set_text(f"{entry.get_text()}-pc")
            self.hostname_edited = False
        self.update_buttons()

    def account_problem(self):
        user = self.username.get_text()
        if not keel_backend.USER_RE.match(user) or user in keel_backend.RESERVED:
            return "Pick a user name of lower-case letters and digits, starting with a letter."
        if not keel_backend.HOST_RE.match(self.hostname.get_text()):
            return "Pick a computer name of letters, digits and dashes."
        if len(self.password.get_text()) < 4:
            return "Pick a password of at least 4 characters."
        if self.password.get_text() != self.password2.get_text():
            return "The two passwords don't match yet."
        return None

    def confirm_page(self):
        box = page("Ready to install")
        self.summary = Gtk.Label(xalign=0, wrap=True, max_width_chars=70)
        box.pack_start(self.summary, False, False, 0)
        warning = Gtk.Label(label="Everything on this disk will be erased. This can't be undone.", xalign=0, wrap=True)
        warning.get_style_context().add_class("keel-warning")
        box.pack_start(warning, False, False, 0)
        return box

    def progress_page(self):
        box = page("Installing freemac")
        self.bar = Gtk.ProgressBar(show_text=True)
        box.pack_start(self.bar, False, False, 12)
        self.step = Gtk.Label(xalign=0, wrap=True)
        box.pack_start(self.step, False, False, 0)
        return box

    def done_page(self):
        box = page("freemac is installed")
        self.done_heading = box.get_children()[0]
        self.done_text = Gtk.Label(xalign=0, wrap=True, max_width_chars=70,
                                   label="Remove the USB stick or disc, then restart to start using freemac.")
        box.pack_start(self.done_text, False, False, 0)
        self.restart = Gtk.Button(label="Restart Now", halign=Gtk.Align.START)
        self.restart.get_style_context().add_class("suggested-action")
        self.restart.connect("clicked", lambda *_: subprocess.Popen(["systemctl", "reboot"]))
        box.pack_start(self.restart, False, False, 0)
        return box

    # Flow ---------------------------------------------------------------------
    def current(self):
        return self.pages[self.index]

    def go(self, step):
        name = self.current()
        if step > 0 and name == "confirm":
            self.start_install()
            return
        self.index = max(0, min(len(self.pages) - 1, self.index + step))
        if self.current() == "confirm":
            disk = self.disk_list.get_selected_row().disk
            self.summary.set_markup(
                f"Keel will erase <b>{GLib.markup_escape_text(disk['model'])}</b> "
                f"({human(disk['size'])}, {disk['path']}) and install freemac on it for "
                f"<b>{GLib.markup_escape_text(self.fullname.get_text() or self.username.get_text())}</b> "
                f"(user name {GLib.markup_escape_text(self.username.get_text())}).")
        self.stack.set_visible_child_name(self.current())
        self.update_buttons()

    def update_buttons(self):
        if not self.ready:
            return
        name = self.current()
        ok = True
        if name == "disk":
            ok = self.disk_list.get_selected_row() is not None
        elif name == "account":
            problem = self.account_problem()
            self.account_hint.set_text(problem or "")
            ok = problem is None
        self.next.set_sensitive(ok)
        self.next.set_label("Erase and Install" if name == "confirm" else "Continue")
        context = self.next.get_style_context()
        if name == "confirm":
            context.remove_class("suggested-action")
            context.add_class("destructive-action")
        else:
            context.remove_class("destructive-action")
            context.add_class("suggested-action")
        busy = name in ("progress", "done")
        self.next.set_visible(not busy)
        self.back.set_visible(not busy and self.index > 0)

    def start_install(self):
        request = {
            "disk": self.disk_list.get_selected_row().disk["path"],
            "fullname": self.fullname.get_text().strip(),
            "username": self.username.get_text(),
            "hostname": self.hostname.get_text(),
            "password": self.password.get_text(),
            "timezone": self.zone.get_active_id() or self.zone.get_child().get_text().replace(" ", "_") or "UTC",
            "autologin": self.autologin.get_active(),
        }
        self.index = self.pages.index("progress")
        self.stack.set_visible_child_name("progress")
        self.update_buttons()
        self.set_deletable(False)
        command = [BACKEND] if os.geteuid() == 0 else ["sudo", "-n", BACKEND]
        self.proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.proc.stdin.write(json.dumps(request))
        self.proc.stdin.close()
        GLib.io_add_watch(self.proc.stdout, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, self.on_output)

    def on_output(self, stream, condition):
        line = stream.readline()
        if not line:
            self.proc.wait()
            if self.current() == "progress":
                self.finish(False, "The installer stopped unexpectedly.")
            return False
        line = line.strip()
        if line.startswith("PROGRESS "):
            _tag, percent, message = line.split(" ", 2)
            self.bar.set_fraction(int(percent) / 100)
            self.bar.set_text(f"{percent}%")
            self.step.set_text(message)
        elif line == "DONE":
            self.finish(True)
        elif line.startswith("ERROR "):
            self.finish(False, line[6:])
        return True

    def finish(self, ok, error=None):
        self.set_deletable(True)
        self.index = self.pages.index("done")
        if not ok:
            self.done_text.set_text(f"freemac couldn't be installed: {error}\n\nNothing else on this computer was "
                                    "changed apart from the disk you chose.")
            self.restart.set_visible(False)
            self.done_heading.set_text("Installation didn\u2019t finish")
        self.stack.set_visible_child_name("done")
        self.update_buttons()


class KeelApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.freemac.Keel")

    def do_startup(self):
        Gtk.Application.do_startup(self)
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def do_activate(self):
        window = self.get_active_window() or Keel(self)
        window.show_all()
        window.present()


def main():
    import sys

    GLib.set_prgname("freemac-keel")
    sys.exit(KeelApp().run(sys.argv))
