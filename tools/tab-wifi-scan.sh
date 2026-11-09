nmcli radio wifi on 2>&1
nmcli dev status | head -6
nmcli dev wifi rescan 2>&1; sleep 8
nmcli -f SSID,SIGNAL,SECURITY,CHAN dev wifi list 2>&1 | head -15
