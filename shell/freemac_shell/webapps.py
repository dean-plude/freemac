# SPDX-License-Identifier: GPL-3.0-or-later
"""Add to Dock for websites, as a Mac's Safari makes a web app of a site.

In Web, File > Add to Dock… makes the page in front an app of its own: it
gets a name, an icon (the site's own, from its web app manifest or its
page, else a tile with its first letter), a place in the Dock, Drawer's
Applications folder and Marina, and opens in a window of its own with no
tabs or address bar. Facebook added this way is one click away, as on a
Mac.

The app is a GNOME Web web app: Web opens it with --application-mode and a
profile folder of its own, so it keeps its own sign-ins. Web finds its
name through the desktop portal's launcher folder
(~/.local/share/xdg-desktop-portal/applications), and the menus find it
through ~/.local/share/applications, where a link to the same file goes,
as the portal itself does when it installs a launcher.

    freemac-webapp --title "Page title"   add Web's page with that title
    freemac-webapp URL [--name NAME]      add a page by its address
    freemac-webapp --remove DESKTOP_ID    delete a web app made here

Original freemac code.
"""
import hashlib
import html.parser
import json
import os
import shutil
import sys
import threading
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

PREFIX = "org.gnome.Epiphany.WebApp_"
TILE = 256          # the icon's size, drawn once and scaled by the Dock
TIMEOUT = 8         # seconds to wait for a site while looking for its icon
AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"


def data_home():
    return os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")


def app_id_for(url):
    """A web app's id: the same address always gives the same app."""
    return hashlib.sha1(url.encode()).hexdigest()


def desktop_id_for(app_id):
    return f"{PREFIX}{app_id}.desktop"


def paths(app_id):
    """Where a web app's pieces go: its profile folder, its launcher (the
    portal's folder), the link the menus read and its icon."""
    home = data_home()
    profile = os.path.join(home, PREFIX + app_id)
    return {
        "profile": profile,
        "launcher": os.path.join(home, "xdg-desktop-portal", "applications", desktop_id_for(app_id)),
        "link": os.path.join(home, "applications", desktop_id_for(app_id)),
        "icon": os.path.join(profile, "app-icon.png"),
    }


def clean_url(text):
    """An address as typed ("facebook.com") made whole, or None."""
    text = (text or "").strip()
    if not text or any(ch.isspace() for ch in text):
        return None
    if "://" not in text:
        text = "https://" + text
    parts = urllib.parse.urlsplit(text)
    if parts.scheme not in ("http", "https") or not parts.netloc:
        return None
    return urllib.parse.urlunsplit(parts._replace(path=parts.path or "/"))


def site_name(url):
    """"facebook.com" for https://www.facebook.com/home: a name to start from."""
    host = urllib.parse.urlsplit(url).hostname or url
    return host[4:] if host.startswith("www.") else host


def short_title(title, url):
    """The name a page's title suggests: "Facebook – log in or sign up" gives
    "Facebook". A title of only the address gives the site's name."""
    title = " ".join((title or "").split())
    for mark in (" – ", " — ", " - ", " | ", " · ", ": "):
        if mark in title:
            head = title.split(mark)[0].strip()
            if len(head) >= 2:
                title = head
                break
    if not title or title.startswith(("http://", "https://")) or title == url:
        return site_name(url)
    return title[:40]


def desktop_text(name, url, app_id):
    """The launcher, as GNOME Web writes one for its own web apps."""
    p = paths(app_id)
    flat = " ".join(name.split()) or site_name(url)
    exe = f'epiphany --application-mode "--profile={p["profile"]}" {quote_exec(url)}'
    return ("[Desktop Entry]\n"
            f"Name={flat}\n"
            f"Exec={exe}\n"
            "StartupNotify=true\n"
            "Terminal=false\n"
            "Type=Application\n"
            "Categories=GNOME;GTK;Network;\n"
            f"Icon={p['icon']}\n"
            f"StartupWMClass={PREFIX}{app_id}\n"
            "NoDisplay=false\n"
            f"X-Freemac-WebApp-URL={url}\n")


def quote_exec(url):
    """An address for a desktop file's Exec line, quoted. The characters the
    specification would have escaped twice are written as %-codes instead,
    which a browser reads the same, and every % is doubled."""
    for ch, code in (("\\", "%5C"), ('"', "%22"), ("`", "%60"), ("$", "%24")):
        url = url.replace(ch, code)
    return '"' + url.replace("%", "%%") + '"'


def installed():
    """Web apps on this account: [(desktop id, name, address)], by name."""
    found = []
    folder = os.path.join(data_home(), "applications")
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        names = []
    for name in names:
        if not (name.startswith(PREFIX) and name.endswith(".desktop")):
            continue
        fields = read_desktop(os.path.join(folder, name))
        found.append((name, fields.get("Name", name), fields.get("X-Freemac-WebApp-URL", "")))
    return sorted(found, key=lambda f: f[1].lower())


def read_desktop(path):
    fields = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if "=" in line and not line.startswith(("#", "[")):
                    key, value = line.rstrip("\n").split("=", 1)
                    fields.setdefault(key.strip(), value)
    except OSError:
        pass
    return fields


def as_desktop_id(name):
    """"org.gnome.Epiphany.WebApp_…" with or without ".desktop" on the end."""
    return name if name.endswith(".desktop") else name + ".desktop"


def is_web_app(desktop_id):
    return bool(desktop_id) and desktop_id.startswith(PREFIX) and desktop_id.endswith(".desktop")


def write_app(name, url, icon_png):
    """Make the web app; icon_png is the icon's PNG bytes. Returns its desktop
    id. Adding a site that is already an app gives it the new name and icon."""
    app_id = app_id_for(url)
    p = paths(app_id)
    for folder in (p["profile"], os.path.dirname(p["launcher"]), os.path.dirname(p["link"])):
        os.makedirs(folder, exist_ok=True)
    # Web takes a profile folder with this mark as a web app's.
    open(os.path.join(p["profile"], ".app"), "a").close()
    with open(p["icon"] + ".tmp", "wb") as f:
        f.write(icon_png)
    os.replace(p["icon"] + ".tmp", p["icon"])
    text = desktop_text(name, url, app_id)
    for target in (p["launcher"], os.path.join(p["profile"], desktop_id_for(app_id))):
        with open(target + ".tmp", "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(target + ".tmp", target)
    if os.path.lexists(p["link"]):
        os.remove(p["link"])
    os.symlink(p["launcher"], p["link"])
    return desktop_id_for(app_id)


def remove_app(desktop_id):
    """Delete a web app: its launcher, its icon and its sign-ins."""
    if not is_web_app(desktop_id):
        return False
    app_id = desktop_id[len(PREFIX):-len(".desktop")]
    if not app_id or "/" in app_id or app_id.startswith("."):
        return False
    p = paths(app_id)
    quit_app(p["profile"])
    for path in (p["link"], p["launcher"]):
        if os.path.lexists(path):
            os.remove(path)
    shutil.rmtree(p["profile"], ignore_errors=True)
    set_pinned(desktop_id, False)
    return True


def quit_app(profile):
    """Close a web app that is open and wait (a few seconds at most) for it
    to go, so it writes nothing into its folder once the folder is gone."""
    import signal
    import time
    wanted = f"--profile={profile}".encode()
    running = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = f.read().split(b"\0")
            if wanted in args and os.stat(f"/proc/{pid}").st_uid == os.getuid():
                os.kill(int(pid), signal.SIGTERM)
                running.append(pid)
        except OSError:
            continue
    for _ in range(30):
        if not any(os.path.exists(f"/proc/{pid}") for pid in running):
            break
        time.sleep(0.1)


# The Dock's pinned apps, as Pier keeps them (pier.json). Pier watches the
# file, so a change shows at once.
PIER = os.path.expanduser("~/.config/freemac/pier.json")


def set_pinned(desktop_id, keep):
    try:
        with open(PIER) as f:
            saved = json.load(f)
    except (OSError, ValueError):
        saved = {}
    if "pinned" not in saved:
        from .pier import DEFAULT_PINNED
        saved["pinned"] = list(DEFAULT_PINNED)
    pinned = saved["pinned"]
    if keep and desktop_id not in pinned:
        pinned.append(desktop_id)
    elif not keep and desktop_id in pinned:
        pinned.remove(desktop_id)
    else:
        return
    os.makedirs(os.path.dirname(PIER), exist_ok=True)
    with open(PIER + ".tmp", "w") as f:
        json.dump(saved, f, indent=2)
    os.replace(PIER + ".tmp", PIER)


# Which page is in front in Web: Web keeps its windows' tabs in
# session_state.xml, with each window's tab in front.

def session_path():
    return os.path.join(data_home(), "epiphany", "session_state.xml")


def page_from_session(xml_text, title=""):
    """(address, title) of the page in front whose title is `title`, else of
    the first window's page in front; None when there is none."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return None
    fronts, every = [], []
    for window in root.iter("window"):
        tabs = [(e.get("url") or "", e.get("title") or "") for e in window.iter("embed")]
        if not tabs:
            continue
        try:
            active = int(window.get("active-tab", "0"))
        except ValueError:
            active = 0
        if 0 <= active < len(tabs):
            fronts.append(tabs[active])
        every += tabs
    title = (title or "").strip()
    for group in (fronts, every):
        for url, page_title in group:
            if title and page_title.strip() == title and url.startswith(("http://", "https://")):
                return url, page_title
    for url, page_title in fronts:
        if url.startswith(("http://", "https://")):
            return url, page_title
    return None


def front_page(title=""):
    try:
        with open(session_path(), encoding="utf-8") as f:
            return page_from_session(f.read(), title)
    except OSError:
        return None


# Finding a site's icon.

class _Links(html.parser.HTMLParser):
    """The <link> icons and manifest a page names."""

    def __init__(self):
        super().__init__()
        self.icons, self.manifest = [], None

    def handle_starttag(self, tag, attrs):
        if tag != "link":
            return
        a = {k.lower(): (v or "") for k, v in attrs}
        rel, href = a.get("rel", "").lower().split(), a.get("href", "")
        if not href:
            return
        if "manifest" in rel and self.manifest is None:
            self.manifest = href
        elif "apple-touch-icon" in rel or "apple-touch-icon-precomposed" in rel:
            self.icons.append((href, biggest(a.get("sizes")) or 180, 2))
        elif "icon" in rel:
            self.icons.append((href, biggest(a.get("sizes")) or (64 if href.endswith(".svg") else 16), 1))


def biggest(sizes):
    """The largest side in a sizes attribute ("16x16 32x32" gives 32); "any" is big."""
    best = 0
    for size in (sizes or "").lower().split():
        if size == "any":
            return 512
        try:
            best = max(best, int(size.split("x")[0]))
        except ValueError:
            pass
    return best


def icon_choices(page_url, page_html, manifest=None, manifest_url=None):
    """Icon addresses to try, best first: big manifest icons, Apple touch
    icons, the page's own icons by size, then /favicon.ico."""
    links = _Links()
    try:
        links.feed(page_html)
    except Exception:  # a page that isn't HTML
        pass
    ranked = []
    for href, size, kind in links.icons:
        ranked.append((size, kind, urllib.parse.urljoin(page_url, href)))
    for icon in (manifest or {}).get("icons", []) if isinstance(manifest, dict) else []:
        if not isinstance(icon, dict) or not icon.get("src"):
            continue
        purpose = str(icon.get("purpose", "any")).split()
        # A maskable icon fills its square to the edges, as a tile should.
        kind = 3 if "maskable" in purpose else 2
        ranked.append((biggest(icon.get("sizes")) or 192, kind, urllib.parse.urljoin(manifest_url or page_url, icon["src"])))
    ranked.sort(key=lambda r: (min(r[0], 512), r[1]), reverse=True)
    out = []
    for _size, _kind, url in ranked:
        if url not in out:
            out.append(url)
    fallback = urllib.parse.urljoin(page_url, "/favicon.ico")
    if fallback not in out:
        out.append(fallback)
    return out


def manifest_name(manifest):
    if not isinstance(manifest, dict):
        return ""
    for key in ("short_name", "name"):
        value = manifest.get(key)
        if isinstance(value, str) and value.strip():
            return " ".join(value.split())[:40]
    return ""


def fetch(url, limit=2_000_000):
    request = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept": "*/*"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read(limit), response.geturl()


def look_up(url):
    """What the site says about itself: (name, [icon image bytes, best
    first]). Either may be empty: a site that can't be reached gives ("", [])."""
    try:
        body, final = fetch(url)
    except Exception:
        return "", []
    page = body.decode("utf-8", "replace")
    links = _Links()
    try:
        links.feed(page)
    except Exception:
        pass
    manifest, manifest_url = None, None
    if links.manifest:
        manifest_url = urllib.parse.urljoin(final, links.manifest)
        try:
            manifest = json.loads(fetch(manifest_url, 500_000)[0].decode("utf-8", "replace"))
        except Exception:
            manifest = None
    images = []
    for choice in icon_choices(final, page, manifest, manifest_url)[:6]:
        try:
            data = fetch(choice, 1_000_000)[0]
        except Exception:
            continue
        if data:
            images.append(data)
        if len(images) >= 2:
            break
    return manifest_name(manifest), images


# Drawing the icon: a rounded square, as a Mac's app icons are.

def _pixbuf(data):
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
    loader = GdkPixbuf.PixbufLoader()
    try:
        loader.write(data)
        loader.close()
    except Exception:
        return None
    return loader.get_pixbuf()


def tile_colour(url):
    """A colour for a site with no icon of its own, the same every time."""
    palette = [(0.20, 0.47, 0.96), (0.93, 0.36, 0.30), (0.20, 0.70, 0.45), (0.95, 0.60, 0.15),
               (0.55, 0.36, 0.85), (0.10, 0.65, 0.75), (0.88, 0.32, 0.55), (0.40, 0.45, 0.55)]
    digest = hashlib.sha1(site_name(url).encode()).digest()
    return palette[digest[0] % len(palette)]


def _rounded(cr, x, y, size, radius):
    import math
    cr.new_sub_path()
    cr.arc(x + size - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + size - radius, y + size - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + size - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


def _corners_clear(pixbuf):
    """Whether a picture's corners are see-through, so it has a shape of its
    own (a round logo) rather than filling its square."""
    if not pixbuf.get_has_alpha():
        return False
    w, h, stride, n = pixbuf.get_width(), pixbuf.get_height(), pixbuf.get_rowstride(), pixbuf.get_n_channels()
    data = pixbuf.get_pixels()
    spots = [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)]
    return all(data[y * stride + x * n + 3] < 40 for x, y in spots if 0 <= x < w and 0 <= y < h)


def draw_icon(url, name, images=()):
    """The web app's icon as PNG bytes: the site's own picture on a rounded
    tile, else its first letter on a coloured tile."""
    import cairo
    import gi
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk
    best = None
    for data in images:
        pixbuf = _pixbuf(data)
        if pixbuf and (best is None or pixbuf.get_width() > best.get_width()):
            best = pixbuf
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, TILE, TILE)
    cr = cairo.Context(surface)
    margin = TILE * 0.09                      # room for the tile's shadow
    side = TILE - 2 * margin
    radius = side * 0.225
    # A soft shadow under the tile.
    for spread, alpha in ((6, 0.05), (4, 0.07), (2, 0.09)):
        _rounded(cr, margin - spread / 2, margin - spread / 2 + 4, side + spread, radius + spread / 2)
        cr.set_source_rgba(0, 0, 0, alpha)
        cr.fill()
    _rounded(cr, margin, margin, side, radius)
    cr.save()
    cr.clip()
    if best is not None and best.get_width() >= 96 and not _corners_clear(best):
        # A big square picture fills the tile to its edges.
        scaled = best.scale_simple(int(side), int(side), 2)  # GdkPixbuf.InterpType.BILINEAR
        Gdk.cairo_set_source_pixbuf(cr, scaled, margin, margin)
        cr.paint()
    elif best is not None:
        cr.set_source_rgb(1, 1, 1)
        cr.paint()
        inner = side * (0.62 if best.get_width() >= 48 else 0.5)
        scaled = best.scale_simple(int(inner), int(inner * best.get_height() / max(1, best.get_width())), 2)
        Gdk.cairo_set_source_pixbuf(cr, scaled, margin + (side - scaled.get_width()) / 2,
                                    margin + (side - scaled.get_height()) / 2)
        cr.paint()
    else:
        r, g, b = tile_colour(url)
        gradient = cairo.LinearGradient(0, margin, 0, margin + side)
        gradient.add_color_stop_rgb(0, min(1, r + 0.12), min(1, g + 0.12), min(1, b + 0.12))
        gradient.add_color_stop_rgb(1, r * 0.85, g * 0.85, b * 0.85)
        cr.set_source(gradient)
        cr.paint()
        letter = (name.strip() or site_name(url))[:1].upper()
        cr.select_font_face("Inter", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(side * 0.56)
        ext = cr.text_extents(letter)
        cr.move_to(margin + (side - ext.width) / 2 - ext.x_bearing,
                   margin + (side - ext.height) / 2 - ext.y_bearing)
        cr.set_source_rgb(1, 1, 1)
        cr.show_text(letter)
    cr.restore()
    # A hairline edge, so a white tile shows on a light Dock.
    _rounded(cr, margin + 0.5, margin + 0.5, side - 1, radius)
    cr.set_source_rgba(0, 0, 0, 0.12)
    cr.set_line_width(1)
    cr.stroke()
    import io
    out = io.BytesIO()
    surface.write_to_png(out)
    return out.getvalue()


# The Add to Dock window.

def run_dialog(url, title):
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf, GLib, Gtk
    # The window is Web's, as Safari's Add to Dock sheet is Safari's: the
    # menu bar names Web, and the Dock shows no app of its own for it.
    GLib.set_prgname("org.gnome.Epiphany")

    state = {"images": [], "url": url, "name_touched": False}
    window = Gtk.Window(title="Add to Dock")
    window.set_resizable(False)
    window.set_position(Gtk.WindowPosition.CENTER)
    window.get_style_context().add_class("freemac-sheet")
    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=22)
    window.add(outer)
    row = Gtk.Box(spacing=18)
    outer.pack_start(row, False, False, 0)
    picture = Gtk.Image()
    picture.set_valign(Gtk.Align.START)
    row.pack_start(picture, False, False, 0)
    fields = Gtk.Grid(row_spacing=10, column_spacing=10)
    row.pack_start(fields, True, True, 0)
    heading = Gtk.Label(xalign=0)
    heading.set_markup("<b>Add to Dock</b>")
    fields.attach(heading, 0, 0, 2, 1)
    blurb = Gtk.Label(label="The website opens in a window of its own, from the Dock and Applications.",
                      xalign=0, wrap=True, max_width_chars=40)
    blurb.get_style_context().add_class("dim-label")
    fields.attach(blurb, 0, 1, 2, 1)
    fields.attach(Gtk.Label(label="Name:", xalign=1), 0, 2, 1, 1)
    name = Gtk.Entry(width_chars=28, activates_default=True)
    name.set_text(short_title(title, url) if url else "")
    fields.attach(name, 1, 2, 1, 1)
    fields.attach(Gtk.Label(label="Address:", xalign=1), 0, 3, 1, 1)
    address = Gtk.Entry(width_chars=28, activates_default=True, placeholder_text="facebook.com")
    address.set_text(url or "")
    fields.attach(address, 1, 3, 1, 1)
    note = Gtk.Label(xalign=0, wrap=True, max_width_chars=40)
    note.get_style_context().add_class("dim-label")
    fields.attach(note, 1, 4, 1, 1)

    buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END)
    outer.pack_start(buttons, False, False, 0)
    cancel = Gtk.Button(label="Cancel")
    add = Gtk.Button(label="Add")
    add.get_style_context().add_class("suggested-action")
    add.set_can_default(True)
    buttons.pack_start(cancel, False, False, 0)
    buttons.pack_start(add, False, False, 0)
    window.set_default(add)

    def show_icon():
        data = draw_icon(state["url"] or "https://example.org/", name.get_text(), state["images"])
        loader = GdkPixbuf.PixbufLoader()
        loader.write(data)
        loader.close()
        picture.set_from_pixbuf(loader.get_pixbuf().scale_simple(96, 96, GdkPixbuf.InterpType.BILINEAR))

    def looked_up(for_url, site, images):
        if for_url != state["url"]:
            return False
        state["images"] = images
        if site and not state["name_touched"]:
            name.set_text(site)
            state["name_touched"] = False
        note.set_text("")
        show_icon()
        return False

    def look(for_url):
        found = look_up(for_url)
        GLib.idle_add(looked_up, for_url, *found)

    def start_looking():
        state["images"] = []
        show_icon()
        if state["url"]:
            note.set_text("Looking for the website's icon…")
            threading.Thread(target=look, args=(state["url"],), daemon=True).start()
        return False

    def address_done(*_):
        typed = clean_url(address.get_text())
        add.set_sensitive(typed is not None)
        if typed and typed != state["url"]:
            state["url"] = typed
            if not state["name_touched"] or not name.get_text().strip():
                name.set_text(site_name(typed))
                state["name_touched"] = False
            start_looking()

    def name_changed(*_):
        state["name_touched"] = True
        if not state["images"]:
            show_icon()

    address.connect("focus-out-event", lambda *_: address_done() or False)
    address.connect("changed", lambda *_: add.set_sensitive(clean_url(address.get_text()) is not None))
    name.connect("changed", name_changed)

    def do_add(*_):
        typed = clean_url(address.get_text())
        if not typed:
            return
        if typed != state["url"]:
            address_done()
        label = " ".join(name.get_text().split()) or site_name(typed)
        try:
            desktop_id = write_app(label, typed, draw_icon(typed, label, state["images"]))
            set_pinned(desktop_id, True)
        except OSError as e:
            note.set_text(f"The website couldn't be added: {e.strerror or e}")
            return
        window.destroy()

    add.connect("clicked", do_add)
    cancel.connect("clicked", lambda *_: window.destroy())
    window.connect("key-press-event", lambda _w, ev: ev.keyval == 0xff1b and window.destroy())
    window.connect("destroy", Gtk.main_quit)
    add.set_sensitive(clean_url(address.get_text()) is not None)
    window.show_all()
    if url:
        name.grab_focus()
    else:
        address.grab_focus()
    state["name_touched"] = False
    GLib.idle_add(start_looking)
    Gtk.main()
    return 0


def ask_to_delete(desktop_id):
    """Dock > Options > Delete Web App…: ask first, since its sign-ins go too."""
    if not is_web_app(desktop_id):
        return 1
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gio, GLib, Gtk
    # The question comes from the Dock, where Delete Web App… was chosen.
    GLib.set_prgname("freemac-pier")
    from . import alert
    fields = read_desktop(os.path.join(data_home(), "applications", desktop_id))
    label = fields.get("Name") or "this web app"
    answer = alert.ask(None, f"Delete “{label}”?",
                       "It leaves the Dock and Applications, and its sign-ins are forgotten. "
                       "The website itself isn't changed.",
                       [("Cancel", Gtk.ResponseType.CANCEL), ("Delete", Gtk.ResponseType.OK)],
                       default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK,
                       icon=Gio.FileIcon.new(Gio.File.new_for_path(fields["Icon"]))
                       if os.path.isfile(fields.get("Icon", "")) else None)
    if answer != Gtk.ResponseType.OK:
        return 1
    return 0 if remove_app(desktop_id) else 1


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv[:1] == ["--remove"] and len(argv) == 2:
        return 0 if remove_app(as_desktop_id(argv[1])) else 1
    if argv[:1] == ["--delete"] and len(argv) == 2:
        return ask_to_delete(as_desktop_id(argv[1]))
    if argv[:1] == ["--list"]:
        for desktop_id, label, url in installed():
            print(f"{label}\t{url}\t{desktop_id}")
        return 0
    title, url, label = "", None, None
    while argv:
        arg = argv.pop(0)
        if arg == "--title" and argv:
            title = argv.pop(0)
        elif arg == "--name" and argv:
            label = argv.pop(0)
        elif not arg.startswith("--"):
            url = clean_url(arg)
    if url is None:
        found = front_page(title)
        if found:
            url, title = found
    return run_dialog(url, label or title)


if __name__ == "__main__":
    sys.exit(main())
