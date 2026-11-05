#!/usr/bin/env bash
# 1 つのテストケース(.in)を実行して、判定を出力先に書き足す。
# 使い方: run_case.sh <入力ファイル> <submit|debug> <出力先> <a.out> <naive.out> <テストフォルダ> <制限ms> <制限MB>
# 終了コード: 判定が RUN(提出モード正常) または AC のとき 0、それ以外は 1

# 引数を名前の付いた変数に受け取る
input="$1"; mode="$2"; out_target="$3"; a_out="$4"; naive_out="$5"; test_dir="$6"; tl="$7"; ml="$8"

# ケース名(拡張子 .in を除いたファイル名)
name="$(basename "$input" .in)"
# 実行結果などを置く一時フォルダ。終了時に必ず削除する
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 長い出力を省略して表示する関数。40 行以上なら先頭 20 行と末尾 10 行、1 行が 40 語以上ならその行の先頭 20 語と末尾 10 語だけ表示
truncate_print() {
  # 行数を数える
  local lines
  lines="$(wc -l < "$1")"
  # 40 行以上のときは、行単位で省略する
  if [ "$lines" -ge 40 ]; then
    # 先頭 20 行を表示する
    head -n 20 "$1"
    # 省略した行数を表示する
    printf '... (%d lines) ...\n' "$((lines - 30))"
    # 末尾 10 行を表示する
    tail -n 10 "$1"
  else
    # 40 行未満のときは、1 行ごとに語数を見て、多すぎる行だけ省略する
    awk '{
      # この行の語数
      n = NF
      # 40 語以上なら、先頭 20 語 ... 末尾 10 語 の形にする
      if (n >= 40) {
        line = ""
        for (i = 1; i <= 20; i++) line = line $i " "
        line = line "... (" (n - 30) " numbers) ... "
        for (i = n - 9; i <= n; i++) line = line (i > n - 9 ? " " : "") $i
        print line
      } else {
        # 40 語未満はそのまま表示する
        print $0
      }
    }' "$1"
  fi
}

# 実行の時間制限(秒)。判定の制限に 0.5 秒の余裕を足す
tl_sec="$(awk "BEGIN { printf \"%.3f\", ($tl + 500) / 1000 }")"
# 開始時刻(ミリ秒)
start="$(date +%s%3N)"
# メモリを制限し、/usr/bin/time で最大メモリを測りながら、時間制限つきで実行する
( ulimit -v $((ml * 1024)); /usr/bin/time -v -o "$tmp/time" timeout "${tl_sec}s" "$a_out" < "$input" > "$tmp/out" 2> "$tmp/err" )
# 実行の終了コード
code=$?
# 実行にかかった時間(秒)
elapsed="$(awk "BEGIN { printf \"%.6f\", ($(date +%s%3N) - $start) / 1000 }")"
# 使った最大メモリ(MB)
rss_kb="$(grep 'Maximum resident set size' "$tmp/time" | awk '{ print $NF }')"
rss_mb="$(awk "BEGIN { printf \"%.3f\", ${rss_kb:-0} / 1024 }")"

# 判定。まず「実行できた」という意味の RUN とし、異常があれば書き換える
verdict="RUN"
# 時間切れ(timeout は 124、強制終了は 137)
if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then verdict="TLE"
# メモリ超過
elif awk "BEGIN { exit !($rss_mb > $ml) }"; then verdict="MLE"
# それ以外の異常終了
elif [ "$code" -ne 0 ]; then verdict="RE"
fi

# 正解出力があるかどうか(debug モードで愚直解が動いたときだけ 1)
has_expected=0
# 愚直解の終了コード
naive_code=""
# debug モードでは、愚直解の出力を正解として比較する
if [ "$mode" = "debug" ]; then
  # 愚直解の実行ファイルがなければ、その旨を判定にする
  if [ ! -x "$naive_out" ]; then
    verdict="NAIVE_MISSING"
  else
    # 愚直解を同じ入力で実行する
    timeout "${tl_sec}s" "$naive_out" < "$input" > "$tmp/expect" 2> "$tmp/naive_err"
    # 愚直解の終了コード
    naive_code=$?
    # 愚直解が正常に終わったとき
    if [ "$naive_code" -eq 0 ]; then
      # 正解出力を test フォルダにも保存する
      install -m 644 "$tmp/expect" "$test_dir/$name.out"
      has_expected=1
      # 自分の解がここまで正常なら、出力が正解と一致するか比較して AC / WA を決める
      if [ "$verdict" = "RUN" ]; then
        if diff -q "$tmp/out" "$tmp/expect" > /dev/null; then verdict="AC"; else verdict="WA"; fi
      fi
    else
      # 愚直解が異常終了したときは、比較できない
      verdict="NAIVE_RE"
    fi
  fi
fi

# 出力先へ、まとめて書き足す
{
  # 空行で区切る
  printf '\n'
  if [ "$mode" = "submit" ]; then
    # 提出モード: 正常なら緑の SUCCESS、それ以外は赤の FAILURE
    if [ "$verdict" = "RUN" ]; then tag="SUCCESS"; color='\033[32m'; else tag="FAILURE"; color='\033[31m'; fi
    # ケース名・時間・メモリを表示する
    printf '\033[34m[INFO]\033[0m %s\n' "$name"
    printf '\033[34m[INFO]\033[0m time: %s sec\n' "$elapsed"
    printf '\033[34m[INFO]\033[0m memory: %s MB\n' "$rss_mb"
    # 結果を色付きで表示する
    printf "${color}[$tag]\033[0m %s\n" "$verdict"
  else
    # debug モード: 判定ごとの色を決める(AC は緑、WA は赤、TLE/MLE/RE は黄、他は専用色)
    case "$verdict" in
      AC) color='\033[32m' ;;
      WA) color='\033[31m' ;;
      TLE|MLE|RE) color='\033[33m' ;;
      NAIVE_MISSING) color='\033[36m' ;;
      NAIVE_RE) color='\033[35m' ;;
      *) color='\033[31m' ;;
    esac
    # ケース名・時間・メモリを表示する
    printf '[INFO] %s\n' "$name"
    printf '[INFO] time: %s sec\n' "$elapsed"
    printf '[INFO] memory: %s MB\n' "$rss_mb"
    # 実行中の標準エラー出力(Nim の dump など)があれば表示する
    if [ -s "$tmp/err" ]; then printf '[INFO] dump:\n'; truncate_print "$tmp/err"; fi
    # 愚直解の実行ファイルがない場合の案内
    if [ "$verdict" = "NAIVE_MISSING" ]; then
      printf '[INFO] naive.out is missing or not executable:\n[INFO] expected path: %s\n' "$naive_out"
    fi
    # 愚直解が異常終了した場合の終了コードと標準エラー出力
    if [ "$verdict" = "NAIVE_RE" ]; then
      printf '[INFO] naive exit code: %s\n' "$naive_code"
      if [ -s "$tmp/naive_err" ]; then printf '[INFO] naive stderr:\n'; truncate_print "$tmp/naive_err"; fi
    fi
    # 入力・自分の出力を表示する
    printf '[INFO] input:\n'; truncate_print "$input"
    printf '[INFO] output:\n'; truncate_print "$tmp/out"
    # 正解出力があれば表示する
    if [ "$has_expected" -eq 1 ]; then printf '[INFO] expected:\n'; truncate_print "$tmp/expect"; fi
    # 判定を色付きで表示する
    printf "${color}[$verdict]\033[0m\n"
  fi
} >> "$out_target"

# RUN(提出モード正常)または AC なら成功、それ以外は失敗として終了する
[ "$verdict" = "RUN" ] || [ "$verdict" = "AC" ]
