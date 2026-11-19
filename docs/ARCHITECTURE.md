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
| **Strata** | Window-management layer: Wayfire config, our own plugins and decoration theme | C++ (Wayfire plugin API) | Left-side window buttons in an original shape and colour scheme; overview of all windows (built on Wayfire's scale and expo ideas, our own look); virtual desktops in a row; 3- and 4-finger gestures. |
| **Topline** | Global menu bar | Python + GTK 3 (layer-shell), C later if needed | Left: system menu, focused app name, the app's own menus (GTK apps since 0.8, through strata-shell; Qt apps planned). Right: network, sound and battery icons (0.4), Bluetooth and printing (0.8), clock; app status icons (StatusNotifierItem) and quick settings later. Falls back to a minimal per-app menu when an app exports none. |
| **Backdrop** | Desktop wallpaper | Python + GTK 3 (layer-shell, background layer) | One window per screen under the menu bar and dock; fills the screen at any shape (or fits or stretches, set in Dials). Replaced wf-shell's background in 0.4. |
| **Pier** | Dock | Python + GTK 3 (layer-shell) | Pinned and running apps from Wayfire's IPC; cursor-proximity magnification; running indicators; size and magnification set in Dials. |
| **Seek** | Search launcher on Super+Space | Python + GTK 3 (layer-shell) | Apps (`.desktop`), files in the home folder, calculator; later plocate, settings panels, unit conversion. |
| **Drawer** | File manager | Python + GTK 3 | Icon, list and column (Miller) views with a preview pane; sidebar of places; GIO for opening files and the Trash. |
| **Dials** | Settings app | Python + GTK 3 | Appearance (light/dark through the GSettings `color-scheme` and GTK theme), wallpaper, dock and menu bar, displays (scale), trackpad and mouse, keyboard layout, network and Wi-Fi, sound (WirePlumber's wpctl), power (screen blanking through Wayfire's idle plugin, power-profiles-daemon), notifications, accessibility, Bluetooth (BlueZ over D-Bus, with its own pairing agent), printers (CUPS), users (through a small root helper run with pkexec: add, delete, change password, administrator, automatic login), about. Writes the same files Wayfire, Backdrop and Pier watch, so changes apply at once. |
| **Beacon** | Notifications | Python + GTK 3 (layer-shell) | Implements the freedesktop.org notification D-Bus interface, so `notify-send` and every app's notifications work. Banners in the top-right corner, a centre with a calendar and the last 50 notifications (opened from the clock), Do Not Disturb. |
| **Lens** | Screenshots | Python + GTK 3 | Whole screen, an area or the focused window, on Print, Shift+Print and Alt+Print; uses grim and slurp, copies to the clipboard with wl-copy and announces the file through Beacon. |
| **Quill** | Text editor | Python + GTK 3 + GtkSourceView 4 | Syntax colours, line numbers, find and replace, go to line, wrapping, light and dark schemes, safe saving. |
| **Frame** | Image viewer | Python + GTK 3 | Fit, zoom, rotate, next and previous in the folder, animated GIFs, Trash, full screen. |
| **Harbor** | App centre and updates | Python + GTK 3 | Browses the AppStream catalogue of the archive (categories, search, picks), app pages with Install, Open and Remove, an Installed list and an Updates page, all through PackageKit, which asks for the password through polkit. A background check once a day notifies through Beacon when updates are ready. Refreshes old package lists before installing. |
| **Latch** | Lock screen | Python (launcher) + gtklock | Locks with gtklock dressed in freemac's style (current wallpaper, large clock, password field); Super+L and Lock Screen in the system menu; swayidle locks after the idle time set in Dials > Power, and before sleep. |
| **Tally** | Calculator | Python + GTK 3 | Its own expression parser (decimal arithmetic for the basic operations), a running tape, a scientific mode with degrees or radians, `Ans`, and keyboard entry. |
| **Chime** | Clock | Python + GTK 3 | World clocks, alarms with repeat days, timers and a stopwatch. Keeps running in the background while an alarm or timer is set, rings with the freedesktop sound theme and notifies through Beacon. |
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
- **Left-side window buttons** come from GTK's decoration layout and a GTK CSS
  layer (`/etc/skel/.config/gtk-3.0/gtk.css`) that draws them as freemac's own
  rounded squares. Apps that ask the compositor for a title bar (foot, some Qt
  apps) still get Wayfire's right-side buttons until our decoration plugin.
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
