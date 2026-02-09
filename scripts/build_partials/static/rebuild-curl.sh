#!/bin/bash
set -e
STATIC_PREFIX=/opt/static
BUILD_DIR=/tmp/static-build
JOBS=$(nproc)

echo "Rebuilding curl 8.9.1..."
rm -f "$STATIC_PREFIX/lib/libcurl.a" "$STATIC_PREFIX/lib/pkgconfig/libcurl.pc"
rm -rf "$BUILD_DIR/curl-rebuild"
mkdir -p "$BUILD_DIR/curl-rebuild" && cd "$BUILD_DIR/curl-rebuild"

curl -fsSL "https://curl.se/download/curl-8.9.1.tar.xz" | tar -xJ --strip-components=1

export CFLAGS="-fPIC -I$STATIC_PREFIX/include"
export LDFLAGS="-L$STATIC_PREFIX/lib"
export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig"

./configure --prefix="$STATIC_PREFIX" \
  --enable-static \
  --disable-shared \
  --with-openssl="$STATIC_PREFIX" \
  --with-zlib="$STATIC_PREFIX" \
  --without-libpsl \
  --without-brotli \
  --without-zstd \
  --without-libidn2 \
  --without-nghttp2 \
  --without-librtmp \
  --without-libssh \
  --without-libssh2 \
  --disable-ldap \
  --disable-manual

make -j"$JOBS"
make install
rm -f "$STATIC_PREFIX/lib"/libcurl.so* 2>/dev/null || true

echo "curl rebuilt successfully"
ls -la "$STATIC_PREFIX/lib/libcurl.a"
