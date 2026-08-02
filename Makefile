# BASH_REMATCH（正規表現マッチ結果の配列）を後で使うため、使用シェルをbashに固定
SHELL := /usr/bin/env bash


# FILE: 呼び出し時に指定する、対象 Nim ソースファイルの相対パス
FILE ?=


# URL: AtCoder 問題 URL（省略時はFILE名から自動推測）
URL  ?=


# Nim コンパイラの実行パス
NIM ?= /root/.nimble/bin/nim


# online-judge-tools のコマンド名
OJ  ?= oj


# TL: TLE 判定に使う実行時間制限（ミリ秒）
TL ?= 2000


# ML: MLE 判定に使うメモリ制限（メガバイト）
ML ?= 1024


# Nimのビルドキャッシュ .nimcache の保存先
NIMCACHE_ROOT ?= /tmp/nimcache-$(notdir $(CURDIR))


# 引数なしで `make` とだけ打った場合のデフォルトターゲットを compile に設定
.DEFAULT_GOAL := compile



# print-url: ターゲット URL を標準出力する（`$(MAKE) print-url` として呼び出す）
.PHONY: print-url
print-url:
	@if [ -n "$(URL)" ]; then \
	  echo "$(URL)"; \
	else \
	  BASENAME="$$(basename "$(FILE)")"; \
	  STEM="$$(echo "$$BASENAME" | tr '[:upper:]' '[:lower:]')"; \
	  STEM="$${STEM%.nim}"; \
	  if [[ "$$STEM" =~ ^([a-z]+[0-9]+)([a-z])$$ ]]; then \
	    CONTEST="$${BASH_REMATCH[1]}"; \
	    TASK_LETTER="$${BASH_REMATCH[2]}"; \
	    echo "https://atcoder.jp/contests/$${CONTEST}/tasks/$${CONTEST}_$${TASK_LETTER}"; \
	  else \
	    echo "cannot infer AtCoder URL from filename: $(FILE)" >&2; \
	    exit 1; \
	  fi; \
	fi



# ============================================================
# 操作1: コンパイル（ローカル検証用）
# ============================================================
.PHONY: compile
compile:
	$(NIM) cpp \
	  -d:release -d:debug -d:useMalloc \
	  --mm:arc --multimethods:on \
	  --warning[SmallLshouldNotBeUsed]:off \
	  --colors:on --hints:off \
	  --maxLoopIterationsVM:10000000000000 \
	  --maxCallDepthVM:10000000000000 \
	  --rangeChecks:on --boundChecks:on --overflowChecks:on \
	  --stackTrace:on \
	  --passC:-Wno-alloc-size-larger-than \
	  --passL:-Wno-alloc-size-larger-than \
	  --nimcache:"$(NIMCACHE_ROOT)/compile" \
	  -o:a.out "$(FILE)"



# download-sample: AtCoder の入出力サンプルをダウンロードする
.PHONY: download-sample
download-sample:
	rm -rf sample
	mkdir -p sample
	@URL_VALUE="$$( $(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)' )"; \
	$(OJ) d "$$URL_VALUE" -d sample -s



# sample: コンパイルしてから、サンプルをダウンロードし、oj test を実行
.PHONY: sample
sample: compile download-sample
	$(OJ) t -c ./a.out -d sample/



# bundle: includeを展開して1ファイルにまとめ、クリップボードへ格納する。
#
# - tmux内: tmuxバッファへ入れ、tmuxのOSC52連携でホストへ送る。
# - tmux外: OSC52を直接出力する。VS Code統合ターミナルと
#   Windows Terminalの双方で、ホスト側クリップボードへ届く。
.PHONY: bundle
bundle:
	bash bundle.sh "$(CURDIR)" "$(abspath $(FILE))"
	@if [ -n "$$TMUX" ]; then \
	  tmux load-buffer -w - < bundled.txt; \
	else \
	  printf '\033]52;c;%s\a' "$$(base64 < bundled.txt | tr -d '\n')"; \
	fi



# ============================================================
# gen-cases: ランダムケース生成プログラムを一時的にビルド・実行し、test/へ出力
#
# 方針（最終版）:
#   - when defined(gen) の有無で「やる/やらない」を分けるだけ。
#     ショートカットや専用フラグは増やさない。
#   - test/ は when defined(gen) の有無に関わらず、必ず先にリフレッシュする
#     （古いテストを残さないことを、生成の成否より優先する）。
#   - when defined(gen) が無い場合は、メッセージを出すだけで正常終了(exit 0)。
#     ここで止めると submit 全体が失敗してしまい、
#     「gen節が無い問題は普通に提出できる」という前提が崩れるため、
#     エラーではなくスキップとして扱う。
#   - when defined(gen) がある場合のみ、mktempで一時バイナリを作り、
#     -d:gen 付きでコンパイル・実行して test/ へケースを書かせる
#     （test/への書き込みは when defined(gen) 側のコードの責務）。
# ============================================================
.PHONY: gen-cases
gen-cases:
	rm -rf test
	mkdir -p test
	@if grep -qE 'when[[:space:]]+defined\([[:space:]]*gen[[:space:]]*\)' "$(FILE)"; then \
	  GEN_BIN="$$(mktemp -u ./.gen_cases.XXXXXX)"; \
	  trap 'rm -f "$$GEN_BIN"' EXIT; \
	  $(NIM) cpp \
	    -d:release -d:gen \
	    --mm:arc --hints:off \
	    --nimcache:"$(NIMCACHE_ROOT)/gen" \
	    -o:"$$GEN_BIN" "$(FILE)"; \
	  "$$GEN_BIN"; \
	else \
	  echo "[gen-cases] $(FILE) に when defined(gen) が見つかりません（include先にある場合はこのチェックは無効）→ スキップ"; \
	fi



# ============================================================
# ケース評価（run_case / check-cases は変更なし）
# ============================================================
define run_case
	NAME=$$(basename "$(1)" .in); \
	TMPOUT=$$(mktemp); \
	TMPERR=$$(mktemp); \
	TMPTIME=$$(mktemp); \
	TMPEXPECT=$$(mktemp); \
	LIMIT_LINES=40; \
	HEAD_LINES=20; \
	TAIL_LINES=10; \
	WORD_LIMIT=40; \
	HEAD_WORDS=20; \
	TAIL_WORDS=10; \
	print_truncated() { \
	  local f="$$1"; \
	  local total_lines; \
	  total_lines=$$(wc -l < "$$f"); \
	  if [ "$$total_lines" -ge "$$LIMIT_LINES" ]; then \
	    head -n "$$HEAD_LINES" "$$f"; \
	    printf "... (%d lines) ...\n" "$$(( total_lines - HEAD_LINES - TAIL_LINES ))"; \
	    tail -n "$$TAIL_LINES" "$$f"; \
	  else \
	    awk -v head="$$HEAD_WORDS" -v tail="$$TAIL_WORDS" -v limit="$$WORD_LIMIT" ' \
	      { \
	        n = NF; \
	        if (n >= limit) { \
	          line = ""; \
	          for (i = 1; i <= head; i++) { line = line $$i (i < head ? " " : ""); } \
	          line = line " ... (" (n - head - tail) " numbers) ... "; \
	          start = n - tail + 1; \
	          rest = ""; \
	          for (i = start; i <= n; i++) { rest = rest (i > start ? " " : "") $$i; } \
	          print line rest; \
	        } else { \
	          print $$0; \
	        } \
	      }' "$$f"; \
	  fi; \
	}; \
	START=$$(date +%s%3N); \
	TL_SEC=$$(awk "BEGIN { printf \"%.3f\", ($(TL) + 500) / 1000 }"); \
	( ulimit -v $$(( $(ML) * 1024 )); \
	  /usr/bin/time -v -o "$$TMPTIME" \
	    timeout "$${TL_SEC}s" ./a.out < "$(1)" > "$$TMPOUT" 2> "$$TMPERR" ); \
	CODE=$$?; \
	END=$$(date +%s%3N); \
	ELAPSED=$$(( END - START )); \
	MAXRSS_KB=$$(grep 'Maximum resident set size' "$$TMPTIME" | awk '{ print $$NF }'); \
	MAXRSS_MB=$$(awk "BEGIN { printf \"%.3f\", $${MAXRSS_KB:-0} / 1024 }"); \
	ELAPSED_SEC=$$(awk "BEGIN { printf \"%.6f\", $$ELAPSED / 1000 }"); \
	VERDICT="RUN"; \
	if [ $$CODE -eq 124 ] || [ $$CODE -eq 137 ]; then VERDICT="TLE"; \
	elif awk "BEGIN { exit !($$MAXRSS_MB > $(ML)) }"; then VERDICT="MLE"; \
	elif [ $$CODE -ne 0 ]; then VERDICT="RE"; \
	fi; \
	HAS_EXPECTED=0; \
	if [ "$(MODE)" = "debug" ] && [ -x naive.out ]; then \
	  timeout "$${TL_SEC}s" ./naive.out < "$(1)" > "$$TMPEXPECT" 2>/dev/null; \
	  NAIVE_CODE=$$?; \
	  if [ $$NAIVE_CODE -eq 0 ]; then \
	    install -m 644 "$$TMPEXPECT" "test/$${NAME}.out"; \
	    HAS_EXPECTED=1; \
	    if [ "$$VERDICT" = "RUN" ]; then \
	      diff -q "$$TMPOUT" "$$TMPEXPECT" > /dev/null && VERDICT="AC" || VERDICT="WA"; \
	    fi; \
	  fi; \
	fi; \
	if [ "$(MODE)" = "submit" ]; then \
	  case "$$VERDICT" in \
	    RUN) TAG="SUCCESS"; COLOR="\033[32m" ;; \
	    *)   TAG="FAILURE"; COLOR="\033[31m" ;; \
	  esac; \
	  { \
	    printf "\n"; \
	    printf "\033[34m[INFO]\033[0m %s\n" "$$NAME"; \
	    printf "\033[34m[INFO]\033[0m time: %s sec\n" "$$ELAPSED_SEC"; \
	    printf "\033[34m[INFO]\033[0m memory: %s MB\n" "$$MAXRSS_MB"; \
	    printf "$${COLOR}[$$TAG]\033[0m %s\n" "$$VERDICT"; \
	  } >> "$(OUT_TARGET)"; \
	else \
	  case "$$VERDICT" in \
	    AC) TAG="SUCCESS" ;; \
	    *)  TAG="FAILURE" ;; \
	  esac; \
	  { \
	    printf "\n"; \
	    printf "[INFO] %s\n" "$$NAME"; \
	    printf "[INFO] time: %s sec\n" "$$ELAPSED_SEC"; \
	    printf "[INFO] memory: %s MB\n" "$$MAXRSS_MB"; \
	    if [ -s "$$TMPERR" ]; then \
	      printf "[INFO] dump:\n"; \
	      print_truncated "$$TMPERR"; \
	    fi; \
	    if [ "$$VERDICT" != "AC" ]; then \
	      printf "[INFO] input:\n"; \
	      print_truncated "$(1)"; \
	      printf "[INFO] output:\n"; \
	      print_truncated "$$TMPOUT"; \
	      if [ $$HAS_EXPECTED -eq 1 ]; then \
	        printf "[INFO] expected:\n"; \
	        print_truncated "$$TMPEXPECT"; \
	      fi; \
	    fi; \
	    printf "[$$TAG] %s\n" "$$VERDICT"; \
	  } >> "$(OUT_TARGET)"; \
	fi; \
	rm -f "$$TMPOUT" "$$TMPERR" "$$TMPTIME" "$$TMPEXPECT"; \
	[ "$$VERDICT" = "RUN" ] || [ "$$VERDICT" = "AC" ]
endef



# check-cases: test/*.in を全件、run_caseで評価する。
.PHONY: check-cases
check-cases:
	@if [ -z "$$(ls test/*.in 2>/dev/null)" ]; then \
	  echo "[check-cases] test/ が空です（gen未実装 or gen-casesが失敗）→ ケース評価をスキップ"; \
	  exit 0; \
	fi; \
	OK=0; \
	for f in test/*.in; do \
	  if $(call run_case,$$f); then :; else OK=1; fi; \
	done; \
	exit $$OK



# ============================================================
# 操作2: 提出
# ============================================================
.PHONY: compile-submit
compile-submit:
	$(NIM) cpp \
	  -d:release -d:useMalloc \
	  --mm:arc --multimethods:on \
	  --warning[SmallLshouldNotBeUsed]:off \
	  --colors:on --hints:off \
	  --maxLoopIterationsVM:10000000000000 \
	  --maxCallDepthVM:10000000000000 \
	  --passC:-Wno-alloc-size-larger-than \
	  --passL:-Wno-alloc-size-larger-than \
	  --nimcache:"$(NIMCACHE_ROOT)/submit" \
	  -o:a.out "$(FILE)"



.PHONY: submit
submit: compile-submit
	rm -rf sample
	mkdir -p sample
	$(MAKE) --no-print-directory download-sample FILE='$(FILE)' URL='$(URL)'
	$(OJ) t -c ./a.out -d sample/
	$(MAKE) --no-print-directory gen-cases FILE='$(FILE)'
	$(MAKE) --no-print-directory check-cases MODE=submit OUT_TARGET=/dev/stdout
	$(MAKE) --no-print-directory bundle FILE='$(FILE)'
	@URL_VALUE="$$( $(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)' )"; \
	$(OJ) s "$$URL_VALUE" bundled.txt -l 6072 -w 0 -y



# ============================================================
# 操作3: デバッグ
#
# naive.out について（最終版・gen-casesと同方針）:
#   when defined(naive) の有無で「やる/やらない」を分けるだけ。
#   - ある場合のみ -d:naive でコンパイルし、naive.out を作る。
#     run_case はこの naive.out との diff で AC/WA を判定する。
#   - 無い場合はコンパイルせず、古い naive.out（前回別ファイルで
#     作られたものを含む）も削除する。
#     これをしないと、古い naive.out が残ったまま
#     「たまたま存在するので比較してしまう」事故につながるため。
#   - gen-cases のときのような標準入力待ちのハングは、
#     test/*.in をリダイレクト入力するため起きない。
#     よって「止める」必要はなく、単純にスキップでよい。
# ============================================================
.PHONY: debug
debug: compile
	rm -f debug.log
	: > debug.log
	$(MAKE) --no-print-directory gen-cases FILE='$(FILE)'
	@if grep -qE 'when[[:space:]]+defined\([[:space:]]*naive[[:space:]]*\)' "$(FILE)"; then \
	  $(NIM) cpp \
	    -d:release -d:naive \
	    --mm:arc --hints:off \
	    --nimcache:"$(NIMCACHE_ROOT)/naive" \
	    -o:naive.out "$(FILE)" 2>> debug.log; \
	else \
	  rm -f naive.out; \
	  echo "[debug] $(FILE) に when defined(naive) が見つかりません → naive比較をスキップ" >> debug.log; \
	fi
	$(MAKE) --no-print-directory check-cases \
	  MODE=debug OUT_TARGET=debug.log FILE='$(FILE)' || true



# ============================================================
# 日付フォルダへアーカイブ
# ============================================================
.PHONY: archive
archive:
	@DATE="$$(date +%y-%m-%d)"; \
	if [ -z "$$(find work -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then \
	  echo "work が空です"; exit 1; \
	fi; \
	mkdir -p "../cp-solved-log/$$DATE"; \
	cp -a work/