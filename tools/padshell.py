"""Minimal raw TCP shell for the tablet's early-boot debug console (busybox telnetd).

Windows has no telnet client by default. Usage: python padshell.py 10.55.0.1 23
"""
import socket
import sys
import threading

IAC = 255


def strip_telnet(data):
    out, i = bytearray(), 0
    while i < len(data):
        if data[i] == IAC and i + 2 < len(data):
            i += 3
            continue
        out.append(data[i])
        i += 1
    return bytes(out)


def main():
    host, port = sys.argv[1], int(sys.argv[2])
    s = socket.create_connection((host, port), timeout=10)
    s.settimeout(None)
    print(f"connected to {host}:{port}; type 'exit' to close")

    def reader():
        while True:
            d = s.recv(4096)
            if not d:
                print("\n[connection closed]")
                return
            sys.stdout.write(strip_telnet(d).decode(errors="replace"))
            sys.stdout.flush()

    threading.Thread(target=reader, daemon=True).start()
    for line in sys.stdin:
        s.sendall(line.replace("\r\n", "\n").encode())
        if line.strip() == "exit":
            break


if __name__ == "__main__":
    main()
