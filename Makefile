# BASH_REMATCH を使うため bash 固定
SHELL := /usr/bin/env bash


# 対象 Nim ソース
FILE ?=


# AtCoder 問題 URL
URL ?=


# コマンド類
NIM ?= /root/.nimble/bin/nim
OJ ?= oj


# 制限
TL ?= 2000
ML ?= 1024


# パスは make 起動ディレクトリ基準で絶対化する
ROOT := $(CURDIR)
FILE_ABS := $(abspath $(FILE))
TEST_DIR := $(ROOT)/test
SAMPLE_DIR := $(ROOT)/sample
A_OUT := $(ROOT)/a.out
NAIVE_OUT := $(ROOT)/naive.out
DEBUG_LOG := $(ROOT)/debug.log


# Nim キャッシュ
NIMCACHE_ROOT ?= /tmp/nimcache-$(notdir $(CURDIR))


.DEFAULT_GOAL := compile



# ============================================================
# URL
# ============================================================
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
# コンパイル（debug版。dumpが有効。ローカル検証・提出前サンプル用）
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
		-o:"$(A_OUT)" "$(FILE_ABS)"



# ============================================================
# サンプル
# ============================================================
.PHONY: download-sample
download-sample:
	rm -rf "$(SAMPLE_DIR)"
	mkdir -p "$(SAMPLE_DIR)"
	@URL_VALUE="$$( $(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)' )"; \
	$(OJ) d "$$URL_VALUE" -d "$(SAMPLE_DIR)" -s


.PHONY: sample
sample: compile download-sample
	$(OJ) t -c "$(A_OUT)" -d "$(SAMPLE_DIR)/"



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
# gen-cases: when defined(gen) がある問題だけランダムケースを生成する
#
# grepはFILE_ABSの生テキストのみを見るため、includeされる
# template.nim内部のwhen defined(gen)とは混同しない。
# 問題ファイル自身がwhen/elif defined(gen)を書いているかだけを判定する。
# ============================================================
.PHONY: gen-cases
gen-cases:
	rm -rf "$(TEST_DIR)"
	mkdir -p "$(TEST_DIR)"
	@if grep -qE '^[[:space:]]*(when|elif)[[:space:]]+defined[[:space:]]*\([[:space:]]*gen[[:space:]]*\)' "$(FILE_ABS)"; then \
		set -e; \
		GEN_BIN="$$(mktemp)"; \
		trap 'rm -f "$$GEN_BIN"' EXIT; \
		$(NIM) cpp \
			-d:release -d:gen \
			--mm:arc --hints:off \
			--nimcache:"$(NIMCACHE_ROOT)/gen" \
			-o:"$$GEN_BIN" "$(FILE_ABS)"; \
		cd "$(ROOT)" && "$$GEN_BIN"; \
	else \
		echo "[gen-cases] $(FILE) に when/elif defined(gen) がありません → ランダムケース生成をスキップ"; \
	fi



# ============================================================
# 各テストケースの評価
#
# 重要:
# - a.out / naive.out / test はすべて絶対パスで扱う。
# - naive.out が存在して正常終了した場合は必ず比較する。
# - naive が RE / TLE なら、理由を debug.log に出す。
# - debugモードでは、AC/WAにかかわらず output と expected を
#   常に出力する（比較のため）。
# - debugモードの判定表示は oj 風の色付けを行う。
# ============================================================
define run_case
	NAME=$$(basename "$(1)" .in); \
	TMPOUT=$$(mktemp); \
	TMPERR=$$(mktemp); \
	TMPTIME=$$(mktemp); \
	TMPEXPECT=$$(mktemp); \
	TMPNAIVEERR=$$(mktemp); \
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
						for (i = 1; i <= head; i++) { \
							line = line $$i (i < head ? " " : ""); \
						} \
						line = line " ... (" (n - head - tail) " numbers) ... "; \
						start = n - tail + 1; \
						rest = ""; \
						for (i = start; i <= n; i++) { \
							rest = rest (i > start ? " " : "") $$i; \
						} \
						print line rest; \
					} else { \
						print $$0; \
					} \
				}' "$$f"; \
		fi; \
	}; \
	START=$$(date +%s%3N); \
	TL_SEC=$$(awk "BEGIN { printf \"%.3f\", ($(TL) + 500) / 1000 }"); \
	( \
		ulimit -v $$(( $(ML) * 1024 )); \
		/usr/bin/time -v -o "$$TMPTIME" \
			timeout "$${TL_SEC}s" "$(A_OUT)" < "$(1)" > "$$TMPOUT" 2> "$$TMPERR" \
	); \
	CODE=$$?; \
	END=$$(date +%s%3N); \
	ELAPSED=$$(( END - START )); \
	MAXRSS_KB=$$(grep 'Maximum resident set size' "$$TMPTIME" | awk '{ print $$NF }'); \
	MAXRSS_MB=$$(awk "BEGIN { printf \"%.3f\", $${MAXRSS_KB:-0} / 1024 }"); \
	ELAPSED_SEC=$$(awk "BEGIN { printf \"%.6f\", $$ELAPSED / 1000 }"); \
	VERDICT="RUN"; \
	if [ $$CODE -eq 124 ] || [ $$CODE -eq 137 ]; then \
		VERDICT="TLE"; \
	elif awk "BEGIN { exit !($$MAXRSS_MB > $(ML)) }"; then \
		VERDICT="MLE"; \
	elif [ $$CODE -ne 0 ]; then \
		VERDICT="RE"; \
	fi; \
	HAS_EXPECTED=0; \
	NAIVE_CODE=""; \
	if [ "$(MODE)" = "debug" ]; then \
		if [ ! -x "$(NAIVE_OUT)" ]; then \
			VERDICT="NAIVE_MISSING"; \
		else \
			timeout "$${TL_SEC}s" "$(NAIVE_OUT)" < "$(1)" > "$$TMPEXPECT" 2> "$$TMPNAIVEERR"; \
			NAIVE_CODE=$$?; \
			if [ $$NAIVE_CODE -eq 0 ]; then \
				install -m 644 "$$TMPEXPECT" "$(TEST_DIR)/$${NAME}.out"; \
				HAS_EXPECTED=1; \
				if [ "$$VERDICT" = "RUN" ]; then \
					diff -q "$$TMPOUT" "$$TMPEXPECT" > /dev/null \
						&& VERDICT="AC" \
						|| VERDICT="WA"; \
				fi; \
			else \
				VERDICT="NAIVE_RE"; \
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
			AC)             COLOR="\033[32m" ;; \
			WA)             COLOR="\033[31m" ;; \
			TLE)            COLOR="\033[33m" ;; \
			MLE)            COLOR="\033[33m" ;; \
			RE)             COLOR="\033[33m" ;; \
			NAIVE_MISSING)  COLOR="\033[36m" ;; \
			NAIVE_RE)       COLOR="\033[35m" ;; \
			*)              COLOR="\033[31m" ;; \
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
			if [ "$$VERDICT" = "NAIVE_MISSING" ]; then \
				printf "[INFO] naive.out is missing or not executable:\n"; \
				printf "[INFO] expected path: %s\n" "$(NAIVE_OUT)"; \
			fi; \
			if [ "$$VERDICT" = "NAIVE_RE" ]; then \
				printf "[INFO] naive exit code: %s\n" "$$NAIVE_CODE"; \
				if [ -s "$$TMPNAIVEERR" ]; then \
					printf "[INFO] naive stderr:\n"; \
					print_truncated "$$TMPNAIVEERR"; \
				fi; \
			fi; \
			printf "[INFO] input:\n"; \
			print_truncated "$(1)"; \
			printf "[INFO] output:\n"; \
			print_truncated "$$TMPOUT"; \
			if [ $$HAS_EXPECTED -eq 1 ]; then \
				printf "[INFO] expected:\n"; \
				print_truncated "$$TMPEXPECT"; \
			fi; \
			printf "$${COLOR}[$$VERDICT]\033[0m\n"; \
		} >> "$(OUT_TARGET)"; \
	fi; \
	rm -f "$$TMPOUT" "$$TMPERR" "$$TMPTIME" "$$TMPEXPECT" "$$TMPNAIVEERR"; \
	[ "$$VERDICT" = "RUN" ] || [ "$$VERDICT" = "AC" ]
endef



# ============================================================
# test/*.in を評価
# ============================================================
.PHONY: check-cases
check-cases:
	@if [ -z "$$(ls "$(TEST_DIR)"/*.in 2>/dev/null)" ]; then \
		echo "[check-cases] test/ が空です → ケース評価をスキップ"; \
		exit 0; \
	fi; \
	OK=0; \
	for f in "$(TEST_DIR)"/*.in; do \
		if $(call run_case,$$f); then :; else OK=1; fi; \
	done; \
	exit $$OK



# ============================================================
# 提出用コンパイル（debugなし。ジャッジサーバー相当）
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
		-o:"$(A_OUT)" "$(FILE_ABS)"



# ============================================================
# 提出
#
# サンプルは debug コンパイル（dumpあり）で確認し、
# 巨大な gen-cases はジャッジサーバー相当の debugなし
# コンパイルで判定してから提出する。
# ============================================================
.PHONY: submit
submit:
	$(MAKE) --no-print-directory compile FILE='$(FILE)'
	rm -rf "$(SAMPLE_DIR)"
	mkdir -p "$(SAMPLE_DIR)"
	$(MAKE) --no-print-directory download-sample FILE='$(FILE)' URL='$(URL)'
	$(OJ) t -c "$(A_OUT)" -d "$(SAMPLE_DIR)/"
	$(MAKE) --no-print-directory compile-submit FILE='$(FILE)'
	$(MAKE) --no-print-directory gen-cases FILE='$(FILE)'
	$(MAKE) --no-print-directory check-cases \
		MODE=submit OUT_TARGET=/dev/stdout FILE='$(FILE)'
	bash bundle.sh "$(CURDIR)" "$(abspath $(FILE))"
	@URL_VALUE="$$( $(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)' )"; \
	if $(OJ) s "$$URL_VALUE" bundled.txt -l 6072 -w 0 -y; then \
		printf "\033[32m[INFO]\033[0m oj による提出が完了しました: %s\n" "$$URL_VALUE"; \
	else \
		printf "\n"; \
		printf "\033[33m[WARN]\033[0m oj による自動提出に失敗しました（コンテスト開催中以外はCAPTCHA認証のため oj からの提出がブロックされます）。\n"; \
		printf "\033[33m[WARN]\033[0m ソースコードをクリップボードにコピーします（OSC52）。\n"; \
		if [ -n "$$TMUX" ]; then \
			tmux load-buffer -w - < bundled.txt; \
		else \
			printf '\033]52;c;%s\a' "$$(base64 < bundled.txt | tr -d '\n')"; \
		fi; \
		printf "\033[33m[WARN]\033[0m 以下のURLをブラウザで開き、手動で貼り付けて提出してください:\n"; \
		printf "  %s\n" "$$URL_VALUE"; \
	fi



# ============================================================
# デバッグ
#
# naive節のgrepは廃止。
# 常に -d:naive 版をビルドする。
# template.nim 側の elif defined(naive) も確実に有効になる。
# ============================================================
.PHONY: debug
debug: compile
	rm -f "$(DEBUG_LOG)" "$(NAIVE_OUT)"
	: > "$(DEBUG_LOG)"
	$(MAKE) --no-print-directory gen-cases FILE='$(FILE)'
	@set -e; \
	$(NIM) cpp \
		-d:release -d:naive \
		--mm:arc --hints:off \
		--nimcache:"$(NIMCACHE_ROOT)/naive" \
		-o:"$(NAIVE_OUT)" "$(FILE_ABS)" >> "$(DEBUG_LOG)" 2>&1; \
	test -x "$(NAIVE_OUT)"
	$(MAKE) --no-print-directory check-cases \
		MODE=debug OUT_TARGET="$(DEBUG_LOG)" FILE='$(FILE)' || true



# ============================================================
# アーカイブ
# ============================================================
.PHONY: archive
archive:
	@DATE="$$(date +%y-%m-%d)"; \
	if [ -z "$$(find work -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then \
	  echo "work が空です"; \
	  exit 1; \
	fi; \
	mkdir -p "../cp-solved-log/$$DATE"; \
	find work -mindepth 1 -maxdepth 1 -exec mv -t "../cp-solved-log/$$DATE" {} +