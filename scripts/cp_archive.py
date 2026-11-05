#!/usr/bin/env python3
"""Archive filenames are the only persistent verdict state; no submission receipts."""
import argparse
import base64
import contextlib
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

FINAL = {"AC", "WA", "TLE", "RE", "CE", "MLE", "OLE", "IE"}
PATTERN = re.compile(r"^([A-Za-z0-9_]+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})(?:_([A-Z]+\+?))?\.nim$")
SUB_URL = re.compile(r"https://atcoder\.jp/contests/[^/\s]+/submissions/\d+")
LAST_REQUEST = 0.0


def username(root):
    value = os.environ.get("ATCODER_USER", "").strip()
    if not value and (root / ".atcoder-user").exists():
        value = (root / ".atcoder-user").read_text().strip()
    if not re.fullmatch(r"[A-Za-z0-9_]+", value):
        raise RuntimeError(".atcoder-userにAtCoderユーザー名を設定してください")
    return value


@contextlib.contextmanager
def locked(root, name):
    # Empty advisory lock files are not queues or verdict metadata.
    state = root / ".cp-state"
    state.mkdir(exist_ok=True)
    with (state / (name + ".lock")).open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
            return
        yield True


def scan(root):
    entries = []
    for path in (root / "archive").glob("*.nim"):
        match = PATTERN.fullmatch(path.name)
        if not match or not path.is_file():
            continue
        problem, stamp, verdict = match.groups()
        if verdict and verdict not in FINAL | {"AC+"}:
            continue
        at = int(dt.datetime.strptime(stamp, "%Y-%m-%d_%H-%M-%S").timestamp())
        entries.append({"problem": problem, "at": at, "verdict": verdict, "path": path})
    return sorted(entries, key=lambda e: (e["at"], e["path"].name), reverse=True)


def remove_legacy_receipts(root):
    for path in (root / "archive").glob("*.nim.pending.json*"):
        name = path.name.removesuffix(".tmp").removesuffix(".pending.json")
        if PATTERN.fullmatch(name) and path.is_file():
            path.unlink()


def task_id(root, problem):
    url = subprocess.check_output(["make", "-s", "--no-print-directory", "-C", str(root),
        "print-url", "FILE=work/" + problem + ".nim", "URL="], text=True).strip()
    parsed = urllib.parse.urlparse(url)
    match = re.fullmatch(r"/contests/[^/]+/tasks/([^/]+)", parsed.path)
    if parsed.netloc != "atcoder.jp" or not match:
        raise RuntimeError("print-urlの結果が不正です: " + problem)
    return match.group(1)


def fetch_all(user, since):
    global LAST_REQUEST
    submissions = {}
    while True:
        time.sleep(max(0, 2 - (time.monotonic() - LAST_REQUEST)))
        query = urllib.parse.urlencode({"user": user, "from_second": since})
        request = urllib.request.Request(
            "https://kenkoooo.com/atcoder/atcoder-api/v3/user/submissions?" + query,
            headers={"User-Agent": "cp-archive/2.0"})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                page = json.load(response)
        finally:
            LAST_REQUEST = time.monotonic()
        if not isinstance(page, list):
            raise RuntimeError("提出履歴APIの応答が配列ではありません")
        before = len(submissions)
        for sub in page:
            submissions[int(sub["id"])] = sub
        if len(page) < 500:
            return list(submissions.values())
        following = max(int(sub["epoch_second"]) for sub in page)
        if following < since or (following == since and len(submissions) == before):
            raise RuntimeError("同一秒の提出履歴を取得し切れないため、照合を保留します")
        since = following


def match_problem(entries, submissions):
    """Newest first; finalized snapshots remain boundaries and consume their window."""
    entries = sorted(entries, key=lambda e: (e["at"], e["path"].name), reverse=True)
    submissions = sorted({int(s["id"]): s for s in submissions}.values(),
                         key=lambda s: (int(s["epoch_second"]), int(s["id"])), reverse=True)
    upper = float("inf")
    matches = []
    for entry in entries:
        candidates = [s for s in submissions if entry["at"] <= int(s["epoch_second"]) < upper]
        upper = entry["at"]
        if entry["verdict"] or not candidates:
            continue
        if len(candidates) != 1:
            print("[保留] 複数提出が同じ保存区間にあります: " + entry["path"].name, flush=True)
            continue
        sub = candidates[0]
        if sub.get("result") in FINAL:
            matches.append((entry, sub["result"]))
    return matches


def finalize(path, verdict):
    if verdict == "AC" and re.search(r"(?m)^\s*#\+", path.read_text(encoding="utf-8")):
        verdict = "AC+"
    target = path.with_name(path.stem + "_" + verdict + ".nim")
    if target.exists():
        raise RuntimeError("確定先がすでに存在します: " + target.name)
    path.rename(target)
    print("[archive] " + target.name, flush=True)
    return target


def sync_once(root):
    with locked(root, "verdict-sync") as acquired:
        if not acquired:
            print("[INFO] 別プロセスが採点回収中です", flush=True)
            return
        try:
            remove_legacy_receipts(root)
            entries = scan(root)
            pending = [e for e in entries if not e["verdict"]]
            if not pending:
                return
            subs = fetch_all(username(root), min(e["at"] for e in pending))
            for problem in sorted({e["problem"] for e in pending}):
                api_id = task_id(root, problem)
                remote = [s for s in subs if s.get("problem_id") == api_id
                          and re.match(r"^Nim(?:\s|$)", s.get("language", ""))]
                local = [e for e in entries if e["problem"] == problem]
                for entry, verdict in match_problem(local, remote):
                    finalize(entry["path"], verdict)
        finally:
            # Also rate-limit separately invoked sync processes.
            time.sleep(max(0, 2 - (time.monotonic() - LAST_REQUEST)))


def watch(root, interval, delay):
    with locked(root, "verdict-watch") as acquired:
        if not acquired:
            return
        time.sleep(delay)
        while True:
            try:
                sync_once(root)
            except Exception as exc:
                print("[WARN] 採点回収を次回へ保留: " + str(exc), file=sys.stderr, flush=True)
            time.sleep(interval)


def start_watcher(root):
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "watch",
        "--interval", "30", "--initial-delay", "30"], cwd=root,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True, close_fds=True)


def work_source(root, value):
    work = root / "work"
    source = Path(value)
    source = (source if source.is_absolute() else root / source).resolve(strict=True)
    if work.is_symlink() or source.parent != work.resolve() or source.suffix != ".nim":
        raise RuntimeError("対象はwork直下のNimファイルに限ります")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", source.stem):
        raise RuntimeError("問題ファイル名が不正です")
    return source


def make_command(root, args, target, source, url):
    return shlex.split(args.make) + ["-s", "--no-print-directory", "-C", str(root), target,
        "FILE=" + str(source), "URL=" + url, "NIM=" + args.nim,
        "OJ=" + args.oj, "TL=" + args.tl, "ML=" + args.ml]


def submit(root, args):
    username(root)
    source = work_source(root, args.file)
    url = subprocess.check_output(make_command(root, args, "print-url", source, args.url), text=True).strip()
    if not re.fullmatch(r"https://atcoder\.jp/contests/[^/]+/tasks/[^/]+", url):
        raise RuntimeError("print-urlがAtCoder問題URLを返しませんでした")
    # Hex-only temporary basename preserves Nim identifiers and relative include paths.
    frozen = source.parent / ("cpfreeze" + secrets.token_hex(8) + ".nim")
    fd = os.open(frozen, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(source.read_bytes())
        subprocess.run(make_command(root, args, "submit-check", frozen, url), check=True)
        archive = root / "archive"
        archive.mkdir(exist_ok=True)
        stamp = dt.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        if list(archive.glob(source.stem + "_" + stamp + "*.nim")):
            raise RuntimeError("同じ秒の保存が存在します。上書きしません")
        snapshot = archive / (source.stem + "_" + stamp + ".nim")
        with snapshot.open("xb") as handle:
            handle.write(frozen.read_bytes())
        subprocess.run(["bash", str(root / "bundle.sh"), str(root), str(snapshot)], check=True)
        start_watcher(root)
        result = subprocess.run(shlex.split(args.oj) + ["s", url, str(root / "bundled.txt"),
            "-l", "6072", "-w", "0", "-y", "--print-url"], text=True, stdout=subprocess.PIPE)
        print(result.stdout or "", end="", flush=True)
        urls = SUB_URL.findall(result.stdout or "")
        if urls:
            subprocess.run(["bash", str(root / "publish-open-url.sh"), urls[-1]], check=False)
        else:
            print("[INFO] 自動提出を確認できません。まずサイトの提出履歴を確認してください。")
            print("[INFO] 未提出ならbundled.txtを手動提出してください。採点監視は継続します。")
            payload = (root / "bundled.txt").read_bytes()
            if os.environ.get("TMUX"):
                subprocess.run(["tmux", "load-buffer", "-w", "-"], input=payload, check=False)
            else:
                print("\033]52;c;" + base64.b64encode(payload).decode() + "\a", end="", flush=True)
    finally:
        frozen.unlink(missing_ok=True)


def promote(root, value):
    source = work_source(root, value)
    archive = root / "archive"
    archive.mkdir(exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".promote-", dir=archive)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(source.read_bytes())
        os.replace(name, archive / source.name)
    finally:
        Path(name).unlink(missing_ok=True)
    print("[promote] " + source.name)


def clear(root):
    work = root / "work"
    if work.is_symlink():
        raise RuntimeError("workのシンボリックリンクは許可しません")
    work.mkdir(exist_ok=True)
    for item in work.iterdir():
        if item.is_dir() and not item.is_symlink():
            shutil.rmtree(item)
        else:
            item.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["submit", "sync", "watch", "promote", "all-clear"])
    for flag, default in [("file", ""), ("url", ""), ("make", "make"), ("oj", "oj"),
                          ("nim", "nim"), ("tl", "2000"), ("ml", "1024")]:
        parser.add_argument("--" + flag, default=default)
    # Compatibility only: the existing Makefile passes these empty/unused options.
    parser.add_argument("--wait", type=float, default=0, help=argparse.SUPPRESS)
    parser.add_argument("--snapshot", default="", help=argparse.SUPPRESS)
    parser.add_argument("--submission-url", default="", help=argparse.SUPPRESS)
    parser.add_argument("--interval", type=float, default=30)
    parser.add_argument("--initial-delay", type=float, default=0)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.command == "watch":
        watch(root, max(30, args.interval), max(0, args.initial_delay))
    elif args.command == "sync":
        start_watcher(root)
        sync_once(root)
    else:
        with locked(root, "operation") as acquired:
            if not acquired:
                raise RuntimeError("別の提出・Promote・全消去処理が実行中です")
            if args.command == "submit":
                submit(root, args)
            elif args.command == "promote":
                promote(root, args.file)
            else:
                clear(root)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as exc:
        print("[ERROR] " + str(exc), file=sys.stderr)
        raise SystemExit(1)