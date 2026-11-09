"""Runs inside WSL. Asks the MediaTek preloader to boot into fastboot through /dev/ttyACM*.

usbipd hands the preloader (0e8d:2000) to Linux, where cdc_acm makes it /dev/ttyACM0 within
milliseconds. The preloader sends "READY"; answering "FASTBOOT" makes it boot into fastboot
once, and it replies "TOOBTSAF". Writes nothing to the tablet's storage.
"""
import glob
import os
import sys
import termios
import time


def log(msg):
    t = time.time()
    print(f"{time.strftime('%H:%M:%S', time.localtime(t))}.{int(t * 1000) % 1000:03d} {msg}", flush=True)


def raw(fd):
    a = termios.tcgetattr(fd)
    a[0] = a[1] = a[3] = 0          # no input, output, or local processing
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    a[6][termios.VMIN] = 0
    a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)


def attempt(path):
    try:
        fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError as e:
        log(f"open {path}: {e}")
        return False
    log(f"opened {path}")
    try:
        raw(fd)
        buf, sent, end = b"", False, time.time() + 5
        while time.time() < end:
            try:
                d = os.read(fd, 512)
            except BlockingIOError:
                d = b""
            except OSError as e:
                log(f"read: {e}")
                return False
            if d:
                buf += d
                log(f"rx {d!r}")
            if b"TOOBTSAF" in buf:
                log("preloader accepted FASTBOOT")
                return True
            if (b"READY" in buf or not sent) and not b"TOOBTSAF" in buf:
                try:
                    os.write(fd, b"FASTBOOT")
                    if not sent:
                        log("tx b'FASTBOOT'")
                    sent = True
                    buf = buf.replace(b"READY", b"")
                except OSError as e:
                    log(f"write: {e}")
                    return False
            time.sleep(0.005)
    finally:
        os.close(fd)
    return False


def main():
    log("waiting for /dev/ttyACM* from the preloader")
    deadline = time.time() + 1200
    while time.time() < deadline:
        ports = sorted(glob.glob("/dev/ttyACM*"))
        if ports:
            if attempt(ports[0]):
                return 0
            while glob.glob("/dev/ttyACM*") and time.time() < deadline:
                time.sleep(0.05)
        time.sleep(0.003)
    log("gave up")
    return 1


if __name__ == "__main__":
    sys.exit(main())
