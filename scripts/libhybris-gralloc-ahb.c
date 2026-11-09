/* archpad: gralloc backend for libhybris on top of AHardwareBuffer (Android's libnativewindow).
 *
 * Inserted into hybris/gralloc/gralloc.c by scripts/62-build-libhybris.sh. On Android 10+ libhybris expects
 * Halium's libui_compat_layer.so (built in an Android tree); without it there is no working allocator on
 * Android 16 (gralloc 0/1 modules are gone). AHardwareBuffer reaches the allocator HAL and mapper that run on
 * the tablet (config/android-units), the same route the compositor (wlroots-pad) uses.
 *
 * version 3 = this backend. Buffers are tracked by native handle so release/lock/unlock can find the AHB.
 * Import needs the buffer description (AHardwareBuffer_createFromHandle), hence
 * hybris_gralloc_import_buffer_desc(); the plain import only works for handles we already know. */
#include <pthread.h>
#include <dlfcn.h>
#include <string.h>

typedef struct { uint32_t width, height, layers, format; uint64_t usage; uint32_t stride, rfu0; uint64_t rfu1; } ahb_desc_t;
typedef struct { int32_t left, top, right, bottom; } ahb_rect_t;
static int (*ahb_allocate)(const ahb_desc_t *, void **);
static void (*ahb_acquire)(void *);
static void (*ahb_release)(void *);
static void (*ahb_describe)(const void *, ahb_desc_t *);
static const native_handle_t *(*ahb_get_handle)(const void *);
static int (*ahb_from_handle)(const ahb_desc_t *, const native_handle_t *, int32_t, void **);
static int (*ahb_lock)(void *, uint64_t, int32_t, const ahb_rect_t *, void **);
static int (*ahb_unlock)(void *, int32_t *);

/* Usage bits AHardwareBuffer accepts (gralloc0 values match for these). */
#define AHB_USAGE_MASK (0xffULL | (1ULL << 8) | (1ULL << 9) | (1ULL << 11) | (1ULL << 14) | (1ULL << 16) | (1ULL << 24))

struct archpad_ahb_entry {
    const native_handle_t *handle;
    void *ahb;
    struct archpad_ahb_entry *next;
};
static struct archpad_ahb_entry *archpad_ahb_list;
static pthread_mutex_t archpad_ahb_lock = PTHREAD_MUTEX_INITIALIZER;

static void archpad_ahb_add(void *ahb)
{
    struct archpad_ahb_entry *e = malloc(sizeof(*e));
    e->ahb = ahb;
    e->handle = ahb_get_handle(ahb);
    pthread_mutex_lock(&archpad_ahb_lock);
    e->next = archpad_ahb_list;
    archpad_ahb_list = e;
    pthread_mutex_unlock(&archpad_ahb_lock);
}

static void *archpad_ahb_find(buffer_handle_t handle, int remove)
{
    void *ahb = NULL;
    pthread_mutex_lock(&archpad_ahb_lock);
    for (struct archpad_ahb_entry **p = &archpad_ahb_list; *p; p = &(*p)->next) {
        if ((*p)->handle == (const native_handle_t *)handle) {
            struct archpad_ahb_entry *e = *p;
            ahb = e->ahb;
            if (remove) {
                *p = e->next;
                free(e);
            }
            break;
        }
    }
    pthread_mutex_unlock(&archpad_ahb_lock);
    return ahb;
}

static int archpad_ahb_init(void)
{
    const char *mode = getenv("HYBRIS_GRALLOC");
    if (mode && strcmp(mode, "legacy") == 0)
        return 0;
    void *nw = android_dlopen("/system/lib64/libnativewindow.so", RTLD_NOW);
    if (!nw)
        return 0;
    ahb_allocate = android_dlsym(nw, "AHardwareBuffer_allocate");
    ahb_acquire = android_dlsym(nw, "AHardwareBuffer_acquire");
    ahb_release = android_dlsym(nw, "AHardwareBuffer_release");
    ahb_describe = android_dlsym(nw, "AHardwareBuffer_describe");
    ahb_get_handle = android_dlsym(nw, "AHardwareBuffer_getNativeHandle");
    ahb_from_handle = android_dlsym(nw, "AHardwareBuffer_createFromHandle");
    ahb_lock = android_dlsym(nw, "AHardwareBuffer_lock");
    ahb_unlock = android_dlsym(nw, "AHardwareBuffer_unlock");
    if (!ahb_allocate || !ahb_acquire || !ahb_release || !ahb_describe || !ahb_get_handle || !ahb_from_handle ||
        !ahb_lock || !ahb_unlock) {
        fprintf(stderr, "hybris gralloc (archpad): libnativewindow lacks AHardwareBuffer symbols\n");
        return 0;
    }
    /* Warm-up: the first allocation loads the gralloc mapper; on Mali that breaks an already initialised EGL
     * (see MotoPadArch tools/src/ahb-late.c). Do it now, before EGL starts. */
    ahb_desc_t warm = { 64, 64, 1, 1, (1ULL << 8) | (1ULL << 9), 0, 0, 0 };
    void *w = NULL;
    if (ahb_allocate(&warm, &w) == 0)
        ahb_release(w);
    else
        fprintf(stderr, "hybris gralloc (archpad): warm-up allocation failed (allocator service running?)\n");
    return 1;
}

static int archpad_ahb_allocate(int width, int height, int format, int usage, buffer_handle_t *handle_ptr,
                                uint32_t *stride_ptr)
{
    ahb_desc_t d = { (uint32_t)width, (uint32_t)height, 1, (uint32_t)format, (uint64_t)(uint32_t)usage & AHB_USAGE_MASK,
                     0, 0, 0 };
    void *ahb = NULL;
    int ret = ahb_allocate(&d, &ahb);
    if (ret != 0) {
        fprintf(stderr, "hybris gralloc (archpad): allocate %dx%d format %d usage 0x%x failed: %d\n",
                width, height, format, usage, ret);
        return ret;
    }
    ahb_describe(ahb, &d);
    archpad_ahb_add(ahb);
    *handle_ptr = ahb_get_handle(ahb);
    *stride_ptr = d.stride;
    return 0;
}

int hybris_gralloc_import_buffer_desc(buffer_handle_t raw_handle, int width, int height, int stride, int format,
                                      uint64_t usage, buffer_handle_t *out_handle)
{
    if (version != 3) {
        return hybris_gralloc_import_buffer(raw_handle, out_handle);
    }
    ahb_desc_t d = { (uint32_t)width, (uint32_t)height, 1, (uint32_t)format, usage & AHB_USAGE_MASK,
                     (uint32_t)stride, 0, 0 };
    void *ahb = NULL;
    int ret = ahb_from_handle(&d, (const native_handle_t *)raw_handle, 3 /* AHARDWAREBUFFER_CREATE_FROM_HANDLE_METHOD_CLONE (REGISTER = 2) */, &ahb);
    if (ret != 0) {
        fprintf(stderr, "hybris gralloc (archpad): import %dx%d format %d failed: %d\n", width, height, format, ret);
        return ret;
    }
    archpad_ahb_add(ahb);
    *out_handle = ahb_get_handle(ahb);
    return 0;
}

static int archpad_ahb_import(buffer_handle_t raw_handle, buffer_handle_t *out_handle)
{
    void *ahb = archpad_ahb_find(raw_handle, 0);
    if (!ahb) {
        fprintf(stderr, "hybris gralloc (archpad): import without a buffer description is not supported\n");
        return -EINVAL;
    }
    ahb_acquire(ahb);
    archpad_ahb_add(ahb);
    *out_handle = raw_handle;
    return 0;
}

static int archpad_ahb_release(buffer_handle_t handle)
{
    void *ahb = archpad_ahb_find(handle, 1);
    if (!ahb)
        return -EINVAL;
    ahb_release(ahb);
    return 0;
}

static int archpad_ahb_retain(buffer_handle_t handle)
{
    void *ahb = archpad_ahb_find(handle, 0);
    if (!ahb)
        return -EINVAL;
    ahb_acquire(ahb);
    archpad_ahb_add(ahb);
    return 0;
}

static int archpad_ahb_lock_buf(buffer_handle_t handle, int usage, int l, int t, int w, int h, void **vaddr)
{
    void *ahb = archpad_ahb_find(handle, 0);
    if (!ahb)
        return -EINVAL;
    ahb_rect_t r = { l, t, l + w, t + h };
    return ahb_lock(ahb, (uint64_t)(uint32_t)usage & 0xff, -1, &r, vaddr);
}

static int archpad_ahb_unlock_buf(buffer_handle_t handle)
{
    void *ahb = archpad_ahb_find(handle, 0);
    if (!ahb)
        return -EINVAL;
    int32_t fence = -1;
    int ret = ahb_unlock(ahb, &fence);
    if (fence >= 0)
        close(fence);
    return ret;
}
