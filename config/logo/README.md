# Boot logo

The first picture the tablet shows at power-on ("hello moto") comes from the `logo_a`
partition. This folder has an Arch Linux replacement and the tools to make your own.

- `arch-logo.png`: the Arch mark and an "Arch Linux" wordmark, centered on black, 2560x1600
  (the screen in landscape). Made by `draw-arch-logo.py`.
- `arch-logo-glow.png`: the same mark with a lowercase "archlinux" wordmark on a dark navy background, with a soft
  blue glow and thin light streaks in two corners, 2560x1600. Made by `draw-arch-logo.py --style glow` (wordmark in
  Segoe UI or DejaVu Sans regular). Matt's pick for the boot logo.
- `draw-arch-logo.py`: draws `arch-logo.png` with Pillow (the mark is an SVG path the script
  flattens itself; the wordmark uses DejaVu Sans Bold, Segoe UI Bold or Arial Bold, or `--font`).
- `../../tools/make-logo.py`: turns any picture into a flashable logo image.

Nothing here has been flashed or tested on the tablet yet (see "Risks" below).

## The format (how it was checked)

`logo_a` is the classic MediaTek `logo.bin`:

| Offset | Contents |
| --- | --- |
| 0x000 | 512-byte MTK header: magic `0x58881688`, payload size, name `logo`, extended magic `0x58891689` at 0x30, header size 0x200, alignment 16 |
| 0x200 | payload: frame count (123), payload size, 123 frame offsets, then the zlib-compressed frames back to back |
| after | `cert1` signature block (factory signing). `make-logo.py` writes none. |

- Frame 0 is the boot logo. It and 36 other frames are full-screen 1600x2560 (16,384,000 bytes
  each = 1600 x 2560 x 4). The others are charging and status screens, battery digits and icons.
- Pixels are BGRA8888 (bytes B, G, R, A; alpha always 0xFF). Checked on the red "Error! Please
  plug out charger!" frame, whose red pixels are `24 1c ed ff`, and on frame 0's blue sky.
- The panel buffer is portrait. Frame 0's picture is a landscape image turned 90 degrees
  clockwise: it shows "hello moto" upright only after turning it back 90 degrees
  counter-clockwise. `make-logo.py` does the same turn (`--rotate cw`, the default).
- Sources: the factory .020 package (`image/logo.img`, signed, and
  `image/mtk_unsigned_images/logo.img`) and the tablet's own `logo_a` and `logo_b`, read with `dd`
  over SSH. The payloads of all of them are byte-identical; only the signature bytes differ.
  Re-packing the tablet's `logo_a` with `make-logo.py` reproduces the factory unsigned image byte
  for byte, which checks the packer.
- Partitions: `logo_a` is 24,641,536 bytes, `logo_b` 16 MiB. Only slot A is used.
- LK checks the entry count ("Logo entries not correct") and frame size ("Logo resolution not
  correct"), so the tool keeps all 123 frames and frame 0 at exactly 1600x2560.

## Make your own logo

Needs Python 3 and Pillow (`pip install pillow` on Windows, or `pacman -S python-pillow` in Arch).
You also need a stock logo image to build on, because the charging frames are copied from it.
Use your backup of `logo_a` (below); the factory `image/logo.img` works too.

```
python tools/make-logo.py build my-picture.png --stock logo_a.stock.bin -o out/logo/my-logo.bin --preview out/logo/my-logo-preview.png
```

- Draw the picture as you want to see it with the tablet in landscape. 2560x1600 fills the
  screen exactly. Other sizes are scaled to fit with black bars (`--bg '#RRGGBB'` for another
  color, `--fill` to cover the screen and crop instead). Transparency is composited onto the
  background.
- `build` checks its output at the end (`CHECK OK`): every frame decodes, frame 0 is
  1600x2560 and opaque, and the other 122 frames are byte-identical to the stock image.
- `--preview` saves frame 0 as it will look, which is the quickest way to check the result.
- Other commands: `info IMAGE` (the frame table), `extract IMAGE DIR [--all]` (frames to PNG),
  `check IMAGE --stock STOCK`.

The Arch image in this repo was built with:

```
python config/logo/draw-arch-logo.py
python tools/make-logo.py build config/logo/arch-logo.png --stock logo_a.stock.bin -o out/logo/arch-logo.bin
```

`out/` is git-ignored. Do not commit stock logo images either: they hold Motorola's artwork.

## Back up the stock logo first

Either way works. The first needs only a running Arch and SSH:

```
# On the tablet (Arch running), then copy it to the PC or keep it on the tablet
sudo dd if=/dev/disk/by-partlabel/logo_a of=/home/matt/logo_a.stock.bin bs=1M
sha256sum /home/matt/logo_a.stock.bin
```

Or through BROM with the factory DA, the same way as `scripts/53-wsl-write-boot-a.sh` (tablet
fully off, unplugged; hold Vol Up + Vol Down and plug in):

```
# In WSL
cd /build/mtkclient
/build/mtkvenv/bin/python mtk.py r logo_a /build/out/logo_a.stock.bin \
  --loader /build/fw/DA_BR.bin --auth /build/fw/da.auth --stock --noreconnect
```

Keep the backup off the repo (it is a 24.6 MB full-partition copy).

## Flash it

Slot A only. Never touch `lk_a`, `lk_b` or the preloader.

```
# In WSL, tablet in BROM mode as above
cd /build/mtkclient
IMG=/mnt/c/mpad26/MotoPadArch/out/logo/arch-logo.bin
/build/mtkvenv/bin/python mtk.py w logo_a "$IMG" \
  --loader /build/fw/DA_BR.bin --auth /build/fw/da.auth --stock --noreconnect
# Read back and compare the written length
/build/mtkvenv/bin/python mtk.py r logo_a /build/out/logo_a.readback \
  --loader /build/fw/DA_BR.bin --auth /build/fw/da.auth --stock --noreconnect
cmp -n "$(stat -c %s "$IMG")" "$IMG" /build/out/logo_a.readback && echo VERIFIED
```

mtkclient writes only the file's length, so the rest of the partition keeps old stock bytes.
That is harmless (the header gives the payload size). To replace the whole partition, build
with `--pad-to 24641536` and compare the full readback instead.

An alternative with no BROM step: from running Arch,
`sudo dd if=arch-logo.bin of=/dev/disk/by-partlabel/logo_a conv=fsync`. It is the same write,
just from Linux.

To undo: write the backup back the same way (`mtk.py w logo_a /build/out/logo_a.stock.bin ...`).

## Risks

- The new image is unsigned (the factory one carries a `cert1` signature that only the vendor
  can make). LK has an image-authentication path (`img_auth_required`). On an unlocked
  MediaTek bootloader it normally skips logo verification, and custom boot logos are common on
  unlocked MediaTek phones, but this has not been tested on this tablet.
- If LK rejects the image, the likely result is no boot logo; at worst LK stops at the logo.
  BROM is in the SoC's ROM and does not depend on LK or the logo, so restoring the backup
  through BROM recovers either way.

## Trademark

The Arch Linux name and logo are trademarks of Judd Vinet and Levente Polyak. They are used
here as allowed by the Arch Linux trademark policy for community projects. This project is
not affiliated with or endorsed by Arch Linux.
