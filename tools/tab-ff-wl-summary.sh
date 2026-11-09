# Runs on the tablet: GPU-buffer related lines of Firefox's Wayland trace (/tmp/ff-wl.log), in order.
L=/tmp/ff-wl.log
grep -n -E 'get_server_buffer_handle|android_wlegl_server_buffer_handle#[0-9]+\.buffer|\.attach\(|wl_buffer#[0-9]+\.release|\.frame\(|wl_callback#[0-9]+\.done|set_desync|get_subsurface|damage_buffer' $L | cut -c1-170 | tail -45
echo "--- last 8 lines:"; tail -8 $L | cut -c1-170
