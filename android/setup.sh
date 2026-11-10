#!/usr/bin/env bash
# Android(Termux)用のセットアップ。PC(WSL)へ SSH でつなぐ設定と、make attach / make copy の準備をする
# 使い方(Termux で実行):
#   pkg update -y && pkg install -y git
#   git clone https://github.com/sukenori/atcoder-nim-env
#   bash ~/atcoder-nim-env/android/setup.sh

# エラー、未定義の変数、パイプの途中の失敗があれば、そこで止める
set -euo pipefail

# 必要なパッケージを入れる(openssh: SSH、termux-api: クリップボード、make: make attach / copy 用)
pkg update -y
pkg install -y openssh termux-api make

# このリポジトリの場所(このスクリプトの一つ上のフォルダ)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# SSH の設定ファイル、make 用の設定ファイル、SSH 接続の共有に使うフォルダを用意する
mkdir -p "$HOME/.ssh/sockets" "$HOME/.config"
# .ssh は自分だけが読めるようにする
chmod 700 "$HOME/.ssh"

# PC(WSL Ubuntu)のユーザー名と、Tailscale 上のホスト名を入力してもらう
printf "WSL Ubuntu のユーザー名を入力してください: "
read -r WSL_USER </dev/tty
printf "WSL Ubuntu の Tailscale hostname を入力してください: "
read -r WSL_HOST </dev/tty

# WSL を作り直すとホスト鍵が変わるため、古い記録を消す
ssh-keygen -R "$WSL_HOST" >/dev/null 2>&1 || true

# host という別名で PC につなげるようにする(ControlMaster で、attach と copy の接続を10分間使い回す)
cat > "$HOME/.ssh/config" << EOF2
Host host
    HostName ${WSL_HOST}
    User ${WSL_USER}
    KexAlgorithms curve25519-sha256
    ControlMaster auto
    ControlPersist 10m
    ControlPath ~/.ssh/sockets/%r@%h-%p
EOF2
# SSH の設定ファイルは自分だけが読み書きできるようにする
chmod 600 "$HOME/.ssh/config"

# Termux の対話シェルで、画面が消えても SSH を切れにくくする設定を .zshrc に一度だけ加える
if ! grep -qF 'ATCODER_NIM_TERMUX_WAKE_LOCK' "$HOME/.zshrc" 2>/dev/null; then
  cat >> "$HOME/.zshrc" <<'EOF2'

# ATCODER_NIM_TERMUX_WAKE_LOCK
# Android の画面消灯中でも、Termuxの対話SSHを維持しやすくする。
if [[ -n "${TERMUX_VERSION:-}" && -o interactive ]]; then
  termux-wake-lock >/dev/null 2>&1
fi
EOF2
fi

# make 用の設定を保存する(接続先の別名と、PC側の attach.sh の場所)
cat > "$HOME/.config/atcoder.conf" << EOF2
# Android 側 Makefile 用設定
HOST=host
ATTACH_SH=/home/${WSL_USER}/atcoder-nim-env/attach.sh
EOF2

# ホームで make を実行できるよう、Makefile へのリンクを作る
ln -sf "$REPO_DIR/android/Makefile" "$HOME/Makefile"

# 完了と、使えるコマンドを表示する
echo ""
echo "設定完了"
echo "  make attach ... Android 用 tmux IDE セッションへ接続"
echo "  make copy   ... bundled.txt を Android のクリップボードへコピー"
