#!/bin/bash
# Prepares the Arch WSL build host. Safe to re-run. Run as root inside WSL.
set -euo pipefail

pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
pacman -Syu --noconfirm --needed \
  base-devel git curl python bc cpio lz4 gzip xz zstd rsync pahole \
  arch-install-scripts android-tools erofs-utils e2fsprogs dosfstools \
  qemu-user-static qemu-user-static-binfmt libarchive openssh

mkdir -p /build/stock /build/kernel /build/rootfs /build/out
systemctl restart systemd-binfmt 2>/dev/null || true

echo "--- tools"
for t in mkbootimg unpack_bootimg avbtool lpunpack img2simg fsck.erofs pacstrap; do
  printf '%-16s %s\n' "$t" "$(command -v "$t" || echo MISSING)"
done
echo "--- aarch64 binfmt"
ls /proc/sys/fs/binfmt_misc | grep -i aarch64 || echo "aarch64 binfmt NOT registered"
du -sh / --exclude=/mnt --exclude=/proc --exclude=/sys 2>/dev/null | tail -1
