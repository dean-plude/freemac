#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the link stub for a Mac library that Ferry serves with this system's
# copy of the same open-source library (see "libraries with Linux twins" in
# src/host.c): every call the Linux library exports, under the Mac install
# name. Prints nothing, and succeeds, when the Linux library isn't installed.
#
#   gen-twin-tbd.sh /usr/lib/libz.1.dylib libz.so.1 > libz.tbd
#   gen-twin-tbd.sh /usr/lib/libicucore.A.dylib icu > libicucore.tbd
#
# ICU is the one whose Linux builds add their version to every name
# (uregex_open_74): its stub has the names without it, as a Mac's has.
set -eu
nm=$(command -v llvm-nm 2>/dev/null || ls /usr/lib/llvm-*/bin/llvm-nm 2>/dev/null | head -n 1)
find_so() {
    found=$(/sbin/ldconfig -p 2>/dev/null | awk -v n="$1" '$1 == n && /x86-64/ {print $NF; exit}')
    [ -n "$found" ] || for d in /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /usr/lib; do
        if [ -e "$d/$1" ]; then found=$d/$1; break; fi
    done
    echo "$found"
}
strip=
if [ "$2" = icu ]; then
    so=
    for d in /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /usr/lib; do
        i18n=$(ls "$d"/libicui18n.so.[0-9]* 2>/dev/null | grep -E '\.so\.[0-9]+$' | head -n 1)
        if [ -n "$i18n" ]; then
            so="$i18n ${i18n%/*}/libicuuc.so.${i18n##*.so.}"
            strip="_${i18n##*.so.}"
            break
        fi
    done
else
    so=$(find_so "$2")
fi
if [ -z "$so" ] || [ -z "$nm" ]; then
    exit 0
fi
echo '--- !tapi-tbd'
echo 'tbd-version:     4'
echo 'targets:         [ x86_64-macos ]'
echo "install-name:    '$1'"
echo 'exports:'
echo '  - targets:     [ x86_64-macos ]'
echo '    symbols:     [ '
for f in $so; do "$nm" -D --defined-only "$f"; done | awk '$2 ~ /^[TDBRV]$/ {print $3}' | sed 's/@.*//' |
    { if [ -n "$strip" ]; then grep -E "^[a-z]+[A-Za-z0-9_]*$strip\$" | sed "s/$strip\$//"; else cat; fi; } | sort -u |
    sed "s/.*/                   '_&',/" | sed '$ s/,$/ ]/'
echo '...'
