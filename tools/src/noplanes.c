/* LD_PRELOAD shim for Xorg on the Moto Pad. mediatek-drm oopses the kernel on some requests that
 * Android's display service never makes, so this hides them from Xorg's modesetting driver:
 *  - plane enumeration: report zero planes, so Xorg uses its legacy (non-atomic) path;
 *  - legacy hardware cursor: no-ops; xorg.conf sets SWcursor so the cursor is drawn in software;
 *  - legacy gamma table writes: no-ops;
 *  - SETCRTC with no framebuffer (disabling a CRTC): skipped;
 *  - connector and object property writes (DPMS on the DSI connector oopses): skipped.
 * With PADSHIM_LOG=1 every DRM ioctl is logged to stderr *before* it reaches the kernel, so the
 * last line shows the request in flight when something crashes.
 * Build: gcc -O2 -shared -fPIC -o noplanes.so noplanes.c -I/usr/include/libdrm -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <drm.h>
#include <drm_mode.h>
#include <xf86drmMode.h>

drmModePlaneResPtr drmModeGetPlaneResources(int fd) {
    (void)fd;
    return calloc(1, sizeof(drmModePlaneRes)); /* count_planes = 0 */
}

int drmModeSetCursor(int fd, uint32_t crtcId, uint32_t bo_handle, uint32_t width, uint32_t height) {
    (void)fd; (void)crtcId; (void)bo_handle; (void)width; (void)height;
    return 0;
}

int drmModeSetCursor2(int fd, uint32_t crtcId, uint32_t bo_handle, uint32_t width, uint32_t height,
                      int32_t hot_x, int32_t hot_y) {
    (void)fd; (void)crtcId; (void)bo_handle; (void)width; (void)height; (void)hot_x; (void)hot_y;
    return 0;
}

int drmModeMoveCursor(int fd, uint32_t crtcId, int x, int y) {
    (void)fd; (void)crtcId; (void)x; (void)y;
    return 0;
}

int drmModeCrtcSetGamma(int fd, uint32_t crtc_id, uint32_t size, const uint16_t *red,
                        const uint16_t *green, const uint16_t *blue) {
    (void)fd; (void)crtc_id; (void)size; (void)red; (void)green; (void)blue;
    return 0;
}

static int (*real_ioctl)(int, unsigned long, ...);
static int log_on = -1;

int ioctl(int fd, unsigned long req, ...) {
    va_list ap;
    va_start(ap, req);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    if (!real_ioctl) real_ioctl = (int (*)(int, unsigned long, ...))dlsym(RTLD_NEXT, "ioctl");
    if (log_on < 0) log_on = getenv("PADSHIM_LOG") != NULL;
    if (_IOC_TYPE(req) == DRM_IOCTL_BASE) {
        if (req == DRM_IOCTL_MODE_SETCRTC) {
            struct drm_mode_crtc *c = arg;
            if (log_on) {
                char b[160];
                int n = snprintf(b, sizeof b, "PADSHIM SETCRTC crtc=%u fb=%u conns=%u mode_valid=%u\n",
                                 c->crtc_id, c->fb_id, c->count_connectors, c->mode_valid);
                write(2, b, n);
            }
            if (c->fb_id == 0) return 0; /* disabling a CRTC: skip */
        } else if (req == DRM_IOCTL_MODE_SETPROPERTY) {
            /* Connector property writes (DPMS on the DSI panel) oops the driver. The panel is
             * already on from the bootloader, so pretend they succeeded. */
            struct drm_mode_connector_set_property *p = arg;
            if (log_on) {
                char b[128];
                int n = snprintf(b, sizeof b, "PADSHIM skip SETPROPERTY conn=%u prop=%u value=%llu\n",
                                 p->connector_id, p->prop_id, (unsigned long long)p->value);
                write(2, b, n);
            }
            return 0;
        } else if (req == DRM_IOCTL_MODE_OBJ_SETPROPERTY) {
            struct drm_mode_obj_set_property *p = arg;
            if (log_on) {
                char b[128];
                int n = snprintf(b, sizeof b, "PADSHIM skip OBJ_SETPROPERTY obj=%u type=0x%x prop=%u value=%llu\n",
                                 p->obj_id, p->obj_type, p->prop_id, (unsigned long long)p->value);
                write(2, b, n);
            }
            return 0;
        } else if (log_on) {
            char b[64];
            int n = snprintf(b, sizeof b, "PADSHIM ioctl nr=0x%02x\n", (unsigned)_IOC_NR(req));
            write(2, b, n);
        }
    }
    return real_ioctl(fd, req, arg);
}
