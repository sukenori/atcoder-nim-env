# setup.sh が生成する接続・コンテナ設定を読み込む
-include $(HOME)/.config/atcoder.conf

.PHONY: attach copy

# Android 用に分離された tmux IDE セッションへ接続する
attach:
	ssh -t $(HOST) "wsl -- bash $(ATTACH_SH) mobile"

# コンテナ内の bundled.txt を取得し、Termux:API 経由で Android のシステムクリップボードへコピーする（Termux の別セッションを用いること）
copy:
	ssh -o RequestTTY=no $(HOST) \
		"wsl -- docker exec $(CONTAINER) cat $(WORKSPACE)/bundled.txt" \
		| termux-clipboard-set
	@echo "copied: $$(date +%H:%M:%S)"