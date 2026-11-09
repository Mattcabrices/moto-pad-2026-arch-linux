pacman -Q labwc seatd xorg-xwayland foot grim wlr-randr wlroots0.20 2>&1 | cut -c1-80; timeout 8 curl -sI https://mirror.archlinuxarm.org >/dev/null && echo NET_OK || echo NET_DOWN; df -h / | tail -1
