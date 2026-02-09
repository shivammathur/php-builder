#!/bin/bash
set -e
STATIC_PREFIX=/opt/static
BUILD_DIR=/tmp/static-build
JOBS=$(nproc)

echo "Rebuilding OpenSSL 3.3.2..."
rm -rf "$BUILD_DIR/openssl-rebuild"
mkdir -p "$BUILD_DIR/openssl-rebuild" && cd "$BUILD_DIR/openssl-rebuild"

curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-3.3.2/openssl-3.3.2.tar.gz" | tar -xz --strip-components=1

./Configure --prefix="$STATIC_PREFIX" \
  --openssldir="$STATIC_PREFIX/ssl" \
  --libdir=lib \
  no-shared \
  no-tests \
  "-fPIC"

make -j"$JOBS"
make install_sw

rm -f "$STATIC_PREFIX/lib"/libssl.so* "$STATIC_PREFIX/lib"/libcrypto.so* 2>/dev/null || true

echo "OpenSSL rebuilt successfully"
ls -la "$STATIC_PREFIX/lib"/lib{ssl,crypto}.a
nm "$STATIC_PREFIX/lib/libssl.a" | grep SSL_get0_group_name || echo "Function not exported"
