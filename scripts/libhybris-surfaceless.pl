#!/usr/bin/perl
# archpad: EGL_MESA_platform_surfaceless (and GBM) for libhybris. Chromium's GPU process (ANGLE's EGL backend) asks
# for an off-screen display and refuses to start ("Failed to get system egl display") when the client extension is
# missing. Android EGL is happy without a window system, so these platforms map to libhybris' "null" ws (pure
# passthrough); if the process already loaded another ws (e.g. wayland), that one is reused.
# Usage: perl libhybris-surfaceless.pl <libhybris>/hybris/egl/egl.c   (idempotent; upgrades a surfaceless-only tree)
use strict;
my $f = shift or die "usage: $0 egl.c\n";
open my $in, '<', $f or die "$f: $!\n"; local $/; my $s = <$in>; close $in;
exit 0 if $s =~ /archpad_gbm/;
my $exts = 'EGL_MESA_platform_surfaceless EGL_KHR_platform_gbm EGL_MESA_platform_gbm';
if ($s =~ /archpad_surfaceless/) {
  # Tree from the first version of this patch: add GBM.
  $s =~ s/ EGL_MESA_platform_surfaceless"/ $exts"/ or die "no surfaceless ext\n";
  $s =~ s/(\t\tcase 0x31DD: )/\t\tcase 0x31D7: \/* EGL_PLATFORM_GBM_KHR; archpad_gbm *\/\n$1/ or die "no surfaceless case\n";
} else {
  $s =~ s/EGL_EXT_client_extensions EGL_EXT_platform_base EGL_EXT_platform_wayland EGL_KHR_platform_wayland"/EGL_EXT_client_extensions EGL_EXT_platform_base EGL_EXT_platform_wayland EGL_KHR_platform_wayland $exts"/
    or die "no client extension string\n";
  $s =~ s/(\t\tcase EGL_PLATFORM_ANDROID_KHR:\n)/\t\tcase 0x31D7: \/* EGL_PLATFORM_GBM_KHR; archpad_gbm *\/\n\t\tcase 0x31DD: \/* EGL_PLATFORM_SURFACELESS_MESA; archpad_surfaceless *\/\n\t\t\thybris_ws = "null";\n\t\t\tif (ws_init(hybris_ws) == EGL_FALSE)\n\t\t\t\thybris_ws = _defaultEglPlatform();\n\t\t\tbreak;\n\n$1/
    or die "no android platform case\n";
}
open my $out, '>', $f or die; print $out $s; close $out;
print "surfaceless + gbm platforms applied\n";
