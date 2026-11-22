# SPDX-License-Identifier: GPL-3.0-or-later
"""Keeping the computer awake while something needs it, as a Mac does: a
video that's playing keeps the screen on, and `caffeinate` keeps it on for
as long as you ask.

    caffeinate                     stay awake until Control-C
    caffeinate -t SECONDS          stay awake that long
    caffeinate -w PID              stay awake until that program ends
    caffeinate COMMAND [ARGS…]     run the command, awake until it's done

-d, -i, -m, -s and -u are taken, as on a Mac, and all mean the same here:
keep the screen on and don't count the computer as idle.

How it works: freemac-lock --watch (which runs the idle timers) also runs
the keep-awake service here. It answers the usual Linux way for apps to ask
for this, org.freedesktop.ScreenSaver's Inhibit and UnInhibit (web browsers,
video players and Reel use it), and org.freedesktop.PowerManagement's. While
anyone holds a request, Strata (strata/keep-awake) tells the compositor the
computer isn't idle: the screen doesn't turn off, and neither the screen
saver nor the lock comes. Closing the lid still sleeps, and still locks
first.

A request ends when it's taken back or when the program that made it ends,
whichever comes first, so a program that crashes can't keep the screen on.
Dials > Power lists what is keeping it awake (org.freemac.KeepAwake.List).
Original freemac code.
"""
import os
import signal
import subprocess
import sys
import time

from gi.repository import Gio, GLib

SCREENSAVER = "org.freedesktop.ScreenSaver"
POWER = "org.freedesktop.PowerManagement"
POWER_IFACE = "org.freedesktop.PowerManagement.Inhibit"
OWN = "org.freemac.KeepAwake"
OWN_PATH = "/org/freemac/KeepAwake"

XML = f"""
<node>
  <interface name="{SCREENSAVER}">
    <method name="Inhibit">
      <arg type="s" name="application_name" direction="in"/>
      <arg type="s" name="reason_for_inhibit" direction="in"/>
      <arg type="u" name="cookie" direction="out"/>
    </method>
    <method name="UnInhibit">
      <arg type="u" name="cookie" direction="in"/>
    </method>
    <method name="SimulateUserActivity"/>
    <method name="GetActive"><arg type="b" direction="out"/></method>
    <method name="GetActiveTime"><arg type="u" direction="out"/></method>
    <method name="GetSessionIdleTime"><arg type="u" direction="out"/></method>
    <method name="SetActive">
      <arg type="b" direction="in"/><arg type="b" direction="out"/>
    </method>
    <method name="Lock"/>
    <signal name="ActiveChanged"><arg type="b"/></signal>
  </interface>
  <interface name="{POWER_IFACE}">
    <method name="Inhibit">
      <arg type="s" name="application" direction="in"/>
      <arg type="s" name="reason" direction="in"/>
      <arg type="u" name="cookie" direction="out"/>
    </method>
    <method name="UnInhibit">
      <arg type="u" name="cookie" direction="in"/>
    </method>
    <method name="HasInhibit"><arg type="b" direction="out"/></method>
    <signal name="HasInhibitChanged"><arg type="b"/></signal>
  </interface>
  <interface name="{OWN}">
    <method name="List">
      <arg type="a(ss)" name="holds" direction="out"/>
    </method>
    <signal name="Changed"/>
  </interface>
</node>
"""


def friendly_name(application):
    """"org.freemac.Reel" or "/usr/bin/epiphany" as people would say it."""
    name = (application or "").strip()
    if not name:
        return "An app"
    name = os.path.basename(name.rstrip("/"))
    if "." in name and " " not in name:
        name = name.rsplit(".", 1)[-1]
    return name[:1].upper() + name[1:]


class Holds:
    """Who is keeping the computer awake: cookie -> (bus name, app, reason).
    Plain bookkeeping, so it can be tried without a bus."""

    def __init__(self):
        self.holds = {}
        self._next = 1

    def add(self, sender, application, reason):
        cookie = self._next
        self._next += 1
        self.holds[cookie] = (sender, application, reason)
        return cookie

    def remove(self, cookie, sender=None):
        """Only the program that asked can take its request back."""
        hold = self.holds.get(cookie)
        if hold and (sender is None or hold[0] == sender):
            del self.holds[cookie]
            return True
        return False

    def drop_sender(self, sender):
        gone = [cookie for cookie, hold in self.holds.items() if hold[0] == sender]
        for cookie in gone:
            del self.holds[cookie]
        return bool(gone)

    def senders(self):
        return {hold[0] for hold in self.holds.values()}

    def listing(self):
        """[(app, reason)], one line per app and reason."""
        seen = []
        for _sender, application, reason in self.holds.values():
            entry = (friendly_name(application), reason or "")
            if entry not in seen:
                seen.append(entry)
        return seen

    def __bool__(self):
        return bool(self.holds)


def tell_strata(on):
    """Ask the compositor to count the computer as busy (or not)."""
    try:
        from .wfipc import Connection
        reply = Connection().call("strata/keep-awake", on=bool(on))
        return reply.get("result") == "ok"
    except (OSError, ValueError, ConnectionError):
        return False


class Service:
    """org.freedesktop.ScreenSaver and PowerManagement's inhibit, for the session."""

    def __init__(self, tell=tell_strata):
        self.tell = tell
        self.holds = Holds()
        self.awake = None
        self.bus = None
        self.watches = {}
        self.owners = []
        self.info = Gio.DBusNodeInfo.new_for_xml(XML)
        # Whatever a crashed watcher left behind is no longer wanted.
        self._apply(force=True)

    def start(self):
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        except GLib.Error:
            return False
        ifaces = {i.name: i for i in self.info.interfaces}
        # Apps ask at either path; KDE's tools use /ScreenSaver.
        for path in ("/org/freedesktop/ScreenSaver", "/ScreenSaver"):
            self.bus.register_object(path, ifaces[SCREENSAVER], self._call, None, None)
        self.bus.register_object("/org/freedesktop/PowerManagement/Inhibit", ifaces[POWER_IFACE],
                                 self._call, None, None)
        self.bus.register_object(OWN_PATH, ifaces[OWN], self._call, None, None)
        for name in (SCREENSAVER, POWER, OWN):
            self.owners.append(Gio.bus_own_name_on_connection(
                self.bus, name, Gio.BusNameOwnerFlags.NONE, None, None))
        return True

    def stop(self):
        for owner in self.owners:
            Gio.bus_unown_name(owner)
        self.owners = []
        for watch in self.watches.values():
            Gio.bus_unwatch_name(watch)
        self.watches = {}
        self.holds = Holds()
        self._apply(force=True)

    def _apply(self, force=False):
        wanted = bool(self.holds)
        if force or wanted != self.awake:
            self.tell(wanted)
            changed = self.awake is not None and wanted != self.awake
            self.awake = wanted
            if changed and self.bus:
                self._emit(POWER_IFACE, "/org/freedesktop/PowerManagement/Inhibit", "HasInhibitChanged",
                           GLib.Variant("(b)", (wanted,)))
        if self.bus:
            self._emit(OWN, OWN_PATH, "Changed", None)

    def _emit(self, iface, path, name, args):
        try:
            self.bus.emit_signal(None, path, iface, name, args)
        except GLib.Error:
            pass

    def _watch(self, sender):
        if sender in self.watches:
            return
        self.watches[sender] = Gio.bus_watch_name_on_connection(
            self.bus, sender, Gio.BusNameWatcherFlags.NONE, None, self._vanished)

    def _vanished(self, _bus, sender):
        watch = self.watches.pop(sender, None)
        if watch is not None:
            Gio.bus_unwatch_name(watch)
        if self.holds.drop_sender(sender):
            self._apply()

    def _call(self, _bus, sender, _path, iface, method, params, invocation):
        if method == "Inhibit":
            application, reason = params.unpack()
            cookie = self.holds.add(sender, application, reason)
            self._watch(sender)
            self._apply()
            invocation.return_value(GLib.Variant("(u)", (cookie,)))
        elif method == "UnInhibit":
            (cookie,) = params.unpack()
            if self.holds.remove(cookie, sender):
                if sender not in self.holds.senders() and sender in self.watches:
                    Gio.bus_unwatch_name(self.watches.pop(sender))
                self._apply()
            invocation.return_value(None)
        elif method == "HasInhibit":
            invocation.return_value(GLib.Variant("(b)", (bool(self.holds),)))
        elif method == "List":
            invocation.return_value(GLib.Variant("(a(ss))", (self.holds.listing(),)))
        elif method == "GetActive":
            from . import saver
            invocation.return_value(GLib.Variant("(b)", (bool(saver.running_pid()),)))
        elif method in ("GetActiveTime", "GetSessionIdleTime"):
            invocation.return_value(GLib.Variant("(u)", (0,)))
        elif method == "SetActive":
            (active,) = params.unpack()
            if active:
                subprocess.Popen(["freemac-screensaver"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            invocation.return_value(GLib.Variant("(b)", (True,)))
        elif method == "Lock":
            subprocess.Popen(["freemac-lock"])
            invocation.return_value(None)
        elif method == "SimulateUserActivity":
            invocation.return_value(None)
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


def holds_now(timeout_ms=500):
    """[(app, reason)] keeping the computer awake now; [] if nothing (or
    the service isn't running)."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        reply = bus.call_sync(OWN, OWN_PATH, OWN, "List", None, GLib.VariantType("(a(ss))"),
                              Gio.DBusCallFlags.NONE, timeout_ms, None)
        return list(reply.unpack()[0])
    except GLib.Error:
        return []


class Request:
    """An app's own request to stay awake, for as long as it's held.
    Reel holds one while a video plays."""

    def __init__(self, application, reason):
        self.application = application
        self.reason = reason
        self.cookie = None
        self.bus = None

    def hold(self):
        if self.cookie is not None:
            return True
        try:
            self.bus = self.bus or Gio.bus_get_sync(Gio.BusType.SESSION, None)
            reply = self.bus.call_sync(SCREENSAVER, "/org/freedesktop/ScreenSaver", SCREENSAVER, "Inhibit",
                                       GLib.Variant("(ss)", (self.application, self.reason)),
                                       GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 1000, None)
            self.cookie = reply.unpack()[0]
            return True
        except GLib.Error:
            return False

    def release(self):
        if self.cookie is None:
            return
        cookie, self.cookie = self.cookie, None
        try:
            self.bus.call_sync(SCREENSAVER, "/org/freedesktop/ScreenSaver", SCREENSAVER, "UnInhibit",
                               GLib.Variant("(u)", (cookie,)), None, Gio.DBusCallFlags.NONE, 1000, None)
        except GLib.Error:
            pass

    def set(self, on):
        return self.hold() if on else self.release()


USAGE = __doc__.split("How it works")[0].strip()


def parse(args):
    """(seconds or None, pid or None, command list) from caffeinate's
    arguments; raises ValueError for ones it doesn't know."""
    seconds = pid = None
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            i += 1
            break
        if not arg.startswith("-") or arg == "-":
            break
        flags = arg[1:]
        for k, flag in enumerate(flags):
            if flag in "dimsu":
                continue
            if flag in "tw":
                rest = flags[k + 1:]
                if not rest:
                    i += 1
                    if i >= len(args):
                        raise ValueError(f"-{flag} needs a number")
                    rest = args[i]
                try:
                    number = int(rest)
                except ValueError:
                    raise ValueError(f"-{flag} needs a number, not {rest!r}") from None
                if number < 0:
                    raise ValueError(f"-{flag} needs a number of 0 or more")
                if flag == "t":
                    seconds = number
                else:
                    pid = number
                break
            raise ValueError(f"unknown option -{flag}")
        i += 1
    return seconds, pid, args[i:]


def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def caffeinate(args):
    if args in (["-h"], ["--help"]):
        print(USAGE)
        return 0
    try:
        seconds, pid, command = parse(args)
    except ValueError as error:
        print(f"caffeinate: {error}", file=sys.stderr)
        print("usage: caffeinate [-dimsu] [-t seconds] [-w pid] [command [args…]]", file=sys.stderr)
        return 64
    if command:
        what = f"Running \u201c{' '.join(command)}\u201d"
    elif pid is not None:
        what = f"Until process {pid} ends"
    elif seconds is not None:
        what = "For a set time"
    else:
        what = "Until it\u2019s stopped in Terminal"

    request = Request("caffeinate", what)
    if not request.hold():
        print("caffeinate: the keep-awake service isn't running (it starts with the desktop)", file=sys.stderr)
    # The request ends with this process, however it ends.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        if command:
            try:
                child = subprocess.Popen(command)
            except OSError as error:
                print(f"caffeinate: {command[0]}: {error.strerror}", file=sys.stderr)
                return 127
            return child.wait()
        deadline = time.monotonic() + seconds if seconds is not None else None
        while True:
            if deadline is not None and time.monotonic() >= deadline:
                return 0
            if pid is not None and not _alive(pid):
                return 0
            wait = 1.0 if pid is not None else 3600.0
            if deadline is not None:
                wait = min(wait, max(0.0, deadline - time.monotonic()))
            time.sleep(wait)
    except KeyboardInterrupt:
        return 130
    finally:
        request.release()


def main():
    return caffeinate(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
