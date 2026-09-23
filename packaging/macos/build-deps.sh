#!/usr/bin/env bash
# Static dependencies for the macOS release build, for one architecture.
#
#   packaging/macos/build-deps.sh ARCH PREFIX      # ARCH: arm64 or x86_64
#
# The macOS counterpart of packaging/linux/Dockerfile. It uses the same versions
# and cuts each library down the same way. OpenSSL, Opus, expat, FFmpeg and curl
# are built from source as static libraries for macOS 11+. FFmpeg decodes
# H.264, HEVC and AV1, with VideoToolbox hardware decoding for H.264 and HEVC
# (FFmpeg 7.1 has none for AV1). Licences go in PREFIX/licenses.
#
# Both architectures build on either kind of Mac. x86_64 FFmpeg needs nasm.
# A finished PREFIX is reused until this script changes.
set -euo pipefail

OPENSSL_VERSION=3.5.4
OPUS_VERSION=1.5.2
EXPAT_VERSION=2.7.3
FFMPEG_VERSION=7.1.2
CURL_VERSION=8.16.0
MIN_MACOS=11.0

ARCH="${1:?usage: build-deps.sh arm64|x86_64 PREFIX}"
PREFIX="${2:?usage: build-deps.sh arm64|x86_64 PREFIX}"
case "$ARCH" in
    arm64) HOST=aarch64-apple-darwin ;;
    x86_64) HOST=x86_64-apple-darwin ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
mkdir -p "$PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"

stamp="$PREFIX/.build-deps-$(shasum -a 256 "$0" | cut -c1-16)"
if [[ -f "$stamp" ]]; then
    echo "Static dependencies for $ARCH are up to date in $PREFIX"
    exit 0
fi
rm -rf "$PREFIX" && mkdir -p "$PREFIX/licenses"

# Build only against the prefix, whatever Homebrew has installed.
unset CPPFLAGS LDFLAGS LIBS CPATH LIBRARY_PATH C_INCLUDE_PATH PKG_CONFIG_PATH
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
ARCH_FLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS"
JOBS=$(sysctl -n hw.ncpu)
# autotools projects
CONFIGURE=(--host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared --with-pic)
export CC=clang CFLAGS="$ARCH_FLAGS -O2" LDFLAGS="$ARCH_FLAGS"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

fetch() { curl -fsSL "$1" | tar -x${2}f -; }
step() { printf '\n==> [%s] %s\n' "$ARCH" "$*"; }

step "OpenSSL $OPENSSL_VERSION"
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" z
(
    cd "openssl-$OPENSSL_VERSION"
    # The darwin64-* targets pass -arch themselves.
    env -u CFLAGS -u LDFLAGS ./Configure "darwin64-$ARCH-cc" --prefix="$PREFIX" --libdir=lib \
        no-shared no-tests no-docs no-apps no-module "-mmacosx-version-min=$MIN_MACOS" >/dev/null 2>&1
    make -j"$JOBS" build_libs >/dev/null && make install_dev >/dev/null
    mkdir -p "$PREFIX/licenses/openssl" && cp LICENSE.txt "$PREFIX/licenses/openssl/"
)

step "Opus $OPUS_VERSION"
fetch "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" z
(
    cd "opus-$OPUS_VERSION"
    ./configure "${CONFIGURE[@]}" --disable-doc --disable-extra-programs >/dev/null
    make -j"$JOBS" >/dev/null && make install >/dev/null
    mkdir -p "$PREFIX/licenses/opus" && cp COPYING "$PREFIX/licenses/opus/"
)

step "expat $EXPAT_VERSION"
fetch "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}/expat-$EXPAT_VERSION.tar.xz" J
(
    cd "expat-$EXPAT_VERSION"
    ./configure "${CONFIGURE[@]}" --without-docbook --without-examples --without-tests --without-xmlwf >/dev/null
    make -j"$JOBS" >/dev/null && make install >/dev/null
    mkdir -p "$PREFIX/licenses/expat" && cp COPYING "$PREFIX/licenses/expat/"
)

# H.264 / HEVC / AV1 decoders and parsers, VideoToolbox hardware decoding.
step "FFmpeg $FFMPEG_VERSION"
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" J
(
    cd "ffmpeg-$FFMPEG_VERSION"
    env -u CFLAGS -u LDFLAGS ./configure --prefix="$PREFIX" --enable-static --disable-shared --enable-pic \
        --enable-cross-compile --target-os=darwin --arch="$ARCH" --cc=clang \
        --extra-cflags="$ARCH_FLAGS" --extra-ldflags="$ARCH_FLAGS" \
        --disable-autodetect --disable-programs --disable-doc --disable-network --disable-everything \
        --disable-avformat --disable-avdevice --disable-avfilter --disable-swscale --disable-swresample \
        --enable-decoder=h264,hevc,av1 --enable-parser=h264,hevc,av1 \
        --enable-videotoolbox --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox >/dev/null
    grep -q '^#define CONFIG_HEVC_VIDEOTOOLBOX_HWACCEL 1' config_components.h ||
        { echo "FFmpeg configured without VideoToolbox" >&2; exit 1; }
    make -j"$JOBS" >/dev/null && make install >/dev/null
    mkdir -p "$PREFIX/licenses/ffmpeg" && cp COPYING.LGPLv2.1 LICENSE.md "$PREFIX/licenses/ffmpeg/"
)

# HTTP(S) over OpenSSL only, for talking to the host.
step "curl $CURL_VERSION"
fetch "https://curl.se/download/curl-$CURL_VERSION.tar.xz" J
(
    cd "curl-$CURL_VERSION"
    ./configure "${CONFIGURE[@]}" --with-openssl="$PREFIX" \
        --without-zlib --without-brotli --without-zstd --without-libpsl --without-libidn2 \
        --without-nghttp2 --without-libssh2 --disable-ldap --disable-ldaps --disable-rtsp \
        --disable-dict --disable-telnet --disable-tftp --disable-pop3 --disable-imap --disable-smtp \
        --disable-gopher --disable-mqtt --disable-smb --disable-ftp --disable-file --disable-docs \
        --disable-manual --disable-ntlm --disable-kerberos-auth --disable-negotiate-auth >/dev/null
    make -j"$JOBS" >/dev/null && make install >/dev/null
    mkdir -p "$PREFIX/licenses/curl" && cp COPYING "$PREFIX/licenses/curl/"
)

touch "$stamp"
step "Done: $PREFIX"
