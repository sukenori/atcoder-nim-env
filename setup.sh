#!/usr/bin/env bash
# setup.sh — atcoder-nim-env のローカル開発環境を構築する
# 目的: Nim / oj / ライブラリ / 作業ディレクトリを一度に整える
set -euo pipefail
# -e: 失敗したら止める
# -u: 未定義変数を禁止
# -o pipefail: パイプ途中の失敗も拾う

# このスクリプト自身のディレクトリを作業ルートにする
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# PATH を整える
# nimble のバイナリと pip --user のバイナリを PATH に入れる
touch "$HOME/.bashrc"
grep -Fqx 'export PATH="$HOME/.nimble/bin:$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || \
  echo 'export PATH="$HOME/.nimble/bin:$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

touch "$HOME/.zshrc"
grep -Fqx 'export PATH="$HOME/.nimble/bin:$HOME/.local/bin:$PATH"' "$HOME/.zshrc" || \
  echo 'export PATH="$HOME/.nimble/bin:$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"

# 今このスクリプト中でも有効にする
export PATH="$HOME/.nimble/bin:$HOME/.local/bin:$PATH"

# タイムゾーンを Asia/Tokyo にする
sudo ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
echo "Asia/Tokyo" | sudo tee /etc/timezone >/dev/null

# APT の索引を更新する
sudo apt-get update

# Dockerfile 相当の基本パッケージを入れる
sudo apt-get install -y bzip2 curl xz-utils build-essential git time
sudo apt-get install -y lsb-release wget software-properties-common gnupg

# LLVM 20 を入れて clang / clang++ を切り替える
cd /tmp
wget -q https://apt.llvm.org/llvm.sh
chmod +x /tmp/llvm.sh
sudo /tmp/llvm.sh 20 all
sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 1
sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 1
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1

# choosenim と Nim を入れる
# nim がまだ無ければ choosenim で入れる
if ! command -v nim >/dev/null 2>&1; then
  export CHOOSENIM_CHOOSE_VERSION="2.2.4"
  curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
  export PATH="$HOME/.nimble/bin:$HOME/.local/bin:$PATH"
fi

# 数値計算系の依存を入れる
sudo apt-get install -y libopenblas-dev liblapack-dev
sudo apt-get install -y libgmp3-dev
sudo apt-get install -y python3-dev
sudo apt-get install -y python3-pip
sudo apt-get install -y libfftw3-dev
sudo apt-get install -y libmpfr-dev

# pip を更新する
# Python ツールを user 領域に入れる準備
PIP_USER_ARGS=(--user)
if python3 -m pip install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
  PIP_USER_ARGS+=(--break-system-packages)
fi
python3 -m pip install "${PIP_USER_ARGS[@]}" --upgrade pip

# Python ツールを入れる
# oj と aclogin を user 領域へ入れる
python3 -m pip install "${PIP_USER_ARGS[@]}" \
  git+https://github.com/sukenori/oj.git \
  aclogin

# Nim ライブラリを入れる
nimble install neo@0.3.5 -y
nimble install https://github.com/zer0-star/Nim-ACL@0.1.0 -y
nimble install https://github.com/chaemon/bignum@1.0.6 -y
nimble install https://github.com/nim-lang/bigints@#ca00f6da386af9ad7e3abf603c0201da6a014477 -y
nimble install arraymancer@#84af537af1bc1f90229fff2b90abf5e5c1b02616 -y
nimble install regex@0.26.3 -y
nimble install nimsimd@1.3.2 -y
nimble install https://github.com/nim-lang/sat@#faf1617f44d7632ee9601ebc13887644925dcc01 -y
nimble install nimlangserver -y

# Boost を入れる
cd /tmp
wget -q https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz
tar -xf /tmp/boost_1_88_0.tar.gz
cd /tmp/boost_1_88_0
./bootstrap.sh --without-libraries=mpi,graph_parallel
sudo ./b2 install
sudo ldconfig

# Eigen を入れる
cd /tmp
wget -q https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz
tar -xvf /tmp/eigen-3.4.0.tar.gz
sudo cp -r /tmp/eigen-3.4.0/Eigen /tmp/eigen-3.4.0/unsupported /usr/local/include/

# AtCoder Library を入れる
cd /tmp
wget -q https://github.com/atcoder/ac-library/archive/refs/tags/v1.5.1.tar.gz
tar -xvf /tmp/v1.5.1.tar.gz
sudo cp -r /tmp/ac-library-1.5.1/atcoder /usr/local/include

# リポジトリを clone する
# cp-nim-lib repo を clone
if [ -d "./cp-nim-lib/.git" ]; then
  if ! git -C ./cp-nim-lib rev-parse --verify HEAD >/dev/null 2>&1; then
    rm -rf ./cp-nim-lib
    git clone https://github.com/sukenori/Competitive_Programming_Library-Nim.git ./cp-nim-lib
  fi
else
  git clone https://github.com/sukenori/Competitive_Programming_Library-Nim.git ./cp-nim-lib
fi

# cp-solved-log repo を clone
if [ ! -d "./cp-solved-log/.git" ]; then
  git clone https://github.com/sukenori/cp-solved-log.git ./cp-solved-log
fi

# 作業ディレクトリを作る
# 作業用ディレクトリ群を作る
mkdir -p ./work
mkdir -p ./test

# 補助スクリプトの実行権限を整える
# 補助スクリプトを実行可能にする
[ -f ./bundle.sh ] && chmod +x ./bundle.sh
