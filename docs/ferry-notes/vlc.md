# VLC under Ferry

Notes from getting VideoLAN's VLC 3.0.24 (its Mac build, `modules/gui/macosx`)
running under Ferry, for the release notes when this lands (freemac 1.NEXT,
Ferry 0.NEXT).

## How it's built

`ferry/apps/vlc.sh [WORK]` builds VLC from VideoLAN's own release tarball and
FFmpeg 6.1.1 from FFmpeg's, both as Ubuntu's archive carries them unchanged
(the script checks their SHA-256). Nothing of VLC's or FFmpeg's is kept in
freemac's repository. The compiler is `sdk/ferry-cc` aimed at
`x86_64-apple-darwin`, the linker ld64.lld, and the nibs come from VLC's
`.xib` files through `sdk/ferry-ibtool`.

Configure needs telling three things about this toolchain: libtool would take
ld64.lld for GNU ld (`lt_cv_prog_gnu_ld=no`), ld64.lld has no `-r`
(`lt_cv_apple_cc_single_mod=yes`), and Ferry's test setup runs as root
(`--enable-run-as-root`). Lua, Qt, skins2, Sparkle, the update check and
AVFoundation capture are left out for now.

## What Ferry gained for it (first round)

libSystem, all in `src/libc_vlc.c`, `src/passthrough.c` and the SDK headers:

- Mach semaphores (`semaphore_create`, `_signal`, `_signal_all`, `_wait`,
  `_timedwait`, `_destroy`), which VLC's darwin threads are built on.
- `pathconf`/`fpathconf` (the Mac's `_PC_` numbers), `getpwuid_r`/`getpwnam_r`
  (the Mac's `struct passwd`), `sigwait`/`sigpending`/`sigsuspend` (the Mac's
  32-bit `sigset_t`), `statvfs`/`fstatvfs` (the Mac's 32-bit block counts),
  `strnstr`, `sys_errlist`/`sys_nerr` (the Mac's errno numbers),
  `__exp10`/`__exp10f`, `mach_error_string`.
- Straight from glibc, the same on both: `swab`, the 48-bit random calls,
  `tsearch` and friends, `posix_madvise`, `timespec_get`, `tempnam`,
  `backtrace`.
- Headers: `execinfo.h`, `termios.h`, `search.h`, `sys/statvfs.h`,
  `sys/file.h`, `mach/semaphore.h` and the Mach headers it needs; the
  least/fast `PRI`/`SCN` formats; `static_assert` in C; more errno names up to
  `ELAST`; `getc_unlocked`/`putc_unlocked`, `execl`/`execlp`, `S_ISBLK`.
- CFNetwork: `CFNetworkCopySystemProxySettings` and its `kCFNetworkProxies`
  keys, read from `http_proxy`, `https_proxy` and `no_proxy`.

Test: `tests/libsystem_vlc.c`.

With these, libvlccore, libvlc, the `vlc-osx` program and 249 of VLC's
plugins build.

## VLC's Mac interface (freemac 1.233, Ferry 0.57)

What VLC's Cocoa interface (`modules/gui/macosx`) calls besides, written
from Apple's public documentation:

- AppKit: presentation options, `NSBeginAlertSheet` and its informational and
  critical kinds (on NSAlert), `NSFrameRectWithWidthUsingOperation`, cell
  tracking and layout direction, slider cells' drawing parts (bar and knob
  rects, `drawBarInside:flipped:`, `drawKnob:`, tick marks), button cells'
  title, image and bezel drawing, segmented cells' `drawSegment:`, scroller
  arrows, `ancestorSharedWithView:`, `clipsToBounds`, a control's
  `selectedCell`, `constrainFrameRect:toScreen:`, magnification events, image
  cap insets, the screen's safe area and deepest screen, NSVisualEffectView,
  `getFileSystemInfoForPath:...` and `mountedRemovableMedia` (removable disks
  are those mounted under `/media`, `/run/media` and `/Volumes`),
  `initWithHTML:options:documentAttributes:`, paragraph alignment and writing
  direction in a range, and the zooming window delegate methods.
- CoreGraphics' `CGDirectDisplay.h`: display IDs, lists and bounds from
  NSScreen, and display fades as a fading full-screen window.
- MediaPlayer: the remote command center (media keys) and Now Playing.
- CoreMedia: `CMTime` and `CMTimeRange` arithmetic.
- AddressBook and AVFoundation's capture devices: both empty. OBS will want
  real capture devices; that is not here.
- Foundation: `localizedStringWithFormat:`, `compare:options:range:` (with and
  without a locale), `stringByReplacingCharactersInRange:withString:`,
  NSLocale's language directions, NSScriptCommandDescription.
- IOKit: the HID and CFPlugIn COM headers, `ev_keymap.h`, the storage media
  class names, `IOBSD.h`, and calls that answer as a Mac with no matching
  device would. CoreServices' `FSGetVolumeParms` answers "no such volume".
- Headers: `paths.h`; `OS_OBJECT_USE_OBJC` defaults on in Objective-C.

Test: `tests/appkit/vlc.m`.

## Playing a video without the window (freemac 1.235, Ferry 0.59)

VLC's own `vlc-osx`, with its core, the mp4 demuxer and FFmpeg's H.264
decoder, now plays a video to its end under Ferry and quits, with no window
and no sound (`-I dummy --no-audio --vout vdummy`). The test was a 3-second
320x240 H.264 and AAC file; VLC's scene filter saved its decoded frames as
BMP, and they match what FFmpeg decodes from the same file. Two things in
Ferry's core stood in the way:

- `pthread_cancel` never woke a thread waiting on a condition, so VLC hung
  stopping its decoder threads at the end of the file. Waiting on a
  condition is now a cancellation point, as POSIX says: the thread ends there
  with the mutex held again for its cleanup handlers (`src/pthread.c`).
- `CFRunLoopRun` on the main thread returned at once when the run loop had
  no sources. On a Mac the main queue counts as one, so it waits until
  `CFRunLoopStop`, which is how VLC's `main` waits for the interface to quit
  (`foundation/NSRunLoop.m`, `foundation/CoreFoundation.m`).
  `CFRunLoopRunInMode` still finishes when there's nothing to do.

`tests/vlc_threads.c` covers both. `apps/vlc.sh` now stages the build in
`WORK/stage` with every plugin that built; before, a hand-made stage missed
the file access plugin and VLC quit without a word. To try it (as a user
other than root, unless VLC was configured with `--enable-run-as-root`):

    cd WORK/stage
    VLC_PLUGIN_PATH=$PWD/plugins ferry ./vlc-osx -I dummy --no-audio \
        --vout vdummy --play-and-exit video.mp4

## Sound (freemac 1.237, Ferry 0.61)

VLC's own sound out, its `auhal` module, plays through Ferry's Core Audio
(freemac 1.234). With no sound server it plays into the null device, and
with `FERRY_AUDIO=null FERRY_AUDIO_OUTPUT_FILE=out.raw` the test video's
sound comes out as the same 440 Hz tone, at the same level, that FFmpeg
decodes from the file. It needed two things:

- `nil` from CoreServices in C (`auhal.c` sets a `char *` to it), as a Mac's
  MacTypes.h gives it.
- CoreFoundation named at link time. The module links Core Audio,
  AudioUnit, AudioToolbox and CoreServices and calls CoreFoundation;
  Apple's linker finds those calls through the frameworks named, ld64.lld
  doesn't, so `apps/vlc.sh` adds `-framework CoreFoundation` to every
  module's link.

    cd WORK/stage
    VLC_PLUGIN_PATH=$PWD/plugins ferry ./vlc-osx -I dummy --aout auhal \
        --vout vdummy --play-and-exit video.mp4

## VLC's window, with the picture in it (freemac 1.237, Ferry 0.61)

With Ferry's OpenGL, Core Video and CAOpenGLLayer (freemac 1.235), VLC's
whole Mac interface builds, and `apps/vlc.sh` lays out
`WORK/build/vlc/VLC.app` as VLC's own `make VLC.app` does. Run as itself,
VLC opens its main window, with its own control bar, and plays a video in
it: the picture through its `caopengllayer` video out, the sound through
`auhal`, the time and the position slider moving, to the end. Its first-run
question about album art shows as VLC's own dialog. It needed:

- Core Video named at link time too (the interface's display link), and
  `-dead_strip_dylibs`, so a module that doesn't call a framework named for
  all of them doesn't load it.
- `kCGDirectMainDisplay`, `-[NSWindow disableScreenUpdatesUntilFlush]` and
  the `NSViewLayerContentScaleDelegate` protocol, which the video outs use.
- ferry-ibtool keeping a slider's, a stepper's or a segmented control's
  cell of the app's own class (`VLCSliderCell` and the HUD cells): before,
  they came out as plain cells, and `VLCSlider` stopped on its assertion.
- The decoding threads not hanging. A cancellable wait (above) waited in
  slices and went back to waiting at the end of each; glibc may report a
  wait it was also signalled in as timed out, and that wake was then lost,
  so FFmpeg's frame threads could wait on each other for ever. The end of a
  slice now returns as a spurious wakeup would, and the waiter looks at its
  condition again.

`tests/appkit/vlc.m`, `tests/vlc_threads.c` and the `ibtool_vlc_cells`
check (`tests/appkit/vlc_cells.xib`) cover these. To try it, as a user
other than root (see above):

    ferry WORK/build/vlc/VLC.app video.mp4

## Preferences and the subtitle fonts (freemac 1.238, Ferry 0.62)

VLC's menus now answer their Command-key equivalents, and its Preferences
window opens, with every pane (Interface, Audio, Video, Subtitles / OSD,
Input / Codecs, Hotkeys). Before, Preferences stopped on an assertion: its
Subtitles pane reads the settings of VLC's subtitle renderer, the
`freetype` module, which hadn't built. It builds now, against FreeType
2.13.3, which `apps/vlc.sh` fetches from Ubuntu's archive (checked against
its SHA-256) and builds static. That needed, in Ferry:

- `setjmp`, `longjmp`, `sigsetjmp`, `siglongjmp` and the underscore forms,
  in a Mac's `jmp_buf` (37 ints; `sigjmp_buf` one more), with the signal
  mask saved and put back as a Mac does (`src/libc_vlc.c`, `setjmp.h`).
- Core Text's font descriptors, collections and
  `CTFontManagerCreateFontDescriptorsFromURL`, and `CTFontCreateForString`,
  which VLC's `darwin.c` uses to find a font's file and its fallbacks.
  Ferry answers from the fonts installed under `/usr/share/fonts` and the
  user's own, read with HarfBuzz; a font without a character falls back to
  the one Pango would pick (`graphics/CoreTextFonts.m`).
- `libkern/OSByteOrder.h`, which a Mac's CoreFoundation brings in.

VLC also showed "No document class is set for the type" at every launch,
and that alert, being modal, kept every click from its other windows. VLC
keeps the shared document controller only for its recent files and has no
document class, so a Mac opens nothing untitled for it; Ferry now opens an
untitled document at launch only for an app with a type it edits and a
class for it (`appkit/NSApplication.m`).

Tests: `tests/setjmp.c`, `tests/graphics/fonts.c`, `tests/byteorder.c`,
`tests/appkit/viewer_launch.m`.

## Subtitles, the playlist and seeking (freemac 1.238, Ferry 0.62)

VLC now shows subtitles over the video in its window, in its default font,
and its Open dialog, the playlist after stopping and seeking all work.
Ferry gained:

- iconv: `iconv_open`, `iconv` and `iconv_close`, and GNU libiconv's own
  names for them, as a Mac's `/usr/lib/libiconv.2.dylib` has them, served
  by this system's C library (`src/libc_vlc.c`, `iconv.h`, `-liconv`).
  VLC's subtitle decoder converts text files from Windows-1252, its
  default, and stopped with "cannot convert" before.
- A Mac font family that isn't installed (VLC asks for Helvetica Neue)
  matches the fonts that stand in for it, which then answer to its name, so
  VLC's FreeType module finds a file to draw with (`graphics/CoreTextFonts.m`).
- A number formatter in the old, Mac OS X 10.0 style (as VLC's Preferences
  nib has, `0%`) shows % as it is, as a Mac does, so the opacity and volume
  fields read 100% and not 10000% (`foundation/NSNumberFormatter.m`).

`apps/vlc.sh` reconfigures a build made without iconv, and its C++ compiler
now links libc++ by itself as a Mac's clang++ does, so VLC's C++ modules
(blend, spatializer, adaptive streaming) build.

Tests: `tests/iconv.c`, `tests/graphics/fonts.c`, `tests/foundation/numbers.m`.

Subtitles burned into a converted video (`--sout '#transcode{...,soverlay}'`)
now come out as on screen. They were striped and tinted whenever VLC scaled
them to fit the picture: `apps/vlc.sh` built FFmpeg without its nasm files
but with its inline assembly, and swscale's inline MMXEXT code then hands
its vertical filter, in the MMX layout, to the plain C scaler, which reads
it as the C layout. FFmpeg is now built in plain C (nasm's Mach-O objects
use a relocation ld64.lld refuses), and a build from the earlier recipe is
redone. Nothing in Ferry was wrong here.

## Opening videos from the desktop (freemac 1.NEXT)

A video double-clicked in Drawer, picked from Open With, or dropped on
VLC's Dock icon now opens in VLC, and in the copy that's already open when
there is one, as on a Mac.

- An app's entry in the app grid lists the kinds of file its Info.plist
  says it opens (`CFBundleDocumentTypes`: MIME types, extensions looked up
  in the system's file types, and Uniform Type Identifiers from a table of
  the public ones), and its command takes the files (`%F`), so Drawer,
  Get Info's Open with and the Dock offer it for them
  (`shell/freemac_shell/macapps.py`). VLC lists 57 kinds here. Folders, disks
  and "anything" aren't claimed, and nothing is made the default: Open
  With, or Get Info's Change All…, does that.
- `freemac-mac-app open VLC.app FILE...` hands the files to Ferry, which
  gives them to the app's delegate (`application:openFiles:` for VLC).
- Ferry's AppKit has each app with a bundle identifier listen on
  `$XDG_RUNTIME_DIR/ferry/<identifier>.open`, and `freemac-mac-app` tries
  it first: the running copy gets the files (or, with none, a "reopen"
  and comes forward), so a second VLC doesn't start. A copy started by
  hand from Terminal while another listens leaves it be, as on a Mac
  (`appkit/NSApplication.m`).
- The Dock finds a running Mac app's entry in the app grid rather than the
  hidden one Ferry writes for its windows, so VLC pinned to the Dock is the
  same icon when it runs, and a file dropped on it opens
  (`shell/freemac_shell/apps.py`).

Tests: `tests/appkit/open_running.m` (OpenApp.app asks its own socket from
another thread) and `shell/tests/test_macapps_open.py`.

## The sidebar and the dark panels (freemac 1.NEXT)

VLC's library sidebar now looks like a Mac source list: grey group rows
with Show and Hide on hover, and its playlist and media library icons kept
square. Media Information, Video Effects and Audio Effects open as dark,
see-through HUD panels with light text, as on a Mac, and the equalizer's
bands stand upright at their small size.

- ferry-ibtool writes a xib's `HUD` window style and works out a slider's
  direction from its frame when the xib doesn't say, and its control size.
- Windows with the HUD style draw dark, and the controls in them (text
  fields, buttons, check boxes, tabs, segmented controls, pop-ups, tables,
  outlines and sliders) draw light on dark (`appkit/NSWindow.m`,
  `AViewIsDark`).
- Auto Layout keeps a view's aspect ratio (a multiplier between its own
  width and height).

## The full Preferences (freemac 1.NEXT)

Show All in VLC's Preferences opens the full list of VLC's settings, with
every module's options, instead of freezing VLC. VLC wraps each setting's
help text with a layout manager and a text container and no text view;
Ferry's layout manager now lays text out by itself in that case, line by
line in the container's width, each line running to the next as on a Mac
(`appkit/NSTextView.m`). Before, every line came back empty and VLC's
wrapping never ended.

VLC's Open dialog shows its "Media Resource Locator (MRL)" field with a
disclosure triangle: Ferry's buttons now draw disclosure triangles and
rounded disclosure buttons, and ferry-ibtool makes a xib's disclosure
buttons stay on when clicked, so the triangle opens the field and turns
down, as on a Mac (`appkit/NSControl.m`).

Tests: `tests/appkit/layout_alone.m`, `tests/appkit/disclosure.m`, and the
disclosure triangle in `tests/appkit/ibtool.xib`.

## Pop-up menus and the other windows (freemac 1.NEXT)

VLC's pop-up menus (the Convert / Save profile, every choice in
Preferences) draw their white rounded button and blue arrow box as on a
Mac. Interface Builder writes a pop-up button's cell with the border style
"borderAndBezel", which ferry-ibtool had read as no border at all; it now
sets both (`sdk/ferry-ibtool`). Convert / Save (Shift-Command-S) and
Bookmarks (Command-B) open with their controls in place.

Test: the pop-up line in `tests/appkit/ibtool.m`.

Bookmarks' list matches its dark panel: a table's header in a HUD panel
is a faint band with light titles, and a scroll view's border there is a
faint line, not a light frame (`appkit/NSTableView.m`,
`appkit/NSScrollView.m`). ferry-ibtool also gives a scroll view the border
its xib names (none, line, bezel or groove); before, every one with a
vertical scroller got a bezel and every one without got none.

Tests: `tests/appkit/hud_table.m`, and the table's line border in
`tests/appkit/ibtool.xib`.

## Fitting the window to a small video (freemac 1.NEXT)

VLC fits its window to a video that starts playing, keeping the window's
top where it was. Ferry's `setFrame:display:` asked the window's delegate
`windowWillResize:toSize:` first, which a Mac does only while the user
resizes a window; VLC's delegate keeps the video's shape, so the window
came out taller than VLC had worked out, its top far above the screen,
and a 320x240 video left VLC's window off the top of the screen. The
frame is now taken as asked (`appkit/NSWindow.m`).

Test: `tests/appkit/set_frame.m`.

## Still to do

- The MIDI module (AudioToolbox's AUGraph) doesn't build yet.
- VideoToolbox decoding, the keychain, speech, the CD module and
  SecureTransport don't build yet.
- The download doesn't include Ferry's VLC build yet; this is Ferry's test
  setup only.
- Auto Layout places views by their frames, not their alignment rectangles,
  so where a xib spaces push buttons by their bezels (the File tab of
  VLC's Open dialog), the space comes out too small and the File tab is
  squashed; a box whose title is a check box (Capture's Video) is cut off.
