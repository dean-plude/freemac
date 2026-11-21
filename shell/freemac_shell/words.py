# SPDX-License-Identifier: GPL-3.0-or-later
"""Words: a dictionary that works without the internet.

Type a word to see what it means, with examples, words that mean the same
and words that mean the opposite. Click any of those to look it up in turn.
Words knows a word's other forms too, so "ran", "mice" and "happier" find
"run", "mouse" and "happy".

The definitions come from WordNet 3.0 (Princeton University), installed as
/usr/share/wordnet by Debian's wordnet-base package. WordNet's licence lets
anyone use and share it; its notice is shown in About Words. This file is
original freemac code that reads WordNet's published file format.
"""
import bisect
import datetime
import difflib
import html
import os
import re
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Words"
WORDNET = os.environ.get("FREEMAC_WORDNET", "/usr/share/wordnet")
POS_FILES = {"n": "noun", "v": "verb", "a": "adj", "r": "adv"}
POS_NAMES = {"n": "noun", "v": "verb", "a": "adjective", "r": "adverb"}
POS_ORDER = ("n", "v", "a", "r")
# How a word's endings change, for finding the word a form comes from.
ENDINGS = {
    "n": [("s", ""), ("ses", "s"), ("xes", "x"), ("zes", "z"), ("ches", "ch"), ("shes", "sh"),
          ("men", "man"), ("ies", "y")],
    "v": [("s", ""), ("ies", "y"), ("es", "e"), ("es", ""), ("ed", "e"), ("ed", ""), ("ing", "e"),
          ("ing", "")],
    "a": [("er", ""), ("est", ""), ("er", "e"), ("est", "e")],
    "r": [],
}
NOTICE = ("WordNet 3.0 Copyright 2006 by Princeton University. All rights reserved.\n\n"
          "THIS SOFTWARE AND DATABASE IS PROVIDED \"AS IS\" AND PRINCETON UNIVERSITY MAKES NO "
          "REPRESENTATIONS OR WARRANTIES, EXPRESS OR IMPLIED. BY WAY OF EXAMPLE, BUT NOT LIMITATION, "
          "PRINCETON UNIVERSITY MAKES NO REPRESENTATIONS OR WARRANTIES OF MERCHANTABILITY OR FITNESS "
          "FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF THE LICENSED SOFTWARE, DATABASE OR "
          "DOCUMENTATION WILL NOT INFRINGE ANY THIRD PARTY PATENTS, COPYRIGHTS, TRADEMARKS OR OTHER "
          "RIGHTS.\n\nThe full licence is in /usr/share/doc/wordnet-base/copyright.")


def key(text):
    """How WordNet spells a word in its files: lower case, _ for spaces."""
    return re.sub(r"\s+", "_", text.strip().lower())


def shown(lemma):
    return lemma.replace("_", " ")


class Sense:
    __slots__ = ("pos", "words", "definition", "examples", "pointers")

    def __init__(self, pos, words, definition, examples, pointers):
        self.pos, self.words, self.definition = pos, words, definition
        self.examples, self.pointers = examples, pointers


class WordNet:
    """Reads WordNet's index, data and exception files."""

    def __init__(self, folder=WORDNET):
        self.folder = folder
        self.index = {}      # pos -> {lemma: [synset offsets]}
        self.exceptions = {}  # pos -> {form: [lemmas]}
        self.data = {}
        common = set()      # well-known words, for the word of the day
        for pos, name in POS_FILES.items():
            table = {}
            with open(os.path.join(folder, "index." + name), encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.startswith(" "):
                        continue
                    parts = line.split()
                    try:
                        pointer_count = int(parts[3])
                        sense_count = int(parts[2])
                    except (IndexError, ValueError):
                        continue
                    start = 6 + pointer_count
                    table[parts[0]] = [int(o) for o in parts[start:start + sense_count]]
                    if (pos in "na" and parts[0].isalpha() and 6 <= len(parts[0]) <= 12
                            and int(parts[start - 1]) >= 3):
                        common.add(parts[0])
            self.index[pos] = table
            forms = {}
            try:
                with open(os.path.join(folder, name + ".exc"), encoding="utf-8", errors="replace") as f:
                    for line in f:
                        parts = line.split()
                        if len(parts) >= 2:
                            forms.setdefault(parts[0], []).extend(parts[1:])
            except OSError:
                pass
            self.exceptions[pos] = forms
            self.data[pos] = open(os.path.join(folder, "data." + name), "rb")
        self.lemmas = sorted(set().union(*(t.keys() for t in self.index.values())))
        self.common = sorted(common)
        self._synsets = {}

    @classmethod
    def available(cls, folder=WORDNET):
        return all(os.path.exists(os.path.join(folder, f"{k}.{n}"))
                   for n in POS_FILES.values() for k in ("index", "data"))

    def synset(self, pos, offset):
        """One meaning: (pos, words, definition, examples, pointers)."""
        cached = self._synsets.get((pos, offset))
        if cached:
            return cached
        f = self.data[pos]
        f.seek(offset)
        line = f.readline().decode("utf-8", "replace")
        head, _bar, gloss = line.partition(" | ")
        parts = head.split()
        count = int(parts[3], 16)
        words = [re.sub(r"\(.*\)$", "", parts[4 + 2 * i]) for i in range(count)]
        at = 4 + 2 * count
        pointers = []
        for i in range(int(parts[at])):
            symbol, target, target_pos, source_target = parts[at + 1 + 4 * i: at + 5 + 4 * i]
            pointers.append((symbol, int(target), "a" if target_pos == "s" else target_pos,
                             int(source_target[:2], 16), int(source_target[2:], 16)))
        gloss = gloss.strip().replace("--", "\u2014")
        examples = re.findall(r'"([^"]+)"', gloss)
        definition = re.split(r';?\s*"', gloss, maxsplit=1)[0].strip().rstrip(";").strip()
        sense = Sense(pos, words, definition, examples, pointers)
        self._synsets[(pos, offset)] = sense
        return sense

    def base_forms(self, text):
        """{pos: [lemma, ...]}: the words in the dictionary this could be a form of."""
        word = key(text)
        found = {}
        for pos in POS_ORDER:
            table = self.index[pos]
            forms = []
            if word in table:
                forms.append(word)
            for base in self.exceptions[pos].get(word, []):
                if base in table and base not in forms:
                    forms.append(base)
            for ending, replacement in ENDINGS[pos]:
                if word.endswith(ending) and len(word) > len(ending):
                    base = word[: len(word) - len(ending)] + replacement
                    if base in table and base not in forms:
                        forms.append(base)
            if forms:
                found[pos] = forms
        return found

    def look_up(self, text):
        """[(pos, lemma, [Sense, ...])], most usual meaning first."""
        entries = []
        for pos, lemmas in self.base_forms(text).items():
            for lemma in lemmas:
                entries.append((pos, lemma, [self.synset(pos, o) for o in self.index[pos][lemma]]))
        return entries

    def related(self, sense, symbols, lemma=None):
        """Words linked to a meaning. A pointer with a source number belongs to
        one word of the meaning only; those count only for lemma."""
        out = []
        for symbol, target, pos, source, dest in sense.pointers:
            if symbol not in symbols:
                continue
            if source and lemma is not None:
                if source - 1 >= len(sense.words) or sense.words[source - 1].lower() != lemma:
                    continue
            other = self.synset(pos, target)
            words = [other.words[dest - 1]] if dest and dest - 1 < len(other.words) else other.words[:3]
            for word in words:
                if word not in out:
                    out.append(word)
        return out

    def starting_with(self, prefix, limit=60):
        prefix = key(prefix)
        if not prefix:
            return []
        start = bisect.bisect_left(self.lemmas, prefix)
        out = []
        for lemma in self.lemmas[start:]:
            if not lemma.startswith(prefix) or len(out) >= limit:
                break
            out.append(lemma)
        return out

    def close_to(self, text, limit=6):
        word = key(text)
        if not word:
            return []
        start = bisect.bisect_left(self.lemmas, word[0])
        end = bisect.bisect_left(self.lemmas, chr(ord(word[0]) + 1))
        pool = [w for w in self.lemmas[start:end] if abs(len(w) - len(word)) <= 2]
        return difflib.get_close_matches(word, pool, n=limit, cutoff=0.72)

    def word_of_the_day(self, day=None):
        """The same word all day, a different one each day."""
        day = day or datetime.date.today()
        if not self.common:
            return None
        return self.common[(day.toordinal() * 7919) % len(self.common)]


def link(word):
    return f'<a href="{html.escape("word:" + word)}">{html.escape(shown(word))}</a>'


class Page(Gtk.Box):
    """One word's entry."""

    def __init__(self, window):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.window = window
        self.set_border_width(28)

    def label(self, markup, css=None, top=0, wrap=True, selectable=True):
        widget = Gtk.Label(xalign=0, wrap=wrap, selectable=selectable)
        widget.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        widget.set_markup(markup)
        widget.set_margin_top(top)
        widget.set_can_focus(False)
        if css:
            widget.get_style_context().add_class(css)
        widget.connect("activate-link", self._clicked)
        self.pack_start(widget, False, False, 0)
        return widget

    def _clicked(self, _label, uri):
        if uri.startswith("word:"):
            GLib.idle_add(self.window.show_word, uri[5:])
        return True

    def clear(self):
        for child in self.get_children():
            self.remove(child)
            child.destroy()

    def show_entry(self, wn, asked, entries, note=None):
        self.clear()
        if note:
            self.label(html.escape(note), "words-note", selectable=False)
        heads = []
        for _pos, lemma, _senses in entries:
            if lemma not in heads:
                heads.append(lemma)
        self.label(html.escape(" · ".join(shown(h) for h in heads)), "words-title")
        if key(asked) not in heads:
            self.label(f"<i>{html.escape(asked.strip())}</i> is a form of "
                       + ", ".join(link(h) for h in heads), "words-form", selectable=False)
        for pos, lemma, senses in entries:
            heading = POS_NAMES[pos]
            if len(heads) > 1:
                heading += f"  ·  {shown(lemma)}"
            self.label(html.escape(heading), "words-pos", top=18)
            for number, sense in enumerate(senses, 1):
                self.label(f"<b>{number}</b>  {html.escape(sense.definition)}", "words-def", top=8)
                for example in sense.examples[:3]:
                    self.label(f"“{html.escape(example)}”", "words-example")
                same = [w for w in sense.words if w.lower() != lemma]
                if pos == "a":
                    same += [w for w in wn.related(sense, {"&"}) if w not in same and w.lower() != lemma]
                if same:
                    self.label("<span weight='600'>Same as</span>  " + ", ".join(link(w) for w in same[:8]),
                               "words-rel", selectable=False)
                opposite = wn.related(sense, {"!"}, lemma)
                if opposite:
                    self.label("<span weight='600'>Opposite</span>  " + ", ".join(link(w) for w in opposite),
                               "words-rel", selectable=False)
                if pos in ("n", "v"):
                    kind = wn.related(sense, {"@", "@i"})
                    if kind:
                        self.label("<span weight='600'>A kind of</span>  "
                                   + ", ".join(link(w) for w in kind[:4]), "words-rel", selectable=False)
        self.show_all()

    def show_missing(self, asked, suggestions):
        self.clear()
        self.label(html.escape(asked.strip()), "words-title")
        self.label("This word isn't in the dictionary.", "words-def", top=8, selectable=False)
        if suggestions:
            self.label("<span weight='600'>Did you mean</span>  " + ", ".join(link(w) for w in suggestions),
                       "words-rel", top=8, selectable=False)
        self.show_all()

    def show_message(self, title, text):
        self.clear()
        self.label(html.escape(title), "words-title", selectable=False)
        self.label(html.escape(text), "words-def", top=8, selectable=False)
        self.show_all()


CSS = b"""
.words-scroll, .words-scroll viewport { background-color: @theme_base_color; }
.words-title { font-size: 30px; font-weight: 700; }
.words-note { font-size: 12px; font-weight: 600; color: #0a7cff; letter-spacing: 1px; }
.words-form { color: alpha(@theme_fg_color, 0.65); margin-top: 2px; }
.words-pos { font-style: italic; font-size: 15px; color: #c2410c; }
.words-def { font-size: 15px; }
.words-example { font-style: italic; color: alpha(@theme_fg_color, 0.6); margin-left: 22px; }
.words-rel { color: alpha(@theme_fg_color, 0.75); margin-left: 22px; font-size: 13px; }
.words-list row { padding: 5px 12px; }
"""


class Window(Gtk.ApplicationWindow):
    def __init__(self, app, first=None):
        super().__init__(application=app, title="Words")
        self.set_default_size(900, 640)
        self.wn = None
        self.history = []
        self.place = -1
        header = Gtk.HeaderBar(show_close_button=True, title="Words")
        self.header = header
        self.set_titlebar(header)
        nav = Gtk.Box()
        nav.get_style_context().add_class("linked")
        self.back = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        self.back.set_tooltip_text("Back")
        self.back.connect("clicked", lambda _b: self.go(-1))
        self.forward = Gtk.Button.new_from_icon_name("go-next-symbolic", Gtk.IconSize.BUTTON)
        self.forward.set_tooltip_text("Forward")
        self.forward.connect("clicked", lambda _b: self.go(1))
        nav.pack_start(self.back, False, False, 0)
        nav.pack_start(self.forward, False, False, 0)
        header.pack_start(nav)
        self.search = Gtk.SearchEntry(placeholder_text="Look up a word", width_chars=26)
        self.search.connect("search-changed", self._typed)
        self.search.connect("activate", self._entered)
        self.search.connect("key-press-event", self._search_key)
        header.pack_end(self.search)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        paned = Gtk.Paned()
        self.matches = Gtk.ListBox()
        self.matches.get_style_context().add_class("words-list")
        self.matches.connect("row-activated", lambda _l, row: self.show_word(row.lemma))
        side = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side.set_size_request(220, -1)
        side.add(self.matches)
        paned.pack1(side, False, False)
        self.page = Page(self)
        self.scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.scroller.get_style_context().add_class("words-scroll")
        self.scroller.add(self.page)
        paned.pack2(self.scroller, True, False)
        self.add(paned)
        menus.add_actions(self, {"close": self.close, "find": self.search.grab_focus,
                                 "back": lambda: self.go(-1), "forward": lambda: self.go(1),
                                 "today": self.show_today})
        self.page.show_message("Words", "Getting the dictionary ready…")
        self.show_all()
        self._update_nav()
        GLib.idle_add(self._load, first)

    def _load(self, first):
        if not WordNet.available():
            self.page.show_message("The dictionary isn't installed",
                                   "Words needs WordNet, which comes with freemac. "
                                   "To add it, install the wordnet-base package.")
            return False
        self.wn = WordNet()
        if first:
            self.search.set_text(first)
            self.show_word(first)
        else:
            self.show_today()
        self.search.grab_focus()
        return False

    def show_today(self):
        if not self.wn:
            return
        word = self.wn.word_of_the_day()
        if word:
            self.show_word(word, note="WORD OF THE DAY")

    def _typed(self, entry):
        if not self.wn:
            return
        for row in self.matches.get_children():
            self.matches.remove(row)
        text = entry.get_text()
        found = self.wn.starting_with(text) if text.strip() else list(reversed(self.history[-60:]))
        if not text.strip() and found:
            heading = Gtk.Label(label="RECENT", xalign=0)
            heading.get_style_context().add_class("words-note")
            row = Gtk.ListBoxRow(selectable=False, activatable=False)
            row.add(heading)
            self.matches.add(row)
        for lemma in dict.fromkeys(found):
            row = Gtk.ListBoxRow()
            row.lemma = lemma
            row.add(Gtk.Label(label=shown(lemma), xalign=0, ellipsize=Pango.EllipsizeMode.END))
            self.matches.add(row)
        self.matches.show_all()

    def _entered(self, entry):
        text = entry.get_text().strip()
        if text:
            self.show_word(text)
            entry.select_region(0, -1)    # the next word typed replaces this one

    def _search_key(self, _entry, event):
        if event.keyval == Gdk.KEY_Down:
            row = self.matches.get_row_at_index(0)
            if row:
                row.grab_focus()
                return True
        return False

    def show_word(self, text, note=None, remember=True):
        if not self.wn or not text.strip():
            return False
        entries = self.wn.look_up(text)
        if entries:
            self.page.show_entry(self.wn, text, entries, note)
            self.header.set_subtitle(shown(entries[0][1]))
        else:
            self.page.show_missing(text, [w for w in self.wn.close_to(text)])
            self.header.set_subtitle(None)
        if remember:
            word = key(text)
            if self.place < 0 or self.history[self.place] != word:
                del self.history[self.place + 1:]
                self.history.append(word)
                self.place = len(self.history) - 1
        self.scroller.get_vadjustment().set_value(0)
        self._update_nav()
        if not self.search.get_text().strip():
            self._typed(self.search)
        return False

    def go(self, step):
        place = self.place + step
        if 0 <= place < len(self.history):
            self.place = place
            self.show_word(self.history[place], remember=False)

    def _update_nav(self):
        self.back.set_sensitive(self.place > 0)
        self.forward.set_sensitive(0 <= self.place < len(self.history) - 1)

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK,
                                   text="About Words")
        dialog.format_secondary_text("Words is part of freemac. Its definitions come from WordNet 3.0, "
                                     "made at Princeton University.\n\n" + NOTICE)
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_File", [[("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Find a Word", "win.find", "<Ctrl>f")]]),
        ("_Go", [[("Back", "win.back", "<Ctrl>bracketleft"), ("Forward", "win.forward", "<Ctrl>bracketright")],
                 [("Word of the Day", "win.today", "<Ctrl>t")]]),
    ])


class Words(Gtk.Application):
    def __init__(self, first=None):
        super().__init__(application_id=APP_ID)
        self.window = None
        self.first = first

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close(),
                                 "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.close", "<Control>w"), ("win.find", "<Control>f"),
                             ("win.back", "<Control>bracketleft"), ("win.forward", "<Control>bracketright"),
                             ("win.today", "<Control>t")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self, self.first)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-words")
    first = " ".join(a for a in sys.argv[1:] if not a.startswith("-")) or None
    return Words(first).run(sys.argv[:1])


if __name__ == "__main__":
    sys.exit(main())
