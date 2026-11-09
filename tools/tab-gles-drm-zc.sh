# Runs as root on the tablet: stop Xorg, run the zero-copy GPU-to-screen test (tools/src/gles-drm-zc.c), restart XFCE.
# The run is wrapped in systemd-run so the desktop comes back even if SSH drops.
install -m755 /tmp/gles-drm-zc /usr/local/hybris/bin/gles-drm-zc
cat > /usr/local/hybris/bin/gles-drm-zc-run <<'EOR'
#!/bin/bash
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
systemctl stop getty@tty1; pkill -x Xorg
for i in $(seq 20); do pgrep -x Xorg >/dev/null || break; sleep 0.5; done
timeout 60 /usr/local/hybris/bin/gles-drm-zc ${1:-15} 2>&1 | grep -v "not found" ; echo "rc=${PIPESTATUS[0]}"
systemctl reset-failed getty@tty1; systemctl start getty@tty1
EOR
chmod 755 /usr/local/hybris/bin/gles-drm-zc-run
rm -f /tmp/gles-drm-zc.log
systemd-run --unit=gles-drm-zc-test --collect sh -c '/usr/local/hybris/bin/gles-drm-zc-run 15 > /tmp/gles-drm-zc.log 2>&1'
for i in $(seq 50); do sleep 2; systemctl is-active -q gles-drm-zc-test || break; done
cut -c1-170 /tmp/gles-drm-zc.log; sleep 8; echo "--- Xorg back:"; pgrep -a Xorg | cut -c1-60
