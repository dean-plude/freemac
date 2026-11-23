# SPDX-License-Identifier: GPL-3.0-or-later
"""Map Wayland app ids to installed applications (.desktop files)."""
from gi.repository import Gio

_cache = {}


def app_info(app_id):
    """Return a Gio.DesktopAppInfo for a window's app id, or None."""
    if not app_id:
        return None
    if app_id in _cache:
        return _cache[app_id]
    info = None
    for candidate in (app_id, app_id.lower(), app_id.split(".")[-1].lower()):
        try:
            info = Gio.DesktopAppInfo.new(candidate + ".desktop")
        except TypeError:
            info = None
        if info:
            break
    if not info:
        for other in Gio.AppInfo.get_all():
            wm_class = other.get_startup_wm_class() if hasattr(other, "get_startup_wm_class") else None
            if wm_class and wm_class.lower() == app_id.lower():
                info = other
                break
    _cache[app_id] = info
    return info


# Helper programs with no app entry of their own, named the way a person
# would think of them.
# The app id of windows the desktop opens in a process of their own (Get Info,
# Rename Items, View Options). Not "freemac-backdrop": a window with the
# desktop's own id is given a frame the size of a big window.
DESKTOP_WINDOW = "freemac-desktop-window"

HELPER_NAMES = {
    "polkit-mate-authentication-agent-1": "Password",
    "gtklock": "Lock Screen",
    "freemac-backdrop": "Drawer",   # the desktop's own windows, such as Get Info
    DESKTOP_WINDOW: "Drawer",
    "freemac-power": "freemac",
    "freemac-beacon": "Notification Centre",   # its Widgets window
    "freemac-hail": "Nearby",   # Hail's window and its questions   # Restart, Shut Down and Log Out's question
}


# Long names some apps give themselves, and what the menu bar calls them.
KNOWN_SHORT = {
    "gnu image manipulation program": "GIMP",
    "vlc media player": "VLC",
    "welcome to freemac": "Welcome",
}

# Words that describe an app rather than name it, as in "Firefox Web Browser".
# A Mac's menu bar shows only the name.
DESCRIPTIVE_ENDINGS = (
    " web browser", " internet browser", " media player", " video player",
    " music player", " text editor", " code editor", " image viewer", " document viewer",
    " email client", " mail client", " file manager", " office suite",
)


def short_name(info):
    """The name an app goes by in the menu bar, the Dock and the app switcher:
    its own short name if it gives one, else its name without the words that
    only describe it."""
    if not info:
        return ""
    get = getattr(info, "get_string", None)
    for key in ("X-Freemac-ShortName",):
        value = get(key) if get else None
        if value:
            return value
    name = info.get_name() or ""
    known = KNOWN_SHORT.get(name.lower())
    if known:
        return known
    lower = name.lower()
    for ending in DESCRIPTIVE_ENDINGS:
        if lower.endswith(ending) and len(name) > len(ending):
            return name[:-len(ending)].strip()
    return name


def display_name(app_id, title=""):
    if app_id in HELPER_NAMES:
        return HELPER_NAMES[app_id]
    info = app_info(app_id)
    if info:
        return short_name(info)
    if app_id:
        return app_id.split(".")[-1].replace("-", " ").title()
    return title or "Desktop"


def icon_for(app_id):
    info = app_info(app_id)
    icon = info.get_icon() if info else None
    return icon or Gio.ThemedIcon.new("application-x-executable")


def launch(desktop_id):
    try:
        info = Gio.DesktopAppInfo.new(desktop_id)
    except TypeError:
        info = None
    if info:
        info.launch([], None)
        return True
    return False
