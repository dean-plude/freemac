# Ferry

Ferry runs simple command-line programs built for Intel Macs on freemac (and
other x86-64 Linux systems). It is our own code, written from public
documentation, and an optional add-on: it isn't on the freemac ISO.

```
ferry ./program [arguments]
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
`CF...` calls on the same objects. See
[docs/ferry-gui.md](../docs/ferry-gui.md) for what is missing and the plan
towards graphical apps. A Mac app's standard folders map to their usual
Linux places: Documents to `~/Documents`, Application Support to
`~/.local/share`, Caches to `~/.cache`.

## What doesn't run, and won't

- **App Store apps.** They are signed and encrypted for Apple's systems. Ferry
  doesn't decrypt, bypass or imitate any of that, and never will.
- **Graphical Mac apps, for now.** Ferry has no AppKit yet;
  they are being added step by step (see
  [docs/ferry-gui.md](../docs/ferry-gui.md)). SwiftUI, Metal and other large
  frameworks are further off.
- **Apple silicon (arm64) programs.** Ferry runs Intel programs only, and says
  so when given an arm64 one.
- **Programs using calls Ferry doesn't have yet**, such as threads, sockets,
  C++ (libc++), Objective-C exceptions (`@throw`) or extra libraries. When a program reaches a call Ferry lacks,
  it stops with a message naming that call (`this program uses X, which Ferry
  doesn't support yet`) and exit status 127, rather than guessing.

## How it works

1. **Loader** (`src/loader.c`). Reads the Mach-O file, maps its segments,
   applies its relocations (classic rebase/bind opcodes and the newer chained
   fixups) and calls `main`.
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
   pools; `blocks.c` has blocks.
5. **Foundation** (`foundation/`). Written in Objective-C and built with
   `ferry-cc` into a Mac library, `frameworks/Foundation.framework/Foundation`,
   which the loader finds when a program asks for Foundation or
   CoreFoundation (installed in `/usr/lib/ferry/frameworks`; `FERRY_FRAMEWORKS`
   points elsewhere). Every CoreFoundation object is the matching Foundation
   object, so the two can be mixed freely, as on a Mac.

## Sources

Ferry is written only from public material: the Mach-O file format as
described in Apple's published headers in the open-source XNU and cctools/ld64
releases and in LLVM's documentation, the System V AMD64 calling convention,
the POSIX standard, and the open-source C library headers that document
structure layouts and constant values. The Objective-C runtime follows
Apple's public API documentation, clang's published ARC and block ABI
specifications, and the metadata clang emits for our own test programs (read
with LLVM's `llvm-objdump --objc-meta-data`); it uses no code from Apple's,
GNUstep's or Darling's runtimes. Foundation is written from Apple's public
API documentation and the published descriptions of the property list
formats; it uses no code from Apple's, GNUstep's or Darling's Foundation. Nothing in Ferry comes from
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
```

`make check` builds every program in `tests/` this way, in both relocation
formats, runs it through Ferry and compares the output. It needs `clang`,
`lld` and `llvm` (for `llvm-nm`).

## Building and packaging

```
make                       # builds ./ferry, the SDK's library descriptions and Foundation
                           # (Foundation needs clang, lld and llvm, as the tests do)
make check                 # runs the tests
./packaging/build-deb.sh   # builds freemac-ferry_VERSION_amd64.deb
```

Ferry is GPL-3.0-or-later, like the rest of freemac.
