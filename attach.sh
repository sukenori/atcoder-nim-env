#!/usr/bin/env bash

# パイプ途中も含めて失敗、未定義変数を検出
set -euo pipefail

docker compose up -d atcoder-nim
docker compose exec -it atcoder-nim zsh -l