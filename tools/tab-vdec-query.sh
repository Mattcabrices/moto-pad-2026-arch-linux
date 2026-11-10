# Runs as root on the tablet: lists the MTK V4L2 decoder's formats and controls; VCP firmware state.
pacman -Q v4l-utils >/dev/null 2>&1 || pacman -S --noconfirm --needed v4l-utils >/dev/null 2>&1 || echo "v4l-utils install failed"
v4l2-ctl -d /dev/video1 --all 2>&1 | head -40
echo "== out fmts"; v4l2-ctl -d /dev/video1 --list-formats-out-ext 2>&1 | head -60
echo "== cap fmts"; v4l2-ctl -d /dev/video1 --list-formats-ext 2>&1 | head -40
echo "== ctrls"; v4l2-ctl -d /dev/video1 -L 2>&1 | head -40
echo "== vcp"; ls /sys/kernel/vcp* /sys/devices/platform/*vcp* -d 2>/dev/null; cat /sys/kernel/vcp/vcp_status 2>/dev/null
dmesg | grep -iE "vcp|vcodec|vdec" | tail -15
ls /vendor 2>&1 | head -3; ls /lib/firmware | grep -iE "vcp|vcodec" 
