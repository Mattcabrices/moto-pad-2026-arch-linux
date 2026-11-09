#!/bin/bash
# Builds hci_vhci.ko (virtual Bluetooth HCI adapter) as a module against the Arch kernel, so a
# userspace bridge can expose MediaTek's /dev/stpbt to BlueZ. Standalone driver: it changes no
# structures that stock modules use. Output: /build/out/tools/hci_vhci.ko
set -uo pipefail
K=/build/kernel/src
O=/build/kernel/out
export PATH=/build/kernel/clang/bin:$PATH
MK=(make -C "$K" O="$O" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-)
"$K/scripts/config" --file "$O/.config" -m BT_HCIVHCI
"${MK[@]}" -s olddefconfig
grep -E '^CONFIG_BT_HCIVHCI=' "$O/.config"
"${MK[@]}" -s -j"$(nproc)" modules_prepare
# In-tree single-module target: modpost reads vmlinux.symvers, so symbol CRCs are recorded.
"${MK[@]}" -j"$(nproc)" drivers/bluetooth/hci_vhci.ko 2>&1 | grep -E "hci_vhci|error|Error|WARNING" | head -8
mkdir -p /build/out/tools
install -m644 "$O/drivers/bluetooth/hci_vhci.ko" /build/out/tools/hci_vhci.ko
modinfo -F vermagic /build/out/tools/hci_vhci.ko
