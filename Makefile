# ===========================================================================
# Makefile — AtCoder Nim 実行環境の操作をまとめた司令塔
#
# 使い方:
#   make build FILE=work/abc999_a.nim        … コンパイルだけ
#   make submit-auto FILE=work/abc999_a.nim  … テスト＋提出（URL自動推測）
#   make submit-url  FILE=work/abc999_a.nim URL=https://...  … URL指定で提出
#   make archive                             … 解いたコードを日付フォルダに整理
# ===========================================================================

# ---------------------------------------------------------------------------
# Distrobox コンテナ経由でコマンドを実行するためのプレフィックス
# （ホスト側からこの Makefile を呼び、コンテナ内の nim / oj を使う）
# ---------------------------------------------------------------------------
CONTAINER  = atcoder-env
DISTROBOX  = distrobox enter $(CONTAINER) --
NIM        = $(DISTROBOX) nim
OJ         = $(DISTROBOX) oj

# ---------------------------------------------------------------------------
# Nim コンパイルオプション（AtCoder の Nim 提出環境に合わせたフラグ）
# ---------------------------------------------------------------------------
NIM_FLAGS = cpp \
  -d:release -d:debug -d:useMalloc \
  --mm:arc --multimethods:on \
  --warning[SmallLshouldNotBeUsed]:off --hints:off \
  --maxLoopIterationsVM:10000000000000 \
  --maxCallDepthVM:10000000000000 \
  --rangeChecks:on --boundChecks:on --overflowChecks:on \
  --passC:-Wno-alloc-size-larger-than \
  --passL:-Wno-alloc-size-larger-than \
  -g -o:a.out

# ---------------------------------------------------------------------------
# パス・日付など共通変数
# ---------------------------------------------------------------------------
ARCHIVE_REPO = ../solved-code
DATE         = $(shell date +%y-%m-%d)

# ファイル名からコンテスト URL を自動推測する
#   例: work/abc999_a.nim → コンテスト=abc999, 問題=a
BASENAME  = $(basename $(notdir $(FILE)))
CONTEST   = $(shell echo $(BASENAME) | sed 's/.$$//')
TASK_CHAR = $(shell echo $(BASENAME) | sed 's/.*\(.\)$$/\1/')
AUTO_URL  = https://atcoder.jp/contests/$(CONTEST)/tasks/$(CONTEST)_$(TASK_CHAR)

# ---------------------------------------------------------------------------
# ターゲット一覧
# ---------------------------------------------------------------------------
.PHONY: build test bundle submit-auto submit-url archive

# コンパイル
build:
	$(NIM) $(NIM_FLAGS) $(FILE)

# テスト（コンパイル → サンプルケースDL → 実行比較）
test: build
	$(DISTROBOX) rm -rf test
	$(OJ) d $(URL) -d test -s
	$(OJ) t -c ./a.out -d test/

# バンドル（include を展開して1ファイルにまとめる）
bundle:
	$(DISTROBOX) bash bundle.sh . $(FILE)

# テスト＋提出（URL をファイル名から自動推測）
submit-auto: URL = $(AUTO_URL)
submit-auto: test bundle
	$(OJ) s $(URL) bundled.txt -l 6072 -w 0 -y

# テスト＋提出（URL を手動で渡す）
submit-url: test bundle
	$(OJ) s $(URL) bundled.txt -l 6072 -w 0 -y

# 解いたコードを日付ごとのフォルダへ移動し、git push する
archive:
	mkdir -p $(ARCHIVE_REPO)/Journal/$(DATE)
	mv work/*.nim $(ARCHIVE_REPO)/Journal/$(DATE)/ 2>/dev/null || true
	cd $(ARCHIVE_REPO) && git add Journal/$(DATE) && git commit -m "Archive $(DATE)" && git push

