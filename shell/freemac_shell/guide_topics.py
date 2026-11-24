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
    "apps": ("Open and switch apps", "launch start open app switch tab dock marina launcher quit hide", [
        "Click an app in the Dock, or press ⌘Space and type the first letters of its name, then Return.",
        "Press F4 for every app on one screen. Drag an app onto another to make a folder.",
        "To switch apps, hold ⌘ and press Tab until the app you want is chosen, then let go. "
        "⌘` goes to the app's next window. While the switcher is up, press Q to quit the chosen app "
        "or H to hide it. ⌘← and ⌘→ move along the row too.",
        "An app stays open after its last window closes, with a dot under it in the Dock. "
        "⌘Q quits it.",
    ]),
    "windows": ("Arrange windows", "window close tile half quarter fill center centre minimize zoom full screen resize move desktop previous size green button side by side left right", [
        "The three round buttons at the top left of a window close it, minimize it into the Dock, "
        "and zoom it.",
        "Drag a window to the left or right edge to fill that half of the screen, "
        "or press Control+⌘ with an arrow key.",
        "- ⌘M minimizes the window.",
        "- Control+⌘F makes it full screen, on a desktop of its own; again to come back.",
        "- ⌘H hides the app and ⌥⌘H hides the others.",
        "- Control+Up shows every window; click one to bring it forward.",
        "Window > Fill and Window > Center in the menu bar work on the window in front.",
        "Window > Move & Resize puts the window in a half or a quarter of the screen. "
        "Return to Previous Size there puts it back as it was.",
        "Rest the pointer on the green button for a moment to choose the same places from pictures. "
        "Left & Right puts the window on the left and the one you used before it on the right.",
    ]),
    "screen-zoom": ("Zoom in on the screen", "zoom magnify enlarge screen bigger accessibility scroll see", [
        "Hold ⌘ and scroll up to zoom in on the part of the screen under the pointer. "
        "Scroll down to zoom out again.",
        "To zoom with ⌥ Option or Control instead, or to turn zooming off, open Dials > Accessibility.",
    ]),
    "desktops": ("Use more than one desktop", "desktop space workspace virtual swipe overview assign all desktops dock options", [
        "freemac starts with four desktops. Control+Left and Control+Right move between them, "
        "as a three-finger swipe does.",
        "To add a desktop or close one, use the row of desktops in Mission Control (Control+Up).",
        "To keep an app on every desktop, or on one, Control-click its icon in the Dock and choose "
        "Options, then All Desktops or This Desktop under Assign To. None puts it back.",
        "Control+Option+Down shows them all. Control+Shift with an arrow key takes the window in front "
        "to the next desktop.",
    ]),
    "mission-control": ("See every window and desktop with Mission Control", "mission control overview all windows "
                        "desktops spaces row top switch control up four finger swipe drag move window "
                        "add new close remove plus app expose exposé show all windows control down full screen empty", [
        "Press Control+Up, or swipe up with four fingers, to see every window on this desktop side by side. "
        "Click one to bring it forward.",
        "Your desktops are named along the top of the screen. Move the pointer up to them and they open out "
        "into small pictures of each desktop with its windows.",
        "Click a desktop to go straight to it.",
        "On a desktop with no windows, Control+Up opens the row of desktops on its own. Click one to go "
        "there, or press Esc or click away to close it.",
        "Press Control+Down, or swipe down with four fingers, for App Exposé: every window of the app "
        "you're using, from every desktop. Show All Windows in an app's Dock menu does the same for that app.",
        "To move a window to another desktop, drag it up onto that desktop and let go.",
        "To add a desktop, click + at the right end of the row. Drag a window onto + to give it a new "
        "desktop of its own.",
        "To close a desktop, point at it and click the round button on its corner. Its windows move to "
        "Desktop 1.",
        "A window in full screen has a desktop of its own, named after its app. Swipe or press "
        "Control+Left to go back to your other desktops; the button on its corner leaves full screen.",
    ]),
    "seek": ("Search with Seek", "seek search find spotlight calculate sum file convert conversion units "
             "miles kilometres celsius fahrenheit pounds kilograms cups", [
        "Press ⌘Space, or click the magnifying glass in the menu bar, type, and press Return to open the "
        "first result. The arrow keys move down the list.",
        "Seek finds apps, settings, the menu items of the app in front, files by their names "
        "and by the words inside them.",
        "Type a sum such as 12*7 to see the answer; Return copies it.",
        "Type an amount with its unit to convert it: 5 km shows it in miles, 70 f in Celsius. Add \u201cin\u201d "
        "and another unit for that one instead, as in 2 cups in ml or 6 ft in cm.",
    ]),
    "help": ("Find a menu item", "help menu item command search find", [
        "Click Help at the end of the menu bar and just type. The menu items that match show "
        "under the search field, with the menu they're in and their shortcut.",
        "Press Return to choose the first one; it does exactly what it does in its own menu.",
        "Guide topics that match are listed under them.",
    ]),
    "files": ("Find and organize files", "drawer files folder finder documents downloads trash copy rename many batch several numbers gallery view icons list columns", [
        "Drawer shows your files. Click it in the Dock.",
        "- ⌘1, ⌘2, ⌘3 and ⌘4 show icons, a list, columns or a gallery, where the file you chose shows large "
        "over a strip of the others.",
        "- Space shows a quick preview of the file you chose.",
        "- F2 renames, and Delete moves a file to the Trash.",
        "- Choose several files and press F2 (or right-click > Rename Items…) to rename them all at once: "
        "replace text in their names, add text, or give them one name with a number, such as Holiday 1, Holiday 2.",
        "- ⌘I shows a file's information, and ⌘T opens a tab.",
        "Click the Trash in the Dock to see it and empty it. In the Trash, Put Back returns a file to its folder.",
    ]),
    "screenshot": ("Take a screenshot", "screenshot screen picture capture record print lens toolbar timer delay options clipboard save to", [
        "- ⇧⌘3 takes a picture of the whole screen.",
        "- ⇧⌘4 lets you drag around part of it.",
        "- ⇧⌘5 opens the Screenshot toolbar: pick the whole screen, a window or part of it, or "
        "record the screen or part of it, then click Capture or Record (or press Return). Esc closes it.",
        "While a recording runs, press ⇧⌘5 again, or click the stop button in the menu bar, to stop it.",
        "The pictures go on the desktop and are copied, ready to paste. A small preview shows in the "
        "corner for a moment.",
        "In the toolbar, Options chooses where pictures go (Desktop, Documents, Pictures or just the "
        "clipboard), a 5 or 10 second timer, and whether the corner preview shows.",
    ]),
    "wifi": ("Join a Wi-Fi network", "wifi wi-fi wireless internet network password connect join menu bar "
             "signal turn off on known networks disconnect ip address router", [
        "Click the Wi-Fi icon in the menu bar. Networks you've joined are listed first, then the others, "
        "strongest first. A padlock means the network needs a password.",
        "Click a network to join it, and type its password when asked. freemac remembers it next time, "
        "and a wrong password isn't kept.",
        "Click the network you're on to see its IP address, router, signal and channel, or to disconnect.",
        "The switch at the top turns Wi-Fi off and on. Wi-Fi Settings… opens Dials > Network.",
    ]),
    "wifi-password": ("Find or share a Wi-Fi password", "wifi wi-fi password forgot share guest phone qr code scan known networks forget join automatically", [
        "Choose Dials > Network. Known Networks lists every Wi-Fi network this computer has joined.",
        "Click the ⋯ button next to a network and choose Show Password and Code. After an administrator's "
        "password you see the password, and a code a phone's camera can scan to join without typing it.",
        "Copy Password puts it on the clipboard instead, ready to paste. Clipboard history doesn't keep it.",
        "Turn off Join Automatically for a network you only want to join by hand, or choose Forget This "
        "Network to remove it and its password.",
    ]),
    "web-apps": ("Put a website in the Dock", "website web app dock add to dock pin facebook site shortcut icon own window app web apps delete remove badge unread count number messages notifications", [
        "Open the website in Web, then choose File > Add to Dock…. Web shows the site's own icon and name; "
        "change the name if you like, then click Add.",
        "The website is now in the Dock and in Applications. Click it and it opens in its own window, without "
        "Web's address bar or tabs, and its name shows in the menu bar like any other app.",
        "It keeps its own sign-in, so you stay logged in to it even after you sign out of the same site in Web.",
        "When the site has something new for you, such as unread messages, its Dock icon shows the number "
        "in a red badge. Turn badges off in Dials > Dock and Menu Bar.",
        "To delete it, right-click its icon in the Dock and choose Options > Delete Web App…. It leaves the "
        "Dock and Applications and its sign-in is forgotten. The website itself isn't changed.",
    ]),
    "passwords": ("See or change saved passwords", "passwords password keychain login logins saved website site web browser forgot copy autofill fill in reused strong suggest purser", [
        "When you log in to a website in Web, it offers to save the login. Next time it fills it in for you.",
        "Open Purser (Passwords) to see them. It asks for your login password first, and locks again "
        "after 5 minutes in the background.",
        "Choose a website, then Copy beside the user name or password. Edit changes a login; + adds one "
        "with a strong password ready to use.",
        "Security lists passwords you use on more than one website, or that are easy to guess. Change "
        "them on the website first, then in Purser.",
        "Wi-Fi lists the networks this computer has joined, with their passwords after an administrator's "
        "password.",
    ]),
    "hovertext": ("See the words under the pointer larger", "hover text larger bigger big text zoom read small words pointer magnify magnifier low vision see accessibility command hold", [
        "Open Dials, choose Accessibility, then turn on Hover Text.",
        "Hold Command and point at some words: they show large in a panel just above the pointer.",
        "Move the pointer to another line to read that one. Let go of Command and the panel goes.",
        "In Dials > Accessibility, choose Option or Control to hold instead, and the size of the text.",
        "Hover Text reads the words on the screen, so it works in every app. Nothing is saved.",
    ]),
    "livetext": ("Copy text from a picture", "live text copy text picture photo image screenshot scan scanned pdf words select ocr recognise recognize read worksheet sign frame", [
        "Open the picture or PDF in Frame. A moment later, if it holds words, a Live Text button shows in the "
        "bottom-right corner.",
        "Drag across the words to select them, then press Command-C to copy them. Double-click a word to "
        "select it, or click three times for the whole line.",
        "Command-A selects all the text. Right-click the text for Copy, Select All and Copy All Text.",
        "Click the Live Text button to see all the text the picture holds, lit up.",
        "Paste the words anywhere, such as a note, a mail or a search.",
    ]),
    "codes": ("Use verification codes for two-step sign-in", "verification code codes two-step two step two-factor 2fa mfa authenticator app otp totp six digit 6-digit qr setup key sign in login purser passwords", [
        "When a website offers two-step sign-in with an authenticator app, Purser can be that app.",
        "Open Purser, choose the website's login, then Set Up Verification Code.",
        "Leave the website's QR code on the screen and choose Scan QR Code. Or copy the setup key the "
        "website shows and paste it in.",
        "Purser shows the code now. Type it into the website to finish, then choose Set Up.",
        "From then on the login shows its code, which changes every 30 seconds, with Copy beside it. "
        "Codes lists every login that has one.",
        "Turn off two-step sign-in on the website before you remove a code, or you may be locked out.",
    ]),
    "appearance": ("Change the look", "dark light mode auto automatic sunset sunrise day night wallpaper dynamic theme accent colour color highlight purple pink green favourite background appearance", [
        "Choose Dials > Appearance for Light, Dark or Auto, and Dials > Wallpaper for the picture on the desktop. "
        "Auto is light while the sun is up and dark after it sets, where you are.",
        "Pick an Accent colour on the same page: blue, purple, pink, red, orange, yellow, green or graphite. "
        "Selections, switches and buttons in every app change to it at once.",
        "Each wallpaper has a day and a night version, and follows light and dark.",
        "Turn on Dynamic in Dials > Wallpaper and the picture follows the sun instead: "
        "day while it's high, golden as it sets, and night after dark.",
    ]),
    "sound": ("Change the volume or where sound plays", "sound volume mute speaker speakers headphones audio output "
              "input microphone mic level balance left right mono one ear hearing", [
        "Use the volume keys, or click the speaker in the menu bar and drag the slider. Click the small "
        "speaker beside the slider to mute or unmute.",
        "The same menu lists the outputs, such as speakers and headphones: click one to play through it.",
        "Dials > Sound has the Balance between left and right, and the input device with its volume and "
        "Input level, a row of lights that follow what the microphone hears.",
        "To hear everything in both ears, turn on Play stereo audio as mono in Dials > Accessibility.",
    ]),
    "storage": ("See what's using space and free some up", "storage disk space full free up clean up available capacity hard drive ssd large big files trash empty review", [
        "Choose Dials > Storage. The bar shows how much is used and how much is left, coloured by what fills it: "
        "apps, documents, pictures, music, movies, downloads, the Trash and the system.",
        "Click Empty Trash… to erase what's in the Trash for good, or turn on Empty Trash Automatically to erase "
        "items after 30 days.",
        "Click Review Files… to see the biggest files in your home folder. Select one and click Move to Trash, "
        "or Show in Drawer to see where it is.",
        "Under What's Using Space, click Show to open that folder in Drawer, or Manage… beside Applications to "
        "remove apps in Harbor.",
    ]),
    "install": ("Install apps", "install app store harbor download update software", [
        "Harbor lists free apps. Click Install beside one; it shows in the Dock and in F4 when it's ready.",
        "Harbor also installs updates for freemac itself. A red number on its Dock icon says how many are ready.",
        "Apps from the Mac App Store don't run on freemac.",
    ]),
    "lock": ("Lock, restart or shut down", "lock shut down restart reboot log out power off", [
        "Control+⌘Q locks the screen. Type your password to come back.",
        "The freemac menu at the left end of the menu bar has Lock Screen, Restart, Shut Down and Log Out.",
    ]),
    "lock-screen": ("What the lock screen shows", "lock screen locked now playing music notifications battery message "
                    "if found lost previews", [
        "While music plays, the lock screen shows the song with buttons to go back, pause and skip.",
        "Notifications that come in while the computer is locked show under the clock. Dials > Notifications > "
        "Show previews chooses what they say there: Always shows the words; When Unlocked and Never show only "
        "which app sent one.",
        "A computer with a battery shows how charged it is in the top right corner.",
        "To show a message under the password field, such as how to return the computer if it's lost, turn on "
        "Show message when locked in Dials > Power (Battery on a laptop) and type it in.",
    ]),
    "switch-user": ("Switch to another person without logging out", "fast user switching switch user family "
                    "kids accounts login window another person logged in", [
        "When the computer has more than one account, your name shows in the menu bar. Click it and choose "
        "someone: your apps stay open behind your lock screen while they use the computer.",
        "If they're already logged in, their own screen comes back, locked, for their password. If not, the "
        "login screen opens with them chosen.",
        "Login Window… opens the login screen to choose anyone. People already logged in have a dot by their "
        "name there; choose one and click the arrow to go back to their session.",
        "To come back, choose your name in their menu bar (or the login screen) and type your password.",
        "Dials > Users adds accounts. Turn off Show fast user switching menu there to hide your name.",
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
        "To make a note from words in another app, select them and press ⇧⌘Y.",
    ]),
    "encryption": ("Keep your disk private with encryption", "encrypt encryption encrypted disk filevault "
                   "recovery key lost stolen password start-up unlock privacy security protect", [
        "With encryption, everything on the disk is scrambled until your password is typed, so nobody can "
        "read your files if the computer is lost or stolen, even by taking the disk out.",
        "Encryption is turned on when you install freemac: on the “Encrypt your disk?” step, turn on "
        "Encrypt the disk. Each time the computer starts, type your password on the start-up screen.",
        "When installing finishes, freemac shows a recovery key. Write it down and keep it away from the "
        "computer. If you forget your password, type the recovery key on the start-up screen instead.",
        "- To see whether your disk is encrypted, choose Dials > Privacy & Security.",
        "- Change Disk Password… changes the password typed at start-up. Changing your own login "
        "password in Dials > Users changes it too, when the two were the same.",
        "- New Recovery Key… makes a new key; the old one stops working.",
        "Without your password or the recovery key, nobody can unlock the disk, not even freemac.",
    ]),
    "vpn": ("Connect to a VPN", "vpn virtual private network wireguard openvpn ovpn conf work office "
            "provider tunnel secure connection menu bar", [
        "A VPN sends your internet traffic through another network, such as your workplace's or a VPN "
        "provider's. They give you a file to set it up: a WireGuard file (ending .conf) or an OpenVPN file "
        "(ending .ovpn).",
        "- Choose Dials > Network, click Add VPN Configuration… and choose the file.",
        "- Turn the VPN's switch on to connect, and off to disconnect.",
        "- While you have a VPN, a VPN icon in the menu bar shows whether it's connected; click it to "
        "connect or disconnect. Show VPN status in menu bar in Dials > Network hides it.",
        "A new VPN waits for you to turn it on. Once added, the file it came from can be deleted.",
    ]),
    "services": ("Use selected words in another app", "services service selected text selection sticky note look up "
                 "define dictionary words search seek jot speak read aloud open url link show in drawer terminal "
                 "folder desktop picture wallpaper shift command y", [
        "Services do small jobs with what you've selected, using another app. Select some words in any app, "
        "then click the app's name in the menu bar and choose Services.",
        "- Make New Sticky Note (⇧⌘Y) puts the words on a new sticky note.",
        "- New Jot Note With Selection starts a Jot note with them.",
        "- Look Up in Words shows a word's meaning, and Search With Seek searches for the words.",
        "- Speak Text reads them aloud. Open URL opens a web address, and Show in Drawer shows a file "
        "whose path you selected.",
        "Only the services that fit what's selected can be chosen. In Drawer, right-click a folder for "
        "New Terminal at Folder, or a picture for Set Desktop Picture.",
        "To give a service its own keys, or take one off the menu, choose Dials > Keyboard and look under Services.",
    ]),
    "voice": ("Record your voice", "voice memo record recorder microphone audio echo trim", [
        "Echo records your voice. Press ⌘Space, type Echo and press Return.",
        "Click the big red button to start recording, and Done when you've finished. "
        "Your recording appears at the top of the list.",
        "Press Space to play it. Click the waveform to jump to a part, or skip back and forward 15 seconds.",
        "Click the recording's name to rename it. Click Trim and drag the yellow handles to keep only the "
        "part you want.",
        "Recordings are kept in the Echo folder in Music. If Echo can't hear you, plug in a microphone "
        "or choose one in Dials > Sound.",
    ]),
    "drawing": ("Draw a picture", "draw drawing paint sketch doodle pen easel art sticker", [
        "Easel is for drawing. Press ⌘Space, type Easel and press Return.",
        "Pick a pen, the highlighter or a shape at the top, then a colour and a size, and draw. "
        "Hold Shift while you draw a shape for a perfect square, circle or straight line.",
        "Click the smiley for stickers, or the A to type words. The eraser rubs out whatever it goes over.",
        "Click the arrow to pick up something you drew and move it. Press Delete to throw it away. "
        "⌘Z undoes your last change.",
        "Your drawings are kept as you go and listed on the left. Click Export to save one as a picture "
        "you can share.",
    ]),
    "chess": ("Play chess", "chess game play board checkmate rook computer friend", [
        "Rook plays chess. Press ⌘Space, type Rook and press Return.",
        "Click a piece to see where it can go, then click where you want it, or drag it there.",
        "Click New Game to play the computer on Easy, Medium or Hard, or a friend on the same screen.",
        "Stuck? Click Hint for a good move. The undo arrow takes your last move back.",
        "Your game is kept, so you can stop and carry on later.",
    ]),
    "patience": ("Play Patience (solitaire)", "solitaire patience cards card game klondike", [
        "Patience is the classic card game. Press ⌘Space, type Patience and press Return.",
        "Build each suit from Ace to King at the top right. On the seven columns, put cards in falling "
        "order, red on black and black on red. Only a King goes in an empty column.",
        "Click the deck to turn cards over. Drag a card to move it, or double-click it to send it home.",
        "Stuck? Click Hint. ⌘Z undoes a move. Once every card is face up, click Finish.",
    ]),
    "mines": ("Play Mines", "mines minesweeper puzzle game flag", [
        "Mines is a puzzle game. Press ⌘Space, type Mines and press Return.",
        "Click a square to open it. A number tells how many squares around it hide a mine. "
        "The first click is always safe.",
        "Right-click, or hold Control and click, to flag a square you think hides a mine. Click a number "
        "whose mines are all flagged to open everything around it.",
        "Pick Small, Medium or Large at the top. Your best time for each is kept.",
    ]),
    "books": ("Read e-books", "books ebook epub read reader library novel kindle", [
        "Books reads EPUB e-books. Press ⌘Space, type Books and press Return.",
        "Click Add Books to bring books in, or put EPUB files in the Books folder in your home. "
        "Many free classics are on Project Gutenberg.",
        "Click a book to read it. Click the right side of the page or press → for the next page.",
        "Click the list button for the contents, and Aa for bigger text or sepia and night pages. "
        "Books keeps your place in every book.",
    ]),
    "piano": ("Play the piano", "piano ivory music keyboard instrument organ notes play record tune", [
        "Ivory is a piano. Press ⌘Space, type Ivory and press Return.",
        "Click the keys, or play on the computer's keyboard: the bottom row of letters plays the lower notes "
        "and the top row plays the higher ones. The letters are shown on the keys.",
        "Choose another sound, like organ, music box or flute, from the menu at the top left. "
        "The arrows move the keyboard higher or lower.",
        "Click Record, play a tune, then click Stop. Click Play to hear it again.",
    ]),
    "dictionary": ("Look up a word", "dictionary words define definition meaning synonym thesaurus spelling", [
        "Words is a dictionary that works without the internet. Press ⌘Space, type Words and press Return.",
        "Type a word in the search box at the top and press Return. Words finds a word from its other forms "
        "too, so ran finds run.",
        "Click any blue word, like one that means the same, to look that up. The arrows go back and forward.",
        "Words shows a new word of the day each time you open it.",
    ]),
    "typing": ("Learn to type", "typing typist keyboard lessons practice touch type speed", [
        "Typist teaches typing without looking at the keys. Press ⌘Space, type Typist and press Return.",
        "Start with lesson 1. Rest your fingers on the middle row of keys and type the letters you see. "
        "The keyboard on the screen lights up the next key in the colour of the finger to use.",
        "A wrong key turns red, and you can carry on once you type the right one.",
        "At the end of a lesson you see your speed and accuracy and earn up to three stars. "
        "Press Return for the next lesson.",
    ]),
    "screentime": ("See your screen time and set limits", "screen time logbook usage hours limit parental controls kids child family parent manage apps time downtime bedtime always allowed more minutes category categories games social schedule weekend custom "
                   "adult websites content filter block sites family safe", [
        "Logbook shows how long each app was used. Press ⌘Space, type Logbook and press Return.",
        "Today shows each hour of the day, and Last 7 Days shows each day of the week, with the apps used most "
        "at the top. Time only counts while someone is using the computer, not while it's locked or left alone.",
        "To limit an app, click Set Limit beside it and choose how long it may be used each day. Five minutes "
        "before the time is up a notice says so, and at the limit its windows close until the next day.",
        "When an app's time is up, click Time's Up beside it and choose 15 More Minutes to give it a little "
        "longer today.",
        "Turn on Downtime and choose the hours, such as 9:00 PM to 7:00 AM, for time away from the screen. "
        "Only the apps under Always Allowed, and Drawer, Dials and Guide, can be used then. A notice comes "
        "five minutes before it starts, and 15 More Minutes holds it off for a while.",
        "To give each day its own downtime, such as later on Fridays and none on Saturdays, choose Custom "
        "instead of Every Day and set the hours beside each day. Untick a day to have no downtime that day.",
        "Categories adds up the time for each kind of app, such as Games or Social. To limit them all together, "
        "click Set Limit beside the category, or Add Category Limit… for one not used yet. At the limit, every "
        "app of that kind closes for the rest of the day.",
        "Click + under Always Allowed to add an app that should always work, such as Jot for homework. "
        "Always Allowed apps have no daily limit either.",
        "Choose Limits ▸ Passcode… to set a passcode, so that only someone who knows it can change a limit, "
        "downtime or Always Allowed, or give more time.",
        "Turn on Limit adult websites, under Content, to keep websites for grown-ups from opening in any browser "
        "on the computer. It needs an administrator's password, and the passcode if there is one.",
        "For a child with their own account, a parent opens Logbook in their own account, clicks Me at the top "
        "and picks the child, then clicks Manage Screen Time and enters their password. Limits, Downtime and "
        "Always Allowed set there apply to the child, who can see them but not change them.",
        "When the child's time is up, they click More Time… in their Logbook, and a parent types their password "
        "on that screen to give 15 more minutes. Stop Managing… gives the child their own settings back.",
    ]),
    "sudoku": ("Play a number puzzle", "sudoku nine number puzzle game logic grid", [
        "Nine is a number puzzle. Press ⌘Space, type Nine and press Return.",
        "Fill the grid so that every row, every column and every 3 × 3 box has each number from 1 to 9 once. "
        "Click a square, then click a number at the bottom or type it.",
        "Turn on the pencil (or press P) to jot small numbers you think might fit. Hold Shift while typing a "
        "number to do the same.",
        "Choose Easy to Expert at the top. Hint fills in one square, and ⌘Z undoes a move.",
    ]),
    "fonts": ("See and add fonts", "fonts font book typecase typeface install font add font letters", [
        "Typecase shows every font on the computer. Press ⌘Space, type Typecase and press Return.",
        "Click a font to see all of its styles. Type in the box at the top to see your own words in it, and "
        "drag the slider to make it bigger or smaller.",
        "To add a font, double-click its file and click Install Font, or click + in Typecase and choose the files. "
        "Every app can use it after that.",
        "Fonts you added are under My Fonts. To take one away, choose it and click Remove Font.",
    ]),
    "memory-game": ("Play the memory game", "memory game pairs match matching cards concentration kids two players", [
        "Pairs is a memory game. Press ⌘Space, type Pairs and press Return.",
        "Click a card to turn it over, then click another. If the pictures match, they stay up. If not, they "
        "turn back over, so try to remember where they were.",
        "Choose the size and the pictures at the top. With 2 Players, you take turns, and finding a pair "
        "gives you another go.",
    ]),
    "graphs": ("Draw a graph of an equation", "graph graphing plot equation function curve math maths calculator", [
        "Plot draws equations. Press ⌘Space, type Plot and press Return.",
        "Type an equation in a box on the left, such as y = x^2 - 3 or sin(x). Use ^ for powers, and you can "
        "write 2x for 2 times x. Click Add Equation for another one in a new colour.",
        "Drag the graph to move it and scroll to zoom. Point at a curve to read its value there.",
        "Put the letter a in an equation, such as a·x^2, and drag the slider for a to watch the curve change.",
    ]),
    "whiteboard": ("Plan ideas on a board", "whiteboard board corkboard sticky notes ideas brainstorm plan pictures", [
        "Corkboard is a big board for notes and pictures. Press ⌘Space, type Corkboard and press Return.",
        "Click Note, Text, Shape or Picture at the top, or double-click anywhere on the board for a note. "
        "Double-click a note or shape to write in it.",
        "Drag things to move them, and drag the small square at the corner to make them bigger. Choose a "
        "colour with the round button at the top.",
        "Drag empty space to move around the board, and hold ⌘ while you scroll to zoom. Click New Board "
        "for another board.",
    ]),
    "jigsaw": ("Do a jigsaw puzzle", "jigsaw puzzle pieces picture photo kids game", [
        "Jigsaw cuts a picture into puzzle pieces. Press ⌘Space, type Jigsaw and press Return.",
        "Click New Puzzle… to pick a picture, or Choose a Photo… to use one of yours, and pick how many pieces.",
        "Drag pieces onto the board. Pieces that fit click together, and pieces in the right place lock into "
        "the frame.",
        "Click Peek to see the whole picture faintly behind the board, and Spread Out to tidy loose pieces.",
    ]),
    "about-computer": ("See what's inside this computer", "about this computer system information specs hardware "
                       "processor memory storage graphics usb version report", [
        "Click the freemac menu at the left of the menu bar and choose About freemac.",
        "You'll see the processor, graphics, memory, free space and the version of freemac.",
        "Click More Info… for the full report: disks, displays, USB devices, network, sound and battery. "
        "Click Copy to copy it, for example to send to someone helping you.",
    ]),
    "pick-colour": ("Pick a colour from the screen", "colour color picker eyedropper hex rgb hsl swatch palette", [
        "Swatch picks colours. Press ⌘Space, type Swatch and press Return.",
        "Click Pick from Screen, then click anywhere. The loupe shows the pixels under the pointer.",
        "Click the copy button next to Hex, RGB or HSL to copy that value. Click Add to Palette to keep the "
        "colour for later.",
    ]),
    "tangram": ("Make shapes with Tangram", "tangram shape puzzle pieces triangle kids game", [
        "Tangram has seven flat pieces to make a shape. Press ⌘Space, type Tangram and press Return.",
        "Pick a shape from the menu at the top. Drag pieces onto the grey outline to fill it.",
        "Click a piece to turn it. Right-click the parallelogram to flip it over.",
        "Click Hint to see where one piece goes.",
    ]),
    "podcasts": ("Listen to podcasts and follow news feeds", "podcast feed rss atom news subscribe episode buoy listen", [
        "Buoy follows podcasts and websites. Press ⌘Space, type Buoy and press Return.",
        "Click the + button (or press ⌘N) and type the address of a podcast's feed, or of a website that has a feed.",
        "New posts and episodes show with a blue dot. Click one to read it, and click Play to listen.",
        "Buoy keeps your place in every episode. Change the speed with the button at the right of the player.",
        "To move your podcasts from another app, export them there as OPML and choose File > Import Subscriptions.",
    ]),
    "word-search": ("Play a word search", "word search hunt puzzle letters grid kids game", [
        "Hunt hides words in a grid of letters. Press ⌘Space, type Hunt and press Return.",
        "Drag from the first letter of a word to its last, or click one and then the other.",
        "Pick a theme from the menu at the top, and Small, Medium or Large. Larger grids hide words on "
        "slants and backwards.",
        "Click Hint to see the first letter of a word you haven't found.",
    ]),
    "four-in-a-row": ("Play four in a row", "four in a row connect counters fourway board game kids", [
        "Fourway is four in a row. Press ⌘Space, type Fourway and press Return.",
        "Click a column to drop a counter. Line up four of yours across, down or on a slant to win.",
        "Choose Computer or Friend at the top. Against the computer, pick Easy, Medium or Hard.",
        "Press ⌘Z to take back a move.",
    ]),
    "draughts": ("Play draughts (checkers)", "draughts checkers kings board game crown jump", [
        "Kings is draughts, also called checkers. Press ⌘Space, type Kings and press Return.",
        "Click one of your pieces, then one of the marked squares to move it there.",
        "Taking is compulsory: when one of your pieces can jump, it's ringed and has to. A piece that "
        "reaches the far side becomes a king and can move backwards too.",
        "Choose Computer or Friend at the top, and press ⌘Z to take back a move.",
    ]),
    "tile-matching": ("Play tile matching", "tile matching solitaire cairn pairs stack pictures", [
        "Cairn is a tile-matching game. Press ⌘Space, type Cairn and press Return.",
        "Click two free tiles with the same picture to take them away. A tile is free when nothing is "
        "on top of it and its left or right side is open. Blocked tiles are shaded.",
        "Pick a layout from the menu at the top. Pyramid is the easiest.",
        "Click Hint to see a pair you can take, Shuffle to mix the tiles that are left, or ⌘Z to put a "
        "pair back. Every game can be cleared.",
    ]),
    "maths-practice": ("Practise maths", "maths math sums adding times tables multiply divide sharing kids", [
        "Sums is maths practice. Press ⌘Space, type Sums and press Return.",
        "Pick Adding, Taking Away, Times Tables or Sharing, then a level. A round has ten questions.",
        "Type the answer and press Return. A wrong answer gets one more try, then Sums shows the right one.",
        "Get stars for answers right first time. Click Times Tables at the top to see every times table, "
        "and click a number along the top of the chart to practise just that table.",
    ]),
    "flashcards": ("Study with flashcards", "flashcards cards study revise learn spelling cue deck", [
        "Cue makes flashcards. Press ⌘Space, type Cue and press Return.",
        "Click + to make a deck, then type a question and its answer and click Add Card.",
        "Click Study. Press Space to turn a card over, then Knew It or Didn't Know It. Cards you didn't "
        "know come back sooner, and ones you know well wait longer.",
        "To bring in cards from a spreadsheet, save it as CSV and choose File > Import Cards.",
    ]),
    "scanning": ("Scan a document or photo", "scan scanner scanning document photo printer all-in-one pdf glass", [
        "Glass scans with a scanner or an all-in-one printer, plugged in or on your network. Press ⌘Space, "
        "type Glass and press Return.",
        "Put the page face down on the glass and click Preview. To scan only part of it, drag over the "
        "preview.",
        "Choose Colour or Grey and a resolution, then click Scan. Each scan becomes a page along the bottom.",
        "Click Save to keep the pages as one PDF or as pictures. They go to your Documents folder unless "
        "you choose another.",
    ]),
    "spreadsheet": ("Make a spreadsheet", "spreadsheet table numbers sum formula csv chart budget ledger grades", [
        "Ledger makes spreadsheets. Press ⌘Space, type Ledger and press Return.",
        "Click a cell and type a number or words, then press Return. To work something out, start with =, "
        "for example =SUM(B2:B6) or =AVERAGE(B2:D2). While typing a formula you can click cells to put them in.",
        "Select cells and click Sum to add them up, Chart to draw them, or Sort to put the rows in order. "
        "The total, average and count of the selected cells show along the bottom.",
        "⌘D copies a cell down the selection, changing its formula to fit each row. Ledger opens and saves "
        "CSV files as well as its own.",
    ]),
    "presentation": ("Make a presentation", "presentation slides slideshow lantern talk project school pdf", [
        "Lantern makes slideshows. Press ⌘Space, type Lantern and press Return.",
        "Type the slide's title and its points on the right, one point on each line. Choose… adds a picture.",
        "Click Add Slide for the next slide, and Theme to change the colours of them all.",
        "Click Play to show the slides full screen. Press the right arrow or Space for the next slide and Esc "
        "to stop. File > Export as PDF makes a copy to print or hand in.",
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
        "Nearby\u2026 sends them over Wi-Fi to a computer or phone in the same room.",
        "Mail opens a new message in Post with the files attached. Type who it's to and click Send.",
        "Copy to puts a copy on a USB drive or memory card that's plugged in. If the drive already has a file "
        "with that name, the copy is called “name 2”, so nothing is replaced.",
        "When the copy is done, Drawer's status line or a notification says so. "
        "Eject the drive before you unplug it.",
    ]),
    "input-sources": ("Type in another language or keyboard layout", "input sources keyboard layout language type british french german spanish dvorak colemak control space input menu key repeat", [
        "Choose Dials > Keyboard and click Add Input Source\u2026 under Input Sources. Type a language or "
        "layout, such as British or German, pick it and click Add. You can have up to four.",
        "With more than one, the menu bar shows the one you're typing with (US, GB, DE). Click it to "
        "choose another, or press Control-Space to go to the next. Click \u2212 beside one to take it off.",
        "Key repeat rate and Delay until repeat, on the same page, set how fast a held key repeats.",
    ]),
    "spelling": ("Check your spelling as you type", "spelling spell check checker misspelled typo dictionary correct underline red learn word ignore", [
        "In Jot, Post, Stickies, Quill and the notes fields of other apps, a misspelled word gets a red "
        "underline. Right-click it to pick the right spelling, Ignore All, or Add to Dictionary so it's "
        "never underlined again.",
        "The same right-click menu has Languages, to check in British, Canadian or Australian English "
        "instead. Quill checks plain text and Markdown, not code.",
        "To turn it off everywhere, choose Dials > Keyboard and turn off Check spelling while typing.",
    ]),
    "text-replacements": ("Type less with text replacements", "text replacements replace abbreviation shortcut expand omw snippet smart quotes curly dash em dash double space full stop period", [
        "Type omw and a space in Jot, Post, Stickies or Quill, and it becomes On my way! To add your own, "
        "choose Dials > Keyboard > Text Replacements\u2026, click + and type what you'll type and what it "
        "should become.",
        "As you type, straight quotes become curly ones (\u201clike this\u201d), two hyphens become a dash (\u2014), "
        "and pressing the space bar twice ends a sentence with a full stop. Each can be turned off on the "
        "same page.",
    ]),
    "servers": ("Open a shared folder on another computer", "connect to server network neighbourhood browse computers nearby shared folder smb windows share nas sftp ftp webdav file server mount drive", [
        "In Drawer, choose Go > Connect to Server\u2026 (\u2318K). Type the address, such as "
        "smb://office-pc/Photos, or just the computer's name for a Windows or Mac shared folder, and click "
        "Connect. If it asks, type the name and password you use on that computer.",
        "The folder opens like a drive and shows under Locations in the sidebar; click its Eject button when "
        "you're done. Click + to keep an address in Favourite Servers for next time.",
        "Or click Network under Locations (Go > Network, \u21e7\u2318K) to see the computers and shared "
        "drives nearby, and double-click one to open it. A computer that shares several folders shows "
        "them; double-click the one you want.",
    ]),
    "filesharing": ("Share a folder with the other computers at home", "file sharing share folder public network windows mac computers family smb samba guest read only kids pc", [
        "Choose Dials > Sharing and turn on File Sharing; you're asked for an administrator's password. "
        "Put whatever you want to share in the Public folder in your home folder (Open Public Folder "
        "takes you there).",
        "On another freemac or a Mac, it shows in Network under this computer's name. On Windows, type "
        "two backslashes, the computer's name and \\Public in File Explorer's address bar. No password is "
        "needed; they can open and copy what's there, but can't change or delete anything.",
        "Turn File Sharing off when you don't need it.",
    ]),
    "screensharing": ("See and use another computer's screen", "screen sharing remote desktop vnc porthole help someone another computer see screen control family kids", [
        "On the computer you want to see: choose Dials > Sharing and turn on Screen Sharing; you're "
        "asked for an administrator's password. Your account needs a password of its own (set one in "
        "Dials > Users).",
        "On the other computer, open Porthole and type the first computer's name, then sign in with "
        "that computer's name and password. You see its screen and can use its mouse and keyboard. "
        "Porthole remembers recent computers, and View has Fit to Window and full screen.",
        "While someone is using your screen, an icon in the menu bar shows who; click it and choose "
        "Disconnect to end it. Porthole also connects to a Mac with Screen Sharing on, or any other "
        "VNC computer.",
    ]),
    "sharing": ("Rename this computer, or log in to it from another", "sharing computer name rename hostname local network remote login ssh terminal another computer", [
        "Choose Dials > Sharing. Type a new Computer name and press Return; you're asked for an "
        "administrator's password. Nearby devices and printers see the new name, and other computers "
        "on your network can reach this one at the name shown underneath, ending in .local.",
        "Remote Login lets someone at another computer on the same network use this one's Terminal: "
        "they type ssh, your user name, @ and the computer's .local name, then your password. "
        "It's off unless you turn it on; turn it off again when you're done.",
    ]),
    "nearby": ("Send files to a computer or phone nearby", "nearby airdrop send share phone iphone android tablet wifi wireless localsend transfer receive photos", [
        "In Drawer, Cove or Frame, select what you want to send, click the Share button and choose "
        "Nearby\u2026. Computers and phones on the same Wi-Fi appear as round icons; click one to send.",
        "The other device asks its owner first. Its icon then says Waiting, Sending and Sent, or Declined. "
        "Click it while it's sending to stop.",
        "To let others send to you, turn on Let nearby devices send files here, at the bottom of the "
        "Nearby window or in Dials > Network or Sharing. Each time, you're asked whether to accept, and accepted "
        "files go in Downloads.",
        "Phones, tablets and Windows computers need the free LocalSend app. Other freemac computers "
        "already have it built in.",
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
        "The song playing shows under the music note in the menu bar, with its buttons, and the media keys "
        "on your keyboard work even when Shanty is behind other windows.",
    ]),
    "videos": ("Watch a video", "video movie film play watch mp4 mov quicktime player reel full screen", [
        "Reel plays videos. Double-click a video in Drawer. Or press ⌘Space, type Reel, and double-click "
        "one of the videos in your Videos folder.",
        "Move the pointer to show the controls; they fade while the video plays.",
        "- Space plays and pauses. ← and → go back or forward 10 seconds.",
        "- F, or the button at the right of the controls, fills the screen. Esc goes back.",
        "- ↑ and ↓ turn the sound up and down.",
        "- P, or the button beside full screen, puts the video in a small window that stays above the "
        "others while you work (Picture in Picture).",
        "Close a video partway through and Reel starts it again where you stopped next time.",
    ]),
    "picture-in-picture": ("Watch a video while you work", "picture in picture pip small window float on top corner video movie reel keep watching", [
        "In Reel, press P, or click the Picture in Picture button beside the full-screen button. The "
        "video shrinks into a small window in the bottom right corner, above all your other windows, "
        "and keeps playing.",
        "Drag the video to move it anywhere on the screen. Point at it to show its buttons: play or pause, "
        "and back to the window.",
        "Double-click the video or press Esc to put it back where it was, at its old size.",
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
        "Once a drive is chosen, a lifebuoy sits in the menu bar. Click it to see when the latest backup was "
        "made, to back up now or skip the backup that's running, or to browse your backups. The lifebuoy "
        "turns while a backup runs.",
    ]),
    "date-time": ("Set the date, time and time zone", "date time clock time zone timezone city 24-hour 12-hour seconds automatic wrong time travel", [
        "Choose Dials > Date & Time.",
        "Turn on Set the time automatically to keep the clock right from the internet. Turn it off to set the date and time yourself with Set….",
        "To change the time zone, click the box under Time zone, type a city and pick it from the list.",
        "Choose 12-hour or 24-hour time, and whether the menu bar shows the day, the date and seconds.",
        "Changing the time or time zone asks for an administrator's password.",
    ]),
    "dock-hide": ("Hide the Dock until you need it", "dock hide hides automatically autohide auto-hide show more room bottom screen magnification recent files recent apps right-click menu position left right side move edge badge badges red number count unread bounce bouncing bounces attention needs you", [
        "Choose Dials > Dock and Menu Bar and turn on Automatically hide and show the Dock, or press ⌥⌘D.",
        "The Dock slides away and windows can use the whole screen. Move the pointer to the bottom "
        "edge of the screen and it slides back up.",
        "It stays up while the pointer is on it or one of its menus is open, and hides again when you move away.",
        "Press ⌥⌘D again to keep it on screen all the time.",
        "You can also right-click the Dock between its icons, or on the line before the Trash, and choose "
        "Turn Hiding On or Turn Hiding Off. The same menu turns magnification on or off and opens Dock Settings.",
        "Right-click an app in the Dock to see the files it had open lately, and click one to open it again.",
        "Up to three apps you used lately stay in the Dock after they quit, after the line by the open apps. "
        "To take one off, drag it out of the Dock or choose Options > Remove from Dock. To keep it, choose "
        "Options > Keep in Dock. Turn this off in Dials > Dock and Menu Bar with Show recent apps in Dock.",
        "A red number on an app's icon says something is waiting there: unread mail on Post, or reminders "
        "due today on Nudge. Other apps that send a count, or a download's progress, show it the same way.",
        "The same page turns off the dots under open apps (Show indicators for open apps), the red numbers "
        "(Show badges on Dock icons) and the bounce while an app opens (Animate opening apps).",
        "When an app in the background needs you, its icon keeps bouncing in the Dock until you go to it. "
        "Click the icon, or switch to the app, and it stops.",
        "To put the Dock on the left or right of the screen, choose Position on screen in Dials > Dock and "
        "Menu Bar, or right-click the Dock between its icons and choose Position on Screen. A Dock that hides "
        "itself comes back when the pointer reaches that edge.",
    ]),
    "stage-manager": ("Keep one app in front with Stage Manager", "stage manager windows apps strip side left recent switch focus tidy clutter one app quick settings", [
        "Click the quick settings icon in the menu bar and click Stage Manager, or turn it on in Dials > Dock and Menu Bar.",
        "The app you're using stays in the middle of the screen. The apps you used just before it wait as "
        "small pictures down the left side, newest at the top.",
        "Click a picture to bring that app forward; the one you were using takes its place in the strip. "
        "Clicking an app in the Dock, or switching with ⌘Tab, does the same.",
        "A window moved or zoomed over the strip covers it. Windows you hid or minimized yourself stay as they are.",
        "Turn Stage Manager off the same way, and every window comes back where it was.",
    ]),
    "menubar-hide": ("Hide the menu bar until you need it", "menu bar hide hides automatically autohide auto-hide top screen more room topline", [
        "Choose Dials > Dock and Menu Bar and turn on Automatically hide and show the menu bar.",
        "The menu bar slides away and windows can use the top of the screen too. Move the pointer to the "
        "top edge of the screen and it slides back down.",
        "It stays while the pointer is on it or one of its menus is open, and hides again when you move away.",
    ]),
    "reveal-desktop": ("Click the wallpaper to see the desktop", "reveal desktop show desktop click wallpaper windows aside hide all windows", [
        "Choose Dials > Dock and Menu Bar and turn on Click wallpaper to reveal desktop.",
        "Now a click on the desktop picture puts the windows on the screen out of the way, so you can get to "
        "the files on the desktop. Click the desktop picture again to bring them back.",
        "Clicking an app in the Dock brings that app's windows back too.",
    ]),
    "login-items": ("Open apps when you log in", "login items open at login startup start up launch automatically autostart", [
        "Choose Dials > Login Items. The apps listed there open by themselves each time you log in.",
        "Click + to choose an app to add, and \u2212 beside an app to stop it opening.",
        "You can also right-click an app in the Dock and choose Options > Open at Login.",
    ]),
    "guest-user": ("Let someone use the computer as a guest", "guest user visitor guest account no password borrow share computer friend erase log in", [
        "Choose Dials > Users and turn on Guest User. You'll be asked for an administrator's password.",
        "Guest User then shows on the login screen. A guest just clicks the arrow; no password is needed.",
        "Nothing a guest does is kept: their files and settings are erased when they log out. Your own files "
        "stay private.",
        "Turn the switch off to remove the Guest User again.",
    ]),
    "alert-sound": ("Change the alert sound", "alert sound beep sound effects error noise volume feedback pop trash screenshot shutter quiet", [
        "Choose Dials > Sound. Under Sound Effects, pick an Alert sound; you hear each one as you pick it.",
        "The alert sound plays when something can\u2019t be done, like pressing Delete with nothing to delete. "
        "Alert volume sets how loud it is, apart from everything else.",
        "Turn off Play feedback when volume is changed to stop the little pop, or Play user interface sound "
        "effects to stop the Trash and screenshot sounds.",
    ]),
    "displays": ("Change your display's resolution or use two displays", "display monitor screen resolution refresh rate hz rotate rotation turn sideways portrait second display two displays external projector tv arrange mirror mirroring extend extended main display menu bar dock bigger text icons scale", [
        "Choose Dials > Displays. Pick a Resolution, a Refresh rate, the Size of text and icons, or a Rotation for each display.",
        "After a new resolution, refresh rate, rotation or mirroring, freemac asks \u201cKeep these display settings?\u201d "
        "If you don\u2019t click Keep within 15 seconds, the old settings come back, so a screen that goes blank fixes itself.",
        "With two or more displays, drag them in the picture to match how they sit on your desk; the pointer crosses where they touch. "
        "Use as \u201cMirror for\u201d another display to show the same thing on both, as for a projector.",
        "The main display has the menu bar, the Dock and the files on the Desktop. To pick another, drag the white bar "
        "in the picture onto it, or choose Use as \u201cMain display\u201d.",
    ]),
    "shut-down": ("Restart, shut down or log out", "restart shut down shutdown turn off power off log out logout sign out sleep recent items recently used apps documents", [
        "Click the freemac mark at the left of the menu bar and choose Sleep, Restart\u2026, Shut Down\u2026 or "
        "Log Out. Shift-Command-Q logs out too.",
        "freemac asks first. If nobody answers, it goes ahead by itself after 60 seconds.",
        "Each open app is then asked to quit, so you can save your work. If an app stays open, freemac "
        "stops and tells you which one.",
        "Recent Items in the same menu lists the apps and documents you used lately. Clear Menu empties it.",
    ]),
    "stay-safe": ("Keep the computer up to date and safe", "software update updates security fixes automatic notice badge daily firewall block incoming connections protect safe virus new version freemac upgrade restart now what's new undo", [
        "Choose Dials > Software Update. When a new version of freemac is out, it's at the top with what's "
        "new in it. Click Update Now and type an administrator's password: it downloads while you carry on.",
        "Then click Restart Now. freemac installs while the computer restarts, and a notice says once it's in. "
        "If the new version stops something working, Undo Last Update in freemac Recovery puts the old one back.",
        "Updates for apps and the rest of the system are below: Check for Updates\u2026 shows them in Harbor, "
        "where you install them.",
        "freemac also looks once a day. When updates are ready, a notice says so and Harbor's icon in the Dock "
        "shows how many. Click the notice to see them.",
        "Leave Install important updates automatically on, and security fixes are put in by themselves in "
        "the background.",
        "To turn away connections that other computers try to start, choose Dials > Network and turn on Firewall. "
        "Browsing, mail and printing carry on as usual.",
        "Both switches ask for an administrator's password.",
    ]),
    "default-apps": ("Choose which app opens a file or link", "default app browser web browser email mail open with change all always open double-click chrome firefox", [
        "To change the browser that opens links, choose Dials > Dock and Menu Bar and pick one under Default "
        "web browser. Default email app is just below it.",
        "To change the app that opens a kind of document, select one in Drawer and press \u2318I. Under Open "
        "with, pick the app, then click Change All\u2026.",
        "To open one file in another app just this once, right-click it and choose Open With.",
    ]),
    "speak": ("Have the computer read words aloud", "speak selection read aloud out loud text to speech speech voice spoken content listen hear dyslexia reading pointer hover announce notifications time clock hour chime", [
        "Choose Dials > Accessibility and turn on Speak selection, under Spoken Content.",
        "Select some words in any app, then press \u2325Esc (Option+Esc) to hear them. Press it again to stop.",
        "Pick a voice and a speaking rate on the same page. Click Play to hear how they sound.",
        "Turn on Speak items under the pointer, then hold Command and point at some words to hear that line.",
        "Announce notifications reads each notification out as it shows. Announce the time says the time on "
        "the hour, half hour or quarter hour. Neither speaks while a Focus is on.",
    ]),
    "screen-reader": ("Use the screen reader", "screen reader blind low vision orca voiceover speak screen read out talk command f5 insert navigate keyboard", [
        "Press \u2318F5 (Command+F5) to turn the screen reader on, and again to turn it off. It's also in "
        "Dials > Accessibility.",
        "It speaks the window and control you move to, the text under the cursor and what you type. Use Tab "
        "and the arrow keys to move around an app.",
        "Insert is the screen reader key. Hold it and press H to learn the keys, or press Insert+Space for "
        "its settings. Screen Reader Settings in Dials changes its voice and speed too.",
        "If it was on when you logged out, it comes back on when you log in.",
    ]),
    "mic-camera": ("See when an app is using the microphone or camera", "microphone mic camera webcam privacy listening watching recording orange dot green dot in use spy", [
        "While an app is using the microphone, a small orange dot shows in the menu bar, next to the other "
        "status icons. A green dot means an app is using the camera.",
        "Click the dot to see which app it is. Quit that app, or close its call, to turn the microphone or "
        "camera off.",
    ]),
    "battery": ("Keep an eye on the battery", "battery low charge charging power percentage time left plug in sleep reserve laptop health capacity cycle count low power mode saver usage history level", [
        "The battery icon in the menu bar shows how much charge is left. Click it for the Battery menu: "
        "the charge, whether it's on the battery or the power adapter, and how long it will last, or how "
        "long until it's full while it charges.",
        "The Battery menu also lists the apps using significant energy, which run the battery down "
        "fastest. Click one to open Gauge. Battery Settings… opens Dials > Battery.",
        "When the battery runs down to 10%, and again at 5%, a notice asks you to plug in. At 2% the "
        "computer goes to sleep, so nothing you're working on is lost. Plug it in, then wake it.",
        "To hide the number next to the icon, turn off Show percentage in the menu bar in Dials > Battery.",
        "Dials > Battery shows the battery's level over the last 24 hours, and how long the computer ran on "
        "battery each of the last 10 days. Battery Health says Normal, or Service Recommended once it holds "
        "much less than it did new.",
        "Low Power Mode makes the battery last longer: choose Always, Only on Battery or Only on Power "
        "Adapter. The switch in the Battery menu turns it on or off at once. The battery in the menu bar "
        "turns yellow while it's on.",
    ]),
    "bluetooth": ("Connect Bluetooth headphones, keyboards and mice", "bluetooth headphones earbuds headset speaker keyboard mouse trackpad wireless pair connect disconnect battery devices menu bar", [
        "Click the Bluetooth symbol in the menu bar for the Bluetooth menu. The switch at the top turns "
        "Bluetooth on or off.",
        "Under Devices are the headphones, keyboards, mice and other devices paired with this computer. "
        "Connected ones are first, with a blue symbol, and those that report it show their battery.",
        "Click a device to connect it, or click a connected one to disconnect it. If it can't connect, "
        "make sure it's on and nearby, then try again.",
        "To pair a new device, choose Bluetooth Settings… and put the device in pairing mode. Dials lists "
        "it under Nearby Devices: click Pair.",
    ]),
    "quick-settings": ("Use Quick Settings in the menu bar", "quick settings control centre center wifi bluetooth focus dark mode night light stage manager volume switch menu bar", [
        "Click the Quick Settings symbol in the menu bar, next to the clock, for Wi-Fi, Bluetooth, Focus, "
        "Dark Mode, Night Light, Stage Manager and the volume in one place.",
        "Each one has a round symbol that's blue while it's on. Click the symbol to turn it on or off.",
        "Click the words Wi-Fi or Bluetooth for their menus, with the networks to join or the devices to "
        "connect. Clicking the words of the others turns them on or off too.",
        "Settings… at the bottom opens Dials.",
    ]),
    "menu-bar-icons": ("Choose which icons show in the menu bar", "menu bar icons hide show remove wifi wi-fi bluetooth sound volume battery focus now playing seek search lifeboat backup control centre center clutter", [
        "Open Dials > Dock and Menu Bar. Under the menu bar settings, turn Show Wi-Fi, Bluetooth, Sound, "
        "Battery, Focus, Now Playing, Seek or Lifeboat in menu bar on or off.",
        "An icon you turn off leaves the menu bar at once. Wi-Fi, Bluetooth, Focus and the volume are still "
        "in Quick Settings, the symbol beside the clock.",
    ]),
    "now-playing": ("Control music and videos from the menu bar", "now playing music song track video play pause skip next previous album cover menu bar controls media", [
        "While an app plays music or a video, a music note shows in the menu bar. Click it to see the album "
        "cover, the song, the artist and how far it has got.",
        "The buttons under it go back, play or pause, and skip forward. The note goes away when the app stops.",
        "To hide it, turn off Show Now Playing in menu bar in Dials > Dock and Menu Bar.",
    ]),
    "menu-extras": ("Use apps' icons in the menu bar", "menu bar extras icons tray status icon system tray app indicator notification area background running chat cloud sync", [
        "Some apps put an icon of their own in the menu bar while they run, such as chat, cloud storage "
        "and password apps. They sit left of freemac's own icons, newest furthest left.",
        "Click an app's icon for its menu, or to bring up its window when it has no menu. Right-click "
        "always opens the menu when there is one. Scroll over an icon if the app reacts to that.",
        "An icon goes away when its app quits. To quit an app that has no window, choose Quit from its "
        "icon's menu.",
        "Mac programs that run through Ferry put their menu bar items here too, as icons or words.",
    ]),
    "see-better": ("Make the screen easier to see", "reduce transparency solid see-through invert colours colors negative contrast accessibility vision eyes", [
        "Choose Dials > Accessibility and turn on Reduce transparency. The menu bar, the Dock and panels "
        "become solid, so what's behind them no longer shows through.",
        "Turn on Invert colours with \u2303\u2325\u23188, then press Control+Option+Command+8 to swap the "
        "screen's colours. Press it again to put them back.",
        "High contrast and Larger text are on the same page.",
    ]),
    "accents": ("Type accented letters", "accent accents accented letter é è ê ñ ü ç umlaut cedilla tilde grave acute diacritic press hold key foreign language french spanish german", [
        "In a text field, press and hold a letter such as e. A small panel shows its accented forms, "
        "each with a number under it.",
        "Press the number, or click the letter you want, and it takes the place of the one you typed. "
        "The arrow keys and Return pick one too, and Escape closes the panel.",
        "Hold Shift as well for capitals. Letters with accents are a, c, e, i, l, n, o, s, u, y and z.",
        "To have held letters repeat instead, open Dials > Keyboard and turn off Press and hold for accents.",
    ]),
    "colour-filters": ("Change the screen's colours", "colour color filter greyscale grayscale black and white colour blind color blind red green blue yellow protanopia deuteranopia tritanopia tint accessibility see", [
        "Choose Dials > Accessibility and pick one of the Colour filters: Greyscale, a red/green or "
        "blue/yellow filter for colour blindness, or Colour tint.",
        "Drag Intensity to make the filter stronger or weaker. With Colour tint, click Tint colour to pick its colour.",
        "To see the screen's own colours again, set Colour filters to Off.",
    ]),
    "sticky-keys": ("Press keyboard shortcuts one key at a time", "sticky keys modifier one hand one finger shift control option command shortcut hold two keys at once latch lock accessibility", [
        "Choose Dials > Accessibility and turn on Sticky Keys, or press Shift five times in a row.",
        "Now tap a modifier key such as \u2318 Command, then the key that goes with it: \u2318 then C copies. "
        "The modifier's symbol shows in the top-right corner until you press the next key.",
        "Tap a modifier twice to lock it, and once more to let it go.",
        "Press Shift five times again to turn Sticky Keys off.",
    ]),
    "slow-keys": ("Type only the keys you mean to", "slow keys accidental keys bumped brushed tremor shaky hands delay hold acceptance typing accessibility click", [
        "Choose Dials > Accessibility and turn on Slow Keys.",
        "Now hold each key down for a moment before it counts. A key you only brush on the way to "
        "another isn't typed.",
        "Drag Acceptance delay toward Long if keys still get typed by accident, or toward Short if typing feels slow.",
        "Shift, Control, Option and Command work at once, so a shortcut only waits for its last key.",
        "Turn off Use click key sounds if you'd rather not hear a click as each key goes down and counts.",
    ]),
    "mouse-keys": ("Move the pointer with the keyboard", "mouse keys keypad numpad number pad move pointer cursor without mouse trackpad click drag keyboard accessibility", [
        "Choose Dials > Accessibility and turn on Mouse Keys, or press Option five times in a row.",
        "On the number keypad, 8, 2, 4 and 6 move the pointer up, down, left and right, and 7, 9, 1 and 3 move it diagonally. "
        "Hold a key and the pointer speeds up.",
        "Press 5 to click, or Control and 5 for a secondary click. Press 0 to hold the button down, move to drag, then press the full stop to let go.",
        "No keypad? Turn on Use the letter keys too, and use 8, K, U and O to move, I to click, M to hold and the full stop to let go.",
        "Drag Initial delay and Maximum speed until the pointer moves the way you like.",
    ]),
    "accessibility-keyboard": ("Type with a keyboard on the screen", "accessibility keyboard on screen onscreen virtual keyboard type with mouse pointer trackpad touch no keyboard broken keys accessibility", [
        "Choose Dials > Accessibility and turn on Accessibility Keyboard.",
        "Click the keys to type in the app you're using, just as if you'd pressed them.",
        "Click \u21e7 Shift, \u2303 Control, \u2325 Option or \u2318 Command and it stays down for the next key: "
        "\u2318 then A selects everything. Click it twice to lock it, and once more to let it go.",
        "Drag the keyboard by its top edge to move it, or click its red button to close it.",
    ]),
    "drawer-settings": ("Change Drawer's settings", "drawer settings preferences finder new window opens folder trash empty 30 days automatically warning folders on top sort", [
        "In Drawer, choose Drawer > Settings, or press \u2318,.",
        "General: pick the folder new Drawer windows open in.",
        "Advanced: turn the warning before emptying the Trash on or off, have items removed from the Trash "
        "after 30 days, and keep folders on top when sorting.",
    ]),
    "night-light": ("Make the screen warmer at night", "night light shift warm warmer yellow orange blue light eyes sleep evening sunset sunrise schedule colour temperature", [
        "Choose Dials > Displays and turn on Night Light.",
        "Set Schedule to Sunset to Sunrise to follow the sun where you are, or to Custom to pick the hours.",
        "Drag Colour toward Warmer or Less warm.",
    ]),
    "background-sounds": ("Play calming background sounds", "background sounds noise white pink brown rain ocean waves stream water focus calm rest mask distractions tinnitus accessibility", [
        "Choose Dials > Accessibility and, under Audio, turn on Background sounds.",
        "Pick a sound: Balanced, Bright or Dark noise, Ocean, Rain or Stream, and drag Volume until it's just right.",
        "The sound plays behind everything else until you turn Background sounds off.",
    ]),
    "keep-awake": ("Keep the screen on", "keep awake screen on stay on stop sleeping prevent sleep display off caffeinate video movie watching lock screen saver presentation", [
        "While a video plays in Reel or a web browser, the screen stays on and doesn\u2019t lock, "
        "however long it is since you touched the mouse.",
        "To keep it on for something else, open Terminal and type caffeinate. The screen stays on "
        "until you press Control+C. caffeinate -t 3600 keeps it on for an hour, and caffeinate "
        "followed by a command keeps it on until the command finishes.",
        "Dials > Power shows what is keeping the screen on. Closing a laptop\u2019s lid still puts it to sleep.",
    ]),
    "pointer-colour": ("Change the pointer\u2019s colours", "pointer cursor mouse arrow colour color fill outline orange pink red bright see easier accessibility reset", [
        "Choose Dials > Accessibility.",
        "Click Pointer fill colour to choose the colour inside the pointer, and Pointer outline colour "
        "for the edge round it. The pointer changes everywhere a moment later.",
        "Colours that differ a lot, like a bright fill with a dark outline, are the easiest to see.",
        "Click Reset to go back to a black pointer with a white edge.",
    ]),
    "find-pointer": ("Find the pointer", "find pointer cursor mouse lost shake big larger size locate where see", [
        "Lost the pointer? Move the mouse quickly back and forth and the pointer grows big for a moment.",
        "To turn this off, or to make the pointer bigger all the time, open Dials > Accessibility and "
        "change Shake mouse pointer to locate or Pointer size.",
    ]),
    "screen-flash": ("Flash the screen for alerts", "flash screen alert sound beep hear deaf hard of hearing visual bell blink accessibility", [
        "Choose Dials > Accessibility and turn on Flash the screen when an alert sound occurs.",
        "Whenever an app plays the alert sound, because something can\u2019t be done, every display flashes "
        "for a moment, even with the alert volume turned all the way down.",
        "Click Test Screen Flash to see how it looks.",
    ]),
    "stacks": ("Tidy the desktop with stacks", "stacks stack desktop tidy clean up arrange sort kind messy screenshots get info item info size dimensions view options icon size bigger smaller text spacing", [
        "Right-click an empty part of the desktop and choose Use Stacks, or press Control+Command+0. "
        "Files of one kind go into a pile: Images, Screenshots, Documents, PDF Documents and so on.",
        "Click a stack to spread its files out on the desktop, and click it again to gather them up.",
        "New files go straight into their stack, so a desktop full of screenshots stays tidy.",
        "With stacks off, Clean Up By Name, Kind or Date Modified puts every icon back in a neat order. "
        "Get Info (Command+I) tells you about a file.",
        "Right-click the desktop and choose Show Item Info to see, under each name, how big a picture is "
        "and how many items a folder holds.",
        "To make the desktop's icons bigger or smaller, right-click the desktop and choose Show View Options, "
        "or press Command+J. Slide Icon size and Grid spacing, pick a Text size, and click Use Defaults "
        "to go back to how it was.",
    ]),
    "notifications": ("Manage notifications and Do Not Disturb", "notifications notification centre center banners alerts do not disturb quiet schedule night sleep focus mute app", [
        "Click the date and time in the menu bar to open the notification centre. Several notifications "
        "from one app sit in a stack: click it to see them all, and click the x beside the app's name to "
        "clear them.",
        "To quiet banners for a while, turn on a Focus, such as Do Not Disturb: choose it from Focus at the "
        "top of the centre, or from Focus in Quick Settings.",
        "In Dials > Notifications each app that has sent a notification has its own choice: Banners, "
        "In Notification Centre only, or Off.",
    ]),
    "focus": ("Use Focus to quiet notifications", "focus do not disturb dnd quiet silence sleep bedtime night work personal schedule allowed apps moon bed concentrate mute", [
        "A Focus hides banners so you can get on with things. Notifications still collect in the "
        "notification centre, and urgent ones always show. There are four: Do Not Disturb, Sleep, Work "
        "and Personal.",
        "To turn one on, click Quick Settings in the menu bar, click Focus and choose one. Click it again "
        "to turn it off. You can also choose it from Focus at the top of the notification centre.",
        "While a Focus is on, its symbol shows in the menu bar: a moon for Do Not Disturb, a bed for "
        "Sleep, a briefcase for Work and a person for Personal. Click it to switch to another Focus, or "
        "click the one that's on to turn it off.",
        "To choose the apps that can still reach you, open Dials > Focus and tick them under the Focus's "
        "Allowed apps.",
        "To have a Focus come on by itself, turn on Turn on at set times under it and choose the hours "
        "and days, for example Work from 09:00 to 17:00, Monday to Friday. If you turn it off early, it "
        "stays off until the next time.",
    ]),
    "widgets": ("Put widgets on your desktop or in the Notification Centre",
                "widgets widget desktop clock calendar weather reminders battery screen time world clock "
                "sticky note photo notification centre gallery edit", [
        "Right-click an empty part of the desktop and choose Edit Widgets…. Click Add beside a clock, "
        "a calendar, the weather, your reminders, the battery, Screen Time, world clocks, your newest "
        "sticky note or a photo of the day.",
        "To put widgets in the Notification Centre instead, click the date and time in the menu bar, "
        "scroll to the bottom and click Edit Widgets…, or choose the Notification Centre tab at the top "
        "of the widget gallery.",
        "Drag a widget to wherever you like it on the desktop. It stays there.",
        "Click a widget to open its app, such as Sky for the weather. Right-click one on the desktop and "
        "choose Remove Widget to take it away, or click Remove beside it in the gallery.",
        "The World Clock widget shows the cities you added in Chime. The Photo widget picks a different "
        "picture from your Pictures folder each day.",
    ]),
    "glance": ("Take a quick look at a file", "glance quick look preview space peek video movie music pdf photo full screen", [
        "Click a file in Drawer or on the desktop and press Space. Glance shows it without opening an app.",
        "Pictures fit the window, PDFs show every page, and movies and music start playing.",
        "Press the arrow keys to look at the next file. With several files chosen, the arrows at the top "
        "step through them.",
        "Press Control+Command+F or click the arrows at the top right to fill the screen. Press Space again "
        "to close Glance, or click Open to open the file.",
    ]),
    "drawer-more": ("Sort, find and put back files", "drawer sort kind date size path bar status bar space available free disk sidebar hide preview pane information created dimensions go to folder open with put back trash empty finder", [
        "Right-click an empty part of a Drawer window and choose Sort By to order files by name, kind, "
        "date modified or size. Drawer remembers your choice.",
        "Right-click a file and choose Open With to open it in another app, or Other… to pick any app.",
        "Choose Go > Go to Folder… (Shift+Command+G) and type where to go, such as ~/Documents. "
        "Press Tab to finish a name.",
        "Choose View > Show Path Bar (Option+Command+P) to see the folders above this one. Click one to go there.",
        "The status bar at the bottom of the window shows how many items there are, how many you've selected "
        "and how much space is left on the disk. Command+/ hides or shows it, and View > Show Sidebar hides the sidebar.",
        "Choose View > Show View Options (Command+J) to make icons bigger or smaller, space them out, change "
        "the size of their names, show a folder's item count or a picture's size under its name, and sort.",
        "Choose View > Show Preview (Shift+Command+P) for a pane on the right with a large picture of the chosen "
        "file and its information: when it was made and changed, a picture's size, and its tags.",
        "In the Trash, right-click a file and choose Put Back (or press Command+Delete) to return it to its folder. "
        "Click Empty to erase everything in the Trash.",
    ]),
    "recents": ("Find files you opened lately", "recents recent files lately opened last new folder with selection group enclosing", [
        "Click Recents at the top of Drawer's sidebar, or press Shift+Command+F, to see the files you opened "
        "lately, newest first.",
        "Right-click a file there and choose Show in Enclosing Folder to open the folder it's in, or "
        "Remove from Recents to take it off the list.",
        "To put several files into a new folder at once, select them, right-click one and choose "
        "New Folder with Selection. Type a name for the folder. Command+Z puts them back.",
    ]),
    "quick-actions": ("Turn pictures and make PDFs", "quick actions rotate turn picture photo pdf create spring loaded folder drag hold", [
        "Right-click a picture in Drawer and choose Quick Actions, then Rotate Left or Rotate Right to turn it. "
        "On the desktop, Rotate Left and Rotate Right are right in the picture's menu.",
        "Select several pictures and choose Create PDF to put them into one PDF, a page for each.",
        "To drop files deep inside a folder, drag them onto the folder and hold them there for a moment. "
        "It opens, so you can keep going into the folder inside it.",
    ]),
    "tags": ("Tag files with colours", "tags tag colour color label red orange yellow green blue purple gray finder", [
        "Right-click a file in Drawer or on the desktop and click a colour under Tags. A dot in that colour "
        "shows after the file's name.",
        "Click the same colour again to take the tag off. You can give a file more than one colour.",
        "Click a colour under Tags in Drawer's sidebar to see every file with that tag, wherever it is.",
        "You can also drag files onto a colour in the sidebar to tag them, or click a colour next to Tags "
        "in Get Info (Command+I).",
        "Memory cards and some USB drives can't keep tags.",
    ]),
    "smart-folders": ("Search all your files, and keep searches as Smart Folders", "search find file everywhere this mac smart folder saved search kind images pdf documents date today week lost where is", [
        "In a Drawer window, type in the search box at the top right. Drawer shows the matching files in the "
        "folder you're in straight away; click This Mac under the toolbar to look through all your files, "
        "by name and by the words inside documents.",
        "Use the Kind and time menus beside it to narrow it down, such as PDF Documents changed in the "
        "past 30 days. They work without any words too: choose Images and Today to see today's pictures.",
        "Click Save to keep the search as a Smart Folder. It shows under Smart Folders in the sidebar and "
        "looks again each time you open it, so new files that match appear by themselves.",
        "Choose File > New Smart Folder (Option+Command+N) to start one from scratch. To change a Smart "
        "Folder, open it, change the words or menus and click Save. Right-click it and choose Remove Smart "
        "Folder to take it away; the files it showed stay where they are.",
    ]),
    "seek-settings": ("Choose what Seek finds, and keep folders private", "seek spotlight search results privacy private folder hide index rebuild settings command space", [
        "Choose Dials > Seek. Under Search Results, turn off any kind of thing you don't want Seek to list, "
        "such as Events or Menu items. It counts the next time you type in Seek.",
        "Under Privacy, click + and choose a folder to keep it out of Seek and out of Drawer's This Mac "
        "searches and Smart Folders. Click − beside it to let them look there again.",
        "Turning off Words inside documents makes Seek forget what it read inside your files. If Seek ever "
        "misses a document you know is there, click Rebuild Index.",
    ]),
    "screen-saver": ("Use a screen saver", "screen saver screensaver idle drift clock album photos slideshow", [
        "Choose Dials > Screen Saver and click the one you like: Drift, Clock or Album, which shows the "
        "photos in your Pictures folder.",
        "It starts when nothing has been touched for the time under Start the screen saver after. "
        "Click Preview to see it now.",
        "Move the pointer or press a key to end it. If the screen was due to lock, it asks for your password.",
        "To start it from a corner of the screen, choose it under Hot Corners in Dials > Dock and Menu Bar.",
    ]),
    "recovery": ("Fix a computer that won't start", "recovery mode recover repair fix start startup boot won't start forgotten password reset reinstall disk check ctrl undo update go back previous version", [
        "freemac Recovery fixes a computer that won't start properly. To open it, hold Ctrl while the "
        "computer starts, or choose Dials > Power > Restart in Recovery….",
        "Type an administrator's password, then choose what to do and click Continue:",
        "- Restore from Lifeboat brings a home folder back from a backup drive. Plug the drive in first.",
        "- Undo Last Update puts back the version of freemac from before the last update.",
        "- Reset a Password chooses a new password for someone who has forgotten theirs.",
        "- Check a Disk looks for problems on a disk and fixes them.",
        "- Reinstall freemac puts a fresh copy on the disk from a freemac USB stick.",
        "- Get Help Online opens these pages on the web. Join a Wi-Fi network first, from the top right.",
        "When you're done, click the power button at the top right and choose Restart.",
    ]),
    "power-schedule": ("Start up or shut down at set times", "schedule energy start up wake shut down sleep "
                       "restart timer automatic every day bedtime night", [
        "Your computer can start up or wake at a set time, and go to sleep, restart or shut down at another. "
        "Open Dials > Battery (Power on a computer with no battery) and click Schedule….",
        "Tick Start up or wake, choose the days (every day, weekdays, weekends or one day) and set the time. "
        "Tick the second line and choose Sleep, Restart or Shut Down, with its days and time. Click Apply and "
        "give an administrator's password; the schedule is for the whole computer.",
        "When it's time to sleep, restart or shut down, anyone who's logged in gets ten minutes' warning. Click "
        "Cancel to stop it this time, or the other button to do it now. Save your work first.",
        "Waking from sleep works on every PC. Starting up from off works on most; if yours doesn't, turn on the "
        "wake alarm (sometimes called RTC Alarm or Resume by Alarm) in its firmware settings.",
    ]),
    "disk-images": ("Open a disk image (.iso or .img)", "disk image iso img dmg raw mount open eject hatch "
                    "virtual disk cd dvd burn make image from folder hull blank new empty copy drive backup clone", [
        "Double-click an .iso or .img file, in Downloads for example: it opens as a disk, on the Desktop and in "
        "Drawer's sidebar, and its window opens. Its files are there to open or copy, as on a USB drive.",
        "When you're done, click the Eject button beside it in Drawer's sidebar, or in Hull. The image file "
        "itself stays where it is.",
        "An .iso, like a disc's, opens read-only. An .img that's yours opens so you can change what's on it.",
        "To make one, open Hull and choose File > New Image from Folder…: pick a folder and where to save it, and "
        "you get an .img holding a copy of that folder. Hull also lists the disk images you have open.",
        "File > New Blank Image… (⌘N) in Hull makes an empty one of the size and format you choose: it opens like a "
        "USB drive you keep in a file, to put files on, eject, and copy or send.",
        "File > New Image from Drive… copies a whole USB drive, disc or volume into an .img (an .iso for a disc), "
        "to keep as a backup or put back on a drive later with Restore.",
        "A Mac's .dmg files are for installing Mac apps; freemac can't open them. Look for the app in Harbor, or a "
        "download made for Linux.",
    ]),
    "applications-folder": ("Find your apps in the Applications folder", "applications folder apps list all "
                            "drawer get info version size remove uninstall delete trash shift command a", [
        "Drawer's sidebar has Applications, as on a Mac: every app on this computer, freemac's own and the ones "
        "you installed. ⇧⌘A opens it from Drawer's Go menu.",
        "Double-click an app there to open it.",
        "Select an app and press ⌘I for its Info: what it does, its version, and how much room it takes.",
        "To remove an app, open Harbor, find it and click Remove; dragging it to the Trash doesn't remove it. "
        "The apps that come with freemac can't be removed.",
    ]),
    "first-aid": ("Check a drive for errors with First Aid", "first aid check repair fix drive disk errors "
                  "corrupt damaged usb stick memory card fsck chkdsk hull won't open", [
        "If a USB drive or memory card acts up, open Hull, choose it in the sidebar and click First Aid. "
        "Choose a drive to check every volume on it, or one volume to check just that one.",
        "It's unmounted while it's checked, so close any files on it first; it's mounted again afterwards.",
        "First Aid repairs what it can. If it says there are problems it couldn't repair, copy what you need off "
        "the drive and erase it to use it again.",
        "freemac can check most formats, including ExFAT, MS-DOS (FAT) and Linux (ext4). The disk freemac is "
        "running from is checked as the computer starts up, when it needs it.",
    ]),
    "partition": ("Divide a drive into several volumes", "partition split divide drive disk volumes "
                  "partitions pie usb stick separate parts hull", [
        "Open Hull, choose a USB drive (or one of its volumes) and click Partition.",
        "Click + to split the chosen volume in two, and − to take it away. Click a slice of the pie to choose it, "
        "then give it a name, a format and a size. Drag the white dots between slices to change their sizes.",
        "Click Apply, and Hull asks once more, naming every volume. Partitioning erases everything on the drive, "
        "so copy off anything you want to keep first.",
        "The new volumes show on the Desktop and in Drawer like any drive. Erase the whole drive in Hull to make "
        "it one volume again.",
    ]),
    "restore-usb": ("Copy a disk image onto a USB drive", "restore usb stick drive bootable startup start up "
                    "installer iso img write flash burn copy image onto hull", [
        "To make a USB drive that starts up freemac, or another system, from its .iso: plug the drive in, open "
        "Hull, choose the drive in the sidebar and click Restore (⇧⌘R).",
        "Choose the disk image, then click Restore. Everything on the drive is replaced by what's in the image, "
        "and that can't be undone, so copy off anything you want to keep first.",
        "A window shows how far it has got. Stop halts it, but then the drive holds only part of the image: "
        "restore it again, or erase it to use it for files.",
        "To start up from it, choose it in Dials > Startup Disk.",
        "Only drives that are plugged in can be restored, never the disk freemac is running from.",
    ]),
    "install-download": ("Install an app you downloaded", "install installer deb package download app software "
                         "setup slipway website", [
        "Most apps are in Harbor, freemac's app centre. If a website offers its app for Linux as a .deb file "
        "(for Debian or Ubuntu), download that and double-click it in Downloads: Slipway opens.",
        "Slipway shows the app with its icon, version, publisher and size, and the website you downloaded it "
        "from. Click Install and give an administrator's password; anything else the app needs comes from the "
        "internet.",
        "When it's done, click Open to start the app, or find it in Marina and Seek. Slipway offers to move the "
        "downloaded file to the Trash, since you don't need it any more.",
        "Only install apps from people you trust: an app can see your files and change anything on the computer. "
        "A file made for another kind of computer (ARM, or older 32-bit PCs) can't be installed; look for the "
        "download for 64-bit PCs (amd64).",
    ]),
    "startup-disk": ("Start up from Windows or another disk", "startup disk boot windows dual boot restart in "
                     "other system linux usb stick disc efi uefi bios firmware boot menu", [
        "If your computer has Windows or another system as well as freemac, choose which one it starts up from "
        "in Dials > Startup Disk. It shows each system and disk the computer can start up from, and which one "
        "you're using now.",
        "Click one, then Restart in it to start up from it just this once; after that the computer goes back to "
        "the one it always starts up from. Click Always Start Up from This to change that for good. Either asks "
        "for an administrator's password.",
        "To come back to freemac from Windows, hold the key for your PC's own start-up menu as it starts (often "
        "F12, F11, F10, F9, F8 or Esc) and choose freemac, or choose it in Windows' own settings.",
        "An older PC that starts up the BIOS way chooses its start-up disk only in its firmware settings or that "
        "start-up menu.",
    ]),
    "bring-over": ("Bring your files from another computer", "migrate migration move transfer old computer new "
                   "windows pc tender copy files settings bring over onedrive", [
        "Tender copies your documents, pictures, music, videos, desktop and downloads from your old computer. "
        "Press F4 and click Tender, or click Bring Files Over… in Welcome.",
        "Plug in the drive with your Lifeboat backup, or your old computer's disk. A Windows PC's disk can go in "
        "a USB case; Tender finds the files of each person on it, OneDrive's too. Or click Choose a Folder….",
        "Choose where the files are and click Continue, then tick what to bring. Each kind shows its size and "
        "whether there's room for it on this computer.",
        "Nothing is deleted and no file you have is replaced: a file that's already here is left alone, and a "
        "different one with the same name comes over as \"name 2\". You can run Tender again later; it skips "
        "what it brought before.",
        "From a Lifeboat backup you can also bring Settings and app data. They replace this account's own, "
        "which are kept in a hidden folder, .local/share/freemac-tender. Log out and back in afterwards.",
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
