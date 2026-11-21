# SPDX-License-Identifier: GPL-3.0-or-later
"""Books: read e-books.

Your EPUB books sit on a shelf with their covers. Books keeps them in the
Books folder in your home; Add Books copies new ones there, and opening an
EPUB from Files works too. A book reads page by page: click the right side of
the page or press → for the next page, the left side or ← to go back. The
contents list jumps to a chapter, Aa makes the text bigger or smaller and
picks light, sepia or night pages, and Books keeps your place in every book.

Pages are shown by WebKit with the book's own scripts switched off; only
files inside the book are loaded, through a book:// address. Original
freemac code; places and settings are kept in
~/.local/share/freemac/books.json.
"""
import hashlib
import json
import os
import posixpath
import shutil
import sys
import time
import zipfile
from urllib.parse import quote, unquote, urlparse
from xml.etree import ElementTree as ET

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
gi.require_version("WebKit2", "4.1")
import cairo  # noqa: E402
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango, PangoCairo, WebKit2  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Books"
NS = {
    "c": "urn:oasis:names:tc:opendocument:xmlns:container",
    "opf": "http://www.idpf.org/2007/opf",
    "dc": "http://purl.org/dc/elements/1.1/",
    "ncx": "http://www.daisy.org/z3986/2005/ncx/",
    "x": "http://www.w3.org/1999/xhtml",
}
EPUB_TYPE = "{http://www.idpf.org/2007/ops}type"
MIME = {
    ".xhtml": "application/xhtml+xml", ".html": "text/html", ".htm": "text/html", ".xml": "application/xml",
    ".css": "text/css", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".gif": "image/gif",
    ".svg": "image/svg+xml", ".webp": "image/webp", ".ttf": "font/ttf", ".otf": "font/otf",
    ".woff": "font/woff", ".woff2": "font/woff2",
}
THEMES = {
    "light": {"bg": "#fbfbf9", "fg": "#1d1d1f", "link": "#0066cc"},
    "sepia": {"bg": "#f5ecda", "fg": "#4b3b28", "link": "#8a5a14"},
    "night": {"bg": "#1c1c1e", "fg": "#d9d9dc", "link": "#6aa8ff"},
}
FONTS = {
    "serif": "'Noto Serif', 'DejaVu Serif', Georgia, serif",
    "sans": "Inter, 'Noto Sans', 'DejaVu Sans', sans-serif",
}
COVER_W, COVER_H = 132, 198

PAGER_JS = r"""
(function () {
  if (window.fm) return;
  const post = m => window.webkit.messageHandlers.fm.postMessage(JSON.stringify(m));
  const root = () => document.scrollingElement || document.documentElement;
  let page = 0, count = 1, placed = false;
  function pages() {
    // Count to the end of the text itself, so no blank page is left at the end.
    const range = document.createRange();
    range.selectNodeContents(document.body || document.documentElement);
    const right = range.getBoundingClientRect().right + root().scrollLeft;
    const most = Math.max(1, Math.round(root().scrollWidth / window.innerWidth));
    return Math.max(1, Math.min(most, Math.ceil((right - 2) / window.innerWidth)));
  }
  function show(n) {
    n = Math.max(0, Math.min(pages() - 1, n));
    page = n;
    count = pages();
    root().scrollLeft = n * window.innerWidth;
    post({page: n, pages: pages()});
  }
  window.fm = {
    setup(o) {
      let s = document.getElementById('fm-style');
      if (!s) {
        s = document.createElement('style');
        s.id = 'fm-style';
        (document.head || document.documentElement).appendChild(s);
      }
      const m = o.margin, t = o.top;
      s.textContent = `
        html { height: 100vh !important; overflow: hidden !important; margin: 0 !important; padding: 0 !important;
               background: ${o.bg} !important; font-size: ${o.size}% !important; }
        body { height: calc(100vh - ${2 * t}px) !important; margin: ${t}px ${m}px !important; padding: 0 !important;
               column-width: calc(100vw - ${2 * m}px) !important; column-gap: ${2 * m}px !important;
               column-fill: auto !important; color: ${o.fg} !important; background: transparent !important;
               font-family: ${o.font} !important; line-height: 1.6 !important; overflow-wrap: break-word; }
        body * { color: inherit !important; background-color: transparent !important; max-width: 100%; }
        img, svg, video { max-height: calc(100vh - ${2 * t + 12}px) !important; max-width: 100% !important;
                          height: auto; object-fit: contain; }
        a { color: ${o.link} !important; }
        p { text-align: justify; hyphens: auto; }
        pre { white-space: pre-wrap; }`;
    },
    go(target) {
      requestAnimationFrame(() => requestAnimationFrame(() => {
        let n = 0;
        if (target === 'end') n = pages() - 1;
        else if (typeof target === 'number') n = Math.round(target * (pages() - 1));
        else if (typeof target === 'string' && target) {
          const el = document.getElementById(target) || document.getElementsByName(target)[0];
          if (el) n = Math.floor((el.getBoundingClientRect().left + root().scrollLeft) / window.innerWidth);
        }
        placed = true;
        show(n);
      }));
    },
    next() { if (page >= pages() - 1) post({edge: 1}); else show(page + 1); },
    prev() { if (page <= 0) post({edge: -1}); else show(page - 1); },
    relayout() {
      if (!placed) return;
      // Keep to the same place in the chapter; the last page stays the last page.
      const atEnd = count > 1 && page >= count - 1;
      const f = count > 1 ? page / (count - 1) : 0;
      requestAnimationFrame(() => show(atEnd ? pages() - 1 : Math.round(f * (pages() - 1))));
    },
  };
  document.addEventListener('click', e => {
    if (e.target.closest && e.target.closest('a[href]')) return;
    post({click: e.clientX / window.innerWidth});
  });
  let wheel = 0;
  document.addEventListener('wheel', e => {
    e.preventDefault();
    const now = Date.now();
    if (now - wheel < 350) return;
    const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    if (Math.abs(d) < 4) return;
    wheel = now;
    d > 0 ? fm.next() : fm.prev();
  }, {passive: false});
  window.addEventListener('resize', () => fm.relayout());
  window.addEventListener('load', () => fm.relayout());
  post({ready: 1});
})();
"""


def data_path():
    folder = os.path.join(GLib.get_user_data_dir(), "freemac")
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, "books.json")


def books_folder():
    folder = os.path.join(GLib.get_home_dir(), "Books")
    os.makedirs(folder, exist_ok=True)
    return folder


def cache_folder():
    folder = os.path.join(GLib.get_user_cache_dir(), "freemac", "books")
    os.makedirs(folder, exist_ok=True)
    return folder


def load_data():
    try:
        with open(data_path(), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_data(data):
    try:
        tmp = data_path() + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, data_path())
    except OSError:
        pass


# -- reading an EPUB --

class Book:
    """The parts of an EPUB that Books needs: its title, author, cover,
    reading order (spine) and contents list."""

    def __init__(self, path):
        self.path = path
        self.zip = zipfile.ZipFile(path)
        self.names = set(self.zip.namelist())
        container = ET.fromstring(self.zip.read("META-INF/container.xml"))
        rootfile = container.find(".//c:rootfile", NS)
        opf_path = rootfile.get("full-path")
        base = posixpath.dirname(opf_path)
        opf = ET.fromstring(self.zip.read(opf_path))

        def text(tag):
            found = opf.find(f".//dc:{tag}", NS)
            return " ".join((found.text or "").split()) if found is not None else ""

        stem = os.path.splitext(os.path.basename(path))[0]
        self.title = text("title") or stem
        self.author = text("creator")
        self.manifest = {}
        for item in opf.findall("opf:manifest/opf:item", NS):
            href = self.join(base, item.get("href", ""))
            self.manifest[item.get("id")] = (href, item.get("media-type", ""), item.get("properties", "") or "")
        spine = opf.find("opf:spine", NS)
        self.spine = []
        for ref in spine.findall("opf:itemref", NS) if spine is not None else []:
            entry = self.manifest.get(ref.get("idref"))
            if entry and entry[0] in self.names:
                self.spine.append(entry[0])
        if not self.spine:
            raise ValueError("nothing to read")
        self.sizes = [max(1, self.zip.getinfo(p).file_size) for p in self.spine]
        self.cover = self._find_cover(opf)
        self.toc = []
        try:
            nav = next((h for h, _m, props in self.manifest.values() if "nav" in props.split()), None)
            if nav and nav in self.names:
                self._read_nav(nav)
            elif spine is not None and spine.get("toc") in self.manifest:
                self._read_ncx(self.manifest[spine.get("toc")][0])
        except (ET.ParseError, KeyError):
            self.toc = []
        if not self.toc:
            self.toc = [(f"Part {i + 1}", p, "", 0) for i, p in enumerate(self.spine)]

    @staticmethod
    def join(base, href):
        href = unquote(href.split("#", 1)[0])
        return posixpath.normpath(posixpath.join(base, href)) if href else base

    def _find_cover(self, opf):
        for href, media, props in self.manifest.values():
            if "cover-image" in props.split() and href in self.names:
                return href
        for meta in opf.findall("opf:metadata/opf:meta", NS):
            if meta.get("name") == "cover" and meta.get("content") in self.manifest:
                href = self.manifest[meta.get("content")][0]
                if href in self.names:
                    return href
        for key, (href, media, _p) in self.manifest.items():
            if media.startswith("image/") and "cover" in (key + href).lower() and href in self.names:
                return href
        return None

    def _split(self, base, href):
        path, _sep, fragment = href.partition("#")
        return self.join(base, path) if path else None, unquote(fragment)

    def _read_nav(self, nav):
        doc = ET.fromstring(self.zip.read(nav))
        base = posixpath.dirname(nav)
        navs = doc.iter("{http://www.w3.org/1999/xhtml}nav")
        chosen = None
        for element in navs:
            if element.get(EPUB_TYPE) == "toc":
                chosen = element
                break
            chosen = chosen or element
        if chosen is None:
            return

        def walk(ol, depth):
            for li in ol.findall("x:li", NS):
                link = li.find("x:a", NS)
                if link is None:
                    link = li.find("x:span", NS)
                if link is not None:
                    label = " ".join("".join(link.itertext()).split())
                    href = link.get("href")
                    if href and label:
                        path, fragment = self._split(base, href)
                        if path in self.names:
                            self.toc.append((label, path, fragment, depth))
                inner = li.find("x:ol", NS)
                if inner is not None:
                    walk(inner, depth + 1)

        ol = chosen.find("x:ol", NS)
        if ol is not None:
            walk(ol, 0)

    def _read_ncx(self, ncx):
        doc = ET.fromstring(self.zip.read(ncx))
        base = posixpath.dirname(ncx)

        def walk(parent, depth):
            for point in parent.findall("ncx:navPoint", NS):
                label = " ".join((point.findtext("ncx:navLabel/ncx:text", "", NS) or "").split())
                content = point.find("ncx:content", NS)
                if content is not None and label:
                    path, fragment = self._split(base, content.get("src", ""))
                    if path in self.names:
                        self.toc.append((label, path, fragment, depth))
                walk(point, depth + 1)

        nav_map = doc.find("ncx:navMap", NS)
        if nav_map is not None:
            walk(nav_map, 0)

    def read(self, name):
        if name not in self.names:
            raise KeyError(name)
        return self.zip.read(name)

    def chapter_title(self, index):
        path = self.spine[index]
        title = None
        for label, toc_path, _f, _d in self.toc:
            if toc_path == path:
                return label
            if toc_path in self.spine and self.spine.index(toc_path) < index:
                title = label
        return title or ""

    def progress(self, index, fraction):
        total = sum(self.sizes)
        return (sum(self.sizes[:index]) + self.sizes[index] * fraction) / total


def book_key(path):
    try:
        stat = os.stat(path)
        return hashlib.sha1(f"{path}:{stat.st_mtime_ns}:{stat.st_size}".encode()).hexdigest()
    except OSError:
        return hashlib.sha1(path.encode()).hexdigest()


def plain_cover(title, author, width=COVER_W, height=COVER_H):
    """A cover for a book that has none: a colour of its own and its title."""
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    cr = cairo.Context(surface)
    hue = int(hashlib.md5(title.encode()).hexdigest()[:4], 16) / 65535
    import colorsys
    r, g, b = colorsys.hsv_to_rgb(hue, 0.45, 0.62)
    grad = cairo.LinearGradient(0, 0, 0, height)
    grad.add_color_stop_rgb(0, min(1, r + 0.12), min(1, g + 0.12), min(1, b + 0.12))
    grad.add_color_stop_rgb(1, r * 0.8, g * 0.8, b * 0.8)
    cr.set_source(grad)
    cr.paint()
    cr.set_source_rgba(0, 0, 0, 0.18)
    cr.rectangle(0, 0, 7, height)
    cr.fill()
    cr.set_source_rgba(1, 1, 1, 0.7)
    cr.set_line_width(1)
    cr.rectangle(16.5, 18.5, width - 28, height - 37)
    cr.stroke()
    for text, size, y, bold in ((title, 15, 34, True), (author, 11, height - 62, False)):
        if not text:
            continue
        layout = PangoCairo.create_layout(cr)
        font = Pango.FontDescription("Noto Serif Bold" if bold else "Noto Serif")
        font.set_absolute_size(size * Pango.SCALE)
        layout.set_font_description(font)
        layout.set_width((width - 44) * Pango.SCALE)
        layout.set_alignment(Pango.Alignment.CENTER)
        layout.set_wrap(Pango.WrapMode.WORD_CHAR)
        layout.set_height(-5 if bold else -2)
        layout.set_ellipsize(Pango.EllipsizeMode.END)
        layout.set_text(text, -1)
        cr.set_source_rgb(1, 1, 1)
        cr.move_to(22, y)
        PangoCairo.show_layout(cr, layout)
    return surface


def cover_pixbuf(book):
    """The book's own cover, scaled and cached, or None."""
    if not book.cover:
        return None
    cached = os.path.join(cache_folder(), book_key(book.path) + ".png")
    try:
        if os.path.exists(cached):
            return GdkPixbuf.Pixbuf.new_from_file(cached)
        loader = GdkPixbuf.PixbufLoader()
        loader.write(book.read(book.cover))
        loader.close()
        pixbuf = loader.get_pixbuf()
        scale = min(COVER_W / pixbuf.get_width(), COVER_H / pixbuf.get_height())
        pixbuf = pixbuf.scale_simple(max(1, int(pixbuf.get_width() * scale)),
                                     max(1, int(pixbuf.get_height() * scale)), GdkPixbuf.InterpType.BILINEAR)
        pixbuf.savev(cached, "png", [], [])
        return pixbuf
    except (GLib.Error, KeyError, OSError, zipfile.BadZipFile):
        return None


# -- the window --

CSS = b"""
.books-shelf flowbox, .books-shelf flowboxchild, .books-shelf scrolledwindow, .books-shelf viewport {
    background: transparent; }
.books-theme:checked { box-shadow: inset 0 0 0 2px #007aff; }
.books-title { font-weight: 600; font-size: 12px; }
.books-author { font-size: 11px; color: alpha(currentColor, 0.6); }
.books-cover { box-shadow: 0 3px 8px alpha(black, 0.28); }
.books-footer { font-size: 11px; color: alpha(currentColor, 0.6); padding: 6px 12px; }
.books-empty { font-size: 14px; color: alpha(currentColor, 0.6); }
"""


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Books")
        self.app = app
        self.set_default_size(1000, 740)
        self.data = load_data()
        self.prefs = self.data.setdefault("prefs", {"size": 110, "theme": "light", "font": "serif"})
        self.places = self.data.setdefault("places", {})
        self.book = None
        self.index = 0
        self.fraction = 0.0
        self.target = 0
        self.page = (0, 1)
        self.save_id = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Books")
        self.header = header
        self.set_titlebar(header)
        self.back = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        self.back.set_tooltip_text("Library (⌘L)")
        self.back.connect("clicked", lambda _b: self.show_library())
        header.pack_start(self.back)
        self.add_button = Gtk.Button(label="Add Books…")
        self.add_button.connect("clicked", lambda _b: self.add_books())
        header.pack_start(self.add_button)
        self.contents_button = Gtk.MenuButton()
        self.contents_button.add(Gtk.Image.new_from_icon_name("view-list-symbolic", Gtk.IconSize.BUTTON))
        self.contents_button.set_tooltip_text("Contents")
        header.pack_start(self.contents_button)
        self.text_button = Gtk.MenuButton(label="Aa")
        self.text_button.set_tooltip_text("Text size and page colour")
        header.pack_end(self.text_button)
        self._build_text_popover()
        self._build_contents_popover()

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=150)
        self.add(self.stack)
        self._build_shelf()
        self._build_reader()
        menus.add_actions(self, {
            "add": self.add_books, "library": self.show_library, "close": self.close,
            "bigger": lambda: self.set_size(self.prefs["size"] + 10),
            "smaller": lambda: self.set_size(self.prefs["size"] - 10),
            "light": lambda: self.set_theme("light"), "sepia": lambda: self.set_theme("sepia"),
            "night": lambda: self.set_theme("night"), "contents": self.show_contents,
            "next": lambda: self.turn(1), "previous": lambda: self.turn(-1),
        })
        self.connect("key-press-event", self._key)
        self.connect("delete-event", lambda *_a: self.save_now() and False)
        monitor = Gio.File.new_for_path(books_folder()).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        monitor.connect("changed", lambda *_a: self._refresh_soon())
        self._monitor = monitor
        self._refresh_id = 0
        self.show_all()
        self.refresh()
        self.show_library()

    # The shelf
    def _build_shelf(self):
        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True, column_spacing=18,
                                row_spacing=24, margin=28, valign=Gtk.Align.START, max_children_per_line=12)
        self.flow.connect("child-activated", lambda _f, child: self.open_book(child.path))
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.flow)
        self.empty = Gtk.Label(label="No books yet.\nClick Add Books, or put EPUB books in the Books folder "
                                     "in your home.", justify=Gtk.Justification.CENTER, wrap=True)
        self.empty.get_style_context().add_class("books-empty")
        shelf = Gtk.Overlay()
        shelf.add(scroll)
        shelf.add_overlay(self.empty)
        shelf.get_style_context().add_class("books-shelf")
        self.stack.add_named(shelf, "shelf")

    def _refresh_soon(self):
        if self._refresh_id:
            GLib.source_remove(self._refresh_id)
        self._refresh_id = GLib.timeout_add(600, self.refresh)

    def refresh(self):
        self._refresh_id = 0
        for child in self.flow.get_children():
            self.flow.remove(child)
        folder = books_folder()
        found = []
        for name in os.listdir(folder):
            path = os.path.join(folder, name)
            if name.lower().endswith(".epub") and os.path.isfile(path):
                try:
                    found.append(Book(path))
                except (OSError, KeyError, ValueError, AttributeError, ET.ParseError, zipfile.BadZipFile):
                    continue
        found.sort(key=lambda b: (-self.places.get(b.path, {}).get("opened", 0), b.title.lower()))
        for book in found:
            self.flow.add(self._shelf_item(book))
            book.zip.close()
        self.empty.set_visible(not found)
        self.flow.show_all()
        return False

    def _shelf_item(self, book):
        child = Gtk.FlowBoxChild()
        child.path = book.path
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, halign=Gtk.Align.CENTER)
        frame = Gtk.Box(halign=Gtk.Align.CENTER, valign=Gtk.Align.END, height_request=COVER_H)
        pixbuf = cover_pixbuf(book)
        image = Gtk.Image.new_from_pixbuf(pixbuf) if pixbuf else Gtk.Image.new_from_surface(
            plain_cover(book.title, book.author))
        image.set_valign(Gtk.Align.END)
        image.get_style_context().add_class("books-cover")
        frame.pack_start(image, True, False, 0)
        box.pack_start(frame, False, False, 0)
        title = Gtk.Label(label=book.title, max_width_chars=18, lines=2, wrap=True,
                          ellipsize=Pango.EllipsizeMode.END, justify=Gtk.Justification.CENTER)
        title.get_style_context().add_class("books-title")
        box.pack_start(title, False, False, 0)
        place = self.places.get(book.path)
        line = book.author or ""
        if place and "progress" in place:
            done = int(place["progress"] * 100)
            line = "Finished" if done >= 99 else f"{done}% read"
        author = Gtk.Label(label=line, max_width_chars=18, ellipsize=Pango.EllipsizeMode.END)
        author.get_style_context().add_class("books-author")
        box.pack_start(author, False, False, 0)
        events = Gtk.EventBox()
        events.add(box)
        events.connect("button-press-event", self._shelf_click, book.path)
        child.add(events)
        return child

    def _shelf_click(self, _w, event, path):
        if event.button == 3:
            menu = Gtk.Menu()
            item = Gtk.MenuItem(label="Move to Trash")
            item.connect("activate", lambda _i: self._trash(path))
            menu.append(item)
            menu.show_all()
            menu.attach_to_widget(self, None)
            menu.popup_at_pointer(event)
            return True
        if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
            self.open_book(path)
            return True
        return False

    def _trash(self, path):
        try:
            Gio.File.new_for_path(path).trash(None)
        except GLib.Error:
            pass
        self.places.pop(path, None)
        self.flush()
        self.refresh()

    def add_books(self):
        dialog = Gtk.FileChooserNative.new("Add Books", self, Gtk.FileChooserAction.OPEN, "Add", "Cancel")
        dialog.set_select_multiple(True)
        epub = Gtk.FileFilter()
        epub.set_name("EPUB books")
        epub.add_pattern("*.epub")
        epub.add_pattern("*.EPUB")
        epub.add_mime_type("application/epub+zip")
        dialog.add_filter(epub)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            folder = books_folder()
            for source in dialog.get_filenames():
                if os.path.dirname(os.path.abspath(source)) == folder:
                    continue
                stem, ext = os.path.splitext(os.path.basename(source))
                target, n = os.path.join(folder, stem + ext), 2
                while os.path.exists(target):
                    target, n = os.path.join(folder, f"{stem} {n}{ext}"), n + 1
                try:
                    shutil.copy2(source, target)
                except OSError:
                    continue
            self.refresh()
        dialog.destroy()

    # The reader
    def _build_reader(self):
        self.context = WebKit2.WebContext.new_ephemeral()
        self.context.register_uri_scheme("book", self._serve)
        self.context.set_cache_model(WebKit2.CacheModel.DOCUMENT_VIEWER)
        manager = WebKit2.UserContentManager()
        manager.register_script_message_handler("fm")
        manager.connect("script-message-received::fm", self._message)
        manager.add_script(WebKit2.UserScript.new(PAGER_JS, WebKit2.UserContentInjectedFrames.TOP_FRAME,
                                                  WebKit2.UserScriptInjectionTime.END, None, None))
        self.view = WebKit2.WebView(web_context=self.context, user_content_manager=manager)
        settings = self.view.get_settings()
        settings.set_enable_javascript(True)            # for Books' own pager only
        settings.set_enable_javascript_markup(False)    # the book's scripts never run
        settings.set_enable_developer_extras(False)
        settings.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.NEVER)
        settings.set_auto_load_images(True)
        self.view.connect("decide-policy", self._policy)
        self.view.connect("context-menu", lambda *_a: True)
        self.footer = Gtk.Label(xalign=0.5, ellipsize=Pango.EllipsizeMode.END)
        self.footer.get_style_context().add_class("books-footer")
        self.progress = Gtk.ProgressBar(margin_start=12, margin_end=12)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.pack_start(self.view, True, True, 0)
        box.pack_start(self.progress, False, False, 0)
        box.pack_start(self.footer, False, False, 0)
        self.reader_box = box
        self.stack.add_named(box, "reader")

    def _serve(self, request):
        name = unquote(urlparse(request.get_uri()).path).lstrip("/")
        try:
            data = self.book.read(name) if self.book else None
            if data is None:
                raise KeyError(name)
        except (KeyError, OSError, zipfile.BadZipFile):
            request.finish_error(GLib.Error.new_literal(Gio.io_error_quark(), "Not in this book",
                                                        Gio.IOErrorEnum.NOT_FOUND))
            return
        mime = MIME.get(os.path.splitext(name)[1].lower(), "application/octet-stream")
        stream = Gio.MemoryInputStream.new_from_bytes(GLib.Bytes.new(data))
        request.finish(stream, len(data), mime)

    def _policy(self, _view, decision, kind):
        if kind not in (WebKit2.PolicyDecisionType.NAVIGATION_ACTION, WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION):
            return False
        action = decision.get_navigation_action()
        uri = action.get_request().get_uri() or ""
        if uri.startswith("book:"):
            if action.get_navigation_type() == WebKit2.NavigationType.LINK_CLICKED:
                decision.ignore()
                parsed = urlparse(uri)
                path = unquote(parsed.path).lstrip("/")
                if path in self.book.spine:
                    self.open_chapter(self.book.spine.index(path), unquote(parsed.fragment) or 0)
                return True
            decision.use()
            return True
        decision.ignore()
        if uri.startswith(("http:", "https:")) and action.get_navigation_type() == WebKit2.NavigationType.LINK_CLICKED:
            Gtk.show_uri_on_window(self, uri, Gdk.CURRENT_TIME)
        return True

    def _message(self, _manager, result):
        value = result.get_js_value() if hasattr(result, "get_js_value") else result
        try:
            message = json.loads(value.to_string())
        except (ValueError, TypeError):
            return
        if "ready" in message:
            self._js(f"fm.setup({json.dumps(self._look())}); fm.go({json.dumps(self.target)});")
        elif "page" in message:
            page, pages = int(message["page"]), max(1, int(message["pages"]))
            self.page = (page, pages)
            self.fraction = page / (pages - 1) if pages > 1 else 0.0
            self.update_footer()
            self.remember()
        elif "edge" in message:
            step = int(message["edge"])
            nxt = self.index + step
            if 0 <= nxt < len(self.book.spine):
                self.open_chapter(nxt, 0 if step > 0 else "end")
        elif "click" in message:
            x = float(message["click"])
            if x > 0.6:
                self.turn(1)
            elif x < 0.4:
                self.turn(-1)

    def _js(self, code):
        if hasattr(self.view, "evaluate_javascript"):
            self.view.evaluate_javascript(code, -1, None, None, None, None, None)
        else:
            self.view.run_javascript(code, None, None, None)

    def _look(self):
        theme = THEMES[self.prefs.get("theme", "light")]
        width = self.view.get_allocated_width()
        margin = max(28, int((width - 760) / 2)) if width > 900 else 36
        return {"bg": theme["bg"], "fg": theme["fg"], "link": theme["link"], "size": self.prefs["size"],
                "font": FONTS[self.prefs.get("font", "serif")], "margin": margin, "top": 44}

    def apply_look(self):
        if not hasattr(self, "view"):
            return
        theme = THEMES[self.prefs.get("theme", "light")]
        colour = Gdk.RGBA()
        colour.parse(theme["bg"])
        self.view.set_background_color(colour)
        if self.book:
            self._js(f"if (window.fm) {{ fm.setup({json.dumps(self._look())}); fm.relayout(); }}")
        self.flush()

    def open_book(self, path):
        try:
            book = Book(path)
        except (OSError, KeyError, ValueError, AttributeError, ET.ParseError, zipfile.BadZipFile):
            dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK,
                                       text="This book can't be opened",
                                       secondary_text="It may not be an EPUB book, or it may be damaged.")
            dialog.run()
            dialog.destroy()
            return
        if self.book:
            self.book.zip.close()
        self.book = book
        place = self.places.get(path, {})
        index = place.get("index", 0) if isinstance(place.get("index"), int) else 0
        if not 0 <= index < len(book.spine):
            index = 0
        self.header.set_title(book.title)
        self.header.set_subtitle(book.author)
        self._fill_contents()
        self.stack.set_visible_child_name("reader")
        self._reader_buttons(True)
        self.places.setdefault(path, {})["opened"] = time.time()
        self.open_chapter(index, float(place.get("fraction", 0)))
        self.view.grab_focus()

    def open_chapter(self, index, target=0):
        self.index = index
        self.target = target
        self.page = (0, 1)
        self.apply_look()
        self.view.load_uri("book://book/" + quote(self.book.spine[index]))

    def turn(self, step):
        if self.book and self.stack.get_visible_child_name() == "reader":
            self._js("fm.next()" if step > 0 else "fm.prev()")

    def update_footer(self):
        if not self.book:
            return
        page, pages = self.page
        left = pages - page - 1
        done = self.book.progress(self.index, self.fraction)
        chapter = self.book.chapter_title(self.index)
        pages_text = "Last page in this chapter" if left == 0 else \
            f"{left} page{'s' if left != 1 else ''} left in this chapter"
        self.footer.set_text(" · ".join(p for p in (chapter, pages_text, f"{int(done * 100)}%") if p))
        self.progress.set_fraction(done)

    def remember(self):
        if not self.book:
            return
        place = self.places.setdefault(self.book.path, {})
        place.update(index=self.index, fraction=round(self.fraction, 4),
                     progress=round(self.book.progress(self.index, self.fraction), 4), opened=time.time())
        self.flush()

    def flush(self):
        if self.save_id:
            GLib.source_remove(self.save_id)
        self.save_id = GLib.timeout_add(800, self.save_now)

    def save_now(self):
        if self.save_id:
            GLib.source_remove(self.save_id)
        self.save_id = 0
        save_data(self.data)
        return False

    def show_library(self):
        self.save_now()
        self.stack.set_visible_child_name("shelf")
        self.header.set_title("Books")
        self.header.set_subtitle(None)
        self._reader_buttons(False)
        self.refresh()

    def _reader_buttons(self, reading):
        self.back.set_visible(reading)
        self.contents_button.set_visible(reading)
        self.text_button.set_visible(reading)
        self.add_button.set_visible(not reading)

    # Contents and text
    def _build_contents_popover(self):
        popover = Gtk.Popover()
        self.contents_list = Gtk.ListBox()
        self.contents_list.connect("row-activated", self._contents_picked)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, min_content_height=200,
                                    max_content_height=480, propagate_natural_height=True, width_request=320)
        scroll.add(self.contents_list)
        scroll.set_margin_top(6)
        scroll.set_margin_bottom(6)
        scroll.show_all()
        popover.add(scroll)
        self.contents_button.set_popover(popover)

    def _fill_contents(self):
        for row in self.contents_list.get_children():
            self.contents_list.remove(row)
        for label, path, fragment, depth in self.book.toc:
            row = Gtk.ListBoxRow()
            row.target = (path, fragment)
            text = Gtk.Label(label=label, xalign=0, ellipsize=Pango.EllipsizeMode.END,
                             margin_start=12 + 16 * min(depth, 4), margin_end=12, margin_top=6, margin_bottom=6)
            row.add(text)
            self.contents_list.add(row)
        self.contents_list.show_all()

    def _contents_picked(self, _list, row):
        self.contents_button.get_popover().popdown()
        path, fragment = row.target
        if path in self.book.spine:
            self.open_chapter(self.book.spine.index(path), fragment or 0)
        self.view.grab_focus()

    def show_contents(self):
        if self.book and self.stack.get_visible_child_name() == "reader":
            self.contents_button.set_active(True)

    def _build_text_popover(self):
        popover = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=12)
        sizes = Gtk.Box(spacing=0)
        sizes.get_style_context().add_class("linked")
        smaller = Gtk.Button(label="A")
        smaller.set_tooltip_text("Smaller text (⌘−)")
        smaller.connect("clicked", lambda _b: self.set_size(self.prefs["size"] - 10))
        bigger = Gtk.Button()
        big = Gtk.Label()
        big.set_markup("<span size='x-large'>A</span>")
        bigger.add(big)
        bigger.set_tooltip_text("Bigger text (⌘+)")
        bigger.connect("clicked", lambda _b: self.set_size(self.prefs["size"] + 10))
        sizes.pack_start(smaller, True, True, 0)
        sizes.pack_start(bigger, True, True, 0)
        box.pack_start(sizes, False, False, 0)
        themes = Gtk.Box(spacing=8, homogeneous=True)
        self.theme_buttons = {}
        group = None
        for key, label in (("light", "Light"), ("sepia", "Sepia"), ("night", "Night")):
            button = Gtk.RadioButton.new_with_label_from_widget(group, label)
            button.set_mode(False)
            group = group or button
            button.get_style_context().add_class("books-theme")
            provider = Gtk.CssProvider()
            theme = THEMES[key]
            provider.load_from_data(f"button {{ background: {theme['bg']}; color: {theme['fg']}; "
                                    f"min-width: 64px; min-height: 30px; }}".encode())
            button.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            button.connect("toggled", lambda b, k=key: b.get_active() and self.set_theme(k))
            themes.pack_start(button, True, True, 0)
            self.theme_buttons[key] = button
        box.pack_start(themes, False, False, 0)
        fonts = Gtk.Box(spacing=0, homogeneous=True)
        fonts.get_style_context().add_class("linked")
        group = None
        for key, label in (("serif", "Book"), ("sans", "Plain")):
            button = Gtk.RadioButton.new_with_label_from_widget(group, label)
            button.set_mode(False)
            group = group or button
            button.set_active(self.prefs.get("font", "serif") == key)
            button.connect("toggled", lambda b, k=key: b.get_active() and self.set_font(k))
            fonts.pack_start(button, True, True, 0)
        box.pack_start(fonts, False, False, 0)
        self.theme_buttons[self.prefs.get("theme", "light")].set_active(True)
        box.show_all()
        popover.add(box)
        self.text_button.set_popover(popover)

    def set_size(self, size):
        self.prefs["size"] = max(70, min(220, size))
        self.apply_look()

    def set_theme(self, key):
        self.prefs["theme"] = key
        if not self.theme_buttons[key].get_active():
            self.theme_buttons[key].set_active(True)
        self.apply_look()

    def set_font(self, key):
        self.prefs["font"] = key
        self.apply_look()

    def _key(self, _w, event):
        if self.stack.get_visible_child_name() != "reader":
            return False
        key = event.keyval
        if event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK):
            return False
        if key in (Gdk.KEY_Right, Gdk.KEY_Page_Down, Gdk.KEY_space, Gdk.KEY_Down):
            self.turn(-1 if key == Gdk.KEY_space and event.state & Gdk.ModifierType.SHIFT_MASK else 1)
            return True
        if key in (Gdk.KEY_Left, Gdk.KEY_Page_Up, Gdk.KEY_Up):
            self.turn(-1)
            return True
        if key == Gdk.KEY_Escape:
            self.show_library()
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("Add Books…", "win.add", "<Ctrl>o"), ("Show Library", "win.library", "<Ctrl>l")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_View", [[("Contents", "win.contents", "<Ctrl>t")],
                   [("Bigger Text", "win.bigger", "<Ctrl>plus"), ("Smaller Text", "win.smaller", "<Ctrl>minus")],
                   [("Light Pages", "win.light", None), ("Sepia Pages", "win.sepia", None),
                    ("Night Pages", "win.night", None)]]),
        ("_Go", [[("Next Page", "win.next", None), ("Previous Page", "win.previous", None)]]),
    ])


class Books(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.add", ["<Control>o"]), ("win.library", ["<Control>l"]),
                             ("win.close", ["<Control>w"]), ("win.contents", ["<Control>t"]),
                             ("win.bigger", ["<Control>plus", "<Control>equal"]),
                             ("win.smaller", ["<Control>minus"])):
            self.set_accels_for_action(action, keys)
        self.set_menubar(menubar())

    def _window(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()
        return self.window

    def do_activate(self):
        self._window()

    def do_open(self, files, _n, _hint):
        window = self._window()
        for file in files:
            path = file.get_path()
            if path:
                window.open_book(path)
                break


def main():
    GLib.set_prgname("freemac-books")
    return Books().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
