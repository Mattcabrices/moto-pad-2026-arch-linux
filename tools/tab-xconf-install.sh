# Runs as root on the tablet: limit Xorg to the built-in DSI panel, then test for 20 s.
cat > /etc/X11/xorg.conf.d/10-pad.conf <<'EOF'
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection
Section "Device"
    Identifier "pad"
    Driver "modesetting"
    Option "kmsdev" "/dev/dri/card0"
    Option "AccelMethod" "none"
    Option "ShadowFB" "true"
    # The legacy hardware cursor oopses mediatek-drm; the shim no-ops it and X draws its own.
    Option "SWcursor" "true"
    # Nothing is attached to the USB-C DisplayPort output, but it reports "connected" and
    # driving its CRTC oopses mediatek-drm. Ignore it.
    Option "Monitor-DP-1" "dp-ignored"
EndSection
Section "Monitor"
    Identifier "dp-ignored"
    Option "Ignore" "true"
EndSection
EOF
sync
rm -f /tmp/xz.log
install -Dm755 /tmp/noplanes.so /usr/local/lib/noplanes.so
echo INSTALLED
