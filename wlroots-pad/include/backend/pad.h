#ifndef BACKEND_PAD_H
#define BACKEND_PAD_H

#include <wayland-server-core.h>
#include <wlr/backend/interface.h>

/* Moto Pad (archpad) display backend: drives the DSI panel through mediatek-drm with only the legacy
 * SETCRTC / ADDFB2 / PAGE_FLIP ioctls (the driver oopses on plane, cursor, gamma and property requests).
 * Selected with WLR_BACKENDS=pad,libinput. */
struct wlr_backend *wlr_pad_backend_create(struct wl_event_loop *loop);

#endif
