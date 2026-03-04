#!/bin/bash
set -eu
workspaceFolder="$1"
file="$2"
# 出力先を workspaceFolder (つまり .) 直下の bundled.txt に変更
out="${workspaceFolder}/bundled.txt"
: > "$out"

echo 'import macros; macro Library(s: static[string]): untyped = parseStmt(staticExec("echo "&s&"|base64 -d|xzcat"))' >> "$out"

while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^[[:space:]]*include[[:space:]]+\"([^\"]+)\"[[:space:]]*$ ]]; then
    inc="${BASH_REMATCH[1]}"
    
    # 決め打ちで /workspace/lib を探しに行く（これが一番確実です）
    target_path="/workspace/library/${inc}"
    
    # ファイルが存在するか厳密にチェック
    if [ ! -f "$target_path" ]; then
      echo "Error: Include file not found -> $target_path" >&2
      exit 1
    fi
    
    enc="$(cat "$target_path" | xz -zc | base64 -w0)"
    printf 'Library "%s"\n' "$enc" >> "$out"
  else
    printf '%s\n' "$line" >> "$out"
  fi
done < "$file"
perl -0777 -pi -e 's/\n\z//' "$out" 2>/dev/null || true

