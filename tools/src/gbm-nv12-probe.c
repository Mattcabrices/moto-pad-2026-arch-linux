/* Prints the plane layout the archpad GBM library (Android allocator) gives NV12 buffers. Run under hybris-run with
 * LD_PRELOAD=/usr/local/lib/archpad-gbm/libgbm.so.1. Build: gcc -o gbm-nv12-probe gbm-nv12-probe.c -lgbm */
#include <gbm.h>
#include <stdio.h>
#include <unistd.h>
int main(void) {
	struct gbm_device *d = gbm_create_device(-1);
	if (!d) { puts("no device"); return 1; }
	int sz[][2] = { { 1920, 1088 }, { 1280, 720 }, { 3840, 2160 }, { 854, 480 } };
	for (int i = 0; i < 4; i++) {
		struct gbm_bo *b = gbm_bo_create(d, sz[i][0], sz[i][1], 0x3231564e /* NV12 */, 0);
		if (!b) { printf("%dx%d: failed\n", sz[i][0], sz[i][1]); continue; }
		int fd = gbm_bo_get_fd(b);
		printf("%dx%d: planes %d stride %u/%u offset %u/%u size %ld\n", sz[i][0], sz[i][1], gbm_bo_get_plane_count(b),
		       gbm_bo_get_stride_for_plane(b, 0), gbm_bo_get_stride_for_plane(b, 1), gbm_bo_get_offset(b, 0),
		       gbm_bo_get_offset(b, 1), (long)lseek(fd, 0, SEEK_END));
		close(fd);
		gbm_bo_destroy(b);
	}
	return 0;
}
