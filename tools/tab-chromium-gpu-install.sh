# Runs as root on the tablet: installs chromium-gpu (pushed to /tmp) and a chromium.desktop override that uses it.
# Undo: rm /usr/local/share/applications/chromium.desktop
set -e
install -m755 /tmp/chromium-gpu /usr/local/bin/chromium-gpu
mkdir -p /usr/local/share/applications
sed -E 's#^Exec=(/usr/bin/)?chromium( |$)#Exec=/usr/local/bin/chromium-gpu\2#' /usr/share/applications/chromium.desktop > /usr/local/share/applications/chromium.desktop
grep -n '^Exec' /usr/local/share/applications/chromium.desktop
update-desktop-database /usr/local/share/applications 2>/dev/null || true
which hybris-run
