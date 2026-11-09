#!/bin/bash
# Assembles a minimal Android runtime for MediaTek's Wi-Fi helper programs, from the stock .020
# system and vendor images, into /build/out/android-rt (installed on the tablet as /opt/android).
# Layout follows Android paths so the bionic linker finds everything:
#   /system/bin/linker64, /system/lib64/*, /vendor/bin/<helpers>, /vendor/firmware/*
set -euo pipefail
S=/build/stock
SRC="${STOCK_SRC:-/mnt/c/Edge 26/motopad-2026/recovery-diagnostics/stock-020-chain}"
W=/build/stock/android-work
OUT=/build/out/android-rt
HELPERS="wmt_loader wmt_launcher wlan_assistant conninfra_loader"
pacman -S --noconfirm --needed unzip >/dev/null 2>&1 || true

# system.img: extract once (about 3 GB).
if [ ! -d $S/system.d/system ]; then
  rm -rf $S/system.d; mkdir -p $S/system.d
  fsck.erofs --extract=$S/system.d "$SRC/system.img" >/dev/null
fi
SYS=$S/system.d/system
[ -d "$SYS/lib64" ] || SYS=$S/system.d

# Bionic lives in the com.android.runtime APEX.
rm -rf $W; mkdir -p $W/rt
APEX=$(ls "$SYS"/apex/com.android.runtime*.apex 2>/dev/null | head -1)
[ -n "$APEX" ] || { echo "runtime APEX not found"; exit 2; }
unzip -o -q "$APEX" apex_payload.img -d $W
if ! fsck.erofs --extract=$W/rt $W/apex_payload.img >/dev/null 2>&1; then
  debugfs -R "rdump / $W/rt" $W/apex_payload.img >/dev/null 2>&1
fi
echo "runtime APEX: $(basename "$APEX")"

rm -rf $OUT; mkdir -p $OUT/system/bin $OUT/system/lib64 $OUT/vendor/bin $OUT/vendor/lib64 \
  $OUT/vendor/firmware $OUT/dev $OUT/proc $OUT/sys $OUT/data/vendor $OUT/linkerconfig $OUT/apex
install -m755 "$(find $W/rt -name linker64 -path "*bin*" | head -1)" $OUT/system/bin/linker64
for b in $HELPERS; do install -m755 $S/vendor.d/bin/$b $OUT/vendor/bin/; done
cp -a $S/vendor.d/firmware/. $OUT/vendor/firmware/

# Copy every needed library, searching vendor, system, then bionic, until nothing is missing.
find_lib() {
  for d in $S/vendor.d/lib64 "$SYS/lib64" $(find $W/rt -type d -path "*lib64/bionic") $W/rt/lib64; do
    [ -f "$d/$1" ] && { echo "$d/$1"; return 0; }
  done
  return 0   # not found: caller reports MISSING (a non-zero status would trip set -e)
}
todo=$(for b in $HELPERS; do readelf -dW $S/vendor.d/bin/$b | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'; done | sort -u)
seen=""
while [ -n "$todo" ]; do
  next=""
  for l in $todo; do
    case " $seen " in *" $l "*) continue ;; esac
    seen="$seen $l"
    f=$(find_lib "$l")
    [ -n "$f" ] || { echo "MISSING $l"; continue; }
    install -m644 "$f" $OUT/system/lib64/$l
    next="$next $(readelf -dW "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')"
  done
  todo=$(echo $next | tr ' ' '\n' | sort -u)
done
echo "libraries: $(ls $OUT/system/lib64 | tr '\n' ' ')"
du -sh $OUT
echo RUNTIME_DONE
