"""Copies the Toon GUI's resources from your (rooted) Toon into firmware/, which the simulator runs:

    python tools/pull_firmware.py <toon-ip> [user] [password] [--apps] [--settings]    (default user: root)
    python tools/pull_firmware.py --setup      asks for the Toon's address and password, then copies it all
                                               (toonsim.bat runs this at its first start)

    --apps       also the custom apps installed on the Toon (/qmf/qml/apps/<app>, the ones with an
                 <Name>App.qml) into apps/ - an app already there is left alone
    --settings   also the apps' settings (/mnt/data/tsc/*.json, e.g. postnl.userSettings.json) into
                 data/mnt/data/tsc/ - a file already there is left alone

What it copies (read-only on the Toon): /qmf/qml/resources-static-base.rcc and drawables-base.rcc (the
GUI), /qmf/qml/qb and /qmf/qml/config, the built-in apps' translations (/qmf/qml/apps/*/lang), and the
firmware version and the model (from opkg's base-*.control: base-qb2 is a Toon 1, base-nxt a Toon 2;
the model goes into firmware/toon-model.txt, the size toonsim.bat starts with). Then it builds the compatibility patches for Qt 5.15
(firmware/compat.rcc, see build_compat.py).

It uses PuTTY's plink when it finds it (on the PATH or in Program Files\\PuTTY): then the password can be
given on the command line. Otherwise the ssh of Windows: a password given reaches it through SSH_ASKPASS
(askpass.bat), without one it asks at every step; the extra options let it talk to the old dropbear of a
stock Toon. The data comes over ssh as a tar stream, as
pscp copies nothing from the Toon's BusyBox while still reporting success.
"""
import getpass, os, shutil, subprocess, sys, tarfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.dirname(TOOLS)
OUT = os.path.join(HOME, "firmware")

FILES = "cd /qmf/qml && tar -chf - resources-static-base.rcc drawables-base.rcc qb config $(ls -d apps/*/lang 2>/dev/null)"
# the Toon's own base package: base-nxt-* on a Toon 2, base-qb2-* on a Toon 1 (not base-files, base-passwd)
# prints "toon2 <version>" or "toon1 <version>"
VERSION = ("for f in /var/lib/opkg/info/base-nxt-*.control /var/lib/opkg/info/base-qb2-*.control"
           " /usr/lib/opkg/info/base-nxt-*.control /usr/lib/opkg/info/base-qb2-*.control; do [ -f \"$f\" ] || continue;"
           " case \"$f\" in *qb2*) m=toon1;; *) m=toon2;; esac;"
           " echo \"$m $(grep -m 1 '^Version:' \"$f\" | cut -d' ' -f2)\"; break; done")
# the custom apps: folders with an <Name>App.qml, by their plain name (tar -h follows the <app> link to
# <app>-<version>, as ToonStore installs them); built-in apps only have their lang/ folder there
APPS = ("cd /qmf/qml/apps && tar -chf - $(for d in *; do case \"$d\" in *-*) continue;; esac; "
        "[ -d \"$d\" ] && ls \"$d\"/*App.qml >/dev/null 2>&1 && echo \"$d\"; done)")
# the readable ones (a non-root login cannot read every file); the others are named on stderr
SETTINGS = ("cd /mnt/data/tsc && tar -cf - $(for f in *.json; do if [ -r \"$f\" ]; then echo \"$f\"; "
            "else echo \"not readable for this login: $f\" >&2; fi; done)")
SSH_OPTS = ["-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa", "-o", "MACs=+hmac-sha1",
            "-o", "StrictHostKeyChecking=accept-new"]


class RemoteError(Exception):
    pass


def find_plink():
    if os.environ.get("TOONSIM_SSH") == "ssh" or os.name != "nt": return None     # ssh (Linux: always ssh)
    p = shutil.which("plink")
    if p: return p
    for base in (os.environ.get("ProgramFiles", r"C:\Program Files"), os.environ.get("ProgramFiles(x86)", "")):
        c = os.path.join(base, "PuTTY", "plink.exe")
        if base and os.path.exists(c): return c
    return None


def remote(toon, user, password, command):
    plink = find_plink()
    env = None
    if plink:
        cmd = [plink, "-ssh", "-l", user] + (["-pw", password] if password else []) + [toon, command]
    else:
        ssh = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32", "OpenSSH", "ssh.exe")
        if os.name != "nt" or not os.path.exists(ssh): ssh = shutil.which("ssh")
        if not ssh:
            raise RemoteError("Neither PuTTY's plink nor ssh found: install PuTTY or an OpenSSH client"
                              " (Linux: sudo apt install openssh-client).")
        cmd = [ssh] + SSH_OPTS + ["%s@%s" % (user, toon), command]
        if password:                  # ssh takes a password only from the console, or from SSH_ASKPASS
            askpass = os.path.join(TOOLS, "askpass.bat" if os.name == "nt" else "askpass.sh")
            if os.name != "nt": os.chmod(askpass, 0o755)
            env = dict(os.environ, SSH_ASKPASS=askpass, SSH_ASKPASS_REQUIRE="force",
                       TOONSIM_PW=password, TOONSIM_ASKPY=sys.executable)
            if os.name != "nt": env.setdefault("DISPLAY", ":0")          # older ssh wants one for askpass
            cmd[1:1] = ["-o", "NumberOfPasswordPrompts=1"]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, env=env)   # stdin/stderr stay the console: prompts
    if r.returncode != 0:
        raise RemoteError("The command on the Toon failed (exit %d) - see the messages above." % r.returncode)
    return r.stdout


def extract_new(data, dest, what):
    """extracts a tar stream into dest, leaving top-level entries that already exist there alone"""
    import io
    os.makedirs(dest, exist_ok=True)
    kept, added = set(), set()
    with tarfile.open(fileobj=io.BytesIO(data)) as tf:
        for m in tf.getmembers():
            top = m.name.split("/")[0]
            if top in kept or (top not in added and os.path.exists(os.path.join(dest, top))):
                kept.add(top); continue
            added.add(top)
            tf.extract(m, dest, filter="data")
    print("%s: copied %s" % (what, ", ".join(sorted(added)) or "nothing new"))
    if kept: print("%s: already there, left alone: %s" % (what, ", ".join(sorted(kept))))


def ask(question, default=""):
    try:
        a = input("%s%s: " % (question, " [%s]" % default if default else "")).strip()
    except EOFError:
        raise SystemExit(1)
    return a or default


def setup():
    """the first start: asks for the Toon and checks the login; returns what pull() needs"""
    print("""
  Welcome to toonsim, the Toon on your PC.

  The simulator runs the Toon's own screens, so it needs them from your Toon, once: a rooted Toon
  on your network that you can log in to with SSH. Nothing on the Toon is changed.
""")
    toon, user = "", "root"
    while True:
        toon = ask("  IP address of your Toon", toon)          # a retry offers the previous answers
        if not toon: continue
        user = ask("  Login", user)
        password = getpass.getpass("  Password [toon]: ") or "toon"
        print("\n  Connecting to %s@%s ..." % (user, toon))
        try:
            if b"toonsim-ok" in remote(toon, user, password, "echo toonsim-ok"): break
        except RemoteError:
            pass
        print("  That did not work: check the address, login and password, and that the Toon is rooted"
              " with SSH on.\n")
    both = ask("\n  Also copy the apps installed on your Toon, with their settings? (Y/n)", "Y")
    return toon, user, password, ["--apps", "--settings"] if both.lower().startswith("y") else []


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    try:
        if "--setup" in flags:
            toon, user, password, more = setup()
            pull(toon, user, password, flags + more)
            print("\n  Done. Starting the simulator; its first start also installs ToonStore.\n")
            return
        if not args:
            print(__doc__)
            sys.exit(1)
        pull(args[0], args[1] if len(args) > 1 else "root", args[2] if len(args) > 2 else "", flags)
    except RemoteError as e:
        sys.exit(str(e))


def pull(toon, user, password, flags):
    os.makedirs(OUT, exist_ok=True)
    if not find_plink() and not password:
        print("Connecting with ssh to %s@%s - type the Toon's password when asked." % (user, toon))
    data = remote(toon, user, password, FILES)
    tar_path = os.path.join(OUT, "qmf_qml.tar")
    with open(tar_path, "wb") as f: f.write(data)
    try:
        with tarfile.open(tar_path) as tf:
            names = tf.getnames()
            if "resources-static-base.rcc" not in names:
                sys.exit("The Toon sent no resources-static-base.rcc - is this a rooted Toon with its GUI in /qmf/qml?")
            tf.extractall(OUT, filter="data")
    finally:
        os.remove(tar_path)
    model, _, version = remote(toon, user, password, VERSION).decode("utf-8", "replace").strip().partition(" ")
    with open(os.path.join(OUT, "firmware-version.txt"), "w") as f: f.write(version + "\n")
    if model:
        with open(os.path.join(OUT, "toon-model.txt"), "w") as f: f.write(model + "\n")
    subprocess.run([sys.executable, os.path.join(TOOLS, "build_compat.py")], check=True)
    print("\nFirmware %s (%s) copied from %s into %s" % (version or "(version unknown)",
          {"toon1": "Toon 1", "toon2": "Toon 2"}.get(model, "model unknown"), toon, OUT))
    if "--apps" in flags:
        extract_new(remote(toon, user, password, APPS), os.path.join(HOME, "apps"), "apps")
    if "--settings" in flags:
        extract_new(remote(toon, user, password, SETTINGS), os.path.join(HOME, "data", "mnt", "data", "tsc"), "settings")


if __name__ == "__main__":
    main()
