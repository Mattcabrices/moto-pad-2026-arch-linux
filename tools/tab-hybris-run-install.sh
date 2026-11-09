install -m755 /tmp/hybris-run /usr/local/bin/hybris-run && ls -la /usr/local/bin/hybris-run
sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 timeout -s INT 4 hybris-run es2gears_wayland >/dev/null 2>&1; echo "es2gears via hybris-run exit: $? (124 = ran until stopped)"
