# Function package PHP SAPI build.
package_sapi() {
  sapi=$1
  (
    echo "::group::package_$sapi"
    zstd -V
    cd "${INSTALL_ROOT:?}"/.. || exit
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
    stage_library_overlays
    echo "::group::package_php"
    cd "$INSTALL_ROOT" || exit
    echo "Creating Package using XZ"
    XZ_OPT=-e9 tar cfJ "php_$PHP_VERSION$PHP_PKG_SUFFIX+$ID$VERSION_ID$ARCH_SUFFIX.tar.xz" ./*
    mv "php_$PHP_VERSION$PHP_PKG_SUFFIX+$ID$VERSION_ID$ARCH_SUFFIX.tar.xz" /tmp

    echo "Creating Package using ZSTD"
    zstd -V
    tar cf - ./* | zstd -22 -T0 --ultra > "php_$PHP_VERSION$PHP_PKG_SUFFIX+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst"
    mv "php_$PHP_VERSION$PHP_PKG_SUFFIX+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst" /tmp

    copy_debug_symbols

    echo "Creating Debug Package using XZ"
    XZ_OPT=-e9 tar cfJ "php_$PHP_VERSION$PHP_PKG_SUFFIX-dbgsym+$ID$VERSION_ID$ARCH_SUFFIX.tar.xz" ./*
    mv "php_$PHP_VERSION$PHP_PKG_SUFFIX-dbgsym+$ID$VERSION_ID$ARCH_SUFFIX.tar.xz" /tmp

    echo "Creating Debug Package using ZSTD"
    zstd -V
    tar cf - ./* | zstd -22 -T0 --ultra > "php_$PHP_VERSION$PHP_PKG_SUFFIX-dbgsym+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst"
    mv "php_$PHP_VERSION$PHP_PKG_SUFFIX-dbgsym+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst" /tmp

    echo "::endgroup::"
  )
}

# Function to package an intermediate build root.
package_root() {
  suffix=$1
  root_name=${2:-php$PHP_VERSION$suffix}
  (
    arch="$(arch)"
    [[ "$arch" = "aarch64" || "$arch" = "arm64" ]] && ARCH_SUFFIX='_arm64' || ARCH_SUFFIX=''
    echo "::group::package_$suffix"
    cd "$INSTALL_ROOT"/.. || exit
    zstd -V
    tar cf - "$root_name" | zstd -22 -T0 --ultra > "php_$PHP_VERSION$PHP_PKG_SUFFIX$suffix+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst"
    mv "php_$PHP_VERSION$PHP_PKG_SUFFIX$suffix+$ID$VERSION_ID$ARCH_SUFFIX.tar.zst" /tmp
    echo "::endgroup::"
  )
}
