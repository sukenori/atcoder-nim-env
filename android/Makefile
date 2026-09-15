# setup.sh が生成する接続・コンテナ設定を読み込む。
-include $(HOME)/.config/atcoder.conf

.PHONY: attach copy

# Android 用に分離された tmux IDE セッションへ接続
# PC 側の attach.sh に mobile を渡し、atcoder-nim-mobile セッションを使用する。
attach:
	ssh -t $(HOST) "bash $(ATTACH_SH) mobile"

# 追加:
# Android の通常ペーストを検証するため、tmuxを介さずコンテナへ入る
direct:
	ssh -tt $(HOST) "bash $(ATTACH_SH) mobile 1"

# コンテナ内の bundled.txt を取得し、Termux:API 経由で Android のシステムクリップボードへコピー（Termux の別セッションで実行のこと）
copy:
	ssh -o RequestTTY=no $(HOST) \
		"sudo -n /usr/bin/docker exec --user dev atcoder-nim /bin/cat /workspace/atcoder-nim-env/bundled.txt" \
		| termux-clipboard-set
	@echo "copied"