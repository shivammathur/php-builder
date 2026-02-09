#!/bin/bash
# Full static build matching CI workflow
set -ex

export DEBIAN_FRONTEND=noninteractive
export PHP_VERSION=${PHP_VERSION:-8.5}
export BUILD=${BUILD:-nts}
export GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-/workspace}
export INSTALL_ROOT=/builds/php
export SAPI_LIST="cli cgi fpm embed phpdbg"
export PHP_SOURCE="--web-php"  # Use web-php to get stable releases
export GITHUB_MESSAGE="build-all"  # Force rebuild even if release exists
export GITHUB_REPOSITORY="shivammathur/php-builder"  # Required for version check

# build-static.sh uses relative paths, must run from workspace
cd "$GITHUB_WORKSPACE"

echo "=== Step 1: Install Static Requirements ==="
bash scripts/install-requirements-static.sh

echo ""
echo "=== Step 2: Build SAPIs (static) ==="

# Build each SAPI
for sapi in cli cgi fpm embed phpdbg; do
  echo "Building $sapi..."
  bash scripts/build-static.sh build_sapi "$sapi"
done

echo ""
echo "=== Step 3: Merge builds ==="
bash scripts/build-static.sh merge

echo ""
echo "=== Step 4: Create symlinks ==="
ln -sf /usr/bin/php${PHP_VERSION} /usr/bin/php
ln -sf /usr/bin/php-cgi${PHP_VERSION} /usr/bin/php-cgi
ln -sf /usr/bin/phpdbg${PHP_VERSION} /usr/bin/phpdbg
ln -sf /usr/bin/php-config${PHP_VERSION} /usr/bin/php-config
ln -sf /usr/bin/phpize${PHP_VERSION} /usr/bin/phpize
ln -sf /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm

echo ""
echo "=== Step 5: Verify build ==="
php -v
php -m | wc -l

echo ""
echo "BUILD COMPLETE"
