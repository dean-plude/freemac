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


def display_name(app_id, title=""):
    info = app_info(app_id)
    if info:
        return info.get_name()
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
