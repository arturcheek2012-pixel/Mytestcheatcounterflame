#!/bin/bash
set -euo pipefail
ROOT=$PWD
PREFIX=$ROOT/ios-prefix
mkdir -p deps "$PREFIX/lib/pkgconfig" && cd deps

CM="-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
-DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_PREFIX_PATH=$PREFIX -DCMAKE_BUILD_TYPE=Release \
-DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON"

build() { n=$1; url=$2; tag=$3; shift 3
  git clone --depth 1 --branch "$tag" "$url" "$n"
  cmake -S "$n" -B "$n/b" $CM "$@"
  cmake --build "$n/b" -j4
  cmake --install "$n/b"; }

cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<EOF
Name: zlib
Description: zlib
Version: 1.2.12
Libs: -lz
EOF

build sdl https://github.com/libsdl-org/SDL release-2.30.8 -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF
build png https://github.com/glennrp/libpng v1.6.43 -DPNG_SHARED=OFF -DPNG_TESTS=OFF -DPNG_EXECUTABLES=OFF
build jpeg https://github.com/libjpeg-turbo/libjpeg-turbo 3.0.3 -DENABLE_SHARED=OFF -DWITH_TURBOJPEG=OFF -DWITH_SIMD=0
build ft https://github.com/freetype/freetype VER-2-13-2 -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_PNG=ON
build curl https://github.com/curl/curl curl-8_9_1 -DCURL_USE_SECTRANSP=ON -DCURL_USE_OPENSSL=OFF -DCURL_USE_LIBPSL=OFF -DBUILD_CURL_EXE=OFF -DCURL_DISABLE_LDAP=ON
