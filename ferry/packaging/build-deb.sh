#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds freemac-ferry_VERSION_amd64.deb, an optional add-on that is not part
# of the freemac ISO. Install it with: sudo apt install ./freemac-ferry_*.deb
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
out=${OUTDIR:-$top/packaging/out}
make -C "$top" -s
version=$("$top/ferry" --version | awk '{print $2}')
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
make -C "$top" -s install DESTDIR="$root" PREFIX=/usr
install -Dm644 "$top/README.md" "$root/usr/share/doc/freemac-ferry/README.md"
install -d "$root/DEBIAN"
size=$(du -sk "$root/usr" | cut -f1)
cat > "$root/DEBIAN/control" <<CONTROL
Package: freemac-ferry
Version: $version
Architecture: amd64
Maintainer: freemac project <noreply@freemac.invalid>
Installed-Size: $size
Depends: libc6
Recommends: systemd
Suggests: clang, lld
Section: otherosfs
Priority: optional
Description: Ferry, runs simple Intel Mac command-line programs
 Ferry loads 64-bit Intel Mach-O programs and connects them to this system's
 C library through its own small libSystem layer and Objective-C runtime,
 written from public documentation. It runs command-line programs that use
 the C and POSIX basics, blocks and the Objective-C runtime. Graphical Mac
 apps and App Store apps do not run yet.
CONTROL
cat > "$root/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if [ "$1" = configure ] && [ -d /run/systemd/system ]; then
    systemctl restart systemd-binfmt.service >/dev/null 2>&1 || true
fi
POSTINST
cat > "$root/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
if [ -e /proc/sys/fs/binfmt_misc/ferry ]; then
    echo -1 > /proc/sys/fs/binfmt_misc/ferry 2>/dev/null || true
fi
POSTRM
chmod 755 "$root/DEBIAN/postinst" "$root/DEBIAN/postrm"
mkdir -p "$out"
dpkg-deb --root-owner-group --build "$root" "$out/freemac-ferry_${version}_amd64.deb"
