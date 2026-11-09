#!/bin/bash
# Fetches pinned libhybris and Halium android-headers (Android 16) sources into /build/src.
# Approved by Matt 2026-11-08 for GPU acceleration work.
set -e
HYBRIS=7079712a42ea2754adf747e70c6cc75764c8596e   # libhybris master, 2026-06-24
mkdir -p /build/src && cd /build/src
HDR=$(curl -fsSL -m 30 -H 'User-Agent: motopad' https://api.github.com/repos/Halium/android-headers/commits/halium-16.0 \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])')
echo "android-headers halium-16.0 at $HDR"
[ -f libhybris-$HYBRIS.tar.gz ] || curl -fsSL -m 300 -o libhybris-$HYBRIS.tar.gz https://codeload.github.com/libhybris/libhybris/tar.gz/$HYBRIS
[ -f android-headers-$HDR.tar.gz ] || curl -fsSL -m 300 -o android-headers-$HDR.tar.gz https://codeload.github.com/Halium/android-headers/tar.gz/$HDR
sha256sum libhybris-$HYBRIS.tar.gz android-headers-$HDR.tar.gz
rm -rf libhybris android-headers; mkdir libhybris android-headers
tar -xzf libhybris-$HYBRIS.tar.gz -C libhybris --strip-components 1
tar -xzf android-headers-$HDR.tar.gz -C android-headers --strip-components 1
echo "$HDR" > android-headers/.pinned-commit
echo "--- platforms:"; ls libhybris/hybris/platforms
echo "--- headers:"; ls android-headers | head; grep -rh "ANDROID_VERSION_MAJOR" android-headers/android-version.h 2>/dev/null | head -2
