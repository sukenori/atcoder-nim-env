#!/bin/bash
# コンテナの起動時に最初に実行される(docker-compose.yaml の entrypoint)

# エラー、未定義の変数、パイプの途中の失敗があれば、そこで止める
set -euo pipefail

# このプロジェクト専用の zsh 設定を、dev ユーザーのホームから読めるようにリンクを張る
ln -sfn /workspace/atcoder-nim-env/.zshrc.local "$HOME/.zshrc.local"

# Nim が nim-acl と cp-nim-lib を探しに行く場所を設定する
cat > /workspace/nim.cfg <<'EOF2'
--path:"/workspace/nim-acl"
--path:"/workspace/cp-nim-lib"
EOF2

# docker-compose.yaml の command(sleep infinity)を、dotfiles 側の entrypoint.sh に渡して引き継ぐ
exec /bin/bash /opt/dotfiles/entrypoint.sh "$@"
