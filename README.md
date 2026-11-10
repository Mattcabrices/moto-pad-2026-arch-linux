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
| GPU | Compositing on the GPU with zero-copy scanout. Apps render on the Mali-G57 (OpenGL ES 3.2): glmark2, GTK4 apps, mpv, and **Firefox with hardware WebRender, WebGL 1 and WebGL 2** (menu entry uses `firefox-gpu`). **Chromium**: rasterization, canvas, WebGL 1/2 and WebGPU on the GPU through ANGLE (menu entry uses `chromium-gpu`); its compositing stays in software |
| Wi-Fi, Bluetooth | Working, through MediaTek's Android helpers run in a small chroot with a property shim |
| Video | **Hardware video decoding** on MediaTek's decoder: H.264, HEVC, VP9 (also MPEG-4, H.263) up to 2560x1440, 8-bit; bit-exact with software decoding. `mpv` (and its menu entry) uses it automatically: 1080p60 plays full screen at the full frame rate with no dropped frames, using about half the CPU of software decoding. Firefox decodes H.264 and HEVC video up to 40 fps on it too (MP4 files and sites that serve H.264; YouTube sends VP9/AV1, which stays in software) |
| Audio | Speakers, the main microphone, and headphone jack switching (headphones and headset mic) |
| USB | Network gadget (SSH over USB) |
| Web server | Caddy + Node (Express) + SQLite + React starter site on port 80; Cloudflare Tunnel (`cloudflared`) to publish it without port forwarding; Codex CLI. See [Web server](#web-server) |
| Extras | On-screen keyboard (squeekboard) in the GPU desktop, Xwayland for X11 apps, Claude Code. Optional Arch boot logo (`config/logo/`, not flashed yet) |
| Not working | Camera, modem. Hardware video decoding in Chromium, and for VP9/AV1 (YouTube) in Firefox |

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
  With no DRM render node Chromium can't hand frames to the compositor as dma-bufs, so `chromium-gpu` turns GPU
  compositing off: pages and WebGL still render on the Mali GPU and are read back once per frame.
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

## License

MIT for the code in this repository (see `LICENSE`). wlroots, libhybris, the Linux kernel and the Android/MediaTek
firmware keep their own licenses.
