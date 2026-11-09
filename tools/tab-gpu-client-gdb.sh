# Runs as root on the tablet: backtrace of a GPU Wayland client (es2gears_wayland) crashing under libhybris.
cat > /tmp/gpu-client-gdb <<'EOR'
#!/bin/bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
export LD_LIBRARY_PATH=/usr/local/hybris/lib EGL_PLATFORM=wayland
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat
export WAYLAND_DEBUG=client
timeout 60 gdb -q -batch -ex run -ex bt -ex 'info sharedlibrary' --args es2gears_wayland 2>&1 | grep -v -E "linker configuration|^\[New Thread|^\[Thread" > /tmp/gpu-client-gdb.out
EOR
chmod 755 /tmp/gpu-client-gdb; sudo -u matt /tmp/gpu-client-gdb
grep -E "^#|SIGSEGV|signal" /tmp/gpu-client-gdb.out | head -25 | cut -c1-200
echo "--- wayland requests before the crash:"; grep -E "^\[" /tmp/gpu-client-gdb.out | tail -12 | cut -c1-160
echo "--- libs:"; grep -E "EGL|GLES|wayland|hybris" /tmp/gpu-client-gdb.out | grep -v "^\[" | awk '{print $NF}' | sort -u | head -12
