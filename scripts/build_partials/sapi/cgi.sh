# Function to configure PHP cgi build.
configure_cgi() {
  # Copy the php-cgi binary to $INSTALL_ROOT/usr/lib/cgi-bin
  ln -sf /usr/bin/php-cgi"$PHP_VERSION" "${INSTALL_ROOT:?}"/usr/lib/cgi-bin/php"$PHP_VERSION"

  # Patch and copy php-cgi config to the INSTALL_ROOT.
  sed -i "s/PHP_VERSION/$PHP_VERSION/g" config/php-cgi.conf
  cp -fp config/php-cgi.conf "$INSTALL_ROOT"/etc/apache2/conf-available/php"$PHP_VERSION"-cgi.conf
}

# Function to build PHP cgi sapi.
build_cgi() {
  mkdir -p "${INSTALL_ROOT:?}" \
           "$INSTALL_ROOT"/etc/apache2/conf-available \
           "$INSTALL_ROOT"/usr/lib/cgi-bin \
           /usr/lib/cgi-bin
  chmod -R 777 "$INSTALL_ROOT"

  configure_sapi_options cgi
  build_php cgi
  configure_cgi
  package_sapi cgi
}
