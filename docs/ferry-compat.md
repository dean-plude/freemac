# Ferry: which Mac apps run

This table says how far real Mac apps get under Ferry, and what stops
each one. It is updated as Ferry grows. The apps are small open-source
Objective-C apps with Intel (x86-64) builds, downloaded from their own
GitHub release pages and run on freemac without any change. **None of
them is in this repository**: they are tested by hand, and only what
happened is written down here. Ferry's own tests (`make check`) use
programs and nibs written for Ferry.

Last checked: 2026-11-23, with Ferry 0.9.0 (after M7: more apps, and the
Installer). A run with Ferry 0.36.0 (freemac 1.210) was planned but
couldn't be done, because the apps' release builds couldn't be downloaded
then. The rows below give what the last run showed, and then what the
apps' public source code says they reach with what Ferry has now. That
second part is a reading of the source, not a run.

## Summary

No real app runs all the way yet. Nine apps have been tried (the seven of
M6, plus MacDown and Sequel Pro). At the last run, seven of them started
and got through `NSApplicationMain` and their main nib. ShiftIt got all
the way into its event loop and kept running, and Gas Mask got through its
whole launch until it laid out its main window. Each of the others
stopped with a message that named what was missing.

Much of what stopped them then is in Ferry now: tab views, split views,
table and outline views, menu bar items, the document classes, the
Security framework's answers for the Sparkle updaters, the Mac's version
file, threads, gradients, shadows, and split view and tab view
controllers. MacPass's document window is built on a split view
controller and its preferences on a tab view controller, so it should now
get past both. Hex Fiend still needs Swift. MacDown's web views can be made now (Ferry 0.40.0), and the `WebFrameView` and DOM classes it also uses came in Ferry 0.42.0, but its preview was not tried. Running all nine again is the next step.

Ferry also has its own **Installer**. Three real installers were tried,
and all three install: the MacPorts and XQuartz packages (`.pkg`) and the
Sequel Pro disk image (`.dmg`). See "Installers" below.

## The apps

| App (version) | What it is | How far it gets | What stops it |
| --- | --- | --- | --- |
| [Hex Fiend](https://github.com/HexFiend/HexFiend) 2.18.1 | Hex editor | Doesn't start | Part of it is written in Swift (`libswiftCore.dylib`), a known limit. All 16 of its nibs (`NIBArchive`) load when tried on their own. Its gradients are in Ferry now, but that doesn't help while Swift is missing |
| [Flycut](https://github.com/TermiT/Flycut) 1.9.6 | Clipboard history (menu bar) | At the last run: starts, loads its main nib, sets up its defaults and bindings, registers its global hotkey (pressed on freemac's desktop from freemac 1.215), and opens its preferences nib | At the last run, `NSTabView` in its preferences nib, then `NSStatusBar` for its menu bar item. Both are in Ferry now (1.155 and 1.157). Its source also uses `NSDistributedNotificationCenter` and `NSRunningApplication`, which are in Ferry now (1.213): its notifications pass between Ferry programs on the session bus, and its other copies are found by bundle identifier. Its shortcut recorder's gradients and shadows are in Ferry now. (Not re-run since M7) |
| [KeyCastr](https://github.com/keycastr/keycastr) 0.9.18 | Shows the keys you press | At the last run: starts, loads its main nib (`NIBArchive`) | At the last run, `NSInvocation` and `NSMethodSignature` (forwarding), which came in (1.170). Its source also uses `NSAnimation`, which is in Ferry now (1.213), and `NSAppleScript`, which is there but runs no scripts and answers an error. Its key labels' shadow is in Ferry now and is drawn (1.213). It also needs to see every key pressed in other apps, which Wayland doesn't allow. (Not re-run since M7) |
| [ShiftIt](https://github.com/fikovnik/ShiftIt) 1.6.6 | Moves and resizes other apps' windows | **Runs**: starts, loads its nibs, asks whether it may use the Accessibility API (freemac asks the user once, as a Mac does), and waits in its event loop | At the last run, nothing visible, because its only window was a status bar item. `NSStatusBar` is in Ferry now (1.157). Moving other apps' windows works on freemac's desktop from freemac 1.215 (Ferry 0.41.0), once the user allows it, through the Accessibility API and Wayfire's IPC. (Not re-run since M7) |
| [Spectacle](https://github.com/eczarny/spectacle) 1.2 | Window tiling by shortcut | At the last run: starts, loads its nibs, registers its shortcuts (pressed on freemac's desktop from freemac 1.215) | At the last run, its Sparkle updater's check of its own code signature (`SecStaticCodeCreateWithPath`), which passes since (1.200). It also couldn't save its shortcuts file. From its source, its shortcut recorders now draw their gradient and their text shadow, and it also uses `NSTrackingArea`, which is in Ferry now (1.213), and `NSAppleScript`, which is there but runs no scripts and answers an error. Its shortcuts are pressed on freemac's desktop from freemac 1.215, and the Accessibility API is there too, once the user allows it, as for ShiftIt. (Not re-run since M7) |
| [MacPass](https://github.com/MacPass/MacPass) 0.8.1 | KeePass password manager | At the last run: starts; all 30 of its nibs (`NIBArchive`) load on their own | At the last run, the document classes, which came in 1.167. From its source, the next stop was its document window's split view controller (`MPDocumentSplitViewController`, built on `NSSplitViewController`), which was left out, and its preferences' tab view controller (`MPTabViewController`, on `NSTabViewController`). Both are in Ferry now, with `NSGradient` and `NSShadow`. Its source also uses `NSCollectionView`, `NSTrackingArea` and `NSMutableCharacterSet`, which are all in Ferry now (1.212 and 1.213). (Not re-run since M7) |
| [Gas Mask](https://github.com/2ndalpha/gasmask) 0.8.6 | Hosts-file editor (menu bar) | At the last run: starts (its Mac OS X 10.7 start-up format loads now), sends its log to a file, uses ICU's regular expressions (through RegexKitLite), watches network reachability, registers its hotkey, loads its preferences (an `NSUserDefaultsController` subclass) and its hosts lists, and sets up its main window | At the last run, `NSSplitView` in its main window (`positionOfDividerAtIndex:`). `NSSplitView` and `NSOutlineView`, its hosts list, are in Ferry now (1.155 and 1.159), as are its gradients and shadows. Its source also uses `NSTrackingArea` and `NSTextAttachment`, which are in Ferry now (1.213). (Not re-run since M7) |
| [MacDown](https://github.com/MacDownApp/macdown) 0.7.2 | Markdown editor | At the last run: starts, loads its main nib | At the last run, its Sparkle updater's assertion that the Mac's version file (`/System/Library/CoreServices/SystemVersion.plist`) exists. Ferry serves one since (1.200). It is built on `NSDocument` and on WebKit's older `WebView`, which are both in Ferry now (1.214), with the `WebFrameView` and DOM classes it also uses (1.217). (Not re-run since M7) |
| [Sequel Pro](https://github.com/sequelpro/sequelpro) 1.1.2 | MySQL client | Installed from its `.dmg` by Ferry's Installer; at the last run it started and loaded its main nib | At the last run, an array made with a nil object (`initWithObjects:count:`), most likely one of the classes it uses that Ferry didn't have being nil. Tables, outline and split views, the document classes, gradients and shadows are in Ferry now. From its source, the classes it was known to miss are all in Ferry now: WebKit's `WebView` came in 1.214. `NSRulerView`, which its line-number ruler is built on, came in 1.212, and `NSAnimation`, `NSTrackingArea` and `NSDistributedNotificationCenter` in 1.213. (Not re-run since M7) |

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
- **Carbon and Accessibility answers**: keyboard layouts have no Mac layout data, which is how a Mac answers when it isn't available. From freemac 1.215, global hotkeys are pressed on freemac's desktop (accepted but never pressed elsewhere), and the Accessibility API is trusted once the user allows the app. SystemConfiguration's network reachability
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
when the app wants one. Left out: versions, and renaming, moving and
locking from the title bar. Printing came in
(1.206). (`prepareWithInvocationTarget:` answered nil until Ferry had
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
(`@count`, `@sum`, `@avg`, `@min`, `@max` and the unions), and `NSPredicate` for filtering (with expressions and `MATCHES` from freemac 1.211, Ferry 0.37.0). Removing an observer that isn't
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
files and Mach ports (those for descriptors, signals and processes came in
1.205), and priorities that change how threads are scheduled.

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

- wide file streams;
- Mac error numbers in error codes from the library (above 34);
- an `operator new` of the program's own used inside the library.

### Thread-local variables (freemac 1.204, Ferry 0.31.0)

Mac programs can now use thread-local variables: C's `__thread` and
`_Thread_local`, Objective-C's `__thread` and C++'s `thread_local`. Each
image's variables are bound to Ferry's own `_tlv_bootstrap`, so every
thread gets its own copy of them the first time it uses one, started from
the image's first values and zeroed where they have none. That holds for
the program, the libraries it links and libraries and plug-ins opened later
with `dlopen`, and for every kind of thread Ferry runs: pthreads,
`NSThread`, `std::thread` and dispatch's worker threads. C++ objects with
constructors are built on each thread when it first uses them, and their
destructors, registered with `_tlv_atexit` or `__cxa_thread_atexit`, run in
reverse order when the thread ends. For the thread that calls `exit`, and
for the main thread when `main` returns, they run before the program's
static destructors. A thread's copies are freed when it ends. `dlsym` of a
thread-local variable gives the calling thread's copy, and the functions in
an image's thread-local init section run once, when the image is set up.
`ferry-cc` links programs that use thread-local variables. The thunk
changes no register but the one it answers in, as the compiler expects,
and it keeps the vector registers too. This was written from the Mach-O
format's public description and the code clang emits, and not compared
with a Mac; `docs/ferry-gui.md` lists what a Mac would settle. The
destructors of threads still running when the program exits are not run,
and the variables of images after the first 128 that have them are reached
the slow way.

### Sockets and streams (freemac 1.205, Ferry 0.32.0)

Mac programs get BSD sockets with Mac layouts. Ferry converts every
socket address between the Mac form (with `sa_len`, and AF_INET6 as 30)
and Linux's, and converts `msghdr` and control messages (32-bit lengths,
4-byte alignment), `timeval` socket options, `addrinfo` (whose
`ai_canonname` comes before `ai_addr` on a Mac), `ifaddrs` (with an AF_LINK
entry for each interface) and `fd_set`. Socket options with Mac numbers are
mapped, and the Mac-only ones are made: SO_NOSIGPIPE (sends are made with
MSG_NOSIGNAL), SO_NREAD, TCP_KEEPALIVE, LOCAL_PEERPID and LOCAL_PEERCRED.
Errors come back as Mac errno and EAI_ values.

kqueue and kevent are built on epoll. Each event in a kqueue gets a
descriptor of its own: a duplicate for READ and WRITE, a timerfd for
TIMER, a pidfd for PROC, an eventfd for USER, and for SIGNAL a counter fed
by Ferry's own signal handler, so the program's disposition stays as it set
it. select and poll take Mac structures and flags. libdispatch's READ,
WRITE, SIGNAL, PROC and TIMER sources run on an internal kqueue served by a
thread.

CFSocket works with a run loop source, using the run loop's descriptor
watching. CFReadStream, CFWriteStream, NSInputStream and NSOutputStream
work over data, files, memory, a bound pair, a native socket, and a host
and port (CFStreamCreatePairWithSocketToHost and
getStreamsToHostWithName:port:inputStream:outputStream:), with delegates,
client callbacks, run loops or a dispatch queue, and blocking use. The
connection is made on a worker thread, so opening never blocks. TLS
(kCFStreamPropertySSLSettings or NSStreamSocketSecurityLevelKey) uses the
system's OpenSSL, and the server's certificates are checked with the same
Security.framework trust calls a program can use itself; the peer trust is
available as kCFStreamPropertySSLPeerTrust. CFNetwork.framework is an alias
of Foundation.

NSNetService and NSNetServiceBrowser are there, but without Bonjour: they
say they will start and then fail with NSNetServicesUnknownError, as a Mac
does when mDNSResponder can't be reached. TXT records are made and read.

### Printing and fonts (freemac 1.206, Ferry 0.33.0)

Mac apps can now print. `NSPrintInfo` holds the paper, margins,
orientation, scaling, pagination and centring in its dictionary, as on a
Mac, and is copied and archived with `NSCoding`; the shared one starts on
the paper this system's locale uses. `NSPrintOperation` prints a view on
pages of that paper, by automatic, fit or clip pagination or by the view's
own `knowsPageRange:` and `rectForPage:`, calling `beginDocument`,
`endDocument`, `beginPageInRect:atPlacement:`, `adjustPageHeightNew:...`,
`drawPageBorderWithSize:` and `pageHeader` and `pageFooter` as Apple's
documentation describes. The pages are drawn by the view's own
`drawRect:` into a PDF with Cairo. The print panel and Page Setup are
GTK's print and page setup dialogs, run modally or as sheets, and what is
chosen in them is written back into the print info; a PDF goes to a file
(Print to File and `NSPrintSaveJob`), to the default PDF viewer (Preview),
or to a printer through GTK or `lp`. `PDFOperationWithView:...` and
`dataWithPDFInsideRect:` make PDF data without a panel, and views and
windows have `print:`, `printJobTitle` and `writePDFInsideRect:toPasteboard:`.
A text view breaks its pages at the edges of lines. `NSDocument`'s Print…
and Page Setup… menu items are enabled and work through
`printOperationWithSettings:error:`, `printDocumentWithSettings:...` and
the document's own print info.

`NSFontManager` lists the installed families and their members from
Pango and fontconfig, makes fonts by family, traits, weight and size, and
converts fonts to and from bold and italic and to other sizes, families,
faces and weights. Its font menu's Bold, Italic, Bigger and Smaller items
work, and the Show Fonts toolbar item opens the font panel. `NSFontPanel`
is GTK's font chooser. What is chosen in it, or in the menu, goes to
`changeFont:` down the responder chain, so a text view changes the
selection's fonts run by run, keeping what wasn't chosen, or the typing
font when nothing is selected.

Left out: accessory views in the panels, the progress panel, printing the
selection, a printer's own margins, multi-page EPS, font collections, the
Styles panel and undo of font changes. This system has no `lp`, so a job
for a printer that the print dialog didn't choose fails here. The work
was written from Apple's documentation and not compared with a Mac;
`docs/ferry-gui.md` lists what a Mac would settle.

### Notifications and the Dock (freemac 1.207, Ferry 0.34.0)

Mac programs can post notifications with UNUserNotificationCenter
(UserNotifications.framework, an alias of Ferry's AppKit) or with the older
NSUserNotificationCenter. Both show them through the desktop's notification
server, over the freedesktop.org `org.freedesktop.Notifications` interface
on the session bus. The notification's title is the summary, and its
subtitle and body make the body, with any markup characters escaped. The
app's name comes from CFBundleDisplayName or CFBundleName, and its icon is
the one Ferry or freemac-mac-app put in the icon theme. Actions become
buttons, a click on the notification itself is the default action, and a
text input action or an NSUserNotification reply button becomes an inline
reply on servers that offer one (KDE's way of doing it). What the user does
comes back on the main run loop and reaches the delegates as on a Mac:
`didReceiveNotificationResponse:` with the action and any text, and
`didActivateNotification:` with the activation type. Removing a delivered
notification closes it on the server. Requests can wait for a time
interval or a calendar date, and NSUserNotifications for a delivery date
with a repeat interval. With no notification server, or no session bus,
nothing is shown, every call still answers, and `FERRY_VERBOSE` says once
why.

The Dock is told about the app with the
`com.canonical.Unity.LauncherEntry` signal, which freemac's Dock reads.
NSApp's dockTile sends a badge label that is a plain number as the Dock's
count, and any other label, such as "New" or "!", as words that freemac's
Dock shows in the badge (`x-freemac-badge-label`, with a count of 1 for
other docks). `requestUserAttention:` makes the app's Dock icon ask for
attention (one bounce, or until the app becomes active for a critical
request), and the delegate's `applicationDockMenu:` is served as a dbusmenu
menu, which freemac's Dock shows in the app's right-click menu, below its
windows. The tile is sent again when freemac's Dock starts.

From freemac 1.208, a badge label that isn't a number, such as "New" or "!",
shows as words in freemac's Dock badge, and the menu from the delegate's
`applicationDockMenu:` shows in the app's right-click menu in freemac's Dock.

### Core Data (freemac 1.209, Ferry 0.35.0)

Mac programs can now use Core Data (`CoreData.framework`). A model is built
in code, or read from the XML source that Xcode keeps in a `.xcdatamodeld`
folder. The model has entities with inheritance, attributes of every
documented type (with default values, and optional, transient and
transformable attributes), and relationships (to-one, to-many and ordered,
with inverses and the nullify, cascade, deny and no-action delete rules).
`NSManagedObject` subclasses get their `@dynamic` accessors made on first
use. The accessors cover objects and scalars, primitive values and the
to-many mutable proxies, and they work with KVC and KVO. Faults, object IDs,
`changedValues` and validation with the documented error codes are there.

`NSManagedObjectContext` inserts, deletes, saves, rolls back, resets and
refreshes, and undoes through its `NSUndoManager`. It posts the will-save,
did-save and objects-did-change notifications. Contexts can be on the main
queue or on a private queue (with `performBlock:` and
`performBlockAndWait:`), and can have a parent context. The merge methods,
`automaticallyMergesChangesFromParent` and the five merge policies work.
`NSFetchRequest` takes a predicate, sort descriptors, a limit and an offset.
It gives objects, object IDs, dictionaries or a count, with or without
unsaved changes. `NSFetchedResultsController` gives sections and tells its
delegate what changed. `NSPersistentContainer` and
`NSPersistentStoreDescription` load stores into Application Support.

The stores are SQLite (this system's SQLite, in Ferry's own table layout),
binary (Ferry's keyed archiver) and in memory. Each keeps its metadata. A
store opens under a changed model when what changed can be inferred:
entities and attributes added or removed. `NSBatchDeleteRequest` and
`NSBatchUpdateRequest` change an SQLite store's rows directly.
`NSArrayController` and `NSObjectController` work in entity mode: they
fetch their content, `add:` inserts and `remove:` deletes. Foundation gained
`NSOrderedSet` and `NSUUID` for Core Data's ordered relationships and UUID
attributes.

Left out: compiled models (`.mom` and `.momd`), whose format isn't
published, so most apps that ship only a compiled model stop there, and
Ferry says so once. Also left out are store files made by a Mac, the XML store, heavyweight migration, and uniqueness constraints. Expressions in fetches came later, in freemac 1.211 (Ferry 0.37.0). The work was written from Apple's documentation and not
compared with a Mac; `docs/ferry-gui.md` lists what a Mac would settle.

### Expressions and decimal numbers (freemac 1.211, Ferry 0.37.0)

Ferry's Foundation now has `NSExpression` and `NSComparisonPredicate` as
public classes, and every predicate the parser reads is built from them.
Expressions come in every documented form: constants, `SELF`, key paths,
variables, functions (also sent to a target), aggregates, the set
expressions, subqueries, `ANYKEY`, blocks and conditionals. The built-in
functions are there, from `sum:`, `count:`, `average:`, `median:`, `mode:`
and `stddev:` to the arithmetic, the bitwise functions, `sqrt:`, `log:`,
`raise:toPower:`, the string functions, `random` and `now`. Format strings
take arithmetic, `FUNCTION`, `TERNARY`, `CAST`, `SUBQUERY` and indexes like
`tags[FIRST]`. `MATCHES` matches regular expressions with this system's ICU,
through `NSRegularExpression`. `predicateWithSubstitutionVariables:` fills
in variables, and predicates can be archived.

`NSDecimalNumber`, `NSDecimalNumberHandler` and the `NSDecimal` functions
(`NSDecimalAdd` and the others, `NSDecimalRound`, `NSDecimalNormalize`,
`NSDecimalCompare`, `NSDecimalString`) do exact arithmetic in base 10, so
0.1 and 0.2 add up to 0.3. Numbers keep up to 38 digits, in the four
rounding modes, and raise the documented exceptions on overflow, underflow
and division by zero unless a handler says not to. Decimal numbers compare
and hash with other `NSNumber`s, and `NSNumber` has `decimalValue`.
`NSScanner` reads them with `scanDecimal:`, `NSNumberFormatter` writes
their digits exactly and makes them with `generatesDecimalNumbers`, and
they go through keyed archiving and `NSJSONSerialization`.

In Core Data, decimal attributes now keep their exact digits, as text, in
the SQLite and binary stores. A store an older Ferry wrote, which kept them
as doubles, is read as before, and an SQLite store's column is changed to
text the first time it is opened for writing. A dictionary fetch takes
`NSExpressionDescription`s in `propertiesToFetch`, with aggregates such as
`sum:`, `count:`, `min:`, `max:` and `average:`, and it groups by
`propertiesToGroupBy` and keeps the groups that pass `havingPredicate`. This
is worked out in memory, and so is `MATCHES` in a fetch's predicate.

Left out: `distanceToLocation:fromLocation:` (Ferry has no Core Location),
archives of predicates made by a Mac, numbers read from JSON as decimals,
aggregates done in SQL, and derived attributes. The work was written from
Apple's documentation and not compared with a Mac; `docs/ferry-gui.md` lists
what a Mac would settle.

### Collection views and rulers (freemac 1.212, Ferry 0.38.0)

Ferry's AppKit now has `NSCollectionView`, in both of its kinds. The
item-based kind takes a data source with sections and items, and makes
`NSCollectionViewItem`s and supplementary views of registered classes or
nibs with `makeItemWithIdentifier:forIndexPath:`, reusing the ones that
scroll out of sight. `NSCollectionViewFlowLayout` lays them out in lines
across or down, with item sizes, spacing, insets, headers and footers
(pinned if asked) and a delegate's own sizes, and
`NSCollectionViewGridLayout` lays them out in rows and columns. Items are
found by point and index path and scrolled to, and selected by code, by
the mouse and by the arrow keys, with the delegate's should and did calls
and single, multiple and empty selection. Items and sections are
inserted, deleted, moved and reloaded, alone or in
`performBatchUpdates:completionHandler:`. The older kind takes a
`content` array and an `itemPrototype`, which is copied for each object,
and binds `content` and `selectionIndexes`. A collection view and its
prototype load from nibs in both forms: the prototype is copied from the
nib, with its own view, outlets, actions and bindings.

`NSRulerView` and `NSRulerMarker` are there too. A scroll view makes its
rulers of the class `rulerViewClass` names when `hasHorizontalRuler` or
`hasVerticalRuler` is set, and lays them out beside the content while
`rulersVisible` is set. Rulers have their thicknesses, a client view,
measurement units (the four built in and any registered by the app), an
origin offset, an accessory view and a ruler line, and they draw their
marks and labels in `drawHashMarksAndLabelsInRect:`, which an app's own
subclass can override, as Sequel Pro's line-number ruler does. Markers
are added, drawn, dragged and dragged off with the client's say, and
added with `trackMarker:withMouseEvent:`.

Left out: animation, dragging items, drawn decoration views, the
compositional layout and diffable data sources, and reading rulers' and
the layouts' settings from nibs. The nib keys of the collection view are
a guess, and the work was written from Apple's documentation and not
compared with a Mac; `docs/ferry-gui.md` lists what a Mac would settle.

### Tracking areas, shadows, animations and other programs (freemac 1.213, Ferry 0.39.0)

Views can track the mouse with `NSTrackingArea`: each mouse event a window
gets is checked against the areas of the views shown in it, and the area's
owner hears `mouseEntered:`, `mouseExited:`, `mouseMoved:` and
`cursorUpdate:` as its options ask, live in the key window, in the active
app, while its view is first responder or always. Views get
`updateTrackingAreas` when their geometry changes, and the older tracking
rectangles and cursor rectangles work too. `NSCursor` shows GTK's named
cursors, or a cursor made from an image, with push, pop and hiding.
Spectacle's and MacPass's controls, Gas Mask's lists and Sequel Pro's
views use these.

Ferry's Core Graphics now draws shadows: `CGContextSetShadow` and
`CGContextSetShadowWithColor` put a blurred, offset copy under each shape,
image, gradient and line of text, and under a transparency layer as a
whole. So `NSShadow` and the `NSShadow` text attribute are drawn, which
gives Flycut's, Spectacle's and KeyCastr's labels and controls their
shadows, and Ferry no longer says that shadows aren't supported.

`NSAnimation` runs on the run loop at its frame rate, blocking or not,
with its four curves, progress marks, its delegate and the progress mark
notification. `NSViewAnimation` moves, resizes and fades views and
windows. KeyCastr and Sequel Pro animate this way.

Programs can talk to each other. `NSDistributedNotificationCenter` carries
notifications between Ferry programs on the D-Bus session bus, with their
user info, and works quietly within the program when there is no bus.
`NSRunningApplication` describes this program and finds the other Ferry
programs by bundle identifier or process, and NSWorkspace lists them.
Flycut and Sequel Pro use these to find their other copies.
`NSAppleScript` is there for the apps that run scripts (KeyCastr and
Spectacle), but runs nothing: it answers an error, and Ferry says so once.

Foundation gained `NSMutableCharacterSet` and the rest of `NSCharacterSet`
(the sets made from Unicode's categories, the URL sets, ranges, bitmaps
and the planes past the first), with percent encoding, which MacPass
uses. AppKit gained `NSTextAttachment`, an image or a cell drawn inline in
text, wherever Ferry draws attributed strings, which Gas Mask uses.

Left out: AppleScript itself, the notifications a Mac's system posts,
programs this system runs without Ferry, layer shadows and shadows in PDF
contexts. The work was written from Apple's documentation and not
compared with a Mac; `docs/ferry-gui.md` lists what a Mac would settle.

### WebKit (freemac 1.214, Ferry 0.40.0)

Mac programs can now show web pages with `WebKit.framework`, which Ferry
draws with this system's WebKitGTK (libwebkit2gtk-4.1). The library is
opened only when a program makes its first web view, so programs that
link WebKit and never show a page don't need it, and where it isn't
installed, or there is no display, a web view stays empty, Ferry says so
once, and the program goes on.

`WKWebView` takes a `WKWebViewConfiguration` with its preferences, a
user content controller and a website data store, the default one or one
of its own that keeps nothing. It loads requests for files, HTML strings
and data, goes back, forward and to an item of its back-forward list,
reloads and stops, and its title, URL, progress, loading state and back
and forward state can be observed with key-value observing.
`evaluateJavaScript:completionHandler:` gives the result as Foundation
objects, in the page's world or in a content world of its own, and user
scripts and script message handlers work in both. The navigation
delegate is asked about each navigation and each response and told when
one starts, is committed, finishes or fails, and the UI delegate shows
the page's alerts, confirms and prompts and makes the new windows a page
opens. `takeSnapshotWithConfiguration:completionHandler:` gives an
`NSImage` of the page.

The older `WebView` is there too, with `WebFrame`, `WebDataSource`,
`WebPreferences`, its frame load, policy and UI delegates and its
progress notifications. `stringByEvaluatingJavaScriptFromString:` answers
at once, and `WebScriptObject` reads, sets and calls the page's objects.

The web view is GTK's own, placed over the `NSView` in its window and
clipped to what its superviews show. It follows the view when it moves,
is resized or hidden, takes the keyboard when it becomes the first
responder, and keeps its page when its window is closed or it moves to
another window.

Left out: downloads, the cookie store and scheme handlers. Requests are loaded as GETs. The DOM classes, `WebFrameView` and subframes in the older `WebView` came in freemac 1.217 (Ferry 0.42.0), in the section below. The work was written from Apple's documentation and
WebKitGTK's, tried on X11 and not on Wayland, and not compared with a
Mac; `docs/ferry-gui.md` lists what a Mac would settle.

### Global hotkeys and other apps' windows (freemac 1.215, Ferry 0.41.0)

Mac apps' global shortcuts now work on freemac's desktop. Carbon's
`RegisterEventHotKey` asks Strata, freemac's Wayfire plugin, to bind the
combination; when the user presses it anywhere, Strata sends the press to
that app alone, and it reaches the app's Carbon event handlers
(`InstallEventHandler`, `GetEventParameter` with the hot-key ID,
`CallNextEventHandler`) and its global key-down monitors. Only the
combinations an app registered ever reach it, and each needs Command,
Option or Control (or is a function key), so no app can read other keys
this way. Spectacle's and ShiftIt's window shortcuts and Flycut's
clipboard key use this. On another desktop, a hotkey is still accepted
but never pressed.

Window managers can move and resize other apps' windows, as on a Mac,
through enough of the Accessibility API: the system-wide and application
elements, the focused app and its focused window, every window's title,
position, size and minimized and full-screen state, and `AXRaise`, with
`AXValue` for points and sizes. Each move goes to Wayfire as a
configure-view call, onto another display when the window is moved there.
`NSScreen` lists every display, with its visible frame, from Wayfire.

As on a Mac, the user decides. Until an app is allowed, every call answers
that the API is disabled. The first time the app asks with the prompt
option, freemac asks "Allow “Spectacle” to control other windows?", keeps
the answer, and never asks again; Dials > Privacy & Security > Control
Other Windows can turn an app off or forget it.

Left out: what is inside other apps' windows (their buttons and text),
observers, reading other apps' key presses in general (KeyCastr), and
plain keys as hotkeys. None of the apps was run again. The work was written
from Apple's documentation and not compared with a Mac; `docs/ferry-gui.md`
lists what a Mac would settle.

### WebKit's frames and DOM (freemac 1.217, Ferry 0.42.0)

The older `WebView` now has its frame views and the DOM classes, which
Markdown editors like MacDown use to keep the preview where the text is.
Each frame has a `WebFrameView` whose document view is as large as the
page and sits in a scroll view scrolled where the page is: a program can
read the page's height, watch the clip view's bounds as the page scrolls,
and scroll the page with `scrollPoint:` or `scrollToPoint:`.

`DOMDocument`, `DOMElement`, `DOMHTMLElement` and some thirty of its
subclasses, `DOMText`, `DOMAttr`, `DOMNodeList`, `DOMHTMLCollection` and
`DOMCSSStyleDeclaration` read and change the page as a Mac's do: finding
nodes by id, tag, class and selector, making and moving them, their
attributes, HTML, text, style, sizes and scroll positions. Each call
waits for the page, as `stringByEvaluatingJavaScriptFromString:` does,
one object stands for each node while it is kept, and an exception in
the page raises `DOMException`.

The older `WebView` also knows its subframes now: `childFrames`, their
names and documents, and their loads told to the frame load and policy
delegates for the right frame. The resource load delegate is told of
each resource a page loads, the preferences' user style sheet is
applied, and `window.open` asks the policy delegate first and gives the
page the new window.

Left out: events, ranges and the other DOM classes, the cookie store,
downloads, and requests' methods, headers and bodies. A subframe's
failed loads aren't told. The work was written from Apple's
documentation, WebKitGTK's and the DOM standards, and not compared with
a Mac; `docs/ferry-gui.md` lists what a Mac would settle.

## What the apps need most

Counted over the nine apps:

1. **More views**: done for the ones every app's nibs use. Split views
   and tab views came in 1.155; table and outline views, which stopped Gas
   Mask and most likely Sequel Pro, in 1.159; `NSPopUpButton`,
   `NSToolbar`, `NSSegmentedControl`, `NSSearchField` and `NSStackView` in
   1.164. Split view and tab view controllers, which MacPass builds
   its windows on, came in 1.210 with `NSGradient` and `NSShadow`, the
   drawing classes six of the apps use. Collection views and rulers, which MacPass and Sequel Pro use, came in 1.212. Tracking areas and cursors, which four of the apps use, came in 1.213, with shadows drawn and `NSAnimation`. Next is running the apps again to see which views they still miss.
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
7. **Other programs**: `NSDistributedNotificationCenter` and `NSRunningApplication` (Flycut, Sequel Pro) came in 1.213, between Ferry programs. `NSAppleScript` (KeyCastr, Spectacle) is there but runs nothing, since there is no AppleScript here.

Global hotkeys and moving other apps' windows came in freemac 1.215 (Ferry 0.41.0), through Strata and Wayfire's IPC. Reading other apps' key presses in general (KeyCastr) stays out of reach by design on Wayland.

## Trying an app yourself

```sh
ferry "Some App.app"
FERRY_VERBOSE=1 ferry "Some App.app"   # every library, missing call and class
ferry SomeApp.pkg                      # or .dmg: Ferry's Installer
```

Ferry prints what it leaves out on the way; the last line before it
stops says why.
