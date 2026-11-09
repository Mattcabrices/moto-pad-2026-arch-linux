#!/bin/bash
# Waits for the preloader inside WSL (via usbipd) and asks it to boot into fastboot.
# Then watches for the bootloader's fastboot device. Writes nothing. Stops after 20 minutes.
cd /build/mtkclient || exit 1
end=$(( $(date +%s) + 1200 ))
while [ "$(date +%s)" -lt "$end" ]; do
  timeout 60 /build/mtkvenv/bin/python mtk.py meta FASTBOOT 2>&1 \
    | sed -u 's/\x1b\[[0-9;]*m//g' | grep -vE 'Hint|Power off the phone|For preloader mode|^[. ]*$' \
    | while IFS= read -r l; do echo "$(date +%T) $l"; done
  if fastboot devices 2>/dev/null | grep -q .; then echo "$(date +%T) FASTBOOT READY"; fastboot devices; exit 0; fi
  lsusb 2>/dev/null | grep -i 0e8d | sed "s/^/$(date +%T) lsusb: /"
  sleep 0.3
done
echo "$(date +%T) gave up"
