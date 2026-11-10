# Moto Pad Arch: handoff

Project by Matt Cabrices. Overview: README.md.

Last updated: 2026-11-10 18:30 (screen off on the power button and after idle; see "18:30 (11-10)").

## Goal

A working, lightweight XFCE Arch Linux system on the Moto Pad 2026 (XT2575-4,
`sycamore_row_5G`, MT6835), a secondary device with an already unlocked bootloader.

## Decisions from Matt

- Keep the project lightweight.
- Build in WSL2 on this PC. Do not reboot the PC for now.
- Arch lives on internal `userdata` (Android data was wiped; Matt does not need it).
- Do not restore stock Android; focus on Arch.
- Keep `product.cleaned.img` in `LocalProjects\Moto Edge Unlock\retail-os\prepared`.
- Later: replace the Hello Moto boot logo with a fun image (the `logo` partition, via BROM).

## What is on the tablet now

| Item | State |
| --- | --- |
| `boot_a` | Arch kernel `5.15.185-archpad` with built-in `archinit` (boot-loop breaker + pstore copy) |
| `userdata` (`/dev/sdc73`) | Arch ext4, grown to 105 GB. Written over the USB console and verified by SHA-256 |
| LK, preloader, slot B, `vendor_boot`, `super` | Untouched |
| Desktop | XFCE on Xorg via `/usr/local/bin/Xpad` + `/usr/local/lib/noplanes.so`; autologin as `matt` on tty1 |
| Working | Display 1600x2560@90, touch (Himax), USB network + SSH, 325 vendor modules |
| Apps | Chromium 156 (renders with its normal sandbox, no flags needed) and the Onboard on-screen keyboard (autostarts). Full `pacman -Syu` done 2026-11-08 |
| Wi-Fi | **Working and connected 2026-11-08 14:00:** home network (saved in NetworkManager, auto-connects), DHCP, internet over wlan0 verified (0% loss, ~23 ms). Earlier: `wlan0` up, NetworkManager scans 2.4 and 5 GHz. Boot service `pad-wifi.service` runs `/usr/local/sbin/pad-wifi-start` (source `tools/pad-wifi-start`). **Boot test passed 13:46** (Wi-Fi, BT, XFCE all start on their own). Fix needed on the way: run `wmt_loader` *without* the prop shim (the shim's `driver.ready=yes` makes it skip setup), wait for `/dev/stpwmt`, then start `wmt_launcher` *with* the shim |
| Bluetooth | **Working 2026-11-08 13:45:** BlueZ sees hci0 (`00:00:46:67:61:01`, looks factory-unset; Android sets the real one from NVRAM). `hci_vhci.ko` built from our kernel source (`scripts/27-build-hci-vhci.sh`, CRCs verified) + `tools/pad-bt-bridge.py` copying H4 packets between `/dev/stpbt` and `/dev/vhci`. The bridge answers HCI 0x0c77 (Read Sync Train Params) itself, because the controller rejects it and that aborted Linux setup. `pad-bt.service` (after pad-wifi). Blueman applet in the panel |
| Display orientation | Landscape at X server start: `/etc/X11/xorg.conf.d/20-pad-landscape.conf` (`Monitor` `Rotate "right"` bound via `Monitor-DSI-1`, plus touch `TransformationMatrix "0 1 0 -1 0 1 0 0 1"`). The login-time xrandr script was dropped: rotating after XFCE started left the desktop sized wrong. Right way up per Matt. Screenshots (`xwd`) show only about 1920 px with the right side black, but Matt confirmed the real screen is full width: a screenshot artifact only |
| Audio | **Speakers working 2026-11-08 14:20** (Matt heard the test tone). Card `mt6835-mt6377`. `MTK_SPK_TYPE_GET=NOT_SMARTPA`: four analog Awinic aw87xxx amps fed by codec line-out. Route (from stock `audio_device.xml` speaker_output + ext_speaker_output): `ADDA_DL_CH1/2 DL1_CH1/2` on, `DAC In Mux=Normal Path`, `LOL Mux=Playback`, `Ext_Speaker_Amp Switch=on`, `aw87xxx_profile_switch_0..3=Music` (`/usr/local/sbin/pad-audio-speaker`, `pad-audio.service`). PipeWire + WirePlumber sink "Built-in Audio Stereo" on hw:0; XFCE pulseaudio volume plugin. **Mic working 14:30:** stock `builtin_Mic_DualMic` + `ADDA_TO_CAPTURE1` route (`/usr/local/sbin/pad-audio-mic`, also run by pad-audio.service) to PCM device 10 `Capture_1`; PipeWire source "Built-in Microphone" from `/etc/pipewire/pipewire.conf.d/90-pad-mic.conf`. Left channel (AIN0) records speech (peak 7227); right (AIN2) is silent, so the second mic is elsewhere or absent. `PGA1/PGA2 Volume` 70%, set by pad-audio-mic. Headphone jack switching 11-09 18:10: `pad-jack.service` (see log entry); not yet tested by ear |
| Not yet | GPU acceleration (libhybris on the back burner), camera, modem, on-screen keyboard is only tolerable (see Keyboard) |

**Keyboard (verified 14:05, auto-show seen in a screenshot when xfce4-terminal took focus):** Onboard tuned to be Gboard-like (Phone layout, Droid theme, auto-show on text focus via AT-SPI after a
session restart; word suggestions/auto-caps CRASH onboard's prediction engine (stl_vector assert), keep off;
autostart needs `org.gnome.desktop.a11y.applications screen-keyboard-enabled=true`; auto-show works for GTK3 apps, but did not trigger for a GTK4 `zenity` dialog;
earlier Compact layout, Droid theme, docked full width,
now always visible and docked (`start-minimized=false`, auto-show off; dock height 260 landscape / 360 portrait, doubled by 2x scaling). Matt used it to type the Wi-Fi password; `tools/tab-onboard-tune.sh`, `tab-onboard-dock.sh`; image defaults in
`31-rootfs-config.sh`). Building svkbd from source was blocked by the permission check (external code),
and the other on-screen keyboards in the repos are Wayland-only. A Bluetooth keyboard is the real fix
for coding (Bluetooth needs the same helper approach as Wi-Fi; not started).

**Internet without Wi-Fi:** `tools/share-internet.sh` (in WSL) makes WSL a NAT gateway, then
`tools/pad-sudo.sh tools/tab-net-via-pc.sh` points the tablet's default route at 10.55.0.2 with
Cloudflare/Quad9 DNS. Not persistent across tablet reboots.

**Wi-Fi status (in progress 2026-11-08 11:10, not working yet):** drivers on disk, not loaded; no `wlan0`.
Findings from the stock .020 vendor init scripts (`init.wmt_drv.rc`, `init.wlan_drv.rc`,
`init_connectivity.rc`):
1. `insmod connfem.ko`, `insmod wmt_drv.ko`.
2. Run `/vendor/bin/wmt_loader` (oneshot). It sets `vendor.connsys.driver.ready=yes`.
3. Then `insmod wmt_chrdev_wifi.ko`, `insmod wlan_drv_gen4m_6835.ko`, start `wlan_assistant`.
4. `wmt_launcher -p /vendor/firmware/` runs as a daemon (firmware patch upload over `/dev/stpwmt`).
5. Switch on with `echo 1 > /dev/wmtWifi`; `wlan0` should appear for NetworkManager.
- Props from vendor build.prop: `ro.vendor.wlan.gen=gen4m_6835`, `ro.vendor.wlan.chrdev=wmt_chrdev_wifi`,
  `ro.vendor.bt.platform=connac1x`. There is no Android property service, so helpers' setprop fails
  harmlessly; do steps 3-5 by hand.
- Wi-Fi firmware is NOT in `/vendor/firmware`; it lives in partition `connsys_wifi_a`
  (8 MB, also `connsys_bt_a`, `connsys_gnss_a`), which the stock bootloader loads into reserved
  memory (`WIFI-EMI`). It should already be in place.
- Helpers are bionic binaries needing `libc libm libdl libc++ liblog libcutils` (+ `libnl` for
  wlan_assistant). `scripts/56-android-runtime.sh` (interrupted by `wsl --shutdown` at 11:15; rerun it) extracts `system.img`
  into `/build/stock/system.d`, takes `linker64` and bionic from the `com.android.runtime` APEX,
  copies helpers, libs and firmware into `/build/out/android-rt`.
- Next: `pad-scp` that folder to the tablet as `/opt/android`; bind `/dev /proc /sys` into it;
  `chroot /opt/android /vendor/bin/wmt_loader`, then steps 3-5. Check `dmesg` for `[wlan]` and
  `WMT` lines. A crash just reboots (boot-loop breaker holds at the console if within 2 min).
- Internet for the tablet meanwhile: `tools/share-internet.sh` + `tools/tab-net-via-pc.sh`.

**How Wi-Fi was solved (13:30):** `wmt_launcher` logged (via `tools/fake-logd.py`, a stand-in
for logd on `/dev/socket/logdw`) that it waits for property `vendor.connsys.driver.ready`. With no
property service, `tools/src/propshim.c` (built by `scripts/57-build-propshim.sh`, `-nostdlib`,
625 props from vendor build.prop + `vendor.connsys.driver.ready=yes`) is LD_PRELOADed into
the helpers. Then: connfem, wmt_drv, wmt_launcher, wmt_loader, wmt_chrdev_wifi,
wlan_drv_gen4m_6835 (+ ccci_md_all, mddp), `echo 1 > /dev/wmtWifi`, and `wlan0` appears.

**Wi-Fi progress at 12:55 (superseded):**
- Runtime built and on the tablet at `/opt/android` (13 MB: linker64, 64-bit bionic, libc++,
  liblog, libcutils, libbase, the four helpers, firmware cfgs). `libnl` was not found, so
  `wlan_assistant` may not run. Fixes made: 64-bit bionic path, a `find_lib` that no longer trips `set -e`.
- `tools/tab-wifi-up.sh` loads connfem and wmt_drv and runs `wmt_loader` (it works; creates `/dev/stpwmt`).
- `tools/tab-wifi-up2.sh` loads `wlan_drv_gen4m_6835` with deps. **It needs `ccci_md_all` and
  `mddp`** (modem modules, which are skipped at boot), and they load fine. Then it starts
  `wmt_launcher`. `wlan_drv_gen4m_6835`, `ccci_md_all` and `mddp` are now loaded.
- Kernel log (`journalctl -k`; plain `dmesg` came back empty): consys powers on, chip ID 0x8a00
  read OK, HW reset OK, then `wmt_ctrl_ul_cmd wait signal timeout` / `wmt close stp failed`.
  The driver waits on `wmt_launcher` (userspace), which is not answering.
- `echo 1 > /dev/wmtWifi` returns an I/O error; there is no `wlan0`.
- Next: run `wmt_launcher` in the foreground with strace (`/usr/bin/strace` is on the tablet) to
  see what it blocks on; it was restarted mid-sequence (`pkill`), so retry the clean order after a
  reboot: wmt_loader, start `wmt_launcher` *before* the driver asks, load wifi drivers, then
  `echo 1 > /dev/wmtWifi`. Suspects: missing Android properties
  (`persist.vendor.connsys.chipid`, patch props) and no `logd`. A tiny property area or
  `LD_PRELOAD`-style stub for `__system_property_get` may be needed. Add `ccci_md_all` and `mddp`
  back to the second-stage module list once Wi-Fi works.

**USER_NS test (interrupted by `wsl --shutdown`; rerun detached):** `scripts/26-test-userns.sh` builds a `CONFIG_USER_NS=y` kernel in
`/build/kernel/out-userns` and runs the module check. Result in `/build/kernel/userns.log`.
Chromium already works without it, so this is optional.

The tablet's rootfs was fixed by hand over SSH. `scripts/31-rootfs-config.sh` now has the same
fixes, so a rebuilt image matches.

## How to get in

- **SSH (normal):** from WSL, `bash /mnt/c/mpad26/MotoPadArch/tools/pad-ssh.sh`.
  Root commands: `tools/pad-sudo.sh <script>`. Copy files: `tools/pad-scp.sh <file>`.
  Needs usbipd to hand the tablet's USB gadget (`18d1:4e23`, busid 2-1) to WSL.
- **Early-boot console:** if a boot crashes within 2 minutes, the next boot holds at a
  busybox telnet console on 10.55.0.1:23 with Arch mounted at `/newroot`.
  Use `tools/padcmd.py 'cmd'` or `tools/padcmd.py @file.sh`. `reboot -f` boots Arch again.
  Touch `/archpad-hold` on the rootfs to force a hold.
- **usbipd:** `tools/usbipd-preloader.ps1` (run elevated, 30 min) binds every tablet mode
  (preloader `0e8d:2000`, BROM `0e8d:0003`, DA `0e8d:2001`, gadget `18d1:4e23`) and
  auto-attaches busid 2-1 to WSL. Bindings sometimes vanish; rerun it.
- **Write partitions without fastboot (BROM):** `scripts/53-wsl-write-boot-a.sh` (mtkclient in
  WSL with the factory `DA_BR.bin` + `da.auth`, `--stock`). BROM entry: tablet fully off
  (Power+VolUp+VolDown until dark, release), unplug, hold VolUp+VolDown, plug in.
  Holding keys during a warm reset does not work.
- Passwords: `matt` and `root` are `archpad`. Change them.

**Reboot gotcha:** rebooting less than 2 minutes after boot leaves the boot-loop marker set (pad-boot-ok
clears it after 120 s), so the next boot holds at the console. Not a crash; `reboot -f` from the console.

**Screenshots:** `tools/tab-screenshot.sh` (xwd on the tablet) + `tools/xwd2png.py` → `out/screen.png`.
Note: xwd screenshots of the rotated screen show only about 1920 px wide; the real screen is full width (Matt confirmed).

**GPU survey (2026-11-08 14:35):** kernel side is ready: `mali_kbase_mt6835`, `ged`, `mtk_gpufreq_*` load,
`/dev/mali0` exists (rw for all), and `/dev/dma_heap/*` exists. Userspace blob: `vendor/lib64/egl/mt6835/libGLES_mali.so` (EGL/GLES)
+ `vulkan.mali.so`, with 23 Android deps (libnativewindow, libutils, libdmabufheap, libion, libged,
libgralloc_extra/metadata/types_mtk, ...). It also needs MediaTek's gralloc allocator HAL service
(`android.hardware.graphics.allocator@4.0-service-mediatek`), i.e. hwservicemanager/binder. libhybris is
**not packaged** in Arch Linux ARM; building it from source was blocked by the permission check
("external code") in this session, as with svkbd. Panfrost (open source) would need a 6.x-era panfrost
kernel driver backported to 5.15 plus MTK GPU power/clock wiring.

**libhybris findings (14:45, Matt approved the build):** `scripts/60-fetch-libhybris.sh` fetched pinned
libhybris `7079712a` (2026-06-24) and Halium `android-headers` branch `halium-16.0` into `/build/src`
(downloads were allowed this time). Its `android-version.h` still says 11.0. libhybris's linker generations
go up to `q` (Android 10+); Android 16 blobs may need linker fixes. **libhybris EGL has only a `wayland`
platform, no X11**, so it cannot accelerate the current Xorg desktop. The proven route (Droidian/Halium):
1. Run Android vendor services from `/opt/android`: servicemanager, hwservicemanager, vndservicemanager,
   `android.hardware.graphics.allocator@4.0-service-mediatek`, and the composer service (`hwcomposer.mtk_common.so`),
   with binder (GKI has it) and the property shim.
2. libhybris built with `--enable-arch=arm64 --enable-mali-quirks --enable-wayland --with-android-headers=...`.
3. A Wayland compositor with a hwcomposer backend (as in Droidian's phosh/wlroots stack), then apps on
   Wayland and X11 apps via Xwayland. XFCE 4.20 Wayland support is partial (panel works under labwc).
This also sidesteps the mediatek-drm crashes, since Android's composer drives the panel. **Estimated multi-day.**
Not started beyond fetching sources.

**GPU port, step 1 (started 14:55):** PC disk is tight (see memory), so no staging on the PC.
`tools/push-android-images.sh` copies the stock .020 `system/vendor/system_ext/product.img` to the tablet;
`tools/tab-android-mount.sh` mounts them read-only (EROFS loop) as `/opt/android-full`, mounts binderfs
(`/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder`), unpacks APEX payloads to `/opt/android-img/apex` and
mounts them at `/opt/android-full/apex/<name>`. Kernel has `ANDROID_BINDER_IPC=y`, `ANDROID_BINDERFS=y`.
**15:10 progress:** the shim (`tools/src/propshim.c`) now also fakes SELinux (getcon, getpidcon, selabel_lookup,
selinux_check_access, ... allow everything), because servicemanager/vndservicemanager abort in `Access::Access()`
without it. Running in `/opt/android-full` (`tools/tab-android-sm.sh`): servicemanager, hwservicemanager (reads
the VINTF manifests fine), vndservicemanager, and `android.hardware.graphics.allocator@4.0-service-mediatek.mt6835`
(`tools/tab-android-alloc.sh`). **15:40:** allocator VERIFIED registered (`IAllocator/default` in lshal). The earlier hang: hwservicemanager and
every HIDL service spin in `WaitForProperty("hwservicemanager.ready")`; the shim now reports
`hwservicemanager.ready`/`servicemanager.ready`=true and keeps a per-process store for `__system_property_set`.
Rebuild the shim with `KEEP_GCC=1 scripts/57-build-propshim.sh` while another build uses the rootfs. Push +
restart: `tools/tab-gpu-restart.sh` (after scp of libpropshim.so, tab-android-sm.sh, tab-android-alloc.sh to /tmp).
Debug trick: `kill -35 <pid>` makes any bionic process log a backtrace (to fake-logd) without dying.
Gralloc logs `platform (common/mt8755) not found` (uses defaults); maybe set ro.board.platform=mt6835 later.

**16:00 libhybris status** (latest: see "23:45 MILESTONE" below):
- Built: `scripts/62-build-libhybris.sh` -> `/build/out/libhybris.tar` (19 MB, prefix /usr/local/hybris).
  `RESUME=1` continues make in the existing tree (fast). Needs `-D_GNU_SOURCE` (gcc 16; already in script).
  Hook patch step: `EXTRA_HOOKS="..."` in script 62 adds `HOOK_DIRECT_NO_DEBUG(fn)` to hooks.c after uselocale.
- Tablet install/test: scp `/build/out/libhybris.tar` + run `tools/tab-hybris-test.sh` (extracts, symlinks
  /system /apex /odm /linkerconfig -> /opt/android-full; Arch's real /vendor keeps `firmware` (MTK drivers need
  it) and gets per-entry links to /opt/android-full/vendor/*; compat dir /usr/local/hybris/compat has
  graphics.common-V3-ndk.so -> V6; HYBRIS_LD_LIBRARY_PATH includes it).
- After a reboot the Android services now start by themselves (pad-android.target, 11-09 12:45). Manual route (debug only): `tab-android-mount.sh`, then `tab-gpu-restart.sh`.
- Current blocker: `test_dlopen /vendor/lib64/egl/libGLES_mali.so` SIGSEGV in bionic `__ctype_get_mb_cur_max`
  (reads bionic TLS, null under glibc), called from libc++ init. Fix = hook it (added to EXTRA_HOOKS; rebuild
  with RESUME=1 was running at 16:00 -> check `/build/out/libhybris.done`). Expect more of the same: debug with
  `tools/tab-hybris-dbg.sh` pattern (gdb on tablet: run, `info proc mappings`, map pc/lr to lib+offset, then
  `gdb -batch -ex 'info symbol 0xOFF' <lib>`), add each bionic-TLS function to EXTRA_HOOKS, RESUME=1 rebuild.
- **16:10: hook fixed it. `test_dlopen libGLES_mali.so` now SUCCEEDS** (warning only: `libpq_cust.so` not found).
  NEXT: `EGL_PLATFORM=null test_egl_configs` / `test_egl` (via tab-hybris-test.sh) -> if a crash, same gdb loop.
- **16:40:** test_egl_configs hung in libhidlbase WaitForProperty(hwservicemanager.ready): stock libhybris
  `__system_property_find` returns NULL. FIXED with `scripts/libhybris-archpad-props.c` (inserted into hooks.c
  by script 62 before the first hook table; find/read/read_callback answer from libhybris props, then
  `/usr/local/hybris/etc/props` which tab-hybris-test.sh writes). To re-apply patches after editing them:
  copy pristine `/build/src/libhybris/hybris/common/hooks.c` over `/build/rootfs/root/root/hb/.../hooks.c`, then
  RESUME=1 build. (Don't `pkill -f` a pattern that's in your own command line - it kills the shell.)
  NOW: Mali initializes (log: `mali: [INIT] ... cdbgp_populate_from_system_environment ... failed (3)`,
  probably harmless), worker threads start, but test_egl_configs/test_egl still HANG (rc=124). NEXT: rerun the
  frame-pointer walk (tools/tab-hybris-dbg.sh: background test, sleep 10, gdb -p with $f=$x29 loop, map
  ret addrs via `info proc mappings`) to see what it waits on now (likely another property/HIDL/AIDL service,
  e.g. mapper or a vendor service such as gpud/ged not running).
- **16:45 CORRECTION:** the stack walk still shows the SAME WaitForProperty in libhidlbase (called from
  configstore via libSurfaceFlingerProp <- Android libEGL). So the archpad find hook is NOT taking effect yet.
  Check first: (1) is `/usr/local/hybris/etc/props` present on the tablet; (2) does the installed
  libhybris-common contain `archpad_prop` (`strings /usr/local/hybris/lib/libhybris-common.so | grep archpad`
  won't show static names - use `nm`); (3) when is `hooks_properties` applied (grep hooks.c for
  hooks_properties usage - it may be used only if no property area/socket exists, or only for some
  linker versions); (4) run with HYBRIS_LOGGING_LEVEL=debug / HYBRIS_TRACE_HOOKS=1 to see find calls.
  Alternative: make WaitForProperty moot by giving hidl a property area, or set
  `ro.surface_flinger.*` / disable configstore lookup (libSurfaceFlingerProp asks configstore HAL first).
- **20:40 MILESTONE: GPU RENDERS.** `tools/src/gles-pbuffer.c` (built by linking `-lhybris-common -lEGL`,
  rpath /usr/local/hybris/lib; run with `tools/tab-gles-test.sh`) prints `GL_RENDERER=Mali-G57 MC2`,
  `OpenGL ES 3.2 v1.r38p1`, pixel 255,128,64,255 correct, glError 0, 200 clears+readback 5.9 ms.
  What fixed the 16:45 hang: libhybris skips `hooks_properties` for SDK>=27 (bionic's real property code
  runs and finds no property area). The archpad property hooks now go in `hooks_common` (script 62), plus
  `__system_property_get`. `test_egl_configs` passes (lists Mali configs).
  Gotchas: (1) programs MUST link libhybris-common before libEGL (like libhybris' tests), otherwise Mali's
  eglInitialize segfaults in sscanf("r%up%u"); (2) `eglQueryString(EGL_VENDOR)` may crash - skipped;
  (3) libhybris' libGLESv2 link not tested - test fetches GL via eglGetProcAddress.
  NEXT (display): EGL_PLATFORM=null is off-screen only. Options: (a) wayland platform
  (`--enable-wayland` built) with a compositor that renders via hybris EGL and scans out with DRM dumb
  buffers/glReadPixels or gralloc buffers imported into KMS; (b) build Halium `libhwc2_compat_layer` +
  start a composer service (`android.hardware.graphics.composer@2.x-service` in vendor/bin/hw) for the
  hwcomposer EGL platform. Also: make the Android userspace start at boot (systemd units for
  tab-android-mount + service managers + allocator).
- **23:45 MILESTONE: GPU ON SCREEN, ZERO-COPY.** Matt picked the Wayland-compositor route.
  Build both tests with `scripts/63-build-gles-drm.sh` (out: /build/out/gles-drm, gles-drm-zc); copy with
  pad-scp, run with `tools/tab-gles-drm.sh` / `tools/tab-gles-drm-zc.sh` (stop getty@tty1 + Xorg, run 15 s via
  systemd-run, restart getty; `tab-gles-drm-zc-gdb.sh` = same under gdb).
  - `gles-drm.c` (glReadPixels into DRM dumb buffers, legacy SETCRTC + PAGE_FLIP): 36.8 fps, 12.4 ms copy/frame.
  - `gles-drm-zc.c` (zero-copy): `AHardwareBuffer_allocate` via `android_dlopen(/system/lib64/libnativewindow.so)`
    (goes to the MTK allocator HAL; needs tab-gpu-restart.sh services) -> native handle has 3 fds:
    fd[0] gralloc_extra, **fd[1] = the dma-buf (mtk_mm-uncached)**, fd[2] memfd metadata. fd[1] ->
    `drmPrimeFDToHandle` + `drmModeAddFB2(XBGR8888, pitch stride*4)` works; same AHB ->
    `eglGetNativeClientBufferANDROID` + `eglCreateImageKHR(EGL_NATIVE_BUFFER_ANDROID)` ->
    `glEGLImageTargetTexture2DOES` -> FBO. Usage GPU_FRAMEBUFFER|GPU_SAMPLED|COMPOSER_OVERLAY|CPU_READ_RARELY
    gives a LINEAR buffer (CPU mmap check 40,80,c0,ff at 3 points). 65 fps with a heavy full-screen shader
    (11.4 ms draw), no copies, glError 0, page flip works on mediatek-drm.
  - Gotchas: (1) **allocating AHBs after eglMakeCurrent breaks later Mali GL calls** (NULL deref at Mali
    offset 0x862e00 in GenTextures/TexParameteri/ImageTarget*) - allocate before EGL init; for a compositor that
    allocates later, test re-calling eglMakeCurrent after allocation or allocating on another thread.
    (2) glEGLImageTargetRenderbufferStorageOES path crashed at the same spot (likely the same cause, untested
    after the reorder). (3) **Never put /usr/local/hybris/lib in ld.so.conf**: Xorg then loads hybris libEGL
    and aborts at start (desktop failed to come back once; fixed, tab-hybris-test.sh now removes it).
    (4) Mali has no frame pointers - gdb frame walks fail; bisect with printfs instead.
  - NEXT: compositor. Ideas: wlroots with a custom allocator handing out AHB dma-bufs (DRM backend scans them out;
    preload noplanes.so-style shim for mediatek-drm), renderer = hybris EGL via EGLImage of the same AHB
    (wlroots' GLES2 renderer expects EGL dma-buf import/GBM, so a small custom renderer or patch is needed);
    clients via libhybris wayland-egl (`android_wlegl` protocol, server side in libhybris eglplatformcommon).
    Simpler stepping stone: a tiny compositor of our own. XFCE would run via Xwayland (labwc + xfce4-panel).
- **00:30 (11-09) COMPOSITOR WORK (Matt: "build and start and test whatever you need", overnight).**
  - Late-allocation fix proven (`tools/src/ahb-late.c`, `tools/tab-ahb-late.sh`): after AHardwareBuffer_allocate,
    `eglMakeCurrent(NONE)` + `eglMakeCurrent(ctx)` again makes both the texture and the renderbuffer EGLImage
    paths work (allocating on another thread does NOT help).
  - `tools/src/gl-caps.c` (scripts/65): Mali EGL has KHR_no_config_context, surfaceless, image_base,
    ANDROID_image_native_buffer, get_native_client_buffer, native_fence_sync, **EGL_WL_bind_wayland_display**
    (hybris); no dma_buf_import. GL has BGRA8888, unpack_subimage, read_format_bgra, OES_EGL_image(_external).
    **Direct GL calls through hybris libGLESv2 work** (FBO clear readback correct).
  - Design: patched wlroots 0.20.2 (same as Arch's wlroots0.20 that labwc 0.20.2 links), installed to
    `/usr/local/pad` and picked up with `LD_LIBRARY_PATH=/usr/local/pad/lib` (system wlroots untouched).
    Source of the changes: `wlroots-pad/` (apply.py patches a pristine tree; render/hybris.c = renderer +
    AHB allocator + dma-buf->EGLImage lookup by inode; backend/pad/pad.c = DSI-1 output with only
    SETCRTC/ADDFB2/PAGE_FLIP, PAD_TRANSFORM default 90). Fetch: scripts/64; build: scripts/66 (out
    /build/out/wlroots-pad.tar). Env: `WLR_RENDERER=hybris WLR_BACKENDS=pad,libinput LIBSEAT_BACKEND=seatd`.
  - Tablet now has labwc seatd xorg-xwayland foot grim wlr-randr (pacman over Wi-Fi). Test:
    `tools/tab-labwc-test.sh` (stops XFCE, runs labwc + foot, grim screenshot /tmp/labwc-shot.png, restarts XFCE).
- **01:25 (11-10) WEB SERVER, CLOUDFLARE TUNNEL, CODEX (side session; browser video decode is a separate,
  unfinished task in the other session).** Matt: "add cloudflare access, codex access, and the modern equivalent of a
  LAMP server (maybe MEAN/MERN)", then "not committed to a specific entity, just something to host a good website on".
  - Installed (`tools/push-web.sh` -> `tools/tab-web-install.sh`, files in `config/web/`): Caddy 2.11 on :80 (React
    build from `/srv/web/app/client/dist`, `/api/*` -> Node on 127.0.0.1:3000), `archpad-web-app.service` (user `web`,
    Express 5 starter in `/srv/web/app`, notes demo), SQLite via Node 26's built-in `node:sqlite`
    (`/srv/web/app/data/site.db`), cloudflared 2026.10 + `cloudflared.service`, Codex CLI 0.167 (`npm -g @openai/codex`).
  - No database server: **this kernel has no System V IPC** (`shmget` -> ENOSYS). PostgreSQL's initdb fails on it;
    MongoDB 9.0.4 (official aarch64 tarball, Arch has no package) aborted at start before logging, likely the same.
    Both removed again (the install script cleans them up). MariaDB is in the repo and may work (untested). Enabling
    CONFIG_SYSVIPC needs a kernel rebuild + boot_a flash (Matt present).
  - Verified: site + API from the PC over Wi-Fi (http://192.168.1.140), and a 20 s trycloudflare quick tunnel
    (no account) served /api/health through Cloudflare's atl01 edge; tunnel stopped, test note deleted.
  - Waiting on Matt: (1) Cloudflare dashboard > Zero Trust > Networks > Tunnels > create a tunnel (Cloudflared),
    copy the token, then on the tablet `echo 'TUNNEL_TOKEN=<token>' | sudo tee /etc/cloudflared/tunnel.env;
    sudo chmod 600 /etc/cloudflared/tunnel.env; sudo systemctl start cloudflared`, and add a public hostname ->
    `http://localhost:80` (optionally SSH -> `ssh://localhost:22` behind a Cloudflare Access policy). (2) `codex login
    --device-auth` in a terminal on the tablet (or `codex login` with an API key). I can't enter either credential.
  - Caveats for real hosting: tablet must stay on the charger (charge limit not known), Wi-Fi only.
- **18:30 (11-10) SCREEN OFF: POWER BUTTON AND IDLE (RESUME HERE).** Matt: "Screen off on the power button or after
  idle is perfect" (real suspend not attempted: kernel offers only s2idle; display/Wi-Fi/Android-service resume untested).
  - Before this, a power-button press did a clean **systemd poweroff** (logind default HandlePowerKey=poweroff); that
    was the 18:02 "restart" in the entry below.
  - `config/screen/archpad-screend` (root service `archpad-screend.service`, Python, no deps):
    - Screen off = `/sys/class/leds/lcd-backlight/brightness` 0 (0-255, default 102); the display pipeline keeps running,
      so no display-driver calls. Brightness is remembered.
    - Grabs `mtk-pmic-keys` (event0: KEY_POWER + KEY_VOLUMEDOWN): short press toggles, 4 s hold = `systemctl
      poweroff`. Volume down goes back to the desktop through a uinput device ("archpad-screend keys").
    - While off, grabs `himax-touchscreen` and `lenovo-stylus` so taps do nothing.
    - FIFO `/run/archpad-screen/ctl` (on/off/toggle), state in `/run/archpad-screen/state`; CLI `archpad-screen`.
    - Hall sensor `hall_irq` (event5) sends vendor key codes 750-753; which is close/open is unknown (no events while
      recording 40 s). Set HALL_CLOSE/HALL_OPEN in `/etc/archpad/screen.conf` to enable cover on/off.
  - Idle: `archpad-screen idle` = swayidle (ext-idle-notify; honours idle inhibitors, so playing video in Chromium/
    Firefox/mpv keeps the screen on) started from `/etc/xdg/labwc/autostart`; IDLE=300 s in /etc/archpad/screen.conf.
  - logind drop-in `50-archpad-powerkey.conf`: HandlePowerKey=ignore (until the service starts), long press poweroff.
  - Install: `tools/push-screen.sh`. Tested: off/on from the CLI (brightness 0 -> 102 restored).
- **18:15 (11-10) STUCK ON "HELLO MOTO" AFTER A RESTART.** Matt powered off (clean systemd power-off
  18:02:31), turned it on, pressed the power button once more. Sequence found:
  1. 18:02:53 Arch boot died ~1 s into userspace (journal boot -1 has 7 lines; no error logged). Most likely the
     extra power-button press reset it.
  2. The bootloader then started the **stock Android kernel from slot B** (pstore console-ramoops: `5.15.185-android13-
     8-...ab14024729`, dm-verity "Hash device is too small", "Attempted to kill init" panic at 2 s), even though misc
     (`/dev/sdc1`, offset 2048, BCAB) says slot A priority 15 / successful, slot B priority 14 / tries 0. Why LK
     tried B is not known.
  3. Back on Arch, the boot-loop breaker saw the unfinished 18:02:53 boot and held at the telnet console. The screen
     keeps the boot logo there, which looks like a hang. `reboot -f` from the console -> normal boot, desktop fine.
  - Gadget moved to usbipd busid **3-1** (was 2-1): attach with `usbipd attach --wsl --busid 3-1 --auto-attach`.
  - Ideas: show something on screen when the breaker holds (part of the boot-splash idea); consider making slot B
    unbootable in misc (priority 0) so LK can't wander there (needs care: CRC32 over the struct).
  - Boot logo: Matt picked an Arch wallpaper (blue mark + "archlinux" wordmark on dark blue with light streaks), saved
    locally as `config/logo/local/arch-wallpaper.webp` (git-excluded: third-party art with the Arch trademark).
    Replaced by our own `config/logo/arch-logo-glow.png` (`draw-arch-logo.py --style glow`, same look, committable);
    **Flashed 18:20 (11-10)** (`--pad-to 24641536`, dd from Arch, readback sha256 match); LK accepts the unsigned
    image and boots on. Stock backup: /home/matt/logo_a.stock.bin (tablet) and /build/out/logo/ (WSL), sha256 866ff62b...
- **11:15 (11-10) CHROMIUM GPU COMPOSITING + HARDWARE VIDEO DECODING.** Matt: "Why does it have to stay
  off? Go ahead and build it." (also: README thanks/license section for a Reddit post, done in `32a1873`).
  - Result: `chromium-gpu` now runs Chromium with **GPU compositing** (chrome://gpu `gpu_compositing: enabled`) and
    Chromium's own **V4L2 video decoder** on the MediaTek decoder for H.264 and VP9. 1080p, CPU as share of one core
    (`tools/tab-crv.sh`, `tools/crv-cpu.sh`):
    - H.264 1080p60: old setup (software compositing) 212 %, ~13 % frames dropped; GPU compositing + software decode
      228 %, 2 drops; GPU compositing + hardware decode **153 %, 1 drop in ~1600**.
    - VP9 1080p30: old 222 %; hardware **104 %** (renderer 18 %, GPU process 76 % - mostly the CPU untiling).
    - H.264 1080p30: 112 % (was 153 %).
    - HEVC fails in Chromium's V4L2 path (it picks its older V4L2VideoDecoder backend, "DecoderStatus::201" after two
      packets); Chromium could not play HEVC before either (no HEVC in its FFmpeg). The launcher sets
      `MTK_V4L2_SHIM_NO_HEVC=1` so the shim hides HEVC and sites aren't offered it.
  - Pieces:
    1. `tools/src/archpad-gbm.c` -> `/usr/local/lib/archpad-gbm/libgbm.so.1` (LD_PRELOAD by chromium-gpu, soname
       libgbm.so.1 so it also satisfies Chromium's DT_NEEDED). GBM on AHardwareBuffers (libhybris android_dlopen of
       libnativewindow); warm-up allocation in gbm_create_device (same EGL gotcha as wlroots-pad). Exports
       `archpad_gbm_ahb_from_dmabuf_fd` (for libhybris) and `archpad_gbm_dmabuf_layout` (for the shim). Sends every
       new buffer to the compositor (`AHardwareBuffer_sendHandleToUnixSocket`, `$XDG_RUNTIME_DIR/archpad-ahb.sock`,
       first byte 'A'; frees as {dev, ino} on a 'F' connection). Chromium flag `--render-node-override=/dev/dri/card0`
       (its path finder only takes real render nodes). Chromium is BIND_NOW: every gbm symbol it imports must exist.
    2. `scripts/libhybris-dmabuf-import.pl` (in scripts/62): eglCreateImageKHR(EGL_LINUX_DMA_BUF_EXT) -> look up the
       AHardwareBuffer through `archpad_gbm_ahb_from_dmabuf_fd` (dlsym RTLD_DEFAULT) -> EGL_NATIVE_BUFFER_ANDROID.
       Advertises EGL_EXT_image_dma_buf_import only in processes that have that symbol (others unchanged).
    3. wlroots-pad: `render/hybris.c` listens on archpad-ahb.sock, keeps received AHardwareBuffers by dma-buf inode,
       and `wlr_hybris_create_image` uses them for client dma-bufs (drains the sockets on a miss, since the buffer is
       sent before Chromium's browser process creates the wl_buffer). `wlr_egl_dup_drm_fd` returns a card0 fd under
       hybris, which turns on linux-dmabuf (the old "Failed to get renderer DRM FD"). New harmless log line at
       start: "Failed to pick primary buffer format for output" (desktop fine).
    4. Shim (`tools/src/mtk-v4l2-shim.c`):
       - **ioctl request normalized to 32 bits**: Chromium passes `int` requests, so _IOR/_IOWR numbers arrived
         sign-extended and no case matched (Chromium saw raw 'H265'/'M21S' and found "No devices").
       - VIDIOC_EXPBUF on MMAP CAPTURE buffers (Chromium's stateful decoder wraps its frames as dma-bufs): a GBM NV12
         buffer per index, filled at every dequeue.
       - DMABUF CAPTURE queues (client's own dma-bufs) supported too (not used by Chromium in the end).
       - MediaTek's gralloc has **no NV12**: Y8Cb8Cr8_420 and every other 4:2:0 request come back NV21 (probe:
         `tools/src/gbm-nv12-probe.c`). GBM still offers NV12; the GPU samples the AHardwareBuffer by its real format,
         and the shim writes chroma as VU (`detile_vu_rows`, NEON) after asking archpad_gbm_dmabuf_layout. Colors
         verified on the test pattern.
       - **Deadlock fix**: frame copy (dma-buf sync waits for the GPU) and GBM allocation now run without the shim's
         lock. Mali's own threads call our close()/munmap() wrappers to finish GPU work; holding the lock there hung
         Chromium's GPU process ~1 run in 6 (watchdog kill, exit_code=512, no core dump). Found with gdb thread dumps.
       - `MTK_V4L2_SHIM_NO_HEVC=1` hides HEVC from ENUM_FMT.
       - mpv/Firefox paths unchanged (ffmpeg HEVC/VP9 still bit-exact; the H.264 frame-30 spot check gives PSNR 20 with
         the old build too: frame selection by output index, not a decode error).
    5. `config/chromium/chromium-gpu`: GPU compositing when the GBM lib and the compositor socket exist (else the old
       --disable-gpu-compositing); hardware decoding adds the shim and
       `--enable-features=AcceleratedVideoDecoder,AcceleratedVideoDecodeLinuxGL,PreferV4L2VideoAcceleration`
       (both VA-API and V4L2 are compiled in; VA-API wins without PreferV4L2VideoAcceleration).
       Off switches: `ARCHPAD_CR_GPU_COMPOSITING=0`, `ARCHPAD_CR_HWDEC=0`.
  - Install: libhybris (scripts/62 + tools/tab-hybris-install.sh), wlroots-pad (scripts/66 + tools/tab-wlr-install.sh,
    restarts the desktop), then `tools/push-crgpu.sh` and `tools/push-vdec.sh` (shim). Backup of the previous shim
    on the tablet: /usr/local/lib/libmtk-v4l2-shim.so.c7f8c6f.
  - **YouTube** (`tools/tab-cryt.sh`): YouTube sends Chromium **AV1** (software dav1d, ~1.2 cores). Chromium has no
    switch to drop AV1, so `config/chromium/no-av1/` (tiny MV3 extension, MAIN-world content script on youtube.com,
    installed to /usr/local/share/archpad/chromium-no-av1) reports av01 as unsupported in isTypeSupported/canPlayType/
    mediaCapabilities. chromium-gpu loads it with `--load-extension` (+ `--disable-features=DisableLoadExtension
    CommandLineSwitch`) while hardware decoding is on; `ARCHPAD_CR_AV1=1` keeps AV1. Result: Big Buck Bunny on
    YouTube -> VP9, V4L2VideoDecoder, all Chromium 98 % (vs 124 % with AV1 at 480p).
  - Stability after the deadlock fix: 2 GPU-process restarts in the first 10 runs (both in the first seconds, cause
    not caught), then 0 in 16 runs in a row (`tools/tab-crv.sh` loop with a gdb dump on freeze). Chromium restarts the
    GPU process by itself; a restart costs a few seconds of video.
  - Not tried: long sessions, many tabs, Matt on real sites.
- **10:15 (11-10) CHROMIUM VIDEO DECODING: BLOCKED BY SOFTWARE COMPOSITING.** Matt: "Chromium video decode".
  - Result: not possible as `chromium-gpu` is set up now. Nothing installed or changed on the tablet except a
    `/dev/video-dec0 -> video1` symlink (harmless, gone after reboot). Chromium still decodes in software.
  - Why the Firefox trick doesn't carry over: Chromium 156 (Arch Linux ARM) has FFmpeg **statically linked** (no
    libavcodec in `ldd`; only dav1d/openh264), so its decoder calls can't be interposed. Software decoding also runs
    in the seccomp-sandboxed renderer, which would refuse V4L2 ioctls.
  - Chromium's own V4L2 decoder is compiled in (`V4L2VideoDecoder`, stateful backend) next to VA-API. Findings:
    - Both built -> VA-API is chosen unless `--enable-features=PreferV4L2VideoAcceleration` (media/base/decoder.cc
      `ActiveLinuxVideoDecoderType`). With it, the GPU process enumerates `/dev/video*` itself (no symlink needed) and
      sees H264/VP9 through the shim. HEVC is skipped: the driver's ENUM_FMT says `H265`, Chromium wants `HEVC`
      (the shim only renames it in S_FMT/TRY_FMT paths; renaming in ENUM_FMT too would fix that).
    - **The blocker:** `RenderThreadImpl::GetGpuFactories()` returns null when GPU compositing is off ("VideoResourceUpdater
      can't convert hardware resources to software resources"), so the renderer never even offers MojoVideoDecoder
      (media log lists only Decrypting/Vpx/Dav1d -> "Selected FFmpegVideoDecoder"). `chromium-gpu` must use
      `--disable-gpu-compositing` because Chromium on Wayland presents GPU-composited frames only as dma-bufs.
  - What it would take (all of it is also what Chromium needs for GPU compositing, i.e. no per-frame readback):
    1. A small libgbm for Chromium's GPU process that allocates through AHardwareBuffer/gralloc and exports dma-bufs.
    2. A render-node path for Chromium (it gets it from the compositor's linux-dmabuf feedback / wl_drm).
    3. libhybris EGL: advertise `EGL_EXT_image_dma_buf_import` and map a dma-buf back to its AHardwareBuffer (by inode,
       as wlroots-pad's hybris renderer already does) -> EGLImage. The Mali EGL has no dma-buf import of its own.
    4. wlroots-pad: linux-dmabuf protocol with that same import.
    5. Shim: DMABUF capture buffers (Chromium hands the decoder NV12 pixmaps), detiling straight into them.
    Each step can fail on something unknown (ANGLE's NV12 external-image checks, Chromium's GBM modifier probing).
  - Test tools (new): `tools/tab-crv.sh` + `tools/crv-list.tmpl` (Chromium plays /tmp/vdec clip in `tools/ffv.html`,
    now Chromium-aware via console.log), `tools/crv-cpu.sh` (CPU of all Chromium / GPU process / renderers),
    `tools/cdp.py` (stdlib DevTools client: `gpu` = feature status + HW decode profiles, `media N` = which decoder
    each player picked, media log). `ffv.html` also prints mediaCapabilities (powerEfficient = HW decoder offered).
  - Baseline, 1080p30 H.264 in Chromium, software: plays at 30 fps, ~5-10 drops per loop start, all Chromium ~153 %
    of a core (renderer 95 %, GPU process 48 %).
- **02:15 (11-10) FIREFOX HARDWARE VIDEO DECODING.** Matt: "Browser video decode".
  - Result: Firefox (menu entry / `firefox-gpu`) decodes H.264 and HEVC up to 40 fps on the MediaTek decoder, with
    Firefox's RDD sandbox on and no prefs. 1080p30 H.264 (`tools/gpu-apps-68.txt`, the installed launcher): plays,
    loops, seeks; dropped frames same as software (~25 in the first 10 s, then ~0); RDD process 12-16 % of a core vs
    79 % in software. All of Firefox is still ~250 % (rendering/compositing), so the saving is ~0.6-1 core.
  - How (`tools/src/ff-v4l2-redirect.c` -> `/usr/local/lib/libff-v4l2-redirect.so`, LD_PRELOAD by `firefox-gpu`
    together with the shim and `MTK_V4L2_SHIM_FORMAT=i420`):
    - Firefox's own V4L2 path needs a DRM render node + EGL dma-buf import (gfxPlatformGtk: HW decode requires
      UseDMABuf; DMABufDevice "missing DRM render device"), so it is unusable here. Instead the redirect wraps
      `dlsym` (Firefox dlsym's every libavcodec function; unwrapped calls tail-call glibc's dlsym so RTLD_NEXT
      lookups by the shim and the sandbox still see the right caller) and hands out wrappers for avcodec_open2 /
      send_packet / receive_frame / flush_buffers / free_context.
    - When Firefox opens the system-FFmpeg h264/hevc software decoder, a private `*_v4l2m2m` context is opened from
      the same parameters and does the work; Firefox's context stays open but idle. FFmpeg's V4L2 decoders have no
      flush callback (after EOF they return EOF forever; after a seek old frames keep coming), so every flush
      replaces the private context with a fresh one.
    - Sets pkt_timebase 1/1000000 (Firefox sets none -> every frame pts was AV_NOPTS) and fills frame durations
      (V4L2 gives 0 -> Firefox dropped ~50 % as late and never got past the end of a loop).
    - First two packets are held to measure the frame rate: above 40 fps (`ARCHPAD_FF_HWDEC_MAXFPS`) the stream stays
      in software. Reason: Firefox waits for each frame, and the hardware path then manages only ~50 fps, so 1080p60
      dropped ~90 % (software 1080p60 drops ~20 % at ~4.4 cores).
    - Firefox's copy path logs "Failed to copy image data" for every frame in the RDD, in software too (texture
      allocation fails there); frames still display. Harmless, not ours.
  - Shim changes: `MTK_V4L2_SHIM_FORMAT=i420` (planar YUV420; Firefox's software path only takes planar frames, NV12
    failed its plane-layout check); NEON chroma split and untiling on 2 threads (`MTK_V4L2_SHIM_THREADS`), which also
    sped up mpv's path (ffmpeg through shim: H.264 85, HEVC 75-93, VP9 53-56 fps 1080p, were 66-82/71-90/40-43);
    timestamps unwrapped (driver keeps only 32 bits of microseconds: negative pts came back as +4295 s and Firefox
    waited forever; now rebuilt from the last queued bitstream timestamp); up to 16 decoder instances per process
    (was 4); decoder node lookup and dma-heap open moved to library load, because Firefox's RDD sandbox refuses
    `/sys/class/video4linux` and `/dev/dma_heap` later (that was the "decoder opens but no frames" with sandbox on).
    Every-frame check still identical for H.264/HEVC/VP9 in both NV12 and I420.
  - Not covered: YouTube. It sends VP9/AV1, which Firefox decodes with its bundled FFmpeg (ffvpx, no V4L2 decoders);
    `media.mediasource.vp9.enabled=false` did not change that (tested, `tools/tab-ffyt.sh`). An extension such as
    h264ify (H.264, max 1080p) would make YouTube use the hardware path; not installed. VP9 through the redirect would
    need ffvpx -> system-FFmpeg frame conversion (different libavcodec majors): possible later. Chromium: not done.
  - Seeking in clips with sparse keyframes is slower than software (decode to the target at ~50 fps).
  - Tests: `tools/tab-ffv.sh` (RUNS=clip:hwdec[:seek]; `tools/ffv.html` page prints Firefox's playback-quality stats
    via dump(); `tools/ffv-cpu.sh` CPU of all Firefox processes / RDD), clips in /tmp/vdec (tmpfs, gone after reboot).
  - Not yet tried by Matt on a real site.
- **23:45 (11-09) FASTER VIDEO DISPLAY.** Matt: "Faster video display".
  - Cause found: mpv's default scalers (gpu-next default profile) cost ~65 ms/frame full screen on the Mali -> 1080p ~15 fps
    untimed. Window size made no difference with `--profile=fast` (bilinear), so the rest is a fixed per-frame cost.
    Clean benchmarks (300 frames 1080p60, `--untimed --framedrop=no`, `tools/gpu-apps-62.txt`): default 20.5 s,
    profile=fast hw 6.9 s (~47 fps), fast sw 6.7 s (2x the CPU). Swap interval, PBO upload, gpu vs gpu-next: no change.
    perf (`tools/tab-perf-mpv.sh`): shim untile ~17 %, vo memcpy (texture upload) ~8 %, Mali ~9 %, cache maintenance.
  - Fix: wrapper adds `--profile=fast` (plus display-resample). Real-time result (`tools/gpu-apps-66.txt`): 1080p60
    H.264 vfps 60, 0 dropped, A/V in sync; 1080p30 H.264/HEVC/VP9 0 dropped. Every-frame check still identical.
  - Shim fixes: release held frames when the driver is down to its minimum CAPTURE buffers (V4L2_CID_MIN_BUFFERS_FOR_
    CAPTURE + 1, tracked by QBUF/DQBUF count) so a client that holds many frames cannot deadlock it; get_ctx ignores fd -1.
  - Do NOT use mpv `--vd-queue-enable`: mpv then holds every decoded frame, all 20 V4L2 capture buffers fill and the
    decoder stops (FFmpeg v4l2m2m limit, shim holds none at that point).
  - Test-harness trap: commands that pipe mpv's status line (`| tr | grep | tail`) leave mpv spinning at 100 % CPU
    on the dead pipe when the harness SIGINTs the pipeline; two such leftovers skewed earlier numbers. Write mpv
    output to a file instead (gpu-apps-62+ do), and `pkill -9 -x mpv` before benchmarking.
  - Still possible later: zero-copy (dma-buf of the untiled frame -> compositor) would save the upload copy.
- **22:45 (11-09) HARDWARE VIDEO DECODING.** Matt: "do videos have gpu accel as well?" -> "Yes, try it".
  - Hardware: `/dev/video1` = `mtk-vcodec-dec` (stock vendor module mtk_vcodec_dec_v1 + vcp; the VCP co-processor
    firmware is already running, loaded by the bootloader). Output formats H264, H265, VP90, MPG4, H263, HEIF up to
    2560x1440; capture only `M21S` (8-bit, luma 16x32 tiles, interleaved chroma 16x16 tiles, planes back to back).
    No Android services needed. Driver source (close to the loaded build): Nest's kernel_device_modules-5.15
    (sparse clone in WSL `/build/src/kdm`, `drivers/media/platform/mtk-vcodec/`).
  - Driver quirks found: (1) MMAP bitstream buffers have no kernel mapping -> worker spams "src_addr is NULL" and never
    decodes; DMABUF (dma-heap `system`) works. (2) Frames are dequeued out of display order (each keeps its own
    timestamp). (3) HEVC fourcc is 'H265'. (4) Negative timestamps come back wrapped mod 2^32 us. Drain via
    DECODER_CMD STOP works.
  - `tools/src/vdec-test.c`: raw V4L2 test (Annex-B H.264 by access unit, dma-heap input). 1080p 115 fps, 720p 220 fps.
    `tools/src/mm21-to-nv12.c` untiles a dump; frame 30 bit-exact vs software.
  - `tools/src/mtk-v4l2-shim.c` -> `/usr/local/lib/libmtk-v4l2-shim.so` (LD_PRELOAD, only touches the mtk-vcodec-dec fd):
    client MMAP queues become DMABUF queues on cached dma-heap buffers (fake mmap offsets); capture reported as NV12
    and untiled into a private copy on DQBUF; H265<->HEVC; frames held and released in timestamp order (depth 6,
    `MTK_V4L2_SHIM_REORDER`; wrap-safe compare) with poll() reporting held frames; `MTK_V4L2_SHIM_DEBUG=1` logs.
  - Verified with FFmpeg h264/hevc/vp9_v4l2m2m on 1080p test clips: every frame identical to software decoding
    (`tools/tab-vdec-h264chk.sh`). Decode speed through the shim: H.264 ~66-82 fps, HEVC ~86-90, VP9 ~40 (VP9 is the
    slow one, firmware or untile cost, not investigated).
  - mpv: `/usr/local/bin/mpv` wrapper (`config/video/mpv`) = shim + `--hwdec=v4l2m2m-copy` + `--video-sync=display-resample`
    + hybris-run; menu entry points at it. udev rule `config/video/70-archpad-dma-heap.rules` (dma_heap/system ->
    group video 0660). Install: `tools/push-vdec.sh` (WSL) -> `tools/tab-vdec-install.sh`. gcc is now on the tablet.
  - mpv results (GPU desktop, fullscreen, `tools/gpu-apps-52..55.txt`): hwdec CPU ~0.5 core vs ~1.1 core software at
    1080p60. The render/present path manages only ~37 fps at 1080p fullscreen (same with software decode, both gpu and
    gpu-next VOs), so with mpv's default sync 30 fps video dropped half its frames; display-resample: 0 drops at 30 fps,
    A/V in sync at 60 fps (shows ~35 fps). Screenshot `shots/mpv-hwdec.png`.
  - Not done / next: (a) [done 23:45: mpv profile=fast] faster presentation for video (zero-copy
    would need dma-buf import of the decoder buffers, which are tiled); (b) browsers (Firefox can use FFmpeg V4L2 decoding
    only on some builds; Chromium needs its own V4L2 path); (c) 10-bit (MT21S10* formats, not mapped); (d) VP9 speed.
    Not tested by Matt with a real video yet.
- **20:25 (11-09) CHROMIUM ON THE GPU.** Matt: "Yes, try Chromium".
  - Three libhybris changes (all in scripts/62, idempotent perl patches on egl.c):
    1. `libhybris-surfaceless.pl`: client extensions add EGL_MESA_platform_surfaceless, EGL_KHR_platform_gbm,
       EGL_MESA_platform_gbm; platforms 0x31DD (surfaceless) and 0x31D7 (GBM) map to the "null" ws (plain Android),
       or the already-loaded ws. Chromium's GPU process asks for GBM with a NULL device.
    2. `libhybris-procaddr-self.pl`: eglGetProcAddress("egl*") returns libhybris' own exported function first. ANGLE
       loads every entry point through eglGetProcAddress; before, it got Android's raw functions.
    3. Trace now has a verbose level: `ARCHPAD_EGL_TRACE=2` also logs every eglGetProcAddress/eglQueryString.
  - Result (ANGLE gles-egl on Mali): chrome://gpu shows Canvas, Rasterization, WebGL, WebGPU hardware accelerated;
    GL_RENDERER "ANGLE (ARM, Mali-G57 MC2, OpenGL ES 3.2)". Compositing is software (no DRM render node -> no
    dma-buf presentation). With GPU compositing left "on" in the renderer, every WebGL context was lost right after
    its first frame (it hands frames over as GPU shared images the software compositor can't use);
    `--disable-gpu-compositing` makes WebGL use readback: spinning triangle 90-91 fps, stable 40 s maximised.
  - `config/chromium/chromium-gpu` -> /usr/local/bin (hybris-run + `--ozone-platform=wayland --ignore-gpu-blocklist
    --disable-gpu-sandbox --use-gl=angle --use-angle=gles-egl --disable-gpu-compositing`), menu override
    /usr/local/share/applications/chromium.desktop (`tools/tab-chromium-gpu-install.sh`). The GPU-process sandbox
    has to be off (seccomp vs binder); renderers keep their sandbox. Chromium shows an "unsupported command-line
    flag" bar for it. Vulkan errors in the log are harmless (no Vulkan on this path).
  - Regression check after restarting the desktop on the new libhybris: labwc OK (4 scan-out buffers), glmark2 720,
    Firefox WebGL 1/2 OK, Chromium from the menu OK. Shots: `shots/chromium-gpu-*.png`.
  - Test pages: `tools/web/webgl-check.html`, `tools/web/webgl-anim.html` (?v=webgl2, ?aa=0). chrome:// URLs on the
    command line are ignored; open them with `--remote-debugging-port=9222` + `curl -X PUT .../json/new?chrome://gpu`.
- **18:25 (11-09) WEBGL 1 IN FIREFOX WORKS; ARCH BOOT LOGO READY.**
  - Cause: Firefox's WebGL 1 path passes context attribute `0x3483=0` to eglCreateContext; Mali rejects every such
    context with EGL_BAD_ATTRIBUTE (0x3004). WebGL 2 does not send it. Found with a new optional libhybris EGL trace
    (`scripts/libhybris-egl-trace.pl`, env `ARCHPAD_EGL_TRACE=1`, logs display/bind/config/context/pbuffer calls and
    failed proc lookups to stderr). Fix: `scripts/libhybris-ctx-attribs.pl` drops `0x3483=0` (the default) in
    libhybris' eglCreateContext. Both wired into scripts/62; installed with `tools/tab-hybris-install.sh`.
  - Verified: `tools/web/webgl-check.html` in firefox-gpu shows webgl and webgl2 both on the Mali GPU and draws a
    WebGL 1 triangle (`shots/firefox-webgl1.png`). Firefox reports the GPU as "Mali-G51, or similar" (its generalised name).
  - Boot logo (subagent, NOT flashed): logo_a is classic MTK logo.bin (512-byte header 0x58881688, 123 zlib frames,
    BGRA8888 1600x2560; frame 0 = boot logo, landscape picture rotated 90 CW). `tools/make-logo.py` (info/extract/
    build/check) rebuilds stock bit-exactly; `config/logo/arch-logo.png` + `draw-arch-logo.py`; output
    `out/logo/arch-logo.bin` (git-ignored). Backup/flash/readback/restore commands in `config/logo/README.md`.
    Risk: the image is unsigned; LK may require a signed logo even unlocked (unverified). Flash only with Matt present,
    after a backup (`dd if=/dev/disk/by-partlabel/logo_a` works from running Arch).
- **18:10 (11-09) HEADPHONE JACK.** Matt picked it; he has not plugged anything in yet (needs his ears).
  - Jack: input device "mt6835-mt6377 Headset Jack" (event4, MT6377 ACCDET) reports SW_HEADPHONE_INSERT /
    SW_MICROPHONE_INSERT / SW_LINEOUT_INSERT. `tools/pad-jackd` (python, /usr/local/sbin, `pad-jack.service`) reads the
    state with EVIOCGSW at start, then follows events. Install: `tools/tab-jack-install.sh` (push pad-jackd first).
  - Headphones in (stock audio_device.xml `headphone_output`): `DAC In Mux=Normal Path`, `HPL/HPR Mux=Audio Playback`,
    `Headphone Plugged In=On`, `Headset Volume=12,12` (index: 0=+8dB, 8=0dB, 18=-10dB, 31=-40dB, from
    Volume_AudioParam.xml; override with PAD_HP_GAIN), speakers off (`Ext_Speaker_Amp Switch=off`, aw87xxx profiles
    Off, `LOL Mux=Open`). Out: HP muxes Open, then pad-audio-speaker.
  - Headset mic (stock `headset_mic_input`): `PGA_L_Mux=AIN1` instead of the built-in AIN0, so the existing
    "Built-in Microphone" PipeWire source carries it. Self-test `tools/tab-jack-selftest.sh` applies both routes and
    reads every control back: all correct. NOT verified by ear: plug in headphones, play something, check level.
  - Boot logo: a subagent is preparing a clean Arch logo.bin + `tools/make-logo.py` (no flashing).
- **16:50 (11-09) CLAUDE CODE ON THE TABLET.** Matt's wish from earlier.
  - `tools/tab-claude-code-install.sh`: nodejs + npm + git + ripgrep from pacman; `npm install -g
    @anthropic-ai/claude-code` as matt with prefix ~/.local (PATH added to ~/.bashrc). The npm postinstall that fetches
    the native linux-arm64 binary did not run the first time; `node install.cjs` in the package dir fixed it.
    `claude --version` = 2.1.321. NOT signed in: Matt runs it once and logs in through the browser.
  - Menu entry Applications > Development > Claude Code (`config/claude-code/claude-code.desktop` ->
    ~/.local/share/applications): xfce4-terminal running claude. squeekboard switches to its terminal layout
    (Esc/Tab/Ctrl/Alt/arrows) in the terminal. Screenshot `shots/claude-code-tablet.png`.
  - Installed noto-fonts (wider symbol coverage). Note: the test harness (`tools/tab-gpu-apps.sh`) now exports
    LANG=en_US.UTF-8; without it xfce4-terminal ran in "C" and UTF-8 symbols looked broken (harness-only problem;
    the desktop session has LANG=en_US.UTF-8).
- **16:45 (11-09) DOUBLE-BUFFERED SCAN-OUT; WEBGL 1 NOTES.**
  - Tearing fix in `wlroots-pad/backend/pad/pad.c`: the backend now locks the buffer handed to drmModePageFlip
    (`queued`) and the one on screen (`current`), releasing the old one on the flip event. Before, wlroots could render
    the next frame into the buffer being scanned out. labwc now holds 4 scan-out dma-bufs; glmark2 build 637 fps (was
    616); desktop verified.
  - WebGL 1 in Firefox still fails ("tryNativeGL FEATURE_FAILURE_EGL"). Findings: Firefox tries desktop GL first
    (eglBindAPI(OPENGL) fails -> that failureId), then GLES 2. `tools/src/ctx-probe.c` (scripts/71): Mali accepts ES2
    and ES3 no-config contexts plain, with EXT robustness, and via CLIENT_VERSION; it rejects EGL 1.5/KHR robust-access
    attributes (0x31B2 or CONTEXT_FLAGS robust bit) for both versions, which Firefox retries past. No GL spew for the
    WebGL 1 attempt (MOZ_GL_SPEW=1), so it fails before a context exists. Next idea: gdb is too slow on Firefox; add a
    trace in libhybris' eglCreateContext/eglChooseConfig instead, or try pref webgl.1.request_es2=false / gfx.egl.prefer-gles.enabled.
- **16:35 (11-09) ON-SCREEN KEYBOARD + XWAYLAND.** Matt: "Lets keep going!".
  - squeekboard (extra) autostarts in the GPU desktop (`config/labwc/autostart`, `tools/tab-osk-install.sh`) and pops up
    on text fields by itself (text-input-v3 / input-method-v2 / virtual-keyboard, all offered by labwc). Landscape
    scale 0.7 (`gsettings sm.puri.Squeekboard scale-in-horizontal-screen-orientation`). Screenshot `shots/osk-2.png`.
    Typing by touch not tested by hand. Onboard (X11-only) still serves the Xorg session.
  - Package installs need `pacman -Sy` first whenever the mirror has moved (404s otherwise); nothing else was out of date.
  - Xwayland: labwc starts it on demand (DISPLAY=:0 for apps); a GDK_BACKEND=x11 GTK app shows fine
    (`shots/xwayland-1.png`). X11 apps render in software (no DRI3/render node). xwm "xcb error ... Window" lines on
    close are harmless.
- **16:20 (11-09) GPU FIREFOX WORKS.** Matt: "Yes, try Firefox", full permission; "if this all works for
  gpu hardware accel you can make the repo public".
  - Measured (`tools/src/tls-probe.c`, scripts/70): Android's GL wrappers write exactly tp+24 (TLS_SLOT_OPENGL, current
    context) and tp+32 (TLS_SLOT_OPENGL_API, GL hooks) on every thread that makes a context current. Loading Mali
    directly (LIBEGL/LIBGLESV2 env) still writes tp+24 and breaks makeCurrent on a 2nd thread: not an option.
  - Firefox's executable has 56 bytes of local-exec TLS at tp+0x10..0x48 used by mozjemalloc/PHC (malloc, moz_arena_*),
    so a save/restore swap around GL calls would not be safe (Android code mallocs mid-call).
  - Fix: `tools/ff-tls-relocate.py` writes `/usr/lib/firefox/firefox-hybris` with every relaxed-TLSDESC offset
    (`movz xN,#0,lsl#16; movk xN,#off`, 232 sites found by `tools/tab-ff-tls-scan.sh`, all within the block) moved
    +0x40 and PT_TLS memsz 0x38 -> 0x78. Slots now hit padding. Child processes use the same binary (/proc/self/exe).
  - libhybris: `eglSwapBuffersWithDamageKHR` now maps to libhybris' wrapper (it did only the EXT name); Firefox got
    Android's raw function, buffers were queued but never attached, and dequeueBuffer blocked forever.
  - Result: about:support Compositing "WebRender" (hardware), WebGL 2 "ARM -- Mali-G57 MC2, OpenGL ES 3.2"; 867 GPU
    buffers presented in 30 s (`shots/firefox-gpu-webgl.png`, `shots/firefox-gpu-launcher.png`). WebGL 1 still fails
    (tryNativeGL FEATURE_FAILURE_EGL; probably a GLES2 context/config attribute); sites mostly use WebGL 2.
  - Daily use (`tools/push-firefox-gpu.sh` -> `tools/tab-firefox-gpu-install.sh`, sources in `config/firefox/`):
    `/usr/local/bin/firefox-gpu` (patched binary through hybris-run inside the GPU desktop, plain Firefox elsewhere);
    AutoConfig `/usr/lib/firefox/archpad.cfg` + `defaults/pref/archpad-autoconfig.js` sets the GPU prefs only when
    ARCHPAD_GPU=1; `/usr/local/share/applications/firefox.desktop` uses firefox-gpu; pacman hook
    `/etc/pacman.d/hooks/archpad-firefox-hybris.hook` rebuilds firefox-hybris after Firefox updates (tested with a
    reinstall; on failure it removes the copy so the launcher falls back).
  - WSL idles out and drops the usbipd attachment: keep `wsl -d archlinux -- sleep 86400` running and use
    `usbipd attach --wsl --busid 2-1 --auto-attach`.
- **14:30 (11-09) MORE GPU APPS.**
  - `pacman -Syu` done (only desktop-file-utils + libstemmer were behind; labwc/wlroots0.20 still 0.20.2, held with
    --ignore anyway). Installed mpv 0.41, glmark2, gtk4-demos, firefox 159, ltrace.
  - Works on the GPU via hybris-run: glmark2-es2-wayland (Mali-G57 MC2, GLES 3.2 r38p1; score 353 at 1280x720,
    616 fps "build" at 800x600), gtk4-demo gears (90 fps = panel), mpv (`--vo=gpu` and default `gpu-next`, both after
    Vulkan fails; 720p60 test pattern, ~10 % dropped, decoder 0; `shots/gpu-mpv.png`).
  - mpv fix: libhybris did not list EGL_EXT_platform_base in client extensions; mpv silently gives up without it
    (egl_helpers.c mpegl_get_display). scripts/62 now adds it. Probe: `tools/src/egl-wl-probe.c`
    (`scripts/69-build-egl-wl-probe.sh`) repeats mpv's EGL start-up step by step.
  - Firefox: crashes on the GPU (rc 139, "Renderer" thread). Cause: /usr/lib/firefox/firefox has its own 56-byte TLS
    (tp+16..72), exactly where Android code writes bionic TLS slots; the preload pad cannot move an executable's TLS.
    Needs a glibc with reserved bionic slots. Firefox runs fine in software (`shots/firefox-sw.png`); do NOT use
    hybris-run for it. Check any app with `tools/tab-tls-check.sh` (readelf PT_TLS of the executable: none = OK).
  - Chromium: ANGLE cannot get a system EGL display (see 14:05); stays software.
  - Installed for daily use (`tools/tab-gpu-apps-install.sh`): hybris-run now falls back to a plain exec outside the
    GPU desktop; `/usr/local/share/applications/mpv.desktop` runs mpv through hybris-run; pad-wayland-session starts
    labwc with LD_PRELOAD=bionic-tls-pad.so (inherited by apps, harmless). Session restarted and verified.
- **14:05 (11-09) REAL APPS ON THE GPU.** `tools/tab-gpu-apps.sh` runs each line of the newest
  `/tmp/gpu-apps-*.txt` ("<secs> <command>") through hybris-run in matt's session and screenshots it (example list
  `tools/gpu-apps-1.txt`; push it with pad-scp first). Results:
  - GTK4 (zenity 4.2): GPU. Vulkan instance fails (no Vulkan), GTK falls back to GskGLRenderer on Mali; renders fine
    (`shots/gpu-app-1.png`). GSK_RENDERER=ngl is now called `gl`; GDK_DEBUG=opengl trips libepoxy
    ("No provider of eglQueryDisplayAttribEXT"), harmless.
  - Chromium 156: runs, but SOFTWARE. ANGLE: "Failed to get system egl display" (it wants an off-screen EGL platform,
    e.g. surfaceless, and dma-buf presentation via a DRM render node; libhybris and the tablet have neither).
    Needs real work (libhybris platform support + dma-buf export); deferred.
  - eglinfo -p wayland: EGL 1.4 Android, no dma-buf import/export.
  - Could not install mpv, glmark2, gtk4-demos, firefox: the mirror moved on (404), needs `pacman -Syu` first.
    Risk: an upgraded labwc built for a newer wlroots would break the GPU session (wlroots-pad is 0.20.2);
    use IgnorePkg=labwc wlroots0.20 or rebuild wlroots-pad to match.
  - Keep hybris-run opt-in: a global LD_LIBRARY_PATH would hand hybris libEGL to Xwayland/glamor and other apps.
- **13:50 (11-09) GPU RENDERING FOR APPS WORKS.** es2gears_wayland renders on the Mali GPU inside the labwc
  desktop (screenshot `shots/gpu-client-2.png`), ~690 frames in 8 s (~87 fps, 90 Hz panel = vsync-bound), zero-copy into
  the compositor. Last fix: AHardwareBuffer_createFromHandle method values are REGISTER = 2, CLONE = 3 (1 gave -22).
  Launcher: `/usr/local/bin/hybris-run <app>` (source `config/labwc/hybris-run`): sets LD_LIBRARY_PATH=/usr/local/hybris/lib,
  LD_PRELOAD=bionic-tls-pad.so, HYBRIS_LD_LIBRARY_PATH, EGL_PLATFORM=wayland. Not global on purpose (Xorg and the
  compositor must not load hybris libEGL that way). Next: try real apps (GTK4 GL renderer, Chromium/Firefox with
  EGL, mpv); desktop-file wrappers for the ones that work; Xwayland still untested.
- **13:45 (11-09) GITHUB REPO + GPU APPS IN PROGRESS.**
  - Repo: https://github.com/Mattcabrices/moto-pad-2026-arch-linux (private, branch main, author "Matt Cabrices"
    <961821+Mattcabrices@users.noreply.github.com>, gh CLI signed in). `.gitignore` keeps out `out/` (images, SSH key),
    `tools/.pad-password` (pad-sudo.sh reads the tablet password from it; default `archpad`). `.gitattributes` forces LF.
    Beware: Python on Windows writes CRLF unless `newline=''`; strip `
` before running scripts on the tablet.
  - GPU clients (apps rendering on the Mali GPU) via libhybris wayland-egl + android_wlegl:
    1. wlroots-pad: `wlr_hybris_bind_wl_display()` (from wlr_renderer_init_wl_shm) calls eglBindWaylandDisplayWL and registers a
       wlr_buffer resource interface for android_wlegl wl_buffers; each gets a placeholder memfd "dma-buf" that
       `wlr_hybris_create_image()` maps back to `eglCreateImageKHR(EGL_WAYLAND_BUFFER_WL)`. Built and installed; labwc stays up.
    2. libhybris: `server_wlegl_buffer_from()` now checks the resource type (was unsafe for other buffer types).
    3. Client crash in sscanf: Android code writes bionic TLS slots (tpidr_el0+24..72) which overlap glibc's TLS (locale
       pointer) in programs without TLS. Fix: LD_PRELOAD `/usr/local/hybris/lib/bionic-tls-pad.so`
       (`tools/src/bionic-tls-pad.c`, `scripts/68-build-bionic-tls-pad.sh`). After it: no crash.
    4. Then: "failed to allocate buffer ... format 1 usage 0xb00": libhybris gralloc needs Halium's libui_compat_layer.so
       (absent). Added an AHardwareBuffer gralloc backend (`scripts/libhybris-gralloc-ahb.c`, wired in by
       `scripts/libhybris-archpad-gralloc.pl` from scripts/62; import uses AHardwareBuffer_createFromHandle with the
       buffer description, new `hybris_gralloc_import_buffer_desc`). Rebuilding/testing at 13:45.
  - Test: `tools/push-gpu-client-test.sh` (WSL) -> `tools/tab-gpu-client-test.sh` (es2gears_wayland in matt's desktop, grim
    to /tmp/gpu-client-shot.png); protocol trace `tools/tab-gpu-client-trace.sh`; gdb `tools/tab-gpu-client-gdb2.sh`.
- **13:45 (11-09) TOUCH FIXED ON THE GPU DESKTOP (Matt confirmed "WORKS").** labwc already rotates touch with the output transform, so the Xorg calibration matrix (0 1 0 -1 0 1) rotated it twice (taps landed on the far side) and its opposite was wrong too. Fix: no <libinput> calibrationMatrix in config/labwc/rc.xml; keep only <touch deviceName="himax-touchscreen" mapToOutput="DSI-1">. Installed by tools/tab-touch-fix.sh. Raw axes: x 0..15999 (short side), y 0..25599 (tools/tab-touch-raw.sh). No mouse pointer while using touch is normal on Wayland.
- **12:45 (11-09) ANDROID SERVICES AUTOSTART; GPU DESKTOP SURVIVES REBOOT.** Units in `config/android-units/`, pushed + installed by `tools/push-android-units.sh` (WSL) -> `tools/tab-android-units-install.sh`. pad-android.target (enabled, WantedBy multi-user) wants: pad-android-mount (oneshot, runs tab-android-mount.sh installed as /usr/local/sbin/pad-android-mount via /bin/bash, it has no shebang), pad-android-logd (fake-logd.py), pad-servicemanager / pad-hwservicemanager / pad-vndservicemanager, pad-gralloc (allocator HAL; ExecStartPost /usr/local/sbin/pad-gralloc-wait waits for IAllocator/default in lshal). All Restart=on-failure, run as `chroot /opt/android-full /system/bin/env LD_PRELOAD=/data/local/libpropshim.so <bin>` (preload inside the chroot so Arch ld.so does not complain). getty@tty1 drop-in android.conf: After=pad-android.target (ordering only; if Android fails, login falls back to Xorg). Verified with a real reboot: all units active, labwc started on its own, screenshot `shots/boot-autostart.png`. pad-gralloc restarts once at boot (starts before hwservicemanager is ready; Restart covers it). Undo: `systemctl disable --now pad-android.target`. tab-android-sm.sh / tab-android-alloc.sh / tab-gpu-restart.sh are now only for manual debugging (stop the units first).
- **12:35 (11-09) CHARGER LOG LOOP FIXED.** Cause: a feedback loop. journald enriches each kernel message with device info by reading the device's sysfs `uevent`; for mtk-master/slave-charger that read makes the sc8960x/MTK charger drivers printk 4 lines, which journald reads again. Fix (`tools/tab-journald-fix.sh`): /etc/systemd/journald.conf.d/archpad.conf with ReadKMsg=no, SystemMaxUse=200M, RuntimeMaxUse=50M. Result: 0 journal lines in 5 s (was ~17k/10 s), journald 0% CPU, journal 3.6 GB -> 182 MB. Kernel messages are no longer in journalctl; use `dmesg`. Load average stays ~14 because 13 MediaTek kernel threads (wdtk-*, hang_detect, disp_echk, ccci_poll, mddp_rx) sit in D state; CPU is 95% idle, so it is cosmetic. Diagnosis script: `tools/tab-charger-spam.sh`.
- **12:25 (11-09) GPU DESKTOP SWITCHED ON.** Matt said "Yes, switch it on". `tools/tab-wayland-session-on.sh` (run via pad-sudo.sh) touches /home/matt/.pad-wayland and restarts getty@tty1; labwc, xfce4-panel and xfdesktop run as matt, Xorg is off, screenshot `shots/session-on.png` shows the full desktop. The flag stays on, so tty1 logins now use labwc while the Android services are up (after a reboot they still need starting by hand, else the session falls back to startx). Undo: `rm ~/.pad-wayland` and restart getty@tty1. Touch still not checked by hand.
  FOUND: the kernel logs ~100k lines/min of charger-driver errors (`get_charger_zcv ... -95`, sc8960x get_input/charging_current, "driver reporting unsupported"), so systemd-journald burns ~50% of a core (11 h CPU in 22 h uptime) and the journal is 3.6 GB. Likely something polling the power_supply sysfs (upower/xfce4-power-manager?). Not fixed yet: cap the journal (SystemMaxUse) and find the poller.
- **01:05 (11-09) MILESTONE: XFCE ON A GPU-COMPOSITED WAYLAND DESKTOP.** labwc 0.20.2 + patched
  wlroots runs as matt on tty1 with xfce4-panel + xfdesktop (wallpaper, icons, dock); screenshots in `shots/`
  (`session-1.png` = matt's session, `scanout-*.png` = what the panel really shows, read from the dma-buf).
  - **Opt-in, OFF by default** (Xorg/XFCE unchanged): `touch ~/.pad-wayland` as matt, then log out or
    `systemctl restart getty@tty1`. `/usr/local/bin/pad-wayland-session` (src `config/labwc/`) falls back to
    Xorg if the allocator service isn't running, and deletes `~/.pad-wayland` if labwc dies within 15 s.
    Logs: `~/.pad-wayland.log`, `~/.pad-wayland-labwc.log`. labwc config: `/etc/xdg/labwc/{rc.xml,autostart}`.
    Install/update: `tools/push-wayland-session.sh` (WSL). Test as matt: `tools/tab-wayland-session-test.sh`
    (enables, screenshots, disables again). Root test harness: `tools/tab-labwc-test.sh` (`/tmp/labwc-cmd`,
    `/tmp/labwc-secs`, `touch /tmp/labwc-gdb` for gdb, PAD_DUMP scanout dump).
  - Fixes found tonight (all in wlroots-pad/ or config):
    1. **Warm-up AHB allocation before eglInitialize** (render/hybris.c). The first allocation (loads the
       gralloc mapper) breaks an already-initialised EGL: GL calls crash or silently do nothing (FBO status 0).
       The earlier "re-make current" idea only hid the crashes - removed. ahb-late FIX=warm proves it.
    2. **Only XBGR/ABGR8888** (AHB R8G8B8A8, format 1) for scan-out + `set_render_format(XBGR8888)`.
       XRGB8888 -> AHB BGRA (5) gave buffers the GPU reads fine but the panel/CPU see as black (likely AFBC).
    3. Pad backend frame pacing: after SETCRTC, page-flip the same fb so vblank events drive frames.
    4. labwc needs DRM + x11 backends compiled in (symbols only; `tools/wlr-symcheck.sh` lists missing ones).
       libwlroots gets RUNPATH /usr/local/hybris/lib via patchelf (meson ignored the link arg).
    5. labwc segfaulted ~50% of starts: touchscreen sends one emulated tap at open -> Root ShowMenu before the
       output is ready -> NULL deref in labwc. rc.xml unbinds Root Left/Right/Middle press (panel has the menu).
       `tools/src/segv-trace.c` (preload, prints lib+offset backtrace) found it; core dumps don't work here.
    6. Binder nodes must be 0666 for the user session (tab-android-mount.sh now chmods them).
    7. Root tests need `dbus-run-session` for XFCE apps (matt's login has a bus already).
  - Touch: rc.xml calibrationMatrix `0 1 0 -1 0 1` + mapToOutput DSI-1 (same as Xorg) - NOT yet verified by
    hand (needs Matt to tap things). Output transform 90 (PAD_TRANSFORM) matched Xorg in screenshots.
  - Known gaps / next: (a) Android services still started by hand -> after a reboot the session falls back to
    Xorg until tab-android-mount + tab-gpu-restart run; make them systemd units. (b) Apps still draw with the
    CPU (wl_shm); only composition is on the GPU. GPU apps need libhybris wayland-egl clients
    (EGL_WL_bind_wayland_display is advertised) + wlroots support for android_wlegl buffers. (c) Xwayland
    untested (mousepad isn't installed). (d) Swapchain reuses ONE buffer (renders into the scanned-out buffer;
    possible tearing) - consider 2 buffers. (e) "Failed to get renderer DRM FD" (linux-dmabuf off) is expected.
    (f) Debug logging (pad: commit per frame) is verbose at -d only; fine. (g) xfce4-session/xfwm4 are not used
    (labwc is the WM); Matt's XFCE panel config carried over.
- test_glesv2 / hwcomposer platform want `libhwc2_compat_layer.so` (Halium, built from AOSP source) - not
  available; use `EGL_PLATFORM=null` for offscreen tests first, then decide on display path (wayland platform +
  a compositor using DRM/dumb buffers, or build hwc2 compat layer). Composer
services available: `android.hardware.graphics.composer@2.1/2.3/2.4/3.1-service`. These are all started by hand
and gone after a reboot. libhybris build: `scripts/62-build-libhybris.sh` (detached; log `/build/out/libhybris-build.log`).

## Why the display needed a shim

mediatek-drm (stock vendor module) oopses at address `0x16d4` on requests that Android's
display service never makes. `noplanes.so`, loaded into Xorg only, hides them:

- plane enumeration → reports zero planes;
- legacy cursor ioctls → no-ops (`SWcursor` in xorg.conf);
- legacy gamma writes → no-ops;
- `SETCRTC` with no framebuffer (disabling unused CRTCs) → skipped;
- connector/object property writes (DPMS on the DSI connector was the last crash) → skipped.

xorg.conf also ignores `DP-1` (USB-C output reports connected with nothing attached).
`PADSHIM_LOG=1` logs every DRM ioctl before it is sent; that is how each crash was found.

## Next steps

1. Finish Wi-Fi (see "Wi-Fi status" above). Then rotate XFCE to landscape (xrandr with ShadowFB rotation + libinput touch matrix), if Matt wants it.
2. Wi-Fi: the driver needs Android helpers (`wmt_loader`, `wmt_launcher`, `conninfra_loader`,
   `wlan_assistant`), which are bionic binaries. Not solved.
3. Audio: speakers, mic and headphone jack switching done (jack not yet tested by ear).
4. Boot logo: Arch logo.bin built (`config/logo/`); flash with Matt present after a backup.
5. Back burner (Matt, 2026-11-08): GPU acceleration via libhybris (Android Mali blob). Panfrost was the other option.
6. Optional: change the USB gadget VID/PID (Windows binds `18d1:4e23` to its ADB driver),
   rebuild on the exact .020 GKI source `2d8ad9139b89` (5.15.197; current 5.15.185 passes the
   module check), make `pad-boot-ok.service` part of a fresh image build.

## Build pipeline (WSL `archlinux`, outputs under `/build`)

`00-host-setup` → `10-unpack-stock` → `20/21` fetch kernel and Clang → `22/23` kernel
(+ `24-check-kmi.py`) → `30` rootfs packages → `55` tablet tools (shim) → `31` rootfs config →
`40` images. `scripts/run-all.sh` runs 55, 31, 23 and 40; start it detached with
`Start-Process wsl.exe -ArgumentList '-d','archlinux','-u','root','--','bash','/mnt/c/mpad26/MotoPadArch/scripts/run-all.sh'`
(WSL shuts down when its controlling session ends). `%USERPROFILE%\.wslconfig` gives WSL 12 GB
memory and 12 GB swap.

## Kernel notes

- `kernel/stock.config` (extracted) + `kernel/arch-fragment.config` (changes).
- Added: `DEVTMPFS`, `FHANDLE`, `AUTOFS_FS`, `TMPFS_POSIX_ACL`, `VT`; built-in initramfs with
  `rdinit=/archinit`. ThinLTO instead of full LTO. `TRIM_UNUSED_KSYMS` and
  `MODULE_SIG_PROTECT` off.
- Keep `LOCALVERSION_AUTO` and `DEBUG_INFO` on: turning either off changes `struct module`
  or CRCs and breaks every stock module.
- `modules.load` is not in dependency order; `archinit` and `pad-load-modules` resolve
  `modules.dep` and pre-softdeps.
- pstore/ramoops does not record this kernel's crashes (only a stale Android log is there);
  MediaTek's AEE owns that path. The systemd journal and the shim's log were the useful sources.

## Safety limits

- Never write `lk_a`, `lk_b`, or preloader. Never relock. Do not use slot B.
- Do not run `fastboot oem device-info` or `fastboot getvar version-baseband`.
- This LK has no `fastboot boot`, ignores the preloader `FASTBOOT` request, and wedges USB after
  an unknown command. Use BROM for partition writes.

## Tools installed on this PC

- WSL2 2.7.14 + `archlinux` distro; usbipd-win 5.3.
- mtkclient commit `118a000a` in `C:\mpad26\tools-ext\mtkclient` (Windows venv `mtkvenv`) and
  `/build/mtkclient` in WSL. UsbDk was installed and then removed (it conflicts with usbipd).

## Files elsewhere

- Factory package (.020):
  `C:\ProgramData\RSA\Download\RomFiles\XT2575_4_ROW_OPEN_USER_M1317.3_W_ZUI_17.5.10.020_ST`
  (scatter files are encrypted; `DA_BR.bin` and `da.auth` are what BROM writes use).
- Stock .020 images: `C:\Edge 26\motopad-2026\recovery-diagnostics\stock-020-chain`.
- Unlock notes: `C:\mpad26\motopad2026unlock\github`. Background: [docs/FINDINGS.md](docs/FINDINGS.md).
