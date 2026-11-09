install -Dm755 /tmp/pad-rotate /usr/local/bin/pad-rotate
printf "[Desktop Entry]
Type=Application
Name=Landscape rotation
Exec=/usr/local/bin/pad-rotate
X-XFCE-Autostart-Override=true
" > /etc/xdg/autostart/pad-rotate.desktop
cat /etc/xdg/autostart/pad-rotate.desktop | head -3
