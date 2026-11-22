# SPDX-License-Identifier: GPL-3.0-or-later
"""Post: mail.

Mailboxes of every account down the side, the messages of the chosen one in
the middle and the chosen message on the right, as in a Mac's mail app.
Messages are read over IMAP and sent over SMTP (mail_store.py); a message
written here opens in a window of its own. HTML mail is shown by WebKit with
scripts off and nothing fetched from the internet until Load Remote Content
is pressed. Original freemac code.
"""
import os
import queue
import sys
import threading

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

try:
    gi.require_version("WebKit2", "4.1")
    from gi.repository import WebKit2  # noqa: E402
except (ValueError, ImportError):   # no WebKit: messages show as text
    WebKit2 = None

from . import alert, launcher_badge, menus, spelling, style  # noqa: E402
from . import mail_store as store  # noqa: E402

APP_ID = "org.freemac.Post"
CHECK_EVERY = 5 * 60    # seconds between looks for new mail
BLUE = "#2f7bf5"

KIND_ICONS = {"inbox": "mail-unread-symbolic", "drafts": "document-edit-symbolic",
              "sent": "mail-send-symbolic", "junk": "mail-mark-junk-symbolic",
              "trash": "user-trash-symbolic", "archive": "folder-symbolic"}

CSS = b"""
.post-side { background: alpha(currentColor, 0.04); }
list.post-side { background: transparent; }
.post-side row { padding: 4px 10px; border-radius: 7px; margin: 0 6px; background: transparent; }
.post-side row:selected { background: alpha(@theme_fg_color, 0.12); }
.post-side row:selected label { color: @theme_fg_color; }
.post-side row:selected image { color: @theme_selected_bg_color; }
.post-side image { color: @theme_selected_bg_color; }
.post-account { font-size: 12px; font-weight: 700; color: alpha(currentColor, 0.5); padding: 12px 14px 2px 14px; }
.post-count { color: alpha(currentColor, 0.5); font-size: 12px; }
.post-list { background: @theme_base_color; }
.post-list row { padding: 7px 12px 7px 6px; border-bottom: 1px solid alpha(currentColor, 0.07); }
.post-list row:selected { background: @theme_selected_bg_color; }
.post-list row:selected label { color: white; }
.post-list row:selected .post-dot { color: white; }
.post-from { font-weight: 700; font-size: 14px; }
.post-from.post-read { font-weight: 500; }
.post-date { font-size: 12px; color: alpha(currentColor, 0.55); }
.post-subject { font-size: 13px; }
.post-dot { color: @theme_selected_bg_color; font-size: 10px; }
.post-flag { color: #f59a23; font-size: 11px; }
.post-head { padding: 14px 20px 10px 20px; border-bottom: 1px solid alpha(currentColor, 0.1); background: @theme_base_color; }
.post-head-from { font-size: 16px; font-weight: 700; }
.post-head-line { font-size: 12px; color: alpha(currentColor, 0.65); }
.post-head-subject { font-size: 14px; font-weight: 600; }
.post-tile { border-radius: 99px; color: white; font-weight: 700; font-size: 16px; }
.post-remote { padding: 6px 20px; background: alpha(#f59a23, 0.12); font-size: 12px; }
.post-files { padding: 6px 16px; border-bottom: 1px solid alpha(currentColor, 0.1); background: @theme_base_color; }
.post-files button { padding: 2px 8px; }
.post-empty { color: alpha(currentColor, 0.4); font-size: 16px; }
.post-plain { font-size: 14px; }
.post-compose-field { border-bottom: 1px solid alpha(currentColor, 0.1); padding: 2px 12px; background: @theme_base_color; }
.post-compose-field label { color: alpha(currentColor, 0.55); min-width: 56px; }
.post-compose-field entry { border: none; box-shadow: none; background: none; min-height: 30px; }
.post-compose-body, .post-compose-body text { font-size: 14px; }
.post-chip { background: alpha(currentColor, 0.08); border-radius: 6px; padding: 2px 4px 2px 8px; }
.post-setup { padding: 30px; }
.post-setup-title { font-size: 22px; font-weight: 700; }
.post-setup-note { color: alpha(currentColor, 0.6); font-size: 12px; }
.post-setup-error { color: #f04d3e; font-size: 12px; }
"""

TINTS = ("#8e9bb0", "#7aa2c8", "#87b39a", "#c4a07a", "#b48fb8", "#c58b8b", "#8fb3b3")


def icon_name(*names):
    theme = Gtk.IconTheme.get_default()
    return next((n for n in names if theme.has_icon(n)), names[-1])


def open_uri(uri):
    try:
        Gio.AppInfo.launch_default_for_uri(uri, None)
    except GLib.Error:
        pass


# --- background work ----------------------------------------------------------
class Worker(threading.Thread):
    """One account's mail server, talked to on a thread of its own, one
    request at a time; answers come back on GTK's thread."""

    def __init__(self, account, password):
        super().__init__(daemon=True)
        self.session = store.Session(account, password)
        self.jobs = queue.Queue()
        self.start()

    def submit(self, work, done=None, failed=None):
        self.jobs.put((work, done, failed))

    def stop(self):
        self.jobs.put(None)

    def run(self):
        while True:
            job = self.jobs.get()
            if job is None:
                self.session.close()
                return
            work, done, failed = job
            try:
                result = self.session.run(work)
            except store.MailError as error:
                if failed:
                    GLib.idle_add(failed, str(error))
                continue
            except Exception as error:   # never let one bad answer stop the thread
                if failed:
                    GLib.idle_add(failed, f"Something went wrong: {error}")
                continue
            if done:
                GLib.idle_add(done, result)


def in_background(work, done, failed):
    """For sending: a short-lived thread of its own."""
    def run():
        try:
            result = work()
        except store.MailError as error:
            GLib.idle_add(failed, str(error))
        except Exception as error:
            GLib.idle_add(failed, f"Something went wrong: {error}")
        else:
            GLib.idle_add(done, result)
    threading.Thread(target=run, daemon=True).start()


# --- account set-up -------------------------------------------------------------
class AccountForm(Gtk.Box):
    """Name, address and password; the servers fill themselves in and can be
    changed under Server Settings."""

    def __init__(self, on_done, on_cancel=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.get_style_context().add_class("post-setup")
        self.on_done, self.on_cancel = on_done, on_cancel
        self.labels = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        self.set_size_request(420, -1)
        title = Gtk.Label(label="Add a Mail Account", xalign=0)
        title.get_style_context().add_class("post-setup-title")
        self.pack_start(title, False, False, 0)
        sub = Gtk.Label(label="Post signs in to your mail with your address and password.", xalign=0, wrap=True)
        sub.get_style_context().add_class("post-setup-note")
        self.pack_start(sub, False, False, 4)

        grid = Gtk.Grid(column_spacing=10, row_spacing=8)
        self.name = self._row(grid, 0, "Name", "Your full name")
        self.name.set_text(GLib.get_real_name() if GLib.get_real_name() not in ("", "Unknown") else "")
        self.address = self._row(grid, 1, "Email", "name@example.com")
        self.password = self._row(grid, 2, "Password", "Required")
        self.password.set_visibility(False)
        self.password.set_input_purpose(Gtk.InputPurpose.PASSWORD)
        self.pack_start(grid, False, False, 0)
        self.note = Gtk.Label(xalign=0, wrap=True, max_width_chars=50)
        self.note.get_style_context().add_class("post-setup-note")
        self.pack_start(self.note, False, False, 0)

        more = Gtk.Expander(label="Server Settings")
        servers = Gtk.Grid(column_spacing=10, row_spacing=8, margin_top=2)
        self.imap_host = self._row(servers, 0, "Incoming", "imap.example.com")
        self.imap_port = self._row(servers, 1, "Port", "993")
        self.smtp_host = self._row(servers, 2, "Outgoing", "smtp.example.com")
        self.smtp_port = self._row(servers, 3, "Port", "465")
        self.username = self._row(servers, 4, "User name", "Same as the email address")
        self.secure = Gtk.CheckButton(label="Use an encrypted connection (TLS)", active=True)
        servers.attach(self.secure, 1, 5, 1, 1)
        servers.set_no_show_all(True)
        for child in servers.get_children():
            child.show()
        more.connect("notify::expanded", lambda e, _p: servers.set_visible(e.get_expanded()))
        self.pack_start(more, False, False, 0)
        self.pack_start(servers, False, False, 0)
        self.edited = False
        for entry in (self.imap_host, self.imap_port, self.smtp_host, self.smtp_port):
            entry.connect("changed", self._servers_edited)
        self.address.connect("changed", lambda *_: self._fill_servers())
        self.address.connect("activate", lambda *_: self.password.grab_focus())
        self.password.connect("activate", lambda *_: self._sign_in())

        self.error = Gtk.Label(xalign=0, wrap=True, max_width_chars=50)
        self.error.get_style_context().add_class("post-setup-error")
        self.pack_start(self.error, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        self.spinner = Gtk.Spinner()
        buttons.pack_start(self.spinner, False, False, 0)
        if on_cancel:
            cancel = Gtk.Button(label="Cancel")
            cancel.connect("clicked", lambda *_: on_cancel())
            buttons.pack_start(cancel, False, False, 0)
        self.go = Gtk.Button(label="Sign In")
        self.go.get_style_context().add_class("suggested-action")
        self.go.connect("clicked", lambda *_: self._sign_in())
        buttons.pack_start(self.go, False, False, 0)
        self.pack_start(buttons, False, False, 6)
        self._filling = False

    def _row(self, grid, row, label, hint):
        text = Gtk.Label(label=label, xalign=1)
        text.get_style_context().add_class("post-setup-note")
        self.labels.add_widget(text)
        entry = Gtk.Entry(placeholder_text=hint, hexpand=True)
        grid.attach(text, 0, row, 1, 1)
        grid.attach(entry, 1, row, 1, 1)
        return entry

    def _servers_edited(self, *_):
        if not self._filling:
            self.edited = True

    def _fill_servers(self):
        address = self.address.get_text().strip()
        if "@" not in address:
            self.note.set_text("")
            return
        imap, iport, smtp, sport, note = store.guess_servers(address)
        self.note.set_text(note)
        if self.edited:
            return
        self._filling = True
        self.imap_host.set_text(imap)
        self.imap_port.set_text(str(iport))
        self.smtp_host.set_text(smtp)
        self.smtp_port.set_text(str(sport))
        self._filling = False

    def _sign_in(self):
        address = self.address.get_text().strip()
        password = self.password.get_text()
        if "@" not in address or not password:
            self.error.set_text("Type your email address and password.")
            return
        try:
            iport, sport = int(self.imap_port.get_text() or 993), int(self.smtp_port.get_text() or 465)
        except ValueError:
            self.error.set_text("A port is a number, like 993.")
            return
        account = store.Account(name=self.name.get_text().strip(), address=address,
                                imap_host=self.imap_host.get_text().strip(), imap_port=iport,
                                smtp_host=self.smtp_host.get_text().strip(), smtp_port=sport,
                                username=self.username.get_text().strip(), secure=self.secure.get_active())
        self.error.set_text("")
        self.spinner.start()
        self.go.set_sensitive(False)

        def done(_result):
            self.spinner.stop()
            self.go.set_sensitive(True)
            self.on_done(account, password)

        def failed(message):
            self.spinner.stop()
            self.go.set_sensitive(True)
            self.error.set_text(message)
        in_background(lambda: store.check_account(account, password), done, failed)


# --- the main window --------------------------------------------------------------
class MessageRow(Gtk.ListBoxRow):
    def __init__(self, summary):
        super().__init__()
        self.summary = summary
        grid = Gtk.Grid(column_spacing=6, row_spacing=2)
        self.dot = Gtk.Label(label="", width_chars=2)
        self.dot.get_style_context().add_class("post-dot")
        grid.attach(self.dot, 0, 0, 1, 1)
        self.sender = Gtk.Label(xalign=0, hexpand=True, ellipsize=Pango.EllipsizeMode.END)
        self.sender.get_style_context().add_class("post-from")
        grid.attach(self.sender, 1, 0, 1, 1)
        self.date = Gtk.Label(label=store.date_text(summary.get("date")))
        self.date.get_style_context().add_class("post-date")
        grid.attach(self.date, 2, 0, 1, 1)
        self.flag = Gtk.Label(label="", width_chars=2)
        self.flag.get_style_context().add_class("post-flag")
        grid.attach(self.flag, 0, 1, 1, 1)
        clip = " 📎" if summary.get("attach") else ""
        subject = Gtk.Label(label=(summary.get("subject") or "(No Subject)") + clip, xalign=0,
                            ellipsize=Pango.EllipsizeMode.END)
        subject.get_style_context().add_class("post-subject")
        grid.attach(subject, 1, 1, 2, 1)
        self.add(grid)
        self.update()

    @property
    def unread(self):
        return "\\Seen" not in self.summary.get("flags", [])

    @property
    def flagged(self):
        return "\\Flagged" in self.summary.get("flags", [])

    def update(self, outgoing=False):
        s = self.summary
        who = s.get("from_name") or s.get("from_addr") or "(Unknown Sender)"
        if outgoing:   # Sent and Drafts show who it went to
            who = store.email.utils.getaddresses([s.get("to", "")])
            who = ", ".join(n or a for n, a in who) or "(No Recipients)"
        self.sender.set_text(who)
        self.dot.set_text("●" if self.unread else "")
        self.flag.set_text("⚑" if self.flagged else "")
        ctx = self.sender.get_style_context()
        (ctx.remove_class if self.unread else ctx.add_class)("post-read")


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Post")
        self.app = app
        self.set_default_size(1180, 720)
        self.set_icon_name("freemac-post")
        self.current = None        # (account, mailbox name)
        self.message = None        # the parsed message shown
        self.load_remote = False

        header = self.header = Gtk.HeaderBar(show_close_button=True)
        header.set_title("Post")
        self.set_titlebar(header)
        self.get_mail = self._tool(("mail-send-receive-symbolic",), "Get New Mail (⇧⌘N)", self.app.refresh_all)
        header.pack_start(self.get_mail)
        header.pack_start(self._tool(("mail-message-new-symbolic", "document-new-symbolic"),
                                     "New Message (⌘N)", lambda: self.app.compose()))
        self.search = Gtk.SearchEntry(placeholder_text="Search", width_chars=18)
        self.search.connect("search-changed", lambda *_: self.fill_list())
        header.pack_end(self.search)
        self.message_tools = []
        for icons, tip, call in ((("mail-mark-important-symbolic", "starred-symbolic"), "Flag (⇧⌘L)", self.toggle_flag),
                                 (("user-trash-symbolic",), "Delete (⌘⌫)", self.delete_message),
                                 (("mail-forward-symbolic",), "Forward (⇧⌘F)", self.forward),
                                 (("mail-reply-all-symbolic",), "Reply All (⇧⌘R)", lambda: self.reply(True)),
                                 (("mail-reply-sender-symbolic",), "Reply (⌘R)", lambda: self.reply(False))):
            button = self._tool(icons, tip, call)
            header.pack_end(button)
            self.message_tools.append(button)
        self.spinner = Gtk.Spinner()
        header.pack_start(self.spinner)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.add(self.stack)
        self.setup = Gtk.Box(halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.stack.add_named(self.setup, "setup")

        outer = Gtk.Paned()
        side_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side_scroll.set_size_request(210, -1)
        side_scroll.get_style_context().add_class("post-side")
        self.sidebar = Gtk.ListBox()
        self.sidebar.get_style_context().add_class("post-side")
        self.sidebar.set_header_func(self._account_header)
        self.sidebar.connect("row-selected", self._mailbox_chosen)
        side_scroll.add(self.sidebar)
        outer.pack1(side_scroll, False, False)

        inner = Gtk.Paned()
        list_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        list_scroll.set_size_request(330, -1)
        self.listbox = Gtk.ListBox()
        self.listbox.get_style_context().add_class("post-list")
        self.listbox.connect("row-selected", self._message_chosen)
        self.listbox.connect("row-activated", self._message_activated)
        list_scroll.add(self.listbox)
        self.list_empty = Gtk.Label(label="No Messages")
        self.list_empty.get_style_context().add_class("post-empty")
        self.listbox.set_placeholder(self.list_empty)
        self.list_empty.show()
        inner.pack1(list_scroll, False, False)
        self.viewer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        inner.pack2(self.viewer, True, False)
        outer.pack2(inner, True, False)
        self.stack.add_named(outer, "mail")

        menus.add_actions(self, {
            "new-message": lambda: self.app.compose(), "reply": lambda: self.reply(False),
            "reply-all": lambda: self.reply(True), "forward": self.forward,
            "delete": self.delete_message, "toggle-read": self.toggle_read,
            "flag": self.toggle_flag, "get-mail": self.app.refresh_all,
            "find": self.search.grab_focus, "add-account": self.add_account,
            "remove-account": self.remove_account, "close": self.close,
        })
        self.connect("key-press-event", self._key)
        self.show_all()
        self.fill_sidebar()
        self.show_message(None)

    def _tool(self, icons, tip, call):
        button = Gtk.Button.new_from_icon_name(icon_name(*icons), Gtk.IconSize.BUTTON)
        button.set_tooltip_text(tip)
        button.connect("clicked", lambda *_: call())
        return button

    def busy(self, on):
        (self.spinner.start if on else self.spinner.stop)()

    # -- set-up --------------------------------------------------------
    def show_setup(self):
        for child in self.setup.get_children():
            child.destroy()
        self.setup.add(AccountForm(self._account_added))
        self.setup.show_all()
        self.stack.set_visible_child_name("setup")
        for button in self.message_tools + [self.get_mail]:
            button.set_sensitive(False)

    def _account_added(self, account, password):
        self.app.add_account(account, password)

    def add_account(self):
        dialog = Gtk.Window(title="Add Account", transient_for=self, modal=True, resizable=False)
        dialog.set_titlebar(Gtk.HeaderBar(show_close_button=True, title="Add Account"))

        def done(account, password):
            dialog.destroy()
            self.app.add_account(account, password)
        dialog.add(AccountForm(done, dialog.destroy))
        dialog.show_all()

    def remove_account(self):
        if not self.current:
            return
        account = self.current[0]
        answer = alert.ask(self, f"Remove the account “{account.address}”?",
                           "Its mail stays on the server; Post forgets the account and the copies kept on this computer.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Remove", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
        if answer == Gtk.ResponseType.OK:
            self.app.remove_account(account)

    # -- the sidebar -----------------------------------------------------
    def fill_sidebar(self, keep=True):
        accounts = self.app.accounts
        if not accounts:
            self.current = None
            self.show_setup()
            return
        self.stack.set_visible_child_name("mail")
        self.get_mail.set_sensitive(True)
        chosen = self.current if keep else None
        for row in self.sidebar.get_children():
            row.destroy()
        first = select = None
        for account in accounts:
            for box in self.app.mailboxes.get(account.id) or [store.Mailbox("INBOX")]:
                row = Gtk.ListBoxRow()
                row.account, row.box = account, box
                line = Gtk.Box(spacing=8)
                line.pack_start(Gtk.Image.new_from_icon_name(icon_name(KIND_ICONS.get(box.kind, "folder-symbolic"),
                                                                       "folder-symbolic"), Gtk.IconSize.MENU),
                                False, False, 0)
                line.pack_start(Gtk.Label(label=box.title, xalign=0, ellipsize=Pango.EllipsizeMode.END), True, True, 0)
                count = Gtk.Label(label=str(box.unread) if box.unread and box.kind not in ("sent", "drafts", "trash", "junk") else "")
                count.get_style_context().add_class("post-count")
                line.pack_start(count, False, False, 0)
                row.add(line)
                self.sidebar.add(row)
                first = first or row
                if chosen and chosen[0].id == account.id and chosen[1] == box.name:
                    select = row
        self.sidebar.show_all()
        self.sidebar.select_row(select or first)

    def _account_header(self, row, before):
        if before is None or before.account.id != row.account.id:
            if len(self.app.accounts) > 1 or before is not None:
                label = Gtk.Label(label=row.account.title, xalign=0)
                label.get_style_context().add_class("post-account")
                row.set_header(label)
                return
        row.set_header(None)

    def _mailbox_chosen(self, _box, row):
        if row is None:
            return
        same = self.current and self.current[0].id == row.account.id and self.current[1] == row.box.name
        self.current = (row.account, row.box.name)
        self.current_kind = row.box.kind
        if not same:
            self.search.set_text("")
            self.fill_list()
            self.app.refresh(row.account, row.box.name)
        self._title()

    def _title(self):
        if not self.current:
            return
        account, name = self.current
        title = next((b.title for b in self.app.mailboxes.get(account.id, []) if b.name == name), name)
        self.header.set_title(title if len(self.app.accounts) == 1 else f"{title} — {account.title}")
        messages = store.load_index(account, name)["messages"]
        unread = sum(1 for m in messages if "\\Seen" not in m.get("flags", []))
        count = len(messages)
        self.header.set_subtitle(f"{count} message{'' if count == 1 else 's'}" + (f", {unread} unread" if unread else ""))

    # -- the list of messages ----------------------------------------------
    def fill_list(self):
        if not self.current:
            return
        account, name = self.current
        chosen = self.chosen_summary()
        chosen_uid = chosen["uid"] if chosen else None
        for row in self.listbox.get_children():
            row.destroy()
        words = self.search.get_text().lower().split()
        outgoing = getattr(self, "current_kind", "") in ("sent", "drafts")
        select = None
        for summary in reversed(store.load_index(account, name)["messages"]):
            if words:
                hay = " ".join(str(summary.get(k, "")) for k in ("from_name", "from_addr", "subject", "to")).lower()
                if not all(w in hay for w in words):
                    continue
            row = MessageRow(summary)
            row.update(outgoing)
            self.listbox.add(row)
            if summary["uid"] == chosen_uid:
                select = row
        self.listbox.show_all()
        if select:
            self.listbox.select_row(select)
        self._title()

    def chosen_row(self):
        return self.listbox.get_selected_row()

    def chosen_summary(self):
        row = self.chosen_row()
        return row.summary if row else None

    def _message_chosen(self, _box, row):
        if row is None:
            self.show_message(None)
            return
        account, name = self.current
        uid = row.summary["uid"]
        self.load_remote = False
        raw = store.cached_body(account, name, uid)
        if raw is not None:
            self.show_message(store.parse(raw), row.summary)
        else:
            self.show_message("loading")
        if row.unread:
            row.summary.setdefault("flags", []).append("\\Seen")
            row.update(getattr(self, "current_kind", "") in ("sent", "drafts"))
            self.app.note_flags(account, name, row.summary)

        def got(raw_message):
            if self.chosen_summary() is row.summary:
                if raw is None:
                    self.show_message(store.parse(raw_message), row.summary)
            return False
        self.app.worker(account).submit(lambda s: s.body(name, uid), got, self.app.problem)

    def _message_activated(self, _box, row):
        if getattr(self, "current_kind", "") == "drafts" and self.message is not None:
            self.app.compose_from_draft(self.current[0], self.current[1], row.summary["uid"], self.message)

    # -- the message -----------------------------------------------------
    def show_message(self, message, summary=None):
        for child in self.viewer.get_children():
            child.destroy()
        self.message = message if not isinstance(message, str) else None
        for button in self.message_tools:
            button.set_sensitive(self.message is not None)
        if message is None or message == "loading":
            text = "Loading…" if message == "loading" else "No Message Selected"
            empty = Gtk.Label(label=text, vexpand=True)
            empty.get_style_context().add_class("post-empty")
            self.viewer.pack_start(empty, True, True, 0)
            self.viewer.show_all()
            return
        self.viewer.pack_start(self._message_head(message), False, False, 0)
        files = store.attachments_of(message)
        if files:
            self.viewer.pack_start(self._files_bar(files), False, False, 0)
        page = store.view_html(message, self.load_remote)
        if not self.load_remote and store.has_remote_content(page.split("</head>", 1)[-1]):
            bar = Gtk.Box(spacing=10)
            bar.get_style_context().add_class("post-remote")
            bar.pack_start(Gtk.Label(label="This message has pictures and other content from the internet, "
                                     "not loaded so the sender can't tell you've read it.",
                                     xalign=0, wrap=True), True, True, 0)
            load = Gtk.Button(label="Load Remote Content")
            load.connect("clicked", lambda *_: self._load_remote())
            bar.pack_start(load, False, False, 0)
            self.viewer.pack_start(bar, False, False, 0)
        self.viewer.pack_start(self._body_view(message, page), True, True, 0)
        self.viewer.show_all()

    def _load_remote(self):
        self.load_remote = True
        message = self.message
        self.show_message(message, self.chosen_summary())
        self.load_remote = False

    def _message_head(self, message):
        head = Gtk.Grid(column_spacing=12, row_spacing=2)
        head.get_style_context().add_class("post-head")
        name, address = store.email.utils.parseaddr(str(message.get("From", "")))
        shown = name or address or "(Unknown Sender)"
        tile = Gtk.Label(label=(shown[:1] or "?").upper())
        tile.set_size_request(40, 40)
        tile.set_valign(Gtk.Align.START)
        tile.set_halign(Gtk.Align.START)
        tile.get_style_context().add_class("post-tile")
        tint = TINTS[sum(map(ord, address or shown)) % len(TINTS)]
        provider = Gtk.CssProvider()
        provider.load_from_data(f"label {{ background: {tint}; }}".encode())
        tile.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        head.attach(tile, 0, 0, 1, 4)
        sender = Gtk.Label(label=shown, xalign=0, hexpand=True, selectable=True, ellipsize=Pango.EllipsizeMode.END)
        sender.set_tooltip_text(address)
        sender.get_style_context().add_class("post-head-from")
        head.attach(sender, 1, 0, 1, 1)
        when = Gtk.Label(label=store._when_text(message), xalign=1)
        when.get_style_context().add_class("post-head-line")
        head.attach(when, 2, 0, 1, 1)
        subject = Gtk.Label(label=str(message.get("Subject", "")) or "(No Subject)", xalign=0, wrap=True,
                            selectable=True)
        subject.get_style_context().add_class("post-head-subject")
        head.attach(subject, 1, 1, 2, 1)
        row = 2
        for key in ("To", "Cc"):
            value = message.get(key)
            if value:
                line = Gtk.Label(label=f"{key}: {value}", xalign=0, wrap=True, selectable=True)
                line.get_style_context().add_class("post-head-line")
                head.attach(line, 1, row, 2, 1)
                row += 1
        return head

    def _files_bar(self, files):
        bar = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=6, column_spacing=6)
        bar.get_style_context().add_class("post-files")
        for filename, ctype, part in files:
            button = Gtk.Button()
            box = Gtk.Box(spacing=6)
            icon = Gio.content_type_get_symbolic_icon(Gio.content_type_from_mime_type(ctype) or ctype)
            box.pack_start(Gtk.Image.new_from_gicon(icon, Gtk.IconSize.MENU), False, False, 0)
            size = len(part.get_payload(decode=True) or b"")
            box.pack_start(Gtk.Label(label=f"{filename}  {GLib.format_size(size)}"), False, False, 0)
            button.add(box)
            button.set_tooltip_text("Save to Downloads and open")
            button.connect("clicked", lambda _b, n=filename, p=part: self.save_file(n, p))
            bar.add(button)
        return bar

    def save_file(self, filename, part):
        folder = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~/Downloads")
        os.makedirs(folder, exist_ok=True)
        safe = os.path.basename(filename.replace("\\", "/")) or "Attachment"
        stem, ext = os.path.splitext(safe)
        path, n = os.path.join(folder, safe), 2
        while os.path.exists(path):
            path = os.path.join(folder, f"{stem} {n}{ext}")
            n += 1
        with open(path, "wb") as f:
            f.write(part.get_payload(decode=True) or b"")
        open_uri(Gio.File.new_for_path(path).get_uri())

    def _body_view(self, message, page):
        if WebKit2 is not None:
            view = WebKit2.WebView()
            settings = view.get_settings()
            settings.set_enable_javascript(False)
            settings.set_enable_javascript_markup(False)
            settings.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.NEVER)
            settings.set_enable_developer_extras(False)
            view.connect("decide-policy", self._policy)
            view.connect("context-menu", lambda *_: False)
            if style.is_dark() and "<div class=\"plain\">" in page:
                page = page.replace("</style>", "body{background:#1e1e1e;color:#e8e8e8}"
                                    "a{color:#5aa0ff}</style>", 1)
            view.load_html(page, None)
            return view
        text = Gtk.TextView(editable=False, wrap_mode=Gtk.WrapMode.WORD_CHAR, cursor_visible=False,
                            left_margin=20, right_margin=20, top_margin=14, bottom_margin=14)
        text.get_style_context().add_class("post-plain")
        text.get_buffer().set_text(store.plain_text(message))
        scroll = Gtk.ScrolledWindow()
        scroll.add(text)
        return scroll

    def _policy(self, _view, decision, kind):
        """Links open in the web browser; nothing else is followed."""
        if kind in (WebKit2.PolicyDecisionType.NAVIGATION_ACTION, WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION):
            request = decision.get_navigation_action().get_request()
            uri = request.get_uri() or ""
            if uri.startswith(("about:", "data:")) and kind == WebKit2.PolicyDecisionType.NAVIGATION_ACTION \
                    and decision.get_navigation_action().get_navigation_type() != WebKit2.NavigationType.LINK_CLICKED:
                decision.use()
                return True
            decision.ignore()
            if uri.startswith(("http:", "https:", "mailto:")):
                if uri.startswith("mailto:"):
                    self.app.compose(mailto=uri)
                else:
                    open_uri(uri)
            return True
        return False

    # -- acting on the message ---------------------------------------------
    def reply(self, everyone):
        if self.message is not None and self.current:
            self.app.compose(reply=(self.current[0], self.message, everyone))

    def forward(self):
        if self.message is not None and self.current:
            self.app.compose(forward=(self.current[0], self.message))

    def delete_message(self):
        row = self.chosen_row()
        if row is None or not self.current:
            return
        account, name = self.current
        uid = row.summary["uid"]
        trash = next((b.name for b in self.app.mailboxes.get(account.id, []) if b.kind == "trash"), None)
        index = row.get_index()
        row.destroy()
        following = self.listbox.get_row_at_index(index) or self.listbox.get_row_at_index(index - 1)
        if following:
            self.listbox.select_row(following)
        self.app.forget_message(account, name, uid)
        self._title()
        if trash and trash != name:
            work = lambda s: s.move(name, uid, trash)  # noqa: E731
        else:
            work = lambda s: s.erase(name, uid)  # noqa: E731
        self.app.worker(account).submit(work, lambda _r: self.app.refresh(account, name), self.app.problem)

    def _change_flag(self, flag):
        row = self.chosen_row()
        if row is None or not self.current:
            return
        account, name = self.current
        flags = row.summary.setdefault("flags", [])
        on = flag not in flags
        if on:
            flags.append(flag)
        else:
            flags.remove(flag)
        row.update(getattr(self, "current_kind", "") in ("sent", "drafts"))
        self.app.note_flags(account, name, row.summary)
        uid = row.summary["uid"]
        self.app.worker(account).submit(lambda s: s.set_flag(name, uid, flag, on), None, self.app.problem)

    def toggle_read(self):
        self._change_flag("\\Seen")

    def toggle_flag(self):
        self._change_flag("\\Flagged")

    def _key(self, _w, event):
        focus = self.get_focus()
        typing = isinstance(focus, Gtk.Entry)
        if event.keyval in (Gdk.KEY_Delete, Gdk.KEY_BackSpace) and not typing and focus is not None \
                and focus.is_ancestor(self.listbox):
            self.delete_message()
            return True
        return False


# --- writing ---------------------------------------------------------------------
class Compose(Gtk.ApplicationWindow):
    def __init__(self, app, account, to="", cc="", subject="", body="", files=(), reply_to=None, draft=None):
        super().__init__(application=app, title="New Message")
        self.app = app
        self.reply_to = reply_to     # the message answered, for In-Reply-To
        self.draft = draft           # (account, mailbox, uid) of the draft this came from
        self.files = []
        self.sending = False
        self.set_default_size(640, 560)
        self.set_icon_name("freemac-post")

        header = self.header = Gtk.HeaderBar(show_close_button=True, title="New Message")
        self.set_titlebar(header)
        self.send_button = Gtk.Button.new_from_icon_name(icon_name("mail-send-symbolic", "document-send-symbolic"),
                                                         Gtk.IconSize.BUTTON)
        self.send_button.set_tooltip_text("Send (⇧⌘D)")
        self.send_button.get_style_context().add_class("suggested-action")
        self.send_button.connect("clicked", lambda *_: self.send())
        header.pack_start(self.send_button)
        self.spinner = Gtk.Spinner()
        header.pack_start(self.spinner)
        attach = Gtk.Button.new_from_icon_name(icon_name("mail-attachment-symbolic"), Gtk.IconSize.BUTTON)
        attach.set_tooltip_text("Attach Files (⇧⌘A)")
        attach.connect("clicked", lambda *_: self.choose_files())
        header.pack_end(attach)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)
        self.from_combo = Gtk.ComboBoxText()
        for a in app.accounts:
            self.from_combo.append(a.id, a.from_header)
        self.from_combo.set_active_id(account.id)
        if len(app.accounts) > 1:
            box.pack_start(self._field("From:", self.from_combo), False, False, 0)
        self.to = self._entry(to)
        self.cc = self._entry(cc)
        self.bcc = self._entry("")
        self.subject = Gtk.Entry(text=subject, hexpand=True)
        self.subject.connect("changed", lambda e: header.set_title(e.get_text() or "New Message"))
        header.set_title(subject or "New Message")
        box.pack_start(self._field("To:", self.to), False, False, 0)
        box.pack_start(self._field("Cc:", self.cc), False, False, 0)
        self.bcc_row = self._field("Bcc:", self.bcc)
        box.pack_start(self.bcc_row, False, False, 0)
        box.pack_start(self._field("Subject:", self.subject), False, False, 0)
        self.chips = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4,
                                 column_spacing=6, row_spacing=4, margin=6)
        box.pack_start(self.chips, False, False, 0)
        self.body = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=16, right_margin=16,
                                 top_margin=12, bottom_margin=12)
        spelling.attach(self.body)
        self.body.get_style_context().add_class("post-compose-body")
        self.body.get_buffer().set_text(body)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.body)
        box.pack_start(scroll, True, True, 0)

        for item in files:
            self.add_file(item)
        self.drag_dest_set(Gtk.DestDefaults.ALL, [Gtk.TargetEntry.new("text/uri-list", 0, 0)], Gdk.DragAction.COPY)
        self.connect("drag-data-received", self._dropped)
        menus.add_actions(self, {"send": self.send, "attach": self.choose_files, "save-draft": self.save_draft,
                                 "close": self.close, "show-bcc": self.show_bcc})
        self.connect("delete-event", self._closing)
        self.show_all()
        self.bcc_row.set_visible(False)
        self.chips.set_visible(bool(self.files))
        if to:
            self.body.grab_focus()
            self.body.get_buffer().place_cursor(self.body.get_buffer().get_start_iter())
        else:
            self.to.grab_focus()
        self.saved_state = self._state()
        # In front of Post's own window, which may open in the same moment.
        GLib.timeout_add(200, lambda: self.present() and False)

    def _field(self, label, widget):
        line = Gtk.Box(spacing=6)
        line.get_style_context().add_class("post-compose-field")
        line.pack_start(Gtk.Label(label=label, xalign=1), False, False, 0)
        line.pack_start(widget, True, True, 0)
        return line

    def _entry(self, text):
        entry = Gtk.Entry(text=text, hexpand=True)
        completion = Gtk.EntryCompletion(model=self.app.address_book(), minimum_key_length=1)
        completion.set_text_column(0)
        completion.set_match_func(self._match, entry)
        completion.connect("match-selected", self._matched, entry)
        entry.set_completion(completion)
        return entry

    @staticmethod
    def _last_word(entry):
        return entry.get_text()[:entry.get_position()].split(",")[-1].strip().lower()

    def _match(self, _completion, _key, it, entry):
        word = self._last_word(entry)
        text = self.app.address_book()[it][0].lower()
        return bool(word) and any(part.startswith(word) for part in text.replace("<", " ").split()) or \
            (bool(word) and text.startswith(word))

    def _matched(self, _completion, model, it, entry):
        text = entry.get_text()
        head = text[:entry.get_position()].rsplit(",", 1)[0] if "," in text[:entry.get_position()] else ""
        new = (head + ", " if head else "") + model[it][0] + ", "
        entry.set_text(new)
        entry.set_position(-1)
        return True

    def show_bcc(self):
        self.bcc_row.set_visible(not self.bcc_row.get_visible())

    def account(self):
        return next(a for a in self.app.accounts if a.id == self.from_combo.get_active_id())

    def body_text(self):
        buffer = self.body.get_buffer()
        return buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False)

    def _state(self):
        return (self.to.get_text(), self.cc.get_text(), self.bcc.get_text(), self.subject.get_text(),
                self.body_text(), len(self.files))

    # -- files -----------------------------------------------------------
    def choose_files(self):
        chooser = Gtk.FileChooserNative(title="Attach Files", transient_for=self,
                                        action=Gtk.FileChooserAction.OPEN, select_multiple=True)
        if chooser.run() == Gtk.ResponseType.ACCEPT:
            for path in chooser.get_filenames():
                self.add_file(path)
        chooser.destroy()

    def _dropped(self, _w, _ctx, _x, _y, data, _info, _time):
        for uri in data.get_uris():
            path = Gio.File.new_for_uri(uri).get_path()
            if path and os.path.isfile(path):
                self.add_file(path)

    def add_file(self, item):
        self.files.append(item)
        name = item[0] if isinstance(item, tuple) else os.path.basename(item)
        chip = Gtk.Box(spacing=4)
        chip.get_style_context().add_class("post-chip")
        chip.pack_start(Gtk.Label(label="📎 " + name), False, False, 0)
        remove = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
        remove.set_relief(Gtk.ReliefStyle.NONE)
        chip.pack_start(remove, False, False, 0)
        self.chips.add(chip)

        def drop(*_):
            if item in self.files:
                self.files.remove(item)
            chip.get_parent().destroy()
            self.chips.set_visible(bool(self.files))
        remove.connect("clicked", drop)
        self.chips.show_all()
        self.chips.set_visible(True)

    # -- sending -----------------------------------------------------------
    def _message(self):
        return store.compose(self.account(), self.to.get_text(), self.cc.get_text(), self.bcc.get_text(),
                             self.subject.get_text(), self.body_text(), list(self.files), self.reply_to)

    def send(self):
        if self.sending:
            return
        if not store.addresses(self.to.get_text() + "," + self.cc.get_text() + "," + self.bcc.get_text()):
            alert.tell(self, "Who is this message to?", "Type an email address in the To field.")
            self.to.grab_focus()
            return
        if not self.subject.get_text().strip():
            answer = alert.ask(self, "This message has no subject.", "Send it anyway?",
                               [("Don't Send", Gtk.ResponseType.CANCEL), ("Send", Gtk.ResponseType.OK)],
                               default=Gtk.ResponseType.OK)
            if answer != Gtk.ResponseType.OK:
                return
        account = self.account()
        password = store.get_password(account)
        try:
            message = self._message()
        except OSError as error:
            alert.tell(self, "A file couldn't be attached.", str(error))
            return
        self.sending = True
        self.set_sensitive(False)
        self.spinner.start()

        def done(_result):
            self.spinner.stop()
            self.app.sent(account, message, self.draft)
            self.saved_state = self._state()
            self.destroy()

        def failed(text):
            self.spinner.stop()
            self.sending = False
            self.set_sensitive(True)
            alert.tell(self, "The message couldn't be sent.", text)
        # smtplib sends to the Bcc addresses and leaves that line out of what goes.
        in_background(lambda: store.send(account, password, message), done, failed)

    def save_draft(self):
        try:
            message = self._message()
        except OSError:
            return False
        self.app.save_draft(self.account(), message, self.draft)
        self.saved_state = self._state()
        return True

    def _closing(self, *_):
        if self.sending:
            return True
        state = self._state()
        if state == self.saved_state or not any(state[:5]):
            return False
        answer = alert.ask(self, "Do you want to save this message as a draft?",
                           "It goes in Drafts, where you can finish it later.",
                           [("Don't Save", Gtk.ResponseType.REJECT), ("Cancel", Gtk.ResponseType.CANCEL),
                            ("Save", Gtk.ResponseType.OK)], default=Gtk.ResponseType.OK)
        if answer == Gtk.ResponseType.OK:
            self.save_draft()
            return False
        return answer != Gtk.ResponseType.REJECT


# --- the application ---------------------------------------------------------------
def menubar():
    return menus.menubar([
        ("_File", [[("New Message", "win.new-message", "<Ctrl>n")],
                   [("Add Account…", "win.add-account", None)],
                   [("Save Draft", "win.save-draft", "<Ctrl>s"), ("Attach Files…", "win.attach", "<Ctrl><Shift>a")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Delete", "win.delete", "<Ctrl>BackSpace")],
                   [("Find", "win.find", "<Ctrl>f")]]),
        ("_View", [[("Bcc Address Field", "win.show-bcc", "<Ctrl><Alt>b")]]),
        ("_Mailbox", [[("Get New Mail", "win.get-mail", "<Ctrl><Shift>n")],
                      [("Remove Account…", "win.remove-account", None)]]),
        ("_Message", [[("Send", "win.send", "<Ctrl><Shift>d")],
                      [("Reply", "win.reply", "<Ctrl>r"), ("Reply All", "win.reply-all", "<Ctrl><Shift>r"),
                       ("Forward", "win.forward", "<Ctrl><Shift>f")],
                      [("Mark as Read or Unread", "win.toggle-read", "<Ctrl><Shift>u"),
                       ("Flag", "win.flag", "<Ctrl><Shift>l")]]),
    ])


class Post(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)
        self.waiting = None   # a mailto: link that came before any account
        self.telling = None   # the problem an alert is showing now
        self.accounts = []
        self.mailboxes = {}       # account id -> [Mailbox]
        self.workers = {}
        self.window = None
        self.newest = {}          # account id -> newest uid seen in the Inbox
        self._book = None

    # -- accounts ------------------------------------------------------------
    def worker(self, account):
        if account.id not in self.workers:
            self.workers[account.id] = Worker(account, store.get_password(account))
        return self.workers[account.id]

    def add_account(self, account, password):
        if any(a.address.lower() == account.address.lower() for a in self.accounts):
            alert.tell(self.window, "That account is already in Post.")
            return
        store.set_password(account, password)
        self.accounts.append(account)
        store.save_accounts(self.accounts)
        self.window.fill_sidebar()
        self.refresh_account(account)
        if self.waiting:
            waiting, self.waiting = self.waiting, None
            self.compose(mailto=waiting)

    def remove_account(self, account):
        worker = self.workers.pop(account.id, None)
        if worker:
            worker.stop()
        store.remove_account(self.accounts, account)
        self.mailboxes.pop(account.id, None)
        self.window.current = None
        self.window.fill_sidebar(keep=False)

    def problem(self, text):
        if self.window:
            self.window.busy(False)
            if text != self.telling:   # once, while the same alert is up
                self.telling = text
                alert.tell(self.window, "There's a problem with your mail.", text)
                self.telling = None
        return False

    # -- keeping up to date -------------------------------------------------
    def refresh_account(self, account):
        """The account's mailboxes, then its Inbox."""
        self.window.busy(True)

        def got(boxes):
            self.mailboxes[account.id] = boxes
            store.save_mailboxes(account, boxes)
            self.badge()
            self.window.fill_sidebar()
            self.window.busy(False)
            inbox = next((b.name for b in boxes if b.kind == "inbox"), "INBOX")
            self.refresh(account, inbox)
        self.worker(account).submit(lambda s: s.mailboxes(), got, self.problem)

    def refresh_all(self):
        for account in self.accounts:
            self.refresh_account(account)
        return True

    def refresh(self, account, name):
        # The window may not be there: Post stays open without one, and the
        # first refresh comes while its window is still being made.
        if self.window:
            self.window.busy(True)

        def got(index):
            if self.window:
                self.window.busy(False)
            unread = sum(1 for m in index["messages"] if "\\Seen" not in m.get("flags", []))
            for box in self.mailboxes.get(account.id, []):
                if box.name == name and box.unread != unread:
                    box.unread = unread
                    store.save_mailboxes(account, self.mailboxes[account.id])
                    self.badge()
                    if self.window:
                        self.window.fill_sidebar()
            if self.window and self.window.current and self.window.current[0].id == account.id and self.window.current[1] == name:
                self.window.fill_list()
            if name.upper() == "INBOX":
                self._tell_new(account, index)
        self.worker(account).submit(lambda s: s.refresh(name), got, self.problem)

    def _tell_new(self, account, index):
        newest = max((m["uid"] for m in index["messages"]), default=0)
        before = self.newest.get(account.id)
        self.newest[account.id] = newest
        if before is None or (self.window is not None and self.window.is_active()):
            return
        fresh = [m for m in index["messages"] if m["uid"] > before and "\\Seen" not in m.get("flags", [])]
        if not fresh:
            return
        note = Gio.Notification.new(fresh[-1].get("from_name") or fresh[-1].get("from_addr") or "New Mail")
        note.set_body(fresh[-1].get("subject") or "(No Subject)" if len(fresh) == 1
                      else f"{len(fresh)} new messages")
        note.set_icon(Gio.ThemedIcon.new("freemac-post"))
        self.send_notification("new-mail", note)

    def note_flags(self, account, name, summary):
        index = store.load_index(account, name)
        for m in index["messages"]:
            if m["uid"] == summary["uid"]:
                m["flags"] = list(summary.get("flags", []))
        store.save_index(account, name, index)
        box = next((b for b in self.mailboxes.get(account.id, []) if b.name == name), None)
        if box:
            unread = sum(1 for m in index["messages"] if "\\Seen" not in m.get("flags", []))
            if unread != box.unread:
                box.unread = unread
                store.save_mailboxes(account, self.mailboxes[account.id])
                self.badge()
                self.window.fill_sidebar()

    def forget_message(self, account, name, uid):
        index = store.load_index(account, name)
        index["messages"] = [m for m in index["messages"] if m["uid"] != uid]
        store.save_index(account, name, index)

    def box_of(self, account, kind):
        return next((b.name for b in self.mailboxes.get(account.id, []) if b.kind == kind), None)

    # -- writing -------------------------------------------------------------
    def address_book(self):
        """Names and addresses from Crew, for the To and Cc fields."""
        if self._book is None:
            self._book = Gtk.ListStore(str)
            seen = set()
            try:
                from . import contacts_store
                for person in contacts_store.load():
                    for _kind, address in person.emails:
                        if address and address.lower() not in seen:
                            seen.add(address.lower())
                            named = person.name if person.name != "No Name" else ""
                            self._book.append([store.email.utils.formataddr((named, address)) if named else address])
            except Exception:
                pass
        return self._book

    def compose(self, reply=None, forward=None, mailto=None):
        if not self.accounts:
            # Shared files wait while the first account is added, then open.
            self.waiting = mailto or self.waiting
            self._main_window().present()
            return
        account = self.window.current[0] if self.window and self.window.current else self.accounts[0]
        if reply:
            account, message, everyone = reply
            to, cc, subject, body = store.reply_fields(message, account, everyone)
            Compose(self, account, to, cc, subject, body, reply_to=message)
        elif forward:
            account, message = forward
            subject, body, files = store.forward_fields(message)
            Compose(self, account, subject=subject, body=body, files=files)
        elif mailto:
            to, cc, subject, body = store.mailto_fields(mailto)
            Compose(self, account, to, cc, subject, body, store.mailto_files(mailto))
        else:
            Compose(self, account)

    def compose_from_draft(self, account, name, uid, message):
        files = [(n, c, p.get_payload(decode=True) or b"") for n, c, p in store.attachments_of(message)]
        Compose(self, account, str(message.get("To", "")), str(message.get("Cc", "")),
                str(message.get("Subject", "")), store.plain_text(message), files, draft=(account, name, uid))

    def sent(self, account, message, draft):
        """After sending: a copy in Sent (Gmail keeps its own), and the draft
        it came from removed."""
        sent_box = self.box_of(account, "sent")
        if sent_box and not account.imap_host.endswith("gmail.com"):
            raw = message.as_bytes()
            self.worker(account).submit(lambda s: s.append(sent_box, raw), None, self.problem)
        self._drop_draft(draft)

    def save_draft(self, account, message, draft):
        drafts = self.box_of(account, "drafts")
        if not drafts:
            return
        raw = message.as_bytes()
        self.worker(account).submit(lambda s: s.append(drafts, raw, "(\\Seen \\Draft)"),
                                    lambda _r: self.refresh(account, drafts), self.problem)
        self._drop_draft(draft)

    def _drop_draft(self, draft):
        if draft:
            account, name, uid = draft
            self.forget_message(account, name, uid)
            self.worker(account).submit(lambda s: s.erase(name, uid), lambda _r: self.refresh(account, name),
                                        self.problem)

    # -- Gtk.Application -----------------------------------------------------
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
        self.hold()   # stays open with no window, as a Mac app does
        self.set_menubar(menubar())
        self.accounts = store.load_accounts()
        for account in self.accounts:
            self.mailboxes[account.id] = store.load_mailboxes(account)
        GLib.timeout_add_seconds(CHECK_EVERY, self.refresh_all)
        self.badge()

    def badge(self):
        """Post's Dock icon shows the unread messages in every Inbox, as on a Mac."""
        unread = sum(box.unread for boxes in self.mailboxes.values() for box in boxes
                     if box.kind == "inbox")
        launcher_badge.set_count("freemac-post.desktop", unread)

    def _main_window(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda *_: setattr(self, "window", None))
            for account in self.accounts:
                self.refresh_account(account)
        return self.window

    def do_activate(self):
        self._main_window().present()

    def do_open(self, files, _count, _hint):
        window = self._main_window()
        window.present()   # first, so a new message opens in front of it
        for f in files:
            uri = f.get_uri()
            if uri.startswith("mailto:"):
                self.compose(mailto=uri)
            elif f.get_path():
                try:
                    with open(f.get_path(), "rb") as handle:
                        message = store.parse(handle.read())
                except OSError:
                    continue
                window.show_message(message)
                window.present()

    def do_shutdown(self):
        for worker in self.workers.values():
            worker.stop()
        Gtk.Application.do_shutdown(self)


def main():
    return Post().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
