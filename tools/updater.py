"""Toon simulator updater: checks https://github.com/ToonSoftwareCollective/toonsim for releases,
downloads and applies updates.
"""
import argparse, json, os, re, shutil, subprocess, sys, time, urllib.request

REPO = "ToonSoftwareCollective/toonsim"
HOME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def current_version(home=None):
    if not home: home = HOME
    vf = os.path.join(home, "VERSION")
    if os.path.exists(vf):
        try:
            with open(vf, encoding="utf-8") as f:
                return f.read().strip()
        except OSError: pass
    return "0.0.0"


def parse_version(v_str):
    if not v_str: return (0,)
    v_clean = v_str.strip().lstrip("v")
    parts = re.findall(r"\d+", v_clean)
    return tuple(map(int, parts)) if parts else (0,)


def is_git_repo(home=None):
    if not home: home = HOME
    return os.path.isdir(os.path.join(home, ".git"))


def check_for_update(repo=REPO, home=None):
    if not home: home = HOME
    cur_ver = current_version(home)
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    req = urllib.request.Request(url, headers={"User-Agent": f"toonsim-updater/{cur_ver}"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {
            "error": str(e),
            "update_available": False,
            "current_version": cur_ver,
            "latest_version": cur_ver,
        }

    tag = data.get("tag_name", "").strip()
    latest_ver = tag.lstrip("v") if tag else "0.0.0"
    is_newer = parse_version(latest_ver) > parse_version(cur_ver)

    # find asset matching platform
    plat_suffix = "-win64.zip" if os.name == "nt" else "-linux-x64.tar.gz"
    matching_asset = None
    for a in data.get("assets", []):
        aname = a.get("name", "")
        if aname.endswith(plat_suffix):
            matching_asset = a
            break

    return {
        "update_available": is_newer and (matching_asset is not None or is_git_repo(home)),
        "current_version": cur_ver,
        "latest_version": latest_ver,
        "release_name": data.get("name", f"Toon Simulator {latest_ver}"),
        "release_notes": data.get("body", ""),
        "published_at": data.get("published_at", ""),
        "asset_name": matching_asset.get("name") if matching_asset else "",
        "asset_url": matching_asset.get("browser_download_url") if matching_asset else "",
        "asset_size": matching_asset.get("size", 0) if matching_asset else 0,
        "is_git": is_git_repo(home),
    }


def download_file(url, target_path, progress_callback=None, timeout=300):
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    part_path = target_path + ".part"
    if os.path.exists(part_path):
        try: os.remove(part_path)
        except OSError: pass

    req = urllib.request.Request(url, headers={"User-Agent": "toonsim-updater"})
    with urllib.request.urlopen(req, timeout=timeout) as response, open(part_path, "wb") as out_file:
        total = int(response.headers.get("content-length", 0))
        downloaded = 0
        chunk_size = 64 * 1024
        last_pct = -1

        while True:
            chunk = response.read(chunk_size)
            if not chunk:
                break
            out_file.write(chunk)
            downloaded += len(chunk)
            if total > 0:
                pct = int(downloaded * 100 / total)
                if pct != last_pct:
                    last_pct = pct
                    if progress_callback:
                        progress_callback(pct, downloaded, total)

    if os.path.exists(target_path):
        try: os.remove(target_path)
        except OSError: pass
    os.rename(part_path, target_path)
    return target_path


def start_apply_update(archive_path, home=None, wait_pid=0, launcher="", extra_args=None):
    if not home: home = HOME
    if extra_args is None: extra_args = []
    py_exe = sys.executable
    apply_script = os.path.join(home, "tools", "apply_update.py")
    cmd = [
        py_exe, apply_script,
        "--wait-pid", str(wait_pid),
        "--archive", archive_path,
        "--home", home,
        "--launcher", launcher,
        "--args", json.dumps(extra_args)
    ]
    if os.name == "nt":
        return subprocess.Popen(cmd, cwd=home, creationflags=subprocess.CREATE_NEW_CONSOLE | subprocess.DETACHED_PROCESS)
    else:
        return subprocess.Popen(cmd, cwd=home, start_new_session=True)


def main():
    parser = argparse.ArgumentParser(description="Toonsim updater")
    parser.add_argument("--check", action="store_true", help="Check for available updates")
    parser.add_argument("--repo", default=REPO, help="GitHub repo (owner/name)")
    parser.add_argument("--home", default=HOME, help="Simulator home folder")
    parser.add_argument("--download", action="store_true", help="Download latest update")
    parser.add_argument("--update", action="store_true", help="Download and apply latest update")
    args = parser.parse_args()

    info = check_for_update(repo=args.repo, home=args.home)
    if "error" in info:
        print(f"Error checking updates: {info['error']}", file=sys.stderr)
        sys.exit(1)

    print(f"Current version: {info['current_version']}")
    print(f"Latest version:  {info['latest_version']}")
    print(f"Update available: {info['update_available']}")
    if info['asset_name']:
        print(f"Asset: {info['asset_name']} ({info['asset_size'] / (1024*1024):.1f} MB)")

    if (args.download or args.update) and info["update_available"] and info["asset_url"]:
        dest = os.path.join(args.home, "data", "tmp", "update", info["asset_name"])
        print(f"Downloading {info['asset_url']} to {dest}...")
        def on_prog(pct, cur, tot):
            print(f"\rDownloading: {pct}% ({cur/(1024*1024):.1f}/{tot/(1024*1024):.1f} MB)", end="", flush=True)
        download_file(info["asset_url"], dest, progress_callback=on_prog)
        print("\nDownload complete!")
        if args.update:
            print("Applying update...")
            start_apply_update(dest, home=args.home, wait_pid=os.getpid())
            print("Updater spawned, exiting.")
            sys.exit(0)


if __name__ == "__main__":
    main()
