# SPDX-License-Identifier: GPL-3.0-or-later
#
# What the app recipes in this folder share (freemac 1.231, Ferry 0.55.0).
# A recipe is a shell script, sourced from here, that fetches an
# open-source Mac app and the packages it uses from their public git
# repositories at pinned commits, builds them with Ferry's SDK
# (sdk/ferry-cc, sdk/ferry-swiftc, sdk/ferry-actool, sdk/ferry-ibtool) and
# lays the app out as a bundle that ./ferry runs:
#
#   apps/tomatobar.sh [WORK]    TomatoBar, a SwiftUI menu bar timer
#   apps/ffmpeg.sh [WORK]       FFmpeg's libraries and tools, for VLC and OBS
#
# and the others listed in README.md. The Objective-C apps are built from
# their Xcode projects by apps/xcode.py (freemac 1.236, Ferry 0.60.0),
# through xcbuild below.
#
# WORK (or FERRY_APPS_WORK; apps/work by default, which git ignores) holds
# the checkouts in src/ and what is built in build/APP/, with the bundle
# at build/APP/APP.app. Nothing fetched is kept in freemac's repository:
# the apps' code stays theirs, under their own licences. A checkout already
# at its commit isn't fetched again, so a second run builds offline.
#
# Swift apps need a swift.org toolchain (FERRY_SWIFT_TOOLCHAIN, or
# swift-frontend on PATH) and Ferry's build of Swift's runtime
# (swift/build-runtime.sh); the recipe brings Ferry's own Swift modules up
# to date first (swift/build-modules.sh).
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
sdk=$top/sdk
work=${1:-${FERRY_APPS_WORK:-$top/apps/work}}
mkdir -p "$work/src" "$work/build"
work=$(cd "$work" && pwd)
src=$work/src

say() { echo "${recipe_name:-recipe}: $*"; }
die() { echo "${recipe_name:-recipe}: $*" >&2; exit 1; }

# fetch NAME URL COMMIT: a checkout of URL at COMMIT in $src/NAME. Only that
# commit is fetched (GitHub serves any commit by its hash).
fetch() {
    fetch_into "$src/$1" "$2" "$3"
}

# fetch_into DIR URL COMMIT: the same, into DIR.
fetch_into() {
    name=$(basename "$1") url=$2 commit=$3 dir=$1
    if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ] &&
       [ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
        return 0
    fi
    say "fetching $name ($url at $commit)"
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
    [ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ] || die "$name: $url gave another commit"
}

# fetch_release NAME URL SHA256: a project's release tarball (as its own site
# publishes it), checked against SHA256 and unpacked into $src/NAME, for
# projects such as FFmpeg that are built from their releases (freemac
# 1.233, Ferry 0.57.0). A copy of the tarball already in $src, under its
# own file name, is used without fetching.
fetch_release() {
    name=$1 url=$2 sum=$3 file=$src/$(basename "$2")
    if [ -f "$src/$name/.release-$sum" ]; then
        return 0
    fi
    if [ ! -f "$file" ] || ! echo "$sum  $file" | sha256sum -c - > /dev/null 2>&1; then
        say "fetching $name ($url)"
        curl -fL --proto '=https' -o "$file.part" "$url" || die "$name: $url couldn't be fetched"
        mv "$file.part" "$file"
    fi
    echo "$sum  $file" | sha256sum -c - > /dev/null 2>&1 || die "$name: $file isn't the release pinned (SHA-256)"
    rm -rf "$src/$name" "$src/$name.unpack"
    mkdir -p "$src/$name.unpack"
    tar -C "$src/$name.unpack" -xf "$file"
    # the tarball's one top folder becomes $src/NAME
    set -- "$src/$name.unpack"/*
    [ $# -eq 1 ] && [ -d "$1" ] || die "$name: $file doesn't hold one folder"
    mv "$1" "$src/$name"
    rmdir "$src/$name.unpack"
    touch "$src/$name/.release-$sum"
}

# submodule SUPER PATH URL: the submodule at PATH of the checkout
# $src/SUPER, fetched from URL at the commit that SUPER's own commit pins
# for it, so it is pinned by SUPER's hash.
submodule() {
    sm_commit=$(git -C "$src/$1" ls-tree HEAD "$2" | awk '$2 == "commit" { print $3 }')
    [ -n "$sm_commit" ] || die "$1 has no submodule at $2"
    fetch_into "$src/$1/$2" "$3" "$sm_commit"
}

# xcbuild PROJECT.xcodeproj TARGET [xcode.py options]: one target of an
# Xcode project built into $build by apps/xcode.py, with Ferry's SDK; a
# framework lands at $build/NAME.framework, where the targets after it
# find it, an app at $build/NAME.app.
xcbuild() {
    xc_proj=$1 xc_target=$2
    shift 2
    say "building $xc_target"
    python3 -I "$top/apps/xcode.py" build "$xc_proj" "$xc_target" "$build" --jobs "${FERRY_APPS_JOBS:-2}" "$@" ||
        die "$xc_target didn't build"
}

# embed APP FRAMEWORK...: frameworks built in $build copied into the app's
# Contents/Frameworks, as Xcode's Embed Frameworks phase does.
embed() {
    em_app=$1
    shift
    mkdir -p "$em_app/Contents/Frameworks"
    for em_fw in "$@"; do
        rm -rf "$em_app/Contents/Frameworks/$(basename "$em_fw")"
        cp -R "$em_fw" "$em_app/Contents/Frameworks/"
    done
}

# sparkle1 COMMIT VERSION: Sparkle 1.x, the updater most of the apps bring
# (github.com/sparkle-project/Sparkle, MIT), built as $build/Sparkle.framework
# with its ed25519 code (its submodule) compiled in. Its binary-delta
# code needs xar, which this system lacks, so apps/sparkle-nodelta.m stands
# in for it and a delta update falls back to the full one, as Sparkle
# does whenever a delta can't be applied.
sparkle1() {
    fetch "Sparkle-$2" https://github.com/sparkle-project/Sparkle "$1"
    submodule "Sparkle-$2" Vendor/ed25519 https://github.com/orlp/ed25519
    sp=$src/Sparkle-$2
    sp_add=
    for sp_c in "$sp"/Vendor/ed25519/src/*.c; do sp_add="$sp_add --add $sp_c"; done
    # shellcheck disable=SC2086
    xcbuild "$sp/Sparkle.xcodeproj" Sparkle \
        --cflags "-fobjc-arc -I $sp/Vendor/ed25519/src -DBUILDING_SPARKLE=1 -DMARKETING_VERSION=\\\"$2\\\"
                  -DSPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME=0 -DSPARKLE_AUTOMATED_DOWNGRADES=0
                  -DSPARKLE_APPEND_VERSION_NUMBER=1 -DSPARKLE_BUNDLE_IDENTIFIER=\\\"org.sparkle-project.Sparkle\\\"
                  -DSPARKLE_RELAUNCH_TOOL_NAME=\\\"Autoupdate\\\" -DSPARKLE_FILEOP_TOOL_NAME=\\\"fileop\\\"" \
        --skip SUBinaryDeltaApply.m --skip SUBinaryDeltaCommon.m --add "$top/apps/sparkle-nodelta.m" $sp_add \
        --info "CFBundleShortVersionString=$2" \
        --ldflags '-framework Cocoa -framework Security -framework SystemConfiguration -framework WebKit
                   -framework IOKit -lz -lbz2'
}

# sparkle2 DIR: Sparkle 2's framework from its checkout in DIR, built as
# $build/Sparkle.framework with its ed25519 library compiled in. Its
# helper services (XPC services, Autoupdate) aren't built: Ferry's
# NSXPCConnection never connects, so Sparkle reports each call to them
# failed, as on a Mac without them.
sparkle2() {
    xcbuild "$1/Sparkle.xcodeproj" Sparkle --with ed25519 \
        --ldflags '-framework Cocoa -framework Security -framework SystemConfiguration -framework WebKit
                   -framework IOKit -lz -lbz2'
}

# need_swift: the toolchain and Ferry's Swift runtime, and Ferry's Swift
# modules up to date.
need_swift() {
    if [ -z "${FERRY_SWIFT_TOOLCHAIN:-}" ] && command -v swift-frontend > /dev/null 2>&1; then
        FERRY_SWIFT_TOOLCHAIN=$(dirname "$(dirname "$(command -v swift-frontend)")")
    fi
    [ -n "${FERRY_SWIFT_TOOLCHAIN:-}" ] && [ -x "$FERRY_SWIFT_TOOLCHAIN/usr/bin/swift-frontend" ] ||
        die "needs a Swift toolchain (FERRY_SWIFT_TOOLCHAIN, or swift-frontend on PATH)"
    export FERRY_SWIFT_TOOLCHAIN
    [ -f "$top/frameworks/swift/libswiftCore.dylib" ] ||
        die "needs Swift's runtime built for Ferry (swift/build-runtime.sh)"
    sh "$top/swift/build-modules.sh" > "$build/swift-modules.log" 2>&1 ||
        { sed 's/^/    /' "$build/swift-modules.log" >&2; die "Ferry's Swift modules didn't build"; }
}

# swift_lib NAME [ferry-swiftc options] SOURCES...: a Swift package's target
# built as $build/libNAME.dylib (@rpath/libNAME.dylib), with its module in
# $build/mods for the targets that import it, as SwiftPM builds a dynamic
# library product.
swift_lib() {
    name=$1
    shift
    mkdir -p "$build/mods"
    say "building $name"
    if ! (cd "$build" && "$sdk/ferry-swiftc" -emit-library -module-name "$name" -I "$build/mods" -L "$build" \
              -Xfrontend -emit-module-path -Xfrontend "$build/mods/$name.swiftmodule" "$@" \
              -o "$build/lib$name.dylib") > "$build/$name.log" 2>&1; then
        grep -E 'error:' "$build/$name.log" | head -20 >&2
        die "$name didn't build (its log: $build/$name.log)"
    fi
}

# resource_bundle NAME SOURCE-SWIFT: the accessor SwiftPM generates for a
# package target with resources, Bundle.module, finding NAME.bundle beside
# the app's resources, as Xcode lays it out. Written to SOURCE-SWIFT.
resource_bundle() {
    cat > "$2" <<EOF
// Generated by ferry/apps/recipe.sh, as SwiftPM generates it for a target
// with resources: Bundle.module, the target's resource bundle.
import Foundation

private final class _ResourceBundleFinder {}

extension Foundation.Bundle {
    static let module: Bundle = {
        let name = "$1.bundle"
        let candidates = [Bundle.main.resourceURL, Bundle(for: _ResourceBundleFinder.self).resourceURL,
                          Bundle.main.bundleURL]
        for candidate in candidates {
            if let url = candidate?.appendingPathComponent(name), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle.main
    }()
}
EOF
}
