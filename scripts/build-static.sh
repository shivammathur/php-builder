#!/usr/bin/env bash
# Static PHP build script
# Uses static libraries from /opt/static to create statically linked PHP

set -eE -o functrace

# Function to print usage help
print_help() {
  cat << HELP > /dev/stdout

Usage: ${0} <action> [sapi]

Available actions:
 - build_sapi
 - merge

Available sapis:
 - cgi
 - cli
 - embed
 - fpm
 - phpdbg

HELP
}

# Function to log error line number and message.
log_failure() {
  echo "Failed at $1: $2"
}
trap 'log_failure ${LINENO} "$BASH_COMMAND"' ERR

# Static prefix
STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"

if [[ "${#}" -eq 0 ]]; then
  print_help
  exit 0;
fi

# sanity checks
if [ -z "${BUILD}" ]; then
  echo "BUILD is not defined"
  exit 1;
fi

if [ -z "${PHP_VERSION}" ]; then
  echo "PHP_VERSION is not defined"
  exit 1;
fi

# Constants
action=$1
prefix=/usr
branch=master
FAKE_ROOT=/tmp
INSTALL_ROOT="$FAKE_ROOT"/debian/php"$PHP_VERSION"
conf_dir=/etc/php/"$PHP_VERSION"
mods_dir="$conf_dir"/mods-available
php_build_dir='/usr/share/php-build'
definitions="$php_build_dir/definitions"
default_options="$php_build_dir/default_configure_options"
default_ini="production"

# Export for static php_build.sh partials
export INSTALL_ROOT PHP_VERSION SAPI_LIST definitions php_build_dir default_options default_ini

# Set thread-safe options.
if [ "${BUILD:?}" = "zts" ]; then
  export PHP_PKG_SUFFIX=-zts
fi

# Import OS information to the environment.
. /etc/os-release

# Source the dynamic partials first (needed for merge and other shared functions)
. scripts/build_partials/package.sh
. scripts/build_partials/version.sh

# Source the static-specific partials
. scripts/build_partials/static/php_build.sh

# Function to patch configure options and patch series files for php-build.
patch_config_file() {
  command=$1
  file=$2
  sed -Ei -e "s/^--/$command \"--/" \
          -e "s/^([0-9]+)/$command \"\1/" \
          -e "s/^($command.*)/\1\"/" "$file"
}

# Function to link php from INSTALL_ROOT to system root.
link_php() {
  cp -af "$INSTALL_ROOT"/* /
}

# Function to save the commit hash to the INSTALL_ROOT.
save_commit() {
  # Only store commit for unstable versions
  if [ "${stable:?}" = "false" ]; then
    commit="$(basename "$(curl -sL https://api.github.com/repos/php/php-src/commits/"${branch:?}" | jq -r .commit.url)")"
    [ "$commit" = 'null' ] && exit 1;
    echo "$commit" | tee "$INSTALL_ROOT/etc/php/$PHP_VERSION/COMMIT" >/dev/null 2>&1
  fi
}

# Function to set default_configure_options of php-build as per the SAPI.
configure_sapi_options() {
  sapi=$1
  sed -i "s/PHP_VERSION/$PHP_VERSION/g" "$definitions"/sapi/"$sapi"
  cp "$definitions"/sapi/"$sapi" "$default_options"
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
  # Install and set cgi binaries (if they exist).
  if [ -f "/usr/lib/libphp$PHP_VERSION.so" ]; then
    update-alternatives --install /usr/lib/libphp"${PHP_VERSION/%.*}".so libphp"${PHP_VERSION/%.*}" /usr/lib/libphp"$PHP_VERSION".so "${PHP_VERSION/./}" && ldconfig
  fi
  if [ -f "/usr/lib/cgi-bin/php$PHP_VERSION" ]; then
    update-alternatives --install /usr/lib/cgi-bin/php php-cgi-bin /usr/lib/cgi-bin/php"$PHP_VERSION" "${PHP_VERSION/./}"
    update-alternatives --set php-cgi-bin /usr/lib/cgi-bin/php"$PHP_VERSION"
  fi

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

cleanup_environment() {
  rm -rf ~/php-build "${INSTALL_ROOT:?}" "${php_build_dir:?}"
  # Ensure php-build source tree is clean between SAPIs
  rm -rf /tmp/php-build 2>/dev/null || true
  mkdir -p ~/php-build "${INSTALL_ROOT:?}" "${php_build_dir:?}"
}

# Function to merge all SAPI builds into one (static version).
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
  if [[ "$PHP_VERSION" =~ 5.6|7.[0-3] ]]; then
    cp "$INSTALL_ROOT"/usr/bin/phar.phar "$INSTALL_ROOT"/usr/bin/phar.phar"$PHP_VERSION"
    cp "$INSTALL_ROOT"/usr/share/man/man1/phar.phar.1 "$INSTALL_ROOT"/usr/share/man/man1/phar.phar"$PHP_VERSION".1
  else
    cp "$INSTALL_ROOT"/usr/bin/phar"$PHP_VERSION".phar "$INSTALL_ROOT"/usr/bin/phar.phar"$PHP_VERSION"
    cp "$INSTALL_ROOT"/usr/share/man/man1/phar"$PHP_VERSION".phar.1 "$INSTALL_ROOT"/usr/share/man/man1/phar.phar"$PHP_VERSION".1
  fi
  ln -sf /usr/bin/phar.phar"$PHP_VERSION" "$INSTALL_ROOT"/usr/bin/phar"$PHP_VERSION"

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

  # Verify static binaries
  echo "::group::verify_static"
  for bin in php"$PHP_VERSION" php-cgi"$PHP_VERSION" phpdbg"$PHP_VERSION"; do
    if [ -f /usr/bin/"$bin" ]; then
      echo "=== $bin ==="
      ldd /usr/bin/"$bin" 2>&1 || echo "Static binary"
      file /usr/bin/"$bin"
    fi
  done
  if [ -f /usr/sbin/php-fpm"$PHP_VERSION" ]; then
    echo "=== php-fpm$PHP_VERSION ==="
    ldd /usr/sbin/php-fpm"$PHP_VERSION" 2>&1 || echo "Static binary"
    file /usr/sbin/php-fpm"$PHP_VERSION"
  fi
  echo "::endgroup::"
}

# Build SAPI
if [ "$action" = "build_sapi" ]; then
  sapi=$2
  # shellcheck source=.
  . scripts/build_partials/sapi/"$sapi".sh
  cleanup_environment
  get_version
  setup_phpbuild_static
  build_"$sapi"
  if [ ! -d "$INSTALL_ROOT-$sapi" ] && [ -d "$INSTALL_ROOT" ]; then
    package_sapi "$sapi"
  fi
  
# Merge SAPI
elif [ "$action" = "merge" ]; then
  . scripts/build_partials/cleanup.sh
  . scripts/build_partials/extensions.sh
  . scripts/build_partials/strip.sh
  . scripts/build_partials/pear.sh
  merge_sapi
  configure_ini
  configure_shared_extensions
  setup_pear
  setup_custom_extensions
  cleanup
  package_php
fi
