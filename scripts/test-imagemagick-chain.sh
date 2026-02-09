#!/bin/bash
# Test ImageMagick dependency chain
set -e

export DEBIAN_FRONTEND=noninteractive
export STATIC_PREFIX=/opt/static
export BUILD_DIR=/tmp/build

# Install build tools
apt-get update -qq 
apt-get install -yqq --no-install-recommends \
    autoconf automake bzip2 ca-certificates cmake curl g++ gcc \
    gettext libtool make nasm ninja-build patch pkg-config wget xz-utils

mkdir -p $STATIC_PREFIX/{lib,include,bin,share,lib/pkgconfig}
mkdir -p $BUILD_DIR

export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig"
export CFLAGS="-fPIC -I$STATIC_PREFIX/include"
export CXXFLAGS="-fPIC -I$STATIC_PREFIX/include"
export LDFLAGS="-L$STATIC_PREFIX/lib"

echo "=== Building ImageMagick dependency chain ==="

build_lib() {
    local lib_name=$1
    echo ""
    echo "=== Building $lib_name ==="
    cd $BUILD_DIR
    rm -rf *
    
    # Unset previous build_library function
    unset -f build_library
    
    source "/workspace/config/static-libs/$lib_name"
    if type build_library &>/dev/null; then
        build_library && echo "$lib_name: SUCCESS" || { echo "$lib_name: FAILED"; return 1; }
    else
        echo "No build_library function for $lib_name"
        return 1
    fi
}

# Build chain
LIBS=(
    "libtiff"
    "libde265"
    "libaom"
    "libheif"
    "imagemagick"
)

for lib in "${LIBS[@]}"; do
    build_lib "$lib" || exit 1
done

echo ""
echo "=== Final library inventory ==="
ls -la $STATIC_PREFIX/lib/*.a 2>/dev/null

echo ""
echo "=== ImageMagick MagickWand header check ==="
ls -la $STATIC_PREFIX/include/ImageMagick-7/MagickWand/*.h 2>/dev/null | head -5 || echo "Headers not found"
