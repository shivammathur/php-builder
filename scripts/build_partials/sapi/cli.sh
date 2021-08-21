# Function to configure PHP cli build.
configure_cli() {
  # Remove libtool files.
  find "${INSTALL_ROOT:?}" -name '*.la' -delete
}

# Function to build PHP cli sapi.
build_cli() {
  mkdir -p "${INSTALL_ROOT:?}"
  chmod -R 777 "$INSTALL_ROOT"

  configure_sapi_options cli
  build_php cli
  configure_cli
  package_sapi cli
}
