"""Runs the simulator tests: every test_*(t) function in tests/test_*.py.

    python tools/run_tests.py                 all tests, Toon 2 size
    python tools/run_tests.py --size toon1    the same on the Toon 1 screen
    python tools/run_tests.py graph           only files/functions whose name contains "graph"
    python tools/run_tests.py --show          with the window visible (to watch the taps)

Each test file gets a fresh simulator, booted and on the home screen. A test gets the Toon client
(tools/toonsim.py) and fails by raising (assert, ToonError). On a failure the screen is saved as
tests/out/<file>.<test>.png, next to the log lines of that test.

The tests run in their own data folder, data-test/, emptied for every test file: they start from the
simulator's defaults, may change settings freely, and do not touch data/ - so a simulator you are
using keeps running undisturbed (on port 5555; the tests use 5556). t.data is that folder.
"""
import argparse, importlib.util, os, shutil, sys, time, traceback

TOOLS = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
from toonsim import Toon  # noqa: E402

TESTS = os.path.join(HOME, "tests")
OUT = os.path.join(TESTS, "out")
DATA = os.path.join(HOME, "data-test")


def load(path):
    spec = importlib.util.spec_from_file_location(os.path.splitext(os.path.basename(path))[0], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("filter", nargs="?", default="")
    ap.add_argument("--size", default="toon2", choices=["toon2", "toon1"])
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--port", type=int, default=5556)       # not 5555: a simulator you are using keeps running
    a = ap.parse_args()

    files = sorted(f for f in os.listdir(TESTS) if f.startswith("test_") and f.endswith(".py"))
    os.makedirs(OUT, exist_ok=True)
    os.environ["TOONSIM_NO_TOONSTORE_INSTALL"] = "1"        # tsc: no ToonStore install (and GUI restart) mid-test
    passed, failed = 0, []
    for f in files:
        mod = load(os.path.join(TESTS, f))
        names = [n for n in dir(mod) if n.startswith("test_") and callable(getattr(mod, n))]
        names = [n for n in names if a.filter in f or a.filter in n]
        if not names: continue
        names.sort(key=lambda n: getattr(mod, n).__code__.co_firstlineno)   # in file order
        print("%s (%s)" % (f, a.size))
        shutil.rmtree(DATA, ignore_errors=True)
        t = Toon.start(size=a.size, hidden=not a.show, port=a.port, data=DATA, extra=["--web-port", "0"])
        try:
            t.wait_until_booted()
            time.sleep(1)
            for n in names:
                mark = t.log_mark()
                start = time.time()
                try:
                    getattr(mod, n)(t)
                    passed += 1
                    print("  ok    %-40s %.1f s" % (n, time.time() - start))
                except Exception as e:
                    base = os.path.join(OUT, "%s.%s" % (f[:-3], n))
                    try:
                        t.shot(base + ".png")
                        with open(base + ".log", "w", encoding="utf-8") as fh: fh.write("\n".join(t.log_since(mark)))
                    except Exception: pass
                    failed.append("%s::%s" % (f, n))
                    print("  FAIL  %-40s %s" % (n, e))
                    traceback.print_exc(limit=3)
                # back to the home screen for the next test
                try: t.eval("stage.navigateHome(), true")
                except Exception: pass
                time.sleep(0.5)
        finally:
            t.close()
    print("\n%d passed, %d failed" % (passed, len(failed)))
    for n in failed: print("  " + n)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
