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
