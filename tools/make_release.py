"""Builds the release package: dist/toonsim-<VERSION>-win64.zip on Windows, and on Linux (after
tools/build.sh) dist/toonsim-<VERSION>-linux-x64.tar.gz, which uses the system's Qt (see main_linux).

    python tools/make_release.py

Run it on the build machine after tools/build.bat. The package is self-contained - it needs no Qt, Python
or compiler on the user's PC:

    bin/        toonsim.exe, the Qt 5.15.2 (MinGW) DLLs, plugins and QML modules it uses, qt.conf
    python/     the embeddable Python from python.org, for tsc.py, netbridge.py and the tools
    tools/busybox/  busybox-w32 (frippery.org), the shell for the apps' own scripts
    sim/ tools/ tests/ docs/ README.md VERSION toonsim.bat
    apps/       empty: the user's apps go here
    firmware/   empty: tools/pull_firmware.bat copies the Toon's GUI into it (it is Eneco's, not ours
                to hand out)

Left out: firmware/, data*/, apps/* and src/build (the sources in src/ are in).
"""
import fnmatch, glob, os, shutil, subprocess, sys, urllib.request, zipfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.dirname(TOOLS)
QT = os.path.join(os.path.expanduser("~"), "Qt", "5.15.2", "mingw81_64")
OBJDUMP = os.path.join(os.path.expanduser("~"), "Qt", "Tools", "mingw810_64", "bin", "objdump.exe")
PYTHON_EMBED = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"
# the shell for the apps' own scripts (tools/tsc.py): busybox-w32, 64-bit, UTF-8; see tools/busybox/README.txt
BUSYBOX_URL = "https://frippery.org/files/busybox/busybox-w64u-FRP-6075-g169694ebd.exe"
BUSYBOX_SHA256 = "6e263d154d8548d1eb936f65d1d8312c80df31c45974e48d6335e4dcc0f4f34c"

# plugins (under QT/plugins) and QML modules (under QT/qml) that go in: what toonsim loads, plus the Qt
# Quick modules apps commonly import (Controls 1/2, XmlListModel, LocalStorage, Particles, Shapes, ...)
PLUGINS = ["platforms/qwindows.dll", "platforminputcontexts/qtvirtualkeyboardplugin.dll", "virtualkeyboard/*.dll",
           "imageformats/*.dll", "iconengines/*.dll", "bearer/*.dll", "styles/*.dll", "sqldrivers/qsqlite.dll"]
QML_MODULES = ["QtQuick.2", "QtQuick", "QtQml", "QtGraphicalEffects", "Qt/labs", "QtQuick/Controls.2", "QtQuick/Templates.2",
               "QtWebSockets"]                   # apps' own web pages talk to them (thermostatPlus's WebSocketServer)
SKIP_QML = ["QtQuick/Scene3D", "QtQuick/Scene2D", "QtQuick3D"]      # need Qt3D, which apps on a Toon do not have

MINGW_RUNTIME = ["libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll"]


def version():
    with open(os.path.join(HOME, "VERSION")) as f: return f.read().strip()


def imports(dll):
    """the DLL names a PE file imports (objdump -p)"""
    out = subprocess.run([OBJDUMP, "-p", dll], capture_output=True, text=True).stdout
    return [l.split("DLL Name:")[1].strip() for l in out.splitlines() if "DLL Name:" in l]


def copy_tree_filtered(src, dst, skip=lambda p: False):
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        if skip(rel): dirs[:] = []; continue
        dirs[:] = [d for d in dirs if d not in ("__pycache__", "build", "build-linux") and not skip(os.path.join(rel, d))]
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in files:
            if f.endswith((".pyc", ".o")): continue
            shutil.copy2(os.path.join(root, f), os.path.join(dst, rel, f))


# Debian/Ubuntu packages the Linux build runs with (the system's Qt 5.15): toonsim.sh installs them
def linux_packages():
    with open(os.path.join(TOOLS, "linux-packages.txt")) as f:
        return " ".join(l.strip() for l in f if l.strip() and not l.startswith("#"))


def main_linux():
    """dist/toonsim-<VERSION>-linux-x64.tar.gz: bin/toonsim (built with tools/build.sh) and the simulator's
    files; Qt is the system's (tools/linux-packages.txt), Python and sh too"""
    import tarfile
    ver = version()
    name = "toonsim-%s-linux-x64" % ver
    dist = os.path.join(HOME, "dist")
    os.makedirs(dist, exist_ok=True)
    exe = os.path.join(HOME, "bin", "toonsim")
    if not os.path.isfile(exe): sys.exit("no bin/toonsim: run tools/build.sh first")
    tar_path = os.path.join(dist, name + ".tar.gz")
    skip_dirs = {"__pycache__", "build", "build-linux", "out"}
    executable = lambda rel: rel in ("toonsim.sh", "bin/toonsim") or (rel.startswith("tools/") and rel.endswith(".sh")) \
        or rel.startswith("tools/shims/")

    def add(tf, src, rel):
        info = tf.gettarinfo(src, name + "/" + rel)
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mode = 0o755 if (info.isdir() or executable(rel)) else 0o644
        if info.isfile():
            with open(src, "rb") as f: tf.addfile(info, f)
        else:
            tf.addfile(info)

    count = 0
    with tarfile.open(tar_path, "w:gz") as tf:
        add(tf, exe, "bin/toonsim")
        for d in ("sim", "tools", "tests", "docs", "src"):
            for root, dirs, files in os.walk(os.path.join(HOME, d)):
                dirs[:] = sorted(x for x in dirs if x not in skip_dirs)
                for f in sorted(files):
                    if f.endswith((".pyc", ".o", ".exe")) or f in ("Makefile", ".qmake.stash"): continue
                    src = os.path.join(root, f)
                    add(tf, src, os.path.relpath(src, HOME).replace(os.sep, "/"))
                    count += 1
        for f in ("README.md", "VERSION", "toonsim.sh"):
            add(tf, os.path.join(HOME, f), f)
        for rel, text in (("apps/PUT-YOUR-APPS-HERE.txt",
                           "Each app in its own folder, as in /qmf/qml/apps on the Toon: apps/<app>/<App>App.qml - see docs/MANUAL.md.\n"),
                          ("firmware/README.txt",
                           "The Toon's GUI goes here. toonsim.sh copies it from your own rooted Toon at its first start\n"
                           "(or: tools/pull_firmware.sh <ip address of your Toon>). See docs/MANUAL.md.\n")):
            import io
            data = text.encode()
            info = tarfile.TarInfo(name + "/" + rel)
            info.size, info.mode, info.mtime = len(data), 0o644, int(os.path.getmtime(exe))
            tf.addfile(info, io.BytesIO(data))
    print("built %s (%d files, %.1f MB)" % (tar_path, count, os.path.getsize(tar_path) / 1e6))
    print("it needs (toonsim.sh installs them): " + linux_packages())


def main():
    if os.name != "nt":
        return main_linux()
    ver = version()
    name = "toonsim-%s-win64" % ver
    dist = os.path.join(HOME, "dist")
    out = os.path.join(dist, name)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    b = os.path.join(out, "bin")
    os.makedirs(b)

    # bin: the exe, plugins, QML modules, then every Qt / MinGW DLL any of them needs
    shutil.copy2(os.path.join(HOME, "bin", "toonsim.exe"), b)
    # Qt's resource compiler: pull_firmware builds the compatibility patches with it (build_compat.py)
    shutil.copy2(os.path.join(QT, "bin", "rcc.exe"), b)
    pe_files = [os.path.join(b, "toonsim.exe"), os.path.join(b, "rcc.exe")]
    for pat in PLUGINS:
        for src in glob.glob(os.path.join(QT, "plugins", pat)):
            if src.endswith("d.dll") and os.path.exists(src[:-5] + ".dll"): continue     # a debug twin
            dst = os.path.join(b, "plugins", os.path.relpath(src, os.path.join(QT, "plugins")))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            pe_files.append(dst)
    qml_src = os.path.join(QT, "qml")
    for mod in QML_MODULES:
        src = os.path.join(qml_src, mod)
        if not os.path.isdir(src): continue
        dst = os.path.join(b, "qml", mod)
        copy_tree_filtered(src, dst, lambda rel, mod=mod: any(fnmatch.fnmatch(os.path.normpath(os.path.join(mod, rel)), os.path.normpath(s) + "*") for s in SKIP_QML))
    for root, _, files in os.walk(os.path.join(b, "qml")):
        pe_files += [os.path.join(root, f) for f in files if f.endswith(".dll")]
    needed, todo = set(MINGW_RUNTIME), list(pe_files)
    while todo:
        for dll in imports(todo.pop()):
            if dll in needed or not os.path.exists(os.path.join(QT, "bin", dll)): continue
            needed.add(dll)
            todo.append(os.path.join(QT, "bin", dll))
    for dll in sorted(needed): shutil.copy2(os.path.join(QT, "bin", dll), b)
    with open(os.path.join(b, "qt.conf"), "w") as f:
        f.write("[Paths]\nPrefix = .\nPlugins = plugins\nQml2Imports = qml\n")
    print("bin: %d Qt/MinGW DLLs" % len(needed))

    # python: the embeddable Python (with the script's folder on sys.path, as a normal Python does)
    py = os.path.join(out, "python")
    # dist/cache: downloads kept for the next build - not something to hand out, the zip has it unpacked
    os.makedirs(os.path.join(dist, "cache"), exist_ok=True)
    zpath = os.path.join(dist, "cache", os.path.basename(PYTHON_EMBED))
    if os.path.exists(os.path.join(dist, os.path.basename(PYTHON_EMBED))):              # where older builds kept it
        os.replace(os.path.join(dist, os.path.basename(PYTHON_EMBED)), zpath)
    if not os.path.exists(zpath):
        print("downloading", PYTHON_EMBED)
        urllib.request.urlretrieve(PYTHON_EMBED, zpath)
    with zipfile.ZipFile(zpath) as z: z.extractall(py)
    for pth in glob.glob(os.path.join(py, "python*._pth")):
        with open(pth, "a") as f: f.write("\n..\\tools\n")
    print("python:", os.path.basename(PYTHON_EMBED))

    # busybox (in tools/, so a development tree has it too): fetched when missing, always checked
    import hashlib
    bb = os.path.join(TOOLS, "busybox", "busybox.exe")
    if not os.path.exists(bb):
        print("downloading", BUSYBOX_URL)
        req = urllib.request.Request(BUSYBOX_URL, headers={"User-Agent": "Mozilla/5.0"})   # the site refuses urllib's
        with urllib.request.urlopen(req) as r, open(bb, "wb") as f: f.write(r.read())
    with open(bb, "rb") as f:
        if hashlib.sha256(f.read()).hexdigest() != BUSYBOX_SHA256:
            sys.exit("tools/busybox/busybox.exe is not %s (sha256 differs)" % os.path.basename(BUSYBOX_URL))
    print("busybox:", os.path.basename(BUSYBOX_URL))

    # the simulator's own files
    for d in ("sim", "tools", "tests", "docs", "src"):
        if os.path.isdir(os.path.join(HOME, d)):
            copy_tree_filtered(os.path.join(HOME, d), os.path.join(out, d), lambda rel: rel.split(os.sep)[0] in ("out", "build"))
    for f in ("README.md", "VERSION", "toonsim.bat"):
        shutil.copy2(os.path.join(HOME, f), out)
    os.makedirs(os.path.join(out, "apps"))
    with open(os.path.join(out, "apps", "PUT-YOUR-APPS-HERE.txt"), "w") as f:
        f.write("Each app in its own folder, as in /qmf/qml/apps on the Toon: apps\\<app>\\<App>App.qml - see docs\\MANUAL.md.\n")
    os.makedirs(os.path.join(out, "firmware"))
    with open(os.path.join(out, "firmware", "README.txt"), "w") as f:
        f.write("The Toon's GUI goes here. toonsim.bat copies it from your own rooted Toon at its first start\n"
                "(or: tools\\pull_firmware.bat <ip address of your Toon>). See docs\\MANUAL.md.\n")

    zip_path = os.path.join(dist, name + ".zip")
    if os.path.exists(zip_path): os.remove(zip_path)
    shutil.make_archive(os.path.join(dist, name), "zip", dist, name)
    size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(out) for f in fs)
    print("built %s (%.0f MB unpacked, %.0f MB zip)" % (zip_path, size / 1e6, os.path.getsize(zip_path) / 1e6))


if __name__ == "__main__":
    main()
