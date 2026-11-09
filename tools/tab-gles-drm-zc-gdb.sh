# Runs as root on the tablet: stop Xorg, run the zero-copy GPU-to-screen test (tools/src/gles-drm-zc.c), restart XFCE.
# The run is wrapped in systemd-run so the desktop comes back even if SSH drops.
install -m755 /tmp/gles-drm-zc /usr/local/hybris/bin/gles-drm-zc
cat > /usr/local/hybris/bin/gles-drm-zc-run <<'EOR'
#!/bin/bash
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
systemctl stop getty@tty1; pkill -x Xorg
for i in $(seq 20); do pgrep -x Xorg >/dev/null || break; sleep 0.5; done
timeout 90 gdb -q -batch -ex 'set pagination off' -ex run -ex 'p/x $pc' -ex 'p/x $lr' -ex 'info symbol $pc' -ex 'info symbol $lr' -ex 'x/6i $pc-12' -ex 'p/x $x0' -ex 'p/x $x8' -ex 'set $f=$x29' -ex 'p/x *(long*)($f+8)' -ex 'set $f=*(long*)$f' -ex 'p/x *(long*)($f+8)' -ex 'set $f=*(long*)$f' -ex 'p/x *(long*)($f+8)' -ex 'set $f=*(long*)$f' -ex 'p/x *(long*)($f+8)' -ex 'info proc mappings' --args /usr/local/hybris/bin/gles-drm-zc 3 2>&1 | grep -vE 'not found|New Thread|exited|fd\[' | grep -E '^\$[0-9]|SIG|ok|glError|client|rror|Cannot|in section|No symbol|=>|^   0x|r-xp .*(mali|EGL|GLES|hybris|gles-drm)'
systemctl reset-failed getty@tty1; systemctl start getty@tty1
EOR
chmod 755 /usr/local/hybris/bin/gles-drm-zc-run
rm -f /tmp/gles-drm-zc.log
systemd-run --unit=gles-drm-zc-gdb --collect sh -c '/usr/local/hybris/bin/gles-drm-zc-run 15 > /tmp/gles-drm-zc.log 2>&1'
for i in $(seq 50); do sleep 2; systemctl is-active -q gles-drm-zc-gdb || break; done
cut -c1-170 /tmp/gles-drm-zc.log; sleep 8; echo "--- Xorg back:"; pgrep -a Xorg | cut -c1-60
