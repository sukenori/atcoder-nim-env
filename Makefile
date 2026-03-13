# bash を使う
SHELL := /usr/bin/env bash

# 対象ファイル（FILE=... で指定する）
FILE ?=

# URL を手入力したいときは URL=... を渡す
URL ?=

# 実行コンテナ設定（.nvim.lua の nimlangserver 起動先と合わせる）
CONTAINER_NAME ?= atcoder-nim
CONTAINER_WORKDIR ?= /home/sukenori/atcoder-nim-env
DOCKER_EXEC ?= docker exec -i -w $(CONTAINER_WORKDIR) $(CONTAINER_NAME)
NIM ?= $(DOCKER_EXEC) /root/.nimble/bin/nim
OJ ?= $(DOCKER_EXEC) oj

# デフォルトターゲット
.DEFAULT_GOAL := help

# ヘルプ表示
.PHONY: help
help:
	@echo "使い方:"
	@echo "  make build   FILE=work/abc447d.nim"
	@echo "  make test    FILE=work/abc447d.nim [URL=...]"
	@echo "  make bundle  FILE=work/abc447d.nim"
	@echo "  make submit  FILE=work/abc447d.nim [URL=...]"
	@echo "  make archive"
	@echo ""
	@echo "URL を省略した場合は FILE 名から URL を推測します。"

# FILE があるかチェック
.PHONY: check-file
check-file:
	@if [ -z "$(FILE)" ]; then \
		echo "FILE=... を指定してください"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "ファイルが見つかりません: $(FILE)"; \
		exit 1; \
	fi

# コンテナが起動済みかチェック
.PHONY: check-container
check-container:
	@if ! docker ps --format '{{.Names}}' | grep -Fxq "$(CONTAINER_NAME)"; then \
		echo "$(CONTAINER_NAME) が起動していません。./setup.sh か docker compose up -d --build を実行してください"; \
		exit 1; \
	fi

# URL を解決して表示
# 1) URL= があればそれを優先する
# 2) 省略時は FILE 名 (abc447d.nim など) から推測する
# 3) 受け付ける形式: abc447d / abc447_d / arc192a
.PHONY: print-url
print-url: check-file
	@if [ -n "$(URL)" ]; then \
		echo "$(URL)"; \
	else \
		BASENAME="$$(basename "$(FILE)")"; \
		STEM="$${BASENAME%.nim}"; \
		STEM="$$(echo "$$STEM" | tr '[:upper:]' '[:lower:]')"; \
		if [[ "$$STEM" =~ ^([a-z]+[0-9]+)_?([a-z])$$ ]]; then \
			CONTEST="$${BASH_REMATCH[1]}"; \
			TASK_LETTER="$${BASH_REMATCH[2]}"; \
			TASK_ID="$${CONTEST}_$${TASK_LETTER}"; \
			echo "https://atcoder.jp/contests/$${CONTEST}/tasks/$${TASK_ID}"; \
		else \
			echo "cannot infer AtCoder URL from filename: $(FILE)" >&2; \
			echo "example supported names: abc447d.nim, abc447_d.nim, arc192a.nim" >&2; \
			exit 1; \
		fi; \
	fi
# ビルド
.PHONY: build
build: check-file check-container
	$(NIM) \
		cpp \
		-d:release \
		-d:debug \
		-d:useMalloc \
		--mm:arc \
		--multimethods:on \
		--warning[SmallLshouldNotBeUsed]:off \
		--hints:off \
		--maxLoopIterationsVM:10000000000000 \
		--maxCallDepthVM:10000000000000 \
		--rangeChecks:on \
		--boundChecks:on \
		--overflowChecks:on \
		--passC:-Wno-alloc-size-larger-than \
		--passL:-Wno-alloc-size-larger-than \
		-g \
		-o:a.out \
		"$(FILE)"

# 実行
.PHONY: run
run: build
	$(DOCKER_EXEC) ./a.out

# テストケース取得
.PHONY: download-test
download-test: check-file check-container
	rm -rf test
	mkdir -p test
	@URL_VALUE="$$( $(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)' )"; \
	$(OJ) d "$$URL_VALUE" -d test -s

# テスト
.PHONY: test
test: build download-test
	$(OJ) t -c ./a.out -d test/

# bundle（include 展開して 1 ファイルにまとめる）
.PHONY: bundle
bundle: check-file
	bash bundle.sh . "$(FILE)"

# submit（テスト → bundle → 提出）
.PHONY: submit
submit: build download-test test bundle check-container
	@URL_VALUE="$$( $(MAKE) --no-print-directory print-url FILE='$(FILE)' URL='$(URL)' )"; \
	$(OJ) s "$$URL_VALUE" bundled.txt -l 6072 -w 0 -y

# 日付フォルダへ保存
.PHONY: archive
archive:
	@DATE="$$(date +%F)"; \
	if [ -z "$$(find work -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then \
		echo "work が空です"; \
		exit 1; \
	fi; \
	mkdir -p "cp-solved-log/$$DATE"; \
	cp -a work/. "cp-solved-log/$$DATE/"; \
	cd cp-solved-log && \
	git add "$$DATE" && \
	if git diff --cached --quiet; then \
		echo "追加差分がないため commit/push はスキップします"; \
	else \
		git commit -m "archive $$DATE" && git push; \
	fi
