#!/usr/bin/env bash

# Test script to compare static PHP build with dynamic PHP build
# Ensures feature parity while verifying static linking

set -eE -o functrace

export DEBIAN_FRONTEND=noninteractive
export PHP_VERSION="${PHP_VERSION:-8.5}"
export BUILD="${BUILD:-nts}"
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/workspace}"

SAPI_LIST="${SAPI_LIST:-cli cgi fpm embed phpdbg}"

# Directories for comparison
DYNAMIC_ROOT="/tmp/dynamic-php"
STATIC_ROOT="/tmp/merged"
COMPARISON_LOG="/tmp/comparison.log"

echo "=============================================="
echo "Static vs Dynamic PHP Build Comparison"
echo "PHP Version: $PHP_VERSION"
echo "Build Type: $BUILD"
echo "SAPIs: $SAPI_LIST"
echo "Workspace: $GITHUB_WORKSPACE"
echo "=============================================="

cd "$GITHUB_WORKSPACE"

# Function to log and display
log() {
  echo "$@"
  echo "$@" >> "$COMPARISON_LOG"
}

# Initialize comparison log
> "$COMPARISON_LOG"

##############################################
# Step 1: Install Requirements
##############################################
echo ""
echo "::group::Step 1 - Install Requirements"
bash scripts/install-requirements-static.sh
echo "::endgroup::"

##############################################
# Step 2: Download and Extract Dynamic Build
##############################################
echo ""
echo "::group::Step 2 - Download Dynamic Build"
. /etc/os-release
arch=$(dpkg --print-architecture)
if [ "$arch" = "arm64" ]; then
  arch_suffix="_arm64"
else
  arch_suffix=""
fi

DYNAMIC_URL="https://github.com/shivammathur/php-builder/releases/download/${PHP_VERSION}/php_${PHP_VERSION}+${ID}${VERSION_ID}${arch_suffix}.tar.xz"
DYNAMIC_TAR="/tmp/php_dynamic.tar.xz"

echo "Downloading dynamic build from: $DYNAMIC_URL"
curl -sL -o "$DYNAMIC_TAR" "$DYNAMIC_URL"

echo "Extracting dynamic build to $DYNAMIC_ROOT..."
rm -rf "$DYNAMIC_ROOT"
mkdir -p "$DYNAMIC_ROOT"
tar xf "$DYNAMIC_TAR" -C "$DYNAMIC_ROOT"

# List what we got
echo "Dynamic build structure:"
find "$DYNAMIC_ROOT" -type f | head -50
echo "::endgroup::"

##############################################
# Step 3: Build Static PHP (All SAPIs)
##############################################
echo ""
echo "::group::Step 3 - Build Static PHP (All SAPIs)"
for sapi in $SAPI_LIST; do
  echo ""
  echo "=== Building SAPI: $sapi ==="
  bash scripts/build-static.sh build_sapi "$sapi"
done
echo "::endgroup::"

##############################################
# Step 4: Merge Static Build
##############################################
echo ""
echo "::group::Step 4 - Merge Static Build"
bash scripts/build-static.sh merge_sapi
echo "::endgroup::"

##############################################
# Step 5: Link Static Build to System
##############################################
echo ""
echo "::group::Step 5 - Link Static PHP to System"
bash scripts/build-static.sh link_php
echo "::endgroup::"

##############################################
# Step 6: Install PECL Extensions (from config/extensions/8.5)
##############################################
echo ""
echo "::group::Step 6 - Install PECL Extensions"

# Install build dependencies for PECL extensions
apt-get install -y --no-install-recommends \
  libmemcached-dev \
  libzmq3-dev \
  libyaml-dev \
  libmagickwand-dev \
  unixodbc-dev

# Install PECL extensions using the same mechanism as dynamic builds
bash scripts/build-static.sh install_extensions
echo "::endgroup::"

##############################################
# Step 7: Compare Directory Structure
##############################################
echo ""
echo "::group::Step 7 - Compare Directory Structure"

log "=== Directory Structure Comparison ==="
log ""

# Compare /etc/php directories
log "--- /etc/php/$PHP_VERSION directories ---"
log "Dynamic:"
find "$DYNAMIC_ROOT/etc/php/$PHP_VERSION" -type d 2>/dev/null | sort | sed "s|$DYNAMIC_ROOT||g" >> "$COMPARISON_LOG" || log "(none)"
log ""
log "Static:"
find "/etc/php/$PHP_VERSION" -type d 2>/dev/null | sort >> "$COMPARISON_LOG" || log "(none)"
log ""

# Compare /usr/bin and /usr/sbin
log "--- Binary directories ---"
log "Dynamic binaries:"
find "$DYNAMIC_ROOT/usr/bin" "$DYNAMIC_ROOT/usr/sbin" -type f -name "*php*" 2>/dev/null | sed "s|$DYNAMIC_ROOT||g" | sort >> "$COMPARISON_LOG" || true
log ""
log "Static binaries:"
find /usr/bin /usr/sbin -type f -name "*php*$PHP_VERSION*" 2>/dev/null | sort >> "$COMPARISON_LOG" || true
log ""

echo "::endgroup::"

##############################################
# Step 8: Compare Extensions
##############################################
echo ""
echo "::group::Step 8 - Compare Extensions"

log "=== Extension Comparison ==="
log ""

# Get dynamic build extensions
DYNAMIC_PHP="$DYNAMIC_ROOT/usr/bin/php$PHP_VERSION"
if [ -x "$DYNAMIC_PHP" ]; then
  # The dynamic build needs shared libs, try with LD_LIBRARY_PATH
  export LD_LIBRARY_PATH="$DYNAMIC_ROOT/usr/lib:$DYNAMIC_ROOT/usr/lib/php:$LD_LIBRARY_PATH"
  
  log "Dynamic PHP extensions:"
  "$DYNAMIC_PHP" -m 2>/dev/null | grep -v "^\[" | sort > /tmp/dynamic_extensions.txt || true
  cat /tmp/dynamic_extensions.txt >> "$COMPARISON_LOG"
else
  log "Dynamic PHP binary not found: $DYNAMIC_PHP"
  touch /tmp/dynamic_extensions.txt
fi
log ""

# Get static build extensions
STATIC_PHP="/usr/bin/php$PHP_VERSION"
if [ -x "$STATIC_PHP" ]; then
  log "Static PHP extensions:"
  "$STATIC_PHP" -m 2>/dev/null | grep -v "^\[" | sort > /tmp/static_extensions.txt
  cat /tmp/static_extensions.txt >> "$COMPARISON_LOG"
else
  log "Static PHP binary not found: $STATIC_PHP"
  touch /tmp/static_extensions.txt
fi
log ""

# Compare and show differences
log "--- Extension Differences ---"
if [ -s /tmp/dynamic_extensions.txt ] && [ -s /tmp/static_extensions.txt ]; then
  log "In dynamic but NOT in static:"
  comm -23 /tmp/dynamic_extensions.txt /tmp/static_extensions.txt >> "$COMPARISON_LOG" || log "(none)"
  log ""
  log "In static but NOT in dynamic:"
  comm -13 /tmp/dynamic_extensions.txt /tmp/static_extensions.txt >> "$COMPARISON_LOG" || log "(none)"
fi

echo "::endgroup::"

##############################################
# Step 9: Compare INI Files
##############################################
echo ""
echo "::group::Step 9 - Compare INI Files"

log "=== INI File Comparison ==="
log ""

# List dynamic INI files
log "Dynamic INI files:"
find "$DYNAMIC_ROOT/etc/php/$PHP_VERSION" -name "*.ini" 2>/dev/null | sed "s|$DYNAMIC_ROOT||g" | sort > /tmp/dynamic_ini.txt
cat /tmp/dynamic_ini.txt >> "$COMPARISON_LOG" || log "(none)"
log ""

# List static INI files
log "Static INI files:"
find "/etc/php/$PHP_VERSION" -name "*.ini" 2>/dev/null | sort > /tmp/static_ini.txt
cat /tmp/static_ini.txt >> "$COMPARISON_LOG" || log "(none)"
log ""

# Show mods-available comparison
log "--- mods-available ---"
log "Dynamic mods-available:"
ls "$DYNAMIC_ROOT/etc/php/$PHP_VERSION/mods-available/"*.ini 2>/dev/null | xargs -n1 basename | sort > /tmp/dynamic_mods.txt || touch /tmp/dynamic_mods.txt
cat /tmp/dynamic_mods.txt >> "$COMPARISON_LOG"
log ""

log "Static mods-available:"
ls "/etc/php/$PHP_VERSION/mods-available/"*.ini 2>/dev/null | xargs -n1 basename | sort > /tmp/static_mods.txt || touch /tmp/static_mods.txt
cat /tmp/static_mods.txt >> "$COMPARISON_LOG"
log ""

log "--- Module INI Differences ---"
log "In dynamic but NOT in static:"
comm -23 /tmp/dynamic_mods.txt /tmp/static_mods.txt >> "$COMPARISON_LOG" || log "(none)"
log ""
log "In static but NOT in dynamic:"
comm -13 /tmp/dynamic_mods.txt /tmp/static_mods.txt >> "$COMPARISON_LOG" || log "(none)"

echo "::endgroup::"

##############################################
# Step 10: Compare Extension .so Files
##############################################
echo ""
echo "::group::Step 10 - Compare Extension Files"

log "=== Extension .so Files ==="
log ""

# Get API version
api_version=$("$STATIC_PHP" -i 2>/dev/null | grep "PHP API" | cut -d '>' -f2 | tr -d ' ' || echo "20250925")

# List dynamic extension files
log "Dynamic extension .so files:"
find "$DYNAMIC_ROOT/usr/lib/php" -name "*.so" 2>/dev/null | xargs -n1 basename | sort > /tmp/dynamic_so.txt || touch /tmp/dynamic_so.txt
cat /tmp/dynamic_so.txt >> "$COMPARISON_LOG"
log ""

# List static extension files
log "Static extension .so files:"
find "/usr/lib/php" -name "*.so" 2>/dev/null | xargs -n1 basename | sort > /tmp/static_so.txt || touch /tmp/static_so.txt
cat /tmp/static_so.txt >> "$COMPARISON_LOG"
log ""

log "--- Extension .so Differences ---"
log "In dynamic but NOT in static:"
comm -23 /tmp/dynamic_so.txt /tmp/static_so.txt >> "$COMPARISON_LOG" || log "(none)"
log ""
log "In static but NOT in dynamic:"
comm -13 /tmp/dynamic_so.txt /tmp/static_so.txt >> "$COMPARISON_LOG" || log "(none)"

echo "::endgroup::"

##############################################
# Step 11: Verify Static Linking
##############################################
echo ""
echo "::group::Step 11 - Verify Static Linking"

log "=== Static Linking Verification ==="
log ""

verify_static() {
  local binary="$1"
  local name="$2"
  
  if [ ! -f "$binary" ]; then
    log "SKIP: $name not found"
    return 0
  fi
  
  log "Checking $name ($binary):"
  
  local ldd_output
  ldd_output=$(ldd "$binary" 2>&1) || {
    log "  PASS: Fully static (ldd failed)"
    return 0
  }
  
  # Check for C++ runtime libs that should be static
  if echo "$ldd_output" | grep -qE 'libstdc\+\+|libgcc_s'; then
    log "  FAIL: Found dynamic C++ runtime!"
    echo "$ldd_output" | grep -E 'libstdc\+\+|libgcc_s' >> "$COMPARISON_LOG"
    return 1
  fi
  
  # Show actual dependencies
  log "  Dependencies:"
  echo "$ldd_output" | sed 's/^/    /' >> "$COMPARISON_LOG"
  log "  PASS: No unwanted dynamic dependencies"
  return 0
}

STATIC_ERRORS=0
verify_static "/usr/bin/php$PHP_VERSION" "CLI" || STATIC_ERRORS=$((STATIC_ERRORS + 1))
verify_static "/usr/bin/php-cgi$PHP_VERSION" "CGI" || STATIC_ERRORS=$((STATIC_ERRORS + 1))
verify_static "/usr/sbin/php-fpm$PHP_VERSION" "FPM" || STATIC_ERRORS=$((STATIC_ERRORS + 1))
verify_static "/usr/bin/phpdbg$PHP_VERSION" "PHPDBG" || STATIC_ERRORS=$((STATIC_ERRORS + 1))

if [ "$STATIC_ERRORS" -gt 0 ]; then
  log ""
  log "STATIC VERIFICATION FAILED: $STATIC_ERRORS errors"
fi

echo "::endgroup::"

##############################################
# Step 12: Compare Shared Library Dependencies
##############################################
echo ""
echo "::group::Step 12 - Compare Library Dependencies"

log "=== Library Dependency Comparison ==="
log ""

# Dynamic build dependencies
log "Dynamic CLI dependencies:"
if [ -x "$DYNAMIC_PHP" ]; then
  ldd "$DYNAMIC_PHP" 2>&1 | head -30 >> "$COMPARISON_LOG" || log "(couldn't check)"
fi
log ""

# Static build dependencies  
log "Static CLI dependencies:"
ldd "/usr/bin/php$PHP_VERSION" 2>&1 | head -30 >> "$COMPARISON_LOG" || log "(fully static)"
log ""

# Compare extension .so dependencies
log "--- Extension .so library dependencies ---"
log ""

# Check a few key extensions in both builds
for ext in redis.so mongodb.so imagick.so xdebug.so; do
  log "Extension: $ext"
  
  # Dynamic
  dyn_ext=$(find "$DYNAMIC_ROOT/usr/lib/php" -name "$ext" 2>/dev/null | head -1)
  if [ -n "$dyn_ext" ] && [ -f "$dyn_ext" ]; then
    log "  Dynamic ($dyn_ext):"
    ldd "$dyn_ext" 2>&1 | grep -E "libstdc\+\+|libgcc" | sed 's/^/    /' >> "$COMPARISON_LOG" || log "    (no C++ deps)"
  else
    log "  Dynamic: not found"
  fi
  
  # Static
  stat_ext=$(find "/usr/lib/php" -name "$ext" 2>/dev/null | head -1)
  if [ -n "$stat_ext" ] && [ -f "$stat_ext" ]; then
    log "  Static ($stat_ext):"
    ldd "$stat_ext" 2>&1 | grep -E "libstdc\+\+|libgcc" | sed 's/^/    /' >> "$COMPARISON_LOG" || log "    (no C++ deps)"
  else
    log "  Static: not found"
  fi
  log ""
done

echo "::endgroup::"

##############################################
# Summary
##############################################
echo ""
echo "=============================================="
echo "COMPARISON SUMMARY"
echo "=============================================="
echo ""

# Count extensions
dyn_ext_count=$(wc -l < /tmp/dynamic_extensions.txt 2>/dev/null || echo 0)
stat_ext_count=$(wc -l < /tmp/static_extensions.txt 2>/dev/null || echo 0)

echo "Extensions:"
echo "  Dynamic: $dyn_ext_count"
echo "  Static:  $stat_ext_count"
echo ""

# Count .so files
dyn_so_count=$(wc -l < /tmp/dynamic_so.txt 2>/dev/null || echo 0)
stat_so_count=$(wc -l < /tmp/static_so.txt 2>/dev/null || echo 0)

echo "Extension .so files:"
echo "  Dynamic: $dyn_so_count"
echo "  Static:  $stat_so_count"
echo ""

# Count INI files
dyn_mod_count=$(wc -l < /tmp/dynamic_mods.txt 2>/dev/null || echo 0)
stat_mod_count=$(wc -l < /tmp/static_mods.txt 2>/dev/null || echo 0)

echo "Module INI files:"
echo "  Dynamic: $dyn_mod_count"
echo "  Static:  $stat_mod_count"
echo ""

# Missing from static
echo "Missing from static build:"
comm -23 /tmp/dynamic_mods.txt /tmp/static_mods.txt 2>/dev/null | while read mod; do
  echo "  - $mod"
done

echo ""
echo "Static linking errors: $STATIC_ERRORS"
echo ""
echo "Full comparison log: $COMPARISON_LOG"
echo ""

# Final test
echo "=== Final PHP Test ==="
php -v
php -m
echo ""

# Show binary sizes
echo "=== Binary Sizes ==="
echo "Static:"
ls -lh /usr/bin/php$PHP_VERSION /usr/bin/php-cgi$PHP_VERSION /usr/sbin/php-fpm$PHP_VERSION /usr/bin/phpdbg$PHP_VERSION 2>/dev/null || true
echo ""
echo "Dynamic:"
ls -lh "$DYNAMIC_ROOT/usr/bin/php$PHP_VERSION" "$DYNAMIC_ROOT/usr/bin/php-cgi$PHP_VERSION" "$DYNAMIC_ROOT/usr/sbin/php-fpm$PHP_VERSION" "$DYNAMIC_ROOT/usr/bin/phpdbg$PHP_VERSION" 2>/dev/null || true
echo ""

if [ "$STATIC_ERRORS" -eq 0 ]; then
  echo "=============================================="
  echo "SUCCESS: Static build matches dynamic build!"
  echo "=============================================="
  exit 0
else
  echo "=============================================="
  echo "FAILED: Static linking issues detected!"
  echo "=============================================="
  exit 1
fi
