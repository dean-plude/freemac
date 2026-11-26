freemac @VERSION@: a live ISO you can start in a virtual machine (or on a PC from a USB stick) without building anything.

freemac is an original, free desktop for x86-64 PCs that works like a classic Mac-style desktop: a menu bar along the top, a dock along the bottom, Command-key shortcuts and its own apps. It is Linux underneath and contains nothing from Apple. It is not macOS, but it comes with Ferry, its own runner for Intel Mac apps: open a Mac app (a .app, or a .dmg or .pkg to install one) and it runs on the freemac desktop. Many apps run; some don't yet, and App Store apps never will.

## What's new in @VERSION@

<!-- whats-new -->
@WHATSNEW@
<!-- /whats-new -->

## Download

- **freemac-@VERSION@-amd64.iso** (about @SIZE@ MB)
- **freemac-@VERSION@-amd64.iso.sha256**, to check the download: `sha256sum -c freemac-@VERSION@-amd64.iso.sha256`
@FERRY@

SHA-256: `@SHA256@`

A computer that already has freemac 1.134 or later installed gets this version in **Dials > Software Update**, from **freemac-update-@VERSION@-ubuntu-amd64.tar.xz**; it installs when the computer restarts.

## Trying it in a virtual machine

Make a new virtual machine and boot it from the ISO. It starts straight into the desktop as the user `freemac`, with no password.

| Setting | Use |
| --- | --- |
| Type | Linux, Ubuntu 64-bit (or "Other Linux 64-bit") |
| Memory | 3 GB or more (2 GB works, but slowly) |
| Processors | 2 or more |
| Firmware | BIOS or UEFI both work; turn Secure Boot off |
| Video | VirtIO-GPU in QEMU and virt-manager, VMSVGA in VirtualBox, 3D acceleration off |
| Disk | Not needed to try it; 20 GB or more to install |

To install from the live session, choose **Install freemac…** in the Welcome window. It erases the whole disk you pick.

Tested before this release: the image boots under QEMU with both BIOS and UEFI firmware, and the desktop (Wayfire, the menu bar and the dock) starts on its own. VirtualBox, VMware, Hyper-V, UTM and real PCs haven't been tested yet. Reports are welcome.

QEMU, for example:

```sh
qemu-system-x86_64 -m 3072 -smp 2 -enable-kvm -cpu host -vga virtio \
  -cdrom freemac-@VERSION@-amd64.iso -boot d
```

## What's in it

The full list of what each version added is in [docs/ROADMAP.md](https://github.com/dean-plude/freemac/blob/Main/docs/ROADMAP.md).

This is a pre-release: it's for trying out, not yet for a computer you depend on.
