# Runs as root on the tablet: GPU capability probe for the wlroots port (tools/src/gl-caps.c). Off-screen.
install -m755 /tmp/gl-caps /usr/local/hybris/bin/gl-caps
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
timeout 30 /usr/local/hybris/bin/gl-caps 2>&1 | grep -vE "not found|^[EWI] " | cut -c1-2000; echo "rc=${PIPESTATUS[0]}"
