#!/bin/bash
# compare-static-dynamic.sh
# Compares file structures between static and dynamic PHP builds
# Files in both builds should match, except binaries should be statically linked

set -euo pipefail

# Usage: ./compare-static-dynamic.sh <php_version> <dynamic_root> <static_root>
# Example: ./compare-static-dynamic.sh 8.5 /tmp/debian/php8.5-dynamic /tmp/debian/php8.5-static

PHP_VERSION="${1:-8.5}"
DYNAMIC_ROOT="${2:-/tmp/debian/php$PHP_VERSION}"
STATIC_ROOT="${3:-/tmp/debian/php$PHP_VERSION-static}"

echo "=== Comparing PHP $PHP_VERSION builds ==="
echo "Dynamic root: $DYNAMIC_ROOT"
echo "Static root: $STATIC_ROOT"
echo ""

# Check if both directories exist
if [ ! -d "$DYNAMIC_ROOT" ]; then
  echo "ERROR: Dynamic build directory not found: $DYNAMIC_ROOT"
  exit 1
fi

if [ ! -d "$STATIC_ROOT" ]; then
  echo "ERROR: Static build directory not found: $STATIC_ROOT"
  exit 1
fi

# Create temp files for file lists
DYNAMIC_FILES=$(mktemp)
STATIC_FILES=$(mktemp)
trap 'rm -f "$DYNAMIC_FILES" "$STATIC_FILES"' EXIT

# Get sorted file lists (relative paths)
(cd "$DYNAMIC_ROOT" && find . -type f | sort) > "$DYNAMIC_FILES"
(cd "$STATIC_ROOT" && find . -type f | sort) > "$STATIC_FILES"

echo "=== File Count Comparison ==="
echo "Dynamic build files: $(wc -l < "$DYNAMIC_FILES")"
echo "Static build files: $(wc -l < "$STATIC_FILES")"
echo ""

echo "=== Files only in dynamic build ==="
comm -23 "$DYNAMIC_FILES" "$STATIC_FILES" || true
echo ""

echo "=== Files only in static build ==="
comm -13 "$DYNAMIC_FILES" "$STATIC_FILES" || true
echo ""

echo "=== Binary Comparison ==="
echo "Checking if static binaries are truly static..."
echo ""

check_binary() {
  local binary="$1"
  local label="$2"
  
  if [ ! -f "$binary" ]; then
    echo "SKIP: $label - not found"
    return
  fi
  
  local ldd_output
  ldd_output=$(ldd "$binary" 2>&1) || true
  
  if echo "$ldd_output" | grep -qE "(not a dynamic executable|statically linked)"; then
    echo "PASS: $label - fully static"
  elif echo "$ldd_output" | grep -qE "libstdc\+\+|libgcc_s"; then
    echo "FAIL: $label - has dynamic C++ runtime"
    echo "      $(echo "$ldd_output" | grep -E "libstdc\+\+|libgcc_s" | head -2)"
  else
    echo "PASS: $label - no C++ runtime dependencies"
  fi
}

# Check static binaries
echo "Static build binaries:"
check_binary "$STATIC_ROOT/usr/bin/php$PHP_VERSION" "php (cli)"
check_binary "$STATIC_ROOT/usr/bin/php-cgi$PHP_VERSION" "php-cgi"
check_binary "$STATIC_ROOT/usr/bin/phpdbg$PHP_VERSION" "phpdbg"
check_binary "$STATIC_ROOT/usr/sbin/php-fpm$PHP_VERSION" "php-fpm"

echo ""
echo "Dynamic build binaries (for reference):"
check_binary "$DYNAMIC_ROOT/usr/bin/php$PHP_VERSION" "php (cli)"
check_binary "$DYNAMIC_ROOT/usr/bin/php-cgi$PHP_VERSION" "php-cgi"
check_binary "$DYNAMIC_ROOT/usr/bin/phpdbg$PHP_VERSION" "phpdbg"
check_binary "$DYNAMIC_ROOT/usr/sbin/php-fpm$PHP_VERSION" "php-fpm"

echo ""
echo "=== Extension .so Files ==="
API_VERSION=$(find "$DYNAMIC_ROOT/usr/lib/php" -maxdepth 1 -type d -name '20*' | head -1 | xargs basename 2>/dev/null || echo "unknown")
echo "API Version: $API_VERSION"
echo ""

DYNAMIC_EXT_DIR="$DYNAMIC_ROOT/usr/lib/php/$API_VERSION"
STATIC_EXT_DIR="$STATIC_ROOT/usr/lib/php/$API_VERSION"

if [ -d "$DYNAMIC_EXT_DIR" ]; then
  echo "Dynamic extensions: $(find "$DYNAMIC_EXT_DIR" -name '*.so' 2>/dev/null | wc -l)"
else
  echo "Dynamic extensions: 0 (directory not found)"
fi

if [ -d "$STATIC_EXT_DIR" ]; then
  echo "Static extensions: $(find "$STATIC_EXT_DIR" -name '*.so' 2>/dev/null | wc -l)"
else
  echo "Static extensions: 0 (directory not found)"
fi

echo ""
echo "=== Config Files Comparison ==="
CONF_DIR="etc/php/$PHP_VERSION"

echo "Comparing conf.d symlinks..."
if [ -d "$DYNAMIC_ROOT/$CONF_DIR" ] && [ -d "$STATIC_ROOT/$CONF_DIR" ]; then
  for sapi in cli fpm cgi; do
    dynamic_count=$(find "$DYNAMIC_ROOT/$CONF_DIR/$sapi/conf.d" -type l 2>/dev/null | wc -l || echo 0)
    static_count=$(find "$STATIC_ROOT/$CONF_DIR/$sapi/conf.d" -type l 2>/dev/null | wc -l || echo 0)
    echo "  $sapi conf.d symlinks - dynamic: $dynamic_count, static: $static_count"
  done
fi

echo ""
echo "=== Binary Sizes ==="
compare_size() {
  local dynamic="$1"
  local static="$2"
  local label="$3"
  
  local d_size=0 s_size=0
  [ -f "$dynamic" ] && d_size=$(stat -c%s "$dynamic" 2>/dev/null || stat -f%z "$dynamic" 2>/dev/null || echo 0)
  [ -f "$static" ] && s_size=$(stat -c%s "$static" 2>/dev/null || stat -f%z "$static" 2>/dev/null || echo 0)
  
  local d_mb=$((d_size / 1024 / 1024))
  local s_mb=$((s_size / 1024 / 1024))
  
  printf "%-12s dynamic: %4dMB (%10d bytes)  static: %4dMB (%10d bytes)\n" "$label" "$d_mb" "$d_size" "$s_mb" "$s_size"
}

compare_size "$DYNAMIC_ROOT/usr/bin/php$PHP_VERSION" "$STATIC_ROOT/usr/bin/php$PHP_VERSION" "php"
compare_size "$DYNAMIC_ROOT/usr/bin/php-cgi$PHP_VERSION" "$STATIC_ROOT/usr/bin/php-cgi$PHP_VERSION" "php-cgi"
compare_size "$DYNAMIC_ROOT/usr/bin/phpdbg$PHP_VERSION" "$STATIC_ROOT/usr/bin/phpdbg$PHP_VERSION" "phpdbg"
compare_size "$DYNAMIC_ROOT/usr/sbin/php-fpm$PHP_VERSION" "$STATIC_ROOT/usr/sbin/php-fpm$PHP_VERSION" "php-fpm"

echo ""
echo "=== Summary ==="
echo "Comparison complete. Review the output above for differences."
echo "Expected differences:"
echo "  - Static binaries should be larger (all dependencies bundled)"
echo "  - Static binaries should have no libstdc++ or libgcc_s dependencies"
echo "  - File structure should otherwise be identical"
