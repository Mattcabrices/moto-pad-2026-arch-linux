#!/usr/bin/perl
# archpad: wires scripts/libhybris-gralloc-ahb.c (AHardwareBuffer gralloc backend) into a libhybris tree.
# Usage: libhybris-archpad-gralloc.pl <libhybris/hybris dir>. Idempotent; dies if an expected spot is missing.
use strict; use warnings;
my $H = shift or die "usage: $0 <hybris dir>\n";
sub slurp { local $/; open my $f, '<', $_[0] or die "$_[0]: $!"; <$f> }
sub spit { open my $f, '>', $_[0] or die "$_[0]: $!"; print $f $_[1]; }
sub patch {
    my ($file, $old, $new) = @_;
    my $s = slurp($file);
    return if index($s, $new) >= 0;
    my $i = index($s, $old);
    die "$file: pattern not found: $old\n" if $i < 0;
    substr($s, $i, length $old) = $new;
    spit($file, $s);
}
my $src = $0; $src =~ s{[^/]+$}{libhybris-gralloc-ahb.c};
spit("$H/gralloc/archpad-gralloc-ahb.c", "#include <unistd.h>\n" . slurp($src));
my $g = "$H/gralloc/gralloc.c";
patch($g, "void hybris_gralloc_deinitialize(void);\n",
      "void hybris_gralloc_deinitialize(void);\n#include \"archpad-gralloc-ahb.c\" /* archpad */\n");
my %entry = (
  "void hybris_gralloc_initialize(int framebuffer)\n{\n" =>
      "    if (version == -1 && archpad_ahb_init()) { version = 3; return; } /* archpad */\n",
  "int hybris_gralloc_release(buffer_handle_t handle, int was_allocated)\n{\n" =>
      "    if (version == 3) return archpad_ahb_release(handle); /* archpad */\n",
  "int hybris_gralloc_import_buffer(buffer_handle_t raw_handle, buffer_handle_t* out_handle)\n{\n" =>
      "    if (version == 3) return archpad_ahb_import(raw_handle, out_handle); /* archpad */\n",
  "int hybris_gralloc_retain(buffer_handle_t handle)\n{\n" =>
      "    if (version == 3) return archpad_ahb_retain(handle); /* archpad */\n",
  "int hybris_gralloc_allocate(int width, int height, int format, int usage, buffer_handle_t *handle_ptr, uint32_t *stride_ptr)\n{\n" =>
      "    if (version == 3) return archpad_ahb_allocate(width, height, format, usage, handle_ptr, stride_ptr); /* archpad */\n",
  "int hybris_gralloc_lock(buffer_handle_t handle, int usage, int l, int t, int w, int h, void **vaddr)\n{\n" =>
      "    if (version == 3) return archpad_ahb_lock_buf(handle, usage, l, t, w, h, vaddr); /* archpad */\n",
  "int hybris_gralloc_unlock(buffer_handle_t handle)\n{\n" =>
      "    if (version == 3) return archpad_ahb_unlock_buf(handle); /* archpad */\n",
);
patch($g, $_, $_ . $entry{$_}) for sort keys %entry;
patch("$H/include/hybris/gralloc/gralloc.h",
      "int hybris_gralloc_import_buffer(buffer_handle_t raw_handle, buffer_handle_t* out_handle);\n",
      "int hybris_gralloc_import_buffer(buffer_handle_t raw_handle, buffer_handle_t* out_handle);\n"
    . "/* archpad: import with a description (needed by the AHardwareBuffer backend). */\n"
    . "int hybris_gralloc_import_buffer_desc(buffer_handle_t raw_handle, int width, int height, int stride, int format, uint64_t usage, buffer_handle_t *out_handle);\n");
patch("$H/platforms/wayland/wayland_window_common.cpp",
      "    int ret = hybris_gralloc_import_buffer(native, &wsb->handle);\n",
      "    int ret = hybris_gralloc_import_buffer_desc(native, wsb->width, wsb->height, stride, format, wsb->usage, &wsb->handle); /* archpad */\n");
patch("$H/platforms/common/server_wlegl_buffer.cpp",
      "\tret = hybris_gralloc_import_buffer(handle, &out_handle);\n",
      "\tret = hybris_gralloc_import_buffer_desc(handle, width, height, stride, format, usage, &out_handle); /* archpad */\n");
my $n = () = slurp($g) =~ /archpad/g;
print "archpad gralloc backend wired in ($n marks in gralloc.c)\n";
