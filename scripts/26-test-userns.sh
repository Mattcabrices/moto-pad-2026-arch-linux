#!/bin/bash
# Offline test: does enabling CONFIG_USER_NS (for Chromium's sandbox) keep every stock module
# loadable? Builds in /build/kernel/out-userns so the working kernel output is untouched.
set -uo pipefail
P=/mnt/c/mpad26/MotoPadArch
K=/build/kernel/src
O=/build/kernel/out-userns
export PATH=/build/kernel/clang/bin:$PATH
MK=(make -C "$K" O="$O" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-)
mkdir -p "$O"
grep -v '^CONFIG_UNUSED_KSYMS_WHITELIST=' "$P/kernel/stock.config" > "$O/.config"
"$K/scripts/kconfig/merge_config.sh" -m -O "$O" "$O/.config" "$P/kernel/arch-fragment.config" >/dev/null
"$K/scripts/config" --file "$O/.config" -e USER_NS
"${MK[@]}" -s olddefconfig
grep -E '^CONFIG_USER_NS=' "$O/.config" || { echo "USER_NS did not stick"; exit 2; }
echo "--- extra changes from USER_NS"
diff <(grep -E '^(# )?CONFIG_' /build/kernel/out/.config | sort) <(grep -E '^(# )?CONFIG_' "$O/.config" | sort) | grep '^[<>]'
time "${MK[@]}" -j"$(nproc)" KBUILD_BUILD_USER=archpad KBUILD_BUILD_HOST=wsl vmlinux > /build/kernel/userns-build.log 2>&1
echo "BUILD_EXIT=$?"
sed "s|/build/kernel/out/vmlinux.symvers|$O/vmlinux.symvers|" "$P/scripts/24-check-kmi.py" > /tmp/kmi-userns.py
python3 /tmp/kmi-userns.py
echo "KMI_EXIT=$?"
