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

## 1.4 "the desktop is yours" (done)

What a Mac user reaches for next.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Files in the Desktop folder show on the wallpaper as icons: open, move, rename and drop files onto them | Backdrop | done |
| 2 | Alt+Tab shows the open apps as a row of icons on a frosted panel; let go to switch | Tack | done |
| 3 | Minimising a window shrinks it into the dock, and it grows back out | Strata, Pier | done |
| 4 | Screenshots land on the Desktop, named with the date and time | Lens | done |

## 1.5 "the little things" (done)

The details a Mac user notices in the first ten minutes.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Right-click (or hold) an app in the dock: its windows, Keep in Dock, Hide, Quit | Pier, Strata | done |
| 2 | Drawer's sidebar shows the folder you're in | Drawer | done |
| 3 | Qt apps get freemac's own buttons, scroll bars and tabs (a Kvantum theme drawn from scratch) | art | done |
| 4 | Windows reopen at the size and place they had last time | Strata | done |

## 1.6 "the Command key" (done)

A Mac user's hands reach for Command, not Control.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The key beside the space bar is Command (as on a Mac keyboard; the Windows key can be Command instead): ⌘C, X, V, Z, A, S, F, N, O, P, T, W and the rest do in every app what Ctrl does, terminals get Ctrl+Shift, ⌘←/→ go to the start and end of a line and ⌥← → move by word, and freemac's own ⌘ shortcuts keep working | Strata, Dials | done |
| 2 | ⌘Q quits the app (every window), ⌘W closes one window, ⌘H hides the app, ⌥⌘H hides the others, ⌘` goes through the app's windows, ⌘Tab switches apps | Strata, Tack | done |
| 3 | Get Info in Drawer (⌘I): kind, size, where it is, when it was made and changed, and who can open it | Drawer | done |
| 4 | A start-up sound of our own when freemac starts, which can be turned off in Sound | art, Dials | done |

## 1.7 "menus and finishing touches" (done)

The small things a Mac user notices in their first minute.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Menus in Topline show each item's shortcut in Mac symbols (⌘C, ⇧⌘S) on the right, not "Ctrl+C" | Topline | done |
| 2 | Every app's bold name menu in Topline has About, Hide, Hide Others and Quit with their shortcuts, the same in every app | Topline | done |
| 3 | After ⇧⌘3 or ⇧⌘4, a small picture of the screenshot sits in the screen's corner for a few seconds; click it to open it | Lens | done |
| 4 | The Window menu has Minimize (⌘M), Zoom and Bring All to Front, then the app's windows with a tick by the front one | Topline, Strata | done |

## 1.8 "the details" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Moving the pointer along the menu bar while a menu is open opens the next menu, with no extra click | Topline | done |
| 2 | An app's dialogs (its Settings or About window) count as that app: the menu bar and the Dock name the app, not a second unknown one | Topline, Pier | done |
| 3 | ⌘, opens an app's settings where it has them, and every app menu offers Settings… (and the app's own About) when it does | Topline, Strata | done |
| 4 | Pier's right-click menu: a tick by the front window, and Options with Keep in Dock and Open at Login | Pier | done |

## 1.9 "the Dock and stuck apps" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | ⌥⌘⎋ (and Force Quit… in the logo menu) opens a Force Quit window listing running apps; Force Quit asks once, then ends the app | Strata, Force Quit | done |
| 2 | Drag apps along the Dock to reorder them, drag one up and out to take it off, or drag a running app in among the kept ones to keep it | Pier | done |
| 3 | Drop a file on an app in the Dock to open it there; only apps that can open that kind of file light up | Pier | done |
| 4 | Dials > Dock and Menu Bar: double-click a window's title bar to Zoom, Minimize or Do Nothing | Dials, Strata | done |

## 1.10 "alerts and the desktop" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Alerts look like a Mac's: a small panel with no title bar, the app's icon on top, the question in bold, a short line under it, and equal buttons side by side (stacked when there are three), the default in blue; Return and Esc work | alert.py, theme | done |
| 2 | Dials' sidebar looks like a Mac's settings sidebar: grouped plain rows, each icon white in a small coloured tile | Dials | done |
| 3 | Clicking the desktop makes Drawer the app in the menu bar, with File (New Drawer Window, New Folder, Find) and Go menus and Empty Trash in its app menu | Topline | done |
| 4 | Drop files on a folder in the Dock (like Downloads) to move them there; the folder darkens while they're over it | Pier | done |

## 1.11 "the file manager and settings, finished" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A search field at the top of Dials' sidebar that finds a setting by name or everyday words (wifi, battery, volume) and opens its page | Dials | done |
| 2 | Drawer's sidebar like a Mac file manager's: Favorites and Locations headings, plain rows with small blue icons | Drawer | done |
| 3 | A thin line, not a thick bar, between a sidebar and its page (the theme's divider no longer paints its grab area) | theme | done |
| 4 | Alerts from the Dock (Empty Trash) show Drawer as the app in the menu bar; Dials' alerts show Dials' own icon | Topline, Dials | done |

## 1.12 "windows that behave like a Mac's" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Minimizing (⌘M or the yellow button) shrinks the window down into its place in the Dock, and it grows back out from there | Strata, Pier | done |
| 2 | A minimized window shows as its own small picture at the right end of the Dock, beside the Trash, with its app's icon on it; clicking it brings the window back. Hidden apps' windows get none. Dials > Dock can put minimized windows into their app's icon instead | Strata, Pier, Dials | done |
| 3 | Closing an app's last window leaves the app in the menu bar (and its Dock dot), as on a Mac, for apps that keep running | Topline, Pier | moved to 1.13 |
| 4 | Window > Fill fills the screen without going full screen, and Window > Center puts the window in the middle | Strata, Topline | done |

## 1.13 "apps that stay open" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Closing an app's last window leaves the app in the menu bar, with its own menus, and keeps its Dock dot, as on a Mac. Quill and Jot keep running; Drawer and Tally don't (a Mac's Calculator quits with its window) | Topline, Pier, Quill, Jot | done |
| 2 | Clicking a running app in the Dock that has no windows opens a new one; Jot's File > New Note works with no window open | Pier, Jot | done |
| 3 | ⌘` moves between the front app's windows | Strata | done (from an earlier release) |
| 4 | ⌘Tab lists apps that are open with no window, and picking one opens a window | Tack | done |
| 5 | ⌘Q, the menu bar and the Dock quit such an app as a whole; Quill asks about unsaved changes first | Strata, Topline, Pier, Quill | done |
| 6 | The menu bar keeps the front app while ⌘Tab or Seek is up, or while its windows are minimized, instead of showing Drawer | Topline | done |

## 1.14 "the menu bar, finished" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The menu bar, the Dock and ⌘Tab name apps by their short names (Welcome, not "Welcome to freemac"; Firefox, not "Firefox Web Browser") | apps, Topline, Pier | done |
| 2 | A dialog (Save, an alert) keeps its app's full menus in the bar | Topline | done |
| 3 | The Dock dot shows for apps open at login straight away, not only after a window event | Pier | done |
| 4 | Menu items that need a window are greyed out while the app has none | Topline | done |
| 5 | Closing an app's last window keeps that app in front, rather than another app's window taking over | Strata, Topline | done |
| 6 | Hints and labels show Mac shortcuts (⌘N), not "Ctrl+N" | Jot | done |
| 7 | Save dialogs and unsaved-changes alerts come down from their window's title bar as sheets and move with the window | Strata | done |

## 1.15 "the keyboard, finished" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | An app's own shortcuts work while it is in front with no window (⌘N in Jot opens a note) | Strata, Topline | done |
| 2 | The Save sheet starts small (name and where) and opens out to the full file browser | Quill | done |
| 3 | Full keyboard access: Tab moves through the fields and buttons of alerts and sheets, Space presses the focused one | apps | done |
| 4 | ⌘. and Escape cancel a sheet or dialog, Return picks its default button; saving over a file asks first | Strata, apps | done |

## 1.16 "every app has a menu bar" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Apps that publish no menus (Firefox, VLC, Qt and older apps) still get File, Edit and Window menus in the bar, whose items press the app's own shortcuts | Topline, Strata | done |
| 2 | Edit has Undo, Redo, Cut, Copy, Paste, Select All and Find for every app, as on a Mac | Topline | done |
| 3 | Web and Firefox get their usual menus (New Tab, New Window, Reopen Closed Tab, History, Bookmarks, zoom), and VLC gets Playback, from a short list freemac keeps | Topline | done |
| 4 | Help in every app's bar, with a search that finds menu items | Topline | moved to 1.17 |

## 1.17 "help and search" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Help in every app's bar, with a search box that finds menu items as you type, showing the menu each is in and its shortcut | Topline | done |
| 2 | Choosing a found item runs it, keyboard only (arrows and Return) | Topline | done |
| 3 | Seek finds menu items of the app in front too | Seek | moved to 1.18 |

## 1.18 "search everywhere" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Seek finds the menu items of the app in front (Topline shares them over D-Bus), with the app's own icon, and Return runs the item | Seek, Topline | done |
| 2 | Seek finds settings by name or by what's on the page ("wallpaper", "night", "mouse") and opens Dials at that page; a settings page comes before an app found only by its description | Seek, Dials | done |

## 1.19 "first impressions" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The menu bar keeps the app in front right after login (opening Help before clicking anything switched the bar to Drawer: Welcome came forward before the bar was listening) | Topline | done |
| 2 | Dials builds each page the first time it's shown, so its window opens in about half the time (10 s to under 5 s in a test PC) | Dials | done |
| 3 | Help and Seek close when you click anywhere outside them, as an open menu or Spotlight does | Topline, Seek | done |
| 4 | Settings results in Seek show Dials' own icon | Seek | done |

## 1.20 "guides and previews" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Help also lists short freemac Guide topics that match, opened in a small Guide app (15 topics: the Command key, apps, windows, desktops, Seek, Help, files, screenshots, Wi-Fi, the look, sound, installing apps, locking, a stuck app, clipboard history) | Guide, Topline | done |
| 2 | Seek shows a preview of the chosen result beside the list: a picture, the start of a text file, a file's kind, size and date, or an app's description | Seek | done |
| 3 | Every freemac app starts faster: the image now ships their Python code compiled (Dials' own code went from about 1.3 s to 0.3 s to load in a test PC) | build | done |
| 4 | Seek finds Guide topics too | Seek | done |

## 1.21 "glass and polish" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Seek, Help and notices are nearly solid, so text under them doesn't show through (the compositor's blur doesn't reach these surfaces yet) | Shell | done |
| 2 | Guide opens from the freemac menu and from Welcome's last page | Topline, Welcome | done |
| 3 | Frame opens PDFs and pages through them; PDFs open in Frame by default | Frame | done |
| 4 | Seek's preview and Drawer's Glance show the first page of a PDF | Seek, Drawer | done |
| 5 | Files opened by other apps, and a screenshot's preview, open in their own app instead of the web browser | Image, Lens | done |
| 6 | Seek lists the front app's commands, not the names of its open windows | Topline, Seek | done |

## 1.22 "everyday apps" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A calendar app with day, week and month views: drag events to move them, events that repeat, undo, all kept in one standard .ics file | Tide (new) | done |
| 2 | A contacts app for names, companies, phone numbers, email and postal addresses, birthdays and notes, one standard .vcf card per person; opening a .vcf adds it | Crew (new) | done |
| 3 | The menu bar's clock opens a small calendar for the month, with dots on days that have events and the chosen day's events under it | Topline, Beacon | done |
| 4 | Frame marks up pictures and PDFs: draw, boxes, text, and a signature drawn once on a pad; Save a Copy keeps the original as it was, and closing asks about marks not yet saved | Frame | done |
| 5 | Every milestone is published as a downloadable live ISO, built and booted (BIOS and UEFI) in QEMU by a GitHub workflow before it goes up | build | done |

## 1.23 "reminders" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Tide's events can give a notice a set time before they start; clicking it opens that day, and Snooze shows it again in 5 minutes | Tide, Beacon | done |
| 2 | A reminders app: lists in colours, Today, Scheduled, All and Flagged, due dates typed as words ("Friday 5pm"), priorities, flags and notes; a notice when one is due, with Mark as Completed and Snooze | Nudge (new) | done |
| 3 | Seek finds contacts, coming events and reminders | Seek | done |
| 4 | Crew's birthdays show in Tide, in purple, every year | Tide, Crew | done |
| 5 | The menu bar shows a newly opened app's name at once | Topline | done |
| 6 | Seek stays running, so ⌘Space opens it without starting a program each time | Seek | done |
| 7 | Pop-up panels and tooltips no longer sit in a grey box | theme | done |
| 8 | ⌘Q quits Tide, Crew and Nudge as a whole (it only closed their windows, leaving them running) | Strata | done |
| 9 | Qt, Kvantum and printer helper apps stay out of the app grid and Seek; Dials still opens the printer one | build | done |
| 10 | Quick settings and the volume pop-up are nearly solid, so windows no longer show through their text | Topline | done |
| 11 | Esc while typing a reminder puts its title back, and a new empty one goes away | Nudge | done |
| 12 | New screenshots of 1.23 in the README | docs | done |
| 13 | App windows: one rounded corner from the title bar down, with no notch under the title bar | freemac-theme | done |

## 1.24 "look and mail" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | An emoji and symbols picker (Control-⌘-Space, and Edit > Emoji & Symbols) that types the chosen one into the app in front | Glyph (new), Topline | done |
| 2 | A mail app for IMAP and SMTP accounts: inbox, read, reply, write, attachments | Post (new) | done |
| 3 | Tide, Crew and Nudge can sync with online calendars and contacts (CalDAV, CardDAV) set up once in Dials | Dials, Tide, Crew, Nudge | done |
| 4 | Seek's window is kept ready so it takes typing the moment ⌘Space is pressed | Seek, Glyph (`ready_panel.py`) | done |
| 5 | A photos app: the Pictures folder by month, a large viewer, and import from a camera or phone | Cove (new) | done |

## 1.25 "drives and albums" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | USB drives, memory cards and phones open by themselves when plugged in, show under Locations in Drawer's sidebar and on the Desktop, and have Eject | Drawer, Backdrop | done |
| 2 | A colour for each calendar, local and online, with a list to show or hide each one | Tide | done |
| 3 | The menu bar always shows the app in front, also just after an app opens or quits | Topline | done |
| 4 | Albums in Cove: make one, add photos to it, and play any album or month as a slideshow | Cove | done |
| 5 | Share from Drawer, Cove and Frame: send a file by mail in Post, or copy it to a drive | Drawer, Cove, Frame, Post | done |

## 1.26 "files that move" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Copy and paste files: ⌘C, then ⌘V for a copy or ⌥⌘V to move them, between Drawer windows, tabs and the Desktop; Duplicate (⌘D) | Drawer, Backdrop | done |
| 2 | Drag files onto a folder, a sidebar place or another window to move them (copy when it's another disk, or with ⌥) | Drawer | done |
| 3 | A small window shows a long copy's progress with a Stop button, and a name that's taken asks Keep Both, Stop or Replace | Drawer, Backdrop | done |
| 4 | Undo (⌘Z) the last move, rename, copy or Move to Trash | Drawer | done |

## 1.27 "music and backups" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A music app for your Music folder, by album, artist and song, with play, shuffle and repeat, shown in the menu bar's what's playing and played with the media keys | Shanty | done |
| 2 | Backups to a drive: pick one in Dials, and while it's plugged in your home folder is copied every hour, keeping earlier copies with unchanged files shared | Lifeboat, Dials | done |
| 3 | Bring back a file or folder from any backup, browsed by date | Lifeboat, Drawer | done |

## 1.28 "videos, the machine, and drives" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A video player: open a video from Drawer or the Videos folder, play, pause and scrub with controls that fade away, full screen, and pick up where you left off | Reel | done |
| 2 | See what's using the processor and memory, app by app, with a small history graph, and quit one that's stuck | Gauge | done |
| 3 | See every drive with its space used, and eject, rename or erase one | Hull | done |

## 1.29 "the camera, the weather, and notes" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Take pictures of yourself with the camera: a 3, 2, 1 countdown, a flash, and fun effects that bend and colour the picture, saved to Pictures | Pose | done |
| 2 | The weather where you are and in places you add: now, by the hour and for the week, with no account needed | Sky | done |
| 3 | Sticky notes on the desktop in a few colours, kept between restarts | Stickies | done |

## 1.30 "record, draw, and play" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Record your voice: a big red button, a moving level, recordings listed with their length, play back, rename, trim the start and end, share to the Drawer | Echo | done |
| 2 | Draw on a big canvas: pens, a highlighter, shapes, sticky text, stickers, an eraser, undo, saved as you go and exported as a picture | Easel | done |
| 3 | Play chess against the computer at a few levels, or with a friend on the same screen, with hints and undo | Rook | done |

## 1.31 "read and play" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Patience (solitaire): drag cards or double-click to send them home, draw one or three, undo, a hint, and the cards finish themselves at the end | Patience | done |
| 2 | Mines: clear a field without setting off a mine, in three sizes; the first click is always safe, right-click flags, best times kept | Mines | done |
| 3 | Read e-books: a shelf of your EPUB books with their covers, page by page with a contents list, bigger or smaller text, light, sepia or night pages, and it keeps your place | Books | done |

## 1.32 "play, look up and type" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A piano to play with the mouse or the keyboard, with a few instruments whose sounds freemac makes itself, and a way to record a tune and play it back | Ivory | done |
| 2 | A dictionary that works without the internet: definitions, examples and words that mean the same, from WordNet | Words | done |
| 3 | Typing practice for children and grown-ups: lessons a few keys at a time, a keyboard that shows the next key, and speed and accuracy kept | Typist | done |

## 1.33 "time, numbers and letters" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Screen time: how long each app was used today and this week, with a daily limit for an app that gives a warning before time is up | Logbook | done |
| 2 | A number puzzle (sudoku) with easy to hard puzzles, pencil marks, hints and undo | Nine | done |
| 3 | A font book: every font on the computer with a sample you can type, sizes, and adding a font file with a double-click | Typecase | done |

## 1.34 "graphs, boards and pairs" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A memory game: turn over cards to find the pairs, in four sizes and three picture sets, for one player or two taking turns | Pairs | done |
| 2 | A graphing calculator: draw y = … equations in colour, zoom and drag, and read off any point on a curve | Plot | done |
| 3 | A whiteboard: a big board for sticky notes, text, shapes, arrows and pictures, with as many boards as you like | Corkboard | done |

## 1.35 "puzzles, parts and colours" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A jigsaw puzzle: real-shaped pieces cut from a built-in picture or one of your own photos, 12 to 100 pieces, that click together when they fit | Jigsaw | done |
| 2 | About this computer: processor, memory, graphics, storage and version at a glance, with a full report of the hardware, USB devices, displays, network and sound; About freemac in the menu bar opens it | Manifest | done |
| 3 | A colour picker: pick a colour from anywhere on the screen, see it as hex, RGB and HSL, copy it, and keep the colours you like | Swatch | done |

## 1.36 "shapes, feeds and words" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A shape puzzle: slide and turn seven flat pieces to fill a silhouette, from easy outlines for kids to harder ones, with a hint when you're stuck | Tangram | done |
| 2 | Podcasts and news feeds: subscribe to a podcast or a website's feed, read new posts, and play episodes with the place remembered | Buoy | done |
| 3 | A word search: find hidden words in a grid of letters, with themed word lists, three sizes and a timer | Hunt | done |

## 1.37 "board games" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Four in a row: drop counters into a stand of seven columns, against the computer at three levels or a friend on the same computer | Fourway | done |
| 2 | Draughts (checkers): the 8×8 game with forced captures and kings, against the computer or a friend, with undo and the legal moves shown | Kings | done |
| 3 | Tile-matching solitaire: clear a stacked layout of original picture tiles by matching free pairs, with several layouts, hints, shuffle and undo | Cairn | done |

## 1.38 "learning and scanning" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Maths practice for children: rounds of adding, taking away, times tables and sharing, at levels from first sums upwards, with stars and a times-table chart | Sums | done |
| 2 | Flashcards: make decks of cards with a question and an answer, study them with the cards you know least coming back most often, and bring decks in from a spreadsheet file | Cue | done |
| 3 | Scanning: find a USB or network scanner, preview, pick the area, colour and resolution, and save pages as a picture or a many-page PDF | Glass | done |
| 4 | The Dock: names above icons, magnification that follows the pointer over the icons, shrinking to fit when crowded, and clicks through its clear top | Pier | done |

## 1.39 "school work" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Spreadsheets: a grid of cells with sums and formulas (SUM, AVERAGE, MIN, MAX, COUNT, IF, ROUND), number formats, sorting, a chart of the selected cells, and CSV files in and out | Ledger | done |
| 2 | Presentations: slides with a title, points and a picture, a few original themes, a full-screen show moved on with the arrow keys, and PDF out | Lantern | done |

## 1.40 "recovery" (done)

From 1.40 on, the work is on the desktop and the system itself.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A recovery mode: hold Ctrl as the computer starts (or choose Restart in Recovery in Dials) to bring back files from a Lifeboat backup, reset a forgotten password, check a disk, reinstall, get help online or use a terminal, with Wi-Fi and an administrator's password asked first | Recovery | done |

## 1.41 "date and time" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Date & Time settings: set the time automatically from the internet or by hand, choose the time zone by typing a city, 12 or 24 hours, and the day, date and seconds in the menu bar | Dials, Topline | done |
| 2 | The clock keeps itself right: systemd-timesyncd is installed, so automatic time works | system | done |
| 3 | Open and Save windows: the default button (Save, Open) is blue and readable; it was white on white | theme | done |

## 1.42 "dock that hides" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Automatically hide and show the Dock: it slides away, windows get the whole screen, and it slides back when the pointer reaches the bottom edge | Pier | done |
| 2 | A switch for it in Dials > Dock and Menu Bar, and ⌥⌘D to turn it on and off anywhere | Dials, keys | done |
| 3 | The Dock stays up while one of its menus is open or something is dragged over it | Pier | done |
| 4 | Guide topic: Hide the Dock until you need it | Guide | done |

## 1.43 "screen saver" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Screen savers: Drift (soft lights), Clock and Album (your photos, or the wallpapers) | Screen Saver | done |
| 2 | Dials > Screen Saver: pick one from its picture, Preview, and when it starts (3 minutes unless changed) | Dials | done |
| 3 | The lock waits for the screen saver: waking it asks for the password, with no desktop in between | Latch | done |
| 4 | A hot corner can start the screen saver | Dials, corners | done |
| 5 | Guide topic: Use a screen saver | Guide | done |

## 1.44 "stacks" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Use Stacks: the Desktop's files pile up by kind (Images, Screenshots, Documents, PDF Documents, Movies, Music and more) | Backdrop | done |
| 2 | A click fans a stack out in place and another gathers it; dragging a stack moves all its files; new files join their stack | Backdrop | done |
| 3 | Clean Up By Name, Kind or Date Modified on the desktop's menu | Backdrop | done |
| 4 | Get Info (⌘I and the right-click menu) on desktop files, shown under Drawer's name | Backdrop, Topline | done |
| 5 | Guide topic: Tidy the desktop with stacks | Guide | done |

## 1.45 "widgets" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Desktop widgets: an analog clock, a calendar with today's events, the weather from Sky and reminders that are due | Backdrop | done |
| 2 | Drag a widget anywhere on the desktop; its place is kept | Backdrop | done |
| 3 | A click opens the widget's app (Chime, Tide, Sky, Nudge); right-click to remove it | Backdrop | done |
| 4 | Edit Widgets… on the desktop's menu opens a gallery to add and remove them | Backdrop | done |
| 5 | Guide topic: Put widgets on your desktop | Guide | done |

## 1.46 "glance" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Glance on the desktop: Space looks at the selected files, and the arrow keys move from icon to icon | Backdrop | done |
| 2 | Movies and music play in Glance, with a play button and a time bar | Drawer | done |
| 3 | Every page of a PDF in Glance, to scroll through | Drawer | done |
| 4 | Several files in Glance, with arrows and "2 of 5"; arrows with one file move the selection; full screen (⌃⌘F) | Drawer, Backdrop | done |
| 5 | Pictures and PDFs show small pictures of themselves in Drawer's icon and list views | Drawer | done |
| 6 | Guide topic: Take a quick look at a file | Guide | done |

## 1.47 "drawer" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Put Back in the Trash (right-click or ⌘⌫), and an Empty button along the top of the Trash | Drawer | done |
| 2 | Open With on a file's menu: the usual app first, the others that can open it, and Other… for any app | Drawer | done |
| 3 | Sort By name, kind, date modified or size, from the View menu or a right-click on empty space; kept for every window | Drawer | done |
| 4 | Show Path Bar (⌥⌘P): the folders above this one along the bottom, each a click away | Drawer | done |
| 5 | Go to Folder… (⇧⌘G) with Tab to finish names and ~ for home; a file opens its folder with it chosen | Drawer | done |
| 6 | Guide topic: Sort, find and put back files | Guide | done |

## 1.48 "tags" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Seven tag colours on a file's menu; a click adds the tag or takes it off, with a tick when every chosen file has it | Drawer, Backdrop | done |
| 2 | A coloured dot after a tagged file's name in every Drawer view and on the desktop | Drawer, Backdrop | done |
| 3 | Tags in Drawer's sidebar: click a colour for every file with that tag, drop files on it to tag them | Drawer | done |
| 4 | Tags kept with the file (user.xdg.tags), and a note when a disk can't keep them | Shell | done |
| 5 | Guide topic: Tag files with colours | Guide | done |

## 1.49 "recents" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Recents at the top of Drawer's sidebar and in the Go menu (⇧⌘F): files opened lately, newest first | Drawer | done |
| 2 | Show in Enclosing Folder for a file in Recents or a tag, and Remove from Recents | Drawer | done |
| 3 | New Folder with Selection in Drawer and on the desktop, named ready to type, with Undo | Drawer, Backdrop | done |
| 4 | Tags in Get Info: click a colour to tag or untag | Drawer, Backdrop | done |
| 5 | Guide topic: Find files you opened lately | Guide | done |

## 1.50 "quick actions" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Spring-loaded folders: hold a drag on a folder (in the window or the sidebar) and it opens | Drawer | done |
| 2 | Quick Actions on pictures: Rotate Left, Rotate Right, Create PDF | Drawer, Backdrop | done |
| 3 | Guide topic: Turn pictures and make PDFs | Guide | done |

## 1.51 "move & resize" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Window > Move & Resize: Left, Right, Top, Bottom, the four quarters, and Return to Previous Size | Topline | done |
| 2 | Submenus in the bar's menus open when the pointer rests on them (the bar no longer refills a menu while it is open) | Topline | done |
| 3 | Screen zoom on or off, and the key to hold while scrolling (⌘, ⌥ or Control) | Dials | done |
| 4 | Guide: Move & Resize in Arrange windows, and a new topic: Zoom in on the screen | Guide | done |

## 1.52 "status bar" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Status bar: "2 of 15 selected, 1.4 GB available", View > Show Status Bar (⌘/) | Drawer | done |
| 2 | View > Show Sidebar | Drawer | done |
| 3 | Show Item Info on the desktop: a picture's size or a folder's item count under its name | Backdrop | done |
| 4 | Guide: status bar, sidebar and Show Item Info | Guide | done |

## 1.53 "gallery" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Gallery view (⌘4): the chosen file large (a picture, a PDF's first page, or its icon) with its name, kind, size and date, over a strip of the folder's files | Drawer | done |
| 2 | The chosen files stay chosen when the view changes | Drawer | done |
| 3 | Guide: ⌘4 in Find and organize files | Guide | done |

## 1.54 "preview" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | View > Show Preview (⇧⌘P): a pane with a large picture of the chosen file, its name and kind, and an Information list (created, modified, items, dimensions, tags) | Drawer | done |
| 2 | Guide: the Preview pane in Sort, find and put back files | Guide | done |

## 1.55 "rename items" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Rename Items for several files (F2 or right-click): Replace Text, Add Text before or after, or Format (name and index, counter or date), with an example and a warning for a taken name | Drawer, Backdrop | done |
| 2 | One Undo puts every name back, swapped names included | Drawer, Backdrop | done |
| 3 | Preview pane: no empty Information heading for several files | Drawer | done |
| 4 | Guide: Rename Items in Find and organize files | Guide | done |

## 1.56 "view options" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | View > Show View Options (⌘J): icon size slider, grid spacing, text size, Show item info, Sort By, kept for every window | Drawer | done |
| 2 | Guide: View Options in Sort, find and put back files | Guide | done |

## 1.57 "desktop view options" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Show View Options (⌘J) on the desktop: icon size, grid spacing, text size, Show item info, Use Defaults | Backdrop | done |
| 2 | Get Info, Rename Items and View Options from the desktop open with a normal-sized frame | Backdrop | done |
| 3 | Guide: View Options in Tidy the desktop with stacks | Guide | done |

## 1.58 "notifications" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Notifications from one app sit in a stack in the centre; a click spreads them out, and the x by the app's name clears them | Beacon | done |
| 2 | Do Not Disturb every day between two times, shown by the menu bar's icon and in the centre | Beacon, Topline, Dials | done |
| 3 | Dials > Notifications lists each app that has sent one, with Banners, In Notification Centre only or Off | Dials, Beacon | done |
| 4 | Guide: Manage notifications and Do Not Disturb | Guide | done |

## 1.59 "dock menus" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | An app's Dock menu lists up to five files it had open lately; a click opens one in that app | Pier | done |
| 2 | Right-click the Dock between its icons: Turn Hiding On/Off, Turn Magnification On/Off, Dock Settings… | Pier | done |
| 3 | Fix: after hiding was turned off, the Dock ignored the pointer until it was restarted | Pier | done |
| 4 | Guide: the Dock's menus in Hide the Dock until you need it | Guide | done |

## 1.60 "switcher keys" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | While ⌘Tab's switcher is up, Q quits the chosen app and takes it out of the row | Tack | done |
| 2 | H hides the chosen app; hidden apps show dimmed in the switcher | Tack | done |
| 3 | Choosing a hidden app brings all its windows back, not just one | Tack | done |
| 4 | Fix: the app's name under the icons was faint when the switcher didn't have the keyboard yet | Tack | done |
| 5 | Guide: Q and H in Open and switch apps | Guide | done |

## 1.61 "recent apps" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Up to three apps used lately that aren't kept in the Dock stay in it after they quit, newest first, after the open apps | Pier | done |
| 2 | Options > Remove from Dock on a recent app, or drag it out of the Dock, takes it off; Keep in Dock keeps it | Pier | done |
| 3 | Dials > Dock and Menu Bar: Show recent apps in Dock | Dials | done |
| 4 | Guide: recent apps in Hide the Dock until you need it | Guide | done |

## 1.62 "dock choices" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Dock and Menu Bar: Show indicators for open apps (the dots) | Pier, Dials | done |
| 2 | Dials > Dock and Menu Bar: Animate opening apps (the bounce) | Pier, Dials | done |
| 3 | ⌘← and ⌘→ move along ⌘Tab's row (they reach apps as Home and End) | Tack | done |
| 4 | Guide: the new Dock switches, and ⌘← ⌘→ in the switcher | Guide | done |

## 1.63 "dock position" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The Dock on the left, bottom or right edge of the screen, with magnification, names, menus, drags and hiding along that edge | Pier | done |
| 2 | Dials > Dock and Menu Bar: Position on screen; the Dock's right-click menu: Position on Screen | Dials, Pier | done |
| 3 | Desktop icons keep clear of a Dock on the right, and use the whole height when the Dock is on a side or hides | Backdrop | done |
| 4 | Guide: moving the Dock | Guide | done |

## 1.64 "menu bar that hides" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The menu bar slides away and comes back when the pointer reaches the top of the screen; windows use the whole height | Topline | done |
| 2 | Open menus and Help keep it on screen | Topline | done |
| 3 | Dials > Dock and Menu Bar: Automatically hide and show the menu bar | Dials | done |
| 4 | Guide: hiding the menu bar | Guide | done |

## 1.65 "reduce transparency" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Reduce transparency: the menu bar, the Dock, the switcher and notifications turn solid, at once | Dials, Topline, Pier, Tack, Beacon | done |
| 2 | Invert colours with Control-Option-Command-8, switched on in Dials > Accessibility | Dials, Strata | done |
| 3 | Guide: making the screen easier to see | Guide | done |

## 1.66 "login items" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Login Items: the apps that open at login, with + to add one from a searchable list and − to take one off | Dials | done |
| 2 | freemac's own apps (Quill, Chime and the rest) set to Open at Login now really open; before, they were skipped | Login items | done |
| 3 | Chime's alarm watcher keeps its own entry, apart from Chime as a login item | Chime | done |
| 4 | Guide: opening apps when you log in | Guide | done |

## 1.67 "reveal desktop" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Click the wallpaper and the windows on screen step aside; click it again to bring them back | Backdrop, Strata | done |
| 2 | Dials > Dock and Menu Bar: Click wallpaper to reveal desktop (off unless you turn it on) | Dials | done |
| 3 | Guide: revealing the desktop | Guide | done |

## 1.68 "conversions" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Seek converts units as you type: length, weight, volume and cooking measures, temperature, speed, time, data and area | Seek | done |
| 2 | An amount alone converts between metric and US units; "in" or "to" picks the unit | Seek | done |
| 3 | Guide: conversions in Search with Seek | Guide | done |

## 1.69 "content limits" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Logbook > Content: Limit adult websites, for every browser and everyone on the computer (Cloudflare for Families name lookups), behind an administrator's password and Logbook's passcode | Logbook | done |
| 2 | pkexec is now installed, so the administrator password prompt works for Users, Restart in Recovery and this | Build | done |
| 3 | Guide: Limit adult websites in screen time | Guide | done |

## 1.70 "the freemac menu" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The freemac menu in a Mac's order: About freemac, Settings…, Harbor…, Recent Items, Force Quit…, Sleep, Restart…, Shut Down…, Lock Screen, Log Out *name*… | Topline | done |
| 2 | Recent Items: the apps and documents used lately, with Clear Menu | Topline | done |
| 3 | Restart, Shut Down and Log Out ask "Are you sure…?" and go ahead by themselves after 60 seconds, as on a Mac (they used to happen at once, without asking) | Session | done |
| 4 | Before restarting, shutting down or logging out, every app is asked to quit, so it can offer to save; an app that stays open stops it and is named | Session | done |
| 5 | Shift-Command-Q logs out (asking first); Dials > Battery and Power's buttons ask the same way | Session, Dials | done |
| 6 | Guide: Restart, shut down or log out | Guide | done |

## 1.71 "updates and firewall" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Software Update: the freemac version, Check for Updates… (opens Harbor's Updates) and "Install important updates automatically" (security fixes in the background through unattended-upgrades), on by default | Dials | done |
| 2 | Dials > Network > Firewall: turns away connections other computers start (ufw), still letting printers and phones on the same network be found; off by default, as on a Mac | Dials | done |
| 3 | One root helper and polkit action for both switches, so each asks for an administrator's password | Build | done |
| 4 | freemac's own Software Update icon | Art | done |
| 5 | Guide: Keep the computer up to date and safe | Guide | done |

## 1.72 "which app opens what" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Dock and Menu Bar: Default web browser and Default email app, each a pop-up of the apps installed that can do it, with their icons | Dials | done |
| 2 | Drawer > Get Info: Open with shows the app that opens the document; pick another (or Other… for any app) and Change All… makes it open every document of that kind, after asking | Drawer | done |
| 3 | Get Info no longer opens with its Kind line highlighted | Drawer | done |
| 4 | Guide: Choose which app opens a file or link | Guide | done |

## 1.72.1 "power fix" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Restart, Shut Down and Log Out's question is now freemac-power: in 1.70 to 1.72 it shared its name with the program that starts the desktop, which came first, so choosing Restart… could start a second desktop instead of asking | Session, Build | done |
| 2 | The desktop's starter passes restart, shutdown, logout and sleep on to freemac-power, so a Shift-Command-Q set up by 1.70 to 1.72 still works | Build | done |

## 1.73 "read it to me" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Accessibility > Spoken Content: Speak selection, a voice and a speaking rate, with a Play button to try them | Dials | done |
| 2 | ⌥Esc reads the words selected in any app aloud, and stops when pressed again; the shortcut can be changed in Dials > Keyboard | Session | done |
| 3 | espeak-ng in the image | Build | done |
| 4 | Guide: Have the computer read words aloud | Guide | done |

## 1.74 "who's listening" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A small orange dot in the menu bar while any app is using the microphone, green while one is using the camera; click it to see which apps | Topline | done |
| 2 | Fixed: the volume, settings, clock and other icons on the right of the menu bar could ignore clicks when the bar started before it had its full width | Topline | done |
| 3 | Guide: See when an app is using the microphone or camera | Guide | done |

## 1.75 "your colour" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Appearance > Accent colour: a row of eight coloured circles; the choice colours selections, switches, sliders and default buttons in every app at once, in light and dark | Dials, Theme | done |
| 2 | A light and a dark GTK 3 theme, GTK 4 style sheet and Qt colour scheme for each accent | Theme, Build | done |
| 3 | The Dock, menu bar, Drawer, Seek and freemac's other apps take their highlight from the accent instead of a fixed blue | Shell | done |
| 4 | Guide: Change the look mentions the accent colour | Guide | done |

## 1.76 "plug me in" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Low-battery notices at 10% and 5% while on battery, once each per charge | Topline | done |
| 2 | At 2% the computer sleeps after 30 seconds' notice, unless it's plugged in first | Topline | done |
| 3 | The battery icon's tooltip shows the time left, or the time until full; clicking it opens Dials > Power | Topline | done |
| 4 | Dials > Power shows "On battery, 2:15 left" and gets Show percentage in the menu bar | Dials | done |
| 5 | Guide: Keep an eye on the battery | Guide | done |

## 1.77 "over here" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Share > Nearby… in Drawer, Cove and Frame: nearby computers and phones as round icons; click one to send, with Waiting, Sending, Sent or Declined under it, and a click to stop | Hail, Share | done |
| 2 | Receiving, off until turned on in the Nearby window or Dials > Network; every offer asks “Sam's Phone would like to share 3 photos” with Decline and Accept, and files land in Downloads with a notification | Hail, Dials | done |
| 3 | Speaks LocalSend's open protocol (v2, HTTPS), so phones and tablets with the free LocalSend app work too; folders keep their shape, names can't climb out of Downloads | Hail | done |
| 4 | Started at log in; the firewall lets it through from the local network only | Build | done |
| 5 | Guide: Send files to a computer or phone nearby | Guide | done |

## 1.78 "say cheese" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | ⇧⌘5 opens the Screenshot toolbar at the bottom of the screen: Entire Screen, Selected Window, Selected Portion, Record Entire Screen, Record Selected Portion, then Capture or Record; Return captures, Esc closes | Lens | done |
| 2 | Options: save to Desktop, Documents, Pictures or only the clipboard; a 5 or 10 second timer with a countdown; show the floating thumbnail or not. ⇧⌘3 and ⇧⌘4 follow the same choices | Lens | done |
| 3 | ⇧⌘5 during a recording stops it; recording a part of the screen keeps Ctrl+Shift+Print | Lens, Build | done |
| 4 | Guide and Dials > Keyboard list the new shortcut | Guide, Dials | done |

## 1.79 "what's my name" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Sharing: Computer name, changed after an administrator's password; nearby devices see it, and other computers reach this one at its-name.local | Dials, Build | done |
| 2 | Nearby sharing's switch on the same page, and Hail calls the computer by its name | Dials, Hail | done |
| 3 | Remote Login (SSH), off unless turned on: each computer makes its own keys, the firewall lets it through from the local network only, and the page says what to type on the other computer | Dials, Build | done |
| 4 | Guide: Rename this computer, or log in to it from another | Guide | done |

## 1.80 "parlez-vous" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Keyboard > Input Sources: the layouts you type with, by name, added from a searchable list of every language and layout, up to four, and taken off with − | Dials | done |
| 2 | The input menu in the menu bar (US, GB, DE…) shows the layout in use and switches to another; Control-Space goes to the next, without catching Control-Command-Space | Topline, Strata | done |
| 3 | Key repeat rate and Delay until repeat sliders | Dials | done |
| 4 | Guide: Type in another language or keyboard layout | Guide | done |

## 1.81 "spellbound" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Check spelling while typing: misspelled words underlined in red in Jot, Post, Stickies, Quill's plain text and Markdown, and the notes in Tide, Nudge, Crew, Corkboard and Lantern | Apps | done |
| 2 | Right-click a misspelled word for suggestions, Ignore All, Add to Dictionary and the language to check in (U.S., British, Canadian, Australian English) | Apps, Build | done |
| 3 | Dials > Keyboard > Text Input: one switch for every app | Dials | done |
| 4 | Guide: Check your spelling as you type | Guide | done |

## 1.82 "omw" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Text Replacements: type a short form and a space and it becomes the long one (omw: On my way!); a list to add to in Dials > Keyboard | Apps, Dials | done |
| 2 | Smart quotes and dashes as you type: “ ” ‘ ’ and — for two hyphens, not in Quill's code | Apps | done |
| 3 | A full stop when you press the space bar twice | Apps | done |
| 4 | Guide: Type less with text replacements | Guide | done |

## 1.83 "knock knock" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Connect to Server (Go menu, ⌘K): type smb://, sftp://, ftp:// or a WebDAV address, or just a computer's name, sign in if asked, and it opens like a drive | Drawer | done |
| 2 | Favourite Servers in the same window, with + and − | Drawer | done |
| 3 | Connected servers under Locations with an Eject button; gvfs-fuse so every app can open their files | Drawer, ISO | done |
| 4 | Guide: Open a shared folder on another computer | Guide | done |

## 1.84 "who's there" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Network under Locations and in the Go menu (⇧⌘K): the computers and shared drives on the local network, appearing as they're found | Drawer | done |
| 2 | Open one to connect, signing in if it asks; Connect and Connect to Server… on right-click | Drawer | done |
| 3 | Errors name the computer ("There was a problem connecting to the server “Kids PC”…") | Drawer | done |

## 1.85 "open house" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | File Sharing in Dials > Sharing: share your Public folder, read-only and with no password, with the other computers on the network (Windows, Mac and freemac) | Dials, system helper | done |
| 2 | Open Public Folder button while it's on; the firewall lets it through to the local network only | Dials, system helper | done |
| 3 | A computer in Network that shares several folders lists them; hidden admin shares (print$, C$) stay hidden | Drawer | done |
| 4 | A folder shared for everyone opens as a guest without a password dialog, and is titled by its own name | Drawer | done |

## 1.86 "porthole" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Screen Sharing in Dials > Sharing: someone at another computer on the network can see and use this screen, after signing in with your name and password; an account without a password can't turn it on | Dials, system helper | done |
| 2 | Always encrypted, with the computer's own certificate made the first time; the firewall lets it through to the local network only | Screen Sharing | done |
| 3 | An icon in the menu bar while someone is using the screen, saying who, with Disconnect | Topline | done |
| 4 | Porthole, the viewer: type a computer's name, sign in, and see and use its screen; recent computers, Fit to Window, full screen, Send Control-Alt-Delete | Porthole | done |
| 5 | Porthole remembers each computer's identity and warns if it changes | Porthole | done |
| 6 | vnc:// addresses in Connect to Server open Porthole | Drawer | done |

## 1.87 "smart folders" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Search This Mac from a Drawer window's toolbar: every file and folder in your home whose name matches, then documents whose words match, as they're found | Drawer | done |
| 2 | A scope bar while searching: This Mac or the folder you're in, a kind (Documents, PDF, Images, Music, Movies, Folders) and when it last changed; kind and date work without any words | Drawer | done |
| 3 | Save a search as a Smart Folder under Smart Folders in the sidebar; it looks again each time it opens, and changing one and pressing Save updates it | Drawer | done |
| 4 | File > New Smart Folder (⌥⌘N), Edit > Find (⌘F) and Save Search; Remove Smart Folder on its right-click menu, which leaves the files alone | Drawer | done |
| 5 | The sidebar scrolls when its places, Smart Folders and tags don't fit | Drawer | done |

## 1.88 "spotlight settings" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Seek: a switch for each kind of result Seek lists (apps, sums and conversions, settings, Guide, menu items, contacts, events, reminders, files, words inside documents), counted the moment it's flipped | Dials, Seek | done |
| 2 | Privacy: + and − keep folders out of Seek, its index of words inside documents and Drawer's This Mac searches and Smart Folders | Dials, Seek, Drawer | done |
| 3 | Turning off Words inside documents forgets what Seek had read; Rebuild Index reads them all again | Dials, Seek | done |
| 4 | Seek is on Dials' View menu and found by searching Dials or Seek for "spotlight", "privacy" or "index" | Dials | done |

## 1.89 "downtime" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Downtime in Logbook: hours of each day (overnight too) when only Always Allowed apps can be used; other apps close when brought to the front, with a notice five minutes before it starts | Logbook | done |
| 2 | Always Allowed: + and − to choose apps that work in downtime and have no daily limit; freemac's own Drawer, Dials, Guide and Logbook always work | Logbook | done |
| 3 | 15 More Minutes: on an app whose time is up, and to hold off downtime for a while | Logbook | done |
| 4 | The passcode guards downtime, Always Allowed and more time as well as limits | Logbook | done |

## 1.90 "guest" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Guest User: a switch in Dials > Users makes an account anyone can log in to without a password | Dials, users helper | done |
| 2 | Everything a guest does is erased when they log out, and again before the next guest logs in; no Welcome for the guest | freemac-session | done |
| 3 | Gangway shows the Guest User with no password box, just the arrow | Gangway | done |
| 4 | Fix: the login screen came back black after logging out, because the greeter couldn't open the seat | Image | done |

## 1.91 "sound effects" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Alert sounds: Pebble, Droplet, Knock, Chirp, Bell and Hum, all made from scratch, and an alert volume, in Dials > Sound | Dials, art | done |
| 2 | Every GTK app's alert (a Backspace with nothing to delete) plays the alert sound; Wayfire made none | Strata | done |
| 3 | Play feedback when volume is changed: a pop at the new level | freemac-keys, Topline | done |
| 4 | Play user interface sound effects: a crumple when the Trash is emptied, a shutter for a screenshot | Drawer, Pier, Lens | done |

## 1.92 "displays" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Displays lists each display by name and size, with its Resolution (every size it can show, or Default) and Refresh rate | Dials, Strata | done |
| 2 | Size of text and icons and Rotation (Standard, 90°, 180°, 270°) for each display | Dials | done |
| 3 | "Keep these display settings?" after a new resolution, refresh rate, rotation or mirroring; the old settings come back after 15 seconds | Dials | done |
| 4 | With two or more displays: drag them into place in a picture of the desk, where they snap together, and Use as Extended display or Mirror for another | Dials | done |

## 1.93 "main display" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The menu bar, the Dock and the files on the Desktop sit on the main display, and move when it changes or is unplugged (the built-in display first, then the first one) | Topline, Pier, Backdrop | done |
| 2 | Choose the main display in Dials > Displays: Use as Main display, or drag the white bar in the picture to another display | Dials | done |

## 1.94 "screen flash" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Flash every display white for a moment, through Strata's IPC method strata/flash | Strata | done |
| 2 | Flash the screen when an alert sound occurs, in Dials > Accessibility, even with the alert sound turned down; Test Screen Flash shows how it looks | Dials, freemac-sound | done |

## 1.95 "green button" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Rest the pointer on a window's green button for a menu: left, right, top and bottom halves, the four quarters, Fill, Centre, Left & Right with the window used before it, and Return to Previous Size | Topline | done |
| 2 | Strata's own title bars say when the pointer rests on the green button; Strata tells where the pointer is and which window is under it (strata/pointer) | Strata | done |
| 3 | A GTK 3 module so the green buttons that GTK apps draw themselves open the same menu | Strata, session | done |

## 1.96 "shake to find the pointer" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Shake the mouse quickly back and forth and the pointer grows big for a moment, so it's easy to find | Strata | done |
| 2 | Shake mouse pointer to locate, on by default, in Dials > Accessibility | Dials | done |

## 1.97 "press and hold for accents" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Hold a letter such as e in a text field and a small panel by the text cursor offers è é ê ë ē ė ę; a number key, a click, or the arrows and Return pick one, and Shift gives capitals | Strata, Topline | done |
| 2 | freemac-im, a quiet input method, so apps say which text field has the keyboard and where its cursor is | Strata | done |
| 3 | Press and hold for accents, on by default, in Dials > Keyboard, and a Guide topic | Dials, Guide | done |

## 1.98 "sticky keys" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Sticky Keys: tap Shift, Control, Option or Command and it stays down for the next key; tap twice to lock it, once more to let it go | Strata | done |
| 2 | Press Shift five times to turn Sticky Keys on or off, with a notice on screen | Strata, Topline | done |
| 3 | The modifiers that are set show in the top-right corner, with a soft click as each one is set | Topline | done |
| 4 | Sticky Keys, its Shift shortcut, the click and the symbols in Dials > Accessibility, and a Guide topic | Dials, Guide | done |

## 1.99 "colour filters" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Colour filters for the whole screen: greyscale, red/green (protanopia), green/red (deuteranopia), blue/yellow (tritanopia) and a colour tint | Strata | done |
| 2 | An intensity slider and a tint colour, in Dials > Accessibility, and a Guide topic | Dials, Guide | done |

## 1.100 "background sounds" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Six background sounds made at build time: balanced, bright and dark noise, ocean, rain and a stream, each a seamless loop at the same level | Art | done |
| 2 | Topline plays the chosen one steadily behind everything else, at its own volume | Topline | done |
| 3 | Background sounds, its sound and volume in Dials > Accessibility, and a Guide topic | Dials, Guide | done |

## 1.101 "sunset" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Sunrise and sunset where you are, from the time zone's city, with no location service | Shell | done |
| 2 | Auto appearance: light while the sun is up, dark after it sets, in Dials > Appearance beside Light and Dark | Dials, Topline | done |
| 3 | Night Light's schedule: Sunset to Sunrise or Custom hours | Dials | done |
| 4 | Guide topics for Auto and Night Light | Guide | done |

## 1.102 "drawer settings" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Drawer > Settings… (⌘,) with General and Advanced | Drawer | done |
| 2 | Choose the folder new Drawer windows open in | Drawer | done |
| 3 | Turn off the warning before emptying the Trash, in Drawer and the Dock | Drawer, Dock | done |
| 4 | Remove items from the Trash after 30 days | Drawer, Topline | done |
| 5 | Keep folders on top when sorting, or mix them in | Drawer | done |
| 6 | A Guide topic | Guide | done |

## 1.103 "keep awake" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The screen stays on and doesn't lock while something asks (Strata `strata/keep-awake`) | Strata | done |
| 2 | Apps can ask the usual Linux way (org.freedesktop.ScreenSaver and PowerManagement Inhibit) | Latch | done |
| 3 | Reel keeps the screen on while a video plays | Reel | done |
| 4 | `caffeinate`, with -t, -w and a command to run, as on a Mac | Terminal | done |
| 5 | Dials > Power shows what is keeping the screen on | Dials | done |
| 6 | A Guide topic | Guide | done |

## 1.104 "pointer colours" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Pointer outline colour and Pointer fill colour, with Reset | Dials | done |
| 2 | freemac's pointer drawing takes colours, and stays in the image for Dials | Art | done |
| 3 | The big pointer a shake shows uses the same colours | Strata | done |
| 4 | A Guide topic | Guide | done |

## 1.105 "picture in picture" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Picture in Picture: the video in a small window above the others, in the corner, playing on | Reel | done |
| 2 | Drag the picture anywhere; double-click or Esc puts it back as it was | Reel | done |
| 3 | A window held above the others isn't remembered as the app's size | Strata | done |
| 4 | Reel's controls fit its smallest window | Reel | done |
| 5 | README screenshots retaken, with Picture in Picture added | Docs | done |
| 6 | A Guide topic | Guide | done |
| 7 | Dials' sidebar scrolls, so the window fits an 800-pixel-high screen with every pane listed | Dials | done |

## 1.106 "dynamic wallpaper" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dynamic wallpaper: the scene follows the sun where you are, fading into its night version through twilight | Backdrop | done |
| 2 | A warm, golden light on the picture as the sun sets and rises | Backdrop | done |
| 3 | The sun's height above the horizon, from the time zone's city | sun.py | done |
| 4 | Dynamic switch in Dials > Wallpaper, found by searching "dynamic" or "sunset" | Dials | done |
| 5 | A Guide line, and README screenshots retaken | Guide, Docs | done |

## 1.107 "stage manager" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Stage Manager: one app in the middle, the others hidden as pictures in a strip down the left | Pier (stage.py) | done |
| 2 | Click a picture, the app's Dock icon or ⌘Tab to swap the app on the stage | Pier | done |
| 3 | A window under the strip moves beside it as its app comes forward | Pier | done |
| 4 | Stage Manager tile in Quick Settings, and a switch in Dials > Dock and Menu Bar | Quick Settings, Dials | done |
| 5 | Turning it off brings back every window it hid; what it hid survives a restart of the Dock | Pier | done |
| 6 | A Guide topic, a README screenshot, and every README screenshot retaken | Guide, Docs | done |

## 1.108 "mission control" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The window overview (Control+Up) names the desktops along the top of the screen | Strata (mission-control.hpp), Topline (spaces.py) | done |
| 2 | Move the pointer up and the row opens out into pictures of each desktop: its wallpaper and its windows | Topline | done |
| 3 | Click a desktop to leave the overview and go there, with its front window active | Strata | done |
| 4 | `strata/desktops` lists the desktops and the windows on each | Strata | done |
| 5 | A window remembered at the top of the screen reopens below the menu bar, title bar and all | Strata (window-places.hpp) | done |
| 6 | A Guide topic, a README screenshot, and every README screenshot retaken | Guide, Docs | done |

## 1.109 "drag to a desktop" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | In the window overview, drag a window up onto one of the desktops along the top and let go to move it there | Strata (mission-control.hpp) | done |
| 2 | The window being dragged shrinks as it nears the row, so the desktops stay in sight | Strata | done |
| 3 | The row opens out a little before the pointer reaches the names | Topline (spaces.py) | done |
| 4 | Picture in Picture turned on just after Reel opens stays in its corner (the window's remembered place no longer pulls it back) | Strata (window-places.hpp) | done |
| 5 | Guide line, README row, every README screenshot retaken | Guide, Docs | done |

## 1.110 "add and close desktops" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A + at the right end of Mission Control's opened row adds a desktop (up to 16) | Strata (mission-control.hpp), Topline (spaces.py) | done |
| 2 | Drag a window onto + to give it a desktop of its own | Strata | done |
| 3 | A round button on the corner of the desktop under the pointer closes it; its windows go to Desktop 1 and the overview stays open | Strata, Topline | done |
| 4 | The number of desktops is kept in wayfire.ini for the next login | Topline | done |
| 5 | Guide lines, README row, every README screenshot retaken | Guide, Docs | done |

## 1.111 "assign to a desktop" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dock > Options > Assign To: All Desktops, This Desktop (or the desktop it's assigned to, ticked) and None, while the app has a window | Pier | done |
| 2 | All Desktops: the app's windows show on every desktop | Strata (mission-control.hpp) | done |
| 3 | This Desktop: the app's windows move there, new ones open there and take you there | Strata | done |
| 4 | Kept in ~/.config/freemac/desktop-assignments; closing a desktop moves the later ones' assignments along and drops its own | Strata | done |
| 5 | Guide line, README row, every README screenshot retaken | Guide, Docs | done |

## 1.112 "app exposé" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Ctrl+Down (or a four-finger swipe down) spreads out every window of the app in front, and nothing else; again, Esc or a click closes it | Strata (mission-control.hpp) | done |
| 2 | Dock > Show All Windows does the same for that app | Pier | done |
| 3 | Show all desktops moves to Ctrl+Option+Down; Dials > Keyboard and Gestures list both | Dials, wayfire.ini | done |
| 4 | Guide line, README row and shortcut, every README screenshot retaken | Guide, Docs | done |

## 1.113 "full screen gets its own desktop" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A window put in full screen (green button, Control+⌘F or the app itself) slides onto a new desktop of its own at the end of the row | Strata (mission-control.hpp) | done |
| 2 | Out of full screen, or closed, it goes back to the desktop it came from and its desktop goes away | Strata | done |
| 3 | Mission Control names that desktop after the app and numbers the others without it; its corner button shows two arrows and leaves full screen | Topline (spaces.py), Strata | done |
| 4 | These desktops are never saved for the next login | Strata, Topline | done |
| 5 | Guide lines, README row, every README screenshot retaken | Guide, Docs | done |

## 1.114 "mission control on an empty desktop" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Control+Up (or a four-finger swipe up) on a desktop with no windows opens the row of desktops on its own, already opened out | Strata (mission-control.hpp), Topline (spaces.py) | done |
| 2 | Click a desktop to go there; Esc, a click away or Control+Up again closes the row | Strata | done |
| 3 | + and the corner buttons work there as in the full overview | Strata, Topline | done |
| 4 | Guide line, README row, every README screenshot retaken | Guide, Docs | done |

## 1.158 "Bluetooth menu" (done)

The menu bar's Bluetooth menu, as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Click the Bluetooth symbol in the menu bar for its menu: a switch that turns Bluetooth on or off | Topline, bluetooth_menu.py | done |
| 2 | Devices: the paired headphones, keyboards and mice, connected ones first with a blue symbol and their battery when they report it | bluetooth_menu.py | done |
| 3 | Click a device to connect or disconnect it, with a spinner while it works and a notification, in plain words, when it can't connect | bluetooth_menu.py | done |
| 4 | Bluetooth Settings… opens Dials > Bluetooth, as a click did before; a computer with no Bluetooth still shows no symbol | bluetooth_menu.py, status.py | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.262 "IINA plays video" (done)

Ferry 0.85.0: IINA 1.3.5, the video player written in Swift, runs from its official download and plays a video, picture and sound, in its own player window. It's the second app picked because it looked likely not to work: a large Swift app built on mpv and FFmpeg. Ferry gained what it was missing: more of the Swift additions a Mac's Foundation makes (`Data` and its protocols, `CharacterSet`, `IndexSet`, `URLRequest`, `CocoaError` and `URLError`, string methods), the Mac's shape of `DispatchQueue`, VideoToolbox (no hardware codecs, so FFmpeg decodes in software), picture in picture, ColorSync and power-source calls, window aspect ratios and drags, and gesture recognizers. A Swift object watched with key-value observing no longer crashes, and Swift's array storage is saved in archives as a plain array, as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Swift overlays: `Data` and `DataProtocol` (from the open-source swift-foundation), the bridged value types, `CocoaError` and `URLError`, more `String` methods, `DispatchQueue` made with a label, for-in over `NSArray` | Ferry Swift | done |
| 2 | Key-value observing a Swift class: the observing subclass copies Swift's class data; instance variables keep the place realizing gave them | Ferry runtime | done |
| 3 | VideoToolbox, served from AppKit: sessions fail as a missing codec does, so FFmpeg goes on in software | Ferry AppKit | done |
| 4 | Picture in picture (`PIPViewController`): a small floating window that keeps the app's view, closed through the app's delegate | Ferry AppKit | done |
| 5 | Window aspect ratios, window drags, gesture recognizers (kept, not yet fired), `NSValue` with `CMTime` | Ferry AppKit | done |
| 6 | ColorSync's device profiles (none), power sources from this system's batteries, IOKit notification ports | Ferry | done |
| 7 | A system framework found by bundle identifier, so mpv finds OpenGL's functions | Ferry Foundation | done |
| 8 | Swift's private storage classes archive and unarchive as `NSArray` and the like | Ferry Foundation | done |
| 9 | IINA 1.3.5 opens a video and plays it | Ferry / IINA | done |

## 1.261 "Swift apps run from the download" (done)

Ferry 0.84.0: Swift's runtime and Ferry's Swift modules are now in Ferry's package, so they're on every freemac computer. Until now they were built only on the computers Ferry is made on, so a Mac app written in Swift (Rectangle, TomatoBar, apps made with SwiftUI) started there and nowhere else. The release now builds them from the open-source Swift project's source, as `swift/build-runtime.sh` always has, and the package puts them where Ferry looks. The runtime's build had stopped working with a recent change to Ferry's SDK headers; that's fixed.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `packaging/build-swift.sh`: fetches a swift.org toolchain and Swift's source, builds the runtime and Ferry's Swift modules | Ferry packaging | done |
| 2 | The release builds them before Ferry's package; the package carries them in /usr/lib/ferry/frameworks/swift | release, Ferry packaging | done |
| 3 | `sys/resource.h` brings in `id_t`, so the runtime builds again | Ferry SDK | done |
| 4 | Rectangle 0.87 starts from the installed package alone | Ferry / Rectangle | done |

## 1.260 "Rectangle starts" (done)

Ferry 0.83.0: Rectangle 0.87, the window-snapping app, runs from its official download, not built for Ferry: a Swift app with a main storyboard, the first of the apps picked because they looked likely not to work. Ferry now opens an app's compiled storyboard (its scenes, view controllers and the nibs inside them) and starts the app from it. Swift code built on a Mac finds what Apple's Swift overlays give it: the Mac's shapes of `DispatchQueue`, `os_log` and `OSLog`, `Locale`, `TimeZone`, `URLComponents`, `Notification` and the other Foundation value types, `NSNumber` conversions, the OS version check and image literals. Objective-C code's `os_log` calls are read as clang packs them. Labels in a nib wrap as the nib says, where before a flag was misread and their text was cut off.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSStoryboard`: a compiled storyboard's scenes, controllers by identifier, the initial controller, the main menu, and an app started from `NSMainStoryboardFile` | Ferry AppKit | done |
| 2 | Swift overlays with the Mac's shapes: Dispatch's queue, group and semaphore classes; `os_log` and `OSLog`; a CoreFoundation module; Foundation's value types, `NSNumber` conversions, `Date` and `URL` strings; `CGRect` from a dictionary; image literals | Ferry Swift | done |
| 3 | `_os_log_impl` (clang's packed values), `_swift_stdlib_operatingSystemVersion` and the OS version check Swift calls | Ferry | done |
| 4 | Accessibility window ids, pointer warping (refused, as Wayland refuses it), haptic feedback (does nothing) | Ferry AppKit | done |
| 5 | Nib text fields wrap as their cell's line-break mode says | Ferry AppKit | done |
| 6 | Rectangle 0.87 starts and shows its "Authorize Rectangle" window | Ferry / Rectangle | done |

## 1.259 "OBS quits cleanly with a camera" (done)

Ferry 0.82.0: OBS Studio's Legacy camera source no longer crashes OBS when it quits. Posting a notification kept the object it was about until the posting thread's autorelease pool drained, and OBS loads its scenes in a pool it never drains, so a capture session that OBS let go of kept running and handed pictures to a source OBS had already freed. A notification is now let go of as soon as it has been posted, as on a Mac. A capture session that its app lets go of while it runs stops, and pictures already on their way to a delegate aren't handed over once it has stopped.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Posted notifications released at once, not autoreleased; `-[NSNotification initWithName:object:userInfo:]` | Ferry Foundation | done |
| 2 | A running capture session stops when its app lets go of it; pictures queued for a delegate dropped after stop | Ferry AVFoundation | done |
| 3 | OBS's Legacy camera source previews, records at 30 fps and quits cleanly on the test camera | Ferry / OBS | done |
| 4 | Tests: `foundation_runloop`, `appkit_avcapture_camera` | Ferry | done |

## 1.258 "OBS's camera source builds" (done)

Ferry 0.81.0: the last calls OBS Studio's camera plugin uses that Ferry didn't have: a camera's video effects (Portrait, Center Stage, Studio Light, reactions and background replacement, all off), Core Media's rounding methods for converting a time to another scale, the names of older and professional video codecs, and sorting a dictionary's keys by value with a block. The OpenGL module (and the CoreVideo and AppKit modules that bring it in) now builds on a system whose OpenGL headers weren't installed when Ferry was built.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | AVCaptureDevice video-effect properties, instance and class | Ferry AVFoundation | done |
| 2 | `CMTimeRoundingMethod` and exact rounding in `CMTimeConvertScale` | Ferry CoreMedia | done |
| 3 | Codec types: Animation, Cinepak, Sorenson, H.263, MPEG-1 and 2, DV and DVCPRO HD, ProRes 4444 and 422 HQ/LT/Proxy, VP9, AV1 | Ferry CoreMedia | done |
| 4 | `keysSortedByValueUsingComparator:` and `keysSortedByValueWithOptions:usingComparator:` | Ferry Foundation | done |
| 5 | OpenGL module without the system's OpenGL headers | Ferry SDK | done |
| 6 | Tests: `appkit_avcapture_camera`, `screencapture_coremedia`, `foundation_collections` | Ferry | done |

## 1.257 "Mac apps see your camera" (done)

Ferry 0.80.0: a Mac app now sees the PC's webcams through AVFoundation, as on a Mac. AVCaptureDevice lists each camera with its formats and frame rates, and a capture session hands its pictures to the app in the pixel format the app asks for (the camera's own, 32BGRA, 420v or yuvs), at the size its preset or chosen format sets. Cameras plugged in or taken out are noticed while the app runs. Camera access goes by what the user said in Dials, Privacy & Security, Camera. This is what OBS Studio's camera source needs, and the last piece before its "Video Capture Device" works.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The PC's cameras (V4L2): list, formats, rates, start, frames, Motion JPEG through libturbojpeg; a test camera with FERRY_CAMERA_TEST=1 | Ferry (camera.c) | done |
| 2 | AVCaptureDevice formats, frame rates, device types, discovery sessions, plug-in and unplug notifications | Ferry AVFoundation (AVCaptureDevice.m) | done |
| 3 | AVCaptureSession, AVCaptureDeviceInput and AVCaptureVideoDataOutput with presets and pixel format conversion into IOSurface-backed pixel buffers | Ferry AVFoundation (AVCaptureSession.m) | done |
| 4 | CoreMediaIO's system object, which OBS's camera plugin sets as it starts | Ferry CoreMediaIO | done |
| 5 | `@import` for CoreMedia, CoreMediaIO, CoreVideo, MediaPlayer, OpenGL, ScreenCaptureKit and AddressBook | Ferry SDK | done |
| 6 | New test `appkit_avcapture_camera` | Ferry | done |

## 1.256 "Layers blend as the app asks" (done)

Ferry 0.79.0: a Mac app's Core Animation layer with a blend mode as its compositing filter (multiply, screen, overlay, plus lighter and the rest) is now blended with what is under it, as on a Mac. Tinted overlays, glows and darkened artwork drew as plain opaque layers before. AppKit's notes on stderr that are whole sentences no longer get "isn't supported yet" stuck on the end.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `compositingFilter` blend modes by Core Animation's and Core Image's names, the layer blended as one at its opacity | Ferry QuartzCore (QRender.m) | done |
| 2 | Whole-sentence notes said as they are (menus with no session bus, a status item's menu) | Ferry AppKit | done |
| 3 | New test `quartzcore_layer_blend_modes` | Ferry | done |

## 1.255 "Sprites and stretchable pictures in layers" (done)

Ferry 0.78.0: a Mac app's Core Animation layers now draw only the part of their image the app asks for, and stretch a picture in nine parts. Sprite sheets and film strips showed the whole sheet before, and buttons, bubbles and panels built from one small picture had their rounded corners stretched out of shape; now they draw as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `contentsRect` picks the part of a layer's image that is drawn, in the layer's own unit space | Ferry QuartzCore (QRender.m) | done |
| 2 | `contentsCenter` stretches the image in nine parts, keeping its corners' size, at the image's `contentsScale` | Ferry QuartzCore | done |
| 3 | New test `quartzcore_layer_contents_parts`, checked pixel by pixel | Ferry | done |

## 1.254 "Layers keep to their masks" (done)

Ferry 0.77.0: a Mac app's Core Animation layer masks are now drawn. A round profile picture, a faded list edge or a shape cut out with a mask layer showed whole before; now the layer shows only where its mask is opaque, as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A layer, its sublayers and border show only where the mask layer, placed by its frame, is opaque, and as far as it is | Ferry QuartzCore (QRender.m) | done |
| 2 | A shape layer masks by its path, and the shadow is cast by what the mask leaves | Ferry QuartzCore | done |
| 3 | New test `quartzcore_layer_masks`, checked pixel by pixel | Ferry | done |

## 1.253 "Layers cast their shadows" (done)

Ferry 0.76.0: a Mac app's Core Animation layers now draw their shadows. Cards, popovers, buttons and panels that an app gives a soft shadow with `shadowOpacity`, `shadowRadius` and `shadowOffset` showed flat before; now they cast the shadow a Mac draws, from the layer's own shape, or from its `shadowPath`.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A layer casts its shadow from all it draws taken as one, in its colour at its opacity, moved and blurred as on a Mac, faded with the layer's opacity | Ferry QuartzCore (QRender.m) | done |
| 2 | A shadow path's whole shadow is drawn under the layer instead | Ferry QuartzCore, Core Graphics | done |
| 3 | New test `quartzcore_layer_shadows`, checked pixel by pixel | Ferry | done |

## 1.252 "An app's own options in the file chooser" (done)

Ferry 0.75.0: a Mac app can add its own controls under an Open or Save panel, most often a Format menu in a Save panel. The file chooser freemac shows is the system's own, which can't hold an app's view, so these were left out. Now the accessory view's pop-up menus and check boxes show in the chooser as its own choices, named by the label beside each menu ("Format") or the check box's title. What is chosen goes back to the app as if its own controls were clicked, before the file is taken, so a Format menu that changes the file type gives the saved file its new extension (picture.png saved as JPEG is picture.jpg), as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | An accessory view's enabled pop-up menus (their items that can be chosen) and check boxes become the chooser's choices, a menu named by the label on its left | Ferry AppKit (NSSavePanel.m) | done |
| 2 | Each changed choice goes back into its control as a click would: the selection, the control's bindings and its action, before the chosen file is checked and taken | Ferry AppKit | done |
| 3 | A Save panel's name keeps no extension of a type allowed before the format changed: it is replaced by the new type's | Ferry AppKit | done |
| 4 | With no display, FERRY_PANEL_CHOICES answers the choices; new test `appkit_panel_accessory` | Ferry | done |

## 1.251 "Auto Layout keeps the rule broken furthest" (done)

Ferry 0.74.0: when a window's layout breaks several rules of one priority, Auto Layout now holds the one broken furthest first, as a Mac's solver in effect does by keeping the total error down. Holding whichever came first could leave a much bigger one broken for good: a view with a minimum width of 50, a minimum of 100 and a maximum of 90 at one priority came out 50 wide, 50 points short, where a Mac makes it 90 to 100 wide, 10 short.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The next inequality held is the one broken furthest at the highest priority any broken one has, the first in order on a tie | Ferry AppKit (NSLayoutConstraint.m) | done |
| 2 | A test of minimums and a maximum at one priority, in either order, and of sliders as tall as the tallest minimum | tests/appkit/equal_priority.m | done |

## 1.250 "Buttons line up as on a Mac" (done)

Ferry 0.73.0: Auto Layout now lines up what a Mac lines up, a view's alignment rect, not its frame. A push button is drawn as a 22-point bezel inside a 32-point frame, and a Mac app's window spaces its buttons by their bezels; Ferry spaced them by their frames, 10 points too tall each, so a tightly laid-out window squeezed its buttons (VLC's Open dialog drew its Browse button 3 pixels tall). Buttons now sit where the window's design puts them, with their frames the size a nib gives them.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The solver works in alignment rects: a view's place, its size and its intrinsic size are its frame less its alignmentRectInsets, and the frame it sets is the one round the rect it solved, for a view with no subviews of its own | Ferry AppKit (NSLayoutConstraint.m) | done |
| 2 | A regular rounded push button's alignment rect is its bezel: 5 points in at the top and bottom and 6 at the sides of its frame; Ferry's own controls' intrinsic sizes, given as frames, are taken less their insets, an app's own as they are | Ferry AppKit (NSControl.m) | done |
| 3 | A test of a label and two buttons spaced by their bezels and an app's own view with insets | tests/appkit/alignment_rects.m | done |

## 1.249 "Ported programs link as on a Mac" (done)

Ferry 0.72.0: a program built with Ferry's SDK can ask for the maths, dynamic-loading, threads and C libraries by name (-lm, -ldl, -lpthread, -lc), as builds ported from other systems do, and gets libSystem for each, as a Mac's SDK gives it. Before, each of those stopped the build at the link.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | libm.tbd, libdl.tbd, libpthread.tbd and libc.tbd in the SDK, each libSystem, made and installed with it | Ferry SDK (Makefile) | done |
| 2 | A test program built with all four links and runs | tests/run.sh (sdk_std_libs) | done |

## 1.248 "Fonts for Mac apps" (done)

Ferry 0.71.0: a Mac app that looks for fonts in a Mac's Fonts folders now finds this computer's fonts there. OBS Studio's Text source lists them, so a font picked in its Select font window shows the text in the preview and the recording, where before it found no fonts and drew nothing.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The Fonts folder of each Library folder Ferry gives (the user's, the computer's and the system's), and the Mac's own ~/Library/Fonts, /Library/Fonts and /System/Library/Fonts, list every font file in this system's matching fonts folder and the folders in it, flat and by name | Ferry libSystem (fonts.c) | done |
| 2 | Opening, stat, lstat, access and listing a font there all reach the font itself, through a folder of links Ferry keeps in the user's cache and makes again when fonts are added or removed; a real Fonts folder is left as it is | Ferry libSystem (fonts.c, posix.c, stdio.c) | done |
| 3 | Checked with OBS opened in a fresh account: a Text (FreeType 2) source with FreeSans picked shows its text in the preview | Acceptance, tests/foundation/mac_fonts.m | done |

## 1.247 "Mac apps open on screen" (done)

Ferry 0.70.0: a Mac app's window that asks to be taller than the screen, as OBS Studio's does the first time it opens (960 points on a 900-point screen), now fits the screen with its title bar showing, instead of opening with its top and title bar above the screen where you can't reach them. A window placed above the top of the screen comes down, as a Mac puts it.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A titled window put on screen keeps its title bar on screen: one whose top is above the screen's visible top comes down, and a resizable one taller than the screen is made to fit it; a fixed-size one keeps its size | Ferry AppKit (NSWindow.m) | done |
| 2 | The fit happens when the window is ordered front, with or without a display, so it is tested headless | Ferry AppKit (NSWindow.m), tests/appkit/qt_popups.m | done |
| 3 | Checked with OBS opened for the first time in a fresh account: its main window is 1280x900 at the top of the screen | Acceptance | done |

## 1.246 "OBS records the screen from its download" (done)

Ferry 0.69.0: OBS Studio, downloaded from its own site and opened in a fresh account, now gets all the way to a recording. Its drop-down lists open, so you can pick the display in a macOS Screen Capture source's Properties, and the preview shows the screen at once; Start Recording then saves a movie of it with sound. Its right-click and + menus stay open until you choose, instead of closing the moment they appear, and those pop-up menus no longer take the keyboard or show up in the Dock.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A window that can't become key (a Qt pop-up menu, a tooltip) takes no focus and stays off the Dock's list; the key window waits a turn before resigning, and doesn't when focus went to one of the app's pop-ups, so Qt's menus no longer close as they open | Ferry AppKit (NSWindow.m, gtk.h) | done |
| 2 | NSPopUpButtonCell's performClickWithFrame:inView: tracks its menu until it closes, the choice made, before it returns, as on a Mac: Qt's lists open their menus this way | Ferry AppKit (NSPopUpButton.m) | done |
| 3 | A number read as a pointer gives its value, as OBS reads a screen's number; menu waits wake now and then, so a menu closed by a timer ends them | Ferry Foundation (NSValue.m), AppKit | done |
| 4 | README screenshot of OBS capturing and recording the screen | Docs | done |

## 1.245 "Mac apps in light and dark" (done)

Ferry 0.68.0: Mac apps follow freemac's appearance, as on a Mac. When Dials > Appearance is Dark, or Auto after sunset, a Mac app that knows dark mode opens dark: its windows, text, lists, sidebars and controls take dark colours, and Qt apps such as OBS and VLC read the same. Switch the appearance while the app is open and it changes with everything else, at once. An app that says it needs the light look, or was built before macOS had dark mode, stays light as it would on a Mac, and one that picks its own appearance keeps it.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A Mac app's appearance is freemac's, read from the desktop's colour scheme and followed while it runs; apps that need the light look (NSRequiresAquaSystemAppearance, or built with an SDK before 10.14) stay light | Ferry AppKit (AppKitMore.m) | done |
| 2 | The system colours (labelColor, windowBackgroundColor, textBackgroundColor, controlColor, the sidebar and table colours and the rest) have dark values and are drawn in the appearance of the view, its window or the app; colorWithName:dynamicProvider: asks its provider for each appearance | Ferry AppKit (NSGraphics.m) | done |
| 3 | A change tells the app as a Mac does: effectiveAppearance's observers, viewDidChangeEffectiveAppearance, NSSystemColorsDidChangeNotification, AppleInterfaceThemeChangedNotification and the AppleInterfaceStyle default | Ferry AppKit, Foundation | done |

## 1.244 "Mac apps' own menus in the menu bar" (done)

Ferry 0.67.0: a Mac app's own menus are in freemac's menu bar, as on a Mac. Its File, Edit, View and other menus are there beside the app's name, with their shortcuts shown the Mac way, a tick by what's on and greyed out what can't be chosen right now, checked again every half second while the app is in front. Its application menu (About, Settings, Check for Updates) joins the menu under the app's name, and Quit there asks the app itself to quit, so it can ask to save first. The app's own Window items join freemac's Window menu and its Help items show under Help's search field, so the bar keeps one of each, and Help's search finds the app's menu items. Windows of a Mac app in the app grid now find its entry by the app's bundle identifier, so the Dock and ⌘Tab show the right icon and name for them even before the app has said where its icon is.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A Mac app's main menu is published on the session bus as GTK menus, and each of its windows tells the compositor where (as a GTK app's do): the application menu without the items freemac adds itself, then the other menus, separators as sections, shortcuts, ticks and dimmed items | Ferry AppKit (AMainMenuBar.m) | done |
| 2 | Choosing an item checks it again and sends its action, as on a Mac; Quit in the app menu ends the app through its own Quit | Ferry AppKit, Topline | done |
| 3 | An app's own Window and Help menus join Topline's: its Window items after Bring All to Front, its Help items under Help's search field, which also finds them | Topline, Help (helpsearch.py) | done |
| 4 | A Mac app's app grid entry names its windows by the bundle identifier (StartupWMClass), and entries made before get it at the next scan | Mac apps (macapps.py) | done |

## 1.243 "Mac apps from a .zip, and Applications that keeps up" (done)

Mac apps often come as a .zip, and their frameworks hold symbolic links (Versions/Current and the links beside it) that the app can't start without. Drawer now keeps links when it expands a .zip, as long as they point inside the new folder, as it already did for tar archives, and Compress stores links as links. A Mac app that comes out of a .zip is selected, and Drawer says it's ready to open. The app grid now follows the Applications folders while you're logged in: an app dragged or copied into Applications shows up in the app grid, the Dock's app list and search with its own icon within seconds, once it has finished copying; one moved out or to the Trash goes. Before, that waited for the next login.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Expanding a .zip keeps its symbolic links that point inside it; Compress keeps links as links | Drawer (drawer_archive) | done |
| 2 | A Mac app that came out of a .zip is selected, with a line saying it's ready to open | Drawer | done |
| 3 | `freemac-mac-app watch`, started with the session: apps added to or taken out of Applications reach the app grid within seconds, a copy only once it's complete | Mac apps (macapps.py), session | done |

## 1.242 "OBS opens again" (done)

Ferry 0.66.0: NSString changes letter case in a given locale (`uppercaseStringWithLocale:`, `lowercaseStringWithLocale:` and `capitalizedStringWithLocale:`), with ICU's rules for that locale, so Turkish gets its dotted capital I. OBS Studio 33 calls one of these at startup, and without it OBS quit before its window opened. In Ferry's test setup OBS now goes through its whole tour (the main window, every Settings page, a source's properties and filters) and quits cleanly, and records a microphone tone at its own pitch and level.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Letter case in a given locale: upper case, lower case and capitalized, as ICU maps them for that locale; nil is no locale's | Ferry Foundation, SDK | done |
| 2 | OBS Studio opens again and finishes its tour in Ferry's test setup, then records the microphone | Ferry (OBS task) | done |

## 1.241 "Ferry comes with freemac" (done)

Ferry 0.65.0 is on the ISO: a new freemac has Ferry from the start, so a Mac app opens from Drawer, the dock or the app grid with its own icon, and a .dmg or .pkg opens in Ferry's Installer, with nothing to add first. Software Update brings Ferry to computers installed earlier. Its libraries come too: libc++ for apps written in C++, 7-Zip for disk images and libcurl for networking. Its package is still published beside the ISO for other Ubuntu computers. In Ferry's test setup, OBS Studio now records the screen with its sound: the Screen source captures the display at half size over a colour, and quitting OBS stops the recording and finishes the file (19 seconds of H.264 and AAC, a 440 Hz test tone recorded at its own pitch and level). Buttons that apps make in code now draw through their cells, as Qt 6's Mac style draws OBS's buttons.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Ferry on the ISO: the release builds its package first and the image installs it with its libraries (`build/packages/ferry.list`); an image whose Ferry didn't build is the same desktop without it | Build (build-iso.sh, release workflow) | done |
| 2 | Software Update carries Ferry (its program, frameworks, Installer, SDK and binfmt registration) to installed computers | Software Update (make-update-bundle.py) | done |
| 3 | The release notes, README and Drawer's message no longer call Ferry an add-on | Docs, Drawer | done |
| 4 | In Ferry's test setup, OBS Studio records the screen and its sound, and stops cleanly when asked to quit | Ferry (OBS task) | done |
| 5 | Buttons made in code draw through their cells; `CGDirectDisplay.h` brings CGImage and CGColorSpace, as on a Mac | Ferry AppKit, SDK | done |
| 6 | Dials > Privacy & Security lists every question Mac apps ask through Ferry: Screen Recording, Microphone and Camera join Control Other Windows once an app has asked, each app with its switch and Forget; freemac-allow-control asks about the microphone and the camera | Dials, Ferry | done |

## 1.240 "Ferry: screen capture on Wayland" (done)

Ferry 0.64.0: Mac apps record the screen on Wayland, freemac's own Wayfire desktop included. Capture now speaks the xdg-desktop-portal ScreenCast portal (a session for each stream, the portal's own dialog where the user picks a display or a window, the pointer as metadata or drawn in, and a restore token kept for each app so the dialog can be skipped the next time) and reads the PipeWire stream it hands back in shared memory, into the same IOSurface frames as under X11, so ScreenCaptureKit, CGDisplayStream and the screen's pictures work the same way. Displays and windows are listed from Wayfire's IPC, as NSScreen and the window list already number them; on other compositors the displays come from wl_output and the window is the one the user picks. Capture chooses the portal where Wayland's portal answers, X11 otherwise, and `FERRY_CAPTURE` still forces one. freemac's own screen-recording question is asked first, as before; the portal's dialog comes after it. It has been tested against a stand-in portal with a real PipeWire, not yet in a real Wayfire session, and DMA-BUF streams aren't read yet.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The ScreenCast portal over D-Bus: CreateSession, SelectSources (monitor or window, cursor mode, persist mode, restore token), Start, OpenPipeWireRemote, the Request and Response signals, Session.Close; declined and failed answers as ScreenCaptureKit's errors | Ferry (appkit/ACapturePortal.m) | done |
| 2 | PipeWire: the stream from the portal's node, BGRx, BGRA, RGBx and RGBA in shared memory, header, crop and cursor metadata, into the capture core's IOSurface ring | Ferry (appkit/ACapturePortal.m) | done |
| 3 | DMA-BUF buffers | Ferry | not started (said once where a portal offers only those) |
| 4 | Restore tokens kept per app and source in `~/.config/freemac/screencast-restore.json` | Ferry (appkit/ACapturePortal.m) | done |
| 5 | Displays and windows from Wayfire's IPC (outputs, views, Strata's view pids), the scale learned from the stream; wl_output and the portal-picked window elsewhere | Ferry (appkit/ACapturePortal.m, CGServices.m) | done |
| 6 | Choosing the back end at run time (portal, X11, `FERRY_CAPTURE`), libpipewire and libwayland-client loaded when needed | Ferry (appkit/ACapture.m, src/host.c) | done |
| 8 | Tests: `screencapture_portal`; `make check` 331 of 331, three times. A test with a private PipeWire, a fake portal on a private session bus and test producers, with no X display | Ferry (tests/screencapture/) | done |

## 1.239 "Ferry: OBS Studio's main window opens" (done)

Ferry 0.63.0: OBS Studio 33 (its Mac build, with Qt 6.11) starts under Ferry and opens its main window: scenes, sources, the audio mixer, transitions and controls, with its OpenGL preview running at 30 frames a second on Mesa. The last thing in the way was libobs asking for the computer's own Application Support folder, a Mac's local domain, which Ferry didn't answer, so OBS stopped at once. Mac apps now get the computer's folders as a Mac gives them: `/Applications`, `/usr/local/share` (Library and Application Support, where freemac's installer puts apps' files for everyone) and `/var/cache` for the local domain, `/usr/share` for the system domain, after the user's own, in a Mac's order. OBS doesn't record yet, and the download doesn't include Ferry's OBS build; this is Ferry's test setup.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSSearchPathForDirectoriesInDomains` and `-[NSFileManager URLsForDirectory:inDomains:]` answer the local and system domains, as OBS's libobs asks for its program data | Ferry (foundation/) | done |
| 2 | OBS 33 runs to its main window, its modules (x264, FFmpeg, outputs, filters, transitions, image source, RTMP services) loaded and its preview drawing | Ferry (OBS task) | done |
| 3 | OBS records, and captures the screen with mac-capture | Ferry (OBS task) | next |
| 4 | Tests: `foundation_system` checks the local and system domains. `make check` 330 of 330, three times | Ferry | done |
| 5 | The README shows OBS under Ferry | Docs | done |

## 1.238 "Ferry: screen capture for OBS, VLC's Preferences and subtitles, and Qt 6 windows on screen" (done)

Ferry 0.62.0: Mac apps record the screen. ScreenCaptureKit lists the displays, the windows and the apps that own them, and streams a display, part of one, a single window, or a display showing only some apps' windows (or all but some) as Core Media sample buffers whose pixels are IOSurface-backed Core Video buffers in 'BGRA', 'l10r', '420v' or '420f', with the frame-info attachments OBS reads, at the configured size and frame interval, with or without the pointer. The older calls OBS also uses are here too: CGDisplayStream, display modes, and the window list with its pictures of other apps' windows and of the screen. Under X11 the pixels come from the X server, through MIT-SHM where it can share memory and XGetImage where it can't, a window's own through XComposite, and the pointer through XFixes; with `capturesAudio` the stream also records what the computer plays from the sound server's monitor. Recording asks the user once, as freemac's own question with its own file of answers. Wayland (Wayfire) would need the ScreenCast portal and PipeWire, which aren't spoken yet: there capture says so and finds nothing, unless `FERRY_CAPTURE=x11` points it at an X server.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | ScreenCaptureKit.framework: `SCShareableContent` (all its `get…` calls), `SCDisplay`, `SCWindow`, `SCRunningApplication`, `SCContentFilter` (a window, a display with windows or apps included or left out), `SCStreamConfiguration`, `SCStream` (outputs, start, stop, `updateConfiguration:`, `updateContentFilter:`, the delegate's `stream:didStopWithError:`), `SCScreenshotManager`, `SCStreamErrorDomain` and its codes | Ferry (screencapturekit/) | done |
| 2 | Core Media: sample buffers (video and audio, timing, sizes, attachments and the per-sample attachments array), format descriptions, block buffers, the host clock, more `CMTime` arithmetic | Ferry (appkit/CMSampleBuffer.m) | done |
| 3 | CGDisplayStream (create on a dispatch queue, start, stop, frame status, IOSurfaces, update rects, drop counts, its property keys) and `CGDisplayCopyDisplayMode` with the display mode calls | Ferry (appkit/CGDisplayStream.m) | done |
| 4 | The window list: other apps' X windows in `CGWindowListCopyWindowInfo`, and `CGWindowListCreateImage` of the screen and of other apps' windows, behind the user's say | Ferry (appkit/CGServices.m) | done |
| 5 | The capture core: an X11 back end (MIT-SHM or XGetImage, XComposite, XFixes, `_NET_CLIENT_LIST`, `_NET_WM_NAME`, `_NET_WM_PID`), frames on a ring of IOSurfaces at the frame interval, scaling, the pointer, the user's say in `screen-recording.json` | Ferry (appkit/ACapture*.m), Shell (window_control.py) | done |
| 6 | The computer's sound as ScreenCaptureKit's audio output, from the sound server's monitor of the default output | Ferry (screencapturekit/, coreaudio/) | done |
| 7 | Wayland: the xdg-desktop-portal ScreenCast portal and PipeWire streams behind the same back-end interface | Ferry (appkit/ACapturePortal.m) | done in 1.240 |
| 8 | Tests on an Xvfb of their own with another app's window beside the test's, and with no display | Ferry, Shell | done |
| 9 | VLC's menus answer their Command-key equivalents and its Preferences window opens with every pane, its subtitle renderer built against FreeType; `setjmp` and `sigsetjmp` in a Mac's `jmp_buf`, Core Text font descriptors and fallbacks from the installed fonts (VLC task, see `docs/ferry-notes/vlc.md`) | Ferry | done |
| 10 | Qt 6.11 builds against Ferry's SDK and a Qt Widgets window runs with its Cocoa platform and macOS style; C linkage for Foundation's and AppKit's C calls in C++, `nil` as `nullptr` in C++, named colour spaces kept, ICC profiles, and what OBS's libobs asks of libSystem, Foundation, Security, IOKit HID and Carbon (OBS task) | Ferry | done |
| 11 | VLC shows subtitles over its video, and its Open dialog, the playlist after stopping and seeking work: iconv as a Mac's libiconv, Mac font families that aren't installed answered by their stand-ins, 10.0-style number formats showing % as it is, and VLC's C++ modules linking libc++ (VLC task, see `docs/ferry-notes/vlc.md`) | Ferry | done |
| 12 | Subtitles burned into a converted video come out as on screen: VLC's FFmpeg is built in plain C, since FFmpeg 6.1 with inline assembly but no nasm hands swscale's MMX-layout vertical filter to the C scaler (VLC task) | Ferry (apps/vlc.sh) | done |
| 13 | Qt 6 windows draw on screen: `setNeedsDisplayInRect:` as the layer's primitive, `setWantsLayer:` through `makeBackingLayer` and `setLayer:`, `displayLayer:` delegates marked on `setNeedsDisplay:`, IOSurfaces as layer contents, and a bare-name `dlopen` tried through `@rpath` as dyld does; OBS 33 gets as far as starting OpenGL (OBS task) | Ferry | done |
| 14 | Tests: `screencapture_coremedia`, `screencapture_x11`, `screencapture_x11_noshm`, `appkit_qt_layers`, `iconv`; the `libcurl` test skips without libcurl's headers. `make check` 330 of 330, three times | Ferry | done |

## 1.237 "Ferry: VLC plays in its own window, and a faster Auto Layout solver" (done)

Ferry 0.61.0: big windows lay out about 70 times faster. The solver is sparse and only goes forward, so trying an inequality in or out goes again only over the rows that change reaches, and a stack view's fitting sizes are worked out once a layout. A window of 245 views and 893 constraints lays out in about a tenth of a second where it took seven, with every frame where it was. VLC's xib windows and Itsycal's popover are the windows this was for. In this release VLC 3.0.24's own Mac app, built from source by `ferry/apps/vlc.sh`, also opens its main window under Ferry and plays a video in it, with the picture, the sound and its control bar (see `docs/ferry-notes/vlc.md`).

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Auto Layout solves big windows about 70 times faster: a window of 245 views and 893 constraints lays out in about a tenth of a second where it took seven, its biggest solve in under 8 ms where it took nearly two seconds, with every frame where it was | Ferry AppKit | done |
| 2 | The fitting sizes a stack view asks for while a window's constraints are gathered are worked out once each | Ferry AppKit | done |
| 3 | A benchmark of a big window (a sidebar, a month of 42 days and a list of events, in stack views, with mixed priorities and inequalities) in Ferry's test suite, checking its frames at four sizes | Ferry tests | done |
| 4 | VLC 3.0.24's Mac app opens its main window and plays a video in it through its `caopengllayer` video out and its `auhal` sound out, its time and position slider moving, to the end; a slider's, stepper's or segmented control's cell keeps the app's own class through `ferry-ibtool`; a cancellable condition wait no longer loses a wake (VLC task) | Ferry | done |

## 1.236 "Ferry: the Mac apps rebuilt by recipes" (done)

Ferry 0.60.0: the open-source Mac apps that have run under Ferry are
built again from their source by one script each, `ferry/apps/APP.sh`,
which fetches the app and what it uses at pinned commits and builds them
with Ferry's SDK, outside freemac's repository. Their Xcode projects are
read by `ferry/apps/xcode.py`, Ferry's own reader of the project file,
which compiles each target's sources, xibs and asset catalogues with
`ferry-cc`, `ferry-ibtool` and `ferry-actool`. Recipes are new for
Flycut, Spectacle, ShiftIt, KeyCastr, MacPass, MacDown and Itsycal, beside
TomatoBar's. Each app was run again under X after 1.232's layout pass:
two stack views and a grid view were put right, so MacPass's welcome
window shows its title and buttons again and Itsycal's agenda shows its
video-call button only for an event with a meeting link.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `ferry/apps/xcode.py`: one target of an Xcode project built for its Release configuration, with its .xcconfig files and `$(inherited)`, prefix header, definitions, search paths, ARC and each file's own flags, and its resources (xibs to nibs, asset catalogues, .lproj folders); an app, a framework with its headers, a plug-in bundle or a library | Ferry apps | done |
| 2 | Recipes for Flycut, Spectacle, ShiftIt, KeyCastr, MacPass, MacDown and Itsycal, with the frameworks and pods they use; Sparkle 1 and 2 built from source by two shared helpers; `ferry/apps/README.md` lists them | Ferry apps | done |
| 3 | Each app run again: Flycut's menu and preferences, Spectacle's and ShiftIt's menus, KeyCastr's update prompt, MacPass's welcome and document windows, MacDown's editor and preview, Itsycal's month and agenda and TomatoBar's popover show as before; screenshots in `docs/screenshots/ferry-apps/` | Ferry | done |
| 4 | A stack view sizes a view held by its own width and height constraints to them, not to its intrinsic size, and is as wide across as the widest view that has a width of its own (MacPass's welcome: its 128-point icon had taken the whole stack, pushing its title and buttons out) | Ferry AppKit | done |
| 5 | A grid view leaves hidden a view the app hid itself; it unhides only the views it hid for a hidden row or column (Itsycal's agenda showed its video-call button on every row) | Ferry AppKit | done |
| 6 | Tests: `appkit_polish` and `appkit_newer_apps` extended. `make check` 309 of 309, three times | Ferry | done |

Not done: Sequel Pro has no recipe yet (MariaDB Connector/C needs its
hashes over CommonCrypto and its build configuration written for Ferry).
Itsycal's window still appears seconds after the click: opening it solves
the window's constraints 22 times, 3.9 seconds in all, and each large solve
takes 80 rounds that hold one broken inequality at a time.

## 1.235 "Ferry: OpenGL and Core Video, for VLC's and OBS's video" (done)

Ferry 0.59.0: Mac apps draw with OpenGL. CGL makes its contexts on this system's EGL (Mesa's software renderer will do), legacy 2.1 and core 3.2 and 4.1, and NSOpenGLView, NSOpenGLContext and CAOpenGLLayer draw into a window as VLC's and OBS's video output do, from the main thread or a thread of the app's own. Core Video gains display links at the display's rate, pixel buffers and pools on IOSurfaces in the formats video uses, and OpenGL texture caches, and IOSurface textures reach OpenGL with CGLTexImageIOSurface2D. Frames go through a copy on the CPU, about 5.5 ms for each 1080p frame, and surfaces aren't shared between programs. With this, everything VLC's interface was waiting on is in Ferry.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | OpenGL.framework: CGL on this system's EGL (Mesa's llvmpipe will do), every gl call passed to its libOpenGL or libGL, opened only when a program draws; legacy 2.1 and core 3.2 and 4.1 profiles, shared contexts, locks, swap intervals, `CGLTexImageIOSurface2D` | Ferry (opengl/) | done |
| 2 | `NSOpenGLPixelFormat`, `NSOpenGLContext` and `NSOpenGLView`, drawn offscreen, read back and painted into the view, from drawRect: or from a thread of the program's own | Ferry (appkit/NSOpenGL.m) | done |
| 3 | `CAOpenGLLayer`, synchronous, from any thread, and asynchronous at the display's rate | Ferry (quartzcore/CAOpenGLLayer.m) | done |
| 4 | Core Video: display links, pixel buffers and pools (BGRA, 420v, 420f, y420, 2vuy and more, on IOSurfaces), attachments, OpenGL texture caches; IOSurface.framework | Ferry (corevideo/, iosurface/) | done |
| 5 | Tests with and without OpenGL, pictures, a compat section | Ferry, Docs | done |

## 1.234 "Ferry: sound, with Core Audio" (done)

Ferry 0.58.0: Mac apps play and record sound. A new Core Audio, which also serves AudioToolbox and AudioUnit, makes each output and input of the desktop's sound server a device, through libpulse, and follows the server's default devices, volume and mute. HALOutput and DefaultOutput units play as VLC's sound out does, a HALOutput unit records as OBS's audio capture does, audio queues play and record as OBS's monitoring does, and converters change PCM formats and rates. With no sound server an app sees one null device and carries on. VLC and OBS themselves weren't run yet, and AAC in converters, which OBS's encoder needs, is next.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Core Audio's HAL, new, in `ferry/coreaudio/` (replacing 1.232's `CoreAudio.c`), on this system's sound server through libpulse, opened when a program first asks: | Ferry Core Audio | done |
|   | - each sink is an output device and each source an input device, with the server's names as their UIDs; a sink's monitor is an input device that is never the default; the defaults are the server's | | |
|   | - with no server, no libpulse, or `FERRY_AUDIO=null`, one null device, 48 kHz stereo both ways, that runs on the clock: what it plays can go to `FERRY_AUDIO_OUTPUT_FILE` and what it records come from `FERRY_AUDIO_INPUT_FILE` (32-bit float samples), or else it hears what it plays, 50 ms later | | |
|   | - the system object and devices: device lists, the defaults (settable on the server), names, UIDs, manufacturers, transport, alive, running, streams and their formats, the nominal rate and the rates offered, buffer frame size, latency and safety offset, channel names, the stream configuration and preferred channel layout, data sources, hog mode, and volume and mute (read and set on the server) | | |
|   | - property listeners, as procs and as blocks on a queue, told when the server's devices come and go and its defaults, volumes and mutes change, as well as of the program's own changes | | |
|   | - IO procs (`AudioDeviceCreateIOProcID`, `AudioDeviceStart`, `AudioDeviceStop`), with the older `AudioDeviceAddIOProc` and `AudioHardwareGetProperty` calls, host time and its conversions, and Audio Hardware Services | | |
| 2 | Audio Toolbox, served by Core Audio: | Ferry Core Audio | done |
|   | - audio components, and the HALOutput, DefaultOutput, SystemOutput and GenericOutput units: stream formats on both sides, render callbacks and render notifications, input on HALOutput with an input callback and `AudioUnitRender`, channel maps, the volume parameter, the current device, following the default device, and the properties VLC and OBS ask of a unit | | |
|   | - audio queues for output and input, in linear PCM, with callbacks on a run loop, a dispatch queue or the queue's own thread; start, stop (at once or once played out), pause, prime, flush and reset; volume, level meters and the current device; `IsRunning` listeners | | |
|   | - audio converters between linear PCM formats: sample formats, byte order, interleaving, channel counts and maps, and rates (linear interpolation) | | |
|   | - Audio Format Services' channel layouts (for a tag, for a bitmap, channel counts and names) and format information | | |
| 3 | Five new tests, `coreaudio_devices`, `coreaudio_missing`, `coreaudio_auhal`, `coreaudio_queue` and, where PulseAudio is installed, `coreaudio_pulse` on a server of its own with null sinks | Ferry | done |
| 4 | Compressed formats (AAC and the rest) in converters and queues, through FFmpeg's libavcodec | Ferry Core Audio | not done |
| 5 | Pass-through of compressed audio to a device (VLC's S/PDIF path); a device's own rates and buffer sizes on the server, and hog mode taking a device for one program | Ferry Core Audio | not done |
| 6 | VLC's sound out and OBS's audio capture and monitoring, tried with the apps themselves | Ferry Core Audio | not done |

## 1.233 "Ferry: FFmpeg as Mac libraries, for VLC and OBS" (done)

Ferry 0.57.0: FFmpeg 8.0.1, which OBS needs, and 6.1.1, which VLC 3.0.24 builds against, are built from their release tarballs as Intel Mac libraries and tools by `ferry/apps/ffmpeg.sh`, and under Ferry they decode, encode, mux and filter to the same output as FFmpeg on Linux. libSystem gains `posix_spawn`, `glob` and `fnmatch`, `mach_wait_until`, a Mac's terminal settings and a `backtrace` that names every Mac frame, and a plugin host test checks the `dlopen` path VLC and OBS take. The release also carries the VLC task's work on what VLC's Mac interface calls (#270): presentation options, alert sheets, slider, button and segmented cell drawing, `CGDirectDisplay.h` on NSScreen, CoreMedia's `CMTime`, MediaPlayer's remote commands and more. VLC's interface now waits only on Core Audio, Core Video's display link and NSOpenGLView.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | FFmpeg 8.0.1 (for OBS) and 6.1.1 (for VLC) built as Intel Mac dylibs and tools by `ferry/apps/ffmpeg.sh`, software codecs only | Ferry recipes | done |
| 2 | FFmpeg's `ffmpeg` and `ffprobe` run under Ferry and decode H.264/AAC, VP9/Opus, Theora/Vorbis and VP8/MP3 to the same frame MD5s as a Linux FFmpeg | Ferry | done |
| 3 | A plugin host test: libraries and plugins built in the test, opened with `dlopen` from four threads, `@rpath`/`@loader_path`, flat lookups, weak imports, plugins that fail to load | Ferry tests | done |
| 4 | `posix_spawn` and `posix_spawnp` with file actions and attributes, Mac children run through Ferry | Ferry libSystem | done |
| 5 | `glob`, `globfree` and `fnmatch` in the Mac's layout and flag numbers; `mach_wait_until`; `getrusage`'s `ru_maxrss` in bytes | Ferry libSystem | done |
| 6 | `backtrace` and `backtrace_symbols` follow Mac code's frame pointers and name each frame's image and symbol | Ferry libSystem | done |
| 7 | Terminal settings (`tcgetattr`, `tcsetattr`, `cfmakeraw`, speeds, flushing) with a Mac's `struct termios`, and `posix_openpt` | Ferry libSystem | done |
| 8 | Hardware codecs (VideoToolbox, AudioToolbox) and external codec libraries (x264, libvpx, libopus) for FFmpeg | Ferry recipes | not started |

## 1.232 "Ferry: Itsycal and EventKit" (done)

Ferry 0.56.0: Itsycal, the menu-bar calendar, is the ninth of the
open-source Mac apps to link and run, built from its source with
MASShortcut and Sparkle built from theirs. Its status item opens the
month with today ringed and the days with events marked, and the agenda
under it lists the events and reminders of the coming days. They come
from a new EventKit, which reads and writes freemac's own calendar
(Tide's) and reminders (Nudge's) files and asks the user before an app
sees them. Auto Layout gained a layout pass before a window draws, with
its view controllers told, a view controller's preferred content size
and a safe-area guide that follows its view's insets. Gas Mask, the
tenth, still doesn't link: the Growl framework it brings stopped at older
Core Foundation and Carbon names, and the round was wound down before it
was taken further. The seven earlier apps weren't rebuilt this round.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Itsycal links and runs from its source, with MASShortcut 2.4.0 and Sparkle 1.27.1 built from theirs: | Ferry | done |
|   | - its status item opens its window at the top right of the screen, under the menu bar, the full width of its month | | |
|   | - the month shows today ringed, the weeks outlined and a dot under each day with events | | |
|   | - the agenda lists today's and the coming days' events and reminders, a day's heading over each, at the height Itsycal asks for | | |
| 2 | EventKit, new, on freemac's own files: | Ferry EventKit | done |
|   | - events are Tide's, in `~/.local/share/freemac/calendar.ics`, as the "Calendar" calendar of "On My Mac" or a calendar of the online account that brought them | | |
|   | - reminders are Nudge's lists, one file of to-dos each, with a "Reminders" list when there is none | | |
|   | - repeating events expanded from their rules, less their exceptions; a moved date of a series is its own item | | |
|   | - a save changes only the items saved and keeps every line it doesn't use, so Tide's and Nudge's own lines survive; the store tells apps when the files change | | |
|   | - an app asks for access first, with an alert, and the answer is kept per app; with no display to ask on the answer is no | | |
|   | - an event's participation status, the user's own among its attendees, which Itsycal reads by key | | |
| 3 | Auto Layout: | Ferry AppKit | done |
|   | - before a window draws, the views marked as needing layout are laid out, their view controllers told before and after (`viewWillLayout`, `viewDidLayout`), and the constraints solved again for what that changed | | |
|   | - a view controller's `preferredContentSize` holds its view to that size, just above a window's wish to keep its size; a zero dimension holds nothing | | |
|   | - the safe-area guide follows the view's insets as they change | | |
|   | - a constraint that held a view at a size of zero is let go of when only a weaker wish breaks without it (Itsycal's month title, which hugs its text at priority 1, had made the window 16 points wide), once a row so the solver can't go back and forth | | |
|   | - a constraint's constant set to the value it has changes nothing, so a layout that sets the same size again doesn't solve again | | |
| 4 | `NSPredicateEditor` and its row templates, in code and from compiled nibs, on the rule editor: the rows made from a predicate, the predicate from the rows, and compound rows. `ferry-ibtool` writes a template's row type, attribute type, modifier and options as numbers, which it had written as references | Ferry AppKit, Ferry SDK | done |
| 5 | Core Audio's audio objects through the AudioToolbox header: the default output and input devices, their names, volume and mute, read and set through this system's sound server; with none, the devices are there and answer that it isn't running | Ferry Core Audio | done |
| 6 | Newer and older names the apps call: safe areas, `CADisplayLink`, window occlusion, symbol configurations, menu section headers, the system fill colours, full-size popovers, scroll phases, `refusesFirstResponder`, an application's will-become-active and will-resign-active notifications, a button cell's background colour in a table, `setTitleWithMnemonic:`, a layer's corner curve, `NSDateIntervalFormatter`, formatting contexts, `localizedStandardCompare:`, resource specifiers and the tags key, and the reachability flags | Ferry AppKit, Foundation, QuartzCore, SDK | done |
| 7 | Two new tests, `appkit_newer_apps` and `eventkit`. `make check` 279 of 279, three times | Ferry | done |

Not done: Itsycal's window appears a few seconds after the click, since
solving the constraints of the agenda's rows takes over a second a time;
every agenda row shows Itsycal's video-call button, which a Mac shows only
for an event with a meeting link; its Mow font isn't loaded and its
`AppIcon.icon` isn't compiled; Sparkle's helper tools aren't built; layer
masks aren't drawn. Gas Mask doesn't link.

The same release brings the first of the work on VLC 3.0.24 (`ferry/apps/vlc.sh`, which builds it and FFmpeg 6.1.1 from their release tarballs): the libSystem calls VLC's core uses, Mach semaphores, `pathconf`, `getpwuid_r`, `sigwait`, `statvfs`, `strnstr`, `backtrace` and more, in `src/libc_vlc.c`, with `CFNetworkCopySystemProxySettings`. With them libvlccore, libvlc, the `vlc-osx` program and 249 of VLC's plugins build; it doesn't run yet.

## 1.231 "Ferry: TomatoBar built by a recipe, and its popover as on a Mac" (done)

Ferry 0.55.0: TomatoBar is built from its source by a recipe in the repo,
`ferry/apps/tomatobar.sh`, which fetches it and its three packages at
pinned commits, builds them with `ferry-swiftc` and lays out the bundle.
Its popover now opens under its menu bar item, and looks and works as on a
Mac: a wide blue Start button, a segmented picker across its width,
steppers with arrows, switches, and plain About and Quit rows with their
shortcuts. About shows the standard About panel. At the end of an interval
it sends its notification, and its sounds play through the system's sound
player.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `apps/recipe.sh`, shared helpers for recipes that build an app from its public source: fetch a repository at a pinned commit, bring Ferry's Swift modules up to date, build a Swift package as a library, write a SwiftPM resource accessor. Work goes in `apps/work` (ignored) or a folder given | Ferry apps | done |
| 2 | `apps/tomatobar.sh`: TomatoBar, SwiftState, LaunchAtLogin and KeyboardShortcuts at the commits TomatoBar's `Package.resolved` pins, built and bundled with its asset catalogue, localizations and KeyboardShortcuts' resource bundle. Rerun from an empty folder, it builds a TomatoBar.app that runs | Ferry apps | done |
| 3 | A popover from a menu bar item opens with its arrow at the foot of the menu bar, under the item, also where the work area under X doesn't leave the menu bar out | Ferry AppKit | done |
| 4 | A click on a label in a popover no longer goes round between the label and the popover for ever (TomatoBar quit on such a click): an event passed back up to the popover stops there, as at a window | Ferry AppKit | done |
| 5 | The standard About panel: the app's icon, name, version and build, credits and copyright, from the options given or the bundle's Info.plist | Ferry AppKit | done |
| 6 | `NSSwitch`, drawn as a pill with a knob, turned by a click or Space; a large control's bezel is taller; the monospaced and other system fonts are non-optional in Swift | Ferry AppKit, SDK | done |
| 7 | SwiftUI: plain, borderless and link button styles (the label's views with a transparent button over them), keyboard shortcuts on buttons and in menus, a default button, `controlSize`, buttons that fill their width when their label does, the switch toggle style, steppers with arrows (`NSStepper`), segmented pickers across their width, `LabeledContent` with its label at the leading edge | Ferry SwiftUI | done |
| 8 | TomatoBar: the popover under its item; Intervals, Settings and Sounds; the steppers step; About; the end-of-interval notification with its Open and Skip actions; windup and ticking sounds through the sound player | Ferry | done |
| 9 | The SwiftUI test driver presses switches by their label, steps steppers (`up:N`, `down:N`) and picks segments (`segment:T`). New test `swift_swiftui_styles`; `make check` 288 of 288 | Ferry | done |

Not yet: labels in TomatoBar's Settings tab are cut short by a few points
("Show timer in menu ba…"), as Ferry's text is wider than a Mac's.
Under X with no compositor the popover's corners show white. Gas Mask
(MASShortcut and Sparkle from source, `NavigationSplitView`, toolbar items,
drop delegates and the rest), `@Observable` with the Observation module,
and Spaceman (Sparkle 2, the window server's spaces calls) were not started
in this round.

## 1.230 "Ferry: TomatoBar links and runs" (done)

Ferry 0.54.0: TomatoBar, an open-source SwiftUI menu bar timer, links and
runs. Its three packages (SwiftState, LaunchAtLogin and KeyboardShortcuts)
are built from their source as libraries with `ferry-swiftc`. Its menu bar
item shows in Topline with its icon. A click opens its popover, with the
whole of its window: Start, the Intervals, Settings and Sounds tabs, the
interval steppers, About and Quit. Start starts the timer, and the time
left counts down in the menu bar. Swift now has Dispatch, the concurrency
library, Combine, Foundation's value types and an AppKit overlay. The
Swift in Hex Fiend compiles too.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dispatch for Swift: an overlay with `DispatchQueue`, groups, semaphores, work items, times and sources (timers among them), over Ferry's libdispatch. libdispatch gains the function handlers, queue assertions, `os_retain` and vouchers that Swift's concurrency runtime calls | Ferry Dispatch, libdispatch | done |
| 2 | Swift's concurrency library (`_Concurrency`), built from Swift's source by `build-runtime.sh`: `async`, `await`, `Task`, actors and `@MainActor`. AppKit's responders are the main actor's, as on a Mac | Ferry runtime, SDK | done |
| 3 | Foundation's value types: `Date`, `Data`, `URL` and `UUID` are structs bridged to their NS classes, with `Codable`. `JSONEncoder` and `JSONDecoder`, `String.Encoding`, `FileHandle`'s throwing methods, the formatters' Swift names, key-value observing with key paths, `NSPredicate(format:)` | Ferry Foundation | done |
| 4 | A Combine module (subjects, sinks, `assign`, the common operators, `Just`, `Future`, schedulers, and the notification, key-value and timer publishers); `ObservableObject` and `@Published` moved into it | Ferry Combine | done |
| 5 | An AppKit overlay and AppKit's nested Swift names: `NSEvent.ModifierFlags`, `NSWindow.StyleMask`, `NSImage.Name`, `NSFont.Weight`, the notification names (`NSWindow.didBecomeKeyNotification`), run loop modes, attributed-string keys, status item lengths, `NSEvent.SpecialKey`, `NSColor.ColorType`. `NSNib.Name` is a plain String, as on a Mac | Ferry SDK, AppKit overlay | done |
| 6 | Run loop observers (`CFRunLoopObserver`); Carbon's key event constants and `UCKeyTranslate`'s header; `SMAppService` (a login item, shown in Dials > Login Items); os's `Logger`; `AVAudioPlayer` over `NSSound`; `UNUserNotificationCenter.current()` non-optional | Ferry Foundation, AppKit, ServiceManagement, os | done |
| 7 | A popover shown from a menu bar item opens in a window of its own, under where Topline says the item was clicked. Topline sends that point with `Activate` | Ferry AppKit, Topline | done |
| 8 | SwiftUI: shapes (`Rectangle`, `RoundedRectangle`, `Circle`, `Ellipse`, `Capsule`, and an app's own `Shape` with `Path`), filled or stroked; `overlay` and `background` placed by alignment; `GeometryReader`; `alert` with its actions; `sheet`; the segmented picker style; `task`, `onReceive`, `LabeledContent`; `#Preview` expands to nothing | Ferry SwiftUI | done |
| 9 | TomatoBar links with its three packages built from source, runs, and its popover's Start starts its timer. Hex Fiend's Swift compiles against its headers | Ferry | done |
| 10 | New tests: `swift_dispatch`, `swift_concurrency`, `swift_values`, `swift_combine`, `swift_services`, `swift_appkit_names`, `swift_swiftui_tasks`, `swift_swiftui_drawing` and `foundation_runloop_observers`; `make check` 284 of 284 | Ferry | done |

Not yet: the popover isn't placed under its menu bar item (it was built before
Ferry placed windows itself in 1.229, and wasn't checked again), and TomatoBar's sounds need a sound player on the system
(`pw-play`, `paplay` or `aplay`). Spaceman needs Sparkle 2 and the window
server's private spaces calls. Gas Mask's Swift needs MASShortcut,
Sparkle, `NavigationSplitView`, toolbar items and drop delegates.

## 1.229 "Ferry: the apps' nibs whole, and windows placed" (done)

Ferry 0.53.0: every element in the seven apps' xibs is made as its own
class, with its attributes, where `ferry-ibtool` made 136 of them as
empty views of their class or left them out, and dropped the formatters
of cells in 16 xibs. Text views keep their text, fonts and colours, web
views their preferences, and matrices their cells. MacPass's inspector
opens at the width of its nib, wide enough for its tabs and its password
row, and its unlock window shows its key file control. Under X a window
is placed as a Mac places it, where its nib puts it on the screen it
opens on, centred, or cascaded, where it used to open at the top left.
Flycut's alert and bezel are centred, and ShiftIt's tall alert is kept
on the screen. Blocks reach JavaScript as functions, and a
`JSManagedValue` holds its object weakly.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `ferry-ibtool` makes the elements it didn't know as their own classes, with their attributes: | Ferry SDK, AppKit, WebKit | done |
|   | - text views, with their attributed text, flags, colours and the text container's sizing | | |
|   | - web views with their preferences (font sizes, plug-ins, JavaScript) | | |
|   | - matrices with their cells and prototype, level indicators, date pickers, path controls, rule editors, plain controls with their cells, and Quartz Composer views | | |
|   | - collection views with their item prototypes | | |
|   | - the formatters of cells (number, date, byte-count, date-components and the app's own), the data cells of table columns, and cells and formatters at a nib's top level | | |
|   | Over the 372 xibs the apps use, 136 elements of 13 kinds were made as empty views of their class or left out, and the formatters in 16 xibs were dropped. Sparkle's release-notes web views, Sequel Pro's text views and filter rule editor, MacPass's notes, key file control, icon picker, expiry date picker and strength indicator, ShiftIt's two matrices and KeyCastr's composition view were among them; none is left | | |
| 2 | Bindings on the new classes: a text view's `value` and `attributedString` (pushed as the text changes and when the view gives up focus), and a button cell's `value` in a matrix. A text view's colour and font from the nib no longer overwrite the runs of its text. `NSAttributedStringBinding` and `NSDataBinding` are declared | Ferry AppKit | done |
| 3 | A split view controller's panes are shared out only once its split view is in a window. MacPass sizes its document view to the window before putting it in, and Ferry squeezed the panes into the 480 points of the controller's nib first, so the inspector opened at its 200-point minimum. It now keeps the 278 points of its own nib. A pane laid out by constraints is also never thinner than its content's fitting size, past its item's minimum, as Auto Layout keeps it on a Mac, collapsed panes included | Ferry AppKit | done |
| 4 | Windows placed under X11, where Ferry now moves them itself: | Ferry AppKit | done |
|   | - a window goes where its frame says, and a move the user makes comes back into its frame, as a did-move notification, and is saved under its autosave name | | |
|   | - a nib's window is placed by its xib's initial position: the edges it keeps its distance from, measured on the screen the xib was drawn on and kept on the screen it opens on | | |
|   | - a document's windows cascade unless one has a frame saved under its name, and a frame saved under a name is the window's again when the name is set | | |
|   | - a titled window's top is kept below the top of the visible screen, and `cascadeTopLeftFromPoint:` starts again at the top left when the next window would leave the screen | | |
|   | Under Wayland the compositor still places windows | | |
| 5 | An alert run modally is kept on the screen, its top first. ShiftIt's is 593 points tall with its picture; centred a third of the way down an 800-point screen, it would have lost its top 29 points | Ferry AppKit | done |
| 6 | JavaScriptCore: a block or an exported method is a function in scripts (`Function.prototype` is its prototype, so `call`, `apply` and `bind` work and `instanceof Function` is true). A `JSManagedValue` holds an object through the language's `WeakRef`, so its value is nil once the collector has taken the object. `JSVirtualMachine`'s managed references, and an owner given when the value is made, keep the object alive for as long as their owner is alive | Ferry JavaScriptCore | done |
| 7 | `webkit_dom` waits for the title change until both the frame load delegate and the frame's data source have it, rather than for a fixed time. It passed 8 runs of 8 | Ferry tests | done |
| 8 | Two new tests (`appkit_ibtool_classes`, and `appkit_x11_placement`, which needs Xvfb and ImageMagick), and more cases in five others. `make check` 277 of 277, three times | Ferry | done |

The xib's initial position is read as Ferry reads it, since Apple
documents no format for it: an edge the window keeps its distance from
is kept on the new screen, the left and bottom edges win when both edges
of an axis are kept, and an axis with neither is placed in proportion. A
window whose xib has no initial position is placed at its frame as it
is, as Spectacle's is. No eighth app was added: Gas Mask and Hex Fiend,
the two candidates already cloned, have Swift in them (the older Gas
Mask clone here has none, but links four prebuilt frameworks whose
source isn't here), and any other app would have had to be fetched from
GitHub, which this round didn't do. A JavaScript
function isn't made into an Objective-C block, which Apple's
JavaScriptCore doesn't do either. MacDown's window fills the screen
under Xvfb, so it looks as it did. `DDHotKey`'s demo xib, which no app
uses, still doesn't compile: its base64 data is damaged.

## 1.228 "Ferry: the apps' windows" (done)

Ferry 0.52.0: the seven apps' windows laid out and drawn as on a Mac.
The constraints in their xibs now reach the nibs `ferry-ibtool` compiles,
and a window's size gives way to them, so MacPass's panes, inspector
included, fill its window, and KeyCastr's Sparkle window opens at the
size of its content.
MacDown shows its toolbar, with its editor and preview filling the
window. Flycut's bezel shows when its shortcut is pressed, Sequel Pro's
spinner goes away when "Connection failed!" comes up, and KeyCastr's
icon, which is JPEG 2000, is drawn.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `ferry-ibtool` carries a xib's constraints into the nib, with each view's hugging and compression resistance and whether it translates its autoresizing mask. It left them all out, so MacPass's panes, MacDown's split view and Sparkle's prompt in KeyCastr stayed at the frames the xib drew them at | Ferry SDK, AppKit | done |
| 2 | A window's content holds its size only at `NSLayoutPriorityWindowSizeStayPut`, as on a Mac. Stronger constraints inside it make the window grow or shrink, within its content's minimum and maximum, keeping its top left corner. Ferry held it at its size as required, so KeyCastr's prompt opened tall with its content at the bottom | Ferry AppKit | done |
| 3 | Split and stack views with constraints: | Ferry AppKit | done |
|   | - a split view controller's split view is held to its view's edges, and a pane is kept within its item's minimum and maximum thickness, so MacPass's inspector is no longer pushed out of its window | | |
|   | - the solver leaves a split view's panes and a stack view's views where their container put them | | |
|   | - a stack view is as long as its views, hugs as firmly as the loosest of them, measures a view laid out by constraints by its fitting size and stretches across it a view that hugs less firmly than the stack | | |
| 4 | `ferry-ibtool` compiles a window's toolbar: its items with their labels, images, tags, tool tips, views, sizes and actions, its default items and its delegate. It made none before, which left a grey band at the top of MacDown's window. A toolbar item shows its view's image when it has none of its own, and an item made from a view with no size given is the size of the view's frame | Ferry SDK, AppKit | done |
| 5 | Windows are sent `-update` once after each event, hotkey or window shown, and on `setWindowsNeedUpdate:`, not on every turn of the run loop. Flycut's bezel sets its background there, which asked for another redraw and update without end, until the app was killed for its memory. A window whose background is a pattern colour draws the pattern image, tiled (Flycut's rounded bezel), rather than its average colour | Ferry AppKit, WebKit | done |
| 6 | A progress indicator's `displayedWhenStopped` was read the wrong way round from xibs, so Sequel Pro's spinner stayed in its connection form after Connect failed | Ferry SDK | done |
| 7 | Buttons and fields: a button with an image and no title set is image-only, as on a Mac, where Ferry gave it its default title. A help button is drawn round, with its question mark, at 25 by 25 points, and an inline button as a small badge, as MacPass's entry counts are. Setting a text field bordered turns its bezel off, and the reverse | Ferry AppKit | done |
| 8 | A window size asked of GTK while a window is drawn is asked again until GTK gives it, so an older size isn't taken. A window that can't be resized can now get smaller | Ferry AppKit | done |
| 9 | `.icns` files with only JPEG 2000 pictures are read by this system's OpenJPEG, at no more than 512 pixels across, so KeyCastr's icon shows | Ferry Core Graphics, loader | done |
| 10 | One new test; `make check` 267 of 267 | Ferry | done |

ShiftIt showed `AUTHORIZATION_INFORMATIVE_TEXT_10_9` because the target
that was built, "ShiftIt NoX11", copies no `Localizable.strings` in its
Xcode project. The build script now takes it from the other target;
Ferry's lookup was right. Spectacle's accessibility window is 780 by 360
points in its nib, unresizable, with the picture under its buttons
reaching past its bottom edge, and Ferry shows it as a Mac does. MacPass's
inspector opens at its 200-point minimum, narrower than its tabs and its
password row need, which a Mac would widen it for. (1.229 fixed this.) MacDown's layout pull-down in its toolbar shows no
picture, because MacDown takes out the empty item that holds it.
JavaScript functions as blocks and a weak `JSManagedValue` weren't
reached. (1.229 did both.)

## 1.227 "Ferry: Swift programs and a first SwiftUI" (done)

Ferry 0.51.0: programs written in Swift are built for an Intel Mac with
Ferry's SDK and run, Swift and Objective-C call each other in one
program, and SwiftUI programs open their windows. The SwiftUI is Ferry's
own, drawn with Ferry's AppKit. Swift's runtime and standard library are
the open-source Swift project's (swift-6.1.3-RELEASE), built unchanged
for a Mac by a script, with a swift.org toolchain for Linux. Neither the
toolchain nor that build is needed to build or run Ferry itself, and the
Swift tests skip without them. Four open-source SwiftUI apps were
surveyed, along with the Swift in Gas Mask and Hex Fiend; none links yet.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Swift's runtime and standard library. `swift/build-runtime.sh` builds them from Swift's own source with `ferry-cc` and the toolchain's compiler, aimed at `x86_64-apple-macosx`, into `frameworks/swift`. Ferry serves that copy to a program that links `/usr/lib/swift/libswiftCore.dylib`. Ferry's Objective-C runtime does what Swift's runtime asks of a Mac's: classes made while the program runs (generic ones included) are realized, a class can be looked up before Swift has made it, and generic classes get their names when asked. The Swift-class bit in an older build's class data is moved to where the stable ABI keeps it | Ferry runtime, Objective-C runtime | done |
| 2 | `sdk/ferry-swiftc` builds Swift programs and libraries as `ferry-cc` builds C, with Objective-C interoperability on, so `import AppKit` reads the SDK's module map. An `@main` type starts the program. `-import-objc-header` takes an app's bridging header, and `-emit-objc-header-path` writes the header that shows its `@objc` classes to Objective-C (Xcode's `App-Swift.h`). An rpath of `@executable_path` or `@loader_path` with nothing after it now works | Ferry SDK, loader | done |
| 3 | The SDK as Swift reads it. API notes for Foundation and AppKit give Swift's names where its own rules don't arrive at Apple's, and give nullability: `NSControl.StateValue`, `NSView.AutoresizingMask` (`.width`, `.height`), `UserDefaults.set(_:forKey:)`, `uintValue`, `separator()`, `statusItem(withLength:)` and others. Some class methods became class properties (`systemStatusBar`, `mainBundle`). `NS_ENUM` and `NS_OPTIONS` carry the attributes that make them Swift enums and option sets. The Bessel functions are left out of `math.h` for Swift, which has its own | Ferry SDK | done |
| 4 | The overlays, Ferry's own: ObjectiveC (`Bool`, selectors, `==` and hashing); CoreGraphics (`CGFloat`, geometry); and Foundation, where `String`, `Array`, `Dictionary`, `Set` and numbers bridge to and from their NS classes, `Error` meets `NSError`, and `NSLocalizedString`, `TimeInterval` and `NSDictionary`'s subscript are given. `Date`, `URL`, `Data`, `UserDefaults` and the like are still the NS classes. Swift's own strings hash as Ferry's do, so they work as `NSDictionary` keys (`foundation/SwiftSupport.m`) | Ferry Foundation | done |
| 5 | Ferry's SwiftUI, written from Apple's documentation and drawn with AppKit controls: | Ferry SwiftUI | done |
|   | - views: `Text`, `Image(systemName:)` (as a text symbol), `Label`, `Button`, `Toggle`, `TextField`, `SecureField`, `Slider`, `Stepper`, `Picker`, `ProgressView`, `Spacer`, `Divider`, `Menu` and `Color` | | |
|   | - containers: `VStack`, `HStack`, `ZStack`, the lazy stacks, `LazyVGrid`, `Grid`, `GroupBox`, `ScrollView`, `List`, `Form`, `Section`, `ForEach` and `NavigationStack` | | |
|   | - state: `@State`, `@Binding`, `ObservableObject` with `@Published`, `@ObservedObject`, `@StateObject`, `@EnvironmentObject`, `@Environment` and `@AppStorage` | | |
|   | - modifiers: padding, frames, fonts, colours, `disabled`, `onAppear`, `onChange`, `help` and `keyboardShortcut`. The styles are accepted. Gestures, hover and `@FocusState` are accepted but don't act yet | | |
|   | - scenes: `WindowGroup`, `Window`, `Settings` (Command-comma) and `MenuBarExtra` (a status item and its menu), with `commands` and `CommandMenu` | | |
|   | - AppKit both ways: `NSHostingView` and `NSHostingController` put SwiftUI in an AppKit program; `NSViewRepresentable`, with its coordinator, puts an AppKit view in SwiftUI; `@NSApplicationDelegateAdaptor` | | |
|   | Each pass works out the views' bodies again and turns them into a tree, and the AppKit views are kept from pass to pass by their place in it. Layout follows SwiftUI's proposal rules, in Swift. A window grows to fit its content | | |
| 6 | A survey of open-source SwiftUI apps (TomatoBar, Spaceman, Maccy, Ice) and of the Swift in Gas Mask and Hex Fiend. Of the SwiftUI names they use, Ferry now has 40 of TomatoBar's 42, 35 of Spaceman's 39, 51 of Gas Mask's 57, 71 of Maccy's 97 and 82 of Ice's 106. TomatoBar was compiled, with its two packages' calls stubbed; all 94 of the errors left are in Foundation, AppKit, Dispatch and UserNotifications, and none is in SwiftUI. Hex Fiend's Swift reads all of Hex Fiend's headers through its bridging header and stops at 14 places | Ferry | done |
| 7 | Eight new tests (Swift's standard library, Foundation bridging, an AppKit window, three SwiftUI programs with their buttons pressed, NSHostingView, and Objective-C using a Swift class); `make check` 270 of 270 | Ferry | done |

SwiftUI next: Swift's concurrency library (`@MainActor`, `Task`) and a
Dispatch overlay, built for Ferry as the runtime is. Then Foundation's
value types (`Date`, `URL` and `Data` as structs) and `Codable` with
`JSONEncoder`, and Combine (OpenCombine). In SwiftUI, shapes,
`GeometryReader`, `overlay`, alerts, sheets and popovers, and
`@Observable`. AppKit's Swift names (`NSImage.Name`,
`NSFont.Weight`, `NSAttributedString.Key`) in an AppKit overlay. Then
TomatoBar and Gas Mask.

## 1.226 "Ferry: Sequel Pro" (done)

Ferry 0.50.0: Sequel Pro linked into a bundle and run, the seventh app.
Its MySQL framework, SPMySQL, was built from its source against MariaDB
Connector/C, which was built from its own source with Ferry's SDK. Sequel
Pro opens its connection window, and pressing Connect for a server that
isn't there brings up its "Connection failed!" sheet with the client
library's own message. Counted with one survey script over the same
clones as 1.225 (627 files), the files that compile went from 543 to 582,
and Sequel Pro's from 150 to 188 of 190.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Sequel Pro links and runs. MariaDB Connector/C 3.4 was built from its source as a static library, without TLS and with its hashes from CommonCrypto. SPMySQL, QueryKit and PSMTabBar were built from Sequel Pro's source. The other frameworks Sequel Pro ships built (Growl, FeedbackReporter, ShortcutRecorder, UniversalDetector) were used as shipped, and Sparkle came from MacDown's build. On a fresh home it shows its window: the toolbar, the favourites list and the quick connect form with its TCP/IP, Socket and SSH tabs and colour choices. On the next launch Sparkle asks whether to check for updates. Given 127.0.0.1 and port 3306, where no server runs, Connect goes through SPMySQL and Connector/C to a refused socket, and the sheet shows "Can't connect to server on '127.0.0.1'". No server is installed, so no connection was made | Ferry AppKit, Foundation, Security, libSystem | done |
| 2 | The older AppKit names Sequel Pro's files stop at: | Ferry AppKit | done |
|   | - `NSColorList`, `NSMatrix`, `NSSpellChecker`, `NSPICTImageRep` (which reads no PICT data), the token field cell's delegate and print panel accessories | | |
|   | - base coordinates, the layout manager's glyph queries and background layout, `graphicsPort`, the HFS type code calls | | |
|   | - the rest of `NSCell`: its represented object, values set from numbers and taken from other controls, its type, states, `sendActionOn:`, `focusRingType` and comparing | | |
|   | - a window's alpha, which now shows: a window at alpha 0 is kept off screen until it fades in | | |
| 3 | The older Foundation, CoreServices and Security names: | Ferry Foundation, CoreServices, Security, WebKit | done |
|   | - `NSCalendarDate`, with its formats and arithmetic, `NSScriptExecutionContext`, and `NSConnection` between the threads of one program | | |
|   | - CFXML's entity calls, the DriverServices clock (`UpTime`, `AbsoluteToNanoseconds`, durations) and `unimpErr` | | |
|   | - the older keychain calls: items added from an attribute list with an access list, searches by attribute, trusted applications | | |
|   | - `WebHistoryItem` and `WebBackForwardList` | | |
| 4 | What SPMySQL, MariaDB Connector/C and Sequel Pro call in libSystem: | Ferry libSystem, SDK | done |
|   | - `pthread_cancel` (deferred) with cleanup handlers, `memset_pattern4`, `8` and `16`, `getlogin`, `ttyname`, `asl_set_query` and `asl_next` | | |
|   | - libbz2 on Mac `FILE`s, `object_getInstanceVariable` and `object_setInstanceVariable`, `Block_copy` from CoreFoundation | | |
|   | - the headers `memory.h`, `alloca.h`, `complex.h`, `bzlib.h`, `zconf.h`, `netinet/ip.h` and `select` from `unistd.h` | | |
| 5 | Setting a view's frame to the frame it has posts no notification, as on a Mac; Sequel Pro sets the frame again from its observer | Ferry AppKit | done |
| 6 | Four new tests; `make check` 266 of 266 | Ferry | done |

The colours and the font in Sequel Pro's `PreferenceDefaults.plist` were
archived by a Mac's `NSArchiver`, whose format is undocumented and which
Ferry doesn't read, so the build script writes its own values there with
Ferry's `NSArchiver`. Gas Mask and Hex Fiend still can't be linked, since
both have Swift in them. MacPass's window still opens too small for its
inspector, MacDown's toolbar doesn't show, and KeyCastr's Sparkle window
is laid out too tall. JavaScript functions as blocks and a weak
`JSManagedValue` weren't reached.

## 1.225 "Ferry: MacPass and MacDown" (done)

Ferry 0.49.0: MacPass and MacDown linked into bundles, with the frameworks
they bring built from their source, and run. MacPass opens a KeePass
database, unlocks it with its password and shows its groups, entries and
an entry's details. MacDown opens a Markdown document, highlights it in
its editor and shows it as HTML in its preview, and its preferences
window opens. Counted with one survey script over the same clones as
1.224 (627 files), with MacPass's dependencies now checked out where its
build puts them, the files that compile went from 496 to 543 (445 in
1.224, counted before they were checked out).

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | MacPass links and runs. KissXML (on this system's libxml2, whose headers the SDK now lays out where a Mac's SDK has them), TransformerKit, KeePassKit (with Argon2), HNHUi and Sparkle were built from their source as frameworks. Given a database made for the test, MacPass opens it, takes its password, unlocks it, and shows the group in its outline, the entry in its table and the entry's user name, password and URL in its inspector. It doesn't offer Touch ID, since Ferry's Security makes no keys | Ferry AppKit, Foundation, Security | done |
| 2 | MacDown links and runs, with hoedown, LibYAML, GBCli, handlebars-objc, MASPreferences, PAPreferences, JJPluralForm, M13OrderedDictionary and Sparkle built from their source. It opens a Markdown file, highlights it in its editor, renders it in its web view preview (headings, emphasis, lists, quotes, code and tables) and shows Sparkle's first-launch question. Its preferences window opens with its toolbar and General pane. flex isn't on the build machine, so handlebars-objc's lexer was replaced, in the build script and not in Ferry, by a hand-written one that follows the same rules | Ferry AppKit, Foundation, WebKit | done |
| 3 | `ferry-ibtool` reads the older xib format (`<archive type="com.apple.InterfaceBuilder3.Cocoa.XIB">`), whose objects are already written out with their keys. MASPreferences ships its window in that format | Ferry SDK | done |
| 4 | Nib loading. A class swapper or a custom view hands its place to the object it makes before that object is decoded, so an object that refers back to it, such as a table's columns, gets the table. A window controller can name its nib by overriding `windowNibName`. Grid views can come from a nib or be made in code. An editable text field has no width of its own, as on a Mac | Ferry AppKit, Foundation | done |
| 5 | What MacPass, MacDown and their frameworks call: | Ferry Foundation, AppKit, Security, WebKit, libSystem | done |
|   | - a small Core Image (images, the affine transform filter, a context, `NSCIImageRep`); a QR code comes out empty and detectors find nothing | | |
|   | - key-value coding through indexed and unordered accessors, `NSURLComponents`, `getValue:size:` and a boxed `CGSize` | | |
|   | - Apple event descriptors and the event manager, collections searched with options and among indexes, `mutableString`, string transforms (XML hex, fullwidth, marks removed) and full case mapping (`ß` to `SS`) | | |
|   | - `UTType`, `CGImageDestination`, Security transforms' Base64 and Base32 encoders, `SecAccessControl`, MD2 and MD4 | | |
|   | - context menus, titlebar accessories, the window list, file promises and colour spaces | | |
|   | - the older web view's selection, DOM ranges, computed style and a frame's JavaScriptCore context | | |
|   | - `@import Darwin` and `@import ObjectiveC` | | |
| 6 | Two new tests; `make check` 262 of 262 | Ferry | done |

Gas Mask and Hex Fiend still can't be linked, since both have Swift in
them, and Sequel Pro waits for its MySQL framework. `NSMatrix` wasn't
needed: in these two apps only a sample program of DDHotKey, which MacPass carries,
uses it. JavaScript functions as blocks and a weak `JSManagedValue`
weren't reached.

## 1.224 "Ferry: shortcuts, asset catalogues and KeyCastr" (done)

Ferry 0.48.0: the running apps' global shortcuts pressed and answered,
asset catalogues compiled, and a fourth app, KeyCastr, linked and run.
Counted with one survey script over the same clones as 1.223 (627 files),
the files that compile went from 435 to 445.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Global shortcuts reach the running apps. Each of Spectacle's 18 shortcuts, pressed through freemac's desktop, moves and sizes the focused window as on a Mac, and Flycut's opens its bezel. An agent app (`LSUIElement`) isn't made active by starting. `frontmostApplication` is the app whose window Wayfire has focused, so Spectacle acts on that app's window. A control whose class keeps its state in a cell of the app's own (ShortcutRecorder's recorder) gets that cell. `TransformProcessType` changes the activation policy | Ferry AppKit, Carbon | done |
| 2 | `ferry-actool`, which compiles an Xcode asset catalogue (`.xcassets`) into an index of Ferry's own beside the image, colour and data files, and the app icon into an `.icns` file named in Info.plist. `imageNamed:`, `colorNamed:` and `NSDataAsset` look there first. Spectacle's status item shows its picture. A Mac's compiled catalogue (`Assets.car`) isn't read, and image stacks and symbol sets aren't compiled | Ferry SDK, AppKit | done |
| 3 | KeyCastr links and runs, with ShortcutRecorder and Sparkle 2 built from their source and its three visualizer plug-ins. It shows its status item and Sparkle's first-launch question. It shows no keystrokes, because Wayland lets no app read another app's keys, so its event tap is never made | Ferry AppKit, Foundation | done |
| 4 | What KeyCastr, Sparkle 2 and ShortcutRecorder call: | Ferry Foundation, AppKit, libSystem | done |
|   | - CoreFoundation's notification centers (`CFMachPortCreate` gives `NULL`), `os_trace` and `os_activity` | | |
|   | - an `NSXPCConnection` that never connects: its error handler gets `NSXPCConnectionInvalid` | | |
|   | - bookmarks, plists read from URLs and data searched backwards and anchored | | |
|   | - window frames saved by name, tool-tip rects, tab stops, catalogue colours and three- and nine-part images | | |
|   | - `renamex_np`, `O_NOFOLLOW_ANY`, the Mac's `struct timeval` in `utimes` and `futimes` | | |
|   | - launchd's job calls and authorization rights, all refused | | |
|   | - `+[NSBundle bundleWithIdentifier:]` for loaded frameworks | | |
|   | - JSON with a comma before a closing bracket, as ShortcutRecorder's style files have | | |
|   | - one object for each input source | | |
| 5 | MacDown's libraries, hoedown, LibYAML and GBCli, built into frameworks from their source and run: Markdown becomes HTML, YAML is parsed and options are read. With them in place, 21 of MacDown's 36 files compile. MacDown doesn't link yet: handlebars-objc's lexer needs flex, and its other libraries aren't built | Ferry Foundation, AppKit | done |
| 6 | Four new tests and three extended; `make check` 260 of 260 | Ferry | done |

Gas Mask and Hex Fiend still can't be linked, since both have Swift in
them. MacPass waits for KeePassKit, KissXML (on libxml2) and HNHUi, and
Sequel Pro for its MySQL framework. `@import Darwin`, JavaScript functions
as blocks and a weak `JSManagedValue` weren't reached.

## 1.223 "Ferry: linking the apps and running them" (done)

Ferry 0.47.0: three of the nine apps linked into bundles with Ferry's SDK
and run, and what they and their updater needed added. Counted with one
survey script over fresh clones of the apps (627 files), the files that
compile went from 395 to 428. Flycut, Spectacle and ShiftIt start, put
their status items and menus in the menu bar and open their windows.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Flycut links and runs. It needed Core Services' Apple events (descriptors, lists, records, object specifiers, and events sent to the app's own handlers), Launch Services, the Process Manager for the app itself, `FSGetCatalogInfo`, `SecTask`, a CloudKit framework with no iCloud account, `CFLocale`, `CFDate`, `CFDateFormatter` and `CFError`, and number and date formatters and decimal numbers in nibs. It shows its first-launch alert, then its status item with its icon, and its menu | Ferry CoreServices, CloudKit, AppKit | done |
| 2 | Spectacle and ShiftIt link and run, each with Sparkle built from Sparkle's own source. They needed Scripting Bridge (which finds no scriptable app), icon references, `objc_msgSend` with the old dispatch prototypes, Cocoa bringing in Application Services, and the Touch Bar's classes (never shown). Both show their status items, menus and preferences windows. Without the accessibility say, Spectacle opens its own window asking for it, and ShiftIt asks again with each Recheck, as on a Mac | Ferry AppKit | done |
| 3 | What Sparkle calls: `fts`, `statfs`, `asl` and `os_log`; uniform type identifiers; `NSURLDownload`; process activities; a bundle's localizations; base64's line options; the File Manager's copy; IOKit's power assertions (its registry is empty); NSWorkspace's file operations; authorization, which never grants a right; and public keys from PEM with Security's verify transforms, which check an update's DSA signature. Delta updates need xar, Apple's own library, which isn't built | Ferry libSystem, Foundation, Security | done |
| 4 | `ferry-ibtool`, which compiles a xib in the document format Interface Builder saves into a nib Ferry's AppKit loads. It covers windows and panels, menus, the common controls and cells, boxes, tab, split, stack, scroll, table and outline views, cell-based and view-based, custom views, the app's own classes, outlets, actions, bindings and runtime attributes. An element it doesn't know is made as a plain view of its class, with a warning. It compiled 108 of the apps' xibs; the two in the older archive format are refused, and storyboards aren't compiled | Ferry SDK | done |
| 5 | kqueue's `EVFILT_VNODE` (`NOTE_WRITE`, `NOTE_DELETE`, `NOTE_RENAME`, `NOTE_ATTRIB`, `NOTE_EXTEND`, `NOTE_LINK`, `NOTE_REVOKE`), dispatch's vnode sources on top, and `O_EVTONLY`, on inotify, for Gas Mask's file watcher. `O_SYMLINK` opens a link itself | Ferry libSystem | done |
| 6 | Foundation brings in Core Services, as on a Mac. The Core Data models test, which had a `write` of its own, renamed it | Ferry Foundation | done |
| 7 | The apps' own frameworks, compiled from their source: KeePassKit, which MacPass is built on, went from 54 to 68 of its 96 files with `NSCountedSet`, `uuid_t` and a few `NSData`, `NSNumber`, `NSIndexSet` and `NSString` calls. hoedown, libyaml and GBCli, which MacDown uses, compile whole, hoedown once `strings.h` was added | Ferry Foundation, SDK | done |
| 8 | Twelve new tests; `make check` 256 of 256 | Ferry | done |

The other six apps aren't linked yet: the table in `docs/ferry-compat.md`
lists what stops each. MacPass and MacDown wait for their own frameworks,
Gas Mask and Hex Fiend have Swift in them, and Sequel Pro waits for its
MySQL framework. Global shortcuts are kept but never pressed, so none of
the three running apps answers its keys yet.

## 1.222 "Ferry: modules, Auto Layout, FSEvents, Quick Look and JavaScriptCore" (done)

Ferry 0.46.0: the next things that stopped the nine apps' sources from
compiling, most-used first. Counted again with one survey script before and
after this work, the files that compile went from 369 of 608 to 383 of 608.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Modules: `@import Foundation;` and the rest, as KeyCastr's and Flycut's sources begin. `ferry-cc` turns modules on for Objective-C, using a module map of the SDK (`sdk/gen-modulemap.sh`) in which each module links its own framework. `#import <Cocoa/Cocoa.h>` becomes a module import, and a header's macros still reach the program. Clang's module cache is kept apart for each version of the map | Ferry SDK | done |
| 2 | Auto Layout. It covers `NSLayoutConstraint`, anchors, layout guides, the visual format language, `NSDictionaryOfVariableBindings`, priorities, intrinsic sizes with hugging and compression resistance, and constraints in nibs. A solver sets the views' frames from the constraints, one axis at a time, higher priorities winning. A required constraint that can't be met is left out with a note, as a Mac logs it | Ferry AppKit | done |
| 3 | Accessibility. It covers the `NSAccessibility` attribute, role, subrole, action and notification names and the protocol's methods, the older informal methods, and HIServices' `kAX` names. There's no screen reader, so a value an app sets is kept and read back, and views, windows and the application answer what they know of themselves | Ferry AppKit | done |
| 4 | `NSFontDescriptor`: a font's attributes and traits, descriptors that become fonts through the installed families' faces, a font's own descriptor, and `applyFontTraits:range:` | Ferry AppKit | done |
| 5 | FSEvents through this system's inotify. A stream watches its folders and the folders inside them, and coalesces what it hears by path over the stream's latency. It hands the events to the callback on a run loop or a dispatch queue, by folder or by file, with the flags for what happened, `FSEventStreamFlushSync` and the extended data | Ferry CoreServices | done |
| 6 | Quick Look and `Quartz/Quartz.h`. `QLPreviewPanel` finds its controller in the responder chain, moves between items with the arrow keys and closes with Escape or Space. Each preview shows the file's icon, name and size, then its picture, the start of its text or a larger icon; `QLPreviewView` shows the same preview. `QLThumbnailImageCreate` and the generator calls are there too. `QCView` can't run a Quartz Composer composition, and says so once | Ferry Quartz | done |
| 7 | `NSRuleEditor`: rows from the delegate's criteria, as pop-ups, labels and the delegate's views, with buttons that add and remove rows. It has nested rows, the `rows` binding and the predicate built from the rows. It came with the text view's selection granularity and the underline pattern names | Ferry AppKit | done |
| 8 | JavaScriptCore. The C API is passed to this system's JavaScriptCore (libjavascriptcoregtk-4.1, which WebKitGTK uses), opened on a program's first call. The Objective-C API is built on it: `JSContext`, `JSValue` with the structure and property calls, `JSExport` and `JSExportAs`, blocks called from scripts, `JSVirtualMachine` and `JSManagedValue`. A system without the library ends the program at its first call, with a message saying so | Ferry JavaScriptCore | done |
| 9 | Thirteen new tests; `make check` 244 of 244 | Ferry | done |

The apps still don't all compile; the table in `docs/ferry-compat.md` lists
what stops each one. Most of MacPass's files wait for KeePassKit and HNHUi,
which are the app's own frameworks and have to be built from its source.
None of the apps was linked or run.

## 1.221 "Ferry: building the nine apps again" (done)

Ferry 0.45.0: each of the nine apps' source files compiled against Ferry's
SDK, and what stopped them added, most-used first. Files that compile went
from 139 of 637 to 418 of 637.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The headers every app includes before anything else: `TargetConditionals.h`, `Availability.h` and `AvailabilityMacros.h`, `sys/cdefs.h`, the BSD types and the Mac's limits (`PATH_MAX`, `MAXPATHLEN`, `sys/param.h`), `inttypes.h`, `zlib.h` (with `-lz`), `mach-o/loader.h`, `malloc/malloc.h`, `libgen.h`, `bitstring.h`, `sys/xattr.h`, Core Foundation's and Foundation's own headers by name, and the `NS_` and `CF_` macros; libSystem's malloc zones and sizes, `basename` and `dirname`, extended attributes, `scandir` and the `long double` maths | Ferry SDK, libSystem | done |
| 2 | Keyboard layouts: the current input source, `UCKeyTranslate` with the English (US) layout, the virtual key codes and modifier glyphs, the symbolic hotkey mode and `GetKeys`, which Flycut, Spectacle, KeyCastr and MacPass use to name their shortcuts' keys | Ferry Carbon | done |
| 3 | File references: `FSRef` from a path and back, `CFURLGetFSRef`, `CFURLCreateFromFSRef` and moving to the trash with `FSMoveObjectToTrashSync` | Ferry CoreServices | done |
| 4 | `NSArchiver` and `NSUnarchiver`, and `NSCoder`'s calls without keys (`encodeValueOfObjCType:at:`, `encodeObject:`, `decodeObject` and the rest), in keyed archives too; a Mac's own typedstream archives aren't read | Ferry Foundation | done |
| 5 | `NSMapTable`, `NSHashTable` and `NSPointerArray`, with weak keys, values and pointers that go when their objects do | Ferry Foundation | done |
| 6 | Foundation's other missing names: searching without accents or widths, collections that copy their items, stable sorts with options, the byte-order functions, JSON through streams, the run loop's ordered performs, the defaults' volatile domains, the file manager's delegate, `NSScriptCommand` (which stopped 19 of Sequel Pro's files), Mach's `boolean_t`, `TRUE` and `FALSE`, and older names of options | Ferry Foundation | done |
| 7 | AppKit's missing names: the tracking and modal run loop modes, `NSAppKitVersionNumber`, the older names of masks and styles, modal sessions, focus rings and rectangle lists, more system colours, the text storage's edits, the layout manager's rectangles, the button cell's highlight and state masks, a cell's menu and hit testing, the field editor's calls, `cancelTracking` and the menu tracking notifications, more image names, and `NSAppearance` | Ferry AppKit | done |
| 8 | Core Graphics functions and shadings (`CGFunctionCreate`, `CGShadingCreateAxial`, `CGShadingCreateRadial`, `CGContextDrawShading`), which Sequel Pro's tab bar draws with | Ferry Core Graphics | done |
| 9 | Eight new tests; `make check` 231 of 231 | Ferry | done |

The apps still don't all compile: the table in `docs/ferry-compat.md` lists
what stops each. Sequel Pro's own MySQL framework and MacPass's KeePassKit
and other frameworks are the apps' own code, built from their source; none
of the apps was linked or run, and the WebKit items (downloads, cookies,
request bodies and DOM events) weren't reached.

## 1.220 "Ferry: other apps' windows, posted keys, drag and drop in tables" (done)

Ferry 0.44.0: what 1.219 left over from the nine apps' calls.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Quartz Window Services: `CGWindowListCopyWindowInfo`, `CGWindowListCreate`, `CGWindowListCreateDescriptionFromArray`, the window info keys and `CGWindowLevelForKey`; other apps' windows come from Wayfire's IPC and are listed only for an app the user let control other windows; an app's own windows always; pictures of an app's own windows | Ferry ApplicationServices | done |
| 2 | Posting events: `CGEventCreateKeyboardEvent`, `CGEventPost`, `CGEventPostToPid`, event sources, flags, fields and the Unicode string; keys go through Strata's `press-key` behind the same consent; mouse and scroll events, and event taps, are refused with a warning | Ferry ApplicationServices, Strata IPC | done |
| 3 | Dragging rows of a table and items of an outline within the app, with the data source's drag methods, drop proposals retargeted with `setDropRow:dropOperation:` and `setDropItem:dropChildIndex:`, the drop shown as a ring or a line; `NSDraggingSession`, `beginDraggingSessionWithItems:event:source:` and the older `dragImage:at:offset:event:pasteboard:source:slideBack:` | Ferry AppKit | done |
| 4 | Core Foundation's sets and bags, with callbacks of their own | Ferry Core Foundation | done |
| 5 | `NSDocument` as a file presenter: it reads its file again after a coordinated write and follows a move | Ferry AppKit | done |
| 6 | Dials > Privacy & Security > Control Other Windows and its question say the answer also covers listing windows and pressing keys | freemac shell | done |
| 7 | A window that a window controller owns is no longer released when it closes, as NSWindow's documentation says; it was released twice when its document closed, which crashed `appkit_autosave` at exit for some lengths of the home folder's path | Ferry AppKit | done |
| 8 | Four new tests; `make check` 223 of 223 | Ferry | done |

Dragging out of the app (or into it from another app), drag images, promised files, mouse posting, event taps, pictures of other apps' windows and typing text with a keyboard layout other than US English aren't done, and none of the apps was run again.

## 1.219 "Ferry: the calls apps make next" (done)

Ferry 0.43.0: what a search of the nine apps' source found them calling that Ferry didn't have, most-used first.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Child windows that move, hide and close with their parent; panels that hide while their app isn't active; ignoring the mouse, collection behaviour and the other window properties menu-bar apps set | Ferry AppKit | done |
| 2 | Login items through `LSSharedFileList` and `SMLoginItemSetEnabled`, kept as autostart entries that Dials > Login Items lists; a ServiceManagement framework | Ferry Foundation | done |
| 3 | The file calls: directory enumerators, display names, attributes, links, URL resource values and reachability, the freedesktop.org trash, bundle resources by URL, `NSFileCoordinator` and file presenters | Ferry Foundation | done |
| 4 | Strings in some seventy-five encodings, a file's encoding found from its bytes, and Core Foundation's encoding calls | Ferry Foundation | done |
| 5 | Text walked by line, paragraph, word, sentence and composed character; Unicode normalization; character-set searches; the older percent escapes | Ferry Foundation | done |
| 6 | Core Foundation's arrays and dictionaries with callbacks of their own and the rest of their calls, `CFUUID`, more of `CFURL` and `CFString`, the bundle keys | Ferry Core Foundation | done |
| 7 | `NSAssert` and its kin with `NSAssertionHandler`; the garbage-collection calls | Ferry Foundation | done |
| 8 | `NSAffineTransform`, with paths transformed and their elements read back, and arcs between lines | Ferry Foundation, AppKit | done |
| 9 | Nine new tests; `make check` 219 of 219 | Ferry | done |
| 10 | The older `WebView` on a busy computer: the page's helper script could start after the web view had given it its number, so it never reported scrolling or subframe loads (`webkit_frames` failed 14 of 32 parallel runs, now 0); the number is now left on the page for the script to pick up | Ferry WebKit | done |
| 11 | A Messages test that failed when run just after midnight | Tests | done |

Table views' drop retargeting, `NSArchiver`, listing other programs' windows and posting events aren't done yet, and none of the apps was run again.

## 1.218 "Messages: firewall, login, tapbacks and attachments" (done)

Messages closes its main gaps: the phone gets through the Firewall, Messages starts at login, and bubbles carry tapbacks, pictures and files.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | With Firewall on, turning the phone on lets KDE Connect in (UDP 1716, TCP 1716–1764) from the local network only, and turning it off closes them again, through the system helper's new `kde-connect on\|off` under the existing polkit action; `firewall on` puts the rules back while the phone is on, and Settings > Phone offers Let Phone Through Firewall… when they're closed | **Messages**, system helper | done |
| 2 | "Start Messages when you log in", on by default once a backend is set up: an autostart file runs `freemac-messages --background` with no window, so new messages arrive and notify | **Messages** | done |
| 3 | Tapbacks: BlueBubbles' associated messages kept one per person per message and shown on the bubble's corner, a notification when someone reacts to yours, and a bubble's right-click menu (Copy, and the six tapbacks when the server's Private API is on) to add one or take it back | **Messages** (messages_store.py, messages_bluebubbles.py) | done |
| 4 | Sending pictures and files: a paperclip button and drag and drop, through BlueBubbles' documented attachment upload and as an MMS through KDE Connect (version 2 `sms.request` with attachments, or kdeconnectd's `sendWithoutConversation`) | **Messages** (messages_bluebubbles.py, messages_kdeconnect.py) | done |
| 5 | Pictures shown inline as thumbnails: sent ones from the file, BlueBubbles ones fetched when a conversation opens, and the phone's own thumbnails | **Messages** | done |
| 6 | A typing bubble from BlueBubbles' `typing-indicator` event | **Messages** (messages_bluebubbles.py) | done |
| 7 | Tests: the system helper's rules against a stand-in ufw (nothing on the real firewall), uploads as the server reads them, tapbacks, typing over the websocket, MMS to the stand-in phone and kdeconnectd, the menu, tray, pictures, login start and firewall asks, headless | Tests | done |
| 8 | docs/messages.md, guide topic | Docs, Guide | done |

## 1.217 "Ferry: frames and the DOM in web views" (done)

Ferry 0.42.0: the rest of the older `WebView` that Markdown editors like MacDown build their previews on.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `WebFrameView` and its document view, with the page's size and scroll position, and scrolling from the app | Ferry WebKit | done |
| 2 | Over forty DOM classes (`DOMDocument`, `DOMElement`, `DOMHTMLElement`, `DOMNodeList` and their kin), kept in step with the page | Ferry WebKit | done |
| 3 | Subframes: `childFrames`, names, `findFrameNamed:` and each subframe's loads reported | Ferry WebKit | done |
| 4 | The resource load delegate, user style sheets, and `window.open` asked of the policy delegate and given a real window | Ferry WebKit | done |
| 5 | Two new tests; `make check` 206 of 206 | Ferry | done |
| 6 | A rare stall fixed in Ferry's dispatch worker pool: when several blocks were queued at once while one worker sat idle, only that worker was woken, and if its block waited on a later one nothing else ever ran (`foundation_locks` hung about once in sixty runs) | Ferry | done |

Downloads, the cookie store, POST requests and DOM events aren't done yet.

## 1.216 "Messages" (done)

Messages: conversations in bubbles, with real iMessage through BlueBubbles on a Mac you own and an Android phone's texts through KDE Connect.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Messages: a sidebar of conversations with search and New Message (⌘N), a conversation pane with bubbles (blue iMessage, green SMS/RCS, grey for the other side), time lines between bursts, Sending…/Sent/Delivered/Read/Not Delivered under what you sent, big emoji on their own, an emoji button and a send button | **Messages** | done |
| 2 | iMessage through BlueBubbles: server address and password, conversations, messages, sending into a conversation or to new addresses, attachments on click, and live new-message, delivered and read events over Socket.IO (polling every 15 seconds without a websocket) | **Messages** (messages_bluebubbles.py) | done |
| 3 | An Android phone's texts over KDE Connect: freemac's own client for the open protocol (UDP and TCP discovery, TLS with its own certificate, protocol 8, pairing with a code checked on both screens, the phone's certificate kept and checked), conversations, history, sending, new texts as they come, and MMS attachments | **Messages** (messages_kdeconnect.py) | done |
| 4 | A kdeconnectd already running is used over D-Bus instead, so the phone never sees two computers | **Messages** | done |
| 5 | An offline store (SQLite in ~/.local/share/freemac/messages), so conversations show at once and survive restarts; the BlueBubbles password in the keychain, or a file only you can read without one | **Messages** (messages_store.py) | done |
| 6 | A first-run screen that explains both ways plainly: real iMessage needs a Mac running BlueBubbles, and an iPhone can't send texts through KDE Connect | **Messages** | done |
| 7 | Notifications for new messages (a click opens the conversation), an unread count on the Dock icon, and Messages stays open with no window, as Post does | **Messages**, Pier, Strata | done |
| 8 | An original speech-bubble icon, a place in the Dock after Post and in Marina | Art, Pier | done |
| 9 | Tests with a stand-in phone over localhost TLS and a stand-in BlueBubbles server (HTTP and websocket), the store, and the window's building and bubble layout, headless | Tests | done |
| 10 | Guide topic, README row | Guide, Docs | done |

## 1.215 "Ferry: global hotkeys and moving windows" (done)

Ferry 0.41.0: Mac window managers and clipboard apps do their main jobs on freemac's desktop, with the user's say.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `RegisterEventHotKey` bound by Strata, with each press sent only to the app that registered it | Ferry Carbon, Strata | done |
| 2 | Carbon event handlers and global and local key monitors for those hotkeys | Ferry Carbon, AppKit | done |
| 3 | The Accessibility API for windows: focused app and window, title, position, size, minimize, full screen and raise, through Wayfire's IPC | Ferry ApplicationServices | done |
| 4 | Asked once per app ("Allow … to control other windows?"), and changed in Dials > Privacy & Security | Shell, Dials | done |
| 5 | `NSScreen` for every display, with visible frames, from Wayfire | Ferry AppKit | done |
| 6 | Four new Ferry tests against a stand-in Wayfire and nine shell tests; `make check` 204 of 204 | Ferry, Shell | done |

Reading other apps' key presses in general (KeyCastr) stays out of reach by design, and what is inside other apps' windows isn't there.

## 1.214 "Ferry: web pages in Mac apps" (done)

Ferry 0.40.0: Mac apps can show web pages, drawn by this system's WebKitGTK inside their own windows.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `WKWebView` with its configuration, data stores, loading, back and forward, and key-value observing | Ferry WebKit | done |
| 2 | Scripts with results as Foundation objects, content worlds, user scripts and message handlers | Ferry WebKit | done |
| 3 | The navigation and UI delegates: policies, alerts, confirms, prompts, new windows and snapshots | Ferry WebKit | done |
| 4 | The older `WebView` with `WebFrame`, `WebDataSource`, `WebPreferences` and `WebScriptObject` | Ferry WebKit | done |
| 5 | GTK's web view placed over its `NSView`, clipped, following moves and taking the keyboard; WebKitGTK opened only on first use | Ferry AppKit, host | done |
| 6 | Ten new tests on a display of their own; `make check` 200 of 200 | Ferry | done |

Downloads, the cookie store, the DOM classes and `WebFrameView` aren't done yet.

## 1.213 "Ferry: tracking areas, shadows and other programs" (done)

Ferry 0.39.0: views that follow the mouse, shadows that are drawn, animations, and Mac apps that talk to their other copies.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSTrackingArea`, tracking and cursor rectangles, and `NSCursor` on GTK's cursors | Ferry AppKit | done |
| 2 | Shadows drawn by Core Graphics under shapes, images, gradients, text and layers, so `NSShadow` shows | Ferry Core Graphics | done |
| 3 | `NSAnimation` and `NSViewAnimation`, blocking and not, with curves and progress marks | Ferry AppKit | done |
| 4 | `NSDistributedNotificationCenter` between Ferry programs on the D-Bus session bus, and `NSRunningApplication` | Ferry Foundation, AppKit | done |
| 5 | `NSMutableCharacterSet`, the rest of `NSCharacterSet` and percent encoding; `NSTextAttachment`; `NSAppleScript`, which answers an error | Ferry Foundation, AppKit | done |
| 6 | Eleven new tests, and the notification test's order made fixed; `make check` 190 of 190 | Ferry | done |

AppleScript itself, the notifications a Mac's system posts, and layer shadows aren't done.

## 1.212 "Ferry: collection views and rulers" (done)

Ferry 0.38.0: grids of items, as in MacPass's icon picker, and rulers such as Sequel Pro's line numbers.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSCollectionView` with a data source, reused items, the flow and grid layouts, and selection by mouse and keys | Ferry AppKit | done |
| 2 | Inserting, deleting, moving and reloading items and sections, alone or in batch updates | Ferry AppKit | done |
| 3 | The older collection view with a content array, an item prototype copied from a nib, and bindings | Ferry AppKit | done |
| 4 | `NSRulerView` and `NSRulerMarker` on scroll views, with units, markers and subclasses that draw their own marks | Ferry AppKit | done |
| 5 | Four new tests; `make check` 179 of 179 | Ferry | done |

Nothing in a collection view is animated, and items can't be dragged yet.

## 1.211 "Ferry: expressions and exact decimals" (done)

Ferry 0.37.0: Mac apps can do sums, averages and grouping over their data, and keep money-style numbers exact.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSExpression` and `NSComparisonPredicate` as public classes, with every documented form and the built-in functions | Ferry Foundation | done |
| 2 | `MATCHES` with regular expressions, `SUBQUERY`, arithmetic and substitution variables in predicates | Ferry Foundation | done |
| 3 | `NSDecimalNumber` and the `NSDecimal` functions: exact base-10 arithmetic, rounding modes and exceptions | Ferry Foundation | done |
| 4 | Core Data: exact decimal attributes, aggregates, `propertiesToGroupBy` and `havingPredicate` | Ferry Core Data | done |
| 5 | Three new tests; `make check` 175 of 175 | Ferry | done |

Aggregates and grouping are worked out in memory rather than in SQL, and derived attributes aren't there yet.

## 1.210 "Ferry: gradients, shadows and window layouts" (done)

Ferry 0.36.0: the drawing and window-layout classes that six of the nine test apps use.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSGradient`: along a line, in a rectangle or path at an angle, between circles and from a centre | Ferry AppKit | done |
| 2 | `NSShadow` with its settings, archives and the text attribute (not drawn yet) | Ferry AppKit | done |
| 3 | `NSSplitViewController` and `NSSplitViewItem`: sidebars and inspectors that collapse, holding priorities and thickness limits | Ferry AppKit | done |
| 4 | `NSTabViewController`, with a segmented control or the window's toolbar | Ferry AppKit | done |
| 5 | Four new tests; `make check` 172 of 172 | Ferry | done |

The nine apps weren't run again this time, because their downloads couldn't be fetched here; the fixes were chosen from what their public source code uses.

## 1.209 "Ferry: Core Data" (done)

Ferry 0.35.0: Mac apps can keep their data with Core Data, Apple's framework for saving an app's records.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Models built in code or read from Xcode's `.xcdatamodeld` source, with every attribute type, inheritance and relationships with delete rules | Ferry | done |
| 2 | `NSManagedObject` with `@dynamic` accessors, faults, object IDs and validation | Ferry | done |
| 3 | Contexts: save, rollback, undo, notifications, private-queue and child contexts, merging and the five merge policies | Ferry | done |
| 4 | Fetch requests and `NSFetchedResultsController` | Ferry | done |
| 5 | SQLite, binary and in-memory stores, `NSPersistentContainer`, lightweight migration, batch deletes and updates | Ferry | done |
| 6 | `NSArrayController` and `NSObjectController` in entity mode | Ferry | done |
| 7 | Eleven new tests; `make check` 168 of 168 | Ferry | done |

Compiled models (`.mom` and `.momd`) aren't read yet, so most apps that use Core Data still stop there, with a clear message.

## 1.208 "Dock: word badges and app menus" (done)

The Dock now shows what apps tell it, as a Mac's Dock does.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A badge can hold a word as well as a number, such as "New" or "!", and a long one ends in "…" so the badge stays small | Pier (launcher_badge.py) | done |
| 2 | Mac apps' badge labels that aren't numbers now reach the Dock as words; other docks still see that there is a badge | Ferry (NSDockTile) | done |
| 3 | An app's own Dock menu items, such as New Window, show in its right-click menu in the Dock, below its windows and above the Dock's own items as on a Mac, with separators, greyed-out items, ticks and submenus; choosing one tells the app | Pier (dock_menu.py) | done |
| 4 | The Dock never waits on an app for its menu: if the app is slow or doesn't answer, the usual menu opens | Pier | done |
| 5 | An app asking for attention bounces until you go to it; a quick request bounces once, a whole bounce | Pier | done |
| 6 | Tests for badges, attention and Dock menus, against a stand-in app on a private bus (`python3 -m unittest discover -s shell/tests`) | shell/tests | done |

Apps that send these things the way many Linux apps do (Telegram, Signal, Thunderbird and others) get the same: their badges, their progress bars, their bounce and their Dock menu items.

## 1.207 "Ferry: notifications and Dock badges" (done)

Ferry 0.34.0: Mac apps can pop up notifications, with buttons and replies, and put a badge on their Dock icon or bounce it for attention.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `UNUserNotificationCenter`: requests, time and calendar triggers, categories with actions and text replies, pending and delivered lists, and the delegate's answers | Ferry | done |
| 2 | The older `NSUserNotificationCenter`: deliver, schedule, buttons and replies | Ferry | done |
| 3 | Notifications shown by this system's notification server over D-Bus, with clicks and replies sent back to the app | Ferry | done |
| 4 | `NSDockTile` badges, `requestUserAttention:`, and the app's Dock menu, sent to the Dock as LauncherEntry updates | Ferry | done |
| 5 | Six new tests on a private bus with a stand-in server and Dock; `make check` 157 of 157 | Ferry | done |

Notifications don't stay after the app quits.

## 1.206 "Ferry: printing and the font panel" (done)

Ferry 0.33.0: Mac apps can print and save as PDF, set up the page, and pick fonts, from their File and Format menus as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSPrintInfo`: paper, margins, orientation, scaling and pagination, kept with a document | Ferry | done |
| 2 | `NSPrintOperation`: a view's pages drawn to PDF with Cairo and sent to a file, Preview or a printer; automatic, fit and clip pagination, page headers and footers | Ferry | done |
| 3 | The print and page setup dialogs, as this system's GTK dialogs or sheets; NSDocument's Print… and Page Setup… turned on | Ferry | done |
| 4 | `NSFontManager` and the font panel, with this system's fonts; Bold and Italic in text views | Ferry | done |
| 5 | Text views split across pages; eight new tests; `make check` 151 of 151 | Ferry | done |

Accessory views in the panels, printing only the selection, and font collections aren't there yet.

## 1.205 "Ferry: network connections and streams" (done)

Ferry 0.32.0: Mac apps can open their own network connections, secure or not, and watch them the Mac way, beyond the web requests Ferry already handled.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | BSD sockets with the Mac's structures, flags, socket options and error numbers; name lookups; `select` and `poll` | Ferry | done |
| 2 | `kqueue` and `kevent` on epoll (reads, writes, timers, signals, processes, user events), and libdispatch read, write, signal and process sources | Ferry | done |
| 3 | `CFSocket` and run loop sources; `CFStream` and `NSStream` over data, files, memory, socket pairs and hosts, with delegates, callbacks, run loops or a queue | Ferry | done |
| 4 | TLS on streams through this system's OpenSSL, with the server checked by Security.framework's trust | Ferry | done |
| 5 | `NSNetService` TXT records (publishing and browsing fail cleanly until Bonjour arrives); six new tests; `make check` 144 of 144 | Ferry | done |

Bonjour, TLS servers and client certificates, proxies, and file and Mach port events aren't there yet.

## 1.204 "Ferry: thread-local variables" (done)

Ferry 0.31.0: Mac programs can keep a separate copy of a variable for each thread, which many C++ and newer apps rely on.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Ferry's own `_tlv_bootstrap`: each thread gets its own copy of each image's thread-local variables on first use, in the program, its libraries and libraries opened with `dlopen` | Ferry | done |
| 2 | A fast path that keeps every register the compiler relies on, and a slow path that saves the vector registers too | Ferry | done |
| 3 | C++ `thread_local` objects built on first use and destroyed when their thread ends (`_tlv_atexit`, `__cxa_thread_atexit`); a thread's copies freed when it ends | Ferry | done |
| 4 | Works on pthreads, `NSThread`, `std::thread` and dispatch's worker threads; `dlsym` of a thread-local variable gives the caller's copy | Ferry | done |
| 5 | `ferry-cc` links these programs; six new tests; `make check` 138 of 138 | Ferry | done |

The destructors of threads still running when a program exits aren't run.

## 1.203 "Ferry: C++ programs" (done)

Ferry 0.30.0: Mac programs written in C++ and Objective-C++ run, on the same open-source C++ library a Mac uses.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A Mac's libc++ and libc++abi served by this system's LLVM libc++ and libc++abi, opened only when a program needs them; a clear message naming the packages when they're missing | Ferry | done |
| 2 | C++ exceptions across the program, its own libraries and this system's code, with each Mac image's unwind tables handed to the unwinder | Ferry | done |
| 3 | Objective-C and C++ exceptions passing through each other's frames; ARC objects with C++ ivars and blocks capturing C++ objects | Ferry | done |
| 4 | `std::thread`, mutexes, condition variables, futures and promises, streams and `ctype` on a Mac's layouts, and the wide-character and locale calls libc++ needs | Ferry | done |
| 5 | `ferry-cc` builds `.cpp` and `.mm`; six new tests; `make check` 131 of 131 | Ferry | done |

`thread_local` variables and wide file streams aren't supported yet. The libc++ packages are recommended by Ferry's package, so a normal install has them.

## 1.202 "Ferry: real threads" (done)

Ferry 0.29.0: Mac apps run on real threads, so they can do several things at once, as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSThread`, each thread with its own run loop and autorelease pools, and the perform-on-thread calls | Ferry | done |
| 2 | Real `NSLock`, `NSRecursiveLock`, `NSCondition`, `NSConditionLock` and `@synchronized`; the pthread, `os_unfair_lock` and `OSSpinLock` calls Mac programs import | Ferry | done |
| 3 | libdispatch's global queues on a worker pool, and NSOperationQueue running operations at the same time; the main queue stays on the main thread | Ferry | done |
| 4 | The Objective-C runtime and Foundation's shared tables made safe across threads; URL loading on a network thread of its own, with its cookies, cache and sign-ins locked | Ferry | done |
| 5 | Four new tests and three rewritten so their output doesn't depend on timing; `make check` 125 of 125, three runs in a row | Ferry | done |

AppKit stays main-thread only, as on a Mac; Ferry warns once when an app draws from another thread. A wait that can never end now stops the app with a message instead of hanging.

## 1.201 "Ferry: asking about the system and loading plug-ins" (done)

Ferry 0.28.0: Mac apps can check which macOS version they're on, ask about the computer, and load plug-ins.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `sysctl`, `sysctlbyname` and `sysctlnametomib` for the version, CPU, memory and own-process names apps read, agreeing with macOS 14.7 and the real machine | Ferry | done |
| 2 | `dlopen`, `dlsym`, `dladdr` and friends for Mac programs, with libraries and bundles loaded after start-up | Ferry | done |
| 3 | `@available` checks (`__isPlatformVersionAtLeast` and the older calls) answering for 14.7 | Ferry | done |
| 4 | NSBundle and CFBundle plug-ins that really load, with their principal class and function lookup | Ferry | done |
| 5 | `getattrlist`, `proc_pidpath` and the Mach host and task statistics; four new tests; `make check` 121 of 121 | Ferry | done |

## 1.200 "Ferry: keychain, encryption and the updater checks" (done)

Ferry 0.27.0: Mac apps can keep passwords in a keychain, encrypt and hash data, and get past the start-up checks that their updaters make.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | CommonCrypto: MD5, SHA-1 and SHA-2 digests, HMAC, PBKDF2 and random bytes of Ferry's own, AES (ECB, CBC, CTR) through OpenSSL, checked against published test vectors | Ferry | done |
| 2 | Security.framework keychain: `SecItem` and the older `SecKeychain` calls for generic and internet passwords, kept per user in `~/.local/share/ferry/keychain` (readable only by you, encrypted against casual reading, not against someone with your account) | Ferry | done |
| 3 | Code signing: an app's check of its own signature passes; all other code reads as unsigned, since Ferry can't check Apple's signatures | Ferry | done |
| 4 | Certificate trust (`SecCertificate`, `SecPolicy`, `SecTrust`) against the system's certificate store, and in NSURLSession's server-trust challenges | Ferry | done |
| 5 | One macOS version, 14.7, in `SystemVersion.plist`, `NSProcessInfo`, `Gestalt` and `uname`; ten new tests; `make check` 117 of 117 | Ferry | done |

## 1.199 "Ferry: redirects, sign-ins, cookies and caching" (done)

Ferry 0.26.0: Mac apps' web requests behave like a browser's, remembering cookies, answering password prompts and reusing pages they already fetched.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Redirects followed one at a time, with the app's delegate able to follow, change or refuse each; what 301 to 308 do to a POST; `currentRequest` | Ferry | done |
| 2 | HTTP Basic and Digest sign-ins through `NSURLCredential`, `NSURLProtectionSpace`, `NSURLAuthenticationChallenge` and `NSURLCredentialStorage`; a delegate can accept an https certificate the system doesn't trust | Ferry | done |
| 3 | `NSHTTPCookie` and `NSHTTPCookieStorage`, with lasting cookies saved per program | Ferry | done |
| 4 | `NSURLCache` in memory and on disk, every request cache policy, revalidation with `ETag` and `Last-Modified` | Ferry | done |
| 5 | `data:` URLs; six new tests; `make check` 107 of 107 | Ferry | done |

## 1.198 "Ferry: Core Animation" (done)

Ferry 0.25.0: Mac apps get layers and animation, so views can fade, slide and round their corners.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | QuartzCore.framework with `CALayer` geometry, its tree, key-value coding and drawing (backgrounds, borders, rounded corners, opacity, contents, transforms) | Ferry | done |
| 2 | Shape, gradient and text layers | Ferry | done |
| 3 | `CATransaction`, implicit animations through the documented action lookup, and basic, keyframe, spring and group animations stepped on the main run loop | Ferry | done |
| 4 | Layer-backed and layer-hosting `NSView`s, `updateLayer`, `NSAnimationContext` and the views' `animator` | Ferry | done |
| 5 | Three new tests; `make check` 101 of 101 | Ferry | done |

## 1.197 "Ferry: XML documents" (done)

Ferry 0.24.0: Mac apps can read, change and write whole XML documents.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSXMLDocument` read from a string, data or a file into a tree of `NSXMLNode`s and `NSXMLElement`s, on this system's libxml2 | Ferry | done |
| 2 | The tree walked and changed (children, attributes, namespaces, values), and every change seen by XPath and by what is written | Ferry | done |
| 3 | Written out compact, pretty printed or canonical, in UTF-8, UTF-16, ISO Latin 1 or ASCII; DTDs and their declarations; validation while reading | Ferry | done |
| 4 | Strings turned into ASCII or ISO Latin 1 data for real, instead of UTF-8 | Ferry | done |
| 5 | One new test and more string checks; `make check` 98 of 98 | Ferry | done |

## 1.196 "Ferry: loading web addresses" (done)

Ferry 0.23.0: Mac apps can fetch from the web, for update checks, feeds and downloads.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSURLSession` data, upload and download tasks, with completion handlers or delegates, cancel and invalidation | Ferry | done |
| 2 | `NSURLConnection`, `NSURLRequest`, `NSHTTPURLResponse` and the usual `NSURLErrorDomain` errors; redirects and gzip handled | Ferry | done |
| 3 | `NSData` and `NSString` read straight from web addresses | Ferry | done |
| 4 | Done by this system's libcurl, opened only when an app first loads a URL; Ferry's package recommends it | Ferry | done |
| 5 | Two new tests against a local test server, and a check that libcurl stays unopened otherwise; `make check` 97 of 97 | Ferry | done |

## 1.195 "Ferry: the rest of the everyday controls" (done)

Ferry 0.22.0: the controls Mac apps' windows use that Ferry lacked.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSStepper`, `NSLevelIndicator` (continuous, discrete, relevancy and rating stars) and `NSColorWell` with a basic colour panel | Ferry | done |
| 2 | `NSDatePicker`: typed and stepped part by part, or a month calendar and a clock | Ferry | done |
| 3 | `NSComboBox`, `NSPopover` (view controllers can be shown as popovers) and `NSPathControl` | Ferry | done |
| 4 | `NSSound`, played through PipeWire, with the Mac's alert sound names mapped to freemac's own sounds; and `NSTokenField` | Ferry | done |
| 5 | All of them read from nibs with their targets and actions; one new test, `make check` 94 of 94 | Ferry | done |

## 1.194 "Ferry: tools, regular expressions and XML" (done)

Ferry 0.21.0: the Foundation pieces Mac apps use to run helper tools,
search text, read XML and queue work.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSTask`, `NSPipe` and `NSFileHandle`: a Mac app can run this system's programs, or a Mac helper through Ferry, and read their output | Ferry | done |
| 2 | `NSRegularExpression` and `NSScanner`, with patterns matched by this system's ICU, as on a Mac | Ferry | done |
| 3 | `NSXMLParser` on this system's libxml2, as on a Mac | Ferry | done |
| 4 | `NSOperationQueue` and its operations, the locks, `NSCache` and `NSProgress`, on Ferry's one thread | Ferry | done |
| 5 | Six new tests; `make check` 93 of 93 | Ferry | done |

## 1.193 "Quick Note" (done)

A small note that opens over whatever you're doing, like Quick Note on a
Mac, and a clearer message when Ferry can't run a Mac app.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Quick Note: a small floating note in the bottom right of the screen, kept on top, saved as you type in Jot's Quick Notes folder, with buttons to open it in Jot or start another | Jot | done |
| 2 | Quick Note from a hot corner (Dials > Dock and Menu Bar > Hot Corners), from File > New Quick Note in Jot, or with `freemac-jot --quick` | Hot Corners, Jot | done |
| 3 | Opens the last quick note again, or with File > Always Resume to Last Quick Note off, only one closed in the last five minutes | Jot | done |
| 4 | Jot lists quick notes with the others, marked Quick Note | Jot | done |
| 5 | A Mac app that Ferry can't run keeps its output in `~/.cache/freemac/ferry/<app>.log`, and the notice says what went wrong from its last line | Ferry | done |

## 1.192 "Bosun" (done)

An app for shortcuts, like Shortcuts on a Mac: steps put together and run
with one click, from the Services menu, from Drawer or with keys.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Bosun: shortcuts as coloured tiles with a play button; an editor with the steps in order, each with its settings, and a list of steps to add, by category, with search | Bosun | done |
| 2 | 29 steps: text (change case, replace, count, clipboard, speak, show, notify), files (get, open, show in Drawer, zip, PDF, rotate, resize, copy, wallpaper), apps and web pages, and the computer (appearance, volume, mute, Do Not Disturb, screenshot, lock, wait, shell script) | Bosun | done |
| 3 | A Gallery of nine shortcuts to start from | Bosun | done |
| 4 | Shortcuts that take words or files in every app's Services menu and in Drawer's menu, and keys for any shortcut in Dials > Keyboard > Bosun Shortcuts | Services, Dials | done |
| 5 | The lock screen and screen saver show English day and month names in the region's date order, whatever the session's older language settings say | Latch, screen saver | done |

## 1.191 "Ferry: controllers from nibs and checked edits" (done)

Mac programs whose windows come from a nib with array, tree, object or
dictionary controllers bound to tables, outlines and fields now work with
no code of their own, and a value the program refuses is not saved.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSArrayController`, `NSTreeController`, `NSObjectController` and `NSDictionaryController` loaded from nibs with their settings, joined up by the nib's bindings | Ferry AppKit | done |
| 2 | View-based tables and outlines make their cell views from the nib's prototypes; a cell view's `objectValue` is its row's object, and fields bound to `objectValue.key` work both ways | Ferry AppKit | done |
| 3 | Values checked with `validate<Key>:error:` before they are written; a refused one shows the program's error and the old value comes back | Ferry AppKit | done |
| 4 | Controls turn off when there is nothing selected, the controller can't be edited, or several different values are selected; content options for deleting, selecting all and whole-array values | Ferry AppKit | done |
| 5 | Ferry 0.20.0, 87 tests | Ferry | done |

## 1.190 "Ferry: tree controllers and outline bindings" (done)

Mac programs that keep a tree of items in a tree controller and show it in
an outline view, expanded, sorted, selected and edited through bindings,
now work the way they do on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSIndexPath`, and `NSTreeNode` children, parents and index paths | Ferry Foundation, AppKit | done |
| 2 | `NSTreeController`: children, count and leaf key paths; arranged nodes kept across changes so open rows stay open; selection by index path, `selection.key`; sorting; add, insert, add child, insert child, remove and move | Ferry AppKit | done |
| 3 | Outline views bound to a tree controller: rows expanded and collapsed, selection both ways, sorting by a column title, edited cells written back; per-row `editable` and `enabled` column bindings | Ferry AppKit | done |
| 4 | `NSDictionaryController`: key and value pairs, included, excluded and localized keys, add and remove | Ferry AppKit | done |
| 5 | Ferry 0.19.0, test `appkit_tree_controller` (85 tests) | Ferry, Docs | done |

## 1.189 "Language & Region" (done)

Dates, times, numbers and money can be written the way the person's own
country writes them, chosen in Dials as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The image generates 48 regions' locales and writes in US English by default (it was C.UTF-8) | Build | done |
| 2 | Dials > Language & Region: region, first day of week, temperature and measurement system, with live date, time, number and currency examples and a Log Out button | Dials | done |
| 3 | The session gives every app the region's formats (LC_TIME, LC_NUMERIC, LC_MONETARY and the rest, checked before use), while menus stay in English | Session | done |
| 4 | freemac's calendars, the menu bar clock, the other clocks and Sky follow the region at once; day and month names stay English in freemac's own apps | Shell | done |
| 5 | Computers installed before 1.189 get a region made the first time it is chosen, after an administrator's password (`freemac-system-helper region`) | System helper | done |
| 6 | Guide topic, README row and screenshot | Docs | done |

## 1.188 "Ferry: array controllers and table bindings" (done)

Mac programs that keep a list in an array controller and show it in a
table, sorted, filtered and edited through bindings, now work the way they
do on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSArrayController`: content from an array, a set or a binding; arranged objects filtered and sorted; selection by index or object, with next and previous; `selection.key` with the multiple, no-selection and not-applicable markers; add, insert and remove, with the usual options | Ferry AppKit | done |
| 2 | Table columns bound to `arrangedObjects.key`: rows, values, sorting by a click on the column title, the selection both ways, and edited cells written back | Ferry AppKit | done |
| 3 | `mutableSetValueForKey:`, the collection operators (`@count`, `@sum`, `@avg`, `@min`, `@max` and the unions) and a subset of `NSPredicate` for filtering | Ferry Foundation | done |
| 4 | Ferry 0.18.0, tests `foundation_kvc_collections` and `appkit_array_controller` (84 tests) | Ferry, Docs | done |

## 1.187 "Tint" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Tint, a new utility in the spirit of a Mac's colour meter: the pixels around the pointer enlarged, with the colour and its red, green and blue values, a few times a second | tint.py | done |
| 2 | Values as 0–255, percentages or hex (View menu); Aperture size averages up to an 11 × 11 square | tint.py | done |
| 3 | Color menu: Hold Color (⇧⌘H), Lock Position (⌘L), Copy Color as Text (⇧⌘C) and Copy Color as Image (⌥⌘C) | tint.py | done |
| 4 | Where the display draws the pointer into the picture (no hardware cursor, as in many virtual machines), Strata says so and Tint reads the spot again with the arrow hidden for a moment once the pointer rests | strata-shell, tint.py | done |
| 5 | Icon, guide topic, README row and screenshot | Art, Guide, Docs | done |

## 1.186 "Folder backgrounds" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | View Options > Background in icon view: White, Color (with a colour well) or Picture (Choose… a picture), as on a Mac | drawer.py, drawer_background.py | done |
| 2 | Each folder keeps its own background, and it follows the folder when it's renamed; the Trash, searches and other views stay plain | drawer_background.py | done |
| 3 | A picture fills the window and stays put while the icons scroll; on a dark colour or picture the names turn white | drawer_background.py | done |
| 4 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.185 "Show Clipboard" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Edit > Show Clipboard in Drawer: one window showing the files, picture or words on the clipboard, with what kind they are at the bottom | drawer.py, drawer_clipboard.py | done |
| 2 | It changes as soon as anything is copied in any app; very long text is cut short and big pictures are shrunk to fit | drawer_clipboard.py | done |
| 3 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.184 "Ferry: observing, bindings and formatters" (done)

Mac programs whose windows follow their data by themselves, through
key-value observing and Cocoa bindings, and fields that only take numbers
or dates, now work the way they do on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Automatic key-value observing: an observed object's setters announce changes, with dependent keys, the Prior, Initial, Old and New options, nested changes, key paths through a replaced object, and array changes at indexes | Ferry Foundation | done |
| 2 | Two-way bindings on text fields, buttons, pop-up buttons and the new slider, with placeholders and the value transformers; `NSObjectController`, `NSUserDefaultsController` and bindings made from nibs | Ferry AppKit | done |
| 3 | Formatters on fields, cells and table cells: shown, edited, checked as you type, with a beep and the delegate's say when text can't be read | Ferry AppKit | done |
| 4 | Ferry 0.17.0, tests `foundation_kvo_auto`, `appkit_formatters` and `appkit_binding_controls` (82 tests) | Ferry, Docs | done |

## 1.183 "Summary Info" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | File > Get Summary Info (⌃⌘I): one Info window for everything chosen, with how many items, their kind (or Multiple kinds), their size all together with folders added up, and where they are | drawer.py, drawer_summary.py | done |
| 2 | Tags and Locked set from it go on every item; Locked shows a dash when only some are locked; aliases are left unlocked, as in Get Info | drawer_summary.py | done |
| 3 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.182 "Back and Forward lists" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Press and hold Back or Forward in Drawer, or right-click it, for the folders it goes through, nearest first; choosing one jumps straight there and keeps the rest to go back or forward to | drawer.py | done |
| 2 | A quick click still goes one folder; holding shows the list instead of going | drawer.py | done |
| 3 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.181 "Recent Folders" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Go > Recent Folders: the last ten folders opened in Drawer, newest first, shared by every Drawer window; choosing one opens it in the window | drawer.py, recent_folders.py | done |
| 2 | Folders that have gone are left out; the Trash, Recents, tags, searches and Network never go in; two folders with one name show the folder each is in | recent_folders.py | done |
| 3 | Clear Menu empties the list; menu bars take submenus | drawer.py, menus.py | done |
| 4 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.180 "Inspector and Copy as Pathname" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | File > Show Inspector (⌥⌘I): one Info window that changes with the selection in Drawer, kept at the right of the screen above other windows, scrolling when it's long; ⌥⌘I again closes it | drawer.py, drawer_info.py | done |
| 2 | Edit > Copy as Pathname (⌥⌘C): the chosen items' full paths on the clipboard, one a line | drawer.py | done |
| 3 | Holding Option turns the shortcut menu's Get Info into Show Inspector and Copy into Copy “item” as Pathname | drawer.py | done |
| 4 | Guide topics, README rows and screenshots | Guide, Docs | done |

## 1.179 "Sharing and permissions" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Get Info's Sharing and permissions becomes a Name and Privilege table: the owner (Me), the group and everyone, each Read & Write, Read only or No Access, with a pop-up when the item is yours | drawer_info.py, permissions.py | done |
| 2 | A folder's read follows into opening it; a file keeps whether it is a program; Write only (Drop Box) is shown when an item has it | permissions.py | done |
| 3 | Apply to Enclosed Items… asks first, then gives everything inside the folder its privileges, deepest first, leaving aliases, locked items and other people's items alone | drawer_info.py, permissions.py | done |
| 4 | A locked item shows the privileges it gets back when unlocked and can't be changed until then | drawer_info.py, permissions.py | done |
| 5 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.178 "Ferry: editing tables and autosave" (done)

Mac programs that keep lists you type into, and document apps that save as
you go, now behave the way they do on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Editing text cells in place in tables and outline lists: double click, Return, Tab and Shift-Tab between cells, Escape to cancel, `editColumn:row:withEvent:select:`, with the data source's and delegate's calls; in view-based tables the cell's own text field | Ferry AppKit | done |
| 2 | `NSDocument` autosaving in place on a timer, untitled documents kept in Autosave Information, the window staying edited | Ferry AppKit | done |
| 3 | Revert To > Last Saved Version for autosaving documents, and closing or quitting without asking once autosaved | Ferry AppKit | done |
| 4 | Ferry 0.16.0, tests `appkit_editing` and `appkit_autosave` (79 tests) | Ferry, Docs | done |

## 1.177 "Change picture" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Change picture in Dials > Wallpaper: never, every 5, 15 or 30 minutes, every hour, every day, or when logging in | dials.py, wallpaper_rotate.py | done |
| 2 | Pictures from freemac's own wallpapers (day or night version to match the mode), the Pictures folder or any folder; Random order shuffles them | dials.py, wallpaper_rotate.py | done |
| 3 | Backdrop checks once a minute and once per session at login, and writes the new picture as the wallpaper, so the Dials tiles follow it | backdrop.py, dials.py | done |
| 4 | Picking one wallpaper by hand turns Change picture off | dials.py | done |
| 5 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.176 "Locked files and folders" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A Locked tick box in Get Info, for items you own: locking takes away writing, so no app can change a locked file and nothing goes into or out of a locked folder; unlocking gives back the permission it had | drawer_info.py, locks.py | done |
| 2 | A small padlock on a locked item's icon in Drawer and on the Desktop, as soon as it is ticked | drawer.py, desktop_icons.py | done |
| 3 | Moving a locked item to the Trash asks first (Stop or Continue); renaming one says it is locked | drawer.py, desktop_icons.py | done |
| 4 | A locked item's icon and comments can't be changed in Get Info until it is unlocked | drawer_info.py | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.175 "List view options" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | View Options (⌘J) shows the options of the view in front, and changes with it: in list view, Show Columns ticks Date Modified, Size and Kind on or off | drawer.py | done |
| 2 | Use relative dates: Today 9:19 AM and Yesterday, or the full date and time with a wider column | drawer.py | done |
| 3 | Calculate all sizes adds up each folder in the background, "Adding up…" until done, and sorting by Size then puts the biggest folders first | drawer.py | done |
| 4 | Each choice is kept for every Drawer window and the next start | drawer.py | done |
| 5 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.174 "Custom icons and comments" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Click the icon in Get Info and paste a picture (⌘V), or drop a picture or picture file on it, to give a file or folder its own icon; Delete takes it off, ⌘C copies it | drawer_info.py, custom_icons.py | done |
| 2 | Drawer and the Desktop show the icon of its own in place of the kind's, an alias shows its original's with the arrow, and they change as soon as it is pasted | drawer.py, desktop_icons.py | done |
| 3 | A Comments box in Get Info keeps a few words with the item, in the freedesktop.org comment attribute, so they move with it | drawer_info.py, comments.py | done |
| 4 | Seek finds files by their comments, whatever kind of file they are | seek_index.py | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.173 "Ferry: calendars and number formats" (done)

Mac programs that show dates by week or month, money, percentages, file
sizes or how long something takes lean on Foundation's calendar and
formatter classes; Ferry now has them.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSCalendar` (Gregorian and ISO 8601) and `NSDateComponents`: a date's parts in any time zone, dates from parts, adding months and days across month ends and daylight saving changes, differences, starts of days and weeks, weekends and the next matching date | Ferry Foundation | done |
| 2 | `NSNumberFormatter` in every style (decimal, percent, currency, accounting, scientific, spelled out, ordinal), with rounding, grouping and patterns, reading numbers back; `NSByteCountFormatter` for file sizes | Ferry Foundation | done |
| 3 | `NSISO8601DateFormatter`, "Yesterday", "Today" and "Tomorrow" in `NSDateFormatter`, and `NSDateComponentsFormatter` for durations such as "1 hr, 5 min" | Ferry Foundation | done |
| 4 | `NSLocale` knows each country's currency; Ferry 0.15.0, tests `foundation_calendar`, `foundation_numbers` and `foundation_iso8601` (77 tests) | Ferry, Docs | done |

## 1.172 "Aliases" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | File > Make Alias in Drawer and on the Desktop, and the right-click menus, make "name alias" beside the item; holding ⌥⌘ while dragging makes the alias where you drop it | aliases.py, drawer.py, desktop_icons.py | done |
| 2 | An alias shows the original's icon with a small curved arrow, its Kind is Alias, and double-clicking opens the original, even a folder in the same window | aliases.py, drawer.py, desktop_icons.py | done |
| 3 | Show Original (⌘R) opens the original's folder with it chosen, from Drawer or the Desktop | drawer.py, desktop_icons.py | done |
| 4 | An alias whose original is gone says so when opened, with Delete Alias and Fix Alias… to choose a new original | aliases.py | done |
| 5 | Get Info on an alias says where its original is, with Select New Original… | drawer_info.py | done |
| 6 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.171 "Definitions in Seek" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Type a word in Seek and a Definition result shows its first meaning, with up to four meanings (noun, verb, adjective, adverb) in the preview beside it, as Spotlight does | seek.py, words.py | done |
| 2 | Plurals and other forms find their word (mice finds mouse, running finds run), read straight from the dictionary's sorted files, so a result shows while you type | words.py | done |
| 3 | Return opens the word in Words | seek.py | done |
| 4 | Dials > Seek can turn Definitions off like the other kinds of result | seek_settings.py | done |
| 5 | Guide line, README row and screenshot | Guide, Docs | done |

## 1.170 "Ferry: messages passed on, JSON and dates" (done)

Many larger Mac programs pass messages on to other objects, read and write
JSON, and show dates in the computer's time zone; Ferry now has the pieces
they're built on.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | `NSMethodSignature` and `NSInvocation`: build a message, send it to any object and read its answer, for every kind of argument a PC's calling rules pass (whole numbers, decimals, small and large structures, more arguments than fit in registers) | Ferry Foundation | done |
| 2 | Messages an object doesn't know are offered to `forwardInvocation:` before the program stops, as on a Mac; `NSProxy` stands in for another object | Ferry runtime, Foundation | done |
| 3 | `NSUndoManager prepareWithInvocationTarget:` records the change to undo, with groups and redo | Ferry Foundation | done |
| 4 | `NSJSONSerialization`: read and write JSON in UTF-8, UTF-16 or UTF-32, pretty-printed or with sorted keys, with a Mac's errors | Ferry Foundation | done |
| 5 | `NSTimeZone` from the computer's own time zone files, a simple `NSLocale`, and `NSDateFormatter` writing and reading every date pattern, in English (United States) | Ferry Foundation | done |
| 6 | Ferry 0.14.0, tests `foundation_invocation`, `foundation_json` and `foundation_dates` (74 tests) | Ferry, Docs | done |

## 1.169 "Accessibility Shortcuts" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Option-Command-F5 anywhere opens a small panel listing the accessibility features, with a tick by each one that's on; a click, or the arrow keys and Space, turns one on or off, and Done or Escape closes it | a11y_shortcuts.py (new), wayfire.ini | done |
| 2 | It covers the screen reader, Zoom, Sticky Keys, Slow Keys, Mouse Keys, the Accessibility Keyboard, Hover Text, Invert Colours, Colour Filters (the filter chosen last), Increase Contrast and Reduce Transparency, each the same setting Dials changes, and follows changes made while it's open | a11y_shortcuts.py | done |
| 3 | Dials > Accessibility > Accessibility Shortcuts ticks which features the panel lists; with only one ticked, the keys turn it on or off at once, with no panel, as on a Mac | dials_more.py | done |
| 4 | The shortcut is in Dials > Keyboard, reaches accounts made before it, and the panel stays out of the Dock | dials_keys.py, Dock | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.168 "Open in Web" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | File > Open in Web in a website's own window opens the page it's on in Web, as a Mac's web apps open theirs in Safari | webapps.py, fallback_menus.py, Topline | done |
| 2 | The page is found in the website's own history by its window's title (an unread count in front of it is allowed for), else the last page it visited, else its address in the Dock | webapps.py | done |
| 3 | Guide line and README row | Guide, Docs | done |

## 1.167 "Ferry: documents, alerts and the workspace" (done)

Mac programs run through Ferry that open, edit and save files (text editors,
password managers, drawing apps) get the document classes they're built on,
with the alerts and sheets that go with them.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Documents (`NSDocument`, `NSDocumentController`): the app's document types from its Info.plist; New, Open, Save, Save As, Save To, Revert and Duplicate; saved safely beside the file first; Open Recent with Clear Menu | Ferry AppKit | done |
| 2 | Edits through `NSUndoManager` set the window's edited dot; closing an edited document asks Save, Cancel or Don't Save in a sheet; quitting with unsaved documents asks to review them | Ferry AppKit, Foundation | done |
| 3 | Alerts (`NSAlert`): message and details, buttons with Return, Escape and ⌘D, the caution style, "Don't ask again" and an extra view; run on their own or as a sheet in the window; `presentError:` | Ferry AppKit | done |
| 4 | `NSWorkspace`: open web addresses, files and folders with freemac's own apps, file icons from the icon theme, apps found by identifier or name; it never starts another Mac app | Ferry AppKit | done |
| 5 | Ferry 0.13.0, test `appkit_documents` (69 tests); README screenshots | Ferry, Docs | done |

## 1.166 "Unread counts on websites in the Dock" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A website in the Dock shows the count its title gives, such as Facebook's "(3) Facebook" or a mail site's "Inbox (12)", in a red badge on its icon, as a Mac shows on web apps | webapps.py, Dock | done |
| 2 | It changes as the title does and goes when the site is closed; Show badges in Dials > Dock and Menu Bar turns it off with the others | Dock | done |
| 3 | Guide lines, README row and screenshot | Guide, Docs | done |

## 1.165 "Add to Dock for websites" (done)

A website such as Facebook can sit in the Dock and open like an app, as Safari's
File > Add to Dock does on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | File > Add to Dock… in Web: the site's own name and its largest icon (from its manifest, touch icon or favicon), drawn on a rounded tile, or its first letter on a coloured tile when it has none | webapps.py (new), fallback_menus.py, Topline | done |
| 2 | The website goes in the Dock and Applications at once and opens in its own window, without the address bar or tabs, with its own sign-in; its name and menus show in the menu bar | webapps.py, apps.py, Dock | done |
| 3 | Options > Delete Web App… in the Dock asks first, quits it if it's open, and removes it with its sign-in | Dock, webapps.py | done |
| 4 | The desktop portal (xdg-desktop-portal, GTK backend) that Web uses to make web apps, set up for each session | Build | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.164 "Ferry: toolbars, pop-up lists and search fields" (done)

Mac programs run through Ferry get the controls most Mac windows have along
their top: a toolbar, pop-up lists, segmented buttons and a search field.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Pop-up lists and pull-down lists (`NSPopUpButton`): the menu opens over the button with the chosen item lined up; chosen by click, by press, drag and release, or the keys and typing; disabled items passed over | Ferry AppKit | done |
| 2 | Segmented controls (`NSSegmentedControl`), such as Day, Week and Month: select one, select any and momentary, with a segment's own menu and the arrow keys | Ferry AppKit | done |
| 3 | Search fields (`NSSearchField`): searching as you type, at once or on Return, the clear button and Escape, and recent searches kept in the search menu | Ferry AppKit | done |
| 4 | Stack views (`NSStackView`), laid out by Ferry itself: gravity areas, distributions, alignments, spacing, hidden views and views dropped when room runs short | Ferry AppKit | done |
| 5 | Toolbars (`NSToolbar`): items from the program or its nib, icon and label modes, show and hide, validation, a chevron menu for items that don't fit, and the layout saved | Ferry AppKit | done |
| 6 | Ferry 0.12.0, test `appkit_controls` (68 tests) | Ferry | done |

## 1.163 "Lifeboat in the menu bar" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Once a backup drive is chosen, a lifebuoy sits in the menu bar, as a Mac shows its backups there; it turns slowly while a backup runs | lifeboat_menu.py (new), Topline | done |
| 2 | Its menu says when the latest backup was made, how far the one running has got, or why the last one didn't finish, and asks for the drive when it isn't plugged in | lifeboat_menu.py | done |
| 3 | Back Up Now, or Skip This Backup while one runs; Browse Lifeboat Backups; Lifeboat Settings… | lifeboat_menu.py | done |
| 4 | Show Lifeboat in menu bar in Dials > Dock and Menu Bar; "1 minute ago" in Dials > Lifeboat instead of "1 minutes ago" | Dials | done |
| 5 | Guide lines, README row and screenshot | Guide, Docs | done |

## 1.162 "Now Playing and Seek in the menu bar" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | While an app plays music or a video, or has it paused, a music note shows in the menu bar, and goes away when it stops | now_playing_menu.py (new), media.py | done |
| 2 | Its menu: the album cover, the track, the artist and album, the app, a line with the time gone and left, and back, play or pause, and forward | now_playing_menu.py | done |
| 3 | Seek's magnifying glass beside Quick Settings, as Spotlight's is on a Mac; a click opens Seek as ⌘Space does | now_playing_menu.py | done |
| 4 | Dials > Dock and Menu Bar: Show Now Playing and Show Seek in menu bar | Dials | done |
| 5 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.161 "Focus menu and the menu bar's icons" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The Focus symbol in the menu bar is a menu, as on a Mac: the four Focuses with the one on in blue and until when a schedule keeps it on, a click to switch or turn it off, and Focus Settings… | focus_menu.py (new), Topline | done |
| 2 | Dials > Dock and Menu Bar: Show Wi-Fi, Bluetooth, Sound, Battery and Focus in menu bar, as a Mac's Control Centre settings choose; Topline hides or shows each at once | Dials, Topline | done |
| 3 | Quick Settings opens Dials for Wi-Fi or Bluetooth when that symbol isn't in the menu bar | quick.py | done |
| 4 | Guide topic, Focus guide, README row | Guide, Docs | done |

## 1.160 "Quick Settings drawn as a Mac's Control Centre" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Each module is a round symbol, blue while it's on, beside its name and how it stands, on a light tile, as in a Mac's Control Centre; a click on the symbol switches it | quick.py | done |
| 2 | Wi-Fi and Bluetooth show a chevron; a click on their words opens the Wi-Fi menu (1.153) or the Bluetooth menu (1.158) from the menu bar, or Dials when that symbol is hidden | quick.py, topline.py | done |
| 3 | A click on the words of the other modules switches them, as before | quick.py | done |
| 4 | Guide topic, README screenshot retaken | Guide, Docs | done |

## 1.159 "Ferry: tables and outlines" (done)

Mac programs run through Ferry can show lists, tables and outlines, the views
most Mac apps are built around.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Table views (`NSTableView`, `NSTableColumn`, `NSTableHeaderView`, `NSTableRowView`, `NSTableCellView`): cell-based tables drawing text, check box, radio and image cells, and view-based tables making views only for the rows in sight and reusing them | Ferry AppKit | done |
| 2 | Columns sized, hidden, moved and resized by dragging the header, by every autoresizing style and to fit; header clicks sort, with Ferry's own sort arrow | Ferry AppKit | done |
| 3 | Rows of fixed or the delegate's heights, alternating colours, grid lines; inserted, removed and moved, with updates batched | Ferry AppKit | done |
| 4 | Selection by click, shift- and command-click, dragging and the arrow keys, with the delegate's say; clicked row and column, action and double action; regular and source-list highlighting | Ferry AppKit | done |
| 5 | Outline views (`NSOutlineView`): chevrons, indentation, items and rows both ways, opening and closing (whole subtrees too), the delegate's say and notifications, left and right keys | Ferry AppKit | done |
| 6 | Both from nibs, with prototype cell views; `NSIndexSet` and `NSSortDescriptor` in Foundation | Ferry AppKit, Foundation | done |
| 7 | A test that clicks, sorts, resizes, opens and closes them (67 tests) | Ferry tests | done |

## 1.157 "Ferry: menu bar items" (done)

Mac programs run through Ferry put their own items in freemac's menu bar.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Menu bar items (`NSStatusBar`, `NSStatusItem`, `NSStatusBarButton`): each one is offered to the menu bar over StatusNotifierItem, drawn by Ferry from its image (template images in the menu bar's ink), its title or both, at three sizes, or from a custom view | Ferry AppKit | done |
| 2 | An item's menu is read by the menu bar as it opens (dbusmenu): ticks, dimmed items from the app's own menu validation, separators, submenus and hidden items, the menu delegate told before it opens; choosing an item sends its action | Ferry AppKit | done |
| 3 | Clicking an item without a menu sends its button's action; hiding it or removing it takes it out of the menu bar, and a restarted menu bar gets every item again | Ferry AppKit | done |
| 4 | Topline shows an app's picture of words (a title item) at the menu bar's text size rather than shrunk to an icon | extras.py | done |
| 5 | Ferry says why when the processor lacks SSSE3, which Mac programs expect (older PCs and virtual machines on a plain processor), before a program stops with "Illegal instruction" | Ferry | done |
| 6 | A test that reads, opens and clicks two items over a private session bus (66 tests) | Ferry tests | done |

## 1.156 "Menu bar extras" (done)

Apps' own icons in the menu bar, as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Topline keeps the StatusNotifierWatcher registry that Linux apps announce their icons to (or reads another program's, if one already runs), and drops an icon when its app quits or crashes | Topline, extras.py | done |
| 2 | Each icon sits left of freemac's own, newest furthest left, from the app's icon name, its own icon folder or its pixel data; Passive icons are hidden and NeedsAttention ones show the app's attention icon; the tooltip shows the app's title and text | extras.py | done |
| 3 | Click opens the app's menu (read through dbusmenu as it opens, with ticks for check and radio items, submenus and dimmed items), or asks an app without one to open its window; right-click always opens the menu; middle-click and scrolling go to the app | extras.py | done |
| 4 | Guide topic, README row and screenshot | Guide, Docs | done |

## 1.155 "Ferry: tabs and split views" (done)

Ferry, freemac's own layer for simple Intel Mac programs, now comes with every
release, and gains two of the views Mac apps use most.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Every release now has Ferry's package beside the ISO (freemac-ferry_VERSION_amd64.deb), built by the release workflow; double-click it to install it with Slipway. A failed Ferry build doesn't hold up the ISO | release.yml, release-notes.py | done |
| 2 | Tab views (`NSTabView`, `NSTabViewItem`): tabs along the top (or the other edges), selection by click, arrow keys, index or identifier, the delegate's questions, and loading from nibs | Ferry AppKit | done |
| 3 | Split views (`NSSplitView`): vertical and horizontal, thin, thick and pane-splitter dividers, dragging with the delegate's limits, collapsing, holding priorities, and positions saved under an autosave name | Ferry AppKit | done |
| 4 | A crash when a Mac app's window was resized or closed (its drawing surface was let go twice) | Ferry graphics | done |
| 5 | A test of both views, built from a nib, in Ferry's test suite (65 tests) | Ferry tests | done |

## 1.154 "Battery menu" (done)

The menu bar's Battery menu, as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Click the battery in the menu bar for its menu: the charge, Power Source (Battery or Power Adapter), and the time remaining, or Charging with the time until full, Not Charging or Battery Is Charged | Topline, battery_menu.py | done |
| 2 | A Low Power Mode switch that turns it on or off at once; Dials > Battery keeps the finer choices | battery_menu.py, style.py | done |
| 3 | Using Significant Energy: the apps whose processes (and the processes they started) used at least 15% of a processor core over the last half minute, busiest first; click one to open Gauge | energy.py, battery_menu.py | done |
| 4 | A shared menu-bar popup that the Battery menu, and later ones, are built from | menubar_popup.py | done |
| 5 | Guide topic, README rows and screenshots | Guide, Docs | done |

## 1.153 "Wi-Fi menu" (done)

The menu bar's Wi-Fi menu, as on a Mac, and a fix that lets every download join Wi-Fi.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Wi-Fi menu: a switch to turn Wi-Fi off and on, Known Networks first (the one you're on in blue), then Other Networks by signal, with a padlock for those that need a password | Topline, wifi_menu.py | done |
| 2 | Click a network to join it: a saved one joins at once, an open one too, and one with a password asks for it in a window (Join stays off until it's long enough); a wrong password isn't saved and a notification says so | wifi_menu.py | done |
| 3 | Click the network you're on for its IP address, router, security, BSSID, channel, signal and rate, and Disconnect | wifi_menu.py | done |
| 4 | The menu-bar symbol shows the signal while Wi-Fi is joined, off or not joined, and the cable when only a cable is used | wifi_menu.py | done |
| 5 | The downloads lacked wpasupplicant, so NetworkManager could not join any Wi-Fi network; it is now in the image, with wireless-regdb | build/packages | done |
| 6 | Menu-bar menus stay open while the pointer is in them; a free-standing alert has no empty grey band at the top | status.py, alert.py | done |
| 7 | Guide topic, README rows and screenshots | Guide, Docs | done |

## 1.152 "New Image" (done)

Hull's File > New Image, as in a Mac's Disk Utility: blank disk images and copies of drives.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | File > New Blank Image… (⌘N): a name, a size in MB or GB (at least 32 MB) and a format; saved in Documents, then opened as a disk on the Desktop | Hull, disk_images.py | done |
| 2 | File > New Image from Drive…: a byte-for-byte copy of a USB drive, disc or volume into an .img (an .iso for a disc), in Documents, that Restore can put back | Hull, disk_images.py | done |
| 3 | The drive's volumes are unmounted while it's copied and mounted again after; empty space takes no room in the file; a window shows progress and Stop leaves no half-made file | disk_images.py, Hull | done |
| 4 | File menu grouped as on a Mac: Open Disk Image…, the three New Image items, Mount and Eject, Close | Hull | done |
| 5 | Guide topic, README rows and screenshots | Guide, Docs | done |

## 1.151 "Partition" (done)

Hull's Partition, as in a Mac's Disk Utility: divide a drive into several volumes.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A Partition button and Edit > Partition… for a drive that's plugged in (not the system's, a disc or an open image) | Hull | done |
| 2 | A pie chart of the drive: + splits the chosen volume in two, − takes it away, a click chooses a slice and dragging the white dots between slices resizes them | hull_partition.py, partition_plan.py | done |
| 3 | Each volume's name, format (ExFAT, MS-DOS (FAT) or freemac (ext4)) and size, in GB or MB, never under 32 MB; up to eight volumes | hull_partition.py | done |
| 4 | One last question names every volume, then a new GUID partition map is written and each volume made, named and mounted | hull_store.py | done |
| 5 | A drive with several volumes shows each one's share of its bar in colour, with its name and size | Hull | done |
| 6 | Guide topic, README rows and screenshots | Guide, Docs | done |

## 1.150 "First Aid" (done)

Hull's First Aid, as in a Mac's Disk Utility: check a drive for errors and repair them.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A First Aid button and Edit > First Aid… for a volume, or a drive (every volume on it), that isn't the system's, a disc or a read-only image | Hull | done |
| 2 | Unmounts while it checks, repairs only when the check finds errors, and mounts again afterwards if it was mounted | hull_store.py | done |
| 3 | One plain report: no problems, repaired, or problems it couldn't repair (with what to do next); volumes in a format freemac can't check are named | Hull | done |
| 4 | Guide topic, README rows and screenshots | Guide, Docs | done |

## 1.149 "Restore" (done)

Hull's Restore, as in a Mac's Disk Utility: copy a disk image onto a drive, the way to make a USB stick that starts up a system.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Edit > Restore… (⇧⌘R) and a Restore button for a drive that's plugged in: choose an .iso or .img (the chooser opens in Downloads), confirm, and it's copied byte for byte onto the whole drive | Hull, disk_images.py | done |
| 2 | Refused for the system's disks, discs and open disk images; an image bigger than the drive says so before anything is touched | Hull | done |
| 3 | Its volumes are unmounted first (hidden ones too); something still using them is named in plain words | disk_images.py | done |
| 4 | A window with a progress bar, how much is copied, and Stop; a stopped restore explains that the drive holds only part of the image | Hull | done |
| 5 | No password for an administrator at the computer, as for erasing (polkit open-device for drives that aren't the system's) | polkit rules | done |
| 6 | Hull's Open Disk Image… and Hatch's chooser open in Downloads too | Hull, Hatch | done |
| 7 | Guide topic, README rows and screenshots | Guide, Docs | done |

## 1.148 "Applications" (done)

Drawer gets the Mac's Applications folder: the apps on the computer, side by side with your own folders.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Applications in Drawer's sidebar lists every app on the computer, freemac's own and installed ones, with their own icons; a Mac app (.app folder) put there shows as itself | Drawer, app_list.py | done |
| 2 | Double-clicking an app there opens it, as from the Dock | Drawer | done |
| 3 | Get Info (⌘I) on an app: its description, Kind Application, Version, Size (or "Part of freemac"), and Where | Drawer | done |
| 4 | Move to Trash (⌘⌫) on an app explains that apps are removed in Harbor, and that freemac's own can't be | Drawer | done |
| 5 | Go menu shortcuts: Documents ⇧⌘O, Downloads ⌥⌘L, Home ⇧⌘H, Computer ⇧⌘C, Applications ⇧⌘A | Drawer | done |
| 6 | Guide topic, README rows and screenshots | Guide, Docs | done |

## 1.147 "Hatch" (done)

Open a disk image you double-click, as a Mac mounts a .dmg: an .iso or .img becomes a disk on the Desktop and in Drawer, and ejects like a USB drive.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Double-clicking an .iso, .img or .raw opens it as a disk through udisks2 (no password for the person at the computer) and opens its window in front; an .iso, or an image you can't write to, opens read-only; opening it again just shows its window | Hatch, disk_images.py, mimeapps | done |
| 2 | A small "Opening…" window only when opening takes a moment; an image with nothing freemac can read is closed again and says so in plain words | Hatch | done |
| 3 | Ejecting the disk closes the image (the loop device goes away by itself) | disk_images.py | done |
| 4 | Hull: a Disk Images section with the image's file, whether it's writable, and Eject; Erase and Rename are off for read-only images; File > Open Disk Image… (⇧⌘O) | Hull | done |
| 5 | Hull: File > New Image from Folder… (⇧⌘N) makes an .img holding a copy of a folder (ext4, owned by you), then offers to open it or show it in Drawer; system folders and a disk without room are refused | Hull, disk_images.py | done |
| 6 | Drawer brings a window opened by another app to the front, rather than leaving it behind the window you were in | Drawer | done |
| 7 | Apps that hide from the menus, like Hatch, stay out of the Dock's recent apps | Pier | done |
| 8 | Guide topic, README rows and screenshots | Guide, Docs | done |

## 1.146 "Slipway" (done)

Install an app you downloaded, as opening an installer package on a Mac opens Installer.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Double-clicking a downloaded .deb opens Slipway, with Introduction, Installation and Summary steps down the side | Slipway, mimeapps | done |
| 2 | Introduction shows the app's own name and icon (read from the package without installing it), version, size, publisher and description, the website it was downloaded from and when, and what's installed already | slipway_store.py | done |
| 3 | Install through PackageKit after an administrator's password, getting what else it needs from the internet, with progress in words; Reinstall when that version is there; a package for another kind of computer is refused with what to download instead | Slipway, PackageKit | done |
| 4 | Summary: Open the app, and the offer to move the downloaded package to the Trash; a failure says why in plain words, with Try Again | Slipway | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.145 "Startup Disk" (done)

Choose which system the computer starts up from, as a Mac's Startup Disk settings do, for PCs with Windows (or another system) beside freemac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Startup Disk shows each system and disk the firmware can start up from (freemac, Windows, another Linux, a USB stick, a disc), which it starts up from and which one is in use; network boot and the firmware's own tools are left out | Dials, startup_disk.py | done |
| 2 | Restart in… starts up from the chosen one just once (the firmware's BootNext), then the computer goes back to its usual one; Always Start Up from This puts it first in BootOrder; a start-up set for next time only can be cancelled | freemac-startup-disk, polkit | done |
| 3 | The changes go through a root helper after an administrator's password, which only takes entries the page shows | freemac-startup-disk | done |
| 4 | On a PC that starts up the BIOS way the page says where to choose instead; the page names the start-up menu keys PCs use | Dials | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.144 "Power schedule" (done)

Start up or wake the computer at a set time, and sleep, restart or shut it down at another, as a Mac's Energy settings have it.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Battery (or Power) > Schedule…: Start up or wake, and Sleep, Restart or Shut Down, each every day, weekdays, weekends or one day of the week, at a time; the row says what's set | Dials | done |
| 2 | The schedule is the whole computer's, kept in /etc/freemac by a root helper after an administrator's password; it holds at the login screen and for every account | freemac-power-schedule, polkit | done |
| 3 | Starting up uses the computer's clock alarm (RTC), set again at each start-up and after each wake, so it wakes the computer from sleep and, on most PCs, from off | systemd, rtcwake | done |
| 4 | Anyone logged in gets a ten-minute countdown before a scheduled sleep, restart or shut down, with Cancel and a button to do it now; with nobody logged in it happens at once | Topline, power_countdown.py | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |
| 6 | Fixed: after an administrator's password, Users and Privacy & Security kept saying "Waiting for an administrator's password…" and didn't show the change or an error; a Software Update now turns on services added since a computer was installed | Dials, freemac-update-helper | done |

## 1.143 "Tender" (done)

Bring your files over from your old computer, as a Mac's Migration Assistant does.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Tender finds sources on plugged-in drives: the newest Lifeboat backup of each computer, each person's files on a Windows disk, and another freemac or Linux computer's home folders; or any folder you choose | Tender | done |
| 2 | Choose what to bring (Documents, Pictures, Music, Videos, Desktop, Downloads, other files), each with its size, against the free space here; OneDrive's folders come with Windows' | Tender | done |
| 3 | Copying merges and never overwrites: files already here are left alone, a different one with the same name comes over as "name 2", and running it again skips what came before; Windows' own files (AppData, desktop.ini, links) stay behind | Tender | done |
| 4 | Settings and app data from a Lifeboat backup or freemac disk replace this account's, which are kept in .local/share/freemac-tender; Log Out… when done | Tender | done |
| 5 | Bring Files Over… in Welcome, Guide topic, README row and screenshots | Welcome, Guide, Docs | done |

## 1.142 "VPN" (done)

Connect to a workplace's or a VPN provider's network from Dials and the menu bar, as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Network: Add VPN Configuration… from a WireGuard (.conf) or OpenVPN (.ovpn) file; a new VPN waits to be turned on | Dials, vpn.py | done |
| 2 | Each VPN with a switch to connect it, its kind and state, and a button to remove it | Dials | done |
| 3 | The VPN menu in the menu bar: filled while connected; connect or disconnect each VPN; Show VPN status in menu bar | Topline | done |
| 4 | OpenVPN support in the image (WireGuard is built into NetworkManager) | packages | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.141 "Encrypted disk" (done)

Keep everything on the disk unreadable without your password, as a Mac's disk encryption does, for a computer that's lost or stolen.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | "Encrypt your disk?" in the installer: the whole system and your files on an encrypted volume, unlocked with your password on the start-up screen | Keel, keel_backend.py | done |
| 2 | A recovery key, shown once when installing finishes, opens the disk if the password is forgotten; Restart waits until you tick that you've written it down | Keel | done |
| 3 | Dials > Privacy & Security: whether the disk is encrypted, Change Disk Password… and New Recovery Key… (the old key stops working) | Dials, freemac-disk-helper | done |
| 4 | Changing your own login password in Users changes the disk's password too, when they were the same | Dials, freemac-users-helper | done |
| 5 | Guide topic, README row and screenshots | Guide, Docs | done |

## 1.140 "Services" (done)

Select words in any app and send them to another app to do something with them, as on a Mac.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Services in every app's menu in the menu bar: Make New Sticky Note, New Jot Note With Selection, Look Up in Words, Search With Seek, Speak Text, Open URL and Show in Drawer; only those that fit the selected words can be chosen | Topline, services.py, freemac-service | done |
| 2 | ⇧⌘Y makes a sticky note from the selected words, in front of your windows until you click away | Stickies, Wayfire config | done |
| 3 | Services in Drawer's right-click menu: New Terminal at Folder and Set Desktop Picture | Drawer | done |
| 4 | Dials > Keyboard > Services: a shortcut for each service, and a switch to take it off the menu | Dials | done |
| 5 | Jot, Words, Seek and Stickies take words from a service whether they're running or not | Jot, Words, Seek, Stickies | done |
| 6 | New shortcuts and settings from a newer freemac now reach accounts made before it, without changing anything the person set | freemac-config-upgrade, freemac-session | done |
| 7 | Show in Drawer picks out the file in its folder | services.py | done |
| 8 | Fix: Dials sometimes opened on Appearance instead of the page it was asked for | Dials | done |
| 9 | Guide topic, README row, every README screenshot retaken | Guide, Docs | done |

## 1.139 "Screen Time schedules and categories" (done)

Downtime can follow the week, and one limit can cover every app of a kind.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Downtime: Every Day or Custom; Custom gives each day its own hours or none, and a night's downtime runs into the next morning | Logbook | done |
| 2 | The downtime notice and "can be used again at" use that day's hours | Logbook | done |
| 3 | Categories: Logbook adds up each kind of app (Games, Social, Entertainment, Creativity, Education, Information & Reading, Productivity & Finance, Utilities, Other), from the Categories line of each app's .desktop file | Logbook | done |
| 4 | A daily limit on a category counts all its apps together and closes them at the limit, with a notice five minutes before; Add Category Limit… lists the apps it counts | Logbook | done |
| 5 | A parent sets a child's custom downtime and category limits too, and More Time… works for a category | Logbook, freemac-screen-time-helper | done |
| 6 | The window no longer rebuilds itself after its own changes | Logbook | done |

## 1.138 "Screen Time for a family" (done)

A parent sets a child's screen time from the parent's own account, and the child can't change it.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | An administrator picks a family member at the top of Logbook (Me, then everyone else) and sees their day and week | Logbook | done |
| 2 | Manage Screen Time (the parent's password) keeps that person's limits, Downtime and Always Allowed in /etc, where only an administrator can change them; Add Limit… sets a limit on an app not used yet; Stop Managing… gives them back | Logbook, freemac-screen-time-helper, polkit | done |
| 3 | The child's Logbook says a parent manages their screen time and shows the limits without letting them change anything | Logbook | done |
| 4 | When time's up, More Time… asks for a parent's password on the child's screen and gives 15 more minutes (or 15 minutes out of Downtime) for that day | Logbook, freemac-screen-time-grant, polkit | done |
| 5 | A warning when a parent's account has no password, since anyone could then give more time | Logbook, freemac-screen-time-helper | done |
| 6 | Fix: with two people logged in, the second person's menu bar, Dock and Logbook talked to the first person's desktop; each session now has its own Wayfire socket in its runtime folder | freemac-session, wfipc.py, sounds.py | done |
| 7 | Fix: the child's time didn't count while the parent's session was locked | Logbook | done |
| 8 | Fix: a limit's pop-over no longer closes on its own when the list refreshes | Logbook | done |
| 9 | Guide topic, README row, every README screenshot retaken | Guide, Docs | done |

## 1.137 "fast user switching" (done)

A family computer where each person has their own account: someone else can log in while the first person's apps keep running.

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | With more than one account, the menu bar shows your name; its menu lists everyone, with a tick by those logged in, Login Window… and Users & Groups Settings… | Topline (status.py UserMenu), switch_user.py | done |
| 2 | Picking someone locks your session and shows their session, or a login screen with them chosen, on another terminal (8 to 12), started by `freemac-greeter@N.service` | switch_user.py, freemac-switch-helper, systemd, polkit | done |
| 3 | The login screen marks people already logged in; choosing one shows an arrow that goes back to their session, where their own lock screen asks for the password | Gangway | done |
| 4 | Dials > Users: Show fast user switching menu | Dials | done |
| 5 | Banners no longer show over the lock screen (a reminder that stays until it's dealt with hid it); they come back after unlocking | Beacon | done |
| 6 | Guide topic, README row, every README screenshot retaken | Guide, Docs | done |

## 1.136 "lock screen" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Now Playing on the lock screen: the song, its artist and app, with back, play or pause, and skip buttons that work without unlocking | Latch (freemac-latch.c, latch.py), media.py | done |
| 2 | Notifications that come in while locked show under the clock, newest first, as many as fit and then "N more notifications"; a Focus keeps its quiet apps off it too | Latch, Beacon's history | done |
| 3 | Dials > Notifications > Show previews: Always, When Unlocked (as on a Mac) or Never; When Unlocked and Never show only which app sent one on the lock screen, and Never hides the words in banners and the Notification Centre as well | Dials, Latch, Beacon | done |
| 4 | The battery's level in the lock screen's top right, green while charging | Latch, battery.py | done |
| 5 | Show message when locked (Dials > Power or Battery): a few words under the password field, such as how to return a lost computer | Dials, Latch | done |
| 6 | Guide topic; README row and lock screen screenshot; every README screenshot retaken | Guide, Docs | done |

## 1.135 "widgets" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Five new widgets: Battery (how full, and whether it's charging, or the power adapter on a computer with no battery), Screen Time (today's total and the three apps used most), World Clock (the cities added in Chime, each with its own clock), Sticky Note (the newest note, in its colour) and Photo (a different picture from Pictures each day) | Backdrop (desktop_widgets.py) | done |
| 2 | Widgets in the Notification Centre, under the notifications: two small ones to a row and a wide one on its own, light or dark to match it; a click opens the widget's app. The month, the day's events, the notifications and the widgets now scroll together | Beacon | done |
| 3 | Edit Widgets… at the foot of the Notification Centre, and on the desktop, opens one gallery with a tab for each place; adding or removing a widget shows at once in the other place too | Backdrop, Beacon | done |
| 4 | A widget added to the desktop goes into the first free spot; the Notification Centre's name shows in the menu bar while its gallery is open | Backdrop, apps.py | done |
| 5 | Guide topic updated; README row; every README screenshot retaken, with two of the widgets | Guide, Docs | done |

## 1.134 "software update" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Software Update shows when a new version of freemac is out, with what's new in it; Update Now downloads it while you carry on working, after an administrator's password | Dials (dials_update.py), freemac_update.py | done |
| 2 | Restart Now installs it while the computer restarts, before anyone logs in, and a notice says once it's in; if anything goes wrong, everything is put back as it was | freemac-update-helper, freemac-update-install.service, Beacon | done |
| 3 | freemac looks for a new version once a day and says when one is ready, once for each version; Software Update's red count includes it | Beacon (update_notice.py), Dials | done |
| 4 | Undo Last Update in freemac Recovery puts back the version from before the last update | Recovery | done |
| 5 | Every release carries an update bundle beside its ISO: freemac's own files with a checksum for each, checked before anything is changed, and only ever written into freemac's own places | build-iso.sh, make-update-bundle.py, release workflow | done |
| 6 | Each release's notes list what's new in it, the same list Software Update shows; the Guide explains updating and undoing; every README screenshot retaken, with two of Software Update | Docs, Guide | done |

## 1.133 "battery" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Battery, as on a Mac: the battery's level every 15 minutes over the last 24 hours, with a green strip under the times it was plugged in, and when it was last charged | Dials (dials_battery.py), battery.py | done |
| 2 | Last 10 Days: how long the computer ran on battery each day, and in all | Dials | done |
| 3 | Battery Health: Normal, or Service Recommended once the battery holds under 80% of what it did new, with its maximum capacity and charge cycles | battery.py, Dials | done |
| 4 | Low Power Mode: Never, Always, Only on Battery or Only on Power Adapter; it switches as the computer is plugged in or unplugged, and the battery in the menu bar turns yellow while it's on | Topline (status.py), battery.py | done |
| 5 | Topline keeps a sample of the battery every 5 minutes, and when it's plugged in or unplugged, for ten days; the page is called Battery on a computer that has one, and Power otherwise | Topline, Dials | done |
| 6 | Guide topic updated; README row; every README screenshot retaken, with two of the Battery page | Guide, Docs | done |

## 1.132 "storage" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Storage, as on a Mac: how much of the disk is used and how much is left, on a bar coloured by what fills it (Applications, Documents, Pictures, Music, Movies, Downloads, Trash and System) | Dials (dials_storage.py), storage.py | done |
| 2 | Recommendations: Empty Trash Automatically (after 30 days), Empty Trash… with how much it frees, and Review Files… for the biggest files in the home folder, sortable by name, size and date, with Show in Drawer and Move to Trash | Dials | done |
| 3 | What's Using Space: each kind with its size, a Show button that opens the folder in Drawer, and Manage… for apps in Harbor | Dials, Drawer, Harbor | done |
| 4 | About's Storage row has Storage Settings… to open the page; Seek finds it by "disk space", "free up" and more | Dials | done |
| 5 | Guide topic; README row; every README screenshot retaken, with one of the Storage page | Guide, Docs | done |

## 1.131 "sound menu" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | The Sound menu, as on a Mac: click the speaker in the menu bar for the volume slider, the outputs (speakers, headphones, a display) with the one playing marked, and Sound Settings…; click an output to play through it | Topline (status.py) | done |
| 2 | Balance, in Dials > Sound: a slider from Left to Right; the volume keys, the menu bar, Quick Settings and Dials keep it as the volume changes | audio.py, Dials | done |
| 3 | Input level, in Dials > Sound: a row of lights that follow what the microphone hears while the page is showing | Dials | done |
| 4 | Play stereo audio as mono, in Dials > Accessibility > Audio: both sides play the same sound; it stays in front of whichever output is chosen, and comes back at the next login | audio.py, Topline | done |
| 5 | The speaker in the menu bar follows the volume keys and other apps at once, not every 10 seconds; the speaker beside the menu's slider shows the level and mutes with a click, and mute is read and set through the same sound server call so the icon never lags | Topline, keys, Dials | done |
| 6 | Guide topic; README row; every README screenshot retaken, with one of the Sound menu | Guide, Docs | done |
| 7 | Release builds no longer hang on a stalled package download: apt gives up on a silent mirror after 30 seconds and tries again (five times), and the build step stops after 70 minutes instead of holding the release for 2.5 hours | build-iso.sh, release.yml | done |

## 1.130 "spoken content" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Speak items under the pointer, as on a Mac: hold the Hover Text key and point at some words to hear that line read aloud, with or without Hover Text's panel; each line is read once until the pointer moves to another | Strata (hover-text.hpp, `hover_speak`), Topline (hover_text.py) | done |
| 2 | Announce notifications: each banner is read out as it shows ("Nudge: Call Sam back"), not while a Focus is on | Beacon (announce.py) | done |
| 3 | Announce the time: on the hour, half hour or quarter hour, in the menu bar clock's 12 or 24 hours, not while a Focus is on | Topline (announce.py) | done |
| 4 | Dials > Accessibility > Spoken Content: a row for each, in the voice and speed already chosen there | Dials | done |
| 5 | Hover Text fix: the word under the pointer was missed about one time in three, as the pointer came back before the picture was taken; now Strata waits for a frame drawn without it and keeps it hidden until Topline is done | Strata, Topline | done |
| 6 | Guide topic; README row; every README screenshot retaken | Guide, Docs | done |

## 1.129 "focus" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Focus, as on a Mac: Do Not Disturb, Sleep, Work and Personal, one at a time; Quick Settings' Focus tile opens a list to pick one, and the menu bar shows its symbol | Beacon (notify_rules.py), Topline (quick.py, topline.py) | done |
| 2 | Each Focus has its own allowed apps, whose banners still show while it's on; urgent notices always show | Beacon | done |
| 3 | Each Focus can turn on by itself at set times on chosen days (Work: 9 to 5, Monday to Friday); turning it off by hand keeps it off until that stretch ends | Beacon (notify_rules.py) | done |
| 4 | Dials > Focus: a page for each Focus with its switch, allowed apps and schedule; the Notification Centre's menu picks a Focus too | Dials, Beacon | done |
| 5 | Original symbols for the four Focuses; Guide topic; README row; every README screenshot retaken | Art, Guide, Docs | done |

## 1.128 "mouse keys" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Mouse Keys, as on a Mac: the number keypad moves the pointer (8, 2, 4 and 6, with 7, 9, 1 and 3 for diagonals), slowly at first and faster while a key is held; 5 clicks, Control with 5 right-clicks, 0 holds the button down to drag and . lets it go | Strata (mouse-keys.hpp) | done |
| 2 | The pointer is a pointer device of its own, so every app sees an ordinary mouse; a laptop with no keypad can use 7, 8, 9, U, I, O, J, K, L and M instead | Strata | done |
| 3 | Press Option five times to turn it on or off, with a sound and a notice at the top right | Strata, Topline (mouse_keys.py) | done |
| 4 | Dials > Accessibility: Mouse Keys switch, Option five times, letter keys, Initial delay and Maximum speed | Dials | done |
| 5 | Guide topic; README row; every README screenshot retaken | Guide, Docs | done |

## 1.127 "accessibility keyboard" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Accessibility Keyboard, as on a Mac: a keyboard on the screen to type with the mouse, a trackpad or a touch screen; it floats above the windows without taking the keyboard from the app, can be dragged by its top edge and closed with its red button | Topline (screen_keyboard.py) | done |
| 2 | Each key is sent through the computer's own keyboard, so shortcuts, Slow Keys and every app see an ordinary key; Shift, Control, Option and Command stay down for the next key, twice locks them | Strata (screen-keyboard.hpp) | done |
| 3 | Keys show what the keyboard layout types, capitals while Shift is down; light and dark | Topline | done |
| 4 | Dials > Accessibility switch; Guide topic; README row; every README screenshot retaken | Dials, Guide, Docs | done |

## 1.126 "slow keys" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Slow Keys, as on a Mac: a key counts only once it has been held for the acceptance delay, so a key brushed by accident isn't typed; Shift, Control, Option and Command act at once, so shortcuts still work | Strata (slow-keys.hpp) | done |
| 2 | A soft click as each key goes down and another once it counts, from sounds kept loaded so they never hold up typing | Topline (slow_keys.py) | done |
| 3 | Dials > Accessibility: Slow Keys switch, Acceptance delay (Short to Long) and Use click key sounds | Dials | done |
| 4 | Guide topic; README row; every README screenshot retaken | Guide, Docs | done |

## 1.125 "hover text" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Hover Text, as on a Mac: hold Command and point at some words, and the line under the pointer shows large in a panel just above it, in any app; letting go, another key or a click puts it away | Strata (hover-text.hpp), Topline (hover_text.py), Tesseract | done |
| 2 | The words are read off the screen with the same reader as Live Text; the pointer is hidden for the moment the picture is taken, so it doesn't cover the word it points at; nothing is saved | Strata, hover_text.py | done |
| 3 | Dials > Accessibility: a Hover Text switch, the key to hold (Command, Option or Control) and the text size | Dials | done |
| 4 | Guide topic; README row and screenshot; every README screenshot retaken | Guide, Docs | done |

## 1.124 "live text" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Live Text, as on a Mac: Frame finds the words in a picture or PDF page by itself; drag across them to select, ⌘C to copy, ⌘A for all, a double click for a word and three for a line, with the text pointer over words | Frame (livetext.py), Tesseract | done |
| 2 | A Live Text button over the picture lights up all its text; right-click for Copy, Select All and Copy All Text, also in the Edit menu | Frame | done |
| 3 | Copied text keeps its lines and paragraphs; nothing is written to disk to read it | livetext.py | done |
| 4 | Guide topic; README row and screenshot; every README screenshot retaken | Guide, Docs | done |

## 1.123 "codes" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Verification codes, as the Passwords app on a Mac keeps them: Set Up Verification Code on a login takes a website's setup key, or reads its QR code straight off the screen, and the login then shows its six-digit code, changing every 30 seconds, with Copy and ⌘⌥C | Purser (codes.py) | done |
| 2 | A Codes list of every login with a code; a code moves with its login when the site or user name is changed, and goes when the login is deleted; Remove Verification Code asks first | Purser | done |
| 3 | Codes are kept in the keychain beside the passwords, so the login password opens them too | codes.py, gnome-keyring | done |
| 4 | Guide topic; README row and screenshot; every README screenshot retaken | Guide, Docs | done |

## 1.122 "passwords" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A login keychain, as on a Mac: gnome-keyring's secret service, opened by the login password, so Web offers "Save Login?" and fills saved logins in; an account that logs in by itself gets a keychain with no password of its own at login, so saving the first password asks nothing | keychain.py, login items, gnome-keyring | done |
| 2 | Purser, a Passwords app: every website login Web saved (or you added), with search, Copy for the user name and password, and a strong password suggested for a new one; edit or delete a login; saved Wi-Fi networks with their password and join code after an administrator's password | Purser (purser.py, logins.py) | done |
| 3 | Purser opens only after your login password (its own polkit action), and locks again after 5 minutes in the background or with ⌘L | Purser | done |
| 4 | A Security list in Purser: passwords used on more than one website, and ones easy to guess | Purser | done |
| 5 | Changing your own password in Dials > Users gives the keychain the new password too, so saved passwords keep opening | Dials, keychain.py | done |
| 6 | Guide topic; README row and screenshot; every README screenshot retaken | Guide, Docs | done |

## 1.121 "known networks" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Dials > Network > Known Networks, as on a Mac: every Wi-Fi network this computer has joined, the newest first, with when it was last joined and whether it joins by itself | Dials | done |
| 2 | A ⋯ menu for each: Copy Password and Show Password and Code (after an administrator's password), with a QR code a phone's camera scans to join; Join Automatically; Forget This Network | Dials, freemac-wifi-password | done |
| 3 | A copied Wi-Fi password is left out of clipboard history | Clips | done |
| 4 | Guide topic; README row; every README screenshot retaken | Guide, Docs | done |

## 1.120 "screen reader" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A screen reader, as a Mac has: Command+F5 anywhere turns it on or off, and it speaks the window and control you move to, the text under the cursor and what you type, in GTK and Qt apps, Firefox and LibreOffice | Strata, screen_reader.py, Orca | done |
| 2 | Dials > Accessibility: a Screen reader switch and Screen Reader Settings for its voice, speed and keys; it comes back at the next login if it was on | Dials, Topline | done |
| 3 | Listed in Dials > Keyboard's shortcuts; Guide topic; README row; every README screenshot retaken | Dials, Guide, Docs | done |

## 1.119 "full size" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A window put in full screen right after it opened (Quill showed it every time) could slide onto its own desktop still at its old size. Strata now sets the full-screen size again once the slide is over, whether the green button, Control+⌘F or the app itself asked | Strata (mission-control.hpp) | done |
| 2 | Every README screenshot retaken | Docs | done |

## 1.118 "update count" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A red count beside Software Update in the Dials sidebar when updates are ready, as on a Mac; it changes as soon as Beacon finds more or Harbor installs them | Dials | done |
| 2 | The Software Update page says how many are ready, and its button reads Update Now… then | Dials | done |
| 3 | Badges come back when the Dock restarts: the Dock says it started, and every open app (Post, Nudge, Beacon for Harbor) sends its count again | Pier, all apps (launcher_badge.py) | done |
| 4 | README row, every README screenshot retaken | Docs | done |

## 1.117 "update notices" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Once a day, freemac asks the archive for new updates (PackageKit, no password in the desktop session); a minute after login it counts the ones it already knows | Beacon (update_notice.py) | done |
| 2 | A notice when updates are ready, once for each new set rather than every day; a click opens Harbor's Updates page | Beacon | done |
| 3 | A red badge on Harbor's Dock icon with the count; Harbor asks for a recount after it checks or installs, so the badge goes when they're in | Beacon, Harbor, Pier | done |
| 4 | The live system doesn't look or nag, since nothing there is kept | Beacon | done |
| 5 | The ISO brings its base system up to date while it's built, so it starts with the archive's current security fixes (the 1.114 image had 31 waiting) | Build | done |
| 6 | Guide lines, README row, every README screenshot retaken | Guide, Docs | done |

## 1.116 "come forward" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | Apps can ask to bring a window forward (xdg-activation): opening a link, or an app that's already open from the Dock, Seek or Drawer, brings its window to the front on its own desktop. Granted when it comes from something you did | Strata (attention.hpp) | done |
| 2 | An app that asks with nothing you did behind it, or an X11 app that sets the urgency hint, doesn't take the keyboard: its Dock icon bounces until you go to it, as on a Mac. A LauncherEntry "urgent" does the same | Strata, Pier | done |
| 3 | Downloads: root owns everything outside /home. The ISO build kept the build machine's user (1001) on /, /etc and /usr, which a PC's second account then got; the build now copies the overlay as root and stops if any system file belongs to an account, and Keel gives such files back to root when it installs. README has a one-line repair for PCs installed before | Build, Keel | done |
| 4 | Live session: sudo works without a password again (sudo had ignored /etc/sudoers.d while the build machine's user owned it) | Build | done |
| 5 | Guide line, README rows, every README screenshot retaken | Guide, Docs | done |

## 1.115 "dock badges" (done)

| # | Item | Component | Status |
| --- | --- | --- | --- |
| 1 | A red count on a Dock icon when an app sends one over the LauncherEntry signal many Linux apps already use; a progress bar along its foot for a download or copy | Pier (launcher_badge.py) | done |
| 2 | Post's icon shows the unread messages in every Inbox; Nudge's shows the reminders due today or late | Post, Nudge | done |
| 3 | A badge goes when its app quits | Pier | done |
| 4 | Dials > Dock and Menu Bar: Show badges on Dock icons | Dials | done |
| 5 | Guide line, README row, every README screenshot retaken | Guide, Docs | done |

## Later

- App menus from Qt apps in Topline (needs KDE's app-menu protocol in
  Strata and a Qt platform plugin that uses it).
- The Debian build, as soon as a build host can reach Debian's servers.
- Qt 6 apps in freemac's own look: Ubuntu 24.04 has no Qt 6 build of
  Kvantum, so Qt 6 apps use Fusion with freemac's colours until it does.

- Ferry, step by step: threads, sockets, C++ programs (libc++), other dynamic
  libraries. Frameworks such as Foundation
  only after that, and only from public documentation. See
  [ARCHITECTURE.md](ARCHITECTURE.md#mac-app-compatibility-optional-layer).
- Signed images and update bundles, with a key kept outside the repository.
- Testing on real laptops: Wi-Fi, batteries, trackpad gestures, suspend.
