# freemac roadmap

Work happens in batches. Each batch is built as an ISO, checked in QEMU
(live session, and an install where the batch touches installing or booting),
then merged into `Main`. When a batch is finished, the next one is written
here. Every item follows the [clean-room rules](../README.md#clean-room-rules).

Status marks: **done**, **in progress**, **planned**.

## 0.5 "everyday desktop" (in progress)

Things a person reaches for in the first hour that 0.4 did not have.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Notifications: a notification service for apps, banners in the top-right corner, a history list and Do Not Disturb, opened from the clock in Topline | **Beacon** | planned |
| 2 | Screenshots: whole screen (Print), an area (Shift+Print) and the focused window (Alt+Print), saved to Pictures/Screenshots with a notification | **Lens** | planned |
| 3 | Text editor with syntax colours, line numbers, find and replace, and dark mode, in place of Mousepad | **Quill** | planned |
| 4 | Image viewer with zoom, fit, rotate and next/previous, in place of Ristretto | **Frame** | planned |
| 5 | Dials: Sound panel (output and input device, volumes) | Dials | planned |
| 6 | Dials: Power panel (battery, screen dimming and blanking, what the power button does) | Dials | planned |
| 7 | Dials: Accessibility panel (larger text, reduced motion, high contrast, bigger pointer) | Dials | planned |
| 8 | Dials: Notifications panel (Do Not Disturb, banner time) | Dials | planned |

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

- Mac app compatibility through Darling, as an optional add-on. On hold until
  the project owner decides on the licence exception described in
  [ARCHITECTURE.md](ARCHITECTURE.md#mac-app-compatibility-optional-layer).
- Signed images, a package repository and release docs.
- Testing on real laptops: Wi-Fi, batteries, trackpad gestures, suspend.
