#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds each test as an Intel Mac program with ferry-cc, runs it through
# ./ferry and compares what it prints (plus its exit status) with NAME.out.
set -u
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
build="$here/build"
mkdir -p "$build"
export FERRY_SDK="$top/sdk"
pass=0
fail=0
# For the URL loading tests: the test server on 127.0.0.1, reached directly,
# never through a proxy, and a home of the test's own (for cookies and caches).
url_env() {
    env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
        NO_PROXY=127.0.0.1 no_proxy=127.0.0.1 TMPDIR="$build/home_$name" \
        HOME="$build/home_$name" XDG_CONFIG_HOME= XDG_CACHE_HOME= XDG_DATA_HOME= \
        FERRY_TEST_HTTP="127.0.0.1:$http_port" FERRY_TEST_CLOSED_PORT="$closed_port" \
        FERRY_TEST_HTTPS="${tls_port:+127.0.0.1:$tls_port}" "$@"
}

run_one() {
    name=$1; src=$2; expected=$3; shift 3
    exe="$build/$name"
    if ! "$top/sdk/ferry-cc" -O1 -o "$exe" "$src" "$@" 2> "$build/$name.cc.log"; then
        echo "FAIL $name (did not compile)"; sed 's/^/    /' "$build/$name.cc.log"
        fail=$((fail + 1)); return
    fi
    if [ "$name" = hello_unixthread ]; then
        python3 "$here/tools/unixthread.py" "$exe" "$(llvm-nm "$exe" | awk '/ T _old_start$/ {print $1}')"
    fi
    case $name in
        hello*) FERRY_TEST_VALUE=tide "$top/ferry" "$exe" boat > "$build/$name.got" 2> "$build/$name.err" ;;
        system) "$top/ferry" "$exe" -a -b val file > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_system)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= XDG_DATA_HOME= XDG_CACHE_HOME= \
                "$top/ferry" "$exe" -Mode fast > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_dates|foundation_calendar|foundation_numbers|foundation_iso8601)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= TZ=Europe/Paris TZDIR= LANG=en_US.UTF-8 LC_ALL= LC_MESSAGES= \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_archive*) FERRY_TEST_DATA="$here/foundation" "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_urlcookies|foundation_urlcache)
            # twice in one home: what the first run keeps, the second finds
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            url_env "$top/ferry" "$exe" first > "$build/$name.got" 2> "$build/$name.err" &&
                url_env "$top/ferry" "$exe" second >> "$build/$name.got" 2>> "$build/$name.err" ;;
        foundation_url*)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            url_env "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_panes|appkit_tables|appkit_controls|appkit_binding_controls|appkit_array_controller|appkit_tree_controller|appkit_nib_controllers|appkit_binding_validation)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= FERRY_TEST_DATA="$here/appkit" env -u WAYLAND_DISPLAY -u DISPLAY \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_more_controls)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= TMPDIR="$build/home_$name" FERRY_TEST_DATA="$here/appkit" \
                FERRY_SOUND_PLAYER="$here/appkit/fake_player.sh" FERRY_FAKE_PLAYER_LOG="$build/home_$name/player.log" \
                TZ=Europe/Paris LANG=en_US.UTF-8 env -u WAYLAND_DISPLAY -u DISPLAY -u FERRY_COLOR_ANSWER \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_hidpi)
            XDG_RUNTIME_DIR="$xdg" WAYLAND_DISPLAY=ferry-hidpi DISPLAY= \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_window*)
            XDG_RUNTIME_DIR="$xdg" WAYLAND_DISPLAY=ferry-test DISPLAY= \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_bindings)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            env -u WAYLAND_DISPLAY -u DISPLAY HOME="$build/home_$name" XDG_CONFIG_HOME= TMPDIR="$build/home_$name" \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_autosave)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            env -u WAYLAND_DISPLAY -u DISPLAY -u FERRY_ALERT_ANSWER HOME="$build/home_$name" XDG_CONFIG_HOME= \
                XDG_DATA_HOME= TMPDIR="$build/home_$name" \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_*) env -u WAYLAND_DISPLAY -u DISPLAY "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        security_keychain)
            # twice in one home: what the first run keeps, the second finds
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_DATA_HOME= "$top/ferry" "$exe" first > "$build/$name.got" 2> "$build/$name.err" &&
                HOME="$build/home_$name" XDG_DATA_HOME= "$top/ferry" "$exe" second >> "$build/$name.got" \
                    2>> "$build/$name.err" ;;
        security_code) FERRY_VERBOSE=1 "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_streams)
            # an echo server of its own, and run.sh's TLS server with its certificate
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            url_env env FERRY_TEST_TLS_CERT="$build/tls.der" timeout 60 "$top/ferry" "$exe" > "$build/$name.got" \
                2> "$build/$name.err" ;;
        security_trust)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            url_env env FERRY_TEST_TLS_CERT="$build/tls.der" "$top/ferry" "$exe" > "$build/$name.got" \
                2> "$build/$name.err" ;;
        twins) "$top/ferry" "$exe" < /dev/null > "$build/$name.got" 2>&1 ;;
        atomics) "$top/ferry" "$exe" > "$build/$name.got" 2>&1 ;;
        # threads: a hang is a failure, not a stuck run
        tlv_*|cxx_thread_local) timeout 60 "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        pthreads|dispatch_concurrent|foundation_threads|foundation_locks|cxx_threads|libsystem_sockets|libsystem_kqueue|\
        dispatch_sources|corefoundation_socket|foundation_netservice)
            timeout 60 "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        # Core Data (freemac 1.209, Ferry 0.35.0): stores in a home of the
        # test's own, no display, and threads, so a hang is a failure
        coredata_*)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" TMPDIR="$build/home_$name" XDG_CONFIG_HOME= XDG_DATA_HOME= \
                env -u WAYLAND_DISPLAY -u DISPLAY timeout 60 "$top/ferry" "$exe" > "$build/$name.got" \
                2> "$build/$name.err" ;;
        # WebKit (freemac 1.214, Ferry 0.40.0): two tests with no display
        # (one as if WebKitGTK weren't installed), and the others on the X
        # display of run.sh's own Xvfb; each in a home of its own
        webkit_linked|webkit_missing)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            missing=; [ "$name" = webkit_missing ] && missing="$build/home_$name/none/libwebkit2gtk-4.1.so.0"
            env -u WAYLAND_DISPLAY -u DISPLAY HOME="$build/home_$name" TMPDIR="$build/home_$name" XDG_CONFIG_HOME= \
                XDG_CACHE_HOME= XDG_DATA_HOME= FERRY_WEBKITGTK="$missing" \
                timeout 60 "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        webkit_*)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"; chmod 700 "$build/home_$name"
            env -u WAYLAND_DISPLAY DISPLAY="$webkit_display" GDK_BACKEND=x11 NO_AT_BRIDGE=1 HOME="$build/home_$name" \
                TMPDIR="$build/home_$name" XDG_RUNTIME_DIR="$build/home_$name" XDG_CONFIG_HOME= XDG_CACHE_HOME= \
                XDG_DATA_HOME= timeout 120 "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        *) "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
    esac
    echo "exit=$?" >> "$build/$name.got"
    if diff -u "$expected" "$build/$name.got" > "$build/$name.diff"; then
        echo "ok   $name"; pass=$((pass + 1))
    else
        echo "FAIL $name"; sed 's/^/    /' "$build/$name.diff"; sed 's/^/    stderr: /' "$build/$name.err"
        fail=$((fail + 1))
    fi
}
for t in hello files errors memory signals system; do
    run_one "$t" "$here/$t.c" "$here/$t.out"
done
# A call Ferry doesn't have is left for the loader to find, as a Mac linker
# would with -undefined dynamic_lookup.
run_one unsupported "$here/unsupported.c" "$here/unsupported.out" -Wl,-undefined,dynamic_lookup
# The same programs linked with chained fixups, the newer Mach-O layout.
for t in hello files; do
    run_one "${t}_chained" "$here/$t.c" "$here/$t.out" -Wl,-fixup_chains
done
# The start-up format of Mac OS X 10.7 and earlier (LC_UNIXTHREAD).
run_one hello_unixthread "$here/unixthread.c" "$here/unixthread.out" -Wl,-headerpad,0x400
run_one twins "$here/twins.c" "$here/twins.out" -lz -lbz2 -licucore
run_one atomics "$here/atomics.c" "$here/atomics.out"
# CommonCrypto (libSystem): digests, HMAC, PBKDF2 and random bytes, and AES
# through this system's OpenSSL, against published test vectors.
run_one commoncrypto_digests "$here/commoncrypto_digests.c" "$here/commoncrypto_digests.out"
run_one commoncrypto_cryptor "$here/commoncrypto_cryptor.c" "$here/commoncrypto_cryptor.out"
# Blocks from plain C, and the Objective-C runtime (M1).
run_one blocks "$here/blocks.c" "$here/blocks.out" -fblocks
# Grand Central Dispatch from plain C (M6).
run_one dispatch "$here/dispatch.c" "$here/dispatch.out" -fblocks
# Real threads: POSIX threads and their locks, and dispatch's queues on
# worker threads, with stress cases.
run_one pthreads "$here/pthreads.c" "$here/pthreads.out"
run_one dispatch_concurrent "$here/dispatch_concurrent.c" "$here/dispatch_concurrent.out" -fblocks
# read, write, signal and process sources on real descriptors, signals and a child
run_one dispatch_sources "$here/dispatch_sources.c" "$here/dispatch_sources.out" -fblocks
run_one objc_basic "$here/objc_basic.m" "$here/objc_basic.out" -lobjc
run_one objc_arc "$here/objc_arc.m" "$here/objc_arc.out" -fobjc-arc -lobjc
run_one objc_unknown "$here/objc_unknown.m" "$here/objc_unknown.out" -lobjc
run_one objc_basic_chained "$here/objc_basic.m" "$here/objc_basic.out" -lobjc -Wl,-fixup_chains
run_one objc_arc_chained "$here/objc_arc.m" "$here/objc_arc.out" -fobjc-arc -lobjc -Wl,-fixup_chains
# Unoptimized code sends messages differently (no tail calls, more stack).
run_one objc_basic_O0 "$here/objc_basic.m" "$here/objc_basic.out" -O0 -lobjc
# A program using a Mac library (dylib) of its own, found through @rpath,
# with both relocation formats.
for fmt in classic chained; do
    flags=; [ $fmt = chained ] && flags=-Wl,-fixup_chains
    mkdir -p "$build/lib_$fmt"
    if "$top/sdk/ferry-cc" -O1 -dynamiclib -install_name @rpath/libgreet.dylib $flags \
            -o "$build/lib_$fmt/libgreet.dylib" "$here/dylib/greet.m" -lobjc 2> "$build/greet_$fmt.cc.log"; then
        run_one "dylib_$fmt" "$here/dylib_main.m" "$here/dylib_main.out" -lobjc $flags \
            -L"$build/lib_$fmt" -lgreet -Wl,-rpath,@executable_path/lib_$fmt
    else
        echo "FAIL dylib_$fmt (library did not compile)"; sed 's/^/    /' "$build/greet_$fmt.cc.log"
        fail=$((fail + 1))
    fi
done
# The system's figures (sysctl, kinfo_proc, libproc, the Mach host and task
# calls, getattrlist), checked against uname, sysconf and stat.
run_one libsystem_sysctl "$here/libsystem_sysctl.c" "$here/libsystem_sysctl.out"
# BSD sockets with the Mac's structures, on 127.0.0.1, ::1 and Unix-domain
# sockets; where this system has no IPv6 loopback, the test says so instead.
sockets_out="$here/libsystem_sockets.out"
if ! grep -qs '^00000000000000000000000000000001 ' /proc/net/if_inet6; then
    sed 's/^ipv6 loopback: .*/ipv6 loopback: not available on this system/' "$sockets_out" \
        > "$build/libsystem_sockets.expected"
    sockets_out="$build/libsystem_sockets.expected"
fi
run_one libsystem_sockets "$here/libsystem_sockets.c" "$sockets_out"
# kqueue and kevent: descriptors, timers, signals, processes and user events.
run_one libsystem_kqueue "$here/libsystem_kqueue.c" "$here/libsystem_kqueue.out"
# dlopen, dlsym, dladdr and the _dyld calls: a library found through @rpath
# and a bundle opened RTLD_LOCAL, both built here.
mkdir -p "$build/dlfcn_lib"
if "$top/sdk/ferry-cc" -O1 -dynamiclib -install_name @rpath/libplug.dylib -o "$build/dlfcn_lib/libplug.dylib" \
        "$here/dlfcn/plug.c" 2> "$build/dlfcn_lib.cc.log" &&
    "$top/sdk/ferry-cc" -O1 -bundle -undefined dynamic_lookup -o "$build/dlfcn_lib/extra.bundle" \
        "$here/dlfcn/extra.c" 2>> "$build/dlfcn_lib.cc.log"; then
    run_one libsystem_dlsym "$here/libsystem_dlsym.c" "$here/libsystem_dlsym.out" \
        -Wl,-rpath,@executable_path/dlfcn_lib
else
    echo "FAIL libsystem_dlsym (library or bundle did not compile)"; sed 's/^/    /' "$build/dlfcn_lib.cc.log"
    fail=$((fail + 1))
fi
# @available compiled the normal way, answered for macOS 14.7.
run_one libsystem_available "$here/libsystem_available.m" "$here/libsystem_available.out" -framework Foundation
# Plug-in bundles through NSBundle and CFBundle: one naming its principal
# class, one not, and one whose program is missing.
plugins="$build/plugin_bundles"
rm -rf "$plugins" "$build/plugin_bundles.cc.log"; mkdir -p "$plugins"
plugins_ok=1
for b in Greeter Plain Broken; do
    mkdir -p "$plugins/$b.bundle/Contents/MacOS"
    principal=; [ $b = Greeter ] && principal='<key>NSPrincipalClass</key><string>Greeter</string>'
    exe=$b; [ $b = Broken ] && exe=Missing
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict>' \
        "<key>CFBundleExecutable</key><string>$exe</string>" \
        "<key>CFBundleIdentifier</key><string>org.freemac.ferry.$(echo $b | tr A-Z a-z)</string>" \
        "<key>CFBundleName</key><string>$b</string>" \
        '<key>CFBundlePackageType</key><string>BNDL</string>' $principal '</dict></plist>' \
        > "$plugins/$b.bundle/Contents/Info.plist"
done
for b in Greeter Plain; do
    src="$here/dlfcn/$(echo $b | tr A-Z a-z).m"
    "$top/sdk/ferry-cc" -O1 -bundle -o "$plugins/$b.bundle/Contents/MacOS/$b" "$src" -framework Foundation \
        2>> "$build/plugin_bundles.cc.log" || plugins_ok=0
done
if [ $plugins_ok = 1 ]; then
    run_one libsystem_plugin "$here/libsystem_plugin.m" "$here/libsystem_plugin.out" -framework Foundation \
        -framework CoreFoundation
else
    echo "FAIL libsystem_plugin (a bundle did not compile)"; sed 's/^/    /' "$build/plugin_bundles.cc.log"
    fail=$((fail + 1))
fi
# Foundation (M2), Ferry's own, loaded as a Mac framework.
for t in strings collections system runloop exception; do
    run_one "foundation_$t" "$here/foundation/$t.m" "$here/foundation/$t.out" -framework Foundation
done
# CoreFoundation from plain C, linked under CoreFoundation's own Mac name.
run_one foundation_corefoundation "$here/foundation/corefoundation.c" "$here/foundation/corefoundation.out" \
    -framework CoreFoundation
# Run loop sources and CFSockets on 127.0.0.1, from plain C.
run_one corefoundation_socket "$here/foundation/cfsocket.c" "$here/foundation/cfsocket.out" -framework CoreFoundation
run_one foundation_arc "$here/foundation/arc.m" "$here/foundation/arc.out" -fobjc-arc -framework Foundation
run_one foundation_dispatch "$here/foundation/dispatch.m" "$here/foundation/dispatch.out" -fobjc-arc -framework Foundation
# The macOS version, the same in the Mac's version file, uname, NSProcessInfo
# and Gestalt, through CoreServices and through Carbon.
run_one foundation_sysversion "$here/foundation/sysversion.m" "$here/foundation/sysversion.out" \
    -framework Foundation -framework CoreServices
run_one foundation_sysversion_carbon "$here/foundation/sysversion.m" "$here/foundation/sysversion.out" \
    -framework Foundation -framework Carbon
# Security: keychain items in a home of the test's own, kept between two
# runs, and the code-signing answers (said once with FERRY_VERBOSE).
run_one security_keychain "$here/security/keychain.m" "$here/security/keychain.out" -framework Foundation \
    -framework Security
run_one security_code "$here/security/code.m" "$here/security/code.out" -framework Foundation -framework Security
# NSThread, cross-thread performs and run loops, and the locks and the
# runtime under real threads.
run_one foundation_threads "$here/foundation/threads.m" "$here/foundation/threads.out" -framework Foundation
run_one foundation_locks "$here/foundation/locks.m" "$here/foundation/locks.out" -framework Foundation
# Thread-local variables (__thread, _Thread_local): eight threads at once,
# the thunk's registers, the image's set-up functions, dispatch's workers
# and storage freed (with both relocation formats), in a library the
# program links and in one opened with dlopen, and with NSThread.
run_one tlv_threads "$here/tlv/threads.c" "$here/tlv/threads.out" -fblocks
run_one tlv_threads_chained "$here/tlv/threads.c" "$here/tlv/threads.out" -fblocks -Wl,-fixup_chains
mkdir -p "$build/tlv_lib" "$build/tlv_plug"
if "$top/sdk/ferry-cc" -O1 -dynamiclib -install_name @rpath/libtlvlib.dylib -o "$build/tlv_lib/libtlvlib.dylib" \
        "$here/tlv/lib.c" 2> "$build/tlv_lib.cc.log" &&
    "$top/sdk/ferry-cc" -O1 -dynamiclib -install_name @rpath/libtlvplug.dylib \
        -o "$build/tlv_plug/libtlvplug.dylib" "$here/tlv/plug.c" 2>> "$build/tlv_lib.cc.log"; then
    run_one tlv_dylib "$here/tlv/dylib_main.c" "$here/tlv/dylib_main.out" -L"$build/tlv_lib" -ltlvlib \
        -Wl,-rpath,@executable_path/tlv_lib
    run_one tlv_dlopen "$here/tlv/dlopen_main.c" "$here/tlv/dlopen_main.out" -Wl,-rpath,@executable_path/tlv_plug
else
    echo "FAIL tlv_dylib, tlv_dlopen (a library did not compile)"; sed 's/^/    /' "$build/tlv_lib.cc.log"
    fail=$((fail + 1))
fi
run_one tlv_objc "$here/tlv/objc.m" "$here/tlv/objc.out" -fobjc-arc -framework Foundation
# NSNetService and NSNetServiceBrowser without Bonjour: TXT records, and the failures a program hears.
run_one foundation_netservice "$here/foundation/netservice.m" "$here/foundation/netservice.out" -framework Foundation
# Exceptions a program catches (M7), unwound through frame-pointer and
# frameless functions, and through Foundation's frames.
run_one foundation_trycatch "$here/foundation/trycatch.m" "$here/foundation/trycatch.out" -fobjc-arc \
    -framework Foundation
run_one foundation_trycatch_frameless "$here/foundation/trycatch.m" "$here/foundation/trycatch.out" -O2 \
    -fomit-frame-pointer -fobjc-arc -framework Foundation
run_one foundation_trycatch_mrc "$here/foundation/trycatch.m" "$here/foundation/trycatch.out" -O0 \
    -framework Foundation -Wl,-fixup_chains
# C++ and Objective-C++ programs, linked with -lc++ as on a Mac and run on
# this system's LLVM libc++ (src/cxx.c): the library, exceptions (with a
# Mac library of the program's own throwing its own types), threads, and
# the two languages' exceptions and objects mixed. Building them needs
# libc++'s headers (libc++-dev) and running them its libraries (libc++1,
# libc++abi1); without them the tests are skipped.
if [ -s "$top/sdk/lib/libc++.tbd" ] &&
        echo '#include <vector>' | "$top/sdk/ferry-cc" -x c++ -E -o /dev/null - 2> /dev/null; then
    run_one cxx_basics "$here/cxx/basics.cpp" "$here/cxx/basics.out" -std=c++17 -lc++
    mkdir -p "$build/cxx_lib"
    if "$top/sdk/ferry-cc" -O1 -std=c++17 -dynamiclib -install_name @rpath/libshapes.dylib \
            -o "$build/cxx_lib/libshapes.dylib" "$here/cxx/shapes.cpp" -lc++ 2> "$build/cxx_lib.cc.log"; then
        run_one cxx_exceptions "$here/cxx/exceptions.cpp" "$here/cxx/exceptions.out" -std=c++17 \
            -L"$build/cxx_lib" -lshapes -Wl,-rpath,@executable_path/cxx_lib -lc++
    else
        echo "FAIL cxx_exceptions (library did not compile)"; sed 's/^/    /' "$build/cxx_lib.cc.log"
        fail=$((fail + 1))
    fi
    run_one cxx_threads "$here/cxx/threads.cpp" "$here/cxx/threads.out" -std=c++17 -lc++
    run_one cxx_thread_local "$here/cxx/thread_local.cpp" "$here/cxx/thread_local.out" -std=c++17 -lc++
    run_one objcxx_mixed "$here/cxx/objcxx_mixed.mm" "$here/cxx/objcxx_mixed.out" -std=c++17 -fobjc-arc \
        -framework Foundation -lc++
    # Without this system's libc++, a C++ program stops and says what to install.
    FERRY_LIBCXX=/nonexistent/libc++.so.1 "$top/ferry" "$build/cxx_basics" > /dev/null 2> "$build/cxx_missing.err"
    status=$?
    if [ "$status" = 127 ] && grep -q "needs this system's libc++ and libc++abi (packages libc++1 and libc++abi1)" \
            "$build/cxx_missing.err"; then
        echo "ok   cxx_missing"; pass=$((pass + 1))
    else
        echo "FAIL cxx_missing (exit $status)"; sed 's/^/    stderr: /' "$build/cxx_missing.err"; fail=$((fail + 1))
    fi
    # A program without C++ never loads it.
    if FERRY_VERBOSE=1 "$top/ferry" "$build/objc_basic" 2>&1 > /dev/null | grep -q "libc++"; then
        echo "FAIL cxx_not_loaded (an Objective-C program loaded libc++)"; fail=$((fail + 1))
    else
        echo "ok   cxx_not_loaded"; pass=$((pass + 1))
    fi
else
    echo "skip cxx_basics, cxx_exceptions, cxx_threads, cxx_thread_local, objcxx_mixed (need LLVM's libc++: libc++-dev, libc++1, libc++abi1)"
fi
# Linked against a system framework Ferry doesn't have (only its .tbd exists).
run_one foundation_missing "$here/foundation/missing.m" "$here/foundation/missing.out" -framework Foundation \
    -F"$here/foundation" -framework Imaginary
run_one foundation_collections_chained "$here/foundation/collections.m" "$here/foundation/collections.out" \
    -framework Foundation -Wl,-fixup_chains
run_one foundation_attributed "$here/foundation/attributed.m" "$here/foundation/attributed.out" -framework Foundation
run_one foundation_kvo "$here/foundation/kvo.m" "$here/foundation/kvo.out" -framework Foundation
# Automatic notification through the hidden subclass, dependent keys, key
# paths, to-many changes and key-value coding's search (Ferry 0.17.0).
run_one foundation_kvo_auto "$here/foundation/kvo_auto.m" "$here/foundation/kvo_auto.out" -framework Foundation
# Set mutations, collection operators, removing an observer that isn't
# registered, and predicates (Ferry 0.18.0).
run_one foundation_kvc_collections "$here/foundation/kvc_collections.m" "$here/foundation/kvc_collections.out" \
    -fobjc-arc -fblocks -framework Foundation
# NSInvocation, NSMethodSignature, NSProxy and forwarding, and undo through
# prepareWithInvocationTarget: (Ferry 0.14.0), also unoptimized and with
# chained fixups. The program ends on a message nothing implements.
run_one foundation_invocation "$here/foundation/invocation.m" "$here/foundation/invocation.out" -framework Foundation
run_one foundation_invocation_O0 "$here/foundation/invocation.m" "$here/foundation/invocation.out" -O0 \
    -framework Foundation -Wl,-fixup_chains
# JSON reading and writing, and dates: time zones, locales and date
# formatting (Ferry 0.14.0).
run_one foundation_json "$here/foundation/json.m" "$here/foundation/json.out" -framework Foundation
run_one foundation_dates "$here/foundation/dates.m" "$here/foundation/dates.out" -framework Foundation
# Calendars and date components, number and byte count formatters, ISO 8601
# dates, relative dates and date components formatters (Ferry 0.15.0).
run_one foundation_calendar "$here/foundation/calendar.m" "$here/foundation/calendar.out" -framework Foundation -fblocks
run_one foundation_numbers "$here/foundation/numbers.m" "$here/foundation/numbers.out" -framework Foundation
run_one foundation_iso8601 "$here/foundation/iso8601.m" "$here/foundation/iso8601.out" -framework Foundation
# Tasks and pipes, regular expressions (ICU), scanners, XML (libxml2: events and trees), operations, locks, caches, progress.
for t in task regex scanner xmlparser xmldocument operation cache; do
    run_one "foundation_$t" "$here/foundation/$t.m" "$here/foundation/$t.out" -fblocks -framework Foundation
done
# Keyed archives (M5), the format of nib files.
run_one foundation_archive "$here/foundation/archive.m" "$here/foundation/archive.out" -framework Foundation
# URL loading through this system's libcurl: NSURLSession, NSURLConnection and
# NSData's and NSString's ...ContentsOfURL:, against a small HTTP server
# started here on 127.0.0.1 (nothing goes past the loopback address).
if command -v python3 > /dev/null 2>&1; then
    rm -f "$build/http.port" "$build/tls.crt" "$build/tls.key"
    # with openssl, a certificate of its own for a TLS port too, which this system doesn't trust
    tls_files=
    if command -v openssl > /dev/null 2>&1 &&
        openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 \
            -keyout "$build/tls.key" -out "$build/tls.crt" > "$build/openssl.log" 2>&1; then
        tls_files="$build/tls.crt $build/tls.key"
    fi
    python3 -I "$here/tools/http_server.py" "$build/http.port" $tls_files > "$build/http_server.log" 2>&1 &
    http_pid=$!
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$build/http.port" ] && break; sleep 0.25; done
    tls_port=
    read http_port closed_port tls_port < "$build/http.port"
    run_one foundation_urlsession "$here/foundation/urlsession.m" "$here/foundation/urlsession.out" -fobjc-arc \
        -framework Foundation
    run_one foundation_urlconnection "$here/foundation/urlconnection.m" "$here/foundation/urlconnection.out" \
        -framework Foundation
    # redirects, authentication, cookies and caching decided as a Mac does,
    # data: URLs, and a server's certificate as a challenge
    for t in urlredirects urlauth urlcookies urlcache urldata; do
        run_one "foundation_$t" "$here/foundation/$t.m" "$here/foundation/$t.out" -fobjc-arc -framework Foundation
    done
    if [ -n "$tls_port" ]; then
        run_one foundation_urltrust "$here/foundation/urltrust.m" "$here/foundation/urltrust.out" -fobjc-arc \
            -framework Foundation
        # the same certificate through Security's trust calls, and the challenge's server trust
        openssl x509 -in "$build/tls.crt" -outform DER -out "$build/tls.der"
        run_one security_trust "$here/security/trust.m" "$here/security/trust.out" -framework Foundation \
            -framework Security
        # NSStream and CFStream: memory, files, a bound pair, TCP to an echo server on 127.0.0.1,
        # and TLS to the test server (CFNetwork's names, linked under CFNetwork's own Mac name)
        run_one foundation_streams "$here/foundation/streams.m" "$here/foundation/streams.out" -framework Foundation \
            -framework CFNetwork -framework Security
    else
        echo "skip foundation_urltrust, security_trust and foundation_streams (need openssl, to make the test server a certificate)"
    fi
    kill "$http_pid" 2> /dev/null; wait "$http_pid" 2> /dev/null
else
    echo "skip foundation_urlsession, foundation_urlconnection, foundation_streams and the other URL tests (need python3, for a test server)"
fi
# Core Graphics and Core Text (M3), drawn by this system's Cairo and Pango.
run_one graphics_geometry "$here/graphics/geometry.c" "$here/graphics/geometry.out" \
    -framework CoreGraphics -framework CoreFoundation
run_one graphics_drawing "$here/graphics/drawing.c" "$here/graphics/drawing.out" -framework CoreGraphics
run_one graphics_text "$here/graphics/text.m" "$here/graphics/text.out" \
    -framework CoreText -framework CoreGraphics -framework Foundation
# The same, linked under ApplicationServices' Mac name, which CoreGraphics' file also serves.
run_one graphics_appservices "$here/graphics/geometry.c" "$here/graphics/geometry.out" \
    -framework ApplicationServices -framework CoreFoundation
run_one graphics_drawing_chained "$here/graphics/drawing.c" "$here/graphics/drawing.out" \
    -framework CoreGraphics -Wl,-fixup_chains
# Core Animation: layers drawn with Core Graphics, and animations stepped by
# the test clock.
run_one quartzcore_layers "$here/quartzcore/layers.m" "$here/quartzcore/layers.out" -fobjc-arc \
    -framework QuartzCore -framework Foundation -framework CoreGraphics
run_one quartzcore_animations "$here/quartzcore/animations.m" "$here/quartzcore/animations.out" -fobjc-arc -fblocks \
    -framework QuartzCore -framework Foundation -framework CoreGraphics
# AppKit (M4). First with no display, where windows are drawn off screen,
# linked through Cocoa and through AppKit itself.
run_one appkit_views "$here/appkit/views.m" "$here/appkit/views.out" -fblocks -framework Cocoa
run_one appkit_hidden_redraw "$here/appkit/hidden_redraw.m" "$here/appkit/hidden_redraw.out" -framework Cocoa
run_one appkit_views_appkit "$here/appkit/views.m" "$here/appkit/views.out" -fblocks \
    -framework AppKit -framework Foundation -framework CoreGraphics -framework CoreText
# Then on a real Wayland display: a headless Weston compositor, when installed.
if command -v weston > /dev/null 2>&1; then
    xdg="$build/xdg"
    rm -rf "$xdg"; mkdir -p "$xdg"; chmod 700 "$xdg"
    XDG_RUNTIME_DIR="$xdg" weston --backend=headless --socket=ferry-test > "$build/weston.log" 2>&1 &
    weston_pid=$!
    for i in 1 2 3 4 5 6 7 8 9 10; do [ -S "$xdg/ferry-test" ] && break; sleep 0.5; done
    run_one appkit_window "$here/appkit/window.m" "$here/appkit/window.out" -framework Cocoa
    # The app's icon for the dock (M7): an app bundle with an icon, on the display
    app="$build/IconApp.app"
    rm -rf "$app" "$build/home_icon"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$build/home_icon"
    cp "$here/appkit/NibApp.app/Contents/Resources/dot.png" "$app/Contents/Resources/"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict>' \
        '<key>CFBundleExecutable</key><string>IconApp</string>' \
        '<key>CFBundleIdentifier</key><string>org.freemac.ferry.iconapp</string>' \
        '<key>CFBundleName</key><string>Icon App</string>' \
        '<key>CFBundleIconFile</key><string>dot.png</string>' '</dict></plist>' > "$app/Contents/Info.plist"
    if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/IconApp" "$here/appkit/icon.m" -framework Cocoa \
            2> "$build/appkit_icon.cc.log"; then
        HOME="$build/home_icon" XDG_DATA_HOME= XDG_RUNTIME_DIR="$xdg" WAYLAND_DISPLAY=ferry-test DISPLAY= \
            "$top/ferry" "$app/Contents/MacOS/IconApp" > "$build/appkit_icon.got" 2> "$build/appkit_icon.err"
        echo "exit=$?" >> "$build/appkit_icon.got"
        if diff -u "$here/appkit/icon.out" "$build/appkit_icon.got" > "$build/appkit_icon.diff"; then
            echo "ok   appkit_icon"; pass=$((pass + 1))
        else
            echo "FAIL appkit_icon"; sed 's/^/    /' "$build/appkit_icon.diff"; sed 's/^/    stderr: /' "$build/appkit_icon.err"
            fail=$((fail + 1))
        fi
    else
        echo "FAIL appkit_icon (did not compile)"; sed 's/^/    /' "$build/appkit_icon.cc.log"
        fail=$((fail + 1))
    fi
    kill "$weston_pid" 2> /dev/null; wait "$weston_pid" 2> /dev/null
    # and a screen at scale 2 (M7)
    XDG_RUNTIME_DIR="$xdg" weston --backend=headless --socket=ferry-hidpi --scale=2 > "$build/weston-hidpi.log" 2>&1 &
    weston_pid=$!
    for i in 1 2 3 4 5 6 7 8 9 10; do [ -S "$xdg/ferry-hidpi" ] && break; sleep 0.5; done
    run_one appkit_hidpi "$here/appkit/hidpi.m" "$here/appkit/hidpi.out" -fobjc-arc -framework Cocoa
    kill "$weston_pid" 2> /dev/null; wait "$weston_pid" 2> /dev/null
else
    echo "skip appkit_window, appkit_icon, appkit_hidpi (need weston, for a test display)"
fi
# Cairo is loaded only by programs that draw, and GTK only by AppKit's
# (glibc's LD_DEBUG lists each library loaded).
if LD_DEBUG=libs "$top/ferry" "$build/foundation_strings" 2>&1 >/dev/null | grep -q "libcairo"; then
    echo "FAIL foundation_strings loads Cairo"; fail=$((fail + 1))
elif ! LD_DEBUG=libs "$top/ferry" "$build/graphics_drawing" 2>&1 >/dev/null | grep -q "libcairo"; then
    echo "FAIL graphics_drawing doesn't load Cairo"; fail=$((fail + 1))
elif LD_DEBUG=libs "$top/ferry" "$build/graphics_drawing" 2>&1 >/dev/null | grep -q "libgtk"; then
    echo "FAIL graphics_drawing loads GTK"; fail=$((fail + 1))
else
    echo "ok   Cairo loaded only when drawing, GTK only for AppKit"; pass=$((pass + 1))
fi
# libcurl only by programs that load URLs from the network.
if LD_DEBUG=libs "$top/ferry" "$build/foundation_strings" 2>&1 >/dev/null | grep -q "libcurl"; then
    echo "FAIL foundation_strings loads libcurl"; fail=$((fail + 1))
else
    echo "ok   libcurl loaded only when loading URLs"; pass=$((pass + 1))
fi
# OpenSSL only by programs that encrypt or check certificates: Ferry's own
# digests need none of it.
if LD_DEBUG=libs "$top/ferry" "$build/commoncrypto_digests" 2>&1 >/dev/null | grep -q "libcrypto"; then
    echo "FAIL commoncrypto_digests loads libcrypto"; fail=$((fail + 1))
elif ! LD_DEBUG=libs "$top/ferry" "$build/commoncrypto_cryptor" 2>&1 >/dev/null | grep -q "libcrypto"; then
    echo "FAIL commoncrypto_cryptor doesn't load libcrypto"; fail=$((fail + 1))
else
    echo "ok   libcrypto loaded only when encrypting"; pass=$((pass + 1))
fi
# A program inside a Mac app bundle: Info.plist, resources, localized strings.
app="$build/Hello.app"
rm -rf "$app"; cp -r "$here/foundation/Hello.app" "$app"; mkdir -p "$app/Contents/MacOS"
if "$top/sdk/ferry-cc" -O1 -o "$app/Contents/MacOS/Hello" "$here/foundation/bundle.m" -framework Foundation \
        2> "$build/foundation_bundle.cc.log"; then
    rm -rf "$build/home_bundle"; mkdir -p "$build/home_bundle"
    for lang in C fr_FR.UTF-8; do
        HOME="$build/home_bundle" XDG_CONFIG_HOME= LANG=$lang LC_ALL= LC_MESSAGES= "$top/ferry" "$app/Contents/MacOS/Hello" \
            > "$build/foundation_bundle_$lang.got" 2> "$build/foundation_bundle.err"
        echo "exit=$?" >> "$build/foundation_bundle_$lang.got"
        expected="$here/foundation/bundle.out"; [ $lang = C ] || expected="$here/foundation/bundle_fr.out"
        if diff -u "$expected" "$build/foundation_bundle_$lang.got" > "$build/foundation_bundle.diff"; then
            echo "ok   foundation_bundle ($lang)"; pass=$((pass + 1))
        else
            echo "FAIL foundation_bundle ($lang)"; sed 's/^/    /' "$build/foundation_bundle.diff"
            sed 's/^/    stderr: /' "$build/foundation_bundle.err"; fail=$((fail + 1))
        fi
    done
else
    echo "FAIL foundation_bundle (did not compile)"; sed 's/^/    /' "$build/foundation_bundle.cc.log"
    fail=$((fail + 1))
fi
# An app's check of its own signature, from inside its bundle.
app="$build/SelfCheck.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict>' \
    '<key>CFBundleExecutable</key><string>SelfCheck</string>' \
    '<key>CFBundleIdentifier</key><string>org.freemac.ferry.selfcheck</string>' '</dict></plist>' \
    > "$app/Contents/Info.plist"
if "$top/sdk/ferry-cc" -O1 -o "$app/Contents/MacOS/SelfCheck" "$here/security/selfcheck.m" -framework Foundation \
        -framework Security 2> "$build/security_selfcheck.cc.log"; then
    "$top/ferry" "$app/Contents/MacOS/SelfCheck" > "$build/security_selfcheck.got" 2> "$build/security_selfcheck.err"
    echo "exit=$?" >> "$build/security_selfcheck.got"
    if diff -u "$here/security/selfcheck.out" "$build/security_selfcheck.got" > "$build/security_selfcheck.diff"; then
        echo "ok   security_selfcheck"; pass=$((pass + 1))
    else
        echo "FAIL security_selfcheck"; sed 's/^/    /' "$build/security_selfcheck.diff"
        sed 's/^/    stderr: /' "$build/security_selfcheck.err"; fail=$((fail + 1))
    fi
else
    echo "FAIL security_selfcheck (did not compile)"; sed 's/^/    /' "$build/security_selfcheck.cc.log"
    fail=$((fail + 1))
fi
# Key paths, value transformers and bindings (M6).
run_one appkit_bindings "$here/appkit/bindings.m" "$here/appkit/bindings.out" -fobjc-arc -framework Cocoa
# An exception left uncaught in the event loop is reported, not fatal (M7).
run_one appkit_scrolling "$here/appkit/scrolling.m" "$here/appkit/scrolling.out" -fobjc-arc -framework Cocoa
# Split views and tab views, built in code and from a nib (after M7).
run_one appkit_panes "$here/appkit/panes.m" "$here/appkit/panes.out" -fobjc-arc -framework Cocoa
run_one appkit_tables "$here/appkit/tables.m" "$here/appkit/tables.out" -fobjc-arc -framework Cocoa
# Editing table and outline cells in place (Ferry 0.16.0).
run_one appkit_editing "$here/appkit/editing.m" "$here/appkit/editing.out" -fobjc-arc -framework Cocoa
# Formatters on text fields, cells and edited table cells (Ferry 0.17.0).
run_one appkit_formatters "$here/appkit/formatters.m" "$here/appkit/formatters.out" -fobjc-arc -framework Cocoa
# Bindings that follow and write back: controls, NSObjectController,
# NSUserDefaultsController and bindings loaded from a nib (Ferry 0.17.0).
run_one appkit_binding_controls "$here/appkit/binding_controls.m" "$here/appkit/binding_controls.out" -fobjc-arc \
    -framework Cocoa
# NSArrayController, and a table whose columns are bound to it (Ferry 0.18.0).
run_one appkit_array_controller "$here/appkit/array_controller.m" "$here/appkit/array_controller.out" -fobjc-arc \
    -framework Cocoa
# NSTreeController and NSTreeNode, an outline view bound to one, per-row
# editable and enabled column bindings, and NSDictionaryController (Ferry 0.19.0).
run_one appkit_tree_controller "$here/appkit/tree_controller.m" "$here/appkit/tree_controller.out" -fobjc-arc \
    -framework Cocoa
# Controllers loaded from a nib written with the keyed archiver, and
# bindings in view-based tables' and outlines' cell views (Ferry 0.20.0).
run_one appkit_nib_controllers "$here/appkit/nib_controllers.m" "$here/appkit/nib_controllers.out" -fobjc-arc \
    -framework Cocoa
# Validation through bindings, NSRaisesForNotApplicableKeys, conditionally
# set enabled and editable, and the array controller's content options
# (Ferry 0.20.0).
run_one appkit_binding_validation "$here/appkit/binding_validation.m" "$here/appkit/binding_validation.out" \
    -fobjc-arc -framework Cocoa
# NSDocument autosaving, in a home of its own (Ferry 0.16.0).
run_one appkit_autosave "$here/appkit/autosave.m" "$here/appkit/autosave.out" -fobjc-arc -framework Cocoa
# Pop-up buttons, segmented controls, search fields, stack views and
# toolbars, built in code and from a nib (1.161).
run_one appkit_controls "$here/appkit/controls.m" "$here/appkit/controls.out" -fobjc-arc -framework Cocoa
run_one appkit_more_controls "$here/appkit/more_controls.m" "$here/appkit/more_controls.out" -fobjc-arc \
    -framework Cocoa
run_one appkit_carbon "$here/appkit/carbon.m" "$here/appkit/carbon.out" -fobjc-arc -framework Cocoa -framework Carbon \
    -framework SystemConfiguration
run_one appkit_report "$here/appkit/report.m" "$here/appkit/report.out" -fobjc-arc -framework Cocoa
# Layer-backed and layer-hosting views, NSAnimationContext and animator
# proxies, on Core Animation's test clock.
run_one appkit_layers "$here/appkit/layers.m" "$here/appkit/layers.out" -fobjc-arc -fblocks -framework Cocoa \
    -framework QuartzCore
# Pasteboards, and cut, copy and paste in text fields (M7).
run_one appkit_pasteboard "$here/appkit/pasteboard.m" "$here/appkit/pasteboard.out" -fobjc-arc -framework Cocoa
# Open and Save panels, answered from FERRY_PANEL_ANSWER with no display (M7).
run_one appkit_panels "$here/appkit/panels.m" "$here/appkit/panels.out" -fobjc-arc -framework Cocoa
# Drag and drop into a window: the steps GTK's drop signals take (M7).
run_one appkit_dragging "$here/appkit/dragging.m" "$here/appkit/dragging.out" -fobjc-arc -framework Cocoa
# Menu bar items (after M7): read, opened and clicked over D-Bus as the
# desktop's menu bar does, on a private session bus.
if command -v dbus-run-session > /dev/null && command -v gdbus > /dev/null; then
    if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$build/appkit_statusbar" "$here/appkit/statusbar.m" -framework Cocoa \
            2> "$build/appkit_statusbar.cc.log"; then
        env -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS timeout 60 dbus-run-session -- \
            sh "$here/appkit/statusbar.sh" "$top/ferry" "$build/appkit_statusbar" "$build/appkit_statusbar.log" \
            > "$build/appkit_statusbar.got" 2> "$build/appkit_statusbar.err"
        echo "exit=$?" >> "$build/appkit_statusbar.got"
        if diff -u "$here/appkit/statusbar.out" "$build/appkit_statusbar.got" > "$build/appkit_statusbar.diff"; then
            echo "ok   appkit_statusbar"; pass=$((pass + 1))
        else
            echo "FAIL appkit_statusbar"; sed 's/^/    /' "$build/appkit_statusbar.diff"
            sed 's/^/    stderr: /' "$build/appkit_statusbar.log.err"; fail=$((fail + 1))
        fi
    else
        echo "FAIL appkit_statusbar (did not compile)"; sed 's/^/    /' "$build/appkit_statusbar.cc.log"
        fail=$((fail + 1))
    fi
else
    echo "skip appkit_statusbar (needs dbus-run-session and gdbus)"
fi
# An app started from its main nib (M5), with no display. The nibs come
# from make_nibs.py; what Ferry says about the parts it can't use goes to
# stderr and is checked too.
app="$build/NibApp.app"
rm -rf "$app"; cp -r "$here/appkit/NibApp.app" "$app"; mkdir -p "$app/Contents/MacOS"
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/NibApp" "$here/appkit/nib.m" -framework Cocoa \
        2> "$build/appkit_nib.cc.log"; then
    env -u WAYLAND_DISPLAY -u DISPLAY LANG=C LC_ALL= LC_MESSAGES= "$top/ferry" "$app/Contents/MacOS/NibApp" \
        > "$build/appkit_nib.got" 2> "$build/appkit_nib.err"
    echo "exit=$?" >> "$build/appkit_nib.got"
    if ! diff -u "$here/appkit/nib.out" "$build/appkit_nib.got" > "$build/appkit_nib.diff"; then
        echo "FAIL appkit_nib"; sed 's/^/    /' "$build/appkit_nib.diff"; sed 's/^/    stderr: /' "$build/appkit_nib.err"
        fail=$((fail + 1))
    elif ! grep -q "view class NoSuchView" "$build/appkit_nib.err" || ! grep -q '"noSuchOutlet"' "$build/appkit_nib.err"; then
        echo "FAIL appkit_nib (no warning for the missing class or outlet)"; sed 's/^/    stderr: /' "$build/appkit_nib.err"
        fail=$((fail + 1))
    else
        echo "ok   appkit_nib"; pass=$((pass + 1))
    fi
else
    echo "FAIL appkit_nib (did not compile)"; sed 's/^/    /' "$build/appkit_nib.cc.log"
    fail=$((fail + 1))
fi
# Window and view controllers loading their own nibs (M7), from a copy
# of NibApp.app.
app="$build/ControllerApp.app"
rm -rf "$app"; cp -r "$here/appkit/NibApp.app" "$app"; mkdir -p "$app/Contents/MacOS"
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/NibApp" "$here/appkit/controllers.m" -framework Cocoa \
        2> "$build/appkit_controllers.cc.log"; then
    env -u WAYLAND_DISPLAY -u DISPLAY "$top/ferry" "$app/Contents/MacOS/NibApp" \
        > "$build/appkit_controllers.got" 2> "$build/appkit_controllers.err"
    echo "exit=$?" >> "$build/appkit_controllers.got"
    if diff -u "$here/appkit/controllers.out" "$build/appkit_controllers.got" > "$build/appkit_controllers.diff"; then
        echo "ok   appkit_controllers"; pass=$((pass + 1))
    else
        echo "FAIL appkit_controllers"; sed 's/^/    /' "$build/appkit_controllers.diff"
        sed 's/^/    stderr: /' "$build/appkit_controllers.err"
        fail=$((fail + 1))
    fi
else
    echo "FAIL appkit_controllers (did not compile)"; sed 's/^/    /' "$build/appkit_controllers.cc.log"
    fail=$((fail + 1))
fi
# Documents, alerts and the workspace (1.167): DocApp.app from make_nibs.py,
# with a note named on the command line, an isolated home and a stand-in
# "gio" first on the PATH that writes down what it was asked to open.
app="$build/DocApp.app"
home="$build/home_documents"
rm -rf "$app" "$home"; cp -r "$here/appkit/DocApp.app" "$app"; mkdir -p "$app/Contents/MacOS" "$home/work" "$home/bin"
printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$HOME/gio.log"' > "$home/bin/gio"; chmod +x "$home/bin/gio"
printf 'launched text' > "$home/work/Launch.note"
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/DocApp" "$here/appkit/documents.m" -framework Cocoa \
        2> "$build/appkit_documents.cc.log"; then
    (cd "$home/work" && env -u WAYLAND_DISPLAY -u DISPLAY -u FERRY_ALERT_ANSWER -u FERRY_PANEL_ANSWER HOME="$home" \
        XDG_CONFIG_HOME= XDG_DATA_HOME= TMPDIR="$home" PATH="$home/bin:$PATH" \
        "$top/ferry" "$app/Contents/MacOS/DocApp" Launch.note) > "$build/appkit_documents.got" \
        2> "$build/appkit_documents.err"
    echo "exit=$?" >> "$build/appkit_documents.got"
    if diff -u "$here/appkit/documents.out" "$build/appkit_documents.got" > "$build/appkit_documents.diff"; then
        echo "ok   appkit_documents"; pass=$((pass + 1))
    else
        echo "FAIL appkit_documents"; sed 's/^/    /' "$build/appkit_documents.diff"
        sed 's/^/    stderr: /' "$build/appkit_documents.err"
        fail=$((fail + 1))
    fi
else
    echo "FAIL appkit_documents (did not compile)"; sed 's/^/    /' "$build/appkit_documents.cc.log"
    fail=$((fail + 1))
fi
# Images (M7), in an app bundle the test writes its image files into: it
# runs from there, so imageNamed: finds them. No image files are kept here.
app="$build/ImageApp.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/ImageApp" "$here/appkit/image.m" -framework Cocoa \
        -framework ImageIO 2> "$build/appkit_image.cc.log"; then
    env -u WAYLAND_DISPLAY -u DISPLAY "$top/ferry" "$app/Contents/MacOS/ImageApp" \
        > "$build/appkit_image.got" 2> "$build/appkit_image.err"
    echo "exit=$?" >> "$build/appkit_image.got"
    if diff -u "$here/appkit/image.out" "$build/appkit_image.got" > "$build/appkit_image.diff"; then
        echo "ok   appkit_image"; pass=$((pass + 1))
    else
        echo "FAIL appkit_image"; sed 's/^/    /' "$build/appkit_image.diff"; sed 's/^/    stderr: /' "$build/appkit_image.err"
        fail=$((fail + 1))
    fi
else
    echo "FAIL appkit_image (did not compile)"; sed 's/^/    /' "$build/appkit_image.cc.log"
    fail=$((fail + 1))
fi
# Ferry's Installer: a package made by make_pkg.py (two components, gzip/odc
# and pbzx/newc payloads, a member that climbs out, a link), described and
# installed into test folders; the same package cut short; and a program
# started by its app bundle's folder.
inst="$build/installer"
rm -rf "$inst"; mkdir -p "$inst"
if python3 "$here/tools/make_pkg.py" "$inst/tiny.pkg"; then
    head -c 3000 "$inst/tiny.pkg" > "$inst/cut.pkg"
    (
        cd "$inst"
        "$top/ferry" tiny.pkg --info; echo "exit=$?"
        "$top/ferry" tiny.pkg --install --applications Apps --root root; echo "exit=$?"
        find Apps root | sort
        echo "link: $(readlink Apps/Tiny.app/Contents/Resources)"
        [ -e escaped.txt ] || [ -e ../escaped.txt ] && echo "a member climbed out"
        tail -1 root/usr/local/bin/tiny-tool
        "$top/ferry" cut.pkg --install --applications Apps2 --root root2 2>&1; echo "exit=$?"
    ) > "$build/installer.got" 2> "$build/installer.err"
    mkdir -p "$build/Bundled.app/Contents/MacOS"
    cp "$build/hello" "$build/Bundled.app/Contents/MacOS/Bundled"
    FERRY_TEST_VALUE=tide "$top/ferry" "$build/Bundled.app" boat >> "$build/installer.got" 2>> "$build/installer.err"
    echo "exit=$?" >> "$build/installer.got"
    if diff -u "$here/installer.out" "$build/installer.got" > "$build/installer.diff"; then
        echo "ok   installer"; pass=$((pass + 1))
    else
        echo "FAIL installer"; sed 's/^/    /' "$build/installer.diff"; sed 's/^/    stderr: /' "$build/installer.err"
        fail=$((fail + 1))
    fi
else
    echo "FAIL installer (make_pkg.py failed)"; fail=$((fail + 1))
fi
# An exception nobody catches ends the program with the Mac's message.
if grep -q "Terminating app due to uncaught exception 'NSRangeException'" "$build/foundation_exception.err" 2>/dev/null; then
    echo "ok   foundation_exception message"; pass=$((pass + 1))
else
    echo "FAIL foundation_exception message"; fail=$((fail + 1))
fi
if grep -q "raised NSInternalInconsistencyException (timer 2 went wrong) and didn't catch it" \
        "$build/appkit_report.err" 2>/dev/null; then
    echo "ok   appkit_report message"; pass=$((pass + 1))
else
    echo "FAIL appkit_report message"; sed 's/^/    stderr: /' "$build/appkit_report.err"; fail=$((fail + 1))
fi
# The missing framework, class and function are each named.
if grep -q "uses Imaginary, which Ferry doesn't provide yet; carrying on" "$build/foundation_missing.err" 2>/dev/null &&
        grep -q "the class MyThing is built on a class Ferry doesn't have yet" "$build/foundation_missing.err" &&
        grep -q "uses 1 Objective-C class Ferry" "$build/foundation_missing.err" &&
        grep -q "uses IMDoSomething, which Ferry doesn't support yet" "$build/foundation_missing.err"; then
    echo "ok   foundation_missing messages"; pass=$((pass + 1))
else
    echo "FAIL foundation_missing messages"; sed 's/^/    stderr: /' "$build/foundation_missing.err"; fail=$((fail + 1))
fi
# An unknown selector must be reported as a Mac reports it.
if grep -q "unrecognized selector sent to instance" "$build/objc_unknown.err" 2>/dev/null; then
    echo "ok   objc_unknown message"; pass=$((pass + 1))
else
    echo "FAIL objc_unknown message"; fail=$((fail + 1))
fi
# ... and so must one through Foundation's forwarding.
if grep -q "\-\[NSObject frobnicate\]: unrecognized selector sent to instance" "$build/foundation_invocation.err" 2>/dev/null; then
    echo "ok   foundation_invocation message"; pass=$((pass + 1))
else
    echo "FAIL foundation_invocation message"; sed 's/^/    stderr: /' "$build/foundation_invocation.err"; fail=$((fail + 1))
fi
# The code-signing answers are each said once with FERRY_VERBOSE, however often asked.
if [ "$(grep -c "own code signature passes" "$build/security_code.err" 2>/dev/null)" = 1 ] &&
    [ "$(grep -c "reads as unsigned (errSecCSUnsigned)" "$build/security_code.err" 2>/dev/null)" = 1 ]; then
    echo "ok   security_code message"; pass=$((pass + 1))
else
    echo "FAIL security_code message"; sed 's/^/    stderr: /' "$build/security_code.err"; fail=$((fail + 1))
fi
# The unsupported program must also say what was missing.
if grep -q "pthread_yield_np" "$build/unsupported.err" 2>/dev/null; then
    echo "ok   unsupported message"; pass=$((pass + 1))
else
    echo "FAIL unsupported message"; fail=$((fail + 1))
fi
# Printing, Page Setup and the font panel (freemac 1.206, Ferry 0.33.0):
# print info, views printed to PDF files and read back with Poppler,
# pagination, a text view across pages, PDF data, a document, and the font
# manager, with no display; then GTK's dialogs on a headless Weston.
run_one appkit_print_info "$here/appkit/print_info.m" "$here/appkit/print_info.out" -fobjc-arc -framework Cocoa
run_one appkit_print_view "$here/appkit/print_view.m" "$here/appkit/print_view.out" -fobjc-arc -framework Cocoa
run_one appkit_print_pagination "$here/appkit/print_pagination.m" "$here/appkit/print_pagination.out" -fobjc-arc \
    -fblocks -framework Cocoa
run_one appkit_print_text "$here/appkit/print_text.m" "$here/appkit/print_text.out" -fobjc-arc -framework Cocoa
run_one appkit_print_pdfdata "$here/appkit/print_pdfdata.m" "$here/appkit/print_pdfdata.out" -fobjc-arc \
    -framework Cocoa
run_one appkit_print_document "$here/appkit/print_document.m" "$here/appkit/print_document.out" -fobjc-arc \
    -framework Cocoa
run_one appkit_fonts "$here/appkit/fonts.m" "$here/appkit/fonts.out" -fobjc-arc -framework Cocoa
if command -v weston > /dev/null 2>&1; then
    xdg="$build/xdg"
    rm -rf "$xdg"; mkdir -p "$xdg"; chmod 700 "$xdg"
    XDG_RUNTIME_DIR="$xdg" weston --backend=headless --socket=ferry-test > "$build/weston-print.log" 2>&1 &
    weston_pid=$!
    for i in 1 2 3 4 5 6 7 8 9 10; do [ -S "$xdg/ferry-test" ] && break; sleep 0.5; done
    run_one appkit_window_print "$here/appkit/window_print.m" "$here/appkit/window_print.out" -fobjc-arc -fblocks \
        -framework Cocoa
    kill "$weston_pid" 2> /dev/null; wait "$weston_pid" 2> /dev/null
else
    echo "skip appkit_window_print (needs weston, for a test display)"
fi
# Notifications and the Dock (UNUserNotificationCenter, NSUserNotification,
# NSDockTile), shown through a stand-in freedesktop.org notification server
# and Dock (fake_notify.py, which needs Python's gi bindings) on a private
# session bus with no services of its own.
notify_python=
for p in python3 python3.13 python3.12 python3.11 python3.10; do
    if command -v "$p" > /dev/null &&
            "$p" -c "import gi; gi.require_version('Gio', '2.0'); from gi.repository import Gio" 2> /dev/null; then
        notify_python=$p; break
    fi
done
notify_home="$build/home_notify"; notify_vars=
notify_env() {
    rm -rf "$notify_home"; mkdir -p "$notify_home/share"
    env -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR HOME="$notify_home" \
        XDG_DATA_HOME= XDG_DATA_DIRS="$notify_home/share" XDG_CONFIG_HOME= "$@"
}
notify_build() {
    "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$build/appkit_$1" "$here/appkit/$1.m" -framework Cocoa \
        -framework UserNotifications 2> "$build/appkit_$1.cc.log" && return 0
    echo "FAIL appkit_$1 (did not compile)"; sed 's/^/    /' "$build/appkit_$1.cc.log"
    fail=$((fail + 1)); return 1
}
# notify_test NAME [fake_notify.py options...]: tests/appkit/NAME.m, run against the stand-in.
notify_test() {
    name=$1; shift
    notify_build "$name" || return 1
    notify_env $notify_vars timeout 60 dbus-run-session --config-file="$here/appkit/session-bus.conf" -- \
        sh "$here/appkit/notifications.sh" "$notify_python" "$top/ferry" "$build/appkit_$name" \
        "$build/appkit_$name.log" "$@" > "$build/appkit_$name.got" 2> "$build/appkit_$name.err"
    echo "exit=$?" >> "$build/appkit_$name.got"
    if diff -u "$here/appkit/$name.out" "$build/appkit_$name.got" > "$build/appkit_$name.diff"; then
        echo "ok   appkit_$name"; pass=$((pass + 1))
    else
        echo "FAIL appkit_$name"; sed 's/^/    /' "$build/appkit_$name.diff"
        sed 's/^/    stderr: /' "$build/appkit_$name.log.err"; fail=$((fail + 1)); return 1
    fi
}
if [ -n "$notify_python" ] && command -v dbus-run-session > /dev/null; then
    notify_test notify_un --act "Lunch?=action:ACCEPT" --reply "New message=Yes, at noon" --dismiss Ignored \
        --dismiss Dismissed --act "Tap me=default"
    notify_test notify_ns --act "Build finished=action" --reply "Ping=Pong" --act "Choices=more:share" \
        --act "Not now=other" --act "Click me=default"
    notify_test notify_dock --dock --menu-click "New Window"
    # No notification server on the bus: nothing is shown, and Ferry says so once.
    notify_vars=FERRY_VERBOSE=1
    if notify_test notify_none --no-server; then
        if [ "$(grep -c "no notification server is running" "$build/appkit_notify_none.log.err")" = 1 ]; then
            echo "ok   appkit_notify_none message"; pass=$((pass + 1))
        else
            echo "FAIL appkit_notify_none message"; sed 's/^/    stderr: /' "$build/appkit_notify_none.log.err"
            fail=$((fail + 1))
        fi
    fi
else
    echo "skip appkit_notify_un, appkit_notify_ns, appkit_notify_dock and appkit_notify_none" \
        "(they need dbus-run-session and a Python with the gi bindings)"
fi
# No session bus at all: the same program carries on, and says so once.
if notify_build notify_none; then
    notify_env FERRY_VERBOSE=1 timeout 60 "$top/ferry" "$build/appkit_notify_none" \
        > "$build/appkit_notify_nobus.got" 2> "$build/appkit_notify_nobus.err"
    echo "app exit=$?" >> "$build/appkit_notify_nobus.got"
    sed '1,/^----$/d; /^exit=/d' "$here/appkit/notify_none.out" > "$build/appkit_notify_nobus.want"
    if ! diff -u "$build/appkit_notify_nobus.want" "$build/appkit_notify_nobus.got" > "$build/appkit_notify_nobus.diff"; then
        echo "FAIL appkit_notify_nobus"; sed 's/^/    /' "$build/appkit_notify_nobus.diff"
        sed 's/^/    stderr: /' "$build/appkit_notify_nobus.err"; fail=$((fail + 1))
    elif [ "$(grep -c "there is no session bus, so nothing is shown" "$build/appkit_notify_nobus.err")" != 1 ]; then
        echo "FAIL appkit_notify_nobus (Ferry didn't say once that there is no session bus)"
        sed 's/^/    stderr: /' "$build/appkit_notify_nobus.err"; fail=$((fail + 1))
    else
        echo "ok   appkit_notify_nobus"; pass=$((pass + 1))
    fi
fi
# Core Data (freemac 1.209, Ferry 0.35.0): the model and validation,
# the SQLite, binary and in-memory stores, fetches, undo and rollback,
# parent and child contexts and threads, the fetched results controller,
# batch requests, lightweight migration, models read from their source, and
# NSArrayController in entity mode; a compiled model is said once on stderr.
for t in model stores fetch undo contexts frc batch migration models; do
    run_one "coredata_$t" "$here/coredata/$t.m" "$here/coredata/$t.out" -fobjc-arc -fblocks -framework Foundation \
        -framework CoreData
done
run_one coredata_array_controller "$here/coredata/array_controller.m" "$here/coredata/array_controller.out" \
    -fobjc-arc -fblocks -framework Cocoa -framework CoreData
if [ "$(grep -c "compiled models (.mom and .momd) aren't supported yet" "$build/coredata_models.err" 2>/dev/null)" = 1 ]
then
    echo "ok   coredata_models message"; pass=$((pass + 1))
else
    echo "FAIL coredata_models message"; sed 's/^/    stderr: /' "$build/coredata_models.err"; fail=$((fail + 1))
fi
# gradients, shadows and the split view and tab view controllers
run_one appkit_gradients "$here/appkit/gradients.m" "$here/appkit/gradients.out" -fobjc-arc -fblocks -framework Cocoa
if [ -f "$build/appkit_gradients.err" ] && [ "$(grep -c "shadow" "$build/appkit_gradients.err")" = 0 ]
then
    echo "ok   appkit_gradients message"; pass=$((pass + 1))
else
    echo "FAIL appkit_gradients message"; sed 's/^/    stderr: /' "$build/appkit_gradients.err"; fail=$((fail + 1))
fi
run_one appkit_split_controller "$here/appkit/split_controller.m" "$here/appkit/split_controller.out" -fobjc-arc -fblocks -framework Cocoa
run_one appkit_tab_controller "$here/appkit/tab_controller.m" "$here/appkit/tab_controller.out" -fobjc-arc -fblocks -framework Cocoa
# NSExpression, NSComparisonPredicate, MATCHES and substitution variables;
# NSDecimalNumber and the NSDecimal functions; and in Core Data, decimal
# attributes kept exactly, expression descriptions with aggregates,
# grouping and having predicates, and MATCHES in fetches (freemac 1.211,
# Ferry 0.37.0).
run_one foundation_expressions "$here/foundation/expressions.m" "$here/foundation/expressions.out" \
    -fobjc-arc -fblocks -framework Foundation
run_one foundation_decimals "$here/foundation/decimals.m" "$here/foundation/decimals.out" \
    -fobjc-arc -fblocks -framework Foundation
run_one coredata_aggregates "$here/coredata/aggregates.m" "$here/coredata/aggregates.out" \
    -fobjc-arc -fblocks -framework Foundation -framework CoreData -lsqlite3
# NSCollectionView, with the item-based API, the flow and grid layouts and
# the older content-array API, and loaded from a nib in both forms; and
# NSRulerView and NSRulerMarker on a scroll view (freemac 1.212, Ferry
# 0.38.0).
run_one appkit_collections "$here/appkit/collections.m" "$here/appkit/collections.out" -fobjc-arc -fblocks -framework Cocoa
run_one appkit_collections_legacy "$here/appkit/collections_legacy.m" "$here/appkit/collections_legacy.out" \
    -fobjc-arc -fblocks -framework Cocoa
export FERRY_TEST_DATA="$here/appkit"
run_one appkit_collections_nib "$here/appkit/collections_nib.m" "$here/appkit/collections_nib.out" -fobjc-arc -fblocks -framework Cocoa
unset FERRY_TEST_DATA
run_one appkit_rulers "$here/appkit/rulers.m" "$here/appkit/rulers.out" -fobjc-arc -fblocks -framework Cocoa
# Shadows drawn by Core Graphics (freemac 1.213, Ferry 0.39.0): shapes,
# strokes, images, gradients, text and transparency layers, in bitmaps.
run_one graphics_shadows "$here/graphics/shadows.m" "$here/graphics/shadows.out" -fobjc-arc -framework CoreText \
    -framework CoreGraphics -framework Foundation
# Tracking areas, tracking rectangles, cursor rectangles and cursors
# (freemac 1.213, Ferry 0.39.0), by mouse events sent to a window.
run_one appkit_tracking "$here/appkit/tracking.m" "$here/appkit/tracking.out" -fobjc-arc -fblocks -framework Cocoa
# NSAnimation and NSViewAnimation on the run loop, blocking and not, and the
# animator proxy (freemac 1.213, Ferry 0.39.0).
run_one appkit_animation "$here/appkit/animation.m" "$here/appkit/animation.out" -fobjc-arc -fblocks -framework Cocoa
# Distributed notifications (freemac 1.213, Ferry 0.39.0): within one
# program with no session bus, saying nothing on stderr, and between two
# programs on a private session bus.
distnote_env() { env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR -u WAYLAND_DISPLAY -u DISPLAY "$@"; }
distnote_diff() {
    if diff -u "$2" "$build/$1.got" > "$build/$1.diff"; then
        echo "ok   $1"; pass=$((pass + 1))
    else
        echo "FAIL $1"; sed 's/^/    /' "$build/$1.diff"; sed 's/^/    stderr: /' "$build/$1.err"; fail=$((fail + 1))
    fi
}
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -fblocks -o "$build/foundation_distnote" "$here/foundation/distnote.m" \
    -framework Foundation 2> "$build/foundation_distnote.cc.log"; then
    distnote_env timeout 60 "$top/ferry" "$build/foundation_distnote" alone > "$build/foundation_distnote_alone.got" \
        2> "$build/foundation_distnote_alone.err"
    echo "exit=$?" >> "$build/foundation_distnote_alone.got"
    distnote_diff foundation_distnote_alone "$here/foundation/distnote_alone.out"
    if [ ! -s "$build/foundation_distnote_alone.err" ]; then
        echo "ok   foundation_distnote_alone quiet"; pass=$((pass + 1))
    else
        echo "FAIL foundation_distnote_alone quiet"; sed 's/^/    stderr: /' "$build/foundation_distnote_alone.err"
        fail=$((fail + 1))
    fi
    if command -v dbus-run-session > /dev/null; then
        distnote_env timeout 60 dbus-run-session --config-file="$here/appkit/session-bus.conf" -- \
            "$top/ferry" "$build/foundation_distnote" > "$build/foundation_distnote.got" 2> "$build/foundation_distnote.err"
        echo "exit=$?" >> "$build/foundation_distnote.got"
        distnote_diff foundation_distnote "$here/foundation/distnote.out"
    else
        echo "skip foundation_distnote (it needs dbus-run-session)"
    fi
else
    echo "FAIL foundation_distnote (did not compile)"; sed 's/^/    /' "$build/foundation_distnote.cc.log"
    fail=$((fail + 1))
fi
# NSRunningApplication (freemac 1.213, Ferry 0.39.0): the current
# application, and an .app the test makes and starts, found and ended.
run_one appkit_running "$here/appkit/running.m" "$here/appkit/running.out" -fobjc-arc -fblocks -framework Cocoa
# NSMutableCharacterSet, the further NSCharacterSet methods and percent
# encoding (freemac 1.213, Ferry 0.39.0).
run_one foundation_charset "$here/foundation/charset.m" "$here/foundation/charset.out" -fobjc-arc -fblocks \
    -framework Foundation
# NSTextAttachment (freemac 1.213, Ferry 0.39.0): images drawn inline in
# text, into bitmaps and in a text view.
run_one appkit_attachment "$here/appkit/attachment.m" "$here/appkit/attachment.out" -fobjc-arc -fblocks -framework Cocoa
# NSAppleScript (freemac 1.213, Ferry 0.39.0): it runs nothing and answers
# an error, and says so on stderr once.
run_one foundation_applescript "$here/foundation/applescript.m" "$here/foundation/applescript.out" -fobjc-arc \
    -framework Foundation
if [ -f "$build/foundation_applescript.err" ] && [ "$(grep -c "AppleScript isn't supported" "$build/foundation_applescript.err")" = 1 ]
then
    echo "ok   foundation_applescript message"; pass=$((pass + 1))
else
    echo "FAIL foundation_applescript message"; sed 's/^/    stderr: /' "$build/foundation_applescript.err"; fail=$((fail + 1))
fi
# WebKit: WKWebView and the older WebView, shown by this system's WebKitGTK
# (freemac 1.214, Ferry 0.40.0). First what needs neither WebKitGTK nor a
# display: the classes, web views that stay empty with no display, and the
# same as if WebKitGTK weren't installed, each saying so once. Pages come
# only from strings, data and local files, never the network.
webkit_flags="-fobjc-arc -fblocks -framework Cocoa -framework WebKit"
webkit_message() {   # test, what stderr says once
    if [ "$(grep -c "$2" "$build/$1.err" 2>/dev/null)" = 1 ]; then
        echo "ok   $1 message"; pass=$((pass + 1))
    else
        echo "FAIL $1 message"; sed 's/^/    stderr: /' "$build/$1.err"; fail=$((fail + 1))
    fi
}
run_one webkit_linked "$here/webkit/linked.m" "$here/webkit/linked.out" $webkit_flags
webkit_message webkit_linked "^WebKit (Ferry): web views need "
run_one webkit_missing "$here/webkit/linked.m" "$here/webkit/linked.out" $webkit_flags
webkit_message webkit_missing "^WebKit (Ferry): web views need WebKitGTK (libwebkit2gtk-4.1), which isn't installed"
# WebKitGTK is opened only by programs that make a web view
if LD_DEBUG=libs env -u DISPLAY -u WAYLAND_DISPLAY "$top/ferry" "$build/webkit_linked" classes 2>&1 >/dev/null |
        grep -q "libwebkit2gtk"; then
    echo "FAIL webkit_linked opens WebKitGTK with no web view"; fail=$((fail + 1))
else
    echo "ok   WebKitGTK opened only for web views"; pass=$((pass + 1))
fi
# Then on an X display of the tests' own (Xvfb, headless), when WebKitGTK
# and Xvfb are installed.
webkit_found=
for d in /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/lib /usr/local/lib; do
    [ -e "$d/libwebkit2gtk-4.1.so.0" ] && webkit_found=1
done
if [ -n "$webkit_found" ] && command -v Xvfb > /dev/null 2>&1; then
    rm -f "$build/xvfb.display"
    Xvfb -displayfd 3 -screen 0 1280x1024x24 -nolisten tcp 3> "$build/xvfb.display" > "$build/xvfb.log" 2>&1 &
    xvfb_pid=$!
    for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$build/xvfb.display" ] && break; sleep 0.5; done
    webkit_display=":$(cat "$build/xvfb.display")"
    run_one webkit_wkwebview "$here/webkit/wkwebview.m" "$here/webkit/wkwebview.out" $webkit_flags
    run_one webkit_ui "$here/webkit/ui.m" "$here/webkit/ui.out" $webkit_flags
    run_one webkit_legacy "$here/webkit/legacy.m" "$here/webkit/legacy.out" $webkit_flags
    run_one webkit_embed "$here/webkit/embed.m" "$here/webkit/embed.out" $webkit_flags
    # the older WebView's DOM classes, frame views, subframes, resource load
    # delegate, user style sheet and new windows (freemac 1.217, Ferry 0.42.0)
    run_one webkit_dom "$here/webkit/dom.m" "$here/webkit/dom.out" $webkit_flags
    run_one webkit_frames "$here/webkit/frames.m" "$here/webkit/frames.out" $webkit_flags
    if grep -q "Gtk-CRITICAL\|Gtk-WARNING\|GLib-GObject-CRITICAL" "$build/webkit_embed.err" 2>/dev/null; then
        echo "FAIL webkit_embed warnings from GTK"; sed 's/^/    stderr: /' "$build/webkit_embed.err"; fail=$((fail + 1))
    else
        echo "ok   webkit_embed with no warnings from GTK"; pass=$((pass + 1))
    fi
    kill "$xvfb_pid" 2> /dev/null; wait "$xvfb_pid" 2> /dev/null
else
    echo "skip webkit_wkwebview, webkit_ui, webkit_legacy, webkit_embed, webkit_dom, webkit_frames (need WebKitGTK, libwebkit2gtk-4.1, and Xvfb)"
fi
# Global hotkeys and the Accessibility API (freemac 1.215, Ferry 0.41.0),
# against a stand-in Wayfire with Strata's calls (tests/tools/
# fake_wayfire.py), each in a home and runtime folder of its own
# (appkit/wayfire_test.sh): RegisterEventHotKey's presses reaching Carbon
# event handlers and global monitors, and, once the stand-in user has
# allowed it (appkit/fake_asker.sh, freemac's own freemac-allow-control
# answering Allow), Spectacle's moves and resizes through configure-view.
# appkit_hotkeys_plain is a Wayfire without Strata: kept, never pressed.
wayfire_test() {
    name=$1; exe=$2; expected=$3; shift 3
    sh "$here/appkit/wayfire_test.sh" "$top/ferry" "$exe" "$build/home_$name" "$@" > "$build/$name.got" \
        2> "$build/$name.err"
    echo "exit=$?" >> "$build/$name.got"
    if diff -u "$expected" "$build/$name.got" > "$build/$name.diff"; then
        echo "ok   $name"; pass=$((pass + 1))
    else
        echo "FAIL $name"; sed 's/^/    /' "$build/$name.diff"; sed 's/^/    stderr: /' "$build/$name.err"
        fail=$((fail + 1))
    fi
}
if command -v python3 > /dev/null 2>&1; then
    if "$top/sdk/ferry-cc" -O1 -fobjc-arc -fblocks -o "$build/appkit_hotkeys" "$here/appkit/hotkeys.m" \
            -framework Cocoa -framework Carbon 2> "$build/appkit_hotkeys.cc.log"; then
        wayfire_test appkit_hotkeys "$build/appkit_hotkeys" "$here/appkit/hotkeys.out"
        if [ -s "$build/appkit_hotkeys.err" ]; then
            echo "FAIL appkit_hotkeys quiet"; sed 's/^/    stderr: /' "$build/appkit_hotkeys.err"; fail=$((fail + 1))
        else
            echo "ok   appkit_hotkeys quiet"; pass=$((pass + 1))
        fi
        wayfire_test appkit_hotkeys_plain "$build/appkit_hotkeys" "$here/appkit/hotkeys_plain.out" --no-strata -- plain
    else
        echo "FAIL appkit_hotkeys (did not compile)"; sed 's/^/    /' "$build/appkit_hotkeys.cc.log"
        fail=$((fail + 1))
    fi
    if "$top/sdk/ferry-cc" -O1 -fobjc-arc -fblocks -o "$build/appkit_accessibility" "$here/appkit/accessibility.m" \
            -framework Cocoa -framework Carbon -framework ApplicationServices 2> "$build/appkit_accessibility.cc.log"
    then
        wayfire_test appkit_accessibility "$build/appkit_accessibility" "$here/appkit/accessibility.out"
    else
        echo "FAIL appkit_accessibility (did not compile)"; sed 's/^/    /' "$build/appkit_accessibility.cc.log"
        fail=$((fail + 1))
    fi
else
    echo "skip appkit_hotkeys, appkit_hotkeys_plain, appkit_accessibility (they need python3)"
fi
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
