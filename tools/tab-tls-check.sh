# Runs on the tablet: static TLS segment of executables we run through hybris-run.
for f in /usr/lib/firefox/firefox /usr/bin/mpv /usr/bin/glmark2-es2-wayland /usr/bin/gtk4-demo /usr/bin/es2gears_wayland /usr/bin/labwc; do
  printf "%-34s %s
" "$f" "$(readelf -lW $f | grep TLS | awk "{print \"memsz\", \$6, \"align\", \$NF}")"
done
