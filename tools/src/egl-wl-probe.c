/* Moto Pad (archpad): repeats mpv's Wayland EGL start-up (video/out/opengl/context_wayland.c + egl_helpers.c)
 * step by step and prints each result, to see where an app gives up under libhybris.
 * Run inside the GPU desktop: hybris-run /usr/local/bin/egl-wl-probe */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    struct wl_display *wl = wl_display_connect(NULL);
    printf("wl_display_connect: %p\n", (void *)wl);
    const char *exts = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
    printf("client extensions: %s\n", exts ? exts : "(null)");
    printf("has EGL_EXT_platform_wayland: %d\n", exts && strstr(exts, "EGL_EXT_platform_wayland") != NULL);
    const char *ver = eglQueryString(EGL_NO_DISPLAY, EGL_VERSION);
    printf("client EGL_VERSION: %s (error 0x%x)\n", ver ? ver : "(null)", eglGetError());
    void *gpd = (void *)eglGetProcAddress("eglGetPlatformDisplay");
    void *gpdx = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
    printf("eglGetProcAddress: eglGetPlatformDisplay %p, eglGetPlatformDisplayEXT %p\n", gpd, gpdx);
    EGLDisplay d = EGL_NO_DISPLAY;
    if (gpdx) {
        d = ((PFNEGLGETPLATFORMDISPLAYEXTPROC)gpdx)(EGL_PLATFORM_WAYLAND_EXT, wl, NULL);
        printf("eglGetPlatformDisplayEXT(WAYLAND): %p (error 0x%x)\n", d, eglGetError());
    }
    EGLint maj = 0, min = 0;
    EGLBoolean ok = eglInitialize(d, &maj, &min);
    printf("eglInitialize: %d %d.%d (error 0x%x)\n", ok, maj, min, eglGetError());
    if (!ok)
        return 1;
    /* mpv: GLES first if desktop GL is unavailable */
    printf("eglBindAPI(OPENGL): %d; eglBindAPI(ES): %d\n", eglBindAPI(EGL_OPENGL_API), eglBindAPI(EGL_OPENGL_ES_API));
    const EGLint ca[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
                          EGL_ALPHA_SIZE, 0, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE };
    EGLConfig cfg[64]; EGLint n = 0;
    ok = eglChooseConfig(d, ca, cfg, 64, &n);
    printf("eglChooseConfig(ES2, window, rgb8): %d, %d configs (error 0x%x)\n", ok, n, eglGetError());
    const EGLint xa3[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
    EGLContext c = eglCreateContext(d, n ? cfg[0] : NULL, EGL_NO_CONTEXT, xa3);
    printf("eglCreateContext(ES3 via MAJOR_VERSION): %p (error 0x%x)\n", c, eglGetError());
    return 0;
}
