# Function to enable the extensions in all SAPI.
enable_extension() {
  extension=$1
  mod_file="${mods_dir:?}"/"$extension".ini

  # If the extension is present in extension directory...
  # copy it along with its headers to the INSTALL_ROOT
  # This is done manually as pecl has broken packagingroot parameter.
  ext_source=""
  if [ -e "$INSTALL_ROOT/$ext_dir/$extension.so" ]; then
    ext_source="$INSTALL_ROOT/$ext_dir/$extension.so"
  elif [ -e "$ext_dir/$extension.so" ]; then
    ext_source="$ext_dir/$extension.so"
  fi
  if [ -n "$ext_source" ]; then
    # Copy the extension to the INSTALL_ROOT.
    if [ "$ext_source" != "$INSTALL_ROOT/$ext_dir/$extension.so" ]; then
      cp -f "$ext_source" "$INSTALL_ROOT"/"$ext_dir"
    fi

    # Copy the headers for the extension to the INSTALL_ROOT.
    ext_include_dir="$(php-config"$PHP_VERSION" --include-dir)"/ext/"$extension"
    if [ -d "$ext_include_dir" ]; then
      mkdir -p "$INSTALL_ROOT"/"$ext_include_dir"
      cp -rf "$ext_include_dir" "$INSTALL_ROOT"/"$ext_include_dir"/..
    fi

    # Link the extension mod file for all SAPI.
    priority="$(grep priority "$INSTALL_ROOT"/"$mod_file" | cut -d '=' -f 2)"
    link_ini_file "$mod_file" "$priority-$extension.ini"
  fi
}

# Return space-delimited custom extension names from config/extensions/$PHP_VERSION.
list_custom_extensions() {
  awk '/^(pecl|git)[[:space:]]+/ {name=$2; sub(/-.*/, "", name); print name}' "config/extensions/$PHP_VERSION" \
    | sort -u \
    | tr '\n' ' '
}

# Function to install extensions.
setup_custom_extensions() {
  local static_build="no"
  if [ -n "${STATIC_PREFIX:-}" ] && [ -f "${STATIC_PREFIX}/lib/libssl.a" ]; then
    static_build="yes"
  fi
  # Ensure extension headers from INSTALL_ROOT are visible to later builds.
  local install_include_dir=""
  install_include_dir="$(php-config"$PHP_VERSION" --include-dir 2>/dev/null || true)"
  if [ -n "$install_include_dir" ] && [ -d "$INSTALL_ROOT$install_include_dir" ]; then
    export CPPFLAGS="-I$INSTALL_ROOT$install_include_dir ${CPPFLAGS:-}"
    export CFLAGS="-I$INSTALL_ROOT$install_include_dir ${CFLAGS:-}"
  fi
  ext_dir="$(php-config"$PHP_VERSION" --extension-dir)"

  # Remove stale custom extension artifacts from previous runs so merge does
  # not silently keep old modules when a rebuild fails.
  custom_extensions="$(list_custom_extensions)"
  for custom_extension in $custom_extensions; do
    rm -f "$ext_dir/$custom_extension.so" "$INSTALL_ROOT/$ext_dir/$custom_extension.so"
    find "$INSTALL_ROOT/etc/php/$PHP_VERSION" -name "*-$custom_extension.ini" -delete 2>/dev/null || true
  done

  # Parse the config/extensions/$PHP_VERSION file.
  while read -r extension_config; do
    # Get extension type, name and prefix
    type=$(echo "$extension_config" | cut -d ' ' -f 1)
    extension=$(echo "$extension_config" | cut -d ' ' -f 2)
    echo "::group::$extension"

    # If there is a compatible release on PECL i.e. type is pecl.
    if [ "$type" = "pecl" ]; then
      # Fetch the extension using PECL
      tag=
      if [ "${extension##*-}" != "${extension%-*}" ]; then
        tag="${extension##*-}"
      fi
      extension="${extension%-*}"
      repo=pecl
    # Else install from git repository as per the config.
    elif [ "$type" = "git" ]; then
      # Get repository, tag and compile arguments from the config
      repo=$(echo "$extension_config" | cut -d ' ' -f 3)
      tag=$(echo "$extension_config" | cut -d ' ' -f 4)
      IFS=' ' read -r -a args <<<"$(echo "$extension_config" | cut -d ' ' -f 5-)"

      # Static build: prefer static IMAP libs and avoid kerberos if static libs are missing
      if [ "$static_build" = "yes" ] && [ "$extension" = "imap" ]; then
        new_args=()
        for arg in "${args[@]}"; do
          case "$arg" in
            --with-imap=shared,*)
              new_args+=( "--with-imap=shared,${STATIC_PREFIX}" )
              ;;
            --with-imap-ssl=*)
              new_args+=( "--with-imap-ssl=${STATIC_PREFIX}" )
              ;;
            --with-kerberos)
              if [ -f "${STATIC_PREFIX}/lib/libkrb5.a" ]; then
                new_args+=( "$arg" )
              fi
              ;;
            *)
              new_args+=( "$arg" )
              ;;
          esac
        done
        args=("${new_args[@]}")
      fi
      if [ "$static_build" = "yes" ] && [ "$extension" = "memcached" ]; then
        has_sasl_toggle="no"
        for arg in "${args[@]}"; do
          if [ "$arg" = "--disable-memcached-sasl" ] || [ "$arg" = "--enable-memcached-sasl" ]; then
            has_sasl_toggle="yes"
            break
          fi
        done
        # Keep SASL enabled when libsasl2 static archive is available.
        # Fall back to disabling SASL only if we have no static SASL runtime.
        if [ "$has_sasl_toggle" = "no" ] && [ ! -f "${STATIC_PREFIX}/lib/libsasl2.a" ]; then
          args+=( "--disable-memcached-sasl" )
        fi
      fi
    fi

    if [ "$static_build" = "yes" ] && [ "$extension" = "yaml" ]; then
      has_yaml_dir="no"
      for arg in "${args[@]}"; do
        case "$arg" in
          --with-yaml=*)
            has_yaml_dir="yes"
            ;;
        esac
      done
      if [ "$has_yaml_dir" = "no" ]; then
        args+=( "--with-yaml=${STATIC_PREFIX}" )
      fi
    fi

    # Add debug symbols to the extension build.
    args+=("--enable-debug")

    # Compile and install the extension.
    bash scripts/retry.sh 5 5 bash "$(pwd)"/scripts/install-extension.sh "$extension" "$repo" "$tag" "$INSTALL_ROOT" "${args[@]}"

    # Enable the extension for all SAPI.
    enable_extension "${extension%-*}"
    echo "::endgroup::"
  done < config/extensions/"$PHP_VERSION"

  # Ensure all built extensions are linked for each SAPI.
  # Static builds may only generate PECL .so files after this loop.
  ext_dir="$(php-config"$PHP_VERSION" --extension-dir)"
  for extension_path in "$ext_dir"/*.so; do
    [ -e "$extension_path" ] || continue
    extension="$(basename "$extension_path" | cut -d '.' -f 1)"
    enable_extension "$extension"
  done

  # Keep PCOV enabled for CLI only (matches dynamic release behavior).
  find "$INSTALL_ROOT"/etc/php/"$PHP_VERSION" -name '*-pcov.ini' ! -path "*/cli/conf.d/*" -delete
  if [ -f "$INSTALL_ROOT/$mods_dir/pcov.ini" ]; then
    mkdir -p "$INSTALL_ROOT/$conf_dir/cli/conf.d"
    # Keep symlink target relocatable after copying INSTALL_ROOT to /
    ln -sf "/$mods_dir/pcov.ini" "$INSTALL_ROOT/$conf_dir/cli/conf.d/20-pcov.ini"
  fi

  # Link php from INSTALL_ROOT to system root.
  link_php
}

# Function to configure extensions
configure_shared_extensions() {
  # Copy all modules to mods-available
  cp -f config/modules/*.ini "$INSTALL_ROOT"/"$mods_dir"/

  # Get the extension directory
  ext_dir="$(php-config"$PHP_VERSION" --extension-dir)"
  custom_extensions=" $(list_custom_extensions) "

  # Enable other shared extensions for all SAPI.
  echo "::group::configure_extensions"
  to_wait=()
  for extension_path in "$ext_dir"/*.so; do
    extension="$(basename "$extension_path" | cut -d '.' -f 1)"
    # Custom extensions are built later by setup_custom_extensions.
    [[ "$custom_extensions" == *" $extension "* ]] && continue
    echo "Adding module file for $extension"
    enable_extension "$extension" &
    to_wait+=( $! )
  done
  wait "${to_wait[@]}"
  echo "::endgroup::"

  # Link php from INSTALL_ROOT to system root.
  link_php
}
