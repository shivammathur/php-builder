# Function to copy the extensions and headers to the build.
install_extension_artifacts() {
  extension=$1

  # If the extension is present in extension directory...
  # copy it along with its headers to the INSTALL_ROOT
  # This is done manually as pecl has broken packagingroot parameter.
  if [ -e "$ext_dir/$extension.so" ]; then
    # Copy the extension to the INSTALL_ROOT.
    mkdir -p "$INSTALL_ROOT"/"$ext_dir"
    cp -f "$ext_dir"/"$extension".so "$INSTALL_ROOT"/"$ext_dir"

    # Copy the headers for the extension to the INSTALL_ROOT.
    ext_include_dir="$(php-config"$PHP_VERSION" --include-dir)"/ext/"$extension"
    if [ -d "$ext_include_dir" ]; then
      mkdir -p "$INSTALL_ROOT"/"$ext_include_dir"
      cp -rf "$ext_include_dir" "$INSTALL_ROOT"/"$ext_include_dir"/..
    fi
  fi
}

# Function to package custom extensions without enabling them.
package_extension() {
  extension=$1
  install_extension_artifacts "$extension"
}

# Function to enable the extensions in all SAPI.
enable_extension() {
  extension=$1
  mod_file="${mods_dir:?}"/"$extension".ini

  install_extension_artifacts "$extension"
  if [ -e "$ext_dir/$extension.so" ]; then
    # Link the extension mod file for all SAPI.
    priority="$(grep priority "$INSTALL_ROOT"/"$mod_file" | cut -d '=' -f 2)"
    link_ini_file "$mod_file" "$priority-$extension.ini"
  fi
}

# Function to check if a custom extension should only be packaged.
is_optional_extension() {
  grep -qx "$1" config/optional-extensions
}

# Function to install a custom extension from a config entry.
setup_custom_extension() {
  local extension_config type extension repo tag
  local args=()
  extension_config=$1
  type=$(echo "$extension_config" | cut -d ' ' -f 1)
  extension=$(echo "$extension_config" | cut -d ' ' -f 2)
  tag=
  echo "::group::$extension"

  # If there is a compatible release on PECL i.e. type is pecl.
  if [ "$type" = "pecl" ]; then
    # Fetch the extension using PECL.
    if [ "${extension##*-}" != "${extension%-*}" ]; then
      tag="${extension##*-}"
    fi
    extension="${extension%-*}"
    repo=pecl
    IFS=' ' read -r -a args <<<"$(echo "$extension_config" | cut -d ' ' -f 3-)"
  # Else install from git repository as per the config.
  elif [ "$type" = "git" ]; then
    # Get repository, tag and compile arguments from the config.
    repo=$(echo "$extension_config" | cut -d ' ' -f 3)
    tag=$(echo "$extension_config" | cut -d ' ' -f 4)
    IFS=' ' read -r -a args <<<"$(echo "$extension_config" | cut -d ' ' -f 5-)"
  fi

  # Add debug symbols to the extension build.
  args+=("--enable-debug")

  # Compile and install the extension.
  bash scripts/retry.sh 5 5 bash "$(pwd)"/scripts/install-extension.sh "$extension" "$repo" "$tag" "$INSTALL_ROOT" "${args[@]}"

  # Package optional extensions without enabling them by default.
  if [ "${EXTENSIONS_ONLY:-false}" = "true" ]; then
    package_extension "${extension%-*}"
  elif is_optional_extension "${extension%-*}"; then
    package_extension "${extension%-*}"
  else
    enable_extension "${extension%-*}"
  fi
  echo "::endgroup::"
}

# Function to install extensions.
setup_custom_extensions() {
  # Parse the config/extensions/$PHP_VERSION file.
  while read -r extension_config; do
    setup_custom_extension "$extension_config"
  done < config/extensions/"$PHP_VERSION"

  # Disable PCOV by default as Xdebug is enabled.
  [ -d "$INSTALL_ROOT"/etc/php/"$PHP_VERSION" ] && find "$INSTALL_ROOT"/etc/php/"$PHP_VERSION" -name '*-pcov.ini' -delete

  # Link php from INSTALL_ROOT to system root.
  [ "${EXTENSIONS_ONLY:-false}" = "true" ] || link_php
}

# Function to enable already built custom extensions.
enable_custom_extensions() {
  while read -r extension_config; do
    extension=$(echo "$extension_config" | cut -d ' ' -f 2)
    extension="${extension%-*}"

    if is_optional_extension "$extension"; then
      package_extension "$extension"
    else
      enable_extension "$extension"
    fi
  done < config/extensions/"$PHP_VERSION"

  find "$INSTALL_ROOT"/etc/php/"$PHP_VERSION" -name '*-pcov.ini' -delete
  link_php
}

# Function to remove module configs for extensions not present in the final build.
prune_missing_extension_configs() {
  local ini_file module target

  for ini_file in "$INSTALL_ROOT"/"$mods_dir"/*.ini; do
    [ -e "$ini_file" ] || continue
    module="$(sed -n -E 's/^[[:space:]]*(zend_extension|extension)[[:space:]]*=[[:space:]]*"?([^";[:space:]]+).*/\2/p' "$ini_file" | head -n 1)"
    [ -n "$module" ] || continue

    case "$module" in
      /*) target="$INSTALL_ROOT$module" ;;
      *) target="$INSTALL_ROOT$ext_dir/${module##*/}" ;;
    esac

    if [ ! -e "$target" ]; then
      echo "Removing module file without extension: $(basename "$ini_file")"
      rm -f "$ini_file"
    fi
  done
}

# Function to configure extensions
configure_shared_extensions() {
  # Copy all modules to mods-available
  cp -f config/modules/*.ini "$INSTALL_ROOT"/"$mods_dir"/

  # Get the extension directory
  ext_dir="$(php-config"$PHP_VERSION" --extension-dir)"

  # Enable other shared extensions for all SAPI.
  echo "::group::configure_extensions"
  to_wait=()
  for extension_path in "$ext_dir"/*.so; do
    extension="$(basename "$extension_path" | cut -d '.' -f 1)"
    echo "Adding module file for $extension"
    enable_extension "$extension" &
    to_wait+=( $! )
  done
  wait "${to_wait[@]}"
  echo "::endgroup::"

  # Link php from INSTALL_ROOT to system root.
  link_php
}
