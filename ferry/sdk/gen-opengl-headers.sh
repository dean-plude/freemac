#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Lays out OpenGL's own headers in the SDK, for <OpenGL/gl.h> and
# <OpenGL/gl3.h> (freemac 1.235, Ferry 0.59.0). Ferry's OpenGL framework
# passes every OpenGL call to this system's OpenGL, whose calls and types
# are the same on 64-bit Intel Macs (the Khronos registry's headers have a
# branch for Macs, which ferry-cc's target takes), so these are this
# system's own headers, copied: gl.h, glext.h, glcorearb.h and
# khrplatform.h, with their includes of each other made relative.
# Leaves the directories empty, and succeeds, when they (libgl-dev) aren't
# installed; programs that include <OpenGL/gl.h> then can't be built.
#
#   gen-opengl-headers.sh OUT_DIR        (OUT_DIR/GL/gl.h, OUT_DIR/KHR/khrplatform.h)
set -eu
out=$1
src=
for d in /usr/include /usr/local/include; do
    if [ -f "$d/GL/gl.h" ] && [ -f "$d/GL/glext.h" ] && [ -f "$d/GL/glcorearb.h" ] && [ -f "$d/KHR/khrplatform.h" ]; then
        src=$d; break
    fi
done
rm -rf "$out/GL" "$out/KHR"
mkdir -p "$out/GL" "$out/KHR"
[ -n "$src" ] || exit 0
for h in gl.h glext.h glcorearb.h; do
    sed -e 's|^#include <GL/glext.h>|#include "glext.h"|' \
        -e 's|^#include <KHR/khrplatform.h>|#include "../KHR/khrplatform.h"|' \
        "$src/GL/$h" > "$out/GL/$h"
done
cp "$src/KHR/khrplatform.h" "$out/KHR/khrplatform.h"
