#!/usr/bin/env bash

# パイプ途中も含めて失敗、未定義変数を検出
set -euo pipefail

# cp-nim-lib と cp-solved-log を取得（既存なら pull）
for repo in cp-nim-lib cp-solved-log; do
  dir="../${repo}"
  if [ -d "${dir}/.git" ]; then
    echo "${repo}: already exists, pulling..."
    git -C "${dir}" pull --ff-only
  else
    git clone "https://github.com/sukenori/${repo}.git" "${dir}"
  fi
done

# 作業ディレクトリを作る
mkdir -p ./work
mkdir -p ./test

# bundle スクリプトに実行権限を付与
[ -f ./bundle.sh ] && chmod +x ./bundle.sh

# nsenter を sudo なしで使えるよう設定
[ -f /etc/sudoers.d/nsenter ] || \
  echo "$USER ALL=(root) NOPASSWD: /usr/bin/nsenter" | sudo tee /etc/sudoers.d/nsenter

# 開発コンテナをビルドして起動する
sudo docker compose up -d --build atcoder-nim