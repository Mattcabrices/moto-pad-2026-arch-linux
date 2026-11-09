#!/usr/bin/perl
# archpad: Firefox's WebGL 1 path passes context attribute 0x3483 = 0 to eglCreateContext. The Android Mali EGL does
# not know it and rejects every such context with EGL_BAD_ATTRIBUTE, so WebGL 1 never starts (WebGL 2 does not send
# it). Value 0 is the default, so libhybris drops the pair before calling Mali. Found with ARCHPAD_EGL_TRACE.
# Usage: perl libhybris-ctx-attribs.pl <libhybris>/hybris/egl/egl.c   (idempotent)
use strict;
my $f = shift or die "usage: $0 egl.c\n";
open my $in, '<', $f or die "$f: $!\n"; local $/; my $s = <$in>; close $in;
exit 0 if $s =~ /archpad_ctx_attribs/;
my $code = <<'C';
	/* archpad_ctx_attribs: drop attributes Mali rejects although they only restate the default. */
	EGLint archpad_attr[128];
	if (attrib_list) {
		int n = 0;
		for (const EGLint *q = attrib_list; *q != EGL_NONE && n < 124; q += 2) {
			if (q[0] == 0x3483 && q[1] == 0)
				continue;
			archpad_attr[n++] = q[0];
			archpad_attr[n++] = q[1];
		}
		archpad_attr[n] = EGL_NONE;
		attrib_list = archpad_attr;
	}

C
$s =~ s/(\tHYBRIS_DLSYSM\(egl, &_eglCreateContext, "eglCreateContext"\);\n\n)/$1$code/ or die "no eglCreateContext\n";
open my $out, '>', $f or die; print $out $s; close $out;
print "context attribute filter applied\n";
