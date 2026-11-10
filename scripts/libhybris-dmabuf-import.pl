#!/usr/bin/perl
# archpad: EGL_EXT_image_dma_buf_import for processes that load the archpad GBM library (tools/src/archpad-gbm.c,
# Chromium's GPU process). The Mali EGL cannot import dma-bufs, but every dma-buf that GBM library hands out belongs
# to an AHardwareBuffer it allocated: eglCreateImageKHR(EGL_LINUX_DMA_BUF_EXT) asks it for the buffer behind the fd
# (archpad_gbm_ahb_from_dmabuf_fd, found with dlsym) and creates the image from the Android native buffer instead.
# Processes without that library see no change (the extension is not advertised).
# Usage: perl libhybris-dmabuf-import.pl <libhybris>/hybris/egl/egl.c   (idempotent)
use strict;
my $f = shift or die "usage: $0 egl.c\n";
open my $in, '<', $f or die "$f: $!\n"; local $/; my $s = <$in>; close $in;
exit 0 if $s =~ /archpad_dmabuf/;

my $helpers = <<'C';
/* archpad_dmabuf: dma-buf import through the archpad GBM library's AHardwareBuffers. */
#ifndef EGL_LINUX_DMA_BUF_EXT
#define EGL_LINUX_DMA_BUF_EXT 0x3270
#define EGL_DMA_BUF_PLANE0_FD_EXT 0x3272
#endif
#ifndef EGL_NATIVE_BUFFER_ANDROID
#define EGL_NATIVE_BUFFER_ANDROID 0x3140
#endif
static void *(*archpad_dmabuf_lookup)(int fd);
static int archpad_dmabuf_init(void)
{
	static int done;
	if (!done) {
		archpad_dmabuf_lookup = (void *(*)(int)) dlsym(RTLD_DEFAULT, "archpad_gbm_ahb_from_dmabuf_fd");
		done = 1;
	}
	return archpad_dmabuf_lookup != NULL;
}
static EGLClientBuffer archpad_dmabuf_client_buffer(const EGLint *attrib_list)
{
	static EGLClientBuffer (*get_cb)(const void *);
	if (!archpad_dmabuf_init() || !attrib_list)
		return NULL;
	int fd = -1;
	for (const EGLint *a = attrib_list; *a != EGL_NONE; a += 2)
		if (a[0] == EGL_DMA_BUF_PLANE0_FD_EXT)
			fd = a[1];
	void *ahb = fd >= 0 ? archpad_dmabuf_lookup(fd) : NULL;
	if (!ahb) {
		fprintf(stderr, "libhybris: dma-buf fd %d is not an archpad GBM buffer\n", fd);
		return NULL;
	}
	if (!get_cb)
		get_cb = (EGLClientBuffer (*)(const void *)) eglGetProcAddress("eglGetNativeClientBufferANDROID");
	return get_cb ? get_cb(ahb) : NULL;
}

C
$s =~ s/(static EGLImageKHR _my_eglCreateImageKHR\()/$helpers$1/ or die "no _my_eglCreateImageKHR\n";

my $create = <<'C';
	static const EGLint archpad_attribs[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
	if (target == EGL_LINUX_DMA_BUF_EXT) {
		newbuffer = archpad_dmabuf_client_buffer(attrib_list);
		if (!newbuffer)
			return EGL_NO_IMAGE_KHR;
		newctx = EGL_NO_CONTEXT;
		newtarget = EGL_NATIVE_BUFFER_ANDROID;
		newattrib_list = archpad_attribs;
	} else
C
$s =~ s/(\tconst EGLint \*newattrib_list = attrib_list;\n\n)(\tws_passthroughImageKHR)/$1$create$2/ or die "no passthrough\n";

my $query = <<'C';
	if (dpy != EGL_NO_DISPLAY && name == EGL_EXTENSIONS && archpad_dmabuf_init()) {
		static char archpad_exts[4096];
		const char *base = ws_eglQueryString(dpy, name, _eglQueryString);
		if (!base)
			return base;
		snprintf(archpad_exts, sizeof(archpad_exts), "%s EGL_EXT_image_dma_buf_import", base);
		return archpad_exts;
	}

C
$s =~ s/(\n\treturn ws_eglQueryString\(dpy, name, _eglQueryString\);\n)/\n$query$1/ or die "no ws_eglQueryString\n";
# archpad_dmabuf_init is defined further down; declare it before eglQueryString.
$s =~ s/(const char \* eglQueryString\(EGLDisplay dpy, EGLint name\)\n)/static int archpad_dmabuf_init(void);\n$1/ or die "no eglQueryString\n";
$s = "#define _GNU_SOURCE 1\n" . $s unless $s =~ /^#define _GNU_SOURCE/m;
$s =~ s/(#include <dlfcn.h>)/$1/ or $s = "#include <dlfcn.h>\n" . $s;
$s =~ /#include <stdio.h>/ or $s = "#include <stdio.h>\n" . $s;
open my $out, '>', $f or die; print $out $s; close $out;
print "dma-buf import applied\n";
