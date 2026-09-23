# Build environment for portable Linux builds of the Linguini extension.
#
# Ubuntu 22.04 sets the glibc baseline (2.35). OpenSSL, Opus, expat, curl and
# FFmpeg are built from source as position-independent static libraries
# (Ubuntu's own .a files aren't PIC) with only what Linguini uses. The finished
# extension needs only glibc and libva (VA-API) from the user's system.
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config nasm python3 python3-pip ca-certificates curl xz-utils file binutils \
        libva-dev perl \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir scons==4.10.1

ARG OPENSSL_VERSION=3.5.4
ARG OPUS_VERSION=1.5.2
ARG EXPAT_VERSION=2.7.3
ARG FFMPEG_VERSION=7.1.2
ARG CURL_VERSION=8.16.0
ENV DEPS=/deps
ENV PKG_CONFIG_PATH=/deps/lib/pkgconfig
WORKDIR /tmp/deps

RUN curl -fsSL https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz | tar -xz \
    && cd openssl-${OPENSSL_VERSION} \
    && ./Configure linux-x86_64 --prefix=$DEPS --libdir=lib no-shared no-tests no-docs no-apps no-module -fPIC \
    && make -j"$(nproc)" build_libs && make install_dev \
    && mkdir -p $DEPS/licenses/openssl && cp LICENSE.txt $DEPS/licenses/openssl/ \
    && cd .. && rm -rf openssl-${OPENSSL_VERSION}

RUN curl -fsSL https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz | tar -xz \
    && cd opus-${OPUS_VERSION} \
    && ./configure --prefix=$DEPS --enable-static --disable-shared --with-pic --disable-doc --disable-extra-programs \
    && make -j"$(nproc)" && make install \
    && mkdir -p $DEPS/licenses/opus && cp COPYING $DEPS/licenses/opus/ \
    && cd .. && rm -rf opus-${OPUS_VERSION}

RUN curl -fsSL https://github.com/libexpat/libexpat/releases/download/R_$(echo ${EXPAT_VERSION} | tr . _)/expat-${EXPAT_VERSION}.tar.xz | tar -xJ \
    && cd expat-${EXPAT_VERSION} \
    && ./configure --prefix=$DEPS --enable-static --disable-shared --with-pic --without-docbook --without-examples --without-tests --without-xmlwf \
    && make -j"$(nproc)" && make install \
    && mkdir -p $DEPS/licenses/expat && cp COPYING $DEPS/licenses/expat/ \
    && cd .. && rm -rf expat-${EXPAT_VERSION}

# FFmpeg: H.264 / HEVC / AV1 decoders and parsers, VA-API hardware decoding.
RUN curl -fsSL https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz | tar -xJ \
    && cd ffmpeg-${FFMPEG_VERSION} \
    && ./configure --prefix=$DEPS --enable-static --disable-shared --enable-pic \
        --disable-autodetect --disable-programs --disable-doc --disable-network --disable-everything \
        --disable-avformat --disable-avdevice --disable-avfilter --disable-swscale --disable-swresample \
        --enable-decoder=h264,hevc,av1 --enable-parser=h264,hevc,av1 \
        --enable-vaapi --enable-hwaccel=h264_vaapi,hevc_vaapi,av1_vaapi \
    && make -j"$(nproc)" && make install \
    && mkdir -p $DEPS/licenses/ffmpeg && cp COPYING.LGPLv2.1 LICENSE.md $DEPS/licenses/ffmpeg/ \
    && cd .. && rm -rf ffmpeg-${FFMPEG_VERSION}

# curl: HTTP(S) over OpenSSL only, for talking to the host.
RUN curl -fsSL https://curl.se/download/curl-${CURL_VERSION}.tar.xz | tar -xJ \
    && cd curl-${CURL_VERSION} \
    && ./configure --prefix=$DEPS --enable-static --disable-shared --with-pic --with-openssl=$DEPS \
        --without-zlib --without-brotli --without-zstd --without-libpsl --without-libidn2 \
        --without-nghttp2 --without-libssh2 --disable-ldap --disable-ldaps --disable-rtsp \
        --disable-dict --disable-telnet --disable-tftp --disable-pop3 --disable-imap --disable-smtp \
        --disable-gopher --disable-mqtt --disable-smb --disable-ftp --disable-file --disable-docs \
        --disable-manual --disable-ntlm --disable-kerberos-auth --disable-negotiate-auth \
    && make -j"$(nproc)" && make install \
    && mkdir -p $DEPS/licenses/curl && cp COPYING $DEPS/licenses/curl/ \
    && cd .. && rm -rf curl-${CURL_VERSION}

WORKDIR /work
