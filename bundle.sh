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
library_root="${workspace_dir}/../cp-nim-lib"

# 出力ファイルを空にして開始する
: > "$out_file"

# デコード用マクロを先頭に書く
echo 'import macros; macro Library(s: static[string]): untyped = parseStmt(staticExec("echo "&s&"|base64 -d|xzcat"))' >> "$out_file"

# include 行を見つけたらライブラリ本体を埋め込む
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^[[:space:]]*include[[:space:]]+\"([^\"]+)\"[[:space:]]*$ ]]; then
    include_path="${BASH_REMATCH[1]}"

    # ライブラリは cp-nim-lib 配下から読む
    target_path="${library_root}/${include_path}"

    if [ ! -f "$target_path" ]; then
      echo "Error: include 先が見つかりません -> $target_path" >&2
      exit 1
    fi

    # xz 圧縮 + base64 した内容を埋め込む
    encoded="$(xz -zc < "$target_path" | base64 -w0)"
    printf 'Library "%s"\n' "$encoded" >> "$out_file"
  else
    printf '%s\n' "$line" >> "$out_file"
  fi
done < "$source_file"

# 末尾の余分な改行を削る
perl -0777 -pi -e 's/\n\z//' "$out_file" 2>/dev/null || true