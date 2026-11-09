ls /sys/class/bluetooth; btmgmt info 2>&1 | head -6; bluetoothctl list 2>&1; tail -3 /tmp/bt-bridge.log
