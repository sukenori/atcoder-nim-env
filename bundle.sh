#!/bin/bash
# ===========================================================================
# bundle.sh — Nim ソースの include 文を展開し、1ファイルにまとめるスクリプト
#
# 使い方: bash bundle.sh <作業ディレクトリ> <ソースファイル>
#   例:   bash bundle.sh . work/abc999_a.nim
#
# 仕組み:
#   1. ソースコード中の include "..." 行を見つける
#   2. 対応するライブラリファイルを xz 圧縮 → Base64 エンコードして埋め込む
#   3. 実行時にデコード・展開する Nim マクロを先頭に挿入する
#   → AtCoder に1ファイルで提出できるようになる
# ===========================================================================
set -eu

workspaceFolder="$1"
file="$2"
out="${workspaceFolder}/bundled.txt"

# 出力ファイルを空にして開始
: > "$out"

# デコード用マクロを先頭に書き込む
echo 'import macros; macro Library(s: static[string]): untyped = parseStmt(staticExec("echo "&s&"|base64 -d|xzcat"))' >> "$out"

# ソースを1行ずつ読み、include 行ならライブラリを埋め込む
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^[[:space:]]*include[[:space:]]+\"([^\"]+)\"[[:space:]]*$ ]]; then
    inc="${BASH_REMATCH[1]}"

    # ライブラリの検索パス（Distrobox 内のホームディレクトリ）
    target_path="$HOME/nim-library/${inc}"

    if [ ! -f "$target_path" ]; then
      echo "Error: include 先が見つかりません → $target_path" >&2
      exit 1
    fi

    # ファイルを xz 圧縮 → Base64 エンコードして埋め込む
    enc="$(xz -zc < "$target_path" | base64 -w0)"
    printf 'Library "%s"\n' "$enc" >> "$out"
  else
    printf '%s\n' "$line" >> "$out"
  fi
done < "$file"

# 末尾の余分な改行を除去
perl -0777 -pi -e 's/\n\z//' "$out" 2>/dev/null || true

