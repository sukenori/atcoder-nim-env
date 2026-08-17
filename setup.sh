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

CURRENT_USER="$(id -un)"

echo "${CURRENT_USER} ALL=(root) NOPASSWD: /usr/bin/nsenter" \
  | sudo tee /etc/sudoers.d/nsenter > /dev/null
sudo chmod 0440 /etc/sudoers.d/nsenter

# attach.sh が使う compose up / inspect も NOPASSWD 化する
{
  echo "${CURRENT_USER} ALL=(root) NOPASSWD:SETENV: /usr/bin/docker compose up -d atcoder-nim"
  echo "${CURRENT_USER} ALL=(root) NOPASSWD: /usr/bin/docker inspect --format {{.State.Pid}} atcoder-nim"
} | sudo tee /etc/sudoers.d/atcoder-attach > /dev/null
sudo chmod 0440 /etc/sudoers.d/atcoder-attach

echo "${CURRENT_USER} ALL=(root) NOPASSWD: /usr/bin/docker exec --user dev atcoder-nim /bin/cat /workspace/atcoder-nim-env/bundled.txt" \
  | sudo tee /etc/sudoers.d/atcoder-copy-bundled > /dev/null
sudo chmod 0440 /etc/sudoers.d/atcoder-copy-bundled

# ホスト user の数値 UID/GID を child image build に渡す
export DEV_UID="$(id -u)"
export DEV_GID="$(id -g)"

# container_name: atcoder-nim を維持した Compose を、host user として build / 起動する（sudo は通常環境変数を引き継がない）
sudo --preserve-env=DEV_UID,DEV_GID docker compose up -d --build atcoder-nim