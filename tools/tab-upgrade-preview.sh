# Runs as root on the tablet: syncs the package database and lists what pacman -Syu would change.
pacman -Sy >/dev/null 2>&1 && echo "db synced"
echo "--- kernel packages installed (should be none; the kernel is ours):"; pacman -Q | grep -E '^linux' | head
echo "--- upgrades:"; pacman -Qu | tee /tmp/upgrades.txt | grep -E 'labwc|wlroots|wayland|mesa|glibc|systemd|xorg-server|libinput|gtk|chromium|pipewire|networkmanager' | cut -c1-90
echo "total: $(wc -l < /tmp/upgrades.txt)"
echo "--- labwc/wlroots in the repo:"; pacman -Si labwc wlroots0.20 2>/dev/null | grep -E '^(Name|Version|Depends On)' | cut -c1-150
pacman -Si wlroots0.21 2>/dev/null | grep -E '^(Name|Version)'
echo "--- download size:"; pacman -Syup --print-format '%s' 2>/dev/null | awk '{s+=$1} END {printf "%.0f MB\n", s/1048576}'
df -h / | tail -1
