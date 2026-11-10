/* archpad-gbm: a small libgbm for Chromium's GPU process on the Moto Pad (no DRM render node, no Mesa driver).
 *
 * Chromium presents GPU-composited frames on Wayland only as dma-bufs it allocates through GBM, and its hardware
 * video decoders also take their frames from GBM. Mesa's libgbm needs a render-node driver this tablet does not
 * have, so this library implements the GBM calls Chromium makes on top of Android's AHardwareBuffer allocator
 * (through libhybris, like the compositor's own buffers in wlroots-pad/render/hybris.c):
 *  - gbm_bo_create*: allocates an AHardwareBuffer and exposes its dma-buf (linear, one plane per format plane).
 *  - archpad_gbm_ahb_from_dmabuf_fd(): libhybris' EGL (scripts/libhybris-dmabuf-import.pl) calls this to turn a
 *    dma-buf back into its AHardwareBuffer, since the Mali EGL cannot import dma-bufs itself.
 *  - Each new buffer is also sent to the compositor (AHardwareBuffer_sendHandleToUnixSocket over
 *    $XDG_RUNTIME_DIR/archpad-ahb.sock), which imports Chromium's wl_buffers the same way; destroyed buffers are
 *    announced on a second connection so the compositor can drop its reference.
 *  - gbm_bo_import keeps the fds (and finds the AHardwareBuffer when the dma-buf is one of ours); gbm_bo_map mmaps
 *    the dma-buf.
 * Used by config/chromium/chromium-gpu: LD_PRELOAD of this file (soname libgbm.so.1, so it also satisfies Chromium's
 * libgbm dependency) plus --render-node-override=/dev/dri/card0. Debug log: ARCHPAD_GBM_DEBUG=1.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <drm_fourcc.h>
#include <errno.h>
#include <fcntl.h>
#include <gbm.h>
#include <linux/dma-buf.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define EXPORT __attribute__((visibility("default")))

typedef struct { uint32_t width, height, layers, format; uint64_t usage; uint32_t stride, rfu0; uint64_t rfu1; } AHBDesc;
typedef struct { int version, numFds, numInts, data[]; } NativeHandle;
typedef struct { void *data; uint32_t pixelStride, rowStride; } AHBPlane;
typedef struct { uint32_t planeCount; AHBPlane planes[4]; } AHBPlanes;

static int (*AHB_allocate)(const AHBDesc *, void **);
static void (*AHB_acquire)(void *);
static void (*AHB_release)(void *);
static void (*AHB_describe)(const void *, AHBDesc *);
static const NativeHandle *(*AHB_getNativeHandle)(const void *);
static int (*AHB_send)(const void *, int);
static int (*AHB_lockPlanes)(void *, uint64_t, int32_t, const void *, AHBPlanes *);
static int (*AHB_unlock)(void *, int32_t *);

/* AHardwareBuffer usage: CPU_READ_RARELY keeps buffers linear (Chromium expects a plain stride/offset layout). */
#define AHB_USAGE (2ULL | (1ULL << 8) /* GPU_SAMPLED */ | (1ULL << 9) /* GPU_FRAMEBUFFER */ | \
                   (1ULL << 11) /* COMPOSER_OVERLAY */)
#define AHB_USAGE_VIDEO (2ULL | (2ULL << 4) /* CPU_WRITE_RARELY */ | (1ULL << 8) /* GPU_SAMPLED */)

struct gbm_device {
	int fd;
};

struct gbm_bo {
	struct gbm_device *dev;
	void *ahb;                 /* NULL for imports of foreign dma-bufs */
	int fd[4];                 /* per plane (dups of one dma-buf for our buffers) */
	ino_t ino;
	dev_t devno;
	uint32_t width, height, format, flags;
	int nplanes;
	int nv21;                  /* NV12 request, but the allocator's buffer has V before U */
	uint32_t stride[4], offset[4];
	uint64_t modifier;
	void *user_data;
	void (*destroy_user_data)(struct gbm_bo *, void *);
	struct gbm_bo *next;
};

struct map_info {
	void *base;
	size_t len;
	int fd;
	uint32_t flags;
};

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static struct gbm_bo *bos;
static int debug = -1;

static void dbg(const char *fmt, ...) {
	if (debug < 0) {
		const char *e = getenv("ARCHPAD_GBM_DEBUG");
		debug = e && *e == '1';
	}
	if (!debug) {
		return;
	}
	va_list ap;
	va_start(ap, fmt);
	fprintf(stderr, "[archpad-gbm %d] ", getpid());
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
}

static int load_ahb(void) {
	if (AHB_allocate) {
		return 1;
	}
	void *hc = dlopen("libhybris-common.so.1", RTLD_NOW | RTLD_GLOBAL);
	if (!hc) {
		hc = dlopen("/usr/local/hybris/lib/libhybris-common.so.1", RTLD_NOW | RTLD_GLOBAL);
	}
	if (!hc) {
		fprintf(stderr, "archpad-gbm: cannot load libhybris-common: %s\n", dlerror());
		return 0;
	}
	void *(*a_dlopen)(const char *, int) = dlsym(hc, "android_dlopen");
	void *(*a_dlsym)(void *, const char *) = dlsym(hc, "android_dlsym");
	void *nw = a_dlopen ? a_dlopen("/system/lib64/libnativewindow.so", RTLD_NOW) : NULL;
	if (!nw) {
		fprintf(stderr, "archpad-gbm: cannot load Android libnativewindow\n");
		return 0;
	}
	AHB_acquire = a_dlsym(nw, "AHardwareBuffer_acquire");
	AHB_release = a_dlsym(nw, "AHardwareBuffer_release");
	AHB_describe = a_dlsym(nw, "AHardwareBuffer_describe");
	AHB_getNativeHandle = a_dlsym(nw, "AHardwareBuffer_getNativeHandle");
	AHB_send = a_dlsym(nw, "AHardwareBuffer_sendHandleToUnixSocket");
	AHB_lockPlanes = a_dlsym(nw, "AHardwareBuffer_lockPlanes");
	AHB_unlock = a_dlsym(nw, "AHardwareBuffer_unlock");
	void *alloc = a_dlsym(nw, "AHardwareBuffer_allocate");
	if (!alloc || !AHB_acquire || !AHB_release || !AHB_describe || !AHB_getNativeHandle) {
		fprintf(stderr, "archpad-gbm: AHardwareBuffer functions missing\n");
		return 0;
	}
	AHB_allocate = alloc;
	return 1;
}

/* --- compositor link: new buffers go to the compositor so it can import Chromium's wl_buffers --- */

static int sock_new = -2, sock_free = -2;

static int connect_kind(char kind) {
	const char *dir = getenv("XDG_RUNTIME_DIR");
	if (!dir) {
		return -1;
	}
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	snprintf(a.sun_path, sizeof(a.sun_path), "%s/archpad-ahb.sock", dir);
	int s = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
	if (s < 0) {
		return -1;
	}
	if (connect(s, (struct sockaddr *)&a, sizeof(a)) != 0 || send(s, &kind, 1, MSG_NOSIGNAL) != 1) {
		dbg("no compositor buffer socket at %s (%s)", a.sun_path, strerror(errno));
		close(s);
		return -1;
	}
	return s;
}

static void announce_new(void *ahb) {
	if (sock_new == -2) {
		sock_new = connect_kind('A');
	}
	if (sock_new >= 0 && AHB_send && AHB_send(ahb, sock_new) != 0) {
		dbg("sending a buffer to the compositor failed");
		close(sock_new);
		sock_new = -1;
	}
}

static void announce_free(dev_t devno, ino_t ino) {
	if (sock_new < 0) {
		return;
	}
	if (sock_free == -2) {
		sock_free = connect_kind('F');
	}
	uint64_t msg[2] = { devno, ino };
	if (sock_free >= 0 && send(sock_free, msg, sizeof(msg), MSG_NOSIGNAL) != sizeof(msg)) {
		close(sock_free);
		sock_free = -1;
	}
}

/* --- formats --- */

struct fmt {
	uint32_t drm, ahb, bpp;   /* bpp of plane 0; NV12 has a half-height interleaved chroma plane */
	int planes;
};
static const struct fmt fmts[] = {
	{ DRM_FORMAT_ARGB8888, 5 /* B8G8R8A8 */, 32, 1 },
	{ DRM_FORMAT_XRGB8888, 5, 32, 1 },
	{ DRM_FORMAT_ABGR8888, 1 /* R8G8B8A8 */, 32, 1 },
	{ DRM_FORMAT_XBGR8888, 1, 32, 1 },
	{ DRM_FORMAT_NV12, 0x23 /* Y8Cb8Cr8_420; ARCHPAD_GBM_NV12_FORMAT overrides */, 8, 2 },
};

static const struct fmt *find_fmt(uint32_t drm) {
	for (size_t i = 0; i < sizeof(fmts) / sizeof(fmts[0]); i++) {
		if (fmts[i].drm == drm) {
			return &fmts[i];
		}
	}
	return NULL;
}

/* --- registry --- */

static void reg_add(struct gbm_bo *bo) {
	pthread_mutex_lock(&lock);
	bo->next = bos;
	bos = bo;
	pthread_mutex_unlock(&lock);
}

static void reg_del(struct gbm_bo *bo) {
	pthread_mutex_lock(&lock);
	for (struct gbm_bo **p = &bos; *p; p = &(*p)->next) {
		if (*p == bo) {
			*p = bo->next;
			break;
		}
	}
	pthread_mutex_unlock(&lock);
}

static void *ahb_by_ino(dev_t devno, ino_t ino) {
	void *r = NULL;
	pthread_mutex_lock(&lock);
	for (struct gbm_bo *b = bos; b; b = b->next) {
		if (b->ahb && b->ino == ino && b->devno == devno) {
			r = b->ahb;
			break;
		}
	}
	pthread_mutex_unlock(&lock);
	return r;
}

/* For whoever fills a YUV buffer from the CPU (the V4L2 shim): luma stride, chroma offset and byte order of the
 * buffer behind a dma-buf fd. Returns 0, or -1 if the dma-buf is not one of ours. */
EXPORT int archpad_gbm_dmabuf_layout(int fd, uint32_t *ystride, uint32_t *uvoff, int *nv21) {
	struct stat st;
	if (fstat(fd, &st) != 0) {
		return -1;
	}
	int r = -1;
	pthread_mutex_lock(&lock);
	for (struct gbm_bo *b = bos; b; b = b->next) {
		if (b->ahb && b->ino == st.st_ino && b->devno == st.st_dev && b->nplanes == 2) {
			*ystride = b->stride[0];
			*uvoff = b->offset[1];
			*nv21 = b->nv21;
			r = 0;
			break;
		}
	}
	pthread_mutex_unlock(&lock);
	return r;
}

EXPORT void *archpad_gbm_ahb_from_dmabuf_fd(int fd) {
	struct stat st;
	if (fstat(fd, &st) != 0) {
		return NULL;
	}
	void *ahb = ahb_by_ino(st.st_dev, st.st_ino);
	dbg("EGL import fd %d ino %lu -> %p", fd, (unsigned long)st.st_ino, ahb);
	return ahb;
}

/* --- device --- */

EXPORT struct gbm_device *gbm_create_device(int fd) {
	if (!load_ahb()) {
		return NULL;
	}
	/* The first AHardwareBuffer allocation loads the gralloc mapper; doing it after EGL is initialized breaks EGL
	 * (see wlroots-pad/render/hybris.c). Chromium creates the GBM device before EGL, so warm up here. */
	AHBDesc warm = { .width = 64, .height = 64, .layers = 1, .format = 1, .usage = AHB_USAGE };
	void *w = NULL;
	if (AHB_allocate(&warm, &w) == 0) {
		AHB_release(w);
	} else {
		fprintf(stderr, "archpad-gbm: AHardwareBuffer allocation failed (allocator service not running?)\n");
		return NULL;
	}
	struct gbm_device *dev = calloc(1, sizeof(*dev));
	if (dev) {
		dev->fd = fd;
	}
	dbg("device created on fd %d", fd);
	return dev;
}

EXPORT void gbm_device_destroy(struct gbm_device *dev) {
	free(dev);
}

EXPORT int gbm_device_get_fd(struct gbm_device *dev) {
	return dev->fd;
}

EXPORT const char *gbm_device_get_backend_name(struct gbm_device *dev) {
	return "archpad-ahb";
}

EXPORT int gbm_device_is_format_supported(struct gbm_device *dev, uint32_t format, uint32_t usage) {
	const struct fmt *f = find_fmt(format);
	if (!f) {
		return 0;
	}
	/* Only RGB formats can be scanout/rendering targets. */
	if (f->planes > 1 && (usage & (GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING))) {
		return 0;
	}
	return 1;
}

EXPORT int gbm_device_get_format_modifier_plane_count(struct gbm_device *dev, uint32_t format, uint64_t modifier) {
	const struct fmt *f = find_fmt(format);
	return f ? f->planes : -1;
}

/* --- buffers --- */

static int dmabuf_of(void *ahb) {
	const NativeHandle *nh = AHB_getNativeHandle(ahb);
	for (int k = 0; nh && k < nh->numFds; k++) {
		char p[64], l[64] = "";
		snprintf(p, sizeof(p), "/proc/self/fd/%d", nh->data[k]);
		ssize_t n = readlink(p, l, sizeof(l) - 1);
		if (n > 0 && strncmp(l, "/dmabuf:", 8) == 0) {
			return nh->data[k];
		}
	}
	return -1;
}

static struct gbm_bo *bo_alloc(struct gbm_device *dev, uint32_t w, uint32_t h, uint32_t format, uint32_t flags) {
	const struct fmt *f = find_fmt(format);
	if (!f || !w || !h) {
		errno = EINVAL;
		return NULL;
	}
	uint32_t af = f->ahb;
	if (f->planes > 1 && getenv("ARCHPAD_GBM_NV12_FORMAT")) af = strtoul(getenv("ARCHPAD_GBM_NV12_FORMAT"), NULL, 0);
	AHBDesc de = { .width = w, .height = h, .layers = 1, .format = af,
	               .usage = f->planes > 1 ? AHB_USAGE_VIDEO : AHB_USAGE };
	void *ahb = NULL;
	int r = AHB_allocate(&de, &ahb);
	if (r != 0) {
		fprintf(stderr, "archpad-gbm: AHardwareBuffer_allocate %ux%u fmt %u failed: %d\n", w, h, af, r);
		errno = ENOMEM;
		return NULL;
	}
	AHB_describe(ahb, &de);
	int dfd = dmabuf_of(ahb);
	if (dfd < 0) {
		fprintf(stderr, "archpad-gbm: no dma-buf in the AHardwareBuffer\n");
		AHB_release(ahb);
		errno = EIO;
		return NULL;
	}
	struct gbm_bo *bo = calloc(1, sizeof(*bo));
	if (!bo) {
		AHB_release(ahb);
		return NULL;
	}
	struct stat st;
	fstat(dfd, &st);
	*bo = (struct gbm_bo){ .dev = dev, .ahb = ahb, .ino = st.st_ino, .devno = st.st_dev, .width = w, .height = h,
	                       .format = format, .flags = flags, .nplanes = f->planes, .modifier = DRM_FORMAT_MOD_LINEAR };
	if (f->planes == 1) {
		bo->stride[0] = de.stride * (f->bpp / 8);
	} else {
		/* Real plane layout from the allocator (gralloc may pad the luma plane). */
		AHBPlanes pl = { 0 };
		if (!AHB_lockPlanes || AHB_lockPlanes(ahb, 2ULL << 4, -1, NULL, &pl) != 0 || pl.planeCount < 3) {
			fprintf(stderr, "archpad-gbm: cannot read the NV12 plane layout\n");
			AHB_release(ahb);
			free(bo);
			errno = EIO;
			return NULL;
		}
		uint8_t *y = pl.planes[0].data, *u = pl.planes[1].data, *v = pl.planes[2].data;
		AHB_unlock(ahb, NULL);
		/* MediaTek's allocator gives NV21 (V first) for every 4:2:0 semi-planar request; there is no NV12. The GPU
		 * samples the buffer by its real format, so it is still offered as NV12 and whoever fills it (the V4L2
		 * shim) asks archpad_gbm_dmabuf_layout() for the byte order. */
		if (pl.planes[1].pixelStride != 2 || (v != u + 1 && u != v + 1)) {
			fprintf(stderr, "archpad-gbm: allocator's YUV layout is not semi-planar (chroma step %u, v-u %td)\n",
				pl.planes[1].pixelStride, v - u);
			AHB_release(ahb);
			free(bo);
			errno = EINVAL;
			return NULL;
		}
		bo->nv21 = u == v + 1;
		bo->stride[0] = pl.planes[0].rowStride;
		bo->stride[1] = pl.planes[1].rowStride;
		bo->offset[1] = (uint32_t)((bo->nv21 ? v : u) - y);
	}
	for (int i = 0; i < bo->nplanes; i++) {
		bo->fd[i] = fcntl(dfd, F_DUPFD_CLOEXEC, 0);
	}
	for (int i = bo->nplanes; i < 4; i++) {
		bo->fd[i] = -1;
	}
	reg_add(bo);
	announce_new(ahb);
	dbg("bo %p %ux%u %.4s%s stride %u/%u offset %u ino %lu", (void *)bo, w, h, (char *)&format, bo->nv21 ? " (NV21)" : "", bo->stride[0],
	    bo->stride[1], bo->offset[1], (unsigned long)bo->ino);
	return bo;
}

EXPORT struct gbm_bo *gbm_bo_create(struct gbm_device *dev, uint32_t w, uint32_t h, uint32_t format, uint32_t flags) {
	return bo_alloc(dev, w, h, format, flags);
}

static int mods_ok(const uint64_t *mods, unsigned int count) {
	if (!mods || !count) {
		return 1;
	}
	for (unsigned int i = 0; i < count; i++) {
		if (mods[i] == DRM_FORMAT_MOD_LINEAR || mods[i] == DRM_FORMAT_MOD_INVALID) {
			return 1;
		}
	}
	return 0;
}

EXPORT struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *dev, uint32_t w, uint32_t h, uint32_t format,
		const uint64_t *mods, const unsigned int count) {
	if (!mods_ok(mods, count)) {
		errno = ENOSYS;
		return NULL;
	}
	struct gbm_bo *bo = bo_alloc(dev, w, h, format, GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
	if (bo && count && mods) {
		int linear = 0;
		for (unsigned int i = 0; i < count; i++) {
			linear |= mods[i] == DRM_FORMAT_MOD_LINEAR;
		}
		bo->modifier = linear ? DRM_FORMAT_MOD_LINEAR : DRM_FORMAT_MOD_INVALID;
	}
	return bo;
}

EXPORT struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *dev, uint32_t w, uint32_t h, uint32_t format,
		const uint64_t *mods, const unsigned int count, uint32_t flags) {
	return gbm_bo_create_with_modifiers(dev, w, h, format, mods, count);
}

EXPORT struct gbm_bo *gbm_bo_import(struct gbm_device *dev, uint32_t type, void *buffer, uint32_t flags) {
	struct gbm_bo *bo = calloc(1, sizeof(*bo));
	if (!bo) {
		return NULL;
	}
	bo->dev = dev;
	bo->flags = flags;
	for (int i = 0; i < 4; i++) {
		bo->fd[i] = -1;
	}
	if (type == GBM_BO_IMPORT_FD) {
		struct gbm_import_fd_data *d = buffer;
		bo->width = d->width;
		bo->height = d->height;
		bo->format = d->format;
		bo->nplanes = 1;
		bo->stride[0] = d->stride;
		bo->fd[0] = fcntl(d->fd, F_DUPFD_CLOEXEC, 0);
		bo->modifier = DRM_FORMAT_MOD_INVALID;
	} else if (type == GBM_BO_IMPORT_FD_MODIFIER) {
		struct gbm_import_fd_modifier_data *d = buffer;
		if (!find_fmt(d->format) || d->num_fds < 1 || d->num_fds > 4) {
			free(bo);
			errno = EINVAL;
			return NULL;
		}
		bo->width = d->width;
		bo->height = d->height;
		bo->format = d->format;
		bo->nplanes = d->num_fds;
		bo->modifier = d->modifier;
		for (unsigned int i = 0; i < d->num_fds; i++) {
			bo->fd[i] = fcntl(d->fds[i], F_DUPFD_CLOEXEC, 0);
			bo->stride[i] = d->strides[i];
			bo->offset[i] = d->offsets[i];
		}
	} else {
		free(bo);
		errno = ENOSYS;
		return NULL;
	}
	struct stat st;
	if (bo->fd[0] < 0 || fstat(bo->fd[0], &st) != 0) {
		for (int i = 0; i < 4; i++) {
			if (bo->fd[i] >= 0) {
				close(bo->fd[i]);
			}
		}
		free(bo);
		errno = EBADF;
		return NULL;
	}
	bo->ino = st.st_ino;
	bo->devno = st.st_dev;
	bo->ahb = ahb_by_ino(st.st_dev, st.st_ino);
	if (bo->ahb) {
		AHB_acquire(bo->ahb);
	}
	reg_add(bo);
	dbg("import %ux%u %.4s planes %d ino %lu%s", bo->width, bo->height, (char *)&bo->format, bo->nplanes,
	    (unsigned long)bo->ino, bo->ahb ? " (ours)" : "");
	return bo;
}

EXPORT void gbm_bo_destroy(struct gbm_bo *bo) {
	if (!bo) {
		return;
	}
	if (bo->destroy_user_data) {
		bo->destroy_user_data(bo, bo->user_data);
	}
	reg_del(bo);
	/* The last holder of one of our buffers tells the compositor it can let go too. */
	if (bo->ahb && !ahb_by_ino(bo->devno, bo->ino)) {
		announce_free(bo->devno, bo->ino);
	}
	for (int i = 0; i < 4; i++) {
		if (bo->fd[i] >= 0) {
			close(bo->fd[i]);
		}
	}
	if (bo->ahb) {
		AHB_release(bo->ahb);
	}
	free(bo);
}

EXPORT uint32_t gbm_bo_get_width(struct gbm_bo *bo) { return bo->width; }
EXPORT uint32_t gbm_bo_get_height(struct gbm_bo *bo) { return bo->height; }
EXPORT uint32_t gbm_bo_get_stride(struct gbm_bo *bo) { return bo->stride[0]; }
EXPORT uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane) {
	return plane >= 0 && plane < bo->nplanes ? bo->stride[plane] : 0;
}
EXPORT uint32_t gbm_bo_get_format(struct gbm_bo *bo) { return bo->format; }
EXPORT uint32_t gbm_bo_get_bpp(struct gbm_bo *bo) {
	const struct fmt *f = find_fmt(bo->format);
	return f ? f->bpp : 0;
}
EXPORT uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane) {
	return plane >= 0 && plane < bo->nplanes ? bo->offset[plane] : 0;
}
EXPORT struct gbm_device *gbm_bo_get_device(struct gbm_bo *bo) { return bo->dev; }
EXPORT uint64_t gbm_bo_get_modifier(struct gbm_bo *bo) { return bo->modifier; }
EXPORT int gbm_bo_get_plane_count(struct gbm_bo *bo) { return bo->nplanes; }
/* No GEM handles (the dma-buf heap buffers are not DRM objects); fd functions cover everything Chromium needs. */
EXPORT union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo) { union gbm_bo_handle h = { .u64 = 0 }; return h; }
EXPORT union gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int plane) {
	union gbm_bo_handle h = { .u64 = 0 };
	return h;
}
EXPORT int gbm_bo_get_fd(struct gbm_bo *bo) { return fcntl(bo->fd[0], F_DUPFD_CLOEXEC, 0); }
EXPORT int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane) {
	if (plane < 0 || plane >= bo->nplanes || bo->fd[plane] < 0) {
		errno = EINVAL;
		return -1;
	}
	return fcntl(bo->fd[plane], F_DUPFD_CLOEXEC, 0);
}
EXPORT void gbm_bo_set_user_data(struct gbm_bo *bo, void *data, void (*destroy)(struct gbm_bo *, void *)) {
	bo->user_data = data;
	bo->destroy_user_data = destroy;
}
EXPORT void *gbm_bo_get_user_data(struct gbm_bo *bo) { return bo->user_data; }

EXPORT void *gbm_bo_map(struct gbm_bo *bo, uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t flags,
		uint32_t *stride, void **map_data) {
	off_t len = lseek(bo->fd[0], 0, SEEK_END);
	if (len <= 0) {
		return NULL;
	}
	int prot = (flags & GBM_BO_TRANSFER_READ ? PROT_READ : 0) | (flags & GBM_BO_TRANSFER_WRITE ? PROT_WRITE : 0);
	void *p = mmap(NULL, len, prot ? prot : PROT_READ, MAP_SHARED, bo->fd[0], 0);
	if (p == MAP_FAILED) {
		return NULL;
	}
	struct map_info *mi = malloc(sizeof(*mi));
	if (!mi) {
		munmap(p, len);
		return NULL;
	}
	*mi = (struct map_info){ .base = p, .len = len, .fd = bo->fd[0],
	                         .flags = (flags & GBM_BO_TRANSFER_READ ? DMA_BUF_SYNC_READ : 0) |
	                                  (flags & GBM_BO_TRANSFER_WRITE ? DMA_BUF_SYNC_WRITE : 0) };
	if (!mi->flags) {
		mi->flags = DMA_BUF_SYNC_READ;
	}
	struct dma_buf_sync s = { .flags = DMA_BUF_SYNC_START | mi->flags };
	ioctl(mi->fd, DMA_BUF_IOCTL_SYNC, &s);
	*map_data = mi;
	*stride = bo->stride[0];
	const struct fmt *f = find_fmt(bo->format);
	return (uint8_t *)p + bo->offset[0] + (size_t)y * bo->stride[0] + (size_t)x * (f ? f->bpp / 8 : 4);
}

EXPORT void gbm_bo_unmap(struct gbm_bo *bo, void *map_data) {
	struct map_info *mi = map_data;
	if (!mi) {
		return;
	}
	struct dma_buf_sync s = { .flags = DMA_BUF_SYNC_END | mi->flags };
	ioctl(mi->fd, DMA_BUF_IOCTL_SYNC, &s);
	munmap(mi->base, mi->len);
	free(mi);
}

EXPORT int gbm_bo_write(struct gbm_bo *bo, const void *buf, size_t count) {
	errno = ENOSYS;
	return -1;
}

/* Surfaces (EGL window surfaces on GBM) are not used by Chromium on Wayland. */
EXPORT struct gbm_surface *gbm_surface_create(struct gbm_device *dev, uint32_t w, uint32_t h, uint32_t format,
		uint32_t flags) {
	errno = ENOSYS;
	return NULL;
}
EXPORT struct gbm_surface *gbm_surface_create_with_modifiers(struct gbm_device *dev, uint32_t w, uint32_t h,
		uint32_t format, const uint64_t *mods, const unsigned int count) {
	errno = ENOSYS;
	return NULL;
}
EXPORT void gbm_surface_destroy(struct gbm_surface *s) {}
EXPORT struct gbm_bo *gbm_surface_lock_front_buffer(struct gbm_surface *s) { return NULL; }
EXPORT void gbm_surface_release_buffer(struct gbm_surface *s, struct gbm_bo *bo) {}
EXPORT int gbm_surface_has_free_buffers(struct gbm_surface *s) { return 0; }

EXPORT char *gbm_format_get_name(uint32_t format, struct gbm_format_name_desc *desc) {
	memcpy(desc->name, &format, 4);
	desc->name[4] = 0;
	return desc->name;
}
