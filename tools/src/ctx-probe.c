/* Moto Pad (archpad): which eglCreateContext attribute sets does Mali (via libhybris) accept? Mirrors Firefox's
 * GLContextEGL::CreateGLContext attempts (ES major version 2 or 3, EXT/KHR robustness, no-config context).
 * Run: hybris-run /tmp/ctx-probe */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <stdio.h>

#ifndef EGL_CONTEXT_OPENGL_ROBUST_ACCESS
#define EGL_CONTEXT_OPENGL_ROBUST_ACCESS 0x31B2
#endif

static EGLDisplay d;

static void try(const char *name, const EGLint *a)
{
    EGLContext c = eglCreateContext(d, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, a);
    EGLint e = eglGetError();
    printf("%-42s %s (0x%x)\n", name, c != EGL_NO_CONTEXT ? "OK" : "FAILED", e);
    if (c != EGL_NO_CONTEXT)
        eglDestroyContext(d, c);
}

int main(void)
{
    d = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    eglInitialize(d, NULL, NULL);
    eglBindAPI(EGL_OPENGL_ES_API);
    for (int v = 2; v <= 3; v++) {
        char n[64];
        const EGLint plain[] = { EGL_CONTEXT_MAJOR_VERSION, v, EGL_NONE };
        snprintf(n, sizeof n, "ES%d plain", v); try(n, plain);
        const EGLint ext[] = { EGL_CONTEXT_MAJOR_VERSION, v, EGL_CONTEXT_OPENGL_ROBUST_ACCESS_EXT, EGL_TRUE,
                               EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_EXT, EGL_LOSE_CONTEXT_ON_RESET_EXT, EGL_NONE };
        snprintf(n, sizeof n, "ES%d EXT robustness + RBAB", v); try(n, ext);
        const EGLint ext2[] = { EGL_CONTEXT_MAJOR_VERSION, v,
                                EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_EXT, EGL_LOSE_CONTEXT_ON_RESET_EXT, EGL_NONE };
        snprintf(n, sizeof n, "ES%d EXT robustness (reset only)", v); try(n, ext2);
        const EGLint khr[] = { EGL_CONTEXT_MAJOR_VERSION, v, EGL_CONTEXT_OPENGL_ROBUST_ACCESS, EGL_TRUE,
                               EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY, EGL_LOSE_CONTEXT_ON_RESET, EGL_NONE };
        snprintf(n, sizeof n, "ES%d KHR robustness + RBAB", v); try(n, khr);
        const EGLint cv[] = { EGL_CONTEXT_CLIENT_VERSION, v, EGL_NONE };
        snprintf(n, sizeof n, "ES%d via CLIENT_VERSION", v); try(n, cv);
    }
    return 0;
}
