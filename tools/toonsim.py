"""Python client for the toonsim remote control, for development and automated tests.

    from toonsim import Toon
    with Toon.start(size="toon2", hidden=True) as t:      # or Toon.connect() to a running simulator
        t.wait_for_text("Instellingen")
        t.tap_text("Instellingen")
        t.shot("settings.png")
        print(t.eval("stage.currentScreen"))

As a command:  python toonsim.py shot out.png | items [TEXT] | tap X Y | taptext TEXT | eval JS | log
"""
import json, os, socket, subprocess, sys, time

HOME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QT = os.path.join(os.path.expanduser("~"), "Qt", "5.15.2", "mingw81_64")


class ToonError(Exception):
    pass


class Toon:
    def __init__(self, port=5555, proc=None):
        self.port = port
        self.proc = proc
        self.data = os.path.join(HOME, "data")
        self.sock = None
        self.buf = b""

    # ---- starting / connecting ----

    @classmethod
    def start(cls, size="toon2", hidden=False, apps=None, port=5555, timeout=30, extra=(), data=None):
        """data: the simulator's writable folder (--data); give tests their own, as one data folder
        takes one simulator at a time"""
        env = dict(os.environ)
        # the Windows package has Qt next to toonsim.exe; a development build uses the Qt it was built with;
        # on Linux Qt is the system's
        if os.name == "nt" and not os.path.exists(os.path.join(HOME, "bin", "Qt5Core.dll")) and os.path.isdir(QT):
            env["PATH"] = QT + r"\bin;" + os.path.join(os.path.dirname(os.path.dirname(QT)), "Tools", "mingw810_64", "bin") + ";" + env.get("PATH", "")
            env["QT_PLUGIN_PATH"] = QT + r"\plugins"
            env["QML2_IMPORT_PATH"] = QT + r"\qml"
        exe = os.path.join(HOME, "bin", "toonsim.exe" if os.name == "nt" else "toonsim")
        args = [exe, "--size", size, "--control-port", str(port)]
        if hidden: args.append("--hidden")
        if apps: args += ["--apps", apps]
        if data: args += ["--data", data]
        args += list(extra)
        proc = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        t = cls(port, proc)
        t.data = os.path.abspath(data) if data else os.path.join(HOME, "data")
        t._connect(timeout)
        return t

    @classmethod
    def connect(cls, port=5555, timeout=5):
        t = cls(port)
        t._connect(timeout)
        return t

    def _connect(self, timeout):
        end = time.time() + timeout
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", self.port), timeout=5)
                return
            except OSError:
                if time.time() > end or (self.proc and self.proc.poll() is not None):
                    raise ToonError("toonsim not reachable on port %d" % self.port)
                time.sleep(0.3)

    def close(self, quit=None):
        """disconnect. quit=None (default): stop the simulator if start() started it; True: stop it
        also when connect() found it running; False: leave it running"""
        if quit is None: quit = self.proc is not None
        if self.sock:
            if quit:
                try: self.cmd("quit")
                except Exception: pass
            self.sock.close()
            self.sock = None
        if self.proc and quit:
            try: self.proc.wait(5)
            except subprocess.TimeoutExpired: self.proc.kill()

    def __enter__(self): return self
    def __exit__(self, *a): self.close()

    # ---- raw protocol ----

    def cmd(self, line):
        self.sock.sendall((line + "\n").encode("utf-8"))
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk: raise ToonError("connection closed")
            self.buf += chunk
        raw, self.buf = self.buf.split(b"\n", 1)
        r = json.loads(raw.decode("utf-8"))
        if not r.get("ok"): raise ToonError(r.get("error", "failed") + " (" + line[:80] + ")")
        return r.get("result")

    # ---- convenience ----

    def eval(self, js): return self.cmd("eval " + js)
    def tap(self, x, y): self.cmd("tap %d %d" % (x, y))
    def shot(self, path): return self.cmd("shot " + os.path.abspath(path))
    def items(self, text=""): return self.cmd("items " + text) or []
    def log(self): return self.cmd("log") or []
    def size(self): return self.cmd("size")

    def find(self, text, exact=False):
        hits = self.items(text)
        if exact: hits = [h for h in hits if h["text"] == text]
        return hits

    def tap_text(self, text, exact=False, index=0):
        hits = self.find(text, exact)
        if not hits: raise ToonError("no visible item with text %r" % text)
        h = hits[index]
        self.tap(h["cx"], h["cy"])
        return h

    def wait_for(self, fn, timeout=10, interval=0.25, what="condition"):
        end = time.time() + timeout
        while True:
            v = fn()
            if v: return v
            if time.time() > end: raise ToonError("timed out waiting for " + what)
            time.sleep(interval)

    def wait_for_text(self, text, timeout=10, exact=False):
        return self.wait_for(lambda: self.find(text, exact), timeout, what="text %r" % text)

    def wait_restart(self, timeout=60):
        """after something restarted the GUI (TSC's Restart GUI, a ToonStore install): connect to the new one"""
        if self.sock:
            self.sock.close()
            self.sock = None
        self.buf = b""
        time.sleep(2)
        self._connect(timeout)
        return self.wait_until_booted(timeout)

    def wait_until_booted(self, timeout=60):
        """until the splash screen is gone (Canvas.firstLoadingDone); follows a restart during it
        (a fresh simulator installs ToonStore at its first start and restarts)"""
        end = time.time() + timeout
        while True:
            try:
                return self.wait_for(lambda: self.eval("firstLoadingDone") is True, max(1, end - time.time()),
                                     what="the GUI to finish loading")
            except (ToonError, OSError) as e:
                if "connection" not in str(e).lower() and not isinstance(e, OSError) or time.time() > end: raise
                if self.sock: self.sock.close()
                self.sock, self.buf = None, b""
                time.sleep(2)
                self._connect(max(5, end - time.time()))

    # ---- apps and simulated devices ----

    @staticmethod
    def app(path):
        """JS expression for a loaded app, e.g. t.eval(Toon.app("graph/GraphApp.qml") + ".graphScreenUrl")"""
        return 'CanvasJS.loadedApps[%s]' % json.dumps(path)

    def apps(self):
        return self.eval("Object.keys(CanvasJS.loadedApps)")

    def open_screen(self, app_path, url_property, args=None):
        """open an app's screen as its tiles and menu do: stage.openFullscreen(app.<url_property>, args)"""
        self.eval("stage.openFullscreen(%s.%s, %s), true" % (self.app(app_path), url_property, json.dumps(args or {})))

    def device(self, type_):
        """the state of a simulated device (sim/devices/<type>.js), e.g. t.device("happ_thermstat")["currentSetpoint"]"""
        return json.loads(self.eval("simDevices.get(%s)" % json.dumps(type_)))

    def set_device(self, type_, **state):
        """change a simulated device and republish it, e.g. t.set_device("happ_thermstat", currentTemp=1650)"""
        return self.eval("simDevices.set(%s, %s)" % (json.dumps(type_), json.dumps(state)))

    # the control port's "log" returns each line once (what came since the previous "log")
    def log_mark(self):
        """start collecting: log_since(mark) returns the lines that came after this call"""
        self._log_seen = []
        self.log()
        return 0

    def log_since(self, mark=0, level=None):
        self._log_seen = getattr(self, "_log_seen", []) + self.log()
        return [l for l in self._log_seen[mark:] if not level or (" %s " % level) in l]


def main():
    if len(sys.argv) < 2:
        print(__doc__); return
    t = Toon.connect()
    c, rest = sys.argv[1], sys.argv[2:]
    if c == "shot": print(t.shot(rest[0]))
    elif c == "items": print(json.dumps(t.items(" ".join(rest)), indent=1))
    elif c == "tap": t.tap(int(rest[0]), int(rest[1]))
    elif c == "taptext": print(t.tap_text(" ".join(rest)))
    elif c == "eval": print(json.dumps(t.eval(" ".join(rest)), indent=1))
    elif c == "log": print("\n".join(t.log()))
    else: print(t.cmd(" ".join(sys.argv[1:])))
    t.close(quit=False)

if __name__ == "__main__":
    main()
