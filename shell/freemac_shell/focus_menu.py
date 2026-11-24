# SPDX-License-Identifier: GPL-3.0-or-later
"""The Focus menu in the menu bar, as on a Mac: while a Focus is on (by hand
or by its schedule) its symbol shows beside the clock, and a click on it
lists the Focuses, the one on in blue, with how long it lasts. A click on
one turns it on, or off when it's the one on; Focus Settings… opens Dials.
Original freemac code.
"""
from gi.repository import Gtk

from . import beacon, notify_rules  # noqa: E402
from .menubar_popup import Popup  # noqa: E402
from .status import StatusButton, launch  # noqa: E402


class FocusMenu(StatusButton):
    def __init__(self):
        super().__init__()
        self.popup = Popup("freemac-focus-menu")
        self.focus = None
        self.prefs = {}
        self.connect("clicked", lambda *_: self._clicked())

    def update(self, prefs):
        """Topline calls this on each tick of the clock and when shell.json
        changes, since a schedule can turn a Focus on with nothing else
        saying so."""
        self.prefs = prefs
        focus = notify_rules.active_focus(prefs)
        changed = focus != self.focus
        self.focus = focus
        if focus is None:
            self.shown = None
            self.popup.hide()
            self.hide()
            return
        self.show_icon(notify_rules.focus_icon(focus), f"{notify_rules.focus_name(focus)} is on")
        if changed and self.popup.visible():
            self.fill()

    def _clicked(self):
        if self.popup.visible():
            self.popup.hide()
            return
        self.fill()
        self.popup.show_under(self)

    def fill(self):
        p = self.popup
        p.clear()
        p.title("Focus")
        p.separator()
        for focus, name, icon, _schedule in notify_rules.FOCUSES:
            on = focus == self.focus
            button = p.item(name, lambda focus=focus: self._pick(focus), icon=icon, round_icon=True, on=on)
            until = notify_rules.until(self.prefs) if on else ""
            if until:
                words = Gtk.Label(label=until.capitalize())
                words.get_style_context().add_class("sound-menu-heading")
                button.get_child().pack_end(words, False, False, 0)
            button.set_tooltip_text(f"Turn off {name}" if on else f"Turn on {name}")
        p.separator()
        p.item("Focus Settings…", lambda: launch("freemac-dials", "--panel", "focus"))
        p.menu.show_all()

    def _pick(self, focus):
        prefs = self.prefs
        # The one on already: a click turns it off.
        chosen = None if notify_rules.active_focus(prefs) == focus else focus
        beacon.write_prefs(**notify_rules.focus_writes(chosen, prefs))
