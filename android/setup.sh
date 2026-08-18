#!/usr/bin/env bash
set -euo pipefail

# 事前準備
# pkg update -y
# pkg install -y git
# git clone https://github.com/sukenori/atcoder-nim-env
# bash ~/atcoder-nim-env/android/setup.sh

# Android の Termux で使用するパッケージをインストールする。
# termux-api は termux-clipboard-set、make は make attach / make copy 用。
pkg update -y
pkg install -y openssh termux-api make

# リポジトリと設定ファイルのパスを定義する。
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONFIG="$HOME/.ssh/config"
CONF_FILE="$HOME/.config/atcoder.conf"

# SSH 設定、Makefile 設定、ControlMaster のソケット用ディレクトリを作成する。
mkdir -p "$HOME/.ssh" "$HOME/.config" "$HOME/.ssh/sockets"
chmod 700 "$HOME/.ssh"

# host という別名で PC 側へ接続できるようにする。
# ControlMaster により、attach と copy の SSH 接続を再利用する。
cat > "$SSH_CONFIG" << EOF
Host host
    HostName ${WSL_HOST}
    User ${WSL_USER}
    ControlMaster auto
    ControlPersist 10m
    ControlPath ~/.ssh/sockets/%r@%h-%p
EOF
chmod 600 "$SSH_CONFIG"

# Android 側 Makefile が使用する設定を保存する。
# ATTACH_SH、CONTAINER、WORKSPACE は WSL 側から見たパス・名前である。
cat > "$CONF_FILE" << EOF
# Android 側 Makefile 用設定
HOST=host
ATTACH_SH=/home/${WSL_USER}/atcoder-nim-env/attach.sh
EOF

# Termux のホームディレクトリで make を実行できるようにする。
ln -sf "$REPO_DIR/android/Makefile" "$HOME/Makefile"

echo ""
echo "設定完了"
echo "  make attach ... Android 用 tmux IDE セッションへ接続"
echo "  make copy   ... bundled.txt を Android のクリップボードへコピー"