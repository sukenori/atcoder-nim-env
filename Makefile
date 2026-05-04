# BASH_REMATCH 変数を使うので、bash を使う
SHELL := /usr/bin/env bash

# 対象ファイルを手入力したいときは FILE=... で指定する
FILE ?=
# URL を手入力したいときは URL=... で渡す
URL ?=

# コンテナ内で直接実行する
NIM ?= /root/.nimble/bin/nim
OJ ?= oj

# デフォルトターゲット
.DEFAULT_GOAL := make

# URL を解決して表示
.PHONY: print-url
print-url:
# URL= があればそれを優先する
# 省略時は FILE 名 (abc447d.nim / ARC447D.nim など) から推測する
# ファイル名だけ取り出し → 小文字に変換し → .nimを取り除き → コンテスト名とアンダーバー付きの問題 ID を取得する
	@if [ -n "$(URL)" ]; then \
		echo "$(URL)"; \
	else \
		BASENAME="$$(basename "$(FILE)")"; \
		STEM="$$(echo "$$BASENAME" | tr '[:upper:]' '[:lower:]')"; \
		STEM="$${STEM%.nim}"; \
		if [[ "$$STEM" =~ ^([a-z]+[0-9]+)([a-z])$$ ]]; then \
			CONTEST="$${BASH_REMATCH[1]}"; \
			TASK_LETTER="$${BASH_REMATCH[2]}"; \
			TASK_ID="$${CONTEST}_$${TASK_LETTER}"; \
			echo "https://atcoder.jp/contests/$${CONTEST}/tasks/$${TASK_ID}"; \
		else \
			echo "cannot infer AtCoder URL from filename: $(FILE)" >&2; \
			exit 1; \
		fi; \
	fi

# ビルド
.PHONY: build
build:
	$(NIM) \
		cpp \
		-d:release \
		-d:debug \
		-d:useMalloc \
		--mm:arc \
		--multimethods:on \
		--warning[SmallLshouldNotBeUsed]:off \
		--colors:on \
		--hints:off \
		--maxLoopIterationsVM:10000000000000 \
		--maxCallDepthVM:10000000000000 \
		--rangeChecks:on \
		--boundChecks:on \
		--overflowChecks:on \
		--stackTrace:on \
		--passC:-Wno-alloc-size-larger-than \
		--passL:-Wno-alloc-size-larger-than \
		-g \
		-o:a.out \
		"$(FILE)"

# 実行
.PHONY: run
run: build
	./a.out

# テストケース取得
.PHONY: download-test
download-test:
	rm -rf test
	mkdir -p test
# --no-print-directory でシステムメッセージを出さずに、print-url の出力を取り込む
	@URL_VALUE="$$( $(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)' )"; \
	$(OJ) d "$$URL_VALUE" -d test -s

# テスト
.PHONY: test
test: build download-test
	$(OJ) t -c ./a.out -d test/

# bundle（include を展開して 1 ファイルにまとめる）
.PHONY: bundle
bundle:
	bash bundle.sh "$(CURDIR)" "$(abspath $(FILE))"

# submit（テスト → bundle → 提出）
.PHONY: submit
submit: build download-test test bundle
	@URL_VALUE="$$( $(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)' )"; \
	$(OJ) s "$$URL_VALUE" bundled.txt -l 6072 -w 0 -y

# 日付フォルダへアーカイブ
# work ディレクトリを深さ 1 で検索し、何かあればそのファイル名を返して検索終了
# 空でなければ、cp-solved-log に日付のディレクトリを作って中身をコピー、diff があれば、commit して push
.PHONY: archive
archive:
	@DATE="$$(date +%y-%m-%d)"; \
	if [ -z "$$(find work -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then \
		echo "work が空です"; \
		exit 1; \
	fi; \
	mkdir -p "../cp-solved-log/$$DATE"; \
	cp -a work/. "../cp-solved-log/$$DATE/"; \
	cd ../cp-solved-log && \
	git add "$$DATE" && \
	if git diff --cached --quiet; then \
		echo "追加差分がないため commit/push はスキップします"; \
	else \
		git commit -m "archive $$DATE" && git push; \
	fi