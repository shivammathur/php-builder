#!/bin/bash
# Test script for static PHP build
set -e

PHP_VERSION="${1:-8.5.2}"
STATIC_PREFIX="/opt/static"
BUILD_DIR="/tmp/php-static-build"
DEFINITIONS_DIR="/workspace/config/definitions/static"

echo "=== Static PHP $PHP_VERSION Build Test ==="
echo "Static prefix: $STATIC_PREFIX"
echo "Build dir: $BUILD_DIR"

# Source the static build helpers
source /workspace/scripts/build_partials/static/php_build.sh

# Setup static environment
echo ""
echo "=== Setting up static environment ==="
setup_static_environment

echo ""
echo "=== Environment Variables ==="
echo "CFLAGS: $CFLAGS"
echo "LDFLAGS: $LDFLAGS"
echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"

# Download PHP source
echo ""
echo "=== Downloading PHP $PHP_VERSION ==="
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f "php-$PHP_VERSION.tar.gz" ]; then
  curl -fsSL "https://www.php.net/distributions/php-$PHP_VERSION.tar.gz" -o "php-$PHP_VERSION.tar.gz"
fi

if [ ! -d "php-$PHP_VERSION" ]; then
  tar -xzf "php-$PHP_VERSION.tar.gz"
fi

cd "php-$PHP_VERSION"

# Generate configure options from definition file
DEFINITION_FILE="$DEFINITIONS_DIR/8.5"
if [ ! -f "$DEFINITION_FILE" ]; then
  echo "ERROR: Definition file not found: $DEFINITION_FILE"
  exit 1
fi

echo ""
echo "=== Generating configure options ==="

# Build configure options from definition file
CONFIGURE_OPTS=""
while IFS= read -r line || [ -n "$line" ]; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  
  # Skip keywords that are not configure options
  [[ "$line" == "ZTS" || "$line" == "PATCHES" || "$line" == "INSTALL" ]] && continue
  
  # Replace placeholders
  line="${line//BUILD_MACHINE_SYSTEM_TYPE/$(dpkg-architecture -qDEB_BUILD_GNU_TYPE)}"
  line="${line//HOST_MACHINE_SYSTEM_TYPE/$(dpkg-architecture -qDEB_HOST_GNU_TYPE)}"
  line="${line//PHP_VERSION/8.5}"
  
  CONFIGURE_OPTS="$CONFIGURE_OPTS $line"
done < "$DEFINITION_FILE"

echo "Configure options:"
echo "$CONFIGURE_OPTS" | tr ' ' '\n' | grep -v "^$" | head -30
echo "..."

# Run configure
echo ""
echo "=== Running configure ==="
./configure $CONFIGURE_OPTS 2>&1 | tee /tmp/configure.log | tail -100

if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo ""
  echo "=== Configure failed! Last 50 lines of config.log: ==="
  tail -50 config.log
  exit 1
fi

# Patch Makefile to use static C++ libraries instead of dynamic
echo ""
echo "=== Patching Makefile for static C++ linkage ==="
GCC_LIB_DIR="/usr/lib/gcc/$(dpkg-architecture -qDEB_HOST_GNU_TYPE)/13"
if [ -f "$GCC_LIB_DIR/libstdc++.a" ]; then
  # Replace -lstdc++ with static library path
  sed -i "s|-lstdc++|$GCC_LIB_DIR/libstdc++.a $GCC_LIB_DIR/libgcc.a|g" Makefile
  # Add static libgcc to the end of EXTRA_LIBS to ensure it's linked
  sed -i "s|^EXTRA_LIBS = |EXTRA_LIBS = -static-libgcc |" Makefile
  echo "Patched Makefile to use static libstdc++ and libgcc"
else
  echo "Warning: Static libstdc++ not found at $GCC_LIB_DIR"
fi

# Build PHP
echo ""
echo "=== Building PHP ==="
make -j"$(nproc)" 2>&1 | tail -50

if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo "Build failed!"
  exit 1
fi

# Check binary
echo ""
echo "=== Checking PHP binary ==="
ls -la sapi/cli/php
file sapi/cli/php

echo ""
echo "=== Checking dynamic dependencies (ldd) ==="
ldd sapi/cli/php 2>&1 || echo "(statically linked)"

echo ""
echo "=== PHP version and modules ==="
./sapi/cli/php -v
echo ""
./sapi/cli/php -m | wc -l
echo ""
./sapi/cli/php -m

echo ""
echo "=== Build complete ==="
