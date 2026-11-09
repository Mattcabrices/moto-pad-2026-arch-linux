#!/bin/bash
# Packs boot-archpad.img and userdata-archpad.simg, checks them, and copies them to out/.
set -euo pipefail
R=/build/rootfs/root
O=/build/out
WIN=/mnt/c/mpad26/MotoPadArch/out
IMG=/build/kernel/out/arch/arm64/boot/Image.lz4
mkdir -p "$O" "$WIN"
[ -f "$R/etc/archpad-release" ] || { echo "ABORT: rootfs not configured"; exit 2; }

# boot: kernel only, as in stock. The ramdisk comes from the kernel's built-in initramfs.
mkbootimg --header_version 4 --kernel "$IMG" --os_version 16.0.0 --os_patch_level 2026-07 \
  -o "$O/boot-archpad.img"
# Unsigned hash footer. The unlocked bootloader reports orange state and continues.
avbtool add_hash_footer --image "$O/boot-archpad.img" --partition_name boot --partition_size 67108864
rm -rf "$O/boot-check"; unpack_bootimg --boot_img "$O/boot-archpad.img" --out "$O/boot-check" | grep -E 'header version|kernel size'
cmp "$O/boot-check/kernel" "$IMG" && echo "boot kernel matches Image.lz4"

# userdata: ext4 sized to the rootfs plus headroom. pad-growfs fills the partition on first boot.
# orphan_file is left off for older-kernel compatibility.
size_mb=$(( $(du -sm "$R" | cut -f1) + 1024 ))
rm -f "$O/userdata-archpad.img"
mke2fs -q -t ext4 -O ^orphan_file -L archpad -d "$R" "$O/userdata-archpad.img" "${size_mb}M"
e2fsck -fn "$O/userdata-archpad.img" | tail -1
debugfs -R 'cat /etc/archpad-release' "$O/userdata-archpad.img" 2>/dev/null
img2simg "$O/userdata-archpad.img" "$O/userdata-archpad.simg"
rm -f "$O/userdata-archpad.img"

cp "$O/boot-archpad.img" "$O/userdata-archpad.simg" "$O/archpad_ed25519" "$O/archpad_ed25519.pub" "$WIN/"
cd "$WIN" && sha256sum boot-archpad.img userdata-archpad.simg > SHA256SUMS.txt
ls -la "$WIN"
echo IMAGES_DONE
