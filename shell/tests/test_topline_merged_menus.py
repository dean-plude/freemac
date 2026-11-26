# SPDX-License-Identifier: GPL-3.0-or-later
"""An app's own Window and Help menus join Topline's (freemac 1.244), as a
Mac app's main menu does once Ferry puts it in the menu bar: the items come
from the app's menu model, with their shortcuts the Mac way, a tick where
the app's action has one, and greyed out where it's off. Quit goes to the
app's own quit action when it has one. Run from the repository with

    python3 -m unittest discover -s shell/tests
"""
import os
import sys
import types
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

try:
    from gi.repository import Gio, GLib

    from freemac_shell import topline
except (ImportError, ValueError):   # no gi bindings, or none of Topline's libraries, for this Python
    raise unittest.SkipTest("needs Python's gi bindings and Topline's libraries")

T = topline.Topline


def stub(merged, groups):
    self = types.SimpleNamespace(_merged=merged, _groups=groups)
    for name in ("_model_rows", "_action_of", "_merged_rows", "_help_extras"):
        setattr(self, name, types.MethodType(getattr(T, name), self))
    self._plain_label = T._plain_label
    return self


class MergedMenus(unittest.TestCase):
    def setUp(self):
        self.chosen = []
        group = Gio.SimpleActionGroup()
        on_top = Gio.SimpleAction.new_stateful("0", None, GLib.Variant.new_boolean(True))
        on_top.connect("activate", lambda *_: self.chosen.append("on top"))
        never = Gio.SimpleAction.new("1", None)
        never.set_enabled(False)
        guide = Gio.SimpleAction.new("2", None)
        guide.connect("activate", lambda *_: self.chosen.append("guide"))
        quit_ = Gio.SimpleAction.new("quit", None)
        for action in (on_top, never, guide, quit_):
            group.add_action(action)
        self.groups = {"app": group}

        window = Gio.Menu()
        first = Gio.Menu()
        item = Gio.MenuItem.new("Float on __Top", "app.0")
        item.set_attribute_value("accel", GLib.Variant.new_string("<Shift><Control>t"))
        first.append_item(item)
        sub = Gio.Menu()
        sub.append("Inside", "app.2")
        first.append_submenu("More", sub)      # submenus are left out
        window.append_section(None, first)
        second = Gio.Menu()
        second.append("Never", "app.1")
        second.append("Gone", "app.9")          # an action the app doesn't have
        window.append_section(None, second)
        help_ = Gio.Menu()
        help_.append("Player _Help", "app.2")
        self.merged = {"Window": window, "Help": help_}

    def test_window_rows(self):
        rows = stub(self.merged, self.groups)._merged_rows("Window")
        self.assertEqual(len(rows), 4)
        label, shortcut, run, tick = rows[0]
        self.assertEqual((label, shortcut, tick), ("Float on _Top", "⇧⌘T", True))
        run()
        self.assertEqual(self.chosen, ["on top"])
        self.assertIsNone(rows[1])
        self.assertEqual(rows[2], ("Never", "", None, None))
        self.assertEqual(rows[3], ("Gone", "", None, None))

    def test_help_items(self):
        extras = stub(self.merged, self.groups)._help_extras()
        self.assertEqual([row[0] for row in extras], ["Player Help"])
        extras[0][2]()
        self.assertEqual(self.chosen, ["guide"])

    def test_nothing_merged(self):
        self.assertEqual(stub({}, self.groups)._merged_rows("Window"), [])
        self.assertEqual(stub({}, {})._help_extras(), [])

    def test_quit_action(self):
        self.assertIsNotNone(stub({}, self.groups)._action_of("app.quit"))
        self.assertIsNone(stub({}, {})._action_of("app.quit"))
        self.assertIsNone(stub({}, self.groups)._action_of("win.quit"))

    def test_merged_titles(self):
        self.assertEqual(T.MERGED, ("Window", "Help"))


if __name__ == "__main__":
    unittest.main()
