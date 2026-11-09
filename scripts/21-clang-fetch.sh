#!/bin/bash
# Fetches Android Clang r450784e (14.0.7), the compiler the stock kernel was built with,
# from the official AOSP prebuilts repository.
set -uo pipefail
C=/build/kernel/clang
BASE=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads
mkdir -p "$C"
for ref in android13-release master-kernel-build-2022 android13-qpr3-release; do
  echo "trying ref: $ref"
  if curl -fsSL -m 1500 "$BASE/$ref/clang-r450784e.tar.gz" | tar -xz -C "$C" && [ -x "$C/bin/clang" ]; then
    echo "got clang from $ref"; break
  fi
  rm -rf "${C:?}"/*
done
"$C/bin/clang" --version | head -1 || { echo CLANG_MISSING; exit 1; }
du -sh "$C"
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) =' /build/kernel/src/Makefile | tr '\n' ' '; echo
echo CLANG_DONE
