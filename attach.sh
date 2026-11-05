#!/usr/bin/env bash
# コンテナを起動し、その中に直接入る(Windows Terminal や Android の Termux から呼ぶ)
# 使い方: attach.sh [端末の名前(省略時は pc、Android は mobile)] [tmux を使わないなら何か文字を渡す]

# エラー、未定義の変数、パイプの途中の失敗があれば、そこで止める
set -euo pipefail

# 接続元の端末の名前(pc か mobile)
DEVICE_TAG="${1:-pc}"
# 空でなければ、tmux を使わずにコンテナへ入る
NO_TMUX="${2:-}"

# docker-compose.yaml のある場所(このスクリプトのあるフォルダ)へ移動する。どこから呼ばれても動くようにするため
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# コンテナ内のユーザーを今のユーザーと同じ UID と GID にするため、docker compose に渡す
export DEV_UID="$(id -u)"
export DEV_GID="$(id -g)"

# コンテナを起動する(sudo は環境変数を引き継がないので、--preserve-env で渡す)
sudo --preserve-env=DEV_UID,DEV_GID docker compose up -d atcoder-nim

# コンテナのプロセス番号を調べる
PID="$(sudo docker inspect --format '{{.State.Pid}}' atcoder-nim)"
# 新しい疑似端末を作らず、コンテナの名前空間に直接入る(Ctrl+p のバッファの問題を避けるため)
sudo nsenter -t "$PID" -m -u -i -n -p --setuid "$DEV_UID" --setgid "$DEV_GID" -- \
  env HOME=/home/dev TZ=Asia/Tokyo DEVICE_TAG="$DEVICE_TAG" NO_TMUX="$NO_TMUX" \
  bash -lc 'cd /workspace/atcoder-nim-env && exec zsh -l'
