# SPDX-License-Identifier: GPL-3.0-or-later
"""Harbor: freemac's app centre.

Browse, search, install and remove open-source apps from the system's
package archive, and install system updates.

  freemac-harbor              open Harbor
  freemac-harbor --updates    open Harbor on the Updates page
  freemac-harbor --check      started at login: looks for updates once a day
                              and sends a notification when there are some

The catalogue is the distribution's AppStream data (names, summaries,
descriptions, categories and icons). Installing, removing and updating go
through PackageKit, which asks for an administrator password through
PolicyKit when it needs one.
"""
import html
import os
import re
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango  # noqa: E402

try:
    gi.require_version("AppStream", "1.0")
    from gi.repository import AppStream  # noqa: E402
except (ImportError, ValueError):
    AppStream = None
try:
    gi.require_version("PackageKitGlib", "1.0")
    from gi.repository import PackageKitGlib as PK  # noqa: E402
except (ImportError, ValueError):
    PK = None

from . import beacon, style  # noqa: E402

APP_ID = "org.freemac.Harbor"
ICON_SIZE = 48
CACHE = os.path.join(GLib.get_user_cache_dir(), "freemac", "harbor")
CATEGORIES = [
    ("Create", "applications-graphics-symbolic", ["Graphics", "AudioVideoEditing", "Photography"]),
    ("Work", "x-office-document-symbolic", ["Office", "ProjectManagement", "Finance"]),
    ("Play", "applications-games-symbolic", ["Game"]),
    ("Learn", "accessories-dictionary-symbolic", ["Education", "Science"]),
    ("Listen and Watch", "applications-multimedia-symbolic", ["AudioVideo", "Audio", "Video"]),
    ("Internet", "web-browser-symbolic", ["Network", "WebBrowser", "Email", "Chat"]),
    ("Develop", "applications-engineering-symbolic", ["Development", "IDE"]),
    ("Utilities", "applications-utilities-symbolic", ["Utility", "System"]),
]
# Apps shown first on the Explore page when the catalogue has them: widely
# used open-source programs, so a new user has somewhere to start.
PICKS = ["org.gimp.GIMP", "org.inkscape.Inkscape", "org.libreoffice.LibreOffice.writer",
         "libreoffice-writer.desktop", "org.videolan.VLC", "vlc.desktop", "org.mozilla.firefox",
         "firefox-esr.desktop", "org.mozilla.Thunderbird", "thunderbird.desktop",
         "org.kde.krita", "org.audacityteam.Audacity", "org.blender.Blender",
         "com.obsproject.Studio", "org.gnome.Rhythmbox3", "org.kde.kdenlive"]


# -- packages ----------------------------------------------------------------
def installed_packages():
    """Names of the installed packages, straight from dpkg (fast)."""
    try:
        out = subprocess.run(["dpkg-query", "-W", "-f", "${Package}\t${db:Status-Abbrev}\n"],
                             capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return set()
    return {name for name, _, status in (line.partition("\t") for line in out.splitlines())
            if status.startswith("ii")}


def plain_description(markup):
    """AppStream descriptions are a small XML subset; turn them into text."""
    if not markup:
        return ""
    text = re.sub(r"<li>\s*", "• ", markup)
    text = re.sub(r"</(p|li|ul|ol)>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


class Packages:
    """PackageKit work on a worker thread; callbacks come back on the main loop."""

    def __init__(self):
        self.client = PK.Client() if PK else None
        self.busy = False

    @property
    def available(self):
        return self.client is not None

    def _run(self, work, done, progress=None):
        def progress_cb(prog, kind, _data=None):
            if progress and kind == PK.ProgressType.PERCENTAGE:
                pct = prog.get_percentage()
                if 0 <= pct <= 100:
                    GLib.idle_add(progress, pct / 100)

        def thread():
            try:
                result, error = work(progress_cb), None
            except GLib.Error as err:
                result, error = None, friendly_error(err)
            self.busy = False
            GLib.idle_add(done, result, error)

        self.busy = True
        threading.Thread(target=thread, daemon=True).start()

    def resolve(self, names, cb):
        def work(progress_cb):
            filters = PK.filter_bitfield_from_string("arch;newest")
            res = self.client.resolve(filters, names, None, progress_cb, None)
            return [p.get_id() for p in res.get_package_array()]
        self._run(work, cb)

    def install(self, names, done, progress):
        def work(progress_cb):
            if lists_stale():
                # Old package lists point at versions the mirror no longer has.
                self.client.refresh_cache(False, None, progress_cb, None)
            filters = PK.filter_bitfield_from_string("arch;newest;~installed")
            ids = [p.get_id() for p in self.client.resolve(filters, names, None, progress_cb, None).get_package_array()]
            if not ids:
                raise GLib.Error("This app isn't in the archive any more. Try again after checking for updates.")
            flags = 1 << int(PK.TransactionFlagEnum.ONLY_TRUSTED)
            self.client.install_packages(flags, ids, None, progress_cb, None)
            return True
        self._run(work, done, progress)

    def remove(self, names, done, progress):
        def work(progress_cb):
            filters = PK.filter_bitfield_from_string("installed")
            ids = [p.get_id() for p in self.client.resolve(filters, names, None, progress_cb, None).get_package_array()]
            if ids:
                self.client.remove_packages(0, ids, True, True, None, progress_cb, None)
            return True
        self._run(work, done, progress)

    def updates(self, done, refresh=True):
        def work(progress_cb):
            if refresh:
                self.client.refresh_cache(False, None, progress_cb, None)
            res = self.client.get_updates(PK.filter_bitfield_from_string("none"), None, progress_cb, None)
            return [(p.get_id(), p.get_name(), p.get_version(), p.get_summary()) for p in res.get_package_array()]
        self._run(work, done)

    def update(self, ids, done, progress):
        def work(progress_cb):
            flags = 1 << int(PK.TransactionFlagEnum.ONLY_TRUSTED)
            self.client.update_packages(flags, ids, None, progress_cb, None)
            return True
        self._run(work, done, progress)


def lists_stale(max_age=2 * 86400):
    """True when apt's package lists are missing or more than two days old."""
    try:
        newest = max(entry.stat().st_mtime for entry in os.scandir("/var/lib/apt/lists")
                     if entry.name.endswith(("Packages", "Packages.lz4", "InRelease", "Release")))
    except (OSError, ValueError):
        return True
    return time.time() - newest > max_age


def friendly_error(err):
    message = err.message or str(err)
    lowered = message.lower()
    if "not authorized" in lowered or "authentication" in lowered or "cancelled" in lowered:
        return "Nothing was changed: the administrator password wasn't given."
    if "lock" in lowered:
        return "Another program is installing software. Try again when it's done."
    if "network" in lowered or "download" in lowered or "resolve" in lowered:
        return "Couldn't download. Check the internet connection and try again."
    return message.split("\n")[0][:300]


# -- catalogue ---------------------------------------------------------------
class Catalogue:
    def __init__(self):
        self.pool = None
        self.error = None
        if AppStream is None:
            self.error = "The app catalogue library (AppStream) isn't installed."
            return
        pool = AppStream.Pool.new()
        try:
            pool.load(None)
        except GLib.Error as err:
            self.error = err.message
            return
        if len(pool.get_components().as_array()) == 0:
            self.error = "empty"   # the package lists haven't been downloaded yet
            return
        self.pool = pool

    @staticmethod
    def apps(box):
        seen, out = set(), []
        for comp in box.as_array():
            if comp.get_kind() != AppStream.ComponentKind.DESKTOP_APP or not comp.get_pkgname():
                continue
            if comp.get_id() in seen:
                continue
            seen.add(comp.get_id())
            out.append(comp)
        return out

    def search(self, text):
        return self.apps(self.pool.search(text)) if self.pool and text.strip() else []

    def category(self, names):
        if not self.pool:
            return []
        found = self.apps(self.pool.get_components_by_categories(names))
        return sorted(found, key=lambda c: (c.get_name() or "").lower())

    def picks(self):
        if not self.pool:
            return []
        out, names = [], set()
        for cid in PICKS:
            for comp in self.apps(self.pool.get_components_by_id(cid)):
                if comp.get_name() not in names:
                    names.add(comp.get_name())
                    out.append(comp)
        return out

    def by_package(self, pkgnames):
        if not self.pool:
            return []
        out = []
        for comp in self.apps(self.pool.get_components()):
            if comp.get_pkgname() in pkgnames:
                out.append(comp)
        return sorted(out, key=lambda c: (c.get_name() or "").lower())


def app_icon(comp, size=ICON_SIZE, on_ready=None):
    """The best icon we can show without waiting: a cached file, then the
    icon theme. A remote icon is fetched in the background into Harbor's
    cache, and on_ready(pixbuf) is called when it arrives."""
    theme = Gtk.IconTheme.get_default()
    remote = None
    for icon in sorted(comp.get_icons(), key=lambda i: -(i.get_width() or 0)):
        kind = icon.get_kind()
        if kind in (AppStream.IconKind.CACHED, AppStream.IconKind.LOCAL):
            path = icon.get_filename()
            if path and os.path.exists(path):
                try:
                    return GdkPixbuf.Pixbuf.new_from_file_at_size(path, size, size)
                except GLib.Error:
                    pass
        elif kind == AppStream.IconKind.STOCK and theme.has_icon(icon.get_name()):
            try:
                return theme.load_icon(icon.get_name(), size, Gtk.IconLookupFlags.FORCE_SIZE)
            except GLib.Error:
                pass
        elif kind == AppStream.IconKind.REMOTE and remote is None:
            remote = icon.get_url()
    if remote and remote.startswith("https://") and on_ready:
        fetch_icon(remote, size, on_ready)
    return theme.load_icon("application-x-executable", size, Gtk.IconLookupFlags.FORCE_SIZE)


def fetch_icon(url, size, on_ready):
    os.makedirs(CACHE, exist_ok=True)
    name = re.sub(r"[^A-Za-z0-9._-]", "_", url.rsplit("/", 1)[-1])[-120:]
    path = os.path.join(CACHE, name)

    def deliver():
        try:
            on_ready(GdkPixbuf.Pixbuf.new_from_file_at_size(path, size, size))
        except GLib.Error:
            pass
        return False

    if os.path.exists(path):
        GLib.idle_add(deliver)
        return

    def loaded(source, result):
        try:
            ok, data, _etag = source.load_contents_finish(result)
        except GLib.Error:
            return
        if ok and data and len(data) < 2_000_000:
            with open(path + ".tmp", "wb") as f:
                f.write(data)
            os.replace(path + ".tmp", path)
            deliver()

    Gio.File.new_for_uri(url).load_contents_async(None, loaded)


# -- widgets -----------------------------------------------------------------
class AppTile(Gtk.FlowBoxChild):
    def __init__(self, comp, installed):
        super().__init__()
        self.comp = comp
        box = Gtk.Box(spacing=12, margin=10)
        self.image = Gtk.Image.new_from_pixbuf(app_icon(comp, on_ready=self._icon))
        box.pack_start(self.image, False, False, 0)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        name = Gtk.Label(label=comp.get_name() or comp.get_id(), xalign=0, ellipsize=Pango.EllipsizeMode.END)
        name.get_style_context().add_class("harbor-name")
        summary = Gtk.Label(label=comp.get_summary() or "", xalign=0, ellipsize=Pango.EllipsizeMode.END,
                            max_width_chars=34)
        summary.get_style_context().add_class("dim-label")
        texts.pack_start(name, False, False, 0)
        texts.pack_start(summary, False, False, 0)
        box.pack_start(texts, True, True, 0)
        if comp.get_pkgname() in installed:
            tick = Gtk.Image.new_from_icon_name("object-select-symbolic", Gtk.IconSize.BUTTON)
            tick.set_tooltip_text("Installed")
            box.pack_start(tick, False, False, 0)
        frame = Gtk.EventBox()
        frame.add(box)
        frame.get_style_context().add_class("harbor-tile")
        self.add(frame)
        self.set_size_request(300, -1)

    def _icon(self, pixbuf):
        self.image.set_from_pixbuf(pixbuf)


def tile_grid():
    grid = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True,
                       min_children_per_line=1, max_children_per_line=3,
                       row_spacing=8, column_spacing=8, valign=Gtk.Align.START)
    grid.set_activate_on_single_click(True)
    return grid


def scrolled(child):
    scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
    scroller.add(child)
    return scroller


def section(text):
    label = Gtk.Label(label=text, xalign=0)
    label.get_style_context().add_class("harbor-section")
    return label


class Details(Gtk.Box):
    """One app: icon, name, summary, the action button and the description."""

    def __init__(self, window, comp):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24)
        self.window, self.comp = window, comp
        top = Gtk.Box(spacing=18)
        self.image = Gtk.Image.new_from_pixbuf(app_icon(comp, 96, on_ready=self.image_ready))
        top.pack_start(self.image, False, False, 0)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER)
        name = Gtk.Label(label=comp.get_name(), xalign=0, wrap=True)
        name.get_style_context().add_class("harbor-title")
        texts.pack_start(name, False, False, 0)
        summary = Gtk.Label(label=comp.get_summary() or "", xalign=0, wrap=True)
        summary.get_style_context().add_class("dim-label")
        texts.pack_start(summary, False, False, 0)
        developer = comp.get_developer().get_name() if hasattr(comp, "get_developer") and comp.get_developer() else None
        if developer:
            dev = Gtk.Label(label=developer, xalign=0)
            dev.get_style_context().add_class("dim-label")
            texts.pack_start(dev, False, False, 0)
        top.pack_start(texts, True, True, 0)
        self.buttons = Gtk.Box(spacing=8, valign=Gtk.Align.CENTER)
        top.pack_start(self.buttons, False, False, 0)
        self.pack_start(top, False, False, 0)
        self.progress = Gtk.ProgressBar(no_show_all=True)
        self.pack_start(self.progress, False, False, 0)
        self.message = Gtk.Label(xalign=0, wrap=True, no_show_all=True)
        self.pack_start(self.message, False, False, 0)
        body = Gtk.Label(label=plain_description(comp.get_description()), xalign=0, yalign=0,
                         wrap=True, selectable=True, max_width_chars=90)
        self.pack_start(body, False, False, 0)
        facts = Gtk.Grid(column_spacing=18, row_spacing=4)
        rows = [("Package", comp.get_pkgname()), ("Licence", comp.get_project_license())]
        homepage = comp.get_url(AppStream.UrlKind.HOMEPAGE)
        for i, (label, value) in enumerate(r for r in rows if r[1]):
            key = Gtk.Label(label=label, xalign=1)
            key.get_style_context().add_class("dim-label")
            facts.attach(key, 0, i, 1, 1)
            facts.attach(Gtk.Label(label=value, xalign=0, selectable=True, wrap=True), 1, i, 1, 1)
        if homepage and homepage.startswith(("https://", "http://")):
            link = Gtk.LinkButton(uri=homepage, label="Website", halign=Gtk.Align.START)
            facts.attach(link, 0, len(rows), 2, 1)
        self.pack_start(facts, False, False, 0)
        self.refresh()

    def image_ready(self, pixbuf):
        self.image.set_from_pixbuf(pixbuf)

    def launchable(self):
        launch = self.comp.get_launchable(AppStream.LaunchableKind.DESKTOP_ID)
        entries = launch.get_entries() if launch else []
        for desktop_id in entries or [self.comp.get_id()]:
            if not desktop_id.endswith(".desktop"):
                desktop_id += ".desktop"
            try:
                info = Gio.DesktopAppInfo.new(desktop_id)
            except TypeError:
                info = None
            if info:
                return info
        return None

    def refresh(self):
        for child in self.buttons.get_children():
            self.buttons.remove(child)
        installed = self.comp.get_pkgname() in self.window.installed
        busy = self.window.packages.busy
        if installed:
            info = self.launchable()
            if info:
                open_button = Gtk.Button(label="Open")
                open_button.connect("clicked", lambda _b: info.launch([], None))
                self.buttons.pack_start(open_button, False, False, 0)
            remove = Gtk.Button(label="Remove", sensitive=not busy)
            remove.get_style_context().add_class("destructive-action")
            remove.connect("clicked", self.on_remove)
            self.buttons.pack_start(remove, False, False, 0)
        else:
            install = Gtk.Button(label="Install", sensitive=not busy and self.window.packages.available)
            install.get_style_context().add_class("suggested-action")
            install.connect("clicked", self.on_install)
            self.buttons.pack_start(install, False, False, 0)
        self.buttons.show_all()

    def busy(self, text):
        self.message.set_text(text)
        self.message.show()
        self.progress.set_fraction(0)
        self.progress.show()
        self.refresh()

    def finished(self, _result, error, done_text):
        self.progress.hide()
        self.window.reload_installed()
        if error:
            self.message.set_text(error)
        else:
            self.message.set_text(done_text)
        self.refresh()

    def on_install(self, _button):
        name = self.comp.get_name()
        self.window.packages.install([self.comp.get_pkgname()],
                                     lambda r, e: self.finished(r, e, f"{name} is installed."),
                                     self.progress.set_fraction)
        self.busy(f"Installing {name}…")

    def on_remove(self, _button):
        name = self.comp.get_name()
        dialog = Gtk.MessageDialog(transient_for=self.get_toplevel(), modal=True,
                                   message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.NONE,
                                   text=f"Remove {name}?")
        dialog.format_secondary_text("Your own files made with it are kept.")
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Remove", Gtk.ResponseType.OK)
        dialog.get_widget_for_response(Gtk.ResponseType.OK).get_style_context().add_class("destructive-action")
        answer = dialog.run()
        dialog.destroy()
        if answer != Gtk.ResponseType.OK:
            return
        self.window.packages.remove([self.comp.get_pkgname()],
                                    lambda r, e: self.finished(r, e, f"{name} was removed."),
                                    self.progress.set_fraction)
        self.busy(f"Removing {name}…")


class UpdatesPage(Gtk.Box):
    def __init__(self, window):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=24)
        self.window = window
        self.ids = []
        top = Gtk.Box(spacing=12)
        self.headline = Gtk.Label(label="Updates", xalign=0)
        self.headline.get_style_context().add_class("harbor-title")
        top.pack_start(self.headline, True, True, 0)
        self.check = Gtk.Button(label="Check Now")
        self.check.connect("clicked", lambda _b: self.load(refresh=True))
        top.pack_start(self.check, False, False, 0)
        self.install = Gtk.Button(label="Update All", sensitive=False, no_show_all=True)
        self.install.get_style_context().add_class("suggested-action")
        self.install.connect("clicked", self.on_install)
        top.pack_start(self.install, False, False, 0)
        self.pack_start(top, False, False, 0)
        self.status = Gtk.Label(xalign=0, wrap=True)
        self.status.get_style_context().add_class("dim-label")
        self.pack_start(self.status, False, False, 0)
        self.progress = Gtk.ProgressBar(no_show_all=True)
        self.pack_start(self.progress, False, False, 0)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.list.get_style_context().add_class("frame")
        self.list.set_no_show_all(True)
        self.pack_start(scrolled(self.list), True, True, 0)
        self.loaded = False

    def load(self, refresh=False):
        if not self.window.packages.available:
            self.status.set_text("Updates need PackageKit, which isn't installed.")
            return
        if self.window.packages.busy:
            return
        self.loaded = True
        self.check.set_sensitive(False)
        self.install.set_sensitive(False)
        self.status.set_text("Checking for updates…")
        self.window.packages.updates(self.show_updates, refresh=refresh)

    def show_updates(self, result, error):
        self.check.set_sensitive(True)
        if not error and self.window.catalogue.pool is None:
            self.window.reload_catalogue()   # a refresh also brings the catalogue
        for row in self.list.get_children():
            self.list.remove(row)
        if error:
            self.status.set_text(error)
            return
        result = result or []
        self.ids = [r[0] for r in result]
        if not result:
            self.headline.set_text("Up to date")
            self.status.set_text("Everything on this computer has its latest updates.")
            self.list.hide()
            self.install.hide()
            return
        self.headline.set_text(f"{len(result)} update{'s' if len(result) != 1 else ''}")
        self.status.set_text("Security fixes and improvements from the archive. Some may need a restart.")
        for _pid, name, version, summary in sorted(result, key=lambda r: r[1]):
            row = Gtk.Box(spacing=12, margin=8)
            row.pack_start(Gtk.Label(label=name, xalign=0), False, False, 0)
            sub = Gtk.Label(label=summary or "", xalign=0, ellipsize=Pango.EllipsizeMode.END)
            sub.get_style_context().add_class("dim-label")
            row.pack_start(sub, True, True, 0)
            row.pack_start(Gtk.Label(label=version), False, False, 0)
            row.show_all()   # the list has no_show_all set, so show_all on it does nothing
            self.list.add(row)
        self.list.show()
        self.install.show()
        self.install.set_sensitive(True)

    def on_install(self, _button):
        self.install.set_sensitive(False)
        self.check.set_sensitive(False)
        self.status.set_text("Installing updates…")
        self.progress.set_fraction(0)
        self.progress.show()
        self.window.packages.update(self.ids, self.installed_updates, self.progress.set_fraction)

    def installed_updates(self, _result, error):
        self.progress.hide()
        self.check.set_sensitive(True)
        if error:
            self.status.set_text(error)
            self.install.set_sensitive(True)
            return
        self.window.reload_installed()
        needs_restart = os.path.exists("/run/reboot-required") or os.path.exists("/var/run/reboot-required")
        self.load(refresh=False)
        if needs_restart:
            self.status.set_text("Updates installed. Restart the computer to finish.")


class HarborWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Harbor")
        self.set_default_size(960, 600)
        self.catalogue = app.catalogue
        self.packages = app.packages
        self.installed = installed_packages()
        self.history = []
        self.result_apps = []

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        self.back = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        self.back.set_tooltip_text("Back")
        self.back.connect("clicked", lambda _b: self.go_back())
        self.back.set_no_show_all(True)
        header.pack_start(self.back)
        self.tabs = Gtk.StackSwitcher()
        header.set_custom_title(self.tabs)
        self.search = Gtk.SearchEntry(placeholder_text="Search apps", width_chars=24)
        self.search.connect("search-changed", self.on_search)
        self.search.connect("activate", self.on_search_enter)
        header.pack_end(self.search)

        # The three tabs live in their own stack so the switcher shows only
        # them; search results and an app's page sit beside it.
        self.tabs_stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.tabs.set_stack(self.tabs_stack)
        self.explore = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24)
        self.tabs_stack.add_titled(scrolled(self.explore), "explore", "Explore")
        self.installed_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24)
        self.tabs_stack.add_titled(scrolled(self.installed_box), "installed", "Installed")
        self.updates = UpdatesPage(self)
        self.tabs_stack.add_titled(self.updates, "updates", "Updates")
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.stack.add_named(self.tabs_stack, "tabs")
        self.results = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24)
        self.stack.add_named(scrolled(self.results), "results")
        self.detail_holder = Gtk.Box()
        self.stack.add_named(self.detail_holder, "details")
        self.stack.connect("notify::visible-child-name", self.on_page)
        self.tabs_stack.connect("notify::visible-child-name", self.on_tab)
        self.add(self.stack)
        self.connect("key-press-event", self.on_key)

        css = Gtk.CssProvider()
        css.load_from_data(b"""
            .harbor-tile { border-radius: 12px; background-color: alpha(currentColor, 0.05); }
            .harbor-tile:hover { background-color: alpha(currentColor, 0.10); }
            .harbor-name { font-weight: bold; }
            .harbor-title { font-size: 22px; font-weight: bold; }
            .harbor-section { font-size: 16px; font-weight: bold; margin-top: 6px; }
            .harbor-category { padding: 14px; border-radius: 12px; }
        """)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.build_explore()
        self.build_installed()
        self.show_all()

    def on_key(self, _window, event):
        """Ctrl+F and typing anywhere go to the search field; Escape and
        Alt+Left go back."""
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        alt = event.state & Gdk.ModifierType.MOD1_MASK
        if ctrl and event.keyval in (Gdk.KEY_f, Gdk.KEY_F):
            self.search.grab_focus()
            return True
        if (alt and event.keyval == Gdk.KEY_Left) or (
                event.keyval == Gdk.KEY_Escape and not self.search.get_text()):
            if self.back.get_visible():
                self.go_back()
                return True
        focus = self.get_focus()
        if not ctrl and not alt and not isinstance(focus, Gtk.Entry) and Gdk.keyval_to_unicode(event.keyval) > 32:
            return self.search.handle_event(event)
        return False

    # pages ------------------------------------------------------------------
    def fill(self, box, apps, empty_text, limit=None):
        grid = tile_grid()
        grid.connect("child-activated", lambda _g, tile: self.open_app(tile.comp))
        for comp in apps[:limit]:
            grid.add(AppTile(comp, self.installed))
        if not apps:
            label = Gtk.Label(label=empty_text, xalign=0, wrap=True)
            label.get_style_context().add_class("dim-label")
            box.pack_start(label, False, False, 0)
        box.pack_start(grid, False, False, 0)
        return grid

    def clear(self, box):
        for child in box.get_children():
            box.remove(child)

    def build_explore(self):
        self.clear(self.explore)
        if self.catalogue.error or not self.catalogue.pool:
            self.explore.pack_start(section("The app catalogue isn't on this computer yet"), False, False, 0)
            note = Gtk.Label(label="Harbor downloads the list of apps from the internet the first time. "
                                   "It takes a minute or two.", wrap=True, xalign=0)
            note.get_style_context().add_class("dim-label")
            self.explore.pack_start(note, False, False, 0)
            self.fetch_status = Gtk.Label(xalign=0, wrap=True)
            fetch = Gtk.Button(label="Download the Catalogue", halign=Gtk.Align.START,
                               sensitive=self.packages.available)
            fetch.get_style_context().add_class("suggested-action")
            fetch.connect("clicked", self.on_fetch)
            self.explore.pack_start(fetch, False, False, 0)
            self.explore.pack_start(self.fetch_status, False, False, 0)
            if self.catalogue.error not in (None, "empty"):
                self.fetch_status.set_text(self.catalogue.error)
            self.explore.show_all()
            return
        self.explore.pack_start(section("Categories"), False, False, 0)
        cats = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True,
                           min_children_per_line=2, max_children_per_line=4, row_spacing=8, column_spacing=8)
        for name, icon, cat_names in CATEGORIES:
            button = Gtk.Button()
            inner = Gtk.Box(spacing=10)
            inner.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            inner.pack_start(Gtk.Label(label=name, xalign=0), True, True, 0)
            button.add(inner)
            button.get_style_context().add_class("harbor-category")
            button.connect("clicked", lambda _b, n=name, c=cat_names: self.show_category(n, c))
            cats.add(button)
        self.explore.pack_start(cats, False, False, 0)
        picks = self.catalogue.picks()
        if picks:
            self.explore.pack_start(section("Popular open-source apps"), False, False, 0)
            self.fill(self.explore, picks, "")
        self.explore.show_all()

    def on_fetch(self, button):
        button.set_sensitive(False)
        self.fetch_status.set_text("Downloading the catalogue…")
        self.packages.updates(self.fetched, refresh=True)

    def fetched(self, _result, error):
        if error:
            self.build_explore()
            self.fetch_status.set_text(error)
            return
        self.reload_catalogue()

    def reload_catalogue(self):
        self.catalogue = self.get_application().catalogue = Catalogue()
        self.build_explore()
        self.build_installed()

    def build_installed(self):
        self.clear(self.installed_box)
        apps = self.catalogue.by_package(self.installed)
        self.installed_box.pack_start(section(f"Installed apps ({len(apps)})"), False, False, 0)
        self.fill(self.installed_box, apps, "No apps from the catalogue are installed.")
        self.installed_box.show_all()

    def show_list(self, title, apps, empty):
        self.clear(self.results)
        self.results.pack_start(section(title), False, False, 0)
        self.fill(self.results, apps, empty, limit=300)
        self.result_apps = apps
        self.results.show_all()
        self.navigate("results")

    def on_search_enter(self, entry):
        """Enter in the search field opens the best match."""
        if entry.get_text().strip() != getattr(self, "searched", None):
            self.on_search(entry)
        if self.page_name() == "results" and self.result_apps:
            self.open_app(self.result_apps[0])

    def show_category(self, name, cats):
        self.show_list(name, self.catalogue.category(cats), "Nothing here yet.")

    def on_search(self, entry):
        text = self.searched = entry.get_text().strip()
        if not text:
            if self.page_name() == "results":
                self.go_back()
            return
        self.show_list(f"Results for “{text}”", self.catalogue.search(text), "No apps match that search.")

    def open_app(self, comp):
        self.clear(self.detail_holder)
        self.details = Details(self, comp)
        self.detail_holder.pack_start(scrolled(self.details), True, True, 0)
        self.detail_holder.show_all()
        self.navigate("details")

    def page_name(self):
        name = self.stack.get_visible_child_name()
        return self.tabs_stack.get_visible_child_name() if name == "tabs" else name

    def show_page(self, name):
        if name in ("explore", "installed", "updates"):
            self.tabs_stack.set_visible_child_name(name)
            self.stack.set_visible_child_name("tabs")
        else:
            self.stack.set_visible_child_name(name)

    def navigate(self, name):
        current = self.page_name()
        if current != name or name == "details":
            self.history.append(current)
        self.show_page(name)

    def go_back(self):
        self.show_page(self.history.pop() if self.history else "explore")

    def on_page(self, stack, _param):
        name = stack.get_visible_child_name()
        self.back.set_visible(name in ("results", "details"))
        if name == "tabs":
            self.history = []
            self.on_tab(self.tabs_stack, None)

    def on_tab(self, tabs, _param):
        if self.stack.get_visible_child_name() != "tabs":
            # Picking a tab while on a search or an app goes to that tab.
            self.stack.set_visible_child_name("tabs")
            return
        if tabs.get_visible_child_name() == "updates" and not self.updates.loaded:
            self.updates.load(refresh=False)

    def reload_installed(self):
        self.installed = installed_packages()
        self.build_installed()


class Harbor(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.catalogue = None
        self.packages = None
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        action = Gio.SimpleAction.new("quit", None)
        action.connect("activate", lambda *_: self.quit())
        self.add_action(action)
        self.set_accels_for_action("app.quit", ["<Control>q"])

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        if self.catalogue is None:
            self.catalogue = Catalogue()
            self.packages = Packages()
        if self.window is None:
            self.window = HarborWindow(self)
        if "--updates" in args:
            self.window.show_page("updates")
        self.window.present()
        return 0


# -- background update check -------------------------------------------------
STAMP = os.path.join(CACHE, "last-check")
DAY = 24 * 3600


def check_loop():
    """Look for updates once a day and say so with a notification."""
    if PK is None:
        return 1
    time.sleep(600)   # let the session settle after login
    client = PK.Client()
    while True:
        try:
            last = os.path.getmtime(STAMP)
        except OSError:
            last = 0
        if time.time() - last >= DAY:
            try:
                client.refresh_cache(False, None, lambda *a: None, None)
                updates = client.get_updates(PK.filter_bitfield_from_string("none"), None,
                                             lambda *a: None, None).get_package_array()
                os.makedirs(CACHE, exist_ok=True)
                with open(STAMP, "w"):
                    pass
                if updates:
                    count = len(updates)
                    beacon.send(f"{count} update{'s' if count != 1 else ''} available",
                                "Open Harbor to install them.", icon="freemac-harbor", app="Harbor")
            except GLib.Error:
                pass   # offline or busy: try again in an hour
        time.sleep(3600)


def main():
    if "--check" in sys.argv[1:]:
        sys.exit(check_loop())
    if "-h" in sys.argv[1:] or "--help" in sys.argv[1:]:
        print(__doc__.strip())
        return
    sys.exit(Harbor().run(sys.argv))


if __name__ == "__main__":
    main()
