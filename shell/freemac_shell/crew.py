# SPDX-License-Identifier: GPL-3.0-or-later
"""Crew: the people you know, kept on this computer.

Names on the left, A to Z under letter headings, with a search field over
them; the chosen person's card on the right, with a round picture of their
initials, then their phones, email, addresses, birthday and a note. Edit
(⌘L, or the Edit button) turns the card into fields; Done saves it. ⌘N adds a
person, Delete removes the chosen one after asking. Opening .vcf files adds
the people in them. Each person is one vCard file (contacts_store.py) that
other address books can import. Original freemac code.
"""
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import alert, menus, spelling, style  # noqa: E402
from . import contacts_store as store  # noqa: E402

APP_ID = "org.freemac.Crew"
KIND_NAMES = {"mobile": "mobile", "home": "home", "work": "work", "other": "other"}
# Soft tile colours for the initials, picked by name so a person keeps theirs.
TINTS = ("#8e9bb0", "#7aa2c8", "#87b39a", "#c4a07a", "#b48fb8", "#c58b8b", "#8fb3b3")

CSS = b"""
.crew-list row { padding: 5px 12px; }
.crew-list .crew-letter { font-weight: 700; font-size: 12px; color: alpha(currentColor, 0.5); padding: 8px 12px 2px 12px; }
.crew-name-big { font-size: 24px; font-weight: 700; }
.crew-sub { color: alpha(currentColor, 0.6); }
.crew-kind { color: alpha(currentColor, 0.55); font-size: 12px; }
.crew-value { font-size: 14px; }
.crew-value-link { color: @theme_selected_bg_color; }
.crew-search { margin: 8px; }
.crew-card entry { min-height: 26px; }
.crew-empty { color: alpha(currentColor, 0.45); font-size: 15px; }
"""


def initials_tile(contact, size):
    """A round tile with the person's initials, drawn in their colour."""
    area = Gtk.DrawingArea()
    area.set_size_request(size, size)
    tint = Gdk.RGBA()
    tint.parse(TINTS[sum(map(ord, contact.name)) % len(TINTS)])

    def draw(_w, cr):
        cr.arc(size / 2, size / 2, size / 2, 0, 6.2832)
        cr.set_source_rgba(tint.red, tint.green, tint.blue, 1)
        cr.fill()
        layout = area.create_pango_layout(contact.initials()[:2])
        font = Pango.FontDescription("Sans Bold")
        font.set_absolute_size(size * 0.38 * Pango.SCALE)
        layout.set_font_description(font)
        w, h = layout.get_pixel_size()
        cr.set_source_rgb(1, 1, 1)
        cr.move_to((size - w) / 2, (size - h) / 2)
        PangoCairo.show_layout(cr, layout)
        return False
    area.connect("draw", draw)
    return area


def birthday_text(value):
    import datetime as dt
    try:
        if value.startswith("--"):
            day = dt.date(2000, int(value[2:4]), int(value[5:7]))
            return f"{day:%B} {day.day}"
        day = dt.date.fromisoformat(value)
        return f"{day:%B} {day.day}, {day.year}"
    except ValueError:
        return value


def parse_birthday(text):
    """A birthday typed loosely (March 15, 3/15/1990, 1990-03-15) as
    YYYY-MM-DD or --MM-DD; None when it can't be read."""
    import datetime as dt
    t = text.strip()
    if not t:
        return ""
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%B %d, %Y", "%b %d, %Y", "%B %d %Y", "%d %B %Y"):
        try:
            return dt.datetime.strptime(t, fmt).date().isoformat()
        except ValueError:
            pass
    for fmt in ("%m/%d", "%B %d", "%b %d", "%d %B"):
        try:
            day = dt.datetime.strptime(t + " 2000", fmt + " %Y")
            return f"--{day.month:02d}-{day.day:02d}"
        except ValueError:
            pass
    return None


class Card(Gtk.ScrolledWindow):
    """One person's card, to read or (editing=True) to change."""

    def __init__(self, win, contact, editing=False):
        super().__init__(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.win, self.contact, self.editing = win, contact.copy(), editing
        self.get_style_context().add_class("crew-card")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_margin_start(36)
        box.set_margin_end(36)
        box.set_margin_top(28)
        box.set_margin_bottom(28)
        self.add(box)
        top = Gtk.Box(spacing=18)
        top.pack_start(initials_tile(contact, 76), False, False, 0)
        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER)
        top.pack_start(names, True, True, 0)
        box.pack_start(top, False, False, 0)
        self.grid = Gtk.Grid(column_spacing=14, row_spacing=10)
        box.pack_start(Gtk.Separator(), False, False, 0)
        box.pack_start(self.grid, False, False, 0)
        self.row = 0
        if editing:
            self.first = self._entry(contact.first, "First")
            self.last = self._entry(contact.last, "Last")
            pair = Gtk.Box(spacing=6)
            pair.pack_start(self.first, True, True, 0)
            pair.pack_start(self.last, True, True, 0)
            names.pack_start(pair, False, False, 0)
            self.company = self._entry(contact.company, "Company")
            self.job = self._entry(contact.job, "Job title")
            names.pack_start(self.company, False, False, 0)
            names.pack_start(self.job, False, False, 0)
            phones, emails, places = self._section(), self._section(), self._section()
            self.phone_rows = [self._pair(phones, "phone", k, n) for k, n in contact.phones or [("mobile", "")]]
            self._adder(phones, "add phone",
                        lambda: self.phone_rows.append(self._pair(phones, "phone", "mobile", "", True)))
            self.email_rows = [self._pair(emails, "email", k, a) for k, a in contact.emails or [("home", "")]]
            self._adder(emails, "add email",
                        lambda: self.email_rows.append(self._pair(emails, "email", "home", "", True)))
            self.address_rows = [self._address(places, a) for a in contact.addresses]
            self._adder(places, "add address", lambda: self.address_rows.append(
                self._address(places, ("home", "", "", "", "", ""), True)))
            self.birthday = self._entry(birthday_text(contact.birthday) if contact.birthday else "", "Month Day, Year")
            self._place("birthday", self.birthday)
            self.notes = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR)
            spelling.attach(self.notes)
            self.notes.get_buffer().set_text(contact.notes)
            frame = Gtk.Frame()
            frame.add(self.notes)
            frame.set_size_request(-1, 70)
            self._place("note", frame)
            GLib.idle_add(self.first.grab_focus)
        else:
            big = Gtk.Label(label=contact.name, xalign=0, selectable=True, wrap=True)
            big.get_style_context().add_class("crew-name-big")
            names.pack_start(big, False, False, 0)
            sub = " · ".join(p for p in (contact.job, contact.company if contact.first or contact.last else "") if p)
            if sub:
                line = Gtk.Label(label=sub, xalign=0, selectable=True)
                line.get_style_context().add_class("crew-sub")
                names.pack_start(line, False, False, 0)
            for kind, number in contact.phones:
                self._show(KIND_NAMES[kind], number)
            for kind, address in contact.emails:
                self._show(KIND_NAMES[kind] if kind != "other" else "email", address, f"mailto:{address}")
            for kind, street, city, region, code, country in contact.addresses:
                lines = [street, " ".join(p for p in (city, region, code) if p), country]
                self._show(KIND_NAMES[kind], "\n".join(p for p in lines if p))
            if contact.birthday:
                self._show("birthday", birthday_text(contact.birthday))
            if contact.notes:
                self._show("note", contact.notes)
            if self.row == 0:
                empty = Gtk.Label(label="Press Edit to add a phone, email or address.", xalign=0)
                empty.get_style_context().add_class("crew-sub")
                self.grid.attach(empty, 0, 0, 2, 1)
        self.show_all()

    # -- reading ---------------------------------------------------------
    def _kind_label(self, text):
        label = Gtk.Label(label=text, xalign=1, yalign=0)
        label.set_size_request(80, -1)
        label.get_style_context().add_class("crew-kind")
        return label

    def _show(self, kind, value, uri=None):
        self.grid.attach(self._kind_label(kind), 0, self.row, 1, 1)
        if uri:
            link = Gtk.Label(xalign=0)
            link.set_markup(f'<a href="{GLib.markup_escape_text(uri)}">{GLib.markup_escape_text(value)}</a>')
            link.connect("activate-link", lambda _l, u: self._open(u))
            link.set_track_visited_links(False)
            value_widget = link
        else:
            value_widget = Gtk.Label(label=value, xalign=0, selectable=True, wrap=True)
        value_widget.get_style_context().add_class("crew-value")
        self.grid.attach(value_widget, 1, self.row, 1, 1)
        self.row += 1

    def _open(self, uri):
        try:
            Gio.AppInfo.launch_default_for_uri(uri, None)
        except GLib.Error:
            pass
        return True

    # -- editing ---------------------------------------------------------
    def _entry(self, text, hint):
        entry = Gtk.Entry(text=text, placeholder_text=hint, activates_default=True)
        entry.connect("activate", lambda *_: self.win.finish_editing())
        return entry

    def _kind_combo(self, kind):
        combo = Gtk.ComboBoxText()
        for key, name in KIND_NAMES.items():
            combo.append(key, name)
        combo.set_active_id(kind)
        combo.set_valign(Gtk.Align.START)
        combo.set_size_request(96, -1)
        return combo

    def _place(self, kind, widget):
        self.grid.attach(self._kind_label(kind), 0, self.row, 1, 1)
        widget.set_hexpand(True)
        self.grid.attach(widget, 1, self.row, 1, 1)
        self.row += 1

    def _section(self):
        """A column of rows (phones, emails or addresses) across the card."""
        section = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.grid.attach(section, 0, self.row, 2, 1)
        self.row += 1
        return section

    def _line(self, section, combo, widget, focus):
        line = Gtk.Box(spacing=14)
        line.pack_start(combo, False, False, 0)
        line.pack_start(widget, True, True, 0)
        section.pack_start(line, False, False, 0)
        if focus:
            line.show_all()
            (widget.get_children()[0] if isinstance(widget, Gtk.Grid) else widget).grab_focus()

    def _pair(self, section, what, kind, value, focus=False):
        combo = self._kind_combo(kind)
        entry = self._entry(value, "Phone" if what == "phone" else "Email")
        self._line(section, combo, entry, focus)
        return combo, entry

    def _address(self, section, address, focus=False):
        kind, street, city, region, code, country = address
        combo = self._kind_combo(kind)
        fields = Gtk.Grid(column_spacing=6, row_spacing=6)
        entries = [self._entry(street, "Street"), self._entry(city, "City"),
                   self._entry(region, "State"), self._entry(code, "ZIP"),
                   self._entry(country, "Country")]
        fields.attach(entries[0], 0, 0, 3, 1)
        fields.attach(entries[1], 0, 1, 1, 1)
        fields.attach(entries[2], 1, 1, 1, 1)
        fields.attach(entries[3], 2, 1, 1, 1)
        fields.attach(entries[4], 0, 2, 3, 1)
        for e in entries:
            e.set_hexpand(True)
        self._line(section, combo, fields, False)
        if focus:
            fields.get_parent().show_all()
            entries[0].grab_focus()
        return combo, entries

    def _adder(self, section, text, add):
        line = Gtk.Box(spacing=14)
        spacer = Gtk.Box()
        spacer.set_size_request(96, -1)
        line.pack_start(spacer, False, False, 0)
        button = Gtk.Button(label=text, halign=Gtk.Align.START, relief=Gtk.ReliefStyle.NONE)
        button.get_style_context().add_class("crew-value-link")

        def clicked(*_):
            add()
            section.reorder_child(line, -1)   # keep the button last

        button.connect("clicked", clicked)
        line.pack_start(button, False, False, 0)
        section.pack_start(line, False, False, 0)

    def result(self):
        """The person as typed, or None when the birthday can't be read."""
        c = self.contact
        c.first, c.last = self.first.get_text().strip(), self.last.get_text().strip()
        c.company, c.job = self.company.get_text().strip(), self.job.get_text().strip()
        c.phones = [(k.get_active_id(), e.get_text().strip()) for k, e in self.phone_rows if e.get_text().strip()]
        c.emails = [(k.get_active_id(), e.get_text().strip()) for k, e in self.email_rows if e.get_text().strip()]
        c.addresses = []
        for k, entries in self.address_rows:
            parts = [e.get_text().strip() for e in entries]
            if any(parts):
                c.addresses.append((k.get_active_id(), *parts))
        birthday = parse_birthday(self.birthday.get_text())
        if birthday is None:
            self.birthday.grab_focus()
            self.birthday.get_style_context().add_class("error")
            return None
        c.birthday = birthday
        buffer = self.notes.get_buffer()
        c.notes = buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False).strip()
        return c


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Crew")
        self.set_default_size(820, 560)
        self.set_icon_name("freemac-crew")
        self.contacts = store.load()
        self.chosen = self.contacts[0].uid if self.contacts else None
        self.card = None
        self.adding = None   # a new person not yet saved

        header = Gtk.HeaderBar(show_close_button=True)
        header.set_title("Crew")
        add = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        add.set_tooltip_text("New Contact (⌘N)")
        add.connect("clicked", lambda *_: self.new_contact())
        header.pack_start(add)
        self.edit_button = Gtk.Button(label="Edit")
        self.edit_button.set_tooltip_text("Edit (⌘L)")
        self.edit_button.connect("clicked", lambda *_: self.toggle_editing())
        header.pack_end(self.edit_button)
        self.set_titlebar(header)
        header.show_all()

        paned = Gtk.Paned()
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.set_size_request(250, -1)
        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.get_style_context().add_class("crew-search")
        self.search.connect("search-changed", lambda *_: self.fill_list())
        self.search.connect("activate", lambda *_: self._first_match())
        side.pack_start(self.search, False, False, 0)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.listbox = Gtk.ListBox()
        self.listbox.get_style_context().add_class("crew-list")
        self.listbox.set_header_func(self._letter_header)
        self.listbox.connect("row-selected", self._row_selected)
        scroll.add(self.listbox)
        side.pack_start(scroll, True, True, 0)
        self.count = Gtk.Label()
        self.count.get_style_context().add_class("crew-sub")
        self.count.set_margin_top(6)
        self.count.set_margin_bottom(6)
        side.pack_start(self.count, False, False, 0)
        paned.pack1(side, False, False)
        self.right = Gtk.Box()
        paned.pack2(self.right, True, False)
        self.add(paned)

        menus.add_actions(self, {
            "new-contact": self.new_contact, "edit": self.toggle_editing,
            "delete": self.delete_chosen, "find": self.search.grab_focus,
            "close": self.close,
        })
        self.connect("key-press-event", self._key)
        self.fill_list()
        self.show_card()
        self.show_all()
        # Cards can change underneath (an online account's sync, another app):
        # read them again a moment after the folder settles.
        os.makedirs(store.store_dir(), exist_ok=True)
        self.monitor = Gio.File.new_for_path(store.store_dir()).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", self._files_changed)
        self.reload_pending = None

    def _files_changed(self, *_):
        if self.reload_pending is None:
            self.reload_pending = GLib.timeout_add(700, self.reload)

    def reload(self):
        """Read the cards again, unless one is being edited (then later)."""
        if self.card is not None and self.card.editing:
            self.reload_pending = GLib.timeout_add_seconds(2, self.reload)
            return False
        self.reload_pending = None
        fresh = store.load()
        if sorted(map(store.dump, fresh)) == sorted(map(store.dump, self.contacts)):
            return False
        self.contacts = fresh
        if self.chosen not in {c.uid for c in fresh}:
            self.chosen = fresh[0].uid if fresh else None
        self.fill_list()
        self.show_card()
        return False

    # -- the list --------------------------------------------------------
    def fill_list(self):
        words = self.search.get_text().strip()
        for row in self.listbox.get_children():
            row.destroy()
        shown = [c for c in self.contacts if not words or c.matches(words)]
        chosen_row = None
        for contact in shown:
            row = Gtk.ListBoxRow()
            row.contact = contact
            label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
            first, last = GLib.markup_escape_text(contact.first), GLib.markup_escape_text(contact.last)
            if contact.last:
                label.set_markup(f"{first} <b>{last}</b>".strip())
            else:
                label.set_markup(f"<b>{GLib.markup_escape_text(contact.name)}</b>")
            row.add(label)
            self.listbox.add(row)
            if contact.uid == self.chosen:
                chosen_row = row
        self.listbox.show_all()
        if chosen_row:
            self.listbox.select_row(chosen_row)
        n = len(self.contacts)
        self.count.set_text(f"{n} card" if n == 1 else f"{n} cards")

    def _letter(self, contact):
        key = (contact.last or contact.first or contact.company or "#")[:1].upper()
        return key if key.isalpha() else "#"

    def _letter_header(self, row, before):
        if self.search.get_text().strip():
            row.set_header(None)
            return
        letter = self._letter(row.contact)
        if before is None or self._letter(before.contact) != letter:
            head = Gtk.Label(label=letter, xalign=0)
            head.get_style_context().add_class("crew-letter")
            row.set_header(head)
        else:
            row.set_header(None)

    def _row_selected(self, _box, row):
        if row is None:
            return
        if self.card and self.card.editing and row.contact.uid != self.card.contact.uid:
            if not self.finish_editing():
                return
        if row.contact.uid != self.chosen or self.card is None:
            self.chosen = row.contact.uid
            self.show_card()

    def _first_match(self):
        row = self.listbox.get_row_at_index(0)
        if row:
            self.listbox.select_row(row)

    # -- the card --------------------------------------------------------
    def chosen_contact(self):
        if self.adding is not None:
            return self.adding
        return next((c for c in self.contacts if c.uid == self.chosen), None)

    def show_card(self, editing=False):
        for child in self.right.get_children():
            child.destroy()
        contact = self.chosen_contact()
        if contact is None:
            empty = Gtk.Label(label="No Cards" if not self.contacts else "No Card Chosen")
            empty.get_style_context().add_class("crew-empty")
            self.right.pack_start(empty, True, True, 0)
            self.card = None
            self.edit_button.set_sensitive(False)
        else:
            self.card = Card(self, contact, editing)
            self.right.pack_start(self.card, True, True, 0)
            self.edit_button.set_sensitive(True)
        self.edit_button.set_label("Done" if editing else "Edit")
        style_context = self.edit_button.get_style_context()
        if editing:
            style_context.add_class("suggested-action")
        else:
            style_context.remove_class("suggested-action")
        self.right.show_all()

    def toggle_editing(self):
        if self.card is None:
            return
        if self.card.editing:
            self.finish_editing()
        else:
            self.show_card(editing=True)

    def finish_editing(self):
        """Save the card being edited; False if it can't be yet."""
        if not (self.card and self.card.editing):
            return True
        contact = self.card.result()
        if contact is None:
            return False
        if self.adding is not None and not (contact.first or contact.last or contact.company
                                            or contact.phones or contact.emails):
            self.adding = None   # nothing typed: no card
        else:
            store.save(contact)
            self.contacts = [c for c in self.contacts if c.uid != contact.uid] + [contact]
            self.contacts.sort(key=store.Contact.sort_key)
            self.chosen = contact.uid
            self.adding = None
        self.fill_list()
        self.show_card()
        return True

    def cancel_editing(self):
        self.adding = None
        self.show_card()
        self.fill_list()

    def new_contact(self):
        if self.card and self.card.editing and not self.finish_editing():
            return
        self.search.set_text("")
        self.adding = store.Contact()
        self.listbox.unselect_all()
        self.show_card(editing=True)

    def delete_chosen(self):
        contact = self.chosen_contact()
        if contact is None or self.adding is not None:
            return
        answer = alert.ask(self, f"Delete {contact.name}?", "This card will be removed from Crew.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Delete", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        index = next((n for n, c in enumerate(self.contacts) if c.uid == contact.uid), 0)
        store.delete(contact)
        self.contacts = [c for c in self.contacts if c.uid != contact.uid]
        if self.contacts:
            self.chosen = self.contacts[min(index, len(self.contacts) - 1)].uid
        else:
            self.chosen = None
        self.fill_list()
        self.show_card()

    def add_people(self, people):
        known = {c.uid for c in self.contacts}
        added = [p for p in people if p.uid not in known]
        for person in added:
            person.path = None
            store.save(person)
            self.contacts.append(person)
        self.contacts.sort(key=store.Contact.sort_key)
        if added:
            self.chosen = added[0].uid
            self.fill_list()
            self.show_card()
        return added

    def _key(self, _w, event):
        command = event.state & Gdk.ModifierType.CONTROL_MASK
        key = Gdk.keyval_to_lower(event.keyval)
        editing = self.card is not None and self.card.editing
        focus = self.get_focus()
        typing = isinstance(focus, (Gtk.Entry, Gtk.TextView))
        if command:
            actions = {Gdk.KEY_n: self.new_contact, Gdk.KEY_l: self.toggle_editing,
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
        if not editing and not typing and key in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self.delete_chosen()
            return True
        if not editing and not typing and key in (Gdk.KEY_Up, Gdk.KEY_Down):
            rows = self.listbox.get_children()
            current = self.listbox.get_selected_row()
            if rows:
                at = rows.index(current) if current in rows else -1
                at = max(0, min(len(rows) - 1, at + (1 if key == Gdk.KEY_Down else -1)))
                self.listbox.select_row(rows[at])
                rows[at].grab_focus()
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("New Contact", "win.new-contact", "<Ctrl>n")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Edit Card", "win.edit", "<Ctrl>l"), ("Delete Card", "win.delete", "<Ctrl>BackSpace")],
                   [("Find", "win.find", "<Ctrl>f")]]),
    ])


class Crew(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_open(self, files, _count, _hint):
        """Opening .vcf files (from mail, another phone or address book) adds
        the people in them, once each."""
        window = self.get_active_window() or Window(self)
        people = []
        for f in files:
            path = f.get_path()
            if not path:
                continue
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    people += store.parse(handle.read())
            except OSError:
                pass
        added = window.add_people(people)
        known = {c.uid for c in window.contacts}
        if people and not added and people[0].uid in known:
            # Already here (Seek opens a card's own file): show that card.
            window.chosen = people[0].uid
            window.fill_list()
            window.show_card()
        window.present()

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
        # Crew stays open with no window, as a Mac app does; Quit ends it.
        self.hold()
        self.set_menubar(menubar())

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


def main():
    return Crew().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
