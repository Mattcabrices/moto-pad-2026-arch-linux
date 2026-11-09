# Run on the held console with Arch mounted at /newroot: stop XFCE autostart for now and add
# the boot-ok service the tablet's rootfs is missing. Then sync and reboot.
: > /newroot/home/matt/.no-x;
chown 1000:1000 /newroot/home/matt/.no-x;
printf '[Unit]\nDescription=Mark this Arch boot as good (clears archinit boot-loop marker)\nAfter=multi-user.target\n[Service]\nType=oneshot\nExecStartPre=/usr/bin/sleep 120\nExecStart=/usr/bin/rm -f /var/lib/archpad/boot-pending\n[Install]\nWantedBy=multi-user.target\n' > /newroot/etc/systemd/system/pad-boot-ok.service;
mkdir -p /newroot/etc/systemd/system/multi-user.target.wants;
ln -sf /etc/systemd/system/pad-boot-ok.service /newroot/etc/systemd/system/multi-user.target.wants/pad-boot-ok.service;
ls -la /newroot/home/matt/.no-x /newroot/etc/systemd/system/multi-user.target.wants/pad-boot-ok.service;
cat /newroot/etc/systemd/system/pad-boot-ok.service | head -3;
ls /newroot/var/lib/archpad/;
sync; echo FIX_APPLIED
