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
- Signed images and a package repository.
- Testing on real laptops: Wi-Fi, batteries, trackpad gestures, suspend.
