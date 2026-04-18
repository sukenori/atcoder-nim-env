#!/bin/bash
# コンテナ内なので、このシェバンでよし

# 設定ファイルへのシンボリックリンク作成
# ln -s（link）で、シンボリックリンク、-f で上書き
ln -sf /home/sukenori/atcoder-nim-env/.zshrc.local /root/.zshrc.local

# docker-compose.yaml の command: の引数を、dotfiles/entrypoint.sh に渡す
exec /root/dotfiles/entrypoint.sh "$@"