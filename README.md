# freemac

freemac is an original, free operating system for ordinary x86-64 PCs whose
desktop *feels* like a classic Mac-style desktop: a global menu bar along the
top, a dock along the bottom, calm window chrome, a fast search launcher and
trackpad gestures that just work.

It is a small Linux distribution (Debian base) with its own Wayland desktop
shell. It is **not** macOS and it contains nothing from Apple. An optional
add-on, [Ferry](ferry/README.md), runs some simple command-line programs built
for Intel Macs; Mac apps in general, and App Store apps in particular, do not
run.

## Screenshots

Taken from the 1.131 live ISO in a virtual machine (QEMU, 1280×800). The
names, contacts and events in them are made-up examples.

![The freemac desktop with the Welcome window, menu bar and Dock](docs/screenshots/welcome.png)

<table>
<tr><td width="50%"><img src="docs/screenshots/drawer.png" alt="Drawer, the file browser, with the menu bar and Dock"><br><sub>Drawer, the file browser, with the menu bar and Dock</sub></td><td width="50%"><img src="docs/screenshots/seek.png" alt="Seek (⌘Space) finds files, apps, contacts, events and reminders"><br><sub>Seek (⌘Space) finds files, apps, contacts, events and reminders</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/apps.png" alt="All apps (F4 or the Dock's grid icon)"><br><sub>All apps (F4 or the Dock's grid icon)</sub></td><td width="50%"><img src="docs/screenshots/freemac-menu.png" alt="The freemac menu at the left of the menu bar"><br><sub>The freemac menu at the left of the menu bar</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/quick-settings.png" alt="Quick Settings open from the menu bar: Wi-Fi and Bluetooth on with blue symbols and chevrons, Focus, Dark Mode, Night Light and Stage Manager off, a volume slider and Settings…"><br><sub>Quick Settings: click a symbol to switch it, or Wi-Fi or Bluetooth for its menu</sub></td><td width="50%"><img src="docs/screenshots/nudge.png" alt="Nudge, for reminders"><br><sub>Nudge, for reminders</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/tide.png" alt="Tide, the calendar"><br><sub>Tide, the calendar</sub></td><td width="50%"><img src="docs/screenshots/crew.png" alt="Crew, for contacts"><br><sub>Crew, for contacts</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/dark-mode.png" alt="Dark mode, with the night wallpaper"><br><sub>Dark mode, with the night wallpaper</sub></td><td width="50%"><img src="docs/screenshots/dials-dark.png" alt="Dials, the settings app, in dark mode"><br><sub>Dials, the settings app, in dark mode</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/lock-screen.png" alt="The lock screen: the date and clock, a song playing with back, pause and skip buttons, a notification that came while locked, the battery in the corner and a message under the password field"><br><sub>The lock screen, with Now Playing and a notification</sub></td><td width="50%"><img src="docs/screenshots/reel-pip.png" alt="Picture in Picture: a Reel video floating above Tide in the corner"><br><sub>Picture in Picture: a Reel video floating above Tide</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/dynamic-wallpaper.png" alt="Dynamic wallpaper: Tide turning golden at sunset, with the Dynamic switch in Dials"><br><sub>Dynamic wallpaper: the picture turns golden at sunset</sub></td><td width="50%"><img src="docs/screenshots/stage-manager.png" alt="Stage Manager: Crew in the middle, with Quill, Tide and Nudge as small pictures down the left"><br><sub>Stage Manager: one app in front, the others down the side</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/mission-control.png" alt="Mission Control on Desktop 3, holding a Drawer window, with the row of desktops opened out along the top: the button to close Desktop 3 on its corner and + at the right end"><br><sub>Mission Control: add a desktop with +, close one from its corner, drag windows onto them</sub></td><td width="50%"><img src="docs/screenshots/passwords.png" alt="Purser, the Passwords app, showing a saved login with its six-digit verification code and a warning that its password is used on another website"><br><sub>Purser keeps website and Wi-Fi passwords and verification codes, and warns about reused passwords</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/live-text.png" alt="Frame showing a school trip form with Live Text on: the picture dimmed, every line of text lit up, and two lines selected for copying"><br><sub>Live Text in Frame: select and copy the words in a picture</sub></td><td width="50%"><img src="docs/screenshots/hover-text.png" alt="Hover Text: Command held over a line of small text in Dials, and the same line shown large in a panel above the pointer"><br><sub>Hover Text: hold ⌘ and point to see small words large</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/focus.png" alt="Quick Settings with the Focus list open and Work picked: the tile turns blue and the menu bar shows a briefcase"><br><sub>Focus: pick Do Not Disturb, Sleep, Work or Personal from Quick Settings</sub></td><td width="50%"><img src="docs/screenshots/focus-settings.png" alt="Dials > Focus: Work lets Nudge and Tide through and turns on from 9:00 to 17:00, Monday to Friday"><br><sub>Each Focus has its own allowed apps and set times, in Dials</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/accessibility-keyboard.png" alt="The Accessibility Keyboard floating over Quill, with a line typed by clicking its keys"><br><sub>Accessibility Keyboard: type by clicking the keys on the screen</sub></td><td width="50%"><img src="docs/screenshots/accessibility-keyboard-dark.png" alt="The Accessibility Keyboard in dark mode, with Shift held so its keys show capitals"><br><sub>In dark mode, with ⇧ Shift held for the next key</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/seek-definition.png" alt="Seek with light typed: among Appearance, Displays and a Guide topic, a Definition result for light is chosen, and the preview lists four meanings, as a noun, a verb, an adjective and an adverb, with Press Return to see it in Words"><br><sub>Seek shows what a word means, from Words</sub></td><td width="50%"><img src="docs/screenshots/seek-definition-forms.png" alt="Seek with mice typed and a Definition result for mouse, whose preview lists four meanings, from the small rodent to the hand-operated device that moves the pointer"><br><sub>Other forms of a word find it: mice finds mouse</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/alias.png" alt="Drawer showing Documents with Recipes alias chosen, its folder icon carrying a small curved arrow, and its Info window: Kind Alias, Original Home/Documents/Recipes and a Select New Original button"><br><sub>Aliases open the original from anywhere, and Get Info says where it is</sub></td><td width="50%"><img src="docs/screenshots/alias-broken.png" alt="An alert over Drawer: The alias Garden plan.txt alias can't be opened because the original item can't be found, with OK, Delete Alias and Fix Alias buttons"><br><sub>An alias whose original is gone can be deleted or pointed somewhere new</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/custom-icon.png" alt="Drawer showing Documents, where the Recipes folder and Recipes alias have a red soup pot as their icon, and the Recipes Info window with that icon chosen and the comment Grandma's soups and stews"><br><sub>Paste any picture on an icon in Get Info, and add a comment</sub></td><td width="50%"><img src="docs/screenshots/seek-comment.png" alt="Seek with cabin typed: a Definition result, then Lakeside.img, found by its comment Lakeside cabin photos backup"><br><sub>Seek finds files by their comments</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/list-view-options.png" alt="Drawer in list view at Home, sorted by size with folder sizes added up, Documents first at 377.5 MB, and the View Options: List panel with Show Columns, Use relative dates and Calculate all sizes"><br><sub>List view options: columns, relative dates and folder sizes</sub></td><td width="50%"><img src="docs/screenshots/locked.png" alt="Drawer showing the Recipes folder with a small padlock on its icon, and its Info window with Locked ticked and You can read it, not change it"><br><sub>Lock a file or folder in Get Info</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/locked-trash.png" alt="Drawer asking: Recipes is locked. Do you want to move it to the Trash anyway? with Stop and Continue"><br><sub>Drawer asks before throwing away a locked item</sub></td><td width="50%"><img src="docs/screenshots/change-picture.png" alt="Dials Wallpaper with Change picture set to Every 5 minutes, Pictures from freemac wallpapers, Random order off"><br><sub>Change picture moves the wallpaper on by itself</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/permissions.png" alt="Recipes Info with Sharing and permissions: freemac (Me) Read and Write, freemac Read and Write, everyone with its pop-up open on Read and Write, Read only and No Access, and Apply to Enclosed Items"><br><sub>Choose who can read or change an item in Get Info</sub></td><td width="50%"><img src="docs/screenshots/inspector.png" alt="Drawer with the Recipes folder chosen and the Recipes Info inspector floating at the right of the screen, scrolled to show its size, comments and privileges"><br><sub>The Inspector follows what you choose</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/option-menu.png" alt="Drawer's shortcut menu with Option held: Show Inspector in place of Get Info, and Copy Lakeside.img as Pathname in place of Copy"><br><sub>Hold Option for Show Inspector and Copy as Pathname</sub></td><td width="50%"><img src="docs/screenshots/recent-folders.png" alt="Drawer's Go menu with Recent Folders open: Recipes, Documents, Downloads and Pictures, then Clear Menu"><br><sub>Go > Recent Folders: back to a folder you used lately</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/history-menu.png" alt="Drawer in Documents with Forward held down, showing Recipes, Pictures and Downloads under the button"><br><sub>Hold Back or Forward to jump several folders at once</sub></td><td width="50%"><img src="docs/screenshots/summary-info.png" alt="Drawer with six items chosen in Documents and the Summary Info window: 6 items, Multiple kinds, 377.5 MB for 8 items, Home/Documents, the tag colours and Locked"><br><sub>Get Summary Info: several items in one window</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/show-clipboard.png" alt="Drawer's Clipboard window showing a picture of a soup pot, with Clipboard contents: picture (512 × 512) at the bottom"><br><sub>Edit > Show Clipboard: what you copied last</sub></td><td width="50%"></td></tr>
<tr><td width="50%"><img src="docs/screenshots/accessibility-shortcuts.png" alt="The Accessibility Shortcuts panel over the desktop, listing Screen Reader, Zoom, Sticky Keys, Slow Keys, Mouse Keys, Accessibility Keyboard, Hover Text, Invert Colours, Colour Filters, Increase Contrast and Reduce Transparency, with a tick by Zoom, and Accessibility Settings… and Done buttons"><br><sub>Accessibility Shortcuts: press ⌥⌘F5 to turn features on or off</sub></td><td width="50%"><img src="docs/screenshots/accessibility-shortcuts-filter.png" alt="The same panel with Sticky Keys and Colour Filters ticked, and the whole screen in greys from the colour filter"><br><sub>One click turns on Colour Filters, here in greys</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/sound-menu.png" alt="The Sound menu open under the speaker in the menu bar: a volume slider, the outputs Speakers and Headphones with Speakers marked, and Sound Settings"><br><sub>The Sound menu: the volume, and the output to play through</sub></td><td width="50%"><img src="docs/screenshots/sound-settings.png" alt="Dials > Sound with the output, its Balance slider and volume, and the microphone's Input level lit up"><br><sub>Balance and Input level in Dials > Sound</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/storage.png" alt="Dials > Storage: 3.2 GB used of 4.0 GB on a bar coloured by Applications, Documents, Pictures, Music, Movies, Downloads, Trash and System, with Empty Trash and Review Files under Recommendations"><br><sub>Storage in Dials: what fills the disk, and ways to free some up</sub></td><td width="50%"><img src="docs/screenshots/storage-review.png" alt="Review Files listing the biggest files in the home folder by size, with Show in Drawer and Move to Trash"><br><sub>Review Files: the biggest files, to move to the Trash</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/widgets.png" alt="Widgets on the desktop: world clocks for London, Tokyo and Denver, a Battery widget showing the power adapter, a yellow sticky note, a photo of a lake at dusk and Screen Time with the three apps used most today"><br><sub>Widgets on the desktop</sub></td><td width="50%"><img src="docs/screenshots/widgets-centre.png" alt="The Notification Centre scrolled down to its widgets: reminders, the battery, world clocks for London, Tokyo and Denver, and Screen Time, as light cards, with Edit Widgets at the foot"><br><sub>Widgets in the Notification Centre</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/software-update.png" alt="Dials > Software Update: freemac 1.135.0 is available, with Update Now and a What's New list, and below it App and System Updates and the switch for installing important updates automatically"><br><sub>Software Update: a new version of freemac and what's new in it</sub></td><td width="50%"><img src="docs/screenshots/software-update-ready.png" alt="freemac 1.135.0 is ready to install, with Restart Now: the computer restarts to install it"><br><sub>Downloaded while you work, installed when the computer restarts</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/battery.png" alt="Dials > Battery: the battery at 76% with 4:42 left, and a chart of its level every 15 minutes over the last 24 hours, green strips marking when it was plugged in, last charged to 100% at 10:55 AM; the battery in the menu bar is yellow for Low Power Mode"><br><sub>Battery in Dials: its level over the last day</sub></td><td width="50%"><img src="docs/screenshots/battery-health.png" alt="Time on Battery for each of the last 10 days, Battery Health Normal at 91% maximum capacity and 143 charge cycles, and Low Power Mode set to Only on Battery"><br><sub>Time on battery, Battery Health and Low Power Mode</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/user-menu.png" alt="Fast user switching: the user menu open under the name freemac in the menu bar, listing freemac and Maya, Login Window and Users &amp; Groups Settings"><br><sub>Fast user switching from the menu bar</sub></td><td width="50%"><img src="docs/screenshots/login-switch.png" alt="The login screen with Maya chosen and freemac marked with a dot as already logged in"><br><sub>The login screen marks who is already logged in</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/logbook-family.png" alt="Logbook in a parent's account with Maya picked at the top: Maya's screen time, a Stop Managing button, and a one hour limit on Web"><br><sub>A parent sets a child's screen time from their own account</sub></td><td width="50%"><img src="docs/screenshots/logbook-child.png" alt="Logbook in Maya's account saying a parent manages their screen time, with the Web limit shown but not changeable"><br><sub>The child sees the limits but can't change them</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/logbook-downtime.png" alt="Logbook with Maya picked: Downtime set to Custom, 9 PM to 7 AM Sunday to Thursday and 11 PM to 8 AM on Friday and Saturday, and Jot always allowed"><br><sub>Downtime with its own hours for each day of the week</sub></td><td width="50%"><img src="docs/screenshots/logbook-categories.png" alt="Logbook's Categories list: Productivity &amp; Finance, Utilities, Social with a 45 minute limit, Creativity, Entertainment, Information &amp; Reading, Other and Games with a one hour limit"><br><sub>One daily limit for every app of a kind</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/services.png" alt="Quill with the word lighthouse selected and the Quill menu open at Services: Make New Sticky Note with ⇧⌘Y, New Jot Note With Selection, Look Up in Words, Search With Seek and Speak Text, with Open URL and Show in Drawer greyed out"><br><sub>Services: use the selected words in another app</sub></td><td width="50%"><img src="docs/screenshots/services-sticky.png" alt="A sentence selected in Quill and a yellow sticky note beside it holding the same sentence, made with ⇧⌘Y"><br><sub>⇧⌘Y makes a sticky note from what's selected</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/keel-encrypt.png" alt="The installer's Encrypt your disk? page with Encrypt the disk switched on, and notes on the start-up password, the recovery key and Dials > Privacy &amp; Security"><br><sub>Encrypt the disk when installing</sub></td><td width="50%"><img src="docs/screenshots/keel-key.png" alt="freemac is installed: the recovery key in large letters, and Restart Now greyed out until I've written down my recovery key is ticked"><br><sub>The recovery key, shown once to write down</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/disk-unlock.png" alt="The black start-up screen with the freemac logo, a password field with six dots and Enter your password to unlock this disk"><br><sub>Type your password on the start-up screen to unlock the disk</sub></td><td width="50%"><img src="docs/screenshots/privacy-security.png" alt="Dials > Privacy &amp; Security: Disk Encryption On, with Change Disk Password and New Recovery Key buttons"><br><sub>Dials > Privacy &amp; Security: change the disk password or make a new key</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/tender-source.png" alt="Tender: Bring your files over, listing Sam's files from Windows on a drive called WINDOWS and a Lifeboat backup on a drive called BACKUP"><br><sub>Tender finds your old files on a Windows disk or a Lifeboat backup</sub></td><td width="50%"><img src="docs/screenshots/tender-choose.png" alt="Tender: Choose what to bring, with Documents, Pictures, Music, Videos, Desktop and Downloads ticked, each with its size, and the free space on this computer"><br><sub>Choose what to bring; nothing you have is overwritten</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/power-schedule.png" alt="Dials, Battery: the Schedule sheet, set to start up or wake on weekdays at 7:00 AM and shut down every day at 10:30 PM"><br><sub>Start up, sleep or shut down at set times</sub></td><td width="50%"><img src="docs/screenshots/power-countdown.png" alt="A window saying Your computer will shut down in 9:01, with Cancel and Shut Down buttons"><br><sub>Ten minutes' warning, and you can cancel</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/slipway-intro.png" alt="Slipway's Install “Pebble” window: the Pebble app's icon, version 2.4.1, 188 KB by Pebble Software, its description, and a note that the package was downloaded from pebble.example.org today, with Cancel and Install"><br><sub>Double-click a downloaded .deb: Slipway shows the app and where it came from</sub></td><td width="50%"><img src="docs/screenshots/slipway-done.png" alt="Slipway's Summary step: a green tick, The installation was successful, Pebble is installed, with Close and Open Pebble"><br><sub>Installed, with the app one click away</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/hatch-opened.png" alt="A disk image called Recipes opened by double-clicking it: its disk on the Desktop and in Drawer's sidebar with an Eject button, and its window in front showing Pancakes.txt and Soup.txt"><br><sub>Double-click an .iso or .img: it opens as a disk, like a USB drive</sub></td><td width="50%"><img src="docs/screenshots/hatch-hull.png" alt="Hull with Lakeside-Holiday.iso selected under Disk Images: a read-only disk image of 380.9 KB at /dev/loop1, with its path, and Eject"><br><sub>Hull lists open disk images and ejects them</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/applications-folder.png" alt="Drawer showing the Applications folder from its sidebar: About This Computer, Books, Buoy, Cairn, Chime and the rest of the 63 apps as icons"><br><sub>Applications in Drawer: every app on the computer</sub></td><td width="50%"><img src="docs/screenshots/app-info.png" alt="Gauge Info over the Applications folder: what Gauge does, Kind Application, Part of freemac, its version and Where Applications"><br><sub>⌘I on an app shows what it does and its version</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/restore-confirm.png" alt="Hull asking: Restore QEMU HARDDISK Media from Lakeside-Holiday.iso? Everything on the drive will be replaced by what is in the disk image, with Cancel and a red Restore button"><br><sub>Restore in Hull copies a disk image onto a USB drive</sub></td><td width="50%"><img src="docs/screenshots/restore-progress.png" alt="Hull's Restore window: restoring a USB drive from Family-Videos.img, 88.1 MB of 209.7 MB, with a Stop button"><br><sub>It shows how far it has got, and can be stopped</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/first-aid-ask.png" alt="Hull asking: Run First Aid on Photos? First Aid checks it for errors and repairs them if it can, with Cancel and Run"><br><sub>First Aid in Hull checks a drive for errors</sub></td><td width="50%"><img src="docs/screenshots/first-aid-repaired.png" alt="Hull saying: First Aid repaired Photos. It found problems on Photos and fixed them"><br><sub>…and repairs what it finds</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/image-from-drive.png" alt="Hull's New Image window: copying QEMU HARDDISK Media into Stick.img, 62.9 MB of 268.4 MB, with a Stop button"><br><sub>File > New Image from Drive copies a USB drive into an .img</sub></td><td width="50%"><img src="docs/screenshots/new-blank-image.png" alt="Hull's New Blank Image sheet: a name, a size of 100 MB and a choice of ExFAT, MS-DOS (FAT) or freemac (ext4)"><br><sub>New Blank Image: a USB drive you keep in a file</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/partition-sheet.png" alt="Hull's Partition sheet: a pie chart of a USB drive split into Photos, Backup and Music, with the name, format and size of the chosen volume beside it"><br><sub>Partition in Hull splits a drive into volumes on a pie chart</sub></td><td width="50%"><img src="docs/screenshots/partition-done.png" alt="Hull showing the USB drive afterwards: a GUID Partition Map with three volumes, Photos, Backup and Music, each in its colour on the bar"><br><sub>A drive with several volumes shows each one on its bar</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/battery-menu.png" alt="The Battery menu open from the menu bar: Battery 76%, Power Source: Battery, 4:00 remaining, a Low Power Mode switch, Using Significant Energy: Easel, and Battery Settings"><br><sub>The Battery menu: the charge, Low Power Mode and the apps using significant energy</sub></td><td width="50%"><img src="docs/screenshots/battery-charging.png" alt="The Battery menu while charging: Power Source: Power Adapter, Charging, 1:16 until full"><br><sub>Plugged in, it says how long until it's full</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/bluetooth-menu.png" alt="The Bluetooth menu open from the menu bar: Bluetooth switched on, Devices Sam's Headphones at 72% and Trackpad at 95% (connected, in blue) and Magic Keys, and Bluetooth Settings"><br><sub>The Bluetooth menu: click a device to connect or disconnect it</sub></td><td width="50%"><img src="docs/screenshots/bluetooth-off.png" alt="The Bluetooth menu with Bluetooth switched off, leaving only Bluetooth Settings"><br><sub>The switch at the top turns Bluetooth off</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/menu-extras.png" alt="An app's own icon in the menu bar with its menu open: Open Demo Mail, 3 Unread, Notify Me ticked, Check Speed with a submenu of Fast and Slow, and Quit Demo Mail"><br><sub>Menu bar extras: apps' own icons in the menu bar, with their menus</sub></td><td width="50%"><img src="docs/screenshots/ferry-menu-bar-items.png" alt="A Mac program run through Ferry with two menu bar items, a dot and the temperature 21°, and the temperature's menu open: Open_Forecast, Notify Me ticked, Not Now greyed out, Units with a submenu, and Quit"><br><sub>Mac programs' menu bar items, through Ferry</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/focus-menu.png" alt="The Focus menu open from the moon in the menu bar: Do Not Disturb on in blue, Sleep, Work and Personal, and Focus Settings…"><br><sub>The Focus menu: switch Focus, or turn it off, from the menu bar</sub></td><td width="50%"><img src="docs/screenshots/menu-bar-choices.png" alt="Dials settings with switches for Show Wi-Fi, Bluetooth, Sound, Battery and Focus in menu bar, all on"><br><sub>Choose which icons the menu bar shows</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/ferry-tables.png" alt="Drawn by Ferry for a Mac program: an outline list with Fruit opened to Apple, Pear and Plum, and a table of files with Name, Size and Done columns, sorted by size, with check boxes"><br><sub>Mac programs' lists and tables, drawn by Ferry</sub></td><td width="50%"><img src="docs/screenshots/now-playing.png" alt="Now Playing open from the music note in the menu bar: the album cover, Harbour Lights by The Tide Pool from Low Water, playing in Shanty, 2:11 gone and 1:22 left on a line, and back, pause and forward buttons; a magnifying glass for Seek sits beside the Quick Settings symbol"><br><sub>Now Playing in the menu bar, with Seek's magnifying glass beside it</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/ferry-documents.png" alt="Drawn by Ferry for a Mac program: a document window called Second.note with a sheet hanging from its title bar asking Do you want to revert to the most recently saved version of the document, with Cancel and Revert"><br><sub>Mac programs' documents and sheets, drawn by Ferry</sub></td><td width="50%"><img src="docs/screenshots/ferry-alert.png" alt="A Ferry alert asking Do you want to save the changes made to the document Report? with Save, Cancel and Don't Save"><br><sub>…and the Save, Cancel or Don't Save alert before closing</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/add-to-dock.png" alt="Web on the Harbour Friends website with the Add to Dock window open: the site's blue icon, the name Harbour, its address, and Cancel and Add"><br><sub>File > Add to Dock… in Web puts a website in the Dock</sub></td><td width="50%"><img src="docs/screenshots/web-app.png" alt="Harbour Chat open in its own window from the Dock, with Harbour Chat in the menu bar, no address bar or tabs, and a red 8 on its Dock icon for 8 new messages"><br><sub>It opens in its own window, with its unread count on its Dock icon</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/lifeboat-menu.png" alt="The Lifeboat menu open from the lifebuoy in the menu bar: Latest backup: Just now, Back Up Now, Browse Lifeboat Backups and Lifeboat Settings"><br><sub>Lifeboat in the menu bar: when you last backed up, and Back Up Now</sub></td><td width="50%"><img src="docs/screenshots/ferry-controls.png" alt="Drawn by Ferry for a Mac program: a toolbar, a pop-up list set to Large, a segmented control with Day, Week and Month, a search field, and a pop-up list open with Blue ticked"><br><sub>Mac programs' pop-up lists, segmented controls, search fields and toolbars, drawn by Ferry</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/wifi-menu.png" alt="The Wi-Fi menu open from the menu bar: Wi-Fi switched on, Known Networks Coffee Shop (joined, in blue) and Lakeside Guest, Other Networks Lakeside Home with a padlock, and Wi-Fi Settings"><br><sub>The Wi-Fi menu: click a network to join it</sub></td><td width="50%"><img src="docs/screenshots/wifi-password.png" alt="A window saying The Wi-Fi network Lakeside Home requires a WPA2 password, with a password field, Show password, Cancel and Join"><br><sub>A network with a padlock asks for its password</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/startup-disk.png" alt="Dials > Startup Disk: freemac, Windows, Ubuntu, a SanDisk USB stick and the DVD drive freemac is running from, with freemac chosen, Restart in freemac… and Always Start Up from This"><br><sub>Dials > Startup Disk: choose Windows, freemac or a USB stick</sub></td><td width="50%"><img src="docs/screenshots/startup-disk-restart.png" alt="An alert asking Restart in Windows? The computer restarts in Windows, just this once, with Cancel and Restart"><br><sub>Restart in Windows just once, then back to freemac</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/vpn-settings.png" alt="Dials > Network with a WireGuard VPN called home-vpn, connected, its switch on, Add VPN Configuration and Show VPN status in menu bar"><br><sub>VPN in Dials > Network: add a WireGuard or OpenVPN file</sub></td><td width="50%"><img src="docs/screenshots/vpn-menu.png" alt="The VPN menu open in the menu bar: home-vpn Connected, Disconnect home-vpn and Open VPN Settings"><br><sub>Connect or disconnect from the VPN menu</sub></td></tr>
</table>

## Download

Each finished milestone is published as a ready-made live ISO on the
[Releases page](https://github.com/dean-plude/freemac/releases), with its
SHA-256 checksum and the virtual machine settings that work. Boot it in
QEMU, virt-manager, VirtualBox or VMware without building anything. Every
image is started in QEMU with both BIOS and UEFI firmware before it is
published.

## Clean-room rules

These rules apply to every commit, issue and pull request. A change that breaks
one of them will be reverted.

1. **No Apple material.** No Apple source code, binaries, firmware, kexts,
   frameworks, fonts, icons, cursors, wallpapers, sounds, screenshots or other
   artwork, in the repository or in built images.
2. **No reverse engineering of Apple software.** Do not disassemble, decompile,
   trace or dump macOS or any other Apple software, and do not use tools that do
   so on your behalf. Do not copy code or data obtained that way by anyone else.
3. **Design from public descriptions only.** Behaviour is designed from how the
   user experience is publicly described (articles, reviews, user guides,
   general knowledge of how such desktops work) and implemented from scratch.
4. **Original names and look.** Components get original names. Window buttons,
   icons and themes are our own designs. Do not imitate Apple's exact shapes,
   colours or layouts pixel for pixel.
5. **No Apple trademarks.** Do not use Apple, Mac, macOS, Finder, Dock,
   Spotlight, Mission Control or similar marks as names of anything we ship.
   (The repository name `freemac` is a working project name; a final product
   name may be chosen before any public release.)
6. **Only compatible open-source parts.** Third-party code must be under a
   licence compatible with GPL-3.0-or-later and must be recorded in
   [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Target experience

| Feature | Our component | Status |
| --- | --- | --- |
| Global top menu bar with app menu, window menu, status icons, clock | **Topline** | 0.4: own bar with network, sound and battery icons; 0.5: clock opens the notification centre; 0.6: Lock Screen item; 0.8: GTK apps' own menus, Bluetooth and printing icons; 0.9: quick settings panel; 1.1: what's playing, with play/pause; 1.7: shortcuts in ⌘ symbols, the same app menu in every app, a Mac Window menu with Zoom; 1.8: slide along the bar between open menus, Settings… ⌘, in the app menu; 1.10: clicking the desktop makes Drawer the app in the bar, with File and Go menus; 1.12: Window > Fill and Center, and Hide leaves windows out of the Dock; 1.13: an app that stays open with no window keeps its name and menus in the bar, and the bar no longer switches to Drawer while ⌘Tab or Seek is up; 1.14: apps go by their short names, a Save dialog or alert keeps its app's menus, an app stays in front when its last window closes, and a window's commands are greyed out while its app has none; 1.15: an app with no window open keeps its shortcuts (⌘N in Jot); 1.16: apps that share no menus (Web, Firefox, VLC, Qt apps) still get File, Edit and Window menus, whose items press the app's own shortcuts; 1.17: Help in every app, where you type to find any menu item and press Return to run it; 1.19: Help closes on a click outside it; 1.20: Help lists Guide topics under the menu items; 1.21: Guide in the freemac menu, and Seek no longer lists open windows' names; 1.22: the clock opens a month calendar with the day's events from Tide; 1.25: an app's menus never show under another app's name while it opens or quits; 1.41: follows a new time zone at once; 1.51: Window > Move & Resize puts a window in a half or a quarter of the screen and back, and submenus in the bar open when the pointer rests on them; 1.64: hides itself until the pointer reaches the top of the screen (Dials); 1.70: the freemac menu in a Mac's order with Harbor, Recent Items (apps and documents, Clear Menu) and Sleep; Restart, Shut Down and Log Out (⇧⌘Q) ask first with a 60-second countdown and let each app save before going on; 1.74: an orange dot while an app is using the microphone and a green one for the camera, with the app's name a click away; the status icons on the right always take clicks; 1.76: low-battery warnings, sleeps at 2%; 1.80: the input menu (US, GB, DE…) switches keyboard layouts, as does ⌃Space; 1.95: rest the pointer on a window's green button for a menu of halves, quarters, Fill, Centre, Left & Right and Return to Previous Size |
| Bottom dock with magnification, running indicators | **Pier** | 0.4; 1.0: Downloads folder and a Trash you can empty; 1.2: icons bounce while an app starts and rise out of the dock when magnified; 1.9: drag apps along it or off it, drop files on an app to open them; 1.10: drop files on a Dock folder to move them there; 1.12: a minimized window shows as its own small picture beside the Trash; 1.13: Quill and Jot keep their dot with no window open, and clicking one opens a new window; 1.14: apps open at login get their dot straight away; 1.38: the app's name shows above its icon, magnification follows the pointer over the icons, a crowded Dock shrinks to fit the screen, and windows behind the Dock's clear top stay clickable; 1.42: hides itself until the pointer reaches the bottom of the screen (Dials or ⌥⌘D); 1.59: an app's menu lists the files it had open lately, and a right-click between the icons turns hiding and magnification on or off; 1.61: up to three apps used lately stay in the Dock after they quit, with Remove from Dock and a switch in Dials; 1.62: switches for the open-app dots and the bounce while an app opens; 1.63: sits on the left, bottom or right of the screen (Dials or its right-click menu), and desktop icons keep clear of it |
| Desktop wallpaper that fills any screen shape; files on the Desktop as icons | **Backdrop** | 0.4; 1.4: desktop icons; 1.25: USB drives, memory cards and phones mount as they're plugged in and show on the Desktop; drag one to the Trash to eject it; 1.26: copy, paste, Duplicate and Undo on the Desktop, and drop files onto a folder icon; 1.44: Use Stacks piles the Desktop's files by kind (a click fans a stack out), Clean Up By Name, Kind or Date Modified, and Get Info; 1.45: desktop widgets (clock, calendar, weather, reminders) you can drag anywhere; Edit Widgets… adds and removes them; 1.135: Battery, Screen Time, World Clock, Sticky Note and Photo widgets; 1.46: Space opens Glance on desktop files, and the arrow keys move from icon to icon; 1.48: tag desktop files with a colour from their menu; 1.49: New Folder with Selection; 1.50: Rotate Left, Rotate Right and Create PDF on pictures; 1.52: Show Item Info puts a picture's size or a folder's item count under its name; 1.55: Rename Items for several files at once; 1.57: Show View Options (⌘J) for icon size, grid spacing and text size; 1.67: click the wallpaper to reveal the desktop |
| Alt+Tab app switcher with large icons | **Tack** | 1.4; 1.13: apps open with no window are listed too, and picking one opens a window; 1.60: Q quits and H hides the chosen app while the switcher is up, hidden apps are dimmed, and a hidden app comes back whole; 1.62: ⌘← and ⌘→ move along the row |
| Window manager: left-side window buttons in our own style, window overview, virtual desktops | **Strata** (Wayfire config + theme) | 0.4: overview, 4 desktops, left buttons in freemac style on GTK apps; 0.8: own title bars for every app (strata-decor); 0.9: drag a window to an edge to tile it; 1.2: rounded title bars with round buttons that show their symbols on hover; 1.3: all four corners round, our own pointer, new windows clear of the menu bar; 1.12: minimizing shrinks a window down into its place in the Dock; 1.14: Save dialogs and alerts come down from the title bar as sheets and move with their window; 1.15: ⌘. cancels a dialog |
| File manager with icon, list, column and gallery views | **Drawer** | 0.4; 1.0: tabs, a sidebar you can change, Glance preview on Space; 1.1: compress to .zip, open .zip and tar archives; 1.2: Mac apps (.app) shown with their own icon; 1.6: Get Info (⌘I); 1.11: Favorites and Locations sidebar with blue icons; 1.21: Glance shows the first page of a PDF; 1.25: drives under Locations with an Eject button (⌘E); 1.25: Share, to mail files in Post or copy them to a drive; 1.26: copy and paste files (⌘C, ⌘V, ⌥⌘V to move), Duplicate (⌘D), drag onto folders, sidebar places and drives, a progress window with Stop, Keep Both or Replace for a taken name, and Undo (⌘Z); 1.46: pictures and PDFs show as small pictures of themselves, and Glance plays movies and music, shows every PDF page, steps through several files and fills the screen; 1.47: Put Back and Empty in the Trash, Open With, Sort By name, kind, date or size, a path bar (⌥⌘P) and Go to Folder (⇧⌘G); 1.48: coloured tags, with a dot after the name and a sidebar list of each colour's files; 1.49: Recents (⇧⌘F) with Show in Enclosing Folder, New Folder with Selection, and tags in Get Info; 1.50: spring-loaded folders (hold a drag on a folder to open it) and Quick Actions to rotate pictures or make a PDF of them; 1.52: a status bar with the item count, how many are selected and the space left (⌘/), and View > Show Sidebar; 1.53: Gallery view (⌘4), the chosen file large over a strip of the others, and the chosen files stay chosen when the view changes; 1.54: a Preview pane (⇧⌘P) with a large picture of the chosen file and its information; 1.55: Rename Items, to rename several files at once by replacing text, adding text or numbering them; 1.56: View Options (⌘J): icon size, grid spacing, text size, Show Item Info and Sort By; 1.72: Get Info shows which app opens a document, and Change All… makes another app open every document of that kind; 1.83: Connect to Server (⌘K) for shared folders on other computers (smb, sftp, ftp, WebDAV); 1.84: Network in the sidebar (⇧⌘K), the computers and shared drives nearby; 1.85: a computer in Network that shares several folders shows them to pick one, and a folder shared for everyone opens without asking for a password; 1.87: search This Mac from the toolbar, by name or by words inside documents, narrowed by kind and date, and Smart Folders that keep a search in the sidebar (⌥⌘N); 1.102: Drawer > Settings (⌘,): the folder new windows open in, the warning before emptying the Trash, removing items from the Trash after 30 days, and keeping folders on top |
| Full-screen grid of all apps (F4) | **Marina** | 1.2; 1.3: folders, and apps can be dragged into any order |
| ⌘Space search launcher (apps, files, sums) | **Seek** | 0.4; 1.0: finds files by the words inside them; 1.18: finds settings pages and the front app's menu items; 1.19: closes on a click outside it; 1.20: a preview of the chosen file, picture or app beside the results, and Guide topics; 1.21: a PDF's first page in the preview, and a nearly solid panel; 1.23: finds contacts, events and reminders, and opens faster; 1.68: unit conversions (5 km, 70 f to c, 2 cups in ml); 1.88: Dials > Seek chooses what it lists and keeps folders private; 1.171: type a word to see what it means, with Return opening it in Words |
| Settings app with light and dark mode | **Dials** | 0.4: appearance, wallpaper, dock, displays, trackpad and mouse, keyboard, network and Wi-Fi, about; 0.5: sound, power, notifications, accessibility; 0.7: users, Bluetooth, printers; 0.9: brightness, night light, changeable shortcuts; 1.6: Command key choices, start-up sound switch; 1.9: what a title-bar double-click does; 1.10: a grouped sidebar with each icon in a coloured tile; 1.11: search in the sidebar; 1.12: minimize windows into their app's icon; 1.19: opens in about half the time, building each page when it's first shown; 1.20: starts faster again, as every freemac app does, now that their code is compiled ahead in the image; 1.41: Date & Time (time zone by city, automatic time, 12 or 24 hours, day, date and seconds in the menu bar); 1.51: screen zoom on or off, and which key to hold while scrolling; 1.65: Reduce transparency and Invert colours (⌃⌥⌘8) in Accessibility; 1.66: Login Items, the apps that open when you log in; 1.71: Software Update page (Check for Updates, and security fixes installed automatically) and Network > Firewall, both behind an administrator's password; 1.72: choose the default web browser and email app; 1.73: Speak selection: select words in any app and press ⌥Esc to hear them read aloud, with a choice of voice and speed; 1.75: Accent colour (blue, purple, pink, red, orange, yellow, green, graphite) for every app, light and dark; 1.76: battery time left and Show percentage; 1.79: Sharing (computer name, Nearby sharing, Remote Login); 1.80: Input Sources (type in up to four languages or layouts, picked by name) and key repeat speed; 1.81: Check spelling while typing (red underlines and right-click corrections in every app where you write); 1.82: Text Replacements (omw becomes On my way!), smart quotes and dashes, and a full stop with a double space; 1.85: File Sharing, which shares your Public folder with the other computers on the network, to look at but not change; 1.86: Screen Sharing, so someone at another computer on the network can see and use this screen after signing in with your password; 1.88: Seek (what Seek lists, private folders it and Drawer leave out, Rebuild Index); 1.90: Users > Guest User, an account anyone can log in to without a password, whose files are erased when they log out; 1.91: Sound Effects (an alert sound of six, played at its own volume whenever an app can't do something, a pop as the volume changes, and a crumple and a shutter for the Trash and screenshots); 1.92: Displays shows each display's resolution, refresh rate, size of text and icons and rotation, asks "Keep these display settings?" for 15 seconds after a change, and with two or more displays lets you drag them into place and mirror one on another; 1.93: Use as Main display, or drag the white bar in the picture, to choose which display has the menu bar, the Dock and the files on the Desktop; 1.94: Flash the screen when an alert sound occurs, in Accessibility, with a Test Screen Flash button; 1.96: Shake mouse pointer to locate, in Accessibility: move the mouse quickly back and forth and the pointer grows big for a moment; 1.97: Press and hold for accents, in Keyboard: hold a letter such as e in a text field to pick é, è, ê and the rest from a small panel by the text cursor; 1.98: Sticky Keys, in Accessibility: tap ⇧, ⌃, ⌥ or ⌘ and it stays down for the next key, tap twice to lock it, or press Shift five times to turn it on or off; 1.99: Colour filters, in Accessibility: the screen in greys, adjusted for red/green or blue/yellow colour blindness, or tinted, at the intensity you choose; 1.100: Background sounds, in Accessibility: balanced, bright or dark noise, ocean, rain or a stream, playing steadily behind everything else at its own volume; 1.101: Appearance can be Auto (light while the sun is up, dark after it sets, where your time zone says you are), and Night Light can run from sunset to sunrise; 1.104: Pointer outline and fill colours, in Accessibility: the pointer drawn in any two colours, with Reset |
| Notifications with banners, a history list and Do Not Disturb | **Beacon** | 0.5; 1.58: notifications from one app stack together, Do Not Disturb on a daily schedule, and a choice for each app (Banners, Notification Centre only or Off) in Dials; 1.129: Focus, with Sleep, Work and Personal beside Do Not Disturb, each with its allowed apps and set times |
| Screenshots of the screen, an area or a window (⇧⌘3, ⇧⌘4 or the Print key) | **Lens** | 0.5; 1.1: screen recording (Ctrl+Print); 1.7: a small picture in the corner after each screenshot; 1.21: clicking it opens the screenshot in Frame, not the web browser; 1.78: the Screenshot toolbar on ⇧⌘5, with Options for where to save, a timer and the thumbnail |
| Notes, saved as plain text files as you type | **Jot** | 1.1; 1.13: stays open with no window, and File > New Note works from the menu bar; 1.14: hints show ⌘N; 1.15: ⌘N works with no window open |
| Short how-to topics (the Command key, windows, screenshots, Wi-Fi and more), found from Help and Seek | **Guide** | 1.20; 1.21: also in the freemac menu and on Welcome's last page |
| Volume, brightness and media keys with an on-screen level | freemac-keys, **Beacon** | 1.1 |
| Clipboard history (Super+Shift+V) | freemac-clips | 1.1 |
| Hot corners | **Strata**, Dials | 1.1 |
| Force Quit window on ⌥⌘⎋ for an app that has stopped answering | **Force Quit**, Strata | 1.9 |
| Alerts in a small panel with the app's icon on top and equal buttons, used by every freemac app | alert.py, theme | 1.10 |
| Text editor | **Quill** | 0.5; 1.13: stays open with no window; ⌘Q asks about unsaved changes, then quits; 1.15: a small Save sheet (name and where) that opens out to the full browser |
| Picture and PDF viewer | **Frame** | 0.5; 1.21: opens PDFs, page by page, and is the default for them; 1.22: Markup (⇧⌘A): draw, boxes, text and a signature drawn once on a pad, saved as a copy beside the original; 1.25: Share; 1.124: Live Text, select and copy the words in a picture |
| Calendar with day, week and month views, events that repeat, kept as a standard .ics file | **Tide** | 1.22; 1.23: notices before events, Crew's birthdays; 1.24: online calendars; 1.25: a colour for each calendar and a Calendars list to show or hide each one, with a month to jump from |
| Contacts, kept as one standard .vcf card per person | **Crew** | 1.22; 1.24: online address books |
| Reminders in coloured lists, with due dates, flags and a notice when one is due | **Nudge** | 1.23; 1.24: online reminder lists |
| Internet Accounts: sign in once (iCloud, Fastmail, Yahoo, Nextcloud or any CalDAV and CardDAV server) and its calendars, contacts and reminders stay in step both ways | **Dials**, freemac-sync | 1.24 |
| Emoji and symbols: search or browse, then type the chosen one into the app in front (Control-⌘-Space, or Edit > Emoji & Symbols) | **Glyph** | 1.24 |
| Photos: everything in your Pictures folder by month, a large view with favourites, and import from a camera, phone or memory card | **Cove** | 1.24; 1.25: albums you make and name, photos added by drag or right-click, and a slideshow of any album or the whole library; Share, to mail photos or copy them to a drive |
| Music: the songs in your Music folder by album, artist and song, with album covers, shuffle and repeat, songs played one after another with no gap, and the media keys and menu bar's what's playing | **Shanty** | 1.27 |
| Videos: plays them in a window or full screen, with controls that fade away, and starts each where you stopped | **Reel** | 1.28 |
| Picture in Picture: a video in a small window that floats above the others in a corner while you work, and drags anywhere | **Reel**, **Strata** | 1.105 |
| Dynamic wallpaper: freemac's own scenes follow the sun where you are, day while it's high, golden as it sets, then night | **Backdrop**, **Dials** | 1.106 |
| Mission Control: drag a window up onto one of the desktops along the top to move it there | **Strata**, **Topline** | 1.109 |
| Mission Control: add a desktop with + (or drag a window onto it), close one with the button on its corner; the count is kept | **Strata**, **Topline** | 1.110 |
| Dock > Options > Assign To: keep an app on All Desktops or on This Desktop (its windows open there and take you there) | **Pier**, **Strata** | 1.111 |
| App Exposé: Ctrl+Down, a four-finger swipe down, or Dock > Show All Windows spreads out just the windows of one app | **Strata**, **Pier** | 1.112 |
| Screen reader: Command+F5 (or Dials > Accessibility) speaks what's on the screen, the control you move to and what you type, and comes back at the next login | **Dials**, **Strata**, Orca | 1.120 |
| Hover Text: hold Command and point at some words to see that line large above the pointer, in any app (Dials > Accessibility) | **Strata**, **Topline**, Tesseract | 1.125 |
| Slow Keys: a key counts only once it has been held for a moment, so keys brushed by accident aren't typed, with a click as each one goes down and counts (Dials > Accessibility) | **Strata**, **Topline**, Dials | 1.126 |
| Accessibility Keyboard: a keyboard on the screen to type with the pointer alone, with Shift, Control, Option and Command held for the next key (Dials > Accessibility) | **Topline**, **Strata**, Dials | 1.127 |
| Mouse Keys: move the pointer and click with the number keypad, or press Option five times to turn it on (Dials > Accessibility) | **Strata**, Topline, Dials | 1.128 |
| Accessibility Shortcuts: press Option-Command-F5 anywhere for a panel that turns the screen reader, Zoom, Sticky, Slow and Mouse Keys, the Accessibility Keyboard, Hover Text, Invert Colours, Colour Filters, Increase Contrast and Reduce Transparency on or off; Dials > Accessibility chooses which it lists, and with one chosen the keys turn it on or off at once | **Accessibility Shortcuts**, Dials | 1.169 |
| Focus: Do Not Disturb, Sleep, Work and Personal, picked from Quick Settings or the Notification Centre, each letting through only the apps you choose and turning on by itself at set times on chosen days (Dials > Focus) | **Beacon**, Topline, Dials | 1.129 |
| Spoken Content: hold ⌘ and point at some words to hear them, and have notifications and the time (on the hour, half or quarter hour) read out (Dials > Accessibility) | **Topline**, **Beacon**, **Strata**, eSpeak NG | 1.130 |
| Widgets on the desktop and in the Notification Centre: clock, calendar, weather, reminders, battery, Screen Time, world clocks, the newest sticky note and a photo of the day, added from one gallery | **Backdrop**, **Beacon** | 1.135 |
| Lock screen with Now Playing and its buttons, the notifications that came while locked (Show previews chooses what they say), the battery, and a message such as how to return a lost computer | **Latch**, Dials | 1.136 |
| Fast user switching: with more than one account, your name in the menu bar lists everyone, and someone else logs in while your apps keep running behind your lock screen | **Topline**, **Gangway**, Dials | 1.137 |
| Screen Time for a family: a parent picks a child's account in Logbook and sets their limits, Downtime and Always Allowed apps, which the child sees but can't change; when time's up, a parent types their password on the child's screen for 15 more minutes | **Logbook** | 1.138 |
| Screen Time schedules and categories: Downtime with different hours for each day of the week, and one daily limit for every app of a kind (Games, Social, Entertainment and more), for yourself or a child | **Logbook** | 1.139 |
| Services: select words in any app and choose Make New Sticky Note (⇧⌘Y), New Jot Note, Look Up in Words, Search With Seek, Speak Text, Open URL or Show in Drawer from the app's menu; New Terminal at Folder and Set Desktop Picture in Drawer; shortcuts and which ones show in Dials > Keyboard. New shortcuts and settings from a newer freemac reach accounts made before it | **Topline**, Drawer, Stickies, Jot, Words, Seek, Dials | 1.140 |
| Encrypted disk: turn on "Encrypt the disk" when installing, unlock it with your password on the start-up screen, and keep the recovery key it shows; Dials > Privacy & Security changes the disk password or makes a new key, and your login password keeps it in step | **Keel**, Dials | 1.141 |
| Tender, to bring your files over from your old computer: a Lifeboat backup, a Windows PC's disk (OneDrive too) or another computer's disk; it merges and never overwrites, and can bring your settings from a Lifeboat backup | **Tender**, Welcome | 1.143 |
| A power schedule: start up or wake at a set time, and sleep, restart or shut down at another, every day, on weekdays or at weekends; anyone logged in gets a ten-minute countdown and can cancel | **Dials** > Battery > Schedule… | 1.144 |
| Startup Disk: choose whether the computer starts up from freemac, Windows, another system or a USB stick, just once (Restart in…) or for good | **Dials** > Startup Disk | 1.145 |
| Install an app downloaded from a website as a .deb file: double-click it to see the app, its publisher and where it came from, install it with an administrator's password, open it and move the download to the Trash | **Slipway** | 1.146 |
| Disk images: double-click an .iso or .img to open it as a disk on the Desktop and in Drawer, and eject it when you're done; Hull lists open images, and File > New Image from Folder makes an .img holding a copy of a folder | **Hatch**, Hull | 1.147 |
| An Applications folder in Drawer's sidebar (⇧⌘A): every app on the computer, opened with a double-click; ⌘I shows what an app does, its version and size; the Trash points to Harbor to remove one | **Drawer** | 1.148 |
| Restore in Hull: copy an .iso or .img onto a USB drive, byte for byte, to make a stick that starts up freemac or another system; it shows its progress and can be stopped | **Hull** | 1.149 |
| First Aid in Hull: check a volume, or every volume on a drive, for errors and repair them; it unmounts while it checks and mounts again after | **Hull** | 1.150 |
| Partition in Hull: split a USB drive into up to eight volumes on a pie chart, each with its own name, format and size (drag between slices to resize); a drive with several volumes shows each one in colour on its bar | **Hull** | 1.151 |
| New Image in Hull: File > New Blank Image… makes an empty disk image of any size and format that opens like a USB drive, and New Image from Drive… copies a USB drive, disc or volume into an .img that Restore can put back | **Hull** | 1.152 |
| A Battery menu in the menu bar: the charge, the power source, time remaining or until full, a Low Power Mode switch, and the apps using significant energy (click one to open Gauge) | **Topline** | 1.154 |
| Menu bar extras: apps that show an icon while they run (chat, cloud storage, password managers) get it in the menu bar, with their menus; Topline is the StatusNotifierItem host that Linux apps look for | **Topline** | 1.156 |
| A Wi-Fi menu in the menu bar: networks you've joined, then the others with their signal and a padlock if they need a password; click one to join (a password is asked once and remembered), click the one you're on for its address, signal and channel, or switch Wi-Fi off and on | **Topline** | 1.153 |
| Now Playing in the menu bar while music or a video plays: the cover, the track, how far it has got, and back, play or pause and forward; and Seek's magnifying glass, as ⌘Space; either can be hidden in Dials > Dock and Menu Bar | **Topline**, Dials | 1.162 |
| Open in Web: a website in the Dock can show the page it's on in Web, with the address bar and tabs, from its File menu | **Web**, Topline | 1.168 |
| Unread counts on websites in the Dock: a red badge with the number a site shows in its title, such as Facebook's (3), on its Dock icon | Dock | 1.166 |
| Add to Dock for websites: File > Add to Dock… in Web puts a website in the Dock with its own icon and name; it opens in its own window, keeps its own sign-in, and is deleted with Options > Delete Web App… | **Web**, Dock | 1.165 |
| Lifeboat in the menu bar: a lifebuoy that turns while a backup runs, with when the latest backup was made, Back Up Now or Skip This Backup, and Browse Lifeboat Backups | **Topline**, Lifeboat | 1.163 |
| Aliases: File > Make Alias in Drawer and on the Desktop, or hold ⌥⌘ while you drag, makes a stand-in with a small arrow on its icon that opens the original from anywhere; Show Original (⌘R) finds it, Get Info says where it is, and an alias whose original is gone offers Delete Alias or Fix Alias… | **Drawer**, Desktop | 1.172 |
| Custom icons and comments: click the icon in an item's Info window (⌘I) and paste a picture (⌘V) or drop one on it to give a file or folder its own icon in Drawer and on the Desktop, Delete to take it off; a Comments box keeps a few words with the item, and Seek finds them | **Drawer**, Desktop, Seek | 1.174 |
| List view options: View Options (⌘J) in list view picks the columns to show, relative dates (Today, Yesterday) or full ones, and Calculate all sizes, which adds up every folder so sorting by Size shows the biggest | **Drawer** | 1.175 |
| Locked files and folders: tick Locked in Get Info (⌘I) and the item shows a padlock, no app can change it, a locked folder keeps its items, and Drawer won't rename it and asks before moving it to the Trash | **Drawer**, Desktop | 1.176 |
| Change picture: the wallpaper moves on by itself every few minutes, every hour, every day or at each login, through freemac's wallpapers or a folder of your pictures, in order or shuffled | **Dials**, Desktop | 1.177 |
| Sharing and permissions in Get Info: choose Read & Write, Read only or No Access for the owner, the group and everyone, and give a folder's privileges to everything inside it | **Drawer** | 1.179 |
| Edit > Show Clipboard: a window showing what's on the clipboard now (words, a picture or files), changing as soon as anything is copied | **Drawer** | 1.185 |
| Get Summary Info (⌃⌘I): one Info window for several items, with their total size, and a tag or lock set on all of them at once | **Drawer** | 1.183 |
| Press and hold Back or Forward in Drawer (or right-click it) for the folders it goes through, and jump straight to one | **Drawer** | 1.182 |
| Go > Recent Folders: the last ten folders opened in Drawer, newest first, shared by every Drawer window, with Clear Menu | **Drawer** | 1.181 |
| The Inspector (⌥⌘I): one Info window that floats at the side and changes as you choose items, and Copy as Pathname (⌥⌘C), which copies the full path; holding Option changes the shortcut menu to both | **Drawer** | 1.180 |
| VPN: add a WireGuard (.conf) or OpenVPN (.ovpn) file in Dials > Network, turn it on with its switch, and connect or disconnect from the VPN menu in the menu bar | Dials, **Topline** | 1.142 |
| Software Update for freemac itself: a new version shows in Dials with what's new, downloads while you work, installs while the computer restarts, and Recovery can undo it | **Dials**, **Beacon**, **Recovery** | 1.134 |
| Battery in Dials: its level over the last 24 hours, time on battery for each of the last 10 days, Battery Health with maximum capacity and charge cycles, and Low Power Mode (always, or only on battery or on the adapter) with a yellow battery in the menu bar | **Dials**, **Topline**, power-profiles-daemon | 1.133 |
| Storage in Dials: what fills the disk on a coloured bar, how much is left, Empty Trash, and Review Files for the biggest files to move to the Trash | **Dials**, Drawer | 1.132 |
| Sound menu: the volume and the outputs to play through from the speaker in the menu bar; Balance and Input level in Dials > Sound; Play stereo audio as mono in Dials > Accessibility | **Topline**, **Dials**, PipeWire | 1.131 |
| Live Text: Frame finds the words in a picture or a scanned PDF, so you can select and copy them (⌘C), or light up all of them with the Live Text button | **Frame**, Tesseract | 1.124 |
| Verification codes: Purser keeps the six-digit codes for two-step sign-in beside each login, set up from a website's setup key or its QR code read straight off the screen | **Purser** | 1.123 |
| Passwords: Web saves and fills in website logins in a keychain opened by your login password, and Purser shows, copies, changes and checks them (reused or easy to guess), with Wi-Fi passwords too | **Purser**, **Dials**, gnome-keyring | 1.122 |
| Known Wi-Fi networks in Dials > Network: show or copy a saved password after an administrator's password, a QR code a phone scans to join, join automatically, forget | **Dials** | 1.121 |
| Dials shows a red count beside Software Update when updates are ready, and Dock badges come back if the Dock restarts | **Dials**, **Pier** | 1.118 |
| Software update notices: freemac looks for updates once a day, says when some are ready, and Harbor's Dock icon shows how many | **Beacon**, **Harbor**, **Pier** | 1.117 |
| Windows come forward when you ask: open a link or an app that's already open and its window comes to the front, on its own desktop; an app in the background that needs you bounces in the Dock until you go to it | **Strata**, **Pier** | 1.116 |
| Dock badges: a red number on an app's icon for unread mail in Post, reminders due in Nudge, or any app that sends a count | **Pier**, **Post**, **Nudge** | 1.115 |
| Mission Control on an empty desktop: Control+Up still shows your desktops along the top, so you can pick one or add another | **Strata**, **Topline** | 1.114 |
| Full screen gets its own desktop: the window slides onto a new desktop named after its app in Mission Control, and slides back when it leaves full screen | **Strata**, **Topline** | 1.113 |
| Mission Control: the window overview names your desktops along the top; move the pointer up to see a picture of each, and click one to go there | **Strata**, **Topline** | 1.108 |
| Stage Manager: the app you're using stands alone in the middle, the apps you used just before it wait as small pictures down the left, and a click brings one forward | **Pier**, **Strata**, **Quick Settings** | 1.107 |
| Keep the screen on while a video plays, or for as long as you ask (`caffeinate` in Terminal) | **Strata**, **Latch** | 1.103 |
| Activity Monitor: each app's share of the processor and memory, every process if you like, a graph of the last two minutes, and Quit or Force Quit for one that's stuck | **Gauge** | 1.28 |
| Disk Utility: every drive with how full it is, and Rename, Erase (ExFAT, MS-DOS or ext4) and Eject, with no password for USB drives | **Hull** | 1.28 |
| Camera: take pictures of yourself after a 3, 2, 1 countdown, with fun effects that bend and colour the picture | **Pose** | 1.29 |
| Weather: now, the next 24 hours and the next 10 days for the places you add, no account needed | **Sky** | 1.29 |
| Sticky notes: little coloured notes that stay on the desktop and come back after a restart | **Stickies** | 1.29 |
| Voice Memos: record with one big button, play back, rename and trim, kept in Music/Echo | **Echo** | 1.30 |
| Drawing: pens, a highlighter, shapes, text, stickers, an eraser and undo on a big canvas, kept as you go and exported as a picture | **Easel** | 1.30 |
| Chess against the computer (Easy, Medium, Hard) or a friend on the same screen, with hints and take-backs | **Rook** | 1.30 |
| Patience (solitaire): drag cards or double-click to send them home, draw one or three, undo, hints, and the cards finish themselves | **Patience** | 1.31 |
| Mines: clear a field in three sizes; the first click is always safe, right-click flags, best times kept | **Mines** | 1.31 |
| Read EPUB e-books: a shelf with covers, page by page, a contents list, bigger text, light, sepia or night pages, and your place kept | **Books** | 1.31 |
| Play the piano with the mouse or the keyboard: piano, organ, music box, flute and synth sounds made by freemac itself, and record a tune to play back | **Ivory** | 1.32 |
| A dictionary that works without the internet: what a word means, examples, words that mean the same or the opposite, and a word of the day (from WordNet) | **Words** | 1.32 |
| Learn to type: lessons that add a few keys at a time, a keyboard that shows the next key and which finger to use, speed, accuracy and stars kept | **Typist** | 1.32 |
| Screen time: how long each app was used today and over the week, and daily limits with a warning before time is up and an optional passcode | **Logbook** | 1.33; 1.69: Limit adult websites, for the whole computer; 1.89: Downtime (hours away from the screen when only Always Allowed apps work), Always Allowed apps with no limit, and 15 More Minutes behind the passcode; 1.138: a parent manages a child's account from their own; 1.139: Downtime for each day of the week and limits for categories of apps |
| A number puzzle (sudoku) from easy to expert, with pencil marks, hints, undo and best times | **Nine** | 1.33 |
| A font book: every font in all its styles, a sample you can type, and adding or removing fonts (double-click a font file to install it) | **Typecase** | 1.33 |
| A memory game: turn over two cards at a time to find the pairs, alone or with two players taking turns | **Pairs** | 1.34 |
| A graphing calculator: type equations such as y = x^2 or sin(x), see them in colour, zoom and drag, and read off any point | **Plot** | 1.34 |
| A whiteboard: sticky notes, text, shapes, arrows and pictures on a big board, with as many boards as you like | **Corkboard** | 1.34 |
| A jigsaw puzzle: real-shaped pieces cut from a built-in picture or one of your own photos, 12 to 100 pieces, that click together when they fit | **Jigsaw** | 1.35 |
| About this computer: processor, memory, graphics and storage at a glance, and a full system report you can copy | **Manifest** | 1.35 |
| A colour picker: pick a colour from anywhere on the screen with a magnifying loupe, copy it as hex, RGB or HSL, and keep a palette | **Swatch** | 1.35 |
| A shape puzzle: slide, turn and flip seven pieces to fill an outline, with twelve shapes from a square to a cat and a hint when you're stuck | **Tangram** | 1.36 |
| Podcasts and news feeds: subscribe by a feed or a website's address, read new posts, and play episodes at the speed you like with your place kept | **Buoy** | 1.36 |
| A word search: find hidden words in a grid, with twelve themes, three sizes and best times | **Hunt** | 1.36 |
| Four in a row: drop counters into a stand against the computer at three levels or a friend | **Fourway** | 1.37 |
| Draughts (checkers) with compulsory jumps and kings, against the computer at three levels or a friend, with the legal moves marked | **Kings** | 1.37 |
| Tile-matching solitaire: clear stacks of picture tiles by matching free pairs, in four layouts that can always be cleared | **Cairn** | 1.37 |
| Maths practice for children: adding, taking away, times tables and sharing at five levels each, with stars and a times-table chart | **Sums** | 1.38 |
| Flashcards: decks of questions and answers, studied so the cards you know least come back most often, and brought in from a spreadsheet file | **Cue** | 1.38 |
| Scanning from USB and network scanners and all-in-one printers: preview, pick part of the glass, colour and resolution, and save a many-page PDF or pictures | **Glass** | 1.38 |
| Spreadsheets: cells with formulas (SUM, AVERAGE, IF, COUNTIF and more), number formats, fill down, sorting, charts of the selected cells, and CSV files | **Ledger** | 1.39 |
| Presentations: slides with a title, points and a picture in six original themes, a full-screen show and PDF export | **Lantern** | 1.39 |
| Nearby sharing: send files over Wi-Fi to other freemac computers and to phones with the free LocalSend app; offers ask before anything is taken, and land in Downloads | **Hail** | 1.77 |
| Screen Sharing viewer: see and use another computer on the network that shares its screen (freemac, or any VNC computer such as a Mac), after signing in with that computer's name and password; encrypted, and it warns if the computer isn't the same one as before | **Porthole** | 1.86 |
| Mail: your IMAP accounts' mailboxes, reading with pictures from the internet held back until you ask, replying, forwarding, attachments and drafts | **Post** | 1.24; 1.25: a new message with files attached when you Share from another app |
| Backups: your home folder copied to a drive every hour, earlier backups kept with unchanged files shared, and any file or folder brought back from a backup chosen by date | **Lifeboat** | 1.27 |
| Recovery: hold Ctrl as the computer starts to bring back a backup, reset a password, check a disk or reinstall | **Recovery** | 1.40 |
| Runs simple Intel Mac command-line programs (optional add-on) | **Ferry** | 0.5: first version |
| App centre for open-source apps, with system updates | **Harbor** | 0.6 |
| Lock screen (Ctrl+Command+Q, idle and before sleep) | **Latch** | 0.6; 1.3: laid out like the login screen; 1.43: waits for the screen saver to end, then asks for the password; 1.136: Now Playing, notifications, battery and a message |
| Screen savers: Drift, Clock and Album (your photos) | **Screen Saver** | 1.43: chosen in Dials > Screen Saver, starts after a few idle minutes or from a hot corner |
| Calculator | **Tally** | 0.6 |
| Clock with world clocks, alarms, timers and a stopwatch | **Chime** | 0.6 |
| Original app icons, folder and file icons, and day/night wallpapers | freemac theme | 0.7: 10 app icons, 17 folder and file icons, 4 wallpaper scenes; 1.2: every app's icon on the same rounded tile, a full GTK theme of our own, Inter as the system font |
| Start-up screen instead of a boot menu and text | build | 1.2 |
| First-run setup: light or dark, wallpaper, Wi-Fi, shortcuts | **Welcome** | 1.0 |
| Installer | **Keel** | 0.4: whole-disk install, BIOS and UEFI |
| Login screen | **Gangway** | 0.4; 1.2: blurred wallpaper, round picture, password field with an arrow; 1.90: the Guest User logs in with just the arrow, and the login screen comes back after logging out (it was black); 1.137: people already logged in are marked, and the arrow goes back to their session |
| Sound (PipeWire) with a volume control in the menu bar | Topline | 0.4 |
| A start-up sound of its own (four soft bell notes, made by our own code), which can be turned off in Dials > Sound | art, Dials | 1.6 |
| Trackpad gestures (switch desktops, overview) | **Strata** gestures | configured, not yet tested on hardware |
| Bootable live ISO | `build/build-iso.sh` | done |

## Roadmap

- **Milestone 1: bootable base.** Reproducible script that builds a live ISO
  (BIOS and UEFI) from a pinned Debian release and boots in QEMU to an
  auto-logged-in console. *(done, 0.1.0)*
- **Milestone 2: graphical session.** Wayfire configured as Strata, greetd
  autologin straight into the Wayland desktop, original wallpaper, a Welcome
  app, window overview, four desktops, gestures, and left-side window buttons
  on GTK apps. wf-shell's bar and dock stand in for Topline and Pier.
  *(0.2.0)*
- **Milestone 3: shell.** Topline menu bar and Pier dock as layer-shell
  clients; Seek launcher on Super+Space. *(0.4.0)*
- **Milestone 4: apps.** Drawer file manager (icon, list and column views) and
  Dials settings (appearance, light/dark, wallpaper, dock, displays, trackpad,
  keyboard, network). *(0.4.0)*
- **Milestone 5: polish.** Keel installer and Gangway login screen *(0.4.0)*;
  original icons and more wallpapers came in 0.7, our own title bars and
  GTK app menus in Topline in 0.8, menu bars in every freemac app in 0.9, File and Edit menus for apps that share none in 1.16; still to do: gestures
  tested on real trackpads.
- **Milestone 6: Mac app compatibility (experimental).** Ferry, our own
  optional layer that runs some programs built for Intel Macs, the way Wine
  runs Windows programs. Written from public documentation only. See
  [Mac app compatibility](docs/ARCHITECTURE.md#mac-app-compatibility-optional-layer).
- **Milestone 7: release.** Signed images, package repository, docs.

From 0.5 on, work is planned in batches of features; the current list is in
[docs/ROADMAP.md](docs/ROADMAP.md).

## Running Mac apps

freemac is not macOS and does not include it. Mac program support comes from
Ferry, our own optional, experimental compatibility layer (milestone 6), and
its limits are real:

- **App Store apps are not supported.** They are encrypted and tied to Apple's
  DRM and Apple ID, and freemac will not try to work around that.
- Only apps built for Intel (x86-64), or universal apps, can run on a PC. Apps
  built only for Apple silicon cannot.
- Ferry runs simple command-line programs, and simple windowed ones built
  with AppKit. Real Mac apps start and load their windows but none runs all
  the way yet; most everyday Mac apps will not work for a long time, if ever.
  See [ferry/README.md](ferry/README.md) and
  [docs/ferry-compat.md](docs/ferry-compat.md).
- Ferry isn't on the ISO. Each release has its package beside the ISO
  (`freemac-ferry_*_amd64.deb`); double-click it in freemac to install it.

Mac apps still look like themselves on freemac: put a `.app` in the
Applications folder (or use Add to Applications in Drawer) and it appears in
the app grid, dock and search with its own icon, read from the app itself.
Opening one runs it through Ferry when Ferry is installed and the program is
simple enough; otherwise freemac says plainly that it can't run yet.
A Mac program's menu bar items (the icons and words at the right of a Mac's
menu bar) appear in freemac's menu bar, with their menus.
Their lists, tables and outlines (the kind with a column header you click
to sort, or folders you open with a little arrow) work too, and so do their
toolbars, pop-up lists, search fields and Day/Week/Month style buttons.
Programs that read and write JSON, show dates in the right time zone and
format, or pass messages on to other objects (as many larger Mac apps do
behind the scenes) have what they need for that too.

For apps that matter, the dependable route is the Linux or web version of the
app, or a free alternative; Harbor, the app centre, lists those.

## Building

You need a Debian or Ubuntu build host, root (the build uses `chroot`) and
about 10 GB free.

```sh
sudo apt-get install debootstrap squashfs-tools xorriso grub-pc-bin \
  grub-efi-amd64-bin grub-common mtools dosfstools qemu-system-x86 ovmf
sudo ./build/build-iso.sh            # writes out/freemac-<version>-amd64.iso
```

Options are environment variables, for example:

```sh
sudo BASE=debian SUITE=trixie MIRROR=http://deb.debian.org/debian ./build/build-iso.sh
sudo SNAPSHOT=20261101T000000Z ./build/build-iso.sh   # pin to snapshot.debian.org
sudo BASE=ubuntu ./build/build-iso.sh                 # fallback base (Ubuntu 24.04)
```

## Testing in QEMU

```sh
./scripts/run-qemu.sh out/freemac-*-amd64.iso          # BIOS, window
./scripts/run-qemu.sh --uefi out/freemac-*-amd64.iso   # UEFI (needs OVMF)
./scripts/run-qemu.sh --serial out/freemac-*-amd64.iso # no window, serial console
```

The raw command it runs is:

```sh
qemu-system-x86_64 -m 2048 -smp 2 -cdrom out/freemac-0.4.0-amd64.iso \
  -boot d -vga virtio -enable-kvm -cpu host
```

Tested so far (Nov 2026), on the `BASE=ubuntu` image in QEMU:

- 0.4.0 live session: the desktop starts on its own with Topline, Pier, the
  wallpaper, network and sound icons; Seek, Drawer (all three views), Dials
  and light/dark mode work, and wired networking comes up through
  NetworkManager.
- Keel installed 0.4.0 to an empty 20 GB virtual disk. The installed system
  boots under both BIOS and UEFI (OVMF) to the Gangway login screen; a wrong
  password is refused and the right one opens the desktop.
- 0.9.0 live session: app menus show in Topline (Tally's View menu switches
  its scientific keys), dragging a window to the screen's edge tiles it, the
  quick settings panel opens from the gear and hides Wi-Fi, Bluetooth and
  brightness on a machine without them, Dials > Keyboard lists the shortcuts,
  and switching night light on starts wlsunset with the chosen hours. QEMU's
  own screen capture can show stale patches of the menu bar without a GL
  display; the compositor's picture (grim) is clean.

Not tested yet: real PC hardware, Wi-Fi (the virtual machine has none),
laptop batteries and trackpads, and the default `BASE=debian` build, which
uses the same script and package lists but couldn't be built on the first
build host because it couldn't reach Debian mirrors.

### Desktop shortcuts

Command (⌘) is the key next to the space bar: Alt on most PC keyboards, with
Option (⌥) beside it, as on a Mac keyboard. Dials > Keyboard can make the
Windows key Command instead (for a Mac keyboard). Command with a key does in
every app what Ctrl does on other PCs: Command+C copies, Command+V pastes,
Command+Z undoes, Command+S saves, Command+T opens a tab, and so on (in a
terminal, Command+C copies). Command+Left/Right go to the start or end of the
line and Option+Left/Right move a word.

| Keys or gesture | Action |
| --- | --- |
| Command+Space | Seek: search apps and files, or type a sum |
| Command+Tab | Switch apps (hold Command, press Tab, let go); Alt+Tab works too |
| Command+` | The app's next window |
| Command+Q / Command+H / Option+Command+H | Quit the app / hide it / hide the others |
| Command+M | Minimise the window |
| Control+Command+F | Full screen |
| Command+F3 | Show the desktop |
| Ctrl+Up, 4-finger swipe up | Show all windows |
| Ctrl+Down, 4-finger swipe down | App Exposé: every window of the app in front |
| Ctrl+Option+Down | Show all desktops |
| Ctrl+Left / Ctrl+Right, 3-finger swipe | Switch desktop |
| Ctrl+Shift+Left / Right | Move the window to the next desktop |
| Control+Command+Left / Right / Up / Down | Fill the left / right half, the screen, or back |
| Control+Command+Q | Lock the screen |
| Ctrl+Alt+T | Terminal |
| Shift+Command+V | Clipboard history |
| Shift+Command+3 / 4 (or Print / Shift+Print) | Screenshot of the screen / an area |
| Alt+Print | Screenshot of the window |
| Shift+Command+5, Ctrl+Print / Ctrl+Shift+Print | Record an area / the screen / an area (press again to stop) |
| Volume, brightness and media keys | Change the level, shown near the bottom of the screen; play/pause, next, previous |

In Drawer: Ctrl+1/2/3 switch between icon, list and column views, Ctrl+H
shows hidden files, F2 renames, Delete moves to the Trash, Space shows a
preview (Glance, which also works on the desktop), Ctrl+T opens a tab and Ctrl+Tab moves between tabs.
Shift+Command+G goes to a folder you type, Option+Command+P shows the path bar, and Command+Delete
in the Trash puts a file back.

## Installing

Start the live ISO and choose **Install freemac…** in the Welcome window (or
search for it with Super+Space). Keel asks for a disk and your account, erases
that disk, and installs freemac so it starts on both BIOS and UEFI PCs. It
uses the whole disk; dual-booting isn't supported yet. The boot loader is not
signed, so turn Secure Boot off first.

If you installed freemac from a download older than 1.116, some system
folders (`/`, `/etc`, `/usr` and parts of them) belong to account number 1001,
which is the second account you make on that PC, instead of to the system.
That account could change the system. Run this once in Terminal to give them
back to the system (it asks for your password):

```sh
sudo chown root:root / && sudo find /etc /usr -xdev \( -uid 1001 -o -gid 1001 \) -exec chown -h root:root {} +
```

The live session logs in automatically as user `freemac` (desktop on VT 7, text console on VT 1) (no password; `sudo`
works without one on the live image).

## Licence

freemac's own code is licensed under the GNU General Public License v3.0 or
later; see [LICENSE](LICENSE). Third-party components keep their own licences,
listed in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
