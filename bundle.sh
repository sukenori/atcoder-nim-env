#!/usr/bin/env bash
# このファイルは bash で実行する

# エラーが出たら止める(-e)。未定義の変数を使ったら止める(-u)。パイプの途中の失敗も拾う(pipefail)
set -euo pipefail
# $( ) の中で起きたエラーでも止まるようにする
shopt -s inherit_errexit

# 第1引数: プロジェクトのルートフォルダ(絶対パス)
workspace_dir="$1"
# 第2引数: まとめる対象のNimファイル(絶対パス)
source_file="$2"
# 結果を書き出すファイル
out_file="${workspace_dir}/bundled.txt"
# ライブラリが置いてあるフォルダ(ルートの隣のcp-nim-lib)
library_root="$(cd "${workspace_dir}/../cp-nim-lib" && pwd)"
# 提出コードに書き込む、ライブラリ元ファイルのURLの前半
library_url_base="https://github.com/sukenori/cp-nim-lib/blob/main"
# include "xxx" の行を見つけるための正規表現
INCLUDE_RE='^[[:space:]]*include[[:space:]]+"([^"]+)"[[:space:]]*$'
# 展開済みのライブラリを記録する表(連想配列)。同じものを二重に埋め込まないために使う
declare -A INCLUDED

# 1つのファイルを読み、include行を中身に置き換えて出力する関数
bundle_file() {
  # 処理するファイル
  local file="$1"
  # このファイル内のincludeを探す基準フォルダ
  local resolve_dir="$2"
  # 読み込み中の1行
  local line
  # ファイルを1行ずつ読む(最後の行に改行がなくても読む)
  while IFS= read -r line || [ -n "$line" ]; do
    # include行なら展開する
    if [[ "$line" =~ $INCLUDE_RE ]]; then
      # includeに書かれた名前(正規表現の括弧の中身)
      local inc="${BASH_REMATCH[1]}"
      # 相対パスなら基準フォルダの下とみなす
      local raw="${resolve_dir}/${inc}"
      # 絶対パスならそのまま使う
      if [[ "$inc" = /* ]]; then raw="$inc"; fi
      # includeされるファイルの絶対パス(../などを整理して、表のキーを揃える)
      local target
      target="$(cd "$(dirname "$raw")" && pwd)/$(basename "$raw")"
      # まだ展開していないファイルだけ処理する
      if [ -z "${INCLUDED[$target]:-}" ]; then
        # 展開済みとして記録する
        INCLUDED[$target]=1
        # そのファイル自身のincludeも、再帰的に展開する(基準はそのファイルのフォルダ)
        local processed
        processed="$(bundle_file "$target" "$(dirname "$target")")"
        # 展開結果を圧縮(xz)して、文字列にする(base64)
        local encoded
        encoded="$(printf '%s\n' "$processed" | xz -zc | base64 -w0)"
        # ライブラリ内のファイルなら、元のURLをコメントとして出力する
        if [[ "$target" == "$library_root"/* ]]; then
          printf '# source: %s/%s\n' "$library_url_base" "${target#$library_root/}"
        fi
        # 圧縮した中身を、Library "..." の形で出力する
        printf 'Library "%s"\n' "$encoded"
      fi
    else
      # include行でなければ、そのまま出力する
      printf '%s\n' "$line"
    fi
  done < "$file"
}

# 出力ファイルを作る
{
  # 先頭に、Library "..." を解凍して取り込むNimのマクロを書く
  echo 'import macros; macro Library(s: static[string]): untyped = parseStmt(staticExec("echo "&s&"|base64 -d|xzcat"))'
  # 対象ファイルを展開する(最初のincludeの基準はライブラリのフォルダ)
  bundle_file "$source_file" "$library_root"
} > "$out_file"

# 末尾の余分な改行を1つ削る
perl -0777 -pi -e 's/\n\z//' "$out_file"
