#!/usr/bin/env python3
"""Submission snapshots and verdict finalization; Python standard library only."""
import argparse
import contextlib
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request

FINAL = {"AC", "WA", "TLE", "RE", "CE", "MLE", "OLE", "IE"}
URL_RE = re.compile(r"https://atcoder\.jp/contests/[^/\s]+/submissions/(\d+)")
SNAP_RE = re.compile(r"^[A-Za-z0-9_]+_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.nim$")


def username(root):
    value = os.environ.get("ATCODER_USER", "").strip()
    if not value:
        p = root / ".atcoder-user"
        value = p.read_text().strip() if p.exists() else ""
    if not re.fullmatch(r"[A-Za-z0-9_]+", value):
        raise RuntimeError("setup.shでAtCoderユーザー名を設定してください")
    return value


@contextlib.contextmanager
def lock(root):
    state = root / ".cp-state"
    state.mkdir(exist_ok=True)
    with (state / "operation.lock").open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("提出・判定回収・Promote・all-clearの別処理が実行中です")
        yield


def atomic_json(path, data):
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as handle:
        json.dump(data, handle)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def work_source(root, value):
    source = Path(value)
    if not source.is_absolute():
        source = root / source
    source = source.resolve(strict=True)
    work = root / "work"
    if work.is_symlink():
        raise RuntimeError("workのシンボリックリンクは許可しません")
    if source.parent != work.resolve() or source.suffix != ".nim":
        raise RuntimeError("対象はwork直下のNimファイルに限ります")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", source.stem):
        raise RuntimeError("問題ファイル名が不正です")
    return source


def create_snapshot(root, source, content=None):
    archive = root / "archive"
    archive.mkdir(exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    name = f"{source.stem}_{stamp}.nim"
    path = archive / name
    if list(archive.glob(f"{source.stem}_{stamp}*.nim")):
        raise RuntimeError("同じ秒のスナップショットが存在します。少し待って再実行してください")
    with path.open("xb") as handle:
        handle.write(source.read_bytes() if content is None else content)
        handle.flush()
        os.fsync(handle.fileno())
    return path


def finalize(snapshot, verdict):
    if verdict not in FINAL:
        return None
    source = snapshot.read_text(encoding="utf-8")
    if verdict == "AC" and re.search(r"(?m)^\s*#\+", source):
        verdict = "AC+"
    target = snapshot.with_name(f"{snapshot.stem}_{verdict}.nim")
    # Hard link + unlink avoids overwriting an existing result file.
    os.link(snapshot, target)
    snapshot.unlink()
    return target


def fetch_results(user, since):
    query = urllib.parse.urlencode({"user": user, "from_second": since})
    url = "https://kenkoooo.com/atcoder/atcoder-api/v3/user/submissions?" + query
    request = urllib.request.Request(url, headers={"User-Agent": "cp-archive/1.0"})
    with urllib.request.urlopen(request, timeout=15) as response:
        results = json.load(response)
    if not isinstance(results, list):
        raise RuntimeError("提出履歴APIが配列を返しませんでした")
    return results


def sync_once(root):
    receipts = sorted((root / "archive").glob("*.nim.pending.json"))
    if not receipts:
        return 0
    user = username(root)
    waiting = []
    for receipt in receipts:
        data = json.loads(receipt.read_text())
        snapshot = receipt.with_name(receipt.name.removesuffix(".pending.json"))
        if not snapshot.exists():
            # Recover interruption between final rename and receipt removal.
            if any(snapshot.parent.glob(snapshot.stem + "_*.nim")):
                receipt.unlink()
            continue
        if data.get("submission_id") is not None:
            waiting.append((receipt, snapshot, data))
    if not waiting:
        return len(receipts)
    since = min(item[2]["from_second"] for item in waiting)
    submissions = {}
    while True:
        page = fetch_results(user, since)
        for item in page:
            submissions[int(item["id"])] = item
        wanted = {item[2]["submission_id"] for item in waiting}
        if wanted.issubset(submissions) or not page:
            break
        following = max(int(item["epoch_second"]) for item in page) + 1
        if following <= since:
            break
        since = following
        time.sleep(2)
    for receipt, snapshot, data in waiting:
        item = submissions.get(data["submission_id"])
        if not item:
            continue
        if item["problem_id"] != data["task_id"]:
            raise RuntimeError("提出IDと問題IDが一致しません: " + str(data["submission_id"]))
        if item.get("result") not in FINAL:
            continue
        target = finalize(snapshot, item["result"])
        receipt.unlink()
        print("[archive] " + target.name, flush=True)
    return len(list((root / "archive").glob("*.nim.pending.json")))


def wait_results(root, seconds):
    deadline = time.monotonic() + seconds
    while True:
        try:
            remaining = sync_once(root)
        except Exception as exc:
            print("[WARN] 判定回収を保留: " + str(exc), file=sys.stderr)
            remaining = 1
        if not remaining:
            return
        if time.monotonic() >= deadline:
            print("[INFO] 採点待ちは非表示です。後で make archive-sync を実行してください")
            return
        time.sleep(min(10, max(0, deadline - time.monotonic())))


def make_command(root, args, target, source, url):
    return shlex.split(args.make) + ["-s", "--no-print-directory", "-C", str(root),
        target, "FILE=" + str(source), "URL=" + url,
        "NIM=" + args.nim, "OJ=" + args.oj, "TL=" + args.tl, "ML=" + args.ml]


def submit(root, args):
    username(root)  # Reject missing configuration before any submission.
    source = work_source(root, args.file)
    url = subprocess.check_output(make_command(root, args, "print-url", source, args.url),
                                  text=True).strip()
    parsed = urllib.parse.urlparse(url)
    task = re.fullmatch(r"/contests/[^/]+/tasks/([^/]+)", parsed.path)
    if parsed.scheme != "https" or parsed.netloc != "atcoder.jp" or not task:
        raise RuntimeError("print-urlがAtCoder問題URLを返しませんでした")
    # Freeze source in the same directory to preserve relative include resolution.
    fd, frozen_name = tempfile.mkstemp(prefix="cpfreeze", suffix=".nim", dir=source.parent)
    frozen = Path(frozen_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(source.read_bytes())
        subprocess.run(make_command(root, args, "submit-check", frozen, url), check=True)
        # Archive keeps the original problem name, never the temporary name.
        snapshot = create_snapshot(root, source, frozen.read_bytes())
        receipt = snapshot.with_name(snapshot.name + ".pending.json")
        data = {"submission_id": None, "from_second": max(0, int(time.time()) - 60),
                "task_id": task.group(1)}
        atomic_json(receipt, data)
        subprocess.run(["bash", str(root / "bundle.sh"), str(root), str(snapshot)], check=True)
        result = subprocess.run(shlex.split(args.oj) + ["s", url, str(root / "bundled.txt"),
            "-l", "6072", "-w", "0", "-y", "--print-url"],
            text=True, stdout=subprocess.PIPE)
        output = result.stdout or ""
        print(output, end="", flush=True)
        matches = URL_RE.findall(output)
        if matches:
            data["submission_id"] = int(matches[-1])
            atomic_json(receipt, data)
            submission_url = URL_RE.search(output).group(0)
            try:
                subprocess.run(["bash", str(root / "publish-open-url.sh"), submission_url], check=False)
            except OSError as exc:
                print("[WARN] 提出済みですがブラウザ起動に失敗: " + str(exc), file=sys.stderr)
        else:
            raise RuntimeError("提出IDを取得できませんでした。再提出せず提出履歴を確認し、"
                "make archive-sync SNAPSHOT=" + str(snapshot) + " SUBMISSION_URL=<提出URL> で紐付けてください")
        if result.returncode:
            print("[WARN] ojは異常終了しましたが提出IDを取得済みです。再提出しないでください",
                  file=sys.stderr)
        wait_results(root, args.wait)
    finally:
        frozen.unlink(missing_ok=True)


def promote(root, value):
    source = work_source(root, value)
    archive = root / "archive"
    archive.mkdir(exist_ok=True)
    target = archive / source.name
    fd, name = tempfile.mkstemp(prefix=".promote-", dir=archive)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(source.read_bytes())
        os.replace(name, target)
    finally:
        Path(name).unlink(missing_ok=True)
    print("[promote] " + target.name)


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
    parser.add_argument("command", choices=["submit", "sync", "promote", "all-clear"])
    parser.add_argument("--file", default="")
    parser.add_argument("--url", default="")
    parser.add_argument("--make", default="make")
    parser.add_argument("--oj", default="oj")
    parser.add_argument("--nim", default="nim")
    parser.add_argument("--tl", default="2000")
    parser.add_argument("--ml", default="1024")
    parser.add_argument("--wait", type=float, default=0)
    parser.add_argument("--snapshot", default="")
    parser.add_argument("--submission-url", default="")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with lock(root):
        if args.command == "submit":
            submit(root, args)
        elif args.command == "promote":
            promote(root, args.file)
        elif args.command == "all-clear":
            clear(root)
        else:
            if args.snapshot or args.submission_url:
                snapshot = Path(args.snapshot).resolve(strict=True)
                if snapshot.parent != root / "archive" or not SNAP_RE.fullmatch(snapshot.name):
                    raise RuntimeError("採点待ちarchiveファイルを指定してください")
                match = URL_RE.fullmatch(args.submission_url)
                if not match:
                    raise RuntimeError("提出URLが不正です")
                receipt = snapshot.with_name(snapshot.name + ".pending.json")
                data = json.loads(receipt.read_text())
                data["submission_id"] = int(match.group(1))
                atomic_json(receipt, data)
            wait_results(root, args.wait)


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as exc:
        print("[ERROR] " + str(exc), file=sys.stderr)
        raise SystemExit(1)