# Build image: the official Swift toolchain of the SAME version (used as the
# bootstrap compiler and as the native build machine toolchain) plus the
# official Static Linux SDK (musl sysroot + static Swift runtime).
ARG SWIFT_VERSION=6.4.2
FROM swift:${SWIFT_VERSION}
ARG SWIFT_VERSION=6.4.2
ARG STATIC_SDK_VERSION=0.1.0
ARG STATIC_SDK_CHECKSUM=3786b179936d9cc9e266dd506bd1654176358d7b25288e243359f4d17cc4dc5a
RUN apt-get update -qq && apt-get install -y -qq cmake ninja-build python3 python3-setuptools \
      libicu-dev libxml2-dev libcurl4-openssl-dev libsqlite3-dev libncurses-dev uuid-dev libedit-dev \
      libpython3-dev rsync git pkg-config zip unzip zstd >/tmp/apt.log 2>&1 || (tail -30 /tmp/apt.log; false)
RUN swift sdk install \
      https://download.swift.org/swift-${SWIFT_VERSION}-release/static-sdk/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE_static-linux-${STATIC_SDK_VERSION}.artifactbundle.tar.gz \
      --checksum ${STATIC_SDK_CHECKSUM}
# A second copy of the aarch64 musl SDK at a fixed path: sysroot for the CMake
# cross builds (the copy under ~/.swiftpm is the one `swift build --swift-sdk` uses).
RUN mkdir -p /usr/local/musl && \
    cp -a "$(dirname "$(dirname "$(dirname "$(find /root/.swiftpm -name libc.a -path '*aarch64*' | head -1)")")")" /usr/local/musl/aarch64 && \
    test -f /usr/local/musl/aarch64/usr/lib/libc.a
# build-script expects cc/c++ to be clang
RUN ln -sf /usr/bin/clang /usr/bin/cc && ln -sf /usr/bin/clang++ /usr/bin/c++
