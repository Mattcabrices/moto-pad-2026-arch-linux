#!/usr/bin/env python3
"""Tiny Chrome DevTools Protocol client (stdlib only), for tests on the tablet.

Chromium must run with --remote-debugging-port=PORT.
  cdp.py gpu                 GPU feature status and hardware video decode profiles (SystemInfo.getInfo)
  cdp.py media SECONDS       which video decoder each media player uses (Media domain events) for SECONDS
"""
import base64, json, os, socket, struct, sys, time, urllib.request

PORT = int(os.environ.get("CDP_PORT", "9222"))


class WS:
    def __init__(self, url):
        host, path = url.split("://", 1)[1].split("/", 1)
        h, p = host.split(":")
        self.s = socket.create_connection((h, int(p)), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall((f"GET /{path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(4096)
        self.rest = buf.split(b"\r\n\r\n", 1)[1]
        self.n = 0

    def _read(self, n):
        while len(self.rest) < n:
            d = self.s.recv(65536)
            if not d:
                raise EOFError
            self.rest += d
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def send(self, method, params=None, session=None):
        self.n += 1
        msg = {"id": self.n, "method": method, "params": params or {}}
        if session:
            msg["sessionId"] = session
        data = json.dumps(msg).encode()
        mask = os.urandom(4)
        hdr = bytes([0x81])
        ln = len(data)
        hdr += bytes([0x80 | ln]) if ln < 126 else (bytes([0x80 | 126]) + struct.pack(">H", ln) if ln < 65536
                                                     else bytes([0x80 | 127]) + struct.pack(">Q", ln))
        self.s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
        return self.n

    def recv(self):
        payload = b""
        while True:
            b1, b2 = self._read(2)
            ln = b2 & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._read(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._read(8))[0]
            payload += self._read(ln)
            if b1 & 0x80:
                return json.loads(payload)

    def call(self, method, params=None, session=None):
        i = self.send(method, params, session)
        while True:
            m = self.recv()
            if m.get("id") == i:
                return m


def browser():
    v = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/version"))
    return WS(v["webSocketDebuggerUrl"])


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "gpu"
    ws = browser()
    if what == "gpu":
        r = ws.call("SystemInfo.getInfo")["result"]["gpu"]
        print("featureStatus:", json.dumps(r.get("featureStatus", {}), sort_keys=True))
        for d in r.get("videoDecoding", []):
            print("decode:", d["profile"], d["maxResolution"])
        print("driverBugWorkarounds:", r.get("driverBugWorkarounds", []))
        return
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 15
    ws.call("Target.setDiscoverTargets", {"discover": True})
    targets = ws.call("Target.getTargets")["result"]["targetInfos"]
    sessions = []
    for t in targets:
        if t["type"] == "page":
            sid = ws.call("Target.attachToTarget", {"targetId": t["targetId"], "flatten": True})["result"]["sessionId"]
            ws.call("Media.enable", None, sid)
            ws.send("Page.reload", None, sid)   # so the player is created while we listen
            sessions.append(sid)
    end = time.time() + secs
    ws.s.settimeout(1)
    while time.time() < end:
        try:
            m = ws.recv()
        except (socket.timeout, TimeoutError):
            continue
        meth = m.get("method", "")
        if meth == "Media.playerPropertiesChanged":
            for p in m["params"]["properties"]:
                if "ecoder" in p["name"] or p["name"] in ("kResolution", "kFrameRate", "kVideoTracks"):
                    print("media:", p["name"], p["value"], flush=True)
        elif meth == "Media.playerMessagesLogged":
            for p in m["params"]["messages"]:
                print("media-log:", p["level"], p["message"][:300], flush=True)
        elif meth == "Media.playerErrorsRaised":
            print("media-error:", json.dumps(m["params"])[:400], flush=True)


if __name__ == "__main__":
    main()
