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

## VLC's Mac interface (freemac 1.NEXT, Ferry 0.NEXT)

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

## Playing a video without the window (freemac 1.NEXT, Ferry 0.NEXT)

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

## Sound (freemac 1.NEXT, Ferry 0.NEXT)

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

## Still to do

- VLC's interface still needs Core Video's display link (`VLCSliderCell.m`)
  and NSOpenGLView's `reshape` (`Windows.m`), which are being built in
  Ferry's core for VLC and OBS together. Nothing else in it is missing; its
  Core Audio calls (`NSSound+VLCAdditions.m`) build since 1.234.
- Video out needs the same OpenGL and Core Video; until then a video plays
  with sound but without its window.
- The C++ plugins need libc++ linked.
