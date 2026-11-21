# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Lifeboat: choose the backup drive, see how backups are going,
back up now, and erase a drive that can't hold backups.

Lifeboat's watcher (lifeboat.py, started at login) does the backing up;
this page writes the settings it reads and shows the status file it
writes, read again every two seconds while the page is open.
"""
import os
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, volumes  # noqa: E402
from . import backup_store as store  # noqa: E402
from .lifeboat import chosen_drive, drive_id  # noqa: E402

NONE = "none"


def _run(*cmd):
    try:
        Gio.Subprocess.new(list(cmd), Gio.SubprocessFlags.NONE)
    except GLib.Error:
        pass


def _ago(when, now=None):
    now = now or time.time()
    gap = max(0, now - when)
    if gap < 90:
        return "Just now"
    if gap < 3600:
        return f"{int(gap // 60)} minutes ago"
    return store.describe(when, now)


class BackupPanel(Gtk.Box):
    def __init__(self, window, page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        group, row, _page, _slider, switch = window.helpers
        self.window = window
        settings = store.settings()

        self.drive = Gtk.ComboBoxText()
        self.drive.set_size_request(220, -1)
        self.drive_handler = self.drive.connect("changed", self._drive_chosen)
        self.auto = switch(bool(settings.get("auto", True)), lambda on: store.save_settings(auto=on))
        choose = group(row("Backup drive", self.drive,
                           "Your home folder is copied to it every hour while it's plugged in. "
                           "Earlier backups are kept, and files that haven't changed take no more room."),
                       row("Back up automatically", self.auto))

        self.latest = Gtk.Label(xalign=1)
        self.oldest = Gtk.Label(xalign=1)
        self.next = Gtk.Label(xalign=1)
        self.room = Gtk.Label(xalign=1)
        for label in (self.latest, self.oldest, self.next, self.room):
            label.get_style_context().add_class("dim-label")
        self.state_row = row("Latest backup", self.latest)
        facts = group(self.state_row, row("Oldest backup", self.oldest), row("Next backup", self.next),
                      row("Free on the drive", self.room))

        self.progress = Gtk.ProgressBar(show_text=True)
        self.progress.set_no_show_all(True)
        self.progress.set_ellipsize(3)

        self.warning = Gtk.Label(xalign=0, wrap=True)
        self.warning.set_no_show_all(True)
        self.warning.get_style_context().add_class("dials-caption")

        buttons = Gtk.Box(spacing=8)
        self.now_button = Gtk.Button(label="Back Up Now")
        self.now_button.connect("clicked", lambda _b: self._now())
        self.stop_button = Gtk.Button(label="Stop Backup")
        self.stop_button.set_no_show_all(True)
        self.stop_button.connect("clicked", lambda _b: _run("freemac-lifeboat", "--stop"))
        self.erase_button = Gtk.Button(label="Erase Drive…")
        self.erase_button.get_style_context().add_class("destructive-action")
        self.erase_button.set_no_show_all(True)
        self.erase_button.connect("clicked", lambda _b: self._erase())
        browse = Gtk.Button(label="Browse Backups…")
        browse.connect("clicked", lambda _b: _run("freemac-lifeboat"))
        for button in (self.now_button, self.stop_button, self.erase_button):
            buttons.pack_start(button, False, False, 0)
        buttons.pack_end(browse, False, False, 0)

        self.pack_start(page("Lifeboat", choose, facts, self.progress, self.warning, buttons), True, True, 0)
        self.handlers = volumes.watch(self._fill_drives)
        self.connect("destroy", self._gone)
        self._fill_drives()
        self.timer = GLib.timeout_add_seconds(2, self._tick)
        self._tick()

    def _gone(self, _w):
        for handler in self.handlers:
            volumes.monitor().disconnect(handler)
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = None

    def _fill_drives(self):
        settings = store.settings()
        self.drive.handler_block(self.drive_handler)
        self.drive.remove_all()
        self.drive.append(NONE, "None")
        self.mounts = {}
        for mount in volumes.drives():
            path = volumes.path_of(mount)
            if not path:
                continue
            key = drive_id(mount)
            self.mounts[key] = mount
            self.drive.append(key, mount.get_name())
        wanted = settings.get("drive")
        if wanted and wanted not in self.mounts:
            self.drive.append(wanted, f"{settings.get('name') or 'Backup drive'} (not plugged in)")
        self.drive.set_active_id(wanted or NONE)
        self.drive.handler_unblock(self.drive_handler)
        self._check_drive()

    def _drive_chosen(self, combo):
        key = combo.get_active_id()
        if key == NONE or key is None:
            store.save_settings(drive=None, name="")
        else:
            mount = self.mounts.get(key)
            if mount is None:
                return
            store.save_settings(drive=key, name=mount.get_name())
            store.save_status(last_ok=None, error=None)
            if self._check_drive():
                _run("freemac-lifeboat", "--watch")   # started at login; this makes sure
        self._tick()

    def _check_drive(self):
        """Show the erase offer when the chosen drive can't hold backups."""
        found = chosen_drive()
        ok = found is None or store.can_link(found[1])
        self.erase_button.set_visible(not ok)
        self.warning.set_visible(not ok)
        if not ok:
            self.warning.set_text(f"“{found[0].get_name()}” can't hold backups the way it's formatted "
                                  "(as most USB drives come). Erase it for Lifeboat to use it: "
                                  "everything on it is deleted.")
        self.now_button.set_sensitive(found is not None and ok)
        return ok

    def _now(self):
        _run("freemac-lifeboat", "--now")
        GLib.timeout_add(500, self._tick)

    def _tick(self):
        if self.timer is None and not self.get_mapped() and self.get_parent() is None:
            return False
        settings = store.settings()
        status = store.status()
        found = chosen_drive()
        busy = status.get("state") == "backing-up"
        if found is not None and not busy:
            everything = store.backups(found[1])
        else:
            everything = []
        last = (everything[-1][0] if everything else None) or status.get("last_ok")
        if busy:
            self.latest.set_text("Backing up now…")
        elif status.get("state") == "error" and status.get("error"):
            self.latest.set_text(status["error"])
        else:
            self.latest.set_text(_ago(last) if last else "None yet")
        oldest = everything[0][0] if everything else status.get("oldest")
        self.oldest.set_text(store.describe(oldest) if oldest else "None yet")
        if not settings.get("drive"):
            self.next.set_text("Choose a drive")
        elif found is None:
            self.next.set_text("When the drive is plugged in")
        elif busy:
            self.next.set_text("—")
        elif not settings.get("auto", True):
            self.next.set_text("When you click Back Up Now")
        elif last:
            due = last + store.EVERY
            self.next.set_text("In a minute" if due - time.time() < 90 else
                               time.strftime("%I:%M %p", time.localtime(due)).lstrip("0"))
        else:
            self.next.set_text("In a minute")
        self.room.set_text(store.size_words(store.free(found[1])) if found else "—")
        self.progress.set_visible(busy)
        if busy:
            self.progress.pulse()
            files, copied = status.get("files", 0), status.get("bytes", 0)
            self.progress.set_text(f"{files:,} files looked at, {store.size_words(copied)} copied"
                                   + (f": {os.path.basename(status.get('current') or '')}"
                                      if status.get("current") else ""))
        self.stop_button.set_visible(busy)
        self.now_button.set_visible(not busy)
        return True

    # -- erasing a drive for backups --

    def _erase(self):
        found = chosen_drive()
        if found is None:
            return
        mount = found[0]
        volume = mount.get_volume()
        device = volume.get_identifier("unix-device") if volume else None
        if not device:
            alert.tell(self.get_toplevel(), "This drive can't be erased here.")
            return
        answer = alert.ask(self.get_toplevel(), f"Erase “{mount.get_name()}” for Lifeboat?",
                           "Everything on it is deleted, for good. It's then ready for backups, "
                           "and freemac can still read and write it.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Erase", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        self.erase_button.set_sensitive(False)
        self.warning.set_text("Erasing…")
        name = "Lifeboat"
        obj = "/org/freedesktop/UDisks2/block_devices/" + os.path.basename(device)
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

        def call(interface, method, args, then):
            bus.call("org.freedesktop.UDisks2", obj, interface, method, args, None,
                     Gio.DBusCallFlags.NONE, 15 * 60 * 1000, None, then, None)

        def failed(error):
            self.erase_button.set_sensitive(True)
            self.warning.set_text("The drive wasn't erased.")
            if not error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED) and \
                    "dismissed" not in error.message.lower() and "not authorized" not in error.message.lower():
                alert.tell(self.get_toplevel(), "The drive wasn't erased.", Gio.DBusError.strip_remote_error(error))

        def mounted(source, result, _data):
            try:
                source.call_finish(result)
            except GLib.Error:
                pass
            self.erase_button.set_sensitive(True)
            GLib.timeout_add(1500, self._after_erase)

        def formatted(source, result, _data):
            try:
                source.call_finish(result)
            except GLib.Error as error:
                failed(error)
                return
            call("org.freedesktop.UDisks2.Filesystem", "Mount", GLib.Variant("(a{sv})", ({},)), mounted)

        def unmounted(source, result, _data):
            try:
                source.call_finish(result)
            except GLib.Error as error:
                failed(error)
                return
            options = {"label": GLib.Variant("s", name), "take-ownership": GLib.Variant("b", True),
                       "update-partition-type": GLib.Variant("b", True)}
            call("org.freedesktop.UDisks2.Block", "Format", GLib.Variant("(sa{sv})", ("ext4", options)), formatted)

        call("org.freedesktop.UDisks2.Filesystem", "Unmount", GLib.Variant("(a{sv})", ({},)), unmounted)

    def _after_erase(self):
        # The drive comes back with a new uuid: choose it again.
        for mount in volumes.drives():
            if mount.get_name() == "Lifeboat":
                store.save_settings(drive=drive_id(mount), name=mount.get_name())
                break
        self._fill_drives()
        if chosen_drive() is not None and self._check_drive():
            self.warning.set_visible(False)
            _run("freemac-lifeboat", "--now")
        return False
