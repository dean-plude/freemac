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

- Not written: transparency layers, patterns, masks (`CGImageMaskCreate`,
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
  drop, input methods (text fields take what
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
- **Some apps' core features can't work on Wayland as written**: global hotkeys (Carbon's `RegisterEventHotKey`), watching other apps' key presses (KeyCastr) and moving other apps' windows through the Accessibility API (ShiftIt, Spectacle). Those need a desktop-side service, and are out of M6's scope. (Global hotkeys and moving other apps' windows came in freemac 1.215, Ferry 0.41.0, through Strata; watching other apps' key presses stays out of reach.)
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
  Hotkeys are pressed on freemac's desktop, where Strata binds them and sends each press to the app alone, and are registered but never pressed elsewhere (Wayland doesn't let one app see another's keys); the keyboard layout has no Mac layout data; the process is trusted for Accessibility once the user allows it, and moves other apps' windows through Wayfire's IPC (freemac 1.215, Ferry 0.41.0); every address is reachable.
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
check` runs 87 tests (60 at M7, 69 before freemac 1.170, 74 before
freemac 1.173, 77 before freemac 1.178, 79 before freemac 1.184, 82
before freemac 1.188, 84 before freemac 1.190, 85 before freemac
(1.191)), all passing.
The new or extended ones:

| Test | Proves |
| --- | --- |
| `installer` | A package made by `tests/tools/make_pkg.py` (two components, a gzip/`070707` payload and a `pbzx`/`070701` one, an RTF licence, an HTML welcome, a member that climbs out, a link): `--info`, `--install` into test folders (apps and the rest in the right places, nothing outside them, the link kept), the same package cut short failing cleanly, and `ferry Bundled.app` running the bundle's program |
| `atomics` | Spin locks, unfair locks, the `OSAtomic` calls' results, and stderr still working after a failed `freopen` of it |
| `twins` | now also ICU's regular expressions through `libicucore` |
| `foundation_kvo` | Key-value observing: options, contexts, key paths, will/didChange around a setter, `setValue:forKey:`, removal, an observed object going away |
| `foundation_runloop` | now also cancelling delayed performs, by object and by selector |
| `appkit_bindings` | now also bindings following changes, and `NSUserDefaultsController` (applied at once, held until saved, reverted); from freemac 1.184 a view's exposed bindings include `NSView`'s `hidden` and `toolTip` |
| `foundation_kvo_auto` | (freemac 1.184, Ferry 0.17.0) automatic key-value observing: the hidden `NSKVONotifying_` subclass made when an object first gets an observer (`class` still the original, `isMemberOfClass:`, the description), setters of objects, integers, `BOOL`, `double`, rects, points and ranges announced; `automaticallyNotifiesObserversForKey:` and `automaticallyNotifiesObserversOf<Key>`; instance variables set by `setValue:forKey:` announced; the subclass kept after the last observer goes; a subclass of an observed class; dependent keys by `keyPathsForValuesAffectingValueForKey:` and `keyPathsForValuesAffecting<Key>`, through a to-one relationship; key paths through a replaced object (the old one no longer followed); the Prior, Initial, Old and New options; `mutableArrayValueForKey:` through indexed accessors, a setter and an instance variable, with insertion, removal and replacement at indexes; `willChange:valuesAtIndexes:forKey:` by hand; nested changes; mutable dictionaries and `NSUserDefaults`; key-value coding's search order, `setValuesForKeysWithDictionary:`, `setNilValueForKey:` and the undefined-key exceptions |
| `appkit_formatters` | (freemac 1.184, Ferry 0.17.0) formatters on text fields: the value shown with `stringForObjectValue:`, editing started from `editingStringForObjectValue:`, a keystroke `isPartialStringValid:` refuses (a beep, `control:didFailToValidatePartialString:errorDescription:`), Return and the end of editing reading the text with `getObjectValue:forString:errorDescription:`; a string it can't read beeping, asking `control:didFailToFormatString:errorDescription:` and keeping the editing going (or kept as the value when the delegate says so); `control:isValidObject:` refusing a value; focus with no typing keeping the value; `abortEditing` and `validateEditing`; an `NSNumberFormatter`; a cell's formatter, kept by its copy; a cell-based table's column cell formatter showing the value, starting the editing and giving the data source a number, a bad entry beeping once and Escape |
| `appkit_binding_controls` | (freemac 1.184, Ferry 0.17.0) bindings that follow and write back: a text field's value (written when the editing ends or on Return, not when nothing was typed, or as it is typed with `NSContinuouslyUpdatesValueBindingOption`), the null placeholder shown as the field's placeholder and an emptied field writing nil, a check box through `NSNegateBoolean`, `enabled` and `enabled2` combined with AND and `hidden` and `hidden2` (through `NSIsNotNil`) with OR, a key path through a to-one relationship, pop-up buttons' `content`, `selectedObject`, `selectedIndex` and `selectedValue` (chosen with the mouse and written back, new content), a slider kept in its range and clicked; `NSObjectController` with no content (the no-selection placeholder, the binding's own), its `selection.name` followed and written, a new content, `remove:` and `add:` (from freemac 1.188 carried out on the run loop's next turn); `NSUserDefaultsController`'s `values.*` changed by a click, in the defaults and through the controller; exposed bindings, `infoForBinding:` and the markers; and a nib (`Bindings.nib`) with binding connectors to an object controller and the shared defaults controller, its slider snapping to its tick marks |
| `foundation_kvc_collections` | (freemac 1.188, Ferry 0.18.0) `mutableSetValueForKey:` through a class's set accessors (one object at a time, and `add<Key>:` for a union), through its setter and straight to an instance variable, with the set mutation kinds observers hear (insertion of what a union adds, removal of what a minus or an intersect takes away, replacement for `setSet:`) and the old, new and prior options, and `willChangeValueForKey:withSetMutation:usingObjects:` by hand; the collection operators `@count`, `@sum`, `@avg`, `@min`, `@max`, `@unionOfObjects`, `@distinctUnionOfObjects`, `@unionOfArrays`, `@distinctUnionOfArrays` and `@distinctUnionOfSets` on arrays, sets and through a to-one key, with nil values, empty collections and an unknown operator; arrays and sets answering and taking keys; removing an observer that isn't registered (or with the wrong context) raising `NSRangeException`; `NSPredicate`'s format strings (comparisons, `[c]`, `[d]`, `LIKE`, `BETWEEN`, `IN`, `ANY`, `ALL`, `NONE`, `AND`, `OR`, `NOT`, the format arguments and an argument array), `$variables`, blocks, `NSCompoundPredicate`, filtering arrays and sets, and formats it can't read |
| `appkit_array_controller` | (freemac 1.188, Ferry 0.18.0) `NSArrayController`: its defaults, content given (an array and a set) and bound (`contentArray`, changed through the owner's indexed accessors and by the owner), `arrangedObjects` sorted and filtered, `selectionIndexes` and `selectedObjects`, `selection.name` with the multiple-values, no-selection and not-applicable markers and `alwaysUsesMultipleValuesMarker`, writing through the selection, `preservesSelection`, `avoidsEmptySelection`, `selectsInsertedObjects`, `clearsFilterPredicateOnInsertion`, adding, inserting at an index and removing, `add:`, `insert:` and `remove:` on the run loop's next turn, `selectNext:` and `selectPrevious:`, `canAdd`, `canInsert` and `canRemove`, `automaticallyRearrangesObjects`, observers of `arrangedObjects.name`, `arrangedObjects.@count`, `selection.name` and `selectionIndexes`, and the `selectionIndexes` binding both ways; a cell-based table whose columns are bound to `arrangedObjects.key`: its content, `selectionIndexes` and `sortDescriptors` bound for it, the columns' sort descriptors (and `NSCreatesSortDescriptorBindingOption`), the null placeholder, a column title bound, clicks and command-clicks selecting in the controller and the controller's selection shown, a model change redrawn, clicks on column titles sorting the controller, cells edited in place written back, rows added and removed |
| `appkit_tree_controller` | (freemac 1.190, Ferry 0.19.0) `NSIndexPath` (adding and removing an index, `indexAtPosition:` past the end, `getIndexes:range:`, equality, hashing, `compare:` and sorting, `section` and `item`); `NSTreeNode` on its own (children through `mutableChildNodes`, observed, a node taken from its old parent, `parentNode`, `indexPath`, `descendantNodeAtIndexPath:`, sorting recursively); `NSTreeController`: its defaults and exposed bindings, content with `childrenKeyPath`, a leaf decided by having no children, by `leafKeyPath` or by `countKeyPath`, `arrangedObjects` as a tree of nodes kept across rearranging, `selectionIndexPaths`, `selectedObjects`, `selectedNodes` and `selection.name` with the multiple-values marker, writing through the selection, sorting level by level with `preservesSelection` on and off, the model adding, removing and replacing children (observed through its indexed accessors), inserting at an index path, removing (a node and its child at once), an index path that has no parent raising, `moveNode:toIndexPath:`, `add:`, `insert:`, `addChild:`, `insertChild:` and `remove:` on the run loop's next turn, `canAddChild` on a leaf, with `countKeyPath` and with no selection, `canAdd` and the rest when not editable, the `contentArray` and `selectionIndexPaths` bindings both ways, and dictionaries as the objects; an outline view whose columns are bound to `arrangedObjects.key`: its `content`, `selectionIndexPaths` and `sortDescriptors` bound for it, its items the controller's nodes, rows opened by code and by a click on a chevron, clicks and command-clicks selecting in the controller, a node the controller selects shown with its parents opened, a model change redrawn, clicks on column titles sorting the controller with open rows kept open, cells edited in place written back (text and a number), no editing and no write back when the controller isn't editable, `addChild:` and `remove:` shown; a table column's per-row `editable` (through `NSNegateBoolean`) and `enabled` bindings for text cells and check boxes, and `NSConditionallySetsEditable`; `NSDictionaryController`: its defaults, a bound `contentDictionary` with included, excluded and localized keys, a pair's value and key changed and written back, `add:` making unique keys, `remove:`, a new dictionary from the model, and an unbound mutable dictionary changed in place |
| `appkit_nib_controllers` | (freemac 1.191, Ferry 0.20.0) A nib written in the test with Ferry's own `NSKeyedArchiver` (an `NSIBObjectData` with custom objects, outlet and binding connectors, and a window template), loaded with `NSNib` and nothing bound in code: an `NSArrayController` (object class, editable, prepares content, avoids empty selection, preserves selection, selects inserted objects, clears the filter on insertion, rearranges automatically, always uses the multiple-values marker, declared keys), an `NSTreeController` (children and leaf key paths), an `NSObjectController` (an entity name, and content prepared at `awakeFromNib`) and an `NSDictionaryController` (initial key and value, included, excluded and localized keys) read back; their `contentArray`, `sortDescriptors` and `contentDictionary` bound to File's Owner by connectors; a cell-based table whose columns are bound to `arrangedObjects.key` (content, selection and sorting bound for it); a view-based table and a view-based outline with no delegate and no data source, bound to the controllers, making their cell views from the table's own prototype nibs (`NSTableViewArchivedReusableViewsKey`), with a text field and a check box in each cell view bound to `objectValue.key`; the rows, a click selecting through the controller, a field bound to `selection.title` and its no-selection and multiple-values placeholders, the field edited and the table and cell views rearranged, a cell view's field edited in place and its check box clicked (written back), the model changed under the views, `add:` and `remove:`, the outline's cell views given the nodes' represented objects and edited in place, `addChild:`, the object controller's prepared dictionary edited through a field with a null placeholder, and the dictionary controller's pairs written back |
| `appkit_binding_validation` | (freemac 1.191, Ferry 0.20.0) `NSValidatesImmediatelyBindingOption`: values typed into fields bound through an object controller's and an array controller's selection put to `validate<Key>:error:` before they are written; a refused one presented (the application delegate's `application:willPresentError:` sees it, and the alert is answered) and the field showing the model's value again, a changed one (trimmed, a string made a number, clamped) written changed and shown, nothing asked without the option; the selection proxies' own `validateValue:forKeyPath:error:`; the same for a cell-based table's columns and for a field in a view-based table's cell view bound to `objectValue.age`; `NSRaisesForNotApplicableKeysBindingOption` absent (the field kept), NO ("Not Applicable", not editable) and YES (raises); a field made uneditable and a check box disabled with no selection, with a controller that isn't editable (followed as it changes) and with multiple values when `NSAllowsEditingMultipleValuesSelection` is NO; an `enabled` binding taken together with them; `NSConditionallySetsEnabled` and `...Editable` set by hand; the views' own settings given back when unbound; `NSDeletesObjectsOnRemove` (through the objects' `managedObjectContext`), `NSSelectsAllWhenSettingContent`, and `NSHandlesContentAsCompoundValue` into an owner's immutable array and into the user defaults through `NSUserDefaultsController` |
| `foundation_task` | (freemac 1.194, Ferry 0.21.0) `NSTask`, `NSPipe` and `NSFileHandle`: running this system's programs with arguments, environment, working directory and pipes, background reads, readability handlers, the termination handler and notification, waiting, signals and exit status |
| `foundation_regex` | (freemac 1.194, Ferry 0.21.0) `NSRegularExpression` on ICU: options, groups and named groups, the searches, templates, escaping, and `NSString`'s `NSRegularExpressionSearch` |
| `foundation_scanner` | (freemac 1.194, Ferry 0.21.0) `NSScanner`: integers with overflow, hexadecimal, floating point, a locale's decimal separator, strings, character sets, case and skipped characters |
| `foundation_xmlparser` | (freemac 1.194, Ferry 0.21.0) `NSXMLParser` on libxml2: elements, attributes, text, CDATA, comments, processing instructions, entities, namespaces, errors with codes and lines, aborting, nested parses |
| `foundation_operation` | (freemac 1.194, Ferry 0.21.0) `NSOperationQueue` with block, invocation and an app's own operations: dependencies, priorities, cancelling, completion blocks, suspending, barriers, key-value notifications, waits; the locks |
| `foundation_cache` | (freemac 1.194, Ferry 0.21.0) `NSCache` (count and cost limits, least recently used first, the delegate) and `NSProgress` (trees of progress, fraction completed with key-value notifications, cancel and pause) |
| `appkit_more_controls` | (freemac 1.195, Ferry 0.22.0) Steppers by click, keys and holding the mouse down (autorepeat, wrapping or stopping at the ends, the value kept within the limits); level indicators in each style (tick marks and their rectangles, a click or drag setting the level when editable, continuous actions, the arrow keys, rating stars); colour wells taking turns with the shared colour panel (one active well, `changeColor:` sent to the active well and down the responder chain, a second click letting go, closing the panel letting go); date pickers in text-and-stepper style (each part stepped by the arrows without carrying into the next, typed digits moving on to the next part, a year typed short, AM and PM, the stepper, the minimum and maximum, the delegate's validation) and graphical style (days clicked, months turned, a range dragged, the clock beside the calendar); combo boxes with their own items and with a data source (the list opened by the button or the keys, chosen by Return or a click, closed by Escape or a click outside, the four notifications in order, completion keeping what was typed, the arrows stepping through the items with the list closed); popovers in each behaviour (shown beside a rectangle on any edge, moved to the other side when there is no room, kept in the window, closed by Escape, a click outside, `performClose:` or the delegate's refusal, the four notifications) and view controllers presented as popovers; path controls (components from a file URL and a web address, clicks and double clicks, own items, a placeholder, long paths cut in the middle, the pop-up style's menu); `NSSound` played through a stand-in player (named sounds, a sound from data, the volume, pause and resume, stop, looping, the delegate told whether it finished); token fields (tokens made at commas or at a character set, Return and end of editing, Backspace selecting then removing a token, the delegate's represented objects, display strings and refusals); and all of them loaded from a nib with their targets and actions |
| `foundation_urlsession` (ARC, dispatch) | (freemac 1.196, Ferry 0.23.0) `NSURLSession` against a server on 127.0.0.1: data tasks with handlers (task state before and after `resume`, handler run after `resume` returns), `NSHTTPURLResponse` (status, MIME type, charset, length, headers in any case, suggested name), POST/PUT/DELETE/HEAD with bodies and headers, 404 and 204 not being errors, redirects, gzip, the URL errors (can't connect -1004, timeouts -1001 while connecting and mid-body, no host -1000, unsupported URL -1002, redirect loop -1007, connection lost -1005, cancel -999), cancelling before and after `resume`, tasks together in a dispatch group, the configuration and session headers, delegates (data, refused response, upload progress, download progress, invalidation), download tasks to a temp file removed after the handler, upload tasks, and a handler under `dispatch_main()` |
| `foundation_urlconnection` (manual retain/release) | (freemac 1.196, Ferry 0.23.0) `NSURLConnection`: synchronous (200, 404, closed port), asynchronous (on the main queue or a private one; a redirect; a bad URL), with a delegate (PATCH with a body, a closed port, `startImmediately:NO`, cancel), `canHandleRequest:`; `NSData` and `NSString` `...ContentsOfURL:` over http (charset from the response, Cocoa error 256 with the URL error underneath); requests and responses made by hand (header case, `addValue:`, copies, Content-Type parsing, status texts) |
| `libcurl loaded only when loading URLs` (check in `run.sh`) | (freemac 1.196, Ferry 0.23.0) a Foundation program that loads no URL never opens libcurl (`LD_DEBUG`) |
| `foundation_xmldocument` | (freemac 1.197, Ferry 0.24.0) `NSXMLDocument` on libxml2: a document with a declaration, a comment, a processing instruction, a default and a prefixed namespace and an entity read into objects (kinds, names, local names, prefixes, URIs, namespaces, attributes, string values, indexes and levels, siblings, next and previous nodes, `elementsForName:` with a prefix, `elementsForLocalName:URI:`, `attributeForLocalName:URI:`, resolving namespaces and prefixes); written out compact, pretty printed, with compact empty elements and single quotes; XPath (by local name, with a prefix, attributes, a relative path, processing instructions, comments, the document, the namespace axis, a result that isn't nodes and a bad expression); the tree changed (inserting, removing, replacing, `setChildren:`, `insertChildren:atIndex:`, a duplicate attribute ignored, removing an attribute, setting string values, normalizing text nodes, a namespace added and a node detached) and XPath and `XMLString` seeing every change; a node that has a parent and an attribute added as children (exceptions); documents built in code, written as ISO-8859-1, US-ASCII (character references) and UTF-16 data and read back; `setRootElement:`; object values (a number, a date, a boolean); resolving entities; CDATA with `]]>` in it; `NSXMLNode` making an `NSXMLElement` for its kind; an element from a string, copied deeply; whitespace and CDATA with and without the preserve options; a document that isn't well formed (error 76 and its line), tidied, empty (error 4) and invalid with `NSXMLDocumentValidate`; a DTD with public and system ids, an entity, an element and an attribute declaration (kinds, values, written back, changed), a declaration made from a string, a predefined entity; canonical XML with and without comments, and of an element; data in ISO-8859-1, a file URL, a web URL refused; a document class whose `replacementClassForClass:` makes its own elements |
| `quartzcore_layers` | (freemac 1.198, Ferry 0.25.0) Layer geometry (frame from bounds, position, anchor point and transform, through scaling and a quarter turn), key-value coding of layer properties and of keys of the caller's own, a subclass's `@dynamic` properties with `defaultValueForKey:` and `needsDisplayForKey:`, sublayer order and replacing, point conversion and hit-testing; drawing checked pixel by pixel: background, border, rounded corners and `maskedCorners`, opacity per layer and as a group, hidden, `masksToBounds`, transforms, `sublayerTransform`, `geometryFlipped`, `zPosition`, an image's contents with the gravities, the delegate's `drawLayer:inContext:` and `displayLayer:`, `needsDisplayOnBoundsChange`, shape layers (fill, stroke, stroke start and end, dashes, even-odd), axial and radial gradients, and text layers |
| `quartzcore_animations` | (freemac 1.198, Ferry 0.25.0) One animation on the real run-loop clock, then everything on the test clock: the transform functions, the named timing functions, implicit animations and when they start, transactions (duration, disabling actions, nesting, the completion block), actions from the `actions` dictionary and the delegate, `onOrderIn`; basic animations (fill modes, replacing, `byValue`, additive, autoreverse, cumulative repeats, a later begin time, speed, a key path into the transform); keyframe animations in every calculation mode, with key times, timing functions and a path; groups; springs; the delegate's start and stop messages; a layer drawn while a property animates |
| `appkit_layers` | (freemac 1.198, Ferry 0.25.0) A view's backing layer and its geometry, `makeBackingLayer`, a layer-backed view drawn with its layer's background, border, corner radius, opacity and sublayers (in plain and flipped views), `wantsUpdateLayer`/`updateLayer`, a hosted layer; `NSAnimationContext` groups with the view's `animator` for `frame` and `alphaValue`, the completion handler, the default duration outside a group, a duration of 0, a new animation taking over, the `animations` dictionary; implicit layer animations only with `allowsImplicitAnimation`; an explicit animation of a view's layer moving where the view is drawn; a window drawing a layer-backed content view |
| `foundation_urlredirects` (ARC) | (freemac 1.199, Ferry 0.26.0) Redirects decided by the delegate, against the server on 127.0.0.1: `URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:` following (also answered later, from the run loop), changing (another URL and header) and refusing a redirect (the 3xx response and its body come back), two redirects in a row, a relative `Location`, what 301, 302, 303, 307 and 308 do to a POST and 303 to a PUT, `currentRequest` before and after; `NSURLConnection`'s `connection:willSendRequest:redirectResponse:` (first with no response, then per redirect; refusing the redirect; refusing the first request); synchronous calls and `stringWithContentsOfURL:` following redirects |
| `foundation_urlauth` (ARC) | (freemac 1.199, Ferry 0.26.0) `NSURLCredential`, `NSURLProtectionSpace` (equality, proxies), `NSURL`'s `user` and `password`, `NSURLCredentialStorage` (credentials per space, the default one, persistence None not kept, removal, its notification); HTTP Basic and Digest (MD5, qop=auth) challenges answered by the task delegate with each disposition (a credential, one given later, a wrong one then cancel, none, reject the space, default handling), previous failure counts and proposed credentials, the URL's user and password, a credential kept for the session and used afterwards by default handling, a session-level method not asked about a password, an ephemeral session's own storage; `NSURLConnection`'s `connection:willSendRequestForAuthenticationChallenge:` with each sender message (cancel gives -1012) and the older `canAuthenticateAgainstProtectionSpace:` and `didReceiveAuthenticationChallenge:` pair |
| `foundation_urlcookies` (ARC, run twice) | (freemac 1.199, Ferry 0.26.0) `NSHTTPCookie` from properties (and without a name or domain, from an origin URL) and from `Set-Cookie` fields (Domain, Path and its default, Expires, Max-Age, Secure, HttpOnly, a foreign domain refused, several in one field), `requestHeaderFieldsWithCookies:`; the shared `NSHTTPCookieStorage` (matching by domain, path and scheme, replacing, deleting, sorting, the accept policy with and without a main document, its notification, the file it saves); sessions sending and keeping cookies (paths, a cookie the server expires, a request that turns cookies off or has its own Cookie field, a cookie set by a redirect, `dataWithContentsOfURL:` and `NSURLConnection` sharing them, `HTTPShouldSetCookies` off, the policy Never, no storage, an ephemeral session's own); a second run reading the lasting cookies back, and the file going when the last is deleted |
| `foundation_urlcache` (ARC, run twice) | (freemac 1.199, Ferry 0.26.0) `NSURLCache` by hand (memory and disk, a second cache on the same files, memory-only and not-allowed entries, the fragment ignored, removal) and through sessions, counted by the server: `max-age`, `max-age=0`, `Expires`, `ETag` and `Last-Modified` revalidated with a 304, `no-store`, a POST; each request cache policy, the configuration's policy, the request's `Cache-Control: no-cache`; the twentieth-of-the-cache size rule; no cache; `URLSession:dataTask:willCacheResponse:completionHandler:` keeping, refusing and changing the entry; downloads not kept; the shared cache through `dataWithContentsOfURL:` and `NSURLConnection`, and its files; a second run answered from disk without the network |
| `foundation_urldata` (ARC) | (freemac 1.199, Ferry 0.26.0) `data:` URLs (RFC 2397) through `NSURLSession`, `NSURLConnection`, `NSData` and `NSString`: plain and percent-encoded, base64, a charset, a MIME type, a fragment, bad base64 (-1015) and no comma (-1000), `canHandleRequest:` |
| `foundation_urltrust` (ARC; needs openssl) | (freemac 1.199, Ferry 0.26.0) An https server whose certificate run.sh made, which the system doesn't trust: no delegate (-1202), the session-level challenge with default handling (-1202), cancel (-999) and a trust credential (the page loads), a password challenge after it, the task-level method alone, `NSURLConnection` accepting it, `dataWithContentsOfURL:` refusing it |
| `commoncrypto_digests` | (freemac 1.200, Ferry 0.27.0) MD5, SHA-1, SHA-224, SHA-256, SHA-384 and SHA-512 against RFC 1321's suite and FIPS 180's examples (the empty message, "abc", the 448- and 896-bit messages, a million "a"), each one-shot and fed in every split; HMAC against RFC 2202 and RFC 4231 (keys shorter and longer than a block), one-shot and incremental; PBKDF2 against RFC 6070 and RFC 7914; `CCCalibratePBKDF`; `CCRandomGenerateBytes` and `CCRandomCopyBytes` |
| `commoncrypto_cryptor` | (freemac 1.200, Ferry 0.27.0) AES through this system's OpenSSL: FIPS 197's ECB examples for 128, 192 and 256-bit keys, SP 800-38A's CBC (AES-128 and AES-256) and CTR (AES-128) examples, PKCS#7 padding and its lengths, `CCCrypt` and the `CCCryptor` calls fed in pieces, `CCCryptorReset`, `CCCryptorGetOutputLength`, and the documented status for a spoilt padding, a buffer too small (with the size needed), unaligned input, a wrong key size, an unknown option and an algorithm or mode Ferry doesn't have |
| `foundation_sysversion` | (freemac 1.200, Ferry 0.27.0) One macOS version (14.7, build 23H124) everywhere: `/System/Library/CoreServices/SystemVersion.plist` read as a property list, with stdio (also through a doubled slash), with `open` and `stat`, refused for writing (`EACCES`, and `access` says so); `uname`'s Darwin 23.6.0; `NSProcessInfo`'s `operatingSystemVersion`, `operatingSystemVersionString` and `isOperatingSystemAtLeastVersion:`; `Gestalt`'s `sys1`, `sys2`, `sys3` and `sysv`, and an unknown selector |
| `foundation_sysversion_carbon` | (freemac 1.200, Ferry 0.27.0) The same program linked against Carbon instead of CoreServices, for `Gestalt` |
| `security_keychain` | (freemac 1.200, Ferry 0.27.0) Generic and internet passwords in a home of the test's own, run twice: `SecItemAdd`, `SecItemCopyMatching` (data, attributes, a reference, a persistent reference, several at once, one or all, case-insensitive), `SecItemUpdate` and `SecItemDelete`; the documented status for a duplicate, nothing found, a wrong type, a missing class, another class's attribute, a match limit where none belongs, a certificate (not kept); synchronizable items found only when asked for; the older `SecKeychain...` calls on the same items; the folder at mode 0700 and its files at 0600, no secret in the clear in the file, a tampered secret refused (`errSecDecode`); items kept for the second run; `SecCopyErrorMessageString`; `SecRandomCopyBytes` |
| `security_code` | (freemac 1.200, Ferry 0.27.0) Code signing as Ferry answers it: `SecCodeCopySelf`, its static code and a static code made for the executable's path pass `SecCodeCheckValidity` and `SecStaticCodeCheckValidity`, with and without a requirement; `/bin/sh` reads as unsigned (`errSecCSUnsigned`, also as a `CFError`); signing information with no identifier, team or certificates; no designated requirement; the program found by its process id and no other; a path with nothing there; requirements kept as text and malformed ones refused |
| `security_code message` | (freemac 1.200, Ferry 0.27.0) With `FERRY_VERBOSE` set, each of the two code-signing answers is said once on stderr, however often it is given |
| `security_selfcheck` | (freemac 1.200, Ferry 0.27.0) An app's check of its own signature from inside its bundle: the running code is the bundle, static codes made for the bundle's and the executable's paths pass, the signing information carries the bundle's Info.plist and main executable but no identifier |
| `security_trust` (needs openssl) | (freemac 1.200, Ferry 0.27.0) The test server's own certificate: read from DER (garbage refused), its subject summary and common name, its data back, `CFEqual`; a trust refused against the system's authorities (`errSecNotTrusted`), accepted with it as the anchor (alone and with the system's), refused in 2000 and 2100 (not yet valid, expired) and for another host name; basic X.509; `SecTrustEvaluate`, `SecTrustGetTrustResult`, the policies, the chain, `SecTrustEvaluateAsyncWithError`; and in an `NSURLSession` challenge, the server trust's certificates read from the server, refused as received and accepted once given its own certificate as the anchor, after which the page loads |
| `libsystem_sysctl` | (freemac 1.201, Ferry 0.28.0) `sysctlbyname` and `sysctl` by number: `kern.ostype`, `kern.osrelease` and `kern.version` matching `uname`, `kern.osproductversion` 14.7 and `kern.osversion` 23H124, `hw.machine`, `hw.model`, `kern.hostname` matching `gethostname`, `hw.ncpu`, `hw.activecpu`, `hw.logicalcpu(_max)`, `hw.physicalcpu` and `machdep.cpu.core_count`/`thread_count` agreeing with `sysconf` and each other, `hw.memsize`, `hw.pagesize` (also read into an int), `hw.cachelinesize`, `hw.byteorder`, `hw.optional.*`, `machdep.cpu.brand_string` and `vendor` matching `cpuid`, `kern.boottime`, `sysctl.proc_translated` 0; the documented rules (a NULL buffer gives the size, a small buffer `ENOMEM` with the start copied, an unknown name `ENOENT`, a write `EPERM`); `sysctlnametomib` and the numbers it gives; `kinfo_proc` for this process (648 bytes, pid, parent, `p_comm`, `P_TRACED` clear, `P_LP64`, user, start time), for the parent and for a pid that doesn't exist; `KERN_PROCARGS2`; `proc_pidpath` and `proc_name`; `host_page_size`, `host_statistics64`, `host_statistics`, `host_info` and `task_info`; `getattrlist` on the program (name, type, modification time, full path, size, returned attributes, `FSOPT_REPORT_FULLSIZE`) and on its folder (entry count) |
| `libsystem_dlsym` | (freemac 1.201, Ferry 0.28.0) `RTLD_DEFAULT`, `RTLD_MAIN_ONLY`, `RTLD_NEXT` and `RTLD_SELF` from the program and from a library; `dlopen(NULL)`; a library built here opened through `@rpath`, `@executable_path` and (from inside it) `@loader_path` as one handle, its initializer run, `RTLD_NOLOAD`, `dlopen_preflight`; a bundle built with `-bundle -undefined dynamic_lookup` opened `RTLD_LOCAL`, calling back into the program and hidden from `RTLD_DEFAULT`; libSystem by path and by leaf name, Foundation and CoreFoundation by their `/System/Library/Frameworks` paths; `dlerror` after each failure (a missing name, a missing library, a framework Ferry doesn't have, a file that isn't a Mac library, a handle that isn't one) and cleared after reading; `dladdr` in a library, inside a program's function and on libSystem's `strlen`; `_dyld_image_count`, `_dyld_get_image_name` and `_dyld_get_image_header`, the add-image callback, `_NSGetExecutablePath`; `_availability_version_check` found with `dlsym` |
| `libsystem_available` | (freemac 1.201, Ferry 0.28.0) `@available` and `__builtin_available` compiled the normal way (macOS 10.15, 14, 14.7 and 13.5 available; 14.7.1, 14.8 and 15 not), `__isOSVersionAtLeast`, `__isPlatformVersionAtLeast` and `NSProcessInfo`'s `isOperatingSystemAtLeastVersion:` agreeing on each, an iOS version not available; `operatingSystemVersion` matching `kern.osproductversion`, `processorCount`, `activeProcessorCount` and `physicalMemory` matching `hw.ncpu`, `hw.activecpu` and `hw.memsize` |
| `libsystem_plugin` | (freemac 1.201, Ferry 0.28.0) Plug-in bundles built here: `NSBundle` not loaded until `load` (its description says so), one bundle per path, `preflightAndReturnError:`, `loadAndReturnError:`, `principalClass` from `NSPrincipalClass`, the plug-in's class finding its own bundle with `bundleForClass:` (Foundation's classes give the main bundle), `classNamed:`, `bundleWithIdentifier:`, `unload` refused; the same bundle through `CFBundleCreate`, `CFBundleIsExecutableLoaded`, `CFBundleGetFunctionPointerForName`, `CFBundleGetDataPointerForName`, `CFBundleCopyExecutableURL` and `CFBundleGetBundleWithIdentifier`; a bundle with no `NSPrincipalClass` (the first class it defines) loaded with `CFBundleLoadExecutable`; a bundle whose program is missing (`NSCocoaErrorDomain` 4, no principal class); a folder that isn't there |
| `pthreads` | (freemac 1.202, Ferry 0.29.0) the pthread calls of a Mac's libSystem on this system's threads: eight threads adding to one counter under a mutex, an `os_unfair_lock` and an `OSSpinLock` (160000 each), threads joined with their results, `pthread_main_np` before and after, a condition variable between a producer and a consumer, `pthread_once` from many threads, keys with destructors, `pthread_exit`'s value, a read-write lock, thread names, detach states, a stack too small refused and the stack size kept, recursive and error-checking mutexes (`EDEADLK`, `EBUSY`), timed waits returning `ETIMEDOUT`, thread ids and stack addresses, `pthread_equal`, Mac static initialisers |
| `dispatch_concurrent` | (freemac 1.202, Ferry 0.29.0) libdispatch across threads: four blocks on a global queue all running at once and none on the main thread, a serial queue running 4000 blocks one at a time in order, `dispatch_sync` from 16 threads, a barrier waiting for the blocks before it and running alone, `dispatch_apply` on more than one thread, semaphore ping-pong between threads and a counting semaphore's limit, `dispatch_once` from eight threads, `dispatch_after` on a global queue, a group's notify after 100 blocks, a stress run of 10000 global and four serial queues' blocks, and the main queue running only on the main thread |
| `foundation_threads` | (freemac 1.202, Ferry 0.29.0) `NSThread`: the main thread's answers (`isMainThread`, name, `threadDictionary`), a thread made with `initWithTarget:selector:object:` and started (executing and finished, the argument, its name, `NSWillBecomeMultiThreadedNotification` once and `NSThreadWillExitNotification`), starting it twice refused, `initWithBlock:` with cancel, its own dictionary, `sleepForTimeInterval:`, its autorelease pool, `+exit` and its quality of service, `detachNewThreadSelector:...` and `detachNewThreadWithBlock:`, `performSelectorOnMainThread:` (with and without waiting, and from the main thread itself), a thread's own run loop, `performSelector:onThread:` waited for and not, `performBlock:` on that thread's run loop, `performSelectorInBackground:`, an operation queue running two operations at once and keeping to a limit of four, main-queue operations from a worker running on the main thread, and 16 threads at once |
| `foundation_locks` | (freemac 1.202, Ferry 0.29.0) Foundation's locks and the runtime under many threads: `NSLock` (counting, its name, `tryLock` and `lockBeforeDate:` against a lock held elsewhere), `NSRecursiveLock`, `NSCondition` between producers and consumers and a wait that times out, `NSConditionLock` handing over in order and a condition never set timing out, `@synchronized`, `+initialize` run once with no thread getting in before it ends, messages sent while a method is added, retain and release, weak references loaded while the object goes away, associated objects, autorelease pools on eight threads, and notifications posted from eight threads |
| `cxx_basics` | (freemac 1.203, Ferry 0.30.0) a C++ program on this system's libc++: a global object constructed before `main` and destroyed after it, a replaced `operator new` used by containers, `vector`, `map`, `unordered_map`, `set`, algorithms and `accumulate`, `string` (find, `stod`, `stoll`), `iomanip` (precision, hex, fill), `printf` and `cout` alternating in order, `ctype` classes and `toupper`, words read with `>>`, `regex`, `stringstream` with `seekg`, `tellg` and `tellp`, `function`, `unique_ptr` and `shared_ptr`, `chrono` clocks and durations, and `filesystem` (directories, files, sizes, `ifstream` and `ofstream`, iteration, extensions, removal) in a temporary folder |
| `cxx_exceptions` | (freemac 1.203, Ferry 0.30.0) C++ exceptions thrown and caught by this system's libc++abi in a Mac program: through six recursive frames running their destructors, out of a function with no frame pointer, through this system's `qsort`, out of a Mac library of the program's own with its own exception class (`BadShape`), typeinfo compared and `dynamic_cast` across the two images, rethrown, kept in an `exception_ptr`, nested, caught by a second base class, `bad_cast` and `out_of_range` from the library, `uncaught_exceptions` during unwinding, and `std::terminate`'s handler for an exception leaving a `noexcept` function |
| `cxx_threads` | (freemac 1.203, Ferry 0.30.0) C++ threads on the Mac's layouts: a counter under `std::mutex` from eight threads, a queue under a `condition_variable`, `wait_for` timing out and `wait_until` woken, `recursive_mutex`, `timed_mutex`, `recursive_timed_mutex`, `shared_mutex` and `shared_timed_mutex`, `call_once`, `promise<int>` and `promise<void>`, `async` (on a thread, deferred, with an exception), a broken promise, a promise set twice, `shared_future`, thread ids and `hardware_concurrency`, joining no thread, and `detach` |
| `objcxx_mixed` | (freemac 1.203, Ferry 0.30.0) Objective-C++ under ARC: an object whose C++ ivars (a class, a `vector` and a `map` holding `NSString`s) are built and destroyed by `.cxx_construct` and `.cxx_destruct`, `NSString`s in a `vector`, a block capturing a C++ object (copied once on the stack and again on the heap, all destroyed), an `NSException` through a C++ frame running its destructor, a C++ exception through `@finally`, `@catch (NSException *)` letting a C++ exception through, `catch (...)` taking an `NSException` and rethrowing it, `@catch (...)` taking a C++ exception and rethrowing it with `@throw`, and a plain `@try` with `@finally` |
| `cxx_missing` | (freemac 1.203, Ferry 0.30.0) a C++ program without this system's libc++ (`FERRY_LIBCXX` naming a file that isn't there) stopping with exit status 127 and naming the packages libc++1 and libc++abi1 |
| `cxx_not_loaded` | (freemac 1.203, Ferry 0.30.0) an Objective-C program with no C++ never loading libc++ |
| `tlv_threads` | (freemac 1.204, Ferry 0.31.0) C `__thread` and `_Thread_local` variables, with first values and without, an array, a pointer to a global, a variable aligned to 64 bytes and a static one: eight threads each start from the template and keep their own copy while all eight change theirs at once, and the main thread's copy stays as it was; the thunk keeps every general register the compiler relies on and all sixteen vector registers, on a thread's first use and after it (checked from assembly); a function in the image's thread-local init section runs once; `dispatch_apply` on the global queue counts on each worker thread's own copy; and 32 threads that each fill a 4 MB thread-local array, half ending with `pthread_exit`, leave no storage behind |
| `tlv_threads_chained` | (freemac 1.204, Ferry 0.31.0) the same program as `tlv_threads`, linked with chained fixups |
| `tlv_dylib` | (freemac 1.204, Ferry 0.31.0) thread-local variables in a Mac library the program links through `@rpath`: the program reaches the library's variables directly, by their exported names, and through the library's own calls, and gets the same variable each way; six threads each start from the library's template and count on their own copies beside the program's own variable |
| `tlv_dlopen` | (freemac 1.204, Ferry 0.31.0) thread-local variables in a Mac library opened with `dlopen` while the program runs: a thread started before the library was opened, four threads started after it and the main thread each get their own copies; `dlsym` of a thread-local variable gives the calling thread's copy, and a write through it is seen by the library; destructors registered with `_tlv_atexit` and `__cxa_thread_atexit` run as each thread ends, the last registered first and still able to read the thread's variables, and the main thread's run when `main` returns, before the program's `atexit` function |
| `tlv_objc` | (freemac 1.204, Ferry 0.31.0) Objective-C `__thread` variables (an `int`, an unretained `NSString`, a static `NSInteger` and a `double`) on eight `NSThread`s started with a target and selector, with a block, detached and with `performSelectorInBackground:`: each sees the first values and keeps its own, one leaves with `+[NSThread exit]`, a destructor registered on each runs as it ends, and the main thread keeps its own values |
| `cxx_thread_local` | (freemac 1.204, Ferry 0.31.0) C++ `thread_local` objects across eight `std::thread`s: objects with constructors and destructors at namespace scope, as a static class member and inside a function, a `std::vector` and a `std::string`; each thread builds them on first use and destroys them in reverse order when it ends, a destructor reads another `thread_local` that is still there, and the main thread's objects are destroyed when `main` returns, before the program's static objects (skipped without libc++, like the other C++ tests) |
| `libsystem_sockets` | (freemac 1.205, Ferry 0.32.0) BSD sockets with the Mac layouts: `sa_len`, AF_INET6 30, the Mac `msghdr`, `cmsghdr`, `addrinfo`, `ifaddrs` and `fd_set`; TCP over 127.0.0.1, UDP with IP_PKTINFO and IP_RECVTTL, Unix sockets with SCM_RIGHTS and LOCAL_PEERPID, Mac socket options (SO_NOSIGPIPE, SO_NREAD, TCP_KEEPALIVE), Mac errno and EAI_ values, select and poll, getaddrinfo, getnameinfo, gethostbyname, inet_pton, and getifaddrs with an AF_LINK entry for the loopback; ::1 when the host has IPv6 |
| `libsystem_kqueue` | (freemac 1.205, Ferry 0.32.0) kqueue, kevent and kevent64 on epoll: EVFILT_READ and WRITE on pipes, sockets and files with EV_EOF, EV_CLEAR, EV_ONESHOT, EV_DISPATCH and EV_DISABLE; EVFILT_TIMER (one-shot, repeating, absolute); EVFILT_SIGNAL counting signals without changing the program's disposition; EVFILT_PROC NOTE_EXIT with the status while waitpid still reaps; EVFILT_USER from another thread; change-list errors as EV_ERROR results |
| `dispatch_sources` | (freemac 1.205, Ferry 0.32.0) libdispatch READ, WRITE, SIGNAL and PROC sources on real descriptors, signals and processes: data counts, suspend and resume, cancel handlers, a source on the main queue, and NULL for signal 0 |
| `corefoundation_socket` | (freemac 1.205, Ferry 0.32.0) CFRunLoopSource version 0 (schedule, perform, cancel, signal) and CFSocket with a run loop source: a TCP listener with the accept callback, a client with the connect and data callbacks, an echo, a refused connection, datagrams, the read callback re-enabled automatically and the write callback once |
| `foundation_streams` | (freemac 1.205, Ferry 0.32.0) NSInputStream and NSOutputStream over data, files and memory with delegate events; a bound pair; socket streams from getStreamsToHostWithName and CFStreamCreatePairWithSocketToHost with delegates, a dispatch queue and blocking use; a refused connection (ECONNREFUSED 61); a native socket; and TLS through the system's OpenSSL against a local server: an untrusted server fails with -9807, without validation the page arrives, and the peer trust holds the server's certificate |
| `foundation_netservice` | (freemac 1.205, Ferry 0.32.0) NSNetService TXT records made and read as RFC 6763 says; publish, resolve and search say "will" and then fail in the run loop with NSNetServicesUnknownError (-72000), as on a Mac where Bonjour can't be reached |
| `appkit_print_info` | (freemac 1.206, Ferry 0.33.0) `NSPrintInfo`: the shared print info's defaults (the paper this system's locale uses, the margins, scaling, pagination and centring), paper sizes and names, orientation turning the paper, the dictionary behind the properties, a copy that doesn't share changes, archiving with `NSCoding`, the print panel and page layout answering from `FERRY_PRINT_ANSWER` and `FERRY_PAGE_LAYOUT_ANSWER` with no display, and the printing calls a document now answers to |
| `appkit_print_view` | (freemac 1.206, Ferry 0.33.0) a tall view printed to a PDF file: laid out on several pages of the print info's paper, each page drawn by the view's own `drawRect:` (not to the screen, with the print operation current), and the file read back with Poppler (the number of pages, their size and the text on each); the same view on A4 in landscape at half size with a header and footer; a print operation run for a window, finishing after the call returns; and a print job that is cancelled |
| `appkit_print_pagination` | (freemac 1.206, Ferry 0.33.0) a view wider and taller than the page printed with automatic pagination (tiled row by row from the top), fit pagination (shrunk onto one page) and clip pagination (one page, cut off); a view that isn't flipped; a view that moves each page's bottom edge with `adjustPageHeightNew:top:bottom:limit:` so that a band isn't cut; a view that knows its own pages (`knowsPageRange:` and `rectForPage:`); and a range of pages printed in reverse order, with each page's rect, its place on the paper and the text on it |
| `appkit_print_text` | (freemac 1.206, Ferry 0.33.0) a text view printed across pages: eighty numbered lines on US Letter, every line printed once, whole and in order, each page ending at the edge of a line, and the selection not printed; the same text at a larger size on A5, fitted to the page's width, through the view's `print:` action with the panel answered; and rich text with a bold run, all of whose words print |
| `appkit_print_pdfdata` | (freemac 1.206, Ferry 0.33.0) `dataWithPDFInsideRect:` making one page the size of the rect, holding the view's drawing and its subviews' inside the rect and nothing outside it; `PDFOperationWithView:insideRect:toData:` and `toPath:` never showing the print panel, even when one is asked for; `writePDFInsideRect:toPasteboard:`; a window's `dataWithPDFInsideRect:` drawing its content view; and `dataWithEPSInsideRect:` giving Encapsulated PostScript |
| `appkit_print_document` | (freemac 1.206, Ferry 0.33.0) an `NSDocument` subclass making its print operation in `printOperationWithSettings:error:` from its own print info; `printDocumentWithSettings:showPrintPanel:delegate:didPrintSelector:contextInfo:` running it with the settings given (saving to a file) and calling the delegate back; Print… (`printDocument:`) through the print panel, answered from the environment, and cancelled; Page Setup… (`runPageLayout:`) changing the document's own print info only, after asking `shouldChangePrintInfo:`, refused and cancelled; and the print info kept when it is archived |
| `appkit_fonts` | (freemac 1.206, Ferry 0.33.0) one shared `NSFontManager`, which a program's own `alloc` gives too; the installed families and their members, from fontconfig; fonts made by family, traits and weight, and a Mac family name (Menlo) matched; conversions to and from bold and italic, to another size, family and face, and heavier and lighter; the Bold and Italic menu items (`addFontTrait:`) turning the trait on and off in a text view's selection through `changeFont:`, and the items' checks following the selected font; Bigger (`modifyFont:`); typing after Bold; and the font panel, answered from `FERRY_FONT_ANSWER` with no display, changing only what was chosen |
| `appkit_window_print` | (freemac 1.206, Ferry 0.33.0) printing on a display: Page Setup as GTK's page setup dialog in a sheet on the window, keeping the paper; the print dialog as GTK's print dialog in a sheet, printing to the file the answer names (GTK's Print to File), and the PDF's pages read back; the dialog cancelled; and the font panel (GTK's font chooser) shown and closed. It needs Weston and is skipped without it |
| `appkit_notify_un` | (freemac 1.207, Ferry 0.34.0) UNUserNotificationCenter, on a private session bus with a stand-in notification server: authorization granted and the settings all authorized; two categories with actions, one with a text input action and a custom dismiss action; a notification with no trigger sent at once with its title as the summary, its subtitle and body as the body (markup escaped), the app's name, its desktop entry and sound, and the actions as buttons; the delegate hearing a named action (which brings the app forward), an inline reply with its text, a dismissal the category asked for, and the default action; a notification swiped away with no category leaving the delivered list without a response; a time-interval trigger pending and then firing half a second later; a calendar trigger firing two seconds on; a repeating daily trigger's next date; removing pending and delivered requests (which sends CloseNotification); the same identifier replacing the notification on screen; the badge from a notification and from `setBadgeCount:`; and, with the app in front, `willPresentNotification:` choosing to show nothing and then a banner without a sound |
| `appkit_notify_ns` | (freemac 1.207, Ferry 0.34.0) NSUserNotificationCenter against the same stand-in: the defaults of a new notification; the action and other buttons, a reply, more actions, the other button closing the notification without telling the delegate, and a click on the notification itself, each reaching `didActivateNotification:` with its activation type, response and action; `didDeliverNotification:` after each delivery; scheduling half a second on and removing a scheduled one; removing a delivered one (CloseNotification); the same identifier replacing the one on screen; and `shouldPresentNotification:` deciding while the app is in front |
| `appkit_notify_dock` | (freemac 1.207, Ferry 0.34.0) the Dock tile, seen by a stand-in Dock as freemac's Dock reads it: com.canonical.Unity.LauncherEntry Update signals for the badge label (a number shown, a label that isn't a number sent as words (`x-freemac-badge-label`, with a count of 1) and taken away again with an empty label, `showsApplicationBadge`), for critical and informational attention requests (cancelled, ended after a second, ended when the app becomes active, and refused while it is active), and sent again when the Dock says it started; the delegate's `applicationDockMenu:` served as a dbusmenu menu (the Update's "quicklist"), read with its submenu and clicked; the tile's size and owner, and a content view drawn by `display` |
| `appkit_notify_none` | (freemac 1.207, Ferry 0.34.0) a session bus with no notification server: every call still answers (authorization, adding requests, delivering, the delegate's `didDeliverNotification:`), nothing is shown, the badge and attention still reach the Dock, and the program carries on |
| `appkit_notify_none message` | (freemac 1.207, Ferry 0.34.0) with `FERRY_VERBOSE` set, Ferry says once that no notification server is running |
| `appkit_notify_nobus` | (freemac 1.207, Ferry 0.34.0) the same program with no session bus at all gives the same answers, and with `FERRY_VERBOSE` set Ferry says once that there is no session bus |
| `coredata_model` | (freemac 1.209, Ferry 0.35.0) A model built in code, used with an in-memory store: attribute types, default values, optional and transient attributes, a transformable attribute, and a subentity. It covers `@dynamic` accessors for objects and scalars, KVC, KVO and the to-many mutable proxies, and primitive values. Inverses stay in step as to-one, to-many and ordered relationships change. The nullify, cascade, deny and no-action delete rules, `changedValues`, `committedValuesForKeys:` and the object's flags are checked. Validation gives the documented error codes (1570, 1660, 1670, 1610 and 1620, and 1560 with the detailed errors), and the deny rule refuses a save with 1600 |
| `coredata_stores` | (freemac 1.209, Ferry 0.35.0) The SQLite store (through this system's sqlite3) and the binary store, each saved and then read again by a second coordinator. The check covers every attribute type, to-one, to-many and ordered relationships, a subentity, faults and object IDs with their URI representations. The in-memory store is checked the same way, short of reopening it. Store metadata is read and set, including on a closed file. `NSPersistentContainer` is checked with a store description and with its default store in Application Support. A file that isn't a store and an unknown store type give 134000, and a save with no store gives 134060 |
| `coredata_fetch` | (freemac 1.209, Ferry 0.35.0) The same fetches from an SQLite store and from an in-memory one, which must answer alike. They cover predicates that the SQLite store puts in SQL (comparisons, strings, `BETWEEN`, `IN`, nil, to-one relationships, `SELF`, `AND`, `OR` and `NOT`) and ones it leaves to the context (key paths through relationships, `ANY`, case-insensitive and diacritic-insensitive comparisons, and a block). Sorting, limits and offsets are checked, with and without subentities. Results come as objects, object IDs, dictionaries (with `propertiesToFetch` and distinct results) and counts, and `countForFetchRequest:` is checked. Unsaved changes are included or left out, and objects come as faults or filled in. The batch size and prefetching are accepted |
| `coredata_undo` | (freemac 1.209, Ferry 0.35.0) An attribute change, an insert, a delete with its cascade and nullify, and a relationship change are undone and redone through the context's `NSUndoManager`, with undo groups closed by the run loop and an explicit group. It also checks changes made with undo registration turned off, `rollback`, `reset`, refreshing an object (merging its changes or not), and a context without an undo manager |
| `coredata_contexts` | (freemac 1.209, Ferry 0.35.0) Contexts together on an SQLite store. It checks the will-save, did-save and objects-did-change notifications and their keys, and `obtainPermanentIDsForObjects:`. A child context saves into its parent, and the parent saves to the store. Private-queue contexts work on their own threads with `performBlock:` and `performBlockAndWait:`, four at once, each saving 25 objects. A did-save notification is merged with `mergeChangesFromContextDidSaveNotification:`, and `automaticallyMergesChangesFromParent` is checked. The five merge policies are each tried when two contexts change the same object |
| `coredata_frc` | (freemac 1.209, Ferry 0.35.0) `NSFetchedResultsController` sections from a key path, with their names, index titles and objects, and index paths both ways. The delegate's callbacks come in order as objects are inserted, updated, moved (by a change to the sort key or to the section) and deleted, and as sections come and go. A controller without a delegate keeps the results it fetched. A request with no sort descriptors raises |
| `coredata_batch` | (freemac 1.209, Ferry 0.35.0) `NSBatchUpdateRequest` on an SQLite store with a predicate and its three result types. Objects in a context don't change until they are refreshed, or until the IDs are merged with `mergeChangesFromRemoteContextSave:intoContexts:`. `NSBatchDeleteRequest` is checked by fetch request and by object IDs, with the cascade and nullify rules applied to the rows and the deny rule refusing (1600). Both requests are refused on an in-memory store (134091) |
| `coredata_migration` | (freemac 1.209, Ferry 0.35.0) Lightweight migration of an SQLite store and of a binary store to a model that adds optional attributes (one with a default value, which the old rows are given) and a new entity, and removes an attribute. The new model is refused without the migration options (134100). With them, it is still refused for a new required attribute with no default value (134110) and for an attribute whose type changed (134190). The store's metadata matches the new model afterwards, and the old model is refused on the migrated store |
| `coredata_models` | (freemac 1.209, Ferry 0.35.0) A model's XML source (a `.xcdatamodeld` folder with two versions and its `.xccurrentversion`) read by `mergedModelFromBundles:`, by `initWithContentsOfURL:` and by `NSPersistentContainer` from the main bundle, then used. It covers attribute types and defaults, length limits, inheritance, inverse relationships, a transformable attribute and a fetch request template. A compiled model (`.momd` or `.mom`) isn't read: each way of asking for one answers nil, and loading the stores of a container without a model fails with 134070 |
| `coredata_models message` | (freemac 1.209, Ferry 0.35.0) The test's stderr says exactly once that compiled models aren't supported yet, though it asks for one four times |
| `coredata_array_controller` | (freemac 1.209, Ferry 0.35.0) `NSArrayController` in entity mode, with no display: an entity name and a managed object context. The content is fetched on the run loop's next turn when the controller prepares its content, by `fetch:` with a fetch predicate, and at once by `fetchWithRequest:merge:error:` (merging or replacing). `add:` inserts a new object of the entity into the context and selects it, and `remove:` deletes the selection from the context. Objects inserted into or deleted from the context by other code are followed, including a subentity's and not another entity's. `NSObjectController` in entity mode makes its new object in the context and fetches its content |
| `appkit_gradients` | (freemac 1.210, Ferry 0.36.0) `NSGradient` and `NSShadow`, with no display. A gradient's stops are made from two colours, from an array, from colours and locations given out of order (sorted, and held to 0 to 1) and from an archive, and nil comes back for no colours or a nil colour. Interpolated colours are checked at and between the stops and outside them. Drawing into a bitmap is checked pixel by pixel: along a line with and without the areas before and after it, in a rectangle at 0, 90, 180 and 45 degrees, in a path with nothing drawn outside it, between two circles, and outward from a rectangle's centre and from a point moved towards a corner. A relative position outside -1 to 1 raises `NSInvalidArgumentException`, and a gradient of one colour fills with that colour. A shadow's defaults (no offset, no blur, black at one third), copies and equality, a blur below 0 held at 0, an archive read back, and `set` with and without a colour, with a rectangle filled under a drop shadow and its shadow checked below and to the right of it (freemac 1.213). The shadow attribute's name is `NSShadow`, and a dictionary of text attributes with a shadow in it keeps the shadow, the way Spectacle, KeyCastr and Sequel Pro make one, and text drawn with it inks more pixels than without (freemac 1.213) |
| `appkit_gradients message` | (freemac 1.210, Ferry 0.36.0; changed in freemac 1.213, Ferry 0.39.0) The test's stderr says nothing about shadows, though two shadows are set and drawn |
| `appkit_split_controller` | (freemac 1.210, Ferry 0.36.0) `NSSplitViewController` and `NSSplitViewItem`, with no display. A controller with no nib has its split view as its view, side by side with thin dividers, and is its delegate. A child view controller added the general way gets an item, and removing it takes its pane away. The item kinds' settings are checked (plain, sidebar, content list and inspector). A controller laid out like MacPass's document window has its own plain view holding the split view, with a sidebar, a content pane and a collapsed inspector added in `viewDidLoad`. The test checks the panes' first thicknesses (the sidebar at its preferred fraction held to its minimum, the room going to the lowest holding priority) and growing and shrinking the window, with the change going to the lowest holding priority within each item's limits. Dividers dragged by the mouse stop at the items' minimum and maximum thicknesses, and an inspector dragged past half its minimum collapses, which its item's `collapsed` reports to an observer. Opening it again by code gives back its thickness. `toggleSidebar:` collapses and opens the sidebar, the menu item is titled Show Sidebar or Hide Sidebar, and it is disabled with no sidebar. `toggleInspector:` does nothing when no item has the inspector's kind. Removing an item and putting it back first are checked too. A new split view after loading raises `NSInternalInconsistencyException`, an item with no view controller raises `NSInvalidArgumentException`, and so does changing an installed item's view controller |
| `appkit_tab_controller` | (freemac 1.210, Ferry 0.36.0) `NSTabViewController`, with no display. The defaults are checked (segmented control on top, cross-fade and slide forward, a tab view with no tabs of its own). Tabs are added as items and as child view controllers, and a tab's view is loaded only when the tab is first shown. The controller's view is as big as the first tab's view, with the segmented control centred at the top or the bottom and the tab view filling the rest, and with no control the tab view fills the view. Choosing a segment, setting `selectedTabViewItemIndex` and selecting through the tab view each change the selection once for an observer, and so does removing the selected tab. An index out of range raises `NSRangeException`, a tab with no view controller raises `NSInvalidArgumentException`, and a new tab view after loading raises `NSInternalInconsistencyException`. A subclass that overrides `tabView:didSelectTabViewItem:` and calls super, as MacPass's preferences do, hears of each choice. In the toolbar style, put in a window, the controller makes the window's toolbar, showing icons and labels, with one item for each tab, named by the tab's identifier or by its place, and the selected one marked. Choosing an item selects its tab, a new tab adds an item, the selected tab's title becomes the controller's title, and a window with a toolbar of the app's own keeps it |
| `foundation_expressions` | (freemac 1.211, Ferry 0.37.0) `NSExpression` in each of its forms (a constant, `SELF`, a key path, a variable with and without a context, a function, a function sent to a target, an aggregate, union, intersect and minus sets, a subquery, `ANYKEY`, a block and a conditional), with their types and descriptions; format strings with arithmetic and its precedence, `**` to the right, unary minus, hexadecimal, binary and octal numbers, `%K` and `%@`, and argument arrays; the built-in functions (`sum:`, `count:`, `min:`, `max:`, `average:`, `median:`, `mode:`, `stddev:`, the arithmetic, `sqrt:`, `log:`, `ln:`, `exp:`, `raise:toPower:`, `ceiling:`, `floor:`, `trunc:`, `abs:`, `modulus:by:`, the bitwise functions and shifts, `uppercase:`, `lowercase:`, `length:`, `random`, `now`), indexes (`FIRST`, `LAST`, `SIZE` and a number), `FUNCTION`, `TERNARY`, `CAST` and `SUBQUERY` with `.@count`; `NSComparisonPredicate` built in code (with options and a custom selector) and as the parser makes it, with its modifier and expressions; arithmetic, functions and subqueries inside predicates; `MATCHES` with and without `[c]` and `[d]`, a bad pattern raising, and filtering with it; `predicateWithSubstitutionVariables:` and `evaluateWithObject:substitutionVariables:`, a missing variable, an unknown function and a bad format raising; equality, hashing and copies of expressions; and a predicate archived and read back |
| `foundation_decimals` | (freemac 1.211, Ferry 0.37.0) `NSDecimalNumber` arithmetic in base 10 (0.1 + 0.2 is 0.3), division to 38 or 39 digits, powers, powers of ten, numbers with more digits than fit, exponents, trailing zeros, text after a number and text that isn't one, a locale's decimal separator both ways, the mantissa initializer, zero, one, the largest and smallest numbers, numbers from doubles and integers, and the scalar values; the four rounding modes on halves and negatives at a scale, a negative scale and no scale; `NSDecimalAdd`, `NSDecimalSubtract`, `NSDecimalMultiply`, `NSDecimalDivide`, `NSDecimalPower`, `NSDecimalMultiplyByPowerOf10`, `NSDecimalCompare`, `NSDecimalRound`, `NSDecimalNormalize`, `NSDecimalCopy` and `NSDecimalCompact` with their error results (loss of precision, underflow, overflow, divide by zero); the overflow, underflow, divide by zero and exactness exceptions, a quiet handler, and `setDefaultBehavior:`; equality, comparison, hashing and sorting with `NSNumber` both ways, `decimalValue` of an `NSNumber`, and `@sum` of decimal numbers; `scanDecimal:`; `NSNumberFormatter` writing a decimal number's digits exactly and `generatesDecimalNumbers`; keyed archiving of a decimal number and a handler with secure coding; and `NSJSONSerialization` writing decimal numbers and refusing NaN |
| `coredata_aggregates` | (freemac 1.211, Ferry 0.37.0) A decimal attribute kept exactly in an SQLite, a binary and an in-memory store, read back as `NSDecimalNumber`; `NSExpressionDescription`s in `propertiesToFetch` with `sum:`, `count:`, `min:`, `max:`, `average:` and arithmetic on an aggregate, over all objects, over the objects a predicate picks and over none; `propertiesToGroupBy` with a nil group, `havingPredicate` by key and by variable, the groups sorted, limited and offset, a fetched property outside the grouping raising, expressions evaluated for each object (arithmetic, a string function and `SELF` as an object ID), and grouping alone; `MATCHES` in fetches and counts, alone, with `[c]`, with `NOT` and inside `AND`; decimal comparisons and sorting; an SQLite store whose decimal column is REAL, as Ferry 0.35.0 made it, changed to text on opening and written exactly afterwards; and a binary store that kept decimal numbers as doubles |
| `appkit_collections` | (freemac 1.212, Ferry 0.38.0) `NSCollectionView` of the item-based kind, with no display. A data source gives two sections, and items of a registered class are made with `makeItemWithIdentifier:forIndexPath:`; items that scroll out of sight are given back and reused, and the test counts how many were made and how many reused. Header and footer views are registered and made the same way. The flow layout's item size, spacing, section insets and header and footer sizes are checked in both scroll directions, with a delegate giving its own sizes, pinned headers and a collapsed section shown as one line. The grid layout's rows and columns, margins and limits are checked too. `indexPathForItemAtPoint:`, `itemAtIndexPath:`, `visibleItems` and `scrollToItemsAtIndexPaths:scrollPosition:` find and show items. Selection by code calls no delegate methods; selection by clicks, shift and command clicks and the arrow keys calls the delegate's should, did and highlight methods, with empty and multiple selection allowed or not. Items and sections are inserted, deleted, moved and reloaded, alone and inside `performBatchUpdates:completionHandler:`, and the selection and the items in sight follow them |
| `appkit_collections_legacy` | (freemac 1.212, Ferry 0.38.0) `NSCollectionView` of the older kind, with no display. A content array and an item prototype made in code, whose class makes its own view in `loadView`, give one copy of the prototype for each object. The grid comes from the prototype's size, `maxNumberOfRows`, `maxNumberOfColumns`, `minItemSize` and `maxItemSize`, and is checked with `frameForItemAtIndex:` and `frameForItemAtIndex:withNumberOfItems:`. When the content changes, the items of objects that stay are kept. `content` and `selectionIndexes` are bound to an `NSArrayController` and followed both ways, a click and a command click select, and an observer of `selectionIndexes` hears each change. The background colours are drawn into a bitmap, one colour and then two colours in rows |
| `appkit_collections_nib` | (freemac 1.212, Ferry 0.38.0) A collection view of the older kind read from a keyed nib and from the same nib in the `NIBArchive` form, with no display. Its settings come from the nib (selectable, multiple selection, columns, the smallest item size and the background colour). Its item prototype, of the app's own class by a class swapper, is copied for each content object with a view, field and button of its own. The copies' outlets point into their own views, each field is bound to its item's `representedObject.name` and changes when the object does, and each button's action goes to File's Owner |
| `appkit_rulers` | (freemac 1.212, Ferry 0.38.0) `NSRulerView` and `NSRulerMarker` on a scroll view, with no display. `hasVerticalRuler`, `hasHorizontalRuler` and `rulersVisible` make and show the rulers, and the content view is moved over to make room for them, also when `ruleThickness` or `reservedThicknessForMarkers` changes. The default drawing is checked in a bitmap (the background, the edge next to the content and the inch marks). A unit registered with `registerUnitWithName:abbreviation:unitToPointsConversionFactor:stepUpCycle:stepDownCycle:` can be chosen, and an unknown one raises `NSInvalidArgumentException`. A marker is added and drawn, dragged by the mouse with the client's should, will and did calls (the client moving it to a multiple of 5), dragged off and kept by the client, and dragged off and removed. A click away from the markers goes to the client's `rulerView:handleMouseDown:`, `trackMarker:withMouseEvent:` adds a marker with the client's say, and setting a new client view tells the old one and clears the markers. A ruler class of the program's own, set with `+setRulerViewClass:`, draws line numbers in `drawHashMarksAndLabelsInRect:` from the clip view's bounds, as Sequel Pro's line-number ruler does, and is checked in a bitmap before and after scrolling |
| `graphics_shadows` | (freemac 1.213, Ferry 0.39.0) Shadows drawn by Core Graphics, checked pixel by pixel in bitmap contexts. A filled rectangle with an offset and no blur casts the default shadow (black at one third) to its right and below it, and nothing above or to the left. A shadow set with no colour draws none, and one set before a save is gone after the restore. A shadow in a colour of its own, half transparent, blends with what is under it. The offset is in base space whatever the current transform. A blurred shadow grows lighter away from the shape's edge, the same on every side, and leaves the inside of a hollow shape white. Strokes, images, gradients and lines of text cast shadows too, a gradient drawn in a clip has no room for one, and a transparency layer casts one shadow for everything in it. An alpha-only context gets its shadow in alpha |
| `appkit_tracking` | (freemac 1.213, Ferry 0.39.0) `NSTrackingArea`, tracking rectangles, cursor rectangles and `NSCursor`, with no display, driven by mouse events sent to a window. An area's options, owner and user info are kept, and a copy is equal but not the same object. Going into an area sends `mouseEntered:` and `mouseMoved:` to its owner, even when the window takes no mouse-moved events, and going out sends `mouseExited:`. An event made by hand with `enterExitEventWithType:` carries its tracking number and user data, and an owner that isn't a view gets the area in its events. With views inside and beside each other, exits come before entries. An area is live only as its options say: in the key window, while its view is first responder, or always. An area assumed to have the mouse in it is told it left on the first move outside. An area in the visible rect follows the view as it grows, and a hidden view's area is never entered. While a button is held, an area not enabled during drags waits for the button to come up. `updateTrackingAreas` is sent once the view is put in a window, after its frame or its superview's bounds change, and not when nothing changed. A tracking rectangle has its tag in its events and isn't listed by `trackingAreas`. Cursors are pushed and popped, an image cursor keeps its hot spot, an area with cursor updates sets the I-beam and the arrow comes back on the way out, and cursor rectangles set their cursor, can be turned off and on, and go away when discarded. An area removed while the mouse is in it sends nothing more |
| `appkit_animation` | (freemac 1.213, Ferry 0.39.0) `NSAnimation` and `NSViewAnimation`, with no display. The defaults, the four curves at a quarter, half and the end, progress held to 1, progress marks in order and each sent once, a mark removed, the delegate's own value for a progress, an archive, a copy and a duration below 0 (`NSInvalidArgumentException`). A blocking animation asks its delegate whether it may start, passes each mark to the delegate and the notification, ends, and returns only after its duration with more than three frames drawn. One that its delegate won't let start doesn't run. A non-blocking one returns at once, can be stopped part way and started again from there, and starts over once it has ended. One animation starts another at a mark and stops a third. A view animation moves and resizes a box between its frames, fades a view out (hidden at the end, its alpha given back) and in, hides a view given an empty end frame, and moves and resizes a window. The animator proxy inside an `NSAnimationContext` group, with a completion handler, and outside a group, leaves the values set by the end |
| `foundation_distnote_alone` | (freemac 1.213, Ferry 0.39.0) `NSDistributedNotificationCenter` with no session bus, working within the program. Nothing is delivered before the run loop turns. Observers by name and by object, a block observer given user info with words and a date, and removal. While the center is suspended, the four suspension behaviours (drop, coalesce, hold and deliver at once) and a post to be delivered at once. An object that isn't a string raises `NSInvalidArgumentException`, and the local type gives the same center |
| `foundation_distnote_alone quiet` | (freemac 1.213, Ferry 0.39.0) With no session bus, the test's stderr is empty |
| `foundation_distnote` | (freemac 1.213, Ferry 0.39.0) The same checks on a private session bus (`dbus-run-session`, skipped without it), and then the test starts itself again as a second program with `NSTask`. The second program says it is ready, its notification reaches an observer of the name, and the first answers with an object and user info that the second checks and sends back. The second program exits 0 |
| `appkit_running` | (freemac 1.213, Ferry 0.39.0) `NSRunningApplication` and NSWorkspace's running applications, with no display. The current application is the same object each time, with our process, a name, no bundle identifier (the test isn't in a bundle), our program, a launch date in the last minute, and finished launching. It is found by its process and in the workspace's list, and it is frontmost only once it is active. The test then makes an .app from its own program, starts it with `NSTask`, and finds it by its bundle identifier and by its process, with its name, bundle, program and launch date. It can't be hidden or activated from here, `terminate` ends it with SIGTERM and `forceTerminate` ends a second copy with SIGKILL, and none is left running after |
| `foundation_charset` | (freemac 1.213, Ferry 0.39.0) `NSMutableCharacterSet` and the further parts of `NSCharacterSet`. Ranges and strings added and removed, a union with the whitespace, an intersection and inversion. A string with an emoji gives a set with a member in plane 1, and a range in plane 1 has none in plane 0. The control, uppercase, lowercase, capitalized, non-base, decomposable, illegal and symbol sets are checked on a few characters, and the class's own makers give mutable sets that change without changing the shared ones. A bitmap is 8192 bytes for the first plane and 8193 more for each further plane with a member, and is read back from data and from a file. Supersets, equality between a set from a string and one from a range, mutable and immutable copies, inverted sets (an older set inverted holds the characters past the first plane), and trimming with a mutable set. The URL sets percent encode a string for a query, a path, a user and a host, decoding gives the string back, and bad escapes give nil |
| `appkit_attachment` | (freemac 1.213, Ferry 0.39.0) `NSTextAttachment`, with no display. An attachment's string is one U+FFFC under `NSAttachmentAttributeName`, and a line with one is wider by the image's width. Its image is drawn inline into bitmaps, upright in unflipped and flipped contexts, with its bottom on the baseline, and at the bounds it is given, 4 points below the baseline. An image is read from an attachment's PNG data, and a file wrapper's contents are its contents. A cell that draws itself is drawn at its size, a plain `NSTextAttachmentCell` takes its image's size, and an `NSTextView` draws the image in its text. An attachment is archived and read back |
| `foundation_applescript` | (freemac 1.213, Ferry 0.39.0) `NSAppleScript`, which keeps its source but runs nothing. Compiling answers NO and running answers nil, each with an error dictionary (number -1750, a message, a brief message, the program's name and the source's range). A copy keeps the source, a script read from a file keeps the file's text and can't be run either, and a file that isn't there gives nil with error -43 |
| `foundation_applescript message` | (freemac 1.213, Ferry 0.39.0) The test's stderr says exactly once that AppleScript isn't supported, though scripts are compiled and run four times |
| `webkit_linked` | (freemac 1.214, Ferry 0.40.0) Ferry's `WebKit.framework` with no display, in a home of its own. The classes and their defaults, which need neither WebKitGTK nor a display: a `WKWebViewConfiguration` with its preferences, user content controller, website data store (the default one, persistent) and process pool, and a copy that shares them; `WKPreferences`, non-persistent data stores (each its own) and the data types; `WKUserScript`, `WKContentWorld` (the page's world is one object, a named world is the same object each time), `WKSnapshotConfiguration` and `handlesURLScheme:`; the constants; `WebPreferences`' standard values and `WebUndefined`. Then web views made where they can't be shown: a `WKWebView` whose loads give nil, whose script and snapshot give `WKErrorDomain` errors and whose data store still removes data, and an older `WebView` whose script gives an empty string, both put in a window and drawn; stderr says once that web views need a display and will stay empty, and the program goes on. Run with the argument `classes` under `LD_DEBUG=libs`, it shows that WebKitGTK is opened only by programs that make a web view |
| `webkit_missing` | (freemac 1.214, Ferry 0.40.0) The same program as `webkit_linked`, run as if WebKitGTK weren't installed (`FERRY_WEBKITGTK` names a library that isn't there): the same output, and stderr says once that web views need WebKitGTK (libwebkit2gtk-4.1), which isn't installed |
| `webkit_wkwebview` | (freemac 1.214, Ferry 0.40.0) `WKWebView` with this system's WebKitGTK, on an X display of the tests' own (Xvfb), in a home of its own, loading only strings, data and local files. The configuration's defaults, user scripts at the start and the end of the document, a second message handler of the same name (which raises) and a data store given in the configuration. An HTML string, data and a file are loaded, with the navigation delegate's calls in order (the action and its type, start, the response and whether it can be shown, commit and finish, each with the navigation its load gave) and the title, URL, loading and progress after each; key-value observing of the same properties. A message from the page to a script message handler, with its body as Foundation objects, its web view and its frame. `evaluateJavaScript:completionHandler:` giving numbers, strings, booleans, arrays, dictionaries, null, undefined and dates, an unsupported result and an exception as `WKErrorDomain` errors, and a value kept apart in a content world of its own. A link clicked in the page, back, forward and reload, the back-forward list and its items, a request for a file, a file that isn't there (`NSURLErrorDomain` -1100) and a navigation the delegate cancels; `goForward` with nothing ahead; a removed handler gone from the page; data removed from a store; and `takeSnapshotWithConfiguration:completionHandler:` giving an image of the size asked for with the page's colour in it |
| `webkit_ui` | (freemac 1.214, Ferry 0.40.0) `WKUIDelegate` with this system's WebKitGTK, on the tests' own X display. A page's `alert`, `confirm` (answered later, yes and no) and `prompt` (answered with text and cancelled) reach the delegate and give the page its answers. A window the page opens with `window.open` is asked for with `webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:`; the web view made with the configuration given shows the page, with the opener's data store, and `window.close()` reaches `webViewDidClose:`. A delegate that gives nil, and no UI delegate at all, give the page what a Mac gives it: no dialog, `false`, `null` and no window |
| `webkit_legacy` | (freemac 1.214, Ferry 0.40.0) The older `WebView` with this system's WebKitGTK, on the tests' own X display. `WebPreferences`, standard and by identifier, with their change notifications; `canShowMIMETypeAsHTML:`, the group name and the main frame. An HTML string, a file, a link clicked, back, a main frame URL set, a load the policy delegate ignores and a file that isn't there, with the frame load, policy and UI delegates' calls in order (the policy for the navigation and for the type, start, commit, the window object cleared, the title, finish and failure) and the progress notifications. `WebDataSource` with its request, response, data and title. `stringByEvaluatingJavaScriptFromString:`, also from inside a frame load delegate's call. `WebScriptObject`: the window object, values of each kind, `valueForKey:`, `callWebScriptMethod:withArguments:`, `webScriptValueAtIndex:`, setting and removing values, `evaluateWebScript:` and exceptions giving `WebUndefined`. A new window asked of the policy delegate with `decidePolicyForNewWindowAction:` (freemac 1.217, Ferry 0.42.0), then with `webView:createWebViewWithRequest:` and shown with `webViewShow:`; no UI delegate; the text size and the user agent |
| `webkit_embed` | (freemac 1.214, Ferry 0.40.0) The GTK web view inside AppKit's window, with this system's WebKitGTK, on the tests' own X display. Where the GTK view is placed (from the window's top left) and how large the page says it is: over its `WKWebView` and the same size, clipped to what its superview shows, following the view when it is moved, made smaller, hidden and shown (and when its superview is), and when the window is made larger and the view's autoresizing follows. The first responder gives the GTK view the keyboard, and another view takes it away. The page stays when the window is ordered out and in, when the window is closed, and when the view is put in a new window and then a third; and GTK prints no warnings or criticals throughout |
| `appkit_hotkeys` | (freemac 1.215, Ferry 0.41.0) Global hotkeys, against a stand-in Wayfire with Strata's calls (`tests/tools/fake_wayfire.py`), in a home and runtime folder of the test's own and with no display. Two Carbon event handlers on the application target, the newest called first. Command-Option-Left, Shift-Command-V and F5 are registered with `RegisterEventHotKey` and reach Strata as Linux key numbers with their modifiers. The same combination again answers `eventHotKeyExistsErr`, and A alone and Shift-A answer `eventHotKeyInvalidErr`. Each press the stand-in sends reaches the handlers as `kEventHotKeyPressed` and then `kEventHotKeyReleased`, with its `EventHotKeyID` from `GetEventParameter` (by its type and by `typeWildCard`). A handler that answers `eventNotHandledErr` lets the next one have the event, and one that calls `CallNextEventHandler` gets the next one's answer. A global key-down monitor sees each press with its Mac key code, characters and modifiers, and a key nobody registered is sent to nobody. After `UnregisterEventHotKey` and `RemoveEventHandler`, the press goes nowhere and the removed handler isn't called, and a removed monitor sees nothing more. A local monitor sees the app's own key events in `sendEvent:` and keeps the one it answers nil for from going further |
| `appkit_hotkeys quiet` | (freemac 1.215, Ferry 0.41.0) With Strata there, the test's stderr is empty |
| `appkit_hotkeys_plain` | (freemac 1.215, Ferry 0.41.0) The same program against a Wayfire without Strata's calls: the hotkey is accepted with a reference and unregistered, and never pressed, as before |
| `appkit_accessibility` | (freemac 1.215, Ferry 0.41.0) The Accessibility API as Spectacle and ShiftIt use it, against the stand-in Wayfire (two displays: a built-in 1280x800 one with a 28-point bar at the top, and a 1920x1080 one to its left; four windows of two apps, one a dialog, and a panel), with no display. Before the user's say the process isn't trusted and calls answer `kAXErrorAPIDisabled`. `AXIsProcessTrustedWithOptions` with the prompt option asks once, through a stand-in for `freemac-allow-control` (`tests/appkit/fake_asker.sh`, freemac's own program answering Allow), and the process is then trusted. The system-wide element's focused application has the focused window's process and its title, and its focused UI element is the same window. The app's focused window and its three windows have their titles, subroles (a dialog for the one with a parent) and places from the main display's top left, one at a negative x on the other display. Position is settable and title isn't. Spectacle's left half of the main display's visible frame (size, position, size) goes to Wayfire as configure-view calls and reads back, and a window put on the main display from the other one is moved there with its output. Another app's window is minimized (set-minimized) and raised (focus-view), and its app is then the focused one. An unknown attribute answers `kAXErrorAttributeUnsupported`, a position given as a size `kAXErrorIllegalArgument`; a size isn't read as a point, a rectangle goes into an `AXValue` and back, and the type ids match. `NSScreen` lists both displays, the main one first, with frames and visible frames from Wayfire's outputs and work areas in a Mac's coordinates. The user's answer is kept in `~/.config/freemac/window-control.json` under the app's name, and once it is turned off there the process isn't trusted and a move answers `kAXErrorAPIDisabled` |
| `webkit_dom` | (freemac 1.217, Ferry 0.42.0) The older `WebView`'s DOM classes with this system's WebKitGTK, on the tests' own X display, with a page from a string. The document (`DOMHTMLDocument`, the main frame's and `mainFrameDocument`), its root, head, body, doctype, title and URL; one object for each node, also when a script gives it. Elements of the classes their tags have (`DOMHTMLHeadingElement`, `DOMHTMLParagraphElement`, `DOMHTMLLIElement`, `DOMHTMLAnchorElement` and others), text nodes, attributes and `DOMNamedNodeMap`; `getElementById:`, `getElementsByTagName:` and `querySelectorAll:` giving `DOMNodeList`, `querySelector:`, `getElementsByClassName:`, `webkitMatchesSelector:` and the links as `DOMHTMLCollection`. Making elements and text nodes, `appendChild:`, `insertBefore:refChild:`, `removeChild:`, `setAttribute:value:`, `className`, `innerHTML`, `outerHTML`, the title and an element's style. `offsetTop`, `clientHeight`, `scrollHeight` and `scrollTop` set on a scrolling box; `scrollIntoView:`, with the frame view's clip view at the page's new place at once. A bad selector and a node put into its own child raise `DOMException`; a plain object from a script is a `WebScriptObject`; after a new page, the old page's nodes give nothing and the new ones are new objects |
| `webkit_frames` | (freemac 1.217, Ferry 0.42.0) The older `WebView`'s frame views, subframes, resource load delegate, user style sheet and new windows, with this system's WebKitGTK, on the tests' own X display, loading only local files and strings. The main frame's `WebFrameView`, its `WebHTMLView` document view (flipped, a `WebDocumentView` and `WebDocumentText`) in a scroll view: as tall as a tall page, its clip view following the page when a script scrolls it (with `NSViewBoundsDidChangeNotification`), the page following `scrollPoint:` on the document view and `scrollToPoint:` on the clip view, both stopping at the end, and the document view twice as tall at a text size multiplier of 2. A page with a file frame and a `srcdoc` frame: each frame's policy, start, commit, title and finish told to the frame load and policy delegates for the right frame; `childFrames`, names, `findFrameNamed:` (also `_top` and `_parent`), each frame's document, data source, title, window, frame element and its `contentFrame`, and a subframe's frame view. The resource load delegate told of the page, its frames, style sheet and script (identifier, request, response and end) and of a missing image (`NSURLErrorDomain` -1100). A link clicked in a subframe and a subframe loaded by the program, each told for its own frame. A user style sheet from a file applied to the page, and not once turned off. `window.open`: the policy delegate's `decidePolicyForNewWindowAction:` first, then the new view, which shows the page, and the opener gets the new window |
| `foundation_encodings` | (freemac 1.219, Ferry 0.43.0) String encodings. More than twenty offered (UTF-8, Latin-1 and Shift JIS among them), with their names; the default C string encoding is UTF-8. A string with an accent, a dash and a euro sign in UTF-8, in Latin-1 strictly (nil) and lossily (`?`), in Windows-1252, Mac Roman and ASCII; UTF-16 with its byte-order mark, both byte orders, UTF-32 big-endian with a character past the Basic Multilingual Plane, Shift JIS, and the non-lossy ASCII escapes (`\351`, `€`). `canBeConvertedToEncoding:`, byte counts. Back from Latin-1, Mac Roman, Windows-1252 (curly quotes and the euro sign), UTF-16 with a byte-order mark and big-endian, Shift JIS, the non-lossy escapes and EUC-KR; bad UTF-8 gives nil. `getCString:maxLength:encoding:` that fits and one that doesn't, `cStringUsingEncoding:` in Latin-1 and NULL for ASCII, `getBytes:maxLength:usedLength:encoding:options:range:remainingRange:` stopping inside the range. Files read with `usedEncoding:`: UTF-8, UTF-16 by its byte-order mark, and Windows-1252 for bytes that aren't UTF-8; Latin-1 bytes read strictly as UTF-8 fail with Cocoa error 261. Core Foundation's IANA names and Windows code pages both ways, an unknown name, encoding names, the NS and CF numbers both ways, the system encoding (Mac Roman), `CFStringIsEncodingAvailable`, `CFStringCreateWithBytes`, `CFStringGetBytes` (whole, into a short buffer, and lossy with `?`), and the external representation in UTF-16 and back |
| `foundation_text` | (freemac 1.219, Ferry 0.43.0) Lines and paragraphs in a string with `\n`, `\r\n`, `\r` and U+2028: `getLineStart:end:contentsEnd:forRange:`, `lineRangeForRange:` (also at the end), `paragraphRangeForRange:`, `getParagraphStart:end:contentsEnd:forRange:`, U+2028 ending a line but not a paragraph. `enumerateSubstringsInRange:options:usingBlock:` by lines, paragraphs, lines backwards, words (with an apostrophe and a decimal number), sentences and composed characters, each with its substring and enclosing ranges; stopping after two words; `NSStringEnumerationSubstringNotRequired` giving nil. Composed character sequences with a combining accent and a surrogate pair, also from inside the pair and for a range. The four normalization forms (with a ligature and a circled digit) and `CFStringNormalize`. `rangeOfCharacterFromSet:` forwards, backwards, anchored (not found), anchored backwards and in a range. `stringByAddingPercentEscapesUsingEncoding:`, `stringByReplacingPercentEscapesUsingEncoding:` (nil for a bad escape), `CFURLCreateStringByAddingPercentEscapes` with extra characters to escape and `CFURLCreateStringByReplacingPercentEscapes` leaving one escaped |
| `foundation_cfmore` | (freemac 1.219, Ferry 0.43.0) Core Foundation from C. An array with no callbacks holding numbers: counts, `CFArrayContainsValue`, first and last index, sorting, `CFArrayBSearchValues` (found, between, past the end), `CFArrayApplyFunction`, `CFArrayReplaceValues`, inserting, exchanging, removing and `CFArrayRemoveAllValues`. Arrays with `kCFTypeArrayCallBacks`: an equal string found, sorting with `CFStringCompare`, `CFStringCreateByCombiningStrings`, `CFArrayAppendArray`, `CFEqual`, the type ID and `CFArrayGetValues`. A dictionary of C strings with key callbacks of its own (retain copies, release frees, its own equality and hash) over forty keys: `CFDictionaryGetValueIfPresent`, `CFDictionaryAddValue` not replacing, `CFDictionaryReplaceValue` not adding, `CFDictionaryGetCountOfValue`, `CFDictionaryApplyFunction`, and the keys freed on removal and emptying. The CFType dictionary created, mutably copied, listed with `CFDictionaryGetKeysAndValues` and copied again. UUIDs from a string, to bytes and back, constant UUIDs kept, a fresh one. File URLs in the POSIX, HFS and Windows path styles, extension, last component, parent; a web URL's host, query, fragment and port; the file system representation. The bundle keys, the Core Foundation version, the byte-order calls |
| `foundation_fileaccess` | (freemac 1.219, Ferry 0.43.0) In a home of the test's own. `enumeratorAtPath:` over a small tree, with each item's level and a file's attributes, and `skipDescendants`; `enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:` skipping hidden files and package contents, and only the top level; a missing folder told to the error handler. `displayNameAtPath:` (an app without `.app`) and `componentsToDisplayForPath:`. `setAttributes:ofItemAtPath:error:` with permissions and a modification date, read back with the owner; a hard link (two links, one file number) and a symbolic link by URL. URL resource values: size, directory, name, package, hidden, symbolic link, parent, several at once; reachability of a file, a missing file (Cocoa error 260) and a web URL (262); `filePathURL`, `fileURLWithPathComponents:`. `writeToURL:options:error:`. `trashItemAtURL:resultingItemURL:error:` into the freedesktop.org trash with its `.trashinfo`, and a second item of the same name. Bundle resources by URL. An `NSFileCoordinator` with a presenter: a write makes it let go and tells it of the change, its own coordinator's write isn't told to it, a read, and removing the presenter |
| `foundation_asserts` | (freemac 1.219, Ferry 0.43.0) `NSAssert1` passing and failing (`NSInternalInconsistencyException` with the formatted message), `NSParameterAssert` (`NSInvalidArgumentException`, "Invalid parameter not satisfying: arg != nil"), an assertion in a class method, `NSCAssert2` and `NSCParameterAssert` in C functions. The current handler is one per thread, kept in the thread dictionary under `NSAssertionHandlerKey`, and a subclass put there is used instead (and needn't raise). `NSGarbageCollector` has no collector, `NSMakeCollectable` gives the same object, `NSAllocateCollectable` and `NSReallocateCollectable` give memory |
| `foundation_asserts messages` | (freemac 1.219, Ferry 0.43.0) The test's stderr has the five "*** Assertion failure in" lines, one for each assertion that failed with the standard handler |
| `appkit_childwindows` | (freemac 1.219, Ferry 0.43.0) With no display. Two child windows added above and below a parent (adding one again keeps it once); moving the parent moves them by as much, resizing in place doesn't; ordering the parent out hides them and ordering it in brings them back; a removed child stays where it is; `setParentWindow:` moves a child to another parent; closing that parent lets the child go. An `NSPanel` hides on deactivation and an `NSWindow` doesn't: deactivating the app hides the panel, activating brings it back, and one set not to hide stays. A floating panel's level. `ignoresMouseEvents`, `excludedFromWindowsMenu`, `collectionBehavior`, `animationBehavior` and a status-level window read back; the dock, pop-up menu and screen saver levels; flushing disabled twice and enabled twice; `NSDisableScreenUpdates`; `convertBaseToScreen:` and back |
| `appkit_affine` | (freemac 1.219, Ferry 0.43.0) With no display. `NSAffineTransform`: the identity; translate then scale (the scale applies to points first); a 90° rotation; appending and prepending a rotation; the inverse undoing a transform and a flat one left as it is; `transformSize:` without the translation; keyed archiving (secure) and copies; a struct set. `transformBezierPath:` leaving the original, `transformUsingAffineTransform:` rotating a path in place; `elementAtIndex:associatedPoints:` over a rectangle and a closed curve, and past the end (`NSRangeException`); `appendBezierPathWithPoints:count:`; `appendBezierPathWithArcFromPoint:toPoint:radius:` rounding a corner, and with no current point (`NSGenericException`). `concat` and `set` drawing into a bitmap |
| `foundation_loginitems` | (freemac 1.219, Ferry 0.43.0) Run as an app (`LoginTest.app`) with a login helper inside it, in a home of its own. The session's login items: empty at first, the app inserted last and another app first (with "hide at launch"), the seed moving on and an observer told; both read back in order with names and resolved URLs; their autostart entries in `~/.config/autostart` (the name, `Exec` running this ferry with the quoted app, starting at login, hide at launch); the property read back; found again with the same ID; inserting the app again first moves it; an app that has moved doesn't resolve (`fnfErr`, also through `LSSharedFileListItemCopyResolvedURL`); an entry switched off with `Hidden=true` drops out; removing (and removing again: `fnfErr`). Recent documents kept in memory and seen by a second list, then removed. `SMLoginItemSetEnabled` turning the helper on (an entry not listed in Dials, and not among the shared file list's items), an unknown helper refused, and off twice |
| `libcrypto loaded only when encrypting` | (freemac 1.200, Ferry 0.27.0) A program using only CommonCrypto's digests doesn't load this system's OpenSSL; one using AES does |
| `appkit_carbon` | The Carbon, Accessibility and SystemConfiguration answers, and the smaller AppKit and Foundation pieces |
| `appkit_scrolling` | (before this report, same branch) scroll views, scrollers, text views, RTF and HTML, progress indicators, boxes |
| `appkit_panes` | (freemac 1.155) tab views and split views: layout, selection, the delegates, dragging, collapsing, holding priorities, autosaved positions, both built from a nib |
| `appkit_statusbar` | (freemac 1.157) menu bar items, on a private session bus: their StatusNotifierItem properties and pictures, the dbusmenu layout of one item's menu (labels, ticks, a dimmed item, a submenu read on its own), clicks on menu items and on an item without a menu, hiding an item, and Quit |
| `appkit_tables` | (freemac 1.159) table and outline views: a cell-based table in a scroll view with its header tiled above it (geometry, drawing through its cells, a check box column), selection by click, shift- and command-click, double click and the arrow keys with the delegate's say, sorting by clicks on the header, columns resized by dragging the header's dividers and by each autoresizing style, rows inserted and removed; a view-based table making only the rows in sight and reusing their views; an outline view opened and closed by code, chevron clicks and the arrow keys, with items and rows mapped both ways; and both loaded from a nib with a prototype cell view |
| `appkit_controls` | (freemac 1.164) pop-up buttons, segmented controls, search fields, stack views and toolbars: a pop-up list's menu opened over the button with the chosen item lined up, chosen by click and click, by press, drag and release, by the arrow keys, Return, Space and typing, closed by Escape or a click outside, disabled items passed over, an item's own action, the menu's delegate and the will-pop-up notification, and full keyboard access; a pull-down list; segmented controls in each tracking mode, with disabled segments, drags off a segment, tags, a segment's menu, the keys and every distribution; search fields searching after a pause, at once or only on Return, cleared by Escape and the clear button, with recent searches kept, saved and shown in the search menu; stack views in rows and columns (gravity areas, every distribution and alignment, insets, custom spacing, hidden and detached views, views dropped for want of room by visibility priority, nested stacks); toolbars from a delegate (the window's frame growing by the strip in each display and size mode, items placed with a flexible space, validation, clicks, a selectable item, items added and removed, the overflow menu, the saved configuration); and all of them loaded from a nib |
| `appkit_documents` | (freemac 1.167) the document classes, alerts and the workspace, in `DocApp.app` from `make_nibs.py` (four document types in its Info.plist, the File and Edit menus and the app's own `NSDocumentController` subclass in its main nib, a document window nib): a note named on the command line opened at launch; the types, classes and extensions; New ("Untitled", "Untitled 2"); edits through the undo manager moving the change count and the window's edited dot, Undo and Redo from the Edit menu; the File menu's validation; Save and Save As through the Save panel shown as a sheet, saved safely beside the file; Revert in a sheet; closing with unsaved changes (Cancel, Don't Save and Save, by Escape, Command-D and Return); Open through the Open panel, a file already open, a type the app can't open and a file it can't read; a package read and written as a file wrapper; a class with only the Mac OS X 10.3 calls; the Recent Documents list in the defaults and the Open Recent menu, opened from and cleared; alerts run modally in a nested loop (Return, Escape, Command-D, a click), their layouts with an accessory view and the suppression check box, the old return codes, `FERRY_ALERT_ANSWER`, `presentError:`; sheets (queued, the window's close refused while one is up, the old `beginSheet:modalForWindow:...` call); the workspace opening addresses, files and folders through a stand-in `gio`, icons, apps by identifier and name, types; and quitting with two unsaved documents (the review alert, each document's sheet, `NSTerminateLater`). Pictures of an alert, a sheet and an edited window go to `FERRY_DOCUMENTS_PNG` |
| `foundation_invocation` | (freemac 1.170, Ferry 0.14.0) `NSMethodSignature` from type encodings (sizes, alignments, frame length, `NSGetSizeAndAlignment`, bad encodings raising); `NSInvocation` calling methods that take and return integers of every width, pointers, objects, `float`, `double`, `long double`, C strings, small and large structs (`NSRect`, `NSRange`, structs mixing integers and floats, one in two vector registers, a struct passed on the stack), `SEL` and blocks, with more arguments than registers; `getReturnValue:`, `setReturnValue:`, `retainArguments` (objects, blocks and C strings kept), `invoke` and `invokeWithTarget:`, a nil target; exceptions thrown through `invoke` and through forwarding; an `NSProxy` that logs and re-sends every kind of call to its target; an `NSObject` subclass catching messages with `methodSignatureForSelector:` and `forwardInvocation:` (instance and class methods, `forwardingTargetForSelector:` going first); `NSUndoManager`'s `prepareWithInvocationTarget:` with groups, nested groups, redo, registration turned off and `removeAllActionsWithTarget:`; and a message nobody implements still stopping the program with the Mac's message (`foundation_invocation message`) |
| `foundation_invocation_O0` | (freemac 1.170) the same program unoptimized and linked with chained fixups |
| `foundation_json` | (freemac 1.170) `NSJSONSerialization` reading objects, arrays, every escape, surrogate pairs, integers, large integers and doubles, `true`, `false` and `null`; the mutability options and fragments; UTF-16 and UTF-32 input; mistakes as errors in the Cocoa domain (3840) with their line, column and index; nesting too deep; writing compactly, pretty-printed and with sorted keys, slashes escaped or not, fragments; `isValidJSONObject:`; what raises (other classes, infinite numbers, non-string keys, a bad top level) |
| `foundation_dates` | (freemac 1.170) `NSTimeZone` from the system's time zone database (offsets, abbreviations, daylight saving time, the next change, a year past the database's list, local mean time), from offsets and abbreviations, `$TZ` as the system zone; `NSLocale` identifiers and their parts; `NSDateFormatter` writing every pattern letter of Unicode date patterns, in four zones, and the standard styles; reading ISO 8601, RFC 2822 and other strings with offsets, zone names and abbreviations, abutting fields, two-digit years, missing fields, day of year, eras, strict and lenient; part of a string, errors; templates; changed symbols and copies |
| `foundation_calendar` | (freemac 1.173, Ferry 0.15.0) `NSCalendar` (Gregorian and ISO 8601) and `NSDateComponents`: every component of dates in New York, Paris and Tokyo, before 1970 and before the common era; week numbers and week-based years (en_US, en_GB and ISO 8601 weeks, week 53); dates from components, with a skipped and a repeated local time, values that carry, the components' own zone, week dates, the fourth Thursday and the last Monday of a month, a day of the year; copies, equality and `isValidDateInCalendar:`; adding months and years at month ends and leap days, days across a daylight saving change against 24 hours, mixed signs, wrapping; differences in years to seconds, weeks, backwards and between components; starts of days (New York, and Havana where midnight is skipped), the span of a day, week, month, year and hour; ranges and ordinals of units; today, yesterday and tomorrow, the weekend, comparing to a unit; the next date matching components (a time, a 31st, 29 February, Friday the 13th, a skipped time with each option, backwards), enumerating dates and setting a unit |
| `foundation_numbers` | (freemac 1.173, Ferry 0.15.0) `NSNumberFormatter` in every style (no style, decimal, percent, currency, accounting, ISO code, plural, scientific, spell-out, ordinal) with their patterns and digits; fraction, integer and significant digits; all seven rounding modes on halves and negatives, 2.675 and 1.005 rounded as decimals, a rounding increment; grouping sizes, separators, multipliers, padding in each position, prefixes and suffixes; patterns with exponents, quotes, negative parts and a zero part; NaN, infinities, negative zero, the zero and nil symbols; euros, pounds, yen, rupees, francs and an unknown code; locales' currencies and the currency keyword; reading strictly and leniently (grouping, exponents, affixes, percent, accounting, limits, integers only, symbols), errors and part of a string; copies; `NSByteCountFormatter` in its four count styles and with its options |
| `foundation_iso8601` | (freemac 1.173, Ferry 0.15.0) `NSISO8601DateFormatter` writing with each option in four zones (fractional seconds, the basic format, week and ordinal dates, a time alone, before 1970) and reading strings of the same shape only (offsets in each form, fractional seconds only with that option, no zone read in the formatter's, week and ordinal dates, a time alone); `NSDateFormatter`'s relative formatting ("Yesterday", "Today", "Tomorrow", with a time, read back) and its calendar; `NSDateComponentsFormatter` in its six styles, padded, without dropping zeros, with days, a limit of units, fractional hours, years and months on the calendar, the approximation and time remaining phrases |
| `appkit_editing` | (freemac 1.178, Ferry 0.16.0) editing cells in place: in a cell-based table, a double click on an editable cell of a selected row, Return on the row and `editColumn:row:withEvent:select:` (with and without selecting the text) start it, `editedRow` and `editedColumn` follow it; the data source gets the typed string, the delegate is asked `tableView:shouldEditTableColumn:row:` and `control:textShouldEndEditing:` (keeping the editing going once) and hears `controlTextDidBeginEditing:` and `controlTextDidEndEditing:` from the table with the `NSTextMovement` (Return, Tab, Shift-Tab, Escape, a click elsewhere); Tab and Shift-Tab across columns and rows, past a column that isn't editable, selecting the new row, and stopping after the last cell; Escape keeping the old value; a refused cell and a column that isn't editable sending the double action instead; the exception for a row that isn't selected; `reloadData` giving the editing up, a data source that reloads as it takes the value, `abortEditing`; in a view-based table, clicks on an editable field going to the table until it's edited, the cell's own text field edited and its action sent (found with `rowForView:`), Escape, Tab to the next row's field; in an outline view, an item the delegate keeps and one edited, the value going back by item |
| `appkit_autosave` | (freemac 1.178, Ferry 0.16.0) `NSDocument` autosaving, in a home of its own: a class that autosaves in place autosaved by the timer `autosavingDelay` after a change (nothing before it, nothing without a change) and by `autosaveWithImplicitCancellability:completionHandler:` and `autosaveDocumentWithDelegate:...`, over its own file with `NSAutosaveInPlaceOperation`, staying edited (and its window too) with no unautosaved changes, `autosavingIsImplicitlyCancellable` during the write; the file as last saved kept aside in Autosave Information and put back by Revert To > Last Saved Version (the File menu's Revert to Saved item becoming Revert To, with Last Saved Version and a dimmed Browse All Versions); Save making it clean and dropping the copy; closing without asking, after an autosave; an untitled document autosaved into Autosave Information (`autosavedContentsFileURL`, the same file each time), still asking, its file removed on closing; a class that doesn't autosave in place not autosaved, its Revert item unchanged, `NSChangeAutosaved` and `NSChangeCleared`; a delay of 0; quitting with two such documents (no review alert, each autosaved and closed) |

**What isn't done yet (and why).**

- **No real app is usable yet.** Tab, split, table and outline views, menu
  bar items, pop-up buttons, segmented controls, search fields, stack views
  and toolbars have come in since these apps were tried (1.155 to 1.164),
  and the document classes, `NSAlert` and `NSWorkspace` in 1.167; what they
  stop at now is still to be checked. The Sparkle updaters' checks of the
  Mac's version file and code signatures are still missing.
  `docs/ferry-compat.md` has the list.
- **Documents: autosaving without versions** (1.167, autosaving from
  freemac 1.178). Only a class whose `autosavesInPlace` answers YES is
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
  disabled. Print… and Page Setup… work from freemac 1.206. (`NSUndoManager`'s
  `prepareWithInvocationTarget:` works from freemac 1.170, so undo
  registered that way is kept, as the selector and block forms were.)
- **`NSInvocation` and forwarding: x86-64 only, and a few edge cases**
  (freemac 1.170). Arguments and results are laid out by Ferry's own
  reading of the x86-64 System V calling convention. A `long double`
  inside a struct that is returned in memory, `_Complex` types other than
  `long double`, and vector types (`__m128` and the like, which type
  encodings can't describe) aren't covered by the tests. When a forwarded
  message's caller and `methodSignatureForSelector:` disagree on whether
  the result comes back in memory, Ferry prints a warning and carries on
  as the signature says (or stops, if no memory was given).
- **JSON: no JSON5** (freemac 1.170). `NSJSONReadingJSON5Allowed` is
  accepted and plain JSON is still read; JSON5's comments, single quotes
  and unquoted keys are mistakes. `TopLevelDictionaryAssumed` has no
  effect. Error messages are Ferry's own words in Apple's style.
- **Dates: English and Gregorian only** (freemac 1.170). `NSLocale`
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
- **Calendars: Gregorian and ISO 8601 only** (freemac 1.173). Other
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
- **Numbers: English (United States) only** (freemac 1.173). Every
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
- **ISO 8601 and relative dates** (freemac 1.173). Week dates are
  written as the standard writes them ("2024-W27-4"); with the week option
  the month option is ignored. Fractional seconds are milliseconds, cut,
  not rounded. Relative formatting joins the day to the time with " at "
  ("Today at 3:05 PM") for every date style, as newer CLDR data does; older
  Macs used ", " for the short and medium styles. A calendar set on a date
  formatter is kept but its fields are still Gregorian.
- **Durations and sizes** (freemac 1.173). `NSDateComponentsFormatter`
  writes English units in the six styles; positional days are written
  "1d" before the clock, `maximumUnitCount` cuts rather than rounds, and
  `collapsesLargestUnit` and reading strings aren't done.
  `NSByteCountFormatter` counts files in thousands and memory in 1,024s
  (still written KB), with Apple's adaptive digits (none for KB, one for
  MB, two above). Neither was compared with a real Mac.
- **Editing in tables: text cells only** (freemac 1.178). Only text
  cells (an `NSTextFieldCell`, or an editable `NSTextField` in a cell view)
  are edited in place, by Ferry's own text field rather than a shared field
  editor (`currentEditor` and `fieldEditor:forObject:` aren't involved, so
  the delegate's `fieldEditor` argument is nil). A click on a selected
  row's cell doesn't start editing after a pause, as a Mac's does; a
  double click or Return does. From freemac 1.184 a column cell's
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
  (1.184), sets from freemac 1.188). The hidden subclass wraps setters
  taking objects, integers, `BOOL`, `float`, `double`, points, sizes,
  rects and ranges, the indexed array accessors and the set accessors
  (`add<Key>Object:`, `remove<Key>Object:`, `add<Key>:`, `remove<Key>:`,
  `intersect<Key>:`); a setter taking another struct or a `long double`
  isn't wrapped (its class has to announce the change).
  `mutableOrderedSetValueForKey:` and ordered sets aren't done. The
  collection operators are read in key paths, but a key path isn't
  observed past a plain array or set (an array controller's
  `arrangedObjects` is followed). `@sum` and `@avg` give an `NSNumber` (an integer when every value is one), and an `NSDecimalNumber` worked out in base 10 when one of the values is a decimal number (from freemac 1.211, Ferry 0.37.0); whether a Mac gives an `NSDecimalNumber` for plain numbers too, and how it prints, wasn't checked, and the
  custom operators some code defines (`_<key>ForKeyPath:`) aren't asked.
  The subclass's name, `NSKVONotifying_` and the class's, follows what is
  described publicly; `observationInfo` returns Ferry's own record, and
  setting it does nothing. Observers aren't retained, as on a Mac, and
  removing one that isn't registered raises `NSRangeException`, as on a
  Mac (from freemac 1.188; before, it was ignored); its reason follows
  the wording Apple's documentation quotes, not compared with a Mac's.
  Not compared with a real Mac: the order of nested notifications and of
  several dependent keys.
- **Predicates and expressions** (freemac 1.188). `NSPredicate` reads
  comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `IN`,
  `CONTAINS`, `BEGINSWITH`, `ENDSWITH`, `LIKE`, with `[c]`, `[d]` and
  `[cd]`), `ANY`, `SOME`, `ALL` and `NONE`, `AND`, `OR` and `NOT`,
  `TRUEPREDICATE` and `FALSEPREDICATE`, the format arguments `%@`, `%K`,
  `%d`, `%i`, `%u`, `%f` and `%s` (with `l`, `ll` and `q`), argument
  arrays, `$variables` and blocks, and `NSCompoundPredicate`. `[d]` folds
  the accents of Latin letters only. From freemac 1.211 (Ferry 0.37.0), `MATCHES` (regular expressions through `NSRegularExpression`), function expressions, `SUBQUERY`, `TERNARY`, `CAST`, arithmetic, and `NSExpression` and `NSComparisonPredicate` as public classes are there. Predicates are archived as their format strings, under Ferry's own keys, so an archive a Mac made isn't read. `predicateFormat` writes Apple's documented forms
  (strings in double quotes, `NOT` before a comparison without
  parentheses); not compared character for character with a Mac.
- **Bindings: controllers, tables and outlines** (freemac 1.184,
  `NSArrayController` and table bindings from freemac 1.188,
  `NSTreeController`, `NSDictionaryController`, outline views and per-row
  column bindings from freemac 1.190, controllers from nibs, cell views'
  bindings and validation from freemac 1.191). Text views, images, date
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
  removed object's `managedObjectContext` to `deleteObject:` it, on the
  array controller only, not the tree controller. In Core Data's entity
  mode (freemac 1.209, Ferry 0.35.0), `remove:` deletes the removed
  objects from the controller's context whether or not that option is
  given.
  `infoForBinding:`'s options are only those given, not every option with
  its default, and `optionDescriptionsForBinding:` is empty. A key the
  observed object lacks leaves the view as it is unless
  `NSRaisesForNotApplicableKeysBindingOption` is given (YES raises, NO
  shows "Not Applicable"); a Mac raises by default. A text field shows
  the no-selection, multiple-values, not-applicable and null placeholders
  greyed, as its placeholder. The bindings a class exposes follow Apple's
  Cocoa Bindings Reference, not a list read from a Mac.
- **NSArrayController: written from the documentation, not compared
  with a Mac** (freemac 1.188). What a Mac would settle: the order in
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
  documentation, not compared with a Mac** (freemac 1.190). What a Mac
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
  from the documentation, not compared with a Mac** (freemac 1.191).
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
- **Formatters: text fields, cells and table cells** (freemac 1.184).
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
- **Sliders: linear and drawn Ferry's way** (freemac 1.184). A
  circular slider is drawn and tracked as a linear one, and the knob is
  always round. The nib keys of `NSSliderCell` are those described
  publicly, not checked against Interface Builder's output.
- **Foundation for tools, regular expressions, XML and operations** (freemac 1.194, Ferry 0.21.0).
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
  - **NSScanner**: `scanDecimal:` reads an `NSDecimal` (from freemac 1.211, Ferry 0.37.0). A localized
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
- **Foundation pieces written from the documentation, not compared with a Mac** (freemac 1.194, Ferry 0.21.0). What a Mac would settle:

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
  controls, sounds and token fields: what is left** (freemac 1.195, Ferry
  0.22.0).
  - `NSPopover`: detaching into a window (`detachableWindowForPopover:`),
    animation (`animates` is kept and ignored), and the appearance options;
    the bubble has a soft edge in place of a shadow, as it had before Ferry drew shadows.
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
  Mac** (freemac 1.195, Ferry 0.22.0). They were written from Apple's
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
- **Loading URLs: what is left** (freemac 1.196, Ferry 0.23.0).
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
  (freemac 1.196, Ferry 0.23.0).
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

- **NSXMLDocument and its tree** (freemac 1.197, Ferry 0.24.0).
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
- **Strings in one-byte encodings** (freemac 1.197, Ferry 0.24.0).
  `dataUsingEncoding:` with ASCII or ISO Latin 1 now gives one byte a
  character, and nil (or `?` with `allowLossyConversion:YES`) for a
  character the encoding lacks; before, it gave UTF-8. Other encodings
  but UTF-16 are still written as UTF-8.
- **NSXMLDocument and its tree** (freemac 1.197, Ferry 0.24.0). Chosen
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

- **Core Animation, not done yet** (freemac 1.198, Ferry 0.25.0).
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
- **Core Animation, not compared with a Mac** (freemac 1.198, Ferry 0.25.0).
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

- **Redirects, authentication, cookies and the URL cache, not done yet** (freemac 1.199, Ferry 0.26.0).
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
- **Redirects, authentication, cookies and the URL cache, not compared with a Mac** (freemac 1.199, Ferry 0.26.0).
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

- **Security and CommonCrypto** (freemac 1.200, Ferry 0.27.0).
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
- **Security and CommonCrypto** (freemac 1.200, Ferry 0.27.0).
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

- **System queries and loading code** (freemac 1.201, Ferry 0.28.0).
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
- **System queries and loading code** (freemac 1.201, Ferry 0.28.0).
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

- **Threads** (freemac 1.202, Ferry 0.29.0).
  - `NSBlockOperation` runs its blocks one after another, in the order
    they were added; a Mac may run them at the same time.
  - A file handle's `writeabilityHandler` is called once, not each time
    the descriptor can take more.
  - A file handle's background reads (`readInBackgroundAndNotify` and the
    like) are served by the main run loop only, and their notifications
    are posted on the main thread, whichever thread asked.
  - Dispatch sources for files and Mach ports still never fire (timer
    and data sources do, and from freemac 1.205 read, write, signal and
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
- **Threads** (freemac 1.202, Ferry 0.29.0).
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

- **C++ programs, not done yet** (freemac 1.203, Ferry 0.30.0).
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

- **C++ programs, not compared with a Mac** (freemac 1.203, Ferry 0.30.0).
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

- **Thread-local variables, not done yet** (freemac 1.204, Ferry 0.31.0).
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

- **Thread-local variables, not compared with a Mac** (freemac 1.204, Ferry 0.31.0).
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

- **Sockets and streams, not done yet** (freemac 1.205, Ferry 0.32.0).
  - Bonjour: NSNetService and NSNetServiceBrowser don't use Avahi, so publishing, resolving and searching always fail with NSNetServicesUnknownError (-72000). Only TXT records work.
  - kevent accepts EVFILT_VNODE, EVFILT_EXCEPT, EVFILT_FS, EVFILT_VM and EVFILT_MACHPORT but never reports them.
  - libdispatch has no dispatch_io, and no VNODE or MACH_RECV/MACH_SEND sources.
  - TLS settings on a socket stream count only before it opens; an open stream can't be upgraded to TLS. There are no TLS server streams (kCFStreamSSLIsServer fails with -50) and no client certificates (kCFStreamSSLCertificates is ignored).
  - The SOCKS and proxy properties of streams are ignored, so streams always connect straight to the host.
  - CFRunLoopSource version 1 (Mach ports) isn't offered.
  - CFReadStreamGetBuffer works only for streams over data.
  - Run loop modes are ignored by sockets and streams: they fire in any mode of the loops they are scheduled on.
  - IPv6 (::1) was not tried here, because the sandbox has no IPv6 loopback; the test checks it only where the host has one.

- **Sockets and streams, not compared with a Mac** (freemac 1.205, Ferry 0.32.0).
  - The string values of the kCFStream and NSStream property keys, and of NSNetServicesErrorCode and NSNetServicesErrorDomain.
  - The TLS error codes: Ferry gives -9807 for every certificate trust failure and -9806 for any other failed handshake.
  - The error for a host name that can't be looked up (kCFErrorDomainCFNetwork code 2 with kCFGetAddrInfoFailureKey).
  - When a socket stream's status moves from opening to open, and when the end and has-space events come.
  - A stream into a fixed buffer returning 0 and being at its end once the buffer is full.
  - CFSocketConnectToAddress with a timeout of 0 waiting without a limit.
  - CFSocket's default flags (131: the read callback re-enabled automatically, close on invalidate).
  - The key order in TXT records made by NSNetService, "key=" for an empty value, and the order of NSNetService's failure events.
  - kqueue: the data field of EVFILT_WRITE (Ferry reports Linux's send buffer size, which Linux doubles, less what is queued), kevent failing with EINVAL for an unknown filter rather than reporting it as an EV_ERROR result, and the data counts of signal events.

- **Printing and fonts, not done yet** (freemac 1.206, Ferry 0.33.0).
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

- **Printing and fonts, not compared with a Mac** (freemac 1.206, Ferry 0.33.0).
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

- **Notifications and the Dock, not done yet** (freemac 1.207, Ferry 0.34.0).
  - Notifications are kept only while the program runs. A scheduled notification or a pending request whose time comes after the program has quit is never shown, and a click on a notification after the program has quit doesn't start it again.
  - Attachments (UNNotificationAttachment) and NSUserNotification's contentImage are kept but not shown, since the freedesktop.org specification has no way to send a picture beside the app's icon that every server reads.
  - A badge label of "0" shows no badge, where a Mac shows "0". Labels longer than eight characters are cut with "…" in freemac's Dock.
  - Docks other than freemac's can't show words in a badge, so for a label that isn't a number they show a count of 1.
  - A tile's contentView is drawn by display, but the picture only becomes the windows' icon, which X11 window managers show. No dock is sent it.
  - A change to applicationIconImage isn't sent to the Dock.
  - NSWindow's dockTile (the tile of a minimised window) isn't there.
  - NSUserNotification and NSUserNotificationCenter are in Ferry's AppKit file, so a program that links only Foundation finds no such classes.
  - freemac's notification server, Beacon, has no inline reply, so there a reply button and a text input action are shown as plain buttons and the response's text is empty.
  - Critical alerts, time-sensitive interruption levels, provisional authorization, notification content and service extensions, remote (push) notifications, and secure coding of the UN classes aren't there. The settings always say authorized, with every setting enabled.

- **Notifications and the Dock, not compared with a Mac** (freemac 1.207, Ferry 0.34.0).
  - The string values of UNNotificationDefaultActionIdentifier, UNNotificationDismissActionIdentifier, UNErrorDomain and NSUserNotificationDefaultSoundName, which were taken from Apple's documentation and not read on a Mac.
  - Which notifications stay in the delivered lists: here a notification leaves them when it is clicked, answered or dismissed, and stays when its time on screen runs out.
  - When `didDeliverNotification:` is called (here once the current turn of the run loop is over), and that it is called for a notification that wasn't presented.
  - The presentation options used when the app isn't in front (here banner, list, sound and badge), and that `willPresentNotification:` and `shouldPresentNotification:` are asked only while the app is active.
  - The exception raised for a time-interval trigger of 0 or less, or under 60 seconds when it repeats (here NSInternalInconsistencyException).
  - A request with no trigger never appearing in the pending list, and an error for a request whose trigger has no next date.
  - The defaults of a new NSUserNotification (an action button titled "Show", an other button titled "Close", no sound) and when its buttons are shown: here only when their titles were set or the app's Info.plist asks for alerts.
  - That an informational attention request ends after one second, and the ids that `requestUserAttention:` returns.

- **Core Data, not done yet** (freemac 1.209, Ferry 0.35.0).
  - Compiled models (`.mom` and `.momd`) aren't read, because their format
    isn't published. Asking for one, through `mergedModelFromBundles:`,
    `initWithContentsOfURL:` or an `NSPersistentContainer` named for one,
    answers nil and says so once on stderr. A model built in code, or the
    model's XML source (`.xcdatamodeld` or `.xcdatamodel`) in the app's
    resources, works. Most apps ship only the compiled model, so most apps
    that use Core Data stop here for now.
  - The SQLite store uses Ferry's own table layout. A store file written by
    a Mac's Core Data isn't read, and a Mac won't read one of Ferry's.
  - The XML store type isn't there. Adding one fails with
    `NSPersistentStoreInvalidTypeError` (134000). Store classes of an app's
    own (`registerStoreClass:forStoreType:`, `NSIncrementalStore` and
    `NSAtomicStore`) aren't supported, and registering one says so once on
    stderr.
  - Only lightweight migration is done. Entities and attributes can be
    added and removed, and a new non-optional attribute needs a default
    value. A renamed property (`renamingIdentifier`) counts as removed and
    added, and its values are lost. A changed type or a changed
    relationship is refused. Mapping models, `NSMigrationManager` and
    `NSEntityMigrationPolicy` aren't there.
  - `NSExpressionDescription`s in `propertiesToFetch`, aggregate functions, `propertiesToGroupBy` and `havingPredicate` are worked out in memory, not in SQL, on the objects the fetch's predicate picks (from freemac 1.211, Ferry 0.37.0). `MATCHES` in a fetch is evaluated in memory too.
  - The SQLite store puts only part of a predicate into SQL. Case-insensitive
    and diacritic-insensitive comparisons, key paths through relationships,
    `ANY`, `ALL` and blocks are evaluated in memory, on rows read from the
    store. A limit and an offset are applied in SQL only when the whole
    predicate went into SQL and every sort is on a number or a date.
  - `fetchBatchSize`, `relationshipKeyPathsForPrefetching` and
    `usesLazyFetching` are kept but change nothing. A fetch gives the
    whole array, and related objects are read when first used.
  - Decimal attributes are kept exactly, as text, in the SQLite and binary stores (from freemac 1.211, Ferry 0.37.0). Comparisons and sorts on them are done in memory, not in SQL. A store that kept them as doubles is read as before, and an SQLite store's column is changed to text when it is opened for writing.
  - Uniqueness constraints are read from the model but not enforced.
    Fetched properties, derived attributes, `allowsExternalBinaryDataStorage`
    (the data is kept in the row), persistent history tracking, query
    generations, CloudKit (`NSPersistentCloudKitContainer`),
    `NSBatchInsertRequest`, `NSAsynchronousFetchRequest` and Spotlight
    indexing aren't there.
  - A batch update can't change relationships. It fails with
    `NSPersistentStoreOperationError` (134070).
  - A save that spans several stores is applied store by store, not as
    one transaction.
  - `NSFetchedResultsController` accepts a cache name but caches nothing on
    disk. Without a delegate it doesn't follow changes, as Apple documents.
  - Version hashes are Ferry's own (SHA-256 over each entity's shape). They
    are only ever compared with hashes Ferry made.
  - Entity mode in AppKit is on `NSObjectController` and `NSArrayController`
    only, not on `NSTreeController`. `fetch:` takes effect on the run
    loop's next turn, and `fetchWithRequest:merge:error:` takes effect at
    once.

- **Core Data, not compared with a Mac** (freemac 1.209, Ferry 0.35.0).
  - The string values of the notification names and their user-info keys.
    Examples are `NSManagedObjectContextObjectsDidChangeNotification`,
    `NSInsertedObjectsKey`, the store option keys and `NSStoreTypeKey`.
  - Which error code each failure gives where Apple's documentation doesn't
    say. Examples are 134000 for a file that isn't a store, 134060 for a
    save with no store, 134070 for a container with no model and for a batch
    update of a relationship, 134100, 134110 and 134190 for the migration
    failures, 134091 for a batch request on a store that can't do it, and
    1560 with `NSDetailedErrorsKey` for several validation errors at once.
  - When the objects-did-change notification is posted. Ferry posts it from
    `processPendingChanges`, which runs on the run loop's next turn, before
    a save and before a fetch. A did-save notification lists only the sets
    that aren't empty.
  - The order of `NSFetchedResultsController`'s callbacks within one change,
    and what counts as a move and what as an update. Ferry reports a move
    only when the object's place among the objects in both results changed,
    or when its section changed.
  - The order of fetch results that have no sort descriptors, and where nil
    sorts (Ferry puts it first).
  - What each merge policy leaves in the store, attribute by attribute. With
    the overwrite policy, Ferry writes every attribute of the saving
    context's object, so a value that only the other context changed is
    overwritten too.
  - A batch delete applying the delete rules to the rows (deny, cascade and
    nullify), and the IDs it reports including the cascaded rows.
  - The undo groups: one for each turn of the run loop, with no action names
    of Ferry's own.
  - The form of `description` for objects and object IDs, and the form of
    an object ID's URI: `x-coredata://<store UUID>/<entity>/p<n>`, and
    `x-coredata:///<entity>/t<UUID>` for a temporary one.
  - `NSPersistentContainer`'s default directory. Apple says Application
    Support, which in Ferry is `$XDG_DATA_HOME` (or `~/.local/share`). The
    store's file name there is `<name>.sqlite`.
  - The array controller in entity mode. Ferry fetches when it is given a
    context and prepares its content, and adds objects of its entity that
    another part of the app inserts into the context, if they match the
    fetch predicate. `remove:` deletes from the context, but
    `removeObjects:` called directly doesn't, unless the content binding has
    `NSDeletesObjectsOnRemove`.

- **Gradients, shadows and two view controllers, not done yet** (freemac 1.210, Ferry 0.36.0).
  - Shadows are drawn from freemac 1.213 (Ferry 0.39.0): `set` passes its settings to Core Graphics, which draws them under what is drawn next, and a shadow in text attributes is drawn under its run. They aren't drawn in PDF contexts, so a printed page has none.
  - `NSGradient` blends in RGB only. The colour space given to `initWithColors:atLocations:colorSpace:` is ignored, and `colorSpace` answers nil. Each colour is read as red, green, blue and alpha.
  - `NSSplitViewController` lays its panes out by itself, not with Auto Layout. Holding priorities decide which pane takes a change of size, and panes at the same priority share it equally. A new pane makes the panes with a preferred fraction go back to it.
  - Sidebars and inspectors never float over the content, and collapsing and opening a pane isn't animated. `minimumThicknessForInlineSidebars`, `isSpringLoaded`, `canCollapseFromWindowResize`, `allowsFullHeightLayout`, `automaticallyAdjustsSafeAreaInsets`, `titlebarSeparatorStyle` and `automaticMaximumThickness` are kept but change nothing.
  - `NSTabViewController` changes tabs at once. The transition options are kept, but nothing is animated.
  - In the toolbar style, the controller's toolbar is put on the window only when the window has none of its own, and the window isn't resized to fit each tab's view. The unspecified style is drawn with no control at all.
  - The keys that the controllers and items are read from in a nib are a guess: `NSSplitViewItems`, `NSViewController`, `NSCollapsed`, `NSCanCollapse`, `NSHoldingPriority`, `NSTabStyle`, `NSCanPropagateSelectedChildViewControllerTitle` and `NSTabViewItems`. The shadow's keys (`NSShadowHoriz`, `NSShadowVert`, `NSShadowBlurRadius`, `NSShadowColor`) and the gradient's (`NSColors`, `NSLocations`) are a guess too. No nib saved by Interface Builder was tried.
  - None of the nine apps was run again, because their release builds couldn't be downloaded in this round.

- **Gradients, shadows and two view controllers, not compared with a Mac** (freemac 1.210, Ferry 0.36.0).
  - The value of `NSShadowAttributeName`, which Ferry makes `NSShadow`, after Apple's documentation of the attribute's raw value.
  - How a gradient in a rectangle at an angle lines up: here the gradient runs along a line through the rectangle's centre at that angle, just long enough that its ends touch the rectangle's corners. The circle that `drawInRect:relativeCenterPosition:` ends on is the smallest one around the moved centre that covers the whole rectangle.
  - The blend between stops, done here in sRGB, and the colour returned by `interpolatedColorAtLocation:`, which here is an sRGB colour.
  - A new shadow's colour (here black with an alpha of one third) and what `set` does with no colour (here it turns shadows off, so what is drawn next has none).
  - The thicknesses that the item kinds start with: here a sidebar can collapse, holds at 260 and is 150 to 400 points thick at 15 percent of the room, a content list is at least 200, and an inspector can collapse, holds at 260 and is 200 to 400. A plain item holds at 250, as Apple documents.
  - The first thickness of a pane with no preferred fraction: here its view's own thickness, held to its limits, or an equal share when its view has none.
  - Collapsing by dragging: here a pane that can collapse does so when its divider is dragged more than halfway from where the pane's limit stops it towards the pane's far edge, as `NSSplitView` does in Ferry.
  - The menu titles that `validateUserInterfaceItem:` gives `toggleSidebar:` and `toggleInspector:` (Show Sidebar, Hide Sidebar, Show Inspector and Hide Inspector), and the exceptions raised for a new split view or tab view after loading and for changing an installed item's view controller.
  - When observers of `selectedTabViewItemIndex` hear of a change: here once for each new selection, once when the first tab is added, and once when a tab is removed.
  - Where the segmented control sits: here centred, 8 points from the top or bottom edge, with the tab view filling the rest. The controller's view is as big as the first tab's view, or 480 by 270 points when there is none.
  - The toolbar's identifiers for tabs that have no string identifier (here `NSTabViewController.tab.` and the tab's place), and its display mode (icons and labels).

- **Expressions and decimal numbers, not done yet** (freemac 1.211, Ferry 0.37.0).
  - `distanceToLocation:fromLocation:` raises `NSInvalidArgumentException`, because Ferry has no Core Location.
  - `allowEvaluation` is accepted on an expression and does nothing, since Ferry doesn't keep expressions from being evaluated after they are read from an archive.
  - Predicates and expressions are archived as their format strings, under Ferry's own keys. An archive a Mac made of a predicate isn't read, and a block predicate or a block expression can't be archived (archiving one raises). A constant that a format string can't write (an object other than a string, number, date, nil or a collection of those) doesn't come back as itself.
  - A format string takes an `NSExpression` passed with `%@` as a constant value, not as a part of the expression.
  - `[NSDecimalNumber numberWithInt:]` and the other `NSNumber` class methods give a plain `NSNumber`, not an `NSDecimalNumber`. The initializers (`initWithInt:`, `initWithInteger:`, `initWithDouble:`, `initWithBool:`) give an `NSDecimalNumber`.
  - `NSJSONSerialization` reads numbers as integers and doubles, never as `NSDecimalNumber`, so a long decimal in a JSON file loses digits when it is read.
  - `@sum` and `@avg` work in base 10 only when at least one of the values is an `NSDecimalNumber`; with plain numbers they add doubles as before.
  - In Core Data, aggregates, grouping and having predicates are worked out in memory on the objects the fetch's predicate picks, not in SQL. A large store is read whole for them.
  - The SQLite store doesn't put comparisons or sorts on decimal attributes into SQL, as before; they are done in memory, now in base 10.
  - `MATCHES` in a fetch is always evaluated in memory, never in SQL.
  - A having predicate is evaluated on each group's dictionary, by key or as a variable (`count > 1` or `$count > 1`); an expression description's expression passed in the having predicate's format isn't matched to that description.
  - An aggregate is only recognized when its argument is read from each object (a key path, `SELF` or a function of those). An aggregate over a to-many key path (`sum:(items.price)`) isn't grouped.
  - Derived attributes are still not done.

- **Expressions and decimal numbers, not compared with a Mac** (freemac 1.211, Ferry 0.37.0).
  - How `NSExpression` and `NSComparisonPredicate` describe themselves: arithmetic written back infix with its parentheses, functions as `name:(arguments)`, `FUNCTION`, `TERNARY`, `CAST` (and a date as a `CAST` of its reference date seconds), `SUBQUERY`, `BLOCK` and the options `[c]`, `[d]`, `[cd]` and `[n]`. Numbers in hexadecimal, octal or binary are written back in decimal.
  - Which exceptions and reasons the expressions raise (a variable with no binding, an unknown function, the wrong number of arguments, a bad pattern for `MATCHES`). The reasons are Ferry's own words.
  - `stddev:` is the population standard deviation (it divides by the count). `mode:` gives an array of the most frequent values. `median:` of an even count is the mean of the middle two. `average:` and `sum:` give an `NSDecimalNumber` when one of the values is one.
  - Whether `MATCHES` without `[c]` lets `.` match a line break (here it doesn't, which is ICU's default), and how `[d]` is applied (the accents are folded from both the string and the pattern before matching).
  - How many digits a decimal division keeps. Here a result keeps as many as fit in the 128 bit mantissa, which is 38 or 39 digits (1/3 has 39 threes and 2/3 has 38 sixes ending in 7). The exponent runs from 128 below to 127 above.
  - What `NSDecimalString` writes for a number with a large exponent (here all its digits and zeros, never an exponent), and for "not a number" (`NaN`).
  - What `decimalValue` gives for a double. Here it is the shortest decimal that reads back as the same double, so `@0.1` gives 0.1.
  - The hash of a decimal number (here the hash of an `NSNumber` holding the same double), its `objCType` (here `d`), and what `NSNumberFormatter` does with one beyond writing its digits exactly.
  - The keys a decimal number and a handler are archived under (Ferry's own: `NS.decimal`, a string, for the number).
  - What a Core Data fetch with aggregates gives for an empty group (here `count:` gives 0 and the others give nothing), what a nil group by value looks like (here the key is left out of the dictionary), and the order of groups when no sort descriptors are given (here the order the first object of each group was found in).
  - The result types of expression descriptions: here an `NSDecimalAttributeType` result is an `NSDecimalNumber`, the integer types are truncated, and an undefined result type keeps the value as it is.
  - The exception raised for a fetched property that is neither grouped nor an aggregate (here `NSInvalidArgumentException`).
  - A decimal attribute's column type and text in Ferry's SQLite store are Ferry's own (the table layout already is).

- **Collection views and rulers, not done yet** (freemac 1.212, Ferry 0.38.0).
  - Nothing in a collection view is animated. `performBatchUpdates:completionHandler:` applies its changes at once, and the completion handler is called straight after with YES.
  - Items can't be dragged to or from a collection view. The dragging methods of `NSCollectionViewDelegate` are declared but never called.
  - Decoration views can be registered, but no layout of Ferry's asks for one, so none is drawn.
  - A collapsed section (`toggleSectionCollapse:`) is shown as one line of its first items with the rest hidden. It doesn't scroll sideways inside its line.
  - The grid layout lays all the sections out as one grid, in order, and stretches items across the room in width only.
  - `NSCollectionViewCompositionalLayout`, diffable data sources, `NSCollectionViewTransitionLayout` and prefetching aren't there.
  - A prototype item made in code is copied by making a new item of the same class. Its view is made by its own `loadView` or nib, or, when its class has neither, as a new empty view of the same class and frame, without the subviews, which Ferry says once.
  - The keys that a collection view and its layouts are read from in a nib are a guess: `NSSelectable`, `NSAllowsMultipleSelection`, `NSAllowsEmptySelection`, `NSBackgroundColors`, `NSMaxNumberOfGridRows`, `NSMaxNumberOfGridColumns`, `NSMinGridSize`, `NSMaxGridSize` and `NSCollectionViewLayout`. The layouts' own settings aren't read from a nib, and no nib saved by Interface Builder was tried.
  - A ruler's accessory view is laid out, but a ruler's own settings aren't read from a nib, and neither are a scroll view's `hasVerticalRuler`, `hasHorizontalRuler` and `rulersVisible`. Apps that set them in code, as Sequel Pro does, aren't affected.
  - The ruler's labels are drawn in the system font at 9 points, with no way to change them other than overriding `drawHashMarksAndLabelsInRect:`.
  - None of the apps was run again.

- **Collection views and rulers, not compared with a Mac** (freemac 1.212, Ferry 0.38.0).
  - The flow layout's defaults (items 50 by 50 points, 10 points between items and between lines, no insets and no headers or footers), and how it fills a line: a full line is spread out to fill the width, the last line of a section starts at the leading edge, and items smaller than the line are centred across it.
  - How the grid layout sizes its items when only one of the row and column limits is set: here, with only a row limit, the items run across in rows.
  - Which delegate calls a click, a shift click, a command click and the arrow keys make, and in what order: here `shouldSelect` or `shouldDeselect`, then the highlight calls on mouse down, and the `did` calls when the mouse goes up. Selection by code makes no delegate calls, as Apple documents.
  - Which item the arrow keys move to: here the nearest item in that direction by the layout's frames, going on to the next or the previous item at the end of a line.
  - What happens when a data source's counts don't agree with the inserts and deletes: here the collection view follows the data source and prints one warning, where a Mac raises.
  - What the older kind of collection view answers for `numberOfSections` (one) and for index paths, and that changing `content` keeps the items of objects that are still there, matched by identity.
  - The ruler's defaults (a rule 16 points thick, 15 points for markers, inches), the factors and cycles of the four built-in units (72, 28.35, 1 and 12 points), and how the marks are spaced (a labelled mark at least 40 points apart, and smaller marks down the step-down cycle while they stay at least 5 points apart).
  - How the ruler is drawn: a very light grey background, a grey line on the edge next to the content, and the labels next to their marks.
  - How far a removable marker has to be dragged off the ruler to be removed (here more than 8 points), and that a dragged marker stays where the client's `willMoveMarker:toLocation:` puts it.

- **Tracking areas, shadows, animations and other programs, not done yet** (freemac 1.213, Ferry 0.39.0).
  - Areas are checked by geometry against every view shown in the window, so an area under another view is still entered. Only an area with the visible rect option is cut to the part of its view that shows; any other area counts in full, even where a scroll view's clip hides it.
  - `NSCursor` sets GTK's named cursors, which the desktop's cursor theme draws, so the arrow, I-beam and hands look like this system's and not a Mac's. With no display, cursors are only kept.
  - Shadows are drawn in bitmap and window contexts but not in PDF contexts, so a printed page has none. The blur is three box blurs, close to a Gaussian but not the same.
  - Layer shadows (`CALayer`'s `shadowOpacity` and the rest) are still kept but not drawn.
  - `NSAnimationNonblockingThreaded` runs like the non-blocking mode, on the run loop of the thread that started it, and not on a thread of its own.
  - The animator proxy and `NSAnimationContext` set values at the end of the group, with no frames between, as before. `NSViewAnimation` fades windows and views by their alpha values.
  - `NSDistributedNotificationCenter` reaches only Ferry programs, over the D-Bus session bus. The notifications a Mac's system posts (such as the change between light and dark appearance) never come. User info that isn't a property list is dropped, as Apple says it must be one. `NSDistributedNotificationPostToAllSessions` posts on this session's bus only.
  - `NSRunningApplication` lists only the Ferry programs of the same user, read from /proc. Programs this system runs without Ferry aren't listed. Another program can't be hidden, unhidden or activated, `isHidden` is always NO, and the frontmost application is this one while it is active and none otherwise. Its properties aren't observable by key-value observing, and NSWorkspace posts no launch or termination notifications for other programs.
  - `NSCharacterSet` has no archive (`NSCoding`) yet. The older sets that NSString.m makes (letters, digits, whitespace and the rest) are still the simple tests they were, and not Unicode's categories.
  - `NSTextAttachment` draws an image or a cell but no placeholder icon for a file with no image, can't be dragged out of a text view, and isn't read from or written to RTFD.
  - `NSAppleScript` compiles and runs nothing: there is no AppleScript here and no Mac applications for Apple events to reach. `NSAppleEventDescriptor` isn't there either.
  - None of the apps was run again, because their release builds couldn't be downloaded in this round.
- **Tracking areas, shadows, animations and other programs, not compared with a Mac** (freemac 1.213, Ferry 0.39.0).
  - The order of events when the mouse moves from one area into another in the same move: here every exit is sent before any entry, the innermost exit first and the outermost entry first.
  - When `updateTrackingAreas` is sent: here once the run loop next turns, or at the next mouse event, after a view's frame or bounds change or the view is put in a window, to that view and the views inside it.
  - Whether `mouseMoved:` reaches an area's owner while the window doesn't take mouse-moved events: here it does.
  - What an area that is live only in the active app does in a key window of an app that isn't active: here the key window counts.
  - The size of a blurred shadow's edge: here the blur is close to a Gaussian whose standard deviation is half the blur radius, and its offset is in base space with a positive height moving it up.
  - The timing of a blocking animation's frames and the number of frames drawn at a frame rate of 0, which here means 60 frames a second.
  - The exact curves: here ease in and out is (1 minus the cosine of pi times t) over 2, ease in is 1 minus the cosine of pi times t over 2, and ease out is the sine of pi times t over 2.
  - What a view faded out ends with: here it is hidden and its alpha is given back as it was before.
  - Whether a distributed notification reaches the program that posted it: here it does.
  - The launch date of another program, read here from the kernel's start time of its process, and `executableArchitecture`, which here is always x86-64.
  - The members of the predefined sets made from Unicode's categories, which here come from this system's ICU version, and the URL sets, which here follow RFC 3986: the user and password sets hold the unreserved characters and the sub-delimiters, the host set adds the colon and square brackets, the path set adds the colon, the at sign and the slash but not the semicolon, and the query and fragment sets add the question mark too.
  - How a line with an attachment is measured: here the line keeps its font's ascent and descent and grows to hold the attachment's bounds.
  - The error number (-1750) and the messages in `NSAppleScript`'s error dictionary.

- **WebKit, not done yet** (freemac 1.214, Ferry 0.40.0).
  - Web views need this system's WebKitGTK (libwebkit2gtk-4.1) and a display. Without either, a web view stays empty, its loads give nil and its scripts and snapshots give errors, and Ferry says so once on stderr.
  - The embedding was tried on X11 (Xvfb) only. It is built from GTK's own containers, which work the same on Wayland, but no Wayland compositor was there to try it on.
  - Typing into a page was not tried, since there was no way to send key events to the test display. The web view takes the keyboard when it is the first responder, and key presses then go to GTK's view, except those with Command, which stay with AppKit's menus.
  - A request is loaded as a GET: its method, headers and body are dropped, and Ferry says so once.
  - `loadFileURL:allowingReadAccessToURL:` ignores the read access URL. The page can read the files that WebKitGTK lets a file page read.
  - Downloads aren't there. A navigation the delegate turns into a download is cancelled, and Ferry says so once.
  - `WKHTTPCookieStore`, `WKURLSchemeHandler`, `callAsyncJavaScript:`, `createPDFWithConfiguration:`, web archives, finding text, authentication challenges and `WKDownload` aren't there.
  - `WKWindowFeatures` gives nil for every feature.
  - A script message's `webView` is the first web view that uses the controller.
  - In the older `WebView`, a window opened by `window.open` gives the page null when the UI delegate's new view wasn't made inside `webView:createWebViewWithRequest:` (it is still shown and loaded). `decidePolicyForNewWindowAction:` is sent first (from freemac 1.217, Ferry 0.42.0).
  - In the older `WebView`, `webView:didClearWindowObject:forFrame:` is sent when the load is committed, and the title can come after `webView:didFinishLoadForFrame:`. Subframes are reported from freemac 1.217 (Ferry 0.42.0), with the limits listed under "WebKit's frames and DOM, not done yet".
  - `WebScriptObject`'s exceptions (`throwException:` and `setException:`) aren't there. A program's own Objective-C object given to a page arrives as its description. The DOM classes, `WebFrameView`, the resource load delegate and user style sheets came in freemac 1.217 (Ferry 0.42.0).
  - The placement of a web view in a window that is ordered out is brought up to date only when the window is shown again.
  - None of the apps was run again.
- **WebKit, not compared with a Mac** (freemac 1.214, Ferry 0.40.0).
  - The order of the navigation delegate's calls, and which navigation each gives: here a link clicked in the page gives a navigation that no load gave, and back, forward and reload give the navigations their calls gave.
  - The `WKNavigationType` given for loads by code (here `WKNavigationTypeOther`), for a link (here `WKNavigationTypeLinkActivated`), for back and forward and for reload.
  - The error codes: here an unsupported result is `WKErrorJavaScriptResultTypeIsUnsupported` (5), an exception is `WKErrorJavaScriptExceptionOccurred` (4) with its message, line and column under the documented keys, and a missing file is `NSURLErrorFileDoesNotExist` (-1100).
  - How results come back from `evaluateJavaScript:completionHandler:`: here dates are `NSDate`, `undefined` is nil and `null` is `NSNull`.
  - What a page gets with no UI delegate: here no dialog, `confirm` gives false, `prompt` gives null and `window.open` gives null.
  - In the older `WebView`, what `stringByEvaluatingJavaScriptFromString:` gives for values that aren't strings (here numbers and booleans as text, and an empty string for objects, undefined, null and errors), and the order of the frame load delegate's calls.
  - `WebPreferences`' standard values: Times at 16 points, Courier at 13, ISO-8859-1, JavaScript and images on.
  - The user agent Ferry gives (WebKitGTK's own, with the configuration's application name after it).
  - How a snapshot is sized when the configuration gives a width.

- **Global hotkeys and other apps' windows, not done yet** (freemac 1.215, Ferry 0.41.0).
  - Hotkeys are pressed only on freemac's own desktop, where Strata (strata-shell) binds them. On another Wayland desktop, or a Wayfire without Strata, they are accepted but never pressed, as before.
  - Each hotkey needs Command, Option or Control, or is a function key. A Mac lets an app register a plain key or Shift with a key as a hotkey; here that answers `eventHotKeyInvalidErr`, so that no app can collect what is typed.
  - The key's release is sent at once after its press, since Strata hears the combination and not the key going up. Key repeat isn't sent.
  - A combination that Wayfire or Strata already binds (such as Strata's own Command shortcuts) may reach them first, and one registered by another program answers `eventHotKeyExistsErr`, as on a Mac.
  - The Carbon Event Manager has only what hotkeys need: handlers on the application, dispatcher and monitor targets, and the hot-key events. No other Carbon events are sent, and a window's target is accepted but sent nothing.
  - Global event monitors (`addGlobalMonitorForEventsMatchingMask:`) see only the app's own registered hotkeys as key-down and key-up events, never other keys, mouse events or other apps' events. Reading other apps' key presses in general, as KeyCastr does, stays out of reach.
  - The Accessibility API reaches windows as Wayfire sees them: an app, its windows and their titles, places and sizes, minimized, full screen, focused and raised. What is inside a window (buttons, text, menus) isn't there, `AXUIElementCopyElementAtPosition` finds nothing, and there are no observers (`AXObserver`) or notifications.
  - An app's windows are matched by process through Strata's `strata/view-pids`; with a Wayfire without Strata, by the app id that the system-wide element's focused window gives.
  - A window's place is the one Wayfire has; a window just moved reads as where it was put for a second, until the app has drawn it there.
  - The user's answer is a choice, not a sandbox: any program of the user's can reach Wayfire's socket. It stops Mac apps under Ferry from moving windows until the user allows them, as a Mac does.
  - The question is asked once per process, with freemac's own dialog (`freemac-allow-control`), and the app learns the answer by asking again, as on a Mac. With no display, nothing is asked.
  - `[NSScreen mainScreen]` is the main display (the one the desktop's Displays settings chose, or the built-in one), not the screen with the key window.
  - Not checked in a real Wayfire here: this machine has no DRM device for a headless Wayfire, so Strata's `strata/hotkeys` calls were built but only exercised through the stand-in, which follows the same rules.
  - None of the apps (Spectacle, ShiftIt, Flycut) was run again.
- **Global hotkeys and other apps' windows, not compared with a Mac** (freemac 1.215, Ferry 0.41.0).
  - The order a hot-key event goes through the handlers: here the event dispatcher target's handlers first, then the hotkey's target's, then the application's, each target's newest first, until one answers anything but `eventNotHandledErr`.
  - Whether a global monitor sees a registered hotkey's press at all: here it does, as a key-down and a key-up event with the Mac key code, its characters and the modifiers.
  - The event time of a hot-key event: here the system's uptime when the press arrived.
  - Which window is an app's focused window when none of its windows is focused: here the one most recently focused.
  - A window's subrole: here `AXDialog` for a window with a parent and `AXStandardWindow` otherwise.
  - Which display a window goes to when it is moved across: here the one holding the middle of its new frame, then the one holding its top left, then the one it was on.
  - The application element's title: here the app id that Wayfire knows, or this program's own name for itself.
  - The visible frame: here the output's work area from Wayfire, which leaves out freemac's menu bar and Dock where they reserve room.

- **WebKit's frames and DOM, not done yet** (freemac 1.217, Ferry 0.42.0).
  - The DOM classes stand for the page's values and each call waits for the page (at most 10 seconds), as `stringByEvaluatingJavaScriptFromString:` does. Events (`DOMEventTarget`, `addEventListener:listener:useCapture:`), ranges and the selection as DOM objects (`DOMRange`), `DOMImplementation`, XPath and the CSS classes other than `DOMCSSStyleDeclaration` aren't there.
  - A string the page gives as null or undefined comes back as an empty string. `DOMHTMLDocument`'s `width` and `height` are its root element's scroll size.
  - A frame of another origin than the main frame's has no `DOMDocument` and its frame view has no size. Pages from files may reach each other's frames, as in a Mac's `WebView`.
  - A subframe's loads are told from a script of Ferry's in each frame, in a world of its own. A subframe's failed loads and server redirects aren't told, and its `webView:didClearWindowObject:forFrame:` comes when the agent's message does, after the frame's first scripts may have run.
  - A navigation is put down to a subframe when it is a link clicked in that frame, a load the program asked of that frame, or the URL of that frame's element; any other navigation of a subframe that a script starts is put down to the main frame.
  - The resource load delegate's calls for a subframe's resources give the main frame's data source. A request changed in `webView:resource:willSendRequest:redirectResponse:fromDataSource:` is sent as it was, and Ferry says so once; `didReceiveContentLength:` comes only where WebKitGTK still reports the data as it comes.
  - The user style sheet is read when it is set and when the preferences change, and it applies from the next page loaded; changes to its file afterwards aren't followed.
  - A policy delegate that answers `decidePolicyForNewWindowAction:` later is taken as having said no, and Ferry says so once. A new window's page reaches the page that opened it only when the UI delegate makes the new `WebView` inside `webView:createWebViewWithRequest:`; a view made otherwise is loaded, and the page gets null.
  - `WebFrameView` prints its document view without the page, and Ferry says so once. `allowsScrolling` set to NO hides the page's overflow.
  - `WKHTTPCookieStore`, downloads (`WKDownload` and the policy listener's `download`) and requests' methods, headers and bodies are still left out.
  - None of the apps was run again.
- **WebKit's frames and DOM, not compared with a Mac** (freemac 1.217, Ferry 0.42.0).
  - Which DOM class a node gets when its tag has no class of its own (here `DOMHTMLElement` for an HTML element and `DOMElement` for others), and which lists are `DOMNodeList` (here the results of `getElementsByTagName:`, `getElementsByClassName:`, `querySelectorAll:` and `childNodes`) and which `DOMHTMLCollection`.
  - Empty strings for what the page gives as null, and the DOM exceptions' names and reasons (here `DOMException`, with the page's message).
  - The order of the frame load delegate's calls between frames: here a subframe's calls come when its frame's messages arrive, all before the main frame's `webView:didFinishLoadForFrame:`.
  - The resource load delegate: which resources are told (here also `about:srcdoc` frames), the default identifiers (here numbers), and the data source given for a subframe's resources.
  - The frame view's sizes: the page's CSS pixels times the text size multiplier, rounded.
  - That pages from files may reach other files' frames in a `WebView` (here WebKitGTK's `allow-file-access-from-file-urls` is on in the older `WebView`).
  - That the policy delegate is asked about a new window before the UI delegate makes its view.

- **The calls the nine apps make next, not done yet** (freemac 1.219, Ferry 0.43.0).
  - About seventy-five encodings are offered, through ICU where Ferry doesn't convert them itself. NeXTSTEP, Symbol and the other old Mac script encodings that ICU doesn't have aren't available. A lossy conversion puts `?` for each character that doesn't fit, where a Mac often puts the nearest one (`e` for `é` in ASCII).
  - `initWithBytes:length:encoding:`, `initWithData:encoding:` and the other calls that take an encoding now give nil for bytes that aren't valid in it, as on a Mac; `initWithUTF8String:` still takes bad UTF-8 and puts U+FFFD for it.
  - Without ICU, words and sentences are split at spaces and at `.`, `!` and `?`, and composed characters by combining marks and surrogate pairs only. `NSStringEnumerationLocalized` is ignored.
  - Core Foundation's allocators are ignored: the `NoCopy` calls copy the bytes and never free the caller's. `CFSet` and `CFBag` with callbacks of their own aren't there. HFS paths name the one volume `Ferry`.
  - Directory enumerators give each folder's items sorted by name, not in the file system's order. `NSDirectoryEnumerationIncludesDirectoriesPostOrder` is ignored.
  - `setAttributes:ofItemAtPath:error:` sets permissions, the owner and group, and the modification date; the creation date, hidden extension and immutable flag are accepted and left as they are. `setResourceValue:forKey:error:` sets only the modification date.
  - The trash is the home folder's freedesktop.org trash, for files on any disk; a second item of a name already there gets " 2", " 3" and so on.
  - `NSFileCoordinator` coordinates only between the presenters of one program, and runs each accessor at once on the calling thread. `NSDocument` isn't a file presenter yet. `NSFileVersion` isn't there.
  - Child windows move with their parent in the window's frame, but on Wayland the compositor places every window, so a child is only kept above its parent (as a transient window), not moved on the screen. `ignoresMouseEvents` drops the window's clicks rather than letting them through to the window below. Collection behaviour, animation behaviour, `disableFlushWindow` and `NSDisableScreenUpdates` are kept and change nothing. A level above the normal one keeps the window above others; levels aren't ordered among themselves.
  - `NSBezierPath`'s `setAssociatedPoints:atIndex:`, `bezierPathByFlatteningPath` and `bezierPathByReversingPath`, and paths from glyphs, aren't there. A quadratic piece of a path is reported as the equivalent cubic one; nothing in the tests makes one.
  - The session's login items are the only shared file list kept on disk. The global login items (which would need root here), recent items and favourites last as long as the program does. Observers are called at once, not from the run loop. Items have no icons, and `LSSharedFileListItemResolve` gives no `FSRef`.
  - A login item's entry names the ferry program that wrote it, so it stops working if Ferry moves. `SMJobBless`, `SMJobSubmit` and the other launchd calls aren't there, and a helper is found only in the app's `Contents/Library/LoginItems`.
  - The login item calls are served through CoreServices, Carbon, Cocoa and ServiceManagement; a program that links only ApplicationServices for them won't find them, since that framework is served from Core Graphics' file.
  - Table and outline views' `setDropItem:dropChildIndex:` and `setDraggingSourceOperationMask:forLocal:`, `NSArchiver` and `NSUnarchiver`, `CGWindowListCopyWindowInfo` and posting `CGEvent`s, which the survey also found, aren't done.
  - None of the apps was run again.
- **The calls the nine apps make next, not compared with a Mac** (freemac 1.219, Ferry 0.43.0).
  - The list of available encodings, its order and the encodings' names.
  - UTF-16 without a byte-order mark read as little-endian, `dataUsingEncoding:` with `NSUTF16StringEncoding` putting a byte-order mark first, and finding a file's encoding in the order byte-order mark, UTF-8, then Windows-1252.
  - The enclosing ranges of words and sentences (here up to the next word or sentence), which come from ICU's break rules.
  - `stringByAddingPercentEscapesUsingEncoding:` leaving `%` and `#` as they are.
  - `CFStringGetBytes` into a buffer too short: here as many whole characters as fit.
  - `kCFCoreFoundationVersionNumber` (here 2000.0) and the HFS volume name.
  - The Cocoa errors for an unreachable URL (260 for a missing file, 262 for a URL that isn't a file).
  - The message of a failed `NSCAssert` (here with the function's full signature, from `__PRETTY_FUNCTION__`).
  - That a child window moves by the parent's change of origin when the parent moves or resizes, and that an `NSPanel` hides on deactivation unless told not to.
  - Where an item inserted before the first or after another goes when the list changed meanwhile, and items' IDs (here numbers from 1, the same for the same entry while the program runs).

Drag and drop within an app: dragging selected table rows or outline items,
or anything a view starts with `beginDraggingSessionWithItems:event:source:`
or the older `dragImage:…`, moves to the view under the pointer in any of
the app's windows, which proposes, shows and takes the drop as on a Mac. A
table shows the proposed drop as a ring around a row or a line between
rows. Nothing is drawn under the pointer, and drags don't leave the app. (freemac 1.220, Ferry 0.44.0)

- **Building the nine apps again, not compared with a Mac** (freemac 1.221, Ferry 0.45.0).
  - `UCKeyTranslate`'s characters for dead keys and Option combinations (here no key is a dead key and Option types what the key types without it), and `LMGetKbdType` (here 40).
  - `NSArchiver`'s format: Ferry writes its own property list (`archiverData` begins `bplist`), so archives made on a Mac can't be read and ones made here can't be read on a Mac.
  - Which accents `NSDiacriticInsensitiveSearch` folds (here Latin letters with accents, cedillas and strokes) and which widths `NSWidthInsensitiveSearch` folds (here the fullwidth ASCII forms).
  - The order of an `NSMapTable`'s or `NSHashTable`'s objects when enumerated.
  - The run loop's ordered performs, which run in every mode, and the modes themselves, which change nothing but `currentMode`.
  - When the file manager asks its delegate: here once for the item it was given, not for each item inside a folder.
  - `editedRange` after several edits between `beginEditing` and `endEditing` (here the union of the edits' ranges, moved as later edits change the length before them).
  - The focus ring's width and colour (here a glow 3 points wide in the focus colour), and `NSFocusRingAbove`, which draws the ring below the shape like `NSFocusRingBelow`.
  - The colours of the older system colours (`windowFrameColor`, `controlShadowColor` and the rest), from Ferry's own light palette, and `NSAppKitVersionNumber` (here 2487).
  - A text field as its own field editor: `currentEditor` answers the field, which takes `selectedRange` and `setSelectedRange:`, and `fieldEditor:forObject:` answers nil.
  - `hitTestForEvent:inRect:ofView:` (here content for any point inside, editable text for an editable or selectable text cell, tracking for an enabled button cell).
  - When a shading's function is called: here 256 times when the shading is made, not while it is drawn, so a function whose answers change later draws its first answers.
  - `NSMenuDidBeginTrackingNotification` and `NSMenuDidEndTrackingNotification` for menus that open over a window; a status item's menu, which is the desktop's, posts neither.

- **Modules, Auto Layout, FSEvents, Quick Look and JavaScriptCore, not compared with a Mac** (freemac 1.222, Ferry 0.46.0).
  - Auto Layout's answers when constraints are ambiguous. Ferry keeps each view where and as big as it was, below every constraint, so the frames can differ from a Mac's. It also differs on which of two conflicting constraints of the same priority is left out (here the one added later) and on the wording of the note about it.
  - The layout's timing: here it runs when a window displays after anything changed, and when an app asks. Views that translate their autoresizing mask into constraints are left to autoresizing.
  - The accessibility values views and windows answer of themselves (role, frame, parent, children and title), and everything else an app hasn't set: there's no screen reader, so nothing is posted and no one asks.
  - Which installed face a font descriptor's traits find, and the weight, width and slant traits a font answers (from its face's name).
  - FSEvents' latency and coalescing: here events for the same path within the latency become one, with their flags combined. Event ids count from 1 for each program, not across the system. A stream started in the past gets only the history-done event. Renames come as two events with Renamed set, without the Mac's pairing of their ids. `ItemFinderInfoMod`, `ItemChangeOwner` and `ItemXattrMod` are never set (any attribute change sets `ItemInodeMetaMod`).
  - The Quick Look panel's look (here a 520 by 440 utility panel with a 48-point icon, the name and size over the preview), which files it previews as pictures or text (text is the first 64 KB of a file that reads as UTF-8), and that it shows no generator's previews.
  - `NSRuleEditor`'s look (pop-ups, labels and 22-point − and + buttons in rows 25 points high, nested rows indented 16 points) and its animation, which here doesn't happen.
  - JavaScriptCore's engine and its version are this system's (WebKitGTK's), so messages, `Error` stacks and newer language features follow it. An object wrapped for a script stays alive as long as its context, and a context as long as any of its values. `JSManagedValue` holds its value weakly, kept alive by managed references and an owner (since 1.229). A `BOOL` or `char` a block or method returns reaches the script as a boolean. Blocks and exported methods reach a script as functions; JavaScript functions aren't turned into blocks, as on a Mac.

- **Linking and running the apps, not compared with a Mac** (freemac 1.223, Ferry 0.47.0).
  - What `ferry-ibtool` makes of a xib: the keys and flags of the nib it writes are Ferry's own, read only by Ferry's AppKit. An element it doesn't know is made as a plain view of its class, with no settings, and outlets to objects it didn't make are left out with a warning. Fonts, colours and images are named as the xib names them, and an asset catalogue's images aren't compiled.
  - Apple events reach only the app's own handlers. Scripting Bridge finds only apps Launch Services knows, and answers nil, 0 or an empty list to all of an app's properties and commands, telling its delegate that each event failed.
  - Authorization never grants a right, and nothing runs with privileges. A process activity, a power assertion and sudden termination are kept and listed back to the program, but this system isn't asked to stay awake.
  - `os_log` and `asl` messages go to syslog. `os_log` mirrors them to standard error when `OS_ACTIVITY_DT_MODE` is set, and `asl` to a client's own files. Debug messages are dropped, and the log can't be searched.
  - `NSURLDownload` names a file it may not overwrite by adding "-2" and up before the extension, and can't resume a download. NSWorkspace names a duplicate "name copy", then "name copy 2", and posts its notification after each operation, done or not.
  - `statfs` reports the kind of file system by this system's name for it (ext4, btrfs), and its flags as far as this system's mount options say.
  - A uniform type the table doesn't know gets a dynamic identifier of Ferry's own form, which conforms to public.data.

- **Shortcuts, asset catalogues and KeyCastr, not compared with a Mac** (freemac 1.224, Ferry 0.48.0).
  - Asset catalogues:
    - `ferry-actool` reads only the `mac` and `universal` idioms and the `any` and `dark` appearances.
    - Ferry draws in the light appearance, so an asset's dark variant is used only when it has no other.
    - Image stacks, symbol sets and the other kinds are left out with a note.
    - The app icon's `.icns` holds each size's PNG, and Ferry shows the largest.
  - `frontmostApplication`, when another app is in front, is the app whose window Wayfire has focused. That is a Ferry program found by its process, or another program named by its window's app id. Its name is the app id's last part.
  - `NSXPCConnection` never connects. A proxy's error handler is called on a background queue (at once for a synchronous proxy), then the invalidation handler, once. Each call through the proxy returns zero.
  - launchd's job calls and authorization rights are always refused, with the Mac's error codes. Content rule lists are never compiled, so nothing in a web view is blocked. Markdown isn't read into attributed strings.
  - Bookmarks:
    - A bookmark holds only the file's path, in a property list of Ferry's own.
    - It resolves while the file is at that path.
    - It is never stale.
    - Security scopes always start.
  - Window frames are saved under the Mac's "NSWindow Frame" keys in Ferry's own preferences. A window that can't be resized keeps its size.
  - A nine-part image's edges and middle are stretched, not tiled. Tab stops are kept and read back, but text is drawn with the system's own tab stops.
  - JSON with one comma before a closing bracket or brace is read, as ShortcutRecorder's files need.
  - The input source for each layout is one object for the program's life.

- **MacPass and MacDown, not compared with a Mac** (freemac 1.225, Ferry 0.49.0).
  - Core Image:
    - A `CIImage` is a Core Graphics image with an extent.
    - Of the filters, only the affine transform does anything. The QR code generator gives an empty image, since no QR encoder is written.
    - A `CIDetector` finds nothing.
  - Security:
    - `SecKeyCreateRandomKey` fails with `errSecUnimplemented`, so MacPass doesn't offer Touch ID.
    - `SecAccessControl` keeps its protection and flags and does nothing with them.
  - A context menu opens as Ferry's in-window menu, as a pop-up button's does. `popUpContextMenu:` and `popUpMenuPositioningItem:` return once it closes, as on a Mac.
  - Case mapping:
    - `uppercaseString`, `lowercaseString` and `capitalizedString` use this system's ICU, so one character can become two (`ß` becomes `SS`, `ﬁ` becomes `FI`).
    - `capitalizedString` takes a word to be a run between white space.
  - String transforms: XML hex references, fullwidth to halfwidth and the removal of marks are served. A transform that changes script returns nil, as one a Mac doesn't know does.
  - `ferry-ibtool` and the older xib format:
    - Each object is carried into the nib with the keys it has in the xib.
    - Outlet, action and binding connections are made, and other kinds are named on standard error.
    - A window is shown at load unless its `visibleAtLaunch` is NO.
  - A frame's `javaScriptContext` runs its scripts in the page. What comes back is copied as JSON carries it, so numbers, strings, arrays and plain objects come back, but functions and nodes don't.
  - MacPass's window opens at the size its nib gives, which cuts off its inspector. Its path control is a plain one.

From freemac 1.226 a window's alpha value reaches its window on screen:
a window at alpha 0 stays off screen until its alpha rises, so an app
that fades a window in, as Sequel Pro does, isn't seen before it is
drawn. Setting a view's frame to the frame it already has posts no frame
notification, as on a Mac.

- **Swift and SwiftUI, not compared with a Mac** (freemac 1.227, Ferry 0.51.0).
  - SwiftUI's views are Ferry's AppKit controls:
    - A `Stepper` is a two-part segmented control (minus and plus) beside its label.
    - A `Slider` doesn't show its label.
    - `Image(systemName:)` is a text symbol, where Ferry has one for the name.
    - A `GroupBox` is a lightly shaded box with its title above.
    - A `MenuBarExtra` is a status item with a menu. With the window style, its content opens in a window.
  - Layout:
    - Sizes follow SwiftUI's rules as Ferry has written them, and a window grows to fit its content.
    - A `ScrollView` is at most 400 points tall when nothing else sets its height.
    - Lazy stacks and grids make all their views at once.
    - Shapes, `GeometryReader`, `overlay`, `offset` and animations aren't there yet.
  - Accepted but not acted on yet: gestures (`onTapGesture`, `gesture`), `onHover`, `@FocusState` and `focused`, `contentShape`, and the accessibility labels.
  - Swift code:
    - `@MainActor`, `async` and `Task` don't compile, because Swift's concurrency library isn't built for Ferry. Ferry's SwiftUI works out its views on the main thread.
    - `Date`, `URL`, `Data` and `UserDefaults` are the NS classes under Swift's names, so code that needs them to be values (copying, `==`, `Codable`) doesn't compile.
    - There is no Dispatch overlay, so `DispatchQueue` doesn't compile.

From freemac 1.228 the constraints in an app's xibs reach its nibs, and
a window holds its content's size only at
`NSLayoutPriorityWindowSizeStayPut`: stronger constraints make it grow or
shrink, keeping its top left corner, so Sparkle's prompt opens at the
size of its content, and MacPass's panes fill its window.
Toolbars in xibs are made, with their items, as MacDown's is. Windows are
sent `-update` once after each event, as on a Mac, not on every turn of
the run loop. A pattern colour as a window's background draws its image,
as Flycut's bezel does, and `.icns` files with only JPEG 2000 pictures are
read when OpenJPEG is installed.

From freemac 1.229 every element in the apps' xibs is made as its own
class, with its attributes: text views keep their text, fonts and
colours, matrices their cells, web views their preferences, and fields
their formatters. Under X a window is placed as a Mac places it: where
its xib's initial position puts it on the screen it opens on, centred,
or cascaded for a document, with a titled window's top kept on the
screen, and a move the user makes is saved under the window's autosave
name. Under Wayland the compositor still places windows. A split view
controller shares out its panes once it is in a window, so MacPass's
inspector opens at the width of its nib. A block reaches JavaScript as a
function, and `JSManagedValue` holds its object weakly, so its value is
nil once the collector has taken the object, unless a managed reference
or its owner keeps it.

- **Swift and SwiftUI, not compared with a Mac** (freemac 1.230, Ferry 0.54.0).
  - A popover shown from a menu bar item (TomatoBar's) opens in a borderless window of its own, at the top of the screen under where the item was clicked. It was written before Ferry placed windows itself under X in 1.229 and hasn't been checked with that since; under Wayland the desktop decides where it finally shows.
  - A segmented `Picker` is an `NSSegmentedControl`; other pickers are pop-up buttons.
  - Shapes are drawn with `NSBezierPath`; `GeometryReader` works its content out again when its size changes.
  - An `alert` is an `NSAlert` sheet on its window, with a button for each action; a `sheet` is a window sheet.
  - Swift's concurrency library, Dispatch, Combine and Foundation's value types (`Date`, `Data`, `URL`, `UUID`, `JSONEncoder`) are in, so the "Swift code" limits of 1.227 no longer hold. Still missing: `@Observable` and the Observation module, `NavigationSplitView`, toolbar items, drag and drop in SwiftUI, animations and `offset`.

**What's next.** Freemac 1.219 added the calls a search of the nine apps' source found missing. Running the nine apps again to see where they stop now
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
and `appkit_binding_validation`; `NSGradient`, `NSShadow`,
`NSSplitViewController` and `NSTabViewController` in 1.210, see
`appkit_gradients`, `appkit_split_controller` and
`appkit_tab_controller`), then validating pending edits when they
are committed (editors registered with a controller), other calendars,
locales' own number and date data, and document versions.

## Known limits (for every milestone)

- **Apple silicon (arm64)-only apps** would need a CPU translator. Ferry runs
  x86-64 programs and the x86-64 slice of universal ones.
- **Mac App Store apps** are encrypted (FairPlay) and won't run.
- **Metal, SwiftUI, AVFoundation** and other large frameworks are out of scope until M1 to M7 are solid. WebKit is in, drawn by this system's WebKitGTK (from Ferry 0.40.0).
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
- 2026-11-24: Ferry 0.14.0 (freemac 1.170): `NSInvocation`, `NSMethodSignature`, `NSProxy` and message forwarding, `prepareWithInvocationTarget:`, `NSJSONSerialization`, `NSTimeZone`, `NSLocale` and `NSDateFormatter`, `make check` 74/74.
- 2026-11-24: Ferry 0.15.0 (freemac 1.173): `NSCalendar` (Gregorian and ISO 8601), `NSDateComponents`, `NSNumberFormatter`, `NSByteCountFormatter`, `NSISO8601DateFormatter`, `NSDateComponentsFormatter`, relative date formatting, locales' currencies, `make check` 77/77.
- 2026-11-24: Ferry 0.16.0 (freemac 1.178): editing text cells in place in table and outline views (double click, Return, Tab and Shift-Tab, Escape, `editColumn:row:withEvent:select:`, the data source's and delegate's calls, the text field's action), `NSDocument` autosaving in place with its timer, Revert To > Last Saved Version and closing without asking, `make check` 79/79.
- 2026-11-24: Ferry 0.17.0 (freemac 1.184): automatic key-value observing through a hidden `NSKVONotifying_` subclass, dependent keys, the observing options and `mutableArrayValueForKey:`'s change kinds; two-way bindings on text fields, buttons, pop-up buttons and the new `NSSlider` (with the null placeholder, `NSNegateBoolean`, `NSIsNil`, `NSIsNotNil` and `NSContinuouslyUpdatesValue`), `NSObjectController`, `NSUserDefaultsController`'s `values.*` and binding connectors in nibs; formatters on controls, cells and table cells being edited, `make check` 82/82.
- 2026-11-24: Ferry 0.18.0 (freemac 1.188): `NSArrayController` (content and `contentArray`/`contentSet` bindings, `arrangedObjects` sorted and filtered, the selection with `NSMultipleValuesMarker`, adding, inserting and removing, the selection options, automatic rearranging, observing `arrangedObjects.key`); table columns bound to `arrangedObjects.key` with the table's `content`, `selectionIndexes` and `sortDescriptors` bindings, edited cells written back and column titles sorting through the controller; `mutableSetValueForKey:` and the set mutation kinds, the collection operators in key paths, removing an observer that isn't registered raising, and an `NSPredicate` subset, `make check` 84/84.
- 2026-11-24: Ferry 0.19.0 (freemac 1.190): `NSTreeController` (children, count and leaf key paths, `arrangedObjects` as a tree of `NSTreeNode`s, `selectionIndexPaths` and `selectedObjects`, sorting, inserting, removing and moving at index paths, `add:`, `insert:`, `addChild:`, `insertChild:` and `remove:`), `NSTreeNode` and `NSIndexPath`; outline views bound to a tree controller (`content`, `selectionIndexPaths`, `sortDescriptors` and columns bound to `arrangedObjects.key`, edited cells written back); per-row `editable` and `enabled` column bindings, and no write back when the controller isn't editable; `NSDictionaryController`, `make check` 85/85.
- 2026-11-24: Ferry 0.20.0 (freemac 1.191): `NSArrayController`, `NSTreeController`, `NSObjectController` and `NSDictionaryController` loaded from keyed nib archives with their settings and the binding connectors that join them, so a nib that binds a table or an outline to a controller works with no code; view-based tables and outlines from a nib making their cell views from the table's prototypes, with controls in a cell view bound to `objectValue.key` both ways; `NSValidatesImmediately` (`validateValue:forKeyPath:error:` and `validate<Key>:error:` before a bound value is written, a refused value presented and the control put back), `NSRaisesForNotApplicableKeys`, `NSConditionallySetsEnabled` and `...Editable` on controls, `NSAllowsEditingMultipleValuesSelection`, `NSDeletesObjectsOnRemove`, `NSSelectsAllWhenSettingContent` and `NSHandlesContentAsCompoundValue`, `make check` 87/87.
- 2026-11-24: Ferry 0.21.0 (freemac 1.194): `NSTask`, `NSPipe` and `NSFileHandle`, `NSRegularExpression` on ICU, `NSScanner`, `NSXMLParser` on libxml2, `NSOperationQueue` and its operations, the locks, `NSCache` and `NSProgress`; ICU and libxml2 reached through a new core call, `ferry_twin_symbol`, only when first used; the desktop's notice for an app Ferry can't run now says "Ferry can't run this app yet" and keeps the app's output in `~/.cache/freemac/ferry/<app>.log` (1.193), `make check` 93/93.
- 2026-11-24: Ferry 0.22.0 (freemac 1.195): `NSStepper`, `NSLevelIndicator`, `NSColorWell` with a basic `NSColorPanel`, `NSDatePicker` (text with a stepper, or a calendar and a clock), `NSComboBox`, `NSPopover` (and view controllers presented as popovers), `NSPathControl`, `NSSound` (through `pw-play`, `paplay` or `aplay`) and `NSTokenField`, each with its cell and read from nibs, `make check` 94/94.
- 2026-11-24: Ferry 0.23.0 (freemac 1.196): loading http and https URLs through this system's libcurl, opened only when a program first loads one: `NSURLSession` (data, upload and download tasks, handlers and delegates, a serial operation queue of its own when none is given), `NSURLConnection`, `NSURLRequest`, `NSHTTPURLResponse`, `NSURLErrorDomain` and `NSData`'s and `NSString`'s `...ContentsOfURL:` for web addresses; a new core call, `ferry_network_symbol`, `make check` 97/97.
- 2026-11-24: Ferry 0.24.0 (freemac 1.197): `NSXMLDocument`, `NSXMLNode`, `NSXMLElement`, `NSXMLDTD` and `NSXMLDTDNode` on libxml2 (a tree of objects that can be walked, changed, searched with XPath and written out again, pretty printed or canonical); `dataUsingEncoding:` with ASCII and ISO Latin 1 converting for real, and `dataUsingEncoding:allowLossyConversion:`, `make check` 98/98.
- 2026-11-24: Ferry 0.25.0 (freemac 1.198): QuartzCore.framework with Core Animation basics (layers, shape, gradient and text layers, transactions, implicit and explicit animations, springs and groups), layer-backed and layer-hosting NSViews, NSAnimationContext and the views' animator, `make check` 101/101.
- 2026-11-24: Ferry 0.26.0 (freemac 1.199): redirects decided by the delegate, HTTP Basic and Digest authentication, server trust, `NSHTTPCookieStorage` saved to disk, `NSURLCache` in memory and on disk, and `data:` URLs, `make check` 107/107.
- 2026-11-24: Ferry 0.27.0 (freemac 1.200): Security.framework (keychain passwords, code-signing answers, certificate trust), CommonCrypto (digests, HMAC, PBKDF2, AES), and one macOS version (14.7) everywhere an app asks, `make check` 117/117.
- 2026-11-24: Ferry 0.28.0 (freemac 1.201): `sysctl`, `dlopen`/`dlsym` and loading code after start-up, `@available` checks, `getattrlist`, the Mach host and task statistics, and NSBundle plug-ins that really load, `make check` 121/121.
- 2026-11-24: Ferry 0.29.0 (freemac 1.202): real threads: NSThread, per-thread run loops and autorelease pools, real locks and `@synchronized`, pthreads, libdispatch on a worker pool, concurrent NSOperationQueue, a thread-safe runtime, and URL loading on a network thread of its own, `make check` 125/125.
- 2026-11-24: Ferry 0.30.0 (freemac 1.203): C++ and Objective-C++ programs on this system's LLVM libc++ and libc++abi, loaded only when a program needs them: the standard library, exceptions across images and mixed with Objective-C's, and C++ threads on a Mac's layouts, `make check` 131/131.
- 2026-11-24: Ferry 0.31.0 (freemac 1.204): Mac thread-local variables (`__thread`, `_Thread_local`, C++ `thread_local`) through Ferry's own `_tlv_bootstrap` and `_tlv_atexit`, per thread and per image, in libraries opened with `dlopen` too, with destructors at thread exit, `make check` 138/138.
- 2026-11-24: Ferry 0.32.0 (freemac 1.205): BSD sockets with the Mac's layouts, kqueue and kevent on epoll, dispatch read, write, signal and process sources, CFSocket and run loop sources, CFStream and NSStream with TLS checked by SecTrust, and NSNetService's TXT records (no Bonjour yet), `make check` 144/144.
- 2026-11-24: Ferry 0.33.0 (freemac 1.206): printing (NSPrintInfo, NSPrintOperation, pagination, PDF output, GTK's print and page setup dialogs), NSDocument's Print… and Page Setup…, and NSFontManager with the font panel (Bold and Italic in text views), `make check` 151/151.
- 2026-11-24: Ferry 0.34.0 (freemac 1.207): UNUserNotificationCenter and NSUserNotificationCenter through the freedesktop notification server, with actions, replies and delegates; NSDockTile badges, attention requests and the Dock menu through LauncherEntry, `make check` 157/157.
- 2026-11-24: freemac 1.208 (Ferry 0.34.0): freemac's Dock shows badge labels that aren't numbers as words and the app's `applicationDockMenu:` in its right-click menu, below its windows; `make check` 157/157.
- 2026-11-24: Ferry 0.35.0 (freemac 1.209): Core Data, with models built in code or read from their Xcode source, managed objects, main-queue, private-queue and child contexts with undo and merging, fetch requests, the fetched results controller, SQLite, binary and in-memory stores with lightweight migration and batch requests, and NSArrayController in entity mode, `make check` 168/168.
- 2026-11-24: Ferry 0.36.0 (freemac 1.210): `NSGradient` and `NSShadow` (kept, not yet drawn), `NSSplitViewController` with `NSSplitViewItem` sidebars and inspectors, and `NSTabViewController` with a segmented control or the window's toolbar, which MacPass's windows are built on, `make check` 172/172.
- 2026-11-24: Ferry 0.37.0 (freemac 1.211): `NSExpression` and `NSComparisonPredicate` as public classes, with every documented form, the built-in functions, `MATCHES` and substitution variables; `NSDecimalNumber` and the `NSDecimal` functions in base 10; and in Core Data, exact decimal attributes, expression descriptions with aggregates, `propertiesToGroupBy` and `havingPredicate`, `make check` 175/175.
- 2026-11-24: Ferry 0.38.0 (freemac 1.212): `NSCollectionView` of both kinds, with the flow and grid layouts, selection, batch updates and prototypes copied from nibs, and `NSRulerView` and `NSRulerMarker` on scroll views, `make check` 179/179.
- 2026-11-24: Ferry 0.39.0 (freemac 1.213): `NSTrackingArea`, tracking and cursor rectangles and `NSCursor`; shadows drawn by Core Graphics, so `NSShadow` and the shadow text attribute show; `NSAnimation` and `NSViewAnimation`; `NSDistributedNotificationCenter` between Ferry programs on the session bus; `NSRunningApplication`; `NSMutableCharacterSet` and percent encoding; `NSTextAttachment`; and `NSAppleScript`, which runs nothing, `make check` 190/190.
- 2026-11-24: Ferry 0.40.0 (freemac 1.214): `WebKit.framework` on this system's WebKitGTK, loaded on first use: `WKWebView` with its configuration, data stores, scripts, message handlers, navigation and UI delegates and snapshots, and the older `WebView` with `WebFrame`, `WebDataSource` and `WebScriptObject`, placed over their views in AppKit's windows, `make check` 200/200.
- 2026-11-24: Ferry 0.41.0 (freemac 1.215): global hotkeys through Strata (`RegisterEventHotKey`, Carbon event handlers, global and local key monitors), enough of the Accessibility API for window managers to move and resize other apps' windows through Wayfire's IPC once the user allows them, and `NSScreen` from Wayfire's outputs, `make check` 204/204.
- 2026-11-24: Ferry 0.42.0 (freemac 1.217): the older `WebView`'s `WebFrameView` and document view with scrolling, over forty DOM classes kept in step with the page, subframes and their loads, the resource load delegate, user style sheets and new windows through the policy delegate, `make check` 206/206.
- 2026-11-25: Ferry 0.43.0 (freemac 1.219): what the nine apps call next: child windows and panels that hide with their app, login items as autostart entries (`LSSharedFileList`, `SMLoginItemSetEnabled`), directory enumerators, resource values, the trash and `NSFileCoordinator`, some seventy-five string encodings, text by line, word and sentence, Core Foundation collections with callbacks, `NSAssert` and `NSAffineTransform`, the older `WebView` no longer loses its page reports on a busy computer, `make check` 219/219.
- 2026-11-25: Ferry 0.44.0 (freemac 1.220): Quartz Window Services and posted keys behind Control Other Windows, table and outline drag and drop within the app, `CFSet` and `CFBag` with callbacks, `NSDocument` as a file presenter, and a window controller's window no longer released twice, `make check` 223/223.
- 2026-11-25: Ferry 0.45.0 (freemac 1.221): the nine apps' source compiled against Ferry's SDK and what stopped it added: the headers and BSD names every app includes first, keyboard layouts, file references, `NSArchiver` and coding without keys, `NSMapTable` and its kin, shadings, `NSScriptCommand`, and Foundation's and AppKit's older and smaller names, 418 of the apps' 637 files compiling, `make check` 231/231.
- 2026-11-25: Ferry 0.46.0 (freemac 1.222): `@import` modules; Auto Layout with a solver; the accessibility names and methods; `NSFontDescriptor`; FSEvents on inotify; Quick Look's panel and previews with `Quartz/Quartz.h`; `NSRuleEditor`; and JavaScriptCore's C and Objective-C APIs on this system's JavaScriptCore, 383 of the apps' 608 files compiling (369 before, counted the same way), `make check` 244/244.
- 2026-11-25: Ferry 0.47.0 (freemac 1.223): Flycut, Spectacle and ShiftIt link and run, with their status items, menus and windows; `ferry-ibtool` compiles document-format xibs; Apple events, Launch Services, CloudKit with no account, Scripting Bridge, uniform type identifiers, authorization, signature checks with Security transforms and what Sparkle calls; kqueue's vnode filter and `O_EVTONLY`; Foundation brings in Core Services; 428 of the apps' 627 files compiling (395 before, counted the same way), `make check` 256/256.
- 2026-11-25: Ferry 0.48.0 (freemac 1.224): global shortcuts answered (Spectacle's 18 move and size the focused window, Flycut's opens its bezel); `ferry-actool` compiles asset catalogues, so Spectacle's status item shows its picture; KeyCastr links and runs with ShortcutRecorder, Sparkle 2 and its plug-ins; CoreFoundation's notification centers, `NSXPCConnection` that never connects, bookmarks, `renamex_np`, `O_NOFOLLOW_ANY`, tab stops, three- and nine-part images and the rest of what they call; MacDown's hoedown, LibYAML and GBCli built as frameworks; 445 of the apps' 627 files compiling (435 before, counted the same way), `make check` 260/260.
- 2026-11-25: Ferry 0.49.0 (freemac 1.225): MacPass links and runs with KissXML, TransformerKit, KeePassKit, HNHUi and Sparkle built from their source, and opens, unlocks and shows a KeePass database; MacDown links and runs with its nine libraries, renders Markdown in its preview and opens its preferences; `ferry-ibtool` reads the older xib format; nib class swappers hand their place over; `NSGridView`, a small Core Image, key-value coding through indexed accessors, `NSURLComponents`, Apple event descriptors, string transforms, full case mapping, `UTType`, Security transforms' encoders, DOM ranges and a frame's JavaScriptCore context; 543 of the apps' 627 files compiling (496 before, counted the same way, with MacPass's dependencies checked out), `make check` 262/262.
- 2026-11-25: Ferry 0.50.0 (freemac 1.226): Sequel Pro links and runs, with SPMySQL built against MariaDB Connector/C built from its source, and shows its connection window, whose Connect reaches the client library; `NSColorList`, `NSMatrix`, `NSSpellChecker`, `NSPICTImageRep`, the rest of `NSCell`, a window's alpha shown, `NSCalendarDate`, `NSConnection` within one program, CFXML's entities, the DriverServices clock, the older keychain calls, the web view's history, thread cancellation and libbz2 on Mac files; 582 of the apps' 627 files compiling (543 before, counted the same way), `make check` 266/266.
- 2026-11-25: Ferry 0.51.0 (freemac 1.227): Swift programs run. Swift's runtime and standard library (swift-6.1.3-RELEASE) are built for a Mac by `swift/build-runtime.sh` and served by Ferry. `sdk/ferry-swiftc` builds Swift with the SDK's module map and API notes, with bridging headers and generated `-Swift.h` headers. There are overlays for ObjectiveC, CoreGraphics and Foundation, and a first SwiftUI of Ferry's own, drawn with AppKit (stacks, grids, lists, forms, the controls, state, observable objects, windows, settings, menu bar extras, `NSHostingView` and `NSViewRepresentable`). Objective-C and Swift call each other in one program. TomatoBar, Spaceman, Maccy, Ice and the Swift in Gas Mask and Hex Fiend were surveyed; none links yet. `make check` 270/270, with eight Swift tests that skip without a toolchain.
- 2026-11-25: Ferry 0.52.0 (freemac 1.228): the seven apps' windows laid out and drawn as on a Mac: a xib's constraints and toolbars in compiled nibs, a window's size giving way to its content's constraints, stack and split views with constraints, `-update` once after each event, pattern backgrounds, the help button, `displayedWhenStopped` read the right way and JPEG 2000 icons through OpenJPEG; MacPass's panes fill its window, MacDown shows its toolbar, KeyCastr its Sparkle window at its content's size and its icon, Flycut its bezel, `make check` 267/267.
- 2026-11-2X: Ferry 0.53.0 (freemac 1.229): every element in the seven apps' xibs made as its own class, with its attributes (text and web views, matrices, level indicators, date pickers, path controls, collection views, rule editors, Quartz Composer views, formatters, 136 elements in all); windows placed under X as on a Mac, by a xib's initial position, centred or cascaded, with moves saved under the autosave name; MacPass's inspector at the width of its nib; alerts kept on the screen; blocks as JavaScript functions and a weak `JSManagedValue`; `webkit_dom` waits for its title change; `make check` 277/277.
- 2026-11-25: Ferry 0.54.0 (freemac 1.230): TomatoBar links and runs, with SwiftState, LaunchAtLogin and KeyboardShortcuts built from their source; its menu bar item opens its popover, and Start starts its timer. Swift gets Dispatch, the concurrency library (`async`, `Task`, `@MainActor`), Combine, Foundation's value types with `JSONEncoder`, an AppKit overlay with AppKit's nested names, run loop observers, `SMAppService`, `Logger` and `AVAudioPlayer`. SwiftUI gets shapes, overlays and backgrounds by alignment, `GeometryReader`, alerts, sheets, segmented pickers and `task`. A menu bar item's popover opens in a window of its own. Hex Fiend's Swift compiles. `make check` 284/284, the Swift tests among them.
