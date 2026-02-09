#!/bin/bash
#
# Comprehensive test script for comparing:
# - Released PHP builds (from GitHub releases)
# - Locally built dynamic PHP
# - Static PHP build
#
# Usage: ./scripts/comprehensive-test.sh

set -e

PHP_VERSION="${PHP_VERSION:-8.5}"
CONTAINER1="php-release-dynamic-test"
CONTAINER2="php-static-test"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== PHP Build Comprehensive Test ==="
echo "PHP Version: $PHP_VERSION"
echo "Container 1 (Release + Dynamic): $CONTAINER1"
echo "Container 2 (Static): $CONTAINER2"
echo ""

# Stop existing containers if running
echo "Cleaning up existing containers..."
docker rm -f "$CONTAINER1" "$CONTAINER2" 2>/dev/null || true

# Start new containers
echo "=== Starting Docker containers ==="
docker run -d --name "$CONTAINER1" \
    -v "$REPO_DIR":/workspace \
    debian:bookworm \
    sleep infinity

docker run -d --name "$CONTAINER2" \
    -v "$REPO_DIR":/workspace \
    debian:bookworm \
    sleep infinity

echo "Containers started."

# Function to run commands in container
run_in() {
    local container=$1
    shift
    docker exec -e DEBIAN_FRONTEND=noninteractive "$container" bash -c "$*"
}

# Function to copy file from container
copy_from() {
    local container=$1
    local src=$2
    local dst=$3
    docker cp "$container:$src" "$dst"
}

# ==============================================================================
# CONTAINER 1: Released build + Dynamic local build
# ==============================================================================

echo ""
echo "=== Container 1: Setting up base requirements ==="
run_in "$CONTAINER1" '
apt-get update && apt-get install -y \
    curl wget git ca-certificates zstd build-essential \
    libxml2-dev libsqlite3-dev libreadline-dev libcurl4-openssl-dev \
    libonig-dev libzip-dev libssl-dev libbz2-dev libpng-dev \
    libjpeg-dev libfreetype6-dev libxpm-dev libwebp-dev \
    libkrb5-dev libldap2-dev libpq-dev libsodium-dev \
    libxslt1-dev libenchant-2-dev libgmp-dev libsnmp-dev \
    libc-client-dev libtidy-dev libffi-dev libpcre2-dev \
    libpspell-dev libmm-dev unixodbc-dev freetds-dev firebird-dev \
    autoconf re2c bison pkg-config libsystemd-dev \
    apache2 nginx libapache2-mod-fcgid \
    --no-install-recommends
'

echo ""
echo "=== Container 1: Installing Released PHP build ==="
run_in "$CONTAINER1" "
cd /workspace
export VERSION=$PHP_VERSION
export INSTALL_ROOT=/tmp/release/php\$VERSION
mkdir -p \$INSTALL_ROOT /tmp/release

# Download the released build using install.sh logic
mkdir -p /tmp/release-download && cd /tmp/release-download
version=\"$PHP_VERSION\"
# Note: Assets are named php_8.5+debian12.tar.zst (no _amd64)
curl -sLo php.tar.zst \"https://github.com/shivammathur/php-builder/releases/download/\${version}/php_\${version}+debian12.tar.zst\" || {
    echo 'ERROR: Could not download released build. Skipping release comparison.'
    touch /tmp/no-release
    exit 0
}
tar -I zstd -xf php.tar.zst
mv php/* /tmp/release/ || true
ls -la /tmp/release/
echo 'Release download successful'
"

echo ""
echo "=== Container 1: Building Dynamic PHP locally ==="
run_in "$CONTAINER1" "
cd /workspace
export PHP_VERSION=$PHP_VERSION
export VERSION=$PHP_VERSION
export INSTALL_ROOT=/tmp/debian/php\$VERSION
export BUILD_MODE=dynamic

# Make scripts executable
chmod +x scripts/*.sh scripts/build_partials/*.sh scripts/build_partials/sapi/*.sh 2>/dev/null || true
chmod +x scripts/build_partials/static/*.sh 2>/dev/null || true

# Run install-requirements first  
bash scripts/install-requirements.sh || true

# Set up PHP_VERSION_CLEAN for directories
export PHP_VERSION_CLEAN=\$(echo \$PHP_VERSION | cut -d- -f1)

# Build dynamic PHP CLI SAPI
bash scripts/build.sh build_sapi cli 2>&1 | head -500

# Check the result
echo ''
echo 'Checking build output:'
ls -la /tmp/debian/ 2>/dev/null || echo 'No /tmp/debian directory'
ls -la /tmp/debian/php$PHP_VERSION/ 2>/dev/null | head -20 || echo 'No /tmp/debian/php$PHP_VERSION directory'
find /tmp/debian -name 'php*' -type f 2>/dev/null | head -10 || echo 'No php binaries found'
"

# Check the result
ls -la /tmp/debian/ 2>/dev/null || ls -la \$INSTALL_ROOT 2>/dev/null || echo 'Build output not found in expected location'
"

echo ""
echo "=== Container 1: Linking builds to system paths ==="
run_in "$CONTAINER1" "
PHP_VERSION=$PHP_VERSION

# Link released build if available
if [ ! -f /tmp/no-release ] && [ -d /tmp/release/usr ]; then
    echo 'Linking released build...'
    cp -rn /tmp/release/usr/* /usr/ 2>/dev/null || true
    cp -rn /tmp/release/etc/* /etc/ 2>/dev/null || true
    cp -rn /tmp/release/var/* /var/ 2>/dev/null || true
    ln -sf /usr/bin/php\$PHP_VERSION /usr/bin/php-release
    echo 'Released build linked.'
fi

# Link dynamic build
if [ -d /tmp/debian/php\$PHP_VERSION/usr ]; then
    echo 'Linking dynamic build...'
    # Create separate links for dynamic
    ln -sf /tmp/debian/php\$PHP_VERSION/usr/bin/php\$PHP_VERSION /usr/bin/php-dynamic
    # Copy config if not exists
    cp -rn /tmp/debian/php\$PHP_VERSION/etc/* /etc/ 2>/dev/null || true
    echo 'Dynamic build linked.'
fi

# Verify
echo ''
echo 'PHP binaries available:'
ls -la /usr/bin/php* 2>/dev/null || echo 'No PHP binaries found'
"

# ==============================================================================
# CONTAINER 2: Static build
# ==============================================================================

echo ""
echo "=== Container 2: Setting up static build requirements ==="
run_in "$CONTAINER2" '
apt-get update && apt-get install -y \
    curl wget git ca-certificates zstd build-essential \
    autoconf re2c bison pkg-config libsystemd-dev \
    --no-install-recommends
'

echo ""
echo "=== Container 2: Downloading static libraries ==="
run_in "$CONTAINER2" '
mkdir -p /opt/static
cd /opt/static
# Download pre-built static libraries (from GitHub releases or build locally)
curl -sLo static-libs.tar.zst "https://github.com/nicothin/static-php-cli/releases/download/v1.0.0/php-8.2-static-libs.tar.zst" 2>/dev/null || {
    echo "No pre-built static libs available, will need to build deps manually"
    
    # Install essential build dependencies for minimal static build
    apt-get install -y \
        libxml2-dev libsqlite3-dev libreadline-dev \
        libssl-dev libbz2-dev libcurl4-openssl-dev \
        libonig-dev libzip-dev libsodium-dev \
        libpng-dev libjpeg-dev libfreetype6-dev \
        zlib1g-dev
}
'

echo ""  
echo "=== Container 2: Building Static PHP ==="
run_in "$CONTAINER2" "
cd /workspace
export PHP_VERSION=$PHP_VERSION
export VERSION=$PHP_VERSION
export INSTALL_ROOT=/tmp/debian/php\$VERSION
export BUILD_MODE=static

# Make scripts executable
chmod +x scripts/*.sh scripts/build_partials/*.sh scripts/build_partials/sapi/*.sh 2>/dev/null || true
chmod +x scripts/build_partials/static/*.sh 2>/dev/null || true

# Install build requirements
bash scripts/install-requirements.sh || true

# Build static PHP CLI SAPI
bash scripts/build.sh build_sapi cli 2>&1 | head -500

# Check the result
echo ''
echo 'Checking build output:'
ls -la /tmp/debian/ 2>/dev/null || echo 'No /tmp/debian directory'
ls -la /tmp/debian/php$PHP_VERSION/ 2>/dev/null | head -20 || echo 'No /tmp/debian/php$PHP_VERSION directory'
find /tmp/debian -name 'php*' -type f 2>/dev/null | head -10 || echo 'No php binaries found'
"

# Check the result
ls -la /tmp/debian/ 2>/dev/null || ls -la \$INSTALL_ROOT 2>/dev/null || echo 'Build output not found'
"

echo ""
echo "=== Container 2: Linking static build to system paths ==="
run_in "$CONTAINER2" "
PHP_VERSION=$PHP_VERSION

if [ -d /tmp/debian/php\$PHP_VERSION/usr ]; then
    echo 'Linking static build...'
    cp -rn /tmp/debian/php\$PHP_VERSION/usr/* /usr/ 2>/dev/null || true
    cp -rn /tmp/debian/php\$PHP_VERSION/etc/* /etc/ 2>/dev/null || true
    ln -sf /usr/bin/php\$PHP_VERSION /usr/bin/php-static
    ln -sf /usr/bin/php\$PHP_VERSION /usr/bin/php
    echo 'Static build linked.'
fi

echo ''
echo 'PHP binaries available:'
ls -la /usr/bin/php* 2>/dev/null || echo 'No PHP binaries found'
"

# ==============================================================================
# TESTING PHASE
# ==============================================================================

echo ""
echo "=============================================="
echo "=== TESTING PHASE ==="
echo "=============================================="

echo ""
echo "=== Testing PHP versions ==="
echo ""
echo "--- Container 1: Released Build ---"
run_in "$CONTAINER1" "/usr/bin/php-release -v 2>/dev/null || echo 'Released build not available'"

echo ""
echo "--- Container 1: Dynamic Build ---"
run_in "$CONTAINER1" "/usr/bin/php-dynamic -v 2>/dev/null || echo 'Dynamic build not available'"

echo ""
echo "--- Container 2: Static Build ---"
run_in "$CONTAINER2" "/usr/bin/php-static -v 2>/dev/null || echo 'Static build not available'"

echo ""
echo "=== Testing loaded extensions ==="

echo ""
echo "--- Container 1: Released Build Extensions ---"
run_in "$CONTAINER1" "/usr/bin/php-release -m 2>/dev/null | head -80 || echo 'Released build not available'"

echo ""
echo "--- Container 1: Dynamic Build Extensions ---"
run_in "$CONTAINER1" "/usr/bin/php-dynamic -m 2>/dev/null | head -80 || echo 'Dynamic build not available'"

echo ""
echo "--- Container 2: Static Build Extensions ---"
run_in "$CONTAINER2" "/usr/bin/php-static -m 2>/dev/null | head -80 || echo 'Static build not available'"

echo ""
echo "=== Extension count comparison ==="
echo ""
echo "Released: $(run_in "$CONTAINER1" "/usr/bin/php-release -m 2>/dev/null | grep -v '^\[' | grep -v '^$' | wc -l" 2>/dev/null || echo "N/A")"
echo "Dynamic:  $(run_in "$CONTAINER1" "/usr/bin/php-dynamic -m 2>/dev/null | grep -v '^\[' | grep -v '^$' | wc -l" 2>/dev/null || echo "N/A")"
echo "Static:   $(run_in "$CONTAINER2" "/usr/bin/php-static -m 2>/dev/null | grep -v '^\[' | grep -v '^$' | wc -l" 2>/dev/null || echo "N/A")"

# ==============================================================================
# TEST PECL EXTENSIONS (Dynamic build only)
# ==============================================================================

echo ""
echo "=== Testing PECL Extensions (Container 1 - Dynamic) ==="
run_in "$CONTAINER1" "
PHP_VERSION=$PHP_VERSION
cd /workspace

# Read extensions from config
echo 'Extensions defined in config/extensions/\$PHP_VERSION:'
cat config/extensions/\$PHP_VERSION 2>/dev/null || echo 'No extension config found'
echo ''

# Check each extension is loadable
for ext in bcmath bz2 calendar ctype curl dba dom exif ffi fileinfo ftp gd gettext gmp iconv intl ldap mbstring mysqli mysqlnd opcache pcntl pdo pdo_mysql pdo_pgsql pdo_sqlite pgsql phar posix readline shmop simplexml soap sockets sqlite3 sysvmsg sysvsem sysvshm tidy tokenizer xml xmlreader xmlwriter xsl zip; do
    if /usr/bin/php-dynamic -r \"extension_loaded('\$ext') || exit(1);\" 2>/dev/null; then
        echo \"[OK] \$ext\"
    else
        echo \"[--] \$ext (not loaded)\"
    fi
done
" 2>/dev/null || echo "Dynamic build extension test failed"

echo ""
echo "=== Testing Built-in Extensions (Container 2 - Static) ==="
run_in "$CONTAINER2" "
PHP_VERSION=$PHP_VERSION
cd /workspace

# Check each extension is compiled in
for ext in bcmath bz2 calendar ctype curl dba dom exif ffi fileinfo ftp gd gettext gmp iconv intl ldap mbstring mysqli mysqlnd opcache pcntl pdo pdo_mysql pdo_pgsql pdo_sqlite pgsql phar posix readline shmop simplexml soap sockets sqlite3 sysvmsg sysvsem sysvshm tidy tokenizer xml xmlreader xmlwriter xsl zip; do
    if /usr/bin/php-static -r \"extension_loaded('\$ext') || exit(1);\" 2>/dev/null; then
        echo \"[OK] \$ext\"
    else
        echo \"[--] \$ext (not loaded)\"
    fi
done
" 2>/dev/null || echo "Static build extension test failed"

# ==============================================================================
# TEST SAPIs (Container 1 only - Dynamic has all SAPIs)
# ==============================================================================

echo ""
echo "=== Testing SAPIs (Container 1 - Dynamic) ==="
run_in "$CONTAINER1" "
PHP_VERSION=$PHP_VERSION

echo '--- CLI SAPI ---'
/usr/bin/php-dynamic -r \"echo 'SAPI: ' . php_sapi_name() . PHP_EOL;\" 2>/dev/null || echo 'CLI not available'

echo ''
echo '--- CGI SAPI ---'
if [ -f /usr/bin/php-cgi\$PHP_VERSION ]; then
    echo 'CGI binary exists'
    /usr/bin/php-cgi\$PHP_VERSION -v 2>/dev/null | head -1 || echo 'CGI version check failed'
else
    echo 'CGI binary not found'
fi

echo ''
echo '--- FPM SAPI ---'
if [ -f /usr/sbin/php-fpm\$PHP_VERSION ]; then
    echo 'FPM binary exists'
    /usr/sbin/php-fpm\$PHP_VERSION -v 2>/dev/null | head -1 || echo 'FPM version check failed'
else
    echo 'FPM binary not found'
fi

echo ''
echo '--- phpdbg SAPI ---'
if [ -f /usr/bin/phpdbg\$PHP_VERSION ]; then
    echo 'phpdbg binary exists'
    /usr/bin/phpdbg\$PHP_VERSION -v 2>/dev/null | head -1 || echo 'phpdbg version check failed'
else
    echo 'phpdbg binary not found'
fi

echo ''
echo '--- Embed SAPI ---'
if [ -f /usr/lib/libphp.so ] || [ -f /usr/lib/x86_64-linux-gnu/libphp.so ]; then
    echo 'Embed library exists'
    ls -la /usr/lib/libphp* /usr/lib/*/libphp* 2>/dev/null || true
else
    echo 'Embed library not found'
fi
"

# ==============================================================================
# FILE-BY-FILE ANALYSIS
# ==============================================================================

echo ""
echo "=============================================="
echo "=== FILE-BY-FILE ANALYSIS ==="
echo "=============================================="

# Extract file lists
echo ""
echo "=== Extracting file lists from each build ==="

run_in "$CONTAINER1" "
if [ -d /tmp/release ]; then
    find /tmp/release -type f | sed 's|^/tmp/release||' | sort > /tmp/files-release.txt
    echo \"Released build files: \$(wc -l < /tmp/files-release.txt)\"
fi
if [ -d /tmp/debian/php$PHP_VERSION ]; then
    find /tmp/debian/php$PHP_VERSION -type f | sed 's|^/tmp/debian/php$PHP_VERSION||' | sort > /tmp/files-dynamic.txt
    echo \"Dynamic build files: \$(wc -l < /tmp/files-dynamic.txt)\"
fi
"

run_in "$CONTAINER2" "
if [ -d /tmp/debian/php$PHP_VERSION ]; then
    find /tmp/debian/php$PHP_VERSION -type f | sed 's|^/tmp/debian/php$PHP_VERSION||' | sort > /tmp/files-static.txt
    echo \"Static build files: \$(wc -l < /tmp/files-static.txt)\"
fi
"

# Copy file lists locally for comparison
mkdir -p /tmp/php-comparison
copy_from "$CONTAINER1" "/tmp/files-release.txt" "/tmp/php-comparison/files-release.txt" 2>/dev/null || touch /tmp/php-comparison/files-release.txt
copy_from "$CONTAINER1" "/tmp/files-dynamic.txt" "/tmp/php-comparison/files-dynamic.txt" 2>/dev/null || touch /tmp/php-comparison/files-dynamic.txt
copy_from "$CONTAINER2" "/tmp/files-static.txt" "/tmp/php-comparison/files-static.txt" 2>/dev/null || touch /tmp/php-comparison/files-static.txt

echo ""
echo "=== File count summary ==="
echo "Released: $(wc -l < /tmp/php-comparison/files-release.txt 2>/dev/null || echo 0) files"
echo "Dynamic:  $(wc -l < /tmp/php-comparison/files-dynamic.txt 2>/dev/null || echo 0) files"
echo "Static:   $(wc -l < /tmp/php-comparison/files-static.txt 2>/dev/null || echo 0) files"

echo ""
echo "=== Files ONLY in Released build (not in Dynamic) ==="
comm -23 /tmp/php-comparison/files-release.txt /tmp/php-comparison/files-dynamic.txt 2>/dev/null | head -30 || echo "None or comparison failed"

echo ""
echo "=== Files ONLY in Dynamic build (not in Released) ==="
comm -13 /tmp/php-comparison/files-release.txt /tmp/php-comparison/files-dynamic.txt 2>/dev/null | head -30 || echo "None or comparison failed"

echo ""
echo "=== Files ONLY in Dynamic build (not in Static) ==="
comm -23 /tmp/php-comparison/files-dynamic.txt /tmp/php-comparison/files-static.txt 2>/dev/null | head -30 || echo "None or comparison failed"

echo ""
echo "=== Files ONLY in Static build (not in Dynamic) ==="
comm -13 /tmp/php-comparison/files-dynamic.txt /tmp/php-comparison/files-static.txt 2>/dev/null | head -30 || echo "None or comparison failed"

echo ""
echo "=== Common files in all three builds ==="
if [ -s /tmp/php-comparison/files-release.txt ]; then
    comm -12 /tmp/php-comparison/files-release.txt /tmp/php-comparison/files-dynamic.txt > /tmp/php-comparison/common-release-dynamic.txt
    comm -12 /tmp/php-comparison/common-release-dynamic.txt /tmp/php-comparison/files-static.txt 2>/dev/null | head -30 || echo "None"
else
    comm -12 /tmp/php-comparison/files-dynamic.txt /tmp/php-comparison/files-static.txt 2>/dev/null | head -30 || echo "None or comparison failed"
fi

echo ""
echo "=== Binary size comparison ==="
echo ""
echo "--- Released build ---"
run_in "$CONTAINER1" "ls -lh /tmp/release/usr/bin/php* 2>/dev/null | head -5 || echo 'Not available'"
echo ""
echo "--- Dynamic build ---"
run_in "$CONTAINER1" "ls -lh /tmp/debian/php$PHP_VERSION/usr/bin/php* 2>/dev/null | head -5 || echo 'Not available'"
echo ""
echo "--- Static build ---"
run_in "$CONTAINER2" "ls -lh /tmp/debian/php$PHP_VERSION/usr/bin/php* 2>/dev/null | head -5 || echo 'Not available'"

echo ""
echo "=== Shared library dependency comparison ==="
echo ""
echo "--- Released build dependencies ---"
run_in "$CONTAINER1" "ldd /tmp/release/usr/bin/php* 2>/dev/null | head -30 || echo 'Not available or statically linked'"
echo ""
echo "--- Dynamic build dependencies ---"
run_in "$CONTAINER1" "ldd /tmp/debian/php$PHP_VERSION/usr/bin/php* 2>/dev/null | head -30 || echo 'Not available or statically linked'"
echo ""
echo "--- Static build dependencies ---"
run_in "$CONTAINER2" "ldd /tmp/debian/php$PHP_VERSION/usr/bin/php* 2>/dev/null | head -30 || echo 'Statically linked (expected)'"

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo "=============================================="
echo "=== TEST SUMMARY ==="
echo "=============================================="

echo ""
echo "Containers running (not cleaned up):"
echo "  - $CONTAINER1 (Released + Dynamic builds)"
echo "  - $CONTAINER2 (Static build)"
echo ""
echo "To access containers:"
echo "  docker exec -it $CONTAINER1 bash"
echo "  docker exec -it $CONTAINER2 bash"
echo ""
echo "Build locations inside containers:"
echo "  Released: /tmp/release/"
echo "  Dynamic:  /tmp/debian/php$PHP_VERSION/"
echo "  Static:   /tmp/debian/php$PHP_VERSION/"
echo ""
echo "System-linked binaries:"
echo "  /usr/bin/php-release (Container 1)"
echo "  /usr/bin/php-dynamic (Container 1)"
echo "  /usr/bin/php-static  (Container 2)"
echo ""
echo "File comparison results saved to: /tmp/php-comparison/"
echo ""
echo "=== Test Complete ==="
