// Moto Pad (archpad): makes Firefox decode H.264 and HEVC on the MediaTek hardware decoder.
// Firefox's own V4L2 path needs a DRM render node and DMA-BUF import into EGL, which this tablet does not have.
// Instead, this LD_PRELOAD library runs FFmpeg's V4L2 decoders (h264_v4l2m2m, hevc_v4l2m2m, on top of
// libmtk-v4l2-shim.so with MTK_V4L2_SHIM_FORMAT=i420) behind the software decoder Firefox opens in system FFmpeg.
// Firefox then treats the result as software-decoded video (it copies each frame for display).
//  - Firefox resolves libavcodec functions with dlsym(), so dlsym() is wrapped to hand out wrappers for
//    avcodec_open2, avcodec_send_packet, avcodec_receive_frame, avcodec_flush_buffers and avcodec_free_context.
//  - When Firefox opens the H.264/HEVC software decoder, a second, private context with the V4L2 decoder is opened
//    from the same parameters, and packets/frames go through it. Firefox's own context stays open but idle.
//  - The V4L2 decoders cannot be flushed (no flush callback: after a seek old frames keep coming, after the end of
//    a video nothing more comes out), so every flush replaces the private context with a fresh one.
//  - Firefox sets no packet time base (its times are microseconds); the V4L2 decoders need one for frame pts.
//  - The V4L2 decoders leave frame durations at 0, which makes Firefox drop frames as late; they are filled in.
//  - Video above 40 frames per second stays in software (ARCHPAD_FF_HWDEC_MAXFPS): Firefox waits for each frame,
//    and the hardware path then manages only about 50 per second, so 60 fps video would drop most frames.
// If the hardware decoder cannot be opened, Firefox's software decoder is used as usual.
// Built against the system FFmpeg headers; it stays out of the way if Firefox loads a different libavcodec major.
// Env: ARCHPAD_FF_HWDEC=0 turns it off; ARCHPAD_FF_HWDEC_DEBUG=1 logs to stderr.
// Build: gcc -O2 -shared -fPIC -o libff-v4l2-redirect.so ff-v4l2-redirect.c -ldl -lpthread  (no FFmpeg linking)
#define _GNU_SOURCE
#include <dlfcn.h>
#include <libavcodec/avcodec.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *(*real_dlsym)(void *, const char *);
static pthread_once_t once = PTHREAD_ONCE_INIT;
static int enabled = 1, debug;

static void init(void) {
  // dlsym itself is not reachable through dlsym, so take glibc's by version (aarch64 baseline is GLIBC_2.17).
  real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
  if (!real_dlsym) real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.17");
  const char *e = getenv("ARCHPAD_FF_HWDEC");
  enabled = !(e && *e == '0');
  e = getenv("ARCHPAD_FF_HWDEC_DEBUG");
  debug = e && *e == '1';
}
#define LOG(...) do { if (debug) fprintf(stderr, "ff-v4l2-redirect: " __VA_ARGS__); } while (0)

/* ---- libavcodec functions, looked up through the handle Firefox opened ---- */
#define NSLOT 4
static struct slot {
  void *handle;
  const AVCodec *(*by_name)(const char *);
  int (*is_decoder)(const AVCodec *);
  AVCodecContext *(*alloc)(const AVCodec *);
  void (*free_ctx)(AVCodecContext **);
  int (*open)(AVCodecContext *, const AVCodec *, AVDictionary **);
  int (*send)(AVCodecContext *, const AVPacket *);
  int (*receive)(AVCodecContext *, AVFrame *);
  void (*flush)(AVCodecContext *);
  AVCodecParameters *(*par_alloc)(void);
  void (*par_free)(AVCodecParameters **);
  int (*par_from_ctx)(AVCodecParameters *, const AVCodecContext *);
  int (*par_to_ctx)(AVCodecContext *, const AVCodecParameters *);
  int (*opt_set_q)(void *, const char *, AVRational, int);
  AVPacket *(*pkt_alloc)(void);
  int (*pkt_ref)(AVPacket *, const AVPacket *);
  void (*pkt_free)(AVPacket **);
} slots[NSLOT];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static struct slot *slot_for(void *handle) {
  pthread_mutex_lock(&lock);
  struct slot *s = NULL;
  for (int i = 0; i < NSLOT && !s; i++)
    if (slots[i].handle == handle) s = &slots[i];
  for (int i = 0; i < NSLOT && !s; i++)
    if (!slots[i].handle) {
      struct slot n = {handle};
#define SYM(f, name) n.f = (__typeof__(n.f))real_dlsym(handle, name)
      SYM(by_name, "avcodec_find_decoder_by_name"); SYM(alloc, "avcodec_alloc_context3");
      SYM(free_ctx, "avcodec_free_context"); SYM(open, "avcodec_open2"); SYM(send, "avcodec_send_packet");
      SYM(receive, "avcodec_receive_frame"); SYM(flush, "avcodec_flush_buffers");
      SYM(par_alloc, "avcodec_parameters_alloc"); SYM(par_free, "avcodec_parameters_free");
      SYM(par_from_ctx, "avcodec_parameters_from_context"); SYM(par_to_ctx, "avcodec_parameters_to_context");
      SYM(opt_set_q, "av_opt_set_q"); SYM(is_decoder, "av_codec_is_decoder");
      SYM(pkt_alloc, "av_packet_alloc"); SYM(pkt_ref, "av_packet_ref"); SYM(pkt_free, "av_packet_free");
      unsigned (*version)(void) = (unsigned (*)(void))real_dlsym(handle, "avcodec_version");
      if (n.by_name && n.alloc && n.free_ctx && n.open && n.send && n.receive && n.flush && n.par_alloc &&
          n.par_free && n.par_from_ctx && n.par_to_ctx && n.opt_set_q && n.is_decoder && n.pkt_alloc && n.pkt_ref && n.pkt_free && version &&
          (version() >> 16) == LIBAVCODEC_VERSION_MAJOR && n.by_name("h264_v4l2m2m")) {
        slots[i] = n;
        s = &slots[i];
      } else {
        LOG("libavcodec %p not used (no V4L2 decoders, missing symbols, or major != %d)\n", handle,
            LIBAVCODEC_VERSION_MAJOR);
      }
      break;
    }
  pthread_mutex_unlock(&lock);
  return s;
}

/* ---- Firefox context -> private hardware decoder ---- */
#define NPROXY 16
static struct proxy {
  AVCodecContext *outer, *inner;   // Firefox's context; the V4L2 decoder doing the work
  const AVCodec *hw;
  AVCodecParameters *par;          // to open fresh V4L2 decoders after a flush
  int64_t last_pts, step;          // for frame durations
  int decided;                     // hardware or software chosen (from the frame rate of the first packets)
  AVPacket *pre[2]; int npre;      // packets held until then
} proxies[NPROXY];

static struct proxy *find_proxy(const AVCodecContext *outer) {
  if (!outer) return NULL;
  pthread_mutex_lock(&lock);
  struct proxy *p = NULL;
  for (int i = 0; i < NPROXY && !p; i++)
    if (proxies[i].outer == outer) p = &proxies[i];
  pthread_mutex_unlock(&lock);
  return p;
}

static AVCodecContext *open_inner(struct slot *s, struct proxy *p) {
  AVCodecContext *c = s->alloc(p->hw);
  if (!c) return NULL;
  if (s->par_to_ctx(c, p->par) < 0) { s->free_ctx(&c); return NULL; }
  s->opt_set_q(c, "pkt_timebase", (AVRational){1, 1000000}, 0);   // Firefox's packet times are in microseconds
  int r = s->open(c, p->hw, NULL);
  if (r < 0) { LOG("opening %s failed (%d)\n", p->hw->name, r); s->free_ctx(&c); return NULL; }
  p->last_pts = AV_NOPTS_VALUE;
  return c;
}

static int open_w(struct slot *s, AVCodecContext *ctx, const AVCodec *c, AVDictionary **opts) {
  int r = s->open(ctx, c, opts);
  if (r < 0 || !c || !s->is_decoder(c) || strstr(c->name, "v4l2m2m")) return r;
  const char *hwname = c->id == AV_CODEC_ID_H264 ? "h264_v4l2m2m" : c->id == AV_CODEC_ID_HEVC ? "hevc_v4l2m2m" : NULL;
  const AVCodec *hw = hwname ? s->by_name(hwname) : NULL;
  if (!hw) return r;
  struct proxy n = {ctx, NULL, hw, s->par_alloc()};
  if (!n.par || s->par_from_ctx(n.par, ctx) < 0 || !(n.inner = open_inner(s, &n))) {
    s->par_free(&n.par);
    LOG("%s stays in software\n", c->name);
    return r;
  }
  pthread_mutex_lock(&lock);
  int i;
  for (i = 0; i < NPROXY && proxies[i].outer; i++) {}
  if (i < NPROXY) proxies[i] = n;
  pthread_mutex_unlock(&lock);
  if (i == NPROXY) { s->free_ctx(&n.inner); s->par_free(&n.par); return r; }
  LOG("%s -> %s\n", c->name, hw->name);
  return r;
}

static void drop_held(struct slot *s, struct proxy *p) {
  for (int i = 0; i < p->npre; i++) s->pkt_free(&p->pre[i]);
  p->npre = 0;
}

// Ends hardware decoding for this context: Firefox's own (software) decoder takes over.
static void drop_proxy(struct slot *s, struct proxy *p) {
  if (p->inner) s->free_ctx(&p->inner);
  drop_held(s, p);
  s->par_free(&p->par);
  pthread_mutex_lock(&lock);
  memset(p, 0, sizeof *p);
  pthread_mutex_unlock(&lock);
}

// Highest frame rate sent to the hardware decoder. Firefox decodes one frame at a time, waiting for each, and the
// hardware path's latency caps that at about 50 frames per second; faster video plays better in software.
static int max_fps(void) {
  static int m;
  if (!m) { const char *e = getenv("ARCHPAD_FF_HWDEC_MAXFPS"); m = e ? atoi(e) : 40; if (m <= 0) m = 1000; }
  return m;
}

// The first two packets are held to measure the frame rate, then go to the hardware or the software decoder.
static int decide(struct slot *s, AVCodecContext *ctx, struct proxy *p, const AVPacket *drain) {
  int sw = 0;
  if (p->npre == 2) {
    int64_t a = p->pre[0]->dts != AV_NOPTS_VALUE ? p->pre[0]->dts : p->pre[0]->pts;
    int64_t b = p->pre[1]->dts != AV_NOPTS_VALUE ? p->pre[1]->dts : p->pre[1]->pts;
    int64_t step = b - a;   // microseconds
    sw = step > 0 && step * max_fps() < 1000000;
    LOG("frame step %lld us: %s\n", (long long)step, sw ? "too fast, software decoder" : "hardware decoder");
  }
  AVCodecContext *to = sw ? ctx : p->inner;
  int r = 0;
  for (int i = 0; i < p->npre; i++) {
    int e = to ? s->send(to, p->pre[i]) : AVERROR(EINVAL);
    if (e < 0) r = e;
  }
  drop_held(s, p);
  p->decided = 1;
  if (sw) drop_proxy(s, p);
  if (drain && to) r = s->send(to, drain);
  return r;
}

static int send_w(struct slot *s, AVCodecContext *ctx, const AVPacket *pkt) {
  struct proxy *p = find_proxy(ctx);
  if (!p) return s->send(ctx, pkt);
  if (!p->decided) {
    if (!pkt || !pkt->size) return decide(s, ctx, p, pkt ? pkt : &(AVPacket){0});
    AVPacket *c = s->pkt_alloc();
    if (!c || s->pkt_ref(c, pkt) < 0) {
      s->pkt_free(&c);
      int r = decide(s, ctx, p, NULL);
      return r < 0 ? r : send_w(s, ctx, pkt);
    }
    p->pre[p->npre++] = c;
    return p->npre < 2 ? 0 : decide(s, ctx, p, NULL);
  }
  int r = p->inner ? s->send(p->inner, pkt) : AVERROR(EINVAL);
  if (r < 0 && r != AVERROR(EAGAIN)) LOG("send %s -> %d\n", pkt && pkt->size ? "packet" : "drain", r);
  return r;
}

static int receive_w(struct slot *s, AVCodecContext *ctx, AVFrame *f) {
  struct proxy *p = find_proxy(ctx);
  if (!p) return s->receive(ctx, f);
  if (!p->decided) return AVERROR(EAGAIN);   // still holding the first packets
  int r = p->inner ? s->receive(p->inner, f) : AVERROR(EINVAL);
  if (r < 0) {
    if (r != AVERROR(EAGAIN)) LOG("receive -> %d\n", r);
    return r;
  }
  // Durations: the spacing between the last two frame times (ignoring jumps), else 1/30 s.
  if (f->duration <= 0 && f->pts != AV_NOPTS_VALUE) {
    int64_t d = p->last_pts != AV_NOPTS_VALUE ? f->pts - p->last_pts : 0;
    if (d > 0 && d < 1000000) p->step = d;
    p->last_pts = f->pts;
    f->duration = p->step > 0 ? p->step : 33333;
  }
  // Keep Firefox's context in step with the stream (it may look at the size and format).
  ctx->width = p->inner->width;
  ctx->height = p->inner->height;
  ctx->coded_width = p->inner->coded_width;
  ctx->coded_height = p->inner->coded_height;
  ctx->pix_fmt = p->inner->pix_fmt;
  return r;
}

static void flush_w(struct slot *s, AVCodecContext *ctx) {
  s->flush(ctx);
  struct proxy *p = find_proxy(ctx);
  if (!p) return;
  drop_held(s, p);
  if (p->inner) s->free_ctx(&p->inner);
  p->inner = open_inner(s, p);
  LOG("flush: new %s decoder%s\n", p->hw->name, p->inner ? "" : " failed to open");
}

static void free_w(struct slot *s, AVCodecContext **pctx) {
  struct proxy *p = pctx ? find_proxy(*pctx) : NULL;
  if (p) drop_proxy(s, p);
  s->free_ctx(pctx);
}

/* ---- dlsym ---- */
#define WRAPPERS(n)                                                                                                \
  static int open_##n(AVCodecContext *x, const AVCodec *c, AVDictionary **o) { return open_w(&slots[n], x, c, o); } \
  static int send_##n(AVCodecContext *x, const AVPacket *p) { return send_w(&slots[n], x, p); }                     \
  static int receive_##n(AVCodecContext *x, AVFrame *f) { return receive_w(&slots[n], x, f); }                     \
  static void flush_##n(AVCodecContext *x) { flush_w(&slots[n], x); }                                              \
  static void free_##n(AVCodecContext **x) { free_w(&slots[n], x); }
WRAPPERS(0) WRAPPERS(1) WRAPPERS(2) WRAPPERS(3)
static const struct { const char *sym; void *fn[NSLOT]; } wrapped[] = {
    {"avcodec_open2", {open_0, open_1, open_2, open_3}},
    {"avcodec_send_packet", {send_0, send_1, send_2, send_3}},
    {"avcodec_receive_frame", {receive_0, receive_1, receive_2, receive_3}},
    {"avcodec_flush_buffers", {flush_0, flush_1, flush_2, flush_3}},
    {"avcodec_free_context", {free_0, free_1, free_2, free_3}},
};
#define NWRAPPED (int)(sizeof wrapped / sizeof wrapped[0])

__attribute__((noinline)) static void *wrap(void *handle, const char *sym, int which) {
  void *p = real_dlsym(handle, sym);
  if (!p) return p;
  struct slot *s = slot_for(handle);
  if (!s) return p;
  LOG("wrapping %s (slot %d)\n", sym, (int)(s - slots));
  return wrapped[which].fn[s - slots];
}

// Everything not wrapped goes to glibc's dlsym as a tail call, so glibc still sees the original caller's return
// address (it needs it for RTLD_NEXT / RTLD_DEFAULT lookups, which libmtk-v4l2-shim and Firefox's sandbox use).
void *dlsym(void *handle, const char *sym) {
  pthread_once(&once, init);
  if (enabled && handle != RTLD_NEXT && handle != RTLD_DEFAULT && sym[0] == 'a' && sym[1] == 'v' && sym[2] == 'c')
    for (int i = 0; i < NWRAPPED; i++)
      if (!strcmp(sym, wrapped[i].sym)) return wrap(handle, sym, i);
  return real_dlsym(handle, sym);
}
