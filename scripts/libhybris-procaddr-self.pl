#!/usr/bin/perl
# archpad: eglGetProcAddress("eglGetPlatformDisplay") etc. used to return Android's own EGL functions, which bypass
# libhybris' display/window-system wrappers. ANGLE (Chromium) loads every EGL entry point that way. Now any egl*
# name that libhybris' libEGL itself exports resolves to libhybris' function first.
# Usage: perl libhybris-procaddr-self.pl <libhybris>/hybris/egl/egl.c   (idempotent)
use strict;
my $f = shift or die "usage: $0 egl.c\n";
open my $in, '<', $f or die "$f: $!\n"; local $/; my $s = <$in>; close $in;
exit 0 if $s =~ /archpad_self/;
my $code = <<'C';
	/* archpad_self: prefer libhybris' own exported egl* functions over Android's. */
	if (procname && strncmp(procname, "egl", 3) == 0) {
		static void *archpad_self;
		if (!archpad_self) {
			Dl_info info;
			if (dladdr((void *) eglGetProcAddress, &info) && info.dli_fname)
				archpad_self = dlopen(info.dli_fname, RTLD_LAZY | RTLD_NOLOAD);
		}
		void *own = archpad_self ? dlsym(archpad_self, procname) : NULL;
		if (own)
			return (__eglMustCastToProperFunctionPointerType) own;
	}

C
$s =~ s/(\tif \(result\)\n\t\treturn result->func;\n\n)/$1$code/ or die "no override lookup\n";
$s = "#define _GNU_SOURCE 1\n" . $s unless $s =~ /^#define _GNU_SOURCE/m;
open my $out, '>', $f or die; print $out $s; close $out;
print "self proc lookup applied\n";
