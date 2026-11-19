# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials panels for accounts and devices: Users, Bluetooth and Printers.

Users changes go through /usr/libexec/freemac-users-helper with pkexec, so an
administrator's password is asked for once and then remembered for a few
minutes. Bluetooth talks to BlueZ over D-Bus. Printers uses the CUPS command
line tools and hands adding a printer to system-config-printer.
"""
import grp
import os
import pwd
import re
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

HELPER = "/usr/libexec/freemac-users-helper"
GREETD = "/etc/greetd/config.toml"
ADMIN_GROUP = "sudo"


def clear(box):
    for child in box.get_children():
        box.remove(child)


def bold(text):
    label = Gtk.Label(xalign=0)
    label.set_markup(f"<b>{GLib.markup_escape_text(text)}</b>")
    return label


def caption(text):
    label = Gtk.Label(label=text, xalign=0, wrap=True)
    label.get_style_context().add_class("dials-caption")
    return label


def item_row(icon, title, subtitle, *widgets):
    line = Gtk.Box(spacing=12)
    line.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.DND), False, False, 0)
    text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    text.pack_start(bold(title), False, False, 0)
    if subtitle:
        text.pack_start(caption(subtitle), False, False, 0)
    line.pack_start(text, True, True, 0)
    for widget in reversed(widgets):
        widget.set_valign(Gtk.Align.CENTER)
        line.pack_end(widget, False, False, 0)
    item = Gtk.ListBoxRow(activatable=False)
    item.add(line)
    return item


def message(window, text, secondary=None, kind=Gtk.MessageType.ERROR):
    dialog = Gtk.MessageDialog(transient_for=window, modal=True, message_type=kind,
                               buttons=Gtk.ButtonsType.OK, text=text, secondary_text=secondary)
    dialog.run()
    dialog.destroy()


# ---- Users ----------------------------------------------------------------------
def people():
    """Accounts that belong to people: [(name, full name, is admin)]."""
    try:
        admins = set(grp.getgrnam(ADMIN_GROUP).gr_mem)
    except KeyError:
        admins = set()
    found = []
    for entry in pwd.getpwall():
        if 1000 <= entry.pw_uid < 60000 and not entry.pw_shell.endswith(("nologin", "false")):
            full = entry.pw_gecos.split(",")[0] or entry.pw_name
            found.append((entry.pw_name, full, entry.pw_name in admins))
    return sorted(found, key=lambda p: p[1].lower())


def autologin_user():
    try:
        with open(GREETD) as f:
            text = f.read()
    except OSError:
        return None
    match = re.search(r'^\[initial_session\][^\[]*?^user\s*=\s*"([^"]+)"', text, re.M | re.S)
    return match.group(1) if match else None


def username_for(full):
    """A user name suggested from a full name: 'Ana María Ruiz' -> 'ana'."""
    first = (full.strip().split() or [""])[0].lower()
    name = re.sub(r"[^a-z0-9_-]", "", first)
    return name if name and name[0].isalpha() else ""


class UsersPanel(Gtk.Box):
    def __init__(self, window, page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.window = window
        self.me = pwd.getpwuid(os.getuid()).pw_name
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.get_style_context().add_class("dials-group")
        add = Gtk.Button(label="Add User…", halign=Gtk.Align.START)
        add.connect("clicked", self.on_add)
        self.auto = Gtk.ComboBoxText()
        self.auto_handler = self.auto.connect("changed", self.on_autologin)
        auto_group = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        auto_group.get_style_context().add_class("dials-group")
        line = Gtk.Box(spacing=12)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        text.pack_start(Gtk.Label(label="Log in automatically as", xalign=0), False, False, 0)
        text.pack_start(caption("Skips the login screen when the computer starts."), False, False, 0)
        line.pack_start(text, True, True, 0)
        self.auto.set_valign(Gtk.Align.CENTER)
        line.pack_end(self.auto, False, False, 0)
        auto_row = Gtk.ListBoxRow(activatable=False)
        auto_row.add(line)
        auto_group.add(auto_row)
        self.status = caption("")
        self.pack_start(page("Users", self.list, add, auto_group, self.status), True, True, 0)
        self.refresh()

    def refresh(self):
        clear(self.list)
        everyone = people()
        for name, full, admin in everyone:
            kind = "Administrator" if admin else "Standard"
            subtitle = f"{name} · {kind}" + (" · You" if name == self.me else "")
            password = Gtk.Button(label="Password…")
            password.connect("clicked", lambda _b, n=name, f=full: self.on_password(n, f))
            more = Gtk.MenuButton(image=Gtk.Image.new_from_icon_name("view-more-symbolic", Gtk.IconSize.BUTTON))
            menu = Gtk.Menu()
            toggle = Gtk.MenuItem(label="Make Standard User" if admin else "Make Administrator")
            toggle.connect("activate", lambda _m, n=name, a=admin: self.helper("admin", n, "0" if a else "1"))
            menu.append(toggle)
            delete = Gtk.MenuItem(label="Delete User…", sensitive=name != self.me)
            delete.connect("activate", lambda _m, n=name, f=full: self.on_delete(n, f))
            menu.append(delete)
            menu.show_all()
            more.set_popup(menu)
            self.list.add(item_row("avatar-default-symbolic", full, subtitle, password, more))
        self.list.show_all()
        current = autologin_user()
        with self.auto.handler_block(self.auto_handler):
            self.auto.remove_all()
            self.auto.append("-", "Nobody")
            for name, full, _admin in everyone:
                self.auto.append(name, full)
            self.auto.set_active_id(current if current in [p[0] for p in everyone] else "-")

    def helper(self, *args, stdin=None, done=None):
        """Run the helper through pkexec without freezing the window."""
        if not os.path.exists(HELPER) or not shutil.which("pkexec"):
            message(self.window, "Can't change accounts here",
                    "freemac's account helper isn't installed on this computer.")
            return
        self.status.set_text("Waiting for an administrator's password…")
        flags = Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDERR_PIPE | Gio.SubprocessFlags.STDOUT_SILENCE
        proc = Gio.Subprocess.new(["pkexec", HELPER, *args], flags)

        def finished(p, result):
            try:
                _out, err = p.communicate_utf8_finish(result)
            except GLib.Error as e:
                err = e.message
            self.status.set_text("")
            code = p.get_exit_status() if p.get_if_exited() else 1
            if code in (126, 127):
                err = "The administrator's password wasn't given, so nothing changed."
            if code:
                message(self.window, "That didn't work", (err or "").strip() or None)
            self.refresh()
            if done:
                done(code == 0)

        proc.communicate_utf8_async(stdin, None, finished)

    def password_fields(self, grid, top):
        first = Gtk.Entry(visibility=False, activates_default=True, hexpand=True)
        second = Gtk.Entry(visibility=False, activates_default=True)
        grid.attach(Gtk.Label(label="Password", xalign=1), 0, top, 1, 1)
        grid.attach(first, 1, top, 1, 1)
        grid.attach(Gtk.Label(label="Confirm", xalign=1), 0, top + 1, 1, 1)
        grid.attach(second, 1, top + 1, 1, 1)
        return first, second

    def dialog(self, title, action):
        dialog = Gtk.Dialog(title=title, transient_for=self.window, modal=True, use_header_bar=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        ok = dialog.add_button(action, Gtk.ResponseType.OK)
        ok.get_style_context().add_class("suggested-action")
        dialog.set_default_response(Gtk.ResponseType.OK)
        grid = Gtk.Grid(row_spacing=10, column_spacing=12, margin=18)
        dialog.get_content_area().add(grid)
        return dialog, grid, ok

    def on_add(self, _button):
        dialog, grid, ok = self.dialog("Add User", "Add")
        full = Gtk.Entry(placeholder_text="Ana Ruiz", activates_default=True, hexpand=True)
        name = Gtk.Entry(placeholder_text="ana", activates_default=True)
        grid.attach(Gtk.Label(label="Full name", xalign=1), 0, 0, 1, 1)
        grid.attach(full, 1, 0, 1, 1)
        grid.attach(Gtk.Label(label="User name", xalign=1), 0, 1, 1, 1)
        grid.attach(name, 1, 1, 1, 1)
        first, second = self.password_fields(grid, 2)
        admin = Gtk.CheckButton(label="Administrator (can install apps and change settings for everyone)")
        grid.attach(admin, 1, 4, 1, 1)
        hint = caption("")
        grid.attach(hint, 1, 5, 1, 1)
        touched = {"name": False}

        def update(*_):
            if not touched["name"]:
                with name.handler_block(name.handler):
                    name.set_text(username_for(full.get_text()))
            problem = ""
            if name.get_text() and not re.match(r"^[a-z_][a-z0-9_-]{0,30}$", name.get_text()):
                problem = "User names use small letters, numbers, - and _."
            elif name.get_text() in [p[0] for p in people()]:
                problem = "That user name is taken."
            elif second.get_text() and first.get_text() != second.get_text():
                problem = "The passwords don't match."
            hint.set_text(problem)
            ok.set_sensitive(bool(name.get_text() and first.get_text()
                                  and first.get_text() == second.get_text() and not problem))

        def typed_name(*_):
            touched["name"] = bool(name.get_text())
            update()

        full.connect("changed", update)
        name.handler = name.connect("changed", typed_name)
        first.connect("changed", update)
        second.connect("changed", update)
        update()
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            self.helper("add", name.get_text(), full.get_text().strip() or name.get_text(),
                        "1" if admin.get_active() else "0", stdin=first.get_text() + "\n")
        dialog.destroy()

    def on_password(self, name, full):
        dialog, grid, ok = self.dialog(f"Password for {full}", "Change")
        first, second = self.password_fields(grid, 0)

        def update(*_):
            ok.set_sensitive(bool(first.get_text()) and first.get_text() == second.get_text())

        first.connect("changed", update)
        second.connect("changed", update)
        update()
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            self.helper("password", name, stdin=first.get_text() + "\n")
        dialog.destroy()

    def on_delete(self, name, full):
        dialog = Gtk.MessageDialog(transient_for=self.window, modal=True, message_type=Gtk.MessageType.QUESTION,
                                   text=f"Delete {full}?",
                                   secondary_text="They won't be able to log in any more. You can keep their "
                                                  "files in /home or delete them too.")
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Keep Files", 1, "Delete Files", 2)
        dialog.get_widget_for_response(2).get_style_context().add_class("destructive-action")
        answer = dialog.run()
        dialog.destroy()
        if answer in (1, 2):
            self.helper("delete", name, "keep" if answer == 1 else "remove")

    def on_autologin(self, combo):
        self.helper("autologin", combo.get_active_id() or "-")


# ---- Bluetooth ------------------------------------------------------------------
AGENT_PATH = "/org/freemac/dials/agent"
AGENT_XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""

DEVICE_ICONS = {
    "audio-headset": "audio-headset-symbolic", "audio-headphones": "audio-headphones-symbolic",
    "audio-card": "audio-speakers-symbolic", "input-keyboard": "input-keyboard-symbolic",
    "input-mouse": "input-mouse-symbolic", "input-tablet": "input-tablet-symbolic",
    "input-gaming": "input-gaming-symbolic", "phone": "phone-symbolic",
    "computer": "computer-symbolic", "printer": "printer-symbolic",
}


class BluetoothPanel(Gtk.Box):
    def __init__(self, window, page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.window = window
        self.adapter = None
        self.objects = {}
        self.pending = None
        self.power = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.power_handler = self.power.connect("notify::active", self.on_power)
        top = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        top.get_style_context().add_class("dials-group")
        line = Gtk.Box(spacing=12)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        text.pack_start(Gtk.Label(label="Bluetooth", xalign=0), False, False, 0)
        self.state = caption("")
        text.pack_start(self.state, False, False, 0)
        line.pack_start(text, True, True, 0)
        line.pack_end(self.power, False, False, 0)
        power_row = Gtk.ListBoxRow(activatable=False)
        power_row.add(line)
        top.add(power_row)
        self.mine_title = Gtk.Label(label="My Devices", xalign=0)
        self.mine_title.get_style_context().add_class("dials-section")
        self.mine = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.mine.get_style_context().add_class("dials-group")
        self.nearby_title = Gtk.Label(label="Nearby Devices", xalign=0)
        self.nearby = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.nearby.get_style_context().add_class("dials-group")
        self.pack_start(page("Bluetooth", top, self.mine_title, self.mine, self.nearby_title, self.nearby),
                        True, True, 0)
        # refresh() decides which of these show; keep show_all() off them.
        for widget in (self.mine_title, self.mine, self.nearby_title, self.nearby):
            widget.set_no_show_all(True)
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        except GLib.Error:
            self.bus = None
        if self.bus:
            self.bus.signal_subscribe("org.bluez", None, None, None, None,
                                      Gio.DBusSignalFlags.NONE, lambda *_: self.later())
            Gio.bus_watch_name_on_connection(self.bus, "org.bluez", Gio.BusNameWatcherFlags.NONE,
                                             lambda *_: self.started(), lambda *_: self.later())
        self.connect("map", lambda *_: self.discover(True))
        self.connect("unmap", lambda *_: self.discover(False))
        self.refresh()

    def started(self):
        self.register_agent()
        self.later()

    # D-Bus helpers
    def call(self, path, iface, method, params=None, reply=None, done=None, timeout=-1):
        if not self.bus:
            return

        def finished(bus, result):
            try:
                bus.call_finish(result)
            except GLib.Error as e:
                if done:
                    done(e.message)
                return
            if done:
                done(None)

        self.bus.call("org.bluez", path, iface, method, params, reply, Gio.DBusCallFlags.NONE,
                      timeout, None, finished)

    def set_prop(self, path, iface, name, value):
        self.call(path, "org.freedesktop.DBus.Properties", "Set",
                  GLib.Variant("(ssv)", (iface, name, value)))

    def register_agent(self):
        if not self.bus or getattr(self, "agent_id", None):
            return
        info = Gio.DBusNodeInfo.new_for_xml(AGENT_XML).interfaces[0]
        try:
            self.agent_id = self.bus.register_object(AGENT_PATH, info, self.agent_method, None, None)
        except GLib.Error:
            return
        self.call("/org/bluez", "org.bluez.AgentManager1", "RegisterAgent",
                  GLib.Variant("(os)", (AGENT_PATH, "KeyboardDisplay")))
        self.call("/org/bluez", "org.bluez.AgentManager1", "RequestDefaultAgent",
                  GLib.Variant("(o)", (AGENT_PATH,)))

    def device_name(self, path):
        props = self.objects.get(path, {}).get("org.bluez.Device1", {})
        return props.get("Alias") or props.get("Name") or "The device"

    def agent_method(self, _conn, _sender, _path, _iface, method, params, invocation):
        args = params.unpack()
        name = self.device_name(args[0]) if args else ""
        if method == "RequestConfirmation":
            ok = self.ask(f"Pair with {name}?", f"Check that {name} shows {args[1]:06d}.")
            invocation.return_value(None) if ok else invocation.return_dbus_error(
                "org.bluez.Error.Rejected", "Rejected")
        elif method in ("DisplayPasskey", "DisplayPinCode"):
            code = f"{args[1]:06d}" if method == "DisplayPasskey" else args[1]
            self.state.set_text(f"Type {code} on {name}, then press Enter.")
            invocation.return_value(None)
        elif method in ("RequestPinCode", "RequestPasskey"):
            code = self.ask_code(name)
            if code is None:
                invocation.return_dbus_error("org.bluez.Error.Canceled", "Canceled")
            elif method == "RequestPinCode":
                invocation.return_value(GLib.Variant("(s)", (code,)))
            else:
                invocation.return_value(GLib.Variant("(u)", (int(code or 0) if code.isdigit() else 0,)))
        elif method == "RequestAuthorization":
            ok = self.ask(f"Pair with {name}?", None)
            invocation.return_value(None) if ok else invocation.return_dbus_error(
                "org.bluez.Error.Rejected", "Rejected")
        else:   # Release, Cancel, AuthorizeService for paired devices
            invocation.return_value(None)

    def ask(self, text, secondary):
        dialog = Gtk.MessageDialog(transient_for=self.window, modal=True, message_type=Gtk.MessageType.QUESTION,
                                   text=text, secondary_text=secondary)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Pair", Gtk.ResponseType.OK)
        answer = dialog.run()
        dialog.destroy()
        return answer == Gtk.ResponseType.OK

    def ask_code(self, name):
        dialog = Gtk.Dialog(title=f"Pair with {name}", transient_for=self.window, modal=True, use_header_bar=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Pair", Gtk.ResponseType.OK).get_style_context().add_class("suggested-action")
        entry = Gtk.Entry(activates_default=True, placeholder_text="0000", margin=18)
        dialog.set_default_response(Gtk.ResponseType.OK)
        box = dialog.get_content_area()
        box.add(Gtk.Label(label=f"Enter the code for {name}. Many devices use 0000.", margin=12))
        box.add(entry)
        dialog.show_all()
        code = entry.get_text() if dialog.run() == Gtk.ResponseType.OK else None
        dialog.destroy()
        return code

    # State
    def later(self):
        if not self.pending:
            self.pending = GLib.timeout_add(1000, self.refresh)

    def refresh(self):
        self.pending = None
        self.objects = {}
        if self.bus:
            try:
                reply = self.bus.call_sync("org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
                                           "GetManagedObjects", None, None, Gio.DBusCallFlags.NO_AUTO_START, 2000, None)
                self.objects = reply.unpack()[0]
            except GLib.Error:
                pass
        adapters = sorted(p for p, ifaces in self.objects.items() if "org.bluez.Adapter1" in ifaces)
        self.adapter = adapters[0] if adapters else None
        clear(self.mine)
        clear(self.nearby)
        if not self.adapter:
            self.power.set_sensitive(False)
            self.state.set_text("This computer has no Bluetooth." if self.bus else "Bluetooth isn't running.")
            for widget in (self.mine_title, self.mine, self.nearby_title, self.nearby):
                widget.hide()
            return False
        props = self.objects[self.adapter]["org.bluez.Adapter1"]
        on = bool(props.get("Powered"))
        self.power.set_sensitive(True)
        with self.power.handler_block(self.power_handler):
            self.power.set_active(on)
        alias = props.get("Alias") or "this computer"
        self.state.set_text(f"Visible to nearby devices as “{alias}”." if on else "Off")
        mine, nearby = [], []
        for path, ifaces in self.objects.items():
            dev = ifaces.get("org.bluez.Device1")
            if not dev or not path.startswith(self.adapter + "/"):
                continue
            (mine if dev.get("Paired") else nearby).append((path, dev))
        for path, dev in sorted(mine, key=lambda d: d[1].get("Alias", "")):
            self.mine.add(self.device_row(path, dev))
        for path, dev in sorted(nearby, key=lambda d: (-d[1].get("RSSI", -999), d[1].get("Alias", "")))[:20]:
            if dev.get("Name"):     # nameless devices are mostly beacons
                self.nearby.add(self.device_row(path, dev))
        for widget in (self.mine_title, self.mine):
            widget.set_visible(on and bool(mine))
        for widget in (self.nearby_title, self.nearby):
            widget.set_visible(on)
        if on and not self.nearby.get_children():
            self.nearby.add(item_row("bluetooth-active-symbolic", "Looking for devices…",
                                     "Put the device in pairing mode to see it here."))
        for row in self.mine.get_children() + self.nearby.get_children():
            row.show_all()      # the lists have no_show_all, so show their rows directly
        return False

    def device_row(self, path, dev):
        name = dev.get("Alias") or dev.get("Name") or "Unknown device"
        icon = DEVICE_ICONS.get(dev.get("Icon", ""), "bluetooth-active-symbolic")
        if dev.get("Paired"):
            connected = bool(dev.get("Connected"))
            status = "Connected" if connected else "Not connected"
            battery = self.objects.get(path, {}).get("org.bluez.Battery1", {}).get("Percentage")
            if battery is not None and connected:
                status += f" · Battery {battery}%"
            toggle = Gtk.Button(label="Disconnect" if connected else "Connect")
            toggle.connect("clicked", lambda _b: self.device_call(path, "Disconnect" if connected else "Connect",
                                                                  "Connecting…" if not connected else None))
            forget = Gtk.Button(image=Gtk.Image.new_from_icon_name("user-trash-symbolic", Gtk.IconSize.BUTTON),
                                tooltip_text="Forget this device")
            forget.connect("clicked", lambda _b: self.call(self.adapter, "org.bluez.Adapter1", "RemoveDevice",
                                                           GLib.Variant("(o)", (path,))))
            return item_row(icon, name, status, toggle, forget)
        pair = Gtk.Button(label="Pair")
        pair.connect("clicked", lambda _b: self.pair(path))
        return item_row(icon, name, None, pair)

    def device_call(self, path, method, note=None):
        if note:
            self.state.set_text(note)
        self.call(path, "org.bluez.Device1", method, done=self.after_call, timeout=30000)

    def after_call(self, error):
        if error:
            reason = error.split(":")[-1].strip()
            message(self.window, "That didn't work", reason or None)
        self.later()

    def pair(self, path):
        self.state.set_text(f"Pairing with {self.device_name(path)}…")

        def paired(error):
            if error:
                self.after_call(error)
                return
            self.set_prop(path, "org.bluez.Device1", "Trusted", GLib.Variant("b", True))
            self.device_call(path, "Connect")

        self.call(path, "org.bluez.Device1", "Pair", done=paired, timeout=60000)

    def on_power(self, switch, _param):
        if self.adapter:
            self.set_prop(self.adapter, "org.bluez.Adapter1", "Powered", GLib.Variant("b", switch.get_active()))
            if switch.get_active():
                GLib.timeout_add(800, lambda: self.discover(True) or False)

    def discover(self, on):
        if not self.adapter:
            return
        props = self.objects.get(self.adapter, {}).get("org.bluez.Adapter1", {})
        if on and props.get("Powered") and not props.get("Discovering"):
            self.call(self.adapter, "org.bluez.Adapter1", "StartDiscovery")
        elif not on and props.get("Discovering"):
            self.call(self.adapter, "org.bluez.Adapter1", "StopDiscovery")


# ---- Printers ---------------------------------------------------------------------
def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5,
                              env=dict(os.environ, LC_ALL="C"))
    except (OSError, subprocess.SubprocessError):
        return None


def printers():
    """[(name, description, state, is default)] from CUPS."""
    result = run("lpstat", "-l", "-p", "-d")
    if result is None:
        return None
    default = None
    found, current = [], None
    for line in result.stdout.splitlines():
        match = re.match(r"printer (\S+) (?:is )?(idle|now printing|disabled)", line)
        if match:
            current = [match.group(1), match.group(1), match.group(2), False]
            found.append(current)
            continue
        match = re.match(r"\s+Description: (.*)", line)
        if match and current:
            current[1] = match.group(1).strip() or current[0]
        match = re.match(r"system default destination: (\S+)", line)
        if match:
            default = match.group(1)
    user_default = os.environ.get("PRINTER") or lpoptions_default()
    for printer in found:
        printer[3] = printer[0] == (user_default or default)
    return [tuple(p) for p in found]


def lpoptions_default():
    try:
        with open(os.path.expanduser("~/.cups/lpoptions")) as f:
            for line in f:
                if line.startswith("Default "):
                    return line.split()[1].split("/")[0]
    except OSError:
        pass
    return None


class PrintersPanel(Gtk.Box):
    def __init__(self, window, page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.window = window
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.get_style_context().add_class("dials-group")
        add = Gtk.Button(label="Add Printer…", halign=Gtk.Align.START)
        add.connect("clicked", self.on_add)
        add.set_sensitive(bool(shutil.which("system-config-printer")))
        note = caption("Most network printers made in the last ten years show up here by themselves. "
                       "For others, Add Printer finds the right driver.")
        self.pack_start(page("Printers", self.list, add, note), True, True, 0)
        self.connect("map", lambda *_: self.refresh())
        self.refresh()

    def refresh(self):
        clear(self.list)
        found = printers()
        if found is None:
            self.list.add(item_row("printer-symbolic", "Printing isn't set up",
                                   "The CUPS printing service isn't installed."))
        elif not found:
            self.list.add(item_row("printer-symbolic", "No printers yet",
                                   "Turn on a network printer, or plug one in, and it appears here."))
        for name, description, state, default in found or ():
            status = {"idle": "Ready", "now printing": "Printing", "disabled": "Paused"}.get(state, state)
            if default:
                status += " · Default"
            test = Gtk.Button(label="Test Page")
            test.connect("clicked", lambda _b, n=name: self.test_page(n))
            more = Gtk.MenuButton(image=Gtk.Image.new_from_icon_name("view-more-symbolic", Gtk.IconSize.BUTTON))
            menu = Gtk.Menu()
            make_default = Gtk.MenuItem(label="Use as Default", sensitive=not default)
            make_default.connect("activate", lambda _m, n=name: self.lp("lpoptions", "-d", n))
            menu.append(make_default)
            queue = Gtk.MenuItem(label="Print Queue and Options…")
            queue.connect("activate", lambda _m, n=name: self.launch("system-config-printer", "--show-jobs", n))
            menu.append(queue)
            remove = Gtk.MenuItem(label="Remove Printer…")
            remove.connect("activate", lambda _m, n=name, d=description: self.remove(n, d))
            menu.append(remove)
            menu.show_all()
            more.set_popup(menu)
            self.list.add(item_row("printer-symbolic", description, status, test, more))
        self.list.show_all()

    def lp(self, *cmd):
        result = run(*cmd)
        if result is None or result.returncode:
            message(self.window, "That didn't work", (result.stderr.strip() if result else "") or None)
        self.refresh()

    def test_page(self, name):
        page = "/usr/share/cups/data/testprint"
        if not os.path.exists(page):
            message(self.window, "No test page", "CUPS's test page isn't installed.")
            return
        self.lp("lp", "-d", name, "-t", "freemac test page", page)

    def remove(self, name, description):
        dialog = Gtk.MessageDialog(transient_for=self.window, modal=True, message_type=Gtk.MessageType.QUESTION,
                                   text=f"Remove {description}?",
                                   secondary_text="You can add it again later.")
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Remove", Gtk.ResponseType.OK)
        answer = dialog.run()
        dialog.destroy()
        if answer == Gtk.ResponseType.OK:
            self.lp("lpadmin", "-x", name)

    def launch(self, *cmd):
        try:
            Gio.Subprocess.new(list(cmd), Gio.SubprocessFlags.NONE)
        except GLib.Error as e:
            message(self.window, "Couldn't open that", e.message)

    def on_add(self, _button):
        self.launch("system-config-printer")
        GLib.timeout_add_seconds(5, lambda: self.refresh() or False)
