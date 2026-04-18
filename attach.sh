#!/usr/bin/env bash

# パイプ途中も含めて失敗、未定義変数を検出
set -euo pipefail

# docker compose 実行は、可能なら sudo なしを優先し、必要時だけ sudo を使う。
compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    sudo docker compose "$@"
  fi
}

compose_cmd up -d atcoder-nim
compose_cmd exec -it atcoder-nim zsh -l