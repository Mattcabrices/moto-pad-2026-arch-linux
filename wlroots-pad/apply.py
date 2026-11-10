#!/usr/bin/env python3
"""Applies the Moto Pad (archpad) libhybris changes to a pristine wlroots 0.20.2 tree.
Usage: apply.py <wlroots-tree>. New files come from this directory; edits are exact replacements and
fail loudly if wlroots changed. Adds: WLR_RENDERER=hybris (render/hybris.c), the hybris AHardwareBuffer
allocator, dma-buf -> EGLImage emulation in render/egl.c, and WLR_BACKENDS=pad (backend/pad/pad.c)."""
import os, shutil, sys

T = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
for f in ["render/hybris.c", "include/render/hybris.h", "backend/pad/pad.c", "include/backend/pad.h"]:
    os.makedirs(os.path.dirname(os.path.join(T, f)), exist_ok=True)
    shutil.copy(os.path.join(HERE, f), os.path.join(T, f))

def edit(path, old, new, count=1):
    p = os.path.join(T, path)
    s = open(p).read()
    if new in s:
        return
    n = s.count(old)
    if n != count:
        sys.exit(f"apply.py: {path}: expected {count} match(es) of {old!r}, found {n}")
    open(p, "w").write(s.replace(old, new))

# --- build files ---
edit("backend/meson.build", "subdir('headless')\n", "subdir('headless')\nwlr_files += files('pad/pad.c') # archpad\n")
edit("render/meson.build", "\t\twlr_files += files('egl.c')\n",
     "\t\twlr_files += files('egl.c')\n"
     "\t\twlr_files += files('hybris.c') # archpad\n"
     "\t\twlr_deps += cc.find_library('hybris-common', dirs: ['/usr/local/hybris/lib'])\n"
     "\t\tadd_project_link_arguments('-Wl,-rpath,/usr/local/hybris/lib', language: 'c')\n")

# --- backend selection ---
edit("backend/backend.c", '#include <wlr/util/log.h>\n', '#include <wlr/util/log.h>\n#include "backend/pad.h"\n')
edit("backend/backend.c", '\tif (strcmp(name, "wayland") == 0) {\n',
     '\tif (strcmp(name, "pad") == 0) {\n\t\tbackend = wlr_pad_backend_create(loop);\n'
     '\t} else if (strcmp(name, "wayland") == 0) {\n')

# --- renderer and allocator selection ---
edit("render/wlr_renderer.c", '#include "util/env.h"\n', '#include "util/env.h"\n#include "render/hybris.h"\n')
edit("render/wlr_renderer.c", '\t\t"pixman",\n\t\tNULL\n', '\t\t"pixman",\n\t\t"hybris",\n\t\tNULL\n')
# GPU clients: every compositor sets up wl_shm, so bind android_wlegl there too.
edit("render/wlr_renderer.c", '\treturn wlr_shm_create_with_renderer(wl_display, 2, r) != NULL;\n',
     '\tif (wlr_hybris_enabled()) {\n\t\twlr_hybris_bind_wl_display(wl_display);\n\t}\n'
     '\treturn wlr_shm_create_with_renderer(wl_display, 2, r) != NULL;\n')
edit("render/wlr_renderer.c", '\tbool own_drm_fd = false;\n',
     '\tbool own_drm_fd = false;\n\n\tif (strcmp(renderer_name, "hybris") == 0) {\n'
     '\t\trenderer = wlr_hybris_renderer_create();\n\t\tgoto out;\n\t}\n')
edit("render/allocator/allocator.c", '#include <wlr/config.h>\n', '#include <wlr/config.h>\n#include "render/hybris.h"\n')
edit("render/allocator/allocator.c", '\tuint32_t backend_caps = backend->buffer_caps;\n',
     '\tif (wlr_hybris_enabled()) {\n\t\treturn wlr_hybris_allocator_create();\n\t}\n'
     '\tuint32_t backend_caps = backend->buffer_caps;\n')

# --- EGL: tolerate Android EGL, emulate dma-buf import ---
edit("render/egl.c", '#include "render/egl.h"\n', '#include "render/egl.h"\n#include "render/hybris.h"\n')
edit("render/egl.c", '\tconst char *client_exts_str = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);\n',
     '\tconst char *client_exts_str = wlr_hybris_enabled() ? "EGL_EXT_platform_base" :\n'
     '\t\teglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);\n')
edit("render/egl.c", '\t\tcheck_egl_ext(display_exts_str, "EGL_EXT_image_dma_buf_import");\n',
     '\t\tcheck_egl_ext(display_exts_str, "EGL_EXT_image_dma_buf_import") || wlr_hybris_enabled();\n')
edit("render/egl.c", '\tif (check_egl_ext(display_exts_str, "EGL_KHR_fence_sync") &&\n',
     '\tif (!wlr_hybris_enabled() && check_egl_ext(display_exts_str, "EGL_KHR_fence_sync") &&\n')
edit("render/egl.c", '\tif (check_egl_ext(display_exts_str, "EGL_KHR_wait_sync")) {\n',
     '\tif (!wlr_hybris_enabled() && check_egl_ext(display_exts_str, "EGL_KHR_wait_sync")) {\n')
edit("render/egl.c", '\twlr_log(WLR_INFO, "EGL vendor: %s", eglQueryString(egl->display, EGL_VENDOR));\n',
     '\tif (!wlr_hybris_enabled()) { // Mali crashes on EGL_VENDOR\n'
     '\t\twlr_log(WLR_INFO, "EGL vendor: %s", eglQueryString(egl->display, EGL_VENDOR));\n\t}\n')
edit("render/egl.c", '\t\t\tDRM_FORMAT_ARGB8888,\n\t\t\tDRM_FORMAT_XRGB8888,\n\t\t};\n',
     '\t\t\tDRM_FORMAT_ARGB8888,\n\t\t\tDRM_FORMAT_XRGB8888,\n'
     '\t\t\tDRM_FORMAT_ABGR8888, // archpad\n\t\t\tDRM_FORMAT_XBGR8888,\n\t\t};\n')
edit("render/egl.c",
     '\t\twlr_log(WLR_ERROR, "dmabuf import extension not present");\n\t\treturn NULL;\n\t}\n',
     '\t\twlr_log(WLR_ERROR, "dmabuf import extension not present");\n\t\treturn NULL;\n\t}\n\n'
     '\tif (wlr_hybris_enabled()) {\n\t\t*external_only = false;\n'
     '\t\treturn wlr_hybris_create_image(egl->display, attributes->fd[0]);\n\t}\n')

# linux-dmabuf (Chromium's GPU-composited buffers) needs a renderer DRM fd.
edit("render/egl.c", 'int wlr_egl_dup_drm_fd(struct wlr_egl *egl) {\n',
     'int wlr_egl_dup_drm_fd(struct wlr_egl *egl) {\n\tif (wlr_hybris_enabled()) {\n'
     '\t\treturn wlr_hybris_dup_drm_fd();\n\t}\n')

# pad.c uses output_defer_present from the internal header.
edit("backend/pad/pad.c", '#include "backend/pad.h"\n', '#include "backend/pad.h"\n#include "types/wlr_output.h"\n')
print("apply.py: archpad wlroots changes applied")
