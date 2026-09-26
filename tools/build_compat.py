"""Builds firmware/compat.rcc: the firmware QML files listed in sim/compat/patches.json, with the
listed replacements applied. toonsim registers compat.rcc before the firmware's .rcc files, so each
patched file replaces the original at the same qrc: address (its relative imports keep working).

    python build_compat.py          (run again after pulling a new firmware or editing patches.json)
"""
import json, os, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rcc import Rcc

HOME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIRMWARE = os.path.join(HOME, "firmware")


def find_rcc():
    """Qt's resource compiler: next to toonsim (the Windows package has bin/rcc.exe), the Qt it was built
    with, or the system's (Linux: qtbase5-dev-tools' /usr/lib/qt5/bin/rcc)"""
    for c in (os.path.join(HOME, "bin", "rcc.exe"), os.path.join(HOME, "bin", "rcc"),
              os.path.join(os.path.expanduser("~"), "Qt", "5.15.2", "mingw81_64", "bin", "rcc.exe"), "/usr/lib/qt5/bin/rcc",
              "/usr/lib/x86_64-linux-gnu/qt5/bin/rcc"):
        if os.path.isfile(c): return c
    return shutil.which("rcc") or shutil.which("rcc-qt5")

def main():
    spec = json.load(open(os.path.join(HOME, "sim", "compat", "patches.json"), encoding="utf-8"))
    sources = {}
    for name in ("resources-static-base.rcc", "drawables-base.rcc"):
        p = os.path.join(FIRMWARE, name)
        if os.path.exists(p):
            sources.update(Rcc(p).files())

    work = tempfile.mkdtemp(prefix="toonsim_compat_")
    patched = {}
    ok = skipped = 0
    for patch in spec["patches"]:
        f = patch["file"]
        if f not in patched:
            if f not in sources:
                print("skip  %s: not in this firmware" % f); skipped += 1; continue
            patched[f] = sources[f]().decode("utf-8")
        if patch["find"] not in patched[f]:
            print("skip  %s: text not found (firmware changed?): %r" % (f, patch["find"][:60])); skipped += 1; continue
        patched[f] = patched[f].replace(patch["find"], patch["replace"])
        print("patch %s  (%s)" % (f, patch.get("why", "")))
        ok += 1

    out = os.path.join(FIRMWARE, "compat.rcc")
    if not patched:
        if os.path.exists(out): os.remove(out)
        print("no patches apply; removed compat.rcc")
        return
    qrc = ['<RCC><qresource prefix="/">']
    for f, text in patched.items():
        dest = os.path.join(work, *f.split("/"))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w", encoding="utf-8", newline="") as fh: fh.write(text)
        qrc.append('<file>%s</file>' % f)
    qrc.append("</qresource></RCC>")
    qrc_path = os.path.join(work, "compat.qrc")
    open(qrc_path, "w", encoding="utf-8").write("\n".join(qrc))
    rcc = find_rcc()
    if not rcc:
        sys.exit("Qt's rcc not found (Linux: sudo apt install qtbase5-dev-tools)")
    subprocess.check_call([rcc, "-binary", qrc_path, "-o", out], cwd=work)
    print("built %s: %d patches in %d files, %d skipped" % (out, ok, len(patched), skipped))

if __name__ == "__main__":
    main()
