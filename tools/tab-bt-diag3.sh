journalctl -k -b --no-pager -o cat -g "hci0|Bluetooth: |MTK-BT" 2>&1 | grep -v sc8960 | tail -14
