# SPDX-License-Identifier: GPL-3.0-or-later
"""freemac Recovery: what to do when the computer won't start properly.

Recovery is a small, separate way of starting the computer. It doesn't start
the desktop or need anyone to log in: it opens one full-screen window with a
short list of things to do, the way a Mac's recovery does.

- Restore from Lifeboat: bring a whole home folder back from a backup drive.
- Reinstall freemac: put a fresh copy on a disk (from a freemac USB stick).
- Reset a Password: for someone who has forgotten theirs.
- Check a Disk: look for problems on a volume that isn't in use, and fix them.
- Drives: Hull, to look at, erase and name drives.
- Get Help Online: a web browser, once the Wi-Fi menu has joined a network.
- Terminal: for people who know their way around one.

To get here, hold Ctrl while the computer starts, choose freemac Recovery in
the start-up menu (hold Esc to see it), or click Restart in Recovery in
Dials > Power. A freemac USB stick has the same entry.

It runs as root in the cage kiosk compositor (freemac-recovery.service);
`freemac-recovery --window` opens it in a window for testing. What it does to
the computer is in recovery_store. Original freemac code.
"""
import os
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

from . import alert, backup_store, style  # noqa: E402
from . import recovery_store as store  # noqa: E402

MARK = "/usr/share/freemac/freemac-mark.svg"
HELP_URL = "https://github.com/dean-plude/freemac#readme"
CSS = b"""
.recovery-backdrop {
    background-image: linear-gradient(160deg, #2b3a55 0%, #17202f 55%, #0f141d 100%);
}
.recovery-bar { padding: 6px 14px; background-color: rgba(255, 255, 255, 0.10); }
.recovery-bar, .recovery-bar label { color: #ffffff; }
.recovery-bar button { color: #ffffff; background: none; border: none; box-shadow: none; padding: 2px 8px; }
.recovery-bar button:hover { background-color: rgba(255, 255, 255, 0.16); border-radius: 6px; }
.recovery-name { font-weight: 700; }
.recovery-card {
    border-radius: 16px;
    padding: 26px 30px 22px 30px;
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.45);
}
.recovery-title { font-size: 22px; font-weight: 800; }
.recovery-lead { font-size: 13px; }
.recovery-list { background: none; }
.recovery-list row { padding: 8px 10px; border-radius: 10px; }
.recovery-list row:selected { background-color: #2f6fdf; }
.recovery-list row:selected label { color: #ffffff; }
.recovery-row-title { font-size: 14px; font-weight: 700; }
.recovery-caption { font-size: 12px; opacity: 0.68; }
.recovery-warning { color: #b3261e; font-weight: 600; }
"""

CHOICES = (
    ("restore", "freemac-lifeboat", "Restore from Lifeboat",
     "Bring a home folder back from a Lifeboat backup drive."),
    ("reinstall", "freemac-keel", "Reinstall freemac",
     "Put a fresh copy of freemac on a disk."),
    ("password", "freemac-crew", "Reset a Password",
     "Choose a new password for someone who has forgotten theirs."),
    ("check", "freemac-hull", "Check a Disk",
     "Look for problems on a disk and fix them."),
    ("drives", "freemac-hull", "Drives",
     "Look at, erase and name the drives in and plugged into this computer."),
    ("help", "freemac-guide", "Get Help Online",
     "Read freemac's help pages on the web, once you've joined a network."),
    ("terminal", "freemac-terminal", "Terminal",
     "Type commands, for people who know how."),
)


def label(text, *classes, wrap=False, xalign=0):
    widget = Gtk.Label(label=text, xalign=xalign, wrap=wrap)
    if wrap:
        widget.set_max_width_chars(60)
    for name in classes:
        widget.get_style_context().add_class(name)
    return widget


def icon(name, size=40):
    theme = Gtk.IconTheme.get_default()
    try:
        pixbuf = theme.load_icon(name, size, Gtk.IconLookupFlags.FORCE_SIZE)
        return Gtk.Image.new_from_pixbuf(pixbuf)
    except GLib.Error:
        return Gtk.Image.new_from_icon_name("applications-system", Gtk.IconSize.DIALOG)


def row(title, caption, icon_name=None):
    line = Gtk.Box(spacing=14)
    if icon_name:
        line.pack_start(icon(icon_name), False, False, 0)
    words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
    words.pack_start(label(title, "recovery-row-title"), False, False, 0)
    if caption:
        words.pack_start(label(caption, "recovery-caption", wrap=True), False, False, 0)
    line.pack_start(words, True, True, 0)
    item = Gtk.ListBoxRow()
    item.add(line)
    return item


def listbox():
    box = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE, activate_on_single_click=False)
    box.get_style_context().add_class("recovery-list")
    return box


def scrolled(child, height=300):
    scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
    scroller.set_min_content_height(height)
    scroller.set_max_content_height(height)
    scroller.set_propagate_natural_height(True)
    scroller.add(child)
    return scroller


def in_background(work, done):
    """Run work() on a thread and done(result, error) on the main loop."""
    def run():
        try:
            result, error = work(), None
        except Exception as problem:  # noqa: BLE001 - shown to the person
            result, error = None, problem
        GLib.idle_add(lambda: done(result, error) and False)
    threading.Thread(target=run, daemon=True).start()


def launch(*cmd):
    try:
        subprocess.Popen(list(cmd), stdin=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False


class Page(Gtk.Box):
    """A page of the card: a heading, a few lines, its content and buttons."""

    def __init__(self, title, lead=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.heading = label(title, "recovery-title")
        self.pack_start(self.heading, False, False, 0)
        self.lead = label(lead or "", "recovery-lead", wrap=True)
        self.pack_start(self.lead, False, False, 0)
        self.lead.set_no_show_all(not lead)
        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.pack_start(self.body, True, True, 0)
        self.buttons = Gtk.Box(spacing=8)
        self.pack_end(self.buttons, False, False, 0)
        self.back = Gtk.Button(label="Back")
        self.buttons.pack_start(self.back, False, False, 0)
        self.go = Gtk.Button(label="Continue")
        self.go.get_style_context().add_class("suggested-action")
        self.buttons.pack_end(self.go, False, False, 0)

    def say(self, lead):
        self.lead.set_text(lead)
        self.lead.set_no_show_all(False)
        self.lead.set_visible(bool(lead))


class Recovery(Gtk.ApplicationWindow):
    def __init__(self, app, windowed=False):
        super().__init__(application=app, title="freemac Recovery")
        self.get_style_context().add_class("recovery-backdrop")
        self.system = None
        self.systems = None
        self.busy = False
        overlay = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(overlay)
        overlay.pack_start(self._bar(), False, False, 0)

        self.card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, halign=Gtk.Align.CENTER,
                            valign=Gtk.Align.CENTER)
        self.card.get_style_context().add_class("recovery-card")
        self.card.get_style_context().add_class("background")
        self.card.set_size_request(640, 520)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        self.card.pack_start(self.stack, True, True, 0)
        overlay.pack_start(self.card, True, True, 0)

        self.stack.add_named(self._home(), "home")
        self.result = Page("")
        self.result.back.set_visible(False)
        self.result.back.set_no_show_all(True)
        self.result.go.set_label("Done")
        self.result.go.connect("clicked", lambda *_: self.show("home"))
        self.result_icon = Gtk.Image(halign=Gtk.Align.START)
        self.result.pack_start(self.result_icon, False, False, 0)
        self.result.reorder_child(self.result_icon, 0)
        self.stack.add_named(self.result, "result")
        self.working = Page("")
        self.bar = Gtk.ProgressBar(show_text=False)
        self.bar_words = label("", "recovery-caption")
        self.bar_words.set_ellipsize(3)
        self.working.body.pack_start(self.bar, False, False, 6)
        self.working.body.pack_start(self.bar_words, False, False, 0)
        self.working.back.set_visible(False)
        self.working.back.set_no_show_all(True)
        self.working.go.set_visible(False)
        self.working.go.set_no_show_all(True)
        self.stack.add_named(self.working, "working")
        self.pages = {}

        if windowed:
            self.set_default_size(1000, 720)
        else:
            # The whole screen, with no title bar: there is nothing behind it to go back to.
            self.set_decorated(False)
            self.fullscreen()
        self.connect("delete-event", lambda *_: self.busy)
        self.connect("key-press-event", self._key)
        if not store.live():
            self._lock()

    # -- unlocking ------------------------------------------------------------------

    def _lock(self):
        """Started from the disk, Recovery first asks for an administrator's
        password, as a Mac's does, so it can't be used to get round one. (A
        freemac USB stick doesn't ask: anyone with one can start any PC.)"""
        self.system = store.systems()[0]
        admins = store.administrators(self.system)
        if not admins:
            return
        page = self.page("unlock", "Recovery is locked",
                         "Choose an administrator and type their password to continue.")
        page.back.set_visible(False)
        page.back.set_no_show_all(True)
        grid = Gtk.Grid(row_spacing=10, column_spacing=12)
        who = Gtk.ComboBoxText()
        for name, _uid, _gid, full, _home in admins:
            who.append(name, f"{full} ({name})" if full != name else name)
        who.set_active(0)
        secret = Gtk.Entry(visibility=False, activates_default=True)
        secret.set_hexpand(True)
        grid.attach(label("Administrator", xalign=1), 0, 0, 1, 1)
        grid.attach(who, 1, 0, 1, 1)
        grid.attach(label("Password", xalign=1), 0, 1, 1, 1)
        grid.attach(secret, 1, 1, 1, 1)
        page.body.pack_start(grid, False, False, 0)
        problem = label("", "recovery-warning", wrap=True)
        page.body.pack_start(problem, False, False, 0)
        page.body.pack_start(label("Forgotten every administrator\u2019s password? Start the computer from a "
                                   "freemac USB stick, hold Ctrl as it starts, and choose Reset a Password.",
                                   "recovery-caption", wrap=True), False, False, 0)
        page.go.set_label("Unlock")
        page.go.set_can_default(True)
        tries = [0]

        def go(*_args):
            if store.password_matches(self.system, who.get_active_id(), secret.get_text()):
                self.stack.remove(page)
                del self.pages["unlock"]
                self.show("home")
                return
            tries[0] += 1
            secret.set_text("")
            problem.set_text("That password isn\u2019t right. Try again.")
            if tries[0] >= 3:
                page.go.set_sensitive(False)
                GLib.timeout_add_seconds(5 * (tries[0] - 2), lambda: page.go.set_sensitive(True) and False)
        page.go.connect("clicked", go)
        secret.connect("activate", go)
        page.show_all()
        self.stack.set_visible_child(page)
        GLib.idle_add(secret.grab_focus)

    # -- the bar along the top ------------------------------------------------------

    def _bar(self):
        bar = Gtk.Box(spacing=6)
        bar.get_style_context().add_class("recovery-bar")
        bar.pack_start(label("freemac Recovery", "recovery-name"), False, False, 0)

        power = Gtk.MenuButton()
        power.add(Gtk.Image.new_from_icon_name("system-shutdown-symbolic", Gtk.IconSize.MENU))
        power.set_tooltip_text("Restart or shut down")
        menu = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for words, action in (("Restart", lambda: self.leave(False)),
                              ("Shut Down", lambda: self.leave(None))):
            button = Gtk.ModelButton(text=words)
            button.connect("clicked", lambda _b, a=action: a())
            menu.pack_start(button, False, False, 0)
        menu.show_all()
        pop = Gtk.Popover()
        pop.add(menu)
        power.set_popover(pop)
        bar.pack_end(power, False, False, 0)

        self.wifi = Gtk.MenuButton()
        self.wifi_icon = Gtk.Image.new_from_icon_name("network-wireless-offline-symbolic", Gtk.IconSize.MENU)
        self.wifi.add(self.wifi_icon)
        self.wifi.set_tooltip_text("Wi-Fi")
        self.wifi_pop = Gtk.Popover()
        self.wifi_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=8, spacing=2)
        self.wifi_box.set_size_request(260, -1)
        self.wifi_pop.add(self.wifi_box)
        self.wifi.set_popover(self.wifi_pop)
        self.wifi_pop.connect("show", lambda *_: self.load_networks())
        bar.pack_end(self.wifi, False, False, 0)
        self._checking_network = False
        GLib.timeout_add_seconds(10, self._wifi_state)
        GLib.idle_add(self._wifi_state)
        return bar

    def _wifi_state(self):
        # One check at a time: nmcli can be slow, and piling them up makes it slower.
        if self._checking_network:
            return True
        self._checking_network = True

        def done(kind, _error):
            self._checking_network = False
            name = {"ethernet": "network-wired-symbolic",
                    "wifi": "network-wireless-signal-excellent-symbolic"}.get(
                kind, "network-wireless-offline-symbolic")
            self.wifi_icon.set_from_icon_name(name, Gtk.IconSize.MENU)
            self.wifi.set_tooltip_text({"ethernet": "Connected by cable",
                                        "wifi": "Wi-Fi"}.get(kind, "Not connected"))
        in_background(store.connection, done)
        return True

    def load_networks(self):
        for child in self.wifi_box.get_children():
            self.wifi_box.remove(child)
        self.wifi_box.pack_start(label("Looking for networks…", "recovery-caption"), False, False, 4)
        self.wifi_box.show_all()

        def done(found, _error):
            for child in self.wifi_box.get_children():
                self.wifi_box.remove(child)
            if not found:
                self.wifi_box.pack_start(label("No Wi-Fi networks were found.", "recovery-caption"),
                                         False, False, 4)
            for ssid, signal, secured, connected in (found or [])[:12]:
                words = ("✓ " if connected else "    ") + ssid + ("  \U0001F512" if secured else "")
                button = Gtk.ModelButton(text=words)
                button.connect("clicked", lambda _b, s=ssid, p=secured: self.join(s, p))
                self.wifi_box.pack_start(button, False, False, 0)
            self.wifi_box.show_all()
        in_background(store.networks, done)

    def join(self, ssid, secured):
        self.wifi_pop.popdown()
        password = None
        if secured:
            password = self.ask_text(f"The Wi-Fi network “{ssid}” needs a password.", "Password",
                                     secret=True, button="Join")
            if password is None:
                return
        in_background(lambda: store.join(ssid, password),
                      lambda _r, error: error and alert.tell(self, f"Couldn’t join “{ssid}”.",
                                                             str(error)))

    def ask_text(self, title, placeholder, secret=False, button="OK"):
        dialog = alert.build(self, title, "", [("Cancel", Gtk.ResponseType.CANCEL), (button, Gtk.ResponseType.OK)],
                             default=Gtk.ResponseType.OK)
        entry = Gtk.Entry(placeholder_text=placeholder, visibility=not secret, activates_default=True)
        dialog.get_content_area().pack_start(entry, False, False, 6)
        entry.show()
        answer = dialog.run()
        text = entry.get_text()
        dialog.destroy()
        return text if answer == Gtk.ResponseType.OK else None

    def leave(self, into_recovery):
        if self.busy:
            alert.tell(self, "Recovery is still working.", "Wait until it has finished.")
            return
        store.unmount_all()
        if into_recovery is None:
            store.shut_down()
        else:
            store.restart(into_recovery)

    # -- the first page ---------------------------------------------------------------

    def _home(self):
        page = Page("Recovery", "Choose what you’d like to do, then click Continue.")
        if os.path.exists(MARK):
            try:
                mark = Gtk.Image.new_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_size(MARK, 44, 44))
                mark.set_halign(Gtk.Align.START)
                page.pack_start(mark, False, False, 0)
                page.reorder_child(mark, 0)
            except GLib.Error:
                pass
        page.back.set_visible(False)
        page.back.set_no_show_all(True)
        self.choices = listbox()
        for key, icon_name, title, caption in CHOICES:
            item = row(title, caption, icon_name)
            item.key = key
            self.choices.add(item)
        self.choices.connect("row-activated", lambda *_: self.choose())
        self.choices.connect("row-selected", lambda *_: page.go.set_sensitive(
            self.choices.get_selected_row() is not None))
        page.body.pack_start(scrolled(self.choices, 400), True, True, 0)
        page.go.set_sensitive(False)
        page.go.connect("clicked", lambda *_: self.choose())
        return page

    def show(self, name):
        self.stack.set_visible_child_name(name)

    def choose(self):
        item = self.choices.get_selected_row()
        if item is None or self.busy:
            return
        getattr(self, "do_" + item.key)()

    def done(self, title, text, icon_name=None):
        if icon_name:
            try:
                self.result_icon.set_from_pixbuf(Gtk.IconTheme.get_default().load_icon(
                    icon_name, 64, Gtk.IconLookupFlags.FORCE_SIZE))
            except GLib.Error:
                icon_name = None
        self.result_icon.set_visible(bool(icon_name))
        self.result.heading.set_text(title)
        self.result.say(text)
        self.show("result")

    def start_work(self, title, text):
        self.busy = True
        self.working.heading.set_text(title)
        self.working.say(text)
        self.bar.set_fraction(0)
        self.bar_words.set_text("")
        self.show("working")
        self._pulse = GLib.timeout_add(120, lambda: self.busy and (self.bar.get_fraction() == 0 and
                                                                     self.bar.pulse() or True))

    def end_work(self):
        self.busy = False

    def page(self, name, title, lead=None, back="home"):
        """A page made afresh each time it's needed; Back shows the page named."""
        if name in self.pages:
            self.stack.remove(self.pages[name])
        page = Page(title, lead)
        page.back.connect("clicked", lambda *_: self.show(back))
        self.pages[name] = page
        self.stack.add_named(page, name)
        return page

    def pick_system(self, then):
        """Find the freemac to fix, asking when a USB stick sees more than one."""
        if self.system is not None:
            then(self.system)
            return

        def found(systems, _error):
            self.end_work()
            systems = systems or []
            if not systems:
                self.done("No freemac was found",
                          "None of this computer’s disks has freemac on it. To put freemac on one, "
                          "choose Reinstall freemac.")
                return
            if len(systems) == 1:
                self.system = systems[0]
                then(self.system)
                return
            page = self.page("systems", "Which freemac?",
                             "This computer has more than one freemac on its disks. Choose the one to work on.")
            choices = listbox()
            for system in systems:
                item = row(system.name, system.root, "freemac-keel")
                item.system = system
                choices.add(item)
            page.body.pack_start(scrolled(choices, 260), True, True, 0)

            def go(*_args):
                chosen = choices.get_selected_row()
                if chosen:
                    self.system = chosen.system
                    then(self.system)
            page.go.connect("clicked", go)
            choices.connect("row-activated", go)
            page.show_all()
            self.show("systems")

        self.start_work("Looking for freemac…", "Recovery is looking at this computer’s disks.")
        in_background(store.systems, found)

    # -- Restore from Lifeboat ----------------------------------------------------------

    def do_restore(self):
        self.pick_system(self._restore_sets)

    def _restore_sets(self, system):
        self.start_work("Looking for backups…", "Recovery is looking at the drives plugged into this "
                        "computer for Lifeboat backups.")

        def found(sets, _error):
            self.end_work()
            page = self.page("restore", "Restore from Lifeboat")
            if not sets:
                page.say("No Lifeboat backups were found. Plug in the drive your backups are on, wait a "
                         "moment, then click Look Again.")
                page.go.set_label("Look Again")
                page.go.connect("clicked", lambda *_: self._restore_sets(system))
            else:
                page.say("Choose the backups to bring back. Each is one person’s home folder from one "
                         "computer.")
                choices = listbox()
                for backup_set in sets:
                    newest = backup_set.backups()[0][0]
                    item = row(f"{backup_set.user} on {backup_set.computer}",
                               f"{store.describe(backup_set.drive)} · newest backup "
                               f"{backup_store.describe(newest)}", "freemac-lifeboat")
                    item.backup_set = backup_set
                    choices.add(item)
                page.body.pack_start(scrolled(choices, 300), True, True, 0)

                def go(*_args):
                    chosen = choices.get_selected_row()
                    if chosen:
                        self._restore_when(system, chosen.backup_set)
                page.go.connect("clicked", go)
                choices.connect("row-activated", go)
                if len(sets) == 1:
                    choices.select_row(choices.get_row_at_index(0))
            page.show_all()
            self.show("restore")

        in_background(store.backup_sets, found)

    def _restore_when(self, system, backup_set):
        page = self.page("restore-when", "Choose a backup",
                         f"Backups of {backup_set.user} on {backup_set.computer}, newest first.", back="restore")
        choices = listbox()
        for when, path in backup_set.backups():
            item = row(backup_store.describe(when), None)
            item.path = path
            choices.add(item)
        choices.select_row(choices.get_row_at_index(0))
        page.body.pack_start(scrolled(choices, 220), True, True, 0)

        people = system.users()
        into = Gtk.ComboBoxText()
        for name, _uid, _gid, full, _home in people:
            into.append(name, f"{full} ({name})" if full != name else name)
        if not into.set_active_id(backup_set.user) and people:
            into.set_active(0)
        line = Gtk.Box(spacing=10)
        line.pack_start(label("Bring it back into the home folder of"), False, False, 0)
        line.pack_start(into, False, False, 0)
        page.body.pack_start(line, False, False, 0)
        if not people:
            page.body.pack_start(label("This freemac has no accounts to bring the files back into. Make one "
                                       "first, then come back.", "recovery-warning", wrap=True), False, False, 0)
            page.go.set_sensitive(False)
        page.go.set_label("Restore")

        def go(*_args):
            chosen = choices.get_selected_row()
            person = next((p for p in people if p[0] == into.get_active_id()), None)
            if chosen and person:
                self._restore_now(system, chosen.path, person)
        page.go.connect("clicked", go)
        page.show_all()
        self.show("restore-when")

    def _restore_now(self, system, path, person):
        name, uid, gid, full, home = person
        when = backup_store.describe(backup_store.stamp_time(os.path.basename(path)) or time.time())
        answer = alert.ask(self, f"Bring back {full}’s home folder from {when}?",
                           "Files in the backup replace the ones of the same name in the home folder. "
                           "Anything made since then is kept.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Restore", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        self.start_work("Restoring…", f"Bringing back {full}’s files from {when}.")

        def progress(fraction, rel):
            GLib.idle_add(lambda: (self.bar.set_fraction(max(fraction, 0.01)), self.bar_words.set_text(rel))
                          and False)

        def work():
            store.writable(system)
            return store.restore(path, home, uid, gid, progress)

        def finished(count, error):
            self.end_work()
            if error:
                self.done("The files couldn’t all be restored.", str(error), "freemac-lifeboat")
            else:
                self.done("Your files are back",
                          f"{count:,} files were brought back into {full}’s home folder. Restart the "
                          "computer to use freemac as usual.", "freemac-lifeboat")
        in_background(work, finished)

    # -- Reinstall ---------------------------------------------------------------------

    def do_reinstall(self):
        if store.live():
            if not launch("freemac-keel"):
                alert.tell(self, "The installer couldn’t be opened.")
            return
        self.done("Reinstall from a freemac USB stick",
                  "To put a fresh copy of freemac on this computer, start it from a freemac USB stick "
                  "(download one from freemac’s Releases page), hold Ctrl as it starts, and choose "
                  "Reinstall freemac.\n\nReinstalling erases the disk, so bring your files back afterwards "
                  "with Restore from Lifeboat.", "freemac-keel")

    # -- Reset a password -----------------------------------------------------------------

    def do_password(self):
        self.pick_system(self._password_page)

    def _password_page(self, system):
        people = system.users()
        page = self.page("password", "Reset a Password",
                         "Choose whose password to change, then type the new one twice.")
        if not people:
            page.say("This freemac has no accounts.")
            page.go.set_sensitive(False)
            page.show_all()
            self.show("password")
            return
        grid = Gtk.Grid(row_spacing=10, column_spacing=12)
        who = Gtk.ComboBoxText()
        for name, _uid, _gid, full, _home in people:
            who.append(name, f"{full} ({name})" if full != name else name)
        who.set_active(0)
        first = Gtk.Entry(visibility=False, activates_default=True)
        again = Gtk.Entry(visibility=False, activates_default=True)
        problem = label("", "recovery-warning", wrap=True)
        for line, (words, widget) in enumerate((("Account", who), ("New password", first),
                                                 ("Again", again))):
            grid.attach(label(words, xalign=1), 0, line, 1, 1)
            widget.set_hexpand(True)
            grid.attach(widget, 1, line, 1, 1)
        page.body.pack_start(grid, False, False, 0)
        page.body.pack_start(problem, False, False, 0)
        page.go.set_label("Reset Password")

        def go(*_args):
            if not first.get_text():
                problem.set_text("Type a new password.")
                return
            if first.get_text() != again.get_text():
                problem.set_text("The two passwords aren’t the same. Type them again.")
                again.set_text("")
                again.grab_focus()
                return
            name = who.get_active_id()
            try:
                store.reset_password(system, name, first.get_text())
            except (OSError, ValueError) as error:
                problem.set_text(str(error))
                return
            full = next((p[3] for p in people if p[0] == name), name)
            self.done("The password was changed",
                      f"{full} can now log in with the new password. If they used their old password for a "
                      "keychain or saved Wi-Fi networks, those may ask for it once more.", "freemac-crew")
        page.go.connect("clicked", go)
        page.show_all()
        self.show("password")
        first.grab_focus()

    # -- Check a disk -----------------------------------------------------------------

    def do_check(self):
        page = self.page("check", "Check a Disk")
        volumes = store.checkable()
        if not volumes:
            page.say("There are no volumes that can be checked right now. A volume can only be checked "
                     "while nothing is using it." + ("" if store.live() else " To check the disk freemac "
                                                     "starts from, start from a freemac USB stick."))
            page.go.set_sensitive(False)
        else:
            page.say("Choose a volume. Checking finds problems and fixes the ones it can."
                     + ("" if store.live() else " The disk freemac is running from can be checked by starting "
                        "from a freemac USB stick."))
            choices = listbox()
            for volume in volumes:
                item = row(store.describe(volume), f"{volume['path']} · {volume['fstype']}",
                           "drive-removable-media" if volume["removable"] else "drive-harddisk")
                item.volume = volume
                choices.add(item)
            choices.select_row(choices.get_row_at_index(0))
            page.body.pack_start(scrolled(choices, 300), True, True, 0)
            page.go.set_label("Check")

            def go(*_args):
                chosen = choices.get_selected_row()
                if not chosen:
                    return
                self.start_work("Checking…", f"Checking “{store.describe(chosen.volume)}”. "
                                "This can take a few minutes on a big disk.")

                def finished(result, error):
                    self.end_work()
                    state, words = result if result else ("problem", str(error))
                    titles = {"ok": "No problems found", "fixed": "Problems were fixed",
                              "problem": "Problems found"}
                    self.done(titles[state], words, "freemac-hull")
                in_background(lambda: store.check(chosen.volume), finished)
            page.go.connect("clicked", go)
        page.show_all()
        self.show("check")

    # -- other apps ----------------------------------------------------------------------

    def do_drives(self):
        if not launch("freemac-hull"):
            alert.tell(self, "Drives couldn’t be opened.")

    def do_help(self):
        if not store.online():
            alert.tell(self, "You’re not connected to the internet.",
                       "Choose a Wi-Fi network from the Wi-Fi menu at the top right, or plug in a network "
                       "cable, then try again.")
            return
        if not launch("epiphany-browser", "--private-instance", HELP_URL) and not launch("epiphany", HELP_URL):
            alert.tell(self, "The web browser couldn’t be opened.")

    def do_terminal(self):
        if not launch("foot"):
            alert.tell(self, "Terminal couldn’t be opened.")

    def _key(self, _w, event):
        if event.keyval == Gdk.KEY_Escape and self.stack.get_visible_child_name() not in ("home", "working",
                                                                                         "unlock"):
            self.show("home")
            return True
        return False


class RecoveryApp(Gtk.Application):
    def __init__(self, windowed):
        super().__init__(application_id="org.freemac.Recovery")
        self.windowed = windowed

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)

    def do_activate(self):
        window = self.get_active_window() or Recovery(self, self.windowed)
        window.show_all()
        window.present()

    def do_shutdown(self):
        store.unmount_all()
        Gtk.Application.do_shutdown(self)


def main():
    GLib.set_prgname("freemac-recovery")
    windowed = "--window" in sys.argv
    args = [a for a in sys.argv if a != "--window"]
    sys.exit(RecoveryApp(windowed).run(args))
