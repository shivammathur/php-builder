# Function to configure PHP embed build.
configure_embed() {
  mv "${INSTALL_ROOT:?}"/usr/lib/php/libphp*.so "$INSTALL_ROOT"/usr/lib/libphp"$PHP_VERSION".so

  # Remove any php binaries in the embed build.
  rm -rf "${INSTALL_ROOT:?}"/usr/bin

  # Remove libtool files and extensions.
  find "${INSTALL_ROOT:?}" -name '*.la' -name '*.so' -delete
}

# Function to build PHP embed sapi.
build_embed() {
  mkdir -p "${INSTALL_ROOT:?}"
  chmod -R 777 "$INSTALL_ROOT"

  configure_sapi_options embed
  build_php embed
  configure_embed
  package_sapi embed
}
