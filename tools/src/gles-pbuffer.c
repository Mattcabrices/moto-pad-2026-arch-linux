/* GPU port smoke test: EGL pbuffer + GLES2 clear/readback through libhybris (EGL_PLATFORM=null). */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <time.h>

/* GL entry points come from eglGetProcAddress so the test needs only libEGL. */
static const GLubyte *(*pGetString)(GLenum);
static void (*pClearColor)(GLfloat, GLfloat, GLfloat, GLfloat);
static void (*pClear)(GLbitfield);
static void (*pReadPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);
static GLenum (*pGetError)(void);
#define glGetString pGetString
#define glClearColor pClearColor
#define glClear pClear
#define glReadPixels pReadPixels
#define glGetError pGetError

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    EGLDisplay d = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    EGLint maj, min, n;
    if (!eglInitialize(d, &maj, &min)) { printf("eglInitialize failed 0x%x\n", eglGetError()); return 1; }
    /* eglQueryString(EGL_VENDOR) crashes in Mali (sscanf "r%up%u" on a NULL string) - skip it. */
    printf("EGL %d.%d initialized\n", maj, min);
    const EGLint ca[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                          EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE };
    EGLConfig c;
    if (!eglChooseConfig(d, ca, &c, 1, &n) || n < 1) { printf("no config\n"); return 1; }
    const EGLint sa[] = { EGL_WIDTH, 256, EGL_HEIGHT, 256, EGL_NONE };
    EGLSurface s = eglCreatePbufferSurface(d, c, sa);
    const EGLint xa[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext x = eglCreateContext(d, c, EGL_NO_CONTEXT, xa);
    if (s == EGL_NO_SURFACE || x == EGL_NO_CONTEXT || !eglMakeCurrent(d, s, s, x)) {
        printf("surface/context failed 0x%x\n", eglGetError()); return 1;
    }
    printf("context current\n");
    pGetString = (void *)eglGetProcAddress("glGetString");
    pClearColor = (void *)eglGetProcAddress("glClearColor");
    pClear = (void *)eglGetProcAddress("glClear");
    pReadPixels = (void *)eglGetProcAddress("glReadPixels");
    pGetError = (void *)eglGetProcAddress("glGetError");
    printf("procs %p %p %p %p %p\n", (void *)pGetString, (void *)pClearColor, (void *)pClear,
           (void *)pReadPixels, (void *)pGetError);
    if (!pGetString || !pClearColor || !pClear || !pReadPixels || !pGetError) return 1;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < 200; i++) {
        glClearColor((i & 1) ? 1.f : 0.f, 0.5f, 0.25f, 1.f);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    unsigned char px[4] = {0};
    glReadPixels(128, 128, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("pixel = %d,%d,%d,%d (expect ~255,128,64,255)  200 clears+readback %.1f ms  glError=0x%x\n",
           px[0], px[1], px[2], px[3], (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6, glGetError());
    printf("GL_VENDOR=%s\nGL_RENDERER=%s\nGL_VERSION=%s\n", glGetString(GL_VENDOR), glGetString(GL_RENDERER),
           glGetString(GL_VERSION));
    eglTerminate(d);
    return 0;
}
