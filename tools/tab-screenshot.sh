# Runs as root on the tablet: take a screenshot of the X display to /tmp/screen.xwd.
pacman -Q xorg-xwd >/dev/null 2>&1 || pacman -S --noconfirm --needed xorg-xwd >/dev/null 2>&1
sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority xwd -root -silent -out /tmp/screen.xwd
chmod 644 /tmp/screen.xwd; ls -la /tmp/screen.xwd
