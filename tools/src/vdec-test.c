// Moto Pad (archpad): hardware H.264 decode test for the MediaTek V4L2 decoder (mtk-vcodec-dec, VCP firmware).
// Feeds an Annex-B .h264 file one access unit per buffer, counts decoded frames, reports fps, and can dump frame N
// (raw capture planes, MediaTek block format) for checking.
// Build: gcc -O2 -o vdec-test vdec-test.c     Run: vdec-test clip.h264 [/dev/video1] [dump-frame-index out.raw]
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/dma-buf.h>
#include <linux/dma-heap.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define NOUT 6
#define NCAP_MAX 32
#define OUT_SIZE (2 << 20)

static int fd;
static const uint8_t *bs;
static size_t bs_len, bs_pos;

static int xioctl(unsigned long req, void *arg, const char *name)
{
	int r;
	do r = ioctl(fd, req, arg); while (r < 0 && errno == EINTR);
	if (r < 0 && errno != EAGAIN)
		fprintf(stderr, "%s: %s\n", name, strerror(errno));
	return r;
}

static size_t next_start(size_t p)
{
	for (; p + 3 <= bs_len; p++)
		if (bs[p] == 0 && bs[p + 1] == 0 && (bs[p + 2] == 1 || (p + 3 < bs_len && bs[p + 2] == 0 && bs[p + 3] == 1)))
			return p;
	return bs_len;
}

static int nal_hdr(size_t p) { return bs[p + 2] == 1 ? p + 3 : p + 4; }

// One access unit: [start, end). A new AU starts at AUD/SPS/PPS/SEI or a slice with first_mb_in_slice == 0, once a
// slice has been seen in the current AU.
static int next_au(size_t *start, size_t *end)
{
	if (bs_pos >= bs_len) return 0;
	size_t p = next_start(bs_pos);
	if (p >= bs_len) return 0;
	*start = p;
	int seen_slice = 0;
	for (;;) {
		size_t h = nal_hdr(p);
		if (h >= bs_len) { p = bs_len; break; }
		int t = bs[h] & 0x1f;
		int is_slice = (t == 1 || t == 5);
		int first_mb0 = is_slice && h + 1 < bs_len && (bs[h + 1] & 0x80);
		if (seen_slice && ((t >= 6 && t <= 9) || first_mb0))
			break;
		if (is_slice) seen_slice = 1;
		p = next_start(h);
		if (p >= bs_len) break;
	}
	*end = p;
	bs_pos = p;
	return 1;
}

struct buf { void *p[2]; size_t len[2]; int planes; int dfd; };
static struct buf outb[NOUT], capb[NCAP_MAX];
static int ncap, cap_planes;

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

static int queue_out(int i)
{
	size_t s, e;
	struct v4l2_plane pl = {0};
	struct v4l2_buffer b = {0};
	b.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE; b.memory = V4L2_MEMORY_DMABUF; b.index = i;
	b.m.planes = &pl; b.length = 1;
	pl.m.fd = outb[i].dfd; pl.length = outb[i].len[0];
	static long long ts;
	if (!next_au(&s, &e)) return 0;
	if (e - s > outb[i].len[0]) { fprintf(stderr, "AU too big %zu\n", e - s); return 0; }
	struct dma_buf_sync sy = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_WRITE };
	ioctl(outb[i].dfd, DMA_BUF_IOCTL_SYNC, &sy);
	memcpy(outb[i].p[0], bs + s, e - s);
	sy.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_WRITE;
	ioctl(outb[i].dfd, DMA_BUF_IOCTL_SYNC, &sy);
	pl.bytesused = e - s;
	b.timestamp.tv_sec = ts / 1000000; b.timestamp.tv_usec = ts % 1000000; ts += 33333;
	return xioctl(VIDIOC_QBUF, &b, "QBUF out") == 0;
}

static void queue_eos(int i)
{
	struct v4l2_plane pl = {0};
	struct v4l2_buffer b = {0};
	b.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE; b.memory = V4L2_MEMORY_DMABUF; b.index = i;
	b.m.planes = &pl; b.length = 1; pl.bytesused = 0; pl.m.fd = outb[i].dfd; pl.length = outb[i].len[0];
	xioctl(VIDIOC_QBUF, &b, "QBUF eos");
}

static void queue_cap(int i)
{
	struct v4l2_plane pl[2] = {0};
	struct v4l2_buffer b = {0};
	b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; b.memory = V4L2_MEMORY_MMAP; b.index = i;
	b.m.planes = pl; b.length = cap_planes;
	xioctl(VIDIOC_QBUF, &b, "QBUF cap");
}

static void setup_cap(void)
{
	struct v4l2_format f = {0};
	f.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	xioctl(VIDIOC_G_FMT, &f, "G_FMT cap");
	uint32_t pf = f.fmt.pix_mp.pixelformat;
	cap_planes = f.fmt.pix_mp.num_planes;
	printf("capture: %.4s %ux%u planes=%d", (char *)&pf, f.fmt.pix_mp.width, f.fmt.pix_mp.height, cap_planes);
	for (int i = 0; i < cap_planes; i++)
		printf(" [bpl %u size %u]", f.fmt.pix_mp.plane_fmt[i].bytesperline, f.fmt.pix_mp.plane_fmt[i].sizeimage);
	struct v4l2_crop c = {0}; c.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	struct v4l2_selection sel = {0}; sel.type = V4L2_BUF_TYPE_VIDEO_CAPTURE; sel.target = V4L2_SEL_TGT_COMPOSE;
	if (ioctl(fd, VIDIOC_G_SELECTION, &sel) == 0)
		printf(" visible %ux%u+%d+%d", sel.r.width, sel.r.height, sel.r.left, sel.r.top);
	(void)c;
	struct v4l2_control ctl = { .id = V4L2_CID_MIN_BUFFERS_FOR_CAPTURE };
	int minb = ioctl(fd, VIDIOC_G_CTRL, &ctl) == 0 ? ctl.value : 0;
	printf(" min_bufs=%d\n", minb);

	struct v4l2_fmtdesc d = {0}; d.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	printf("capture formats:");
	for (d.index = 0; ioctl(fd, VIDIOC_ENUM_FMT, &d) == 0; d.index++) printf(" %.4s", (char *)&d.pixelformat);
	printf("\n");

	struct v4l2_requestbuffers rb = {0};
	rb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; rb.memory = V4L2_MEMORY_MMAP;
	rb.count = minb + 4 > NCAP_MAX ? NCAP_MAX : minb + 4;
	if (rb.count < 8) rb.count = 8;
	if (xioctl(VIDIOC_REQBUFS, &rb, "REQBUFS cap")) exit(1);
	ncap = rb.count;
	for (int i = 0; i < ncap; i++) {
		struct v4l2_plane pl[2] = {0};
		struct v4l2_buffer b = {0};
		b.type = rb.type; b.memory = V4L2_MEMORY_MMAP; b.index = i; b.m.planes = pl; b.length = cap_planes;
		if (xioctl(VIDIOC_QUERYBUF, &b, "QUERYBUF cap")) exit(1);
		capb[i].planes = cap_planes;
		for (int j = 0; j < cap_planes; j++) {
			capb[i].len[j] = pl[j].length;
			capb[i].p[j] = mmap(NULL, pl[j].length, PROT_READ, MAP_SHARED, fd, pl[j].m.mem_offset);
			if (capb[i].p[j] == MAP_FAILED) { perror("mmap cap"); exit(1); }
		}
		queue_cap(i);
	}
	int t = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	if (xioctl(VIDIOC_STREAMON, &t, "STREAMON cap")) exit(1);
	printf("capture buffers: %d\n", ncap);
}

int main(int argc, char **argv)
{
	if (argc < 2) { fprintf(stderr, "usage: %s clip.h264 [dev] [dump-index out.raw]\n", argv[0]); return 2; }
	const char *dev = argc > 2 ? argv[2] : "/dev/video1";
	int dump_idx = argc > 4 ? atoi(argv[3]) : -1;
	const char *dump_path = argc > 4 ? argv[4] : NULL;
	int in = open(argv[1], O_RDONLY);
	struct stat st;
	if (in < 0 || fstat(in, &st)) { perror(argv[1]); return 1; }
	bs_len = st.st_size;
	bs = mmap(NULL, bs_len, PROT_READ, MAP_PRIVATE, in, 0);
	fd = open(dev, O_RDWR | O_NONBLOCK);
	if (fd < 0) { perror(dev); return 1; }

	struct v4l2_format f = {0};
	f.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	f.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_H264;
	f.fmt.pix_mp.width = 1920; f.fmt.pix_mp.height = 1088; f.fmt.pix_mp.num_planes = 1;
	f.fmt.pix_mp.plane_fmt[0].sizeimage = OUT_SIZE;
	if (xioctl(VIDIOC_S_FMT, &f, "S_FMT out")) return 1;

	struct v4l2_event_subscription sub = {0};
	sub.type = V4L2_EVENT_SOURCE_CHANGE; xioctl(VIDIOC_SUBSCRIBE_EVENT, &sub, "SUB src");
	sub.type = V4L2_EVENT_EOS; xioctl(VIDIOC_SUBSCRIBE_EVENT, &sub, "SUB eos");

	struct v4l2_requestbuffers rb = {0};
	rb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE; rb.memory = V4L2_MEMORY_DMABUF; rb.count = NOUT;
	if (xioctl(VIDIOC_REQBUFS, &rb, "REQBUFS out")) return 1;
	const char *heap = getenv("VDEC_HEAP") ? getenv("VDEC_HEAP") : "/dev/dma_heap/system";
	int hfd = open(heap, O_RDONLY | O_CLOEXEC);
	if (hfd < 0) { perror(heap); return 1; }
	for (unsigned i = 0; i < rb.count; i++) {
		struct dma_heap_allocation_data a = { .len = OUT_SIZE, .fd_flags = O_RDWR | O_CLOEXEC };
		if (ioctl(hfd, DMA_HEAP_IOCTL_ALLOC, &a)) { perror("heap alloc"); return 1; }
		outb[i].dfd = a.fd; outb[i].len[0] = OUT_SIZE;
		outb[i].p[0] = mmap(NULL, OUT_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, a.fd, 0);
		if (outb[i].p[0] == MAP_FAILED) { perror("mmap dmabuf"); return 1; }
	}
	int t = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	int nfed = 0, eos_sent = 0;
	for (unsigned i = 0; i < rb.count; i++)
		if (queue_out(i)) nfed++;
		else { queue_eos(i); eos_sent = 1; break; }
	if (xioctl(VIDIOC_STREAMON, &t, "STREAMON out")) return 1;
	printf("output buffers: %u (size %zu)\n", rb.count, outb[0].len[0]);

	double t0 = now(), tfirst = 0;
	int frames = 0, cap_on = 0, done = 0;
	while (!done) {
		struct pollfd p = { .fd = fd, .events = POLLIN | POLLOUT | POLLPRI };
		int r = poll(&p, 1, 3000);
		if (r == 0) { fprintf(stderr, "timeout (frames=%d fed=%d)\n", frames, nfed); break; }
		if (p.revents & POLLPRI) {
			struct v4l2_event ev;
			while (ioctl(fd, VIDIOC_DQEVENT, &ev) == 0) {
				if (ev.type == V4L2_EVENT_SOURCE_CHANGE) {
					printf("source change after %.3fs\n", now() - t0);
					if (!cap_on) { setup_cap(); cap_on = 1; }
					else printf("(resolution change mid-stream not handled)\n");
				} else if (ev.type == V4L2_EVENT_EOS) {
					printf("EOS event\n");
				}
			}
		}
		if (p.revents & POLLOUT) {
			struct v4l2_plane pl = {0};
			struct v4l2_buffer b = {0};
			b.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE; b.memory = V4L2_MEMORY_DMABUF; b.m.planes = &pl; b.length = 1;
			while (ioctl(fd, VIDIOC_DQBUF, &b) == 0) {
				if (!eos_sent) {
					if (queue_out(b.index)) nfed++;
					else { queue_eos(b.index); eos_sent = 1; }
				}
			}
		}
		if ((p.revents & POLLIN) && cap_on) {
			struct v4l2_plane pl[2] = {0};
			struct v4l2_buffer b = {0};
			b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; b.memory = V4L2_MEMORY_MMAP; b.m.planes = pl; b.length = cap_planes;
			while (ioctl(fd, VIDIOC_DQBUF, &b) == 0) {
				if (pl[0].bytesused) {
					if (!frames) tfirst = now();
					if (frames == dump_idx && dump_path) {
						FILE *o = fopen(dump_path, "wb");
						for (int j = 0; j < cap_planes; j++) fwrite(capb[b.index].p[j], 1, pl[j].bytesused, o);
						fclose(o);
						printf("dumped frame %d (%u + %u bytes)\n", frames, pl[0].bytesused, cap_planes > 1 ? pl[1].bytesused : 0);
					}
					frames++;
				}
				if (b.flags & V4L2_BUF_FLAG_LAST) { done = 1; break; }
				queue_cap(b.index);
			}
		}
		if (p.revents & POLLERR) {
			if (!cap_on) continue;
			fprintf(stderr, "POLLERR\n"); usleep(1000);
		}
	}
	double el = now() - (tfirst ? tfirst : t0);
	printf("fed %d access units, decoded %d frames in %.2fs (%.1f fps after first frame)\n", nfed, frames, now() - t0,
	       frames > 1 ? (frames - 1) / el : 0.0);
	return frames ? 0 : 1;
}
