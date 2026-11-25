#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/ffmpeg.sh [WORK]
#
# FFmpeg (ffmpeg.org, LGPL 2.1+), built from its release tarball as Intel
# Mac (Mach-O) dylibs and command-line tools with Ferry's SDK, for the Mac
# apps that use it (VLC, OBS) and as a test of Ferry's loader and libSystem
# (freemac 1.233, Ferry 0.57.0). It makes, in PREFIX:
#
#   lib/      libavutil, libavcodec, libavformat, libavfilter, libavdevice,
#             libswscale, libswresample (.dylib, install names @rpath/...),
#             and lib/pkgconfig/ with their .pc files
#   include/  their headers
#   bin/      ffmpeg and ffprobe, with an rpath of @executable_path/../lib
#
# Run the tools with  ./ferry PREFIX/bin/ffmpeg -i in.mp4 -f framemd5 -
#
# Environment:
#   FFMPEG_VERSION  8.0.1 (the default) or 6.1.1, the two releases pinned here
#   FFMPEG_PREFIX   where to install (WORK/build/ffmpeg-VERSION by default)
#   FFMPEG_MIRROR   a site carrying the same tarballs as ffmpeg.org/releases
#   JOBS            make -j (2 by default)
# A copy of the tarball in WORK/src (ffmpeg-VERSION.tar.xz) is used without
# fetching. Ubuntu's archive carries the same files, byte for byte, as
# ffmpeg_VERSION.orig.tar.xz, signed by FFmpeg.
#
# Software only: no hardware decoding or encoding (VideoToolbox,
# AudioToolbox), and no external libraries but zlib and bzip2, which Ferry
# serves from this system's copies. libavutil links CoreFoundation, as
# FFmpeg's configure does for any Mac. The decoders, demuxers, encoders,
# muxers and filters are a set chosen for VLC and OBS; the rest are left
# out. Needs clang, lld, llvm-ar/ranlib/nm/strip, nasm, make and curl, and
# Ferry built (make), so that sdk/lib exists. See apps/recipe.sh for WORK.
recipe_name=ffmpeg
. "$(dirname "$0")/recipe.sh"

version=${FFMPEG_VERSION:-8.0.1}
case $version in
    8.0.1) sum=05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41 ;;
    6.1.1) sum=8684f4b00f94b85461884c3719382f1261f0d9eb3d59640a1f4ac0873616f968 ;;
    *) die "FFMPEG_VERSION is 8.0.1 or 6.1.1, the releases pinned here" ;;
esac
[ -f "$sdk/lib/libSystem.tbd" ] || die "build Ferry first (make in $top), so that $sdk/lib exists"
fetch_release "ffmpeg-$version" "${FFMPEG_MIRROR:-https://ffmpeg.org/releases}/ffmpeg-$version.tar.xz" "$sum"

build=$work/build/ffmpeg-$version.obj
prefix=${FFMPEG_PREFIX:-$work/build/ffmpeg-$version}
mkdir -p "$build" "$prefix"
prefix=$(cd "$prefix" && pwd)

# The parts VLC's avcodec, avformat and swscale modules and OBS's obs-ffmpeg
# plugin use, plus what ffmpeg and ffprobe need to decode, filter and write
# framemd5 or raw output.
decoders="h264 hevc aac aac_latm vp8 vp9 vorbis opus theora vp3 mp3 mp3float mp2 mp2float mp1 \
flac alac ac3 eac3 mpeg4 mpeg2video mpeg1video mjpeg png rawvideo wrapped_avframe ffv1 utvideo prores \
pcm_s16le pcm_s16be pcm_s24le pcm_s32le pcm_f32le pcm_u8 pcm_alaw pcm_mulaw"
encoders="aac opus flac alac ac3 mpeg4 mpeg2video mjpeg png ffv1 utvideo prores_ks rawvideo \
wrapped_avframe pcm_s16le pcm_s24le pcm_s32le pcm_f32le"
demuxers="mov matroska webm_dash_manifest ogg mp3 aac h264 hevc m4v mpegvideo wav flac ac3 eac3 \
flv mpegts mpegps avi image2 image2pipe rawvideo pcm_s16le"
muxers="mp4 mov ipod matroska webm ogg opus flv mpegts hls segment wav null framemd5 framecrc md5 \
crc rawvideo pcm_s16le image2 adts mp3 flac"
parsers="h264 hevc aac aac_latm vp8 vp9 vorbis opus vp3 mpegaudio flac ac3 mpeg4video \
mpegvideo mjpeg png"
protocols="file pipe tcp udp rtmp http"
filters="buffer abuffer buffersink abuffersink format aformat null anull scale aresample \
setpts asetpts trim atrim fps copy split asplit concat volume amix pan \
hflip vflip transpose crop pad overlay rotate showinfo ashowinfo \
anullsrc nullsrc color testsrc sine settb asettb fifo afifo"
list() { pfx=$1; shift; for c in $*; do printf ' --enable-%s=%s' "$pfx" "$c"; done; }

# configured again whenever this recipe, the prefix or the calls Ferry serves change
stamp="$prefix $(cksum < "$0") $(cksum < "$sdk/lib/libSystem.tbd")"
if [ ! -f "$build/ffbuild/config.mak" ] || [ "$(cat "$build/.configured" 2>/dev/null)" != "$stamp" ]; then
    say "configuring FFmpeg $version"
    # --disable-everything comes first: the --enable-... after it pick the parts.
    # shellcheck disable=SC2046
    (cd "$build" && "$src/ffmpeg-$version/configure" --prefix="$prefix" --disable-everything \
        --enable-cross-compile --target-os=darwin --arch=x86_64 \
        --cc="$sdk/ferry-cc" --cxx="$sdk/ferry-cc" --host-cc=cc \
        --ar=llvm-ar --ranlib=llvm-ranlib --nm=llvm-nm --strip=llvm-strip --x86asmexe=nasm \
        --pkg-config=false --install-name-dir=@rpath \
        --extra-ldexeflags='-Wl,-rpath,@executable_path/../lib' \
        --enable-shared --disable-static --enable-pic --disable-stripping --disable-doc \
        --disable-autodetect --enable-zlib --enable-bzlib --disable-lzma --disable-iconv \
        --disable-hwaccels --disable-videotoolbox --disable-audiotoolbox \
        --disable-appkit --disable-avfoundation --disable-coreimage \
        --disable-metal --disable-indevs --disable-outdevs --enable-indev=lavfi \
        --enable-avdevice --enable-avfilter --enable-swscale --enable-swresample \
        --enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-network \
        $(list decoder $decoders) $(list encoder $encoders) $(list demuxer $demuxers) \
        $(list muxer $muxers) $(list parser $parsers) $(list protocol $protocols) \
        $(list filter $filters) --enable-bsfs) > "$build/configure.log" 2>&1 ||
        { tail -20 "$build/configure.log" >&2; die "configure failed (its log: $build/ffbuild/config.log)"; }
    echo "$stamp" > "$build/.configured"
fi
say "building FFmpeg $version (make -j${JOBS:-2})"
(cd "$build" && make -j"${JOBS:-2}" && make install) > "$build/make.log" 2>&1 ||
    { grep -E 'error' "$build/make.log" | head -20 >&2; die "FFmpeg didn't build (its log: $build/make.log)"; }
say "done: $prefix"
