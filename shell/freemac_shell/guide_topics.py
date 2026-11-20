# SPDX-License-Identifier: GPL-3.0-or-later
"""The freemac Guide: short topics on how to do everyday things.

Help in the menu bar lists the topics that match what you type, under the
menu items, and Seek finds them too; either opens the topic in Guide. Kept
apart from guide.py, with no GTK, so the menu bar and Seek can read it
without loading the Guide window. Original freemac text.

Each topic is (title, usual words, paragraphs). A paragraph that starts
with "- " is a line of a list.
"""

TOPICS = {
    "keys": ("Use the Command key", "command cmd alt key shortcut copy paste keyboard ctrl control", [
        "Command (⌘) is the key right next to the space bar: Alt on most PC keyboards. "
        "Option (⌥) is the key beside it.",
        "Command with a letter does what Ctrl does on other PCs, in every app:",
        "- ⌘C copies, ⌘V pastes and ⌘X cuts.",
        "- ⌘Z undoes and ⇧⌘Z redoes.",
        "- ⌘S saves, ⌘O opens and ⌘P prints.",
        "- ⌘W closes the window and ⌘Q quits the app.",
        "With a Mac keyboard, choose Dials > Keyboard and make the Windows key Command.",
    ]),
    "apps": ("Open and switch apps", "launch start open app switch tab dock marina launcher", [
        "Click an app in the Dock, or press ⌘Space and type the first letters of its name, then Return.",
        "Press F4 for every app on one screen. Drag an app onto another to make a folder.",
        "To switch apps, hold ⌘ and press Tab until the app you want is chosen, then let go. "
        "⌘` goes to the app's next window.",
        "An app stays open after its last window closes, with a dot under it in the Dock. "
        "⌘Q quits it.",
    ]),
    "windows": ("Arrange windows", "window close tile half fill minimize zoom full screen resize move desktop", [
        "The three round buttons at the top left of a window close it, minimize it into the Dock, "
        "and zoom it.",
        "Drag a window to the left or right edge to fill that half of the screen, "
        "or press Control+⌘ with an arrow key.",
        "- ⌘M minimizes the window.",
        "- Control+⌘F makes it full screen.",
        "- ⌘H hides the app and ⌥⌘H hides the others.",
        "- Control+Up shows every window; click one to bring it forward.",
        "Window > Fill and Window > Center in the menu bar work on the window in front.",
    ]),
    "desktops": ("Use more than one desktop", "desktop space workspace virtual swipe overview", [
        "freemac has four desktops. Control+Left and Control+Right move between them, "
        "as a three-finger swipe does.",
        "Control+Down shows all four. Control+Shift with an arrow key takes the window in front "
        "to the next desktop.",
    ]),
    "seek": ("Search with Seek", "seek search find spotlight calculate sum file", [
        "Press ⌘Space, type, and press Return to open the first result. The arrow keys move "
        "down the list.",
        "Seek finds apps, settings, the menu items of the app in front, files by their names "
        "and by the words inside them.",
        "Type a sum such as 12*7 to see the answer; Return copies it.",
    ]),
    "help": ("Find a menu item", "help menu item command search find", [
        "Click Help at the end of the menu bar and just type. The menu items that match show "
        "under the search field, with the menu they're in and their shortcut.",
        "Press Return to choose the first one; it does exactly what it does in its own menu.",
        "Guide topics that match are listed under them.",
    ]),
    "files": ("Find and organize files", "drawer files folder finder documents downloads trash copy rename", [
        "Drawer shows your files. Click it in the Dock.",
        "- ⌘1, ⌘2 and ⌘3 show icons, a list or columns.",
        "- Space shows a quick preview of the file you chose.",
        "- F2 renames, and Delete moves a file to the Trash.",
        "- ⌘I shows a file's information, and ⌘T opens a tab.",
        "Click the Trash in the Dock to see it and empty it.",
    ]),
    "screenshot": ("Take a screenshot", "screenshot screen picture capture record print lens", [
        "- ⇧⌘3 takes a picture of the whole screen.",
        "- ⇧⌘4 lets you drag around part of it.",
        "- ⇧⌘5 records part of the screen; press it again to stop.",
        "The pictures go on the desktop and are copied, ready to paste. A small preview shows in the "
        "corner for a moment.",
    ]),
    "wifi": ("Join a Wi-Fi network", "wifi wi-fi wireless internet network password connect", [
        "Click the network icon in the menu bar, or choose Dials > Network, and choose the network.",
        "Type its password when asked. freemac remembers it next time.",
    ]),
    "appearance": ("Change the look", "dark light mode wallpaper theme accent background appearance", [
        "Choose Dials > Appearance for light or dark, and Dials > Wallpaper for the picture on the desktop.",
        "Each wallpaper has a day and a night version, and follows light and dark.",
    ]),
    "sound": ("Change the volume", "sound volume mute speaker headphones audio output", [
        "Use the volume keys, or click the sound icon in the menu bar and drag the slider.",
        "Choose Dials > Sound to pick the output, such as headphones.",
    ]),
    "install": ("Install apps", "install app store harbor download update software", [
        "Harbor lists free apps. Click Install beside one; it shows in the Dock and in F4 when it's ready.",
        "Harbor also installs updates for freemac itself.",
        "Apps from the Mac App Store don't run on freemac.",
    ]),
    "lock": ("Lock, restart or shut down", "lock shut down restart reboot log out power off", [
        "Control+⌘Q locks the screen. Type your password to come back.",
        "The freemac menu at the left end of the menu bar has Lock Screen, Restart, Shut Down and Log Out.",
    ]),
    "stuck": ("When an app stops answering", "force quit frozen stuck hang not responding crash", [
        "Press ⌥⌘⎋ (Option, Command and Escape), or choose Force Quit in the freemac menu, "
        "then choose the app and Force Quit.",
        "Anything not saved in that app is lost.",
    ]),
    "clipboard": ("Paste something copied earlier", "clipboard history paste copied earlier", [
        "Press ⇧⌘V to see what you copied recently. Click one to copy it again, then paste it with ⌘V.",
    ]),
    "photos": ("Bring in photos from a phone or camera", "photos pictures import camera phone iphone android sd card cove", [
        "Connect the phone or camera with its cable, or put its memory card in. On a phone, allow access "
        "to photos when it asks.",
        "Open Cove. The phone or camera shows in the sidebar under Devices: click it.",
        "Click Import All New Items. Photos already brought in are dimmed with a tick and aren't copied again.",
        "To bring in only some, click one, then ⌘-click the others, and click Import Selected.",
        "The photos go into your Pictures folder, in a folder for each day, and show in Cove under "
        "Recently Added.",
    ]),
    "drives": ("Use a USB drive or memory card", "usb drive stick flash memory card sd disk external eject unmount", [
        "Plug the drive in. Its icon shows on the Desktop, at the top right, and under Locations in "
        "Drawer's sidebar.",
        "Double-click the icon, or click it in Drawer, to see what's on it. Drag files onto it to copy them there.",
        "Before you pull it out, eject it: click the Eject button next to it in Drawer, press ⌘E, or drag its "
        "icon onto the Trash in the Dock. Its icon goes away when it's safe to unplug.",
        "If it says the disk wasn't ejected, an app still has a file open on it. Close that file or quit the app, "
        "and eject it again.",
    ]),
    "calendars": ("Show, hide and colour your calendars", "calendar calendars colour color hide show tide work family", [
        "In Tide, click Calendars at the top left (or press ⌥⌘S) to see the list of your calendars: "
        "Home on this computer, each calendar from an online account, and Birthdays.",
        "Click a calendar's box to show or hide its events. Hidden calendars still sync and still give alerts.",
        "Right-click a calendar to give it another colour.",
        "To move an event to another calendar, double-click it and pick one next to calendar:. "
        "It moves online too, the next time the account syncs.",
    ]),
    "albums": ("Make a photo album and play a slideshow", "album albums photos pictures slideshow cove collection", [
        "In Cove, click + next to My Albums (or press ⌘N), type a name and press Return.",
        "To add photos, drag them onto the album in the sidebar, or select them, right-click and choose Add to Album. "
        "Hold ⌘ or Shift while you click to select more than one.",
        "To take a photo out of an album, open the album, select the photo and press Delete. "
        "It stays in your library.",
        "To play a slideshow, open an album (or the Library) and click the play button at the top right. "
        "Space pauses, the arrow keys go back and forward, and Esc ends it.",
    ]),
    "share": ("Send files by mail or copy them to a drive", "share send mail email attach copy usb drive stick", [
        "In Drawer, Cove or Frame, select what you want to send and click the Share button at the top "
        "(a tray with an arrow), or right-click and choose Share. File > Share… does the same.",
        "Mail opens a new message in Post with the files attached. Type who it's to and click Send.",
        "Copy to puts a copy on a USB drive or memory card that's plugged in. If the drive already has a file "
        "with that name, the copy is called “name 2”, so nothing is replaced.",
        "When the copy is done, Drawer's status line or a notification says so. "
        "Eject the drive before you unplug it.",
    ]),
}


def matching(query):
    """Names of the topics whose title or usual words hold every word of the
    query, those whose title has the first word first."""
    words = query.lower().split()
    if not words:
        return []
    found = []
    for name, (title, usual, _body) in TOPICS.items():
        low = title.lower()
        text = (low + " " + usual).split()
        if all(any(t.startswith(w) for t in text) for w in words):
            found.append((0 if any(t.startswith(words[0]) for t in low.split()) else 1, name))
    return [name for _rank, name in sorted(found, key=lambda f: f[0])]
