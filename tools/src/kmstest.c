/* Minimal display test for the Moto Pad: legacy KMS only, no plane enumeration.
 * Finds the connected connector, creates a dumb buffer, draws color bars, and shows it for
 * the number of seconds given (default 10). Build: gcc -O2 -o kmstest kmstest.c -I/usr/include/libdrm -ldrm
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

int main(int argc, char **argv) {
    int secs = argc > 1 ? atoi(argv[1]) : 10;
    int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open card0"); return 1; }
    drmModeRes *res = drmModeGetResources(fd);
    if (!res) { perror("GetResources"); return 1; }
    printf("crtcs=%d connectors=%d encoders=%d\n", res->count_crtcs, res->count_connectors, res->count_encoders);
    drmModeConnector *conn = NULL;
    for (int i = 0; i < res->count_connectors; i++) {
        drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);
        if (!c) continue;
        printf("connector %u type %u status %d modes %d\n", c->connector_id, c->connector_type, c->connection, c->count_modes);
        if (c->connection == DRM_MODE_CONNECTED && c->count_modes > 0 && !conn) conn = c; else drmModeFreeConnector(c);
    }
    if (!conn) { fprintf(stderr, "no connected connector\n"); return 1; }
    drmModeModeInfo mode = conn->modes[0];
    printf("mode %s %ux%u@%u\n", mode.name, mode.hdisplay, mode.vdisplay, mode.vrefresh);
    uint32_t crtc_id = 0;
    if (conn->encoder_id) {
        drmModeEncoder *e = drmModeGetEncoder(fd, conn->encoder_id);
        if (e) { crtc_id = e->crtc_id; drmModeFreeEncoder(e); }
    }
    if (!crtc_id) crtc_id = res->crtcs[0];
    printf("using crtc %u\n", crtc_id);

    struct drm_mode_create_dumb cd = { .width = mode.hdisplay, .height = mode.vdisplay, .bpp = 32 };
    if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd)) { perror("CREATE_DUMB"); return 1; }
    uint32_t fb;
    if (drmModeAddFB(fd, cd.width, cd.height, 24, 32, cd.pitch, cd.handle, &fb)) { perror("AddFB"); return 1; }
    struct drm_mode_map_dumb md = { .handle = cd.handle };
    if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md)) { perror("MAP_DUMB"); return 1; }
    uint8_t *p = mmap(0, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, md.offset);
    if (p == MAP_FAILED) { perror("mmap"); return 1; }
    static const uint32_t bars[] = { 0xffffff, 0xffff00, 0x00ffff, 0x00ff00, 0xff00ff, 0xff0000, 0x0000ff, 0x1793d1 };
    for (uint32_t y = 0; y < cd.height; y++) {
        uint32_t *row = (uint32_t *)(p + y * cd.pitch);
        for (uint32_t x = 0; x < cd.width; x++) row[x] = bars[(x * 8) / cd.width];
    }
    printf("SetCrtc...\n"); fflush(stdout);
    if (drmModeSetCrtc(fd, crtc_id, fb, 0, 0, &conn->connector_id, 1, &mode)) { perror("SetCrtc"); return 1; }
    printf("SHOWING color bars for %d s\n", secs); fflush(stdout);
    sleep(secs);
    return 0;
}
