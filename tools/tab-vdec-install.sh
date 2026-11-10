# Runs as root on the tablet: installs hardware video decoding (shim built from /tmp/mtk-v4l2-shim.c, mpv wrapper,
# dma-heap udev rule; files pushed to /tmp by tools/push-vdec.sh).
# Undo: rm /usr/local/bin/mpv /usr/local/lib/libmtk-v4l2-shim.so /etc/udev/rules.d/70-archpad-dma-heap.rules
set -e
pacman -Q gcc >/dev/null 2>&1 || pacman -S --noconfirm --needed gcc >/dev/null
gcc -O2 -Wall -Wno-array-bounds -shared -fPIC -o /usr/local/lib/libmtk-v4l2-shim.so /tmp/mtk-v4l2-shim.c -ldl -lpthread
install -m755 /tmp/mpv /usr/local/bin/mpv
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
