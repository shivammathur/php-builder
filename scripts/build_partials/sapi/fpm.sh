# Function to configure PHP fpm build.
configure_fpm() {
  # Set FPM_CONF_DIR
  FPM_CONF_DIR="$INSTALL_ROOT"/"${conf_dir:?}"/fpm

  # Rename the php fpm pools config directory to pool.d and move to php fpm scan directory.
  mv "${INSTALL_ROOT:?}"/etc/php-fpm.d "$FPM_CONF_DIR"/pool.d
  mv "$INSTALL_ROOT"/etc/php-fpm.conf "$FPM_CONF_DIR"/php-fpm.conf

  # Patch PHP_VERSION, pid and log in php-fpm.conf
  sed -Ei -e "s|PHP_VERSION|$PHP_VERSION|g" \
          -e "s|pool.d|php/$PHP_VERSION/fpm/pool.d|" \
          -e "s|;pid.*|pid = /run/php/php$PHP_VERSION-fpm.pid|" \
          -e "s|;error_log.*|error_log = /var/log/php$PHP_VERSION-fpm.log|" "$FPM_CONF_DIR"/php-fpm.conf

  # Set fpm listener socket, owner, group and mode in pool.d/www.conf.
  sed -Ei -e "s|^listen = .*|listen = /run/php/php$PHP_VERSION-fpm.sock|" \
          -e 's|;listen.owner.*|listen.owner = www-data|' \
          -e 's|;listen.group.*|listen.group = www-data|' \
          -e 's|;listen.mode.*|listen.mode = 0660|' "$FPM_CONF_DIR"/pool.d/www.conf

  # Patch the config files.
  sed -i -e "s|PHP_VERSION|$PHP_VERSION|g" config/php-fpm.logrotate
  sed -i -e "s|PHP_VERSION|$PHP_VERSION|g" \
         -e "s|PHP_MAJOR|${PHP_VERSION/%.*}|g" config/php-fpm.conf
  sed -i -e "s|PHP_VERSION|$PHP_VERSION|g" \
         -e "s|NO_DOT|${PHP_VERSION/./}|g" config/php-fpm.service

  # Patch the scripts.
  sed -i -e "s|PHP_VERSION|$PHP_VERSION|g" scripts/php-fpm.init
  sed -i -e "s|PHP_VERSION|$PHP_VERSION|g" scripts/php-fpm-reopenlogs

  # Copy the config files to INSTALL_ROOT.
  cp -fp config/php-fpm.logrotate "$INSTALL_ROOT"/etc/logrotate.d/php"$PHP_VERSION"-fpm
  cp -fp config/php-fpm.service "$INSTALL_ROOT"/lib/systemd/system/php"$PHP_VERSION"-fpm.service
  cp -fp config/php-fpm.tmpfile "$INSTALL_ROOT"/usr/lib/tmpfiles.d/php"$PHP_VERSION"-fpm.conf
  cp -fp config/php-fpm.conf "$INSTALL_ROOT"/etc/apache2/conf-available/php"$PHP_VERSION"-fpm.conf

  # Copy the scripts to INSTALL_ROOT.
  cp -fp scripts/php-fpm.init "$INSTALL_ROOT"/etc/init.d/php"$PHP_VERSION"-fpm
  cp -fp scripts/php-fpm-reopenlogs "$INSTALL_ROOT"/usr/lib/php/php"$PHP_VERSION"-fpm-reopenlogs
  chmod -R a+x "$INSTALL_ROOT"/etc/init.d/php"$PHP_VERSION"-fpm

  # Remove the defaults.
  rm -f "$INSTALL_ROOT"/etc/init.d/php-fpm \
        "$INSTALL_ROOT"/etc/php-fpm.conf.default \
        "$FPM_CONF_DIR"/pool.d/www.conf.default

  # Remove all binaries on fpm build in bin as php-fpm is in sbin.
  rm -rf "${INSTALL_ROOT:?}"/usr/bin

  # Remove libtool files and extensions.
  find "${INSTALL_ROOT:?}" -name '*.la' -name '*.so' -delete
}

# Function to build PHP fpm sapi.
build_fpm() {
  mkdir -p "$INSTALL_ROOT" \
           "$INSTALL_ROOT"/lib/systemd/system \
           "$INSTALL_ROOT"/etc/apache2/conf-available \
           "$INSTALL_ROOT"/etc/logrotate.d \
           "$INSTALL_ROOT"/usr/lib/tmpfiles.d \
           /usr/local/ssl \
           /lib/systemd/system
  chmod -R 777 "$INSTALL_ROOT" \
               /usr/local/ssl

  configure_sapi_options fpm
  build_php fpm
  configure_fpm
  package_sapi fpm
}
