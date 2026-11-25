#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Lays out libxml2's headers in the SDK where a Mac's SDK has them,
# usr/include/libxml2/libxml, so that a project's
# HEADER_SEARCH_PATHS = $(SDKROOT)/usr/include/libxml2 finds them with
# SDKROOT set to Ferry's SDK. Ferry serves libxml2 with this system's copy
# (see "libraries with Linux twins" in src/host.c), whose calls and data
# layouts are the Mac's on 64-bit Intel, so these are this system's own
# headers, copied. Two includes that name this system's other libraries are
# replaced by the one type each header needs from them: iconv's iconv_t and
# ICU's UConverter and UChar, so that the encoding handler keeps its layout. Writes
# nothing, and succeeds, when libxml2's headers (libxml2-dev) aren't
# installed.
#
#   gen-libxml2-headers.sh OUT_DIR        (OUT_DIR/libxml/tree.h and the rest)
set -eu
out=$1
src=
for d in /usr/include/libxml2 /usr/local/include/libxml2; do
    if [ -f "$d/libxml/tree.h" ]; then src=$d; break; fi
done
rm -rf "$out"
mkdir -p "$out"
[ -n "$src" ] || exit 0
mkdir -p "$out/libxml"
for h in "$src"/libxml/*.h; do
    sed -e 's|^#include <iconv.h>|typedef void *iconv_t; /* iconv.h */|' \
        -e 's|^#include <unicode/ucnv.h>|typedef struct UConverter UConverter; typedef unsigned short UChar; /* unicode/ucnv.h */|' \
        -e 's|^#include <winsock2.h>||' \
        "$h" > "$out/libxml/${h##*/}"
done
