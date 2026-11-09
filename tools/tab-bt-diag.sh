journalctl -k -b --no-pager -o cat -n 3000 | grep -E "Bluetooth|hci0|MTK-BT|BT_open|bt_drv|stpbt" | tail -18
echo ---; cat /tmp/bt-bridge.log
