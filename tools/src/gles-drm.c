/* GPU port: first GPU-to-screen test. Renders a GLES2 shader on the Mali GPU (libhybris,
 * EGL_PLATFORM=null pbuffer), reads each frame back into a DRM dumb buffer and page-flips it on DSI-1.
 * Needs DRM master (stop Xorg first). Usage: gles-drm [seconds]
 * Only legacy SETCRTC/PAGE_FLIP/dumb-buffer ioctls are used; mediatek-drm crashes on planes,
 * cursor, gamma and property writes (see HANDOFF.md "Why the display needed a shim"). */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

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
    X(void, ReadPixels, (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *)) \
    X(void, Finish, (void)) \
    X(GLenum, GetError, (void))
#define DECL(r, n, a) static r (*p##n) a;
GLFUNCS(DECL)
#define LOAD(r, n, a) if (!(p##n = (void *)eglGetProcAddress("gl" #n))) { printf("missing gl" #n "\n"); return 1; }

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

/* Colours are written as (b,g,r): RGBA bytes read back then land as B,G,R,X = DRM XRGB8888. */
static const char *vs = "attribute vec2 p; varying vec2 uv; void main(){ uv = p*0.5+0.5; gl_Position = vec4(p,0.,1.); }";
static const char *fs =
    "precision mediump float; varying vec2 uv; uniform float t; uniform vec2 res;\n"
    "void main(){ vec2 q = uv*res/400.;\n"
    " float v = sin(q.x+t) + sin(q.y*1.3-t*1.7) + sin((q.x+q.y)*0.7+t*0.9) + sin(length(q-vec2(2.,3.))*1.5-t*2.);\n"
    " vec3 c = 0.5+0.5*cos(vec3(0.,2.1,4.2)+v*1.3+t*0.3);\n"
    " vec2 b = abs(uv-0.5); if (max(b.x*res.x, b.y*res.y) > 0.5*min(res.x,res.y)-40. && max(b.x,b.y)<0.5) c = c*0.4;\n"
    " gl_FragColor = vec4(c.b, c.g, c.r, 1.); }";

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
    printf("DSI connector %u, crtc %u, mode %s %dx%d@%d\n", con->connector_id, crtc, mode.name, W, H, mode.vrefresh);

    uint32_t fb[2], pitch = 0; uint8_t *map[2];
    for (int i = 0; i < 2; i++) {
        struct drm_mode_create_dumb cd = { .width = W, .height = H, .bpp = 32 };
        if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd)) { perror("create_dumb"); return 1; }
        pitch = cd.pitch;
        if (drmModeAddFB(fd, W, H, 24, 32, cd.pitch, cd.handle, &fb[i])) { perror("addfb"); return 1; }
        struct drm_mode_map_dumb md = { .handle = cd.handle };
        drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md);
        map[i] = mmap(0, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, md.offset);
        if (map[i] == MAP_FAILED) { perror("mmap"); return 1; }
        memset(map[i], 0, cd.size);
    }
    if (pitch != (uint32_t)W * 4) printf("note: pitch %u != width*4, rows copied one by one\n", pitch);
    if (drmModeSetCrtc(fd, crtc, fb[0], 0, 0, &con->connector_id, 1, &mode)) { perror("setcrtc"); return 1; }

    EGLDisplay d = eglGetDisplay(EGL_DEFAULT_DISPLAY); EGLint n;
    if (!eglInitialize(d, NULL, NULL)) { printf("eglInitialize failed\n"); return 1; }
    const EGLint ca[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                          EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE };
    EGLConfig c; eglChooseConfig(d, ca, &c, 1, &n);
    const EGLint sa[] = { EGL_WIDTH, W, EGL_HEIGHT, H, EGL_NONE };
    EGLSurface s = eglCreatePbufferSurface(d, c, sa);
    const EGLint xa[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext x = eglCreateContext(d, c, EGL_NO_CONTEXT, xa);
    if (!eglMakeCurrent(d, s, s, x)) { printf("makecurrent failed 0x%x\n", eglGetError()); return 1; }
    GLFUNCS(LOAD)
    printf("GL_RENDERER=%s\n", pGetString(GL_RENDERER));
    GLuint prog = pCreateProgram();
    pAttachShader(prog, sh(GL_VERTEX_SHADER, vs)); pAttachShader(prog, sh(GL_FRAGMENT_SHADER, fs));
    pBindAttribLocation(prog, 0, "p"); pLinkProgram(prog); pUseProgram(prog);
    static const float quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
    pVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad); pEnableVertexAttribArray(0);
    GLint ut = pGetUniformLocation(prog, "t"), ur = pGetUniformLocation(prog, "res");
    pUniform2f(ur, W, H); pViewport(0, 0, W, H);

    uint8_t *tmp = pitch == (uint32_t)W * 4 ? NULL : malloc((size_t)W * H * 4);
    drmEventContext ev = { .version = 2, .page_flip_handler = on_flip };
    double t0 = now(), tdraw = 0, tread = 0; int frames = 0, cur = 1, flips_ok = 1;
    while (now() - t0 < secs) {
        double a = now();
        pUniform1f(ut, (float)(a - t0)); pDrawArrays(GL_TRIANGLE_STRIP, 0, 4); pFinish();
        double b = now();
        if (tmp) {
            pReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, tmp);
            for (int y = 0; y < H; y++) memcpy(map[cur] + (size_t)y * pitch, tmp + (size_t)y * W * 4, W * 4);
        } else pReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, map[cur]);
        tdraw += b - a; tread += now() - b;
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
    printf("frames=%d in %.1fs = %.1f fps | draw %.1f ms, readback+copy %.1f ms per frame | glError=0x%x\n", frames, el,
           frames / el, tdraw * 1e3 / frames, tread * 1e3 / frames, pGetError());
    if (saved && saved->buffer_id)
        drmModeSetCrtc(fd, crtc, saved->buffer_id, saved->x, saved->y, &con->connector_id, 1, &saved->mode);
    eglTerminate(d);
    return 0;
}
