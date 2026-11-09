journalctl -k -b --no-pager -o cat 2>/dev/null | grep -iE "wmt|wlan|consys|conninfra|patch|stp|wifi|mtk_wcn" | grep -viE "sc8960|charger" | tail -40
