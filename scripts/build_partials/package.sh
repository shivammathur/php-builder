# Function package PHP SAPI build.
package_sapi() {
  sapi=$1
  (
    echo "::group::package_$sapi"
    zstd -V
    cd "${INSTALL_ROOT:?}"/.. || exit
    mv "$INSTALL_ROOT" "$INSTALL_ROOT-$sapi"
    tar cf - "$PHP_VERSION-$sapi" | zstd -22 -T0 --ultra > "php_$PHP_VERSION-$sapi+$ID$VERSION_ID.tar.zst"
    echo "::endgroup::"
  )
}

# Function to package PHP
package_php() {
  (
    echo "::group::package_php"
    cd "$INSTALL_ROOT" || exit
    echo "Creating Package using XZ"
    XZ_OPT=-e9 tar cfJ "php_$PHP_VERSION+$ID$VERSION_ID.tar.xz" ./*
    mv "php_$PHP_VERSION+$ID$VERSION_ID.tar.xz" /tmp

    echo "Creating Package using ZSTD"
    zstd -V
    tar cf - ./* | zstd -22 -T0 --ultra > "php_$PHP_VERSION+$ID$VERSION_ID.tar.zst"
    mv "php_$PHP_VERSION+$ID$VERSION_ID.tar.zst" /tmp
    echo "::endgroup::"
  )
}