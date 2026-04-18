#!/usr/bin/env bash

# パイプ途中も含めて失敗、未定義変数を検出
set -euo pipefail

# cp-nim-lib と cp-solved-log を取得
git clone "https://github.com/sukenori/cp-nim-lib.git" "../cp-nim-lib"
git clone "https://github.com/sukenori/cp-solved-log.git" "../cp-solved-log"

# 作業ディレクトリを作る
mkdir -p ./work
mkdir -p ./test

# bundle スクリプトに実行権限を付与
[ -f ./bundle.sh ] && chmod +x ./bundle.sh

# 開発コンテナをビルドして起動する
sudo docker compose up -d --build atcoder-nim