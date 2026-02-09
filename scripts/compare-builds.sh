#!/usr/bin/env bash
# Compare three PHP builds: static, dynamic, and release
# Usage: ./compare-builds.sh
set -eE -o functrace

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${SCRIPT_DIR}/.."

# Configuration
PHP_VERSION="${PHP_VERSION:-8.5}"
BUILD="${BUILD:-nts}"
SAPI_LIST="${SAPI_LIST:-cli cgi fpm embed phpdbg}"
OS_VERSION="ubuntu24.04"
ARCH=$(uname -m)
[[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]] && RELEASE_SUFFIX="_arm64" || RELEASE_SUFFIX=""

# Container names
STATIC_CONTAINER="php-build-static"
DYNAMIC_CONTAINER="php-build-dynamic"
RELEASE_CONTAINER="php-build-release"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

cleanup_containers() {
  log "Cleaning up existing containers..."
  docker stop $STATIC_CONTAINER $DYNAMIC_CONTAINER $RELEASE_CONTAINER 2>/dev/null || true
  docker rm $STATIC_CONTAINER $DYNAMIC_CONTAINER $RELEASE_CONTAINER 2>/dev/null || true
}

start_containers() {
  log "Starting containers..."
  
  for container in $STATIC_CONTAINER $DYNAMIC_CONTAINER $RELEASE_CONTAINER; do
    docker run -d --name "$container" \
      -v "$WORKSPACE:/workspace" \
      -e DEBIAN_FRONTEND=noninteractive \
      -e PHP_VERSION="$PHP_VERSION" \
      -e BUILD="$BUILD" \
      -e SAPI_LIST="$SAPI_LIST" \
      -e GITHUB_WORKSPACE=/workspace \
      -w /workspace \
      ubuntu:24.04 sleep infinity
  done
}

# Build function for a container
run_in_container() {
  local container=$1
  shift
  docker exec -e DEBIAN_FRONTEND=noninteractive \
              -e PHP_VERSION="$PHP_VERSION" \
              -e BUILD="$BUILD" \
              -e SAPI_LIST="$SAPI_LIST" \
              -e GITHUB_WORKSPACE=/workspace \
              "$container" bash -c "$*"
}

build_static() {
  log "Building STATIC PHP..."
  
  run_in_container $STATIC_CONTAINER '
    set -e
    export BUILD_MODE=static
    
    echo "=== Installing static requirements ==="
    bash /workspace/scripts/install-requirements-static.sh
    
    echo "=== Building SAPIs one by one ==="
    for sapi in '"$SAPI_LIST"'; do
      echo "Building SAPI: $sapi"
      bash /workspace/scripts/build.sh build_sapi $sapi
    done
    
    echo "=== Merging builds ==="
    bash /workspace/scripts/build.sh merge
    
    echo "=== Linking PHP to / ==="
    cp -af /tmp/debian/php'"$PHP_VERSION"'/* /
    
    echo "=== Testing extensions ==="
    bash /workspace/scripts/test_extensions.sh || true
    
    echo "=== Static build complete ==="
  '
}

build_dynamic() {
  log "Building DYNAMIC PHP..."
  
  run_in_container $DYNAMIC_CONTAINER '
    set -e
    export BUILD_MODE=dynamic
    
    echo "=== Installing dynamic requirements ==="
    bash /workspace/scripts/install-requirements.sh
    
    echo "=== Building SAPIs one by one ==="
    for sapi in '"$SAPI_LIST"'; do
      echo "Building SAPI: $sapi"
      bash /workspace/scripts/build.sh build_sapi $sapi
    done
    
    echo "=== Merging builds ==="
    bash /workspace/scripts/build.sh merge
    
    echo "=== Linking PHP to / ==="
    cp -af /tmp/debian/php'"$PHP_VERSION"'/* /
    
    echo "=== Testing extensions ==="
    bash /workspace/scripts/test_extensions.sh || true
    
    echo "=== Dynamic build complete ==="
  '
}

setup_release() {
  log "Setting up RELEASE PHP..."
  
  local release_url="https://github.com/shivammathur/php-builder/releases/download/${PHP_VERSION}/php_${PHP_VERSION}+${OS_VERSION}${RELEASE_SUFFIX}.tar.zst"
  
  run_in_container $RELEASE_CONTAINER '
    set -e
    apt-get update
    apt-get install -yq curl zstd
    
    echo "=== Downloading release ==="
    curl -sL "'"$release_url"'" -o /tmp/php-release.tar.zst
    
    echo "=== Extracting release to / ==="
    cd /
    tar --zstd -xf /tmp/php-release.tar.zst
    rm /tmp/php-release.tar.zst
    
    echo "=== Release setup complete ==="
    php -v || true
  '
}

generate_file_list() {
  local container=$1
  local output=$2
  
  run_in_container "$container" '
    find /etc/php /usr/bin/php* /usr/sbin/php* /usr/lib/php /usr/lib/cgi-bin/php* \
         /usr/share/man/man1/php* /usr/share/php \
         -type f 2>/dev/null | sort
  ' > "$output" 2>/dev/null || true
}

generate_module_list() {
  local container=$1
  
  run_in_container "$container" 'php -m 2>/dev/null | sort' 2>/dev/null || echo "FAILED"
}

generate_extension_info() {
  local container=$1
  
  run_in_container "$container" '
    ext_dir=$(php -i 2>/dev/null | grep "extension_dir" | head -1 | cut -d">" -f2 | tr -d " ")
    if [ -d "$ext_dir" ]; then
      ls -la "$ext_dir"/*.so 2>/dev/null | while read line; do
        fname=$(echo "$line" | awk "{print \$NF}")
        size=$(echo "$line" | awk "{print \$5}")
        file_type=$(file "$fname" 2>/dev/null | grep -o "dynamically linked\|statically linked" || echo "unknown")
        echo "$(basename $fname) $size $file_type"
      done | sort
    fi
  ' 2>/dev/null || echo "FAILED"
}

compare_builds() {
  log "Comparing builds..."
  
  local tmpdir=$(mktemp -d)
  
  # Generate file lists
  log "Generating file lists..."
  generate_file_list $STATIC_CONTAINER "$tmpdir/static_files.txt"
  generate_file_list $DYNAMIC_CONTAINER "$tmpdir/dynamic_files.txt"
  generate_file_list $RELEASE_CONTAINER "$tmpdir/release_files.txt"
  
  # Generate module lists
  log "Generating module lists..."
  generate_module_list $STATIC_CONTAINER > "$tmpdir/static_modules.txt"
  generate_module_list $DYNAMIC_CONTAINER > "$tmpdir/dynamic_modules.txt"
  generate_module_list $RELEASE_CONTAINER > "$tmpdir/release_modules.txt"
  
  # Generate extension info
  log "Generating extension info..."
  generate_extension_info $STATIC_CONTAINER > "$tmpdir/static_extensions.txt"
  generate_extension_info $DYNAMIC_CONTAINER > "$tmpdir/dynamic_extensions.txt"
  generate_extension_info $RELEASE_CONTAINER > "$tmpdir/release_extensions.txt"
  
  echo ""
  echo "=========================================="
  echo "         BUILD COMPARISON RESULTS         "
  echo "=========================================="
  echo ""
  
  # Compare files: Dynamic vs Release
  echo "=== FILES: Dynamic vs Release ==="
  if diff -q "$tmpdir/dynamic_files.txt" "$tmpdir/release_files.txt" >/dev/null 2>&1; then
    echo "MATCH: File lists are identical"
  else
    echo "DIFFERENCE found:"
    echo "Only in DYNAMIC:"
    comm -23 "$tmpdir/dynamic_files.txt" "$tmpdir/release_files.txt" | head -20
    echo ""
    echo "Only in RELEASE:"
    comm -13 "$tmpdir/dynamic_files.txt" "$tmpdir/release_files.txt" | head -20
  fi
  echo ""
  
  # Compare files: Static vs Release (should have same structure)
  echo "=== FILES: Static vs Release ==="
  if diff -q "$tmpdir/static_files.txt" "$tmpdir/release_files.txt" >/dev/null 2>&1; then
    echo "MATCH: File lists are identical"
  else
    echo "DIFFERENCE found:"
    echo "Only in STATIC:"
    comm -23 "$tmpdir/static_files.txt" "$tmpdir/release_files.txt" | head -20
    echo ""
    echo "Only in RELEASE:"
    comm -13 "$tmpdir/static_files.txt" "$tmpdir/release_files.txt" | head -20
  fi
  echo ""
  
  # Compare modules: Dynamic vs Release
  echo "=== MODULES: Dynamic vs Release ==="
  if diff -q "$tmpdir/dynamic_modules.txt" "$tmpdir/release_modules.txt" >/dev/null 2>&1; then
    echo "MATCH: Module lists are identical"
  else
    echo "DIFFERENCE found:"
    diff "$tmpdir/dynamic_modules.txt" "$tmpdir/release_modules.txt" || true
  fi
  echo ""
  
  # Compare modules: Static vs Release
  echo "=== MODULES: Static vs Release ==="
  if diff -q "$tmpdir/static_modules.txt" "$tmpdir/release_modules.txt" >/dev/null 2>&1; then
    echo "MATCH: Module lists are identical"
  else
    echo "DIFFERENCE found:"
    diff "$tmpdir/static_modules.txt" "$tmpdir/release_modules.txt" || true
  fi
  echo ""
  
  # Compare extensions: Dynamic vs Release (should be identical)
  echo "=== EXTENSIONS: Dynamic vs Release ==="
  if diff -q "$tmpdir/dynamic_extensions.txt" "$tmpdir/release_extensions.txt" >/dev/null 2>&1; then
    echo "MATCH: Extensions are identical"
  else
    echo "DIFFERENCE found:"
    diff "$tmpdir/dynamic_extensions.txt" "$tmpdir/release_extensions.txt" || true
  fi
  echo ""
  
  # Show extension info
  echo "=== EXTENSION DETAILS ==="
  echo ""
  echo "STATIC extensions:"
  cat "$tmpdir/static_extensions.txt" | head -30
  echo ""
  echo "DYNAMIC extensions:"
  cat "$tmpdir/dynamic_extensions.txt" | head -30
  echo ""
  echo "RELEASE extensions:"
  cat "$tmpdir/release_extensions.txt" | head -30
  
  # Save results
  cp -r "$tmpdir" /tmp/build-comparison
  echo ""
  echo "Full comparison saved to /tmp/build-comparison/"
  
  rm -rf "$tmpdir"
}

test_sapis() {
  log "Testing SAPIs..."
  
  for container in $STATIC_CONTAINER $DYNAMIC_CONTAINER $RELEASE_CONTAINER; do
    echo "=== Testing $container ==="
    run_in_container "$container" '
      echo "PHP Version:"
      php -v
      echo ""
      echo "PHP Binary Type:"
      file /usr/bin/php'"$PHP_VERSION"'
      echo ""
      echo "SAPI files:"
      ls -la /usr/lib/php/'"$PHP_VERSION"'/sapi/ 2>/dev/null || echo "No SAPI dir"
      echo ""
      echo "Loaded modules count:"
      php -m | wc -l
    ' 2>/dev/null || echo "Container $container failed"
    echo ""
  done
}

main() {
  log "Starting PHP build comparison"
  log "PHP Version: $PHP_VERSION"
  log "SAPIs: $SAPI_LIST"
  log "Architecture: $ARCH"
  
  cleanup_containers
  start_containers
  
  # Run builds in sequence
  build_dynamic
  build_static
  setup_release
  
  # Compare
  compare_builds
  test_sapis
  
  log "Comparison complete. Containers are still running for inspection."
  log "To cleanup: docker stop $STATIC_CONTAINER $DYNAMIC_CONTAINER $RELEASE_CONTAINER && docker rm $STATIC_CONTAINER $DYNAMIC_CONTAINER $RELEASE_CONTAINER"
}

main "$@"
