# setup.sh が生成する接続・コンテナ設定を読み込む。
-include $(HOME)/.config/atcoder.conf

.PHONY: attach copy

# Android 用に分離された tmux IDE セッションへ接続
# PC 側の attach.sh に mobile を渡し、atcoder-nim-mobile セッションを使用する。
attach:
	ssh -t $(HOST) "wsl -- bash $(ATTACH_SH) mobile"

# コンテナ内の bundled.txt を取得し、Termux:API 経由で Android のシステムクリップボードへコピー（Termux の別セッションで実行のこと）
copy:
	ssh -o RequestTTY=no $(HOST) \
		"wsl -- sudo -n /usr/local/sbin/atcoder-copy-bundled" \
		| termux-clipboard-set
	@echo "copied"