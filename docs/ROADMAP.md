# freemac roadmap

Work happens in batches. Each batch is built as an ISO, checked in QEMU
(live session, and an install where the batch touches installing or booting),
then merged into `Main`. When a batch is finished, the next one is written
here. Every item follows the [clean-room rules](../README.md#clean-room-rules).

Status marks: **done**, **in progress**, **planned**.

## 0.5 "everyday desktop" (done)

Things a person reaches for in the first hour that 0.4 did not have.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Notifications: a notification service for apps, banners in the top-right corner, a history list and Do Not Disturb, opened from the clock in Topline | **Beacon** | done |
| 2 | Screenshots: whole screen (Print), an area (Shift+Print) and the focused window (Alt+Print), saved to Pictures/Screenshots with a notification | **Lens** | done |
| 3 | Text editor with syntax colours, line numbers, find and replace, and dark mode, in place of Mousepad | **Quill** | done |
| 4 | Image viewer with zoom, fit, rotate and next/previous, in place of Ristretto | **Frame** | done |
| 5 | Dials: Sound panel (output and input device, volumes) | Dials | done |
| 6 | Dials: Power panel (battery, when the screen turns off, power mode, sleep, restart and shut down) | Dials | done |
| 7 | Dials: Accessibility panel (larger text, reduced motion, high contrast, bigger pointer) | Dials | done |
| 8 | Dials: Notifications panel (Do Not Disturb, banner time) | Dials | done |
| 9 | First version of our own Mac program layer: Mach-O loader, libSystem conversions, SDK and tests (optional package, not on the ISO) | **Ferry** | done |

## 0.6 "apps and safety" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | App centre for open-source apps from the archive: categories, search, picks, app pages with Install, Open and Remove, an Installed list. Installs and removals go through PackageKit and ask for the password | **Harbor** | done |
| 2 | System updates: a daily check in the background with a notification, and an Updates page in Harbor | Harbor | done |
| 3 | Lock screen with the wallpaper and a large clock: Super+L, Lock Screen in the system menu, locking after an idle time and before sleep, set in Dials > Power | **Latch** | done |
| 4 | Calculator with a running tape, a scientific mode and keyboard entry | **Tally** | done |
| 5 | Clock with world clocks, alarms, timers and a stopwatch; alarms ring and notify even with the window closed | **Chime** | done |
| 6 | Debian (`BASE=debian`, trixie) build tested end to end, as the default | build | moved to 0.8 |
| 7 | App menus from GTK and Qt apps in Topline | Topline | moved to 0.8 |

App menus moved because Wayfire doesn't pass on the menu addresses that apps
publish on Wayland, so Topline can't find them yet. 0.8 adds that to
Strata. The Debian build moved because the machine that builds and tests
freemac can't reach Debian's mirrors at the moment; 0.6 was built and checked
on the Ubuntu 24.04 base (`BASE=ubuntu`). The new packages in 0.6 (gtklock,
swayidle, PackageKit, AppStream, mate-polkit) should all be in Debian trixie under the same names,
but that build hasn't been run yet.

## 0.7 "own look and people" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | More original wallpapers, each in a day and a night version that follows light and dark mode | art, Dials | done |
| 2 | Original icons for every freemac app | art/icons | done |
| 3 | A freemac icon theme with our own folder and file-type icons (Adwaita for the rest) | art/icon-theme | done |
| 4 | Users panel: add and delete users, change passwords, administrators, automatic login | Dials | done |
| 5 | Bluetooth panel: on/off, pairing (with codes), connect, forget, battery level | Dials | done |
| 6 | Printers panel: list, default, test page, remove; Add Printer through system-config-printer | Dials | done |

Also in 0.7: the session now creates the standard folders (Desktop, Documents,
Downloads and so on) at login, so they get their own icons, and the last
administrator can no longer be deleted.

## 0.8 "Strata plugins" (done)

These need C++ plugins built against Wayfire's headers, so the ISO build now
has a compile step (`strata/build.sh`, run in the image and removed again).

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Strata decoration plugin: our own title bar and left-side buttons on apps that leave the title bar to the desktop (terminals, Qt apps, browsers), following light and dark mode as it changes | **Strata** (strata-decor) | done |
| 2 | App menus in Topline: a Strata plugin that hands Topline the menus a GTK app publishes; Topline shows them (File, Edit, View, ...) and runs them, and the app leaves them out of its window | **Strata** (strata-shell), Topline | done |
| 3 | Quill gets a File / Edit / View menu bar | Quill | done |
| 4 | A Bluetooth icon in Topline: off, on, or which devices are connected | Topline | done |
| 5 | Printing in Topline: an icon while something prints, notifications when it has printed, didn't print, or the printer stopped | Topline | done |
| 6 | Debian (`BASE=debian`, trixie) build tested end to end, as the default | build | moved to 0.9 |

Also in 0.8: Dials writes Wayfire's settings file in place, so changes to
animations, title bars and the like apply straight away rather than after
logging in again.

## 0.9 "menus everywhere" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Menu bars for the rest of freemac's apps (Drawer, Frame, Tally, Chime, Harbor, Dials) | apps | done |
| 2 | App menus from Qt apps in Topline (KDE's appmenu protocol and DBusMenu) | Strata, Topline | moved to 1.0 |
| 3 | Quick settings from Topline: Wi-Fi, Bluetooth, Do Not Disturb, dark mode, night light, brightness and volume in one panel | Topline | done |
| 4 | Screen brightness and a night light (warmer colours in the evening) in Dials > Displays | Dials | done |
| 5 | Drag a window to the left or right edge to fill that half of the screen, to a corner for a quarter, to the top to fill it; Super+arrows too | Strata | done |
| 6 | Keyboard panel: see and change shortcuts | Dials | done |
| 7 | Debian (`BASE=debian`, trixie) build tested end to end, as the default | build | moved to 1.0 |

Qt app menus moved because freemac ships no Qt apps yet and Qt only hands its
menus over through KDE's own platform plugin; it needs more work in Strata to
do properly. The Debian build is still waiting on the build machine reaching
Debian's mirrors.

## 1.0 "release candidate" (1.0.0-rc1)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | App menus from Qt apps in Topline | Strata, Topline | moved to Later: Qt apps only publish menus on Wayland through KDE's own protocol and platform plugin, and freemac ships no Qt apps yet |
| 2 | Debian (`BASE=debian`, trixie) build tested end to end, as the default | build | still blocked: the build host can't reach Debian's servers |
| 3 | Seek finds files by the text inside them, not only by name | Seek | done: a full-text index of text, OpenDocument and Word files in the home folder |
| 4 | Drawer: tabs, a sidebar you can edit, and a preview of the selected file with Space | Drawer | done: tabs, Favourites you add, reorder and remove, and Glance on Space |
| 5 | Pier: folders on the dock (Downloads stack) and a Trash you can empty | Pier | done |
| 6 | First-run welcome: pick light or dark, wallpaper, Wi-Fi and a user account before the desktop opens | Welcome | done: light or dark, wallpaper, Wi-Fi and the account page; accounts themselves are made by Keel at install and in Dials > Users |

## 1.1 "everyday extras" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Volume, mute, microphone, brightness and media keys work, with the new level shown in a small panel near the bottom of the screen | freemac-keys, Beacon | done |
| 2 | What's playing in quick settings (from any player that publishes it), with back, play/pause and forward | Topline | done |
| 3 | A notes app: notes are plain text files in Documents › Notes, saved as you type, searchable, and found by Seek | **Jot** | done |
| 4 | Screen recording: Ctrl+Print for the screen, Ctrl+Shift+Print for an area, a red stop button in Topline, videos saved to Videos › Screen Recordings | Lens | done |
| 5 | Clipboard history: Super+Shift+V lists the last 50 things you copied; secrets marked by password managers are never kept; on/off and clear in Dials > Keyboard | freemac-clips, Dials | done |
| 6 | Drawer compresses files to .zip and expands .zip and tar archives (safely: nothing is written outside the new folder) | Drawer | done |
| 7 | Hot corners: pick what each screen corner does (all windows, all desktops, show the desktop, notifications, a new note, lock) | Dials, Strata | done |

## 1.2 "feels like a Mac" (done)

The goal: someone who knows a Mac sits down at freemac and it feels like one,
without any Apple artwork, code or names.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Title bars: rounded top corners, a soft edge, centred titles, round grey buttons on the left whose symbols show on hover | strata-decor | done |
| 2 | Every installed app's icon on the same rounded-square tile, including apps installed later | freemac-icon-tiles | done |
| 3 | Mac apps (.app) show their own icon, read from the app's Info.plist and .icns file; drop one into Applications and it's in the app grid and dock | freemac-mac-app, Drawer | done; graphical Mac apps still can't run, and opening one says so |
| 4 | A full GTK theme of our own, light and dark, with Mac-like blue and Inter as the system font | freemac-theme | done |
| 5 | Start-up: no boot menu or text, just the freemac mark on black with a progress bar | build, Keel | done |
| 6 | Login screen like a Mac's: blurred wallpaper, round picture, password field with an arrow | Gangway | done |
| 7 | Terminal under its plain name, with its own icon and a light look; windows no longer wobble | build, Strata | done |
| 8 | Every app on one full-screen grid over a blurred wallpaper, with search and pages (F4, the dock or a hot corner) | **Marina** | done |
| 9 | Dock icons bounce while an app starts, and magnified icons rise out of the dock instead of stretching it | Pier | done |

## 1.3 "nothing gives it away" (done)

What still looked like Linux after 1.2.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Windows round at all four corners, not only at the top | Strata | done |
| 2 | Our own pointer: a black arrow with a white edge, and matching busy, text and hand pointers | freemac-cursors | done |
| 3 | The lock screen looks like the login screen: blurred wallpaper, clock, round picture, password field | Latch | done |
| 4 | Marina: drag apps to rearrange them, and drop one on another to make a folder | Marina | done |
| 5 | Qt and GTK 4 apps use the same colours and font as the rest | build | done |
| 6 | New windows never start under the menu bar; one too big is made to fit | strata-decor | done |

## 1.4 "the desktop is yours" (in progress)

What a Mac user reaches for next.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Files in the Desktop folder show on the wallpaper as icons: open, move, rename and drop files onto them | Backdrop | done |
| 2 | Alt+Tab shows the open apps as a row of icons on a frosted panel; let go to switch | Strata, Topline | |
| 3 | Minimising a window shrinks it into the dock, and it grows back out | Strata | |
| 4 | Screenshots land on the Desktop, named with the date and time | Lens | done |

## Later

- App menus from Qt apps in Topline (needs KDE's app-menu protocol in
  Strata and a Qt platform plugin that uses it).
- The Debian build, as soon as a build host can reach Debian's servers.

- Ferry, step by step: threads, sockets, C++ programs (libc++), other dynamic
  libraries. Frameworks such as Foundation
  only after that, and only from public documentation. See
  [ARCHITECTURE.md](ARCHITECTURE.md#mac-app-compatibility-optional-layer).
- Signed images, a package repository and release docs.
- Testing on real laptops: Wi-Fi, batteries, trackpad gestures, suspend.
