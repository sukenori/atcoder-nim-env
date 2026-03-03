NIM = ~/.nimble/bin/nim
NIM_FLAGS = cpp -d:release -d:debug -d:useMalloc --mm:arc --multimethods:on \\
--warning[SmallLshouldNotBeUsed]:off --hints:off \\
--maxLoopIterationsVM:10000000000000 --maxCallDepthVM:10000000000000 \\
--rangeChecks:on --boundChecks:on --overflowChecks:on \\
--passC:-Wno-alloc-size-larger-than --passL:-Wno-alloc-size-larger-than \\
-g -o:a.out
DATE = $(shell date +%Y-%m-%d)

# abc234d.nim のようなファイル名からURLを推測するための文字列処理
BASENAME = $(basename $(notdir $(FILE))
CONTEST = $(shell echo $(BASENAME) | sed 's/.$$//')
TASK_CHAR = $(shell echo $(BASENAME) | sed 's/.*\(.\)$$/\1/')
AUTO_URL = https://atcoder.jp/contests/$(CONTEST)/tasks/$(CONTEST)_$(TASK_CHAR)

.PHONY: build test bundle submit-auto submit-url archive clean

# 1. 単純なコンパイル
build:
	$(NIM) $(NIM_FLAGS) $(FILE)

# テスト実行（提出コマンドから呼ばれる）
test: build
	rm -rf test
	oj d $(URL) -d test -s
	oj t -c ./a.out -d test/

# バンドル処理（提出コマンドから呼ばれる）
bundle:
	bash bundle.sh . $(FILE)
	mv -f bundled.txt work/bundled.txt 2>/dev/null || true

# 2. ファイル名類推での提出 (URL変数を自動生成したものに上書き)
submit-auto: URL = $(AUTO_URL)
submit-auto: test bundle
	oj s $(URL) bundled.txt -l 6072 -w 0 -y

# 3. URL指定（クリップボード等）での提出
submit-url: test bundle
	oj s $(URL) bundled.txt -l 6072 -w 0 -y

# 4. 机の上の片付け (一時ファイルの削除とnimファイルのアーカイブ)
archive: clean
	mkdir -p $(DATE)
	mv *.nim $(DATE)/ 2>/dev/null || true

