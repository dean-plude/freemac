# SPDX-License-Identifier: GPL-3.0-or-later
"""The Battery menu in the menu bar, as on a Mac: the charge, the power
source, Low Power Mode, the apps using significant energy and Battery
Settings. The symbol itself, and its low-battery warnings, are status.Battery.
"""
import os
import shlex

from . import apps, battery, energy, style  # noqa: E402
from .menubar_popup import Popup  # noqa: E402
from .status import Battery, launch  # noqa: E402


def charge_words(facts):
    """The line under Power Source: how charging is going, or how long is left."""
    status, left = facts.get("status"), facts.get("left")
    if status == "Full" or (facts.get("plugged") and facts.get("capacity", 0) >= 100):
        return "Battery Is Charged"
    if status == "Charging":
        return f"Charging, {left} until full" if left else "Charging"
    if facts.get("plugged"):
        return "Not Charging"
    return f"{left} remaining" if left else None


def programs(app_id):
    """The program an app's .desktop file runs, as more names its processes
    may go by (Firefox's window is "firefox", its program firefox-esr)."""
    info = apps.app_info(app_id)
    line = info.get_commandline() if info and hasattr(info, "get_commandline") else None
    try:
        words = shlex.split(line or "")
    except ValueError:
        return []
    words = [w for w in words if "=" not in w or w.startswith("/")]
    while words and os.path.basename(words[0]) == "env":
        words = words[1:]
    if not words:
        return []
    program = os.path.basename(words[0])
    if program.startswith(energy.INTERPRETERS) or program in ("flatpak", "snap"):
        return []
    return [program]


def app_name(app_id):
    info = apps.app_info(app_id)
    return info.get_name() if info else app_id


class BatteryMenu(Battery):
    def __init__(self):
        self.sampler = self.popup = None
        super().__init__()
        self.sampler = energy.Sampler(programs=programs)
        self.popup = Popup("freemac-battery")
        self.update()

    def update(self):
        super().update()
        if self.sampler is not None and self.get_visible():
            # Every 30 seconds while there's a battery: how much each app used.
            self.sampler.sample()
        if self.popup is not None and self.popup.visible():
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
        facts = self.facts or {}
        p.title("Battery", self._figure(f"{facts.get('capacity', 0)}%"))
        p.note("Power Source: " + ("Power Adapter" if facts.get("plugged") else "Battery"))
        words = charge_words(facts)
        if words:
            p.note(words)
        p.separator()
        mode = style.prefs().get("low_power_mode", "never")
        on = battery.low_power_wanted(mode, bool(facts.get("plugged"))) or self.low_power
        p.switch_row("Low Power Mode", on, self._low_power)
        p.separator()
        busy = self.sampler.significant()
        if busy:
            p.heading("Using Significant Energy")
            for app_id in busy[:5]:
                p.item(app_name(app_id), lambda: launch("freemac-gauge"), gicon=apps.icon_for(app_id))
        else:
            p.heading("No Apps Using Significant Energy")
        p.separator()
        p.item("Battery Settings…", lambda: launch("freemac-dials", "--panel", "power"))
        p.menu.show_all()

    @staticmethod
    def _figure(words):
        from gi.repository import Gtk
        label = Gtk.Label(label=words)
        label.get_style_context().add_class("sound-menu-heading")
        return label

    def _low_power(self, on):
        """The menu's switch: Low Power Mode always, or never. Dials > Battery
        keeps the finer choices (only on battery, only on the adapter)."""
        style.save_prefs(low_power_mode="always" if on else "never")
        self.low_power_for = None       # apply it now, not at the next look
        super().update()
