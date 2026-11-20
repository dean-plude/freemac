# SPDX-License-Identifier: GPL-3.0-or-later
"""freemac-sync: keeps online accounts in step in the background.

Runs from the session's start. Syncs every account every 15 minutes, a few
seconds after Tide, Crew or Nudge saves a change, and whenever
`freemac-sync` is run again (Dials' Sync Now does that). The work itself is
in dav_sync.py. Original freemac code.
"""
import os
import sys
import threading

from gi.repository import Gio, GLib  # noqa: E402

from . import calendar_store, contacts_store, dav_sync, reminders_store  # noqa: E402

APP_ID = "org.freemac.Sync"
EVERY = 15 * 60       # seconds between syncs
SETTLE = 4            # seconds after a save before syncing it
OWN_WRITES = 3_000_000  # µs after our own sync in which changes are ours


class SyncService(Gio.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.running = False
        self.again = False
        self.finished_at = 0
        self.pending = None
        self.monitors = []

    def do_startup(self):
        Gio.Application.do_startup(self)
        self.hold()
        for path, folder in ((calendar_store.store_path(), False), (contacts_store.store_dir(), True),
                             (reminders_store.store_dir(), True),
                             (os.path.dirname(dav_sync.accounts_path()), True)):
            directory = path if folder else os.path.dirname(path)
            os.makedirs(directory, exist_ok=True)
            handle = Gio.File.new_for_path(path)
            monitor = handle.monitor_directory(Gio.FileMonitorFlags.NONE, None) if folder else \
                handle.monitor_file(Gio.FileMonitorFlags.NONE, None)
            monitor.connect("changed", self._changed, path)
            self.monitors.append(monitor)
        GLib.timeout_add_seconds(EVERY, self._tick)
        GLib.timeout_add_seconds(20, lambda: self.sync() or False)   # once the session has settled

    def do_activate(self):
        self.sync()

    def _tick(self):
        self.sync()
        return True

    def _changed(self, _monitor, changed, _other, kind, path):
        if kind not in (Gio.FileMonitorEvent.CHANGES_DONE_HINT, Gio.FileMonitorEvent.DELETED,
                        Gio.FileMonitorEvent.CREATED, Gio.FileMonitorEvent.MOVED_IN,
                        Gio.FileMonitorEvent.RENAMED):
            return
        name = changed.get_basename() or ""
        if name.endswith(".new"):
            return
        if path == os.path.dirname(dav_sync.accounts_path()) and name != os.path.basename(dav_sync.accounts_path()):
            return
        if self.running or GLib.get_monotonic_time() - self.finished_at < OWN_WRITES:
            return   # our own writes (Dials runs freemac-sync itself after a change)
        if self.pending:
            GLib.source_remove(self.pending)
        self.pending = GLib.timeout_add_seconds(SETTLE, self._settled)

    def _settled(self):
        self.pending = None
        self.sync()
        return False

    def sync(self):
        if not dav_sync.load_accounts():
            return
        if self.running:
            self.again = True
            return
        self.running = True
        threading.Thread(target=self._work, daemon=True).start()

    def _work(self):
        try:
            dav_sync.sync_all()
        except Exception as error:   # a bug must not stop later syncs
            print("freemac-sync:", error, file=sys.stderr)
        GLib.idle_add(self._done)

    def _done(self):
        self.running = False
        self.finished_at = GLib.get_monotonic_time()
        if self.again:
            self.again = False
            self.sync()
        return False


def main(argv=None):
    return SyncService().run(argv or sys.argv)


if __name__ == "__main__":
    sys.exit(main())
