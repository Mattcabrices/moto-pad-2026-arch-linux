# Runs as root on the tablet: installs hardware video decoding (shim built from /tmp/mtk-v4l2-shim.c, mpv wrapper,
# dma-heap udev rule, Firefox decoder redirect and the firefox-gpu launcher that loads it; files pushed to /tmp by
# tools/push-vdec.sh).
# Undo: rm /usr/local/bin/mpv /usr/local/lib/libmtk-v4l2-shim.so /usr/local/lib/libff-v4l2-redirect.so \
#          /etc/udev/rules.d/70-archpad-dma-heap.rules   (firefox-gpu then runs Firefox without it)
set -e
pacman -Q gcc >/dev/null 2>&1 || pacman -S --noconfirm --needed gcc >/dev/null
gcc -O2 -Wall -Wno-array-bounds -shared -fPIC -o /usr/local/lib/libmtk-v4l2-shim.so /tmp/mtk-v4l2-shim.c -ldl -lpthread
# Firefox: built against the installed FFmpeg headers (rebuild after an FFmpeg major update; until then it stays off).
gcc -O2 -Wall -shared -fPIC -o /usr/local/lib/libff-v4l2-redirect.so /tmp/ff-v4l2-redirect.c -ldl -lpthread
install -m755 /tmp/mpv /usr/local/bin/mpv
[ -e /usr/local/bin/firefox-gpu ] && install -m755 /tmp/firefox-gpu /usr/local/bin/firefox-gpu
install -m644 /tmp/70-archpad-dma-heap.rules /etc/udev/rules.d/70-archpad-dma-heap.rules
udevadm control --reload
udevadm trigger --subsystem-match=dma_heap --action=add
sleep 1
ls -l /dev/dma_heap/system
# Menu entry: the wrapper (it calls hybris-run itself).
mkdir -p /usr/local/share/applications
sed 's|^Exec=mpv |Exec=/usr/local/bin/mpv |' /usr/share/applications/mpv.desktop > /usr/local/share/applications/mpv.desktop
grep -n '^Exec' /usr/local/share/applications/mpv.desktop
update-desktop-database /usr/local/share/applications 2>/dev/null || true
