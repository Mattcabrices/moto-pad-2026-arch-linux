#!/bin/bash
# Unpacks stock 17.5.10.020 images into /build/stock. Reads the Windows copies only.
set -euo pipefail
SRC="${STOCK_SRC:-/mnt/c/Edge 26/motopad-2026/recovery-diagnostics/stock-020-chain}"
OUT=/build/stock
mkdir -p "$OUT"; cd "$OUT"

for f in boot init_boot vendor_boot dtbo vbmeta vendor_dlkm system_dlkm odm_dlkm; do
  [ -f "$f.img" ] || cp "$SRC/$f.img" .
done

rm -rf boot vendor_boot
unpack_bootimg --boot_img boot.img --out boot --format mkbootimg > boot.args
unpack_bootimg --boot_img vendor_boot.img --out vendor_boot --format mkbootimg > vendor_boot.args
unpack_bootimg --boot_img init_boot.img --out init_boot --format mkbootimg > init_boot.args 2>&1 || true

for p in vendor_dlkm system_dlkm odm_dlkm; do
  rm -rf "$p.d"; mkdir "$p.d"
  fsck.erofs --extract="$p.d" "$p.img" >/dev/null 2>&1 || echo "erofs extract failed: $p"
done

# vendor.img is large, so keep only what bring-up needs.
if [ ! -d vendor.d ]; then
  mkdir vendor.d
  fsck.erofs --extract=vendor.d "$SRC/vendor.img" >/dev/null 2>&1 || echo "erofs extract failed: vendor"
  mkdir -p vendor.keep
  for d in firmware etc/firmware etc/init etc/fstab* etc/wifi etc/bluetooth etc/audio_param; do
    [ -e "vendor.d/$d" ] && cp -a --parents "vendor.d/$d" vendor.keep/
  done
  find vendor.d/bin -maxdepth 1 -type f -printf '%f\n' | sort > vendor.bin.list
fi

echo "--- boot args"; cat boot.args
echo; echo "--- vendor_boot args"; cat vendor_boot.args
echo; echo "--- vendor_boot files"; ls -la vendor_boot
du -sh "$OUT"
