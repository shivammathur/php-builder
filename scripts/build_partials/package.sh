# Function package PHP SAPI build.
package_sapi() {
  sapi=$1
  (
    echo "::group::package_$sapi"
    zstd -V
    cd "${INSTALL_ROOT:?}"/.. || exit
    rm -rf "$INSTALL_ROOT-$sapi"
    mv "$INSTALL_ROOT" "$INSTALL_ROOT-$sapi"
    arch="$(arch)"
    [[ "$arch" = "aarch64" || "$arch" = "arm64" ]] && ARCH_SUFFIX='_arm64' || ARCH_SUFFIX=''
    tar cf - "php$PHP_VERSION-$sapi" | zstd -22 -T0 --ultra > "php_$PHP_VERSION$PHP_PKG_SUFFIX-$sapi+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst"
    echo "::endgroup::"
  )
}

# Function to package PHP
package_php() {
  (
    arch="$(arch)"
    [[ "$arch" = "aarch64" || "$arch" = "arm64" ]] && ARCH_SUFFIX='_arm64' || ARCH_SUFFIX=''
    strip_debug
    if declare -F post_strip_runtime_adjustments >/dev/null 2>&1; then
      post_strip_runtime_adjustments
    fi
    echo "::group::package_php"
    echo "Creating Package using XZ"
    XZ_OPT=-e9 tar -C "$INSTALL_ROOT" -cJf "/tmp/php_$PHP_VERSION$PHP_PKG_SUFFIX+$ID$VERSION_ID$ARCH_SUFFIX.tar.xz" .

    echo "Creating Package using ZSTD"
    zstd -V
    tar -C "$INSTALL_ROOT" -cf - . | zstd -22 -T0 --ultra > "/tmp/php_$PHP_VERSION$PHP_PKG_SUFFIX+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst"

    copy_debug_symbols

    echo "Creating Debug Package using XZ"
    XZ_OPT=-e9 tar -C "$INSTALL_ROOT" -cJf "/tmp/php_$PHP_VERSION$PHP_PKG_SUFFIX-dbgsym+$ID$VERSION_ID$ARCH_SUFFIX.tar.xz" .

    echo "Creating Debug Package using ZSTD"
    zstd -V
    tar -C "$INSTALL_ROOT" -cf - . | zstd -22 -T0 --ultra > "/tmp/php_$PHP_VERSION$PHP_PKG_SUFFIX-dbgsym+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst"

    # Keep debug symbols out of the runtime install tree used by comparison tests.
    rm -rf "$INSTALL_ROOT"/usr/lib/debug

    echo "::endgroup::"
  )
}
