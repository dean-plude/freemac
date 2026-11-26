#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A stand-in for xdg-desktop-portal's ScreenCast interface, for Ferry's
Wayland capture test (freemac 1.240, Ferry 0.64.0; portal_test.sh).

    fake_portal.py LOG --monitor NODE --window NODE --size WxH [--answers A,B,...]

It owns org.freedesktop.portal.Desktop on the session bus and answers as
the portal does: ScreenCast version 5, monitors and windows, the pointer
hidden, drawn in or as metadata; each of CreateSession, SelectSources and
Start returns a Request whose Response signal follows. Start is the dialog:
the answers are taken in turn (ok, or cancel for the user saying no; ok
once they run out); an ok gives the monitor's node (with --size as its
size, at 0,0) or, for a window, the window's node, and a restore token
"token-N". OpenPipeWireRemote hands back a connection to the PipeWire
daemon in $XDG_RUNTIME_DIR. Each call is written to LOG with the options
the test checks, one line each.
"""
import argparse
import os
import socket
import sys

from gi.repository import Gio, GLib

IFACES = """
<node>
  <interface name="org.freedesktop.portal.ScreenCast">
    <method name="CreateSession">
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="SelectSources">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="Start">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="OpenPipeWireRemote">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="h" name="fd" direction="out"/>
    </method>
    <property name="AvailableSourceTypes" type="u" access="read"/>
    <property name="AvailableCursorModes" type="u" access="read"/>
    <property name="version" type="u" access="read"/>
  </interface>
</node>
"""
REQUEST = """
<node>
  <interface name="org.freedesktop.portal.Request">
    <method name="Close"/>
    <signal name="Response">
      <arg type="u" name="response"/>
      <arg type="a{sv}" name="results"/>
    </signal>
  </interface>
</node>
"""
SESSION = """
<node>
  <interface name="org.freedesktop.portal.Session">
    <method name="Close"/>
    <signal name="Closed">
      <arg type="a{sv}" name="details"/>
    </signal>
    <property name="version" type="u" access="read"/>
  </interface>
</node>
"""
BASE = "/org/freedesktop/portal/desktop"


class Portal:
    def __init__(self, bus, args):
        self.bus = bus
        self.args = args
        self.answers = [a for a in (args.answers or "").split(",") if a]
        self.tokens = 0
        self.sessions = {}
        self.log = open(args.log, "a", buffering=1)
        self.request_info = Gio.DBusNodeInfo.new_for_xml(REQUEST).interfaces[0]
        self.session_info = Gio.DBusNodeInfo.new_for_xml(SESSION).interfaces[0]
        info = Gio.DBusNodeInfo.new_for_xml(IFACES).interfaces[0]
        bus.register_object(BASE, info, self.call, self.get, None)

    def say(self, line):
        self.log.write(line + "\n")

    def get(self, conn, sender, path, iface, name):
        return {"version": GLib.Variant("u", 5), "AvailableSourceTypes": GLib.Variant("u", 3),
                "AvailableCursorModes": GLib.Variant("u", 7)}[name]

    def sender_part(self, sender):
        return sender[1:].replace(".", "_")

    def request(self, sender, options, code, results):
        token = options.get("handle_token", "t")
        path = "%s/request/%s/%s" % (BASE, self.sender_part(sender), token)
        closed = []

        def close(conn, sender_, path_, iface, method, params, inv):
            closed.append(True)
            self.say("Request.Close")
            inv.return_value(None)

        rid = self.bus.register_object(path, self.request_info, close, None, None)

        def answer():
            self.bus.unregister_object(rid)
            if not closed:
                self.bus.emit_signal(sender, path, "org.freedesktop.portal.Request", "Response",
                                     GLib.Variant("(ua{sv})", (code, results)))
            return False

        GLib.timeout_add(30, answer)
        return path

    def call(self, conn, sender, path, iface, method, params, inv):
        p = params.unpack()
        if method == "CreateSession":
            options = p[0]
            handle = "%s/session/%s/%s" % (BASE, self.sender_part(sender), options["session_handle_token"])

            def close(conn_, sender_, path_, iface_, method_, params_, inv_):
                self.say("Session.Close")
                s = self.sessions.pop(path_, None)
                if s and s.get("id"):
                    self.bus.unregister_object(s["id"])
                inv_.return_value(None)

            sid = self.bus.register_object(handle, self.session_info, close,
                                           lambda *a: GLib.Variant("u", 1), None)
            self.sessions[handle] = {"id": sid, "types": 1}
            self.say("CreateSession")
            inv.return_value(GLib.Variant("(o)", (self.request(sender, options, 0,
                                                               {"session_handle": GLib.Variant("s", handle)}),)))
        elif method == "SelectSources":
            handle, options = p
            s = self.sessions.get(handle, {})
            s["types"] = options.get("types", 1)
            self.say("SelectSources types=%s multiple=%s cursor_mode=%s persist_mode=%s restore_token=%s" % (
                options.get("types"), options.get("multiple"), options.get("cursor_mode"),
                options.get("persist_mode"), options.get("restore_token", "none")))
            inv.return_value(GLib.Variant("(o)", (self.request(sender, options, 0, {}),)))
        elif method == "Start":
            handle, parent, options = p
            s = self.sessions.get(handle, {})
            answer = self.answers.pop(0) if self.answers else "ok"
            self.say("Start (%s)" % ("the user picked" if answer == "ok" else "the user said no"))
            if answer != "ok":
                inv.return_value(GLib.Variant("(o)", (self.request(sender, options, 1, {}),)))
                return
            self.tokens += 1
            if s.get("types") == 2:
                node, props = self.args.window, {"source_type": GLib.Variant("u", 2)}
            else:
                w, h = (int(x) for x in self.args.size.split("x"))
                node, props = self.args.monitor, {"source_type": GLib.Variant("u", 1),
                                                  "position": GLib.Variant("(ii)", (0, 0)),
                                                  "size": GLib.Variant("(ii)", (w, h))}
            results = {"streams": GLib.Variant("a(ua{sv})", [(node, props)]),
                       "restore_token": GLib.Variant("s", "token-%d" % self.tokens)}
            inv.return_value(GLib.Variant("(o)", (self.request(sender, options, 0, results),)))
        elif method == "OpenPipeWireRemote":
            self.say("OpenPipeWireRemote")
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], "pipewire-0"))
            fds = Gio.UnixFDList.new()
            fds.append(sock.fileno())
            sock.close()
            inv.return_value_with_unix_fd_list(GLib.Variant("(h)", (0,)), fds)
        else:
            inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--monitor", type=int, required=True)
    ap.add_argument("--window", type=int, required=True)
    ap.add_argument("--size", default="320x200")
    ap.add_argument("--answers", default="")
    args = ap.parse_args()
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    portal = Portal(bus, args)
    loop = GLib.MainLoop()

    def owned(*a):
        print("ready", flush=True)

    Gio.bus_own_name_on_connection(bus, "org.freedesktop.portal.Desktop", Gio.BusNameOwnerFlags.NONE, owned,
                                   lambda *a: sys.exit("fake_portal: the name is taken"))
    loop.run()
    del portal


if __name__ == "__main__":
    main()
