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
| M1 | Objective-C runtime (libobjc) and blocks | **done**, pull request open (see the M1 report below) |
| M2 | Foundation core + CoreFoundation basics | planned |
| M3 | Drawing: Core Graphics subset, Core Text basics (Cairo, Pango/HarfBuzz) | planned |
| M4 | AppKit minimum on Wayland | planned |
| M5 | Nibs (compiled .nib) | planned |
| M6 | Real apps, with a compatibility table in `docs/ferry-compat.md` | planned |
| M7 | Polish: Dock icons, Open/Save panels, clipboard, drag and drop, scaling | planned |

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
