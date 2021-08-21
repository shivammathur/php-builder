# Function to configure phpdbg build.
configure_phpdbg() {
  # Remove all binaries except phpdbg.
  find "${INSTALL_ROOT:?}/usr/bin" -name "*$PHP_VERSION*" ! -name "phpdbg$PHP_VERSION" -delete

  # Remove libtool files and extensions.
  find "${INSTALL_ROOT:?}" -name '*.la' -name '*.so' -delete
}

# Function to build PHP phpdbg sapi.
build_phpdbg() {
  mkdir -p "${INSTALL_ROOT:?}"
  chmod -R 777 "$INSTALL_ROOT"

  configure_sapi_options phpdbg
  build_php phpdbg
  configure_phpdbg
  package_sapi phpdbg
}
