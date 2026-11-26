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
        info = _just_made(app_id)
    if not info:
        for other in Gio.AppInfo.get_all():
            wm_class = other.get_startup_wm_class() if hasattr(other, "get_startup_wm_class") else None
            if wm_class and wm_class.lower() == app_id.lower():
                info = other
                break
    info = _mac_app_entry(info)
    _cache[app_id] = info
    return info


def _mac_app_entry(info):
    """A Mac app's windows carry its bundle identifier, which finds the entry
    Ferry writes for them (X-Ferry-Bundle names the app). When the app is in
    the app grid, its entry there (X-freemac-MacApp) stands for it instead:
    the one pinned to the Dock, and the one that knows the app's documents
    and gives them to the copy that's running."""
    if not isinstance(info, Gio.DesktopAppInfo) or not info.has_key("X-Ferry-Bundle"):
        return info
    import os
    bundle = os.path.realpath(info.get_string("X-Ferry-Bundle") or "")
    for other in Gio.AppInfo.get_all():
        if isinstance(other, Gio.DesktopAppInfo) and other.has_key("X-freemac-MacApp"):
            if os.path.realpath(other.get_string("X-freemac-MacApp") or "") == bundle:
                return other
    return info


def _just_made(app_id):
    """An app entry made in the last moments (a website added to the Dock):
    GLib's list of apps only learns of a new file once its folder watch has
    told it, so read the person's own apps folder directly."""
    import os
    folder = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                          "applications")
    name = app_id if app_id.endswith(".desktop") else app_id + ".desktop"
    path = os.path.join(folder, name)
    if "/" in name or not os.path.exists(path):
        return None
    try:
        return Gio.DesktopAppInfo.new_from_filename(path)
    except TypeError:
        return None


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
