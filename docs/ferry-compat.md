# Ferry: which Mac apps run

This table says how far real Mac apps get under Ferry, and what stops
each one. It is updated as Ferry grows. The apps are small open-source
Objective-C apps with Intel (x86-64) builds, downloaded from their own
GitHub release pages and run on freemac without any change. **None of
them is in this repository**: they are tested by hand, and only what
happened is written down here. Ferry's own tests (`make check`) use
programs and nibs written for Ferry.

Last checked: 2026-11-23, with Ferry 0.9.0 (after M7: more apps, and the Installer).

## Summary

No real app runs all the way yet, but they get much further than at M7.
Nine apps have been tried (the seven of M6, plus MacDown and Sequel Pro).
Seven start and get through `NSApplicationMain` and their main nib; ShiftIt
now gets all the way into its event loop and keeps running (it shows
nothing, because its only window is a status bar item, which Ferry doesn't
have yet), and Gas Mask gets through its whole launch until it lays out
its main window. Each of the others stops with a message that names what
was missing.

Ferry also has its own **Installer** now. Three real installers were
tried, and all three install: the MacPorts and XQuartz packages (`.pkg`)
and the Sequel Pro disk image (`.dmg`). See "Installers" below.

## The apps

| App (version) | What it is | How far it gets | What stops it |
| --- | --- | --- | --- |
| [Hex Fiend](https://github.com/HexFiend/HexFiend) 2.18.1 | Hex editor | Doesn't start | Part of it is written in Swift (`libswiftCore.dylib`), a known limit. All 16 of its nibs (`NIBArchive`) load when tried on their own |
| [Flycut](https://github.com/TermiT/Flycut) 1.9.6 | Clipboard history (menu bar) | Starts, loads its main nib, sets up its defaults and bindings, registers its global hotkey (accepted, never pressed), and opens its preferences nib | `NSTabView` in its preferences nib (`selectTabViewItemAtIndex:` sent to the plain view Ferry put in its place). Then `NSStatusBar`, for its menu bar item |
| [KeyCastr](https://github.com/keycastr/keycastr) 0.9.18 | Shows the keys you press | Starts, loads its main nib (`NIBArchive`) | `NSInvocation`/`NSMethodSignature` (forwarding), which Ferry has from (1.170); what it stops at now is still to be checked. It also needs to see every key pressed in other apps, which Wayland doesn't allow. (Not re-run since M7) |
| [ShiftIt](https://github.com/fikovnik/ShiftIt) 1.6.6 | Moves and resizes other apps' windows | **Runs**: starts, loads its nibs, asks whether it may use the Accessibility API (Ferry answers no, as a Mac does before the user allows it), and waits in its event loop | Nothing visible: its only window is a status bar item (`NSStatusBar`, not in Ferry yet). Moving other apps' windows can't work as such on Wayland |
| [Spectacle](https://github.com/eczarny/spectacle) 1.2 | Window tiling by shortcut | Starts, loads its nibs, registers its shortcuts (accepted, never pressed) | Its Sparkle updater checks its own code signature (`SecStaticCodeCreateWithPath`, the Security framework). It also couldn't save its shortcuts file. Then the Accessibility API, as for ShiftIt |
| [MacPass](https://github.com/MacPass/MacPass) 0.8.1 | KeePass password manager | Starts; all 30 of its nibs (`NIBArchive`) load on their own | The document classes (`NSDocumentController`, `NSDocument`): its own document controller class is left out and the app stops when it makes one. (The document classes came in 1.167; not re-run since) |
| [Gas Mask](https://github.com/2ndalpha/gasmask) 0.8.6 | Hosts-file editor (menu bar) | Starts (its Mac OS X 10.7 start-up format loads now), sends its log to a file, uses ICU's regular expressions (through RegexKitLite), watches network reachability, registers its hotkey, loads its preferences (an `NSUserDefaultsController` subclass) and its hosts lists, and sets up its main window | `NSSplitView` in its main window (`positionOfDividerAtIndex:`). Its hosts list is an `NSOutlineView`, also not in Ferry yet |
| [MacDown](https://github.com/MacDownApp/macdown) 0.7.2 | Markdown editor | Starts, loads its main nib | Its Sparkle updater asserts that `/System/Library/CoreServices/SystemVersion.plist` (the Mac's version file) exists. It is also built on `NSDocument` and WebKit (a known limit) |
| [Sequel Pro](https://github.com/sequelpro/sequelpro) 1.1.2 | MySQL client | Installed from its `.dmg` by Ferry's Installer; starts, loads its main nib | An array made with a nil object (`initWithObjects:count:`), most likely one of the 89 classes it uses that Ferry doesn't have yet (tables, outline and split views, documents...) being nil |

## Installers

Ferry's Installer (`ferry SomeApp.pkg` or `ferry SomeApp.dmg`, or a
double-click) shows a package's welcome, read-me and licence pages, then
installs for the user alone: apps to `~/Applications`, everything else to
`~/.local/share/ferry/root`. Install scripts and JavaScript checks are not
run, and it says so before installing.

| Installer | Kind | Result |
| --- | --- | --- |
| [MacPorts](https://www.macports.org/) 2.10.5 for macOS 13 | Flat `.pkg`, with JavaScript checks and install scripts | Every page shows (welcome, read-me and licence); 1,364 files install in under a second, the same files 7-Zip extracts. Its install scripts aren't run, and its absolute links (to `/opt/local/...`) point outside Ferry's folder, so the installed tools aren't usable as they are |
| [XQuartz](https://www.xquartz.org/) 2.8.5 | Flat `.pkg` (a 107 MB package holding 310 MB) | Installs in about 1.5 seconds: `XQuartz.app` to Applications, 349 MB of libraries and tools into Ferry's folder. Running XQuartz itself wasn't tried |
| Sequel Pro 1.1.2 | Disk image (`.dmg`) holding the app | The app is copied to Applications; "Open Sequel Pro" on the last page starts it through Ferry |

## What M6 changed to get this far

Before M6, every one of these apps stopped at once: each links a system
framework Ferry doesn't have (Carbon, IOKit, Security, WebKit, Quartz...).

- A missing system framework or `/usr/lib` library no longer stops the
  program: Ferry says which and carries on. A call into it stops the
  program with that call's name; a missing Objective-C class is nil (as a
  weakly linked class missing from an older macOS is); a class of the
  app's own built on a missing class is left out, with its name; a missing
  string constant (`NS...Notification`, `NS...Key`, `kAX...`) holds its
  own name.
- Grand Central Dispatch (`dispatch_async`, `dispatch_once`, queues,
  groups, semaphores, timers), which every app here uses.
- Libraries built before Mac OS X 10.6 (relocation entries instead of
  `LC_DYLD_INFO`, and the message references of that era's compilers).
- Nibs in the `NIBArchive` form.
- Smaller pieces the apps hit: key paths, `NSValueTransformer`, Cocoa
  bindings (set once, not yet kept up to date), `NSUserDefaults` through
  key-value coding, `+[NSValue valueWithNonretainedObject:]`,
  `-[NSDictionary initWithContentsOfFile:]`, `atexit`, a control's
  `formatter`.

## What M7 changed

- `NSImage` and image views, so the apps' icons and button images load.
- `@try`/`@catch`/`@finally`: exceptions are caught as on a Mac, and one
  left uncaught in the event loop is reported and the app carries on. Only
  frames of Mac code can be unwound: an exception thrown through a Linux
  library's frame (a GTK callback, say) is treated as uncaught.
- `NSWindowController` and `NSViewController`.
- The clipboard, Open and Save panels, drag and drop onto views, the
  app's icon in the dock, and backing-scale conversions.
- A missing `...Type` constant (Flycut's `NSStringPboardType` was one)
  now holds its own name, like the other missing string constants, instead
  of pointing at a stub.

## What changed after M7

Trying more apps, and an installer, filled these gaps:

- **The Installer**, and `ferry` given an app bundle (`ferry Foo.app`) or
  an installer.
- **Views**: scroll views (with scrollers, clip views, wheel and
  autoscrolling), text views (editing, selection, the keyboard's standard
  commands, copy and paste, RTF and simple HTML in and out), progress
  indicators, boxes.
- **Key-value observing**, so Cocoa bindings now follow the values they
  are bound to; `NSUserDefaultsController`; cancelling delayed performs.
- **Libraries from this system**: zlib, bzip2, xz, libxml2, SQLite and ICU
  (Gas Mask's regular expressions).
- **Carbon and Accessibility answers**: global hotkeys are accepted but
  never pressed, keyboard layouts have no Mac layout data, and the
  Accessibility API is "not trusted", which is how a Mac answers when
  these aren't available. SystemConfiguration's network reachability
  (always reachable). This let Flycut, Spectacle, ShiftIt and Gas Mask go on.
- **Smaller pieces**: `CFPreferences`, `OSSpinLock` and `OSAtomic`,
  `os_unfair_lock`, the old garbage collector's write barriers, the
  Services menu's provider, paragraph styles in nibs, content borders,
  cell background styles, `URLByResolvingSymlinksInPath`,
  `CFStringGetCharacters`.
- **Two crashes fixed**: a message to a class Ferry left out could crash
  instead of being reported (older linkers leave different values in a
  class's cache words), and a program that redirected its stderr to a file
  it couldn't open closed the stream Ferry reports on.

### Tab views and split views (1.155)

`NSTabView` (with `NSTabViewItem`) and `NSSplitView` are in Ferry now, read
from nibs in both formats, with their delegates, drawing, mouse and keyboard
handling, and split views' saved positions. They are what stopped Flycut and
Gas Mask. The apps have not been run again since (running downloaded apps
isn't done on the machine that builds freemac), so the table above still
shows where they stopped before; Flycut's next known need is `NSStatusBar`,
and Gas Mask's is `NSOutlineView`.

Ferry's package is now attached to every freemac release.

### Menu bar items (1.157)

`NSStatusBar` and `NSStatusItem` are in Ferry now: an item appears in
freemac's menu bar (over StatusNotifierItem, which Topline has read since
1.156), with its image or title drawn by Ferry and its menu read as it opens.
That was Flycut's next known need, and the only window ShiftIt has; Spectacle
and Gas Mask use one too. The apps haven't been run again here, for the reason
above. Mac programs expect SSSE3, which every Intel Mac had; Ferry now says
so plainly on a processor without it, where a program would otherwise stop
with "Illegal instruction".

### Table views and outline views (1.159)

`NSTableView` and `NSOutlineView` are in Ferry now, with `NSTableColumn`,
`NSTableHeaderView`, `NSTableRowView` and `NSTableCellView`: cell-based and
view-based tables (cell views made from a nib's prototypes and reused as
rows scroll), columns that are resized by dragging the header or follow the
table's width, alternating rows and grid lines, selection by mouse and
keyboard with the delegate's say, sorting from the header with Ferry's own
sort arrow, and the source list's rounded selection. Outline views open and
close items by their chevrons, the arrow keys or code. Scroll views now
keep a table's header above its rows. Both are read from nibs. They were Gas
Mask's next known need and are most likely Sequel Pro's; the apps haven't
been run again here, for the reason above. Foundation gained `NSIndexSet`
and `NSSortDescriptor` for them. Not done yet: editing text in a table's
cells, dragging rows and columns, type-to-select, saved column widths, and
animations (rows change at once).

### Pop-up buttons, segmented controls, search fields, stack views and toolbars (1.164)

`NSPopUpButton`, `NSSegmentedControl`, `NSSearchField`, `NSStackView` and
`NSToolbar` are in Ferry now, with their cells and `NSToolbarItem`, all
read from nibs and drawn by Ferry's own code to look like a current Mac's.
A pop-up button's menu opens inside the window, the chosen item lined up
over the button (a pull-down list's opens below it), and is worked by the
mouse, the arrow keys, Return, Escape and typing; the menu's delegate is
asked before it opens and items are enabled by their targets as in the
menu bar. Segmented controls select one, any or momentarily, with segment
menus and the four distributions. Search fields search as the user types
(after a pause, or at once) or on Return, with the clear button, Escape
and recent searches kept in the user defaults. Stack views lay out rows
and columns by hand (Ferry has no Auto Layout) from their views' intrinsic
sizes, with the gravity areas, every distribution and alignment, hidden
and detached views and visibility priorities. A window's toolbar is drawn
under the desktop's title bar in the same colour; the window grows by it
as on a Mac, its items are validated as events come, and those that don't
fit go in a chevron's menu. Pop-up buttons and segmented controls take the
keyboard focus when full keyboard access is on (the `AppleKeyboardUIMode`
default). Every app's nibs use some of these; the apps haven't been run
again here, for the reason above. Not done yet: menus can't reach past the
window, submenus in a pop-up button's menu, key equivalents shown in it,
customizing a toolbar (the sheet), dragging the window by its toolbar, and
`NSToolbarItemGroup` beyond showing its parts. The nib keys these classes
read are the names published descriptions of the format give; a nib that
names something differently loads with the default.

### Documents, alerts and the workspace (1.167)

`NSDocument`, `NSDocumentController` and the document side of
`NSWindowController` are in Ferry now, written from Apple's documentation
of the document architecture. The types come from the Info.plist's
`CFBundleDocumentTypes` (`LSItemContentTypes` or `CFBundleTypeName`, the
extensions from `CFBundleTypeExtensions` or the app's type declarations,
the role and `NSDocumentClass`); New, Open (through the Open panel), Save,
Save As, Save To, Revert and Duplicate work, and so do the File menu's
actions and their validation. A document reads and writes its file as a
URL, a file wrapper (a package) or data, each calling the next as
documented, and the calls of Mac OS X 10.3 when a class overrides those
instead; saving writes beside the file and then moves it into place. The
change count follows the undo manager (`NSUndoManager` is new in
Foundation, with the selector and block forms) and the window shows the
edited dot. Closing an edited document asks Save, Cancel or Don't Save in a
sheet, and quitting with several asks to review them first; the app's
delegate may answer `NSTerminateLater`. The Recent Documents list is kept
in the user defaults (and given to the desktop's recent files) and fills
the Open Recent menu. The first document controller made is the shared
one, so an app's own subclass in its main nib (MacPass has one) is used.
Files named on the command line open at launch, else an untitled document
when the app wants one. Left out: autosaving and versions
(`autosavesInPlace` answers NO, as on Mac OS X 10.6, and the autosave calls
save nothing), renaming, moving and locking from the title bar, and
printing. (`prepareWithInvocationTarget:` answered nil until Ferry had
`NSInvocation`; it works from (1.170).)

`NSAlert` draws as a current Mac's alert: the app's icon (the caution sign
for a critical alert), the message in bold, the informative text, an
accessory view and the suppression check box, then one to three or more
buttons; the first answers Return, Cancel answers Escape and Don't Save
Command-D. `runModal` runs a nested event loop, and
`beginSheetModalForWindow:` shows it as a sheet: sheets (any window's, and
the old `beginSheet:modalForWindow:...` call) hang inside their window
under its title bar and toolbar, queue one after another, and keep the
window from closing while they are up. `presentError:` goes up the
responder chain to an alert, and the `NSRunAlertPanel` family is there.
With no display, `FERRY_ALERT_ANSWER` (a button's title or number) answers
alerts, for scripted runs.

`NSWorkspace` opens web addresses, files and folders ("show in Finder"
opens the folder) through the desktop's own launcher, `gio open` or
`xdg-open`, started with the address as its one argument and no shell;
that is the only way Ferry starts anything outside itself, so another Mac
app is never launched. Icons come from the desktop's icon theme (an app
bundle shows its own), apps are found by bundle identifier or name only
when they are this app or in `~/Applications` and `/Applications`, and the
workspace's notifications are all defined, though nothing on Linux posts
sleep, wake or launch ones.

### Invocations, forwarding, JSON and dates ((1.170), Ferry 0.14.0)

`NSInvocation` and `NSMethodSignature` call any method from its type
encoding, laying out integers, pointers, objects, floating-point numbers,
`long double`, and small and large structs as the x86-64 calling
convention does, and read the result back. A message an object doesn't
answer now goes, as on a Mac, to `forwardingTargetForSelector:`, then to
`methodSignatureForSelector:` and `forwardInvocation:` (`NSProxy` is new,
for proxies that catch and re-send messages), and only then to
`doesNotRecognizeSelector:`, which stops the program with the same message
as before. KeyCastr needed this, and `NSUndoManager`'s
`prepareWithInvocationTarget:` is built on it. `NSJSONSerialization` reads
and writes JSON with the usual options (not JSON5). `NSDateFormatter`
writes and reads Unicode date patterns and the standard styles in English
(United States) for every locale, with `NSTimeZone` reading this system's
time zone database and an `NSLocale` that knows identifiers only.

### Calendars and number formatters ((1.173), Ferry 0.15.0)

`NSCalendar` (Gregorian and ISO 8601) and `NSDateComponents` split dates
into components in any time zone and build them back, add components,
count the difference between two dates, find starts of days and other
units across daylight saving changes, and look for the next date that
matches components, as Apple documents them. `NSNumberFormatter` writes
and reads numbers in every style (decimal, percent, currency and its
accounting, ISO code and plural forms, scientific, spell-out, ordinal) with
digits, rounding modes, grouping, padding and patterns;
`NSISO8601DateFormatter` writes and reads ISO 8601 dates with its format
options; `NSDateFormatter` now does relative formatting ("Today at 3:05
PM"); and `NSDateComponentsFormatter` and `NSByteCountFormatter` write
durations and file sizes. All of it is English (United States) for every
locale; a locale's country only picks the default currency. None of the
nine apps has been run again since.

## What the apps need most

Counted over the nine apps:

1. **More views**: done for the ones every app's nibs use. Split views
   and tab views came in 1.155; table and outline views, which stopped Gas
   Mask and most likely Sequel Pro, in 1.159; `NSPopUpButton`,
   `NSToolbar`, `NSSegmentedControl`, `NSSearchField` and `NSStackView` in
   1.164. Next is running the apps again to see which views they still
   miss.
2. **`NSStatusBar`/`NSStatusItem`**: four of the apps live in the menu bar
   (Flycut, ShiftIt, Spectacle, Gas Mask). Done in 1.157, as items in
   freemac's menu bar.
3. **The document classes** (`NSDocument`, `NSDocumentController`):
   MacPass, MacDown, Sequel Pro. Done in 1.167, without autosaving and
   versions.
4. **Foundation's `NSThread`, `NSTask`/`NSPipe`/`NSFileHandle` and
   `NSXMLDocument`** (each used by five or more of the apps). `NSIndexSet`
   came in 1.159, `NSAlert` and `NSWorkspace` in 1.167, and `NSInvocation`
   with message forwarding, `NSJSONSerialization` and `NSDateFormatter`
   (English only, with `NSTimeZone` and a minimal `NSLocale`) in
   (1.170), and `NSCalendar`, `NSNumberFormatter` and the other
   formatters in (1.173).
5. **Updaters**: three apps' Sparkle frameworks check the Mac's version
   file or the app's code signature at start. Ferry could provide a version
   file of its own and answer the signature check plainly.
6. **Threads**: Ferry runs a program on one thread; dispatch queues run
   there too.

Things that are out of reach by design on Wayland, and so will need
another approach: global hotkeys, reading other apps' key presses, and
moving other apps' windows (the Accessibility API).

## Trying an app yourself

```sh
ferry "Some App.app"
FERRY_VERBOSE=1 ferry "Some App.app"   # every library, missing call and class
ferry SomeApp.pkg                      # or .dmg: Ferry's Installer
```

Ferry prints what it leaves out on the way; the last line before it
stops says why.
