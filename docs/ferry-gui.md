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
check` runs 67 tests (60 at M7), all passing. The new or extended ones:

| Test | Proves |
| --- | --- |
| `installer` | A package made by `tests/tools/make_pkg.py` (two components, a gzip/`070707` payload and a `pbzx`/`070701` one, an RTF licence, an HTML welcome, a member that climbs out, a link): `--info`, `--install` into test folders (apps and the rest in the right places, nothing outside them, the link kept), the same package cut short failing cleanly, and `ferry Bundled.app` running the bundle's program |
| `atomics` | Spin locks, unfair locks, the `OSAtomic` calls' results, and stderr still working after a failed `freopen` of it |
| `twins` | now also ICU's regular expressions through `libicucore` |
| `foundation_kvo` | Key-value observing: options, contexts, key paths, will/didChange around a setter, `setValue:forKey:`, removal, an observed object going away |
| `foundation_runloop` | now also cancelling delayed performs, by object and by selector |
| `appkit_bindings` | now also bindings following changes, and `NSUserDefaultsController` (applied at once, held until saved, reverted) |
| `appkit_carbon` | The Carbon, Accessibility and SystemConfiguration answers, and the smaller AppKit and Foundation pieces |
| `appkit_scrolling` | (before this report, same branch) scroll views, scrollers, text views, RTF and HTML, progress indicators, boxes |
| `appkit_panes` | (freemac 1.155) tab views and split views: layout, selection, the delegates, dragging, collapsing, holding priorities, autosaved positions, both built from a nib |

**What isn't done yet (and why).**

- **No real app is usable yet.** The next things they stop at are views
  Ferry doesn't have (`NSTabView` for Flycut, `NSSplitView` and
  `NSOutlineView` for Gas Mask, tables for Sequel Pro), `NSStatusBar` (four
  apps live in the menu bar), the document classes (MacPass, MacDown,
  Sequel Pro), and their Sparkle updaters' checks of the Mac's version file
  and code signatures. `docs/ferry-compat.md` has the list.
- **Install scripts aren't run**, by design: they expect a Mac and root.
  Packages whose files only work after their scripts (MacPorts) install
  their files but aren't usable as they are. Absolute links in a payload
  point at the Mac's paths, outside Ferry's folder.
- **Disk images need 7-Zip** (`7zip` or `p7zip-full`, now a recommended
  package); without it the Installer says so. Encrypted images aren't
  handled.
- **Key-value observing doesn't rewrite setters**: a class's own setter,
  called directly, notifies only if the class announces the change (a Mac
  makes a subclass whose setters do it). Dependent keys aren't followed.
  Bindings made in nibs are still skipped, and a control's edits aren't
  written back to the key path.
- **The desktop's "can't run graphical Mac apps yet" message.** The shell's
  `freemac-mac-app open` (outside `ferry/`, the desktop side) runs an app
  with Ferry, and when the app stops it shows Ferry's last line followed
  by "freemac can't run graphical Mac apps yet". That sentence is now out
  of date (some apps start, and the Installer is one); left for the
  desktop side to reword.

**What's next.** The views every app's nibs use (`NSTableView`,
`NSOutlineView`, `NSPopUpButton`; `NSSplitView` and `NSTabView` came in
freemac 1.155, see `appkit_panes`), then
`NSStatusBar` as a tray icon, the document classes, `NSAlert` and
`NSWorkspace`.

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
