#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Build Strata's Wayfire plugins. Run inside the image (the ISO build does
# this in its chroot) with g++, pkg-config, wayfire-dev, wayland-protocols,
# libwayland-bin and nlohmann-json3-dev installed.
# Usage: build.sh OUTDIR   -> OUTDIR/libstrata-decor.so, OUTDIR/libstrata-shell.so
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build.sh OUTDIR}
mkdir -p "$OUT"
INC="$(pkg-config --variable=includedir wayfire)/wayfire"
# The plugins follow Wayfire's plugin API as of ABI 2023-11-23 (the Wayfire
# that Ubuntu 24.04 ships). Other versions changed that API.
if ! grep -q "WAYFIRE_API_ABI_VERSION = 2023'11'23" "$INC/plugin.hpp"; then
  echo "strata: this Wayfire ($(pkg-config --modversion wayfire)) uses another plugin API; skipping the plugins" >&2
  exit 2
fi
FLAGS="-std=c++17 -O2 -fPIC -shared -DWLR_USE_UNSTABLE -DWAYFIRE_PLUGIN -I$INC"
CFLAGS=$(pkg-config --cflags wayfire wlroots cairo pangocairo pixman-1 wf-config)
# shellcheck disable=SC2046,SC2086
g++ $FLAGS $CFLAGS \
  "$HERE"/decor/*.cpp -o "$OUT/libstrata-decor.so" $(pkg-config --libs cairo pangocairo)
echo "strata: built $OUT/libstrata-decor.so"

# strata-shell speaks the gtk_shell1 Wayland protocol; generate its code.
GEN="$OUT/gen"
mkdir -p "$GEN"
wayland-scanner server-header "$HERE/shell/gtk-shell.xml" "$GEN/gtk-shell-protocol.h"
wayland-scanner private-code "$HERE/shell/gtk-shell.xml" "$GEN/gtk-shell-protocol.c"
# wlroots' xdg-shell header (used to follow window configures) needs this one.
WLPROTO=$(pkg-config --variable=pkgdatadir wayland-protocols)
wayland-scanner server-header "$WLPROTO/stable/xdg-shell/xdg-shell.xml" "$GEN/xdg-shell-protocol.h"
gcc -O2 -fPIC -c "$GEN/gtk-shell-protocol.c" -o "$GEN/gtk-shell-protocol.o" $(pkg-config --cflags wayland-server)
# shellcheck disable=SC2086
g++ $FLAGS $CFLAGS -I"$GEN" "$HERE/shell/strata-shell.cpp" "$GEN/gtk-shell-protocol.o" \
  -o "$OUT/libstrata-shell.so"
echo "strata: built $OUT/libstrata-shell.so"
