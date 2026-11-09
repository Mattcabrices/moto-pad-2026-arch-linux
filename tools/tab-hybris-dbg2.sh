export HYBRIS_LD_DEBUG=0 LD_LIBRARY_PATH=/usr/local/hybris/lib HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
B=/usr/local/hybris/bin; mkdir -p /tmp/sw
cp $B/gles-pbuffer /tmp/sw/test_egl_configs; cp $B/test_egl_configs /tmp/sw/gles-pbuffer
echo "== pbuffer code named test_egl_configs"; timeout 60 /tmp/sw/test_egl_configs 2>&1 | grep -v "not found"; echo "rc=${PIPESTATUS[0]}"
echo "== configs code named gles-pbuffer"; timeout 60 /tmp/sw/gles-pbuffer > /tmp/c.txt 2>&1; echo "rc=$? lines=$(wc -l < /tmp/c.txt)"
