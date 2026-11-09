#!/bin/bash
# Stages a full Android 16 userspace (stock .020 system + vendor + runtime APEX) for the GPU port.
# Output: /build/out/android-full.tar, installed on the tablet as /opt/android-full.
set -euo pipefail
S=/build/stock
O=/build/out/android-full
SYS=$S/system.d/system; [ -d "$SYS/lib64" ] || SYS=$S/system.d
rm -rf "$O"; mkdir -p "$O"/{apex,dev,proc,sys,data,linkerconfig,mnt,odm,product,system_ext,tmp,acct,config}
cp -a "$SYS" "$O/system"
cp -a $S/vendor.d "$O/vendor"
# APEXes: extract each payload into /apex/<name> (what apexd would mount).
for a in "$SYS"/apex/*.apex "$SYS"/apex/*.capex; do
  [ -f "$a" ] || continue
  n=$(basename "$a"); n=${n%.apex}; n=${n%.capex}
  t=$(mktemp -d)
  unzip -o -q "$a" apex_payload.img -d "$t" 2>/dev/null || { rm -rf "$t"; continue; }
  mkdir -p "$O/apex/$n"
  fsck.erofs --extract="$O/apex/$n" "$t/apex_payload.img" >/dev/null 2>&1 \
    || debugfs -R "rdump / $O/apex/$n" "$t/apex_payload.img" >/dev/null 2>&1 || true
  rm -rf "$t"
done
# Android also exposes APEXes without the version/vendor suffix, e.g. /apex/com.android.runtime.
for d in "$O"/apex/*; do b=$(basename "$d"); s=${b%%@*}; [ "$s" != "$b" ] && [ ! -e "$O/apex/$s" ] && ln -s "$b" "$O/apex/$s"; done
ln -sfn /system/bin "$O/bin"; ln -sfn /system/etc "$O/etc"
echo "apexes: $(ls $O/apex | wc -l): $(ls $O/apex | head -12 | tr '\n' ' ')"
ls -la "$O/apex/com.android.runtime/bin/linker64" 2>&1 | cut -c1-100
tar -C "$O" -cf /build/out/android-full.tar .
ls -la /build/out/android-full.tar
du -sh "$O"
