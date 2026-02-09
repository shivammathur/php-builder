#!/usr/bin/env bash

# Full end-to-end test comparing released, dynamic, and static builds
# Creates 3 Docker containers with identical PHP installations
# Usage: ./fulltest.sh <php_version> [arch]
# Example: ./fulltest.sh 8.5 arm64

set -eE

PHP_INPUT="${1:-8.5}"
ARCH="${2:-$(dpkg --print-architecture 2>/dev/null || uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')}"
BUILD="${BUILD:-nts}"
SAPI_LIST="${SAPI_LIST:-cli cgi fpm phpdbg embed}"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK_DIR="/tmp/fulltest"
mkdir -p "$WORK_DIR"

echo "=== Full Build Test ==="
echo "Input version: $PHP_INPUT"
echo "Architecture: $ARCH"
echo "Build type: $BUILD"
echo "SAPIs: $SAPI_LIST"
echo "Workspace: $GITHUB_WORKSPACE"
echo ""

# Resolve PHP version to stable release (e.g., 8.5 -> 8.5.2)
resolve_version() {
  local version=$1
  local result
  result=$(curl -sL "https://www.php.net/releases/index.php?json&version=$version" | jq -r '.version // empty')
  if [ -z "$result" ]; then
    # Fallback to GitHub API
    result=$(curl -sL "https://api.github.com/repos/php/php-src/tags" | jq -r --arg v "php-$version" '[.[] | select(.name | startswith($v)) | .name | ltrimstr("php-")] | sort_by(split(".") | map(tonumber)) | last // empty')
  fi
  echo "$result"
}

echo "Resolving PHP version..."
PHP_VERSION=$(resolve_version "$PHP_INPUT")
if [ -z "$PHP_VERSION" ]; then
  echo "ERROR: Could not resolve version for PHP $PHP_INPUT"
  exit 1
fi
echo "Resolved version: $PHP_VERSION"

# Get major.minor for config paths
PHP_MAJOR_MINOR="${PHP_VERSION%.*}"

# Determine OS for download URL (default to ubuntu for Docker)
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  # Default for running on macOS - target Ubuntu containers
  ID="ubuntu"
  VERSION_ID="24.04"
fi
OS_VERSION="${ID}-${VERSION_ID}"

# Container base image
BASE_IMAGE="${ID}:${VERSION_ID}"

echo ""
echo "=== Configuration ==="
echo "PHP Version: $PHP_VERSION (from input: $PHP_INPUT)"
echo "Major.minor: $PHP_MAJOR_MINOR"
echo "OS: $OS_VERSION"
echo "Base image: $BASE_IMAGE"
echo ""

# Create Dockerfiles for each build type
create_release_dockerfile() {
  cat > "$WORK_DIR/Dockerfile.release" << 'DOCKEOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG PHP_VERSION
ARG PHP_MAJOR_MINOR
ARG OS_VERSION
ARG ARCH

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies and tools
RUN apt-get update && apt-get install -yq --no-install-recommends \
    curl zstd ca-certificates \
    libxml2 libsqlite3-0 libcurl4 libssl3 libonig5 \
    libpng16-16 libjpeg-turbo8 libfreetype6 libwebp7 \
    libzip4 libsodium23 libargon2-1 libgmp10 \
    libldap2 libpq5 libicu74 libbz2-1.0 libxslt1.1 \
    libedit2 libtidy5deb1 libenchant-2-2 libsnmp40 \
    libffi8

# Download released build
WORKDIR /tmp
RUN set -ex && \
    if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then ARCH_SUFFIX="_arm64"; else ARCH_SUFFIX=""; fi && \
    OS_PART=$(echo $OS_VERSION | sed 's/-//') && \
    DOWNLOAD_URL="https://github.com/shivammathur/php-builder/releases/download/${PHP_MAJOR_MINOR}/php_${PHP_MAJOR_MINOR}+${OS_PART}${ARCH_SUFFIX}.tar.zst" && \
    echo "Downloading: $DOWNLOAD_URL" && \
    curl -fsSL "$DOWNLOAD_URL" -o php.tar.zst && \
    zstd -d php.tar.zst && \
    tar xf php.tar -C / && \
    rm -f php.tar.zst php.tar

# Link PHP to /
RUN ln -sf /usr/bin/php${PHP_MAJOR_MINOR} /usr/bin/php && \
    ln -sf /usr/bin/php-cgi${PHP_MAJOR_MINOR} /usr/bin/php-cgi 2>/dev/null || true && \
    ln -sf /usr/sbin/php-fpm${PHP_MAJOR_MINOR} /usr/sbin/php-fpm 2>/dev/null || true && \
    ln -sf /usr/bin/phpdbg${PHP_MAJOR_MINOR} /usr/bin/phpdbg 2>/dev/null || true

CMD ["php", "-v"]
DOCKEOF
}

create_dynamic_dockerfile() {
  cat > "$WORK_DIR/Dockerfile.dynamic" << 'DOCKEOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG PHP_VERSION
ARG PHP_MAJOR_MINOR
ARG BUILD
ARG SAPI_LIST

ENV DEBIAN_FRONTEND=noninteractive
ENV PHP_VERSION=${PHP_MAJOR_MINOR}
ENV BUILD=${BUILD}
ENV SAPI_LIST="${SAPI_LIST}"
ENV GITHUB_WORKSPACE=/workspace

# Copy workspace
COPY . /workspace
WORKDIR /workspace

# Install requirements
RUN bash scripts/install-requirements.sh

# Build each SAPI one by one (matching CI flow)
RUN set -ex && \
    for sapi in $SAPI_LIST; do \
      echo "=== Building SAPI: $sapi ===" && \
      bash scripts/build.sh build_sapi $sapi; \
    done

# Merge all SAPIs
RUN bash scripts/build.sh merge

# Link PHP to /
RUN ln -sf /usr/bin/php${PHP_MAJOR_MINOR} /usr/bin/php && \
    ln -sf /usr/bin/php-cgi${PHP_MAJOR_MINOR} /usr/bin/php-cgi 2>/dev/null || true && \
    ln -sf /usr/sbin/php-fpm${PHP_MAJOR_MINOR} /usr/sbin/php-fpm 2>/dev/null || true && \
    ln -sf /usr/bin/phpdbg${PHP_MAJOR_MINOR} /usr/bin/phpdbg 2>/dev/null || true

CMD ["php", "-v"]
DOCKEOF
}

create_static_dockerfile() {
  cat > "$WORK_DIR/Dockerfile.static" << 'DOCKEOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG PHP_VERSION
ARG PHP_MAJOR_MINOR
ARG BUILD
ARG SAPI_LIST

ENV DEBIAN_FRONTEND=noninteractive
ENV PHP_VERSION=${PHP_MAJOR_MINOR}
ENV BUILD=${BUILD}
ENV SAPI_LIST="${SAPI_LIST}"
ENV GITHUB_WORKSPACE=/workspace

# Copy workspace
COPY . /workspace
WORKDIR /workspace

# Install static library requirements
RUN bash scripts/install-requirements-static.sh

# Build each SAPI one by one (matching CI flow)
RUN set -ex && \
    for sapi in $SAPI_LIST; do \
      echo "=== Building SAPI: $sapi ===" && \
      bash scripts/build-static.sh build_sapi $sapi; \
    done

# Merge all SAPIs
RUN bash scripts/build-static.sh merge

# Link PHP to / (merge already does this)
RUN ln -sf /usr/bin/php${PHP_MAJOR_MINOR} /usr/bin/php && \
    ln -sf /usr/bin/php-cgi${PHP_MAJOR_MINOR} /usr/bin/php-cgi 2>/dev/null || true && \
    ln -sf /usr/sbin/php-fpm${PHP_MAJOR_MINOR} /usr/sbin/php-fpm 2>/dev/null || true && \
    ln -sf /usr/bin/phpdbg${PHP_MAJOR_MINOR} /usr/bin/phpdbg 2>/dev/null || true

CMD ["php", "-v"]
DOCKEOF
}

# Build containers
echo "=== Building Containers ==="

create_release_dockerfile
create_dynamic_dockerfile
create_static_dockerfile

# Copy workspace to temp for docker build context
rm -rf "$WORK_DIR/context"
cp -r "$GITHUB_WORKSPACE" "$WORK_DIR/context"

echo ""
echo "Building release container..."
docker build -f "$WORK_DIR/Dockerfile.release" \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg PHP_VERSION="$PHP_VERSION" \
  --build-arg PHP_MAJOR_MINOR="$PHP_MAJOR_MINOR" \
  --build-arg OS_VERSION="$OS_VERSION" \
  --build-arg ARCH="$ARCH" \
  -t "php-test-release:$PHP_VERSION" \
  "$WORK_DIR/context" 2>&1 | tee "$WORK_DIR/build-release.log"

echo ""
echo "Building dynamic container..."
docker build -f "$WORK_DIR/Dockerfile.dynamic" \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg PHP_VERSION="$PHP_VERSION" \
  --build-arg PHP_MAJOR_MINOR="$PHP_MAJOR_MINOR" \
  --build-arg BUILD="$BUILD" \
  --build-arg SAPI_LIST="$SAPI_LIST" \
  -t "php-test-dynamic:$PHP_VERSION" \
  "$WORK_DIR/context" 2>&1 | tee "$WORK_DIR/build-dynamic.log"

echo ""
echo "Building static container..."
docker build -f "$WORK_DIR/Dockerfile.static" \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg PHP_VERSION="$PHP_VERSION" \
  --build-arg PHP_MAJOR_MINOR="$PHP_MAJOR_MINOR" \
  --build-arg BUILD="$BUILD" \
  --build-arg SAPI_LIST="$SAPI_LIST" \
  -t "php-test-static:$PHP_VERSION" \
  "$WORK_DIR/context" 2>&1 | tee "$WORK_DIR/build-static.log"

# Compare builds
echo ""
echo "=== Comparing Builds ==="

compare_builds() {
  local container1=$1
  local container2=$2
  local name1=$3
  local name2=$4
  
  echo ""
  echo "--- Comparing $name1 vs $name2 ---"
  
  # Extract file lists
  docker run --rm "$container1" find /usr/bin /usr/sbin /usr/lib/php /etc/php -type f 2>/dev/null | sort > "$WORK_DIR/files-$name1.txt"
  docker run --rm "$container2" find /usr/bin /usr/sbin /usr/lib/php /etc/php -type f 2>/dev/null | sort > "$WORK_DIR/files-$name2.txt"
  
  local count1=$(wc -l < "$WORK_DIR/files-$name1.txt")
  local count2=$(wc -l < "$WORK_DIR/files-$name2.txt")
  
  echo "File count: $name1=$count1, $name2=$count2"
  
  # Show differences
  echo ""
  echo "Files only in $name1:"
  comm -23 "$WORK_DIR/files-$name1.txt" "$WORK_DIR/files-$name2.txt" | head -20
  
  echo ""
  echo "Files only in $name2:"
  comm -13 "$WORK_DIR/files-$name1.txt" "$WORK_DIR/files-$name2.txt" | head -20
}

# PHP version check
echo ""
echo "=== PHP Version Check ==="
echo "Release:"
docker run --rm "php-test-release:$PHP_VERSION" php -v
echo ""
echo "Dynamic:"
docker run --rm "php-test-dynamic:$PHP_VERSION" php -v
echo ""
echo "Static:"
docker run --rm "php-test-static:$PHP_VERSION" php -v

# SAPI check
echo ""
echo "=== SAPI Check ==="
for container in "php-test-release:$PHP_VERSION" "php-test-dynamic:$PHP_VERSION" "php-test-static:$PHP_VERSION"; do
  name="${container%%:*}"
  name="${name##*-}"
  echo "$name SAPIs:"
  docker run --rm "$container" sh -c "ls -la /usr/bin/php* /usr/sbin/php* 2>/dev/null | grep -v 'ize\|config'" || true
  echo ""
done

# Extensions check
echo "=== Extension Count ==="
for container in "php-test-release:$PHP_VERSION" "php-test-dynamic:$PHP_VERSION" "php-test-static:$PHP_VERSION"; do
  name="${container%%:*}"
  name="${name##*-}"
  count=$(docker run --rm "$container" php -m 2>/dev/null | wc -l)
  echo "$name: $count modules"
done

# Binary type check for static
echo ""
echo "=== Static Binary Verification ==="
docker run --rm "php-test-static:$PHP_VERSION" sh -c "ldd /usr/bin/php 2>&1 || echo 'Static binary (no dynamic deps)'"

# Compare release vs dynamic
compare_builds "php-test-release:$PHP_VERSION" "php-test-dynamic:$PHP_VERSION" "release" "dynamic"

# Compare release vs static  
compare_builds "php-test-release:$PHP_VERSION" "php-test-static:$PHP_VERSION" "release" "static"

echo ""
echo "=== Test Complete ==="
echo "Containers created:"
echo "  - php-test-release:$PHP_VERSION"
echo "  - php-test-dynamic:$PHP_VERSION"
echo "  - php-test-static:$PHP_VERSION"
echo ""
echo "Build logs saved to: $WORK_DIR/"
