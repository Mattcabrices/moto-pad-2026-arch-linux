#ifndef RENDER_HYBRIS_H
#define RENDER_HYBRIS_H

/* Moto Pad (archpad) libhybris support for wlroots: Mali GLES through libhybris, with buffers from
 * Android's AHardwareBuffer allocator. See MotoPadArch HANDOFF.md "GPU port". */

#include <stdbool.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <wlr/render/allocator.h>

/* True when WLR_RENDERER=hybris. */
bool wlr_hybris_enabled(void);

/* The AHardwareBuffer behind a dma-buf fd allocated by the hybris allocator, or NULL. */
void *wlr_hybris_ahb_from_dmabuf(int fd);

/* EGLImage for a dma-buf allocated by the hybris allocator (EGL_NATIVE_BUFFER_ANDROID). */
EGLImageKHR wlr_hybris_create_image(EGLDisplay display, int dmabuf_fd);

struct wlr_renderer *wlr_hybris_renderer_create(void);

/* Offers libhybris' android_wlegl global on the display and accepts its wl_buffers (GPU-rendered clients). */
struct wl_display;
void wlr_hybris_bind_wl_display(struct wl_display *wl_display);
struct wlr_allocator *wlr_hybris_allocator_create(void);

#endif
