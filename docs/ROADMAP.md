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

## 0.6 "apps and safety" (planned)

- **Harbor**, an app centre for open-source apps: browse, install and remove
  apps from the Debian archive (and optionally Flathub), with categories and
  search. Installs go through PolicyKit.
- Lock screen with idle locking, Super+L and a Lock item in the system menu.
- System updates: a check in the background and an Updates section in Harbor.
- Debian (`BASE=debian`, trixie) build tested end to end, as the default.
- App menus from GTK and Qt apps in Topline where the apps export them.
- Calculator and clock apps with original names.

## 0.7 "own look" (planned)

- An original icon set for freemac's own apps and the common file types.
- Strata decoration plugin: our own window buttons on every app, not just GTK.
- More original wallpapers, with a dynamic light/dark pair.
- Printing (CUPS) and Bluetooth panels in Dials.
- Users panel in Dials (add, remove, change password, automatic login).

## Later

- Ferry, step by step: threads, sockets, C++ programs (libc++), other dynamic
  libraries, opening Mac programs from Drawer. Frameworks such as Foundation
  only after that, and only from public documentation. See
  [ARCHITECTURE.md](ARCHITECTURE.md#mac-app-compatibility-optional-layer).
- Signed images, a package repository and release docs.
- Testing on real laptops: Wi-Fi, batteries, trackpad gestures, suspend.
