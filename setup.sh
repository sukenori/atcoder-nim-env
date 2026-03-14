#!/usr/bin/env bash
# setup.sh — atcoder-nim-env のローカル開発環境を構築する
# 目的: 依存リポジトリと Docker コンテナを一度に整える
set -euo pipefail
# -e: 失敗したら止める
# -u: 未定義変数を禁止
# -o pipefail: パイプ途中の失敗も拾う

# このスクリプト自身のディレクトリを作業ルートにする
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 依存コマンドが使えるか確認する
if ! command -v git >/dev/null 2>&1; then
  echo "git が見つかりません。先に git をインストールしてください。" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker が見つかりません。先に Docker Engine をインストールしてください。" >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose が使えません。Docker Compose プラグインを確認してください。" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker デーモンに接続できません。権限不足の可能性があります。" >&2
  echo "以下を実行後に再ログインするか newgrp を実行してください。" >&2
  echo "  sudo usermod -aG docker \"$USER\"" >&2
  echo "  newgrp docker" >&2
  exit 1
fi

ensure_repo() {
  local url="$1"
  local dir="$2"
  local current_url

  if [ -d "$dir/.git" ]; then
    if git -C "$dir" remote get-url origin >/dev/null 2>&1; then
      current_url="$(git -C "$dir" remote get-url origin)"
      if [ "$current_url" != "$url" ]; then
        git -C "$dir" remote set-url origin "$url"
      fi
    else
      git -C "$dir" remote add origin "$url"
    fi

    if ! git -C "$dir" ls-remote --exit-code --heads origin >/dev/null 2>&1; then
      echo "$dir の origin にブランチがないため pull をスキップします。" >&2
      return
    fi

    git -C "$dir" pull --ff-only
    return
  fi

  if [ -e "$dir" ]; then
    echo "$dir が既に存在しますが Git リポジトリではないため中断します。" >&2
    return 1
  fi

  git clone "$url" "$dir"
}

ensure_repo "https://github.com/sukenori/cp-nim-lib.git" "${PARENT_DIR}/cp-nim-lib"
ensure_repo "https://github.com/sukenori/cp-solved-log.git" "${PARENT_DIR}/cp-solved-log"

# 開発コンテナをビルドして起動する
docker compose up -d --build atcoder-nim


# 作業ディレクトリを作る
mkdir -p ./work
mkdir -p ./test

# 補助スクリプトの実行権限を整える
[ -f ./bundle.sh ] && chmod +x ./bundle.sh
