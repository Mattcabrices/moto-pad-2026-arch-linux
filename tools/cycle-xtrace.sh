#!/bin/bash
# Runs in WSL. If the tablet is at the early-boot console, reboots it into Arch; waits for SSH;
# then runs the traced Xorg test and saves the stream to /build/out/xstrace2.log.
T=/mnt/c/mpad26/MotoPadArch/tools
r=$(bash $T/wait-console.sh)
echo "$r"
if echo "$r" | grep -q CONSOLE; then
  python3 $T/padcmd.py "umount /newroot/proc /newroot/sys 2>/dev/null; sync; reboot -f" 4 >/dev/null
  sleep 20
  r=$(bash $T/wait-console.sh); echo "$r"
fi
echo "$r" | grep -q SSH || { echo "no SSH"; exit 1; }
bash $T/pad-scp.sh /build/out/tools/noplanes.so >/dev/null && bash $T/pad-sudo.sh $T/tab-xconf-install.sh
timeout 100 bash $T/pad-sudo.sh $T/tab-xstrace-shim.sh > /build/out/xstrace2.log 2>&1
bash /mnt/c/Users/mattc/AppData/Local/Temp/claude/f3f7358aa469fc08/5d5c5fa4-7f39-4c49-a3f1-c915337df15b/scratchpad/xanalyze2.sh
grep -E "^XTRACE \((II|EE|WW)\)" /build/out/xstrace2.log | tail -15 | cut -c1-170
