#!/bin/bash
# Rebuilds rootfs config, kernel (with module check), and images. Meant to be started
# detached from Windows; writes /build/kernel/run23.log and the exit code to run23.done.
S=/mnt/c/mpad26/MotoPadArch/scripts
rm -f /build/kernel/run23.done
{
  bash "$S/55-build-tablet-tools.sh" && bash "$S/56-android-runtime.sh" && bash "$S/57-build-propshim.sh" && bash "$S/31-rootfs-config.sh" && bash "$S/23-kernel-build.sh" && bash "$S/27-build-hci-vhci.sh" && bash "$S/40-images.sh"
} > /build/kernel/run23.log 2>&1
echo $? > /build/kernel/run23.done
