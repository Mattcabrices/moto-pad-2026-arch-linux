# Runs as root on the tablet: unpacks a pushed /tmp/libhybris.tar (running apps keep the old copy until restarted).
set -e
tar -C / -xf /tmp/libhybris.tar && rm /tmp/libhybris.tar && echo "libhybris installed"
rm -f /etc/ld.so.conf.d/hybris.conf; ldconfig
grep -c ARCHPAD_EGL_TRACE /usr/local/hybris/lib/libEGL.so.1 || true
