/* GPU port: zero-copy GPU-to-screen test. Allocates scanout buffers with Android's AHardwareBuffer
 * (libnativewindow via libhybris -> MediaTek allocator HAL), renders into them on the Mali GPU through an
 * EGLImage-backed FBO, imports the same dma-buf into mediatek-drm (PRIME + ADDFB2) and page-flips it.
 * No glReadPixels. Needs DRM master (stop Xorg first). Usage: gles-drm-zc [seconds]
 * Only legacy SETCRTC/PAGE_FLIP/ADDFB2 ioctls are used (see HANDOFF.md "Why the display needed a shim"). */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>
#include <hybris/common/binding.h>

#define GLFUNCS(X) \
    X(const GLubyte *, GetString, (GLenum)) \
    X(GLuint, CreateShader, (GLenum)) \
    X(void, ShaderSource, (GLuint, GLsizei, const GLchar *const *, const GLint *)) \
    X(void, CompileShader, (GLuint)) \
    X(void, GetShaderiv, (GLuint, GLenum, GLint *)) \
    X(void, GetShaderInfoLog, (GLuint, GLsizei, GLsizei *, GLchar *)) \
    X(GLuint, CreateProgram, (void)) \
    X(void, AttachShader, (GLuint, GLuint)) \
    X(void, BindAttribLocation, (GLuint, GLuint, const GLchar *)) \
    X(void, LinkProgram, (GLuint)) \
    X(void, UseProgram, (GLuint)) \
    X(GLint, GetUniformLocation, (GLuint, const GLchar *)) \
    X(void, Uniform1f, (GLint, GLfloat)) \
    X(void, Uniform2f, (GLint, GLfloat, GLfloat)) \
    X(void, VertexAttribPointer, (GLuint, GLint, GLenum, GLboolean, GLsizei, const void *)) \
    X(void, EnableVertexAttribArray, (GLuint)) \
    X(void, DrawArrays, (GLenum, GLint, GLsizei)) \
    X(void, Viewport, (GLint, GLint, GLsizei, GLsizei)) \
    X(void, GenFramebuffers, (GLsizei, GLuint *)) \
    X(void, BindFramebuffer, (GLenum, GLuint)) \
    X(void, GenTextures, (GLsizei, GLuint *)) \
    X(void, BindTexture, (GLenum, GLuint)) \
    X(void, TexParameteri, (GLenum, GLenum, GLint)) \
    X(void, EGLImageTargetTexture2DOES, (GLenum, void *)) \
    X(void, FramebufferTexture2D, (GLenum, GLenum, GLenum, GLuint, GLint)) \
    X(GLenum, CheckFramebufferStatus, (GLenum)) \
    X(void, ClearColor, (GLfloat, GLfloat, GLfloat, GLfloat)) \
    X(void, Clear, (GLbitfield)) \
    X(void, Finish, (void)) \
    X(GLenum, GetError, (void))
#define DECL(r, n, a) static r (*p##n) a;
GLFUNCS(DECL)
#define LOAD(r, n, a) if (!(p##n = (void *)eglGetProcAddress("gl" #n))) { printf("missing gl" #n "\n"); return 1; }

/* AHardwareBuffer C API (Android NDK ABI). */
typedef struct { uint32_t width, height, layers, format; uint64_t usage; uint32_t stride, rfu0; uint64_t rfu1; } AHBDesc;
typedef struct { int version, numFds, numInts, data[]; } NativeHandle;
static int (*AHB_allocate)(const AHBDesc *, void **);
static void (*AHB_describe)(const void *, AHBDesc *);
static const NativeHandle *(*AHB_getNativeHandle)(const void *);
#define AHB_FORMAT_R8G8B8A8 1
#define AHB_USAGE_CPU_READ_RARELY 2ULL
#define AHB_USAGE_GPU_SAMPLED_IMAGE (1ULL << 8)
#define AHB_USAGE_GPU_FRAMEBUFFER (1ULL << 9)
#define AHB_USAGE_COMPOSER_OVERLAY (1ULL << 11)

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

static const char *vs = "attribute vec2 p; varying vec2 uv; void main(){ uv = p*0.5+0.5; gl_Position = vec4(p,0.,1.); }";
static const char *fs =
    "precision mediump float; varying vec2 uv; uniform float t; uniform vec2 res;\n"
    "void main(){ vec2 q = uv*res/400.;\n"
    " float v = sin(q.x+t) + sin(q.y*1.3-t*1.7) + sin((q.x+q.y)*0.7+t*0.9) + sin(length(q-vec2(2.,3.))*1.5-t*2.);\n"
    " vec3 c = 0.5+0.5*cos(vec3(0.,2.1,4.2)+v*1.3+t*0.3);\n"
    " vec2 b = abs(uv-0.5); if (max(b.x*res.x, b.y*res.y) > 0.5*min(res.x,res.y)-40. && max(b.x,b.y)<0.5) c = c*0.4;\n"
    " gl_FragColor = vec4(c, 1.); }";

static GLuint sh(GLenum ty, const char *src)
{
    GLuint s = pCreateShader(ty); GLint ok; char log[512];
    pShaderSource(s, 1, &src, NULL); pCompileShader(s); pGetShaderiv(s, 0x8B81 /*COMPILE_STATUS*/, &ok);
    if (!ok) { pGetShaderInfoLog(s, sizeof log, NULL, log); printf("shader: %s\n", log); exit(1); }
    return s;
}

static int flip_pending;
static void on_flip(int fd, unsigned f, unsigned s, unsigned us, void *d) { (void)fd; (void)f; (void)s; (void)us; (void)d; flip_pending = 0; }

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    double secs = argc > 1 ? atof(argv[1]) : 10;
    int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0 || drmSetMaster(fd)) { printf("no DRM master (is Xorg still running?)\n"); return 1; }
    drmModeRes *res = drmModeGetResources(fd);
    drmModeConnector *con = NULL;
    for (int i = 0; i < res->count_connectors && !con; i++) {
        drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);
        if (c->connector_type == DRM_MODE_CONNECTOR_DSI && c->connection == DRM_MODE_CONNECTED && c->count_modes) con = c;
        else drmModeFreeConnector(c);
    }
    if (!con) { printf("no DSI connector\n"); return 1; }
    drmModeModeInfo mode = con->modes[0];
    uint32_t crtc = 0;
    drmModeEncoder *enc = drmModeGetEncoder(fd, con->encoder_id ? con->encoder_id : con->encoders[0]);
    if (enc && enc->crtc_id) crtc = enc->crtc_id;
    for (int i = 0; !crtc && enc && i < res->count_crtcs; i++) if (enc->possible_crtcs & (1u << i)) crtc = res->crtcs[i];
    drmModeCrtc *saved = drmModeGetCrtc(fd, crtc);
    int W = mode.hdisplay, H = mode.vdisplay;
    printf("DSI connector %u, crtc %u, mode %dx%d@%d\n", con->connector_id, crtc, W, H, mode.vrefresh);

    void *nw = android_dlopen("/system/lib64/libnativewindow.so", RTLD_NOW);
    if (!nw) { printf("android_dlopen libnativewindow failed\n"); return 1; }
    AHB_allocate = android_dlsym(nw, "AHardwareBuffer_allocate");
    AHB_describe = android_dlsym(nw, "AHardwareBuffer_describe");
    AHB_getNativeHandle = android_dlsym(nw, "AHardwareBuffer_getNativeHandle");
    if (!AHB_allocate || !AHB_describe || !AHB_getNativeHandle) { printf("AHardwareBuffer symbols missing\n"); return 1; }

    uint32_t fb[2]; void *ahb[2]; int dfd[2]; uint32_t stride = 0;
    for (int i = 0; i < 2; i++) { /* allocate + import before EGL starts: allocating after eglMakeCurrent broke Mali GL calls */
        AHBDesc de = { .width = W, .height = H, .layers = 1, .format = AHB_FORMAT_R8G8B8A8,
                       .usage = AHB_USAGE_GPU_FRAMEBUFFER | AHB_USAGE_GPU_SAMPLED_IMAGE | AHB_USAGE_COMPOSER_OVERLAY |
                                AHB_USAGE_CPU_READ_RARELY };
        int r = AHB_allocate(&de, &ahb[i]);
        if (r) { printf("AHardwareBuffer_allocate failed %d\n", r); return 1; }
        AHB_describe(ahb[i], &de); stride = de.stride;
        const NativeHandle *nh = AHB_getNativeHandle(ahb[i]);
        printf("buffer %d: stride %u px, %d fds, %d ints\n", i, de.stride, nh->numFds, nh->numInts);
        /* Pick the first fd mediatek-drm accepts as a PRIME buffer; log what each fd is. */
        uint32_t h = 0; dfd[i] = -1;
        for (int k = 0; k < nh->numFds; k++) {
            char p[64], l[128] = "", info[512] = ""; snprintf(p, sizeof p, "/proc/self/fd/%d", nh->data[k]);
            ssize_t ln = readlink(p, l, sizeof l - 1); if (ln > 0) l[ln] = 0;
            snprintf(p, sizeof p, "/proc/self/fdinfo/%d", nh->data[k]);
            FILE *f = fopen(p, "r"); if (f) { size_t r2 = fread(info, 1, sizeof info - 1, f); info[r2] = 0; fclose(f); }
            for (char *q = info; *q; q++) if (*q == '\n') *q = ' ';
            int ok = dfd[i] < 0 && !drmPrimeFDToHandle(fd, nh->data[k], &h);
            printf("  fd[%d]=%d %s | %.150s| prime %s\n", k, nh->data[k], l, info, ok ? "OK" : (dfd[i] < 0 ? strerror(errno) : "-"));
            if (ok) dfd[i] = nh->data[k];
        }
        if (dfd[i] < 0) return 1;
        uint32_t hs[4] = { h }, ps[4] = { stride * 4 }, os[4] = { 0 };
        if (drmModeAddFB2(fd, W, H, DRM_FORMAT_XBGR8888, hs, ps, os, &fb[i], 0)) { perror("addfb2"); return 1; }
        printf("  addfb2 ok fb=%u\n", fb[i]);
    }
    EGLDisplay d = eglGetDisplay(EGL_DEFAULT_DISPLAY); EGLint n;
    if (!eglInitialize(d, NULL, NULL)) { printf("eglInitialize failed\n"); return 1; }
    const EGLint ca[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                          EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE };
    EGLConfig c; eglChooseConfig(d, ca, &c, 1, &n);
    const EGLint sa[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
    EGLSurface s = eglCreatePbufferSurface(d, c, sa);
    const EGLint xa[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext x = eglCreateContext(d, c, EGL_NO_CONTEXT, xa);
    if (!eglMakeCurrent(d, s, s, x)) { printf("makecurrent failed 0x%x\n", eglGetError()); return 1; }
    GLFUNCS(LOAD)
    PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC getCB = (void *)eglGetProcAddress("eglGetNativeClientBufferANDROID");
    PFNEGLCREATEIMAGEKHRPROC createImage = (void *)eglGetProcAddress("eglCreateImageKHR");
    if (!getCB || !createImage) { printf("missing EGL android buffer extensions\n"); return 1; }
    printf("GL_RENDERER=%s\n", pGetString(GL_RENDERER));
    GLuint fbo[2], rb[2];
    pGenTextures(2, rb); printf("  textures %u %u ok\n", rb[0], rb[1]);
    pGenFramebuffers(2, fbo); printf("  framebuffers %u %u ok\n", fbo[0], fbo[1]);
    pBindTexture(GL_TEXTURE_2D, rb[0]); printf("  early bind ok\n");
    pTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR); printf("  early texparameter ok\n");

    for (int i = 0; i < 2; i++) {
        void *cb = getCB(ahb[i]); printf("  client buffer %p, glError 0x%x\n", cb, pGetError());
        EGLint ia[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
        EGLImageKHR img = createImage(d, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID, cb, ia);
        if (img == EGL_NO_IMAGE_KHR) { printf("eglCreateImageKHR failed 0x%x\n", eglGetError()); return 1; }
        printf("  eglimage ok %p (driver image %p)\n", img, *(void **)img);
        printf("  glError 0x%x\n", pGetError());
        /* Texture-backed FBO (the path Android apps use). The renderbuffer path crashed inside Mali. */
        pBindTexture(GL_TEXTURE_2D, rb[i]); printf("  bound tex %u ok\n", rb[i]);
        pTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        pEGLImageTargetTexture2DOES(GL_TEXTURE_2D, img); printf("  image->texture ok (glError 0x%x)\n", pGetError());
        pBindFramebuffer(GL_FRAMEBUFFER, fbo[i]);
        pFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, rb[i], 0);
        GLenum st = pCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (st != GL_FRAMEBUFFER_COMPLETE) { printf("FBO incomplete 0x%x\n", st); return 1; }
    }

    /* Layout check: clear buffer 0 to a known colour and look at it through a CPU mapping of the dma-buf.
     * Linear RGBA gives 40,80,c0,ff at every pixel; a compressed (AFBC) layout would not. */
    pBindFramebuffer(GL_FRAMEBUFFER, fbo[0]); pViewport(0, 0, W, H);
    pClearColor(0x40 / 255.f, 0x80 / 255.f, 0xc0 / 255.f, 1); pClear(GL_COLOR_BUFFER_BIT); pFinish();
    size_t sz = (size_t)stride * 4 * H;
    uint8_t *m = mmap(0, sz, PROT_READ, MAP_SHARED, dfd[0], 0);
    if (m != MAP_FAILED) {
        size_t offs[3] = { 0, (size_t)(H / 2) * stride * 4 + (W / 2) * 4, (size_t)(H - 1) * stride * 4 + (W - 1) * 4 };
        for (int k = 0; k < 3; k++) printf("layout check px%d = %02x,%02x,%02x,%02x\n", k, m[offs[k]], m[offs[k] + 1], m[offs[k] + 2], m[offs[k] + 3]);
        munmap(m, sz);
    } else perror("mmap dma-buf (layout check skipped)");

    GLuint prog = pCreateProgram();
    pAttachShader(prog, sh(GL_VERTEX_SHADER, vs)); pAttachShader(prog, sh(GL_FRAGMENT_SHADER, fs));
    pBindAttribLocation(prog, 0, "p"); pLinkProgram(prog); pUseProgram(prog);
    static const float quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
    pVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad); pEnableVertexAttribArray(0);
    GLint ut = pGetUniformLocation(prog, "t"), ur = pGetUniformLocation(prog, "res");
    pUniform2f(ur, W, H);

    if (drmModeSetCrtc(fd, crtc, fb[0], 0, 0, &con->connector_id, 1, &mode)) { perror("setcrtc"); return 1; }
    drmEventContext ev = { .version = 2, .page_flip_handler = on_flip };
    double t0 = now(), tdraw = 0; int frames = 0, cur = 1, flips_ok = 1;
    while (now() - t0 < secs) {
        double a = now();
        pBindFramebuffer(GL_FRAMEBUFFER, fbo[cur]);
        pUniform1f(ut, (float)(a - t0)); pDrawArrays(GL_TRIANGLE_STRIP, 0, 4); pFinish();
        tdraw += now() - a;
        if (flips_ok && !drmModePageFlip(fd, crtc, fb[cur], DRM_MODE_PAGE_FLIP_EVENT, NULL)) {
            flip_pending = 1;
            while (flip_pending) drmHandleEvent(fd, &ev);
        } else {
            if (flips_ok) { printf("page flip unsupported, using SETCRTC per frame\n"); flips_ok = 0; }
            drmModeSetCrtc(fd, crtc, fb[cur], 0, 0, &con->connector_id, 1, &mode);
        }
        cur ^= 1; frames++;
    }
    double el = now() - t0;
    printf("frames=%d in %.1fs = %.1f fps | draw %.1f ms per frame | glError=0x%x\n", frames, el, frames / el,
           tdraw * 1e3 / frames, pGetError());
    if (saved && saved->buffer_id)
        drmModeSetCrtc(fd, crtc, saved->buffer_id, saved->x, saved->y, &con->connector_id, 1, &saved->mode);
    eglTerminate(d);
    return 0;
}
