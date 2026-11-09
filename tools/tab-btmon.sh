pkill -f pad-bt-bridge.py; sleep 2
(timeout 25 btmon > /tmp/btmon.txt 2>&1 &)
sleep 1; (nohup python3 /usr/local/bin/pad-bt-bridge.py > /tmp/bt-bridge.log 2>&1 &)
sleep 22
grep -E "^[<>@=] |Status|Command|Event|Index|hci0" /tmp/btmon.txt | tail -30
