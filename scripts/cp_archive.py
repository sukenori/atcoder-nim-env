#!/usr/bin/env python3
"""提出の保存・採点結果の回収・正解コードへの昇格・workの全消去を行う。

採点結果の記録場所は、隣の cp-solved-log のルートにあるファイル名だけ。
  abc212c_2026-11-04_18-34-36.nim     提出済み、採点結果待ち
  abc212c_2026-11-04_18-34-36_AC.nim  採点結果が確定した（AC+ は #+ コメントありのAC）
"""
# コマンドライン引数を読むための標準ライブラリ
import argparse
# 文字列を base64 に変換するためのライブラリ（端末のクリップボードに送るのに使う）
import base64
# 日時の計算に使うライブラリ
import datetime as dt
# 同時に複数の採点監視が動かないようにファイルロックをかけるためのライブラリ
import fcntl
# 提出履歴 API の応答（JSON）を読むためのライブラリ
import json
# 環境変数を読むためのライブラリ
import os
# ファイルの場所を扱いやすくするためのライブラリ
from pathlib import Path
# 正規表現のライブラリ（ファイル名や URL の判定に使う）
import re
# 文字列をコマンド引数に分割するためのライブラリ
import shlex
# ファイルのコピーや、フォルダごとの削除に使うライブラリ
import shutil
# 外部コマンド（make、oj、bash）を実行するためのライブラリ
import subprocess
# 終了コードやエラー出力に使うライブラリ
import sys
# 待ち時間を作るためのライブラリ
import time
# URL の組み立てと分解に使うライブラリ
import urllib.parse
# 提出履歴 API にアクセスするためのライブラリ
import urllib.request

# 採点結果として認める文字列の一覧
VERDICTS = {"AC", "WA", "TLE", "RE", "CE", "MLE", "OLE", "IE"}
# cp-solved-log のファイル名（問題名_日時 と、あれば _採点結果）を読み取る正規表現
NAME = re.compile(r"^([A-Za-z0-9_]+)_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})(?:_([A-Z]+\+?))?\.nim$")
# oj の出力から、提出結果ページの URL を取り出す正規表現
SUBMISSION_URL = re.compile(r"https://atcoder\.jp/contests/[^/\s]+/submissions/\d+")
# 採点監視が二重に動かないようにするためのロックファイルの場所
WATCH_LOCK = "/tmp/cp-solved-log-watch.lock"

# 保存先はプロジェクトの隣の cp-solved-log。提出・回収・昇格で同じ場所を使う
def archive_dir(root):
    return root.parent / "cp-solved-log"


def username(root):
    # 環境変数 ATCODER_USER があればそれを使う
    value = os.environ.get("ATCODER_USER", "").strip()
    # なければ、プロジェクト直下の .atcoder-user ファイルから読む
    if not value and (root / ".atcoder-user").exists():
        value = (root / ".atcoder-user").read_text().strip()
    # 英数字とアンダースコア以外が混じっていれば、設定漏れとしてエラーにする
    if not re.fullmatch(r"[A-Za-z0-9_]+", value):
        raise RuntimeError(".atcoder-user に AtCoder のユーザー名を書いてください")
    # ユーザー名を返す
    return value


def scan(root):
    # cp-solved-log 内の提出ファイルの情報を入れるリスト
    entries = []
    # cp-solved-log のルートにある .nim ファイルを 1 つずつ調べる
    for path in archive_dir(root).glob("*.nim"):
        # ファイル名が「問題名_日時(_採点結果)」の形か確認する
        match = NAME.fullmatch(path.name)
        # その形でないファイル（正解コード abc212c.nim など）は対象外
        if not match:
            continue
        # 問題名・日時・採点結果（なければ None）に分ける
        problem, stamp, verdict = match.groups()
        # 日時の文字列を、秒数（Unix 時刻）に変換する
        at = int(dt.datetime.strptime(stamp, "%Y-%m-%d_%H-%M-%S").timestamp())
        # 情報をまとめてリストに追加する
        entries.append({"problem": problem, "at": at, "verdict": verdict, "path": path})
    # 新しい順に並べて返す
    return sorted(entries, key=lambda e: e["at"], reverse=True)


def task_id(root, problem):
    # 既存の make print-url で、問題名（abc212c）から問題ページの URL を得る
    url = subprocess.check_output(["make", "-s", "--no-print-directory", "-C", str(root),
        "print-url", "FILE=work/" + problem + ".nim", "URL="], text=True).strip()
    # URL の末尾（abc212_c の部分）を取り出す
    match = re.search(r"/tasks/([^/]+)$", url)
    # 取り出せなければ問題名が解決できていない
    if not match:
        raise RuntimeError("問題 URL を解決できません: " + problem)
    # 提出履歴 API が使う問題 ID を返す
    return match.group(1)


def fetch_submissions(user, since):
    # 問題 ID ごとではなく、ユーザーの提出履歴をまとめて取る。id で重複を除くための辞書
    found = {}
    # API は 1 回に最大 500 件なので、続きがある間は繰り返す
    while True:
        # アクセスしすぎないよう、毎回 2 秒待つ
        time.sleep(2)
        # since（秒）以降の、このユーザーの提出を問い合わせる URL
        url = ("https://kenkoooo.com/atcoder/atcoder-api/v3/user/submissions?"
               + urllib.parse.urlencode({"user": user, "from_second": since}))
        # API に送るリクエスト（識別用の名前付き）
        request = urllib.request.Request(url, headers={"User-Agent": "cp-archive"})
        # 20 秒以内に応答が来るのを待って、JSON として読む
        with urllib.request.urlopen(request, timeout=20) as response:
            page = json.load(response)
        # 新しく見つかった提出の数を数えるため、追加前の件数を覚える
        before = len(found)
        # 取得した提出を id をキーにして保存する
        for sub in page:
            found[sub["id"]] = sub
        # 500 件未満、または新しい提出がなければ、全部取れたので終わる
        if len(page) < 500 or len(found) == before:
            return list(found.values())
        # 続きは、取れた中で最も新しい時刻から取る
        since = max(sub["epoch_second"] for sub in page)


def match_problem(entries, submissions):
    # 保存ファイルを新しい順に並べる
    entries = sorted(entries, key=lambda e: e["at"], reverse=True)
    # AtCoder の提出も新しい順に並べる
    submissions = sorted(submissions, key=lambda s: (s["epoch_second"], s["id"]), reverse=True)
    # 1 つ新しい保存ファイルの時刻。最初はそれより新しいものが無いので無限大
    upper = float("inf")
    # (ファイル, 採点結果) の組を入れるリスト
    matches = []
    # 保存ファイルを新しい順に 1 つずつ見る
    for entry in entries:
        # 「この保存より後、次の保存より前」に提出された履歴が、このファイルの提出
        candidates = [s for s in submissions if entry["at"] <= s["epoch_second"] < upper]
        # 次のファイルのために、区間の上限をこのファイルの時刻に更新する
        upper = entry["at"]
        # すでに採点結果が付いている、または対応する提出がなければ何もしない
        if entry["verdict"] or not candidates:
            continue
        # 提出が複数あって 1 つに決められないときは、間違えないよう保留する
        if len(candidates) != 1:
            print("[保留] 同じ区間に複数の提出があります: " + entry["path"].name, flush=True)
            continue
        # 採点が終わっている（待機中でない）ときだけ結果を採用する
        if candidates[0].get("result") in VERDICTS:
            matches.append((entry, candidates[0]["result"]))
    # 対応が決まったものを返す
    return matches


def finalize(path, verdict):
    # AC のコードに #+ コメントがあれば、助けを得たACとして AC+ にする
    if verdict == "AC" and re.search(r"(?m)^\s*#\+", path.read_text(encoding="utf-8")):
        verdict = "AC+"
    # 拡張子の前に採点結果を付けた新しいファイル名にする
    target = path.with_name(path.stem + "_" + verdict + ".nim")
    # ファイル名を変更する
    path.rename(target)
    # 変更したことを表示する
    print("[archive] " + target.name, flush=True)


def sync_once(root):
    # cp-solved-log の全提出ファイルを調べる
    entries = scan(root)
    # 採点結果がまだ付いていないファイルだけを取り出す
    pending = [e for e in entries if not e["verdict"]]
    # 待ちが無ければ、API には問い合わせずに終わる
    if not pending:
        return
    # 一番古い待ちファイルの時刻以降の提出履歴を取得する
    submissions = fetch_submissions(username(root), min(e["at"] for e in pending))
    # 待ちがある問題ごとに処理する
    for problem in sorted({e["problem"] for e in pending}):
        # ローカルの問題名を、API の問題 ID（abc212_c の形）に変換する
        api_id = task_id(root, problem)
        # その問題で、言語が Nim の提出だけを残す
        remote = [s for s in submissions if s.get("problem_id") == api_id
                  and s.get("language", "").startswith("Nim")]
        # その問題の保存ファイルだけを取り出す
        local = [e for e in entries if e["problem"] == problem]
        # 時刻で対応付けて、決まったものからファイル名を変更する
        for entry, verdict in match_problem(local, remote):
            finalize(entry["path"], verdict)


def watch(root, interval, delay):
    # 監視が二重に動かないよう、ロックファイルを開く
    with open(WATCH_LOCK, "a") as lock:
        # すでに別の監視が動いていれば、何もせず終わる
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        # 提出直後は AtCoder Problems に反映されないので、最初に少し待つ
        time.sleep(delay)
        # 以後は一定間隔で、採点結果を回収し続ける
        while True:
            # 通信エラーなどが起きても監視は止めず、次回に回す
            try:
                sync_once(root)
            except Exception as exc:
                print("[WARN] 次回に持ち越し: " + str(exc), file=sys.stderr, flush=True)
            # 次の回収まで待つ
            time.sleep(interval)


def start_watcher(root):
    # 自分自身を watch コマンドで、画面とは切り離したバックグラウンドで起動する
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "watch"], cwd=root,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True)


def work_source(root, value):
    # 相対パスなら、プロジェクト直下からのパスとして絶対パスにする
    source = Path(value)
    source = source if source.is_absolute() else root / source
    # work フォルダ直下の .nim ファイルだけを対象にする
    if source.parent.resolve() != (root / "work").resolve() or source.suffix != ".nim":
        raise RuntimeError("対象は work 直下の .nim ファイルです")
    # 絶対パスを返す
    return source.resolve()


def make_command(root, args, target, source, url):
    # make を呼び出すコマンド。Makefile から受け取った設定をそのまま渡す
    return shlex.split(args.make) + ["-s", "--no-print-directory", "-C", str(root), target,
        "FILE=" + str(source), "URL=" + url, "NIM=" + args.nim,
        "OJ=" + args.oj, "TL=" + args.tl, "ML=" + args.ml]


def submit(root, args):
    # 採点回収に必要なユーザー名が設定済みか、最初に確認する
    username(root)
    # 提出する work のファイルを決める
    source = work_source(root, args.file)
    # 問題ページの URL を、既存の make print-url で得る
    url = subprocess.check_output(make_command(root, args, "print-url", source, args.url),
                                  text=True).strip()
    # サンプルテスト・ランダムテストなどの提出前チェックを行う。失敗すればここで止まる
    subprocess.run(make_command(root, args, "submit-check", source, url), check=True)
    # 保存先の cp-solved-log フォルダがなければ作る
    archive = archive_dir(root)
    archive.mkdir(exist_ok=True)
    # 現在時刻（コンテナの時刻 = 日本時間）を、ファイル名用の文字列にする
    stamp = dt.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    # 提出時点のコードの保存先（まだ採点結果は付かない）
    snapshot = archive / (source.stem + "_" + stamp + ".nim")
    # work のコードを、そのまま cp-solved-log のルートに複製する
    shutil.copyfile(source, snapshot)
    # 保存したコードを、提出用の 1 ファイル（bundled.txt）にまとめる
    subprocess.run(["bash", str(root / "bundle.sh"), str(root), str(snapshot)], check=True)
    # 採点結果を回収する監視を、バックグラウンドで始める
    start_watcher(root)
    # oj で自動提出する（ログインできない時間帯は失敗するが、それは異常ではない）
    result = subprocess.run(shlex.split(args.oj) + ["s", url, str(root / "bundled.txt"),
        "-l", "6072", "-w", "0", "-y", "--print-url"], text=True, stdout=subprocess.PIPE)
    # oj の出力を画面に表示する
    print(result.stdout or "", end="", flush=True)
    # 出力から提出結果ページの URL を探す
    urls = SUBMISSION_URL.findall(result.stdout or "")
    # 自動提出できていれば、その結果ページをブラウザで開く
    if urls:
        subprocess.run(["bash", str(root / "publish-open-url.sh"), urls[-1]], check=False)
        return
    # 自動提出できなかったときは、手動で貼り付ける案内を表示する
    print("[INFO] 自動提出できませんでした。bundled.txt をサイトに貼り付けて提出してください。")
    print("[INFO] 採点結果は、提出後に自動でファイル名へ反映されます。")
    # 貼り付けやすいよう、bundled.txt の中身をクリップボードに送る
    payload = (root / "bundled.txt").read_bytes()
    if os.environ.get("TMUX"):
        # tmux の中なら、tmux 経由でクリップボードに送る
        subprocess.run(["tmux", "load-buffer", "-w", "-"], input=payload, check=False)
    else:
        # tmux の外なら、端末の OSC52 という仕組みでクリップボードに送る
        print("\033]52;c;" + base64.b64encode(payload).decode() + "\a", end="", flush=True)


def promote(root, value):
    # 昇格する work のファイルを決める
    source = work_source(root, value)
    # cp-solved-log フォルダがなければ作る
    archive_dir(root).mkdir(exist_ok=True)
    # 時刻なしの名前（abc212c.nim）で複製する。すでにあれば上書きする
    shutil.copyfile(source, archive_dir(root) / source.name)
    # 昇格したことを表示する
    print("[promote] " + source.name)


def clear(root):
    # work フォルダがなければ作る
    (root / "work").mkdir(exist_ok=True)
    # work の中身を 1 つずつ確認なしで削除する
    for item in (root / "work").iterdir():
        # フォルダなら中身ごと削除する
        if item.is_dir() and not item.is_symlink():
            shutil.rmtree(item)
        # ファイルならそのまま削除する
        else:
            item.unlink()


def main():
    # コマンドライン引数の定義を作る
    parser = argparse.ArgumentParser()
    # 実行する動作を 1 つ選ぶ
    parser.add_argument("command", choices=["submit", "sync", "watch", "promote", "all-clear"])
    # Makefile から渡される設定（既定値つき）を受け取る
    for flag, default in [("file", ""), ("url", ""), ("make", "make"), ("oj", "oj"),
                          ("nim", "nim"), ("tl", "2000"), ("ml", "1024")]:
        parser.add_argument("--" + flag, default=default)
    # Makefile が渡すが、もう使わない古い引数は読み捨てる
    args, _ = parser.parse_known_args()
    # このファイルの 2 つ上のフォルダ（scripts の親）がプロジェクト直下
    root = Path(__file__).resolve().parent.parent
    # 採点監視（バックグラウンド用）。30 秒ごとに回収し、最初は 30 秒待つ
    if args.command == "watch":
        watch(root, 30, 30)
    # 手動の採点回収。監視も起動して、今すぐ 1 回回収する
    elif args.command == "sync":
        start_watcher(root)
        sync_once(root)
    # 提出
    elif args.command == "submit":
        submit(root, args)
    # 正解コードへの昇格
    elif args.command == "promote":
        promote(root, args.file)
    # work の全消去
    else:
        clear(root)


# このファイルを直接実行したときだけ main を動かす
if __name__ == "__main__":
    # 失敗時は短いメッセージだけ出して終了する
    try:
        main()
    except Exception as exc:
        print("[ERROR] " + str(exc), file=sys.stderr)
        raise SystemExit(1)
