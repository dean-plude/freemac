# SPDX-License-Identifier: GPL-3.0-or-later
"""The pages of Dials (freemac's settings), by name, for Dials' own sidebar
search and for Seek, which opens Dials at the page that matches. Kept apart
from dials.py so Seek can read it without loading the settings app."""

# name: (title, icon), in the sidebar's order.
PAGES = {
    "network": ("Network", "network-wired-symbolic"),
    "bluetooth": ("Bluetooth", "bluetooth-active-symbolic"),
    "notifications": ("Notifications", "preferences-system-notifications-symbolic"),
    "sound": ("Sound", "audio-volume-high-symbolic"),
    "about": ("About", "help-about-symbolic"),
    "appearance": ("Appearance", "preferences-desktop-appearance-symbolic"),
    "accessibility": ("Accessibility", "preferences-desktop-accessibility-symbolic"),
    "dock": ("Dock and Menu Bar", "view-app-grid-symbolic"),
    "displays": ("Displays", "video-display-symbolic"),
    "wallpaper": ("Wallpaper", "preferences-desktop-wallpaper-symbolic"),
    "power": ("Power", "battery-good-symbolic"),
    "lifeboat": ("Lifeboat", "document-open-recent-symbolic"),
    "users": ("Users", "system-users-symbolic"),
    "accounts": ("Internet Accounts", "emblem-synchronizing-symbolic"),
    "keyboard": ("Keyboard", "input-keyboard-symbolic"),
    "pointing": ("Trackpad and Mouse", "input-touchpad-symbolic"),
    "printers": ("Printers", "printer-symbolic"),
}

# Other words people use for what's on each page, for the sidebar's search.
SEARCH_WORDS = {
    "network": "wifi wi-fi internet wireless ethernet vpn proxy",
    "bluetooth": "pair headphones speaker mouse keyboard",
    "notifications": "alerts banners do not disturb focus",
    "sound": "volume speaker microphone output input audio alert chime",
    "about": "version computer name storage memory system update",
    "appearance": "dark light mode theme accent text size tiling",
    "accessibility": "zoom contrast larger text reduce motion screen reader",
    "dock": "menu bar magnification trash downloads title bar double-click hide minimize windows application icon",
    "displays": "screen resolution brightness night light scale monitor",
    "wallpaper": "background desktop picture",
    "power": "battery sleep suspend energy shut down restart",
    "lifeboat": "backup back up time machine restore drive disk copy",
    "users": "accounts password login automatic log in people",
    "accounts": "icloud fastmail nextcloud yahoo caldav carddav sync online calendar contacts reminders",
    "keyboard": "shortcuts command key layout input language typing",
    "pointing": "trackpad mouse click scroll tap pointer speed",
    "printers": "print scanner",
}


def matching(query):
    """Names of the pages whose title or usual words hold every word of
    the query: those whose title starts with it first, then those with a
    word of the title that does ("mouse" for Trackpad and Mouse)."""
    words = query.lower().split()
    if not words:
        return []
    found = []
    for name, (title, _icon) in PAGES.items():
        text = (title + " " + SEARCH_WORDS.get(name, "")).lower()
        if all(any(t.startswith(w) for t in text.split()) for w in words):
            low = title.lower()
            rank = 0 if low.startswith(words[0]) else 1 if any(t.startswith(words[0]) for t in low.split()) else 2
            found.append((rank, name))
    return [name for _rank, name in sorted(found, key=lambda f: f[0])]
