#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/obs.sh [WORK]
#
# OBS Studio 33.0.3's Mac app, built from OBS's own source at a pinned
# commit with Ferry's SDK, so that ./ferry runs it: its main window and
# preview, screen capture (mac-capture, over Ferry's ScreenCaptureKit) and
# x264 recording with sound through FFmpeg, and its other sources, filters,
# transitions and Tools menu (freemac 1.NEXT, Ferry 0.NEXT; what works and
# what doesn't yet is in docs/ferry-notes/obs.md). Everything it uses is
# fetched from its project's own repository or release and built here too:
#
#   Qt 6.11.1      qtbase and qtsvg, as frameworks (and a build of qtbase
#                  for this system, whose moc, rcc and uic the Mac build
#                  runs); its Cocoa platform plugin draws through Ferry's
#                  AppKit
#   FFmpeg 8.0.1   by apps/ffmpeg.sh
#   x264, mbedtls 3.6.2, jansson 2.14.1, nlohmann/json 3.11.3, SIMDe 0.8.2,
#   uthash 2.3.0, and FreeType from qtbase's own copy
#
# Nothing of Apple's is used: the compiler is clang aimed at
# x86_64-apple-macos with Ferry's headers, the linker ld64.lld, the asset
# catalogue goes through sdk/ferry-actool. Two small patches, in
# apps/obs/, are applied to the checkouts: qtbase.patch lets Qt's Cocoa
# plugin build without Metal (Ferry draws Qt's windows through Core
# Animation layers, not Metal), and obs-studio.patch lets OBS's CMake
# build a Mac app with Ninja instead of Xcode, skip the modules Ferry has
# nothing for and include two headers a Mac's SDK brings in by itself.
#
# Left out: the browser source and docks (CEF), obs-websocket, VST,
# scripting, virtual camera, Syphon, AJA and Decklink cards, VideoToolbox
# and Core Audio's AAC encoder (Ferry has neither; FFmpeg's AAC encoder
# serves), and the camera source (mac-avcapture, until Ferry's
# AVCaptureDevice lists cameras). docs/ferry-notes/obs.md has the details.
#
# The app lands at WORK/build/obs/OBS.app, with its Qt frameworks and
# plugins inside it. Run it with
#
#   ./ferry WORK/build/obs/OBS.app [--startrecording] [--collection NAME]
#
# Screen capture needs the app allowed to record the screen (Settings, or
# freemac-allow-control com.obsproject.obs-studio).
#
# Needs: clang, lld and llvm (llvm-ar, llvm-otool, llvm-install-name-tool),
# libc++-dev, cmake (3.28 or later), ninja, nasm, make, pkg-config, git,
# curl, python3, and Ferry built (make). A first build compiles Qt twice
# and takes a while (an hour or more on four cores); a second run only
# rebuilds what changed. FERRY_APPS_JOBS sets the parallel jobs (2 by
# default). See apps/recipe.sh for WORK.
recipe_name=obs
. "$(dirname "$0")/recipe.sh"

jobs=${FERRY_APPS_JOBS:-2}
patches=$top/apps/obs
build=$work/build/obs
deps=$build/deps
qt=$build/qt
qthost=$build/qt-host
bin=$build/bin
app=$build/OBS.app
mkdir -p "$build" "$deps/lib" "$deps/include" "$bin" "$build/sysroot"

for tool in cmake ninja nasm make pkg-config git curl python3 clang; do
    command -v "$tool" > /dev/null 2>&1 || die "$tool isn't installed"
done
[ -f "$sdk/lib/libSystem.tbd" ] || die "build Ferry first (make in $top), so that $sdk/lib exists"
[ -d "$top/frameworks/AppKit.framework" ] || die "build Ferry first (make in $top): its frameworks are missing"

# LLVM's tools, from the folder that holds ld64.lld
llvm=
for candidate in "$(command -v ld64.lld 2>/dev/null || true)" /usr/lib/llvm-*/bin/ld64.lld; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then llvm=$(dirname "$(readlink -f "$candidate")"); break; fi
done
[ -n "$llvm" ] || die "LLVM's Mach-O linker (ld64.lld, package lld) isn't installed"
for t in llvm-ar llvm-ranlib llvm-nm llvm-strip llvm-otool llvm-install-name-tool llvm-lipo; do
    [ -x "$llvm/$t" ] || die "$t isn't installed (package llvm, beside $llvm/ld64.lld)"
done
cxxinc=$(cd "$llvm/.." && pwd)/include/c++/v1
[ -f "$cxxinc/__config" ] || cxxinc=/usr/include/c++/v1
[ -f "$cxxinc/__config" ] || die "LLVM's libc++ headers (package libc++-dev) aren't installed"

# The compilers CMake, Qt and the configure scripts are given (named
# mac-cc and mac-c++, so that the build of Qt for this system still finds
# this system's own cc): clang for
# macOS 12 with Ferry's headers and libraries, without clang modules (Qt's
# and OBS's Objective-C++ include headers in the classic way), and the
# C++ one with libc++, as a Mac's clang++ links it.
cat > "$bin/mac-cc" <<EOF
#!/bin/sh
exec clang -target x86_64-apple-macos\${FERRY_MACOS_MIN:-12} -nostdlibinc -isystem "$sdk/include" \\
  -idirafter "$sdk/usr/include" -fno-stack-protector -Wno-unused-command-line-argument -fno-modules \\
  -nostdlib -B"$llvm" -fuse-ld=lld -L"$sdk/lib" -F"$top/frameworks" -lSystem -lobjc "\$@"
EOF
cat > "$bin/mac-c++" <<EOF
#!/bin/sh
exec clang++ -target x86_64-apple-macos\${FERRY_MACOS_MIN:-12} -nostdlibinc -nostdinc++ -isystem "$cxxinc" \\
  -isystem "$sdk/include" -idirafter "$sdk/usr/include" -fno-stack-protector -Wno-unused-command-line-argument \\
  -fno-modules -nostdlib -B"$llvm" -fuse-ld=lld -L"$sdk/lib" -F"$top/frameworks" -lSystem -lc++ -lobjc "\$@"
EOF
# What Qt's and CMake's Mac checks ask xcrun and xcodebuild: an SDK folder
# (an empty one: the headers come from the compiler's own -isystem) and
# versions new enough for them.
for t in xcrun xcodebuild; do
    cat > "$bin/$t" <<EOF
#!/bin/sh
for a in "\$@"; do case \$a in
  --show-sdk-path|--show-sdk-platform-path) echo "$build/sysroot"; exit 0 ;;
  --show-sdk-version) echo 14.5; exit 0 ;;
esac; done
case "\$*" in *-version*) echo "Xcode 15.4"; echo "Build version 15F31d"; exit 0 ;; esac
echo "$t: not available here (Ferry's OBS recipe): \$*" >&2
exit 1
EOF
done
for t in ar ranlib nm strip otool install-name-tool lipo; do ln -sf "$llvm/llvm-$t" "$bin/$t"; done
ln -sf "$llvm/llvm-install-name-tool" "$bin/install_name_tool"
chmod +x "$bin/mac-cc" "$bin/mac-c++" "$bin/xcrun" "$bin/xcodebuild"
# libm, libpthread and libdl, which a Mac's SDK has as names for libSystem
# (x264's configure links them)
mkdir -p "$build/libalias"
for l in m pthread dl; do cp "$sdk/lib/libSystem.tbd" "$build/libalias/lib$l.tbd"; done

cat > "$build/toolchain.cmake" <<EOF
# Intel Mac binaries, built on Linux against Ferry's SDK (apps/obs.sh)
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_VERSION 21.0)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_OSX_ARCHITECTURES x86_64)
set(CMAKE_OSX_DEPLOYMENT_TARGET 12.0)
set(CMAKE_OSX_SYSROOT "$build/sysroot")
set(CMAKE_C_COMPILER "$bin/mac-cc")
set(CMAKE_CXX_COMPILER "$bin/mac-c++")
set(CMAKE_OBJC_COMPILER "$bin/mac-cc")
set(CMAKE_OBJCXX_COMPILER "$bin/mac-c++")
set(CMAKE_AR "$llvm/llvm-ar")
set(CMAKE_RANLIB "$llvm/llvm-ranlib")
set(CMAKE_NM "$llvm/llvm-nm")
set(CMAKE_STRIP "$llvm/llvm-strip")
set(CMAKE_INSTALL_NAME_TOOL "$llvm/llvm-install-name-tool")
set(CMAKE_OTOOL "$llvm/llvm-otool")
set(CMAKE_LIPO "$llvm/llvm-lipo")
set(CMAKE_FRAMEWORK_PATH "$top/frameworks")
set(CMAKE_FIND_ROOT_PATH "$deps" "$qt" "$top" "$sdk" "$sdk/usr")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
set(CMAKE_FIND_FRAMEWORK FIRST)
set(CMAKE_PROGRAM_PATH "$bin")
EOF
export PATH="$bin:$PATH"
export PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig" PKG_CONFIG_PATH=
tc="-DCMAKE_TOOLCHAIN_FILE=$build/toolchain.cmake"

# step NAME KEY: true when NAME hasn't been built with KEY yet; done_step
# NAME KEY marks it built.
step() { [ "$(cat "$build/.done-$1" 2>/dev/null)" != "$2" ]; }
done_step() { echo "$2" > "$build/.done-$1"; }
# run NAME COMMAND...: COMMAND's output into NAME.log, its last lines shown if it fails
run() {
    run_log=$build/$1.log
    shift
    "$@" > "$run_log" 2>&1 || { grep -E 'error|Error' "$run_log" | head -20 >&2; tail -5 "$run_log" >&2; die "failed: $* (its log: $run_log)"; }
}

# fetch_patched NAME URL COMMIT PATCH: fetch, with PATCH applied. A checkout
# already patched with this PATCH is left as it is (so nothing in it is
# rebuilt); another is put back to its commit and patched again.
fetch_patched() {
    fp_dir=$src/$1 fp_key="$3 $(cksum < "$4")"
    if [ "$(cat "$fp_dir/.git/ferry-patched" 2>/dev/null)" = "$fp_key" ] &&
       [ "$(git -C "$fp_dir" rev-parse HEAD 2>/dev/null)" = "$3" ]; then
        return 0
    fi
    [ ! -d "$fp_dir/.git" ] || git -C "$fp_dir" checkout -q -- .
    fetch "$1" "$2" "$3"
    git -C "$fp_dir" apply "$4" || die "$4 doesn't apply to $1"
    echo "$fp_key" > "$fp_dir/.git/ferry-patched"
}

qt_commit=59c81a3c2247b821b9b84b4eb8d939b77e07e276      # qtbase v6.11.1
qtsvg_commit=2596f43da2dc72d2afecc084355b0f5f87922a6c   # qtsvg v6.11.1
obs_commit=f2aa9ce69caa7239ef26660b5889de4f53d9880e     # OBS Studio 33.0.3
obs_version=33.0.3
fetch_patched qtbase https://github.com/qt/qtbase "$qt_commit" "$patches/qtbase.patch"
fetch qtsvg https://github.com/qt/qtsvg "$qtsvg_commit"
fetch_patched obs-studio https://github.com/obsproject/obs-studio "$obs_commit" "$patches/obs-studio.patch"
fetch x264 https://github.com/mirror/x264 c24e06c2e184345ceb33eb20a15d1024d9fd3497
fetch mbedtls https://github.com/Mbed-TLS/mbedtls 107ea89daaefb9867ea9121002fbbdf926780e98  # v3.6.2
submodule mbedtls framework https://github.com/Mbed-TLS/mbedtls-framework
fetch jansson https://github.com/akheron/jansson ed5cae4ed0621ef409510f94270c9f8f263736d0   # v2.14.1
fetch json https://github.com/nlohmann/json 9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03     # v3.11.3
fetch simde https://github.com/simd-everywhere/simde 71fd833d9666141edcd1d3c109a80e228303d8d7  # v0.8.2
fetch uthash https://github.com/troydhanson/uthash e493aa90a2833b4655927598f169c31cfcdf7861   # v2.3.0

# Qt for this system: only its build tools (moc, rcc, uic and the rest)
# are used, by the Mac build of Qt and by OBS's.
if step qt-host "$qt_commit"; then
    say "building Qt for this system (its build tools)"
    run qt-host-configure env -u CC -u CXX -u OBJC -u OBJCXX cmake -S "$src/qtbase" -B "$build/qt-host.obj" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$qthost" \
        -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DFEATURE_xcb=OFF -DFEATURE_wayland=OFF -DINPUT_opengl=no \
        -DFEATURE_dbus=OFF -DFEATURE_glib=OFF -DFEATURE_sql=OFF -DFEATURE_printsupport=OFF -DFEATURE_testlib=OFF \
        -DFEATURE_concurrent=OFF -DFEATURE_vulkan=OFF -DINPUT_openssl=no -DFEATURE_icu=OFF \
        -DFEATURE_fontconfig=OFF -DFEATURE_system_harfbuzz=OFF --fresh
    run qt-host-build ninja -C "$build/qt-host.obj" -j"$jobs" install
    done_step qt-host "$qt_commit"
fi

# Qt for Ferry: frameworks with @rpath install names, as a Mac's Qt has.
qt_link="-framework Foundation -framework CoreGraphics -framework CoreText -lz"
qt_names() {
    for f in "$qt"/lib/Qt*.framework/Versions/A/Qt* $(find "$qt/plugins" -name '*.dylib'); do
        [ -f "$f" ] || continue
        case $f in *.prl) continue ;; esac
        args=
        id=$(otool -D "$f" | sed -n 2p)
        case $id in Qt*.framework/*) args="-id @rpath/$id" ;; esac
        for dep in $(otool -L "$f" | sed -n '2,$p' | awk '{print $1}'); do
            case $dep in Qt*.framework/*) args="$args -change $dep @rpath/$dep" ;; esac
        done
        # shellcheck disable=SC2086
        [ -z "$args" ] || install_name_tool $args "$f" 2> /dev/null || true
    done
}
qt_key="$qt_commit $(cksum < "$patches/qtbase.patch")"
if step qt "$qt_key"; then
    say "building Qt 6.11.1 for Ferry"
    # Qt's features that Ferry's headers now let it detect but that OBS was
    # first tried without (Metal frame capture, SecureTransport, System V
    # shared memory, backtrace) are kept off, so the build stays the tried one
    run qt-configure cmake -S "$src/qtbase" -B "$build/qt.obj" -G Ninja $tc -DCMAKE_BUILD_TYPE=Release \
        -DQT_HOST_PATH="$qthost" -DCMAKE_INSTALL_PREFIX="$qt" -DBUILD_SHARED_LIBS=ON -DQT_FEATURE_framework=ON \
        -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DFEATURE_dbus=OFF -DFEATURE_glib=OFF -DFEATURE_sql=OFF \
        -DFEATURE_printsupport=OFF -DFEATURE_testlib=OFF -DFEATURE_qmake=OFF -DFEATURE_macdeployqt=OFF \
        -DINPUT_openssl=no -DFEATURE_brotli=OFF -DFEATURE_pdf=OFF -DFEATURE_system_zlib=OFF \
        -DFEATURE_system_pcre2=OFF -DFEATURE_system_png=OFF -DFEATURE_system_jpeg=OFF \
        -DFEATURE_system_doubleconversion=OFF -DFEATURE_icu=OFF -DFEATURE_vulkan=OFF -DFEATURE_metal=OFF \
        -DINPUT_opengl=no -DFEATURE_concurrent=ON -DFEATURE_separate_debug_info=OFF \
        -DFEATURE_force_debug_info=OFF -DFEATURE_permissions=OFF -DFEATURE_backtrace=OFF \
        -DFEATURE_graphicsframecapture=OFF -DFEATURE_securetransport=OFF -DFEATURE_ssl=OFF -DFEATURE_sharedmemory=OFF \
        -DFEATURE_sysv_sem=OFF -DFEATURE_sysv_shm=OFF -DFEATURE_memrchr=OFF \
        -DCMAKE_SHARED_LINKER_FLAGS="$qt_link" -DCMAKE_MODULE_LINKER_FLAGS="$qt_link" --fresh
    run qt-build ninja -C "$build/qt.obj" -j"$jobs" install
    qt_names
    done_step qt "$qt_key"
fi
if step qtsvg "$qtsvg_commit $qt_key"; then
    say "building Qt SVG for Ferry"
    run qtsvg-configure cmake -S "$src/qtsvg" -B "$build/qtsvg.obj" -G Ninja $tc -DCMAKE_BUILD_TYPE=Release \
        -DQT_HOST_PATH="$qthost" -DCMAKE_PREFIX_PATH="$qt" -DCMAKE_INSTALL_PREFIX="$qt" \
        -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
        -DCMAKE_SHARED_LINKER_FLAGS="$qt_link" -DCMAKE_MODULE_LINKER_FLAGS="$qt_link" --fresh
    run qtsvg-build ninja -C "$build/qtsvg.obj" -j"$jobs" install
    qt_names
    done_step qtsvg "$qtsvg_commit $qt_key"
fi

# FFmpeg's libraries, by their own recipe, into deps
say "FFmpeg (apps/ffmpeg.sh)"
FFMPEG_PREFIX=$deps JOBS=$jobs sh "$top/apps/ffmpeg.sh" "$work" || die "FFmpeg didn't build"

# x264, OBS's H.264 encoder, in C (its assembly is nasm's, which ld64.lld
# can't link in Mach-O)
if step x264 c24e06c2e184345ceb33eb20a15d1024d9fd3497; then
    say "building x264"
    rm -rf "$build/x264.obj"; mkdir -p "$build/x264.obj"
    (cd "$build/x264.obj" && run x264-configure env CC=mac-cc AR=ar RANLIB=ranlib STRIP=strip \
        "$src/x264/configure" --host=x86_64-apple-darwin --prefix="$deps" --enable-shared --disable-cli \
        --disable-asm --extra-ldflags="-L$build/libalias" &&
        run x264-build make -j"$jobs" && run x264-install make install)
    install_name_tool -id @rpath/libx264.164.dylib "$deps/lib/libx264.164.dylib"
    done_step x264 c24e06c2e184345ceb33eb20a15d1024d9fd3497
fi

# mbedtls (OBS's RTMPS), jansson (its JSON in C), nlohmann/json, and the
# header-only SIMDe and uthash
cmake_dep() { # NAME [cmake options]
    cd_name=$1
    shift
    run "$cd_name-configure" cmake -S "$src/$cd_name" -B "$build/$cd_name.obj" -G Ninja $tc \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$deps" --fresh "$@"
    run "$cd_name-build" ninja -C "$build/$cd_name.obj" -j"$jobs" install
}
# (their install names stay plain: an @rpath one in their CMake files makes
# OBS's CMake, which isn't on a real Mac, refuse them; the app's copies get
# @rpath names below)
if step libs 3; then
    say "building mbedtls, jansson and json"
    cmake_dep mbedtls -DUSE_SHARED_MBEDTLS_LIBRARY=ON -DUSE_STATIC_MBEDTLS_LIBRARY=OFF -DENABLE_PROGRAMS=OFF \
        -DENABLE_TESTING=OFF -DMBEDTLS_FATAL_WARNINGS=OFF -DPython3_EXECUTABLE="$(command -v python3)"
    cmake_dep jansson -DJANSSON_BUILD_SHARED_LIBS=ON -DJANSSON_BUILD_DOCS=OFF -DJANSSON_EXAMPLES=OFF \
        -DJANSSON_WITHOUT_TESTS=ON
    cmake_dep json -DJSON_BuildTests=OFF
    cp "$src/uthash/src/"*.h "$deps/include/"
    rm -rf "$deps/include/simde"; cp -R "$src/simde/simde" "$deps/include/"
    done_step libs 3
fi

# FreeType for OBS's text source, a static library from qtbase's own copy
# (2.14), with its own gzip code rather than zlib's
if step freetype "$qt_commit"; then
    say "building FreeType"
    ft=$src/qtbase/src/3rdparty/freetype
    rm -rf "$build/freetype.obj"; mkdir -p "$build/freetype.obj"
    for f in autofit/autofit.c base/ftbase.c base/ftbbox.c base/ftbdf.c base/ftbitmap.c base/ftcid.c \
        base/ftfstype.c base/ftgasp.c base/ftglyph.c base/ftgxval.c base/ftinit.c base/ftmm.c base/ftotval.c \
        base/ftpatent.c base/ftpfr.c base/ftstroke.c base/ftsynth.c base/fttype1.c base/ftwinfnt.c \
        base/ftdebug.c base/ftsystem.c bdf/bdf.c cache/ftcache.c cff/cff.c cid/type1cid.c gzip/ftgzip.c \
        lzw/ftlzw.c pcf/pcf.c pfr/pfr.c psaux/psaux.c pshinter/pshinter.c psnames/psnames.c raster/raster.c \
        sdf/sdf.c sfnt/sfnt.c smooth/smooth.c svg/svg.c truetype/truetype.c type1/type1.c type42/type42.c \
        winfonts/winfnt.c; do
        mac-cc -O2 -DFT2_BUILD_LIBRARY -I"$ft/include" -c "$ft/src/$f" \
            -o "$build/freetype.obj/$(echo "$f" | tr / _ | sed 's/\.c$/.o/')" || die "FreeType's $f didn't compile"
    done
    rm -f "$deps/lib/libfreetype.a"
    ar rcs "$deps/lib/libfreetype.a" "$build/freetype.obj/"*.o
    rm -rf "$deps/include/freetype2"; mkdir -p "$deps/include/freetype2"
    cp -R "$ft/include/." "$deps/include/freetype2/"
    done_step freetype "$qt_commit"
fi

# OBS Studio
skip="aja;aja-output-ui;decklink;decklink-captions;decklink-output-ui;mac-syphon;mac-virtualcam"
skip="$skip;mac-videotoolbox;coreaudio-encoder;obs-browser;obs-libfdk;obs-vst;obs-webrtc;obs-websocket"
skip="$skip;vlc-video;mac-avcapture"
obs_key="$obs_commit $(cksum < "$patches/obs-studio.patch") $skip $qt_key"
if step obs-configure "$obs_key" || [ ! -f "$build/obs.obj/build.ninja" ]; then
    say "configuring OBS Studio $obs_version"
    run obs-configure cmake -S "$src/obs-studio" -B "$build/obs.obj" -G Ninja $tc -DCMAKE_BUILD_TYPE=Release \
        -DOBS_FERRY=ON -DOBS_VERSION_OVERRIDE="$obs_version" -DQT_HOST_PATH="$qthost" \
        -DCMAKE_PREFIX_PATH="$deps;$qt" -DOBS_FERRY_SKIP_MODULES="$skip" \
        -DENABLE_SCRIPTING=OFF -DENABLE_BROWSER=OFF -DENABLE_WEBSOCKET=OFF -DENABLE_VST=OFF \
        -DENABLE_SPARKLE_UPDATER=OFF -DENABLE_AJA=OFF -DENABLE_DECKLINK=OFF -DENABLE_VIRTUALCAM=OFF \
        -DENABLE_WHATSNEW=OFF -DENABLE_WEBRTC=OFF -DENABLE_NVENC=OFF -DENABLE_QSV11=OFF -DENABLE_UPDATER=OFF \
        -DENABLE_PLUGINS_TESTS=OFF -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF -DENABLE_NEW_MPEGTS_OUTPUT=OFF \
        -DENABLE_SPEEXDSP=OFF -DENABLE_RNNOISE=OFF --fresh
    done_step obs-configure "$obs_key"
fi
say "building OBS Studio $obs_version (ninja -j$jobs)"
# Xcode makes the app's Frameworks folder before OBS's post-build step
# links libobs-frontend-api into it; Ninja doesn't.
mkdir -p "$build/obs.obj/frontend/OBS.app/Contents/Frameworks"
run obs-build ninja -C "$build/obs.obj" -j"$jobs"
rm -rf "$build/obs.install"
run obs-install cmake --install "$build/obs.obj" --prefix "$build/obs.install"

# OBS.app, laid out as OBS's own Xcode build and macdeployqt lay it out:
# libobs, its OpenGL module, the frontend API and the libraries it uses
# in Frameworks with Qt's frameworks; OBS's modules, and Qt's plugins
# beside them, in PlugIns; every install name on @rpath.
say "laying out OBS.app"
o=$build/obs.obj
rm -rf "$app"
cp -R "$build/obs.install/OBS.app" "$app"
c=$app/Contents
mkdir -p "$c/Frameworks" "$c/PlugIns"
cp -R "$o/libobs/libobs.framework" "$c/Frameworks/"
cp "$o/libobs-opengl/libobs-opengl.dylib" "$c/Frameworks/"
# OBS's install leaves the frontend API as a link to a library it doesn't
# install; the library itself goes in its place.
rm -f "$c/Frameworks/libobs-frontend-api.1.dylib"
for f in "$o/frontend/OBS.app/Contents/Frameworks/libobs-frontend-api.1.dylib" "$o/frontend/api/obs-frontend-api.dylib"; do
    if [ -f "$f" ]; then cp -L "$f" "$c/Frameworks/libobs-frontend-api.1.dylib"; break; fi
done
[ -f "$c/Frameworks/libobs-frontend-api.1.dylib" ] || die "OBS's frontend API library didn't build"
for d in libavcodec.62 libavformat.62 libavutil.60 libswscale.9 libswresample.6 libavdevice.62 libavfilter.11 \
    libjansson.4 libx264.164 libmbedtls.21 libmbedcrypto.16 libmbedx509.7; do
    [ -f "$deps/lib/$d.dylib" ] || die "$deps/lib/$d.dylib is missing"
    cp -L "$deps/lib/$d.dylib" "$c/Frameworks/$d.dylib"
done
for p in "$o"/plugins/*/*.plugin; do
    [ -d "$p" ] || continue
    rm -rf "$c/PlugIns/$(basename "$p")"
    cp -R "$p" "$c/PlugIns/"
done
for fw in QtCore QtGui QtWidgets QtNetwork QtSvg QtSvgWidgets QtXml QtConcurrent; do
    cp -R "$qt/lib/$fw.framework" "$c/Frameworks/"
    rm -rf "$c/Frameworks/$fw.framework/Headers" "$c/Frameworks/$fw.framework/Versions/A/Headers"
done
for kind in platforms imageformats iconengines styles tls networkinformation; do
    [ -d "$qt/plugins/$kind" ] && cp -R "$qt/plugins/$kind" "$c/PlugIns/"
done
printf '[Paths]\nPlugins = PlugIns\n' > "$c/Resources/qt.conf"

# every library OBS built or brought in found through @rpath
fix() { # FILE: its non-system dependencies on @rpath/NAME
    otool -L "$1" | sed -n '2,$p' | awk '{print $1}' | while read -r dep; do
        case $dep in
            /usr/lib/*|/System/*|@rpath/*|@executable_path/*|@loader_path/*) ;;
            *libobs.framework/Versions/A/libobs) install_name_tool -change "$dep" @rpath/libobs.framework/Versions/A/libobs "$1" ;;
            *obs-frontend-api*.dylib) install_name_tool -change "$dep" @rpath/libobs-frontend-api.1.dylib "$1" ;;
            *) install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$1" ;;
        esac
    done
}
rpath() { # FILE RPATH...
    rp_file=$1
    shift
    for rp in "$@"; do install_name_tool -add_rpath "$rp" "$rp_file" 2> /dev/null || true; done
}
libobs=$c/Frameworks/libobs.framework/Versions/A/libobs
install_name_tool -id @rpath/libobs.framework/Versions/A/libobs "$libobs"
for f in "$c/Frameworks/"*.dylib; do install_name_tool -id "@rpath/$(basename "$f")" "$f"; done
for f in "$libobs" "$c/Frameworks/"*.dylib "$c/MacOS/"* "$c"/PlugIns/*.plugin/Contents/MacOS/*; do
    fix "$f"
done
for f in "$c/MacOS/"*; do rpath "$f" @executable_path/../Frameworks; done
rpath "$libobs" @loader_path/../../..
for f in "$c/Frameworks/"*.dylib; do rpath "$f" @loader_path; done
for f in "$c"/PlugIns/*.plugin/Contents/MacOS/*; do rpath "$f" @loader_path/../../../../Frameworks; done
for f in "$c"/PlugIns/*/*.dylib; do rpath "$f" @loader_path/../../Frameworks; done

# its icon from its asset catalogue, and what Xcode would have merged into
# the property lists from OBS's build settings
assets=$(find "$src/obs-studio/frontend/cmake/macos" -maxdepth 1 -name Assets.xcassets | head -n 1)
if [ -n "$assets" ]; then
    python3 -I "$sdk/ferry-actool" --compile "$c/Resources" --app-icon AppIcon \
        --output-partial-info-plist "$build/assets.plist" "$assets" > "$build/actool.log" 2>&1 ||
        { cat "$build/actool.log" >&2; die "OBS's asset catalogue didn't compile"; }
    rm -rf "$c/Resources/Assets.xcassets"
fi
python3 -I - "$c" "$obs_version" "$build/assets.plist" <<'EOF'
import glob, os, plistlib, sys
contents, version, assets = sys.argv[1:4]
def merge(path, keys):
    with open(path, 'rb') as f:
        d = plistlib.load(f)
    for k, v in keys.items():
        if not d.get(k) or str(d[k]).startswith('$('):
            d[k] = v
    with open(path, 'wb') as f:
        plistlib.dump(d, f)
keys = {'CFBundleIdentifier': 'com.obsproject.obs-studio', 'CFBundleExecutable': 'OBS',
        'CFBundleName': 'OBS', 'CFBundleDisplayName': 'OBS Studio', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': version, 'CFBundleVersion': version,
        'CFBundleInfoDictionaryVersion': '6.0', 'LSMinimumSystemVersion': '12.0',
        'NSPrincipalClass': 'NSApplication'}
if os.path.exists(assets):
    with open(assets, 'rb') as f:
        keys.update(plistlib.load(f))
merge(contents + '/Info.plist', keys)
for p in glob.glob(contents + '/PlugIns/*.plugin/Contents/Info.plist'):
    n = os.path.basename(os.path.dirname(os.path.dirname(p)))[:-len('.plugin')]
    merge(p, {'CFBundleIdentifier': 'com.obsproject.' + n, 'CFBundleExecutable': n, 'CFBundleName': n,
              'CFBundlePackageType': 'BNDL', 'CFBundleInfoDictionaryVersion': '6.0'})
EOF
say "OBS.app in $app ($(ls -d "$c"/PlugIns/*.plugin | wc -l) OBS modules)"

# and as a .zip, the way Mac apps are handed out: the frameworks' symbolic
# links (Versions/Current and those beside it) are kept as links (zip -y)
if command -v zip > /dev/null; then
    zipped="$(dirname "$app")/OBS-$obs_version.zip"
    rm -f "$zipped"
    (cd "$(dirname "$app")" && zip -qry "$zipped" "$(basename "$app")") || die "OBS.app didn't zip"
    say "and zipped: $zipped"
fi
