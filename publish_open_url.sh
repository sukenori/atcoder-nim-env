#!/usr/bin/env bash
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "usage: publish_open_url.sh <url>" >&2
  exit 1
fi

QUEUE_DIR="/workspace/atcoder-nim-env/.runtime/open-url"
TAG="${DEVICE_TAG:-pc}"
TARGET="${QUEUE_DIR}/${TAG}.pending"

mkdir -p "$QUEUE_DIR"

TMP="$(mktemp "${QUEUE_DIR}/.tmp.XXXXXX")"
printf '%s
' "$URL" > "$TMP"
mv -f "$TMP" "$TARGET"

echo "queued for ${TAG}: ${URL}"