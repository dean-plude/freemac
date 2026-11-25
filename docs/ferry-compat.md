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

### What the apps call next (freemac 1.219, Ferry 0.43.0)

A search of the nine apps' public source for the calls Ferry didn't have
came up with these, and this round adds them.

The public source of the nine apps (MacPass, MacDown, Sequel Pro, Gas Mask,
Flycut, ShiftIt, Spectacle, Hex Fiend, KeyCastr) was searched for the calls
they make that Ferry didn't have. Counted by app:

| Calls | Apps |
| --- | --- |
| `addChildWindow:ordered:` (4), `removeChildWindow:` (3), `setCollectionBehavior:` (3), `ignoresMouseEvents`, `hidesOnDeactivate` | Flycut, KeyCastr, Hex Fiend, Sequel Pro, Spectacle, ShiftIt |
| Login items: `LSSharedFileList` and `SMLoginItemSetEnabled` | Gas Mask, ShiftIt, Spectacle, Flycut |
| `checkResourceIsReachableAndReturnError:`, `enumeratorAtPath:`/`NSDirectoryEnumerator`, `displayNameAtPath:` (3 each) | Gas Mask, MacDown, Sequel Pro, MacPass |
| `enumerateSubstringsInRange:options:usingBlock:`, `lineRangeForRange:` (3 each) | MacDown, Sequel Pro, Flycut |
| `NSAffineTransform` (3) | ShiftIt, Hex Fiend, MacDown |
| `NSAssertionHandler`, `NSAssert` and the garbage-collection calls (3) | Sequel Pro, Hex Fiend, KeyCastr |
| String encodings past UTF-8 and Latin-1 | Hex Fiend, Sequel Pro, Flycut |
| `CFArrayRemoveAllValues`, `CFArrayReplaceValues`, `kCFBundleVersionKey` (3), and the Core Foundation string calls RegexKitLite makes | Sequel Pro, MacDown, Hex Fiend |
| `NSFileCoordinator` (2) | MacPass, MacDown |
| `setDropItem:dropChildIndex:`, `setDraggingSourceOperationMask:forLocal:` (3) | not done this round |
| `NSArchiver`/`NSUnarchiver` (3) | not done: the old typed-stream format isn't publicly documented |
| `CGWindowListCopyWindowInfo` (3), posting `CGEvent`s (2) | not done this round |

The WebKit items suggested for this round (downloads, the cookie store,
request bodies, DOM events) are used by none of the nine apps, so they
ranked last and weren't done.

Strings now convert to and from some seventy-five encodings: Ferry's own
for ASCII, Latin-1, the UTF forms and the non-lossy ASCII escapes, and
ICU's for the rest (Mac Roman, the Windows code pages, Shift JIS, EUC,
GB 18030, Big5, KOI8 and their kin), with their names, IANA names and
Windows code pages on Core Foundation's side, and a file's encoding found
from its bytes. Hex Fiend, Sequel Pro and Flycut need these. Text can be
walked by line, paragraph, word, sentence and composed character
(`enumerateSubstringsInRange:options:usingBlock:`, `lineRangeForRange:`),
normalized in the four Unicode forms, and searched for characters from a
set in any direction, as MacDown, Sequel Pro and Flycut do.

Core Foundation's arrays and dictionaries take callbacks of their own, as
Sequel Pro and Hex Fiend use them from C for plain pointers and C strings,
with the rest of their calls (binary search, sorting, replacing ranges,
applying functions), `CFUUID`, more of `CFURL` and `CFString`, and the
bundle keys.

The file calls Gas Mask, MacDown, Sequel Pro and MacPass make are in:
directory enumerators, display names, setting attributes, links, URL
resource values and reachability, the trash (freedesktop.org's, so the
desktop's own trash shows what an app throws away), bundle resources by
URL, and `NSFileCoordinator` with file presenters within one program.
`NSAssert` and its kin raise as on a Mac, and the garbage-collection calls
of older apps do nothing harmful.

Windows can have child windows that move, hide and close with their
parent, panels hide while their app isn't active, and the window
properties menu-bar apps set (ignoring the mouse, collection behaviour,
levels) are kept. `NSAffineTransform` transforms points, paths and
drawing, and paths give their elements back.

Login items, which Gas Mask, ShiftIt, Spectacle and Flycut offer, are
freemac's own: an app the user asks to open at login gets an entry in
`~/.config/autostart` that runs it through Ferry, and it shows in Dials >
Login Items, where it can be taken off. `SMLoginItemSetEnabled` does the
same for a helper inside the app, without listing it.

Left out: table views' drop retargeting, `NSArchiver`, listing other
programs' windows and posting events, and the WebKit items (downloads, the
cookie store, request bodies and DOM events), which none of the nine apps
uses. None of the apps was run again; `docs/ferry-gui.md` lists what a Mac
would settle.

### Other apps' windows, posted keys, drag and drop (freemac 1.220, Ferry 0.44.0)

What 1.219's search of the nine apps' source found and left for later.

| Calls | Apps | Now |
| --- | --- | --- |
| `CGWindowListCopyWindowInfo`, `kCGWindowNumber`, `kCGWindowOwnerPID`, `kCGWindowBounds`, `kCGWindowLayer` | ShiftIt, MacPass | done, behind Control Other Windows for other apps' windows |
| `CGEventCreateKeyboardEvent`, `CGEventSetFlags`, `CGEventPost` (Flycut's Cmd-V to paste, MacPass's Autotype) | Flycut, MacPass | keys done, behind the same consent; mouse posting and event taps refused |
| `setDropRow:dropOperation:`, `setDraggingSourceOperationMask:forLocal:`, `tableView:writeRowsWithIndexes:toPasteboard:`, `tableView:validateDrop:…`, `tableView:acceptDrop:…` | Sequel Pro, MacPass | done, within the app |
| `setDropItem:dropChildIndex:`, `outlineView:writeItems:toPasteboard:`, `outlineView:pasteboardWriterForItem:`, `outlineView:validateDrop:proposedItem:proposedChildIndex:` | MacPass, Sequel Pro, Gas Mask | done, within the app |
| `CFSetCreateMutable`, `CFBag…` with callbacks | asked for this round; none of the nine apps' source calls them directly | done |
| `NSFilePresenter`, `presentedItemDidChange` | Hex Fiend, MacPass | `NSDocument` presents its file, for writers in the same program |

**Consent.** Listing other apps' windows and pressing keys in them use the
answer the user already gave in freemac's question "Allow “App” to control
other windows?" (freemac 1.215): `AXIsProcessTrusted` reads
`~/.config/freemac/window-control.json` on every call, so turning an app off
in Dials takes effect at once. Without that answer:

- `CGWindowListCopyWindowInfo` lists only the app's own windows (an app
  may always list its own, as on a Mac);
- `CGEventPost` drops the keys with a warning naming Dials > Privacy &
  Security > Control Other Windows;
- `CGEventPostToPid` to the app's own process still works (it goes
  straight into the app's event queue, never to the compositor);
- `CGPreflightPostEventAccess` answers NO and `CGRequestPostEventAccess`
  asks freemac's same question.

`CGPreflightListenEventAccess`, `CGRequestListenEventAccess` and
`CGPreflightScreenCaptureAccess` always answer NO: Ferry has no way to
watch other apps' input or their pixels, so it doesn't pretend to.

**Windows.** Other apps' windows are Wayfire's toplevel views (from
`window-rules/list-views`, the same IPC socket `AWayfire.m` uses for
Accessibility), newest-focused first, with Strata's `view-pids` for the
owner's process, the app id's last part for its name, and frames in the
Mac's top-left screen space. Window numbers for them are
`0x40000000 | view id`, so they never collide with the app's own.
`kCGWindowListOptionOnScreenOnly`, `…OnScreenAboveWindow`,
`…OnScreenBelowWindow` and `…IncludingWindow` are honoured.
`CGWindowListCreateImage` makes a picture only of one of the app's own
windows (from its views' drawing) and gives NULL for anything else.

**Keys.** Strata's `press-key` presses and releases keys
through the compositor's own seat, as if typed, into whichever window has
the focus. `CGEventPost` turns a Mac virtual key code into a Linux key code,
presses the flags' modifiers (Command as the Super key, Control, Option as
Alt, Shift), taps the key and lets the modifiers go, always, even when a
press fails. A key-down posts the key; the key-up that follows it is
already done. `CGEventKeyboardSetUnicodeString` text is typed key by key
only while the keyboard layout is US English (`strata/input-source`), since
with another layout the same keys type other characters; otherwise it is
dropped with a warning. `CGEventPostToPid` for another app's process posts
only when that process owns the focused view. Mouse and scroll events have
no safe route (Strata's pointer IPC only reads), so they are dropped with a
warning, and `CGEventTapCreate` gives NULL with a warning: nothing on
freemac lets an app watch other apps' input.

**Drag and drop.** A drag within the app is a session of Ferry's own: the
dragging source's operation mask (Option for Copy, Control for Link,
Command for Generic, unless the source ignores the modifiers), the
destination under the pointer in any of the app's windows told
`draggingEntered:`, `draggingUpdated:`, `draggingExited:`,
`prepareForDragOperation:`, `performDragOperation:` and
`concludeDragOperation:`, and the source `draggingSession:endedAtPoint:operation:`.
Tables start one when a selected row is dragged 4 points (vertically, by
default) and the data source writes it (`tableView:pasteboardWriterForRow:`
or `tableView:writeRowsWithIndexes:toPasteboard:`); a click on one of
several selected rows waits for the mouse to come up, so the selection can
be dragged. A drop is proposed above a row from its top quarter, below it
from its bottom quarter and on it from the middle (past the last row, at
the end), and the data source may change it with `setDropRow:dropOperation:`
in `tableView:validateDrop:proposedRow:proposedDropOperation:`. Outlines
propose an item and child index the same way and
`setDropItem:dropChildIndex:` retargets them; a drop between the children of
a closed item shows on the item. The drop is drawn as a ring around the row
or a line between rows, in the accent colour, indented to the level in an
outline.

**Sets and bags.** `CFSet` with `kCFTypeSetCallBacks` is an `NSSet`; with
other callbacks, or none, it is a hash table of Ferry's own that calls them
to keep, compare, hash, describe and free values, and still answers
Foundation's set methods. `CFBag` counts its values.

**Documents.** A document the document controller holds is a file
presenter: a coordinated write to its file reads the file again when the
document has no unsaved changes and its modification date moved, and a
move it is told of sets its `fileURL`. Changes made by other programs
aren't seen, since Ferry's `NSFileCoordinator` works within one program.

Left out: dragging between apps (Wayland's drag and drop would need the
pasteboard's types offered across), drag images (rows aren't drawn under
the pointer), promised files, posting mouse events, event taps, pictures
of other apps' windows, and typing with a layout other than US English.

### Building the nine apps again (freemac 1.221, Ferry 0.45.0)

Every `.m` file in the nine apps' own targets, compiled with `ferry-cc
-fsyntax-only` against Ferry's SDK (the apps' prefix headers and include
paths as their projects set them):

| App | Source files | Compiled before | Compile now |
| --- | --- | --- | --- |
| Flycut | 24 | 11 | 19 |
| ShiftIt | 23 | 4 | 14 |
| Spectacle | 31 | 18 | 23 |
| Gas Mask | 43 | 23 | 36 |
| MacPass | 156 | 53 | 63 |
| MacDown | 35 | 12 | 23 |
| Sequel Pro | 204 | 0 | 142 |
| KeyCastr | 17 | 7 | 12 |
| Hex Fiend | 104 | 11 | 86 |
| All nine | 637 | 139 | 418 |

What was missing, by how many apps needed it:

| Calls | Apps | Now |
| --- | --- | --- |
| `TargetConditionals.h`, `Availability.h`, `AvailabilityMacros.h`, `sys/cdefs.h`, `PATH_MAX`, `MAXPATHLEN`, `u_int32_t` and the other BSD types | all nine | done |
| `NSUnarchiver`, `NSArchiver`, `encodeValueOfObjCType:at:`, `decodeObject` | Hex Fiend, KeyCastr, Sequel Pro | done; a Mac's typedstream archives give nil with a note |
| `Quartz/Quartz.h` (`QLPreviewPanel`, `PDFView`) | MacPass, KeyCastr, Sequel Pro | not done |
| `NSEventTrackingRunLoopMode`, `NSModalPanelRunLoopMode` | Flycut, Hex Fiend, Sequel Pro | done; Ferry's run loop runs every source in every mode |
| `NSKeyValueChangeKey`, `NSMappedRead`, `NSAtomicWrite`, `NSRegistrationDomain` and other older or newer names | Hex Fiend, KeyCastr, Sequel Pro, MacDown | done |
| `initWithArray:copyItems:`, `NSSwapBigIntToHost`, `JSONObjectWithStream:options:error:` | Hex Fiend, Sequel Pro, MacDown | done |
| `NSTextStorageDelegate`, `editedMask`, `editedRange` | Gas Mask, Sequel Pro | done |
| `boundingRectForGlyphRange:inTextContainer:` | MacDown, Sequel Pro | done, one glyph for each character |
| `NSScriptCommand` (in a header 19 of Sequel Pro's files include) | Sequel Pro | done; Ferry receives no Apple events, so it never makes one |
| `CGFunctionCallbacks`, `CGShadingCreateAxial`, `CGContextDrawShading` (its tab bar) | Sequel Pro | done |
| `TRUE`, `FALSE`, `boolean_t`, `NSSortStable`, `userCanceledErr`, `NSMenuDidEndTrackingNotification`, `NSImageNameComputer` | Flycut, Spectacle, Hex Fiend, MacPass, Sequel Pro | done |
| `+windowFrameColor`, `NSSetFocusRingStyle`, `NSFocusRingOnly`, `cancelTracking`, `setHighlightsBy:` | Flycut, Spectacle, Hex Fiend, MacPass, Sequel Pro | done |
| `NSLeftMouseDraggedMask`, `NSSmallControlSize` and the other older names | Flycut, Sequel Pro | done |
| `JavaScriptCore/JavaScriptCore.h` | MacDown, Spectacle | not done |
| `NSLayoutConstraint` | Flycut, MacPass | not done |
| `Sparkle/SPUUpdater.h` | MacPass, Spectacle | the apps' own updater framework, not Ferry's to provide |
| `TISCopyCurrentKeyboardInputSource`, `UCKeyTranslate`, `kVK_ANSI_A` and the other key codes | Flycut, Spectacle, KeyCastr, MacPass | done, English (US) |
| `NSMapTable`, `NSHashTable`, `NSPointerArray` | Hex Fiend, Sequel Pro | done |
| `FSRef`, `FSPathMakeRef`, `FSMoveObjectToTrashSync` | Hex Fiend, Gas Mask | done |
| `endEditingFor:`, `currentEditor`, `beginModalSessionForWindow:` | Sequel Pro | done; a text field is its own field editor |
| `NSAppearance`, `NSAppearanceNameDarkAqua` | Hex Fiend, Sequel Pro | done; Ferry draws in the light appearance only |
| `+colorNamed:` | Gas Mask | answers nil: an app's colours are in its compiled asset catalogue, which Ferry doesn't read |
| The accessibility constants (`NSAccessibilityRoleAttribute`, `NSAccessibilityButtonRole` and the rest), `NSRuleEditor`, `NSMatrix`, `NSColorList`, `NSURLComponents`, `NSTitlebarAccessoryViewController`, `FSEventStream…`, `CFNotificationCenter`, `NSConnection`, `NSPICTImageRep` | one app each | not done |

### Building the nine apps, 1.222 (freemac 1.222, Ferry 0.46.0)

Every `.m` file in the nine apps' own targets was compiled with `ferry-cc
-fsyntax-only` against Ferry's SDK. Each target's prefix header was used, and
KeyCastr's ARC targets were built with `-fobjc-arc`. This survey script
finds 608 files, not the 637 that 1.221 counted, so both columns below come
from the same script, before and after this work.

| App | Source files | Compiled before | Compile now |
| --- | --- | --- | --- |
| Flycut | 23 | 18 | 20 |
| ShiftIt | 23 | 17 | 18 |
| Spectacle | 31 | 23 | 26 |
| Gas Mask | 43 | 35 | 36 |
| MacPass | 159 | 55 | 58 |
| MacDown | 35 | 12 | 13 |
| Sequel Pro | 172 | 128 | 131 |
| KeyCastr | 17 | 11 | 11 |
| Hex Fiend | 105 | 70 | 70 |
| All nine | 608 | 369 | 383 |

What was added:

| Calls | Apps | Now |
| --- | --- | --- |
| `@import Foundation;`, `@import AppKit;` and the other modules | KeyCastr, Flycut | done |
| `NSLayoutConstraint`, anchors, `NSDictionaryOfVariableBindings`, the visual format language | Flycut, MacPass | done, with a solver |
| `NSAccessibility` names and protocol methods, `kAX` names | Spectacle, MacPass, Sequel Pro | done; values are kept, since there's no screen reader |
| `NSFontDescriptor`, `NSFontSymbolicTraits` | MacPass, MacDown, Sequel Pro | done |
| `FSEventStreamCreate` and the rest of FSEvents | Hex Fiend, Gas Mask | done, on inotify; no history from before a stream starts |
| `Quartz/Quartz.h`, `QLPreviewPanel`, `QLPreviewView` | MacPass, KeyCastr, Sequel Pro | done; `QCView` loads nothing |
| `NSRuleEditor` | Gas Mask, Sequel Pro | done |
| `JavaScriptCore/JavaScriptCore.h` (the C API, `JSContext`, `JSValue`, `JSExport`) | MacDown, Spectacle | done, on this system's JavaScriptCore |

What still stops each app's files (the first error in each file):

- **Flycut (3)**: the app's own `MJCloudKitUserDefaultsSync`; `IOKit/hidsystem/IOLLEvent.h`; a dictionary read into an `NSUInteger` (an error under the newer compiler).
- **ShiftIt (5)**: `X11/Xlib.h` (its X11 driver); `ScriptingBridge/ScriptingBridge.h`; `GetIconRefFromFileInfo`; `ProcessSerialNumber`; a hotkey macro.
- **Spectacle (5)**: the app's own Sparkle; `LSSharedFileListRef` named as an identifier; `NSPreferencePanesDirectory`; two files that subclass `NSObject` with only `Carbon/Carbon.h` imported.
- **Gas Mask (7)**: its Swift bridging header; kqueue's `NOTE_WRITE` and `O_EVTONLY`; `AuthorizationRef`; `SMAppService`; `kSCNetworkFlagsReachable`; `alloca` without `alloca.h`.
- **MacPass (101)**: KeePassKit (60 files) and HNHUi (16), the app's own frameworks; TransformerKit and Sparkle; `kSecClass`; `windowNumbersWithOptions:`; `NSTitlebarAccessoryViewController`; `LSCopyAllHandlersForURLScheme`; `kUTTypeFileURL`; and a dozen single calls (`getValue:size:`, `popUpMenuPositioningItem:atLocation:inView:`, `openURLs:withApplicationAtURL:options:configuration:error:`, `eventWithEventRef:` and others).
- **MacDown (22)**: the app's own frameworks and libraries (MASPreferences, PAPreferences, HBHandlebars, GBCli, JJPluralForm, hoedown, libyaml); a header named in the wrong case (`MPDOcument.h`); `version.h`, made by its build; `base64Encoding`; `hasMarkedText`; `NSCursorAttributeName`; `addSuiteNamed:`.
- **Sequel Pro (41)**: `NSConnection` (3); `NSTokenFieldCellDelegate` (3); `complex.h` (3); `NSCalendarDate`; `NSPersistentStoreCoordinator` in its own headers; `NSPrintPanelAccessorizing`; `NSTextTab`; `NSAppleEventManager`; `SecTrustedApplicationRef`; `NSPICTImageRep`; `NSColorSpace` and `NSColorList`; `WebHistoryItem`; `bzlib.h`; `CFXMLCreateStringByEscapingEntities`; `getlogin`; `object_getInstanceVariable`; `NSFileTypeForHFSTypeCode`; and a few older names (`unimpErr`, `Nanoseconds`, `NSThickSquareBezelStyle`).
- **KeyCastr (6)**: `CFNotificationCenterRef`; `CFMachPortCreateRunLoopSource`; `setFrameUsingName:force:`; `relativeCurveToPoint:controlPoint1:controlPoint2:`; a `__weak` in a file built without ARC; the app's own ShortcutRecorder.
- **Hex Fiend (35)**: its Swift bridging header and generated `version.h`; headers named in the wrong case or missing from the checkout (`HFFUnctions.h`, `HFTest.h`, `HFBTree.h`, `FortunateSonIPCTypes.h`); `OSMemoryBarrier` and `OSQueueHead`; `DiskArbitration` and `sys/disk.h`; `PAGE_SIZE`; the remaining Mac text encodings (`kCFStringEncodingMacDevanagari`); `initWithUnsignedInteger:`; `UTTypeEqual`; `NSClickGestureRecognizer`; `CGContextShowGlyphsAtPositions`; `NSFrameRectWithWidthUsingOperation`; bridged casts the newer compiler requires; and a file that uses FSEvents having imported only Foundation (on a Mac, Foundation brings in CoreServices).

### Linking and running the apps (freemac 1.223, Ferry 0.47.0)

The nine apps were cloned again from their public repositories, and every
`.m` file in their own targets was compiled with `ferry-cc -fsyntax-only`
against Ferry's SDK. Each target's prefix header was used, with
`-fobjc-arc` where the target uses ARC and the strict `objc_msgSend`
prototypes where it asks for them. The newer clones have 627 files, so both
columns come from the same script, before and after this work.

| App | Source files | Compiled before | Compile now |
| --- | --- | --- | --- |
| Flycut | 23 | 20 | 23 |
| ShiftIt | 23 | 18 | 21 |
| Spectacle | 31 | 26 | 31 |
| Gas Mask | 43 | 35 | 38 |
| MacPass | 159 | 58 | 64 |
| MacDown | 36 | 13 | 14 |
| Sequel Pro | 190 | 145 | 148 |
| KeyCastr | 17 | 8 | 8 |
| Hex Fiend | 105 | 72 | 81 |
| All nine | 627 | 395 | 428 |

ShiftIt's two left are its X11 driver, which its NoX11 target leaves out.

Three apps were linked into bundles with their own Info.plist, resources
and frameworks (Sparkle built from its source, ShiftIt's ShortcutRecorder),
and their xibs compiled with `ferry-ibtool`. Started with no display but
the session bus, each is still running ten seconds later. What each does:

| App | When started |
| --- | --- |
| Flycut | Shows its first-launch alert, then its status item, with its icon, and its menu: Search…, the Edit submenu, Clear All, Merge All, Preferences…, About Flycut and Quit, with the clippings above them once there are some. Its shortcut is kept but never pressed |
| Spectacle | Without the accessibility say, opens its own window asking for it, from its nib. With it, shows its status item and menu (About, Check for Updates…, Disable for an hour or for the frontmost app, Preferences…, the window positions and sizes, Undo, Redo and Quit) and opens its preferences window with its shortcut recorders. The status item has no picture, since the asset catalogue isn't compiled. Its shortcuts are kept but never pressed |
| ShiftIt | Without the accessibility say, asks for it in an alert and asks again with each Recheck, as on a Mac. With it, shows its status item with its icon, its menu of window positions and sizes, and a preferences window with its five tabs. Its `NSMatrix` is made as a plain view, and its shortcuts are kept but never pressed |

What was added:

| Calls | Apps | Now |
| --- | --- | --- |
| Apple events, Launch Services, the Process Manager, `FSGetCatalogInfo` | Flycut | done; events reach the app's own handlers, and no other app's |
| CloudKit, `SecTask` | Flycut | done, with no iCloud account |
| `CFLocale`, `CFDate`, `CFDateFormatter`, `CFError` | Flycut, Sparkle | done |
| `ScriptingBridge/ScriptingBridge.h` | ShiftIt | done; finds no scriptable app, and each event fails with `errAEEventNotHandled` |
| `GetIconRefFromFileInfo`, `AcquireIconRef`, `ReleaseIconRef` | ShiftIt | done |
| `objc_msgSend` with its arguments (the old dispatch prototypes) | ShiftIt | done, as on a Mac unless the target asks for the strict ones |
| `NSTouchBar` and its items | Sparkle | done; never shown |
| `fts`, `statfs`, `asl`, `os_log`, `O_SYMLINK`, `fchown` | Sparkle | done |
| `UTType...` and `kUTType...` | Sparkle, Hex Fiend, MacPass | done, from Apple's published list of types and the app's own declarations |
| `NSURLDownload` | Sparkle | done; downloads can't be resumed |
| `SecItemImport`, `SecVerifyTransformCreate`, the digest and read transforms | Sparkle | done; signing isn't |
| `AuthorizationCreate` and the rest | Sparkle, Gas Mask | done; never grants a right |
| `IOPMAssertionCreateWithName`, `IOServiceGetMatchingService` | Sparkle | done; assertions are kept but not passed on, and the registry is empty |
| `performFileOperation:source:destination:files:tag:`, `recycleURLs:`, `duplicateURLs:` | Sparkle | done |
| kqueue's `EVFILT_VNODE`, `O_EVTONLY` | Gas Mask | done, on inotify |
| `NSCountedSet`, `uuid_t`, `increaseLengthBy:`, `initWithLong:` and the others | KeePassKit | done |
| `strings.h` | hoedown | done |

What still stops each app's files (the first error in each file):

- **Flycut (0)**: all compile, and it links and runs.
- **ShiftIt (2)**: `X11/Xlib.h`, its X11 driver, left out of the NoX11 target that was linked.
- **Spectacle (0)**: all compile, and it links and runs.
- **Gas Mask (5)**: its Swift bridging header; `SMAppService`; `kSCNetworkFlagsReachable`; `alloca` without `alloca.h`; its launcher, which uses `NSString` having imported nothing. Its MainMenu.xib is in the older archive format, which `ferry-ibtool` doesn't read.
- **MacPass (95)**: KeePassKit (60 files) and HNHUi (16); TransformerKit and Sparkle; `CIImage`; `windowNumbersWithOptions:`; `kSecAttrApplicationTag`; `NSTitlebarAccessoryViewController`; and single calls (`getValue:size:`, `popUpMenuPositioningItem:atLocation:inView:`, `openURLs:withApplicationAtURL:options:configuration:error:`, `eventWithEventRef:`, `mutableString`, a `CGSize` in a boxed expression).
- **MacDown (22)**: its libraries (MASPreferences, PAPreferences, HBHandlebars, GBCli, JJPluralForm, hoedown, libyaml), whose headers come from its Pods; a header named in the wrong case (`MPDOcument.h`); `version.h`, made by its build; `addSuiteNamed:`; `hasMarkedText`; `NSCursorAttributeName`.
- **Sequel Pro (42)**: `NSConnection` (3); `NSTokenFieldCellDelegate` (3); `complex.h` (3); `alloca` without `alloca.h` (3); `NSCalendarDate`; `NSPersistentStoreCoordinator` in its own headers; `SecTrustedApplicationRef`; `NSPrintPanelAccessorizing`; `NSTextTab`; `NSAppleEventManager`; `NSPICTImageRep`; `NSColorSpace` and `NSColorList`; `WebHistoryItem`; `NSToolTipTag`; `bzlib.h`; `CFXMLCreateStringByEscapingEntities`; `getlogin`; `object_getInstanceVariable`; `NSFileTypeForHFSTypeCode`; and older names (`unimpErr`, `Nanoseconds`, `NSThickSquareBezelStyle`, `NSExcludedElementsDocumentAttribute`).
- **KeyCastr (9)**: `CFNotificationCenterRef`; `CFMachPortCreateRunLoopSource`; `setFrameUsingName:force:`; `relativeCurveToPoint:controlPoint1:controlPoint2:`; a `__weak` in a file built without ARC; files that use `NSColor` and `NSEventType` having imported only Foundation; its ShortcutRecorder's headers.
- **Hex Fiend (24)**: its Swift bridging header (2); `OSMemoryBarrier` and `OSQueueHead`; `DiskArbitration` and `sys/disk.h`; `mach/message.h`; `PAGE_SIZE`; the remaining Mac text encodings (`kCFStringEncodingMacDevanagari`); `NSClickGestureRecognizer`; `CGContextShowGlyphsAtPositions`; `NSFrameRectWithWidthUsingOperation`; `setRefusesFirstResponder:`, `orderedDocuments`, `ancestorSharedWithView:`, `enclosingMenuItem`, `makeObjectsPerformSelector:` on a set; `uint64` in its templates; a header named in the wrong case (`HFFUnctions.h`).

The apps' own frameworks, compiled the same way from their public source:

| Framework | App | Files | Compile now | What stops the rest |
| --- | --- | --- | --- | --- |
| KeePassKit | MacPass | 96 | 68 | its own headers as its build lays them out (15); KissXML (6); Argon2's header (3); `NSColorSpace`; `NSURLComponents`; `CC_MD2_DIGEST_LENGTH`; `CGImageDestinationRef` |
| KissXML | MacPass | 5 | 2 | `libxml/tree.h`: libxml2, which Ferry's SDK doesn't have |
| TransformerKit | MacPass | 7 | 0 | `@import Darwin;` |
| HNHUi | MacPass | 19 | 14 | `NSColorSpace`; `fontAttributesInRange:`; a window's `animations`; `truncatesLastVisibleLine`; `validateMenuItem:` on `NSSecureTextView` |
| handlebars-objc | MacDown | 38 | 37 | subscripting an `id<NSFastEnumeration>` |
| hoedown, libyaml, GBCli | MacDown | 9, 8, 6 | all | nothing |
| MASPreferences | MacDown | 1 | 0 | `commitEditing` on a view controller |
| M13OrderedDictionary | MacDown | 1 | 0 | a generic type it declares |

None of them was linked yet, and Sequel Pro's MySQL framework wasn't
reached: it needs the MySQL client library built for Ferry.

### Shortcuts, asset catalogues and KeyCastr (freemac 1.224, Ferry 0.48.0)

The same 627 files as in 1.223 were compiled again with `ferry-cc
-fsyntax-only`, before and after this work, by one survey script. The
script now finds a header that a source names in another case
(`SUlog.h`, `MPDOcument.h`, `<HexFiend/HFFUnctions.h>`), as a Mac's disk
does. That is why the "before" column is a little higher than 1.223's
"now".

| App | Source files | Compiled before | Compile now |
| --- | --- | --- | --- |
| Flycut | 23 | 23 | 23 |
| ShiftIt | 23 | 21 | 21 |
| Spectacle | 31 | 31 | 31 |
| Gas Mask | 43 | 39 | 39 |
| MacPass | 159 | 64 | 64 |
| MacDown | 36 | 16 | 20 |
| Sequel Pro | 190 | 148 | 149 |
| KeyCastr | 17 | 12 | 17 |
| Hex Fiend | 105 | 81 | 81 |
| All nine | 627 | 435 | 445 |

With hoedown, LibYAML and GBCli built as frameworks, 21 of MacDown's files
compile.

Global shortcuts were pressed through the stand-in for Wayfire's IPC
that the tests use, with the app started with no display. Every
combination an app registered with Strata was pressed once:

| App | When its shortcuts are pressed |
| --- | --- |
| Spectacle | Registers its 18 shortcuts. Each press resizes or moves the focused window: centre, full screen, the halves, the corners, the next and previous thirds, larger and smaller. Its status item shows its picture from the asset catalogue |
| Flycut | Registers its shortcut. A press runs its handler, which opens the bezel on the main screen (not drawn with no display) |
| KeyCastr | Registers none until the user records one; shows its status item with its icon |

KeyCastr was linked into a bundle as the other three were:

- ShortcutRecorder and Sparkle 2 (with its ed25519 code) were built from
  their source as frameworks.
- KCVisualizer was built as a framework, and the Default, Minimal and
  Svelte visualizers as plug-ins.
- Its xibs were compiled with `ferry-ibtool`.

Under X it shows Sparkle's "Check for updates automatically?" window and
its status item. Its About window's Quartz Composer animation doesn't
run, and it shows no keystrokes. Its event tap is `NULL`, since Wayland
lets no app read another app's keys, and KeyCastr says nothing about
that. On freemac's desktop it puts its status item in the menu bar.
Sparkle 2's XPC services never connect: every call to them fails, as on
a Mac without the services.

What was added:

| Calls | Apps | Now |
| --- | --- | --- |
| `RegisterEventHotKey` presses on the dispatcher target, `LSUIElement` and `LSBackgroundOnly`, `frontmostApplication` from Wayfire's focused window, `TransformProcessType`, a control class's own cell | Spectacle, Flycut, KeyCastr | done |
| `ferry-actool`; `imageNamed:`, `colorNamed:`, `NSDataAsset`, the app icon from an `.icns` file's largest PNG | Spectacle, KeyCastr's ShortcutRecorder | done; `Assets.car` isn't read, image stacks and symbol sets aren't compiled |
| `CFNotificationCenter` (local, distributed, Darwin), `CFMachPort` | KeyCastr | done; there are no Mach ports, so `CFMachPortCreate` gives `NULL` |
| `os_trace`, `os_activity`, `audit_token_t`, the PowerPC CPU subtypes | Sparkle 2, ShortcutRecorder | done |
| `NSXPCConnection`, `NSXPCInterface`, `NSXPCListener` | Sparkle 2 | done; a connection never connects, and its proxies fail with `NSXPCConnectionInvalid` |
| `SMJobBless`, `SMJobSubmit`, `SMJobRemove`, `SMJobCopyDictionary`, `AuthorizationRightGet` and `Set` | Sparkle 2 | done; there's no launchd, so each is refused |
| bookmarks and security scopes, `NSURLVolumeIdentifierKey`, a bundle's other folders, auxiliary executables, `bundleWithIdentifier:` for loaded frameworks, `allFrameworks`, `allBundles` | Sparkle 2, ShortcutRecorder | done; a bookmark holds the path only |
| `renamex_np`, `renameatx_np`, `renameat`, `O_NOFOLLOW_ANY`, `utimes`, `futimes`, `lutimes` | Sparkle 2 | done, on `renameat2`, `openat2` and the Mac's `struct timeval` |
| `rangeOfData:` backwards and anchored, plists from URLs, `writeToURL:atomically:`, localized case changes, `NSHomeDirectoryForUser`, `addSuiteNamed:` | Sparkle 2, MacDown | done |
| JSON with a comma before `]` or `}` | ShortcutRecorder | done |
| Markdown in attributed strings, `NSPresentationIntent` | Sparkle 2 | the intents are there; Markdown isn't read and the initializers fail |
| `WKContentRuleListStore` | Sparkle 2 | done; nothing is compiled, so nothing is blocked |
| window frames by name, tool-tip rects, `relativeCurveToPoint:`, layout direction, control tint, `NSTextTab` and tab stops, `colorWithCatalogName:colorName:`, `parentItem`, `NSStringDrawingContext`, `NSDrawThreePartImage`, `NSDrawNinePartImage`, the function keys up to F35 | KeyCastr, ShortcutRecorder, Sequel Pro | done; nine-part middles are stretched, not tiled |
| `hasMarkedText`, `NSCursorAttributeName`, the text view's `is...Enabled` names | MacDown | done; there's no input method, so there's never marked text |
| the current input source as one object | ShortcutRecorder | done |
| `<qcView>` in `ferry-ibtool` | KeyCastr | done; made as a `QCView`, which can't run a composition |

What still stops each app's files (the first error in each file):

- **Flycut (0)**, **Spectacle (0)**, **KeyCastr (0)**: all compile, and
  they link and run.
- **ShiftIt (2)**: `X11/Xlib.h`, its X11 driver, left out of the NoX11
  target that was linked.
- **Gas Mask (4)**: its Swift bridging header; `SMAppService`;
  `kSCNetworkFlagsReachable`; `alloca` without `alloca.h`.
- **MacPass (95)**: KeePassKit (60 files) and HNHUi (16), plus
  TransformerKit and Sparkle. Then:
  - `windowNumbersWithOptions:` and `kSecAttrApplicationTag`;
  - `NSTitlebarAccessoryViewController`;
  - single calls: `getValue:size:`,
    `popUpMenuPositioningItem:atLocation:inView:`,
    `openURLs:withApplicationAtURL:options:configuration:error:`,
    `eventWithEventRef:`, `mutableString`, `menuForEvent:`;
  - a `CGSize` in a boxed expression, and Core Image's `CIImage` (2).
- **MacDown (16)**: its libraries' headers, from its Pods:
  MASPreferences, PAPreferences, JJPluralForm, M13OrderedDictionary,
  handlebars-objc, and `yaml.h` named bare. Then `version.h`, made by its
  build.
- **Sequel Pro (41)**:
  - `NSConnection`, `NSTokenFieldCellDelegate`,
    `NSPrintPanelAccessorizing`, `complex.h` and `alloca` without
    `alloca.h` (3 each);
  - `NSCalendarDate`, `SecTrustedApplicationRef`, and
    `NSAppleEventManager`;
  - `NSPICTImageRep`, `NSColorSpace`, `NSColorList` and `WebHistoryItem`;
  - `bzlib.h`, `CFXMLCreateStringByEscapingEntities`, `getlogin`,
    `Block_copy`, `object_getInstanceVariable` and
    `NSFileTypeForHFSTypeCode`;
  - older names (`unimpErr`, `Nanoseconds`, `NSThickSquareBezelStyle`,
    `NSTexturedBackgroundWindowMask`,
    `NSExcludedElementsDocumentAttribute`);
  - a few calls that return `id` where a value is wanted.
- **Hex Fiend (24)**:
  - its Swift bridging header (2);
  - `OSMemoryBarrier` and `OSQueueHead`;
  - `DiskArbitration`, `sys/disk.h` and `servers/bootstrap.h`;
  - `PAGE_SIZE`;
  - the remaining Mac text encodings;
  - `NSClickGestureRecognizer`, `CTFontCopyCharacterSet`,
    `CGContextShowGlyphsAtPositions` and
    `NSFrameRectWithWidthUsingOperation`;
  - `setRefusesFirstResponder:`, `orderedDocuments`,
    `ancestorSharedWithView:`, `enclosingMenuItem`, and
    `makeObjectsPerformSelector:` on a set;
  - `uint64` in its templates (3), and a parse error inside its data
    inspector's fetch macros.

MacDown's libraries, built from their public source into frameworks:

| Library | Files | Built | What it does under Ferry |
| --- | --- | --- | --- |
| hoedown | 9 | all | turns Markdown into HTML |
| LibYAML | 8 | all | parses YAML |
| GBCli | 4 | all | reads command-line options into settings |
| handlebars-objc | 38 | 35 | not usable: its lexer is a flex file, and flex wasn't available to build it. One file subscripts an `id<NSFastEnumeration>`, and two need the framework's headers laid out as its build lays them |

### MacPass and MacDown (freemac 1.225, Ferry 0.49.0)

The same 627 files as in 1.224 were compiled again with `ferry-cc
-fsyntax-only`, before and after this work, by the same survey script.
MacPass's dependencies (KeePassKit, KissXML, HNHUi, TransformerKit and
Sparkle) are now checked out in its clone under `Carthage/Checkouts`,
where its build looks for them, and MacDown has the pod headers that
are plain copies (`Pods/Headers`).
Both columns were counted that way, the "before" one with Ferry 0.48.0's
SDK. That is why it is higher than 1.224's "now" (445): MacPass's own
count went from 64 to 114 with its dependencies' headers alone.

| App | Source files | Compiled before | Compile now |
| --- | --- | --- | --- |
| Flycut | 23 | 23 | 23 |
| ShiftIt | 23 | 21 | 21 |
| Spectacle | 31 | 31 | 31 |
| Gas Mask | 43 | 39 | 39 |
| MacPass | 159 | 114 | 159 |
| MacDown | 36 | 21 | 21 |
| Sequel Pro | 190 | 149 | 150 |
| KeyCastr | 17 | 17 | 17 |
| Hex Fiend | 105 | 81 | 82 |
| All nine | 627 | 496 | 543 |

The survey doesn't build MacDown's libraries. With them built as
frameworks, all 36 of MacDown's files compile and it links, as MacPass
does.

The frameworks, built from their public source:

| App | Framework | Files | What it does under Ferry |
| --- | --- | --- | --- |
| MacPass | KissXML | 5 | reads and writes XML through this system's libxml2 |
| MacPass | TransformerKit | 7 | its value transformers, the cryptographic ones included |
| MacPass | KeePassKit | 96 (8 of them Argon2) | reads KeePass 1 and 2 databases and unlocks them with a password, AES and Argon2 included |
| MacPass | HNHUi | 19 | MacPass's own views and cells |
| MacPass | Sparkle (1.x) | 65 | its updater, as in Flycut |
| MacDown | hoedown, LibYAML, GBCli | 21 | as in 1.224 |
| MacDown | handlebars-objc | 38, its parser and a lexer | renders MacDown's preview templates. Its parser is made with this system's bison; flex isn't on the build machine, so its lexer is a hand-written one in the build script that follows the flex file's rules |
| MacDown | MASPreferences, PAPreferences, JJPluralForm, M13OrderedDictionary | 5 | its preferences window and settings, plural forms and an ordered dictionary |
| MacDown | Sparkle (1.x) | 38 | its updater |

Both apps were run under X with no desktop, given input with XTest:

| App | When run |
| --- | --- |
| MacPass | Opens a KeePass 2 database made for the test with KeePassKit's own writer. Typing the password and pressing Unlock unlocks it. The outline shows the "General" group, selecting it lists "Example login" with its user name, and selecting that fills the inspector with the user name, the password (hidden) and the URL. Its window opens at 700 by 538 points, so the inspector is cut off at the right. It logs that Touch ID can't be used, since `SecKeyCreateRandomKey` fails |
| MacDown | Opens a Markdown file. The editor highlights its syntax, and the preview shows the heading, emphasis, the list, the quote, the code block and the table as HTML. Sparkle asks whether to check for updates. Command-comma opens the preferences window, compiled from MASPreferences's older-format xib, with its toolbar (General, Markdown, Editor, Rendering, Terminal) and the General pane's checkboxes |

What was added:

| Calls | Apps | Now |
| --- | --- | --- |
| the older xib format in `ferry-ibtool`: objects carried over with their keys, outlets, actions and bindings connected, a window shown unless it isn't visible at launch | MacDown (MASPreferences) | done; Interface Builder's own records (plug-in versions, class descriptions) are left out |
| a class swapper's or custom view's place handed to the object it makes, so references back to it find that object; `windowNibName` overridden by a window controller | MacPass (HNHUi's table, its window controllers) | done |
| `NSGridView`, `NSGridRow`, `NSGridColumn` and `NSGridCell`, from nibs and in code, merged cells included; `<gridView>` in `ferry-ibtool` | MacPass | done |
| an editable text field's intrinsic width (none, as on a Mac) | MacPass's inspector | done |
| Core Image: `CIImage`, `CIFilter` (the affine transform and the QR code generator), `CIContext`, `CIDetector`, `NSCIImageRep` | MacPass (TOTP setup) | done; a QR code comes out empty and detectors find nothing |
| key-value coding through `countOf<Key>` with `objectIn<Key>AtIndex:` or `<key>AtIndexes:`, and through `countOf<Key>`, `enumeratorOf<Key>` and `memberOf<Key>:` | MacPass (KeePassKit's groups and entries) | done |
| `NSURLComponents`, `NSURLQueryItem` | KeePassKit | done, by RFC 3986 |
| `getValue:size:`, a boxed `CGSize`, `mutableString` on a subclass, an empty `NSSet` subclass | MacPass, MacDown | done |
| `NSAppleEventDescriptor`, `NSAppleEventManager` | MacDown | done, over Ferry's Apple Event Manager |
| collections searched with options, among indexes and with sort hints; the dictionary's from-arrays calls | MacDown (M13OrderedDictionary) | done; a concurrent search runs in order |
| `CFStringTransform` and `stringByApplyingTransform:reverse:` (XML hex, fullwidth to halfwidth, combining marks and diacritics removed); full case mapping in `uppercaseString`, `lowercaseString`, `capitalizedString` and `CFStringUppercase` | KissXML, MacPass | done; the transforms that change script return nil |
| `UTType` and its tags, `iconForContentType:`, `CGImageDestination` | MacPass, KeePassKit | done |
| Security transforms' Base64, Base32 and Base32hex encoders and decoders, `kSecLineLength64`, `SecAccessControl`, `kSecAttrApplicationTag` | MacPass, TransformerKit | done; `SecKeyCreateRandomKey` fails with `errSecUnimplemented` |
| MD2 and MD4 in CommonCrypto, `strptime_l` | KeePassKit, TransformerKit | done |
| context menus from `menuForEvent:` and `popUpMenuPositioningItem:`, `NSTitlebarAccessoryViewController`, `windowNumbersWithOptions:`, the window's sharing type, file promises, `NSColorSpace`, the lock image names, `initWithFocusedViewRect:` | MacPass, HNHUi | done; a context menu is Ferry's in-window menu |
| the older web view's selection, `DOMRange`, computed style, the CSS properties by name and a frame's `javaScriptContext` | MacDown | done; what a script gives back is copied as JSON carries it, so functions and nodes don't come back |
| `@import Darwin` and `@import ObjectiveC`, libxml2's headers under `usr/include/libxml2` | KissXML, MacPass | done |

What still stops each app's files (the first error in each file), with
no framework of the apps' own built:

- **Flycut (0)**, **Spectacle (0)**, **KeyCastr (0)**: all compile, and
  they link and run.
- **ShiftIt (2)**: `X11/Xlib.h`, its X11 driver, left out of the NoX11
  target that was linked.
- **Gas Mask (4)**: its Swift bridging header; `SMAppService`;
  `kSCNetworkFlagsReachable`; `alloca` without `alloca.h`.
- **MacPass (0)**: all compile, and it links and runs.
- **MacDown (15)**: only its libraries' headers, since the survey doesn't
  build them: MASPreferences (5), PAPreferences (3), handlebars-objc (2),
  GBCli (2), hoedown, JJPluralForm and M13OrderedDictionary. Built as
  frameworks, they let all 36 compile, and it links and runs.
- **Sequel Pro (40)**:
  - `NSConnection`, `NSTokenFieldCellDelegate`,
    `NSPrintPanelAccessorizing`, `complex.h` and `alloca` without
    `alloca.h` (3 each);
  - `NSCalendarDate` and `SecTrustedApplicationRef` (2 each), and
    `NSScriptExecutionContext`;
  - `NSPICTImageRep`, `NSColorList` and `WebHistoryItem`;
  - `bzlib.h`, `CFXMLCreateStringByEscapingEntities`, `getlogin`,
    `Block_copy`, `object_getInstanceVariable` and
    `NSFileTypeForHFSTypeCode`;
  - older names (`unimpErr`, `Nanoseconds`, `NSThickSquareBezelStyle`,
    `NSTexturedBackgroundWindowMask`,
    `NSExcludedElementsDocumentAttribute`);
  - calls that return `id` where a value is wanted (4), and a method
    declared `void` that returns a value (2).
- **Hex Fiend (23)**:
  - its Swift bridging header (2);
  - `OSMemoryBarrier` (2) and `OSQueueHead`;
  - `DiskArbitration`, `sys/disk.h` and `servers/bootstrap.h`;
  - `PAGE_SIZE`;
  - the remaining Mac text encodings (2);
  - `NSClickGestureRecognizer`, `CTFontCopyCharacterSet`,
    `CGContextShowGlyphsAtPositions` and
    `NSFrameRectWithWidthUsingOperation`;
  - `setRefusesFirstResponder:`, `ancestorSharedWithView:`,
    `enclosingMenuItem`, and `makeObjectsPerformSelector:` on a set;
  - `uint64` in its templates (3), and a parse error inside its data
    inspector's fetch macros.

### Sequel Pro (freemac 1.226, Ferry 0.50.0)

The same 627 files as in 1.225 were compiled again with `ferry-cc
-fsyntax-only`, before and after this work, by the same survey script,
with MacPass's dependencies checked out as in 1.225. The "before" column
is 1.225's "now".

| App | Source files | Compiled before | Compile now |
| --- | --- | --- | --- |
| Flycut | 23 | 23 | 23 |
| ShiftIt | 23 | 21 | 21 |
| Spectacle | 31 | 31 | 31 |
| Gas Mask | 43 | 39 | 40 |
| MacPass | 159 | 159 | 159 |
| MacDown | 36 | 21 | 21 |
| Sequel Pro | 190 | 150 | 188 |
| KeyCastr | 17 | 17 | 17 |
| Hex Fiend | 105 | 82 | 82 |
| All nine | 627 | 543 | 582 |

The two Sequel Pro files left are one file counted in two targets,
`SPAlertSheets.m`, whose method declared `void` returns a value. The
clang of its day warned about that; today's stops. The build, which turns
the warnings off as the survey doesn't, compiles it, and all 158 of the
app target's files with it.

The frameworks:

| Framework | Files | From | What it does under Ferry |
| --- | --- | --- | --- |
| MariaDB Connector/C 3.4 | 36 | its public source, built with `ferry-cc` | the MySQL client protocol, linked into SPMySQL in place of the Mac `libmysqlclient.a` Sequel Pro's repository carries. Built without TLS, with its hashes from CommonCrypto. Three names differ from MySQL 5.5's (the transport `vio`, the SSL mode option and `SERVER_MORE_RESULTS_EXISTS`), and the build forces a header into SPMySQL's files that maps them |
| SPMySQL | 23 | Sequel Pro's source | connects, queries and streams results, over Connector/C |
| QueryKit | 9 | Sequel Pro's source | builds queries |
| PSMTabBar | 13 | Sequel Pro's source | the tab bar. It declares two of the window server's private calls itself, to picture a window while a tab is dragged; the build links do-nothing ones, so the tab drags without its picture |
| Growl, FeedbackReporter, ShortcutRecorder, UniversalDetector | | built, in Sequel Pro's repository | used as shipped. FeedbackReporter names `libgcc_s` and UniversalDetector `libstdc++`, which Ferry doesn't provide; both load without them |
| Sparkle (1.x) | | MacDown's 1.225 build | its updater |

Sequel Pro's `PreferenceDefaults.plist` holds its query editor's colours
and font, and the favourite colours, as data a Mac's `NSArchiver` wrote.
That format is undocumented, and Ferry's `NSUnarchiver` gives nil for it,
so Sequel Pro put nil into an array. The build script writes those values
again with Ferry's own `NSArchiver`, in colours chosen for it (black on
white, with the usual syntax colours), not read from the shipped data.
The built Info.plist's empty `CFBundleVersion` is set to 1, which Sparkle
needs.

Sequel Pro was run under X with no desktop, given input with XTest:

| When | What it does |
| --- | --- |
| First launch, fresh home | Opens its window at 948 by 608 points: the toolbar (database menu, Structure, Content, Relations, Triggers, Table Info, Query, Table History, Users, Console), the favourites list with Quick Connect, and the connection form with its TCP/IP, Socket and SSH tabs, the colour choices, the fields with their placeholders and Connect |
| Second launch | Sparkle's sheet asks whether to check for updates automatically |
| Host 127.0.0.1, user root, port 3306, Connect | "Add to Favorites", "Save changes" and "Test connection" appear under the form. SPMySQL connects through Connector/C to a socket nothing listens on, and the sheet says "Connection failed!" with "MySQL said: Can't connect to server on '127.0.0.1' (36)". The 36 is `EINPROGRESS`, the `errno` left by Connector/C's non-blocking connect, which it reports rather than the socket's own error (61, connection refused, which Ferry gives, as a test program shows). No server is installed, so no query was run |

What was added:

| Calls | Apps | Now |
| --- | --- | --- |
| `NSColorList`, the HFS type code calls (`NSFileTypeForHFSTypeCode` and the rest), base coordinates (`convertBaseToScreen:` and the others), the layout manager's glyph queries and `backgroundLayoutEnabled` | Sequel Pro | done; a colour list is read from and written to Ferry's own archives |
| `NSMatrix`, with its modes, cells by row and column, `selectedTag` and rows running down from the top | Sequel Pro | done |
| `NSSpellChecker` | Sequel Pro | done; it knows no words, so it finds nothing to correct |
| `NSPICTImageRep` | Sequel Pro | done; it reads no PICT data |
| `NSTokenFieldCellDelegate`, `NSPrintPanelAccessorizing`, `graphicsPort` (the context's `CGContext`) | Sequel Pro | done |
| the rest of `NSCell`: represented object, numeric values set and taken from another control, type, mixed and next state, `sendActionOn:`, first responder, undo, single line mode, focus ring, writing direction, key equivalent and `compare:` | Sequel Pro | done |
| a window's alpha applied to its window on screen, kept off screen at 0 | Sequel Pro (fades its window in) | done |
| a frame set to the one a view already has posts nothing | Sequel Pro | done |
| `NSCalendarDate`: its formats, fields, time zones, arithmetic and parsing | Sequel Pro | done |
| `NSScriptExecutionContext`; `NSConnection` by registered name between the threads of one program, with its root proxy | Sequel Pro's SSH tunnel | done; another program's connection isn't found |
| `CFXMLCreateStringByEscapingEntities` and its unescaping twin, the DriverServices clock, `unimpErr`, `object_getInstanceVariable`, `Block_copy` from CoreFoundation | Sequel Pro, SPMySQL | done |
| `SecKeychainItemCreateFromContent`, `SecKeychainSearchCreateFromAttributes` and `SecKeychainSearchCopyNext`, `SecAccessCreate`, trusted applications | Sequel Pro (its passwords) | done; an access list is kept with nothing to check, as Ferry's keychain asks no one |
| `WebHistoryItem`, `WebBackForwardList` | Sequel Pro's help viewer | done |
| `NSMutableArray` and `NSMutableDictionary` read from files typed as mutable | Sequel Pro | done |
| `pthread_cancel` and the cleanup handlers, `memset_pattern4`, `8` and `16`, `getlogin`, `ttyname`, `asl_set_query`, `asl_next` | MariaDB Connector/C, Sequel Pro | done; cancellation is acted on only in `pthread_testcancel` |
| libbz2's calls on a Mac `FILE`; `memory.h`, `alloca.h`, `complex.h`, `bzlib.h`, `zconf.h`, `netinet/in_systm.h`, `netinet/ip.h` | Sequel Pro, Connector/C, Gas Mask | done |

What still stops each app's files (the first error in each file), with
no framework of the apps' own built:

- **Flycut (0)**, **Spectacle (0)**, **KeyCastr (0)**, **MacPass (0)**:
  all compile, and they link and run.
- **ShiftIt (2)**: `X11/Xlib.h`, its X11 driver, left out of the NoX11
  target that was linked.
- **Gas Mask (3)**: its Swift bridging header; `SMAppService`;
  `kSCNetworkFlagsReachable`.
- **MacDown (15)**: only its libraries' headers, as in 1.225. Built as
  frameworks, they let all 36 compile, and it links and runs.
- **Sequel Pro (2)**: `SPAlertSheets.m`, in two targets, whose `void`
  method returns a value. The build compiles it, and it links and runs.
- **Hex Fiend (23)**: as in 1.225.

### Swift programs and SwiftUI (freemac 1.227, Ferry 0.51.0)

Gas Mask and Hex Fiend have Swift in them, and many newer Mac apps are
written in Swift with SwiftUI. These are the first steps.

How it fits together:

| Part | Where | What it is |
| --- | --- | --- |
| Swift's runtime and standard library | `swift/build-runtime.sh` into `frameworks/swift` | the open-source Swift project's own, at swift-6.1.3-RELEASE, built unchanged for `x86_64-apple-macosx` with `ferry-cc` and a swift.org toolchain for Linux. It is the same kind of library as a Mac's `/usr/lib/swift/libswiftCore.dylib`, with Objective-C interoperability on |
| Loading it | `src/swiftsupport.c` | `/usr/lib/swift/libswift*.dylib`, or `@rpath/libswift*.dylib` when the app carries no copy, is served from `frameworks/swift` |
| What Swift's runtime asks of Objective-C | `src/objc/swift.c`, `src/objc/runtime.c` | classes made while the program runs are realized; class lookups go to Swift's hook first; generic classes get their names when asked. The older Swift-class bit is moved to the stable one |
| The compiler driver | `sdk/ferry-swiftc` | the toolchain's `swift-frontend`, aimed at a Mac, reading the SDK's module map and API notes; `ferry-cc` links |
| The SDK as Swift reads it | `sdk/include/*.apinotes`, `FERRY_SWIFT_NONNULL` and `FERRY_SWIFT_NULLABLE` | Swift's names for what Swift's own rules name differently, and nullability. Nullability that API notes give a method applies to all its parameters, so a method with a nullable parameter lists them all |
| The overlays | `swift/overlays`, built by `swift/build-modules.sh` | ObjectiveC, CoreGraphics and Foundation. `String`, `Array`, `Dictionary`, `Set` and numbers bridge both ways. `Date`, `URL`, `Data` and the like are, for now, the NS classes under Swift's names. AppKit has no overlay yet |
| SwiftUI | `swift/SwiftUI` | Ferry's own, drawn with Ferry's AppKit |

How Ferry's SwiftUI works: each pass works out the views' bodies again
and turns the result into a tree of plain nodes, each with a path. The
state behind `@State`, `@StateObject` and the like is kept in a slot for
that path, and the AppKit views are matched to the nodes by path, so a
control is kept from one pass to the next and only its title or value
changes. Layout is SwiftUI's: a parent proposes a size and the child
answers. Stacks share what is left among the children that can grow.
Changes are collected and drawn once per pass of the run loop. A window
grows to fit what it holds.

Programs that run (with the Swift toolchain present, in `make check`, and under X):

| Program | When run |
| --- | --- |
| `hello` | the standard library: printing, arrays, sorting, dictionaries |
| `foundation` | strings, arrays, dictionaries and numbers to and from their NS classes, `NSString`'s methods on Swift strings, a Swift `NSObject` subclass, and Swift strings, ASCII or not, as `NSDictionary` keys |
| `appkit_window` | an application delegate written in Swift, a window and a button's target and action |
| `swiftui_counter` | `@State`, `Text`, `Button`, stacks and `Toggle`. Its buttons are pressed in turn and the count changes |
| `swiftui_app` | an `ObservableObject` model, `List`, `ForEach`, `TextField`, `Picker`, `Settings` and a `MenuBarExtra`. Its window and status menu items are pressed |
| `swiftui_hosting` | `NSHostingView` in an AppKit program |
| `swiftui_grid` | `GroupBox`, `LazyVGrid`, a `Stepper` and a `Slider` with label views, a button whose label is several views, `NSLocalizedString`, gestures, `@FocusState`, and an `NSViewRepresentable` whose coordinator counts the passes |
| `mixed` | an Objective-C program using two Swift classes through the header `ferry-swiftc` wrote, the Swift built as a library beside it |

The apps surveyed (cloned from their public source; SwiftUI names
counted by one script, and the code was compiled where it could be):

| App | Swift files | SwiftUI names Ferry has | How far it got |
| --- | --- | --- | --- |
| TomatoBar | 7 | 42 of 42 | links and runs (freemac 1.230), built from its source by `ferry/apps/tomatobar.sh` (freemac 1.231), which fetches it and SwiftState, LaunchAtLogin and KeyboardShortcuts at pinned commits. Its menu bar item shows in Topline with its icon; a click opens its popover under the item (Start, the Intervals, Settings and Sounds tabs, steppers with arrows, switches, sliders, About and Quit with their shortcuts); Start starts the timer, and the time left counts down in the menu bar. About shows the About panel. At the end of an interval it sends its notification with Open and Skip, and its sounds play through `pw-play`, `paplay` or `aplay`. A few labels in Settings are cut short by a few points. Screenshot: `docs/screenshots/ferry-tomatobar.png` |
| Spaceman | 14 | 35 of 39 (no `scaledToFit`, `offset`, `ignoresSafeArea`, `Link`) | not compiled: KeyboardShortcuts, LaunchAtLogin and Sparkle are Swift packages that would have to be built first |
| Gas Mask (current source) | 23 | 51 of 57 (no `alert`, `Circle`, `onDrop`, `Link`, `NavigationSplitView`, `safeAreaInset`) | not compiled: it imports Combine (3 files), MASShortcut, Sparkle and UniformTypeIdentifiers |
| Maccy | 120 | 71 of 97 | not tried: `@Observable` and the Observation module, SwiftData, Defaults and seven other packages, animations and shapes |
| Ice | 116 | 82 of 106 | not tried: Combine in 34 files, shapes and paths, preference keys, ScreenCaptureKit and the private window server calls |

The Swift in the two apps of the nine that have it:

- **Hex Fiend** (4 files in the app, Cocoa and Foundation only):
  compiled with its bridging header, which brings in all of the HexFiend
  framework's headers and the app's. Since freemac 1.230 all four files
  compile with no errors and no warnings (in 1.227 the Swift stopped at 14
  places, among them `@MainActor`, `DispatchQueue`, `JSONSerialization`
  and `NSColor.usingType`). The app as a whole has not been linked or run.
- **Gas Mask** (23 files in its current source, 16 of them SwiftUI): its
  windows are SwiftUI views that its Objective-C opens through
  `NSHostingController`, which Ferry has. It also needs Combine, its
  MASShortcut and Sparkle frameworks seen from Swift, and the six SwiftUI
  names above.

Both apps' Objective-C files import the header their Swift makes
(`HexFiend_2-Swift.h`, `GasMask-Swift.h`). `ferry-swiftc` can now write
that header, once the Swift compiles.

### The apps' windows (freemac 1.228, Ferry 0.52.0)

Each app was built again from the same source with this round's
`ferry-ibtool` and run under X with no desktop, with input from XTest;
Flycut's shortcut was pressed through a stand-in for freemac's desktop.
No source file's result changed, and the survey wasn't run again; the
table under "Sequel Pro" stands.

| App | What was wrong | Why | Now |
| --- | --- | --- | --- |
| MacPass | The inspector ran off the window's right edge, the entry list and the outline started part way down, and a group's entry count was missing | `ferry-ibtool` left a xib's constraints out. The split view controller's split view wasn't held to its view when MacPass turned off its autoresizing mask, a pane's minimum thickness wasn't kept, and the solver moved panes the split view had placed | The outline with its counts, the entry list and the inspector with its tabs fill the window, each at least its minimum width. The inspector opens at its 200-point minimum, narrower than its tabs and its password row need, which a Mac would widen it for |
| MacDown | A grey band across the top of the window, with the editor and preview under it at the xib's frames | `ferry-ibtool` made no toolbar and left the constraints out | The toolbar shows its items with their pictures, and the editor and preview fill the window. The layout pull-down shows no picture: MacDown takes out the empty item that holds it |
| KeyCastr | Sparkle's window was too tall, with its content at the bottom, and the app's icon was a grey square | Sparkle's prompt is laid out by constraints in a stack view, which `ferry-ibtool` left out, and the window couldn't shrink to them. KeyCastr's `.icns` files hold only JPEG 2000 pictures, which GdkPixbuf doesn't read | The window is 437 by 171 points, the size of its content, with the icon drawn |
| Spectacle | The accessibility window seemed shorter than its content | Its nib makes it 780 by 360 points, unresizable, with the picture under its buttons reaching past its bottom edge | As on a Mac; nothing changed |
| ShiftIt | `AUTHORIZATION_INFORMATIVE_TEXT_10_9` shown in place of its text | The "ShiftIt NoX11" target, the one built, copies no `Localizable.strings` | The build script takes it from the ShiftIt target; Ferry's lookup was right |
| Flycut | Pressing its shortcut under X showed nothing, and the app was killed for its memory | Ferry sent `-update` to the windows on every turn of the run loop. Flycut's bezel sets its background colour in `-update`, which asked for a redraw, so it was updated and drawn again without end, with nothing given back between turns | `-update` goes out once after each event, and the bezel shows its rounded pattern with "Empty" in it. Since 1.229 Ferry places it under X, centred as on a Mac |
| Sequel Pro | Its spinner stayed in the connection form after "Connection failed!" | `ferry-ibtool` read `displayedWhenStopped` the wrong way round | The spinner shows only while it spins, and the help button is a round "?" |

What was added:

| Calls | Apps | Now |
| --- | --- | --- |
| a xib's constraints, hugging and compression resistance, and `translatesAutoresizingMaskIntoConstraints` in compiled nibs | all seven | done |
| a window's content size held at `NSLayoutPriorityWindowSizeStayPut`, within its content minimum and maximum | KeyCastr (Sparkle), MacPass | done; the window keeps its top left corner |
| `NSStackView`'s intrinsic size and hugging from its views; views laid out by constraints measured by their fitting size | KeyCastr (Sparkle), MacPass | done |
| `NSSplitViewController`'s split view held to its view; a pane kept within its item's thickness | MacPass | done |
| toolbars in xibs: items, images, views, sizes, actions, default items and the delegate | MacDown | done; a toolbar item without an image takes its view's |
| `-[NSWindow update]` once after each event; `setWindowsNeedUpdate:` | Flycut | done |
| pattern colours as a window's background | Flycut | done |
| an image-only button, the round help button, the inline badge, a field's border and bezel turning each other off | Sequel Pro, MacDown, MacPass, Flycut | done |
| JPEG 2000 pictures in `.icns` files | KeyCastr | done, through this system's OpenJPEG, which is optional |

### The apps' nibs and windows (freemac 1.229, Ferry 0.53.0)

Each app was built again from the same source with this round's
`ferry-ibtool` and run under X with no window manager, on a 1280 by 800
screen, with input from XTest; Flycut's shortcut was pressed through a
stand-in for freemac's desktop. No source file's result changed, and the
survey wasn't run again; the table under "Sequel Pro" stands.

| App | What was wrong | Why | Now |
| --- | --- | --- | --- |
| MacPass | The inspector opened at its 200-point minimum, its tabs cut off at "Autotype" and its password field a few points wide. The window opened at the top left. The unlock window had no key file control, and the notes, the icon picker, the expiry date picker and the password strength indicator came without their attributes | The split view controller shared the panes out in the 480 points of its nib's view, before MacPass gave it the window's width. `ferry-ibtool` made path controls, text views, collection views, date pickers and level indicators as empty views of their class | The inspector is 278 points wide, as in its nib, with its tabs and its password row whole, and the entry list takes the rest. The window opens part way in from the top left, as its xib places it. The key file control shows under the password field, and the other controls come with their attributes |
| Sequel Pro | The connection window opened at the top left. Its text views, the filter's rule editor, the export dialog's matrix and the combo box cells came without their attributes, and the fields' formatters were left out | `ferry-ibtool` made these elements as empty views of their class and dropped formatters, and Ferry didn't place windows under X | The window opens where its xib places it. The text views keep their text, fonts and colours, the matrix its cells, the combo boxes their items, and the fields their formatters |
| Flycut | The accessibility alert and the bezel opened at the top left | The X server puts a window there when nothing places it, and Ferry didn't move windows | Both are centred: the alert by Ferry, and the bezel where Flycut sets its frame, the middle of the screen, which Ferry now moves the window to. The text view and formatters in its main nib come with their attributes |
| ShiftIt | The authorization alert opened at the top left. Its preferences' two matrices had no cells | Ferry didn't move windows under X; `ferry-ibtool` made matrices empty | The alert is centred across the screen and kept on it, its top first, since it is 593 points tall. The matrices have their cells |
| KeyCastr | Sparkle's prompt and the key display opened at the top left. The composition view in its main nib was an empty view, and a duration formatter in ShortcutRecorder's inspector was left out | As for the others | The prompt opens near the middle of the screen, where its xib places it, and the key display along the bottom, where KeyCastr places it |
| Spectacle | The accessibility window opened at the top left | Ferry didn't move windows under X | It opens at the place its nib gives it. Its xib keeps no initial position, so its frame is used as it is, as on a Mac |
| MacDown | The editor's text view, the preview's web view and the path control in its preferences came without their attributes | `ferry-ibtool` made them as empty views of their class; MacDown sets up its editor and preview itself | They come with their attributes. Its window fills the screen, so it looks as it did |

What was added:

| Calls | Apps | Now |
| --- | --- | --- |
| text views, web views and their preferences, matrices, level indicators, date pickers, path controls, collection views and their items, rule editors, plain controls, Quartz Composer views, formatters, table columns' data cells, cells and formatters at the top level, in compiled nibs | all seven, and Sparkle | done |
| a text view's `value` and `attributedString` bindings, a matrix's button cells bound by `value`, `NSAttributedStringBinding`, `NSDataBinding` | Sequel Pro, MacPass, ShiftIt | done; the test binds both, the apps' own bindings weren't counted |
| a split view controller's panes shared out once in a window, and never thinner than their content | MacPass | done |
| windows placed under X11: `center`, `setFrame:`, `cascadeTopLeftFromPoint:`, a xib's initial position, a document's windows cascading, a titled window kept below the top of the screen, a move the user makes coming back into the frame, frames saved and restored under an autosave name | all seven | done; Wayland's compositor still places windows |
| an alert run modally kept on the screen | ShiftIt | done |
| a block as a JavaScript function; `JSManagedValue` holding its object weakly; `JSVirtualMachine`'s managed references | none of the seven | done |

### Itsycal and Gas Mask (freemac 1.232, Ferry 0.56.0)

Itsycal was cloned at its newest commit, with MASShortcut 2.4.0 and
Sparkle 1.27.1, and built with Ferry's SDK: all 36 of its files compile,
and Sparkle's with ARC and its build settings, less its binary-delta
files and with its ed25519 code compiled in. It was run under X with no
window manager on a 1280 by 800 screen, in a home of its own holding a
calendar file with ten events and a reminders list, and its status item
was clicked through a stand-in for freemac's desktop. Gas Mask was cloned
too; its Growl framework didn't compile, and the round was wound down
before it was taken further. Hammerspoon, Vienna and CocoaRestClient
were looked at as later candidates.

| App | What was wrong | Why | Now |
| --- | --- | --- | --- |
| Itsycal | It wouldn't link: no EventKit, and newer AppKit, Foundation and Core Animation names missing | Ferry had no EventKit, and the app is written for recent macOS | It links and runs, and its status item shows its window |
| Itsycal | The window was 16 to 78 points wide, its month cut off | The month title hugs its text at priority 1; the solver held its width at zero while any weaker wish broke, and the window took the width | The window is the width of its month, at the top right of the screen under the menu bar |
| Itsycal | Clicking the status item raised an exception | It reads an event's `participationStatus` by key, which Ferry's EventKit didn't answer | The status is the user's own among the event's attendees |
| Itsycal | The agenda never showed | `preferredContentSize` changed nothing, and `viewDidLayout`, where the agenda asks for its height, was never sent | The agenda shows under the month, with each day's events and reminders. It appears a few seconds after the click: the window's constraints, with the agenda's rows in them, take over a second to solve, two or three times |
| Gas Mask | It doesn't compile | Its Growl framework, built from source, uses `CFPropertyListFormat`, `kCFAllocatorMalloc` and `AliasHandle`, which Ferry's headers lack, and declares a type its own way that the SDK declares another | Not done |

What was added:

| Calls | Apps | Now |
| --- | --- | --- |
| EventKit: the event store on Tide's calendar and Nudge's reminders files, calendars and sources, events and reminders with their dates, repeats, alarms and attendees, predicates, saves and removals, change notifications, access asked per app | Itsycal | done; birthdays, subscribed calendars and invitations aren't |
| the layout pass before a window draws, with `viewWillLayout` and `viewDidLayout`; `preferredContentSize` as constraints; the safe-area guide following its insets | Itsycal | done |
| the solver letting go of a zero size held against a weaker wish; a constant set to its own value changing nothing | Itsycal | done |
| `NSPredicateEditor` and `NSPredicateEditorRowTemplate`, in code and in nibs | Gas Mask | done; Gas Mask doesn't link to use it |
| Core Audio's default devices, their names, volume and mute, through AudioToolbox's header | the surveyed apps | done, through pactl or wpctl |
| safe areas, display links, window occlusion, symbol configurations, menu section headers, system fill colours, scroll phases, `refusesFirstResponder`, the application's will-become and will-resign notifications, older cell and field calls, a layer's corner curve, `NSDateIntervalFormatter`, `localizedStandardCompare:`, the tags key, reachability flags | Itsycal, Gas Mask | done |

The seven earlier apps weren't rebuilt or run again this round: the
build scripts and builds they were run from were lost with the round's
scratch space. The layout pass and the solver changes reach them too, so
they should be run again in the next round.

### FFmpeg's libraries and tools (freemac 1.233, Ferry 0.57.0)

FFmpeg 8.0.1 and 6.1.1 were built from their release tarballs with
`ferry/apps/ffmpeg.sh` as Intel Mac dylibs (libavutil, libavcodec,
libavformat, libavfilter, libavdevice, libswscale, libswresample, with
`@rpath` install names) and the `ffmpeg` and `ffprobe` tools. OBS needs
8.0; VLC 3.0.24 builds against 6.1.1. Only FFmpeg's own software codecs
are in: no VideoToolbox or AudioToolbox, and no x264, libvpx or libopus;
zlib and bzip2 come from this system. libavutil links CoreFoundation, as
it does on any Mac.

Run under Ferry, both decode four test clips (H.264 with AAC, VP9 with
Opus, Theora with Vorbis, VP8 with MP3) with `ffmpeg -i FILE -f framemd5 -`
to the same frame MD5s, stream by stream, as this system's Linux FFmpeg
6.1.1; 6.1.1's whole output is byte for byte the same, and 8.0.1's
differs only in the line naming its version. Each also gives the same
output as a Linux build of its own version for decoding on 1, 2, 4 and 8
threads, for eight encoders, for MP4, MOV, Matroska, MPEG-TS, FLV and HLS
files, for input from a pipe and for `ffprobe -show_frames`, and for a
lavfi filter graph (with 8.0.1, up to where the Linux build's audio also
changes from run to run). Ctrl-C ends a recording cleanly, as on Linux.

| Calls | Who | Now |
| --- | --- | --- |
| `posix_spawn`, `posix_spawnp`, file actions (open, close, dup2, inherit, chdir, fchdir) and attributes (flags, signal mask and defaults, process group, `POSIX_SPAWN_CLOEXEC_DEFAULT`); a Mac program as the child runs through Ferry | OBS, VLC | done; `POSIX_SPAWN_SETEXEC` and `START_SUSPENDED` answer `ENOTSUP` |
| `glob`, `globfree`, `fnmatch`, with the Mac's `glob_t` and flag numbers | OBS, VLC | done; `GLOB_ALTDIRFUNC`'s directory calls aren't used |
| `mach_wait_until` | OBS | done |
| `backtrace`, `backtrace_symbols`, `backtrace_symbols_fd`: Mac code's frame pointers followed, each frame named by its image and symbol in a Mac's format, in place of this system's, which found no Mac frames | VLC, OBS | done; the walk stops at a frame of Ferry's own without a frame pointer |
| `tcgetattr`, `tcsetattr` (with `TCSASOFT`), `cfmakeraw`, `cfget`/`cfset` speeds, `tcflush`, `tcflow`, `tcdrain`, `tcsendbreak`, `tcgetpgrp`, `tcsetpgrp`, `tcgetsid`, with a Mac's `struct termios` and BSD's numbers; `posix_openpt`, `grantpt`, `unlockpt`, `ptsname` | FFmpeg's `ffmpeg` (single keys), terminal apps | done; on Linux a pseudo-terminal stays CS8 without parity |
| `getrusage`, with `ru_maxrss` in bytes as on a Mac | FFmpeg's `-benchmark` | done |
| `struct rusage` in the SDK's `sys/resource.h` | FFmpeg | done |
| loading plugins: `dlopen` by path from several threads, `@rpath` and `@loader_path` in plugins, `-undefined dynamic_lookup` bundles, weak imports, `dladdr`, a plugin whose library is gone | VLC, OBS | done, with no change to Ferry's loader; libraries are never unloaded |

### Sound: Core Audio and Audio Toolbox (freemac 1.234, Ferry 0.58.0)

Ferry's Core Audio plays and records through this system's sound server,
PulseAudio or PipeWire's PulseAudio server, which it reaches through
libpulse when a program first asks for a device. VLC's sound out (its
`auhal` module) and OBS's audio capture and monitoring were read for
the calls and properties they use, from their source; neither app was
run. AudioToolbox and AudioUnit are served by the Core Audio library.

| Calls | Apps | Now |
| --- | --- | --- |
| the HAL's objects and properties: the system object, its devices and their streams, with names, UIDs, formats, rates, buffer sizes, latency, channel layouts, data sources, hog mode, volume and mute; listeners as procs and blocks | VLC, OBS | done; a device's rate and buffer size are what the program asks for, and the server converts to its own |
| devices from the server: sinks as outputs, sources as inputs, monitors as inputs that are never the default; devices that come and go, and default devices set and followed | VLC, OBS | done |
| a null device when there is no server, which plays into a file or to its own loopback in real time | tests | done |
| IO procs, host time | VLC (pass-through) | done for linear PCM; no compressed formats reach a device |
| HALOutput and DefaultOutput units with render callbacks, HALOutput recording with `AudioUnitRender`, channel maps, the volume parameter | VLC, OBS | done |
| audio queues for output and input | OBS (monitoring) | done for linear PCM, interleaved |
| audio converters | OBS | done for linear PCM to linear PCM; AAC and other compressed formats answer `kAudioConverterErr_FormatNotSupported` |
| Audio Format Services' channel layouts | VLC | done |
| the default devices' volume and mute, from 1.232 | Itsycal | done, through libpulse in place of pactl and wpctl; the null device has no volume |

### OpenGL, Core Video and IOSurface (freemac 1.235, Ferry 0.59.0)

VLC's video output (`modules/video_output/caopengllayer.m` and
`macosx.m`) and OBS's (`libobs-opengl/gl-cocoa.m`) draw with OpenGL into
views and layers, and move frames in Core Video pixel buffers on
IOSurfaces. Ferry now has all of that, drawn with this system's OpenGL.

| Calls | Apps | Now |
| --- | --- | --- |
| CGL: pixel formats (legacy, 3.2 core, 4.1 core), contexts and sharing, current context per thread, locks, parameters (swap interval, backing size), `CGLFlushDrawable`, `CGLTexImageIOSurface2D`; every `gl` call of `<OpenGL/gl.h>`, `<OpenGL/gl3.h>` and their extensions passed to this system's libOpenGL or libGL | VLC, OBS | done, on EGL; the libraries are opened when a program first asks for a pixel format, so programs that don't draw don't need them |
| `NSOpenGLPixelFormat`, `NSOpenGLContext` (`setView:` from any thread, `update`, `flushBuffer`, `makeCurrentContext`, `CGLContextObj`), `NSOpenGLView` (`prepareOpenGL`, `reshape`, `update`, `drawRect:` with its context current), `wantsBestResolutionOpenGLSurface` | OBS, VLC | done |
| `CAOpenGLLayer`: `canDrawInCGLContext:`, `drawInCGLContext:` with the viewport set, `copyCGLPixelFormatForDisplayMask:`, `copyCGLContextForPixelFormat:`, `display` from any thread, `asynchronous`; `visibleRect`, `scrollPoint:` | VLC | done |
| `CVDisplayLink`: create for displays or a display, output callback or handler, start, stop (also from its callback), running, current display, nominal and actual period, time stamps | OBS, VLC | done, at the display's rate (60 Hz, or `FERRY_REFRESH_RATE`), shared with `CADisplayLink` |
| `CVPixelBuffer` and its pool: create (also with bytes, planar bytes or an IOSurface), lock, base address and planes, extended pixels, IOSurface, attachments, the creation keys, pixel format descriptions; BGRA, ARGB, RGBA, 2vuy, yuvs, 420v, 420f, y420, f420, 2101010, half-float RGBA and more | OBS, VLC | done |
| `CVOpenGLTextureCache` and `CVOpenGLTexture` (rectangle textures of a buffer, flipped, clean coordinates); `CVImageBuffer` sizes, clean rect and colour space | VLC | done; planar buffers are refused, as on a Mac, so VLC's OpenGL converter uploads planes itself |
| IOSurface: create, lookup by ID, lock, base address and planes, bytes per row, element sizes, use count, values | OBS | done, in the program's memory: surfaces aren't shared with other processes |
| `CGDisplay*` calls for display IDs and modes | OBS | being written for OBS in `appkit/CGDirectDisplay.m` |

How it draws: each context renders into an offscreen EGL buffer. A flush
reads it back with `glReadPixels` (BGRA) and a view or layer paints the
frame through Core Graphics, so OpenGL's drawing shows in any window,
under X, Wayland or none. That costs CPU on every frame. On a
4-core machine with Mesa's llvmpipe, a 1920 by 1080 frame takes about
3.5 ms to flush (2.4 ms of it the read back) and about 2 ms to paint;
uploading a 1080p BGRA IOSurface to a texture takes 0.8 ms. So 1080p at
60 frames a second uses about a third of one core for the copies alone,
on top of the rendering; 720p uses less than half that. A GPU driver
makes the rendering quicker but not the copies. `CGLTexImageIOSurface2D`
copies the surface when it's called, so later writes to the surface need
another call. Each context's swap interval paces its flushes to the
display's rate. Without OpenGL (no libEGL.so.1, or no display it can
use), Ferry says so once on stderr, `CGLChoosePixelFormat` returns
`kCGLBadDisplay`, the AppKit and Core Animation classes give nil or draw
nothing, and pixel buffers and display links still work.

Tests: `corevideo_pixelbuffer`, `corevideo_displaylink`, `opengl_cgl`,
`opengl_iosurface`, `opengl_view`, `opengl_layer` and `opengl_missing`.
The OpenGL ones run when OpenGL makes contexts here and are skipped
otherwise. With `FERRY_TEST_SHOTS` set to a folder, `opengl_view` and
`opengl_layer` save pictures of their windows there.

## What the apps need most

Counted over the nine apps:

1. **More views**: done for the ones every app's nibs use. Split views
   and tab views came in 1.155; table and outline views, which stopped Gas
   Mask and most likely Sequel Pro, in 1.159; `NSPopUpButton`,
   `NSToolbar`, `NSSegmentedControl`, `NSSearchField` and `NSStackView` in
   1.164. Split view and tab view controllers, which MacPass builds
   its windows on, came in 1.210 with `NSGradient` and `NSShadow`, the
   drawing classes six of the apps use. Collection views and rulers, which MacPass and Sequel Pro use, came in 1.212. Tracking areas and cursors, which four of the apps use, came in 1.213, with shadows drawn and `NSAnimation`. In 1.219 a search of the apps' source added the calls they make next (child windows, login items, file calls, encodings). In 1.221 and 1.222 each app's source was compiled against Ferry's SDK and what it stopped at was added, most-used first. In 1.223 Flycut, Spectacle and ShiftIt were linked into bundles with Ferry's SDK and run, each showing its status item, its menu and its windows. In 1.224 their global shortcuts were pressed through freemac's desktop, and Spectacle's and Flycut's did what they do on a Mac; asset catalogues were compiled, so Spectacle's status item shows its picture; and KeyCastr became the fourth app to link and run. In 1.225 MacPass and MacDown became the fifth and sixth, with the frameworks they bring built from their source: MacPass opens and unlocks a KeePass database and shows its entries, and MacDown renders Markdown in its preview and opens its preferences window, whose xib, in the older format, `ferry-ibtool` now reads. In 1.226 Sequel Pro became the seventh, with its MySQL framework built against MariaDB Connector/C, built from its source, and the older AppKit, Foundation and keychain names its files stopped at: it shows its connection window, and Connect reaches the client library, which reports that no server answers. Counted over the same clones, 582 of 627 files now compile (543 before), and the table under "Sequel Pro" lists what stops the rest. In 1.228 the seven apps' windows were laid out and drawn as on a Mac: the constraints in their xibs reach their nibs, a window's size gives way to them, and MacDown has its toolbar, Flycut its bezel and KeyCastr its icon (see "The apps' windows"). In 1.229 every element in the seven apps' xibs became its own class, with its attributes (text views, web views, matrices and ten more kinds, 136 elements in all), MacPass's inspector opened at the width of its nib, and under X windows were placed as on a Mac, centred, cascaded or where their nibs put them, rather than at the top left (see "The apps' nibs and windows"). Gas Mask and Hex Fiend also have Swift in them; Ferry builds Swift since 1.227, but neither links yet. In 1.232 Itsycal, a menu-bar calendar, became the ninth (TomatoBar, in 1.230, was the eighth), with MASShortcut and Sparkle built from their source and a new EventKit on freemac's own calendar and reminders: its status item opens the month with today ringed and its events marked, and the agenda under it lists the coming days' events and reminders (see "Itsycal and Gas Mask"). Gas Mask, the tenth, still doesn't link: the Growl framework it brings stopped at older Core Foundation and Carbon names before the round was wound down.
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
