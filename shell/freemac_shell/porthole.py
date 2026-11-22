# SPDX-License-Identifier: GPL-3.0-or-later
"""Porthole: see and use another computer's screen, as a Mac's Screen Sharing
does. Type the other computer's name (a freemac with Screen Sharing on in
Dials > Sharing, or any computer that shares its screen over VNC), sign in
with a name and password from that computer, and its screen opens in a
window: what you do with the mouse and keyboard there happens on it.

    freemac-porthole                    ask which computer
    freemac-porthole vnc://NAME[:PORT]  connect straight away (Drawer's
                                        Connect to Server sends vnc:// here)

The connection is encrypted. freemac computers prove who they are with a
certificate of their own; Porthole remembers it the first time, as ssh does,
and warns if a computer by that name ever shows a different one. The screen
itself is drawn by GTK-VNC. Original freemac code."""
import hashlib
import json
import os
import socket
import ssl
import struct
import subprocess
import sys
import threading

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkVnc", "2.0")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkVnc  # noqa: E402

from . import alert, menus, style  # noqa: E402

APP_ID = "org.freemac.Porthole"
PORT = 5900
VENCRYPT = 19
X509_SUBTYPES = (262, 261, 260)      # X509Plain, X509Vnc, X509None
HERE = os.path.join(GLib.get_user_config_dir(), "freemac", "porthole")
KNOWN = os.path.join(HERE, "known.json")
RECENTS = os.path.join(HERE, "recent.json")
# GTK-VNC trusts the certificates in this file; Porthole keeps its own part.
CA_FILE = os.path.join(GLib.get_home_dir(), ".pki", "CA", "cacert.pem")
MARK_BEGIN, MARK_END = "# freemac Porthole: begin\n", "# freemac Porthole: end\n"

CSS = b"""
.porthole-start { padding: 36px; }
.porthole-title { font-size: 1.6em; font-weight: bold; }
.porthole-hint { opacity: 0.65; }
.porthole-recents { border: 1px solid alpha(currentColor, 0.12); border-radius: 8px; }
.porthole-recents row { padding: 6px 10px; }
.porthole-screen { background: #000; }
"""


# ---- addresses -------------------------------------------------------------
def parse(address):
    """(host, port) from what was typed: name, name:port, vnc://name:port,
    or name:0 as VNC display numbers are written. None if it's no address."""
    text = address.strip()
    if text.lower().startswith("vnc://"):
        text = text[6:]
    text = text.strip("/").rsplit("@", 1)[-1]
    if not text:
        return None
    host, port = text, PORT
    if text.startswith("["):                      # [IPv6]:port
        host, _, rest = text[1:].partition("]")
        if rest.startswith(":") and rest[1:].isdigit():
            port = int(rest[1:])
    elif text.count(":") == 1:
        host, _, number = text.partition(":")
        if number.isdigit():
            port = int(number) if int(number) >= 100 else PORT + int(number)
        elif number:
            return None
    if not host or any(c.isspace() for c in host):
        return None
    return host, port


def label(host, port):
    return host if port == PORT else f"{host}:{port}"


def _load(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _save(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(value, f, indent=1)
    os.replace(tmp, path)


def recents():
    items = _load(RECENTS, [])
    return [i for i in items if isinstance(i, str)][:8]


def remember(address):
    _save(RECENTS, [address] + [a for a in recents() if a != address])


# ---- the other computer's certificate ---------------------------------------
def _exactly(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise ConnectionError("closed")
        data += chunk
    return data


def fetch_certificate(host, port, timeout=8):
    """The certificate the computer shows for an encrypted (VeNCrypt X.509)
    sign-in, as PEM, or None if it offers none. Raises OSError if it can't be
    reached at all."""
    with socket.create_connection((host, port), timeout=timeout) as sock:
        version = _exactly(sock, 12)
        if not version.startswith(b"RFB "):
            raise ConnectionError("not a screen-sharing server")
        sock.sendall(b"RFB 003.008\n")
        count = _exactly(sock, 1)[0]
        if count == 0:
            return None
        types = _exactly(sock, count)
        if VENCRYPT not in types:
            return None
        sock.sendall(bytes([VENCRYPT]))
        _exactly(sock, 2)
        sock.sendall(bytes([0, 2]))
        if _exactly(sock, 1)[0] != 0:
            return None
        count = _exactly(sock, 1)[0]
        subtypes = struct.unpack(f">{count}I", _exactly(sock, 4 * count)) if count else ()
        chosen = next((s for s in X509_SUBTYPES if s in subtypes), None)
        if chosen is None:
            return None
        sock.sendall(struct.pack(">I", chosen))
        if _exactly(sock, 1)[0] != 1:
            return None
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE   # checked below against what we remember
        with context.wrap_socket(sock) as tls:
            der = tls.getpeercert(binary_form=True)
    return ssl.DER_cert_to_PEM_cert(der) if der else None


def fingerprint(pem):
    return hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest()


def common_name(pem):
    """The name the certificate was made for, which GTK-VNC checks."""
    try:
        out = subprocess.run(["openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253"],
                             input=pem, capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    for part in out.strip().partition("=")[2].split(","):
        key, _, value = part.strip().partition("=")
        if key == "CN" and value:
            return value
    return None


def known():
    value = _load(KNOWN, {})
    return value if isinstance(value, dict) else {}


def trust(key, pem):
    """Remember this computer's certificate and let GTK-VNC accept it."""
    store = known()
    store[key] = {"sha256": fingerprint(pem), "pem": pem}
    _save(KNOWN, store)
    try:
        with open(CA_FILE, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        text = ""
    if MARK_BEGIN in text:                         # keep anything that isn't ours
        before, _, rest = text.partition(MARK_BEGIN)
        text = before + rest.partition(MARK_END)[2]
    ours = "".join(entry["pem"] for entry in store.values()
                   if isinstance(entry, dict) and entry.get("pem"))
    os.makedirs(os.path.dirname(CA_FILE), exist_ok=True)
    with open(CA_FILE, "w", encoding="utf-8") as f:
        f.write(text + MARK_BEGIN + ours + MARK_END)


# ---- the window --------------------------------------------------------------
class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Porthole")
        self.set_default_size(560, 440)
        self.display = None
        self.sock = None
        self.target = None          # (host, port)
        self.signed_in = False
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.add(self.stack)
        self.stack.add_named(self._start_page(), "start")
        self.stack.add_named(self._busy_page(), "busy")
        self.stack.add_named(self._ended_page(), "ended")
        self.screen = Gtk.Box()
        self.screen.get_style_context().add_class("porthole-screen")
        self.stack.add_named(self.screen, "screen")
        menus.add_actions(self, {"close": self.close, "new": self.new_connection,
                                 "disconnect": self.disconnect, "fullscreen": self.toggle_fullscreen,
                                 "ctrl-alt-del": self.send_ctrl_alt_del})
        menus.add_toggle(self, "fit", True, self.set_fit)
        self.fullscreened = False
        self.connect("window-state-event", self._state)
        self.show_all()
        self._actions_for("start")

    # pages
    def _start_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, valign=Gtk.Align.CENTER)
        box.get_style_context().add_class("porthole-start")
        icon = Gtk.Image.new_from_icon_name("freemac-porthole", Gtk.IconSize.DIALOG)
        icon.set_pixel_size(96)
        box.pack_start(icon, False, False, 0)
        title = Gtk.Label(label="Connect to a computer")
        title.get_style_context().add_class("porthole-title")
        box.pack_start(title, False, False, 0)
        hint = Gtk.Label(label="Type its name, such as Kids-freemac. It needs Screen Sharing turned on "
                               "in Dials > Sharing.", wrap=True, max_width_chars=48, justify=Gtk.Justification.CENTER)
        hint.get_style_context().add_class("porthole-hint")
        box.pack_start(hint, False, False, 0)
        line = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER, margin_top=6)
        self.entry = Gtk.Entry(width_chars=30, placeholder_text="Computer name or address")
        self.entry.connect("activate", lambda *_: self.connect_to(self.entry.get_text()))
        go = Gtk.Button(label="Connect")
        go.get_style_context().add_class("suggested-action")
        go.connect("clicked", lambda *_: self.connect_to(self.entry.get_text()))
        line.pack_start(self.entry, False, False, 0)
        line.pack_start(go, False, False, 0)
        box.pack_start(line, False, False, 0)
        self.recent_heading = Gtk.Label(label="Recent", xalign=0, margin_top=10)
        self.recent_heading.get_style_context().add_class("porthole-hint")
        self.recent_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.recent_list.get_style_context().add_class("porthole-recents")
        self.recent_list.connect("row-activated", lambda _l, row: self.connect_to(row.address))
        holder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, halign=Gtk.Align.CENTER)
        holder.set_size_request(340, -1)
        holder.pack_start(self.recent_heading, False, False, 0)
        holder.pack_start(self.recent_list, False, False, 0)
        box.pack_start(holder, False, False, 0)
        self._fill_recents()
        return box

    def _fill_recents(self):
        for child in self.recent_list.get_children():
            self.recent_list.remove(child)
        items = recents()
        for address in items:
            row = Gtk.ListBoxRow()
            row.address = address
            line = Gtk.Box(spacing=8)
            line.pack_start(Gtk.Image.new_from_icon_name("computer-symbolic", Gtk.IconSize.MENU), False, False, 0)
            line.pack_start(Gtk.Label(label=address, xalign=0), True, True, 0)
            row.add(line)
            self.recent_list.add(row)
        self.recent_list.set_no_show_all(not items)
        self.recent_heading.set_no_show_all(not items)
        self.recent_list.set_visible(bool(items))
        self.recent_heading.set_visible(bool(items))
        self.recent_list.show_all()

    def _busy_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER)
        spinner = Gtk.Spinner(active=True)
        spinner.set_size_request(32, 32)
        box.pack_start(spinner, False, False, 0)
        self.busy_label = Gtk.Label()
        box.pack_start(self.busy_label, False, False, 0)
        cancel = Gtk.Button(label="Cancel", halign=Gtk.Align.CENTER)
        cancel.connect("clicked", lambda *_: self.disconnect())
        box.pack_start(cancel, False, False, 0)
        return box

    def _ended_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, valign=Gtk.Align.CENTER)
        box.get_style_context().add_class("porthole-start")
        self.ended_title = Gtk.Label(wrap=True, max_width_chars=44, justify=Gtk.Justification.CENTER)
        self.ended_title.get_style_context().add_class("porthole-title")
        self.ended_text = Gtk.Label(wrap=True, max_width_chars=48, justify=Gtk.Justification.CENTER)
        self.ended_text.get_style_context().add_class("porthole-hint")
        box.pack_start(self.ended_title, False, False, 0)
        box.pack_start(self.ended_text, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER, margin_top=8)
        other = Gtk.Button(label="Another Computer…")
        other.connect("clicked", lambda *_: self.new_connection())
        again = Gtk.Button(label="Connect Again")
        again.get_style_context().add_class("suggested-action")
        again.connect("clicked", lambda *_: self.target and self.connect_to(label(*self.target)))
        buttons.pack_start(other, False, False, 0)
        buttons.pack_start(again, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        return box

    def _actions_for(self, page):
        on_screen = page == "screen"
        for name in ("disconnect", "fit", "fullscreen", "ctrl-alt-del"):
            self.lookup_action(name).set_enabled(on_screen or (name == "disconnect" and page == "busy"))

    def _show(self, page):
        self.stack.set_visible_child_name(page)
        self._actions_for(page)

    def ended(self, title, text=""):
        self._drop_display()
        self.ended_title.set_text(title)
        self.ended_text.set_text(text)
        self.ended_text.set_visible(bool(text))
        self.set_title("Porthole")
        if self.fullscreened:
            self.unfullscreen()
        self._show("ended")

    # connecting
    def new_connection(self):
        self.disconnect(quietly=True)
        self._fill_recents()
        self.set_title("Porthole")
        self.unmaximize()
        self._show("start")
        self.entry.grab_focus()

    def connect_to(self, address):
        target = parse(address)
        if target is None:
            alert.tell(self, "That isn’t a computer’s name or address.",
                       "Type a name such as Kids-freemac, or an address such as 192.168.1.20.")
            return
        self.disconnect(quietly=True)
        self.target = target
        self.entry.set_text(label(*target))
        self.busy_label.set_text(f"Connecting to “{target[0]}”…")
        self._show("busy")
        attempt = object()
        self.attempt = attempt

        def work():
            try:
                pem = fetch_certificate(*target)
                problem = None
            except (OSError, ssl.SSLError, ConnectionError, struct.error) as error:
                pem, problem = None, error
            GLib.idle_add(self._checked, attempt, target, pem, problem)
        threading.Thread(target=work, daemon=True).start()

    def _checked(self, attempt, target, pem, problem):
        if attempt is not getattr(self, "attempt", None):
            return False                           # cancelled meanwhile
        host, port = target
        if problem is not None:
            self.ended(f"“{host}” didn’t answer.",
                       "Check the name, that it's on and on this network, and that Screen Sharing is "
                       "turned on in its Dials > Sharing.")
            return False
        hostname = None
        if pem:
            key = label(host, port).lower()
            before = known().get(key)
            if isinstance(before, dict) and before.get("sha256") != fingerprint(pem):
                answer = alert.ask(
                    self, f"“{host}” isn’t showing the same identity as before.",
                    "This happens if it was reinstalled, but it could also be a different computer "
                    "pretending to be it. Connect only if you know why it changed.",
                    (("Cancel", Gtk.ResponseType.CANCEL), ("Connect Anyway", Gtk.ResponseType.OK)),
                    default=Gtk.ResponseType.CANCEL)
                if answer != Gtk.ResponseType.OK:
                    self.ended("Not connected.", f"“{host}” showed a different identity.")
                    return False
            try:
                trust(key, pem)
            except OSError:
                pass
            hostname = common_name(pem) or host
        self._open(host, port, hostname)
        return False

    def _open(self, host, port, hostname):
        display = GtkVnc.Display()
        display.set_scaling(self.lookup_action("fit").get_state().get_boolean())
        display.set_keep_aspect_ratio(True)
        display.set_pointer_local(False)
        display.set_hexpand(True)
        display.set_vexpand(True)
        display.connect("vnc-auth-credential", self._credentials)
        display.connect("vnc-auth-failure", self._auth_failed)
        display.connect("vnc-auth-unsupported", lambda *_: self.ended(
            f"Porthole can’t sign in to “{host}”.", "It asks for a kind of sign-in Porthole doesn't know."))
        display.connect("vnc-initialized", self._initialized)
        display.connect("vnc-disconnected", self._disconnected)
        display.connect("vnc-error", lambda _d, message: setattr(self, "problem", message))
        self.display, self.problem, self.signed_in, self.auth_failed = display, None, False, False
        for child in self.screen.get_children():
            self.screen.remove(child)
        self.screen.pack_start(display, True, True, 0)
        display.show()
        if hostname:
            # Connect here and hand GTK-VNC the socket, with the name the
            # certificate was made for, so it's checked against what we
            # remember whatever name or address was typed.
            try:
                sock = socket.create_connection((host, port), timeout=10)
                sock.settimeout(None)
            except OSError:
                self.ended(f"“{host}” didn’t answer.")
                return
            display.open_fd_with_hostname(sock.detach(), hostname)
        else:
            display.open_host(host, str(port))

    def _credentials(self, display, wanted):
        kinds = []
        for i in range(wanted.n_values):
            value = wanted.get_nth(i)
            kinds.append(int(value.get_enum() if hasattr(value, "get_enum") else value))
        needs_name = GtkVnc.DisplayCredential.USERNAME in kinds
        needs_password = GtkVnc.DisplayCredential.PASSWORD in kinds
        if GtkVnc.DisplayCredential.CLIENTNAME in kinds:
            display.set_credential(GtkVnc.DisplayCredential.CLIENTNAME, "freemac")
        if not (needs_name or needs_password):
            return
        answer = self._sign_in(needs_name)
        if answer is None:
            self.disconnect(quietly=True)
            self.ended("Not connected.")
            return
        name, password = answer
        if needs_name:
            display.set_credential(GtkVnc.DisplayCredential.USERNAME, name)
        if needs_password:
            display.set_credential(GtkVnc.DisplayCredential.PASSWORD, password)

    def _sign_in(self, needs_name):
        host = self.target[0] if self.target else "the computer"
        dialog = alert.build(self, f"Sign in to “{host}”",
                             "Use a name and password from that computer.",
                             (("Cancel", Gtk.ResponseType.CANCEL), ("Sign In", Gtk.ResponseType.OK)),
                             default=Gtk.ResponseType.OK, icon="freemac-porthole")
        grid = Gtk.Grid(row_spacing=8, column_spacing=8, margin_top=6, halign=Gtk.Align.CENTER)
        name = Gtk.Entry(activates_default=True, text=GLib.get_user_name(), width_chars=22)
        password = Gtk.Entry(activates_default=True, visibility=False, width_chars=22,
                             input_purpose=Gtk.InputPurpose.PASSWORD)
        row = 0
        if needs_name:
            grid.attach(Gtk.Label(label="Name:", xalign=1), 0, row, 1, 1)
            grid.attach(name, 1, row, 1, 1)
            row += 1
        grid.attach(Gtk.Label(label="Password:", xalign=1), 0, row, 1, 1)
        grid.attach(password, 1, row, 1, 1)
        body = dialog.get_content_area().get_children()[0]   # the alert's own column
        body.pack_start(grid, False, False, 0)
        body.reorder_child(grid, len(body.get_children()) - 2)   # above the buttons
        grid.show_all()
        dialog.set_default_response(Gtk.ResponseType.OK)
        password.grab_focus()
        response = dialog.run()
        result = (name.get_text().strip(), password.get_text()) if response == Gtk.ResponseType.OK else None
        dialog.destroy()
        return result

    def _auth_failed(self, _display, _message):
        self.auth_failed = True

    def _initialized(self, display):
        self.signed_in = True
        host, port = self.target
        remember(label(host, port))
        name = display.get_name() or host
        self.set_title(f"{host} — Porthole" if name.lower() in ("wayvnc", host.lower()) else f"{name} — Porthole")
        self._show("screen")
        width, height = display.get_width(), display.get_height()
        if width and height and not self.fullscreened:
            screen = self.get_screen()
            limit_w, limit_h = (screen.get_width() * 0.85, screen.get_height() * 0.8) if screen else (1200, 800)
            scale = min(1.0, limit_w / width, limit_h / height)
            if scale < 1:
                # Bigger than this screen: fill it, as a Mac zooms the window
                # (grown in place, it would run off the edge, and on Wayland
                # a window can't move itself).
                self.maximize()
            else:
                self.resize(width, height)
        display.grab_focus()

    def _disconnected(self, _display):
        if self.display is None:
            return
        host = self.target[0] if self.target else "the computer"
        if self.auth_failed:
            self.ended("The name or password wasn’t accepted.",
                       f"Use the name and password of the person who's logged in on “{host}”.")
        elif self.signed_in:
            self.ended(f"The connection to “{host}” ended.",
                       "Someone there may have disconnected you, or it went to sleep.")
        else:
            self.ended(f"Porthole couldn’t connect to “{host}”.", self.problem or "")

    def _drop_display(self):
        display, self.display = self.display, None
        if display is not None:
            display.close()
            display.destroy()

    def disconnect(self, quietly=False):
        self.attempt = None
        if self.display is None and not quietly:
            if self.stack.get_visible_child_name() == "busy":
                self.new_connection()
            return
        self._drop_display()
        if not quietly:
            host = self.target[0] if self.target else "the computer"
            self.ended(f"Disconnected from “{host}”.")

    # view
    def set_fit(self, on):
        if self.display is not None:
            self.display.set_scaling(on)

    def toggle_fullscreen(self):
        (self.unfullscreen if self.fullscreened else self.fullscreen)()

    def _state(self, _window, event):
        self.fullscreened = bool(event.new_window_state & Gdk.WindowState.FULLSCREEN)

    def send_ctrl_alt_del(self):
        if self.display is not None:
            self.display.send_keys([Gdk.KEY_Control_L, Gdk.KEY_Alt_L, Gdk.KEY_Delete])


def menubar():
    return menus.menubar([
        ("_Connection", [[("New Connection…", "win.new", "<Ctrl>n")],
                         [("Disconnect", "win.disconnect", "<Ctrl>d")],
                         [("Close", "win.close", "<Ctrl>w")]]),
        ("_View", [[("Fit to Window", "win.fit", None)],
                   [("Enter Full Screen", "win.fullscreen", "<Ctrl><Super>f")]]),
        ("_Keys", [[("Send Control-Alt-Delete", "win.ctrl-alt-del", None)]]),
    ])


class Porthole(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": self.quit_all})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.new", ["<Control>n"]), ("win.disconnect", ["<Control>d"]),
                             ("win.close", ["<Control>w"]), ("win.fullscreen", ["<Control><Super>f"])):
            self.set_accels_for_action(action, keys)
        self.set_menubar(menubar())

    def quit_all(self):
        for window in self.get_windows():
            window.close()

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        window = self.get_active_window()
        if window is None or args:
            window = Window(self)
        if args:
            window.connect_to(args[0])
        else:
            window.entry.grab_focus()
        window.present()
        return 0


def main():
    GLib.set_prgname("freemac-porthole")
    return Porthole().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
