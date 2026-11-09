#!/bin/bash
# Builds libpropshim.so (tools/src/propshim.c) for the bionic Wi-Fi helpers. The property table
# comes from the stock vendor build.prop plus overrides that Android's init would normally set.
set -e
R=/build/rootfs/root
S=/mnt/c/mpad26/MotoPadArch/tools/src
OUT=/build/out/android-rt/system/lib64
mountpoint -q "$R" || mount --bind "$R" "$R"
# KEEP_GCC=1: leave gcc and the package cache alone (another build is using the rootfs).
W=/root/propshim-src
mkdir -p "$R$W"
cp "$S/propshim.c" "$R$W/"
{
  echo "static const struct kv PROPS[] = {"
  cat /build/stock/vendor.d/build.prop /build/stock/vendor.d/default.prop 2>/dev/null \
    | grep -E '^[a-z][A-Za-z0-9._-]*=' | grep -v '^vendor\.connsys\.driver\.ready=' \
    | sed 's/\\/\\\\/g; s/"/\\"/g' | awk -F= '!seen[$1]++ { v=substr($0, length($1)+2); printf "  {\"%s\", \"%s\"},\n", $1, v }'
  # Set by Android init/wmt_loader at runtime:
  echo '  {"vendor.connsys.driver.ready", "yes"},'
  echo '  {"ro.build.type", "user"},'
  echo '  {"ro.boot.hardware", "mt8755"},'
  # GPU port: the service managers are started by hand, so report them ready.
  echo '  {"hwservicemanager.ready", "true"},'
  echo '  {"servicemanager.ready", "true"},'
  echo "};"
} > "$R$W/props.h"
echo "props: $(grep -c '{"' "$R$W/props.h")"
arch-chroot "$R" pacman -S --noconfirm --needed gcc >/dev/null
arch-chroot "$R" sh -c 'cd /root/propshim-src && gcc -O2 -shared -fPIC -nostdlib -fno-stack-protector -fno-builtin \
  -Wl,--hash-style=both -Wl,-z,max-page-size=4096 -o libpropshim.so propshim.c'
install -Dm644 "$R$W/libpropshim.so" "$OUT/libpropshim.so"
rm -rf "$R$W"
if [ -z "${KEEP_GCC:-}" ]; then
  arch-chroot "$R" pacman -Rns --noconfirm gcc >/dev/null || true
  rm -f "$R"/var/cache/pacman/pkg/*
fi
readelf -dW "$OUT/libpropshim.so" | grep -E "NEEDED|HASH" || true
nm -D "$OUT/libpropshim.so" | grep " T "
