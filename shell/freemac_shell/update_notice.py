# SPDX-License-Identifier: GPL-3.0-or-later
"""Software updates, noticed in the background, as on a Mac.

Beacon runs this. A minute after you log in it reads which updates the
computer already knows about, and once a day it asks the archive for new
ones (PackageKit refreshes its lists; an active desktop session may do that
without a password). The count shows as a red badge on Harbor's Dock icon,
and a notice says when updates are ready, once for each new set, not every
day. A click on the notice opens Harbor's Updates page. Harbor asks Beacon
to look again after it checks or installs, so the badge goes when they're in.
The live system doesn't look for them.

What was found is kept in ~/.local/state/freemac/updates.json.
Original freemac code.
"""
import json
import os
import threading
import time

import gi
from gi.repository import GLib

from . import launcher_badge

try:
    gi.require_version("PackageKitGlib", "1.0")
    from gi.repository import PackageKitGlib as PK  # noqa: E402
except (ImportError, ValueError):
    PK = None

HARBOR = "freemac-harbor.desktop"
STATE = os.path.join(GLib.get_user_state_dir(), "freemac", "updates.json")
FIRST_LOOK = 60          # seconds after login: the lists already on the computer
DAILY = 24 * 3600        # how often to ask the archive for new ones
WAKE = 15 * 60           # how often to see whether a day has gone by


def load():
    try:
        with open(STATE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(data):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, STATE)


def news(ids, told):
    """Whether the updates found include any the person hasn't been told about."""
    return bool(set(ids) - set(told or ()))


def summary(count):
    return "1 update is ready" if count == 1 else f"{count} updates are ready"


class Watch:
    """Looks for updates and calls tell(count) when there are new ones."""

    def __init__(self, tell):
        self.tell = tell
        self.busy = False
        self.state = load()
        # The live system isn't kept up to date, so it gets no badge or notice.
        self.live = os.path.isdir("/run/live/medium")
        if PK is None or self.live:
            return
        GLib.timeout_add_seconds(FIRST_LOOK, self._first)
        GLib.timeout_add_seconds(WAKE, self._wake)

    def _first(self):
        self.look(refresh=self._due())
        return False

    def _wake(self):
        if self._due():
            self.look(refresh=True)
        return True

    def _due(self):
        return time.time() - float(self.state.get("refreshed", 0)) >= DAILY

    def look(self, refresh=False):
        """Count the updates; refresh=True asks the archive first."""
        if PK is None or self.live or self.busy:
            return
        self.busy = True

        def work():
            ids, refreshed = None, False
            try:
                client = PK.Client()
                if refresh:
                    try:
                        client.refresh_cache(False, None, lambda *_: None, None)
                        refreshed = True
                    except GLib.Error:
                        pass   # offline, or not allowed: count what's already known
                res = client.get_updates(PK.filter_bitfield_from_string("none"), None,
                                         lambda *_: None, None)
                ids = sorted(p.get_id() for p in res.get_package_array())
            except GLib.Error:
                pass
            GLib.idle_add(self._found, ids, refreshed)

        threading.Thread(target=work, daemon=True).start()

    def _found(self, ids, refreshed):
        self.busy = False
        if ids is None:
            return False
        if refreshed:
            self.state["refreshed"] = time.time()
        told = self.state.get("told", [])
        self.state["ids"] = ids
        launcher_badge.set_count(HARBOR, len(ids), force=True)
        if ids and news(ids, told):
            self.tell(len(ids))
        # Remember only what's still waiting, so a later new set is news again.
        self.state["told"] = ids
        try:
            save(self.state)
        except OSError:
            pass
        return False
