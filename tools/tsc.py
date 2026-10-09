"""tsc for the simulator: the Toon's TSC helper script (/usr/bin/tsc, a copy of the device's version is
sim/tsc/tsc.device.sh) as far as it matters on a PC.

toonsim starts it (and starts it again when it stops, like the Toon's inittab). Every 5 seconds it
looks at the command file /tmp/tsc.command (data/tmp/tsc.command here) that apps write, and runs the
commands in it:

    toonstore     install the apps in /tmp/packages_to_install.txt ("folder-version ..."), from the
                  ToonSoftwareCollective GitHub repository, and remove those in
                  /tmp/packages_to_delete.txt; then restart the GUI
    deletefile    delete the files in /tmp/files_to_delete.txt from /mnt/data/tsc/appData
    postnl        run apps/postnl/postnl.sh with the account from postnl.userSettings.json
    external-<app>  run apps/<app>/<app>.sh in the background
                  (both in a Unix shell for Windows, see run_app_script)

As on the Toon an app is installed as apps/<app>-<version> with apps/<app> pointing to it (a
junction here, a symlink on the Toon). Removing an app removes apps/<app>*, with two safety nets
the Toon does not have: a link is removed without touching what it points to (your own working
folder linked into apps/ stays), and a folder the simulator did not install itself is moved to
data/tsc/removed/ instead of deleted.

Left out, because they concern the device and not the apps: firmware and resource file updates,
self update, CA certificates, the mobile web app, VPN, firewall, root password, activation, the
Toon 2 sensors. Their commands (tscupdate, toonupdate, togglebeta, flushfirewall,
restorerootpassword) change nothing here; most send the notification the device sends.

Log: data/var/log/tsc (the Toon's /var/log/tsc) and the simulator's log, prefixed "tsc:".
("data" is the simulator's --data folder, data/ by default.)
"""
import argparse, datetime, glob, json, os, shutil, socket, sys, tarfile, threading, time, urllib.request
import updater

VERSION = "2.61-toonsim"
ROUNDWAIT = 5
GITHUB = "ToonSoftwareCollective"
MARKER = ".toonsim-installed"          # in an app folder this script installed

A = None                               # command line arguments
LOGFILE = None


def log(msg):
    line = "%s %s" % (datetime.datetime.now().strftime("%d/%m/%Y %H:%M:%S"), msg)
    print(line, flush=True)
    if LOGFILE:
        try:
            with open(LOGFILE, "a", encoding="utf-8") as f: f.write(line + "\n")
        except OSError: pass


def dev(path):
    """device path -> PC path, as src/pathmap.cpp maps it"""
    p = path.replace("\\", "/")
    if p.startswith("/qmf/qml/apps"): return os.path.normpath(A.apps + p[len("/qmf/qml/apps"):])
    if p == "/qmf/qml/config" or p.startswith("/qmf/qml/config/"): return os.path.normpath(os.path.join(A.data, p.lstrip("/")))
    if p == "/qmf/config" or p.startswith("/qmf/config/"):        # a link to /mnt/data/qmf/config on the Toon
        return os.path.normpath(os.path.join(A.data, "mnt", "data", p.lstrip("/")))
    for d in ("/qmf/www", "/qmf/etc"):                               # the same as /HCBv2/www, /HCBv2/etc there
        if p == d or p.startswith(d + "/"): return os.path.normpath(os.path.join(A.data, "HCBv2", p[len("/qmf/"):]))
    if p.startswith("/qmf/qml/"): return os.path.normpath(os.path.join(A.home, "firmware", p[len("/qmf/qml/"):]))
    if p.startswith("/qmf/"): return os.path.normpath(os.path.join(A.home, "firmware", "qmf", p[len("/qmf/"):]))
    return os.path.normpath(os.path.join(A.data, p.lstrip("/")))


def http_get(url, binary=False, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "toonsim-tsc/" + VERSION})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def control(line):
    with socket.create_connection(("127.0.0.1", A.port), timeout=5) as s:
        s.sendall((line + "\n").encode("utf-8"))
        return s.recv(4096)


def notify(sub_type, text, type_="tsc"):
    """the device script's /HCBv2/bin/bxt -d :happ_usermsg -s Notification -n CreateNotification -a type -v tsc ..."""
    if not A.port: return
    try:
        control("eval simDevices.createNotification(%s, %s, %s)" % (json.dumps(type_), json.dumps(sub_type), json.dumps(text)))
    except OSError as e:
        log("Could not send the notification: %s" % e)


def restart_gui():
    """the Toon's "killall -9 qt-gui": the GUI starts again and loads the new set of apps"""
    if not A.port:
        log("GUI restart needed, but toonsim has no control port: restart it yourself")
        return
    try:
        control("restart")
        log("Restarting the GUI")
    except OSError as e:
        log("Could not ask toonsim to restart: %s" % e)


# ---- apps (toonStoreRemove / toonStoreInstall / toonStore of the device script) ----

def is_junction(path):
    f = getattr(os.path, "isjunction", None)                # Python 3.12+; Windows only anyway
    return bool(f and f(path))


def is_link(path):
    return os.path.islink(path) or is_junction(path)


def link_dir(target, link):
    """<app> -> <app>-<version>: a symlink, as on the Toon; on Windows a junction (no admin rights needed)"""
    if os.name == "nt":
        import _winapi
        _winapi.CreateJunction(target, link)
    else:
        os.symlink(os.path.basename(target), link)          # relative, as ToonStore does on the device


def remove_entry(path):
    name = os.path.basename(path)
    if is_link(path):
        os.rmdir(path) if is_junction(path) else os.unlink(path)
        log("Removed link %s (what it pointed to is untouched)" % name)
    elif os.path.isdir(path):
        if os.path.exists(os.path.join(path, MARKER)):
            shutil.rmtree(path)
            log("Removed %s" % name)
        else:
            dest = os.path.join(dev("/mnt/data/tsc"), "removed", "%s.%s" % (name, time.strftime("%Y%m%d-%H%M%S")))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.move(path, dest)
            log("Moved %s to %s (not installed by the simulator, so kept)" % (name, dest))
    elif os.path.exists(path):
        os.remove(path)


def toonstore_remove(app):
    # the device also removes an old opkg installation of the app first: there is no opkg here
    for path in glob.glob(os.path.join(A.apps, glob.escape(app) + "*")):
        try: remove_entry(path)
        except OSError as e: log("Could not remove %s: %s" % (path, e))


def extract(tar_path, dest):
    with tarfile.open(tar_path) as tf:
        for m in tf.getmembers():
            try:
                tf.extract(m, dest, filter="data")
            except Exception as e:           # a name Windows cannot have, a link outside the tree, ...
                log("  skipped %s: %s" % (m.name, e))


def toonstore_install(app, version):
    try:
        tags = http_get("https://api.github.com/repos/%s/%s/tags" % (GITHUB, app))
    except Exception as e:
        log("Can not reach github for %s: %s" % (app, e))
        return
    if '"name": "%s"' % version not in tags and '"name":"%s"' % version not in tags:
        log("Can not find %s %s in github!" % (app, version))
        return
    work = dev("/tmp/%s-%s" % (app, version))
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    try:
        tar_path = os.path.join(work, app + ".tar.gz")
        with open(tar_path, "wb") as f:
            f.write(http_get("https://api.github.com/repos/%s/%s/tarball/%s" % (GITHUB, app, version), binary=True, timeout=300))
        extract(tar_path, work)
        dirs = [d for d in os.listdir(work) if os.path.isdir(os.path.join(work, d))]
        if len(dirs) != 1:
            log("download failed! (%d folders in the archive)" % len(dirs))
            return
        # first remove old versions of the app, then move the new version in and link the app to it
        toonstore_remove(app)
        target = os.path.join(A.apps, "%s-%s" % (app, version))
        shutil.move(os.path.join(work, dirs[0]), target)
        open(os.path.join(target, MARKER), "w").close()
        link_dir(target, os.path.join(A.apps, app))
        log("Installed %s %s ..." % (app, version))
        if app == "wastecollection":
            wastecollection_provider()
    except Exception as e:
        log("download failed! %s" % e)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def wastecollection_provider():
    provider = "1"
    try:
        with open(dev("/mnt/data/tsc/wastecollection.userSettings.json"), encoding="utf-8") as f:
            provider = json.load(f).get("Afvalverwerker") or "1"
    except Exception: pass
    try:
        js = http_get("https://raw.githubusercontent.com/%s/wastecollection_plugins/main/wastecollectionProvider_%s.js" % (GITHUB, provider))
        with open(dev("/qmf/qml/apps/wastecollection/wastecollectionProvider.js"), "w", encoding="utf-8") as f: f.write(js)
        log("Downloading script for afvalverwerker %s" % provider)
    except Exception:
        log("Downloading script for afvalverwerker %s failed" % provider)


def split_package(p):
    """"sonos-1.3.5" -> ("sonos", "1.3.5"): the version is what follows the last "-" before a digit"""
    for i in range(len(p) - 1, 0, -1):
        if p[i - 1] == "-" and p[i].isdigit():
            return p[:i - 1], p[i:]
    return p, ""


def read_list(device_path):
    path = dev(device_path)
    if not os.path.exists(path) or os.path.getsize(path) == 0: return None
    with open(path, encoding="utf-8") as f: items = f.read().split()
    os.remove(path)                    # before the work, so a restart halfway does not repeat it
    return items


def toonstore():
    log("Toonstore instructed me to install or remove software")
    installs = read_list("/tmp/packages_to_install.txt")
    deletes = read_list("/tmp/packages_to_delete.txt")
    for p in installs or []:
        log("Installing: %s" % p)
        toonstore_install(*split_package(p))
    for p in deletes or []:
        app = p.split("-")[0]           # as the device: cut -d- -f1
        log("Deleting: %s" % app)
        toonstore_remove(app)
    restart_gui()


def delete_file():
    log("Delete file(s) from /mnt/data/tsc/appData")
    for name in read_list("/tmp/files_to_delete.txt") or []:
        path = os.path.normpath(os.path.join(dev("/mnt/data/tsc/appData"), name))
        if not path.startswith(dev("/mnt/data/tsc/appData")):
            log("Not deleting %s: outside appData" % name)
            continue
        log("Deleting: /mnt/data/tsc/appData/%s" % name)
        try: os.remove(path)
        except OSError as e: log("  %s" % e)


# ---- the apps' own shell scripts (postnl, external-<app>) ----
#
# They run unchanged in a Unix shell for Windows: by default the bundled BusyBox (tools/busybox/, the
# Windows build of the BusyBox the Toon itself runs), else MSYS2 (e.g. devkitPro's) or Git for Windows.
# Two adaptations: the device paths in the script and its arguments point to the simulator's folders
# (a rewritten copy in data/tmp/toonsim-scripts/ is what runs), and tools/shims/ comes first on the
# PATH with stand-ins for device commands: bxt (a notification in the GUI), killall qt-gui and reboot /
# shutdown (a GUI restart - never the PC's: Windows' own shutdown.exe takes -r), opkg and pkill (nothing).

SCRIPT_PATHS = ["/qmf/qml/apps", "/qmf/config", "/mnt/data", "/tmp", "/var/volatile", "/var/log", "/var/run", "/HCBv2", "/root"]
TOOLS = os.path.dirname(os.path.abspath(__file__))
SHIMS = os.path.join(TOOLS, "shims")
BUSYBOX = os.path.join(TOOLS, "busybox", "busybox.exe")
SHELL_CANDIDATES = [BUSYBOX, r"C:\devkitPro\msys2\usr\bin\sh.exe", r"C:\msys64\usr\bin\sh.exe",
                    r"C:\Program Files\Git\bin\sh.exe", r"C:\Program Files\Git\usr\bin\sh.exe"]
# BusyBox runs its own applet before a program on the PATH; these must be the stand-ins instead
BUSYBOX_OVERRIDE = "killall pkill"


def find_shell():
    if os.name != "nt":
        # Linux: the system's own sh. Never a Windows candidate - under WSL busybox.exe would run as a
        # Windows program, with Windows' PATH (shutdown.exe instead of the stand-in)
        p = os.environ.get("TOONSIM_SH", "")
        if p and os.path.isfile(p) and not p.lower().endswith(".exe"): return p
        return "/bin/sh" if os.path.isfile("/bin/sh") else shutil.which("sh")
    for p in [os.environ.get("TOONSIM_SH", "")] + SHELL_CANDIDATES + [shutil.which("sh") or ""]:
        if p and os.path.isfile(p): return p
    return None


def is_busybox(sh):
    return os.path.basename(sh).lower().startswith("busybox")


def short_path(path):
    """the 8.3 form of a path with spaces (C:\\Users\\John Smith -> C:\\Users\\JOHNSM~1), so an unquoted $DIR
    in a script stays one word; the part that does not exist yet is kept as it is"""
    p = os.path.abspath(path)
    if " " not in p or os.name != "nt": return p
    import ctypes
    head, tail = p, []
    while head and not os.path.exists(head):
        head, t = os.path.split(head)
        tail.insert(0, t)
    buf = ctypes.create_unicode_buffer(32768)
    if ctypes.windll.kernel32.GetShortPathNameW(head, buf, len(buf)): head = buf.value
    return os.path.join(head, *tail)


def shell_path(path, sh=None):
    """a PC path as the shell understands it: C:/Users/x for BusyBox, /c/Users/x for MSYS2 and Git's shell"""
    p = short_path(path).replace("\\", "/")
    if sh and is_busybox(sh): return p
    return "/" + p[0].lower() + p[2:] if len(p) > 1 and p[1] == ":" else p


def map_device_paths(text, sh=None):
    import re
    # device commands called by their full path: to the stand-ins in tools/shims. Their real paths go in
    # as placeholders, put back at the end: the rewrites below must not take them for device paths (on
    # Linux the simulator itself can be in /tmp/..., /usr/...)
    real = []

    def keep(path):
        real.append(path)
        return "\x01%d\x01" % (len(real) - 1)
    for cmd, shim in (("/HCBv2/bin/bxt", "bxt"), ("/usr/bin/killall", "killall"), ("/bin/killall", "killall"),
                      ("/usr/bin/pkill", "pkill"), ("/usr/bin/opkg", "opkg"), ("/bin/opkg", "opkg"),
                      ("/sbin/reboot", "reboot"), ("/sbin/shutdown", "shutdown"), ("/sbin/poweroff", "poweroff"),
                      ("/sbin/halt", "halt"), ("/bin/reboot", "reboot")):
        token = keep(shell_path(os.path.join(SHIMS, shim), sh))
        text = re.sub(r'(?<![\w./-])%s(?![\w./-])' % re.escape(cmd), lambda m, t=token: t, text)
    # other programs by their full path (/usr/bin/curl): by name, from the PATH - BusyBox knows /bin/<applet>
    # only, and Windows' curl.exe is no /usr/bin/curl
    text = re.sub(r'(?<![\w./!-])/(?:usr/)?s?bin/([A-Za-z][\w.+-]*)(?![\w./-])', r'\1', text)
    # the Toon's own web server (happ_thermstat, hcb_rrd, ...) is the simulator's local web server
    if getattr(A, "http_port", 0):
        text = re.sub(r'http://(localhost|127\.0\.0\.1)(?=[/"\'\s]|$)', "http://127.0.0.1:%d" % A.http_port, text)

    def repl(m):
        return shell_path(dev(m.group(1)), sh)
    # a device path at the start of a word or after a quote, = or :, up to the next / or word end
    pat = r'(?<![\w./-])((?:%s))(?=[/"\'\s;)|&>]|$)' % "|".join(re.escape(p) for p in SCRIPT_PATHS)
    text = re.sub(pat, repl, text, flags=re.M)
    return re.sub("\x01(\\d+)\x01", lambda m: real[int(m.group(1))], text)


def run_app_script(app, args=(), background=False):
    """/bin/sh /qmf/qml/apps/<app>/<app>.sh args - as the device runs it, with the paths mapped"""
    src = dev("/qmf/qml/apps/%s/%s.sh" % (app, app))
    if not os.path.isfile(src) or os.path.getsize(src) == 0:
        log("/qmf/qml/apps/%s/%s.sh does not exist" % (app, app))
        return
    sh = find_shell()
    if not sh:
        log("Skipped %s.sh: no Unix shell found (tools/busybox/busybox.exe, MSYS2 or Git for Windows; or set TOONSIM_SH)" % app)
        return
    with open(src, encoding="utf-8", errors="replace") as f: text = f.read()
    work = dev("/tmp/toonsim-scripts")
    os.makedirs(work, exist_ok=True)
    script = os.path.join(work, app + ".sh")
    with open(script, "w", encoding="utf-8", newline="\n") as f:
        f.write(map_device_paths(text.replace("\r\n", "\n"), sh))
    argv = [map_device_paths(a, sh) for a in args]
    env = dict(os.environ)
    env["PATH"] = SHIMS + os.pathsep + os.path.dirname(sh) + os.pathsep + env.get("PATH", "")
    env["TOONSIM_PY"] = shell_path(sys.executable, sh)
    env["TOONSIM_TSC"] = shell_path(os.path.abspath(__file__), sh)
    env["TOONSIM_PORT"] = str(A.port)
    if is_busybox(sh):
        env["BB_OVERRIDE_APPLETS"] = BUSYBOX_OVERRIDE
        # no MSYS2 / Cygwin programs (Git's or devkitPro's usr\bin): started by a non-MSYS program they
        # expand {..} and * in their arguments themselves - curl -w "%{http_code}" printed "%http_code"
        env["PATH"] = os.pathsep.join(d for d in env["PATH"].split(os.pathsep) if not d or not any(
            os.path.exists(os.path.join(d, dll)) for dll in ("msys-2.0.dll", "cygwin1.dll")))
        env["MSYS"] = env["CYGWIN"] = "noglob"
        cmd = [sh, "sh", shell_path(script, sh)]
    else:
        env["MSYS2_PATH_TYPE"] = "inherit"
        env["CHERE_INVOKING"] = "1"
        cmd = [sh, shell_path(script, sh)]
    import subprocess, threading
    log("Running %s.sh%s (with %s)" % (app, " in the background" if background else "", sh))
    proc = subprocess.Popen(cmd + argv, cwd=dev("/qmf/qml/apps/" + app), env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    def pump():
        for raw in proc.stdout:
            line = raw.decode("utf-8", "replace").rstrip()
            if line: log("  [%s.sh] %s" % (app, line))
        code = proc.wait()
        log("%s.sh ended (exit %d)" % (app, code))

    if background:
        threading.Thread(target=pump, daemon=True).start()
    else:
        try:
            t = threading.Thread(target=pump, daemon=True)
            t.start()
            t.join(600)
            if t.is_alive():
                proc.kill()
                log("%s.sh took over 10 minutes and was stopped" % app)
        except Exception as e:
            log("%s.sh: %s" % (app, e))


def postnl():
    # the device: read Userid/Password from postnl.userSettings.json and run
    # /bin/sh /qmf/qml/apps/postnl/postnl.sh -u $USERID -p $PASSWORD -d /tmp/postnl
    try:
        with open(dev("/mnt/data/tsc/postnl.userSettings.json"), encoding="utf-8") as f:
            s = json.load(f)
    except Exception:
        return
    user, pw = s.get("Userid") or "", s.get("Password") or ""
    if user and pw:
        run_app_script("postnl", ["-u", user, "-p", pw, "-d", "/tmp/postnl"])


# ---- a fresh simulator gets ToonStore (as a Toon rooted with TSC has it) ----

def ensure_toonstore():
    if os.path.exists(os.path.join(A.apps, "toonstore")) or os.environ.get("TOONSIM_NO_TOONSTORE_INSTALL"):
        return                              # (tools/run_tests.py sets that: no GUI restart during tests)
    try:
        repo = http_get("https://raw.githubusercontent.com/%s/toonstore_AppRepository/main/ToonRepo.xml" % GITHUB)
    except Exception as e:
        log("No ToonStore in the apps folder, and GitHub not reachable to install it: %s" % e)
        return
    import re
    m = re.search(r"<app>\s*<name>[^<]*</name>\s*<version>\s*([^<\s]+)\s*</version>\s*<folder>toonstore</folder>", repo)
    if not m:
        log("No ToonStore in the apps folder, and its version is not in the repository list")
        return
    log("No ToonStore in the apps folder: installing ToonStore %s" % m.group(1))
    toonstore_install("toonstore", m.group(1))
    if os.path.exists(os.path.join(A.apps, "toonstore")):
        restart_gui()


# ---- Toon mobile (the device script's checkMobileWeb / installMobileWeb) ----
# The mobile web site of ToonSoftwareCollective/mobile, in /HCBv2/www/mobile - served by the simulator's
# local web server as http://127.0.0.1:<web port>/mobile/. Installed at the start and updated when
# GitHub has a newer release; checked every 12 hours, as the device does.

MOBILE_CHECK = 12 * 3600
_last_mobile_check = 0


def check_mobile_web():
    global _last_mobile_check
    _last_mobile_check = time.time()
    folder = dev("/HCBv2/www/mobile")
    current = ""
    try:
        with open(os.path.join(folder, "version.txt"), encoding="utf-8") as f: current = f.read().strip()
    except OSError: pass
    try:
        rel = json.loads(http_get("https://api.github.com/repos/%s/mobile/releases/latest" % GITHUB))
    except Exception as e:
        log("Could not check for a Toon Mobile Web app: %s" % e)
        return
    latest = rel.get("tag_name", "")
    if current and (current == "0" or current == latest):
        return
    log("%s Toon Mobile Web app (%s), installing..." % ("New version of" if current else "Could not find mandatory", latest))
    work = dev("/tmp/mobile-install")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    try:
        tar_path = os.path.join(work, "mobile.tar.gz")
        with open(tar_path, "wb") as f: f.write(http_get(rel["tarball_url"], binary=True, timeout=300))
        extract(tar_path, work)
        dirs = [d for d in os.listdir(work) if os.path.isdir(os.path.join(work, d))]
        if len(dirs) != 1:
            log("Toon Mobile Web app: unexpected archive")
            return
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(os.path.dirname(folder), exist_ok=True)
        shutil.move(os.path.join(work, dirs[0]), folder)
        log("Installed toon mobile web app... (http://127.0.0.1:%d/mobile/)" % A.http_port)
    except Exception as e:
        log("Installing the Toon Mobile Web app failed: %s" % e)
    finally:
        shutil.rmtree(work, ignore_errors=True)


BETA = False
LATEST_UPDATE_INFO = None


def tsc_update(manual=True):
    global LATEST_UPDATE_INFO
    log("Checking for Toonsim updates from %s..." % updater.REPO)
    try:
        info = updater.check_for_update(repo=updater.REPO, home=A.home)
    except Exception as e:
        log("Check for updates failed: %s" % e)
        if manual: notify("notify", "Fout bij controleren op updates")
        return

    LATEST_UPDATE_INFO = info
    cur = info.get("current_version", "")
    new = info.get("latest_version", "")

    if info.get("update_available"):
        log("Toonsim update available: v%s (current: v%s)" % (new, cur))
        notify("update", "Toonsim update v%s beschikbaar" % new)
        if info.get("is_git"):
            try:
                control("eval updater.showGitNotice()")
            except Exception as e:
                log("Could not show git notice dialog: %s" % e)
        else:
            notes = (info.get("release_notes", "") or "").replace("\r", "").replace("\n", " ")[:150]
            url = info.get("asset_url", "")
            try:
                control("eval updater.showPrompt(%s, %s, %s, %s)" % (
                    json.dumps(cur), json.dumps(new), json.dumps(notes), json.dumps(url)))
            except Exception as e:
                log("Could not show update dialog: %s" % e)
    else:
        log("Toonsim is up-to-date (v%s)" % cur)
        if manual:
            notify("notify", "Toonsim is up-to-date (v%s)" % cur)
            try:
                control("eval updater.showUpToDate(%s)" % json.dumps(cur))
            except Exception as e:
                log("Could not show up-to-date dialog: %s" % e)


def handle_toonsim_update():
    global LATEST_UPDATE_INFO
    if not LATEST_UPDATE_INFO or not LATEST_UPDATE_INFO.get("asset_url"):
        info = updater.check_for_update(repo=updater.REPO, home=A.home)
        LATEST_UPDATE_INFO = info
        if not info.get("update_available") or not info.get("asset_url"):
            log("No update asset available to download")
            return

    info = LATEST_UPDATE_INFO
    asset_url = info["asset_url"]
    asset_name = info["asset_name"]
    dest = os.path.join(A.data, "tmp", "update", asset_name)

    log("Downloading update %s from %s..." % (asset_name, asset_url))
    try:
        control("eval updater.setProgress(0, 'Update downloaden...')")
    except Exception: pass

    last_reported = [-1]

    def on_progress(pct, cur, tot):
        if pct != last_reported[0] and (pct % 5 == 0 or pct == 100):
            last_reported[0] = pct
            try:
                cur_mb = cur / (1024 * 1024)
                tot_mb = tot / (1024 * 1024)
                msg = "Update downloaden (%.1f/%.1f MB)..." % (cur_mb, tot_mb)
                control("eval updater.setProgress(%d, %s)" % (pct, json.dumps(msg)))
            except Exception: pass

    try:
        updater.download_file(asset_url, dest, progress_callback=on_progress)
        log("Download complete (%s), starting updater process..." % dest)
        try:
            control("eval updater.setProgress(100, 'Download voltooid! De simulator herstart...')")
        except Exception: pass
        time.sleep(1.0)

        launcher = os.path.join(A.home, "toonsim.bat" if os.name == "nt" else "toonsim.sh")
        parent_pid = A.parent if A.parent else 0
        updater.start_apply_update(dest, home=A.home, wait_pid=parent_pid, launcher=launcher)
        log("Update process launched. Quitting toonsim...")
        time.sleep(0.5)
        control("quit")
    except Exception as e:
        log("Update failed: %s" % e)
        try:
            control("eval updater.setProgress(0, %s)" % json.dumps("Update mislukt: %s" % e))
        except Exception: pass


def flush_firewall():
    log("Flushing firewall rules - skipped, no firewall in the simulator")
    notify("firewall", "Firewall regels verwijderd")


def restore_root_password():
    log("Restoring root password to 'toon' - skipped, no root password in the simulator")
    notify("password", "Root password restored to 'toon'")


def toggle_beta():
    global BETA
    BETA = not BETA
    log("Switching to %s releases (nothing changes in the simulator)" % ("beta" if BETA else "production"))
    notify("firewall", "TSC Beta releases geselecteerd" if BETA else "TSC Productie releases geselecteerd")


COMMANDS = {
    "toonstore": lambda: toonstore(),
    "deletefile": lambda: delete_file(),
    "tscupdate": lambda: tsc_update(manual=True),
    "toonsimupdate": handle_toonsim_update,
    "flushfirewall": flush_firewall,
    "restorerootpassword": restore_root_password,
    "togglebeta": toggle_beta,
    "toonupdate": lambda: log("Skipped: no firmware updates in the simulator"),
    "postnl": lambda: postnl(),
}


def run_commands():
    path = dev("/tmp/tsc.command")
    if not os.path.exists(path) or os.path.getsize(path) == 0: return
    with open(path, encoding="utf-8", errors="replace") as f: text = f.read()
    os.remove(path)
    if text.split("-")[0].strip() == "external":
        app = text.split("-")[1].strip() if "-" in text else ""
        log("External sh request found (request app): %s" % app)
        log("%s app instructed me to do some external scripting : %s.sh" % (app, app))
        run_app_script(app, background=True)        # the device: /bin/sh ... >/dev/null 2>&1 &
        return
    for line in text.splitlines():
        line = line.strip()
        if not line: continue
        log("Command received: %s" % line)
        if line in COMMANDS: COMMANDS[line]()
        else: log("Command not available: %s" % line)


def watch_parent(pid):
    """stop when toonsim is gone (also when it was killed and could not stop us)"""
    if os.name == "nt":
        import ctypes
        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x100000, False, pid)            # SYNCHRONIZE
        if not h: os._exit(0)
        k.WaitForSingleObject(h, 0xFFFFFFFF)
        os._exit(0)
    while True:                                             # Linux: the parent changes when it is gone
        if os.getppid() != pid:
            os._exit(0)
        try:
            os.kill(pid, 0)
        except OSError:
            os._exit(0)
        time.sleep(1)


def shim_command(argv):
    """for tools/shims (bxt, killall): tsc.py notify|restart-gui --port P [type subType text]"""
    global A
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["notify", "restart-gui"])
    ap.add_argument("--port", type=int, default=int(os.environ.get("TOONSIM_PORT", "5555")))
    ap.add_argument("rest", nargs="*")
    A = ap.parse_intermixed_args(argv)      # words after --port too (Python < 3.12 refuses them otherwise)
    if A.what == "notify" and len(A.rest) >= 3:
        notify(A.rest[1], A.rest[2], A.rest[0])
    elif A.what == "restart-gui":
        control("restart")


def openssl(argv):
    """for tools/shims/openssl: what app scripts use openssl for - hashes, base64, random bytes - as
    Windows has no openssl.exe. stdin to stdout, as "openssl dgst -sha256 -binary | openssl base64" does."""
    import base64, hashlib
    data = lambda: sys.stdin.buffer.read()
    out = sys.stdout.buffer
    cmd, opts = (argv[0] if argv else ""), argv[1:]
    algs = ("md5", "sha1", "sha224", "sha256", "sha384", "sha512")
    if cmd in algs:                                        # "openssl sha256" is "openssl dgst -sha256"
        cmd, opts = "dgst", ["-" + cmd] + opts
    if cmd == "dgst":
        alg = next((o[1:] for o in opts if o[1:] in algs), "sha256")
        h = hashlib.new(alg, data())
        if "-binary" in opts: out.write(h.digest())
        else: out.write(("(stdin)= %s\n" % h.hexdigest()).encode())     # as the Toon's OpenSSL 1.x prints it
        return 0
    if cmd == "base64" or (cmd == "enc" and "-base64" in opts):
        if "-d" in opts:
            out.write(base64.b64decode(b"".join(data().split())))
        else:
            b = base64.b64encode(data())
            if "-A" in opts: out.write(b + b"\n")
            else: out.write(b"".join(b[i:i + 64] + b"\n" for i in range(0, len(b), 64)))
        return 0
    if cmd == "rand" and opts and opts[-1].isdigit():
        r = os.urandom(int(opts[-1]))
        if "-hex" in opts: out.write(r.hex().encode() + b"\n")
        elif "-base64" in opts: out.write(base64.b64encode(r) + b"\n")
        else: out.write(r)
        return 0
    sys.stderr.write("toonsim: openssl %s is not simulated (only dgst, base64 and rand)\n" % " ".join(argv))
    return 1


def main():
    global A, LOGFILE
    if len(sys.argv) > 1 and sys.argv[1] == "openssl":
        sys.exit(openssl(sys.argv[2:]))
    if len(sys.argv) > 1 and sys.argv[1] in ("notify", "restart-gui"):
        return shim_command(sys.argv[1:])
    ap = argparse.ArgumentParser()
    ap.add_argument("--home", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--apps", default=None)
    ap.add_argument("--data", default=None)
    ap.add_argument("--port", type=int, default=5555)
    ap.add_argument("--parent", type=int, default=0)
    ap.add_argument("--http-port", type=int, default=0)     # the simulated http://localhost (src/localweb.cpp)
    A = ap.parse_args()
    if A.parent:
        import threading
        threading.Thread(target=watch_parent, args=(A.parent,), daemon=True).start()
    A.home = os.path.abspath(A.home)
    A.apps = os.path.abspath(A.apps or os.path.join(A.home, "apps"))
    A.data = os.path.abspath(A.data or os.path.join(A.home, "data"))
    LOGFILE = dev("/var/log/tsc")
    os.makedirs(os.path.dirname(LOGFILE), exist_ok=True)
    if os.name != "nt":                                     # the stand-ins run from the PATH: executable
        for f in os.listdir(SHIMS):
            p = os.path.join(SHIMS, f)
            try: os.chmod(p, os.stat(p).st_mode | 0o111)
            except OSError: pass
    os.makedirs(dev("/mnt/data/tsc/appData"), exist_ok=True)
    os.makedirs(dev("/tmp"), exist_ok=True)
    log("Starting TSC support script (version %s), apps in %s" % (VERSION, A.apps))

    def check_updates_background():
        time.sleep(10)
        try:
            tsc_update(manual=False)
        except Exception as e:
            log("Background update check failed: %s" % e)

    threading.Thread(target=check_updates_background, daemon=True).start()

    try:
        ensure_toonstore()
    except Exception as e:
        log("Installing ToonStore failed: %s" % e)
    while True:
        start = time.time()
        try:
            run_commands()
            if A.http_port and time.time() - _last_mobile_check > MOBILE_CHECK:
                check_mobile_web()
        except Exception as e:
            log("Error: %s" % e)
        time.sleep(max(0.0, start + ROUNDWAIT - time.time()))


if __name__ == "__main__":
    main()
