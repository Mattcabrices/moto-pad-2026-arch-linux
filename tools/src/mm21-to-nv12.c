// Moto Pad (archpad): converts one MediaTek block-mode frame (V4L2 'M21S' / MM21: luma in 16x32 tiles, chroma
// (interleaved UV) in 16x16 tiles, planes back to back) to linear NV12. For checking decoder output.
// Usage: mm21-to-nv12 in.raw out.nv12 coded_width coded_height
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void detile(const unsigned char *src, unsigned char *dst, int w, int h, int th)
{
	int tiles_x = w / 16;
	for (int y = 0; y < h; y++)
		for (int tx = 0; tx < tiles_x; tx++) {
			int ty = y / th, ry = y % th;
			const unsigned char *t = src + ((size_t)ty * tiles_x + tx) * 16 * th + ry * 16;
			memcpy(dst + (size_t)y * w + tx * 16, t, 16);
		}
}

int main(int argc, char **argv)
{
	if (argc != 5) { fprintf(stderr, "usage: %s in.raw out.nv12 coded_w coded_h\n", argv[0]); return 2; }
	int w = atoi(argv[3]), h = atoi(argv[4]);
	size_t ys = (size_t)w * h, cs = ys / 2;
	unsigned char *in = malloc(ys + cs), *out = malloc(ys + cs);
	FILE *f = fopen(argv[1], "rb");
	if (!f || fread(in, 1, ys + cs, f) != ys + cs) { fprintf(stderr, "short read\n"); return 1; }
	fclose(f);
	detile(in, out, w, h, 32);
	detile(in + ys, out + ys, w, h / 2, 16);
	f = fopen(argv[2], "wb");
	fwrite(out, 1, ys + cs, f);
	fclose(f);
	return 0;
}
