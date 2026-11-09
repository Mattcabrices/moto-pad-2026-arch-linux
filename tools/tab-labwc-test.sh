# Runs as root on the tablet: GPU port compositor test. Installs /tmp/wlroots-pad.tar (prefix /usr/local/pad),
# stops XFCE, runs labwc on the patched wlroots (WLR_RENDERER=hybris, WLR_BACKENDS=pad,libinput) with a foot
# terminal, screenshots it with grim (/tmp/labwc-shot.png), then restarts XFCE. All via systemd-run so the
# desktop comes back even if SSH drops. Log: /tmp/labwc-test.log. Seconds: first line of /tmp/labwc-secs (default 25).
if [ -f /tmp/wlroots-pad.tar ]; then rm -rf /usr/local/pad; tar -C / -xf /tmp/wlroots-pad.tar && rm -f /tmp/wlroots-pad.tar; fi
ls /usr/local/pad/lib/libwlroots-0.20.so || exit 1
[ -f /tmp/labwc-rc.xml ] && install -D -m644 /tmp/labwc-rc.xml /etc/xdg/labwc/rc.xml
cat > /usr/local/pad/labwc-test-run <<'EOR'
#!/bin/bash
S=$(head -1 /tmp/labwc-secs 2>/dev/null || echo 25)
CMD=$(cat /tmp/labwc-cmd 2>/dev/null || echo foot)  # startup command(s), e.g. "xfce4-panel & foot"
systemctl stop getty@tty1; pkill -x Xorg
for i in $(seq 20); do pgrep -x Xorg >/dev/null || break; sleep 0.5; done
pkill -x seatd; seatd -g video > /tmp/seatd.log 2>&1 &
sleep 1
export XDG_RUNTIME_DIR=/run/labwc-test; rm -rf $XDG_RUNTIME_DIR; mkdir -m 700 $XDG_RUNTIME_DIR
export LIBSEAT_BACKEND=seatd WLR_BACKENDS=pad,libinput WLR_RENDERER=hybris LD_LIBRARY_PATH=/usr/local/pad/lib
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
export WLR_NO_HARDWARE_CURSORS=1 PAD_DUMP=/tmp/pad-scanout.ppm; rm -f /tmp/pad-scanout.ppm
ulimit -c unlimited
if [ -f /tmp/labwc-gdb ]; then  # touch /tmp/labwc-gdb on the tablet to get a backtrace in /tmp/labwc.out
  gdb -q -batch -ex 'set pagination off' -ex run -ex bt -ex 'info registers pc lr' -ex 'info sharedlibrary' --args labwc -d -s "$CMD" > /tmp/labwc.out 2>&1 &
else
  LD_PRELOAD=$([ -f /usr/local/pad/segv-trace.so ] && echo /usr/local/pad/segv-trace.so) labwc -d -s "$CMD" > /tmp/labwc.out 2>&1 &
fi
L=$!
sleep 10
W=$(ls $XDG_RUNTIME_DIR | grep -E '^wayland-[0-9]+$' | head -1)
echo "labwc pid $L alive=$(kill -0 $L 2>/dev/null && echo yes || echo no) socket=$W"
[ -n "$W" ] && WAYLAND_DISPLAY=$W LD_LIBRARY_PATH= timeout 10 grim /tmp/labwc-shot.png && echo "screenshot ok"
[ -n "$W" ] && WAYLAND_DISPLAY=$W LD_LIBRARY_PATH= timeout 5 wlr-randr
sleep $((S > 12 ? S - 12 : 1))
kill $L 2>/dev/null; sleep 2; kill -9 $L 2>/dev/null; pkill -x foot; pkill -x xfce4-panel; pkill -x xfce4-terminal; pkill -x Xwayland; pkill -x seatd
systemctl reset-failed getty@tty1; systemctl start getty@tty1
EOR
chmod 755 /usr/local/pad/labwc-test-run
rm -f /tmp/labwc-shot.png /tmp/labwc.out
systemd-run --unit=labwc-test --collect -p LimitCORE=infinity sh -c '/usr/local/pad/labwc-test-run > /tmp/labwc-test.log 2>&1'
for i in $(seq 60); do sleep 2; systemctl is-active -q labwc-test || break; done
cat /tmp/labwc-test.log
echo "--- labwc log (filtered):"
grep -vE "not found|linker configuration" /tmp/labwc.out | grep -iE "pad:|hybris|error|fail|egl|gles|renderer|allocator|output|abort|segfault" | head -40 | cut -c1-200
echo "--- last lines:"; tail -8 /tmp/labwc.out | cut -c1-200
sleep 8; echo "--- Xorg back:"; pgrep -a Xorg | cut -c1-60
