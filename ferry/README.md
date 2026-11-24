# Ferry

Ferry runs simple command-line programs and simple windowed programs built for Intel Macs on freemac (and
other x86-64 Linux systems). It is our own code, written from public
documentation, and an optional add-on: it isn't on the freemac ISO.

```
ferry ./program [arguments]
ferry "Some App.app"                  # an app bundle: its program, from Info.plist
ferry SomeInstaller.pkg               # Ferry's Installer, for .pkg and .dmg files
```

With the package installed, `./program` also works directly, because Ferry
registers itself with the kernel for 64-bit Intel Mach-O programs.

## What runs

Ferry runs 64-bit Intel (x86-64) Mach-O programs that only use the C library
and basic POSIX calls: text and number formatting, files and folders, error
numbers, memory, sorting, clocks, signals, child processes, `getopt`,
user lookups and the like. Universal ("fat") files work when they contain an
Intel slice.

It also has its own Objective-C runtime (Ferry's `libobjc.A.dylib`) and
blocks, so Objective-C command-line programs that only need the runtime and
`NSObject` run: classes, categories, protocols, properties, `+load` and
`+initialize`, manual and automatic reference counting (ARC), weak
references, autorelease pools, `@synchronized`, blocks, and the
`<objc/runtime.h>` calls apps use for introspection and swizzling.

Ferry also has its own Foundation and the basics of CoreFoundation, loaded as
Mac frameworks (`Foundation.framework`, `CoreFoundation.framework`), so
programs written against Foundation run too: `NSString` (including `@"..."`
literals and `%@` formatting), `NSNumber`, `NSArray`, `NSDictionary`,
`NSSet`, `NSData`, `NSDate`, `NSURL`, `NSError`, property lists (XML, binary
and the old text form), `NSBundle` (a program inside an `.app` folder finds
its `Info.plist`, resources and localized strings), `NSUserDefaults` (kept
in `~/.config/ferry/preferences/<app id>.plist`), `NSFileManager`,
`NSProcessInfo`, `NSRunLoop`, `NSTimer`, `NSNotificationCenter`, and the
`CF...` calls on the same objects, `NSAttributedString`, keyed
archives (`NSKeyedArchiver`, `NSKeyedUnarchiver`), `NSInvocation`,
`NSMethodSignature`, `NSProxy` and message forwarding
(`forwardInvocation:`), `NSUndoManager`, `NSJSONSerialization`,
`NSDateFormatter` with `NSTimeZone` and `NSLocale`, and, from freemac
(1.173), `NSCalendar` (Gregorian and ISO 8601), `NSDateComponents`,
`NSNumberFormatter`, `NSISO8601DateFormatter`, `NSDateComponentsFormatter`
and `NSByteCountFormatter` (dates and numbers in English only).

From Ferry 0.21.0 (freemac 1.194) there are also `NSTask`, `NSPipe` and `NSFileHandle`
(a task runs this system's program of the name it is given, or a Mac
program through Ferry), `NSRegularExpression` and `NSTextCheckingResult`
(on this system's ICU, as on a Mac), `NSScanner`, `NSXMLParser` (on this
system's libxml2, as on a Mac), `NSOperationQueue` with `NSOperation`,
`NSBlockOperation` and `NSInvocationOperation`, the locks (`NSLock`,
`NSRecursiveLock`, `NSCondition`, `NSConditionLock`), `NSCache` and
`NSProgress`. Ferry runs a program on one thread, so queued operations
and a task's notifications come on that thread, from the run loop.
ICU and libxml2 are loaded only when a program first uses them.

From Ferry 0.22.0 (freemac 1.195), steppers, level indicators, colour
wells (with a basic colour panel), date pickers (text with a stepper, or
a calendar and a clock), combo boxes, popovers, path controls and token
fields are there too, with their cells and read from nibs, and `NSSound`
plays sounds through PipeWire's `pw-play` (or `paplay` or `aplay`),
finding the Mac's alert sounds by name among freemac's own.

From Ferry 0.23.0 (freemac 1.196), programs can also load URLs over http
and https: `NSURLSession` (data, upload and download tasks),
`NSURLConnection`, `NSURLRequest` and `NSHTTPURLResponse`, errors in
`NSURLErrorDomain`, and `NSData`'s and `NSString`'s `...ContentsOfURL:`
for web addresses, through this system's libcurl, opened only when a
program first loads a URL. Transfers move, and handlers run, while the
program runs its run loop or waits in dispatch.

From Ferry 0.24.0 (freemac 1.197) there is also `NSXMLDocument`, with `NSXMLNode`,
`NSXMLElement`, `NSXMLDTD` and `NSXMLDTDNode`: a document read from a
string, data or a file (with this system's libxml2, as on a Mac) is a
tree of objects that can be walked, changed, searched with XPath
(`nodesForXPath:error:`) and written out again (`XMLString`, `XMLData`,
pretty printed or canonical). XQuery, XSLT and HTML documents are left out.

From Ferry 0.25.0 (freemac 1.198), QuartzCore.framework is Ferry's Core Animation: layers and their tree,
drawn with Ferry's Core Graphics (backgrounds, borders, rounded corners,
opacity, contents, shape, gradient and text layers), and implicit and
explicit animations stepped by a timer on the main run loop. AppKit's
layer-backed and layer-hosting views draw their layers, and
NSAnimationContext with the views' animator proxies animates frames and
alpha. Shadows, masks, filters, transitions and 3D perspective aren't
drawn. The tests step animations with a test clock of Ferry's own
(`FerryCASetManualClock` and `FerryCAAdvanceTime`), so each run gives the
same results.

From Ferry 0.26.0 (freemac 1.199), URL loading also follows redirects as the
delegate decides, answers HTTP Basic and Digest challenges (from the
delegate, the URL's user and password or `NSURLCredentialStorage`), lets a
delegate accept an https certificate the system doesn't trust, keeps
cookies in `NSHTTPCookieStorage` (saved to
`~/.config/ferry/cookies/<program>.plist`) and responses in `NSURLCache`
(in memory and under `~/.cache/<program>/URLCache`), honouring the
request cache policies and revalidating stale responses, and loads
`data:` URLs.

From Ferry 0.27.0 (freemac 1.200), programs can link the Security
framework: `SecItem` and the older `SecKeychain` password calls keep
generic and internet passwords in `~/.local/share/ferry/keychain` (mode
0700; the secrets are encrypted with a key kept beside them, which stops
casual reading only, not anyone who can read your files), an app's check of
its own code signature passes while any other code reads as unsigned, and
`SecTrust` checks certificates with this system's OpenSSL. libSystem now
has CommonCrypto's digests, HMAC, PBKDF2, random bytes and AES (AES needs
OpenSSL's libcrypto, which Ferry loads only when a program uses it), and
the macOS version is one answer everywhere: 14.7 in
`/System/Library/CoreServices/SystemVersion.plist`, `NSProcessInfo`,
`Gestalt` and `uname`.

From Ferry 0.28.0 (freemac 1.201), programs can ask the system about
itself and load code while they run: `sysctl` and `sysctlbyname` answer
the common kernel and hardware names (macOS 14.7, the processors, memory,
model and CPU name) and `kinfo_proc` for a process, `proc_pidpath`,
`host_statistics64`, `task_info` and `getattrlist` answer from Linux, and
`dlopen`, `dlsym` and `dladdr` load Mac libraries and plug-in bundles by
path, `@rpath`, `@executable_path` or `@loader_path`, and Ferry's own
frameworks by their `/System/Library/Frameworks` paths. `NSBundle`'s
`load` and `principalClass` and `CFBundleGetFunctionPointerForName` work on
plug-ins, and `@available` checks answer for macOS 14.7. Code loaded this
way is never unloaded.

From Ferry 0.29.0 (freemac 1.202), programs run on real threads:
`NSThread` (each thread with its own run loop and autorelease pools, and
`performSelectorOnMainThread:`, `performSelector:onThread:` and
`performSelectorInBackground:`), the pthread calls Mac programs import,
real `NSLock`, `NSRecursiveLock`, `NSCondition`, `NSConditionLock`,
`@synchronized`, `OSSpinLock` and `os_unfair_lock`, dispatch's global
queues on a pool of worker threads (the main queue still only on the main
thread) and `NSOperationQueue` running operations at the same time. The
Objective-C runtime and Foundation's shared state are safe across
threads, URL loading included (redirects, challenges, cookies, the URL
cache and server trust run on its network thread, and the cookie and
credential storages and URL caches have locks of their own); AppKit is for
the main thread only, and Ferry warns once when it
is used elsewhere. Where a Mac would hang for ever on a deadlock, Ferry
stops the program with a message.

From Ferry 0.30.0 (freemac 1.203), Mac programs written in C++ and
Objective-C++ run on this system's LLVM libc++ and libc++abi (packages
libc++1 and libc++abi1), which Ferry opens only when a program links them.
That covers:

- the standard library, streams in step with `printf`, locales, `chrono`
  and `filesystem`;
- exceptions across the program, its libraries and this system's code;
- `std::thread`, mutexes, condition variables and futures on a Mac's
  layouts;
- ARC objects with C++ ivars, and blocks capturing C++ objects;
- Objective-C and C++ exceptions passing through each other's frames.

Without those libraries, a C++ program stops and names them, and other
programs are unaffected. Wide file streams are not supported yet.

From Ferry 0.31.0 (freemac 1.204), Mac programs can use thread-local
variables: C's `__thread` and `_Thread_local`, Objective-C's `__thread` and
C++'s `thread_local`, in the program, in its own libraries and in libraries
opened with `dlopen`. Each thread gets its own copy of an image's variables
the first time it uses one, started from their first values, on pthreads,
`NSThread`, `std::thread` and dispatch's worker threads alike. C++
`thread_local` objects are built on first use and destroyed, last built
first, when their thread ends, and the main thread's are destroyed when the
program exits, before its static objects. A thread's copies are freed when
it ends, and `ferry-cc` links programs that use them.

From Ferry 0.32.0 (freemac 1.205), programs can use the network the BSD way: sockets with Mac layouts and errors, select, poll, kqueue and kevent, libdispatch READ, WRITE, SIGNAL and PROC sources, CFSocket with a run loop source, and CFStream and NSStream socket streams with delegates, client callbacks and TLS through the system's OpenSSL (libssl 3 or 1.1), with certificates checked by Security.framework's trust calls. NSNetService and NSNetServiceBrowser are there but have no Bonjour, so they always report that it can't be reached.

From Ferry 0.33.0 (freemac 1.206), Mac apps can print. A view, a window,
a text view or a document prints through GTK's print dialog and Page
Setup, shown as sheets, on pages laid out from `NSPrintInfo` (paper,
margins, orientation, scaling and pagination) and drawn by the app's own
code into a PDF with Cairo, which goes to a file, a viewer or a printer.
`dataWithPDFInsideRect:` and the PDF operations make PDF data without a
panel. `NSFontManager` and `NSFontPanel` (GTK's font chooser) list the
installed fonts and change them, so the font menu's Bold, Italic, Bigger
and Smaller and the font panel work in text views. Accessory views in the
panels, the progress panel and font collections are left out.

From Ferry 0.34.0 (freemac 1.207), programs can post notifications with UNUserNotificationCenter or NSUserNotificationCenter. They are shown by the desktop's notification server, with the app's name and icon, their actions as buttons and a text reply where the server has one, and the delegates hear what the user clicked or typed. Requests can wait for a time interval or a calendar date. The app's Dock badge, its requests for attention and its Dock menu reach the Dock over the LauncherEntry interface that freemac's Dock reads, which shows the badge, words or a number, and the app's Dock menu. With no notification server, nothing is shown and the program carries on.

From Ferry 0.35.0 (freemac 1.209), Mac programs can use Core Data: a
model built in code or read from its Xcode source (`.xcdatamodeld`),
managed objects with `@dynamic` accessors, contexts on the main queue, on
private queues and as children of other contexts, with undo, merging and
the change notifications. Fetch requests and the fetched results
controller work, as do `NSPersistentContainer` and SQLite, binary and
in-memory stores with lightweight migration and batch deletes and updates.
`NSArrayController` and `NSObjectController` work in entity mode.
Compiled models (`.mom` and `.momd`) aren't read yet, and Ferry says so
once when an app asks for one. Store files made on a Mac aren't read either.

From Ferry 0.36.0 (freemac 1.210), Mac apps can draw gradients with
`NSGradient`: along a line, in a rectangle or a path at an angle, and
between circles, with stops at any locations. `NSShadow` is there with
its settings, archives and the `NSShadow` text attribute, though shadows
aren't drawn yet. `NSSplitViewController` and `NSSplitViewItem` lay out
panes in a split view, with sidebars and inspectors that collapse by
code, by `toggleSidebar:` or by dragging, holding priorities and
thickness limits. `NSTabViewController` shows its tabs as a segmented
control or as the window's toolbar, loading each tab's view when it is
first shown. These are what MacPass's document window and preferences
are built on.

From Ferry 0.37.0 (freemac 1.211), Foundation has `NSExpression` and
`NSComparisonPredicate`, and `NSPredicate` reads the rest of Apple's format
strings: arithmetic, the built-in functions such as `sum:`, `average:` and
`uppercase:`, `FUNCTION`, `TERNARY`, `CAST`, `SUBQUERY`, and `MATCHES` with
regular expressions. `predicateWithSubstitutionVariables:` fills in
variables. `NSDecimalNumber` and the `NSDecimal` functions do exact base-10
arithmetic with Apple's rounding modes and exceptions, and work with
`NSNumber`, `NSScanner`, `NSNumberFormatter`, keyed archiving and JSON.
Core Data keeps decimal attributes exactly in its SQLite and binary stores,
and a dictionary fetch takes expression descriptions with aggregates,
`propertiesToGroupBy` and `havingPredicate`.

For drawing there are Ferry's own Core Graphics and Core Text
(`CoreGraphics.framework`, which also serves `CoreText` and
`ApplicationServices`), drawn by this system's Cairo, Pango and HarfBuzz:
bitmap contexts, paths, colours, transforms, clipping, gradients, images
(PNG files), and text in the system's fonts, in lines and wrapped frames.
Mac font names map to the nearest installed font (on freemac, Helvetica and
the system font are Inter). See
[docs/ferry-gui.md](../docs/ferry-gui.md) for what is missing and the plan
towards graphical apps. A Mac app's standard folders map to their usual
Linux places: Documents to `~/Documents`, Application Support to
`~/.local/share`, Caches to `~/.cache`.

Ferry also has the start of its own AppKit (`AppKit.framework`, also
reached as `Cocoa`), so a program can open windows on the desktop, built
in code or loaded from nib files (an app's `MainMenu.nib` is loaded by
`NSApplicationMain`, with outlets, actions and `awakeFromNib`): `NSApplication`, `NSWindow`, `NSView` with
`drawRect:`, mouse and keyboard events, `NSColor`, `NSFont`,
`NSBezierPath`, buttons, check boxes, radio buttons, text fields and
labels, and menus' keyboard shortcuts. Windows are shown through this
system's GTK 3 (on Wayland, or X11), get the desktop's own title bars, and
are sharp on HiDPI screens. It also has `NSImage` and image views (PNG,
JPEG, GIF, TIFF, BMP, ICO, `.icns` and PDF images, read with this system's
GdkPixbuf and Poppler), window and view controllers that load their own
nibs, the clipboard (`NSPasteboard`, shared with other apps for text, with
cut, copy and paste in text fields), Open and Save panels (the system's
file chooser), files and text dropped onto views from other apps, the
app's icon in the dock, and menu bar items (`NSStatusItem`, shown in the
desktop's menu bar over StatusNotifierItem, with their menus). Exceptions work as on a Mac: `@try`/`@catch`/
`@finally` catch them, and one a program leaves uncaught in its event loop
is reported and the app carries on. Scroll views, text views (with RTF
and simple HTML documents), progress indicators, boxes, tab and split
views, table and outline views (cell-based or view-based, with
selection, sorting from the header, resizable columns and, from freemac
(1.178), text cells edited in place), pop-up
buttons, segmented controls, search fields, stack views, toolbars and,
from freemac (1.184), sliders are there too,
and key-value observing, so bindings follow the values they are bound to.
From freemac (1.184) observing is automatic (a hidden subclass's setters
announce each change, and dependent keys are followed), bindings write
the user's edits back to their key path (text fields, buttons, pop-up
buttons and sliders, with `NSObjectController`'s `selection.*`,
`NSUserDefaultsController`'s `values.*` and bindings made in nibs), and
formatters on controls, cells and edited table cells show values, read
what is typed and beep at what they can't read. From freemac (1.188)
`NSArrayController` is there too (bound content, sorted and filtered
`arrangedObjects`, a selection that answers `NSMultipleValuesMarker`, and
adding, inserting and removing), with table columns bound to
`arrangedObjects.key`: a click selects in the controller, a click on a
column's title sorts it, and an edited cell writes back. Key-value
coding has `mutableSetValueForKey:` and the collection operators
(`@count`, `@sum`, `@avg`, `@min`, `@max` and the unions), and
`NSPredicate` reads Apple's format strings (most of them from Ferry 0.37.0; see below). From freemac
(1.190) `NSTreeController` is there (children, count and leaf key paths,
`arrangedObjects` as a tree of `NSTreeNode`s, a selection of
`NSIndexPath`s, and adding, inserting, removing and moving nodes), with
outline view columns bound to `arrangedObjects.key`: rows open and close,
the selection goes both ways, a column's title sorts the tree, and an
edited cell writes back. Columns' per-row `editable` and `enabled`
bindings are followed, an edited cell isn't written back when its
controller isn't editable, and `NSDictionaryController` shows a
dictionary as key-value pairs. From freemac (1.191) the four controllers
load from nibs with their settings and the binding connectors that join
them, so a nib that binds a table or an outline to a controller works with
no code; view-based tables and outlines make their cell views from the
nib's prototypes, and controls in a cell view bound to `objectValue.key`
write back. Bindings validate with `NSValidatesImmediately` (a refused
value is presented and the control put back), follow
`NSRaisesForNotApplicableKeys`, enable and make editable their controls
conditionally, and the array controller takes `NSDeletesObjectsOnRemove`,
`NSSelectsAllWhenSettingContent` and `NSHandlesContentAsCompoundValue`.
Document-based apps work: `NSDocument` and `NSDocumentController` take the
document types from the app's Info.plist and give it New, Open, Save,
Save As and Revert, the edited dot, the Save / Don't Save / Cancel question
on closing and quitting, and the Open Recent menu; from freemac (1.178) a
document class that autosaves in place is autosaved after each change,
closes without asking and gets Revert To > Last Saved Version (versions
are left out). `NSAlert` shows alerts, run modally or as sheets hanging in
their window, and `NSWorkspace` opens web addresses, files and folders
through the desktop's own launcher (`gio open` or `xdg-open`, never a Mac
app) and gives files their icons from the desktop's icon theme.
Ctrl works as Command (and Super too);
`FERRY_CONTROL_KEY=control` makes it the Mac's Control key instead.

### Installing Mac apps

Ferry has its own Installer, a Mac app of its own built with Ferry's
AppKit (`installer/`). `ferry SomeApp.pkg` (or a `.dmg`, or a double-click
in the file manager) opens it: it shows the package's welcome, read-me and
licence pages, then installs **for the user alone**: apps go to
`~/Applications` (and into the desktop's app list, through
`freemac-mac-app` when the desktop has it), everything else into Ferry's
own folder, `~/.local/share/ferry/root`. Nothing outside the home folder
changes, so no password is asked for. It reads flat packages (`.pkg`,
`.mpkg`: xar archives with gzip, `pbzx` or plain cpio payloads), old
bundle packages, and disk images, which it opens with this system's 7-Zip
(`7z`; a disk image holding an app to drag to Applications is copied
straight there). A package's install scripts and its JavaScript checks
are not run, and the Installer says so before installing; anything only
those scripts would have set up is missing. `ferry X.pkg --info` and
`ferry X.pkg --install [--applications DIR] [--root DIR]` do the same
without a window.

## What doesn't run, and won't

- **App Store apps.** They are signed and encrypted for Apple's systems. Ferry
  doesn't decrypt, bypass or imitate any of that, and never will.
- **Most graphical Mac apps, for now.** Ferry's AppKit is young: many
  some views, alerts and the document classes are missing, and
  storyboards aren't read. Real apps' nibs (made by Xcode, in both its
  formats) load, and real apps start, but none runs all the way yet:
  [docs/ferry-compat.md](../docs/ferry-compat.md) lists the apps tried and
  what stops each one. These are being added step by step (see
  [docs/ferry-gui.md](../docs/ferry-gui.md)). SwiftUI, Metal and other large
  frameworks are further off. Core Data is there (from Ferry 0.35.0), but
  compiled models aren't read yet, so an app that ships only a `.momd`
  stops there.
- **Apple silicon (arm64) programs.** Ferry runs Intel programs only, and says
  so when given an arm64 one.
- **Programs using calls Ferry doesn't have yet**, such as threads, sockets,
  C++ (libc++), `NSXMLDocument` or extra libraries. (Some of a Mac's
  `/usr/lib` libraries come from this system's copy: zlib, bzip2, xz,
  libxml2, SQLite and ICU.) When a program reaches a call Ferry lacks,
  it stops with a message naming that call (`this program uses X, which Ferry
  doesn't support yet`) and exit status 127, rather than guessing. A
  program that links a system framework Ferry doesn't have still starts
  (Ferry names the framework); the framework's classes are nil and its
  calls stop the program as above. Grand Central Dispatch works, with
  every queue run in order on the program's one thread.

## How it works

1. **Loader** (`src/loader.c`). Reads the Mach-O file, maps its segments,
   applies its relocations (classic rebase/bind opcodes, the newer chained
   fixups, and the relocation entries of libraries built before Mac OS X
   10.6) and calls `main`.
2. **Symbol lookup** (`src/lookup.c`). Each imported call is matched against
   Ferry's own tables first, then against a short list of C library calls that
   behave identically on both systems (`src/passthrough.c`). Anything else gets
   a stub that stops the program with the message above.
3. **libSystem layer** (`src/stdio.c`, `src/posix.c`, `src/errno.c`). Where
   macOS and Linux differ (the layout of `FILE`, `struct stat` and directory
   entries, flag values, error and signal numbers), Ferry converts between
   them.
4. **Objective-C runtime** (`src/objc/`). The loader hands the program's
   `__objc_*` sections to the runtime, which registers selectors, classes,
   categories and protocols before `main` runs. `objc_msgSend` and friends
   (`msgsend.S`) look methods up in a per-class cache; `nsobject.c` has
   `NSObject`, reference counting, ARC, weak references and autorelease
   pools; `blocks.c` has blocks; `dispatch.c` has Grand Central Dispatch,
   run from Foundation's run loop. `exception.c` and `unwind.S` throw and
   catch Objective-C exceptions: Ferry's own two-phase unwinder walks the
   program's frames with the compact unwind and DWARF tables the linker
   leaves in each Mach-O image, and finds the `@catch` blocks in the
   compiler's tables for each function.
5. **Foundation** (`foundation/`). Written in Objective-C and built with
   `ferry-cc` into a Mac library, `frameworks/Foundation.framework/Foundation`,
   which the loader finds when a program asks for Foundation or
   CoreFoundation (installed in `/usr/lib/ferry/frameworks`; `FERRY_FRAMEWORKS`
   points elsewhere). Every CoreFoundation object is the matching Foundation
   object, so the two can be mixed freely, as on a Mac.
6. **Core Graphics and Core Text** (`graphics/`). Also Objective-C built
   into a Mac library, `frameworks/CoreGraphics.framework/CoreGraphics`,
   which serves CoreText and ApplicationServices too. It draws by calling
   this system's Cairo, Pango and HarfBuzz directly (both systems use the
   same calling convention); Ferry opens those libraries only when a program
   first draws, and only for the calls listed in `graphics/host.h`
   (`src/host.c`).
7. **AppKit** (`appkit/`). Objective-C again, built into
   `frameworks/AppKit.framework/AppKit` (`Cocoa` is an alias). Each window
   is a GTK 3 window whose contents are an image that the program's views
   draw into with Core Graphics; GTK's events become `NSEvent`s, and GTK's
   main loop runs inside Foundation's run loop. GTK is opened only when a
   program uses AppKit, and only for the calls in `appkit/gtk.h`. Without a
   display, windows still work off screen, which the tests use. Nib files
   are keyed archives or, from current Xcode, `NIBArchive` files
   (`appkit/ANibArchive.m` reads those); `appkit/NSNib.m` turns Interface
   Builder's stand-in objects into the real ones and makes the connections.
   Menu bar items (`appkit/NSStatusBar.m`) are D-Bus objects on the
   session bus, through GIO's calls in `appkit/gtk.h`.
   The few Carbon calls Cocoa apps still make (global hotkeys, keyboard
   layouts, Accessibility) are answered here too (`appkit/Carbon.m`), the
   way a Mac answers when the thing isn't available.
8. **The Installer** (`installer/`), a Mac app built with the frameworks
   above, which `ferry` starts for a `.pkg` or `.dmg`. Its package reader
   (`installer/IPackage.m`) is written from the public descriptions of the
   xar, cpio and `pbzx` formats and of the Distribution and PackageInfo
   files; `tests/tools/make_pkg.py` builds the package its test installs.

## Sources

Ferry is written only from public material: the Mach-O file format as
described in Apple's published headers in the open-source XNU and cctools/ld64
releases and in LLVM's documentation, the System V AMD64 calling convention,
the POSIX standard, and the open-source C library headers that document
structure layouts and constant values. The Objective-C runtime follows
Apple's public API documentation, clang's published ARC and block ABI
specifications, and the metadata clang emits for our own test programs (read
with LLVM's `llvm-objdump --objc-meta-data`); exceptions follow the
Itanium C++ ABI's exception-handling specification, the DWARF standard's
call frame information, and the compact unwind format as LLVM documents it
in its own headers; it uses no code from Apple's,
GNUstep's or Darling's runtimes. Foundation, Core Graphics, Core Text and AppKit are written from Apple's
public API documentation and the published descriptions of the property
list formats; they use no code from Apple's, GNUstep's or Darling's
frameworks, and AppKit's controls are Ferry's own drawing, not Apple's
artwork. Nothing in Ferry comes from
disassembling or decompiling Apple software, and it contains no Apple code,
binaries or assets.

## The SDK and tests

`sdk/` holds a small kit for building test programs on Linux, with no Mac or
Apple SDK: our own C headers (`sdk/include`), a description of the libSystem
calls Ferry provides (generated by `ferry --list-symbols`), and `ferry-cc`,
which runs clang and LLVM's lld with them:

```
ferry-cc -O1 -o hello hello.c
ferry ./hello
ferry-cc -O1 -fobjc-arc -o hello hello.m -lobjc    # Objective-C
ferry-cc -O1 -fobjc-arc -o hello hello.m -framework Foundation
ferry-cc -O1 -o draw draw.m -framework CoreText -framework CoreGraphics -framework Foundation
ferry-cc -O1 -fobjc-arc -o app app.m -framework Cocoa
```

`make check` builds every program in `tests/` this way, in both relocation
formats, runs it through Ferry and compares the output. It needs `clang`,
`lld` and `llvm` (for `llvm-nm`), and `python3` for the Installer's test; the drawing tests also need Cairo, Pango
and HarfBuzz (the runtime libraries, not their `-dev` packages) and some
fonts, and the AppKit tests need GTK 3 (and GdkPixbuf and Poppler for
images), and the menu bar test needs `dbus-run-session` and `gdbus` (it is
skipped without them). The on-screen tests (a window, the dock icon, a screen at scale 2)
also need `weston`, which they start headless; without it they are
skipped.

## Building and packaging

```
make                       # builds ./ferry, the SDK's library descriptions, Foundation,
                           # CoreGraphics and AppKit (these need clang, lld and llvm, as the tests do)
make check                 # runs the tests
./packaging/build-deb.sh   # builds freemac-ferry_VERSION_amd64.deb
```

Ferry is GPL-3.0-or-later, like the rest of freemac.
