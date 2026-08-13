#!/usr/bin/env bash
# bash で実行する

set -euo pipefail
# -e: 失敗したら止める
# -u: 未定義変数を禁止
# -o pipefail: パイプ途中の失敗も拾う

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <workspace_dir> <source_file>" >&2
  exit 1
fi

# 第1引数: プロジェクトルート
workspace_dir="$1"
# 第2引数: bundle 対象の Nim ファイル
source_file="$2"

if [ ! -d "$workspace_dir" ]; then
  echo "Error: workspace_dir が見つかりません -> $workspace_dir" >&2
  exit 1
fi

workspace_dir="$(cd "$workspace_dir" && pwd)"

if [[ "$source_file" != /* ]]; then
  source_file="${workspace_dir}/${source_file}"
fi

if [ ! -f "$source_file" ]; then
  echo "Error: source_file が見つかりません -> $source_file" >&2
  exit 1
fi

# 出力先
out_file="${workspace_dir}/bundled.txt"
# include の解決先ルート
library_root="$(cd "${workspace_dir}/../cp-nim-lib" && pwd)"

INCLUDE_RE='^[[:space:]]*include[[:space:]]+"([^"]+)"[[:space:]]*$'

# 一度展開したライブラリファイルは二重に埋め込まない
declare -A INCLUDED

# file: 処理対象ファイル
# resolve_dir: そのファイル内に書かれた include の相対パス解決の基準ディレクトリ
#   - トップレベル source_file の include は library_root 基準
#   - ライブラリファイル内部の include はそのファイル自身のディレクトリ基準
#     (Nim 本来の include セマンティクスと同じにする)
bundle_file() {
  local file="$1"
  local resolve_dir="$2"
  local line

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ $INCLUDE_RE ]]; then
      local inc="${BASH_REMATCH[1]}"
      local raw_target
      if [[ "$inc" = /* ]]; then
        raw_target="$inc"
      else
        raw_target="${resolve_dir}/${inc}"
      fi

      local target_dir target_base target
      if ! target_dir="$(cd "$(dirname "$raw_target")" 2>/dev/null && pwd)"; then
        echo "Error: include 先のディレクトリが見つかりません -> $raw_target (in $file)" >&2
        exit 1
      fi
      target_base="$(basename "$raw_target")"
      target="${target_dir}/${target_base}"

      if [ ! -f "$target" ]; then
        echo "Error: include 先が見つかりません -> $target (in $file)" >&2
        exit 1
      fi

      # 未展開のファイルだけ再帰的に処理してエンコードする
      if [ -z "${INCLUDED[$target]:-}" ]; then
        INCLUDED[$target]=1
        local processed encoded
        processed="$(bundle_file "$target" "$target_dir")"
        encoded="$(printf '%s\n' "$processed" | xz -zc | base64 -w0)"
        printf 'Library "%s"\n' "$encoded"
      fi
      # 既に展開済みなら何も出力しない (include ガード相当)
    else
      printf '%s\n' "$line"
    fi
  done < "$file"
}

# デコード用マクロを先頭に書く
{
  echo 'import macros; macro Library(s: static[string]): untyped = parseStmt(staticExec("echo "&s&"|base64 -d|xzcat"))'
  bundle_file "$source_file" "$library_root"
} > "$out_file"

# 末尾の余分な改行を削る
perl -0777 -pi -e 's/\n\z//' "$out_file" 2>/dev/null || true