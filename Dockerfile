# First Stage: protoc_builder
FROM alpine:3.7 as protoc_builder

RUN apk add --no-cache \
    build-base \
    curl \
    automake \
    autoconf \
    libtool \
    git \
    zlib-dev \
    go

ENV GRPC_VERSION=1.8.3 \
    GRPC_JAVA_VERSION=1.8.0 \
    PROTOBUF_VERSION=3.5.1 \
    PROTOBUF_C_VERSION=1.3.0 \
    PROTOC_GEN_DOC_VERSION=1.1.0 \
    OUTDIR=/out \
    GOPATH=/go \
    PATH=/go/bin/:$PATH

RUN mkdir -p /protobuf \
    && sh -c 'curl -L https://github.com/google/protobuf/archive/v${PROTOBUF_VERSION}.tar.gz | tar xvz --strip-components=1 -C /protobuf' \
    && git clone --depth 1 --recursive -b v${GRPC_VERSION} https://github.com/grpc/grpc.git /grpc \
    && rm -rf grpc/third_party/protobuf \
    && ln -s /protobuf /grpc/third_party/protobuf \
    && mkdir -p /grpc-java \
    && sh -c 'curl -L https://github.com/grpc/grpc-java/archive/v${GRPC_JAVA_VERSION}.tar.gz | tar xvz --strip-components=1 -C /grpc-java' \
    && mkdir -p /protobuf-c \
    && sh -c 'curl -L https://github.com/protobuf-c/protobuf-c/releases/download/v${PROTOBUF_C_VERSION}/protobuf-c-${PROTOBUF_C_VERSION}.tar.gz | tar xvz --strip-components=1 -C /protobuf-c' \
    && cd /protobuf \
    && autoreconf -f -i -Wall,no-obsolete \
    && ./configure --prefix=/usr --enable-static=no \
    && make -j2 \
    && make install \
    && cd /grpc \
    && make -j2 plugins \
    && cd /grpc-java/compiler/src/java_plugin/cpp \
    && g++ \
       -I. -I/protobuf/src \
       *.cpp \
       -L/protobuf/src/.libs \
       -lprotoc -lprotobuf -lpthread --std=c++0x -s \
       -o protoc-gen-grpc-java \
    && cd /protobuf-c \
    && ./configure --prefix=/usr \
    && make -j2 \
    && cd /protobuf \
    && make install DESTDIR=${OUTDIR} \
    && cd /grpc \
    && make install-plugins prefix=${OUTDIR}/usr \
    && cd /grpc-java/compiler/src/java_plugin/cpp \
    && install -c protoc-gen-grpc-java ${OUTDIR}/usr/bin/ \
    && cd /protobuf-c \
    && make install DESTDIR=${OUTDIR} \
    && find ${OUTDIR} -name "*.a" -delete -or -name "*.la" -delete \
    && go get -u -v -ldflags '-w -s' \
       github.com/Masterminds/glide \
       github.com/golang/protobuf/protoc-gen-go \
       github.com/gogo/protobuf/protoc-gen-gofast \
       github.com/gogo/protobuf/protoc-gen-gogo \
       github.com/gogo/protobuf/protoc-gen-gogofast \
       github.com/gogo/protobuf/protoc-gen-gogofaster \
       github.com/gogo/protobuf/protoc-gen-gogoslick \
       github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger \
       github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway \
       github.com/johanbrandhorst/protobuf/protoc-gen-gopherjs \
       github.com/ckaznocha/protoc-gen-lint \
     && install -c ${GOPATH}/bin/protoc-gen* ${OUTDIR}/usr/bin/ \
     && mkdir -p ${GOPATH}/src/github.com/pseudomuto/protoc-gen-doc \
     && sh -c 'curl -L https://github.com/pseudomuto/protoc-gen-doc/archive/v${PROTOC_GEN_DOC_VERSION}.tar.gz | tar xvz --strip 1 -C ${GOPATH}/src/github.com/pseudomuto/protoc-gen-doc' \
     && cd ${GOPATH}/src/github.com/pseudomuto/protoc-gen-doc \
     && make build \
     && install -c ${GOPATH}/src/github.com/pseudomuto/protoc-gen-doc/protoc-gen-doc ${OUTDIR}/usr/bin/

# Second Stage: Swift Builder
FROM ubuntu:16.04 as swift_builder

ENV SWIFT_VERSION=4.0.3 \
    LLVM_VERSION=5.0.1 \
    SWIFT_PROTOBUF_VERSION=1.0.3

RUN apt-get update \
    && apt-get install -y \
       build-essential \
       make \
       tar \
       xz-utils \
       bzip2 \
       gzip \
       sed \
       libz-dev \
       unzip \
       patchelf \
       curl \
       libedit-dev \
       python2.7 \
       python2.7-dev \
       libxml2 \
       git \
       libxml2-dev \
       uuid-dev \
       libssl-dev \
       bash \
       patch \
       libcurl4-openssl-dev \
    && sh -c 'curl -L http://releases.llvm.org/${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-16.04.tar.xz | tar --strip-components 1 -C /usr/local/ -xJv' \
    && sh -c 'curl -L https://swift.org/builds/swift-${SWIFT_VERSION}-release/ubuntu1604/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu16.04.tar.gz | tar --strip-components 1 -C / -xz' \
    && mkdir -p /swift-protobuf \
    && sh -c 'curl -L https://github.com/apple/swift-protobuf/archive/${SWIFT_PROTOBUF_VERSION}.tar.gz | tar --strip-components 1 -C /swift-protobuf -xz' \
    && cd /swift-protobuf \
    && swift build -c release \
    && mkdir -p /protoc-gen-swift \
    && cp /swift-protobuf/.build/x86_64-unknown-linux/release/protoc-gen-swift /protoc-gen-swift/ \
    && cp /lib64/ld-linux-x86-64.so.2 $(ldd /protoc-gen-swift/protoc-gen-swift | awk '{print $3}' | grep /lib | sort | uniq) /protoc-gen-swift/ \
    && find /protoc-gen-swift/ -name 'lib*.so*' -exec patchelf --set-rpath /protoc-gen-swift {} \; \
    && for p in protoc-gen-swift; do patchelf --set-interpreter /protoc-gen-swift/ld-linux-x86-64.so.2 /protoc-gen-swift/${p}; done

# Third Stage: Rust Builder
FROM rust:1.22.1 as rust_builder

ENV RUST_PROTOBUF_VERSION=1.4.3 \
    OUTDIR=/out

RUN mkdir -p ${OUTDIR} \
    && apt-get update \
    && apt-get install -y \
       musl-tools \
    && rustup target add x86_64-unknown-linux-musl \
    && mkdir -p /rust-protobuf \
    && sh -c 'curl -L https://github.com/stepancheg/rust-protobuf/archive/v${RUST_PROTOBUF_VERSION}.tar.gz | tar xvz --strip 1 -C /rust-protobuf' \
    && cd /rust-protobuf/protobuf \
    && RUSTFLAGS='-C linker=musl-gcc' cargo build --target=x86_64-unknown-linux-musl --release \
    && mkdir -p ${OUTDIR}/usr/bin \
    && strip /rust-protobuf/target/x86_64-unknown-linux-musl/release/protoc-gen-rust \
    && install -c /rust-protobuf/target/x86_64-unknown-linux-musl/release/protoc-gen-rust ${OUTDIR}/usr/bin/

# Fourth Stage: Packer
FROM znly/upx as packer

COPY --from=protoc_builder /out/ /out/

RUN upx --lzma \
        /out/usr/bin/protoc \
        /out/usr/bin/grpc_* \
        /out/usr/bin/protoc-gen-*

# Fifth and last Stage: Base
FROM debian:stretch

COPY --from=packer /out/ /
COPY --from=rust_builder /out/ /
COPY --from=swift_builder /protoc-gen-swift /protoc-gen-swift

RUN for p in protoc-gen-swift protoc-gen-swiftgrpc; do ln -s /protoc-gen-swift/${p} /usr/bin/${p}; done \
    && apt-get update \
    && apt-get install --no-install-recommends -t jessie-backports -y \
       curl \
       python-pip \
    && mkdir -p /protobuf/google/protobuf \
    && for f in any duration descriptor empty struct timestamp wrappers; do curl -L -o /protobuf/google/protobuf/${f}.proto https://raw.githubusercontent.com/google/protobuf/master/src/google/protobuf/${f}.proto; done \
    && mkdir -p /protobuf/google/api \
    && for f in annotations http; do curl -L -o /protobuf/google/api/${f}.proto https://raw.githubusercontent.com/grpc-ecosystem/grpc-gateway/master/third_party/googleapis/google/api/${f}.proto; done \
    && mkdir -p /protobuf/github.com/gogo/protobuf/gogoproto \
    && curl -L -o /protobuf/github.com/gogo/protobuf/gogoproto/gogo.proto https://raw.githubusercontent.com/gogo/protobuf/master/gogoproto/gogo.proto \
    && pip install jinja2
