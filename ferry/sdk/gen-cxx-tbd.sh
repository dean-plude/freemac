#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the link stubs for a Mac's C++ libraries, /usr/lib/libc++.1.dylib
# and /usr/lib/libc++abi.dylib, which Ferry serves with this system's LLVM
# libc++ and libc++abi (src/cxx.c): every name those export, under the Mac
# install names. As on a Mac, libc++ re-exports libc++abi, so a program
# linked with -lc++ records both libraries. Prints nothing, and succeeds,
# when this system's libc++ isn't installed.
#
#   gen-cxx-tbd.sh libc++    > libc++.tbd
#   gen-cxx-tbd.sh libc++abi > libc++abi.tbd
set -eu
nm=$(command -v llvm-nm 2>/dev/null || ls /usr/lib/llvm-*/bin/llvm-nm 2>/dev/null | head -n 1)
find_so() {
    found=$(/sbin/ldconfig -p 2>/dev/null | awk -v n="$1" '$1 == n && /x86-64/ {print $NF; exit}')
    [ -n "$found" ] || for d in /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /usr/lib; do
        if [ -e "$d/$1" ]; then found=$d/$1; break; fi
    done
    echo "$found"
}
cxx=$(find_so libc++.so.1)
abi=$(find_so libc++abi.so.1)
if [ -z "$cxx" ] || [ -z "$abi" ] || [ -z "$nm" ]; then
    exit 0
fi
symbols() {
    echo '    symbols:     [ '
    "$nm" -D --defined-only "$1" | awk '$2 ~ /^[TDBRVW]$/ {print $3}' | sed 's/@.*//' | sort -u |
        sed "s/.*/                   '_&',/" | sed '$ s/,$/ ]/'
}
abi_document() {
    echo '--- !tapi-tbd'
    echo 'tbd-version:     4'
    echo 'targets:         [ x86_64-macos ]'
    echo "install-name:    '/usr/lib/libc++abi.dylib'"
    echo 'current-version: 1.0.0'
    echo 'exports:'
    echo '  - targets:     [ x86_64-macos ]'
    symbols "$abi"
    echo '...'
}
case ${1:-libc++} in
    libc++)
        echo '--- !tapi-tbd'
        echo 'tbd-version:     4'
        echo 'targets:         [ x86_64-macos ]'
        echo "install-name:    '/usr/lib/libc++.1.dylib'"
        echo 'current-version: 1.0.0'
        echo 'reexported-libraries:'
        echo '  - targets:     [ x86_64-macos ]'
        echo "    libraries:   [ '/usr/lib/libc++abi.dylib' ]"
        echo 'exports:'
        echo '  - targets:     [ x86_64-macos ]'
        symbols "$cxx"
        echo '...'
        abi_document
        ;;
    libc++abi) abi_document ;;
    *) echo "gen-cxx-tbd.sh: unknown library $1" >&2; exit 2 ;;
esac
