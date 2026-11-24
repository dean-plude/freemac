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
  bindings (at M6 set once and not kept up to date; they follow values since
  the work after M7 and write edits back from (1.184)), `NSUserDefaults` through
  key-value coding, `+[NSValue valueWithNonretainedObject:]`,
  `-[NSDictionary initWithContentsOfFile:]`, `atexit`, a control's
  `formatter` (applied from (1.184)).

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
and `NSSortDescriptor` for them. Not done yet: dragging rows and columns,
type-to-select, saved column widths, and animations (rows change at once).
(Editing text in a table's cells came in (1.178).)

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
when the app wants one. Left out: versions, renaming, moving and locking
from the title bar, and
printing. (`prepareWithInvocationTarget:` answered nil until Ferry had
`NSInvocation`; it works from (1.170). Autosaving came in (1.178).)

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

### Editing in tables and autosaving ((1.178), Ferry 0.16.0)

Table and outline views edit text cells in place: a double click on an
editable cell of a selected row, Return on the selected row, or
`editColumn:row:withEvent:select:` starts it, Tab and Shift-Tab move to
the next or previous editable cell (selecting its row), Return or a click
elsewhere ends it and Escape gives it up. In a cell-based table a field is
laid over the cell, the delegate's `tableView:shouldEditTableColumn:row:`
(or the outline's `outlineView:shouldEditTableColumn:item:`) is asked
first, the data source gets the new string through
`tableView:setObjectValue:forTableColumn:row:` (or by item), and the
delegate hears `controlTextDidEndEditing:` with the `NSTextMovement`; in a
view-based table the cell view's own text field is edited and its action
sent to its target. `editedRow` and `editedColumn` say which cell is being
edited. A document class whose `autosavesInPlace` answers YES is now
autosaved `autosavingDelay` seconds after a change, over its own file (or,
untitled, into Autosave Information), stays edited until it's saved, closes
without asking, and gets Revert To > Last Saved Version, which puts back
the file as it was last saved. Versions (Browse All Versions) are still
left out. None of the nine apps has been run again since.

### Key-value observing, bindings and formatters ((1.184), Ferry 0.17.0)

Key-value observing is now automatic: the first observer of an object
moves it to a hidden subclass (`NSKVONotifying_` and the class's name,
while `class` still answers the original) whose setters announce the
change, so a class's own setter called directly notifies its observers.
Dependent keys (`keyPathsForValuesAffectingValueForKey:` and
`keyPathsForValuesAffecting<Key>`) are followed, the Prior, Initial, Old
and New options work, and `mutableArrayValueForKey:` reports insertions,
removals and replacements with their indexes. Cocoa bindings now go both
ways: text fields, buttons, pop-up buttons and sliders write the user's
edits back to the key path they're bound to (text fields when the editing
ends, or as it is typed with `NSContinuouslyUpdatesValue`), bindings made
in nibs (`NSNibBindingConnector`) are made when the nib loads, and
`NSObjectController` (`selection.*`) and `NSUserDefaultsController`
(`values.*`) are there. The null placeholder and the `NSNegateBoolean`,
`NSIsNil` and `NSIsNotNil` transformers are applied. `NSSlider` is new.
A control's or cell's `formatter` now shows the value, reads what the user
typed, refuses keystrokes it can't take and beeps (asking the delegate's
`control:didFailToFormatString:errorDescription:`), and a cell-based
table's column cell formatter is used when its cells are edited. Array
and tree controllers aren't done yet. None of the nine apps has been run
again since.

### Array controllers and table bindings ((1.188), Ferry 0.18.0)

`NSArrayController` is in. It holds an array (or a set), set with
`setContent:` or bound with `contentArray` or `contentSet`, and shows it
in `arrangedObjects`, filtered by `filterPredicate` and sorted by
`sortDescriptors`. `selection.someKey` reads and writes the key of every
selected object: their one value, or `NSMultipleValuesMarker` when they
disagree. Adding, inserting and removing change the bound array through
its owner's accessors, so the owner hears of each change. The `add:`,
`insert:` and `remove:` actions are carried out on the run loop's next
turn, and `NSObjectController`'s `add:` and `remove:` now are too, as
Apple documents. `avoidsEmptySelection`, `preservesSelection`,
`selectsInsertedObjects`, `clearsFilterPredicateOnInsertion` and
`automaticallyRearrangesObjects` are honoured.

A table column's `value` bound to `arrangedObjects.key` shows that key of
each arranged object. The table's `content`, `selectionIndexes` and
`sortDescriptors` are then bound to the same controller, so a click on a
row selects in the controller, and a click on a column's title sorts the
controller's objects. A cell edited in place sets the key on its row's
object. Underneath, `mutableSetValueForKey:` and the set mutation kinds of
key-value observing are in. So are the collection operators in key paths
(`@count`, `@sum`, `@avg`, `@min`, `@max` and the unions), and an
`NSPredicate` subset for filtering. Removing an observer that isn't
registered now raises, as on a Mac.

None of the nine apps has been run again with these.

### Tree controllers and outline bindings ((1.190), Ferry 0.19.0)

`NSTreeController` is in, with `NSTreeNode` and `NSIndexPath`. It holds a
tree of objects, read through `childrenKeyPath` (an array or a set of
children), with `leafKeyPath` or `countKeyPath` saying which objects are
leaves. Its `arrangedObjects` is a tree of `NSTreeNode`s, each holding
one of the objects, sorted level by level by `sortDescriptors`. The
selection is a list of index paths (`selectionIndexPaths`), and
`selectedObjects`, `selectedNodes` and `selection.someKey` follow it.
Inserting, removing and moving at index paths change the children
through each parent's accessors, so the model hears of each change. The
`add:`, `insert:`, `addChild:`, `insertChild:` and `remove:` actions are
carried out on the run loop's next turn. When the model changes its
children, the tree is arranged again and the nodes that are still there
are kept.

An outline view column's `value` bound to `arrangedObjects.key` of a tree
controller shows that key of each node's object. The outline's `content`,
`selectionIndexPaths` and `sortDescriptors` are then bound to the same
controller. Opening and closing rows works as with a data source, a
click selects in the controller, a node the controller selects is shown
with its parents opened, and a click on a column's title sorts the tree.
A cell edited in place sets the key on its node's object.

A table or outline column's `editable` and `enabled` bindings are now
read for each row's object, so some rows can be locked or greyed. An
edited cell is written back only when its controller is editable. With
`NSConditionallySetsEditable` set to NO, the column's own editability
decides.

`NSDictionaryController` is in too. It shows a dictionary as key-value
pairs sorted by key, with included, excluded and localized keys. A
pair's changed key or value is written back to the dictionary, and `add:`
makes a pair with a new key.

These were written from Apple's documentation and not compared with a
Mac; `docs/ferry-gui.md` lists what a Mac would settle. None of the nine
apps has been run again with these.

### Controllers from nibs, cell views and validation ((1.191), Ferry 0.20.0)

`NSArrayController`, `NSTreeController`, `NSObjectController` and
`NSDictionaryController` now load from nibs with their settings: the
object class, editable, preparing content, the selection options, the
tree's key paths, and the dictionary's initial, included, excluded and
localized keys. The binding connectors in the nib bind them to File's
Owner and bind tables, outlines and fields to them, so a nib that shows a
controller's objects in a table works with no code. Apple doesn't
document a compiled nib's keys, so the controllers' keys are a guess
after Interface Builder's names; `docs/ferry-gui.md` lists them.

A view-based table or outline whose content is bound and whose delegate
makes no views makes its cell views from the nib's prototypes. Each cell
view's `objectValue` is its row's object (in an outline, the node's
represented object), and a field or check box in it bound to
`objectValue.key` shows that key and writes the user's edits back.

Bindings now validate. With `NSValidatesImmediately`, a value is checked
with the model's `validate<Key>:error:` before it is written: a refused
value isn't written, its error is presented, and the control shows the
model's value again; a value the method changes is written changed.
`NSRaisesForNotApplicableKeys` is followed. A bound control is disabled,
or a bound text field made uneditable, when there is nothing to edit: no
selection, a controller that isn't editable, or several values when
`NSAllowsEditingMultipleValuesSelection` is NO. The array controller
takes `NSDeletesObjectsOnRemove`, `NSSelectsAllWhenSettingContent` and
`NSHandlesContentAsCompoundValue` (for example a list in the user
defaults, set whole each time).

These were written from Apple's documentation and not compared with a
Mac, and no nib saved by Interface Builder was tried: the tests write
their nibs with Ferry's own keyed archiver. None of the nine apps has been
run again with these.

### Tasks, pipes, regular expressions, scanners, XML and operations ((1.194), Ferry 0.21.0)

`NSTask`, `NSPipe` and `NSFileHandle` are in. A task is a child process:
the program an app names (`/bin/sh`, `/usr/bin/env`, `/usr/bin/git`) is
this system's program of that name, and a Mac program, such as a helper
tool inside an app bundle, is run through Ferry. Arguments, environment,
working directory, standard input, output and error (pipes, file handles
or inherited), `terminationHandler`, `NSTaskDidTerminateNotification`,
`waitUntilExit`, `terminate`, `interrupt` and the exit status and reason
all work. File handles read and write files and pipes, at once or in the
background (`readInBackgroundAndNotify`,
`readToEndOfFileInBackgroundAndNotify`,
`waitForDataInBackgroundAndNotify`, `readabilityHandler`), with the
notifications arriving from the run loop.

`NSRegularExpression` matches with this system's ICU, which is what a Mac
uses, so patterns behave the same: options, capture groups and named
groups, `enumerateMatchesInString:` and the other searches, templates
(`$1`, `${name}`) in replacements, and `NSString`'s
`rangeOfString:options:` and replacing with `NSRegularExpressionSearch`.
`NSScanner` reads numbers (decimal, hexadecimal, floating point) and words
out of a string. `NSXMLParser` parses with this system's libxml2, also
what a Mac uses, and tells its delegate of elements, attributes, text,
CDATA, comments, processing instructions, entity declarations and, with
namespace processing on, namespaces and prefixes; errors come with
libxml2's codes and line numbers.

`NSOperationQueue` runs `NSBlockOperation`s, `NSInvocationOperation`s and
operations of an app's own, with dependencies, priorities, cancelling,
completion blocks, suspending and barriers, on Ferry's one thread. The
locks (`NSLock`, `NSRecursiveLock`, `NSCondition`, `NSConditionLock`)
are there so code written for threads runs; on one thread a lock only
has to wait for work queued on the run loop. `NSCache` and `NSProgress`
are in too.

These were written from Apple's documentation and not compared with a
Mac; `docs/ferry-gui.md` lists what a Mac would settle. None of the nine
apps has been run again with these.

### Steppers, date pickers, combo boxes, colour wells, popovers, path controls, sounds and token fields (freemac 1.195, Ferry 0.22.0)

`NSStepper`, `NSLevelIndicator`, `NSColorWell`, `NSColorPanel`,
`NSDatePicker`, `NSComboBox`, `NSPopover`, `NSPathControl`, `NSSound` and
`NSTokenField` are in Ferry now, with their cells, all read from nibs and
drawn by Ferry's own code in freemac's look. Steppers step by click, the
arrow keys and holding the mouse down. Level indicators draw the
continuous, discrete, relevancy and rating styles with tick marks, and can
be set by the mouse and keys when editable. A colour well opens the shared
colour panel (GTK's colour chooser on a display) and sends `changeColor:`
when a colour is chosen. Date pickers show their parts in the user's
locale's order, are typed into and stepped part by part, keep within their
limits and ask their delegate; the graphical style shows a month calendar
(with ranges) and a clock, and a text picker can open its calendar in a
popover. Combo boxes take their items or a data source, complete what is
typed and open their list inside the window. Popovers open beside a
rectangle in the window, on the side with room, and close as their
behaviour says; view controllers can be presented as popovers. Path
controls show a file's folders (or a web address's parts) with icons, in
the standard, navigation-bar and pop-up styles. `NSSound` plays through
`pw-play`, `paplay` or `aplay`, whichever is there, and `soundNamed:` finds
the Mac's alert sounds' names in freemac's own sounds in
`/usr/share/sounds/freemac`. Token fields turn what is typed into tokens at
commas. Not done yet: detaching popovers, dragging files onto path
controls, the token field's completion list, setting the clock by its
hands, and time zones read from nibs.

### URL loading (freemac 1.196, Ferry 0.23.0)

Programs can now load http and https URLs. They can use `NSURLSession`
(data, upload and download tasks, with completion handlers or delegates),
`NSURLConnection` (synchronous, asynchronous and with a delegate),
`NSURLRequest`, `NSMutableURLRequest` and `NSHTTPURLResponse`, and
`NSData`'s and `NSString`'s `...ContentsOfURL:` for web addresses.
Failures come back as `NSError`s in `NSURLErrorDomain` with the usual
codes. The transfers use this system's libcurl (`libcurl4`). It is opened
only when a program first loads a URL, so programs that don't use the
network are unaffected. Ferry has one thread. Transfers progress, and
handlers and delegate messages run, while the program runs its run loop
(as any AppKit app does) or waits in dispatch. That covers the usual
patterns: an update check at launch, fetching a feed or JSON, and
downloading a file. Not yet supported:
- cookies, the URL cache, authentication challenges and redirect
  callbacks;
- background sessions, WebSockets and resume data;
- Mac programs that bundle or link libcurl themselves.

### XML documents (freemac 1.197, Ferry 0.24.0)

`NSXMLDocument` reads a document into a tree of `NSXMLNode`s
(`NSXMLElement`, attributes, namespaces, text, comments, processing
instructions, and an `NSXMLDTD` with its declarations), with this
system's libxml2 as a Mac's does. The tree is made of Objective-C objects,
so an app can walk it, change it (insert, remove and replace children,
attributes and namespaces, set values, detach and copy nodes), search it
with `nodesForXPath:error:` (libxml2's XPath, on a copy of the tree made
again after each change) and write it out again with `XMLString`,
`XMLData` (UTF-8, UTF-16, ISO-8859-1 or US-ASCII) or pretty printed, or as
canonical XML. Documents come from strings, data or files; errors come
with libxml2's codes and line numbers, and `NSXMLDocumentValidate`
checks a document against its DTD. XQuery, XSLT and HTML documents are
left out. This was written from Apple's documentation and not compared
with a Mac; `docs/ferry-gui.md` lists what a Mac would settle. None of
the apps that use `NSXMLDocument` has been run again with it.

### Core Animation basics (freemac 1.198, Ferry 0.25.0)

Ferry has a QuartzCore.framework now, so apps that link it load. It is
written from Apple's documentation. A `CALayer` has its geometry (bounds,
position, anchor point, frame, transform and the `CATransform3D`
functions), a tree of sublayers, and the drawing an AppKit app uses:
background colour, border, rounded corners, opacity, hidden,
`masksToBounds`, `zPosition`, an image as its contents with the contents
gravities, and the delegate's `drawLayer:inContext:` and `displayLayer:`
after `setNeedsDisplay`. A subclass can add `@dynamic` properties, which
animate. `CAShapeLayer`, `CAGradientLayer` (axial and radial) and
`CATextLayer` draw too. Changes inside a `CATransaction` animate implicitly
over its duration, unless actions are disabled, and its completion block
runs when they are all done. `CABasicAnimation`, `CAKeyframeAnimation`,
`CASpringAnimation` and `CAAnimationGroup` run with the documented timing
(begin time, speed, repeats, autoreverse, fill modes and the named timing
functions). A timer on the main run loop steps them, and the delegate is
told when each starts and stops. An NSView gets a backing layer from
`makeBackingLayer` when it wants one, keeps it in step with its frame,
alpha and hidden state, and draws it with the view: the layer's background
and border around the view's `drawRect:` (or `updateLayer`), and its
sublayers above. A layer set with `setLayer:` first is hosted.
`NSAnimationContext` groups and a view's `animator` animate `frame`,
`bounds` and `alphaValue`. Left out: shadows, masks, filters, transitions,
3D perspective, and views' layers joined into one tree.

### Redirects, authentication, cookies and the URL cache (freemac 1.199, Ferry 0.26.0)

URL loading now does what a Mac does between the request and the answer.
Redirects are followed one at a time, and a delegate can follow, change
or refuse each one (`URLSession:task:willPerformHTTPRedirection:...` and
`connection:willSendRequest:redirectResponse:`); `currentRequest` follows
them. A 401 is answered with HTTP Basic or Digest: the delegate is asked
(`URLSession:task:didReceiveChallenge:...`,
`connection:willSendRequestForAuthenticationChallenge:` and the older
pair), and otherwise the URL's own user and password or a credential in
`NSURLCredentialStorage` is used. Before connecting to an https server,
a delegate can accept a certificate the system doesn't trust; otherwise
libcurl checks it as before. Cookies are kept in `NSHTTPCookieStorage`,
sent with each request and saved, the lasting ones, to a file beside the
program's preferences. Responses are kept in `NSURLCache`, in memory and
on disk, reused while fresh, revalidated with `ETag` and
`Last-Modified`, and the request cache policies are honoured. `data:`
URLs load too. Ephemeral sessions keep their cookies, credentials and
cache to themselves. Not yet supported:
- proxy authentication, NTLM, Kerberos and client certificates;
- a keychain: credentials last only while the program runs;
- looking inside a server's certificate (there is no Security framework);
- background sessions, WebSockets and resume data.

### Security and CommonCrypto (freemac 1.200, Ferry 0.27.0)

Apps that link the Security framework now load, and the calls they make
most work. `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate` and
`SecItemDelete` keep generic and internet passwords for the user in
`~/.local/share/ferry/keychain` (a folder only the user can open), with the
common attributes, the return types and match limits, and the documented
status codes; the older `SecKeychainAddGenericPassword`,
`SecKeychainFindGenericPassword` and their internet-password twins use the
same items. Secrets in that file are encrypted with a key kept beside them,
which protects against casual reading only, not against anyone or anything
that can read the user's files. Code signing gets one plain answer: an
app's check of its own signature passes, and everything else reads as
unsigned (Ferry can't check Apple's signatures; `FERRY_VERBOSE=1` says so).
`SecTrust` checks certificates with this system's OpenSSL against its
certificate authorities, including the server trust a URL session's
delegate is asked about. CommonCrypto (in libSystem) has the MD5, SHA-1
and SHA-2 digests, HMAC, PBKDF2 and random bytes of its own, and AES
(ECB, CBC with PKCS#7 padding, CTR) through OpenSSL. The macOS version is
now one answer everywhere: 14.7 in `SystemVersion.plist`, `NSProcessInfo`,
`Gestalt` and `uname` (Darwin 23.6.0).

### System queries and loading code (freemac 1.201, Ferry 0.28.0)

Apps that ask the system about itself, or load code while they run, now
get answers. `sysctl`, `sysctlbyname` and `sysctlnametomib` serve the
kernel and hardware names apps read most (`kern.osproductversion` 14.7,
`kern.osversion` 23H124, `kern.osrelease` 23.6.0, `hw.ncpu`, `hw.memsize`,
`hw.model`, `machdep.cpu.brand_string` and others), with the documented
size, `ENOMEM` and `ENOENT` rules, and `kinfo_proc` for a process,
including `P_TRACED`, which apps check to see whether they are being
debugged. `proc_pidpath`, `host_statistics64`, `host_info`, `task_info` and
`getattrlist` (common, folder and file attributes) answer from Linux, and
`NSProcessInfo`'s processor and memory figures are `sysctl`'s. `dlopen`,
`dlsym`, `dlclose`, `dlerror` and `dladdr` work on Mac libraries and
bundles found by path, `@rpath`, `@executable_path` or `@loader_path`, on
the system frameworks Ferry provides by their Mac paths, and with the
special handles `RTLD_DEFAULT`, `RTLD_SELF`, `RTLD_NEXT` and
`RTLD_MAIN_ONLY`. `NSBundle`'s `load` and `principalClass` and CFBundle's
`CFBundleGetFunctionPointerForName` load plug-in bundles, and a plug-in's
classes find their own bundle. `@available` checks, and compiler-rt's
`_availability_version_check`, answer for macOS 14.7, as `NSProcessInfo`
does. Code loaded with `dlopen` stays loaded, and process listings,
volume attributes and most Mach statistics flavors are left out.

### Threads (freemac 1.202, Ferry 0.29.0)

Mac programs now run on real threads. `NSThread` starts them
(`detachNewThreadSelector:toTarget:withObject:`,
`detachNewThreadWithBlock:`, `initWithTarget:selector:object:` and
`initWithBlock:` with `start`) and answers about them (`currentThread`,
`mainThread`, `isMainThread`, a thread's dictionary, name, stack size and
quality of service, whether it is executing, finished or cancelled). A
thread can sleep, exit and be cancelled, and the will-exit and
will-become-multithreaded notifications are posted. Each thread has its
own run loop and autorelease pools, so `performSelectorOnMainThread:`,
`performSelector:onThread:`, `performSelectorInBackground:` and a run
loop's `performBlock:` deliver work to the thread named. `NSLock`,
`NSRecursiveLock`, `NSCondition`, `NSConditionLock`, `@synchronized`,
`OSSpinLock` and `os_unfair_lock` are real locks on this system's
pthreads, and the pthread calls Mac programs import are there, keeping
the Mac's static initialisers and numbers. Dispatch's global queues run on
a pool of worker threads; serial queues keep their order, and
`dispatch_sync`, groups, semaphores, barriers, `dispatch_after` and
`dispatch_apply` work between threads. The main queue runs only on the
main thread, from its run loop. `NSOperationQueue` runs operations at the
same time, up to its `maxConcurrentOperationCount`; its main queue stays on
the main thread. The Objective-C runtime (method caches, class set-up,
retain and release, weak references, associated objects, `+initialize`)
and Foundation's shared tables are safe to use from many threads. URL
transfers move on a thread of their own, and so does the rest of URL
loading: redirects, authentication challenges and server trust, cookies
and the URL cache are handled there under the network's lock, and a
delegate's answers to them may come later and from any thread. The shared
cookie storage (and its file), each credential storage and each URL cache
(its memory part and its files) keep their contents under a lock of their
own, so programs may use them from any thread too, and the libraries Ferry
opens for the network and for cryptography (libcurl, libcrypto, libssl)
are opened once whichever thread asks first. A task's exit and its file
handles' handlers are watched from a dispatch queue, so completion
handlers, termination handlers and readability handlers run on background
threads as on a Mac. AppKit is still for the main thread only; Ferry warns
once if it is used from another. Where a Mac would hang for ever (a lock
taken twice, `dispatch_sync` onto the current queue, the main thread
waiting for something nothing can do) Ferry stops the program with a
message instead. This was written from Apple's documentation and not
compared with a Mac; `docs/ferry-gui.md` lists what a Mac would settle.
Left out: `NSDistributedLock`, call stack symbols, dispatch sources for
descriptors, signals and processes, and priorities that change how threads
are scheduled.

### C++ programs (freemac 1.203, Ferry 0.30.0)

Mac programs written in C++ and Objective-C++ now run. They link a Mac's
libc++ and libc++abi, and Ferry serves both from this system's LLVM
libc++ and libc++abi (packages libc++1 and libc++abi1). Ferry opens them
only when a program needs them. Without them, a C++ program stops and
says what to install, and everything else runs as before.

- **The standard library.** Containers, strings, streams (`cout` keeping
  its order with `printf`), string and file streams with their positions,
  locales and `ctype`, regular expressions, `chrono`, `filesystem`,
  `function` and the smart pointers.
- **Exceptions.** They are thrown and caught by this system's libc++abi
  and unwound by its libunwind. They pass through the program, its own
  libraries and this system's code, with typeinfo and `dynamic_cast`
  working across images. `exception_ptr`, nested exceptions and
  `std::terminate`'s handler work too.
- **Threads.** `std::thread`, `mutex`, `condition_variable`, the timed,
  recursive and shared mutexes, `call_once`, futures, promises and `async`
  work on a Mac's layouts.
- **Objective-C++.** Under ARC, C++ ivars are built and destroyed with
  their object, and blocks copy and destroy the C++ objects they capture.
  Objective-C and C++ exceptions cross each other's frames: `@finally`
  and destructors run, `@catch (NSException *)` lets a C++ exception go
  on, and `catch (...)` and `@catch (...)` take either.

`ferry-cc` builds `.cpp` and `.mm` sources with LLVM's libc++ headers
(package libc++-dev) when given `-lc++`. Not yet:

- `thread_local` variables;
- wide file streams;
- Mac error numbers in error codes from the library (above 34);
- an `operator new` of the program's own used inside the library.

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
   MacPass, MacDown, Sequel Pro. Done in 1.167, and autosaving in
   (1.178); versions are still left out.
4. **Foundation's `NSThread`, `NSTask`/`NSPipe`/`NSFileHandle` and
   `NSXMLDocument`** (each used by five or more of the apps). `NSTask`,
   `NSPipe` and `NSFileHandle` came in (1.194), with `NSXMLParser`, which
   some apps use instead of `NSXMLDocument`; `NSXMLDocument` came in
   1.197 and `NSThread` in 1.202. `NSIndexSet`
   came in 1.159, `NSAlert` and `NSWorkspace` in 1.167, and `NSInvocation`
   with message forwarding, `NSJSONSerialization` and `NSDateFormatter`
   (English only, with `NSTimeZone` and a minimal `NSLocale`) in
   (1.170), and `NSCalendar`, `NSNumberFormatter` and the other
   formatters in (1.173).
5. **Updaters**: three apps' Sparkle frameworks check the Mac's version
   file or the app's code signature at start. Done in (1.200): Ferry
   serves a version file of its own (macOS 14.7, the same version that
   `NSProcessInfo`, `Gestalt` and `uname` report), an app's check of its
   own signature passes, and the Security framework's keychain and trust
   calls are there for what comes after. Next is running the three apps
   again to see what Sparkle asks for next.
6. **Threads**: done in 1.202. Programs run on real threads (`NSThread`,
   pthreads, dispatch's worker threads and concurrent operation queues),
   with AppKit kept to the main thread. Next is running the apps again to
   see whether any of them relied on Ferry having one thread.

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
