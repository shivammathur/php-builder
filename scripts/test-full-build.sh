#!/usr/bin/env bash

# Full build test script for static, dynamic and release comparison
# This script builds PHP using the same process as CI

set -eE

export DEBIAN_FRONTEND=noninteractive
export PHP_VERSION="${PHP_VERSION:-8.5}"
export BUILD="${BUILD:-nts}"
export SAPI_LIST="${SAPI_LIST:-cli cgi fpm embed phpdbg}"
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/workspace}"

cd "$GITHUB_WORKSPACE"

# Import OS information
. /etc/os-release

echo "=== Building PHP $PHP_VERSION ($BUILD) ==="
echo "OS: $ID $VERSION_ID"
echo "SAPIs: $SAPI_LIST"

# Build each SAPI
IFS=' ' read -r -a sapi_arr <<< "$SAPI_LIST"
for sapi in "${sapi_arr[@]}"; do
  echo ""
  echo "=== Building SAPI: $sapi ==="
  bash scripts/build.sh build_sapi "$sapi"
done

# Merge all SAPIs
echo ""
echo "=== Merging SAPIs ==="
bash scripts/build.sh merge

# Verify build
echo ""
echo "=== Verifying Build ==="
php -v
php -m | head -20
echo "..."
echo "Total modules: $(php -m | grep -v '^\[' | grep -v '^$' | wc -l)"

# Test SAPIs
echo ""
echo "=== Testing SAPIs ==="
for sapi in "${sapi_arr[@]}"; do
  case "$sapi" in
    cli)
      php"$PHP_VERSION" -v && echo "CLI: OK" || echo "CLI: FAILED"
      ;;
    cgi)
      php-cgi"$PHP_VERSION" -v && echo "CGI: OK" || echo "CGI: FAILED"
      ;;
    fpm)
      php-fpm"$PHP_VERSION" -v && echo "FPM: OK" || echo "FPM: FAILED"
      ;;
    phpdbg)
      phpdbg"$PHP_VERSION" -v && echo "PHPDBG: OK" || echo "PHPDBG: FAILED"
      ;;
    embed)
      [ -f /usr/lib/libphp"$PHP_VERSION".so ] && echo "EMBED: OK" || echo "EMBED: FAILED"
      ;;
  esac
done

echo ""
echo "=== Build Complete ==="
