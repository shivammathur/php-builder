# Function to patch configure options and patch series files for php-build.
patch_config_file() {
  command=$1
  file=$2
  sed -Ei -e "s/^--/$command \"--/" \
          -e "s/^([0-9]+)/$command \"\1/" \
          -e "s/^($command.*)/\1\"/" "$file"
}

# Function to configure static library paths in definitions
configure_static_paths() {
  local def_file=$1
  STATIC_PREFIX="${STATIC_PREFIX:-/opt/static}"
  
  # Only modify if static build environment exists
  if [ ! -f "$STATIC_PREFIX/lib/libssl.a" ]; then
    return 0
  fi
  
  echo "Configuring definition for static library paths..."
  
  # Replace /usr paths with static prefix for libraries we have statically
  # Only replace specific known library paths, not all /usr references
  
  # Libraries to link statically - replace their paths
  if [ -f "$STATIC_PREFIX/lib/libbz2.a" ]; then
    sed -i "s|--with-bz2=shared,/usr|--with-bz2=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libz.a" ]; then
    sed -i "s|--with-zlib=/usr|--with-zlib=$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libssl.a" ]; then
    sed -i "s|--with-openssl-dir=/usr|--with-openssl-dir=$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libgmp.a" ]; then
    sed -i "s|--with-gmp=shared|--with-gmp=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libtidy.a" ]; then
    sed -i "s|--with-tidy=shared,/usr|--with-tidy=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libxslt.a" ]; then
    sed -i "s|--with-xsl=shared|--with-xsl=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libsqlite3.a" ]; then
    sed -i "s|--with-sqlite3=shared|--with-sqlite3=shared,$STATIC_PREFIX|g" "$def_file"
    sed -i "s|--with-pdo-sqlite=shared|--with-pdo-sqlite=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libpq.a" ]; then
    sed -i "s|--with-pgsql=shared,/usr|--with-pgsql=shared,$STATIC_PREFIX|g" "$def_file"
    sed -i "s|--with-pdo-pgsql=shared,/usr|--with-pdo-pgsql=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libldap.a" ]; then
    sed -i "s|--with-ldap=shared,/usr|--with-ldap=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libodbc.a" ]; then
    sed -i "s|--with-unixODBC=shared,/usr|--with-unixODBC=shared,$STATIC_PREFIX|g" "$def_file"
    sed -i "s|--with-pdo-odbc=shared,unixODBC,/usr|--with-pdo-odbc=shared,unixODBC,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libedit.a" ]; then
    sed -i "s|--with-libedit=shared|--with-libedit=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libnetsnmp.a" ]; then
    sed -i "s|--with-snmp=shared,/usr|--with-snmp=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libqdbm.a" ]; then
    sed -i "s|--with-qdbm=/usr|--with-qdbm=$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/liblmdb.a" ]; then
    sed -i "s|--with-lmdb=/usr|--with-lmdb=$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libdb.a" ] || [ -f "$STATIC_PREFIX/lib/libdb-4.8.a" ]; then
    sed -i "s|--with-db4=/usr|--with-db4=$STATIC_PREFIX|g" "$def_file"
  fi
  
  if [ -f "$STATIC_PREFIX/lib/libsybdb.a" ]; then
    sed -i "s|--with-pdo-dblib=shared,/usr|--with-pdo-dblib=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  # Use external GD with static paths if we have the libraries
  if [ -f "$STATIC_PREFIX/lib/libpng.a" ] && [ -f "$STATIC_PREFIX/lib/libjpeg.a" ]; then
    sed -i "s|--enable-gd=shared,/usr|--enable-gd=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  # PCRE - use static pcre2 if available
  if [ -f "$STATIC_PREFIX/lib/libpcre2-8.a" ]; then
    sed -i "s|--with-external-pcre|--with-external-pcre=$STATIC_PREFIX|g" "$def_file"
  fi
  
  # mhash - use static path if available
  if [ -f "$STATIC_PREFIX/lib/libmhash.a" ] || [ -f "$STATIC_PREFIX/lib/libcrypto.a" ]; then
    sed -i "s|--with-mhash=/usr|--with-mhash=$STATIC_PREFIX|g" "$def_file"
  fi
  
  # gettext - use static path if available
  # Note: gettext is system library, typically not statically linked
  
  # ffi - use static libffi if available
  if [ -f "$STATIC_PREFIX/lib/libffi.a" ]; then
    sed -i "s|--with-ffi=shared|--with-ffi=shared,$STATIC_PREFIX|g" "$def_file"
  fi
  
  echo "Static paths configured in definition file."
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
         -e "s|INSTALL|$install_command|" \
         -e "s|PHP_VERSION|$PHP_VERSION|" \
         -e "s|PHP_VERSION|$PHP_VERSION|" \
         -e "/PATCHES/{r./$patches_dir/~series" -e "d}" "$definitions"/"$PHP_VERSION"

  # Configure static library paths if static build environment exists
  configure_static_paths "$definitions"/"$PHP_VERSION"

  # Print the definition file.
  cat "$definitions"/"$PHP_VERSION"

  # Remove ~series file.
  rm "$patches_dir"/~series
}

# Function to install php-build.
setup_phpbuild() {
  echo "::group::php-build"
  rm -rf ~/php-build
  git clone -b debian https://github.com/shivammathur/php-build ~/php-build || {
    rm -rf ~/php-build
    git clone -b debian https://github.com/shivammathur/php-build ~/php-build
  }
  ~/php-build/install.sh
  configure_phpbuild
  echo "::endgroup::"
}
