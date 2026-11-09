# Runs as root on the tablet: list R/D-state processes from /proc/*/stat only (ps can block on D-state tasks).
for s in /proc/[0-9]*/stat; do
  read -r l < "$s" 2>/dev/null || continue
  st=$(echo "$l" | sed 's/.*) //' | cut -d' ' -f1)
  case $st in R|D) echo "$st $l" | cut -c1-90;; esac
done
cat /proc/pressure/cpu 2>/dev/null
