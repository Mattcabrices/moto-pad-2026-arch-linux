/* GPU port: capability probe for wlroots on libhybris. Prints EGL/GL extension strings, tests a configless
 * surfaceless context (what wlroots creates) and calls GL directly through libhybris' libGLESv2 (linked). */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <string.h>

static void has(const char *all, const char *e) { printf("  %-40s %s\n", e, all && strstr(all, e) ? "yes" : "NO"); }

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    EGLDisplay d = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    EGLint ma, mi;
    if (!eglInitialize(d, &ma, &mi)) { printf("eglInitialize failed\n"); return 1; }
    const char *e = eglQueryString(d, EGL_EXTENSIONS);
    printf("EGL %d.%d extensions: %s\n", ma, mi, e);
    const char *need[] = { "EGL_KHR_image_base", "EGL_KHR_no_config_context", "EGL_MESA_configless_context",
                           "EGL_KHR_surfaceless_context", "EGL_ANDROID_image_native_buffer", "EGL_ANDROID_get_native_client_buffer",
                           "EGL_EXT_image_dma_buf_import", "EGL_KHR_fence_sync", "EGL_ANDROID_native_fence_sync",
                           "EGL_KHR_wait_sync", "EGL_IMG_context_priority", "EGL_EXT_create_context_robustness",
                           "EGL_KHR_create_context", NULL };
    for (int i = 0; need[i]; i++) has(e, need[i]);
    eglBindAPI(EGL_OPENGL_ES_API);
    const EGLint xa[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext x = eglCreateContext(d, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, xa);
    printf("configless context %p (err 0x%x)\n", x, eglGetError());
    if (x == EGL_NO_CONTEXT) return 1;
    if (!eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, x)) { printf("surfaceless makecurrent failed 0x%x\n", eglGetError()); return 1; }
    printf("surfaceless current ok\n");
    const char *g = (const char *)glGetString(GL_EXTENSIONS);
    printf("direct glGetString: %s / %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    const char *gneed[] = { "GL_EXT_texture_format_BGRA8888", "GL_EXT_unpack_subimage", "GL_EXT_read_format_bgra",
                            "GL_OES_EGL_image", "GL_OES_EGL_image_external", "GL_KHR_debug", "GL_EXT_disjoint_timer_query",
                            "GL_KHR_robustness", "GL_OES_rgb8_rgba8", NULL };
    for (int i = 0; gneed[i]; i++) has(g, gneed[i]);
    GLuint t, f; glGenTextures(1, &t); glBindTexture(GL_TEXTURE_2D, t);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glGenFramebuffers(1, &f); glBindFramebuffer(GL_FRAMEBUFFER, f);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t, 0);
    glClearColor(1, 0.5f, 0.25f, 1); glClear(GL_COLOR_BUFFER_BIT);
    unsigned char px[4]; glReadPixels(1, 1, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    printf("direct GL FBO clear: %d,%d,%d,%d glError 0x%x\n", px[0], px[1], px[2], px[3], glGetError());
    return 0;
}
