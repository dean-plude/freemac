# Ferry: running Mac GUI apps

This file is the working notebook for teaching Ferry to run windowed Mac apps
(apps built with AppKit). It says what the plan is, what is done, what isn't,
and where to pick up. Any session continuing this work should read it first,
then `ferry/README.md`.

Ferry today runs command-line programs for Intel Macs: a Mach-O loader
(`ferry/src/loader.c`), a libSystem layer that converts Mac C library calls
to Linux ones, and an SDK (`ferry/sdk`) that builds Mac test programs on
Linux with clang and lld. GUI apps need four more layers, built in order:

| Milestone | Layer | Status |
| --- | --- | --- |
| M1 | Objective-C runtime (libobjc) and blocks | **done**, merged (#25) |
| M2 | Foundation core + CoreFoundation basics | **done**, merged (#28) |
| M3 | Drawing: Core Graphics subset, Core Text basics (Cairo, Pango/HarfBuzz) | **done**, merged (#33) |
| M4 | AppKit minimum on Wayland (through GTK 3) | **done**, merged (#35) |
| M5 | Nibs (compiled .nib) | **done**, merged (#37) |
| M6 | Real apps, with a compatibility table in `docs/ferry-compat.md` | **done**, merged (#136) |
| M7 | What the apps needed first (`NSImage`, exceptions, window and view controllers), then polish: Dock icons, Open/Save panels, clipboard, drag and drop, scaling | **done**, merged (#171) |
| After M7 | More apps, and a graphical installer: Ferry's Installer, scroll and text views, key-value observing, Carbon answers | **in review** (see "More apps, and the Installer" below) |

## Ground rules

- **Clean room.** Everything is written from public material: the Mach-O
  format, the data structures clang itself emits for Objective-C (seen with
  LLVM's own `llvm-objdump --objc-meta-data` on programs we compile
  ourselves), clang's published documents (the Objective-C ARC specification
  `AutomaticReferenceCounting.rst` and the block ABI `Block-ABI-Apple.rst`),
  Apple's public API documentation for what each runtime call does, and our
  own tests. No Apple binary, framework or header is read, disassembled or
  copied. Apple's objc4 source (APSL) is not used; neither is GNUstep's or
  Darling's code.
- **No Apple files** in the repo or on the ISO: no frameworks, fonts, icons or
  system binaries.
- **Stay in `ferry/`** (and this file). The desktop, theme and apps belong to
  other work.
- Each milestone keeps `make check` green and adds tests.

## M1: the Objective-C runtime

### What a Mac program expects

A program compiled from Objective-C for an Intel Mac (`clang -target
x86_64-apple-macos11`) links against `/usr/lib/libobjc.A.dylib` and expects:

- **Message sending**: `objc_msgSend`, `objc_msgSendSuper2`, their `_stret`
  variants (methods returning large structs, where the result address comes
  first), `objc_msgSend_fpret` (`long double` results), and the
  `objc_alloc`, `objc_alloc_init`, `objc_opt_*` shortcuts newer compilers
  emit.
- **Metadata in the binary**, in `__DATA` sections named `__objc_*`:
  - `__objc_classlist` / `__objc_nlclslist`: the classes the image defines
    (and those with `+load`). Each class is a 5-word structure (isa,
    superclass, cache, vtable, data) whose data points at a read-only
    description: flags, instance start and size, name, method list, protocol
    list, ivar list, property list.
  - `__objc_catlist` / `__objc_nlcatlist`: categories, which add methods,
    protocols and properties to existing classes.
  - `__objc_selrefs`: references to selector names; the runtime makes every
    selector with the same name the same pointer.
  - `__objc_classrefs`, `__objc_superrefs`: class references (already right
    after binding).
  - `__objc_protolist`, `__objc_protorefs`: protocols, uniqued by name.
  - `__objc_ivar`: one offset variable per instance variable. The runtime
    moves ivars down when a superclass turned out bigger than the compiler
    assumed ("non-fragile ivars").
  - `__objc_imageinfo`: version and flags.
- **Memory management**: `retain`/`release`/`autorelease` on `NSObject`,
  autorelease pools (`objc_autoreleasePoolPush`/`Pop`), and the ARC entry
  points (`objc_retain`, `objc_release`, `objc_storeStrong`,
  `objc_autoreleaseReturnValue`, `objc_retainAutoreleasedReturnValue`, weak
  references `objc_initWeak`/`objc_storeWeak`/`objc_loadWeakRetained`/...).
- **The root class `NSObject`**, which on a Mac lives in libobjc.
- **Properties**: `objc_getProperty`, `objc_setProperty*`, `objc_copyStruct`.
- **`@synchronized`**: `objc_sync_enter`/`objc_sync_exit`.
- **Blocks** (from libSystem): `_Block_copy`, `_Block_release`,
  `_Block_object_assign`, `_Block_object_dispose` and the block classes
  `_NSConcreteStackBlock`, `_NSConcreteGlobalBlock`, `_NSConcreteMallocBlock`.
- **The public runtime API** in `<objc/runtime.h>`: `objc_getClass`,
  `class_addMethod`, `class_copyMethodList`, `method_exchangeImplementations`,
  `objc_setAssociatedObject`, `objc_allocateClassPair` and so on, which real
  apps use for introspection and swizzling.

### Design

- **Where it lives.** `ferry/src/objc/`, compiled into the `ferry` binary
  like the libSystem layer. Imports from `libobjc.A.dylib` are looked up in a
  new symbol table; the SDK gets a generated `libobjc.tbd` next to
  `libSystem.tbd`, plus our own `<objc/*.h>` and `<Block.h>` headers.
- **Loading.** After the loader applies fixups it hands every `__objc_*`
  section to the runtime, which uniques selectors, realizes classes
  (superclass first, sliding ivars when needed), attaches categories and
  uniques protocols, all before the segments are made read-only. `+load`
  methods run after that, classes before categories, superclasses first.
- **Classes.** The binary's class structures are used as they are; the
  `cache` word (which the compiler points at `_objc_empty_cache`) is set to
  the runtime's own per-class record: method cache, method lists (copied into
  one normalized form so compiled lists, relative "small" method lists,
  categories and `class_addMethod` all look alike), ivars, properties,
  protocols and flags.
- **Dispatch.** `objc_msgSend` is a short x86-64 assembly routine: nil
  receivers return zero; otherwise it looks the selector up in the class's
  cache and jumps to the method. A cache miss saves the argument registers
  and calls the C slow path, which runs `+initialize` the first time a class
  is used, searches the method lists up the superclass chain, tries
  `+resolveInstanceMethod:`/`+resolveClassMethod:`, and fills the cache. An
  unknown selector goes to the forwarding path (`forwardingTargetForSelector:`,
  then `doesNotRecognizeSelector:`, which stops the program with the usual
  message). `forwardInvocation:` needs NSInvocation and waits for M2.
- **Objects and reference counts.** Each object allocated by the runtime has
  a 16-byte header in front of it holding the extra retain count and flags
  (deallocating, has weak references, has associated objects). The object
  pointer itself starts with `isa`, as on a Mac. Classes that override
  retain/release (and block and protocol objects, which are static) are sent
  real messages instead.
- **Weak references, associated objects and `@synchronized`** use side
  tables keyed by object address.
- **Autorelease pools** are a per-thread stack of objects with boundary
  markers.
- **Blocks** follow clang's published block ABI. Heap blocks are runtime
  objects (class `__NSMallocBlock__`), so `objc_retain`/`release` work on
  them; `__block` variables move to the heap with a small reference count.
- **Thread safety.** Ferry can't run threaded programs yet, but the runtime
  already takes a lock around its tables and uses atomic reference counts,
  so it won't need rewriting when threads arrive.

### Tests (all built with `ferry-cc`, run by `make check`)

- `objc_basic.m`: classes, inheritance, `super`, class methods, ivars and
  synthesized properties, categories, protocols, `+load` and `+initialize`
  order, struct and floating-point returns, variadic methods, introspection,
  dynamic classes, swizzling, associated objects, method resolution and
  forwarding. Built with both relocation formats.
- `objc_arc.m`: ARC: dealloc timing, weak references zeroing, autorelease
  pools, strong and copy properties, blocks capturing objects, `__block`,
  `imp_implementationWithBlock`, `@synchronized`.
- `objc_mrr.m`: manual retain/release and `retainCount`.
- `blocks.c`: blocks from plain C (libSystem only).
- `objc_unknown.m`: an unknown selector stops the program with the Mac's
  message and status.

### M1 report (2026-11-20)

**What works now.** Objective-C command-line programs built for an Intel Mac
run on Ferry, using Ferry's own runtime and `NSObject`. `make check` runs
18 tests (10 before M1), all passing. The new ones:

| Test | Proves |
| --- | --- |
| `blocks` | blocks in plain C: global, stack and heap blocks, `Block_copy`/`Block_release`, `__block` variables shared between copies, nested blocks |
| `objc_basic` (also built with chained fixups and at `-O0`) | classes, inheritance and `super`, class methods, ivars, properties, categories (including `+load` in a category), protocols, `+load`/`+initialize` order, struct, `float`, `long double` and variadic methods, nil receivers, `objc_msgSend`/`objc_msgSendSuper` by hand, introspection (ivars, properties, method types), classes made at run time, swizzling, associated objects, `+resolveInstanceMethod:`, `forwardingTargetForSelector:`, manual retain/release/autorelease |
| `objc_arc` (also with chained fixups) | ARC: objects freed the moment their last strong reference goes (including those returned from convenience constructors), weak references turning nil, `__autoreleasing` and `@autoreleasepool`, `copy` and atomic properties, blocks capturing objects and `__block` objects, `__weak` captured in blocks, `imp_implementationWithBlock`, nested `@synchronized` |
| `objc_unknown` | an unrecognized selector stops the program with the Mac's message (`-[Quiet speak]: unrecognized selector sent to instance ...`) and SIGABRT |

**Design notes for the next session.**

- The runtime is in `ferry/src/objc/`: `runtime.c` (selectors, classes,
  image loading, lookup, `<objc/runtime.h>`), `nsobject.c` (`NSObject`,
  reference counts, ARC, weak, associated objects, `@synchronized`,
  properties), `blocks.c`, `msgsend.S` (dispatch), `symbols.c` (what
  `libobjc.A.dylib` exports). The SDK headers are in
  `ferry/sdk/include/objc/` and `Block.h`; `sdk/gen-tbd.sh` writes
  `libobjc.tbd` from `ferry --list-symbols=libobjc`.
- A class's `cache` word points at the method cache's buckets and its
  `vtable` word holds the cache mask; the bucket array is preceded by a
  header pointing at the runtime's record for the class (`class_rt()`).
- Built-in classes (`NSObject`, `Protocol`, the block classes) are made in C
  with `ferry_objc_make_class()`. Foundation classes in M2 should instead be
  written in Objective-C and built as a Mach-O dylib (see the M2 sketch).
- ARC's return-value handshake: `objc_autoreleaseReturnValue` looks at the
  caller's code at the return address; if it is `mov %rax,%rdi` followed by
  a call (direct, through a stub, or through a pointer) to
  `objc_retainAutoreleasedReturnValue`/`objc_claimAutoreleasedReturnValue`/
  `objc_unsafeClaimAutoreleasedReturnValue`, the object is handed over
  without the autorelease pool. Unoptimized (`-O0`) methods don't tail-call
  the runtime, so their results still go through the pool.

**What isn't done yet (and why).**

- Objective-C exceptions: needs an unwinder for Mach-O (`__unwind_info`,
  `__eh_frame`). Throwing prints the exception's class and stops.
- `forwardInvocation:`: needs `NSInvocation` and `NSMethodSignature` (M2).
  The program stops with a message naming the selector.
- "Small" (relative) method lists, which newer Apple linkers emit, are
  implemented but untested: LLVM 18's lld can't produce them. They need a
  test once a binary that uses them is available.
- Moving ivars for a superclass that grew ("non-fragile ivars") is
  implemented but not exercised: `NSObject` is the only superclass outside
  the program so far, and its size matches what the compiler assumes.
- Threads: Ferry has no pthreads yet. The runtime takes a lock around its
  tables and uses atomic reference counts, but method-cache growth isn't
  safe against a message being sent on another thread at the same moment.
  That needs revisiting with threads.
- `@"..."` string literals: Foundation's constant string class (M2).

**What's next.** M2, Foundation core. First the loader learns Mach-O
dylibs, then Foundation is written in Objective-C as Ferry's own
`Foundation.framework`.

### Not in M1

- **Objective-C exceptions** (`@try`/`@throw`) need a Mach-O stack unwinder.
  `objc_exception_throw` prints the exception and stops the program;
  `@try` blocks compile and run when nothing is thrown.
- **`forwardInvocation:`** (needs NSInvocation, M2).
- **String literals `@"..."`** need Foundation's constant string class (M2).
- **Threads**: Ferry itself has no pthreads yet.

## M2: Foundation and CoreFoundation basics

### Design

- **Ferry loads Mac libraries now.** The loader reads `MH_DYLIB` files,
  their export tries (including re-exports), `LC_LOAD_DYLIB` dependencies
  with two-level namespace ordinals, `LC_RPATH` and `@rpath`,
  `@executable_path` and `@loader_path`, and runs each library's
  initializers (its Objective-C `+load` methods, then its C constructors)
  after the libraries it depends on. `libSystem` and `libobjc` stay built
  into the `ferry` binary.
- **Frameworks.** A program asking for
  `/System/Library/Frameworks/X.framework/...` gets Ferry's own
  `X.framework/X`, searched in `$FERRY_FRAMEWORKS`, then `frameworks/` next
  to the `ferry` binary, then `/usr/lib/ferry/frameworks`. CoreFoundation is
  an alias for Foundation's file (one library serves both, so every CF
  object is the Foundation object and toll-free bridging is automatic).
- **Foundation is Objective-C**, in `ferry/foundation/`, built by `make` with
  `ferry-cc -dynamiclib` into `ferry/frameworks/Foundation.framework/Foundation`
  (install name `/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`).
  It uses manual reference counting, like Apple's frameworks, and runs on
  the M1 runtime. For linking, `CoreFoundation.framework` holds a
  generated `CoreFoundation.tbd` (`sdk/gen-cf-tbd.sh`), so C programs record
  CoreFoundation's real Mac name, which exercises the loader's alias.
- **Class clusters as on a Mac.** `NSString`, `NSArray`, `NSDictionary`,
  `NSSet`, `NSNumber`, `NSData`, `NSDate`, `NSValue` are abstract; allocating
  one gives a private concrete class (`NSConcreteString`, `FArray`,
  `FMutableArray`, `FDictionary`, ...). Subclasses of the public classes work
  through the primitive methods.
- **Strings** hold UTF-16 code units, so lengths and indexes match a Mac's.
  `@"..."` literals are clang's constant strings (`{isa, flags, chars,
  length}`), whose class `___CFConstantStringClassReference` is an alias of
  Ferry's `__NSCFConstantString`. Formatting (`%@`, the C conversions,
  widths, `*`, positional `%1$@`) is Ferry's own (`FFormat`).
- **Empty literals.** clang refers to `__NSArray0__` and `__NSDictionary0__`
  for `@[]` and `@{}`; Foundation exports them.
- **Exceptions.** `-[NSException raise]` prints the Mac's message (`***
  Terminating app due to uncaught exception 'NSRangeException', reason:
  '...'`) and ends the program (still no unwinder; see below).
- **Run loop.** One run loop on the main thread, waiting in `poll()`, with
  timers, a queue of blocks (`performBlock:`, `CFRunLoopPerformBlock`) and
  file-descriptor sources. `FerryRunLoopAddDescriptor(fd, callback, ctx)` is
  the hook AppKit (M4) will use for its Wayland connection.
- **Where things go on freemac.** `NSUserDefaults` writes through to
  `~/.config/ferry/preferences/<bundle id or program name>.plist` (XML,
  honouring `XDG_CONFIG_HOME`); `-Key value` on the command line overrides a
  default, as on a Mac. Documents is `~/Documents`, Application Support and
  Library are `~/.local/share` (`XDG_DATA_HOME`), Caches is `~/.cache`
  (`XDG_CACHE_HOME`), Applications is `~/Applications`, Movies is
  `~/Videos`. Only the user domain has folders.
- **Bundles.** A program at `X.app/Contents/MacOS/X` gets `X.app` as its main
  bundle, reads `Contents/Info.plist` and finds resources in
  `Contents/Resources`, then in `<language>.lproj` folders, picking the
  language from `LC_ALL`/`LC_MESSAGES`/`LANG`, then English, then `Base`.
  `.strings` files (UTF-8 or UTF-16) are read with the OpenStep parser.

### M2 report (2026-11-20)

**What works now.** A Mac program written against Foundation (manual
reference counting or ARC) runs on Ferry with Ferry's own Foundation,
including programs that live in an `.app` bundle. `make check` runs 31
tests (20 before M2's Foundation part, 18 before M2), all passing. The new
ones:

| Test | Proves |
| --- | --- |
| `dylib_classic`, `dylib_chained` | a program using its own Mac library, found through `@rpath`, in both relocation formats (classes, categories and C calls across the library boundary, `+load` and constructors in order) |
| `foundation_strings` | `@"..."` literals, `stringWithFormat:` (flags, widths, `*`, `%@`, positional arguments), comparing and searching, numeric compare, substrings, case, trimming, padding, splitting and joining, number parsing, UTF-16 lengths for accented letters and emoji, paths, `NSMutableString` editing, copies, line enumeration, `NSData` round trip |
| `foundation_collections` (also with chained fixups) | `NSNumber` (types, equality across int/float, shortest float text, shared booleans), `NSValue`, `NSArray` (literals, stable sorting by selector and block, filtering, enumerators, fast enumeration, blocks), `NSMutableArray`, `NSDictionary` (literal, description with sorted keys and nesting, 100-key growth and removal, copied keys, sorting by value), `NSSet`, `NSData` and base64, `NSNull`, key-value coding, and objects freed when collections and pools release them |
| `foundation_system` | property lists: XML out and back, binary out and back (mutable containers), OpenStep text and `.strings`, a bad plist giving error 3840; `NSFileManager` (nested folders, attributes, copy, move, listing, subpaths, removal, the Mac's error messages); search paths; `NSUserDefaults` (registered defaults, typed setters, the file on disk, reloading, a command-line override); `NSURL` (parts, relative resolution, file URLs with escaping); `NSDate`; `NSError`; `NSProcessInfo` |
| `foundation_runloop` | `NSRunLoop` (returns at once with nothing to do, runs until its timers are done), repeating and one-shot timers with targets and blocks, `performSelector:withObject:afterDelay:`, queued blocks, a pipe as an input source, `CFRunLoopRunInMode`, `CFRunLoopStop`, notifications (selector and block observers, object filtering, removal), and CF calls on Foundation objects and back |
| `foundation_corefoundation` | CoreFoundation from plain C, linked under CoreFoundation's own Mac name |
| `foundation_arc` | Foundation from ARC code: collections owning objects, weak references clearing when the last owner goes |
| `foundation_bundle` (C and French) | a program inside `Hello.app`: bundle path, identifier, Info.plist values, resources, `NSLocalizedString` from `en.lproj` and `fr.lproj`, `CFBundle`, preferences named after the bundle identifier |
| `foundation_exception` (+ message check) | reading past the end of an array stops the program with the Mac's "Terminating app due to uncaught exception 'NSRangeException'" message |

The expected outputs were written from Apple's documented behaviour and
checked by hand; they were not captured on a Mac (we have none), so small
differences in wording from real macOS output are possible.

**Design notes for the next session.**

- Sources: `foundation/NSString.m` (strings, character sets, formatting),
  `NSValue.m` (numbers), `NSArray.m`, `NSDictionary.m` (dictionaries and
  sets on one hash table), `NSData.m`, `NSDate.m` (dates and URLs),
  `NSObject.m` (NSObject additions, errors, exceptions, `NSLog`, functions,
  descriptions), `NSPropertyList.m`, `NSSystem.m` (process info, bundles,
  defaults, files), `NSRunLoop.m` (run loop, timers, notifications),
  `CoreFoundation.m`. Shared helpers are in `FInternal.h`.
- Headers: `sdk/include/Foundation/Foundation.h` declares everything (the
  per-class headers just include it) and `sdk/include/CoreFoundation/`.
  Everything declared there is implemented; keep it that way.
- `ferry-cc` passes `-F` for Ferry's frameworks and adds `-lobjc` when a
  program links a framework (on a Mac, Foundation re-exports libobjc; lld
  can't follow that re-export to a library outside a Mac SDK).
- Foundation's own singletons and the run loop have no locks: Ferry still
  has no threads.

**What isn't done yet (and why).**

- Exceptions still can't be caught (`@try`/`@catch`): that needs a Mach-O
  unwinder. An uncaught exception prints the Mac's message and stops.
- Not written yet: `NSInvocation`/`NSMethodSignature` (so no
  `forwardInvocation:`), `NSThread`, `NSOperationQueue`, `NSTask`,
  `NSDateFormatter`, `NSCalendar`, `NSLocale`, `NSNumberFormatter`,
  `NSRegularExpression`, `NSScanner`, `NSPredicate`, `NSSortDescriptor`,
  `NSIndexSet`, `NSUUID`, `NSCache`, `NSJSONSerialization`, keyed archiving
  (`NSCoding`, needed for nibs in M5) and key-value observing
  (`NSAttributedString` came with M3). M4 to M6 will add what real apps turn out to need.
- Simplifications: upper/lower case mapping covers ASCII and Latin-1 only;
  `localizedCompare:` is plain `compare:`; dates print in UTC;
  `bundleForClass:` returns the main bundle; only the user domain has
  search paths; there's no global defaults domain; notification queues are
  ignored (observers run at once); there's one run loop.
- The private class names differ from Apple's (`FArray` instead of
  `__NSArrayI`), so exception messages name Ferry's classes.
- A pre-existing difference in Ferry's C library layer: `printf("%p", NULL)`
  prints `(nil)` (Linux) instead of `0x0`. Foundation's own formatting
  prints `0x0`.

**What's next.** M3, drawing: a Core Graphics subset and Core Text basics on
Cairo, Pango/HarfBuzz and FreeType, using freemac's system font.

## M3: drawing (Core Graphics and Core Text)

### Design

- **The bridge to this system's libraries.** Ferry's frameworks are Mac code,
  but the System V calling convention is the same on both systems, so a Mac
  library can call a Linux one directly. Ferry's own drawing framework
  imports Cairo, Pango and HarfBuzz calls from a library name that exists
  only inside Ferry, `/usr/lib/ferry/libFerryHost.dylib`. The loader treats
  it as built in (like libSystem) and resolves those names with `dlopen` and
  `dlsym` on `libcairo.so.2`, `libpangocairo-1.0.so.0`, `libpango-1.0.so.0`,
  `libgobject-2.0.so.0`, `libglib-2.0.so.0` and `libharfbuzz.so.0`
  (`src/host.c`). Only the calls declared in `graphics/host.h` are allowed;
  the list is generated from that header at build time, and so is the link
  stub `graphics/build/libFerryHost.tbd`. The libraries are opened the first
  time a program needs one, so programs that don't draw never load them,
  and the `ferry` binary doesn't link against them (a test checks both).
  The declarations in `host.h` are written from each library's published API
  documentation, because a Mac build can't include Linux headers. Building
  needs no `-dev` packages; running a drawing program needs the libraries.
- **One file, three frameworks.** `ferry/graphics/` builds
  `frameworks/CoreGraphics.framework/CoreGraphics` (install name
  `/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics`).
  CoreText and ApplicationServices are aliases for that file in the loader,
  like CoreFoundation for Foundation, with generated `.tbd` link stubs
  (`sdk/gen-alias-tbd.sh`) so programs record the real Mac names.
- **CG objects are Objective-C objects** (`GColor`, `GPath`, `GContext`,
  `GFont`, `GLine`, ...), so `CFRetain`, `CFRelease` and `CFEqual` work on
  them and they can sit in `NSArray`s.
- **Coordinates.** A CG context's origin is the bottom left with y going up;
  Cairo's is the top left with y going down. Each context keeps a base
  transform (`[1 0 0 -1 0 height]`) under the user's CTM, and
  `CGContextGetCTM` reports the CTM without it, as on a Mac (identity for a
  new bitmap context). A bitmap's first row in memory is its top, as on a
  Mac. Arcs, ellipses and rounded rectangles become Bézier curves when they
  are added, so `CGPathApply` reports curves as it does on a Mac.
- **Bitmap layouts.** Cairo's own layout (32-bit premultiplied ARGB in host
  order, which is `kCGImageAlphaPremultipliedFirst |
  kCGBitmapByteOrder32Little` on Intel, the same with the alpha byte
  skipped, and 8-bit alpha only) is drawn into the caller's memory directly.
  Every other supported layout (RGBA, i.e. `kCGImageAlphaPremultipliedLast`,
  the most common in Mac code; big-endian ARGB; 8-bit grey) is drawn in a
  Cairo copy and converted in and out around each drawing call. Supported:
  8 bits per component, RGB with alpha or a skipped byte, grey, alpha only.
  16-bit, float and CMYK bitmaps give `NULL` with the Mac's "unsupported
  parameter combination" message.
- **Colour.** Everything is drawn as sRGB with no colour management: a
  colour's components are used as sRGB values whatever space they are in
  (grey and CMYK are converted simply).
- **Text.** A `CTFont` is a Pango font loaded at an absolute size in points
  in a Pango context at 72 dpi with metric hinting off, so one point is one
  unit of user space and widths scale exactly with size. Metrics, glyphs,
  advances and glyph boxes come from HarfBuzz in font units. Mac font names
  are matched to the system's fonts: Helvetica, Helvetica Neue, Arial, SF
  (`.SFNS...`, `.AppleSystemUIFont`), Lucida Grande, Geneva and others ask
  for `sans-serif`, which freemac's fontconfig maps to Inter; Menlo, Monaco,
  Courier and SF Mono ask for `monospace`; Times, Georgia and Palatino for
  `serif`. Weights and italics are read from the name (`Helvetica-Bold`,
  `HelveticaNeue-LightItalic`). The font then reports its real name
  (`Inter`, `Inter-Bold`), never the Mac name it was asked for.
  `CTFontCreateUIFontForLanguage` gives the Mac's documented default sizes
  (13 pt for the system font).
- **Lines and frames** are Pango layouts built from the attributed string
  (font, colour, colour from the context, kerning, underline), with a map
  between the string's UTF-16 indexes and Pango's UTF-8 byte offsets.
  `CTLineDraw` and `CTFrameDraw` draw at the text position (the text
  matrix's translation, as on a Mac), flipping y locally so glyphs stand
  upright. Pango shapes with HarfBuzz and falls back to other installed
  fonts for missing characters (emoji, for example), which Core Text also
  does. Frames lay lines out from the top of the rectangle down and stop at
  the last line that fits.
- **NSAttributedString** joined Foundation (`foundation/NSAttributedString.m`):
  a string plus a list of runs (length and attribute dictionary), merged when
  neighbours are equal, with the Mac's rules for what new text inherits.
  `CFAttributedString` calls work on the same objects.

### M3 report (2026-11-20)

**What works now.** A Mac program can draw with Core Graphics and Core
Text into bitmaps: shapes, paths, colours, transforms, clipping, gradients,
images (including PNG files), and text in the system's fonts, laid out in
lines and wrapped in rectangles. `make check` runs 38 tests (31 before M3),
all passing. The new ones:

| Test | Proves |
| --- | --- |
| `foundation_attributed` | `NSAttributedString` and `NSMutableAttributedString`: adding, setting and removing attributes, replacing text (what the new text inherits), appending, deleting, effective ranges, substrings, copies, enumeration forwards and in reverse, and `CFAttributedString` from C |
| `graphics_geometry` (also as `graphics_appservices`, linked under ApplicationServices' name) | `CGRect` functions (standardizing, union, intersection, inset, integral, divide, containment, null and infinite rectangles), affine transforms (make, translate, scale, rotate, invert, concatenate, apply to points and rectangles), dictionary forms |
| `graphics_drawing` (also with chained fixups) | RGBA bitmap contexts checked pixel by pixel: filled rectangles and ellipses where y-up puts them, stroked lines, colours with alpha and a global alpha, save and restore, translate, scale and rotate, `CGContextGetCTM`, clipping and its bounding box, even-odd fill, clearing, linear gradients (rising, half-way grey in the middle, the before/after options) and radial ones, an image from one context drawn into another the right way up and cropped, a PNG decoded with its colours and transparency, the BGRA, xRGB, grey and alpha-only memory layouts, `NULL` for an unsupported layout, path elements (lines, quadratic curves, arcs as curves), bounding boxes, containment, `CGPathIsRect`, transformed copies, rounded rectangles, `CGContextAddArcToPoint`, copying the context's path, and colours |
| `graphics_text` | Helvetica and the system font are the same family, Menlo and SF Mono the same monospace one; default sizes; bold and monospace traits; a bold copy; metrics that double with the size; glyphs and advances; glyph boxes and outlines on the baseline; a line's width, ascent, offsets and hit testing; drawn text landing inside its image bounds above the baseline and nothing below the descent; red text drawn red; truncation; a framesetter's suggested size; a frame's lines going down the rectangle in order, starting at the top, with all ink inside it; a short frame showing one line; centred paragraphs |
| `Cairo loaded only when drawing` | a Foundation-only program doesn't load Cairo; a drawing program does |

Text tests check properties that hold for any font (sizes scale, ink lands
where it should, Mac names map to the right kind of font) rather than exact
pixel widths, so they pass with whatever fonts a machine has. They were
also checked by eye: text stands upright on its baseline, wraps inside its
frame and starts at the top; arcs go the documented way round.

**Design notes for the next session.**

- Sources: `graphics/GInternal.h` (shared types), `host.h` (the Linux calls),
  `CGGeometry.m`, `CGColor.m`, `CGPath.m` (paths and the shape builders
  shared with contexts), `CGImage.m` (pixel layouts, data providers, images,
  gradients), `CGContext.m`, `CoreText.m`. Public headers are in
  `sdk/include/CoreGraphics/`, `CoreText/` and `ApplicationServices/`.
- For M4: `GContextCreateWithSurface(cairo_surface_t *, height)` (exported
  from CoreGraphics) makes a context on any Cairo surface; AppKit will use
  it for window contents. AppKit's `NSFont` and `NSColor` can sit on
  `GFont` and `GColor`: Core Text already accepts the `NSFont` key (it is the
  same string as `kCTFontAttributeName`) and any colour object that answers
  `-CGColor`, under `NSColor` or `CTForegroundColor`.
- Adding a Linux call means declaring it in `graphics/host.h`; the allow
  list and link stub follow from that.
- Programs link Core Text, Core Graphics and CoreFoundation separately, as
  on a Mac (none of them re-exports the others).
- `__sincos_stret` and `__sincosf_stret` (clang on a Mac turns `sin(x)` and
  `cos(x)` of the same x into one call) were added to Ferry's libSystem.

**What isn't done yet (and why).**

- Not written: shadows (`CGContextSetShadow` warns once and draws without
  one), transparency layers, patterns, masks (`CGImageMaskCreate`,
  `CGContextClipToMask`), `CGContextReplacePathWithStrokedPath`, PDF
  contexts and documents, `CGFont` and the old CG text calls
  (`CGContextShowText`...), `CTRun` and `CTLineGetGlyphRuns`, font
  descriptors and collections, font name lists, vertical text, and
  ImageIO (so only PNG images can be read, through
  `CGImageCreateWithPNGDataProvider`; no JPEG, and nothing can be written).
- Simplifications: no colour management (see above); a radial gradient
  drawn with only one of the before/after options extends both ends;
  `kCGBlendModePlusDarker` draws as normal; justified text is left-aligned;
  a text frame that isn't a rectangle uses its bounding box; truncation
  always uses "…" (a custom token is ignored); `CTFontGetBoundingBox` is an
  estimate (HarfBuzz doesn't expose the font's own box); clip text drawing
  modes draw without clipping; line spacing in frames is Pango's (ascent
  plus descent), which can be a little tighter than a Mac's.
- Bitmaps in a layout Cairo doesn't have are converted around every
  drawing call, which is slow for big bitmaps; drawing in
  `kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little` avoids it.
- Fonts: the font a Mac name maps to depends on what the machine has; on
  freemac that is Inter, DejaVu Sans Mono and DejaVu Serif (or Noto, if
  installed). The real Mac fonts are never used or shipped.
- Still no threads, so the shared Pango context and caches have no locks.

**What's next.** M4, the AppKit minimum on Wayland: `NSApplication`,
`NSWindow`, `NSView` with `drawRect:` on the M3 contexts, events, `NSFont`
and `NSColor`, a few controls. The first M4 task is to choose how windows
reach Wayland (directly with libwayland and xdg-shell, or through GTK) and
record the choice and the reason here.

## M4: the AppKit minimum

### Decision: windows go through GTK 3, not raw libwayland

Ferry's AppKit opens its windows with this system's GTK 3 (`libgtk-3.so.0`,
`libgdk-3.so.0`), called directly like Cairo and Pango, and draws every
window's contents itself with the M3 Core Graphics. GTK is used only as a
window and input layer: no GTK widgets appear inside a Mac window. Reasons:

- freemac already ships GTK 3 and runs Wayfire, which prefers server-side
  decorations, so a GTK window gets the same title bar, borders and
  resizing as every other freemac app with no work from Ferry.
- Raw libwayland plus xdg-shell would mean writing, and keeping working,
  things GTK already does well: shared-memory buffers, frame callbacks,
  output scale (HiDPI), cursors, keyboard maps (xkbcommon), input methods,
  clipboard, drag and drop and file choosers. The last few are M7 work,
  and GTK has them ready.
- GTK draws with Cairo, which is what M3 already uses, so a window's
  backing image goes to the screen with no conversion.
- It also works on X11 (with `DISPLAY`) for free, which helps testing.

The cost is one more library (about 6 MB, already on freemac) and GTK's
own main loop, which Ferry drives from its run loop (below) rather than
handing control to `gtk_main`.

### Design

- Sources are in `ferry/appkit/` (Objective-C, built into
  `frameworks/AppKit.framework/AppKit`). `Cocoa` is an alias for AppKit in
  the loader, and `Cocoa.tbd` lists AppKit, Foundation and Core Graphics, so
  `-framework Cocoa` links like on a Mac. Headers:
  `sdk/include/AppKit/AppKit.h` and `sdk/include/Cocoa/Cocoa.h`.
- **Host calls.** `src/host.c` now opens two groups of Linux libraries on
  first use: "drawing" (Cairo, Pango, HarfBuzz, GLib) and "windows" (GTK and
  GDK, for `gtk_`/`gdk_` names, declared in `appkit/gtk.h`). A drawing-only
  program never loads GTK (a test checks this). If a library is missing,
  Ferry says which one.
- **Windows.** Each `NSWindow` keeps a backing image (a Cairo image surface
  at the screen's scale) and a Core Graphics context on it
  (`GContextCreateWithSurface`). Views draw into it with `drawRect:`; a
  `GtkDrawingArea` copies it to the screen. The window frame equals its
  content rectangle, because the compositor draws the title bar. Wayland
  doesn't let apps place windows, so `setFrameOrigin:` is remembered but
  has no effect on screen.
- **No display.** If neither `WAYLAND_DISPLAY` nor `DISPLAY` is set (or GTK
  can't connect), AppKit still works off screen: windows draw into their
  backing images, events can be posted, `NSScreen` reports 1440x900. The
  off-screen tests rely on this.
- **Run loop.** M2's `NSRunLoop` gained a poll hook
  (`FerryRunLoopSetPollHook`), and AppKit installs one that runs GLib's main
  context (prepare, query, poll, check, dispatch) inside the run loop's own
  `poll`. So timers, `performSelector:afterDelay:`, run-loop sources and GTK
  events all wake the same loop, and `[NSApp run]` is the Mac's loop, not
  `gtk_main`.
- **Events.** GTK signals become `NSEvent`s in the application's queue;
  `nextEventMatchingMask:` redraws windows that need it before waiting.
  `NSWindow` routes mouse events to the view under the pointer (and keeps
  the view a drag started in), key events to the first responder, and walks
  the responder chain. Clicks are counted by Ferry. Linux key codes map to
  the Mac's virtual key codes; arrows and function keys use the Mac's
  `NSUpArrowFunctionKey` range.
- **Modifier keys.** Alt is Option. Super is Command. Ctrl is also Command,
  because on freemac the Strata command key sends Ctrl to apps while the
  Command (Super) key is held, and Linux users expect Ctrl+C. Setting
  `FERRY_CONTROL_KEY=control` makes Ctrl the Mac's Control key instead.
- **Fonts and colours.** `NSFont` is a subclass of Core Text's font class,
  and Core Text creates `NSFont` objects when AppKit is loaded, so `CTFontRef`
  and `NSFont *` are the same object, as on a Mac. `NSParagraphStyle` is
  Core Text's paragraph style the same way. `NSColor` holds sRGB components
  and hands out a `CGColor`. Named system colours (`controlTextColor`,
  `controlAccentColor`...) are Ferry's own palette, not Apple's values.
- **Controls** are Ferry's own drawing (rounded rectangles, a blue default
  button, check boxes and radio buttons, a focus ring), not imitations of
  Apple artwork. There is no `NSCell`: `NSButton` and `NSTextField` draw and
  track themselves, without nested event loops.
- **Text fields** edit in place: typing, Backspace and Delete, arrows,
  Option-arrows by word, Command-arrows to the ends, Shift to select,
  Command-A, placeholder text, secure fields (bullets), and wrapping labels.
  Keys go through `interpretKeyEvents:` and the Mac's standard key bindings
  (`moveLeft:`, `deleteBackward:`, `insertNewline:`...), so a subclass can
  override the same methods it would on a Mac.
- **Keyboard navigation.** Tab and Shift-Tab move between key views (in
  reading order if the app set none); Return presses the default button
  and Escape the Cancel one. Menus aren't shown yet, but `NSMenu` and
  `NSMenuItem` exist, are validated, and their key equivalents work, so
  Command-Q, Command-W and an app's own shortcuts do what the app set up.
- **Geometry** (`NSRect`, `NSPoint`, `NSMakeRect`, `NSStringFromRect`...)
  moved into Foundation, where it is on a Mac, as typedefs of the CG
  structures; `NSValue` holds points, sizes, rectangles and edge insets.

### M4 report (2026-11-20)

**What works now.** A Mac program written in code (no nib) can open
windows on freemac's desktop, draw in them with `drawRect:`, and respond to
the mouse and keyboard: buttons (push, check box, radio groups, default
and Cancel buttons), editable and secure text fields, labels, custom views,
flipped views, autoresizing, key equivalents through `NSMenu`, the
responder chain, the window delegate (`windowShouldClose:`,
`windowWillClose:`, resize and focus notifications) and
`applicationShouldTerminateAfterLastWindowClosed:`. Windows follow the
screen's scale, so they are sharp on HiDPI. `make check` runs 41 tests (38
before M4), all passing. The new ones:

| Test | Proves |
| --- | --- |
| `appkit_views` (built with `-framework Cocoa`) and `appkit_views_appkit` (with AppKit, Foundation, Core Graphics and Core Text linked separately) | Off screen: `NSRect` functions and strings, `NSValue` geometry; view trees, frames and bounds, flipped and unflipped coordinate conversion, hit testing, autoresizing; `drawRect:` checked pixel by pixel through `cacheDisplayInRect:`; `NSBezierPath`, `NSColor`, `NSFont` (and that it is a `CTFont`), string drawing; buttons, check boxes and radio groups by posted mouse events; typing, selection, word movement and deletion in a text field; Tab and Shift-Tab; menu key equivalents with validation; the responder chain and `sendAction:to:from:`; `[NSApp run]` with a timer and an application event, `stop:`; closing a window |
| `appkit_window` | On a real Wayland display (a headless Weston started by the test): a window shows, is drawn, is resized and redrawn at the new size, closes through its delegate, and the app terminates after the last window closes. Skipped, with a message, if `weston` isn't installed |
| `Cairo loaded only when drawing` | now also checks that a drawing program doesn't load GTK |

It was also checked by eye under Weston at scale 1 and 2: a decorated
window with a text field (selection and focus ring), a blue default button,
a check box, radio buttons, a wrapping label and a flipped view, all drawn
where they should be.

**What isn't done yet (and why).**

- **Nibs.** `NSApplicationMain` starts the app but can't load
  `MainMenu.nib` yet; it says so. That is M5, so most real apps don't start
  yet.
- **Menus aren't shown.** There is no menu bar on screen (freemac's global
  menu is the desktop's business; M7 can export menus to it). Key
  equivalents work.
- Not written: `NSCell` and its subclasses, `NSImage` and `NSImageView`,
  `NSScrollView`, `NSTextView`, `NSTableView`, `NSStackView` and Auto
  Layout, alerts and sheets, Open/Save panels, the pasteboard and drag and
  drop, cursors, tracking areas, input methods (text fields take what
  the keyboard layout types, not composed text from an IME), and
  accessibility. A few stand-ins (`lockFocus`, `scrollPoint:`, the About
  panel) print a one-time "not supported yet" warning.
- Simplifications: a window redraws in full whenever any part needs it;
  `lockFocus` does nothing and `NSBezierPath setClip` adds to the clip
  rather than replacing it; window positions are
  ignored on Wayland; `runModalForWindow:` ignores events for other windows
  but the compositor doesn't know the window is modal; colours aren't managed (all
  sRGB).
- Under headless Weston GTK prints a harmless warning about the seat on
  stderr; the test ignores stderr.

**What's next.** M5: load compiled nib files (`NSKeyedArchiver` archives,
`.nib` bundles in an app's Resources), so that `NSApplicationMain` can
build `MainMenu.nib` and an app's windows from Interface Builder, with
outlets, actions and bindings of the simple kind.

## M5: nib files

### What a nib is

A compiled Mac nib (what Xcode makes from a `.xib`, in an app's
`Resources`, often inside `Base.lproj` or a language's `.lproj`) is a
keyed archive: a property list written by `NSKeyedArchiver`, with
`$archiver`, `$version`, `$top` and `$objects`, where objects refer to each
other by UID and each names its class. A nib is either one such file or a
folder holding `keyedobjects.nib`. Its top object, `IB.objectdata`, is an
`NSIBObjectData` listing the nib's root (File's Owner), every object with
its parent, the connections (outlets and actions) and the windows to show
at launch. Interface Builder stores stand-ins for some objects:
`NSCustomObject` (File's Owner, First Responder, the Application, the app's
own objects such as its delegate), `NSCustomView` and `NSClassSwapper`
(views and controls of the app's own classes) and `NSWindowTemplate`
(each window).

### Design

- **Foundation** gained `NSCoder`, `NSKeyedArchiver` and
  `NSKeyedUnarchiver` (`foundation/NSCoder.m`), with `NSCoding` for
  strings, arrays, dictionaries, sets, data, dates, numbers, `NSNull`,
  `NSURL`, `NSValue` (points, sizes, rectangles, ranges) and
  `NSAttributedString`. Secure decoding checks the allowed classes. An
  object of a class the program doesn't have is decoded as the nearest
  superclass the archive names, with a warning. The binary property-list
  writer learned UIDs. Archives are written in binary by default, or XML.
- **AppKit**: `appkit/NSNib.m` has the stand-ins, the connectors and
  `NSNib`; `appkit/NSCell.m` has `NSCell`, `NSActionCell`, `NSButtonCell`,
  `NSTextFieldCell` and `NSSecureTextFieldCell`. `NSView`, `NSControl`,
  `NSButton`, `NSTextField`, `NSMenu`, `NSMenuItem`, `NSColor` and `NSFont`
  can be decoded from a nib.
- **Cells.** Ferry's controls still draw and keep their state themselves
  (M4). A nib stores a control's settings in its cell, so a control loaded
  from a nib copies them from the cell, and keeps the cell for `-cell`.
- **Loading** (`-[NSNib instantiateWithOwner:topLevelObjects:]`):
  1. Decode the archive.
  2. Replace the stand-ins: File's Owner becomes the owner, First Responder
     becomes nil (an action with no target, which goes up the responder
     chain), the Application becomes `NSApp`, and anything else becomes a
     new object of its class made with `-init`. Custom views are made with
     `-initWithFrame:` and swapped classes with `-initWithCoder:`, as on a
     Mac. Each window template becomes its window as it is decoded.
  3. Make the connections. Outlets use the setter, or an instance variable
     of that name, as key-value coding does. An outlet the object doesn't
     have is reported rather than crashing. Actions set the target and
     action. "User Defined Runtime Attributes" are set too.
  4. Set the main menu and the Windows menu from the menus named
     `_NSMainMenu` and `_NSWindowsMenu`.
  5. Send `awakeFromNib` to every object the nib made, then to the owner.
  6. Show the windows marked visible at launch.
- `NSApplicationMain` loads the main nib named by `NSMainNibFile` in
  `Info.plist`, with `NSApp` as its owner, before running. `NSBundle`'s
  `loadNibNamed:owner:topLevelObjects:` (and the older
  `+loadNibNamed:owner:`) find a nib through the bundle's resources,
  including `Base.lproj` and the user's language.
- **Sources.** Keyed archives follow Apple's public documentation of
  `NSKeyedArchiver`/`NSKeyedUnarchiver` and of property lists. Nib loading
  follows Apple's documentation of `NSNib`, File's Owner, outlets, actions
  and `awakeFromNib`. The names of the stand-in classes and their keys
  (`NSWindowRect`, `NSvFlags`, `NSCellFlags`...) and the meaning of their
  flag bits follow descriptions of the format published by developers and
  by the GNUstep project. No code was copied from GNUstep, Darling or
  Apple, and no Apple nib is in the repository: the test nibs are written
  by our own script (`tests/appkit/make_nibs.py`) with Python's plistlib.

### M5 report (2026-11-20)

**What works now.** An app bundle whose `Info.plist` names a main nib
starts with `NSApplicationMain`. It gets its menu bar's menus (with their
keyboard shortcuts), its application delegate, its windows with their
views, buttons, check boxes, text fields, secure fields and labels, its own
custom view and control classes, and its outlets and actions connected,
then `awakeFromNib` and `applicationDidFinishLaunching:`. A program can
load more nibs with `NSNib` or `NSBundle`. Keyed archives also work on
their own (for apps that save documents or settings with
`NSKeyedArchiver`). `make check` runs 43 tests (41 before M5), all
passing. The new ones:

| Test | Proves |
| --- | --- |
| `foundation_archive` | Reading an archive made by another program (`archive.bplist`, written with Python's plistlib by `make_archive.py`): strings, numbers, booleans, arrays, sets, dates, data, mutable strings, rectangles, attributed strings with two runs, URLs, an object shared in two places, an object that refers to itself, a class the program doesn't have. Secure decoding refusing the wrong class. Junk data giving an error, not a crash. Writing and reading back a graph of objects (sharing and loops kept, mutable stays mutable, `classForKeyedArchiver`), the archive's layout, XML output and class renaming both ways |
| `appkit_nib` | `NibApp.app`, started by `NSApplicationMain` from `Base.lproj/MainMenu.nib`, with no display: the main menu, its submenus and shortcuts; the delegate connected to `NSApp`; ten outlets; the window's title, size, minimum size and style; each view's class, frame and autoresizing; the text field's text, placeholder, font and switches; the default button (Return), its target and action; a check box; a custom view made with `initWithFrame:` and given runtime attributes; a swapped button class; a wrapping label; the key-view loop; the custom view's colour drawn in the window; button actions, the check box, Command-H and Command-Q through the menu, which quits. Then `Panel.nib` (the folder form) loaded with its own owner: top-level objects, a panel not shown, `awakeFromNib` order, and warnings (not crashes) for a missing class, a missing outlet and a missing nib |

It was also checked by eye on a headless Weston display: the window from
the nib draws as it should (screenshot attached to the M5 report).

**What isn't done yet (and why).**

- **Not yet tried with nibs made by Xcode.** The test nibs are written by
  our own script, following the published descriptions of the format.
  Ferry can't use Apple's tools to make nibs here, and the rules say no
  Apple files in the repository. Real nibs carry many more keys and
  classes than the tests, and some flag bits (in `NSCellFlags`,
  `NSButtonFlags`) may be read wrong. A key or class Ferry doesn't know is
  skipped or warned about, so a real nib should load with some settings
  missing rather than crash, but that is unproven. Trying a few real
  apps' nibs is the first job of M6.
- **Not read:** storyboards (`NSMainStoryboardFile` warns), the newer
  `NIBArchive` container (says so), Cocoa bindings (skipped, with a
  warning), images in nibs (Ferry has no `NSImage` yet; image names are
  kept), toolbars, and classes Ferry doesn't have (`NSScrollView`,
  `NSTableView`, `NSTextView`, `NSPopUpButton`, `NSBox`, `NSImageView`,
  `NSStackView`, `NSTabView`, `NSSplitView`, `NSWindowController` and
  `NSViewController` and so on). Such objects are left out with a
  warning, which is what most real nibs will hit first.
- **Writing AppKit objects** to archives is partial: views, menus, colours,
  fonts and cells have `encodeWithCoder:`, but controls made in code have
  no cell, so their titles aren't written. Apps rarely archive views.
- The window position in a nib is ignored on Wayland, as in M4.
- Auto Layout constraints in nibs are ignored; views keep their frames and
  autoresizing masks.

**What's next.** M6: real apps, with a compatibility table in
`docs/ferry-compat.md`. The first step is trying real nibs; the next is
the AppKit classes they need most (likely `NSWindowController`,
`NSViewController`, `NSImage`, `NSBox`, `NSPopUpButton`, `NSScrollView`
and `NSTextView`).

## M6: real apps

Dean chose the apps to aim for: small open-source Objective-C apps with
Intel builds. Seven were downloaded from their GitHub release pages and run
here without being added to the repository (they are third-party code, and
their nibs hold Apple colour profiles): Hex Fiend, Flycut, KeyCastr,
ShiftIt, Spectacle, MacPass and Gas Mask. `docs/ferry-compat.md` has the
table of how far each gets. Work went app by app: run it, find the first
thing that stops it, fix that if it is general, run it again.

### What stopped them first, and the fixes

- **Every app links a framework Ferry doesn't have** (Carbon, IOKit,
  Security, WebKit, Quartz, CloudKit...). Ferry stopped at load. Now
  (`src/loader.c`) a missing `/System/Library` framework or `/usr/lib`
  library is named once and skipped. Its functions become the usual stubs
  that stop the program with their name if called. Its Objective-C classes
  are bound to nil, as a Mac binds a weakly linked class an older system
  lacks (a stub there would be read as a class and crash); the count is
  printed, and `FERRY_VERBOSE=1` lists them. A class of the app's own built
  on a missing one is left out with its name (`src/objc/runtime.c`), and a
  message sent to it later stops the program with both names rather than
  looping. A missing variable named like one of Apple's string constants
  (`NS...Notification`, `NS...Key`, `kAX...`) gets a constant string
  holding its own name, which is what most of them hold on a Mac.
- **Nibs from current Xcode are `NIBArchive` files**, not keyed archives
  (all of Hex Fiend's, KeyCastr's and MacPass's). `appkit/ANibArchive.m`
  is an `NSCoder` that reads them: a header with four tables (objects,
  keys, values, classes), seven-bit variable-length numbers whose last byte
  has the top bit set, typed values (integers of four sizes, booleans,
  float, double, bytes, nil, object references), strings and data under
  `NS.bytes`, and arrays, sets and dictionaries as repeated
  `UINibEncoderEmptyKey` values. It feeds the same `initWithCoder:`
  methods as M5's keyed archives, so nothing else changed. The format was
  worked out from developers' published notes and by reading the real
  nibs' structure with a small script (kept outside the repository).
- **Grand Central Dispatch** (`src/objc/dispatch.c`, header
  `sdk/include/dispatch/dispatch.h`): every app calls `dispatch_once` or
  `dispatch_async`. Ferry runs a program on one thread, so all queues run
  their work on it, in order, from Foundation's run loop (or
  `dispatch_main`). That keeps what programs rely on: a serial queue runs
  one block at a time in order, `dispatch_sync` returns after its block
  ran. A semaphore or group wait runs queued work until what it waits for
  happens; if nothing could, Ferry says so and stops instead of hanging.
  Dispatch objects are Objective-C objects, so ARC manages them. Covered:
  queues (serial, concurrent, global, main, suspend and resume, labels,
  specific values, target queues), `dispatch_async`/`sync`/`after`/`apply`/
  `once` and the `_f` forms, groups, semaphores, timer sources and the
  data-merging sources; other source types say they won't fire.
- **Libraries built before Mac OS X 10.6** (ShiftIt's Sparkle, from 2011)
  have no `LC_DYLD_INFO`: their fixups are relocation entries (local ones
  slide, external ones bind a symbol, at offsets from the first writable
  segment), their imports sit in symbol-pointer sections named by the
  indirect symbol table, and their exports are only in the symbol table.
  The loader now reads all three. Their compiler also sent messages
  through `__objc_msgrefs` pairs (`objc_msgSend_fixup`); the runtime
  registers those selectors and `msgsend.S` has the `_fixup` entry points.
- **Smaller things the apps hit**, each fixed where the app hit it:
  `valueForKeyPath:`/`setValue:forKeyPath:`; `NSValueTransformer` with the
  named transformers (negate, is nil, is not nil, unarchive from data) and
  transformers found by class name; Cocoa bindings
  (`appkit/NSKeyValueBinding.m`: `bind:toObject:withKeyPath:options:`
  records the binding and sets the bound value once, `infoForBinding:`,
  `exposeBinding:`; Foundation has no key-value observing yet, so changes
  aren't followed); `NSUserDefaults` through key-value coding;
  `+[NSValue valueWithNonretainedObject:]`; `initWithContentsOfFile:` and
  `initWithContentsOfURL:` for arrays and dictionaries; `atexit` (not a
  symbol of glibc itself); `formatter`, `allowsEditingTextAttributes` and
  `importsGraphics` kept on controls; `colorWithPatternImage:` giving plain
  grey until there is `NSImage`.

### M6 report (2026-11-22)

**What works now.** Five of the seven apps start (Hex Fiend needs Swift
and Gas Mask an older start-up format), and four of those get through
`NSApplicationMain` and their main nib into their own launch code. All 53 nib files in them load (16 in Hex Fiend, 30 in MacPass,
the rest one or two each), in both of Xcode's formats, with the windows,
panels, menus, buttons, labels and text fields Ferry has, and a warning for
each class it hasn't. No app runs all the way yet; `docs/ferry-compat.md`
says what stops each one. `make check` runs 48 tests (43 before M6), all
passing. The new ones:

| Test | Proves |
| --- | --- |
| `dispatch` | Dispatch from plain C: queue labels, `dispatch_once` once only, `dispatch_async` and `_f` in order, `dispatch_sync` at once, a group of work on a global queue with a wait and a notify, a semaphore signalled from queued work and one timing out, a suspended queue holding its work until `dispatch_after` resumes it, `dispatch_apply`, queue-specific values, a repeating timer source cancelled after three firings with its cancel handler, `dispatch_main` |
| `foundation_dispatch` | Dispatch with Foundation and ARC: work hopping from a queue back to the main queue on the run loop, a queue freed with its owner (a weak reference turns nil), `dispatch_after` waking `CFRunLoopRun` after the right time, dispatch and run-loop blocks sharing the loop |
| `foundation_missing` (+ message check) | A program linked against a framework that doesn't exist (`Imaginary.framework`, only a `.tbd` for the linker): it starts, the framework's class is nil, the program's subclass of it is left out, its notification name and key constants hold their names and work as dictionary keys, and calling its function stops the program with the function's name; each step's message checked |
| `appkit_bindings` | Key paths both ways; the named value transformers, one found by class name, and data through the unarchiving transformer and back; `valueWithNonretainedObject:`; arrays and dictionaries read from a file, mutable ones staying mutable; a text field's value and a button's enabled state bound to an object, a binding to a missing key leaving the property alone, `infoForBinding:`, `exposedBindings`, `unbind:`; `NSUserDefaults` by key-value coding |
| `appkit_nib` | now also loads `PanelArchive.nib`, the M5 panel written in the `NIBArchive` form by `make_nibs.py`, and checks it gives the same objects, frames, outlets and `awakeFromNib` calls as the keyed-archive copy |

**What isn't done yet (and why).**

- **No real app is usable yet.** Each one stops at the next missing piece
  (see `docs/ferry-compat.md`). The pieces that come up most: `NSImage`;
  exceptions that can be caught (Ferry has no Mach-O unwinder, so the first
  `@throw` stops the program); `NSWindowController`, `NSViewController` and
  the document classes; `NSScrollView`, `NSTableView`, `NSTextView`,
  `NSPopUpButton`, `NSBox` and the other views nibs use; `NSInvocation`;
  `NSAlert`, `NSWorkspace`, `NSStatusBar`.
- **Flycut crashes** on a bad object pointer during its launch code; not
  traced yet. It is the only app here that crashes rather than stopping
  with a message.
- **Some apps' core features can't work on Wayland as written**: global
  hotkeys (Carbon's `RegisterEventHotKey`), watching other apps' key
  presses (KeyCastr) and moving other apps' windows through the
  Accessibility API (ShiftIt, Spectacle). Those need a desktop-side
  service, and are out of M6's scope.
- **One thread.** Dispatch work never runs in parallel, and a program that
  starts a thread (`pthread_create`, `NSThread`) still stops there. Programs
  that wait for another thread without dispatch would stop too.
- **Bindings don't follow changes**, because Foundation has no key-value
  observing yet.
- **Old start-up format.** Gas Mask's program uses `LC_UNIXTHREAD`
  (Mac OS X 10.7 and earlier), which the loader doesn't run yet.
- The old-relocation loading was tested on one real library (ShiftIt's
  Sparkle) only, because current linkers can't produce that format for a
  test.

**What's next.** M7 was planned as polish (Dock icons, Open/Save panels,
clipboard, drag and drop, scaling). Given what the apps need, I'd suggest
starting it with `NSImage`, catchable exceptions and `NSWindowController`/
`NSViewController`, which every app here reaches before any polish.

## M7: what the apps needed, then polish

M6 showed every app reaching `NSImage`, a caught exception or a window
controller before any of the planned polish would matter, so M7 did those
first (Dean: "Do whatever is best"), then the polish.

### Design

- **Images** (`appkit/NSImage.m`, `appkit/NSImageView.m`,
  `graphics/ImageIO.m`). Files are decoded by this system's GdkPixbuf
  (PNG, JPEG, GIF, TIFF, BMP, ICO, `.icns`) and PDF pages are drawn by
  Poppler, both new optional groups in `src/host.c` (quiet when missing).
  An `NSImage` holds representations: bitmaps (`NSBitmapImageRep`, which
  caches its `CGImage`), PDF pages (`NSPDFImageRep`) and drawing blocks
  (`NSCustomImageRep`); drawing picks the best one for the destination's
  pixels. `imageNamed:` looks in the registry, the app bundle (with `@2x`
  files) and then at a few standard images Ferry draws itself (never
  Apple's artwork); names ending in `Template` tint. Image I/O's
  `CGImageSource` calls are served from Core Graphics. Fixed on the way: a
  bitmap context's contents were wiped when an image was made from it.
- **Exceptions** (`src/objc/exception.c`, `src/objc/unwind.S`). Ferry's
  own two-phase unwinder, as the Itanium C++ ABI describes: the throw
  captures the registers, the search phase walks the frames with each
  image's compact unwind entries (frame-pointer, frameless with the stack
  size in the entry or in the code, and DWARF), reads each function's
  table of `@catch` clauses (the LSDA) and matches the exception's class;
  the cleanup phase runs `@finally` blocks and lands in the handler. An
  exception nobody catches goes to the uncaught-exception handler, where
  Foundation prints the Mac's "Terminating app due to uncaught exception"
  message; `NSApplication`'s event loop catches what an app's event
  handling throws, reports it and carries on, as a Mac app does. Only
  frames of Mac code can be unwound.
- **Controllers** (`appkit/NSViewController.m`). A window controller loads
  its window from its nib when first asked, and is the window's next
  responder; a view controller loads the nib named after its class (or its
  `nibName`), and sits between its view and the view's superview in the
  responder chain. `windowWithContentViewController:` makes a window
  around one. Sheets, modal windows and popovers presented by a view
  controller open a window of their own, with a warning.
- **Clipboard** (`appkit/NSPasteboard.m`). Pasteboards are Ferry's own
  objects; the general one also talks to GTK's clipboard: text written to
  it goes there, and when another app has copied something, the next read
  takes its text, files or image. Text fields cut, copy and paste.
- **Open and Save panels** (`appkit/NSSavePanel.m`): GTK's file chooser
  (`GtkFileChooserNative`, so the desktop's own through a portal where
  there is one), with filters from the allowed types. With no display, a
  panel answers Cancel, or the paths in `FERRY_PANEL_ANSWER`.
- **Drag and drop** (`appkit/NSDragging.m`): each window's GTK drawing area
  becomes a drop target once something in it registers types; files and
  text dropped from other apps go on the drag pasteboard and through the
  `NSDraggingDestination` messages. Dragging out of a Ferry window is not
  done.
- **Dock icons**: an app bundle with an icon, started on a display, writes
  a hidden desktop entry named after its bundle identifier (its Wayland app
  id) and its icon as a PNG into `~/.local/share`, which is how a Wayland
  dock finds an app's icon (`FERRY_NO_DESKTOP_ENTRY=1` turns it off). Under
  X11 the icon is also the windows' own.
- **Scaling**: windows were already drawn at the screen's whole-number
  scale; M7 adds the conversions between points and pixels
  (`convertRectToBacking:` and friends, `backingAlignedRect:options:`) and
  tells windows and views when their scale changes.

### M7 report (2026-11-23)

**What works now.** A Mac program can load and draw images, catch
exceptions, use window and view controllers with their own nibs, copy and
paste (with other apps too), ask for files with the system's Open and Save
panels, take files dropped on it, and show its icon in the dock. In the
seven apps from M6, 160 of the 162 image files load and draw, and Flycut
no longer crashes. `make check` runs 60 tests (48 before M7), all passing.
The new ones:

| Test | Proves |
| --- | --- |
| `foundation_trycatch` (three builds: ARC, `-O2 -fomit-frame-pointer`, `-O0` without ARC) | `@catch` by class and by `id`, the first matching clause winning, a string thrown, `@finally` with and without an exception, `@throw;` rethrowing, exceptions through Foundation's own frames (a block called by `enumerateObjectsUsingBlock:`), `NSArray`'s range exception, `@synchronized` unlocking on the way out, `NS_DURING`/`NS_HANDLER`, a thousand in a row, and values in callee-saved registers surviving the unwind, over frame-pointer, frameless and DWARF frames |
| `appkit_report` (+ message check) | An exception raised in the event loop (from a timer) is reported and the app keeps running |
| `appkit_image` | An image drawn with `lockFocus`, written as PNG, JPEG, TIFF and BMP into the test's own app bundle and read back, unreadable data refused, `imageNamed:` finding a file and its `@2x` twin, drawing scaled, from part of the image, into a flipped context and at half strength (checked pixel by pixel), a PDF page as an image, standard and template images (tinted), the app icon, an image view and image buttons, Image I/O's `CGImageSource`, a pattern colour |
| `appkit_nib` | now also an image view in both panel nibs, its image (`NSCustomResource`) found in the bundle |
| `appkit_controllers` | A window controller loading its window lazily (`windowWillLoad`, `windowDidLoad`), its outlets and the button's action, the window's next responder, `showWindow:` and `close`; a view controller loading the nib named after its class (in the `NIBArchive` form), `viewDidLoad`, the responder chain view → controller → superview, `windowWithContentViewController:`, a window controller's `contentViewController`, child controllers |
| `appkit_pasteboard` | Types by old and new names, items, `writeObjects:`/`readObjectsForClasses:` with strings, URLs (file URLs only, on request), `NSFilenamesPboardType` both ways, an image, data promised by an owner and by an item's provider (asked once), a separate pasteboard, and cut/copy/paste in a text field with the Edit menu items enabled to match (copy disabled in a password field) |
| `appkit_panels` | Open panels choosing one or several files, by extension or type identifier in either case, folders only when allowed, missing files and the delegate turned down; save panels adding the extension and remembering the folder; begin calls running their handler after they return |
| `appkit_dragging` | Which view gets a drop (the one under the pointer that took the pasteboard's types, else the window's delegate), the order of the destination messages, the operation limited to what the source allows, the dropped files read back |
| `appkit_icon` | An app bundle with an icon writing its desktop entry and a 256-pixel icon, on the headless Weston |
| `appkit_hidpi` | On a headless Weston at scale 2: the scale reported by screen and window, points to pixels and back, aligned rectangles, an image drawn with twice the pixels |

Checked by hand, beyond `make check`: copying text from one Ferry program
and pasting it in another, the file chooser opening on the right folder
with its filter, and a real drag of two files from a GTK program into a
Ferry window, all under Xvfb (the headless Weston has no seat, so no
clipboard or drag there).

**What isn't done yet (and why).**

- **No real app is usable yet.** The next things they stop at: the views
  nibs use (`NSScrollView`, `NSTableView`, `NSTextView`, `NSPopUpButton`,
  `NSBox`...), the document classes (MacPass), `NSInvocation` (KeyCastr),
  and Carbon's hotkeys (Flycut, Spectacle). See `docs/ferry-compat.md`.
- **Exceptions through Linux code.** Only Mac frames can be unwound, so an
  exception can't cross a frame of a Linux library. AppKit catches and
  reports exceptions in the code GTK calls back into (drawing, resizing,
  closing, focus, drops) before they reach GTK's frames; an exception
  thrown inside some other Linux callback would be treated as uncaught.
- **JPEG 2000 icons.** `.icns` files holding only JPEG 2000 artwork (both
  of KeyCastr's) don't load: GdkPixbuf has no reader for it.
- **Drag sources.** Dragging out of a Ferry window, or between views of
  the same app, is not done; only drops from other apps.
- **The clipboard is text both ways, and files and images one way.**
  Files and images copied in a Ferry app stay inside it.
- **Panel accessory views** aren't shown, and an Open panel can't choose
  files and folders at once (GTK's chooser does one or the other); each
  says so once.
- **Dock icons on Wayland** depend on the dock reading desktop entries by
  app id, as GNOME's and KDE's do; whether freemac's own dock does is for
  the desktop side. Changing the icon while the app runs
  (`setApplicationIconImage:`) only reaches X11 windows opened later.
- **Whole-number scales only**, as GTK 3 draws: at a fractional scale the
  compositor scales the next whole one down.

**What's next.** From what the apps hit: the scrolling views and tables
(every app's nibs use them), then `NSDocument`/`NSDocumentController`,
`NSInvocation`, and `NSAlert`/`NSWorkspace`/`NSStatusBar`.

## More apps, and the Installer

Dean (2026-11-23): "can you make sure other apps will work as well, try
something with a GUI installer". Two new apps (MacDown, Sequel Pro) and
three real installers (MacPorts' and XQuartz's `.pkg`, Sequel Pro's
`.dmg`) were added to the seven of M6, and the gaps they showed were
filled in order.

### Design

- **`ferry` and bundles** (`src/main.c`). `ferry Foo.app` runs the bundle's
  program (`CFBundleExecutable`, else `Contents/MacOS/<name>`). A `.pkg`,
  `.mpkg` or `.dmg` (or a file that starts with `xar!` or ends with a disk
  image's `koly` trailer) starts the Installer instead, found through
  `FERRY_INSTALLER`, next to `ferry`, or in `/usr/lib/ferry`.
- **The Installer** (`installer/`), a Mac app built with `ferry-cc`
  against Ferry's own frameworks. `IPackage.m` reads the formats:
  - a flat package is a xar archive: a header, a zlib-compressed XML table
    of contents, then the heap; the Distribution file gives the title,
    the welcome, read-me, licence and conclusion documents (RTF, HTML or
    text, from `en.lproj`, `English.lproj`, `Base.lproj`...) and the
    components; each component's PackageInfo gives its install location;
  - a Payload is a cpio archive (the portable `070707` form or the newer
    `070701`), gzip-compressed or in `pbzx` chunks of xz, read as a stream
    a megabyte at a time so the window stays live;
  - an old bundle package's `Contents/Archive.pax.gz`;
  - a disk image is opened with this system's 7-Zip (`7z`, else `7zz`) into
    a temporary folder; it is searched for packages, and if there are none
    its apps are copied (7-Zip's `com.apple.*` metadata files left out).
  Where things go (`IDestination`): anything inside an `X.app` folder to
  `~/Applications`, everything else under `~/.local/share/ferry/root`.
  Paths that climb out are skipped, nothing is written through a link the
  archive made, and an app already installed is replaced. Scripts and the
  Distribution's JavaScript checks are never run; the pages say so. The
  window (`Installer.m`) has the usual steps in a sidebar, a licence to
  agree to, a destination page that says where things go and how much
  space it takes, a progress page and a summary with "Open <App>"; an
  installed app is added to the desktop's list with `freemac-mac-app
  install` when the desktop has it (`FERRY_NO_DESKTOP_ENTRY=1` turns that
  off). `--info` and `--install` do the same without a window.
- **Scroll views and text views** (`appkit/NSScrollView.m`,
  `appkit/NSTextView.m`, `appkit/ATextFormats.m`). `NSClipView` scrolls by
  moving its bounds origin; scrollers are drawn and dragged; wheel events
  scroll by lines or by the touchpad's exact amounts. The text view lays
  out its storage with a Core Text framesetter, draws selection and
  caret, takes the standard key commands (`moveWordLeft:`,
  `deleteBackward:`...), copy and paste, and reads and writes RTF (from
  Microsoft's published RTF specification) and simple HTML, which the
  Installer's pages use. `NSProgressIndicator` and `NSBox` came with them.
- **Key-value observing** (`foundation/NSKeyValueObserving.m`).
  Observers registered for a key path hear changes an object announces
  with `will/didChangeValueForKey:` and changes made through
  `setValue:forKey:`, with the New, Old, Initial and Prior options and
  contexts; an observed object that goes away takes its registrations
  along. Bindings (`appkit/NSKeyValueBinding.m`) now observe the key path
  they are bound to and set the view again on a change.
  `NSUserDefaultsController` reads and writes defaults through its
  `values` proxy.
- **Libraries from this system** (`src/host.c`). ICU joins zlib, bzip2,
  xz, libxml2 and SQLite: a Mac's `libicucore` calls go to this system's
  ICU under its versioned names (`uregex_open_74`), and
  `sdk/gen-twin-tbd.sh` writes the matching link stub.
- **Carbon and Accessibility** (`appkit/Carbon.m`, served as `Carbon`
  from AppKit's file) and **SystemConfiguration**
  (`foundation/SystemConfiguration.m`, from Foundation's file): each call
  answers as a Mac does when the thing isn't available, so apps carry on.
  Hotkeys are registered but never pressed (Wayland doesn't let one app
  see another's keys); the keyboard layout has no Mac layout data; the
  process is never trusted for Accessibility; every address is reachable.
- **Smaller pieces**: `OSSpinLock`, `OSAtomic...` and `os_unfair_lock`
  (`src/posix.c`, with headers in the SDK), the old garbage collector's
  write barriers (plain stores), `CFPreferences`, `CFStringGetCharacters`,
  cancelling delayed performs, the Services menu's provider, paragraph
  styles in archives, content borders, cell background styles.
- **Fixes**: a class left out for a missing superclass now gets an empty
  method cache, so a message to it is reported instead of crashing (older
  linkers fill a class's cache words with `_objc_empty_cache` and
  `_objc_empty_vtable`); `freopen` on stdout or stderr moves the file onto
  the same descriptor and leaves the stream open when the new file can't
  be opened, so Ferry's own messages still reach the terminal (Gas Mask
  redirects its stderr to a log); the Installer counts files it couldn't
  write and fails instead of reporting success.

### Report (2026-11-23)

**What works now.** A Mac installer package or disk image opens in
Ferry's Installer and installs for the user: MacPorts' package (1,364
files, the same as 7-Zip extracts), XQuartz's (310 MB in about 1.5
seconds) and Sequel Pro's disk image all install through the window,
checked page by page under Xvfb, and "Open Sequel Pro" starts the app. Of
the nine apps, ShiftIt now runs into its event loop and stays there, and
Gas Mask, Flycut and Spectacle get much further than before. `make
check` runs 87 tests (60 at M7, 69 before freemac (1.170), 74 before
freemac (1.173), 77 before freemac (1.178), 79 before freemac (1.184), 82
before freemac (1.188), 84 before freemac (1.190), 85 before freemac
(1.191)), all passing.
The new or extended ones:

| Test | Proves |
| --- | --- |
| `installer` | A package made by `tests/tools/make_pkg.py` (two components, a gzip/`070707` payload and a `pbzx`/`070701` one, an RTF licence, an HTML welcome, a member that climbs out, a link): `--info`, `--install` into test folders (apps and the rest in the right places, nothing outside them, the link kept), the same package cut short failing cleanly, and `ferry Bundled.app` running the bundle's program |
| `atomics` | Spin locks, unfair locks, the `OSAtomic` calls' results, and stderr still working after a failed `freopen` of it |
| `twins` | now also ICU's regular expressions through `libicucore` |
| `foundation_kvo` | Key-value observing: options, contexts, key paths, will/didChange around a setter, `setValue:forKey:`, removal, an observed object going away |
| `foundation_runloop` | now also cancelling delayed performs, by object and by selector |
| `appkit_bindings` | now also bindings following changes, and `NSUserDefaultsController` (applied at once, held until saved, reverted); from freemac (1.184) a view's exposed bindings include `NSView`'s `hidden` and `toolTip` |
| `foundation_kvo_auto` | (freemac (1.184), Ferry 0.17.0) automatic key-value observing: the hidden `NSKVONotifying_` subclass made when an object first gets an observer (`class` still the original, `isMemberOfClass:`, the description), setters of objects, integers, `BOOL`, `double`, rects, points and ranges announced; `automaticallyNotifiesObserversForKey:` and `automaticallyNotifiesObserversOf<Key>`; instance variables set by `setValue:forKey:` announced; the subclass kept after the last observer goes; a subclass of an observed class; dependent keys by `keyPathsForValuesAffectingValueForKey:` and `keyPathsForValuesAffecting<Key>`, through a to-one relationship; key paths through a replaced object (the old one no longer followed); the Prior, Initial, Old and New options; `mutableArrayValueForKey:` through indexed accessors, a setter and an instance variable, with insertion, removal and replacement at indexes; `willChange:valuesAtIndexes:forKey:` by hand; nested changes; mutable dictionaries and `NSUserDefaults`; key-value coding's search order, `setValuesForKeysWithDictionary:`, `setNilValueForKey:` and the undefined-key exceptions |
| `appkit_formatters` | (freemac (1.184), Ferry 0.17.0) formatters on text fields: the value shown with `stringForObjectValue:`, editing started from `editingStringForObjectValue:`, a keystroke `isPartialStringValid:` refuses (a beep, `control:didFailToValidatePartialString:errorDescription:`), Return and the end of editing reading the text with `getObjectValue:forString:errorDescription:`; a string it can't read beeping, asking `control:didFailToFormatString:errorDescription:` and keeping the editing going (or kept as the value when the delegate says so); `control:isValidObject:` refusing a value; focus with no typing keeping the value; `abortEditing` and `validateEditing`; an `NSNumberFormatter`; a cell's formatter, kept by its copy; a cell-based table's column cell formatter showing the value, starting the editing and giving the data source a number, a bad entry beeping once and Escape |
| `appkit_binding_controls` | (freemac (1.184), Ferry 0.17.0) bindings that follow and write back: a text field's value (written when the editing ends or on Return, not when nothing was typed, or as it is typed with `NSContinuouslyUpdatesValueBindingOption`), the null placeholder shown as the field's placeholder and an emptied field writing nil, a check box through `NSNegateBoolean`, `enabled` and `enabled2` combined with AND and `hidden` and `hidden2` (through `NSIsNotNil`) with OR, a key path through a to-one relationship, pop-up buttons' `content`, `selectedObject`, `selectedIndex` and `selectedValue` (chosen with the mouse and written back, new content), a slider kept in its range and clicked; `NSObjectController` with no content (the no-selection placeholder, the binding's own), its `selection.name` followed and written, a new content, `remove:` and `add:` (from freemac (1.188) carried out on the run loop's next turn); `NSUserDefaultsController`'s `values.*` changed by a click, in the defaults and through the controller; exposed bindings, `infoForBinding:` and the markers; and a nib (`Bindings.nib`) with binding connectors to an object controller and the shared defaults controller, its slider snapping to its tick marks |
| `foundation_kvc_collections` | (freemac (1.188), Ferry 0.18.0) `mutableSetValueForKey:` through a class's set accessors (one object at a time, and `add<Key>:` for a union), through its setter and straight to an instance variable, with the set mutation kinds observers hear (insertion of what a union adds, removal of what a minus or an intersect takes away, replacement for `setSet:`) and the old, new and prior options, and `willChangeValueForKey:withSetMutation:usingObjects:` by hand; the collection operators `@count`, `@sum`, `@avg`, `@min`, `@max`, `@unionOfObjects`, `@distinctUnionOfObjects`, `@unionOfArrays`, `@distinctUnionOfArrays` and `@distinctUnionOfSets` on arrays, sets and through a to-one key, with nil values, empty collections and an unknown operator; arrays and sets answering and taking keys; removing an observer that isn't registered (or with the wrong context) raising `NSRangeException`; `NSPredicate`'s format strings (comparisons, `[c]`, `[d]`, `LIKE`, `BETWEEN`, `IN`, `ANY`, `ALL`, `NONE`, `AND`, `OR`, `NOT`, the format arguments and an argument array), `$variables`, blocks, `NSCompoundPredicate`, filtering arrays and sets, and formats it can't read |
| `appkit_array_controller` | (freemac (1.188), Ferry 0.18.0) `NSArrayController`: its defaults, content given (an array and a set) and bound (`contentArray`, changed through the owner's indexed accessors and by the owner), `arrangedObjects` sorted and filtered, `selectionIndexes` and `selectedObjects`, `selection.name` with the multiple-values, no-selection and not-applicable markers and `alwaysUsesMultipleValuesMarker`, writing through the selection, `preservesSelection`, `avoidsEmptySelection`, `selectsInsertedObjects`, `clearsFilterPredicateOnInsertion`, adding, inserting at an index and removing, `add:`, `insert:` and `remove:` on the run loop's next turn, `selectNext:` and `selectPrevious:`, `canAdd`, `canInsert` and `canRemove`, `automaticallyRearrangesObjects`, observers of `arrangedObjects.name`, `arrangedObjects.@count`, `selection.name` and `selectionIndexes`, and the `selectionIndexes` binding both ways; a cell-based table whose columns are bound to `arrangedObjects.key`: its content, `selectionIndexes` and `sortDescriptors` bound for it, the columns' sort descriptors (and `NSCreatesSortDescriptorBindingOption`), the null placeholder, a column title bound, clicks and command-clicks selecting in the controller and the controller's selection shown, a model change redrawn, clicks on column titles sorting the controller, cells edited in place written back, rows added and removed |
| `appkit_tree_controller` | (freemac (1.190), Ferry 0.19.0) `NSIndexPath` (adding and removing an index, `indexAtPosition:` past the end, `getIndexes:range:`, equality, hashing, `compare:` and sorting, `section` and `item`); `NSTreeNode` on its own (children through `mutableChildNodes`, observed, a node taken from its old parent, `parentNode`, `indexPath`, `descendantNodeAtIndexPath:`, sorting recursively); `NSTreeController`: its defaults and exposed bindings, content with `childrenKeyPath`, a leaf decided by having no children, by `leafKeyPath` or by `countKeyPath`, `arrangedObjects` as a tree of nodes kept across rearranging, `selectionIndexPaths`, `selectedObjects`, `selectedNodes` and `selection.name` with the multiple-values marker, writing through the selection, sorting level by level with `preservesSelection` on and off, the model adding, removing and replacing children (observed through its indexed accessors), inserting at an index path, removing (a node and its child at once), an index path that has no parent raising, `moveNode:toIndexPath:`, `add:`, `insert:`, `addChild:`, `insertChild:` and `remove:` on the run loop's next turn, `canAddChild` on a leaf, with `countKeyPath` and with no selection, `canAdd` and the rest when not editable, the `contentArray` and `selectionIndexPaths` bindings both ways, and dictionaries as the objects; an outline view whose columns are bound to `arrangedObjects.key`: its `content`, `selectionIndexPaths` and `sortDescriptors` bound for it, its items the controller's nodes, rows opened by code and by a click on a chevron, clicks and command-clicks selecting in the controller, a node the controller selects shown with its parents opened, a model change redrawn, clicks on column titles sorting the controller with open rows kept open, cells edited in place written back (text and a number), no editing and no write back when the controller isn't editable, `addChild:` and `remove:` shown; a table column's per-row `editable` (through `NSNegateBoolean`) and `enabled` bindings for text cells and check boxes, and `NSConditionallySetsEditable`; `NSDictionaryController`: its defaults, a bound `contentDictionary` with included, excluded and localized keys, a pair's value and key changed and written back, `add:` making unique keys, `remove:`, a new dictionary from the model, and an unbound mutable dictionary changed in place |
| `appkit_nib_controllers` | (freemac (1.191), Ferry 0.20.0) A nib written in the test with Ferry's own `NSKeyedArchiver` (an `NSIBObjectData` with custom objects, outlet and binding connectors, and a window template), loaded with `NSNib` and nothing bound in code: an `NSArrayController` (object class, editable, prepares content, avoids empty selection, preserves selection, selects inserted objects, clears the filter on insertion, rearranges automatically, always uses the multiple-values marker, declared keys), an `NSTreeController` (children and leaf key paths), an `NSObjectController` (an entity name, and content prepared at `awakeFromNib`) and an `NSDictionaryController` (initial key and value, included, excluded and localized keys) read back; their `contentArray`, `sortDescriptors` and `contentDictionary` bound to File's Owner by connectors; a cell-based table whose columns are bound to `arrangedObjects.key` (content, selection and sorting bound for it); a view-based table and a view-based outline with no delegate and no data source, bound to the controllers, making their cell views from the table's own prototype nibs (`NSTableViewArchivedReusableViewsKey`), with a text field and a check box in each cell view bound to `objectValue.key`; the rows, a click selecting through the controller, a field bound to `selection.title` and its no-selection and multiple-values placeholders, the field edited and the table and cell views rearranged, a cell view's field edited in place and its check box clicked (written back), the model changed under the views, `add:` and `remove:`, the outline's cell views given the nodes' represented objects and edited in place, `addChild:`, the object controller's prepared dictionary edited through a field with a null placeholder, and the dictionary controller's pairs written back |
| `appkit_binding_validation` | (freemac (1.191), Ferry 0.20.0) `NSValidatesImmediatelyBindingOption`: values typed into fields bound through an object controller's and an array controller's selection put to `validate<Key>:error:` before they are written; a refused one presented (the application delegate's `application:willPresentError:` sees it, and the alert is answered) and the field showing the model's value again, a changed one (trimmed, a string made a number, clamped) written changed and shown, nothing asked without the option; the selection proxies' own `validateValue:forKeyPath:error:`; the same for a cell-based table's columns and for a field in a view-based table's cell view bound to `objectValue.age`; `NSRaisesForNotApplicableKeysBindingOption` absent (the field kept), NO ("Not Applicable", not editable) and YES (raises); a field made uneditable and a check box disabled with no selection, with a controller that isn't editable (followed as it changes) and with multiple values when `NSAllowsEditingMultipleValuesSelection` is NO; an `enabled` binding taken together with them; `NSConditionallySetsEnabled` and `...Editable` set by hand; the views' own settings given back when unbound; `NSDeletesObjectsOnRemove` (through the objects' `managedObjectContext`), `NSSelectsAllWhenSettingContent`, and `NSHandlesContentAsCompoundValue` into an owner's immutable array and into the user defaults through `NSUserDefaultsController` |
| `foundation_task` | (freemac (1.194), Ferry 0.21.0) `NSTask`, `NSPipe` and `NSFileHandle`: running this system's programs with arguments, environment, working directory and pipes, background reads, readability handlers, the termination handler and notification, waiting, signals and exit status |
| `foundation_regex` | (freemac (1.194), Ferry 0.21.0) `NSRegularExpression` on ICU: options, groups and named groups, the searches, templates, escaping, and `NSString`'s `NSRegularExpressionSearch` |
| `foundation_scanner` | (freemac (1.194), Ferry 0.21.0) `NSScanner`: integers with overflow, hexadecimal, floating point, a locale's decimal separator, strings, character sets, case and skipped characters |
| `foundation_xmlparser` | (freemac (1.194), Ferry 0.21.0) `NSXMLParser` on libxml2: elements, attributes, text, CDATA, comments, processing instructions, entities, namespaces, errors with codes and lines, aborting, nested parses |
| `foundation_operation` | (freemac (1.194), Ferry 0.21.0) `NSOperationQueue` with block, invocation and an app's own operations: dependencies, priorities, cancelling, completion blocks, suspending, barriers, key-value notifications, waits; the locks |
| `foundation_cache` | (freemac (1.194), Ferry 0.21.0) `NSCache` (count and cost limits, least recently used first, the delegate) and `NSProgress` (trees of progress, fraction completed with key-value notifications, cancel and pause) |
| `appkit_more_controls` | (freemac (1.195), Ferry 0.22.0) Steppers by click, keys and holding the mouse down (autorepeat, wrapping or stopping at the ends, the value kept within the limits); level indicators in each style (tick marks and their rectangles, a click or drag setting the level when editable, continuous actions, the arrow keys, rating stars); colour wells taking turns with the shared colour panel (one active well, `changeColor:` sent to the active well and down the responder chain, a second click letting go, closing the panel letting go); date pickers in text-and-stepper style (each part stepped by the arrows without carrying into the next, typed digits moving on to the next part, a year typed short, AM and PM, the stepper, the minimum and maximum, the delegate's validation) and graphical style (days clicked, months turned, a range dragged, the clock beside the calendar); combo boxes with their own items and with a data source (the list opened by the button or the keys, chosen by Return or a click, closed by Escape or a click outside, the four notifications in order, completion keeping what was typed, the arrows stepping through the items with the list closed); popovers in each behaviour (shown beside a rectangle on any edge, moved to the other side when there is no room, kept in the window, closed by Escape, a click outside, `performClose:` or the delegate's refusal, the four notifications) and view controllers presented as popovers; path controls (components from a file URL and a web address, clicks and double clicks, own items, a placeholder, long paths cut in the middle, the pop-up style's menu); `NSSound` played through a stand-in player (named sounds, a sound from data, the volume, pause and resume, stop, looping, the delegate told whether it finished); token fields (tokens made at commas or at a character set, Return and end of editing, Backspace selecting then removing a token, the delegate's represented objects, display strings and refusals); and all of them loaded from a nib with their targets and actions |
| `foundation_urlsession` (ARC, dispatch) | (freemac (1.196), Ferry 0.23.0) `NSURLSession` against a server on 127.0.0.1: data tasks with handlers (task state before and after `resume`, handler run after `resume` returns), `NSHTTPURLResponse` (status, MIME type, charset, length, headers in any case, suggested name), POST/PUT/DELETE/HEAD with bodies and headers, 404 and 204 not being errors, redirects, gzip, the URL errors (can't connect -1004, timeouts -1001 while connecting and mid-body, no host -1000, unsupported URL -1002, redirect loop -1007, connection lost -1005, cancel -999), cancelling before and after `resume`, tasks together in a dispatch group, the configuration and session headers, delegates (data, refused response, upload progress, download progress, invalidation), download tasks to a temp file removed after the handler, upload tasks, and a handler under `dispatch_main()` |
| `foundation_urlconnection` (manual retain/release) | (freemac (1.196), Ferry 0.23.0) `NSURLConnection`: synchronous (200, 404, closed port), asynchronous (on the main queue or a private one; a redirect; a bad URL), with a delegate (PATCH with a body, a closed port, `startImmediately:NO`, cancel), `canHandleRequest:`; `NSData` and `NSString` `...ContentsOfURL:` over http (charset from the response, Cocoa error 256 with the URL error underneath); requests and responses made by hand (header case, `addValue:`, copies, Content-Type parsing, status texts) |
| `libcurl loaded only when loading URLs` (check in `run.sh`) | (freemac (1.196), Ferry 0.23.0) a Foundation program that loads no URL never opens libcurl (`LD_DEBUG`) |
| `foundation_xmldocument` | (freemac (1.197), Ferry 0.24.0) `NSXMLDocument` on libxml2: a document with a declaration, a comment, a processing instruction, a default and a prefixed namespace and an entity read into objects (kinds, names, local names, prefixes, URIs, namespaces, attributes, string values, indexes and levels, siblings, next and previous nodes, `elementsForName:` with a prefix, `elementsForLocalName:URI:`, `attributeForLocalName:URI:`, resolving namespaces and prefixes); written out compact, pretty printed, with compact empty elements and single quotes; XPath (by local name, with a prefix, attributes, a relative path, processing instructions, comments, the document, the namespace axis, a result that isn't nodes and a bad expression); the tree changed (inserting, removing, replacing, `setChildren:`, `insertChildren:atIndex:`, a duplicate attribute ignored, removing an attribute, setting string values, normalizing text nodes, a namespace added and a node detached) and XPath and `XMLString` seeing every change; a node that has a parent and an attribute added as children (exceptions); documents built in code, written as ISO-8859-1, US-ASCII (character references) and UTF-16 data and read back; `setRootElement:`; object values (a number, a date, a boolean); resolving entities; CDATA with `]]>` in it; `NSXMLNode` making an `NSXMLElement` for its kind; an element from a string, copied deeply; whitespace and CDATA with and without the preserve options; a document that isn't well formed (error 76 and its line), tidied, empty (error 4) and invalid with `NSXMLDocumentValidate`; a DTD with public and system ids, an entity, an element and an attribute declaration (kinds, values, written back, changed), a declaration made from a string, a predefined entity; canonical XML with and without comments, and of an element; data in ISO-8859-1, a file URL, a web URL refused; a document class whose `replacementClassForClass:` makes its own elements |
| `quartzcore_layers` | (freemac (1.198), Ferry 0.25.0) Layer geometry (frame from bounds, position, anchor point and transform, through scaling and a quarter turn), key-value coding of layer properties and of keys of the caller's own, a subclass's `@dynamic` properties with `defaultValueForKey:` and `needsDisplayForKey:`, sublayer order and replacing, point conversion and hit-testing; drawing checked pixel by pixel: background, border, rounded corners and `maskedCorners`, opacity per layer and as a group, hidden, `masksToBounds`, transforms, `sublayerTransform`, `geometryFlipped`, `zPosition`, an image's contents with the gravities, the delegate's `drawLayer:inContext:` and `displayLayer:`, `needsDisplayOnBoundsChange`, shape layers (fill, stroke, stroke start and end, dashes, even-odd), axial and radial gradients, and text layers |
| `quartzcore_animations` | (freemac (1.198), Ferry 0.25.0) One animation on the real run-loop clock, then everything on the test clock: the transform functions, the named timing functions, implicit animations and when they start, transactions (duration, disabling actions, nesting, the completion block), actions from the `actions` dictionary and the delegate, `onOrderIn`; basic animations (fill modes, replacing, `byValue`, additive, autoreverse, cumulative repeats, a later begin time, speed, a key path into the transform); keyframe animations in every calculation mode, with key times, timing functions and a path; groups; springs; the delegate's start and stop messages; a layer drawn while a property animates |
| `appkit_layers` | (freemac (1.198), Ferry 0.25.0) A view's backing layer and its geometry, `makeBackingLayer`, a layer-backed view drawn with its layer's background, border, corner radius, opacity and sublayers (in plain and flipped views), `wantsUpdateLayer`/`updateLayer`, a hosted layer; `NSAnimationContext` groups with the view's `animator` for `frame` and `alphaValue`, the completion handler, the default duration outside a group, a duration of 0, a new animation taking over, the `animations` dictionary; implicit layer animations only with `allowsImplicitAnimation`; an explicit animation of a view's layer moving where the view is drawn; a window drawing a layer-backed content view |
| `foundation_urlredirects` (ARC) | (freemac (1.199), Ferry 0.26.0) Redirects decided by the delegate, against the server on 127.0.0.1: `URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:` following (also answered later, from the run loop), changing (another URL and header) and refusing a redirect (the 3xx response and its body come back), two redirects in a row, a relative `Location`, what 301, 302, 303, 307 and 308 do to a POST and 303 to a PUT, `currentRequest` before and after; `NSURLConnection`'s `connection:willSendRequest:redirectResponse:` (first with no response, then per redirect; refusing the redirect; refusing the first request); synchronous calls and `stringWithContentsOfURL:` following redirects |
| `foundation_urlauth` (ARC) | (freemac (1.199), Ferry 0.26.0) `NSURLCredential`, `NSURLProtectionSpace` (equality, proxies), `NSURL`'s `user` and `password`, `NSURLCredentialStorage` (credentials per space, the default one, persistence None not kept, removal, its notification); HTTP Basic and Digest (MD5, qop=auth) challenges answered by the task delegate with each disposition (a credential, one given later, a wrong one then cancel, none, reject the space, default handling), previous failure counts and proposed credentials, the URL's user and password, a credential kept for the session and used afterwards by default handling, a session-level method not asked about a password, an ephemeral session's own storage; `NSURLConnection`'s `connection:willSendRequestForAuthenticationChallenge:` with each sender message (cancel gives -1012) and the older `canAuthenticateAgainstProtectionSpace:` and `didReceiveAuthenticationChallenge:` pair |
| `foundation_urlcookies` (ARC, run twice) | (freemac (1.199), Ferry 0.26.0) `NSHTTPCookie` from properties (and without a name or domain, from an origin URL) and from `Set-Cookie` fields (Domain, Path and its default, Expires, Max-Age, Secure, HttpOnly, a foreign domain refused, several in one field), `requestHeaderFieldsWithCookies:`; the shared `NSHTTPCookieStorage` (matching by domain, path and scheme, replacing, deleting, sorting, the accept policy with and without a main document, its notification, the file it saves); sessions sending and keeping cookies (paths, a cookie the server expires, a request that turns cookies off or has its own Cookie field, a cookie set by a redirect, `dataWithContentsOfURL:` and `NSURLConnection` sharing them, `HTTPShouldSetCookies` off, the policy Never, no storage, an ephemeral session's own); a second run reading the lasting cookies back, and the file going when the last is deleted |
| `foundation_urlcache` (ARC, run twice) | (freemac (1.199), Ferry 0.26.0) `NSURLCache` by hand (memory and disk, a second cache on the same files, memory-only and not-allowed entries, the fragment ignored, removal) and through sessions, counted by the server: `max-age`, `max-age=0`, `Expires`, `ETag` and `Last-Modified` revalidated with a 304, `no-store`, a POST; each request cache policy, the configuration's policy, the request's `Cache-Control: no-cache`; the twentieth-of-the-cache size rule; no cache; `URLSession:dataTask:willCacheResponse:completionHandler:` keeping, refusing and changing the entry; downloads not kept; the shared cache through `dataWithContentsOfURL:` and `NSURLConnection`, and its files; a second run answered from disk without the network |
| `foundation_urldata` (ARC) | (freemac (1.199), Ferry 0.26.0) `data:` URLs (RFC 2397) through `NSURLSession`, `NSURLConnection`, `NSData` and `NSString`: plain and percent-encoded, base64, a charset, a MIME type, a fragment, bad base64 (-1015) and no comma (-1000), `canHandleRequest:` |
| `foundation_urltrust` (ARC; needs openssl) | (freemac (1.199), Ferry 0.26.0) An https server whose certificate run.sh made, which the system doesn't trust: no delegate (-1202), the session-level challenge with default handling (-1202), cancel (-999) and a trust credential (the page loads), a password challenge after it, the task-level method alone, `NSURLConnection` accepting it, `dataWithContentsOfURL:` refusing it |
| `commoncrypto_digests` | (freemac (1.200), Ferry 0.27.0) MD5, SHA-1, SHA-224, SHA-256, SHA-384 and SHA-512 against RFC 1321's suite and FIPS 180's examples (the empty message, "abc", the 448- and 896-bit messages, a million "a"), each one-shot and fed in every split; HMAC against RFC 2202 and RFC 4231 (keys shorter and longer than a block), one-shot and incremental; PBKDF2 against RFC 6070 and RFC 7914; `CCCalibratePBKDF`; `CCRandomGenerateBytes` and `CCRandomCopyBytes` |
| `commoncrypto_cryptor` | (freemac (1.200), Ferry 0.27.0) AES through this system's OpenSSL: FIPS 197's ECB examples for 128, 192 and 256-bit keys, SP 800-38A's CBC (AES-128 and AES-256) and CTR (AES-128) examples, PKCS#7 padding and its lengths, `CCCrypt` and the `CCCryptor` calls fed in pieces, `CCCryptorReset`, `CCCryptorGetOutputLength`, and the documented status for a spoilt padding, a buffer too small (with the size needed), unaligned input, a wrong key size, an unknown option and an algorithm or mode Ferry doesn't have |
| `foundation_sysversion` | (freemac (1.200), Ferry 0.27.0) One macOS version (14.7, build 23H124) everywhere: `/System/Library/CoreServices/SystemVersion.plist` read as a property list, with stdio (also through a doubled slash), with `open` and `stat`, refused for writing (`EACCES`, and `access` says so); `uname`'s Darwin 23.6.0; `NSProcessInfo`'s `operatingSystemVersion`, `operatingSystemVersionString` and `isOperatingSystemAtLeastVersion:`; `Gestalt`'s `sys1`, `sys2`, `sys3` and `sysv`, and an unknown selector |
| `foundation_sysversion_carbon` | (freemac (1.200), Ferry 0.27.0) The same program linked against Carbon instead of CoreServices, for `Gestalt` |
| `security_keychain` | (freemac (1.200), Ferry 0.27.0) Generic and internet passwords in a home of the test's own, run twice: `SecItemAdd`, `SecItemCopyMatching` (data, attributes, a reference, a persistent reference, several at once, one or all, case-insensitive), `SecItemUpdate` and `SecItemDelete`; the documented status for a duplicate, nothing found, a wrong type, a missing class, another class's attribute, a match limit where none belongs, a certificate (not kept); synchronizable items found only when asked for; the older `SecKeychain...` calls on the same items; the folder at mode 0700 and its files at 0600, no secret in the clear in the file, a tampered secret refused (`errSecDecode`); items kept for the second run; `SecCopyErrorMessageString`; `SecRandomCopyBytes` |
| `security_code` | (freemac (1.200), Ferry 0.27.0) Code signing as Ferry answers it: `SecCodeCopySelf`, its static code and a static code made for the executable's path pass `SecCodeCheckValidity` and `SecStaticCodeCheckValidity`, with and without a requirement; `/bin/sh` reads as unsigned (`errSecCSUnsigned`, also as a `CFError`); signing information with no identifier, team or certificates; no designated requirement; the program found by its process id and no other; a path with nothing there; requirements kept as text and malformed ones refused |
| `security_code message` | (freemac (1.200), Ferry 0.27.0) With `FERRY_VERBOSE` set, each of the two code-signing answers is said once on stderr, however often it is given |
| `security_selfcheck` | (freemac (1.200), Ferry 0.27.0) An app's check of its own signature from inside its bundle: the running code is the bundle, static codes made for the bundle's and the executable's paths pass, the signing information carries the bundle's Info.plist and main executable but no identifier |
| `security_trust` (needs openssl) | (freemac (1.200), Ferry 0.27.0) The test server's own certificate: read from DER (garbage refused), its subject summary and common name, its data back, `CFEqual`; a trust refused against the system's authorities (`errSecNotTrusted`), accepted with it as the anchor (alone and with the system's), refused in 2000 and 2100 (not yet valid, expired) and for another host name; basic X.509; `SecTrustEvaluate`, `SecTrustGetTrustResult`, the policies, the chain, `SecTrustEvaluateAsyncWithError`; and in an `NSURLSession` challenge, the server trust's certificates read from the server, refused as received and accepted once given its own certificate as the anchor, after which the page loads |
| `libsystem_sysctl` | (freemac (1.201), Ferry 0.28.0) `sysctlbyname` and `sysctl` by number: `kern.ostype`, `kern.osrelease` and `kern.version` matching `uname`, `kern.osproductversion` 14.7 and `kern.osversion` 23H124, `hw.machine`, `hw.model`, `kern.hostname` matching `gethostname`, `hw.ncpu`, `hw.activecpu`, `hw.logicalcpu(_max)`, `hw.physicalcpu` and `machdep.cpu.core_count`/`thread_count` agreeing with `sysconf` and each other, `hw.memsize`, `hw.pagesize` (also read into an int), `hw.cachelinesize`, `hw.byteorder`, `hw.optional.*`, `machdep.cpu.brand_string` and `vendor` matching `cpuid`, `kern.boottime`, `sysctl.proc_translated` 0; the documented rules (a NULL buffer gives the size, a small buffer `ENOMEM` with the start copied, an unknown name `ENOENT`, a write `EPERM`); `sysctlnametomib` and the numbers it gives; `kinfo_proc` for this process (648 bytes, pid, parent, `p_comm`, `P_TRACED` clear, `P_LP64`, user, start time), for the parent and for a pid that doesn't exist; `KERN_PROCARGS2`; `proc_pidpath` and `proc_name`; `host_page_size`, `host_statistics64`, `host_statistics`, `host_info` and `task_info`; `getattrlist` on the program (name, type, modification time, full path, size, returned attributes, `FSOPT_REPORT_FULLSIZE`) and on its folder (entry count) |
| `libsystem_dlsym` | (freemac (1.201), Ferry 0.28.0) `RTLD_DEFAULT`, `RTLD_MAIN_ONLY`, `RTLD_NEXT` and `RTLD_SELF` from the program and from a library; `dlopen(NULL)`; a library built here opened through `@rpath`, `@executable_path` and (from inside it) `@loader_path` as one handle, its initializer run, `RTLD_NOLOAD`, `dlopen_preflight`; a bundle built with `-bundle -undefined dynamic_lookup` opened `RTLD_LOCAL`, calling back into the program and hidden from `RTLD_DEFAULT`; libSystem by path and by leaf name, Foundation and CoreFoundation by their `/System/Library/Frameworks` paths; `dlerror` after each failure (a missing name, a missing library, a framework Ferry doesn't have, a file that isn't a Mac library, a handle that isn't one) and cleared after reading; `dladdr` in a library, inside a program's function and on libSystem's `strlen`; `_dyld_image_count`, `_dyld_get_image_name` and `_dyld_get_image_header`, the add-image callback, `_NSGetExecutablePath`; `_availability_version_check` found with `dlsym` |
| `libsystem_available` | (freemac (1.201), Ferry 0.28.0) `@available` and `__builtin_available` compiled the normal way (macOS 10.15, 14, 14.7 and 13.5 available; 14.7.1, 14.8 and 15 not), `__isOSVersionAtLeast`, `__isPlatformVersionAtLeast` and `NSProcessInfo`'s `isOperatingSystemAtLeastVersion:` agreeing on each, an iOS version not available; `operatingSystemVersion` matching `kern.osproductversion`, `processorCount`, `activeProcessorCount` and `physicalMemory` matching `hw.ncpu`, `hw.activecpu` and `hw.memsize` |
| `libsystem_plugin` | (freemac (1.201), Ferry 0.28.0) Plug-in bundles built here: `NSBundle` not loaded until `load` (its description says so), one bundle per path, `preflightAndReturnError:`, `loadAndReturnError:`, `principalClass` from `NSPrincipalClass`, the plug-in's class finding its own bundle with `bundleForClass:` (Foundation's classes give the main bundle), `classNamed:`, `bundleWithIdentifier:`, `unload` refused; the same bundle through `CFBundleCreate`, `CFBundleIsExecutableLoaded`, `CFBundleGetFunctionPointerForName`, `CFBundleGetDataPointerForName`, `CFBundleCopyExecutableURL` and `CFBundleGetBundleWithIdentifier`; a bundle with no `NSPrincipalClass` (the first class it defines) loaded with `CFBundleLoadExecutable`; a bundle whose program is missing (`NSCocoaErrorDomain` 4, no principal class); a folder that isn't there |
| `pthreads` | (freemac (1.202), Ferry 0.29.0) the pthread calls of a Mac's libSystem on this system's threads: eight threads adding to one counter under a mutex, an `os_unfair_lock` and an `OSSpinLock` (160000 each), threads joined with their results, `pthread_main_np` before and after, a condition variable between a producer and a consumer, `pthread_once` from many threads, keys with destructors, `pthread_exit`'s value, a read-write lock, thread names, detach states, a stack too small refused and the stack size kept, recursive and error-checking mutexes (`EDEADLK`, `EBUSY`), timed waits returning `ETIMEDOUT`, thread ids and stack addresses, `pthread_equal`, Mac static initialisers |
| `dispatch_concurrent` | (freemac (1.202), Ferry 0.29.0) libdispatch across threads: four blocks on a global queue all running at once and none on the main thread, a serial queue running 4000 blocks one at a time in order, `dispatch_sync` from 16 threads, a barrier waiting for the blocks before it and running alone, `dispatch_apply` on more than one thread, semaphore ping-pong between threads and a counting semaphore's limit, `dispatch_once` from eight threads, `dispatch_after` on a global queue, a group's notify after 100 blocks, a stress run of 10000 global and four serial queues' blocks, and the main queue running only on the main thread |
| `foundation_threads` | (freemac (1.202), Ferry 0.29.0) `NSThread`: the main thread's answers (`isMainThread`, name, `threadDictionary`), a thread made with `initWithTarget:selector:object:` and started (executing and finished, the argument, its name, `NSWillBecomeMultiThreadedNotification` once and `NSThreadWillExitNotification`), starting it twice refused, `initWithBlock:` with cancel, its own dictionary, `sleepForTimeInterval:`, its autorelease pool, `+exit` and its quality of service, `detachNewThreadSelector:...` and `detachNewThreadWithBlock:`, `performSelectorOnMainThread:` (with and without waiting, and from the main thread itself), a thread's own run loop, `performSelector:onThread:` waited for and not, `performBlock:` on that thread's run loop, `performSelectorInBackground:`, an operation queue running two operations at once and keeping to a limit of four, main-queue operations from a worker running on the main thread, and 16 threads at once |
| `foundation_locks` | (freemac (1.202), Ferry 0.29.0) Foundation's locks and the runtime under many threads: `NSLock` (counting, its name, `tryLock` and `lockBeforeDate:` against a lock held elsewhere), `NSRecursiveLock`, `NSCondition` between producers and consumers and a wait that times out, `NSConditionLock` handing over in order and a condition never set timing out, `@synchronized`, `+initialize` run once with no thread getting in before it ends, messages sent while a method is added, retain and release, weak references loaded while the object goes away, associated objects, autorelease pools on eight threads, and notifications posted from eight threads |
| `cxx_basics` | (freemac (1.203), Ferry 0.30.0) a C++ program on this system's libc++: a global object constructed before `main` and destroyed after it, a replaced `operator new` used by containers, `vector`, `map`, `unordered_map`, `set`, algorithms and `accumulate`, `string` (find, `stod`, `stoll`), `iomanip` (precision, hex, fill), `printf` and `cout` alternating in order, `ctype` classes and `toupper`, words read with `>>`, `regex`, `stringstream` with `seekg`, `tellg` and `tellp`, `function`, `unique_ptr` and `shared_ptr`, `chrono` clocks and durations, and `filesystem` (directories, files, sizes, `ifstream` and `ofstream`, iteration, extensions, removal) in a temporary folder |
| `cxx_exceptions` | (freemac (1.203), Ferry 0.30.0) C++ exceptions thrown and caught by this system's libc++abi in a Mac program: through six recursive frames running their destructors, out of a function with no frame pointer, through this system's `qsort`, out of a Mac library of the program's own with its own exception class (`BadShape`), typeinfo compared and `dynamic_cast` across the two images, rethrown, kept in an `exception_ptr`, nested, caught by a second base class, `bad_cast` and `out_of_range` from the library, `uncaught_exceptions` during unwinding, and `std::terminate`'s handler for an exception leaving a `noexcept` function |
| `cxx_threads` | (freemac (1.203), Ferry 0.30.0) C++ threads on the Mac's layouts: a counter under `std::mutex` from eight threads, a queue under a `condition_variable`, `wait_for` timing out and `wait_until` woken, `recursive_mutex`, `timed_mutex`, `recursive_timed_mutex`, `shared_mutex` and `shared_timed_mutex`, `call_once`, `promise<int>` and `promise<void>`, `async` (on a thread, deferred, with an exception), a broken promise, a promise set twice, `shared_future`, thread ids and `hardware_concurrency`, joining no thread, and `detach` |
| `objcxx_mixed` | (freemac (1.203), Ferry 0.30.0) Objective-C++ under ARC: an object whose C++ ivars (a class, a `vector` and a `map` holding `NSString`s) are built and destroyed by `.cxx_construct` and `.cxx_destruct`, `NSString`s in a `vector`, a block capturing a C++ object (copied once on the stack and again on the heap, all destroyed), an `NSException` through a C++ frame running its destructor, a C++ exception through `@finally`, `@catch (NSException *)` letting a C++ exception through, `catch (...)` taking an `NSException` and rethrowing it, `@catch (...)` taking a C++ exception and rethrowing it with `@throw`, and a plain `@try` with `@finally` |
| `cxx_missing` | (freemac (1.203), Ferry 0.30.0) a C++ program without this system's libc++ (`FERRY_LIBCXX` naming a file that isn't there) stopping with exit status 127 and naming the packages libc++1 and libc++abi1 |
| `cxx_not_loaded` | (freemac (1.203), Ferry 0.30.0) an Objective-C program with no C++ never loading libc++ |
| `tlv_threads` | (freemac (1.204), Ferry 0.31.0) C `__thread` and `_Thread_local` variables, with first values and without, an array, a pointer to a global, a variable aligned to 64 bytes and a static one: eight threads each start from the template and keep their own copy while all eight change theirs at once, and the main thread's copy stays as it was; the thunk keeps every general register the compiler relies on and all sixteen vector registers, on a thread's first use and after it (checked from assembly); a function in the image's thread-local init section runs once; `dispatch_apply` on the global queue counts on each worker thread's own copy; and 32 threads that each fill a 4 MB thread-local array, half ending with `pthread_exit`, leave no storage behind |
| `tlv_threads_chained` | (freemac (1.204), Ferry 0.31.0) the same program as `tlv_threads`, linked with chained fixups |
| `tlv_dylib` | (freemac (1.204), Ferry 0.31.0) thread-local variables in a Mac library the program links through `@rpath`: the program reaches the library's variables directly, by their exported names, and through the library's own calls, and gets the same variable each way; six threads each start from the library's template and count on their own copies beside the program's own variable |
| `tlv_dlopen` | (freemac (1.204), Ferry 0.31.0) thread-local variables in a Mac library opened with `dlopen` while the program runs: a thread started before the library was opened, four threads started after it and the main thread each get their own copies; `dlsym` of a thread-local variable gives the calling thread's copy, and a write through it is seen by the library; destructors registered with `_tlv_atexit` and `__cxa_thread_atexit` run as each thread ends, the last registered first and still able to read the thread's variables, and the main thread's run when `main` returns, before the program's `atexit` function |
| `tlv_objc` | (freemac (1.204), Ferry 0.31.0) Objective-C `__thread` variables (an `int`, an unretained `NSString`, a static `NSInteger` and a `double`) on eight `NSThread`s started with a target and selector, with a block, detached and with `performSelectorInBackground:`: each sees the first values and keeps its own, one leaves with `+[NSThread exit]`, a destructor registered on each runs as it ends, and the main thread keeps its own values |
| `cxx_thread_local` | (freemac (1.204), Ferry 0.31.0) C++ `thread_local` objects across eight `std::thread`s: objects with constructors and destructors at namespace scope, as a static class member and inside a function, a `std::vector` and a `std::string`; each thread builds them on first use and destroys them in reverse order when it ends, a destructor reads another `thread_local` that is still there, and the main thread's objects are destroyed when `main` returns, before the program's static objects (skipped without libc++, like the other C++ tests) |
| `libsystem_sockets` | (freemac (1.205), Ferry 0.32.0) BSD sockets with the Mac layouts: `sa_len`, AF_INET6 30, the Mac `msghdr`, `cmsghdr`, `addrinfo`, `ifaddrs` and `fd_set`; TCP over 127.0.0.1, UDP with IP_PKTINFO and IP_RECVTTL, Unix sockets with SCM_RIGHTS and LOCAL_PEERPID, Mac socket options (SO_NOSIGPIPE, SO_NREAD, TCP_KEEPALIVE), Mac errno and EAI_ values, select and poll, getaddrinfo, getnameinfo, gethostbyname, inet_pton, and getifaddrs with an AF_LINK entry for the loopback; ::1 when the host has IPv6 |
| `libsystem_kqueue` | (freemac (1.205), Ferry 0.32.0) kqueue, kevent and kevent64 on epoll: EVFILT_READ and WRITE on pipes, sockets and files with EV_EOF, EV_CLEAR, EV_ONESHOT, EV_DISPATCH and EV_DISABLE; EVFILT_TIMER (one-shot, repeating, absolute); EVFILT_SIGNAL counting signals without changing the program's disposition; EVFILT_PROC NOTE_EXIT with the status while waitpid still reaps; EVFILT_USER from another thread; change-list errors as EV_ERROR results |
| `dispatch_sources` | (freemac (1.205), Ferry 0.32.0) libdispatch READ, WRITE, SIGNAL and PROC sources on real descriptors, signals and processes: data counts, suspend and resume, cancel handlers, a source on the main queue, and NULL for signal 0 |
| `corefoundation_socket` | (freemac (1.205), Ferry 0.32.0) CFRunLoopSource version 0 (schedule, perform, cancel, signal) and CFSocket with a run loop source: a TCP listener with the accept callback, a client with the connect and data callbacks, an echo, a refused connection, datagrams, the read callback re-enabled automatically and the write callback once |
| `foundation_streams` | (freemac (1.205), Ferry 0.32.0) NSInputStream and NSOutputStream over data, files and memory with delegate events; a bound pair; socket streams from getStreamsToHostWithName and CFStreamCreatePairWithSocketToHost with delegates, a dispatch queue and blocking use; a refused connection (ECONNREFUSED 61); a native socket; and TLS through the system's OpenSSL against a local server: an untrusted server fails with -9807, without validation the page arrives, and the peer trust holds the server's certificate |
| `foundation_netservice` | (freemac (1.205), Ferry 0.32.0) NSNetService TXT records made and read as RFC 6763 says; publish, resolve and search say "will" and then fail in the run loop with NSNetServicesUnknownError (-72000), as on a Mac where Bonjour can't be reached |
| `appkit_print_info` | (freemac (1.206), Ferry 0.33.0) `NSPrintInfo`: the shared print info's defaults (the paper this system's locale uses, the margins, scaling, pagination and centring), paper sizes and names, orientation turning the paper, the dictionary behind the properties, a copy that doesn't share changes, archiving with `NSCoding`, the print panel and page layout answering from `FERRY_PRINT_ANSWER` and `FERRY_PAGE_LAYOUT_ANSWER` with no display, and the printing calls a document now answers to |
| `appkit_print_view` | (freemac (1.206), Ferry 0.33.0) a tall view printed to a PDF file: laid out on several pages of the print info's paper, each page drawn by the view's own `drawRect:` (not to the screen, with the print operation current), and the file read back with Poppler (the number of pages, their size and the text on each); the same view on A4 in landscape at half size with a header and footer; a print operation run for a window, finishing after the call returns; and a print job that is cancelled |
| `appkit_print_pagination` | (freemac (1.206), Ferry 0.33.0) a view wider and taller than the page printed with automatic pagination (tiled row by row from the top), fit pagination (shrunk onto one page) and clip pagination (one page, cut off); a view that isn't flipped; a view that moves each page's bottom edge with `adjustPageHeightNew:top:bottom:limit:` so that a band isn't cut; a view that knows its own pages (`knowsPageRange:` and `rectForPage:`); and a range of pages printed in reverse order, with each page's rect, its place on the paper and the text on it |
| `appkit_print_text` | (freemac (1.206), Ferry 0.33.0) a text view printed across pages: eighty numbered lines on US Letter, every line printed once, whole and in order, each page ending at the edge of a line, and the selection not printed; the same text at a larger size on A5, fitted to the page's width, through the view's `print:` action with the panel answered; and rich text with a bold run, all of whose words print |
| `appkit_print_pdfdata` | (freemac (1.206), Ferry 0.33.0) `dataWithPDFInsideRect:` making one page the size of the rect, holding the view's drawing and its subviews' inside the rect and nothing outside it; `PDFOperationWithView:insideRect:toData:` and `toPath:` never showing the print panel, even when one is asked for; `writePDFInsideRect:toPasteboard:`; a window's `dataWithPDFInsideRect:` drawing its content view; and `dataWithEPSInsideRect:` giving Encapsulated PostScript |
| `appkit_print_document` | (freemac (1.206), Ferry 0.33.0) an `NSDocument` subclass making its print operation in `printOperationWithSettings:error:` from its own print info; `printDocumentWithSettings:showPrintPanel:delegate:didPrintSelector:contextInfo:` running it with the settings given (saving to a file) and calling the delegate back; Print… (`printDocument:`) through the print panel, answered from the environment, and cancelled; Page Setup… (`runPageLayout:`) changing the document's own print info only, after asking `shouldChangePrintInfo:`, refused and cancelled; and the print info kept when it is archived |
| `appkit_fonts` | (freemac (1.206), Ferry 0.33.0) one shared `NSFontManager`, which a program's own `alloc` gives too; the installed families and their members, from fontconfig; fonts made by family, traits and weight, and a Mac family name (Menlo) matched; conversions to and from bold and italic, to another size, family and face, and heavier and lighter; the Bold and Italic menu items (`addFontTrait:`) turning the trait on and off in a text view's selection through `changeFont:`, and the items' checks following the selected font; Bigger (`modifyFont:`); typing after Bold; and the font panel, answered from `FERRY_FONT_ANSWER` with no display, changing only what was chosen |
| `appkit_window_print` | (freemac (1.206), Ferry 0.33.0) printing on a display: Page Setup as GTK's page setup dialog in a sheet on the window, keeping the paper; the print dialog as GTK's print dialog in a sheet, printing to the file the answer names (GTK's Print to File), and the PDF's pages read back; the dialog cancelled; and the font panel (GTK's font chooser) shown and closed. It needs Weston and is skipped without it |
| `appkit_notify_un` | (freemac (1.207), Ferry 0.34.0) UNUserNotificationCenter, on a private session bus with a stand-in notification server: authorization granted and the settings all authorized; two categories with actions, one with a text input action and a custom dismiss action; a notification with no trigger sent at once with its title as the summary, its subtitle and body as the body (markup escaped), the app's name, its desktop entry and sound, and the actions as buttons; the delegate hearing a named action (which brings the app forward), an inline reply with its text, a dismissal the category asked for, and the default action; a notification swiped away with no category leaving the delivered list without a response; a time-interval trigger pending and then firing half a second later; a calendar trigger firing two seconds on; a repeating daily trigger's next date; removing pending and delivered requests (which sends CloseNotification); the same identifier replacing the notification on screen; the badge from a notification and from `setBadgeCount:`; and, with the app in front, `willPresentNotification:` choosing to show nothing and then a banner without a sound |
| `appkit_notify_ns` | (freemac (1.207), Ferry 0.34.0) NSUserNotificationCenter against the same stand-in: the defaults of a new notification; the action and other buttons, a reply, more actions, the other button closing the notification without telling the delegate, and a click on the notification itself, each reaching `didActivateNotification:` with its activation type, response and action; `didDeliverNotification:` after each delivery; scheduling half a second on and removing a scheduled one; removing a delivered one (CloseNotification); the same identifier replacing the one on screen; and `shouldPresentNotification:` deciding while the app is in front |
| `appkit_notify_dock` | (freemac (1.207), Ferry 0.34.0) the Dock tile, seen by a stand-in Dock as freemac's Dock reads it: com.canonical.Unity.LauncherEntry Update signals for the badge label (a number shown, a label that isn't a number not shown, `showsApplicationBadge`), for critical and informational attention requests (cancelled, ended after a second, ended when the app becomes active, and refused while it is active), and sent again when the Dock says it started; the delegate's `applicationDockMenu:` served as a dbusmenu menu (the Update's "quicklist"), read with its submenu and clicked; the tile's size and owner, and a content view drawn by `display` |
| `appkit_notify_none` | (freemac (1.207), Ferry 0.34.0) a session bus with no notification server: every call still answers (authorization, adding requests, delivering, the delegate's `didDeliverNotification:`), nothing is shown, the badge and attention still reach the Dock, and the program carries on |
| `appkit_notify_none message` | (freemac (1.207), Ferry 0.34.0) with `FERRY_VERBOSE` set, Ferry says once that no notification server is running |
| `appkit_notify_nobus` | (freemac (1.207), Ferry 0.34.0) the same program with no session bus at all gives the same answers, and with `FERRY_VERBOSE` set Ferry says once that there is no session bus |
| `libcrypto loaded only when encrypting` | (freemac (1.200), Ferry 0.27.0) A program using only CommonCrypto's digests doesn't load this system's OpenSSL; one using AES does |
| `appkit_carbon` | The Carbon, Accessibility and SystemConfiguration answers, and the smaller AppKit and Foundation pieces |
| `appkit_scrolling` | (before this report, same branch) scroll views, scrollers, text views, RTF and HTML, progress indicators, boxes |
| `appkit_panes` | (freemac 1.155) tab views and split views: layout, selection, the delegates, dragging, collapsing, holding priorities, autosaved positions, both built from a nib |
| `appkit_statusbar` | (freemac 1.157) menu bar items, on a private session bus: their StatusNotifierItem properties and pictures, the dbusmenu layout of one item's menu (labels, ticks, a dimmed item, a submenu read on its own), clicks on menu items and on an item without a menu, hiding an item, and Quit |
| `appkit_tables` | (freemac 1.159) table and outline views: a cell-based table in a scroll view with its header tiled above it (geometry, drawing through its cells, a check box column), selection by click, shift- and command-click, double click and the arrow keys with the delegate's say, sorting by clicks on the header, columns resized by dragging the header's dividers and by each autoresizing style, rows inserted and removed; a view-based table making only the rows in sight and reusing their views; an outline view opened and closed by code, chevron clicks and the arrow keys, with items and rows mapped both ways; and both loaded from a nib with a prototype cell view |
| `appkit_controls` | (freemac 1.164) pop-up buttons, segmented controls, search fields, stack views and toolbars: a pop-up list's menu opened over the button with the chosen item lined up, chosen by click and click, by press, drag and release, by the arrow keys, Return, Space and typing, closed by Escape or a click outside, disabled items passed over, an item's own action, the menu's delegate and the will-pop-up notification, and full keyboard access; a pull-down list; segmented controls in each tracking mode, with disabled segments, drags off a segment, tags, a segment's menu, the keys and every distribution; search fields searching after a pause, at once or only on Return, cleared by Escape and the clear button, with recent searches kept, saved and shown in the search menu; stack views in rows and columns (gravity areas, every distribution and alignment, insets, custom spacing, hidden and detached views, views dropped for want of room by visibility priority, nested stacks); toolbars from a delegate (the window's frame growing by the strip in each display and size mode, items placed with a flexible space, validation, clicks, a selectable item, items added and removed, the overflow menu, the saved configuration); and all of them loaded from a nib |
| `appkit_documents` | (freemac 1.167) the document classes, alerts and the workspace, in `DocApp.app` from `make_nibs.py` (four document types in its Info.plist, the File and Edit menus and the app's own `NSDocumentController` subclass in its main nib, a document window nib): a note named on the command line opened at launch; the types, classes and extensions; New ("Untitled", "Untitled 2"); edits through the undo manager moving the change count and the window's edited dot, Undo and Redo from the Edit menu; the File menu's validation; Save and Save As through the Save panel shown as a sheet, saved safely beside the file; Revert in a sheet; closing with unsaved changes (Cancel, Don't Save and Save, by Escape, Command-D and Return); Open through the Open panel, a file already open, a type the app can't open and a file it can't read; a package read and written as a file wrapper; a class with only the Mac OS X 10.3 calls; the Recent Documents list in the defaults and the Open Recent menu, opened from and cleared; alerts run modally in a nested loop (Return, Escape, Command-D, a click), their layouts with an accessory view and the suppression check box, the old return codes, `FERRY_ALERT_ANSWER`, `presentError:`; sheets (queued, the window's close refused while one is up, the old `beginSheet:modalForWindow:...` call); the workspace opening addresses, files and folders through a stand-in `gio`, icons, apps by identifier and name, types; and quitting with two unsaved documents (the review alert, each document's sheet, `NSTerminateLater`). Pictures of an alert, a sheet and an edited window go to `FERRY_DOCUMENTS_PNG` |
| `foundation_invocation` | (freemac (1.170), Ferry 0.14.0) `NSMethodSignature` from type encodings (sizes, alignments, frame length, `NSGetSizeAndAlignment`, bad encodings raising); `NSInvocation` calling methods that take and return integers of every width, pointers, objects, `float`, `double`, `long double`, C strings, small and large structs (`NSRect`, `NSRange`, structs mixing integers and floats, one in two vector registers, a struct passed on the stack), `SEL` and blocks, with more arguments than registers; `getReturnValue:`, `setReturnValue:`, `retainArguments` (objects, blocks and C strings kept), `invoke` and `invokeWithTarget:`, a nil target; exceptions thrown through `invoke` and through forwarding; an `NSProxy` that logs and re-sends every kind of call to its target; an `NSObject` subclass catching messages with `methodSignatureForSelector:` and `forwardInvocation:` (instance and class methods, `forwardingTargetForSelector:` going first); `NSUndoManager`'s `prepareWithInvocationTarget:` with groups, nested groups, redo, registration turned off and `removeAllActionsWithTarget:`; and a message nobody implements still stopping the program with the Mac's message (`foundation_invocation message`) |
| `foundation_invocation_O0` | (freemac (1.170)) the same program unoptimized and linked with chained fixups |
| `foundation_json` | (freemac (1.170)) `NSJSONSerialization` reading objects, arrays, every escape, surrogate pairs, integers, large integers and doubles, `true`, `false` and `null`; the mutability options and fragments; UTF-16 and UTF-32 input; mistakes as errors in the Cocoa domain (3840) with their line, column and index; nesting too deep; writing compactly, pretty-printed and with sorted keys, slashes escaped or not, fragments; `isValidJSONObject:`; what raises (other classes, infinite numbers, non-string keys, a bad top level) |
| `foundation_dates` | (freemac (1.170)) `NSTimeZone` from the system's time zone database (offsets, abbreviations, daylight saving time, the next change, a year past the database's list, local mean time), from offsets and abbreviations, `$TZ` as the system zone; `NSLocale` identifiers and their parts; `NSDateFormatter` writing every pattern letter of Unicode date patterns, in four zones, and the standard styles; reading ISO 8601, RFC 2822 and other strings with offsets, zone names and abbreviations, abutting fields, two-digit years, missing fields, day of year, eras, strict and lenient; part of a string, errors; templates; changed symbols and copies |
| `foundation_calendar` | (freemac (1.173), Ferry 0.15.0) `NSCalendar` (Gregorian and ISO 8601) and `NSDateComponents`: every component of dates in New York, Paris and Tokyo, before 1970 and before the common era; week numbers and week-based years (en_US, en_GB and ISO 8601 weeks, week 53); dates from components, with a skipped and a repeated local time, values that carry, the components' own zone, week dates, the fourth Thursday and the last Monday of a month, a day of the year; copies, equality and `isValidDateInCalendar:`; adding months and years at month ends and leap days, days across a daylight saving change against 24 hours, mixed signs, wrapping; differences in years to seconds, weeks, backwards and between components; starts of days (New York, and Havana where midnight is skipped), the span of a day, week, month, year and hour; ranges and ordinals of units; today, yesterday and tomorrow, the weekend, comparing to a unit; the next date matching components (a time, a 31st, 29 February, Friday the 13th, a skipped time with each option, backwards), enumerating dates and setting a unit |
| `foundation_numbers` | (freemac (1.173), Ferry 0.15.0) `NSNumberFormatter` in every style (no style, decimal, percent, currency, accounting, ISO code, plural, scientific, spell-out, ordinal) with their patterns and digits; fraction, integer and significant digits; all seven rounding modes on halves and negatives, 2.675 and 1.005 rounded as decimals, a rounding increment; grouping sizes, separators, multipliers, padding in each position, prefixes and suffixes; patterns with exponents, quotes, negative parts and a zero part; NaN, infinities, negative zero, the zero and nil symbols; euros, pounds, yen, rupees, francs and an unknown code; locales' currencies and the currency keyword; reading strictly and leniently (grouping, exponents, affixes, percent, accounting, limits, integers only, symbols), errors and part of a string; copies; `NSByteCountFormatter` in its four count styles and with its options |
| `foundation_iso8601` | (freemac (1.173), Ferry 0.15.0) `NSISO8601DateFormatter` writing with each option in four zones (fractional seconds, the basic format, week and ordinal dates, a time alone, before 1970) and reading strings of the same shape only (offsets in each form, fractional seconds only with that option, no zone read in the formatter's, week and ordinal dates, a time alone); `NSDateFormatter`'s relative formatting ("Yesterday", "Today", "Tomorrow", with a time, read back) and its calendar; `NSDateComponentsFormatter` in its six styles, padded, without dropping zeros, with days, a limit of units, fractional hours, years and months on the calendar, the approximation and time remaining phrases |
| `appkit_editing` | (freemac (1.178), Ferry 0.16.0) editing cells in place: in a cell-based table, a double click on an editable cell of a selected row, Return on the row and `editColumn:row:withEvent:select:` (with and without selecting the text) start it, `editedRow` and `editedColumn` follow it; the data source gets the typed string, the delegate is asked `tableView:shouldEditTableColumn:row:` and `control:textShouldEndEditing:` (keeping the editing going once) and hears `controlTextDidBeginEditing:` and `controlTextDidEndEditing:` from the table with the `NSTextMovement` (Return, Tab, Shift-Tab, Escape, a click elsewhere); Tab and Shift-Tab across columns and rows, past a column that isn't editable, selecting the new row, and stopping after the last cell; Escape keeping the old value; a refused cell and a column that isn't editable sending the double action instead; the exception for a row that isn't selected; `reloadData` giving the editing up, a data source that reloads as it takes the value, `abortEditing`; in a view-based table, clicks on an editable field going to the table until it's edited, the cell's own text field edited and its action sent (found with `rowForView:`), Escape, Tab to the next row's field; in an outline view, an item the delegate keeps and one edited, the value going back by item |
| `appkit_autosave` | (freemac (1.178), Ferry 0.16.0) `NSDocument` autosaving, in a home of its own: a class that autosaves in place autosaved by the timer `autosavingDelay` after a change (nothing before it, nothing without a change) and by `autosaveWithImplicitCancellability:completionHandler:` and `autosaveDocumentWithDelegate:...`, over its own file with `NSAutosaveInPlaceOperation`, staying edited (and its window too) with no unautosaved changes, `autosavingIsImplicitlyCancellable` during the write; the file as last saved kept aside in Autosave Information and put back by Revert To > Last Saved Version (the File menu's Revert to Saved item becoming Revert To, with Last Saved Version and a dimmed Browse All Versions); Save making it clean and dropping the copy; closing without asking, after an autosave; an untitled document autosaved into Autosave Information (`autosavedContentsFileURL`, the same file each time), still asking, its file removed on closing; a class that doesn't autosave in place not autosaved, its Revert item unchanged, `NSChangeAutosaved` and `NSChangeCleared`; a delay of 0; quitting with two such documents (no review alert, each autosaved and closed) |

**What isn't done yet (and why).**

- **No real app is usable yet.** Tab, split, table and outline views, menu
  bar items, pop-up buttons, segmented controls, search fields, stack views
  and toolbars have come in since these apps were tried (1.155 to 1.164),
  and the document classes, `NSAlert` and `NSWorkspace` in 1.167; what they
  stop at now is still to be checked. The Sparkle updaters' checks of the
  Mac's version file and code signatures are still missing.
  `docs/ferry-compat.md` has the list.
- **Documents: autosaving without versions** (1.167, autosaving from
  freemac (1.178)). Only a class whose `autosavesInPlace` answers YES is
  autosaved; others are saved only when the user saves them, as on Mac OS
  X 10.6 (a Mac autosaves those elsewhere for crash recovery). There is one
  version kept aside, the file as last saved, for Revert To > Last Saved
  Version; it lives in `~/.local/share/Autosave Information` (freemac's
  place for the Mac's Library) only while the document is open, and is
  gone after a save or a close. `preservesVersions` is ignored and Browse
  All Versions is disabled. `autosavesDrafts` is honoured only in that an
  untitled document still asks on closing; an autosave is done on the main
  thread and never cancelled, whatever `autosavingIsImplicitlyCancellable`
  says. Untitled documents' autosaved files aren't offered again after a
  crash. The File menu's Revert to Saved item turns into Revert To with
  its menu the first time it is validated for such a document, and stays
  so. Whether an autosave keeps the "Edited" title exactly as a Mac does,
  and the names of the files in Autosave Information, weren't compared
  with a real Mac. Renaming, moving and locking from the title bar are
  disabled. Print… and Page Setup… work from freemac (1.206). (`NSUndoManager`'s
  `prepareWithInvocationTarget:` works from freemac (1.170), so undo
  registered that way is kept, as the selector and block forms were.)
- **`NSInvocation` and forwarding: x86-64 only, and a few edge cases**
  (freemac (1.170)). Arguments and results are laid out by Ferry's own
  reading of the x86-64 System V calling convention. A `long double`
  inside a struct that is returned in memory, `_Complex` types other than
  `long double`, and vector types (`__m128` and the like, which type
  encodings can't describe) aren't covered by the tests. When a forwarded
  message's caller and `methodSignatureForSelector:` disagree on whether
  the result comes back in memory, Ferry prints a warning and carries on
  as the signature says (or stops, if no memory was given).
- **JSON: no JSON5** (freemac (1.170)). `NSJSONReadingJSON5Allowed` is
  accepted and plain JSON is still read; JSON5's comments, single quotes
  and unquoted keys are mistakes. `TopLevelDictionaryAssumed` has no
  effect. Error messages are Ferry's own words in Apple's style.
- **Dates: English and Gregorian only** (freemac (1.170)). `NSLocale`
  knows identifiers and their parts, but every locale writes and reads
  dates in English (United States): its month and day names and its
  standard styles (with a plain space before AM and PM, where newer Macs
  put a narrow one). Since (1.173) there are `NSCalendar`,
  `NSDateComponents`, `NSISO8601DateFormatter` and relative formatting
  (see the next items). Time zone
  names (`zzzz`, `vvvv`) come from a table of the common zones, and others
  are written as GMT offsets. Fields a string leaves out come from
  `defaultDate`, or else from 1 January 2000 at midnight. `dateFormatFromTemplate:` handles
  the usual templates by rule, not from the Unicode locale data.
- **Calendars: Gregorian and ISO 8601 only** (freemac (1.173)). Other
  identifiers (Buddhist, Hebrew, Japanese and the rest) give nil. The
  Gregorian calendar is proleptic: dates before 15 October 1582 are
  Gregorian too, where a Mac switches to the Julian calendar. A local time
  the clocks pass twice is the first of the two, and one they skip is moved
  forward by the jump; ICU's documented default for a repeated time is the
  later one, so this may differ on a Mac (not checked on one). The first
  weekday and minimum days of the first week come from a subset of CLDR's
  week data (Sunday first in the United States and the other countries CLDR
  lists so, Saturday or Friday in a few, Monday elsewhere; four days in the
  first week for most of Europe, one elsewhere); the weekend is always
  Saturday and Sunday. The quarter is worked out, where older Macs returned
  0. `dateBySettingUnit:` looks forward, as Apple documents, keeping the
  smaller units; the range of weeks in a year counts the weeks of the
  calendar year's own week-based year. Leap months (`isLeapMonth`) never
  happen. None of these was compared with a real Mac.
- **Numbers: English (United States) only** (freemac (1.173)). Every
  locale writes and reads numbers with a point and commas; a locale's
  country only picks the default currency, from a table of about 60
  countries (a language alone, "en", has none). Currency symbols, digits
  and plural names come from a table of 31 currencies; an unknown code is
  written as itself. Doubles are rounded as the shortest decimal that
  reads back as the same double (2.675 to two places is 2.68). Scientific
  style shows every significant digit until fraction digits are set;
  negative numbers that round to zero show "-0", and the infinities are
  "+∞" and "-∞", as ICU writes them. Reading is strict unless lenient:
  the affixes must be there and the whole string must be a number, though
  grouping may be anywhere (ICU's default). Spelling out covers whole
  numbers up to the quintillions and digits after "point"; spell-out
  strings aren't read back. Partial string validation only checks the
  characters. These choices weren't compared with a real Mac.
- **ISO 8601 and relative dates** (freemac (1.173)). Week dates are
  written as the standard writes them ("2024-W27-4"); with the week option
  the month option is ignored. Fractional seconds are milliseconds, cut,
  not rounded. Relative formatting joins the day to the time with " at "
  ("Today at 3:05 PM") for every date style, as newer CLDR data does; older
  Macs used ", " for the short and medium styles. A calendar set on a date
  formatter is kept but its fields are still Gregorian.
- **Durations and sizes** (freemac (1.173)). `NSDateComponentsFormatter`
  writes English units in the six styles; positional days are written
  "1d" before the clock, `maximumUnitCount` cuts rather than rounds, and
  `collapsesLargestUnit` and reading strings aren't done.
  `NSByteCountFormatter` counts files in thousands and memory in 1,024s
  (still written KB), with Apple's adaptive digits (none for KB, one for
  MB, two above). Neither was compared with a real Mac.
- **Editing in tables: text cells only** (freemac (1.178)). Only text
  cells (an `NSTextFieldCell`, or an editable `NSTextField` in a cell view)
  are edited in place, by Ferry's own text field rather than a shared field
  editor (`currentEditor` and `fieldEditor:forObject:` aren't involved, so
  the delegate's `fieldEditor` argument is nil). A click on a selected
  row's cell doesn't start editing after a pause, as a Mac's does; a
  double click or Return does. From freemac (1.184) a column cell's
  formatter is applied, so a cell-based data source gets the value the
  formatter reads; without one it gets the string as typed. Return on a table edits the
  selected row's first editable cell and only falls back to the double
  action when there is none. Tab stops after the last editable cell and
  Shift-Tab before the first, leaving the table first responder, and
  cell-based editing posts `controlTextDidEndEditing:` only when the text
  was changed. These choices weren't compared with a real Mac.
- **Alerts and sheets are drawn inside Ferry** (1.167): a sheet hangs
  inside its window; one taller or wider than the window gets a window of
  its own, set modal for its parent. The alert's help button asks the
  delegate and otherwise does nothing (no Help Books).
- **The workspace opens things only through the desktop's launcher**
  (1.167): `gio open`, else `xdg-open`, with the address as its one
  argument and no shell; another Mac app is never launched, and an app
  named for `openFile:withApplication:` is not used. The sleep, wake,
  launch and mount notifications exist but nothing posts them.
- **Install scripts aren't run**, by design: they expect a Mac and root.
  Packages whose files only work after their scripts (MacPorts) install
  their files but aren't usable as they are. Absolute links in a payload
  point at the Mac's paths, outside Ferry's folder.
- **Disk images need 7-Zip** (`7zip` or `p7zip-full`, now a recommended
  package); without it the Installer says so. Encrypted images aren't
  handled.
- **Key-value observing: arrays and sets, not ordered sets** (freemac
  (1.184), sets from freemac (1.188)). The hidden subclass wraps setters
  taking objects, integers, `BOOL`, `float`, `double`, points, sizes,
  rects and ranges, the indexed array accessors and the set accessors
  (`add<Key>Object:`, `remove<Key>Object:`, `add<Key>:`, `remove<Key>:`,
  `intersect<Key>:`); a setter taking another struct or a `long double`
  isn't wrapped (its class has to announce the change).
  `mutableOrderedSetValueForKey:` and ordered sets aren't done. The
  collection operators are read in key paths, but a key path isn't
  observed past a plain array or set (an array controller's
  `arrangedObjects` is followed). `@sum` and `@avg` give an `NSNumber`
  (an integer when every value is one); whether a Mac gives an
  `NSDecimalNumber` there, and how it prints, wasn't checked, and the
  custom operators some code defines (`_<key>ForKeyPath:`) aren't asked.
  The subclass's name, `NSKVONotifying_` and the class's, follows what is
  described publicly; `observationInfo` returns Ferry's own record, and
  setting it does nothing. Observers aren't retained, as on a Mac, and
  removing one that isn't registered raises `NSRangeException`, as on a
  Mac (from freemac (1.188); before, it was ignored); its reason follows
  the wording Apple's documentation quotes, not compared with a Mac's.
  Not compared with a real Mac: the order of nested notifications and of
  several dependent keys.
- **Predicates: a subset** (freemac (1.188)). `NSPredicate` reads
  comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `IN`,
  `CONTAINS`, `BEGINSWITH`, `ENDSWITH`, `LIKE`, with `[c]`, `[d]` and
  `[cd]`), `ANY`, `SOME`, `ALL` and `NONE`, `AND`, `OR` and `NOT`,
  `TRUEPREDICATE` and `FALSEPREDICATE`, the format arguments `%@`, `%K`,
  `%d`, `%i`, `%u`, `%f` and `%s` (with `l`, `ll` and `q`), argument
  arrays, `$variables` and blocks, and `NSCompoundPredicate`. `[d]` folds
  the accents of Latin letters only. Not done: `MATCHES` (regular
  expressions), function expressions, `SUBQUERY`, arithmetic, keyed
  archiving of predicates, and `NSExpression` and `NSComparisonPredicate`
  as public classes. `predicateFormat` writes Apple's documented forms
  (strings in double quotes, `NOT` before a comparison without
  parentheses); not compared character for character with a Mac.
- **Bindings: controllers, tables and outlines** (freemac (1.184),
  `NSArrayController` and table bindings from freemac (1.188),
  `NSTreeController`, `NSDictionaryController`, outline views and per-row
  column bindings from freemac (1.190), controllers from nibs, cell views'
  bindings and validation from freemac (1.191)). Text views, images, date
  pickers and segmented controls have no bindings of their own (a binding
  to a property of the same name is set by key-value coding, one way). A
  view-based table or outline from a nib whose content is bound and whose
  delegate makes no views makes each cell view from the prototype nib
  named by its column's identifier; a table with neither prototypes nor a
  delegate that makes views still draws cells. `contentArrayForMultipleSelection`,
  `NSInsertsNullPlaceholder` and editors registered with a controller
  (`commitEditing` always says YES) aren't done. Validation happens only
  with `NSValidatesImmediately`: without it a value is written as typed,
  and nothing validates it later (a Mac validates pending edits when they
  are committed). A refused value is presented as an alert through
  `presentError:` on the view's responder chain, not as a sheet on its
  window, and there is no "Discard Change" button to recover with; a
  value refused while typing continuously is skipped quietly.
  `NSHandlesContentAsCompoundValue` covers adding and removing objects
  (a new array is set whole); a change to one element's own keys isn't
  written back as a new array. `NSDeletesObjectsOnRemove` asks each
  removed object's `managedObjectContext` to `deleteObject:` it (Ferry has
  no Core Data), on the array controller only, not the tree controller.
  `infoForBinding:`'s options are only those given, not every option with
  its default, and `optionDescriptionsForBinding:` is empty. A key the
  observed object lacks leaves the view as it is unless
  `NSRaisesForNotApplicableKeysBindingOption` is given (YES raises, NO
  shows "Not Applicable"); a Mac raises by default. A text field shows
  the no-selection, multiple-values, not-applicable and null placeholders
  greyed, as its placeholder. The bindings a class exposes follow Apple's
  Cocoa Bindings Reference, not a list read from a Mac.
- **NSArrayController: written from the documentation, not compared
  with a Mac** (freemac (1.188)). What a Mac would settle: the order in
  which observers of the selection and of `arrangedObjects` hear of a
  change (Ferry: the selection's around the arranged objects'); where
  `insert:` puts the new object with nothing selected (Ferry: the top);
  where an object inserted at an arranged index goes in a sorted
  controller's content array (Ferry: before the arranged object it is put
  before); which object is selected when the selected ones are removed
  (Ferry: the one now where the first removed one was); and that an empty
  selection set by hand stays empty even with `avoidsEmptySelection`
  (Ferry selects something only when content arrives or the selected
  objects go). Automatic rearranging happens at once, not at the end of
  the event loop's turn. An unbound content that isn't mutable is
  replaced by a mutable copy when objects are added or removed. The nib
  keys of its checkboxes (`NSAvoidsEmptySelection`,
  `NSPreservesSelection`, `NSSelectsInsertedObjects`,
  `NSClearsFilterPredicateOnInsertion`,
  `NSAutomaticallyRearrangesObjects`) are a guess, untested against
  Interface Builder's output; the nibs tried were written by Ferry's own
  archiver with those keys (see `appkit_nib_controllers`). `NSObjectController`'s `add:` and `remove:` now also wait for the
  run loop's next turn, as Apple documents.
- **NSTreeController and NSDictionaryController: written from the
  documentation, not compared with a Mac** (freemac (1.190)). What a Mac
  would settle: a node with no `leafKeyPath` and no `countKeyPath` is a
  leaf when it has no children (Ferry), and with `countKeyPath` set no
  children can be added (Ferry: `canAddChild` is NO); where `add:` and
  `insert:` put the new object (Ferry: after the selected node's last
  sibling, and where the selected node is; at the top level with nothing
  selected) and that `addChild:` and `insertChild:` do nothing unless
  exactly one node that isn't a leaf is selected; that inserted objects
  are sorted into place at once; which node is selected after a removal
  (Ferry: the one now where the first removed one was, else its parent);
  which is selected when every selected node goes and
  `preservesSelection` is on (Ferry: the old index paths if they still
  lead somewhere, else the first node with `avoidsEmptySelection`); that
  a node the controller selects is shown in a bound outline with its
  parents opened, and that closing a row deselects its hidden children in
  the controller too; the order in which observers hear of a change; and
  `NSIndexPath`'s description (Ferry: `{length = 2, path = 1 - 4}`). An
  object with no children key (a dictionary without one) counts as having
  none, and a child added to it is set as a new array under the key. The
  dictionary controller sorts its pairs by key with `compare:`, names new
  keys `key`, `key1`, ... after `initialKey`, and writes a bound dictionary
  back as a new copy. The nib keys of the tree controller's key paths
  (`NSTreeContentChildrenKey`, `NSTreeContentCountKey`,
  `NSTreeContentLeafKey`) are a guess, and the dictionary controller's
  have no documented name at all; the nibs tried were Ferry's own. `NSIndexPath` isn't archived, and `NSTreeNode`'s
  `representedObject` can't be changed after it is made.
- **Controllers from nibs, cell views' bindings and validation: written
  from the documentation, not compared with a Mac** (freemac (1.191)).
  Apple doesn't document the keys of a compiled nib, so every controller
  key Ferry reads is a guess after Interface Builder's attribute names:
  `NSObjectClassName`, `NSEditable`, `NSAutomaticallyPreparesContent`,
  `NSDeclaredKeys`, `NSEntityName`, `NSAlwaysUsesMultipleValuesMarker`, the
  array controller's selection keys above, the tree controller's
  `NSTreeContent...Key`s, and the dictionary controller's `NSInitialKey`,
  `NSInitialValue`, `NSIncludedKeys`, `NSExcludedKeys`,
  `NSLocalizedKeyDictionary` and `NSLocalizedKeyTable`. The binding
  connector's keys (`NSBinding`, `NSKeyPath`, `NSOptions`, and `NSLabel`
  as "binding: key path") and the table's prototype nibs under
  `NSTableViewArchivedReusableViewsKey` follow public descriptions of the
  format. No nib saved by Interface Builder was loaded: the tests' nibs
  were written by Ferry's own keyed archiver. What a Mac would settle:
  that a view-based outline bound to a tree controller gives its cell
  views the node's represented object, not the `NSTreeNode` (Ferry: the
  represented object); that a table with prototypes and bound content but
  a delegate that doesn't make views makes them from the prototypes by
  the column's identifier, with the delegate as owner; the defaults of
  `NSConditionallySetsEnabled` (Ferry: YES, but NO for a text field,
  which is made uneditable instead through `NSConditionallySetsEditable`,
  YES) and which conditions count (Ferry: no selection, multiple values
  when they can't be edited, not applicable when the raise option is
  given, and an observed controller that isn't editable); that the
  option NO for `NSRaisesForNotApplicableKeys` shows "Not Applicable";
  that a value a validation method changes is shown at once, even while
  editing goes on; and whether a controller's selection validates against
  each selected object, stopping at the first that refuses (Ferry).
- **Formatters: text fields, cells and table cells** (freemac (1.184)).
  A text field edits its own text (there is no field editor), so
  `isPartialStringValid:proposedSelectedRange:...` (the newer form) isn't
  asked, only the older one; a refused partial string with a replacement
  puts the caret at its end. Attributed strings from a formatter
  (`attributedStringForObjectValue:withDefaultAttributes:`) aren't used.
  A Ferry control made in code has no cell (nib controls do), so its
  formatter is the control's alone. When a formatter refuses the text, a
  Ferry window's `makeFirstResponder:` returns NO and keeps the field
  first responder, as on a Mac; whether a Mac beeps exactly once there
  wasn't checked.
- **Sliders: linear and drawn Ferry's way** (freemac (1.184)). A
  circular slider is drawn and tracked as a linear one, and the knob is
  always round. The nib keys of `NSSliderCell` are those described
  publicly, not checked against Interface Builder's output.
- **Foundation for tools, regular expressions, XML and operations** (freemac (1.194), Ferry 0.21.0).
  - **NSTask**: `standardInput`, `standardOutput` and `standardError` take
    an `NSPipe`, an `NSFileHandle` or nil (inherit). A child gets its own
    process group only as the shell gives it, and there is no
    `startsNewProcessGroup`. `qualityOfService` is kept and not used.
    Programs are found as given: a launch path is not searched for in
    `PATH`, as on a Mac. A Mac program inside an app bundle is run through
    Ferry; any other file is run by this system as it is, so a script's `#!`
    line names this system's interpreter.
  - **NSFileHandle**: `acceptConnectionInBackgroundAndNotify` (sockets) is
    missing. `writeabilityHandler` is called once, soon after it is set,
    and not again each time the descriptor can take more. The
    `...ForModes:` forms accept the modes but are served in every mode.
    `fileHandleWithStandardInput` and the others are single objects that
    never close their descriptors.
  - **NSRegularExpression**: `NSDataDetector` and the other
    `NSTextCheckingResult` kinds (dates, links, addresses, spelling) are
    missing; only regular-expression results are made.
    `NSMatchingReportProgress` doesn't call the block during long searches.
    `NSMatchingWithoutAnchoringBounds` and `NSMatchingWithTransparentBounds`
    are passed to ICU and not tested.
  - **NSScanner**: `scanDecimal:` (NSDecimal) is missing. A localized
    scanner uses its locale's decimal separator and nothing else, so
    grouping separators such as `1,000` stop a number.
  - **NSXMLParser**: `parser:foundElementDeclarationWithName:model:`,
    `parser:foundAttributeDeclarationWithAttributeName:...` and
    `parser:resolveExternalEntityName:systemID:` are never called, and
    `foundIgnorableWhitespace:` only comes when libxml2 reports it (with no
    DTD it doesn't). `initWithStream:` is missing (there is no
    `NSInputStream`), and `initWithContentsOfURL:` reads files, not the
    network. With `shouldResolveExternalEntities` set, external entities
    and DTDs are loaded from files only, never over the network, and
    `allowedExternalEntityURLs` and `externalEntityResolvingPolicy` are
    kept but not enforced. Parsing stops at the first error, so
    `parser:validationErrorOccurred:` never comes. `NSXMLDocument` (the
    tree, with XPath) is still missing; several apps want it.
  - **NSOperationQueue**: every queue's operations run on the one thread,
    so `maxConcurrentOperationCount` only limits operations that finish
    later (that override `-start`), and a block operation's blocks run one
    after another in the order they were added. `underlyingQueue`,
    `qualityOfService` and `threadPriority` are kept but not used.
    `progress` counts finished operations once its `totalUnitCount` is
    set. A completion block runs on the main queue soon after its
    operation finishes, not on another thread.
    `NSInvocationOperation`'s `result` for a structure return is an
    `NSData` of its bytes, as Ferry has no `+[NSValue
    valueWithBytes:objCType:]` yet.
  - **Locks**: with one thread, `NSRecursiveLock` always succeeds, and an
    `NSLock` taken twice without anything left to unlock it prints the
    deadlock note and carries on. There is no `NSThread`, and
    `NSDistributedLock` is missing.
  - **NSCache**: nothing evicts but the limits; there is no memory
    pressure signal. `discardContentIfPossible` isn't called on eviction.
  - **NSProgress**: there's no publishing (`publish`, `addSubscriberForFileURL:`),
    no `NSProgressReporting` adoption by Ferry's own classes, and no
    `estimatedTimeRemaining` or `throughput` worked out by itself. A file
    progress's descriptions are the plain ones ("50% completed", "1 of 2"),
    not sizes in bytes.
- **Foundation pieces written from the documentation, not compared with a Mac** (freemac (1.194), Ferry 0.21.0). What a Mac would settle:

  - **NSTask**: the error codes and messages for a launch that fails
    (Ferry: `NSCocoaErrorDomain` 4 for a missing file, 257 otherwise, with
    `NSFilePathErrorKey`; `launch` raises `NSInvalidArgumentException`
    "launch path not accessible"); whether `terminationHandler` runs before
    or after `NSTaskDidTerminateNotification` is posted (Ferry: before);
    the `terminationStatus` of a child killed by a signal (Ferry: the
    signal number, with `NSTaskTerminationReasonUncaughtSignal`); and the
    exception text of `NSFileHandle` errors (Ferry: `*** -[NSConcreteFileHandle
    readDataOfLength:]: <strerror>`).
  - **NSRegularExpression**: the characters `escapedPatternForString:`
    escapes (Ferry: `\ * ? + [ ] ( ) { } ^ $ | . /`); that `rangeWithName:`
    raises `NSInvalidArgumentException` for a name the pattern lacks; which
    flags the last `NSMatchingReportCompletion` call carries; that a
    `$` followed by more digits than there are groups takes the longest
    number that names a group; the error for a bad pattern
    (`NSCocoaErrorDomain` 2048 with the pattern under `NSInvalidValue`).
  - **NSScanner**: that a failed scan leaves the location where it was even
    after skipping white space; that `scanString:intoString:` gives the
    scanned text (in the scanned string's case) rather than the argument;
    that `scanUnsignedLongLong:` refuses a minus sign; what the integer
    scans give on overflow (Ferry: the largest or smallest value, the
    location past all the digits); hexadecimal scans with a `0x` and no
    digit after it (Ferry: the `0` is scanned).
  - **NSXMLParser**: that with namespaces off `namespaceURI` and
    `qualifiedName` are nil (not empty strings); the attribute keys with
    namespaces on (Ferry: the qualified name, `x:id`, and the `xmlns`
    attributes left out); the order of `didEndMappingPrefix:` calls; that
    CDATA goes to `foundCharacters:` when the delegate lacks `foundCDATA:`
    (Ferry: it goes nowhere); the `userInfo` keys of a parse error (Ferry:
    `NSXMLParserErrorLineNumber`, `NSXMLParserErrorColumn`,
    `NSXMLParserErrorMessage`); that empty data gives error 4 and the
    delegate hears of it; that `abortParsing` calls
    `parser:parseErrorOccurred:` with code 512; that
    `parserDidEndDocument:` doesn't come after an error.
  - **NSOperation**: the exceptions for starting an operation twice, one
    that isn't ready, or adding one that is finished or already queued
    (Ferry: `NSInvalidArgumentException`, with Ferry's own wording); that
    a cancelled operation is ready even with unfinished dependencies; that
    `completionBlock` is set to nil once it has run; that
    `+currentQueue` outside any operation is the main queue; the order in
    which equal-priority operations of a suspended queue start once it is
    resumed (Ferry: the order they were added); that a barrier also
    holds back operations of higher priority added after it.
  - **NSCache**: that the delegate hears of an object that is removed or
    replaced, not only evicted; that `setObject:forKey:` with nil removes
    the key (a Mac may raise); which object goes first when the cost limit
    is passed (Ferry: the least recently used, which can be the one just
    added if it alone is over the limit); that `name` starts as "".
  - **NSProgress**: what `isFinished`, `isIndeterminate` and
    `fractionCompleted` say for a total of 0 (Ferry: not finished, not
    indeterminate, 0; 1 once something is completed); that only the first
    progress made while another is current becomes its child; the exact
    `localizedDescription` (Ferry: "N% completed", rounded to the nearest
    percent, and "" when indeterminate) and `localizedAdditionalDescription`
    (Ferry: "2 of 10"); which key-value notifications a change sends and in
    what order (Ferry: `fractionCompleted` for the progress and every
    ancestor, inner first, around the change of the unit count; and once
    more when a child is attached).
- **Steppers, date pickers, combo boxes, colour wells, popovers, path
  controls, sounds and token fields: what is left** (freemac (1.195), Ferry
  0.22.0).
  - `NSPopover`: detaching into a window (`detachableWindowForPopover:`),
    animation (`animates` is kept and ignored), and the appearance options;
    the bubble has a soft edge in place of a shadow, since Ferry draws no
    shadows.
  - `NSPathControl`: dragging files on and off, the "Choose…" item and its
    open panel (`NSPathControlDelegate`'s open-panel methods are never
    called), and editing the path.
  - `NSTokenField`: the completion list (`completionsForSubstring:` is never
    asked), tokens wrapping onto more lines, editing a token again, copying
    and pasting tokens as tokens, and tokens' menus.
  - `NSDatePicker`: the clock face is drawn but can't be set by dragging its
    hands; time zones read from nibs (Ferry can't decode `NSTimeZone` yet,
    so a nib's time zone is left out and the picker uses the default one).
  - `NSComboBox`: the list is drawn inside the window, so a long list can't
    reach past it (the same limit as pop-up buttons' menus).
  - `NSColorPanel`: a basic panel. On a display it opens GTK's colour
    chooser; it has no modes, swatches, opacity slider or eyedropper, and
    `setColor:` on the panel answers no well.
  - `NSSound`: seeking (`currentTime` is read only), changing the volume of
    a sound already playing, `playbackDeviceIdentifier`, and formats other
    than what the player takes (the duration is read only from WAV files).
  - `NSProgressIndicator` wasn't changed here; `NSProgress` isn't there.
- **Those controls: written from the documentation, not compared with a
  Mac** (freemac (1.195), Ferry 0.22.0). They were written from Apple's
  published documentation and general knowledge of how the controls behave:
  - `NSStepper`: the defaults (0 to 59 by 1, autorepeat and wrapping on),
    and that wrapping goes from the maximum to the minimum, not past it.
  - `NSLevelIndicator`: the default maximum of 2, the colours at the warning
    and critical values, and how a click between two stars rounds.
  - `NSColorWell` and `NSColorPanel`: that a second click on an active well
    lets go of the panel, that closing the panel lets go of every well, and
    that the panel's `setColor:` reaches no well.
  - `NSDatePicker`: that stepping a part wraps without carrying into the
    next (the 31st up goes to the 1st of the same month), that typing moves
    on to the next part once a part is full, that a two-digit year is taken
    as 20xx, and that setting a limit brings the date within it at once.
  - `NSComboBox`: that the arrow keys step through the items while the list
    is closed, that choosing sends the action, that completion keeps the
    case of what was typed, and the order of the notifications.
  - `NSPopover`: that a click outside a transient popover goes on to what
    was clicked as well as closing it, and where the bubble goes when there
    is no room on either side.
  - `NSPathControl`: "Computer" as the root's name, the pop-up menu's order
    (the last component first), and which components are cut first when the
    path is long.
  - `NSSound`: that `stop` tells the delegate the sound didn't finish, and
    that a named sound is kept and handed out again by `soundNamed:`.
  - `NSTokenField`: that `stringValue` joins the tokens with ", ".
  - The nib keys these classes read (`NSIncrement`, `NSAutorepeat`,
    `NSValueWraps`, `NSIndicatorStyle`, `NSDatePickerElements`,
    `NSPopUpListData`, `NSUsesDataSource`, `NSPathStyle`, `NSTokenStyle`,
    `NSBehavior`, `NSContentViewController` and the rest) are the names
    published descriptions of the format give; a nib that names something
    differently loads with the default.
  - How each control looks next to the real one: they are drawn by Ferry's
    own code in freemac's look, not compared side by side.
- **Loading URLs: what is left** (freemac (1.196), Ferry 0.23.0).
  - **Delegate queues.** With no delegate queue given, a session makes a
    serial `NSOperationQueue` of its own, as on a Mac.
    `sendAsynchronousRequest:queue:` with a nil queue uses the main dispatch
    queue.
  - **Redirects are followed silently.** `URLSession:task:willPerformHTTPRed
    irection:newRequest:completionHandler:` and
    `connection:willSendRequest:redirectResponse:` aren't asked.
    `currentRequest` stays the original request, though the response's URL
    is the final one.
  - **Authentication challenges aren't sent to the delegate.** This covers
    both server trust and HTTP auth. TLS is checked against this system's CA
    certificates by libcurl, and a failure gives -1200 or -1202.
  - No cookies (`NSHTTPCookieStorage`, `HTTPShouldHandleCookies` is stored
    but not used).
  - No URL cache (`NSURLCache`, cache policies are stored but not used).
  - No `connectionProxyDictionary`, since only the environment's proxies are
    used.
  - No background sessions.
  - No resume data (`cancelByProducingResumeData:` gives nil).
  - No stream tasks, `HTTPBodyStream`, upload from a stream,
    `NSURLSessionTaskMetrics`, `NSURLSessionWebSocketTask`, `NSURLProtocol`,
    data URLs or ftp. The schemes are http and https only. File URLs go
    through Foundation's usual file reading.
  - The `NSURLSessionResponseBecomeDownload` and `BecomeStream` dispositions
    are treated as Allow.
  - `HTTPMaximumConnectionsPerHost` and `allowsCellularAccess` are stored
    but not used. libcurl's own connection limits apply.
  - **Progress happens only while the program runs its run loop or waits in
    dispatch.** A program that sleeps or busy-waits without doing either
    sees no progress. With one thread there is no network thread to move the
    transfers along.
  - **Mac programs that link libcurl themselves**
    (`/usr/lib/libcurl.4.dylib`) aren't served. Only Foundation's own use of
    libcurl is.
  - `NSURLSession` with a delegate retains it until it is invalidated, as on
    a Mac. Nothing in Ferry warns about a session that is never invalidated.
- **Loading URLs: written from the documentation, not compared with a Mac**
  (freemac (1.196), Ferry 0.23.0).
  - The wording of the `localizedDescription` of each URL error ("Could not
    connect to the server.", "The request timed out.", "bad URL", and so
    on). It follows wording that is publicly quoted. It wasn't compared with
    a Mac for every code.
  - The default `User-Agent`. A Mac sends `<app>/<version> CFNetwork/...
    Darwin/...`, and Ferry sends `... Ferry (freemac)`.
  - **The case of names in `allHeaderFields`.** Ferry keeps the server's
    case. Newer Macs may change the case of some names.
  - **Which timeout wins when the request and the configuration both set
    one.** Ferry uses the request's unless it is the default 60 seconds.
  - The Content-Type added to a body without one: libcurl's
    `application/x-www-form-urlencoded`. A Mac is thought to do the same for
    `NSURLConnection`, but this wasn't checked for `NSURLSession`.
  - Whether a task made with a completion handler also sends
    `didCompleteWithError:` to the session's delegate. Ferry calls only the
    handler.
  - `suggestedFilename` falling back to "Unknown".
  - The text of `NSCocoaErrorDomain` 256 from
    `dataWithContentsOfURL:options:error:` ("The file “X” couldn’t be
    opened.", with X the URL's last component or host).
  - A body on a GET request is dropped. A Mac may also drop it, or may send
    it.
  - The order of `didReceiveData:` chunks against `didSendBodyData:` for an
    upload with a large response.

- **NSXMLDocument and its tree** (freemac (1.197), Ferry 0.24.0).
  - **Missing**: `objectsForXQuery:error:` and
    `objectsForXQuery:constants:error:`, XSLT
    (`objectByApplyingXSLT:arguments:error:` and the others),
    `validateAndReturnError:` (a document is only validated as it is
    read, with `NSXMLDocumentValidate`), and NSCoding for the nodes.
  - **HTML**: `NSXMLDocumentTidyHTML` is refused with an error, and
    `documentContentKind` (HTML, XHTML, text) and `MIMEType` are kept but
    change nothing in what is written.
    `NSXMLDocumentIncludeContentTypeDeclaration` is ignored.
  - **Options read but not kept**: libxml2's tree doesn't record how the
    text was written, so `NSXMLNodePreserveEntities`,
    `NSXMLNodePreserveCharacterReferences`, `NSXMLNodePreservePrefixes`,
    `NSXMLNodePreserveEmptyElements`, `NSXMLNodePreserveQuotes` and
    `NSXMLNodePromoteSignificantWhitespace` have no effect on parsing;
    entities are always written out as their text, empty elements as
    `<a></a>` (unless `NSXMLNodeCompactEmptyElement` is given when
    writing) and attributes in double quotes. Attributes and namespaces
    always keep the order they were read or added in.
  - **Entities**: external entities and an external DTD are only read
    with `NSXMLNodeLoadExternalEntitiesAlways` (or
    `NSXMLDocumentValidate`), and then only from files, never the
    network; `NSXMLNodeLoadExternalEntitiesSameOriginOnly` loads nothing.
    A reference to an entity that wasn't read is dropped from the text.
  - **URLs**: `initWithContentsOfURL:options:error:` (and `NSXMLDTD`'s)
    read files only; any other URL gives `NSCocoaErrorDomain` 262.
  - **XPath**: a result that isn't a set of nodes (`count(...)`,
    `string(...)`) is an error rather than an answer; there is no XQuery
    to give it.
  - **DTDs**: only as far as reading a document needs. Notation
    declarations in a document's DTD aren't read (libxml2 keeps them
    apart from the others); `NSXMLDTD`'s `initWithData:options:error:`
    reads the declarations as a document's internal subset would, so a
    DTD file with conditional sections or parameter entities used between
    declarations may be refused. Declarations aren't checked or used once
    the document has been read.
  - **Encodings for `XMLData`**: UTF-8, UTF-16 (little-endian, with a byte
    order mark), ISO-8859-1 and US-ASCII; a document whose
    `characterEncoding` names another encoding is written in UTF-8 under
    that name.
  - **XInclude**: `NSXMLDocumentXInclude` is passed to libxml2 and not tested.
- **Strings in one-byte encodings** (freemac (1.197), Ferry 0.24.0).
  `dataUsingEncoding:` with ASCII or ISO Latin 1 now gives one byte a
  character, and nil (or `?` with `allowLossyConversion:YES`) for a
  character the encoding lacks; before, it gave UTF-8. Other encodings
  but UTF-16 are still written as UTF-8.
- **NSXMLDocument and its tree** (freemac (1.197), Ferry 0.24.0). Chosen
  from the documentation, without a Mac to check:
  - **Writing**: no line break after the XML declaration or between a
    document's top-level nodes unless pretty printing, and none at the
    end; pretty printing indents by four spaces, puts each child of an
    element that holds no text on its own line and leaves an element with
    text (mixed content) on one line; empty elements as `<a></a>` by
    default; `>` written as `&gt;`, a carriage return as `&#13;`, and in
    attributes `"`, a line break and a tab as `&quot;`, `&#10;` and
    `&#9;`; `]]>` inside CDATA split into two sections. The XML
    declaration is written only when the document has a version, an
    encoding or is standalone, with version "1.0" if none was set, and
    `standalone="yes"` only (never `"no"`). `description` is `XMLString`.
  - **Reading**: whitespace-only text is dropped where an element has
    other children (elements, comments, processing instructions) and kept
    where it is the element's only content; without
    `NSXMLNodePreserveCDATA` a CDATA section becomes text and joins the
    text next to it; an entity's text joins the text around it.
    `version` is nil when there was no XML declaration, and
    `characterEncoding` is the encoding the declaration names (nil when
    it names none). `NSXMLDocumentTidyXML` is libxml2's recovery mode.
  - **Errors**: `NSXMLParserErrorDomain` with libxml2's codes (76 for a
    mismatched tag, 534 and the like for an invalid document, 1207 for a
    bad XPath expression), error 4 for an empty string or empty data,
    `NSLocalizedDescriptionKey` as "Line N: libxml2's message", and
    `NSXMLParserErrorLineNumber`, `NSXMLParserErrorColumn` and
    `NSXMLParserErrorMessage` in `userInfo`; a non-node XPath result is
    code 1.
  - **Trees**: `children`, `attributes` and `namespaces` are nil (not
    empty arrays) when there are none; `addAttribute:` and
    `addNamespace:` ignore a node whose name (prefix) the element already
    has; `setRootElement:` replaces the old root element where it was and
    keeps the document's comments and processing instructions (nil removes
    it); `setStringValue:` on an element replaces its children with one
    text node (none for an empty string) and does nothing on a document;
    adding a node that has a parent raises
    `NSInternalInconsistencyException`, a node of the wrong kind
    `NSInvalidArgumentException` (with Ferry's own wording);
    `setVersion:` refuses anything but "1.0" and "1.1";
    `-[NSXMLNode initWithKind:]` gives an `NSXMLElement`, `NSXMLDocument`,
    `NSXMLDTD` or `NSXMLDTDNode` for those kinds.
  - **Names and namespaces**: `prefix` is the empty string when there is
    none; an element made without a URI takes the one its prefix (or the
    default namespace) has where it is in the tree; `resolveNamespaceForName:`
    for a name without a prefix answers the default namespace;
    `predefinedNamespaceForPrefix:` knows `xml`, `xs`, `xsi` and `fn`.
  - **Places**: `level` counts ancestors (a document's root element is at
    level 1); `XPath` gives every step a position (`/catalog[1]/book[2]`,
    `text()[1]`, `@id`, `namespace::p`), with no leading `/` for a node
    outside a document.
  - **XPath**: prefixes in an expression are those declared anywhere in
    the tree, those in scope where the search starts taking precedence;
    names without a prefix match only elements in no namespace (XPath
    1.0, as libxml2 does it); a namespace node in a result that no element
    declares (the `xml` one) is a new node with no parent.
  - **Values**: an object value is written as XML Schema writes it: a
    boolean `NSNumber` as `true`/`false`, an `NSDate` as
    `1971-01-01T00:00:00Z` (UTC), `NSData` as upper-case hexadecimal;
    `setStringValue:resolvingEntities:` knows the five predefined entities
    and character references.
  - **Canonical XML**: C14N 1.0 (inclusive); an element's canonical form
    carries the namespaces in scope from its ancestors.
  - **DTD nodes**: an element or attribute declaration's `stringValue` is
    the rest of the declaration after its name (`(#PCDATA)`,
    `CDATA "plain"`), an entity's is its replacement text; a declaration
    is written as libxml2 read it until it is changed, then as Ferry
    writes it.

- **Core Animation, not done yet** (freemac (1.198), Ferry 0.25.0).
  - Shadows (`shadowOpacity` and the rest) are kept but not drawn.
  - Masks (`mask`) and filters (`filters`, `backgroundFilters`,
    `compositingFilter`) are kept but not drawn.
  - CATransition keeps its type, subtype and timing, but nothing is drawn
    for it: the change shows at once.
  - `contentsRect`, `contentsCenter` and `contentsScale` are stored but not
    used when the contents are drawn.
  - Only the 2D part of a layer's transform is drawn. Perspective and
    rotations about x or y are kept and animate, but the drawing is flat.
  - A keyframe animation's `rotationMode` is ignored.
  - A change of `contents` doesn't crossfade, and `hidden` doesn't animate:
    both change at once, as `masksToBounds` does.
  - The conic gradient type is drawn as an axial gradient.
  - There's no `CAConstraintLayoutManager`, `CAScrollLayer`,
    `CAReplicatorLayer`, `CATiledLayer`, `CAEmitterLayer`, `CAMetalLayer`
    or `CAOpenGLLayer`. `CADisplayLink` isn't there either.
  - A view's layer isn't made a sublayer of its superview's layer. Each
    view draws its own layer tree, so a view's `superlayer` is nil and
    `zPosition` doesn't reorder views.
  - The animator proxy animates numbers, points, sizes and rects only.
    Colours set through it change at once. Only views have `animator`, not
    windows, constraints or other objects.
  - `layerContentsRedrawPolicy` and `canDrawSubviewsIntoLayer` are kept but
    change nothing.
  - Hit-testing ignores where an animation of a view's layer shows it.
- **Core Animation, not compared with a Mac** (freemac (1.198), Ferry 0.25.0).
  - A spring animation's `settlingDuration` (1.28 s for the defaults) and
    the values it passes through.
  - When an implicit animation first runs. Here a layer animates its changes
    once it has been drawn on screen, or once the transaction it was made in
    is committed.
  - Where the contents gravities put an image in flipped spaces.
  - Where a text layer's lines land, and its default font (Helvetica).
  - How autoresizing shares a change of size between the margins and the
    width or height when several are flexible.
  - `contentsAreFlipped` for a view's layer.
  - The animator's default timing: the default timing function is used here
    when the context doesn't set one.
  - Whether a nested NSAnimationContext group starts from the outer group's
    duration. Here each group starts at a quarter of a second.
  - Where an animation of a flipped view's layer position shows the view.

- **Redirects, authentication, cookies and the URL cache, not done yet** (freemac (1.199), Ferry 0.26.0).
  - Proxy authentication (407) is not answered: a proxy's challenge isn't
    passed to the delegate, and `NSURLProtectionSpace`'s proxy spaces are
    only objects to store credentials under.
  - NTLM, Negotiate (Kerberos) and client certificates are not offered: a
    401 that asks only for them comes back as it is. Digest is MD5 and
    MD5-sess with `qop=auth` only (not SHA-256, not `auth-int`).
  - Credentials are kept in memory for as long as the program runs: there
    is no keychain, so `NSURLCredentialPersistencePermanent` and
    `...Synchronizable` last no longer than `...ForSession`.
  - `NSURLProtectionSpace`'s `serverTrust` is Ferry's own object that names
    the server; there is no Security framework, so nothing can look inside
    it (no `SecTrustEvaluate`, no certificate chain). A delegate can only
    accept it (`credentialForTrust:`), refuse it or leave it to libcurl's
    own check against the system's certificate authorities. Accepting it
    turns libcurl's check off for that host and port for the rest of that
    task. The question is asked once per task and host, before connecting.
  - The shared cookie storage saves to one file per program and reads it
    once; two programs, or two copies of one, don't see each other's
    changes while running. `sharedCookieStorageForGroupContainerIdentifier:`
    returns the shared storage. SameSite is kept but not acted on.
  - The URL cache keeps one entry per URL (no `Vary`), stores only GET
    responses with a 2xx status other than 206, and never serves part of a
    response. The disk store is one property list per entry, trimmed oldest
    first; its size is counted by reading the folder.
  - Cookies, credentials and the cache are not used for `file:` URLs, and
    `data:` URLs never touch them.
  - Background sessions, WebSockets and resume data are still not done.
- **Redirects, authentication, cookies and the URL cache, not compared with a Mac** (freemac (1.199), Ferry 0.26.0).
  - The constants' string values (`NSURLAuthenticationMethodHTTPBasic` and
    the others are their own names, `NSURLProtectionSpaceHTTPProxy` is
    "http", the cookie property keys are "Name", "Value", "Domain" and so
    on, HttpOnly is kept under "HttpOnly"), and which keys a cookie's
    `properties` holds.
  - The default path of a cookie made from properties without one ("/", or
    the origin URL's directory) and from a `Set-Cookie` field (RFC 6265's
    default path); a cookie with `Max-Age=0` read from a field comes back
    already expired rather than left out.
  - Whether `NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain` accepts
    cookies when a request has no main document URL (Ferry accepts them, as
    session requests rarely have one), and how a request's own `Cookie`
    field combines with the storage's (Ferry sends the request's alone).
  - The shared URL cache's sizes (512 KB in memory, 10 MB on disk) and
    where its files go (`~/.cache/<program>/URLCache`, or a relative
    `diskPath` under `~/.cache/<program>`); the cookie file's place and
    format (`~/.config/ferry/cookies/<program>.plist`, an XML property
    list).
  - Freshness without `max-age` or `Expires`: a tenth of the time since
    `Last-Modified`, as RFC 9111 suggests. Which fields of a 304 replace
    the stored ones (all but the length, type and encoding).
  - The error codes and texts chosen: -1008 for
    `NSURLRequestReturnCacheDataDontLoad` with nothing stored, -1012 for a
    connection whose challenge is cancelled (a session's is -999), -1015
    for bad base64 in a data URL, -1000 for a data URL without a comma, and
    the descriptions of -1008, -1012 and -1015.
  - NSURLConnection's first `connection:willSendRequest:redirectResponse:`
    (with no response): returning nil ends the connection with no further
    message.
  - Default handling's choice of credential: the URL's user and password
    first, then the storage's default credential for the space, or its only
    one, each tried once. When a delegate's credential is kept (persistence
    other than None), it becomes the space's default if there was none.
  - Whether a redirect to another host keeps a request's own
    `Authorization` field (Ferry copies the request's fields to the new
    request; its own credentials go only to the space they were given for).
  - The order of the delegate's messages around a 304 and around
    `willCacheResponse:` (it comes after the last data and before the task
    completes), and whether a task with a completion handler is asked
    about redirects and challenges (Ferry asks the session's delegate).
  - A `data:` URL's response: a plain `NSURLResponse`, text/plain and
    US-ASCII when no type is given, no encoding name when a type is given
    without a charset.

- **Security and CommonCrypto** (freemac (1.200), Ferry 0.27.0).
  - The keychain keeps generic and internet passwords only. Certificates,
    keys and identities are never found (`errSecItemNotFound`) and can't be
    added (`errSecUnimplemented`); there is no `SecKey`, `SecIdentity`,
    `SecAccessControl` or import and export (`SecItemImport`, PKCS#12).
  - The keychain file's encryption only keeps a secret from being read by
    accident (a glance at the file, a backup listing, a search). The key is
    in the same folder, so anyone who can read the user's files, every
    program the user runs included, can read every secret. There is no
    lock with the user's login password, no prompt before another app
    reads an item, and access groups are only attributes that are matched:
    any program can read any item.
  - Nothing is synchronized: `kSecAttrSynchronizable` is kept and matched
    and nothing more. `kSecAttrAccessible` is kept and has no effect.
    `SecKeychainSetUserInteractionAllowed` is remembered and changes
    nothing; Ferry never asks.
  - The older keychain calls are the password ones (add, find, change,
    delete, free) and `SecKeychainCopyDefault`; there are no keychain
    files of their own (`SecKeychainCreate`, `SecKeychainOpen`), no search
    objects and no `SecKeychainItemCopyContent` or `...CopyAttributesAndData`.
  - `NSURLCredentialStorage` still keeps credentials in memory only; it
    doesn't use the keychain yet.
  - Code signing reads no signature at all. Every piece of code reads as
    unsigned except for the running program's check of itself, which
    passes. Requirements are checked only for their shape (quotes and
    brackets), not parsed. There are no hosting calls, no
    `SecTaskCopyValueForEntitlement` and no Gatekeeper (`SecAssessment`).
  - Trust is checked by OpenSSL against this system's authorities: no
    revocation (OCSP, CRLs), no certificate transparency, no Mac trust
    settings, no network fetch of missing intermediates, and none of the
    Mac's own rules (certificate lifetimes, policy constraints). Only the
    SSL and basic X.509 policies exist; `SecTrustSetNetworkFetchAllowed`,
    `SecTrustCopyKey`, `SecTrustCopyExceptions` and the like are missing.
  - A server trust from `NSURLSession` fetches its certificates over a
    second, direct connection the first time it is asked about, never
    through a proxy: behind a proxy that is the only way out, it has no
    certificates and is not trusted.
  - CommonCrypto has AES only, in ECB, CBC and CTR (big-endian counter)
    modes: no CFB, OFB, XTS or GCM, no DES, 3DES, CAST, RC4 or Blowfish
    (`kCCUnimplemented`), no `CCCryptorCreateFromData`, no
    `CCKeyDerivationHMac`, and no `CC_MD2` or `CC_MD4`. AES needs this system's OpenSSL (libcrypto 3
    or 1.1): without it AES calls fail (`kCCUnimplemented`) and
    certificates can't be read; the digests, HMAC, PBKDF2 and random bytes
    are Ferry's own and always work.
  - Two other ways to read the version are not served yet. `sysctl` and
    `sysctlbyname` are missing, so a program that reads
    `kern.osproductversion` or `kern.osrelease` that way stops. And
    `@available` (`__builtin_available`) is compiled into the app as a call
    to the compiler's runtime, which looks the version up through `dlsym`;
    Ferry has no `dlsym` for Mac programs yet.
- **Security and CommonCrypto** (freemac (1.200), Ferry 0.27.0).
  - The constants' string values: the attribute keys that the older calls
    also name are their four-letter tags ("acct", "svce", "srvr"...), the
    protocols and authentication types are the older calls' codes
    ("htps", "dflt"...), and every other key and value (`kSecClass`,
    `kSecReturnData`, `kSecMatchLimitAll`, `kSecCodeInfoIdentifier`,
    `kSecAttrAccessibleWhenUnlocked`...) is its own name.
  - What `SecItemCopyMatching` returns when no `kSecReturn...` key is given
    (Ferry: `errSecSuccess` and no result, a check that an item exists),
    whether a query may ask for data with `kSecMatchLimitAll` (Ferry allows
    it), and whether a key Ferry doesn't know is refused (Ferry ignores it,
    and says so once with `FERRY_VERBOSE`).
  - Which attributes come back: Ferry returns those given when the item was
    made plus the class, the two dates and `sync`; a Mac also fills in
    defaults (an empty account, the app's access group, the accessibility).
    Uniqueness treats a missing account, service, server, path and the like
    as empty and a missing port as 0.
  - Which status comes back for an attribute of the other class
    (`errSecNoSuchAttr`), a value of the wrong type (`errSecParam`), a class
    Ferry doesn't keep (find and delete `errSecItemNotFound`, add
    `errSecUnimplemented`), deleting an item reference twice
    (`errSecInvalidItemRef`), and a secret that fails its check
    (`errSecDecode`). The texts of `SecCopyErrorMessageString` are Ferry's
    wording of the documented descriptions.
  - The older calls: the label given to a new item (the service or server
    name), what a `NULL` or empty name matches (anything), and which
    attribute tags `SecKeychainItemModifyAttributesAndData` takes.
  - Code signing: the status for a path with nothing there
    (`errSecCSStaticCodeNotFound`), for an unknown guest process
    (`errSecCSNoSuchCode`), for a requirement whose text is malformed
    (`errSecCSReqInvalid`), and the keys a Mac puts in an unsigned
    program's signing information (Ferry: main executable and Info.plist).
  - Trust: the result for a trusted chain (`kSecTrustResultUnspecified`)
    and for each failure (`kSecTrustResultRecoverableTrustFailure`), which
    OpenSSL failure maps to which status (dates, host name, everything else
    `errSecNotTrusted`), the error texts, and what
    `SecTrustGetCertificateCount` counts before evaluating (Ferry
    evaluates first).
  - CommonCrypto: `CCCalibratePBKDF`'s timing, and the status and moved
    length for every mistake, which follow the manual pages.
  - The version Ferry presents, macOS 14.7 (build 23H124, Darwin 23.6.0),
    is a choice: recent enough for apps that require macOS 11 to 14, and
    the build number is the one of a released 14.7. A real Mac's version
    file has more keys (`iOSSupportVersion`, `ProductCopyright`).

- **System queries and loading code** (freemac (1.201), Ferry 0.28.0).
  - `sysctl` serves only the names listed in the test row and the
    `hw.optional` features (`sse` to `avx512vl`, `aes`, `fma`, `bmi1`/`bmi2`
    and the others named in `src/sysctl.c`); nothing can be set (`EPERM`).
    Names such as `kern.uuid`, `hw.cpufamily`, `machdep.cpu.features`,
    `vm.swapusage`, `kern.osvariant_status` and the `net` tree answer
    `ENOENT`. `hw.cpufrequency` answers `ENOENT` where Linux has no cpufreq.
  - `KERN_PROC` answers only `KERN_PROC_PID`; listing processes
    (`KERN_PROC_ALL`, by group, terminal or user) answers `ENOTSUP`.
    `KERN_PROCARGS2` answers only for the program's own process (`EINVAL`
    for others). In `kinfo_proc`, the scheduling and memory fields
    (`p_wchan`, `p_wmesg`, `p_estcpu`, `p_pctcpu`, `e_vm`, `e_login` and the
    like) are zero; `p_comm` is the Mac program's name for this process and
    Linux's name for others.
  - `proc_pidinfo`, `proc_listpids` and the other libproc calls are not
    there; only `proc_pidpath` and `proc_name`.
  - Mach: `host_statistics64` and `host_statistics` answer only
    `HOST_VM_INFO64`, `HOST_VM_INFO` and `HOST_CPU_LOAD_INFO`, `host_info`
    only `HOST_BASIC_INFO`, `task_info` only `MACH_TASK_BASIC_INFO` for the
    program's own task (not `TASK_BASIC_INFO`, `TASK_VM_INFO` or thread
    times). The memory figures come from `/proc/meminfo` and `/proc/vmstat`;
    the compressor fields and purgeable counts are zero.
  - `getattrlist` and `fgetattrlist` serve the common attributes, the
    folder's link count, entry count and mount status, and the file's sizes
    (the resource fork's are zero), link count, block size and device type.
    Volume and fork attributes,
    `getattrlistbulk`, `getattrlistat` and `setattrlist` are not done. The
    Finder information is 32 zero bytes, the backup time zero, and the
    creation time is the modification time where the file system keeps no
    birth time.
  - Libraries and bundles loaded with `dlopen` are never unloaded:
    `dlclose` only counts, `RTLD_NODELETE` changes nothing and the
    remove-image callbacks never run. A load that fails part way leaves its
    memory mapped (it is taken off the list of images).
  - `RTLD_LOCAL` hides an image only from `dlsym`'s special handles; a
    library loaded later that binds by flat lookup (`-undefined
    dynamic_lookup`) can still find its names.
  - Only the system frameworks Ferry provides open by their
    `/System/Library/Frameworks` paths; others fail with a `dlerror` that
    says Ferry doesn't provide the framework yet. Linux libraries can't be
    opened by their own paths (the Mac names of the libraries Ferry passes
    to Linux's, such as `/usr/lib/libz.1.dylib`, do open).
  - `dladdr` on a libSystem call gives `/usr/lib/libSystem.B.dylib` as the
    file but the base of this system's C library or of Ferry, not a Mach-O
    header.
  - `dlerror` is kept per thread, but this isn't tested across threads
    (Ferry's SDK has no `pthread.h` for a test to start one).
  - `NSBundle`: `unload` returns NO, `allBundles` and `allFrameworks` are
    not there, `NSBundleDidLoadNotification` is not posted,
    `bundleWithIdentifier:` finds only bundles already made, and
    `bundleForClass:` gives the main bundle for classes of Ferry's own
    frameworks (which have no Info.plist), so AppKit's classes don't
    find an AppKit bundle. `CFBundleUnloadExecutable` does nothing.
- **System queries and loading code** (freemac (1.201), Ferry 0.28.0).
  - `sysctl.proc_translated` answers 0, as asked; a real Intel Mac may
    answer `ENOENT` instead.
  - `kern.version` (and `uname`'s version, now the same string) reads
    "Darwin Kernel Version 23.6.0: Ferry on Linux <release>;
    root:ferry/RELEASE_X86_64"; only its start follows a Mac's form. The
    numbers given to names that have no fixed number in the man page
    (`kern.osproductversion`, `hw.physicalcpu`, `machdep.cpu.*`,
    `hw.optional.*`, `sysctl.proc_translated`) are Ferry's own, from 100
    up; a Mac picks its own when it starts.
  - `hw.model` is `Macmini8,1`, chosen for an Intel Mac that runs 14.7.
    `hw.pagesize` and `hw.memsize` are 64-bit and may also be read into 4
    bytes when the value fits.
  - The layout of `struct kinfo_proc` (648 bytes, `p_flag` at 32, `p_pid`
    at 40, `p_comm` at 243, `e_ppid` at 560) is rebuilt from the documented
    field names and types, not checked against a Mac. A pid that doesn't
    exist gives success with a length of 0.
  - `proc_pidpath` with a buffer under `PROC_PIDPATHINFO_SIZE` returns 0
    with `EINVAL`; for this process it gives the program's path with links
    resolved.
  - `getattrlist` without `FSOPT_REPORT_FULLSIZE` puts the length of what
    fit in the buffer's first word; a buffer under 4 bytes is `ERANGE`;
    `ATTR_CMN_USERACCESS` comes from `access()`.
  - `dlerror`'s wording ("dlopen(path, 0x0002): tried: 'path' (no such
    file)", "dlsym(RTLD_DEFAULT, name): symbol not found", "invalid
    handle"), `dladdr`'s choice between symbols at one address (the
    external one), `RTLD_NEXT` and `RTLD_SELF` searching libSystem after
    the images, and opening an image again with `RTLD_GLOBAL` after
    `RTLD_LOCAL` making it global.
  - `_availability_version_check` with a platform other than macOS (an
    iOS version asked of macOS) answers false; 14.7.1 is not available on
    14.7.
  - `NSBundle`: `loadAndReturnError:` gives `NSCocoaErrorDomain` 4 for a
    missing program and 3587 when `dlopen` fails, with `dlerror`'s text as
    the description; with no `NSPrincipalClass`, `principalClass` is the
    first class in the program's class list; `description` ends "(loaded)"
    or "(not yet loaded)"; a bundle with no `CFBundleExecutable` uses its
    folder's name for the program, when that file is there.

- **Threads** (freemac (1.202), Ferry 0.29.0).
  - `NSBlockOperation` runs its blocks one after another, in the order
    they were added; a Mac may run them at the same time.
  - A file handle's `writeabilityHandler` is called once, not each time
    the descriptor can take more.
  - A file handle's background reads (`readInBackgroundAndNotify` and the
    like) are served by the main run loop only, and their notifications
    are posted on the main thread, whichever thread asked.
  - Dispatch sources for files and Mach ports still never fire (timer
    and data sources do, and from freemac (1.205) read, write, signal and
    process sources do too).
  - `NSDistributedLock` is missing.
  - `callStackSymbols` is empty, for a thread and for an exception.
  - Threads' priorities and qualities of service are kept and read back,
    but don't change how this system schedules them.
  - AppKit isn't made safe to use off the main thread. The first time a
    view is marked for display, a view is added or a window is drawn or
    ordered front from another thread, Ferry says so once on stderr.
  - `pthread_cancel` isn't provided; `pthread_setcancelstate`,
    `pthread_setcanceltype` and `pthread_testcancel` are accepted and do
    nothing.
- **Threads** (freemac (1.202), Ferry 0.29.0).
  - The wording of the message an `NSLock` prints when a thread locks it
    twice, or unlocks it without holding it.
  - Where a Mac hangs for ever (a lock taken twice by the same thread,
    `dispatch_sync` onto its own queue, or the main thread waiting for
    something nothing can do), Ferry stops the program with a message.
  - Which thread `NSTaskDidTerminateNotification` is posted on (here the
    run loop of the thread that launched the task), and which thread an
    operation's `completionBlock` runs on (here a worker thread).
  - The default number of operations an `NSOperationQueue` runs at once
    (64 here) and the width of the global queues' worker pool.
  - `+[NSOperationQueue currentQueue]` on a thread that isn't running an
    operation: nil here, unless it is the main thread.
  - The name of the thread that moves URL transfers, and that a session's
    delegate queue is a background queue unless the app gives one.
  - A task's state just after `cancel`: canceling, or already completed
    when the session's queue has run the completion handler in the
    meantime (the `foundation_urlsession` test now accepts either).
  - Which thread `NSHTTPCookieManagerCookiesChangedNotification` is posted
    on when a response sets cookies (here the network thread), and the
    same for `NSURLCredentialStorageChangedNotification` when a credential
    a delegate gave is kept.
  - The default stack size of a new `NSThread` (1 MiB here) and the
    smallest one `pthread_attr_setstacksize` accepts.

- **C++ programs, not done yet** (freemac (1.203), Ferry 0.30.0).
  - A Mac `operator new` or `operator delete` that the program defines
    replaces the one its own code calls, but not the one this system's
    libc++ calls from inside the library.
  - `std::ctype<wchar_t>` keeps this system's class bits. Wide character
    classes asked through `is` on that facet may differ from a Mac's.
  - Wide file streams (`wifstream`, `wofstream`) keep this system's
    layout. A Mac program that opens one may crash.
  - `seekoff` and `seekpos` overridden in a Mac program's own stream
    buffer, and called by this system's library, get Linux's calling form.
    The same goes for seeking on the standard streams' own buffers.
  - Error codes from this system's library (`filesystem`, and the
    `system_error`s it throws) carry Linux error numbers. They match a
    Mac's only up to 34 (`ERANGE`); `ENOTEMPTY` and `EAGAIN`, for example,
    don't. Ferry's own thread calls give Mac numbers, but their messages
    come from this system's `strerror`.
  - `notify_all_at_thread_exit` and `set_value_at_thread_exit` are not
    provided.
  - Ferry writes the unwind tables of all Mac images when C++ first loads.
    A program with very many functions takes longer to start and to
    throw. The unwinder looks up dynamic tables one by one.
  - An exceptional `future<void>::get` keeps one reference to the
    exception too many, so it is never freed.
  - The Mac-layout corrections assume that a Mac's libc++ lays out its
    classes as LLVM libc++ 18 does, the version they were tested on.

- **C++ programs, not compared with a Mac** (freemac (1.203), Ferry 0.30.0).
  - The tests' output was written from the C++ standard, not from a Mac
    run. These are the lines a Mac might print differently:
    - `std::terminate`'s message for an uncaught exception;
    - the text of `what()` for library errors;
    - `hardware_concurrency`;
    - the order of `unordered_map` iteration, which the tests don't print.
  - The classes a Mac's `ctype<char>` gives the characters above 127 in
    the "C" locale.
  - Whether a Mac runs `@finally` and C++ destructors in the same order
    when an `NSException` and a C++ exception meet in one frame.
  - Stream positions after `seekg` and `tellp` on a `stringstream` opened
    for both reading and writing.

- **Thread-local variables, not done yet** (freemac (1.204), Ferry 0.31.0).
  - The first 128 images with thread-local variables are reached the quick
    way. A program with more than that still works, but each use of a
    variable in a later image takes the slow way, which saves and restores
    every register.
  - The thread that calls `exit`, and the main thread when `main` returns,
    runs its thread-local destructors but keeps its storage until the
    program ends, because static destructors may still reach it.
  - Ferry keeps a small table of each thread's copies in this system's own
    thread storage, which takes about 1 KB from every thread's stack. A
    program that asks for a very small stack has that much less.
  - A library that `dlopen` fails to load part way through keeps the key
    Ferry gave it. A program can have 512 images with thread-local
    variables in all, as many as Ferry loads.
  - `dladdr` on the address of a thread's copy of a variable names nothing,
    because the copies are on the heap and in no image.

- **Thread-local variables, not compared with a Mac** (freemac (1.204), Ferry 0.31.0).
  - When the functions in an image's thread-local init section
    (`S_THREAD_LOCAL_INIT_FUNCTION_POINTERS`) run. The format's description
    only says they initialise thread-local values, and clang doesn't emit
    them. Ferry runs them once, when the image is set up, on the thread
    that loads it, before the image's C and C++ initialisers. The
    `tlv_threads` test prints that another thread doesn't see what they
    set.
  - What `dlsym` gives for the name of a thread-local variable. Ferry gives
    the address of the calling thread's copy, not the descriptor.
  - Whether the destructors of threads still running when the program
    exits are run. Ferry doesn't run them.
  - The order of a destructor registered while another one runs. Ferry
    runs the new one next, before the ones registered earlier.
  - What a destructor gets when it reaches a variable after the thread's
    storage was freed, which can only happen from a later destructor of
    this system's thread-specific data. Ferry makes a fresh copy from the
    template and frees it again.
  - The order between thread-local destructors and a thread's other
    end-of-thread work (pthread key destructors and an `NSThread`'s
    autorelease pool), which here follows this system's C library.
  - The tests' output was written from the C and C++ standards, not from a
    Mac run.

- **Sockets and streams, not done yet** (freemac (1.205), Ferry 0.32.0).
  - Bonjour: NSNetService and NSNetServiceBrowser don't use Avahi, so publishing, resolving and searching always fail with NSNetServicesUnknownError (-72000). Only TXT records work.
  - kevent accepts EVFILT_VNODE, EVFILT_EXCEPT, EVFILT_FS, EVFILT_VM and EVFILT_MACHPORT but never reports them.
  - libdispatch has no dispatch_io, and no VNODE or MACH_RECV/MACH_SEND sources.
  - TLS settings on a socket stream count only before it opens; an open stream can't be upgraded to TLS. There are no TLS server streams (kCFStreamSSLIsServer fails with -50) and no client certificates (kCFStreamSSLCertificates is ignored).
  - The SOCKS and proxy properties of streams are ignored, so streams always connect straight to the host.
  - CFRunLoopSource version 1 (Mach ports) isn't offered.
  - CFReadStreamGetBuffer works only for streams over data.
  - Run loop modes are ignored by sockets and streams: they fire in any mode of the loops they are scheduled on.
  - IPv6 (::1) was not tried here, because the sandbox has no IPv6 loopback; the test checks it only where the host has one.

- **Sockets and streams, not compared with a Mac** (freemac (1.205), Ferry 0.32.0).
  - The string values of the kCFStream and NSStream property keys, and of NSNetServicesErrorCode and NSNetServicesErrorDomain.
  - The TLS error codes: Ferry gives -9807 for every certificate trust failure and -9806 for any other failed handshake.
  - The error for a host name that can't be looked up (kCFErrorDomainCFNetwork code 2 with kCFGetAddrInfoFailureKey).
  - When a socket stream's status moves from opening to open, and when the end and has-space events come.
  - A stream into a fixed buffer returning 0 and being at its end once the buffer is full.
  - CFSocketConnectToAddress with a timeout of 0 waiting without a limit.
  - CFSocket's default flags (131: the read callback re-enabled automatically, close on invalidate).
  - The key order in TXT records made by NSNetService, "key=" for an empty value, and the order of NSNetService's failure events.
  - kqueue: the data field of EVFILT_WRITE (Ferry reports Linux's send buffer size, which Linux doubles, less what is queued), kevent failing with EINVAL for an unknown filter rather than reporting it as an EV_ERROR result, and the data counts of signal events.

- **Printing and fonts, not done yet** (freemac (1.206), Ferry 0.33.0).
  - Accessory views and controllers in the print panel, the page layout
    and the font panel aren't shown. Ferry prints a one-time warning when
    an app adds one.
  - There is no progress panel. `showsProgressPanel` is kept but changes
    nothing, and pages are drawn on the main thread whatever
    `canSpawnSeparateThread` says.
  - Printing to a real printer hands the finished PDF to GTK's print job
    when the print dialog chose the printer, and otherwise to `lp`. This
    system has no `lp` or `lpstat`, so `NSPrinter` lists no printers and a
    job sent to a printer without the dialog fails with "AppKit (Ferry):
    printing failed: …".
  - Every printer's imageable area is the whole sheet; a printer's own
    margins aren't read. `printerTypes` is empty, and `NSPrinter`'s device
    description says only that it is a printer.
  - `pagesAcross`, `pagesDown`, printing only the selection and the
    "Selection" range in the print dialog aren't supported.
  - When the print dialog is given several page ranges, they are joined
    into one range, from the first page to the last.
  - `dataWithEPSInsideRect:` and `EPSOperationWithView:...` make one page
    only.
  - With no display, the print panel and Page Setup answer Cancel unless
    `FERRY_PRINT_ANSWER` or `FERRY_PAGE_LAYOUT_ANSWER` gives an answer, and
    Ferry prints a one-time warning. On a display, only those two dialogs
    can answer themselves for the tests; the font panel can't.
  - `printOperationWithSettings:error:` in `NSDocument` itself fails with
    `NSFeatureUnsupportedError`, as Apple documents. A document class that
    prints must make its own operation, as on a Mac.
  - The font panel is GTK's font chooser. It has no font collections, no
    Styles panel (`orderFrontStylesPanel:` prints a one-time warning), no
    live preview in the text, and no colour, underline or shadow controls.
  - Changes of fonts and of the print info aren't registered with the undo
    manager.

- **Printing and fonts, not compared with a Mac** (freemac (1.206), Ferry 0.33.0).
  - The shared print info's paper comes from the locale (`LC_ALL`, then
    `LC_PAPER`, then `LANG`). The C locale and the countries that use US
    Letter give US Letter, and any other gives A4. A Mac takes it from the
    chosen printer and the region settings.
  - The defaults that Apple's documentation doesn't spell out: margins of
    72 points on the left and right and 90 points at the top and bottom,
    horizontal and vertical centring on, horizontal pagination Clip and
    vertical pagination Auto.
  - When a page is centred. Ferry centres the view only in a direction
    where it fits on one page, and puts it at the top left otherwise.
  - Fit pagination only shrinks a view; a view smaller than the page isn't
    enlarged.
  - The header and footer's layout: the job title and the date at the top,
    and "Page n of m" at the bottom, in the system font at 10 points.
  - A print operation works on a copy of the print info it is given, so
    the panel's changes reach `[op printInfo]` and not the caller's object.
  - `NSWindow`'s `print:` and `dataWithPDFInsideRect:` print the content
    view, without the title bar.
  - `NSTextView` doesn't draw the selection or the insertion point
    whenever it draws to something other than the screen. That includes
    `cacheDisplayInRect:toBitmapImageRep:`, not only printing.
  - `addFontTrait:` takes the trait off when the selected font already has
    it, so Bold and Italic toggle as the menu items' checks say.
  - Bigger and Smaller change the size by one point.
  - The font that a family name with no installed match gives. Mac names
    such as Menlo or Helvetica go to the matching kind of system font, and
    any other unknown family gives nil.
  - The text that Poppler reads back from Ferry's PDFs, which the tests
    print, and whether a Mac's PDFs would give the same line breaks.
  - `usesFontPanel` is YES for a new text view, and a text view tells the
    font manager about its selection's font only while it is the first
    responder.

- **Notifications and the Dock, not done yet** (freemac (1.207), Ferry 0.34.0).
  - Notifications are kept only while the program runs. A scheduled notification or a pending request whose time comes after the program has quit is never shown, and a click on a notification after the program has quit doesn't start it again.
  - Attachments (UNNotificationAttachment) and NSUserNotification's contentImage are kept but not shown, since the freedesktop.org specification has no way to send a picture beside the app's icon that every server reads.
  - freemac's Dock shows only a number as a badge, so a badge label that isn't a whole number above 0, such as "New" or "!", isn't shown at all.
  - freemac's Dock doesn't read the "quicklist" property yet, so the Dock menu that Ferry serves isn't shown there. Docks that read the property show it.
  - A tile's contentView is drawn by display, but the picture only becomes the windows' icon, which X11 window managers show. No dock is sent it.
  - A change to applicationIconImage isn't sent to the Dock.
  - NSWindow's dockTile (the tile of a minimised window) isn't there.
  - NSUserNotification and NSUserNotificationCenter are in Ferry's AppKit file, so a program that links only Foundation finds no such classes.
  - freemac's notification server, Beacon, has no inline reply, so there a reply button and a text input action are shown as plain buttons and the response's text is empty.
  - Critical alerts, time-sensitive interruption levels, provisional authorization, notification content and service extensions, remote (push) notifications, and secure coding of the UN classes aren't there. The settings always say authorized, with every setting enabled.

- **Notifications and the Dock, not compared with a Mac** (freemac (1.207), Ferry 0.34.0).
  - The string values of UNNotificationDefaultActionIdentifier, UNNotificationDismissActionIdentifier, UNErrorDomain and NSUserNotificationDefaultSoundName, which were taken from Apple's documentation and not read on a Mac.
  - Which notifications stay in the delivered lists: here a notification leaves them when it is clicked, answered or dismissed, and stays when its time on screen runs out.
  - When `didDeliverNotification:` is called (here once the current turn of the run loop is over), and that it is called for a notification that wasn't presented.
  - The presentation options used when the app isn't in front (here banner, list, sound and badge), and that `willPresentNotification:` and `shouldPresentNotification:` are asked only while the app is active.
  - The exception raised for a time-interval trigger of 0 or less, or under 60 seconds when it repeats (here NSInternalInconsistencyException).
  - A request with no trigger never appearing in the pending list, and an error for a request whose trigger has no next date.
  - The defaults of a new NSUserNotification (an action button titled "Show", an other button titled "Close", no sound) and when its buttons are shown: here only when their titles were set or the app's Info.plist asks for alerts.
  - That an informational attention request ends after one second, and the ids that `requestUserAttention:` returns.

**What's next.** Running the nine apps again to see where they stop now
that the views every app's nibs use are in (`NSSplitView` and `NSTabView`
came in freemac 1.155, see `appkit_panes`; `NSStatusBar` in 1.157, see
`appkit_statusbar`; `NSTableView` and `NSOutlineView` in 1.159, see
`appkit_tables`; `NSPopUpButton`, `NSSegmentedControl`, `NSSearchField`,
`NSStackView` and `NSToolbar` in 1.164, see `appkit_controls`; the
document classes, `NSAlert` and `NSWorkspace` in 1.167, see
`appkit_documents`; `NSInvocation`, forwarding, `NSJSONSerialization` and
`NSDateFormatter` in (1.170), see `foundation_invocation`,
`foundation_json` and `foundation_dates`; `NSCalendar`, `NSNumberFormatter`,
`NSISO8601DateFormatter` and the components and byte count formatters in
(1.173), see `foundation_calendar`, `foundation_numbers` and
`foundation_iso8601`; editing in tables' cells and autosaving in (1.178),
see `appkit_editing` and `appkit_autosave`; automatic key-value observing,
two-way bindings, `NSObjectController`, `NSSlider` and formatters in
(1.184), see `foundation_kvo_auto`, `appkit_binding_controls` and
`appkit_formatters`; `NSArrayController`, bindings on tables and their
columns, set mutations, collection operators and `NSPredicate` in
(1.188), see `appkit_array_controller` and
`foundation_kvc_collections`; `NSTreeController`, `NSTreeNode`,
`NSIndexPath`, bindings on outline views, per-row column bindings and
`NSDictionaryController` in (1.190), see `appkit_tree_controller`;
controllers loaded from a nib, bindings in view-based tables' cell views
and validation through bindings in (1.191), see `appkit_nib_controllers`
and `appkit_binding_validation`), then validating pending edits when they
are committed (editors registered with a controller), other calendars,
locales' own number and date data, and document versions.

## Known limits (for every milestone)

- **Apple silicon (arm64)-only apps** would need a CPU translator. Ferry runs
  x86-64 programs and the x86-64 slice of universal ones.
- **Mac App Store apps** are encrypted (FairPlay) and won't run.
- **Metal, SwiftUI, WebKit, AVFoundation** and other large frameworks are
  out of scope until M1 to M7 are solid.
- **Swift apps** need the Swift runtime; that is a later milestone after M4.

## Plan for M2 onwards (sketch)

Foundation and AppKit are big, and writing them in C would be painful. The
plan is to write them in Objective-C, compiled with `ferry-cc` into Mach-O
dylibs (`Foundation.framework/Foundation` and so on, our own code) that
Ferry's loader loads like a Mac library, running on the M1 runtime. That
needs the loader to learn dylibs (`MH_DYLIB`, export tries, dependent
libraries), which is the first task of M2. Drawing (M3) and windows (M4)
then call into Linux libraries (Cairo, Pango, Wayland/GTK) through a small
bridge in the `ferry` binary.

## Log

- 2026-11-20: read Ferry, `make check` 10/10 green, wrote this plan, started M1.
- 2026-11-20: M1 done: Objective-C runtime and blocks, `make check` 18/18.
- 2026-11-20: M1 merged (#25). M2 done: dylib loading, Foundation and CoreFoundation basics, `make check` 31/31.
- 2026-11-20: M2 merged (#28). M3 done: Core Graphics and Core Text on Cairo, Pango and HarfBuzz, NSAttributedString, `make check` 38/38.
- 2026-11-20: M3 merged (#33). M4 done: AppKit on GTK 3 (Wayland or X11), windows, views, events, controls, `make check` 41/41.
- 2026-11-20: M4 merged (#35). M5 done: keyed archives, nib loading, `NSApplicationMain` with a main nib, `make check` 43/43.
- 2026-11-22: M5 merged (#37). M6 done: real apps tried (docs/ferry-compat.md), NIBArchive nibs, missing frameworks tolerated, Grand Central Dispatch, pre-10.6 libraries, `make check` 48/48.
- 2026-11-23: M6 merged (#136). M7 done: NSImage, catchable exceptions, window and view controllers, clipboard, Open/Save panels, drag and drop, dock icons, backing scale; Flycut's crash fixed, `make check` 60/60.
- 2026-11-23: M7 merged (#171). More apps and installers: Ferry's Installer (.pkg, .dmg), scroll and text views, key-value observing, ICU, Carbon and Accessibility answers; ShiftIt runs into its event loop; MacPorts, XQuartz and Sequel Pro install, `make check` 67/67.
- 2026-11-24: Ferry 0.14.0 (freemac (1.170)): `NSInvocation`, `NSMethodSignature`, `NSProxy` and message forwarding, `prepareWithInvocationTarget:`, `NSJSONSerialization`, `NSTimeZone`, `NSLocale` and `NSDateFormatter`, `make check` 74/74.
- 2026-11-24: Ferry 0.15.0 (freemac (1.173)): `NSCalendar` (Gregorian and ISO 8601), `NSDateComponents`, `NSNumberFormatter`, `NSByteCountFormatter`, `NSISO8601DateFormatter`, `NSDateComponentsFormatter`, relative date formatting, locales' currencies, `make check` 77/77.
- 2026-11-24: Ferry 0.16.0 (freemac (1.178)): editing text cells in place in table and outline views (double click, Return, Tab and Shift-Tab, Escape, `editColumn:row:withEvent:select:`, the data source's and delegate's calls, the text field's action), `NSDocument` autosaving in place with its timer, Revert To > Last Saved Version and closing without asking, `make check` 79/79.
- 2026-11-24: Ferry 0.17.0 (freemac (1.184)): automatic key-value observing through a hidden `NSKVONotifying_` subclass, dependent keys, the observing options and `mutableArrayValueForKey:`'s change kinds; two-way bindings on text fields, buttons, pop-up buttons and the new `NSSlider` (with the null placeholder, `NSNegateBoolean`, `NSIsNil`, `NSIsNotNil` and `NSContinuouslyUpdatesValue`), `NSObjectController`, `NSUserDefaultsController`'s `values.*` and binding connectors in nibs; formatters on controls, cells and table cells being edited, `make check` 82/82.
- 2026-11-24: Ferry 0.18.0 (freemac (1.188)): `NSArrayController` (content and `contentArray`/`contentSet` bindings, `arrangedObjects` sorted and filtered, the selection with `NSMultipleValuesMarker`, adding, inserting and removing, the selection options, automatic rearranging, observing `arrangedObjects.key`); table columns bound to `arrangedObjects.key` with the table's `content`, `selectionIndexes` and `sortDescriptors` bindings, edited cells written back and column titles sorting through the controller; `mutableSetValueForKey:` and the set mutation kinds, the collection operators in key paths, removing an observer that isn't registered raising, and an `NSPredicate` subset, `make check` 84/84.
- 2026-11-24: Ferry 0.19.0 (freemac (1.190)): `NSTreeController` (children, count and leaf key paths, `arrangedObjects` as a tree of `NSTreeNode`s, `selectionIndexPaths` and `selectedObjects`, sorting, inserting, removing and moving at index paths, `add:`, `insert:`, `addChild:`, `insertChild:` and `remove:`), `NSTreeNode` and `NSIndexPath`; outline views bound to a tree controller (`content`, `selectionIndexPaths`, `sortDescriptors` and columns bound to `arrangedObjects.key`, edited cells written back); per-row `editable` and `enabled` column bindings, and no write back when the controller isn't editable; `NSDictionaryController`, `make check` 85/85.
- 2026-11-24: Ferry 0.20.0 (freemac (1.191)): `NSArrayController`, `NSTreeController`, `NSObjectController` and `NSDictionaryController` loaded from keyed nib archives with their settings and the binding connectors that join them, so a nib that binds a table or an outline to a controller works with no code; view-based tables and outlines from a nib making their cell views from the table's prototypes, with controls in a cell view bound to `objectValue.key` both ways; `NSValidatesImmediately` (`validateValue:forKeyPath:error:` and `validate<Key>:error:` before a bound value is written, a refused value presented and the control put back), `NSRaisesForNotApplicableKeys`, `NSConditionallySetsEnabled` and `...Editable` on controls, `NSAllowsEditingMultipleValuesSelection`, `NSDeletesObjectsOnRemove`, `NSSelectsAllWhenSettingContent` and `NSHandlesContentAsCompoundValue`, `make check` 87/87.
- 2026-11-24: Ferry 0.21.0 (freemac (1.194)): `NSTask`, `NSPipe` and `NSFileHandle`, `NSRegularExpression` on ICU, `NSScanner`, `NSXMLParser` on libxml2, `NSOperationQueue` and its operations, the locks, `NSCache` and `NSProgress`; ICU and libxml2 reached through a new core call, `ferry_twin_symbol`, only when first used; the desktop's notice for an app Ferry can't run now says "Ferry can't run this app yet" and keeps the app's output in `~/.cache/freemac/ferry/<app>.log` (1.193), `make check` 93/93.
- 2026-11-24: Ferry 0.22.0 (freemac (1.195)): `NSStepper`, `NSLevelIndicator`, `NSColorWell` with a basic `NSColorPanel`, `NSDatePicker` (text with a stepper, or a calendar and a clock), `NSComboBox`, `NSPopover` (and view controllers presented as popovers), `NSPathControl`, `NSSound` (through `pw-play`, `paplay` or `aplay`) and `NSTokenField`, each with its cell and read from nibs, `make check` 94/94.
- 2026-11-24: Ferry 0.23.0 (freemac (1.196)): loading http and https URLs through this system's libcurl, opened only when a program first loads one: `NSURLSession` (data, upload and download tasks, handlers and delegates, a serial operation queue of its own when none is given), `NSURLConnection`, `NSURLRequest`, `NSHTTPURLResponse`, `NSURLErrorDomain` and `NSData`'s and `NSString`'s `...ContentsOfURL:` for web addresses; a new core call, `ferry_network_symbol`, `make check` 97/97.
- 2026-11-24: Ferry 0.24.0 (freemac (1.197)): `NSXMLDocument`, `NSXMLNode`, `NSXMLElement`, `NSXMLDTD` and `NSXMLDTDNode` on libxml2 (a tree of objects that can be walked, changed, searched with XPath and written out again, pretty printed or canonical); `dataUsingEncoding:` with ASCII and ISO Latin 1 converting for real, and `dataUsingEncoding:allowLossyConversion:`, `make check` 98/98.
- 2026-11-24: Ferry 0.25.0 (freemac (1.198)): QuartzCore.framework with Core Animation basics (layers, shape, gradient and text layers, transactions, implicit and explicit animations, springs and groups), layer-backed and layer-hosting NSViews, NSAnimationContext and the views' animator, `make check` 101/101.
- 2026-11-24: Ferry 0.26.0 (freemac (1.199)): redirects decided by the delegate, HTTP Basic and Digest authentication, server trust, `NSHTTPCookieStorage` saved to disk, `NSURLCache` in memory and on disk, and `data:` URLs, `make check` 107/107.
- 2026-11-24: Ferry 0.27.0 (freemac (1.200)): Security.framework (keychain passwords, code-signing answers, certificate trust), CommonCrypto (digests, HMAC, PBKDF2, AES), and one macOS version (14.7) everywhere an app asks, `make check` 117/117.
- 2026-11-24: Ferry 0.28.0 (freemac (1.201)): `sysctl`, `dlopen`/`dlsym` and loading code after start-up, `@available` checks, `getattrlist`, the Mach host and task statistics, and NSBundle plug-ins that really load, `make check` 121/121.
- 2026-11-24: Ferry 0.29.0 (freemac (1.202)): real threads: NSThread, per-thread run loops and autorelease pools, real locks and `@synchronized`, pthreads, libdispatch on a worker pool, concurrent NSOperationQueue, a thread-safe runtime, and URL loading on a network thread of its own, `make check` 125/125.
- 2026-11-24: Ferry 0.30.0 (freemac (1.203)): C++ and Objective-C++ programs on this system's LLVM libc++ and libc++abi, loaded only when a program needs them: the standard library, exceptions across images and mixed with Objective-C's, and C++ threads on a Mac's layouts, `make check` 131/131.
- 2026-11-24: Ferry 0.31.0 (freemac (1.204)): Mac thread-local variables (`__thread`, `_Thread_local`, C++ `thread_local`) through Ferry's own `_tlv_bootstrap` and `_tlv_atexit`, per thread and per image, in libraries opened with `dlopen` too, with destructors at thread exit, `make check` 138/138.
- 2026-11-24: Ferry 0.32.0 (freemac (1.205)): BSD sockets with the Mac's layouts, kqueue and kevent on epoll, dispatch read, write, signal and process sources, CFSocket and run loop sources, CFStream and NSStream with TLS checked by SecTrust, and NSNetService's TXT records (no Bonjour yet), `make check` 144/144.
- 2026-11-24: Ferry 0.33.0 (freemac (1.206)): printing (NSPrintInfo, NSPrintOperation, pagination, PDF output, GTK's print and page setup dialogs), NSDocument's Print… and Page Setup…, and NSFontManager with the font panel (Bold and Italic in text views), `make check` 151/151.
- 2026-11-24: Ferry 0.34.0 (freemac (1.207)): UNUserNotificationCenter and NSUserNotificationCenter through the freedesktop notification server, with actions, replies and delegates; NSDockTile badges, attention requests and the Dock menu through LauncherEntry, `make check` 157/157.
