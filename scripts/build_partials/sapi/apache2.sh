# Function to set APXS option to the php-build definition.
configure_apache2_options() {
  sed -i '1iconfigure_option "--with-apxs2" "/usr/bin/apxs2"' "${definitions:?}"/"$PHP_VERSION"
}

# Function to get major php version of apache module.
get_php_major_version() {
  if [[ "$PHP_VERSION" =~ 8.[0-9] ]]; then
    echo '';
  else
    echo ${PHP_VERSION/%.*};
  fi
}

# Function to configure PHP apache2 build.
configure_apache2() {
  # Suffix the PHP version to the apache php library.
  mv "${INSTALL_ROOT:?}"/usr/lib/apache2/modules/libphp*.so "$INSTALL_ROOT"/usr/lib/apache2/modules/libphp"$PHP_VERSION".so

  # Copy configuration files for mod-php to the INSTALL_ROOT.
  sed -i -e "s/PHP_VERSION/$PHP_VERSION/g" \
         -e "s/PHP_MAJOR/$(get_php_major_version)/g" config/php.load
  cp -fp config/php.conf "$INSTALL_ROOT"/etc/apache2/mods-available/php"$PHP_VERSION".conf
  cp -fp config/php.load "$INSTALL_ROOT"/etc/apache2/mods-available/php"$PHP_VERSION".load

  # Copy the minimal apache configuration to the INSTALL_ROOT.
  cp -fp config/default_apache "$INSTALL_ROOT"/etc/apache2/sites-available/000-default.conf

  # Remove any php binaries in the apache build.
  rm -rf "${INSTALL_ROOT:?}"/usr/bin

  # Remove libtool files and extensions.
  find "${INSTALL_ROOT:?}" -name '*.la' -name '*.so' -delete
}

# Function to build PHP apache2 sapi.
build_apache2() {
  mkdir -p "${INSTALL_ROOT:?}" \
           "$INSTALL_ROOT"/etc/apache2/mods-available \
           "$INSTALL_ROOT"/etc/apache2/sites-available \
           "$INSTALL_ROOT"/usr/lib/apache2/modules \
           /usr/local/ssl
  chmod -R 777 "$INSTALL_ROOT" \
               /etc/apache2/ \
               /usr/local/ssl \
               /usr/include/apache2 \
               /var/lib/apache2

  configure_apache2_options
  configure_sapi_options apache2
  build_php apache2
  configure_apache2
  package_sapi apache2
}
