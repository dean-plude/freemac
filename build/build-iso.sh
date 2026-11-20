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
need debootstrap mksquashfs xorriso grub-mkrescue mformat python3

# Package list: shared packages plus the base's own extras.
PACKAGES=$(cat "$REPO/build/packages/common.list" "$REPO/build/packages/desktop.list" \
  "$REPO/build/packages/installer.list" "$REPO/build/packages/$BASE.list" | grep -v '^[[:space:]]*#' | tr -s ' \n' ' ')

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

# Sources for apt inside the image (also used for the install step below):
# the release, its updates and its security fixes, so Harbor's Updates page
# and the daily check have something to offer.
COMPS=$(echo "$COMPONENTS" | tr ',' ' ')
case "$BASE" in
  debian)
    if [ -n "${SNAPSHOT:-}" ]; then
      SECURITY=${SECURITY_MIRROR:-http://snapshot.debian.org/archive/debian-security/$SNAPSHOT}
    else
      SECURITY=${SECURITY_MIRROR:-http://security.debian.org/debian-security}
    fi
    ;;
  ubuntu) SECURITY=${SECURITY_MIRROR:-http://security.ubuntu.com/ubuntu} ;;
esac
{
  printf 'deb %s %s %s\n' "$MIRROR" "$SUITE" "$COMPS"
  printf 'deb %s %s-updates %s\n' "$MIRROR" "$SUITE" "$COMPS"
  printf 'deb %s %s-security %s\n' "$SECURITY" "$SUITE" "$COMPS"
} > "$ROOTFS/etc/apt/sources.list"
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
# A second update, now that AppStream is installed, downloads the app
# catalogue (DEP-11) for Harbor and builds its cache.
in_chroot apt-get update || log "Warning: couldn't download the app catalogue; Harbor will fetch it later"

log "Applying freemac overlay"
cp -a "$REPO/build/overlay/." "$ROOTFS/"
chmod 0440 "$ROOTFS/etc/sudoers.d/freemac-live"
# freemac's own shell (Topline, Pier, Seek, ...).
mkdir -p "$ROOTFS/usr/lib/python3/dist-packages"
rm -rf "$ROOTFS/usr/lib/python3/dist-packages/freemac_shell"
cp -r "$REPO/shell/freemac_shell" "$ROOTFS/usr/lib/python3/dist-packages/"
find "$ROOTFS/usr/lib/python3/dist-packages/freemac_shell" -name __pycache__ -prune -exec rm -rf {} +
install -m 0755 "$REPO"/shell/bin/* "$ROOTFS/usr/bin/"
install -m 0644 "$REPO"/shell/applications/*.desktop "$ROOTFS/usr/share/applications/"
cat > "$ROOTFS/etc/os-release" <<EOF
PRETTY_NAME="freemac $VERSION"
NAME="freemac"
VERSION="$VERSION"
VERSION_ID="$VERSION"
ID=freemac
ID_LIKE="$ID_LIKE"
HOME_URL="https://github.com/dean-plude/freemac"
EOF
for d in Desktop Documents Downloads Music Pictures Videos; do
  mkdir -p "$ROOTFS/etc/skel/$d"
done
USER_GROUPS=sudo
for g in audio video render input plugdev bluetooth lpadmin; do
  in_chroot getent group "$g" >/dev/null && USER_GROUPS="$USER_GROUPS,$g"
done
in_chroot useradd --create-home --shell /bin/bash --groups "$USER_GROUPS" --user-group freemac
in_chroot passwd --delete freemac
in_chroot passwd --lock root
if in_chroot getent group netdev >/dev/null; then
  in_chroot usermod -aG netdev freemac
fi
# NetworkManager handles wired and Wi-Fi networks.
in_chroot systemctl enable NetworkManager.service
in_chroot systemctl enable seatd.service greetd.service
in_chroot systemctl set-default graphical.target
in_chroot glib-compile-schemas /usr/share/glib-2.0/schemas
# freemac's own app icons (art/icons), then refresh the cache so apps and the
# dock find them.
install -d "$ROOTFS/usr/share/icons/hicolor/scalable/apps"
install -m 0644 "$REPO"/art/icons/*.svg "$ROOTFS/usr/share/icons/hicolor/scalable/apps/"
in_chroot gtk-update-icon-cache -f -t /usr/share/icons/hicolor
# freemac's own GTK theme, light and dark (art/gtk-theme), on top of GTK's Adwaita,
# and the same colours for GTK 4 and Qt apps in /usr/share/freemac.
python3 "$REPO/art/gtk-theme/make-theme.py" "$ROOTFS/usr/share/themes" "$ROOTFS/usr/share/freemac"
# The same look for Qt 5 apps: freemac's own Kvantum themes (art/kvantum).
python3 "$REPO/art/kvantum/make-kvantum.py" "$ROOTFS/usr/share/Kvantum"
# freemac's icon theme: our own folder and file-type icons, Adwaita for the rest.
rm -rf "$ROOTFS/usr/share/icons/freemac"
cp -r "$REPO/art/icon-theme" "$ROOTFS/usr/share/icons/freemac"
# freemac's own pointer (art/cursors), drawn into the same theme.
cp "$REPO/art/cursors/make-cursors.py" "$ROOTFS/tmp/make-cursors.py"
in_chroot python3 /tmp/make-cursors.py /usr/share/icons/freemac || log "Warning: couldn't draw freemac's pointer"
rm -f "$ROOTFS/tmp/make-cursors.py"
in_chroot gtk-update-icon-cache -f -t /usr/share/icons/freemac
# Every installed app's own icon on freemac's rounded-square tile. The apt hook
# in the overlay does the same for apps installed later.
in_chroot freemac-icon-tiles --system --quiet || log "Warning: couldn't make app icon tiles"
# Strata's own Wayfire plugins (C++), compiled against the image's Wayfire:
# strata-decor (title bars and rounded window corners) and strata-shell
# (gtk-shell that hands app menus to Topline), plus Latch's lock screen
# module for gtklock. The build tools are removed again afterwards. If this Wayfire
# has a plugin API they don't support yet, Wayfire's stock plugins stay in use.
log "Building Strata's plugins"
STRATA_BUILD_DEPS="g++ pkg-config wayfire-dev wayland-protocols libwayland-bin nlohmann-json3-dev libgtk-3-dev"
# Only remove afterwards what this step added.
STRATA_NEW_DEPS=""
for pkg in $STRATA_BUILD_DEPS; do
  in_chroot dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" \
    || STRATA_NEW_DEPS="$STRATA_NEW_DEPS $pkg"
done
rm -rf "$ROOTFS/tmp/strata"
cp -r "$REPO/strata" "$ROOTFS/tmp/strata"
if in_chroot apt-get install -y --no-install-recommends $STRATA_BUILD_DEPS \
   && in_chroot sh /tmp/strata/build.sh /tmp/strata/out; then
  plugdir=$(in_chroot pkg-config --variable=plugindir wayfire 2>/dev/null || true)
  [ -n "$plugdir" ] || plugdir=/usr/lib/$(in_chroot dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)/wayfire
  for plugin in decor shell; do
    install -m 0644 "$ROOTFS/tmp/strata/out/libstrata-$plugin.so" "$ROOTFS$plugdir/libstrata-$plugin.so"
    install -D -m 0644 "$REPO/strata/$plugin/strata-$plugin.xml" "$ROOTFS/usr/share/wayfire/metadata/strata-$plugin.xml"
  done
  if [ -f "$ROOTFS/tmp/strata/out/freemac-latch.so" ]; then
    install -D -m 0644 "$ROOTFS/tmp/strata/out/freemac-latch.so" "$ROOTFS/usr/lib/gtklock/freemac-latch.so"
  fi
  for ini in "$ROOTFS/etc/skel/.config/wayfire.ini" "$ROOTFS/home/freemac/.config/wayfire.ini"; do
    if [ -f "$ini" ]; then
      sed -i -e 's/^\(plugins = .*\) decoration /\1 strata-decor /' \
             -e 's/^\(plugins = .*\) gtk-shell /\1 strata-shell /' "$ini"
    fi
  done
else
  log "Warning: Strata's plugins didn't build; using Wayfire's stock title bars and gtk-shell"
fi
if [ -n "$STRATA_NEW_DEPS" ]; then
  in_chroot apt-get purge -y --auto-remove $STRATA_NEW_DEPS || true
fi
rm -rf "$ROOTFS/tmp/strata"
mkdir -p "$ROOTFS/usr/share/backgrounds/freemac"
# Every scene in a day and a night version (Dials swaps them with the mode).
python3 "$REPO/art/make-wallpaper.py" --all "$ROOTFS/usr/share/backgrounds/freemac"
# freemac's own start-up sound, made from scratch
python3 "$REPO/art/sounds/make-sounds.py" "$ROOTFS/usr/share/sounds/freemac"
# Start-up screen: freemac's own Plymouth theme (overlay), built into the initramfs.
# Debian has plymouth-set-default-theme; Ubuntu picks the theme with an
# alternative instead.
THEME=/usr/share/plymouth/themes/freemac/freemac.plymouth
if in_chroot sh -c "command -v plymouth-set-default-theme >/dev/null && plymouth-set-default-theme freemac \
     || { update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth $THEME 300 \
          && update-alternatives --set default.plymouth $THEME; }"; then
  in_chroot update-initramfs -u || log "Warning: couldn't rebuild the initramfs with the start-up screen"
else
  log "Warning: couldn't set the start-up screen; the boot shows text instead"
fi

log "Cleaning the image"
rm -f "$ROOTFS/usr/sbin/policy-rc.d"
in_chroot apt-get clean
# The package lists stay: Harbor's app catalogue (AppStream DEP-11 data) and
# installs work straight away; Harbor refreshes them when they get old.
rm -rf "$ROOTFS"/var/lib/apt/lists/partial/* "$ROOTFS"/var/lib/apt/lists/lock \
  "$ROOTFS"/var/cache/apt/*.bin \
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
# mksquashfs reads SOURCE_DATE_EPOCH itself for the image timestamps. /boot
# stays in the image so the installer can copy a complete system.
mksquashfs "$ROOTFS" "$ISOTREE/live/filesystem.squashfs" \
  -noappend -comp xz -b 1M -no-progress

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
