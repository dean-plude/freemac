# SPDX-License-Identifier: GPL-3.0-or-later
"""Cue: flashcards.

Make a deck, add cards with a question on the front and the answer on the
back, then study. Each card sits in one of five boxes. A card you know moves
up a box and comes back less often (after 1, 3, 7 and then 14 days); a card
you miss drops to the first box and comes back later in the same session. So
the cards you know least come round most.

Decks can be filled from a spreadsheet saved as CSV or tab-separated text:
the first column is the front and the second the back.

Original freemac code. Decks are kept in ~/.local/share/freemac/cue.json.
"""
import csv
import datetime
import io
import json
import os
import random
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402

from . import alert, menus, style  # noqa: E402

APP_ID = "org.freemac.Cue"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "cue.json")
INTERVALS = (0, 1, 3, 7, 14)   # days before a card in each box comes back
BOXES = len(INTERVALS)
IMPORT_LIMIT = 2 * 1024 * 1024
CARD_LIMIT = 2000
HEADER_WORDS = {"front", "back", "question", "answer", "term", "definition", "word", "meaning"}

SAMPLE = {
    "name": "Capital Cities",
    "cards": [["France", "Paris"], ["Japan", "Tokyo"], ["Italy", "Rome"], ["Spain", "Madrid"],
              ["Canada", "Ottawa"], ["Australia", "Canberra"], ["Egypt", "Cairo"], ["Kenya", "Nairobi"],
              ["Norway", "Oslo"], ["Brazil", "Brasília"], ["Mexico", "Mexico City"], ["India", "New Delhi"]],
}


def today():
    return datetime.date.today().toordinal()


def new_card(front, back):
    return {"front": front, "back": back, "box": 0, "due": 0}


def clean_card(card):
    if not isinstance(card, dict):
        return None
    front, back = card.get("front"), card.get("back")
    if not isinstance(front, str) or not isinstance(back, str):
        return None
    box = card.get("box")
    due = card.get("due")
    return {"front": front, "back": back,
            "box": box if isinstance(box, int) and 0 <= box < BOXES else 0,
            "due": due if isinstance(due, int) else 0}


def is_due(card, day):
    return card["due"] <= day


def study_queue(cards, day, rng, everything=False):
    """The cards to study now: those due, lowest box first, shuffled within a box."""
    chosen = [c for c in cards if everything or is_due(c, day)]
    rng.shuffle(chosen)
    chosen.sort(key=lambda c: c["box"])
    return chosen


def mark(card, knew, day):
    """Move a card after an answer. Returns True when it should come back this session."""
    if knew:
        card["box"] = min(card["box"] + 1, BOXES - 1)
        card["due"] = day + INTERVALS[card["box"]]
        return False
    card["box"] = 0
    card["due"] = day
    return True


def parse_rows(text):
    """(front, back) pairs from CSV or tab-separated text."""
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return []
    sample = "\n".join(lines[:20])
    if "\t" in lines[0]:
        delimiter = "\t"
    else:
        try:
            delimiter = csv.Sniffer().sniff(sample, delimiters=",;").delimiter
        except csv.Error:
            delimiter = ","
    pairs = []
    for row in csv.reader(io.StringIO("\n".join(lines)), delimiter=delimiter):
        cells = [cell.strip() for cell in row]
        if len(cells) < 2 or not cells[0] or not cells[1]:
            continue
        pairs.append((cells[0], cells[1]))
    if len(pairs) > 1 and looks_like_headings(pairs):
        pairs = pairs[1:]
    return pairs[:CARD_LIMIT]


def looks_like_headings(pairs):
    """Whether the first row names the columns rather than being a card."""
    first = pairs[0]
    if first[0].lower() in HEADER_WORDS and first[1].lower() in HEADER_WORDS:
        return True
    rest = pairs[1:]

    def capital(text):
        return text[:1].isupper()
    if not (capital(first[0]) and capital(first[1])) or any(ch.isdigit() for ch in first[0] + first[1]):
        return False
    if len(first[0].split()) > 2 or len(first[1].split()) > 2:
        return False
    lower = sum(1 for f, b in rest if not capital(f) or not capital(b))
    return lower >= max(1, 0.8 * len(rest))


def load_store():
    try:
        with open(STORE) as f:
            data = json.load(f)
    except FileNotFoundError:
        return [{"name": SAMPLE["name"], "cards": [new_card(f, b) for f, b in SAMPLE["cards"]]}]
    except (OSError, ValueError):
        return []
    decks = []
    for deck in data.get("decks", []) if isinstance(data, dict) else []:
        if isinstance(deck, dict) and isinstance(deck.get("name"), str):
            cards = [c for c in map(clean_card, deck.get("cards", []) if isinstance(deck.get("cards"), list)
                                    else []) if c]
            decks.append({"name": deck["name"], "cards": cards})
    return decks


def save_store(decks):
    try:
        os.makedirs(os.path.dirname(STORE), exist_ok=True)
        tmp = STORE + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"decks": decks}, f, ensure_ascii=False)
        os.replace(tmp, STORE)
    except OSError:
        pass


def plural(n, word):
    return f"{n} {word}" + ("" if n == 1 else "s")


CSS = b"""
.cue-card { background-color: @theme_base_color; border-radius: 16px; padding: 28px;
            box-shadow: 0 2px 10px alpha(black, 0.18); }
.cue-front { font-size: 34px; font-weight: 700; }
.cue-back { font-size: 28px; color: @theme_selected_bg_color; font-weight: 600; }
.cue-side { font-size: 11px; font-weight: 700; letter-spacing: 1px; color: alpha(@theme_fg_color, 0.45); }
.cue-count { font-size: 12px; color: alpha(@theme_fg_color, 0.6); }
.cue-deck-name { font-weight: 600; }
.cue-big { font-size: 26px; font-weight: 700; }
.cue-box { font-size: 11px; border-radius: 9px; padding: 1px 7px;
           background-color: alpha(@theme_selected_bg_color, 0.15); }
.cue-knew { min-width: 150px; min-height: 40px; }
.cue-missed { min-width: 150px; min-height: 40px; }
"""


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Cue")
        self.set_default_size(900, 620)
        self.decks = load_store()
        self.rng = random.Random()
        self.current = 0
        self.session = None

        header = Gtk.HeaderBar(show_close_button=True, title="Cue")
        self.set_titlebar(header)
        self.header = header
        add_deck = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        add_deck.set_tooltip_text("New Deck")
        add_deck.connect("clicked", lambda _b: self.new_deck())
        header.pack_start(add_deck)
        importer = Gtk.Button.new_from_icon_name("document-open-symbolic", Gtk.IconSize.BUTTON)
        importer.set_tooltip_text("Import Cards from a Spreadsheet File")
        importer.connect("clicked", lambda _b: self.import_cards())
        header.pack_start(importer)
        self.back = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        self.back.set_tooltip_text("Stop Studying")
        self.back.connect("clicked", lambda _b: self.stop_study())
        header.pack_start(self.back)

        paned = Gtk.Paned()
        self.add(paned)
        side = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side.set_size_request(230, -1)
        self.deck_list = Gtk.ListBox()
        self.deck_list.get_style_context().add_class("sidebar")
        self.deck_list.connect("row-selected", self._deck_selected)
        side.add(self.deck_list)
        self.side = side
        paned.pack1(side, False, False)
        self.pages = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.pages.add_named(self.build_deck_page(), "deck")
        self.pages.add_named(self.build_study_page(), "study")
        self.pages.add_named(self.build_done_page(), "done")
        self.pages.add_named(self.build_empty_page(), "empty")
        paned.pack2(self.pages, True, False)

        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self.connect("key-press-event", self._key)
        menus.add_actions(self, {"close": self.close, "new-deck": self.new_deck, "rename": self.rename_deck,
                                 "delete-deck": self.delete_deck, "import": self.import_cards,
                                 "study": lambda: self.start_study(False),
                                 "study-all": lambda: self.start_study(True)})
        self.show_all()
        self.back.hide()
        self.rebuild_decks()

    # Pages --------------------------------------------------------------------

    def build_deck_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
        top = Gtk.Box(spacing=10)
        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.deck_title = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.deck_title.get_style_context().add_class("cue-big")
        self.deck_summary = Gtk.Label(xalign=0)
        self.deck_summary.get_style_context().add_class("cue-count")
        names.pack_start(self.deck_title, False, False, 0)
        names.pack_start(self.deck_summary, False, False, 0)
        top.pack_start(names, True, True, 0)
        self.study_button = Gtk.Button(label="Study", valign=Gtk.Align.CENTER)
        self.study_button.get_style_context().add_class("suggested-action")
        self.study_button.connect("clicked", lambda _b: self.start_study(False))
        top.pack_end(self.study_button, False, False, 0)
        box.pack_start(top, False, False, 0)

        adder = Gtk.Box(spacing=8)
        self.front_entry = Gtk.Entry(placeholder_text="Front: a question or word", hexpand=True)
        self.back_entry = Gtk.Entry(placeholder_text="Back: its answer", hexpand=True)
        self.front_entry.connect("activate", lambda _e: self.back_entry.grab_focus())
        self.back_entry.connect("activate", lambda _e: self.add_card())
        add = Gtk.Button(label="Add Card")
        add.connect("clicked", lambda _b: self.add_card())
        for widget in (self.front_entry, self.back_entry):
            adder.pack_start(widget, True, True, 0)
        adder.pack_start(add, False, False, 0)
        box.pack_start(adder, False, False, 0)

        self.model = Gtk.ListStore(str, str, str, int)
        self.view = Gtk.TreeView(model=self.model, headers_visible=True, enable_search=False)
        self.view.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        for column, title in ((0, "Front"), (1, "Back")):
            cell = Gtk.CellRendererText(editable=True, ellipsize=Pango.EllipsizeMode.END)
            cell.connect("edited", self._edited, column)
            col = Gtk.TreeViewColumn(title, cell, text=column)
            col.set_expand(True)
            col.set_resizable(True)
            self.view.append_column(col)
        known = Gtk.TreeViewColumn("Learned", Gtk.CellRendererText(), text=2)
        self.view.append_column(known)
        self.view.connect("key-press-event", self._view_key)
        scroller = Gtk.ScrolledWindow(vexpand=True)
        scroller.get_style_context().add_class("frame")
        scroller.add(self.view)
        box.pack_start(scroller, True, True, 0)

        bottom = Gtk.Box(spacing=8)
        remove = Gtk.Button(label="Delete Card")
        remove.connect("clicked", lambda _b: self.delete_cards())
        tip = Gtk.Label(label="Double-click a card to change it.", xalign=0)
        tip.get_style_context().add_class("dim-label")
        bottom.pack_start(tip, True, True, 0)
        bottom.pack_end(remove, False, False, 0)
        box.pack_start(bottom, False, False, 0)
        return box

    def build_study_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=28)
        self.progress = Gtk.ProgressBar()
        self.progress_label = Gtk.Label(xalign=0.5)
        self.progress_label.get_style_context().add_class("cue-count")
        box.pack_start(self.progress, False, False, 0)
        box.pack_start(self.progress_label, False, False, 0)
        card = Gtk.EventBox()
        card.connect("button-press-event", lambda *_a: self.flip())
        face = Gtk.Box(valign=Gtk.Align.CENTER)
        face.get_style_context().add_class("cue-card")
        face.set_size_request(-1, 300)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, valign=Gtk.Align.CENTER)
        face.pack_start(inner, True, True, 0)
        front_side = Gtk.Label(label="FRONT")
        front_side.get_style_context().add_class("cue-side")
        self.front_label = Gtk.Label(wrap=True, justify=Gtk.Justification.CENTER, selectable=False)
        self.front_label.get_style_context().add_class("cue-front")
        self.front_label.set_max_width_chars(40)
        self.back_side = Gtk.Label(label="BACK")
        self.back_side.get_style_context().add_class("cue-side")
        self.back_label = Gtk.Label(wrap=True, justify=Gtk.Justification.CENTER)
        self.back_label.get_style_context().add_class("cue-back")
        self.back_label.set_max_width_chars(40)
        for widget in (front_side, self.front_label, self.back_side, self.back_label):
            inner.pack_start(widget, False, False, 0)
        card.add(face)
        box.pack_start(card, True, True, 0)
        self.answer_buttons = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        show = Gtk.Button(label="Show Answer", halign=Gtk.Align.CENTER)
        show.get_style_context().add_class("suggested-action")
        show.get_style_context().add_class("cue-knew")
        show.set_tooltip_text("Space")
        show.connect("clicked", lambda _b: self.flip())
        self.answer_buttons.add_named(show, "show")
        pair = Gtk.Box(spacing=14, halign=Gtk.Align.CENTER)
        missed = Gtk.Button(label="Didn't Know It")
        missed.get_style_context().add_class("cue-missed")
        missed.set_tooltip_text("1")
        missed.connect("clicked", lambda _b: self.answer(False))
        knew = Gtk.Button(label="Knew It")
        knew.get_style_context().add_class("suggested-action")
        knew.get_style_context().add_class("cue-knew")
        knew.set_tooltip_text("2")
        knew.connect("clicked", lambda _b: self.answer(True))
        pair.pack_start(missed, False, False, 0)
        pair.pack_start(knew, False, False, 0)
        self.answer_buttons.add_named(pair, "judge")
        box.pack_start(self.answer_buttons, False, False, 0)
        hint = Gtk.Label(label="Space shows the answer. Then press 1 if you didn't know it, or 2 if you did.")
        hint.get_style_context().add_class("dim-label")
        box.pack_start(hint, False, False, 0)
        return box

    def build_done_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER, margin=28)
        icon = Gtk.Image.new_from_icon_name("emblem-ok-symbolic", Gtk.IconSize.DIALOG)
        icon.set_pixel_size(64)
        self.done_title = Gtk.Label()
        self.done_title.get_style_context().add_class("cue-big")
        self.done_text = Gtk.Label(justify=Gtk.Justification.CENTER, wrap=True)
        buttons = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER)
        back = Gtk.Button(label="Back to the Deck")
        back.connect("clicked", lambda _b: self.stop_study())
        self.more = Gtk.Button(label="Study Them All Anyway")
        self.more.connect("clicked", lambda _b: self.start_study(True))
        buttons.pack_start(back, False, False, 0)
        buttons.pack_start(self.more, False, False, 0)
        for widget in (icon, self.done_title, self.done_text):
            box.pack_start(widget, False, False, 0)
        box.pack_start(buttons, False, False, 8)
        return box

    def build_empty_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER, margin=28)
        title = Gtk.Label(label="No Decks")
        title.get_style_context().add_class("cue-big")
        text = Gtk.Label(label="Make a deck, then add cards to it, or import them from a spreadsheet file.")
        text.get_style_context().add_class("dim-label")
        new = Gtk.Button(label="New Deck", halign=Gtk.Align.CENTER)
        new.get_style_context().add_class("suggested-action")
        new.connect("clicked", lambda _b: self.new_deck())
        for widget in (title, text, new):
            box.pack_start(widget, False, False, 0)
        return box

    # Decks --------------------------------------------------------------------

    def deck(self):
        return self.decks[self.current] if 0 <= self.current < len(self.decks) else None

    def save(self):
        save_store(self.decks)

    def rebuild_decks(self):
        for row in self.deck_list.get_children():
            self.deck_list.remove(row)
        day = today()
        for deck in self.decks:
            row = Gtk.ListBoxRow()
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1, margin=8)
            name = Gtk.Label(label=deck["name"], xalign=0, ellipsize=Pango.EllipsizeMode.END)
            name.get_style_context().add_class("cue-deck-name")
            due = sum(1 for c in deck["cards"] if is_due(c, day))
            count = Gtk.Label(label=plural(len(deck["cards"]), "card") + (f", {due} to study" if due else ""),
                              xalign=0)
            count.get_style_context().add_class("cue-count")
            box.pack_start(name, False, False, 0)
            box.pack_start(count, False, False, 0)
            row.add(box)
            self.deck_list.add(row)
        self.deck_list.show_all()
        if not self.decks:
            self.pages.set_visible_child_name("empty")
            return
        self.current = max(0, min(self.current, len(self.decks) - 1))
        self.deck_list.select_row(self.deck_list.get_row_at_index(self.current))
        self.show_deck()

    def _deck_selected(self, _list, row):
        if row is None:
            return
        self.current = row.get_index()
        if self.session is None:
            self.show_deck()

    def show_deck(self):
        deck = self.deck()
        if deck is None:
            return
        day = today()
        due = sum(1 for c in deck["cards"] if is_due(c, day))
        learned = sum(1 for c in deck["cards"] if c["box"] == BOXES - 1)
        self.deck_title.set_text(deck["name"])
        parts = [plural(len(deck["cards"]), "card")]
        if deck["cards"]:
            parts.append(f"{due} to study today" if due else "nothing to study today")
            parts.append(f"{learned} learned")
        self.deck_summary.set_text(", ".join(parts))
        self.study_button.set_label("Study" if due or not deck["cards"] else "Study Anyway")
        self.study_button.set_sensitive(bool(deck["cards"]))
        self.model.clear()
        for n, card in enumerate(deck["cards"]):
            self.model.append([card["front"], card["back"], "●" * card["box"] + "○" * (BOXES - 1 - card["box"]),
                               n])
        self.pages.set_visible_child_name("deck")

    def ask_name(self, title, button, initial=""):
        dialog = alert.build(self, title, "", [("Cancel", Gtk.ResponseType.CANCEL), (button, Gtk.ResponseType.OK)],
                             default=Gtk.ResponseType.OK)
        body = dialog.get_content_area().get_children()[0]
        entry = Gtk.Entry(text=initial, activates_default=True, width_chars=28, placeholder_text="Deck name")
        body.pack_start(entry, False, False, 0)
        body.reorder_child(entry, len(body.get_children()) - 2)
        entry.show()
        entry.grab_focus()
        answer = dialog.run()
        text = entry.get_text().strip()
        dialog.destroy()
        return text if answer == Gtk.ResponseType.OK and text else None

    def new_deck(self, name=None):
        if self.session is not None:
            return None
        name = name or self.ask_name("New Deck", "Create")
        if not name:
            return None
        self.decks.append({"name": name[:80], "cards": []})
        self.current = len(self.decks) - 1
        self.save()
        self.rebuild_decks()
        self.front_entry.grab_focus()
        return self.decks[-1]

    def rename_deck(self):
        deck = self.deck()
        if deck is None or self.session is not None:
            return
        name = self.ask_name("Rename Deck", "Rename", deck["name"])
        if name:
            deck["name"] = name[:80]
            self.save()
            self.rebuild_decks()

    def delete_deck(self):
        deck = self.deck()
        if deck is None or self.session is not None:
            return
        answer = alert.ask(self, f"Delete the deck {deck['name']}?",
                           f"Its {plural(len(deck['cards']), 'card')} will be deleted too.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Delete", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
        if answer == Gtk.ResponseType.OK:
            del self.decks[self.current]
            self.current = max(0, self.current - 1)
            self.save()
            self.rebuild_decks()

    # Cards --------------------------------------------------------------------

    def add_card(self):
        front = self.front_entry.get_text().strip()
        back = self.back_entry.get_text().strip()
        if not front or not back:
            (self.front_entry if not front else self.back_entry).grab_focus()
            return
        deck = self.deck() or self.new_deck("My Cards")
        if deck is None:
            return
        deck["cards"].append(new_card(front, back))
        self.save()
        self.front_entry.set_text("")
        self.back_entry.set_text("")
        self.front_entry.grab_focus()
        self.rebuild_decks()
        last = self.model.iter_nth_child(None, len(self.model) - 1)
        if last:
            self.view.scroll_to_cell(self.model.get_path(last), None, False, 0, 0)

    def _edited(self, _cell, path, text, column):
        deck = self.deck()
        text = text.strip()
        if deck is None or not text:
            return
        index = self.model[path][3]
        deck["cards"][index]["front" if column == 0 else "back"] = text
        self.model[path][column] = text
        self.save()

    def delete_cards(self):
        deck = self.deck()
        model, paths = self.view.get_selection().get_selected_rows()
        if deck is None or not paths:
            return
        doomed = {model[p][3] for p in paths}
        deck["cards"] = [c for n, c in enumerate(deck["cards"]) if n not in doomed]
        self.save()
        self.rebuild_decks()

    def _view_key(self, _view, event):
        if event.keyval in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self.delete_cards()
            return True
        return False

    def import_cards(self):
        if self.session is not None:
            return
        chooser = Gtk.FileChooserNative.new("Import Cards", self, Gtk.FileChooserAction.OPEN, "Import", "Cancel")
        kinds = Gtk.FileFilter()
        kinds.set_name("Spreadsheet text (CSV or tab-separated)")
        for pattern in ("*.csv", "*.CSV", "*.tsv", "*.TSV", "*.txt"):
            kinds.add_pattern(pattern)
        chooser.add_filter(kinds)
        if chooser.run() != Gtk.ResponseType.ACCEPT:
            return
        path = chooser.get_filename()
        try:
            with open(path, "rb") as handle:
                raw = handle.read(IMPORT_LIMIT)
        except OSError:
            alert.tell(self, "Cue couldn't open that file", "Check that it's still there and you can read it.")
            return
        text = raw.decode("utf-8-sig", errors="replace")
        pairs = parse_rows(text)
        if not pairs:
            alert.tell(self, "No cards found in that file",
                       "Cue reads the first column as the front of each card and the second as the back.")
            return
        name = os.path.splitext(os.path.basename(path))[0].replace("_", " ").strip() or "Imported Cards"
        deck = self.deck()
        if deck is not None:
            answer = alert.ask(self, f"Add {plural(len(pairs), 'card')}?",
                               f"Add them to {deck['name']}, or make a new deck called {name}.",
                               [("Cancel", Gtk.ResponseType.CANCEL), ("New Deck", Gtk.ResponseType.NO),
                                (f"Add to {deck['name'][:24]}", Gtk.ResponseType.OK)],
                               default=Gtk.ResponseType.OK)
            if answer == Gtk.ResponseType.NO:
                deck = None
            elif answer != Gtk.ResponseType.OK:
                return
        if deck is None:
            self.decks.append({"name": name[:80], "cards": []})
            self.current = len(self.decks) - 1
            deck = self.decks[-1]
        known = {(c["front"], c["back"]) for c in deck["cards"]}
        deck["cards"].extend(new_card(f, b) for f, b in pairs if (f, b) not in known)
        self.save()
        self.rebuild_decks()

    # Studying -----------------------------------------------------------------

    def start_study(self, everything):
        deck = self.deck()
        if deck is None or not deck["cards"]:
            return
        day = today()
        queue = study_queue(deck["cards"], day, self.rng, everything)
        if not queue:
            queue = study_queue(deck["cards"], day, self.rng, True)
        self.session = {"queue": queue, "total": len(queue), "done": 0, "knew": 0, "missed": set(),
                        "flipped": False, "day": day}
        self.back.show()
        self.side.set_sensitive(False)
        self.header.set_subtitle(deck["name"])
        self.pages.set_visible_child_name("study")
        self.show_card()

    def show_card(self):
        session = self.session
        card = session["queue"][0]
        session["flipped"] = False
        self.front_label.set_text(card["front"])
        self.back_label.set_text(card["back"])
        self.back_label.set_opacity(0)
        self.back_side.set_opacity(0)
        self.answer_buttons.set_visible_child_name("show")
        left = len(session["queue"])
        self.progress.set_fraction(session["done"] / max(1, session["done"] + left))
        self.progress_label.set_text(f"{plural(left, 'card')} to go")

    def flip(self):
        session = self.session
        if session is None or session["flipped"]:
            return
        session["flipped"] = True
        self.back_label.set_opacity(1)
        self.back_side.set_opacity(1)
        self.answer_buttons.set_visible_child_name("judge")

    def answer(self, knew):
        session = self.session
        if session is None or not session["flipped"]:
            return
        card = session["queue"].pop(0)
        again = mark(card, knew, session["day"])
        if again:
            session["missed"].add(id(card))
            at = min(len(session["queue"]), 3 + self.rng.randint(0, 2))
            session["queue"].insert(at, card)
        else:
            session["done"] += 1
            if id(card) not in session["missed"]:
                session["knew"] += 1
        self.save()
        if session["queue"]:
            self.show_card()
        else:
            self.finish_study()

    def finish_study(self):
        session = self.session
        deck = self.deck()
        self.done_title.set_text("All Done")
        total, knew = session["total"], session["knew"]
        text = f"You went through {plural(total, 'card')} and knew {knew} of them first time."
        nxt = min((c["due"] for c in deck["cards"]), default=None)
        if nxt is not None and nxt > session["day"]:
            days = nxt - session["day"]
            text += "\nThe next cards come back " + ("tomorrow." if days == 1 else f"in {days} days.")
        self.done_text.set_text(text)
        self.more.set_visible(nxt is not None and nxt > session["day"])
        self.session = None
        self.pages.set_visible_child_name("done")
        self.back.hide()
        self.side.set_sensitive(True)
        self.header.set_subtitle(None)
        self.rebuild_decks()
        self.pages.set_visible_child_name("done")

    def stop_study(self):
        self.session = None
        self.back.hide()
        self.side.set_sensitive(True)
        self.header.set_subtitle(None)
        self.rebuild_decks()

    def _key(self, _w, event):
        if self.session is None:
            return False
        key = event.keyval
        if key in (Gdk.KEY_space, Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.flip()
            return True
        if key in (Gdk.KEY_1, Gdk.KEY_KP_1, Gdk.KEY_Left):
            self.answer(False)
            return True
        if key in (Gdk.KEY_2, Gdk.KEY_KP_2, Gdk.KEY_Right):
            self.answer(True)
            return True
        if key == Gdk.KEY_Escape:
            self.stop_study()
            return True
        return False

    def about(self):
        alert.tell(self, "About Cue", "Cue is a flashcard app, part of freemac.")


def menubar():
    return menus.menubar([
        ("_File", [[("New Deck", "win.new-deck", "<Ctrl>n"), ("Import Cards…", "win.import", "<Ctrl>o")],
                   [("Rename Deck…", "win.rename", None), ("Delete Deck…", "win.delete-deck", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Study", [[("Study Today's Cards", "win.study", "<Ctrl>Return"),
                     ("Study Every Card", "win.study-all", "<Shift><Ctrl>Return")]]),
    ])


class Cue(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close(),
                                 "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_accels_for_action("win.new-deck", ["<Control>n"])
        self.set_accels_for_action("win.import", ["<Control>o"])
        self.set_accels_for_action("win.study", ["<Control>Return"])
        self.set_accels_for_action("win.study-all", ["<Shift><Control>Return"])
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-cue")
    return Cue().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
