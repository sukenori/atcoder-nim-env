# --- コンテナ操作用の司令塔設定 ---
DOCKER = docker exec -w /workspace/env atcoder-nim
NIM = $(DOCKER) /root/.nimble/bin/nim
OJ = $(DOCKER) oj

# --- コンパイルオプション (1行) ---
NIM_FLAGS = cpp -d:release -d:debug -d:useMalloc --mm:arc --multimethods:on --warning[SmallLshouldNotBeUsed]:off --hints:off --maxLoopIterationsVM:10000000000000 --maxCallDepthVM:10000000000000 --rangeChecks:on --boundChecks:on --overflowChecks:on --passC:-Wno-alloc-size-larger-than --passL:-Wno-alloc-size-larger-than -g -o:a.out

# --- WSL側の設定 ---
ARCHIVE_REPO = ../solved-code
DATE = $(shell date +%y-%m-%d)

# ファイル名からURLを推測
BASENAME = $(basename $(notdir $(FILE)))
CONTEST = $(shell echo $(BASENAME) | sed 's/.$$//')
TASK_CHAR = $(shell echo $(BASENAME) | sed 's/.*\(.\)$$/\1/')
AUTO_URL = https://atcoder.jp/contests/$(CONTEST)/tasks/$(CONTEST)_$(TASK_CHAR)

.PHONY: build test bundle submit-auto submit-url archive clean

build:
	$(NIM) $(NIM_FLAGS) $(FILE)

test: build
	$(DOCKER) rm -rf test
	$(OJ) d $(URL) -d test -s
	$(OJ) t -c ./a.out -d test/

bundle:
	$(DOCKER) bash bundle.sh . $(FILE)
	mv -f bundled.txt work/bundled.txt 2>/dev/null || true

submit-auto: URL = $(AUTO_URL)
submit-auto: test bundle
	$(OJ) s $(URL) work/bundled.txt -l 6072 -w 0 -y

submit-url: test bundle
	$(OJ) s $(URL) work/bundled.txt -l 6072 -w 0 -y

archive:
	mkdir -p $(ARCHIVE_REPO)/Journal/$(DATE)
	mv work/*.nim $(ARCHIVE_REPO)/Journal/$(DATE)/ 2>/dev/null || true
	cd $(ARCHIVE_REPO) && git add Journal/$(DATE) && git commit -m "Archive $(DATE)" && git push

