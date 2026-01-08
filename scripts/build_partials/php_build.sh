# Function to patch configure options and patch series files for php-build.
patch_config_file() {
  command=$1
  file=$2
  sed -Ei -e "s/^--/$command \"--/" \
          -e "s/^([0-9]+)/$command \"\1/" \
          -e "s/^($command.*)/\1\"/" "$file"
}

# Function to configure php-build.
configure_phpbuild() {
  # Set install command based on PHP version.
  if [[ "${branch:?}" =~ ^(master|PHP-"$PHP_VERSION"(.0)?)$ ]]; then
    install_command="install_package_from_github $branch"
  else
    install_command="install_package \"https://github.com/php/web-php-distributions/raw/master/${new_version:?}.tar.gz\""
  fi

  # Copy all the custom definitions to php-build definitions directory.
  cp -rf config/definitions/* "${definitions:?}"

  # Patch the definition for the PHP version.
  patch_config_file configure_option "${definitions:?}"/"$PHP_VERSION"

  # Path the definition for thread-safe.
  # Zend Signals are broken with ZTS: https://externals.io/message/118859
  zts=''
  if [ "${BUILD:?}" = "zts" ]; then
    patch_config_file configure_option "${definitions:?}"/zts/"$PHP_VERSION"
    zts="$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' "${definitions:?}"/zts/"$PHP_VERSION")"
  fi

  # Path the definition for ASAN.
  asan=''
  if [ "${ASAN:-}" = "asan" ]; then
    asan='configure_option "--enable-address-sanitizer"'
  fi

  # Copy all local patches to the php-build patches directory.
  patches_dir=config/patches/"$PHP_VERSION"
  if [ -d "$patches_dir" ]; then
    find "$patches_dir" -name '*' -exec cp -rf "{}" "${php_build_dir:?}"/patches \;
  fi
  cp "$patches_dir"/series $patches_dir/~series

  # Patch series file to php-build syntax.
  patch_config_file patch_file "$patches_dir"/~series

  # Patch PHP version, host, build, patches and install command in the definition template.
  sed -i -e "s|BUILD_MACHINE_SYSTEM_TYPE|$(dpkg-architecture -q DEB_BUILD_GNU_TYPE)|" \
         -e "s|HOST_MACHINE_SYSTEM_TYPE|$(dpkg-architecture -q DEB_HOST_GNU_TYPE)|" \
         -e "s|ZTS|$zts|" \
         -e "s|ASAN|$asan|" \
         -e "s|INSTALL|$install_command|" \
         -e "s|PHP_VERSION|$PHP_VERSION|" \
         -e "s|PHP_VERSION|$PHP_VERSION|" \
         -e "/PATCHES/{r./$patches_dir/~series" -e "d}" "$definitions"/"$PHP_VERSION"

  # Print the definition file.
  cat "$definitions"/"$PHP_VERSION"

  # Remove ~series file.
  rm "$patches_dir"/~series
}

# Function to install php-build.
setup_phpbuild() {
  echo "::group::php-build"
  git clone -b debian https://github.com/shivammathur/php-build ~/php-build
  ~/php-build/install.sh
  configure_phpbuild
  echo "::endgroup::"
}
