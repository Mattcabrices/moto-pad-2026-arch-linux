# Runs as root on the tablet (internet through the PC): full update, then Chromium and Onboard.
set -o pipefail
pacman-key --populate archlinuxarm >/dev/null 2>&1
pacman -Syu --noconfirm --needed chromium onboard 2>&1 | grep -vE "^ *(checking|loading|resolving|looking|:: Proceed)|downloading|^\s*$" | tail -25
echo "PACMAN_EXIT=$?"
pacman -Q chromium onboard
df -h / | tail -1
