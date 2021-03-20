configure_phpbuild() {
  sudo cp /usr/local/share/php-build/default_configure_options /usr/local/share/php-build/default_configure_options.bak
  if [ "$new_version" != "nightly" ]; then
    sudo cp "$action_dir"/config/definitions/stable /usr/local/share/php-build/definitions/"$PHP_VERSION"
    sudo sed -i "s/phpsrctag/$new_version/" /usr/local/share/php-build/definitions/"$PHP_VERSION"
    branch="$new_version"
  else
    sudo cp "$action_dir"/config/definitions/"$PHP_VERSION" /usr/local/share/php-build/definitions/
  fi
  sudo sed -i "s|PREFIX|$install_dir|" /usr/local/share/php-build/definitions/"$PHP_VERSION"
}

setup_phpbuild() {
  (
    cd ~ || exit
    git clone git://github.com/php-build/php-build
    cd php-build || exit
    sudo ./install.sh
    configure_phpbuild
  )
}

setup_pear() {
  sudo curl -fsSL --retry "$tries" -o /usr/local/ssl/cert.pem https://curl.haxx.se/ca/cacert.pem
  sudo curl -fsSL --retry "$tries" -O https://pear.php.net/go-pear.phar
  sudo chmod a+x scripts/install-pear.expect
  scripts/install-pear.expect "$install_dir"
  rm go-pear.phar
  sudo "$install_dir"/bin/pear config-set php_ini "$install_dir"/etc/php.ini system
  sudo "$install_dir"/bin/pear channel-update pear.php.net
}

setup_extensions() {
  for extension in amqp-1.11.0beta apcu igbinary memcache msgpack pcov sqlsrv pdo_sqlsrv xdebug; do
    yes '' | sudo "$install_dir"/bin/pecl install -f "$extension"
  done
  sudo bash scripts/install-ext.sh imagick extension Imagick/imagick master "$install_dir"
  sudo bash scripts/install-ext.sh memcached extension php-memcached-dev/php-memcached master "$install_dir"
  sudo bash scripts/install-ext.sh redis extension phpredis/phpredis develop "$install_dir" --enable-redis --enable-redis-igbinary --enable-redis-msgpack --enable-redis-zstd --enable-redis-lz4 --with-libzstd=/usr --with-liblz4=/usr
}

build_php() {
  export CFLAGS="-Wno-missing-field-initializers $CFLAGS"
  export CXXFLAGS="-Wno-missing-field-initializers $CXXFLAGS"
  if ! php-build -v -i production "$PHP_VERSION" "$install_dir"; then
    echo 'Failed to build PHP'
    exit 1
  fi
}

configure_apache_fpm_opts() {
  sudo sed -i "/cgi/d" /usr/local/share/php-build/default_configure_options
  sudo sed -i '1iconfigure_option "--with-apxs2" "/usr/bin/apxs2"' /usr/local/share/php-build/definitions/"$PHP_VERSION"
  echo "--enable-cgi" | sudo tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  echo "--enable-fpm" | sudo tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  echo "--with-fpm-user=www-data" | sudo tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  echo "--with-fpm-group=www-data" | sudo tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
}

configure_apache_fpm() {
  sudo ln -sv "$install_dir"/sbin/php-fpm "$install_dir"/bin/php-fpm
  sudo ln -sv "$install_dir"/bin/php-cgi "$install_dir"/usr/lib/cgi-bin/php"$PHP_VERSION"
  sudo mv "$install_dir"/etc/init.d/php-fpm "$install_dir"/etc/init.d/php"$PHP_VERSION"-fpm
  sudo mv "$install_dir"/usr/lib/apache2/modules/libphp.so "$install_dir"/usr/lib/apache2/modules/libphp"$PHP_VERSION".so
  sudo sed -Ei -e "s|^listen = .*|listen = /run/php/php$PHP_VERSION-fpm.sock|" -e 's|;listen.owner.*|listen.owner = www-data|' -e 's|;listen.group.*|listen.group = www-data|' -e 's|;listen.mode.*|listen.mode = 0660|' "$install_dir"/etc/php-fpm.d/www.conf
  sudo sed -i "s/PHP_MAJOR/${PHP_VERSION/%.*}/g" config/php-fpm.conf
  for file in default_nginx fpm.service php-cgi.conf php-fpm.conf php.load; do
    sudo sed -i "s/PHP_VERSION/$PHP_VERSION/g" config/"$file"
  done
  sudo sed -i "s/NO_DOT/${PHP_VERSION/./}/g" config/fpm.service
  sudo sed -i "s/PHP_VERSION/$PHP_VERSION/g" scripts/switch_sapi

  sudo cp -fp config/fpm.service "$install_dir"/etc/systemd/system/php"$PHP_VERSION"-fpm.service
  sudo cp -fp scripts/php-fpm-socket-helper scripts/switch_sapi "$install_dir"/bin/ && sudo chmod -R a+x "$install_dir"/bin
  sudo sed -Ei -e "s|;pid.*|pid = /run/php/php$PHP_VERSION-fpm.pid|" -e "s|;error_log.*|error_log = /var/log/php$PHP_VERSION-fpm.log|" "$install_dir"/etc/php-fpm.conf
  sudo cp -fp config/php.conf "$install_dir"/etc/apache2/mods-available/php"$PHP_VERSION".conf
  sudo cp -fp config/php.load "$install_dir"/etc/apache2/mods-available/php"$PHP_VERSION".load
  sudo cp -fp config/php-cgi.conf "$install_dir"/etc/apache2/conf-available/php"$PHP_VERSION"-cgi.conf
  sudo cp -fp config/php-fpm.conf "$install_dir"/etc/apache2/conf-available/php"$PHP_VERSION"-fpm.conf
  sudo cp -fp config/default_apache "$install_dir"/etc/apache2/sites-available/000-default.conf
  sudo cp -fp config/default_nginx "$install_dir"/etc/nginx/sites-available/default
}

build_apache_fpm() {
  sudo cp /usr/local/share/php-build/default_configure_options.bak /usr/local/share/php-build/default_configure_options
  sudo mkdir -p "$install_dir" "$install_dir"/"$(apxs -q SYSCONFDIR)"/mods-available "$install_dir"/"$(apxs -q SYSCONFDIR)"/sites-available "$install_dir"/etc/nginx/sites-available "$install_dir"/"$(apxs -q SYSCONFDIR)"/conf-available "$install_dir"/usr/lib/cgi-bin /usr/local/ssl /lib/systemd/system /usr/lib/cgi-bin
  sudo chmod -R 777 "$install_dir" /usr/local/php /usr/local/ssl /usr/include/apache2 /usr/lib/apache2 /etc/apache2/ /var/lib/apache2 /var/log/apache2
  basename "$(curl -sL https://api.github.com/repos/php/php-src/commits/"$branch" | jq -r .commit.url)" | sudo tee "$install_dir/COMMIT"
  export PHP_BUILD_APXS="/usr/bin/apxs2"
  configure_apache_fpm_opts
  build_php
  configure_apache_fpm
  sudo mv "$install_dir" "$install_dir-fpm"
}

build_embed() {
  sudo mkdir -p "$install_dir"
  sudo chmod -R 777 "$install_dir"
  sudo cp /usr/local/share/php-build/default_configure_options.bak /usr/local/share/php-build/default_configure_options
  sudo sed -i "/apxs2/d" /usr/local/share/php-build/definitions/"$PHP_VERSION" || true
  sudo sed -i "/fpm/d" /usr/local/share/php-build/default_configure_options || true
  sudo sed -i "/cgi/d" /usr/local/share/php-build/default_configure_options || true
  echo "--enable-embed=shared" | sudo tee -a /usr/local/share/php-build/default_configure_options >/dev/null 2>&1
  build_php
  sudo mv "$install_dir" "$install_dir-embed"
}

merge_sapi() {
  sudo mv "$install_dir-fpm" "$install_dir"
  sudo cp "$install_dir-embed/lib/libphp.so" "$install_dir/usr/lib/libphp$PHP_VERSION.so"
  sudo sed -i 's/php_sapis=" apache2handler cli fpm phpdbg cgi"/php_sapis=" apache2handler cli fpm phpdbg cgi embed"/' "$install_dir"/bin/php-config
  sudo cp -a "$install_dir-embed/include/php/sapi" "$install_dir/include/php"
}

configure_php() {
  sudo ln -sf "$install_dir"/bin/* /usr/bin/
  sudo ln -sf "$install_dir"/etc/php.ini /etc/php.ini
  sudo chmod 777 "$install_dir"/etc/php.ini
  (
    echo "date.timezone=UTC"
    echo "memory_limit=-1"
  ) >>"$install_dir"/etc/php.ini
  sudo cp -fp "$install_dir"/etc/init.d/php"$PHP_VERSION"-fpm /etc/init.d/
  sudo cp -fp "$install_dir"/etc/systemd/system/php"$PHP_VERSION"-fpm.service /lib/systemd/system/
  sudo cp -fp "$install_dir"/usr/lib/cgi-bin/php"$PHP_VERSION" /usr/lib/cgi-bin/
  sudo cp -fp "$install_dir"/usr/lib/apache2/modules/libphp"$PHP_VERSION".so /usr/lib/apache2/modules/
  sudo cp -fp "$install_dir"/etc/apache2/mods-available/php"$PHP_VERSION".load /etc/apache2/mods-available/php"$PHP_VERSION".load
  sudo cp -fp "$install_dir"/etc/apache2/mods-available/php"$PHP_VERSION".conf /etc/apache2/mods-available/
  sudo cp -fp "$install_dir"/etc/apache2/conf-available/php"$PHP_VERSION"-*.conf /etc/apache2/conf-available/
  sudo a2dismod php
  if ! sudo service php"$PHP_VERSION"-fpm start; then
    journalctl -xe
  fi
  setup_pear
  setup_extensions
}

package() {
  (
    export PATH="$HOME/.linuxbrew/bin:$PATH"
    echo "export PATH=$HOME/.linuxbrew/bin:\$PATH" >> "$GITHUB_ENV"
    brew install zstd >/dev/null 2>&1 && zstd -V
    cd "$install_dir"/.. || exit
    sudo XZ_OPT=-e9 tar cfJ php_"$PHP_VERSION"+ubuntu"$release".tar.xz "$PHP_VERSION"
    sudo tar cf - "$PHP_VERSION" | zstd -22 -T0 --ultra > php_"$PHP_VERSION"+ubuntu"$release".tar.zst
  )
}

check_stable() {
  if [[ "$GITHUB_MESSAGE" != *build-all* ]]; then
    if [ "$new_version" = "$existing_version" ]; then
      (
        sudo mkdir -p "$install_dir"
        cd "$install_dir"/.. || exit
        sudo curl -fSL --retry "$tries" -O "$github"/php_"$PHP_VERSION"+ubuntu"$release".tar.xz
        sudo curl -fSL --retry "$tries" -O "$github"/php_"$PHP_VERSION"+ubuntu"$release".tar.zst
        ls -la
      )
      echo "$new_version" exists
      exit 0
    fi
  fi
  if [ "$new_version" = "" ]; then
    new_version='nightly'
  fi
}

release=$(lsb_release -r -s)
install_dir=/usr/local/php/"$PHP_VERSION"
action_dir=$(pwd)
tries=10
branch=master
github="https://github.com/${GITHUB_REPOSITORY:?}/releases/download/builds"
existing_version=$(curl -sL "$github"/php"$PHP_VERSION".log)
new_version=$(curl -sL https://www.php.net/releases/feed.php | grep -Po -m 1 "php-($PHP_VERSION.[0-9]+)" | head -n 1)
check_stable
setup_phpbuild
build_embed
build_apache_fpm
merge_sapi
configure_php
package
