#!/usr/bin/env bash
# Comprehensive build test script
# Tests static, dynamic, and release builds

set -eE

export DEBIAN_FRONTEND=noninteractive
export GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-/workspace}
export PHP_VERSION=${PHP_VERSION:-8.5}
export BUILD=${BUILD:-nts}
export SAPI_LIST=${SAPI_LIST:-"cli cgi fpm embed phpdbg"}
export BUILD_MODE=${BUILD_MODE:-dynamic}  # static, dynamic, or release

# Constants
FAKE_ROOT=/tmp
INSTALL_ROOT="$FAKE_ROOT/debian/php$PHP_VERSION"
prefix=/usr
conf_dir=/etc/php/$PHP_VERSION
mods_dir=$conf_dir/mods-available
php_build_dir='/usr/local/share/php-build'
definitions="$php_build_dir/definitions"
default_options="$php_build_dir/default_configure_options"

echo "=== Build Mode: $BUILD_MODE ==="
echo "PHP Version: $PHP_VERSION"
echo "Build Type: $BUILD"
echo "SAPI List: $SAPI_LIST"

# Function to install build requirements
install_requirements() {
    echo "=== Installing Requirements ==="
    if [ "$BUILD_MODE" = "static" ]; then
        bash "$GITHUB_WORKSPACE/scripts/install-requirements-static.sh"
    else
        bash "$GITHUB_WORKSPACE/scripts/install-requirements.sh"
    fi
}

# Function to download release build
download_release() {
    echo "=== Downloading Release Build ==="
    
    # Install curl and jq
    apt-get update -qq
    apt-get install -y -qq curl jq xz-utils ca-certificates > /dev/null 2>&1
    
    # Get the release download URL
    ARCH=$(dpkg --print-architecture)
    . /etc/os-release
    
    # Fetch release tarball
    API_URL="https://api.github.com/repos/shivammathur/php-builder/releases/tags/$PHP_VERSION"
    # Format: php_8.5+ubuntu24.04_arm64.tar.xz or php_8.5+ubuntu24.04.tar.xz for amd64
    if [ "$ARCH" = "amd64" ]; then
        TARBALL_NAME="php_${PHP_VERSION}+ubuntu${VERSION_ID}.tar.xz"
    else
        TARBALL_NAME="php_${PHP_VERSION}+ubuntu${VERSION_ID}_${ARCH}.tar.xz"
    fi
    
    DOWNLOAD_URL=$(curl -sL "$API_URL" | jq -r ".assets[] | select(.name == \"$TARBALL_NAME\") | .browser_download_url")
    
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        echo "ERROR: Could not find release tarball: $TARBALL_NAME"
        return 1
    fi
    
    echo "Downloading: $DOWNLOAD_URL"
    curl -sL "$DOWNLOAD_URL" -o /tmp/php-release.tar.xz
    
    # Extract to root
    mkdir -p "$INSTALL_ROOT"
    tar -xJf /tmp/php-release.tar.xz -C /
    
    # Copy to INSTALL_ROOT for comparison
    for dir in /usr /etc /lib; do
        if [ -d "$dir" ]; then
            mkdir -p "$INSTALL_ROOT/$dir"
            cp -af "$dir"/php* "$INSTALL_ROOT/$dir/" 2>/dev/null || true
            cp -af "$dir"/cgi-bin "$INSTALL_ROOT/$dir/" 2>/dev/null || true
        fi
    done
    
    echo "Release installed successfully"
}

# Function to build a single SAPI
build_sapi() {
    local sapi=$1
    echo "=== Building SAPI: $sapi ==="
    
    cd "$GITHUB_WORKSPACE"
    
    # Source required scripts
    . scripts/build_partials/sapi/"$sapi".sh
    . scripts/build_partials/package.sh
    . scripts/build_partials/php_build.sh
    . scripts/build_partials/version.sh
    
    # Clean and prepare
    rm -rf ~/php-build "$INSTALL_ROOT" "$php_build_dir"
    mkdir -p ~/php-build "$INSTALL_ROOT" "$php_build_dir"
    
    # Get PHP version and setup
    get_version
    setup_phpbuild
    
    # Build the SAPI
    build_"$sapi"
}

# Function to merge all SAPI builds
merge_builds() {
    echo "=== Merging SAPI Builds ==="
    
    cd "$GITHUB_WORKSPACE"
    
    . scripts/build_partials/cleanup.sh
    . scripts/build_partials/extensions.sh
    . scripts/build_partials/package.sh
    . scripts/build_partials/strip.sh
    . scripts/build_partials/pear.sh
    
    # Create directories
    mkdir -p "$INSTALL_ROOT" \
             "$INSTALL_ROOT/etc/php/$PHP_VERSION/mods-available" \
             "$INSTALL_ROOT/usr/lib/php/$PHP_VERSION/sapi"
    
    # Merge SAPI builds
    IFS=' ' read -r -a sapi_arr <<< "$SAPI_LIST"
    for sapi in "${sapi_arr[@]}"; do
        echo "  Merging $sapi..."
        cp -af "$INSTALL_ROOT-$sapi"/* "$INSTALL_ROOT"
        touch "$INSTALL_ROOT/usr/lib/php/$PHP_VERSION/sapi/$sapi"
    done
    
    # Fix directory structure
    rm -rf "${INSTALL_ROOT:?}/var" "$INSTALL_ROOT/run"
    if [ -h /lib ] && [ -d "$INSTALL_ROOT/lib" ]; then
        cp -rf "$INSTALL_ROOT/lib" "$INSTALL_ROOT/usr"
        rm -rf "${INSTALL_ROOT:?}/lib"
    fi
    
    # Make sure php-cli is from cli build
    cp -f "$INSTALL_ROOT-cli/usr/bin/php$PHP_VERSION" "$INSTALL_ROOT/usr/bin"
    
    # Fix phar binary
    if [ -f "$INSTALL_ROOT/usr/bin/phar$PHP_VERSION.phar" ]; then
        cp "$INSTALL_ROOT/usr/bin/phar$PHP_VERSION.phar" "$INSTALL_ROOT/usr/bin/phar.phar$PHP_VERSION"
        cp "$INSTALL_ROOT/usr/share/man/man1/phar$PHP_VERSION.phar.1" "$INSTALL_ROOT/usr/share/man/man1/phar.phar$PHP_VERSION.1" 2>/dev/null || true
    fi
    ln -sf /usr/bin/phar.phar"$PHP_VERSION" "$INSTALL_ROOT/usr/bin/phar$PHP_VERSION"
    
    # Copy switch scripts
    cp -fp scripts/switch_sapi "$INSTALL_ROOT/usr/sbin/switch_sapi"
    cp -fp scripts/switch_jit "$INSTALL_ROOT/usr/sbin/switch_jit"
    
    # Make binaries executable
    chmod -R a+x "$INSTALL_ROOT/usr/bin" "$INSTALL_ROOT/usr/sbin"
    
    # Copy nginx config
    mkdir -p "$INSTALL_ROOT/etc/nginx/sites-available"
    sed "s/PHP_VERSION/$PHP_VERSION/g" config/default_nginx > "$INSTALL_ROOT/etc/nginx/sites-available/default"
    
    # Link to system
    cp -af "$INSTALL_ROOT"/* /
    
    # Install alternatives
    switch_version
}

# Function to configure extensions
configure_extensions() {
    echo "=== Configuring Extensions ==="
    
    cd "$GITHUB_WORKSPACE"
    . scripts/build_partials/extensions.sh
    
    # Configure shared extensions
    configure_shared_extensions
    
    # Setup custom PECL extensions
    setup_custom_extensions
}

# Function to configure INI files
configure_ini_files() {
    echo "=== Configuring INI Files ==="
    
    IFS=' ' read -r -a sapi_arr <<< "$SAPI_LIST"
    
    # Get all php.ini files
    mapfile -t ini_files < <(find "$INSTALL_ROOT/$conf_dir" -name "php.ini" -exec readlink -m {} +)
    
    # Create pecl.ini
    pecl_file="$mods_dir/pecl.ini"
    touch "$INSTALL_ROOT/$pecl_file"
    
    # Link pecl.ini to all SAPIs
    for sapi in "${sapi_arr[@]}"; do
        ln -sf "$pecl_file" "$INSTALL_ROOT/$conf_dir/$sapi/conf.d/99-pecl.ini"
    done
    
    # Set permissions
    chmod 777 "${ini_files[@]}" "$INSTALL_ROOT/$pecl_file" 2>/dev/null || true
    
    # Link to system
    cp -af "$INSTALL_ROOT"/* /
}

# Function to setup FPM config
setup_fpm_config() {
    echo "=== Setting up FPM Config ==="
    
    mkdir -p /run/php
    
    # Copy FPM config files if they exist
    if [ -f "$GITHUB_WORKSPACE/config/php-fpm.conf" ]; then
        cp "$GITHUB_WORKSPACE/config/php-fpm.conf" "/etc/php/$PHP_VERSION/fpm/php-fpm.conf"
    fi
    
    if [ -f "$GITHUB_WORKSPACE/config/php-fpm.service" ]; then
        mkdir -p /lib/systemd/system
        sed "s/PHP_VERSION/$PHP_VERSION/g" "$GITHUB_WORKSPACE/config/php-fpm.service" > "/lib/systemd/system/php$PHP_VERSION-fpm.service"
    fi
}

# Function to configure JIT
setup_jit_config() {
    echo "=== Setting up JIT Config ==="
    
    # Enable opcache and JIT in CLI for testing
    cat > "/etc/php/$PHP_VERSION/cli/conf.d/10-opcache-jit.ini" << 'EOF'
opcache.enable=1
opcache.enable_cli=1
opcache.jit=1255
opcache.jit_buffer_size=256M
EOF
}

# Function to install update-alternatives
switch_version() {
    echo "Installing alternatives..."
    
    # Install libphp
    update-alternatives --install /usr/lib/libphp"${PHP_VERSION/%.*}".so libphp"${PHP_VERSION/%.*}" /usr/lib/libphp"$PHP_VERSION".so "${PHP_VERSION/./}" 2>/dev/null || true
    ldconfig 2>/dev/null || true
    
    # Install CGI
    update-alternatives --install /usr/lib/cgi-bin/php php-cgi-bin /usr/lib/cgi-bin/php"$PHP_VERSION" "${PHP_VERSION/./}" 2>/dev/null || true
    update-alternatives --set php-cgi-bin /usr/lib/cgi-bin/php"$PHP_VERSION" 2>/dev/null || true
    
    # Install FPM
    update-alternatives --install /usr/bin/php-fpm php-fpm /usr/sbin/php-fpm"$PHP_VERSION" "${PHP_VERSION/./}" 2>/dev/null || true
    update-alternatives --set php-fpm /usr/sbin/php-fpm"$PHP_VERSION" 2>/dev/null || true
    
    # Install other tools
    for tool in phar phar.phar php-config phpize php php-cgi phpdbg; do
        update-alternatives --install /usr/bin/"$tool" "$tool" /usr/bin/"$tool$PHP_VERSION" "${PHP_VERSION/./}" 2>/dev/null || true
        update-alternatives --set "$tool" /usr/bin/"$tool$PHP_VERSION" 2>/dev/null || true
    done
}

# Function to test extensions
test_extensions() {
    echo "=== Testing Extensions ==="
    
    php -v
    echo ""
    php -m
    echo ""
    
    # Test each extension from config
    while read -r extension_config; do
        extension=$(echo "$extension_config" | cut -d ' ' -f 2 | cut -d '-' -f 1)
        if [ "$extension" = "pcov" ]; then
            ln -sf "/etc/php/$PHP_VERSION/mods-available/pcov.ini" "/etc/php/$PHP_VERSION/cli/conf.d/20-pcov.ini" 2>/dev/null || true
        fi
        if php -r "if(! extension_loaded(\"$extension\")) {echo \"MISSING: $extension\n\"; exit(1);}" 2>/dev/null; then
            echo "OK: $extension"
        else
            echo "FAIL: $extension"
        fi
    done < "$GITHUB_WORKSPACE/config/extensions/$PHP_VERSION"
}

# Function to test SAPI
test_sapi() {
    echo "=== Testing SAPI ==="
    
    # Install web servers for testing
    apt-get install -y -qq nginx apache2 libapache2-mod-fcgid > /dev/null 2>&1 || true
    
    mkdir -p /var/www/html
    rm -f /var/www/html/index.html
    printf '<?php echo current(explode("-", php_sapi_name())).":".strtolower(current(explode("/", $_SERVER["SERVER_SOFTWARE"])))."\n";' > /var/www/html/index.php
    
    # Test each SAPI
    for sapi in fpm:apache fpm:nginx cgi:apache; do
        echo "Testing $sapi..."
        if switch_sapi -v "$PHP_VERSION" -s "$sapi" 2>/dev/null; then
            sleep 2
            resp=$(curl -s http://localhost 2>/dev/null || echo "CURL_FAILED")
            if [ "$sapi" = "$resp" ]; then
                echo "  OK: $resp"
            else
                echo "  WARN: Expected '$sapi', got '$resp'"
            fi
        else
            echo "  SKIP: switch_sapi failed for $sapi"
        fi
    done
}

# Function to show binary info
show_binary_info() {
    echo "=== Binary Info ==="
    echo ""
    echo "--- php -v ---"
    php -v
    echo ""
    echo "--- php -m ---"
    php -m
    echo ""
    echo "--- ldd php ---"
    ldd /usr/bin/php"$PHP_VERSION" 2>&1 || echo "ldd failed or binary is static"
    echo ""
    echo "--- file php ---"
    file /usr/bin/php"$PHP_VERSION"
}

# Function to list installed files
list_installed_files() {
    echo "=== Installed Files ==="
    
    # List key directories
    echo "--- /usr/bin/php* ---"
    ls -la /usr/bin/php* 2>/dev/null | head -20
    echo ""
    echo "--- /usr/sbin/php* ---"
    ls -la /usr/sbin/php* 2>/dev/null | head -10
    echo ""
    echo "--- Extension directory ---"
    ext_dir=$(php-config"$PHP_VERSION" --extension-dir 2>/dev/null || echo "/usr/lib/php/$PHP_VERSION")
    ls -la "$ext_dir"/*.so 2>/dev/null | head -30
}

# Main execution
main() {
    if [ "$BUILD_MODE" = "release" ]; then
        download_release
        switch_version
    else
        install_requirements
        
        # Build each SAPI
        IFS=' ' read -r -a sapi_arr <<< "$SAPI_LIST"
        for sapi in "${sapi_arr[@]}"; do
            build_sapi "$sapi"
        done
        
        # Merge builds
        merge_builds
        
        # Configure
        configure_ini_files
        configure_extensions
        setup_fpm_config
        setup_jit_config
    fi
    
    # Show results
    show_binary_info
    list_installed_files
    
    echo ""
    echo "=== Build Complete ==="
}

main "$@"
