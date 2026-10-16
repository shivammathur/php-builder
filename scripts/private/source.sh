# Sourced into the generated php-build definition only for private staging.
install_package_from_private() {
  local source_path="$PHP_BUILD_TMPDIR/source/$DEFINITION"
  printf '%s  %s\n' "${PHP_PRIVATE_SOURCE_SHA256:?}" "${PHP_PRIVATE_SOURCE_ARCHIVE:?}" | sha256sum --check -
  mkdir -p "$source_path"
  tar -xf "$PHP_PRIVATE_SOURCE_ARCHIVE" --strip-components=1 -C "$source_path"
  (
    cd "$source_path"
    build_package
  )
}
