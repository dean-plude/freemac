# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Software Update, as on a Mac.

The top part is freemac itself: which version this is, and when a newer one
is out, what's new in it and Update Now, which downloads it (after an
administrator's password) while you carry on working; then Restart Now,
and it installs while the computer restarts (freemac_update.py). Opening the
page looks for a new version if it hasn't looked in the last hour.

Below are the apps and the rest of the system, from Ubuntu or Debian: a
button to Harbor's Updates page, and a switch that installs important
(security) updates by themselves through unattended-upgrades.
Original freemac code.
"""
import os
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import admin_switch, freemac_update, style, update_notice  # noqa: E402

LOOK_AGAIN = 3600     # opening the page looks again after an hour


def _when(t):
    h24 = style.prefs().get("clock") == "24"
    clock = time.strftime("%H:%M" if h24 else "%-I:%M %p", time.localtime(t))
    days = (time.localtime().tm_yday - time.localtime(t).tm_yday) % 366
    if days == 0:
        return f"today at {clock}"
    if days == 1:
        return f"yesterday at {clock}"
    return time.strftime("%-d %B", time.localtime(t))


class FreemacPart(Gtk.Box):
    """The freemac row, redrawn as its state changes."""

    def __init__(self, window):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.window = window
        self.state = None        # None, "checking", "downloading" or "error"
        self.error = None
        self.download = None
        self.done = self.total = 0
        self.draw()
        if freemac_update.available() and not freemac_update.pending():
            if time.time() - float(freemac_update.cached().get("checked", 0)) > LOOK_AGAIN:
                GLib.idle_add(self.check_now)

    # -- what to show --------------------------------------------------------
    def draw(self):
        for child in self.get_children():
            self.remove(child)
        group, row, _page, _slider, _switch = self.window.helpers
        rows = self.rows(row)
        self.pack_start(group(*rows), False, False, 0)
        notes = self.notes()
        if notes:
            self.pack_start(notes, False, False, 0)
        self.show_all()

    def _button(self, label, action, suggested=False):
        button = Gtk.Button(label=label)
        if suggested:
            button.get_style_context().add_class("suggested-action")
        button.connect("clicked", lambda *_: action())
        return button

    def rows(self, row):
        here = freemac_update.current()
        if freemac_update.live():
            return [row(f"freemac {here}", None,
                        "This is freemac running from its USB stick. Install freemac on the computer "
                        "to get new versions here.")]
        if not freemac_update.available():
            return [row(f"freemac {here}", None,
                        "New versions of freemac are on its Releases page.")]
        waiting = freemac_update.pending()
        if waiting:
            return [row(f"freemac {waiting} is ready to install",
                        self._button("Restart Now", self.restart, suggested=True),
                        "The computer restarts to install it, which takes a minute or two. "
                        "Save your work in open apps first.")]
        offer = freemac_update.offer()
        if self.state == "downloading" and offer:
            bar = Gtk.ProgressBar(fraction=self.done / self.total if self.total else 0)
            bar.set_size_request(200, -1)
            words = (f"{freemac_update.size_text(self.done)} of {freemac_update.size_text(self.total)}"
                     if self.total else "Starting…")
            if self.total and self.done >= self.total:
                words = "Checking the download…"
            return [row(f"Downloading freemac {offer['version']}…", bar, words)]
        if offer:
            size = offer.get("size") or 0
            caption = "A new version of freemac is ready to download"
            caption += f" ({freemac_update.size_text(size)})." if size else "."
            if self.state == "error" and self.error:
                caption = self.error
            return [row(f"freemac {offer['version']} is available",
                        self._button("Update Now", self.update_now, suggested=True), caption)]
        if self.state == "checking":
            spinner = Gtk.Spinner(active=True)
            return [row(f"freemac {here}", spinner, "Checking for a new version…")]
        if self.state == "error" and self.error:
            return [row(f"freemac {here}", self._button("Try Again", self.check_now), self.error)]
        checked = freemac_update.cached().get("checked")
        caption = (f"freemac is up to date. Last checked {_when(float(checked))}." if checked
                   else "Click Check Now to look for a new version of freemac.")
        done = freemac_update.result()
        if done and done.get("ok") and not done.get("undone") and done.get("to") == here \
                and time.time() - float(done.get("time", 0)) < 7 * 86400:
            caption = f"Updated from {done.get('from')} {_when(float(done['time']))}. " + caption
        return [row(f"freemac {here}", self._button("Check Now", self.check_now), caption)]

    def notes(self):
        """What's new in the version on offer or waiting."""
        offer = freemac_update.offer()
        done = freemac_update.result()
        if freemac_update.pending():
            items = freemac_update.pending_whats_new()
        elif offer:
            items = offer.get("whats_new") if self.state != "downloading" else []
        elif done and done.get("ok") and not done.get("undone") and done.get("to") == freemac_update.current() \
                and time.time() - float(done.get("time", 0)) < 7 * 86400:
            items = done.get("whats_new") or []      # just installed
        else:
            items = []
        if not items:
            return None
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.get_style_context().add_class("update-notes")
        title = Gtk.Label(label="What’s New", xalign=0)
        title.get_style_context().add_class("update-notes-title")
        box.pack_start(title, False, False, 0)
        for item in items[:6]:
            line = Gtk.Label(label="•  " + item, xalign=0, wrap=True, max_width_chars=70)
            line.get_style_context().add_class("dials-caption")
            box.pack_start(line, False, False, 0)
        if len(items) > 6:
            more = Gtk.Label(label=f"and {len(items) - 6} more", xalign=0)
            more.get_style_context().add_class("dials-caption")
            box.pack_start(more, False, False, 0)
        return box

    # -- what the buttons do -------------------------------------------------------
    def check_now(self):
        if self.state in ("checking", "downloading"):
            return False
        self.state, self.error = "checking", None
        self.draw()

        def work():
            try:
                freemac_update.check()
                error = None
            except freemac_update.helper().Failed as problem:
                error = str(problem)
            GLib.idle_add(self._checked, error)
        threading.Thread(target=work, daemon=True).start()
        return False

    def _checked(self, error):
        self.state, self.error = ("error", error) if error else (None, None)
        self.draw()
        self.window._show_update_count()
        return False

    def update_now(self):
        offer = freemac_update.offer()
        if not offer or self.state == "downloading":
            return
        self.state, self.error = "downloading", None
        self.done, self.total = 0, 0     # 0 until the helper says how big it is
        self.draw()
        self.download = freemac_update.Download(offer["version"], self._progress, self._checking, self._downloaded)

    def _progress(self, done, total):
        self.done, self.total = done, total or int((freemac_update.offer() or {}).get("size") or 0)
        self.draw()

    def _checking(self):
        self.done = self.total
        self.draw()

    def _downloaded(self, ok, words):
        self.download = None
        self.state, self.error = (None, None) if ok or not words else ("error", words)
        self.draw()
        self.window._show_update_count()

    def restart(self):
        freemac_update.restart()


def software_update_page(window):
    group, row, page, _slider, _switch = window.helpers
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(window.get_screen(), provider,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    count = len(update_notice.load().get("ids") or [])
    check = Gtk.Button(label="Update Now…" if count else "Check for Updates…")

    def open_updates(_button):
        try:
            Gio.Subprocess.new(["freemac-harbor", "--updates"], Gio.SubprocessFlags.NONE)
        except GLib.Error:
            pass
    check.connect("clicked", open_updates)
    if count:
        caption = update_notice.summary(count) + ". Harbor shows what they are and installs them."
    else:
        caption = ("Apps and the rest of the system get updates from "
                   f"{'Ubuntu' if freemac_update.helper().base() == 'ubuntu' else 'Debian'}. freemac "
                   "looks for them once a day and tells you when some are ready.")
    rows = [row("App and System Updates", check, caption)]
    if os.path.exists("/usr/bin/unattended-upgrade") and os.path.exists(admin_switch.SYSTEM_HELPER):
        rows.append(row("Install important updates automatically", admin_switch.auto_updates_switch(),
                        "Security fixes are installed in the background, so the computer stays safe "
                        "without you doing anything. Other updates still wait for you in Harbor."))
    return page("Software Update", FreemacPart(window), group(*rows))


CSS = b"""
.update-notes { padding: 2px 14px 4px 14px; }
.update-notes-title { font-weight: bold; }
"""
