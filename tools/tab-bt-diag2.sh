ls /sys/class/bluetooth/ 2>&1
btmgmt info 2>&1 | head -5
hciconfig -a 2>&1 | head -6
pgrep -af pad-bt-bridge
cat /proc/$(pgrep -f pad-bt-bridge.py | head -1)/status 2>/dev/null | grep State
