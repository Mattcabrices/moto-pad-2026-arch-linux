#!/bin/bash
# Read-only: waits for the preloader in WSL and prints the GPT using the factory DA and auth.
P="/mnt/c/ProgramData/RSA/Download/RomFiles/XT2575_4_ROW_OPEN_USER_M1317.3_W_ZUI_17.5.10.020_ST/XT2575-4_ROW_OPEN_USER_M1317.3_W_ZUI_17.5.10.020_ST"
mkdir -p /build/fw
cp "$P/image/download_agent/DA_BR.bin" "$P/da.auth" /build/fw/ || exit 1
sha256sum /build/fw/DA_BR.bin /build/fw/da.auth
cmp -s "$P/da.auth" "$P/image/download_agent/da.auth" && echo "both da.auth copies identical"
cd /build/mtkclient || exit 1
echo "$(date +%T) waiting for preloader; power-cycle the tablet now"
timeout 900 /build/mtkvenv/bin/python mtk.py printgpt --loader /build/fw/DA_BR.bin --auth /build/fw/da.auth --stock 2>&1 \
  | sed -u 's/\x1b\[[0-9;]*m//g' | grep --line-buffered -vE 'Hint|Power off the phone|For preloader mode|^[. ]*$' \
  | while IFS= read -r l; do echo "$(date +%T) $l"; done
echo "$(date +%T) printgpt finished"
