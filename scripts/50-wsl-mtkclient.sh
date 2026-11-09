#!/bin/bash
# Installs mtkclient inside WSL Arch for preloader recovery (talks to the tablet over usbipd).
set -euo pipefail
pacman -S --noconfirm --needed python python-pip libusb usbutils >/dev/null
D=/build/mtkclient
if [ ! -f "$D/mtk.py" ]; then
  rm -rf "$D"; mkdir -p "$D"
  # Same pinned commit as the Windows copy, but unpacked fresh, without the Windows-only UsbDk change.
  bsdtar -xf /mnt/c/mpad26/tools-ext/mtkclient.zip -C "$D" --strip-components 1
fi
[ -x /build/mtkvenv/bin/python ] || python -m venv /build/mtkvenv
/build/mtkvenv/bin/pip install -q pyusb pyserial pycryptodome pycryptodomex colorama
cd "$D" && /build/mtkvenv/bin/python mtk.py meta --help >/dev/null && echo "mtkclient OK"
lsmod 2>/dev/null | grep -E 'vhci|usbip' || echo "(usbip support is built into the WSL kernel)"
