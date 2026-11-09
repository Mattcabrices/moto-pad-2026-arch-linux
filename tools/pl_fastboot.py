"""Asks the MediaTek preloader to boot into fastboot, over USB through UsbDk.

Writes nothing to the tablet's storage. At power-on the preloader (USB 0e8d:2000) sends
"READY"; answering "FASTBOOT" makes it boot into fastboot once, and it replies "TOOBTSAF".
Run: python -I pl_fastboot.py   then power the tablet on with the cable connected.
"""
import ctypes
import sys
import time

import usb.backend.libusb1
import usb.core

DLL = r"C:\mpad26\tools-ext\mtkclient\mtkclient\Windows\libusb-1.0.dll"
backend = usb.backend.libusb1.get_backend(find_library=lambda _: DLL)
backend.lib.libusb_set_option.argtypes = [ctypes.c_void_p, ctypes.c_int]
backend.lib.libusb_set_option(backend.ctx, 1)  # LIBUSB_OPTION_USE_USBDK


def log(msg):
    print(f"{time.strftime('%H:%M:%S')}.{int(time.time() * 1000) % 1000:03d} {msg}", flush=True)


def attempt(dev):
    try:
        dev.set_configuration()
    except usb.core.USBError as e:
        log(f"set_configuration: {e} (continuing)")
    for intf in (0, 1):
        try:
            usb.util.claim_interface(dev, intf)
        except usb.core.USBError as e:
            log(f"claim {intf}: {e}")
    try:  # CDC SET_CONTROL_LINE_STATE: DTR and RTS on
        dev.ctrl_transfer(0x21, 0x22, 0x03, 0, None, timeout=200)
    except usb.core.USBError as e:
        log(f"line state: {e}")
    sent = False
    end = time.time() + 6
    while time.time() < end:
        try:
            data = bytes(dev.read(0x81, 512, timeout=100))
        except usb.core.USBTimeoutError:
            data = b""
        except usb.core.USBError as e:
            log(f"read: {e}")
            return False
        if data:
            log(f"rx {data!r}")
            if b"TOOBTSAF" in data:
                log("preloader accepted FASTBOOT")
                return True
            if data.startswith(b"READY") or not sent:
                dev.write(0x01, b"FASTBOOT", timeout=200)
                sent = True
                log("tx b'FASTBOOT'")
        elif not sent:
            # Some preloaders only answer after the host speaks first.
            try:
                dev.write(0x01, b"FASTBOOT", timeout=100)
            except usb.core.USBError:
                pass
    return False


def main():
    log("waiting for preloader 0e8d:2000 (power the tablet on now)")
    deadline = time.time() + 600
    while time.time() < deadline:
        try:
            dev = usb.core.find(idVendor=0x0E8D, idProduct=0x2000, backend=backend)
        except usb.core.USBError:
            # Enumeration can fail for a moment while a device is attaching or detaching.
            time.sleep(0.02)
            continue
        if dev is not None:
            log("preloader found")
            try:
                if attempt(dev):
                    return 0
            except Exception as e:  # keep trying on the next power-on
                log(f"attempt error: {type(e).__name__}: {e}")
            usb.util.dispose_resources(dev)
            time.sleep(0.5)
        time.sleep(0.02)
    log("gave up after 10 minutes")
    return 1


if __name__ == "__main__":
    sys.exit(main())
