# Arch Linux on the Moto Pad 2026 (Lenovo Idea Tab)

A lightweight Arch Linux ARM + XFCE system for the **Motorola Moto Pad 2026** (XT2575-4, `sycamore_row_5G`,
MediaTek Dimensity 6300 / MT6835, Mali-G57 MC2), running from the tablet's internal storage with the stock
Android vendor kernel modules. The Moto Pad 2026 is a rebrand of the **Lenovo Idea Tab**; that tablet will likely
need only small changes, but this has only been tested on the XT2575-4.

By **Matt Cabrices**, built with Claude Code (Anthropic), November 2026.

Bootloader unlock (a prerequisite): [moto-pad-2026-xt2575-4-unlock](https://github.com/Mattcabrices/moto-pad-2026-xt2575-4-unlock).

## Status

| Area | State |
| --- | --- |
| Boot | Rebuilt Android GKI kernel `5.15.185-archpad` in `boot_a`, Arch on `userdata` (ext4), boot-loop breaker with a telnet rescue console |
| Display and touch | 1600x2560 @ 90 Hz panel, used in landscape; Himax touchscreen |
| Desktop | XFCE. Default: **GPU-composited Wayland session** (labwc on the Mali GPU through libhybris). Fallback: Xorg |
| GPU | Compositing on the GPU with zero-copy scanout. Apps render on the Mali-G57 (OpenGL ES 3.2): glmark2, GTK4 apps, mpv, and **Firefox with hardware WebRender, WebGL 1 and WebGL 2** (menu entry uses `firefox-gpu`). **Chromium with GPU compositing**, rasterization, canvas, WebGL 1/2 and WebGPU on the GPU through ANGLE (menu entry uses `chromium-gpu`) |
| Wi-Fi, Bluetooth | Working, through MediaTek's Android helpers run in a small chroot with a property shim |
| Video | **Hardware video decoding** on MediaTek's decoder: H.264, HEVC, VP9 (also MPEG-4, H.263) up to 2560x1440, 8-bit; bit-exact with software decoding. `mpv` (and its menu entry) uses it automatically: 1080p60 plays full screen at the full frame rate with no dropped frames, using about half the CPU of software decoding. **Chromium** decodes H.264 and VP9 on it, 1080p60 at full frame rate; on YouTube a small built-in extension (`config/chromium/no-av1`) turns off AV1 so YouTube sends VP9. Firefox decodes H.264 and HEVC up to 40 fps on it (MP4 files and sites that serve H.264; YouTube's VP9/AV1 stays in software there) |
| Audio | Speakers, the main microphone, and headphone jack switching (headphones and headset mic) |
| USB | Network gadget (SSH over USB) |
| Web server | Caddy + Node (Express) + SQLite + React starter site on port 80; Cloudflare Tunnel (`cloudflared`) to publish it without port forwarding; Codex CLI. See [Web server](#web-server) |
| Extras | On-screen keyboard (squeekboard) in the GPU desktop, Xwayland for X11 apps, Claude Code. Optional Arch boot logo (`config/logo/`, not flashed yet) |
| Not working | Camera, modem. Hardware video decoding for HEVC in Chromium, and for VP9/AV1 in Firefox |

## How it works (short version)

- **Kernel:** AOSP `kernel/common` rebuilt with Arch-friendly options (`kernel/arch-fragment.config`) while keeping
  the symbol CRCs, so the 300+ stock vendor modules (display, touch, Wi-Fi, audio, GPU) still load.
- **Android pieces without Android:** the stock system/vendor images are mounted read-only at `/opt/android-full`.
  `servicemanager`, `hwservicemanager`, `vndservicemanager` and MediaTek's gralloc allocator run in a chroot as
  systemd units (`config/android-units/`), with `tools/src/propshim.c` standing in for Android's property service
  and `tools/fake-logd.py` for logd.
- **GPU:** [libhybris](https://github.com/libhybris/libhybris) loads the Mali EGL/GLES blob. A patched wlroots 0.20
  (`wlroots-pad/`) adds a `hybris` renderer, an AHardwareBuffer allocator and a minimal `pad` display backend
  that sticks to the KMS calls the vendor display driver handles safely. labwc runs on top; XFCE's panel and
  desktop run inside it.
- **GPU apps:** libhybris' `android_wlegl` protocol carries app buffers to the compositor. Two libhybris changes make it
  work on Android 16: an AHardwareBuffer gralloc backend (`scripts/libhybris-gralloc-ahb.c`) and a preload that keeps
  Android's TLS-slot writes off glibc's thread-local data (`tools/src/bionic-tls-pad.c`).
- **GPU Firefox:** Android's GL stack writes two fixed thread-pointer slots (tp+24, tp+32) that overlap Firefox's own
  thread-local variables (its allocator). `tools/ff-tls-relocate.py` makes `/usr/lib/firefox/firefox-hybris`, a copy
  of the executable with all 232 local-exec TLS offsets moved 64 bytes up; a pacman hook rebuilds it after updates
  (`config/firefox/`). Also needed two libhybris fixes: `EGL_EXT_platform_base` in the client extensions and
  `eglSwapBuffersWithDamageKHR` routed through libhybris' Wayland presentation.
- **GPU Chromium:** ANGLE asks for an off-screen EGL display (GBM/surfaceless); libhybris now advertises those
  platforms and maps them to its plain Android path, and `eglGetProcAddress` returns libhybris' own EGL wrappers.
  Chromium hands GPU-composited frames to the compositor only as dma-bufs it allocates through GBM, which needs a
  render node and a Mesa driver the tablet doesn't have. `libgbm.so.1` from `tools/src/archpad-gbm.c` (preloaded by
  `chromium-gpu`) allocates them as Android AHardwareBuffers instead; libhybris' EGL turns those dma-bufs back into
  Android buffers for import (`scripts/libhybris-dmabuf-import.pl`), and each buffer is also sent to the compositor
  over a socket so wlroots-pad can import Chromium's linux-dmabuf wl_buffers the same way. With GPU compositing on,
  Chromium's own V4L2 video decoder runs (through the shim), writing frames into GBM buffers the GPU samples directly.
  Install: `tools/push-crgpu.sh` (after the libhybris and wlroots-pad builds).
- **Video decoding:** the vendor V4L2 decoder (`mtk-vcodec-dec`, with the VCP co-processor's firmware doing the work)
  decodes fine, but only takes dma-buf bitstream buffers, outputs MediaTek's tiled `M21S` format, calls HEVC `H265` and
  hands back frames out of display order. `libmtk-v4l2-shim.so` (`tools/src/mtk-v4l2-shim.c`, LD_PRELOAD) hides all four,
  so FFmpeg's standard `*_v4l2m2m` decoders work unchanged: `mpv --hwdec=v4l2m2m-copy`. Install: `tools/push-vdec.sh`.
  Firefox's own V4L2 path needs a DRM render node, so `libff-v4l2-redirect.so` (`tools/src/ff-v4l2-redirect.c`) instead
  slips a private `h264_v4l2m2m`/`hevc_v4l2m2m` decoder in behind the software decoder Firefox opens in system FFmpeg;
  Firefox then shows the frames like software-decoded ones, with its sandbox intact.
- No vendor binaries or stock images are included in this repository. The scripts extract what they need from
  your own device's firmware.

## Web server

`tools/push-web.sh` (from WSL) installs a small web hosting stack from `config/web/`:

- **Caddy** on port 80 serves the built React site and passes `/api/*` to the Node app.
- **Node/Express** app in `/srv/web/app` (`archpad-web-app.service`, user `web`): a starter to replace with your own site.
- **SQLite** through Node's built-in `node:sqlite`, so there is no database server to run. PostgreSQL and MongoDB cannot run on this kernel: it has no System V shared memory.
- **cloudflared** publishes the site through a Cloudflare Tunnel, with HTTPS and no port forwarding. To turn it on:
  1. In the Cloudflare dashboard, create a tunnel (Zero Trust > Networks > Tunnels, connector "Cloudflared") and copy its token.
  2. On the tablet:
     ```bash
     echo 'TUNNEL_TOKEN=<token>' | sudo tee /etc/cloudflared/tunnel.env
     sudo chmod 600 /etc/cloudflared/tunnel.env
     sudo systemctl start cloudflared
     ```
  3. In the tunnel's settings, add a public hostname that points to `http://localhost:80`.
- **Codex CLI** (`codex`). Sign in once with `codex login --device-auth`.

For real hosting, keep the tablet on the charger. It is Wi-Fi only.

## Layout

| Path | Contents |
| --- | --- |
| `scripts/` | Numbered build steps, run in WSL2 (Arch) on Windows: host setup, unpack stock, kernel, rootfs, images, flashing via mtkclient, libhybris, wlroots |
| `tools/` | Helpers (SSH/USB networking, flashing, screenshots) and `tab-*.sh` scripts run on the tablet as root via `tools/pad-sudo.sh` |
| `tools/src/` | Small C programs: property shim, GPU tests, KMS tests |
| `wlroots-pad/` | Patches and new files for wlroots 0.20.2 (`apply.py`) |
| `config/` | labwc session files and the Android-service systemd units |
| `kernel/` | Stock kernel config and the Arch config fragment |
| `docs/FINDINGS.md` | Device research |
| `HANDOFF.md` | Detailed working log: every fix, gotcha and open item |

## Warnings

- This wipes Android's `userdata`. You need an unlocked bootloader and must accept the risk of bricking.
- A fresh image's `matt` and `root` passwords are `archpad`. **Change them.** `tools/pad-sudo.sh` reads the current
  password from `tools/.pad-password` (git-ignored).
- Paths in the scripts assume the project lives at `C:\mpad26\MotoPadArch` and WSL distro `archlinux`.

## Thanks

This port stands on a lot of other people's work. Thank you to:

- **[Arch Linux ARM](https://archlinuxarm.org/)** and **[Arch Linux](https://archlinux.org/)** for the base system and packages.
- **The Linux kernel and Android Common Kernel** developers ([kernel/common](https://android.googlesource.com/kernel/common)),
  and **Motorola** for publishing the tablet's kernel source ([MotoTablets](https://github.com/MotorolaMobilityLLC/MotoTablets)).
- **[libhybris](https://github.com/libhybris/libhybris)** (Carsten Munk and contributors) and
  **[Halium](https://github.com/Halium)** (android-headers): the bridge that lets glibc Linux use Android's GPU driver.
- **[wlroots](https://gitlab.freedesktop.org/wlroots/wlroots)** and **[labwc](https://github.com/labwc/labwc)** for the
  Wayland compositor this desktop runs on.
- **[XFCE](https://xfce.org/)** for the desktop, and **[squeekboard](https://gitlab.gnome.org/World/Phosh/squeekboard)**
  (Purism / Phosh) for the on-screen keyboard.
- **[mtkclient](https://github.com/bkerler/mtkclient)** (Bjoern Kerler) for MediaTek flashing and recovery.
- **[BobTheBlinker](https://github.com/BobTheBlinker/recovery_device_motorola_sycamore_row_5G)** for the
  `sycamore_row_5G` recovery device tree, and the people reporting on MotoTablets issue 8.
- **[FFmpeg](https://ffmpeg.org/)** and **[mpv](https://mpv.io/)** for video; **Mozilla Firefox** and **Chromium /
  ANGLE** for the browsers.
- **[Caddy](https://caddyserver.com/)**, **[Node.js](https://nodejs.org/)**, **Express**, **React**, **Vite**,
  **SQLite** and **[cloudflared](https://github.com/cloudflare/cloudflared)** for the web server stack.
- **MediaTek** and **Lenovo/Motorola** for the hardware and the vendor drivers this runs on.
- **[Claude Code](https://claude.com/claude-code)** (Anthropic), which did much of the debugging and writing with me.

## License

MIT, copyright (c) 2026 **Matt Cabrices**, for the code in this repository (see `LICENSE`).

The upstream projects above keep their own licenses: for example the Linux kernel (GPL-2.0), libhybris (Apache-2.0),
wlroots (MIT), labwc (GPL-2.0), mtkclient (GPL-3.0), FFmpeg (LGPL/GPL), Firefox (MPL-2.0) and Chromium (BSD-3-Clause).
The files in `wlroots-pad/` and the libhybris changes in `scripts/` are written to be built into wlroots and
libhybris; they may also be used under those projects' licenses. No vendor binaries or firmware are included: the
scripts extract them from your own device.
