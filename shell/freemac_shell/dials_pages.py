# SPDX-License-Identifier: GPL-3.0-or-later
"""The pages of Dials (freemac's settings), by name, for Dials' own sidebar
search and for Seek, which opens Dials at the page that matches. Kept apart
from dials.py so Seek can read it without loading the settings app."""

# name: (title, icon), in the sidebar's order.
PAGES = {
    "network": ("Network", "network-wired-symbolic"),
    "bluetooth": ("Bluetooth", "bluetooth-active-symbolic"),
    "sharing": ("Sharing", "folder-publicshare-symbolic"),
    "notifications": ("Notifications", "preferences-system-notifications-symbolic"),
    "sound": ("Sound", "audio-volume-high-symbolic"),
    "about": ("About", "help-about-symbolic"),
    "softwareupdate": ("Software Update", "freemac-software-update-symbolic"),
    "datetime": ("Date & Time", "preferences-system-time-symbolic"),
    "appearance": ("Appearance", "preferences-desktop-appearance-symbolic"),
    "accessibility": ("Accessibility", "preferences-desktop-accessibility-symbolic"),
    "dock": ("Dock and Menu Bar", "view-app-grid-symbolic"),
    "displays": ("Displays", "video-display-symbolic"),
    "wallpaper": ("Wallpaper", "preferences-desktop-wallpaper-symbolic"),
    "screensaver": ("Screen Saver", "weather-clear-night-symbolic"),
    "power": ("Power", "battery-good-symbolic"),
    "lifeboat": ("Lifeboat", "document-open-recent-symbolic"),
    "users": ("Users", "system-users-symbolic"),
    "loginitems": ("Login Items", "system-run-symbolic"),
    "accounts": ("Internet Accounts", "emblem-synchronizing-symbolic"),
    "keyboard": ("Keyboard", "input-keyboard-symbolic"),
    "pointing": ("Trackpad and Mouse", "input-touchpad-symbolic"),
    "printers": ("Printers", "printer-symbolic"),
}

# Other words people use for what's on each page, for the sidebar's search.
SEARCH_WORDS = {
    "network": "wifi wi-fi internet wireless ethernet vpn proxy firewall security block incoming connections nearby sharing airdrop receive files localsend",
    "bluetooth": "pair headphones speaker mouse keyboard",
    "sharing": "computer name rename hostname local network nearby sharing airdrop localsend remote login ssh terminal file sharing public folder windows smb samba",
    "notifications": "alerts banners do not disturb focus",
    "sound": "volume speaker microphone output input audio alert chime",
    "about": "version storage memory system update",
    "softwareupdate": "software update updates upgrade security patches automatic automatically install new version check",
    "datetime": "date time clock time zone timezone 24-hour 12-hour seconds automatic internet ntp city",
    "appearance": "dark light mode theme accent colour color highlight purple pink red orange yellow green graphite text size tiling",
    "accessibility": "zoom contrast larger text reduce motion screen reader transparency solid invert colours colors speak selection speech read aloud out loud voice spoken content text to speech",
    "dock": "hide automatically autohide auto-hide menu bar magnification trash downloads title bar double-click hide minimize windows application icon default web browser email mail app links",
    "displays": "screen resolution brightness night light scale monitor",
    "wallpaper": "background desktop picture",
    "screensaver": "screensaver idle drift clock album photos slideshow inactive",
    "power": "battery sleep suspend energy shut down restart percentage low battery time left charging",
    "lifeboat": "backup back up time machine restore drive disk copy",
    "users": "accounts password login automatic log in people",
    "loginitems": "startup start up open at login launch automatically apps autostart",
    "accounts": "icloud fastmail nextcloud yahoo caldav carddav sync online calendar contacts reminders",
    "keyboard": "shortcuts command key layout input sources input menu language typing keyboard languages key repeat delay until repeat control space spelling spell check misspelled dictionary text input text replacements shortcuts abbreviations smart quotes curly apostrophe dash double space full stop period",
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
