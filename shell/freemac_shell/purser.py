# SPDX-License-Identifier: GPL-3.0-or-later
"""Purser: the passwords this computer keeps for you, in one place.

Like a ship's purser, who keeps the passengers' valuables, Purser keeps your
passwords. It opens locked: your own login password unlocks it (a polkit
check, org.freemac.passwords.unlock, which remembers the answer for a few
minutes), and it locks again when it has been in the background for five
minutes or when you choose Lock (⌘L).

On the left, three lists:

    All Passwords   every website login Web has saved, or you added here
    Wi-Fi           the Wi-Fi networks this computer has joined
    Security        logins whose password is used on more than one site, or
                    is easy to guess

In the middle the logins (search with ⌘F), on the right the chosen one: its
user name and password (shown on request), each with Copy, and the website.
Edit changes them, + (⌘N) adds one with a strong password filled in, Delete
removes one after asking. A copied password is marked so clipboard history
doesn't keep it.

Website logins live in the login keychain (logins.py); Wi-Fi passwords are
kept for the whole computer, so showing one asks for an administrator's
password, as Dials > Network does (known_networks.py). A login can also keep
a verification code for two-step sign-in (codes.py), shown beside it and
listed under Codes. Original freemac code.
"""
import os
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert, codes, known_networks, logins, menus, style  # noqa: E402

APP_ID = "org.freemac.Purser"
ACTION = "org.freemac.passwords.unlock"
LOCK_AFTER = 5 * 60   # seconds in the background before Purser locks
TINTS = ("#5b6fd6", "#3f9dd6", "#34a58f", "#d08a3c", "#b46fb8", "#cf6767", "#6f8fa6")

CSS = b"""
.purser-side row { padding: 7px 10px; }
.purser-count { color: alpha(currentColor, 0.5); font-size: 12px; }
.purser-list row { padding: 6px 12px; }
.purser-sub { color: alpha(currentColor, 0.6); font-size: 12px; }
.purser-search { margin: 8px; }
.purser-title { font-size: 22px; font-weight: 700; }
.purser-label { color: alpha(currentColor, 0.55); font-size: 12px; }
.purser-value { font-size: 14px; }
.purser-secret { font-family: Monospace; font-size: 14px; }
.purser-empty { color: alpha(currentColor, 0.45); font-size: 15px; }
.purser-warning { background: alpha(#e5a52e, 0.16); border-radius: 8px; padding: 10px 12px; }
.purser-locked-title { font-size: 20px; font-weight: 700; }
.purser-code { font-family: Monospace; font-size: 22px; font-weight: 700; letter-spacing: 1px; }
.purser-left { color: alpha(currentColor, 0.55); font-size: 12px; min-width: 34px; }
"""


def tile(text, size):
    """A rounded square with a site's first letter, in a colour of its own."""
    area = Gtk.DrawingArea()
    area.set_size_request(size, size)
    tint = Gdk.RGBA()
    tint.parse(TINTS[sum(map(ord, text or "?")) % len(TINTS)])
    letter = (text or "?")[:1].upper()

    def draw(_w, cr):
        r = size * 0.22
        cr.new_sub_path()
        cr.arc(size - r, r, r, -1.5708, 0)
        cr.arc(size - r, size - r, r, 0, 1.5708)
        cr.arc(r, size - r, r, 1.5708, 3.1416)
        cr.arc(r, r, r, 3.1416, 4.7124)
        cr.close_path()
        cr.set_source_rgba(tint.red, tint.green, tint.blue, 1)
        cr.fill()
        layout = area.create_pango_layout(letter)
        font = Pango.FontDescription("Sans Bold")
        font.set_absolute_size(size * 0.5 * Pango.SCALE)
        layout.set_font_description(font)
        w, h = layout.get_pixel_size()
        cr.set_source_rgb(1, 1, 1)
        cr.move_to((size - w) / 2, (size - h) / 2)
        from gi.repository import PangoCairo
        PangoCairo.show_layout(cr, layout)
        return False
    area.connect("draw", draw)
    return area


def copy_secret(text):
    known_networks.copy_text(text)


def copy_plain(text):
    Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)


def when(stamp):
    if not stamp:
        return ""
    day = GLib.DateTime.new_from_unix_local(stamp)
    return "Changed " + day.format("%B %-d, %Y")


# -- unlocking -------------------------------------------------------------
def _start_time():
    """This process's start time, as polkit names a process."""
    with open("/proc/self/stat") as f:
        fields = f.read().rsplit(")", 1)[1].split()
    return int(fields[19])


def ask_unlock(done):
    """Ask polkit whether this person may see their passwords; polkit's agent
    asks for their own password. done(True) when they gave it."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        subject = ("unix-process", {"pid": GLib.Variant("u", os.getpid()),
                                    "start-time": GLib.Variant("t", _start_time()),
                                    "uid": GLib.Variant("i", os.getuid())})
        args = GLib.Variant("((sa{sv})sa{ss}us)", (subject, ACTION, {}, 1, ""))
    except (GLib.Error, OSError, ValueError, IndexError):
        done(None)
        return

    def answered(conn, result):
        try:
            reply = conn.call_finish(result)
            done(bool(reply.unpack()[0][0]))
        except GLib.Error:
            done(None)
    bus.call("org.freedesktop.PolicyKit1", "/org/freedesktop/PolicyKit1/Authority",
             "org.freedesktop.PolicyKit1.Authority", "CheckAuthorization", args,
             GLib.VariantType("((bba{ss}))"), Gio.DBusCallFlags.NONE, GLib.MAXINT, None, answered)


# -- the right-hand side -----------------------------------------------------
def field_row(grid, row, label, widget, *buttons):
    name = Gtk.Label(label=label, xalign=1, valign=Gtk.Align.CENTER)
    name.get_style_context().add_class("purser-label")
    grid.attach(name, 0, row, 1, 1)
    line = Gtk.Box(spacing=6)
    line.pack_start(widget, True, True, 0)
    for button in buttons:
        button.set_valign(Gtk.Align.CENTER)
        line.pack_start(button, False, False, 0)
    grid.attach(line, 1, row, 1, 1)


def value_label(text, secret=False):
    label = Gtk.Label(label=text, xalign=0, selectable=not secret, ellipsize=Pango.EllipsizeMode.END)
    label.get_style_context().add_class("purser-secret" if secret else "purser-value")
    return label


def small_button(label, tip=None, icon=None):
    button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON) if icon else Gtk.Button(label=label)
    if tip:
        button.set_tooltip_text(tip)
    return button


def page_box():
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    for side in ("start", "end"):
        getattr(box, f"set_margin_{side}")(32)
    box.set_margin_top(26)
    box.set_margin_bottom(26)
    return box


class LoginCard(Gtk.ScrolledWindow):
    """One login to read, or (editing) to change; also a new one."""

    def __init__(self, win, login, editing=False):
        super().__init__(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.win, self.login, self.editing = win, login, editing
        box = page_box()
        self.add(box)
        top = Gtk.Box(spacing=16)
        top.pack_start(tile(login.site if login else "+", 64), False, False, 0)
        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        title = Gtk.Label(label=login.site if login else "New Password", xalign=0,
                          ellipsize=Pango.EllipsizeMode.END)
        title.get_style_context().add_class("purser-title")
        names.pack_start(title, False, False, 0)
        if login and login.modified:
            sub = Gtk.Label(label=when(login.modified), xalign=0)
            sub.get_style_context().add_class("purser-sub")
            names.pack_start(sub, False, False, 0)
        top.pack_start(names, True, True, 0)
        box.pack_start(top, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)
        grid = Gtk.Grid(column_spacing=14, row_spacing=12)
        box.pack_start(grid, False, False, 0)
        if editing:
            self.website = Gtk.Entry(text=login.origin if login else "", placeholder_text="example.com",
                                     activates_default=True, hexpand=True)
            self.username = Gtk.Entry(text=login.username if login else "", placeholder_text="name@example.com",
                                      activates_default=True)
            self.password = Gtk.Entry(text=login.password if login else logins.strong_password(),
                                      activates_default=True)
            self.password.get_style_context().add_class("purser-secret")
            suggest = small_button("Suggest", "A new strong password")
            suggest.connect("clicked", lambda *_: self.password.set_text(logins.strong_password()))
            field_row(grid, 0, "Website", self.website)
            field_row(grid, 1, "User name", self.username)
            field_row(grid, 2, "Password", self.password, suggest)
            hint = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
            hint.get_style_context().add_class("purser-sub")
            self.hint = hint
            self.password.connect("changed", lambda *_: self._update_hint())
            self._update_hint()
            box.pack_start(hint, False, False, 0)
            if login and login.key() in win.codes:
                drop = Gtk.Button(label="Remove Verification Code…", halign=Gtk.Align.START)
                drop.connect("clicked", lambda *_: win.remove_code(login))
                box.pack_start(drop, False, False, 0)
            if login:
                delete = Gtk.Button(label="Delete Login…", halign=Gtk.Align.START)
                delete.get_style_context().add_class("destructive-action")
                delete.connect("clicked", lambda *_: win.delete_chosen())
                box.pack_start(delete, False, False, 6)
            GLib.idle_add(lambda: (self.website if not login else self.password).grab_focus() and False)
            return
        copy_name = small_button("Copy", "Copy User Name")
        copy_name.connect("clicked", lambda b: (copy_plain(login.username), b.set_label("Copied")))
        field_row(grid, 0, "User name", value_label(login.username or "—"), copy_name)
        self.shown = value_label("•" * 12, secret=True)
        self.eye = small_button(None, "Show Password", "view-reveal-symbolic")
        self.eye.connect("clicked", lambda *_: self.toggle_password())
        copy_password = small_button("Copy", "Copy Password (⇧⌘C)")
        copy_password.connect("clicked", lambda b: (copy_secret(login.password), b.set_label("Copied")))
        field_row(grid, 1, "Password", self.shown, self.eye, copy_password)
        site = Gtk.LinkButton(uri=login.origin, label=login.origin, halign=Gtk.Align.START)
        site.get_child().set_ellipsize(Pango.EllipsizeMode.END)
        field_row(grid, 2, "Website", site)
        self.code = win.codes.get(login.key())
        if self.code is not None:
            self.code_label = Gtk.Label(xalign=0)
            self.code_label.get_style_context().add_class("purser-code")
            self.code_left = Gtk.Label(xalign=1)
            self.code_left.get_style_context().add_class("purser-left")
            copy_code = small_button("Copy", "Copy Verification Code (⌥⌘C)")
            copy_code.connect("clicked", lambda b: (copy_secret(self.code.now()[0]), b.set_label("Copied")))
            field_row(grid, 3, "Code", self.code_label, self.code_left, copy_code)
            self.tick()
            timer = GLib.timeout_add(500, self.tick)
            self.connect("destroy", lambda *_: GLib.source_remove(timer))
        for problem in logins.problems(login, win.shared):
            note = Gtk.Box(spacing=10)
            note.get_style_context().add_class("purser-warning")
            note.pack_start(Gtk.Image.new_from_icon_name("dialog-warning-symbolic", Gtk.IconSize.BUTTON),
                            False, False, 0)
            text = Gtk.Label(label=problem + " Change it on the website, then here.", xalign=0,
                             wrap=True, max_width_chars=50)
            note.pack_start(text, True, True, 0)
            box.pack_start(note, False, False, 0)
        if not login.fillable:
            hint = Gtk.Label(label="Added here. Copy it into the website's sign-in page; once Web saves "
                                   "the login there, it fills it in for you.",
                             xalign=0, wrap=True, max_width_chars=50)
            hint.get_style_context().add_class("purser-sub")
            box.pack_start(hint, False, False, 0)
        if self.code is None:
            setup = Gtk.Button(label="Set Up Verification Code…", halign=Gtk.Align.START)
            setup.set_tooltip_text("Keep the codes this website asks for when you sign in in two steps")
            setup.connect("clicked", lambda *_: win.set_up_code(login))
            box.pack_start(setup, False, False, 0)

    def tick(self):
        text, left = self.code.now()
        self.code_label.set_text(codes.shown(text))
        self.code_left.set_text(f"{left} s")
        return True

    def _update_hint(self):
        text = self.password.get_text()
        if not text:
            self.hint.set_text("")
        elif logins.easy_to_guess(text):
            self.hint.set_text("This password is easy to guess. Suggest makes a strong one.")
        elif any(l.password == text and l is not self.login for l in self.win.logins):
            self.hint.set_text("You already use this password on another website.")
        else:
            self.hint.set_text("Strong password.")

    def toggle_password(self):
        hidden = self.shown.get_text() == "•" * 12
        self.shown.set_text(self.login.password if hidden else "•" * 12)
        self.shown.set_selectable(hidden)
        self.eye.set_image(Gtk.Image.new_from_icon_name(
            "view-conceal-symbolic" if hidden else "view-reveal-symbolic", Gtk.IconSize.BUTTON))
        self.eye.set_tooltip_text("Hide Password" if hidden else "Show Password")

    def result(self):
        return (self.website.get_text().strip(), self.username.get_text().strip(), self.password.get_text())


class NetworkCard(Gtk.ScrolledWindow):
    """A Wi-Fi network: its password and join code, after an administrator's
    password."""

    def __init__(self, win, connection):
        super().__init__(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.win, self.connection = win, connection
        box = page_box()
        self.add(box)
        ssid = known_networks.ssid_text(connection)
        top = Gtk.Box(spacing=16)
        icon = Gtk.Image.new_from_icon_name("network-wireless-symbolic", Gtk.IconSize.DIALOG)
        top.pack_start(icon, False, False, 0)
        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        title = Gtk.Label(label=ssid, xalign=0, ellipsize=Pango.EllipsizeMode.END)
        title.get_style_context().add_class("purser-title")
        names.pack_start(title, False, False, 0)
        sub = Gtk.Label(label=known_networks.last_used(connection), xalign=0)
        sub.get_style_context().add_class("purser-sub")
        names.pack_start(sub, False, False, 0)
        top.pack_start(names, True, True, 0)
        box.pack_start(top, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)
        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.pack_start(self.body, False, False, 0)
        if not known_networks.secured(connection):
            self.show_code("")
            return
        grid = Gtk.Grid(column_spacing=14, row_spacing=12)
        self.body.pack_start(grid, False, False, 0)
        reveal = Gtk.Button(label="Show Password…", halign=Gtk.Align.START)
        reveal.connect("clicked", lambda *_: known_networks.fetch_password(win, connection, self.show_code))
        field_row(grid, 0, "Password", reveal)
        note = Gtk.Label(label="Wi-Fi networks are kept for everyone on this computer, so seeing a "
                               "password needs an administrator's password.",
                         xalign=0, wrap=True, max_width_chars=50)
        note.get_style_context().add_class("purser-sub")
        self.body.pack_start(note, False, False, 0)

    def show_code(self, password):
        for child in self.body.get_children():
            child.destroy()
        ssid = known_networks.ssid_text(self.connection)
        if password:
            grid = Gtk.Grid(column_spacing=14, row_spacing=12)
            copy = small_button("Copy", "Copy Password")
            copy.connect("clicked", lambda b: (copy_secret(password), b.set_label("Copied")))
            shown = value_label(password, secret=True)
            shown.set_selectable(True)
            field_row(grid, 0, "Password", shown, copy)
            self.body.pack_start(grid, False, False, 0)
        else:
            open_note = Gtk.Label(label="This network has no password. Anyone nearby can join it.",
                                  xalign=0, wrap=True, max_width_chars=50)
            open_note.get_style_context().add_class("purser-sub")
            self.body.pack_start(open_note, False, False, 0)
        code = known_networks.qr_area(known_networks.qr_text(ssid, password), 180)
        if code is not None:
            frame = Gtk.Box(halign=Gtk.Align.START)
            frame.pack_start(code, False, False, 0)
            self.body.pack_start(frame, False, False, 0)
            hint = Gtk.Label(label="Point a phone's camera at the code to join this network.", xalign=0)
            hint.get_style_context().add_class("purser-sub")
            self.body.pack_start(hint, False, False, 0)
        self.body.show_all()


# -- the window --------------------------------------------------------------
class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Purser")
        self.set_default_size(940, 580)
        self.set_icon_name("freemac-purser")
        self.logins, self.shared, self.networks, self.codes = [], {}, [], {}
        self.category = "all"
        self.chosen = None      # a Login, or a Wi-Fi connection's UUID
        self.card = None
        self.adding = False
        self.unlocked = False
        self.away_since = None

        header = Gtk.HeaderBar(show_close_button=True)
        header.set_title("Purser")
        self.add_button = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        self.add_button.set_tooltip_text("New Password (⌘N)")
        self.add_button.connect("clicked", lambda *_: self.new_login())
        header.pack_start(self.add_button)
        self.lock_button = Gtk.Button.new_from_icon_name("changes-prevent-symbolic", Gtk.IconSize.BUTTON)
        self.lock_button.set_tooltip_text("Lock Purser (⌘L)")
        self.lock_button.connect("clicked", lambda *_: self.lock())
        header.pack_start(self.lock_button)
        self.edit_button = Gtk.Button(label="Edit")
        self.edit_button.set_tooltip_text("Edit (⌘E)")
        self.edit_button.connect("clicked", lambda *_: self.toggle_editing())
        header.pack_end(self.edit_button)
        self.set_titlebar(header)
        header.show_all()

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.stack.add_named(self.locked_page(), "locked")
        self.stack.add_named(self.main_page(), "main")
        self.add(self.stack)

        menus.add_actions(self, {
            "new-login": self.new_login, "edit": self.toggle_editing, "delete": self.delete_chosen,
            "find": lambda: self.search.grab_focus(), "lock": self.lock, "close": self.close,
            "copy-password": self.copy_chosen_password, "copy-username": self.copy_chosen_username,
            "copy-code": self.copy_chosen_code,
        })
        self.connect("key-press-event", self._key)
        self.connect("focus-in-event", self._focus_in)
        self.connect("focus-out-event", self._focus_out)
        GLib.timeout_add_seconds(20, self._check_away)
        self.show_all()
        self.show_locked()
        GLib.idle_add(self.unlock)

    # -- locked ------------------------------------------------------------
    def locked_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, valign=Gtk.Align.CENTER,
                      halign=Gtk.Align.CENTER)
        icon = Gtk.Image.new_from_icon_name("freemac-purser", Gtk.IconSize.DIALOG)
        icon.set_pixel_size(96)
        box.pack_start(icon, False, False, 0)
        title = Gtk.Label(label="Purser is locked")
        title.get_style_context().add_class("purser-locked-title")
        box.pack_start(title, False, False, 0)
        self.locked_text = Gtk.Label(label="Enter your login password to see your saved passwords.",
                                     wrap=True, max_width_chars=40, justify=Gtk.Justification.CENTER)
        self.locked_text.get_style_context().add_class("purser-sub")
        box.pack_start(self.locked_text, False, False, 0)
        self.unlock_button = Gtk.Button(label="Unlock…", halign=Gtk.Align.CENTER)
        self.unlock_button.get_style_context().add_class("suggested-action")
        self.unlock_button.connect("clicked", lambda *_: self.unlock())
        box.pack_start(self.unlock_button, False, False, 6)
        return box

    def show_locked(self):
        self.stack.set_visible_child_name("locked")
        for button in (self.add_button, self.lock_button, self.edit_button):
            button.set_sensitive(False)

    def unlock(self):
        self.unlock_button.set_sensitive(False)

        def answered(ok):
            self.unlock_button.set_sensitive(True)
            if ok is None:
                self.locked_text.set_text("Purser couldn't check your password. Try again in a moment.")
            elif ok:
                self.open_up()
        ask_unlock(answered)
        return False

    def open_up(self):
        if not self.read_all():
            return
        self.unlocked = True
        self.stack.set_visible_child_name("main")
        self.add_button.set_sensitive(True)
        self.lock_button.set_sensitive(True)
        self.fill_lists()
        self.search.grab_focus()

    def lock(self):
        if not self.unlocked:
            return
        self.unlocked = False
        self.logins, self.shared, self.codes = [], {}, {}
        self.adding = False
        self.card = None
        self.chosen = None
        for row in self.listbox.get_children():
            row.destroy()
        for child in self.right.get_children():
            child.destroy()
        self.locked_text.set_text("Enter your login password to see your saved passwords.")
        self.show_locked()

    def _focus_out(self, *_):
        self.away_since = time.monotonic()
        return False

    def _focus_in(self, *_):
        self.away_since = None
        if self.unlocked and not (self.card and getattr(self.card, "editing", False)):
            # Web may have saved a login meanwhile.
            self.reload()
        return False

    def _check_away(self):
        if self.unlocked and self.away_since and time.monotonic() - self.away_since > LOCK_AFTER:
            self.lock()
        return True

    # -- reading -------------------------------------------------------------
    def read_all(self):
        try:
            self.logins = logins.load()
        except GLib.Error as error:
            self.locked_text.set_text("Your saved passwords can't be read right now: the keychain "
                                      "isn't running. " + (error.message or ""))
            return False
        self.shared = logins.reused(self.logins)
        try:
            self.codes = codes.load()
        except Exception:   # passwords still work without codes
            self.codes = {}
        self.networks = self._read_networks()
        return True

    def _read_networks(self):
        if known_networks.NM is None:
            return []
        if not hasattr(self, "nm"):
            try:
                self.nm = known_networks.NM.Client.new(None)
            except GLib.Error:
                self.nm = None
        return known_networks.wifi_connections(self.nm) if self.nm else []

    def reload(self):
        before = (sorted((l.key(), l.password) for l in self.logins),
                  [c.get_uuid() for c in self.networks], sorted(self.codes))
        if not self.read_all():
            return
        after = (sorted((l.key(), l.password) for l in self.logins),
                 [c.get_uuid() for c in self.networks], sorted(self.codes))
        if before != after:
            if isinstance(self.chosen, logins.Login):
                self.chosen = next((l for l in self.logins if l.key() == self.chosen.key()), None)
            self.fill_lists()

    # -- the main page ---------------------------------------------------------
    def main_page(self):
        paned = Gtk.Paned()
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.set_size_request(190, -1)
        self.categories = Gtk.ListBox()
        self.categories.get_style_context().add_class("purser-side")
        self.category_counts = {}
        for key, icon, name in (("all", "dialog-password-symbolic", "All Passwords"),
                                ("codes", "preferences-system-time-symbolic", "Codes"),
                                ("wifi", "network-wireless-symbolic", "Wi-Fi"),
                                ("security", "dialog-warning-symbolic", "Security")):
            row = Gtk.ListBoxRow()
            row.key = key
            line = Gtk.Box(spacing=8)
            line.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
            line.pack_start(Gtk.Label(label=name, xalign=0), True, True, 0)
            count = Gtk.Label()
            count.get_style_context().add_class("purser-count")
            line.pack_end(count, False, False, 0)
            self.category_counts[key] = count
            row.add(line)
            self.categories.add(row)
        self.categories.connect("row-selected", self._category_selected)
        side.pack_start(self.categories, False, False, 6)
        inner = Gtk.Paned()
        middle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        middle.set_size_request(260, -1)
        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.get_style_context().add_class("purser-search")
        self.search.connect("search-changed", lambda *_: self.fill_list())
        self.search.connect("activate", lambda *_: self._first_match())
        middle.pack_start(self.search, False, False, 0)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.listbox = Gtk.ListBox()
        self.listbox.get_style_context().add_class("purser-list")
        self.listbox.connect("row-selected", self._row_selected)
        scroll.add(self.listbox)
        middle.pack_start(scroll, True, True, 0)
        self.right = Gtk.Box()
        inner.pack1(middle, False, False)
        inner.pack2(self.right, True, False)
        paned.pack1(side, False, False)
        paned.pack2(inner, True, False)
        return paned

    def shown_category(self):
        if self.category == "wifi":
            return self.networks
        if self.category == "security":
            return [l for l in self.logins if logins.problems(l, self.shared)]
        if self.category == "codes":
            return [l for l in self.logins if l.key() in self.codes]
        return self.logins

    def fill_lists(self):
        self.category_counts["all"].set_text(str(len(self.logins)))
        self.category_counts["wifi"].set_text(str(len(self.networks)))
        with_code = sum(1 for l in self.logins if l.key() in self.codes)
        self.category_counts["codes"].set_text(str(with_code) if with_code else "")
        trouble = sum(1 for l in self.logins if logins.problems(l, self.shared))
        self.category_counts["security"].set_text(str(trouble) if trouble else "")
        row = next(r for r in self.categories.get_children() if r.key == self.category)
        if self.categories.get_selected_row() is not row:
            self.categories.select_row(row)
        self.fill_list()

    def _category_selected(self, _box, row):
        if row is None or row.key == self.category and self.listbox.get_children():
            return
        if self.card and getattr(self.card, "editing", False) and not self.finish_editing():
            return
        self.category = row.key
        self.chosen = None
        self.adding = False
        self.fill_list()

    def fill_list(self):
        words = self.search.get_text().strip()
        for row in self.listbox.get_children():
            row.destroy()
        chosen_row, first = None, None
        for thing in self.shown_category():
            if self.category == "wifi":
                title = known_networks.ssid_text(thing)
                sub = known_networks.last_used(thing)
                key = thing.get_uuid()
                if words and words.lower() not in title.lower():
                    continue
            else:
                if words and not thing.matches(words):
                    continue
                title, sub, key = thing.site, thing.username or "No user name", thing.key()
            row = Gtk.ListBoxRow()
            row.thing = thing
            row.key = key
            line = Gtk.Box(spacing=10)
            if self.category == "wifi":
                line.pack_start(Gtk.Image.new_from_icon_name("network-wireless-symbolic", Gtk.IconSize.DND),
                                False, False, 0)
            else:
                line.pack_start(tile(title, 30), False, False, 0)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            name = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
            name.set_markup(f"<b>{GLib.markup_escape_text(title)}</b>")
            text.pack_start(name, False, False, 0)
            detail = Gtk.Label(label=sub, xalign=0, ellipsize=Pango.EllipsizeMode.END)
            detail.get_style_context().add_class("purser-sub")
            text.pack_start(detail, False, False, 0)
            line.pack_start(text, True, True, 0)
            row.add(line)
            self.listbox.add(row)
            first = first or row
            if self._chosen_key() == key:
                chosen_row = row
        self.listbox.show_all()
        if not self.adding:
            target = chosen_row or first
            if target:
                self.listbox.select_row(target)
            else:
                self.chosen = None
                self.show_card()

    def _chosen_key(self):
        if isinstance(self.chosen, logins.Login):
            return self.chosen.key()
        return self.chosen

    def _row_selected(self, _box, row):
        if row is None:
            return
        if self.card and getattr(self.card, "editing", False):
            same = self.card.login is not None and isinstance(row.thing, logins.Login) \
                and row.thing.key() == self.card.login.key()
            if not same and not self.finish_editing():
                return
        self.adding = False
        self.chosen = row.thing if self.category != "wifi" else row.key
        self.show_card()

    def _first_match(self):
        row = self.listbox.get_row_at_index(0)
        if row:
            self.listbox.select_row(row)

    def chosen_network(self):
        return next((c for c in self.networks if c.get_uuid() == self.chosen), None)

    def show_card(self, editing=False):
        for child in self.right.get_children():
            child.destroy()
        self.card = None
        if self.adding:
            self.card = LoginCard(self, None, editing=True)
        elif self.category == "wifi" and self.chosen_network() is not None:
            self.card = NetworkCard(self, self.chosen_network())
        elif isinstance(self.chosen, logins.Login):
            self.card = LoginCard(self, self.chosen, editing)
        if self.card is None:
            self.right.pack_start(self.empty_page(), True, True, 0)
        else:
            self.right.pack_start(self.card, True, True, 0)
        can_edit = isinstance(self.card, LoginCard)
        self.edit_button.set_sensitive(can_edit)
        editing_now = can_edit and self.card.editing
        self.edit_button.set_label("Done" if editing_now else "Edit")
        context = self.edit_button.get_style_context()
        (context.add_class if editing_now else context.remove_class)("suggested-action")
        self.right.show_all()

    def empty_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        if self.search.get_text().strip():
            head, text = "No Results", "Nothing here matches your search."
        elif self.category == "wifi":
            head, text = "No Wi-Fi Networks", "Networks this computer joins appear here."
        elif self.category == "codes":
            head, text = "No Verification Codes", ("When a website asks for a code from an authenticator "
                                                   "app, choose its login and Set Up Verification Code. "
                                                   "The codes then show here.")
        elif self.category == "security":
            head, text = "No Problems Found", "None of your passwords is used twice or easy to guess."
        elif not self.logins:
            head, text = "No Saved Passwords", ("When you sign in to a website in Web, it offers to save "
                                                "the password here. Or press + to add one.")
        else:
            head, text = "No Login Chosen", ""
        title = Gtk.Label(label=head)
        title.get_style_context().add_class("purser-empty")
        box.pack_start(title, False, False, 0)
        if text:
            sub = Gtk.Label(label=text, wrap=True, max_width_chars=36, justify=Gtk.Justification.CENTER)
            sub.get_style_context().add_class("purser-sub")
            box.pack_start(sub, False, False, 0)
        return box

    # -- changing ------------------------------------------------------------
    def toggle_editing(self):
        if not isinstance(self.card, LoginCard):
            return
        if self.card.editing:
            self.finish_editing()
        else:
            self.show_card(editing=True)

    def finish_editing(self):
        """Save the login being edited; False if it can't be yet."""
        if not (isinstance(self.card, LoginCard) and self.card.editing):
            return True
        website, username, password = self.card.result()
        login = self.card.login
        if login is None and not (website or username) and not self.adding:
            return True
        if not logins.origin_of(website):
            self.card.website.grab_focus()
            self.card.website.get_style_context().add_class("error")
            return False
        if not password:
            self.card.password.grab_focus()
            self.card.password.get_style_context().add_class("error")
            return False
        origin = logins.origin_of(website)
        try:
            if login is None:
                logins.add(website, username, password)
            elif (origin, username, password) != (login.origin, login.username, login.password):
                old = login.key()
                logins.change(login, website, username, password)
                codes.move(*old, origin, username)
        except Exception as error:   # the keychain said no, or isn't there
            alert.tell(self, "The login couldn't be saved.", getattr(error, "message", str(error)))
            return False
        self.adding = False
        self.card.editing = False   # saved: choosing rows below mustn't save it again
        if not self.read_all():
            return True
        self.chosen = next((l for l in self.logins if l.key() == (origin, username)), None)
        if self.category == "wifi":
            self.category = "all"
        self.fill_lists()
        return True

    def cancel_editing(self):
        self.adding = False
        if not self.listbox.get_selected_row():
            self.fill_list()
        self.show_card()

    def new_login(self):
        if not self.unlocked:
            return
        if self.card and getattr(self.card, "editing", False) and not self.finish_editing():
            return
        if self.category in ("wifi", "codes"):
            self.category = "all"
            self.fill_lists()
        self.search.set_text("")
        self.adding = True
        self.listbox.unselect_all()
        self.show_card(editing=True)

    def delete_chosen(self):
        login = self.chosen if isinstance(self.chosen, logins.Login) else None
        if login is None or self.adding or not self.unlocked:
            return
        who = f" for {login.username}" if login.username else ""
        answer = alert.ask(self, f"Delete the login for {login.site}?",
                           f"The password{who} is removed from this computer, and Web won't fill it in "
                           "any more. This can't be undone.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Delete", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        try:
            logins.delete(login)
            if login.key() in self.codes:
                codes.remove(*login.key())
        except Exception as error:
            alert.tell(self, "The login couldn't be deleted.", getattr(error, "message", str(error)))
            return
        rows = self.listbox.get_children()
        at = next((n for n, r in enumerate(rows) if r.key == login.key()), 0)
        self.read_all()
        shown = [l for l in self.shown_category() if l.key() != login.key()]
        self.chosen = shown[min(at, len(shown) - 1)] if shown else None
        self.fill_lists()

    def copy_chosen_code(self):
        if isinstance(self.chosen, logins.Login) and self.unlocked and self.chosen.key() in self.codes:
            copy_secret(self.codes[self.chosen.key()].now()[0])

    def set_up_code(self, login):
        """Ask for a setup key, or read the website's QR code off the screen."""
        dialog = Gtk.Dialog(title="Set Up Verification Code", transient_for=self, modal=True,
                            use_header_bar=True)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        ok = dialog.add_button("Set Up", Gtk.ResponseType.OK)
        ok.get_style_context().add_class("suggested-action")
        dialog.set_default_response(Gtk.ResponseType.OK)
        box = dialog.get_content_area()
        box.set_spacing(12)
        box.set_border_width(20)
        intro = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
        intro.set_markup(
            f"On <b>{GLib.markup_escape_text(login.site)}</b>, turn on two-step sign-in with an "
            "authenticator app. When it shows a QR code, leave it on the screen and choose Scan QR "
            "Code. Or copy the setup key it shows and paste it here.")
        box.pack_start(intro, False, False, 0)
        line = Gtk.Box(spacing=8)
        entry = Gtk.Entry(placeholder_text="Setup key", activates_default=True, hexpand=True)
        entry.get_style_context().add_class("purser-secret")
        line.pack_start(entry, True, True, 0)
        scan = Gtk.Button(label="Scan QR Code")
        scan.set_tooltip_text("Read the website's QR code from the screen")
        scan.set_sensitive(codes.can_scan())
        line.pack_start(scan, False, False, 0)
        box.pack_start(line, False, False, 0)
        status = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
        status.get_style_context().add_class("purser-sub")
        box.pack_start(status, False, False, 0)
        found = {"code": None}

        def check(*_):
            text = entry.get_text().strip()
            found["code"] = None
            if not text:
                status.set_text("")
            else:
                try:
                    found["code"] = codes.parse(text)
                    now = codes.shown(found["code"].now()[0])
                    status.set_text(f"The code now is {now}. Type it into the website to finish "
                                    "turning on two-step sign-in, then choose Set Up.")
                except codes.BadKey as error:
                    status.set_text(str(error))
            ok.set_sensitive(found["code"] is not None)

        def scanned(texts):
            self.set_opacity(1)
            dialog.set_opacity(1)
            usable = [t for t in texts if t.lower().startswith("otpauth://totp")]
            if not usable:
                status.set_text("No setup QR code was found on the screen. Make sure the website's "
                                "code is showing and not covered, then try again." if not texts else
                                "The QR code on the screen isn't a verification code setup.")
                return
            entry.set_text(usable[0])

        def do_scan(*_):
            status.set_text("Looking at the screen…")
            # See through Purser's windows for a moment (hiding them would
            # lose the dialog behind its window), then read the screen.
            dialog.set_opacity(0)
            self.set_opacity(0)
            GLib.timeout_add(500, lambda: (scanned(codes.scan_screen()), False)[1])

        entry.connect("changed", check)
        scan.connect("clicked", do_scan)
        check()
        dialog.show_all()
        while dialog.run() == Gtk.ResponseType.OK and found["code"] is not None:
            try:
                codes.save(found["code"], *login.key())
            except Exception as error:
                alert.tell(dialog, "The code couldn't be saved.", getattr(error, "message", str(error)))
                continue
            break
        dialog.destroy()
        self.read_all()
        self.fill_lists()

    def remove_code(self, login):
        answer = alert.ask(self, f"Remove the verification code for {login.site}?",
                           "Turn off two-step sign-in on the website first, or set it up again with "
                           "another app, or you may not be able to sign in there.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Remove", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        try:
            codes.remove(*login.key())
        except Exception as error:
            alert.tell(self, "The code couldn't be removed.", getattr(error, "message", str(error)))
            return
        self.read_all()
        if self.category == "codes":
            self.category = "all"   # the login leaves this list; stay on it
        self.fill_lists()
        self.show_card(editing=True)

    def copy_chosen_password(self):
        if isinstance(self.chosen, logins.Login) and self.unlocked:
            copy_secret(self.chosen.password)

    def copy_chosen_username(self):
        if isinstance(self.chosen, logins.Login) and self.unlocked:
            copy_plain(self.chosen.username)

    def _key(self, _w, event):
        command = event.state & Gdk.ModifierType.CONTROL_MASK
        shift = event.state & Gdk.ModifierType.SHIFT_MASK
        key = Gdk.keyval_to_lower(event.keyval)
        editing = isinstance(self.card, LoginCard) and self.card.editing
        typing = isinstance(self.get_focus(), Gtk.Entry)
        if command:
            if shift and key == Gdk.KEY_c:
                self.copy_chosen_password()
                return True
            actions = {Gdk.KEY_n: self.new_login, Gdk.KEY_e: self.toggle_editing, Gdk.KEY_l: self.lock,
                       Gdk.KEY_f: self.search.grab_focus, Gdk.KEY_w: self.close}
            if not typing:
                actions[Gdk.KEY_BackSpace] = self.delete_chosen
            if key in actions:
                actions[key]()
                return True
            return False
        if editing and key == Gdk.KEY_Escape:
            self.cancel_editing()
            return True
        if editing and key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.finish_editing()
            return True
        if not editing and not typing and key in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self.delete_chosen()
            return True
        if not editing and key in (Gdk.KEY_Up, Gdk.KEY_Down) and self.unlocked:
            rows = self.listbox.get_children()
            current = self.listbox.get_selected_row()
            if rows:
                at = rows.index(current) if current in rows else -1
                at = max(0, min(len(rows) - 1, at + (1 if key == Gdk.KEY_Down else -1)))
                self.listbox.select_row(rows[at])
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("New Password", "win.new-login", "<Ctrl>n")],
                   [("Lock Purser", "win.lock", "<Ctrl>l")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Copy Password", "win.copy-password", "<Ctrl><Shift>c"),
                    ("Copy User Name", "win.copy-username", None),
                    ("Copy Verification Code", "win.copy-code", "<Ctrl><Alt>c")],
                   [("Edit Login", "win.edit", "<Ctrl>e"), ("Delete Login", "win.delete", "<Ctrl>BackSpace")],
                   [("Find", "win.find", "<Ctrl>f")]]),
    ])


class Purser(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: GLib.idle_add(self.quit))
        self.add_action(quit_action)
        # Purser quits when its window closes, so the passwords it read go
        # with it; the next window starts locked.
        self.set_menubar(menubar())

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


def main():
    return Purser().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
