#!/usr/bin/env bash

# Test script for new static library build configs
# Tests: qdbm, libyaml, tidy, postgresql, openldap, netsnmp, enchant, zeromq, 
#        libmemcached, imap, libtiff, libde265, libaom, libheif, imagemagick, freetds

set -e

export DEBIAN_FRONTEND=noninteractive
export STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
export BUILD_DIR="/tmp/static-build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Libraries to test (in dependency order)
LIBS_TO_TEST=(
    # Simple libraries first
    "qdbm"
    "libyaml"
    "tidy"
    "freetds"
    # Libraries with dependencies on base libs
    "postgresql"
    "openldap"
    "netsnmp"
    "enchant"
    "zeromq"
    "libmemcached"
    "imap"
    # ImageMagick dependency chain
    "libtiff"
    "libde265"
    "libaom"
    "libheif"
    "imagemagick"
)

# Track results
declare -A RESULTS

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Install base requirements if not already installed
install_base_requirements() {
    log_info "Installing base build requirements..."
    
    apt-get update -qq
    apt-get install -yqq --no-install-recommends \
        autoconf automake bison ca-certificates cmake curl \
        dpkg-dev file flex g++ gcc gettext git gperf \
        libltdl-dev libtool make nasm ninja-build patch \
        perl pkg-config python3 re2c texinfo unzip wget xz-utils
}

# Install base static libraries from prebuilt (needed as dependencies)
install_base_prebuilts() {
    log_info "Installing base prebuilt libraries (dependencies)..."
    
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Run the full requirements installer to get base libraries
    if [ -f "$SCRIPT_DIR/install-requirements-static.sh" ]; then
        bash "$SCRIPT_DIR/install-requirements-static.sh"
    else
        log_warn "Base requirements script not found, some tests may fail"
    fi
}

# Load library config
load_lib_config() {
    local lib_name=$1
    local config_file="/workspace/config/static-libs/$lib_name"
    
    if [ ! -f "$config_file" ]; then
        log_error "Config file not found: $config_file"
        return 1
    fi
    
    # Reset variables
    LIB_SOURCE=""
    LIB_NAME=""
    LIB_VERSION=""
    LIB_URL=""
    LIB_BUILD_CMD=""
    
    # Source the config
    . "$config_file"
    
    return 0
}

# Test building a single library
test_library() {
    local lib_name=$1
    
    echo ""
    echo "========================================"
    log_info "Testing library: $lib_name"
    echo "========================================"
    
    if ! load_lib_config "$lib_name"; then
        RESULTS[$lib_name]="SKIP (no config)"
        return 1
    fi
    
    log_info "Version: ${LIB_VERSION:-unknown}"
    log_info "Source: ${LIB_SOURCE:-build}"
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    rm -rf "$BUILD_DIR"/*
    
    # Check if build_library function exists in config
    if type build_library &>/dev/null; then
        unset -f build_library
    fi
    
    # Re-source to get build_library function
    . "/workspace/config/static-libs/$lib_name"
    
    if type build_library &>/dev/null; then
        log_info "Using build_library() function from config"
        if build_library; then
            log_info "SUCCESS: $lib_name built successfully"
            RESULTS[$lib_name]="SUCCESS"
        else
            log_error "FAILED: $lib_name build failed"
            RESULTS[$lib_name]="FAILED"
            return 1
        fi
    elif [ -n "$LIB_BUILD_CMD" ]; then
        log_info "Using LIB_BUILD_CMD from config"
        if eval "$LIB_BUILD_CMD"; then
            log_info "SUCCESS: $lib_name built successfully"
            RESULTS[$lib_name]="SUCCESS"
        else
            log_error "FAILED: $lib_name build failed"
            RESULTS[$lib_name]="FAILED"
            return 1
        fi
    else
        log_warn "No build method defined for $lib_name"
        RESULTS[$lib_name]="SKIP (no build method)"
        return 1
    fi
    
    # Verify the library was created
    verify_library "$lib_name"
    
    cd /
    rm -rf "$BUILD_DIR"/*
}

# Verify library files exist
verify_library() {
    local lib_name=$1
    
    log_info "Verifying $lib_name installation..."
    
    case "$lib_name" in
        qdbm)
            [ -f "$STATIC_PREFIX/lib/libqdbm.a" ] && log_info "  Found: libqdbm.a" || log_warn "  Missing: libqdbm.a"
            ;;
        libyaml)
            [ -f "$STATIC_PREFIX/lib/libyaml.a" ] && log_info "  Found: libyaml.a" || log_warn "  Missing: libyaml.a"
            ;;
        tidy)
            [ -f "$STATIC_PREFIX/lib/libtidy.a" ] && log_info "  Found: libtidy.a" || log_warn "  Missing: libtidy.a"
            ;;
        postgresql)
            [ -f "$STATIC_PREFIX/lib/libpq.a" ] && log_info "  Found: libpq.a" || log_warn "  Missing: libpq.a"
            [ -x "$STATIC_PREFIX/bin/pg_config" ] && log_info "  Found: pg_config" || log_warn "  Missing: pg_config"
            ;;
        openldap)
            [ -f "$STATIC_PREFIX/lib/libldap.a" ] && log_info "  Found: libldap.a" || log_warn "  Missing: libldap.a"
            [ -f "$STATIC_PREFIX/lib/liblber.a" ] && log_info "  Found: liblber.a" || log_warn "  Missing: liblber.a"
            ;;
        netsnmp)
            [ -f "$STATIC_PREFIX/lib/libnetsnmp.a" ] && log_info "  Found: libnetsnmp.a" || log_warn "  Missing: libnetsnmp.a"
            ;;
        enchant)
            [ -f "$STATIC_PREFIX/lib/libenchant-2.a" ] && log_info "  Found: libenchant-2.a" || log_warn "  Missing: libenchant-2.a"
            ;;
        zeromq)
            [ -f "$STATIC_PREFIX/lib/libzmq.a" ] && log_info "  Found: libzmq.a" || log_warn "  Missing: libzmq.a"
            ;;
        libmemcached)
            [ -f "$STATIC_PREFIX/lib/libmemcached.a" ] && log_info "  Found: libmemcached.a" || log_warn "  Missing: libmemcached.a"
            ;;
        imap)
            [ -f "$STATIC_PREFIX/lib/libc-client.a" ] && log_info "  Found: libc-client.a" || log_warn "  Missing: libc-client.a"
            ;;
        libtiff)
            [ -f "$STATIC_PREFIX/lib/libtiff.a" ] && log_info "  Found: libtiff.a" || log_warn "  Missing: libtiff.a"
            ;;
        libde265)
            [ -f "$STATIC_PREFIX/lib/libde265.a" ] && log_info "  Found: libde265.a" || log_warn "  Missing: libde265.a"
            ;;
        libaom)
            [ -f "$STATIC_PREFIX/lib/libaom.a" ] && log_info "  Found: libaom.a" || log_warn "  Missing: libaom.a"
            ;;
        libheif)
            [ -f "$STATIC_PREFIX/lib/libheif.a" ] && log_info "  Found: libheif.a" || log_warn "  Missing: libheif.a"
            ;;
        imagemagick)
            [ -f "$STATIC_PREFIX/lib/libMagickCore-7.Q16HDRI.a" ] && log_info "  Found: libMagickCore-7.Q16HDRI.a" || log_warn "  Missing: libMagickCore-7.Q16HDRI.a"
            [ -f "$STATIC_PREFIX/lib/libMagickWand-7.Q16HDRI.a" ] && log_info "  Found: libMagickWand-7.Q16HDRI.a" || log_warn "  Missing: libMagickWand-7.Q16HDRI.a"
            ;;
        freetds)
            [ -f "$STATIC_PREFIX/lib/libsybdb.a" ] && log_info "  Found: libsybdb.a" || log_warn "  Missing: libsybdb.a"
            ;;
    esac
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "TEST SUMMARY"
    echo "========================================"
    
    local passed=0
    local failed=0
    local skipped=0
    
    for lib in "${LIBS_TO_TEST[@]}"; do
        local result="${RESULTS[$lib]:-NOT TESTED}"
        case "$result" in
            SUCCESS)
                echo -e "  ${GREEN}✓${NC} $lib"
                passed=$((passed + 1))
                ;;
            FAILED*)
                echo -e "  ${RED}✗${NC} $lib - $result"
                failed=$((failed + 1))
                ;;
            SKIP*)
                echo -e "  ${YELLOW}-${NC} $lib - $result"
                skipped=$((skipped + 1))
                ;;
            *)
                echo -e "  ${YELLOW}?${NC} $lib - $result"
                skipped=$((skipped + 1))
                ;;
        esac
    done
    
    echo ""
    echo "Results: $passed passed, $failed failed, $skipped skipped"
    echo ""
    
    # List created static libraries
    echo "Static libraries created:"
    find "$STATIC_PREFIX/lib" -name "*.a" -newer /tmp/test-start-marker 2>/dev/null | sort || true
    
    return $failed
}

# Main
main() {
    # Check if running in Docker or with workspace mounted
    if [ ! -d "/workspace/config/static-libs" ]; then
        log_error "Workspace not mounted at /workspace"
        log_info "Run this script in Docker with: -v \$PWD:/workspace"
        exit 1
    fi
    
    # Create timestamp marker for tracking new files
    touch /tmp/test-start-marker
    
    # Parse arguments
    local test_specific=""
    if [ $# -gt 0 ]; then
        test_specific="$1"
    fi
    
    # Install base requirements
    install_base_requirements
    
    # Install base prebuilt libraries (openssl, zlib, etc.)
    install_base_prebuilts
    
    # Create static prefix
    mkdir -p "$STATIC_PREFIX"/{lib,lib64,include,bin,share}
    mkdir -p "$BUILD_DIR"
    
    export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig:$STATIC_PREFIX/lib64/pkgconfig"
    
    if [ -n "$test_specific" ]; then
        # Test specific library
        if [[ " ${LIBS_TO_TEST[*]} " =~ " $test_specific " ]]; then
            test_library "$test_specific"
        else
            log_error "Unknown library: $test_specific"
            log_info "Available: ${LIBS_TO_TEST[*]}"
            exit 1
        fi
    else
        # Test all libraries
        for lib in "${LIBS_TO_TEST[@]}"; do
            test_library "$lib" || true
        done
    fi
    
    print_summary
}

main "$@"
