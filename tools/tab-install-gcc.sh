# Runs as root on the tablet: native compiler for small test programs.
pacman -S --noconfirm --needed gcc make pkgconf 2>&1 | tail -3; gcc --version | head -1
