# SPDX-License-Identifier: GPL-3.0-or-later
"""Gangway: freemac's login screen.

A greetd greeter. greetd runs it as `cage -s -- freemac-gangway`; it talks to
greetd over the socket in $GREETD_SOCK (JSON messages with a 4-byte
native-endian length prefix) and starts freemac-session for the person who
logs in.
"""
import json
import os
import pwd
import socket
import struct
import subprocess
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

SESSION = ["/usr/local/bin/freemac-session"]
WALLPAPER = "/usr/share/backgrounds/freemac/dusk-tide.png"
CSS = b"""
window { background-color: #1c1e4a; }
.gangway-card { background-color: rgba(250, 249, 253, 0.90); border-radius: 18px; padding: 28px 32px; }
.gangway-card label { color: #1d1d27; }
.gangway-clock { color: white; font-size: 64px; font-weight: 300; font-feature-settings: "tnum"; }
.gangway-date { color: rgba(255, 255, 255, 0.85); font-size: 18px; }
.gangway-name { font-size: 20px; font-weight: 700; }
.gangway-error { color: #b3261e; }
.gangway-power { color: white; background: rgba(0, 0, 0, 0.25); border: none; border-radius: 10px; }
entry { min-height: 38px; font-size: 15px; }
button.suggested-action { background-image: none; background-color: #4b5fc4; color: white; border: none; }
"""


class Greetd:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)

    def request(self, **message):
        data = json.dumps(message).encode()
        self.sock.sendall(struct.pack("=I", len(data)) + data)
        size = struct.unpack("=I", self._read(4))[0]
        return json.loads(self._read(size))

    def _read(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise OSError("greetd closed the connection")
            buf += chunk
        return buf


def people():
    """Accounts that can log in: regular uids with a real shell."""
    found = []
    for entry in pwd.getpwall():
        if 1000 <= entry.pw_uid < 60000 and not entry.pw_shell.endswith(("nologin", "false")):
            found.append(entry)
    return sorted(found, key=lambda e: e.pw_uid)


class Gangway(Gtk.Window):
    def __init__(self):
        super().__init__(title="Log In")
        self.greetd = None
        self.users = people()
        overlay = Gtk.Overlay()
        self.add(overlay)
        self.background = Gtk.DrawingArea()
        self.background.connect("draw", self._draw_background)
        self.wallpaper = None
        try:
            self.wallpaper = GdkPixbuf.Pixbuf.new_from_file(WALLPAPER)
        except GLib.Error:
            pass
        overlay.add(self.background)

        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                         halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.clock = Gtk.Label()
        self.clock.get_style_context().add_class("gangway-clock")
        self.date = Gtk.Label()
        self.date.get_style_context().add_class("gangway-date")
        column.pack_start(self.clock, False, False, 0)
        column.pack_start(self.date, False, False, 0)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_top=36)
        card.get_style_context().add_class("gangway-card")
        card.set_size_request(340, -1)
        self.user_combo = Gtk.ComboBoxText()
        for entry in self.users:
            name = entry.pw_gecos.split(",")[0] or entry.pw_name
            self.user_combo.append(entry.pw_name, name)
        if self.users:
            self.user_combo.set_active(0)
        self.name_label = Gtk.Label()
        self.name_label.get_style_context().add_class("gangway-name")
        if len(self.users) == 1:
            self.name_label.set_text(self.users[0].pw_gecos.split(",")[0] or self.users[0].pw_name)
            card.pack_start(self.name_label, False, False, 0)
        else:
            card.pack_start(self.user_combo, False, False, 0)
        self.password = Gtk.Entry(visibility=False, placeholder_text="Password")
        self.password.connect("activate", lambda *_: self.log_in())
        card.pack_start(self.password, False, False, 0)
        self.message = Gtk.Label(wrap=True, max_width_chars=36)
        self.message.get_style_context().add_class("gangway-error")
        card.pack_start(self.message, False, False, 0)
        self.button = Gtk.Button(label="Log In")
        self.button.get_style_context().add_class("suggested-action")
        self.button.connect("clicked", lambda *_: self.log_in())
        card.pack_start(self.button, False, False, 0)
        column.pack_start(card, False, False, 0)
        overlay.add_overlay(column)

        power = Gtk.Box(spacing=8, halign=Gtk.Align.END, valign=Gtk.Align.END, margin=24)
        for label, action in (("Restart", "reboot"), ("Shut Down", "poweroff")):
            button = Gtk.Button(label=label)
            button.get_style_context().add_class("gangway-power")
            button.connect("clicked", lambda _b, a=action: self.power(a))
            power.pack_start(button, False, False, 0)
        overlay.add_overlay(power)
        self.tick()
        GLib.timeout_add_seconds(5, self.tick)

    def _draw_background(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        if self.wallpaper:
            scale = max(width / self.wallpaper.get_width(), height / self.wallpaper.get_height())
            scaled = self.wallpaper.scale_simple(int(self.wallpaper.get_width() * scale) + 1,
                                                 int(self.wallpaper.get_height() * scale) + 1,
                                                 GdkPixbuf.InterpType.BILINEAR)
            Gdk.cairo_set_source_pixbuf(cr, scaled, (width - scaled.get_width()) / 2,
                                        (height - scaled.get_height()) / 2)
        else:
            cr.set_source_rgb(0.11, 0.12, 0.29)
        cr.paint()
        return False

    def tick(self):
        now = time.localtime()
        self.clock.set_text(time.strftime("%-I:%M", now))
        self.date.set_text(time.strftime("%A, %B %-d", now))
        return True

    def username(self):
        if len(self.users) == 1:
            return self.users[0].pw_name
        return self.user_combo.get_active_id()

    def fail(self, text):
        self.message.set_text(text)
        self.password.set_text("")
        self.password.grab_focus()
        self.button.set_sensitive(True)
        if self.greetd:
            try:
                self.greetd.request(type="cancel_session")
            except OSError:
                pass

    def log_in(self):
        user = self.username()
        if not user:
            return
        self.button.set_sensitive(False)
        self.message.set_text("")
        try:
            self.greetd = self.greetd or Greetd(os.environ["GREETD_SOCK"])
            reply = self.greetd.request(type="create_session", username=user)
            # Answer the prompts PAM sends: the password for secret prompts,
            # nothing for informational ones.
            for _ in range(5):
                if reply.get("type") != "auth_message":
                    break
                kind = reply.get("auth_message_type")
                answer = self.password.get_text() if kind in ("secret", "visible") else None
                reply = self.greetd.request(type="post_auth_message_response", response=answer)
            if reply.get("type") != "success":
                self.fail("That password didn’t work. Try again.")
                return
            reply = self.greetd.request(type="start_session", cmd=SESSION, env=[])
            if reply.get("type") == "success":
                Gtk.main_quit()
            else:
                self.fail(reply.get("description") or "The desktop couldn’t start.")
        except (OSError, KeyError, ValueError) as err:
            self.greetd = None
            self.fail(f"Can’t reach the login service ({err}).")

    def power(self, action):
        if subprocess.run(["systemctl", action], capture_output=True).returncode != 0:
            self.message.set_text("This computer can’t be turned off from here right now.")


def main():
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    window = Gangway()
    window.connect("destroy", Gtk.main_quit)
    window.fullscreen()
    window.show_all()
    window.password.grab_focus()
    Gtk.main()
