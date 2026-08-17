#!/bin/bash
# コンテナ内なので、このシェバンでよし
set -euo pipefail

# workspace 内の AtCoder 専用 zsh 設定を dev の home に反映
ln -sfn /workspace/atcoder-nim-env/.zshrc.local "$HOME/.zshrc.local"

# docker-compose.yaml の command: の引数を、dotfiles/entrypoint.sh に渡す
exec /opt/dotfiles/entrypoint.sh "$@"