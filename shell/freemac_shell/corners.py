# SPDX-License-Identifier: GPL-3.0-or-later
"""Hot corners: move the pointer into a corner of the screen to do something.

Wayfire's activator bindings take "hotspot <edges> <along>x<away> <ms>"
next to keys and swipes, so a corner is one more way to trigger an action
that already has a shortcut. Dials > Desktop & Dock picks an action for each
corner; this module writes that into wayfire.ini by adding the corner to the
action's binding and taking it off any other.
"""

CORNERS = (("top-left", "Top left"), ("top-right", "Top right"),
           ("bottom-left", "Bottom left"), ("bottom-right", "Bottom right"))
SIZE = "10x10"
DELAY = 250   # ms the pointer rests in the corner first

# action id -> (label, section, option, command or None)
ACTIONS = {
    "none": ("Nothing", None, None, None),
    "overview": ("All windows", "scale", "toggle_all", None),
    "desktops": ("All desktops", "expo", "toggle", None),
    "apps": ("All apps", "command", "binding_marina", None),
    "show-desktop": ("Show the desktop", "wm-actions", "toggle_showdesktop", None),
    "notifications": ("Notifications", "command", "binding_corner_notifications", "freemac-beacon --center"),
    "note": ("New note in Jot", "command", "binding_corner_note", "freemac-jot"),
    "quick-note": ("Quick Note", "command", "binding_corner_quick_note", "freemac-jot --quick"),
    "lock": ("Lock the screen", "command", "binding_lock", None),
    "saver": ("Start the screen saver", "command", "binding_corner_saver", "freemac-screensaver"),
}
ORDER = ("none", "overview", "desktops", "apps", "show-desktop", "notifications", "quick-note", "note", "saver",
         "lock")


def parts(value):
    return [p.strip() for p in (value or "").split("|") if p.strip()]


def corner_of(part):
    words = part.split()
    if len(words) >= 2 and words[0] == "hotspot":
        return words[1]
    return None


def current(ini_get):
    """{corner: action id} from wayfire.ini."""
    found = {corner: "none" for corner, _label in CORNERS}
    for action, (_label, section, option, _cmd) in ACTIONS.items():
        if section is None:
            continue
        for part in parts(ini_get(section, option, "")):
            corner = corner_of(part)
            if corner in found:
                found[corner] = action
    return found


def assign(ini_get, ini_set, corner, action):
    """Make `corner` do `action` (an ACTIONS key), and nothing else."""
    for other, (_label, section, option, command) in ACTIONS.items():
        if section is None:
            continue
        value = ini_get(section, option, "")
        kept = [p for p in parts(value) if corner_of(p) != corner]
        if other == action:
            kept.append(f"hotspot {corner} {SIZE} {DELAY}")
            if command:
                ini_set(section, option.replace("binding_", "command_", 1), command)
        if kept != parts(value):
            ini_set(section, option, " | ".join(kept))
