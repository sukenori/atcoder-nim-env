#!/bin/bash
# ===========================================================================
# setup.sh — AtCoder Nim 環境を Distrobox コンテナ内に構築するスクリプト
#
# 前提: ホスト側に Distrobox (+ Podman) がインストール済みであること
#       （ホスト側のセットアップは dotfiles/linux/setup.sh が担当）
#
# このスクリプトが行うこと:
#   1. "atcoder-env" という名前の Distrobox コンテナを作成する
#   2. コンテナ内に Nim / nimlangserver / 競プロ用ライブラリ一式をインストールする
#   3. ホスト側に nimlangserver ラッパーと tmux 起動スクリプトを配置する
#   4. コンテナ内に online-judge-tools (oj) をインストールし、補助リポジトリを配置する
#
# Distrobox の特徴:
#   - ホスト側の $HOME がそのままコンテナ内にマウントされる
#   - つまりホスト側の ~/atcoder-nim-env や ~/nim-library がコンテナ内からも見える
#   - ホスト側の Neovim からは、ラッパー経由で nimlangserver をそのまま起動できる
# ===========================================================================
set -euo pipefail

# --- 1. Distrobox コンテナの作成 ---
CONTAINER_NAME="atcoder-env"
echo "=== 1/4 Distrobox コンテナ ($CONTAINER_NAME) の作成 ==="
if ! distrobox list | grep -q "$CONTAINER_NAME"; then
  distrobox create --name "$CONTAINER_NAME" --image ubuntu:22.04 --yes
else
  echo "  → コンテナは作成済みです。スキップします。"
fi

# --- 2. コンテナ内部で環境を構築する ---
echo "=== 2/4 コンテナ内での環境構築を開始 ==="
distrobox enter "$CONTAINER_NAME" -- bash -s << 'EOF'
set -e

echo "--- apt パッケージのインストール ---"
sudo apt update
sudo apt install -y \
  git bzip2 curl xz-utils build-essential time \
  lsb-release wget software-properties-common gnupg \
  libopenblas-dev liblapack-dev libgmp3-dev \
  python3-dev libfftw3-dev libmpfr-dev python3-pip

echo "--- LLVM 20 (clang / clang++) のインストール ---"
cd /tmp
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 20 all
sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 1
sudo update-alternatives --install /usr/bin/clang   clang   /usr/bin/clang-20  1
sudo update-alternatives --install /usr/bin/python  python  /usr/bin/python3   1

echo "--- Nim (choosenim) と nimlangserver のインストール ---"
export CHOOSENIM_CHOOSE_VERSION=2.2.4
curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
export PATH="$HOME/.nimble/bin:$PATH"
nimble install -y nimlangserver
nimble install -y \
  neo@0.3.5 \
  https://github.com/zer0-star/Nim-ACL@0.1.0 \
  https://github.com/chaemon/bignum@1.0.6 \
  https://github.com/nim-lang/bigints@#ca00f6da386af9ad7e3abf603c0201da6a014477 \
  arraymancer@#84af537af1bc1f90229fff2b90abf5e5c1b02616 \
  regex@0.26.3 nimsimd@1.3.2 \
  https://github.com/nim-lang/sat@#faf1617f44d7632ee9601ebc13887644925dcc01

echo "--- Boost / Eigen / AC Library のインストール ---"
cd /tmp
wget https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz && tar -xf boost_1_88_0.tar.gz
cd boost_1_88_0 && ./bootstrap.sh --without-libraries=mpi,graph_parallel && sudo ./b2 install && sudo ldconfig

cd /tmp
wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz && tar -xf eigen-3.4.0.tar.gz
sudo cp -r eigen-3.4.0/Eigen/ eigen-3.4.0/unsupported/ /usr/local/include/

cd /tmp
wget https://github.com/atcoder/ac-library/archive/refs/tags/v1.5.1.tar.gz && tar -xf v1.5.1.tar.gz
sudo cp -r ac-library-1.5.1/atcoder /usr/local/include

echo "--- online-judge-tools (oj) のインストール ---"
sudo pip3 install git+https://github.com/sukenori/oj.git --break-system-packages
sudo pip3 install aclogin --break-system-packages

echo "=== コンテナ内の環境構築が完了しました ==="
EOF

echo "=== 3/4 ホスト側の補助スクリプト配置 ==="
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/atcoder-nim-env/bin/dev" "$HOME/.local/bin/dev-atcoder"
ln -sf "$HOME/atcoder-nim-env/bin/nimlangserver" "$HOME/.local/bin/nimlangserver"
chmod +x "$HOME/atcoder-nim-env/bin/dev"
chmod +x "$HOME/atcoder-nim-env/bin/nimlangserver"
chmod +x "$HOME/atcoder-nim-env/bin/dev-tmux"

echo "=== 4/4 競プロ用リポジトリのクローン ==="
# Distrobox は $HOME を共有するので、ホスト側でクローンすれば OK
if [ ! -d "$HOME/nim-library" ]; then
  git clone https://github.com/sukenori/Competitive_Programming_Library-Nim.git "$HOME/nim-library"
else
  echo "  → nim-library は取得済みです。"
fi

if [ ! -d "$HOME/solved-code" ]; then
  git clone https://github.com/sukenori/Competitive_Programming-Solved_Code.git "$HOME/solved-code"
else
  echo "  → solved-code は取得済みです。"
fi

echo "=== AtCoder 環境のセットアップが完了しました ==="
echo ""
echo "使い方:"
echo "  cd ~/atcoder-nim-env"
echo "  ./bin/dev"
echo "  make build FILE=work/abc999_a.nim"
echo "  make submit-auto FILE=work/abc999_a.nim"
