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
| cryptsetup, cryptsetup-initramfs | Encrypted disks: Keel, the start-up unlock and Dials > Privacy & Security (1.141) | GPL-2.0-or-later (separate programs) |
| GtkSourceView 4 | Text view with syntax colours, used by Quill | LGPL-2.1-or-later |
| grim, slurp | Screen capture and area picking for Lens | MIT (separate programs) |
| wl-clipboard | Clipboard for Lens | GPL-3.0-or-later (separate program) |
| power-profiles-daemon | Power modes in Dials | GPL-3.0-or-later (separate program) |
| at-spi2-core | Accessibility bus for screen readers | LGPL-2.1-or-later |
| Orca | Screen reader (Command+F5, 1.120) | LGPL-2.1-or-later |
| speech-dispatcher | Speech for the screen reader | GPL-2.0-or-later, LGPL-2.1-or-later |
| python3-qrcode | QR codes for known Wi-Fi networks (1.121) | BSD-3-Clause |
| gnome-keyring, libpam-gnome-keyring | The keychain: the secret service, opened at login (1.122) | GPL-2.0-or-later, LGPL-2.0-or-later (separate program) |
| libsecret (gir1.2-secret-1) | Purser reads and changes saved logins (1.122) | LGPL-2.1-or-later |
| gcr | Asks for a keychain password when one is needed (1.122) | LGPL-2.0-or-later |
| pyzbar (python3-pyzbar), ZBar (libzbar0), Pillow (python3-pil) | Purser reads a setup QR code off the screen (1.123) | MIT; LGPL-2.1-or-later; MIT-CMU |
| clang, lld (build only) | Compiling Mac test programs for Ferry | Apache-2.0 with LLVM exception |
| wayvnc | Screen Sharing: shares the Wayland screen over VNC | ISC (separate program) |
| GTK-VNC | The screen view in Porthole | LGPL-2.1-or-later |
| Samba, wsdd-server | File Sharing (SMB) and being found by Windows | GPL-3.0-or-later (separate programs) |
| GNOME Web (Epiphany) | Web browser shipped in the image | GPL-3.0-or-later (separate program) |
| xdg-desktop-portal(-gtk) | Color-scheme setting, file pickers | LGPL-2.1-or-later |
| libdbusmenu / appmenu-gtk-module | Exporting app menus for the global menu bar | LGPL-3.0 / LGPL-3.0-or-later |
| Poppler (GLib bindings) | PDF pages in Frame, Seek and Glance | GPL-2.0-or-later |
| Tesseract (tesseract-ocr, tesseract-ocr-eng), Leptonica | Live Text in Frame (1.124), Hover Text (1.125) | Apache-2.0; BSD-2-Clause |
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
| **Topline** | Global menu bar | Python + GTK 3 (layer-shell), C later if needed | Left: system menu, focused app name, the app's own menus (GTK apps since 0.8, through strata-shell; Qt apps planned). Right: network, sound and battery icons (0.4), Bluetooth and printing (0.8), clock; app status icons (StatusNotifierItem) and quick settings later. Falls back to a minimal per-app menu when an app exports none. Window > Move & Resize (1.51) works out a half or a quarter of the output's work area (the screen less the bar and the Dock) and moves the window there through Wayfire's `window-rules/configure-view` IPC call, keeping the size it had so Return to Previous Size can put it back. The bar never refills a menu while one is open, since taking its rows away under the pointer also closed any submenu GTK had just opened on hover; it catches up when the menu closes. When it hides itself (1.64, `menubar_autohide` in shell.json, set in Dials) it gives up its exclusive zone (-1, so windows use the whole height), slides the bar up inside a GtkRevealer while the surface stays put, and takes input only on the screen's top row of pixels until the pointer arrives there; an open menu or Help keeps it down.; 1.70: the freemac menu (About, Settings, Harbor, Recent Items, Force Quit, Sleep, Restart, Shut Down, Lock Screen, Log Out) runs `freemac-power` (session.py) for the last four: a Mac-style question that goes ahead by itself after 60 seconds, then every app window is closed through Strata's `strata/close` (so apps offer to save), and only when none is left does it run `systemctl reboot/poweroff` or end Wayfire. A window with a parent (a Save changes? question) keeps it waiting up to 5 minutes; otherwise, 10 seconds with nothing closing stops it with an alert naming the app. Recent Items (recent_items.py): Topline records each app that comes to the front in `~/.local/state/freemac/recent-items.json`; documents come from recently-used.xbel, and Clear Menu hides the ones opened before it without touching Drawer's Recents; 1.74: microphone and camera dot (`inuse.py`: running capture streams from `pw-dump --monitor`, and /dev/video* held open by the person's own processes, checked every 3 s); the bar takes the pointer again whenever its width changes; 1.76: low-battery warnings, sleeps at 2%; 1.80: the input menu (`status.InputMenu`) reads and sets the keyboard group through Strata's `strata/input-source` IPC call, which reads the layout names from the keymap and sets the group on every keyboard with `wlr_keyboard_notify_modifiers`; it shows only with two or more sources While someone is using the screen through Screen Sharing (1.86), an icon shows who, with Disconnect; it learns of viewers from wayvnc's own connect and disconnect events (`wayvncctl event-receive`), because asking wayvnc 0.7 for its list while a viewer is still connecting crashes it. 1.95: the green button's menu (`window_tiles.py`): a layer-shell panel that Topline shows when the pointer rests on a window's green button, told over `$XDG_RUNTIME_DIR/freemac-topline.sock`. Strata's decorator sends `tiles VIEW X Y` and `leave VIEW` for its own title bars; GTK apps, which draw their own, load the GTK 3 module `libfreemac-zoom.so` (`strata/gtk/freemac-zoom.c`, through `GTK_MODULES` in freemac-session), which sends `hover PID` and `unhover PID` from the headerbar's maximize button, and Topline then asks `strata/pointer` where the pointer is and which window is under it. The picks use the same `_place`, `_fill`, `_center` and `_unplace` as Window > Move & Resize. 1.125: Hover Text (`hover_text.py`): Strata's `hover-text.hpp` watches the chosen key (`strata-shell/hover_text_key`) held on its own and, once the pointer has rested 120 ms, sends `hover at X Y` over the same socket (`hover stop` when the key is let go, or another key, a button or a scroll comes). Topline asks `strata/hover-cursor` to hide the pointer, takes a 760×64 strip around it with `grim -g`, enlarges it three times and reads it with `livetext.Reader`, then shows the line the pointer is on in an overlay panel above the strip (below it under the menu bar), with no input region. 1.130: Strata hides the pointer until Topline shows it again (or 3 s pass) and answers `strata/hover-cursor {"query": true}` with whether every output has drawn a frame without it (an `OUTPUT_EFFECT_POST` hook), so the picture is taken only then; one picture at a time. The same watch runs when `strata-shell/hover_speak` (Speak items under the pointer) is on, and Topline then reads the line out through `speak.say`, once per line, showing the panel only if Hover Text is on too. `announce.py`: the clock's tick says the time when shell.json `announce_time` (`hour`, `half`, `quarter`) is due, and Beacon reads a banner as it shows when `announce_notifications` is on; neither while a Focus is on. 1.131: the Sound menu (`status.Sound`): the slider, the outputs from `audio.outputs()` (`pactl -f json list sinks`, less mono's own device) and Sound Settings…; Topline runs `pactl subscribe` and, on each sink, server, module or card event (200 ms apart at most), updates the speaker and calls `audio.keep_mono()`. 1.133: the Battery button (`status.Battery`) keeps a sample in `battery.record()` (`~/.local/state/freemac/battery-history.json`: time, percent, plugged in; every 5 minutes or when plugged in or unplugged; ten days) and, when shell.json `low_power_mode` or the charger changes, calls `battery.apply_low_power()`, which sets power-profiles-daemon's Power Saver (`powerprofilesctl`, allowed for the active session) and hands back Balanced only if it chose Power Saver itself (`~/.local/state/freemac/low-power-mode`); the icon gets the `battery-low-power` class (yellow) while it's on. |
| **Backdrop** | Desktop wallpaper | Python + GTK 3 (layer-shell, background layer) | One window per screen under the menu bar and dock; fills the screen at any shape (or fits or stretches, set in Dials). Replaced wf-shell's background in 0.4. Since 1.4 the first screen also shows the Desktop folder's files as icons down the right side (`desktop_icons.py`): click to select, double-click to open, drag to place (kept in `~/.config/freemac/desktop.json`) or drop files in, right-click for Rename, Move to Trash, New Folder and Change Wallpaper. Since 1.25 Backdrop also mounts each drive, memory card or phone as it is plugged in (GIO with udisks2 and gvfs, `volumes.py`) and shows it on the Desktop; Eject is on its right-click menu, ⌘E, or a drag onto the Dock's Trash. Since 1.44 Use Stacks (⌃⌘0, kept in `desktop.json` beside the places) gathers files of one kind (`kind_of()`: by content type, with Screenshot names first) into a `StackIcon` drawn as a small pile with cairo; with stacks on the desktop lays itself out (drives, folders, stacks with any fanned-out files after them, then the rest) and the saved places wait for stacks to go off. Clean Up By rewrites the places in order; Get Info uses Drawer's `drawer_info`. 1.45 `desktop_widgets.py` puts widgets on the desktop layout (`WidgetHost`, kept in `widgets.json`): clock, calendar, weather and reminders cards drawn with cairo and Pango from Chime's time, Tide's and Nudge's stores and Sky's cached forecast; a click opens the app, a drag moves the card, and a Gallery window adds and removes them. 1.135 adds battery (battery.py), Screen Time (Logbook's day), world clocks (Chime's cities with zoneinfo offsets), the newest sticky note and a photo of the day (from ~/Pictures, JPEG photos first, picked by the date) widgets; `paint()` draws any kind, dark on the desktop or light cards with dark ink through `scheme()`. The desktop list and the Notification Centre's list (`centre`) share `widgets.json`, and each side watches the file with a Gio monitor, so the one Gallery (a tab per place, with `DesktopFile` and `CentreFile` standing in for the side in the other process) changes both; 1.67: click the wallpaper to reveal the desktop (reveal.py hides the windows on screen through strata/hide and brings them back on the next click) |
| **Pier** | Dock | Python + GTK 3 (layer-shell) | Pinned and running apps from Wayfire's IPC; cursor-proximity magnification (the pointer is read from the Dock window itself, since each icon is a button with its own input window); the hovered app's name drawn above its icon in the Dock's own surface, not as a GTK tooltip, which would cover the pointer; the surface spans the screen's width so magnifying never resizes it, takes input only over the resting shelf until the pointer arrives, and the icons shrink, and grow less, when the Dock would not fit; running indicators; size and magnification set in Dials. Tells Strata where each window goes when minimized (`strata/minimize-hint`): its own small picture beside the Trash (drawn by Strata with `strata/snapshot`), or its app's icon if Dials says so. Strata shrinks the window into that place and grows it back out. Hidden apps' windows (`strata/hide`, `strata/hidden`) get no picture. Right-click or hold an app for its menu: its windows, its recent files (`recents.for_app`: files the recent-files list says it opened, or that it is the usual app for, newest first; up to five), Keep in Dock, Hide and Quit. A right-click on the shelf between icons reaches the Dock window itself (the shelf sits in a revealer, which has its own window) and gives Turn Hiding On/Off, Turn Magnification On/Off and Dock Settings…, written to pier.json. Every new input region is followed by a redraw, since Wayland applies it with the next frame; without one, turning hiding off left the Dock deaf to the pointer. When it hides itself (`autohide` in pier.json, set in Dials or by ⌥⌘D through `freemac-keys dock-autohide`) it reserves no space, sits on the screen's edge (exclusive zone -1), and slides the shelf down inside a GtkRevealer while the surface itself stays put, taking input only on the bottom row; the compositor mistakes where a still pointer is over a moving surface. Open menus and drags keep it up. Apps that stay open with no window (Quill, Jot; listed in held.py) are watched on the session bus by the names they own, so their dot stays and Quit asks the app itself to quit. Apps used lately that are not kept stay after they quit (1.61): Pier notes an app as it quits in ~/.local/state/freemac/dock-recents.json and shows the three newest after the open apps, unless pier.json has "recents": false. The Dock sits on the edge that pier.json's "position" names (left, bottom or right; 1.63): the shelf turns vertical, each icon's dot goes beside it, magnification, the name label (beside the icon), menus (popped up beside the item), drags, the input region and the revealer's slide all follow the axis. Moving to another edge restarts the Dock in place (`os.execv`), since a layer-shell surface keeps its anchors. Backdrop reads the same key and keeps its icons clear of a Dock on the right. |
| **Seek** | Search launcher on Super+Space | Python + GTK 3 (layer-shell) | Apps (`.desktop`), Dials pages (`dials_pages.py`), Guide topics (`guide_topics.py`), the front app's menu items (Topline's `SearchMenus` on D-Bus), files in the home folder by name and by the words inside them, calculator. A preview beside the results shows the chosen picture, a PDF's first page, the start of a text file, a file's kind, size and date, or an app's description.. Stays running (started with the session); `freemac-seek` asks the running copy over D-Bus, and the file index is updated while it's closed. Also finds contacts, coming events and reminders.; 1.68: unit conversions (convert.py: length, weight, volume, temperature, speed, time, data, area); 1.88: seek_settings.py (~/.config/freemac/seek.json) turns kinds of result off and keeps folders private, read by Seek, its index and Drawer's searches; Dials > Seek (dials_seek.py) changes it |
| **Drawer** | File manager | Python + GTK 3 | Icon, list and column (Miller) views with a preview pane; sidebar of places, with drives under Locations and an Eject button on each (`volumes.py`, shared with Backdrop and Pier); GIO for opening files and the Trash. Share (`share.py`, also used by Cove and Frame): a toolbar button, a right-click menu and File > Share… offer Mail, which opens Post with a `mailto:?subject=…&attach=/path` link (Post attaches the files it names), and Copy to each drive, which copies on a thread, names a copy “name 2” rather than replace a file, and says how it went. Moving and copying (`transfer.py`, also used by Backdrop): ⌘C keeps the paths in `~/.cache/freemac/file-clipboard.json` beside the names as clipboard text, and ⌘V/⌥⌘V, ⌘D and drops onto folders, sidebar places and drives run a `Job` on a thread: a move on the same disk is a rename, anything else is copied in 1 MB pieces with a progress window after 0.6 s, a taken name asks Keep Both, Stop or Replace (the old item goes to the Trash), and Stop removes the half-made copy. Each move, copy, rename, new folder and Move to Trash is kept for ⌘Z in `~/.cache/freemac/file-undo.json` for two hours.; 1.72: Get Info's Open with and Change All… Connect to Server (1.83, `servers.py`) mounts smb, sftp, ftp and WebDAV addresses with GIO; gvfs-fuse gives them a path, and they show under Locations with Eject. The Network place (1.84, `neighbours.py`) lists GVfs's network:/// (DNS-SD, WS-Discovery and SMB browsing) as it answers and connects through `servers.py`. 1.85: opening a computer in Network mounts the server itself (smb://host/), which has no FUSE path, so `servers.connect` reports `NO_FOLDER` and Drawer lists that server's shares at `network:smb://host/` (`neighbours.browse` with that URI; names ending in $ are hidden). The mount operation answers GVfs's first password question as anonymous when that's allowed, so a guest share opens with no dialog; a refusal shows the usual sign-in. Connected folders are titled by the share's name. 1.87: searching (`smart_folders.py`). Typing in the toolbar box filters the folder on show at once; a scope bar offers This Mac, which goes to a search place (`search:?text=…&kind=…&when=…`) that walks the home folder on a thread (hidden folders, the Trash and build folders left out, at most 1,000 results) and then adds documents whose words match from Seek's index (`seek_index.search`), with rows added every 120 ms as they're found; Kind and Last changed narrow it and work with no words. Save keeps the search under a name in `~/.config/freemac/smart-folders.json` as `smart:Name`, listed under Smart Folders in the sidebar, and it searches again each time it opens. The sidebar scrolls when it's too tall. |
| **Tack** | App switcher | Python + GTK 3 (layer-shell, overlay layer) | Alt+Tab shows the open apps, last used first, as large icons on a translucent panel; Tab and Shift+Tab move, letting go of Alt brings that app's windows forward (restoring one if all are minimized, or every window of a hidden app). While it is up, Q quits the chosen app and H hides it (1.60). Runs with the session and hears the key presses on a socket, so it answers at once. Replaced Wayfire's fast-switcher in 1.4. |
| **Dials** | Settings app | Python + GTK 3 | Appearance (light/dark through the GSettings `color-scheme` and GTK theme), wallpaper, dock and menu bar, displays (resolution, refresh rate, scale, rotation, arrangement and mirroring from Strata's `strata/outputs`, written to `[output:NAME]` in wayfire.ini with a 15-second Keep or Revert, 1.92; the main display, which has the menu bar, the Dock and the Desktop's files, as shell.json `main_display`, followed by Topline, Pier and Backdrop through `main_display.py`, 1.93), trackpad and mouse, keyboard layout, network and Wi-Fi, sound (WirePlumber's wpctl), power (screen blanking through Wayfire's idle plugin, power-profiles-daemon), notifications, accessibility (with screen zoom: Wayfire's `zoom` plugin, on or off in `core/plugins`, and the key held while scrolling in `zoom/modifier`, 1.51), Bluetooth (BlueZ over D-Bus, with its own pairing agent), printers (CUPS), users (through a small root helper run with pkexec: add, delete, change password, administrator, automatic login), about. Date & Time (`dials_time.py`) talks to systemd-timedated over D-Bus (SetNTP, SetTime, SetTimezone, with polkit asking for an administrator's password); the time zone is found by typing a city, and the menu bar clock's format (12 or 24 hours, day, date, seconds) is kept in Dials' own settings, which Topline reads. Topline watches `/etc/localtime`, so a new time zone shows at once. Writes the same files Wayfire, Backdrop and Pier watch, so changes apply at once.; 1.65: Accessibility > Reduce transparency (solid menu bar, Dock and panels) and Invert colours with ⌃⌥⌘8 (Wayfire's invert plugin); 1.66: Login Items page (dials_login.py) over ~/.config/autostart, the list the Dock's Open at Login ticks; 1.71: Software Update page (Check for Updates, and security fixes installed automatically) and Network > Firewall, both behind an administrator's password; 1.72: default web browser and email app (`default_apps.py`, written to mimeapps.list through GIO); 1.73: Accessibility > Spoken Content: Speak selection (`speak.py`, `freemac-speak` on ⌥Esc reads the primary selection through espeak-ng; press again to stop), voice and rate; 1.75: Appearance > Accent colour: make-theme.py writes a GTK 3 theme, a GTK 4 style sheet and a Qt colour scheme for each accent in light and dark (freemac-purple, freemac-dark-purple…), Dials switches `gtk-theme` to the chosen one, and the shell's own style sheets use `@theme_selected_bg_color`; 1.76: battery time left and Show percentage 1.79: Sharing (`dials_sharing.py`): Computer name sets the pretty and network host names through `freemac-system-helper computer-name` (hostnamectl, /etc/hosts, Avahi for name.local), which Hail also uses; Remote Login turns OpenSSH on or off (`remote-login on|off`: makes this computer's own host keys, since the image ships none, and lets port 22 through the firewall from local networks only); 1.80: Keyboard > Input Sources (`input_sources.py`, `dials_input.py`): the XKB layouts and variants by name from the rules' evdev.lst, up to four, written to `[input] xkb_layout`/`xkb_variant`; ⌃Space is a Wayfire command binding (`freemac-input --next`) written only while there are two or more, rather than XKB's grp:ctrl_space_toggle, which also fired on ⌃⌘Space; Key repeat rate and Delay until repeat set `kb_repeat_rate` and `kb_repeat_delay`; 1.81: Keyboard > Check spelling while typing (`check_spelling` in shell.json): `spelling.py` attaches gspell (Enchant with Hunspell's en-US/GB/CA/AU dictionaries) to the writing views of Jot, Post, Stickies, Quill (only for plain text, Markdown, LaTeX, reStructuredText and AsciiDoc), Tide, Nudge, Crew, Corkboard and Lantern, and turns inline checking on or off when shell.json changes; words added to the dictionary go to gspell's personal word list; 1.82: `textinput.py` watches each key typed into the same views (one character at a time, so pasted text is left alone, and not in Quill's code) and, on the next idle, swaps it for a curly quote, turns -- into an em dash, two spaces after a word into ". ", or a Text Replacement's short form into its long one when a space or punctuation follows it, as one undoable step; the replacements are `~/.config/freemac/text-replacements.json`, edited in Dials, and each rule has its switch in shell.json (`text_replacements`, `smart_quotes`, `double_space_period`). 1.85: Sharing > File Sharing runs `freemac-system-helper file-sharing on|off` behind an administrator's password: Samba (smbd) shares the person's ~/Public read-only to guests (`guest only`, `force user`), from `/etc/samba/freemac.conf`, included in smb.conf's [global]; wsdd-server makes it show in Windows' Network, Samba's own mDNS in a Mac's or freemac's; the firewall opens SMB and WS-Discovery to the local network only. Samba and wsdd-server are installed but off in the image. Sharing > Screen Sharing (1.86) turns on `screen_sharing.py`: wayvnc runs inside the person's own session (started at log in by `freemac-screen-sharing --serve`, which restarts it if it stops by itself), with this computer's own certificate and keys made the first time, TLS (VeNCrypt) or RSA-AES only, and the name and password checked through PAM (`/etc/pam.d/wayvnc`, `pam_unix` without `nullok`, so an empty password never works); the system helper opens TCP 5900 to the local network only and refuses an account with no password.; 1.91: Sound > Sound Effects (`sounds.py`, `freemac-sound`): six alert sounds made by `art/sounds/make-sounds.py` with the start-up chime, `alert_sound` and `alert_volume` in shell.json (played with `pw-play --volume`); `volume_feedback` plays `pop.wav` after the volume keys, a scroll on the sound icon or letting go of a volume slider; `ui_sounds` plays `trash.wav` when the Trash is emptied (transfer.empty_trash) and `shutter.wav` for a Lens screenshot. sounds.py reads shell.json itself so the command starts without GTK.; 1.94: Accessibility > Flash the screen when an alert sound occurs (`flash_screen` in shell.json): `sounds.alert()` asks Strata for `strata/flash` over Wayfire's socket directly, still without GTK, even with the alert volume at zero; Test Screen Flash calls `freemac-sound flash`'s same function.; 1.96: Accessibility > Shake mouse pointer to locate writes `[strata-shell] shake_to_locate` (on by default), which Strata watches.; 1.131: `audio.py` (pactl from pulseaudio-utils, talking to pipewire-pulse; no GTK) sets volumes per channel so the balance stays put (`balance_of` and `spread` use PulseAudio's measure, and `~/.config/freemac/sound.json` keeps each output's balance for when its volume is 0); the volume keys, Quick Settings, the Sound menu and Dials all go through it. Sound > Balance and Input level (`InputLevel`: `parec` at 16 kHz mono, its peak every 60 ms over 60 dB on 16 lights, only while the page is showing). Accessibility > Play stereo audio as mono (`mono_audio` in shell.json): `module-remap-sink` makes a one-channel `freemac-mono` in front of the real output and becomes the default; PipeWire mixes stereo down into it and plays its one channel on both sides. 1.132: Storage (`storage.py`, no GTK, measured on a thread; `dials_storage.py`): the disk from statvfs; each kind is the size on the disk (st_blocks) of its folders under the home folder, without following links, on the same disk, hard links counted once; Trash is `~/.local/share/Trash/files`; Applications are the Installed-Size of the packages that ship a `.desktop` file in /usr/share/applications, plus Flatpak; System is the rest of what is used (at least the other packages). Review Files lists regular files of 50 MB or more outside hidden folders, biggest first, and moves them with `transfer.to_trash`. 1.133: Battery (`dials_battery.py`, on the Power page when a battery is there, which is then called Battery): `BatteryChart` draws `battery.levels()` (the last sample in each 15-minute slot, empty where the gap between samples is over 20 minutes: off or asleep) and `battery.days_on_battery()`; Battery Health is `energy_full`/`energy_full_design` (or `charge_*`) and `cycle_count` from the kernel; Low Power Mode replaces the Power mode menu there. |
| **Beacon** | Notifications | Python + GTK 3 (layer-shell) | Implements the freedesktop.org notification D-Bus interface, so `notify-send` and every app's notifications work. Banners in the top-right corner, a centre with a month calendar that marks days with Tide events and lists the chosen day's events (`minimonth.py`, `calendar_store.py`), and the last 50 notifications (opened from the clock), grouped by app into stacks, Do Not Disturb. The rules for what to show (`notify_rules.py`, no GTK) are the Focus in use (1.129: Do Not Disturb, Sleep, Work or Personal, chosen by hand as `focus` in shell.json, or on by its schedule of times and weekdays, which may cross midnight; turning a scheduled Focus off by hand sets `focus_skip` for that stretch; each Focus's `allow` list in `focus_settings` lets those apps' banners through) and each app's choice in `notify_apps` (banners, centre only, off); Beacon keeps the apps that have notified in `~/.local/state/freemac/notification-apps.json` for Dials to list, and urgent notifications always show. Topline shows the active Focus's symbol from the same rules on each clock tick. Since 1.135 everything under the date (the month, the day's events, the Notifications row with Focus, the list and `desktop_widgets.CentreWidgets` under it) is in one scroller that opens at the top, with Clear All fixed below it; the widgets come from `widgets.json`'s `centre` list, refreshed each time the centre opens and redrawn every second while shown, with Edit Widgets… opening the shared Gallery on its Notification Centre tab. |
| **Lens** | Screenshots | Python + GTK 3 | Whole screen, an area or the focused window, on Print, Shift+Print and Alt+Print; uses grim and slurp, saves to the Desktop, copies to the clipboard with wl-copy and announces the file through Beacon. 1.78: ⇧⌘5 opens the Screenshot toolbar (a layer-shell bar with the five modes, Options for Desktop, Documents, Pictures or Clipboard, a 5 or 10 second timer and the floating thumbnail, kept in shell.json); pressed during a recording it stops it. |
| **Quill** | Text editor | Python + GTK 3 + GtkSourceView 4 | Syntax colours, line numbers, find and replace, go to line, wrapping, light and dark schemes, safe saving. |
| **Frame** | Picture and PDF viewer | Python + GTK 3, Poppler | Fit, zoom, rotate, next and previous in the folder, animated GIFs, Trash, full screen; PDFs page by page (`pdf.py`, also used by Seek's preview and Glance). Markup (`markup.py`): marks are plain data in the picture's own pixels, drawn with cairo on screen and into the saved copy; a PDF copy keeps each page as vectors with the marks drawn over it. Signatures are kept in `~/.local/share/freemac/signatures.json`. Live Text (1.124, `livetext.py`): half a second after a still picture or page shows, it is scaled so its longest side is 1,600 to 3,200 pixels and piped as a PNG to `tesseract stdin stdout -l eng tsv` on a thread (two threads, at most 90 s; the next picture stops it); the TSV's words, in reading order with their block, paragraph and line, are kept per file and page, and selection is a range of them, drawn as one box per line. |
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
| **Logbook** | Screen time | Python + GTK 3 + cairo | `logbook.py --track` starts with the session: it follows which app is in front through Wayfire's IPC events, counts time only while the screen is unlocked and swayidle has seen input in the last two minutes, and writes each day to `~/.local/share/freemac/logbook/DATE.json` (five weeks kept). Daily limits live in `~/.config/freemac/logbook.json`; the tracker sends a Beacon notice five minutes before and closes the app's windows at the limit. A passcode for limits is stored salted and hashed.; 1.69: Limit adult websites: /usr/libexec/freemac-family-helper (pkexec, org.freemac.family.websites) sets NetworkManager's global DNS to Cloudflare for Families; 1.89: Downtime (`downtime` in logbook.json: on, start and end as HH:MM, a paused-until time for 15 More Minutes) closes the front app unless it is Always Allowed (`allowed`, desktop ids, plus freemac's own Drawer, Dials, Guide and Logbook), with a notice five minutes before; `extra` adds minutes to an app's limit for one day; 1.138: Screen Time for a family. An administrator picks another account at the top of the window; Manage Screen Time runs `/usr/libexec/freemac-screen-time-helper set NAME` through pkexec (org.freemac.screen-time.manage, auth_admin_keep), which writes the checked limits, Always Allowed and downtime to `/etc/freemac/screen-time/NAME.json` (root-owned, so the child can read but not change them) and makes `/var/lib/freemac/screen-time/NAME/` (owned by the child, group sudo, 2750), where the child's tracker copies each day for the parent's window to read. More time comes from `freemac-screen-time-grant NAME more APP` or `downtime` (org.freemac.screen-time.grant, auth_admin every time, so the parent types their password on the child's screen) into `NAME.grants.json`, which only counts for that day. `set` reports administrators with no password, and Logbook warns the parent. Deleting the account in Dials removes all three. The tracker's lock check now looks only for the person's own gtklock; 1.139: `downtime.custom` with `downtime.days` (seven entries, Monday first, each start and end or null) gives each day its own hours, and a window whose end is before its start runs into the next morning. A limit kept as `category:games` (and so on) counts every app whose .desktop Categories line maps to that kind, first matching rule winning (reading, education, games, social, creativity, entertainment, productivity, utilities, then other); the helper accepts these keys for limits and for `grant NAME more category:KIND` |
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
| **Hail** | Nearby sharing | Python + GTK 3, `ssl`, `http.server`, OpenSSL | `hail.py` speaks LocalSend's published protocol (v2): a JSON "who's there?" message to multicast group 224.0.0.167 on UDP 53317, answered by an HTTPS `POST /api/localsend/v2/register`, and files sent with `prepare-upload` then one `upload` per file. Each computer makes its own self-signed certificate once (`openssl req -x509`); its SHA-256 is the fingerprint other devices use to tell it apart. `freemac-hail --background` (autostarted) listens always, so its own Nearby window can be answered, but answers others' questions and takes offers only while receiving is on; an offer shows an alert (60 s, then declined), names are stripped of `..` and hidden parts, and files are written as `.part` then renamed into Downloads. A Gtk.Application, so `--send FILES` from Share opens the window in the running copy. If nothing answers within 4 s it also asks each address on the local /24 directly. The firewall allows UDP to the group and TCP 53317 from private ranges only. |
| **Porthole** | Screen Sharing viewer | Python + GTK 3, GTK-VNC, OpenSSL | `porthole.py` connects to a computer that shares its screen over VNC (`vnc://` addresses from Connect to Server open it too). Before connecting it reads the computer's certificate in a short VeNCrypt handshake of its own, remembers it the first time (trust on first use, as SSH does, in `~/.config/freemac/porthole/known.json`, handed to GTK-VNC through the CA file it reads), and warns if it changes later; then GTK-VNC connects over TLS on that socket and Porthole asks for the name and password in a sheet. Fit to Window, full screen, and Send Control-Alt-Delete. Original icon: a brass porthole with a screen behind it. |
| **Lifeboat** | Backups | Python + GTK 3, GIO, udisks2 | `backup_store.py` (no GTK) makes each backup as a whole dated copy of the home folder under `freemac-backups/<computer>-<user>/` on the drive, in a folder ending `.inprogress` that is renamed when whole; a file whose size and time are the same as in the backup before is a hard link to that copy, so unchanged files take no more room. Caches and the Trash are left out. Backups thin to all of the last day, one a day for a month and one a week before that, and the oldest go when the drive is full. `lifeboat.py` runs at login with `--watch`: it backs up an hour after the last backup while the drive (known by its uuid, from `~/.config/freemac/lifeboat.json`) is plugged in, stops when the drive is ejected, and writes its state to `~/.cache/freemac/lifeboat-status.json`. Opened from the Dock it shows the backups by date with the chosen folder as it was, and Restore copies items back with `transfer.Job`. Dials > Lifeboat (`dials_backup.py`) chooses the drive and erases one that can't hold hard links with udisks2's `Format` as ext4, owned by the user. |
| **Post** | Mail | Python + GTK 3, WebKit2GTK 4.1, imaplib/smtplib | `mail_store.py` (no GTK) talks IMAP and SMTP over TLS, keeps accounts in `~/.config/freemac/mail` (passwords in a file only the user can read) and a copy of the newest 300 messages of each mailbox in `~/.local/share/freemac/mail`, so mail shows at once and the server is asked only for what's new. Each account has one worker thread; the window never waits on the network. HTML mail is shown by WebKit with JavaScript off and a Content-Security-Policy that blocks everything from the internet until Load Remote Content is pressed; links open in the web browser. The handler for `mailto:` links and `.eml` files. Address completion comes from Crew. |
| **freemac-sync** | Online calendars, contacts and reminders | Python (Gio, http.client) | Accounts are added in Dials > Internet Accounts (`dials_accounts.py`) and kept in `~/.config/freemac/accounts.json`, passwords in a file only the user can read. `dav.py` (no GTK) is a small WebDAV client: it finds the account's calendars and address books from the server's address (`.well-known`, principal, home set), lists items with their ETags, fetches them with multiget and writes with If-Match. `dav_sync.py` keeps each collection in step with Tide's calendar file, Crew's cards and Nudge's lists both ways: changes are found by ETag on the server and by a hash of each item here, new items made here go to the account's first calendar or address book, and when both sides changed the server wins. Items that came from an account carry an `X-FREEMAC-SOURCE` line (never sent to the server), so turning a kind off or removing the account takes only those off this computer. `sync_service.py` runs from the session's start, syncs every 15 minutes and a few seconds after Tide, Crew or Nudge saves; running `freemac-sync` again syncs at once (Dials' Sync Now). |
| **Harbor** | App centre and updates | Python + GTK 3 | Browses the AppStream catalogue of the archive (categories, search, picks), app pages with Install, Open and Remove, an Installed list and an Updates page, all through PackageKit, which asks for the password through polkit. A background check once a day notifies through Beacon when updates are ready. Refreshes old package lists before installing. |
| **Latch** | Lock screen | Python (launcher) + gtklock | Locks with gtklock dressed in freemac's style (current wallpaper, large clock, password field); Ctrl+Command+Q and Lock Screen in the system menu; swayidle locks after the idle time set in Dials > Power, and before sleep. While a screen saver shows, the idle lock (`freemac-lock --idle`) only leaves a mark, and the screen saver locks before it closes. Since 1.136 the gtklock module (`strata/latch/freemac-latch.c`) starts `freemac-lock --feed`, which sends tab-separated blocks (battery, the MPRIS player `media.py` picks, Beacon's notifications since the lock, filtered by Focus and `notify_previews`, and `lock_message`) every two seconds when they change, and takes back `play-pause`, `next` and `previous`; the module shows them as a battery in the corner, cards under the clock (as many as fit above the person, then "N more notifications") and a line under the password field. |
| **Screen Saver** | Screen savers | Python + GTK 3 (layer-shell) + cairo | `freemac-screensaver` (saver.py): one overlay-layer window per screen, the pointer hidden, ended by a key, a click or a pointer move of more than a few pixels. Drift (glowing gradients added together), Clock (Pango text bouncing slowly) and Album (Pictures, else the wallpapers, cross-faded with a slow zoom). swayidle starts it (in the background, since `-w` waits for each command) after `saver_after` minutes and ends it on resume; a hot corner can start it. Each saver draws a frame for any size and time, which is how Dials draws its stills. |
| **Tally** | Calculator | Python + GTK 3 | Its own expression parser (decimal arithmetic for the basic operations), a running tape, a scientific mode with degrees or radians, `Ans`, and keyboard entry. |
| **Chime** | Clock | Python + GTK 3 | World clocks, alarms with repeat days, timers and a stopwatch. Keeps running in the background while an alarm or timer is set, rings with the freedesktop sound theme and notifies through Beacon. |
| **Marina** | Full-screen app grid | Python + GTK 3 (layer-shell) | Every app that shows in menus, freemac's first, then A to Z, in pages over a blurred copy of the wallpaper; filters as you type. Drop an app on another to make a folder; drag to rearrange (kept in ~/.config/freemac/marina.json). Opened with F4, from Pier or a hot corner. |
| **Jot** | Notes | Python + GTK 3 | Each note is a plain text file in `~/Documents/Notes`; the first line is the title. Saves a moment after typing stops, searches as you type, and notes show up in Seek and Drawer like any file. |
| **Guide** | How-to topics | Python + GTK 3 | Short topics in `guide_topics.py` (no GTK, so Topline's Help and Seek read them cheaply); `freemac-guide --topic NAME` opens one, in the window already open if there is one. |
| **Ferry** | Optional Mac program layer | C | Loads Intel Mach-O programs and connects them to our own libSystem conversions. Not on the ISO; see [Mac app compatibility](#mac-app-compatibility-optional-layer). |
| **Keel** | Installer | Python + GTK 3, root backend | Whole-disk GPT install (BIOS boot, EFI and ext4 partitions, or with encryption a separate /boot and a LUKS2 root, 1.141); copies the pristine live image, creates the account, removes live-only parts, installs GRUB for BIOS and UEFI. The password goes to the backend on stdin, never on a command line. |
| **Gangway** | Login screen | Python + GTK 3 in cage | A greetd greeter that starts freemac-session.; 1.90: the Guest User (the account `guest` with the mark `/etc/freemac/guest-user`, made and removed by `freemac-users-helper guest on` or `off`, with no password) is chosen with no password box; `freemac-session` empties `/home/guest` and copies `/etc/skel` in before the guest's session starts and again after it ends; the image adds `_greetd` to the `video` group so cage can open the seat again after a log-out. Since 1.137, fast user switching (`switch_user.py`): every person after the first logs in on terminal 8 to 12, where `freemac-greeter@N.service` runs `/usr/libexec/freemac-switch-helper greeter N` (a second greetd with its own config and socket in `/run`); `freemac-switch-to@N.service` shows a terminal with VT_ACTIVATE, and seatd hands the screen to that terminal's compositor. A polkit rule (`50-freemac-switch-user.rules`) lets `_greetd` and the active local session start only those two units for terminals 7 to 12. Topline's user menu locks first; the pick is left in `/tmp/freemac-switch-choice-UID` for Gangway to choose that person. Gangway asks logind which people already have a session and switches to it instead of logging in again. |
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
  window (`[strata-shell] global_menus`). For gtk_shell1's `system_bell`,
  which GTK rings for `gtk_widget_error_bell()` and `gdk_display_beep()`,
  it runs `freemac-sound alert` (at most every 150 ms), so every GTK app's
  alert plays the sound chosen in Dials > Sound (1.91; Wayfire makes none).
  Its IPC method `strata/outputs` lists every display as Wayfire sees it:
  make, model, physical size, built-in or not, whether it shows itself, is
  mirrored or off, its mode, scale, rotation, place in the layout and every
  mode it can show. Dials > Displays reads it (1.92). `strata/flash`
  (`screen-flash.hpp`) flashes every display once: a post-processing hook
  mixes the finished frame toward white, quickly up and fading over 380 ms,
  then takes itself off. `freemac-sound alert` calls it when shell.json's
  `flash_screen` is on (Dials > Accessibility, 1.94), for anyone who can't
  hear the alert sound.
  `strata/pointer` gives the pointer's place in the layout and the app
  window under it; Topline asks when an app's own green button says the
  pointer is resting on it (1.95). The decorator tells Topline itself when
  the pointer rests 550 ms on one of its own green buttons.
  `strata/keep-awake` (1.103) holds or lets go of a Wayfire idle
  inhibitor, for the keep-awake service in `freemac-lock --watch`.
  `pointer-locate.hpp` (1.96) watches pointer motion after Wayfire handles
  it; five quick turns within 900 ms, each after 40 px of travel, are a
  shake. The pointer is then hidden and a large arrow, drawn once with
  Cairo, is drawn in its place as an overlay on the display under it,
  growing to four times the size, staying while the shaking goes on and
  shrinking back 450 ms after it stops (`strata-shell/shake_to_locate`).
  `press-hold.hpp` (1.97) gives held letters their accents. A plain letter
  that has accents (a c e i l n o s u y z, Shift allowed) is sent to the app
  once, as a press and a release, so it never repeats; held 450 ms, Strata
  tells Topline over its socket to show the panel at the text cursor
  ("accent show LETTER X Y H"), passes it the number keys, arrows, Return
  and Escape while it shows, and types the pick (`strata/accent-type`): with
  delete-surrounding-text and commit-string where the app reports the text
  around its cursor, otherwise with a Backspace key and then the accent,
  sent once the app has answered the Backspace. Apps only say which text
  field has the keyboard while an input method runs, so `freemac-im`
  (strata/im, started by Topline) is a quiet input method that does nothing
  else; an app that says nothing gets the panel by its window and the
  accent through wtype (`strata-shell/press_and_hold`).
  `sticky-keys.hpp` (1.98) is Sticky Keys: a modifier key tapped on its
  own (Shift, Control, Option or Command, by what the layout makes the key)
  stays down for the next key, and a second tap locks it until a third.
  Strata only watches the keys; once a tap counts, it sets the sticky
  modifiers on the keyboard itself with `wlr_keyboard_notify_modifiers`
  when the key event is over (wlroots updates the keyboard's state after
  the event), so apps, Wayfire's bindings and the Command key all see them
  held. A latched one is let go just after the next key. Five Shifts in a
  row turn it on or off (`strata-shell/sticky_keys`,
  `strata-shell/sticky_keys_shift`); Topline saves that and shows the
  modifiers that are set in the top-right corner ("sticky state ...").
  `slow-keys.hpp` (1.126) is Slow Keys: Strata connects to the keyboard
  first and holds back each key press (`IGNORE`). Let go before the
  acceptance delay (`strata-shell/slow_keys_delay`, 100 to 2000 ms) and the
  press and its release go nowhere; held that long, the press is sent again
  as the keyboard itself would send it, with `wlr_keyboard_notify_key`
  (without updating the keyboard's state a second time), so Wayfire's
  bindings, the Command key, press and hold and the app all see an ordinary
  key, and the app repeats it while it's held. Modifier keys pass at once.
  With `strata-shell/slow_keys_click` on it sends "slow pressed" and "slow
  accepted" to Topline, which plays a tick and a pop from two GStreamer
  players kept loaded (`slow_keys.py`): starting a player program for each
  key held the keyboard up long enough on a slow machine for the app to
  repeat the key.
  `screen-keyboard.hpp` (1.127) types for the Accessibility Keyboard:
  Topline's panel (`screen_keyboard.py`, a layer-shell surface that never
  takes the keyboard, so the app being typed in keeps it) calls
  `strata/press-key` with a key code and "tap", "press" or "release", and
  Strata sends it through the seat's own keyboard with
  `wlr_keyboard_notify_key`, updating its state, so a clicked Shift or
  Command is held for the next key exactly as a pressed one is. Slow Keys
  lets these through at once. `strata/release-keys` lets go of anything
  still held when the panel closes. The panel labels its keys from the
  keyboard layout in use (`Gdk.Keymap`), and is dragged with
  `strata/pointer`, since a Wayland window doesn't know where it is.
  `mouse-keys.hpp` (1.128) is Mouse Keys: with `strata-shell/mouse_keys`
  on it swallows the keypad keys (and, with `mouse_keys_letters`, the
  letter keys a laptop uses instead) and drives a wlr_pointer of its own,
  announced on the backend's `new_input` signal so the seat treats it like
  any mouse, sending motion, button and frame events. A held key moves the
  pointer every 16 ms, still for `mouse_keys_delay` and then speeding up
  to `mouse_keys_speed`. Option tapped alone five times tells Topline
  "mouse turned on" or "off"; Topline saves the setting, plays a sound
  and shows a notice (`mouse_keys.py`).
  `colour-filters.hpp` (1.99) is Colour filters: greyscale, filters for
  red/green and blue/yellow colour blindness, or a colour tint, at a chosen
  intensity (`strata-shell/colour_filter`, `colour_filter_intensity`,
  `colour_filter_tint`). Each display gets a post-processing pass that
  multiplies every pixel by one colour matrix, worked out from the filter
  and blended toward no change by the intensity. The colour-blindness
  filters take the screen as it would be seen (widely published
  simulation matrices), and add what's lost back into the channels that
  remain. With the filter off there's no pass at all.

Mission Control's row of desktops (1.108, `strata/shell/mission-control.hpp`
and `spaces.py` in Topline): the overview of windows is Wayfire's scale
plugin, which holds the pointer while it is open, so the row along the top
never gets the pointer itself. Strata notices scale opening (its
`scale-filter` signal) and closing (`scale-end`) and tells Topline over
Topline's socket ("spaces open OUTPUT", "spaces close", "spaces changed"), and
while it is open reports where the pointer is near the top of the screen
("spaces pointer X Y"). Topline draws the row as an overlay layer surface that
takes no input: desktop names, opened out into pictures (the wallpaper, and a
`strata/snapshot` picture of each window, with its shadow cut away, placed
from `strata/desktops`) when the pointer comes up to it. It sends where each
desktop is drawn with `strata/spaces-areas`; Strata keeps a click inside one
of those areas from the overview, closes the overview through its own
`scale/toggle` IPC method, and once scale has ended asks for that desktop
(`request_workspace`, so vswitch slides there) and brings its front window
forward. Wayfire 0.9 has no IPC call to change desktop, so this lives in
Strata. Dragging a window onto a desktop in the row (1.109) uses the drag
that scale already does: while scale's drag holds the pointer no motion
signals arrive, so Strata looks at the pointer on a 40 ms timer while the
overview is open and a window is dragged, shrinks the dragged window near the
row (`core_drag_t::set_scale`), and on the drag's `drag_done_signal` over one
of the desktops moves the window there (`move_to_workspace`); scale lays out
the windows left when the window's geometry changes. Adding and closing
desktops (1.110) changes the `core/vwidth` option in place, so every output's
workspace set picks up the new grid through the option's callback; Topline
sends the "+" and each corner button as extra areas (desktop -1 for "+", -2
and an index for a close button) and saves the count to wayfire.ini when
Strata says "spaces desktops N". Closing a desktop first moves the desktop
showing, with its windows held in place (`set_workspace` with them as fixed
views), so scale never finds itself on an empty desktop and ends; then the
windows on later desktops move along by one, and the closed desktop's go to
Desktop 1. Desktops are only added or closed when the grid is a single row.
Assigning an app to desktops (1.111) is the Dock's Options > Assign To menu
calling `strata/assign` ("all", "none" or a desktop index; `strata/assignments`
lists them). Strata keeps them in `~/.config/freemac/desktop-assignments` and
applies them: an app on all desktops has its windows made sticky; an app on
one desktop has its windows moved there, and a window it opens is moved there
on idle after mapping (after the other plugins have placed it) and the
desktop is switched to it with `request_workspace`, as on a Mac.
App Exposé (1.112) reuses the same scale session: the `app_expose` key
binding, or `strata/app-expose` with an app-id (the Dock's Show All Windows),
remembers the app and calls `scale/toggle_all`. While it is set, Strata's
scale filter hides every view whose root parent has another app-id, and the
desktops row is not opened; the same key again calls `scale/toggle_all` to
close it, and the end of scale clears it.
A window put in full screen (1.113) gets a desktop of its own, as on a Mac.
Strata watches `view_fullscreen_signal` and, on idle once core has given the
window its new size, adds a desktop at the end of the row and slides there
with `request_workspace` and the window as a fixed view. Leaving full screen
or closing the window slides back to the desktop it came from, and the empty
desktop is closed once the slide is over. `strata/desktops` lists these
desktops under "full-screen" so Topline names them after the app, and the
corner button on one calls `fullscreen_request(false)` instead of closing it.
Because Topline writing wayfire.ini makes Wayfire read it again, the count is
only saved while no window has a desktop of its own, so these are never kept.
Mission Control on an empty desktop (1.114): Wayfire's scale will not open
with no views, so Strata also binds the scale keys itself. On idle after the
key, if neither scale nor App Exposé opened (and scale did not just close),
it tells Topline `spaces open OUTPUT out`, which shows the desktops row opened
out and keeps it open while the pointer is away. A click on a desktop goes
there, and Esc, a click elsewhere or the key again closes the row; Strata
takes those presses so they do not reach the desktop underneath.

Known Networks (1.121, `known_networks.py`): Dials > Network lists
NetworkManager's saved Wi-Fi connections (libnm, newest `connection.timestamp`
first). Join Automatically sets `connection.autoconnect` and Forget deletes
the connection, both through libnm, which freemac's polkit rule already allows
for people in the sudo or netdev group. The password is kept for the whole
computer, so showing or copying it runs `/usr/libexec/freemac-wifi-password
UUID` through pkexec (its own polkit action, `org.freemac.wifi.password`,
auth_admin_keep, so the prompt says what it's for). The helper reads only a
saved Wi-Fi connection named by a well-formed UUID and prints its PSK (or WEP
key) with `nmcli -s`; the window reads it from the helper's output. The
QR code is the usual `WIFI:T:WPA;S:…;P:…;;` text, drawn with python3-qrcode's
matrix in Cairo. GTK can't offer the x-kde-passwordManagerHint type, so a
copied password is marked for clipboard history instead: a SHA-256 of it in
`$XDG_RUNTIME_DIR/freemac-clips-secret` (mode 600) for 30 seconds, which
`clips.store()` checks before keeping a copy.

Passwords (1.122, `keychain.py`, `logins.py`, `purser.py`): the keychain is
gnome-keyring's secret service (org.freedesktop.secrets), which Web and other
apps already use through libsecret. greetd's PAM file opens its "login"
keyring with the login password (pam_gnome_keyring). An automatic login types
no password, so `freemac-login-items` calls `keychain.ensure_login()`, which,
when there is no login keyring yet, makes one with an empty password through
gnome-keyring's own D-Bus interface (CreateWithMasterPassword; the label
"login" picks the keyring's name) and makes it the default alias. Changing
your own password in Dials asks for the current one and, once the account
helper has changed it, calls ChangeWithMasterPassword with the old and new
passwords (an empty old one too, unless the account logs in by itself, whose
keyring keeps no password); if neither opens it, Dials says the old password
will be asked for once. Purser reads and writes the items Web saves, of the
`org.epiphany.FormPassword` kind (uri, username, form field names; the
password as the secret), through libsecret, so a login changed in Purser is
the one Web fills in. Logins added by hand have no form field names, which
Web needs to fill a page, until Web saves its own. Before showing anything
Purser asks polkit about its own action, `org.freemac.passwords.unlock`
(auth_self_keep), for its own process (CheckAuthorization with a unix-process
subject and AllowUserInteraction), so the agent asks for the person's own
login password; no helper runs as root. It locks after 5 minutes without
focus. Wi-Fi passwords come through `known_networks.fetch_password`, the
1.121 helper. The Security list compares passwords in memory: one used on
more than one origin, or one that is short, all digits, from few characters
or on a short list of the passwords people pick most.

Verification codes (1.123, `codes.py`): Purser works out the six-digit codes
for two-step sign-in itself, TOTP (RFC 6238) over HOTP (RFC 4226) with
Python's hmac and hashlib (SHA-1, SHA-256 or SHA-512; 6 to 8 digits; the
period from the setup address). Each setup key is a keychain item of
freemac's own `org.freemac.Purser.Code` kind, with the login's origin and
user name as attributes and the base32 key as the secret, so the login
password opens codes and passwords alike, and changing or deleting a login
moves or removes its code. Set Up takes a pasted key or an
`otpauth://totp/` address; Scan QR Code makes Purser's windows see-through
for half a second, takes the screen with grim into a file in
`$XDG_RUNTIME_DIR` (deleted straight after, as the screen may show other
secrets), and reads QR codes in it with ZBar through pyzbar. Counter-based
(HOTP) setups are refused, as Purser can't keep their count in step.

Screen reader (1.120, `screen_reader.py`): the reader is Orca (LGPL-2.1),
which apps reach over the AT-SPI accessibility bus that at-spi2-core already
runs; it speaks through speech-dispatcher and eSpeak NG. Command+F5 is the
`strata-shell/screen_reader` activator, an option of Strata's own (default
`<super> KEY_F5`) so wayfire.ini files from before 1.120 get it, and runs
`freemac-screen-reader --toggle`. That starts Orca with `--replace`, or
stops it with SIGTERM (Orca 46 has no `--quit`; unknown options start a
second reader), sets `org.gnome.desktop.a11y.applications
screen-reader-enabled` for apps that look before they speak, and keeps
`screen_reader` in shell.json. Topline calls `at_login()` two seconds after
it starts, so the reader comes back at the next login.

Orca 46's keyboard device (libatspi 2.52's legacy device) calls
`XOpenDisplay` and stops or hangs when there is no X11 display, and
freemac's desktop has none. So `freemac-screen-reader --orca` starts a
private `Xwayland -rootless -displayfd` for Orca alone, runs Orca with that
`DISPLAY`, and ends the X server when Orca ends. It shows no windows; Orca's
own settings window is a Wayland window. Keys reach Orca through the apps'
AT-SPI bridge. Screen Reader Settings in Dials stops the running reader
before `orca --setup`, because that window goes on as the reader when it
closes and two readers at once leave the window you came from stuck.

Full-screen size (1.119, `mission-control.hpp`): `move_to_workspace` moves a
window with the size it has now. When a window goes full screen, Strata moves
it to its own desktop on the next idle, and an app that hasn't yet answered
the full-screen configure is moved at its old size, which then sticks. So
for three seconds after `enter_full`, once `vswitch` has finished sliding and
the app has answered, Strata sets the window's geometry to the whole output
at its desktop if it isn't already.

Badges after a Dock restart (1.118, `launcher_badge.py`): apps send a
LauncherEntry badge only when their count changes, so a Dock that starts later
would miss it. When Pier starts it emits `org.freemac.Dock.Started` on
`/org/freemac/Dock`; every app that has sent a badge listens for it (the
subscription is made with its first `set_count`) and sends its non-zero counts
again. Dials reads the same `updates.json` that Beacon writes and watches its
folder, so the red count beside Software Update follows Beacon.

Update notices (1.117, `update_notice.py`): Beacon, which runs for the whole
session, keeps a `Watch`. A minute after login it calls PackageKit's
`get_updates` (plus `refresh_cache` when the last refresh is a day old), and
every 15 minutes it checks whether a day has passed. The count goes to
Harbor's Dock icon as a LauncherEntry badge sent from Beacon, so it outlives
Harbor; Harbor asks Beacon (`org.freemac.Beacon.UpdatesChanged`) for a
recount after it checks or installs. A
notice (`x-freemac-uri` `harbor:updates`, opening `freemac-harbor --updates`)
goes out only when the set of package ids includes some not already told;
the ids are kept in `~/.local/state/freemac/updates.json`. Nothing runs on
the live system (`/run/live/medium`).

Coming forward and asking for attention (1.116, `strata/shell/attention.hpp`):
Strata creates the xdg-activation global, which Wayfire 0.8 leaves to an
optional plugin. A request whose token carries a seat (made from an input
event the app got, as when the Dock or Seek launches with a GTK launch
context) is granted with `focus_request`, which raises the window and goes to
its desktop. Any other request, and Xwayland's urgency hint
(`view_hints_changed_signal`), marks the app as asking instead: Strata writes
`attention APP-ID on` to the Dock's socket (`$XDG_RUNTIME_DIR/freemac-pier.sock`),
and `off` when the app gets the keyboard or its last window closes. The Dock
bounces the icon of an app that is asking (also for a LauncherEntry
`"urgent": true`), and asks `strata/attention` for the list when it starts.

The ISO build copies `build/overlay` with `cp -a --no-preserve=ownership`
and checks that nothing outside /home belongs to an account (uid or gid 1000
and up, apart from nobody) before it makes the squashfs. Before 1.116, CI
images had /, /etc and /usr owned by the runner's uid 1001. Keel's
`own_by_root` gives any such file back to root after it unpacks the image.

Dock badges (1.115, `launcher_badge.py`): apps send
`com.canonical.Unity.LauncherEntry.Update(app_uri, properties)` on the
session bus, the signal Thunderbird, Telegram and others already send, with
"count"/"count-visible" and "progress"/"progress-visible". Pier subscribes to
it from any sender, keeps the latest badge per desktop file, watches each
sender's bus name and drops its badges when it goes, and each Dock item draws
its own count and progress bar after its icon. Post sends the unread count of
every Inbox, Nudge the reminders due today or late; `"badges": false` in
pier.json (Dials) hides them.

Stage Manager (1.107, `stage.py`, hosted by Pier because the Dock is always
running): with `"stage": true` in pier.json it follows Wayfire's focus events.
When a window of another app comes forward, every visible window of the
other apps is hidden through Strata (`strata/hide`, so nothing shrinks into
the Dock), and a picture of each app's front window is drawn a moment later
with `strata/snapshot`, which works on hidden windows. The pictures sit in a
`gtk-layer-shell` strip on the bottom layer down the left edge, under the
windows and reserving no room, so the Dock stays centred and a zoomed window
covers it; only the pictures take clicks. Clicking one un-minimizes the
windows Stage Manager hid for that app and focuses the newest. Windows the
person hid or minimized are never touched. What it hid, the strip's order and
the app on stage are kept in the Dock's runtime folder, so a restart of the
Dock (a new position, say) doesn't lose them; turning it off brings them all
back, least recent first.

Dynamic wallpaper (1.106, `backdrop.py`, `sun.elevation`): with
`[background] dynamic = true` and one of freemac's own scenes, Backdrop loads
both the day and the night picture and works out once a minute how high the
sun is where the computer is (the time zone's city, as for Auto
appearance). `sky_mix` turns that into how much of the night picture to lay
over the day one (eased from 6 degrees above the horizon to 6 below) and
how warm the light is (a gold soft-light wash, strongest as the sun sits on
the horizon). Light and dark mode no longer change the picture while it's on.
`FREEMAC_SUN_HEIGHT` pins the sun's height, for screenshots and tests.

Picture in Picture (1.105, `reel_pip.py`): Reel hides its title bar and
controls, shows two buttons of its own over the middle, resizes to the
video's shape at 384 pixels wide, and asks Wayfire to put the window in the
bottom right of its output's work area (`window-rules/configure-view`) and
keep it above the others (`wm-actions/set-always-on-top`). The window's
place and size are noted first and given back on the way out. With no title
bar, a press on the picture that moves more than a few pixels starts the
compositor's own move (`begin_move_drag`). Strata's window places skip a
window held above the others as it closes, so a picture closed in its
corner doesn't become the size Reel opens at next time.

Pointer colours (1.104, `dials_pointer.py`): Dials runs freemac's own
pointer drawing (`art/cursors/make-cursors.py`, kept in the image at
`/usr/share/freemac`) again with `--fill` and `--outline`, into
`~/.icons/freemac-pointer-RRGGBBRRGGBB` (a theme that inherits `freemac`),
in the background, then sets Wayfire's `[input] cursor_theme`, GTK's
`cursor-theme` and Strata's `pointer_fill` and `pointer_outline`, which
colour the big arrow a shake shows. The theme is named after its colours
because Wayfire and apps load a theme afresh only under a new name; older
ones are removed. Reset goes back to the `freemac` theme.

Keeping the computer awake (1.103, `awake.py`): `freemac-lock --watch`,
which runs the idle timers, also owns `org.freedesktop.ScreenSaver` and
`org.freedesktop.PowerManagement` on the session bus, the usual way Linux
apps (web browsers, video players) ask the screen to stay on. While anyone
holds a request it asks Strata (`strata/keep-awake`), which holds a
`wf::idle_inhibitor_t`: the compositor stops counting the computer as
idle, so swayidle's screen saver and lock and Wayfire's screen-off all
wait, and their timers start fresh afterwards. Requests end when taken
back or when their program leaves the bus, and the watcher drops any left
over when it starts. Reel holds one while a video plays; `caffeinate`
(`-t`, `-w`, or a command to run) holds one for as long as it runs; Dials
> Power lists them (`org.freemac.KeepAwake.List`). Closing the lid still
sleeps and locks.

Drawer's settings (1.102, `drawer_settings.py`) live in
`~/.config/freemac/drawer.json`: the folder new windows open in, the
warning before emptying the Trash (the Dock's Empty Trash follows it
too), removing items from the Trash after 30 days and keeping folders on
top. Topline does the 30 days (`transfer.purge_old_trash`, by each item's
DeletionDate) shortly after login and every six hours.

Sunrise and sunset (1.101) come from `sun.py`: the time zone's city in
the tz database (`zone1970.tab`, with `tzdata.zi` for older names) gives
a latitude and longitude, and the usual sunrise equation gives the times.
Auto appearance (`appearance_auto` in shell.json) is Topline's
(`auto_mode.py`): once a minute it checks whether the sun is up and, only
as the sun rises or sets or as Auto is chosen, runs
`freemac-dials --appearance`, so Dark Mode chosen by hand lasts until the
next change. Night Light's Sunset to Sunrise passes the same place to
wlsunset (`-l`, `-L`), which works out the times itself.

Background sounds (1.100) are Topline's (`background_sounds.py`): a
GStreamer playbin plays one of six loops from
`/usr/share/sounds/freemac/background`, queued again on about-to-finish so
it repeats with no gap, at `(volume/100)**2`, following shell.json
(`background_sounds`, `background_sound`, `background_volume`).
`art/sounds/make-background-sounds.py` makes the loops at build time from
seeded noise (pink, white, brown, filtered and shaped), each crossfaded
end to start and matched in level.

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
  **View Options** (1.56, ⌘J) keeps icon size (32 to 128 pixels), grid
  spacing, text size and Show Item Info in drawer.json for every window.
  Icon size and item info refill the folder (pictures are drawn at the new
  size); spacing and text size (a CSS provider on the icon view) apply at
  once. The item-info line is shared with the desktop (`drawer_info.item_info`).
  **Rename Items** (1.55, `batch_rename.py`) works out every new name first
  and refuses the lot if any is empty, taken or given twice; it then renames
  through hidden temporary names, so names can be swapped, and keeps one
  Undo record for all of them. The desktop runs it as its own process
  (`python3 -m freemac_shell.batch_rename`), because dialogs that the
  layer-shell desktop opens itself get a frame far larger than the window;
  the process prints the names it changed so icons keep their places.
  Every window the desktop opens is now such a process (Rename Items, Get
  Info through `python3 -m freemac_shell.drawer_info`, and View Options),
  with the app id `freemac-desktop-window` (`apps.DESKTOP_WINDOW`): any
  window under the desktop's own app id gets the oversized frame, while this
  id gets a normal one and the menu bar names it Drawer. **Desktop View
  Options** (1.57, `desktop_view.py`) keeps icon size, grid spacing, text
  size and Show Item Info in `desktop-view.json`; the panel writes the file
  as each control rests and the desktop, watching it, works out a new grid
  cell from the icon and text size and redraws, keeping the selection.
  **Spring-loaded folders** (1.50): every drop target in Drawer starts a
  short timer when a drag rests on a folder and opens it when the timer
  ends; the drag hands over the files picked up when it began, not the
  window's selection, which is empty after the folder changes.
  **Gallery view** (1.53) moves the icon view itself into a strip under a
  large picture of the chosen file and lays it out in one row (no names,
  narrower items), so choosing, opening, dragging and Glance work as they
  do in icon view; switching back moves it home. The large picture is the
  file itself for pictures, a PDF's first page, or its icon at 256 pixels.
  **Preview pane** (1.54) sits right of the files in every view but
  gallery (which already shows the file large). It uses the gallery's
  picture widget and picture loader, and lists created and modified dates,
  a folder's item count, a picture's size and the file's tags; with
  nothing chosen it describes the open folder.
  **Status bar** (1.52): the label under the files counts the open
  folder's items (the last column's in column view) and the chosen ones,
  and adds the space left from `os.statvfs`; a message Drawer shows there
  stays for four seconds before the counts come back. **Show Item Info**
  on the desktop (`desktop_icons.item_info`, saved in the layout file) reads
  a picture's size from its header with `GdkPixbuf.Pixbuf.get_file_info`
  and counts a folder's visible items; the grid's rows move apart to fit.
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
  Undo Last Update (1.134) runs `freemac-update-helper --root ROOT rollback`
  on the chosen system (see below).

## Software Update for freemac itself (1.134)

Apps and the rest of the system come from Ubuntu or Debian through apt and
Harbor. freemac's own files (the shell, the apps' launchers, icons, helpers,
themes, wallpapers, sounds, Strata's plugins and freemac's files in `/etc`)
are updated separately, a whole version at a time, the way a Mac installs a
new macOS:

- **The bundle.** `build-iso.sh` runs `scripts/make-update-bundle.py` on the
  finished image, which writes `freemac-update-VERSION-BASE-amd64.tar.xz`:
  `manifest.json` (version, base, each file's SHA-256 and mode, links, and
  what's new from this repository's ROADMAP via `scripts/whats_new.py`) and
  `files/`. The release workflow uploads it and its `.sha256` beside the
  ISO, and `scripts/release-notes.py` puts the same what's-new list in the
  release notes between `<!-- whats-new -->` markers.
- **Finding it.** `freemac_update.py` (user side) and Beacon's daily look
  read GitHub's releases API (`/etc/freemac/update.conf` `feed=` can name
  another) and pick the newest release newer than `/etc/os-release`'s
  `VERSION_ID` that has a bundle for this base. The result is cached in
  `~/.local/state/freemac/freemac-update.json`.
- **Downloading.** Update Now runs `pkexec freemac-update-helper download
  VERSION` (`org.freemac.update`, auth_admin_keep). The helper (root, standard
  library only, importing nothing from the shell so it can also bring an older
  computer up to date) fetches the `.sha256`, downloads the bundle with
  progress lines on stdout, checks the checksum, unpacks it (regular files
  only, no `..`), checks every file against the manifest, and refuses any
  path outside `usr/`, `etc/os-release`, `etc/skel/` and `/etc` paths named
  for freemac (never the live disk's sudoers file). The result waits in
  `/var/lib/freemac/update/pending/`.
- **Installing.** `freemac-update-install.service` runs `freemac-update-helper
  apply` at the next start, before greetd: each file goes in through a
  temporary name and `rename`, what it replaces is copied to `previous/`,
  files the last update put in that the new one doesn't have are removed,
  then the icon caches, GSettings schemas, compiled Python, systemd and GRUB
  are brought up to date as needed. If any step fails, what was changed is
  put back. `result.json` says what happened, for Beacon's notice and Dials;
  `installed.json` lists what this version put in.
- **Undoing.** `rollback` puts `previous/` back and removes what the update
  added; Recovery's Undo Last Update runs it.
- The bundle's integrity rests on HTTPS to GitHub and its checksum; signing
  bundles with a key kept outside the repository is on the roadmap.

## Services (1.140)

Services hand what's selected in one app to another app, as on a Mac.
`services.py` lists them (id, title, whether they take words or files, a
test of whether they fit, and the shortcut freemac ships). The words come
from Wayland's primary selection (`wl-paste --primary`), which every app
keeps up to date as you select, so no app needs to do anything to offer
them. Topline's app menu reads it when Services opens and greys out the
services that don't fit; Drawer's right-click menu offers the ones for files.

`freemac-service ID [TEXT|PATH...]` does the job. Stickies, Jot, Words and
Seek each publish a `service` app action, which it calls over the session
bus through `org.gtk.Actions.Activate`, starting the app first if its name
isn't on the bus. Shortcuts are ordinary Wayfire command bindings
(`binding_service_ID` / `command_service_ID`); Dials > Keyboard edits them,
and which services show is kept in `~/.config/freemac/shell.json`
(`services_off`).

Because `wayfire.ini` and `wf-shell.ini` are copied from `/etc/skel` only
when an account is made, `freemac-config-upgrade` runs at each login and adds
every setting the shipped file has that the person's lacks, at the end of its
section. Anything already there, even turned off, is left alone.

## Disk encryption (1.141)

With "Encrypt the disk" on, Keel's backend lays the disk out as BIOS boot,
EFI, a 1 GB ext4 `/boot` and a LUKS2 volume (GPT type 8309) for the rest.
`cryptsetup luksFormat` uses argon2id at 256 MB, so a PC with little memory
can still unlock it, and the account's password goes in key slot 0. A
recovery key (24 letters and digits from an alphabet without 0/O or 1/I, in
groups of four: 120 random bits) goes in slot 1, and the backend prints it
once as `RECOVERYKEY …` for Keel to show; it isn't stored anywhere. Keys
reach cryptsetup through files only root can read in `/run`, removed at
once, never on a command line. The volume opens as
`/dev/mapper/freemac_root`, which is formatted ext4 and becomes `/`.

The installed system gets `/etc/crypttab`
(`freemac_root UUID=… none luks,discard,initramfs`). The `initramfs` option
makes cryptsetup-initramfs's hook put the volume and cryptsetup in the
initramfs that `update-initramfs` builds in the chroot (where it can't see
`/` as the booted system will), and in every rebuild after a kernel update,
so the package's own conf-hook is left as shipped. cryptsetup asks through Plymouth, whose freemac theme draws the
password field. GRUB reads the kernel from the plain `/boot`, so it needs no
crypto of its own.

`/usr/libexec/freemac-disk-helper`, run by Dials through pkexec
(`org.freemac.disk-encryption`, an administrator's password), finds the
volume behind `/` with findmnt and lsblk (`status` needs no root).
`password` changes slot 0 and only when the current password opens slot 0;
`recovery` adds a new key in a free slot, then removes every older slot but
the password's, so an old written-down key stops working. `freemac-users-helper password`, given
the old password as a second line when you change your own, calls it too, so
the disk follows the login password when they were the same.

## Summary Info (1.183)

`drawer_summary.SummaryWindow` is a small window of its own beside
`drawer_info.InfoWindow`, using its `folder_total` and `nice_size`. The
total is added up in a thread that the window's `stop` event ends. The
tag picker already takes several paths. Locked is a check button that is
inconsistent when only some items are locked, and sets every item that
`locks.can_lock` allows and that isn't an alias. ⌃⌘I reaches Drawer as Ctrl
with Super, so the key handler looks for both before ⌘I.

## Back and Forward lists (1.182)

Drawer's Back and Forward buttons start a 450 ms timer on a left press and
show the list on a right press. The list is a `Gtk.Popover` under the
button, not a `Gtk.Menu`: a menu popped from a header bar button is placed
above the window on Wayland. Choosing an entry moves that many folders
between `history` and `future` and refreshes once. A held press that showed
the list sets `_history_popped`, so the click that may follow is ignored;
the next press clears it, as the popover's grab can keep that click away.

## Recent Folders (1.181)

`recent_folders.py` keeps the last ten real folders Drawer has shown in
`~/.local/share/freemac/recent-folders`, one a line, written whole and
renamed into place. `DrawerWindow.refresh()` notes each folder it shows.
The app's Go menu holds one `Gio.Menu` (`RECENT_MENU`) that the app fills
again when the list changes or one of its windows comes to the front (each
Drawer is its own process, so another may have added folders). Items use
the window action `go-recent` with the folder as a string target; Topline
builds its menus from the exported model, so changes show at once.

## Inspector (1.180)

`drawer_info.InfoWindow` builds its contents in `_build(path)`, so the
Inspector (`inspector=True`) can swap them with `show_path()` when Drawer's
selection changes; the old item's comment is kept and its size thread is
stopped first. Wayfire has no floating-panel role, so once mapped the
Inspector finds its own view through the IPC socket, moves it to the top
right of the work area and sets it always on top (as Picture in Picture
does). GTK on Wayland only knows the whole screen, so its contents scroll
past the screen's height less room for the menu bar and the Dock.

## Sharing and permissions (1.179)

permissions.py maps a Mac's three privileges onto each permission class:
Read & Write is rw, Read only r, No Access nothing, and a lone w is shown as
Write only (Drop Box). A folder's x bit follows its r bit so Read only still
opens it; a file keeps its own x bit. A locked item's privileges are read
from the mode saved in `user.freemac.locked`, and only the owner of an
unlocked item gets the pop-ups. `apply_to_enclosed()` walks bottom-up so a
folder that loses its owner's access is changed after its contents, skips
symbolic links, locked items and items owned by others, and reports what it
skipped.

## Change picture (1.177)

wallpaper_rotate.py keeps its settings in the `[background]` section of
`wf-shell.ini` beside the image key: `rotate` (never, seconds, or login),
`rotate_from` (a folder, empty for freemac's own), `rotate_random` and
`rotate_last`. Backdrop runs for the whole session, so it calls `tick()` every
minute and `login()` once per session (a marker file in `$XDG_RUNTIME_DIR`
keeps a Backdrop restart from counting as a login). A change is written as
the `image` key, which wf-background and everything else already follow;
Dials watches the file to move its selected tile. freemac's scenes count
once each, in the day or night version for the current mode. A missing or
future `rotate_last` restarts the count instead of changing at once.

## Locked items (1.176)

Linux has no user-settable lock flag a program can't simply ignore, so
locks.py uses the file's permission: `lock()` writes the current mode into the
`user.freemac.locked` extended attribute first (writing a user attribute needs
write permission) and then clears every write bit; `unlock()` restores the
saved mode, then removes the attribute. The attribute is the mark Drawer,
the Desktop and Get Info read; changing it touches ctime, so the folder
monitors redraw the icon with `locks.badge()`. Only the owner can lock, and
symbolic links (aliases) can't carry the attribute. `ask_trash()` asks
before trashing and unlocks on Continue (moving a folder to another parent
needs write permission on the folder itself); `tell_cant_rename()` is the
refusal both rename paths share.

## List view options (1.175)

View Options builds its rows from `view_mode`; `_view_toggled` destroys and
rebuilds an open panel, so it always speaks for the view in front. The list
columns are kept in `list_columns` and hidden with `set_visible`; the hidden
ones, `relative_dates` and `calculate_sizes` are saved with the other Drawer
settings. `when()` formats Today/Yesterday or the full date from the module
flag `RELATIVE_DATES`, and `date_width()` widens the Modified column to fit.
With `FOLDER_SIZES` on, `refresh` calls `Folder.add_up_folders()`, a thread
that runs `drawer_info.folder_total` on each folder row and fills C_SIZE and
C_BYTES on the main loop; `Folder.cancel()` stops it when the folder changes.
`sort_key` then sorts folders by their total, biggest first, like files.

## Custom icons and comments (1.174)

A custom icon is a PNG, at most 512 pixels a side, kept once in
`~/.local/share/freemac/icons/` under a digest of its pixels; the item names
it in its `user.freemac.icon` extended attribute (custom_icons.py), which
moves with it on the same disk. `get()` accepts only a plain file name in
that folder, so a crafted attribute can't point elsewhere. Clearing removes
only the attribute, since another item may share the picture. Drawer's
`_add` and the Desktop's `picture_for` ask `custom_icons.pixbuf()` first
(for an alias, its original's) and skip the thumbnail; setting the attribute
changes the item's ctime, which the folder monitors already report, so both
redraw at once. In Get Info the icon is a focusable EventBox: ⌘C, ⌘X, ⌘V
and Delete act on it while it is chosen, and it takes dropped pictures and
picture files. Symbolic links can't carry user attributes, so an alias
has no icon of its own.

Comments live in `user.xdg.comment` (comments.py), the name freedesktop.org
gives them, so other file managers read them too. seek_index indexes any
file with a comment, whatever its kind, with the comment before its text,
and keys files on the later of mtime and ctime so a new comment is read.
A disk that can't keep extended attributes (FAT, some network shares) says
so when an icon is pasted.

## Aliases (1.172)

An alias is a symbolic link to the original's absolute path (aliases.py), so
it keeps working when the alias itself moves, and the rest of the system (a
file dialog, Terminal, an app opening it) follows it like any link. `make()`
names it as a Mac does ("Notes alias", "Notes alias 2"), and an alias of an
alias points at the same original. `badge()` draws the arrow onto the
original's icon with cairo, so no artwork is borrowed; Drawer caches the
badged icons. A broken alias (its link leads nowhere) gets a plain document
icon and, when opened, `ask_broken()`: Delete Alias moves it to the Trash and
Fix Alias… repoints it through a temporary link and `os.replace`, so it is
never missing. Show Original on the Desktop runs `freemac-drawer --select
PATH`, which opens PATH's folder with PATH chosen even when PATH is a folder.
Make Alias has no ⌃⌘A shortcut: Strata turns ⌘ into Ctrl for apps, so ⌃⌘A
reaches them as Ctrl+A, the same as Select All.

## Definitions in Seek (1.171)

`words.meanings(text)` answers Seek without starting Words: it bisects
WordNet's sorted `index.<pos>` files (open once and kept open) for the word,
trying the `.exc` exception lists and the usual endings first so plurals and
tenses find their lemma, then reads each sense's gloss from `data.<pos>` at
its byte offset and drops the examples. Results are cached (lru_cache), so a
lookup takes a few milliseconds and runs on each keystroke. Seek asks only
for queries that look like one to three words, adds one Definition result
after the Guide topics, and opens `freemac-service words <lemma>` on Return.
"definitions" is a category in seek_settings.py, so Dials > Seek can hide it.

## Accessibility Shortcuts (1.169)

`freemac-accessibility-shortcuts` (a11y_shortcuts.py) is a command binding
on ⌥⌘F5 in wayfire.ini. It lists the accessibility features this computer
has (the screen reader only where Orca is installed, Hover Text only where
Tesseract is), each as a pair of functions that read and change the very
setting Dials does: a `strata-shell` switch, a Wayfire plugin in `core/plugins`
(Zoom, and Invert with its key written first), a shell.json key, or the GTK
theme. So the panel, Dials and the features' own keys never disagree, and the
panel re-reads them every second while it's open. Colour Filters turns on the
filter last chosen (shell.json `colour_filter_last`, kept by Dials and by the
panel when it turns the filter off). shell.json `accessibility_shortcuts` is
the list Dials ticks; with exactly one, the command flips it and exits without
a window.

## Add to Dock for websites (1.165)

Web (Epiphany) makes web apps itself: a profile folder
`~/.local/share/org.gnome.Epiphany.WebApp_<id>` with a `.app` marker, and a
launcher running `epiphany --application-mode --profile=…`, which gives the
site its own window and cookies. Epiphany finds its launcher through the
desktop portal's DynamicLauncher, so the image now ships
`xdg-desktop-portal` and `xdg-desktop-portal-gtk`, with
`freemac-portals.conf` choosing the GTK backend, and `wayfire.ini` runs
`dbus-update-activation-environment` at login so the portal can reach the
Wayland display.

`webapps.py` (`freemac-webapp`) writes that layout without Epiphany's own
dialog. The id is a SHA-1 of the address. The launcher is written under the
portal's `applications` folder and linked into `~/.local/share/applications`,
with the address in `X-Freemac-WebApp-URL`, and `Exec` quoted so that a `%`,
`$` or quote in an address can't reach the shell. The menu item
`topline.add-to-dock` (Web's File menu) runs it with the window's title; the
address comes from Epiphany's `session_state.xml`, matching that title. A
background thread reads the page for a manifest, touch icons and icons
(`icon_choices` ranks them) and draws a 256-pixel tile: a large opaque icon
fills it, a small or transparent one sits on white, and a site with none gets
its first letter on a colour from its host. Add pins the launcher in
`pier.json`. Topline gives app ids starting `org.gnome.Epiphany.WebApp_`
the shorter `WEB_APP` menus. Because GLib's list of apps can lag a new
launcher, `apps.app_info` and the Dock read it from its file. Delete Web
App… asks first, stops the app's own Epiphany (matched by its `--profile`
argument, waiting for it to exit so it can't rewrite the folder), then
removes the link, launcher, profile and pin.

Epiphany has no Badging API, so a web app can't send a LauncherEntry badge
(1.166). Instead `Item.set_views` in the Dock passes the windows of a web
app's launcher to `webapps.views_count`, which reads a leading "(3)" or an
"Inbox (12)" from each title and keeps the largest; `_draw_badge` uses it
when no LauncherEntry count was sent. The Dock reads views on each Wayfire
event and every five seconds, so the badge follows the title.

A web app's File > Open in Web (`topline.open-in-web`, 1.168) runs
`freemac-webapp --open-in-web ID --title T`. Epiphany keeps no session file
for a web app, so `page_in_app` reads the profile's own `ephy-history.db`
read-only and takes the latest visit whose page title is the window's
(with or without a leading count), else the latest visit, else the
launcher's `X-Freemac-WebApp-URL`. Only an http or https address is passed,
as one argument, to `epiphany`, which opens it in a tab of Web's own profile.

## Lifeboat in the menu bar (1.163)

`lifeboat_menu.LifeboatMenu` watches `lifeboat-status.json` and
`lifeboat.json` with `Gio.FileMonitor`s and the volume monitor's mount
signals, folding bursts into one look a quarter of a second later, plus a
minute timer so "Just now" ages. `describe()` (no GTK) turns the settings,
the status, whether the chosen drive is plugged in (`lifeboat.chosen_drive`,
not the watcher's own `plugged`, which can be stale after a drive is first
chosen) and the drive's backups into the menu's lines. Its buttons run
`freemac-lifeboat --now` and `--stop`, which reach the running watcher
through `GApplication`. While a backup runs the button has the class
`lifeboat-busy`, whose CSS animation turns the icon with
`-gtk-icon-transform`. Holder name `lifeboat` in `menubar_hide`.

## Now Playing and Seek in the menu bar (1.162)

`now_playing_menu.NowPlayingMenu` subscribes once to `PropertiesChanged` on
the MPRIS object path and to `NameOwnerChanged` for `org.mpris.MediaPlayer2.*`
names, and folds bursts of them (a new track changes title, cover and length
together) into one `media.current()` a quarter of a second later; nothing
polls while the menu is closed. `media.describe()` now gives the album, the
length and the position in microseconds. While the menu is open a one-second
timer reads `Position` from the player playing and redraws the whole popup,
since a partial redraw of a see-through layer surface can leave the desktop
showing through on some compositors. `Seek` is a plain `StatusButton` that
launches `freemac-seek`. Both have holder names (`nowplaying`, `seek`) in
`menubar_hide`, so Dials can hide them as it does Wi-Fi and the rest.

## Focus menu and menu bar choices (1.161)

`focus_menu.FocusMenu` is a `StatusButton` that Topline updates from its
clock tick and from shell.json changes (`notify_rules.active_focus`, since a
schedule turns a Focus on with nothing else saying so); its `Popup` lists
`notify_rules.FOCUSES` and writes `notify_rules.focus_writes` through
`beacon.write_prefs`, as Quick Settings does. Wi-Fi, Bluetooth, Sound,
Battery and Focus each sit in a holder box in the bar; shell.json's
`menubar_hide` (a list of those names, written by Dials) hides the holder,
so an icon's own showing and hiding (no battery, no adapter) is untouched.
Quick Settings checks `is_visible()`, which counts the holder, before opening
a menu from its symbol.

## Quick Settings modules (1.160)

`quick.py`'s `Tile` is a box of two buttons: a round `GtkToggleButton` holding
the symbol (the module's state, styled `quick-tile-symbol`, blue when checked)
and a flat button for the words. `show_state` sets the toggle with its handler
blocked, so reading the state back never switches anything. A tile given a
`more` callback shows a chevron and calls it from its words; Topline hands
Quick Settings its `WifiMenu` and `BluetoothMenu` (`menus`), and the words
open that menu from its own symbol, or Dials' panel when the symbol is hidden.

## Ferry's toolbars and controls (1.164)

`ferry/appkit/NSPopUpButton.m`, `NSSegmentedControl.m`, `NSSearchField.m`,
`NSStackView.m` and `NSToolbar.m`. Wayland gives a program no say over where
its own windows go, so a pop-up button's menu is drawn inside the window,
above its views: `NSWindow` routes events to the open menu first, and opening
returns at once instead of running a modal loop. A toolbar is a strip of
views under the title bar; the window's frame grows by its height with its
top edge kept, and its items are validated from `-[NSWindow update]` on each
pass of the event loop. Stack views are laid out by hand (Ferry has no Auto
Layout) from each view's fitting size and its hugging, compression and
visibility priorities.

## Ferry's tables and outlines (1.159)

`ferry/appkit/NSTableView.m` and `NSOutlineView.m`, with private declarations
shared in `appkit/AInternal.h`. A cell-based table draws each visible row
through its columns' data cells; a view-based table asks its delegate for a
view per visible row and column, keeps them in `NSTableRowView`s, and puts
views that scroll out of sight in a reuse queue keyed by identifier
(`makeViewWithIdentifier:owner:` also instantiates prototype views stored as
nibs inside the table's nib, which `NSNib` can now decode). `NSScrollView`
tiles a table's header view above its clip view and keeps it in step with
horizontal scrolling. The outline view is a table whose rows map to items
through a flattened, lazily expanded tree; its first column is indented by
level and draws the chevron.

## Bluetooth menu (1.158)

`bluetooth_menu.BluetoothMenu` subclasses `status.Bluetooth`, which still
draws the symbol from BlueZ's objects on the system bus (an
`ObjectManagerClient` on `org.bluez`, whose cached properties follow
`PropertiesChanged`). Its menu is a `menubar_popup.Popup`, refilled whenever
BlueZ changes something while it is open. The switch sets the first
adapter's `Adapter1.Powered`; the devices are that adapter's objects with
`Device1.Paired`, connected first, each with `Battery1.Percentage` when
BlueZ has it. A click calls `Device1.Connect` or `Disconnect` asynchronously
with a 30-second timeout and shows a spinner on that row meanwhile; on an
error BlueZ's reason (such as `br-connection-page-timeout`) is replaced by
words a person can act on in a Beacon notification. Pairing stays in Dials,
which runs discovery and the agent for PIN and passkey prompts.

## Ferry's menu bar items (1.157)

`ferry/appkit/NSStatusBar.m`. Each `NSStatusItem` registers two objects on the
program's own session-bus connection (GIO's D-Bus calls, served to Mac code
through `src/host.c` like GTK's): `org.kde.StatusNotifierItem` at
`/StatusNotifierItem/N` and `com.canonical.dbusmenu` at `/MenuBar/N`, and
registers the item path with `org.kde.StatusNotifierWatcher` (Topline, see
below), again whenever the watcher's owner changes. GLib's default main
context is attached to Ferry's run loop (`AGlibAttach`) so the calls arrive on
the app's main thread with or without a window. `IconPixmap` is drawn with
Ferry's Core Graphics at 16, 22 and 32 pixels high, as the item would be drawn
in a Mac's 22-point bar, and converted from premultiplied RGBA to straight
ARGB. The menu is numbered when the menu bar reads it from the top;
`AboutToShow` tells the menu's delegate, and each item's enabled state comes
from the app's own `validateMenuItem:`. Setters coalesce `NewIcon`,
`NewToolTip` and `NewStatus` until the run loop's next turn. A removed item
first says it is `Passive`. Topline shows a wide picture (a title) 22 pixels
high and an icon 16.

## Menu bar extras (1.156)

`shell/freemac_shell/extras.py`. Topline owns `org.kde.StatusNotifierWatcher`
on the session bus (replaceable, so a restarted Topline takes it back; apps
register again when the watcher's owner changes). Items register with a bus
name, or with an object path on their own connection; a `NameOwnerChanged`
subscription per name drops an item when its app goes. If another program
already owns the watcher, Topline registers as a host with it and follows its
signals. Each item is a `Gtk.Button` packed at the end of a box left of the
status icons; it reads `org.kde.StatusNotifierItem` with `GetAll` and again
after any of the item's signals (batched for 80 ms). Its menu is read with
`com.canonical.dbusmenu` `AboutToShow` and `GetLayout` each time it opens and
built as a `Gtk.Menu`; a chosen item sends `Event(id, "clicked")`.

## Ferry in releases (1.155)

Ferry stays off the ISO, but the release workflow now builds its package
(`ferry/packaging/build-deb.sh`, with clang, lld and llvm for its Mac-side
libraries) and attaches `freemac-ferry_VERSION_amd64.deb` to the release. The
step may fail without stopping the release; `scripts/release-notes.py` names
the package in the notes only when it was built. Ferry 0.10.0 adds
`NSTabView`/`NSTabViewItem` and `NSSplitView` to its AppKit
(`ferry/appkit/NSTabView.m`, `NSSplitView.m`), tested by `appkit_panes`.

## Battery menu (1.154)

`battery_menu.BatteryMenu` subclasses `status.Battery`, which still draws the
symbol, warns at 10% and 5% and applies Low Power Mode; `update()` now keeps
the figures it read in `facts` for the menu. The menu is a
`menubar_popup.Popup`, a layer-shell overlay drawn like the Sound and Wi-Fi
menus, which closes on Escape, a little after the pointer leaves, or a few
seconds after opening if it is never pointed at. "Using Significant Energy"
comes from `energy.Sampler`: every 30 seconds it reads `/proc` for this
person's processes and adds up their processor ticks per app. Wayfire's
`window-rules/list-views` gives no pid, so an app's processes are found by
name (the window's app id, its last dotted part, or the program its
.desktop file runs; a script is known by its script's name) and then every
process they started, stopping at one that belongs to another app. An app
that used 15% of a core or more since the last sample is listed. The Low
Power Mode switch writes `always` or `never` to `shell.json` through
`style.save_prefs()`, which merges and writes the file atomically.

## Wi-Fi menu (1.153)

`wifi_menu.WifiMenu` replaces the old network status icon in Topline. It
keeps one `NM.Client` and follows its signals and those of the first managed
Wi-Fi device (an unmanaged one belongs to something else, such as a hotspot),
debounced by 250 ms. The menu is a layer-shell overlay like the Sound menu.
NetworkManager reports every scan result and change of strength while it is
open, so `fill()` compares a plan of what the rows show and rebuilds only when
it changes; a row rebuilt under the pointer would lose the click. Joining
uses `activate_connection_async` for a saved network, or builds an
`NM.SimpleConnection` (`wpa-psk`, `sae` or WEP) for `add_and_activate`;
`_watch()` follows the new active connection and, if it is deactivated
before it is activated, deletes it (so a wrong password is never kept) and
sends a Beacon notification. Turning Wi-Fi off is never reported as a failed
join. Clicking the joined network shows `_add_details()`; the Option key
works too when Topline can see it, but a layer surface without keyboard
focus is not told about modifiers. The image now installs `wpasupplicant`,
which NetworkManager needs for any Wi-Fi network but only recommends.

## New Image in Hull (1.152)

`disk_images.make_blank()` makes a sparse file of the size asked for with
`truncate`, then formats it directly (`mkfs.exfat`, `mkfs.fat`, or
`mkfs.ext4 -E root_owner=` so the user owns its top folder); no loop device
or privilege is needed, and a failure removes the file. Hull then opens it
with Hatch, so it mounts like any image. `disk_images.copy_drive()` unmounts
the drive's mounted volumes through udisks2, calls `Block.OpenForBackup` for
a read-only file descriptor (polkit `open-device`, allowed for an
administrator at the computer, as for Restore), and copies 4 MiB at a time
into a new file opened with `O_EXCL`; chunks that are all zeros become holes
with `lseek`, so mostly empty drives make small files. Stopping or failing
removes the file, and the volumes are mounted again either way. The copy runs
on a thread and reports progress to the same window Restore uses, which is
shown a moment after the file chooser closes so the compositor doesn't leave
it hidden.

## Partition in Hull (1.151)

`partition_plan.Layout` is the arithmetic, with no GTK: a list of parts
(name, format, size) whose sizes always add up to the drive less 2 MiB (the
partition map at the start and its backup copy at the end), each a whole
number of MiB and at least 32 MiB. Adding splits a part in half, removing
gives its space to the part before it, and resizing (or `move_line`, for a
dragged dot) moves space between neighbours. `hull_partition.Sheet` draws it
as a pie with cairo and edits the chosen part. `Actions.partition_drive()`
unmounts everything on the drive, formats the whole disk as `gpt`, then calls
`PartitionTable.CreatePartitionAndFormat` once per part at the offsets
`Layout.offsets()` gives (the last with size 0, the rest of the disk), with
the part's name as both partition name and label, and mounts each new
volume. polkit `modify-device` is already allowed for an administrator at the
computer. A drive with more than one volume draws its bar in the same
colours (`Bar.show_parts`).

## First Aid in Hull (1.150)

`hull_store.first_aid()` runs on a thread for each volume: it asks udisks2's
`Manager.CanCheck` whether the format has a checker installed, unmounts the
volume if it was mounted, calls `Filesystem.Check`, and only if that reports
errors (and `Manager.CanRepair` allows) calls `Filesystem.Repair`, then mounts
it again. udisks runs the format's own checker (e2fsck, fsck.vfat, fsck.exfat
and so on); both calls use polkit `modify-device`, already allowed for an
administrator at the computer on drives that aren't the system's.
`first_aid_words()` turns the results into one report.

## Restore in Hull (1.149)

`disk_images.restore()` runs on a thread: it unmounts every mounted file
system whose `Block.Drive` is the chosen drive, then asks udisks2 for
`Block.OpenForRestore` on the drive's whole block device, which hands back a
writable file descriptor (polkit `open-device`, allowed without a password for
a local, active administrator by `50-freemac-drives.rules`; the system's own
disks use `open-device-system`, which still asks). It copies the image in
4 MiB chunks, reports progress to Hull's `Restoring` window through
`GLib.idle_add` at most five times a second, checks a stop flag between
chunks, and `fsync`s before closing; closing the descriptor makes udisks read
the drive again, so its new volumes appear in Hull and on the Desktop.
`Window._restorable()` allows only external drives that aren't the system's,
optical or an open disk image.

## The Applications folder (1.148)

`~/Applications` is a real, empty folder so the sidebar has somewhere to go;
when Drawer lists it, `Folder._add_apps()` adds a row for each app from
`app_list.installed_apps()`: `Gio.AppInfo.get_all()` filtered by
`should_show()`, without Ferry's `ferry-` entries (the `.app` folders
themselves show instead) and de-duplicated by id. Each row's path is the app's `.desktop` file,
so `app_list.is_installed_app()` (a `.desktop` file under an `applications`
data directory) lets `open_file` launch it with `Gio.DesktopAppInfo`, the
gallery and Get Info show its icon, and Move to Trash refuses it with an alert
pointing to Harbor. Get Info's Version and Size come from
`app_list.package_of()` on a thread: freemac's own apps (`freemac-*.desktop`)
report the freemac version from the manifest; others ask `dpkg-query -S` for
the owning package and `-W` for its version and installed size.

## Hatch and disk images (1.147)

`freemac-hatch` is the default app for `application/x-cd-image`,
`application/x-iso9660-image` and `application/x-raw-disk-image`
(`/etc/xdg/mimeapps.list`); its `.desktop` file is `NoDisplay`, and Pier keeps
such apps out of the Dock's recents. `disk_images.attach()` passes an open file
descriptor to udisks2's `Manager.LoopSetup` (read-only for an `.iso` or a file
the user can't write), which polkit allows the active session's user without a
password; an image already set up by this user is reused. `mount()` waits for
udisks to see its file systems (the whole image or its partitions), mounts any
the Desktop hasn't, then sets `Loop.SetAutoclear` so the loop device goes away
when its disk is unmounted or ejected. Hatch opens each mount point with its
default app, which is Drawer; `Drawer.do_open` then focuses the new window
through Wayfire IPC (`window-rules/focus-view`), as an activation token from
another app isn't available. Hull's `hull_store` shows loops set up by this
user as an `ImageDrive` under Disk Images; ejecting one unmounts its volumes
and deletes the loop if autoclear hasn't already. New Image from Folder sizes
the image from the folder (plus a fifth and 16 MB) and runs
`mkfs.ext4 -d FOLDER -E root_owner=UID:GID` on a sparse file, so nothing needs
root.

## Slipway (1.146)

`freemac-slipway` is the default app for `application/vnd.debian.binary-package`
(`/etc/xdg/mimeapps.list`). `slipway_store.read()` runs `dpkg-deb --field`
for the control fields and streams `dpkg-deb --fsys-tarfile` through
`tarfile` once, keeping the `.desktop` files under `usr/share/applications`
and the image files that could be icons, so the app's own name and icon show
before anything is installed; nothing from the package is run. The download
site is the `user.xdg.origin.url` attribute browsers put on the file.
Installing is PackageKit's `install_files` on a worker thread (polkit's
`package-install-untrusted`, an administrator's password), with
`ALLOW_REINSTALL` or `ALLOW_DOWNGRADE` when that or a newer version is
installed. Afterwards the app opens through its `Gio.DesktopAppInfo`, and
the package can go to the Trash with `Gio.File.trash`.

## Startup Disk (1.145)

Dials > Startup Disk (`dials_startup.py`) lists the firmware's UEFI boot
entries, read with `efibootmgr` by `startup_disk.py` (reading needs no
password). Each active entry gets a kind from its name and device path:
freemac (Keel installs GRUB as `freemac`), Windows, Linux, USB, disc or disk;
network boot (`MAC(`, `IPv4(`, `Uri(`) and the firmware's own tools
(`FvFile(`, UiApp, the shell) are left out, and the entry running now is kept
whatever it is. The first shown entry in `BootOrder` is the one it starts up
from. Changes go through `pkexec /usr/libexec/freemac-startup-disk`:
`always NUM` moves NUM to the front of `BootOrder` and clears `BootNext`;
`once NUM` sets `BootNext` and restarts; `cancel-once` clears `BootNext`.
The helper takes only an entry the page itself would show. Without
`/sys/firmware/efi` the page explains that a BIOS PC chooses in its firmware.

## Power schedule (1.144)

Dials > Battery (or Power) > Schedule… (`dials_schedule.py`) writes the
schedule through `pkexec /usr/libexec/freemac-power-schedule set`, which
keeps it in `/etc/freemac/power-schedule.json` (`power_schedule.py` reads and
checks it). A sleep, restart or shut down is the systemd timer
`freemac-power-action.timer`, which the helper writes from the schedule; its
service runs `freemac-power-schedule run`. Starting up is the real-time
clock's wake alarm, set with `rtcwake -m no` for the next start-up time;
`freemac-power-wake.service` sets it again at every boot and the
`system-sleep` hook after every wake, since an alarm goes off once.

When the timer fires and someone is logged in to the desktop (loginctl),
`run` writes `/run/freemac-power-schedule/pending` with what it will do and
when, ten minutes on, and waits. Topline's `power_countdown.Watcher` looks
for that file every three seconds and shows the countdown; Cancel or the
button to do it now leaves a file in the world-writable `answers` folder,
which `run` reads each second. With nobody logged in it acts at once.

## Tender (1.143)

Tender (`tender.py`, with the copying in `tender_store.py`) looks on every
mounted drive for `freemac-backups/<computer>-<user>/<date>` (the newest
backup of each), `Users/<name>` with a Documents, Desktop or Pictures folder
(Windows; Public and Default are skipped) and `home/<name>` (another Linux
computer). A source becomes a list of kinds, each a list of (from, to)
folder pairs; Windows' `OneDrive/Documents` and the like join the same kinds.
Symbolic links on a Windows disk, AppData, `desktop.ini` and `NTUSER.DAT`
stay behind.

`bring()` walks each pair and copies file by file with `shutil.copy2`. A file
whose destination exists and is the same (same size, and the same time or
the same bytes) is skipped, and so is one that matches an earlier "name 2"
beside it, so running Tender twice brings nothing twice. A different file
with the same name comes over as "name 2". Settings are the exception: the
dotfiles of a Lifeboat backup or Linux home replace this account's, which
are first moved to `~/.local/share/freemac-tender/replaced-<date>/`. Caches,
Trash, keyrings, `.Xauthority`, Lifeboat's drive choice and the like are
never brought, since they belong to the other computer.

## VPN (1.142)

VPN configurations are ordinary NetworkManager connections of type
`wireguard` (built into NetworkManager and the kernel) or `vpn` with the
OpenVPN plugin (`network-manager-openvpn`). `vpn.py` lists them, reads each
one's state from its active connection, and turns them on and off through
libnm. Add VPN Configuration… runs `nmcli connection import` on the file the
person chose, then sets `connection.autoconnect no` and takes it down, so a
new VPN waits to be turned on, as a Mac's does. NetworkManager keeps the keys;
freemac never reads them.

Topline's VPN menu (`status.VPN`) shows while there is at least one VPN and
the `vpn_menu` pref is on. It refills its menu when connections change, and
looks at their state every three seconds, since an active connection's state
has no client-wide signal; the menu is never filled as it opens, because a
menu that opens late is refused by the compositor.

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
