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

Taken from the 1.23 live ISO in a virtual machine (QEMU, 1280×800). The
names, contacts and events in them are made-up examples.

![The freemac desktop with the Welcome window, menu bar and Dock](docs/screenshots/welcome.png)

<table>
<tr><td width="50%"><img src="docs/screenshots/drawer.png" alt="Drawer, the file browser, with the menu bar and Dock"><br><sub>Drawer, the file browser, with the menu bar and Dock</sub></td><td width="50%"><img src="docs/screenshots/seek.png" alt="Seek (⌘Space) finds files, apps, contacts, events and reminders"><br><sub>Seek (⌘Space) finds files, apps, contacts, events and reminders</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/apps.png" alt="All apps (F4 or the Dock's grid icon)"><br><sub>All apps (F4 or the Dock's grid icon)</sub></td><td width="50%"><img src="docs/screenshots/freemac-menu.png" alt="The freemac menu at the left of the menu bar"><br><sub>The freemac menu at the left of the menu bar</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/quick-settings.png" alt="Quick settings from the menu bar"><br><sub>Quick settings from the menu bar</sub></td><td width="50%"><img src="docs/screenshots/nudge.png" alt="Nudge, for reminders"><br><sub>Nudge, for reminders</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/tide.png" alt="Tide, the calendar"><br><sub>Tide, the calendar</sub></td><td width="50%"><img src="docs/screenshots/crew.png" alt="Crew, for contacts"><br><sub>Crew, for contacts</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/dark-mode.png" alt="Dark mode, with the night wallpaper"><br><sub>Dark mode, with the night wallpaper</sub></td><td width="50%"><img src="docs/screenshots/dials-dark.png" alt="Dials, the settings app, in dark mode"><br><sub>Dials, the settings app, in dark mode</sub></td></tr>
<tr><td width="50%"><img src="docs/screenshots/lock-screen.png" alt="The lock screen"><br><sub>The lock screen</sub></td></tr>
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
| Global top menu bar with app menu, window menu, status icons, clock | **Topline** | 0.4: own bar with network, sound and battery icons; 0.5: clock opens the notification centre; 0.6: Lock Screen item; 0.8: GTK apps' own menus, Bluetooth and printing icons; 0.9: quick settings panel; 1.1: what's playing, with play/pause; 1.7: shortcuts in ⌘ symbols, the same app menu in every app, a Mac Window menu with Zoom; 1.8: slide along the bar between open menus, Settings… ⌘, in the app menu; 1.10: clicking the desktop makes Drawer the app in the bar, with File and Go menus; 1.12: Window > Fill and Center, and Hide leaves windows out of the Dock; 1.13: an app that stays open with no window keeps its name and menus in the bar, and the bar no longer switches to Drawer while ⌘Tab or Seek is up; 1.14: apps go by their short names, a Save dialog or alert keeps its app's menus, an app stays in front when its last window closes, and a window's commands are greyed out while its app has none; 1.15: an app with no window open keeps its shortcuts (⌘N in Jot); 1.16: apps that share no menus (Web, Firefox, VLC, Qt apps) still get File, Edit and Window menus, whose items press the app's own shortcuts; 1.17: Help in every app, where you type to find any menu item and press Return to run it; 1.19: Help closes on a click outside it; 1.20: Help lists Guide topics under the menu items; 1.21: Guide in the freemac menu, and Seek no longer lists open windows' names; 1.22: the clock opens a month calendar with the day's events from Tide; 1.25: an app's menus never show under another app's name while it opens or quits; 1.41: follows a new time zone at once |
| Bottom dock with magnification, running indicators | **Pier** | 0.4; 1.0: Downloads folder and a Trash you can empty; 1.2: icons bounce while an app starts and rise out of the dock when magnified; 1.9: drag apps along it or off it, drop files on an app to open them; 1.10: drop files on a Dock folder to move them there; 1.12: a minimized window shows as its own small picture beside the Trash; 1.13: Quill and Jot keep their dot with no window open, and clicking one opens a new window; 1.14: apps open at login get their dot straight away; 1.38: the app's name shows above its icon, magnification follows the pointer over the icons, a crowded Dock shrinks to fit the screen, and windows behind the Dock's clear top stay clickable; 1.42: hides itself until the pointer reaches the bottom of the screen (Dials or ⌥⌘D) |
| Desktop wallpaper that fills any screen shape; files on the Desktop as icons | **Backdrop** | 0.4; 1.4: desktop icons; 1.25: USB drives, memory cards and phones mount as they're plugged in and show on the Desktop; drag one to the Trash to eject it; 1.26: copy, paste, Duplicate and Undo on the Desktop, and drop files onto a folder icon; 1.44: Use Stacks piles the Desktop's files by kind (a click fans a stack out), Clean Up By Name, Kind or Date Modified, and Get Info; 1.45: desktop widgets (clock, calendar, weather, reminders) you can drag anywhere; Edit Widgets… adds and removes them; 1.46: Space opens Glance on desktop files, and the arrow keys move from icon to icon; 1.48: tag desktop files with a colour from their menu; 1.49: New Folder with Selection |
| Alt+Tab app switcher with large icons | **Tack** | 1.4; 1.13: apps open with no window are listed too, and picking one opens a window |
| Window manager: left-side window buttons in our own style, window overview, virtual desktops | **Strata** (Wayfire config + theme) | 0.4: overview, 4 desktops, left buttons in freemac style on GTK apps; 0.8: own title bars for every app (strata-decor); 0.9: drag a window to an edge to tile it; 1.2: rounded title bars with round buttons that show their symbols on hover; 1.3: all four corners round, our own pointer, new windows clear of the menu bar; 1.12: minimizing shrinks a window down into its place in the Dock; 1.14: Save dialogs and alerts come down from the title bar as sheets and move with their window; 1.15: ⌘. cancels a dialog |
| File manager with icon, list and column views | **Drawer** | 0.4; 1.0: tabs, a sidebar you can change, Glance preview on Space; 1.1: compress to .zip, open .zip and tar archives; 1.2: Mac apps (.app) shown with their own icon; 1.6: Get Info (⌘I); 1.11: Favorites and Locations sidebar with blue icons; 1.21: Glance shows the first page of a PDF; 1.25: drives under Locations with an Eject button (⌘E); 1.25: Share, to mail files in Post or copy them to a drive; 1.26: copy and paste files (⌘C, ⌘V, ⌥⌘V to move), Duplicate (⌘D), drag onto folders, sidebar places and drives, a progress window with Stop, Keep Both or Replace for a taken name, and Undo (⌘Z); 1.46: pictures and PDFs show as small pictures of themselves, and Glance plays movies and music, shows every PDF page, steps through several files and fills the screen; 1.47: Put Back and Empty in the Trash, Open With, Sort By name, kind, date or size, a path bar (⌥⌘P) and Go to Folder (⇧⌘G); 1.48: coloured tags, with a dot after the name and a sidebar list of each colour's files; 1.49: Recents (⇧⌘F) with Show in Enclosing Folder, New Folder with Selection, and tags in Get Info |
| Full-screen grid of all apps (F4) | **Marina** | 1.2; 1.3: folders, and apps can be dragged into any order |
| ⌘Space search launcher (apps, files, sums) | **Seek** | 0.4; 1.0: finds files by the words inside them; 1.18: finds settings pages and the front app's menu items; 1.19: closes on a click outside it; 1.20: a preview of the chosen file, picture or app beside the results, and Guide topics; 1.21: a PDF's first page in the preview, and a nearly solid panel; 1.23: finds contacts, events and reminders, and opens faster |
| Settings app with light and dark mode | **Dials** | 0.4: appearance, wallpaper, dock, displays, trackpad and mouse, keyboard, network and Wi-Fi, about; 0.5: sound, power, notifications, accessibility; 0.7: users, Bluetooth, printers; 0.9: brightness, night light, changeable shortcuts; 1.6: Command key choices, start-up sound switch; 1.9: what a title-bar double-click does; 1.10: a grouped sidebar with each icon in a coloured tile; 1.11: search in the sidebar; 1.12: minimize windows into their app's icon; 1.19: opens in about half the time, building each page when it's first shown; 1.20: starts faster again, as every freemac app does, now that their code is compiled ahead in the image; 1.41: Date & Time (time zone by city, automatic time, 12 or 24 hours, day, date and seconds in the menu bar) |
| Notifications with banners, a history list and Do Not Disturb | **Beacon** | 0.5 |
| Screenshots of the screen, an area or a window (⇧⌘3, ⇧⌘4 or the Print key) | **Lens** | 0.5; 1.1: screen recording (Ctrl+Print); 1.7: a small picture in the corner after each screenshot; 1.21: clicking it opens the screenshot in Frame, not the web browser |
| Notes, saved as plain text files as you type | **Jot** | 1.1; 1.13: stays open with no window, and File > New Note works from the menu bar; 1.14: hints show ⌘N; 1.15: ⌘N works with no window open |
| Short how-to topics (the Command key, windows, screenshots, Wi-Fi and more), found from Help and Seek | **Guide** | 1.20; 1.21: also in the freemac menu and on Welcome's last page |
| Volume, brightness and media keys with an on-screen level | freemac-keys, **Beacon** | 1.1 |
| Clipboard history (Super+Shift+V) | freemac-clips | 1.1 |
| Hot corners | **Strata**, Dials | 1.1 |
| Force Quit window on ⌥⌘⎋ for an app that has stopped answering | **Force Quit**, Strata | 1.9 |
| Alerts in a small panel with the app's icon on top and equal buttons, used by every freemac app | alert.py, theme | 1.10 |
| Text editor | **Quill** | 0.5; 1.13: stays open with no window; ⌘Q asks about unsaved changes, then quits; 1.15: a small Save sheet (name and where) that opens out to the full browser |
| Picture and PDF viewer | **Frame** | 0.5; 1.21: opens PDFs, page by page, and is the default for them; 1.22: Markup (⇧⌘A): draw, boxes, text and a signature drawn once on a pad, saved as a copy beside the original; 1.25: Share |
| Calendar with day, week and month views, events that repeat, kept as a standard .ics file | **Tide** | 1.22; 1.23: notices before events, Crew's birthdays; 1.24: online calendars; 1.25: a colour for each calendar and a Calendars list to show or hide each one, with a month to jump from |
| Contacts, kept as one standard .vcf card per person | **Crew** | 1.22; 1.24: online address books |
| Reminders in coloured lists, with due dates, flags and a notice when one is due | **Nudge** | 1.23; 1.24: online reminder lists |
| Internet Accounts: sign in once (iCloud, Fastmail, Yahoo, Nextcloud or any CalDAV and CardDAV server) and its calendars, contacts and reminders stay in step both ways | **Dials**, freemac-sync | 1.24 |
| Emoji and symbols: search or browse, then type the chosen one into the app in front (Control-⌘-Space, or Edit > Emoji & Symbols) | **Glyph** | 1.24 |
| Photos: everything in your Pictures folder by month, a large view with favourites, and import from a camera, phone or memory card | **Cove** | 1.24; 1.25: albums you make and name, photos added by drag or right-click, and a slideshow of any album or the whole library; Share, to mail photos or copy them to a drive |
| Music: the songs in your Music folder by album, artist and song, with album covers, shuffle and repeat, songs played one after another with no gap, and the media keys and menu bar's what's playing | **Shanty** | 1.27 |
| Videos: plays them in a window or full screen, with controls that fade away, and starts each where you stopped | **Reel** | 1.28 |
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
| Screen time: how long each app was used today and over the week, and daily limits with a warning before time is up and an optional passcode | **Logbook** | 1.33 |
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
| Mail: your IMAP accounts' mailboxes, reading with pictures from the internet held back until you ask, replying, forwarding, attachments and drafts | **Post** | 1.24; 1.25: a new message with files attached when you Share from another app |
| Backups: your home folder copied to a drive every hour, earlier backups kept with unchanged files shared, and any file or folder brought back from a backup chosen by date | **Lifeboat** | 1.27 |
| Recovery: hold Ctrl as the computer starts to bring back a backup, reset a password, check a disk or reinstall | **Recovery** | 1.40 |
| Runs simple Intel Mac command-line programs (optional add-on) | **Ferry** | 0.5: first version |
| App centre for open-source apps, with system updates | **Harbor** | 0.6 |
| Lock screen (Ctrl+Command+Q, idle and before sleep) | **Latch** | 0.6; 1.3: laid out like the login screen; 1.43: waits for the screen saver to end, then asks for the password |
| Screen savers: Drift, Clock and Album (your photos) | **Screen Saver** | 1.43: chosen in Dials > Screen Saver, starts after a few idle minutes or from a hot corner |
| Calculator | **Tally** | 0.6 |
| Clock with world clocks, alarms, timers and a stopwatch | **Chime** | 0.6 |
| Original app icons, folder and file icons, and day/night wallpapers | freemac theme | 0.7: 10 app icons, 17 folder and file icons, 4 wallpaper scenes; 1.2: every app's icon on the same rounded tile, a full GTK theme of our own, Inter as the system font |
| Start-up screen instead of a boot menu and text | build | 1.2 |
| First-run setup: light or dark, wallpaper, Wi-Fi, shortcuts | **Welcome** | 1.0 |
| Installer | **Keel** | 0.4: whole-disk install, BIOS and UEFI |
| Login screen | **Gangway** | 0.4; 1.2: blurred wallpaper, round picture, password field with an arrow |
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
- Ferry today runs simple command-line programs only. Graphical apps need
  Mac frameworks Ferry doesn't have; most everyday Mac apps will not work for
  a long time, if ever. See [ferry/README.md](ferry/README.md).

Mac apps still look like themselves on freemac: put a `.app` in the
Applications folder (or use Add to Applications in Drawer) and it appears in
the app grid, dock and search with its own icon, read from the app itself.
Opening one runs it through Ferry when Ferry is installed and the program is
simple enough; otherwise freemac says plainly that it can't run yet.

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
| Ctrl+Down, 4-finger swipe down | Show all desktops |
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

The live session logs in automatically as user `freemac` (desktop on VT 7, text console on VT 1) (no password; `sudo`
works without one on the live image).

## Licence

freemac's own code is licensed under the GNU General Public License v3.0 or
later; see [LICENSE](LICENSE). Third-party components keep their own licences,
listed in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
