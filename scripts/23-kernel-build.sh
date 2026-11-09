#!/bin/bash
# Builds the kernel with the built-in early-boot initramfs, then checks stock modules.
set -uo pipefail
P=/mnt/c/mpad26/MotoPadArch
BB=/build/rootfs/root/usr/bin/busybox
[ -x "$BB" ] || { echo "ABORT: build the rootfs first; busybox not found"; exit 2; }
grep -q $'\r' "$P/scripts/archinit" && { echo "ABORT: archinit has CRLF line endings"; exit 2; }

/build/kernel/clang/bin/clang --target=aarch64-linux-gnu -nostdlib -static -ffreestanding \
  -fno-stack-protector -O2 -fuse-ld=lld -o /build/kernel/reboot-bootloader "$P/scripts/reboot-bootloader.c" \
  || { echo "ABORT: reboot-bootloader did not compile"; exit 2; }
cat > /build/kernel/initramfs.list <<EOF
dir /dev 755 0 0
nod /dev/console 600 0 0 c 5 1
dir /archbin 755 0 0
file /archbin/busybox $BB 755 0 0
file /archbin/reboot-bootloader /build/kernel/reboot-bootloader 755 0 0
file /archinit $P/scripts/archinit 755 0 0
EOF

bash "$P/scripts/22-kernel-config.sh" > /build/kernel/config-diff.txt 2>&1
for want in MODULE_SCMVERSION DEBUG_INFO_BTF_MODULES CFI_CLANG DEVTMPFS FHANDLE VT AUTOFS_FS; do
  grep -q "^CONFIG_$want=y" /build/kernel/out/.config || { echo "ABORT: CONFIG_$want lost"; exit 2; }
done
echo "--- config changes from stock"; grep -E '^[<>]' /build/kernel/config-diff.txt

export PATH=/build/kernel/clang/bin:$PATH
cd /build/kernel/src
time make O=/build/kernel/out ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- \
  KBUILD_BUILD_USER=archpad KBUILD_BUILD_HOST=wsl -j"$(nproc)" Image.lz4 > /build/kernel/build.log 2>&1
rc=$?
tail -8 /build/kernel/build.log
ls -la /build/kernel/out/arch/arm64/boot/Image.lz4 2>&1
du -sh /build/kernel/out
echo "BUILD_EXIT=$rc"
[ $rc -eq 0 ] || exit $rc
echo "--- module check"
python3 "$P/scripts/24-check-kmi.py"
echo "KMI_EXIT=$?"
