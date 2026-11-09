/* Moto Pad (archpad) display backend for wlroots. See include/backend/pad.h.
 *
 * One output (DSI-1, the panel). Buffers come from the hybris allocator (dma-bufs of AHardwareBuffers);
 * each is imported once with drmPrimeFDToHandle + drmModeAddFB2 and cached on the buffer. The first
 * frame uses drmModeSetCrtc, later frames drmModePageFlip; the flip event drives present + frame.
 * Never sent: plane queries, cursor ioctls, gamma, property writes, SETCRTC without a framebuffer.
 * Env: PAD_TRANSFORM = 0/90/180/270 (initial output transform, default 90 = landscape like Xorg).
 */
#include <assert.h>
#include <drm_fourcc.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/mman.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/interfaces/wlr_output.h>
#include <wlr/render/drm_format_set.h>
#include <wlr/util/addon.h>
#include <wlr/util/log.h>
#include "backend/pad.h"

struct pad_backend {
	struct wlr_backend backend;
	struct wl_event_loop *loop;
	struct wl_listener loop_destroy;
	struct wl_event_source *drm_event;
	int fd;
	struct pad_output *output;
	bool started;
};

struct pad_output {
	struct wlr_output wlr_output;
	struct pad_backend *backend;
	struct wlr_output_mode mode;
	drmModeModeInfo drm_mode;
	uint32_t crtc, connector;
	bool crtc_set, flip_pending;
	/* Buffers the panel uses, locked so wlroots' swapchain cannot render into them (no tearing):
	 * queued = handed to drmModePageFlip, current = on screen since the last flip event. */
	struct wlr_buffer *queued, *current;
	struct wl_event_source *frame_timer;
	struct wlr_drm_format_set formats;
};

struct pad_fb {
	struct wlr_addon addon;
	struct pad_backend *backend;
	uint32_t fb_id, handle;
};

static const struct wlr_backend_impl backend_impl;
static const struct wlr_output_impl output_impl;

static struct pad_backend *pad_backend(struct wlr_backend *b) {
	assert(b->impl == &backend_impl);
	struct pad_backend *pb = wl_container_of(b, pb, backend);
	return pb;
}

static struct pad_output *pad_output(struct wlr_output *o) {
	assert(o->impl == &output_impl);
	struct pad_output *po = wl_container_of(o, po, wlr_output);
	return po;
}

/* --- framebuffers, one per wlr_buffer --- */

static void fb_addon_destroy(struct wlr_addon *addon) {
	struct pad_fb *fb = wl_container_of(addon, fb, addon);
	drmModeRmFB(fb->backend->fd, fb->fb_id);
	struct drm_gem_close gc = { .handle = fb->handle };
	drmIoctl(fb->backend->fd, DRM_IOCTL_GEM_CLOSE, &gc);
	wlr_addon_finish(&fb->addon);
	free(fb);
}

static const struct wlr_addon_interface fb_addon_impl = {
	.name = "pad_fb",
	.destroy = fb_addon_destroy,
};

static uint32_t buffer_fb(struct pad_backend *pb, struct wlr_buffer *buffer) {
	struct wlr_addon *a = wlr_addon_find(&buffer->addons, pb, &fb_addon_impl);
	if (a) {
		struct pad_fb *fb = wl_container_of(a, fb, addon);
		return fb->fb_id;
	}
	struct wlr_dmabuf_attributes dmabuf;
	if (!wlr_buffer_get_dmabuf(buffer, &dmabuf)) {
		wlr_log(WLR_ERROR, "pad: buffer has no dma-buf");
		return 0;
	}
	uint32_t format = dmabuf.format;
	/* Scan-out ignores alpha; mediatek-drm is known to take the X variants. */
	if (format == DRM_FORMAT_ABGR8888) format = DRM_FORMAT_XBGR8888;
	if (format == DRM_FORMAT_ARGB8888) format = DRM_FORMAT_XRGB8888;
	uint32_t handle;
	if (drmPrimeFDToHandle(pb->fd, dmabuf.fd[0], &handle) != 0) {
		wlr_log_errno(WLR_ERROR, "pad: drmPrimeFDToHandle");
		return 0;
	}
	uint32_t handles[4] = { handle }, pitches[4] = { dmabuf.stride[0] }, offsets[4] = { dmabuf.offset[0] };
	uint32_t fb_id;
	if (drmModeAddFB2(pb->fd, dmabuf.width, dmabuf.height, format, handles, pitches, offsets, &fb_id, 0) != 0) {
		wlr_log_errno(WLR_ERROR, "pad: drmModeAddFB2 %dx%d 0x%08x", dmabuf.width, dmabuf.height, format);
		return 0;
	}
	struct pad_fb *fb = calloc(1, sizeof(*fb));
	fb->backend = pb;
	fb->fb_id = fb_id;
	fb->handle = handle;
	wlr_addon_init(&fb->addon, &buffer->addons, pb, &fb_addon_impl);
	wlr_log(WLR_DEBUG, "pad: new framebuffer %u", fb_id);
	return fb_id;
}

/* --- output --- */

static const uint32_t SUPPORTED = WLR_OUTPUT_STATE_BACKEND_OPTIONAL | WLR_OUTPUT_STATE_BUFFER |
	WLR_OUTPUT_STATE_ENABLED | WLR_OUTPUT_STATE_MODE | WLR_OUTPUT_STATE_TRANSFORM | WLR_OUTPUT_STATE_SCALE |
	WLR_OUTPUT_STATE_DAMAGE | WLR_OUTPUT_STATE_RENDER_FORMAT | WLR_OUTPUT_STATE_SUBPIXEL;

static bool output_test(struct wlr_output *wlr_output, const struct wlr_output_state *state) {
	struct pad_output *po = pad_output(wlr_output);
	uint32_t unsupported = state->committed & ~SUPPORTED;
	if (unsupported) {
		wlr_log(WLR_DEBUG, "pad: unsupported output state 0x%x", unsupported);
		return false;
	}
	if (state->committed & WLR_OUTPUT_STATE_MODE) {
		if (state->mode_type == WLR_OUTPUT_STATE_MODE_FIXED) {
			if (state->mode != &po->mode) return false;
		} else if (state->custom_mode.width != po->mode.width || state->custom_mode.height != po->mode.height) {
			return false;
		}
	}
	return true;
}

static int send_frame_cb(void *data) {
	struct pad_output *po = data;
	wlr_log(WLR_DEBUG, "pad: frame (timer)");
	wlr_output_send_frame(&po->wlr_output);
	return 0;
}

static void set_queued(struct pad_output *po, struct wlr_buffer *buffer) {
	if (po->queued) {
		wlr_buffer_unlock(po->queued);
	}
	po->queued = wlr_buffer_lock(buffer);
}

/* The queued buffer is now on screen: release the one it replaced. */
static void promote_queued(struct pad_output *po) {
	if (!po->queued) {
		return;
	}
	if (po->current) {
		wlr_buffer_unlock(po->current);
	}
	po->current = po->queued;
	po->queued = NULL;
}

static bool output_commit(struct wlr_output *wlr_output, const struct wlr_output_state *state) {
	struct pad_output *po = pad_output(wlr_output);
	struct pad_backend *pb = po->backend;
	wlr_log(WLR_DEBUG, "pad: commit 0x%x buffer %p crtc_set %d flip_pending %d", state->committed,
		(void *)state->buffer, po->crtc_set, po->flip_pending);
	if (!output_test(wlr_output, state)) {
		wlr_log(WLR_ERROR, "pad: commit rejected by test (state 0x%x)", state->committed);
		return false;
	}
	if ((state->committed & WLR_OUTPUT_STATE_ENABLED) && !state->enabled) {
		/* Disabling the CRTC (SETCRTC without a framebuffer) oopses mediatek-drm: just stop flipping. */
		po->crtc_set = false;
		return true;
	}
	if (!(state->committed & WLR_OUTPUT_STATE_BUFFER)) {
		return true;
	}
	uint32_t fb = buffer_fb(pb, state->buffer);
	if (!fb) {
		return false;
	}
	if (!po->crtc_set) {
		if (drmModeSetCrtc(pb->fd, po->crtc, fb, 0, 0, &po->connector, 1, &po->drm_mode) != 0) {
			wlr_log_errno(WLR_ERROR, "pad: drmModeSetCrtc");
			return false;
		}
		po->crtc_set = true;
		wlr_log(WLR_DEBUG, "pad: modeset done, fb %u", fb);
		/* Flip to the same framebuffer so the vblank event drives present + frame, like every later commit. */
		if (drmModePageFlip(pb->fd, po->crtc, fb, DRM_MODE_PAGE_FLIP_EVENT, po) == 0) {
			po->flip_pending = true;
			set_queued(po, state->buffer);
		} else {
			set_queued(po, state->buffer);
			promote_queued(po);
			wlr_log_errno(WLR_ERROR, "pad: page flip after modeset failed, using a timer");
			struct wlr_output_event_present present = { .commit_seq = wlr_output->commit_seq + 1, .presented = true };
			output_defer_present(wlr_output, present);
			wl_event_source_timer_update(po->frame_timer, 1);
		}
		return true;
	}
	if (po->flip_pending) {
		wlr_log(WLR_DEBUG, "pad: commit while a flip is pending");
		return false;
	}
	if (drmModePageFlip(pb->fd, po->crtc, fb, DRM_MODE_PAGE_FLIP_EVENT, po) != 0) {
		wlr_log_errno(WLR_ERROR, "pad: drmModePageFlip");
		return false;
	}
	po->flip_pending = true;
	set_queued(po, state->buffer);
	return true;
}

/* Debug: PAD_DUMP=/path.ppm writes the buffer on screen (read from its dma-buf, 1/4 scale, panel
 * orientation) once, at the first flip at least 8 s after start. Shows what the panel really displays. */
static void dump_scanout(struct pad_output *po) {
	static bool done;
	static struct timespec t0;
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	if (t0.tv_sec == 0) t0 = now;
	const char *path = getenv("PAD_DUMP");
	if (done || !path || !po->current || now.tv_sec - t0.tv_sec < 8) return;
	done = true;
	struct wlr_dmabuf_attributes d;
	if (!wlr_buffer_get_dmabuf(po->current, &d)) return;
	size_t size = (size_t)d.stride[0] * d.height;
	uint8_t *m = mmap(NULL, size, PROT_READ, MAP_SHARED, d.fd[0], 0);
	if (m == MAP_FAILED) { wlr_log_errno(WLR_ERROR, "pad: dump mmap"); return; }
	FILE *f = fopen(path, "wb");
	if (f) {
		int w = d.width / 4, h = d.height / 4;
		fprintf(f, "P6\n%d %d\n255\n", w, h);
		bool bgr = d.format == DRM_FORMAT_XRGB8888 || d.format == DRM_FORMAT_ARGB8888;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
			const uint8_t *p = m + (size_t)(y * 4) * d.stride[0] + (size_t)(x * 4) * 4;
			uint8_t rgb[3] = { bgr ? p[2] : p[0], p[1], bgr ? p[0] : p[2] };
			fwrite(rgb, 1, 3, f);
		}
		fclose(f);
		wlr_log(WLR_INFO, "pad: dumped scanout %dx%d fmt 0x%08x to %s", d.width, d.height, d.format, path);
	}
	munmap(m, size);
}

static void handle_flip(int fd, unsigned seq, unsigned sec, unsigned usec, void *data) {
	(void)fd;
	struct pad_output *po = data;
	po->flip_pending = false;
	promote_queued(po);
	dump_scanout(po);
	static unsigned flips;
	if (++flips <= 5 || flips % 300 == 0) wlr_log(WLR_DEBUG, "pad: flip done #%u", flips);
	struct wlr_output_event_present present = {
		.commit_seq = po->wlr_output.commit_seq,
		.presented = true,
		.when = { .tv_sec = sec, .tv_nsec = (long)usec * 1000 },
		.seq = seq,
		.refresh = (int)(1000000000000LL / po->mode.refresh),
		.flags = WLR_OUTPUT_PRESENT_VSYNC | WLR_OUTPUT_PRESENT_HW_CLOCK | WLR_OUTPUT_PRESENT_HW_COMPLETION |
			WLR_OUTPUT_PRESENT_ZERO_COPY,
	};
	wlr_output_send_present(&po->wlr_output, &present);
	wlr_output_send_frame(&po->wlr_output);
}

static int handle_drm_event(int fd, uint32_t mask, void *data) {
	(void)mask; (void)data;
	drmEventContext ev = { .version = 2, .page_flip_handler = handle_flip };
	drmHandleEvent(fd, &ev);
	return 0;
}

static const struct wlr_drm_format_set *output_get_primary_formats(struct wlr_output *wlr_output, uint32_t caps) {
	struct pad_output *po = pad_output(wlr_output);
	if (!(caps & WLR_BUFFER_CAP_DMABUF)) {
		return NULL;
	}
	return &po->formats;
}

static void output_destroy(struct wlr_output *wlr_output) {
	struct pad_output *po = pad_output(wlr_output);
	if (po->queued) wlr_buffer_unlock(po->queued);
	if (po->current) wlr_buffer_unlock(po->current);
	wlr_output_finish(wlr_output);
	wl_event_source_remove(po->frame_timer);
	wlr_drm_format_set_finish(&po->formats);
	po->backend->output = NULL;
	free(po);
}

static const struct wlr_output_impl output_impl = {
	.destroy = output_destroy,
	.test = output_test,
	.commit = output_commit,
	.get_primary_formats = output_get_primary_formats,
};

static bool add_output(struct pad_backend *pb) {
	drmModeRes *res = drmModeGetResources(pb->fd);
	if (!res) {
		wlr_log_errno(WLR_ERROR, "pad: drmModeGetResources");
		return false;
	}
	drmModeConnector *con = NULL;
	for (int i = 0; i < res->count_connectors && !con; i++) {
		drmModeConnector *c = drmModeGetConnector(pb->fd, res->connectors[i]);
		if (c && c->connector_type == DRM_MODE_CONNECTOR_DSI && c->connection == DRM_MODE_CONNECTED && c->count_modes) {
			con = c;
		} else if (c) {
			drmModeFreeConnector(c);
		}
	}
	if (!con) {
		wlr_log(WLR_ERROR, "pad: no connected DSI connector");
		drmModeFreeResources(res);
		return false;
	}
	uint32_t crtc = 0;
	drmModeEncoder *enc = drmModeGetEncoder(pb->fd, con->encoder_id ? con->encoder_id : con->encoders[0]);
	if (enc && enc->crtc_id) crtc = enc->crtc_id;
	for (int i = 0; !crtc && enc && i < res->count_crtcs; i++) {
		if (enc->possible_crtcs & (1u << i)) crtc = res->crtcs[i];
	}
	drmModeFreeEncoder(enc);
	drmModeFreeResources(res);
	if (!crtc) {
		wlr_log(WLR_ERROR, "pad: no CRTC for the DSI connector");
		drmModeFreeConnector(con);
		return false;
	}

	struct pad_output *po = calloc(1, sizeof(*po));
	po->backend = pb;
	po->crtc = crtc;
	po->connector = con->connector_id;
	po->drm_mode = con->modes[0];
	po->mode.width = po->drm_mode.hdisplay;
	po->mode.height = po->drm_mode.vdisplay;
	po->mode.refresh = po->drm_mode.vrefresh * 1000;
	po->mode.preferred = true;
	/* Only the RGBA-order formats: Android BGRA (XRGB8888) buffers come out compressed/unreadable for scan-out
	 * (black panel while the GPU itself reads them fine). RGBA is verified linear (gles-drm-zc). */
	static const uint32_t fmts[] = { DRM_FORMAT_XBGR8888, DRM_FORMAT_ABGR8888 };
	for (size_t i = 0; i < sizeof(fmts) / sizeof(fmts[0]); i++) {
		wlr_drm_format_set_add(&po->formats, fmts[i], DRM_FORMAT_MOD_INVALID);
		wlr_drm_format_set_add(&po->formats, fmts[i], DRM_FORMAT_MOD_LINEAR);
	}

	struct wlr_output_state state;
	wlr_output_state_init(&state);
	wlr_output_state_set_enabled(&state, true);
	wlr_output_state_set_mode(&state, &po->mode);
	wlr_output_state_set_render_format(&state, DRM_FORMAT_XBGR8888); /* see fmts above */
	const char *t = getenv("PAD_TRANSFORM");
	int deg = t ? atoi(t) : 90;
	wlr_output_state_set_transform(&state, deg == 90 ? WL_OUTPUT_TRANSFORM_90 : deg == 180 ? WL_OUTPUT_TRANSFORM_180 :
		deg == 270 ? WL_OUTPUT_TRANSFORM_270 : WL_OUTPUT_TRANSFORM_NORMAL);
	wlr_output_init(&po->wlr_output, &pb->backend, &output_impl, pb->loop, &state);
	wlr_output_state_finish(&state);
	wl_list_insert(&po->wlr_output.modes, &po->mode.link);
	wlr_output_set_name(&po->wlr_output, "DSI-1");
	wlr_output_set_description(&po->wlr_output, "Moto Pad 2026 panel (archpad pad backend)");
	po->wlr_output.make = strdup("Motorola");
	po->wlr_output.model = strdup("Moto Pad panel");
	po->wlr_output.phys_width = con->mmWidth;
	po->wlr_output.phys_height = con->mmHeight;
	po->frame_timer = wl_event_loop_add_timer(pb->loop, send_frame_cb, po);
	wlr_log(WLR_INFO, "pad: DSI-1 connector %u crtc %u %dx%d@%d", po->connector, crtc, po->mode.width,
		po->mode.height, po->drm_mode.vrefresh);
	drmModeFreeConnector(con);
	pb->output = po;
	return true;
}

/* --- backend --- */

static bool backend_start(struct wlr_backend *b) {
	struct pad_backend *pb = pad_backend(b);
	if (!add_output(pb)) {
		return false;
	}
	pb->started = true;
	wl_signal_emit_mutable(&pb->backend.events.new_output, &pb->output->wlr_output);
	return true;
}

static void backend_destroy(struct wlr_backend *b) {
	struct pad_backend *pb = pad_backend(b);
	wlr_backend_finish(b);
	if (pb->output) {
		wlr_output_destroy(&pb->output->wlr_output);
	}
	if (pb->drm_event) {
		wl_event_source_remove(pb->drm_event);
	}
	wl_list_remove(&pb->loop_destroy.link);
	close(pb->fd);
	free(pb);
}

static int backend_get_drm_fd(struct wlr_backend *b) {
	return pad_backend(b)->fd;
}

static const struct wlr_backend_impl backend_impl = {
	.start = backend_start,
	.destroy = backend_destroy,
	.get_drm_fd = backend_get_drm_fd,
};

static void handle_loop_destroy(struct wl_listener *l, void *data) {
	(void)data;
	struct pad_backend *pb = wl_container_of(l, pb, loop_destroy);
	backend_destroy(&pb->backend);
}

struct wlr_backend *wlr_pad_backend_create(struct wl_event_loop *loop) {
	int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		wlr_log_errno(WLR_ERROR, "pad: open /dev/dri/card0");
		return NULL;
	}
	if (drmSetMaster(fd) != 0) {
		wlr_log_errno(WLR_ERROR, "pad: drmSetMaster (is Xorg running?)");
	}
	struct pad_backend *pb = calloc(1, sizeof(*pb));
	wlr_backend_init(&pb->backend, &backend_impl);
	pb->backend.buffer_caps = WLR_BUFFER_CAP_DMABUF;
	pb->loop = loop;
	pb->fd = fd;
	pb->drm_event = wl_event_loop_add_fd(loop, fd, WL_EVENT_READABLE, handle_drm_event, pb);
	pb->loop_destroy.notify = handle_loop_destroy;
	wl_event_loop_add_destroy_listener(loop, &pb->loop_destroy);
	wlr_log(WLR_INFO, "pad: backend created");
	return &pb->backend;
}
