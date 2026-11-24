#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A stand-in for the desktop's notification server and Dock, for Ferry's
notification tests (notifications.sh starts it on a private session bus).

It owns org.freedesktop.Notifications (unless --no-server) and writes down,
one line each, the Notify and CloseNotification calls it gets and the
com.canonical.Unity.LauncherEntry Update signals it sees. As the user would,
it answers the notifications named on its command line:

  --act SUMMARY=KEY     ActionInvoked(id, KEY), then NotificationClosed(id, 2)
  --reply SUMMARY=TEXT  NotificationReplied(id, TEXT), then NotificationClosed(id, 2)
  --dismiss SUMMARY     NotificationClosed(id, 2)

and as freemac's Dock does, with --dock it says the Dock started again after
the first Update (org.freemac.Dock Started), and after the app sends its
badges again it opens the app's Dock menu (the Update's "quicklist", a
dbusmenu object) and clicks the item labelled --menu-click.
"""
import argparse
import signal
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

XML = """
<node>
  <interface name="org.freedesktop.Notifications">
    <method name="GetCapabilities"><arg type="as" direction="out"/></method>
    <method name="Notify">
      <arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
      <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/>
      <arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/>
    </method>
    <method name="CloseNotification"><arg type="u" direction="in"/></method>
    <method name="GetServerInformation">
      <arg type="s" direction="out"/><arg type="s" direction="out"/>
      <arg type="s" direction="out"/><arg type="s" direction="out"/>
    </method>
    <signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
    <signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
    <signal name="NotificationReplied"><arg type="u"/><arg type="s"/></signal>
  </interface>
</node>
"""
PATH = "/org/freedesktop/Notifications"
IFACE = "org.freedesktop.Notifications"


def pairs(values):
    out = {}
    for v in values or []:
        key, _, rest = v.partition("=")
        out[key] = rest
    return out


def show(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return repr(value)
    return str(value)


class Fake:
    def __init__(self, args):
        self.args = args
        self.acts = pairs(args.act)
        self.replies = pairs(args.reply)
        self.dismiss = set(args.dismiss or [])
        self.caps = [c for c in args.caps.split(",") if c]
        self.log = open(args.log, "w", buffering=1)
        self.next_id = 1
        self.updates = 0
        self.menu_read = False
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.bus.signal_subscribe(None, "com.canonical.Unity.LauncherEntry", "Update", None, None,
                                  Gio.DBusSignalFlags.NONE, self.update)
        if args.no_server:
            self.ready()
            return
        node = Gio.DBusNodeInfo.new_for_xml(XML)
        self.bus.register_object(PATH, node.interfaces[0], self.method, None, None)
        Gio.bus_own_name_on_connection(self.bus, IFACE, Gio.BusNameOwnerFlags.NONE,
                                       lambda *_: self.ready(), None)

    def ready(self):
        with open(self.args.ready, "w") as f:
            f.write("ready\n")

    def write(self, line):
        self.log.write(line + "\n")

    def emit(self, signal_name, signature, values):
        self.bus.emit_signal(None, PATH, IFACE, signal_name, GLib.Variant(signature, values))

    def method(self, _bus, _sender, _path, _iface, method, params, invocation):
        if method == "GetCapabilities":
            invocation.return_value(GLib.Variant("(as)", (self.caps,)))
        elif method == "GetServerInformation":
            invocation.return_value(GLib.Variant("(ssss)", ("fake", "ferry tests", "1.0", "1.2")))
        elif method == "Notify":
            app, replaces, icon, summary, body, actions, hints, timeout = params.unpack()
            nid = replaces or self.next_id
            if not replaces:
                self.next_id += 1
            acts = ", ".join(f"{k}:{v}" for k, v in zip(actions[0::2], actions[1::2]))
            shown = ", ".join(f"{k}: {show(hints[k])}" for k in sorted(hints))
            self.write(f"Notify #{nid} app={app!r} replaces={replaces} icon={icon!r} summary={summary!r} "
                       f"body={body!r} timeout={timeout}")
            self.write(f"    actions [{acts}]")
            self.write(f"    hints {{{shown}}}")
            invocation.return_value(GLib.Variant("(u)", (nid,)))
            if summary in self.acts:
                GLib.timeout_add(50, self.invoke, nid, self.acts[summary])
            elif summary in self.replies:
                GLib.timeout_add(50, self.answer, nid, self.replies[summary])
            elif summary in self.dismiss:
                GLib.timeout_add(50, self.closed, nid, 2)
        elif method == "CloseNotification":
            (nid,) = params.unpack()
            self.write(f"CloseNotification #{nid}")
            invocation.return_value(None)
            self.emit("NotificationClosed", "(uu)", (nid, 3))
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

    def invoke(self, nid, key):
        self.write(f"(clicks {key} on #{nid})")
        self.emit("ActionInvoked", "(us)", (nid, key))
        self.emit("NotificationClosed", "(uu)", (nid, 2))
        return False

    def answer(self, nid, text):
        self.write(f"(replies {text!r} to #{nid})")
        self.emit("NotificationReplied", "(us)", (nid, text))
        self.emit("NotificationClosed", "(uu)", (nid, 2))
        return False

    def closed(self, nid, reason):
        self.write(f"(dismisses #{nid})")
        self.emit("NotificationClosed", "(uu)", (nid, reason))
        return False

    def update(self, _bus, sender, _path, _iface, _signal, params):
        uri, props = params.unpack()
        shown = ", ".join(f"{k}: {show(props[k])}" for k in sorted(props))
        self.write(f"Update {uri} {{{shown}}}")
        self.updates += 1
        if self.args.dock and self.updates == 1:
            self.write("(the Dock starts again)")
            self.bus.emit_signal(None, "/org/freemac/Dock", "org.freemac.Dock", "Started", None)
        elif self.args.dock and self.updates == 2 and "quicklist" in props and not self.menu_read:
            self.menu_read = True
            self.read_menu(sender, props["quicklist"])

    def call(self, sender, path, method, args, reply):
        return self.bus.call_sync(sender, path, "com.canonical.dbusmenu", method, args,
                                  GLib.VariantType.new(reply), Gio.DBusCallFlags.NONE, 5000, None)

    def read_menu(self, sender, path):
        self.call(sender, path, "AboutToShow", GLib.Variant("(i)", (0,)), "(b)")
        _rev, layout = self.call(sender, path, "GetLayout", GLib.Variant("(iias)", (0, -1, [])),
                                 "(u(ia{sv}av))").unpack()
        found = []

        def walk(node, depth):
            ident, props, children = node
            if ident:
                label = props.get("label", "-" if props.get("type") == "separator" else "")
                self.write("    " + "  " * depth + f"menu {label}")
                found.append((ident, label))
            for child in children:
                walk(child, depth + (1 if ident else 0))
        self.write("Dock menu:")
        walk(layout, 0)
        for ident, label in found:
            if label == self.args.menu_click:
                self.write(f"(clicks {label} in the Dock menu)")
                self.call(sender, path, "Event", GLib.Variant("(isvu)", (ident, "clicked", GLib.Variant("i", 0), 0)),
                          "()")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--log", required=True)
    p.add_argument("--ready", required=True)
    p.add_argument("--caps", default="body,actions,body-markup,inline-reply,persistence")
    p.add_argument("--act", action="append")
    p.add_argument("--reply", action="append")
    p.add_argument("--dismiss", action="append")
    p.add_argument("--dock", action="store_true")
    p.add_argument("--menu-click", default="")
    p.add_argument("--no-server", action="store_true")
    args = p.parse_args()
    loop = GLib.MainLoop()
    fake = Fake(args)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: (loop.quit(), False)[1])
    loop.run()
    fake.log.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
