/* Android property and SELinux stand-ins for Android helpers/services on Arch.
 * Loaded into the bionic helpers with LD_PRELOAD. Answers __system_property_get/find/read*
 * from a built-in table (props.h, generated from the stock vendor build.prop plus overrides)
 * and accepts writes. Built with -nostdlib: it must not depend on any C library.
 */
#include <stddef.h>
#include <stdint.h>

#define PROP_VALUE_MAX 92

struct kv { const char *k; const char *v; };
#include "props.h" /* static const struct kv PROPS[] = {...}; */

static int eq(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}
static int cpy(char *d, const char *s) {
    int n = 0;
    while (s[n] && n < PROP_VALUE_MAX - 1) { d[n] = s[n]; n++; }
    d[n] = 0;
    return n;
}
/* Values set by this process (__system_property_set) live here and win over the table.
 * Per-process only: there is no shared property area. */
#define NSET 64
static struct { char k[96]; char v[PROP_VALUE_MAX]; struct kv e; } SET[NSET];
static int nset;

static const struct kv *lookup(const char *name) {
    for (int i = 0; i < nset; i++)
        if (eq(SET[i].k, name)) return &SET[i].e;
    for (size_t i = 0; i < sizeof(PROPS) / sizeof(PROPS[0]); i++)
        if (eq(PROPS[i].k, name)) return &PROPS[i];
    return 0;
}

int __system_property_get(const char *name, char *value) {
    const struct kv *p = lookup(name);
    if (!p) { value[0] = 0; return 0; }
    return cpy(value, p->v);
}

/* Bionic's prop_info is opaque to callers, so a pointer to our table entry works as one. */
const void *__system_property_find(const char *name) { return lookup(name); }

int __system_property_read(const void *pi, char *name, char *value) {
    const struct kv *p = pi;
    if (name) cpy(name, p->k);
    return cpy(value, p->v);
}

void __system_property_read_callback(const void *pi,
        void (*cb)(void *cookie, const char *name, const char *value, uint32_t serial), void *cookie) {
    const struct kv *p = pi;
    cb(cookie, p->k, p->v, 0);
}

static void scpy(char *d, const char *s, int max) {
    int n = 0;
    while (s[n] && n < max - 1) { d[n] = s[n]; n++; }
    d[n] = 0;
}

int __system_property_set(const char *key, const char *value) {
    int i;
    for (i = 0; i < nset; i++) if (eq(SET[i].k, key)) break;
    if (i == nset) {
        if (nset == NSET) return 0;
        nset++;
        scpy(SET[i].k, key, sizeof SET[i].k);
    }
    scpy(SET[i].v, value, PROP_VALUE_MAX);
    SET[i].e.k = SET[i].k;
    SET[i].e.v = SET[i].v;
    return 0;
}

/* --- SELinux stand-ins. Arch runs without an SELinux policy, but Android's service managers
 * abort unless they can read their own context and look up service labels. These report a
 * fixed context and allow every access check. Strings are static, so freecon() is a no-op. */
static char CON_SELF[] = "u:r:servicemanager:s0";
static char CON_PEER[] = "u:r:hal_graphics_allocator_default:s0";
static char CON_SVC[] = "u:object_r:default_android_service:s0";
static int HANDLE;

int getcon(char **con) { *con = CON_SELF; return 0; }
int getpidcon(int pid, char **con) { (void)pid; *con = CON_PEER; return 0; }
void freecon(char *con) { (void)con; }
int selinux_status_open(int fallback) { (void)fallback; return 0; }
int selinux_status_updated(void) { return 0; }
void selinux_set_callback(int type, void *cb) { (void)type; (void)cb; }
int selinux_vendor_log_callback(int type, const char *fmt, ...) { (void)type; (void)fmt; return 0; }
int selinux_log_callback(int type, const char *fmt, ...) { (void)type; (void)fmt; return 0; }
void *selinux_android_service_context_handle(void) { return &HANDLE; }
void *selinux_android_vendor_service_context_handle(void) { return &HANDLE; }
void *selinux_android_hw_service_context_handle(void) { return &HANDLE; }
int selabel_lookup(void *h, char **con, const char *key, int type) {
    (void)h; (void)key; (void)type; *con = CON_SVC; return 0;
}
void selabel_close(void *h) { (void)h; }
int selinux_check_access(const char *s, const char *t, const char *c, const char *p, void *a) {
    (void)s; (void)t; (void)c; (void)p; (void)a; return 0;
}
int is_selinux_enabled(void) { return 1; }
