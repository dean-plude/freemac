# freemac architecture

freemac is a Debian-based distribution with an original Wayland desktop shell.
We reuse mature open-source parts for everything below the shell and write the
parts that give the desktop its character.

All of freemac's own code is GPL-3.0-or-later. Every third-party component
below has a licence that is compatible with that (or is a separate program we
only ship alongside, which is fine for any free licence).

## Layers

```
+-----------------------------------------------------------------+
|  Apps:  Drawer (files)  Dials (settings)  Seek (launcher)        |  ours
|         Keel (installer)  Gangway (login screen)                 |  ours
+-----------------------------------------------------------------+
|  Shell: Topline (menu bar)   Pier (dock)   notifications (later) |  ours
+-----------------------------------------------------------------+
|  Strata: Wayfire + our plugins, decorations, gestures, config    |  ours on top of reused
+-----------------------------------------------------------------+
|  Session: greetd, PipeWire, NetworkManager, xdg-desktop-portal   |  reused
+-----------------------------------------------------------------+
|  Base: Debian stable, Linux kernel, systemd, live-boot           |  reused
+-----------------------------------------------------------------+
```

## Reused components

| Component | Role | Licence |
| --- | --- | --- |
| Debian (trixie) | Base system and package archive | DFSG-free, mixed |
| Linux kernel | Kernel | GPL-2.0-only (separate program) |
| systemd | Init, logind, networkd for the live image | LGPL-2.1-or-later |
| debootstrap | Builds the root filesystem | MIT |
| live-boot | Boots the squashfs root from the ISO | GPL-3.0-or-later |
| GRUB 2 | BIOS and UEFI boot loader on the ISO | GPL-3.0-or-later |
| squashfs-tools, xorriso | Image creation (build time only) | GPL-2.0-or-later / GPL-3.0-or-later |
| Wayfire | Wayland compositor we extend into Strata | MIT |
| seatd | Seat and device access for the compositor | MIT |
| foot | Terminal | MIT |
| wlroots | Compositor library under Wayfire | MIT |
| wf-touch / libinput | Gesture recognition, input | MIT |
| GTK 3 (GTK 4 later) | Toolkit for our shell and apps | LGPL-2.1-or-later |
| gtk-layer-shell (gtk4-layer-shell later) | Menu bar, dock and Seek as Wayland layer surfaces | MIT |
| libadwaita (later) | Widgets and light/dark style handling | LGPL-2.1-or-later |
| PyGObject | Python bindings for prototyping shell apps | LGPL-2.1-or-later |
| greetd | Login manager and autologin | GPL-3.0-or-later |
| PipeWire, WirePlumber | Audio and screen capture | MIT |
| NetworkManager, libnm | Wired and Wi-Fi networking; Dials joins Wi-Fi through libnm | GPL-2.0-or-later (separate program) / LGPL-2.1-or-later |
| polkit | Lets the desktop user manage networks | LGPL-2.0-or-later |
| dconf | Stores GSettings such as light/dark mode for all apps | LGPL-2.1-or-later |
| cage | Kiosk compositor that shows Gangway, the login screen | MIT |
| gdisk, parted, dosfstools, e2fsprogs, squashfs-tools | Partitioning and copying the system in Keel | GPL-2.0-or-later (separate programs) |
| GtkSourceView 4 | Text view with syntax colours, used by Quill | LGPL-2.1-or-later |
| grim, slurp | Screen capture and area picking for Lens | MIT (separate programs) |
| wl-clipboard | Clipboard for Lens | GPL-3.0-or-later (separate program) |
| power-profiles-daemon | Power modes in Dials | GPL-3.0-or-later (separate program) |
| at-spi2-core | Accessibility bus for screen readers | LGPL-2.1-or-later |
| clang, lld (build only) | Compiling Mac test programs for Ferry | Apache-2.0 with LLVM exception |
| GNOME Web (Epiphany) | Web browser shipped in the image | GPL-3.0-or-later (separate program) |
| xdg-desktop-portal(-gtk) | Color-scheme setting, file pickers | LGPL-2.1-or-later |
| libdbusmenu / appmenu-gtk-module | Exporting app menus for the global menu bar | LGPL-3.0 / LGPL-3.0-or-later |
| Poppler (GLib bindings) | PDF pages in Frame, Seek and Glance | GPL-2.0-or-later |
| plocate (later) | Fast file-name index for Seek | GPL-2.0-or-later (separate program) |
| Inter font | UI typeface | SIL OFL 1.1 |
| PackageKit, packagekit-glib | Installs, removes and updates packages for Harbor | GPL-2.0-or-later / LGPL-2.1-or-later (separate program) |
| AppStream, apt-config-icons | The app catalogue (names, summaries, categories, icons) Harbor shows | LGPL-2.1-or-later |
| mate-polkit | Password prompt when an app asks for administrator rights | LGPL-2.0-or-later (separate program) |
| gtklock | Wayland session locking with PAM, styled by Latch | GPL-3.0-only (separate program) |
| swayidle | Idle and before-sleep events for Latch | MIT (separate program) |
| sound-theme-freedesktop | Alarm and timer sounds for Chime | GPL-2.0-or-later / CC-BY-SA (sounds) |
| BlueZ | Bluetooth service that Dials' Bluetooth panel talks to over D-Bus | GPL-2.0-or-later (separate program) |
| CUPS, cups-browsed | Printing; finds driverless network printers by itself | Apache-2.0 with exceptions (separate programs) |
| system-config-printer | Adding printers that need a driver, print queues | GPL-2.0-or-later (separate program) |

## Components we write

| Name | What it is | Language | Notes |
| --- | --- | --- | --- |
| **Strata** | Window-management layer: Wayfire config, our own plugins and decoration theme | C++ (Wayfire plugin API) | Left-side window buttons in an original shape and colour scheme; overview of all windows (built on Wayfire's scale and expo ideas, our own look); virtual desktops in a row; 3- and 4-finger gestures. Remembers each app's window size and place and reopens its next window there (`$XDG_STATE_HOME/freemac/window-places`); `strata/close` closes a window for Quit. A modal dialog with a parent window becomes a sheet (`sheets.hpp`): it comes down from the parent's title bar and moves with it. |
| **Topline** | Global menu bar | Python + GTK 3 (layer-shell), C later if needed | Left: system menu, focused app name, the app's own menus (GTK apps since 0.8, through strata-shell; Qt apps planned). Right: network, sound and battery icons (0.4), Bluetooth and printing (0.8), clock; app status icons (StatusNotifierItem) and quick settings later. Falls back to a minimal per-app menu when an app exports none. Window > Move & Resize (1.51) works out a half or a quarter of the output's work area (the screen less the bar and the Dock) and moves the window there through Wayfire's `window-rules/configure-view` IPC call, keeping the size it had so Return to Previous Size can put it back. The bar never refills a menu while one is open, since taking its rows away under the pointer also closed any submenu GTK had just opened on hover; it catches up when the menu closes. |
| **Backdrop** | Desktop wallpaper | Python + GTK 3 (layer-shell, background layer) | One window per screen under the menu bar and dock; fills the screen at any shape (or fits or stretches, set in Dials). Replaced wf-shell's background in 0.4. Since 1.4 the first screen also shows the Desktop folder's files as icons down the right side (`desktop_icons.py`): click to select, double-click to open, drag to place (kept in `~/.config/freemac/desktop.json`) or drop files in, right-click for Rename, Move to Trash, New Folder and Change Wallpaper. Since 1.25 Backdrop also mounts each drive, memory card or phone as it is plugged in (GIO with udisks2 and gvfs, `volumes.py`) and shows it on the Desktop; Eject is on its right-click menu, ⌘E, or a drag onto the Dock's Trash. Since 1.44 Use Stacks (⌃⌘0, kept in `desktop.json` beside the places) gathers files of one kind (`kind_of()`: by content type, with Screenshot names first) into a `StackIcon` drawn as a small pile with cairo; with stacks on the desktop lays itself out (drives, folders, stacks with any fanned-out files after them, then the rest) and the saved places wait for stacks to go off. Clean Up By rewrites the places in order; Get Info uses Drawer's `drawer_info`. 1.45 `desktop_widgets.py` puts widgets on the desktop layout (`WidgetHost`, kept in `widgets.json`): clock, calendar, weather and reminders cards drawn with cairo and Pango from Chime's time, Tide's and Nudge's stores and Sky's cached forecast; a click opens the app, a drag moves the card, and a Gallery window adds and removes them. |
| **Pier** | Dock | Python + GTK 3 (layer-shell) | Pinned and running apps from Wayfire's IPC; cursor-proximity magnification (the pointer is read from the Dock window itself, since each icon is a button with its own input window); the hovered app's name drawn above its icon in the Dock's own surface, not as a GTK tooltip, which would cover the pointer; the surface spans the screen's width so magnifying never resizes it, takes input only over the resting shelf until the pointer arrives, and the icons shrink, and grow less, when the Dock would not fit; running indicators; size and magnification set in Dials. Tells Strata where each window goes when minimized (`strata/minimize-hint`): its own small picture beside the Trash (drawn by Strata with `strata/snapshot`), or its app's icon if Dials says so. Strata shrinks the window into that place and grows it back out. Hidden apps' windows (`strata/hide`, `strata/hidden`) get no picture. Right-click or hold an app for its menu: its windows, Keep in Dock, Hide and Quit. When it hides itself (`autohide` in pier.json, set in Dials or by ⌥⌘D through `freemac-keys dock-autohide`) it reserves no space, sits on the screen's edge (exclusive zone -1), and slides the shelf down inside a GtkRevealer while the surface itself stays put, taking input only on the bottom row; the compositor mistakes where a still pointer is over a moving surface. Open menus and drags keep it up. Apps that stay open with no window (Quill, Jot; listed in held.py) are watched on the session bus by the names they own, so their dot stays and Quit asks the app itself to quit. |
| **Seek** | Search launcher on Super+Space | Python + GTK 3 (layer-shell) | Apps (`.desktop`), Dials pages (`dials_pages.py`), Guide topics (`guide_topics.py`), the front app's menu items (Topline's `SearchMenus` on D-Bus), files in the home folder by name and by the words inside them, calculator. A preview beside the results shows the chosen picture, a PDF's first page, the start of a text file, a file's kind, size and date, or an app's description.. Stays running (started with the session); `freemac-seek` asks the running copy over D-Bus, and the file index is updated while it's closed. Also finds contacts, coming events and reminders. |
| **Drawer** | File manager | Python + GTK 3 | Icon, list and column (Miller) views with a preview pane; sidebar of places, with drives under Locations and an Eject button on each (`volumes.py`, shared with Backdrop and Pier); GIO for opening files and the Trash. Share (`share.py`, also used by Cove and Frame): a toolbar button, a right-click menu and File > Share… offer Mail, which opens Post with a `mailto:?subject=…&attach=/path` link (Post attaches the files it names), and Copy to each drive, which copies on a thread, names a copy “name 2” rather than replace a file, and says how it went. Moving and copying (`transfer.py`, also used by Backdrop): ⌘C keeps the paths in `~/.cache/freemac/file-clipboard.json` beside the names as clipboard text, and ⌘V/⌥⌘V, ⌘D and drops onto folders, sidebar places and drives run a `Job` on a thread: a move on the same disk is a rename, anything else is copied in 1 MB pieces with a progress window after 0.6 s, a taken name asks Keep Both, Stop or Replace (the old item goes to the Trash), and Stop removes the half-made copy. Each move, copy, rename, new folder and Move to Trash is kept for ⌘Z in `~/.cache/freemac/file-undo.json` for two hours. |
| **Tack** | App switcher | Python + GTK 3 (layer-shell, overlay layer) | Alt+Tab shows the open apps, last used first, as large icons on a translucent panel; Tab and Shift+Tab move, letting go of Alt brings that app's windows forward (restoring one if all are minimized). Runs with the session and hears the key presses on a socket, so it answers at once. Replaced Wayfire's fast-switcher in 1.4. |
| **Dials** | Settings app | Python + GTK 3 | Appearance (light/dark through the GSettings `color-scheme` and GTK theme), wallpaper, dock and menu bar, displays (scale), trackpad and mouse, keyboard layout, network and Wi-Fi, sound (WirePlumber's wpctl), power (screen blanking through Wayfire's idle plugin, power-profiles-daemon), notifications, accessibility (with screen zoom: Wayfire's `zoom` plugin, on or off in `core/plugins`, and the key held while scrolling in `zoom/modifier`, 1.51), Bluetooth (BlueZ over D-Bus, with its own pairing agent), printers (CUPS), users (through a small root helper run with pkexec: add, delete, change password, administrator, automatic login), about. Date & Time (`dials_time.py`) talks to systemd-timedated over D-Bus (SetNTP, SetTime, SetTimezone, with polkit asking for an administrator's password); the time zone is found by typing a city, and the menu bar clock's format (12 or 24 hours, day, date, seconds) is kept in Dials' own settings, which Topline reads. Topline watches `/etc/localtime`, so a new time zone shows at once. Writes the same files Wayfire, Backdrop and Pier watch, so changes apply at once. |
| **Beacon** | Notifications | Python + GTK 3 (layer-shell) | Implements the freedesktop.org notification D-Bus interface, so `notify-send` and every app's notifications work. Banners in the top-right corner, a centre with a month calendar that marks days with Tide events and lists the chosen day's events (`minimonth.py`, `calendar_store.py`), and the last 50 notifications (opened from the clock), Do Not Disturb. |
| **Lens** | Screenshots | Python + GTK 3 | Whole screen, an area or the focused window, on Print, Shift+Print and Alt+Print; uses grim and slurp, saves to the Desktop, copies to the clipboard with wl-copy and announces the file through Beacon. |
| **Quill** | Text editor | Python + GTK 3 + GtkSourceView 4 | Syntax colours, line numbers, find and replace, go to line, wrapping, light and dark schemes, safe saving. |
| **Frame** | Picture and PDF viewer | Python + GTK 3, Poppler | Fit, zoom, rotate, next and previous in the folder, animated GIFs, Trash, full screen; PDFs page by page (`pdf.py`, also used by Seek's preview and Glance). Markup (`markup.py`): marks are plain data in the picture's own pixels, drawn with cairo on screen and into the saved copy; a PDF copy keeps each page as vectors with the marks drawn over it. Signatures are kept in `~/.local/share/freemac/signatures.json`. |
| **Tide** | Calendar | Python + GTK 3 | Day, week and month views; events kept in `~/.local/share/freemac/calendar.ics` (`calendar_store.py`, no GTK, also read by Beacon), as floating local times; repeats every day, week, month or year; lines it doesn't use are kept as they were. The Calendars list (`calendars.py`, no GTK) shows Home on this computer, each calendar from an online account (by its `X-FREEMAC-SOURCE` mark and the sync state's names and colours) and Birthdays; colours and which are hidden are kept in `~/.config/freemac/calendars.json`, and moving an event to another calendar moves it online at the next sync. |
| **Crew** | Contacts | Python + GTK 3 | One vCard 3.0 file per person in `~/.local/share/freemac/contacts` (`contacts_store.py`); opening a .vcf imports it. |
| **Nudge** | Reminders | Python + GTK 3 | Lists of to-dos, one iCalendar file of VTODOs per list in `~/.local/share/freemac/reminders` (`reminders_store.py`, no GTK, also read by Beacon and Seek); Beacon gives a notice when one is due, with Mark as Completed and Snooze; `nudge-reminder:<uid>` opens one. |
| **Glyph** | Emoji & Symbols panel | Python + GTK 3, gtk-layer-shell | Reads the emoji names and keywords that GTK ships (`/org/gtk/libgtk/emoji/en.data`) once and keeps them as JSON in `~/.cache/freemac`; stays running from the session's start with its panel hidden, and `freemac-glyph` asks it over D-Bus (gdbus) to open. Types the chosen emoji with wtype into the app in front (or copies it if that fails); remembers recent ones in `~/.local/state/freemac/emoji-recent.json`. Colour emoji come from Noto Color Emoji. Topline adds Emoji & Symbols to every app's Edit menu. Seek and Glyph keep their window mapped while closed (`ready_panel.py`): nothing drawn, clicks pass through, no keyboard; opening only shows the panel and takes the keyboard, so typing straight after the shortcut lands in it. |
| **Cove** | Photos | Python + GTK 3, GdkPixbuf, GIO | `photos_store.py` (no GTK) finds every picture under Pictures, reads when each was taken from its own EXIF data (JPEG and TIFF; otherwise the file's date) and keeps what it learned in `~/.cache/freemac/photos.json`; small copies follow the freedesktop.org thumbnail rules in `~/.cache/thumbnails/large`, so other apps share them. The grid is a FlowBox per month of drawn tiles whose small pictures are made on one worker thread, newest-drawn first, with only the last 700 kept in memory. Cameras, phones and cards are any mount with a DCIM folder (at the top, or one folder down on a phone), found through GIO's volume monitor, so USB storage, MTP, PTP and iPhones (GVfs) all work; Cove opens ones that are plugged in but not yet mounted. Import copies through GIO into `Pictures/<year>/<year-month-day>/` by the photo's own date and remembers what came from each device (`~/.local/share/freemac/photos.json`, with favourites). Since 1.25 the same file keeps albums (an id, a name and the photos' paths in the order they were added); a photo that leaves the library leaves its albums too, and deleting an album keeps its photos. The slideshow (`cove_slideshow.py`) is a full-screen window of its own, not a child of Cove's, so Wayfire lifts it above the menu bar and Dock; it draws each photo with Cairo, cross-fades and drifts it slowly closer, and loads the next one on a thread at the screen's size. |
| **Shanty** | Music | Python + GTK 3 + GStreamer | `music_store.py` (no GTK) walks `~/Music` and reads tags with GStreamer's Discoverer, keeping them in `~/.cache/freemac/music.json` by size and time so later opens only read new files; covers come from a picture in the file or a cover/folder image beside it, saved in `~/.cache/freemac/music-covers`. `shanty.py` shows albums, artists and songs, and plays with one `playbin` whose about-to-finish signal queues the next song for gapless play. It is an MPRIS player (`org.mpris.MediaPlayer2.shanty`), so Topline's what's playing, Quick Settings and the media keys drive it. The queue, position and volume are kept in `~/.config/freemac/shanty.json`. |
| **Reel** | Videos | Python + GTK 3 + GStreamer | `reel.py` plays with one `playbin` whose video goes to a `gtksink` widget (gstreamer1.0-gtk3), under controls in a crossfading Revealer that hide with the pointer after 2.5 s of playing. The window is sized to the picture once it is known, at most 80% of the screen. Because GTK asks again for a size given with `resize()`, full screen first asks for the screen's size and gives the old size back on the way out. Where each video was left (past 15 s and over 20 s from the end) is kept in `~/.cache/freemac/reel.json`, newest 200, and the volume in `~/.cache/freemac/reel-volume`. With no video it lists `~/Videos`. |
| **Gauge** | Activity Monitor | Python + GTK 3 | `gauge_store.py` (no GTK) reads `/proc` every 2 s: each process's CPU ticks (as % of one core, so a four-core machine reaches 400%), resident memory and threads, plus `/proc/stat` and `/proc/meminfo` for the machine. Apps are the programs behind windows: Strata's `strata/view-pids` IPC method gives each window's client pid (only for the user's own clients), and an app's row adds up every process it started. Without that method it guesses by name. `gauge.py` keeps one `ListStore` row per key under a filter and a sort model, and only writes the cells that changed, so a quiet list costs almost nothing. Quit asks an app's windows to close through Wayfire IPC (or sends SIGTERM to a process); Force Quit sends SIGKILL; the session's own processes are refused. |
| **Hull** | Disk Utility | Python + GTK 3 + udisks2 (D-Bus) | `hull_store.py` (no GTK) reads udisks2's object manager once per burst of change signals: each `Drive` with its whole-disk block and the file systems on it, space from `statvfs` while mounted. The disks the running system lives on (found from `/proc/self/mounts` through `/sys/class/block` slaves and partitions, so encryption and LVM count) are shown but can't be changed. Rename is `Filesystem.SetLabel` then a remount, so the mount point follows the new name. Erasing a volume is `Block.Format`; erasing a drive is a new partition map (MBR, or GPT for ext4 or over 2 TB) and `CreatePartitionAndFormat` filling it; both mount the result, with `take-ownership` for ext4. Eject unmounts everything, then powers the drive off (or opens a disc tray). `50-freemac-drives.rules` lets an admin at the computer do this to non-system disks without a password, as on a Mac; erasing in Hull also needs `exfatprogs` and `dosfstools`. |
| **Pose** | Camera | Python + GTK 3 + GStreamer | `pose.py` runs one pipeline: the camera from `Gst.DeviceMonitor` (capped near 720p, through `decodebin` so MJPEG cameras work), `videoflip` for the mirror, the chosen effect between two `videoconvert`s, then a `gtksink` widget. Effects are swapped while the camera runs by blocking the pad before the effect, relinking, and syncing the new bin's state; only effects whose elements are installed are offered (effectv from plugins-good, colour and geometry effects from plugins-bad). A picture is the sink's `last-sample`, converted to RGB and saved as JPEG in `~/Pictures/Pose`, so it is exactly what was on screen. The countdown and shutter sounds are made by `art/sounds/make-sounds.py`. |
| **Sky** | Weather | Python + GTK 3 | `sky_store.py` (no GTK) asks Open-Meteo, which needs no account or key, for the current weather, 48 hours and 10 days in the place's own time zone, keeps each answer in `~/.cache/freemac/sky` so the last weather shows straight away and offline, and keeps the places and °F/°C in `~/.config/freemac/sky.json` (the unit starts from the locale, the first place from the time zone). `sky.py` draws the chosen place over colours picked by the weather and day or night, with each day's low to high drawn against the week's. Requests run in a thread and are repeated after 15 minutes. `FREEMAC_SKY_SAMPLE=dir` answers from saved files, for testing. |
| **Stickies** | Sticky notes | Python + GTK 3 + layer shell | `stickies.py` runs one process (started with the session as `freemac-stickies --restore`) with a layer-shell surface per note on the bottom layer, above the wallpaper and under the windows, or on the top layer when the note floats. A note's place is its surface's margin from the top-left of the screen, so dragging the strip changes the margins. Keyboard input is on demand. The notes, their colours, places and sizes are kept in `~/.local/share/freemac/stickies.json` a moment after each change. |
| **Echo** | Voice recorder | Python + GTK 3 + GStreamer | `echo.py` records `autoaudiosrc` through `level` (the moving waveform) into Opus in Ogg in `~/Music/Echo`, and stops with an end-of-stream so the file is finished properly. A recording's waveform is the `level` element over a fast decode, kept in `~/.cache/freemac/echo` by file and size. Trim re-encodes the part between the handles with an accurate seek that has a stop. `FREEMAC_ECHO_TEST` records a test sound instead of the microphone. |
| **Easel** | Drawing | Python + GTK 3 + cairo | `easel.py` keeps a drawing as a list of strokes, shapes, texts and stickers in JSON in `~/.local/share/freemac/easel`, on a 1600 × 1000 page scaled to fit the window. Finished items are drawn once into a transparent picture so long drawings stay quick; the eraser is a stroke drawn with cairo's clear operator into that picture, so the paper colour stays underneath. Undo keeps earlier lists of items, which share the items themselves. Export writes the page and paper as a PNG. |
| **Rook** | Chess | Python + GTK 3 | `rook_engine.py` holds the rules (castling, en passant, promotion, checks, draws by repetition, the 50-move rule and too few pieces), checked against the standard perft counts, and a computer player: alpha-beta search a few moves deep with captures followed to the end, scored by material and piece-square tables, run in a thread with a time limit. `rook.py` draws the board with cairo and the pieces as DejaVu Sans chess symbols, and keeps the game's moves in `~/.local/share/freemac/rook.json`, replaying and checking them on start. |
| **Patience** | Card game | Python + GTK 3 + cairo | `patience.py` holds the rules of the classic one-player game (seven columns, four home piles, a deck turned one or three at a time) and draws freemac's own cards with cairo: the rank and suit symbol in the corner, a framed letter for the court cards, and a wave pattern on the back. Moves are undone from saved snapshots; a hint looks for a card that can go home, then a move that turns a card over, then the deck. The game in progress is kept in `~/.local/share/freemac/patience.json`. |
| **Mines** | Puzzle game | Python + GTK 3 + cairo | `mines.py` lays the mines after the first click, away from it and its neighbours, opens empty areas with a flood fill, and opens around a number whose mines are flagged. Best times for each size are kept in `~/.local/share/freemac/mines.json`. |
| **Books** | E-book reader | Python + GTK 3 + WebKit2GTK 4.1 | `books.py` reads an EPUB's container, package file, reading order and contents list (EPUB 3 nav or EPUB 2 NCX) with the standard library, and keeps books in `~/Books`. Pages are shown by WebKit from a `book://` address that serves only files inside the book; the book's own scripts are switched off, and a small script of Books' own lays each chapter out in columns one window wide and turns pages by scrolling. Covers are cached in `~/.cache/freemac/books`; places and text settings are kept in `~/.local/share/freemac/books.json`. |
| **Ivory** | Piano | Python + GTK 3 + GStreamer | `ivory.py` makes every sound itself: each instrument is two wave tables (bright and mellow) built from a few harmonics, with its own attack, decay and release. Notes are mixed in Python and fed to an `appsrc` (PulseAudio or PipeWire through `pulsesink` when there is one) a little ahead of the clock, never blocking the window. A recorded tune is a list of timed key presses kept in `~/.local/share/freemac/ivory.json`. |
| **Words** | Dictionary | Python + GTK 3 | `words.py` reads WordNet 3.0 (Debian's `wordnet-base`, in `/usr/share/wordnet`): the index files are read into memory at start, and each meaning is read from the data files by its byte offset when shown. A word's other forms are found with WordNet's exception lists and its ending rules. WordNet is Princeton University's, under its own permissive licence, shown in About Words. |
| **Typist** | Typing practice | Python + GTK 3 + cairo | `typist.py` makes up each lesson's text from the keys taught so far, using its own list of everyday words, and draws the text and an on-screen keyboard coloured by finger with cairo and Pango. Best speed, accuracy and stars per lesson are kept in `~/.local/share/freemac/typist.json`. |
| **Logbook** | Screen time | Python + GTK 3 + cairo | `logbook.py --track` starts with the session: it follows which app is in front through Wayfire's IPC events, counts time only while the screen is unlocked and swayidle has seen input in the last two minutes, and writes each day to `~/.local/share/freemac/logbook/DATE.json` (five weeks kept). Daily limits live in `~/.config/freemac/logbook.json`; the tracker sends a Beacon notice five minutes before and closes the app's windows at the limit. A passcode for limits is stored salted and hashed. |
| **Nine** | Number puzzle | Python + GTK 3 + cairo | `nine.py` makes each puzzle itself: it fills a grid with a randomised backtracking solver, then takes numbers away while the puzzle still has exactly one answer, until the level's number of givens is reached. The game in progress and best times are kept in `~/.local/share/freemac/nine.json`. |
| **Typecase** | Font book | Python + GTK 3 | `typecase.py` lists font families from Pango and their files from `fc-list`; fonts in `~/.local/share/fonts` count as the person's own. Adding copies files there and runs `fc-cache`; removing moves them to the Trash. A double-clicked font file is read with `fc-scan` and offered for install. |
| **Pairs** | Memory game | Python + GTK 3 | `pairs.py` deals pairs of emoji cards (drawn with the colour emoji font) on a cairo table with a flip animation; one player or two taking turns, four sizes, best results per size in `~/.local/share/freemac/pairs.json`. |
| **Plot** | Graphing calculator | Python + GTK 3 | `plot.py` reads equations with its own small parser (numbers, x, a, operators, brackets, implicit multiplication and the usual functions; never Python's `eval`) and draws them with cairo, breaking the curve at gaps and jumps. A letter a in an equation gets a slider. Equations are kept in `~/.local/share/freemac/plot.json`. |
| **Corkboard** | Whiteboard | Python + GTK 3 | `corkboard.py` keeps each board as JSON in `~/.local/share/freemac/corkboard/` (notes, text, rectangles, ovals, lines, arrows and pictures, with the view), pictures copied into its `pictures` folder. Items are drawn with cairo and Pango; moving, resizing and writing in them can be undone. |
| **Jigsaw** | Jigsaw puzzle | Python + GTK 3 | `jigsaw.py` cuts a picture into a grid of pieces whose edges are original bezier tabs, caches each piece as a cairo surface and hit-tests on its alpha. Pieces that meet their neighbours join into groups; groups near their place lock into the frame. The game in progress is kept in `~/.local/share/freemac/jigsaw.json`. |
| **Manifest** | About this computer | Python + GTK 3 | `manifest.py` reads `/proc`, `/sys` (DMI, DRM, USB, network, power supply, ALSA), `/etc/os-release`, `lscpu` and `lsblk`, all readable without a password, into an overview window and a sectioned system report that can be copied or saved as text. Topline's About freemac opens it. |
| **Swatch** | Colour picker | Python + GTK 3 | `swatch.py` takes a screenshot with grim and shows it on one GtkLayerShell overlay per screen, with a cairo loupe; the clicked pixel becomes the colour, shown as hex, RGB and HSL with its contrast against black and white. The palette is kept in `~/.local/share/freemac/swatch.json`. |
| **Tangram** | Shape puzzle | Python + GTK 3 | `tangram.py` keeps the seven pieces as polygons on a unit grid, drawn with cairo; pieces snap to the grid and turn in steps of 45°. Each of the twelve outlines comes with a solution that is checked when the module loads, and a puzzle is solved when the pieces cover the outline without overlapping. Progress is kept in `~/.local/share/freemac/tangram.json`. |
| **Buoy** | Podcasts and feeds | Python + GTK 3, WebKit2GTK 4.1, GStreamer | `buoy_feeds.py` (no GTK) fetches feeds with urllib, finds a feed from a web page's `<link rel=alternate>`, reads RSS, RDF and Atom (refusing entities) and OPML, and cleans HTML for display. `buoy.py` keeps subscriptions and items in `~/.local/share/freemac/buoy/feeds.json`, shows posts in a WebView with JavaScript off and a Content-Security-Policy, and plays episodes with a GStreamer playbin through scaletempo, remembering the place. |
| **Hunt** | Word search | Python + GTK 3 | `hunt.py` places a theme's words across, down, on slants or backwards in a seeded grid, never one wholly inside another, fills the rest mostly from the theme's letters, and draws it with cairo and Pango. The game and best times are kept in `~/.local/share/freemac/hunt.json`. |
| **Fourway** | Four in a row | Python + GTK 3 | `fourway.py` keeps the position as two bitboards (seven bits a column) and plays with an iterative-deepening alpha-beta search in a thread, scoring every four-cell window; Easy sometimes misses wins and blocks on purpose. The game, settings and results are kept in `~/.local/share/freemac/fourway.json`. |
| **Kings** | Draughts | Python + GTK 3 | `kings.py` generates legal moves with compulsory and multiple jumps (a piece that is crowned ends its move) and plays with an alpha-beta search that keeps following captures past its depth, in a thread. The game is kept as a list of moves in `~/.local/share/freemac/kings.json` and replayed, so a saved game can't hold an illegal position. |
| **Cairn** | Tile matching | Python + GTK 3 | `cairn.py` deals by taking pairs of free positions from the full layout in reverse, so every deal (and every Shuffle of what's left) has a way through. Tiles are drawn with cairo, pictures with the emoji font through Pango. The game and best times are kept in `~/.local/share/freemac/cairn.json`. |
| **Sums** | Maths practice | Python + GTK 3 | `sums.py` makes rounds of ten questions for adding, taking away, times tables and sharing at five levels each (sharing questions are built from a product, so they always come out whole), gives one more try before showing the answer, and stars a round by how many were right first time. Best stars are kept in `~/.local/share/freemac/sums.json`. |
| **Cue** | Flashcards | Python + GTK 3 | `cue.py` keeps decks in `~/.local/share/freemac/cue.json` and schedules cards in five Leitner boxes (due again after 0, 1, 3, 7 and 14 days); a card you didn't know goes back to the first box and comes round again in the same session. Imports CSV or tab-separated files, guessing the separator and whether the first row is headings. |
| **Glass** | Scanning | Python + GTK 3, SANE (`scanimage`), sane-airscan, ipp-usb | `glass.py` lists scanners with `scanimage -L` (network scanners through sane-airscan's eSCL and WSD, USB all-in-ones through ipp-usb), reads each one's modes, resolutions and glass size from `scanimage -A`, and scans to PNG in a thread, reading progress from its output; Stop sends SIGINT to the process group. A low-resolution preview fills the glass, and dragging over it sets the area passed as `-l -t -x -y`. Pages are kept in a temporary folder and saved as a PDF written with cairo (each page at its own resolution, as JPEG) or as PNG or JPEG pictures. |
| **Ledger** | Spreadsheets | Python + GTK 3 | `ledger_calc.py` (no GTK) holds a sheet as a dict of cell text, parses formulas with a small recursive-descent parser (references, ranges, `&`, comparisons, `%`, functions such as SUM, AVERAGE, IF, COUNTIF, SUMIF and ROUND) and works values out on demand with a cache cleared on every change; a cell that refers back to itself shows #CYCLE!. `shift_formula` moves references without `$` when cells are copied, filled or sorted, and `insert_or_delete` rewrites references when rows or columns are added or taken away (references to deleted cells become #REF!). `ledger.py` draws the grid itself in a DrawingArea, so a sheet of any size scrolls at the same speed, with an Entry over the cell being typed in. Files are `.ledger` (JSON) or CSV; a CSV cell starting with = is read as text. |
| **Lantern** | Presentations | Python + GTK 3, cairo | `lantern.py` keeps a presentation as JSON (`.lantern`) with each slide's layout, title, points and picture (as base64, made smaller first if over 2400 pixels, so the file can be copied on its own). Every slide is drawn by one function in a 1600×900 space with cairo and Pango, scaled for the thumbnails, the editing stage, the full-screen show and the PDF (960×540 points a page), so all four look the same. Themes are original colour sets. |
| **Lifeboat** | Backups | Python + GTK 3, GIO, udisks2 | `backup_store.py` (no GTK) makes each backup as a whole dated copy of the home folder under `freemac-backups/<computer>-<user>/` on the drive, in a folder ending `.inprogress` that is renamed when whole; a file whose size and time are the same as in the backup before is a hard link to that copy, so unchanged files take no more room. Caches and the Trash are left out. Backups thin to all of the last day, one a day for a month and one a week before that, and the oldest go when the drive is full. `lifeboat.py` runs at login with `--watch`: it backs up an hour after the last backup while the drive (known by its uuid, from `~/.config/freemac/lifeboat.json`) is plugged in, stops when the drive is ejected, and writes its state to `~/.cache/freemac/lifeboat-status.json`. Opened from the Dock it shows the backups by date with the chosen folder as it was, and Restore copies items back with `transfer.Job`. Dials > Lifeboat (`dials_backup.py`) chooses the drive and erases one that can't hold hard links with udisks2's `Format` as ext4, owned by the user. |
| **Post** | Mail | Python + GTK 3, WebKit2GTK 4.1, imaplib/smtplib | `mail_store.py` (no GTK) talks IMAP and SMTP over TLS, keeps accounts in `~/.config/freemac/mail` (passwords in a file only the user can read) and a copy of the newest 300 messages of each mailbox in `~/.local/share/freemac/mail`, so mail shows at once and the server is asked only for what's new. Each account has one worker thread; the window never waits on the network. HTML mail is shown by WebKit with JavaScript off and a Content-Security-Policy that blocks everything from the internet until Load Remote Content is pressed; links open in the web browser. The handler for `mailto:` links and `.eml` files. Address completion comes from Crew. |
| **freemac-sync** | Online calendars, contacts and reminders | Python (Gio, http.client) | Accounts are added in Dials > Internet Accounts (`dials_accounts.py`) and kept in `~/.config/freemac/accounts.json`, passwords in a file only the user can read. `dav.py` (no GTK) is a small WebDAV client: it finds the account's calendars and address books from the server's address (`.well-known`, principal, home set), lists items with their ETags, fetches them with multiget and writes with If-Match. `dav_sync.py` keeps each collection in step with Tide's calendar file, Crew's cards and Nudge's lists both ways: changes are found by ETag on the server and by a hash of each item here, new items made here go to the account's first calendar or address book, and when both sides changed the server wins. Items that came from an account carry an `X-FREEMAC-SOURCE` line (never sent to the server), so turning a kind off or removing the account takes only those off this computer. `sync_service.py` runs from the session's start, syncs every 15 minutes and a few seconds after Tide, Crew or Nudge saves; running `freemac-sync` again syncs at once (Dials' Sync Now). |
| **Harbor** | App centre and updates | Python + GTK 3 | Browses the AppStream catalogue of the archive (categories, search, picks), app pages with Install, Open and Remove, an Installed list and an Updates page, all through PackageKit, which asks for the password through polkit. A background check once a day notifies through Beacon when updates are ready. Refreshes old package lists before installing. |
| **Latch** | Lock screen | Python (launcher) + gtklock | Locks with gtklock dressed in freemac's style (current wallpaper, large clock, password field); Ctrl+Command+Q and Lock Screen in the system menu; swayidle locks after the idle time set in Dials > Power, and before sleep. While a screen saver shows, the idle lock (`freemac-lock --idle`) only leaves a mark, and the screen saver locks before it closes. |
| **Screen Saver** | Screen savers | Python + GTK 3 (layer-shell) + cairo | `freemac-screensaver` (saver.py): one overlay-layer window per screen, the pointer hidden, ended by a key, a click or a pointer move of more than a few pixels. Drift (glowing gradients added together), Clock (Pango text bouncing slowly) and Album (Pictures, else the wallpapers, cross-faded with a slow zoom). swayidle starts it (in the background, since `-w` waits for each command) after `saver_after` minutes and ends it on resume; a hot corner can start it. Each saver draws a frame for any size and time, which is how Dials draws its stills. |
| **Tally** | Calculator | Python + GTK 3 | Its own expression parser (decimal arithmetic for the basic operations), a running tape, a scientific mode with degrees or radians, `Ans`, and keyboard entry. |
| **Chime** | Clock | Python + GTK 3 | World clocks, alarms with repeat days, timers and a stopwatch. Keeps running in the background while an alarm or timer is set, rings with the freedesktop sound theme and notifies through Beacon. |
| **Marina** | Full-screen app grid | Python + GTK 3 (layer-shell) | Every app that shows in menus, freemac's first, then A to Z, in pages over a blurred copy of the wallpaper; filters as you type. Drop an app on another to make a folder; drag to rearrange (kept in ~/.config/freemac/marina.json). Opened with F4, from Pier or a hot corner. |
| **Jot** | Notes | Python + GTK 3 | Each note is a plain text file in `~/Documents/Notes`; the first line is the title. Saves a moment after typing stops, searches as you type, and notes show up in Seek and Drawer like any file. |
| **Guide** | How-to topics | Python + GTK 3 | Short topics in `guide_topics.py` (no GTK, so Topline's Help and Seek read them cheaply); `freemac-guide --topic NAME` opens one, in the window already open if there is one. |
| **Ferry** | Optional Mac program layer | C | Loads Intel Mach-O programs and connects them to our own libSystem conversions. Not on the ISO; see [Mac app compatibility](#mac-app-compatibility-optional-layer). |
| **Keel** | Installer | Python + GTK 3, root backend | Whole-disk GPT install (BIOS boot, EFI and ext4 partitions); copies the pristine live image, creates the account, removes live-only parts, installs GRUB for BIOS and UEFI. The password goes to the backend on stdin, never on a command line. |
| **Gangway** | Login screen | Python + GTK 3 in cage | A greetd greeter that starts freemac-session. |
| **freemac-theme** | GTK theme layer, cursor, icon set, wallpapers | CSS, SVG, generated PNG | 0.4: a GTK 3 CSS layer over Adwaita with freemac's window buttons and indigo accent, and two generated wallpapers (Dusk Tide, Night Tide). 0.7: original icons for every freemac app (`art/icons`), a `freemac` icon theme with our own folder and file-type icons that inherits Adwaita for everything else (`art/icon-theme`), and four wallpaper scenes (Tide, Lagoon, Prism, Harbor), each computed in a day and a night version that Dials swaps with light and dark mode (`art/make-wallpaper.py`). |
| **build/** | ISO build tooling | POSIX shell | This repository's `build/build-iso.sh`. |

Python with GTK 3 is chosen for the first versions of the shell apps because
it lets the look and behaviour iterate quickly and gtk-layer-shell for GTK 3 is
packaged everywhere; a move to GTK 4 and libadwaita is planned once
gtk4-layer-shell is widely packaged. Anything that turns out to be performance
sensitive (the dock's magnification, for example) can move to C or Rust later
without changing the user experience.

## Status in 0.4 (milestones 3 to 5)

- **Strata** is a Wayfire configuration (`/etc/skel/.config/wayfire.ini` in
  `build/overlay`): overview (scale), all-desktops view (expo), four desktops
  in a row (vswitch), 3-finger desktop swipe (vswipe), animations, and the
  `ipc` plugins our shell uses.
- **Left-side window buttons** come from GTK's decoration layout and
  freemac's own GTK theme (`art/gtk-theme`, installed as `freemac` and
  `freemac-dark`), which draws them as small round buttons. Apps that ask the
  compositor for a title bar (foot, some Qt apps) get strata-decor's, which
  matches.
- **Qt apps** take freemac's colours and font through qt5ct and qt6ct, and
  Qt 5 apps also freemac's own buttons, fields, tabs, check boxes, pop-up
  menus and scroll bars: a Kvantum theme (`art/kvantum/make-kvantum.py`,
  installed as `freemac` and `freemac-dark` in `/usr/share/Kvantum`) drawn
  from the same colours as the GTK theme. Dials switches it with light and
  dark. Qt 6 apps still use Qt's Fusion style in freemac's colours, since
  Ubuntu 24.04 has no Kvantum for Qt 6. Qt apps run on Wayland
  (qtwayland5, qt6-wayland); there is no X server.
- **Shell:** Topline, Pier, Seek and Backdrop are layer-shell clients in the
  `freemac_shell` Python package (`shell/`), started from Wayfire's autostart.
  They talk to Wayfire over its IPC socket for windows and focus.
- **Apps:** Drawer, Dials, Keel and Gangway live in the same package.
  `build/build-iso.sh` installs it into the image.
- **Session:** greetd logs the live user in on VT 7 and shows Gangway after
  log-out; installed systems show Gangway unless "Log in automatically" was
  chosen. seatd hands the compositor its devices; NetworkManager runs the
  network.
- **Known gaps (then):** app menus in Topline and our own decoration plugin
  (both came in 0.8), our own icons (0.7), and gestures, Wi-Fi and
  batteries tested on real hardware. In QEMU's software rendering the menu
  bar sometimes shows a dark patch for a moment while it redraws; not yet
  checked on real hardware.

## Strata's plugins (0.8)

`strata/` holds Wayfire plugins in C++. `build/build-iso.sh` copies them into
the image, installs the compilers and Wayfire's headers, runs
`strata/build.sh`, installs the `.so` files and their option files
(`/usr/share/wayfire/metadata`), swaps them into `wayfire.ini`'s plugin list,
and removes the compilers again. They follow Wayfire's plugin API as of ABI
2023-11-23; with another Wayfire the build skips them and Wayfire's stock
plugins stay in use.

- **strata-decor** (`strata/decor`) replaces `decoration`: the title bar for
  apps that leave it to the desktop, with freemac's buttons on the left, a
  centred title, and colours that follow Dials' light/dark setting live.
- **strata-shell** (`strata/shell`) replaces `gtk-shell`: it keeps the menu
  addresses GTK apps publish for each window and answers the IPC call
  `strata/app-menus {"id": N}` with them. Topline reads the menus over D-Bus
  (`org.gtk.Menus` and `org.gtk.Actions`, through GIO's `GDBusMenuModel` and
  `GDBusActionGroup`) and shows them next to the app's name. It also tells
  GTK apps that the desktop shows their menu bar, so they leave it out of the
  window (`[strata-shell] global_menus`).

Both start from Wayfire's own MIT-licensed plugins; see each folder's README.

## Menus, tiling, quick settings and night light (0.9)

- Every freemac app publishes its menu bar through `GtkApplication`
  (`shell/freemac_shell/menus.py` builds them). The menus only show the keys;
  each window still handles its own keys, so typing in a text field works as
  usual.
- Tiling at the screen edges is Wayfire's `grid` plugin together with
  `move`'s snapping (`[move] enable_snap`), in freemac's colours. Dials >
  Appearance switches it off.
- Dials > Keyboard edits the shortcuts in `wayfire.ini`. It reads the key
  pressed as a Linux input code through libevdev, so the name it writes
  (`KEY_A` and so on) is right whatever the keyboard layout.
- Brightness goes through logind's `SetBrightness`, so the person at the
  seat can change it without a password. Night light is `wlsunset` (Wayland
  gamma control), started at login by `freemac-nightlight` from
  `~/.config/freemac/nightlight.json`. Virtual machines usually can't change
  gamma, so night light only shows on real screens.
- Quick settings (`quick.py`) is a layer-shell panel from Topline, like the
  volume slider, so it can draw below the bar.

## Finding, previewing and first run (1.0)

- **Seek's text index** (`seek_index.py`): a SQLite FTS5 table with the
  trigram tokenizer in `~/.cache/freemac/seek.db`, so any three or more
  characters match inside words. Seek updates it in a background thread
  each time it opens, rereading only files whose modification time
  changed. It reads text files by extension (skipping anything with NUL
  bytes), and the XML inside OpenDocument (`.odt`, `.ods`, `.odp`) and
  Word (`.docx`) files; files over 2 MB and hidden folders are skipped.
- **Drawer tabs** keep each tab's folder, history, view and filter and
  swap them into the one set of views when switching, rather than
  building a set of views per tab. **Favourites** live in
  `~/.config/freemac/drawer.json`, with the Sort By choice and whether the
  path bar shows (1.47). Sorting is a sort function on each folder's
  ListStore over two number columns (modified time and bytes), so every
  view and the column view share it; list headings sort on those too.
  **Put Back** (`transfer.put_back`) reads the item's `.trashinfo` note in
  `Trash/info` for where it came from, moves it there (a taken name gets
  "name 2", a missing folder is made again) and removes the note;
  emptying the Trash is `transfer.empty_trash`, shared with the Dock.
  **Tags** (`tags.py`, 1.48) live on the file itself in the
  `user.xdg.tags` extended attribute (comma-separated names, as other
  Linux file managers keep them), so they follow a rename or move on the
  same disk. An index in `~/.local/share/freemac/tags.json` notes where
  tagged files were last seen: tagging notes a file, every folder Drawer
  reads brings the index up to date for that folder, and listing a tag
  (Drawer's `tag:Red` place) rereads each file's attribute and drops any
  that lost it. Names are drawn as Pango markup with a dot per tag.
  **Recents** (`recents.py`, 1.49) is the desktop's shared list of
  recently used files (`recently-used.xbel` through Gtk.RecentManager),
  which freemac's apps and most Linux apps already add to; Drawer and the
  desktop add a file when they open it. Drawer's `recents:` place lists
  the ones still there, newest first, in insertion order (the store is
  left unsorted). **New Folder with Selection** (`transfer.folder_with`)
  renames the items into a new folder beside them and notes a "group"
  record, which Undo moves back and removes the folder if it is empty.
  **Spring-loaded folders** (1.50): every drop target in Drawer starts a
  short timer when a drag rests on a folder and opens it when the timer
  ends; the drag hands over the files picked up when it began, not the
  window's selection, which is empty after the folder changes.
  **Quick Actions** (`quick_actions.py`, 1.50) turn a picture with
  GdkPixbuf and save it back in its own format (JPEG, PNG, TIFF, BMP), and
  make a PDF with cairo's PDF surface, one page per picture fitted to an
  A4 page's long side; a made PDF is noted for Undo like a copy.
  **Glance** (`drawer_glance.py`) is a
  plain window that follows the selection while open. Since 1.46 it also
  opens from the desktop, plays movies and music with its own GStreamer
  playbin into a gtksink, shows every PDF page (up to 60, drawn while you
  read), steps through several selected files, fills the screen, and hands
  arrow keys back to its owner (Drawer's view or the desktop) to move the
  selection. Drawer's folders load picture and PDF thumbnails a few at a
  time after the folder shows (`Folder._thumbnails`).
- **Pier's places** sit after a separator at the dock's right end: folder
  stacks open as a menu of the newest files, and the Trash watches
  `~/.local/share/Trash/files` (the freedesktop.org trash that Drawer and
  GLib use) and empties it by deleting `files/`, `info/` and `expunged/`.
- **Welcome** (`welcome.py`) runs from the login autostart once per
  account (`~/.config/freemac/welcome-seen`), and every time on the live
  system. Its Wi-Fi step reuses Dials' network panel, and its look and
  wallpaper steps call the same code as Dials.

## Everyday extras (1.1)

- **Keys** (`keys.py`, `freemac-keys`): Wayfire's command plugin runs it
  for volume, mute, microphone, brightness and media keys (repeating
  bindings for the levels). It changes the level with wpctl or logind's
  backlight call and asks Beacon, over a new `ShowLevel` D-Bus method, to
  show the level in a small panel near the bottom of the screen.
- **Now playing** (`media.py`): reads MPRIS players on the session bus
  with Gio only, so a key press doesn't load GTK. It prefers a playing
  player, then a paused one. Quick settings shows it with back,
  play/pause and forward.
- **Screen recording** (Lens): wf-recorder to the Desktop (where
  screenshots land too, as on a Mac), the whole screen or an area picked with
  slurp; Topline shows a red stop button while it runs.
- **Clipboard history** (`clips.py`): `wl-paste --watch` hands each new
  text copy to `freemac-clips --store`, which keeps the last 50 in
  `~/.local/state/freemac/clips.json` (mode 600). Copies a password
  manager marks with `x-kde-passwordManagerHint` are skipped, and nothing
  is kept while history is off in Dials > Keyboard.
- **Archives** (`drawer_archive.py`): zip with Python's zipfile; zip and
  tar extraction skip absolute paths, `..` and links that would point
  outside the new folder, and use tarfile's `data` filter where Python
  has it.
- **Hot corners** (`corners.py`): Wayfire activators accept
  `hotspot <corner> 10x10 250`, so Dials adds that to the binding of the
  chosen action and removes it from every other one.

## Recovery

freemac Recovery (`recovery.py`, with the GTK-free `recovery_store.py`) is a
full-screen app for fixing a computer that won't start properly, like a
Mac's recovery. It is the same on an installed system and on the live USB.

- **Getting in.** Holding Ctrl as the computer starts picks the "freemac
  Recovery" entry: `/etc/grub.d/42_freemac_recovery` writes that entry (the
  newest kernel with `systemd.unit=freemac-recovery.target`) and a
  `keystatus --ctrl` test after it, and the live USB's `grub.cfg` has the
  same. Dials > Power > Restart in Recovery… runs
  `/usr/libexec/freemac-recovery-helper` with pkexec
  (`org.freemac.recovery.restart`), which runs `grub-reboot
  freemac-recovery` and restarts.
- **Starting.** `freemac-recovery.target` stops the login screen and pulls in
  `freemac-recovery.service`, which runs `cage -s -- freemac-recovery` as root
  on tty1 (PAM service `freemac-recovery`), so there is no desktop, Dock or
  menu bar, only Recovery. If it quits, systemd starts it again.
- **Who may use it.** Started from the disk, it asks for an administrator's
  password (a member of sudo, admin or wheel), checked against the system's
  own `/etc/shadow` with libcrypt. From the live USB it doesn't ask.
- **Which system.** From the disk it fixes `/`. From the live USB it mounts,
  read-only, each fixed-disk partition whose `/etc/os-release` says
  `ID=freemac` under `/run/freemac-recovery/drives/`, and remounts one
  read-write only to change it.
- **What it does.** Restore from Lifeboat (finds `freemac-backups/` on any
  drive, lists backups newest first, and copies one back over a person's home
  folder, keeping links as links and giving the files back to their owner);
  Reinstall freemac (runs Keel from the live USB; from the disk it says how);
  Reset a Password (`chpasswd`, with `-R` for a mounted system); Check a Disk
  (`e2fsck -f -y`, `fsck.vfat -a -w` or `fsck.exfat -y` on a volume that isn't
  mounted); Drives (Hull); Get Help Online (the browser, private); and
  Terminal (foot). The bar at the top joins Wi-Fi through NetworkManager
  (`nmcli`, one check at a time) and restarts or shuts down.

## Hard problems we know about

- **Global menus on Wayland.** There is no single standard. GTK 3 apps with
  a GtkApplication menu bar publish it through the gtk-shell protocol, which
  strata-shell passes to Topline (0.8). Qt apps can export menus through the
  KDE appmenu protocol (planned); GTK 4 and Electron apps mostly cannot.
  Topline falls back to its own small app menu (Hide, Quit) when an app
  publishes none.
- **Overview and gestures** need compositor support, which is why Strata is
  built inside Wayfire rather than as a separate client.
- **Hardware support** follows Debian's kernel and firmware (we enable
  `non-free-firmware` so Wi-Fi works on common laptops).

## App icons (1.2)

- **freemac-icon-tiles** (`shell/freemac_shell/icontiles.py`) gives every
  installed app's icon freemac's rounded-square shape, so the dock, app grid
  and search look like one family. It reads each `.desktop` file's icon,
  then writes a tile into the `freemac` icon theme (`scalable/apps`): an icon
  that already fills a square is just rounded; any other shape sits at 70%
  on a soft paper tile. It runs while the image is built, after each package
  install (an apt hook), and at login for apps in the home folder.
  freemac's own icons are left alone.
- **Mac apps** (`shell/freemac_shell/macapps.py`, `freemac-mac-app`): a
  `.app` folder is read for its name (`CFBundleDisplayName`/`CFBundleName`)
  and icon (`CFBundleIconFile` in `Contents/Resources`). The `.icns` file is
  read following its public format: PNG entries are used as they are, and
  the older run-length-encoded RGB entries are combined with their 8-bit
  masks. The icon goes into `hicolor` and a `.desktop` file into the app
  grid, both named `ferry-<bundle id>`. Apps found in `~/Applications` are
  added at login; Drawer shows `.app` folders as single apps with their own
  icon. Apps whose icon only exists in a compiled asset catalogue get
  freemac's generic Mac app icon.

## Mac app compatibility (optional layer)

Goal: let some programs built for Intel Macs run on freemac the way Wine lets
Windows programs run on Linux, without macOS itself and without anything taken
from a Mac.

**Approach: Ferry, written by us.** The project owner chose to build our own
layer instead of packaging Darling, so no Apple-published source code (APSL)
is involved. Ferry lives in [`ferry/`](../ferry/README.md) and ships as an
optional `freemac-ferry` package that is **not** part of the default ISO.

- `ferry` is a loader written in C. It reads a Mach-O executable (picking the
  Intel slice of a universal file), maps its segments, applies rebases and
  binds (classic opcode streams and chained fixups), and calls its `main`.
- Imports from libSystem resolve to Ferry's own code: conversions for the
  calls whose numbers or data layouts differ between macOS and Linux (errno,
  `FILE`, `struct stat`, directory entries, open flags, signals, clocks,
  `sysconf`, `uname`, locales, getopt), and this system's C library for calls
  that are the same on both. Anything else stops the program with a message
  naming the call; Ferry never guesses.
- The Ferry SDK (`ferry-cc`) builds Mac programs on freemac with clang and
  lld, against our own headers and our own description of libSystem, so tests
  never need a Mac.

**Sources.** Only public documentation and open specifications: the Mach-O
file format as documented publicly and in LLVM's open-source tools (Apache-2.0
with LLVM exception), the System V AMD64 calling convention, POSIX, and the
numbers and structure layouts that are part of the published macOS C
interface. No Apple binary is ever disassembled, decompiled, traced or dumped,
and no Apple code, headers or assets are copied.

**What it runs today (honestly).** Simple command-line programs that use the
C library: text, files, directories, environment, time, maths, signals.
Not yet: threads, sockets, C++ (libc++), Objective-C, frameworks such as
Foundation or AppKit, and programs that need other dynamic libraries. GUI
apps are a long way off and may never be practical.

**Hard limits, by design:**

- No App Store apps: they are FairPlay-encrypted and tied to Apple ID. freemac
  will not decrypt them, bypass DRM or code signing, or sign in to Apple
  services.
- No Apple binaries, frameworks or system files copied from a Mac, ever, even
  from the user's own machine.
- Intel (x86-64) and universal binaries only; Apple-silicon-only programs
  cannot run on a PC.

## Build pipeline (milestone 1)

1. `debootstrap` a minimal Debian root for a pinned suite (optionally from a
   fixed snapshot.debian.org timestamp).
2. Install kernel, live-boot, systemd and a small tool set in a chroot.
3. Apply `build/overlay/` (branding, autologin, hostname).
4. Normalise timestamps to `SOURCE_DATE_EPOCH`, strip caches and machine ids.
5. Pack the root into `live/filesystem.squashfs`.
6. Assemble a hybrid BIOS/UEFI ISO with `grub-mkrescue`.

See [the README](../README.md) for how to build and test.
