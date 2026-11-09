# Runs as root on the tablet: display/DRM facts for the GPU display path.
uptime
ls -l /dev/dri/
cat /sys/class/drm/*/status 2>/dev/null | paste -sd' '
for c in /sys/class/drm/card*-*; do echo "$c $(cat $c/status) $(head -1 $c/modes 2>/dev/null)"; done
pgrep -a Xorg | cut -c1-120; pgrep -a lightdm | head -2
systemctl list-units --type=service --state=running | grep -iE "dm|getty|x" | head
pgrep -af "servicemanager|allocator" | cut -c1-100
ls /usr/local/hybris/bin | head; ls /usr/include/xf86drm.h /usr/lib/libdrm.so* 2>&1 | head -3
