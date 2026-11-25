#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Lays out libcurl's headers in the SDK where a Mac's SDK has them,
# usr/include/curl, for programs (OBS) that link a Mac's /usr/lib/libcurl.4.dylib.
# Ferry serves libcurl with this system's copy (see "libraries with Linux
# twins" in src/host.c), whose calls and data layouts are the Mac's on
# 64-bit Intel, so these are this system's own headers, copied. Writes
# nothing, and succeeds, when libcurl's headers (libcurl4-openssl-dev or
# another libcurl -dev) aren't installed.
#
#   gen-curl-headers.sh OUT_DIR        (OUT_DIR/curl.h and the rest)
set -eu
out=$1
src=
for d in /usr/include/x86_64-linux-gnu/curl /usr/include/curl /usr/local/include/curl; do
    if [ -f "$d/curl.h" ]; then src=$d; break; fi
done
mkdir -p "$out"
[ -n "$src" ] || exit 0
cp "$src"/*.h "$out"/
