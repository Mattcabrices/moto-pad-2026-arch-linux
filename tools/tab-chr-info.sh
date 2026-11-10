# Runs on the tablet: Chromium binary facts relevant to libhybris (TLS segment, libEGL lookup).
pacman -Q chromium
readelf -lW /usr/lib/chromium/chromium | grep -E 'TLS|LOAD' | head
ls /usr/lib/chromium/ | grep -iE 'egl|gles|angle|vk|swiftshader'
