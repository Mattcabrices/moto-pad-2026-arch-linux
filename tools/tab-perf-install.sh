# Runs as root on the tablet: perf for profiling.
pacman -Q perf >/dev/null 2>&1 || pacman -S --noconfirm --needed perf >/dev/null 2>&1; perf --version; cat /proc/sys/kernel/perf_event_paranoid
echo -1 > /proc/sys/kernel/perf_event_paranoid; echo 0 > /proc/sys/kernel/kptr_restrict
