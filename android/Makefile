# setup.sh が作った接続の設定(HOST、ATTACH_SH)を読み込む
-include $(HOME)/.config/atcoder.conf

# 同名のファイルがあっても、常にコマンドを実行する
.PHONY: attach direct copy

# PC のコンテナへ、Android 用の tmux セッション(atcoder-nim-mobile)でつなぐ
attach:
	ssh -t $(HOST) "bash $(ATTACH_SH) mobile"

# tmux を使わずに、直接コンテナへ入る(Android の通常のペーストを確認する用)
direct:
	ssh -tt $(HOST) "bash $(ATTACH_SH) mobile 1"

# コンテナ内の bundled.txt を取得し、Android のクリップボードへコピーする(Termux の別セッションで実行する)
copy:
	ssh -o RequestTTY=no $(HOST) \
		"sudo -n /usr/bin/docker exec --user dev atcoder-nim /bin/cat /workspace/atcoder-nim-env/bundled.txt" \
		| termux-clipboard-set
	@echo "copied"
