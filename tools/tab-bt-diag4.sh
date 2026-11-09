journalctl -k -b --no-pager -o cat 2>/dev/null | grep -F -e "[MTK-BT]" -e "hci0" -e "WMT-FUNC" | grep -vE "Shorten read|xhci" | head -24
