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

## Still to do

- VLC's Cocoa interface: about 120 AppKit, Foundation and CoreGraphics names
  it uses that Ferry doesn't declare yet (custom slider, scroller and button
  cell drawing, presentation options, display fades, alert sheets).
- Video out and sound out need OpenGL, Core Video and Core Audio, which are
  being built in Ferry's core for VLC and OBS together.
- The C++ plugins need libc++ linked.
