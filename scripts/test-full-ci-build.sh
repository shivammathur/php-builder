#!/usr/bin/env bash
# Full CI-like build test script
# Uses the actual build.sh script to build PHP

set -eE

export DEBIAN_FRONTEND=noninteractive
export GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-/workspace}
export PHP_VERSION=${PHP_VERSION:-8.5}
export BUILD=${BUILD:-nts}
export SAPI_LIST=${SAPI_LIST:-"cli cgi fpm embed phpdbg"}
export BUILD_MODE=${BUILD_MODE:-dynamic}  # static, dynamic, or release

echo "=== Build Mode: $BUILD_MODE ==="
echo "PHP Version: $PHP_VERSION"
echo "Build Type: $BUILD"
echo "SAPI List: $SAPI_LIST"
echo ""

cd "$GITHUB_WORKSPACE"

# Install requirements  
if [ "$BUILD_MODE" = "release" ]; then
    echo "=== Downloading Release Build ==="
    apt-get update -qq
    apt-get install -y -qq curl jq xz-utils ca-certificates > /dev/null 2>&1
    
    # Install runtime dependencies for dynamic PHP
    apt-get install -y -qq \
        libxml2 libsqlite3-0 libonig5 libzip4t64 libcurl4t64 libpng16-16t64 \
        libjpeg62 libfreetype6 libwebp7 libgmp10 libedit2 libpq5 libldap2 \
        libsnmp40t64 libodbc2 libodbcinst2 libargon2-1 libsodium23 libyaml-0-2 \
        libenchant-2-2 libtidy5deb1 libffi8 libicu74 libxslt1.1 libbz2-1.0 \
        libfbclient2t64 libqdbm14t64 liblmdb0 libdb5.3 libc-client2007e \
        libmemcached11t64 libzmq5 libuv1t64 libgd3 libavif16 libheif1 \
        > /dev/null 2>&1 || true
    
    ARCH=$(dpkg --print-architecture)
    . /etc/os-release
    
    API_URL="https://api.github.com/repos/shivammathur/php-builder/releases/tags/$PHP_VERSION"
    if [ "$ARCH" = "amd64" ]; then
        TARBALL_NAME="php_${PHP_VERSION}+ubuntu${VERSION_ID}.tar.xz"
    else
        TARBALL_NAME="php_${PHP_VERSION}+ubuntu${VERSION_ID}_${ARCH}.tar.xz"
    fi
    
    DOWNLOAD_URL=$(curl -sL "$API_URL" | jq -r ".assets[] | select(.name == \"$TARBALL_NAME\") | .browser_download_url")
    
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        echo "ERROR: Could not find release tarball: $TARBALL_NAME"
        exit 1
    fi
    
    echo "Downloading: $DOWNLOAD_URL"
    curl -sL "$DOWNLOAD_URL" -o /tmp/php-release.tar.xz
    
    echo "Extracting to /"
    tar -xJf /tmp/php-release.tar.xz -C /
    
    echo "Release installed successfully"
    
elif [ "$BUILD_MODE" = "static" ]; then
    echo "=== Installing Static Requirements ==="
    bash scripts/install-requirements-static.sh
    
else
    echo "=== Installing Dynamic Requirements ==="
    bash scripts/install-requirements.sh
fi

if [ "$BUILD_MODE" != "release" ]; then
    # Build each SAPI
    IFS=' ' read -r -a sapi_arr <<< "$SAPI_LIST"
    for sapi in "${sapi_arr[@]}"; do
        echo ""
        echo "=== Building SAPI: $sapi ==="
        if [ "$BUILD_MODE" = "static" ]; then
            bash scripts/build-static.sh build_sapi "$sapi"
        else
            bash scripts/build.sh build_sapi "$sapi"
        fi
    done
    
    # Merge builds
    echo ""
    echo "=== Merging Builds ==="
    if [ "$BUILD_MODE" = "static" ]; then
        bash scripts/build-static.sh merge
    else
        bash scripts/build.sh merge
    fi
fi

# Show results
echo ""
echo "=== Build Results ==="
echo ""
echo "--- php -v ---"
php -v || /usr/bin/php"$PHP_VERSION" -v
echo ""
echo "--- php -m ---"
php -m || /usr/bin/php"$PHP_VERSION" -m
echo ""
echo "--- ldd php ---"
ldd /usr/bin/php"$PHP_VERSION" 2>&1 || echo "ldd failed or binary is static"
echo ""
echo "--- file php ---"
file /usr/bin/php"$PHP_VERSION"
echo ""
echo "--- Extension directory ---"
ext_dir=$(/usr/bin/php-config"$PHP_VERSION" --extension-dir 2>/dev/null || echo "/usr/lib/php/$PHP_VERSION")
ls -la "$ext_dir"/*.so 2>/dev/null | wc -l && echo "extensions found"
echo ""
echo "--- /usr/bin/php* ---"
ls -la /usr/bin/php* 2>/dev/null

echo ""
echo "=== Build Complete ==="
