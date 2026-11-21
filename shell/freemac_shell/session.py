# SPDX-License-Identifier: GPL-3.0-or-later
"""Restart, Shut Down and Log Out the way a Mac does them.

    freemac-power restart|shutdown|logout   ask first, then do it
    freemac-power sleep                     sleep at once
    freemac-power restart --now             don't ask

Asking shows "Are you sure you want to shut down your computer now?" and
counts down: if nobody answers, it goes ahead after 60 seconds. Then every
app is asked to quit, as its own Quit would, so each can offer to save what's
open. Only when they have all gone does the computer restart, shut down or
log out; an app that stays open stops it, and says which one. The freemac
menu, Dials > Battery and Power, and Shift-Command-Q use this.
Original freemac code.
"""
import fcntl
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

from . import alert, apps, style  # noqa: E402
from .wfipc import Wayfire  # noqa: E402

PROGRAM = "freemac-power"
COUNTDOWN = 60
# Seconds to wait once nothing has changed (no window has closed or opened)
# and no app is asking something, before saying an app didn't quit.
QUIET = 10
LONGEST = 300          # an app asking "Save changes?" is given this long
# Windows that aren't apps to quit: this program's own, the password prompt
# and the lock screen.
OWN = {PROGRAM, "polkit-mate-authentication-agent-1", "gtklock"}

WORDS = {
    # action: (question, what happens, button, the word for "it didn't")
    "restart": ("Are you sure you want to restart your computer now?",
                "If you do nothing, the computer will restart automatically in {n} seconds.",
                "Restart", "restart"),
    "shutdown": ("Are you sure you want to shut down your computer now?",
                 "If you do nothing, the computer will shut down automatically in {n} seconds.",
                 "Shut Down", "shut down"),
    "logout": ("Are you sure you want to quit all apps and log out now?",
               "If you do nothing, you will be logged out automatically in {n} seconds.",
               "Log Out", "log out"),
}
ICONS = {"restart": "system-reboot", "shutdown": "system-shutdown", "logout": "system-log-out"}


def _label_with_class(widget, name):
    if isinstance(widget, Gtk.Label) and widget.get_style_context().has_class(name):
        return widget
    if isinstance(widget, Gtk.Container):
        for child in widget.get_children():
            found = _label_with_class(child, name)
            if found is not None:
                return found
    return None


def ask(action, seconds=COUNTDOWN):
    """True if the person said yes, or didn't answer in time."""
    question, detail, button, _word = WORDS[action]
    dialog = alert.build(None, question, detail.format(n=seconds),
                         [("Cancel", Gtk.ResponseType.CANCEL), (button, Gtk.ResponseType.OK)],
                         default=Gtk.ResponseType.OK, icon=ICONS[action])
    dialog.set_keep_above(True)
    text = _label_with_class(dialog, "alert-text")
    left = [seconds]

    def tick():
        left[0] -= 1
        if left[0] <= 0:
            dialog.response(Gtk.ResponseType.OK)
            return False
        if text is not None:
            text.set_text(detail.format(n=left[0]))
        return True

    timer = GLib.timeout_add_seconds(1, tick)
    answer = dialog.run()
    if left[0] > 0:
        GLib.source_remove(timer)
    dialog.destroy()
    return answer == Gtk.ResponseType.OK


def _asking(view):
    """A window opened by another one, such as "Save changes?"."""
    return view.get("parent", -1) not in (-1, 0, None)


def app_windows(wf):
    return [v for v in wf.views() if (v.get("app-id") or "").lower() not in OWN]


def quit_apps(wf, now=GLib.get_monotonic_time):
    """Ask every app to quit and wait while they do. Returns [] when they
    have all gone, or the windows still open when one didn't."""
    windows = app_windows(wf)
    for view in windows:
        wf.close(view["id"])
    start = changed = now()
    seen = {v["id"] for v in windows}
    context = GLib.MainContext.default()
    while True:
        windows = app_windows(wf)
        if not windows:
            return []
        ids = {v["id"] for v in windows}
        if ids != seen:
            # A window closed, or an app opened one to ask about its unsaved
            # work. Each app is asked once: Cancel there means it stays open.
            seen, changed = ids, now()
        asking = any(_asking(v) for v in windows)
        waited = (now() - changed) / 1e6
        if (not asking and waited > QUIET) or (now() - start) / 1e6 > LONGEST:
            return windows
        # Keep the screen drawn (and any prompt answered) while waiting.
        deadline = now() + 500000
        while now() < deadline:
            while context.pending():
                context.iteration(False)
            GLib.usleep(50000)


def stopped(action, windows):
    """Tell the person which app kept the computer from going on."""
    word = WORDS[action][3]
    names = []
    for view in windows:
        name = apps.display_name(view.get("app-id") or "", view.get("title", ""))
        if name not in names:
            names.append(name)
    what = "logging out" if action == "logout" else ("restarting" if action == "restart" else "shutting down")
    title = f"“{names[0]}” stopped the computer from {what}." if names else f"The computer didn't {word}."
    alert.ask(None, title, "Save or close what's open in it, then try again.", icon=ICONS[action])


def finish(action):
    if action == "logout":
        subprocess.run(["pkill", "-u", str(os.getuid()), "-x", "wayfire"], check=False)
    else:
        subprocess.run(["systemctl", {"restart": "reboot", "shutdown": "poweroff"}[action]], check=False)


def run(action, confirm=True):
    if action == "sleep":
        subprocess.run(["systemctl", "suspend"], check=False)
        return 0
    if action not in WORDS:
        print(f"usage: {PROGRAM} restart|shutdown|logout|sleep [--now]", file=sys.stderr)
        return 2
    if confirm and not ask(action):
        return 1
    try:
        wf = Wayfire()
    except (ConnectionError, OSError):
        wf = None
    if wf is not None:
        left = quit_apps(wf)
        if left:
            stopped(action, left)
            return 1
    finish(action)
    return 0


def _only_one():
    """One question at a time: choosing Shut Down twice asks once."""
    path = os.path.join(GLib.get_user_runtime_dir(), PROGRAM + ".lock")
    try:
        handle = open(path, "w")
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return None
    return handle


def main():
    GLib.set_prgname(PROGRAM)
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    confirm = "--now" not in sys.argv[1:]
    if not args:
        print(f"usage: {PROGRAM} restart|shutdown|logout|sleep [--now]", file=sys.stderr)
        sys.exit(2)
    if args[0] != "sleep":
        lock = _only_one()
        if lock is None:
            sys.exit(0)
        Gtk.init(None)
        style.apply()
    sys.exit(run(args[0], confirm))


if __name__ == "__main__":
    main()
