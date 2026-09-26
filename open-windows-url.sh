#!/usr/bin/env bash
set -euo pipefail

url="${1:?URL is required}"
case "$url" in
  https://*|http://*) ;;
  *)
    printf 'Unsupported URL: %s\n' "$url" >&2
    exit 2
    ;;
esac

# WSLからWindows実行ファイルを呼べた作業ディレクトリで実行する
cd /mnt/c/Windows

socket=""

# このシェルに有効なsocketが渡されていれば優先する
if [[ -n "${WSL_INTEROP:-}" && -S "$WSL_INTEROP" ]] &&
   WSL_INTEROP="$WSL_INTEROP" \
     /mnt/c/Windows/System32/cmd.exe /c exit >/dev/null 2>&1
then
  socket="$WSL_INTEROP"
fi

# なければ、応答するsocketを一つだけ探す
if [[ -z "$socket" ]]; then
  for candidate in /run/WSL/*_interop; do
    [[ -S "$candidate" ]] || continue

    if WSL_INTEROP="$candidate" \
       /mnt/c/Windows/System32/cmd.exe /c exit >/dev/null 2>&1
    then
      socket="$candidate"
      break
    fi
  done
fi

if [[ -z "$socket" ]]; then
  echo "応答するWSL interop socketがありません" >&2
  exit 1
fi

# socket探索はここで終了。URLは一度だけ開く
WSL_INTEROP="$socket" /mnt/c/Windows/System32/cmd.exe /c start "" "$url"
