"""Applies a downloaded Toonsim update archive after the running simulator exits.
Safely extracts new files over the installation, preserving user data (firmware, apps, data).
"""
import argparse, json, os, shutil, subprocess, sys, tarfile, time, zipfile

PRESERVED = {"firmware", "data", "apps"}


def wait_for_pid(pid, timeout=30):
    if not pid or pid <= 0:
        return
    start = time.time()
    if os.name == "nt":
        import ctypes
        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x100000, False, pid)  # SYNCHRONIZE
        if h:
            k.WaitForSingleObject(h, int(timeout * 1000))
            k.CloseHandle(h)
    else:
        while time.time() - start < timeout:
            try:
                os.kill(pid, 0)
                time.sleep(0.5)
            except OSError:
                break
    # Give the operating system a second to release file locks on DLLs
    time.sleep(1.0)


def extract_archive(archive_path, extract_dir):
    shutil.rmtree(extract_dir, ignore_errors=True)
    os.makedirs(extract_dir, exist_ok=True)
    if archive_path.endswith(".zip"):
        with zipfile.ZipFile(archive_path, "r") as z:
            z.extractall(extract_dir)
    elif archive_path.endswith((".tar.gz", ".tgz")):
        with tarfile.open(archive_path, "r:gz") as t:
            t.extractall(extract_dir)
    else:
        raise ValueError(f"Unknown archive format: {archive_path}")


def copy_tree_safe(src, dst):
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        top_folder = rel.split(os.sep)[0] if rel != "." else ""
        if top_folder in PRESERVED:
            dirs[:] = []
            continue

        target_dir = os.path.join(dst, rel) if rel != "." else dst
        os.makedirs(target_dir, exist_ok=True)

        for f in files:
            src_f = os.path.join(root, f)
            dst_f = os.path.join(target_dir, f)
            try:
                if os.path.exists(dst_f):
                    os.chmod(dst_f, 0o777)
                shutil.copy2(src_f, dst_f)
            except Exception as e:
                print(f"Warning: could not update {dst_f}: {e}", file=sys.stderr)


def make_executable(path):
    if os.name != "nt" and os.path.exists(path):
        try:
            mode = os.stat(path).st_mode
            os.chmod(path, mode | 0o755)
        except OSError: pass


def main():
    parser = argparse.ArgumentParser(description="Toonsim update applier")
    parser.add_argument("--wait-pid", type=int, default=0, help="PID of toonsim to wait for")
    parser.add_argument("--archive", required=True, help="Path to update archive (.zip / .tar.gz)")
    parser.add_argument("--home", required=True, help="Toonsim root directory")
    parser.add_argument("--launcher", default="", help="Launcher script to restart")
    parser.add_argument("--args", default="[]", help="JSON list of arguments to pass to launcher")
    args = parser.parse_args()

    print(f"Toonsim updater: waiting for process {args.wait_pid} to terminate...")
    wait_for_pid(args.wait_pid)

    home = os.path.abspath(args.home)
    extract_dir = os.path.join(home, "data", "tmp", "update_extracted")

    print(f"Toonsim updater: extracting {args.archive}...")
    extract_archive(args.archive, extract_dir)

    # Detect if the archive has a single top-level directory (e.g. toonsim-1.2.0-win64/)
    items = [i for i in os.listdir(extract_dir) if not i.startswith(".")]
    if len(items) == 1 and os.path.isdir(os.path.join(extract_dir, items[0])):
        source_root = os.path.join(extract_dir, items[0])
    else:
        source_root = extract_dir

    print(f"Toonsim updater: updating files in {home}...")
    copy_tree_safe(source_root, home)

    # Ensure Linux executables retain execute permissions
    if os.name != "nt":
        make_executable(os.path.join(home, "toonsim.sh"))
        make_executable(os.path.join(home, "bin", "toonsim"))
        for s in os.listdir(os.path.join(home, "tools")):
            if s.endswith(".sh"): make_executable(os.path.join(home, "tools", s))

    # Clean up update files
    shutil.rmtree(extract_dir, ignore_errors=True)
    try: os.remove(args.archive)
    except OSError: pass

    # Restart toonsim
    launcher = args.launcher
    if not launcher:
        launcher = os.path.join(home, "toonsim.bat" if os.name == "nt" else "toonsim.sh")

    extra_args = []
    try:
        extra_args = json.loads(args.args)
    except Exception: pass

    if os.path.exists(launcher):
        print(f"Toonsim updater: restarting {launcher}...")
        cmd = [launcher] + extra_args
        if os.name == "nt":
            subprocess.Popen(cmd, cwd=home, creationflags=subprocess.CREATE_NEW_CONSOLE | subprocess.DETACHED_PROCESS)
        else:
            subprocess.Popen(cmd, cwd=home)
    else:
        print(f"Toonsim updater: could not find launcher {launcher}")


if __name__ == "__main__":
    main()

