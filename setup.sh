#!/bin/bash
set -e
sed -i 's/\r$//' "$0" # 改行コードエラー防止

# --- 1. あなたの競プロ資産（リポジトリ）の自動クローン ---
echo "=== 1. 競プロ用リポジトリのクローン（ホスト側） ==="

# 競プロ環境のベース（※このスクリプト自体が含まれるリポジトリ）
if [ ! -d "$HOME/atcoder-nim-env" ]; then
  git clone https://github.com/sukenori/AtCoder-Nim-Codespace.git ~/atcoder-nim-env
fi

# 自作ライブラリ
if [ ! -d "$HOME/nim-library" ]; then
  git clone https://github.com/sukenori/Competitive_Programming_Library-Nim.git ~/nim-library
fi

# 過去の解答コード
if [ ! -d "$HOME/solved-code" ]; then
  git clone https://github.com/sukenori/Competitive_Programming-Solved_Code.git ~/solved-code
fi

# --- 2. Distroboxコンテナの作成 ---
CONTAINER_NAME="atcoder-env"
echo "=== 2. Distroboxコンテナ ($CONTAINER_NAME) の作成 ==="
if ! distrobox list | grep -q "$CONTAINER_NAME"; then
  distrobox create --name $CONTAINER_NAME --image ubuntu:22.04 --yes
else
  echo "コンテナは既に存在します。"
fi

# --- 3. コンテナ内部でのツール構築（一括実行） ---
echo "=== 3. コンテナ内へのNim環境セットアップ ==="
distrobox enter $CONTAINER_NAME -- bash -c '
set -e

echo "--- パッケージ更新と基本ツールのインストール ---"
sudo apt update
sudo apt install -y bzip2 curl xz-utils build-essential time lsb-release wget software-properties-common gnupg libopenblas-dev liblapack-dev libgmp3-dev python3-dev libfftw3-dev libmpfr-dev python3-pip

echo "--- LLVM 20 のインストール ---"
cd /tmp
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 20 all
sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 1
sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 1
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1

echo "--- Nim と nimlangserver のインストール ---"
export CHOOSENIM_CHOOSE_VERSION=2.2.4
curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
export PATH=$HOME/.nimble/bin:$PATH

nimble install -y nimlangserver
nimble install -y neo@0.3.5 https://github.com/zer0-star/Nim-ACL@0.1.0 https://github.com/chaemon/bignum@1.0.6 https://github.com/nim-lang/bigints@#ca00f6da386af9ad7e3abf603c0201da6a014477 arraymancer@#84af537af1bc1f90229fff2b90abf5e5c1b02616 regex@0.26.3 nimsimd@1.3.2 https://github.com/nim-lang/sat@#faf1617f44d7632ee9601ebc13887644925dcc01

echo "--- Boost, Eigen, AC Library のインストール ---"
cd /tmp
wget https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz && tar -xf boost_1_88_0.tar.gz
cd boost_1_88_0 && ./bootstrap.sh --without-libraries=mpi,graph_parallel && sudo ./b2 install && sudo ldconfig

cd /tmp
wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz && tar -xf eigen-3.4.0.tar.gz
sudo cp -r eigen-3.4.0/Eigen/ eigen-3.4.0/unsupported/ /usr/local/include/

cd /tmp
wget https://github.com/atcoder/ac-library/archive/refs/tags/v1.5.1.tar.gz && tar -xf v1.5.1.tar.gz
sudo cp -r ac-library-1.5.1/atcoder /usr/local/include

echo "--- online-judge-tools のインストール ---"
sudo pip3 install git+https://github.com/sukenori/oj.git --break-system-packages
sudo pip3 install aclogin --break-system-packages

echo "--- コンテナ内の環境構築が完了しました ---"
'

echo "=== AtCoder環境 ($CONTAINER_NAME) と資産の構築がすべて完了しました ==="
