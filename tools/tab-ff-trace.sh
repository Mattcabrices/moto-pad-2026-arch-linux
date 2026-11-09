# Runs on the tablet: summary of the libhybris EGL trace from Firefox (/tmp/ff-trace.log).
grep -n 'egl-trace\|WebGL\|webgl\|FEATURE_FAIL' /tmp/ff-trace.log | cut -c1-260 | head -80
