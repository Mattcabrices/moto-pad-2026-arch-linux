pacman -Q strace >/dev/null 2>&1 || pacman -S --noconfirm --needed strace >/dev/null 2>&1; pacman -Q strace
