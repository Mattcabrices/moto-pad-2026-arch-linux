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
EndSection
EOF
sync
rm -f /tmp/xz.log
install -Dm755 /tmp/noplanes.so /usr/local/lib/noplanes.so
LD_PRELOAD=/usr/local/lib/noplanes.so nohup timeout 20 /usr/lib/Xorg :1 vt2 -keeptty -nolisten tcp -logfile /tmp/xz.log >/tmp/xz.out 2>&1 &
sleep 12
echo "--- Xorg running?"; pgrep -a Xorg || echo "not running"
echo "--- log"; grep -E "\(EE\)|crtcs needed|ZaphodHeads|Output DSI|Output DP|Virtual size|Modeline \"1600|FatalError" /tmp/xz.log | head -20
