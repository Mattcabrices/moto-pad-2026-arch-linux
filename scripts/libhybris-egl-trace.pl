#!/usr/bin/perl
# archpad: optional EGL call trace in libhybris (env ARCHPAD_EGL_TRACE=1, to stderr). For finding which EGL call an
# app (Firefox WebGL 1) gives up on: display, initialize, bind, config, context, surface and failed proc lookups.
# Usage: perl libhybris-egl-trace.pl <libhybris>/hybris/egl/egl.c   (idempotent)
use strict;
my $f = shift or die "usage: $0 egl.c\n";
open my $in, '<', $f or die "$f: $!\n"; local $/; my $s = <$in>; close $in;
# Verbose part (ARCHPAD_EGL_TRACE=2): every proc lookup and query string; added separately so older trees get it too.
sub verbose {
  my $t = shift;
  return $t if $t =~ /archpad_trace_v/;
  $t =~ s/(__eglMustCastToProperFunctionPointerType eglGetProcAddress\(const char \*procname\)\n\{\n)/$1\tif (getenv("ARCHPAD_EGL_TRACE") && getenv("ARCHPAD_EGL_TRACE")[0] == '2') \/* archpad_trace_v *\/\n\t\tfprintf(stderr, "[egl-trace] eglGetProcAddress(%s)\\n", procname);\n/ or die "no eglGetProcAddress\n";
  $t =~ s/(const char \* eglQueryString\(EGLDisplay dpy, EGLint name\)\n\{\n)/$1\tif (getenv("ARCHPAD_EGL_TRACE") && getenv("ARCHPAD_EGL_TRACE")[0] == '2')\n\t\tfprintf(stderr, "[egl-trace] eglQueryString(%p, %#x)\\n", dpy, name);\n/ or die "no eglQueryString\n";
  return $t;
}
if ($s =~ /archpad_trace/) {
  my $v = verbose($s);
  if ($v ne $s) { open my $o, '>', $f or die; print $o $v; close $o; print "egl trace (verbose) applied\n"; }
  exit 0;
}
$s = verbose($s);

my $helpers = <<'C';
/* archpad: EGL call trace (ARCHPAD_EGL_TRACE=1) */
#include <stdarg.h>
#include <stdio.h>
static int archpad_trace_on = -1;
static void archpad_trace(const char *fmt, ...)
{
	if (archpad_trace_on < 0)
		archpad_trace_on = getenv("ARCHPAD_EGL_TRACE") != NULL;
	if (!archpad_trace_on)
		return;
	va_list ap;
	va_start(ap, fmt);
	fputs("[egl-trace] ", stderr);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
}
static const char *archpad_attribs(const EGLint *a)
{
	static __thread char buf[512];
	int n = 0;
	buf[0] = 0;
	for (int i = 0; a && a[i] != EGL_NONE && i < 60 && n < 480; i += 2)
		n += snprintf(buf + n, sizeof buf - n, " %#x=%#x", a[i], a[i + 1]);
	return buf;
}
/* Read Android's error for the trace, then put it back so the app still sees it. */
static EGLint archpad_peek_error(void);
C
$s =~ s/(#include "logging.h"\n)/$1$helpers/ or die "no logging.h include\n";

my $peek = <<'C';
static EGLint archpad_peek_error(void)
{
	HYBRIS_DLSYSM(egl, &_eglGetError, "eglGetError");
	EGLint e = _eglGetError();
	if (e != EGL_SUCCESS)
		__eglHybrisSetError(e);
	return e;
}

C
$s =~ s/(EGLint eglGetError\(void\)\n)/$peek$1/ or die "no eglGetError\n";

my %repl = (
  'HYBRIS_IMPLEMENT_FUNCTION5(egl, EGLBoolean, eglChooseConfig, EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *);' => <<'C',
EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attribs, EGLConfig *configs, EGLint size, EGLint *num)
{
	static EGLBoolean (*f)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *) = NULL;
	HYBRIS_DLSYSM(egl, &f, "eglChooseConfig");
	EGLBoolean r = f(dpy, attribs, configs, size, num);
	archpad_trace("eglChooseConfig(%s) size=%d -> %d num=%d err=%#x", archpad_attribs(attribs), size, r,
		num ? *num : -1, r ? 0 : archpad_peek_error());
	return r;
}
C
  'HYBRIS_IMPLEMENT_FUNCTION3(egl, EGLSurface, eglCreatePbufferSurface, EGLDisplay, EGLConfig, const EGLint *);' => <<'C',
EGLSurface eglCreatePbufferSurface(EGLDisplay dpy, EGLConfig config, const EGLint *attribs)
{
	static EGLSurface (*f)(EGLDisplay, EGLConfig, const EGLint *) = NULL;
	HYBRIS_DLSYSM(egl, &f, "eglCreatePbufferSurface");
	EGLSurface r = f(dpy, config, attribs);
	archpad_trace("eglCreatePbufferSurface(cfg=%p%s) -> %p err=%#x", config, archpad_attribs(attribs), r,
		r ? 0 : archpad_peek_error());
	return r;
}
C
  'HYBRIS_IMPLEMENT_FUNCTION1(egl, EGLBoolean, eglBindAPI, EGLenum);' => <<'C',
EGLBoolean eglBindAPI(EGLenum api)
{
	static EGLBoolean (*f)(EGLenum) = NULL;
	HYBRIS_DLSYSM(egl, &f, "eglBindAPI");
	EGLBoolean r = f(api);
	archpad_trace("eglBindAPI(%#x) -> %d err=%#x", api, r, r ? 0 : archpad_peek_error());
	return r;
}
C
  'HYBRIS_IMPLEMENT_FUNCTION4(egl, EGLBoolean, eglMakeCurrent, EGLDisplay, EGLSurface, EGLSurface, EGLContext);' => <<'C',
EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx)
{
	static EGLBoolean (*f)(EGLDisplay, EGLSurface, EGLSurface, EGLContext) = NULL;
	HYBRIS_DLSYSM(egl, &f, "eglMakeCurrent");
	EGLBoolean r = f(dpy, draw, read, ctx);
	if (!r)
		archpad_trace("eglMakeCurrent(draw=%p read=%p ctx=%p) -> 0 err=%#x", draw, read, ctx, archpad_peek_error());
	return r;
}
C
);
for my $k (keys %repl) {
  my $i = index($s, $k); die "missing: $k\n" if $i < 0;
  substr($s, $i, length $k) = $repl{$k};
}

# eglCreateContext: trace attribs and result.
$s =~ s/\treturn \(\*_eglCreateContext\)\(dpy, config, share_context, attrib_list\);\n/\tEGLContext archpad_r = (*_eglCreateContext)(dpy, config, share_context, attrib_list);\n\tarchpad_trace("eglCreateContext(cfg=%p share=%p%s) -> %p err=%#x", config, share_context, archpad_attribs(attrib_list), archpad_r, archpad_r ? 0 : archpad_peek_error());\n\treturn archpad_r;\n/ or die "no eglCreateContext return\n";
# Display requests (platform) and initialize result.
$s =~ s/(EGLDisplay __eglHybrisGetPlatformDisplayCommon\(EGLenum platform,\n\s+void \*display_id, const EGLAttrib \*attrib_list\)\n\{\n)/$1\tarchpad_trace("getPlatformDisplay(platform=%#x, native=%p)", platform, display_id);\n/ or die "no GetPlatformDisplayCommon\n";
$s =~ s/(\tEGLBoolean ret = _eglInitialize\(dpy, major, minor\);\n)/$1\tarchpad_trace("eglInitialize(%p) -> %d", dpy, ret);\n/ or die "no eglInitialize\n";
# Failed proc lookups.
$s =~ s/(\tif \(ret == NULL && _eglGetProcAddress != NULL\) \{\n\t\tret = \(\*_eglGetProcAddress\)\(procname\);\n\t\}\n)/$1\tif (ret == NULL)\n\t\tarchpad_trace("eglGetProcAddress(%s) -> NULL", procname);\n/ or die "no proc fallback\n";

open my $out, '>', $f or die; print $out $s; close $out;
print "egl trace patch applied\n";
