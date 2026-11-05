#!/usr/bin/env bash
# oj submit のあとなどにブラウザとして呼ばれ、URL を接続元の端末(PC か Android)で開く
# 環境変数 BROWSER に設定してある(.zshrc.local)。接続元は DEVICE_TAG で決まる

# エラー、未定義の変数、パイプの途中の失敗があれば、そこで止める
set -euo pipefail

# 第1引数の URL を受け取る(無ければエラーにする)
url="${1:?URL is required}"
# http と https 以外の URL は、開かずに終わる
case "$url" in
  http://*|https://*) ;;
  *)
    printf 'unsupported URL: %s\n' "$url" >&2
    exit 2
    ;;
esac

# 接続元の端末の名前(省略時は pc)
tag="${DEVICE_TAG:-pc}"

# PC: Windows 側のブラウザで開く
open_pc() {
  exec /workspace/atcoder-nim-env/open-windows-url.sh "$url"
}

# Android: SSH で Termux につなぎ、termux-open-url で開く
open_mobile() {
  # Termux への接続先が設定されていなければ、エラーにする
  : "${TERMUX_SSH_HOST:?TERMUX_SSH_HOST is not set}"
  # URL をシェルで安全に渡せる形(引用符付き)に変える
  local quoted_url
  quoted_url="$(python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$url")"
  # パスワードを聞かず、5秒で諦める設定で、Termux に URL を開かせる
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$TERMUX_SSH_HOST" "termux-open-url $quoted_url"
}

# 端末の名前に合わせて開く
case "$tag" in
  pc)     open_pc ;;
  mobile) open_mobile ;;
  *)
    printf 'unknown DEVICE_TAG: %s\n' "$tag" >&2
    exit 3
    ;;
esac
