# Runs as root on the tablet: stop Xorg, run the GPU-to-screen test (tools/src/gles-drm.c), restart XFCE.
# The run is wrapped in systemd-run so the desktop comes back even if SSH drops.
install -m755 /tmp/gles-drm /usr/local/hybris/bin/gles-drm
cat > /usr/local/hybris/bin/gles-drm-run <<'EOR'
#!/bin/sh
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
systemctl stop getty@tty1; pkill -x Xorg
for i in $(seq 20); do pgrep -x Xorg >/dev/null || break; sleep 0.5; done
timeout 60 /usr/local/hybris/bin/gles-drm ${1:-15} 2>&1 | grep -v "not found"
systemctl reset-failed getty@tty1; systemctl start getty@tty1
EOR
chmod 755 /usr/local/hybris/bin/gles-drm-run
rm -f /tmp/gles-drm.log
systemd-run --unit=gles-drm-test --collect sh -c '/usr/local/hybris/bin/gles-drm-run 15 > /tmp/gles-drm.log 2>&1'
for i in $(seq 50); do sleep 2; systemctl is-active -q gles-drm-test || break; done
cut -c1-170 /tmp/gles-drm.log; sleep 8; echo "--- Xorg back:"; pgrep -a Xorg | cut -c1-60
