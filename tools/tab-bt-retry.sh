install -Dm755 /tmp/pad-bt-bridge.py /usr/local/bin/pad-bt-bridge.py
pkill -f pad-bt-bridge.py; sleep 2
(nohup python3 /usr/local/bin/pad-bt-bridge.py > /tmp/bt-bridge.log 2>&1 &)
sleep 12; grep -E "answered|error" /tmp/bt-bridge.log; bluetoothctl list 2>&1; btmgmt info 2>&1 | grep -E "hci0|addr|current settings" | head -4
