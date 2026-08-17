#!/usr/bin/env bash
set -euo pipefail

# この wrapper は引数を受け取らない
# 読み出せる対象を固定し、任意の docker command を許可しない

exec /usr/bin/docker exec \
  --user dev \
  atcoder-nim \
  /bin/cat \
  /workspace/atcoder-nim-env/bundled.txt