#!/usr/bin/env bash

# atcoder-nim-env 専用の短縮パスを用意する（/work, /test）
PROJECT_DIR="${ATCODER_NIM_ENV_DIR:-/home/sukenori/atcoder-nim-env}"

ensure_symlink() {
  local target="$1"
  local link_path="$2"

  if [ -L "$link_path" ] || [ ! -e "$link_path" ]; then
    ln -sfn "$target" "$link_path"
  else
    echo "entrypoint: $link_path は通常ファイル/ディレクトリとして既に存在するため変更しません" >&2
  fi
}

if [ -d "$PROJECT_DIR" ]; then
  mkdir -p "$PROJECT_DIR/work" "$PROJECT_DIR/test"
  ensure_symlink "$PROJECT_DIR/work" /work
  ensure_symlink "$PROJECT_DIR/test" /test
fi

# 共通の dotfiles 初期化を実行して本来コマンドへ処理を引き継ぐ
exec /bin/bash /root/dotfiles/entrypoint.sh "$@"
