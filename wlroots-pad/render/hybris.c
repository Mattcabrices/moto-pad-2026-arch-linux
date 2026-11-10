/* Moto Pad (archpad) libhybris support for wlroots.
 *
 * - Renderer: wlroots' GLES2 renderer on a context from libhybris' EGL (Mali blobs).
 * - Allocator: AHardwareBuffer (Android libnativewindow, via android_dlopen) -> MediaTek allocator HAL.
 *   Each buffer exposes its dma-buf (the "/dmabuf:" fd in the native handle) to wlroots, so the pad
 *   backend can scan it out with ADDFB2.
 * - Mali has no EGL_EXT_image_dma_buf_import, so render/egl.c asks wlr_hybris_create_image() to turn
 *   our own dma-bufs back into EGLImages via EGL_NATIVE_BUFFER_ANDROID. Client dma-bufs (linux-dmabuf) work
 *   only for buffers whose AHardwareBuffer the client also sent over archpad-ahb.sock (Chromium through
 *   tools/src/archpad-gbm.c); others fail to import.
 * Gotcha: the FIRST AHardwareBuffer allocation (it loads the gralloc mapper) breaks EGL if EGL is already
 * initialized: later GL calls crash or silently do nothing (FBO status 0, nothing rendered). So the
 * renderer makes one throw-away allocation before eglInitialize. Later allocations are then fine
 * (tools/src/ahb-late.c FIX=warm: correct pixels on both the texture and renderbuffer paths).
 */
#define _GNU_SOURCE /* memfd_create, accept4 */
#include <dlfcn.h>
#include <drm_fourcc.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/mman.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

/* EGL_WL_bind_wayland_display (libhybris implements it; Mesa's eglmesaext.h does not build here). */
#ifndef EGL_WAYLAND_BUFFER_WL
#define EGL_WAYLAND_BUFFER_WL 0x31D5
#endif
#ifndef EGL_TEXTURE_RGB
#define EGL_TEXTURE_RGB 0x305D
#define EGL_TEXTURE_RGBA 0x305E
#endif
typedef EGLBoolean (*hybris_bind_wl_display_fn)(EGLDisplay, struct wl_display *);
typedef EGLBoolean (*hybris_query_wl_buffer_fn)(EGLDisplay, struct wl_resource *, EGLint, EGLint *);
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/render/egl.h>
#include <wlr/render/gles2.h>
#include <wlr/util/log.h>
#include "render/hybris.h"

void *android_dlopen(const char *filename, int flag);
void *android_dlsym(void *handle, const char *symbol);

typedef struct { uint32_t width, height, layers, format; uint64_t usage; uint32_t stride, rfu0; uint64_t rfu1; } AHBDesc;
typedef struct { int version, numFds, numInts, data[]; } NativeHandle;
static int (*AHB_allocate)(const AHBDesc *, void **);
static void (*AHB_describe)(const void *, AHBDesc *);
static void (*AHB_release)(void *);
static const NativeHandle *(*AHB_getNativeHandle)(const void *);
static int (*AHB_recv)(int, void **);

#define AHB_USAGE (2ULL /* CPU_READ_RARELY: keeps the buffer linear */ | (1ULL << 8) /* GPU_SAMPLED */ | \
                   (1ULL << 9) /* GPU_FRAMEBUFFER */ | (1ULL << 11) /* COMPOSER_OVERLAY */)

bool wlr_hybris_enabled(void) {
	const char *r = getenv("WLR_RENDERER");
	return r && strcmp(r, "hybris") == 0;
}

static bool load_ahb(void) {
	if (AHB_allocate) {
		return true;
	}
	void *nw = android_dlopen("/system/lib64/libnativewindow.so", RTLD_NOW);
	if (!nw) {
		wlr_log(WLR_ERROR, "hybris: android_dlopen(libnativewindow) failed");
		return false;
	}
	AHB_describe = android_dlsym(nw, "AHardwareBuffer_describe");
	AHB_release = android_dlsym(nw, "AHardwareBuffer_release");
	AHB_getNativeHandle = android_dlsym(nw, "AHardwareBuffer_getNativeHandle");
	AHB_recv = android_dlsym(nw, "AHardwareBuffer_recvHandleFromUnixSocket");
	AHB_allocate = android_dlsym(nw, "AHardwareBuffer_allocate");
	return AHB_allocate && AHB_describe && AHB_release && AHB_getNativeHandle;
}

/* --- dma-buf -> AHardwareBuffer registry (keyed by dma-buf inode, so dup'ed fds match) --- */

struct hybris_buffer {
	struct wlr_buffer base;
	void *ahb;
	ino_t ino;
	struct wlr_dmabuf_attributes dmabuf;
	struct hybris_buffer *next;
};
static struct hybris_buffer *registry;

void *wlr_hybris_ahb_from_dmabuf(int fd) {
	struct stat st;
	if (fstat(fd, &st) != 0) {
		return NULL;
	}
	for (struct hybris_buffer *b = registry; b; b = b->next) {
		if (b->ino == st.st_ino) {
			return b->ahb;
		}
	}
	return NULL;
}

static struct wl_resource *client_resource_from_fd(int fd);

/* --- AHardwareBuffers sent by clients (Chromium's GPU process through tools/src/archpad-gbm.c) ---
 * Their dma-bufs arrive as ordinary linux-dmabuf wl_buffers; the AHardwareBuffer behind each one comes over
 * $XDG_RUNTIME_DIR/archpad-ahb.sock first (AHardwareBuffer_sendHandleToUnixSocket). A connection's first byte says
 * what it carries: 'A' = buffers, 'F' = 16-byte {st_dev, st_ino} messages for buffers the client destroyed. */



struct remote_ahb {
	void *ahb;
	dev_t dev;
	ino_t ino;
	int conn;
	struct remote_ahb *next;
};
static struct remote_ahb *remote_ahbs;

struct ahb_conn {
	int fd;
	char kind;
	struct wl_event_source *source;
	struct ahb_conn *next;
};
static struct ahb_conn *ahb_conns;

static void remote_drop(bool (*match)(struct remote_ahb *, const void *), const void *arg) {
	for (struct remote_ahb **p = &remote_ahbs; *p;) {
		struct remote_ahb *r = *p;
		if (match(r, arg)) {
			*p = r->next;
			AHB_release(r->ahb);
			free(r);
		} else {
			p = &r->next;
		}
	}
}

static bool match_conn(struct remote_ahb *r, const void *arg) {
	return r->conn == *(const int *)arg;
}

static bool match_ino(struct remote_ahb *r, const void *arg) {
	const uint64_t *m = arg;
	return r->dev == (dev_t)m[0] && r->ino == (ino_t)m[1];
}

static void ahb_conn_close(struct ahb_conn *c) {
	if (c->kind == 'A') {
		remote_drop(match_conn, &c->fd);
	}
	wl_event_source_remove(c->source);
	close(c->fd);
	for (struct ahb_conn **p = &ahb_conns; *p; p = &(*p)->next) {
		if (*p == c) {
			*p = c->next;
			break;
		}
	}
	free(c);
}

/* Reads everything waiting on one connection. Returns false when the connection is gone. */
static bool ahb_conn_read(struct ahb_conn *c) {
	for (;;) {
		if (c->kind == 0) {
			char k;
			ssize_t n = recv(c->fd, &k, 1, MSG_DONTWAIT);
			if (n == 1 && (k == 'A' || k == 'F')) {
				c->kind = k;
				continue;
			}
			return n < 0 && errno == EAGAIN;
		}
		if (c->kind == 'F') {
			uint64_t m[2];
			ssize_t n = recv(c->fd, m, sizeof(m), MSG_DONTWAIT);
			if (n == sizeof(m)) {
				remote_drop(match_ino, m);
				continue;
			}
			return n < 0 && errno == EAGAIN;
		}
		struct pollfd pfd = { .fd = c->fd, .events = POLLIN };
		if (poll(&pfd, 1, 0) <= 0) {
			return true;
		}
		if (pfd.revents & (POLLHUP | POLLERR) && !(pfd.revents & POLLIN)) {
			return false;
		}
		void *ahb = NULL;
		if (AHB_recv(c->fd, &ahb) != 0 || !ahb) {
			return false;
		}
		const NativeHandle *nh = AHB_getNativeHandle(ahb);
		struct stat st = { 0 };
		bool found = false;
		for (int k = 0; nh && k < nh->numFds && !found; k++) {
			char p[64], l[64] = "";
			snprintf(p, sizeof(p), "/proc/self/fd/%d", nh->data[k]);
			ssize_t n = readlink(p, l, sizeof(l) - 1);
			found = n > 0 && strncmp(l, "/dmabuf:", 8) == 0 && fstat(nh->data[k], &st) == 0;
		}
		struct remote_ahb *r = found ? calloc(1, sizeof(*r)) : NULL;
		if (!r) {
			AHB_release(ahb);
			continue;
		}
		*r = (struct remote_ahb){ .ahb = ahb, .dev = st.st_dev, .ino = st.st_ino, .conn = c->fd, .next = remote_ahbs };
		remote_ahbs = r;
		wlr_log(WLR_DEBUG, "hybris: client buffer ino %lu received", (unsigned long)st.st_ino);
	}
}

static int ahb_conn_event(int fd, uint32_t mask, void *data) {
	struct ahb_conn *c = data;
	if (!ahb_conn_read(c) || (mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR))) {
		ahb_conn_close(c);
	}
	return 0;
}

static int ahb_listen_event(int fd, uint32_t mask, void *data) {
	struct wl_event_loop *loop = data;
	int s = accept4(fd, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
	if (s < 0) {
		return 0;
	}
	struct ahb_conn *c = calloc(1, sizeof(*c));
	if (!c) {
		close(s);
		return 0;
	}
	c->fd = s;
	c->source = wl_event_loop_add_fd(loop, s, WL_EVENT_READABLE, ahb_conn_event, c);
	c->next = ahb_conns;
	ahb_conns = c;
	return 0;
}

static void ahb_listen(struct wl_display *wl_display) {
	const char *dir = getenv("XDG_RUNTIME_DIR");
	if (!dir || !AHB_recv) {
		return;
	}
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	snprintf(a.sun_path, sizeof(a.sun_path), "%s/archpad-ahb.sock", dir);
	unlink(a.sun_path);
	int s = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (s < 0 || bind(s, (struct sockaddr *)&a, sizeof(a)) != 0 || listen(s, 16) != 0) {
		wlr_log_errno(WLR_ERROR, "hybris: client buffer socket %s", a.sun_path);
		if (s >= 0) {
			close(s);
		}
		return;
	}
	chmod(a.sun_path, 0600);
	struct wl_event_loop *loop = wl_display_get_event_loop(wl_display);
	wl_event_loop_add_fd(loop, s, WL_EVENT_READABLE, ahb_listen_event, loop);
	wlr_log(WLR_INFO, "hybris: client buffers (linux-dmabuf) accepted through %s", a.sun_path);
}

static void *remote_ahb_from_fd(int fd) {
	struct stat st;
	if (fstat(fd, &st) != 0) {
		return NULL;
	}
	for (int pass = 0; pass < 2; pass++) {
		for (struct remote_ahb *r = remote_ahbs; r; r = r->next) {
			if (r->ino == st.st_ino && r->dev == st.st_dev) {
				return r->ahb;
			}
		}
		/* The client sends the buffer before its wl_buffer exists, but we may not have read it yet. */
		for (struct ahb_conn *c = ahb_conns, *next; c; c = next) {
			next = c->next;
			if (!ahb_conn_read(c)) {
				ahb_conn_close(c);
			}
		}
	}
	return NULL;
}

EGLImageKHR wlr_hybris_create_image(EGLDisplay display, int dmabuf_fd) {
	static PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC get_cb;
	static PFNEGLCREATEIMAGEKHRPROC create_image;
	if (!get_cb) {
		get_cb = (void *)eglGetProcAddress("eglGetNativeClientBufferANDROID");
		create_image = (void *)eglGetProcAddress("eglCreateImageKHR");
	}
	const EGLint attribs[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
	void *ahb = wlr_hybris_ahb_from_dmabuf(dmabuf_fd);
	if (!ahb) {
		ahb = remote_ahb_from_fd(dmabuf_fd);
	}
	if (ahb) {
		return create_image(display, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID, get_cb(ahb), attribs);
	}
	/* A GPU client's android_wlegl wl_buffer: libhybris maps EGL_WAYLAND_BUFFER_WL to its native buffer. */
	struct wl_resource *res = client_resource_from_fd(dmabuf_fd);
	if (res) {
		return create_image(display, EGL_NO_CONTEXT, EGL_WAYLAND_BUFFER_WL, (EGLClientBuffer)res, attribs);
	}
	wlr_log(WLR_ERROR, "hybris: dma-buf fd %d is neither a hybris allocation nor a GPU client buffer", dmabuf_fd);
	return EGL_NO_IMAGE_KHR;
}

/* --- GPU clients (libhybris wayland-egl, android_wlegl protocol) ---
 * eglBindWaylandDisplayWL makes libhybris offer android_wlegl; clients' wl_buffers then carry Android native
 * buffers. wlroots only knows buffer types through dma-buf attributes, so each such buffer gets a placeholder
 * memfd as its "dma-buf"; wlr_hybris_create_image() maps it back to the wl_resource. */

static EGLDisplay hybris_display = EGL_NO_DISPLAY;
static hybris_query_wl_buffer_fn query_wl_buffer;

struct hybris_client_buffer {
	struct wlr_buffer base;
	struct wl_resource *resource;
	struct wl_listener resource_destroy;
	struct wl_listener release;
	ino_t ino;
	struct wlr_dmabuf_attributes dmabuf;
	struct hybris_client_buffer *next;
};
static struct hybris_client_buffer *client_buffers;

static struct wl_resource *client_resource_from_fd(int fd) {
	struct stat st;
	if (fstat(fd, &st) != 0) {
		return NULL;
	}
	for (struct hybris_client_buffer *b = client_buffers; b; b = b->next) {
		if (b->ino == st.st_ino) {
			return b->resource;
		}
	}
	return NULL;
}

static const struct wlr_buffer_impl client_buffer_impl;

static void client_buffer_destroy(struct wlr_buffer *wlr_buffer) {
	struct hybris_client_buffer *buf = wl_container_of(wlr_buffer, buf, base);
	for (struct hybris_client_buffer **p = &client_buffers; *p; p = &(*p)->next) {
		if (*p == buf) {
			*p = buf->next;
			break;
		}
	}
	if (buf->resource) {
		wl_list_remove(&buf->resource_destroy.link);
	}
	wl_list_remove(&buf->release.link);
	wlr_buffer_finish(wlr_buffer);
	close(buf->dmabuf.fd[0]);
	free(buf);
}

static bool client_buffer_get_dmabuf(struct wlr_buffer *wlr_buffer, struct wlr_dmabuf_attributes *attribs) {
	struct hybris_client_buffer *buf = wl_container_of(wlr_buffer, buf, base);
	*attribs = buf->dmabuf;
	return true;
}

static const struct wlr_buffer_impl client_buffer_impl = {
	.destroy = client_buffer_destroy,
	.get_dmabuf = client_buffer_get_dmabuf,
};

static void client_buffer_handle_resource_destroy(struct wl_listener *listener, void *data) {
	struct hybris_client_buffer *buf = wl_container_of(listener, buf, resource_destroy);
	wl_list_remove(&buf->resource_destroy.link);
	buf->resource = NULL;
	wlr_buffer_drop(&buf->base);
}

static void client_buffer_handle_release(struct wl_listener *listener, void *data) {
	struct hybris_client_buffer *buf = wl_container_of(listener, buf, release);
	if (buf->resource) {
		wl_buffer_send_release(buf->resource);
	}
}

static bool client_buffer_is_instance(struct wl_resource *resource) {
	EGLint w;
	/* libhybris (patched in scripts/62) answers only for its own android_wlegl wl_buffers. */
	return query_wl_buffer && query_wl_buffer(hybris_display, resource, EGL_WIDTH, &w);
}

static struct wlr_buffer *client_buffer_from_resource(struct wl_resource *resource) {
	struct wl_listener *l = wl_resource_get_destroy_listener(resource, client_buffer_handle_resource_destroy);
	if (l) {
		struct hybris_client_buffer *buf = wl_container_of(l, buf, resource_destroy);
		return &buf->base;
	}
	EGLint w = 0, h = 0, fmt = EGL_TEXTURE_RGBA;
	query_wl_buffer(hybris_display, resource, EGL_WIDTH, &w);
	query_wl_buffer(hybris_display, resource, EGL_HEIGHT, &h);
	query_wl_buffer(hybris_display, resource, EGL_TEXTURE_FORMAT, &fmt);
	int fd = memfd_create("hybris-wl-buffer", MFD_CLOEXEC);
	struct stat st;
	if (fd < 0 || fstat(fd, &st) != 0) {
		wlr_log_errno(WLR_ERROR, "hybris: memfd for a client buffer");
		if (fd >= 0) {
			close(fd);
		}
		return NULL;
	}
	struct hybris_client_buffer *buf = calloc(1, sizeof(*buf));
	if (!buf) {
		close(fd);
		return NULL;
	}
	wlr_buffer_init(&buf->base, &client_buffer_impl, w, h);
	buf->resource = resource;
	buf->ino = st.st_ino;
	buf->dmabuf = (struct wlr_dmabuf_attributes){
		.width = w, .height = h,
		.format = fmt == EGL_TEXTURE_RGB ? DRM_FORMAT_XBGR8888 : DRM_FORMAT_ABGR8888,
		.modifier = DRM_FORMAT_MOD_INVALID, .n_planes = 1,
		.offset = { 0 }, .stride = { (uint32_t)w * 4 }, .fd = { fd },
	};
	buf->resource_destroy.notify = client_buffer_handle_resource_destroy;
	wl_resource_add_destroy_listener(resource, &buf->resource_destroy);
	buf->release.notify = client_buffer_handle_release;
	wl_signal_add(&buf->base.events.release, &buf->release);
	buf->next = client_buffers;
	client_buffers = buf;
	wlr_log(WLR_DEBUG, "hybris: GPU client buffer %dx%d (texture format 0x%x)", w, h, fmt);
	return &buf->base;
}

static const struct wlr_buffer_resource_interface client_buffer_resource_interface = {
	.name = "hybris_android_wlegl",
	.is_instance = client_buffer_is_instance,
	.from_resource = client_buffer_from_resource,
};

void wlr_hybris_bind_wl_display(struct wl_display *wl_display) {
	if (hybris_display == EGL_NO_DISPLAY) {
		return;
	}
	hybris_bind_wl_display_fn bind = (void *)eglGetProcAddress("eglBindWaylandDisplayWL");
	query_wl_buffer = (void *)eglGetProcAddress("eglQueryWaylandBufferWL");
	if (!bind || !query_wl_buffer || !bind(hybris_display, wl_display)) {
		wlr_log(WLR_ERROR, "hybris: eglBindWaylandDisplayWL failed; GPU clients unavailable");
		query_wl_buffer = NULL;
		return;
	}
	wlr_buffer_register_resource_interface(&client_buffer_resource_interface);
	wlr_log(WLR_INFO, "hybris: android_wlegl bound; GPU clients can render with the Mali GPU");
	ahb_listen(wl_display);
}

/* linux-dmabuf needs a DRM device for its feedback; the panel's card0 stands in (it has no render node). */
int wlr_hybris_dup_drm_fd(void) {
	return open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
}

/* --- allocator --- */

static const struct wlr_buffer_impl buffer_impl;

static void buffer_destroy(struct wlr_buffer *wlr_buffer) {
	struct hybris_buffer *buf = wl_container_of(wlr_buffer, buf, base);
	for (struct hybris_buffer **p = &registry; *p; p = &(*p)->next) {
		if (*p == buf) {
			*p = buf->next;
			break;
		}
	}
	close(buf->dmabuf.fd[0]);
	AHB_release(buf->ahb);
	free(buf);
}

static bool buffer_get_dmabuf(struct wlr_buffer *wlr_buffer, struct wlr_dmabuf_attributes *attribs) {
	struct hybris_buffer *buf = wl_container_of(wlr_buffer, buf, base);
	*attribs = buf->dmabuf;
	return true;
}

static const struct wlr_buffer_impl buffer_impl = {
	.destroy = buffer_destroy,
	.get_dmabuf = buffer_get_dmabuf,
};

static uint32_t ahb_format(uint32_t drm) {
	switch (drm) {
	case DRM_FORMAT_ABGR8888: return 1; /* R8G8B8A8 */
	case DRM_FORMAT_XBGR8888: return 1; /* R8G8B8A8 (verified linear; alpha ignored) */
	case DRM_FORMAT_ARGB8888:
	case DRM_FORMAT_XRGB8888: return 5; /* B8G8R8A8 */
	default: return 0;
	}
}

static struct wlr_buffer *allocator_create_buffer(struct wlr_allocator *alloc, int width, int height,
		const struct wlr_drm_format *format) {
	uint32_t f = ahb_format(format->format);
	if (!f) {
		wlr_log(WLR_ERROR, "hybris: unsupported format 0x%08x", format->format);
		return NULL;
	}
	struct hybris_buffer *buf = calloc(1, sizeof(*buf));
	if (!buf) {
		return NULL;
	}
	AHBDesc de = { .width = width, .height = height, .layers = 1, .format = f, .usage = AHB_USAGE };
	int r = AHB_allocate(&de, &buf->ahb);
	if (r != 0) {
		wlr_log(WLR_ERROR, "hybris: AHardwareBuffer_allocate %dx%d format %u failed: %d", width, height, f, r);
		free(buf);
		return NULL;
	}
	AHB_describe(buf->ahb, &de);
	const NativeHandle *nh = AHB_getNativeHandle(buf->ahb);
	int dfd = -1;
	for (int k = 0; k < nh->numFds && dfd < 0; k++) {
		char p[64], l[64] = "";
		snprintf(p, sizeof(p), "/proc/self/fd/%d", nh->data[k]);
		ssize_t n = readlink(p, l, sizeof(l) - 1);
		if (n > 0 && strncmp(l, "/dmabuf:", 8) == 0) {
			dfd = nh->data[k];
		}
	}
	if (dfd < 0) {
		wlr_log(WLR_ERROR, "hybris: no dma-buf fd in the AHardwareBuffer native handle");
		AHB_release(buf->ahb);
		free(buf);
		return NULL;
	}
	struct stat st;
	fstat(dfd, &st);
	buf->ino = st.st_ino;
	buf->dmabuf = (struct wlr_dmabuf_attributes){
		.width = width, .height = height, .format = format->format,
		.modifier = DRM_FORMAT_MOD_INVALID, .n_planes = 1,
		.offset = { 0 }, .stride = { de.stride * 4 }, .fd = { dup(dfd) },
	};
	wlr_buffer_init(&buf->base, &buffer_impl, width, height);
	buf->next = registry;
	registry = buf;
	wlr_log(WLR_DEBUG, "hybris: allocated %dx%d fmt 0x%08x stride %u", width, height, format->format, de.stride);
	return &buf->base;
}

static void allocator_destroy(struct wlr_allocator *alloc) {
	free(alloc);
}

static const struct wlr_allocator_interface allocator_impl = {
	.create_buffer = allocator_create_buffer,
	.destroy = allocator_destroy,
};

struct wlr_allocator *wlr_hybris_allocator_create(void) {
	if (!load_ahb()) {
		return NULL;
	}
	struct wlr_allocator *alloc = calloc(1, sizeof(*alloc));
	if (!alloc) {
		return NULL;
	}
	wlr_allocator_init(alloc, &allocator_impl, WLR_BUFFER_CAP_DMABUF);
	wlr_log(WLR_INFO, "hybris: using the AHardwareBuffer allocator");
	return alloc;
}

/* --- renderer --- */

struct wlr_renderer *wlr_hybris_renderer_create(void) {
	if (!load_ahb()) {
		return NULL;
	}
	/* Warm-up allocation before EGL starts (see the gotcha at the top). */
	AHBDesc warm = { .width = 64, .height = 64, .layers = 1, .format = 1, .usage = AHB_USAGE };
	void *warm_buf = NULL;
	if (AHB_allocate(&warm, &warm_buf) == 0) {
		AHB_release(warm_buf);
	} else {
		wlr_log(WLR_ERROR, "hybris: warm-up AHardwareBuffer allocation failed (allocator HAL not running?)");
	}
	EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL)) {
		wlr_log(WLR_ERROR, "hybris: EGL init failed");
		return NULL;
	}
	eglBindAPI(EGL_OPENGL_ES_API);
	const EGLint attribs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attribs);
	if (ctx == EGL_NO_CONTEXT) {
		wlr_log(WLR_ERROR, "hybris: eglCreateContext failed 0x%x", eglGetError());
		return NULL;
	}
	hybris_display = dpy;
	struct wlr_egl *egl = wlr_egl_create_with_context(dpy, ctx);
	if (!egl) {
		return NULL;
	}
	struct wlr_renderer *renderer = wlr_gles2_renderer_create(egl);
	if (renderer) {
		wlr_log(WLR_INFO, "hybris: GLES2 renderer on libhybris EGL");
	}
	return renderer;
}
