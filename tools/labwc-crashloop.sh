#!/bin/bash
# Runs in WSL: repeats tools/tab-labwc-test.sh until labwc dies (max 4 runs), then prints the tablet's last coredump.
T=/mnt/c/mpad26/MotoPadArch/tools
for i in 1 2 3 4; do
  r=$(bash $T/pad-sudo.sh $T/tab-labwc-test.sh | grep -E "alive")
  echo "run $i: $r"
  case "$r" in *alive=no*) break;; esac
done
bash $T/pad-sudo.sh $T/tab-coredump.sh
