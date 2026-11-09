# Runs as root on the tablet: installs GPU Firefox (pushed to /tmp by tools/push-firefox-gpu.sh):
# firefox-hybris builder + pacman hook, AutoConfig GPU prefs, the firefox-gpu launcher and a firefox.desktop
# override that uses it. Undo: rm /usr/local/share/applications/firefox.desktop (menu goes back to plain Firefox).
set -e
L=/usr/local/lib/archpad
install -D -m755 /tmp/tab-ff-tls-scan.sh $L/tab-ff-tls-scan.sh
install -D -m755 /tmp/ff-tls-relocate.py $L/ff-tls-relocate.py
install -D -m755 /tmp/firefox-hybris-update $L/firefox-hybris-update
install -D -m644 /tmp/archpad-firefox-hybris.hook /etc/pacman.d/hooks/archpad-firefox-hybris.hook
install -D -m755 /tmp/firefox-gpu /usr/local/bin/firefox-gpu
# AutoConfig: GPU prefs only under firefox-gpu (ARCHPAD_GPU=1).
install -m644 /tmp/archpad.cfg /usr/lib/firefox/archpad.cfg
printf '// Moto Pad (archpad): load archpad.cfg (GPU prefs under firefox-gpu)\npref("general.config.filename", "archpad.cfg");\npref("general.config.obscure_value", 0);\npref("general.config.sandbox_enabled", false);\n' \
  > /usr/lib/firefox/defaults/pref/archpad-autoconfig.js
$L/firefox-hybris-update
# Menu entry: same as Firefox's, but through firefox-gpu.
mkdir -p /usr/local/share/applications
sed -E 's#^Exec=(/usr/lib/firefox/firefox|firefox)( |$)#Exec=/usr/local/bin/firefox-gpu\2#' /usr/share/applications/firefox.desktop \
  > /usr/local/share/applications/firefox.desktop
grep -n '^Exec' /usr/local/share/applications/firefox.desktop
update-desktop-database /usr/local/share/applications 2>/dev/null || true
ls -la /usr/lib/firefox/firefox-hybris
