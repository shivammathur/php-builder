#!/usr/bin/env bash

# Compare static, dynamic and release builds
# Run this from the host machine

set -e

PHP_VERSION="${1:-8.5}"
ARCH=$(uname -m)
[[ "$ARCH" == "arm64" ]] && ARCH="aarch64"
ARCH_RELEASE="$ARCH"
[[ "$ARCH_RELEASE" == "aarch64" ]] && ARCH_RELEASE="arm64"
SAPI_LIST="apache2 cgi cli fpm embed phpdbg"

echo "=== Setting up 3 containers for comparison ==="

# Clean up existing containers
for c in php-static php-dynamic php-release; do
  docker stop "$c" 2>/dev/null || true
  docker rm "$c" 2>/dev/null || true
done

# Start containers
docker run -d --name php-static \
  -v "$(pwd):/workspace" \
  -e GITHUB_WORKSPACE=/workspace \
  -e PHP_VERSION="$PHP_VERSION" \
  -e BUILD=nts \
  -e SAPI_LIST="$SAPI_LIST" \
  -w /workspace \
  ubuntu:24.04 sleep infinity

docker run -d --name php-dynamic \
  -v "$(pwd):/workspace" \
  -e GITHUB_WORKSPACE=/workspace \
  -e PHP_VERSION="$PHP_VERSION" \
  -e BUILD=nts \
  -e SAPI_LIST="$SAPI_LIST" \
  -w /workspace \
  ubuntu:24.04 sleep infinity

docker run -d --name php-release \
  -v "$(pwd):/workspace" \
  -e PHP_VERSION="$PHP_VERSION" \
  -e GITHUB_WORKSPACE=/workspace \
  -w /workspace \
  ubuntu:24.04 sleep infinity

echo "Containers started"

run_static() {
  echo ""
  echo "=========================================="
  echo "=== STATIC BUILD ==="
  echo "=========================================="
  docker exec php-static bash -c '
export DEBIAN_FRONTEND=noninteractive
export PHP_VERSION='"$PHP_VERSION"'
export BUILD=nts
export GITHUB_WORKSPACE=/workspace
export SAPI_LIST="'"$SAPI_LIST"'"
export STATIC_PREFIX=/opt/static
cd /workspace

# Start from a clean static prefix
rm -rf /opt/static

# Install static library requirements
bash scripts/install-requirements-static.sh

# Build each SAPI using static build script
for sapi in $SAPI_LIST; do
  echo "=== Building SAPI: $sapi ==="
  bash scripts/build-static.sh build_sapi "$sapi"
done

# Merge all SAPIs
echo "=== Merging SAPIs ==="
bash scripts/build-static.sh merge

# Add JIT config for tests (system only)
mkdir -p /etc/php/"$PHP_VERSION"/mods-available /etc/php/"$PHP_VERSION"/cli/conf.d /etc/php/"$PHP_VERSION"/fpm/conf.d
cat > /etc/php/"$PHP_VERSION"/mods-available/jit.ini << "EOF"
opcache.enable=1
opcache.enable_cli=1
opcache.jit=tracing
opcache.jit_buffer_size=128M
EOF
ln -sf /etc/php/"$PHP_VERSION"/mods-available/jit.ini /etc/php/"$PHP_VERSION"/cli/conf.d/10-jit.ini
ln -sf /etc/php/"$PHP_VERSION"/mods-available/jit.ini /etc/php/"$PHP_VERSION"/fpm/conf.d/10-jit.ini

# Test extensions and SAPIs
bash scripts/test_extensions.sh
bash scripts/test_sapi.sh

# Verify build
php -v
php -m
ldd /usr/bin/php"$PHP_VERSION" 2>&1 || echo "Static binary"
' 2>&1 | tee /tmp/static-build.log
}

run_dynamic() {
  echo ""
  echo "=========================================="
  echo "=== DYNAMIC BUILD ==="
  echo "=========================================="
  docker exec php-dynamic bash -c '
export DEBIAN_FRONTEND=noninteractive
export PHP_VERSION='"$PHP_VERSION"'
export BUILD=nts
export GITHUB_WORKSPACE=/workspace
export SAPI_LIST="'"$SAPI_LIST"'"
cd /workspace

bash scripts/install-requirements.sh

# Build each SAPI using dynamic build script
for sapi in $SAPI_LIST; do
  echo "=== Building SAPI: $sapi ==="
  bash scripts/build.sh build_sapi "$sapi"
done

# Merge all SAPIs
echo "=== Merging SAPIs ==="
bash scripts/build.sh merge

# Add JIT config for tests (system only)
mkdir -p /etc/php/"$PHP_VERSION"/mods-available /etc/php/"$PHP_VERSION"/cli/conf.d /etc/php/"$PHP_VERSION"/fpm/conf.d
cat > /etc/php/"$PHP_VERSION"/mods-available/jit.ini << "EOF"
opcache.enable=1
opcache.enable_cli=1
opcache.jit=tracing
opcache.jit_buffer_size=128M
EOF
ln -sf /etc/php/"$PHP_VERSION"/mods-available/jit.ini /etc/php/"$PHP_VERSION"/cli/conf.d/10-jit.ini
ln -sf /etc/php/"$PHP_VERSION"/mods-available/jit.ini /etc/php/"$PHP_VERSION"/fpm/conf.d/10-jit.ini

# Test extensions and SAPIs
bash scripts/test_extensions.sh
bash scripts/test_sapi.sh

php -v
echo "Modules: $(php -m | grep -v "^\[" | grep -v "^$" | wc -l)"
' 2>&1 | tee /tmp/dynamic-build.log
}

run_release() {
  echo ""
  echo "=========================================="
  echo "=== RELEASE SETUP ==="
  echo "=========================================="
  docker exec php-release bash -c '
export DEBIAN_FRONTEND=noninteractive
export PHP_VERSION='"$PHP_VERSION"'
cd /workspace

apt-get update -qq
apt-get install -yq curl xz-utils ca-certificates sudo

# Install release via install.sh
bash scripts/install.sh "$PHP_VERSION"

# Add JIT config for tests (system only)
mkdir -p /etc/php/"$PHP_VERSION"/mods-available /etc/php/"$PHP_VERSION"/cli/conf.d /etc/php/"$PHP_VERSION"/fpm/conf.d
cat > /etc/php/"$PHP_VERSION"/mods-available/jit.ini << "EOF"
opcache.enable=1
opcache.enable_cli=1
opcache.jit=tracing
opcache.jit_buffer_size=128M
EOF
ln -sf /etc/php/"$PHP_VERSION"/mods-available/jit.ini /etc/php/"$PHP_VERSION"/cli/conf.d/10-jit.ini
ln -sf /etc/php/"$PHP_VERSION"/mods-available/jit.ini /etc/php/"$PHP_VERSION"/fpm/conf.d/10-jit.ini

# Download release tarball for file comparison
ARCH='"$ARCH_RELEASE"'
URL="https://github.com/shivammathur/php-builder/releases/download/${PHP_VERSION}/php_${PHP_VERSION}+ubuntu24.04_${ARCH}.tar.xz"
echo "Downloading: $URL"
curl -sL "$URL" -o /tmp/php.tar.xz
mkdir -p /tmp/release
tar -xJf /tmp/php.tar.xz -C /tmp/release

# Test extensions and SAPIs
bash scripts/test_extensions.sh
bash scripts/test_sapi.sh

php -v
echo "Modules: $(php -m | grep -v "^\[" | grep -v "^$" | wc -l)"
' 2>&1 | tee /tmp/release-setup.log
}

# Run all builds in parallel
run_static &
pid_static=$!
run_dynamic &
pid_dynamic=$!
run_release &
pid_release=$!

wait $pid_static
wait $pid_dynamic
wait $pid_release

# Compare
echo ""
echo "=========================================="
echo "=== COMPARISON ==="
echo "=========================================="

# Get file lists (compare merged install trees only)
docker exec php-static bash -c "find /tmp/debian/php$PHP_VERSION -type f 2>/dev/null | sort" > /tmp/static-files.txt
docker exec php-dynamic bash -c "find /tmp/debian/php$PHP_VERSION -type f 2>/dev/null | sort" > /tmp/dynamic-files.txt
docker exec php-release bash -c 'find /tmp/release -type f 2>/dev/null | sort' > /tmp/release-files.txt

# Normalize paths
sed -i '' "s|/tmp/debian/php$PHP_VERSION|/INSTALL|g" /tmp/static-files.txt 2>/dev/null || sed -i "s|/tmp/debian/php$PHP_VERSION|/INSTALL|g" /tmp/static-files.txt
sed -i '' "s|/tmp/debian/php$PHP_VERSION|/INSTALL|g" /tmp/dynamic-files.txt 2>/dev/null || sed -i "s|/tmp/debian/php$PHP_VERSION|/INSTALL|g" /tmp/dynamic-files.txt
sed -i '' 's|/tmp/release|/INSTALL|g' /tmp/release-files.txt 2>/dev/null || sed -i 's|/tmp/release|/INSTALL|g' /tmp/release-files.txt

echo "File counts:"
echo "  Static:  $(wc -l < /tmp/static-files.txt)"
echo "  Dynamic: $(wc -l < /tmp/dynamic-files.txt)"
echo "  Release: $(wc -l < /tmp/release-files.txt)"

echo ""
echo "=== Files only in DYNAMIC (missing from RELEASE) ==="
comm -23 /tmp/dynamic-files.txt /tmp/release-files.txt | head -20

echo ""
echo "=== Files only in RELEASE (missing from DYNAMIC) ==="
comm -13 /tmp/dynamic-files.txt /tmp/release-files.txt | head -20

echo ""
echo "=== Files only in STATIC (missing from DYNAMIC) ==="
comm -23 /tmp/static-files.txt /tmp/dynamic-files.txt | head -20

echo ""
echo "=== Files only in DYNAMIC (missing from STATIC) ==="
comm -13 /tmp/static-files.txt /tmp/dynamic-files.txt | head -20

# Module comparison
echo ""
echo "=== Module Comparison ==="
docker exec php-static bash -c 'php -m 2>/dev/null | grep -v "^\[" | grep -v "^$" | sort' > /tmp/static-mods.txt
docker exec php-dynamic bash -c 'php -m 2>/dev/null | grep -v "^\[" | grep -v "^$" | sort' > /tmp/dynamic-mods.txt
docker exec php-release bash -c 'php -m 2>/dev/null | grep -v "^\[" | grep -v "^$" | sort' > /tmp/release-mods.txt

echo "Module counts:"
echo "  Static:  $(wc -l < /tmp/static-mods.txt)"
echo "  Dynamic: $(wc -l < /tmp/dynamic-mods.txt)"
echo "  Release: $(wc -l < /tmp/release-mods.txt)"

echo ""
echo "Modules only in RELEASE (missing from DYNAMIC):"
comm -13 /tmp/dynamic-mods.txt /tmp/release-mods.txt

echo ""
echo "Modules only in DYNAMIC (missing from RELEASE):"
comm -23 /tmp/dynamic-mods.txt /tmp/release-mods.txt

echo ""
echo "=== Done ==="
