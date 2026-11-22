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

from . import guest_user, style  # noqa: E402

SESSION = ["/usr/local/bin/freemac-session"]
WALLPAPER = "/usr/share/backgrounds/freemac/dusk-tide.png"
AVATAR = 96
CSS = b"""
window { background-color: #1c1e4a; }
label { color: white; text-shadow: 0 1px 3px rgba(0, 0, 0, 0.35); }
.gangway-clock { font-size: 84px; font-weight: 600; font-feature-settings: "tnum"; }
.gangway-date { font-size: 21px; font-weight: 500; color: rgba(255, 255, 255, 0.92); }
.gangway-name { font-size: 17px; font-weight: 600; }
.gangway-placeholder { color: rgba(255, 255, 255, 0.62); text-shadow: none; font-size: 14px; }
.gangway-hint { font-size: 13px; color: rgba(255, 255, 255, 0.80); }
.gangway-error { font-size: 13px; color: #ffd8d4; }
.gangway-field { background-color: rgba(255, 255, 255, 0.22); border-radius: 18px; padding: 0 4px 0 14px; }
.gangway-field entry { background: none; border: none; box-shadow: none; color: white; caret-color: white;
                       min-height: 34px; font-size: 14px; }
.gangway-field entry image { color: rgba(255, 255, 255, 0.8); }
.gangway-go { min-width: 26px; min-height: 26px; padding: 0; border-radius: 13px; border: none; box-shadow: none;
              background-image: none; background-color: rgba(255, 255, 255, 0.28); color: white; }
.gangway-go:hover { background-color: rgba(255, 255, 255, 0.40); }
.gangway-go:disabled { background-color: rgba(255, 255, 255, 0.12); }
.gangway-people button { background: none; border: none; box-shadow: none; padding: 6px; border-radius: 14px; }
.gangway-people button:hover { background-color: rgba(255, 255, 255, 0.12); }
.gangway-power { background: none; border: none; box-shadow: none; padding: 4px; }
.gangway-power .gangway-power-circle { min-width: 44px; min-height: 44px; border-radius: 22px;
                                       background-color: rgba(255, 255, 255, 0.20); color: white; }
.gangway-power:hover .gangway-power-circle { background-color: rgba(255, 255, 255, 0.34); }
.gangway-power label { font-size: 12px; }
"""


def initials(name):
    words = [w for w in name.replace(".", " ").split() if w[:1].isalpha()]
    return ("".join(w[0] for w in words[:2]) or name[:1] or "?").upper()


def avatar(entry, size=AVATAR):
    """A round picture: ~/.face if the person set one, else their initials on
    a soft gradient."""
    import cairo

    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    cr = cairo.Context(surface)
    cr.arc(size / 2, size / 2, size / 2, 0, 6.2832)
    cr.clip()
    picture = None
    for name in (".face", ".face.icon"):
        try:
            picture = GdkPixbuf.Pixbuf.new_from_file_at_scale(os.path.join(entry.pw_dir, name), size, size, False)
            break
        except GLib.Error:
            continue
    if picture is not None:
        Gdk.cairo_set_source_pixbuf(cr, picture, 0, 0)
        cr.paint()
    else:
        gradient = cairo.LinearGradient(0, 0, 0, size)
        gradient.add_color_stop_rgb(0, 0.66, 0.69, 0.75)
        gradient.add_color_stop_rgb(1, 0.47, 0.50, 0.57)
        cr.set_source(gradient)
        cr.paint()
        cr.set_source_rgb(1, 1, 1)
        cr.select_font_face("Inter", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        cr.set_font_size(size * 0.40)
        text = initials(display_name(entry))
        ext = cr.text_extents(text)
        cr.move_to(size / 2 - ext.width / 2 - ext.x_bearing, size / 2 - ext.height / 2 - ext.y_bearing)
        cr.show_text(text)
    image = Gtk.Image()
    image.set_from_surface(surface)
    return image


def display_name(entry):
    return entry.pw_gecos.split(",")[0] or entry.pw_name


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
        # cage shows one window at full size; no title bar on the login screen.
        self.set_decorated(False)
        self.greetd = None
        self.users = people()
        self.chosen = self.users[0] if self.users else None
        overlay = Gtk.Overlay()
        self.add(overlay)
        self.background = Gtk.DrawingArea()
        self.background.connect("draw", self._draw_background)
        self.wallpaper, self.soft = None, None
        try:
            self.wallpaper = GdkPixbuf.Pixbuf.new_from_file(WALLPAPER)
        except GLib.Error:
            pass
        overlay.add(self.background)

        # The time and date near the top, the person in the lower middle.
        top = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0,
                      halign=Gtk.Align.CENTER, valign=Gtk.Align.START, margin_top=64)
        self.date = Gtk.Label()
        self.date.get_style_context().add_class("gangway-date")
        self.clock = Gtk.Label()
        self.clock.get_style_context().add_class("gangway-clock")
        top.pack_start(self.date, False, False, 0)
        top.pack_start(self.clock, False, False, 0)
        overlay.add_overlay(top)

        bottom = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                         halign=Gtk.Align.CENTER, valign=Gtk.Align.END, margin_bottom=150)
        self.person = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        bottom.pack_start(self.person, False, False, 0)
        self.people = Gtk.Box(spacing=18, halign=Gtk.Align.CENTER)
        self.people.get_style_context().add_class("gangway-people")
        bottom.pack_start(self.people, False, False, 0)

        self.field = Gtk.Box(spacing=4, halign=Gtk.Align.CENTER, margin_top=6)
        self.field.get_style_context().add_class("gangway-field")
        self.field.set_size_request(240, -1)
        self.password = Gtk.Entry(visibility=False, has_frame=False)
        self.password.set_hexpand(True)
        self.password.connect("activate", lambda *_: self.log_in())
        # GTK hides an entry's placeholder while it has focus; this one stays
        # until typing starts, as on the Mac.
        placeholder = Gtk.Label(label="Enter Password", xalign=0, halign=Gtk.Align.START)
        placeholder.get_style_context().add_class("gangway-placeholder")
        placeholder.set_margin_start(2)
        self.password.connect("changed", lambda e: placeholder.set_visible(not e.get_text()))
        stack = Gtk.Overlay()
        stack.add(self.password)
        stack.add_overlay(placeholder)
        stack.set_overlay_pass_through(placeholder, True)
        self.stack = stack
        self.field.pack_start(stack, True, True, 0)
        self.button = Gtk.Button.new_from_icon_name("go-next-symbolic", Gtk.IconSize.BUTTON)
        self.button.set_tooltip_text("Log In")
        self.button.get_style_context().add_class("gangway-go")
        self.button.set_valign(Gtk.Align.CENTER)
        self.button.connect("clicked", lambda *_: self.log_in())
        self.field.pack_start(self.button, False, False, 0)
        bottom.pack_start(self.field, False, False, 0)
        self.message = Gtk.Label(wrap=True, max_width_chars=40, justify=Gtk.Justification.CENTER)
        self.message.get_style_context().add_class("gangway-hint")
        bottom.pack_start(self.message, False, False, 0)
        overlay.add_overlay(bottom)
        self.combo_hint = None
        self._show_person()

        power = Gtk.Box(spacing=28, halign=Gtk.Align.CENTER, valign=Gtk.Align.END, margin_bottom=28)
        for label, action, icon in (("Restart", "reboot", "view-refresh-symbolic"),
                                    ("Shut Down", "poweroff", "system-shutdown-symbolic")):
            button = Gtk.Button()
            button.get_style_context().add_class("gangway-power")
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            circle = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR)
            circle.get_style_context().add_class("gangway-power-circle")
            circle.set_halign(Gtk.Align.CENTER)
            inner.pack_start(circle, False, False, 0)
            inner.pack_start(Gtk.Label(label=label), False, False, 0)
            button.add(inner)
            button.connect("clicked", lambda _b, a=action: self.power(a))
            power.pack_start(button, False, False, 0)
        overlay.add_overlay(power)
        self.tick()
        GLib.timeout_add_seconds(5, self.tick)

    def _show_person(self):
        """The chosen person large, with the others as small pictures under
        them to switch to (one account: just that person)."""
        for box in (self.person, self.people):
            for child in box.get_children():
                box.remove(child)
        if self.chosen is None:
            label = Gtk.Label(label="No accounts can log in on this computer.")
            self.person.pack_start(label, False, False, 0)
            self.field.set_no_show_all(True)
            self.field.hide()
            return
        picture = avatar(self.chosen)
        picture.set_halign(Gtk.Align.CENTER)
        self.person.pack_start(picture, False, False, 0)
        name = Gtk.Label(label=display_name(self.chosen))
        name.get_style_context().add_class("gangway-name")
        self.person.pack_start(name, False, False, 0)
        for entry in self.users:
            if entry is self.chosen:
                continue
            button = Gtk.Button()
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            inner.pack_start(avatar(entry, 44), False, False, 0)
            small = Gtk.Label(label=display_name(entry))
            small.get_style_context().add_class("gangway-hint")
            inner.pack_start(small, False, False, 0)
            button.add(inner)
            button.connect("clicked", lambda _b, e=entry: self._choose(e))
            self.people.pack_start(button, False, False, 0)
        self.person.show_all()
        self.people.show_all()
        # The Guest User needs no password: just the arrow to log in.
        guest = guest_user.is_guest(self.chosen.pw_name)
        self.stack.set_visible(not guest)
        self.field.set_size_request(-1 if guest else 240, -1)
        if guest and not self.message.get_text():
            self.message.get_style_context().remove_class("gangway-error")
            self.message.set_text("No password needed. Everything is erased when you log out.")

    def _choose(self, entry):
        self.chosen = entry
        self.message.set_text("")
        self.password.set_text("")
        self._show_person()
        (self.button if guest_user.is_guest(entry.pw_name) else self.password).grab_focus()

    def _draw_background(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        if self.wallpaper:
            if self.soft is None or (self.soft.get_width(), self.soft.get_height()) < (width, height):
                self.soft = style.blurred(self.wallpaper, width, height)
            Gdk.cairo_set_source_pixbuf(cr, self.soft, (width - self.soft.get_width()) / 2,
                                        (height - self.soft.get_height()) / 2)
            cr.paint()
            cr.set_source_rgba(0, 0, 0, 0.12)
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
        return self.chosen.pw_name if self.chosen else None

    def fail(self, text):
        self.message.get_style_context().add_class("gangway-error")
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
        self.message.get_style_context().remove_class("gangway-error")
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
                self.fail("The Guest User couldn’t log in." if guest_user.is_guest(user)
                          else "That password didn’t work. Try again.")
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
    # show_all brings back the password box the Guest User doesn't have.
    window.stack.set_visible(not guest_user.is_guest(window.username() or ""))
    window.password.grab_focus()
    Gtk.main()
