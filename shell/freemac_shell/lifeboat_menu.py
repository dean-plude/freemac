# SPDX-License-Identifier: GPL-3.0-or-later
"""Lifeboat in the menu bar, as a Mac shows its backups there: once a backup
drive is chosen, a lifebuoy sits in the menu bar. Its menu says when the
latest backup was made, or how far the one under way has got, with Back Up
Now or Skip This Backup, Browse Lifeboat Backups and Lifeboat Settings….
It follows Lifeboat's status file and settings as they change rather than
asking every few seconds. Original freemac code.
"""
import os
import time

from gi.repository import Gio, GLib

from . import backup_store as store  # noqa: E402
from .lifeboat import chosen_drive  # noqa: E402
from .menubar_popup import Popup  # noqa: E402
from .status import StatusButton, launch  # noqa: E402

ICON = "freemac-lifeboat-symbolic"


def alive(pid):
    """Whether the Lifeboat that wrote the status is still running."""
    try:
        os.kill(int(pid), 0)
        return True
    except (TypeError, ValueError, ProcessLookupError):
        return False
    except PermissionError:
        return True


def latest_words(when, now=None):
    now = now or time.time()
    gap = max(0, now - when)
    if gap < 90:
        return "Just now"
    if gap < 3600:
        minutes = int(gap // 60)
        return "1 minute ago" if minutes == 1 else f"{minutes} minutes ago"
    return store.describe(when, now)


def describe(settings, status, plugged, backups=(), now=None):
    """What the menu says: (state, lines). state is "none" when no drive is
    chosen (no icon), else "busy", "error" or "idle". plugged says whether
    the drive is plugged in; backups are its backups' times, oldest first."""
    if not settings.get("drive"):
        return "none", []
    busy = status.get("state") == "backing-up" and alive(status.get("pid"))
    name = settings.get("name") or "the backup drive"
    if busy:
        files, copied = status.get("files", 0), status.get("bytes", 0)
        lines = ["Backing up…"]
        if files:
            lines.append(f"{files:,} files looked at, {store.size_words(copied)} copied")
        return "busy", lines
    last = (backups[-1] if backups else None) or status.get("last_ok")
    lines = [f"Latest backup: {latest_words(last, now)}" if last else "No backups yet"]
    if status.get("state") == "error" and status.get("error"):
        # Lifeboat's own words, such as "The backup drive is full."
        reason = status["error"] if len(status["error"]) < 50 else ""
        lines.append(f"The last backup didn't finish. {reason}".strip())
        state = "error"
    else:
        state = "idle"
    if not plugged:
        lines.append(f"Plug in “{name}” to back up")
    elif not settings.get("auto", True):
        lines.append("Backs up when you click Back Up Now")
    return state, lines


class LifeboatMenu(StatusButton):
    def __init__(self):
        super().__init__()
        self.popup = Popup("freemac-lifeboat-menu")
        self.state, self.lines = "none", []
        self.pending = None
        self.connect("clicked", lambda *_: self._clicked())
        # Lifeboat rewrites its status as it works (every few hundred files):
        # a quarter of a second's rest folds those into one look.
        self.monitors = []
        self.plugged = False
        # Plugging the drive in or ejecting it changes what the menu offers.
        self.volumes = Gio.VolumeMonitor.get()
        for signal in ("mount-added", "mount-removed"):
            self.volumes.connect(signal, lambda *_: self._changed())
        for path in (store.status_path(), store.settings_path()):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            monitor = Gio.File.new_for_path(path).monitor_file(Gio.FileMonitorFlags.NONE, None)
            monitor.connect("changed", lambda *_: self._changed())
            self.monitors.append(monitor)
        # "Just now" turns into "3 minutes ago" with nothing written.
        GLib.timeout_add_seconds(60, self._minute)
        self.update()

    def _minute(self):
        self.update()
        return True

    def _changed(self):
        if self.pending is None:
            self.pending = GLib.timeout_add(250, self._settle)

    def _settle(self):
        self.pending = None
        self.update()
        return False

    def update(self):
        settings, status = store.settings(), store.status()
        found = chosen_drive() if settings.get("drive") else None
        self.plugged = found is not None
        backups = []
        if found is not None and status.get("state") != "backing-up":
            try:
                backups = [when for when, *_rest in store.backups(found[1])]
            except OSError:
                pass
        state, lines = describe(settings, status, self.plugged, backups)
        changed = (state, lines) != (self.state, self.lines)
        self.state, self.lines = state, lines
        if state == "none":
            self.shown = None
            self.popup.hide()
            self.hide()
            return
        tip = {"busy": "Lifeboat is backing up", "error": "Lifeboat: the last backup didn't finish"}
        self.show_icon(ICON, tip.get(state, "Lifeboat"))
        self.get_style_context().remove_class("lifeboat-busy")
        if state == "busy":
            self.get_style_context().add_class("lifeboat-busy")
        if changed and self.popup.visible():
            self.fill()

    def _clicked(self):
        if self.popup.visible():
            self.popup.hide()
            return
        self.update()
        if self.state == "none":
            return
        self.fill()
        self.popup.show_under(self)

    def fill(self):
        p = self.popup
        p.clear()
        p.title("Lifeboat")
        for line in self.lines:
            p.note(line)
        p.separator()
        if self.state == "busy":
            p.item("Skip This Backup", lambda: launch("freemac-lifeboat", "--stop"))
        elif self.plugged:
            p.item("Back Up Now", lambda: launch("freemac-lifeboat", "--now"))
        p.item("Browse Lifeboat Backups", lambda: launch("freemac-lifeboat"))
        p.separator()
        p.item("Lifeboat Settings…", lambda: launch("freemac-dials", "--panel", "lifeboat"))
        p.menu.show_all()
