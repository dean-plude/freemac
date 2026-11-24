# SPDX-License-Identifier: GPL-3.0-or-later
"""Which Mac apps may control other windows (freemac 1.215, Ferry 0.41.0):
the answers window_control keeps for Ferry's AXIsProcessTrusted,
freemac-allow-control's asking only once, and the switches in Dials >
Privacy & Security. Run from the repository with

    python3 -m unittest discover -s shell/tests

The Dials test builds GTK widgets, so it needs a display and is skipped
without one.
"""
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from freemac_shell import window_control  # noqa: E402


class Store(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.env = mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": self.dir.name})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.dir.cleanup()

    def stored(self):
        with open(window_control.path()) as f:
            return json.load(f)

    def test_path_follows_the_config_folder(self):
        self.assertEqual(window_control.path(), os.path.join(self.dir.name, "freemac", "window-control.json"))
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": "", "HOME": "/home/someone"}):
            self.assertEqual(window_control.path(), "/home/someone/.config/freemac/window-control.json")

    def test_nothing_kept_is_not_asked_yet(self):
        self.assertIsNone(window_control.answer("com.example.Spectacle"))
        self.assertEqual(window_control.apps(), [])

    def test_answers_are_kept_in_the_file_ferry_reads(self):
        window_control.set_allowed("com.example.Spectacle", True, "Spectacle")
        window_control.set_allowed("/opt/tools/shiftit", False)
        self.assertEqual(self.stored(), {"apps": {
            "com.example.Spectacle": {"name": "Spectacle", "allowed": True},
            "/opt/tools/shiftit": {"name": "shiftit", "allowed": False},
        }})
        self.assertTrue(window_control.answer("com.example.Spectacle"))
        self.assertFalse(window_control.answer("/opt/tools/shiftit"))
        self.assertEqual(window_control.apps(), [("/opt/tools/shiftit", "shiftit", False),
                                                 ("com.example.Spectacle", "Spectacle", True)])

    def test_turning_off_keeps_the_name_and_forget_asks_again(self):
        window_control.set_allowed("com.example.Spectacle", True, "Spectacle")
        window_control.set_allowed("com.example.Spectacle", False)
        self.assertEqual(self.stored()["apps"]["com.example.Spectacle"], {"name": "Spectacle", "allowed": False})
        window_control.forget("com.example.Spectacle")
        self.assertIsNone(window_control.answer("com.example.Spectacle"))

    def test_a_damaged_file_is_nothing_kept(self):
        os.makedirs(os.path.dirname(window_control.path()))
        for text in ("not json", "[]", '{"apps": []}', '{"apps": {"x": {"allowed": "yes"}}}'):
            with open(window_control.path(), "w") as f:
                f.write(text)
            self.assertEqual(window_control.load(), {}, text)

    def test_names_and_question(self):
        self.assertEqual(window_control.display_name("com.example.Spectacle"), "Spectacle")
        self.assertEqual(window_control.display_name("/Applications/Flycut.app/Contents/MacOS/Flycut"), "Flycut")
        self.assertEqual(window_control.question("ShiftIt"), "Allow “ShiftIt” to control other windows?")

    def test_main_keeps_an_answer_and_asks_only_once(self):
        with mock.patch.object(window_control, "ask") as ask:
            self.assertEqual(window_control.main(["--app-id", "com.example.Spectacle", "--name", "Spectacle",
                                                  "--answer", "allow"]), 0)
            # asked again (even told to deny): the kept answer stands, no dialog
            self.assertEqual(window_control.main(["--app-id", "com.example.Spectacle", "--answer", "deny"]), 0)
            self.assertEqual(window_control.main(["--app-id", "org.example.Other", "--answer", "deny"]), 1)
            ask.assert_not_called()
        self.assertEqual(window_control.apps(), [("org.example.Other", "Other", False),
                                                 ("com.example.Spectacle", "Spectacle", True)])

    def test_main_asks_the_user_when_nothing_is_kept(self):
        def the_user_denies(app_id, name):     # as ask() does: shows the dialog, keeps the answer
            window_control.set_allowed(app_id, False, name)
            return False

        with mock.patch.object(window_control, "ask", side_effect=the_user_denies) as ask:
            self.assertEqual(window_control.main(["--app-id", "com.example.Flycut", "--name", "Flycut"]), 1)
            self.assertEqual(window_control.main(["--app-id", "com.example.Flycut", "--name", "Flycut"]), 1)
            ask.assert_called_once_with("com.example.Flycut", "Flycut")


def gtk():
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        return None
    try:
        import gi

        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
    except (ImportError, ValueError):
        return None
    return Gtk if Gtk.init_check([])[0] else None


class Dials(unittest.TestCase):
    def setUp(self):
        self.Gtk = gtk()
        if not self.Gtk:
            self.skipTest("needs a display and Python's GTK bindings")
        self.dir = tempfile.TemporaryDirectory()
        self.env = mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": self.dir.name})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.dir.cleanup()

    def window(self):
        Gtk = self.Gtk

        def group():
            return Gtk.ListBox()

        def row(title, widget=None, subtitle=None):
            box = Gtk.Box()
            box.title = title
            box.pack_start(Gtk.Label(label=title), True, True, 0)
            if widget:
                box.pack_end(widget, False, False, 0)
            return box

        def switch(active, changed):
            s = Gtk.Switch(active=active)
            s.connect("notify::active", lambda w, _p: changed(w.get_active()))
            return s

        class Window:
            helpers = (group, row, None, None, switch)
        return Window()

    def rows(self, listbox):
        return [r.get_child() for r in listbox.get_children()]

    def find(self, widget, kind):
        if isinstance(widget, kind):
            return [widget]
        found = []
        if isinstance(widget, self.Gtk.Container):
            for child in widget.get_children():
                found += self.find(child, kind)
        return found

    def test_the_section_lists_the_apps_with_their_switches(self):
        from freemac_shell import dials_security

        heading, listbox, _caption = dials_security.control_section(self.window())
        self.assertEqual(heading.get_text(), "Control Other Windows")
        self.assertEqual([r.title for r in self.rows(listbox)], ["No Mac app has asked yet"])

        window_control.set_allowed("com.example.Spectacle", True, "Spectacle")
        window_control.set_allowed("com.example.Flycut", False, "Flycut")
        heading, listbox, _caption = dials_security.control_section(self.window())
        rows = self.rows(listbox)
        self.assertEqual([r.title for r in rows], ["Flycut", "Spectacle"])
        spectacle = self.find(rows[1], self.Gtk.Switch)[0]
        self.assertTrue(spectacle.get_active())
        spectacle.set_active(False)
        self.assertFalse(window_control.answer("com.example.Spectacle"))

        forget = [b for b in self.find(rows[0], self.Gtk.Button) if b.get_label() == "Forget"][0]
        forget.clicked()
        self.assertIsNone(window_control.answer("com.example.Flycut"))
        self.assertEqual([r.title for r in self.rows(listbox)], ["Spectacle"])


if __name__ == "__main__":
    unittest.main()
