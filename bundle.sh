#!/bin/bash
set -eu
workspaceFolder="$1"
file="$2"
out="${workspaceFolder}/bundled.txt"
: > "$out"
echo 'import macros; macro Library(s: static[string]): untyped = parseStmt(staticExec("echo "&s&"|base64 -d|xzcat"))' >> "$out"
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^[[:space:]]*include[[:space:]]+\"([^\"]+)\"[[:space:]]*$ ]]; then
    inc="${BASH_REMATCH[1]}"
    target_path="${inc}"
    enc="$(printf '%s\n' "$(cat "$target_path")" | xz -zc | base64 -w0)"
    printf 'Library "%s"\n' "$enc" >> "$out"
  else
    printf '%s\n' "$line" >> "$out"
  fi
done < "$file"
perl -0777 -pi -e 's/\n\z//' "$out" 2>/dev/null || true
