#!/bin/bash
# Writes ONLY boot_a through the factory DA in BROM mode, then reads it back and compares.
# Usage: 53-wsl-write-boot-a.sh <image>   (default: /build/out/boot-archpad.img)
IMG=${1:-/build/out/boot-archpad.img}
cd /build/mtkclient || exit 1
want=$(grep boot-archpad /mnt/c/mpad26/MotoPadArch/out/SHA256SUMS.txt | cut -d' ' -f1)
have=$(sha256sum "$IMG" | cut -d' ' -f1)
if [ "$IMG" = /build/out/boot-archpad.img ] && [ "$want" != "$have" ]; then echo "ABORT: image hash mismatch"; exit 2; fi
[ "$(stat -c %s "$IMG")" -eq 67108864 ] || { echo "ABORT: image is not 64 MiB"; exit 2; }
echo "$(date +%T) image $IMG sha256 $have"
echo "$(date +%T) waiting for BROM; hold Vol Up + Vol Down and plug in USB"
run() { timeout 900 /build/mtkvenv/bin/python mtk.py "$@" --loader /build/fw/DA_BR.bin --auth /build/fw/da.auth --stock 2>&1 \
  | sed -u 's/\x1b\[[0-9;]*m//g' | grep --line-buffered -vE 'Hint|Power off the phone|For preloader mode|For brom mode|If it is already|^[. ]*$' \
  | while IFS= read -r l; do echo "$(date +%T) $l"; done; }
# One session: write, then read back. 'w' and 'r' each take partition and file lists.
run w boot_a "$IMG" --noreconnect
echo "$(date +%T) write step finished; reading back for verification"
run r boot_a /build/out/boot_a.readback --noreconnect
if [ -f /build/out/boot_a.readback ]; then
  rb=$(sha256sum /build/out/boot_a.readback | cut -d' ' -f1)
  echo "$(date +%T) readback sha256 $rb"
  [ "$rb" = "$have" ] && echo "VERIFIED: boot_a matches the image" || echo "MISMATCH: boot_a differs from the image"
else
  echo "readback not produced"
fi
