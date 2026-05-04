#!/usr/bin/env bash

# パイプ途中も含めて失敗、未定義変数を検出
set -euo pipefail

# docker group に属していなければ sudo を使う
compose_cmd() {
  if groups | grep -q docker; then
    docker compose "$@"
  else
    sudo docker compose "$@"
  fi
}

compose_cmd up -d atcoder-nim
compose_cmd exec -it atcoder-nim zsh -l