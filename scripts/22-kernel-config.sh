#!/bin/bash
# Generates .config from stock plus the fragment and reports every difference.
set -euo pipefail
pacman -S --noconfirm --needed flex bison openssl elfutils perl >/dev/null 2>&1 || true
P=/mnt/c/mpad26/MotoPadArch/kernel
K=/build/kernel/src
O=/build/kernel/out
export PATH=/build/kernel/clang/bin:$PATH
mkdir -p "$O"
MK=(make -C "$K" O="$O" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- -s)

grep -v '^CONFIG_UNUSED_KSYMS_WHITELIST=' "$P/stock.config" > "$O/.config"
"$K/scripts/kconfig/merge_config.sh" -m -O "$O" "$O/.config" "$P/arch-fragment.config" >/dev/null
"${MK[@]}" olddefconfig

echo "--- every change from stock"
diff <(grep -E '^(# )?CONFIG_' "$P/stock.config" | sort) <(grep -E '^(# )?CONFIG_' "$O/.config" | sort) || true
echo "--- signing key setting"; grep -E 'CONFIG_MODULE_SIG_(KEY|ALL|HASH)=' "$O/.config"
