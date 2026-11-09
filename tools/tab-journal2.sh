chroot /newroot /usr/bin/journalctl -D /var/log/journal -b -1 --no-pager -o short-monotonic 2>&1 | grep -vE "sc8960x|get_charger_zcv|unsupported connected type" | tail -40;
echo ---FIRST-CHARGER-SPAM;
chroot /newroot /usr/bin/journalctl -D /var/log/journal -b -1 --no-pager -o short-monotonic 2>&1 | grep -m3 "unsupported connected type"
