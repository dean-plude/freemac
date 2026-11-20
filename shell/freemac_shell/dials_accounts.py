# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Internet Accounts: online calendars, contacts and reminders.

An account (iCloud, Fastmail, Yahoo, Nextcloud or any CalDAV and CardDAV
server) is added once here, and its calendars show in Tide, its address
books in Crew and its reminder lists in Nudge. Each kind can be turned off.
The syncing is done by freemac-sync (dav_sync.py). Original freemac code.
"""
import subprocess
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, dav, dav_sync  # noqa: E402

KINDS = (("calendars", "events", "Calendars", "In Tide"),
         ("contacts", "contacts", "Contacts", "In Crew"),
         ("reminders", "reminders", "Reminders", "In Nudge"))


def sync_now():
    try:
        subprocess.Popen(["freemac-sync"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        pass


def ago(when):
    if not when:
        return "Not synced yet"
    minutes = int((time.time() - when) // 60)
    if minutes < 1:
        return "Synced just now"
    if minutes < 60:
        return f"Synced {minutes} minute{'s' if minutes != 1 else ''} ago"
    hours = minutes // 60
    if hours < 24:
        return f"Synced {hours} hour{'s' if hours != 1 else ''} ago"
    return "Synced " + time.strftime("%b %-d", time.localtime(when))


def mark_error(widget, text):
    """Turn the caption showing text red."""
    if isinstance(widget, Gtk.Label) and widget.get_text() == text:
        widget.get_style_context().add_class("dials-error")
    elif isinstance(widget, Gtk.Container):
        for child in widget.get_children():
            mark_error(child, text)


class AccountsPanel(Gtk.Box):
    def __init__(self, window, page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.window = window
        self.groups = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        buttons = Gtk.Box(spacing=8)
        add = Gtk.Button(label="Add Account…")
        add.connect("clicked", lambda *_: self.add_account())
        buttons.pack_start(add, False, False, 0)
        self.sync_button = Gtk.Button(label="Sync Now", no_show_all=True)   # only with an account
        self.sync_button.connect("clicked", lambda *_: self._sync())
        buttons.pack_start(self.sync_button, False, False, 0)
        intro = Gtk.Label(label="Calendars, contacts and reminders from an online account show in Tide, "
                          "Crew and Nudge, and changes made on this computer go back to it.",
                          xalign=0, wrap=True, max_width_chars=60)
        intro.get_style_context().add_class("dials-caption")
        self.pack_start(page("Internet Accounts", intro, self.groups, buttons), True, True, 0)
        self.monitor = Gio.File.new_for_path(dav_sync.accounts_path()).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", lambda *_: self._later())
        self.pending = None
        GLib.timeout_add_seconds(30, lambda: self.refresh() or True)   # "x minutes ago"
        self.refresh()

    def _later(self):
        if self.pending is None:
            self.pending = GLib.timeout_add(400, self._refresh_once)

    def _refresh_once(self):
        self.pending = None
        self.refresh()
        return False

    def _sync(self):
        sync_now()
        self.sync_button.set_sensitive(False)
        GLib.timeout_add_seconds(3, lambda: self.sync_button.set_sensitive(True) or False)

    def refresh(self):
        group, row, _page, _slider, switch = self.window.helpers
        for child in self.groups.get_children():
            child.destroy()
        accounts = dav_sync.load_accounts()
        self.sync_button.set_visible(bool(accounts))
        if not accounts:
            empty = Gtk.Label(label="No accounts yet.", xalign=0)
            empty.get_style_context().add_class("dials-caption")
            self.groups.pack_start(empty, False, False, 0)
        for account in accounts:
            remove = Gtk.Button(label="Remove…")
            remove.connect("clicked", lambda _b, a=account: self.remove(a))
            status = account.last_error or ago(account.last_sync)
            caption = f"{account.username} · {status}"
            head = row(account.title, remove, caption)
            if account.last_error:
                mark_error(head, caption)
            rows = [head]
            for field, kind, title, where in KINDS:
                rows.append(row(title, switch(getattr(account, field),
                                              lambda on, a=account, f=field, k=kind: self.toggle(a, f, k, on)),
                                where))
            self.groups.pack_start(group(*rows), False, False, 0)
        self.groups.show_all()

    def toggle(self, account, field, kind, on):
        accounts = dav_sync.load_accounts()
        mine = next((a for a in accounts if a.id == account.id), None)
        if mine is None:
            return
        setattr(mine, field, on)
        if on:
            if kind in ("events", "contacts"):
                dav_sync.note_local_only(mine, (kind,))
            dav_sync.save_accounts(accounts)
            sync_now()
        else:
            dav_sync.save_accounts(accounts)
            dav_sync.forget(mine, (kind,))   # off this computer; the account keeps them

    def remove(self, account):
        answer = alert.ask(self.get_toplevel(), f"Remove the {account.title} account?",
                           "Its calendars, contacts and reminders are taken off this computer. "
                           "They stay in the account online.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Remove", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        dav_sync.forget(account)
        dav_sync.set_password(account, None)
        dav_sync.save_accounts([a for a in dav_sync.load_accounts() if a.id != account.id])
        self.refresh()

    def add_account(self):
        AddAccount(self.get_toplevel(), self._added).show_all()

    def _added(self, account, password):
        accounts = dav_sync.load_accounts()
        dav_sync.note_local_only(account)
        accounts.append(account)
        dav_sync.save_accounts(accounts)
        dav_sync.set_password(account, password)
        self.refresh()
        sync_now()


class AddAccount(Gtk.Window):
    def __init__(self, parent, on_done):
        super().__init__(title="Add Account", transient_for=parent, modal=True, resizable=False)
        self.on_done = on_done
        self.set_titlebar(Gtk.HeaderBar(show_close_button=True, title="Add Account"))
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=24)
        box.set_size_request(400, -1)
        self.add(box)
        grid = Gtk.Grid(column_spacing=10, row_spacing=8)
        self.provider = Gtk.ComboBoxText(hexpand=True)
        for key, (name, *_rest) in dav.PROVIDERS.items():
            self.provider.append(key, name)
        self.provider.set_active_id("icloud")
        self.server = Gtk.Entry(placeholder_text="dav.example.com", hexpand=True)
        self.username = Gtk.Entry(placeholder_text="Your email address or user name", hexpand=True)
        self.password = Gtk.Entry(visibility=False, input_purpose=Gtk.InputPurpose.PASSWORD,
                                  placeholder_text="Required", hexpand=True)
        self.server_label = Gtk.Label(label="Server", xalign=1)
        for widget in (self.server, self.server_label):   # shown only for providers that need it
            widget.set_no_show_all(True)
        for n, (label, widget) in enumerate((("Account", self.provider), ("Server", self.server),
                                             ("User name", self.username), ("Password", self.password))):
            text = self.server_label if label == "Server" else Gtk.Label(label=label, xalign=1)
            text.get_style_context().add_class("dials-caption")
            grid.attach(text, 0, n, 1, 1)
            grid.attach(widget, 1, n, 1, 1)
        box.pack_start(grid, False, False, 0)
        self.note = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
        self.note.get_style_context().add_class("dials-caption")
        box.pack_start(self.note, False, False, 0)
        self.error = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
        self.error.get_style_context().add_class("dials-error")
        box.pack_start(self.error, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        self.spinner = Gtk.Spinner()
        buttons.pack_start(self.spinner, False, False, 0)
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_: self.destroy())
        buttons.pack_start(cancel, False, False, 0)
        self.go = Gtk.Button(label="Sign In")
        self.go.get_style_context().add_class("suggested-action")
        self.go.connect("clicked", lambda *_: self.sign_in())
        buttons.pack_start(self.go, False, False, 0)
        box.pack_start(buttons, False, False, 4)
        self.password.connect("activate", lambda *_: self.sign_in())
        self.provider.connect("changed", lambda *_: self._provider_changed())
        self.show_all()
        self._provider_changed()

    def _provider_changed(self):
        key = self.provider.get_active_id()
        _name, caldav, _carddav, note = dav.PROVIDERS[key]
        needs_server = not caldav
        self.server.set_visible(needs_server)
        self.server_label.set_visible(needs_server)
        self.note.set_text(note)

    def sign_in(self):
        provider = self.provider.get_active_id()
        server = self.server.get_text().strip() if self.server.get_visible() else ""
        username, password = self.username.get_text().strip(), self.password.get_text()
        if not username or not password or (self.server.get_visible() and not server):
            self.error.set_text("Fill in every field.")
            return
        self.error.set_text("")
        self.spinner.start()
        self.go.set_sensitive(False)

        def work():
            try:
                calendars, books = dav_sync.check(provider, server, username, password)
            except dav.DavError as error:
                GLib.idle_add(self._failed, str(error.args[0]))
                return
            except OSError as error:
                GLib.idle_add(self._failed, f"Couldn't sign in ({error}).")
                return
            GLib.idle_add(self._worked, provider, server, username, password, calendars, books)
        threading.Thread(target=work, daemon=True).start()

    def _failed(self, text):
        self.spinner.stop()
        self.go.set_sensitive(True)
        self.error.set_text(text)
        return False

    def _worked(self, provider, server, username, password, calendars, books):
        self.spinner.stop()
        if not calendars and not books:
            return self._failed("Signed in, but the account has no calendars or address books.")
        account = dav_sync.Account(provider=provider, server=server, username=username,
                                   calendars=any("VEVENT" in k for *_r, k in calendars),
                                   reminders=any("VTODO" in k for *_r, k in calendars),
                                   contacts=bool(books))
        self.on_done(account, password)
        self.destroy()
        return False
