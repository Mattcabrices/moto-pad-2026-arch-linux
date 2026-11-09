"""Bluetooth bridge for the Moto Pad: exposes MediaTek's /dev/stpbt to BlueZ as hci0.

MediaTek's bt_drv_connac1x driver speaks raw H4 HCI on /dev/stpbt (the Android HAL reads and
writes it directly). hci_vhci creates a virtual HCI controller from /dev/vhci. This copies
packets both ways. Requires bt_drv_connac1x and hci_vhci loaded and Wi-Fi/WMT up (pad-wifi).
"""
import os
import select
import sys
import time


def log(m):
    print(f"pad-bt-bridge: {m}", flush=True)


for _ in range(30):
    if os.path.exists("/dev/stpbt") and os.path.exists("/dev/vhci"):
        break
    time.sleep(1)
else:
    log("missing /dev/stpbt or /dev/vhci"); sys.exit(1)

bt = os.open("/dev/stpbt", os.O_RDWR | os.O_NOCTTY)
vh = os.open("/dev/vhci", os.O_RDWR)
os.write(vh, bytes([0xFF, 0x00]))  # HCI_VENDOR_PKT: create a primary controller
r = os.read(vh, 16)
log(f"vhci created controller, reply {r.hex()}")

stats = {"to_bt": 0, "to_host": 0}
last = time.time()
while True:
    rd, _, _ = select.select([bt, vh], [], [], 30)
    for fd in rd:
        try:
            data = os.read(fd, 4096)
        except OSError as e:
            log(f"read error on {'stpbt' if fd == bt else 'vhci'}: {e}"); sys.exit(1)
        if not data:
            continue
        if fd == vh:
            # The controller claims Read Synchronization Train Parameters (opcode 0x0c77) but
            # answers "Unknown HCI Command", which aborts Linux's controller setup. Answer it
            # here: Command Complete, status 0, interval 0x0080, timeout 0x0002_0000, data 0.
            if data[:3] == b"\x01\x77\x0c":
                os.write(vh, bytes.fromhex("040e0b01770c00800000000200" "00"))
                log("answered Read Sync Train Params locally")
                continue
            os.write(bt, data); stats["to_bt"] += 1
            if stats["to_bt"] <= 8: log(f"host->bt {data[:24].hex()}")
        else:
            os.write(vh, data); stats["to_host"] += 1
            if stats["to_host"] <= 8: log(f"bt->host {data[:24].hex()}")
    if time.time() - last > 60:
        log(f"packets host->bt {stats['to_bt']}, bt->host {stats['to_host']}"); last = time.time()
