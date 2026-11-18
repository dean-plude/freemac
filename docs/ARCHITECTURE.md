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
|  Apps:  Drawer (files)   Dials (settings)   Seek (launcher)      |  ours
+-----------------------------------------------------------------+
|  Shell: Topline (menu bar)   Pier (dock)   notifications         |  ours
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
| wlroots | Compositor library under Wayfire | MIT |
| wf-touch / libinput | Gesture recognition, input | MIT |
| GTK 4 | Toolkit for our shell and apps | LGPL-2.1-or-later |
| gtk4-layer-shell | Panels and dock as Wayland layer surfaces | MIT |
| libadwaita | Widgets and light/dark style handling | LGPL-2.1-or-later |
| PyGObject | Python bindings for prototyping shell apps | LGPL-2.1-or-later |
| greetd | Login manager and autologin | GPL-3.0-or-later |
| PipeWire, WirePlumber | Audio and screen capture | MIT |
| NetworkManager | Networking | GPL-2.0-or-later (separate program) |
| xdg-desktop-portal(-gtk) | Color-scheme setting, file pickers | LGPL-2.1-or-later |
| libdbusmenu / appmenu-gtk-module | Exporting app menus for the global menu bar | LGPL-3.0 / LGPL-3.0-or-later |
| plocate | Fast file-name index for Seek | GPL-2.0-or-later (separate program) |
| Inter font | UI typeface | SIL OFL 1.1 |
| Calamares (later) | Installer | GPL-3.0-or-later |
| Darling (optional add-on, milestone 6) | Runs some macOS programs | GPL-3.0, plus APSL-2.0 Apple open-source parts (separate program) |

## Components we write

| Name | What it is | Language | Notes |
| --- | --- | --- | --- |
| **Strata** | Window-management layer: Wayfire config, our own plugins and decoration theme | C++ (Wayfire plugin API) | Left-side window buttons in an original shape and colour scheme; overview of all windows (built on Wayfire's scale and expo ideas, our own look); virtual desktops in a row; 3- and 4-finger gestures. |
| **Topline** | Global menu bar | Python + GTK 4 (layer-shell), C later if needed | Left: system menu, focused app name, app menus read over DBusMenu (KDE appmenu protocol on Wayland). Right: status icons (StatusNotifierItem), clock, quick settings. Falls back to a minimal per-app menu when an app exports none. |
| **Pier** | Dock | Python + GTK 4 (layer-shell) | Pinned and running apps from `wlr-foreign-toplevel-management`; cursor-proximity magnification; running indicators; trash at the end. |
| **Seek** | Search launcher on Super+Space | Python + GTK 4 | Apps (`.desktop`), files (plocate), settings panels, calculator, unit conversion. |
| **Drawer** | File manager | Python + GTK 4 / libadwaita | Icon, list and column (Miller) views; sidebar of places; GIO for file operations and trash. |
| **Dials** | Settings app | Python + GTK 4 / libadwaita | Appearance (light/dark through `org.freedesktop.appearance` color-scheme), wallpaper, dock and menu bar options, displays, trackpad, network, sound. |
| **freemac-theme** | GTK theme, cursor, icon set, wallpapers | CSS, SVG | All original artwork. Until our icon set exists we ship a free third-party icon theme and record its licence here first. |
| **build/** | ISO build tooling | POSIX shell | This repository's `build/build-iso.sh`. |

Python is chosen for the first versions of the shell apps because it lets the
look and behaviour iterate quickly; anything that turns out to be performance
sensitive (the dock's magnification, for example) can move to C or Rust later
without changing the user experience.

## Hard problems we know about

- **Global menus on Wayland.** There is no single standard. Qt apps can export
  menus through the KDE appmenu protocol; GTK 3 apps through
  appmenu-gtk-module; GTK 4 and Electron apps mostly cannot. Topline must
  handle "no menu exported" gracefully from day one.
- **Overview and gestures** need compositor support, which is why Strata is
  built inside Wayfire rather than as a separate client.
- **Hardware support** follows Debian's kernel and firmware (we enable
  `non-free-firmware` so Wi-Fi works on common laptops).

## Mac app compatibility (optional layer)

Goal: let some macOS programs run on freemac the way Wine lets Windows programs
run on Linux, without macOS itself and without anything taken from a Mac.

**Approach.** Package the open-source
[Darling](https://github.com/darlinghq/darling) project as an optional
`freemac-darling` add-on that is **not** part of the default ISO. Darling loads
Mach-O programs and provides its own implementations of macOS system libraries
and frameworks. We integrate it rather than write our own: a desktop file
handler so `.app` bundles open from Drawer, and a Dials panel to install or
remove it.

**Licence.** Darling's own code is GPL-3.0. It also builds Apple's published
open-source Darwin components (libc, libdispatch and others), which are under
the Apple Public Source License 2.0, a free licence that is not GPL-compatible.
Because Darling is a separate program, shipping it as its own package beside
freemac is fine licence-wise. It does put Apple-published open-source code on
the system, so the clean-room rule 1 needs a deliberate, narrow exception for
this one optional package before milestone 6 starts. That is a decision for the
project owner; until it is made, Darling is out of scope.

**What it runs today (honestly).** Command-line programs and many developer
tools work. Graphical apps need AppKit, Metal and many other frameworks that
Darling only partly implements, so GUI support is experimental and most
everyday apps do not run. Check the Darling project's current status before
promising anything to users.

**Hard limits, by design:**

- No App Store apps: they are FairPlay-encrypted and tied to Apple ID. freemac
  will not decrypt them, bypass DRM or sign in to Apple services.
- No Apple binaries, frameworks or system files copied from a Mac, ever, even
  from the user's own machine. Compatibility comes only from open-source
  reimplementations.
- Intel (x86-64) and universal binaries only; Apple-silicon-only apps cannot
  run on a PC.

## Build pipeline (milestone 1)

1. `debootstrap` a minimal Debian root for a pinned suite (optionally from a
   fixed snapshot.debian.org timestamp).
2. Install kernel, live-boot, systemd and a small tool set in a chroot.
3. Apply `build/overlay/` (branding, autologin, hostname).
4. Normalise timestamps to `SOURCE_DATE_EPOCH`, strip caches and machine ids.
5. Pack the root into `live/filesystem.squashfs`.
6. Assemble a hybrid BIOS/UEFI ISO with `grub-mkrescue`.

See [the README](../README.md) for how to build and test.
