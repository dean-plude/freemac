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

## 0.9 "menus everywhere" (planned)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Menu bars for the rest of freemac's apps (Drawer, Frame, Tally, Chime, Harbor, Dials) | apps | planned |
| 2 | App menus from Qt apps in Topline (KDE's appmenu protocol and DBusMenu) | Strata, Topline | planned |
| 3 | Quick settings from Topline: Wi-Fi, Bluetooth, Do Not Disturb, dark mode, volume and brightness in one panel | Topline | planned |
| 4 | Screen brightness and a night light (warmer colours in the evening) in Dials > Displays | Dials | planned |
| 5 | Drag a window to the left or right edge to fill that half of the screen, to the top to fill it | Strata | planned |
| 6 | Keyboard panel: see and change shortcuts | Dials | planned |
| 7 | Debian (`BASE=debian`, trixie) build tested end to end, as the default (moved from 0.6; waiting until the build machine can reach Debian's mirrors) | build | planned |

## Later

- Ferry, step by step: threads, sockets, C++ programs (libc++), other dynamic
  libraries, opening Mac programs from Drawer. Frameworks such as Foundation
  only after that, and only from public documentation. See
  [ARCHITECTURE.md](ARCHITECTURE.md#mac-app-compatibility-optional-layer).
- Signed images, a package repository and release docs.
- Testing on real laptops: Wi-Fi, batteries, trackpad gestures, suspend.
