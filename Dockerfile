# 基盤イメージの読み込み
FROM base-image

SHELL ["/bin/bash", "-c"]

USER root
WORKDIR /tmp

RUN apt-get update && apt-get install -y \
      bzip2 xz-utils lsb-release wget software-properties-common \
      build-essential \
      libfftw3-dev \
      libmpfr-dev \
      libopenblas-dev liblapack-dev libgmp3-dev \
      python3-dev \
      time

# パッケージリストキャッシュの削除
RUN rm -rf /var/lib/apt/lists/*

# LLVM のインストール
RUN wget https://apt.llvm.org/llvm.sh \
 && chmod +x llvm.sh \
 && ./llvm.sh 20 all \
 && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 1 \
 && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 1 \
 && rm -f llvm.sh

# Boost のインストールと後片付け
RUN wget https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz \
 && tar -xf boost_1_88_0.tar.gz \
 && cd boost_1_88_0 \
 && ./bootstrap.sh --without-libraries=mpi,graph_parallel \
 && ./b2 install \
 && ldconfig \
 && cd /tmp \
 && rm -rf boost_1_88_0 boost_1_88_0.tar.gz

# Eigen のインストールと後片付け
RUN wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz \
 && tar -xvf eigen-3.4.0.tar.gz \
 && cp -r eigen-3.4.0/Eigen/ eigen-3.4.0/unsupported/ /usr/local/include/ \
 && rm -rf eigen-3.4.0 eigen-3.4.0.tar.gz

# ac-library のインストールと後片付け
RUN wget https://github.com/atcoder/ac-library/archive/refs/tags/v1.5.1.tar.gz \
 && tar -xvf v1.5.1.tar.gz \
 && cp -r ac-library-1.5.1/atcoder /usr/local/include/ \
 && rm -rf ac-library-1.5.1 v1.5.1.tar.gz

# online-judge-tools のインストール
RUN pip3 install git+https://github.com/sukenori/oj.git \
 && pip3 install aclogin

# コンテナ内開発ユーザーを定義（DEV_UID / DEV_GID は Compose 実行時に WSL の id -u / id -g から受け取る）
ARG DEV_USER=dev
ARG DEV_UID
ARG DEV_GID

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

# dev: user-local な Nim toolchain と Nimble packages をインストール
USER ${DEV_USER}
ENV HOME=/home/${DEV_USER}

ENV CHOOSENIM_CHOOSE_VERSION=2.2.4
ENV PATH=${HOME}/.local/bin:${HOME}/.nimble/bin:${PATH}

WORKDIR /workspace/atcoder-nim-env
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

# Nim Language Server のインストール
RUN nimble install nimlangserver -y

# nph のインストール
RUN nimble install nph -y

# 最終 image の既定ユーザーと既定作業場所
USER ${DEV_USER}
WORKDIR /workspace/atcoder-nim-env