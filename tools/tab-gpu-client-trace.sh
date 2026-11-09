# Runs as root on the tablet: Wayland protocol trace of a GPU client (es2gears_wayland) in matt's GPU desktop.
cat > /tmp/gpu-client-trace <<'EOR'
#!/bin/bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
export LD_LIBRARY_PATH=/usr/local/hybris/lib EGL_PLATFORM=wayland
export LD_PRELOAD=/usr/local/hybris/lib/bionic-tls-pad.so
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat
export WAYLAND_DEBUG=client
timeout -s INT 8 es2gears_wayland > /tmp/gpu-client-trace.out 2>&1
echo "exit $?" >> /tmp/gpu-client-trace.out
EOR
chmod 755 /tmp/gpu-client-trace; sudo -u matt /tmp/gpu-client-trace
O=/tmp/gpu-client-trace.out
echo "lines: $(wc -l < $O)"
grep -v -E "wl_registry#2.global|linker configuration" $O | head -45 | cut -c1-170
echo "--- last lines:"; tail -12 $O | cut -c1-170
echo "--- counts:"; for m in android_wlegl create_buffer wl_surface.*attach wl_surface.*commit 'frame(' xdg_toplevel configure; do echo "$m: $(grep -c "$m" $O)"; done
