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
        "To see which app is slowing the computer down, open Gauge and look at the % CPU column.",
    ]),
    "busy": ("See what's using your computer", "activity monitor gauge slow cpu memory processor busy fan hot process task manager", [
        "Gauge shows each open app with how much of the processor and memory it's using. Press ⌘Space, "
        "type Gauge and press Return.",
        "Click CPU or Memory at the top to switch. Click a column's heading to sort by it.",
        "Under the list, a graph shows the last two minutes.",
        "- View > My Processes or All Processes lists every program, not only apps.",
        "- To quit one, select it and click ✕ at the top left, or press Delete. Quit asks it to close; "
        "Force Quit ends it at once and loses what it hasn't saved.",
    ]),
    "disk-utility": ("Rename, erase or eject a drive", "disk utility hull drive usb stick format erase rename eject space full exfat fat", [
        "Hull shows every drive, how full it is and what kind it is. Press ⌘Space, type Hull and press Return.",
        "Choose a drive or a volume on the left, then use the buttons at the top.",
        "- Rename: type a new name. Double-clicking a volume does the same.",
        "- Erase: deletes everything on it. Choose ExFAT for a drive you'll also use with a Mac or "
        "Windows computer.",
        "- Eject: do this before you unplug a drive, so nothing being saved is lost.",
        "Hull won't change the disk freemac is running from.",
    ]),
    "camera": ("Take a picture of yourself", "camera webcam selfie photo picture pose effects booth countdown", [
        "Pose takes pictures with the computer's camera. Press ⌘Space, type Pose and press Return.",
        "Click the red button (or press Space). Pose counts down 3, 2, 1 so you can get ready, then "
        "takes the picture. Click 3 seconds to take pictures straight away instead.",
        "Click Effects for fun ones: bend your face, make it a comic or an old movie, and more. "
        "The picture is taken with the effect you choose.",
        "Your pictures are saved in the Pose folder in Pictures, and show along the bottom of the window. "
        "Double-click one to open it, or right-click it to move it to the Trash.",
        "If Pose says no camera is connected, plug one in. If another app is using the camera, quit it first.",
    ]),
    "weather": ("See the weather", "weather forecast sky temperature rain snow sun hourly week celsius fahrenheit", [
        "Sky shows the weather. Press ⌘Space, type Sky and press Return.",
        "The first time, Sky shows the weather for the city of your time zone. Click + and type a city "
        "or town to add more places, then click a place on the left to see its weather.",
        "You'll see the temperature now, the next 24 hours, the next 10 days, and how it feels, the wind "
        "and when the sun rises or sets.",
        "To switch between °F and °C, choose View > Fahrenheit or View > Celsius. To remove a place, "
        "right-click it and choose Remove.",
        "Sky needs the internet. If it can't connect, it shows the last weather it got.",
    ]),
    "stickies": ("Leave yourself a sticky note", "sticky note notes stickies memo reminder desktop post-it", [
        "Stickies puts little coloured notes on your desktop. Press ⌘Space, type Stickies and press Return, "
        "or click Stickies in the Dock, and a new note appears. Just start typing.",
        "Drag a note by its top strip to move it, and drag its bottom-right corner to make it bigger. "
        "Click the dots on the strip to change its colour, or + for another note.",
        "Notes stay under your windows. To keep one in front, right-click its strip and choose Float on Top.",
        "Your notes are kept as you type and come back when you log in. To throw one away, click the × on its strip.",
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
    "copy-files": ("Copy, move and duplicate files", "copy paste move cut duplicate drag folder undo files "
                   "replace keep both", [
        "Drag files onto a folder, a place in Drawer's sidebar, the Desktop or another Drawer window to move "
        "them there. Onto another disk, such as a USB drive, they're copied instead. Hold ⌥ while you drop "
        "to copy them anyway.",
        "Or select them and press ⌘C, open the folder where they should go, and press ⌘V for a copy, or ⌥⌘V "
        "to move them. Edit > Paste Item and Move Item Here do the same.",
        "⌘D makes a copy beside the original, called “name copy”.",
        "If the folder already has something with that name, you're asked: Keep Both (the new one is called "
        "“name 2”), Stop, or Replace (the old one goes to the Trash).",
        "A long copy shows a small window with how much is left. Click its stop button to stop it; the half-made "
        "copy is removed.",
        "Changed your mind? ⌘Z (Edit > Undo) takes back the last move, copy, rename, new folder or Move to Trash.",
    ]),
    "music": ("Play your music", "music songs album artist play shuffle repeat mp3 shanty itunes playlist", [
        "Shanty plays the music in your Music folder. Click it in the Dock. It finds new songs each time it opens.",
        "To add songs, drag them or their folder onto Shanty's window, or choose File > Add to Library…. "
        "They're copied into your Music folder.",
        "Albums, Artists, Songs and Recently Added are in the sidebar. Double-click a song or an album to play it.",
        "- Space plays and pauses, ⌘→ and ⌘← go to the next and previous song.",
        "- The buttons at the top turn shuffle and repeat on and off. Click repeat again to repeat one song.",
        "- Type in the search field to find a song, an artist or an album.",
        "The song playing shows in the menu bar's quick settings, and the media keys on your keyboard work "
        "even when Shanty is behind other windows.",
    ]),
    "videos": ("Watch a video", "video movie film play watch mp4 mov quicktime player reel full screen", [
        "Reel plays videos. Double-click a video in Drawer. Or press ⌘Space, type Reel, and double-click "
        "one of the videos in your Videos folder.",
        "Move the pointer to show the controls; they fade while the video plays.",
        "- Space plays and pauses. ← and → go back or forward 10 seconds.",
        "- F, or the button at the right of the controls, fills the screen. Esc goes back.",
        "- ↑ and ↓ turn the sound up and down.",
        "Close a video partway through and Reel starts it again where you stopped next time.",
    ]),
    "backups": ("Back up your files", "backup back up time machine lifeboat drive restore copy safe", [
        "Lifeboat copies your home folder to a drive every hour while the drive is plugged in, and keeps "
        "earlier backups, so you can get back a file you deleted or changed.",
        "Plug in a USB drive or another disk, choose Dials > Lifeboat, and pick it next to Backup drive. "
        "The first backup starts within a minute and takes a while; later ones only copy what changed.",
        "If it says the drive can't hold backups, click Erase Drive…. Everything on it is deleted.",
        "Lifeboat keeps every backup of the last day, one a day for a month, and one a week before that. "
        "When the drive is full, the oldest go first.",
        "To eject the drive, eject it as usual. A backup that's running stops and starts again next time.",
    ]),
    "restore": ("Get back a file from a backup", "restore backup lifeboat deleted lost earlier version old file", [
        "Press F4 and click Lifeboat, or choose Go > Browse Backups in Drawer to start at that folder. "
        "The backup drive must be plugged in.",
        "Backups are listed by date on the left. Choose a time, then open folders as you would in Drawer.",
        "The Now column says whether each file is the same now, has changed since, or is gone now.",
        "Double-click a file to open a copy of it. Choose the files you want, then click Restore: copies go back "
        "where they were. If there's already a file with that name, you're asked whether to keep both.",
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
