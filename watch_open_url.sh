#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_DIR="${SCRIPT_DIR}/.runtime/open-url"
LOCK_FILE="${QUEUE_DIR}/.watch.lock"

# Termux (Android) への接続設定。~/.ssh/config に別名を用意しておくか、
# 環境変数で上書きしてください。
MOBILE_SSH_HOST="${MOBILE_SSH_HOST:-mobile}"
MOBILE_SSH_PORT="${MOBILE_SSH_PORT:-8022}"

mkdir -p "$QUEUE_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "watch-open-url.sh はすでに起動中です" >&2
  exit 0
fi

open_for_pc() {
  local url="$1"
  echo "open(pc): ${url}"
  explorer.exe "$url" >/dev/null 2>&1 || true
}

open_for_mobile() {
  local url="$1"
  echo "open(mobile): ${url}"
  ssh -o RequestTTY=no -o ConnectTimeout=5 -p "$MOBILE_SSH_PORT" "$MOBILE_SSH_HOST" \
    "termux_open_url '${url}'" >/dev/null 2>&1 || true
}

echo "PC/Android共通のURL監視を開始します: ${QUEUE_DIR}"

while true; do
  for TAG_FILE in "${QUEUE_DIR}"/*.pending; do
    [ -e "$TAG_FILE" ] || continue
    TAG="$(basename "$TAG_FILE" .pending)"
    URL="$(cat "$TAG_FILE" 2>/dev/null || true)"
    rm -f "$TAG_FILE"
    [ -n "$URL" ] || continue
    case "$TAG" in
      pc)
        open_for_pc "$URL"
        ;;
      mobile)
        open_for_mobile "$URL"
        ;;
      *)
        echo "未知のタグです: ${TAG} (${URL})" >&2
        ;;
    esac
  done
  sleep 1
done
