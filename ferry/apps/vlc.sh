#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds VLC 3.0.24's Mac app from VideoLAN's own source, against Ferry's
# SDK, so it can be run under Ferry (freemac 1.232). Nothing here is
# Apple's: the compiler is clang aimed at x86_64-apple-darwin with Ferry's
# sysroot (sdk/ferry-cc), the linker ld64.lld, and the nibs come from VLC's
# .xib files through Ferry's own sdk/ferry-ibtool.
#
#   apps/vlc.sh [WORK]    (WORK as for the other recipes: apps/work by
#                          default; the build goes in build/vlc)
#
# Needs: clang, lld, llvm (llvm-ar and friends), libc++-dev and
# libc++abi-dev (VLC's C++ checks), make, pkg-config, xz, and Ferry built
# (cd ferry && make). The two source tarballs come from Ubuntu's archive,
# which carries VideoLAN's and FFmpeg's own release tarballs unchanged; the
# checksums below are those files'.
set -eu

ferry=$(cd "$(dirname "$0")/.." && pwd)
top=${1:-${FERRY_APPS_WORK:-$ferry/apps/work}}
mkdir -p "$top/src" "$top/build/vlc"
top=$(cd "$top" && pwd)
work=$top/build/vlc
jobs=$(nproc 2>/dev/null || echo 4)

vlc_ver=3.0.24
vlc_tar=vlc_$vlc_ver.orig.tar.xz
vlc_url=http://archive.ubuntu.com/ubuntu/pool/universe/v/vlc/$vlc_tar
vlc_sha=e7cab503d1d7d5849b89d2cf0e1ee60d0ef6d012407791b644b9cfc0cc225fdf
ff_ver=6.1.1
ff_tar=ffmpeg_$ff_ver.orig.tar.xz
ff_url=http://archive.ubuntu.com/ubuntu/pool/universe/f/ffmpeg/$ff_tar
ff_sha=8684f4b00f94b85461884c3719382f1261f0d9eb3d59640a1f4ac0873616f968
# FreeType, for VLC's subtitle and on-screen text (Debian's repack of the
# release, as Ubuntu's archive carries it)
ft_ver=2.13.3
ft_tar=freetype_$ft_ver+dfsg.orig.tar.xz
ft_url=http://archive.ubuntu.com/ubuntu/pool/main/f/freetype/$ft_tar
ft_sha=686ec73cbf6783b245dd068a09ce807b729ac0f8a46dd70f7867923c32fdf4de

mkdir -p "$work/bin" "$work/prefix" "$work/ffbuild" "$work/ftbuild" "$work/vlcbuild"

fetch() { # tarball url sha256
    if [ ! -f "$top/src/$1" ]; then
        curl -fL -o "$top/src/$1.part" "$2"
        mv "$top/src/$1.part" "$top/src/$1"
    fi
    echo "$3  $top/src/$1" | sha256sum -c -
}
fetch "$vlc_tar" "$vlc_url" "$vlc_sha"
fetch "$ff_tar" "$ff_url" "$ff_sha"
fetch "$ft_tar" "$ft_url" "$ft_sha"
[ -d "$top/src/vlc-$vlc_ver" ] || tar -C "$top/src" -xJf "$top/src/$vlc_tar"
[ -d "$top/src/ffmpeg-$ff_ver" ] || tar -C "$top/src" -xJf "$top/src/$ff_tar"
[ -d "$top/src/freetype-$ft_ver" ] || tar -C "$top/src" -xJf "$top/src/$ft_tar"

# The tools a Mac build expects, by their Mac names.
b=$work/bin
printf '#!/bin/sh\nexec %s "$@"\n' "$ferry/sdk/ferry-cc" > "$b/x86_64-apple-darwin-gcc"
# The C++ compiler links libc++ by itself, as a Mac's clang++ does: VLC's
# C++ modules (blend, spatializer, adaptive) are linked with it.
cat > "$b/x86_64-apple-darwin-g++" <<EOF
#!/bin/sh
for a; do case \$a in -c|-E|-S|-M|-MM) exec "$ferry/sdk/ferry-cc" "\$@";; esac; done
exec "$ferry/sdk/ferry-cc" "\$@" -lc++
EOF
for t in ar ranlib nm strip objdump; do ln -sf "$(command -v llvm-$t)" "$b/x86_64-apple-darwin-$t"; done
for t in otool lipo install-name-tool; do
    p=$(command -v llvm-$t || ls /usr/bin/llvm-$t-* 2>/dev/null | tail -n 1)
    mac=$(echo "$t" | tr - _)
    ln -sf "$p" "$b/$mac"
    ln -sf "$p" "$b/x86_64-apple-darwin-$mac"
done
printf '#!/bin/sh\nexit 0\n' > "$b/dsymutil"
cp "$b/dsymutil" "$b/x86_64-apple-darwin-dsymutil"
# Xcode's ibtool flags, as VLC's Makefile passes them, for ferry-ibtool
cat > "$b/ibtool" <<EOF
#!/bin/sh
out= in=
while [ \$# -gt 0 ]; do
  case \$1 in
    --compile) out=\$2; shift 2;;
    --module|--target-device|--minimum-deployment-target|--output-format) shift 2;;
    --*) shift;;
    *) in=\$1; shift;;
  esac
done
exec "$ferry/sdk/ferry-ibtool" --compile "\$out" "\$in"
EOF
chmod +x "$b"/*

export PATH="$b:$PATH"
export PKG_CONFIG_LIBDIR="$work/prefix/lib/pkgconfig" PKG_CONFIG_PATH=
export CC=x86_64-apple-darwin-gcc CXX=x86_64-apple-darwin-g++
export OBJC=$CC OBJCXX=$CXX

# FFmpeg's codecs and demuxers, as static libraries for VLC's avcodec,
# avformat and swscale modules. Built in plain C: nasm's Mach-O objects use a
# relocation ld64.lld refuses, and the inline assembly can't go alone, since
# swscale's inline MMXEXT code expects the vertical scaler from the nasm
# files and without it scales planar YUV pictures wrongly (VLC's subtitles,
# when it scaled them to burn them into a video, came out striped).
# (a build from an earlier recipe, with the inline assembly, is redone, and
# VLC's modules that link it are linked again)
if [ -f "$work/ffbuild/config.h" ] && grep -q 'HAVE_INLINE_ASM 1' "$work/ffbuild/config.h"; then
    rm -rf "$work/ffbuild" "$work/prefix/lib/libav"* "$work/prefix/lib/libsw"* "$work/prefix/lib/libpostproc"*
    rm -f "$work/vlcbuild/modules/"lib*avcodec_plugin.la "$work/vlcbuild/modules/"lib*avformat_plugin.la \
        "$work/vlcbuild/modules/"libswscale_plugin.la "$work/vlcbuild/modules/"libpacketizer_avparser_plugin.la
    mkdir -p "$work/ffbuild"
fi
if [ ! -f "$work/prefix/lib/libavcodec.a" ]; then
    (cd "$work/ffbuild" && "$top/src/ffmpeg-$ff_ver/configure" --prefix="$work/prefix" \
        --enable-cross-compile --target-os=darwin --arch=x86_64 \
        --cc="$CC" --cxx="$CXX" --ar=llvm-ar --ranlib=llvm-ranlib --nm=llvm-nm --strip=llvm-strip \
        --disable-programs --disable-doc --enable-static --disable-shared --enable-pic \
        --disable-autodetect --disable-devices --disable-x86asm --disable-inline-asm --disable-network \
        --enable-gpl --disable-debug &&
        make -j"$jobs" && make install)
fi

# FreeType, as a static library for VLC's freetype module, which VLC's
# preferences need (they read its options) as well as its subtitles.
if [ ! -f "$work/prefix/lib/libfreetype.a" ]; then
    (cd "$work/ftbuild" && "$top/src/freetype-$ft_ver/configure" --host=x86_64-apple-darwin \
        --prefix="$work/prefix" --enable-static --disable-shared --with-pic --without-zlib \
        --without-bzip2 --without-png --without-harfbuzz --without-brotli &&
        make -j"$jobs" && make install)
fi

# VLC itself. Libtool would take ld64.lld for GNU ld, and ld64.lld has no
# -r, so libtool is told both. VLC won't start as root unless built to,
# and Ferry's test setup runs as root. Apple's linker finds CoreFoundation's
# and Core Video's calls through the frameworks a module links (its sound
# out names only Core Audio's, its interface QuartzCore for Core Video's
# display link); ld64.lld looks only in the ones named, so every module
# names both, and drops whichever it doesn't call.
cd "$work/vlcbuild"
# (a build configured by an earlier recipe, without Core Video, FreeType or
# iconv, is redone)
[ ! -f config.status ] || { grep -q CoreVideo config.status && grep -q freetype2 config.status &&
    grep -q '"HAVE_ICONV"' config.status; } ||
    rm -f config.status
if [ ! -f config.status ]; then
    "$top/src/vlc-$vlc_ver/configure" --host=x86_64-apple-darwin --prefix="$work/vlcprefix" \
        --disable-lua --disable-sparkle --disable-nls --disable-qt --disable-skins2 \
        --disable-macosx-avfoundation --disable-a52 --disable-libgcrypt --disable-update-check \
        --disable-dbus --disable-vcd --disable-screen --enable-run-as-root \
        lt_cv_prog_gnu_ld=no lt_cv_apple_cc_single_mod=yes LDFLAGS="-Wl,-framework,CoreFoundation -Wl,-framework,CoreVideo -Wl,-dead_strip_dylibs"
fi
# A few modules still wait on parts of Ferry (docs/ferry-notes/vlc.md), so
# the rest is built around them.
make -j"$jobs" -k XIB=ibtool || echo "vlc.sh: some modules didn't build; see docs/ferry-notes/vlc.md" >&2

# Staged to run in place: vlc-osx, libvlc and libvlccore beside it in lib/,
# and every plugin that built in plugins/ (VLC_PLUGIN_PATH names it).
stage="$work/stage"
rm -rf "$stage"; mkdir -p "$stage/lib" "$stage/plugins"
cp bin/.libs/vlc-osx "$stage/"
cp -P lib/.libs/libvlc*.dylib src/.libs/libvlccore*.dylib "$stage/lib/"
find modules -path '*/.libs/*_plugin.dylib' -exec cp {} "$stage/plugins/" \;
echo "vlc.sh: staged in $stage ($(ls "$stage/plugins" | wc -l) plugins)"

# VLC.app, laid out as VLC's own "make VLC.app" lays it out
# (extras/package/macosx/package.mak), from the build tree rather than an
# install: the Info.plist, the English strings with the nibs ferry-ibtool
# compiled, every other resource side by side in Resources, and in MacOS
# the program as VLC with libvlc and libvlccore in lib/ and the plugins in
# plugins/, where its rpaths look. Run it with: ferry "$work/VLC.app" [file]
src=$top/src/vlc-$vlc_ver
app=$work/VLC.app
if [ -f "$stage/plugins/libmacosx_plugin.dylib" ]; then
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp share/macosx/Info.plist "$app/Contents/"
    printf 'APPLVLC#' > "$app/Contents/PkgInfo"
    cp -R "$src/modules/gui/macosx/Resources/"*.lproj "$app/Contents/Resources/"
    cp -R modules/gui/macosx/UI/. "$app/Contents/Resources/English.lproj/"
    find "$src/modules/gui/macosx/Resources/" -type f -not -path '*.lproj/*' -exec cp {} "$app/Contents/Resources/" \;
    cp -R "$stage/lib" "$stage/plugins" "$app/Contents/MacOS/"
    cp "$stage/vlc-osx" "$app/Contents/MacOS/VLC"
    echo "vlc.sh: VLC.app in $app"
else
    echo "vlc.sh: VLC's Mac interface didn't build, so no VLC.app; see docs/ferry-notes/vlc.md" >&2
fi
