#!/usr/bin/env bash

# Set bash mode.
set -eE -o functrace

# Function to log error line number and message.
log_failure() {
  echo "Failed at $1: $2"
}
trap 'log_failure ${LINENO} "$BASH_COMMAND"' ERR

# Function to get build flags
get_buildflags() {
  type=$1
  debug=${2:-false}
  lto=${3:--lto}
  flags=$(dpkg-buildflags --get "$type")

  # Add or remove flag for debug symbols.
  if [ "$debug" = "false" ]; then
    flags=${flags/-g/}
  else
    flags="$flags -g"
  fi

  # Add or remove lto optimization flags.
  if [ "$lto" = "-lto" ]; then
    flags=$(echo "$flags" | sed -E 's/[^ ]+lto[^ ]+ //g')
  else
    flags="$flags -flto=auto -ffat-lto-objects"
  fi

  echo "$flags"
}

# Function to build PHP.
build_php() {
  echo "::group::$1"
  SAPI=$1

  # Set and export FLAGS
  CFLAGS="$(get_buildflags CFLAGS "$debug" "$lto") $(getconf LFS_CFLAGS)"
  CPPFLAGS="$(get_buildflags CPPFLAGS "$debug" "$lto")"
  CXXFLAGS="$(get_buildflags CXXFLAGS "$debug" "$lto")"
  LDFLAGS="$(get_buildflags LDFLAGS "$debug" "$lto") -Wl,-z,now -Wl,--as-needed"
  EXTRA_CFLAGS="-Wall -fsigned-char -fno-strict-aliasing -Wno-missing-field-initializers"
  export CFLAGS
  export CPPFLAGS
  export CXXFLAGS
  export LDFLAGS
  export EXTRA_CFLAGS

  # Export inputs
  export INSTALL_ROOT
  export PHP_VERSION
  export SAPI

  # Build PHP using php-build.
  if ! php-build -v -i "$default_ini" "$PHP_VERSION" "$prefix"; then
    echo 'Failed to build PHP'
    exit 1
  fi
  echo "::endgroup::"
}

# Function to save the commit hash to the INSTALL_ROOT.
save_commit() {
  # Only store commit for unstable versions
  if [ "${stable:?}" = "false" ]; then
    basename "$(curl -sL https://api.github.com/repos/php/php-src/commits/"${branch:?}" | jq -r .commit.url)" | tee "$INSTALL_ROOT/etc/php/$PHP_VERSION/COMMIT" >/dev/null 2>&1
  fi  
}

# Function to copy PHP from INSTALL_ROOT to the system root.
link_php() {
  cp -af "$INSTALL_ROOT"/* /
}

# Function to merge all SAPI builds into one.
merge_sapi() {
  mkdir -p "$INSTALL_ROOT" \
           "$INSTALL_ROOT"/etc/php/"$PHP_VERSION"/mods-available \
           "$INSTALL_ROOT"/usr/lib/php/"$PHP_VERSION"/sapi

  # Merge SAPI builds.
  IFS=' ' read -r -a sapi_arr <<<"${SAPI_LIST:?}"
  for sapi in "${sapi_arr[@]}"; do
    cp -af "$INSTALL_ROOT-$sapi"/* "$INSTALL_ROOT"
    touch "$INSTALL_ROOT/usr/lib/php/$PHP_VERSION/sapi/$sapi"
  done

  # Fix directory structure for newer OS.
  # Remove var and run from the builds
  rm -rf "${INSTALL_ROOT:?}"/var "$INSTALL_ROOT"/run
  # $INSTALL_ROOT/lib should symlink to /lib if it is a symlink.
  if [ -h /lib ] && [ -d "$INSTALL_ROOT"/lib ]; then
    cp -rf "$INSTALL_ROOT"/lib "$INSTALL_ROOT"/usr
    rm -rf "${INSTALL_ROOT:?}"/lib
  fi

  # Make sure php-cli and php-config is from cli build.
  cp -f "$INSTALL_ROOT-cli/usr/bin/php$PHP_VERSION" "$INSTALL_ROOT"/usr/bin

  # Fix phar.phar binary and docs version suffix.
  cp "$INSTALL_ROOT"/usr/bin/phar"$PHP_VERSION".phar "$INSTALL_ROOT"/usr/bin/phar.phar"$PHP_VERSION"
  ln -sf /usr/bin/phar.phar"$PHP_VERSION" "$INSTALL_ROOT"/usr/bin/phar"$PHP_VERSION"
  cp "$INSTALL_ROOT"/usr/share/man/man1/phar"$PHP_VERSION".phar.1 "$INSTALL_ROOT"/usr/share/man/man1/phar.phar"$PHP_VERSION".1

  # Copy switch_sapi and switch_jit scripts
  cp -fp scripts/switch_sapi "$INSTALL_ROOT"/usr/sbin/switch_sapi
  cp -fp scripts/switch_jit "$INSTALL_ROOT"/usr/sbin/switch_jit

  # Make sure the binaries are executable.
  chmod -R a+x "$INSTALL_ROOT"/usr/bin "$INSTALL_ROOT"/usr/sbin

  # Copy nginx config to the build.
  mkdir -p "$INSTALL_ROOT"/etc/nginx/sites-available
  sed -i "s/PHP_VERSION/$PHP_VERSION/g" config/default_nginx
  cp -fp config/default_nginx "$INSTALL_ROOT"/etc/nginx/sites-available/default

  # Link php from INSTALL_ROOT to system root.
  link_php

  # Install PHP binaries as alternatives.
  switch_version
}

# Function to set default_configure_options of php-build as per the SAPI.
configure_sapi_options() {
  sapi=$1
  sed -i "s/PHP_VERSION/$PHP_VERSION/g" "$definitions"/sapi/"$sapi"
  mv "$definitions"/sapi/"$sapi" "$default_options"
}

# Function to link a ini file to scan directory of each SAPI.
link_ini_file() {
  ini_file_path=$1
  link_file_name=${2:-"$(basename "$ini_file_path")"}

  # Create ini file if it does exist.
  ! [ -e "$ini_file_path" ] && echo '' | tee "$ini_file_path"

  # Link the ini file to each SAPI.
  for sapi in "${sapi_arr[@]}"; do
    ln -sf "$ini_file_path" "$INSTALL_ROOT"/"$conf_dir"/"$sapi"/conf.d/"$link_file_name"
  done
}

# Configure ini files of the PHP build.
configure_ini() {
  # Get all php.ini in a bash array ini_file
  mapfile -t ini_file < <(find "$INSTALL_ROOT/$conf_dir" -name "php.ini" -exec readlink -m {} +)

  # Create a pecl.ini and link it as 99-pecl.ini.
  # This can be used by pecl to enable extensions in each SAPI.
  pecl_file="$mods_dir"/pecl.ini
  link_ini_file "$pecl_file" "99-pecl.ini"
  touch "$INSTALL_ROOT"/"$pecl_file"

  # Set permissions to ini files
  chmod 777 "${ini_file[@]}" \
            "$INSTALL_ROOT"/"$pecl_file"

  # Link php from INSTALL_ROOT to system root.
  link_php
}

switch_version() {
  echo "::group::switch_version"
  # Install and set cgi binaries.
  update-alternatives --install /usr/lib/libphp"${PHP_VERSION/%.*}".so libphp"${PHP_VERSION/%.*}" /usr/lib/libphp"$PHP_VERSION".so "${PHP_VERSION/./}" && ldconfig
  update-alternatives --install /usr/lib/cgi-bin/php php-cgi-bin /usr/lib/cgi-bin/php"$PHP_VERSION" "${PHP_VERSION/./}"
  update-alternatives --set php-cgi-bin /usr/lib/cgi-bin/php"$PHP_VERSION"

  # Install and set fpm binary.
  update-alternatives --install /usr/bin/php-fpm php-fpm /usr/sbin/php-fpm"$PHP_VERSION" "${PHP_VERSION/./}"
  update-alternatives --set php-fpm /usr/sbin/php-fpm"$PHP_VERSION"

  # Install and set other PHP binaries.
  to_wait_arr=()
  for tool in phar phar.phar php-config phpize php php-cgi phpdbg; do
    (
      update-alternatives --install /usr/bin/"$tool" "$tool" /usr/bin/"$tool$PHP_VERSION" "${PHP_VERSION/./}" \
                          --slave /usr/share/man/man1/"$tool".1 "$tool".1 /usr/share/man/man1/"$tool$PHP_VERSION".1
      update-alternatives --set "$tool" /usr/bin/"$tool$PHP_VERSION"
    ) &
    to_wait_arr+=( $! )
  done
  wait "${to_wait_arr[@]}"
  echo "::endgroup::"
}

# Constants
action=$1
prefix=/usr
branch=master
debug=false
lto=-lto
INSTALL_ROOT=/tmp/"$PHP_VERSION"
conf_dir=/etc/php/"$PHP_VERSION"
mods_dir="$conf_dir"/mods-available
php_build_dir='/usr/local/share/php-build'
definitions="$php_build_dir/definitions"
default_options="$php_build_dir/default_configure_options"
default_ini="production"

# Import OS information to the environment.
. /etc/os-release

# Build SAPI
if [ "$action" = "build_sapi" ]; then
  sapi=$2
  # shellcheck source=.
  . scripts/build_partials/sapi/"$sapi".sh
  . scripts/build_partials/package.sh
  . scripts/build_partials/php_build.sh
  . scripts/build_partials/version.sh
  get_version
  setup_phpbuild
  build_"${sapi}"
# Merge SAPI
elif [ "$action" = "merge" ]; then
  . scripts/build_partials/cleanup.sh
  . scripts/build_partials/extensions.sh
  . scripts/build_partials/package.sh
  . scripts/build_partials/pear.sh
  merge_sapi
  configure_ini
  configure_shared_extensions
  setup_pear
  setup_custom_extensions
  cleanup
  package_php
fi
