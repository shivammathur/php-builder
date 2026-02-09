#!/usr/bin/env bash
# Install requirements for static PHP builds
# Downloads pre-built static libraries when available, builds from source otherwise

set -eE

# Static prefix for all static libraries
export STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
export BUILD_DIR="${BUILD_DIR:-/tmp/static-build}"
export JOBS="${JOBS:-$(nproc)}"

# Pre-built static library URL
PRE_BUILT_URL="https://dl.static-php.dev/static-php-cli/pre-built"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    ARCH_SUFFIX="aarch64"
elif [ "$ARCH" = "x86_64" ]; then
    ARCH_SUFFIX="x86_64"
else
    ARCH_SUFFIX="$ARCH"
fi

# OS detection for pre-built binaries
if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    ID="linux"
fi

# Determine OS tag for pre-built downloads
case "$ID" in
    debian)
        OS_TAG="debian-bookworm"
        ;;
    ubuntu)
        case "$VERSION_ID" in
            24.04) OS_TAG="ubuntu-2404" ;;
            22.04) OS_TAG="ubuntu-2204" ;;
            *) OS_TAG="debian-bookworm" ;;
        esac
        ;;
    *)
        OS_TAG="debian-bookworm"
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="${GITHUB_WORKSPACE:-$(dirname "$SCRIPT_DIR")}"

echo "=== Installing Static Build Requirements ==="
echo "Static prefix: $STATIC_PREFIX"
echo "Architecture: $ARCH_SUFFIX"
echo "OS tag: $OS_TAG"
echo "Workspace: $WORKSPACE"
echo ""

# Create directories
mkdir -p "$STATIC_PREFIX"/{lib,lib64,include,bin,share}
mkdir -p "$STATIC_PREFIX"/lib/pkgconfig
mkdir -p "$BUILD_DIR"

# Set up pkg-config for static libs
export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig:$STATIC_PREFIX/lib64/pkgconfig"

# Install basic build tools
echo "=== Installing build tools ==="
apt-get update -qq
apt-get install -yq --no-install-recommends \
    apache2 \
    apache2-dev \
    apt-transport-https \
    autoconf \
    automake \
    bison \
    bzip2 \
    ca-certificates \
    cmake \
    curl \
    dpkg-dev \
    file \
    flex \
    g++ \
    gcc \
    gettext \
    git \
    gnupg \
    jq \
    libgcc-13-dev \
    libapache2-mod-fcgid \
    libacl1-dev \
    libapparmor-dev \
    libtool \
    libltdl-dev \
    libsystemd-dev \
    make \
    nasm \
    ninja-build \
    pkg-config \
    re2c \
    sudo \
    wget \
    xz-utils \
    zstd

# Install GitHub CLI for resolving latest git tags
echo ""
echo "=== Installing GitHub CLI ==="
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update -qq
apt-get install -yq gh

# Install libraries for dynamically linked extensions (enchant, firebird)
# These cannot be statically linked due to GLib/PCRE2 conflicts (enchant) and
# complex static build requirements (firebird)
# All other headers come from static library builds/downloads
echo ""
echo "=== Installing libraries for dynamic extensions ==="
apt-get install -yq --no-install-recommends \
    libenchant-2-dev \
    firebird-dev \
    libcurl4-openssl-dev \
    libbsd-dev \
    liblzma-dev \
    libncurses-dev \
    shtool 2>/dev/null || true

# Function to download pre-built static library from static-php-cli
# URL format: https://dl.static-php.dev/static-php-cli/pre-built/{lib}-{arch}-linux-glibc-2.17.txz
download_prebuilt() {
    local lib_name=$1
    local _version=$2  # Unused - kept for compatibility
    
    # Map library names to static-php-cli naming convention
    # Available pre-built: zlib, bzip2, gmp, libsodium, onig, sqlite, libpng, 
    # libyaml, icu, unixodbc, ncurses, openssl, libwebp
    local spc_name="$lib_name"
    case "$lib_name" in
        oniguruma) spc_name="onig" ;;
        # These match as-is: zlib, bzip2, gmp, libsodium, sqlite, libpng, 
        # libyaml, icu, unixodbc, ncurses, openssl, libwebp
    esac
    
    # Try glibc build (most compatible)
    local url="$PRE_BUILT_URL/$spc_name-$ARCH_SUFFIX-linux-glibc-2.17.txz"
    local tmp_file="/tmp/spc-$spc_name.txz"
    
    if curl -fsSL --connect-timeout 15 -L "$url" -o "$tmp_file" 2>/dev/null; then
        # Extract with buildroot prefix handling
        # static-php-cli archives use buildroot/ as top-level directory
        if tar -tJf "$tmp_file" 2>/dev/null | head -1 | grep -q "^buildroot/"; then
            tar -xJf "$tmp_file" -C "$STATIC_PREFIX" --strip-components=1 2>/dev/null
        else
            tar -xJf "$tmp_file" -C "$STATIC_PREFIX" 2>/dev/null
        fi
        rm -f "$tmp_file"
        echo "  Downloaded $lib_name (glibc)"
        return 0
    fi
    
    # Try musl build as fallback
    local musl_url="$PRE_BUILT_URL/$spc_name-$ARCH_SUFFIX-linux-musl-1.2.5.txz"
    if curl -fsSL --connect-timeout 15 -L "$musl_url" -o "$tmp_file" 2>/dev/null; then
        if tar -tJf "$tmp_file" 2>/dev/null | head -1 | grep -q "^buildroot/"; then
            tar -xJf "$tmp_file" -C "$STATIC_PREFIX" --strip-components=1 2>/dev/null
        else
            tar -xJf "$tmp_file" -C "$STATIC_PREFIX" 2>/dev/null
        fi
        rm -f "$tmp_file"
        echo "  Downloaded $lib_name (musl)"
        return 0
    fi
    
    rm -f "$tmp_file" 2>/dev/null
    return 1
}

# Function to build a static library from source
build_static_lib() {
    local lib_name=$1
    local config_file="$WORKSPACE/config/static-libs/$lib_name"
    
    if [ ! -f "$config_file" ]; then
        echo "  No config for $lib_name - skipping"
        return 1
    fi
    
    echo "  Building $lib_name from source..."
    (
        set -e
        cd "$BUILD_DIR"
        rm -rf "$lib_name-build" && mkdir -p "$lib_name-build" && cd "$lib_name-build"
        
        # Source the library config
        source "$config_file"
        
        # Download source if needed
        if [ "$LIB_SOURCE" = "build" ] && [ -n "$LIB_URL" ]; then
            curl -fsSL "$LIB_URL" -o source.tar.gz
            tar -xf source.tar.gz --strip-components=1 2>/dev/null || tar -xf source.tar.gz
            SRC_DIR="$PWD"
        fi
        
        # Run build command
        if [ -n "$LIB_BUILD_CMD" ]; then
            eval "$LIB_BUILD_CMD"
        fi
        
        cd "$BUILD_DIR"
        rm -rf "$lib_name-build"
    ) 2>&1 | tail -20 | sed 's/^/    /'
    
    return ${PIPESTATUS[0]}
}

# Function to check if library exists
lib_exists() {
    local lib_name=$1
    case "$lib_name" in
        zlib)           [ -f "$STATIC_PREFIX/lib/libz.a" ] ;;
        bzip2)          [ -f "$STATIC_PREFIX/lib/libbz2.a" ] ;;
        openssl)        [ -f "$STATIC_PREFIX/lib/libssl.a" ] ;;
        curl)           [ -f "$STATIC_PREFIX/lib/libcurl.a" ] ;;
        libxml2)        [ -f "$STATIC_PREFIX/lib/libxml2.a" ] ;;
        sqlite)         [ -f "$STATIC_PREFIX/lib/libsqlite3.a" ] ;;
        oniguruma)      [ -f "$STATIC_PREFIX/lib/libonig.a" ] ;;
        libffi)         [ -f "$STATIC_PREFIX/lib/libffi.a" ] ;;
        libiconv)       [ -f "$STATIC_PREFIX/lib/libiconv.a" ] ;;
        libsodium)      [ -f "$STATIC_PREFIX/lib/libsodium.a" ] ;;
        gmp)            [ -f "$STATIC_PREFIX/lib/libgmp.a" ] ;;
        ncurses)        [ -f "$STATIC_PREFIX/lib/libncursesw.a" ] || [ -f "$STATIC_PREFIX/lib/libncurses.a" ] ;;
        libedit)        [ -f "$STATIC_PREFIX/lib/libedit.a" ] ;;
        libpng)         [ -f "$STATIC_PREFIX/lib/libpng.a" ] || [ -f "$STATIC_PREFIX/lib/libpng16.a" ] ;;
        libjpeg)        [ -f "$STATIC_PREFIX/lib/libjpeg.a" ] ;;
        libxslt)        [ -f "$STATIC_PREFIX/lib/libxslt.a" ] ;;
        libwebp)        [ -f "$STATIC_PREFIX/lib/libwebp.a" ] ;;
        freetype)       [ -f "$STATIC_PREFIX/lib/libfreetype.a" ] ;;
        libaom)         [ -f "$STATIC_PREFIX/lib/libaom.a" ] ;;
        libde265)       [ -f "$STATIC_PREFIX/lib/libde265.a" ] ;;
        libheif)        [ -f "$STATIC_PREFIX/lib/libheif.a" ] ;;
        libtiff)        [ -f "$STATIC_PREFIX/lib/libtiff.a" ] ;;
        imagemagick)    [ -f "$STATIC_PREFIX/lib/libMagickWand-7.Q16HDRI.a" ] || [ -f "$STATIC_PREFIX/lib/libMagickWand-7.Q16.a" ] ;;
        libzip)         [ -f "$STATIC_PREFIX/lib/libzip.a" ] ;;
        icu)            [ -f "$STATIC_PREFIX/lib/libicuuc.a" ] ;;
        libyaml)        [ -f "$STATIC_PREFIX/lib/libyaml.a" ] ;;
        postgresql)     [ -f "$STATIC_PREFIX/lib/libpq.a" ] ;;
        openldap)       [ -f "$STATIC_PREFIX/lib/libldap.a" ] ;;
        freetds)        [ -f "$STATIC_PREFIX/lib/libsybdb.a" ] ;;
        imap)           [ -f "$STATIC_PREFIX/lib/libc-client.a" ] ;;
        netsnmp)        [ -f "$STATIC_PREFIX/lib/libnetsnmp.a" ] ;;
        tidy)           [ -f "$STATIC_PREFIX/lib/libtidy.a" ] ;;
        zeromq)         [ -f "$STATIC_PREFIX/lib/libzmq.a" ] ;;
        libmemcached)   [ -f "$STATIC_PREFIX/lib/libmemcached.a" ] ;;
        qdbm)           [ -f "$STATIC_PREFIX/lib/libqdbm.a" ] ;;
        lmdb)           [ -f "$STATIC_PREFIX/lib/liblmdb.a" ] ;;
        db4)            [ -f "$STATIC_PREFIX/lib/libdb.a" ] || [ -f "$STATIC_PREFIX/lib/libdb-4.8.a" ] ;;
        unixodbc)       [ -f "$STATIC_PREFIX/lib/libodbc.a" ] ;;
        *)              return 1 ;;
    esac
}

# Function to install a library (try pre-built, then source)
install_static_lib() {
    local lib_name=$1
    local versions=$2  # Space-separated list of versions to try
    
    # Skip if already installed
    if lib_exists "$lib_name"; then
        echo "$lib_name: Already installed"
        return 0
    fi
    
    echo "$lib_name:"
    
    # Always try pre-built first (versions parameter is unused - kept for compatibility)
    # ncurses is built from source to ensure PIC static archives.
    if [ "$lib_name" != "ncurses" ]; then
        if download_prebuilt "$lib_name" ""; then
            return 0
        fi
    fi
    
    # Fall back to building from source
    echo "  Pre-built not available, building from source..."
    if build_static_lib "$lib_name"; then
        echo "  Built successfully"
        return 0
    else
        echo "  Build failed - continuing"
        return 1
    fi
}

echo ""
echo "=== Installing static libraries ==="

# Core libraries in dependency order
# Group 1: No dependencies
install_static_lib "zlib" "" || true
install_static_lib "bzip2" "" || true
install_static_lib "libffi" "" || true
install_static_lib "libiconv" "" || true
install_static_lib "gmp" "" || true
install_static_lib "ncurses" "" || true
install_static_lib "libsodium" "" || true

# Group 2: Depends on group 1
# OpenSSL - try pre-built first, then build from source
if ! lib_exists openssl; then
    echo "openssl:"
    if ! download_prebuilt "openssl" ""; then
        echo "  Pre-built not available, building from source..."
        build_static_lib "openssl" || echo "  OpenSSL build failed"
    fi
else
    echo "openssl: Already installed"
fi
# Fix OpenSSL pkg-config files early (some builds use @build_root_path@)
for pc_file in "$STATIC_PREFIX/lib/pkgconfig/openssl.pc" "$STATIC_PREFIX/lib/pkgconfig/libssl.pc" "$STATIC_PREFIX/lib/pkgconfig/libcrypto.pc"; do
    if [ -f "$pc_file" ] && grep -q "@build_root_path@" "$pc_file"; then
        sed -i "s|@build_root_path@|$STATIC_PREFIX|g" "$pc_file"
    fi
done
install_static_lib "libedit" "" || true
install_static_lib "oniguruma" "" || true
install_static_lib "sqlite" "" || true
install_static_lib "libpng" "" || true
install_static_lib "libjpeg" "" || true

# Group 3: Depends on group 2
install_static_lib "curl" "" || true
install_static_lib "libxml2" "" || true
install_static_lib "freetype" "" || true
install_static_lib "libwebp" "" || true
install_static_lib "libaom" "" || true
install_static_lib "libde265" "" || true
install_static_lib "libheif" "" || true
install_static_lib "libtiff" "" || true

# Group 4: Depends on group 3
install_static_lib "libxslt" "" || true
install_static_lib "libzip" "" || true
install_static_lib "icu" "" || true

# ImageMagick (for imagick extension)
install_static_lib "imagemagick" "" || true

# Additional libraries
install_static_lib "libyaml" "" || true
install_static_lib "tidy" "" || true

# Database libraries
install_static_lib "postgresql" "" || true
install_static_lib "freetds" "" || true
install_static_lib "unixodbc" "" || true
# Note: Firebird is linked dynamically (complex static build requirements)

# IMAP c-client (must be after openssl)
install_static_lib "imap" "" || true

# DBA handler libraries
install_static_lib "qdbm" "" || true
install_static_lib "lmdb" "" || true
install_static_lib "db4" "" || true

# Network libraries
install_static_lib "openldap" "" || true
install_static_lib "netsnmp" "" || true

# Caching libraries
install_static_lib "libmemcached" "" || true
install_static_lib "zeromq" "" || true

# Note: Enchant is linked dynamically (GLib requires pcre2 which conflicts with bundled PCRE2)

# Final summary
echo ""
echo "=== Copying system static libraries ==="
# Copy system static libraries that aren't built from source
for syslib in libcurl.a liblzma.a libbsd.a libltdl.a libargon2.a libpcre2-8.a libpcre2-posix.a; do
    if [ -f "$STATIC_PREFIX/lib/$syslib" ]; then
        echo "  Skipped $syslib (already present)"
        continue
    fi
    if [ -f "/usr/lib/aarch64-linux-gnu/$syslib" ]; then
        cp "/usr/lib/aarch64-linux-gnu/$syslib" "$STATIC_PREFIX/lib/"
        echo "  Copied $syslib"
    elif [ -f "/usr/lib/x86_64-linux-gnu/$syslib" ]; then
        cp "/usr/lib/x86_64-linux-gnu/$syslib" "$STATIC_PREFIX/lib/"
        echo "  Copied $syslib"
    fi
done

echo ""
echo "=== Fixing pkg-config files for static linking ==="
# Update .pc files to properly specify static linking dependencies
# This ensures that when PHP's configure runs pkg-config --static, it gets all required libs

# Fix any build_root_path placeholders in .pc files (notably OpenSSL)
for pc_file in "$STATIC_PREFIX/lib/pkgconfig/"*.pc; do
    if [ -f "$pc_file" ] && grep -q "@build_root_path@" "$pc_file"; then
        sed -i "s|@build_root_path@|$STATIC_PREFIX|g" "$pc_file"
    fi
done

# Fix openssl.pc - needs -ldl -lpthread
if [ -f "$STATIC_PREFIX/lib/pkgconfig/openssl.pc" ]; then
    if ! grep -q "Libs.private:" "$STATIC_PREFIX/lib/pkgconfig/openssl.pc"; then
        echo "Libs.private: -ldl -lpthread" >> "$STATIC_PREFIX/lib/pkgconfig/openssl.pc"
    fi
    echo "  Fixed openssl.pc"
fi

# Add pkg-config file for libyaml if missing.
if [ -f "$STATIC_PREFIX/lib/libyaml.a" ] && [ ! -f "$STATIC_PREFIX/lib/pkgconfig/yaml-0.1.pc" ]; then
    mkdir -p "$STATIC_PREFIX/lib/pkgconfig"
    cat > "$STATIC_PREFIX/lib/pkgconfig/yaml-0.1.pc" <<'EOF'
prefix=/opt/static
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include

Name: libyaml
Description: YAML parser and emitter library
Version: 0.2.5
Libs: -L${libdir} -lyaml
Cflags: -I${includedir}
EOF
    echo "  Created yaml-0.1.pc"
fi

# Fix libcrypto.pc
if [ -f "$STATIC_PREFIX/lib/pkgconfig/libcrypto.pc" ]; then
    if ! grep -q "Libs.private:" "$STATIC_PREFIX/lib/pkgconfig/libcrypto.pc"; then
        echo "Libs.private: -ldl -lpthread" >> "$STATIC_PREFIX/lib/pkgconfig/libcrypto.pc"
    fi
    echo "  Fixed libcrypto.pc"
fi

# Fix libssl.pc
if [ -f "$STATIC_PREFIX/lib/pkgconfig/libssl.pc" ]; then
    if ! grep -q "Libs.private:" "$STATIC_PREFIX/lib/pkgconfig/libssl.pc"; then
        echo "Libs.private: -ldl -lpthread -lcrypto" >> "$STATIC_PREFIX/lib/pkgconfig/libssl.pc"
    fi
    echo "  Fixed libssl.pc"
fi

# Fix libcurl.pc - needs ssl, crypto, z, and system libs
if [ -f "$STATIC_PREFIX/lib/pkgconfig/libcurl.pc" ]; then
    sed -i 's/^Libs:.*/Libs: -L${libdir} -lcurl -lssl -lcrypto -lz -lpthread -ldl/' "$STATIC_PREFIX/lib/pkgconfig/libcurl.pc"
    echo "  Fixed libcurl.pc"
fi

# Fix libxml-2.0.pc - needs lzma, z
if [ -f "$STATIC_PREFIX/lib/pkgconfig/libxml-2.0.pc" ]; then
    if ! grep -q "Libs.private:" "$STATIC_PREFIX/lib/pkgconfig/libxml-2.0.pc"; then
        echo "Libs.private: -llzma -lz -lm" >> "$STATIC_PREFIX/lib/pkgconfig/libxml-2.0.pc"
    fi
    echo "  Fixed libxml-2.0.pc"
fi

# Fix libpq.pc - needs ssl, crypto
if [ -f "$STATIC_PREFIX/lib/pkgconfig/libpq.pc" ]; then
    if ! grep -q "Libs.private:" "$STATIC_PREFIX/lib/pkgconfig/libpq.pc"; then
        echo "Libs.private: -lssl -lcrypto -lpthread" >> "$STATIC_PREFIX/lib/pkgconfig/libpq.pc"
    fi
    echo "  Fixed libpq.pc"
fi

# Fix icu .pc files - need stdc++
for icu_pc in "$STATIC_PREFIX"/lib/pkgconfig/icu*.pc; do
    if [ -f "$icu_pc" ]; then
        if ! grep -q "Libs.private:" "$icu_pc"; then
            echo "Libs.private: -lstdc++ -lm -ldl" >> "$icu_pc"
        fi
    fi
done
echo "  Fixed icu*.pc"

echo ""
echo "=== Creating static linking wrapper ==="
# Create a pkg-config wrapper that always uses --static
# This ensures PHP configure gets static library flags
cat > "$STATIC_PREFIX/bin/pkg-config-static" << 'PKGCFG'
#!/bin/bash
# Wrapper for pkg-config that enforces static linking
# Adds --static flag and prioritizes static library path

STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig:$STATIC_PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"

# Always add --static for proper static library resolution
exec /usr/bin/pkg-config --static "$@"
PKGCFG
chmod +x "$STATIC_PREFIX/bin/pkg-config-static"
echo "  Created pkg-config-static wrapper"

echo ""
echo "=== Converting pkg-config to use full static library paths ==="
# The key fix: modify .pc files to use full paths to .a files instead of -l flags
# This ensures the linker uses static libraries even when system .so files exist
convert_pc_to_static_paths() {
    local pc_file=$1
    local lib_dir="$STATIC_PREFIX/lib"
    
    if [ ! -f "$pc_file" ]; then
        return
    fi
    
    # Backup the original
    cp "$pc_file" "${pc_file}.orig" 2>/dev/null || true
    
    # Get the Libs line and convert -l flags to full paths where .a exists
    # e.g., -lssl becomes /opt/static/lib/libssl.a
    local libs_line=$(grep "^Libs:" "$pc_file" | sed 's/^Libs://')
    local new_libs=""
    
    for flag in $libs_line; do
        if [[ "$flag" == -l* ]]; then
            local lib_name="${flag#-l}"
            local static_lib="$lib_dir/lib${lib_name}.a"
            if [ -f "$static_lib" ]; then
                new_libs="$new_libs $static_lib"
            else
                new_libs="$new_libs $flag"
            fi
        else
            new_libs="$new_libs $flag"
        fi
    done
    
    # Update the Libs line with full paths
    if [ -n "$new_libs" ]; then
        sed -i "s|^Libs:.*|Libs:$new_libs|" "$pc_file"
    fi
}

# Convert key pkg-config files to use full static paths
for pc_file in "$STATIC_PREFIX"/lib/pkgconfig/*.pc; do
    if [ -f "$pc_file" ]; then
        convert_pc_to_static_paths "$pc_file"
        echo "  Converted $(basename "$pc_file")"
    fi
done

echo ""
echo "=== Removing dynamic library symlinks from static prefix ==="
# Remove any .so symlinks/files from static prefix to prevent accidental dynamic linking
find "$STATIC_PREFIX/lib" -name "*.so*" -type f -delete 2>/dev/null || true
find "$STATIC_PREFIX/lib" -name "*.so*" -type l -delete 2>/dev/null || true
find "$STATIC_PREFIX/lib64" -name "*.so*" -type f -delete 2>/dev/null || true
find "$STATIC_PREFIX/lib64" -name "*.so*" -type l -delete 2>/dev/null || true
echo "  Removed .so files from $STATIC_PREFIX"

echo ""
echo "=== Creating linker wrapper for static linking ==="
# Create a linker wrapper that forces static linking for libraries in STATIC_PREFIX
# This is the most reliable way to ensure static linkage
cat > "$STATIC_PREFIX/bin/ld-static-wrapper" << 'LDWRAP'
#!/bin/bash
# Linker wrapper that converts -l flags to full static library paths
# when a static version exists in STATIC_PREFIX

STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
REAL_LD="${REAL_LD:-/usr/bin/ld}"

args=()
for arg in "$@"; do
    if [[ "$arg" == -l* ]]; then
        lib_name="${arg#-l}"
        static_lib="$STATIC_PREFIX/lib/lib${lib_name}.a"
        if [ -f "$static_lib" ]; then
            args+=("$static_lib")
        else
            args+=("$arg")
        fi
    else
        args+=("$arg")
    fi
done

exec "$REAL_LD" "${args[@]}"
LDWRAP
chmod +x "$STATIC_PREFIX/bin/ld-static-wrapper"
echo "  Created ld-static-wrapper"

echo ""
echo "=== Creating multiarch compatibility symlinks ==="
# PHP configure often looks for libraries in lib/MULTIARCH directory
# Create symlinks so it finds our static libraries
MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "aarch64-linux-gnu")
mkdir -p "$STATIC_PREFIX/lib/$MULTIARCH"
# Symlink all .a files to the multiarch dir
for lib in "$STATIC_PREFIX/lib"/*.a; do
    if [ -f "$lib" ]; then
        ln -sf "$lib" "$STATIC_PREFIX/lib/$MULTIARCH/" 2>/dev/null || true
    fi
done
echo "  Created symlinks in $STATIC_PREFIX/lib/$MULTIARCH"

echo ""
echo "=== Setting up SSL certificates ==="
# Link system CA certificates to static OpenSSL path
# This is needed because OpenSSL is built with --openssldir=/opt/static/ssl
mkdir -p "$STATIC_PREFIX/ssl/certs"
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    ln -sf /etc/ssl/certs/ca-certificates.crt "$STATIC_PREFIX/ssl/cert.pem"
    ln -sf /etc/ssl/certs "$STATIC_PREFIX/ssl/certs"
    echo "  Linked system CA certificates"
else
    echo "  WARNING: System CA certificates not found"
fi

echo ""
echo "=== Creating build environment setup script ==="
# Create a setup script that can be sourced before building PHP
cat > "$STATIC_PREFIX/setup-env.sh" << 'ENVSETUP'
#!/bin/bash
# Source this file before building PHP to ensure static linking
# Usage: source /opt/static/setup-env.sh

export STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"

# Prioritize static library paths
export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig:$STATIC_PREFIX/lib64/pkgconfig"

# Use the static pkg-config wrapper
export PKG_CONFIG="$STATIC_PREFIX/bin/pkg-config-static"

# Add static prefix to compiler/linker search paths
export CPPFLAGS="-I$STATIC_PREFIX/include ${CPPFLAGS:-}"
export CFLAGS="-I$STATIC_PREFIX/include ${CFLAGS:-}"

# Force static linking using -Wl,-Bstatic for our libraries
# The order is important: -Bstatic for our libs, then -Bdynamic for system libs
export LDFLAGS="-L$STATIC_PREFIX/lib -L$STATIC_PREFIX/lib64 ${LDFLAGS:-}"

# CRITICAL: Use explicit full paths to static archives in LIBS
# This is the most reliable way to force static linking
build_static_libs() {
    local libs=""
    for lib in libz libxml2 libssl libcrypto libsodium libargon2 libpcre2-8 libonig \
               libsqlite3 libbz2 libpng libjpeg libfreetype libwebp libgmp libedit \
               libffi liblzma libzip libcurl libxslt; do
        if [ -f "$STATIC_PREFIX/lib/${lib}.a" ]; then
            libs="$libs $STATIC_PREFIX/lib/${lib}.a"
        fi
    done
    echo "$libs"
}

# Library paths for configure scripts that don't use pkg-config
# Use FULL PATHS to .a files - not -l flags
export ZLIB_CFLAGS="-I$STATIC_PREFIX/include"
export ZLIB_LIBS="$STATIC_PREFIX/lib/libz.a"

export OPENSSL_CFLAGS="-I$STATIC_PREFIX/include"
export OPENSSL_LIBS="$STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -ldl -lpthread"

export CURL_CFLAGS="-I$STATIC_PREFIX/include"
export CURL_LIBS="$STATIC_PREFIX/lib/libcurl.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a $STATIC_PREFIX/lib/libz.a -lpthread -ldl"

export LIBXML_CFLAGS="-I$STATIC_PREFIX/include/libxml2"
export LIBXML_LIBS="$STATIC_PREFIX/lib/libxml2.a $STATIC_PREFIX/lib/liblzma.a $STATIC_PREFIX/lib/libz.a -lm"

export SQLITE_CFLAGS="-I$STATIC_PREFIX/include"
export SQLITE_LIBS="$STATIC_PREFIX/lib/libsqlite3.a -lpthread -ldl"

export SODIUM_CFLAGS="-I$STATIC_PREFIX/include"
export SODIUM_LIBS="$STATIC_PREFIX/lib/libsodium.a"

export ARGON2_CFLAGS="-I$STATIC_PREFIX/include"
export ARGON2_LIBS="$STATIC_PREFIX/lib/libargon2.a -lpthread"

export PCRE_CFLAGS="-I$STATIC_PREFIX/include"
export PCRE_LIBS="$STATIC_PREFIX/lib/libpcre2-8.a"

export ONIG_CFLAGS="-I$STATIC_PREFIX/include"
export ONIG_LIBS="$STATIC_PREFIX/lib/libonig.a"

export LIBZIP_CFLAGS="-I$STATIC_PREFIX/include"
export LIBZIP_LIBS="$STATIC_PREFIX/lib/libzip.a $STATIC_PREFIX/lib/libz.a $STATIC_PREFIX/lib/libbz2.a $STATIC_PREFIX/lib/liblzma.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a"

export ICU_CFLAGS="-I$STATIC_PREFIX/include"
export ICU_LIBS="$STATIC_PREFIX/lib/libicuio.a $STATIC_PREFIX/lib/libicui18n.a $STATIC_PREFIX/lib/libicuuc.a $STATIC_PREFIX/lib/libicudata.a -lstdc++ -lm -ldl"

export PNG_CFLAGS="-I$STATIC_PREFIX/include"
export PNG_LIBS="$STATIC_PREFIX/lib/libpng.a $STATIC_PREFIX/lib/libz.a"

export JPEG_CFLAGS="-I$STATIC_PREFIX/include"
export JPEG_LIBS="$STATIC_PREFIX/lib/libjpeg.a"

export WEBP_CFLAGS="-I$STATIC_PREFIX/include"
export WEBP_LIBS="$STATIC_PREFIX/lib/libwebp.a"

export FREETYPE_CFLAGS="-I$STATIC_PREFIX/include/freetype2"
export FREETYPE_LIBS="$STATIC_PREFIX/lib/libfreetype.a $STATIC_PREFIX/lib/libpng.a $STATIC_PREFIX/lib/libz.a $STATIC_PREFIX/lib/libbz2.a"

export GMP_CFLAGS="-I$STATIC_PREFIX/include"
export GMP_LIBS="$STATIC_PREFIX/lib/libgmp.a"

export EDIT_CFLAGS="-I$STATIC_PREFIX/include"
export EDIT_LIBS="$STATIC_PREFIX/lib/libedit.a $STATIC_PREFIX/lib/libncursesw.a"

# LDAP requires OpenSSL and other dependencies for static linking
export LDAP_CFLAGS="-I$STATIC_PREFIX/include"
export LDAP_LIBS="$STATIC_PREFIX/lib/libldap.a $STATIC_PREFIX/lib/liblber.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -lpthread -ldl"

# Additional library exports for static linking
export PGSQL_CFLAGS="-I$STATIC_PREFIX/include"
export PGSQL_LIBS="$STATIC_PREFIX/lib/libpq.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -lpthread -ldl"

export FFI_CFLAGS="-I$STATIC_PREFIX/include"
export FFI_LIBS="$STATIC_PREFIX/lib/libffi.a"

export XSL_CFLAGS="-I$STATIC_PREFIX/include/libxslt"
export XSL_LIBS="$STATIC_PREFIX/lib/libxslt.a $STATIC_PREFIX/lib/libexslt.a $STATIC_PREFIX/lib/libxml2.a $STATIC_PREFIX/lib/libz.a $STATIC_PREFIX/lib/liblzma.a -lm"

export TIDY_CFLAGS="-I$STATIC_PREFIX/include"
export TIDY_LIBS="$STATIC_PREFIX/lib/libtidy.a"

export BZ2_CFLAGS="-I$STATIC_PREFIX/include"
export BZ2_LIBS="$STATIC_PREFIX/lib/libbz2.a"

export LMDB_CFLAGS="-I$STATIC_PREFIX/include"
export LMDB_LIBS="$STATIC_PREFIX/lib/liblmdb.a -lpthread"

export QDBM_CFLAGS="-I$STATIC_PREFIX/include"
export QDBM_LIBS="$STATIC_PREFIX/lib/libqdbm.a"

# SASL for LDAP if available
if [ -f "$STATIC_PREFIX/lib/libsasl2.a" ]; then
    export LDAP_LIBS="$STATIC_PREFIX/lib/libldap.a $STATIC_PREFIX/lib/liblber.a $STATIC_PREFIX/lib/libsasl2.a $STATIC_PREFIX/lib/libssl.a $STATIC_PREFIX/lib/libcrypto.a -lpthread -ldl"
fi

# Path additions
export PATH="$STATIC_PREFIX/bin:$PATH"

echo "Static build environment configured."
echo "  STATIC_PREFIX=$STATIC_PREFIX"
echo "  PKG_CONFIG=$PKG_CONFIG"
ENVSETUP
chmod +x "$STATIC_PREFIX/setup-env.sh"
echo "  Created $STATIC_PREFIX/setup-env.sh"

echo ""
echo "=== Static Library Installation Complete ==="
echo "Static libraries: $(find "$STATIC_PREFIX"/lib -name "*.a" 2>/dev/null | wc -l)"
echo "Pkg-config files: $(find "$STATIC_PREFIX"/lib/pkgconfig -name "*.pc" 2>/dev/null | wc -l)"
echo ""
echo "Key libraries:"
for lib in libssl libcrypto libcurl libxml2 libsqlite3 libonig libzip libsodium libffi libz libbz2 libpng libjpeg libfreetype libwebp libgmp libedit libpq libldap libnetsnmp libodbc libodbcinst libsybdb libqdbm liblmdb libdb libc-client libargon2 libpcre2-8; do
    if [ -f "$STATIC_PREFIX/lib/$lib.a" ]; then
        echo "  $lib.a - OK"
    else
        echo "  $lib.a - MISSING (will use system)"
    fi
done

echo ""
echo "=== IMPORTANT: Before building PHP ==="
echo "Source the environment setup script:"
echo "  source $STATIC_PREFIX/setup-env.sh"
echo ""
echo "Static build environment ready."
echo "STATIC_PREFIX=$STATIC_PREFIX"
echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
