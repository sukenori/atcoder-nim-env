FROM ubuntu:22.04

# AtCoder のジャッジサーバー通りにインストール
WORKDIR /tmp
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime && bash -c 'echo Etc/UTC > /etc/timezone'
RUN apt update && apt install -y bzip2 curl xz-utils build-essential git ca-certificates
RUN apt install -y lsb-release wget software-properties-common gnupg
RUN wget https://apt.llvm.org/llvm.sh
RUN chmod +x llvm.sh
RUN ./llvm.sh 20 all
RUN update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 1
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 1
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1
ENV CHOOSENIM_CHOOSE_VERSION=2.2.4
RUN curl https://nim-lang.org/choosenim/init.sh -sSf | bash -s -- -y
ENV PATH=/root/.nimble/bin:$PATH
RUN apt install libopenblas-dev liblapack-dev -y
RUN nimble install neo@0.3.5 -y
RUN nimble install https://github.com/zer0-star/Nim-ACL@0.1.0 -y
RUN apt install -y libgmp3-dev
RUN nimble install https://github.com/chaemon/bignum@1.0.6 -y
RUN nimble install https://github.com/nim-lang/bigints@#ca00f6da386af9ad7e3abf603c0201da6a014477 -y
RUN nimble install arraymancer@#84af537af1bc1f90229fff2b90abf5e5c1b02616 -y
RUN nimble install regex@0.26.3 -y
RUN nimble install nimsimd@1.3.2 -y
RUN nimble install https://github.com/nim-lang/sat@#faf1617f44d7632ee9601ebc13887644925dcc01 -y
RUN apt install -y python3-dev
RUN wget https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz
RUN tar -xf boost_1_88_0.tar.gz
WORKDIR /tmp/boost_1_88_0
RUN ./bootstrap.sh --without-libraries=mpi,graph_parallel
RUN ./b2 install
RUN ldconfig
WORKDIR /tmp
RUN apt install -y libfftw3-dev
RUN wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz
RUN tar -xvf eigen-3.4.0.tar.gz
WORKDIR /tmp/eigen-3.4.0
RUN cp -r Eigen/ unsupported/ /usr/local/include/
WORKDIR /tmp
RUN wget https://github.com/atcoder/ac-library/archive/refs/tags/v1.5.1.tar.gz
RUN tar -xvf v1.5.1.tar.gz
RUN cp -r ac-library-1.5.1/atcoder /usr/local/include
RUN apt install -y libmpfr-dev

# Nim Language Server をインストール
RUN nimble install nimlangserver -y

# online-judge-tools をインストール
RUN apt install -y python3-pip &&\
    #pip3 install online-judge-tools
    pip3 install git+https://github.com/sukenori/oj.git &&\
    pip install aclogin