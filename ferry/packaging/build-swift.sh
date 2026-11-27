#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   packaging/build-swift.sh [WORKDIR]
#
# Builds Swift's runtime and standard library (swift/build-runtime.sh) and
# Ferry's Swift modules (swift/build-modules.sh) into frameworks/swift, so
# that build-deb.sh puts them in the package and Swift apps from a Mac
# (Rectangle, TomatoBar, SwiftUI apps) run on a freemac computer, which has
# no Swift of its own (freemac 1.261). It fetches what it needs into WORKDIR:
# a swift.org toolchain for Ubuntu 24.04 and the open-source Swift project's
# source at the same release, unless SWIFT_TOOLCHAIN (the folder holding
# usr/bin) and SWIFT_SOURCE (a checkout of github.com/swiftlang/swift) name
# copies already here. Neither is Ferry's code; nothing of them but the
# built libraries goes in the package.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
v=6.1.3
work=${1:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ferry-swift}
mkdir -p "$work"
work=$(cd "$work" && pwd)

tc=${SWIFT_TOOLCHAIN:-}
if [ -z "$tc" ]; then
    name=swift-$v-RELEASE-ubuntu24.04
    tc=$work/$name
    if [ ! -x "$tc/usr/bin/swift-frontend" ]; then
        echo "build-swift: fetching the Swift $v toolchain"
        curl -fsSL --retry 3 -o "$work/toolchain.tar.gz" \
            "https://download.swift.org/swift-$v-release/ubuntu2404/swift-$v-RELEASE/$name.tar.gz"
        tar -xzf "$work/toolchain.tar.gz" -C "$work"
        rm -f "$work/toolchain.tar.gz"
    fi
fi
src=${SWIFT_SOURCE:-}
if [ -z "$src" ]; then
    src=$work/swift-swift-$v-RELEASE
    if [ ! -d "$src/stdlib/public/runtime" ]; then
        echo "build-swift: fetching Swift $v's source"
        curl -fsSL --retry 3 -o "$work/source.tar.gz" \
            "https://github.com/swiftlang/swift/archive/refs/tags/swift-$v-RELEASE.tar.gz"
        # the tests and the docs aren't needed
        tar -xzf "$work/source.tar.gz" -C "$work" --exclude="swift-swift-$v-RELEASE/test" \
            --exclude="swift-swift-$v-RELEASE/validation-test" --exclude="swift-swift-$v-RELEASE/docs"
        rm -f "$work/source.tar.gz"
    fi
fi

make -C "$top" -s -j"$(nproc 2>/dev/null || echo 4)"
FERRY_SWIFT_TOOLCHAIN=$tc sh "$top/swift/build-runtime.sh" "$src" "$tc"
FERRY_SWIFT_TOOLCHAIN=$tc sh "$top/swift/build-modules.sh"
ls -la "$top"/frameworks/swift/*.dylib
