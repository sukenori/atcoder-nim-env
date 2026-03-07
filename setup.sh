#!/bin/bash

sudo apt update
sudo apt install -y podman distrobox

distrobox create --name atcoder-env --image ubuntu:22.04 --yes
distrobox enter atcoder-env

# パッケージのアップデートと基本ツールのインストール
sudo apt install -y bzip2 curl xz-utils build-essential time lsb-release wget software-properties-common gnupg libopenblas-dev liblapack-dev libgmp3-dev python3-dev libfftw3-dev libmpfr-dev python3-pip

# LLVM 20 のインストール
cd /tmp
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 20 all
sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 1
sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 1
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1

# Nim のインストール (ユーザーディレクトリに入ります)
export CHOOSENIM_CHOOSE_VERSION=2.2.4
curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
export PATH=$HOME/.nimble/bin:$PATH

# Nimble パッケージのインストール
nimble install neo@0.3.5 -y
nimble install https://github.com/zer0-star/Nim-ACL@0.1.0 -y
nimble install https://github.com/chaemon/bignum@1.0.6 -y
nimble install https://github.com/nim-lang/bigints@#ca00f6da386af9ad7e3abf603c0201da6a014477 -y
nimble install arraymancer@#84af537af1bc1f90229fff2b90abf5e5c1b02616 -y
nimble install regex@0.26.3 -y
nimble install nimsimd@1.3.2 -y
nimble install https://github.com/nim-lang/sat@#faf1617f44d7632ee9601ebc13887644925dcc01 -y

# Nim Language Server のインストール
nimble install nimlangserver -y

# Boost のビルドとインストール
cd /tmp
wget https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz
tar -xf boost_1_88_0.tar.gz
cd boost_1_88_0
./bootstrap.sh --without-libraries=mpi,graph_parallel
sudo ./b2 install
sudo ldconfig

# Eigen のインストール
cd /tmp
wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz
tar -xvf eigen-3.4.0.tar.gz
sudo cp -r eigen-3.4.0/Eigen/ eigen-3.4.0/unsupported/ /usr/local/include/

# AC Library のインストール
cd /tmp
wget https://github.com/atcoder/ac-library/archive/refs/tags/v1.5.1.tar.gz
tar -xvf v1.5.1.tar.gz
sudo cp -r ac-library-1.5.1/atcoder /usr/local/include

# online-judge-tools のインストール
sudo pip3 install git+https://github.com/sukenori/oj.git
sudo pip3 install aclogin

echo "コンテナ内の環境構築が完了しました。"

# 1. 競プロ環境のベース（atcoder-nim-env）
if [ ! -d "$HOME/atcoder-nim-env" ]; then
  git clone https://github.com/sukenori/AtCoder-Nim-Codespace.git ~/atcoder-nim-env
fi

# 2. 自作ライブラリ（nim-libraryとしてクローン）
if [ ! -d "$HOME/nim-library" ]; then
  git clone https://github.com/sukenori/Competitive_Programming_Library-Nim.git ~/nim-library
fi

# 3. 過去の解答コード（solved-codeとしてクローン）
if [ ! -d "$HOME/solved-code" ]; then
  git clone https://github.com/sukenori/Competitive_Programming-Solved_Code.git ~/solved-code
fi

