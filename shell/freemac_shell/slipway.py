# SPDX-License-Identifier: GPL-3.0-or-later
"""Slipway: install an app you downloaded.

Double-clicking a downloaded app package (.deb) opens Slipway, as opening an
installer package on a Mac opens Installer: it shows the app with its icon,
version, publisher and size, and where the file came from, and installs it
after an administrator's password, getting what else it needs from the
internet. Afterwards it offers to open the app and to move the package to
the Trash. slipway_store reads the package; PackageKit installs it.

Original freemac code.
"""
import os
import sys
import threading

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

try:
    gi.require_version("PackageKitGlib", "1.0")
    from gi.repository import PackageKitGlib as PK  # noqa: E402
except (ImportError, ValueError):
    PK = None

from . import alert, menus, style  # noqa: E402
from . import slipway_store as store  # noqa: E402

APP_ID = "org.freemac.Slipway"
STEPS = (("intro", "Introduction"), ("install", "Installation"), ("summary", "Summary"))
STATUS_WORDS = {"dep-resolve": "Checking what it needs…", "download": "Downloading what it needs…",
                "install": "Installing…", "update": "Installing…", "setup": "Getting ready…",
                "wait": "Getting ready…", "commit": "Finishing…",
                "cleanup": "Finishing…", "finished": "Finishing…", "loading-cache": "Getting ready…",
                "query": "Checking what it needs…", "sig-check": "Checking the package…"}
CSS = b"""
.slipway-steps { padding: 26px 0 0 22px; background: alpha(currentColor, 0.04);
                 border-right: 1px solid alpha(currentColor, 0.1); }
.slipway-step { color: alpha(currentColor, 0.5); font-size: 13px; }
.slipway-step.current { color: @theme_fg_color; font-weight: 700; }
.slipway-dot { min-width: 8px; min-height: 8px; border-radius: 4px; background: alpha(currentColor, 0.25); }
.slipway-dot.current { background: @theme_selected_bg_color; }
.slipway-page { padding: 24px 28px 12px 28px; }
.slipway-name { font-size: 21px; font-weight: 800; }
.slipway-facts { color: alpha(currentColor, 0.6); font-size: 12px; }
.slipway-lead { font-size: 14px; font-weight: 600; }
.slipway-body { font-size: 13px; }
.slipway-notice { padding: 10px 12px; border-radius: 8px; background: alpha(currentColor, 0.05);
                  border: 1px solid alpha(currentColor, 0.1); }
.slipway-warning { color: #b3261e; font-weight: 600; }
.slipway-buttons { padding: 10px 16px 14px 16px; }
.slipway-big { font-size: 17px; font-weight: 700; }
.slipway-done { color: #2fa84f; }
"""


def label(text, css=None, wrap=True, chars=58):
    widget = Gtk.Label(label=text, xalign=0, wrap=wrap, max_width_chars=chars)
    widget.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
    if css:
        widget.get_style_context().add_class(css)
    return widget


def friendly_error(message):
    lowered = (message or "").lower()
    if "not authorized" in lowered or "authentication" in lowered or "cancelled" in lowered \
            or "dismissed" in lowered:
        return "Nothing was installed: the administrator's password wasn't given."
    if "lock" in lowered or "another" in lowered:
        return "Another program is installing software. Try again when it's done."
    if "depend" in lowered or "unmet" in lowered or "broken" in lowered:
        return ("It needs other software that couldn't be found. Check the internet connection and try again; "
                "if it still fails, the app may be made for a different version of Linux.")
    if "network" in lowered or "download" in lowered or "resolve" in lowered or "fetch" in lowered:
        return "Couldn't download what it needs. Check the internet connection and try again."
    return (message or "Something went wrong.").split("\n")[0][:300]


class Window(Gtk.ApplicationWindow):
    def __init__(self, app, path):
        super().__init__(application=app, title="Slipway")
        self.path = path
        self.info = None
        self.installing = False
        self.installed_ok = False
        self.set_default_size(640, 450)
        self.header = Gtk.HeaderBar(show_close_button=True, title="Slipway")
        self.set_titlebar(self.header)
        menus.add_actions(self, {"close": self.close})

        outer = Gtk.Box()
        self.add(outer)
        steps = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        steps.set_size_request(170, -1)
        steps.get_style_context().add_class("slipway-steps")
        self.step_rows = {}
        for key, words in STEPS:
            line = Gtk.Box(spacing=10)
            dot = Gtk.Box(valign=Gtk.Align.CENTER)
            dot.get_style_context().add_class("slipway-dot")
            text = Gtk.Label(label=words, xalign=0)
            text.get_style_context().add_class("slipway-step")
            line.pack_start(dot, False, False, 0)
            line.pack_start(text, False, False, 0)
            steps.pack_start(line, False, False, 0)
            self.step_rows[key] = (dot, text)
        outer.pack_start(steps, False, False, 0)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.pack_start(right, True, True, 0)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, vexpand=True)
        right.pack_start(self.stack, True, True, 0)
        self.buttons = Gtk.Box(spacing=8)
        self.buttons.get_style_context().add_class("slipway-buttons")
        right.pack_end(self.buttons, False, False, 0)

        self.stack.add_named(self.loading_page(), "loading")
        self.connect("delete-event", self._closing)
        self.show_all()
        self.step("intro")
        self.show_buttons([("Cancel", self.close, False)])
        threading.Thread(target=self._read, daemon=True).start()

    # ---- frame ------------------------------------------------------------------
    def step(self, current):
        for key, (dot, text) in self.step_rows.items():
            for widget in (dot, text):
                context = widget.get_style_context()
                (context.add_class if key == current else context.remove_class)("current")

    def show_buttons(self, buttons):
        """buttons: [(label, callback, primary)], laid out right to left as a
        Mac's Installer has them, the primary one last."""
        for child in self.buttons.get_children():
            child.destroy()
        for words, callback, primary in reversed(buttons):
            button = Gtk.Button(label=words)
            button.set_size_request(96, -1)
            if primary:
                button.get_style_context().add_class("suggested-action")
            button.connect("clicked", lambda _b, cb=callback: cb())
            self.buttons.pack_end(button, False, False, 0)
            if primary:
                button.set_can_default(True)
                self.set_default(button)
        self.buttons.show_all()

    def loading_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER)
        spinner = Gtk.Spinner(active=True)
        spinner.set_size_request(28, 28)
        box.pack_start(spinner, False, False, 0)
        words = Gtk.Label(label=f"Checking “{os.path.basename(self.path)}”…", ellipsize=Pango.EllipsizeMode.MIDDLE,
                          max_width_chars=40)
        box.pack_start(words, False, False, 0)
        return box

    def _read(self):
        try:
            info = store.read(self.path)
        except store.NotAPackage:
            info = None
        except Exception as e:  # a broken file mustn't leave the spinner turning
            print("slipway:", e, file=sys.stderr)
            info = None
        GLib.idle_add(self._loaded, info)

    def _closing(self, *_):
        if self.installing:
            alert.tell(self, f"{self.info['name']} is still installing",
                       "Wait for it to finish; stopping halfway could leave it broken.")
            return True
        if self.installed_ok and os.path.exists(self.path):
            self.offer_trash()
        return False

    # ---- 1. introduction -------------------------------------------------------------
    def _loaded(self, info):
        if info is None:
            page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            page.get_style_context().add_class("slipway-page")
            page.pack_start(label("This file can't be installed", "slipway-name"), False, False, 0)
            page.pack_start(label(f"“{os.path.basename(self.path)}” isn't an app package, or it's damaged. "
                                  "Try downloading it again.", "slipway-body"), False, False, 0)
            self.stack.add_named(page, "intro")
            page.show_all()
            self.stack.set_visible_child_name("intro")
            self.show_buttons([("Close", self.close, True)])
            return False
        self.info = info
        self.header.set_title(f"Install “{info['name']}”")
        self.set_title(f"Install “{info['name']}”")
        self.stack.add_named(self.intro_page(), "intro")
        self.stack.set_visible_child_name("intro")
        installed = info["installed"]
        if not info["runs_here"]:
            self.show_buttons([("Close", self.close, True)])
        elif installed and store.compare(installed, info["version"]) == 0:
            buttons = [("Reinstall", self.install, False)]
            if self.app_info():
                buttons.append((f"Open {info['name']}", self.open_app, True))
            else:
                buttons.append(("Close", self.close, True))
            self.show_buttons(buttons)
        else:
            self.show_buttons([("Cancel", self.close, False), ("Install", self.install, True)])
        return False

    def intro_page(self):
        info = self.info
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        page.get_style_context().add_class("slipway-page")
        top = Gtk.Box(spacing=14)
        pixbuf = store.icon_pixbuf(info, 64)
        image = Gtk.Image.new_from_pixbuf(pixbuf) if pixbuf else \
            Gtk.Image.new_from_icon_name("package-x-generic", Gtk.IconSize.DIALOG)
        image.set_pixel_size(64)
        top.pack_start(image, False, False, 0)
        names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3, valign=Gtk.Align.CENTER)
        names.pack_start(label(info["name"], "slipway-name"), False, False, 0)
        facts = [f"Version {info['version']}"] if info["version"] else []
        if info["size"]:
            facts.append(info["size"])
        if info["publisher"]:
            facts.append(f"by {info['publisher']}")
        names.pack_start(label(" · ".join(facts), "slipway-facts"), False, False, 0)
        top.pack_start(names, True, True, 0)
        page.pack_start(top, False, False, 0)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        if info["summary"]:
            text.pack_start(label(info["summary"], "slipway-lead"), False, False, 0)
        for paragraph in info["paragraphs"][:4]:
            text.pack_start(label(paragraph, "slipway-body"), False, False, 0)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        scroller.set_propagate_natural_height(True)
        scroller.set_max_content_height(170)
        scroller.add(text)
        page.pack_start(scroller, True, True, 0)

        notice = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        notice.get_style_context().add_class("slipway-notice")
        installed = info["installed"]
        if not info["runs_here"]:
            arch = store.ARCH_WORDS.get(info["arch"], info["arch"])
            notice.pack_start(label(f"{info['name']} can't be installed on this computer: it's made for {arch}. "
                                    "Look for a download for 64-bit PCs (amd64).", "slipway-warning"),
                              False, False, 0)
        else:
            where = "You downloaded this package"
            if info["site"]:
                where += f" from {info['site']}"
            when = store.when_words(info["when"])
            notice.pack_start(label(f"{where} {when}.".replace("  ", " ").replace(" .", "."), "slipway-body"),
                              False, False, 0)
            if installed:
                order = store.compare(installed, info["version"])
                words = {0: f"This version of {info['name']} is already installed.",
                         -1: f"This replaces the {info['name']} {installed} that's installed now.",
                         1: f"A newer {info['name']} ({installed}) is installed; this replaces it with an "
                            "older one."}[order]
                notice.pack_start(label(words, "slipway-body"), False, False, 0)
            notice.pack_start(label("Only install apps from people you trust. An app you install can see your "
                                    "files and change anything on this computer. Installing asks for an "
                                    "administrator's password.", "slipway-facts"), False, False, 0)
        page.pack_start(notice, False, False, 0)
        page.show_all()
        return page

    # ---- 2. installation -------------------------------------------------------------
    def install(self):
        if PK is None:
            alert.tell(self, "Apps can't be installed here", "This copy of freemac doesn't have PackageKit, "
                       "which installs apps.")
            return
        self.step("install")
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER)
        page.get_style_context().add_class("slipway-page")
        page.pack_start(label(f"Installing {self.info['name']}", "slipway-big"), False, False, 0)
        self.status = label("Waiting for an administrator's password…", "slipway-body")
        self.bar = Gtk.ProgressBar()
        page.pack_start(self.bar, False, False, 0)
        page.pack_start(self.status, False, False, 0)
        page.show_all()
        old = self.stack.get_child_by_name("install")
        if old:
            old.destroy()
        self.stack.add_named(page, "install")
        self.stack.set_visible_child_name("install")
        self.show_buttons([])
        self.installing = True
        self.pulse = GLib.timeout_add(120, self._pulse)
        threading.Thread(target=self._install, daemon=True).start()

    def _pulse(self):
        if self.bar.get_fraction() == 0:
            self.bar.pulse()
        return self.installing

    def _install(self):
        def progress(prog, kind, _data=None):
            if kind == PK.ProgressType.PERCENTAGE:
                pct = prog.get_percentage()
                if 0 <= pct <= 100:
                    GLib.idle_add(self.bar.set_fraction, max(pct / 100, 0.01))
            elif kind == PK.ProgressType.STATUS:
                words = STATUS_WORDS.get(PK.status_enum_to_string(prog.get_status()))
                if words:
                    GLib.idle_add(self.status.set_text, words)

        error = None
        try:
            client = PK.Client()
            flags = 0
            if self.info["installed"]:
                order = store.compare(self.info["installed"], self.info["version"])
                if order == 0:
                    flags |= 1 << int(PK.TransactionFlagEnum.ALLOW_REINSTALL)
                elif order > 0:
                    flags |= 1 << int(PK.TransactionFlagEnum.ALLOW_DOWNGRADE)
            results = client.install_files(flags, [self.path], None, progress, None)
            failure = results.get_error_code() if results else None
            if failure is not None:
                error = failure.get_details()
        except GLib.Error as e:
            error = e.message
        GLib.idle_add(self._installed, error)

    # ---- 3. summary ------------------------------------------------------------------
    def _installed(self, error):
        self.installing = False
        self.step("summary")
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER,
                       halign=Gtk.Align.CENTER)
        page.get_style_context().add_class("slipway-page")
        name = self.info["name"]
        if error is None:
            self.installed_ok = True
            mark = Gtk.Image.new_from_icon_name("emblem-ok-symbolic", Gtk.IconSize.DIALOG)
            mark.set_pixel_size(56)
            mark.get_style_context().add_class("slipway-done")
            page.pack_start(mark, False, False, 0)
            heading = Gtk.Label(label="The installation was successful.")
            heading.get_style_context().add_class("slipway-big")
            page.pack_start(heading, False, False, 0)
            where = "Marina and Seek" if self.app_info() else "the Terminal"
            more = Gtk.Label(label=f"{name} is installed. You'll find it in {where}.", wrap=True,
                             justify=Gtk.Justification.CENTER, max_width_chars=50)
            page.pack_start(more, False, False, 0)
            buttons = [("Close", self.close, not self.app_info())]
            if self.app_info():
                buttons.append((f"Open {name}", self.open_app, True))
            self.show_buttons(buttons)
        else:
            mark = Gtk.Image.new_from_icon_name("dialog-error-symbolic", Gtk.IconSize.DIALOG)
            mark.set_pixel_size(56)
            page.pack_start(mark, False, False, 0)
            heading = Gtk.Label(label="The installation failed.")
            heading.get_style_context().add_class("slipway-big")
            page.pack_start(heading, False, False, 0)
            page.pack_start(Gtk.Label(label=friendly_error(error), wrap=True, justify=Gtk.Justification.CENTER,
                                      max_width_chars=50), False, False, 0)
            self.show_buttons([("Close", self.close, False), ("Try Again", self.install, True)])
        page.show_all()
        self.stack.add_named(page, "summary-" + str(id(page)))
        self.stack.set_visible_child(page)
        return False

    def app_info(self):
        app = (self.info or {}).get("app")
        if not app:
            return None
        try:
            found = Gio.DesktopAppInfo.new(app["desktop"])
        except TypeError:
            return None
        return found

    def open_app(self):
        """Close first, asking about the package, so the app doesn't open
        over that question; then open the app."""
        found = self.app_info()
        # close() only queues the window's close, so ask here, before the
        # app opens, and then let the window go without asking again.
        if self.installed_ok and os.path.exists(self.path):
            self.offer_trash()
        self.installed_ok = False
        self.destroy()
        if found:
            try:
                found.launch([], None)
            except GLib.Error as e:
                alert.tell(None, f"{self.info['name']} didn't open", e.message)

    def offer_trash(self):
        answer = alert.ask(self, f"Move the “{os.path.basename(self.path)}” package to the Trash?",
                           f"{self.info['name']} is installed, so you don't need it any more. You can always "
                           "download it again.",
                           [("Keep", Gtk.ResponseType.CANCEL), ("Move to Trash", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK)
        if answer == Gtk.ResponseType.OK:
            try:
                Gio.File.new_for_path(self.path).trash(None)
            except GLib.Error:
                pass


def menubar():
    return menus.menubar([
        ("_File", [[("Close Window", "win.close", "<Ctrl>w")]]),
    ])


class Slipway(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": self.quit})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_menubar(menubar())

    def do_activate(self):
        windows = self.get_windows()
        if windows:
            windows[0].present()
            return
        dialog = Gtk.FileChooserNative(title="Choose an App Package", action=Gtk.FileChooserAction.OPEN,
                                       accept_label="Open")
        only = Gtk.FileFilter()
        only.set_name("App packages (.deb)")
        only.add_pattern("*.deb")
        only.add_mime_type("application/vnd.debian.binary-package")
        dialog.add_filter(only)
        downloads = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)
        if downloads:
            dialog.set_current_folder(downloads)
        self.hold()
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            Window(self, dialog.get_filename()).present()
        self.release()

    def do_open(self, files, _n, _hint):
        for file in files:
            path = file.get_path()
            if path:
                Window(self, path).present()


def main():
    GLib.set_prgname("freemac-slipway")
    return Slipway().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
