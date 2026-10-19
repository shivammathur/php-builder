# Sourced into the generated php-build definition only for private staging.
install_package_from_private() {
  local source_path="$PHP_BUILD_TMPDIR/source/$DEFINITION"
  printf '%s  %s\n' "${PHP_PRIVATE_SOURCE_SHA256:?}" "${PHP_PRIVATE_SOURCE_ARCHIVE:?}" | sha256sum --check -
  if [ -n "${PHP_PRIVATE_PATCH_FILE:-}" ]; then
    printf '%s  %s\n' "${PHP_PRIVATE_PATCH_SHA256:?}" "$PHP_PRIVATE_PATCH_FILE" | sha256sum --check -
    # Append after the normal distribution series. The patch bytes are
    # downloaded from private storage and never stored in this checkout.
    patch_file "$PHP_PRIVATE_PATCH_FILE"
  elif [ -n "${PHP_PRIVATE_PATCH_SHA256:-}" ]; then
    return 1
  fi
  mkdir -p "$source_path"
  tar -xf "$PHP_PRIVATE_SOURCE_ARCHIVE" --strip-components=1 -C "$source_path"
  (
    cd "$source_path"
    build_package
  )
}
