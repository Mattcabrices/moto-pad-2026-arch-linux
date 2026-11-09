/* archpad: Android property lookups for bionic code running inside glibc processes.
 * Inserted into libhybris hybris/common/hooks.c by scripts/62-build-libhybris.sh.
 * Stock libhybris returns NULL from __system_property_find, so Android code that waits for a
 * property (libhidlbase waits for "hwservicemanager.ready") spins forever. These versions answer
 * from libhybris' usual lookup (property socket, then /system/build.prop) and then from
 * /usr/local/hybris/etc/props (key=value lines) for values Android's init would set.
 * The prop_info handle is a strdup'd copy of the name. */
#include <stdint.h>
static int archpad_prop(const char *name, char *value)
{
    char line[256];
    size_t n = strlen(name);
    int found = 0;
    FILE *f;

    value[0] = 0;
    if (my_property_get(name, value, NULL) > 0 && value[0]) return 1;
    value[0] = 0;
    f = fopen("/usr/local/hybris/etc/props", "r");
    if (!f) return 0;
    while (fgets(line, sizeof line, f)) {
        if (!strncmp(line, name, n) && line[n] == '=') {
            char *v = line + n + 1;
            v[strcspn(v, "\r\n")] = 0;
            strncpy(value, v, 91);
            value[91] = 0;
            found = 1;
            break;
        }
    }
    fclose(f);
    return found;
}

static const void *archpad_property_find(const char *name)
{
    char v[92];
    return archpad_prop(name, v) ? strdup(name) : NULL;
}

static int archpad_property_read(const void *pi, char *name, char *value)
{
    if (name) strcpy(name, (const char *)pi);
    archpad_prop((const char *)pi, value);
    return strlen(value);
}

static void archpad_property_read_callback(const void *pi,
        void (*cb)(void *cookie, const char *name, const char *value, uint32_t serial), void *cookie)
{
    char v[92];
    archpad_prop((const char *)pi, v);
    cb(cookie, (const char *)pi, v, 0);
}

static int archpad_property_get(const char *name, char *value)
{
    archpad_prop(name, value);
    return strlen(value);
}
