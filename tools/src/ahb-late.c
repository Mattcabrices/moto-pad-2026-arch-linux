/* GPU port experiment: does allocating an AHardwareBuffer AFTER eglMakeCurrent break Mali GL calls, and
 * which workaround fixes it? FIX=none|remake|thread  (remake = eglMakeCurrent again after allocating,
 * thread = allocate on a separate pthread). Also tests the renderbuffer EGLImage path (RB=1).
 * Off-screen only; no DRM needed. */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <hybris/common/binding.h>

typedef struct { uint32_t width, height, layers, format; uint64_t usage; uint32_t stride, rfu0; uint64_t rfu1; } AHBDesc;
static int (*AHB_allocate)(const AHBDesc *, void **);
static void *ahb;
static void *alloc_thread(void *a) { (void)a; AHBDesc de = { 256, 256, 1, 1, (1ULL << 9) | (1ULL << 8) | (1ULL << 11) | 2 }; AHB_allocate(&de, &ahb); return NULL; }

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    const char *fix = getenv("FIX") ? getenv("FIX") : "none"; int rbpath = getenv("RB") != NULL;
    void *nw = android_dlopen("/system/lib64/libnativewindow.so", RTLD_NOW);
    AHB_allocate = android_dlsym(nw, "AHardwareBuffer_allocate");
    if (strstr(fix, "warm")) { /* one throw-away allocation before EGL starts */
        AHBDesc de = { 64, 64, 1, 1, (1ULL << 9) | (1ULL << 8) | 2 }; void *w = NULL;
        printf("warm-up allocation %d\n", AHB_allocate(&de, &w));
    }
    EGLDisplay d = eglGetDisplay(EGL_DEFAULT_DISPLAY); EGLint n;
    eglInitialize(d, NULL, NULL);
    const EGLint ca[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_NONE };
    EGLConfig c; eglChooseConfig(d, ca, &c, 1, &n);
    const EGLint sa[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
    EGLSurface s = eglCreatePbufferSurface(d, c, sa);
    const EGLint xa[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext x = eglCreateContext(d, c, EGL_NO_CONTEXT, xa);
    eglMakeCurrent(d, s, s, x);
    void (*GenTextures)(GLsizei, GLuint *) = (void *)eglGetProcAddress("glGenTextures");
    void (*BindTexture)(GLenum, GLuint) = (void *)eglGetProcAddress("glBindTexture");
    void (*TexParameteri)(GLenum, GLenum, GLint) = (void *)eglGetProcAddress("glTexParameteri");
    void (*GenRenderbuffers)(GLsizei, GLuint *) = (void *)eglGetProcAddress("glGenRenderbuffers");
    void (*BindRenderbuffer)(GLenum, GLuint) = (void *)eglGetProcAddress("glBindRenderbuffer");
    void (*ImgTex)(GLenum, void *) = (void *)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    void (*ImgRb)(GLenum, void *) = (void *)eglGetProcAddress("glEGLImageTargetRenderbufferStorageOES");
    GLenum (*GetError)(void) = (void *)eglGetProcAddress("glGetError");
    PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC getCB = (void *)eglGetProcAddress("eglGetNativeClientBufferANDROID");
    PFNEGLCREATEIMAGEKHRPROC createImage = (void *)eglGetProcAddress("eglCreateImageKHR");
    printf("FIX=%s RB=%d: context current\n", fix, rbpath);

    if (!strcmp(fix, "thread")) { pthread_t t; pthread_create(&t, NULL, alloc_thread, NULL); pthread_join(t, NULL); }
    else alloc_thread(NULL);
    printf("allocated %p\n", ahb);
    if (strstr(fix, "remake")) { eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT); eglMakeCurrent(d, s, s, x); printf("re-made current\n"); }

    GLuint t; GenTextures(1, &t); printf("GenTextures ok\n");
    BindTexture(GL_TEXTURE_2D, t); TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR); printf("TexParameteri ok\n");
    EGLImageKHR img = createImage(d, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID, getCB(ahb), NULL);
    printf("image %p\n", img);
    void (*GenFramebuffers)(GLsizei, GLuint *) = (void *)eglGetProcAddress("glGenFramebuffers");
    void (*BindFramebuffer)(GLenum, GLuint) = (void *)eglGetProcAddress("glBindFramebuffer");
    void (*FbRb)(GLenum, GLenum, GLenum, GLuint) = (void *)eglGetProcAddress("glFramebufferRenderbuffer");
    void (*FbTex)(GLenum, GLenum, GLenum, GLuint, GLint) = (void *)eglGetProcAddress("glFramebufferTexture2D");
    GLenum (*Check)(GLenum) = (void *)eglGetProcAddress("glCheckFramebufferStatus");
    void (*ClearColor)(GLfloat, GLfloat, GLfloat, GLfloat) = (void *)eglGetProcAddress("glClearColor");
    void (*Clear)(GLbitfield) = (void *)eglGetProcAddress("glClear");
    void (*Viewport)(GLint, GLint, GLsizei, GLsizei) = (void *)eglGetProcAddress("glViewport");
    void (*Finish)(void) = (void *)eglGetProcAddress("glFinish");
    GLuint fbo; GenFramebuffers(1, &fbo); BindFramebuffer(GL_FRAMEBUFFER, fbo);
    if (rbpath) { GLuint r; GenRenderbuffers(1, &r); BindRenderbuffer(GL_RENDERBUFFER, r); ImgRb(GL_RENDERBUFFER, img);
                  FbRb(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, r); printf("renderbuffer path ok\n"); }
    else { ImgTex(GL_TEXTURE_2D, img); FbTex(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t, 0); printf("texture path ok\n"); }
    printf("fbo status 0x%x\n", Check(GL_FRAMEBUFFER));
    Viewport(0, 0, 256, 256); ClearColor(0x40 / 255.f, 0x80 / 255.f, 0xc0 / 255.f, 1); Clear(GL_COLOR_BUFFER_BIT); Finish();
    /* Read the dma-buf (fd named /dmabuf:) through a CPU mapping. */
    typedef struct { int version, numFds, numInts, data[]; } NH;
    const NH *(*getNH)(const void *) = android_dlsym(nw, "AHardwareBuffer_getNativeHandle");
    const NH *nh = getNH(ahb);
    for (int k = 0; k < nh->numFds; k++) {
        char p[64], l[64] = ""; snprintf(p, sizeof p, "/proc/self/fd/%d", nh->data[k]);
        ssize_t ln = readlink(p, l, sizeof l - 1); if (ln > 0) l[ln] = 0;
        if (strncmp(l, "/dmabuf:", 8)) continue;
        unsigned char *m = mmap(0, 256 * 256 * 4, PROT_READ, MAP_SHARED, nh->data[k], 0);
        if (m != MAP_FAILED) printf("dma-buf pixel = %02x,%02x,%02x,%02x (want 40,80,c0,ff)\n", m[4 * 300], m[4 * 300 + 1], m[4 * 300 + 2], m[4 * 300 + 3]);
    }
    printf("RESULT %s RB=%d: PASS glError 0x%x\n", fix, rbpath, GetError());
    return 0;
}
