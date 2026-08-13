# setup.sh が生成する接続・コンテナ設定を読み込む。
-include $(HOME)/.config/atcoder.conf

.PHONY: attach copy

# Android 用に分離された tmux IDE セッションへ接続する。
# PC 側の attach.sh に mobile を渡し、atcoder-nim-mobile セッションを使用する。
attach:
	ssh -t $(HOST) "wsl -- bash $(ATTACH_SH) mobile"

# コンテナ内で生成済みの bundled.txt を取得し、
# Termux:API 経由で Android のシステムクリップボードへコピーする。
# このターゲットは Termux の別セッションで実行する。
copy:
	ssh -o RequestTTY=no $(HOST) \
		"wsl -- docker exec $(CONTAINER) cat $(WORKSPACE)/bundled.txt" \
		| termux-clipboard-set
	@echo "copied: $$(date +%H:%M:%S)"