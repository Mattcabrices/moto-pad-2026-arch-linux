/* Moto Pad (archpad): which bytes after the thread pointer does Android's GL stack (via libhybris) write?
 * The executable's own TLS block sits at tp+16 (aarch64 TLS variant I), like Firefox's. Fill it with 0xAA, run
 * EGL (surfaceless context, make current, draw, unbind) on the main thread and on a second thread, and print the
 * offsets (relative to tp) that changed. Run: hybris-run /tmp/tls-probe  (no LD_PRELOAD pad needed or wanted). */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#define N 512
static __thread unsigned char probe[N] __attribute__((aligned(16)));

static void report(const char *who)
{
    unsigned char *tp = __builtin_thread_pointer();
    long base = (long)(probe - tp);
    printf("%s: probe at tp+%ld; changed bytes:", who, base);
    int any = 0;
    for (int i = 0; i < N; i += 8) {
        int ch = 0;
        for (int k = 0; k < 8; k++)
            ch |= probe[i + k] != 0xAA;
        if (ch) {
            unsigned long v;
            memcpy(&v, probe + i, 8);
            printf(" [tp+%ld]=%#lx", base + i, v);
            any = 1;
        }
    }
    printf("%s\n", any ? "" : " none");
}

static EGLDisplay d;
static EGLContext ctx;

static void gl_work(const char *who, int bind)
{
    memset(probe, 0xAA, N);
    if (bind && !eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx))
        printf("%s: eglMakeCurrent failed 0x%x\n", who, eglGetError());
    report(bind ? "after eglMakeCurrent" : "before");
    glClearColor(0.2f, 0.4f, 0.6f, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    GLuint t;
    glGenTextures(1, &t);
    glFinish();
    report("after GL calls");
    eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    report("after unbind");
    (void)who;
}

static void *thread_main(void *a)
{
    (void)a;
    memset(probe, 0xAA, N);
    report("thread start");
    gl_work("thread", 1);
    return NULL;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    memset(probe, 0xAA, N);
    d = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    report("after eglGetDisplay");
    eglInitialize(d, NULL, NULL);
    report("after eglInitialize");
    eglBindAPI(EGL_OPENGL_ES_API);
    const EGLint xa[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    ctx = eglCreateContext(d, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, xa);
    report("after eglCreateContext");
    printf("--- main thread\n");
    gl_work("main", 1);
    printf("--- second thread\n");
    pthread_t th;
    pthread_create(&th, NULL, thread_main, NULL);
    pthread_join(th, NULL);
    return 0;
}
