// Moto Pad (archpad): LD_PRELOAD shim that makes the MediaTek V4L2 video decoder (mtk-vcodec-dec, VCP firmware)
// usable by standard stateful-decoder clients (FFmpeg *_v4l2m2m, so mpv --hwdec=v4l2m2m-copy).
//
// The vendor driver differs from what clients expect in three ways:
//  1. Bitstream (OUTPUT queue) buffers must be dma-bufs: with MMAP buffers the driver has no kernel mapping and the
//     worker drops every job ("src_addr is NULL").
//  2. Decoded frames come out only as 'M21S' (8-bit, luma in 16x32 tiles, interleaved chroma in 16x16 tiles, planes
//     back to back).
//  3. HEVC is called 'H265' instead of V4L2_PIX_FMT_HEVC.
// So the shim turns the client's MMAP queues into DMABUF queues backed by (cached) dma-heap buffers. OUTPUT buffers
// are mapped straight into the client. CAPTURE buffers are reported as NV12; the client's mmap gets a private
// linear copy that is filled (untiled) from the hardware buffer when the client dequeues it.
// Everything else (events, drain, poll) goes straight to the driver. Other devices are untouched.
// Build: gcc -O2 -shared -fPIC -o libmtk-v4l2-shim.so mtk-v4l2-shim.c -ldl -lpthread
// Use:   LD_PRELOAD=/usr/local/lib/libmtk-v4l2-shim.so mpv --hwdec=v4l2m2m-copy video.mp4
// Env:   MTK_V4L2_SHIM_DEBUG=1 logs to stderr; MTK_V4L2_SHIM_HEAP picks the dma-heap (default /dev/dma_heap/system).
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/dma-buf.h>
#include <linux/dma-heap.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#define FMT_M21S v4l2_fourcc('M', '2', '1', 'S')
#define FMT_H265 v4l2_fourcc('H', '2', '6', '5')
#define MAXBUF 32
#define MAXCTX 4
/* Fake mmap offsets handed to the client (vb2's own are 0.. for OUTPUT and 1<<30.. for CAPTURE). */
#define OFF_BASE(q) ((q) ? 0x20000000UL : 0x10000000UL)
#define OFF_STEP 0x00800000UL

static int (*real_ioctl)(int, unsigned long, ...);
static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
static int (*real_munmap)(void *, size_t);
static int (*real_close)(int);
static pthread_mutex_t lock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
static int dbg = -1;
static dev_t dec_rdev;
static int dec_rdev_known;

/* q = 0: OUTPUT (bitstream), q = 1: CAPTURE (frames). */
struct sbuf { int dfd; size_t size; void *map; void *client; };
struct squeue { int n; int faked; struct sbuf b[MAXBUF]; };
/* Decoded frames the driver returned early, waiting to be handed out in timestamp order. */
struct pend { struct v4l2_buffer b; struct v4l2_plane p[VIDEO_MAX_PLANES]; };
struct ctx {
	int fd;
	struct squeue q[2];
	uint32_t cap_w, cap_h; int cap_tiled;
	int npend, last_seen;
	struct pend pend[MAXBUF];
};
static struct ctx ctxs[MAXCTX] = { { .fd = -1 }, { .fd = -1 }, { .fd = -1 }, { .fd = -1 } };

static void logf_(const char *fmt, ...)
{
	if (dbg < 0) dbg = getenv("MTK_V4L2_SHIM_DEBUG") != NULL;
	if (!dbg) return;
	va_list ap; va_start(ap, fmt);
	fputs("[mtk-v4l2-shim] ", stderr); vfprintf(stderr, fmt, ap); fputc('\n', stderr);
	va_end(ap);
}

static void init(void)
{
	if (real_ioctl) return;
	real_ioctl = dlsym(RTLD_NEXT, "ioctl");
	real_mmap = dlsym(RTLD_NEXT, "mmap");
	real_munmap = dlsym(RTLD_NEXT, "munmap");
	real_close = dlsym(RTLD_NEXT, "close");
}

static void find_decoder(void)
{
	if (dec_rdev_known) return;
	dec_rdev_known = 1;
	DIR *d = opendir("/sys/class/video4linux");
	if (!d) return;
	struct dirent *e;
	while ((e = readdir(d))) {
		char p[300], name[64] = "", dev[32] = "";
		snprintf(p, sizeof p, "/sys/class/video4linux/%s/name", e->d_name);
		FILE *f = fopen(p, "re");
		if (!f) continue;
		if (!fgets(name, sizeof name, f)) name[0] = 0;
		fclose(f);
		if (strncmp(name, "mtk-vcodec-dec", 14)) continue;
		snprintf(p, sizeof p, "/sys/class/video4linux/%s/dev", e->d_name);
		f = fopen(p, "re");
		if (!f) continue;
		unsigned ma, mi;
		if (fgets(dev, sizeof dev, f) && sscanf(dev, "%u:%u", &ma, &mi) == 2) dec_rdev = makedev(ma, mi);
		fclose(f);
		logf_("decoder is /dev/%s (%u:%u)", e->d_name, major(dec_rdev), minor(dec_rdev));
		break;
	}
	closedir(d);
}

static struct ctx *get_ctx(int fd, int create)
{
	for (int i = 0; i < MAXCTX; i++) if (ctxs[i].fd == fd) return &ctxs[i];
	if (!create) return NULL;
	find_decoder();
	struct stat st;
	if (!dec_rdev || fstat(fd, &st) || !S_ISCHR(st.st_mode) || st.st_rdev != dec_rdev) return NULL;
	for (int i = 0; i < MAXCTX; i++)
		if (ctxs[i].fd < 0) {
			memset(&ctxs[i], 0, sizeof ctxs[i]);
			ctxs[i].fd = fd;
			logf_("tracking fd %d", fd);
			return &ctxs[i];
		}
	return NULL;
}

static int qidx(uint32_t t)
{
	if (t == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE || t == V4L2_BUF_TYPE_VIDEO_OUTPUT) return 0;
	if (t == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE || t == V4L2_BUF_TYPE_VIDEO_CAPTURE) return 1;
	return -1;
}
static int mplane(uint32_t t) { return t == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE || t == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; }

static void free_queue(struct squeue *q)
{
	for (int i = 0; i < q->n; i++) {
		struct sbuf *b = &q->b[i];
		if (b->client && b->client != b->map) real_munmap(b->client, b->size);
		if (b->map) real_munmap(b->map, b->size);
		if (b->dfd >= 0) real_close(b->dfd);
	}
	memset(q, 0, sizeof *q);
}

/* ---- formats ---- */
static uint32_t pf_to_client(uint32_t pf) { return pf == FMT_M21S ? V4L2_PIX_FMT_NV12 : pf == FMT_H265 ? V4L2_PIX_FMT_HEVC : pf; }
static uint32_t pf_to_driver(int q, uint32_t pf)
{
	if (q == 1 && pf == V4L2_PIX_FMT_NV12) return FMT_M21S;
	if (q == 0 && pf == V4L2_PIX_FMT_HEVC) return FMT_H265;
	return pf;
}

static void fmt_from_driver(struct ctx *c, struct v4l2_format *f)
{
	if (!mplane(f->type)) return;
	uint32_t pf = f->fmt.pix_mp.pixelformat;
	if (qidx(f->type) == 1) {
		c->cap_tiled = pf == FMT_M21S;
		c->cap_w = f->fmt.pix_mp.plane_fmt[0].bytesperline ? f->fmt.pix_mp.plane_fmt[0].bytesperline : f->fmt.pix_mp.width;
		c->cap_h = f->fmt.pix_mp.height;
	}
	f->fmt.pix_mp.pixelformat = pf_to_client(pf);
}

static void fmt_to_driver(struct v4l2_format *f)
{
	if (mplane(f->type)) f->fmt.pix_mp.pixelformat = pf_to_driver(qidx(f->type), f->fmt.pix_mp.pixelformat);
}

/* ---- untiling ---- */
static void detile_plane(const uint8_t *src, uint8_t *dst, uint32_t w, uint32_t h, uint32_t th)
{
	uint32_t tiles_x = w / 16;
	size_t tile = 16 * th;
	for (uint32_t ty = 0; ty < h / th; ty++) {
		const uint8_t *trow = src + (size_t)ty * tiles_x * tile;
		uint8_t *drow = dst + (size_t)ty * th * w;
		for (uint32_t tx = 0; tx < tiles_x; tx++) {
			const uint8_t *t = trow + tx * tile;          /* read each tile sequentially */
			uint8_t *d = drow + tx * 16;
			for (uint32_t r = 0; r < th; r++) memcpy(d + (size_t)r * w, t + r * 16, 16);
		}
	}
}

static void deliver_frame(struct ctx *c, struct sbuf *b, size_t used)
{
	if (!b->client || b->client == b->map) return;
	struct dma_buf_sync sy = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
	real_ioctl(b->dfd, DMA_BUF_IOCTL_SYNC, &sy);
	uint32_t w = c->cap_w, h = c->cap_h;
	size_t ys = (size_t)w * h;
	if (c->cap_tiled && !(w % 16) && !(h % 32) && ys + ys / 2 <= b->size) {
		detile_plane(b->map, b->client, w, h, 32);
		detile_plane((const uint8_t *)b->map + ys, (uint8_t *)b->client + ys, w, h / 2, 16);
	} else {
		memcpy(b->client, b->map, used && used <= b->size ? used : b->size);
	}
	sy.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
	real_ioctl(b->dfd, DMA_BUF_IOCTL_SYNC, &sy);
}

/* ---- buffers ---- */
static int heap_open(void)
{
	const char *h = getenv("MTK_V4L2_SHIM_HEAP");
	return open(h ? h : "/dev/dma_heap/system", O_RDONLY | O_CLOEXEC);
}

static size_t plane_size(int fd, uint32_t type)
{
	struct v4l2_format f = { .type = type };
	size_t sz = 0;
	if (real_ioctl(fd, VIDIOC_G_FMT, &f) == 0) {
		if (mplane(type)) for (unsigned i = 0; i < f.fmt.pix_mp.num_planes && i < VIDEO_MAX_PLANES; i++) sz += f.fmt.pix_mp.plane_fmt[i].sizeimage;
		else sz = f.fmt.pix.sizeimage;
	}
	return sz;
}

static int do_reqbufs(struct ctx *c, int fd, struct v4l2_requestbuffers *rb)
{
	int qi = qidx(rb->type);
	struct squeue *q = &c->q[qi];
	if (rb->memory != V4L2_MEMORY_MMAP || !mplane(rb->type)) { free_queue(q); return real_ioctl(fd, VIDIOC_REQBUFS, rb); }
	struct v4l2_requestbuffers r = *rb;
	r.memory = V4L2_MEMORY_DMABUF;
	if (r.count > MAXBUF) r.count = MAXBUF;
	int ret = real_ioctl(fd, VIDIOC_REQBUFS, &r);
	if (ret) return ret;
	free_queue(q);
	rb->count = r.count;
	rb->capabilities = r.capabilities | V4L2_BUF_CAP_SUPPORTS_MMAP;
	if (!r.count) return 0;
	size_t sz = plane_size(fd, rb->type);
	if (qi == 0 && sz < (1 << 20)) sz = 1 << 20;
	sz = (sz + 4095) & ~4095UL;
	int h = heap_open();
	if (h < 0) { logf_("cannot open dma-heap: %s", strerror(errno)); errno = ENOMEM; return -1; }
	for (unsigned i = 0; i < r.count; i++) {
		struct dma_heap_allocation_data a = { .len = sz, .fd_flags = O_RDWR | O_CLOEXEC };
		if (real_ioctl(h, DMA_HEAP_IOCTL_ALLOC, &a)) { logf_("heap alloc: %s", strerror(errno)); real_close(h); errno = ENOMEM; return -1; }
		q->b[i].dfd = a.fd; q->b[i].size = sz;
		q->b[i].map = real_mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, a.fd, 0);
		q->n = i + 1;
		if (q->b[i].map == MAP_FAILED) { q->b[i].map = NULL; real_close(h); errno = ENOMEM; return -1; }
	}
	real_close(h);
	q->faked = 1;
	logf_("%s: %u dma-heap buffers of %zu bytes", qi ? "CAPTURE" : "OUTPUT", r.count, sz);
	return 0;
}

/* Rewrite a DMABUF v4l2_buffer (as the driver sees it) back to the client's MMAP view. */
static void to_client(struct ctx *c, struct v4l2_buffer *b)
{
	struct squeue *q = &c->q[qidx(b->type)];
	b->memory = V4L2_MEMORY_MMAP;
	if (b->index >= (unsigned)q->n || !b->m.planes || b->length < 1) return;
	b->m.planes[0].length = q->b[b->index].size;
	b->m.planes[0].m.mem_offset = OFF_BASE(qidx(b->type)) + b->index * OFF_STEP;
}

static int to_driver(struct ctx *c, struct v4l2_buffer *b)
{
	struct squeue *q = &c->q[qidx(b->type)];
	if (b->index >= (unsigned)q->n || !b->m.planes || b->length < 1) { errno = EINVAL; return -1; }
	b->memory = V4L2_MEMORY_DMABUF;
	b->m.planes[0].m.fd = q->b[b->index].dfd;
	b->m.planes[0].length = q->b[b->index].size;
	return 0;
}

/* The driver finishes frames out of display order (seen with plain H.264: 0.20 s before 0.17 s and 0.13 s), but each
 * frame keeps its own timestamp. Collect what the driver has, and hand out the earliest once more than `depth` are
 * waiting (or the stream is draining). Empty, non-final buffers pass straight through. */
static int reorder_depth(void)
{
	static int d = -1;
	if (d < 0) { const char *s = getenv("MTK_V4L2_SHIM_REORDER"); d = s ? atoi(s) : 6; if (d < 0) d = 0; }
	return d;
}

/* A frame can go out now: enough are waiting, the stream is draining, or the decoder would run out of buffers. */
static int releasable(const struct ctx *c)
{
	if (!c->npend) return 0;
	if (c->last_seen || c->npend > reorder_depth()) return 1;
	return c->q[1].n && c->npend >= c->q[1].n - 2;
}

static long long ts_us(const struct v4l2_buffer *b) { return (long long)b->timestamp.tv_sec * 1000000 + b->timestamp.tv_usec; }

static int cap_dqbuf(struct ctx *c, int fd, struct v4l2_buffer *ub)
{
	struct squeue *q = &c->q[1];
	int err = EAGAIN;
	while (!c->last_seen && c->npend < MAXBUF) {
		struct pend *p = &c->pend[c->npend];
		memset(p, 0, sizeof *p);
		p->b.type = ub->type; p->b.memory = V4L2_MEMORY_DMABUF;
		p->b.m.planes = p->p; p->b.length = ub->length > VIDEO_MAX_PLANES ? VIDEO_MAX_PLANES : ub->length;
		if (real_ioctl(fd, VIDIOC_DQBUF, &p->b)) { err = errno; break; }
		if (p->b.flags & V4L2_BUF_FLAG_LAST) c->last_seen = 1;
		c->npend++;
	}
	if (!c->npend) { errno = err; return -1; }
	int pick = -1;
	for (int i = 0; i < c->npend; i++)          /* empty, non-final buffers (errors, no picture) go out at once */
		if (!c->pend[i].p[0].bytesused && !(c->pend[i].b.flags & V4L2_BUF_FLAG_LAST)) { pick = i; break; }
	if (pick < 0) {
		if (!releasable(c)) { errno = EAGAIN; return -1; }
		for (int i = 0; i < c->npend; i++) {
			const struct pend *p = &c->pend[i];
			int empty_last = !p->p[0].bytesused && (p->b.flags & V4L2_BUF_FLAG_LAST);
			if (empty_last && c->npend > 1) continue;  /* the empty end-of-stream buffer goes last */
			/* modulo 2^32 us: the driver wraps negative timestamps (e.g. -0.1 s comes back as 4294.87 s) */
			if (pick < 0 || (int32_t)((uint32_t)ts_us(&p->b) - (uint32_t)ts_us(&c->pend[pick].b)) < 0) pick = i;
		}
	}
	struct pend sel = c->pend[pick];
	memmove(&c->pend[pick], &c->pend[pick + 1], (c->npend - pick - 1) * sizeof sel);
	c->npend--;
	/* LAST belongs on whatever goes out last. */
	int had_last = sel.b.flags & V4L2_BUF_FLAG_LAST;
	sel.b.flags &= ~V4L2_BUF_FLAG_LAST;
	if (c->last_seen && !c->npend) { sel.b.flags |= V4L2_BUF_FLAG_LAST; c->last_seen = 0; }
	else if (had_last) { /* moved to a later buffer */ }
	if (sel.p[0].bytesused && sel.b.index < (unsigned)q->n) deliver_frame(c, &q->b[sel.b.index], sel.p[0].bytesused);
	struct v4l2_plane *up = ub->m.planes;
	uint32_t ulen = ub->length;
	*ub = sel.b;
	ub->m.planes = up;
	ub->length = ulen;
	if (up) memcpy(up, sel.p, (ulen < sel.b.length ? ulen : sel.b.length) * sizeof *up);
	logf_("DQ cap idx %u ts %lld flags %#x (%d waiting)", ub->index, ts_us(ub), ub->flags, c->npend);
	to_client(c, ub);
	return 0;
}

static int handle(struct ctx *c, int fd, unsigned long req, void *arg)
{
	switch (req) {
	case VIDIOC_ENUM_FMT: {
		struct v4l2_fmtdesc *d = arg;
		int r = real_ioctl(fd, req, arg);
		if (!r && d->pixelformat == FMT_M21S) {
			d->flags &= ~V4L2_FMT_FLAG_COMPRESSED;
			snprintf((char *)d->description, sizeof d->description, "Y/UV 4:2:0 (archpad untiled)");
		}
		if (!r) d->pixelformat = pf_to_client(d->pixelformat);
		return r;
	}
	case VIDIOC_ENUM_FRAMESIZES: {
		struct v4l2_frmsizeenum *s = arg;
		uint32_t pf = s->pixel_format;
		s->pixel_format = pf == V4L2_PIX_FMT_NV12 ? FMT_M21S : pf == V4L2_PIX_FMT_HEVC ? FMT_H265 : pf;
		int r = real_ioctl(fd, req, arg);
		s->pixel_format = pf;
		return r;
	}
	case VIDIOC_G_FMT: {
		int r = real_ioctl(fd, req, arg);
		if (!r) fmt_from_driver(c, arg);
		return r;
	}
	case VIDIOC_S_FMT:
	case VIDIOC_TRY_FMT: {
		fmt_to_driver(arg);
		int r = real_ioctl(fd, req, arg);
		int e = errno;
		fmt_from_driver(c, arg);
		errno = e;
		return r;
	}
	case VIDIOC_STREAMOFF: {
		if (qidx(*(uint32_t *)arg) == 1) { c->npend = 0; c->last_seen = 0; }   /* the driver takes all buffers back */
		return real_ioctl(fd, req, arg);
	}
	case VIDIOC_REQBUFS: {
		struct v4l2_requestbuffers *rb = arg;
		if (qidx(rb->type) == 1) { c->npend = 0; c->last_seen = 0; }
		if (qidx(rb->type) < 0) return real_ioctl(fd, req, arg);
		return do_reqbufs(c, fd, rb);
	}
	case VIDIOC_QUERYBUF:
	case VIDIOC_QBUF:
	case VIDIOC_DQBUF:
	case VIDIOC_PREPARE_BUF: {
		struct v4l2_buffer *b = arg;
		int qi = qidx(b->type);
		if (qi < 0 || !c->q[qi].faked || b->memory != V4L2_MEMORY_MMAP) return real_ioctl(fd, req, arg);
		struct squeue *q = &c->q[qi];
		if (req == VIDIOC_DQBUF && qi == 1 && mplane(b->type)) return cap_dqbuf(c, fd, b);
		if (req == VIDIOC_DQBUF) {
			b->memory = V4L2_MEMORY_DMABUF;
		} else if (to_driver(c, b)) {
			return -1;
		}
		if (req == VIDIOC_QBUF && qi == 0) {
			struct dma_buf_sync sy = { DMA_BUF_SYNC_END | DMA_BUF_SYNC_WRITE };
			real_ioctl(q->b[b->index].dfd, DMA_BUF_IOCTL_SYNC, &sy);
		}
		int r = real_ioctl(fd, req, arg);
		int e = errno;
		if (!r && req == VIDIOC_DQBUF && qi == 0 && b->index < (unsigned)q->n) {
			struct dma_buf_sync sy = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_WRITE };
			real_ioctl(q->b[b->index].dfd, DMA_BUF_IOCTL_SYNC, &sy);
		}
		to_client(c, b);
		errno = e;
		return r;
	}
	case VIDIOC_CREATE_BUFS: {
		struct v4l2_create_buffers *cb = arg;
		int qi = qidx(cb->format.type);
		if (qi >= 0 && cb->memory == V4L2_MEMORY_MMAP) { errno = ENOTTY; return -1; }
		fmt_to_driver(&cb->format);
		int r = real_ioctl(fd, req, arg);
		fmt_from_driver(c, &cb->format);
		return r;
	}
	case VIDIOC_EXPBUF: {
		struct v4l2_exportbuffer *e = arg;
		int qi = qidx(e->type);
		if (qi == 0 && c->q[0].faked && e->index < (unsigned)c->q[0].n) {
			e->fd = fcntl(c->q[0].b[e->index].dfd, F_DUPFD_CLOEXEC, 0);
			return e->fd < 0 ? -1 : 0;
		}
		if (qi == 1 && c->q[1].faked) { errno = ENOTTY; return -1; }   /* exported buffers would be tiled */
		return real_ioctl(fd, req, arg);
	}
	}
	return real_ioctl(fd, req, arg);
}

int ioctl(int fd, unsigned long req, ...)
{
	va_list ap; va_start(ap, req); void *arg = va_arg(ap, void *); va_end(ap);
	init();
	if (_IOC_TYPE(req) != 'V') return real_ioctl(fd, req, arg);
	pthread_mutex_lock(&lock);
	struct ctx *c = get_ctx(fd, 1);
	if (!c) { pthread_mutex_unlock(&lock); return real_ioctl(fd, req, arg); }
	int r = handle(c, fd, req, arg);
	int e = errno;
	pthread_mutex_unlock(&lock);
	errno = e;
	return r;
}

void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off)
{
	init();
	if (fd < 0) return real_mmap(addr, len, prot, flags, fd, off);
	pthread_mutex_lock(&lock);
	struct ctx *c = get_ctx(fd, 0);
	unsigned long o = (unsigned long)off;
	for (int qi = 0; c && qi < 2; qi++) {
		if (o < OFF_BASE(qi) || o >= OFF_BASE(qi) + MAXBUF * OFF_STEP || (o - OFF_BASE(qi)) % OFF_STEP) continue;
		struct squeue *q = &c->q[qi];
		int i = (o - OFF_BASE(qi)) / OFF_STEP;
		void *p = MAP_FAILED;
		if (i >= q->n || len > q->b[i].size) { errno = EINVAL; }
		else if (qi == 0) {
			p = real_mmap(addr, len, prot, flags, q->b[i].dfd, 0);   /* bitstream: the dma-buf itself */
			if (p != MAP_FAILED) {
				q->b[i].client = p;
				struct dma_buf_sync sy = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_WRITE };
				real_ioctl(q->b[i].dfd, DMA_BUF_IOCTL_SYNC, &sy);
			}
		} else {
			p = real_mmap(addr, q->b[i].size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
			if (p != MAP_FAILED) q->b[i].client = p;
		}
		pthread_mutex_unlock(&lock);
		return p;
	}
	pthread_mutex_unlock(&lock);
	return real_mmap(addr, len, prot, flags, fd, off);
}
void *mmap64(void *addr, size_t len, int prot, int flags, int fd, off_t off) __attribute__((alias("mmap")));

int munmap(void *addr, size_t len)
{
	init();
	pthread_mutex_lock(&lock);
	for (int k = 0; k < MAXCTX; k++) {
		if (ctxs[k].fd < 0) continue;
		for (int qi = 0; qi < 2; qi++)
			for (int i = 0; i < ctxs[k].q[qi].n; i++) {
				struct sbuf *b = &ctxs[k].q[qi].b[i];
				if (b->client == addr) {
					b->client = NULL;
					int r = real_munmap(addr, qi ? b->size : len);
					pthread_mutex_unlock(&lock);
					return r;
				}
			}
	}
	pthread_mutex_unlock(&lock);
	return real_munmap(addr, len);
}

/* Frames held for reordering are invisible to the driver's poll, so report them here. */
int poll(struct pollfd *fds, nfds_t n, int timeout)
{
	static int (*real_poll)(struct pollfd *, nfds_t, int);
	if (!real_poll) real_poll = dlsym(RTLD_NEXT, "poll");
	init();
	unsigned char ready[64] = { 0 };
	int any = 0;
	pthread_mutex_lock(&lock);
	for (nfds_t i = 0; i < n && i < 64; i++) {
		struct ctx *c = fds[i].fd >= 0 ? get_ctx(fds[i].fd, 0) : NULL;
		if (c && (fds[i].events & (POLLIN | POLLRDNORM)) && releasable(c)) ready[i] = any = 1;
	}
	pthread_mutex_unlock(&lock);
	if (!any) return real_poll(fds, n, timeout);
	int r = real_poll(fds, n, 0);
	if (r < 0) return r;
	for (nfds_t i = 0; i < n && i < 64; i++)
		if (ready[i]) {
			if (!fds[i].revents) r++;
			fds[i].revents |= fds[i].events & (POLLIN | POLLRDNORM);
		}
	return r;
}

int close(int fd)
{
	init();
	pthread_mutex_lock(&lock);
	struct ctx *c = get_ctx(fd, 0);
	if (c) {
		logf_("closing fd %d", fd);
		free_queue(&c->q[0]);
		free_queue(&c->q[1]);
		c->fd = -1;
	}
	pthread_mutex_unlock(&lock);
	return real_close(fd);
}
