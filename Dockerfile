# 基盤イメージの読み込み
FROM base-image

WORKDIR /tmp
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime && bash -c 'echo Etc/UTC > /etc/timezone'
RUN apt-get update && apt-get install -y --no-install-recommends \
    bzip2 xz-utils lsb-release wget software-properties-common

# LLVM のインストール
RUN wget https://apt.llvm.org/llvm.sh \
 && chmod +x llvm.sh \
 && ./llvm.sh 20 all \
 && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 1 \
 && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 1 \
 && update-alternatives --install /usr/bin/python python /usr/bin/python3 1 \
 && rm llvm.sh

# Nim とライブラリのインストール
ENV CHOOSENIM_CHOOSE_VERSION=2.2.4
ENV PATH="/root/.nimble/bin:${PATH}"
RUN curl https://nim-lang.org/choosenim/init.sh -sSf | bash -s -- -y \
 && apt-get update && apt-get install -y \
    libopenblas-dev liblapack-dev \
    libgmp3-dev \
 && nimble install -y \
    neo@0.3.5 \
    https://github.com/zer0-star/Nim-ACL@0.1.0 \
    https://github.com/chaemon/bignum@1.0.6 \
    https://github.com/nim-lang/bigints@#ca00f6da386af9ad7e3abf603c0201da6a014477 \
    arraymancer@#84af537af1bc1f90229fff2b90abf5e5c1b02616 \
    regex@0.26.3 \
    nimsimd@1.3.2 \
    https://github.com/nim-lang/sat@#faf1617f44d7632ee9601ebc13887644925dcc01
RUN apt-get update && apt-get install -y python3-dev

# Boost のインストールと後片付け
RUN wget https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz \
 && tar -xf boost_1_88_0.tar.gz \
 && cd boost_1_88_0 \
 && ./bootstrap.sh --without-libraries=mpi,graph_parallel \
 && ./b2 install \
 && ldconfig \
 && cd .. \
 && rm -rf boost_1_88_0 boost_1_88_0.tar.gz
RUN apt-get update && apt-get install -y libfftw3-dev

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
RUN apt-get update && apt-get install -y libmpfr-dev

# Nim Language Server のインストール
RUN nimble install nimlangserver -y

# nph のインストール
RUN nimble install nph -y

# online-judge-tools のインストール
RUN apt-get update && apt-get install -y python3-pip time\
 && pip3 install git+https://github.com/sukenori/oj.git \
 && pip3 install aclogin

# パッケージリストキャッシュの削除
RUN rm -rf /var/lib/apt/lists/*
