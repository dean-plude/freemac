# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Network > Known Networks, as on a Mac: every Wi-Fi network this
computer has joined, the newest first, each with a … menu:

    Copy Password                  after an administrator's password
    Show Password and Code…        the same, with a code a phone can scan to join
    Join Automatically             whether the computer joins it by itself
    Forget This Network…           after asking

The networks are NetworkManager's saved Wi-Fi connections. Their passwords
are kept for the whole computer, so seeing one runs freemac-wifi-password
through pkexec, which asks for an administrator's
password, as a Mac does before it shows a Wi-Fi password; the password goes
from the helper's output to the window and the clipboard, never onto a
command line. A copied password is marked so clipboard history skips it.

The code is a standard Wi-Fi QR code (WIFI:T:WPA;S:…;P:…;;), which phone
cameras offer to join. Original freemac code.
"""
import os
import shutil

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert  # noqa: E402

try:
    gi.require_version("NM", "1.0")
    from gi.repository import NM  # noqa: E402
except (ValueError, ImportError):
    NM = None

try:
    import qrcode
except ImportError:
    qrcode = None

HELPER = "/usr/libexec/freemac-wifi-password"
SHOWN = 30   # more than a laptop meets in a year of coffee shops


def ssid_text(connection):
    wireless = connection.get_setting_wireless()
    if not wireless or not wireless.get_ssid():
        return None
    return NM.utils_ssid_to_utf8(wireless.get_ssid().get_data())


def wifi_connections(client):
    """Saved Wi-Fi networks, the one used most recently first."""
    found = []
    for connection in client.get_connections() if client else []:
        if connection.get_connection_type() != "802-11-wireless":
            continue
        ssid = ssid_text(connection)
        if not ssid:
            continue
        found.append(connection)
    found.sort(key=lambda c: -(c.get_setting_connection().get_timestamp() or 0))
    return found


def secured(connection):
    security = connection.get_setting_wireless_security()
    return bool(security and security.get_key_mgmt() and security.get_key_mgmt() != "none")


def last_used(connection):
    stamp = connection.get_setting_connection().get_timestamp() or 0
    if not stamp:
        return "Never joined"
    day = GLib.DateTime.new_from_unix_local(stamp)
    today = GLib.DateTime.new_now_local()
    if day.format("%Y-%m-%d") == today.format("%Y-%m-%d"):
        return "Joined today"
    if day.format("%Y-%m-%d") == today.add_days(-1).format("%Y-%m-%d"):
        return "Joined yesterday"
    return "Joined " + day.format("%B %-d, %Y")


def qr_text(ssid, password):
    """The text of a Wi-Fi QR code; \\ ; , : and " are escaped."""
    def esc(value):
        for ch in '\\;,:"':
            value = value.replace(ch, "\\" + ch)
        return value
    if not password:
        return f"WIFI:T:nopass;S:{esc(ssid)};;"
    return f"WIFI:T:WPA;S:{esc(ssid)};P:{esc(password)};;"


def qr_area(text, size=220):
    """A drawing of the QR code for text, or None without the qrcode module."""
    if qrcode is None:
        return None
    code = qrcode.QRCode(border=2, error_correction=qrcode.constants.ERROR_CORRECT_M)
    code.add_data(text)
    code.make(fit=True)
    matrix = code.get_matrix()
    area = Gtk.DrawingArea()
    area.set_size_request(size, size)

    def draw(_w, cr):
        cells = len(matrix)
        cell = size / cells
        cr.set_source_rgb(1, 1, 1)
        cr.rectangle(0, 0, size, size)
        cr.fill()
        cr.set_source_rgb(0, 0, 0)
        for y, line in enumerate(matrix):
            for x, dark in enumerate(line):
                if dark:
                    cr.rectangle(x * cell, y * cell, cell + 0.4, cell + 0.4)
        cr.fill()
        return False
    area.connect("draw", draw)
    return area


def mark_secret(text):
    """Tell clipboard history (clips.py) not to keep this copy."""
    from . import clips
    clips.mark_secret(text)


def copy_text(text):
    mark_secret(text)
    Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)


def fetch_password(parent, connection, done):
    """Ask the system helper for a network's password (an administrator's
    password first); done(password) on success, nothing if cancelled."""
    if not os.path.exists(HELPER) or not shutil.which("pkexec"):
        alert.tell(parent, "Can't show Wi-Fi passwords here",
                   "freemac's Wi-Fi password helper isn't installed on this computer.")
        return
    flags = Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
    try:
        proc = Gio.Subprocess.new(["pkexec", HELPER, connection.get_uuid()], flags)
    except GLib.Error as error:
        alert.tell(parent, "The password couldn't be shown.", error.message)
        return

    def finished(p, result):
        try:
            _ok, out, err = p.communicate_utf8_finish(result)
        except GLib.Error:
            out, err = "", ""
        status = p.get_exit_status()
        if status in (126, 127):   # the administrator's password was cancelled
            return
        if status == 3:
            alert.tell(parent, f"“{ssid_text(connection)}” has no password",
                       "Anyone nearby can join this network.")
            return
        if status != 0 or not out:
            alert.tell(parent, "The password couldn't be shown.", (err or "").strip())
            return
        done(out.rstrip("\n"))
    proc.communicate_utf8_async(None, None, finished)


def show_sheet(parent, ssid, password):
    """The password in large type, with a code a phone camera can scan."""
    dialog = Gtk.Dialog(title=f"“{ssid}”", transient_for=parent, modal=True)
    dialog.add_button("Done", Gtk.ResponseType.OK)
    dialog.set_default_response(Gtk.ResponseType.OK)
    box = dialog.get_content_area()
    box.set_spacing(10)
    box.set_border_width(18)
    title = Gtk.Label(xalign=0.5)
    title.set_markup(f"<b>{GLib.markup_escape_text(ssid)}</b>")
    box.pack_start(title, False, False, 0)
    code = qr_area(qr_text(ssid, password))
    if code is not None:
        frame = Gtk.Box(halign=Gtk.Align.CENTER)
        frame.pack_start(code, False, False, 0)
        box.pack_start(frame, False, False, 0)
        hint = Gtk.Label(label="Point a phone's camera at the code to join this network.",
                         wrap=True, max_width_chars=34, justify=Gtk.Justification.CENTER)
        hint.get_style_context().add_class("dials-caption")
        box.pack_start(hint, False, False, 0)
    shown = Gtk.Label(label=password, selectable=True, wrap=True, max_width_chars=30,
                      wrap_mode=Pango.WrapMode.CHAR, justify=Gtk.Justification.CENTER)
    font = Pango.FontDescription("Monospace 15")
    shown.override_font(font)
    box.pack_start(shown, False, False, 4)
    copy = Gtk.Button(label="Copy Password", halign=Gtk.Align.CENTER)
    copy.connect("clicked", lambda b: (copy_text(password), b.set_label("Copied")))
    box.pack_start(copy, False, False, 0)
    dialog.show_all()
    dialog.run()
    dialog.destroy()


class KnownNetworks:
    """Builds the Known Networks group for the Network page."""

    def __init__(self, panel):
        self.panel = panel

    @property
    def client(self):
        return self.panel.client

    def window(self):
        return self.panel.get_toplevel()

    def in_use(self):
        """The UUIDs of the Wi-Fi connections in use now."""
        used = set()
        for active in self.client.get_active_connections() if self.client else []:
            if active.get_connection_type() == "802-11-wireless":
                used.add(active.get_uuid())
        return used

    def sections(self):
        if not self.client:
            return []
        saved = wifi_connections(self.client)
        if not saved:
            return []
        used = self.in_use()
        rows = [self.panel.row("Known Networks", None,
                               "Wi-Fi networks this computer has joined. It joins them again "
                               "by itself when they're in range.")]
        for connection in saved[:SHOWN]:
            rows.append(self.network_row(connection, connection.get_uuid() in used))
        return [self.panel.group(*rows)]

    def network_row(self, connection, using):
        ssid = ssid_text(connection)
        parts = ["Connected" if using else last_used(connection)]
        if not connection.get_setting_connection().get_autoconnect():
            parts.append("Doesn't join automatically")
        if not secured(connection):
            parts.append("Open")
        more = Gtk.MenuButton(image=Gtk.Image.new_from_icon_name("view-more-symbolic", Gtk.IconSize.BUTTON))
        more.set_tooltip_text(f"More for “{ssid}”")
        menu = Gtk.Menu()
        has_password = secured(connection)
        copy = Gtk.MenuItem(label="Copy Password", sensitive=has_password)
        copy.connect("activate", lambda _m: self.copy_password(connection))
        menu.append(copy)
        show = Gtk.MenuItem(label="Show Password and Code…" if has_password else "Show Code…")
        show.connect("activate", lambda _m: self.show_password(connection))
        menu.append(show)
        menu.append(Gtk.SeparatorMenuItem())
        auto = Gtk.CheckMenuItem(label="Join Automatically",
                                 active=connection.get_setting_connection().get_autoconnect())
        auto.connect("toggled", lambda item: self.set_autojoin(connection, item.get_active()))
        menu.append(auto)
        forget = Gtk.MenuItem(label="Forget This Network…")
        forget.connect("activate", lambda _m: self.forget(connection))
        menu.append(forget)
        menu.show_all()
        more.set_popup(menu)
        return self.panel.row(ssid, more, " · ".join(parts))

    def copy_password(self, connection):
        fetch_password(self.window(), connection, copy_text)

    def show_password(self, connection):
        ssid = ssid_text(connection)
        if not secured(connection):
            show_sheet(self.window(), ssid, "")
            return
        fetch_password(self.window(), connection, lambda password: show_sheet(self.window(), ssid, password))

    def set_autojoin(self, connection, on):
        setting = connection.get_setting_connection()
        if setting.get_autoconnect() == on:
            return
        setting.set_property(NM.SETTING_CONNECTION_AUTOCONNECT, on)

        def saved(conn, result):
            try:
                conn.commit_changes_finish(result)
            except GLib.Error as error:
                alert.tell(self.window(), "The change couldn't be saved.", error.message)
            self.panel.schedule()
        connection.commit_changes_async(True, None, saved)

    def forget(self, connection):
        ssid = ssid_text(connection)
        if secured(connection):
            text = ("This computer won't join it by itself any more, and its password is "
                    "removed. You can join it again later with the password.")
        else:
            text = "This computer won't join it by itself any more. You can join it again later."
        answer = alert.ask(self.window(), f"Forget “{ssid}”?", text,
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Forget", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return

        def deleted(conn, result):
            try:
                conn.delete_finish(result)
            except GLib.Error as error:
                alert.tell(self.window(), f"“{ssid}” couldn't be forgotten.", error.message)
            self.panel.schedule()
        connection.delete_async(None, deleted)
