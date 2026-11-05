# AtCoder 用の Nim 開発・提出用 Makefile
# 使い方の例: make compile FILE=work/abc212c.nim

# recipe(各ターゲットの命令)を bash で実行する。print-url が bash の正規表現機能を使うため
SHELL := /usr/bin/env bash

# 対象の Nim ファイル(make 実行時に FILE=... で渡す)
FILE ?=
# 問題の URL。空なら、ファイル名(abc212c.nim)から自動で決める
URL ?=
# Nim コンパイラのコマンド
NIM ?= nim
# 問題を解くテストツール oj のコマンド
OJ ?= oj
# 実行時間の制限(ミリ秒)
TL ?= 2000
# メモリの制限(MB)
ML ?= 1024

# このプロジェクトのフォルダ(make を実行した場所)
ROOT := $(CURDIR)
# FILE を絶対パスにしたもの
FILE_ABS := $(abspath $(FILE))
# ランダムケースと、その正解を置くフォルダ
TEST_DIR := $(ROOT)/test
# oj が取得したサンプルを置くフォルダ
SAMPLE_DIR := $(ROOT)/sample
# コンパイルした自分の解答の実行ファイル
A_OUT := $(ROOT)/a.out
# 愚直解(正解を出す遅い解法)の実行ファイル
NAIVE_OUT := $(ROOT)/naive.out
# debug の結果を書き出すログ
DEBUG_LOG := $(ROOT)/debug.log
# Nim のコンパイル途中の生成物を置く場所
NIMCACHE_ROOT ?= /tmp/nimcache-$(notdir $(CURDIR))

# どちらの設定でも共通のコンパイルオプション(C++ へ変換、最適化、ARC、再帰やループの上限緩和など)
NIM_COMMON := cpp -d:release -d:useMalloc --mm:arc --multimethods:on \
	--warning[SmallLshouldNotBeUsed]:off --colors:on --hints:off \
	--maxLoopIterationsVM:10000000000000 --maxCallDepthVM:10000000000000 \
	--passC:-Wno-alloc-size-larger-than --passL:-Wno-alloc-size-larger-than

# 引数なしで make を実行したときは compile を行う
.DEFAULT_GOAL := compile


# ---------- 問題 URL を表示する ----------
# URL が指定されていればそれを、なければファイル名 abc212c.nim から
# https://atcoder.jp/contests/abc212/tasks/abc212_c を作って表示する
.PHONY: print-url
print-url:
	@if [ -n "$(URL)" ]; then echo "$(URL)"; else \
		STEM="$$(basename "$(FILE)" .nim | tr '[:upper:]' '[:lower:]')"; \
		if [[ "$$STEM" =~ ^([a-z]+[0-9]+)([a-z])$$ ]]; then \
			echo "https://atcoder.jp/contests/$${BASH_REMATCH[1]}/tasks/$${BASH_REMATCH[1]}_$${BASH_REMATCH[2]}"; \
		else echo "cannot infer AtCoder URL from filename: $(FILE)" >&2; exit 1; fi; \
	fi


# ---------- コンパイル(確認用) ----------
# デバッグ出力(dump)と、範囲外アクセスやオーバーフローの検査を有効にして a.out を作る
.PHONY: compile
compile:
	$(NIM) $(NIM_COMMON) -d:debug \
		--rangeChecks:on --boundChecks:on --overflowChecks:on --stackTrace:on \
		--nimcache:"$(NIMCACHE_ROOT)/compile" -o:"$(A_OUT)" "$(FILE_ABS)"

# ---------- コンパイル(提出と同じ設定) ----------
# デバッグ出力も検査もなしで a.out を作る。AtCoder のジャッジに近い
.PHONY: compile-submit
compile-submit:
	$(NIM) $(NIM_COMMON) \
		--nimcache:"$(NIMCACHE_ROOT)/submit" -o:"$(A_OUT)" "$(FILE_ABS)"


# ---------- サンプル ----------
# 問題ページからサンプルを取得し直して sample フォルダに置く
.PHONY: download-sample
download-sample:
	rm -rf "$(SAMPLE_DIR)"
	mkdir -p "$(SAMPLE_DIR)"
	$(OJ) d "$$($(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)')" -d "$(SAMPLE_DIR)" -s

# コンパイルし、サンプルを取得して、a.out をサンプルで試す
.PHONY: sample
sample: compile download-sample
	$(OJ) t -c "$(A_OUT)" -d "$(SAMPLE_DIR)/"


# ---------- バンドル ----------
# include を展開して 1 ファイルにまとめ(bundled.txt)、クリップボードへ送る
# tmux の中では tmux のバッファへ、外では端末の OSC52 という仕組みで送る
.PHONY: bundle
bundle:
	bash bundle.sh "$(CURDIR)" "$(FILE_ABS)"
	@if [ -n "$$TMUX" ]; then tmux load-buffer -w - < bundled.txt; \
	else printf '\033]52;c;%s\a' "$$(base64 < bundled.txt | tr -d '\n')"; fi


# ---------- ランダムケースの生成 ----------
# 問題ファイル自身に when defined(gen) などがあるときだけ、-d:gen 付きでビルドして実行し、test フォルダに入力を作る
.PHONY: gen-cases
gen-cases:
	rm -rf "$(TEST_DIR)"
	mkdir -p "$(TEST_DIR)"
	@if grep -qE '^[[:space:]]*(when|elif)[[:space:]]+defined[[:space:]]*\([[:space:]]*gen[[:space:]]*\)' "$(FILE_ABS)"; then \
		mkdir -p "$(NIMCACHE_ROOT)" && $(NIM) cpp -d:release -d:gen --mm:arc --hints:off \
			--nimcache:"$(NIMCACHE_ROOT)/gen" -o:"$(NIMCACHE_ROOT)/gen.out" "$(FILE_ABS)" \
		&& cd "$(ROOT)" && "$(NIMCACHE_ROOT)/gen.out"; \
	else echo "[gen-cases] defined(gen) がないため、ランダムケース生成をスキップ"; fi


# ---------- test/*.in を 1 つずつ評価 ----------
# MODE が submit か debug か、結果の出力先 OUT_TARGET は呼び出し側が渡す。1 つでも失敗すれば失敗で終わる
# 1 ケースの評価は scripts/run_case.sh が行う
.PHONY: check-cases
check-cases:
	@if ! ls "$(TEST_DIR)"/*.in > /dev/null 2>&1; then echo "[check-cases] test/ が空のためスキップ"; exit 0; fi; \
	status=0; \
	for f in "$(TEST_DIR)"/*.in; do \
		bash "$(ROOT)/scripts/run_case.sh" "$$f" "$(MODE)" "$(OUT_TARGET)" \
			"$(A_OUT)" "$(NAIVE_OUT)" "$(TEST_DIR)" "$(TL)" "$(ML)" || status=1; \
	done; \
	exit $$status


# ---------- 提出前の検証 ----------
# scripts/cp_archive.py の submit から呼ばれる。順に
# 1 確認用ビルド 2 サンプル取得 3 サンプル実行 4 提出用ビルド 5 ランダムケース生成 6 ケース評価
.PHONY: submit-check
submit-check:
	$(MAKE) --no-print-directory compile FILE='$(FILE)'
	$(MAKE) --no-print-directory download-sample FILE='$(FILE)' URL='$(URL)'
	$(OJ) t -c "$(A_OUT)" -d "$(SAMPLE_DIR)/"
	$(MAKE) --no-print-directory compile-submit FILE='$(FILE)'
	$(MAKE) --no-print-directory gen-cases FILE='$(FILE)'
	$(MAKE) --no-print-directory check-cases MODE=submit OUT_TARGET=/dev/stdout FILE='$(FILE)'


# ---------- 提出 ----------
# 検証、日時付きの保存、バンドル、提出、採点結果の回収開始までを scripts/cp_archive.py が行う
.PHONY: submit
submit:
	python3 "$(ROOT)/scripts/cp_archive.py" submit --file "$(FILE_ABS)" --url "$(URL)" \
		--make "$(MAKE)" --oj "$(OJ)" --nim "$(NIM)" --tl "$(TL)" --ml "$(ML)"


# ---------- デバッグ ----------
# 自分の解答と、-d:naive でビルドした愚直解を、ランダムケースで比べて debug.log に書く
.PHONY: debug
debug: compile
	rm -f "$(DEBUG_LOG)" "$(NAIVE_OUT)"
	: > "$(DEBUG_LOG)"
	$(MAKE) --no-print-directory gen-cases FILE='$(FILE)'
	$(NIM) cpp -d:release -d:naive --mm:arc --hints:off \
		--nimcache:"$(NIMCACHE_ROOT)/naive" -o:"$(NAIVE_OUT)" "$(FILE_ABS)" >> "$(DEBUG_LOG)" 2>&1
	$(MAKE) --no-print-directory check-cases MODE=debug OUT_TARGET="$(DEBUG_LOG)" FILE='$(FILE)' || true


# ---------- アーカイブ関係(処理は scripts/cp_archive.py) ----------
# work のコードを、正解コードとして隣の cp-solved-log/問題名.nim に複製する
.PHONY: promote
promote:
	python3 "$(ROOT)/scripts/cp_archive.py" promote --file "$(FILE_ABS)"

# cp-solved-log 内の採点待ちのファイルを、いますぐ回収する(通常は自動で回収される)
.PHONY: archive-sync
archive-sync:
	python3 "$(ROOT)/scripts/cp_archive.py" sync

# work の中身を、確認なしですべて削除する
.PHONY: all-clear
all-clear:
	python3 "$(ROOT)/scripts/cp_archive.py" all-clear
