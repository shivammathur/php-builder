#!/bin/bash
# Full comparison test for dynamic vs static PHP builds
# This script runs inside each container

set -e

export DEBIAN_FRONTEND=noninteractive
export PHP_VERSION="${PHP_VERSION:-8.5}"
export BUILD="${BUILD:-nts}"
export BUILD_MODE="${BUILD_MODE:-dynamic}"
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/workspace}"

cd "$GITHUB_WORKSPACE"

echo "=============================================="
echo "PHP $BUILD_MODE Build Test"
echo "PHP_VERSION: $PHP_VERSION"
echo "BUILD: $BUILD"
echo "=============================================="

INSTALL_ROOT="/tmp/debian/php$PHP_VERSION"
COMPARE_ROOT="/tmp/php-$BUILD_MODE"

# Step 1: Install requirements
echo ""
echo "=== Step 1: Installing requirements ==="
if [ "$BUILD_MODE" = "static" ]; then
  bash scripts/install-requirements-static.sh
else
  # Use the full install-requirements.sh for dynamic builds
  bash scripts/install-requirements.sh
fi
echo "Requirements installed"

# Step 2: Build CLI SAPI
echo ""
echo "=== Step 2: Building CLI SAPI ==="
if [ "$BUILD_MODE" = "static" ]; then
  bash scripts/build.sh build_sapi cli
else
  bash scripts/build.sh build_sapi cli
fi
echo "CLI SAPI built"

# Step 3: Copy to comparison directory
echo ""
echo "=== Step 3: Preparing comparison directory ==="
rm -rf "$COMPARE_ROOT"
mkdir -p "$COMPARE_ROOT"
# After packaging, the install root is renamed to include the SAPI name
PACKAGED_ROOT="${INSTALL_ROOT}-cli"
if [ -d "$PACKAGED_ROOT" ]; then
  cp -a "$PACKAGED_ROOT"/* "$COMPARE_ROOT"/
  echo "Copied $PACKAGED_ROOT to $COMPARE_ROOT"
elif [ -d "$INSTALL_ROOT" ]; then
  cp -a "$INSTALL_ROOT"/* "$COMPARE_ROOT"/
  echo "Copied $INSTALL_ROOT to $COMPARE_ROOT"
else
  echo "ERROR: Neither $PACKAGED_ROOT nor $INSTALL_ROOT found!"
  ls -la /tmp/debian/ 2>/dev/null || true
  exit 1
fi

# Step 4: Generate file listings
echo ""
echo "=== Step 4: Generating file listings ==="

# All files
find "$COMPARE_ROOT" -type f | sort > "/tmp/all-files-$BUILD_MODE.txt"
find "$COMPARE_ROOT" -type d | sort > "/tmp/all-dirs-$BUILD_MODE.txt"
find "$COMPARE_ROOT" -type l | sort > "/tmp/all-links-$BUILD_MODE.txt"

# Normalized paths (for comparison between builds)
find "$COMPARE_ROOT" -type f | sed "s|$COMPARE_ROOT||" | sort > "/tmp/files-normalized-$BUILD_MODE.txt"
find "$COMPARE_ROOT" -type d | sed "s|$COMPARE_ROOT||" | sort > "/tmp/dirs-normalized-$BUILD_MODE.txt"
find "$COMPARE_ROOT" -type l | sed "s|$COMPARE_ROOT||" | sort > "/tmp/links-normalized-$BUILD_MODE.txt"

# Config files only
find "$COMPARE_ROOT/etc" -type f 2>/dev/null | sed "s|$COMPARE_ROOT||" | sort > "/tmp/etc-files-$BUILD_MODE.txt" || touch "/tmp/etc-files-$BUILD_MODE.txt"

# Binaries
find "$COMPARE_ROOT/usr/bin" -type f 2>/dev/null | sed "s|$COMPARE_ROOT||" | sort > "/tmp/bin-files-$BUILD_MODE.txt" || touch "/tmp/bin-files-$BUILD_MODE.txt"

# Libraries
find "$COMPARE_ROOT" -name "*.so" -o -name "*.a" 2>/dev/null | sed "s|$COMPARE_ROOT||" | sort > "/tmp/lib-files-$BUILD_MODE.txt" || touch "/tmp/lib-files-$BUILD_MODE.txt"

# Share files
find "$COMPARE_ROOT/usr/share" -type f 2>/dev/null | sed "s|$COMPARE_ROOT||" | sort > "/tmp/share-files-$BUILD_MODE.txt" || touch "/tmp/share-files-$BUILD_MODE.txt"

# Var files
find "$COMPARE_ROOT/var" -type f 2>/dev/null | sed "s|$COMPARE_ROOT||" | sort > "/tmp/var-files-$BUILD_MODE.txt" || touch "/tmp/var-files-$BUILD_MODE.txt"

echo "File counts:"
echo "  Total files: $(wc -l < /tmp/files-normalized-$BUILD_MODE.txt)"
echo "  Total dirs:  $(wc -l < /tmp/dirs-normalized-$BUILD_MODE.txt)"
echo "  Total links: $(wc -l < /tmp/links-normalized-$BUILD_MODE.txt)"
echo "  etc files:   $(wc -l < /tmp/etc-files-$BUILD_MODE.txt)"
echo "  bin files:   $(wc -l < /tmp/bin-files-$BUILD_MODE.txt)"
echo "  lib files:   $(wc -l < /tmp/lib-files-$BUILD_MODE.txt)"
echo "  share files: $(wc -l < /tmp/share-files-$BUILD_MODE.txt)"
echo "  var files:   $(wc -l < /tmp/var-files-$BUILD_MODE.txt)"

# Step 5: Analyze binaries
echo ""
echo "=== Step 5: Binary Analysis ==="
for bin in "$COMPARE_ROOT"/usr/bin/*; do
  if [ -f "$bin" ] && file "$bin" | grep -q "ELF"; then
    binname=$(basename "$bin")
    echo "Binary: $binname"
    echo "  Type: $(file -b "$bin" | head -c80)"
    echo "  Size: $(du -h "$bin" | cut -f1)"
    ldd_out=$(ldd "$bin" 2>&1) || true
    if echo "$ldd_out" | grep -q "not a dynamic executable\|statically linked"; then
      echo "  Linking: STATIC"
    else
      dynlibs=$(echo "$ldd_out" | grep "=>" | wc -l)
      echo "  Linking: DYNAMIC ($dynlibs shared libs)"
    fi
    echo ""
  fi
done

# Step 6: Analyze shared objects
echo ""
echo "=== Step 6: Shared Object Analysis ==="
find "$COMPARE_ROOT" -name "*.so" -type f 2>/dev/null | while read so; do
  soname=$(echo "$so" | sed "s|$COMPARE_ROOT||")
  echo "SO: $soname"
  echo "  Type: $(file -b "$so" | head -c80)"
done

echo ""
echo "=== $BUILD_MODE build complete ==="
echo "Files preserved in: $COMPARE_ROOT"
echo "File listings in: /tmp/*-$BUILD_MODE.txt"
