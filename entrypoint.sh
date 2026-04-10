#!/usr/bin/env bash
# atcoder-nim-env 専用の短縮パスを用意する（/work, /test）

# 環境変数 ATCODER_NIM_ENV_DIR が設定されていればその値を、未設定なら /home/sukenori/atcoder-nim-env をデフォルト値として PROJECT_DIR に代入
PROJECT_DIR="${ATCODER_NIM_ENV_DIR:-/home/sukenori/atcoder-nim-env}"

# 関数 ensure_symlink を定義
ensure_symlink() {
  # 第1引数と第2引数を代入
  local target="$1"
  local link_path="$2"
  # link_path がすでにシンボリックリンクである、またはそのパスに何も存在しない場合
  if [ -L "$link_path" ] || [ ! -e "$link_path" ]; then
    # -s でシンボリックリンクを作成、-f で既存のリンクを強制上書き、-n でリンク先がディレクトリでもリンク自体を置き換え
    ln -sfn "$target" "$link_path"
  else
    # link_path が通常ファイルまたは通常ディレクトリとして存在する場合は、上書きせず警告を stderr に出力
    echo "entrypoint: $link_path は通常ファイル／ディレクトリとして既に存在するため変更しません" >&2
  fi
}

# PROJECT_DIR が実際にディレクトリとして存在する場合のみ
if [ -d "$PROJECT_DIR" ]; then
  # $PROJECT_DIR/work と $PROJECT_DIR/test を作成（-p により親ディレクトリがなくてもエラーにならず、既存でも無視）
  mkdir -p "$PROJECT_DIR/work" "$PROJECT_DIR/test"
  # コンテナ内の /work → $PROJECT_DIR/work、/test → $PROJECT_DIR/test というシンボリックリンクを作成
  ensure_symlink "$PROJECT_DIR/work" /work
  ensure_symlink "$PROJECT_DIR/test" /test
fi

# 共通の dotfiles 初期化を実行して本来コマンドへ処理を引き継ぐ
exec /bin/bash /root/dotfiles/entrypoint.sh "$@"
