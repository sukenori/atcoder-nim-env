#!/usr/bin/env bash
set -euo pipefail

# 事前準備
# pkg update -y
# pkg install -y git
# git clone https://github.com/sukenori/atcoder-nim-env
# bash ~/atcoder-nim-env/android/setup.sh

# パッケージのインストール
pkg update -y
pkg install -y openssh termux-api make

# ディレクトリの準備
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONFIG="$HOME/.ssh/config"
CONF_FILE="$HOME/.config/atcoder.conf"
mkdir -p "$HOME/.ssh" "$HOME/.config" "$HOME/.ssh/sockets"
chmod 700 "$HOME/.ssh"

# 接続情報の入力
printf "PC 側のユーザー名を入力してください: "
read -r WIN_USER </dev/tty
printf "PC 側の Tailscale IP を入力してください: "
read -r TS_IP </dev/tty

# SSH config の生成
cat > "$SSH_CONFIG" << EOF
Host host
    HostName ${TS_IP}
    User ${WIN_USER}
    ControlMaster auto
    ControlPersist 10m
    ControlPath ~/.ssh/sockets/%r@%h-%p
EOF
chmod 600 "$SSH_CONFIG"

# Makefile用設定ファイルの生成
cat > "$CONF_FILE" << EOF
# Makefile用設定
HOST=host
ATTACH_SH=/home/sukenori/atcoder-nim-env/attach.sh
EOF

# Makefileのリンク
ln -sf "$REPO_DIR/android/Makefile" "$HOME/Makefile"

echo ""
echo "設定完了"
echo "make attach でコンテナに接続できます"