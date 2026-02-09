#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export STATIC_PREFIX=/opt/static
export BUILD_DIR=/tmp/build

# Install build tools
apt-get update -qq 
apt-get install -yqq --no-install-recommends \
    autoconf automake bison bzip2 ca-certificates cmake curl flex g++ gcc \
    gettext libtool make nasm ninja-build pkg-config wget xz-utils

mkdir -p $STATIC_PREFIX/{lib,include,bin,share,lib/pkgconfig}
mkdir -p $BUILD_DIR

export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig"
export CFLAGS="-fPIC -I$STATIC_PREFIX/include"
export CXXFLAGS="-fPIC -I$STATIC_PREFIX/include"
export LDFLAGS="-L$STATIC_PREFIX/lib"

# Install base prebuilts
PRE_BUILT_URL="https://dl.static-php.dev/static-php-cli/pre-built"

echo "=== Installing base prebuilts ==="

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    ARCH_SUFFIX="aarch64"
else
    ARCH_SUFFIX="x86_64"
fi

# zlib
curl -fsSL "$PRE_BUILT_URL/linux/zlib/zlib-1.3.1-debian-bookworm-${ARCH_SUFFIX}.tar.gz" | tar -xzC "$STATIC_PREFIX" || echo "zlib prebuilt not found, skipping"
# libjpeg  
curl -fsSL "$PRE_BUILT_URL/linux/libjpeg/libjpeg-9f-debian-bookworm-${ARCH_SUFFIX}.tar.gz" | tar -xzC "$STATIC_PREFIX" || echo "libjpeg prebuilt not found, skipping"
# openssl
curl -fsSL "$PRE_BUILT_URL/linux/openssl/openssl-3.2.1-debian-bookworm-${ARCH_SUFFIX}.tar.gz" | tar -xzC "$STATIC_PREFIX" || echo "openssl prebuilt not found, skipping"

# Test library (passed as argument)
LIB_NAME="${1:-libtiff}"
echo ""
echo "=== Testing $LIB_NAME ==="

if [ -f "/workspace/config/static-libs/$LIB_NAME" ]; then
    cd $BUILD_DIR
    rm -rf *
    source "/workspace/config/static-libs/$LIB_NAME"
    if type build_library &>/dev/null; then
        build_library && echo "$LIB_NAME: SUCCESS" || echo "$LIB_NAME: FAILED"
    else
        echo "No build_library function found in config"
    fi
    echo ""
    echo "=== Libraries created ==="
    ls -la $STATIC_PREFIX/lib/*.a 2>/dev/null | tail -10 || echo "None found"
else
    echo "Config not found: /workspace/config/static-libs/$LIB_NAME"
fi
