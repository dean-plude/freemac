# Ferry: which Mac apps run

This table says how far real Mac apps get under Ferry, and what stops
each one. It is updated as Ferry grows. The apps are small open-source
Objective-C apps with Intel (x86-64) builds, downloaded from their own
GitHub release pages and run on freemac without any change. **None of
them is in this repository**: they are tested by hand, and only what
happened is written down here. Ferry's own tests (`make check`) use
programs and nibs written for Ferry.

Last checked: 2026-11-22, with Ferry 0.7.0 (milestone M6).

## Summary

No real app runs all the way yet. Five of the seven apps below start
(Ferry loads them, their libraries and frameworks, and runs their start-up
code), and four of those get through `NSApplicationMain`, their main nib
and part of their own launch code before they reach something Ferry can't
do yet. Each stops with a message that names what was missing, except
Flycut, which crashes (see below).

All 53 nib files in these apps load (with the parts Ferry lacks left out,
and a warning for each): Ferry reads both the keyed-archive nibs of older
Xcode versions and the `NIBArchive` form current Xcode writes.

## The apps

| App (version) | What it is | How far it gets | What stops it |
| --- | --- | --- | --- |
| [Hex Fiend](https://github.com/HexFiend/HexFiend) 2.18.1 | Hex editor | Doesn't start | Part of it is written in Swift (`libswiftCore.dylib`), a known limit. All 16 of its nibs (`NIBArchive`) load when tried on their own: windows, panels, menus, buttons, labels and text fields come out right; tables, scroll views, split and stack views, pop-up buttons, segmented controls, search fields, colour wells, formatters and layout constraints are left out |
| [Flycut](https://github.com/TermiT/Flycut) 1.9.6 | Clipboard history (menu bar) | Starts, loads its main nib, sets up its defaults and bindings | Crashes during `applicationDidFinishLaunching:` on a bad object pointer, not yet traced. Without it, it would next need the global hotkey calls of Carbon (`RegisterEventHotKey`) and a status bar item (`NSStatusBar`) |
| [KeyCastr](https://github.com/keycastr/keycastr) 0.9.18 | Shows the keys you press | Starts, loads its main nib (`NIBArchive`) | Its ShortcutRecorder library calls `+instanceMethodSignatureForSelector:`: Ferry has no `NSMethodSignature` or `NSInvocation` yet. It also needs to see every key pressed in other apps, which Wayland doesn't allow |
| [ShiftIt](https://github.com/fikovnik/ShiftIt) 1.6.6 | Moves and resizes other apps' windows | Starts, including its 2011 Sparkle library (built before Mac OS X 10.6, now loadable), loads its nibs | Asks for the Accessibility API (`AXIsProcessTrusted`) to move other apps' windows. That can't work as such on Wayland, where an app may not move another app's windows |
| [Spectacle](https://github.com/eczarny/spectacle) 1.2 | Window tiling by shortcut | Starts, loads its main nib and preferences nib | Carbon's global hotkeys (`GetApplicationEventTarget`, `RegisterEventHotKey`), then the Accessibility API, as for ShiftIt |
| [MacPass](https://github.com/MacPass/MacPass) 0.8.1 | KeePass password manager | Starts; all 30 of its nibs (`NIBArchive`) load on their own | Built on the document architecture: `NSDocumentController` (and `NSDocument`, `NSWindowController`, `NSViewController`) aren't in Ferry yet, so its own controller class is left out and the app stops when it makes one |
| [Gas Mask](https://github.com/2ndalpha/gasmask) 0.8.6 | Hosts-file editor (menu bar) | Doesn't start | Its program uses the start-up format of Mac OS X 10.7 and earlier (`LC_UNIXTHREAD`), which Ferry doesn't load yet. Its nib loads |

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
  bindings (set once, not yet kept up to date), `NSUserDefaults` through
  key-value coding, `+[NSValue valueWithNonretainedObject:]`,
  `-[NSDictionary initWithContentsOfFile:]`, `atexit`, a control's
  `formatter`.

## What the apps need most

Counted over the apps that start and the nibs of all seven, the gaps that come up most:

1. **`NSImage`** (imported by every app tried) and image views; image names in nibs are kept
   for it.
2. **Exceptions that can be caught** (`@try`/`@catch`): Ferry stops at the
   first exception thrown, caught or not.
3. **`NSWindowController` and `NSViewController`**, then the document
   classes (`NSDocument`, `NSDocumentController`).
4. **`NSScrollView`, `NSTableView`, `NSTextView`, `NSPopUpButton`,
   `NSBox`, `NSTabView`, `NSStackView`, `NSSplitView`** in nibs.
5. **`NSInvocation` and `NSMethodSignature`** (forwarding).
6. **`NSAlert`, `NSWorkspace`, `NSStatusBar`**, `NSUserDefaultsController`.
7. **Common libraries with Linux twins**: `libz`, `libbz2`, `libxml2`
   could come from this system, as Cairo does for drawing.
8. **Threads** (`pthread_create`, `NSThread`): Ferry runs a program on one
   thread; dispatch queues run there too.

Things that are out of reach by design on Wayland, and so will need
another approach: global hotkeys, reading other apps' key presses, and
moving other apps' windows (the Accessibility API).

## Trying an app yourself

```sh
ferry "Some App.app/Contents/MacOS/Some App"
FERRY_VERBOSE=1 ferry "Some App.app/Contents/MacOS/Some App"   # every library, missing call and class
```

Ferry prints what it leaves out on the way; the last line before it
stops says why.
