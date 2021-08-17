# Function to build PHP apache2 sapi.
build_cli() {
  mkdir -p "${INSTALL_ROOT:?}"
  chmod -R 777 "$INSTALL_ROOT"

  configure_sapi_options cli
  build_php cli
  package_sapi cli
}
