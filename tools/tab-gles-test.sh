# Runs as root on the tablet: off-screen GLES2 render on the Mali GPU via libhybris (GPU port).
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
install -m755 /tmp/gles-pbuffer /usr/local/hybris/bin/gles-pbuffer 2>/dev/null
timeout 60 /usr/local/hybris/bin/gles-pbuffer 2>&1 | grep -v "not found" | cut -c1-170; echo "rc=${PIPESTATUS[0]}"
