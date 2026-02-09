#!/usr/bin/env bash

# Set bash mode.
set -eE -o functrace

# Function to print usage help
print_help() {
  cat << HELP > /dev/stdout

Usage: ${0} <action> [sapi]

Available actions:
 - build_sapi
 - merge

Available sapis:
 - apache2
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

# Function to get build flags
get_buildflags() {
  type=$1
  lto=${2:--lto}
  flags=$(dpkg-buildflags --get "$type")

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
  export PHP_BUILD_EXTRA_MAKE_ARGUMENTS="${PHP_BUILD_EXTRA_MAKE_ARGUMENTS:--j1}"

  # Check for static build environment
  STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
  USE_STATIC_LIBS="no"
  if [ -f "$STATIC_PREFIX/setup-env.sh" ] && [ -f "$STATIC_PREFIX/lib/libssl.a" ]; then
    USE_STATIC_LIBS="yes"
    echo "Static build environment detected at $STATIC_PREFIX"
    # Source the static environment setup
    source "$STATIC_PREFIX/setup-env.sh"
  fi

  # Set and export FLAGS
  CFLAGS="$(get_buildflags CFLAGS "$lto") $(getconf LFS_CFLAGS)"  
  CFLAGS=$(echo "$CFLAGS" | sed -E 's/-Werror=implicit-function-declaration//g')
  CFLAGS="$CFLAGS -DOPENSSL_SUPPRESS_DEPRECATED"

  CPPFLAGS="$(get_buildflags CPPFLAGS "$lto")"
  CXXFLAGS="$(get_buildflags CXXFLAGS "$lto")"
  LDFLAGS="$(get_buildflags LDFLAGS "$lto") -Wl,-z,now -Wl,--as-needed"

  # Add static library paths if using static build
  if [ "$USE_STATIC_LIBS" = "yes" ]; then
    CFLAGS="-I$STATIC_PREFIX/include $CFLAGS"
    CPPFLAGS="-I$STATIC_PREFIX/include $CPPFLAGS"
    # Put static lib path first
    LDFLAGS="-L$STATIC_PREFIX/lib -L$STATIC_PREFIX/lib64 $LDFLAGS"
    
    # Build LIBS with explicit full paths to static archives
    # For static linking, order matters: libraries that USE symbols first,
    # libraries that PROVIDE symbols after. Using --start-group/--end-group
    # to handle circular dependencies between static archives.
    LIBS=""
    
    # Allow multiple definitions to handle libargon2/libsodium symbol conflicts
    # (libsodium has internal argon2, but PHP needs the public argon2 API)
    LIBS="$LIBS -Wl,--allow-multiple-definition"
    
    # Start a link group to handle circular dependencies in static archives
    LIBS="$LIBS -Wl,--start-group"
    
    # High-level libraries that depend on others (curl, ldap, pq depend on ssl/crypto)
    [ -f "$STATIC_PREFIX/lib/libcurl.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libcurl.a"
    [ -f "$STATIC_PREFIX/lib/libldap.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libldap.a"
    [ -f "$STATIC_PREFIX/lib/liblber.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/liblber.a"
    # PostgreSQL requires libpq plus libpgcommon and libpgport for static linking
    [ -f "$STATIC_PREFIX/lib/libpq.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libpq.a"
    [ -f "$STATIC_PREFIX/lib/libpgcommon.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libpgcommon.a"
    [ -f "$STATIC_PREFIX/lib/libpgport.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libpgport.a"
    
    # Mid-level libraries (xslt->xml2->z/lzma, zip->z/bz2/lzma/ssl)
    [ -f "$STATIC_PREFIX/lib/libxslt.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libxslt.a"
    [ -f "$STATIC_PREFIX/lib/libexslt.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libexslt.a"
    [ -f "$STATIC_PREFIX/lib/libzip.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libzip.a"
    [ -f "$STATIC_PREFIX/lib/libxml2.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libxml2.a"
    
    # SSL/Crypto (many things depend on these)
    [ -f "$STATIC_PREFIX/lib/libssl.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libssl.a"
    [ -f "$STATIC_PREFIX/lib/libcrypto.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libcrypto.a"
    
    # Compression and encoding libraries
    [ -f "$STATIC_PREFIX/lib/liblzma.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/liblzma.a"
    [ -f "$STATIC_PREFIX/lib/libz.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libz.a"
    [ -f "$STATIC_PREFIX/lib/libbz2.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libbz2.a"
    
    # Standalone libraries with minimal dependencies
    # argon2 before sodium - PHP needs argon2's public API (argon2_encodedlen, argon2_error_message)
    # but libsodium also has internal argon2 symbols, so --allow-multiple-definition is needed
    [ -f "$STATIC_PREFIX/lib/libargon2.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libargon2.a"
    [ -f "$STATIC_PREFIX/lib/libsodium.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libsodium.a"
    [ -f "$STATIC_PREFIX/lib/libpcre2-8.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libpcre2-8.a"
    [ -f "$STATIC_PREFIX/lib/libonig.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libonig.a"
    [ -f "$STATIC_PREFIX/lib/libsqlite3.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libsqlite3.a"
    [ -f "$STATIC_PREFIX/lib/libffi.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libffi.a"
    [ -f "$STATIC_PREFIX/lib/libtidy.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libtidy.a"
    [ -f "$STATIC_PREFIX/lib/libedit.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libedit.a"
    # ncurses/terminfo - libedit depends on these
    if [ -f "$STATIC_PREFIX/lib/libncursesw.a" ]; then
        LIBS="$LIBS $STATIC_PREFIX/lib/libncursesw.a"
    elif [ -f "$STATIC_PREFIX/lib/libncurses.a" ]; then
        LIBS="$LIBS $STATIC_PREFIX/lib/libncurses.a"
    fi
    [ -f "$STATIC_PREFIX/lib/libtinfo.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libtinfo.a"
    [ -f "$STATIC_PREFIX/lib/libgmp.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libgmp.a"
    [ -f "$STATIC_PREFIX/lib/libqdbm.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libqdbm.a"
    [ -f "$STATIC_PREFIX/lib/liblmdb.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/liblmdb.a"
    
    # ICU libraries (order: io -> i18n -> uc -> data)
    [ -f "$STATIC_PREFIX/lib/libicuio.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libicuio.a"
    [ -f "$STATIC_PREFIX/lib/libicui18n.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libicui18n.a"
    [ -f "$STATIC_PREFIX/lib/libicuuc.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libicuuc.a"
    [ -f "$STATIC_PREFIX/lib/libicudata.a" ] && LIBS="$LIBS $STATIC_PREFIX/lib/libicudata.a"
    
    # End the link group
    LIBS="$LIBS -Wl,--end-group"
    
    # Note: Image libraries (freetype, png, jpeg, webp) are NOT included in LIBS
    # because the GD extension uses external system libgd which has its own
    # dynamic dependencies on these libraries.
    
    # System libs that must be linked dynamically
    LIBS="$LIBS -lm -ldl -lpthread -lstdc++"
    
    # Set pkg-config to use static mode
    export PKG_CONFIG="$STATIC_PREFIX/bin/pkg-config-static"
    export PKG_CONFIG_PATH="$STATIC_PREFIX/lib/pkgconfig:$STATIC_PREFIX/lib64/pkgconfig"
    
    echo "Using static libraries from $STATIC_PREFIX"
    echo "PKG_CONFIG=$PKG_CONFIG"
    echo "Static LIBS: $LIBS"
  fi
    
  if [[ "$PHP_VERSION" =~ 5.6|7.[0-4]|8.0 ]]; then
    EXTRA_CFLAGS="-fpermissive -Wno-deprecated -Wno-deprecated-declarations"
  else
    EXTRA_CFLAGS="-Wall -pedantic"
  fi
  EXTRA_CFLAGS="$EXTRA_CFLAGS -fsigned-char -fno-strict-aliasing -Wno-missing-field-initializers"

  DEB_HOST_MULTIARCH="$(dpkg-architecture -q DEB_HOST_MULTIARCH)"
  
  # Set ICU Version - check static ICU first, then system ICU
  if [ "$USE_STATIC_LIBS" = "yes" ] && [ -f "$STATIC_PREFIX/lib/pkgconfig/icu-uc.pc" ]; then
    # Use static ICU version
    ICU_VERSION="$(grep '^Version:' "$STATIC_PREFIX/lib/pkgconfig/icu-uc.pc" | sed 's/^Version: //' | cut -d. -f1)"
    echo "Using static ICU version: $ICU_VERSION"
  else
    ICU_VERSION="$(dpkg -s libicu-dev | sed -ne 's/^Version: \([0-9]\+\).*/\1/p')"  
  fi
  # ICU 75+ requires C++17 for features like std::u16string_view
  if [ -n "$ICU_VERSION" ] && [ "$ICU_VERSION" -ge 75 ] 2>/dev/null; then
    ICU_CXXFLAGS=-std=c++17
  else
    ICU_CXXFLAGS=-std=c++11
  fi
  [[ "$VERSION_ID" = "11" && "$PHP_VERSION" = "8.6" ]] && export CXXFLAGS="$CXXFLAGS -include unicode/localpointer.h"

  SED=$(command -v sed)

  export CFLAGS
  export CPPFLAGS
  export CXXFLAGS
  export LDFLAGS
  export EXTRA_CFLAGS
  export DEB_HOST_MULTIARCH
  export ICU_CXXFLAGS
  export SED
  
  # Export LIBS if using static build
  if [ -n "${LIBS:-}" ]; then
    export LIBS
  fi

  # Export inputs
  export INSTALL_ROOT
  export PHP_VERSION
  export SAPI

  # Pre-fetch stable release tarball to avoid php-build download flakiness.
  if [ "${stable:-}" = "true" ] && [ -n "${new_version:-}" ]; then
    tar_name="${new_version}.tar.gz"
    tar_path="/tmp/php-build/$tar_name"
    if [ ! -f "$tar_path" ]; then
      mkdir -p /tmp/php-build
      curl -sL "https://github.com/php/web-php-distributions/raw/master/$tar_name" -o "$tar_path"
    fi
  fi

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
    commit="$(basename "$(curl -sL https://api.github.com/repos/php/php-src/commits/"${branch:?}" | jq -r .commit.url)")"
    [ "$commit" = 'null' ] && exit 1;
    echo "$commit" | tee "$INSTALL_ROOT/etc/php/$PHP_VERSION/COMMIT" >/dev/null 2>&1
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

cleanup_environment() {
  rm -rf ~/php-build "${INSTALL_ROOT:?}" "${php_build_dir:?}"
  # Ensure php-build source tree is clean between SAPIs
  rm -rf /tmp/php-build 2>/dev/null || true
  mkdir -p ~/php-build "${INSTALL_ROOT:?}" "${php_build_dir:?}"
}


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
lto=-lto
FAKE_ROOT=/tmp
INSTALL_ROOT="$FAKE_ROOT"/debian/php"$PHP_VERSION"
conf_dir=/etc/php/"$PHP_VERSION"
mods_dir="$conf_dir"/mods-available
php_build_dir='/usr/local/share/php-build'
definitions="$php_build_dir/definitions"
default_options="$php_build_dir/default_configure_options"
default_ini="production"

# Set thread-safe options.
if [ "${BUILD:?}" = "zts" ]; then
  export PHP_PKG_SUFFIX=-zts
fi

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
  cleanup_environment
  get_version
  setup_phpbuild
  build_"${sapi}"
# Merge SAPI
elif [ "$action" = "merge" ]; then
  . scripts/build_partials/cleanup.sh
  . scripts/build_partials/extensions.sh
  . scripts/build_partials/package.sh
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
