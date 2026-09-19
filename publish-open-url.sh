#!/usr/bin/env bash
# /workspace/atcoder-nim-env/publish_open_url.sh
set -euo pipefail

url="${1:?URL is required}"
case "$url" in
  http://*|https://*) ;;
  *)
    printf 'unsupported URL: %s\n' "$url" >&2
    exit 2
    ;;
esac

TAG="${DEVICE_TAG:-pc}"

open_pc() {
  ssh -o BatchMode=yes -o ConnectTimeout=5 \
    "${WSL_SSH_HOST:?WSL_SSH_HOST is not set}" \
    "/home/${WSL_SSH_USER:?WSL_SSH_USER is not set}/bin/open-windows-url" \
    "$1"
}

open_mobile() {
  ssh -o BatchMode=yes -o ConnectTimeout=5 \
    "${TERMUX_SSH_HOST:?TERMUX_SSH_HOST is not set}" \
    "termux-open-url '$1'"
}

case "$TAG" in
  pc)     open_pc "$url" ;;
  mobile) open_mobile "$url" ;;
  *)
    printf 'unknown DEVICE_TAG: %s\n' "$TAG" >&2
    exit 3
    ;;
esac