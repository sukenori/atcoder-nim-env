#!/usr/bin/env bash
set -euo pipefail

url="${1:?URL is required}"
case "$url" in
  http://*|https://*) ;;
  *)
    printf 'unsupported URL: %s\n' "$url" >&2
    exit 2
    ;;
esac

tag="${DEVICE_TAG:-pc}"

open_pc() {
  exec /workspace/atcoder-nim-env/open-windows-url.sh "$url"
}

open_mobile() {
  : "${TERMUX_SSH_HOST:?TERMUX_SSH_HOST is not set}"

  local quoted_url
  quoted_url="$(python3 -c \
    'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$url")"

  ssh -o BatchMode=yes -o ConnectTimeout=5 \
    "$TERMUX_SSH_HOST" "termux-open-url $quoted_url"
}

case "$tag" in
  pc)     open_pc ;;
  mobile) open_mobile ;;
  *)
    printf 'unknown DEVICE_TAG: %s\n' "$tag" >&2
    exit 3
    ;;
esac