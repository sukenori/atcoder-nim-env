#!/usr/bin/env bash
# WSL から、Windows 側の既定のブラウザで URL を開く(コンテナの中からも呼ばれる)
# 使い方: open-windows-url.sh <http または https の URL>

# エラー、未定義の変数、パイプの途中の失敗があれば、そこで止める
set -euo pipefail

# 第1引数の URL を受け取る(無ければエラーにする)
url="${1:?URL is required}"
# http と https 以外の URL は、開かずに終わる
case "$url" in
  https://*|http://*) ;;
  *)
    printf 'Unsupported URL: %s\n' "$url" >&2
    exit 2
    ;;
esac

# Windows の実行ファイルを呼べる場所へ移動する
cd /mnt/c/Windows

# 指定した WSL の通信用ファイル(socket)で、Windows の cmd.exe が応答するかを調べる関数
works() {
  WSL_INTEROP="$1" /mnt/c/Windows/System32/cmd.exe /c exit >/dev/null 2>&1
}

# 使う socket(まだ見つかっていない)
socket=""
# 今のシェルに渡されている socket が応答するなら、それを使う
if [[ -n "${WSL_INTEROP:-}" && -S "$WSL_INTEROP" ]] && works "$WSL_INTEROP"; then
  socket="$WSL_INTEROP"
# 無ければ、WSL が用意している socket から、応答する最初のものを探す
else
  for candidate in /run/WSL/*_interop; do
    if [[ -S "$candidate" ]] && works "$candidate"; then
      socket="$candidate"
      break
    fi
  done
fi

# 応答する socket が無ければ、エラーで終わる
if [[ -z "$socket" ]]; then
  echo "応答するWSL interop socketがありません" >&2
  exit 1
fi

# 見つけた socket を使い、Windows 側で URL を開く
WSL_INTEROP="$socket" /mnt/c/Windows/System32/cmd.exe /c start "" "$url"
