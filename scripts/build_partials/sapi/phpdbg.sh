# Function to build PHP phpdbg sapi.
build_phpdbg() {
  mkdir -p "${INSTALL_ROOT:?}"
  chmod -R 777 "$INSTALL_ROOT"

  configure_sapi_options phpdbg
  build_php phpdbg
  package_sapi phpdbg
}
