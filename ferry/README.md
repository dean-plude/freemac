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
`CF...` calls on the same objects, `NSAttributedString`, and keyed
archives (`NSKeyedArchiver`, `NSKeyedUnarchiver`).

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
views, and table and outline views (cell-based or view-based, with
selection, sorting from the header and resizable columns) are there too,
and key-value observing, so bindings follow the values they are bound to.
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
  views (pop-up buttons, toolbars, alerts) and the document classes are missing, and
  storyboards aren't read. Real apps' nibs (made by Xcode, in both its
  formats) load, and real apps start, but none runs all the way yet:
  [docs/ferry-compat.md](../docs/ferry-compat.md) lists the apps tried and
  what stops each one. These are being added step by step (see
  [docs/ferry-gui.md](../docs/ferry-gui.md)). SwiftUI, Metal and other large
  frameworks are further off.
- **Apple silicon (arm64) programs.** Ferry runs Intel programs only, and says
  so when given an arm64 one.
- **Programs using calls Ferry doesn't have yet**, such as threads, sockets,
  C++ (libc++), `NSInvocation` or extra libraries. (Some of a Mac's
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
