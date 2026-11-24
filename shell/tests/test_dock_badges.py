# SPDX-License-Identifier: GPL-3.0-or-later
"""What apps tell the Dock: badges (numbers and words), attention, progress
and the app's own Dock menu items, as launcher_badge, dock_menu and Pier
read them. Run from the repository with

    python3 -m unittest discover -s shell/tests

(with a Python that has the gi bindings). The menu tests talk to a stand-in
app on a private session bus, so they need dbus-daemon; the ones that build
GTK menus need a display, and are skipped without one.
"""
import os
import sys
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

try:
    import gi

    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
except (ImportError, ValueError):   # no gi bindings for this Python
    raise unittest.SkipTest("needs Python's gi bindings")

from freemac_shell import dock_menu, launcher_badge  # noqa: E402

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
ENTRY = "com.canonical.Unity.LauncherEntry"


def recorded(name):
    """A D-Bus message body recorded from a real app, in GVariant's text form."""
    with open(os.path.join(DATA, name)) as f:
        text = "".join(line for line in f if not line.startswith("#")).strip()
    return GLib.Variant.parse(None, text, None, None)


def update(props):
    """An Update signal's properties as the Dock gets them off the bus."""
    variants = {k: v if isinstance(v, GLib.Variant) else _variant(v) for k, v in props.items()}
    _uri, unpacked = GLib.Variant("(sa{sv})", ("application://app.desktop", variants)).unpack()
    return unpacked


def _variant(value):
    if isinstance(value, bool):
        return GLib.Variant("b", value)
    if isinstance(value, int):
        return GLib.Variant("x", value)
    if isinstance(value, float):
        return GLib.Variant("d", value)
    return GLib.Variant("s", value)


class LauncherEntryProperties(unittest.TestCase):
    def test_count(self):
        badge = launcher_badge.merge(None, update({"count": 3, "count-visible": True}), ":1.5")
        self.assertEqual(badge["count"], 3)
        self.assertEqual(launcher_badge.text_of(badge), "3")
        self.assertEqual(launcher_badge.shown(badge), (3, None))
        self.assertEqual(badge["sender"], ":1.5")

    def test_count_hidden_or_zero(self):
        self.assertIsNone(launcher_badge.text_of(launcher_badge.merge(None, update({"count": 3,
                                                                                     "count-visible": False}))))
        self.assertIsNone(launcher_badge.text_of(launcher_badge.merge(None, update({"count": 0}))))
        self.assertEqual(launcher_badge.merge(None, update({"count": -4}))["count"], 0)

    def test_label_shown_in_place_of_the_count(self):
        badge = launcher_badge.merge(None, update({"count": 1, "count-visible": True,
                                                   launcher_badge.LABEL_KEY: "New"}))
        self.assertEqual(launcher_badge.text_of(badge), "New")
        badge = launcher_badge.merge(badge, update({launcher_badge.LABEL_KEY: "!"}))
        self.assertEqual(launcher_badge.text_of(badge), "!")

    def test_empty_label_takes_it_away(self):
        badge = launcher_badge.merge(None, update({"count": 1, launcher_badge.LABEL_KEY: "New"}))
        badge = launcher_badge.merge(badge, update({"count": 0, "count-visible": False,
                                                    launcher_badge.LABEL_KEY: ""}))
        self.assertNotIn("label", badge)
        self.assertIsNone(launcher_badge.text_of(badge))
        badge = launcher_badge.merge(badge, update({"count": 5, "count-visible": True}))
        self.assertEqual(launcher_badge.text_of(badge), "5")

    def test_later_updates_keep_what_they_leave_out(self):
        badge = launcher_badge.merge(None, update({"count": 2, "count-visible": True}))
        badge = launcher_badge.merge(badge, update({"urgent": True}))
        self.assertEqual(badge["count"], 2)
        self.assertTrue(badge["urgent"])

    def test_progress(self):
        badge = launcher_badge.merge(None, update({"progress": 0.4, "progress-visible": True}))
        self.assertEqual(launcher_badge.shown(badge), (0, 0.4))
        badge = launcher_badge.merge(badge, update({"progress": 1.7}))
        self.assertEqual(launcher_badge.shown(badge)[1], 1.0)
        badge = launcher_badge.merge(badge, update({"progress": -1.0}))
        self.assertEqual(launcher_badge.shown(badge)[1], 0.0)
        badge = launcher_badge.merge(badge, update({"progress-visible": False}))
        self.assertIsNone(launcher_badge.shown(badge)[1])
        self.assertIsNone(launcher_badge.text_of(badge))

    def test_wrong_types_are_passed_over(self):
        badge = launcher_badge.merge(None, update({"count": 4}))
        badge = launcher_badge.merge(badge, update({"count": "lots", "progress": "half",
                                                    launcher_badge.LABEL_KEY: GLib.Variant("i", 3),
                                                    "quicklist": GLib.Variant("i", 3)}))
        self.assertEqual(badge["count"], 4)
        self.assertNotIn("progress", badge)
        self.assertNotIn("label", badge)
        self.assertNotIn("quicklist", badge)

    def test_quicklist_as_string_or_object_path(self):
        for value in (GLib.Variant("s", "/app/menu"), GLib.Variant("o", "/app/menu")):
            badge = launcher_badge.merge(None, update({"quicklist": value}), ":1.9")
            self.assertEqual(launcher_badge.menu_of(badge), (":1.9", "/app/menu"))
        badge = launcher_badge.merge(badge, update({"quicklist": ""}), ":1.9")
        self.assertIsNone(launcher_badge.menu_of(badge))
        self.assertIsNone(launcher_badge.menu_of(launcher_badge.merge(None, update({"quicklist": "/m"}))))

    def test_recorded_ferry_update(self):
        """An Update a Mac app sent through Ferry, with the label "New"."""
        uri, props = recorded("ferry-update.txt").unpack()
        self.assertEqual(launcher_badge.desktop_id_of(uri), "dockmenu.desktop")
        badge = launcher_badge.merge(None, props, ":1.2")
        self.assertEqual(launcher_badge.text_of(badge), "New")
        self.assertFalse(badge["urgent"])
        self.assertEqual(launcher_badge.menu_of(badge), (":1.2", "/com/canonical/unity/launcherentry/ferry/menu"))

    def test_desktop_id(self):
        self.assertEqual(launcher_badge.desktop_id_of("application://org.telegram.desktop.desktop"),
                         "org.telegram.desktop.desktop")
        self.assertEqual(launcher_badge.desktop_id_of("application://thunderbird"), "thunderbird.desktop")
        self.assertIsNone(launcher_badge.desktop_id_of("file:///x"))


class BadgeText(unittest.TestCase):
    def test_numbers(self):
        self.assertEqual(launcher_badge.badge_text(7), "7")
        self.assertEqual(launcher_badge.badge_text(9999), "9999")
        self.assertEqual(launcher_badge.badge_text(12345), "12K")

    def test_short_labels_as_sent(self):
        for label in ("New", "!", "99+", "Beta"):
            self.assertEqual(launcher_badge.label_text(label), label)

    def test_long_labels_end_in_an_ellipsis(self):
        text = launcher_badge.label_text("Downloading")
        self.assertEqual(len(text), launcher_badge.LABEL_LIMIT)
        self.assertEqual(text, "Downloa\u2026")
        self.assertEqual(launcher_badge.label_text("x" * launcher_badge.LABEL_LIMIT), "x" * launcher_badge.LABEL_LIMIT)
        # No space left before the ellipsis.
        self.assertEqual(launcher_badge.label_text("Get it now"), "Get it\u2026")

    def test_one_line(self):
        self.assertEqual(launcher_badge.label_text("  Hi\nthere "), "Hi there")
        self.assertEqual(launcher_badge.label_text(" a\tb "), "a b")
        self.assertIsNone(launcher_badge.label_text("   "))
        self.assertIsNone(launcher_badge.label_text(None))


class Attention(unittest.TestCase):
    def test_critical_hops_until_you_go_to_the_app(self):
        seen = set()
        asking = {"urgent": True}
        self.assertTrue(launcher_badge.still_urgent("a.desktop", asking, False, seen))
        self.assertTrue(launcher_badge.still_urgent("a.desktop", asking, False, seen))
        self.assertFalse(launcher_badge.still_urgent("a.desktop", asking, True, seen))
        # Back in the background, still asking (the app never said stop): no more hops.
        self.assertFalse(launcher_badge.still_urgent("a.desktop", asking, False, seen))

    def test_informational_ends_when_the_app_stops_asking(self):
        seen = set()
        self.assertTrue(launcher_badge.still_urgent("a.desktop", {"urgent": True}, False, seen))
        self.assertFalse(launcher_badge.still_urgent("a.desktop", {"urgent": False}, False, seen))

    def test_asking_again_hops_again(self):
        seen = set()
        launcher_badge.still_urgent("a.desktop", {"urgent": True}, True, seen)
        launcher_badge.still_urgent("a.desktop", {"urgent": False}, False, seen)
        self.assertTrue(launcher_badge.still_urgent("a.desktop", {"urgent": True}, False, seen))

    def test_no_badge_no_hops(self):
        self.assertFalse(launcher_badge.still_urgent("a.desktop", None, False, set()))

    def test_one_hop_then_a_rest(self):
        try:
            from freemac_shell import pier
        except (ImportError, ValueError) as e:
            self.skipTest(f"Pier needs GTK and gtk-layer-shell: {e}")
        lift, resting = pier.attention_hop(0.0)
        self.assertEqual((lift, resting), (0.0, False))
        lift, resting = pier.attention_hop(pier.BOUNCE_PERIOD / 2)
        self.assertAlmostEqual(lift, 1.0)
        self.assertFalse(resting)
        # Ferry's informational request stops after a second: by then the one hop has landed.
        self.assertTrue(pier.attention_hop(1.0)[1])
        self.assertTrue(pier.BOUNCE_PERIOD < 1.0 < pier.BOUNCE_PERIOD + pier.ATTENTION_REST)
        self.assertFalse(pier.attention_hop(pier.BOUNCE_PERIOD + pier.ATTENTION_REST + 0.1)[1])


class MenuLayout(unittest.TestCase):
    """A Dock menu a Mac app served through Ferry (recorded GetLayout reply)."""

    def setUp(self):
        self.rows = dock_menu.parse_layout(recorded("ferry-dock-menu.txt").unpack())

    def test_items_in_order(self):
        labels = [r.get("label", "-") for r in self.rows]
        self.assertEqual(labels, ["New Window", "Nothing Playing", "-", "Shuffle", "Some Selected", "-", "Recent"])

    def test_states(self):
        by_label = {r["label"]: r for r in self.rows if "label" in r}
        self.assertTrue(by_label["New Window"]["enabled"])
        self.assertFalse(by_label["Nothing Playing"]["enabled"])
        self.assertEqual(by_label["Shuffle"]["mark"], dock_menu.TICK)
        self.assertEqual(by_label["Some Selected"]["mark"], dock_menu.DASH)
        self.assertEqual(by_label["New Window"]["mark"], "")
        self.assertTrue(dock_menu.has_marks(self.rows))

    def test_hidden_items_and_doubled_separators_go(self):
        self.assertNotIn("Hidden", [r.get("label") for r in self.rows])
        for a, b in zip(self.rows, self.rows[1:]):
            self.assertFalse(a.get("separator") and b.get("separator"))

    def test_submenu_and_underscores(self):
        recent = self.rows[-1]
        self.assertEqual([r["label"] for r in recent["children"]], ["my_notes.txt"])
        self.assertIsInstance(recent["children"][0]["id"], int)

    def test_ids_are_the_apps(self):
        ids = [r["id"] for r in self.rows]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(isinstance(i, int) and i > 0 for i in ids))

    def test_labels(self):
        self.assertEqual(dock_menu.label_of("_File"), "File")
        self.assertEqual(dock_menu.label_of("a__b"), "a_b")
        self.assertEqual(dock_menu.label_of("Save _As\u2026"), "Save As\u2026")

    def test_separators_at_the_ends_go(self):
        nodes = ((1, {"type": GLib.Variant("s", "separator")}, []),
                 (2, {"label": GLib.Variant("s", "Only")}, []),
                 (3, {"type": GLib.Variant("s", "separator")}, []))
        layout = GLib.Variant("(u(ia{sv}av))", (1, (0, {}, [GLib.Variant("(ia{sv}av)", n) for n in nodes])))
        self.assertEqual(dock_menu.parse_layout(layout.unpack()),
                         [{"id": 2, "label": "Only", "enabled": True, "mark": ""}])

    def test_not_a_layout(self):
        self.assertEqual(dock_menu.parse_layout(None), [])
        self.assertEqual(dock_menu.parse_layout((1, "nonsense")), [])


MENU_XML = """
<node><interface name="com.canonical.dbusmenu">
  <method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/>
    <arg type="as" direction="in"/><arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
  <method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/>
    <arg type="v" direction="in"/><arg type="u" direction="in"/></method>
  <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
</interface></node>
"""


class StandInApp:
    """An app on the private bus that serves the recorded Dock menu. answer:
    "now", "never" (holds every GetLayout unanswered) or "error"."""

    def __init__(self, address, answer="now", about_to_show=True):
        self.answer, self.about_to_show = answer, about_to_show
        self.calls, self.events, self.held = [], [], []
        self.bus = Gio.DBusConnection.new_for_address_sync(
            address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)
        node = Gio.DBusNodeInfo.new_for_xml(MENU_XML)
        self.reg = self.bus.register_object("/app/menu", node.interfaces[0], self.method, None, None)
        self.name = self.bus.get_unique_name()
        self.layout = recorded("ferry-dock-menu.txt")

    def method(self, _bus, _sender, _path, _iface, method, params, invocation):
        self.calls.append(method)
        if method == "AboutToShow":
            if self.about_to_show:
                invocation.return_value(GLib.Variant("(b)", (False,)))
            else:
                invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", "no AboutToShow")
        elif method == "GetLayout":
            if self.answer == "never":
                self.held.append(invocation)
            elif self.answer == "error":
                invocation.return_dbus_error("org.freedesktop.DBus.Error.Failed", "no menu")
            else:
                invocation.return_value(self.layout)
        elif method == "Event":
            self.events.append(params.unpack())
            invocation.return_value(None)

    def close(self):
        self.bus.unregister_object(self.reg)
        self.bus.close_sync(None)


@unittest.skipUnless(GLib.find_program_in_path("dbus-daemon"), "needs dbus-daemon for a private bus")
class MenuOverTheBus(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.test_bus = Gio.TestDBus.new(Gio.TestDBusFlags.NONE)
        cls.test_bus.up()
        cls.address = cls.test_bus.get_bus_address()

    @classmethod
    def tearDownClass(cls):
        cls.test_bus.down()

    def setUp(self):
        dock_menu._stuck.clear()
        self.dock = Gio.DBusConnection.new_for_address_sync(
            self.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)

    def tearDown(self):
        self.dock.close_sync(None)

    def wait(self, until, seconds=3.0):
        end = time.monotonic() + seconds
        context = GLib.MainContext.default()
        while not until() and time.monotonic() < end:
            context.iteration(False)
            time.sleep(0.002)
        return until()

    def fetch(self, app, timeout_ms=dock_menu.TIMEOUT_MS):
        results = []
        started = time.monotonic()
        dock_menu.fetch(self.dock, app.name, "/app/menu", results.append, timeout_ms)
        self.assertTrue(self.wait(lambda: results))
        took = time.monotonic() - started
        self.wait(lambda: False, 0.3 + timeout_ms / 1000)   # nothing more comes
        self.assertEqual(len(results), 1, "done is called once")
        return results[0], took

    def test_reads_the_menu(self):
        app = StandInApp(self.address)
        try:
            rows, _took = self.fetch(app)
        finally:
            app.close()
        self.assertEqual(app.calls[:2], ["AboutToShow", "GetLayout"])
        self.assertEqual(rows, dock_menu.parse_layout(app.layout.unpack()))

    def test_without_about_to_show(self):
        app = StandInApp(self.address, about_to_show=False)
        try:
            rows, _took = self.fetch(app)
        finally:
            app.close()
        self.assertEqual(rows[0]["label"], "New Window")

    def test_click_sends_the_event(self):
        app = StandInApp(self.address)
        try:
            dock_menu.click(self.dock, app.name, "/app/menu", 7, 1234)
            self.assertTrue(self.wait(lambda: app.events))
        finally:
            app.close()
        ident, kind, data, timestamp = app.events[0]
        self.assertEqual((ident, kind, timestamp), (7, "clicked", 1234))

    def test_timeout_falls_back(self):
        app = StandInApp(self.address, answer="never")
        try:
            rows, took = self.fetch(app, timeout_ms=200)
            self.assertIsNone(rows)
            self.assertLess(took, 1.5)
            # Still stuck: the next menu opens at once, without asking it.
            calls = len(app.calls)
            rows, took = self.fetch(app, timeout_ms=200)
            self.assertIsNone(rows)
            self.assertLess(took, 0.15)
            self.assertEqual(len(app.calls), calls)
        finally:
            for invocation in app.held:
                invocation.return_value(app.layout)   # too late: nothing changes
            self.wait(lambda: False, 0.2)
            app.close()

    def test_error_falls_back(self):
        app = StandInApp(self.address, answer="error")
        try:
            rows, _took = self.fetch(app)
        finally:
            app.close()
        self.assertIsNone(rows)

    def test_app_gone_falls_back(self):
        app = StandInApp(self.address)
        name = app.name
        app.close()
        results = []
        dock_menu.fetch(self.dock, name, "/app/menu", results.append)
        self.assertTrue(self.wait(lambda: results))
        self.assertEqual(results, [None])

    def test_no_bus_falls_back(self):
        results = []
        dock_menu.fetch(None, ":1.1", "/app/menu", results.append)
        self.assertTrue(self.wait(lambda: results))
        self.assertEqual(results, [None])

    def test_listener_keeps_the_sender_and_forgets_it(self):
        changes = []
        listener = launcher_badge.Listener.__new__(launcher_badge.Listener)
        listener.changed = lambda: changes.append(1)
        listener.badges, listener.senders, listener.watches = {}, {}, {}
        listener.bus = self.dock
        self.dock.signal_subscribe(None, ENTRY, "Update", None, None, Gio.DBusSignalFlags.NONE, listener._update)
        app = StandInApp(self.address)
        app.bus.emit_signal(None, "/app", ENTRY, "Update", GLib.Variant("(sa{sv})", (
            "application://app.desktop", {"count": GLib.Variant("x", 2), "count-visible": GLib.Variant("b", True),
                                          launcher_badge.LABEL_KEY: GLib.Variant("s", "Beta"),
                                          "quicklist": GLib.Variant("o", "/app/menu")})))
        self.assertTrue(self.wait(lambda: "app.desktop" in listener.badges))
        badge = listener.get("app.desktop")
        self.assertEqual(launcher_badge.text_of(badge), "Beta")
        self.assertEqual(launcher_badge.menu_of(badge), (app.name, "/app/menu"))
        app.close()   # the app quits: its badge and menu go
        self.assertTrue(self.wait(lambda: "app.desktop" not in listener.badges))


class GtkMenu(unittest.TestCase):
    """The app's rows as GTK menu items (needs a display)."""

    @classmethod
    def setUpClass(cls):
        try:
            gi.require_version("Gtk", "3.0")
            from gi.repository import Gtk
        except (ImportError, ValueError):
            raise unittest.SkipTest("needs GTK 3")
        if not Gtk.init_check()[0]:
            raise unittest.SkipTest("needs a display")
        cls.Gtk = Gtk

    def make_item(self, label, mark, ticks):
        item = self.Gtk.MenuItem(label=(mark or " ") + " " + label if ticks else label)
        return item

    def test_builds_the_menu(self):
        Gtk = self.Gtk
        rows = dock_menu.parse_layout(recorded("ferry-dock-menu.txt").unpack())
        menu = Gtk.Menu()
        chosen = []
        dock_menu.add_rows(menu, rows, self.make_item, chosen.append)
        items = menu.get_children()
        self.assertEqual(len(items), len(rows))
        self.assertIsInstance(items[2], Gtk.SeparatorMenuItem)
        self.assertEqual(items[0].get_label(), "  New Window")
        self.assertFalse(items[1].get_sensitive())
        self.assertEqual(items[3].get_label(), dock_menu.TICK + " Shuffle")
        sub = items[-1].get_submenu()
        self.assertIsNotNone(sub)
        self.assertEqual(sub.get_children()[0].get_label(), "my_notes.txt")
        items[0].activate()
        sub.get_children()[0].activate()
        self.assertEqual(chosen, [rows[0]["id"], rows[-1]["children"][0]["id"]])

    def test_dock_menu_order(self):
        """As on a Mac: the app's windows, then its own items, then the Dock's."""
        try:
            from freemac_shell import pier
        except (ImportError, ValueError) as e:
            self.skipTest(f"Pier needs gtk-layer-shell: {e}")
        item = pier.Item(StubPier(), app_id="org.example.Stand-in")
        item.views = [{"id": 1, "title": "Notes", "app-id": "org.example.Stand-in", "last-focus-timestamp": 2},
                      {"id": 2, "title": "Inbox", "app-id": "org.example.Stand-in", "last-focus-timestamp": 1}]
        rows = dock_menu.parse_layout(recorded("ferry-dock-menu.txt").unpack())
        item._show_menu(rows, (":1.4", "/app/menu"))
        shown = [menu_text(child) for child in item.menu.get_children()]
        self.assertEqual(shown, ["Inbox", "Notes", "-",
                                 "New Window", "Nothing Playing", "-", "Shuffle", "Some Selected", "-", "Recent", "-",
                                 "Options", "Show All Windows", "-", "Hide", "Quit"])
        # The front window has its tick; the app's ticked item has its own.
        marks = {menu_text(c): menu_mark(c) for c in item.menu.get_children()}
        self.assertEqual((marks["Notes"], marks["Inbox"]), ("✓", ""))
        self.assertEqual(marks["Shuffle"], dock_menu.TICK)

    def test_dock_menu_without_app_items(self):
        try:
            from freemac_shell import pier
        except (ImportError, ValueError) as e:
            self.skipTest(f"Pier needs gtk-layer-shell: {e}")
        item = pier.Item(StubPier(), app_id="org.example.Stand-in")
        item.views = [{"id": 1, "title": "Notes", "app-id": "org.example.Stand-in"}]
        item._show_menu()
        self.assertEqual([menu_text(c) for c in item.menu.get_children()],
                         ["Notes", "-", "Options", "Show All Windows", "-", "Hide", "Quit"])


class StubPier:
    """Just enough of the Dock for one of its items to build its menu."""
    base, vertical, side, config, wf = 48, False, "bottom", {}, None
    pinned, places, recent = [], [], {}

    def __init__(self):
        self.badges = type("Badges", (), {"bus": None, "get": lambda self, _id: None})()

    def show_badges(self):
        return True

    def show_dots(self):
        return True

    def hold_up(self, _menu):
        pass

    def popup_beside(self, _menu, _widget):
        pass


def _labels(child):
    from gi.repository import Gtk
    box = child.get_child()
    return [w.get_text() for w in box.get_children()] if isinstance(box, Gtk.Box) else ["", child.get_label()]


def menu_text(child):
    from gi.repository import Gtk
    return "-" if isinstance(child, Gtk.SeparatorMenuItem) else _labels(child)[-1]


def menu_mark(child):
    return _labels(child)[0]


if __name__ == "__main__":
    unittest.main()
