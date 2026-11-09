#!/bin/bash
# Prints the stock facts bring-up depends on. Read-only apart from unpacking the ramdisk.
cd /build/stock
if [ ! -d vr ]; then
  mkdir vr
  (cd vr && lz4 -dc --no-sparse ../vendor_boot/vendor_ramdisk00 2>/dev/null | cpio -idm --quiet 2>/dev/null)
fi
echo "--- ramdisk top"; ls vr vr/first_stage_ramdisk 2>/dev/null | head -30
M=$(find vr -type d -path '*lib/modules' | head -1); echo "ramdisk modules dir: $M"
echo "ko: $(find vr -name '*.ko' | wc -l)  load: $(wc -l < "$M/modules.load" 2>/dev/null)"
ls "$M" | grep -v '\.ko$' | head
echo "--- dlkm"; for p in vendor_dlkm system_dlkm odm_dlkm; do
  echo "$p ko=$(find $p.d -name '*.ko' | wc -l) load=$(find $p.d -name modules.load -exec wc -l {} + | tail -1)"
done
echo "--- display, touch, input, storage candidates"
find vr vendor_dlkm.d system_dlkm.d -name '*.ko' -printf '%f\n' | sort -u | grep -iE 'drm|disp|panel|dsi|lcm|touch|ts_|gt9|focal|nt36|novatek|himax|ilitek|goodix|chipone|ufs|mmc|msdc|mtk_sd|usb|musb|mtu3|xhci|gadget|charger|battery|gauge|pmic' | tr '\n' ' '
echo; echo "--- wifi and bt modules"
find vr vendor_dlkm.d -name '*.ko' -printf '%f\n' | sort -u | grep -iE 'wlan|wmt|conn|bt|wifi|gen4' | tr '\n' ' '
echo; echo "--- connectivity rc"
grep -rlE 'wmt|wlan|conninfra|connsys' vendor.keep/vendor.d/etc/init 2>/dev/null | head -12
grep -rhE '^service .*(wmt|wlan|conn|wifi|bt|mtk_stp)' vendor.keep/vendor.d/etc/init 2>/dev/null | head -20
echo "--- connectivity binaries"
grep -iE 'wmt|wlan|conn|wifi|hostapd|supplicant|stp' vendor.bin.list | tr '\n' ' '; echo
echo "--- wifi firmware"
find vendor.keep -type f | grep -iE 'WIFI_RAM|WIFI_|wifi.cfg|mt6835|soc[0-9]|BT_RAM|bt_|connsys|WMT' | sed 's|.*/||' | head -40 | tr '\n' ' '; echo
echo "firmware total: $(du -sh vendor.keep | cut -f1)"
echo "--- kernel"
file boot/kernel 2>/dev/null; head -c 4 boot/kernel | od -An -tx1
echo "--- symbols needed vs provided"
python3 - <<'E'
import subprocess,glob
E
ls vr/first_stage_ramdisk 2>/dev/null | head; cat vr/fstab* 2>/dev/null | head -5
