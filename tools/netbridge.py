"""https for the simulator's GUI. The Qt build toonsim uses has no OpenSSL (Qt 5.15 wants OpenSSL 1.1,
which is no longer distributed), so toonsim sends every https request of the GUI and its apps here
instead, as http://127.0.0.1:<port>/<host>/<path>?<query>; this script makes the real https request
with Python's own TLS and passes the answer back (status, headers, body). Redirects are followed.

toonsim starts it (--port) and starts it again when it stops.
"""
import argparse, http.server, os, socketserver, ssl, sys, threading, time, urllib.error, urllib.request

HOP = {"connection", "keep-alive", "proxy-connection", "transfer-encoding", "te", "trailer", "upgrade",
       "host", "content-length", "accept-encoding"}
CTX = ssl.create_default_context()


class Bridge(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def forward(self):
        path = self.path.lstrip("/")
        if "/" not in path: path += "/"
        host, rest = path.split("/", 1)
        url = "https://%s/%s" % (host, rest)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        req = urllib.request.Request(url, data=body, headers=headers, method=self.command)
        try:
            with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
                status, rheaders, data = r.status, r.headers, r.read()
        except urllib.error.HTTPError as e:
            status, rheaders, data = e.code, e.headers, e.read()
        except Exception as e:
            print("netbridge: %s %s failed: %s" % (self.command, url, e), flush=True)
            data = str(e).encode()
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(status)
        for k, v in rheaders.items():
            if k.lower() not in HOP and k.lower() != "content-encoding":
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD": self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_PATCH = do_OPTIONS = forward


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def watch_parent(pid):
    """stop when toonsim is gone (also when it was killed and could not stop us)"""
    if os.name == "nt":
        import ctypes
        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x100000, False, pid)            # SYNCHRONIZE
        if not h: os._exit(0)
        k.WaitForSingleObject(h, 0xFFFFFFFF)
        os._exit(0)
    import time
    while os.getppid() == pid:                              # Linux: the parent changes when it is gone
        time.sleep(1)
    os._exit(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--parent", type=int, default=0)
    a = ap.parse_args()
    if a.parent: threading.Thread(target=watch_parent, args=(a.parent,), daemon=True).start()
    srv = Server(("127.0.0.1", a.port), Bridge)
    print("netbridge: https for the GUI via 127.0.0.1:%d" % a.port, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
