#!/usr/bin/env bash

# パイプ途中も含めて失敗、未定義変数を検出
set -euo pipefail

# 接続元の識別タグ（省略時は "pc"、Androidからは "mobile" を渡す）
DEVICE_TAG="${1:-pc}"

# docker-compose.yml のある場所へ移動（どこから呼ばれても動くようにするため）
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# atcoder-nim をバックグラウンドで起動（Docker daemon の操作は host root が行う）
sudo docker compose up -d atcoder-nim

# Ctrl+p のバッファ問題を避けるため、PTY（疑似端末）を新たに作らず、カーネルの名前空間に直接入る（Windows Terminal → WSL の PTY → コンテナのプロセス）
PID="$(sudo docker inspect --format '{{.State.Pid}}' atcoder-nim)"
# 起動する zsh 自体は、container 内 dev と同じ UID/GID に落とす
DEV_UID="$(id -u)"
DEV_GID="$(id -g)"
sudo nsenter -t "$PID" -m -u -i -n -p --setuid "$DEV_UID" --setgid "$DEV_GID" -- env DEVICE_TAG="$DEVICE_TAG" zsh -l
