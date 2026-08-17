#!/usr/bin/env bash

# パイプ途中も含めて失敗、未定義変数を検出
set -euo pipefail

# setup.sh 自身がある atcoder-nim-env を基準
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

fix_ownership() {
  local target_path="$1"
  local target_user
  local target_group

  target_user="$(id -un)"
  target_group="$(id -gn)"

  find "$target_path" \
    \( ! -user "$target_user" -o ! -group "$target_group" \) \
    -exec sudo chown "$target_user:$target_group" {} +
}

# 古い root 実行の残骸があれば、AtCoder 環境の管理対象だけ所有者を戻す
fix_ownership "$SCRIPT_DIR"

# cp-nim-lib / cp-solved-log / nim-acl を取得（既存なら pull）
for repo in cp-nim-lib cp-solved-log nim-acl; do
  dir="../${repo}"
  if [ -d "${dir}/.git" ]; then
    echo "${repo}: already exists, pulling..."
    fix_ownership "$dir"
    git -C "$dir" pull --ff-only
  else
    git clone "https://github.com/sukenori/${repo}.git" "$dir"
  fi
done

# 作業ディレクトリを作る
mkdir -p ./work
mkdir -p ./test

# bundle.sh はホストから直接使うため、実行可能にする
[ -f ./bundle.sh ] && chmod +x ./bundle.sh

# attach / Android 用の nsenter 権限は現行機能として維持
if [ ! -f /etc/sudoers.d/nsenter ]; then
  echo "$(id -un) ALL=(root) NOPASSWD: /usr/bin/nsenter" \
    | sudo tee /etc/sudoers.d/nsenter > /dev/null
fi

# Android の make copy 専用 wrapper を root 所有で配置
# repository 内の user 書込み可能な script を、そのまま sudo 許可しない
WRAPPER_SRC="$SCRIPT_DIR/android/copy-bundled-host.sh"
WRAPPER_DST="/usr/local/sbin/atcoder-copy-bundled"
SUDOERS_FILE="/etc/sudoers.d/atcoder-copy-bundled"
CURRENT_USER="$(id -un)"
sudo install -o root -g root -m 0755 "$WRAPPER_SRC" "$WRAPPER_DST"
# "" は「引数なしでしか実行できない」という sudoers の指定。
sudo tee "$SUDOERS_FILE" > /dev/null <<EOF
${CURRENT_USER} ALL=(root) NOPASSWD: ${WRAPPER_DST} ""
EOF
sudo chmod 0440 "$SUDOERS_FILE"
sudo visudo -cf "$SUDOERS_FILE"

# ホスト user の数値 UID/GID を child image build に渡す
export DEV_UID="$(id -u)"
export DEV_GID="$(id -g)"

# container_name: atcoder-nim を維持した Compose を、host user として build / 起動する（sudo は通常環境変数を引き継がない）
sudo --preserve-env=DEV_UID,DEV_GID docker compose up -d --build atcoder-nim