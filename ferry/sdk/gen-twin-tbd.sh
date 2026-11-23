#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the link stub for a Mac library that Ferry serves with this system's
# copy of the same open-source library (see "libraries with Linux twins" in
# src/host.c): every call the Linux library exports, under the Mac install
# name. Prints nothing, and succeeds, when the Linux library isn't installed.
#
#   gen-twin-tbd.sh /usr/lib/libz.1.dylib libz.so.1 > libz.tbd
set -eu
nm=$(command -v llvm-nm 2>/dev/null || ls /usr/lib/llvm-*/bin/llvm-nm 2>/dev/null | head -n 1)
so=$(/sbin/ldconfig -p 2>/dev/null | awk -v n="$2" '$1 == n && /x86-64/ {print $NF; exit}')
[ -n "$so" ] || for d in /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /usr/lib; do
    if [ -e "$d/$2" ]; then so=$d/$2; break; fi
done
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
"$nm" -D --defined-only "$so" | awk '$2 ~ /^[TDBRV]$/ {print $3}' | sed 's/@.*//' | sort -u |
    sed "s/.*/                   '_&',/" | sed '$ s/,$/ ]/'
echo '...'
