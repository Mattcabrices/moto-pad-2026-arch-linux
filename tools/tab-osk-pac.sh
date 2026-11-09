pacman -Sy >/dev/null 2>&1; pacman -Qu | cut -c1-70
pacman -Su --noconfirm --ignore labwc,wlroots0.20 2>&1 | grep -E "archpad|error|upgrading" | tail -15
pacman -S --noconfirm --needed squeekboard 2>&1 | tail -2
pacman -Q squeekboard labwc wlroots0.20
