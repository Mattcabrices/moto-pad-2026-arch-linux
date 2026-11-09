# Run on the tablet's held console: reads the Arch journal from the mounted root filesystem.
mountpoint -q /newroot/proc || mount -t proc proc /newroot/proc;
mountpoint -q /newroot/sys || mount -t sysfs sys /newroot/sys;
chroot /newroot /usr/bin/journalctl -D /var/log/journal --list-boots --no-pager 2>&1 | tail -5;
echo ---LAST-BOOT-TAIL;
chroot /newroot /usr/bin/journalctl -D /var/log/journal -b -1 --no-pager -o short-monotonic 2>&1 | tail -45
