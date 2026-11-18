#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Boot a freemac ISO in QEMU.
#
#   ./scripts/run-qemu.sh [--uefi] [--serial] [ISO]
#
#   --uefi    boot with OVMF UEFI firmware instead of legacy BIOS
#   --serial  no window: show the serial console in this terminal
#             (quit with Ctrl-A then X)
#
# KVM is used when /dev/kvm is available; otherwise QEMU emulates the CPU,
# which works but is much slower.

set -eu

UEFI=0
SERIAL=0
ISO=

for arg in "$@"; do
  case "$arg" in
    --uefi) UEFI=1 ;;
    --serial) SERIAL=1 ;;
    -h|--help) sed -n '3,13p' "$0"; exit 0 ;;
    *) ISO=$arg ;;
  esac
done

if [ -z "$ISO" ]; then
  ISO=$(ls -t "$(dirname "$0")"/../out/freemac-*.iso 2>/dev/null | head -n1 || true)
fi
[ -f "$ISO" ] || { echo "No ISO found; build one with: sudo ./build/build-iso.sh" >&2; exit 1; }

set -- -m 2048 -smp 2 -cdrom "$ISO" -boot d \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0

if [ -w /dev/kvm ]; then
  set -- "$@" -enable-kvm -cpu host
fi

if [ "$UEFI" -eq 1 ]; then
  FOUND=0
  for fw in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
    vars=$(echo "$fw" | sed 's/CODE/VARS/')
    if [ -f "$fw" ] && [ -f "$vars" ]; then
      # UEFI variables need a writable copy.
      VARS_COPY=$(mktemp "${TMPDIR:-/tmp}/freemac-ovmf-vars.XXXXXX")
      cp "$vars" "$VARS_COPY"
      set -- "$@" -drive if=pflash,format=raw,readonly=on,file="$fw" \
        -drive if=pflash,format=raw,file="$VARS_COPY"
      FOUND=1
      break
    fi
  done
  [ "$FOUND" -eq 1 ] || { echo "OVMF firmware not found; install the ovmf package." >&2; exit 1; }
fi

if [ "$SERIAL" -eq 1 ]; then
  set -- "$@" -nographic
else
  set -- "$@" -vga virtio
fi

exec qemu-system-x86_64 "$@"
