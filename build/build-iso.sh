#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build a bootable freemac live ISO (BIOS + UEFI) for x86-64.
#
#   sudo ./build/build-iso.sh
#
# Settings (environment variables):
#   BASE      debian (default) or ubuntu (fallback base for hosts that can only
#             reach Ubuntu mirrors)
#   SUITE     release to build from (default: trixie for debian, noble for ubuntu)
#   MIRROR    archive URL (default: the base's main mirror)
#   SNAPSHOT  snapshot.debian.org timestamp such as 20261101T000000Z; pins every
#             package to that moment for a reproducible build (debian only)
#   VERSION   image version string (default: contents of VERSION file)
#   WORKDIR   scratch directory (default: ./work)
#   OUTDIR    output directory (default: ./out)
#   SOURCE_DATE_EPOCH  timestamp used for every file in the image (default: last
#             git commit time, or the VERSION file's mtime)

set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
BASE=${BASE:-debian}
VERSION=${VERSION:-$(cat "$REPO/VERSION")}
WORKDIR=${WORKDIR:-$REPO/work}
OUTDIR=${OUTDIR:-$REPO/out}
ARCH=amd64

case "$BASE" in
  debian)
    SUITE=${SUITE:-trixie}
    if [ -n "${SNAPSHOT:-}" ]; then
      MIRROR=${MIRROR:-http://snapshot.debian.org/archive/debian/$SNAPSHOT}
    else
      MIRROR=${MIRROR:-http://deb.debian.org/debian}
    fi
    COMPONENTS=main,contrib,non-free-firmware
    KERNEL=linux-image-amd64
    ID_LIKE=debian
    ;;
  ubuntu)
    SUITE=${SUITE:-noble}
    MIRROR=${MIRROR:-http://archive.ubuntu.com/ubuntu}
    COMPONENTS=main,universe
    KERNEL=linux-image-generic
    ID_LIKE="ubuntu debian"
    ;;
  *)
    echo "BASE must be debian or ubuntu" >&2
    exit 1
    ;;
esac

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git -C "$REPO" log -1 --format=%ct 2>/dev/null || stat -c %Y "$REPO/VERSION")
fi
export SOURCE_DATE_EPOCH

ROOTFS=$WORKDIR/rootfs
ISOTREE=$WORKDIR/iso
ISO=$OUTDIR/freemac-$VERSION-$ARCH.iso

log() { printf '\n==> %s\n' "$*"; }

need() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "Missing tool: $tool (see README.md for the packages to install)" >&2
      exit 1
    }
  done
}

[ "$(id -u)" -eq 0 ] || { echo "Run as root (the build uses chroot)." >&2; exit 1; }
need debootstrap mksquashfs xorriso grub-mkrescue mformat

# Package list: shared packages plus the base's own extras.
PACKAGES=$(grep -hv '^\s*#' "$REPO/build/packages/common.list" "$REPO/build/packages/$BASE.list" | tr -s ' \n' ' ')

umount_chroot() {
  for m in dev/pts dev proc sys run; do
    if mountpoint -q "$ROOTFS/$m" 2>/dev/null; then umount -l "$ROOTFS/$m"; fi
  done
}
trap umount_chroot EXIT INT TERM

log "freemac $VERSION: $BASE $SUITE from $MIRROR (SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH)"
umount_chroot
rm -rf "$WORKDIR"
mkdir -p "$ROOTFS" "$ISOTREE/live" "$OUTDIR"

log "Bootstrapping minimal root filesystem"
debootstrap --arch="$ARCH" --variant=minbase --components="$COMPONENTS" \
  "$SUITE" "$ROOTFS" "$MIRROR"

# Sources for apt inside the image (also used for the install step below).
printf 'deb %s %s %s\n' "$MIRROR" "$SUITE" "$(echo "$COMPONENTS" | tr ',' ' ')" \
  > "$ROOTFS/etc/apt/sources.list"
[ -n "${SNAPSHOT:-}" ] && printf 'Acquire::Check-Valid-Until "false";\n' \
  > "$ROOTFS/etc/apt/apt.conf.d/10freemac-snapshot"

mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t tmpfs tmpfs "$ROOTFS/run"

in_chroot() { LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" "$@"; }

log "Installing packages"
# Do not start services inside the build chroot.
printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
chmod 755 "$ROOTFS/usr/sbin/policy-rc.d"
in_chroot apt-get update
# shellcheck disable=SC2086
in_chroot apt-get install -y --no-install-recommends $KERNEL $PACKAGES

log "Applying freemac overlay"
cp -a "$REPO/build/overlay/." "$ROOTFS/"
chmod 0440 "$ROOTFS/etc/sudoers.d/freemac-live"
cat > "$ROOTFS/etc/os-release" <<EOF
PRETTY_NAME="freemac $VERSION"
NAME="freemac"
VERSION="$VERSION"
VERSION_ID="$VERSION"
ID=freemac
ID_LIKE="$ID_LIKE"
HOME_URL="https://github.com/dean-plude/freemac"
EOF
in_chroot useradd --create-home --shell /bin/bash --groups sudo,audio,video,plugdev --user-group freemac 2>/dev/null \
  || in_chroot useradd --create-home --shell /bin/bash --groups sudo --user-group freemac
in_chroot passwd --delete freemac
in_chroot passwd --lock root
in_chroot systemctl enable systemd-networkd.service >/dev/null 2>&1 || true
mkdir -p "$ROOTFS/etc/systemd/network"
cat > "$ROOTFS/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF

log "Cleaning the image"
rm -f "$ROOTFS/usr/sbin/policy-rc.d"
in_chroot apt-get clean
rm -rf "$ROOTFS"/var/lib/apt/lists/* "$ROOTFS"/var/cache/apt/*.bin \
  "$ROOTFS"/var/log/*.log "$ROOTFS"/var/log/apt/* "$ROOTFS"/tmp/* \
  "$ROOTFS"/var/cache/debconf/*-old "$ROOTFS"/var/lib/dpkg/*-old
: > "$ROOTFS/etc/machine-id"
rm -f "$ROOTFS/var/lib/dbus/machine-id"

# Kernel and initramfs for the ISO (the initramfs contains live-boot).
cp "$(readlink -f "$ROOTFS/boot/vmlinuz")" "$ISOTREE/live/vmlinuz" 2>/dev/null \
  || cp "$ROOTFS"/boot/vmlinuz-* "$ISOTREE/live/vmlinuz"
cp "$(readlink -f "$ROOTFS/boot/initrd.img")" "$ISOTREE/live/initrd.img" 2>/dev/null \
  || cp "$ROOTFS"/boot/initrd.img-* "$ISOTREE/live/initrd.img"

umount_chroot

log "Normalising timestamps"
find "$ROOTFS" -newermt "@$SOURCE_DATE_EPOCH" -print0 \
  | xargs -0r touch --no-dereference --date="@$SOURCE_DATE_EPOCH"

log "Creating squashfs"
# mksquashfs reads SOURCE_DATE_EPOCH itself for the image timestamps.
mksquashfs "$ROOTFS" "$ISOTREE/live/filesystem.squashfs" \
  -noappend -comp xz -b 1M -no-progress -e boot

log "Assembling ISO"
mkdir -p "$ISOTREE/boot/grub" "$ISOTREE/.disk"
sed "s/@VERSION@/$VERSION/g" "$REPO/build/grub.cfg" > "$ISOTREE/boot/grub/grub.cfg"
printf 'freemac %s %s %s\n' "$VERSION" "$ARCH" "$SUITE" > "$ISOTREE/.disk/info"
find "$ISOTREE" -exec touch --no-dereference --date="@$SOURCE_DATE_EPOCH" {} +

grub-mkrescue -o "$ISO" "$ISOTREE" -- \
  -volid FREEMAC \
  -preparer_id "freemac build-iso.sh" \
  -application_id "freemac $VERSION"

(cd "$OUTDIR" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256")

log "Done: $ISO ($(du -h "$ISO" | cut -f1))"
echo "Test it with: ./scripts/run-qemu.sh $ISO"
