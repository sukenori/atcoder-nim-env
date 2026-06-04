#!/usr/bin/env bash

# パイプ途中も含めて失敗、未定義変数を検出
set -euo pipefail

# atcoder-nim をバックグラウンドで起動（docker group に属していなければ sudo を使う）
compose_cmd() {
  if groups | grep -q docker; then
    docker compose "$@"
  else
    sudo docker compose "$@"
  fi
}
compose_cmd up -d atcoder-nim

# Ctrl+p のバッファ問題を避けるため、PTY（疑似端末）を新たに作らず、カーネルの名前空間に直接入る（Windows Terminal → WSL の PTY → コンテナのプロセス）
PID=$(docker inspect --format '{{.State.Pid}}' atcoder-nim)
sudo nsenter -t "$PID" -m -u -i -n -p -- zsh -l