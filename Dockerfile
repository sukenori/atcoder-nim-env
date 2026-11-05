# AtCoder 用の開発イメージ。基盤イメージに C++ の道具、Python の oj、Nim と nph、nimlangserver を加える

# 基盤イメージを読み込む
FROM base-image

# RUN の中のコマンドを bash で実行する
SHELL ["/bin/bash", "-c"]

# 以降の作業は root で行い、作業場所は /tmp にする
USER root
WORKDIR /tmp

# ビルドと数値計算に必要なパッケージを入れる
RUN apt-get update && apt-get install -y \
      # 圧縮ファイルの展開、取得、ビルドの道具
      bzip2 xz-utils lsb-release wget software-properties-common \
      build-essential \
      # 数値計算のライブラリ
      libfftw3-dev \
      libmpfr-dev \
      libopenblas-dev liblapack-dev libgmp3-dev \
      # Python の拡張を作るためのヘッダ
      python3-dev \
      # 実行時間を測る time コマンド
      time

# パッケージの一覧のキャッシュを消す
RUN rm -rf /var/lib/apt/lists/*

# LLVM 20 を入れ、clang と clang++ をその版に向ける
RUN wget https://apt.llvm.org/llvm.sh \
 && chmod +x llvm.sh \
 && ./llvm.sh 20 all \
 && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 1 \
 && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 1 \
 && rm -f llvm.sh

# Boost 1.88.0 をビルドして入れ、作業用のファイルを消す
RUN wget https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz \
 && tar -xf boost_1_88_0.tar.gz \
 && cd boost_1_88_0 \
 && ./bootstrap.sh --without-libraries=mpi,graph_parallel \
 && ./b2 install \
 && ldconfig \
 && cd /tmp \
 && rm -rf boost_1_88_0 boost_1_88_0.tar.gz

# Eigen 3.4.0 のヘッダを入れ、作業用のファイルを消す
RUN wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz \
 && tar -xvf eigen-3.4.0.tar.gz \
 && cp -r eigen-3.4.0/Eigen/ eigen-3.4.0/unsupported/ /usr/local/include/ \
 && rm -rf eigen-3.4.0 eigen-3.4.0.tar.gz

# AtCoder Library(C++) 1.5.1 のヘッダを入れ、作業用のファイルを消す
RUN wget https://github.com/atcoder/ac-library/archive/refs/tags/v1.5.1.tar.gz \
 && tar -xvf v1.5.1.tar.gz \
 && cp -r ac-library-1.5.1/atcoder /usr/local/include/ \
 && rm -rf ac-library-1.5.1 v1.5.1.tar.gz

# online-judge-tools(oj、自分の修正版)と aclogin を入れる
RUN pip3 install git+https://github.com/sukenori/oj.git \
 && pip3 install aclogin
# oj の API クライアントを直す修正スクリプトを持ち込む
COPY patch-api-client-mib.py /tmp/patch-api-client-mib.py
# 修正を適用して、スクリプトを消す
RUN python3 /tmp/patch-api-client-mib.py \
 && rm /tmp/patch-api-client-mib.py

# 開発用ユーザーの名前を決める
ARG DEV_USER=dev
# ユーザーの UID と GID は、docker compose が WSL の id -u / id -g から渡す
ARG DEV_UID
ARG DEV_GID

# 渡された UID と GID でグループとユーザーを作り、/workspace をそのユーザーのものにする
RUN test -n "${DEV_UID}" \
 && test -n "${DEV_GID}" \
 && groupadd --gid "${DEV_GID}" "${DEV_USER}" \
 && useradd --uid "${DEV_UID}" \
            --gid "${DEV_GID}" \
            --create-home \
            --shell /bin/zsh \
            "${DEV_USER}" \
 && mkdir -p /workspace \
 && chown "${DEV_UID}:${DEV_GID}" /workspace

# 以降は開発用ユーザーで作業し、ホームの場所と Nim の版、PATH を決める
USER ${DEV_USER}
ENV HOME=/home/${DEV_USER}

ENV CHOOSENIM_CHOOSE_VERSION=2.2.4
ENV PATH=${HOME}/.local/bin:${HOME}/.nimble/bin:${PATH}

# 作業場所をプロジェクトのフォルダにする
WORKDIR /workspace/atcoder-nim-env
# Nim 2.2.4 を入れ、競プロ用のパッケージを決まった版で入れる
RUN curl https://nim-lang.org/choosenim/init.sh -sSf | bash -s -- -y \
 && nimble install -y \
    neo@0.3.5 \
    https://github.com/zer0-star/Nim-ACL@0.1.0 \
    https://github.com/chaemon/bignum@1.0.6 \
    https://github.com/nim-lang/bigints@#ca00f6da386af9ad7e3abf603c0201da6a014477 \
    arraymancer@#84af537af1bc1f90229fff2b90abf5e5c1b02616 \
    regex@0.26.3 \
    nimsimd@1.3.2 \
    https://github.com/nim-lang/sat@#faf1617f44d7632ee9601ebc13887644925dcc01

# nimlangserver(Nim の言語サーバー)を、公式のビルド済みバイナリで入れる。インストールは root で行う
USER root
ARG NIMLANGSERVER_VERSION=1.16.0
RUN set -eu; \
    tmp="$(mktemp -d)"; \
    curl -fsSL "https://github.com/nim-lang/langserver/releases/download/v${NIMLANGSERVER_VERSION}/nimlangserver-linux-amd64.tar.gz" -o "$tmp/server.tar.gz"; \
    tar -xzf "$tmp/server.tar.gz" -C "$tmp"; \
    binary="$(find "$tmp" -type f -name nimlangserver -print -quit)"; \
    test -n "$binary"; \
    install -m 0755 "$binary" /usr/local/bin/nimlangserver; \
    rm -rf "$tmp"
USER dev

# nph(Nim の整形ツール)を入れる
ARG NPH_VERSION=v0.7.0
RUN curl -fsSL "https://github.com/arnetheduck/nph/releases/download/${NPH_VERSION}/nph-linux_x64.tar.gz" -o /tmp/nph.tar.gz \
 && tar -xzf /tmp/nph.tar.gz -C /tmp \
 && install -m 0755 /tmp/nph "${HOME}/.nimble/bin/nph" \
 && rm -f /tmp/nph.tar.gz /tmp/nph

# 最終的な既定のユーザーと作業場所を決める
USER ${DEV_USER}
WORKDIR /workspace/atcoder-nim-env
