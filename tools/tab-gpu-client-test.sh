# Runs as root on the tablet: installs the rebuilt libhybris + wlroots-pad (pushed to /tmp), restarts matt's GPU
# desktop, then runs a GPU-rendered Wayland client (es2gears_wayland via libhybris EGL) inside it.
set -u
NEW=
[ -s /tmp/libhybris.tar ] && { tar -C / -xf /tmp/libhybris.tar && rm /tmp/libhybris.tar && echo "libhybris installed"; NEW=1; }
[ -s /tmp/wlroots-pad.tar ] && { tar -C / -xf /tmp/wlroots-pad.tar && rm /tmp/wlroots-pad.tar && echo "wlroots-pad installed"; NEW=1; }
[ -s /tmp/bionic-tls-pad.so ] && install -m755 /tmp/bionic-tls-pad.so /usr/local/hybris/lib/bionic-tls-pad.so
rm -f /etc/ld.so.conf.d/hybris.conf; ldconfig   # never put hybris on the global path (Xorg would load its libEGL)
command -v es2gears_wayland >/dev/null || pacman -S --noconfirm --needed mesa-utils >/dev/null 2>&1
command -v es2gears_wayland || { echo "es2gears_wayland not available"; exit 1; }
# Restart the session so labwc loads the new wlroots.
[ -n "$NEW" ] && { systemctl stop getty@tty1; pkill -u matt -x labwc; sleep 2; systemctl reset-failed getty@tty1; systemctl start getty@tty1; }
for i in $(seq 30); do sleep 1; ls /run/user/1000/wayland-0 >/dev/null 2>&1 && pgrep -u matt -x xfce4-panel >/dev/null && break; done
sleep 4
echo "labwc: $(pgrep -u matt -x labwc)"; grep -E "hybris" /home/matt/.pad-wayland-labwc.log | head -5 | cut -c1-150
cat > /tmp/gpu-client-run <<'EOR'
#!/bin/bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
export LD_LIBRARY_PATH=/usr/local/hybris/lib EGL_PLATFORM=wayland
export LD_PRELOAD=/usr/local/hybris/lib/bionic-tls-pad.so  # see tools/src/bionic-tls-pad.c
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat
timeout -s INT 14 es2gears_wayland > /tmp/gpu-client.out 2>&1 &
sleep 9
timeout 10 grim /tmp/gpu-client-shot.png
wait
EOR
chmod 755 /tmp/gpu-client-run; rm -f /tmp/gpu-client-shot.png
sudo -u matt /tmp/gpu-client-run
echo "--- client output:"; grep -v "linker configuration" /tmp/gpu-client.out | tail -12 | cut -c1-160
echo "--- compositor:"; grep -E "ERROR|hybris|Unknown buffer" /home/matt/.pad-wayland-labwc.log | tail -8 | cut -c1-160
echo "labwc still running: $(pgrep -u matt -x labwc)"; ls -la /tmp/gpu-client-shot.png 2>&1
