# Runs as root on the tablet: what the Mali blob passes to sscanf when a GPU Wayland client crashes.
cat > /tmp/gpu-client-gdb2 <<'EOR'
#!/bin/bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
export LD_LIBRARY_PATH=/usr/local/hybris/lib EGL_PLATFORM=wayland
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat
timeout 60 gdb -q -batch -ex run -ex 'x/12i $pc-24' -ex 'info registers' -ex 'p/x $tpidr_el0' -ex 'x/8gx $tpidr_el0' -ex 'info threads' \
  --args es2gears_wayland > /tmp/gpu-client-gdb2.out 2>&1
EOR
chmod 755 /tmp/gpu-client-gdb2; sudo -u matt /tmp/gpu-client-gdb2
sed -n '/^Program received/,$p' /tmp/gpu-client-gdb2.out | head -60 | cut -c1-120
